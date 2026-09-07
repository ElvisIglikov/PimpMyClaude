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
// cashout, scroll, theme, status, workflow, new-window, popout-window,
// live-colors, themes-restore. И сокращает время под сообщениями («3 minutes
// ago» → «3 min ago»). Команда
// theme несёт четыре слоя — цвет по
// палитре из claude-patch/themes.json, шрифт, размер текста сообщений и
// неоновую рамку окна (раздел «2а. Слои чата»): тема живёт на ЧАТЕ
// (ключ `id:<id чата>`, имя чата — тень для окон без известного id), у главного
// окна есть ещё и своя — она и остаётся,
// когда открыт новый чат; всё переживает перезапуск Claude, а команда
// themes-restore возвращает слои и после переустановки Claude, когда
// localStorage стирается целиком (копию карты держит приложение). На нижней кромке
// рамки поля ввода рисуется полоса прогресса марафона воркфлоу по строке
// состояния из последнего ответа — по сегменту на воркфлоу, с подсказкой из
// сводки, присланной командой status (раздел «2б»). Команда workflow кладёт в
// поле ввода текст запуска и НЕ отправляет его (раздел «12а»). Команды
// new-window и popout-window открывают чат отдельным окном — новый (⌘N от
// приложения, папка проекта, первое сообщение, отправка, имя чата и его цвет
// вперёд) или уже открытый (раздел «12б»). Страница ещё и говорит, КАКОЙ в ней
// чат: window.__myclaude.chats() отдаёт id чата этой страницы, карту попапов и
// папку чипа домашнего экрана, попап спрашивает свой id у окна-родителя
// (раздел «12в»), а команда theme может
// адресовать окно этим id — полем chat. Команда live-colors катит окно по
// цветовому кругу: цвет считается на странице от стенных часов, палитры
// приходят кольцом опорных точек (раздел «2в»). «Обкэшить» из подчинённого
// окна (WF37) не вставляет перенос себе, а помечает его «ждёт адресата»:
// адресата назовёт цепочка «Нового окна», и перенос ляжет в НОВОЕ окно
// (раздел «12»).
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
  const VERSION = "wf22-p-1";

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
  // Отказ не окончательный: раз в столько проверяем, не приехала ли разметка
  // Claude позже (окно «Open in new window» рождается пустым about:blank).
  const REVIVE_MS = 5000;
  const CASHOUT_FRESH_MS = 90000;
  const CASHOUT_TICK_MS = 300;
  // Перенос из подчинённого окна (WF37): пока цепочка «Нового окна» не назвала
  // адресата, запись помечена этим словом. Своё окно она узнаёт по id чата, а
  // срок ей считается от ШТАМПА, а не от нажатия: между нажатием и рождением
  // нового чата проходит несколько секунд работы цепочки.
  const CASHOUT_PENDING = "pending";
  const CASHOUT_STAMP_FRESH_MS = 60000;
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
    // Спрашивал ли сторож переноса окно-родителя, какой в нём чат (WF37).
    // Один вопрос на запись, а не на каждый тик (см. cashoutAskParent).
    cashoutAsked: false,
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
    // «Новое окно» и «В отдельное окно» (раздел 12б): запись последнего запуска
    // любой из двух команд — {state, step, id, at, busy, runs, back} и, с WF16,
    // ещё {folder, chip, name, rename, title, layers}; она же уходит наружу
    // полем newWindow в status().
    newWindow: null,
    scheduled: false,
    rafId: 0,
    layoutTimer: 0,
    layoutAt: 0,
    layoutRuns: 0,
    mutationBatches: 0,
    mutationSkipped: 0,
  };

  // ---- 2а. Слои чата: тема, шрифт, размер, рамка --------------------------
  // Четыре независимых слоя, у каждого своя ячейка в хранилище: тема (цвета),
  // шрифт, размер текста сообщений и неоновая рамка окна. У первых трёх своя
  // таблица стилей, у рамки — свой оверлей. Команда меняет тот слой, поле
  // которого в ней есть, — шрифт без темы окно не красит, тема без шрифта его не
  // сбрасывает, размер и рамка не трогают ни того, ни другого.
  //
  // С WF9 тема закреплена за ЧАТОМ, а не за окном: вернулся в разговор — вернулся
  // его цвет, в каком бы окне он ни открылся. У главного окна сверх того есть
  // своя тема (`main`) — ею красится всякий чат, у которого записи нет, поэтому
  // «Новый чат» и «Обкэшить» цвет окна не меняют. Смену чата ловит сторож
  // заголовка (watchChatTitle): страница при этом не перезагружается, и другого
  // признака у смены разговора нет.
  //
  // С WF35 чат опознаётся не именем, а ID (`id:local_<uuid>`, раздел 12в): имя
  // Элвис меняет, id — нет, и переименование разговора больше не теряет цвет.
  // Имя осталось тенью — под ним живут окна, которые своего id ещё не знают
  // (попап в первые секунды). Вся карта при этом умирает вместе с переустановкой
  // Claude, поэтому её копию держит приложение и присылает командой
  // themes-restore (см. runThemesRestoreCommand).
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
  // Кэш ответа родителя про свой чат (раздел 12в). Константа стоит ЗДЕСЬ, а не
  // в самом разделе: её читает chatIdKey (раздел 2а) уже на инжекте, а раздел
  // 12в лежит ниже по файлу — его `const`-ы к тому мгновению ещё в TDZ.
  const CHAT_ID_KEY = "myclaude-chat-v1";
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
  // Размер текста сообщений (WF12). Границы — по обе стороны от обычных 15 px:
  // меньше 11 текст не читается, больше 24 в окне помещается пара абзацев.
  const SIZE_MIN = 11;
  const SIZE_MAX = 24;
  // Правило пишется ТОЛЬКО на текст сообщений. Кнопки, сайдбар, поле ввода и
  // шапка живут своим размером: полезли бы туда — поехала бы вся раскладка окна,
  // а вместе с ней и замеры ручки. Приметы взяты те же, что уже проверены живьём
  // в CHAT_STARTED_SELECTOR (раздел 1): .font-claude-response отвечает за ответы
  // и в claude.ai, и в окне Claude Code, .epitaxy-user-turn — за вопросы в Code.
  // Точный селектор ответов Code сверяет probe на гейте (план WF12, п. 1).
  const SIZE_ANSWER_SELECTORS = [
    ".font-claude-response",
    ".font-claude-response-body",
    '[data-testid="assistant-message"] .prose',
    // Окно Claude Code (probe 04.09): ответ — .prose внутри строки сообщения, у вопроса своя обёртка.
    '.epitaxy-transcript-typography [class*="message-row"]:not(:has(.epitaxy-user-turn)) .prose',
  ];
  const SIZE_QUESTION_SELECTORS = ["[data-user-message-bubble]", ".epitaxy-user-turn"];
  // Заголовки и код внутри ответа — в em, то есть долей от заданного размера:
  // так они едут пропорционально сами и не спорят с выбором Элвиса.
  const SIZE_HEADINGS = [["h1", 1.6], ["h2", 1.35], ["h3", 1.18], ["h4", 1.05]];
  const SIZE_CODE_SCALE = 0.9;
  // Неоновая рамка окна (WF12, #5343): оверлей во всё окно, свет внутрь.
  // Скругление — как у окна macOS; 2 точки линии и то же свечение, что у полосы
  // прогресса, потому что цвет у них один — акцент темы.
  const WINDOW_FRAME_ID = "myclaude-window-frame";
  const WINDOW_FRAME_RADIUS = 10;
  // Ниже полосы прогресса (2147483645) и её подсказки (2147483646): полоска
  // спорить с рамкой не должна и идёт поверх (план WF12, п. 4). Меню приложения —
  // родное меню macOS, оно поверх всего окна и в этот счёт не входит.
  const WINDOW_FRAME_Z = "2147483644";

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
  // Разбор цвета на части: тон 0…360, насыщенность и светлота долями 0…1.
  // Отсюда же растёт hslTriple — вывод у него обязан остаться прежним побайтно.
  const hslParts = color => {
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
    return [hue, saturation, lightness];
  };
  // Переменные Claude хранят не цвет, а HSL-триплет «H S% L%»: страница сама
  // подставляет его в hsl(...) и добавляет прозрачность.
  const hslTriple = color => {
    const [hue, saturation, lightness] = hslParts(color);
    return `${hue.toFixed(3)} ${(saturation * 100).toFixed(3)}% ${(lightness * 100).toFixed(3)}%`;
  };
  const hexFromHsl = (hue, saturation, lightness) => {
    const turn = ((hue % 360) + 360) % 360;
    const sat = Math.max(0, Math.min(1, saturation));
    const light = Math.max(0, Math.min(1, lightness));
    const chroma = (1 - Math.abs(2 * light - 1)) * sat;
    const second = chroma * (1 - Math.abs(((turn / 60) % 2) - 1));
    const shift = light - chroma / 2;
    const [red, green, blue] = turn < 60 ? [chroma, second, 0]
      : turn < 120 ? [second, chroma, 0]
      : turn < 180 ? [0, chroma, second]
      : turn < 240 ? [0, second, chroma]
      : turn < 300 ? [second, 0, chroma]
      : [chroma, 0, second];
    return hexOf([(red + shift) * 255, (green + shift) * 255, (blue + shift) * 255]);
  };
  // Яркость и контраст по WCAG: подсветка кода обязана читаться и в тёмных, и в
  // светлых темах, а «на глаз» это не проверить — считаем числом (#5365).
  const luminance = color => {
    const [red, green, blue] = rgbOf(color).map(value => {
      const channel = value / 255;
      return channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
  };
  const contrastRatio = (left, right) => {
    const first = luminance(left);
    const second = luminance(right);
    return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
  };
  // Дотянуть цвет до читаемости, НЕ трогая тон и насыщенность: двигаем только
  // светлоту шагом в процент прочь от фона. Так оттенки One Dark остаются
  // узнаваемыми. Контраст уже достаточен — отдаём цвет как есть, без обратного
  // хода hex → hsl → hex (иначе дрожал бы последний знак). Цели не достигли —
  // отдаём лучшего из перепробованных, включая исходный: хуже, чем было, не
  // возвращаем никогда.
  const readableOn = (color, background, target) => {
    const start = normalizeHex(color, "#000000");
    const under = normalizeHex(background, "#000000");
    if (contrastRatio(start, under) >= target) return start;
    const [hue, saturation, lightness] = hslParts(start);
    const step = luminance(under) < 0.5 ? 0.01 : -0.01;
    let best = start;
    let bestRatio = contrastRatio(start, under);
    let level = lightness;
    for (let index = 0; index < 100; index += 1) {
      level += step;
      if (level < 0 || level > 1) break;
      const candidate = hexFromHsl(hue, saturation, level);
      const ratio = contrastRatio(candidate, under);
      if (ratio > bestRatio) { best = candidate; bestRatio = ratio; }
      if (ratio >= target) return candidate;
    }
    return best;
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
    // Палитра кода считается ОДИН раз и раздаётся всем, кому нужна: блокам кода,
    // подсветке, инлайну и просмотрщику диффов — иначе коробки в одном окне
    // разъезжаются по цвету (#5365).
    const code = codePalette({ type: theme.type, background, foreground, accent });
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
${epitaxyCss({ type: theme.type, background, foreground, accent, panel, muted, code })}
${codeCss(code)}`;
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
  const epitaxyCss = ({ type, background, foreground, accent, panel, muted, code }) => {
    const light = type === "light";
    // Палитру кода даёт themeCss, чтобы диффы и блоки кода были одного цвета.
    // Позвали без неё (старые тесты, прямой вызов) — считаем сами.
    const codeColors = code ?? codePalette({ type, background, foreground, accent });
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
/* Блоки кода — <diffs-container> с shadow DOM: наши таблицы стилей внутрь не
   попадают, зато его цвета — переменные хоста и схема light-dark(). Без этого
   блок остаётся чёрным на любой теме (#5365). Фон — общая подложка кода (в
   светлых темах старый замес от панели давал почти белое и коробка сливалась
   со страницей), текст — цвет темы; схема — по типу темы, чтобы подсветка
   синтаксиса взяла свой светлый/тёмный набор. */
.epitaxy-root diffs-container, diffs-container {
  color-scheme: ${light ? "light" : "dark"} !important;
  --diffs-light-bg: ${codeColors.surface} !important;
  --diffs-dark-bg: ${codeColors.surface} !important;
  --diffs-light: ${foreground} !important;
  --diffs-dark: ${foreground} !important;
}
`;
  };

  // Блоки кода (#5365). Подсветка у Claude — highlight.js «One Dark»: числа
  // зашиты в его таблицу, светлого набора нет вовсе, и коробка остаётся чёрной
  // при любой теме, а в светлых темах токены на ней не читаются (строка давала
  // контраст 1,65). Держим привычные оттенки One Dark — по цвету читают код, —
  // но подтягиваем светлоту под нашу подложку: тон и насыщенность не трогаем.
  const ONE_DARK_TOKENS = {
    comment: "#5c6370", keyword: "#c678dd", name: "#e06c75", literal: "#56b6c2",
    string: "#98c379", number: "#d19a66", title: "#61aeee", builtin: "#e6c07b",
  };
  // Комментарий приглушён намеренно: на 4,5 он стал бы таким же ярким, как код,
  // и подсветка потеряла бы смысл.
  const CODE_CONTRAST = 4.5;
  const CODE_COMMENT_CONTRAST = 3.5;
  const codePalette = ({ type, background, foreground, accent }) => {
    const light = type === "light";
    const base = THEME_FALLBACK[light ? "light" : "dark"];
    const page = normalizeHex(background, base.background);
    const ink = normalizeHex(foreground, base.foreground);
    const brand = normalizeHex(accent, base.accent);
    // Подложка считается от пары фон↔текст, а НЕ от панели: у всех девяти
    // светлых тем panel = #ffffff, и коробка на нём пропала бы. Такой замес даёт
    // «полочку» чуть светлее страницы в тёмной теме и чуть темнее — в светлой.
    const surface = mixHex(page, ink, light ? 0.06 : 0.09);
    const tokens = {};
    for (const [group, color] of Object.entries(ONE_DARK_TOKENS)) {
      tokens[group] = readableOn(color, surface, group === "comment" ? CODE_COMMENT_CONTRAST : CODE_CONTRAST);
    }
    return {
      surface,
      // Своя рамка коробки: акцент, уведённый к фону. Рамка цитаты берётся
      // готовой var(--cds-border) — второй константы для неё тут нет.
      border: mixHex(brand, page, 0.62),
      ink,
      // Чип считаем против той же подложки: alpha-1 у Claude — те же 5 % сдвига
      // от фона, а одна опорная поверхность на весь код предсказуемее.
      chipInk: readableOn(brand, surface, CODE_CONTRAST),
      tokens,
    };
  };

  // Превью артефактов Claude прикрывает у себя ровно один background у pre —
  // наши чернила, рамка и восемь токенов туда бы попали, и код на «белой бумаге»
  // превью стал бы нечитаемым. Поэтому каждое наше правило кода выключает себя
  // внутри превью само: хвост приписывается к КАЖДОМУ селектору списка.
  const CODE_NOT_PREVIEW = ":not(:is(.artifact-markdown-preview, .channel-artifact-markdown-preview) *)";
  const outsidePreview = list => list.split(",").map(part => `${part.trim()}${CODE_NOT_PREVIEW}`).join(", ");
  // Селекторы групп — дословно из таблиц Claude (разведка WF34), порядок как в
  // его файле. Правила без цвета (курсив, жирный, подчёркивание) не трогаем.
  const CODE_TOKEN_SELECTORS = {
    comment: ".hljs-comment, .hljs-quote",
    keyword: ".hljs-doctag, .hljs-formula, .hljs-keyword",
    name: ".hljs-deletion, .hljs-name, .hljs-section, .hljs-selector-tag, .hljs-subst",
    literal: ".hljs-literal",
    string: ".hljs-addition, .hljs-attribute, .hljs-meta .hljs-string, .hljs-regexp, .hljs-string",
    number: ".hljs-attr, .hljs-number, .hljs-selector-attr, .hljs-selector-class, .hljs-selector-pseudo, .hljs-template-variable, .hljs-type, .hljs-variable",
    title: ".hljs-bullet, .hljs-link, .hljs-meta, .hljs-selector-id, .hljs-symbol, .hljs-title",
    builtin: ".hljs-built_in, .hljs-class .hljs-title, .hljs-title.class_",
  };
  const codeCss = code => {
    const tokens = Object.entries(CODE_TOKEN_SELECTORS)
      .map(([group, selector]) => `${outsidePreview(selector)} { color: ${code.tokens[group]} !important; }`)
      .join("\n");
    // Инлайн-код красится ТРЕМЯ код-только переменными Claude, а не своими
    // фонами: у него развешаны исключения (чип в ссылке, ячейка th, таблица,
    // вложенный код) — любое наше правило фона их затопчет. Прямое правило ниже
    // нужно старому рендеру, который --cds-* не читает вовсе, и служит
    // страховкой полю ввода, где переменная объявлена ближе к элементу.
    return `/* Блоки кода, подсветка и инлайн — из палитры темы (#5365) */
${THEME_ROOT_SELECTOR} {
  --cds-prose-code-color: ${code.chipInk} !important;
  --code-chip-ink: ${code.chipInk} !important;
  --cds-editor-code-ink: ${code.chipInk} !important;
}
${outsidePreview("pre, .hljs, code.hljs, .code-block__code")} { background: ${code.surface} !important; color: ${code.ink} !important; }
${outsidePreview("pre")} { border: 0.5px solid ${code.border} !important; }
${tokens}
${outsidePreview(".ReactMarkdown code, div.ProseMirror > p > code")} { color: ${code.chipInk} !important; }
${outsidePreview(".epitaxy-markdown blockquote")} { border-left-color: var(--cds-border) !important; }
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

  // Размер — третий слой, со своим разбором. Половинки независимы: команда может
  // нести только «размер ответов», и тогда размер вопросов остаётся прежним
  // (контракт WF12: поля нет — не менять). Обе половинки — целые точки в
  // границах SIZE_MIN…SIZE_MAX; мусор равен отсутствию поля, пустой слой — null.
  const sizePx = value => {
    const px = Math.round(Number(value));
    return Number.isFinite(px) && px >= SIZE_MIN && px <= SIZE_MAX ? px : null;
  };
  const normalizeSize = value => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null;
    const clean = {};
    const answer = sizePx(value.answer);
    const question = sizePx(value.question);
    if (answer != null) clean.answer = answer;
    if (question != null) clean.question = question;
    return Object.keys(clean).length ? clean : null;
  };
  // У КОМАНДЫ размера (WF19) половина знает три состояния, у записи в хранилище —
  // по-прежнему два. Поэтому разбор команды живёт отдельной функцией, а
  // normalizeSize и карта LAYER_NORMALIZE остаются нетронутыми: ту же normalizeSize
  // зовёт entryLayer на КАЖДОМ чтении записи карты, и половина со значением null
  // значит там «слоя нет» — тристейт, вкрученный в неё, потёк бы в хранилище
  // (разбор критика WF19, В1).
  //   поля нет    — половину не трогаем;
  //   число 11…24 — поставить;
  //   ровно null  — снять ЭТУ половину, вторая остаётся как была.
  // Дискриминатор снятия строгий (В2): только литеральный null. sizePx одинаково
  // отдаёт null и на null, и на "abc", и мусор вида {"answer":"abc"} без этого
  // читался бы как снятие. Мусор равен отсутствию поля, как и раньше.
  // Ни одного значимого ключа не осталось (пустой объект, один мусор) — слой равен
  // null, то есть полный сброс: ровно так же читался старый {}.
  const SIZE_HALVES = ["answer", "question"];
  const normalizeSizeCommand = value => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null;
    const clean = {};
    for (const half of SIZE_HALVES) {
      if (!(half in value)) continue;
      if (value[half] === null) { clean[half] = null; continue; }
      const px = sizePx(value[half]);
      if (px != null) clean[half] = px;
    }
    return Object.keys(clean).length ? clean : null;
  };
  // Рамка — слой-тумблер: значение у него ровно одно, true. Всё остальное (в том
  // числе false и "none") доходит сюда как «слоя нет» либо как сброс.
  const normalizeFrame = value => (value === true ? true : null);

  // Отдельная таблица стилей (см. sizeSheet ниже). Цветов в ней нет ВОВСЕ: размер
  // и тема — разные слои, и правило размера обязано пережить любую смену темы.
  const sizeRule = (selectors, suffix, body) =>
    `${selectors.map(item => (suffix ? `${item} ${suffix}` : item)).join(", ")} { ${body} }`;
  const sizeCss = size => {
    const rules = ["/* PimpMyClaude · размер текста сообщений */"];
    if (size.answer) {
      rules.push(sizeRule(SIZE_ANSWER_SELECTORS, "",
        `font-size: ${size.answer}px !important; line-height: 1.5 !important;`));
      for (const [tag, scale] of SIZE_HEADINGS) {
        rules.push(sizeRule(SIZE_ANSWER_SELECTORS, tag, `font-size: ${scale}em !important;`));
      }
      rules.push(sizeRule(SIZE_ANSWER_SELECTORS, ":is(code, pre, kbd, samp)",
        `font-size: ${SIZE_CODE_SCALE}em !important;`));
      // Блок кода — <pre><code>: второй проход em гасим, иначе 0.9 × 0.9.
      rules.push(sizeRule(SIZE_ANSWER_SELECTORS, ":is(pre, kbd, samp) :is(code, kbd, samp)",
        "font-size: 1em !important;"));
    }
    if (size.question) {
      rules.push(sizeRule(SIZE_QUESTION_SELECTORS, "",
        `font-size: ${size.question}px !important; line-height: 1.5 !important;`));
    }
    return `${rules.join("\n")}\n`;
  };

  // Свет рамки — три тени внутрь одним цветом: линия в две точки, широкий ореол
  // и второй проход по нему, отчего свет плотнее у самой кромки. Приём тот же,
  // что у полосы прогресса (раздел 2б), и цвет тот же — акцент темы.
  const frameShadow = accent =>
    `inset 0 0 0 2px ${accent}, inset 0 0 18px ${accent}, inset 0 0 6px ${accent}`;

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
  // WF35 добавил к этому `id:<id чата>` и сделал его ГЛАВНЫМ ключом чата:
  // приоритет по слою `id:` → `chat:` → сессия → `main` → `*`, пишутся оба
  // ключа чата разом, а первое совпадение копирует старую запись на `id:`
  // (migrateChatKey). Старую запись не удаляем: по ней ещё живут окна, которые
  // своего id не знают.
  // Красим только окна Claude: claude.ai (главное) и about:blank («Open in new
  // window»). Артефакты, браузерная панель (data:) и file: — не наши.
  const themable = /^(https:\/\/claude\.ai\/|about:blank)/.test(location.href);
  const THEME_MAIN_KEY = "main";
  const THEME_CHAT_PREFIX = "chat:";
  const THEME_LEGACY_PREFIX = "w:";
  // WF35: главный ключ чата — его id (`id:local_<uuid>`), а не имя. Имя чата
  // Элвис меняет, id — нет, и после переименования ключ `chat:<старое имя>`
  // больше никем не читался: окно теряло цвет (пункт 20 списка 05.09).
  const THEME_ID_PREFIX = "id:";
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
  const chatTitleKey = () => {
    if (!themable) return null;
    const title = windowTitle();
    if (!title || THEME_TITLE_STUBS.has(title.toLowerCase())) return null;
    return `${THEME_CHAT_PREFIX}${title}`;
  };
  // Ключ по id чата (WF35). Проверка themable стоит явно, а не достаётся от
  // myChatId: раздел 12в про ключи темы ничего не обещает, а чужая страница
  // (артефакт, браузерная панель) не должна давать ключа вовсе. Заголовок-
  // заглушка при известном id ключом ТЕПЕРЬ становится — у безымянного чата
  // тоже есть id, и выбранный в нём цвет обязан остаться, когда имя появится.
  // Осечка myChatId (раздел 12в лежит ниже, источники id у него чужие) не должна
  // уносить с собой всю тему окна: id неизвестен — работаем по имени чата, ровно
  // как деградирует адресация WF29.
  const chatIdKey = () => {
    if (!themable) return null;
    let id = null;
    try { id = myChatId(); } catch { id = null; }
    return typeof id === "string" && id ? `${THEME_ID_PREFIX}${id}` : null;
  };
  // Действующий ключ чата: id сильнее имени, имя — тень для окон, которые своего
  // id ещё не знают (попап в первые секунды: карту попапов наполняет probe).
  const chatKey = () => chatIdKey() ?? chatTitleKey();
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
  // Слоёв четыре, и каждый хранится трёхзначно: значение — оно самое, "none" —
  // явный сброс («Как у Claude» это тоже выбор, иначе окно на следующем инжекте
  // покрасилось бы обратно из карты), поля нет — слоя не касались. Поэтому
  // запись окна — объект { theme, font, size, frame }, а не одна тема, как было
  // в WF5. Порядок важен: рамка идёт ПОСЛЕ темы, потому что берёт её акцент, и
  // на восстановлении цвет к тому времени уже на месте.
  const THEME_LAYERS = ["theme", "font", "size", "frame"];
  const LAYER_NORMALIZE = {
    theme: normalizeTheme, font: normalizeFont, size: normalizeSize, frame: normalizeFrame,
  };
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
  // Запись ЭТОГО чата: сперва по id, потом по имени (WF35). Порядок и есть
  // приоритет `id:` → `chat:` — им пользуются все три места чтения карты.
  const chatEntry = map => mapEntry(map, chatIdKey()) ?? mapEntry(map, chatTitleKey());
  // Первое совпадение переносит запись имени на id — КОПИЕЙ, старую оставляем:
  // по ней ещё живёт окно, которое своего id не знает (попап в первые секунды,
  // непропатченная страница). Зовётся трижды: на инжекте, в syncChatTheme (у
  // попапа id появляется ПОЗЖЕ инжекта) и первой строкой writeLayers — иначе
  // запись `id:` создалась бы с одним слоем и навсегда закрыла бы более полную
  // тень `chat:`, а остальные слои чата пропали бы с экрана.
  const migrateChatKey = () => {
    const idKey = chatIdKey();
    if (!idKey) return;
    const map = readThemeMap();
    if (map[idKey] !== undefined) return;
    const entry = mapEntry(map, chatTitleKey());
    if (!entry || Object.keys(entry).length === 0) return;
    map[idKey] = entry;
    writeThemeMap(map);
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
    // Ключей чата теперь два (WF35), и принимать надо ОБА: сессии, записанные до
    // обновления, лежат под именем чата, свежие — под id. Признай мы только один,
    // окна Элвиса разово потеряли бы слой сессии.
    for (const chat of [chatIdKey(), chatTitleKey()]) if (chat && stored === chat) return true;
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
  // previewLayers — какие именно слои сейчас примерены (WF31, #5453): новая
  // примерка возвращает из хранилища те из них, которых в ней нет, — цвет
  // всегда смотрится с УСТАНОВЛЕННЫМ шрифтом, а шрифт с установленным цветом.
  // chatKey — заголовок, под который окно уже покрашено: сторож (watchChatTitle)
  // сверяет его с нынешним и на смене чата перекрашивает окно. pending — выбор,
  // сделанный до появления заголовка: дописываем его, когда ключ чата появится.
  const themeState = {
    theme: null, source: null, font: null, fontSource: null, previewing: false, previewLayers: [],
    size: null, sizeSource: null, frame: false, frameSource: null,
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
  // Размер — третья таблица по тому же доводу: сменить размер, не тронув ни
  // цветов, ни шрифта.
  const sizeSheet = new CSSStyleSheet();
  const detachSheet = sheet => {
    try { document.adoptedStyleSheets = document.adoptedStyleSheets.filter(item => item !== sheet); } catch {}
  };
  const adoptSheet = sheet => {
    try {
      document.adoptedStyleSheets = [...document.adoptedStyleSheets.filter(item => item !== sheet), sheet];
      return true;
    } catch { return false; }
  };
  track(() => { detachSheet(themeSheet); detachSheet(fontSheet); detachSheet(sizeSheet); });
  // Сироты от прежней реализации (<style id=…>, в том числе зеркальные копии) и
  // оверлей рамки от упавшей на середине установки.
  for (const orphan of document.querySelectorAll(`#${THEME_STYLE_ID}`)) orphan.remove();
  for (const orphan of document.querySelectorAll(`#${WINDOW_FRAME_ID}`)) orphan.remove();

  // Акцент окна: у Claude и у наших тем (themeCss выше) --accent-brand хранит не
  // цвет, а тройку HSL — «251.000 40.000% 54.500%». Подставить её как есть
  // нельзя, объявление отбросится, поэтому тройку заворачиваем в hsl() сами, а на
  // всё незнакомое берём фиолетовый донора. Одним цветом живут рамка окна и
  // полоса прогресса (раздел 2б) — на то он и акцент.
  const ACCENT_FALLBACK = "#8b5cf6";
  const accentColor = () => {
    let raw = "";
    // В окне Claude Code палитра живёт на .epitaxy-root, а не на html.
    try {
      const host = state.composerBlock ?? document.querySelector(".epitaxy-root") ?? document.documentElement;
      raw = getComputedStyle(host).getPropertyValue("--accent-brand").trim();
    } catch {}
    if (!raw) return ACCENT_FALLBACK;
    if (/^(?:#|rgba?\(|hsla?\(|oklch\(|lab\(|lch\(|color\()/i.test(raw)) return raw;
    if (/^[\d.]+(?:deg)?\s+[\d.]+%\s+[\d.]+%$/.test(raw)) return `hsl(${raw})`;
    return ACCENT_FALLBACK;
  };

  // Рамка — не таблица стилей, а свой узел: правило пришлось бы вешать на body
  // или :root, а у них уже есть и фон темы, и тени самого Claude. Оверлей ничего
  // не ловит мышью (pointer-events:none) и ни на что в разметке не влияет.
  const frameNode = document.createElement("div");
  frameNode.id = WINDOW_FRAME_ID;
  frameNode.setAttribute("aria-hidden", "true");
  for (const [name, value] of Object.entries({
    position: "fixed", inset: "0px", display: "none", "pointer-events": "none",
    "border-radius": `${WINDOW_FRAME_RADIUS}px`, "z-index": WINDOW_FRAME_Z,
  })) frameNode.style.setProperty(name, value);
  (document.body ?? document.documentElement).appendChild(frameNode);
  track(() => frameNode.remove());
  // Цвет у рамки не свой, а темин: сменилась тема — перекрашиваем. Инлайновая
  // тень хранит уже вычисленный цвет и сама за переменной не поедет.
  const paintFrame = () => {
    if (themeState.frame !== true) return;
    frameNode.style.setProperty("box-shadow", frameShadow(accentColor()));
  };
  const removeFrame = source => {
    themeState.frame = false;
    themeState.frameSource = source ?? null;
    frameNode.style.setProperty("display", "none");
  };
  const applyFrame = (value, source) => {
    if (normalizeFrame(value) !== true) { removeFrame(source); return null; }
    themeState.frame = true;
    themeState.frameSource = source ?? null;
    frameNode.style.setProperty("display", "block");
    paintFrame();
    return true;
  };

  const removeTheme = source => {
    detachSheet(themeSheet);
    try { themeSheet.replaceSync(""); } catch {}
    themeState.theme = null;
    themeState.source = source ?? null;
    paintFrame();
  };
  const applyTheme = (theme, source) => {
    const clean = normalizeTheme(theme);
    if (!clean) { removeTheme(source); return null; }
    try { themeSheet.replaceSync(themeCss(clean)); } catch { return null; }
    if (!adoptSheet(themeSheet)) return null;
    themeState.theme = clean;
    themeState.source = source ?? null;
    paintFrame();
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
  // Размер поля ввода и ручки не касается — трогает только текст сообщений, —
  // поэтому кэш обычной высоты (state.natural), в отличие от шрифта, не сбрасываем.
  const removeSize = source => {
    detachSheet(sizeSheet);
    try { sizeSheet.replaceSync(""); } catch {}
    themeState.size = null;
    themeState.sizeSource = source ?? null;
  };
  const applySize = (size, source) => {
    const clean = normalizeSize(size);
    if (!clean) { removeSize(source); return null; }
    try { sizeSheet.replaceSync(sizeCss(clean)); } catch { return null; }
    if (!adoptSheet(sizeSheet)) return null;
    themeState.size = clean;
    themeState.sizeSource = source ?? null;
    return clean;
  };
  const applyLayer = (layer, value, source) => {
    if (layer === "font") { if (value) applyFont(value, source); else removeFont(source); return; }
    if (layer === "size") { if (value) applySize(value, source); else removeSize(source); return; }
    if (layer === "frame") { applyFrame(value, source); return; }
    if (value) applyTheme(value, source); else removeTheme(source);
  };
  const applyLayers = (layers, source) => {
    for (const layer of THEME_LAYERS) if (layer in layers) applyLayer(layer, layers[layer], source);
  };

  // Порядок восстановления у КАЖДОГО слоя свой: запись чата (`id:<id>`, а нет её
  // — `chat:<заголовок>`; см. chatEntry) → своя сессия окна → у главного окна
  // запись окна (`main`) → запись «для всех». Чат стоит ПЕРВЫМ нарочно: сессия у
  // окна одна на все разговоры, и
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
    const chat = chatEntry(map);
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

  // То же значение слоя, что взяло бы восстановление, но БЕЗ применения: нужно
  // размеру, у которого половинки независимы, — команда «размер ответов 16» без
  // этого стёрла бы выбранный размер вопросов.
  const storedLayer = layer => {
    if (!themable) return null;
    const map = readThemeMap();
    const chain = [
      chatEntry(map),
      readSessionEntry(),
      isMainWindow() ? mapEntry(map, THEME_MAIN_KEY) : null,
      themeEntry(map[THEME_ALL_KEY]),
    ];
    for (const entry of chain) {
      const value = entryLayer(entry, layer);
      if (value !== undefined) return value;
    }
    return null;
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
  // WF35: пока id известен, пишем ОБА ключа чата — id главный, имя остаётся
  // тенью для окон, которые id ещё не знают.
  const writeKeys = () => {
    const keys = [];
    const id = chatIdKey();
    if (id) keys.push(id);
    const title = chatTitleKey();
    if (title) keys.push(title);
    if (isMainWindow()) keys.push(THEME_MAIN_KEY);
    return keys;
  };
  const writeLayers = layers => {
    // Перенос ДО записи обязателен: setMapLayers начинает с mapEntry(map, key),
    // и без переноса запись `id:` родилась бы с одним слоем этой команды.
    migrateChatKey();
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
    const entry = chatEntry(readThemeMap());
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
    // Пока идёт предпросмотр, на экране намеренно не то, что в хранилище: ключ не
    // запоминаем, чтобы смена чата не «съелась» и применилась после конца примерки.
    if (themeState.previewing) return;
    themeState.chatKey = key;
    // Сначала дописываем несохранённый выбор: иначе восстановление затрёт на
    // экране только что выбранную тему.
    flushPendingLayers();
    // У попапа id приезжает ПОЗЖЕ инжекта (карту попапов наполняет probe), и без
    // этого вызова перенос записи на `id:` в попапе не случился бы никогда.
    try { migrateChatKey(); } catch {}
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
  // Необязательное поле match (WF15) адресует окно ПУТЁМ страницы
  // ("/epitaxy/local_<id>" — приложение берёт его из status.json лоадера) и
  // сильнее заголовка: у главного окна на вкладке Claude Code заголовок —
  // заглушка «Claude», и такой же носят безымянные попапы, так что команда
  // по заголовку ушла бы веером им всем. Поля нет — поведение прежнее.
  // Необязательное поле chat (WF29) адресует окно ID ЧАТА и стоит МЕЖДУ match и
  // заголовком: у попапа путь — "blank", и match ему бесполезен, а заголовок он
  // носит снимком имени чата на момент выноса в окно — чат с тех пор могли
  // переименовать, и по заголовку окно не опознаётся вовсе (задача #5455).
  // Свой id страница знает синхронно (myChatId(), раздел 12в): главное окно —
  // из пути, попап — из кэша ответа родителя. Команда приходит событием, ждать
  // промиса ей нечем; id неизвестен — команда не наша, и приложение пришлёт её
  // заголовком на следующем тике. Лучше не покраситься, чем покраситься чужим
  // проектом. match и chat разом приложение не шлёт никогда.
  const addressed = detail => {
    if (typeof detail.match === "string") return location.pathname === detail.match;
    if (typeof detail.chat === "string") {
      const id = myChatId();
      return Boolean(detail.chat) && id === detail.chat;
    }
    const title = typeof detail.title === "string" ? detail.title.trim() : "";
    return title ? (document.title || "").trim() === title : document.hasFocus();
  };

  // Команда меню, порядок полей по контракту WF12: {id, action:"theme", at,
  // scope:"window"|"all", title, preview, theme|null, font|null,
  // size:{answer?,question?}|null, frame:true|null}.
  // Поля слоя нет — слой не трогаем, null — сброс слоя, значение — применить.
  // У размера то же правило действует и на КАЖДУЮ половину (WF19): поля половины
  // нет — не трогаем, число — поставить, null — снять её одну («Как у Claude» в
  // «Размер ответов ▸» не уносит с собой размер вопросов). "size":null по-прежнему
  // снимает обе — этим ходит «🧹 Всё как у Claude».
  // «Для всех» перекрывает СВОЙ слой у всех окон и чужой не трогает: «шрифт
  // всем» не снимает тем у окон, «тема всем» не снимает их шрифтов.
  // «Для окна» адресуется заголовком, как «Обкэшить», либо необязательным
  // полем match — путём страницы (WF15, см. addressed()).
  // Примерка была, а закрепили не все слои: остальные — назад из хранилища.
  const endPreviewExcept = committedLayers => {
    if (!themeState.previewing) return;
    themeState.previewing = false;
    themeState.previewLayers = [];
    const rest = THEME_LAYERS.filter(layer => !committedLayers.includes(layer));
    if (rest.length) restoreTheme(true, rest);
  };

  const runThemeCommand = detail => {
    if (!themable || !detail || typeof detail !== "object") return false;
    const layers = {};
    for (const layer of THEME_LAYERS) {
      if (!(layer in detail)) continue;
      // Размер — единственный слой, у которого команда богаче записи: половину
      // можно снять по отдельности (WF19, normalizeSizeCommand). Остальные слои
      // разбирает общая карта.
      layers[layer] = layer === "size"
        ? normalizeSizeCommand(detail[layer])
        : LAYER_NORMALIZE[layer](detail[layer]);
    }
    // Размер — единственный слой с половинками: «Размер ответов ▸ 16» приходит
    // без поля question, и оно обязано остаться прежним. Недостающую половину
    // дописываем здесь, и дальше слой ходит по коду цельным, как тема и шрифт.
    // Основа у примерки — то, что сейчас на экране (мышь ведут по подменю и
    // половинки примеряются одна за другой), у закрепления — хранилище: иначе
    // выбор «размер вопросов» утащил бы за собой примеренный размер ответов.
    if (layers.size) {
      const base = detail.preview === true
        ? themeState.size
        : (detail.scope === "all"
          ? entryLayer(themeEntry(readThemeMap()[THEME_ALL_KEY]), "size")
          : storedLayer("size"));
      const merged = { ...(base ?? {}), ...layers.size };
      // Единственное место, где снятая половина исчезает, — сразу после слияния и
      // ДО экрана (applyLayers), карты (writeLayers), сессии (storeSessionLayers) и
      // отложенной записи (themeState.pending): в хранилище половина со значением
      // null читается как «слоя нет» (entryLayer), и запись вышла бы неверной.
      for (const half of SIZE_HALVES) if (merged[half] == null) delete merged[half];
      // Снята последняя половина — слоя больше нет вовсе: это полный сброс, как
      // "size":null (и как старый пустой {}).
      layers.size = Object.keys(merged).length ? merged : null;
    }
    // Предпросмотр (мышь ведут по подменю тем и шрифтов): слои из команды идут
    // ТОЛЬКО в таблицы стилей, хранилища они не касаются вовсе — иначе проход
    // по списку записал бы в карту каждую тему, мимо которой проехала мышь.
    // Предпросмотр всегда адресован одному окну, scope тут не при чём.
    if (detail.preview === true) {
      if (Object.keys(layers).length === 0 || !addressed(detail)) return false;
      // Новая примерка перекрывает прежнюю (WF31, #5453): слои, которые примерялись
      // до неё и в эту команду не попали, возвращаются из хранилища. Иначе проезд по
      // «🔤 Шрифт ▸» оставлял бы чужой шрифт на всех цветах, мимо которых мышь пойдёт
      // дальше. Возврат стоит ПОСЛЕ guard нарочно: команда, адресованная ЧУЖОМУ окну,
      // наши слои не трогает вовсе.
      const rest = themeState.previewLayers.filter(layer => !(layer in layers));
      if (rest.length) restoreTheme(true, rest);
      applyLayers(layers, "preview");
      themeState.previewing = true;
      themeState.previewLayers = Object.keys(layers);
      return true;
    }
    // Конец предпросмотра: меню закрылось, ничего не выбрав. Оба слоя
    // возвращаем из хранилища, а слой, записи о котором нигде нет, снимаем.
    if (detail.preview === false && Object.keys(layers).length === 0) {
      if (!addressed(detail)) return false;
      restoreTheme(true);
      themeState.previewing = false;
      themeState.previewLayers = [];
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

  // Возврат тем после переустановки Claude (WF35). Переустановка стирает
  // localStorage страниц — вместе с ним умирает вся карта тем, и пять окон
  // Элвиса становятся серыми (#5473). Копию карты держит приложение в файле
  // ~/Library/Application Support/MyClaude/window-themes.json и присылает её
  // одной командой на все окна:
  //   {id, action:"themes-restore", at, scope:"all", entries:{<ключ>:{theme?,font?,size?,frame?}}}
  // Страница НЕ заменяет свою память присланной, а ДОЛИВАЕТ недостающие слои:
  // так команда идемпотентна (память цела — не меняется ни байта), и спрашивать
  // окно «ты пуста?» не нужно вовсе. Явный сброс приезжает маркером "none" и
  // остаётся сбросом — «Как у Claude» переживает переустановку наравне с цветом.
  const RESTORE_KEY_LIMIT = 200;
  const RESTORE_KEY_MAX_LENGTH = 200;
  // Ключ из чужих рук: только наши пять видов и без пустого хвоста у префикса.
  const restoreKeyOk = key => {
    if (typeof key !== "string" || !key.length || key.length > RESTORE_KEY_MAX_LENGTH) return false;
    if (key === THEME_ALL_KEY || key === THEME_MAIN_KEY) return true;
    for (const prefix of [THEME_ID_PREFIX, THEME_CHAT_PREFIX, THEME_LEGACY_PREFIX]) {
      if (key.startsWith(prefix)) return key.length > prefix.length;
    }
    return false;
  };
  // Слой из чужих рук: "none"/null — сброс, значение — через ту же нормализацию,
  // что и команда меню; мусор равен отсутствию слоя.
  const restoreLayer = (entry, layer) => {
    if (!(layer in entry)) return undefined;
    const raw = entry[layer];
    if (raw === "none" || raw == null) return "none";
    return LAYER_NORMALIZE[layer](raw) ?? undefined;
  };
  const restoreState = { at: 0, keys: 0, merged: 0, painted: false };
  const runThemesRestoreCommand = detail => {
    if (!themable || !detail || typeof detail !== "object") return false;
    const entries = detail.entries;
    if (!entries || typeof entries !== "object" || Array.isArray(entries)) return false;
    const map = readThemeMap();
    let keys = 0;
    let merged = 0;
    for (const [key, value] of Object.entries(entries)) {
      if (keys >= RESTORE_KEY_LIMIT) break;
      if (!restoreKeyOk(key)) continue;
      const incoming = themeEntry(value);
      keys += 1;
      const current = mapEntry(map, key);
      const entry = current ? { ...current } : {};
      let added = 0;
      for (const layer of THEME_LAYERS) {
        // Всё, что у страницы уже есть, не трогаем вовсе — в том числе "none".
        if (current && layer in current) continue;
        const next = restoreLayer(incoming, layer);
        if (next === undefined) continue;
        entry[layer] = next;
        added += 1;
      }
      if (!added) continue;
      map[key] = entry;
      merged += added;
    }
    if (merged) writeThemeMap(map);
    restoreState.at = now();
    restoreState.keys = keys;
    restoreState.merged = merged;
    // Экран трогаем, только если он наш: примерка мышью и живые цвета показывают
    // не то, что в хранилище, и перекраска сбила бы их обоих.
    restoreState.painted = !themeState.previewing && !liveState.on;
    if (restoreState.painted) { try { restoreTheme(false); } catch {} }
    return true;
  };

  // Осечка темы не должна утащить за собой ручку: раздел стоит выше её
  // постройки, и без этой обёртки любое падение на неготовой разметке оставило
  // бы окно вовсе без полоски.
  try { migrateChatKey(); restoreTheme(); watchChatTitle(); } catch {}

  // ---- 2б. Полоса прогресса воркфлоу --------------------------------------
  // Тонкая светящаяся линия на нижней кромке рамки поля ввода: насколько прошёл
  // марафон воркфлоу. Вид взят у «полосы кэша» донора ElvisOS
  // (Resources/claude-chat-cleaner-inject.js): две точки высотой, свечение двумя
  // тенями, заливка едет плавно.
  //
  // WF11 (плавный хвост): лента чата виртуальная, при прокрутке в неё попадают
  // разные строки состояния — число сегментов гуляет. Раньше на каждую смену
  // числа узлы пересоздавались, и вся полоса заново росла с нуля. Теперь узлы
  // живут в пуле: меняется только хвост (недостающие проявляются, лишние гаснут),
  // а заливка уже нарисованных сегментов едет от прежнего значения к новому.
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
  // По той же причине и наведение, и клик ловятся общими слушателями документа,
  // а не прозрачной накладкой над линией: накладка стояла бы поверх низа поля
  // ввода и съедала клики по нему.
  //
  // WF12 (подсказка по клику): наведение больше ничего не показывает — только
  // ставит «руку» в ±4 точках от линии. Подсказка открывается кликом по сегменту
  // и рассказывает про ОДИН воркфлоу, а не про весь марафон разом: раньше она
  // выскакивала сама, стоило мыши пройти над полем ввода, и закрывала пол-окна
  // сводкой. Повторный клик по тому же сегменту, Escape и клик мимо — закрывают.
  //
  // Отступление от плана: полоса не absolute внутри блока ввода, а fixed по
  // координатам — как и сама ручка. Довод записан в разделе 4 прямым текстом:
  // рамка поля живёт в чужом дереве, и свой узел туда лучше не вставлять. React
  // пересобирает низ окна на каждую смену модели, а position:absolute потребовал
  // бы ещё и менять position у чужого контейнера. Место на экране от этого не
  // меняется: считаем его по boundingClientRect рамки поля.
  const PROGRESS_ID = "myclaude-progress-bar";
  const PROGRESS_TIP_ID = "myclaude-progress-tip";
  const PROGRESS_CARD_ID = "myclaude-progress-card";
  // Вид карточки сегмента по макету docs/mockup-wf22-cards.html. Элвис выбрал
  // 3A — «таблица с цветной кромкой»; назовёт 3B или 3C, меняется эта строка и
  // вид карточки, а данные, разбор и попадание мышью общие для всех трёх.
  const PROGRESS_CARD_VARIANT = "3A";
  // Ширина едет 400 мс: быстрее — дёрганье на каждом ответе, медленнее — полоса
  // заметно отстаёт от цифры в чате. Тем же временем живут проявление и
  // затухание сегментов и смена цвета состояния — движение у полосы одно.
  const PROGRESS_MOVE_MS = 400;
  // Погасший сегмент убираем чуть позже конца затухания. Таймером, а не по
  // transitionend: в свёрнутом окне переходы не идут и событие не придёт вовсе,
  // а узел с opacity 0 остался бы висеть в разметке до самой смены числа.
  const PROGRESS_DROP_MS = PROGRESS_MOVE_MS + 120;
  // Перечитывать ленту чаще раза в секунду незачем: строка состояния меняется
  // раз в ответ, а innerText сообщения — это принудительный reflow.
  const PROGRESS_MIN_GAP = 1000;
  // Страховочный перечёт: в тихом окне мутаций ленты может не быть вовсе.
  const PROGRESS_IDLE_MS = 10000;
  // Сколько последних ответов просматриваем. Строку состояния пишет каждый
  // ответ, поэтому дальше десятка забираться незачем, а перечитывать весь
  // длинный разговор раз в секунду — уже заметная работа.
  const PROGRESS_LOOKBACK = 12;
  // Цвет по состоянию: ждём Элвиса — жёлтый, упало — красный, «готово» —
  // зелёный (буква Элвиса 1A, WF22); «идёт» берёт акцент темы окна (её красит
  // раздел 2а). Жёлтый и красный достаются ТЕКУЩЕМУ сегменту — красным метится
  // ровно то место, где марафон встал; зелёное «готово» красит всю полосу.
  const PROGRESS_PAINT = { done: "#4dbb7d", wait: "#f5c542", fail: "#ef4444" };
  // Зазор между сегментами и их предельное число. Марафон длиннее сорока
  // воркфлоу — уже не марафон, а полоса из одних зазоров.
  const PROGRESS_SEG_GAP = 3;
  const PROGRESS_SEG_MAX = 40;
  // Уже трёх точек сегмент не читается: тогда рисуем одну сплошную долю.
  const PROGRESS_SEG_MIN = 6;
  // Высота линии и допуск попадания по ней: ±4 точки по вертикали (план WF12,
  // п. 3). Зона узкая нарочно — внутри неё курсор становится «рукой», а клик
  // достаётся полосе, а не полю ввода под ней, и промахиваться этим по полю
  // Элвис не должен.
  const PROGRESS_BAR_HEIGHT = 2;
  const PROGRESS_HIT_SLACK = 4;
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
  // Номер — ЦЕПОЧКА клавиш, а не одна (WF22): «2️⃣9️⃣» это 29, «4️⃣0️⃣» — 40, «🔟» — 10.
  // Читалась первая клавиша, и весь четвёртый десяток сводки числился четвёртым
  // воркфлоу.
  const STATUS_HEAD_RE = /^((?:\d\uFE0F?\u20E3|\u{1F51F})+)\s*(.*)$/u;
  const STATUS_KEYCAP_RE = /\d\uFE0F?\u20E3|\u{1F51F}/gu;
  const STATUS_DEFAULT_ICON = "⬜";
  // Четыре этапа воркфлоу (AGENTS.md): по ним заливается идущий сегмент и
  // строится карточка. Пятая роль в сводке («макет» и подобные) на заливку не
  // влияет и в карточку не идёт — этапов по букве Элвиса ровно четыре.
  const STATUS_STAGES = [
    { key: "plan", label: "план", re: /^план/i },
    { key: "critic", label: "критик", re: /^критик/i },
    { key: "code", label: "кодинг", re: /^кодинг/i },
    { key: "check", label: "проверка", re: /^проверк/i },
  ];
  const STATUS_EFFORT_RE = /\s(low|medium|high|xhigh|max)$/i;
  // Шапка сводки — три строки счёта («41 воркфлоу», «26 готово», «39 ч»): они
  // уходят в подвал карточки.
  const STATUS_HEAD_LINES = 3;
  const statusFeed = { at: 0, projects: new Map() };

  // Строка подсказки из блока. Вид её закреплён тестами знак в знак: разбор
  // переехал в объекты (WF22), а строка осталась прежней.
  const statusLine = (block) => {
    const roles = block.roles.slice(0, 6).map(role => role.role).join(" · ");
    const line = [`${block.mark} ${block.icon}`, block.about, roles]
      .filter(Boolean).join(" · ").replace(/\s+/g, " ").trim();
    return line.length > STATUS_LINE_MAX ? `${line.slice(0, STATUS_LINE_MAX - 1)}…` : line;
  };
  // Номер воркфлоу, с которого начинается строка сводки: «3️⃣ …» → 3, «🔟 …» → 10,
  // «2️⃣9️⃣ …» → 29. Разбираем по цифрам клавиш, а не по готовому значку: в сводке
  // встречается и запись без вариационного селектора («3⃣»), и та и другая — один
  // и тот же номер.
  const statusLineNumber = (line) => {
    const head = String(line ?? "").match(STATUS_HEAD_RE);
    if (!head) return null;
    let digits = "";
    for (const cap of head[1].match(STATUS_KEYCAP_RE) ?? []) {
      digits += cap === "\u{1F51F}" ? "10" : (cap.match(/\d/)?.[0] ?? "");
    }
    const number = Number(digits);
    return digits !== "" && Number.isFinite(number) ? number : null;
  };
  // Строка роли: «- кодинг · 2 агента · Opus max». Кто (агенты) и на чём (модель,
  // эффорт) стоят в любом порядке, части может не быть вовсе («- кодинг · Opus
  // max», «- проверка · 🔴 **Fable max**»). Значок 💭 в конце — необязательная
  // пометка идущего этапа (правило AGENTS.md пишет чат Max).
  const statusRole = (item) => {
    const running = /💭\s*$/.test(item);
    const parts = item.replace(/💭\s*$/, "").split(/\s*[·•]\s*/).map(part => part.trim()).filter(Boolean);
    const rest = parts.slice(1);
    const agentsAt = rest.findIndex(part => /аген/i.test(part) || part === "я" || part.startsWith("я "));
    // Жирное начертание и красный кружок «Fable max» — разметка сводки, а не имя
    // модели: снимаем их здесь, рисует их карточка сама.
    const who = rest.filter((part, index) => index !== agentsAt).join(" · ")
      .replace(/\*\*/g, "").replace(/^[^\p{L}\p{N}]+/u, "").trim();
    const effort = who.match(STATUS_EFFORT_RE);
    return {
      role: parts[0] ?? "",
      agents: agentsAt >= 0 ? rest[agentsAt] : "",
      model: effort ? who.slice(0, who.length - effort[0].length).trim() : who,
      effort: effort ? effort[1] : "",
      running,
    };
  };
  // Сводка написана списками, а не таблицей, поэтому разбираем построчно:
  // заголовок блока даёт номер и значок, первый пункт — «о чём», пункты с
  // разделителем и словом впереди — роли, «шаги N из M» и время — свои поля.
  // Разбор ОДИН на три читателя (WF22): строки подсказки, объекты блоков для
  // карточки и заливки, шапка проекта. Порядок проверок внутри цикла менять
  // нельзя — на нём стоят строки подсказки знак в знак.
  const statusParse = (text) => {
    const head = [];
    const blocks = [];
    let current = null;
    const flush = () => { if (current) blocks.push(current); current = null; };
    for (const raw of String(text ?? "").split("\n")) {
      const line = raw.trim();
      const title = line.match(STATUS_HEAD_RE);
      if (title) {
        flush();
        const hit = PROGRESS_STATES.find(([icon]) => (title[2] ?? "").includes(icon));
        current = {
          number: statusLineNumber(line), mark: title[1],
          icon: hit ? hit[0] : STATUS_DEFAULT_ICON, state: hit ? hit[1] : "todo",
          about: "", steps: null, time: "", roles: [],
        };
        continue;
      }
      if (!current) {
        // Шапка: три строки счёта, каждая начинается с числа.
        if (head.length < STATUS_HEAD_LINES && /^[-*]?\s*\d/.test(line)) head.push(line.replace(/^[-*]\s*/, ""));
        continue;
      }
      if (!/^[-*]\s/.test(line)) continue;
      const item = line.replace(/^[-*]\s*/, "").trim();
      if (!item) continue;
      const steps = item.match(/^шаги\s+(\d+)\s+из\s+(\d+)/i);
      if (steps && !current.steps) current.steps = { done: Number(steps[1]), total: Number(steps[2]) };
      if (!current.about && !/^шаги\b/i.test(item) && !/\d\s*:\s*\d/.test(item)) {
        current.about = item.replace(/^о\s+чём\s*:\s*/i, "");
        continue;
      }
      if (!current.time && /\d\s*:\s*\d/.test(item)) { current.time = item; continue; }
      const role = item.split(/\s*[·•]\s*/)[0] ?? "";
      if (item.includes("·") && !item.includes("→") && role && !/\d/.test(role)) current.roles.push(statusRole(item));
    }
    flush();
    // Подсказка не должна вырастать в простыню: последние двенадцать воркфлоу.
    return { head, blocks, lines: blocks.map(statusLine).slice(-STATUS_MAX_LINES) };
  };
  const statusBlocks = (text) => statusParse(text).blocks;
  const statusLines = (text) => statusParse(text).lines;
  // Имя проекта в строке состояния и имя папки, которое прислало приложение,
  // совпадают не побуквенно (регистр, дефисы). Сравниваем по буквам и цифрам.
  const statusKey = (name) => String(name ?? "").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "");
  // Точное имя выигрывает всегда, а по началу имени отвечаем ТОЛЬКО когда такой
  // сосед один (WF22): «VkusnoffKz» рядом с «VkusnoffKz-deploy» выбирался
  // алфавитом, то есть случайно.
  const statusFeedProject = (project) => {
    const key = statusKey(project);
    if (!key) return null;
    let near = null;
    let count = 0;
    for (const [name, item] of statusFeed.projects) {
      const other = statusKey(name);
      if (!other) continue;
      if (other === key) return item;
      if (other.startsWith(key) || key.startsWith(other)) { near = item; count += 1; }
    }
    return count === 1 ? near : null;
  };
  const statusFeedLines = (project) => statusFeedProject(project)?.lines ?? [];
  // Команда снаружи: разбираем сразу, а не при показе карточки — разбор дешевле
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
      // в карточке хуже, чем её отсутствие.
      budget -= name.length + text.length;
      if (budget < 0) break;
      next.set(name, statusParse(text));
    }
    statusFeed.projects = next;
    statusFeed.at = Date.now();
    progressState.cardText = "";
    // Со сводкой меняется и заливка идущего сегмента — она считается по этапам
    // блока (WF22). Перерисовываем полосу сразу, а не ждём страховочного
    // перечёта через десять секунд.
    try { placeProgress(); } catch {}
    if (progressState.tipOpen) { try { progressTipShow(); } catch {} }
    return true;
  };

  const progressState = {
    info: null, reason: "полоса ещё не считалась", at: 0, runs: 0, timer: 0, pulse: 0,
    // Найденная рамка поля, нарисованные доли сегментов, место линии на экране
    // и наведение (только курсор).
    frame: null, shell: null, segments: [], box: null, hovering: false,
    // Подсказка: какой сегмент открыт кликом и открыта ли она вообще. Наведение
    // подсказку не показывает — только клик (план WF12, п. 3).
    tipSegment: null, tipOpen: false,
    // Карточка сегмента (WF22): что на ней написано сейчас, дышит ли значок
    // состояния и сама анимация значка.
    cardText: "", cardPulse: false, anim: null,
    // На чём сейчас сидит линия: "рамка" или запасное "строка инструментов".
    anchor: null,
  };

  // Полосу, подсказку и карточку сносим по id, как ручку и стили: упавшая на
  // середине установка оставляет их в окне, а реестра отмены у них уже нет.
  for (const id of [PROGRESS_ID, PROGRESS_TIP_ID, PROGRESS_CARD_ID]) {
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
    // Сама коробка не анимируется НИКОГДА: место и ширину ей задаёт геометрия
    // окна (resize, ручка, смена якоря), и переход тут означал бы, что полоса
    // ползёт за краем поля ввода с опозданием. Пишем это прямым объявлением, а
    // не молчанием: страница вправе объявить переход на всё подряд.
    transition: "none",
  })) progressBar.style.setProperty(name, value);
  (document.body ?? document.documentElement).appendChild(progressBar);
  track(() => progressBar.remove());

  // Коробка карточки. Ширина — во всё окно минус поля, текст переносится:
  // окна у Элвиса по 360 точек, и прежняя однострочная подсказка в них не
  // влезала (#5566, #5434). Прокрутки нет намеренно — узел прозрачен для мыши,
  // колесо до него не доходит; вместо неё потолок в 60 % высоты окна.
  const progressTip = document.createElement("div");
  progressTip.id = PROGRESS_TIP_ID;
  progressTip.setAttribute("aria-hidden", "true");
  for (const [name, value] of Object.entries({
    position: "fixed", display: "none", left: "0px", top: "0px",
    // box-sizing своим объявлением: ширину карточке считаем от окна, и хозяйская
    // раскладка страницы (content-box) вынесла бы её за край на поля и рамку.
    "box-sizing": "border-box",
    padding: "9px 11px 8px", "border-radius": "12px", "border-width": "1px", "border-style": "solid",
    font: "13px/1.4 -apple-system, system-ui, sans-serif", "white-space": "normal",
    "overflow-wrap": "anywhere", overflow: "hidden", "pointer-events": "none", "z-index": "2147483646",
  })) progressTip.style.setProperty(name, value);
  (document.body ?? document.documentElement).appendChild(progressTip);
  track(() => progressTip.remove());

  // Карточка сегмента (WF22, вариант 3A макета): «Workflow N · состояние», о чём,
  // время и шаги, четыре этапа со своим «кто», подвал со счётом проекта. Узлы
  // строим один раз и потом только переписываем текст — карточка открывается по
  // клику, и пересобирать её дерево на каждый показ незачем.
  const progressCard = document.createElement("div");
  progressCard.id = PROGRESS_CARD_ID;
  // Свой aria-hidden и никаких role/data-state: и раздел 16 (Escape), и
  // progressCovered ловят открытые накладки по role="dialog"/data-state="open" —
  // назовись карточка так, она сама себя и накрыла бы.
  progressCard.setAttribute("aria-hidden", "true");
  const cardNode = (parent, styles) => {
    const node = document.createElement("div");
    for (const [name, value] of Object.entries(styles)) node.style.setProperty(name, value);
    parent.appendChild(node);
    return node;
  };
  const progressCardHead = cardNode(progressCard, {
    display: "flex", "align-items": "center", "column-gap": "10px", "row-gap": "4px", "flex-wrap": "wrap",
  });
  const progressCardTitle = cardNode(progressCardHead, { "font-size": "15px", "font-weight": "700" });
  const progressCardWhere = cardNode(progressCardHead, { "font-size": "12px" });
  const progressCardPill = cardNode(progressCardHead, {
    "border-radius": "999px", padding: "1px 10px", "font-size": "12px", "font-weight": "650",
    "border-width": "1px", "border-style": "solid", "white-space": "nowrap",
  });
  // «О чём» — три строки с настоящим троеточием (line-clamp), а не обрезка по
  // буквам: длинная строка в узком окне иначе съедает всю карточку.
  const progressCardAbout = cardNode(progressCard, {
    "margin-top": "5px", display: "-webkit-box", "-webkit-line-clamp": "3",
    "-webkit-box-orient": "vertical", overflow: "hidden",
  });
  const progressCardMeta = cardNode(progressCard, { "margin-top": "4px", "font-size": "12px" });
  const progressCardStages = cardNode(progressCard, { "margin-top": "7px" });
  const progressCardRows = STATUS_STAGES.map(() => {
    const row = cardNode(progressCardStages, {
      display: "grid", "grid-template-columns": "20px 74px minmax(0, 1fr)", "column-gap": "4px",
      "align-items": "baseline", padding: "2px 6px", margin: "0 -6px", "border-radius": "6px",
    });
    return {
      row,
      icon: cardNode(row, { "font-size": "12px" }),
      label: cardNode(row, { "font-weight": "600" }),
      who: cardNode(row, { "font-size": "12px", "min-width": "0" }),
    };
  });
  const progressCardFoot = cardNode(progressCard, {
    "margin-top": "7px", "padding-top": "5px", "border-top-width": "1px", "border-top-style": "solid",
    "font-size": "12px", "white-space": "nowrap", overflow: "hidden", "text-overflow": "ellipsis",
  });
  progressTip.appendChild(progressCard);

  // Цвет полосы — тот же акцент окна, что у неоновой рамки, и функция на двоих
  // одна (accentColor, раздел 2а). Раньше она жила здесь, но рамка красится ещё
  // на восстановлении слоёв — то есть до этого раздела.
  const progressAccent = accentColor;
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

  // ---- сегмент ↔ блок сводки (WF22) ----------------------------------------
  // Соединяем по ЗНАЧКУ, а не по номеру: «WF N из M» считает воркфлоу ЭТОГО
  // чата, а status.md нумерует их по проекту (решение Элвиса 05.09,
  // docs/PROGRESS.md) — совпадение номеров было бы случайностью, и клик по
  // седьмому сегменту показывал чужой воркфлоу.
  const progressBlockAt = (info, number) => {
    if (!info) return null;
    const blocks = statusFeedProject(info.project)?.blocks ?? [];
    if (blocks.length === 0) return null;
    // Идущий блок — ПОСЛЕДНИЙ с 💭 в заголовке: в сводке рядом легко висит
    // недописанный старый.
    let runAt = -1;
    for (let index = 0; index < blocks.length; index += 1) if (blocks[index].state === "run") runAt = index;
    // Идущий сегмент — он же. ✋ и 🛑 в сводке значков не имеют: чат ждёт Элвиса
    // или упал на том же самом блоке, который в сводке помечен 💭.
    if (info.state !== "done" && number === info.wf) return runAt >= 0 ? blocks[runAt] : null;
    // Готовый сегмент k из D — k-й с ХВОСТА среди ✅: последние готовые блоки
    // проекта и есть воркфлоу этого чата. Свой номер карточка называет честно.
    const doneCount = info.state === "done" ? info.of : info.wf - 1;
    if (number <= doneCount) {
      const done = blocks.filter(block => block.state === "done");
      return done[done.length - 1 - (doneCount - number)] ?? null;
    }
    // Будущий — ⬜ с головы, но только те, что стоят ПОСЛЕ идущего.
    const todo = blocks.filter((block, index) => block.state === "todo" && index > runAt);
    return todo[number - info.wf - 1] ?? null;
  };
  // Четыре этапа блока и который из них идёт. Явная пометка 💭 в строке роли
  // сильнее порядка записи; её нет — идущим считаем ПОСЛЕДНИЙ записанный этап
  // (по шаблону AGENTS.md роли дописывают по мере прохождения).
  const progressStages = (block) => {
    const rows = STATUS_STAGES.map(stage => ({
      key: stage.key, label: stage.label,
      role: block?.roles.find(role => stage.re.test(role.role)) ?? null,
    }));
    let now = rows.findIndex(row => row.role?.running);
    if (now < 0) for (let index = 0; index < rows.length; index += 1) if (rows[index].role) now = index;
    return { rows, now };
  };
  // Заливка идущего сегмента (буква 1A): не проценты — их в строке состояния
  // больше нет (AGENTS.md 07.09), — а ПРОЙДЕННЫЕ ЭТАПЫ из четырёх. Каждый этап
  // четверть, идущий даёт половину своей четверти. Ролей в блоке нет — считаем
  // по «шаги N из M»; нет и их — минимум, чтобы сегмент вообще был виден (#5543).
  const PROGRESS_MIN_FILL = 8;
  // Потолок ширины карточки: в широком окне она остаётся такой же компактной, как в
  // узком (слово Элвиса 07.09 22:50).
  const PROGRESS_CARD_MAX_WIDTH = 400;
  const progressBlockFill = (block) => {
    if (!block) return null;
    if (block.state === "done") return 100;
    const { rows, now } = progressStages(block);
    // Роли записаны все разом и без 💭, а «шаги 0 из M» — этапы ещё не пройдены:
    // без этого сводка WF22 давала 87,5 % на нулевом шаге (проверка WF22, риск 1).
    const marked = rows.some(row => row.role?.running);
    const unstarted = !marked && block.steps != null && block.steps.done === 0;
    if (now >= 0 && !unstarted) return (now + 0.5) * (100 / rows.length);
    if (block.steps && block.steps.total > 0) return block.steps.done / block.steps.total * 100;
    return null;
  };
  const progressFill = (info) => {
    if (!info) return 0;
    if (info.state === "done") return 100;
    // Процент из строки состояния сильнее сводки: его пишут чаты, которые ещё не
    // перечитали правила, и врать про них незачем.
    const share = info.pct != null ? info.pct : progressBlockFill(progressBlockAt(info, info.wf));
    return Math.max(PROGRESS_MIN_FILL, Math.min(100, share ?? 0));
  };

  // Сегменты марафона: готовые полные, текущий на свою заливку, будущие пустые.
  // ✅ закрашивает все — «готово» сильнее всего, что написано рядом.
  const progressShares = (info, width) => {
    const count = Math.max(1, Math.min(PROGRESS_SEG_MAX, Math.round(info.of) || 1));
    // Совсем узкая полоса: сегменты по паре точек с зазором в три уже не
    // читаются — тогда честнее одна сплошная доля всего марафона.
    if (count > 1 && (width - (count - 1) * PROGRESS_SEG_GAP) / count < PROGRESS_SEG_MIN) {
      const merged = info.state === "done" ? 100
        : ((info.wf - 1) + progressFill(info) / 100) / Math.max(1, info.of) * 100;
      return [Math.max(PROGRESS_MIN_FILL, merged)];
    }
    const fill = progressFill(info);
    const shares = [];
    for (let number = 1; number <= count; number += 1) {
      if (info.state === "done" || number < info.wf) shares.push(100);
      else if (number === info.wf) shares.push(fill);
      else shares.push(0);
    }
    return shares;
  };

  // Узлы сегментов: у каждого свой контур (track) и своя заливка (fill). Контур
  // отдельным узлом, а не прозрачностью самого сегмента, — иначе вместе с ним
  // выцвела бы и заливка текущего воркфлоу.
  //
  // Доля сегмента — flex-basis в процентах, а не flex:1 1 0. Довод в том, какие
  // смены обязаны ехать плавно, а какие мгновенно: процент не меняется от того,
  // что окно стало шире (переход не запускается — полоса перестраивается в тот
  // же кадр), зато при смене числа сегментов проценты другие, и браузер сам
  // проводит их переходом. Зазоры при этом съедает flex-shrink: сумма долей
  // всегда ровно 100 %, лишнее ужимается поровну.
  const PROGRESS_CELL_TRANS = `flex-basis ${PROGRESS_MOVE_MS}ms ease, ` +
    `margin-left ${PROGRESS_MOVE_MS}ms ease, opacity ${PROGRESS_MOVE_MS}ms ease`;
  const PROGRESS_FILL_TRANS =
    `width ${PROGRESS_MOVE_MS}ms linear, background ${PROGRESS_MOVE_MS}ms ease, box-shadow ${PROGRESS_MOVE_MS}ms ease`;
  const PROGRESS_TRACK_TRANS = `box-shadow ${PROGRESS_MOVE_MS}ms ease`;

  // ---- пульс идущего этапа (WF22, буква 1A) --------------------------------
  // Дышит ОТДЕЛЬНЫЙ слой свечения, а не тень заливки: анимировать box-shadow
  // значит перерисовывать тень каждый кадр, а прозрачность composited-слоя
  // ничего не стоит. Ключевые кадры — Web Animations (element.animate): своей
  // таблицы стилей у полосы нет и заводить её нельзя (CSP страницы, раздел 4),
  // а @keyframes без таблицы не бывает.
  const PROGRESS_PULSE_MS = 2400;
  const PROGRESS_GLOW_FRAMES = [{ opacity: "0.35" }, { opacity: "0.8" }, { opacity: "0.35" }];
  const PROGRESS_PILL_FRAMES = [{ opacity: "0.6" }, { opacity: "1" }, { opacity: "0.6" }];
  // Скрытое окно и «поменьше движения» в системе гасят пульс: Electron всё равно
  // придушит таймеры перекрытого окна, а анимация останется висеть.
  const progressMotionOk = () => {
    if (document.hidden) return false;
    try { return !matchMedia("(prefers-reduced-motion: reduce)").matches; } catch { return true; }
  };
  // slot — любой объект с полем anim (сегмент или карточка): вторую анимацию на
  // тот же узел не заводим, а снимаем ровно свою.
  const progressPulse = (slot, node, on, frames, rest) => {
    if (!node) return;
    if (!on || !progressMotionOk()) {
      if (slot.anim) { try { slot.anim.cancel(); } catch {} slot.anim = null; }
      node.style.setProperty("opacity", rest);
      return;
    }
    if (slot.anim) return;
    try { slot.anim = node.animate(frames, { duration: PROGRESS_PULSE_MS, iterations: Infinity }); }
    catch { slot.anim = null; node.style.setProperty("opacity", rest); }
  };
  // Живые сегменты слева направо и те, что сейчас гаснут (они ещё в разметке).
  const progressCells = [];
  const progressLeaving = [];
  // Пересобрать пульсы по тому, что уже решил последний проход: зовётся на
  // visibilitychange, где меняется не полоса, а только право двигаться.
  const progressPulseSync = () => {
    for (const item of progressCells) progressPulse(item, item.glow, item.pulse, PROGRESS_GLOW_FRAMES, "0");
    for (const item of progressLeaving) progressPulse(item, item.glow, false, PROGRESS_GLOW_FRAMES, "0");
    progressPulse(progressState, progressCardPill, progressState.cardPulse, PROGRESS_PILL_FRAMES, "1");
  };
  on(document, "visibilitychange", () => { try { progressPulseSync(); } catch {} });
  // Снятие: анимация переживает и удаление узла из разметки, и dispose().
  track(() => {
    for (const item of [...progressCells, ...progressLeaving]) {
      if (item.anim) { try { item.anim.cancel(); } catch {} item.anim = null; }
    }
    if (progressState.anim) { try { progressState.anim.cancel(); } catch {} progressState.anim = null; }
  });

  const progressDrop = (item) => {
    if (item.timer) { clearTimeout(item.timer); item.timer = 0; }
    if (item.anim) { try { item.anim.cancel(); } catch {} item.anim = null; }
    const index = progressLeaving.indexOf(item);
    if (index >= 0) progressLeaving.splice(index, 1);
    item.cell.remove();
  };
  // Лишний сегмент не выдёргиваем из разметки на месте: гасим прозрачностью и
  // убираем, когда затухание кончилось. Полоса при этом спрятана — гасить
  // нечего, узел уходит сразу.
  //
  // Заодно гаснущий отдаёт своё место: доля едет в ноль, а отрицательное поле
  // слева гасит его зазор (гаснущие всегда в хвосте, зазор перед ними есть
  // всегда). Иначе оставшиеся сегменты сидели бы ужатыми все затухание и
  // прыгнули бы вширь в тот миг, когда узел исчез из разметки.
  const progressLeave = (item, instant) => {
    if (instant) { progressDrop(item); return; }
    // Гаснущий сегмент больше не идущий этап — пульс снимаем сразу, не дожидаясь
    // конца затухания.
    progressPulse(item, item.glow, false, PROGRESS_GLOW_FRAMES, "0");
    item.pulse = false;
    progressLeaving.push(item);
    for (const [name, value] of Object.entries({
      opacity: "0", "flex-basis": "0%", "margin-left": `-${PROGRESS_SEG_GAP}px`,
    })) item.cell.style.setProperty(name, value);
    item.timer = setTimeout(() => { item.timer = 0; progressDrop(item); }, PROGRESS_DROP_MS);
  };
  track(() => { for (const item of progressLeaving.splice(0)) if (item.timer) clearTimeout(item.timer); });

  const progressCell = () => {
    const cell = document.createElement("div");
    for (const [name, value] of Object.entries({
      position: "relative", "flex-grow": "0", "flex-shrink": "1", "flex-basis": "100%",
      "min-width": "0", "margin-left": "0px", height: "100%", "border-radius": "999px",
      // Рождается прозрачным и без переходов: доли и цвета ему впишет тот же
      // проход progressApply, и вписать их надо мгновенно — иначе новый сегмент
      // поехал бы от нуля, то есть ровно то, от чего уходим.
      opacity: "0", transition: "none",
    })) cell.style.setProperty(name, value);
    const track = document.createElement("div");
    for (const [name, value] of Object.entries({
      position: "absolute", left: "0", top: "0", right: "0", bottom: "0",
      "border-radius": "999px", opacity: "0.25", transition: "none",
    })) track.style.setProperty(name, value);
    const fill = document.createElement("div");
    for (const [name, value] of Object.entries({
      position: "absolute", left: "0", top: "0", bottom: "0", width: "0%",
      "border-radius": "999px", transition: "none",
    })) fill.style.setProperty(name, value);
    // Слой свечения поверх заливки: он и дышит (WF22). Отдельным узлом, потому
    // что заливке нельзя менять прозрачность — вместе с ней выцвел бы и цвет
    // сегмента, а тень у неё своя, постоянная.
    const glow = document.createElement("div");
    for (const [name, value] of Object.entries({
      position: "absolute", left: "0", top: "0", bottom: "0", width: "0%",
      "border-radius": "999px", opacity: "0", "pointer-events": "none", transition: "none",
    })) glow.style.setProperty(name, value);
    cell.appendChild(track);
    cell.appendChild(fill);
    cell.appendChild(glow);
    return { cell, track, fill, glow, anim: null, pulse: false, timer: 0, born: true };
  };

  // Пул: число сегментов гуляет при каждой прокрутке ленты, и пересоздавать их
  // нельзя — новый узел не помнит, на сколько был залит прежний. Меняется
  // только хвост.
  const progressBuild = (count, instant) => {
    if (progressCells.length === count) return;
    if (progressCells.length > count) {
      for (const item of progressCells.splice(count)) progressLeave(item, instant);
      return;
    }
    while (progressCells.length < count) {
      // Ещё не убранный сегмент возвращаем на место, а не рожаем новый:
      // гаснущие стоят в разметке ПОСЛЕ живых, и новый узел встал бы за ними.
      const back = progressLeaving.shift();
      if (back) {
        if (back.timer) { clearTimeout(back.timer); back.timer = 0; }
        // Долю ему впишет тот же проход, а прозрачность и поле возвращаем здесь.
        back.cell.style.setProperty("opacity", "1");
        back.cell.style.setProperty("margin-left", "0px");
        progressCells.push(back);
        continue;
      }
      const item = progressCell();
      progressBar.appendChild(item.cell);
      progressCells.push(item);
    }
  };

  const progressTipHide = () => {
    if (progressState.cardPulse) {
      progressState.cardPulse = false;
      progressPulse(progressState, progressCardPill, false, PROGRESS_PILL_FRAMES, "1");
    }
    if (progressTip.style.display !== "none") progressTip.style.setProperty("display", "none");
  };
  // Сегмент под точкой x. Считаем арифметикой по коробке полосы, а не по
  // прямоугольникам узлов: доли едут переходом (WF11), и на середине движения
  // геометрия узлов врёт. Доли равны, зазор один и тот же, поэтому шаг —
  // (ширина + зазор) / число сегментов.
  const progressSegmentAt = (x) => {
    const box = progressState.box;
    const count = progressState.segments.length;
    if (!box || count < 1) return null;
    const width = box.right - box.left;
    if (width <= 0) return null;
    const step = (width + PROGRESS_SEG_GAP) / count;
    return Math.min(count - 1, Math.max(0, Math.floor((x - box.left) / step)));
  };
  // Состояние ОДНОГО воркфлоу словом: до текущего — готов, после — запланирован,
  // сам текущий — по значку строки состояния. ✅ у всего марафона закрывает всё.
  const PROGRESS_WORDS = { done: "готов", run: "идёт", wait: "ждёт", fail: "упал" };
  const progressWord = (info, number) => {
    if (info.state === "done" || number < info.wf) return "готов";
    if (number > info.wf) return "запланирован";
    return PROGRESS_WORDS[info.state] ?? "идёт";
  };
  // Номер воркфлоу по сегменту: обычно это его порядок, а в слитой полосе
  // (узкое окно, сегмент один на весь марафон) — текущий воркфлоу.
  const progressNumberAt = (index) => {
    const info = progressState.info;
    if (!info) return null;
    const count = progressState.segments.length || 1;
    if (count === 1 && info.of > 1) return info.wf;
    return Math.min(count, Math.max(1, index + 1));
  };
  // Значок состояния воркфлоу и цвет карточки под него. Цвета взяты из макета
  // (docs/mockup-wf22-cards.html): тройками, потому что кромка, плашка и заливка
  // строки берут один и тот же тон с разной прозрачностью.
  const PROGRESS_CARD_ICONS = {
    "готов": "✅", "идёт": "💭", "ждёт": "✋", "упал": "🛑", "запланирован": "⬜",
  };
  const PROGRESS_CARD_TONES = {
    "готов": "ok", "идёт": "run", "ждёт": "wait", "упал": "fail", "запланирован": "todo",
  };
  const PROGRESS_CARD_SKIN = {
    dark: {
      back: "#33373f", line: "rgba(255,255,255,.16)", text: "#eef0f4", dim: "#aab0bc",
      shadow: "0 18px 44px rgba(0,0,0,.62),0 2px 6px rgba(0,0,0,.45)",
      run: "126,160,255", ok: "77,187,125", wait: "245,197,66", fail: "238,106,95", todo: "150,155,165",
    },
    light: {
      back: "#ffffff", line: "rgba(20,24,32,.16)", text: "#171a20", dim: "#666c7a",
      shadow: "0 18px 44px rgba(20,24,32,.24),0 2px 6px rgba(20,24,32,.12)",
      run: "47,98,216", ok: "31,154,90", wait: "196,138,0", fail: "204,58,48", todo: "130,136,150",
    },
  };
  // Кто делал этап: «2 агента · Opus max». Fable max — красный кружок и жирным
  // (слово Элвиса 04.09 21:10): по нему видно, где потрачена дорогая модель.
  const progressWho = (role) => {
    if (!role) return { text: "—", fable: false };
    const model = [role.model, role.effort].filter(Boolean).join(" ");
    const fable = /fable/i.test(role.model) && role.effort.toLowerCase() === "max";
    const text = [role.agents, fable ? `🔴 ${model}` : model].filter(Boolean).join(" · ");
    return { text: text || "—", fable };
  };
  const progressTipShow = () => {
    const info = progressState.info;
    const segment = progressState.tipSegment;
    if (!progressState.tipOpen || segment == null || !info ||
        !progressState.box || progressBar.style.display === "none") { progressTipHide(); return; }
    const count = progressState.segments.length || 1;
    const index = Math.min(count - 1, Math.max(0, segment));
    const number = progressNumberAt(index);
    const word = progressWord(info, number);
    // Блок сводки ищем по значку, а не по номеру (progressBlockAt): номера
    // марафона и проекта — разные счёты. Нашёлся — карточка называет СВОЙ номер
    // из сводки, и подмена не врёт.
    const feed = statusFeedProject(info.project);
    const block = progressBlockAt(info, number);
    const stages = progressStages(block);
    const skin = PROGRESS_CARD_SKIN[progressDark() ? "dark" : "light"];
    const tone = skin[PROGRESS_CARD_TONES[word] ?? "run"];
    const title = block ? `Workflow ${block.number ?? number}` : `Воркфлоу ${number}`;
    const where = block ? "в проекте" : `из ${info.of} · этот чат`;
    const about = block ? (block.about || "—") : "сводки нет";
    const meta = block
      ? [block.time, block.steps ? `шаги ${block.steps.done} из ${block.steps.total}` : ""].filter(Boolean).join(" · ")
      : "";
    const foot = [info.project, ...(feed?.head ?? [])].filter(Boolean).join(" · ");
    const rows = stages.rows.map((row, order) => {
      const state = block?.state === "done"
        ? (row.role ? "done" : "todo")
        : (block?.state === "run" && stages.now >= 0
          ? (order < stages.now ? "done" : (order === stages.now ? "now" : "todo"))
          : "todo");
      return { ...row, state, who: progressWho(row.role) };
    });
    // Пишем только когда содержимое поменялось: карточка живёт открытой, а
    // команда status приходит раз в две секунды.
    // Ключ смены — он же читаемый слепок карточки для гейта (status().progress.tip.card).
    const key = [title, where, word, about, meta,
      ...rows.map(row => `${row.label} ${row.state} ${row.who.text}`), foot].filter(Boolean).join(" · ");
    if (progressState.cardText !== key) {
      progressState.cardText = key;
      // Только textContent: сводка приходит снаружи, и разметки в ней быть не должно.
      progressCardTitle.textContent = title;
      progressCardWhere.textContent = where;
      // Слово Элвиса 07.09 22:50: бейдж называет этап — «идёт кодинг», «ждёт тебя».
      const pill = word === "идёт" && stages.now >= 0 ? `идёт ${stages.rows[stages.now].label}`
        : (word === "ждёт" ? "ждёт тебя" : word);
      progressCardPill.textContent = `${PROGRESS_CARD_ICONS[word] ?? "💭"} ${pill}`;
      progressCardAbout.textContent = about;
      progressCardMeta.textContent = meta;
      progressCardMeta.hidden = meta === "";
      progressCardFoot.textContent = foot;
      progressCardFoot.hidden = foot === "";
      progressCardStages.hidden = !block;
      for (let order = 0; order < progressCardRows.length; order += 1) {
        const node = progressCardRows[order];
        const row = rows[order];
        node.icon.textContent = row.state === "done" ? "✅" : (row.state === "now" ? "💭" : "⬜");
        node.label.textContent = row.label;
        node.who.textContent = row.who.text;
        node.who.style.setProperty("font-weight", row.who.fable ? "700" : "400");
      }
    }
    // Цвета переписываем каждый показ: тон зависит от состояния сегмента, а тема
    // окна меняется командой в любой момент.
    for (const [name, value] of Object.entries({
      background: skin.back, color: skin.text, "border-color": skin.line, "box-shadow": skin.shadow,
      // Ширина — всё окно минус поля; потолок высоты 60 % окна, лишнее уходит
      // под обрез: прокрутки у прозрачного для мыши узла всё равно нет.
      width: `${Math.max(120, Math.min(PROGRESS_CARD_MAX_WIDTH, innerWidth - 12))}px`, "max-height": `${Math.round(innerHeight * 0.6)}px`,
    })) progressTip.style.setProperty(name, value);
    for (const [name, value] of Object.entries(PROGRESS_CARD_VARIANT === "3A"
      // 3A — «таблица с цветной кромкой»: состояние читается кромкой слева.
      ? { "border-left": `4px solid rgb(${tone})`, "padding-left": "12px" }
      : { "border-left": "0", "padding-left": "0" })) progressCard.style.setProperty(name, value);
    progressCardWhere.style.setProperty("color", skin.dim);
    progressCardMeta.style.setProperty("color", skin.dim);
    progressCardFoot.style.setProperty("color", skin.dim);
    progressCardFoot.style.setProperty("border-top-color", skin.line);
    for (const [name, value] of Object.entries({
      color: `rgb(${tone})`, background: `rgba(${tone},.14)`, "border-color": `rgba(${tone},.4)`,
    })) progressCardPill.style.setProperty(name, value);
    for (let order = 0; order < progressCardRows.length; order += 1) {
      const node = progressCardRows[order];
      const row = rows[order];
      node.row.style.setProperty("background", row.state === "now" ? `rgba(${tone},.14)` : "transparent");
      node.row.style.setProperty("opacity", row.state === "todo" ? "0.55" : "1");
      node.label.style.setProperty("color", row.state === "now" ? `rgb(${tone})` : skin.text);
      node.who.style.setProperty("color", row.state === "now" || row.who.fable ? skin.text : skin.dim);
    }
    progressTip.style.setProperty("display", "block");
    // Идёт и готово — дышат, как сегмент полосы (буква 1A). Ждёт и упал стоят.
    progressState.cardPulse = word === "идёт" || word === "готов";
    progressPulse(progressState, progressCardPill, progressState.cardPulse, PROGRESS_PILL_FRAMES, "1");
    // Место считаем уже по показанной карточке: до показа высоты у неё нет.
    // Карточка шире сегмента, поэтому стоит она у левого края окна, а не над
    // своим сегментом — иначе в узком окне её всё равно прижимало бы к краю.
    const rect = progressTip.getBoundingClientRect();
    const height = rect.height || 0;
    const top = Math.max(6, progressState.box.top - height - 8);
    // В широком окне карточка не растёт (потолок PROGRESS_CARD_MAX_WIDTH) и стоит у
    // левого края полосы, а не окна (слово Элвиса 22:50).
    const cardWidth = rect.width || parseFloat(progressTip.style.getPropertyValue("width")) || 0;
    const left = Math.max(6, Math.min(progressState.box.left, innerWidth - cardWidth - 6));
    progressTip.style.setProperty("left", `${Math.round(left)}px`);
    progressTip.style.setProperty("top", `${Math.round(top)}px`);
  };
  const progressTipClose = () => {
    progressState.tipOpen = false;
    progressState.tipSegment = null;
    progressTipHide();
  };
  // Клик по полосе: по тому же сегменту — закрыть, по другому — переключить.
  // Пустой контур (строки состояния нет) карточке рассказать нечего.
  const progressTipToggle = (segment) => {
    if (segment == null || !progressState.info) { progressTipClose(); return; }
    if (progressState.tipOpen && progressState.tipSegment === segment) { progressTipClose(); return; }
    progressState.tipSegment = segment;
    progressState.tipOpen = true;
    progressTipShow();
  };
  // Попадание в открытую карточку. Своя проверка нужна потому, что узел
  // прозрачен для мыши (pointer-events:none, чтобы не съедать клики по полю
  // ввода под ним): без неё клик по самой карточке гасил бы её же.
  const progressCardHit = (x, y) => {
    if (!progressState.tipOpen || progressTip.style.display === "none") return false;
    try {
      const rect = progressTip.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) return false;
      return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
    } catch { return false; }
  };

  const progressHide = () => {
    progressState.box = null;
    progressState.anchor = null;
    // Полоса ушла с экрана (меню накрыло линию, окно уехало) — дышать нечему.
    for (const item of progressCells) {
      item.pulse = false;
      progressPulse(item, item.glow, false, PROGRESS_GLOW_FRAMES, "0");
    }
    // Полосы нет — не о чем и подсказке: держать её открытой над пустым местом
    // (меню накрыло линию, окно уехало) не за что.
    progressTipClose();
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
    if (rect.width < PROGRESS_MIN_WIDTH || rect.bottom <= 0 || rect.top >= innerHeight) {
      progressState.reason = "рамка поля вне окна";
      progressHide();
      return;
    }
    // Отступ от краёв — по скруглению рамки (как у ручки), иначе сегменты вылезают
    // за скругления (слово Элвиса 04.09 04:10).
    const inset = onFrame ? handleInset(progressState.frame ?? state.shell) : 0;
    const left = Math.round(rect.left + inset);
    const width = Math.round(rect.width - inset * 2);
    // Полоса сидит верхом на кромке: половина линии выше низа рамки, половина
    // ниже. На запасном якоре кромка — верх строки инструментов.
    const top = Math.round(onFrame ? rect.bottom : rect.top) - 1;
    if (progressCovered(top, left, left + width)) {
      progressState.reason = "полосу закрыло меню";
      progressHide();
      return;
    }
    // Строки состояния нет — рисуем ОДИН пустой контур, а не прячем полосу
    // (PROGRESS.md, п. 1): в новом чате должно быть видно, что полоса на месте и
    // ждёт первого ответа, а не «сломалась». Причину при этом называем честно —
    // её читает гейт через probe.
    progressState.reason = info ? null : "нет строки состояния — пустой контур";
    progressState.anchor = onFrame ? "рамка" : "строка инструментов";
    const shares = info ? progressShares(info, width) : [0];
    progressState.segments = shares;
    // Полоса сейчас спрятана — значит это её появление: ни первый показ при
    // открытии окна, ни возврат из-под закрывшегося меню анимировать нечего,
    // всё пишется сразу набело.
    const instant = progressBar.style.display !== "flex";
    progressBuild(shares.length, instant);
    const accent = progressAccent();
    // Вся полоса «готово» — зелёная (буква Элвиса 1A: готово это сигнал
    // продолжать, а не «всё, конец»). У идущего марафона зелени нет: цвет по
    // состоянию берёт только текущий сегмент.
    const base = info?.state === "done" ? PROGRESS_PAINT.done : accent;
    const hot = (info && PROGRESS_PAINT[info.state]) ?? accent;
    // Слитая в одну полоса — это и есть текущий воркфлоу целиком.
    const merged = shares.length === 1 && (info?.of ?? 1) > 1;
    const current = info ? (merged ? 0 : Math.min(shares.length - 1, Math.max(0, info.wf - 1))) : -1;
    // Доли считаем от сотни: сумма ровно 100 %, зазоры съедает flex-shrink.
    const basis = `${Math.round(10000 / shares.length) / 100}%`;
    // Узлы, которым этот проход пишется без переходов: свежерождённые и все
    // подряд на появлении полосы. Переходы им вернём одним махом ниже.
    const quiet = [];
    for (let index = 0; index < shares.length; index += 1) {
      const item = progressCells[index];
      if (!item) continue;
      if (instant || item.born) {
        for (const node of [item.cell, item.track, item.fill]) node.style.setProperty("transition", "none");
        quiet.push(item);
      }
      const share = shares[index];
      const paint = index === current ? hot : base;
      item.cell.style.setProperty("flex-basis", basis);
      if (instant) item.cell.style.setProperty("opacity", "1");
      item.fill.style.setProperty("width", `${share}%`);
      item.fill.style.setProperty("background", paint);
      // Свечение двумя тенями — приём донора: широкий мягкий ореол и второй
      // проход по той же тени, отчего свет плотнее у самой линии. Пустому
      // сегменту светиться нечем.
      item.fill.style.setProperty("box-shadow", share > 0 ? `0 0 18px ${paint},0 0 6px ${paint}` : "none");
      // Дышит только идущий этап и вся зелёная полоса «готово»: ждёт (жёлтый) и
      // упал (красный) стоят на месте — движение там значило бы «работа идёт».
      item.glow.style.setProperty("width", `${share}%`);
      item.glow.style.setProperty("box-shadow", share > 0 ? `0 0 18px ${paint},0 0 10px ${paint}` : "none");
      item.pulse = share > 0 && Boolean(info) &&
        (info.state === "done" || (index === current && info.state === "run"));
      progressPulse(item, item.glow, item.pulse, PROGRESS_GLOW_FRAMES, "0");
      // Контур в одну точку — «сюда марафон ещё не дошёл».
      item.track.style.setProperty("box-shadow", `inset 0 0 0 1px ${accent}`);
    }
    if (quiet.length > 0) {
      // Принудительная раскладка одна на весь проход: без неё браузер сведёт обе
      // записи стиля в один пересчёт, увидит только «переходы включены» и всё-таки
      // проиграет движение от старых значений к новым.
      try { progressBar.getBoundingClientRect(); } catch {}
      for (const item of quiet) {
        item.born = false;
        item.cell.style.setProperty("transition", PROGRESS_CELL_TRANS);
        item.track.style.setProperty("transition", PROGRESS_TRACK_TRANS);
        item.fill.style.setProperty("transition", PROGRESS_FILL_TRANS);
        // Хвост проявляется: узел уже нужной ширины и с готовой заливкой, ему
        // осталось только всплыть. На появлении полосы он всплыл выше, разом.
        item.cell.style.setProperty("opacity", "1");
      }
    }
    progressBar.style.setProperty("left", `${left}px`);
    progressBar.style.setProperty("top", `${top}px`);
    progressBar.style.setProperty("width", `${width}px`);
    const title = info
      ? `Воркфлоу ${info.wf} из ${info.of}` + (info.pct == null ? "" : ` · ${info.pct} %`)
      : "Воркфлоу ещё не начаты";
    // Указателя полоса не ловит, и родной title на ней не покажется — он остаётся
    // для разбора окна (probe на гейте). Человеку показывается свой div выше.
    if (progressBar.title !== title) progressBar.title = title;
    progressBar.style.setProperty("display", "flex");
    progressState.box = { left, right: left + width, top };
    if (progressState.tipOpen) progressTipShow();
  };
  // Раскладку ручки полоса не имеет права уронить: её зовут из чужого кода.
  const placeProgress = () => { try { progressApply(); } catch {} };

  // Попадание по линии: ±4 точки по вертикали и своя ширина по горизонтали.
  const progressHit = (x, y) => {
    const box = progressState.box;
    // Пустой контур (строки состояния нет) — только украшение: мышь не ловит,
    // клик под ним доходит до страницы (проверка WF22).
    if (!progressState.info) return false;
    if (!box || progressBar.style.display === "none") return false;
    if (y < box.top - PROGRESS_HIT_SLACK || y > box.top + PROGRESS_BAR_HEIGHT + PROGRESS_HIT_SLACK) return false;
    if (x < box.left || x > box.right) return false;
    // Ручка сильнее полосы. У свёрнутого поля она стоит ровно над строкой
    // модели (раздел 9, placeCollapsedHandle) — там же, где линия прогресса, —
    // и кликом по ней поле возвращают. Не уступи мы здесь, вернуть поле стало бы
    // нечем: наш обработчик глушит клик на захвате, до самой ручки.
    try {
      if (handle.style.display !== "none") {
        const rect = handle.getBoundingClientRect();
        if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) return false;
      }
    } catch {}
    return true;
  };
  // Курсор — единственное, что даёт наведение (план WF12, п. 3): подсказка
  // открывается кликом. Полоса ничего не ловит мышью (pointer-events:none), и
  // своего курсора у неё быть не может, поэтому «руку» ставим корню документа и
  // снимаем ровно её же — чужой курсор (перетаскивание ручки) не трогаем.
  const progressCursor = (hand) => {
    try {
      const root = document.documentElement;
      if (hand) { if (root.style.cursor !== "pointer") root.style.cursor = "pointer"; }
      else if (root.style.cursor === "pointer") root.style.cursor = "";
    } catch {}
  };
  track(() => progressCursor(false));
  const onProgressMove = (event) => {
    // Над карточкой «руку» не ставим: кликать по ней нечего, а линия под ней
    // может оказаться на том же месте у самого края окна.
    const inside = !state.dragging && !progressCardHit(event.clientX, event.clientY) &&
      progressHit(event.clientX, event.clientY);
    if (inside === progressState.hovering) return;
    progressState.hovering = inside;
    progressCursor(inside);
  };
  on(document, "mousemove", onProgressMove, { passive: true, capture: true });
  // Клик по полосе. Ловим на ЗАХВАТЕ и только внутри линии: там событие наше
  // целиком (preventDefault + stopPropagation), и полю ввода под ней оно не
  // достаётся. Мимо линии — не трогаем событие вовсе, только закрываем подсказку.
  const onProgressDown = (event) => {
    // Попадание в карточку проверяем ДО закрытия: она прозрачна для мыши, и без
    // этой проверки любой клик по ней самой её же и гасил бы. Событие при этом
    // не трогаем — под карточкой живёт лента, и выделять в ней текст Элвису
    // никто не мешает.
    if (progressCardHit(event.clientX, event.clientY)) return;
    if (!progressHit(event.clientX, event.clientY)) { progressTipClose(); return; }
    event.preventDefault();
    event.stopPropagation();
    try { progressTipToggle(progressSegmentAt(event.clientX)); } catch {}
  };
  on(document, "pointerdown", onProgressDown, { capture: true });
  // Escape закрывает подсказку. Слушатель свой, а не ветка в разделе 16: там
  // Escape ГЛОТАЕТСЯ насовсем, и подсказка обязана закрыться раньше. Этот
  // слушатель встаёт первым (раздел 2б идёт по файлу выше) и потому успевает.
  const onProgressKey = (event) => {
    if (event.key === "Escape" && progressState.tipOpen) progressTipClose();
  };
  on(window, "keydown", onProgressKey, { capture: true });
  // Указатель ушёл из окна — движений больше не будет, и «рука» осталась бы
  // висеть. То же на потере фокуса окном. Подсказку это не закрывает: её
  // открыли кликом, и родное меню приложения как раз отнимает фокус.
  const onProgressLeave = () => {
    if (!progressState.hovering) return;
    progressState.hovering = false;
    progressCursor(false);
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
      // Плюс строки виртуальной ленты Claude Code: у ответа с шагами инструментов
      // aria-label «Message N» достаётся строке шагов, а итоговый текст (со строкой
      // состояния) лежит отдельной строкой без приметы (замер 04.09 21:00).
      const all = [...document.querySelectorAll(`${ANSWER_SELECTOR},[data-testid="transcript-row"]`)]
        .filter(answerUsable);
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

  // ---- 2в. Живые цвета ----------------------------------------------------
  // Окна плавно едут по цветовому кругу. Приложение шлёт ОДНУ команду
  // live-colors на все окна разом, дальше каждое окно считает свой цвет само.
  // Крутить цвет командами из Swift нельзя: канал (command.json) держит зазор
  // 0,6 с между записями, а лоадер раз в 500 мс берёт из файла только ПОСЛЕДНЮЮ
  // запись — на «плавненько» этого не хватит, зато очередь меню и сводки такой
  // поток задушил бы.
  //
  // Цвет считается ОТ СТЕННЫХ ЧАСОВ, а не накоплением тиков. Отсюда два
  // свойства даром: epoch и period у всех окон одни, поэтому в режиме «все одним
  // цветом» окна сходятся сами, без единого байта между ними; а придушенное
  // фоновое окно (Electron режет таймеры перекрытых окон до 1 Гц) после
  // пробуждения оказывается на правильном цвете, а не отстаёт на всё время сна.
  //
  // Палитры страница не считает: их присылает приложение кольцом опорных точек
  // из того же генератора, что и «Раскрасить по кругу» (AutoPaint с его
  // подтяжкой контраста), а страница между соседними точками смешивает цвета
  // покомпонентно. Вторая копия формул контраста в JS через месяц разъехалась бы
  // со Swift.
  //
  // Хранилища тем живые цвета не касаются вовсе: идут через applyTheme(…, "live")
  // мимо writeLayers. Выключили — restoreTheme поднял тему чата/окна по обычному
  // приоритету, как будто ничего не было. Своё состояние (кольцо, скорость,
  // режим) лежит отдельным ключом в localStorage: он у окон Claude общий, и
  // окно, открытое во время крутёжа, подхватывает цвет само, без команды —
  // в том числе когда приложение уже не запущено.
  const LIVE_KEY = "myclaude-live-v1";
  const LIVE_PHASE_KEY = "myclaude-live-phase-v1";
  // Круг за минуту — предел снизу: при 4 Гц это ровно 1,5° за шаг, быстрее уже
  // не «цвет едет», а мигание. Медленнее часа — цвет стоит на месте.
  const LIVE_PERIOD_MIN = 60;
  const LIVE_PERIOD_MAX = 3600;
  const LIVE_PERIOD_DEFAULT = 300;
  // Шаг по кругу и потолок частоты. Тик считается ОТ СКОРОСТИ: на самом быстром
  // круге это 250 мс (4 Гц), на медленном — секунда. Чаще незачем — каждый тик
  // это ≈200 строк CSS и полный пересчёт стилей окна; реже — видны ступени.
  const LIVE_STEP_DEG = 1.5;
  const LIVE_TICK_MIN_MS = 500; // гейт WF18: при 250 мс (круг за минуту) рендереры +100–160 % CPU, при 500 — вдвое легче; шаг ≤ 3°
  const LIVE_TICK_MAX_MS = 1000;
  // Полоса прогресса берёт акцент один раз при отрисовке и за темой сама не
  // едет (её пульс — 10 с), то есть рядом с уехавшим окном держала бы старый
  // цвет. Зовём её перекраску на ГРУБОМ шаге: раз в 30° глазу не отличить от
  // непрерывной, а обмер низа окна четыре раза в секунду не нужен никому.
  const LIVE_COARSE_DEG = 30;
  // Кольцо приходит снаружи: три точки — уже круг, больше семи десятков не
  // бывает и разбирать незачем.
  const LIVE_RING_MIN = 3;
  const LIVE_RING_MAX = 72;

  const liveState = {
    on: false, mode: "sync", period: LIVE_PERIOD_DEFAULT, epoch: 0, light: null,
    useLight: false, ring: null, phase: 0, phased: false, hue: null, coarse: null,
    timer: 0, source: null, paints: 0,
  };

  // Устойчивый хэш заголовка (FNV-1a) — запасной способ развести окна по кругу,
  // когда окна нет в присланном списке (открылось позже). Одно и то же имя
  // всегда даёт одну и ту же точку круга.
  const liveHash = text => {
    let hash = 2166136261;
    for (let index = 0; index < text.length; index += 1) {
      hash = Math.imul(hash ^ text.charCodeAt(index), 16777619) >>> 0;
    }
    return hash;
  };
  // Сдвиг окна по кругу в режиме «каждое своим цветом»: место в списке окон
  // (слева направо, как у «Расставить») делит круг поровну. Окна с одинаковым
  // заголовком получат одну фазу — ровно как в автопокраске, где адресация тоже
  // по заголовку.
  const livePhaseFor = titles => {
    const title = windowTitle();
    const list = Array.isArray(titles) ? titles.filter(item => typeof item === "string") : [];
    const index = list.indexOf(title);
    if (list.length > 0 && index >= 0) return (360 * index) / list.length;
    return liveHash(title) % 360;
  };
  const liveReadPhase = () => {
    try {
      const raw = sessionStorage.getItem(LIVE_PHASE_KEY);
      if (raw == null) return null;
      const record = JSON.parse(raw);
      // Окно «Open in new window» стартует с КОПИЕЙ sessionStorage главного окна
      // (см. readSessionEntry): без сверки ключа попап взял бы его фазу и сел
      // на ту же точку круга.
      if (!record || typeof record !== "object" || record.key !== sessionKey()) return null;
      const phase = Number(record.phase);
      return Number.isFinite(phase) ? ((phase % 360) + 360) % 360 : null;
    } catch { return null; }
  };
  const liveWritePhase = phase => {
    const key = sessionKey();
    if (!key) return;
    try { sessionStorage.setItem(LIVE_PHASE_KEY, JSON.stringify({ key, phase })); } catch {}
  };
  // Фаза защёлкивается ОДИН раз на жизнь окна и дальше от заголовка не зависит:
  // у главного окна заголовок меняется на каждом чате (watchChatTitle), и
  // считай мы фазу каждый раз заново — окно перескакивало бы на другую точку
  // круга при каждой смене разговора. Список titles задаёт только начальное
  // распределение. Ключа сессии может ещё не быть (about:blank без заголовка) —
  // тогда фаза живёт в памяти окна, а на диск ляжет при следующем случае.
  //
  // Но защёлкивать НЕ ПО ЧЕМУ, пока имени у окна нет: попап («Новое окно») в
  // первые мгновения сидит на about:blank без заголовка, а безымянный чат носит
  // заглушку («Claude», «New chat») — по такому имени и хэш, и место в списке у
  // ВСЕХ окон одинаковые. Заперлись бы на нём — окна, открытые во время
  // крутёжа, поехали бы одним цветом навсегда, и меню это уже не чинило бы.
  // Поэтому фаза от ненастоящего имени временная: красим ею, но замок не ставим
  // (livePaint пересчитает, как только заголовок появится) и на диск не пишем.
  // Присланный список окон авторитетнее памяти окна и сильнее замка: нашли себя
  // в нём — считаем фазу заново даже при phased, иначе повторное «каждое окно
  // своим цветом» не развело бы окна, слипшиеся по заглушке.
  const liveLatchPhase = titles => {
    const title = windowTitle();
    const real = title !== "" && !THEME_TITLE_STUBS.has(title.toLowerCase());
    const listed = real && Array.isArray(titles) && titles.indexOf(title) >= 0;
    if (liveState.phased && !listed) { liveWritePhase(liveState.phase); return; }
    liveState.phase = (listed ? null : liveReadPhase()) ?? livePhaseFor(titles);
    // Место в списке бывает только у настоящего имени, поэтому «фаза
    // авторитетная ИЛИ имя настоящее» и сводится к одному условию.
    liveState.phased = real;
    if (real) liveWritePhase(liveState.phase);
  };

  // Кольцо — текст снаружи, за который мы не отвечаем: палитра только из шести
  // известных цветов и только hex. Шаг по кругу берём из самой длины кольца
  // (12 точек — 30°), чтобы приложение могло сгустить кольцо, не трогая страницу.
  const liveRing = (list, type) => {
    if (!Array.isArray(list) || list.length < LIVE_RING_MIN) return null;
    const base = THEME_FALLBACK[type];
    const ring = [];
    for (const item of list.slice(0, LIVE_RING_MAX)) {
      if (!item || typeof item !== "object" || Array.isArray(item)) return null;
      const stop = {};
      for (const key of THEME_PALETTE_KEYS) stop[key] = normalizeHex(item[key], base[key]);
      ring.push(stop);
    }
    return ring;
  };
  // Разбор команды и записи из хранилища — один и тот же: в localStorage лежит
  // ровно то, что пришло командой. Кольца нет вовсе — крутить нечем.
  const liveConfig = raw => {
    if (!raw || typeof raw !== "object") return null;
    const rings = raw.ring && typeof raw.ring === "object" ? raw.ring : {};
    const dark = liveRing(rings.dark, "dark");
    const light = liveRing(rings.light, "light");
    if (!dark && !light) return null;
    const period = Number(raw.period);
    const epoch = Number(raw.epoch);
    return {
      mode: raw.mode === "solo" ? "solo" : "sync",
      period: Number.isFinite(period)
        ? Math.min(LIVE_PERIOD_MAX, Math.max(LIVE_PERIOD_MIN, Math.round(period)))
        : LIVE_PERIOD_DEFAULT,
      // Часы окна и часы приложения — одни и те же; epoch не наш, но и не чужой.
      epoch: Number.isFinite(epoch) ? epoch : Date.now(),
      light: raw.light === true ? true : (raw.light === false ? false : null),
      ring: { dark: dark ?? light, light: light ?? dark },
    };
  };
  const liveRead = () => {
    try {
      const raw = JSON.parse(localStorage.getItem(LIVE_KEY) ?? "null");
      return raw?.on === true ? liveConfig(raw) : null;
    } catch { return null; }
  };
  const liveWrite = config => {
    try {
      if (!config) localStorage.removeItem(LIVE_KEY);
      else localStorage.setItem(LIVE_KEY, JSON.stringify({ on: true, ...config }));
    } catch {}
  };

  const liveHue = () => {
    const turns = (Date.now() - liveState.epoch) / (liveState.period * 1000);
    // В режиме «все одним цветом» фаза не участвует вовсе, но защёлкнутое
    // значение сохраняется: переключили режим — окно встало на свою точку круга,
    // а не пересчитало её заново.
    const phase = liveState.mode === "solo" ? liveState.phase : 0;
    return (((turns * 360 + phase) % 360) + 360) % 360;
  };
  // Между опорными точками кольца — прямая в sRGB, покомпонентно (mixHex,
  // раздел 2а). На шаге в 30° контраст промежуточных цветов лежит между
  // контрастами соседей, и глазу это заметно не больше самой смены цвета.
  const livePalette = (ring, hue) => {
    const place = hue / (360 / ring.length);
    const first = Math.floor(place) % ring.length;
    const second = (first + 1) % ring.length;
    const ratio = place - Math.floor(place);
    const palette = {};
    for (const key of THEME_PALETTE_KEYS) palette[key] = mixHex(ring[first][key], ring[second][key], ratio);
    return palette;
  };
  const livePaint = () => {
    if (!liveState.on) return;
    const ring = liveState.useLight ? liveState.ring?.light : liveState.ring?.dark;
    if (!ring || ring.length === 0) return;
    // Замка ещё нет — окно красится временной фазой (при первом мазке имени не
    // было). Пробуем на каждом мазке: заголовок появился — фаза села сама, новой
    // команды из меню для этого не нужно.
    if (!liveState.phased) liveLatchPhase(null);
    const hue = liveHue();
    const type = liveState.useLight ? "light" : "dark";
    // id виден в status().theme.id — на гейте по нему сразу читается, где окно
    // на круге и живой ли это слой вообще.
    const applied = applyTheme({
      id: `live-${type}-${Math.round(hue)}`, name: "Живые цвета", type,
      palette: livePalette(ring, hue),
    }, "live");
    if (!applied) return;
    liveState.hue = hue;
    liveState.paints += 1;
    const coarse = Math.floor(hue / LIVE_COARSE_DEG);
    if (coarse !== liveState.coarse) {
      liveState.coarse = coarse;
      try { placeProgress(); } catch {}
    }
  };
  // evenHidden — первый мазок (команда, подъём из памяти): его пускаем и в
  // спрятанное окно, чтобы к показу цвет был уже верный, но примерку темы он,
  // как и обычный тик, не трогает.
  const liveTick = evenHidden => {
    if (!liveState.on || !state.alive) return;
    // Предпросмотр сильнее: мышь ведут по подменю тем, и затирать примерку через
    // четверть секунды нельзя. Меню закрылось — крутёж продолжился сам.
    if (themeState.previewing) return;
    // Окна не видно — цвет не крутим (батарея). Догонит одним шагом, когда
    // вернётся: цвет считается от часов, а не копится тиками.
    if (document.hidden && !evenHidden) return;
    livePaint();
  };
  const liveInterval = () => Math.round(Math.min(LIVE_TICK_MAX_MS,
    Math.max(LIVE_TICK_MIN_MS, (liveState.period * 1000 * LIVE_STEP_DEG) / 360)));
  const liveStopTimer = () => {
    if (liveState.timer) { clearInterval(liveState.timer); liveState.timer = 0; }
  };
  // Снятие экземпляра (новый инжект по mtime) обязано погасить интервал: иначе в
  // окне крутили бы цвет два таймера сразу.
  track(liveStopTimer);
  const liveStop = restore => {
    liveStopTimer();
    const was = liveState.on;
    liveState.on = false;
    liveState.hue = null;
    liveState.coarse = null;
    liveState.source = null;
    if (!was || !restore) return;
    // Выключение — это ровно «вернуть прежнее»: слой темы поднимается из
    // хранилища по обычному приоритету (чат → сессия → окно → всем), а нет
    // записи нигде — снимается вовсе. Своей ветки отката у живых цветов нет,
    // потому что и запоминать было нечего.
    try { restoreTheme(true, ["theme"]); } catch {}
    try { placeProgress(); } catch {}
  };
  const liveRun = (config, source) => {
    liveStopTimer();
    liveState.on = true;
    liveState.mode = config.mode;
    liveState.period = config.period;
    liveState.epoch = config.epoch;
    liveState.light = config.light;
    // «Как окно сейчас» решается ОДИН раз, на приёме команды: дальше на экране
    // уже живая тема, и спрашивать её тип — спрашивать самих себя.
    liveState.useLight = config.light === null ? themeState.theme?.type === "light" : config.light;
    liveState.ring = config.ring;
    liveState.source = source;
    liveState.coarse = null;
    liveTick(true);
    liveState.timer = setInterval(() => { try { liveTick(); } catch {} }, liveInterval());
  };

  // Контракт WF18: {id, action:"live-colors", at, scope:"all", on, mode, period,
  // epoch, light, titles, ring:{dark,light}}. Выключение — {scope, on:false}, и
  // больше в нём полей нет. Команда одна на все окна, адресации по заголовку у
  // неё нет: своё окно каждая страница отбирает сама (themable).
  const runLiveCommand = detail => {
    if (!themable || !detail || typeof detail !== "object") return false;
    if (detail.on !== true) { liveWrite(null); liveStop(true); return true; }
    const config = liveConfig(detail);
    if (!config) return false;
    liveWrite(config);
    liveLatchPhase(detail.titles);
    liveRun(config, "command");
    return true;
  };
  // Окно, открытое во время крутёжа, поднимает его само: команды ему ждать
  // неоткуда — приложение шлёт её один раз, на нажатие в меню.
  const liveRestore = () => {
    if (!themable) return;
    const config = liveRead();
    if (!config) return;
    liveLatchPhase(null);
    liveRun(config, "storage");
  };
  // Догоняем цвет, как только окно снова видно: тик всё это время молчал.
  on(document, "visibilitychange", () => { try { liveTick(); } catch {} });
  // Осечка живых цветов не должна утащить за собой ручку и полоску — как и у
  // восстановления темы выше.
  try { liveRestore(); } catch {}

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
    // Свёрнутая полоска стоит на 5 точек выше, чем раньше: на кромке строки
    // модели её линия сливалась с полосой прогресса (слово Элвиса 05.09 19:30).
    handle.style.top = `${Math.round(row && row.height > 0
      ? row.top - HANDLE_HEIGHT - 2
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
      if (!text || !Number.isFinite(at)) return null;
      const record = { at, text };
      // Поля переноса (WF37, эталоны tests/fixtures/cashout): to — кому запись
      // предназначена (CASHOUT_PENDING — адресата ещё нет), title — заголовок
      // строки сайдбара нового чата, stampedAt — когда штамповали. Поля to нет
      // — это обычная запись главного окна, и правила у неё прежние.
      const to = typeof data?.to === "string" ? data.to.trim() : "";
      if (!to) return record;
      record.to = to;
      record.title = typeof data?.title === "string" ? data.title.trim() : "";
      const stampedAt = Number(data?.stampedAt);
      record.stampedAt = Number.isFinite(stampedAt) ? stampedAt : null;
      return record;
    } catch { return null; }
  };
  // Слепок записи для гейта (status().cashout): есть ли она, кому адресована,
  // под каким заголовком её ждут и когда штамповали.
  const cashoutState = () => {
    const record = readCashout();
    return {
      record: record != null,
      to: record?.to ?? null,
      title: record?.title || null,
      stampedAt: record?.stampedAt ?? null,
    };
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
  // «Эта запись — мне?» (WF37). true — да, false — точно нет, null — сказать
  // нечего: своего id окно ещё не знает, а заголовок не совпал.
  // Заголовок — второй, запасной признак: попап получает его от сессии в момент
  // выноса, и до первого ответа probe это единственное, чем он себя знает.
  // Заглушки («Claude», «New chat») в сопоставлении не участвуют вовсе — их
  // носят разные чаты во всех окнах разом.
  const cashoutMine = record => {
    const id = myChatId();
    if (id && id === record.to) return true;
    const title = windowTitle();
    if (title && record.title === title && !THEME_TITLE_STUBS.has(title.toLowerCase())) return true;
    return id ? false : null;
  };
  // Попап узнаёт свой id только у окна-родителя (раздел 12в), и сторож спрашивает
  // его РОВНО один раз на запись: ответ ложится в кэш myclaude-chat-v1, и
  // следующий тик берёт id уже оттуда. Не ответили — ждём круга probe от
  // приложения, а не долбим родителя каждые 300 мс.
  const cashoutAskParent = () => {
    if (state.cashoutAsked) return;
    state.cashoutAsked = true;
    try { Promise.resolve(chatsAsk(true)).catch(() => {}); } catch {}
  };
  const tryPasteCashout = () => {
    const record = readCashout();
    if (record == null) return "нет записи";
    if (record.to != null) {
      // Перенос из подчинённого окна (WF37, #5575) адресован НОВОМУ окну,
      // которое родит цепочка «Нового окна». Главное окно такие записи не
      // трогает вовсе: ⌘N в нём случается по десять раз на дню, и перенос
      // уехал бы в чат, где Элвис работает.
      if (isMainWindow()) return "перенос не главному окну";
      if (record.to === CASHOUT_PENDING) {
        // Цепочка сорвалась и адресата так и не назвала: запись умирает молча
        // по общему сроку от нажатия (риск 3 плана WF37).
        if (Date.now() - record.at > CASHOUT_FRESH_MS) { clearCashout(); return "запись протухла"; }
        return "адресат не назначен";
      }
      if (record.stampedAt == null || Date.now() - record.stampedAt > CASHOUT_STAMP_FRESH_MS) {
        clearCashout();
        return "перенос протух";
      }
      const mine = cashoutMine(record);
      if (mine === null) { cashoutAskParent(); return "чат не опознан"; }
      if (!mine) return "перенос не в это окно";
    } else if (Date.now() - record.at > CASHOUT_FRESH_MS) { clearCashout(); return "запись протухла"; }
    const editor = state.editor?.isConnected ? state.editor : findEditor();
    if (!editor?.isConnected) return "нет редактора";
    // Вставляем только в свежий чат и только в пустое поле: иначе перенос
    // затёр бы чужой черновик или лёг посреди разговора. Свежесть чата
    // спрашиваем только у записи БЕЗ адресата: у переноса окно названо
    // поимённо, а первым сообщением в нём может оказаться что угодно.
    if (record.to == null && !isFreshChat()) return "чат не свежий";
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
  const CASHOUT_WATCH_DONE = new Set([
    "вставлено", "запись протухла", "нет записи",
    // Перенос протух или достался главному окну — ждать в этом окне больше
    // нечего: свою запись главное окно заведёт заново, вместе со сторожем.
    "перенос протух", "перенос не главному окну",
  ]);
  const armCashoutWatch = () => {
    clearCashoutWatch();
    if (readCashout() == null) return;
    // Вопрос родителю — один на запись, а не на сторожа: новая запись имеет
    // право спросить заново (см. cashoutAskParent).
    state.cashoutAsked = false;
    state.cashoutTimer = setInterval(() => {
      if (!state.alive) { clearCashoutWatch(); return; }
      const result = tryPasteCashout();
      if (CASHOUT_WATCH_DONE.has(result)) clearCashoutWatch();
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
    // Из подчинённого окна перенос уезжает в НОВОЕ окно (WF37, #5575): ⌘N в
    // попапе исполняет главное окно Claude, и старый путь бил по чату, где
    // Элвис ведёт диктовку. Адресата назовёт цепочка «Нового окна»
    // (cashoutStamp), поэтому здесь только пометка «ждёт адресата». Своего
    // сторожа донор не заводит и чужого не оставляет: вставлять перенос ему
    // некуда, а тикать 300 мс впустую незачем.
    const transfer = !isMainWindow();
    const record = transfer
      ? { at: Date.now(), text, to: CASHOUT_PENDING }
      : { at: Date.now(), text };
    try { localStorage.setItem(CASHOUT_KEY, JSON.stringify(record)); } catch { return false; }
    if (transfer) clearCashoutWatch(); else armCashoutWatch();
    return true;
  };
  // Штамп переноса (WF37): цепочка «Нового окна» с полем transfer называет
  // адресата записи, оставленной попапом-донором, — id только что рождённого
  // чата и заголовок его строки сайдбара. Записи без пометки «ждёт адресата»
  // не трогаем вовсе: чужой перенос и обычная запись главного окна обязаны
  // остаться как были (критик плана, блокер 2).
  const cashoutStamp = (id, title) => {
    const record = readCashout();
    if (record == null || record.to !== CASHOUT_PENDING) return false;
    const chat = typeof id === "string" ? id.trim() : "";
    if (!chat) return false;
    const stamped = {
      at: record.at,
      text: record.text,
      to: chat,
      title: typeof title === "string" ? title.trim() : "",
      stampedAt: Date.now(),
    };
    try { localStorage.setItem(CASHOUT_KEY, JSON.stringify(stamped)); } catch { return false; }
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

  // ---- 12б. «Новое окно» и «В отдельное окно» -----------------------------
  // Пункт меню «🪟 Новое окно»: новый чат Claude Code сразу отдельным окном.
  // Одним вызовом это не делается — окно-попап живёт поверх СУЩЕСТВУЮЩЕЙ сессии,
  // а локальная сессия рождается только на первом сообщении (свежий local_<uuid>
  // даёт «This session couldn't be found»). Поэтому порядок ровно тот, что Элвис
  // проходит руками: ⌘N → «Привет» → отправка → вынести получившийся чат в окно
  // → вернуть главное окно на прежний разговор.
  //
  // Само окно открывает не страница, а приложение claude.ai: у него есть стор с
  // действием openPopout({type:"code-session", sessionId, …}) — тот же, что за
  // пунктом «Open in new window» и за ⌘-кликом по строке чата в сайдбаре. Стор
  // ищем ПОВЕДЕНЧЕСКИ (по наличию popoutWindows и openPopout), а не по имени
  // экспорта: имена чанков и экспортов claude.ai меняются каждый релиз.
  //
  // Второй пункт, «🪟 В отдельное окно» (команда popout-window), — последний шаг
  // того же пути в отдельности: вынести ТЕКУЩИЙ чат. Он же честная деградация:
  // не сложилось у «Нового окна» уже после создания чата — плашка зовёт его.
  //
  // ⌘N жмёт Swift штатной клавишей: синтетический KeyboardEvent на document
  // Claude не слышит вовсе (проверено 04.09), поэтому страница только ЖДЁТ.
  const NEW_WINDOW_NOTE_ID = "myclaude-new-window-note";
  const NEW_WINDOW_HOME_PATH = "/epitaxy";
  const NEW_WINDOW_INPUT_SELECTOR = '[data-testid="code-prompt-input"]';
  const NEW_WINDOW_SEND_SELECTOR = '[data-testid="code-prompt-send"]';
  const NEW_WINDOW_ROWS_SELECTOR = '[data-testid="sidebar-recents"]';
  // Шаг опроса: смену адреса роутер делает без события, ловить её нечем.
  const NEW_WINDOW_POLL_MS = 100;
  // Сколько ждём домашний экран после ⌘N от приложения.
  const NEW_WINDOW_HOME_MS = 5000;
  // Кнопка отправки бывает disabled, пока не выбраны папка и модель.
  const NEW_WINDOW_SEND_MS = 3000;
  // Сессия заводится не мгновенно: адрес становится /epitaxy/local_<uuid>.
  const NEW_WINDOW_SESSION_MS = 15000;
  // Строка сайдбара появляется, когда сессия уже создана; её имя уходит в окно.
  const NEW_WINDOW_ROW_MS = 20000;
  // Строки так и нет — даём ей последний вздох и идём дальше без имени.
  const NEW_WINDOW_ROW_GRACE_MS = 1500;
  // Возврат главного окна на прежний чат.
  const NEW_WINDOW_BACK_MS = 1000;
  // Папка проекта (WF16): сколько ждём, пока выбор дойдёт до стора, а потом до
  // чипа на домашнем экране.
  const NEW_WINDOW_FOLDER_MS = 5000;
  // Переименование чата (WF16): контекстное меню строки, поле имени, закрытие.
  const NEW_WINDOW_MENU_MS = 1500;
  const NEW_WINDOW_RENAME_MS = 2000;
  // Сколько ждём, пока новое имя доедет до строки сайдбара (критик WF16, В3).
  const NEW_WINDOW_TITLE_MS = 2000;
  // Страховка: сорвавшийся прогон не должен выключить кнопку навсегда.
  // С WF16 к цепочке добавились папка (до 10 с) и имя (до 7,5 с).
  const NEW_WINDOW_GUARD_MS = 95000; // худшая цепочка ожиданий ≈ 65 с (verify WF13, находка 2)
  const NEW_WINDOW_NOTE_MS = 3000;
  const NEW_WINDOW_NOTE_FAIL = "Новое окно не открылось";
  const NEW_WINDOW_NOTE_CREATED = "Отдельным окном не вышло, чат создан здесь.\nМеню ▸ 🪟 В отдельное окно";
  const NEW_WINDOW_NOTE_DRAFT = "В поле ввода черновик — новый чат не открываю";
  const NEW_WINDOW_NOTE_FOLDER = "Сообщение не ушло: не выбрана папка";
  // Папку выбрать не вышло (макет WF16): чат в чужой папке хуже отказа — там
  // работает авто-Allow, и агент стартовал бы в чужом проекте.
  const NEW_WINDOW_NOTE_FOLDER_PICK = "Не смог выбрать папку — чат не создавал";
  const NEW_WINDOW_NOTE_CHAT = "Сначала открой чат — выносить нечего";
  const NEW_WINDOW_NOTE_POPOUT = "Отдельным окном не вышло";
  // Пункт нажали в самом окне-попапе: этот чат уже вынесен, выносить его некуда.
  // Раньше команда там тихо умирала (слово Элвиса 05.09: «ничего не произошло»).
  const NEW_WINDOW_NOTE_ALREADY = "Этот чат уже в отдельном окне";
  // Пункт «Переименовать» ищем по началу текста: у claude.ai он английский, но
  // сборка бывает и русской.
  const NEW_WINDOW_RENAME_RE = /^(rename|переимен)/i;
  const NEW_WINDOW_MENU_SELECTOR = '[role="menuitem"], [role="menu"] button, [role="menu"] [role="button"]';
  // Чип папки на домашнем экране («Local / <папка> / <ветка>»): своего селектора
  // у него мы не снимали, узнаём по тексту среди кнопок и списков.
  const NEW_WINDOW_CHIP_SELECTOR = 'button, [role="button"], [role="combobox"]';
  // Поле имени у переименования: модалка, инлайн-поле строки или contenteditable.
  const NEW_WINDOW_NAME_SELECTOR = 'input[type="text"], input:not([type]), textarea, [contenteditable="true"]';

  // Все таймеры раздела — в одном наборе: снимаются разом на dispose, а реестр
  // уборки не пухнет от сотен опросов по 100 мс.
  const newWindowTimers = new Set();
  const newWindowLater = (fn, ms) => {
    const timer = setTimeout(() => { newWindowTimers.delete(timer); fn(); }, ms);
    newWindowTimers.add(timer);
    return timer;
  };
  const newWindowClearTimers = () => {
    for (const timer of newWindowTimers) { try { clearTimeout(timer); } catch {} }
    newWindowTimers.clear();
  };
  // У каждого запуска свой номер. Живой inject.js перечитывается по mtime, и
  // `cp` посреди работы кнопки поднял бы второй экземпляр: старая цепочка ждёт
  // адреса ещё десятки секунд и открыла бы ВТОРОЕ окно. Номер и state.alive
  // проверяет каждый шаг.
  let newWindowToken = 0;
  const newWindowLive = token => state.alive && token === newWindowToken;
  const newWindowMark = patch => {
    state.newWindow = { ...(state.newWindow ?? {}), ...patch, at: Date.now() };
  };
  const newWindowRuns = () => (Number(state.newWindow?.runs) || 0) + 1;
  const newWindowError = error => String(error?.message ?? error).slice(0, 200);

  // Плашка отказа. Молчать нельзя: со стороны пункт меню выглядит сломанным
  // (прецедент MenuModel.workflowKitMissingAlert). Стиль — подсказки полосы
  // прогресса (раздел 2б), слой на единицу ниже неё: подсказка Элвиса важнее.
  let newWindowNoteNode = null;
  let newWindowNoteTimer = 0;
  const newWindowNoteHide = drop => {
    if (newWindowNoteTimer) {
      clearTimeout(newWindowNoteTimer);
      newWindowTimers.delete(newWindowNoteTimer);
      newWindowNoteTimer = 0;
    }
    if (!newWindowNoteNode) return;
    if (drop) { try { newWindowNoteNode.remove(); } catch {} newWindowNoteNode = null; return; }
    newWindowNoteNode.style.setProperty("display", "none");
  };
  const newWindowNote = text => {
    if (!text) return;
    newWindowNoteHide(false);
    if (!newWindowNoteNode) {
      const node = document.createElement("div");
      node.id = NEW_WINDOW_NOTE_ID;
      node.setAttribute("aria-hidden", "true");
      // Стили прямо в узел, без <style>: CSP страницы может не пустить нашу
      // таблицу, а element.style ей неподвластен (довод раздела 2б).
      for (const [name, value] of Object.entries({
        position: "fixed", display: "none", "max-width": "420px",
        padding: "8px 10px", "border-radius": "8px", "border-width": "1px", "border-style": "solid",
        font: "12px/1.45 -apple-system, system-ui, sans-serif", "white-space": "pre-line",
        "pointer-events": "none", "z-index": "2147483644",
        left: "50%", transform: "translateX(-50%)", bottom: "96px",
      })) node.style.setProperty(name, value);
      (document.body ?? document.documentElement).appendChild(node);
      newWindowNoteNode = node;
    }
    // Только textContent: текст свой, но разметке в плашке делать нечего.
    newWindowNoteNode.textContent = text;
    for (const [name, value] of Object.entries(progressDark()
      ? { background: "#12151c", color: "#e7e9f0", "border-color": "#2a2f3a", "box-shadow": "0 8px 24px rgba(0,0,0,.45)" }
      : { background: "#ffffff", color: "#14181f", "border-color": "#d7dbe3", "box-shadow": "0 8px 24px rgba(15,20,30,.18)" })) {
      newWindowNoteNode.style.setProperty(name, value);
    }
    newWindowNoteNode.style.setProperty("display", "block");
    newWindowNoteTimer = newWindowLater(() => { newWindowNoteTimer = 0; newWindowNoteHide(false); }, NEW_WINDOW_NOTE_MS);
  };
  // Экземпляр уходит — с ним уходят таймеры, плашка и признак занятости: иначе
  // `cp inject.js` посреди работы оставил бы кнопку «занятой» навсегда.
  track(() => {
    newWindowClearTimers();
    newWindowNoteHide(true);
    if (state.newWindow) state.newWindow.busy = false;
  });

  // Ожидание опросом: вернёт найденное или null, когда время вышло либо
  // экземпляр сменился.
  const newWindowWait = (check, limitMs, token) => new Promise(resolve => {
    const deadline = now() + limitMs;
    const tick = () => {
      if (!newWindowLive(token)) { resolve(null); return; }
      let hit = null;
      try { hit = check(); } catch { hit = null; }
      if (hit) { resolve(hit); return; }
      if (now() >= deadline) { resolve(null); return; }
      newWindowLater(tick, NEW_WINDOW_POLL_MS);
    };
    tick();
  });
  const newWindowSleep = ms => new Promise(resolve => { newWindowLater(resolve, ms); });

  // Объявления, а не стрелки в `const`: обе функции нужны ключу темы по id чата
  // (chatIdKey, раздел 2а) уже на инжекте, а он стоит ВЫШЕ по файлу — `const` к
  // тому мгновению ещё в TDZ, а объявление поднимается (WF35).
  function newWindowSegment(path) { return String(path ?? "").split("/").filter(Boolean).pop() ?? ""; }
  // Открытый чат Claude Code — /epitaxy/local_<uuid>. Всё прочее (обычный чат
  // claude.ai, домашний экран) сессии popout не даёт.
  function newWindowSessionId() {
    const id = newWindowSegment(location.pathname);
    return id.startsWith("local_") ? id : "";
  }
  const newWindowAtHome = () =>
    location.pathname === NEW_WINDOW_HOME_PATH && Boolean(document.querySelector(NEW_WINDOW_INPUT_SELECTOR));
  // Ключи строк сайдбара — chat:<uuid> / code:… / local_…, поэтому ищем по концу.
  // Значение внутри кавычек селектора экранируем сами: CSS.escape пишет по
  // правилам идентификатора и в строке в кавычках только испортил бы ключ.
  const newWindowRow = id => {
    if (!id) return null;
    try {
      const key = String(id).replace(/["\\]/g, "\\$&");
      return document.querySelector(`${NEW_WINDOW_ROWS_SELECTOR} [data-row-key$="${key}"]`);
    } catch { return null; }
  };
  const newWindowRowTitle = row => {
    const raw = String(row?.innerText ?? row?.textContent ?? "").trim();
    return (raw.split("\n").map(line => line.trim()).find(Boolean) ?? "").slice(0, 200);
  };

  // Стор ищем ТОЛЬКО по приходу команды и останавливаемся на первом совпадении:
  // import() исполняет те модули, которые страница ещё не выполняла (preload —
  // не исполнение), а это чужая инициализация в чужой странице. Найденное — в
  // кэш замыкания; кэш перепроверяем, вдруг стор пересобрали.
  let newWindowStore = null;
  const newWindowStoreOk = store => {
    try {
      const value = store?.getState?.();
      return Boolean(value && value.popoutWindows instanceof Map && typeof value.openPopout === "function");
    } catch { return false; }
  };
  const newWindowModuleUrls = () => {
    const urls = [];
    const seen = new Set();
    const add = href => {
      const url = typeof href === "string" ? href : "";
      if (!url || seen.has(url)) return;
      seen.add(url);
      urls.push(url);
    };
    try { for (const link of document.querySelectorAll('link[rel="modulepreload"]')) add(link.href); } catch {}
    // Запасной источник адресов: ссылок modulepreload в окне может не оказаться.
    try {
      for (const entry of performance.getEntriesByType("resource")) {
        const name = String(entry?.name ?? "");
        if (/\/assets\/v1\/[^?#]*\.js(\?|#|$)/.test(name)) add(name);
      }
    } catch {}
    return urls;
  };
  // Сиденье импортёра модулей. В бою — тот же самый import(), байт в байт; в
  // стенде тестов его подменяют через люк (setModuleImporter). Иначе скан в
  // тестах не проверить вовсе: tests/load.mjs гоняет файл через
  // vm.runInContext БЕЗ опции importModuleDynamically, живой import() там
  // бросает ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING, а бросок молча съедает
  // catch на каждый адрес — скан не нашёл бы ничего никогда и «импортов ровно
  // столько же» считать было бы нечем (план WF29, решение 4).
  let moduleImporter = url => import(url);
  const setModuleImporter = fn => { moduleImporter = typeof fn === "function" ? fn : url => import(url); };
  // Обход модулей общий на оба стора раздела (попапы и папка проекта): проход
  // один и тот же, разный только предикат.
  const newWindowScanStores = async (token, ok) => {
    for (const url of newWindowModuleUrls()) {
      if (!newWindowLive(token)) return null;
      let chunk = null;
      // Каждый import в своём try: чужой модуль вправе упасть на исполнении.
      try { chunk = await moduleImporter(url); } catch { continue; }
      try {
        for (const key of Object.keys(chunk)) {
          const value = chunk[key];
          if (typeof value !== "function" || typeof value.getState !== "function") continue;
          if (ok(value)) return value;
        }
      } catch {}
    }
    return null;
  };
  const newWindowFindStore = async token => {
    if (newWindowStoreOk(newWindowStore)) return newWindowStore;
    newWindowStore = await newWindowScanStores(token, newWindowStoreOk);
    return newWindowStore;
  };

  // Папка проекта (WF16, ступень b). Домашний экран /epitaxy держит выбранную
  // папку в СВОЁМ сторе (разведка П2, снято живьём 04.09): состояние с полями
  // selectedFolder и trustedSelectedFolder, действия setLocalSelectedFolder(path)
  // и setTrustedSelectedFolder(path). Имя экспорта у него своё («Zt» в сборке
  // 04.09) и меняется с каждым релизом — ищем ПОВЕДЕНЧЕСКИ, как и стор попапов,
  // и держим в кэше замыкания с перепроверкой.
  //
  // Доверие ставим сразу вторым вызовом: setLocalSelectedFolder обнуляет
  // trustedSelectedFolder, и без него Claude поднял бы модальное окно доверия к
  // папке, на котором вся цепочка встала бы (разведка WF16, п. 6). Папки в меню
  // — только те, где сессии уже были, то есть доверенные.
  let newWindowFolderStore = null;
  const newWindowFolderStoreOk = store => {
    try {
      const value = store?.getState?.();
      return Boolean(value && typeof value === "object"
        && typeof value.setLocalSelectedFolder === "function"
        && "selectedFolder" in value);
    } catch { return false; }
  };
  const newWindowFindFolderStore = async token => {
    if (newWindowFolderStoreOk(newWindowFolderStore)) return newWindowFolderStore;
    // Присваиваем только находку: прерванный по токену скан отдаёт null, и он не
    // должен затирать стор, который тем временем нашла цепочка «Нового окна»
    // (сканеров с WF37 два — проверка WF37, находка 1).
    const found = await newWindowScanStores(token, newWindowFolderStoreOk);
    if (found) newWindowFolderStore = found;
    return newWindowFolderStore;
  };
  // Хвостовой слэш путь не меняет: «…/Dictatorik» и «…/Dictatorik/» — одна папка.
  const newWindowFolderPath = value => {
    let path = typeof value === "string" ? value.trim() : "";
    while (path.length > 1 && path.endsWith("/")) path = path.slice(0, -1);
    return path;
  };
  const newWindowFolderName = path => newWindowFolderPath(path).split("/").filter(Boolean).pop() ?? "";
  const newWindowFolderNow = store => {
    try { return newWindowFolderPath(store?.getState?.()?.selectedFolder); } catch { return ""; }
  };
  // Чип папки виден на домашнем экране, и по нему проверяется, что стор мы нашли
  // ТОТ: своего селектора у чипа нет, поэтому узнаём его по тексту — имени папки.
  const newWindowChipShows = name => {
    if (!name) return false;
    try {
      for (const node of document.querySelectorAll(NEW_WINDOW_CHIP_SELECTOR)) {
        if (String(node.textContent ?? "").replace(/\s+/g, " ").trim() === name) return true;
      }
    } catch {}
    return false;
  };
  // Шаг «папка»: поставить папку проекта и СВЕРИТЬ обратно. Отдаёт "ok",
  // "no-folder-ui" (нечем выбирать — стора нет) или "folder-missing" (выбор не
  // встал). Правда одна — значение в сторе: он и есть то, с чем Claude заведёт
  // сессию. Чип на экране — только пометка (WF36, #5544): его текст рисуется
  // своим тактом и на глазах Элвиса отставал, а шаг из-за этого откатывался
  // целиком. Чип спрашиваем там, где он нашёлся до переключения (с прежней
  // папкой), и кладём в state.newWindow.chip: "ok" (сменился), "stale" (стор
  // принял, а чип не догнал), "none" (чипа не видно вовсе). Сравнение остаётся
  // ТОЧНЫМ: по префиксу «Dictator» совпал бы с «Dictatorik» — ложное ok.
  const newWindowPickFolder = async (folder, token) => {
    const store = await newWindowFindFolderStore(token);
    if (!newWindowLive(token) || !store) return "no-folder-ui";
    const want = newWindowFolderPath(folder);
    const before = newWindowFolderNow(store);
    const chipBefore = before !== "" && newWindowChipShows(newWindowFolderName(before));
    try {
      const actions = store.getState();
      actions.setLocalSelectedFolder(folder);
      if (typeof actions.setTrustedSelectedFolder === "function") actions.setTrustedSelectedFolder(folder);
    } catch { return "folder-missing"; }
    const picked = await newWindowWait(
      () => (newWindowFolderNow(store) === want ? true : null), NEW_WINDOW_FOLDER_MS, token);
    if (!newWindowLive(token) || !picked) return "folder-missing";
    if (!chipBefore) { newWindowMark({ chip: "none" }); return "ok"; }
    const chip = await newWindowWait(
      () => (newWindowChipShows(newWindowFolderName(want)) ? true : null), NEW_WINDOW_FOLDER_MS, token);
    if (!newWindowLive(token)) return "folder-missing";
    newWindowMark({ chip: chip ? "ok" : "stale" });
    return "ok";
  };

  // Имя чата (WF16). Штатного действия в предзагруженных сторах claude.ai нет
  // (разведка П2: у попапов есть setPopoutTitle, но renameSession/setSessionTitle
  // там не лежит), поэтому переименовываем тем же путём, каким это делает Элвис
  // руками, — контекстным меню строки сайдбара. Путь заведомо хрупкий, и вся
  // цепочка от него не зависит: не нашли пункта или поля — молча идём дальше
  // (статус no-rename), имя чата остаётся авто-заголовком Claude, а ключ темы и
  // заголовок окна берутся из ФАКТИЧЕСКОЙ строки сайдбара (критик WF16, В3).
  const newWindowMenuClose = () => {
    try {
      document.dispatchEvent(new KeyboardEvent("keydown", {
        key: "Escape", code: "Escape", keyCode: 27, which: 27, bubbles: true, cancelable: true,
      }));
    } catch {}
    try { document.body?.click(); } catch {}
  };
  // Поле имени: живое, редактируемое и заведомо НЕ поле ввода чата — иначе имя
  // проекта уехало бы в композер только что созданного разговора.
  const newWindowNameField = node => {
    if (!node?.isConnected) return false;
    try { if (node.closest?.(NEW_WINDOW_INPUT_SELECTOR)) return false; } catch {}
    if (node.tagName === "INPUT") return /^(text|search|)$/i.test(node.getAttribute("type") ?? "");
    if (node.tagName === "TEXTAREA") return true;
    return node.isContentEditable === true;
  };
  const newWindowNameText = node => String(node?.value ?? node?.innerText ?? node?.textContent ?? "").trim();
  // React слушает не .value, а событие input: присвоение напрямую он не видит,
  // поэтому значение ставим родным сеттером прототипа и досылаем события сами.
  const newWindowNameSet = (node, value) => {
    try {
      const proto = node.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      const setter = Object.getOwnPropertyDescriptor(proto, "value")?.set;
      if (setter) setter.call(node, value); else node.value = value;
      node.dispatchEvent(new Event("input", { bubbles: true }));
      node.dispatchEvent(new Event("change", { bubbles: true }));
    } catch {}
  };
  const newWindowRename = async (row, name, token) => {
    if (!row?.isConnected || !name) return false;
    try {
      const box = row.getBoundingClientRect();
      row.dispatchEvent(new MouseEvent("contextmenu", {
        bubbles: true, cancelable: true, view: window,
        clientX: Math.round(box.left + box.width / 2), clientY: Math.round(box.top + box.height / 2),
      }));
    } catch { return false; }
    const item = await newWindowWait(() => {
      try {
        for (const node of document.querySelectorAll(NEW_WINDOW_MENU_SELECTOR)) {
          if (NEW_WINDOW_RENAME_RE.test(String(node.textContent ?? "").trim())) return node;
        }
      } catch {}
      return null;
    }, NEW_WINDOW_MENU_MS, token);
    // Меню за собой гасим ВСЕГДА: команда идёт в живом окне Элвиса, и открытое
    // контекстное меню там оставлять нельзя.
    if (!item) { newWindowMenuClose(); return false; }
    try { item.click(); } catch { newWindowMenuClose(); return false; }
    // Где появится поле имени — в модалке или прямо в строке, — зависит от
    // сборки claude.ai, поэтому берём то, что под фокусом, а нет его — первое
    // поле внутри модалки или списка чатов. Дальше этих двух мест не смотрим
    // НАРОЧНО: промахнись мы полем — имя проекта уехало бы в чужую строку
    // живого окна Элвиса (поиск по чатам, поле ввода).
    const field = await newWindowWait(() => {
      const hosts = [];
      try { hosts.push(...document.querySelectorAll('[role="dialog"]')); } catch {}
      try {
        const rows = document.querySelector(NEW_WINDOW_ROWS_SELECTOR);
        if (rows) hosts.push(rows);
      } catch {}
      const active = document.activeElement;
      if (newWindowNameField(active) && hosts.some(host => host.contains(active))) return active;
      for (const host of hosts) {
        let found = null;
        try { found = host.querySelector(NEW_WINDOW_NAME_SELECTOR); } catch {}
        if (newWindowNameField(found)) return found;
      }
      return null;
    }, NEW_WINDOW_RENAME_MS, token);
    if (!field) { newWindowMenuClose(); return false; }
    try { field.focus(); } catch {}
    if (typeof field.value === "string") {
      try { field.select?.(); } catch {}
      newWindowNameSet(field, name);
    } else {
      try { document.execCommand("selectAll", false, null); } catch {}
      try { document.execCommand("insertText", false, name); } catch {}
    }
    if (newWindowNameText(field) !== name) { newWindowMenuClose(); return false; }
    // Подтверждение — Enter в самом поле: кнопки «Сохранить» у переименования
    // может и не быть, а Enter понимают обе разметки.
    try {
      for (const type of ["keydown", "keypress", "keyup"]) {
        field.dispatchEvent(new KeyboardEvent(type, {
          key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true, cancelable: true,
        }));
      }
    } catch {}
    // Поле ушло из документа — переименование приняли. Осталось на месте —
    // гасим за собой и честно говорим «не вышло».
    const closed = await newWindowWait(() => (field.isConnected ? null : true), NEW_WINDOW_RENAME_MS, token);
    if (!closed) { newWindowMenuClose(); return false; }
    return true;
  };

  // Общий шаг обоих пунктов: вынести сессию в отдельное окно. Заголовок берём
  // тот, что показывает сайдбар (константу «Новый чат» передавать нельзя — это
  // заглушка из THEME_TITLE_STUBS, и ключа темы chat: у окна не будет вовсе).
  const newWindowOpenPopout = (store, id, title, x, y) => {
    store.getState().openPopout({
      type: "code-session",
      sessionId: id,
      sessionType: "local",
      isSsh: false,
      title,
      entryPoint: "context_menu",
      initialPosition: { x, y },
    });
  };

  // Возврат главного окна на прежний разговор. Основной путь — клик по строке
  // сайдбара: это собственная навигация приложения. Запасной — history: после
  // ⌘N и отправки окно прошло ДВЕ навигации, поэтому шагов назад тоже два.
  // pushState для возврата не годится: он затирает служебный history.state
  // роутера и ломает back/forward до перезагрузки страницы.
  const newWindowBack = async (prev, prevId, lengthBefore, token) => {
    if (location.pathname === prev) { newWindowMark({ back: "stay" }); return; }
    const row = newWindowRow(prevId);
    if (row) { try { (row.querySelector("a,button") ?? row).click(); } catch {} }
    else {
      const steps = history.length - lengthBefore;
      // history.go(0) — это перезагрузка страницы, а не шаг назад.
      if (steps <= 0) { newWindowMark({ back: "back-failed" }); return; }
      try { history.go(-steps); } catch {}
    }
    const ok = await newWindowWait(() => (location.pathname === prev ? true : null), NEW_WINDOW_BACK_MS, token);
    // Не вернулось — оставляем как есть: лучше остаться на новом чате, чем
    // ломать роутер главного окна.
    newWindowMark({ back: ok ? (row ? "row" : "history") : "back-failed" });
  };

  // Команда «Новое окно», контракт WF16 (расширение WF13), с WF37 —
  // необязательное transfer после name: {id, action:"new-window", at,
  // scope:"window", title, match?, x, y, text, folder, name, transfer?,
  // theme?, font?, size?, frame?}. Исполняет только ГЛАВНОЕ окно и только
  // адресованное заголовком: страниц claude.ai может оказаться две, и обе
  // завели бы по чату.
  //
  // folder и name — всегда есть, пустая строка = «не трогать» (это и есть
  // поведение WF13). Слои — по правилам команды theme: поля нет — слой не
  // трогаем, null — сброс. Уникальность имени считает приложение по всем
  // сессиям на диске: страница номер не придумывает и сайдбар на совпадения не
  // проверяет (критик WF16, В4).
  const runNewWindowCommand = async detail => {
    if (!isMainWindow() || !addressed(detail)) return false;
    const text = typeof detail?.text === "string" ? detail.text.trim() : "";
    // Координаты — именно ЧИСЛА, не строки: CommandChannel.write(action:extra:)
    // делает все значения строками, и такую команду мы обязаны отбить, а не
    // молча склеить (контракт WF13 требует write(action:fields:) с .number).
    const x = detail?.x;
    const y = detail?.y;
    const folder = typeof detail?.folder === "string" ? detail.folder.trim() : "";
    // Папка — только абсолютный путь (Swift шлёт standardizedFileURL.path); мусор
    // отсекаем сразу, а не поздним no-folder (verify WF16, находка 5).
    if (folder && !folder.startsWith("/")) { newWindowMark({ state: "bad-command", step: "folder" }); return false; }
    // Длину имени режем ровно так же, как её режет строка сайдбара
    // (newWindowRowTitle): иначе сверка заголовка не сошлась бы никогда.
    const name = typeof detail?.name === "string" ? detail.name.trim().slice(0, 200) : "";
    // Перенос «Обкэшить» (WF37): поле есть ТОЛЬКО у ветки «Обкэшить» из попапа
    // и разбирается строго. Любая другая правда (строка "true", 1, объект)
    // переносом не считается: ⌥⌘N, «▸ проект», «Здесь же» и канал «Пимп» чужую
    // запись переноса не трогают вовсе (критик плана, блокер 2).
    const transfer = detail?.transfer === true;
    const layers = {};
    for (const layer of THEME_LAYERS) {
      if (detail && layer in detail) layers[layer] = LAYER_NORMALIZE[layer](detail[layer]);
    }
    if (detail?.scope !== "window" || !text || !Number.isFinite(x) || !Number.isFinite(y)) {
      newWindowMark({ state: "bad-command", step: null });
      return false;
    }
    // Второй клик, пока идёт первый: два «Привета» в два чата никому не нужны.
    if (state.newWindow?.busy === true) { newWindowMark({ state: "busy" }); return false; }
    const token = ++newWindowToken;
    newWindowMark({
      state: "run", step: "store", id: null, back: null, pushed: false, busy: true, runs: newWindowRuns(),
      // Поля WF16 — начисто на каждый запуск: иначе на гейте не отличить, что
      // от этого прогона, а что осталось от прошлого.
      folder: folder || null, chip: null, name: name || null, rename: null, title: null,
      layers: Object.keys(layers).length ? Object.keys(layers) : null,
      // WF37: разобрано ли поле transfer и удалось ли штампануть перенос.
      transfer: transfer || null, stamped: null,
    });
    // Мягкая осечка: чат создан и вынесен, но имя или цвет не задались. Роняет
    // не цепочку, а только итоговый статус — плашки у неё нет.
    let soft = null;
    const guard = newWindowLater(() => {
      if (token !== newWindowToken) return;
      newWindowMark({ state: "timeout", busy: false });
    }, NEW_WINDOW_GUARD_MS);
    // Чат уже заведён — возвращать главное окно на прежний разговор нельзя:
    // новый чат живёт именно здесь, и плашка зовёт вынести его вторым пунктом.
    let created = false;
    try {
      // Прежний разговор запоминаем ДО поиска стора: поиск идёт около секунды,
      // а Swift жмёт ⌘N через 0,9 с — иначе «прежним» окажется уже /epitaxy
      // (verify WF13, находка 1).
      const prev = location.pathname;
      // Домашний экран прежним разговором не считается: возвращаться будем
      // историей, а не по строке сайдбара (её у /epitaxy нет).
      const prevId = prev === NEW_WINDOW_HOME_PATH ? "" : newWindowSegment(prev);
      const lengthBefore = history.length;
      const store = await newWindowFindStore(token);
      if (!newWindowLive(token)) return false;
      if (!store) {
        newWindowMark({ state: "no-store" });
        newWindowNote(NEW_WINDOW_NOTE_FAIL);
        return false;
      }

      // 1. Новый чат открывает Swift штатным ⌘N — ждём домашний экран.
      newWindowMark({ step: "home" });
      let home = await newWindowWait(() => (newWindowAtHome() ? true : null), NEW_WINDOW_HOME_MS, token);
      if (!newWindowLive(token)) return false;
      if (!home) {
        // Последний запасной путь: pushState портит history.state роутера, но
        // без него команда просто умерла бы. Пометка pushed — для гейта.
        let pushed = false;
        try {
          history.pushState({}, "", NEW_WINDOW_HOME_PATH);
          window.dispatchEvent(new PopStateEvent("popstate", { state: history.state }));
          pushed = true;
        } catch {}
        newWindowMark({ pushed });
        home = pushed ? await newWindowWait(() => (newWindowAtHome() ? true : null), NEW_WINDOW_HOME_MS, token) : null;
        if (!newWindowLive(token)) return false;
        if (!home) {
          newWindowMark({ state: "no-home" });
          newWindowNote(NEW_WINDOW_NOTE_FAIL);
          return false;
        }
      }

      // 2. Композер обязан быть ПУСТ, иначе «Привет» приклеится к недописанной
      // мысли Элвиса и уедет в модель. Узел берём прямым селектором: в
      // state.editor/findEditor лежит кэш поля прошлого чата.
      newWindowMark({ step: "draft" });
      const editor = document.querySelector(NEW_WINDOW_INPUT_SELECTOR);
      if (location.pathname !== NEW_WINDOW_HOME_PATH || !editor?.isConnected || editorText(editor) !== "") {
        newWindowMark({ state: "draft" });
        newWindowNote(NEW_WINDOW_NOTE_DRAFT);
        await newWindowBack(prev, prevId, lengthBefore, token);
        return false;
      }

      // 2б. Папка проекта (WF16). Шаг стоит ДО первого сообщения нарочно:
      // отправить «Привет» и только потом обнаружить, что папка не та, уже
      // нельзя — в этой сессии работает авто-Allow, и агент стартовал бы в
      // чужом проекте. Не вышло — сообщение НЕ отправляем, чат НЕ создаём,
      // плашка, главное окно назад (решение 1 плана WF16).
      if (folder) {
        newWindowMark({ step: "folder" });
        const picked = await newWindowPickFolder(folder, token);
        if (!newWindowLive(token)) return false;
        if (picked !== "ok") {
          newWindowMark({ state: picked });
          newWindowNote(NEW_WINDOW_NOTE_FOLDER_PICK);
          await newWindowBack(prev, prevId, lengthBefore, token);
          return false;
        }
      }

      // 3. Первое сообщение. Узел поля перечитываем: смена папки перерисовывает
      // домашний экран, и запомненный на шаге 2 узел мог отвалиться.
      newWindowMark({ step: "insert" });
      const input = document.querySelector(NEW_WINDOW_INPUT_SELECTOR) ?? editor;
      try { window.focus(); } catch {}
      try { window.electronWindowControl?.focus?.(); } catch {}
      if (!input?.isConnected || !insertIntoEditor(input, text, false)) {
        newWindowMark({ state: "no-insert" });
        newWindowNote(NEW_WINDOW_NOTE_FAIL);
        await newWindowBack(prev, prevId, lengthBefore, token);
        return false;
      }

      // 4. Отправка. Кнопку ждём живой: пока не выбраны папка и модель, она
      // disabled, и клик вслепую ничего не даст.
      newWindowMark({ step: "send" });
      const send = await newWindowWait(
        () => document.querySelector(`${NEW_WINDOW_SEND_SELECTOR}:not([disabled])`), NEW_WINDOW_SEND_MS, token);
      if (!newWindowLive(token)) return false;
      if (send) { try { send.click(); } catch {} }
      else {
        // Кнопка так и не ожила — пробуем Enter в самом редакторе.
        try {
          input.dispatchEvent(new KeyboardEvent("keydown", {
            key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true, cancelable: true,
          }));
        } catch {}
      }

      // 5. Сессия рождается на первом сообщении: ждём /epitaxy/local_<uuid>.
      // Прежний чат за новую сессию не принимаем: мигни роутер старым адресом —
      // и в отдельное окно уехал бы не тот разговор.
      newWindowMark({ step: "session" });
      const id = await newWindowWait(() => {
        const found = newWindowSessionId();
        return found && found !== prevId ? found : null;
      }, NEW_WINDOW_SESSION_MS, token);
      if (!newWindowLive(token)) return false;
      if (!id) {
        // Кнопка не ожила — почти всегда это несуществующая последняя папка.
        const reason = send ? "no-send" : "no-folder";
        newWindowMark({ state: reason });
        newWindowNote(send ? NEW_WINDOW_NOTE_FAIL : NEW_WINDOW_NOTE_FOLDER);
        return false;
      }
      created = true;

      // 6. Строка сайдбара: по ней видно, что сессия действительно создана, и
      // из неё же берём имя для окна.
      newWindowMark({ step: "row", id });
      const row = await newWindowWait(() => newWindowRow(id), NEW_WINDOW_ROW_MS, token);
      if (!newWindowLive(token)) return false;
      if (!row) await newWindowSleep(NEW_WINDOW_ROW_GRACE_MS);
      if (!newWindowLive(token)) return false;

      // 6а. Имя чата (WF16). Пока чат не переименован, его заголовок — это текст
      // первого сообщения, и приложение позже перепишет его своей сводкой; после
      // переименования заголовок становится «пользовательским» и больше не
      // меняется — а значит, не съедет и цвет окна, привязанный к заголовку.
      // Отказ переименования цепочку не роняет: чат создан и назван правильно.
      if (name) {
        newWindowMark({ step: "rename" });
        const renamed = await newWindowRename(newWindowRow(id) ?? row, name, token);
        if (!newWindowLive(token)) return false;
        newWindowMark({ rename: renamed });
        if (!renamed) { soft = "no-rename"; newWindowMark({ state: soft }); }
      }

      // 6б. Сверка заголовка (критик WF16, В3). В ключ темы и в openPopout
      // обязана уйти ОДНА И ТА ЖЕ строка — та, что реально показывает сайдбар:
      // заголовок попапа приходит из сессии, а красится окно по нему
      // (applyChatEntry). Ждём до двух секунд, пока имя доедет до строки, и
      // дальше берём фактическое.
      if (name) {
        newWindowMark({ step: "title" });
        await newWindowWait(
          () => (newWindowRowTitle(newWindowRow(id)) === name ? true : null), NEW_WINDOW_TITLE_MS, token);
        if (!newWindowLive(token)) return false;
      }
      // Ключ темы — ТОЛЬКО из строки сайдбара: без неё (сайдбар свёрнут) document.title
      // главного окна может ещё быть заголовком чата Элвиса, и слои легли бы под него
      // (verify WF16, находка 1). Для openPopout заголовок окна как запасной годится.
      const rowTitle = newWindowRowTitle(newWindowRow(id) ?? row);
      const title = rowTitle || windowTitle();
      newWindowMark({ title: title || null });

      // 6в. Цвет и размер нового окна — ДО openPopout: попап читает ту же карту
      // (localStorage у окон Claude общий), и запись под ключом его чата успевает
      // лечь раньше, чем окно откроется, — оно рисуется уже покрашенным.
      // Пишем РОВНО одну запись, чата. Ни writeLayers, ни storeSessionLayers, ни
      // applyLayer тут звать нельзя: команду исполняет ГЛАВНОЕ окно, и writeKeys()
      // добавил бы к ключу чата ещё и `main` с сессией — один клик по «Новое окно
      // ▸ Dictatorik» перекрасил бы окно Элвиса в чужой цвет (критик WF16, Б3).
      // Слои на экран здесь тоже не применяются: они не про это окно.
      if (Object.keys(layers).length) {
        if (!rowTitle || !title || THEME_TITLE_STUBS.has(title.toLowerCase())) {
          // Заголовок-заглушка ключом чата не бывает: запись под ней досталась бы
          // каждому безымянному чату разом. Лучше без цвета, чем такой ценой.
          soft = "no-title";
          newWindowMark({ state: soft, layers: "no-title" });
        } else {
          try {
            const map = readThemeMap();
            setMapLayers(map, `${THEME_CHAT_PREFIX}${title}`, layers);
            writeThemeMap(map);
            newWindowMark({ layers: Object.keys(layers) });
          } catch {
            // Квота или битая карта — не повод ронять окно, как и no-rename.
            newWindowMark({ layers: "failed" });
          }
        }
      }

      // 6г. Перенос «Обкэшить» (WF37): запись донора ждала адресата — теперь он
      // есть. Штамп стоит ДО openPopout, чтобы новое окно нашло готовую запись
      // уже на инжекте, и только при transfer: обычное «Новое окно» чужой
      // перенос не трогает вовсе.
      if (transfer) newWindowMark({ stamped: cashoutStamp(id, title) });

      // 7. Отдельное окно.
      newWindowMark({ step: "popout" });
      try { newWindowOpenPopout(store, id, title, x, y); }
      catch (error) {
        newWindowMark({ state: "popout-failed", error: newWindowError(error) });
        newWindowNote(NEW_WINDOW_NOTE_CREATED);
        return false;
      }

      // 8. Главное окно — обратно на прежний разговор (П1: openPopout само его
      // никуда не уводит).
      newWindowMark({ state: soft ?? "ok", step: "back" });
      await newWindowBack(prev, prevId, lengthBefore, token);
      return true;
    } catch (error) {
      newWindowMark({ state: "error", error: newWindowError(error) });
      newWindowNote(created ? NEW_WINDOW_NOTE_CREATED : NEW_WINDOW_NOTE_FAIL);
      return false;
    } finally {
      clearTimeout(guard);
      newWindowTimers.delete(guard);
      if (token === newWindowToken) newWindowMark({ busy: false });
    }
  };

  // Команда «В отдельное окно», контракт WF13: {id, action:"popout-window", at,
  // scope:"window", title, x, y}. Тот же стор и тот же openPopout, только по уже
  // открытому чату — мгновенно и без сообщения.
  //
  // Отказы у неё видимые, все три (WF19): нет чата (домашний экран /epitaxy —
  // в адресе нет local_<uuid>), окно уже попап и стор не нашёлся. Молчащий пункт
  // читается как сломанный — тот же довод, что у плашек «Нового окна».
  const runPopoutCommand = async detail => {
    // Отвечаем только на страницах Claude: в оболочке (file://…/main_window), на
    // логине и в браузерной панели плашке делать нечего.
    if (!themable || !addressed(detail)) return false;
    // Координаты — числа, а не строки (разбор у runNewWindowCommand).
    const x = detail?.x;
    const y = detail?.y;
    if (detail?.scope !== "window" || !Number.isFinite(x) || !Number.isFinite(y)) {
      newWindowMark({ state: "bad-command", step: null });
      return false;
    }
    // Окно «Open in new window» (about:blank) — это и есть отдельное окно: чат
    // в нём уже вынесен, второго openPopout у него нет (стор попапов живёт на
    // claude.ai). Приложение адресует пункт главному окну, но нажимают его и
    // здесь — отвечаем плашкой, а не молчанием.
    if (!isMainWindow()) {
      newWindowMark({ state: "already", step: "popout", id: null, runs: newWindowRuns() });
      newWindowNote(NEW_WINDOW_NOTE_ALREADY);
      return false;
    }
    const token = newWindowToken;
    const id = newWindowSessionId();
    // Запись в state.newWindow одна на оба пункта: она про ПОСЛЕДНИЙ запуск
    // раздела. Признак занятости чужого прогона мы не трогаем — вынести
    // текущий чат можно и пока «Новое окно» ещё ждёт свою сессию.
    newWindowMark({ state: "run", step: "popout", id: id || null, runs: newWindowRuns() });
    if (!id) {
      newWindowMark({ state: "no-chat" });
      newWindowNote(NEW_WINDOW_NOTE_CHAT);
      return false;
    }
    const store = await newWindowFindStore(token);
    if (!state.alive) return false;
    if (!store) {
      newWindowMark({ state: "no-store" });
      newWindowNote(NEW_WINDOW_NOTE_POPOUT);
      return false;
    }
    try { newWindowOpenPopout(store, id, newWindowRowTitle(newWindowRow(id)) || windowTitle(), x, y); }
    catch (error) {
      newWindowMark({ state: "popout-failed", error: newWindowError(error) });
      newWindowNote(NEW_WINDOW_NOTE_POPOUT);
      return false;
    }
    newWindowMark({ state: "ok" });
    return true;
  };
  // Обе команды асинхронные: отказ промиса не должен всплывать в консоль страницы.
  const newWindowStart = (run, detail) => { try { run(detail).catch(() => {}); } catch {} };

  // ---- 12в. Кто этот чат ---------------------------------------------------
  // Приложение красит окно цветом ПРОЕКТА, а проект берёт из папки чата. До
  // WF29 окно опознавалось заголовком — и три попапа из четырёх у Элвиса не
  // опознавались вовсе: заголовок попапа это снимок имени чата на момент выноса
  // в окно, а чаты с тех пор переименованы (задача #5455; setPopoutTitle Claude
  // при переименовании не зовёт). Отсюда правило: чат окна называет САМА
  // страница, а приложение только спрашивает.
  //
  // Кто как узнаёт свой чат:
  //   главное окно (claude.ai) — хвост location.pathname (/epitaxy/local_<id>);
  //   попап (about:blank, своего адреса у него нет) — спрашивает окно-родителя:
  //     window.opener.__myclaude.popoutChat(<заголовок>). У claude.ai есть стор
  //     с картой popoutWindows: <id чата> → {title,…}, где title — ровно то, что
  //     стоит в document.title попапа. Стор ищется поведенчески, тот же, что у
  //     «Нового окна» (раздел 12б), и тем же кэшем.
  //   чужая страница (data:, file:, localhost) — молчит первой же строкой:
  //     лоадер шлёт probe.js во ВСЕ страницы, а их у Claude больше сорока.
  //
  // Спрашивает приложение через probe.js (канал лоадера): скрипт зовёт
  // window.__myclaude.chats({scan, nonce}), ответ ложится в probe-result.json.
  // Своих таймеров, подписок и наблюдателей раздел не заводит НИ ОДНОГО —
  // лоадер перечитывает файл по mtime и гоняет его в том же окне снова, и
  // каждая подписка здесь стала бы зомби (раздел 0).
  // Карта попапов свежа полминуты: чаще круга probe она всё равно не нужна, а
  // скан исполняет чужие модули (раздел 12б).
  const CHATS_MAP_TTL_MS = 30000;
  // Активную строку сайдбара кладём отдельным полем — ТОЛЬКО для сверки на
  // гейте: data-selected чужой атрибут claude.ai, «focused» может значить не
  // «показан», и поведение на нём не строится (план WF29, решение 5).
  const CHAT_ROW_SELECTOR = '[data-selected="focused"][data-row-key], [data-selected="focused"] [data-row-key]';

  // Карта попапов и её возраст живут в замыкании: спрашиваем стор только по
  // просьбе приложения, между кругами отдаём кэш. store — чем кончился
  // последний вызов chats(), его же показывает status().chat.
  const chatsState = { map: null, at: 0, store: null };
  // Идущий скан: на него садятся все, кто попросил, пока он не кончился.
  let chatsScanInFlight = null;
  // Идущий поиск стора папки (WF37, см. chatsFolder): второго не заводим.
  let chatsFolderScanInFlight = null;
  track(() => { chatsFolderScanInFlight = null; });
  // Неудача поиска запоминается: повтор не чаще раза в CHATS_FOLDER_RETRY_MS —
  // иначе после релиза Claude, сменившего форму стора, скан всех адресов шёл бы
  // каждый круг probe, раз в 4 с (проверка WF37, находка 2).
  const CHATS_FOLDER_RETRY_MS = 60000;
  let chatsFolderScanAt = 0;
  track(() => { chatsFolderScanAt = 0; });

  const chatKind = () => (!themable ? "other" : isMainWindow() ? "main" : "popout");
  // Путь чужой страницы наружу не отдаём: у артефакта это data:-адрес целиком,
  // а такие уже раздули probe-result.json до 3,9 МБ (разведка плана, п. 1).
  const chatPath = () => (themable ? location.pathname : "");
  const chatRowId = () => {
    if (!isMainWindow()) return null;
    try {
      const node = document.querySelector(CHAT_ROW_SELECTOR);
      // Ключи строк — code:local_<uuid> / chat:<uuid>, нам нужен хвост.
      const id = String(node?.getAttribute?.("data-row-key") ?? "").split(":").pop() ?? "";
      return id.startsWith("local_") ? id : null;
    } catch { return null; }
  };

  // Ответ родителя переживает перезапуск инжекта: лоадер перечитывает файл по
  // mtime (каждый гейт после cp, каждое обновление приложения), и замыкание при
  // этом умирает. Команда с полем chat приходит событием и ждать промиса не
  // может — с пустым кэшем попап отверг бы её, а отпечаток в приложении был бы
  // уже записан, и окно осталось бы некрашеным. sessionStorage у попапа свой на
  // окно (about:blank унаследовал origin claude.ai) — так же живут
  // myclaude-theme-v1 и myclaude-live-phase-v1. Запись годна, пока заголовок
  // окна равен сохранённому: сменился — спросим родителя заново.
  // Объявление, а не стрелка: readChatId зовёт chatIdKey (раздел 2а) на инжекте,
  // то есть ВЫШЕ этой строки — `const` там был бы ещё в TDZ (WF35).
  function readChatId() {
    try {
      const raw = sessionStorage.getItem(CHAT_ID_KEY);
      if (raw == null) return null;
      const record = JSON.parse(raw);
      const id = typeof record?.id === "string" ? record.id : "";
      const title = typeof record?.title === "string" ? record.title : "";
      if (!id.startsWith("local_") || title !== windowTitle()) return null;
      return id;
    } catch { return null; }
  }
  const writeChatId = id => {
    try { sessionStorage.setItem(CHAT_ID_KEY, JSON.stringify({ id, title: windowTitle() })); } catch {}
  };

  // Синхронный ответ «какой чат в этом окне» — им пользуются addressed() и ключ
  // темы chatIdKey (раздел 2а). Объявление, а не стрелка: chatIdKey зовёт его на
  // инжекте, а инжект проходит раздел 2а раньше этой строки (WF35).
  function myChatId() {
    if (!themable) return null;
    if (isMainWindow()) return newWindowSessionId() || null;
    return readChatId();
  }

  // Карта попапов из стора: [{id, title}]. null — стор ответить не смог (упал
  // или отдал не Map); пустой список — попапов нет, и это тоже ответ.
  const chatsMap = store => {
    try {
      const value = store?.getState?.();
      const map = value?.popoutWindows;
      if (!(map instanceof Map)) return null;
      const out = [];
      for (const [id, record] of map) {
        const key = typeof id === "string" ? id : "";
        if (!key) continue;
        out.push({ id: key, title: String(record?.title ?? "").trim() });
      }
      return out;
    } catch { return null; }
  };
  const chatsNeedScan = () => !chatsState.map || Date.now() - chatsState.at > CHATS_MAP_TTL_MS;
  // Одновременные просьбы (четыре попапа спросили родителя разом) складываются
  // в ОДИН скан: промис держится в замыкании, остальные ждут его. Токен берём
  // ТЕКУЩИЙ и не увеличиваем — начался прогон «Нового окна», скан бросит работу
  // сам, и мы честно скажем "busy", оставив прежнюю карту.
  const chatsScan = () => {
    if (chatsScanInFlight) return chatsScanInFlight;
    const token = newWindowToken;
    const run = (async () => {
      let store = null;
      try { store = await newWindowFindStore(token); } catch { store = null; }
      if (!newWindowLive(token)) return "busy";
      if (!store) return "none";
      const map = chatsMap(store);
      if (!map) return "none";
      chatsState.map = map;
      chatsState.at = Date.now();
      return "ok";
    })();
    chatsScanInFlight = run.then(
      result => { chatsScanInFlight = null; return result; },
      () => { chatsScanInFlight = null; return "none"; },
    );
    return chatsScanInFlight;
  };

  // Ответ попапу: id чата с ТАКИМ заголовком. Ноль совпадений или два и больше
  // — null: лучше «не определён», чем чужой проект. Заглушки («Claude», «New
  // chat») в сопоставлении не участвуют вовсе — их носят разные чаты во всех
  // окнах разом.
  const popoutChat = async (title, opts) => {
    try {
      const want = typeof title === "string" ? title.trim() : "";
      if (!want || THEME_TITLE_STUBS.has(want.toLowerCase())) return null;
      // Карта попапов есть только у главного окна; спрашивать попап незачем.
      if (!isMainWindow()) return null;
      if (opts?.scan === true && chatsNeedScan()) await chatsScan();
      const hits = (chatsState.map ?? []).filter(item => item.title === want);
      return hits.length === 1 ? hits[0].id : null;
    } catch { return null; }
  };

  // Попап спрашивает родителя. Кэш — раньше вопроса: он и дешевле, и переживает
  // перезапуск инжекта. "ok" значит «канал сработал», даже если id не нашёлся
  // (это и есть «не определён», приложение такое окно не красит вовсе); "none"
  // — спросить было некого, и приложение падает на старый путь по заголовку.
  const chatsAsk = async scan => {
    const title = windowTitle();
    if (!title || THEME_TITLE_STUBS.has(title.toLowerCase())) return { id: null, store: "none" };
    const cached = readChatId();
    if (cached) return { id: cached, store: "cache" };
    try {
      const parent = window.opener;
      const ask = parent?.__myclaude?.popoutChat;
      if (typeof ask !== "function") return { id: null, store: "none" };
      const answered = await ask.call(parent.__myclaude, title, { scan: scan === true });
      const id = typeof answered === "string" && answered.startsWith("local_") ? answered : null;
      if (id) writeChatId(id);
      return { id, store: "ok" };
    } catch { return { id: null, store: "none" }; }
  };

  // Карта тем в ответ probe (WF35): по ней приложение держит на диске копию
  // хранилища окон и возвращает её после переустановки Claude. Отдаёт её ТОЛЬКО
  // главное окно: лоадер гоняет probe.js во ВСЕХ страницах (их у Claude больше
  // сорока), а карта на origin одна — иначе каждая страница вернула бы её КОПИЮ
  // (ответ и без того весит мегабайты), а артефакт на чужом origin вернул бы
  // ПУСТУЮ карту и подсунул бы приложению ложное «Элвис снял всё сам».
  const chatsThemes = () => (isMainWindow() ? readThemeMap() : null);

  // Папка домашнего экрана (WF37, #5576). Пока чат не открыт, сессии на диске
  // нет, и приложению папку взять неоткуда — окно оставалось некрашеным, хотя
  // чип над полем ввода проект уже показывает. Этот выбор (папка БУДУЩЕГО чата)
  // живёт в сторе claude.ai, и его же ставит цепочка «Нового окна»
  // (newWindowFolderStore, раздел 12б).
  // Отдаёт папку ТОЛЬКО главное окно и ТОЛЬКО на домашнем экране: в открытом
  // чате правду говорит индекс сессий (там выбор чипа не значит ничего), а у
  // попапа своего выбора нет вовсе.
  // Стор ещё не найден — ищем его В ФОНЕ (один скан на все круги, чужие модули
  // исполняются по разу) и честно отвечаем null: скан идёт около секунды, а
  // ответ probe ждать не может. Поле scan команды тут ни при чём — оно про
  // карту попапов; фоновый поиск заводит любой круг probe, а status() — никогда
  // (mayScan = false): он обещан синхронным слепком из кэша.
  const chatsFolder = mayScan => {
    try {
      if (!isMainWindow() || !newWindowAtHome()) return null;
      // Идёт «Новое окно»: чип показывает папку БУДУЩЕГО чата, а не выбор Элвиса, —
      // покраска главного окна по ней мигала бы чужим цветом (проверка WF37, находка 3).
      if (state.newWindow?.busy === true) return null;
      if (newWindowFolderStoreOk(newWindowFolderStore)) return newWindowFolderNow(newWindowFolderStore) || null;
      if (mayScan && !chatsFolderScanInFlight && Date.now() - chatsFolderScanAt >= CHATS_FOLDER_RETRY_MS) {
        // Токен берём ТЕКУЩИЙ и не увеличиваем: начался прогон «Нового окна» —
        // скан бросит работу сам (newWindowLive).
        const token = newWindowToken;
        chatsFolderScanAt = Date.now();
        const done = () => { chatsFolderScanInFlight = null; };
        chatsFolderScanInFlight = Promise.resolve(newWindowFindFolderStore(token)).then(done, done);
      }
      return null;
    } catch { return null; }
  };

  // Ответ probe.js. Контракт (план WF29, решение 4; WF37 дописал folder после
  // store) — побайтно:
  //   {v, nonce, kind, self, path, row, title, popouts:[{id,title}], store, folder, at}
  // WF35 дописывает в ХВОСТ необязательное themes (карта тем главного окна):
  // контракт выше остаётся побайтно прежним, а «поля нет» приложение отличает
  // от «карта пуста».
  // store: "ok" — спросили стор/родителя, "cache" — из карты в замыкании,
  // "busy" — идёт «Новое окно», "none" — спросить не вышло, "skip" — не наша
  // страница. Функция НИКОГДА не бросает: probe ждёт объект, а не исключение.
  const chats = async opts => {
    const nonce = typeof opts?.nonce === "string" ? opts.nonce : null;
    const scan = opts?.scan === true;
    const answer = (kind, self, store, popouts) => {
      const themes = chatsThemes();
      return {
        v: 1,
        nonce,
        kind,
        self: self ?? null,
        path: chatPath(),
        row: chatRowId(),
        title: windowTitle(),
        popouts: popouts ?? [],
        store,
        folder: chatsFolder(true),
        at: Date.now(),
        ...(themes ? { themes } : {}),
      };
    };
    try {
      const kind = chatKind();
      if (kind === "other") {
        chatsState.store = "skip";
        return answer(kind, null, "skip");
      }
      if (kind === "popout") {
        const found = await chatsAsk(scan);
        chatsState.store = found.store;
        return answer(kind, found.id, found.store);
      }
      // Главное окно: свой id берётся из пути и вопроса не требует, а скан нужен
      // ради карты попапов — и только когда карты нет или она старше TTL.
      let store = chatsState.map ? "cache" : "none";
      if (scan && chatsNeedScan()) store = await chatsScan();
      chatsState.store = store;
      return answer(kind, myChatId(), store, (chatsState.map ?? []).map(item => ({ id: item.id, title: item.title })));
    } catch {
      chatsState.store = "none";
      return answer(chatKind(), null, "none");
    }
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
    // «Живые цвета» (раздел 2в) — по тем же доводам, что тема: команда адресована
    // всем окнам разом (scope:"all"), поля ввода ей не нужно, а своё окно
    // страница отбирает сама. И до отмены примерки: гасить её здесь незачем.
    if (action === "live-colors") { try { runLiveCommand(detail); } catch {} return; }
    // «Возврат тем» (scope:"all", WF35) — по тем же доводам и ДО отмены примерки:
    // команда приезжает сама, по часам приложения, а не из меню, и гасить ею
    // подменю под рукой у Элвиса нельзя.
    if (action === "themes-restore") { try { runThemesRestoreCommand(detail); } catch {} return; }
    // Любая другая команда из меню закрывает примерку: меню ушло, выбора темы не было.
    if (themeState.previewing) {
      try { restoreTheme(true); themeState.previewing = false; themeState.previewLayers = []; } catch {}
    }
    // «Новое окно» и «В отдельное окно» — ДО проверки поля ввода: композер
    // страница дожидается сама (после ⌘N он ещё не тот, что в state.editor), и
    // команда не должна умирать молча на окне без поля. Обе адресованы одному
    // главному окну — отбор внутри (isMainWindow + addressed).
    if (action === "new-window") { newWindowStart(runNewWindowCommand, detail); return; }
    if (action === "popout-window") { newWindowStart(runPopoutCommand, detail); return; }
    if (!state.editor?.isConnected) return;
    // «Свернуть»/«Развернуть» — тоже на все окна (ElvisOS: «убирает поле ввода во
    // всех окнах»; слово Элвиса 03.09 13:30). Только «Обкэшить» адресована окну в фокусе.
    if (action === "collapse") { setStage(STAGE_COLLAPSED); return; }
    if (action === "expand") { setStage(STAGE_NORMAL); return; }
    // «Обкэшить» адресована одному окну — с WF37 через общий addressed()
    // (match → chat → заголовок/фокус, #5535), а не своей проверкой заголовка.
    // Заголовок один на два окна разом: главное окно с открытым названным чатом
    // и безымянный попап носят его одинаково, и команда уходила веером им обоим
    // (критик плана, блокер 3).
    if (action === "cashout") {
      if (addressed(detail)) runCashout();
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

  // Тик вынесен в функцию: после отказа от наблюдения интервал снимают, а при
  // возврате заводят заново — тем же телом.
  const heartbeatTick = () => {
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
  };
  let heartbeat = setInterval(heartbeatTick, HEARTBEAT_MS);
  track(() => clearInterval(heartbeat));

  // Инжект попадает и в оболочку file://…/main_window, и на страницы логина —
  // там поля ввода нет и не будет. Через минуту ожидания перестаём смотреть за
  // документом, если страница явно не claude.ai и на ней нет ни одной приметы
  // интерфейса Claude (последняя проверка — сверх плана: окна «Open in new
  // window» живут на about:blank, и терять в них полоску из-за одного лишь URL
  // было бы обиднее, чем лишний наблюдатель на пустой странице).
  // Примета интерфейса Claude: по ней страница признаётся своей — и когда мы от
  // неё отказываемся, и когда возвращаемся.
  const CLAUDE_MARK_SELECTOR = ".ProseMirror,.epitaxy-prompt,.epitaxy-titlebar,.epitaxy-composer-width";
  let reviveTimer = 0;
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
    // Отказ не окончательный. Окно «Open in new window» рождается пустым
    // about:blank, а чат в него въезжает позже; тяжёлый чат в фоновом окне
    // не успевал за GIVE_UP_MS, и страница оставалась мёртвой навсегда — без
    // ручки и без полоски прогресса, хотя поле ввода в ней уже стояло (окно
    // «Bro Flow продолжение», 05.09). Наблюдателей обратно не заводим: остаётся
    // самая дешёвая сторожевая проверка — один querySelector раз в REVIVE_MS.
    if (!reviveTimer) reviveTimer = setInterval(() => {
      if (!state.alive) return;
      if (!document.querySelector(CLAUDE_MARK_SELECTOR)) return;
      resumeWatching();
    }, REVIVE_MS);
  };
  // Разметка Claude всё-таки приехала: поднимаем ровно то, что снял stopWatching.
  const resumeWatching = () => {
    if (reviveTimer) { clearInterval(reviveTimer); reviveTimer = 0; }
    if (!state.alive || state.watching) return;
    state.watching = true;
    observer.observe(document.documentElement, { childList: true, subtree: true });
    heartbeat = setInterval(heartbeatTick, HEARTBEAT_MS);
    if (!progressState.pulse) {
      progressState.pulse = setInterval(() => { try { progressRefresh(); } catch {} }, PROGRESS_IDLE_MS);
    }
    watchTime();
    scheduleShortTime();
    scheduleLayout();
    try { progressSchedule(); } catch {}
  };
  track(() => { if (reviveTimer) { clearInterval(reviveTimer); reviveTimer = 0; } });
  state.giveUpTimer = setTimeout(() => {
    state.giveUpTimer = 0;
    if (state.editorFound || !state.alive) return;
    if (location.href.startsWith("https://claude.ai")) return;
    if (document.querySelector(CLAUDE_MARK_SELECTOR)) return;
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
    // Раздел 12в. chats() зовёт probe.js приложения (ответ — промис), а
    // popoutChat() зовёт ПОПАП у своего родителя через window.opener.
    chats,
    popoutChat,
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
      // «Обкэшить»: есть ли запись переноса, кому она адресована (id чата или
      // «ждёт адресата»), под каким заголовком её ждут и когда штамповали (WF37).
      cashout: cashoutState(),
      // Полоса прогресса воркфлоу (раздел 2б): что вычитано из строки состояния
      // последнего ответа и почему полосы нет (или почему она пустым контуром). total — доля всего
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
        // Карточка сегмента: какой сегмент открыт кликом (с нуля), открыта ли
        // она, каким вариантом макета нарисована и дышит ли значок состояния.
        tip: {
          segment: progressState.tipSegment, open: progressState.tipOpen,
          variant: PROGRESS_CARD_VARIANT, pulse: progressState.cardPulse,
          card: progressState.tipOpen ? (progressState.cardText || null) : null,
        },
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
      // «Новое окно» и «В отдельное окно» (раздел 12б): чем кончился последний
      // запуск, на каком он шаге, какая сессия уехала в окно, занята ли кнопка
      // и как вернулось главное окно.
      newWindow: state.newWindow ? { ...state.newWindow } : null,
      // Кто этот чат (раздел 12в) — синхронный слепок, ТОЛЬКО из кэша: скана
      // status() не запускает и промиса не отдаёт. self — id чата этой
      // страницы, popouts — сколько записей в карте попапов, store — чем
      // кончился последний chats(), at — когда снята карта.
      chat: {
        kind: chatKind(),
        self: myChatId(),
        path: chatPath(),
        row: chatRowId(),
        popouts: chatsState.map ? chatsState.map.length : 0,
        store: chatsState.store,
        // Папка чипа домашнего экрана (WF37) — только из кэша: скана status()
        // не запускает, стор ещё не найден — null.
        folder: chatsFolder(false),
        at: chatsState.at || null,
      },
      // Возврат тем (WF35): когда приезжала команда themes-restore, сколько
      // ключей приняли, сколько слоёв долили и красилось ли окно (примерка и
      // живые цвета красить запрещают).
      restore: {
        at: restoreState.at || null,
        keys: restoreState.keys,
        merged: restoreState.merged,
        painted: restoreState.painted,
      },
      // Ключ чата, под которым окно хранит тему (раздел 2а): у главного окна это
      // id разговора (`id:local_…`), а пока id неизвестен — его имя.
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
      // Размер текста сообщений: половинки независимы, любой может не быть.
      size: {
        answer: themeState.size?.answer ?? null,
        question: themeState.size?.question ?? null,
        source: themeState.sizeSource,
      },
      // Неоновая рамка окна: включена ли и откуда взялась.
      frame: { on: themeState.frame === true, source: themeState.frameSource },
      // Живые цвета (раздел 2в): крутится ли круг, в каком режиме и с какой
      // скоростью, где на круге стоит окно (phase — его защёлкнутый сдвиг,
      // hue — тон прямо сейчас), из скольких точек кольцо, сколько раз окно
      // перекрашено и откуда взялся крутёж — из команды или из памяти окон.
      live: {
        on: liveState.on,
        mode: liveState.mode,
        period: liveState.period,
        light: liveState.on ? liveState.useLight : null,
        phase: Math.round(liveState.phase * 10) / 10,
        hue: liveState.hue == null ? null : Math.round(liveState.hue * 10) / 10,
        ring: liveState.ring?.dark?.length ?? 0,
        paints: liveState.paints,
        source: liveState.source,
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

  // Тестовый люк: в бою этой функции нет, объект даже не собирается.
  // Ставит её только tests/load.mjs, чтобы дотянуться до чистых функций замыкания.
  // Глушителя ошибок здесь нет намеренно: переименовали функцию — люк обязан кричать, а не отдавать тестам undefined.
  if (typeof globalThis.__myclaudeTest === "function") globalThis.__myclaudeTest({ themeCss, epitaxyCss, fontCss, sizeCss,
    frameShadow, normalizeTheme, normalizeFont, normalizeSize, normalizeSizeCommand, normalizeHex, mixHex, hslTriple,
    codeCss, codePalette, contrastRatio, readableOn,
    chatKey, chatIdKey, chatTitleKey, chatEntry, migrateChatKey, sameSessionKey, restoreKeyOk, chatsThemes,
    sessionKey, themeKey, legacyKey, mapEntry, entryLayer, readThemeMap, writeThemeMap, liveRing, livePalette,
    parseProgressText, progressShares, progressFill, progressBlockAt, progressStages,
    statusLines, statusBlocks, statusLineNumber, statusFeedLines, statusKey, runWorkflowCommand, newWindowSegment,
    newWindowSessionId, newWindowAtHome, newWindowStoreOk, setModuleImporter, newWindowScanStores,
    readCashout, runCashout, tryPasteCashout, cashoutStamp, cashoutMine,
    chatKind, chatPath, chatRowId, myChatId, readChatId, writeChatId, chatsMap, chatsScan, chatsFolder,
    popoutChat, chats });

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
