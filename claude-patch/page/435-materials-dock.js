  // ---- 12п⁴. Панель материалов слева в окне Claude — PimpViewer «док» (#10644, WF277) ----
  // Слово Элвиса 22.10 22:16 (trelvis 10644): панель материалов «прямо в клауды, во внутрь» — слева внутри окна,
  // прямоугольная кнопка «PMP» рядом с кнопкой бокового меню; любая ссылка из чата (html, картинка, md, pdf,
  // ролик) открывается в панели, а не справа; открыл файл — панель открылась сама; панель тянется влево-вправо.
  //
  // CSP claude.ai не пускает в страницу iframe с localhost и file:, поэтому панель — окно PimpViewer в режиме
  // «док» поверх места, которое страница освобождает слева (контракт К-DOCK, docs/contracts/560-wf277-dock.md):
  //  - место — между боковой панелью Claude и чатом, под строкой «Show/Hide sidebar»: .dframe-pane-host получает
  //    padding-left (метка DOCK_ATTRIBUTE и переменная DOCK_VARIABLE на .dframe-root), на месте — своя подложка
  //    цвета темы (no-drag), справа от неё — рейка ширины, над ней — полоса перетаскивания окна (своя полоса
  //    раздела 2ж уходит: чат больше не под кнопками окна). Ширина — в точках экрана: DOCK_MIN_PT…, лента не ýже
  //    DOCK_FEED_MIN CSS px, двойной клик по рейке — DOCK_DEFAULT_PT; помнится в DOCK_WIDTH_KEY;
  //  - GET /dock на порт приложения: on=1 — место относительно окна в точках (CSS px × z, z = outerWidth /
  //    innerWidth), рамка окна (для поиска CGWindowID), vis, chat, seq (растёт и через переустановку страницы —
  //    от часов); шлётся при открытии, при смене места (тяга рейки — кадром) и сердцем DOCK_BEAT_MS (готово с
  //    DOCK_BEAT_READY_MS от прошлой отправки: таймер не ровно 2 с); on=0 (с рамкой окна — владельца Пимп узнаёт по
  //    окну) — закрыл человек и снятие экземпляра. Пока панель не нажата — probe=1 раз в DOCK_PROBE_MS узнаёт, жив
  //    ли PimpViewer (Пимп отвечает сам, в PimpViewer ничего не шлёт): кнопка стоит только в главном окне и только
  //    при viewer "up";
  //  - vis=0 — окно скрыто, выехала свёрнутая боковая панель, над местом меню, диалог Claude или свой слой;
  //  - нажата ли панель — DOCK_ON_KEY (общий у окон, как ширина боковой панели у Claude): ставит нажатие, стирает
  //    только закрытие человеком. Док у другого окна (owner "other") — не отказ: место здесь снято, нажатие
  //    помнится, кнопка переносит панель сюда;
  //  - файл из чата (fileClick, 12д¹) при живом PimpViewer — `click&dock=1` с местом (dockForFile), панель
  //    встаёт сама. Клик по фото в ленте — по-прежнему просмотр 12л;
  //  - размер (#10759, WF282, контракт К-DOCK-5 в 590-wf282-dock-size.md; слово Элвиса 23.10: «в пол-экрана и потом
  //    вообще во весь экран. Нажимаешь вот так — чик и чик… легко его было возвращать к исходному размеру»; «три кнопки
  //    размера… стандартный узенький»): три кнопки справа от «PMP», пока панель стоит. "narrow" — ширина рейки (как
  //    было), "half" — половина .dframe-pane-host, "full" — «панель + поле» (#11202, WF301; слово Элвиса 30.10:
  //    «отображается панель и поле ввода. Одновременно, то есть вот это по серединке убирается»): панель — всё место
  //    чата, кроме колонки справа DOCK_FEED_MIN (лента узко и поле ввода), но не уже половины. Нажатая «½» или
  //    «панель + поле» — обратно к узкой; тяга рейки и двойной щелчок по ней — тоже узкая. Помнится в DOCK_MODE_KEY.
  const DOCK_ATTRIBUTE = "data-myclaude-dock";
  const DOCK_VARIABLE = "--myclaude-dock-w";
  const DOCK_BG_VARIABLE = "--myclaude-dock-bg";
  const DOCK_LINE_VARIABLE = "--myclaude-dock-line";
  const DOCK_ON_KEY = "myclaude-dock-on-v1";
  const DOCK_WIDTH_KEY = "myclaude-dock-width-v1";
  const DOCK_MODE_KEY = "myclaude-dock-mode-v1";
  const DOCK_MODES = ["narrow", "half", "full"];
  const DOCK_MODE_TITLES = {
    narrow: "Панель материалов узкая (обычная)",
    half: "Панель материалов на пол-окна (ещё раз — узкая)",
    full: "Панель материалов и поле ввода справа (ещё раз — узкая)",
  };
  // Кнопка размера — квадрат высотой с «PMP»; значок — рамка окна с залитой долей панели.
  const DOCK_SIZE_WIDTH = 28;
  const DOCK_MIN_PT = 260;
  const DOCK_DEFAULT_PT = 420;
  const DOCK_FEED_MIN = 360;
  const DOCK_RAIL = 12;
  const DOCK_RAIL_PILL = 48;
  // Место — ниже строки «Show/Hide sidebar» на этот зазор; строки нет — от этой высоты.
  const DOCK_TOP_GAP = 6;
  const DOCK_TOP_FALLBACK = 44;
  // Кнопка — как «Show sidebar» (28 в высоту, скругление 8, тонкая рамка и подложка), но прямоугольная.
  // #11340 (слово Элвиса 31.10 04:00: «Назови не PIM, а файлы, пусть называется»): подпись «Файлы» — ~39 px при 11 px,
  // в 40 не влезала; 48 — по 4 px с боков.
  const DOCK_BUTTON_WIDTH = 48;
  const DOCK_BUTTON_GAP = 4;
  const DOCK_BEAT_MS = 2000;
  const DOCK_BEAT_READY_MS = 1700;
  const DOCK_PROBE_MS = 30000;
  // Короткий перерыв PimpViewer или Пимпа (установка, перезапуск) — кнопка и место остаются (#10722, Элвис 23.10 15:25:
  // «у меня куда-то пропала кнопка Pimp из Claude. Была ж только что здесь»): минуту после последнего «up» переспрашиваем
  // раз в 3 с; не вернулся за минуту или удалён («none») — кнопки нет, как без PimpViewer.
  const DOCK_GRACE_MS = 60000;
  const DOCK_RETRY_MS = 3000;
  const DOCK_WAIT_MS = 3000;
  // Смена места дорисовывается: Claude выдвигает боковую панель анимацией.
  const DOCK_SETTLE_MS = 350;
  // PimpViewer жив, но в док не встал столько ответов подряд — панель снимается с плашкой.
  const DOCK_REFUSALS = 3;
  const DOCK_SIDEBAR_HIDE = ["Hide sidebar", "Скрыть боковую панель"];
  // #11618: надпись на обоих языках перечислением через запятую, не uiAria: :is() стаб DOM тестов не понимает.
  const DOCK_SIDEBAR_BUTTON = ["Show sidebar", "Показать боковую панель", ...DOCK_SIDEBAR_HIDE].map(word => `[aria-label="${word}"]`).join(",");
  const DOCK_HOST_SELECTOR = ".dframe-root .dframe-pane-host";
  const DOCK_PEEK_SELECTOR = ".dframe-root[data-collapsed][data-hovering]";
  const DOCK_KEYS = ["x", "y", "w", "h", "wx", "wy", "ww", "wh"];
  // Строка «Файлы» над местом (#11654, К-DOCK-6a): bx — правый край кнопок размера + зазор, by и bh — кнопка «Файлы».
  const DOCK_BAR_KEYS = ["bx", "by", "bh"];
  const DOCK_BAR_GAP = 6;
  const DOCK_TITLE_OFF = "Панель материалов слева — PimpViewer";
  const DOCK_TITLE_ON = "Закрыть панель материалов";
  const DOCK_TITLE_HERE = "Панель материалов в другом окне — перенести сюда";
  const DOCK_NOTES = {
    down: "Панель материалов: PimpViewer не запущен",
    none: "Панель материалов: PimpViewer не установлен",
    silent: "Панель материалов недоступна: PMP не отвечает (порт 47615)",
    refused: "Панель материалов не встала: PimpViewer не нашёл окно Claude",
  };
  const dockStoredWidth = () => {
    try {
      const value = Number(localStorage.getItem(DOCK_WIDTH_KEY));
      return Number.isFinite(value) && value > 0 ? Math.round(value) : null;
    } catch { return null; }
  };
  const dockStoredMode = () => {
    try {
      const value = localStorage.getItem(DOCK_MODE_KEY);
      return DOCK_MODES.includes(value) ? value : "narrow";
    } catch { return "narrow"; }
  };
  const dockStoredOn = () => {
    try { return localStorage.getItem(DOCK_ON_KEY) === "1"; } catch { return false; }
  };
  // want — нажата (помнится); viewer/docked/owner — из последнего ответа /dock; place — последнее посланное место
  // (точки); sig — его подпись с vis; answered — seq последнего принятого ответа (старые ответы — мимо).
  const dockState = {
    want: dockStoredOn(), width: dockStoredWidth(), mode: dockStoredMode(), viewer: null, docked: false, owner: null, refusals: 0,
    seq: 0, answered: 0, sent: 0, answers: 0, opens: 0, last: null, error: null, pressing: false,
    place: null, sig: "", vis: null, shift: null, beatAt: -Infinity, probeAt: -Infinity, upAt: -Infinity,
    dragging: false, grip: null, frame: 0, relayout: false, later: 0, wait: 0, timer: 0, bg: "", look: "", paint: "",
    file: false,
  };
  // Размер на виду: панель от файла из чата (file, #11223) — узкая, запомненный размер ждёт кнопки «PMP».
  const dockMode = () => dockState.file ? "narrow" : dockState.mode;
  const dockNodes = (() => {
    for (const orphan of document.querySelectorAll(`#${DOCK_BUTTON_ID},#${DOCK_SIZES_ID},#${DOCK_PLACE_ID},#${DOCK_RAIL_ID},#${DOCK_DRAG_ID}`)) orphan.remove();
    const make = id => {
      const node = document.createElement("div");
      node.id = id;
      node.style.setProperty("display", "none");
      (document.body ?? document.documentElement).appendChild(node);
      track(() => node.remove());
      return node;
    };
    const button = make(DOCK_BUTTON_ID);
    button.setAttribute("role", "button");
    button.setAttribute("tabindex", "0");
    button.setAttribute("aria-pressed", "false");
    button.setAttribute("aria-label", DOCK_TITLE_OFF);
    button.title = DOCK_TITLE_OFF;
    const label = document.createElement("span");
    label.textContent = "Файлы";
    button.appendChild(label);
    const sizes = make(DOCK_SIZES_ID);
    sizes.setAttribute("role", "group");
    sizes.setAttribute("aria-label", "Размер панели материалов");
    const modes = {};
    for (const mode of DOCK_MODES) {
      const item = document.createElement("div");
      item.dataset.mode = mode;
      item.dataset.on = "false";
      item.setAttribute("role", "button");
      item.setAttribute("tabindex", "0");
      item.setAttribute("aria-pressed", "false");
      item.setAttribute("aria-label", DOCK_MODE_TITLES[mode]);
      item.title = DOCK_MODE_TITLES[mode];
      item.appendChild(document.createElement("span"));
      sizes.appendChild(item);
      modes[mode] = item;
    }
    const place = make(DOCK_PLACE_ID);
    place.setAttribute("aria-hidden", "true");
    const rail = make(DOCK_RAIL_ID);
    rail.setAttribute("aria-hidden", "true");
    rail.title = "Ширина панели материалов (двойной щелчок — обычная)";
    rail.appendChild(document.createElement("span"));
    const drag = make(DOCK_DRAG_ID);
    drag.setAttribute("aria-hidden", "true");
    return { button, sizes, modes, place, rail, drag };
  })();
  const dockShow = (node, display, box) => {
    if (!node.isConnected) { try { (document.body ?? document.documentElement).appendChild(node); } catch {} }
    if (node.style.getPropertyValue("display") !== display) node.style.setProperty("display", display);
    for (const [name, value] of Object.entries(box)) {
      const text = `${Math.round(value * 100) / 100}px`;
      if (node.style.getPropertyValue(name) !== text) node.style.setProperty(name, text);
    }
  };
  const dockHide = node => {
    if (node.style.getPropertyValue("display") !== "none") node.style.setProperty("display", "none");
  };
  const dockMain = () => state.alive && state.watching && chatKind() === "main";
  // Масштаб страницы: точки экрана на CSS px (рамка окна — в точках, страница — в CSS px).
  const dockZoom = () => {
    const z = Number(window.outerWidth) / Number(window.innerWidth);
    return Number.isFinite(z) && z >= 0.25 && z <= 8 ? z : 1;
  };
  const dockHost = () => {
    try { return document.querySelector(DOCK_HOST_SELECTOR); } catch { return null; }
  };
  const dockSidebarButton = () => {
    let nodes = [];
    try { nodes = [...document.querySelectorAll(DOCK_SIDEBAR_BUTTON)]; } catch { nodes = []; }
    for (const node of nodes) {
      const box = node.getBoundingClientRect();
      if (box.width > 0 && box.height > 0) return { node, box };
    }
    return null;
  };
  // Правый край ряда «Show/Hide sidebar»: последняя видимая кнопка или переключатель на его высоте (свёрнутая
  // панель — .df-collapsed-chrome, открытая — .df-titlebar с «назад», «вперёд» и Claude/Code).
  const dockRowEnd = found => {
    const row = found.node.closest?.(".df-collapsed-chrome,.df-titlebar") ?? found.node.parentElement;
    let end = found.box.right;
    let items = [];
    try { items = [...(row?.querySelectorAll?.('button,[role="button"],[role="radiogroup"]') ?? [])]; } catch { items = []; }
    for (const item of items) {
      const box = item.getBoundingClientRect();
      if (box.width > 0 && box.height > 0 && box.top < found.box.bottom && box.bottom > found.box.top) end = Math.max(end, box.right);
    }
    return end;
  };
  // Ширина панели в точках: просьба (тяга) или запомненная, в границах [DOCK_MIN_PT, лента ≥ DOCK_FEED_MIN].
  const dockWidthFor = (hostWidth, z, value = null) => {
    const max = (hostWidth - DOCK_RAIL - DOCK_FEED_MIN) * z;
    const want = Number.isFinite(value) ? value : dockState.width ?? DOCK_DEFAULT_PT;
    return Math.round(Math.max(DOCK_MIN_PT, Math.min(want, max)));
  };
  // Место панели (CSS px) и оно же в точках относительно окна (pt — для /dock). Рамка pane-host от отступа не
  // меняется: место одно и до, и после того, как чат подвинулся.
  const dockMeasure = () => {
    const host = dockHost();
    if (!host?.isConnected) return null;
    const box = host.getBoundingClientRect();
    if (!(box.width > 0 && box.height > 0)) return null;
    const z = dockZoom();
    const found = dockSidebarButton();
    const top = Math.max(box.top, found ? found.box.bottom + DOCK_TOP_GAP : DOCK_TOP_FALLBACK);
    const height = box.bottom - top;
    if (!(height > 0)) return null;
    // Размер (#10759): узкая — ширина рейки; «½» — половина чата; «панель + поле» (#11202) — всё место, кроме колонки
    // ленты DOCK_FEED_MIN справа, не уже половины (предел — прямо: Infinity в dockWidthFor дал бы запомненную ширину).
    // Открыл файл из чата (#11223): узкая и не шире половины чата, ключи ширины и размера не трогаем.
    const narrow = dockState.file ? Math.min(dockWidthFor(box.width, z), Math.floor(box.width * z / 2)) : dockWidthFor(box.width, z);
    const mode = dockMode();
    const half = Math.round(box.width * z / 2);
    const points = mode === "full" ? Math.max(half, Math.floor((box.width - DOCK_RAIL - DOCK_FEED_MIN) * z))
      : mode === "half" ? half : narrow;
    const width = points / z;
    let frame = null;
    try { frame = chatFrame("main"); } catch { frame = null; }
    const pt = { x: Math.round(box.left * z), y: Math.round(top * z), w: points, h: Math.round(height * z) };
    if (frame) Object.assign(pt, { wx: frame[0], wy: frame[1], ww: frame[2], wh: frame[3] });
    // Строка «Файлы» (#11654, К-DOCK-6a): верх и высота кнопки, правый край кнопок размера + DOCK_BAR_GAP — так же,
    // как их ставят dockPlaceButton и dockPlaceSizes (кнопки размера стоят, пока место здесь — с каждым on=1 и dock=1).
    if (found && dockMain()) {
      const buttonRight = dockRowEnd(found) + DOCK_BUTTON_GAP + DOCK_BUTTON_WIDTH;
      const sizesRight = Math.max(buttonRight, box.left) + DOCK_BUTTON_GAP + DOCK_MODES.length * DOCK_SIZE_WIDTH + (DOCK_MODES.length - 1) * DOCK_BUTTON_GAP;
      Object.assign(pt, { bx: Math.round((sizesRight + DOCK_BAR_GAP) * z), by: Math.round(found.box.top * z), bh: Math.round(found.box.height * z) });
    }
    const room = width + DOCK_RAIL;
    return { host, found, z, mode, left: box.left, top, width, height, room, pt };
  };
  // Ключи места в адресе (К-DOCK-1): x, y, w, h, wx, wy, ww, wh — целые, размеры > 0; иначе "" (не шлём).
  const dockPlaceKeys = pt => {
    if (!pt || !DOCK_KEYS.every(key => Number.isInteger(pt[key]))) return "";
    if (!(pt.w > 0 && pt.h > 0 && pt.ww > 0 && pt.wh > 0)) return "";
    return DOCK_KEYS.map(key => `${key}=${pt[key]}`).join("&") + dockBarKeys(pt);
  };
  // Строка «Файлы» (К-DOCK-6b): целые до 6 знаков, by ≥ 0, 16 ≤ bh ≤ 64, by + bh ≤ y, полосе ≥ 80 pt; иначе "".
  const dockBarKeys = pt => {
    if (!DOCK_BAR_KEYS.every(key => Number.isInteger(pt[key]) && Math.abs(pt[key]) < 1e6)) return "";
    if (!(pt.by >= 0 && pt.bh >= 16 && pt.bh <= 64 && pt.by + pt.bh <= pt.y && Math.max(pt.bx, pt.x) <= pt.x + pt.w - 80)) return "";
    return DOCK_BAR_KEYS.map(key => `&${key}=${pt[key]}`).join("");
  };
  // Рамка окна для on=0 (К-DOCK-1: владельца Пимп узнаёт по окну): нынешняя, иначе последнего места (fallback).
  const dockWindowKeys = (fallback = null) => {
    let frame = null;
    try { frame = chatFrame("main"); } catch { frame = null; }
    const box = frame ? { wx: frame[0], wy: frame[1], ww: frame[2], wh: frame[3] } : fallback ?? dockState.place;
    if (!box || !["wx", "wy", "ww", "wh"].every(key => Number.isInteger(box[key])) || !(box.ww > 0 && box.wh > 0)) return "";
    return `&wx=${box.wx}&wy=${box.wy}&ww=${box.ww}&wh=${box.wh}`;
  };
  const dockUrl = (on, pt = null, vis = true) => {
    const chat = galleryChat();
    const who = chat ? `&chat=${encodeURIComponent(chat)}` : "";
    const base = `http://127.0.0.1:${HTML_CHROME_PORT}/dock?`;
    const paint = dockState.paint ? `&bg=${dockState.paint}` : "";
    return on ? `${base}on=1&vis=${vis ? 1 : 0}&${dockPlaceKeys(pt)}${paint}${who}&seq=${dockState.seq}`
      : `${base}on=0${who}${dockWindowKeys(pt)}&seq=${dockState.seq}`;
  };
  const DOCK_PROBE_URL = `http://127.0.0.1:${HTML_CHROME_PORT}/dock?probe=1`;
  // Кнопке место — у живого PimpViewer в главном окне, где есть куда встать панели.
  const dockGrace = () => dockState.viewer !== "up" && dockState.viewer !== "none" && now() - dockState.upAt < DOCK_GRACE_MS;
  const dockUsable = () => dockMain() && (dockState.viewer === "up" || dockGrace());
  // Пол боковой панели (раздел 2д): у открытой панели кнопка стоит в её строке «Hide sidebar» — панель не ýже,
  // чем нужно кнопке. 0 — кнопки там нет.
  const dockLeftFloor = aside => {
    if (!dockUsable() || !dockHost()) return 0;
    const found = dockSidebarButton();
    if (!found || !DOCK_SIDEBAR_HIDE.includes(found.node.getAttribute("aria-label")) || !aside?.contains?.(found.node)) return 0;
    const box = aside.getBoundingClientRect();
    return Math.round(dockRowEnd(found) + DOCK_BUTTON_GAP + DOCK_BUTTON_WIDTH + LEFT_TITLEBAR_PAD - box.left);
  };
  // Слои над местом: меню, диалоги и панель 12п³ (опоры health(), раздел 18), выехавший список чатов Claude и
  // свои слои — просмотр фото 12л, меню глав 12х², «Запустить?» 12т. Окно PimpViewer выше всего окна Claude:
  // не спрячь его — оно закроет их.
  let dockCoverList = "";
  const dockCovers = () => (dockCoverList ||= `${HEALTH_PAGE.sel.overlay},#frame-peek-popover,#${PHOTO_VIEW_ID},#${CH_DIM_ID},#${CH_SET_ID},#${RUN_CONFIRM_ID}`);
  const dockVisible = measure => {
    if (document.hidden) return false;
    try { if (document.querySelector(DOCK_PEEK_SELECTOR)) return false; } catch {}
    let nodes = [];
    try { nodes = [...document.querySelectorAll(dockCovers())]; } catch { nodes = []; }
    const right = measure.left + measure.width;
    const bottom = measure.top + measure.height;
    for (const node of nodes) {
      const box = node.getBoundingClientRect();
      if (!(box.width > 0 && box.height > 0)) continue;
      if (box.right <= measure.left || box.left >= right || box.bottom <= measure.top || box.top >= bottom) continue;
      let style = null;
      try { style = getComputedStyle(node); } catch { style = null; }
      if (style && (style.display === "none" || style.visibility === "hidden" || Number.parseFloat(style.opacity) === 0)) continue;
      return false;
    }
    return true;
  };
  // keep — снять нажатие только у этого экземпляра (отказ PimpViewer): ключ общий у окон, стирает его человек.
  const dockSetWant = (on, keep = false) => {
    dockState.want = on;
    if (keep) return;
    try { if (on) localStorage.setItem(DOCK_ON_KEY, "1"); else localStorage.removeItem(DOCK_ON_KEY); } catch {}
  };
  const dockSettle = () => {
    if (dockState.wait) { clearTimeout(dockState.wait); dockState.wait = 0; }
    dockState.pressing = false;
    if (dockNodes.button.dataset.state) delete dockNodes.button.dataset.state;
  };
  // Ответ /dock: {ok, viewer:"up|down|none", docked, owner:"this|other"}; нет JSON или сети — viewer неизвестен.
  // asked — что спрашивали ({on, vis} или {probe}). Нажатие, на которое PimpViewer не встал, возвращает кнопку как
  // была, говорит причину и шлёт on=0 (вдруг PimpViewer встал позже ответа). Отказ встать считается только на видимое
  // место: скрытый док (vis=0) — не отказ; док у другого окна (owner "other") — тоже: место здесь снимает dockSync.
  const dockAnswer = (body, status = 200, seq = dockState.seq, asked = {}) => {
    const on = asked?.on === true;
    if (!state.alive || seq < dockState.answered) return;
    dockState.answered = seq;
    dockState.answers += 1;
    const viewer = body && typeof body === "object" && ["up", "down", "none"].includes(body.viewer) ? body.viewer : null;
    const was = dockState.viewer;
    dockState.viewer = viewer;
    if (viewer === "up") dockState.upAt = now();
    dockState.docked = body?.docked === true;
    dockState.owner = typeof body?.owner === "string" ? body.owner : null;
    // apart (#11677): отдельное окно PimpViewer на экране и дока нет — файл из чата идёт в то окно.
    dockState.apart = body?.apart === true;
    dockState.error = viewer ? null : status ? `http ${status}` : "network";
    const pressed = dockState.pressing;
    if (on) dockSettle();
    let note = "";
    if (on && dockState.want) {
      if (viewer !== "up") {
        if (pressed) note = DOCK_NOTES[viewer] ?? DOCK_NOTES.silent;
      } else if (dockState.docked || dockState.owner === "other") dockState.refusals = 0;
      else if (asked.vis !== false && (dockState.refusals += 1) >= DOCK_REFUSALS) note = DOCK_NOTES.refused;
    }
    if (note) {
      dockSetWant(false, true);
      try { dockSend(false); } catch {}
    }
    if (!dockState.want) { dockState.refusals = 0; dockState.place = null; dockState.sig = ""; }
    if (note) { try { newWindowNote(note); } catch {} }
    try { dockSync(); } catch {}
    if (was !== viewer || note) { try { scheduleLayout(); } catch {} }
  };
  // Запрос /dock; then — после ответа (любого), раз.
  const dockFetch = (url, asked, then = null) => {
    dockState.seq = Math.max(dockState.seq + 1, Date.now());
    const seq = dockState.seq;
    const address = url();
    dockState.last = address;
    dockState.sent += 1;
    const answer = (body, status) => {
      dockAnswer(body, status, seq, asked);
      if (then) { try { then(); } catch {} }
    };
    let sent = null;
    try { sent = fetch(address, { mode: "cors", credentials: "omit", cache: "no-store" }); } catch { sent = null; }
    if (!sent || typeof sent.then !== "function") { answer(null, 0); return true; }
    sent.then(reply => {
      const status = Number(reply?.status) || (reply?.ok ? 200 : 0);
      if (typeof reply?.json !== "function") return answer(null, status);
      return reply.json().then(body => answer(body, status), () => answer(null, status));
    }, () => answer(null, 0)).catch(() => {});
    return true;
  };
  const dockSend = (on, pt = null, vis = true, then = null) => {
    if (typeof fetch !== "function" || (on && !dockPlaceKeys(pt))) return false;
    return dockFetch(() => dockUrl(on, pt, vis), { on, vis: on ? vis : null }, then);
  };
  // Жив ли PimpViewer (кнопка): Пимп отвечает сам, док не трогает (on=0 снял бы панель другого окна).
  const dockProbe = () => typeof fetch === "function" && dockFetch(() => DOCK_PROBE_URL, { probe: true });
  // Снять место: отступ чата, подложку, рейку и полосу перетаскивания.
  const dockUnplace = () => {
    try {
      for (const root of document.querySelectorAll(`.dframe-root[${DOCK_ATTRIBUTE}]`)) {
        root.removeAttribute(DOCK_ATTRIBUTE);
        root.style.removeProperty(DOCK_VARIABLE);
      }
    } catch {}
    for (const node of [dockNodes.place, dockNodes.rail, dockNodes.drag, dockNodes.sizes]) dockHide(node);
    dockState.shift = null;
  };
  // Вид места (слово Элвиса 23.10 19:30: «разделение точно такое же, как вот здесь вот»; 05.11 #11692: «у файлов фон
  // точно такой же, как у клауда… как единое целое»): подложка — поверхность чата Claude (фон main, нет — --cds-page-bg),
  // рейка — тонкая граница боковой панели (открытая — замер border-inline-end aside, иначе --cds-border). Живой фон
  // (look.aurora, раздел 2а) — подложка прозрачна. paint — сплошной цвет для PimpViewer (`bg` в /dock, hex без #).
  const dockClear = text => !text || text === "transparent" || /^rgba\([^)]*,\s*0(\.0+)?\s*\)$/.test(text);
  const dockSidebarLook = root => {
    const read = (style, name) => { try { return String(style?.getPropertyValue?.(name) ?? "").trim(); } catch { return ""; } };
    let rs = null;
    try { rs = getComputedStyle(root); } catch { rs = null; }
    const own = read(rs, "--cds-page-bg") || read(rs, "--df-web-sidebar-bg") || read(rs, "--df-sidebar-bg");
    let line = read(rs, "--cds-border");
    let bg = own;
    try {
      const main = root.querySelector("main");
      const color = main ? String(getComputedStyle(main).backgroundColor ?? "").trim() : "";
      if (!dockClear(color)) bg = color;
    } catch {}
    let aside = null;
    try { aside = root.querySelector("aside.dframe-sidebar"); } catch { aside = null; }
    if (aside && !root.hasAttribute("data-collapsed")) {
      let style = null;
      try { style = getComputedStyle(aside); } catch { style = null; }
      const edge = read(style, "border-right-color");
      if (Number.parseFloat(read(style, "border-right-width")) > 0 && !dockClear(edge)) line = edge;
    }
    if (themeState.look?.aurora) bg = "transparent";
    let paint = "";
    try { paint = htmlChromeBgKey(progressHex(dockClear(bg) ? own : bg) ?? ""); } catch { paint = ""; }
    return { bg, line, paint };
  };
  const dockPaint = root => {
    const look = dockSidebarLook(root);
    dockState.paint = look.paint;
    const sig = `${look.bg}|${look.line}`;
    if (sig === dockState.bg) return;
    dockState.bg = sig;
    for (const node of [dockNodes.place, dockNodes.rail, dockNodes.button, dockNodes.sizes]) {
      if (look.bg) node.style.setProperty(DOCK_BG_VARIABLE, look.bg); else node.style.removeProperty(DOCK_BG_VARIABLE);
    }
    if (look.line) dockNodes.rail.style.setProperty(DOCK_LINE_VARIABLE, look.line); else dockNodes.rail.style.removeProperty(DOCK_LINE_VARIABLE);
  };
  const dockPlaceAt = (measure, buttonRight) => {
    const root = measure.host.closest?.(".dframe-root") ?? document.querySelector(".dframe-root");
    if (!root) return;
    const room = `${Math.round(measure.room * 100) / 100}px`;
    if (root.style.getPropertyValue(DOCK_VARIABLE) !== room) root.style.setProperty(DOCK_VARIABLE, room);
    if (!root.hasAttribute(DOCK_ATTRIBUTE)) root.setAttribute(DOCK_ATTRIBUTE, "");
    dockPaint(root);
    // Подложка — всё место панели во всех размерах; чат правее (у «панель + поле» — колонкой с полем ввода).
    dockShow(dockNodes.place, "block", { left: measure.left, top: measure.top, width: measure.width, height: measure.height });
    dockShow(dockNodes.rail, "block", { left: measure.left + measure.width, top: measure.top, width: DOCK_RAIL, height: measure.height });
    // Полоса перетаскивания — над местом, правее кнопок «PMP» и размера, до кромки чата: правее в этой строке шапка
    // чата Claude (имя сессии, «Session rail», «View options»), полоса над ней сделала бы её кнопки ручкой окна.
    const from = Math.max(measure.left, buttonRight > 0 ? buttonRight + DOCK_BUTTON_GAP : measure.left);
    const width = measure.left + measure.room - from;
    if (width > 0 && measure.top > 0) dockShow(dockNodes.drag, "block", { left: from, top: 0, width, height: measure.top });
    else dockHide(dockNodes.drag);
    // Сдвиг чата замером: отступ правда встал (правило раздела 4 нашло pane-host) — status().dock.shift.
    try {
      const primary = measure.host.querySelector(".dframe-pane-primary");
      dockState.shift = primary ? Math.round(primary.getBoundingClientRect().left - measure.left) : null;
    } catch { dockState.shift = null; }
  };
  // Вид кнопки — с соседа (#10705, слово Элвиса по снимку 23.10: «Там жирно, здесь не жирно»): рамка, подложка, вес,
  // гарнитура и цвет «Show/Hide sidebar» замером его computed style (у свёрнутой панели — рамка и подложка раздела 4,
  // у открытой — без них, как у Claude); не прочлось — правила ниже. Нажата — как нажатая кнопка Claude (заливка и цвет
  // акцента), рамка та же.
  const DOCK_LOOK = { ring: "--myclaude-dock-ring", under: "--myclaude-dock-under", weight: "--myclaude-dock-weight",
    font: "--myclaude-dock-font", fg: "--myclaude-dock-fg" };
  const dockLook = (button, node) => {
    let own = null;
    let before = null;
    try { own = getComputedStyle(node); before = getComputedStyle(node, "::before"); } catch { return; }
    // Фокус соседа — его кольцо фокуса, не рамка: вид не меняем.
    try { if (node.matches?.(":focus-visible")) return; } catch {}
    const read = (style, name) => { try { return String(style?.getPropertyValue?.(name) ?? "").trim(); } catch { return ""; } };
    const content = read(before, "content") || "none";
    const look = {
      ring: read(own, "box-shadow") || "none", weight: read(own, "font-weight"), font: read(own, "font-family"), fg: read(own, "color"),
      under: content !== "none" && content !== "normal" ? read(before, "background-color") : "transparent",
    };
    const sig = JSON.stringify(look);
    if (sig === dockState.look) return;
    dockState.look = sig;
    for (const [key, name] of Object.entries(DOCK_LOOK)) {
      for (const node of [button, dockNodes.sizes]) {
        if (look[key]) node.style.setProperty(name, look[key]); else node.style.removeProperty(name);
      }
    }
  };
  const dockPlaceButton = (found, measure) => {
    const button = dockNodes.button;
    if (!found || !measure) { dockHide(button); return 0; }
    dockLook(button, found.node);
    const left = dockRowEnd(found) + DOCK_BUTTON_GAP;
    dockShow(button, "flex", { left, top: found.box.top, width: DOCK_BUTTON_WIDTH, height: found.box.height });
    const on = dockState.want ? "true" : "false";
    if (button.dataset.on !== on) button.dataset.on = on;
    button.setAttribute("aria-pressed", on);
    const title = !dockState.want ? DOCK_TITLE_OFF : dockState.owner === "other" ? DOCK_TITLE_HERE : DOCK_TITLE_ON;
    if (button.title !== title) { button.title = title; button.setAttribute("aria-label", title); }
    return left + DOCK_BUTTON_WIDTH;
  };
  // Кнопки размера — справа от «PMP», только пока место стоит; правый край — для полосы перетаскивания. floor — левый
  // край места: у открытой боковой панели «PMP» в её строке, кнопки — над местом, правее её границы (не поперёк линии).
  const dockPlaceSizes = (found, buttonRight, show, floor = 0) => {
    const sizes = dockNodes.sizes;
    if (!show || !found || !(buttonRight > 0)) { dockHide(sizes); return buttonRight; }
    const left = Math.max(buttonRight, floor) + DOCK_BUTTON_GAP;
    const width = DOCK_MODES.length * DOCK_SIZE_WIDTH + (DOCK_MODES.length - 1) * DOCK_BUTTON_GAP;
    dockShow(sizes, "flex", { left, top: found.box.top, width, height: found.box.height });
    for (const mode of DOCK_MODES) {
      const item = dockNodes.modes[mode];
      const on = dockMode() === mode ? "true" : "false";
      if (item.dataset.on !== on) item.dataset.on = on;
      if (item.getAttribute("aria-pressed") !== on) item.setAttribute("aria-pressed", on);
    }
    return left + width;
  };
  const dockLater = () => {
    if (dockState.later) return;
    dockState.later = setTimeout(() => { dockState.later = 0; if (state.alive) { try { dockSync(); } catch {} } }, DOCK_SETTLE_MS);
  };
  // Один проход: кнопка, место, и — если пора — запрос. force — шлём сейчас (нажатие, команда).
  const dockSync = (force = false) => {
    if (!dockMain()) { dockHide(dockNodes.button); dockUnplace(); return; }
    const measure = dockMeasure();
    const usable = dockUsable() && Boolean(measure);
    const buttonRight = dockPlaceButton(usable ? measure.found : null, usable ? measure : null);
    // Док у другого окна — место здесь снято, чат на всю ширину; нажатие помнится, сердце идёт.
    const placing = dockState.want && usable && dockState.owner !== "other";
    const shown = placing && dockVisible(measure);
    const dragFrom = dockPlaceSizes(usable ? measure.found : null, buttonRight, placing, usable ? measure.left : 0);
    if (placing) dockPlaceAt(measure, dragFrom); else dockUnplace();
    const t = now();
    if (!dockState.want) {
      // Не нажата: раз в DOCK_PROBE_MS — жив ли PimpViewer (кнопка), только там, где ей есть место.
      if (measure?.found && !document.hidden && t - dockState.probeAt >= (dockGrace() ? DOCK_RETRY_MS : DOCK_PROBE_MS)) {
        dockState.probeAt = t;
        dockProbe();
      }
      return;
    }
    // Места нет (Claude ушёл со страницы чата) — сердце с прежним местом и vis=0, док прячется сам.
    const pt = measure?.pt ?? dockState.place;
    if (!pt) return;
    const vis = placing ? shown : Boolean(measure) && dockVisible(measure);
    const sig = `${pt.x},${pt.y},${pt.w},${pt.h},${pt.bx},${pt.by},${pt.bh},${vis ? 1 : 0}`;
    const up = dockState.viewer === "up";
    const due = t - dockState.beatAt >= (up ? DOCK_BEAT_READY_MS : dockGrace() ? DOCK_RETRY_MS : DOCK_PROBE_MS);
    if (!force && !due && !(up && sig !== dockState.sig)) return;
    if (dockState.sig && sig !== dockState.sig) dockLater();
    dockState.place = { ...pt };
    dockState.sig = sig;
    dockState.vis = vis;
    dockState.beatAt = t;
    dockSend(true, pt, vis);
  };
  const placeDock = () => dockSync();
  // Нажать (on) или закрыть панель: кнопка, команда `dock`, файл из чата. Нажатие ждёт ответа — кнопка «wait».
  // Нажатие при доке у другого окна забирает его сюда: пауза и показ подряд — для Пимпа это новость этого окна
  // (владелец — окно, приславшее vis=1 с новым местом или видом). then — после ответа на on=0 (закрытие).
  // file — панель открыл файл из чата (#11223): узкая, ≤ ½ чата, пока её не закроют или не выберут размер.
  const dockSet = (on, then = null, file = false) => {
    if (!dockMain()) return false;
    dockState.file = on && file;
    if (on) {
      const claim = dockState.want && dockState.owner === "other";
      if (!dockState.want) dockState.refusals = 0;
      dockSetWant(true);
      dockState.pressing = true;
      dockNodes.button.dataset.state = "wait";
      if (dockState.wait) clearTimeout(dockState.wait);
      const seq = Math.max(dockState.seq + 1, Date.now());
      dockState.wait = setTimeout(() => { dockState.wait = 0; if (dockState.pressing) dockAnswer(null, 0, seq, { on: true, vis: true }); }, DOCK_WAIT_MS);
      if (claim) { const pt = dockMeasure()?.pt; if (pt) dockSend(true, pt, false); }
      dockSync(true);
      try { scheduleLayout(); } catch {}
      return true;
    }
    // Закрыл человек (кнопка, команда): on=0; следующая проверка «жив ли PimpViewer» — через DOCK_PROBE_MS.
    dockSettle();
    const pt = dockState.place;
    dockSetWant(false);
    dockState.refusals = 0;
    dockState.place = null;
    dockState.sig = "";
    dockUnplace();
    dockState.probeAt = now();
    if (!dockSend(false, pt, true, then) && then) { try { then(); } catch {} }
    dockSync();
    try { scheduleLayout(); } catch {}
    return true;
  };
  // Кнопка: не нажата или док у другого окна — панель сюда; иначе закрыть.
  const dockToggle = () => dockSet(!dockState.want || dockState.owner === "other");
  // «🖼 Открыть в новом окне» (раздел 12г): галерея одна на окно и панель — панель этого окна закрывается, как
  // кнопкой, а фото уходит окну галереи по ответу на on=0 (иначе PimpViewer открыл бы его в доке). false — панели
  // здесь нет, then не звали.
  const dockLeave = then => {
    if (!dockMain() || !dockState.want || dockState.owner === "other") return false;
    return dockSet(false, then);
  };
  // Файл из чата (fileClick, 12д¹): место для `click&dock=1`, панель встаёт сама; не выйдет — null (прежний путь).
  // Док у другого окна: Пимп отдаёт его окну клика (К-DOCK-1, `/open-html … dock=1`), место здесь — по ответу.
  // Панели не было — встаёт узкой, не шире половины места чата (#11223, Элвис 30.10: «свёрнутый был, взял весь экран»).
  // Отдельное окно PimpViewer на экране (apart, #11677) и панели тут нет — null: файл уходит в то окно.
  const dockForFile = () => {
    if (!dockUsable() || (dockState.apart && !dockState.want)) return null;
    const opening = !dockState.want;
    const was = dockState.file;
    if (opening) dockState.file = true;
    const measure = dockMeasure();
    if (!measure || !dockPlaceKeys(measure.pt)) { dockState.file = was; return null; }
    dockState.opens += 1;
    if (opening) dockSet(true, null, true);
    return { ...measure.pt };
  };
  // Размер панели (#10759): mode — "narrow" | "half" | "full"; помнится; место и запрос — сразу.
  const dockSize = mode => {
    if (!dockMain() || !DOCK_MODES.includes(mode)) return false;
    dockState.file = false;
    dockState.mode = mode;
    try { localStorage.setItem(DOCK_MODE_KEY, mode); } catch {}
    try { dockSync(); } catch {}
    try { scheduleLayout(); } catch {}
    return true;
  };
  // Кнопка размера: нажатая «½» или «панель + поле» — обратно к узкой («легко возвращать к исходному размеру»).
  // #11657 (слово Элвиса 05.11: «кнопка левая самая левая и кнопка самая правая… одинаково»): узкая с кнопок — всегда
  // «стандартный узенький» DOCK_DEFAULT_PT, как двойной щелчок по рейке. Тяга рейки у «панель + поле» запоминала
  // ширину почти во всё окно, и узкая выходила той же «панель + поле».
  const dockSizePress = mode => {
    const next = dockMode() === mode && mode !== "narrow" ? "narrow" : mode;
    if (next === "narrow" && dockMain()) { dockState.width = DOCK_DEFAULT_PT; dockStoreWidth(DOCK_DEFAULT_PT); }
    return dockSize(next);
  };
  // Команда `dock` {on:true|false, size:"narrow"|"half"|"full"} (раздел 15): то же, что кнопки, — для живой проверки
  // без клика. Только size — размер, нажатие не трогаем.
  // only:"owner" — от `/viewer-dock-off` (#11224, ✕ в PimpViewer): закрыть, только если панель стоит в этом окне.
  const dockCommand = detail => {
    if (detail?.only === "owner") return dockLeave(null);
    const sized = detail?.size !== undefined && dockSize(detail.size);
    if (detail?.on === undefined && detail?.size !== undefined) return sized;
    return dockSet(detail?.on === true || String(detail?.on) === "true");
  };
  // Кадр на смену места: тяга рейки (с ней — проход раскладки: чат стал другой ширины) и чужая тяга мышью
  // (боковая панель Claude) — последний выигрывает.
  const dockFrame = (relayout = false) => {
    if (relayout) dockState.relayout = true;
    if (dockState.frame) return;
    dockState.frame = requestAnimationFrame(() => {
      dockState.frame = 0;
      if (!state.alive) return;
      try { dockSync(); } catch {}
      if (dockState.relayout) { dockState.relayout = false; try { scheduleLayout(); } catch {} }
    });
  };
  const dockStoreWidth = value => {
    try {
      if (value == null) localStorage.removeItem(DOCK_WIDTH_KEY);
      else localStorage.setItem(DOCK_WIDTH_KEY, String(Math.round(value)));
    } catch {}
  };
  const dockDragEnd = () => {
    dockState.dragging = false;
    dockState.grip = null;
    dockNodes.rail.dataset.dragging = "false";
    try { document.documentElement.style.cursor = ""; document.documentElement.style.userSelect = ""; } catch {}
  };
  // Тяга рейки: ширина = ширина при захвате + сдвиг курсора (в точках), в границах dockWidthFor.
  const onDockRailDown = event => {
    if (event.button !== 0 || !dockState.want) return;
    const measure = dockMeasure();
    if (!measure) return;
    event.preventDefault();
    // Тянут рейку у «½» или «панель + поле» — дальше узкая с этой ширины.
    if (dockState.mode !== "narrow") { dockState.mode = "narrow"; try { localStorage.setItem(DOCK_MODE_KEY, "narrow"); } catch {} }
    if (dockState.file) { dockState.file = false; dockState.width = measure.pt.w; }
    dockState.dragging = true;
    dockState.grip = { x: event.clientX, width: measure.pt.w, z: measure.z, host: measure.host.getBoundingClientRect().width };
    dockNodes.rail.dataset.dragging = "true";
    try { document.documentElement.style.cursor = "col-resize"; document.documentElement.style.userSelect = "none"; } catch {}
    try { dockNodes.rail.setPointerCapture?.(event.pointerId); } catch {}
  };
  const onDockMove = event => {
    if (dockState.dragging && dockState.grip) {
      event.preventDefault?.();
      const grip = dockState.grip;
      dockState.width = dockWidthFor(grip.host, grip.z, grip.width + (event.clientX - grip.x) * grip.z);
      dockFrame(true);
      return;
    }
    // Боковую панель Claude тянут или выдвигают мышью — место едет вместе с ней.
    if (dockState.want && (Number(event.buttons) & 1) === 1) dockFrame();
  };
  const onDockRailUp = () => {
    if (!dockState.dragging) return;
    dockDragEnd();
    dockStoreWidth(dockState.width);
    try { dockSync(); } catch {}
    try { scheduleLayout(); } catch {}
  };
  const onDockRailReset = event => {
    event?.preventDefault?.();
    dockState.width = DOCK_DEFAULT_PT;
    dockStoreWidth(DOCK_DEFAULT_PT);
    dockState.mode = "narrow";
    try { localStorage.setItem(DOCK_MODE_KEY, "narrow"); } catch {}
    try { dockSync(); } catch {}
    try { scheduleLayout(); } catch {}
  };
  on(dockNodes.button, "click", event => {
    event.preventDefault();
    if (!state.alive || Number(event.detail) > 1) return;
    try { dockToggle(); } catch {}
  });
  on(dockNodes.button, "keydown", event => {
    if (!state.alive || (event.key !== "Enter" && event.key !== " ")) return;
    event.preventDefault();
    try { dockToggle(); } catch {}
  });
  on(dockNodes.button, "pointerdown", galleryKeepFocus);
  on(dockNodes.button, "mousedown", galleryKeepFocus);
  for (const mode of DOCK_MODES) {
    const item = dockNodes.modes[mode];
    on(item, "click", event => {
      event.preventDefault();
      if (!state.alive || Number(event.detail) > 1) return;
      try { dockSizePress(mode); } catch {}
    });
    on(item, "keydown", event => {
      if (!state.alive || (event.key !== "Enter" && event.key !== " ")) return;
      event.preventDefault();
      try { dockSizePress(mode); } catch {}
    });
    on(item, "pointerdown", galleryKeepFocus);
    on(item, "mousedown", galleryKeepFocus);
  }
  on(dockNodes.rail, "pointerdown", onDockRailDown);
  on(dockNodes.rail, "dblclick", onDockRailReset);
  on(document, "pointermove", onDockMove, { capture: true, passive: false });
  on(document, "pointerup", onDockRailUp, { capture: true });
  on(document, "pointercancel", onDockRailUp, { capture: true });
  // Окно скрыто или вернулось — сразу: проход раскладки ждёт кадра, а у скрытой страницы кадров нет.
  on(document, "visibilitychange", () => { try { dockSync(); } catch {} });
  if (chatKind() === "main") dockState.timer = setInterval(() => { try { if (state.alive) dockSync(); } catch {} }, DOCK_BEAT_MS);
  track(() => {
    if (dockState.timer) { clearInterval(dockState.timer); dockState.timer = 0; }
    if (dockState.frame) { cancelAnimationFrame(dockState.frame); dockState.frame = 0; }
    if (dockState.later) { clearTimeout(dockState.later); dockState.later = 0; }
    if (dockState.wait) { clearTimeout(dockState.wait); dockState.wait = 0; }
    if (dockState.dragging) dockDragEnd();
    // Снятие экземпляра (К-DOCK-1): панель стояла — on=0; нажатие помнится, новый экземпляр поставит её снова.
    if (dockState.want && dockState.place) { try { dockSend(false); } catch {} }
    dockUnplace();
  });
  // Место (правило раздела 4 у файла фичи): чат — правее панели; у свёрнутой боковой панели Claude держит в чате
  // место под кнопки окна и «Show sidebar» (--top-left-clearance, --df-trigger-right) — чат теперь не под ними.
  lateRules.push(
    `.dframe-root[${DOCK_ATTRIBUTE}] .dframe-pane-host{padding-left:var(${DOCK_VARIABLE}) !important}`,
    `.dframe-root[${DOCK_ATTRIBUTE}] .dframe-pane-primary{--top-left-clearance:0px !important;--df-trigger-right:0px !important;--df-traffic-light-spacer-end:0px !important}`,
    `#${DOCK_BUTTON_ID}{position:fixed;display:none;align-items:center;justify-content:center;box-sizing:border-box;width:${DOCK_BUTTON_WIDTH}px;height:28px;padding:0;border:0;border-radius:8px;background:var(${DOCK_LOOK.under},var(${DOCK_BG_VARIABLE},var(--cds-page-bg,#131518)));box-shadow:var(${DOCK_LOOK.ring},0 0 0 1px var(--cds-border,rgba(127,127,127,.3)));color:var(${DOCK_LOOK.fg},var(--cds-text-primary,inherit));font-weight:var(${DOCK_LOOK.weight},var(--cds-font-weight-control,435));font-size:11px;line-height:1;font-family:var(${DOCK_LOOK.font},var(--cds-font-sans,-apple-system,system-ui,sans-serif));letter-spacing:.3px;cursor:pointer;-webkit-app-region:no-drag;user-select:none;-webkit-user-select:none;z-index:2147483645;transition:color .15s,background-color .15s,box-shadow .15s,opacity .15s}`,
    `#${DOCK_BUTTON_ID}>span{pointer-events:none}`,
    // Наведение и нажатие — заливкой поверх подложки, как paint у кнопки Claude (ghost-hover, bg-accent и text-accent).
    `#${DOCK_BUTTON_ID}:hover{background:linear-gradient(var(--cds-fill-button-ghost-hover,var(--cds-fill-ghost-hover,rgba(255,255,255,.07))),var(--cds-fill-button-ghost-hover,var(--cds-fill-ghost-hover,rgba(255,255,255,.07)))),var(${DOCK_LOOK.under},var(${DOCK_BG_VARIABLE},var(--cds-page-bg,#131518)))}`,
    `#${DOCK_BUTTON_ID}:focus-visible{outline:2px solid var(--cds-text-accent,currentColor);outline-offset:1px}`,
    `#${DOCK_BUTTON_ID}[data-on="true"]{color:var(--cds-text-accent,currentColor);background:linear-gradient(var(--cds-bg-accent,rgba(37,125,224,.12)),var(--cds-bg-accent,rgba(37,125,224,.12))),var(${DOCK_LOOK.under},var(${DOCK_BG_VARIABLE},var(--cds-page-bg,#131518)))}`,
    `#${DOCK_BUTTON_ID}[data-state="wait"]{cursor:progress;opacity:.65}`,
    `#${DOCK_PLACE_ID}{position:fixed;display:none;box-sizing:border-box;background:var(${DOCK_BG_VARIABLE},var(--cds-page-bg,#131518));-webkit-app-region:no-drag;z-index:1}`,
    // Кнопки размера — вид «PMP» (рамка, подложка, наведение, нажатие); значок — рамка окна, доля панели залита.
    `#${DOCK_SIZES_ID}{position:fixed;display:none;align-items:stretch;gap:${DOCK_BUTTON_GAP}px;-webkit-app-region:no-drag;user-select:none;-webkit-user-select:none;z-index:2147483645}`,
    `#${DOCK_SIZES_ID}>div{position:relative;flex:0 0 ${DOCK_SIZE_WIDTH}px;box-sizing:border-box;border-radius:8px;background:var(${DOCK_LOOK.under},var(${DOCK_BG_VARIABLE},var(--cds-page-bg,#131518)));box-shadow:var(${DOCK_LOOK.ring},0 0 0 1px var(--cds-border,rgba(127,127,127,.3)));color:var(${DOCK_LOOK.fg},var(--cds-text-primary,inherit));cursor:pointer;transition:color .15s,background-color .15s,box-shadow .15s}`,
    `#${DOCK_SIZES_ID}>div>span{position:absolute;left:7px;top:50%;width:14px;height:11px;box-sizing:border-box;transform:translateY(-50%);border:1.5px solid currentColor;border-radius:2.5px;opacity:.8;pointer-events:none}`,
    `#${DOCK_SIZES_ID}>div>span::before{content:"";position:absolute;left:0;top:0;bottom:0;background:currentColor}`,
    `#${DOCK_SIZES_ID}>div[data-mode="narrow"]>span::before{width:30%}`,
    `#${DOCK_SIZES_ID}>div[data-mode="half"]>span::before{width:50%}`,
    // «Панель + поле» (#11202): панель ~80%, справа узкая колонка чата.
    `#${DOCK_SIZES_ID}>div[data-mode="full"]>span::before{width:80%}`,
    `#${DOCK_SIZES_ID}>div:hover{background:linear-gradient(var(--cds-fill-button-ghost-hover,var(--cds-fill-ghost-hover,rgba(255,255,255,.07))),var(--cds-fill-button-ghost-hover,var(--cds-fill-ghost-hover,rgba(255,255,255,.07)))),var(${DOCK_LOOK.under},var(${DOCK_BG_VARIABLE},var(--cds-page-bg,#131518)))}`,
    `#${DOCK_SIZES_ID}>div:focus-visible{outline:2px solid var(--cds-text-accent,currentColor);outline-offset:1px}`,
    `#${DOCK_SIZES_ID}>div[data-on="true"]{color:var(--cds-text-accent,currentColor);background:linear-gradient(var(--cds-bg-accent,rgba(37,125,224,.12)),var(--cds-bg-accent,rgba(37,125,224,.12))),var(${DOCK_LOOK.under},var(${DOCK_BG_VARIABLE},var(--cds-page-bg,#131518)))}`,
    `#${DOCK_SIZES_ID}>div[data-on="true"]>span{opacity:1}`,
    // Рейка — граница боковой панели Claude (#10759, 19:30): тонкая линия у края места, сама рейка прозрачна (тёмного
    // зазора между панелью и лентой нет); ручка наведения — на линии, как у Claude.
    `#${DOCK_RAIL_ID}{position:fixed;display:none;box-sizing:border-box;padding:0;border:0;background:transparent;color:rgba(127,127,127,.75);cursor:col-resize;-webkit-app-region:no-drag;user-select:none;-webkit-user-select:none;touch-action:none;z-index:2}`,
    `#${DOCK_RAIL_ID}::before{content:"";position:absolute;left:0;top:0;bottom:0;width:max(var(--cds-panel-line,0px),.5px);background:var(${DOCK_LINE_VARIABLE},var(--cds-border,rgba(127,127,127,.3)));pointer-events:none}`,
    `#${DOCK_RAIL_ID}>span{position:absolute;left:0;top:50%;width:3px;height:100%;max-height:${DOCK_RAIL_PILL}px;transform:translate(-50%,-50%);border-radius:999px;background:currentColor;opacity:0;pointer-events:none;transition:opacity 200ms cubic-bezier(.4,0,.2,1)}`,
    `#${DOCK_RAIL_ID}:hover>span{opacity:1;transition-delay:${SIDE_RAIL_REVEAL_MS}ms}`,
    `#${DOCK_RAIL_ID}[data-dragging="true"]>span{opacity:1;transition-delay:0ms}`,
    `#${DOCK_DRAG_ID}{position:fixed;display:none;-webkit-app-region:drag;z-index:1}`,
  );
  // Панель материалов (#10644, раздел 12п⁴): кнопка на виду; нажата (on, помнится); ответ PimpViewer (viewer,
  // docked, owner); место стоит (placed), последнее посланное место в точках и vis; ширина (точки, null —
  // обычная); размер (mode, #10759; file — узкая от файла из чата, #11223) и видны ли его кнопки (sizes); сдвиг чата замером (shift, CSS px); вид кнопки (state "wait"); запросов, ответов, файлов в панель;
  // отказов подряд; последний адрес; ошибка последнего ответа; тянут ли рейку.
  statusPart("dock", () => ({
    button: dockNodes.button.isConnected && dockNodes.button.style.getPropertyValue("display") === "flex",
    on: dockState.want, viewer: dockState.viewer, docked: dockState.docked, owner: dockState.owner, apart: dockState.apart === true,
    placed: dockNodes.place.style.getPropertyValue("display") === "block",
    place: dockState.place ? { ...dockState.place } : null, vis: dockState.vis, width: dockState.width, mode: dockState.mode, file: dockState.file,
    sizes: dockNodes.sizes.style.getPropertyValue("display") === "flex", shift: dockState.shift,
    state: dockNodes.button.dataset.state ?? null, sent: dockState.sent, answers: dockState.answers, opens: dockState.opens,
    refusals: dockState.refusals, last: dockState.last, error: dockState.error, dragging: dockState.dragging,
  }));
  HATCH && Object.assign(HATCH, { dockState, dockAnswer, dockSync, dockMeasure, dockUrl, dockPlaceKeys, dockSet, dockForFile,
    dockLeftFloor, dockSize, DOCK_MIN_PT, DOCK_DEFAULT_PT, DOCK_FEED_MIN, DOCK_RAIL });
