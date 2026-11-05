  // ---- 12х. «Прочитано» у ответов (#9377, WF215) ----------------------------
  // Слово Элвиса 10.10: в длинном чате теряется, какие ответы прочитаны, а пропущенные искать долго —
  // «слева нажимать… на зону… ответ помечался бы как прочитанный… сереньким», «кнопка… плавающая…
  // непрочитанные… ненавязчиво», «правой кнопкой неохота», «одно поле», «прочитанные сворачивал…
  // большими блоками… заметные, но всё же свёрнутые».
  // Ответ — весь ход ассистента: Claude пишет его id (msg_…) на каждую строку ленты хода
  // (data-epitaxy-entry у колонки строки, data-turn-key у сообщения; замер 10.10, Claude 2.31226) —
  // это и есть ключ пометки: он не зависит от места в DOM и переживает перезапуск.
  // • Дорожка — свой узел в каждой строке ответа, слева от текста; у первой — роль кнопки и место в
  //   порядке Tab. Нажал (Enter, пробел) — ответ помечен и свёрнут одним блоком: первая строка текста
  //   и «прочитано». Нажал на блок — раскрыт, пометка остаётся; ещё раз на дорожку — пометка снята.
  //   Ответ, который ещё пишется, не помечается.
  // • Свёртка — метками на строках и правилами раздела 4; узлы Claude не удаляются и не
  //   переставляются. Лента виртуальная: строки вне экрана в DOM отсутствуют и приходят заново —
  //   метки возвращаются в том же колбэке мутаций, до отрисовки.
  // • «непрочитанные N» — в доке поля ввода, пока есть что показать. Счёт — по списку ходов ленты
  //   (пропс entries у React-узла над лентой — там и ходы вне экрана); списка нет — только по
  //   строкам в DOM, и status().read.lastError говорит об этом. Непрочитанные — ответы без пометки
  //   ПОСЛЕ первого помеченного: в старом длинном чате без пометок кнопки нет вовсе.
  //   Нажал — лента едет к следующему непрочитанному ниже, после последнего — к первому.
  // • Пометки — localStorage[READ_KEY] = {<ключ чата раздела 2а>: {at, ids}} — общие у окон; потолок —
  //   readStoreTrim. Запись не удалась — пометки живут до закрытия окна, причина — в lastError.
  //   Раскрытые прочитанные помнятся, пока окно открыто.
  const READ_KEY = "myclaude-read-v1";
  const READ_CHATS_MAX = 40;
  const READ_IDS_MAX = 600;
  const READ_TOTAL_MAX = 6000;
  const READ_FIBER_DEPTH = 40;
  const READ_ROW_SELECTOR = '[data-testid="transcript-row"]';
  const READ_FEED_SELECTOR = '[data-testid="epitaxy-virtual-transcript"]';
  const READ_ZONE_MIN = 12;
  const READ_ZONE_MAX = 20;
  const READ_ZONE_GAP = 2;
  // Переход: ответ встаёт на долю высоты ленты от её верха; до READ_SEEK_STEPS шагов прокрутки,
  // пока его строка не придёт в DOM; потом место сверяется, пока две сверки подряд не сойдутся
  // (высоты строк доезжают), но не больше READ_SEEK_SETTLE раз.
  const READ_SEEK_INSET = 0.12;
  const READ_SEEK_STEPS = 120;
  const READ_SEEK_STEP_MS = 50;
  const READ_SEEK_SETTLE = 12;
  const READ_SEEK_CALM = 2;
  const READ_SEEK_SETTLE_MS = 120;
  const READ_SEEK_GLIDE_MS = 420;
  const READ_HIT_MS = 1400;
  const readState = {
    chat: undefined, marks: new Set(), kept: new Map(), open: new Set(), order: [], above: false, whole: true, busy: null,
    unread: [], first: null, error: null, heads: new Map(), zones: new Map(), opens: new Map(), rows: new Set(), lines: new Set(),
    hot: null, lit: null, hit: null, hitTimer: 0, seek: null, jumped: null, clicks: 0, jumps: 0,
  };
  // Блок ответа подсвечен (#9506): курсор на его дорожке (hot) или дорожка в фокусе с клавиатуры (lit).
  const readLit = key => key != null && (key === readState.hot || key === readState.lit);
  const readOwn = node => Boolean(node?.hasAttribute?.(READ_ZONE_ATTRIBUTE) || node?.hasAttribute?.(READ_OPEN_ATTRIBUTE) || node?.id === READ_NEXT_ID
    || node?.hasAttribute?.(WORK_LINE_ATTRIBUTE));
  // Ход, которому принадлежит строка ленты (любая, и реплика человека тоже). Узел с id хода помнится
  // за строкой, сам id читается с него каждый раз: лента в покое поиском по строкам не ходит, а строка,
  // которую Claude отдал другому ходу (тот же узел, новый атрибут), прежним ходом не назовётся.
  const readEntries = new WeakMap();
  const readEntryOf = row => {
    if (!row) return null;
    const lead = row.firstElementChild ?? null;
    let known = readEntries.get(row);
    if (!known || known.lead !== lead || (known.node && !row.contains(known.node))) {
      let node = null;
      try { node = row.querySelector("[data-epitaxy-entry],[data-turn-key]"); } catch {}
      known = { node, lead };
      readEntries.set(row, known);
    }
    return known.node?.getAttribute("data-epitaxy-entry") || known.node?.getAttribute("data-turn-key") || null;
  };
  // Ключ ответа: ход строки ассистента; у реплики человека и служебной строки ключа нет.
  const readKeyOf = row => {
    const kind = String(row?.getAttribute?.("data-perf-row") ?? "");
    return kind === "assistant" || kind.startsWith("assistant_") ? readEntryOf(row) : null;
  };
  // Непрочитанные (чистая функция): ответы без пометки после первого помеченного; пишущийся не в счёт.
  // order — ходы чата по порядку [{id, assistant}], marks — помеченные id. above — выше списка есть
  // незагруженная история: пометки, которых в списке нет, лежат там, и считаются все ответы списка.
  const readUnreadOf = (order, marks, busy = null, above = false) => {
    const answers = (order ?? []).filter(entry => entry?.assistant).map(entry => entry.id);
    const first = answers.findIndex(id => marks.has(id));
    if (first < 0 && !(above && marks.size)) return [];
    return answers.slice(first + 1).filter(id => !marks.has(id) && id !== busy);
  };
  // Следующий непрочитанный ниже хода here; после последнего — первый сверху (по кругу).
  const readNextOf = (order, unread, here = null) => {
    if (!unread?.length) return null;
    const ids = (order ?? []).map(entry => entry.id);
    const from = here == null ? -1 : ids.indexOf(here);
    return unread.find(id => ids.indexOf(id) > from) ?? unread[0];
  };
  const readStoreLoad = () => {
    try {
      const data = JSON.parse(localStorage.getItem(READ_KEY) ?? "null");
      return data && typeof data === "object" && !Array.isArray(data) ? data : {};
    } catch { return {}; }
  };
  // Поставить или снять одну пометку. Чтение — заново: другое окно того же чата могло пометить своё.
  // Ответ — пометки чата после записи; null — запись не удалась (пометки остаются на сеанс).
  const readStoreApply = (chat, id, marked) => {
    try {
      const map = readStoreLoad();
      const ids = readIdsOf(map[chat]).filter(item => item !== id);
      if (marked) ids.push(id);
      map[chat] = { at: Date.now(), ids };
      const next = readStoreTrim(map, chat);
      if (Object.keys(next).length) localStorage.setItem(READ_KEY, JSON.stringify(next));
      else localStorage.removeItem(READ_KEY);
      return next[chat]?.ids ?? [];
    } catch (error) {
      readState.error = `пометки не сохранены, действуют до закрытия окна: ${String(error?.name ?? error).slice(0, 60)}`;
      return null;
    }
  };
  const readFeed = () => { try { return document.querySelector(READ_FEED_SELECTOR); } catch { return null; } };
  const readRowsNow = () => { try { return [...document.querySelectorAll(READ_ROW_SELECTOR)]; } catch { return []; } };
  // Ходы чата по порядку. Список ленты (в нём и ходы вне экрана) — пропс entries у React-узла над
  // лентой, там же isResponding и olderHistoryAbove; нет его — только строки в DOM (whole: false).
  const readOrder = (feed, rows) => {
    let host = null;
    try {
      let fiber = feed ? chatFiberOf(feed) : null;
      for (let hop = 0; fiber && hop < READ_FIBER_DEPTH && !host; hop += 1, fiber = fiber.return) {
        if (Array.isArray(fiber.memoizedProps?.entries)) host = fiber.memoizedProps;
      }
    } catch { host = null; }
    let list = [];
    if (host) {
      list = host.entries.filter(entry => typeof entry?.id === "string" && entry.id)
        .map(entry => ({ id: entry.id, assistant: entry.author === "assistant" }));
    } else {
      const seen = new Set();
      for (const row of rows) {
        const id = readEntryOf(row);
        if (!id || seen.has(id)) continue;
        seen.add(id);
        list.push({ id, assistant: readKeyOf(row) != null });
      }
    }
    const tail = list[list.length - 1];
    const working = host ? host.isResponding === true : pageWorking();
    return { list, whole: Boolean(host), above: host?.olderHistoryAbove === true, busy: working && tail?.assistant ? tail.id : null, entries: host?.entries ?? null, working };
  };
  // Ответы ленты, как они сейчас в DOM: ключ → {rows, start, cut, whole, busy}. start — первая
  // строка ответа в DOM и есть его начало (перед ней нет дыры в номерах строк); cut — сколько строк
  // идут от начала подряд; whole — известен и конец ответа.
  const readGroups = rows => {
    const groups = new Map();
    // Строки, где ответ ещё пишется: метка потока на сообщении — одним поиском на всю ленту.
    const live = new Set();
    try { for (const node of document.querySelectorAll(`${READ_ROW_SELECTOR} [data-is-streaming="true"]`)) live.add(node.closest(READ_ROW_SELECTOR)); } catch {}
    // run — ответ, чьи строки от начала пока идут подряд.
    let run = null;
    let lastIndex = null;
    let any = false;
    for (const row of rows) {
      const key = readKeyOf(row);
      const index = feedEnterIndex(row);
      const gap = any ? lastIndex != null && index != null && index !== lastIndex + 1 : index != null && index > 0;
      // Полоса кончилась: дырой — конец ответа неизвестен, строкой другого хода — известен.
      if (run && (gap || run.key !== key)) { run.cut = run.rows.length; run.whole = !gap; run = null; }
      let group = key ? groups.get(key) : null;
      if (key && !group) {
        group = { key, rows: [], start: !gap, cut: 0, whole: false, busy: key === readState.busy };
        groups.set(key, group);
        if (group.start) run = group;
      }
      if (group) {
        group.rows.push(row);
        if (row.getAttribute("data-perf-row-streaming") === "true" || live.has(row)) group.busy = true;
      }
      any = true;
      lastIndex = index;
    }
    // Ответ в самом низу ленты: за ним строк нет — конец известен.
    if (run) { run.cut = run.rows.length; run.whole = true; }
    return groups;
  };
  const readProse = row => { try { return row.querySelector('[data-cds="Prose"]'); } catch { return null; } };
  // Строка-блок свёрнутого ответа: первая строка с текстом от начала ответа; текста нет вовсе
  // (картинка, файл, одни инструменты) — первая строка. Найденная строка помнится по номеру: лента
  // уберёт из DOM строки над ней (они нулевой высоты) — блок остаётся блоком, высота не скачет.
  // Начала ответа в DOM нет и блок ещё не известен — блока пока нет.
  const readHeadOf = group => {
    const lead = group.rows.slice(0, group.cut);
    let head = lead.find(row => readProse(row)) ?? (group.whole ? lead[0] ?? null : null);
    if (head) readState.heads.set(group.key, feedEnterIndex(head));
    else if (readState.heads.get(group.key) != null) {
      const index = readState.heads.get(group.key);
      head = group.rows.find(row => feedEnterIndex(row) === index) ?? null;
    }
    return head;
  };
  const readMake = attribute => {
    const node = document.createElement("div");
    node.setAttribute(attribute, "");
    return node;
  };
  const readPlace = (store, row, attribute) => {
    let node = store.get(row);
    if (node?.parentNode === row) return node;
    node ??= readMake(attribute);
    try { row.appendChild(node); } catch { return null; }
    store.set(row, node);
    return node;
  };
  // Разметка ровно по тому, что сейчас в ленте; ушедшее снято. Раскладку не читает.
  const readPaint = (rows = readRowsNow()) => {
    // Серии «Работа идёт» (раздел 12х¹) — тем же проходом и раньше дорожек: строка ленты, занятая
    // свёрнутой серией целиком, дорожку не получает.
    try { workPaint(rows); } catch (error) { workState.error = `серии не размечены: ${String(error?.message ?? error).slice(0, 80)}`; }
    try { dotPaint(rows); } catch {}
    const groups = readGroups(rows);
    const want = new Map();
    const lines = new Set();
    const opens = new Set();
    for (const group of groups.values()) {
      const marked = readState.marks.has(group.key);
      const shut = marked && !group.busy && !readState.open.has(group.key);
      const head = shut ? readHeadOf(group) : null;
      const line = head ? readProse(head) : null;
      if (line) lines.add(line);
      const main = head ?? group.rows.find(row => !workState.rows.has(row)) ?? group.rows[0];
      // Дорожки ответа, что на виду, по порядку: по ним подложка блока знает свои края (#9506). Строка
      // свёрнутой серии (дорожки у неё нет) подложку рвёт — null; строки свёрнутого блока не в счёт.
      const shown = [];
      for (const row of group.rows) {
        want.set(row, !marked ? null : !shut ? "open" : row !== head ? "rest" : line ? "head" : "bare");
        if (workState.rows.has(row)) { shown.push(null); continue; }
        const zone = readPlace(readState.zones, row, READ_ZONE_ATTRIBUTE);
        if (!zone) continue;
        if (want.get(row) === "rest") foldSet(zone, READ_EDGE_ATTRIBUTE, null); else shown.push(zone);
        zone.__myclaudeRead = group.key;
        foldSet(zone, READ_ZONE_ATTRIBUTE, marked ? "on" : "");
        // Пометить нельзя: ответ ещё пишется или окно ещё не знает своего чата (пометку некуда записать).
        // Подсказка называет, что будет по нажатию (#9506: «нажимаю, и оно исчезает» — ответ сворачивается).
        foldSet(zone, "title", group.busy ? "Ответ ещё пишется" : !readState.chat ? "Чат ещё открывается" : marked ? "Прочитано. Нажми — снять пометку" : "Отметить прочитанным и свернуть");
        foldSet(zone, "aria-disabled", group.busy || !readState.chat ? "true" : null);
        foldSet(zone, READ_HOT_ATTRIBUTE, readLit(group.key) && !group.busy ? "" : null);
        foldSet(zone, READ_HIT_ATTRIBUTE, readState.hit === group.key ? "" : null);
        // Кнопка — одна на ответ: первая дорожка (у свёрнутого — дорожка блока).
        foldSet(zone, "role", row === main ? "button" : null);
        foldSet(zone, "tabindex", row === main ? "0" : "-1");
        foldSet(zone, "aria-label", row === main ? "Прочитано" : null);
        foldSet(zone, "aria-pressed", row === main ? String(marked) : null);
        foldSet(zone, "aria-hidden", row === main ? null : "true");
      }
      shown.forEach((zone, at) => {
        if (zone) foldSet(zone, READ_EDGE_ATTRIBUTE, [shown[at - 1] ? null : "top", shown[at + 1] ? null : "bottom"].filter(Boolean).join(" ") || null);
      });
      if (!head) continue;
      const open = readPlace(readState.opens, head, READ_OPEN_ATTRIBUTE);
      if (!open) continue;
      opens.add(open);
      open.__myclaudeRead = group.key;
      foldSet(open, "role", "button");
      foldSet(open, "tabindex", "0");
      foldSet(open, "aria-expanded", "false");
      foldSet(open, "aria-label", "Развернуть прочитанный ответ");
      foldSet(open, "title", "Развернуть ответ");
    }
    for (const [row, zone] of readState.zones) if (!want.has(row) || workState.rows.has(row)) { try { zone.remove(); } catch {} readState.zones.delete(row); }
    for (const [row, open] of readState.opens) if (!opens.has(open)) { try { open.remove(); } catch {} readState.opens.delete(row); }
    for (const row of readState.rows) if (!want.get(row)) foldSet(row, READ_ROW_ATTRIBUTE, null);
    for (const node of readState.lines) if (!lines.has(node)) foldSet(node, READ_LINE_ATTRIBUTE, null);
    readState.rows = new Set();
    for (const [row, value] of want) if (value) { foldSet(row, READ_ROW_ATTRIBUTE, value); readState.rows.add(row); }
    for (const node of lines) foldSet(node, READ_LINE_ATTRIBUTE, "");
    readState.lines = lines;
    return groups;
  };
  // Место и ширина дорожки — по полю слева от текста: целиком в поле, вплотную к тексту; поле уже
  // дорожки — она не уже READ_ZONE_MIN и встаёт от края строки. Подложка блока (под курсором на
  // дорожке) — от левого края дорожки до правого края текста с тем же полем, что слева, и не шире строки.
  const readMeasure = () => {
    let gutter = NaN;
    let right = NaN;
    let room = NaN;
    try {
      for (const message of document.querySelectorAll(`${READ_ROW_SELECTOR} [data-cds="AssistantMessage"]`)) {
        const row = message.closest(READ_ROW_SELECTOR);
        if (!readState.zones.has(row) || ["head", "bare", "rest"].includes(row.getAttribute(READ_ROW_ATTRIBUTE))) continue;
        const box = message.getBoundingClientRect();
        if (!(box.width > 0)) continue;
        const line = row.getBoundingClientRect();
        gutter = box.left - line.left;
        right = box.right - line.left;
        room = line.width;
        break;
      }
    } catch {}
    if (!Number.isFinite(gutter)) return;
    const width = Math.max(READ_ZONE_MIN, Math.min(READ_ZONE_MAX, Math.floor(gutter) - READ_ZONE_GAP));
    const left = Math.max(0, Math.floor(gutter) - READ_ZONE_GAP - width);
    const span = Math.max(width, Math.round(Math.min(room, right + Math.floor(gutter) - left)) - left);
    const style = document.documentElement.style;
    for (const [name, value] of [[READ_LEFT_VARIABLE, `${left}px`], [READ_WIDTH_VARIABLE, `${width}px`], [READ_SPAN_VARIABLE, `${span}px`]]) {
      if (style.getPropertyValue(name) !== value) style.setProperty(name, value);
    }
    foldSet(document.documentElement, READ_TIGHT_ATTRIBUTE, gutter < width + READ_ZONE_GAP ? "" : null);
  };
  const readNext = readMake(READ_LABEL_ATTRIBUTE);
  readNext.id = READ_NEXT_ID;
  readNext.setAttribute("role", "button");
  readNext.setAttribute("tabindex", "0");
  readNext.setAttribute("title", "К следующему непрочитанному ответу");
  // Счёт и кнопка: ноль непрочитанных — кнопки нет.
  const readCount = () => {
    // Ход, в котором нет ничего, кроме свёрнутой серии «Работа идёт» (раздел 12х¹), — не ответ: читать в нём нечего.
    readState.unread = readUnreadOf(readState.order.filter(entry => !workState.only.has(entry.id)), readState.marks, readState.busy, readState.above);
    readState.first = readState.order.find(entry => entry.assistant && readState.marks.has(entry.id))?.id ?? null;
    const count = readState.unread.length;
    let dock = null;
    try { dock = count ? document.querySelector('[class~="group/approval-dock"]') : null; } catch {}
    if (!dock) { if (readNext.parentNode) { try { readNext.remove(); } catch {} } return; }
    foldSet(readNext, READ_LABEL_ATTRIBUTE, `непрочитанные ${count}`);
    foldSet(readNext, "aria-label", `Непрочитанные ответы: ${count}. К следующему`);
    if (readNext.parentNode !== dock) { try { dock.appendChild(readNext); } catch {} }
  };
  const readTick = () => {
    let chat = null;
    try { chat = chatKey(); } catch { chat = null; }
    if (chat !== readState.chat) {
      readState.chat = chat;
      readState.jumped = null;
      readState.heads.clear();
      readSeekStop();
      readState.marks = new Set(chat ? readState.kept.get(chat) ?? readIdsOf(readStoreLoad()[chat]) : []);
    }
    const rows = readRowsNow();
    const order = readOrder(readFeed(), rows);
    readState.order = order.list;
    readState.whole = order.whole;
    readState.above = order.above;
    readState.busy = order.busy;
    workSync(order.entries, order.working);
    readPaint(rows);
    readMeasure();
    readCount();
  };
  // Строки ленты приходят заново при прокрутке (новым узлом или прежним, отданным другому ходу):
  // пока в чате есть пометки, разметка сверяется в том же колбэке мутаций, до отрисовки. Свои
  // вставки сюда не считаются — второго круга нет. Пометок нет, но есть серии «Работа идёт»
  // (раздел 12х¹) — сверяются только они.
  const readOnMutation = records => {
    const idle = !readState.marks.size && !workState.map.size && !workState.counted;
    const foreign = records.some(record => record.type !== "childList"
      || [...(record.addedNodes ?? []), ...(record.removedNodes ?? [])].some(node => !readOwn(node)));
    if (!foreign) return;
    // Ответ-точка (раздел 12х³) сверяется всегда: пришла — спрятана до отрисовки, без мигания.
    if (readState.marks.size) readPaint();
    else { if (!idle) workPaint(); dotPaint(); }
  };
  const readStill = () => { try { return matchMedia("(prefers-reduced-motion: reduce)").matches; } catch { return false; } };
  const readFlash = key => {
    clearTimeout(readState.hitTimer);
    readState.hit = key;
    readState.hitTimer = setTimeout(() => { readState.hitTimer = 0; readState.hit = null; if (state.alive) readPaint(); }, READ_HIT_MS);
    readPaint();
  };
  // Ход, который сейчас у линии чтения ленты (доля READ_SEEK_INSET от её верха).
  const readHere = (view, rows) => {
    const line = view.top + view.height * READ_SEEK_INSET + 4;
    let here = null;
    for (const row of rows) {
      const top = row.getBoundingClientRect().top;
      if (top > line) break;
      here = row;
    }
    return here ? readEntryOf(here) : null;
  };
  const readSeekStop = () => {
    if (readState.seek?.timer) clearTimeout(readState.seek.timer);
    readState.seek = null;
  };
  // Поставить ответ на место: верх его первой видимой строки — на top (или её низ — на bottom;
  // по умолчанию — линия чтения). Строки ответа нет в DOM — лента прокручивается к нему шагами
  // (сторона — по порядку ходов; проскочили — шаг вдвое короче). flash — подсветить, smooth — плавно; stamp — на
  // место встаёт время реплики Элвиса над ответом («N min ago», раздел 14а; #10764), нет его рядом — сам ответ.
  const readSeek = (key, { top = null, bottom = null, flash = false, smooth = false, stamp = false } = {}) => {
    readSeekStop();
    const job = { key, steps: 0, settle: 0, calm: 0, side: 0, hop: 0, stuck: 0, timer: 0 };
    readState.seek = job;
    const step = () => {
      job.timer = 0;
      if (!state.alive || readState.seek !== job) return;
      const feed = readFeed();
      if (!feed?.isConnected) { readState.seek = null; return; }
      const view = feed.getBoundingClientRect();
      const rows = readRowsNow();
      const group = readGroups(rows).get(key);
      // Свёрнутый ответ стоит своим блоком; раскрытый — первой строкой (если начало ответа в DOM).
      const row = group?.rows.find(item => ["head", "bare"].includes(item.getAttribute(READ_ROW_ATTRIBUTE)))
        ?? group?.rows.slice(0, group.cut).find(item => item.getAttribute(READ_ROW_ATTRIBUTE) !== "rest") ?? null;
      if (row) {
        const box = row.getBoundingClientRect();
        // stamp: время реплики над ответом — у самого верха ленты (stampTop), ответ под ним; нет его — как было.
        const lead = stamp ? stampLead(row, box, view.height) : 0;
        const want = lead ? (top ?? view.top + stampTop(feed, view)) + lead
          : bottom != null ? bottom - box.height : top ?? view.top + Math.round(view.height * READ_SEEK_INSET);
        const delta = Math.round(box.top - want);
        let wait = READ_SEEK_SETTLE_MS;
        job.calm = Math.abs(delta) > 1 ? 0 : job.calm + 1;
        if (Math.abs(delta) > 1) {
          if (smooth && job.settle === 0 && !readStill() && typeof feed.scrollTo === "function") {
            feed.scrollTo({ top: feed.scrollTop + delta, behavior: "smooth" });
            wait = READ_SEEK_GLIDE_MS;
          } else feed.scrollTop += delta;
        }
        if (flash && job.settle === 0) readFlash(key);
        job.settle += 1;
        if (job.settle < READ_SEEK_SETTLE && job.calm < READ_SEEK_CALM) job.timer = setTimeout(step, wait);
        else readState.seek = null;
        return;
      }
      if (job.steps >= READ_SEEK_STEPS || job.stuck > 3) { readState.seek = null; return; }
      job.steps += 1;
      const ids = readState.order.map(entry => entry.id);
      const here = ids.indexOf(readHere(view, rows));
      const there = ids.indexOf(key);
      // Строки ответа уже в DOM: начала нет — оно выше; начало есть, а блока ещё нет — ждём строк на месте.
      const side = group ? (group.start ? 0 : -1) : there < 0 || here < 0 ? job.side || 1 : there > here ? 1 : -1;
      if (side) {
        const page = Math.max(1, feed.clientHeight || view.height);
        // Шаг — меньше экрана: цель мимо не проскочит. Далёкая (по числу ходов) — до двух экранов.
        job.hop = job.side && side !== job.side ? Math.max(page / 2, job.hop / 2)
          : job.hop || page * Math.max(0.85, Math.min(2, Math.abs(there - here) / 4));
        job.side = side;
        const before = feed.scrollTop;
        feed.scrollTop = before + side * job.hop;
        job.stuck = feed.scrollTop === before ? job.stuck + 1 : 0;
      }
      job.timer = setTimeout(step, READ_SEEK_STEP_MS);
    };
    step();
  };
  // Фокус не остаётся на узле, который свернулся или ушёл: он переходит на дорожку-кнопку ответа.
  const readFocused = key => readOwn(document.activeElement) && document.activeElement.__myclaudeRead === key;
  const readFocus = key => {
    for (const zone of readState.zones.values()) {
      if (zone.__myclaudeRead !== key || zone.getAttribute("role") !== "button") continue;
      if (document.activeElement !== zone) { try { zone.focus({ preventScroll: true }); } catch {} }
      return;
    }
  };
  // Поставить или снять пометку. То, на что человек смотрит, остаётся на месте: верх ответа виден —
  // блок встаёт на его место; виден только низ — на месте остаётся то, что под ответом; не видно ни
  // верха, ни низа — блок встаёт под курсор.
  const readToggle = (key, event = null) => {
    const group = key ? readGroups(readRowsNow()).get(key) : null;
    if (!group || group.busy || !readState.chat) return false;
    const was = readState.marks.has(key);
    const shut = was && !readState.open.has(key);
    let anchor = null;
    try {
      const view = readFeed()?.getBoundingClientRect();
      const first = group.rows[0].getBoundingClientRect();
      const last = group.rows[group.rows.length - 1].getBoundingClientRect();
      // Пометка снята со свёрнутого — он раскрывается вниз от блока; с раскрытого — высота та же.
      if (!view || (was && !shut)) anchor = null;
      else if (shut) anchor = { top: (readHeadOf(group) ?? group.rows[0]).getBoundingClientRect().top };
      else if (group.start && first.top >= view.top - 1) anchor = { top: first.top };
      else if (last.bottom <= view.bottom + 1 && last.bottom > view.top) anchor = { bottom: last.bottom };
      else anchor = { top: Math.max(view.top + 8, Math.min(view.bottom - 60, (Number(event?.clientY) || view.top + view.height * READ_SEEK_INSET) - 14)) };
    } catch { anchor = null; }
    const focused = readFocused(key);
    readState.clicks += 1;
    readState.error = null;
    if (was) readState.marks.delete(key); else readState.marks.add(key);
    readState.open.delete(key);
    readState.heads.delete(key);
    const stored = readStoreApply(readState.chat, key, !was);
    if (stored) { readState.marks = new Set(stored); readState.kept.delete(readState.chat); }
    else readState.kept.set(readState.chat, readState.marks);
    readPaint();
    readCount();
    if (focused) readFocus(key);
    if (anchor) readSeek(key, anchor);
    return true;
  };
  // Раскрыть свёрнутый прочитанный: пометка остаётся, блок раскрывается вниз от своего места.
  const readExpand = key => {
    if (!key || !readState.marks.has(key) || readState.open.has(key)) return false;
    let top = null;
    for (const [row, open] of readState.opens) if (open.__myclaudeRead === key) { try { top = row.getBoundingClientRect().top; } catch {} }
    const focused = readFocused(key);
    readState.clicks += 1;
    readState.open.add(key);
    readPaint();
    if (focused) readFocus(key);
    if (top != null) readSeek(key, { top });
    return true;
  };
  // К следующему непрочитанному ниже линии чтения; после последнего — к первому.
  const readJump = () => {
    const feed = readFeed();
    if (!feed || !readState.unread.length) return false;
    const rows = readRowsNow();
    const view = feed.getBoundingClientRect();
    const ids = readState.order.map(entry => entry.id);
    let here = readHere(view, rows);
    // Прошлая цель ещё на экране (у низа ленты её не довести до линии чтения) — идём дальше неё.
    const past = readState.jumped;
    if (past && ids.indexOf(past) > ids.indexOf(here)) {
      const shown = rows.some(row => {
        if (readKeyOf(row) !== past) return false;
        const box = row.getBoundingClientRect();
        return box.height > 0 && box.bottom > view.top && box.top < view.bottom;
      });
      if (shown) here = past;
    }
    const key = readNextOf(readState.order, readState.unread, here);
    if (!key) return false;
    readState.jumps += 1;
    readState.jumped = key;
    readSeek(key, { flash: true, smooth: true, stamp: true });
    return true;
  };
  const readAct = (target, event) => {
    const zone = target?.closest?.(`[${READ_ZONE_ATTRIBUTE}]`) ?? null;
    if (zone) { readToggle(zone.__myclaudeRead, event); return true; }
    const work = target?.closest?.(`[${WORK_LINE_ATTRIBUTE}]`) ?? null;
    if (work) { workToggle(work.__myclaudeWork); return true; }
    const open = target?.closest?.(`[${READ_OPEN_ATTRIBUTE}]`) ?? null;
    if (open) { readExpand(open.__myclaudeRead); return true; }
    if (target?.closest?.(`#${READ_NEXT_ID}`)) { readJump(); return true; }
    return false;
  };
  const onReadClick = event => {
    if (!state.alive || !readOwn(event?.target?.closest?.(`[${READ_ZONE_ATTRIBUTE}],[${READ_OPEN_ATTRIBUTE}],#${READ_NEXT_ID},[${WORK_LINE_ATTRIBUTE}]`))) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    if (Number(event.detail) > 1) return;
    try { readAct(event.target, event); } catch {}
  };
  const onReadKey = event => {
    if (!state.alive) return;
    const key = event?.key;
    // Клавиша мимо своих узлов — человек листает сам: переход снимается.
    if (!readOwn(event.target) || (key !== "Enter" && key !== " " && key !== "Spacebar")) { readSeekStop(); return; }
    event.preventDefault?.();
    event.stopPropagation?.();
    // Удержание клавиши пометкой не мигает.
    if (event.repeat) return;
    try { readAct(event.target, null); } catch {}
  };
  // Наведение и фокус с клавиатуры: подложка — у всего блока ответа (все его строки ленты), а не
  // у одной строки. Фокус мышью (нажатие на дорожку) блок не зажигает — его ведёт курсор.
  const onReadHover = event => {
    if (!state.alive) return;
    const focus = event?.type === "focusin" || event?.type === "focusout";
    const under = event?.type === "pointerover" || event?.type === "focusin" ? event.target : event?.relatedTarget;
    let zone = under?.closest?.(`[${READ_ZONE_ATTRIBUTE}]`) ?? null;
    if (focus && zone) { try { if (!zone.matches(":focus-visible")) zone = null; } catch { zone = null; } }
    const key = zone?.__myclaudeRead ?? null;
    const slot = focus ? "lit" : "hot";
    if (key === readState[slot]) return;
    readState[slot] = key;
    for (const node of readState.zones.values()) {
      foldSet(node, READ_HOT_ATTRIBUTE, readLit(node.__myclaudeRead) && node.getAttribute("aria-disabled") !== "true" ? "" : null);
    }
  };
  // Нажатие мышью — человек взялся за ленту сам: идущий переход снимается (новый начнёт click).
  // Двойное нажатие по своему узлу не выделяет слово рядом.
  const onReadPress = event => {
    readSeekStop();
    if (Number(event?.detail) > 1 && readOwn(event.target)) event.preventDefault?.();
  };
  // Сироты прошлой установки — до первой разметки.
  const readSweep = () => {
    try {
      for (const node of document.querySelectorAll(`[${READ_ZONE_ATTRIBUTE}],[${READ_OPEN_ATTRIBUTE}],#${READ_NEXT_ID}`)) node.remove();
      for (const attr of [READ_ROW_ATTRIBUTE, READ_LINE_ATTRIBUTE]) {
        for (const node of document.querySelectorAll(`[${attr}]`)) node.removeAttribute(attr);
      }
    } catch {}
  };
  readSweep();
  track(() => {
    readSeekStop();
    clearTimeout(readState.hitTimer);
    readState.zones.clear();
    readState.opens.clear();
    readState.rows.clear();
    readState.lines.clear();
    try { readNext.remove(); } catch {}
    readSweep();
    try {
      document.documentElement.style.removeProperty(READ_LEFT_VARIABLE);
      document.documentElement.style.removeProperty(READ_WIDTH_VARIABLE);
      document.documentElement.style.removeProperty(READ_SPAN_VARIABLE);
      document.documentElement.removeAttribute(READ_TIGHT_ATTRIBUTE);
    } catch {}
  });
  // «Прочитано» (#9377, раздел 12х): пометок в этом чате, непрочитанных на кнопке, первый
  // помеченный ответ; lastError — запись не удалась или лента не отдала список ответов.
  statusPart("read", () => ({
    marked: readState.marks.size, unread: readState.unread.length,
    ...(readState.first ? { firstMarked: readState.first } : {}),
    lastError: readState.error ?? (readState.whole ? null : "лента не отдала список ответов: счёт только по строкам на экране"),
  }));
  HATCH && Object.assign(HATCH, { readKeyOf, readUnreadOf, readNextOf, readTick, readPaint, readToggle, readState,
    READ_KEY, READ_IDS_MAX, READ_CHATS_MAX, READ_TOTAL_MAX });

