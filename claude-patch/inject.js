// MyClaude — ручка высоты поля ввода Claude Desktop и команды снаружи.
//
// Файл кладётся в ~/Library/Application Support/MyClaude/inject.js; лоадер из
// patch-claude.mjs выполняет его через executeJavaScript в КАЖДОЙ странице при
// dom-ready и заново при каждом изменении файла. Отсюда три требования:
//   1. никаких модулей и импортов — это обычный скрипт в контексте страницы;
//   2. идемпотентность: скрипт сам снимает прошлый экземпляр (window.__myclaude.dispose);
//   3. на чужих страницах (file://…/main_window, логин) он обязан тихо ничего не делать.
//
// Что делает: над полем ввода рисует едва заметную полоску. Потянул — меняешь
// высоту, клик — свернуть/вернуть, двойной клик — во всю высоту окна. Плюс
// команды из Hammerspoon (событие window "myclaude-command"): collapse, expand,
// cashout, scroll. И сокращает время под сообщениями («3 minutes ago» → «3 min
// ago»).
//
// Логика ступеней, порогов и кликов перенесена из донора ElvisOS
// (~/_ElvisProjects/ElvisOS/Resources/claude-chat-cleaner-inject.js, разделы
// «Ручка высоты поля ввода» и ниже). Донорские пояснения к неочевидным местам
// сохранены — они объясняют, почему числа именно такие.
//
// НЕ перенесено намеренно: очередь сообщений, подъём выше потолка (over-top),
// сворачивание после отправки, «две секунды на стоп», автопрокрутка, боковая
// панель, шрифты.
"use strict";
(() => {
  const VERSION = "wf3-a3-3";

  // ---- 0. Снятие прошлого экземпляра -------------------------------------
  // Сначала штатный путь, потом реестр уборки: даже упавшая на середине
  // установка оставляет после себя готовый список отмен, и следующий инжект
  // начинает с чистого листа (приём донора).
  try { window.__myclaude?.dispose?.(); } catch {}
  const REGISTRY_KEY = "__myclaudeUndo";
  const pendingUndo = window[REGISTRY_KEY];
  if (Array.isArray(pendingUndo)) {
    for (const undo of pendingUndo.splice(0).reverse()) { try { undo(); } catch {} }
  }
  const undoList = [];
  window[REGISTRY_KEY] = undoList;
  const track = undo => { undoList.push(undo); };
  // Подписка и её снятие пишутся одной строкой — разъехаться они не могут.
  const on = (target, type, handler, options) => {
    target.addEventListener(type, handler, options);
    track(() => target.removeEventListener(type, handler, options));
  };

  // ---- 1. Постоянные ------------------------------------------------------
  const HANDLE_ID = "myclaude-input-handle";
  const STYLE_ID = "myclaude-input-handle-style";
  const EDITOR_ROOT_ATTRIBUTE = "data-myclaude-editor-root";
  const EDITOR_ATTRIBUTE = "data-myclaude-editor";
  const BLOCK_ATTRIBUTE = "data-myclaude-composer-block";
  const HEIGHT_VARIABLE = "--myclaude-input-height";
  // Высота и ступень — в sessionStorage. Отступление от донора (у него высота в
  // localStorage) намеренное: профиль у всех окон Claude общий, и новое окно
  // поднималось бы уже растянутым. sessionStorage у каждого окна свой и
  // переживает перезагрузку страницы.
  const HEIGHT_STORAGE_KEY = "myclaude-input-height-v1";
  const STAGE_STORAGE_KEY = "myclaude-input-stage-v1";
  // «Обкэшить» кладёт перенос в localStorage: забирает его ДРУГОЕ окно (⌘N).
  const CASHOUT_KEY = "myclaude-cashout";

  // Зона захвата полоски — как у донора. Заметность даёт не зона (она
  // прозрачная), а сама линия в 2 точки, поэтому «полоска едва заметная» от
  // высокой зоны не толстеет, зато мышью в неё попадаешь. Полоска сидит верхом
  // на кромке рамки, то есть выше кромки её ровно половина — донорские 9 точек,
  // больше не поднимаемся.
  const HANDLE_HEIGHT = 18;
  // Полоска узкая и строго по центру поля (донор): во всю ширину рамки её зона
  // захвата накрывает кнопки и параметры по краям поля, и Элвис назвал такую
  // полоску «широченной». Сотни точек хватает, чтобы схватить её мышью.
  const HANDLE_NARROW_WIDTH = 96;
  // Отступ свёрнутой полоски от краёв рамки: её собственное скругление плюс
  // пара точек, но не меньше этого.
  const HANDLE_MIN_INSET = 10;
  // Потолок высоты поля, запасное значение: плитка окна отступает от края на 9
  // точек, титульная полоса .epitaxy-titlebar занимает 32. Меряем саму полосу —
  // на части экранов Claude её просто нет, и константа врала бы.
  const SAFE_TOP_INSET = 42;
  const MIN_HEIGHT = 38;
  // Обычная высота поля, пока её ни разу не удалось замерить (поле свёрнуто с
  // самого открытия окна). Только запасное значение.
  const NATURAL_FALLBACK = 96;
  // Насколько ниже минимума надо протянуть, чтобы поле свернулось: случайный
  // перелёт на пару точек сворачивать не должен.
  const COLLAPSE_DRAG_SLACK = 44;
  // Гистерезис между «обычной высотой» и «растянуто»: вверх ступень берётся с
  // запасом, вниз — по самой обычной высоте, поэтому дрожь руки на границе не
  // перещёлкивает ступень туда-сюда.
  const STAGE_DRAG_SLACK = 26;
  // Двойной клик метит чуть НИЖЕ упора: недобор на несколько точек глазами не
  // виден, а перелёт приходится подтягивать обратно — вот это уже видно как
  // лесенка.
  const CEILING_UNDERSHOOT = 8;
  // Насколько грубо надо промахнуться, чтобы разрешить второй — и последний —
  // шаг разворота. Порог заметно больше недобора: иначе второй шаг срабатывал
  // бы всегда и лесенка вернулась бы.
  const CEILING_RETRY_GAP = 28;
  // Прибавка высоты, ушедшая не вверх, а в пустоту. Больше этого — значит
  // контейнер Claude верх поля дальше не пустил, и замеренный пол пора
  // запомнить: в следующий раз целимся сразу в него.
  const CEILING_WASTE_SLACK = 3;
  // Сколько места сверх обычной высоты обязана оставлять полю отметка, чтобы
  // считаться потолком. Меньше — это не потолок, а промах замера: низ шапки,
  // найденный вплотную к полю, или пол, записанный по рамке, которая и не
  // думала двигаться. Целиться в такую отметку — значит не делать ничего, и
  // именно так двойной клик и умирал в главном окне.
  const CEILING_MIN_ROOM = 80;
  // Сдвиг в пределах этого допуска — ещё клик, а не перетаскивание.
  const CLICK_SLACK = 4;
  // Одиночный клик ждёт возможного второго: без задержки каждый двойной клик
  // успевал бы сначала сделать лишний шаг по лестнице.
  const CLICK_STEP_DELAY = 260;
  // Свёрнутая полоска уже рамки на пятую часть и стоит по центру: во всю ширину
  // её зона захвата накрывала бы строку модели под ней.
  const COLLAPSED_WIDTH_SCALE = 0.8;
  // Лестница ровно из трёх положений: полоска → обычная высота → растянуто.
  const STAGE_COLLAPSED = 0;
  const STAGE_NORMAL = 1;
  const STAGE_STRETCHED = 2;
  // Полный проход раскладки — это обход документа с замерами, то есть
  // принудительный reflow. Пока Claude печатает ответ, мутаций сотни в секунду,
  // поэтому проход не чаще раза в 250 мс плюс фильтр affectsComposer.
  const LAYOUT_MIN_GAP = 250;
  // Страховочный проход: в спрятанном или перекрытом окне macOS не даёт кадров
  // вовсе, и requestAnimationFrame молчит — тогда доводим руками.
  const HEARTBEAT_MS = 500;
  // Сколько ждём появления поля ввода, прежде чем признать страницу чужой.
  const GIVE_UP_MS = 60000;
  const CASHOUT_FRESH_MS = 90000;
  const CASHOUT_TICK_MS = 300;
  // Ниже этой высоты сосед рамки — пустая обёртка, а не строка модели.
  const MODEL_ROW_MIN_HEIGHT = 8;
  // Признак рамки поля — скругление: у Claude Code это 10px, у контейнеров
  // вокруг скруглений нет вовсе.
  const FRAME_RADIUS = 6;
  const FRAME_RISE = 140;
  const POPUP_MIN_Z = 20;
  const BOTTOM_SAFE_INSET = 2;
  // Выступ меньше этого — дрожь замера, а не уехавший за край окна низ.
  const BOTTOM_TRIM_SLACK = 1;
  const EDITOR_SELECTOR = '.ProseMirror[contenteditable],[contenteditable="true"],textarea';
  const COLLAPSED_BLOCK_SELECTOR = `[${BLOCK_ATTRIBUTE}="collapsed"]`;
  // Роли — самое устойчивое, что есть у меню и модалок: классы Claude
  // перегенерирует каждый релиз, а role держит доступность.
  const OVERLAY_SELECTOR = '[role="menu"],[role="listbox"],[role="dialog"]';
  // Последний ответ ассистента для «Обкэшить». Селекторов три: разметка чата
  // Claude Code и обычного claude.ai различается, и какой из них жив сегодня —
  // видно только в живом окне.
  // '[aria-label^="Message"]' цепляет заодно строку действий под ответом
  // ('[aria-label="Message actions"]' с «3 minutes ago») и вложенные куски
  // одного ответа — отсев и выбор внешнего узла живут в lastAnswerText.
  const ANSWER_SELECTOR = '[data-testid="assistant-message"],[aria-label^="Message"],div.font-claude-response';
  // Приметы ленты разговора: если хоть одна внутри кандидата в блок ввода —
  // кандидат не тот, и сворачивать его нельзя.
  const TRANSCRIPT_SELECTOR = '.epitaxy-transcript-width,[data-testid="assistant-message"],.font-claude-response,[data-testid="epitaxy-virtual-transcript"]';
  // Приметы того, что разговор уже идёт. Список широкий намеренно: разметка
  // чата в claude.ai и в окне Claude Code разная, и в сборке 1.40609.1 живой
  // оказалась не всякая — `.epitaxy-transcript-width` там нет вовсе (замер
  // оркестратора), из-за чего разговор считался пустым чатом. Ленты
  // `[data-testid="epitaxy-virtual-transcript"]` в списке нет намеренно: она
  // висит в окне и до первого сообщения, и пустой чат перестал бы быть пустым.
  const CHAT_STARTED_SELECTOR = '.font-claude-response,[data-user-message-bubble],' +
    '[data-testid="assistant-message"],.epitaxy-user-turn,.epitaxy-transcript-width,' +
    '[aria-label="Message actions"]';

  const now = () => (typeof performance?.now === "function" ? performance.now() : Date.now());

  // ---- 2. Хранилище -------------------------------------------------------
  const readStoredHeight = () => {
    try {
      const stored = Number(sessionStorage.getItem(HEIGHT_STORAGE_KEY));
      return Number.isFinite(stored) && stored >= MIN_HEIGHT ? stored : null;
    } catch { return null; }
  };
  const storeHeight = value => {
    try {
      if (value == null) sessionStorage.removeItem(HEIGHT_STORAGE_KEY);
      else sessionStorage.setItem(HEIGHT_STORAGE_KEY, String(Math.round(value)));
    } catch {}
  };
  const readStoredStage = () => {
    try {
      const raw = sessionStorage.getItem(STAGE_STORAGE_KEY);
      const stage = Number(raw);
      if (raw != null && Number.isInteger(stage) && stage >= STAGE_COLLAPSED && stage <= STAGE_STRETCHED) return stage;
    } catch {}
    return null;
  };
  const storeStage = value => {
    try { sessionStorage.setItem(STAGE_STORAGE_KEY, String(value)); } catch {}
  };

  // Стартовая ступень. Ступень «растянуто» без сохранённой высоты невозможна,
  // поэтому она откатывается к обычной (донор).
  const initialHeight = readStoredHeight();
  const storedStage = readStoredStage();
  const initialStage = (() => {
    if (storedStage === STAGE_STRETCHED || storedStage == null) return initialHeight == null ? STAGE_NORMAL : STAGE_STRETCHED;
    return storedStage;
  })();
  // Откат записываем сразу. Иначе он живёт только в памяти: setStage в ту же
  // ступень выходит на равенстве и хранилище не поправит, и в сессии остаётся
  // «растянуто», которому поле уже не соответствует. Заодно убираем негодную
  // высоту — из-за неё откат и случился.
  storeStage(initialStage);
  if (storedStage === STAGE_STRETCHED && initialStage !== STAGE_STRETCHED) storeHeight(null);

  const state = {
    alive: true,
    watching: true,
    editorFound: false,
    cssOk: false,
    cssViolations: [],
    editor: null,
    editorRoot: null,
    shell: null,
    composerBlock: null,
    // Прямой ребёнок блока ввода, внутри которого лежит рамка поля, и строка
    // модели под ним: сворачиваем всё до рамки включительно, строку оставляем.
    frameChild: null,
    modelRow: null,
    collapsedNodes: [],
    stage: initialStage,
    height: initialStage === STAGE_STRETCHED ? initialHeight : null,
    // Последняя высота, которую натянули рукой. Живёт в памяти окна и переживает
    // уход на другие ступени: без неё возврат в «растянуто» терял бы размер.
    lastStretched: initialHeight,
    // Высота, на которой верх поля перестаёт подниматься; живёт до выхода из
    // растянутого вида.
    ceiling: null,
    // Замеренный упор самого контейнера вместе с приметой вида окна: выше этой
    // отметки он верх поля не пускает, а в другом размере замер не годится.
    ceilingFloor: null,
    stretchSteps: 0,
    natural: null,
    handleCovered: false,
    dragging: false,
    moved: false,
    startY: 0,
    startHeight: 0,
    dragNatural: NATURAL_FALLBACK,
    clickTimer: 0,
    cashoutTimer: 0,
    giveUpTimer: 0,
    // Прокрутка ленты: кто едет, до какой высоты доехали и сколько доборов
    // осталось. Кадр и таймер добора снимаются вместе, одним clearScrollWatch.
    scroller: null,
    scrollRaf: 0,
    scrollTimer: 0,
    scrollSteps: 0,
    scrollSeen: 0,
    scrollRuns: 0,
    // Короткое время под сообщениями: за кем смотрим и когда был последний
    // проход (троттлинг, см. TIME_MIN_GAP).
    timeTarget: null,
    timeTimer: 0,
    timeAt: 0,
    timeRuns: 0,
    scheduled: false,
    rafId: 0,
    layoutTimer: 0,
    layoutAt: 0,
    layoutRuns: 0,
    mutationBatches: 0,
    mutationSkipped: 0,
  };

  // ---- 3. Сироты прошлых установок ---------------------------------------
  // Реестра у них могло и не быть (падение до его заполнения), а в окне они уже
  // висят. Сносим по id и по своим атрибутам — иначе полосок в окне остаётся
  // столько же, сколько было падений.
  for (const id of [STYLE_ID, HANDLE_ID]) {
    for (const orphan of document.querySelectorAll(`#${id}`)) orphan.remove();
  }
  for (const node of document.querySelectorAll(`[${EDITOR_ROOT_ATTRIBUTE}],[${EDITOR_ATTRIBUTE}],[${BLOCK_ATTRIBUTE}]`)) {
    node.removeAttribute(EDITOR_ROOT_ATTRIBUTE);
    node.removeAttribute(EDITOR_ATTRIBUTE);
    node.removeAttribute(BLOCK_ATTRIBUTE);
    try { node.style.removeProperty(HEIGHT_VARIABLE); } catch {}
  }

  // ---- 4. Стили и сама полоска -------------------------------------------
  const RULES = [
    // Полоска висит поверх всего и позиционируется координатами: рамка поля
    // живёт в чужом дереве, и вставлять в него свой узел — лишний риск.
    `#${HANDLE_ID}{position:fixed;display:none;align-items:center;justify-content:center;height:${HANDLE_HEIGHT}px;padding:0;border:0;background:transparent;cursor:ns-resize;user-select:none;-webkit-user-select:none;touch-action:none;z-index:2147483646}`,
    // Едва заметная линия в цвет текста: 0.10 — слово Элвиса «полоска едва
    // заметная, при наведении видимая».
    `#${HANDLE_ID}>span{display:block;width:100%;height:2px;border-radius:999px;background:currentColor;opacity:.10;pointer-events:none;transition:height 120ms ease,opacity 120ms ease}`,
    `#${HANDLE_ID}:hover>span,#${HANDLE_ID}[data-dragging="true"]>span{height:3px;opacity:.45}`,
    // Свёрнутое поле чаще возвращают кликом, поэтому курсор там не «тянуть», а
    // обычная рука, и сама полоска заметнее. Тяга вверх при этом тоже работает.
    `#${HANDLE_ID}[data-collapsed="true"]{cursor:pointer}`,
    `#${HANDLE_ID}[data-collapsed="true"]>span{height:3px;opacity:.30}`,
    `#${HANDLE_ID}[data-collapsed="true"]:hover>span{height:4px;opacity:.45}`,
    // Схлопнутый узел: не display:none, а полоска нулевой высоты — редактор
    // остаётся живым, черновик и фокус переживают сворачивание.
    `[${BLOCK_ATTRIBUTE}="collapsed"]{height:0 !important;min-height:0 !important;max-height:0 !important;padding-top:0 !important;padding-bottom:0 !important;margin-top:0 !important;margin-bottom:0 !important;overflow:hidden !important;opacity:0 !important;pointer-events:none !important}`,
    // Растягиваем скролл-контейнер, а сам редактор освобождаем от его
    // собственного максимума (в Claude Code это max-h-[218px] на .tiptap) —
    // иначе текст остаётся полосой сверху. Прокрутка одна: у контейнера,
    // редактор внутри не скроллит, поэтому вторая полоса не появляется.
    `[${EDITOR_ROOT_ATTRIBUTE}="true"]{box-sizing:border-box !important;height:var(${HEIGHT_VARIABLE}) !important;min-height:var(${HEIGHT_VARIABLE}) !important;max-height:var(${HEIGHT_VARIABLE}) !important;overflow-y:auto !important}`,
    `[${EDITOR_ROOT_ATTRIBUTE}="true"] [${EDITOR_ATTRIBUTE}="true"],[${EDITOR_ROOT_ATTRIBUTE}="true"][${EDITOR_ATTRIBUTE}="true"]{max-height:none !important;min-height:100% !important;height:auto !important;overflow-y:visible !important}`,
  ];

  const style = document.createElement("style");
  style.id = STYLE_ID;
  style.textContent = RULES.join("\n");
  (document.head ?? document.documentElement).appendChild(style);
  track(() => style.remove());
  // CSP страницы может не пустить наш <style>. Молча это выглядит как
  // «полоски нет», поэтому проверяем сразу и отдаём наружу через
  // __myclaude.status(): резерв — перенести правила в claude.css, его лоадер
  // вставляет как cssOrigin:"user" и CSP страницы его не касается.
  state.cssOk = (() => {
    try { return (style.sheet?.cssRules?.length ?? 0) > 0; } catch { return false; }
  })();
  if (!state.cssOk) {
    try { console.warn("[MyClaude] стили ручки не применились (CSP?) — правила надо перенести в claude.css"); } catch {}
  }
  on(document, "securitypolicyviolation", event => {
    if (state.cssViolations.length >= 5) return;
    state.cssViolations.push({
      directive: String(event?.effectiveDirective ?? ""),
      blocked: String(event?.blockedURI ?? "").slice(0, 120),
    });
  });

  const handle = document.createElement("div");
  handle.id = HANDLE_ID;
  handle.setAttribute("role", "separator");
  handle.setAttribute("aria-orientation", "horizontal");
  handle.setAttribute("aria-label", "Изменить высоту поля ввода");
  handle.title = "Потяни вверх или вниз\nКлик свернёт, двойной — во всю высоту";
  // Кнопки на полоске нет: стрелка получалась крошечной, сидела у правого края
  // и попасть в неё было нечем. Свёрнутое поле разворачивает одиночный клик по
  // любому месту полоски.
  handle.appendChild(document.createElement("span"));
  (document.body ?? document.documentElement).appendChild(handle);
  track(() => handle.remove());
  // Резерв на случай, когда CSP страницы не пустила наш <style>: положение
  // полоски и саму линию ставим напрямую через CSSOM — его CSP не касается
  // (запрещён бывает <style> и атрибут style, а не element.style.setProperty).
  // Без этого незастилованная полоска встала бы обычным блоком в поток страницы.
  // Сворачивание и высота этим не спасаются: их правила переносит в claude.css
  // оркестратор.
  if (!state.cssOk) {
    const box = {
      position: "fixed", display: "none", "align-items": "center", "justify-content": "center",
      height: `${HANDLE_HEIGHT}px`, padding: "0", border: "0", background: "transparent",
      cursor: "ns-resize", "user-select": "none", "touch-action": "none", "z-index": "2147483646",
    };
    const line = {
      display: "block", width: "100%", height: "2px", "border-radius": "999px",
      background: "currentColor", opacity: ".10", "pointer-events": "none",
    };
    for (const [name, value] of Object.entries(box)) handle.style.setProperty(name, value);
    const span = handle.firstElementChild;
    if (span) for (const [name, value] of Object.entries(line)) span.style.setProperty(name, value);
  }

  // ---- 5. Поиск поля ввода ------------------------------------------------
  // Свёрнутый блок ввода схлопнут в ноль и прижат к нижнему краю окна: у
  // редактора внутри геометрия перестаёт быть «видимой», хотя сам он живой и
  // держит черновик. Без этой поблажки поле терялось, свёрнутость снималась,
  // блок разворачивался — и на следующем кадре всё повторялось: низ окна
  // начинал мигать с частотой перерисовки.
  const visibleEditor = element => {
    const computed = getComputedStyle(element);
    if (element.disabled || computed.display === "none" || computed.visibility === "hidden") return false;
    if (element.closest(COLLAPSED_BLOCK_SELECTOR)) return true;
    const rect = element.getBoundingClientRect();
    return rect.width >= 200 && rect.bottom > 0 && rect.top < innerHeight;
  };
  // Кэш держится не на счётчике мутаций (во время набора дерево меняется каждую
  // букву), а на проверке самого ответа: прежнее поле всё ещё в документе, всё
  // ещё видно и всё ещё .ProseMirror. Держимся только за .ProseMirror — textarea
  // выигрывает развёртку лишь когда composer'а нет вовсе. И считаем ЖИВЫЕ
  // .ProseMirror: их число изменилось — значит рядом появился ещё один, и
  // выбирать надо заново (React пересоздаёт composer при смене чата).
  let editorHit = null;
  let editorSeen = -1;
  const findEditor = () => {
    const live = document.getElementsByClassName("ProseMirror");
    if (editorHit?.isConnected && live.length === editorSeen &&
        editorHit.classList.contains("ProseMirror") && visibleEditor(editorHit)) {
      return editorHit;
    }
    editorSeen = live.length;
    editorHit = [...document.querySelectorAll(EDITOR_SELECTOR)]
      .filter(visibleEditor)
      .map(element => ({ element, score: (element.matches(".ProseMirror") ? 100000 : 0) + element.getBoundingClientRect().bottom * 10 }))
      .sort((left, right) => right.score - left.score)[0]?.element ?? null;
    return editorHit;
  };
  // Скролл-контейнер редактора: высотой управляет он, поэтому кнопки composer
  // остаются на месте, а текст внутри прокручивается штатно.
  const findEditorRoot = editor => {
    let element = editor.parentElement;
    for (let depth = 0; element && depth < 5; depth += 1, element = element.parentElement) {
      const computed = getComputedStyle(element);
      if (computed.overflowY === "auto" || computed.overflowY === "scroll") return element;
    }
    return editor.parentElement;
  };
  // Внешняя рамка composer: полоску ставим на её верхнюю границу — над строкой
  // вложений, а не между вложениями и текстом. В нынешней сборке рамка зовётся
  // .epitaxy-prompt (замер оркестратора), и если она на месте — берём её. Если
  // класс переименуют, остаётся разбор донора по геометрии: признак рамки —
  // скругление, у контейнеров вокруг его нет вовсе. Скруглённый предок не
  // считается рамкой, если поднялся над полем выше, чем помещается строка
  // вложений: это уже разметка страницы.
  const findShell = (editor, editorRoot) => {
    const named = editor?.closest?.(".epitaxy-prompt");
    if (named?.isConnected) return named;
    const start = editorRoot ?? editor;
    const base = start.getBoundingClientRect();
    let shell = start;
    let frame = null;
    let element = start.parentElement;
    for (let depth = 0; element && depth < 12; depth += 1, element = element.parentElement) {
      const rect = element.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) continue;  // обёртки display:contents
      if (rect.width > base.width + 220 || rect.height > base.height + 260) break;
      if (rect.bottom < base.bottom - 40) break;
      shell = element;
      const radius = parseFloat(getComputedStyle(element).borderTopLeftRadius) || 0;
      if (radius >= FRAME_RADIUS && rect.top >= base.top - FRAME_RISE) frame = element;
    }
    return frame ?? shell;
  };
  // Блок ввода целиком: рамка поля, плашка проекта и строка модели. Сворачиваем
  // не его — иначе вместе с полем уезжает строка модели и effort, а она нужна
  // на виду всегда.
  //
  // Донор искал блок по .epitaxy-composer-width. В сборке 1.40609.1 такого
  // класса уже нет: боковые поля задаёт `ps-[var(--chat-gutter…)]` (тот же
  // контейнер, что известен как group/approval-dock). Поэтому селектора два, а
  // третьим — разбор по дереву: предок рамки, у которого под ней есть ещё один
  // видимый и невысокий сосед. Глубина ограничена: выше начинается лента
  // разговора, и схлопнуть её было бы катастрофой.
  const findComposerBlock = (editor, shell) => {
    const named = editor?.closest?.(".epitaxy-composer-width");
    if (named?.isConnected) return named;
    const gutter = editor?.closest?.('[class*="ps-[var(--chat-gutter"]');
    // Тот же класс носит и широкая обёртка вместе с лентой разговора. Свернуть
    // её значило бы спрятать весь разговор, поэтому кандидата проверяем дважды:
    // по содержимому (нет ли внутри ленты) и по росту.
    if (gutter?.isConnected && gutter !== shell &&
        !gutter.querySelector(TRANSCRIPT_SELECTOR) &&
        gutter.getBoundingClientRect().height <= innerHeight * 0.6) return gutter;
    let child = shell ?? editor;
    for (let depth = 0; child?.parentElement && depth < 3; depth += 1, child = child.parentElement) {
      const block = child.parentElement;
      for (let node = child.nextElementSibling; node; node = node.nextElementSibling) {
        const rect = node.getBoundingClientRect();
        if (rect.height >= MODEL_ROW_MIN_HEIGHT && rect.height <= 200) return block;
      }
    }
    return shell ?? null;
  };

  // Строка модели — единственный обычный сосед рамки ввода снизу внутри блока.
  // Ищем не селектором, а обходом соседей: рамкой может оказаться не прямой
  // ребёнок блока, а .sr-only и пустые обёртки надо пропускать по факту, а не по
  // имени класса. Не нашли — возвращаем null, и всё откатывается к прежнему
  // поведению «схлопнуть одну рамку поля».
  const findComposerParts = (block, shell) => {
    if (!block?.isConnected || !shell?.isConnected) return null;
    if (shell === block || !block.contains(shell)) return null;
    let frameChild = shell;
    while (frameChild && frameChild.parentElement !== block) frameChild = frameChild.parentElement;
    if (!frameChild) return null;
    for (let node = frameChild.nextElementSibling; node; node = node.nextElementSibling) {
      if (node.classList.contains("sr-only") || node.getAttribute("aria-hidden") === "true") continue;
      const computed = getComputedStyle(node);
      if (computed.display === "none" || computed.visibility === "hidden") continue;
      // Высотой отсеиваем пустые обёртки: строка модели место занимает, а
      // технический div между рамкой и ней — нет.
      if (node.getBoundingClientRect().height < MODEL_ROW_MIN_HEIGHT) continue;
      return { frameChild, modelRow: node };
    }
    return null;
  };

  // ---- 6. Сворачивание ----------------------------------------------------
  // Что именно схлопывать: рамка поля и всё, что стоит над ней (плашка проекта,
  // вложения, строка окружения). Строка модели идёт после рамки и в список не
  // попадает — она и остаётся видимой.
  const collapseTargets = () => {
    const block = state.composerBlock;
    if (!block?.isConnected) return [];
    // Блок целиком не схлопываем ни при каких обстоятельствах: вместе с ним
    // уезжает строка модели («Auto · Opus 5 · Max»), низ окна превращается в
    // чёрную полосу, и вернуть поле мышью становится нечем. Разбор низа
    // composer не удался — сворачиваем одну рамку поля, а если и её нет, не
    // сворачиваем вовсе: открытое поле лучше слепого окна.
    if (!state.frameChild?.isConnected || !state.modelRow?.isConnected) {
      const shell = state.shell;
      return shell?.isConnected && block.contains(shell) && shell !== block ? [shell] : [];
    }
    const targets = [];
    for (let node = block.firstElementChild; node; node = node.nextElementSibling) {
      targets.push(node);
      if (node === state.frameChild) return targets;
    }
    const shell = state.shell;
    return shell?.isConnected && block.contains(shell) && shell !== block ? [shell] : [];
  };

  const clearCollapsedNodes = () => {
    for (const node of state.collapsedNodes) {
      if (node.isConnected) node.removeAttribute(BLOCK_ATTRIBUTE);
    }
    state.collapsedNodes = [];
  };

  const applyCollapse = () => {
    const collapsed = state.stage === STAGE_COLLAPSED;
    const next = collapsed ? collapseTargets() : [];
    // Сворачивать нечего: в свёрнутой ступени не залипаем, иначе полоска
    // рисовалась бы поверх открытого поля и врала о состоянии.
    if (collapsed && next.length === 0) {
      clearCollapsedNodes();
      state.stage = STAGE_NORMAL;
      storeStage(STAGE_NORMAL);
      handle.dataset.collapsed = "false";
      return;
    }
    for (const node of state.collapsedNodes) {
      if (node.isConnected && !next.includes(node)) node.removeAttribute(BLOCK_ATTRIBUTE);
    }
    for (const node of next) node.setAttribute(BLOCK_ATTRIBUTE, "collapsed");
    state.collapsedNodes = next;
    handle.dataset.collapsed = collapsed ? "true" : "false";
    handle.setAttribute("aria-label", collapsed ? "Вернуть поле ввода" : "Изменить высоту поля ввода");
    // Подсказка в две строки: одна строка через точки читалась как список
    // условий, а человеку надо понять, что можно и потянуть, и щёлкнуть.
    handle.title = collapsed
      ? "Поле ввода свёрнуто\nНажми, чтобы вернуть"
      : "Потяни вверх или вниз\nКлик свернёт, двойной — во всю высоту";
  };

  // ---- 7. Высота ----------------------------------------------------------
  // Куда именно упирается верх поля: в низ титульной полосы. Меряем её саму —
  // на части экранов Claude полосы просто нет, и константа врала бы.
  const topLimit = () => {
    const bar = document.querySelector(".epitaxy-titlebar");
    const rect = bar?.isConnected ? bar.getBoundingClientRect() : null;
    return rect && rect.height > 0 ? Math.round(rect.top + rect.height + 2) : SAFE_TOP_INSET;
  };
  const maximumHeight = () => {
    if (!state.shell) return 640;
    const top = state.shell.getBoundingClientRect().top;
    const current = state.height ?? state.editorRoot?.getBoundingClientRect().height ?? 0;
    return Math.max(MIN_HEIGHT, Math.floor(current + top - topLimit()));
  };
  const clampHeight = value => Math.round(Math.min(maximumHeight(), Math.max(MIN_HEIGHT, value)));
  // Обычная высота поля — та, которую Claude держит сам, без нашей подмены.
  // Меряем её только на ступени «обычная высота» и запоминаем: на других
  // ступенях померить нечего, а порог ступеней без неё не посчитать.
  const naturalHeight = () =>
    state.natural != null && state.natural >= MIN_HEIGHT ? state.natural : NATURAL_FALLBACK;

  const clearResizer = () => {
    if (state.editorRoot?.isConnected) {
      state.editorRoot.style.removeProperty(HEIGHT_VARIABLE);
      state.editorRoot.removeAttribute(EDITOR_ROOT_ATTRIBUTE);
    }
    if (state.editor?.isConnected) state.editor.removeAttribute(EDITOR_ATTRIBUTE);
    clearCollapsedNodes();
    handle.style.display = "none";
  };

  // Низ всего блока ввода: рамка поля, а под ней строка модели с кругляшком.
  const composerBottom = () => {
    const node = state.composerBlock?.isConnected
      ? state.composerBlock : (state.shell?.isConnected ? state.shell : null);
    if (node == null) return null;
    const rect = node.getBoundingClientRect();
    return rect.height > 0 ? rect.bottom : null;
  };
  const setHeightVariable = () => {
    state.height = clampHeight(state.height);
    state.editorRoot.setAttribute(EDITOR_ROOT_ATTRIBUTE, "true");
    state.editor?.setAttribute(EDITOR_ATTRIBUTE, "true");
    state.editorRoot.style.setProperty(HEIGHT_VARIABLE, `${state.height}px`);
  };
  // maximumHeight() считает место от ВЕРХА рамки: пока верх не упёрся в потолок,
  // формула разрешает расти. Но контейнер Claude верх выше своего края не
  // пускает, и лишние точки уходят ВНИЗ — вместе со строкой модели и кругляшком
  // отправки. Поэтому после каждой подстановки смотрим не на формулу, а на факт:
  // низ блока ввода обязан остаться в окне. Вылез — срезаем ровно на выступ.
  const trimToViewport = () => {
    if (state.height == null || !state.editorRoot?.isConnected) return;
    // Двух подходов хватает: первый срезает выступ, второй добирает остаток,
    // если контейнер отдал не всю высоту. Дальше ждём следующего прохода —
    // лесенка из бесконечных подрезаний хуже одной лишней точки.
    for (let step = 0; step < 2; step += 1) {
      const bottom = composerBottom();
      if (bottom == null) return;
      const over = Math.round(bottom - (innerHeight - BOTTOM_SAFE_INSET));
      if (over <= BOTTOM_TRIM_SLACK) return;
      const before = state.height;
      state.height = Math.max(MIN_HEIGHT, before - over);
      if (state.height >= before) { state.height = before; return; }
      setHeightVariable();
      // Срез не поднял низ — значит держит его не наша высота, и дальше мы
      // просто отбираем поле ни за что. Возвращаем как было.
      const after = composerBottom();
      if (after == null || after > bottom - BOTTOM_TRIM_SLACK) {
        state.height = before;
        setHeightVariable();
        return;
      }
    }
  };
  const applyHeight = () => {
    if (!state.editorRoot?.isConnected) return;
    if (state.height == null) {
      state.editorRoot.style.removeProperty(HEIGHT_VARIABLE);
      state.editorRoot.removeAttribute(EDITOR_ROOT_ATTRIBUTE);
      state.editor?.removeAttribute(EDITOR_ATTRIBUTE);
      return;
    }
    setHeightVariable();
    trimToViewport();
  };

  // ---- 8. Полоска уступает всплывающим меню -------------------------------
  // Полоска живёт на самом верхнем z-index, поэтому меню Effort и модели она
  // перечёркивала насквозь. Ищем не по классам, а хит-тестом: стек элементов под
  // точкой уже отсортирован по z и не содержит прозрачных контейнеров
  // (pointer-events:none). Дошли до composer раньше чужого слоя — над полоской
  // ничего нет.
  const ownNode = node =>
    (state.shell?.isConnected === true && (state.shell.contains(node) || node.contains(state.shell))) ||
    (state.composerBlock?.isConnected === true &&
      (state.composerBlock.contains(node) || node.contains(state.composerBlock)));
  const popupCoversHandle = () => {
    const rect = handle.getBoundingClientRect();
    if (rect.width < 1) return false;
    const y = Math.round(rect.top + rect.height / 2);
    const points = [rect.left + 4, (rect.left + rect.right) / 2, rect.right - 4];
    for (const x of points) {
      for (const node of document.elementsFromPoint(Math.round(x), y)) {
        if (node === handle || handle.contains(node)) continue;
        if (node === document.body || node === document.documentElement) break;
        if (ownNode(node)) break;
        const computed = getComputedStyle(node);
        if (computed.position !== "fixed" && computed.position !== "absolute") continue;
        // z-index:auto — тоже слой: у попапа Effort числового z-index нет вовсе,
        // и полоска рисовалась НАСКВОЗЬ через его карточку. Безопасно, потому
        // что всё своё уже отсеяно, прозрачные обёртки в elementsFromPoint не
        // попадают, а хит-тест идёт ровно по трём точкам полоски.
        const z = Number(computed.zIndex);
        if (Number.isFinite(z)) {
          if (z >= POPUP_MIN_Z) return true;
          continue;
        }
        if (computed.position === "fixed") return true;
      }
    }
    return false;
  };
  // Есть ли вообще что прятать: открытое меню, список или модалка.
  const overlayOpen = () => {
    for (const node of document.querySelectorAll(OVERLAY_SELECTOR)) {
      const rect = node.getBoundingClientRect();
      if (rect.width > 0 && rect.height > 0) return true;
    }
    return false;
  };
  // Отступ свёрнутой полоски от краёв рамки — её собственное скругление плюс
  // пара точек.
  const handleInset = node => {
    const radius = node?.isConnected
      ? parseFloat(getComputedStyle(node).borderTopLeftRadius) || 0
      : 0;
    return Math.max(HANDLE_MIN_INSET, Math.round(radius) + 2);
  };

  // ---- 9. Раскладка -------------------------------------------------------
  // Свёрнутая рамка занимает нулевую высоту, поэтому её геометрия для
  // расстановки уже не годится: полоска садится над строкой модели — она
  // осталась на виду и держит низ блока. Строки нет — полоска возвращается на
  // нижний край окна.
  const placeCollapsedHandle = () => {
    const base = state.composerBlock?.isConnected ? state.composerBlock.getBoundingClientRect() : null;
    const wide = base != null && base.width >= 200;
    const span = wide ? base.width : Math.round(innerWidth * 0.6);
    const left = wide ? base.left : Math.round((innerWidth - span) / 2);
    const collapsedInset = handleInset(state.composerBlock);
    // Та же узкая полоска, что и на открытом поле (донор): полной шириной она
    // наезжала бы зоной захвата на надпись «Opus 5 · Max» и кругляшок рядом с
    // ней. В совсем узком окне её ужимает ещё и доля от ширины рамки.
    const width = Math.round(Math.max(64,
      Math.min(HANDLE_NARROW_WIDTH, (span - collapsedInset * 2) * COLLAPSED_WIDTH_SCALE)));
    const row = state.modelRow?.isConnected ? state.modelRow.getBoundingClientRect() : null;
    handle.style.display = "flex";
    handle.style.left = `${Math.round(left + (span - width) / 2)}px`;
    handle.style.width = `${width}px`;
    handle.style.top = `${Math.round(row && row.height > 0
      ? row.top - HANDLE_HEIGHT + 3
      : innerHeight - HANDLE_HEIGHT - 4)}px`;
    // Хит-тест нужен и здесь: меню модели и effort раскрываются вверх ровно над
    // этим местом. Но одного хит-теста мало: центр свёрнутой полоски лежит выше
    // строки модели, то есть уже вне блока ввода, и любой градиент расшифровки с
    // position:absolute спрятал бы её навсегда — а вернуть поле мышью больше
    // нечем. Поэтому прячем только когда меню действительно открыто.
    state.handleCovered = !state.dragging && overlayOpen() && popupCoversHandle();
    if (state.handleCovered) handle.style.display = "none";
  };

  const noteEditorFound = () => {
    if (state.editorFound) return;
    state.editorFound = true;
    if (state.giveUpTimer) { clearTimeout(state.giveUpTimer); state.giveUpTimer = 0; }
  };

  const layout = () => {
    // Проход мог прийти в обход плана (heartbeat, команда, старт): снимаем всё
    // запланированное, иначе кадр и таймер сработают ещё раз впустую, а id
    // старого таймера потеряется и снять его будет уже нечем.
    cancelPendingLayout();
    state.scheduled = false;
    state.layoutAt = now();
    state.layoutRuns += 1;
    const editor = findEditor();
    // Страховка от мигания: даже если редактор потерялся, свёрнутое состояние не
    // сбрасываем, пока жив хоть один схлопнутый узел.
    const keepCollapsed = !editor && state.stage === STAGE_COLLAPSED &&
      state.collapsedNodes.some(node => node.isConnected);
    if (keepCollapsed) { placeCollapsedHandle(); return; }
    if (editor !== state.editor) {
      clearResizer();
      state.editor = editor;
      state.editorRoot = editor ? findEditorRoot(editor) : null;
      state.shell = editor ? findShell(editor, state.editorRoot) : null;
    }
    if (!editor) { handle.style.display = "none"; return; }
    noteEditorFound();
    const block = findComposerBlock(editor, state.shell);
    if (block !== state.composerBlock) {
      clearCollapsedNodes();
      state.composerBlock = block;
    }
    // Рамку и строку модели пересчитываем каждый проход: Claude перерисовывает
    // низ окна целиком (смена модели, вложения), и закэшированные узлы после
    // этого указывали бы в пустоту.
    if (!state.collapsedNodes.includes(block)) {
      const parts = findComposerParts(block, state.shell);
      state.frameChild = parts?.frameChild ?? null;
      state.modelRow = parts?.modelRow ?? null;
    }
    applyCollapse();
    if (!state.shell?.isConnected) { handle.style.display = "none"; return; }
    if (state.stage === STAGE_COLLAPSED) { placeCollapsedHandle(); return; }
    applyHeight();
    // Обычная высота известна только здесь: на этой ступени подмены высоты нет и
    // поле показывает свой собственный размер.
    if (state.stage === STAGE_NORMAL && state.editorRoot?.isConnected) {
      const measured = Math.round(state.editorRoot.getBoundingClientRect().height);
      if (measured >= MIN_HEIGHT) state.natural = measured;
    }
    const rect = state.shell.getBoundingClientRect();
    if (rect.width < 200 || rect.bottom <= 0 || rect.top >= innerHeight) { handle.style.display = "none"; return; }
    handle.style.display = "flex";
    // Узкая полоска по центру рамки и верхом на её кромке (донор). Место под
    // неё считаем от полной ширины за вычетом скруглений: в совсем узком окне
    // полоска ужимается, а на скругления не выезжает. Поле выше своего
    // контейнера всё равно не поднимается, поэтому кромке ничего не мешает.
    const stripRoom = Math.max(64, rect.width - handleInset(state.shell) * 2);
    const stripWidth = Math.round(Math.min(HANDLE_NARROW_WIDTH, stripRoom));
    handle.style.left = `${Math.round(rect.left + (rect.width - stripWidth) / 2)}px`;
    handle.style.width = `${stripWidth}px`;
    handle.style.top = `${Math.round(Math.max(topLimit() - HANDLE_HEIGHT / 2, rect.top - HANDLE_HEIGHT / 2))}px`;
    // Проверяем после расстановки: хит-тест идёт по новому месту полоски. Во
    // время перетаскивания не прячем — курсор держит именно её.
    state.handleCovered = !state.dragging && popupCoversHandle();
    if (state.handleCovered) handle.style.display = "none";
  };

  const cancelPendingLayout = () => {
    if (state.rafId) { cancelAnimationFrame(state.rafId); state.rafId = 0; }
    if (state.layoutTimer) { clearTimeout(state.layoutTimer); state.layoutTimer = 0; }
  };
  const runLayout = () => { state.rafId = 0; if (state.alive) layout(); };
  // Проход планируется через кадр, но не чаще раза в LAYOUT_MIN_GAP: во время
  // ответа Claude мутаций сотни в секунду, а каждый проход — принудительный
  // reflow в каждом из открытых окон.
  const scheduleLayout = () => {
    // После отбоя (страница оказалась чужой) проходов больше нет: подписки на
    // resize/scroll/указатель снять нельзя — они держат ручку и команды, — но
    // работы им уже не даём.
    if (state.scheduled || !state.alive || !state.watching) return;
    state.scheduled = true;
    const wait = Math.max(0, LAYOUT_MIN_GAP - (now() - state.layoutAt));
    if (wait === 0) { state.rafId = requestAnimationFrame(runLayout); return; }
    state.layoutTimer = setTimeout(() => {
      state.layoutTimer = 0;
      state.rafId = requestAnimationFrame(runLayout);
    }, wait);
  };
  track(cancelPendingLayout);

  // Блок ввода прибит к низу окна, и лента его не двигает, поэтому реагируем
  // только на то, что задело сам блок или его предка. Всё остальное подберёт
  // страховочный проход.
  const affectsComposer = node => {
    const anchor = state.composerBlock?.isConnected ? state.composerBlock
      : (state.shell?.isConnected ? state.shell : null);
    if (anchor == null || !(node instanceof Node)) return true;
    return anchor.contains(node) || node.contains(anchor);
  };
  const onScrolled = event => {
    if (!state.watching) return;
    if (!affectsComposer(event.target)) return;
    scheduleLayout();
  };
  const onMutated = records => {
    state.mutationBatches += 1;
    for (const record of records) {
      if (!affectsComposer(record.target)) continue;
      scheduleLayout();
      return;
    }
    state.mutationSkipped += 1;
  };

  // ---- 10. Ступени --------------------------------------------------------
  const finishDrag = () => {
    if (!state.dragging) return;
    state.dragging = false;
    handle.dataset.dragging = "false";
    document.documentElement.style.cursor = "";
    document.documentElement.style.userSelect = "";
    storeHeight(state.height);
    scheduleLayout();
  };
  // Единственная точка смены ступени: и тяга, и клики, и команды снаружи ходят
  // только через неё, поэтому ступень и высота не могут разъехаться.
  const setStage = (next, options) => {
    const value = Math.max(STAGE_COLLAPSED, Math.min(STAGE_STRETCHED, next));
    const height = options?.height;
    if (state.stage === value && (value !== STAGE_STRETCHED || height == null)) return;
    state.stage = value;
    storeStage(value);
    if (value === STAGE_STRETCHED) {
      // Возврат в «растянуто» без явной высоты — это возврат к своему размеру, а
      // не к потолку окна: сначала последняя натянутая рукой высота и только
      // потом максимум.
      state.height = clampHeight(height ?? state.height ?? state.lastStretched ?? maximumHeight());
      state.lastStretched = state.height;
    } else {
      // Обычная высота и полоска своей высоты не хранят: подмену снимаем, и поле
      // снова слушается самого Claude. Саму цифру помним в памяти окна, иначе
      // возврат в «растянуто» открывал бы поле во всё окно вместо прежнего.
      state.lastStretched = state.height ?? state.lastStretched;
      state.height = null;
      // Достигнутый упор верен только для текущего вида: сменилась ступень —
      // считать заново.
      state.ceiling = null;
      storeHeight(null);
      if (state.editorRoot?.isConnected) {
        state.editorRoot.style.removeProperty(HEIGHT_VARIABLE);
        state.editorRoot.removeAttribute(EDITOR_ROOT_ATTRIBUTE);
      }
    }
    applyCollapse();
    applyHeight();
    if (options?.silent) return;
    layout();
  };

  const onPointerDown = event => {
    if (event.button !== 0 || !state.editorRoot) return;
    // Любое новое нажатие обесценивает отложенный шаг предыдущего клика: иначе
    // «щёлкнул и сразу потянул» доводит поле руками до нужной ступени, а через
    // 260 мс таймер делает ещё один шаг прямо посреди тяги.
    cancelClickStep();
    state.moved = false;
    event.preventDefault();
    state.dragging = true;
    state.startY = event.clientY;
    // Снимок высоты на момент захвата. Дальше во время тяги живую геометрию не
    // трогаем: пороги, посчитанные от неё, опрокидывали бы решение обратно.
    // Свёрнутое поле — это ноль, и тяга вверх поднимает его с нуля.
    state.startHeight = state.stage === STAGE_COLLAPSED
      ? 0
      : (state.height ?? state.editorRoot.getBoundingClientRect().height);
    state.dragNatural = naturalHeight();
    document.documentElement.style.cursor = "ns-resize";
    document.documentElement.style.userSelect = "none";
    handle.dataset.dragging = "true";
    try { handle.setPointerCapture(event.pointerId); } catch {}
  };
  const onPointerMove = event => {
    if (!state.dragging || !state.editorRoot) return;
    event.preventDefault();
    // Дрожь руки на пару точек — это всё ещё клик, а не перетаскивание.
    if (Math.abs(event.clientY - state.startY) > CLICK_SLACK) state.moved = true;
    // Всё решает курсор: desired — это снимок высоты плюс пройденный мышью путь,
    // живой геометрии здесь нет ни в одном пороге. Ступени разведены
    // гистерезисом, поэтому на границе они не дребезжат.
    const desired = state.startHeight - (event.clientY - state.startY);
    const natural = state.dragNatural;
    // Протянул заметно ниже минимума — значит хотел убрать поле совсем. Тягу не
    // обрываем: обратным движением вверх поле возвращается тем же жестом.
    if (state.stage !== STAGE_COLLAPSED && desired < MIN_HEIGHT - COLLAPSE_DRAG_SLACK) {
      setStage(STAGE_COLLAPSED);
      return;
    }
    if (state.stage === STAGE_COLLAPSED) {
      if (desired > MIN_HEIGHT) setStage(STAGE_NORMAL);
      return;
    }
    if (state.stage === STAGE_STRETCHED && desired < natural) { setStage(STAGE_NORMAL); return; }
    if (state.stage !== STAGE_STRETCHED) {
      if (desired > natural + STAGE_DRAG_SLACK) setStage(STAGE_STRETCHED, { height: desired });
      return;
    }
    state.height = clampHeight(desired);
    applyHeight();
    layout();
  };

  // Одиночный клик — шаг по лестнице: полоску разворачивает до обычной высоты,
  // любое развёрнутое поле сворачивает. Шаг отложен: второй клик двойного
  // приходит сюда же, и без задержки каждый двойной клик успевал бы сначала
  // сделать лишний шаг.
  const cancelClickStep = () => {
    if (!state.clickTimer) return;
    clearTimeout(state.clickTimer);
    state.clickTimer = 0;
  };
  track(cancelClickStep);
  const onClick = event => {
    // Полоску только что тащили — это не клик. Отложенный шаг гасим и здесь:
    // после длинной тяги Chromium присылает click с detail=1, и без отмены поле
    // сделало бы лишний шаг сразу после того, как его растянули рукой.
    if (state.moved) { state.moved = false; cancelClickStep(); return; }
    event.preventDefault();
    cancelClickStep();
    if (event.detail > 1) return;
    state.clickTimer = setTimeout(() => {
      state.clickTimer = 0;
      // За 260 мс ожидания всё могло измениться: началась новая тяга или
      // экземпляр сняли — тогда шаг свернул бы поле, а полоски для возврата уже
      // нет.
      if (state.dragging || !state.alive) return;
      setStage(state.stage === STAGE_COLLAPSED ? STAGE_NORMAL : STAGE_COLLAPSED);
    }, CLICK_STEP_DELAY);
  };

  // ---- 11. Разворот до потолка -------------------------------------------
  // Пустой чат: разговора ещё нет, и над полем висит шапка с приветствием и
  // выбором проекта. В Claude Code своя разметка разговора, без классов обычного
  // чата (замер донора: ноль .font-claude-response даже посреди переписки),
  // поэтому примет несколько — см. CHAT_STARTED_SELECTOR. Прежние три приметы
  // в сборке 1.40609.1 не срабатывали ни одна, и разговор считался пустым чатом:
  // из-за этого двойной клик целился в «низ шапки», найденный вплотную к полю,
  // и не растягивал поле вовсе.
  const isFreshChat = () => document.querySelectorAll(CHAT_STARTED_SELECTOR).length === 0;
  // Низ шапки пустого чата: самый нижний осмысленный блок над рамкой ввода. Не
  // по классам — Claude их перегенерирует, — а по геометрии: строка выбора
  // проекта стоит прямо над полем и попадает сюда сама.
  const freshHeaderBottom = () => {
    if (state.shell == null) return null;
    const limit = state.shell.getBoundingClientRect().top - 2;
    let bottom = null;
    for (const node of document.querySelectorAll("main h1,main h2,main button,main a,main p")) {
      // Сам блок ввода шапкой не является ни одной своей частью.
      if (state.composerBlock?.contains(node)) continue;
      const rect = node.getBoundingClientRect();
      if (rect.height < 12 || rect.width < 40) continue;
      if (rect.bottom > limit || rect.top < SAFE_TOP_INSET) continue;
      if (bottom == null || rect.bottom > bottom) bottom = rect.bottom;
    }
    return bottom == null ? null : Math.round(bottom + 12);
  };
  // Примета вида окна для замеренного упора: в пустом чате и в разговоре, в
  // узком окне и в широком контейнер держит верх поля на разной высоте, и чужой
  // замер только навредил бы.
  const ceilingFloorKey = () =>
    `${isFreshChat() ? 1 : 0}:${Math.round(innerWidth)}x${Math.round(innerHeight)}`;
  const ceilingFloorTop = () => {
    const memo = state.ceilingFloor;
    return memo != null && memo.key === ceilingFloorKey() ? memo.top : null;
  };
  // Годится ли отметка в цель. Мерим не «насколько выше нынешнего верха» (эта
  // разница у растянутого поля своя, и atCeiling с разворотом разошлись бы), а
  // сколько места отметка оставляет полю до низа рамки: низ рамки прибит к
  // строке модели и от ступени не зависит. Меньше обычной высоты с запасом —
  // отметка вырожденная, и целиться в неё нельзя.
  const aimUsable = aim => {
    if (aim == null || !state.shell?.isConnected) return false;
    return state.shell.getBoundingClientRect().bottom - aim >= naturalHeight() + CEILING_MIN_ROOM;
  };
  // Куда целимся верхом поля: обычно в низ титульной полосы, в пустом чате — в
  // низ шапки, но только пока шапка оставляет полю место. Одна точка на всех:
  // atCeiling и разворот обязаны считать одинаково, иначе двойной клик начинает
  // мигать между «растянуть» и «вернуть обычную».
  const stretchLimit = () => {
    const limit = topLimit();
    if (!isFreshChat()) return limit;
    const header = freshHeaderBottom();
    return header != null && header > limit && aimUsable(header) ? header : limit;
  };
  // Верх поля уже у потолка — значит тянуть дальше некуда. Мерим не до
  // расчётного потолка, а до замеренного упора контейнера: выше него верх поля
  // не поднимется, сколько ни тяни, и без этого повторный двойной клик перестал
  // бы возвращать обычную высоту — намеренный недобор съел бы весь допуск.
  const atCeiling = () => {
    if (state.shell == null || state.stage !== STAGE_STRETCHED) return false;
    const limit = stretchLimit();
    const floor = ceilingFloorTop();
    // Пол берём без aimUsable: в очень низком окне отвергнутый пол уводил бы цель на
    // титульную полосу, и растянутое поле никогда не считалось бы «у потолка».
    const aim = floor != null && floor > limit ? floor : limit;
    return state.shell.getBoundingClientRect().top <= aim + CEILING_UNDERSHOOT + 10;
  };
  // До упора — одним шагом и с намеренным недобором. Формуле maximumHeight()
  // верить нельзя: она считает, что прибавка высоты целиком уходит вверх, а
  // контейнер Claude верх дальше своего края не пускает, и лишние точки уходят
  // вниз, выдавливая строку модели. Поэтому целимся в ранее замеренный упор, а
  // промах разбираем по факту: второй шаг разрешён только на грубом промахе и
  // всегда последний — лесенки из трёх подходов быть не должно.
  const stretchToCeiling = ceilingTop => {
    const shell = state.shell;
    if (shell == null) return;
    // setStage перерисовывает низ окна, и рамка под руками может смениться или
    // исчезнуть. Дальше меряем только ту, с которой начинали, и на каждой смене
    // уходим: замеры от чужой рамки бессмысленны, а от исчезнувшей — падение.
    const gone = () => state.shell !== shell || !shell.isConnected;
    const limit = ceilingTop ?? topLimit();
    const floor = ceilingFloorTop();
    const aim = floor != null && floor > limit && aimUsable(floor) ? floor : limit;
    const before = shell.getBoundingClientRect().top;
    // Опорная высота годится только осмысленная: свёрнутое поле даёт нули, и от
    // нуля цель вышла бы вдвое больше нужного.
    const measured = state.editorRoot?.isConnected
      ? Math.round(state.editorRoot.getBoundingClientRect().height) : 0;
    const base = state.height ?? (measured >= MIN_HEIGHT ? measured : naturalHeight());
    const target = Math.max(base, Math.round(base + (before - aim) - CEILING_UNDERSHOOT));
    setStage(STAGE_STRETCHED, { height: target });
    state.stretchSteps = 1;
    if (gone()) return;
    // clampHeight внутри setStage мог урезать запрошенное — дальше считаем по
    // тому, что реально применилось.
    const applied = state.height ?? target;
    const after = shell.getBoundingClientRect().top;
    const grew = applied - base;
    const moved = before - after;
    // Прибавка, не ушедшая вверх. Она и показывает настоящий упор контейнера.
    const wasted = grew - moved;
    if (wasted > CEILING_WASTE_SLACK) {
      // Упор запоминаем, только если рамка вообще сдвинулась. Замер по
      // неподвижной рамке равен её нынешнему верху, а он потом идёт целью —
      // и разворот запирается на обычной высоте навсегда. Причин не сдвинуться
      // хватает и без упора контейнера: черновик выше поля, подрезка по низу
      // окна, чужая раскладка. Тогда высоту так же отдаём назад, но память
      // чистим — следующая попытка начнёт с чистого листа.
      state.ceilingFloor = moved > 0 ? { key: ceilingFloorKey(), top: Math.round(after) } : null;
      // Контейнер не пустил заметно выше: поджимаем ровно на пустоту — один раз
      // и всё. В следующий раз этот же упор возьмётся из памяти.
      setStage(STAGE_STRETCHED, { height: Math.max(base, applied - wasted - CEILING_UNDERSHOOT) });
      state.stretchSteps = 2;
    } else if (grew > 0 && after - limit > CEILING_RETRY_GAP) {
      // Прибавка уходила вверх целиком, а до настоящего потолка всё равно
      // далеко. Меряем именно до limit, а не до запомненного упора: иначе
      // однажды записанная память навсегда запирает разворот низко. Раз места
      // оказалось больше, память устарела — стираем её.
      state.ceilingFloor = null;
      setStage(STAGE_STRETCHED, { height: applied + (after - limit) - CEILING_UNDERSHOOT });
      state.stretchSteps = 2;
    }
    if (gone()) return;
    state.ceiling = state.height ?? applied;
    // Отступление от донора: он писал высоту только по концу тяги, и разворот
    // двойным кликом перезагрузку страницы не переживал. Раз высота теперь
    // сессионная (своя у каждого окна), сохранить её здесь ничего не стоит.
    storeHeight(state.height);
  };
  // Разворот до упора одним движением. Вынесен отдельно от обработчика двойного
  // клика: тем же путём поле разворачивает вставка «Обкэшить».
  const stretchToMax = () => {
    // Пока поле свёрнуто, мерить нечего — сначала молча возвращаем обычный вид.
    // Именно обычный, а не растянутый: setStage(STRETCHED) без высоты подставил
    // бы запомненный чужой размер, и это лишний скачок на глазах.
    if (state.stage === STAGE_COLLAPSED) setStage(STAGE_NORMAL, { silent: true });
    // В пустом чате шапку не съедаем: над полем стоят приветствие и кнопки
    // проекта, и без них непонятно даже, в какой папке откроется разговор.
    // Низ шапки меряем уже по возвращённому полю: у свёрнутого верх стоит ниже,
    // и в замер попали бы блоки, которые поле собой закроет. Разбор «шапка или
    // титульная полоса» — в stretchLimit(), общий с atCeiling.
    stretchToCeiling(stretchLimit());
    layout();
  };
  // Двойной клик — сразу максимум, без лесенки. Ступени остались за одиночным
  // кликом и тягой. Повторный двойной клик по уже развёрнутому до упора полю
  // возвращает обычную высоту: иначе из максимума не выйти тем же жестом.
  // «Уже до упора» решаем по верху поля, а не по высоте: у высоты цифра пляшет
  // от прохода к проходу, а верх на упоре стоит намертво.
  const onDoubleClick = event => {
    event.preventDefault();
    cancelClickStep();
    state.moved = false;
    if (atCeiling()) { setStage(STAGE_NORMAL); return; }
    stretchToMax();
  };

  // ---- 12. «Обкэшить» -----------------------------------------------------
  // Переносит в поле ввода нового чата последний ответ Claude и текущий
  // черновик. Само открытие нового чата делает Hammerspoon (⌘N) — здесь только
  // запись переноса и вставка на другой стороне. Донор тут не помощник: у него
  // для этого свой канал наружу.
  const rawText = node => {
    if (!node?.isConnected) return "";
    if (typeof node.value === "string") return node.value;
    return node.innerText ?? node.textContent ?? "";
  };
  // Пустой ProseMirror держит переносы и невидимые заполнители — они не текст.
  const editorText = (node = state.editor) => rawText(node).replace(/[\s\u200B\uFEFF]+/g, "");
  // Примета реплики самого Элвиса — .epitaxy-user-turn внутри или снаружи; ещё
  // отсеиваем строку действий под ответом (там «3 minutes ago», а не текст) и
  // само поле ввода.
  const answerUsable = node =>
    !node.closest('[aria-label="Message actions"]') &&
    !node.closest(".epitaxy-user-turn") &&
    !node.querySelector(".epitaxy-user-turn") &&
    !state.composerBlock?.contains(node) &&
    Boolean((node.textContent ?? "").trim());
  // Последний по документу — но только среди внешних узлов: один ответ даёт
  // несколько совпадений (вложенные куски), и «просто последний» брал бы кусок.
  const pickAnswer = list => {
    const nodes = [...list].filter(answerUsable);
    const outer = nodes.filter(node => !nodes.some(other => other !== node && other.contains(node)));
    return outer[outer.length - 1] ?? null;
  };
  // Строгая примета разметки, если она сегодня жива, надёжнее общего списка.
  const lastAnswerNode = () =>
    pickAnswer(document.querySelectorAll('[data-testid="assistant-message"]'))
    ?? pickAnswer(document.querySelectorAll(ANSWER_SELECTOR));
  const lastAnswerText = () => {
    const hit = lastAnswerNode();
    return hit == null ? "" : rawText(hit).trim();
  };
  const clearCashout = () => { try { localStorage.removeItem(CASHOUT_KEY); } catch {} };
  const readCashout = () => {
    try {
      const raw = localStorage.getItem(CASHOUT_KEY);
      if (!raw) return null;
      const data = JSON.parse(raw);
      const at = Number(data?.at);
      const text = typeof data?.text === "string" ? data.text : "";
      return text && Number.isFinite(at) ? { at, text } : null;
    } catch { return null; }
  };
  const insertIntoEditor = (editor, text) => {
    try { editor.focus(); } catch {}
    try { document.execCommand("insertText", false, text); } catch {}
    if (editorText(editor)) return true;
    // ProseMirror не принял execCommand — досылаем то же самое событием paste.
    try {
      const data = new DataTransfer();
      data.setData("text/plain", text);
      editor.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
    } catch {}
    return Boolean(editorText(editor));
  };
  const tryPasteCashout = () => {
    const record = readCashout();
    if (record == null) return "нет записи";
    if (Date.now() - record.at > CASHOUT_FRESH_MS) { clearCashout(); return "запись протухла"; }
    const editor = state.editor?.isConnected ? state.editor : findEditor();
    if (!editor?.isConnected) return "нет редактора";
    // Вставляем только в свежий чат и только в пустое поле: иначе перенос
    // затёр бы чужой черновик или лёг посреди разговора.
    if (!isFreshChat()) return "чат не свежий";
    if (editorText(editor)) return "в поле черновик";
    if (!insertIntoEditor(editor, record.text)) return "вставка не удалась";
    clearCashout();
    setStage(STAGE_NORMAL);
    return "вставлено";
  };
  const clearCashoutWatch = () => {
    if (!state.cashoutTimer) return;
    clearInterval(state.cashoutTimer);
    state.cashoutTimer = 0;
  };
  track(clearCashoutWatch);
  // Сторож вставки. ⌘N может открыть новый чат и в этом же окне (страница не
  // перезагружается, инжект заново не приходит), поэтому ждём появления свежего
  // чата, а не одного лишь момента установки. Живёт ровно пока запись свежая.
  const armCashoutWatch = () => {
    clearCashoutWatch();
    if (readCashout() == null) return;
    state.cashoutTimer = setInterval(() => {
      if (!state.alive) { clearCashoutWatch(); return; }
      const result = tryPasteCashout();
      if (result === "вставлено" || result === "запись протухла" || result === "нет записи") clearCashoutWatch();
    }, CASHOUT_TICK_MS);
  };
  const runCashout = () => {
    const answer = lastAnswerText();
    const draft = rawText(state.editor).trim();
    const parts = [];
    if (answer) parts.push(answer);
    if (draft) parts.push(draft);
    const text = parts.join("\n\n");
    if (!text) return false;
    try { localStorage.setItem(CASHOUT_KEY, JSON.stringify({ at: Date.now(), text })); } catch { return false; }
    armCashoutWatch();
    return true;
  };

  // ---- 13. Прокрутка ленты ------------------------------------------------
  // Команда «Прокрутить»: поставить ленту разговора на последнее сообщение.
  // В отличие от collapse/expand она адресована ВСЕМ окнам сразу, поэтому
  // фокуса не спрашивает (см. onCommand).
  //
  // Лента Claude Code — сама себе скролл-контейнер и помечена
  // epitaxy-virtual-transcript. В обычном чате claude.ai такой приметы нет, и
  // там работает запасной путь донора: ближайший прокручиваемый предок
  // последнего сообщения.
  const SCROLL_SELECTOR = '[data-testid="epitaxy-virtual-transcript"]';
  // Меньше этого запаса — контейнер не прокручивается вовсе, брать его незачем.
  const SCROLL_MIN_ROOM = 8;
  // Виртуальная лента дорисовывает хвост уже после первого скролла: кадр плюс
  // до пяти доборов по 120 мс покрывают и самое медленное досчитывание высоты.
  const SCROLL_STEPS = 5;
  const SCROLL_STEP_MS = 120;

  const scrollRoom = node => {
    const height = Number(node?.scrollHeight);
    const view = Number(node?.clientHeight);
    if (!Number.isFinite(height) || !Number.isFinite(view)) return 0;
    return height - view;
  };
  const scrollerFor = node => {
    let current = node?.parentElement ?? null;
    while (current && current !== document.body && current !== document.documentElement) {
      if (scrollRoom(current) > SCROLL_MIN_ROOM) {
        let overflow = "";
        try { overflow = getComputedStyle(current).overflowY ?? ""; } catch {}
        if (/(auto|scroll)/.test(overflow)) return current;
      }
      current = current.parentElement;
    }
    return null;
  };
  // Последнее сообщение. Ответ ассистента — самая надёжная примета; если его
  // ещё нет (первый вопрос в свежем чате), годится любой узел ленты.
  const lastMessageNode = () => {
    let answer = null;
    try { answer = lastAnswerNode(); } catch {}
    if (answer?.isConnected) return answer;
    try {
      const nodes = document.querySelectorAll(TRANSCRIPT_SELECTOR);
      return nodes[nodes.length - 1] ?? null;
    } catch { return null; }
  };
  const findScroller = () => {
    let virtual = null;
    try { virtual = document.querySelector(SCROLL_SELECTOR); } catch {}
    if (virtual?.isConnected && scrollRoom(virtual) > SCROLL_MIN_ROOM) return virtual;
    return scrollerFor(lastMessageNode()) ?? (virtual?.isConnected ? virtual : null);
  };
  const clearScrollWatch = () => {
    if (state.scrollRaf) { cancelAnimationFrame(state.scrollRaf); state.scrollRaf = 0; }
    if (state.scrollTimer) { clearTimeout(state.scrollTimer); state.scrollTimer = 0; }
    state.scrollSteps = 0;
    state.scroller = null;
  };
  track(clearScrollWatch);
  // Ниже scrollHeight браузер сам зажимает до предела прокрутки — целимся в
  // него, а не в разницу с clientHeight: та врёт, пока хвост ещё дорисовывают.
  const scrollDown = target => {
    const height = Number(target?.scrollHeight);
    if (!Number.isFinite(height)) return 0;
    try { target.scrollTop = height; } catch {}
    return height;
  };
  const scrollTail = () => {
    state.scrollTimer = 0;
    if (!state.alive) return;
    const target = state.scroller;
    if (!target?.isConnected) { clearScrollWatch(); return; }
    const height = Number(target.scrollHeight) || 0;
    // Лента перестала расти — хвост на месте, дёргать её дальше незачем.
    if (height <= state.scrollSeen) { clearScrollWatch(); return; }
    state.scrollSeen = height;
    state.scrollSteps -= 1;
    scrollDown(target);
    if (state.scrollSteps <= 0) { clearScrollWatch(); return; }
    state.scrollTimer = setTimeout(scrollTail, SCROLL_STEP_MS);
  };
  const runScroll = () => {
    // Прошлая прокрутка (двойной клик по пункту меню) свои доборы доигрывать не
    // должна: цель могла смениться, а два ряда таймеров спорили бы друг с другом.
    clearScrollWatch();
    const target = findScroller();
    if (!target?.isConnected) return false;
    state.scrollRuns += 1;
    state.scroller = target;
    state.scrollSeen = scrollDown(target);
    state.scrollSteps = SCROLL_STEPS;
    state.scrollRaf = requestAnimationFrame(() => {
      state.scrollRaf = 0;
      if (!state.alive) return;
      const node = state.scroller;
      if (!node?.isConnected) { clearScrollWatch(); return; }
      // Кадр скроллит без условий: он и есть тот самый добор за подставленной
      // высотой последнего сообщения.
      state.scrollSeen = Math.max(state.scrollSeen, scrollDown(node));
      state.scrollTimer = setTimeout(scrollTail, SCROLL_STEP_MS);
    });
    return true;
  };

  // ---- 14. Короткое время под сообщениями ---------------------------------
  // Под каждым сообщением Claude пишет «3 minutes ago» — по слову Элвиса, это
  // визуальный шум. Сокращаем в самом тексте: minutes → min, seconds → sec,
  // hours → h, days → d. Всё остальное («Just now», числа, «ago») не трогаем.
  const TIME_SELECTOR = '[aria-label="Message actions"] time';
  const TIME_LONG = /\b(?:seconds?|minutes?|hours?|days?)\b/;
  // Часики тикают: Claude сам перерисовывает текст, и правку приходится
  // повторять. Проход — обход всех строк действий, поэтому не чаще раза в
  // 250 мс, как и раскладка.
  const TIME_MIN_GAP = 250;
  const shortenTime = text => text
    .replace(/\bminutes?\b/g, "min")
    .replace(/\bseconds?\b/g, "sec")
    .replace(/\bhours?\b/g, "h")
    .replace(/\bdays?\b/g, "d");
  // Правим текстовые узлы, а не textContent целиком: внутри <time> у Claude
  // бывает своя разметка, и перезапись текстом снесла бы её.
  const shortenTextNodes = node => {
    if (node == null) return;
    if (node.nodeType === 3) {
      const text = node.nodeValue ?? "";
      // Уже коротко — молчим. Правка порождает мутацию, мутация зовёт нас
      // обратно, и без этой проверки круг наблюдатель ↔ правка не разорвать.
      if (!TIME_LONG.test(text)) return;
      node.nodeValue = shortenTime(text);
      return;
    }
    const kids = node.childNodes;
    if (!kids) return;
    for (let index = 0; index < kids.length; index += 1) shortenTextNodes(kids[index]);
  };
  const timeObserver = new MutationObserver(() => scheduleShortTime());
  const stopTimeWatch = () => {
    try { timeObserver.disconnect(); } catch {}
    state.timeTarget = null;
  };
  track(stopTimeWatch);
  // Лента приезжает позже инжекта, поэтому до неё смотрим за body, а как
  // появится — переезжаем на неё: мимо body идут ещё и поле ввода с боковой
  // панелью, а строки действий живут только в ленте.
  const watchTime = () => {
    if (!state.alive || !state.watching) return false;
    let target = null;
    try { target = document.querySelector(SCROLL_SELECTOR); } catch {}
    if (!target?.isConnected) target = document.body ?? null;
    if (!target || target === state.timeTarget) return false;
    try { timeObserver.disconnect(); } catch {}
    state.timeTarget = target;
    try {
      timeObserver.observe(target, { characterData: true, childList: true, subtree: true });
    } catch { state.timeTarget = null; }
    return state.timeTarget != null;
  };
  const runShortTime = () => {
    state.timeTimer = 0;
    if (!state.alive || !state.watching) return;
    state.timeAt = now();
    state.timeRuns += 1;
    try {
      for (const node of document.querySelectorAll(TIME_SELECTOR)) shortenTextNodes(node);
    } catch {}
    watchTime();
  };
  const cancelShortTime = () => {
    if (!state.timeTimer) return;
    clearTimeout(state.timeTimer);
    state.timeTimer = 0;
  };
  track(cancelShortTime);
  const scheduleShortTime = () => {
    if (state.timeTimer || !state.alive || !state.watching) return;
    const wait = Math.max(0, TIME_MIN_GAP - (now() - state.timeAt));
    if (wait === 0) { runShortTime(); return; }
    state.timeTimer = setTimeout(runShortTime, wait);
  };

  // ---- 15. Команды снаружи ------------------------------------------------
  // command.json доставляется лоадером во ВСЕ страницы разом, поэтому команду
  // берёт только окно под фокусом — и только то, где вообще есть поле ввода
  // (в оболочке file://…/main_window и на логине его нет).
  const onCommand = event => {
    const detail = event?.detail;
    const action = typeof detail?.action === "string" ? detail.action : "";
    if (!action || !state.alive) return;
    // «Прокрутить» — исключение: она адресована всем окнам, а не одному под
    // фокусом, и поля ввода ей не нужно — нужна лента. На чужой странице ленты
    // нет, и команда там тихо ничего не делает.
    if (action === "scroll") { runScroll(); return; }
    if (!state.editor?.isConnected) return;
    // «Свернуть»/«Развернуть» — тоже на все окна (ElvisOS: «убирает поле ввода во
    // всех окнах»; слово Элвиса 03.09 13:30). Только «Обкэшить» адресована окну в фокусе.
    if (action === "collapse") { setStage(STAGE_COLLAPSED); return; }
    if (action === "expand") { setStage(STAGE_NORMAL); return; }
    // «Обкэшить» адресована одному окну. Окно «Open in new window» (about:blank) может
    // не считать себя в фокусе, поэтому сверяем заголовок окна, который присылает
    // Hammerspoon; фокус — запасной критерий, когда заголовка нет.
    if (action === "cashout") {
      const title = typeof detail?.title === "string" ? detail.title.trim() : "";
      const mine = title ? (document.title || "").trim() === title : document.hasFocus();
      if (mine) runCashout();
    }
    // Неизвестные команды игнорируем молча: их может слать не только наш модуль.
  };

  // ---- 16. Подписки -------------------------------------------------------
  on(handle, "pointerdown", onPointerDown);
  on(handle, "click", onClick);
  on(handle, "dblclick", onDoubleClick);
  on(document, "pointermove", onPointerMove, { capture: true });
  on(document, "pointerup", finishDrag, { capture: true });
  on(document, "pointercancel", finishDrag, { capture: true });
  on(window, "resize", scheduleLayout);
  on(window, "scroll", onScrolled, true);
  on(window, "myclaude-command", onCommand);
  // Escape не должен останавливать выполнение (слово Элвиса 03.09 14:00: F1/F2 рядом,
  // «постоянно боюсь нажать Escape»). Глотаем Escape на захвате, но только когда на
  // странице нет открытого диалога/меню/списка — там Escape нужен, чтобы их закрыть.
  const ESC_OVERLAY_SELECTOR = '[role="dialog"],[role="menu"],[role="listbox"],[role="alertdialog"],[data-state="open"],[cmdk-root]';
  const onKeyDown = (event) => {
    if (event.key !== "Escape" || event.defaultPrevented) return;
    if (document.querySelector(ESC_OVERLAY_SELECTOR)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    state.escapesBlocked = (state.escapesBlocked || 0) + 1;
  };
  on(window, "keydown", onKeyDown, { capture: true });

  const observer = new MutationObserver(onMutated);
  observer.observe(document.documentElement, { childList: true, subtree: true });
  track(() => observer.disconnect());
  // Наблюдатель за временем — отдельный: у него свои цель (лента, а не весь
  // документ), свой набор мутаций (ещё и characterData) и свой троттлинг.
  watchTime();

  const heartbeat = setInterval(() => {
    if (!state.alive) return;
    // Лента могла смениться целиком (React пересобрал разговор): наблюдатель за
    // временем остался бы висеть на выброшенном узле и оглох — мутаций оттуда
    // больше не придёт, а значит и переехать сам он уже не сможет.
    if (state.timeTarget && !state.timeTarget.isConnected && watchTime()) scheduleShortTime();
    if (state.scheduled) {
      // Запланированный кадр так и не пришёл (окно спрятано или перекрыто, и
      // macOS остановил requestAnimationFrame) — доводим руками.
      if (now() - state.layoutAt >= LAYOUT_MIN_GAP) { cancelPendingLayout(); layout(); }
      return;
    }
    scheduleLayout();
  }, HEARTBEAT_MS);
  track(() => clearInterval(heartbeat));

  // Инжект попадает и в оболочку file://…/main_window, и на страницы логина —
  // там поля ввода нет и не будет. Через минуту ожидания перестаём смотреть за
  // документом, если страница явно не claude.ai и на ней нет ни одной приметы
  // интерфейса Claude (последняя проверка — сверх плана: окна «Open in new
  // window» живут на about:blank, и терять в них полоску из-за одного лишь URL
  // было бы обиднее, чем лишний наблюдатель на пустой странице).
  const stopWatching = () => {
    state.watching = false;
    observer.disconnect();
    clearInterval(heartbeat);
    cancelPendingLayout();
    // Страница признана чужой — строк действий с временем на ней нет и не
    // будет, так что и второй наблюдатель уходит вместе с первым.
    cancelShortTime();
    stopTimeWatch();
  };
  state.giveUpTimer = setTimeout(() => {
    state.giveUpTimer = 0;
    if (state.editorFound || !state.alive) return;
    if (location.href.startsWith("https://claude.ai")) return;
    if (document.querySelector(".ProseMirror,.epitaxy-prompt,.epitaxy-titlebar,.epitaxy-composer-width")) return;
    stopWatching();
  }, GIVE_UP_MS);
  track(() => { if (state.giveUpTimer) { clearTimeout(state.giveUpTimer); state.giveUpTimer = 0; } });

  // ---- 17. Снятие экземпляра ---------------------------------------------
  const dispose = () => {
    state.alive = false;
    // Штатная высота редактора возвращается здесь: снимаем переменную, атрибуты
    // и свёрнутость. Дальше по реестру уходят подписки, наблюдатель, таймеры,
    // <style> и сама полоска.
    try { clearResizer(); } catch {}
    try {
      for (const node of document.querySelectorAll(`[${EDITOR_ROOT_ATTRIBUTE}],[${EDITOR_ATTRIBUTE}],[${BLOCK_ATTRIBUTE}]`)) {
        node.removeAttribute(EDITOR_ROOT_ATTRIBUTE);
        node.removeAttribute(EDITOR_ATTRIBUTE);
        node.removeAttribute(BLOCK_ATTRIBUTE);
        try { node.style.removeProperty(HEIGHT_VARIABLE); } catch {}
      }
    } catch {}
    if (state.dragging) {
      state.dragging = false;
      try {
        document.documentElement.style.cursor = "";
        document.documentElement.style.userSelect = "";
      } catch {}
    }
    for (const undo of undoList.splice(0).reverse()) { try { undo(); } catch {} }
  };

  const api = {
    version: VERSION,
    stages: { COLLAPSED: STAGE_COLLAPSED, NORMAL: STAGE_NORMAL, STRETCHED: STAGE_STRETCHED },
    dispose,
    setStage,
    get stage() { return state.stage; },
    // Для probe.js на гейте: видно, приехал ли инжект, применились ли стили
    // (CSP) и нашлось ли поле.
    status: () => ({
      version: VERSION,
      url: location.href,
      stage: state.stage,
      height: state.height,
      ceiling: state.ceiling,
      natural: state.natural,
      cssOk: state.cssOk,
      cssViolations: state.cssViolations,
      watching: state.watching,
      editor: Boolean(state.editor?.isConnected),
      shell: Boolean(state.shell?.isConnected),
      composerBlock: Boolean(state.composerBlock?.isConnected),
      modelRow: Boolean(state.modelRow?.isConnected),
      collapsedNodes: state.collapsedNodes.length,
      handleVisible: handle.style.display !== "none",
      handleCovered: state.handleCovered,
      layoutRuns: state.layoutRuns,
      mutationBatches: state.mutationBatches,
      mutationSkipped: state.mutationSkipped,
      scrollRuns: state.scrollRuns,
      timeRuns: state.timeRuns,
      timeWatched: Boolean(state.timeTarget),
      cashout: readCashout() != null,
    }),
  };
  window.__myclaude = api;
  track(() => { if (window.__myclaude === api) { try { delete window.__myclaude; } catch { window.__myclaude = undefined; } } });

  // Всё, что ниже, трогает живую страницу и может бросить на неготовой
  // разметке. Такое падение не должно оставлять в окне зомби: установка
  // откатывается целиком, а причина остаётся в окне для разбора.
  try {
    armCashoutWatch();
    // Первый проход по времени — сразу: те сообщения, что уже на экране, ждать
    // ближайшей мутации не должны.
    runShortTime();
    layout();
  } catch (error) {
    try { dispose(); } catch {}
    window.__myclaudeFailure = {
      at: new Date().toISOString(),
      message: String(error?.message ?? error),
      stack: String(error?.stack ?? "").slice(0, 900),
    };
    throw error;
  }

  return VERSION;
})();
