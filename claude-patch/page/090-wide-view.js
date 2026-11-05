  // ---- 2г. Широкий вид окна (WF65) -----------------------------------------
  // Раскладку делает CSS (layoutCss, раздел 2а); здесь — то, что страница обязана
  // знать сама: широкий ли сейчас вид, что при этом делать со ступенями поля и
  // рейка ширины правой колонки. Своих таймеров и наблюдателей раздел не
  // заводит: всё ходит в существующем проходе layout() (раздел 9).
  const SIDE_RAIL_ID = "myclaude-side-rail";
  // Рейка — копия рейки левой панели Claude (WF176, #9182: «у левой панельки… полоска
  // для изменения размера — правильно… у правой тоже должна быть такая полосочка»):
  // зона захвата 12 (w-3), пилюля 3×48 по центру высоты цветом text-muted, проявляется
  // на наведении через 200 мс за 200 мс (delay-200 duration-base) — замер 09.10.
  const SIDE_RAIL_WIDTH = 12;
  const SIDE_RAIL_PILL = 48;
  // Пауза перед появлением линии рейки на наведении — как у рейки Claude: случайный
  // проезд курсора её не зажигает.
  const SIDE_RAIL_REVEAL_MS = 200;
  const SIDE_RAIL_PILL_SELECTOR = '[data-cds="ResizeHandle"] [data-cds-part="resize-pill"]';
  // Ширина колонки, выбранная мышью: localStorage — окна Claude делят её, как и
  // ширину боковой панели у самого Claude. v2 с WF68: под v1 у Элвиса лежало
  // ровно 300 — тяга упёрлась в прежний минимум, и новая, узкая граница осталась
  // бы за этим числом невидимой; ширины v1 не читаются и не переносятся.
  const SIDE_STORAGE_KEY = "myclaude-wide-side-v2";
  // Доля к ней (WF197): ширина / ширина сетки в момент тяги, число 0…1. Отдельным ключом — v2 читают и
  // прежние страницы (Number() строки с долей дал бы NaN).
  const SIDE_SHARE_STORAGE_KEY = "myclaude-wide-side-share-v1";
  const layoutPanel = editor => {
    try {
      return editor?.closest?.(".epitaxy-chat-panel") ?? document.querySelector(".epitaxy-chat-panel");
    } catch { return null; }
  };
  // Единственный оракул: флаг, который CSS ставит на панель внутри контейнерного
  // запроса (см. layoutCss). На innerWidth не падаем никогда — стенды тестов
  // шириной 1200 обязаны оставаться узкими, а в бою второй порог разошёлся бы
  // с первым.
  const wideLayout = panel => {
    if (!panel?.isConnected) return false;
    try { return getComputedStyle(panel).getPropertyValue(WIDE_FLAG).trim() === "1"; } catch { return false; }
  };
  // Дока — правая колонка целиком: её левая кромка — кромка колонки, а ширина — колонка плюс COLUMN_PULL,
  // на который дока выезжает влево.
  const sideDock = panel => {
    try { return panel?.querySelector?.('[class~="group/approval-dock"]') ?? null; } catch { return null; }
  };
  // Ширина колонки — в единицах колонки (#6214): как переменная SIDE_VARIABLE, пол и sideMin. До WF261 здесь
  // отдавалась ширина доки, и status().layout.side было на 12 больше колонки рядом с sideMin в её единицах.
  const sideWidth = panel => {
    const dock = sideDock(panel);
    const box = dock?.isConnected ? dock.getBoundingClientRect() : null;
    return box && box.width > 0 ? Math.round(box.width) - COLUMN_PULL : null;
  };
  const readStoredSide = () => {
    try {
      const stored = Number(localStorage.getItem(SIDE_STORAGE_KEY));
      return Number.isFinite(stored) && stored >= SIDE_FLOOR ? Math.round(stored) : null;
    } catch { return null; }
  };
  const readStoredShare = () => {
    try {
      const share = Number(localStorage.getItem(SIDE_SHARE_STORAGE_KEY));
      return share > 0 && share <= 1 ? share : null;
    } catch { return null; }
  };
  // Сетка колонок — родитель шапки (обе формы пути, panelGridSelector); проценты сетки — от её ширины.
  const sideGridWidth = panel => {
    try {
      // 3.1623: между шапкой и колонкой — обёртки (раздел 2а, PANEL_TITLE_PATHS), в сетке они display: contents
      // и ширины не имеют; сетка — первый предок шапки с шириной.
      let grid = panel?.querySelector?.(".epitaxy-titlebar")?.parentElement;
      let width = grid?.isConnected ? grid.getBoundingClientRect().width : 0;
      while (!(width > 0) && grid?.parentElement && grid !== panel) {
        grid = grid.parentElement;
        width = grid === panel ? 0 : grid.getBoundingClientRect().width;
      }
      return width > 0 ? width : (panel?.getBoundingClientRect?.()?.width ?? 0);
    } catch { return 0; }
  };
  const sideShareFor = (panel, value) => {
    const grid = sideGridWidth(panel);
    return grid > 0 && value > 0 ? Math.min(1, value / grid) : null;
  };
  const chinRow = panel => {
    try { return sideDock(panel)?.querySelector?.(CHIN_ROW_SELECTOR) ?? null; } catch { return null; }
  };
  // Нижняя граница колонки по строке модели (WF68, #6212): натуральная ширина
  // строки — обе группы плюс её собственные поля — плюс зазор между группами
  // плюс обвязка колонки вокруг строки. Обвязка — замер, не константа: ширина
  // колонки (дока минус COLUMN_PULL, на который она выезжает влево) минус ширина
  // строки; сегодня это 12, но держится оно на трёх правилах layoutCss разом.
  // Строки нет или она пуста — SIDE_MIN, как до WF68. Ниже SIDE_FLOOR не
  // опускаемся, сверху режет clamp CSS долей панели.
  // Натуральная ширина узла строки (WF197, #9291): растянутый ребёнок (flex-grow — распорка Claude
  // «flex-1 basis-0» между группами) занимает всё свободное место строки, и его рамка — это ширина
  // колонки, а не нужная строке. До WF197 sideMinFor складывал рамки всех детей вместе с распоркой:
  // минимум выходил равным нынешней ширине, и колонка не уступала при сужении окна («она больше не
  // сжимается»). Растянутый узел — сумма натуральных ширин его детей и зазоров (пустая распорка — 0),
  // нерастянутый — его рамка. top — сам ряд: его рамку не берём никогда, только детей.
  const sideNatural = (node, top = false) => {
    let style = null;
    try { style = getComputedStyle(node); } catch {}
    const grow = Number.parseFloat(style?.flexGrow ?? style?.getPropertyValue?.("flex-grow") ?? "");
    if (!top && !(grow > 0)) return node.getBoundingClientRect?.()?.width ?? 0;
    const kids = [...(node.children ?? [])];
    const gap = Number.parseFloat(style?.columnGap ?? style?.getPropertyValue?.("column-gap") ?? "") || 0;
    let width = kids.reduce((sum, kid) => sum + sideNatural(kid), 0) + gap * Math.max(0, kids.length - 1);
    if (!top && width > 0) {
      width += (Number.parseFloat(style?.getPropertyValue?.("padding-left") ?? "") || 0) +
        (Number.parseFloat(style?.getPropertyValue?.("padding-right") ?? "") || 0);
    }
    return width;
  };
  const sideMinFor = panel => {
    const row = chinRow(panel);
    const dock = sideDock(panel);
    if (!row?.isConnected || row.children.length < 2 || !dock?.isConnected) return SIDE_MIN;
    const rowBox = row.getBoundingClientRect();
    const dockBox = dock.getBoundingClientRect();
    if (rowBox.width <= 0 || dockBox.width <= 0) return SIDE_MIN;
    const content = sideNatural(row, true);
    if (content <= 0) return SIDE_MIN;
    const computed = getComputedStyle(row);
    const padding = (Number.parseFloat(computed.getPropertyValue("padding-left")) || 0) +
      (Number.parseFloat(computed.getPropertyValue("padding-right")) || 0);
    const chrome = dockBox.width - COLUMN_PULL - rowBox.width;
    return Math.max(SIDE_FLOOR, Math.round(content + padding + SIDE_CHIN_GAP + chrome));
  };
  // Действующая нижняя граница — та, что лежит на панели: по ней и CSS, и рейка.
  const sideMinOf = panel => {
    const value = Number.parseFloat(panel?.style?.getPropertyValue(SIDE_MIN_VARIABLE) ?? "");
    return Number.isFinite(value) && value >= SIDE_FLOOR ? value : SIDE_MIN;
  };
  const storeSide = (value, share = null) => {
    try {
      if (value == null) localStorage.removeItem(SIDE_STORAGE_KEY);
      else localStorage.setItem(SIDE_STORAGE_KEY, String(Math.round(value)));
      if (value == null || !(share > 0)) localStorage.removeItem(SIDE_SHARE_STORAGE_KEY);
      else localStorage.setItem(SIDE_SHARE_STORAGE_KEY, String(Math.round(share * 10000) / 10000));
    } catch {}
  };
  const wideState = { on: false, panel: null, dragging: false, grip: 0, gaps: null, langPanel: null, floors: {} };
  // Пол колонки по факту (WF183, слово Элвиса 09.10 03:15: «Не давай уменьшать правую панель меньше, чем
  // можно… пропадает кругляшок с токенами»): ниже SIDE_FLOOR ещё и ширины, при которой встаёт нижняя строка
  // поля с кружком (12з¹, «chin»; замер «nav» блока 12п² снят вместе с блоком, page-60). Каждый замер — сколько
  // точек не хватает (need > 0) или лишних (need < 0) при нынешней ширине колонки (замер доки, не своя
  // переменная — её CSS мог поднять полом); пол = колонка + need. Пол — инлайн-переменной на панель
  // (её берёт clamp сетки) и границей тяги рейки.
  const sideFloorOf = () => Math.max(SIDE_FLOOR, ...Object.values(wideState.floors).filter(Number.isFinite));
  const sideFloorNeed = (kind, need) => {
    const panel = wideState.panel;
    if (!wideState.on || !panel?.isConnected || !Number.isFinite(need)) return;
    const width = sideWidth(panel);
    if (width == null) return;
    wideState.floors[kind] = Math.ceil(width + need);
    sideFloorPaint();
  };
  // Замера больше нет (чат сменился) — его пол снимается.
  const sideFloorDrop = kind => {
    if (!(kind in wideState.floors)) return;
    delete wideState.floors[kind];
    sideFloorPaint();
  };
  const sideFloorPaint = () => {
    const panel = wideState.panel;
    if (!panel?.style) return;
    const floor = sideFloorOf();
    if (floor <= SIDE_FLOOR) { if (panel.style.getPropertyValue(SIDE_FLOOR_VARIABLE)) panel.style.removeProperty(SIDE_FLOOR_VARIABLE); return; }
    const value = `${Math.round(floor)}px`;
    if (panel.style.getPropertyValue(SIDE_FLOOR_VARIABLE) !== value) panel.style.setProperty(SIDE_FLOOR_VARIABLE, value);
  };
  // Инлайн-переменные и атрибут на чужом узле снимаются вместе с экземпляром;
  // следующий прогон вернёт их на первом же проходе (ширину — из хранилища).
  track(() => {
    try { wideState.panel?.style?.removeProperty(SIDE_VARIABLE); } catch {}
    try { wideState.panel?.style?.removeProperty(SIDE_SHARE_VARIABLE); } catch {}
    try { wideState.panel?.style?.removeProperty(SIDE_MIN_VARIABLE); } catch {}
    try { wideState.panel?.style?.removeProperty(SIDE_FLOOR_VARIABLE); } catch {}
    try { wideState.panel?.style?.removeProperty(TITLE_INSET_VARIABLE); } catch {}
    try { titleAlignClear(wideState.panel); } catch {}
    try { clearGaps(wideState.panel); } catch {}
    try { if (wideState.langPanel?.getAttribute("lang") === "ru") wideState.langPanel.removeAttribute("lang"); } catch {}
    try { wideState.panel?.removeAttribute(TITLE_SIDE_ATTRIBUTE); } catch {}
    try { wideState.panel?.removeAttribute(SIDE_TIGHT_ATTRIBUTE); } catch {}
  });
  // Куда класть шапку: панель начинается у левого края окна (попап) — шапка
  // влево, в полосу под кнопками окна; иначе — вправо, над полем ввода. Главное
  // окно (#7913, WF102) — всегда вправо: лента во всю высоту, под кнопками окна
  // затухание (раздел 2ж).
  // Одно правило на два места (WF209): шапку кладёт applyTitleSide, а угол (cornerSpot, место head)
  // спрашивает его же ещё до метки на панели — иначе попап на первом проходе на кадр вставал бы в head.
  const titleGoesLeft = (panel, wide) => wide && !isMainWindow() && panel.getBoundingClientRect().left < TITLEBAR_CLEARANCE_LEFT;
  const applyTitleSide = (panel, wide) => {
    if (!panel) return;
    wideState.panel = panel;
    const left = titleGoesLeft(panel, wide);
    if (!left) {
      if (panel.hasAttribute(TITLE_SIDE_ATTRIBUTE)) panel.removeAttribute(TITLE_SIDE_ATTRIBUTE);
      panel.style.removeProperty(TITLE_INSET_VARIABLE);
      return;
    }
    const inset = `${location.href === "about:blank" ? TITLE_INSET_POPOUT : TITLE_INSET_MAIN}px`;
    if (panel.style.getPropertyValue(TITLE_INSET_VARIABLE) !== inset) panel.style.setProperty(TITLE_INSET_VARIABLE, inset);
    if (panel.getAttribute(TITLE_SIDE_ATTRIBUTE) !== "left") panel.setAttribute(TITLE_SIDE_ATTRIBUTE, "left");
  };
  // #9135: значок шапки колонки — левым краем по тексту поля. Значок — самый левый
  // видимый узел шапки (кнопка, картинка, название); сдвигается её ребёнок, в котором он
  // лежит. Прежний сдвиг из замера вычитаем — проходы сходятся, а не копят. Шапка слева,
  // узкий вид, нет поля — сдвиг снят.
  const titleAlign = { lead: null, shift: null, end: null, title: null, fade: false };
  // Затухание хвоста названия (WF185): метка — только пока текст правда не влез.
  const titleFadeMark = title => {
    if (titleAlign.title && titleAlign.title !== title) { try { titleAlign.title.removeAttribute(TITLE_FADE_ATTRIBUTE); } catch {} }
    titleAlign.title = title ?? null;
    let over = false;
    try { over = Boolean(title) && Number(title.scrollWidth) - Number(title.clientWidth) > 1; } catch {}
    titleAlign.fade = over;
    if (!title) return;
    if (over && !title.hasAttribute(TITLE_FADE_ATTRIBUTE)) title.setAttribute(TITLE_FADE_ATTRIBUTE, "");
    else if (!over && title.hasAttribute(TITLE_FADE_ATTRIBUTE)) title.removeAttribute(TITLE_FADE_ATTRIBUTE);
  };
  const titleAlignClear = panel => {
    try { titleAlign.lead?.removeAttribute?.(TITLE_LEAD_ATTRIBUTE); } catch {}
    titleFadeMark(null);
    titleAlign.lead = null;
    titleAlign.shift = null;
    titleAlign.end = null;
    if (panel?.style?.getPropertyValue(TITLE_SHIFT_VARIABLE)) panel.style.removeProperty(TITLE_SHIFT_VARIABLE);
    if (panel?.style?.getPropertyValue(TITLE_END_VARIABLE)) panel.style.removeProperty(TITLE_END_VARIABLE);
  };
  const applyTitleAlign = (panel, wide, editor) => {
    if (!panel || !wide || panel.getAttribute(TITLE_SIDE_ATTRIBUTE) === "left" || !editor?.isConnected) {
      titleAlignClear(panel);
      return;
    }
    const bar = panel.querySelector(".epitaxy-titlebar");
    let icon = null;
    let iconLeft = Infinity;
    for (const node of bar?.querySelectorAll?.("button, svg, img, [data-pane-title]") ?? []) {
      const box = node.getBoundingClientRect();
      // Название (с WF179 оно первое, #9206) — по началу ТЕКСТА: у кнопки Claude поле внутри.
      let inner = 0;
      if (node.matches?.("[data-pane-title]")) { try { inner = Number.parseFloat(getComputedStyle(node).getPropertyValue("padding-left")) || 0; } catch {} }
      if (box.width > 0 && box.height > 0 && box.left + inner < iconLeft) { icon = node; iconLeft = box.left + inner; }
    }
    let lead = icon;
    while (lead && lead.parentElement !== bar) lead = lead.parentElement;
    const text = editor.getBoundingClientRect();
    if (!lead || !(text.width > 0)) { titleAlignClear(panel); return; }
    let pad = 0;
    try { pad = Number.parseFloat(getComputedStyle(editor).getPropertyValue("padding-left")) || 0; } catch {}
    const applied = titleAlign.lead === lead ? titleAlign.shift ?? 0 : 0;
    const shift = Math.max(0, Math.min(TITLE_SHIFT_MAX, Math.round(text.left + pad - (iconLeft - applied))));
    if (titleAlign.lead !== lead) {
      try { titleAlign.lead?.removeAttribute?.(TITLE_LEAD_ATTRIBUTE); } catch {}
      titleAlign.lead = lead;
    }
    if (!lead.hasAttribute(TITLE_LEAD_ATTRIBUTE)) lead.setAttribute(TITLE_LEAD_ATTRIBUTE, "");
    titleAlign.shift = shift;
    const value = `${shift}px`;
    if (panel.style.getPropertyValue(TITLE_SHIFT_VARIABLE) !== value) panel.style.setProperty(TITLE_SHIFT_VARIABLE, value);
    // WF185 (слово Элвиса 09.10 03:20: «мониторчик — к самому краю, как по выравниванию, отступ от
    // правого края как у всех»): правый край значка Remote Control — по правому краю поля ввода
    // (по нему же стоят «Отправить», кружок лимитов и полоса Рика; замер 09.10: поле 941, значок 961).
    // Прежний отступ из замера вычитаем — проходы сходятся.
    const gutter = bar?.querySelector?.('[data-testid="epitaxy-origin-gutter"]');
    const field = editor.closest?.('[data-cds="ChatComposer"]') ?? null;
    const gutterBox = gutter?.isConnected ? gutter.getBoundingClientRect() : null;
    const fieldBox = field?.isConnected ? field.getBoundingClientRect() : null;
    if (gutterBox && fieldBox && gutterBox.width > 0 && fieldBox.width > 0) {
      const appliedEnd = Number.parseFloat(panel.style.getPropertyValue(TITLE_END_VARIABLE)) || 0;
      const end = Math.max(0, Math.min(TITLE_END_MAX, Math.round(gutterBox.right + appliedEnd - fieldBox.right)));
      titleAlign.end = end;
      const endValue = `${end}px`;
      if (panel.style.getPropertyValue(TITLE_END_VARIABLE) !== endValue) panel.style.setProperty(TITLE_END_VARIABLE, endValue);
    } else if (titleAlign.end != null) {
      titleAlign.end = null;
      panel.style.removeProperty(TITLE_END_VARIABLE);
    }
    titleFadeMark(bar?.querySelector?.("[data-pane-title]") ?? null);
  };
  const applySide = (panel, value, share = null) => {
    if (!panel) return;
    wideState.panel = panel;
    if (value == null) panel.style.removeProperty(SIDE_VARIABLE);
    else panel.style.setProperty(SIDE_VARIABLE, `${Math.round(value)}px`);
    if (value == null || !(share > 0)) panel.style.removeProperty(SIDE_SHARE_VARIABLE);
    else panel.style.setProperty(SIDE_SHARE_VARIABLE, `${Math.round(share * 10000) / 100}%`);
  };
  // Нижняя граница пересчитывается каждый проход: строка модели меняется со
  // сменой модели и эффорта, и колонка обязана следовать за ней в обе стороны.
  // Первый широкий проход меряет строку ещё при границе CSS по умолчанию (300),
  // второй — уже при своей; сходится сразу: группы не ужимаются, обвязка та же.
  const applySideMin = (panel, wide) => {
    if (!panel) return;
    wideState.panel = panel;
    if (!wide) {
      if (panel.style.getPropertyValue(SIDE_MIN_VARIABLE)) panel.style.removeProperty(SIDE_MIN_VARIABLE);
      if (panel.style.getPropertyValue(SIDE_FLOOR_VARIABLE)) panel.style.removeProperty(SIDE_FLOOR_VARIABLE);
      wideState.floors = {};
      if (panel.hasAttribute(SIDE_TIGHT_ATTRIBUTE)) panel.removeAttribute(SIDE_TIGHT_ATTRIBUTE);
      return;
    }
    const side = Number.parseFloat(panel.style.getPropertyValue(SIDE_VARIABLE));
    if (panel.hasAttribute(SIDE_TIGHT_ATTRIBUTE)) {
      if (Number.isFinite(side) && side < sideMinOf(panel)) return;
      panel.removeAttribute(SIDE_TIGHT_ATTRIBUTE);
      return;
    }
    const min = sideMinFor(panel);
    const value = `${min}px`;
    if (panel.style.getPropertyValue(SIDE_MIN_VARIABLE) !== value) panel.style.setProperty(SIDE_MIN_VARIABLE, value);
    if (Number.isFinite(side) && side < min) panel.setAttribute(SIDE_TIGHT_ATTRIBUTE, "");
  };
  // Поля правой колонки (#9148): каждый широкий проход — по полю ленты; узкий вид — снять.
  // С WF163 (33.5) — и просветы трёх столбиков: wideGapsFor по полю ряда, ширине тела ленты
  // и краю боковой панели; итог — четыре переменные на панели и status().layout.gaps.
  const GAP_VARIABLES = [DOCK_INSET_VARIABLE, DOCK_INSET_START_VARIABLE, FEED_START_VARIABLE, FEED_END_VARIABLE];
  const clearGaps = panel => {
    for (const name of GAP_VARIABLES) if (panel?.style?.getPropertyValue(name)) panel.style.removeProperty(name);
  };
  const applyDockInset = (panel, wide) => {
    if (!panel?.style) return;
    if (!wide) { clearGaps(panel); wideState.gaps = null; return; }
    let pad = NaN, column = NaN, menuGap = null;
    try {
      const source = panel.querySelector?.(DOCK_INSET_SOURCE);
      if (source) pad = Number.parseFloat(window.getComputedStyle(source).getPropertyValue("padding-left"));
    } catch { pad = NaN; }
    try {
      const body = panel.querySelector?.(".epitaxy-chat-panel-body")?.getBoundingClientRect?.();
      if (body?.width > 0) {
        column = body.width;
        const aside = document.querySelector("aside.dframe-sidebar");
        const side = aside && !aside.closest?.(".dframe-root[data-collapsed]") ? aside.getBoundingClientRect() : null;
        if (side?.width > 0 && side.right <= body.left + 1) menuGap = body.left - (side.right - MENU_ITEM_INSET);
      }
    } catch {}
    const gaps = wideGapsFor({ pad, column, menuGap });
    wideState.gaps = gaps;
    const values = [gaps.dockEnd, gaps.dockStart, gaps.feedStart, gaps.feedEnd];
    GAP_VARIABLES.forEach((name, index) => {
      const value = `${values[index]}px`;
      if (panel.style.getPropertyValue(name) !== value) panel.style.setProperty(name, value);
    });
  };
  // Переносы по-русски (#9148, 33.5): у страницы Claude lang="en-US", а hyphens: auto берёт
  // словарь по lang — русские слова не переносились бы. Панель чата получает lang="ru";
  // свой lang у панели или русская страница — не трогаем.
  const applyTextLang = panel => {
    try {
      if (!panel?.setAttribute || panel.hasAttribute("lang")) return;
      if (/^ru\b/i.test(document.documentElement?.getAttribute?.("lang") ?? "")) return;
      panel.setAttribute("lang", "ru");
      wideState.langPanel = panel;
    } catch {}
  };
  // Ступени в широком виде выключены: поле стоит на обычной высоте и растёт само
  // вместе с колонкой, ручки нет — свёрнутое поле тут исчезло бы навсегда.
  // Хранилище ступени при этом НЕ переписываем: возврат в узкий вид берёт ступень
  // оттуда, как при инжекте, — поле возвращается таким, каким его оставили.
  const syncWide = wide => {
    if (wide) {
      if (state.stage !== STAGE_NORMAL) {
        const stage = readStoredStage();
        const height = readStoredHeight();
        setStage(STAGE_NORMAL, { silent: true });
        if (stage != null) storeStage(stage);
        storeHeight(height);
      }
    } else if (wideState.on) {
      const stage = readStoredStage();
      if (stage != null && stage !== state.stage) setStage(stage, { silent: true });
    }
    wideState.on = wide;
  };
  // Рейка стоит fixed по координатам, как ручка и полоса: узел живёт в body, а не
  // в дереве Claude (довод раздела 4 — React пересобирает панель, и свой узел
  // внутри неё пришлось бы ловить заново). Место — левая кромка доки, во всю
  // высоту панели; в узком виде рейки нет.
  const placeSideRail = (panel, wide) => {
    if (!wide || !panel) {
      if (rail.style.display !== "none") rail.style.setProperty("display", "none");
      return;
    }
    // Сохранённая ширина ставится ДО замера: после неё колонка уже другая.
    if (!panel.style.getPropertyValue(SIDE_VARIABLE)) {
      const stored = readStoredSide();
      if (stored != null) {
        // Доли ещё нет (ширина выбрана до WF197) — берём её от нынешней сетки и запоминаем.
        let share = readStoredShare();
        if (share == null) { share = sideShareFor(panel, stored); if (share != null) storeSide(stored, share); }
        applySide(panel, stored, share);
      }
    }
    const dock = sideDock(panel);
    const box = dock?.isConnected ? dock.getBoundingClientRect() : null;
    const frame = panel.getBoundingClientRect();
    if (!box || box.width <= 0 || frame.height <= 0) {
      if (rail.style.display !== "none") rail.style.setProperty("display", "none");
      return;
    }
    rail.style.setProperty("display", "block");
    // Рейка — сразу правее полосы прокрутки ленты (#10110: над полосой она забирала её себе, и тянуть ленту было
    // нельзя); прокрутки нет (стенд, чужая сборка) — от кромки доки.
    const scroller = panel.querySelector('[data-testid="epitaxy-virtual-transcript"]');
    const scrollerBox = scroller?.isConnected ? scroller.getBoundingClientRect() : null;
    const railLeft = scrollerBox && scrollerBox.width > 0 ? scrollerBox.right : box.left;
    rail.style.setProperty("left", `${Math.round(railLeft)}px`);
    rail.style.setProperty("top", `${Math.round(frame.top)}px`);
    rail.style.setProperty("height", `${Math.round(frame.height)}px`);
    // Цвет — как у пилюли рейки левой панели (тема красит её text-muted); панели нет
    // (свёрнута, попап) — прежний, а до первого замера — запасной из CSS.
    let tint = "";
    try {
      const pill = document.querySelector(SIDE_RAIL_PILL_SELECTOR);
      if (pill) tint = getComputedStyle(pill).getPropertyValue("color") || getComputedStyle(pill).color || "";
    } catch {}
    if (tint && rail.style.getPropertyValue("color") !== tint) rail.style.setProperty("color", tint);
  };
  // Тяга: ширина колонки = ширина в момент захвата + сдвиг курсора влево, в границах
  // [пол, 60 % панели]. Значение уходит инлайн-переменной на панель, сетка
  // пересчитывается сама; отпустили — в хранилище. Двойной клик — умолчание.
  // До WF176 ширину считали от кромки доки, а дока шире колонки на COLUMN_PULL:
  // каждый захват без движения расширял колонку на 12 — «размер сбился» (#9182).
  const railSide = (panel, x) => {
    const frame = panel.getBoundingClientRect();
    return Math.round(Math.min(frame.width * SIDE_MAX_SHARE, Math.max(sideFloorOf(), wideState.grip - x)));
  };
  // Ширина колонки сейчас: замер доки без её выезда влево (с WF197 колонка бывает ýже своей переменной —
  // уступила долей), нет замера — своя переменная.
  const railColumn = panel => {
    const width = sideWidth(panel);
    if (width != null) return width;
    const own = Number.parseFloat(panel?.style?.getPropertyValue(SIDE_VARIABLE) ?? "");
    return Number.isFinite(own) && own > 0 ? own : null;
  };
  const onRailDown = event => {
    if (event.button !== 0) return;
    const panel = layoutPanel(state.editor);
    if (!panel) return;
    event.preventDefault();
    wideState.dragging = true;
    wideState.panel = panel;
    // grip — «ширина + x» захвата: ширина на ходу = grip − x, без скачка на захвате.
    const column = railColumn(panel);
    wideState.grip = (column ?? panel.getBoundingClientRect().right - event.clientX) + event.clientX;
    rail.dataset.dragging = "true";
    document.documentElement.style.cursor = "col-resize";
    document.documentElement.style.userSelect = "none";
    try { rail.setPointerCapture(event.pointerId); } catch {}
  };
  const onRailMove = event => {
    if (!wideState.dragging) return;
    const panel = wideState.panel;
    if (!panel?.isConnected) return;
    event.preventDefault();
    const value = railSide(panel, event.clientX);
    applySide(panel, value, sideShareFor(panel, value));
    layout();
  };
  const onRailUp = () => {
    if (!wideState.dragging) return;
    wideState.dragging = false;
    rail.dataset.dragging = "false";
    document.documentElement.style.cursor = "";
    document.documentElement.style.userSelect = "";
    const panel = wideState.panel;
    const value = Number.parseFloat(panel?.style?.getPropertyValue(SIDE_VARIABLE) ?? "");
    const share = Number.parseFloat(panel?.style?.getPropertyValue(SIDE_SHARE_VARIABLE) ?? "") / 100;
    if (Number.isFinite(value)) storeSide(value, share);
    scheduleLayout();
  };
  const onRailReset = () => {
    applySide(wideState.panel ?? layoutPanel(state.editor), null);
    storeSide(null);
    layout();
  };
  // Лоадер перечитал файл посреди тяги — курсор и запрет выделения на
  // documentElement сняли бы только по отпусканию, а обработчика уже нет.
  track(() => {
    if (!wideState.dragging) return;
    wideState.dragging = false;
    document.documentElement.style.cursor = "";
    document.documentElement.style.userSelect = "";
  });
  // Широкий вид (#7974): поле ввода в правой колонке — цветом ленты, с рамкой 1 px.
  statusPart("wide", () => ({ on: wideState.on, field: wideState.on ? "line" : null }));

