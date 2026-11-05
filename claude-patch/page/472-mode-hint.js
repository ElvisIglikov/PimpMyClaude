  // ---- 12з². Подсказка режима Claude: что делает каждый режим (#6591) ---------
  // Слово Элвиса: «в Мануале объяснить людям надо в Пимпе. Не все же знают, что в Мануале прав больше, люди хотят
  // использовать клауду на полную катушку… не знают про эту фишку с авто». Мышь MODE_HINT_DELAY_MS на кнопке режима
  // под полем (PMP пишет на ней Au/Ac/As/Pl/Bp, раздел 12з¹) или фокус на ней с клавиатуры (Tab) — над кнопкой
  // карточка PMP: пять режимов, что делает каждый, текущий выделен, последней строкой — «в Auto „не могу“ → Ask и
  // Allow». Ничего не нажимает: кнопку и меню Claude не трогает, сторож режима (12с) и Bypass во всех чатах (12с¹) —
  // как были. Уходит, когда мышь (фокус) ушла с кнопки, по нажатию, по клавише и по Escape; Escape, закрывший
  // карточку, глотается на захвате окна — до Claude (в поле Claude Code он останавливает ход) и до сторожа Esc
  // (раздел 16) он не доходит. Открыто меню или поповер — карточки нет; открылось при ней — уходит (сверка раз в
  // MODE_HINT_WATCH_MS, только пока видна). Пока мышь или фокус на кнопке, её title снят (MODE_HINT_HOLD_ATTRIBUTE,
  // chinTitle), а пока карточка видна — спрятаны и подсказки Claude: как у кружка контекста (#6906, «при наведении не
  // надо показывать стандартную подсказку»). Названия — как пункты меню режима Claude (Ask permissions, Accept edits,
  // Plan mode, Auto mode, Bypass permissions); слева — тот же код, что PMP пишет на кнопке.
  const MODE_HINT_ID = "myclaude-mode-hint";
  const MODE_HINT_OPEN_ATTRIBUTE = "data-myclaude-mode-hint-open";
  const MODE_HINT_DELAY_MS = 600;
  const MODE_HINT_WATCH_MS = 250;
  const MODE_HINT_WIDTH = 320;
  const MODE_HINT_GAP = 6;
  const MODE_HINT_EDGE = 8;
  // Открытое меню или поповер Claude (только видимые — overlayOpen). Диалоги не считаем: карточка не должна
  // пропадать из-за окна разрешения, которое ждёт Allow, — там она как раз и нужна.
  const MODE_HINT_POPUP_SELECTOR = '[role="menu"],[role="listbox"],[data-cds="Popover"],[data-radix-popper-content-wrapper] > [data-state="open"]';
  // Клавиши, которые карточку не закрывают: модификаторы и Tab (фокус уйдёт с кнопки — уйдёт и она).
  const MODE_HINT_SOFT_KEYS = new Set(["Shift", "Control", "Alt", "Meta", "CapsLock", "Tab"]);
  const MODE_HINT_ROWS = [
    ["As", "Ask permissions", "Спрашивает разрешение на каждое действие. Медленнее, но Claude может всё, что ты разрешишь."],
    ["Ac", "Accept edits", "Файлы правит сам, команды спрашивает."],
    ["Pl", "Plan mode", "Только думает и пишет план, ничего не меняет."],
    ["Au", "Auto mode", "Сам решает, что можно. Действия «в реальном мире» (кассы, клики мышью, браузер, отправка) робот-сторож молча запрещает."],
    ["By", "Bypass permissions", "Ничего не спрашивает. Только для своих проектов."],
  ];
  const MODE_HINT_TAIL = "Claude в Auto говорит «не могу»? Поставь Ask permissions и жми Allow";
  const modeHint = {
    button: null, hover: false, focus: false, quiet: false, timer: 0, watch: 0, shown: false, mode: null, key: null,
    shows: 0, escapes: 0,
  };
  // Сироты прошлой установки: карточка и метки переживают перезагрузку inject.js.
  try {
    for (const orphan of document.querySelectorAll(`#${MODE_HINT_ID}`)) orphan.remove();
    for (const node of document.querySelectorAll(`[${MODE_HINT_HOLD_ATTRIBUTE}]`)) node.removeAttribute(MODE_HINT_HOLD_ATTRIBUTE);
    document.documentElement.removeAttribute(MODE_HINT_OPEN_ATTRIBUTE);
  } catch {}
  const modeHintNode = document.createElement("div");
  modeHintNode.id = MODE_HINT_ID;
  modeHintNode.setAttribute("role", "tooltip");
  modeHintNode.style.setProperty("display", "none");
  try { (document.body ?? document.documentElement).appendChild(modeHintNode); } catch {}
  track(() => modeHintNode.remove());
  // Кнопка режима под полем: кнопка нижней строки, чей текст — режим (CHIN_MODES; textContent полный и при «Au»).
  const modeHintTarget = node => {
    const button = node?.closest?.(`${CHIN_SELECTOR} button`);
    return button && chinModeShort(chinText(button)) ? button : null;
  };
  // Карточке не место: страница не Claude, кнопки не видно (поле свёрнуто), меню режима открыто — человеком или
  // невидимо сторожами (12с, 12с¹), или открыт другой поповер.
  const modeHintBlocked = button => {
    if (!themable || !state.alive || !button?.isConnected) return true;
    if (button.getAttribute("aria-expanded") === "true" || button.closest?.(COLLAPSED_BLOCK_SELECTOR)) return true;
    if (document.documentElement.hasAttribute(BYPASS_QUIET_ATTRIBUTE)) return true;
    const rect = button.getBoundingClientRect();
    if (!(rect.width > 0 && rect.height > 0)) return true;
    return overlayOpen(MODE_HINT_POPUP_SELECTOR);
  };
  const modeHintRender = code => {
    modeHintNode.textContent = "";
    for (const [key, name, text] of MODE_HINT_ROWS) {
      const row = document.createElement("div");
      row.className = "r";
      row.dataset.mode = key;
      if (key === code) row.setAttribute("aria-current", "true");
      const tag = document.createElement("i");
      tag.textContent = CHIN_MODE_LABELS[key] ?? key;
      const head = document.createElement("b");
      head.textContent = name;
      const line = document.createElement("span");
      line.textContent = text;
      row.append(tag, head, line);
      modeHintNode.append(row);
    }
    const tail = document.createElement("div");
    tail.className = "t";
    tail.textContent = MODE_HINT_TAIL;
    modeHintNode.append(tail);
    modeHint.mode = code;
  };
  // Над кнопкой по её середине, не шире колонки поля (нижней строки) и в пределах окна.
  const modeHintPlace = button => {
    const rect = button.getBoundingClientRect();
    const column = button.closest?.(CHIN_SELECTOR)?.getBoundingClientRect?.();
    const known = Boolean(column && column.width > 0);
    const low = Math.max(MODE_HINT_EDGE, known ? column.left : 0);
    const high = Math.min(innerWidth - MODE_HINT_EDGE, known ? column.right : innerWidth);
    const width = Math.max(0, Math.min(MODE_HINT_WIDTH, high - low));
    const left = Math.max(low, Math.min(rect.left + rect.width / 2 - width / 2, high - width));
    const style = modeHintNode.style;
    style.setProperty("left", `${Math.round(left)}px`);
    style.setProperty("width", `${Math.round(width)}px`);
    style.setProperty("bottom", `${Math.round(innerHeight - rect.top + MODE_HINT_GAP)}px`);
    style.setProperty("max-height", `${Math.max(0, Math.round(rect.top - MODE_HINT_GAP - MODE_HINT_EDGE))}px`);
  };
  const modeHintClear = () => {
    if (modeHint.timer) { clearTimeout(modeHint.timer); modeHint.timer = 0; }
  };
  const modeHintHide = () => {
    if (modeHint.watch) { clearInterval(modeHint.watch); modeHint.watch = 0; }
    if (!modeHint.shown) return false;
    modeHint.shown = false;
    modeHintNode.style.setProperty("display", "none");
    try { document.documentElement.removeAttribute(MODE_HINT_OPEN_ATTRIBUTE); } catch {}
    return true;
  };
  // Нажатие, клавиша, Escape, открытое меню: карточка уходит и до ухода мыши (фокуса) с кнопки не возвращается.
  const modeHintQuiet = () => {
    modeHintClear();
    modeHint.quiet = true;
    return modeHintHide();
  };
  // Пока видна: меню открылось или кнопки не стало — уходит; режим сменился — перерисовка; место — заново.
  const modeHintWatch = () => {
    const button = modeHint.button;
    if (!button || modeHintBlocked(button)) { modeHintQuiet(); return; }
    const code = chinModeShort(chinText(button));
    if (code !== modeHint.mode) modeHintRender(code);
    modeHintPlace(button);
  };
  const modeHintShow = () => {
    const button = modeHint.button;
    if (!button || modeHint.quiet || modeHintBlocked(button)) return false;
    modeHintRender(chinModeShort(chinText(button)));
    modeHintPlace(button);
    modeHintNode.style.setProperty("display", "block");
    try { document.documentElement.setAttribute(MODE_HINT_OPEN_ATTRIBUTE, ""); } catch {}
    if (!modeHint.shown) modeHint.shows += 1;
    modeHint.shown = true;
    if (!modeHint.watch) modeHint.watch = setInterval(() => { try { modeHintWatch(); } catch {} }, MODE_HINT_WATCH_MS);
    return true;
  };
  const modeHintArm = () => {
    if (modeHint.quiet || modeHint.shown || modeHint.timer || !modeHint.button) return;
    modeHint.timer = setTimeout(() => { modeHint.timer = 0; try { modeHintShow(); } catch {} }, MODE_HINT_DELAY_MS);
  };
  // Кнопку отпустили: карточки нет, метка снята, подсказку браузера вернёт ближайший проход раскладки (markChin).
  const modeHintRelease = () => {
    const button = modeHint.button;
    modeHintClear();
    modeHintHide();
    Object.assign(modeHint, { button: null, hover: false, focus: false, quiet: false });
    if (!button) return;
    try { button.removeAttribute(MODE_HINT_HOLD_ATTRIBUTE); } catch {}
    try { scheduleLayout(); } catch {}
  };
  const modeHintEnter = (button, how) => {
    if (modeHint.button !== button) {
      modeHintRelease();
      modeHint.button = button;
      try { button.setAttribute(MODE_HINT_HOLD_ATTRIBUTE, ""); chinTitle(button, null); } catch {}
    }
    modeHint[how] = true;
    modeHintArm();
  };
  const modeHintLeave = how => {
    modeHint[how] = false;
    if (!modeHint.hover && !modeHint.focus) modeHintRelease();
  };
  // Только руки человека: «как мышью» сторожей (pressLikeMouse) шлёт pointerover и нажатие без isTrusted.
  const onModeHintOver = event => {
    if (event?.isTrusted !== true || !themable) return;
    const button = modeHintTarget(event.target);
    if (button) { modeHintEnter(button, "hover"); return; }
    // Уход с кнопки потерялся (React заменил узел) — первый же заход мыши на другое его и закрывает.
    if (modeHint.hover && !modeHint.button?.contains?.(event.target)) modeHintLeave("hover");
  };
  const onModeHintOut = event => {
    const button = modeHint.button;
    if (event?.isTrusted !== true || !button || !modeHint.hover || !button.contains?.(event.target)) return;
    const next = event.relatedTarget;
    if (next && button.contains?.(next)) return;
    modeHintLeave("hover");
  };
  // Фокус с клавиатуры — только приход по Tab: фокус, который Claude возвращает на кнопку после меню, — не просьба.
  const onModeHintFocus = event => {
    if (event?.isTrusted !== true || !themable) return;
    const button = modeHintTarget(event.target);
    if (event.type === "focusin") {
      if (button && modeHint.key === "Tab") modeHintEnter(button, "focus");
      return;
    }
    if (modeHint.focus && button && button === modeHint.button) modeHintLeave("focus");
  };
  const onModeHintPress = event => {
    if (event?.isTrusted !== true) return;
    modeHint.key = null;
    if (modeHint.button) modeHintQuiet();
  };
  const onModeHintKey = event => {
    if (event?.isTrusted !== true) return;
    modeHint.key = event.key;
    if (!modeHint.button || MODE_HINT_SOFT_KEYS.has(event.key)) return;
    const shown = modeHintQuiet();
    if (event.key !== "Escape" || !shown) return;
    modeHint.escapes += 1;
    event.preventDefault();
    event.stopImmediatePropagation();
  };
  // Escape карточки — первым на захвате окна: раньше сторожа Esc (раздел 16) и слушателей Claude.
  on(window, "keydown", onModeHintKey, true);
  on(window, "pointerdown", onModeHintPress, true);
  on(document, "pointerover", onModeHintOver, true);
  on(document, "pointerout", onModeHintOut, true);
  on(document, "focusin", onModeHintFocus, true);
  on(document, "focusout", onModeHintFocus, true);
  on(window, "blur", () => modeHintRelease());
  on(window, "resize", () => modeHintRelease());
  track(() => {
    modeHintClear();
    modeHintHide();
    try { modeHint.button?.removeAttribute(MODE_HINT_HOLD_ATTRIBUTE); } catch {}
    modeHint.button = null;
  });
  // Цвета — переменные темы Claude; текущий режим — подложка цветом акцента. Пока карточка видна, подсказки Claude
  // спрятаны (правило как у кружка, раздел 4).
  lateRules.push(
    `#${MODE_HINT_ID}{position:fixed;z-index:2147483646;box-sizing:border-box;overflow:hidden;padding:5px;border:1px solid var(--cds-border,rgba(127,127,127,.35));border-radius:10px;background:var(--cds-surface-3,#2b2a27);color:var(--cds-text-primary,#f5f4ef);font-size:12px;line-height:16px;font-weight:400;text-align:left;white-space:normal;pointer-events:none;box-shadow:0 8px 28px rgba(0,0,0,.32)}`,
    `#${MODE_HINT_ID}>.r{display:grid;grid-template-columns:18px minmax(0,1fr);column-gap:6px;padding:4px 6px;border-radius:6px}`,
    `#${MODE_HINT_ID}>.r>i{grid-column:1;grid-row:1/span 2;font-style:normal;font-weight:600;color:var(--cds-text-secondary,#a8a6a0)}`,
    `#${MODE_HINT_ID}>.r>b{grid-column:2;font-weight:600}`,
    `#${MODE_HINT_ID}>.r>span{grid-column:2;color:var(--cds-text-secondary,#a8a6a0)}`,
    `#${MODE_HINT_ID}>.r[aria-current]{background:color-mix(in srgb,var(--cds-text-accent,#d97757) 16%,transparent)}`,
    `#${MODE_HINT_ID}>.r[aria-current]>i{color:var(--cds-text-accent,#d97757)}`,
    `#${MODE_HINT_ID}>.t{margin:4px 6px 0;padding:6px 0 2px;border-top:1px solid var(--cds-border,rgba(127,127,127,.35))}`,
    `html[${MODE_HINT_OPEN_ATTRIBUTE}] [data-cds="Tooltip"],html[${MODE_HINT_OPEN_ATTRIBUTE}] [role="tooltip"]:not(#${MODE_HINT_ID}){display:none !important}`,
  );
  // Подсказка режима (раздел 12з², #6591): видна ли, какой режим в ней выделен, сколько раз показана, сколько Escape закрыли её.
  statusPart("modeHint", () => ({ shown: modeHint.shown, mode: modeHint.shown ? modeHint.mode : null, shows: modeHint.shows, escapes: modeHint.escapes }));
  HATCH && Object.assign(HATCH, { modeHint });
