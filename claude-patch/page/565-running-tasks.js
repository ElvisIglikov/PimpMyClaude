  // ---- 12х⁴. Фоновые задачи серым под последним сообщением (#5548) ----
  // Слово Элвиса: «Здесь Running Task — непонятно, что за задача выполняется… Хочу, чтобы все задания выводились
  // ниже списком сереньким шрифтом всегда, в одном и том же месте под сообщением, если есть хотя бы одна, чтобы
  // понимать, какие работают, какие не работают. Часто кажется, что он завис».
  // Замер 19.10.2026 (Claude 2.42304; код ленты — веб-сборка claude.ai из кэша окна, только чтение): фоновая задача
  // в списке ходов (entries — его читает тик «Прочитано», 12х) — блок хода {kind: "task_event", id, taskId,
  // description, taskType, status: running | completed | failed | stopped, summary, durationMs, startedAt (мс Unix),
  // suppressedByWorkflow}. Claude правит его на месте, пока задача идёт; задача, пришедшая за открытой группой
  // инструментов, лежит в ней: items[kind="tools"].taskEvents[] = {at, ev: <тот же task_event>}. Задачи Workflow
  // (suppressedByWorkflow) Claude в карточке «N running» не считает — мы тоже. Отметки конца в списке нет: конец —
  // startedAt + durationMs, иначе — когда страница увидела задачу законченной. Карточка «N background commands
  // running» — кнопка [data-transcript-keeps-pin]; её задачи — в React-пропсах (focusTaskId, events).
  // • Блок — последним ребёнком колонки ([data-transcript-column-row]) последней видимой строки ленты: под
  //   сообщением и под строкой «Работа идёт» (12х¹), вне сообщения Claude — свёртки 12х, 12х¹ и 12х³ его не
  //   прячут и не перебирают. Низа ленты в DOM нет (человек читает выше) — блока нет, это не ошибка.
  // • Строка на задачу: «● имя · 3 мин» — идёт (все, давние сверху); «✕ имя · не вышло» (или «· остановлена») и
  //   «✓ имя · 1 мин» (сколько шла; не больше трёх последних) — закончилась не раньше 2 мин назад. Имя — до 60
  //   знаков по слову, без многоточия; полное — в подсказке. «Идёт» дольше 12 ч — сирота прошлого сеанса: не
  //   показывается, счёт — status().runningTasks.stale.
  // • Текста в узлах нет: подпись в атрибуте и ::after — innerText ленты тот же. Время тикает от сердцебиения
  //   (tasksTick, раздел 16) — меняется только атрибут: главный наблюдатель (childList, characterData) его не видит,
  //   контракт 220. Вставка и снятие блока будят обходы один раз; своего таймера нет.
  // • Нажатие (Enter, пробел) — нажатие на родную карточку задачи: Claude открывает панель задач на ней (её onClick —
  //   openTasksPaneAtTask), свёрнутая карточка жмётся так же. Карточки нет в DOM — лента едет к её ходу и жмёт, когда
  //   карточка придёт (пока идёт переход, не дольше TASKS_PENDING_MS); не узнали карточку — только едет.
  // • Не узнал разметку (списка ходов нет или в нём нет задач, а карточка «running» есть) — блока нет; незнакомый
  //   статус — задача пропущена. Причина — в status().runningTasks.error. Узлы Claude не трогаем.
  const TASKS_ATTRIBUTE = "data-myclaude-tasks";
  const TASKS_ROW_ATTRIBUTE = "data-myclaude-tasks-row";
  const TASKS_TEXT_ATTRIBUTE = "data-myclaude-tasks-text";
  const TASKS_COLUMN = "[data-transcript-column-row]";
  const TASKS_PIN = "button[data-transcript-keeps-pin]";
  const TASKS_KEEP_MS = 2 * 60 * 1000;
  const TASKS_DONE_MAX = 3;
  const TASKS_NAME_MAX = 60;
  const TASKS_STALE_MS = 12 * 60 * 60 * 1000;
  const TASKS_PENDING_MS = 8000;
  const TASKS_FIBER_HOPS = 6;
  // Список задач Claude (замер 21.10.2026, Claude 2.42304): пропс value React-узла выше ленты (у Рика — 164 шага
  // вверх) — [{taskId, toolUseId, description, taskType, status, startedAt, completedAt, parentTaskId…}]. Блок хода
  // task_event Claude кладёт не всегда (фоновая команда хода, кончившегося раньше неё, его не получает), а этот список
  // знает каждую задачу сеанса. Берём только задачи, чей вызов инструмента есть в этом чате, без вложенных.
  const TASKS_STORE_HOPS = 260;
  const tasksStoreOf = () => {
    try {
      const feed = readFeed();
      let fiber = feed ? chatFiberOf(feed) : null;
      for (let hop = 0; fiber && hop < TASKS_STORE_HOPS; hop += 1, fiber = fiber.return) {
        const value = fiber.memoizedProps?.value;
        if (Array.isArray(value) && value.length && typeof value[0]?.taskId === "string" && "toolUseId" in value[0]) return value;
      }
    } catch {}
    return null;
  };
  const TASKS_STATUS = {
    running: "run", in_progress: "run", pending: "run", started: "run",
    completed: "done", complete: "done", success: "done", succeeded: "done", done: "done",
    failed: "fail", failure: "fail", error: "fail",
    stopped: "stop", killed: "stop", cancelled: "stop", canceled: "stop", interrupted: "stop",
  };
  const TASKS_TAIL = { fail: "не вышло", stop: "остановлена" };
  const TASKS_SAY = { run: "Идёт", done: "Готово", fail: "Не вышло", stop: "Остановлена" };
  // primed — первый ход списка, который страница уже видела в этом чате (null — ещё ни одного): законченная задача
  // без отметок — новость, только если список тот же (не первый взгляд на чат и не чужой список на смене чата).
  const tasksState = {
    chat: undefined, primed: null, seen: new Map(), cache: new WeakMap(), tasks: [], keys: "", found: 0, listed: false,
    block: null, nodes: new Map(), placed: false, pending: null,
    running: 0, done: 0, failed: 0, stale: 0, markError: null, spotError: null, clicks: 0,
  };
  // Имя задачи без описания — по её виду.
  const tasksKindOf = type => {
    const kind = String(type ?? "").toLowerCase();
    if (/bash|shell|command/.test(kind)) return "фоновая команда";
    if (/agent|teammate/.test(kind)) return "агент";
    if (/workflow/.test(kind)) return "Workflow";
    return "фоновая задача";
  };
  const tasksTimeOf = value => {
    const ms = typeof value === "number" ? value : typeof value === "string" && value.trim() ? Date.parse(value) : NaN;
    return Number.isFinite(ms) && ms > 0 ? ms : null;
  };
  // Фоновая задача из блока списка ходов (чистая функция): {key, item, status, raw, name, named, start, end, duration};
  // не задача или задача Workflow — null. status: run | done | fail | stop, незнакомый — null (raw — как пришёл).
  const tasksInfoOf = item => {
    if (!item || typeof item !== "object" || item.kind !== "task_event" || item.suppressedByWorkflow === true) return null;
    const pick = names => {
      for (const name of names) { const value = item[name]; if (value != null && value !== "") return value; }
      return null;
    };
    const raw = pick(["status", "state"]);
    const key = pick(["taskId", "task_id"]);
    const own = pick(["description", "command", "title"]);
    const text = sayNorm(own != null ? String(own) : String(pick(["summary"]) ?? "").split("\n").find(line => line.trim()) ?? "");
    const spent = pick(["durationMs", "duration_ms"]);
    const duration = spent == null ? NaN : Number(spent);
    return {
      key: key == null ? null : String(key),
      item: item.id == null ? null : String(item.id),
      status: TASKS_STATUS[String(raw ?? "").trim().toLowerCase()] ?? null,
      raw: raw == null ? null : String(raw),
      name: text || tasksKindOf(pick(["taskType", "task_type"])),
      named: Boolean(text),
      start: tasksTimeOf(pick(["startedAt", "started_at"])),
      end: tasksTimeOf(pick(["endedAt", "ended_at", "completedAt"])),
      duration: Number.isFinite(duration) && duration >= 0 ? duration : null,
    };
  };
  // Имя строки (чистая функция): до TASKS_NAME_MAX знаков; длинное — по последнему целому слову, без многоточия.
  const tasksName = value => {
    const text = sayNorm(value);
    if (text.length <= TASKS_NAME_MAX) return text;
    const cut = text.slice(0, TASKS_NAME_MAX + 1);
    const at = cut.lastIndexOf(" ");
    return (at >= TASKS_NAME_MAX / 2 ? cut.slice(0, at) : text.slice(0, TASKS_NAME_MAX)).replace(/[\s,.;:—–-]+$/u, "");
  };
  // Сколько времени (чистая функция): «12 с», «3 мин», «1 ч 5 мин», «2 ч».
  const tasksAge = ms => {
    const seconds = Math.max(0, Math.floor(Number(ms) / 1000) || 0);
    if (seconds < 60) return `${seconds} с`;
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes} мин`;
    const rest = minutes % 60;
    return rest ? `${Math.floor(minutes / 60)} ч ${rest} мин` : `${Math.floor(minutes / 60)} ч`;
  };
  // Задачи чата по списку ходов. Блоки одной задачи — одна запись: имя — первое настоящее, начало — самое раннее,
  // статус — последний. Разбор хода (где у него задачи и группы инструментов) помнится за объектом хода, как в 12х¹;
  // поля задач читаются каждый раз — Claude правит их на месте.
  const tasksSync = () => {
    if (readState.chat !== tasksState.chat) {
      tasksState.chat = readState.chat;
      tasksState.seen.clear();
      tasksState.primed = null;
      tasksState.pending = null;
    }
    const entries = workState.entries;
    const head = Array.isArray(entries) && typeof entries[0]?.id === "string" ? entries[0].id : null;
    const news = head != null && tasksState.primed === head;
    const found = new Map();
    let error = null;
    const put = (item, slot, entryId, last) => {
      const info = tasksInfoOf(item);
      if (!info) return;
      if (!info.status) { error = `статус фоновой задачи не узнан: ${String(info.raw).slice(0, 40)}`; return; }
      const key = info.key ?? (info.item ? `item:${info.item}` : `${entryId}:${slot}`);
      const task = found.get(key);
      if (!task) { found.set(key, { ...info, key, keyed: info.key != null, entry: entryId, last }); return; }
      if (!task.named && info.named) { task.name = info.name; task.named = true; }
      if (info.start != null && (task.start == null || info.start < task.start)) task.start = info.start;
      Object.assign(task, { status: info.status, end: info.end ?? task.end, duration: info.duration ?? task.duration, entry: entryId, last });
    };
    // Вызов инструмента → ход, где он (для списка задач Claude).
    const toolEntry = new Map();
    // Задачи, которые Claude в ходе прячет как задачи Workflow (suppressedByWorkflow), — и из списка не берём.
    const hidden = new Set();
    if (Array.isArray(entries)) {
      let lastId = null;
      for (let at = entries.length - 1; at >= 0 && lastId == null; at -= 1) {
        if (entries[at]?.author === "assistant" && typeof entries[at].id === "string") lastId = entries[at].id;
      }
      for (const entry of entries) {
        if (entry?.author !== "assistant" || typeof entry.id !== "string" || !Array.isArray(entry.items)) continue;
        const items = entry.items;
        const size = items.length;
        let known = tasksState.cache.get(entry);
        if (!known || known.size !== size || known.tail !== items[size - 1]) {
          const spots = [];
          items.forEach((item, index) => { if (item?.kind === "task_event" || item?.kind === "tools") spots.push(index); });
          known = { size, tail: items[size - 1], spots };
          tasksState.cache.set(entry, known);
        }
        const last = entry.id === lastId;
        const add = (item, slot) => put(item, slot, entry.id, last);
        for (const index of known.spots) {
          const item = items[index];
          if (item?.kind === "task_event") {
            if (item.suppressedByWorkflow === true && item.taskId != null) hidden.add(String(item.taskId));
            add(item, index);
          } else if (item?.kind === "tools") {
            if (Array.isArray(item.tools)) for (const tool of item.tools) if (typeof tool?.id === "string") toolEntry.set(tool.id, { id: entry.id, last });
            if (Array.isArray(item.taskEvents)) item.taskEvents.forEach((row, at) => {
              if (row?.ev?.suppressedByWorkflow === true && row.ev.taskId != null) hidden.add(String(row.ev.taskId));
              if (row?.ev) add(row.ev, `${index}.${at}`);
            });
          }
        }
      }
      // Список задач Claude — последним: его статус свежее блоков хода.
      if (toolEntry.size) {
        for (const task of tasksStoreOf() ?? []) {
          const spot = typeof task?.toolUseId === "string" ? toolEntry.get(task.toolUseId) : null;
          if (!spot || task.parentTaskId || task.suppressedByWorkflow === true || hidden.has(String(task.taskId))) continue;
          put({ ...task, kind: "task_event" }, task.taskId, spot.id, spot.last);
        }
      }
    }
    // Время — часы Unix, как у отметок задач (now() раздела 1 — от загрузки страницы).
    const t = Date.now();
    const tasks = [];
    let stale = 0;
    for (const task of found.values()) {
      let seen = tasksState.seen.get(task.key);
      const fresh = !seen;
      if (!seen) { seen = { runAt: null, endAt: null }; tasksState.seen.set(task.key, seen); }
      if (task.status === "run") {
        seen.runAt ??= t;
        seen.endAt = null;
        // Задача без своего ключа (его нет — конца к ней не приклеить) идёт только в последнем ходе.
        if (!task.keyed && !task.last) continue;
        task.start ??= seen.runAt;
        if (t - task.start > TASKS_STALE_MS) { stale += 1; continue; }
      } else {
        // Конец: по отметкам задачи; нет их — когда страница увидела задачу законченной: шла у нас на глазах или
        // пришла новой в последний ход. Законченная до открытия чата (перезагрузка) без отметок — не новость.
        if (seen.endAt == null && (seen.runAt != null || (fresh && news && task.last))) seen.endAt = t;
        task.end ??= task.start != null && task.duration != null ? task.start + task.duration : seen.endAt;
        if (task.end == null || t - task.end > TASKS_KEEP_MS) continue;
        task.start ??= seen.runAt;
      }
      tasks.push(task);
    }
    tasksState.primed = head;
    Object.assign(tasksState, { tasks, stale, markError: error, found: found.size, listed: Array.isArray(entries) });
  };
  // Задач в списке ходов нет (или списка нет вовсе), а карточка Claude говорит «running» — разметка не узнана.
  // Считается, когда спрашивают status(): тик в покое ленту ради этого не обходит.
  const tasksMissed = () => {
    if (tasksState.found) return null;
    try {
      for (const pin of document.querySelectorAll(`${READ_ROW_SELECTOR} ${TASKS_PIN}`)) {
        if (!/\brunning\b|выполняется/i.test(pin.textContent ?? "")) continue;
        return tasksState.listed ? "в списке ходов нет фоновых задач, а карточка «running» есть" : "лента не отдала список ходов, а карточка «running» есть";
      }
    } catch {}
    return null;
  };
  // Строки блока на миг t: идущие — все, давние сверху; закончившиеся не раньше TASKS_KEEP_MS назад — по времени конца,
  // готовых — не больше TASKS_DONE_MAX последних. Ушедшие за срок выпадают из списка насовсем (до новой сверки).
  const tasksRows = t => {
    tasksState.tasks = tasksState.tasks.filter(task => task.status === "run" || t - task.end <= TASKS_KEEP_MS);
    const run = tasksState.tasks.filter(task => task.status === "run").sort((a, b) => a.start - b.start);
    const ended = tasksState.tasks.filter(task => task.status !== "run").sort((a, b) => a.end - b.end);
    const done = ended.filter(task => task.status === "done").slice(-TASKS_DONE_MAX);
    const rows = [];
    for (const task of [...run, ...ended]) {
      if (task.status === "done" && !done.includes(task)) continue;
      let tail = TASKS_TAIL[task.status] ?? null;
      if (task.status === "run") tail = tasksAge(t - task.start);
      if (task.status === "done") {
        const spent = task.duration ?? (task.start != null ? task.end - task.start : null);
        tail = spent == null ? null : tasksAge(spent);
      }
      const mark = task.status === "run" ? "●" : task.status === "done" ? "✓" : "✕";
      const name = tasksName(task.name);
      // Голосом — слово статуса впереди, время — после имени («не вышло» второй раз не повторяется).
      const spoken = task.status === "run" || task.status === "done" ? tail : null;
      rows.push({
        key: task.key, kind: task.status === "stop" ? "fail" : task.status,
        text: `${mark} ${name}${tail ? ` · ${tail}` : ""}`,
        label: `${TASKS_SAY[task.status]}: ${sayNorm(task.name)}${spoken ? `, ${spoken}` : ""}`,
        title: `${sayNorm(task.name)}\nОткрыть задачу`,
      });
    }
    tasksState.running = rows.filter(row => row.kind === "run").length;
    tasksState.done = rows.filter(row => row.kind === "done").length;
    tasksState.failed = rows.filter(row => row.kind === "fail").length;
    return rows;
  };
  // Место блока: колонка последней видимой строки ленты, когда низ ленты в DOM (последняя строка — последнего хода;
  // ходы после неё ещё пусты). Низа нет — null; строка без колонки — false (разметка не узнана).
  const tasksSpot = () => {
    const entries = workState.entries;
    if (!Array.isArray(entries) || !entries.length) return null;
    const rows = readRowsNow();
    const tail = rows[rows.length - 1];
    const id = tail ? readEntryOf(tail) : null;
    if (!id) return null;
    let bottom = false;
    for (let at = entries.length - 1; at >= 0; at -= 1) {
      if (entries[at]?.id === id) { bottom = true; break; }
      if (!Array.isArray(entries[at]?.items) || entries[at].items.length) break;
    }
    if (!bottom) return null;
    for (let at = rows.length - 1; at >= 0; at -= 1) {
      const row = rows[at];
      // Строки нулевой высоты: занятая свёрнутой серией (12х¹), свёрнутого прочитанного (12х), ответ-точка (12х³).
      if (row.getAttribute(WORK_ATTRIBUTE) === "row" || row.getAttribute(READ_ROW_ATTRIBUTE) === "rest"
        || ["row", "gap"].includes(row.getAttribute(DOT_ATTRIBUTE))) continue;
      let column = null;
      try { column = row.querySelector(TASKS_COLUMN); } catch {}
      return column ?? false;
    }
    return null;
  };
  const tasksMakeRow = () => {
    const node = document.createElement("div");
    node.setAttribute(TASKS_ROW_ATTRIBUTE, "run");
    node.setAttribute("role", "button");
    node.setAttribute("tabindex", "0");
    return node;
  };
  // Строки блока по списку: узел строки — за ключом задачи (фокус и наведение переживают тик); порядок
  // переставляется, только когда он не тот.
  const tasksDress = rows => {
    const block = tasksState.block;
    if (!block) return;
    const nodes = new Map();
    let order = block.children.length !== rows.length;
    rows.forEach((row, at) => {
      const node = tasksState.nodes.get(row.key) ?? tasksMakeRow();
      node.__myclaudeTask = row.key;
      nodes.set(row.key, node);
      foldSet(node, TASKS_ROW_ATTRIBUTE, row.kind);
      foldSet(node, TASKS_TEXT_ATTRIBUTE, row.text);
      foldSet(node, "aria-label", row.label);
      foldSet(node, "title", row.title);
      if (block.children[at] !== node) order = true;
    });
    if (order) {
      const keep = new Set(nodes.values());
      for (const node of [...block.children]) if (!keep.has(node)) { try { node.remove(); } catch {} }
      for (const node of keep) block.appendChild(node);
    }
    tasksState.nodes = nodes;
  };
  // Блок — на месте или снят. Лента стояла у низа — у низа и остаётся; читают выше — блок ниже экрана, ничего не едет.
  const tasksPaint = rows => {
    let spot = rows.length ? tasksSpot() : null;
    tasksState.spotError = spot === false ? "у строки ленты нет колонки [data-transcript-column-row]: блок не поставлен" : null;
    if (spot === false) spot = null;
    let block = tasksState.block;
    const right = Boolean(spot && block && block.parentNode === spot && spot.lastElementChild === block);
    if (spot) {
      if (!block) {
        block = document.createElement("div");
        block.setAttribute(TASKS_ATTRIBUTE, "");
        block.setAttribute("role", "group");
        block.setAttribute("aria-label", "Фоновые задачи");
        tasksState.block = block;
      }
      tasksDress(rows);
    }
    tasksState.placed = Boolean(spot);
    if (right || (!spot && !block?.parentNode)) return;
    const feed = readFeed();
    let pinned = false;
    try { pinned = Boolean(feed) && feed.scrollHeight - feed.scrollTop - feed.clientHeight < 2; } catch {}
    try { if (spot) spot.appendChild(block); else block.remove(); } catch { tasksState.placed = false; }
    if (pinned) { try { feed.scrollTop = feed.scrollHeight; } catch {} }
  };
  // Кнопка задачи в ленте: React-пропсы кнопки и её родителей (focusTaskId карточки, events и run её задач).
  const tasksIdsOf = button => {
    const ids = new Set();
    let fiber = chatFiberOf(button);
    for (let hop = 0; fiber && hop <= TASKS_FIBER_HOPS; hop += 1, fiber = fiber.return) {
      const props = fiber.memoizedProps;
      if (!props || typeof props !== "object") continue;
      for (const value of [props.focusTaskId, props.taskId, props.entry?.taskId, props.item?.taskId, props.tool?.taskId, props.ev?.taskId]) {
        if (typeof value === "string" && value) ids.add(value);
      }
      for (const list of [props.events, props.run, props.taskEventRun]) {
        if (Array.isArray(list)) for (const one of list) if (typeof one?.taskId === "string") ids.add(one.taskId);
      }
    }
    return ids;
  };
  // Кнопка задачи среди строк её хода, что в DOM: сперва карточка фоновых задач, потом любая другая её кнопка.
  const tasksCardOf = job => {
    let other = null;
    for (const row of readRowsNow()) {
      if (readEntryOf(row) !== job.entry) continue;
      let buttons = [];
      try { buttons = [...row.querySelectorAll("button")]; } catch {}
      for (const button of buttons) {
        if (!tasksIdsOf(button).has(job.key)) continue;
        if (button.matches(TASKS_PIN)) return button;
        other ??= button;
      }
    }
    return other;
  };
  // Нажатие на строку: нажать родную карточку задачи. Её нет в DOM — лента едет к ходу задачи, нажатие ждёт карточку.
  const tasksOpen = key => {
    const task = tasksState.tasks.find(item => item.key === key);
    if (!task) return false;
    tasksState.clicks += 1;
    const job = { key: task.key, entry: task.entry, until: now() + TASKS_PENDING_MS };
    const button = tasksCardOf(job);
    if (button) {
      tasksState.pending = null;
      try { button.click(); } catch {}
      return true;
    }
    readSeek(task.entry, { flash: true, smooth: true });
    // Нажатие ждёт, пока идёт этот переход: человек взялся за ленту сам (переход снят) — карточку уже не жмём.
    job.seek = readState.seek;
    tasksState.pending = job;
    tasksPendingTry();
    return true;
  };
  // Карточка пришла, пока переход идёт или после того, как он довёл ход до места (settle — его шаги на месте, 12х), —
  // нажать. Переход кончился (последняя попытка — сейчас) или срок вышел — больше не ждать; снят человеком по пути —
  // не жать.
  const tasksPendingTry = () => {
    const job = tasksState.pending;
    if (!job) return;
    const button = tasksCardOf(job);
    const going = Boolean(job.seek) && readState.seek === job.seek;
    if (button || !going || now() > job.until) tasksState.pending = null;
    if (button && (going || job.seek?.settle > 0)) { try { button.click(); } catch {} }
  };
  // Тик сердцебиения (раздел 16): dirty — лента менялась, список задач сверяется заново; иначе только подписи и
  // срок. Блок, который пропал из DOM (лента пересоздала строку), ставится снова; снятый намеренно — ждёт сверки.
  const tasksTick = (dirty = false) => {
    if (!state.alive) return;
    if (dirty) tasksSync();
    if (!tasksState.tasks.length && !tasksState.placed && !tasksState.block?.parentNode && !tasksState.pending) {
      tasksState.running = tasksState.done = tasksState.failed = 0;
      return;
    }
    const rows = tasksRows(Date.now());
    const keys = rows.map(row => row.key).join("\n");
    if (dirty || keys !== tasksState.keys || (tasksState.placed && !tasksState.block?.isConnected)) tasksPaint(rows);
    else if (tasksState.placed) tasksDress(rows);
    tasksState.keys = keys;
    tasksPendingTry();
  };
  const tasksRowOf = target => {
    let row = null;
    try { row = target?.closest?.(`[${TASKS_ROW_ATTRIBUTE}]`) ?? null; } catch {}
    return row && tasksState.block?.contains(row) ? row : null;
  };
  // Нажатие и Enter / пробел на строке — на захвате document (раньше React Claude, позже window-слушателей 12х:
  // те снимают идущий переход до того, как строка его начнёт).
  const onTasksClick = event => {
    if (!state.alive) return;
    const row = tasksRowOf(event?.target);
    if (!row) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    if (Number(event.detail) > 1) return;
    try { tasksOpen(row.__myclaudeTask); } catch {}
  };
  const onTasksKey = event => {
    if (!state.alive) return;
    const key = event?.key;
    if (key !== "Enter" && key !== " " && key !== "Spacebar") return;
    const row = tasksRowOf(event?.target);
    if (!row) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    if (event.repeat) return;
    try { tasksOpen(row.__myclaudeTask); } catch {}
  };
  // Только в окне Claude (как подписки поля ввода, раздел 16): на чужой странице ленты нет.
  if (themable) {
    on(document, "click", onTasksClick, true);
    on(document, "keydown", onTasksKey, true);
  }
  lateRules.push(
    `[${TASKS_ATTRIBUTE}]{display:flex;flex-direction:column;align-items:flex-start;align-self:flex-start;box-sizing:border-box;max-width:100%;margin:4px 0 2px;font-size:12px;line-height:1.45;font-weight:400;color:var(--cds-text-muted,currentColor);font-variant-numeric:tabular-nums}`,
    `[${TASKS_ROW_ATTRIBUTE}]{box-sizing:border-box;max-width:calc(100% + 4px);margin:0 0 0 -4px;padding:1px 6px 1px 4px;border-radius:6px;white-space:normal;overflow-wrap:anywhere;cursor:pointer;user-select:none;-webkit-user-select:none;-webkit-app-region:no-drag;transition:background-color .15s}`,
    `[${TASKS_ROW_ATTRIBUTE}]::after{content:attr(${TASKS_TEXT_ATTRIBUTE})}`,
    `[${TASKS_ROW_ATTRIBUTE}]:hover{background:rgba(127,127,127,.14)}`,
    `[${TASKS_ROW_ATTRIBUTE}]:active{background:rgba(127,127,127,.24)}`,
    `[${TASKS_ROW_ATTRIBUTE}]:focus-visible{outline:2px solid rgba(245,158,11,.7);outline-offset:1px}`,
    `@media (prefers-reduced-motion: reduce){[${TASKS_ROW_ATTRIBUTE}]{transition:none}}`,
  );
  // Сироты прошлой установки — до первой разметки.
  const tasksSweep = () => {
    try { for (const node of document.querySelectorAll(`[${TASKS_ATTRIBUTE}]`)) node.remove(); } catch {}
  };
  tasksSweep();
  track(() => {
    try { tasksState.block?.remove(); } catch {}
    Object.assign(tasksState, { block: null, placed: false, pending: null, tasks: [], keys: "" });
    tasksState.nodes.clear();
    tasksState.seen.clear();
    tasksSweep();
  });
  // Фоновые задачи (#5548, раздел 12х⁴): блок в ленте; строк — идёт, готово, не вышло (с остановленными); stale —
  // «идёт» дольше 12 ч (не показаны); error — разметка не узнана, блока нет.
  statusPart("runningTasks", () => ({
    shown: Boolean(tasksState.block?.isConnected), running: tasksState.running, done: tasksState.done, failed: tasksState.failed,
    error: tasksState.markError ?? tasksState.spotError ?? tasksMissed(), stale: tasksState.stale,
  }));
  HATCH && Object.assign(HATCH, { tasksInfoOf, tasksName, tasksAge, tasksTick, tasksState });

