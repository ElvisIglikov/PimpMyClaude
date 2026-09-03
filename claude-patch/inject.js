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
// команды из приложения (событие window "myclaude-command"): collapse, expand,
// cashout, scroll, theme, status, workflow. И сокращает время под сообщениями
// («3 minutes ago» → «3 min ago»). Команда theme красит окно по палитре из
// claude-patch/themes.json (раздел «2а. Тема и шрифт чата»): тема живёт на ЧАТЕ
// (ключ `chat:<заголовок>`), у главного окна есть ещё и своя — она и остаётся,
// когда открыт новый чат; всё переживает перезапуск Claude. На нижней кромке
// рамки поля ввода рисуется полоса прогресса марафона воркфлоу по строке
// состояния из последнего ответа — по сегменту на воркфлоу, с подсказкой из
// сводки, присланной командой status (раздел «2б»). Команда workflow кладёт в
// поле ввода текст запуска и НЕ отправляет его (раздел «12а»).
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
  const VERSION = "wf9-a-2";

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
    // Кнопка «Workflow»: сколько раз вставляли текст запуска и чем кончилось
    // в последний раз (видно в status() на гейте).
    workflowRuns: 0,
    workflowResult: null,
    scheduled: false,
    rafId: 0,
    layoutTimer: 0,
    layoutAt: 0,
    layoutRuns: 0,
    mutationBatches: 0,
    mutationSkipped: 0,
  };

  // ---- 2а. Тема и шрифт чата ----------------------------------------------
  // Два независимых слоя, у каждого своя таблица стилей и своя ячейка в
  // хранилище: тема (цвета) и шрифт. Команда меняет тот слой, поле которого в
  // ней есть, — шрифт без темы окно не красит, тема без шрифта его не сбрасывает.
  //
  // С WF9 тема закреплена за ЧАТОМ, а не за окном: вернулся в разговор — вернулся
  // его цвет, в каком бы окне он ни открылся. У главного окна сверх того есть
  // своя тема (`main`) — ею красится всякий чат, у которого записи нет, поэтому
  // «Новый чат» и «Обкэшить» цвет окна не меняют. Смену чата ловит сторож
  // заголовка (watchChatTitle): страница при этом не перезагружается, и другого
  // признака у смены разговора нет.
  //
  // Тема — конструируемая таблица стилей (adoptedStyleSheets) с переменными
  // Claude, собранная из палитры шести цветов. Порт ElvisOS/Resources/claude-theme-manager.mjs
  // (хелперы normalizeHex/rgb/mix/hslTriple и generateThemeCss), урезанный:
  // без Epitaxy-блока Claude Code, без шкал --cds-gray/--cds-blue, без
  // --tw-prose и скроллбаров. Всё с !important — стили самого Claude авторские
  // и без !important, а claude.css лоадер вставляет как user-стили, и цветов в
  // нём нет: конфликта каскада не возникает.
  //
  // Раздел стоит здесь, а не в конце файла, намеренно: сохранённая тема обязана
  // вернуться в окно ДО того, как строится полоска ручки, иначе окно моргает
  // чужими цветами. Ручку, «Обкэшить» и прокрутку модуль не трогает — у него
  // свой узел и свои ключи хранилища myclaude-theme-*.
  const THEME_STYLE_ID = "myclaude-theme";
  // Тема и шрифт этого окна на время его жизни: sessionStorage у каждого окна
  // свой и переживает навигацию внутри окна (как высота поля выше).
  const THEME_SESSION_KEY = "myclaude-theme-v1";
  // Карта на перезапуск Claude: { main: запись главного окна, "w:<заголовок>":
  // запись подчинённого окна, "*": запись для всех }. localStorage у окон общий.
  const THEME_MAP_KEY = "myclaude-themes-v1";
  const THEME_ALL_KEY = "*";
  // Сторож заголовка: подчинённое окно («Open in new window») живёт на
  // about:blank и получает заголовок позже, чем выполняется инжект, а в главном
  // окне заголовок меняется на каждом чате. План просит опрос раз в секунду —
  // берём вдвое чаще, чтобы окно не моргало чужой темой (наблюдатель за <head>
  // ловит смену тем же кадром, опрос — только страховка).
  const THEME_TITLE_TICK_MS = 500;
  // Сколько ждём заголовка, чтобы дописать выбор, сделанный до его появления.
  const THEME_TITLE_WAIT_MS = 10000;
  const THEME_ROOT_SELECTOR =
    ':root, html, body, [data-mode], .cds-root, .dark, .light, .darkTheme, .lightTheme, .dframe-root';
  const THEME_PALETTE_KEYS = ["accent", "background", "foreground", "sidebar", "panel", "muted"];
  const THEME_FALLBACK = {
    dark: { accent: "#60a5fa", background: "#0b1020", foreground: "#e5edff", sidebar: "#070b16", panel: "#121a30", muted: "#91a0bf" },
    light: { accent: "#2563eb", background: "#ffffff", foreground: "#111827", sidebar: "#f3f4f6", panel: "#ffffff", muted: "#64748b" },
  };
  // Шрифт приходит голым именем семейства («SF Mono»), стек дописываем здесь:
  // так меню шлёт одно слово, а страница отвечает за то, чем это слово подпереть.
  const FONT_FAMILY_MAX = 60;
  const FONT_STACK_UI = "-apple-system, system-ui, sans-serif";
  const FONT_STACK_MONO = "ui-monospace, SFMono-Regular, Menlo, monospace";

  // Цветовая арифметика донора один в один: короткая запись #abc и запись с
  // альфой приводятся к шести знакам, остальное падает на запасной цвет.
  const normalizeHex = (value, fallback) => {
    let source = typeof value === "string" ? value.trim() : fallback;
    if (!/^#[0-9a-f]{3,8}$/i.test(source)) source = fallback;
    let hex = String(source).slice(1);
    if (![3, 4, 6, 8].includes(hex.length)) hex = String(fallback).slice(1);
    if (hex.length === 3 || hex.length === 4) hex = hex.split("").map(part => part + part).join("");
    return `#${hex.slice(0, 6).toLowerCase()}`;
  };
  const rgbOf = color => {
    const hex = normalizeHex(color, "#000000").slice(1);
    return [0, 2, 4].map(offset => Number.parseInt(hex.slice(offset, offset + 2), 16));
  };
  const hexOf = channels => `#${channels
    .map(value => Math.round(Math.max(0, Math.min(255, value))).toString(16).padStart(2, "0"))
    .join("")}`;
  const mixHex = (left, right, ratio) => {
    const from = rgbOf(left);
    const to = rgbOf(right);
    return hexOf(from.map((value, index) => value + (to[index] - value) * ratio));
  };
  // Переменные Claude хранят не цвет, а HSL-триплет «H S% L%»: страница сама
  // подставляет его в hsl(...) и добавляет прозрачность.
  const hslTriple = color => {
    const [red, green, blue] = rgbOf(color).map(value => value / 255);
    const max = Math.max(red, green, blue);
    const min = Math.min(red, green, blue);
    const lightness = (max + min) / 2;
    const delta = max - min;
    let hue = 0;
    let saturation = 0;
    if (delta !== 0) {
      saturation = delta / (1 - Math.abs(2 * lightness - 1));
      if (max === red) hue = 60 * (((green - blue) / delta) % 6);
      else if (max === green) hue = 60 * ((blue - red) / delta + 2);
      else hue = 60 * ((red - green) / delta + 4);
    }
    if (hue < 0) hue += 360;
    return `${hue.toFixed(3)} ${(saturation * 100).toFixed(3)}% ${(lightness * 100).toFixed(3)}%`;
  };

  // Тема приходит снаружи (command.json) и из хранилища, то есть текстом, за
  // который мы не отвечаем. Отсюда разбор: палитра — только шесть цветов и
  // только hex, имя и id — без знаков, которыми можно закрыть комментарий или
  // правило CSS. Не объект или нет палитры — темы нет вовсе.
  const themeText = (raw, fallback) => {
    const result = String(raw ?? "").replace(/[<>{};*\\/"']/g, " ").replace(/\s+/g, " ").trim().slice(0, 80);
    return result || fallback;
  };
  const normalizeTheme = value => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null;
    const palette = value.palette;
    if (!palette || typeof palette !== "object" || Array.isArray(palette)) return null;
    const type = value.type === "light" ? "light" : "dark";
    const base = THEME_FALLBACK[type];
    const clean = {};
    for (const key of THEME_PALETTE_KEYS) clean[key] = normalizeHex(palette[key], base[key]);
    return { id: themeText(value.id, "custom"), name: themeText(value.name, "Тема"), type, palette: clean };
  };

  const themeCss = theme => {
    const light = theme.type === "light";
    const base = THEME_FALLBACK[theme.type === "light" ? "light" : "dark"];
    const background = normalizeHex(theme.palette?.background, base.background);
    const foreground = normalizeHex(theme.palette?.foreground, base.foreground);
    const accent = normalizeHex(theme.palette?.accent, base.accent);
    const sidebar = normalizeHex(theme.palette?.sidebar, mixHex(background, foreground, 0.04));
    const panel = normalizeHex(theme.palette?.panel, mixHex(background, foreground, 0.06));
    const muted = normalizeHex(theme.palette?.muted, mixHex(foreground, background, 0.35));
    // Две ступени поверхностей над фоном: карточки, поповеры, поля.
    const surface1 = mixHex(background, foreground, light ? 0.025 : 0.045);
    const surface2 = mixHex(background, foreground, light ? 0.05 : 0.075);
    const border = mixHex(accent, background, 0.72);
    const accentHot = mixHex(accent, foreground, 0.20);
    return `/* PimpMyClaude · тема ${themeText(theme.name, "Тема")} · порт ElvisOS */
${THEME_ROOT_SELECTOR} {
  color-scheme: ${theme.type} !important;
  --accent-brand: ${hslTriple(accent)} !important;
  --accent-000: ${hslTriple(accent)} !important;
  --accent-100: ${hslTriple(mixHex(accent, background, 0.12))} !important;
  --accent-200: ${hslTriple(mixHex(accent, background, 0.30))} !important;
  --accent-900: ${hslTriple(mixHex(accent, background, 0.78))} !important;
  --accent-pro-000: ${hslTriple(accent)} !important;
  --accent-pro-100: ${hslTriple(mixHex(accent, background, 0.12))} !important;
  --accent-pro-200: ${hslTriple(mixHex(accent, background, 0.30))} !important;
  --accent-pro-900: ${hslTriple(mixHex(accent, background, 0.78))} !important;
  --bg-000: ${hslTriple(surface2)} !important;
  --bg-100: ${hslTriple(surface1)} !important;
  --bg-200: ${hslTriple(background)} !important;
  --bg-300: ${hslTriple(mixHex(background, light ? "#000000" : "#ffffff", 0.015))} !important;
  --bg-400: ${hslTriple(background)} !important;
  --bg-500: ${hslTriple(background)} !important;
  --text-000: ${hslTriple(foreground)} !important;
  --text-100: ${hslTriple(foreground)} !important;
  --text-200: ${hslTriple(mixHex(foreground, background, 0.15))} !important;
  --text-300: ${hslTriple(mixHex(foreground, background, 0.28))} !important;
  --text-400: ${hslTriple(mixHex(foreground, background, 0.42))} !important;
  --text-500: ${hslTriple(mixHex(foreground, background, 0.55))} !important;
  --border-100: ${hslTriple(mixHex(foreground, background, 0.25))} !important;
  --border-200: ${hslTriple(mixHex(foreground, background, 0.45))} !important;
  --border-300: ${hslTriple(mixHex(accent, background, 0.45))} !important;
  --border-400: ${hslTriple(accent)} !important;
  --oncolor-100: ${hslTriple(background)} !important;
  --oncolor-200: ${hslTriple(background)} !important;
  --oncolor-300: ${hslTriple(background)} !important;
  --claude-accent-clay: ${accent} !important;
  --claude-background-color: ${background} !important;
  --claude-foreground-color: ${foreground} !important;
  --claude-secondary-color: ${muted} !important;
  --claude-border-color: ${mixHex(accent, background, 0.55)} !important;
  --claude-text-color: ${foreground} !important;
  --claude-border: ${border} !important;
  --claude-border-300: ${border} !important;
  --claude-border-300-more: ${mixHex(accent, background, 0.50)} !important;
  --claude-text-100: ${foreground} !important;
  --claude-text-200: ${mixHex(foreground, background, 0.15)} !important;
  --claude-text-400: ${muted} !important;
  --claude-text-500: ${mixHex(muted, background, 0.22)} !important;
  --claude-description-text: ${muted} !important;
  --page-bg: ${background} !important;
  --surface-0: ${background} !important;
  --surface-1: ${panel} !important;
  --surface-2: ${surface2} !important;
  --surface-3: ${mixHex(panel, foreground, 0.04)} !important;
  --clay: ${accent} !important;
  --clay-emphasized: ${mixHex(accent, foreground, 0.24)} !important;
  --border: ${mixHex(accent, background, 0.72)} !important;
  --border-strong: ${mixHex(accent, background, 0.50)} !important;
  --border-stronger: ${mixHex(accent, background, 0.30)} !important;
  --border-accent: ${accent} !important;
  --bg-neutral: ${surface1} !important;
  --bg-neutral-hover: ${surface2} !important;
  --on-primary: ${background} !important;
  --on-accent: ${background} !important;
  --on-brand: ${background} !important;
  --ring-color: ${mixHex(accent, background, 0.42)} !important;
  --cds-page-bg: ${background} !important;
  --cds-surface-0: ${background} !important;
  --cds-surface-1: ${surface1} !important;
  --cds-surface-2: ${surface2} !important;
  --cds-surface-3: ${panel} !important;
  --cds-surface-panel: ${panel} !important;
  --cds-surface-popover: ${surface2} !important;
  --cds-text-primary: ${foreground} !important;
  --cds-text-secondary: ${muted} !important;
  --cds-text-muted: ${mixHex(muted, background, 0.22)} !important;
  --cds-text-accent: ${accent} !important;
  --cds-border: ${mixHex(accent, background, 0.72)} !important;
  --cds-border-strong: ${mixHex(accent, background, 0.50)} !important;
  --cds-border-stronger: ${mixHex(accent, background, 0.30)} !important;
  --cds-border-accent: ${accent} !important;
  --cds-clay: ${accent} !important;
  --cds-clay-emphasized: ${mixHex(accent, foreground, 0.24)} !important;
  --cds-fill-accent: ${accent} !important;
  --cds-fill-accent-hover: ${mixHex(accent, foreground, 0.20)} !important;
  --cds-fill-brand: ${accent} !important;
  --cds-fill-brand-hover: ${mixHex(accent, foreground, 0.20)} !important;
  --cds-fill-primary: ${foreground} !important;
  --cds-fill-primary-hover: ${mixHex(foreground, background, 0.12)} !important;
  --cds-fill-secondary: ${surface2} !important;
  --cds-fill-secondary-hover: ${panel} !important;
  --cds-fill-field: ${surface1} !important;
  --cds-fill-control: ${surface2} !important;
  --cds-fill-control-hover: ${panel} !important;
  --cds-fill-ghost-hover: ${mixHex(accent, background, 0.82)} !important;
  --cds-oncolor-200: ${background} !important;
  --cds-oncolor-300: ${background} !important;
  --surface-panel: ${panel} !important;
  --surface-popover: ${surface2} !important;
  --text-primary: ${foreground} !important;
  --text-secondary: ${muted} !important;
  --text-muted: ${mixHex(muted, background, 0.22)} !important;
  --fill-accent: ${accent} !important;
  --fill-accent-hover: ${accentHot} !important;
  --fill-brand: ${accent} !important;
  --fill-brand-hover: ${accentHot} !important;
  --fill-primary: ${accent} !important;
  --fill-primary-hover: ${accentHot} !important;
  --fill-secondary: ${surface2} !important;
  --fill-secondary-hover: ${panel} !important;
  --fill-field: ${panel} !important;
  --fill-control: ${surface2} !important;
  --fill-control-hover: ${mixHex(accent, background, 0.70)} !important;
  --fill-ghost-hover: ${mixHex(accent, background, 0.82)} !important;
  --df-z0: ${hslTriple(background)} !important;
  --df-z1: ${hslTriple(surface1)} !important;
  --df-z2: ${hslTriple(surface2)} !important;
  --df-z3: ${hslTriple(panel)} !important;
  --df-z4: ${hslTriple(mixHex(panel, foreground, 0.04))} !important;
  --df-z5: ${hslTriple(mixHex(panel, foreground, 0.08))} !important;
  --df-z6: ${hslTriple(mixHex(accent, background, 0.62))} !important;
  --df-bg-page-hsl: ${hslTriple(background)} !important;
  --df-bg-page: ${background} !important;
  --df-bg-sidebar: ${sidebar} !important;
  --df-sidebar-bg: ${sidebar} !important;
  --df-web-sidebar-bg: ${sidebar} !important;
  --df-surface-primary: ${panel} !important;
  --df-hover: ${mixHex(accent, background, 0.82)} !important;
  --df-selected: ${mixHex(accent, background, 0.70)} !important;
  --df-chip-bg: ${surface2} !important;
  --df-tray-hairline: ${mixHex(accent, background, 0.62)} !important;
}
html, body, #root, .dframe-root, .dframe-content, [class*="dframe-content"] { background: ${background} !important; color: ${foreground} !important; }
.dframe-sidebar, [class*="dframe-sidebar"], [data-testid*="sidebar"] { background-color: ${sidebar} !important; background-image: none !important; }
::selection { color: ${background} !important; background: ${accent} !important; }
input, textarea, select, [contenteditable="true"] { caret-color: ${accent} !important; }
${epitaxyCss({ type: theme.type, background, foreground, accent, panel, muted })}`;
  };

  // Окна Claude Code (Epitaxy) держат свою палитру на .epitaxy-root: серая шкала
  // --_gray-*, альфа-шкала --t*, ступени --z*, поверхности поля ввода
  // (--surface-prompt-*, --prompt-*). Без этого блока поле ввода и панели Code
  // остаются серыми при любой теме. Порт epitaxyThemeCss из ElvisOS, без шрифтов.
  const EPITAXY_GRAY_LEVELS = [0, 10, 30, 60, 90, 100, 150, 300, 450, 500, 600, 650, 700, 750, 800, 830, 860, 890, 900];
  const EPITAXY_T_ALPHA = {
    light: [0, 0.04, 0.06, 0.1, 0.16, 0.25, 0.5, 0.8, 0.9, 1],
    dark: [0, 0.04, 0.08, 0.12, 0.16, 0.25, 0.48, 0.7, 0.8, 1],
  };
  const epitaxyCss = ({ type, background, foreground, accent, panel, muted }) => {
    const light = type === "light";
    const lightEnd = light ? background : foreground;
    const darkEnd = light ? foreground : background;
    const grayScale = EPITAXY_GRAY_LEVELS
      .map(level => `  --_gray-${level}: ${hslTriple(mixHex(lightEnd, darkEnd, level / 900))} !important;`).join("\n");
    const ink = hslTriple(foreground);
    const tScale = EPITAXY_T_ALPHA[light ? "light" : "dark"]
      .map((alpha, index) => `  --t${index}: hsl(${ink} / ${alpha}) !important;`).join("\n");
    const zColors = [
      background, mixHex(background, panel, 0.55), panel, mixHex(panel, foreground, 0.04),
      mixHex(panel, foreground, 0.08), mixHex(panel, foreground, 0.13), mixHex(foreground, background, light ? 0.45 : 0.3),
    ];
    const zScale = zColors.map((color, index) => `  --z${index}: ${color} !important;`).join("\n");
    const promptBorder = mixHex(accent, background, 0.55);
    const promptFocusBorder = mixHex(accent, background, 0.32);
    return `/* Claude Code · Epitaxy */
.epitaxy-root, [data-mode="dark"] .epitaxy-root, [data-mode="light"] .epitaxy-root {
${grayScale}
${tScale}
${zScale}
  --_brand-clay: ${hslTriple(accent)} !important;
  --accent: ${accent} !important;
  --accent-hover: ${mixHex(accent, foreground, 0.14)} !important;
  --accent-brand: ${accent} !important;
  --accent-20-brightness: ${mixHex(accent, background, 0.72)} !important;
  --surface-primary: ${background} !important;
  --surface-primary-elevated: ${background}f0 !important;
  --surface-hud: ${background}f2 !important;
  --surface-panel: ${panel} !important;
  --surface-panel-elevated: ${mixHex(panel, foreground, 0.04)} !important;
  --surface-popover: ${mixHex(panel, foreground, 0.03)} !important;
  --surface-popover-elevated: ${mixHex(panel, foreground, 0.06)} !important;
  --surface-toast: ${mixHex(panel, foreground, 0.08)} !important;
  --surface-prompt-blur: ${panel} !important;
  --surface-prompt-focus-hover: ${mixHex(panel, foreground, 0.05)} !important;
  --prompt-compact-bg: ${panel} !important;
  --prompt-compact-bg-focus: ${mixHex(panel, foreground, 0.05)} !important;
  --prompt-blur-inner-color: ${promptBorder} !important;
  --prompt-blur-outer-color: ${promptBorder} !important;
  --prompt-focus-inner-color: ${promptFocusBorder} !important;
  --prompt-focus-outer-color: ${promptFocusBorder} !important;
  --fill-primary-hover: ${mixHex(foreground, background, 0.12)} !important;
  --text-muted: hsl(${hslTriple(muted)} / 0.62) !important;
  --ui-tooltip-fill: ${mixHex(panel, foreground, 0.08)} !important;
  --ui-tooltip-text: ${foreground} !important;
}
.epitaxy-root ::placeholder { color: ${muted} !important; -webkit-text-fill-color: ${muted} !important; opacity: 0.78 !important; }
.epitaxy-root [data-theme="claude"] { --accent-brand: ${hslTriple(accent)} !important; }
`;
  };

  // Шрифт — свой слой, со своим разбором. Имя семейства попадает в CSS внутрь
  // кавычек, поэтому белый список жёстче темы: только буквы, цифры, пробел и
  // дефис — ни кавычки, ни точки с запятой, ни звёздочки в имени не будет.
  const normalizeFont = value => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null;
    if (typeof value.family !== "string") return null;
    const family = value.family
      .replace(/[^A-Za-z0-9 -]/g, " ").replace(/\s+/g, " ").trim().slice(0, FONT_FAMILY_MAX).trim();
    if (!family) return null;
    return { id: themeText(value.id, family), family, mono: value.mono === true };
  };

  // Отдельная таблица стилей (см. fontSheet ниже): шрифт без темы окно не
  // красит, тема без шрифта его не сбрасывает.
  const fontCss = font => {
    const stack = `"${font.family}", ${font.mono ? FONT_STACK_MONO : FONT_STACK_UI}`;
    // mono:true — тем же шрифтом и код; mono:false — моно-переменные не трогаем,
    // иначе пропорциональный шрифт уехал бы в блоки кода и таблицы.
    const monoVariables = font.mono ? `
  --font-mono: var(--claude-themes-ui-font) !important;
  --cds-font-mono: var(--claude-themes-ui-font) !important;
  --family-monospace: var(--claude-themes-ui-font) !important;` : "";
    const monoRule = font.mono
      ? "\ncode, pre, kbd, samp { font-family: var(--claude-themes-ui-font) !important; }"
      : "";
    return `/* PimpMyClaude · шрифт ${font.family} */
${THEME_ROOT_SELECTOR} {
  --claude-themes-ui-font: ${stack} !important;
  --font-sans: var(--claude-themes-ui-font) !important;
  --font-serif: var(--claude-themes-ui-font) !important;
  --font-system: var(--claude-themes-ui-font) !important;
  --cds-font-sans: var(--claude-themes-ui-font) !important;
  --cds-font-system: var(--claude-themes-ui-font) !important;
  --cds-font-voice: var(--claude-themes-ui-font) !important;
  --default-font-family: var(--claude-themes-ui-font) !important;
  --family-ui: var(--claude-themes-ui-font) !important;
  --font-ui: var(--claude-themes-ui-font) !important;
  --font-claude-response: var(--claude-themes-ui-font) !important;${monoVariables}
}
body, button, input, textarea, select, h1, h2, h3, h4, h5, h6, p, label, li, td, th, .font-claude-response-body, .font-claude-response-title, .font-claude-response, [data-user-message-bubble] { font-family: var(--claude-themes-ui-font) !important; }${monoRule}
`;
  };

  // Ключи хранилища (WF9, п. 6): тема живёт на ЧАТЕ, а не на окне. Заголовок
  // окна — это и есть имя чата, поэтому ключ `chat:<заголовок>` одинаково годен
  // и главному окну (заголовок меняется с каждым чатом), и подчинённому («Open
  // in new window», заголовок постоянный). Сверх того у главного окна есть
  // ключ `main` — «тема этого окна вообще»: чат без своей записи (новый чат,
  // окно после «Обкэшить») цвет не меняет: на смене заголовка окно применяет
  // только запись нового чата, а нет её — не трогает ничего.
  // `w:<заголовок>` — записи подчинённых окон до WF9; читаются как `chat:` и при
  // первой же записи переносятся (контракт WF9). Ключ СЕССИИ, в отличие от
  // ключей карты, всегда оконный (`main`/`w:<заголовок>`): сессия обязана
  // пережить смену чата в окне (см. sessionKey).
  // Красим только окна Claude: claude.ai (главное) и about:blank («Open in new
  // window»). Артефакты, браузерная панель (data:) и file: — не наши.
  const themable = /^(https:\/\/claude\.ai\/|about:blank)/.test(location.href);
  const THEME_MAIN_KEY = "main";
  const THEME_CHAT_PREFIX = "chat:";
  const THEME_LEGACY_PREFIX = "w:";
  const isMainWindow = () => themable && location.href.includes("claude.ai");
  // Заголовки-заглушки. Пока у разговора нет имени, окно зовётся «Claude» или
  // «New chat», и такой заголовок носят РАЗНЫЕ чаты во всех окнах разом. Ключа
  // чата у заглушки нет вовсе — ни на чтение, ни на запись: иначе выбор темы в
  // безымянном чате красил бы каждый новый чат в каждом окне (разбор критика,
  // п. 3). Тема такого окна живёт в `main` и в сессии.
  const THEME_TITLE_STUBS = new Set(["claude", "new chat", "новый чат"]);
  const windowTitle = () => (document.title || "").trim();
  // Заголовка ещё нет (about:blank сразу после открытия) — ключа чата нет, ждём
  // его (см. watchChatTitle).
  const chatKey = () => {
    if (!themable) return null;
    const title = windowTitle();
    if (!title || THEME_TITLE_STUBS.has(title.toLowerCase())) return null;
    return `${THEME_CHAT_PREFIX}${title}`;
  };
  // Ключ СЕССИИ — по окну, а не по чату: главное окно `main`, подчинённое
  // `w:<заголовок>` (его заголовок при жизни окна не меняется). Сессия обязана
  // пережить смену чата: с ключом чата этот слой умирал бы на каждом ⌘N, а
  // заведён он ровно ради «пока окно живо, оно того цвета, что выбрали».
  const sessionKey = () => {
    if (!themable) return null;
    if (isMainWindow()) return THEME_MAIN_KEY;
    const title = windowTitle();
    return title ? `${THEME_LEGACY_PREFIX}${title}` : null;
  };
  // Ключ ХРАНИЛИЩА окна: чат, а у главного окна без имени чата — `main`.
  const themeKey = () => chatKey() ?? (isMainWindow() ? THEME_MAIN_KEY : null);
  const readThemeMap = () => {
    try {
      const raw = localStorage.getItem(THEME_MAP_KEY);
      const data = raw ? JSON.parse(raw) : null;
      return data && typeof data === "object" && !Array.isArray(data) ? data : {};
    } catch { return {}; }
  };
  const writeThemeMap = map => {
    try {
      if (!map || Object.keys(map).length === 0) localStorage.removeItem(THEME_MAP_KEY);
      else localStorage.setItem(THEME_MAP_KEY, JSON.stringify(map));
    } catch {}
  };
  // Слоёв два, и каждый хранится трёхзначно: объект — значение, "none" — явный
  // сброс («Как у Claude» это тоже выбор, иначе окно на следующем инжекте
  // покрасилось бы обратно из карты), поля нет — слоя не касались. Поэтому
  // запись окна — объект { theme, font }, а не одна тема, как было в WF5.
  const THEME_LAYERS = ["theme", "font"];
  const LAYER_NORMALIZE = { theme: normalizeTheme, font: normalizeFont };
  // Старый формат WF5 читается обязательно: в живых окнах уже лежат записи, где
  // тема стоит на верхнем уровне, и строки "none". Без этого перевода окна
  // потеряли бы темы на первом же инжекте новой версии.
  const themeEntry = value => {
    if (value === "none") return { theme: "none" };
    if (!value || typeof value !== "object" || Array.isArray(value)) return {};
    if (value.palette) return { theme: value };
    const entry = {};
    for (const layer of THEME_LAYERS) if (layer in value) entry[layer] = value[layer];
    return entry;
  };
  // Слой записи: undefined — слоя нет (не трогаем), null — сброс, объект —
  // значение. Мусор в слое равен его отсутствию: пусть решает следующий уровень.
  const entryLayer = (entry, layer) => {
    if (!entry || !(layer in entry)) return undefined;
    const raw = entry[layer];
    if (raw === "none" || raw == null) return null;
    return LAYER_NORMALIZE[layer](raw) ?? undefined;
  };
  // Ключ старого образца для ключа чата: `chat:Vkusnoff` → `w:Vkusnoff`.
  const legacyKey = key =>
    (typeof key === "string" && key.startsWith(THEME_CHAT_PREFIX)
      ? THEME_LEGACY_PREFIX + key.slice(THEME_CHAT_PREFIX.length)
      : null);
  // Запись карты по ключу. Записи подчинённых окон до WF9 лежат под `w:<title>`,
  // и читаются они как запись чата — иначе окна Элвиса потеряли бы темы на
  // первом же инжекте новой версии.
  const mapEntry = (map, key) => {
    if (!key) return null;
    if (map[key] !== undefined) return themeEntry(map[key]);
    const legacy = legacyKey(key);
    return legacy != null && map[legacy] !== undefined ? themeEntry(map[legacy]) : null;
  };

  // Годится ли сессия этому окну. Свой ключ у неё оконный (`main`/`w:<заголовок>`),
  // но в живых окнах лежат записи и от wf9-a-1, где ключом был чат. Принимаем и
  // их — пока окно в том же разговоре, — чтобы окна Элвиса не моргнули чужим
  // цветом на первом инжекте новой версии. Перекрыть запись чата такая сессия
  // больше не может: она стоит В ПОРЯДКЕ восстановления ниже (см. restoreTheme).
  const sameSessionKey = (stored) => {
    if (typeof stored !== "string" || stored === "") return false;
    const key = sessionKey();
    if (key && stored === key) return true;
    const chat = chatKey();
    if (chat && stored === chat) return true;
    return stored === THEME_MAIN_KEY && isMainWindow();
  };
  // Запись привязана к ключу окна: окно «Open in new window» — попап, и по
  // спецификации HTML оно стартует с КОПИЕЙ sessionStorage главного окна.
  // Без ключа подчинённое окно красилось бы темой главного.
  const readSessionEntry = () => {
    try {
      const raw = sessionStorage.getItem(THEME_SESSION_KEY);
      if (raw == null) return null;
      const record = JSON.parse(raw);
      if (!record || typeof record !== "object" || Array.isArray(record) || !record.key) return null;
      if (!sameSessionKey(record.key)) return null;
      // Сессия старого формата — { key, theme }: слоя font в ней нет, и шрифта
      // у окна тоже нет. Именно это и значит «поля нет».
      return themeEntry(record);
    } catch { return null; }
  };
  const storeSessionLayers = layers => {
    try {
      // Слой, которого команда не касалась, остаётся в записи как был.
      const record = { key: sessionKey(), ...(readSessionEntry() ?? {}) };
      for (const layer of THEME_LAYERS) {
        if (layer in layers) record[layer] = layers[layer] ?? "none";
      }
      sessionStorage.setItem(THEME_SESSION_KEY, JSON.stringify(record));
    } catch {}
  };

  // previewing — окно сейчас показывает предпросмотр (мышь ведут по подменю), и
  // в хранилище лежит не то, что на экране: см. runThemeCommand.
  // chatKey — заголовок, под который окно уже покрашено: сторож (watchChatTitle)
  // сверяет его с нынешним и на смене чата перекрашивает окно. pending — выбор,
  // сделанный до появления заголовка: дописываем его, когда ключ чата появится.
  const themeState = {
    theme: null, source: null, font: null, fontSource: null, previewing: false,
    chatKey: null, chatTimer: 0, chatObserver: null, pending: null, pendingUntil: 0,
  };
  // Тема — конструируемая таблица стилей (adoptedStyleSheets), а не <style> в
  // <head>: Claude зеркалит <style> из главного окна во все попапы «Open in new
  // window» (проверено живьём 03.09: тема главного окна появилась во всех
  // подчинённых). Adopted-таблицы — не DOM-узлы, зеркало их не видит, а в
  // каскаде они идут после таблиц документа и при равной силе побеждают.
  const themeSheet = new CSSStyleSheet();
  // Шрифт — вторая таблица, независимая от первой: сменить шрифт, не тронув
  // цвета, и наоборот. Одной таблицей это не выходит — её пришлось бы
  // перегенерировать целиком на каждую половину.
  const fontSheet = new CSSStyleSheet();
  const detachSheet = sheet => {
    try { document.adoptedStyleSheets = document.adoptedStyleSheets.filter(item => item !== sheet); } catch {}
  };
  const adoptSheet = sheet => {
    try {
      document.adoptedStyleSheets = [...document.adoptedStyleSheets.filter(item => item !== sheet), sheet];
      return true;
    } catch { return false; }
  };
  track(() => { detachSheet(themeSheet); detachSheet(fontSheet); });
  // Сироты от прежней реализации (<style id=…>, в том числе зеркальные копии).
  for (const orphan of document.querySelectorAll(`#${THEME_STYLE_ID}`)) orphan.remove();

  const removeTheme = source => {
    detachSheet(themeSheet);
    try { themeSheet.replaceSync(""); } catch {}
    themeState.theme = null;
    themeState.source = source ?? null;
  };
  const applyTheme = (theme, source) => {
    const clean = normalizeTheme(theme);
    if (!clean) { removeTheme(source); return null; }
    try { themeSheet.replaceSync(themeCss(clean)); } catch { return null; }
    if (!adoptSheet(themeSheet)) return null;
    themeState.theme = clean;
    themeState.source = source ?? null;
    return clean;
  };
  // Другой шрифт — другая высота строки, а обычная высота поля закэширована
  // (state.natural, раздел 9). Без сброса кэша ручка осталась бы стоять по
  // старому замеру, а поле — прежней высоты.
  const refreshAfterFont = () => {
    state.natural = null;
    try { scheduleLayout(); } catch {}
  };
  const removeFont = source => {
    detachSheet(fontSheet);
    try { fontSheet.replaceSync(""); } catch {}
    themeState.font = null;
    themeState.fontSource = source ?? null;
    refreshAfterFont();
  };
  const applyFont = (font, source) => {
    const clean = normalizeFont(font);
    if (!clean) { removeFont(source); return null; }
    try { fontSheet.replaceSync(fontCss(clean)); } catch { return null; }
    if (!adoptSheet(fontSheet)) return null;
    themeState.font = clean;
    themeState.fontSource = source ?? null;
    refreshAfterFont();
    return clean;
  };
  const applyLayer = (layer, value, source) => {
    if (layer === "font") { if (value) applyFont(value, source); else removeFont(source); return; }
    if (value) applyTheme(value, source); else removeTheme(source);
  };
  const applyLayers = (layers, source) => {
    for (const layer of THEME_LAYERS) if (layer in layers) applyLayer(layer, layers[layer], source);
  };

  // Порядок восстановления у КАЖДОГО слоя свой: запись чата (`chat:<заголовок>`)
  // → своя сессия окна → у главного окна запись окна (`main`) → запись «для
  // всех». Чат стоит ПЕРВЫМ нарочно: сессия у окна одна на все разговоры, и
  // стоя выше она перекрывала бы цвет чата, в который окно только что вернулось
  // (разбор критика, п. 2). Тема у окна своя, а шрифт общий — законная пара,
  // поэтому слои и разведены. Явный сброс («none») сильнее следующего уровня и
  // переживает перезапуск. Возвращает true, когда ждать больше нечего (ключ уже
  // известен). clear=true — «конец предпросмотра»: слой, которого в хранилище
  // нет, надо не оставить как есть (на экране сейчас примеренные цвета), а
  // снять. Смена чата сюда не ходит — у неё свой путь, applyChatEntry.
  const restoreTheme = (clear, onlyLayers) => {
    if (!themable) return true;
    const session = readSessionEntry();
    const map = readThemeMap();
    const chat = mapEntry(map, chatKey());
    // Запись окна берёт только главное окно: у подчинённого своего `main` нет,
    // и чужой он не касается.
    const own = isMainWindow() ? mapEntry(map, THEME_MAIN_KEY) : null;
    const all = themeEntry(map[THEME_ALL_KEY]);
    for (const layer of (onlyLayers ?? THEME_LAYERS)) {
      const fromChat = entryLayer(chat, layer);
      if (fromChat !== undefined) { applyLayer(layer, fromChat, "chat"); continue; }
      const fromSession = entryLayer(session, layer);
      if (fromSession !== undefined) { applyLayer(layer, fromSession, "session"); continue; }
      const fromWindow = entryLayer(own, layer);
      if (fromWindow !== undefined) { applyLayer(layer, fromWindow, "window"); continue; }
      const fromAll = entryLayer(all, layer);
      if (fromAll !== undefined) applyLayer(layer, fromAll, "all");
      else if (clear) applyLayer(layer, null, null);
    }
    return themeKey() != null;
  };

  // Запись по ключу и по слоям. Сброс пишем маркером "none" только когда у ЭТОГО
  // слоя есть запись «для всех» — иначе запись лишняя. Пустая запись не хранится.
  // Основа записи — mapEntry: у ключа чата это может быть старая запись `w:`, и
  // взять её обязательно, иначе перенос потерял бы второй слой.
  const setMapLayers = (map, key, layers) => {
    const entry = mapEntry(map, key) ?? {};
    const all = themeEntry(map[THEME_ALL_KEY]);
    for (const layer of THEME_LAYERS) {
      if (!(layer in layers)) continue;
      if (layers[layer]) entry[layer] = layers[layer];
      else if (entryLayer(all, layer)) entry[layer] = "none";
      else delete entry[layer];
    }
    if (Object.keys(entry).length) map[key] = entry; else delete map[key];
    // Перенос старой записи: всё, что в ней было, уже в entry.
    const legacy = legacyKey(key);
    if (legacy != null) delete map[legacy];
  };

  // Куда пишется выбор «тема этого окна»: запись чата — её увидит любое окно с
  // этим разговором, — и у главного окна ещё и `main`, чтобы окно «в целом»
  // помнило цвет и не теряло его на новом чате. У безымянного чата ключа нет
  // (chatKey отдаёт null на заголовках-заглушках), и выбор ложится только в
  // `main` да в сессию — иначе он достался бы всем безымянным чатам разом.
  const writeKeys = () => {
    const keys = [];
    const chat = chatKey();
    if (chat) keys.push(chat);
    if (isMainWindow()) keys.push(THEME_MAIN_KEY);
    return keys;
  };
  const writeLayers = layers => {
    const keys = writeKeys();
    if (keys.length) {
      const map = readThemeMap();
      for (const key of keys) setMapLayers(map, key, layers);
      writeThemeMap(map);
    }
    storeSessionLayers(layers);
  };
  // Выбор сделан до того, как у окна появился заголовок (about:blank сразу после
  // открытия) или пока чат ещё безымянный: записываем, когда ключ чата появится,
  // но не дольше десяти секунд — дальше это уже не «тот самый выбор». Заголовок-
  // заглушка ключом не считается, и ждать под ней нечего — она не запись чата.
  const flushPendingLayers = () => {
    const layers = themeState.pending;
    if (!layers) return;
    if (now() > themeState.pendingUntil) { themeState.pending = null; return; }
    if (!chatKey()) return;
    themeState.pending = null;
    writeLayers(layers);
  };

  const stopChatWatch = () => {
    if (themeState.chatTimer) { clearInterval(themeState.chatTimer); themeState.chatTimer = 0; }
    if (themeState.chatObserver) {
      try { themeState.chatObserver.disconnect(); } catch {}
      themeState.chatObserver = null;
    }
  };
  track(stopChatWatch);
  // Смена чата в главном окне — это смена document.title, больше ничего: страница
  // не перезагружается, инжект заново не приходит. Поэтому за заголовком следим
  // всё время жизни окна и на каждую смену перечитываем хранилище. В подчинённом
  // окне тот же сторож ловит момент, когда заголовок наконец появился.
  //
  // Применяем ТОЛЬКО то, что записано у нового чата, и только те слои, которые в
  // записи есть. Записи нет — на экране не трогаем ничего: ⌘N и «Обкэшить»
  // открывают чат без записи, и окно обязано остаться того же цвета (слово
  // Элвиса; разбор критика, п. 3). Полное восстановление тут не годится — оно
  // перекрасило бы окно из `main`/«для всех» на каждом новом чате.
  const applyChatEntry = () => {
    const entry = mapEntry(readThemeMap(), chatKey());
    if (!entry) return;
    for (const layer of THEME_LAYERS) {
      const value = entryLayer(entry, layer);
      if (value !== undefined) applyLayer(layer, value, "chat");
    }
  };
  const syncChatTheme = () => {
    if (!state.alive || !themable) return;
    const key = chatKey();
    if (key === themeState.chatKey) return;
    themeState.chatKey = key;
    // Сначала дописываем несохранённый выбор: иначе восстановление затрёт на
    // экране только что выбранную тему.
    flushPendingLayers();
    // Пока идёт предпросмотр, на экране намеренно не то, что в хранилище.
    if (themeState.previewing) return;
    try { applyChatEntry(); } catch {}
  };
  const watchChatTitle = () => {
    stopChatWatch();
    themeState.chatKey = chatKey();
    if (!themable) return;
    // Наблюдатель ловит смену заголовка тем же кадром, опрос — страховка на
    // случай, когда <title> подменили целиком или наблюдатель не встал.
    try {
      const host = document.head ?? null;
      if (host && typeof MutationObserver === "function") {
        const watcher = new MutationObserver(() => { try { syncChatTheme(); } catch {} });
        watcher.observe(host, { childList: true, subtree: true, characterData: true });
        themeState.chatObserver = watcher;
      }
    } catch { themeState.chatObserver = null; }
    themeState.chatTimer = setInterval(() => {
      if (!state.alive) { stopChatWatch(); return; }
      try { syncChatTheme(); } catch {}
    }, THEME_TITLE_TICK_MS);
  };

  // Окно адресуют заголовком, как в «Обкэшить»; заголовка нет — берёт окно под
  // фокусом. Подчинённое окно (about:blank) себя в фокусе может и не считать.
  const addressed = detail => {
    const title = typeof detail.title === "string" ? detail.title.trim() : "";
    return title ? (document.title || "").trim() === title : document.hasFocus();
  };

  // Команда меню: {action:"theme", scope:"window"|"all", title, preview, theme|null, font|null}.
  // Поля слоя нет — слой не трогаем, null — сброс слоя, объект — применить.
  // «Для всех» перекрывает СВОЙ слой у всех окон и чужой не трогает: «шрифт
  // всем» не снимает тем у окон, «тема всем» не снимает их шрифтов.
  // «Для окна» адресуется заголовком, как «Обкэшить».
  // Примерка была, а закрепили не все слои: остальные — назад из хранилища.
  const endPreviewExcept = committedLayers => {
    if (!themeState.previewing) return;
    themeState.previewing = false;
    const rest = THEME_LAYERS.filter(layer => !committedLayers.includes(layer));
    if (rest.length) restoreTheme(true, rest);
  };

  const runThemeCommand = detail => {
    if (!themable || !detail || typeof detail !== "object") return false;
    const layers = {};
    for (const layer of THEME_LAYERS) {
      if (layer in detail) layers[layer] = LAYER_NORMALIZE[layer](detail[layer]);
    }
    // Предпросмотр (мышь ведут по подменю тем и шрифтов): слои из команды идут
    // ТОЛЬКО в таблицы стилей, хранилища они не касаются вовсе — иначе проход
    // по списку записал бы в карту каждую тему, мимо которой проехала мышь.
    // Предпросмотр всегда адресован одному окну, scope тут не при чём.
    if (detail.preview === true) {
      if (Object.keys(layers).length === 0 || !addressed(detail)) return false;
      applyLayers(layers, "preview");
      themeState.previewing = true;
      return true;
    }
    // Конец предпросмотра: меню закрылось, ничего не выбрав. Оба слоя
    // возвращаем из хранилища, а слой, записи о котором нигде нет, снимаем.
    if (detail.preview === false && Object.keys(layers).length === 0) {
      if (!addressed(detail)) return false;
      restoreTheme(true);
      themeState.previewing = false;
      return true;
    }
    if (Object.keys(layers).length === 0) return false;
    if (detail.scope === "all") {
      const map = readThemeMap();
      const next = {};
      for (const [entryKey, value] of Object.entries(map)) {
        if (entryKey === THEME_ALL_KEY) continue;
        const entry = themeEntry(value);
        // Свой слой у окна снимаем — теперь его задаёт общая запись.
        for (const layer of Object.keys(layers)) delete entry[layer];
        if (Object.keys(entry).length) next[entryKey] = entry;
      }
      const all = themeEntry(map[THEME_ALL_KEY]);
      for (const [layer, value] of Object.entries(layers)) {
        if (value) all[layer] = value; else delete all[layer];
      }
      if (Object.keys(all).length) next[THEME_ALL_KEY] = all;
      writeThemeMap(next);
      storeSessionLayers(layers);
      // Закрепление гасит предпросмотр: слой, которого в команде нет, возвращаем из
      // хранилища (примерили тему, закрепили шрифт — тема не должна зависнуть).
      endPreviewExcept(Object.keys(layers));
      applyLayers(layers, "all");
      return true;
    }
    if (!addressed(detail)) return false;
    endPreviewExcept(Object.keys(layers));
    writeLayers(layers);
    applyLayers(layers, "window");
    // Ключа чата ещё нет (about:blank без заголовка): запись чата дописываем,
    // когда заголовок появится (см. syncChatTheme).
    if (!chatKey()) {
      themeState.pending = layers;
      themeState.pendingUntil = now() + THEME_TITLE_WAIT_MS;
    }
    return true;
  };

  // Осечка темы не должна утащить за собой ручку: раздел стоит выше её
  // постройки, и без этой обёртки любое падение на неготовой разметке оставило
  // бы окно вовсе без полоски.
  try { restoreTheme(); watchChatTitle(); } catch {}

  // ---- 2б. Полоса прогресса воркфлоу --------------------------------------
  // Тонкая светящаяся линия на нижней кромке рамки поля ввода: насколько прошёл
  // марафон воркфлоу. Вид взят у «полосы кэша» донора ElvisOS
  // (Resources/claude-chat-cleaner-inject.js): две точки высотой, свечение двумя
  // тенями, ширина едет плавно.
  //
  // WF9 (полоска v2): линия разбита на сегменты — по одному на воркфлоу марафона
  // («WF N из M»), зазор 3 точки. Готовые полные, текущий залит на свои проценты,
  // будущие — пустой контур. Место тоже другое: ровно низ рамки поля
  // (.epitaxy-prompt или тот её потомок, который рамку и рисует), а не верх
  // строки инструментов — между ними бывает зазор, и полоса висела в воздухе.
  //
  // Источник — сам чат, а не хранилище: последняя строка состояния в ответах
  // ассистента («💭⚪[Проект](docs/status.md) · WF 6 из 7 · 40%💭», формат из
  // SkilZZZ/AGENTS.md). Поэтому каждое окно считает по своему разговору, ничего
  // не хранит и ни с кем не синхронизируется.
  //
  // Строки состояния нет — полосы нет вовсе (довод донора): пустая полоса
  // утверждала бы «марафон только начался» ровно там, где марафона нет.
  //
  // Подсказка — свой div, а не title: у полосы pointer-events:none (иначе она
  // ловила бы клики по полю ввода), а без указателя title не показывается вовсе.
  // По той же причине наведение ловится общим mousemove по документу, а не
  // прозрачной накладкой над линией: накладка стояла бы поверх низа поля ввода и
  // съедала клики по нему.
  //
  // Отступление от плана: полоса не absolute внутри блока ввода, а fixed по
  // координатам — как и сама ручка. Довод записан в разделе 4 прямым текстом:
  // рамка поля живёт в чужом дереве, и свой узел туда лучше не вставлять. React
  // пересобирает низ окна на каждую смену модели, а position:absolute потребовал
  // бы ещё и менять position у чужого контейнера. Место на экране от этого не
  // меняется: считаем его по boundingClientRect рамки поля.
  const PROGRESS_ID = "myclaude-progress-bar";
  const PROGRESS_TIP_ID = "myclaude-progress-tip";
  // Ширина едет 400 мс: быстрее — дёрганье на каждом ответе, медленнее — полоса
  // заметно отстаёт от цифры в чате.
  const PROGRESS_MOVE_MS = 400;
  // Перечитывать ленту чаще раза в секунду незачем: строка состояния меняется
  // раз в ответ, а innerText сообщения — это принудительный reflow.
  const PROGRESS_MIN_GAP = 1000;
  // Страховочный перечёт: в тихом окне мутаций ленты может не быть вовсе.
  const PROGRESS_IDLE_MS = 10000;
  // Сколько последних ответов просматриваем. Строку состояния пишет каждый
  // ответ, поэтому дальше десятка забираться незачем, а перечитывать весь
  // длинный разговор раз в секунду — уже заметная работа.
  const PROGRESS_LOOKBACK = 12;
  const PROGRESS_ACCENT_FALLBACK = "#8b5cf6";
  // Цвет ТЕКУЩЕГО сегмента по состоянию: ждём Элвиса — жёлтый, упало — красный;
  // «идёт» и «готово» берут акцент темы окна (её красит раздел 2а). Готовые и
  // будущие сегменты всегда в акценте: красным метится ровно то место, где
  // марафон встал.
  const PROGRESS_PAINT = { wait: "#f5c542", fail: "#ef4444" };
  // Зазор между сегментами и их предельное число. Марафон длиннее сорока
  // воркфлоу — уже не марафон, а полоса из одних зазоров.
  const PROGRESS_SEG_GAP = 3;
  const PROGRESS_SEG_MAX = 40;
  // Уже трёх точек сегмент не читается: тогда рисуем одну сплошную долю.
  const PROGRESS_SEG_MIN = 6;
  // Высота линии и высота зоны наведения над ней.
  const PROGRESS_BAR_HEIGHT = 2;
  const PROGRESS_HOVER_ZONE = 10;
  // Уже этого якорь считается вырожденным: React как раз пересобирает низ окна,
  // и рамка на кадр съезжает в ноль. Тогда полоса садится на запасной якорь.
  const PROGRESS_MIN_WIDTH = 80;

  // >>> разбор строки состояния (кусок вырезает скретч-тест по этим маркерам)
  // Значки состояния из шаблона строки. Порядок — старшинство: 🛑 сильнее ✋,
  // ✋ сильнее ✅, ✅ сильнее 💭. Шаблон несёт один и тот же значок по краям,
  // поэтому спорить им обычно не о чем; старшинство решает те случаи, когда в
  // строку попало два разных.
  const PROGRESS_STATES = [["🛑", "fail"], ["✋", "wait"], ["✅", "done"], ["💭", "run"]];
  // «WF 6 из 7 · 40%»: счёт марафона и процент текущего воркфлоу. Процента может
  // не быть (готовый воркфлоу пишется без него). «WF» — тоже необязательно, но
  // без него счёт засчитывается только рядом с ✅: «5 из 5» без значка — это
  // обычная фраза из ответа, а не строка состояния.
  const PROGRESS_RE = /(WF\s+)?(\d+)\s+из\s+(\d+)(?:\s*[·•]\s*(\d+)\s*%)?/g;
  // Имя проекта в строке состояния — markdown-ссылка `[Имя](docs/status.md)`.
  // Просмотрщик обычно уже развернул её в текст, но в сыром виде она встречается.
  const PROGRESS_LINK_RE = /\[([^\]]{1,80})\]\([^)\s]*\)/g;
  // Имя проекта — текст между маркером-кружком и первым « · ». По нему подсказка
  // ищет сводку, присланную командой status.
  const projectFromLine = (line) => {
    const head = String(line ?? "").replace(PROGRESS_LINK_RE, "$1").split(/\s+[·•]\s+/)[0] ?? "";
    const hit = head.match(/[\p{L}\p{N}][^\n]*/u);
    return hit ? hit[0].trim().slice(0, 80) : "";
  };
  // Берём ПОСЛЕДНЕЕ совпадение в тексте: строка состояния стоит последней
  // строкой ответа, а выше по тексту легко встречается пересказ чужой строки.
  const parseProgressText = (text) => {
    const source = String(text ?? "");
    if (source === "") return null;
    let found = null;
    PROGRESS_RE.lastIndex = 0;
    for (let match = PROGRESS_RE.exec(source); match; match = PROGRESS_RE.exec(source)) {
      // Значок ищем в той же строке, а не во всём ответе: ✅ стоит чуть ли не в
      // каждом списке сделанного, и любое «2 из 2» стало бы строкой состояния.
      const from = source.lastIndexOf("\n", match.index) + 1;
      const end = source.indexOf("\n", match.index);
      const line = source.slice(from, end === -1 ? source.length : end);
      const hit = PROGRESS_STATES.find(([icon]) => line.includes(icon));
      const mark = hit ? hit[1] : null;
      if (!match[1] && mark !== "done") continue;
      const wf = Number(match[2]);
      const count = Number(match[3]);
      if (!Number.isFinite(wf) || !Number.isFinite(count) || wf < 1 || count < 1) continue;
      const done = mark === "done";
      const raw = match[4] === undefined ? null : Number(match[4]);
      const pct = done ? 100 : (raw == null ? null : Math.min(100, Math.max(0, raw)));
      // Прогресс марафона: закрытые воркфлоу целиком плюс доля текущего.
      // Готово — сразу полная полоса, сколько бы процентов ни было написано
      // рядом.
      const share = done ? 1 : ((wf - 1) + (pct ?? 0) / 100) / count;
      const total = Math.round(Math.min(1, Math.max(0, share)) * 1000) / 10;
      found = { wf, of: count, pct, total, state: mark ?? "run", project: projectFromLine(line) };
    }
    if (found) return found;
    // Одиночный воркфлоу: марафона нет, и кусок «WF N из M» в строке опущен
    // (AGENTS.md) — остаётся «💭⚪Проект · 40%💭». Такую строку узнаём строго, по
    // одному и тому же значку с обоих краёв: иначе «✅ покрытие 80%» из любого
    // ответа стало бы прогрессом. Сегмент у неё один.
    for (const raw of source.split("\n")) {
      const line = raw.trim();
      if (line.length < 3) continue;
      const hit = PROGRESS_STATES.find(([icon]) => line.startsWith(icon) && line.endsWith(icon));
      if (!hit) continue;
      const percent = line.match(/(\d+)\s*%/);
      const done = hit[1] === "done";
      if (!percent && !done) continue;
      const pct = done ? 100 : Math.min(100, Math.max(0, Number(percent[1])));
      found = { wf: 1, of: 1, pct, total: pct, state: hit[1], project: projectFromLine(line) };
    }
    return found;
  };
  // <<< разбор строки состояния

  // ---- сводка проектов (команда status) ------------------------------------
  // Страница файлов не читает — сводку присылает приложение командой
  // {action:"status", scope:"all", projects:[{name, text}]}, где text — сырой
  // markdown status.md проекта. Держим её в памяти окна (не в хранилище: сводка
  // живёт минуту до следующей команды и общей для окон быть не обязана) и
  // показываем в подсказке полосы для того проекта, чьё имя стоит в строке
  // состояния этого чата.
  const STATUS_MAX_PROJECTS = 24;
  const STATUS_MAX_TEXT = 8000;
  // Общий потолок на команду со стороны страницы: приложение своё режет само, но
  // верить ему на слово нельзя — разбор сводки идёт в главном потоке окна.
  const STATUS_MAX_TOTAL = 32 * 1024;
  const STATUS_MAX_LINES = 12;
  const STATUS_LINE_MAX = 120;
  // Блок воркфлоу в сводке начинается с номера-клавиши: «1️⃣ Workflow ✅ готово».
  const STATUS_HEAD_RE = /^(\d\uFE0F?\u20E3|\u{1F51F})\s*(.*)$/u;
  const STATUS_DEFAULT_ICON = "⬜";
  const statusFeed = { at: 0, projects: new Map() };

  const statusLine = (item) => {
    const roles = item.roles.slice(0, 6).join(" · ");
    const line = [`${item.number} ${item.icon}`, item.about, roles]
      .filter(Boolean).join(" · ").replace(/\s+/g, " ").trim();
    return line.length > STATUS_LINE_MAX ? `${line.slice(0, STATUS_LINE_MAX - 1)}…` : line;
  };
  // Сводка написана списками, а не таблицей, поэтому разбираем построчно:
  // заголовок блока даёт номер и значок, первый пункт — «о чём», пункты с
  // разделителем и словом впереди — роли. Пункты «шаги 2 из 2» и время
  // («00:17 → 01:20 · 1 ч») в подсказку не идут: в ней важно, что за воркфлоу и
  // кто в нём занят.
  const statusLines = (text) => {
    const lines = [];
    let current = null;
    const flush = () => { if (current) lines.push(statusLine(current)); current = null; };
    for (const raw of String(text ?? "").split("\n")) {
      const line = raw.trim();
      const head = line.match(STATUS_HEAD_RE);
      if (head) {
        flush();
        const hit = PROGRESS_STATES.find(([icon]) => (head[2] ?? "").includes(icon));
        current = { number: head[1], icon: hit ? hit[0] : STATUS_DEFAULT_ICON, about: "", roles: [] };
        continue;
      }
      if (!current || !/^[-*]\s/.test(line)) continue;
      const item = line.replace(/^[-*]\s*/, "").trim();
      if (!item) continue;
      if (!current.about && !/^шаги\b/i.test(item) && !/\d\s*:\s*\d/.test(item)) {
        current.about = item.replace(/^о\s+чём\s*:\s*/i, "");
        continue;
      }
      const role = item.split(/\s*[·•]\s*/)[0] ?? "";
      if (item.includes("·") && !item.includes("→") && role && !/\d/.test(role)) current.roles.push(role);
    }
    flush();
    // Подсказка не должна вырастать в простыню: последние двенадцать воркфлоу.
    return lines.slice(-STATUS_MAX_LINES);
  };
  // Имя проекта в строке состояния и имя папки, которое прислало приложение,
  // совпадают не побуквенно (регистр, дефисы). Сравниваем по буквам и цифрам.
  const statusKey = (name) => String(name ?? "").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "");
  const statusFeedLines = (project) => {
    const key = statusKey(project);
    if (!key) return [];
    for (const [name, lines] of statusFeed.projects) {
      const other = statusKey(name);
      if (!other) continue;
      if (other === key || other.startsWith(key) || key.startsWith(other)) return lines;
    }
    return [];
  };
  // Команда снаружи: разбираем сразу, а не при показе подсказки — разбор дешевле
  // раза в минуту, чем на каждое движение мыши.
  const runStatusCommand = (detail) => {
    const list = Array.isArray(detail?.projects) ? detail.projects : null;
    if (!list) return false;
    const next = new Map();
    let budget = STATUS_MAX_TOTAL;
    for (const item of list.slice(0, STATUS_MAX_PROJECTS)) {
      const name = typeof item?.name === "string" ? item.name.trim().slice(0, 80) : "";
      const text = typeof item?.text === "string" ? item.text.slice(0, STATUS_MAX_TEXT) : "";
      if (!name || !text) continue;
      // Потолок выбран — остальные проекты отбрасываем целиком: половина сводки
      // в подсказке хуже, чем её отсутствие.
      budget -= name.length + text.length;
      if (budget < 0) break;
      next.set(name, statusLines(text));
    }
    statusFeed.projects = next;
    statusFeed.at = Date.now();
    progressState.tipText = "";
    if (progressState.hovering) { try { progressTipShow(); } catch {} }
    return true;
  };

  const progressState = {
    info: null, reason: "полоса ещё не считалась", at: 0, runs: 0, timer: 0, pulse: 0,
    // Найденная рамка поля, нарисованные доли сегментов, место линии на экране,
    // наведение и последний текст подсказки.
    frame: null, shell: null, segments: [], box: null, hovering: false, tipText: "", tipDark: null,
    // На чём сейчас сидит линия: "рамка" или запасное "строка инструментов".
    anchor: null,
  };

  // Полосу и подсказку сносим по id, как ручку и стили: упавшая на середине
  // установка оставляет их в окне, а реестра отмены у них уже нет.
  for (const id of [PROGRESS_ID, PROGRESS_TIP_ID]) {
    for (const orphan of document.querySelectorAll(`#${id}`)) orphan.remove();
  }

  const progressBar = document.createElement("div");
  progressBar.id = PROGRESS_ID;
  // aria-hidden и никакого aria-live: полоса меняется на каждом ответе, и
  // VoiceOver проговаривал бы её без остановки (довод донора).
  progressBar.setAttribute("aria-hidden", "true");
  // Стили — прямо в узел, без <style>: CSP страницы может не пустить нашу
  // таблицу (см. state.cssOk в разделе 4), а element.style ей неподвластен.
  for (const [name, value] of Object.entries({
    position: "fixed", display: "none", left: "0px", top: "0px", width: "0px",
    height: `${PROGRESS_BAR_HEIGHT}px`, "align-items": "stretch", gap: `${PROGRESS_SEG_GAP}px`,
    "pointer-events": "none", "z-index": "2147483645",
  })) progressBar.style.setProperty(name, value);
  (document.body ?? document.documentElement).appendChild(progressBar);
  track(() => progressBar.remove());

  const progressTip = document.createElement("div");
  progressTip.id = PROGRESS_TIP_ID;
  progressTip.setAttribute("aria-hidden", "true");
  for (const [name, value] of Object.entries({
    position: "fixed", display: "none", left: "0px", top: "0px", "max-width": "560px",
    padding: "8px 10px", "border-radius": "8px", "border-width": "1px", "border-style": "solid",
    font: "12px/1.45 -apple-system, system-ui, sans-serif", "white-space": "pre",
    overflow: "hidden", "pointer-events": "none", "z-index": "2147483646",
  })) progressTip.style.setProperty(name, value);
  (document.body ?? document.documentElement).appendChild(progressTip);
  track(() => progressTip.remove());

  // --accent-brand и у Claude, и у наших тем (раздел 2а) хранит не цвет, а
  // тройку HSL: «251.000 40.000% 54.500%». Подставить её в background как есть
  // нельзя — объявление отбросится и полоса станет невидимой, поэтому тройку
  // заворачиваем в hsl() сами, а на всё незнакомое берём фиолетовый донора.
  const progressAccent = () => {
    let raw = "";
    // В окне Claude Code палитра живёт на .epitaxy-root, а не на html.
    try {
      const host = state.composerBlock ?? document.querySelector(".epitaxy-root") ?? document.documentElement;
      raw = getComputedStyle(host).getPropertyValue("--accent-brand").trim();
    } catch {}
    if (!raw) return PROGRESS_ACCENT_FALLBACK;
    if (/^(?:#|rgba?\(|hsla?\(|oklch\(|lab\(|lch\(|color\()/i.test(raw)) return raw;
    if (/^[\d.]+(?:deg)?\s+[\d.]+%\s+[\d.]+%$/.test(raw)) return `hsl(${raw})`;
    return PROGRESS_ACCENT_FALLBACK;
  };
  // Тёмное окно или светлое: наши темы пишут color-scheme прямо на :root, а без
  // темы решает системная настройка.
  const progressDark = () => {
    try {
      const scheme = String(getComputedStyle(document.documentElement).colorScheme ?? "");
      if (/dark/.test(scheme) && !/light/.test(scheme)) return true;
      if (/light/.test(scheme) && !/dark/.test(scheme)) return false;
    } catch {}
    try { return matchMedia("(prefers-color-scheme: dark)").matches; } catch { return true; }
  };

  // Кромка, на которой сидит полоса. Сама .epitaxy-prompt бывает обёрткой без
  // границы, а рамку рисует её потомок (border или box-shadow) — садиться надо
  // на ту кромку, которую видит глаз. Ищем неглубоко и с ограничением по числу
  // узлов: проход зовётся до четырёх раз в секунду.
  const PROGRESS_FRAME_SELECTOR = ".epitaxy-prompt";
  const PROGRESS_FRAME_DEPTH = 3;
  const PROGRESS_FRAME_BUDGET = 32;
  const PROGRESS_FRAME_SLACK = 24;
  const framePainted = (node) => {
    let computed = null;
    try { computed = getComputedStyle(node); } catch { return false; }
    if (!computed) return false;
    if ((parseFloat(computed.borderBottomWidth) || 0) > 0) return true;
    const shadow = String(computed.boxShadow ?? "");
    return shadow !== "" && shadow !== "none";
  };
  const paintedChild = (root) => {
    const base = root.getBoundingClientRect();
    let level = [root];
    let budget = PROGRESS_FRAME_BUDGET;
    for (let depth = 0; depth < PROGRESS_FRAME_DEPTH && level.length > 0 && budget > 0; depth += 1) {
      const next = [];
      for (const node of level) {
        for (const kid of node.children ?? []) {
          if (budget <= 0) break;
          budget -= 1;
          const rect = kid.getBoundingClientRect();
          // Рамка — во всю ширину поля и с тем же низом. Всё, что заметно уже
          // (кнопки, значки), не рамка и внутрь себя её не прячет.
          if (rect.width < base.width - PROGRESS_FRAME_SLACK) continue;
          if (Math.abs(rect.bottom - base.bottom) <= PROGRESS_FRAME_SLACK && framePainted(kid)) return kid;
          next.push(kid);
        }
      }
      level = next;
    }
    return null;
  };
  const progressFrame = (block) => {
    const shell = state.shell?.isConnected && block.contains(state.shell) ? state.shell : null;
    const cached = progressState.frame;
    // Кэш годится, пока жива и сама найденная рамка, и та рамка поля, от которой
    // мы её нашли: React пересобирает низ окна целиком.
    if (cached?.isConnected && block.contains(cached) && progressState.shell === shell) return cached;
    progressState.shell = shell;
    let root = shell?.closest?.(PROGRESS_FRAME_SELECTOR) ?? null;
    if (!root?.isConnected) root = block.querySelector(PROGRESS_FRAME_SELECTOR);
    if (!root?.isConnected) root = shell;
    if (!root?.isConnected) return null;
    progressState.frame = framePainted(root) ? root : (paintedChild(root) ?? root);
    return progressState.frame;
  };

  // Меню модели и effort раскрываются вверх ровно над этой границей, а полоса
  // висит поверх страницы и рисовалась бы сквозь них. Хит-тест, как у ручки
  // (раздел 8), здесь не нужен: полоса ничего не ловит мышью, хватает
  // пересечения с открытым меню или модалкой.
  const progressCovered = (top, left, right) => {
    for (const node of document.querySelectorAll(OVERLAY_SELECTOR)) {
      const rect = node.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) continue;
      if (rect.top <= top + 2 && rect.bottom >= top - 2 && rect.left <= right && rect.right >= left) return true;
    }
    return false;
  };

  // Сегменты марафона: готовые полные, текущий на свои проценты, будущие пустые.
  // ✅ закрашивает все — «готово» сильнее любых процентов рядом.
  const progressShares = (info, width) => {
    const count = Math.max(1, Math.min(PROGRESS_SEG_MAX, Math.round(info.of) || 1));
    // Совсем узкая полоса: сегменты по паре точек с зазором в три уже не
    // читаются — тогда честнее одна сплошная доля всего марафона.
    if (count > 1 && (width - (count - 1) * PROGRESS_SEG_GAP) / count < PROGRESS_SEG_MIN) return [info.total];
    const shares = [];
    for (let number = 1; number <= count; number += 1) {
      if (info.state === "done" || number < info.wf) shares.push(100);
      else if (number === info.wf) shares.push(info.pct ?? 0);
      else shares.push(0);
    }
    return shares;
  };

  // Узлы сегментов: у каждого свой контур (track) и своя заливка (fill). Контур
  // отдельным узлом, а не прозрачностью самого сегмента, — иначе вместе с ним
  // выцвела бы и заливка текущего воркфлоу.
  const progressCells = [];
  const progressBuild = (count) => {
    if (progressCells.length === count) return;
    for (const item of progressCells) item.cell.remove();
    progressCells.length = 0;
    for (let index = 0; index < count; index += 1) {
      const cell = document.createElement("div");
      for (const [name, value] of Object.entries({
        position: "relative", flex: "1 1 0", "min-width": "0", height: "100%", "border-radius": "999px",
      })) cell.style.setProperty(name, value);
      const track = document.createElement("div");
      for (const [name, value] of Object.entries({
        position: "absolute", left: "0", top: "0", right: "0", bottom: "0",
        "border-radius": "999px", opacity: "0.25",
      })) track.style.setProperty(name, value);
      const fill = document.createElement("div");
      for (const [name, value] of Object.entries({
        position: "absolute", left: "0", top: "0", bottom: "0", width: "0%",
        "border-radius": "999px", transition: `width ${PROGRESS_MOVE_MS}ms linear`,
      })) fill.style.setProperty(name, value);
      cell.appendChild(track);
      cell.appendChild(fill);
      progressBar.appendChild(cell);
      progressCells.push({ cell, track, fill });
    }
  };

  const progressTipHide = () => {
    if (progressTip.style.display !== "none") progressTip.style.setProperty("display", "none");
  };
  const progressTipShow = () => {
    const info = progressState.info;
    if (!info || !progressState.box || progressBar.style.display === "none") { progressTipHide(); return; }
    const head = `Воркфлоу ${info.wf} из ${info.of}` + (info.pct == null ? "" : ` · ${info.pct} %`);
    const text = [head, ...statusFeedLines(info.project)].join("\n");
    if (progressState.tipText !== text) {
      progressState.tipText = text;
      // Только textContent: сводка приходит снаружи, и разметки в ней быть не должно.
      progressTip.textContent = text;
    }
    const dark = progressDark();
    if (progressState.tipDark !== dark) {
      progressState.tipDark = dark;
      for (const [name, value] of Object.entries(dark
        ? { background: "#12151c", color: "#e7e9f0", "border-color": "#2a2f3a", "box-shadow": "0 8px 24px rgba(0,0,0,.45)" }
        : { background: "#ffffff", color: "#14181f", "border-color": "#d7dbe3", "box-shadow": "0 8px 24px rgba(15,20,30,.18)" })) {
        progressTip.style.setProperty(name, value);
      }
    }
    progressTip.style.setProperty("display", "block");
    // Место считаем уже по показанной подсказке: до показа высоты у неё нет.
    const rect = progressTip.getBoundingClientRect();
    const width = rect.width || 0;
    const height = rect.height || 0;
    const left = Math.max(6, Math.min(innerWidth - width - 6, progressState.box.left));
    const top = Math.max(6, progressState.box.top - height - 8);
    progressTip.style.setProperty("left", `${Math.round(left)}px`);
    progressTip.style.setProperty("top", `${Math.round(top)}px`);
  };

  const progressHide = () => {
    progressState.box = null;
    progressState.anchor = null;
    progressTipHide();
    if (progressBar.style.display !== "none") progressBar.style.setProperty("display", "none");
  };

  // Одно место решает и про причину, и про видимость: иначе status().progress
  // рассказывал бы одно, а окно показывало другое.
  const progressApply = () => {
    const block = state.composerBlock?.isConnected ? state.composerBlock : null;
    if (!block) { progressState.reason = "нет блока композера"; progressHide(); return; }
    // Якорь основной — нижняя кромка рамки поля. Запасной — верх строки
    // инструментов (там полоса и стояла до WF9): рамки может не оказаться вовсе
    // (чужая разметка, Claude Code) или она вырождается на кадр, пока React
    // пересобирает низ окна. Лучше на пару точек ниже, чем пропасть.
    const frame = progressFrame(block);
    const frameRect = frame?.isConnected ? frame.getBoundingClientRect() : null;
    const onFrame = frameRect != null && frameRect.width >= PROGRESS_MIN_WIDTH;
    const rowRect = onFrame || !state.modelRow?.isConnected
      ? null
      : state.modelRow.getBoundingClientRect();
    const rect = onFrame ? frameRect : rowRect;
    if (!rect) { progressState.reason = "нет рамки поля"; progressHide(); return; }
    const info = progressState.info;
    if (!info) { progressState.reason = "нет строки состояния"; progressHide(); return; }
    if (rect.width < PROGRESS_MIN_WIDTH || rect.bottom <= 0 || rect.top >= innerHeight) {
      progressState.reason = "рамка поля вне окна";
      progressHide();
      return;
    }
    const left = Math.round(rect.left);
    const width = Math.round(rect.width);
    // Полоса сидит верхом на кромке: половина линии выше низа рамки, половина
    // ниже. На запасном якоре кромка — верх строки инструментов.
    const top = Math.round(onFrame ? rect.bottom : rect.top) - 1;
    if (progressCovered(top, left, left + width)) {
      progressState.reason = "полосу закрыло меню";
      progressHide();
      return;
    }
    progressState.reason = null;
    progressState.anchor = onFrame ? "рамка" : "строка инструментов";
    const shares = progressShares(info, width);
    progressState.segments = shares;
    progressBuild(shares.length);
    const accent = progressAccent();
    const hot = PROGRESS_PAINT[info.state] ?? accent;
    // Слитая в одну полоса — это и есть текущий воркфлоу целиком.
    const merged = shares.length === 1 && info.of > 1;
    const current = merged ? 0 : Math.min(shares.length - 1, Math.max(0, info.wf - 1));
    for (let index = 0; index < shares.length; index += 1) {
      const item = progressCells[index];
      if (!item) continue;
      const share = shares[index];
      const paint = index === current ? hot : accent;
      item.fill.style.setProperty("width", `${share}%`);
      item.fill.style.setProperty("background", paint);
      // Свечение двумя тенями — приём донора: широкий мягкий ореол и второй
      // проход по той же тени, отчего свет плотнее у самой линии. Пустому
      // сегменту светиться нечем.
      item.fill.style.setProperty("box-shadow", share > 0 ? `0 0 18px ${paint},0 0 6px ${paint}` : "none");
      // Контур в одну точку — «сюда марафон ещё не дошёл».
      item.track.style.setProperty("box-shadow", `inset 0 0 0 1px ${accent}`);
    }
    progressBar.style.setProperty("left", `${left}px`);
    progressBar.style.setProperty("top", `${top}px`);
    progressBar.style.setProperty("width", `${width}px`);
    const title = `Воркфлоу ${info.wf} из ${info.of}` + (info.pct == null ? "" : ` · ${info.pct} %`);
    // Указателя полоса не ловит, и родной title на ней не покажется — он остаётся
    // для разбора окна (probe на гейте). Человеку показывается свой div выше.
    if (progressBar.title !== title) progressBar.title = title;
    progressBar.style.setProperty("display", "flex");
    progressState.box = { left, right: left + width, top };
    if (progressState.hovering) progressTipShow();
  };
  // Раскладку ручки полоса не имеет права уронить: её зовут из чужого кода.
  const placeProgress = () => { try { progressApply(); } catch {} };

  // Наведение: зона в десять точек над линией и сама линия. Ловим общим
  // mousemove, а не накладкой, — накладка стояла бы поверх низа поля ввода.
  const onProgressMove = (event) => {
    const box = progressState.box;
    const inside = box != null &&
      event.clientX >= box.left && event.clientX <= box.right &&
      event.clientY >= box.top - PROGRESS_HOVER_ZONE && event.clientY <= box.top + PROGRESS_BAR_HEIGHT + 1;
    if (inside === progressState.hovering) return;
    progressState.hovering = inside;
    if (inside) { try { progressTipShow(); } catch {} } else progressTipHide();
  };
  on(document, "mousemove", onProgressMove, { passive: true, capture: true });
  // Указатель ушёл из окна — движений больше не будет, и подсказка осталась бы
  // висеть. То же на потере фокуса окном.
  const onProgressLeave = () => {
    if (!progressState.hovering) return;
    progressState.hovering = false;
    progressTipHide();
  };
  on(document, "mouseleave", onProgressLeave, { passive: true });
  on(window, "blur", onProgressLeave, { passive: true });

  // Идём от последнего ответа к более старым и останавливаемся на первом, где
  // строка нашлась: это и есть «последняя по ленте».
  const progressRead = () => {
    // Те же приметы ответа, что у «Обкэшить» (ANSWER_SELECTOR + answerUsable): разметка
    // claude.ai и окна Claude Code разная, свой узкий селектор в 1.40609.1 не находил ничего.
    let nodes = [];
    try {
      const all = [...document.querySelectorAll(ANSWER_SELECTOR)].filter(answerUsable);
      nodes = all.filter(node => !all.some(other => other !== node && other.contains(node)));
    } catch {}
    const stop = Math.max(0, nodes.length - PROGRESS_LOOKBACK);
    for (let index = nodes.length - 1; index >= stop; index -= 1) {
      const node = nodes[index];
      if (!node?.isConnected) continue;
      // Черновик в поле ввода ответом не считается: там Элвис вполне может
      // держать недописанную строку состояния.
      if (state.composerBlock?.contains(node)) continue;
      const info = parseProgressText(node.innerText ?? node.textContent ?? "");
      if (info) return info;
    }
    // Запасной путь: в окнах «Open in new window» приметы ответа почти не совпадают
    // (проверено 04.09: 0–3 узла на сотню сообщений, лента виртуальная). Тогда читаем
    // текст всего окна без черновика в поле ввода — в нём строка состояния есть.
    try {
      let text = document.body?.innerText ?? "";
      const draft = (state.composerBlock?.innerText ?? "").trim();
      if (draft && text.endsWith(draft)) text = text.slice(0, -draft.length);
      else if (draft) text = text.replace(draft, "");
      return parseProgressText(text);
    } catch { return null; }
  };

  const progressRefresh = () => {
    if (!state.alive || !state.watching) return;
    progressState.at = now();
    progressState.runs += 1;
    progressState.info = progressRead();
    progressApply();
  };
  // Троттлинг откладыванием, а не пропуском: последняя мутация ленты — как раз
  // та, что дописала строку состояния, и терять её нельзя.
  const progressSchedule = () => {
    if (progressState.timer || !state.alive || !state.watching) return;
    const wait = Math.max(0, PROGRESS_MIN_GAP - (now() - progressState.at));
    if (wait === 0) { progressRefresh(); return; }
    progressState.timer = setTimeout(() => {
      progressState.timer = 0;
      try { progressRefresh(); } catch {}
    }, wait);
  };
  track(() => { if (progressState.timer) { clearTimeout(progressState.timer); progressState.timer = 0; } });
  // Тихое окно мутаций не даёт вовсе (чат открыт и не двигается), поэтому сверх
  // тика ленты — редкий страховочный перечёт.
  progressState.pulse = setInterval(() => { try { progressRefresh(); } catch {} }, PROGRESS_IDLE_MS);
  track(() => { clearInterval(progressState.pulse); progressState.pulse = 0; });

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
    // Полоса прогресса (раздел 2б) переезжает вместе с полем. Зовём её дважды:
    // здесь — чтобы её достали и те проходы, что кончатся ранним выходом
    // (свёрнутое поле, потерянный редактор), и в самом конце — чтобы во время
    // тяги она не отставала на проход от только что изменённой высоты.
    placeProgress();
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
    placeProgress();
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
  // Курсор в самое начало поля: вставка ложится ПЕРЕД черновиком и не затирает
  // его. Пустому полю это ничего не стоит.
  const caretToStart = (editor) => {
    try {
      const selection = (typeof getSelection === "function" ? getSelection() : null) ?? document.getSelection?.();
      if (!selection) return;
      const range = document.createRange();
      range.setStart(editor, 0);
      range.collapse(true);
      selection.removeAllRanges();
      selection.addRange(range);
    } catch {}
  };
  // Приметный кусок вставки: по нему видно, что в поле попал ИМЕННО наш текст.
  // Нужен он только при вставке ПЕРЕД черновиком — там поле непусто и до
  // вставки, и «поле не пусто» ничего не доказывает. В пустое поле критерий
  // прежний: поле стало непустым. Требовать примету и там нельзя — ProseMirror
  // переписывает вставленное по-своему (списки, кавычки, разметка), примета не
  // находится, и второй путь клал бы текст ВТОРОЙ раз: так дублился «Обкэшить».
  const insertProbe = (text) => String(text).replace(/\s+/g, " ").trim().slice(0, 40);
  const insertLength = (editor) => rawText(editor).replace(/\s+/g, " ").length;
  const insertLanded = (editor, probe, before) => {
    const after = rawText(editor).replace(/\s+/g, " ");
    return after.length > before && (probe === "" || after.includes(probe));
  };
  // Вставка текста в редактор. Сначала execCommand — Chromium проводит его через
  // штатный ввод, и ProseMirror видит обычный набор; если тот его проглотил (в
  // разных сборках бывает и так), досылаем то же самое событием paste с
  // DataTransfer. Отправку не трогаем ни в одном из путей: Enter не шлём.
  const insertIntoEditor = (editor, text, atStart) => {
    const probe = atStart ? insertProbe(text) : "";
    const before = insertLength(editor);
    try { editor.focus(); } catch {}
    if (atStart) caretToStart(editor);
    try { document.execCommand("insertText", false, text); } catch {}
    if (insertLanded(editor, probe, before)) return true;
    // Поле выросло, а примета не нашлась: текст всё-таки лёг, просто редактор
    // переписал его. Второй путь поверх — это ровно дубль, поэтому его нет.
    if (insertLength(editor) > before) return true;
    // ProseMirror не принял execCommand — досылаем то же самое событием paste.
    try { editor.focus(); } catch {}
    if (atStart) caretToStart(editor);
    try {
      const data = new DataTransfer();
      data.setData("text/plain", text);
      editor.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
    } catch {}
    return insertLanded(editor, probe, before);
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
    // Поле заведомо пустое — вставлять с начала незачем.
    if (!insertIntoEditor(editor, record.text, false)) return "вставка не удалась";
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

  // ---- 12а. Кнопка «Workflow» ---------------------------------------------
  // Пункт меню «🚀 Workflow» присылает готовый текст запуска (KICKOFF.md) —
  // страница кладёт его в поле ввода и НЕ отправляет: последнее слово за Элвисом,
  // он дописывает задачу и жмёт сам.
  //
  // Черновик не затираем: текст ложится ПЕРЕД ним (курсор в начало поля) и
  // отделяется пустой строкой. Иначе кнопка съедала бы недописанную мысль.
  const WORKFLOW_TEXT_MAX = 64000;
  const runWorkflowCommand = (detail) => {
    const raw = typeof detail?.text === "string" ? detail.text : "";
    const text = raw.slice(0, WORKFLOW_TEXT_MAX).replace(/\s+$/, "");
    if (!text) { state.workflowResult = "пустой текст"; return false; }
    const editor = state.editor?.isConnected ? state.editor : findEditor();
    if (!editor?.isConnected) { state.workflowResult = "нет редактора"; return false; }
    // Свёрнутое поле сначала возвращаем: вставлять в невидимое поле — значит
    // потерять текст из виду.
    if (state.stage === STAGE_COLLAPSED) setStage(STAGE_NORMAL);
    // Повторный клик (Элвис нажал дважды или команда доехала второй раз): первая
    // строка запуска уже стоит в поле — второй копии там делать нечего.
    const head = text.split("\n").find(line => line.trim() !== "")?.trim() ?? "";
    if (head && rawText(editor).replace(/\s+/g, " ").includes(head.replace(/\s+/g, " "))) {
      state.workflowRuns += 1;
      state.workflowResult = "уже вставлено";
      return true;
    }
    const draft = editorText(editor) !== "";
    const ok = insertIntoEditor(editor, draft ? `${text}\n\n` : text, draft);
    state.workflowRuns += 1;
    state.workflowResult = ok ? (draft ? "вставлено перед черновиком" : "вставлено") : "вставка не удалась";
    if (ok) scheduleLayout();
    return ok;
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
    // Тик времени сообщений заодно двигает полосу прогресса (раздел 2б): он
    // приходит от наблюдателя за лентой, то есть ровно тогда, когда в разговоре
    // что-то изменилось. Свой троттлинг у полосы отдельный, в секунду.
    try { progressSchedule(); } catch {}
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
    // «Тема» — тоже до проверки поля ввода: красить окно можно и пока composer
    // ещё не нашёлся, а окно с scope:"all" красится вообще любое.
    if (action === "theme") { try { runThemeCommand(detail); } catch {} return; }
    // «Сводка» (scope:"all") — приложение раз в минуту присылает status.md
    // проектов. Поля ввода ей не нужно: она ложится в память окна и всплывает в
    // подсказке полосы прогресса (раздел 2б). Стоит ДО отмены примерки нарочно:
    // сводка приходит сама по часам и меню не закрывает — иначе она сбивала бы
    // предпросмотр темы прямо под рукой у Элвиса.
    if (action === "status") { try { runStatusCommand(detail); } catch {} return; }
    // Любая другая команда из меню закрывает примерку: меню ушло, выбора темы не было.
    if (themeState.previewing) { try { restoreTheme(true); themeState.previewing = false; } catch {} }
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
      return;
    }
    // «Workflow» — тоже одному окну (заголовок из AX, запасной критерий — фокус):
    // текст запуска ложится в поле ввода этого окна и не отправляется.
    if (action === "workflow" && addressed(detail)) { try { runWorkflowCommand(detail); } catch {} }
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
    clearInterval(progressState.pulse);
    progressState.pulse = 0;
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
      // Полоса прогресса воркфлоу (раздел 2б): что вычитано из строки состояния
      // последнего ответа и почему полосы нет, если её нет. total — доля всего
      // марафона в процентах, pct — процент текущего воркфлоу, segments — доли
      // нарисованных сегментов слева направо (в узком окне их сливают в один).
      progress: {
        wf: progressState.info?.wf ?? null,
        of: progressState.info?.of ?? null,
        pct: progressState.info?.pct ?? null,
        total: progressState.info?.total ?? null,
        state: progressState.info?.state ?? null,
        segments: progressState.segments.slice(),
        // На чём сидит линия: "рамка" или запасное "строка инструментов".
        anchor: progressState.anchor,
        reason: progressState.reason,
      },
      // Сводка проектов из команды status: имя проекта, взятое из строки
      // состояния этого чата, и строки воркфлоу, которые уйдут в подсказку.
      // at и projects — для гейта: видно, дошла ли команда и под какими именами.
      statusFeed: {
        project: progressState.info?.project ?? null,
        lines: statusFeedLines(progressState.info?.project),
        at: statusFeed.at,
        projects: [...statusFeed.projects.keys()],
      },
      // Кнопка «Workflow»: вставок и чем кончилась последняя.
      workflow: { runs: state.workflowRuns, result: state.workflowResult },
      // Ключ чата, под которым окно хранит тему (раздел 2а): у главного окна он
      // меняется вместе с разговором, а у безымянного чата его нет вовсе.
      chatKey: chatKey(),
      // Ключ сессии — по ОКНУ: `main` у главного, `w:<заголовок>` у подчинённого.
      sessionKey: sessionKey(),
      // Тема и шрифт окна: что применено, под каким ключом хранится и откуда
      // взялось (session — своя сессия окна, window — карта по ключу, all —
      // запись «для всех»). У слоёв источники независимы.
      theme: {
        id: themeState.theme?.id ?? null,
        key: themeKey(),
        source: themeState.source,
      },
      font: {
        id: themeState.font?.id ?? null,
        family: themeState.font?.family ?? null,
        mono: themeState.font?.mono ?? false,
        source: themeState.fontSource,
      },
      // true — в окне сейчас предпросмотр (мышь в подменю), и хранилище про эти
      // цвета ничего не знает: см. runThemeCommand.
      preview: themeState.previewing,
      // Сырая запись карты по ключу окна — на гейте видно, что там лежит на
      // самом деле (в том числе запись старого формата `w:` и запись `main`).
      raw: (() => {
        const key = themeKey();
        if (!key) return null;
        const map = readThemeMap();
        const legacy = legacyKey(key);
        return map[key] ?? (legacy != null ? map[legacy] ?? null : null);
      })(),
      rawMain: isMainWindow() ? readThemeMap()[THEME_MAIN_KEY] ?? null : null,
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
    // Полоса прогресса — сразу после первой раскладки: блок ввода к этому
    // моменту уже найден, и ждать ближайшей мутации ленты ей нечего.
    progressRefresh();
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
