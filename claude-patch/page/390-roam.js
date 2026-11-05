  // ---- 12е, продолжение. Обход чатов списка слева (#7099, WF82) ------------
  // Слово Элвиса 23.09 ~02:10: «чтобы Авто-Allow работало, перемещаясь по
  // чатам, иначе работа встанет». Карточку разрешения тик выше видит только в
  // чате, открытом в ЭТОМ окне, а чат в списке слева ждёт Элвиса до утра.
  // Поэтому главное окно, пока его никто не трогает, само заходит в ждущий
  // чат, ждёт, пока тик выше нажмёт Allow, и возвращается в прежний.
  //
  // Кто ждёт разрешения (разведка WF82, 2.2553.13). У строки сайдбара
  // `[data-row-key="code:local_<id>"]` в React-волокне, в 14–15 прыжках вверх,
  // лежит пропс `session` с полем hasPendingApproval. Claude ставит его по
  // своему стору разрешений: id чата → запросы с именем инструмента.
  // liveStatus "awaiting" и pendingPermissions у чата Claude Code значат ещё и
  // «ждёт ответа» и «прочитай итог» — на них не идём. Метку сверяем со стором
  // и идём, только если среди запросов есть инструмент. Вопрос
  // (AskUserQuestion) и план (ExitPlanMode) нажимает только человек.
  //
  // Метку сверяем со стором, только когда он о чате что-то знает: стор
  // разрешений заполнен лишь для чата, открытого в окне (живой замер 23.09
  // 12:22 — чат слева с pendingPermissions: 1, а в сторе пусто), и сверка
  // «метка без запроса» не пускала обход никуда. Незнакомый чат навещаем:
  // там стор уже знает, что ждёт, — вопрос или план, и окно сразу уходит
  // назад, а Allow тик выше нажмёт сам.
  //
  // Правила — критик WF82, п. 2–12. Сначала «сухой» режим: status пишет, куда
  // и почему окно пошло бы, но ничего не нажимает. Слово Элвиса 23.09 ~12:10:
  // «не по 30 минут ждал… сразу переключается… тац-тац-тац — и готово», — поэтому
  // окно без фокуса ждёт 1,5 с тишины мыши, с фокусом — 3 с тишины всего.
  // Черновик в поле чата не помеха: Claude хранит его сам по чату
  // (localStorage composer-draft:epitaxy-local_<id>, замер 23.09) и вернёт; на
  // домашнем экране черновик держит обход, как раньше. Не идём в
  // попап, в чат этого окна, при «Новом окне», свежем «Обкэшить» и открытом
  // меню. Щит глушит ввод на время обхода. Возврат — строкой сайдбара, иначе
  // историей по ключу записи. Весь обход — не дольше 10 с. Нет кнопки — к этому чату не
  // возвращаемся, пока метка не сменится. Три пустых обхода подряд выключают
  // обход до переинжекта. Своего таймера у обхода нет: он шагает тиком выше.
  //
  // Выключатель — ключ в localStorage, а не свойство окна: свойство слетает с
  // каждым cp и перезагрузкой, и выключить обход было бы нечем. Значения:
  // "on" — обход, "dry" — сухой, "off" — выключен; ключа нет — умолчание ниже.
  const ROAM_MODE_KEY = "myclaude-auto-allow-roam";
  const ROAM_MODES = new Set(["on", "dry", "off"]);
  const ROAM_DEFAULT_MODE = "on";
  // Замок между окнами: {chat, owner, at}. Пока метка свежа, чужое окно не идёт никуда.
  const ROAM_LOCK_KEY = "myclaude-auto-allow-roam-lock";
  const ROAM_LOCK_MS = 15000;
  // Список слева читаем не чаще, чем раз в столько. Метка обязана пережить два
  // прочтения подряд: мигнувшая и тут же снятая — не повод уводить окно.
  const ROAM_SCAN_MS = 1200;
  const ROAM_IDLE_BLUR_MS = 1500;
  const ROAM_IDLE_FOCUS_MS = 3000;
  const ROAM_NAV_MS = 2000;
  const ROAM_BUTTON_MS = 4000;
  // После нажатия стоим ещё: Claude часто просит разрешение второй раз подряд.
  const ROAM_LINGER_MS = 1800;
  const ROAM_MAX_MS = 10000;
  // Из B в C идём, только если обход моложе этого; чатов за заход — не больше двух.
  const ROAM_NEXT_MS = 5000;
  const ROAM_MAX_TARGETS = 2;
  const ROAM_EMPTY_LIMIT = 3;
  const ROAM_STORE_RETRY_MS = 60000;
  const ROAM_FIBER_DEPTH = 24;
  const ROAM_LOG_MAX = 5;
  const ROAM_HUMAN_TOOLS = new Set(["AskUserQuestion", "ExitPlanMode"]);
  const ROAM_SIDEBAR_SELECTOR = '[data-testid="sidebar"]';
  const ROAM_ROW_SELECTOR = '[data-row-key^="code:local_"]';
  // Кнопка перехода строки. У строки есть и кнопки действий («…», архив,
  // закрепить) — по ним обход не щёлкает никогда.
  const ROAM_MAIN_BUTTON_SELECTOR = "[data-row-main-button]";
  const ROAM_OVERLAY_SELECTOR = '[role="menu"],[role="listbox"],[role="dialog"],[role="alertdialog"],[cmdk-root]';
  // Обход ходит только с экрана Claude Code: домашний экран или чат local_<id>.
  const ROAM_CODE_PATH_RE = /^\/epitaxy(\/local_[^/]+)?\/?$/;
  const roamState = {
    phase: "idle", reason: "", disabled: "",
    chat: null, title: "", from: null, fromId: "", fromTitle: "", since: 0, phaseAt: 0,
    lengthBefore: 0, fromKey: "", token: 0, startCount: 0, seenCount: 0, visited: [], titles: [],
    scroll: null, bText: null, why: "", via: "", polling: false,
    roams: 0, dryRuns: 0, empty: 0, lastRoam: null, skipped: [], waiting: [],
    scanAt: -Infinity, seen: new Map(), noted: new Set(), noButton: new Set(), blockedRequests: new Map(),
    storeScanAt: -Infinity, storeScan: null, deferred: [], unrendered: 0,
    input: { key: 0, pointer: 0 },
  };
  // Инжект — тоже «рука на окне»: после каждого cp обход сперва выжидает.
  roamState.input.key = roamState.input.pointer = autoAllowNow();
  const setAutoAllowClock = fn => {
    autoAllowClock = typeof fn === "function" ? fn : () => Date.now();
    roamState.input.key = roamState.input.pointer = autoAllowNow();
  };
  const roamOwner = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
  const roamIso = t => { try { return new Date(t).toISOString(); } catch { return null; } };
  const roamShort = text => { const value = String(text ?? "").trim(); return value.length > 40 ? `${value.slice(0, 39)}…` : value; };
  const roamMode = () => {
    try {
      const value = localStorage.getItem(ROAM_MODE_KEY);
      if (value && ROAM_MODES.has(value)) return value;
    } catch {}
    return ROAM_DEFAULT_MODE;
  };

  const roamLockRead = () => {
    try {
      const value = JSON.parse(localStorage.getItem(ROAM_LOCK_KEY) ?? "null");
      return value && typeof value === "object" ? value : null;
    } catch { return null; }
  };
  const roamLockForeign = t => {
    const held = roamLockRead();
    return Boolean(held && held.owner !== roamOwner && t - Number(held.at) < ROAM_LOCK_MS);
  };
  // Взять или продлить. Перечитываем после записи: окна пишут в одно хранилище.
  const roamLockTake = (chat, t) => {
    if (roamLockForeign(t)) return false;
    try { localStorage.setItem(ROAM_LOCK_KEY, JSON.stringify({ chat, owner: roamOwner, at: t })); } catch { return false; }
    return roamLockRead()?.owner === roamOwner;
  };
  const roamLockDrop = () => {
    if (roamLockRead()?.owner !== roamOwner) return;
    try { localStorage.removeItem(ROAM_LOCK_KEY); } catch {}
  };

  // Сессия строки из её React-волокна (chatFiberOf — раздел 12в).
  const roamSession = (row, id) => {
    let fiber = chatFiberOf(row);
    for (let hop = 0; fiber && hop <= ROAM_FIBER_DEPTH; hop += 1, fiber = fiber.return) {
      const session = fiber.memoizedProps?.session;
      if (session && typeof session === "object" && session.ref?.id === id) return session;
    }
    return null;
  };
  // Ждущие чаты списка слева: [{id, title}]; null — самого списка не видно.
  // Строки — из ЛЮБОЙ группы (#7112): недавние, Pinned, группы проектов.
  // Строка есть, а размера нет (свёрнутая группа) — чат ждёт, но зайти в него
  // нечем: считаем в roamState.unrendered и называем причиной в status().
  const roamWaiting = () => {
    const rows = [...document.querySelectorAll(ROAM_ROW_SELECTOR)];
    if (!rows.length && !document.querySelector(ROAM_SIDEBAR_SELECTOR)) return null;
    const found = new Map();
    const shown = new Set();
    for (const row of rows) {
      const id = String(row.getAttribute("data-row-key") ?? "").split(":").pop() ?? "";
      if (!id.startsWith("local_")) continue;
      if (!found.has(id)) {
        const session = roamSession(row, id);
        if (session?.hasPendingApproval !== true) continue;
        found.set(id, { id, title: String(session.title ?? "").trim() || newWindowRowTitle(row) });
      }
      if (newWindowRowShown(row)) shown.add(id);
    }
    roamState.unrendered = [...found.keys()].filter(id => !shown.has(id)).length;
    return [...found.values()];
  };
  // Метка у чата пропала — всё, что мы о нём помнили, забываем: появится снова
  // — это новый запрос (и чат, где кнопки не было, снова можно навестить).
  const roamTrack = (waiting, t) => {
    const ids = new Set(waiting.map(item => item.id));
    for (const id of [...roamState.seen.keys()]) if (!ids.has(id)) roamState.seen.delete(id);
    for (const [id, blocked] of roamState.blockedRequests) {
      if (!ids.has(id) || blocked.permissions !== roamPermissionStamp(id)) {
        roamState.blockedRequests.delete(id);
        for (const key of [...roamState.noted]) if (key.startsWith(`${id}|`)) roamState.noted.delete(key);
      }
    }
    for (const id of [...roamState.noButton]) if (!ids.has(id)) roamState.noButton.delete(id);
    for (const key of [...roamState.noted]) if (!ids.has(key.split("|")[0])) roamState.noted.delete(key);
    for (const item of waiting) if (!roamState.seen.has(item.id)) roamState.seen.set(item.id, t);
    roamState.waiting = waiting.slice(0, ROAM_LOG_MAX).map(item => ({ id: item.id, title: item.title }));
  };

  // Сторы claude.ai ищутся тем же обходом модулей, что у «Нового окна»: стор
  // попапов — ради исключения «чат в отдельном окне», стор разрешений — ради
  // сверки метки. Без любого из них обход не идёт никуда.
  let roamPermStore = null;
  const roamPermStoreOk = store => {
    try {
      const value = store?.getState?.();
      return Boolean(value && value.permissionsBySessionId && typeof value.permissionsBySessionId === "object"
        && typeof value.addPermission === "function");
    } catch { return false; }
  };
  const roamStoresReady = () => newWindowStoreOk(newWindowStore) && roamPermStoreOk(roamPermStore);
  const roamFindStores = t => {
    if (roamState.storeScan || t - roamState.storeScanAt < ROAM_STORE_RETRY_MS) return;
    roamState.storeScanAt = t;
    // Токен ТЕКУЩИЙ и не растёт: начнётся «Новое окно» — скан бросит работу сам.
    const token = newWindowToken;
    const run = (async () => {
      try { await newWindowFindStore(token); } catch {}
      if (roamPermStoreOk(roamPermStore)) return;
      try {
        const found = await newWindowScanStores(token, roamPermStoreOk);
        if (found) roamPermStore = found;
      } catch {}
    })();
    const done = () => { roamState.storeScan = null; };
    roamState.storeScan = run.then(done, done);
  };
  // Что ждёт в чате по стору разрешений: "" — идём, иначе причина словом.
  // Пусто — стор этот чат не слушает (он не открыт): идём смотреть.
  // Непрозрачный отпечаток очереди только для снятия дедупликации, не для Allow.
  const roamPermissionStamp = id => {
    try { return JSON.stringify(roamPermStore?.getState?.()?.permissionsBySessionId?.[id] ?? null); }
    catch { return null; }
  };
  const roamVerdict = id => {
    let list = null;
    try { list = roamPermStore?.getState?.()?.permissionsBySessionId?.[id]; } catch { list = null; }
    const tools = (Array.isArray(list) ? list : [])
      .filter(item => item && typeof item === "object" && (item.status == null || item.status === "pending"))
      .map(item => String(item.toolName ?? ""));
    if (!tools.length) return { reason: "", tools };
    if (tools.some(tool => tool && !ROAM_HUMAN_TOOLS.has(tool))) return { reason: "", tools };
    if (tools.includes("AskUserQuestion")) return { reason: "вопрос человеку", tools };
    if (tools.includes("ExitPlanMode")) return { reason: "план на одобрение", tools };
    return { reason: "непонятная метка", tools };
  };
  // Пропуск пишется раз на метку: иначе каждый круг забивал бы журнал одним и тем же.
  const roamSkip = (item, reason, t) => {
    const key = `${item.id}|${reason}`;
    if (roamState.noted.has(key)) return;
    roamState.noted.add(key);
    roamState.skipped.unshift({ at: roamIso(t), chat: item.id, title: item.title, reason });
    roamState.skipped.length = Math.min(roamState.skipped.length, ROAM_LOG_MAX);
  };
  const roamButton = id => {
    const row = newWindowRow(id, true);
    if (!row) return null;
    const box = row.getBoundingClientRect();
    if (!(box.width > 0 && box.height > 0)) return null;
    return row.querySelector(ROAM_MAIN_BUTTON_SELECTOR);
  };
  // Куда идти: самый давно ждущий из тех, куда можно. exclude — где уже были.
  const roamPick = (t, waiting, exclude) => {
    const here = newWindowSessionId();
    let popouts = null;
    try { popouts = newWindowStore?.getState?.()?.popoutWindows; } catch { popouts = null; }
    if (!(popouts instanceof Map)) return null;
    const order = waiting.slice().sort((a, b) => (roamState.seen.get(a.id) ?? t) - (roamState.seen.get(b.id) ?? t));
    for (const item of order) {
      if (item.id === here || exclude.includes(item.id) || roamState.noButton.has(item.id) || roamState.blockedRequests.has(item.id)) continue;
      // Чат в отдельном окне жмёт тик 12е самого попапа, а щелчок по его строке
      // поднял бы чужое окно.
      if (popouts.has(item.id)) { roamSkip(item, "в отдельном окне", t); continue; }
      const verdict = roamVerdict(item.id);
      if (verdict.reason) { roamSkip(item, verdict.reason, t); continue; }
      if (t - (roamState.seen.get(item.id) ?? t) < ROAM_SCAN_MS) continue;
      if (!roamButton(item.id)) { roamSkip(item, newWindowRow(item.id, true) ? "строка не отрисована" : "строки нет", t); continue; }
      return { ...item, tools: verdict.tools };
    }
    return null;
  };

  // Можно ли уводить окно прямо сейчас: "" — можно, иначе причина словом.
  const roamComposer = () => {
    const editor = state.editor?.isConnected ? state.editor : document.querySelector(NEW_WINDOW_INPUT_SELECTOR);
    return editor?.isConnected ? editor : null;
  };
  // Текст поля того чата, где окно сейчас: по нему видно, не легло ли что-то в B.
  // null — поля нет: Claude мог спрятать его на время карточки разрешения, и
  // пустая строка на этом месте легла бы ложной базой (проверяющий WF82).
  const roamComposerText = () => {
    try {
      const editor = document.querySelector(NEW_WINDOW_INPUT_SELECTOR) ?? state.editor;
      return editor?.isConnected ? editorText(editor) : null;
    } catch { return null; }
  };
  // Лёг ли в поле B чужой текст. Поле, которого не было, при первом появлении
  // даёт новую базу: Claude возвращает его с сохранённым черновиком B.
  const roamBTextChanged = () => {
    const text = roamComposerText();
    if (text == null) return false;
    if (roamState.bText == null) { roamState.bText = text; return false; }
    return text !== roamState.bText;
  };
  // Запись «Обкэшить» и её штамп живут по своим часам — стенным Date.now().
  const roamCashoutFresh = () => {
    const record = readCashout();
    if (!record) return false;
    const wall = Date.now();
    return wall - record.at < CASHOUT_FRESH_MS
      || (record.stampedAt != null && wall - record.stampedAt < CASHOUT_STAMP_FRESH_MS);
  };
  const roamBlocker = t => {
    if (!ROAM_CODE_PATH_RE.test(location.pathname)) return "не экран Claude Code";
    // Свёрнутый сайдбар (⌘B, живой замер 23.09 04:25) — всплывашка у края окна:
    // она inert, но строки в ней есть и с размерами, а программному click() inert
    // не мешает (тот же приём у 12б). У Элвиса список свёрнут почти всегда — ходим
    // и по нему (решение оркестратора WF82 на гейте, #7099 «(⌘B)»).
    if (state.newWindow?.busy === true) return "идёт «Новое окно»";
    if (roamCashoutFresh()) return "свежий «Обкэшить»";
    try { if (document.querySelector(ROAM_OVERLAY_SELECTOR)) return "открыто меню"; } catch {}
    const editor = roamComposer();
    if (!editor) return "поле ввода не найдено";
    if (location.pathname === NEW_WINDOW_HOME_PATH && composerFilled(editor)) return "в поле черновик";
    let focused = false;
    try { focused = document.hasFocus(); } catch {}
    if (focused && t - Math.max(roamState.input.key, roamState.input.pointer) < ROAM_IDLE_FOCUS_MS) return "окно в работе";
    if (!focused && t - roamState.input.pointer < ROAM_IDLE_BLUR_MS) return "мышь над окном";
    if (roamLockForeign(t)) return "обход идёт в другом окне";
    return "";
  };

  // Лента A: где стоял Элвис — туда её и вернуть (разделы 13 и 12е).
  const roamScrollSave = () => {
    try {
      const node = findScroller();
      if (!node?.isConnected) return null;
      const top = Number(node.scrollTop) || 0;
      return { top, bottom: scrollRoom(node) - top <= 4 };
    } catch { return null; }
  };
  const roamScrollRestore = saved => {
    if (!saved) return;
    const path = location.pathname, entry = navEntryKey(), input = { ...roamState.input };
    const apply = () => {
      if (!state.alive || roamState.phase !== "idle" || location.pathname !== path || navEntryKey() !== entry
        || roamState.input.key !== input.key || roamState.input.pointer !== input.pointer) return;
      try {
        const node = findScroller();
        if (!node?.isConnected) return;
        if (saved.bottom) scrollDown(node); else node.scrollTop = saved.top;
      } catch {}
    };
    apply();
    // Лента A дорисовывается не сразу: доводим ещё дважды.
    newWindowLater(apply, 300);
    newWindowLater(apply, 900);
  };

  const roamDisable = why => {
    roamState.disabled = why;
    autoAllowNote("navigation", "unknown", []);
  };
  // Конец обхода: где бы ни кончился, замок и щит снимаются; отложенные
  // команды исполняются, только если окно вернулось в A. stayed — остались в B
  // нарочно (в поле B лёг текст).
  const roamFinish = (t, stayed = false) => {
    if (roamState.phase === "idle") return;
    const home = !stayed && location.pathname === roamState.from;
    const presses = autoAllowState.pressCount - roamState.startCount;
    roamState.phase = "idle";
    roamState.polling = false;
    roamLockDrop();
    roamState.roams += 1;
    roamState.lastRoam = {
      at: roamIso(roamState.since), chats: roamState.visited.slice(), titles: roamState.titles.slice(),
      from: roamState.from, presses, why: roamState.why,
      back: stayed ? "stay" : home ? roamState.via : "back-failed", ms: Math.round(t - roamState.since),
    };
    roamState.reason = stayed ? "остался в чате: в поле появился текст" : home ? "вернулся" : "не вернулся";
    if (home) roamScrollRestore(roamState.scroll);
    // Чат с вопросом или планом (кнопки Allow нет) — честный пустой заход, не сбой.
    if (presses > 0) roamState.empty = 0;
    else if (!roamState.visited.some(id => roamState.noButton.has(id) || roamState.blockedRequests.has(id))) {
      roamState.empty += 1;
      if (roamState.empty >= ROAM_EMPTY_LIMIT) roamDisable("три пустых обхода подряд");
    }
    if (!stayed && !home) {
      roamDisable("не вернулся в прежний чат");
      autoAllowToast(`PMP не смог вернуться в «${roamShort(roamState.fromTitle)}» — обход чатов выключен`, 8000);
    }
    // Окно не в A — команду отменяем вслух (проверяющий WF82): «В отдельное
    // окно» вынесло бы чужой B, «Workflow» лёг бы в его поле, «Обкэшить» взял
    // бы его ответ. Плашка раздела 12б — выше тоста обхода, он не затирается.
    const deferred = roamState.deferred.splice(0);
    if (home) for (const run of deferred) { try { run(); } catch {} }
    else if (deferred.length) newWindowNote("Команда отменена: окно не в прежнем чате");
  };
  const roamNavigateBack = () => {
    // С домашнего экрана — только историей: строки у /epitaxy нет.
    const button = roamState.fromId ? newWindowRow(roamState.fromId, true)?.querySelector?.(ROAM_MAIN_BUTTON_SELECTOR) : null;
    if (button) {
      try { button.click(); return "row"; } catch {}
    }
    return roamHistoryBack() ? "history" : "none";
  };
  // Запасной путь — история. Шаги по history.length тут не считаются: Chromium
  // держит не больше 50 записей, у живого главного окна их ровно 50 (замер
  // проверяющего WF82, 23.09 05:32), и после перехода длина не растёт. Поэтому
  // на старте обхода запоминаем ключ записи A (Navigation API) и идём ровно в
  // неё. Без API — прежний счёт по длине, как у newWindowBack. history.go(0) —
  // перезагрузка, а не шаг; pushState портит служебное состояние роутера (12б).
  // Сам ход — общий с возвратом раздела 12б (navBackTo, #7113).
  const roamEntryKey = navEntryKey;
  const roamHistoryBack = () => navBackTo({ key: roamState.fromKey, length: roamState.lengthBefore });
  const roamBack = (why, t = autoAllowNow()) => {
    const phase = roamState.phase;
    if (phase === "idle" || phase === "back") return;
    roamState.why = why;
    // В поле B за обход что-то легло (щит глушит клавиши, но не всё на свете) —
    // уводить окно из-под этого текста нельзя.
    if ((phase === "wait" || phase === "linger") && roamBTextChanged()) {
      autoAllowToast(`В поле «${roamShort(roamState.title)}» появился текст — PMP остался здесь`, 6000);
      roamFinish(t, true);
      return;
    }
    roamState.phase = "back";
    roamState.phaseAt = t;
    // Щелчок по строке B уже был, а адрес ещё прежний: переход у Claude бывает
    // отложенным (в сторе адреса есть pendingPathname), и окно может уехать в B
    // уже после нашего «вернулись». Ждём: доедет в B — вернём, нет — не уходили.
    if (phase === "go" && location.pathname === roamState.from) { roamState.via = "pending"; return; }
    if (location.pathname === roamState.from) { roamState.via = "never"; roamFinish(t); return; }
    roamState.via = roamNavigateBack();
  };
  // Возврат дошёл? Строка не довела за секунду — пробуем историей, за две — сдаёмся.
  const roamBackCheck = t => {
    if (roamState.phase !== "back") return true;
    if (roamState.via === "pending") {
      if (location.pathname !== roamState.from) { roamState.via = roamNavigateBack(); roamState.phaseAt = t; return false; }
      if (t - roamState.phaseAt <= ROAM_NAV_MS) return false;
      // Окно так и не ушло из A: возвращаться было некуда.
      roamState.via = "never";
      roamFinish(t);
      return true;
    }
    if (location.pathname === roamState.from) { roamFinish(t); return true; }
    if (roamState.via === "row" && t - roamState.phaseAt > ROAM_NAV_MS / 2 && roamHistoryBack()) {
      roamState.via = "history";
      roamState.phaseAt = t;
      return false;
    }
    if (t - roamState.phaseAt > ROAM_NAV_MS) { roamFinish(t); return true; }
    return false;
  };
  // Срочный возврат: рука на окне или команда, которой нужен прежний чат.
  // Тик идёт раз в 700 мс, а ⌘N «Нового окна» приходит через 0,4–0,9 с после
  // команды, поэтому возврат досматриваем опросом раздела 12б по 100 мс.
  const roamAbort = why => {
    if (roamState.phase === "idle") return;
    roamBack(why);
    if (roamState.phase !== "back" || roamState.polling) return;
    roamState.polling = true;
    // Бюджет опроса — на худший честный ход: отложенный переход (2 с), строка (1 с), история (2 с).
    newWindowWait(() => (roamBackCheck(autoAllowNow()) ? true : null), ROAM_NAV_MS * 3, roamState.token)
      .then(() => { roamState.polling = false; if (roamState.phase === "back") roamFinish(autoAllowNow()); });
  };
  // Команды «Новое окно», «В отдельное окно», «Обкэшить» и «Workflow» берут
  // прежний чат из адреса страницы: посреди обхода это был бы чужой чат B.
  // Сперва окно возвращается, потом команда исполняется (критик WF82, п. 11).
  const roamDefer = run => {
    if (roamState.phase === "idle") return false;
    roamState.deferred.push(run);
    roamAbort("команда");
    return true;
  };

  const roamGo = id => {
    const button = roamButton(id);
    if (!button) return false;
    try { button.click(); } catch { return false; }
    return true;
  };
  const roamStart = (target, t) => {
    if (!roamLockTake(target.id, t)) { roamState.reason = "обход идёт в другом окне"; return; }
    modeGuardDrop(); // До перехода: даже быстрый A→B→A отменяет старый token.
    const from = location.pathname;
    const fromId = from === NEW_WINDOW_HOME_PATH ? "" : newWindowSegment(from);
    Object.assign(roamState, {
      phase: "go", phaseAt: t, since: t, chat: target.id, title: target.title, from, fromId,
      fromTitle: (fromId && newWindowRowTitle(newWindowRow(fromId, true))) || (fromId ? "прежний чат" : "новый чат"),
      lengthBefore: history.length, fromKey: roamEntryKey(), token: newWindowToken, startCount: autoAllowState.pressCount,
      seenCount: autoAllowState.pressCount, visited: [target.id], titles: [target.title],
      scroll: roamScrollSave(), bText: null, why: "", via: "", reason: `обход: «${target.title}»`,
    });
    if (!roamGo(target.id)) roamBack("строки нет", t);
  };
  // Шаг обхода на тике: тик выше уже поискал и нажал кнопку, теперь — часы.
  const roamStep = t => {
    if (roamState.phase === "back") { roamBackCheck(t); return; }
    roamLockTake(roamState.chat, t);
    const here = newWindowSessionId();
    if (roamState.phase === "go") {
      if (here === roamState.chat) {
        roamState.phase = "wait";
        roamState.phaseAt = t;
        roamState.bText = roamComposerText();
      } else if (t - roamState.phaseAt > ROAM_NAV_MS) roamBack("чат не открылся", t);
      return;
    }
    // Окно увели из чата не мы — возвращаемся, пока не наделали дел.
    if (here !== roamState.chat) { roamBack("чат сменился", t); return; }
    if (roamState.phase === "wait") {
      if (autoAllowState.pressCount !== roamState.seenCount) {
        roamState.seenCount = autoAllowState.pressCount;
        roamState.phase = "linger";
        roamState.phaseAt = t;
        return;
      }
      // Черновик B мог доехать позже адреса — до первого нажатия это ещё не «чужой текст».
      roamState.bText = roamComposerText();
      // В B стор уже знает, что ждёт: вопрос или план — не наше, сразу назад.
      const verdict = roamVerdict(roamState.chat);
      if (verdict.reason) {
        roamState.noButton.add(roamState.chat);
        roamBack(verdict.reason, t);
        return;
      }
      if (t - roamState.phaseAt > ROAM_BUTTON_MS || t - roamState.since > ROAM_MAX_MS) {
        roamState.noButton.add(roamState.chat);
        roamBack("кнопки нет", t);
      }
      return;
    }
    // linger: второе разрешение подряд продлевает стоянку, но не весь обход.
    if (autoAllowState.pressCount !== roamState.seenCount) {
      roamState.seenCount = autoAllowState.pressCount;
      roamState.phaseAt = t;
    }
    // Поле, спрятанное на время карточки, берёт базу, как только появится.
    if (roamState.bText == null) roamState.bText = roamComposerText();
    if (t - roamState.phaseAt < ROAM_LINGER_MS && t - roamState.since < ROAM_MAX_MS) return;
    // Текст в поле B — не идём дальше: roamBack оставит окно здесь.
    if (roamBTextChanged()) { roamBack("в поле текст", t); return; }
    const next = roamState.visited.length < ROAM_MAX_TARGETS && t - roamState.since < ROAM_NEXT_MS
      ? roamPick(t, roamWaiting() ?? [], [...roamState.visited, roamState.fromId]) : null;
    if (next && roamGo(next.id)) {
      Object.assign(roamState, { phase: "go", phaseAt: t, chat: next.id, title: next.title, bText: null });
      roamState.visited.push(next.id);
      roamState.titles.push(next.title);
      return;
    }
    roamBack("готово", t);
  };
  const roamDry = target => {
    roamState.reason = `сухой режим: пошёл бы в «${target.title}»`;
    const key = `${target.id}|dry`;
    if (roamState.noted.has(key)) return;
    roamState.noted.add(key);
    roamState.dryRuns += 1;
    roamState.lastRoam = {
      at: roamIso(autoAllowNow()), dry: true, chats: [target.id], titles: [target.title],
      tools: target.tools.slice(0, 5).map(tool => AUTO_ALLOW_TOOLS.has(tool) ? tool : "unknown"), from: location.pathname,
    };
  };
  const roamScan = t => {
    roamState.scanAt = t;
    const waiting = roamWaiting();
    if (!waiting) { roamState.waiting = []; roamState.reason = "список слева не виден"; return; }
    roamTrack(waiting, t);
    if (!waiting.length) { roamState.reason = "никто не ждёт"; return; }
    if (!roamStoresReady()) {
      roamFindStores(t);
      roamState.reason = roamState.storeScan ? "ищу стор" : "стор не найден";
      return;
    }
    // Что ждёт в каждом чате — для сверки метки на гейте (status().autoAllow.roam.waiting).
    for (const item of roamState.waiting) item.tools = roamVerdict(item.id).tools.slice(0, 5).map(tool => AUTO_ALLOW_TOOLS.has(tool) ? tool : "unknown");
    const target = roamPick(t, waiting, []);
    if (!target) {
      roamState.reason = roamState.unrendered
        ? `идти некуда: ждущих в свёрнутой группе списка — ${roamState.unrendered}`
        : "идти некуда";
      return;
    }
    const blocker = roamBlocker(t);
    if (blocker) { roamState.reason = blocker; return; }
    if (roamMode() === "dry") { roamDry(target); return; }
    roamStart(target, t);
  };
  const roamTick = () => {
    if (!state.alive || !isMainWindow()) return;
    const t = autoAllowNow();
    if (roamState.phase !== "idle") { roamStep(t); return; }
    if (!autoAllowEnabled()) { roamState.reason = "Авто-Allow выключен"; return; }
    const mode = roamMode();
    if (mode === "off") { roamState.reason = "выключен"; return; }
    if (roamState.disabled) { roamState.reason = `выключен: ${roamState.disabled}`; return; }
    if (t - roamState.scanAt < ROAM_SCAN_MS) return;
    roamScan(t);
  };

  // Щит и тишина. Считаем только доверенные события — наши click() и нажатия
  // тика выше доверенными не бывают. Фокус узла (Claude сам ставит курсор в
  // поле открытого чата) — не человек, берём только фокус самого окна.
  const roamBlocks = event => {
    const type = event.type;
    if (type === "keydown") {
      const key = String(event.key ?? "");
      // Сочетания с ⌘ пропускаем, кроме ⌘V: ⌘N «Нового окна» Swift шлёт настоящей клавишей.
      if (event.metaKey || event.ctrlKey) return event.code === "KeyV" || key.toLowerCase() === "v" || key === "м";
      return key.length === 1 || key === "Enter" || key === "Backspace" || key === "Delete";
    }
    return type === "paste" || type === "drop" || type === "beforeinput" || type === "pointerdown" || type === "click";
  };
  const onRoamInput = event => {
    if (!event?.isTrusted) return;
    const type = event.type;
    if (type === "focus" && event.target !== window) return;
    const t = autoAllowNow();
    if (type === "pointermove" || type === "pointerdown" || type === "wheel" || type === "click" || type === "focus") roamState.input.pointer = t;
    if (type !== "pointermove" && type !== "wheel" && type !== "pointerdown" && type !== "click") roamState.input.key = t;
    if (roamState.phase === "idle") return;
    const block = roamBlocks(event);
    if (block) {
      try { event.preventDefault(); } catch {}
      try { event.stopImmediatePropagation(); } catch {}
    }
    if (block || type === "focus") roamAbort(block ? "рука на окне" : "окно подняли");
  };
  // Обход живёт только в главном окне: у попапа нет списка слева.
  if (isMainWindow()) {
    for (const type of ["keydown", "pointerdown", "paste", "drop", "beforeinput", "compositionstart", "click", "focus"]) {
      on(window, type, onRoamInput, true);
    }
    for (const type of ["pointermove", "wheel"]) on(window, type, onRoamInput, { capture: true, passive: true });
  }
  // Экземпляр уходит посреди обхода (cp inject.js) — окно возвращаем сразу:
  // новому экземпляру про этот обход знать неоткуда.
  track(() => {
    const phase = roamState.phase;
    const away = phase === "go" || phase === "wait" || phase === "linger" || (phase === "back" && roamState.via === "pending");
    if (away) { try { roamNavigateBack(); } catch {} }
    roamState.phase = "idle";
    roamState.deferred.length = 0;
    roamLockDrop();
  });
  const roamStatus = () => ({
    on: isMainWindow() && autoAllowEnabled() && roamMode() === "on" && !roamState.disabled,
    mode: roamMode(),
    state: roamState.phase,
    chat: roamState.chat,
    from: roamState.from,
    since: roamState.since ? roamIso(roamState.since) : null,
    roams: roamState.roams,
    lastRoam: roamState.lastRoam,
    skipped: roamState.skipped.slice(),
    reason: isMainWindow() ? roamState.reason : "не главное окно",
    waiting: roamState.waiting.slice(),
    unrendered: roamState.unrendered,
    dryRuns: roamState.dryRuns,
    disabled: roamState.disabled || null,
  });

  // Один тик на оба дела: сперва кнопка в этом окне, потом шаг обхода.
  // Выключено (К3) — не жмём и не ходим; обход, начатый до выключения,
  // возвращается домой.
  const trustCycle = () => { if (state.alive) { try { autoTrustTick(autoAllowNow()); } catch {} } };
  const autoAllowCycle = () => {
    if (!state.alive) return;
    const on = autoAllowEnabled();
    // Тумблер выключен — жмёт только чат в Bypass permissions (#9998, autoAllowActive в тике).
    if (on || autoAllowBypassHere()) { try { autoAllowTick(); } catch {} }
    // Доверие папке (#7905) — вне выключателя: см. раздел 12е, autoTrustTick.
    trustCycle();
    if (!on && roamState.phase !== "idle") { try { roamAbort("Авто-Allow выключен"); } catch {} }
    try { roamTick(); } catch {}
  };
  autoAllowState.timer = setInterval(autoAllowCycle, AUTO_ALLOW_TICK_MS);
  // Тик и из общего наблюдателя мутаций (раздел 9, onMutated): перекрытое окно
  // Chromium душит (setInterval реже раза в секунду), а мутации от React идут и
  // там — карточка разрешения появилась, тик тут же. Дешёвый фильтр — в
  // добавленных узлах есть кнопка; плюс смена заголовка под замком. Не чаще
  // раза в AUTO_ALLOW_MUTATION_MS.
  const AUTO_ALLOW_MUTATION_MS = 150;
  const autoAllowOnMutation = records => {
    let hit = false;
    for (const record of records) {
      for (const node of record.addedNodes ?? []) {
        if (node?.nodeType !== 1) continue;
        if (node.nodeName === "BUTTON" || node.querySelector?.("button")) { hit = true; break; }
      }
      if (hit) break;
    }
    if (!hit) return;
    const t = autoAllowNow();
    if (t - autoAllowState.mutationAt < AUTO_ALLOW_MUTATION_MS) return;
    autoAllowState.mutationAt = t;
    autoAllowState.mutationRuns += 1;
    autoAllowCycle();
  };
  track(() => { clearInterval(autoAllowState.timer); autoAllowState.timer = 0; });

