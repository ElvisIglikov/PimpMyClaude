  // ---- 13б. Сквозная история чатов (#11201, перенос #10959 с Windows) ---------
  // Слово Элвиса 30.10.2026 ~16:00 (#11201): «у Пимпа должно быть сквозное… посмотри на Windows, как PIM работает.
  // Он там в новые чаты переходит автоматически… нам так же надо сделать». Это блок PimpWin «Сквозная история чатов»
  // (#10959, 25.10, слово Элвиса: «доходил до начала, до самого-самого верха… оказывался в предыдущем чате… дошёл до
  // края — следующий… кнопка — последний чат»), перенесённый целиком; поведение и числа — как на Windows.
  //  • Цепочка — из самой страницы: LocalSessions.getAll() (не чаще CHAIN_LIST_TTL_MS и при смене чата). Линия папки —
  //    чаты без родителя или хоть раз закреплённые (isStarred, помнятся в localStorage), по времени создания; боковой,
  //    форк и копия worktree ведут вверх в родителя («↑ Откуда запущен»), следующего у них нет. Папка — путь как
  //    есть (регистр учитывается), без хвостового «/».
  //  • У самого верха ленты (Claude догрузил всё: olderHistoryAbove и isPoolPending у узла React над лентой) — зазор
  //    CHAIN_GAP_PX и плашка «↑ Предыдущий чат «…» дата»; у низа (Claude не отвечает) — «↓ Следующий чат». Нажатие —
  //    переход; колесо у края — ускорение к той же кнопке: край взводится, когда лента стоит у него CHAIN_ARM_MS и
  //    колесо помолчало CHAIN_QUIET_MS (хвост инерции тачпада край не взводит), дальше CHAIN_PULL_PX натяжки
  //    заполняют полоску плашки; недотянул — натяжка спадает.
  //  • Вверх — в низ предыдущего, вниз — в начало следующего (лента докручивается к верху, пока Claude догружает;
  //    колесо новым жестом или назад, стрелки, Esc, нажатие плашки — стоп). Переход — роутером приложения
  //    (__TSR_ROUTER__, пишет историю: «Назад» мыши возвращает), запасной — строка сайдбара.
  //  • «N из M · В последний чат» — фишка в строке заголовка чата после его меню; не влезает — под строкой справа.
  //    В последнем чате после перехода фишкой — тихая метка «Последний чат» внизу.
  //  • Только главное окно (chatKind "main"): у попапа роутера нет. Идёт обход чатов (12е) — края не взводятся.
  // Мак, в отличие от Windows: Esc только слушаем — раздел 16 сам глотает Esc, а Claude по нему обрывает ход; на время
  // докрутки — feedHold.ownUntil (раздел 13а не возвращает ленте «место чтения»); «↓ Следующий чат» встаёт выше
  // «непрочитанных N» (раздел 12х); строка заголовка, накрывающая ленту, — только если правда над ней (широкий вид).
  // Автопереход (слово Элвиса 30.10 16:50: «окно автоматически должно переходить в новый чат»): стоим в последнем чате
  // линии, в ней появился новый — окно само уходит в него, когда тихо (поле пустое, Claude молчит, чат не открыт рядом).
  const CHAIN_ROOT_ID = "myclaude-chain";
  const CHAIN_FEED_SELECTOR = '[data-testid="epitaxy-virtual-transcript"]';
  const CHAIN_PINNED_KEY = "myclaude-chain-pinned-v1";
  const CHAIN_PINNED_MAX = 400;
  const CHAIN_GAP_ATTRIBUTE = "data-myclaude-chain-gap";
  const CHAIN_GAP_PX = 48;
  // Зазор снизу: шов «↓ Следующий чат» у низа встаёт над ним, а не на последнюю строку последнего сообщения.
  const CHAIN_GAP_BOTTOM_ATTRIBUTE = "data-myclaude-chain-gap-bottom";
  const CHAIN_GAP_BOTTOM_PX = 52;
  const CHAIN_LIST_TTL_MS = 15000;
  const CHAIN_MISS_RETRY_MS = 2000;
  const CHAIN_TICK_MS = 150;
  const CHAIN_ARM_MS = 400;
  const CHAIN_ARM_BLIND_MS = 1000;
  const CHAIN_QUIET_MS = 250;
  const CHAIN_PULL_PX = 320;
  const CHAIN_DECAY_AFTER_MS = 350;
  const CHAIN_SETTLE_MS = 1200;
  const CHAIN_GO_MS = 8000;
  const CHAIN_LAND_TOP_MS = 15000;
  const CHAIN_LAND_BOTTOM_MS = 2500;
  const CHAIN_LAND_STEP_MS = 160;
  const CHAIN_FLASH_MS = 1400;
  const CHAIN_FAIL_MS = 6000;
  const CHAIN_EDGE_PX = 2;
  const CHAIN_BUTTON_H = 30;
  const CHAIN_UNDER_PX = 32;
  const CHAIN_FOLLOW_IDLE_MS = 3000;
  const CHAIN_FOLLOW_WINDOW_MS = 30 * 60 * 1000;
  const CHAIN_FOLLOW_FLASH_MS = 4000;
  // Окна одного приложения делят localStorage: {<id окна>: {chat, at}} — кто какой чат держит (at — Date.now()).
  const CHAIN_WINDOWS_KEY = "myclaude-chain-windows-v1";
  const CHAIN_WINDOWS_WRITE_MS = 2000;
  const CHAIN_WINDOWS_DROP_MS = 10000;
  const CHAIN_WINDOWS_FRESH_MS = 6000;
  // Новый чат мог только что открыться в другом окне: его запись в реестре придёт за ≤ CHAIN_WINDOWS_WRITE_MS — до
  // перехода ждём чуть дольше, и окно без фокуса тоже.
  const CHAIN_FOLLOW_SETTLE_MS = 2500;
  const CHAIN_MONTHS = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"];
  const CHAIN_TEXT = {
    prev: "↑ Предыдущий чат", parent: "↑ Откуда запущен", next: "↓ Следующий чат", last: "В последний чат",
    pos: "{i} из {n}", opening: "Открываю {t}", landing: "Листаю к началу {t}", failed: "Не открылся {t} — нажми ещё раз",
    latest: "Последний чат", lastTip: "Последний чат: {t} · {d}", pullTip: "Нажми или крути колесо дальше",
    stopTip: "Нажми или Esc — остановить",
    follow: "Перешёл в новый чат", followTip: "В линии появился новый чат — окно перешло само · «Назад» — вернуться",
  };
  // Кнопка меню чата в строке заголовка: Claude подписывает её «More options for <название>» (раздел 9).
  // #11618: русские — из каталога claude.ai: «Другие действия — {title}», «Другие действия: {name}», «Дополнительные параметры».
  const CHAIN_MORE_RE = /^(More options|Другие действия|Дополнительные параметры)/i;
  const chainLive = themable && chatKind() === "main";
  const chainState = {
    chat: "", links: null, list: null, listAt: -Infinity, listing: null, listError: null, missAt: 0,
    edges: { up: { since: 0, height: 0, quiet: false }, down: { since: 0, height: 0, quiet: false } },
    pull: 0, pullDir: "", pullAt: -Infinity, wheelAt: -Infinity, settleUntil: 0, host: null, gapDelta: 0, gapBottom: 0,
    going: null, failed: null, flash: null, gos: 0, last: null, error: null, disposed: false, raf: 0,
    // Автопереход: хвост линии, когда стояли в последнем; ждём перехода; причина последнего отказа; последний переход.
    follow: { tail: null, pending: null, blocked: null, last: null }, touchAt: -Infinity, windowsAt: -Infinity,
    // Шов 13в (677): чат, для которого верх отдан шву (плашки «↑», зазора и натяжки вверх нет), его фаза и срок, до
    // которого колесо — его жест (погашенный жест шва — его до конца, и после закрытия).
    seamTop: "", seamPhase: "idle", seamHeld: -Infinity,
  };
  const chainTimers = new Set();
  const chainLater = (fn, ms) => {
    const id = setTimeout(() => { chainTimers.delete(id); fn(); }, ms);
    chainTimers.add(id);
    return id;
  };
  const chainSleep = ms => new Promise(resolve => chainLater(resolve, ms));
  // Сбой блока не мешает окну: ловим и кладём в status().chain.error.
  const chainSafe = fn => (...args) => {
    try { return fn(...args); } catch (error) { chainState.error = String(error?.message ?? error).slice(0, 160); return undefined; }
  };

  // ---- цепочка (чистые функции; люк — HATCH.chainOf) ----
  const chainFolder = path => String(path ?? "").trim().replace(/\/+$/, "");
  // Время создания — число мс (замер 30.10) или строка (число или дата ISO).
  const chainAt = s => {
    const raw = s?.createdAt;
    if (typeof raw === "number") return Number.isFinite(raw) ? raw : NaN;
    if (typeof raw !== "string" || !raw.trim()) return NaN;
    const n = Number(raw);
    return Number.isFinite(n) ? n : Date.parse(raw);
  };
  // Откуда чат: боковой (lineage side_session, spawnedFrom) или форк.
  const chainParentOf = s => {
    const lineage = s?.lineage;
    if (lineage && lineage.kind === "side_session" && typeof lineage.sessionId === "string") return lineage.sessionId;
    if (typeof s?.spawnedFrom?.sessionId === "string") return s.spawnedFrom.sessionId;
    return typeof s?.forkedFromSessionId === "string" ? s.forkedFromSessionId : "";
  };
  const chainUsable = s => Boolean(s) && typeof s.sessionId === "string" && s.sessionId.startsWith("local_")
    && s.isScratchWorkspace !== true && s.neverStarted !== true && Number.isFinite(chainAt(s));
  // Основная линия папки — чаты без родителя в самой папке (копия worktree агента — не основная) и чаты, хоть раз
  // закреплённые: новый главный чат, запущенный из старого (start_session, lineage side_session), — продолжение
  // линии, а не боковой. Закреплённые помнятся (CHAIN_PINNED_KEY): открепили старый — в линии он остаётся.
  const chainPinned = new Set();
  const chainMainLine = (s, pinned) => (!chainParentOf(s) || s.isStarred === true || pinned.has(s.sessionId))
    && (!s.originCwd || chainFolder(s.originCwd) === chainFolder(s.cwd));
  const chainBrief = s => (s ? { id: s.sessionId, title: String(s.title ?? "").trim(), at: chainAt(s) } : null);
  const chainOf = (list, id, pinned = chainPinned) => {
    // Архивные — мимо линии, как на Windows (там getAll их не отдаёт); открытый архивный — сам в линии.
    const all = (Array.isArray(list) ? list : []).filter(s => chainUsable(s) && (s.isArchived !== true || s.sessionId === id));
    const me = all.find(s => s.sessionId === id);
    if (!me) return null;
    const line = folder => all.filter(s => chainMainLine(s, pinned) && chainFolder(s.cwd) === folder)
      .sort((a, b) => chainAt(a) - chainAt(b) || (a.sessionId < b.sessionId ? -1 : 1));
    if (!chainMainLine(me, pinned)) {
      const parent = all.find(s => s.sessionId === chainParentOf(me)) ?? null;
      const own = line(chainFolder(parent ? parent.originCwd || parent.cwd : me.originCwd || me.cwd));
      // Последний — он же родитель: одна кнопка, «Откуда запущен».
      const last = own[own.length - 1] ?? null;
      const lastOk = last && last.sessionId !== id && last.sessionId !== parent?.sessionId;
      return { side: true, prev: chainBrief(parent), next: null, last: lastOk ? chainBrief(last) : null, index: 0, total: own.length };
    }
    const own = line(chainFolder(me.cwd));
    const i = own.findIndex(s => s.sessionId === id);
    const last = own[own.length - 1];
    return {
      side: false, prev: chainBrief(own[i - 1]), next: chainBrief(own[i + 1]),
      last: last && last.sessionId !== id ? chainBrief(last) : null, index: i + 1, total: own.length,
      at: chainAt(me), ids: own.map(s => s.sessionId),
    };
  };

  // ---- подписи ----
  const chainT = (key, vars = {}) => String(CHAIN_TEXT[key] ?? "").replace(/\{(\w)\}/g, (_, k) => vars[k] ?? "");
  const chainQuoted = title => {
    const s = title || "…";
    return `«${s.length > 60 ? `${s.slice(0, 58).trimEnd()}…` : s}»`;
  };
  const chainWhen = at => {
    if (!Number.isFinite(at)) return "";
    const d = new Date(at);
    return `${d.getDate()} ${CHAIN_MONTHS[d.getMonth()]}, ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  };

  // ---- список чатов ----
  const chainId = () => (String(location.pathname).startsWith("/epitaxy/") ? newWindowSessionId() : "");
  const chainSessions = () => { try { return window["claude.web"]?.LocalSessions ?? null; } catch { return null; } };
  try { for (const id of JSON.parse(localStorage.getItem(CHAIN_PINNED_KEY) ?? "[]")) if (typeof id === "string") chainPinned.add(id); } catch {}
  const chainRememberPinned = list => {
    let added = false;
    for (const s of list ?? []) if (s?.isStarred === true && chainUsable(s) && !chainPinned.has(s.sessionId)) { chainPinned.add(s.sessionId); added = true; }
    if (!added) return;
    try { localStorage.setItem(CHAIN_PINNED_KEY, JSON.stringify([...chainPinned].slice(-CHAIN_PINNED_MAX))); } catch {}
  };
  const chainRelink = () => {
    chainState.links = chainState.chat ? chainOf(chainState.list, chainState.chat) : null;
    // Чата ещё нет в списке (только что создан) — спросим ещё раз, один раз на чат.
    if (chainState.chat && chainState.list && !chainState.links && !chainState.missAt) {
      chainState.missAt = now();
      chainLater(() => { if (!chainState.disposed) chainRefresh(true); }, CHAIN_MISS_RETRY_MS);
    }
  };
  const chainRefresh = (force = false) => {
    if (chainState.listing || (!force && now() - chainState.listAt < CHAIN_LIST_TTL_MS)) return chainState.listing;
    const api = chainSessions();
    if (typeof api?.getAll !== "function") { chainState.listError = "no-api"; chainState.listAt = now(); return null; }
    const asked = chainState.chat;
    chainState.listing = Promise.resolve().then(() => api.getAll()).then(list => {
      chainState.list = Array.isArray(list) ? list : null;
      chainRememberPinned(chainState.list);
      chainState.listError = chainState.list ? null : "not-array";
    }, error => { chainState.listError = String(error?.message ?? error).slice(0, 120); })
      .finally(() => {
        chainState.listing = null;
        chainState.listAt = now();
        if (!chainState.disposed) chainSafe(() => { chainRelink(); chainFollowSee(asked); chainRender(); })();
      });
    return chainState.listing;
  };

  // ---- лента и края ----
  const chainFeed = () => { try { return document.querySelector(CHAIN_FEED_SELECTOR); } catch { return null; } };
  // Узел React над лентой (olderHistoryAbove — выше есть недогруженное, isPoolPending, isResponding), как у раздела
  // 12х; нет его (другая сборка Claude) — null, и край ждёт дольше.
  const chainHostOf = el => {
    try {
      let fiber = chatFiberOf(el);
      for (let hop = 0; fiber && hop < READ_FIBER_DEPTH; hop += 1, fiber = fiber.return) {
        const props = fiber.memoizedProps;
        if (props && typeof props === "object" && "olderHistoryAbove" in props) return props;
      }
    } catch {}
    return null;
  };
  const chainGapOf = el => String(el?.getAttribute?.(CHAIN_GAP_ATTRIBUTE) ?? "");
  const chainAtTop = el => el.scrollTop <= CHAIN_EDGE_PX;
  const chainGapBottomOf = el => Boolean(el?.hasAttribute?.(CHAIN_GAP_BOTTOM_ATTRIBUTE));
  // Свой зазор снизу — не лента: стоять в нём — тоже низ.
  const chainAtBottom = el => el.scrollHeight - el.clientHeight - el.scrollTop <= CHAIN_EDGE_PX + (chainGapBottomOf(el) ? chainState.gapBottom : 0);
  const chainTarget = dir => (dir === "up" ? chainState.links?.prev : dir === "down" ? chainState.links?.next : null) ?? null;
  // Край готов: сверху Claude догрузил всё (olderHistoryAbove = false, пул не ждёт), снизу Claude не пишет ответ.
  const chainReady = dir => {
    const host = chainState.host;
    if (!host) return true;
    return dir === "up" ? host.olderHistoryAbove !== true && host.isPoolPending !== true : host.isResponding !== true;
  };
  const chainTrackEdges = el => {
    const at = now();
    chainState.host = el ? chainHostOf(el) : null;
    for (const dir of ["up", "down"]) {
      const edge = chainState.edges[dir];
      const here = Boolean(el) && (dir === "up" ? chainAtTop(el) : chainAtBottom(el));
      if (!here) { edge.since = 0; edge.quiet = false; continue; }
      // Свой зазор сверху меняет высоту ленты — это не догрузка Claude: высота — без него.
      const height = el.scrollHeight - (chainGapOf(el) ? chainState.gapDelta : 0) - (chainGapBottomOf(el) ? chainState.gapBottom : 0);
      if (!edge.since || edge.height !== height) { edge.since = at; edge.quiet = false; edge.height = height; }
      // Пауза колеса — уже у края: хвост инерции, который донёс сюда, её не даёт.
      if (!edge.quiet && at - Math.max(chainState.wheelAt, edge.since) >= CHAIN_QUIET_MS) edge.quiet = true;
    }
  };
  const chainArmed = dir => {
    const edge = chainState.edges[dir];
    if (!edge.since || !edge.quiet || now() < chainState.settleUntil || chainState.going || !chainReady(dir)) return false;
    if (roamState.phase !== "idle") return false;
    return now() - edge.since >= (chainState.host ? CHAIN_ARM_MS : CHAIN_ARM_BLIND_MS);
  };
  // Колесо над вложенным блоком, который сам ещё крутится в ту сторону (длинный вывод инструмента), — его, не наше.
  const chainNestedTakes = (node, el, dy) => {
    for (let n = node?.nodeType === 1 ? node : node?.parentElement; n && n !== el; n = n.parentElement) {
      let oy = "";
      try { oy = getComputedStyle(n).overflowY; } catch {}
      if ((oy === "auto" || oy === "scroll") && n.scrollHeight > n.clientHeight + 1) {
        if (dy < 0 ? n.scrollTop > 0 : n.scrollTop + n.clientHeight < n.scrollHeight - 1) return true;
      }
    }
    return false;
  };

  // ---- переход ----
  const chainWaitFor = (test, ms) => new Promise(resolve => {
    const start = now();
    const step = () => {
      let value = null;
      try { value = test(); } catch { value = null; }
      if (value || chainState.disposed || now() - start >= ms) { resolve(value || null); return; }
      chainLater(step, 100);
    };
    step();
  });
  // Роутер приложения (раздел 12б, navRouterTo): ведёт и в чат, которого нет в видимом списке слева, и пишет
  // историю. Запасной путь — строка сайдбара из любой группы.
  const chainNavigate = id => {
    if (navRouterTo(`${NEW_WINDOW_HOME_PATH}/${id}`)) return "router";
    const row = newWindowRow(id, true);
    if (row) { newWindowRowClick(row); return "row"; }
    return "";
  };
  // Лента нового чата готова: адрес сменился, узел ленты есть (прежний узел — не раньше 500 мс) и высота стоит 250 мс
  // (или прошло 1,5 с: длинный чат Claude досчитывает строки секундами).
  const chainReadyFeed = (id, old, from) => {
    const started = now();
    let seen = null;
    let routed = 0;
    return () => {
      const here = chainId();
      // Человек сам ушёл в другой чат посреди перехода — молча отступаем, без «Не открылся».
      if (here && here !== id && here !== from && now() - started > 300) return "away";
      if (here !== id) return null;
      routed = routed || now();
      const el = chainFeed();
      if (!el || el.scrollHeight <= 0 || (el === old && now() - routed < 500)) return null;
      if (now() - routed >= 1500) return el;
      if (!seen || seen.el !== el || seen.height !== el.scrollHeight) { seen = { el, height: el.scrollHeight, since: now() }; return null; }
      return now() - seen.since >= 250 ? el : null;
    };
  };
  // Приземление: «bottom» — низ (Claude мог запомнить место — ставим явно), «top» — начало: лента докручивается вверх,
  // пока Claude догружает старое. Колесо, клавиши, Esc или нажатие плашки — стоп. На всё время — своя прокрутка для
  // раздела 13а (место чтения не возвращает).
  const chainLand = async going => {
    const top = going.where === "top";
    const limit = top ? CHAIN_LAND_TOP_MS : CHAIN_LAND_BOTTOM_MS;
    const begin = now();
    let height = -1;
    let stable = 0;
    going.phase = "land";
    chainRender();
    while (!chainState.disposed && !going.stop && now() - begin < limit && chainId() === going.id) {
      const el = chainFeed();
      if (!el) break;
      feedHold.ownUntil = now() + CHAIN_LAND_STEP_MS * 3;
      el.scrollTop = top ? 0 : el.scrollHeight;
      going.steps = (going.steps || 0) + 1;
      await chainSleep(CHAIN_LAND_STEP_MS);
      const host = chainHostOf(el);
      const done = top ? chainAtTop(el) && host?.olderHistoryAbove !== true : chainAtBottom(el);
      stable = done && el.scrollHeight === height ? stable + 1 : 0;
      height = el.scrollHeight;
      if (stable >= (host ? 2 : 4)) break;
    }
  };
  const chainGo = async (to, where, kind) => {
    if (!to || chainState.going || chainState.disposed || roamState.phase !== "idle") return;
    const from = chainState.chat;
    const old = chainFeed();
    const going = { id: to.id, title: to.title, kind, where, at: now(), phase: "open", stop: false, dir: kind === "up" ? "up" : "down", steps: 0 };
    chainState.going = going;
    chainState.failed = null;
    chainState.pull = 0;
    chainState.pullDir = "";
    let ok = false;
    let via = "";
    try {
      chainSafe(chainRender)();
      via = chainNavigate(to.id);
      const el = via ? await chainWaitFor(chainReadyFeed(to.id, old, from), CHAIN_GO_MS) : null;
      if (chainState.disposed) return;
      if (el === "away") { chainState.last = { from, to: to.id, kind, via, ok: false, away: true, at: Date.now() }; return; }
      if (!el) {
        chainState.failed = { id: to.id, title: to.title, kind, where, at: now() };
        chainState.last = { from, to: to.id, kind, via, ok: false, at: Date.now() };
        return;
      }
      chainState.chat = to.id;
      chainState.missAt = 0;
      chainRelink();
      await chainLand(going);
      if (chainState.disposed) return;
      ok = true;
    } catch (error) {
      chainState.error = String(error?.message ?? error).slice(0, 160);
    } finally {
      if (chainState.going === going) chainState.going = null;
    }
    if (!ok || chainState.disposed) { chainSafe(chainRender)(); return; }
    chainState.gos += 1;
    chainState.settleUntil = now() + CHAIN_SETTLE_MS;
    chainState.flash = { side: kind === "last" ? "latest" : kind === "follow" ? "follow" : where === "bottom" ? "down" : "up", from, at: now() };
    chainState.last = { from, to: to.id, kind, via, ok: true, stopped: going.stop, at: Date.now() };
    chainSafe(() => { chainTrackEdges(chainFeed()); chainRender(); })();
    chainRefresh(true);
  };

  // ---- автопереход в новый чат линии ----
  const chainWindowId = `w${Math.random().toString(36).slice(2, 10)}${Date.now().toString(36)}`;
  const chainWindowsRead = () => {
    try {
      const all = JSON.parse(localStorage.getItem(CHAIN_WINDOWS_KEY) ?? "{}");
      return all && typeof all === "object" && !Array.isArray(all) ? all : {};
    } catch { return {}; }
  };
  // Своя запись — на своём тике раз в 2 с (и сразу при смене чата); чужие старше 10 с вычищаются.
  const chainWindowsWrite = (force = false) => {
    if (!force && now() - chainState.windowsAt < CHAIN_WINDOWS_WRITE_MS) return;
    chainState.windowsAt = now();
    const wall = Date.now();
    const all = chainWindowsRead();
    for (const [id, rec] of Object.entries(all)) if (!(wall - Number(rec?.at) <= CHAIN_WINDOWS_DROP_MS)) delete all[id];
    all[chainWindowId] = { chat: chainState.chat || null, at: wall };
    try { localStorage.setItem(CHAIN_WINDOWS_KEY, JSON.stringify(all)); } catch {}
  };
  const chainWindowsDrop = () => {
    const all = chainWindowsRead();
    if (!(chainWindowId in all)) return;
    delete all[chainWindowId];
    try {
      if (Object.keys(all).length) localStorage.setItem(CHAIN_WINDOWS_KEY, JSON.stringify(all));
      else localStorage.removeItem(CHAIN_WINDOWS_KEY);
    } catch {}
  };
  const chainOpenElsewhere = id => {
    const wall = Date.now();
    return Object.entries(chainWindowsRead()).some(([w, rec]) => w !== chainWindowId && rec?.chat === id && wall - Number(rec?.at) <= CHAIN_WINDOWS_FRESH_MS);
  };
  // Свежий список, спрошенный из этого же чата: стоим в последнем — запомнить хвост линии; в линии после нас новый
  // чат, которого в хвосте не было, — ждать перехода (один раз на чат: он сразу уходит в хвост).
  const chainFollowSee = asked => {
    const f = chainState.follow;
    const links = chainState.links;
    const x = chainState.chat;
    if (!x || asked !== x || !links || links.side || !chainState.list) return;
    if (f.tail?.chat !== x) f.tail = null;
    if (!links.last) { f.tail = { chat: x, ids: new Set(links.ids), at: links.at }; return; }
    const y = links.last;
    if (!f.tail || f.tail.ids.has(y.id) || !(y.at > f.tail.at)) return;
    f.tail.ids.add(y.id);
    if (chainOpenElsewhere(y.id)) { f.pending = null; f.blocked = "other-window"; return; }
    f.pending = { from: x, to: y.id, title: y.title, since: Date.now(), t: now() };
    f.blocked = null;
  };
  const chainTyping = () => {
    const editor = state.editor?.isConnected ? state.editor : findEditor();
    return Boolean(editor) && editorText(editor) !== "";
  };
  const chainFocused = () => { try { return document.hasFocus() !== false; } catch { return true; } };
  // Каждый тик, пока ждём: снять ожидание (ушли, 30 мин, чат пропал, открыт в другом окне) или отложить (обход,
  // переход, Claude пишет, текст в поле, человек трогал окно < 3 с, новый чат увиден < 2,5 с назад) — иначе переход
  // роутером, как «В последний чат».
  const chainFollowTry = () => {
    const f = chainState.follow;
    const p = f.pending;
    if (!p) return;
    const drop = why => { f.pending = null; f.blocked = why; };
    if (chainState.chat !== p.from) return drop("moved");
    if (now() - p.t > CHAIN_FOLLOW_WINDOW_MS) return drop("expired");
    const y = chainState.list?.find(s => s?.sessionId === p.to);
    if (!chainUsable(y) || y.isArchived === true) return drop("gone");
    if (chainOpenElsewhere(p.to)) return drop("other-window");
    if (roamState.phase !== "idle" || chainState.going) { f.blocked = "busy"; return; }
    if (chainState.seamPhase && chainState.seamPhase !== "idle") { f.blocked = "seam"; return; }
    if (chainState.host?.isResponding === true) { f.blocked = "responding"; return; }
    if (chainTyping()) { f.blocked = "typing"; return; }
    if (chainFocused() && now() - chainState.touchAt < CHAIN_FOLLOW_IDLE_MS) { f.blocked = "active"; return; }
    if (now() - p.t < CHAIN_FOLLOW_SETTLE_MS) { f.blocked = "settle"; return; }
    f.pending = null;
    const before = chainState.last;
    chainGo({ id: p.to, title: String(y.title ?? "").trim() || p.title }, "bottom", "follow").then(chainSafe(() => {
      const last = chainState.last;
      const ok = last !== before && last?.kind === "follow" && last.to === p.to && last.ok === true;
      f.last = { from: p.from, to: p.to, ok, at: Date.now() };
      f.blocked = ok ? null : last !== before && last?.away ? "moved" : "failed";
    }));
  };
  const onChainTouch = () => { chainState.touchAt = now(); };

  // ---- вид ----
  lateRules.push(
    `#${CHAIN_ROOT_ID}{position:fixed;inset:0;pointer-events:none;z-index:45;font-size:12.5px;line-height:18px}`,
    `#${CHAIN_ROOT_ID}>button{position:fixed;display:none;align-items:center;gap:6px;box-sizing:border-box;max-width:min(560px,calc(100vw - 16px));height:${CHAIN_BUTTON_H}px;margin:0;padding:0 12px;border:1px solid var(--cds-border,rgba(127,127,127,.35));border-radius:15px;background:var(--cds-surface-1,#262624);color:var(--cds-text-primary,inherit);box-shadow:0 2px 10px rgba(0,0,0,.18);pointer-events:auto;cursor:pointer;white-space:nowrap;overflow:hidden;-webkit-app-region:no-drag;transition:background-color .15s;font:inherit}`,
    `#${CHAIN_ROOT_ID}>button[data-show="true"]{display:flex}`,
    `#${CHAIN_ROOT_ID}>button:hover{background:color-mix(in srgb,currentColor 9%,var(--cds-surface-1,#262624))}`,
    `#${CHAIN_ROOT_ID}>button:focus-visible{outline:2px solid var(--cds-text-accent,#d97757);outline-offset:2px}`,
    `#${CHAIN_ROOT_ID}>button>b{flex:none;font-weight:500}`,
    `#${CHAIN_ROOT_ID}>button>span{flex:0 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis}`,
    `#${CHAIN_ROOT_ID}>button>i{flex:none;font-style:normal;color:var(--cds-text-secondary,inherit);opacity:.8}`,
    `#${CHAIN_ROOT_ID}>button>u{position:absolute;left:0;bottom:0;height:2px;width:100%;transform-origin:left;transform:scaleX(var(--pull,0));background:var(--cds-text-accent,#d97757);text-decoration:none;transition:transform .12s}`,
    `#${CHAIN_ROOT_ID}>button[data-state="going"]>b::after{content:"";display:inline-block;width:1.2em;text-align:left;animation:myclaude-chain-dots 1.2s steps(4) infinite}`,
    `#${CHAIN_ROOT_ID}>button[data-state="failed"]{border-color:color-mix(in srgb,#e5484d 60%,transparent)}`,
    `#${CHAIN_ROOT_ID}>button[data-flash="true"]{animation:myclaude-chain-flash ${CHAIN_FLASH_MS}ms ease-out 1}`,
    `#${CHAIN_ROOT_ID}>button[data-k="last"]{height:24px;padding:0 10px;border-radius:12px;font-size:12px;box-shadow:none}`,
    `#${CHAIN_ROOT_ID}>button[data-k="latest"]{cursor:default}`,
    // Зазор над первой строкой ленты: первый ребёнок ленты — колонка flex (Claude 3.1623), псевдоэлемент встаёт её
    // первым элементом и сдвигает строки, а не ложится поверх.
    `${CHAIN_FEED_SELECTOR}[${CHAIN_GAP_ATTRIBUTE}~="top"]>:first-child::before{content:"";display:block;flex:none;height:${CHAIN_GAP_PX}px}`,
    `${CHAIN_FEED_SELECTOR}[${CHAIN_GAP_ATTRIBUTE}~="under"]>:first-child::before{height:${CHAIN_GAP_PX + CHAIN_UNDER_PX}px}`,
    `${CHAIN_FEED_SELECTOR}[${CHAIN_GAP_BOTTOM_ATTRIBUTE}]>:first-child::after{content:"";display:block;flex:none;height:${CHAIN_GAP_BOTTOM_PX}px}`,
    `@keyframes myclaude-chain-flash{0%{box-shadow:0 0 0 0 var(--cds-text-accent,#d97757)}25%{box-shadow:0 0 0 3px var(--cds-text-accent,#d97757)}100%{box-shadow:0 0 0 0 transparent}}`,
    `@keyframes myclaude-chain-dots{0%{content:""}25%{content:"."}50%{content:".."}75%{content:"..."}}`,
    `@media (prefers-reduced-motion: reduce){#${CHAIN_ROOT_ID}>button[data-flash="true"]{animation:none;outline:2px solid var(--cds-text-accent,#d97757);outline-offset:0}#${CHAIN_ROOT_ID}>button>u{transition:none}}`,
  );
  let chainRoot = null;
  const chainNodes = {};
  const chainBuild = () => {
    if (chainRoot?.isConnected) return chainRoot;
    if (!chainRoot) {
      chainRoot = document.createElement("div");
      chainRoot.id = CHAIN_ROOT_ID;
      for (const k of ["up", "down", "last", "latest"]) {
        const b = document.createElement("button");
        b.type = "button";
        b.setAttribute("data-k", k);
        b.setAttribute("data-show", "false");
        chainRoot.appendChild(b);
        chainNodes[k] = b;
      }
    }
    (document.body ?? document.documentElement).appendChild(chainRoot);
    return chainRoot;
  };
  const chainGoingSpot = () => {
    const g = chainState.going;
    if (!g) return "";
    if (g.phase === "land") return g.where === "top" ? "up" : "";
    return g.kind;
  };
  const chainPress = k => {
    const g = chainState.going;
    if (g) { if (g.phase === "land" && chainGoingSpot() === k) g.stop = true; return; }
    const f = chainState.failed;
    if (f && f.kind === k && now() - f.at < CHAIN_FAIL_MS) { chainState.failed = null; chainGo({ id: f.id, title: f.title }, f.where, f.kind); return; }
    if (k === "up") chainGo(chainTarget("up"), "bottom", "up");
    else if (k === "down") chainGo(chainTarget("down"), "top", "down");
    else if (k === "last") chainGo(chainState.links?.last, "bottom", "last");
  };
  const chainFill = (b, label, title, date, tip) => {
    const print = `${label}|${title}|${date}|${tip}`;
    if (b.getAttribute("data-print") === print) return;
    b.setAttribute("data-print", print);
    b.textContent = "";
    const head = document.createElement("b"); head.textContent = label; b.appendChild(head);
    if (title) { const s = document.createElement("span"); s.textContent = title; b.appendChild(s); }
    if (date) { const i = document.createElement("i"); i.textContent = date; b.appendChild(i); }
    b.appendChild(document.createElement("u"));
    b.title = tip || "";
    b.setAttribute("aria-label", [label, title, date].filter(Boolean).join(" "));
  };
  const chainSet = (b, name, value) => { if (b.getAttribute(name) !== value) b.setAttribute(name, value); };
  const chainShow = (b, yes) => chainSet(b, "data-show", yes ? "true" : "false");
  const chainShown = b => b?.getAttribute("data-show") === "true";
  const chainPut = (b, left, top) => {
    const l = `${Math.round(left)}px`;
    const t = `${Math.round(top)}px`;
    if (b.style.left !== l) b.style.left = l;
    if (b.style.top !== t) b.style.top = t;
  };
  const chainOverlap = (a, b) => Math.min(a.right, b.right) - Math.max(a.left, b.left);
  // Видимая часть ленты: сверху её накрывает строка заголовка (только если правда над ней: в широком виде она над
  // правой колонкой), снизу — поле ввода, если оно в той же колонке; в широком виде лента выше окна (низ за краем).
  const chainVisibleBox = el => {
    const r = el.getBoundingClientRect();
    let top = Math.max(r.top, 0);
    let bottom = Math.min(r.bottom, innerHeight);
    const panel = el.closest?.(".epitaxy-chat-panel") ?? null;
    const bar = panel?.querySelector(".epitaxy-titlebar") ?? null;
    const b = bar?.getBoundingClientRect();
    if (b && b.height > 0 && b.bottom > top && b.top < top + 80 && chainOverlap(b, r) > r.width / 2) top = b.bottom;
    try {
      const p = (panel?.querySelector(".epitaxy-prompt") ?? document.querySelector(".epitaxy-prompt"))?.getBoundingClientRect();
      if (p && p.height > 0 && p.top > top + 80 && p.top < bottom && chainOverlap(p, r) > r.width / 2) bottom = p.top;
    } catch {}
    return { left: r.left, right: r.right, width: r.width, top, bottom, bar: b && b.height > 0 ? { el: bar, box: b } : null };
  };
  // «N из M · В последний чат» — в строке заголовка, справа от названия и его меню (знак самого чата, не новая
  // стрелка рядом с «↓» Claude). Не влезает до кнопок справа — под строкой у правого края ленты.
  const chainPlaceLast = (b, box) => {
    const w = b.offsetWidth || 0;
    const bar = box.bar;
    if (bar) {
      const buttons = [...bar.el.querySelectorAll("button")].map(x => ({ x, r: x.getBoundingClientRect() }))
        .filter(x => x.r.width > 0).sort((a, c) => a.r.left - c.r.left);
      const lead = buttons.filter(x => x.x.hasAttribute("data-pane-title") || CHAIN_MORE_RE.test(String(x.x.getAttribute("aria-label") ?? "")));
      if (lead.length) {
        const right = Math.max(...lead.map(x => x.r.right));
        const limit = buttons.find(x => x.r.left > right + 4)?.r.left ?? bar.box.right;
        const left = right + 10;
        if (w > 0 && left + w <= limit - 10) { chainPut(b, left, bar.box.top + (bar.box.height - (b.offsetHeight || 24)) / 2); return "bar"; }
      }
    }
    chainPut(b, box.right - w - 18, box.top + 8);
    return "under";
  };
  const chainRender = () => {
    if (chainState.disposed) return;
    const el = chainState.chat ? chainFeed() : null;
    const links = chainState.links;
    if (!el || !links) {
      for (const b of Object.values(chainNodes)) chainShow(b, false);
      if (el && chainGapOf(el)) { el.removeAttribute(CHAIN_GAP_ATTRIBUTE); chainState.gapDelta = 0; }
      if (el && chainGapBottomOf(el)) { el.removeAttribute(CHAIN_GAP_BOTTOM_ATTRIBUTE); chainState.gapBottom = 0; }
      return;
    }
    chainBuild();
    const at = now();
    const flashFor = chainState.flash?.side === "follow" ? CHAIN_FOLLOW_FLASH_MS : CHAIN_FLASH_MS;
    const flash = chainState.flash && at - chainState.flash.at < flashFor ? chainState.flash.side : "";
    const spot = chainGoingSpot();
    const g = chainState.going;
    const failed = !g && chainState.failed && at - chainState.failed.at < CHAIN_FAIL_MS ? chainState.failed : null;
    const visible = {};
    const seamUp = Boolean(chainState.chat) && chainState.seamTop === chainState.chat;
    for (const dir of ["up", "down"]) {
      const b = chainNodes[dir];
      const to = chainTarget(dir);
      const busy = spot === dir;
      const fail = failed && failed.kind === dir;
      visible[dir] = busy || Boolean(fail) || (Boolean(to) && !g && !(dir === "up" && seamUp) && (chainArmed(dir) || flash === dir));
      if (busy) chainFill(b, chainT(g.phase === "land" ? "landing" : "opening", { t: chainQuoted(g.title) }), "", "", g.phase === "land" ? chainT("stopTip") : "");
      else if (fail) chainFill(b, chainT("failed", { t: chainQuoted(failed.title) }), "", "", "");
      else if (to) chainFill(b, dir === "up" && links.side ? chainT("parent") : chainT(dir === "up" ? "prev" : "next"), chainQuoted(to.title), chainWhen(to.at), chainT("pullTip"));
      chainSet(b, "data-state", busy ? "going" : fail ? "failed" : "");
      chainSet(b, "data-flash", String(flash === dir));
      b.style.setProperty("--pull", chainState.pullDir === dir ? String(Math.min(1, chainState.pull / CHAIN_PULL_PX)) : "0");
      chainShow(b, visible[dir]);
    }
    const box = chainVisibleBox(el);
    // «В последний чат» — в любом не последнем чате; у низа, где «Следующий» и есть последний, — одна кнопка.
    const lastB = chainNodes.last;
    const last = links.last;
    const busyLast = spot === "last";
    const failLast = failed && failed.kind === "last";
    if (busyLast) chainFill(lastB, chainT("opening", { t: chainQuoted(g.title) }), "", "", "");
    else if (failLast) chainFill(lastB, chainT("failed", { t: chainQuoted(failed.title) }), "", "", "");
    else if (last) chainFill(lastB, links.side ? chainT("last") : `${chainT("pos", { i: links.index, n: links.total })} · ${chainT("last")}`, "", "", chainT("lastTip", { t: chainQuoted(last.title), d: chainWhen(last.at) }));
    chainSet(lastB, "data-state", busyLast ? "going" : failLast ? "failed" : "");
    const sameAsNext = last && links.next && last.id === links.next.id && visible.down;
    const lastShow = busyLast || Boolean(failLast) || (Boolean(last) && !sameAsNext);
    chainShow(lastB, lastShow);
    const lastAt = lastShow ? chainPlaceLast(lastB, box) : "";
    // Зазор сверху: плашка у самого верха не закрывает первую строку первого сообщения; фишка под строкой заголовка
    // (узкая колонка) опускает плашку — зазор выше на столько же. Снят зазор, пока ленту крутят вниз, — лента
    // остаётся на месте (сдвиг на зазор); у самого верха — без сдвига, иначе снова взвелась бы.
    const wantGap = visible.up && chainAtTop(el) && (chainGapOf(el) || el.scrollHeight > el.clientHeight + CHAIN_GAP_PX + 16)
      ? (lastAt === "under" ? "top under" : "top") : "";
    if (chainGapOf(el) !== wantGap) {
      if (wantGap) {
        const before = el.scrollHeight;
        el.setAttribute(CHAIN_GAP_ATTRIBUTE, wantGap);
        chainState.gapDelta = Math.max(0, chainState.gapDelta + el.scrollHeight - before);
      } else {
        const delta = chainState.gapDelta;
        el.removeAttribute(CHAIN_GAP_ATTRIBUTE);
        chainState.gapDelta = 0;
        if (delta && el.scrollTop > delta) el.scrollTop -= delta;
      }
    }
    // Зазор снизу — пока виден шов «↓ Следующий чат» у низа: лента докручивается на него, низ остаётся низом;
    // ушли вверх дальше зазора — шов прячется, зазор снимается (над ним ничего не сдвигается).
    const wantBottom = visible.down && chainAtBottom(el);
    if (chainGapBottomOf(el) !== wantBottom) {
      if (wantBottom) {
        const before = el.scrollHeight;
        el.setAttribute(CHAIN_GAP_BOTTOM_ATTRIBUTE, "");
        chainState.gapBottom = Math.max(0, el.scrollHeight - before);
        el.scrollTop = el.scrollHeight;
      } else {
        el.removeAttribute(CHAIN_GAP_BOTTOM_ATTRIBUTE);
        chainState.gapBottom = 0;
      }
    }
    const center = (b, top) => {
      const w = b.offsetWidth || 0;
      const left = Math.max(box.left + 8, Math.min(box.left + (box.width - w) / 2, box.right - w - 8));
      chainPut(b, left, top);
      return { left, right: w ? left + w : box.right, top, bottom: top + CHAIN_BUTTON_H };
    };
    // Низ: «непрочитанные N» (раздел 12х) стоит у правого края над полем — «Следующий чат» встаёт выше неё.
    const lower = b => {
      let top = box.bottom - CHAIN_BUTTON_H - 14;
      const place = center(b, top);
      try {
        const read = document.getElementById(READ_NEXT_ID)?.getBoundingClientRect();
        if (read && read.width > 0 && read.height > 0 && chainOverlap(read, place) > 0 && read.bottom > top - 4 && read.top < place.bottom + 4) {
          top = read.top - CHAIN_BUTTON_H - 8;
          center(b, top);
        }
      } catch {}
    };
    if (visible.up) center(chainNodes.up, box.top + 8 + (lastAt === "under" ? CHAIN_UNDER_PX : 0));
    if (visible.down) lower(chainNodes.down);
    // Приехали в последний чат по кнопке — короткая тихая метка («привёз — подсвети») на месте фишки «N из M» в строке
    // заголовка: в последнем чате фишки нет, а внизу метка легла бы на последнее сообщение. Автопереход — та же метка
    // своей подписью и дольше: человек должен понять, почему окно сменилось.
    const latest = chainNodes.latest;
    const latestShow = (flash === "latest" || flash === "follow") && !links.last;
    if (latestShow) {
      const me = chainState.list?.find(s => s?.sessionId === chainState.chat);
      const title = chainQuoted(String(me?.title ?? "").trim());
      if (flash === "follow") chainFill(latest, chainT("follow"), title, "", chainT("followTip"));
      else chainFill(latest, chainT("latest"), title, "", "");
      chainSet(latest, "data-flash", "true");
      chainPlaceLast(latest, box);
    }
    chainShow(latest, latestShow);
  };

  // ---- события ----
  const chainDelta = (event, el) => (event.deltaMode === 1 ? event.deltaY * 40 : event.deltaMode === 2 ? event.deltaY * el.clientHeight : event.deltaY);
  const onChainWheel = event => {
    const el = chainFeed();
    const node = event?.target;
    if (!el || !node || typeof node !== "object" || !("nodeType" in node) || event.ctrlKey) return;
    const own = Boolean(chainRoot?.contains(node));
    if (!own && !el.contains(node)) return;
    const dy = chainDelta(event, el);
    if (!dy || Math.abs(Number(event.deltaX) || 0) > Math.abs(dy)) return;
    const at = now();
    const gap = at - chainState.wheelAt;
    chainState.wheelAt = at;
    const dir = dy < 0 ? "up" : "down";
    // Докрутку к месту останавливает только новый жест (после паузы) или колесо в обратную сторону: хвост тех же
    // щелчков, которыми начат переход, её не рвёт.
    const g = chainState.going;
    if (g) { if (g.phase === "land" && (gap >= CHAIN_QUIET_MS || dir !== g.dir)) g.stop = true; return; }
    if (at < chainState.settleUntil) return;
    if (dir === "up" && chainState.seamTop && chainState.seamTop === chainState.chat) return;
    // Шов открыт или жест его — колесо его (и вниз: короткий чат у верха и у низа разом не уводит в следующий).
    if ((chainState.seamPhase && chainState.seamPhase !== "idle") || at < chainState.seamHeld) return;
    const to = chainTarget(dir);
    // Колесо в обратную сторону — отмена натяжки.
    if (chainState.pullDir && chainState.pullDir !== dir) { chainState.pull = 0; chainState.pullDir = ""; chainRender(); }
    if (!to || !chainArmed(dir) || (!own && chainNestedTakes(node, el, dy))) return;
    chainState.pull = (chainState.pullDir === dir ? chainState.pull : 0) + Math.abs(dy);
    chainState.pullDir = dir;
    chainState.pullAt = at;
    chainRender();
    if (chainState.pull >= CHAIN_PULL_PX) chainGo(to, dir === "up" ? "bottom" : "top", dir);
  };
  // Esc и клавиши прокрутки — стоп докрутки. Только слушаем: Esc глотает раздел 16 (Claude по нему обрывает ход).
  const onChainKey = event => {
    const g = chainState.going;
    if (!g || g.phase !== "land") return;
    if (event.key === "Escape" && g.where === "top") { g.stop = true; return; }
    if (["ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End"].includes(event.key)) g.stop = true;
  };
  const onChainScroll = event => {
    const el = chainFeed();
    if (!el || event?.target !== el || chainState.raf) return;
    chainState.raf = requestAnimationFrame(chainSafe(() => {
      chainState.raf = 0;
      chainTrackEdges(el);
      if (chainState.pullDir && !chainArmed(chainState.pullDir)) { chainState.pull = 0; chainState.pullDir = ""; }
      chainRender();
    }));
  };
  const onChainClick = event => {
    if (!chainRoot) return;
    let node = event?.target ?? null;
    while (node && node.parentNode !== chainRoot) node = node.parentNode;
    if (!node || node.tagName !== "BUTTON") return;
    event.preventDefault();
    event.stopPropagation();
    chainPress(node.getAttribute("data-k"));
  };
  const chainTick = chainSafe(() => {
    if (chainState.disposed) return;
    const id = chainId();
    if (id !== chainState.chat) {
      chainState.chat = id;
      chainState.missAt = 0;
      chainRelink();
      chainState.pull = 0;
      chainState.pullDir = "";
      chainState.edges.up.since = 0;
      chainState.edges.down.since = 0;
      if (!chainState.going) chainState.settleUntil = now() + CHAIN_SETTLE_MS;
      if (id) chainRefresh(true);
      chainWindowsWrite(true);
    } else if (id) chainRefresh();
    // Натяжка без колеса плавно спадает.
    if (chainState.pull && now() - chainState.pullAt > CHAIN_DECAY_AFTER_MS) {
      chainState.pull = Math.max(0, chainState.pull - CHAIN_PULL_PX * 0.15);
      if (!chainState.pull) chainState.pullDir = "";
    }
    chainTrackEdges(id ? chainFeed() : null);
    chainWindowsWrite();
    chainFollowTry();
    chainRender();
  });
  // Сирота прошлой установки (её dispose не дошёл) — снять до своей.
  try {
    for (const node of document.querySelectorAll(`#${CHAIN_ROOT_ID}`)) node.remove();
    for (const node of document.querySelectorAll(`[${CHAIN_GAP_ATTRIBUTE}],[${CHAIN_GAP_BOTTOM_ATTRIBUTE}]`)) { node.removeAttribute(CHAIN_GAP_ATTRIBUTE); node.removeAttribute(CHAIN_GAP_BOTTOM_ATTRIBUTE); }
  } catch {}
  track(() => {
    chainState.disposed = true;
    if (chainState.going) chainState.going.stop = true;
    if (chainLive) chainWindowsDrop();
    for (const id of chainTimers) clearTimeout(id);
    chainTimers.clear();
    if (chainState.raf) { cancelAnimationFrame(chainState.raf); chainState.raf = 0; }
    try { chainRoot?.remove(); } catch {}
    try { for (const node of document.querySelectorAll(`#${CHAIN_ROOT_ID}`)) node.remove(); } catch {}
    try { for (const node of document.querySelectorAll(`[${CHAIN_GAP_ATTRIBUTE}],[${CHAIN_GAP_BOTTOM_ATTRIBUTE}]`)) { node.removeAttribute(CHAIN_GAP_ATTRIBUTE); node.removeAttribute(CHAIN_GAP_BOTTOM_ATTRIBUTE); } } catch {}
  });
  if (chainLive) {
    on(window, "wheel", chainSafe(onChainWheel), { capture: true, passive: true });
    on(window, "scroll", chainSafe(onChainScroll), { capture: true, passive: true });
    // Раньше раздела 16 (он подписан ниже и глотает Esc на том же захвате окна).
    on(window, "keydown", chainSafe(onChainKey), true);
    on(document, "click", chainSafe(onChainClick), true);
    on(window, "resize", chainSafe(chainRender));
    // Автопереход ждёт, пока человек не трогает окно: колесо, клавиши, нажатие — где угодно в окне.
    for (const type of ["wheel", "keydown", "pointerdown"]) on(window, type, onChainTouch, { capture: true, passive: true });
    const chainTimer = setInterval(chainTick, CHAIN_TICK_MS);
    track(() => clearInterval(chainTimer));
    chainTick();
  }
  // Сквозная история (раздел 13б): чат, соседи по линии, список, края, натяжка, идущий и последний переход, что видно.
  statusPart("chain", () => {
    const el = chainState.chat ? chainFeed() : null;
    const host = chainState.host;
    const pick = item => (item ? { id: item.id, title: item.title } : null);
    const links = chainState.links;
    return {
      on: chainLive, chat: chainState.chat || null,
      links: links ? { side: links.side, index: links.index, total: links.total, prev: pick(links.prev), next: pick(links.next), last: pick(links.last) } : null,
      list: chainState.list ? chainState.list.length : null, listError: chainState.listError,
      host: host ? { olderHistoryAbove: host.olderHistoryAbove ?? null, isPoolPending: host.isPoolPending ?? null, isResponding: host.isResponding ?? null } : null,
      armed: { up: chainArmed("up"), down: chainArmed("down") }, pull: Math.round(chainState.pull), pullDir: chainState.pullDir, gap: chainGapOf(el), gapBottom: chainGapBottomOf(el),
      going: chainState.going ? { id: chainState.going.id, kind: chainState.going.kind, where: chainState.going.where, phase: chainState.going.phase } : null,
      failed: chainState.failed ? { id: chainState.failed.id, kind: chainState.failed.kind } : null,
      gos: chainState.gos, last: chainState.last, error: chainState.error,
      follow: {
        pending: chainState.follow.pending ? { from: chainState.follow.pending.from, to: chainState.follow.pending.to, since: chainState.follow.pending.since } : null,
        blocked: chainState.follow.blocked, last: chainState.follow.last,
      },
      shown: Object.fromEntries(Object.entries(chainNodes).map(([k, b]) => [k, chainShown(b)])),
    };
  });
  HATCH && Object.assign(HATCH, { chainOf, chainAt, chainFolder, chainState, chainTick, chainRender, chainPress, chainPinned, feedHold, CHAIN_PULL_PX, CHAIN_GAP_PX, chainWindowId, CHAIN_WINDOWS_KEY, CHAIN_FOLLOW_WINDOW_MS });
