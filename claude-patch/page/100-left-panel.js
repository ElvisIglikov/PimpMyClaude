  // ---- 2д. Левая панель Claude ýже заводского минимума (#6625) ------------
  // Claude держит ширину боковой панели переменной `--df-sidebar-width` на
  // `.dframe-root` и сам не даёт ей стать меньше 242 (aria-valuemin рейки
  // «Resize sidebar», замер 20.09). Тянут его же рейку левее минимума — ширину
  // ведём мы: своя переменная на корне + правило с !important (инлайновое
  // значение Claude без !important уступает). Пол — кнопка «Hide sidebar» и
  // переключатель Claude/Code вплотную (слово Элвиса: «вплотную, но уже не стоит»).
  // С WF176 (#9182: «левая панель тоже размер не меняет») своя ширина ведётся во
  // всём ходе рейки, до aria-valuemax: раньше за минимумом 242 мы отдавали ширину
  // Claude, а его состояние помнило свои 242 — на границе панель прыгала, а со
  // своей узкой шириной у пола (216) не тянулась вовсе. Двойной клик — Claude.
  const LEFT_ATTRIBUTE = "data-myclaude-left";
  const LEFT_VARIABLE = "--myclaude-left";
  const LEFT_STORAGE_KEY = "myclaude-left-side-v1";
  // #11618: подпись на обоих языках; в querySelector/closest — списком через запятую, без :is (так понимает и стаб тестов).
  const LEFT_RAIL_SELECTOR = '[data-cds="ResizeHandle"][aria-label="Resize sidebar"],[data-cds="ResizeHandle"][aria-label="Изменить размер боковой панели"]';
  const LEFT_BUTTONS_GAP = 4;
  const LEFT_FLOOR_FALLBACK = 190;
  const LEFT_MAX_FALLBACK = 420;
  // forced — ширину держим мы не по тяге, а ради кнопки «PMP» в строке «Hide sidebar» (раздел 12п⁴): не помним её.
  const leftState = { dragging: false, root: null, grip: 0, min: 242, max: LEFT_MAX_FALLBACK, floor: LEFT_FLOOR_FALLBACK, forced: false };
  const leftMaxOf = handle => {
    const max = Number(handle?.getAttribute?.("aria-valuemax"));
    return Number.isFinite(max) && max > 0 ? max : LEFT_MAX_FALLBACK;
  };
  const leftRoot = () => document.querySelector(".dframe-root");
  const applyLeft = (root, value) => {
    if (!root) return;
    leftState.root = root;
    if (value == null) {
      if (root.hasAttribute(LEFT_ATTRIBUTE)) root.removeAttribute(LEFT_ATTRIBUTE);
      root.style.removeProperty(LEFT_VARIABLE);
      return;
    }
    root.style.setProperty(LEFT_VARIABLE, `${Math.round(value)}px`);
    if (!root.hasAttribute(LEFT_ATTRIBUTE)) root.setAttribute(LEFT_ATTRIBUTE, "");
  };
  const readStoredLeft = () => {
    try {
      const stored = Number(localStorage.getItem(LEFT_STORAGE_KEY));
      return Number.isFinite(stored) && stored > 0 ? Math.round(stored) : null;
    } catch { return null; }
  };
  const storeLeft = value => {
    try {
      if (value == null) localStorage.removeItem(LEFT_STORAGE_KEY);
      else localStorage.setItem(LEFT_STORAGE_KEY, String(Math.round(value)));
    } catch {}
  };
  // Пол по живой геометрии: правый край последней кнопки строки окна (панель, назад, вперёд —
  // до WF155 считалась одна «Hide sidebar», и переключатель Claude/Code при 190 заезжал за край
  // панели на ленту, #9146) и переключателя, если он в этой строке (с WF166 он стоит сразу за
  // «вперёд», и пол — его правый край); плюс поле строки справа.
  const LEFT_TITLEBAR_PAD = 8;
  const leftFloor = aside => {
    const box = aside?.getBoundingClientRect();
    const bar = aside?.querySelector?.(".df-titlebar");
    const row = bar?.getBoundingClientRect();
    const ends = [...(bar?.querySelectorAll?.(".df-chrome-btn") ?? [])]
      .map(node => node.getBoundingClientRect()).filter(rect => rect.width > 0).map(rect => rect.right);
    if (!box || box.width <= 0 || !row || !ends.length) return LEFT_FLOOR_FALLBACK;
    let end = Math.max(...ends);
    const mode = bar.querySelector('[role="radiogroup"][aria-label="Mode"],[role="radiogroup"][aria-label="Режим"]')?.getBoundingClientRect();
    if (mode && mode.width > 0 && mode.top < row.bottom && mode.bottom > row.top) end = Math.max(end, mode.right);
    return Math.round(end - box.left + LEFT_TITLEBAR_PAD);
  };
  const onLeftDown = event => {
    if (event.button !== 0) return;
    const handle = event.target?.closest?.(LEFT_RAIL_SELECTOR);
    const root = leftRoot();
    const aside = root?.querySelector("aside.dframe-sidebar");
    if (!handle || !aside) return;
    const min = Number(handle.getAttribute("aria-valuemin"));
    leftState.dragging = true;
    leftState.root = root;
    leftState.min = Number.isFinite(min) && min > 0 ? min : 242;
    leftState.max = Math.max(leftState.min, leftMaxOf(handle));
    let need = 0;
    try { need = dockLeftFloor(aside); } catch { need = 0; }
    leftState.floor = Math.max(Math.min(leftState.min, leftFloor(aside)), need);
    leftState.grip = aside.getBoundingClientRect().right - event.clientX;
  };
  const onLeftMove = event => {
    if (!leftState.dragging) return;
    const root = leftState.root;
    if (!root?.isConnected) return;
    const aside = root.querySelector("aside.dframe-sidebar");
    const width = event.clientX + leftState.grip - (aside?.getBoundingClientRect().left ?? 0);
    applyLeft(root, Math.min(leftState.max, Math.max(leftState.floor, width)));
  };
  const onLeftUp = () => {
    if (!leftState.dragging) return;
    leftState.dragging = false;
    leftState.forced = false;
    const value = Number.parseFloat(leftState.root?.style?.getPropertyValue(LEFT_VARIABLE) ?? "");
    storeLeft(leftState.root?.hasAttribute(LEFT_ATTRIBUTE) && Number.isFinite(value) ? value : null);
    scheduleLayout();
  };
  const onLeftReset = event => {
    if (!event.target?.closest?.(LEFT_RAIL_SELECTOR)) return;
    leftState.forced = false;
    applyLeft(leftRoot(), null);
    storeLeft(null);
  };
  // Сохранённая ширина — на каждом проходе раскладки: корень Claude пересобирает.
  // С WF166 переключатель в строке окна — своя ширина не уже пола: узкая панель (190 до WF166)
  // раздвигается ровно настолько, чтобы переключатель не свешивался на ленту.
  // С WF277 (#10644) у открытой панели в строке «Hide sidebar» стоит кнопка «PMP» панели материалов: панель не ýже,
  // чем нужно ей (dockLeftFloor раздела 12п⁴), — и сверх минимума Claude; своей ширины нет — держим эту, не запоминая.
  const restoreLeft = () => {
    if (leftState.dragging) return;
    const root = leftRoot();
    if (!root) return;
    const aside = root.querySelector("aside.dframe-sidebar");
    const open = Boolean(aside) && !root.hasAttribute("data-collapsed");
    let need = 0;
    try { need = open ? dockLeftFloor(aside) : 0; } catch { need = 0; }
    const own = root.hasAttribute(LEFT_ATTRIBUTE) && !leftState.forced ? Number.parseFloat(root.style.getPropertyValue(LEFT_VARIABLE)) : readStoredLeft();
    if (own == null || !Number.isFinite(own)) {
      if (need > 0 && (leftState.forced || aside.getBoundingClientRect().width < need)) {
        if (Number.parseFloat(root.style.getPropertyValue(LEFT_VARIABLE)) !== need) applyLeft(root, need);
        leftState.forced = true;
      } else if (leftState.forced) { applyLeft(root, null); leftState.forced = false; }
      return;
    }
    leftState.forced = false;
    const floor = open ? leftFloor(aside) : 0;
    const max = Math.max(leftState.min, leftMaxOf(root.querySelector(LEFT_RAIL_SELECTOR)));
    const width = Math.min(max, Math.max(own, Math.min(leftState.min, floor), need));
    if (!root.hasAttribute(LEFT_ATTRIBUTE) || width !== own) applyLeft(root, width);
    if (width !== own && width !== need) storeLeft(width);
  };
  // Переключатель Claude/Code в строке окна (WF166, #9164): левый край — правый край «вперёд»
  // плюс зазор групп, по высоте — по центру кнопок окна; в точках боковой панели (она держит
  // position: absolute). Место — замером, а не числом: в режиме Chat строка у Claude своя.
  const placeModeSwitch = () => {
    const root = document.documentElement.style;
    const put = (name, value) => {
      if (value == null) { if (root.getPropertyValue(name)) root.removeProperty(name); return; }
      if (root.getPropertyValue(name) !== value) root.setProperty(name, value);
    };
    const frame = leftRoot();
    const aside = frame && !frame.hasAttribute("data-collapsed") ? frame.querySelector("aside.dframe-sidebar") : null;
    const back = aside?.querySelector?.('.df-titlebar .df-chrome-btn[aria-label="Forward"],.df-titlebar .df-chrome-btn[aria-label="Вперед"]')?.getBoundingClientRect();
    const mode = aside?.querySelector?.('.df-titlebar [role="radiogroup"][aria-label="Mode"],.df-titlebar [role="radiogroup"][aria-label="Режим"]');
    const box = aside?.getBoundingClientRect();
    if (!mode || !back || !(back.width > 0) || !box) {
      put(SIDE_SWITCH_LEFT_VARIABLE, null);
      put(SIDE_SWITCH_TOP_VARIABLE, null);
      cornerState.switch = null;
      return;
    }
    const left = Math.round(back.right - box.left + LEFT_BUTTONS_GAP);
    const top = Math.round(back.top - box.top + (back.height - MODE_BUTTON) / 2);
    put(SIDE_SWITCH_LEFT_VARIABLE, `${left}px`);
    put(SIDE_SWITCH_TOP_VARIABLE, `${top}px`);
    cornerState.switch = { left, top, size: MODE_BUTTON };
  };
  track(() => {
    const root = document.documentElement.style;
    root.removeProperty(SIDE_SWITCH_LEFT_VARIABLE);
    root.removeProperty(SIDE_SWITCH_TOP_VARIABLE);
  });
  track(() => {
    leftState.dragging = false;
    leftState.forced = false;
    try { applyLeft(leftState.root ?? leftRoot(), null); } catch {}
  });
  HATCH && Object.assign(HATCH, { leftFloor });

