  // ---- 12с¹. Bypass permissions во всех чатах (#9060, WF154) ----------------
  // Слово Элвиса (#9060): «как сделать, чтобы Claude при открытии во всех чатах
  // Bypass permissions всегда делал. У нас такая настройка есть в Пимпе, она не
  // срабатывает». До WF154 настройка `bypassNewChats` доходила только до
  // черновиков, которые открывал сам PMP (`draft-setup` с `mode:"bypass"`, путь
  // А WF126; снят вместе с движком пустого окна, WF248); чаты, открытые в Claude, о ней не знали вовсе. Теперь настройка —
  // у каждой страницы: команда `bypass-chats` с `on:"true"|"false"` (как
  // `hide-tools`), хранится в localStorage, окна сверяются через storage.
  // Включена — в каждом открытом чате (и черновике нового) один раз за открытие:
  // чат простоял BYPASS_SETTLE_MS, кнопка режима под полем видна и не Bypass,
  // меню не открыты, нажималки, сторож режима, черновик PMP и обход Авто-Allow
  // не заняты → меню режима (невидимое, BYPASS_QUIET_ATTRIBUTE) → пункт Bypass.
  // Пункта нет (Bypass в Claude не разрешён) — Escape своему меню, итог no-item.
  // Подтверждение Claude — его не жмём и не закрываем (confirm). Чат, где
  // человек сам выбирал режим (кнопка режима, его меню, ⇧Tab), больше не трогаем
  // до перезагрузки страницы; любое его касание посреди выбора — выбор брошен.
  const BYPASS_KEY = "myclaude.bypassChats";
  const BYPASS_SETTLE_MS = 1200;
  const BYPASS_WAIT_MS = 10000;
  const BYPASS_UNQUIET_MS = 250;
  // Пункт Bypass в меню режима и диалоги, по которым видно подтверждение Claude (WF126).
  const BYPASS_MODE_ITEM = /^(?:bypass(?:\s+permissions)?|обход)/i;
  const BYPASS_DIALOG_SELECTOR = '[role="dialog"], [role="alertdialog"]';
  const bypassDialogs = () => { try { return [...document.querySelectorAll(BYPASS_DIALOG_SELECTOR)]; } catch { return []; } };
  const bypassState = {
    key: null, since: 0, tried: new Set(), user: new Set(), busy: false, token: 0, runs: 0, last: null, timer: 0,
  };
  const bypassOn = () => {
    try { return localStorage.getItem(BYPASS_KEY) === "1"; } catch { return false; }
  };
  // Чат окна: local_… или черновик нового чата (поле есть, id ещё нет).
  const bypassChatKey = () => {
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    if (/^local_[A-Za-z0-9_-]+$/.test(chat || "")) return chat;
    const path = String(location.pathname ?? "");
    if (/local_/.test(path)) return null;
    return state.editor?.isConnected ? `draft:${path}` : null;
  };
  const bypassQuiet = on => {
    if (bypassState.timer) { clearTimeout(bypassState.timer); bypassState.timer = 0; }
    try {
      if (on) document.documentElement.setAttribute(BYPASS_QUIET_ATTRIBUTE, "");
      else document.documentElement.removeAttribute(BYPASS_QUIET_ATTRIBUTE);
    } catch {}
  };
  // Escape — самому меню, а не активному узлу: Escape в поле ввода Claude Code
  // останавливает агента.
  const bypassEscape = () => {
    const menu = modeMenus()[0];
    if (!menu) return;
    try {
      menu.dispatchEvent(new KeyboardEvent("keydown", {
        key: "Escape", code: "Escape", keyCode: 27, which: 27, bubbles: true, cancelable: true,
      }));
    } catch {}
  };
  const bypassDrop = () => {
    bypassState.token += 1;
    bypassState.busy = false;
    bypassQuiet(false);
  };
  const bypassSet = value => {
    try {
      if (value) localStorage.setItem(BYPASS_KEY, "1");
      else localStorage.removeItem(BYPASS_KEY);
    } catch {}
    // Включили заново — открытый сейчас чат тоже получает свою попытку.
    if (value) bypassState.tried.delete(bypassState.key);
    else bypassDrop();
  };
  const bypassEnd = (key, result) => {
    bypassState.last = { chat: key, result, at: Date.now() };
  };
  const bypassRun = async (key, button) => {
    bypassState.busy = true;
    bypassState.runs += 1;
    const token = ++bypassState.token;
    const focus = document.activeElement;
    const live = () => state.alive && bypassState.token === token && bypassOn()
      && bypassChatKey() === key && button.isConnected && nazhModeButton() === button;
    let result = "gone";
    let confirm = false;
    try {
      const before = new Set(bypassDialogs());
      bypassQuiet(true);
      pressLikeMouse(button);
      const find = () => {
        const menus = modeMenus();
        if (menus.length !== 1) return null;
        const items = newWindowMenuItems().filter(node => menus[0].contains(node) && BYPASS_MODE_ITEM.test(newWindowLabel(node)));
        return items.length === 1 ? items[0] : null;
      };
      const item = await nazhWait(find, NAZH_MENU_MS, live);
      if (!live()) return;
      if (!item) {
        // Меню открыто нами и невидимо: закрываем; пункта нет — Bypass не разрешён.
        bypassEscape();
        result = "no-item";
        return;
      }
      for (const dialog of bypassDialogs()) before.add(dialog);
      pressLikeMouse(item);
      const got = await nazhWait(() => {
        if (bypassDialogs().some(dialog => !before.has(dialog) && !dialog.contains?.(item))) return "confirm";
        return chinModeShort(chinText(nazhModeButton())) === "By" ? "ok" : null;
      }, NAZH_MENU_MS, live);
      if (!live()) return;
      if (got === "confirm") { confirm = true; bypassQuiet(false); }
      else if (!got) bypassEscape();
      result = got ?? "not-set";
    } catch {
      result = "fail";
    } finally {
      if (bypassState.token === token) {
        bypassState.busy = false;
        bypassEnd(key, result);
        // Подтверждение Claude — фокус у него; иначе — туда, где он был (поле ввода).
        if (!confirm && result !== "gone") {
          try { if (focus?.isConnected && focus !== document.activeElement) focus.focus({ preventScroll: true }); } catch {}
        }
        // Меню закрывается с анимацией: покажем меню снова, когда её уже нет.
        if (bypassState.timer) clearTimeout(bypassState.timer);
        bypassState.timer = confirm ? 0 : setTimeout(() => { bypassState.timer = 0; if (!bypassState.busy) bypassQuiet(false); }, BYPASS_UNQUIET_MS);
      }
    }
  };
  const bypassTick = t => {
    if (!themable || !state.alive || bypassState.busy) return;
    const key = bypassOn() ? bypassChatKey() : null;
    if (key !== bypassState.key) {
      // Ушли из чата — следующее его открытие снова «открытие».
      if (bypassState.key) bypassState.tried.delete(bypassState.key);
      bypassState.key = key;
      bypassState.since = t;
    }
    if (!key || bypassState.tried.has(key) || bypassState.user.has(key)) return;
    if (t - bypassState.since < BYPASS_SETTLE_MS) return;
    if (nazhState.modeBusy || modeGuard.armed || roamState.phase !== "idle") return;
    const button = nazhModeButton();
    if (!button) {
      if (t - bypassState.since > BYPASS_WAIT_MS) { bypassState.tried.add(key); bypassEnd(key, "no-button"); }
      return;
    }
    if (button.closest?.(COLLAPSED_BLOCK_SELECTOR)) return;
    if (chinModeShort(chinText(button)) === "By") { bypassState.tried.add(key); bypassEnd(key, "already"); return; }
    // Диалоги и поповеры — только видимые (overlayOpen): скрытая своя панель с role="dialog"
    // (настройка глав до WF248) иначе держала Bypass выключенным до перезагрузки страницы.
    if (modeMenus().length || newWindowMenuItems().length || overlayOpen(`${BYPASS_DIALOG_SELECTOR},${CLAUDE_POPUP_SELECTOR}`)) return;
    bypassState.tried.add(key);
    bypassRun(key, button).catch(() => {});
  };
  // Человек сам выбирает режим — этот чат его; любое его касание посреди
  // нашего выбора бросает выбор и возвращает меню на вид.
  const onBypassInput = event => {
    if (event?.isTrusted !== true) return;
    // Своё невидимое меню закрываем: иначе оно встало бы перед человеком.
    if (bypassState.busy) { bypassDrop(); bypassEscape(); }
    const target = event.target;
    const modeButton = target?.closest?.(`${CHIN_SELECTOR} button`);
    const choosing = (modeButton && chinModeShort(chinText(modeButton)))
      || target?.closest?.('[role="menu"], [role="listbox"]')
      || (event.type === "keydown" && event.key === "Tab" && event.shiftKey);
    if (!choosing) return;
    const key = bypassChatKey();
    if (key) bypassState.user.add(key);
  };
  const bypassView = () => ({
    on: bypassOn(), chat: bypassState.key, busy: bypassState.busy, runs: bypassState.runs,
    user: bypassState.user.size, result: bypassState.last?.result ?? null,
  });
  on(window, "storage", event => { if ((event.key === BYPASS_KEY || event.key === null) && !bypassOn()) bypassDrop(); });
  track(bypassDrop);
  // Bypass во всех чатах (раздел 12с¹, #9060): включено ли, чат, итог последней попытки.
  statusPart("bypassChats", () => bypassView());
  HATCH && Object.assign(HATCH, { bypassTick });

