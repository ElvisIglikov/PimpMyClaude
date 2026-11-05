  // ---- 12е². Повтор при ошибке сервера (#6936) ------------------------------
  // Слово Элвиса: «по-хорошему Пимп должен каждые минут десять, например, пытаться нажать try again до тех пор,
  // пока сервер не восстановится… try again должен нажимать не постоянно, а максимум час… продумать, как хорошо
  // сделать, чтобы не навредить кэшу». Ход Claude упал с ошибкой сети или сервера — страница сама жмёт родную
  // кнопку повтора Claude раз в N минут (2 / 5 / 10, по умолчанию 5), первый раз — через N минут после того, как
  // увидела ошибку, и не дольше часа от неё. Выключатель — у приложения (команда auto-retry, К-AR,
  // docs/contracts/485-6936-avtopovtor.md); нет ключа — выключено (решение WF108).
  //
  // ЗАМЕРА РАЗМЕТКИ НЕТ (19.10.2026): живой probe агенту был запрещён, в репозитории снятой ошибки нет. Опознаватель
  // осторожный, все приметы — константами ниже; не опознал — не жмёт и строку не ставит. Замер (оркестратору):
  // probe.js с выражением из docs/contracts/485-6936-avtopovtor.md, дважды — пока Claude Code повторяет сам
  // («Retrying… attempt n/10», кнопка стоп) и после. Другая разметка — правятся только константы.
  //
  // Жмёт только при всех условиях сразу: кнопка «Try again»/«Retry» внутри ленты, в последней отрисованной строке
  // ленты, после неё нет хода человека, лента у низа; ход не идёт (нет кнопки стоп); поле ввода пустое, 30 с без
  // ввода (общий штамп раздела 12к); меню и диалоги Claude закрыты; обход Авто-Allow стоит. Повторяет только
  // сеть, 5xx и overloaded; лимит подписки, длинный запрос, вход, плохой запрос и отказ модели — нет.
  //
  // Час — одна запись на чат в общем для окон localStorage. Она переживает перезагрузку и новые строки ошибки
  // после наших же нажатий (Claude Code сам повторяет минутами и падает снова — это тот же ход). Сбрасывают её
  // только явные признаки: ход человека новее ошибки, человек сам нажал повтор, последняя строка ленты — ответ без
  // ошибки 5 с подряд. Сверху — жёсткий потолок: за любые 60 минут не больше 60/N нажатий в чате, сброс его не
  // снимает. Своих таймеров нет: тик — сердце раздела 16.
  const AUTO_RETRY_ON_KEY = "myclaude.autoRetry";
  const AUTO_RETRY_EVERY_KEY = "myclaude.autoRetryEvery";
  const AUTO_RETRY_STORE_KEY = "myclaude-auto-retry-v1";
  const AUTO_RETRY_CHOICES = [2, 5, 10];
  const AUTO_RETRY_DEFAULT_EVERY = 5;
  const AUTO_RETRY_HOUR_MS = 60 * 60 * 1000;
  // Последняя попытка часа, которую тик застал чуть позже срока, ещё в счёт часа; позже конца часа — стоп.
  const AUTO_RETRY_LATE_MS = 30 * 1000;
  // «Ответ без ошибки» держится столько, прежде чем запись сбросится: кнопка повтора рисуется не сразу.
  const AUTO_RETRY_SETTLE_MS = 5000;
  // После нажатия: за столько должна встать кнопка стоп или уйти кнопка повтора, иначе «press-failed».
  const AUTO_RETRY_CHECK_MS = 5000;
  const AUTO_RETRY_TICK_MS = 1000;
  // Записи чатов: не больше стольких; запись, которую 7 дней не видели, убирается. Час старой ошибки так
  // переживает и ночь сна Мака: запись не исчезает, пока её ошибка может быть на экране.
  const AUTO_RETRY_CHATS_MAX = 30;
  const AUTO_RETRY_KEEP_MS = 7 * 24 * 60 * 60 * 1000;
  const AUTO_RETRY_CHAT_RE = /^local_[A-Za-z0-9_-]+$/;
  // Приметы разметки (без замера — см. шапку).
  // #11618: русский Claude — «Повторить», «Повторить попытку», «Попробуй еще раз» (каталог claude.ai).
  const AUTO_RETRY_BUTTON_RE = /^(?:try again|retry|повторить|повторить попытку|попробуй е[её]ще раз)$/i;
  const AUTO_RETRY_BUTTONS = 'button,[role="button"]';
  const AUTO_RETRY_ROW = '[data-testid="transcript-row"]';
  const AUTO_RETRY_FEED = '[data-testid="epitaxy-virtual-transcript"]';
  const AUTO_RETRY_HUMAN = '[data-testid="transcript-row"][data-perf-row="human"],[data-testid="user-message"],.epitaxy-user-turn,[data-user-message-bubble]';
  // Второй пояс: кнопка внутри ленты, но в чужом узле — не наша.
  const AUTO_RETRY_SKIP = '.epitaxy-approval-card,[data-testid="sidebar"],[role="dialog"],[role="alertdialog"],[role="menu"],[role="listbox"],[id^="myclaude-"],[data-myclaude-auto-retry],.ProseMirror,textarea';
  const AUTO_RETRY_OVERLAY = `${CLAUDE_POPUP_SELECTOR},[cmdk-root]`;
  // Блок ошибки — самый малый предок кнопки (до стольких уровней, не шире строки ленты) с текстом от
  // AUTO_RETRY_TEXT_MIN знаков без подписей кнопок; длиннее AUTO_RETRY_TEXT_MAX — это уже не блок ошибки.
  const AUTO_RETRY_DEPTH = 4;
  const AUTO_RETRY_TEXT_MIN = 8;
  const AUTO_RETRY_TEXT_MAX = 2000;
  // Как жать: "click" — button.click(); "mouse" — pressLikeMouse (025), если замер покажет, что click не берёт.
  const AUTO_RETRY_PRESS = "click";
  // Виды ошибок одним списком: сначала те, что НЕ повторяем, потом те, что повторяем; ни одна примета не
  // совпала — unknown, не жмём. Числа — только целым словом: «4000 tokens» не 400.
  const AUTO_RETRY_KINDS = [
    ["user-stop", false, /interrupted by user|request (?:was )?(?:aborted|cancell?ed) by (?:the )?user/i],
    ["limit", false, /usage limit|rate[\s_-]?limit|limit reached|limit will reset|out of (?:extra )?usage|\b429\b|лимит использования|достигнут лимит|лимит(?:ы)? запросов|использование исчерпано|закончились кредиты/i],
    ["too-long", false, /prompt is too long|context (?:window|length)|too many tokens|maximum context|слишком длинн|контекстное окно/i],
    ["auth", false, /\b401\b|\b403\b|\/login\b|invalid (?:x-)?api[\s_-]?key|authenticat|credit balance|unauthori[sz]ed|permission_error|oauth token|войдите снова|повторного входа/i],
    ["bad-request", false, /\b400\b|invalid_request|invalid request/i],
    ["refusal", false, /usage polic|\brefusal\b|\brefused to\b|declined to|content (?:filter|policy)/i],
    ["overloaded", true, /overloaded|\b529\b|capacity|service is busy|server is busy|перегруж/i],
    ["server", true, /\b50[0-4]\b|internal server error|bad gateway|service unavailable|gateway time-?out|server error|\bapi_error\b/i],
    ["network", true, /connection problem|connection went idle|response stopped before finishing|can['’]?t reach|cannot reach|unable to (?:reach|connect)|connection (?:error|refused|reset|closed|lost)|network (?:error|connection)|\bECONN(?:RESET|REFUSED)\b|\bETIMEDOUT\b|\bENOTFOUND\b|\bEAI_AGAIN\b|fetch failed|failed to fetch|timed out|\btimeout\b|offline|socket hang up|no internet|проблема с подключением|соединение неактивно|ответ прервался|не удается подключиться|ошибка сети|время ожидания подключения|нет подключения к интернету|не в сети/i],
  ];
  const AUTO_RETRY_ATTRIBUTE = "data-myclaude-auto-retry";
  const AUTO_RETRY_TEXT_ATTRIBUTE = "data-myclaude-auto-retry-text";
  const AUTO_RETRY_CANCEL_ATTRIBUTE = "data-myclaude-auto-retry-cancel";
  // Подписи строки «мешает человек» — по причине.
  const AUTO_RETRY_WAIT_TEXT = {
    field: ", когда поле освободится", typing: ", когда поле освободится", "no-field": ", когда поле освободится",
    menu: ", когда закроется меню", roam: " после обхода Allow",
  };

  // state — off | no-chat | idle | not-bottom | not-last | working | skip | count | wait | stopped | pressed | storage.
  const autoRetryState = {
    tickAt: -Infinity, chat: null, state: "off", reason: "", kind: null, tries: 0, max: 0, next: null, last: null,
    stoppedBy: null, presses: 0, manual: 0, resets: 0, outcome: null, check: null, calmAt: 0, line: null,
  };

  const autoRetryOn = () => { try { return localStorage.getItem(AUTO_RETRY_ON_KEY) === "true"; } catch { return false; } };
  const autoRetryMinutes = raw => {
    const value = Number(String(raw ?? "").trim());
    return AUTO_RETRY_CHOICES.includes(value) ? value : AUTO_RETRY_DEFAULT_EVERY;
  };
  const autoRetryEvery = () => {
    try { return autoRetryMinutes(localStorage.getItem(AUTO_RETRY_EVERY_KEY)); } catch { return AUTO_RETRY_DEFAULT_EVERY; }
  };
  const autoRetryIso = value => (Number.isFinite(value) ? new Date(value).toISOString() : null);

  // Вид ошибки по тексту её блока.
  const autoRetryKind = text => {
    const value = String(text ?? "");
    if (!value || value.length > AUTO_RETRY_TEXT_MAX) return "unknown";
    for (const [kind, , pattern] of AUTO_RETRY_KINDS) if (pattern.test(value)) return kind;
    return "unknown";
  };
  const autoRetryAgain = kind => AUTO_RETRY_KINDS.some(([name, again]) => name === kind && again);

  // ---- запись чатов (общая для окон) ----
  // {"<чат>":{first,tries,last,stopped,print,row,human,seen,presses:[ms]}}; first=null — эпизода нет, остались
  // только нажатия последнего часа (потолок).
  const autoRetryNum = value => (typeof value === "number" && Number.isFinite(value) ? value : null);
  const autoRetryBlank = (seen, presses = []) => ({
    first: null, tries: 0, last: null, stopped: null, print: "", row: null, human: "", seen, presses,
  });
  const autoRetryRead = () => {
    let data = null;
    try { data = JSON.parse(localStorage.getItem(AUTO_RETRY_STORE_KEY) ?? "null"); } catch { data = null; }
    const out = {};
    if (!data || typeof data !== "object" || Array.isArray(data)) return out;
    for (const [chat, raw] of Object.entries(data)) {
      if (!AUTO_RETRY_CHAT_RE.test(chat) || !raw || typeof raw !== "object") continue;
      const record = autoRetryBlank(autoRetryNum(raw.seen) ?? 0,
        (Array.isArray(raw.presses) ? raw.presses : []).map(autoRetryNum).filter(at => at != null).slice(-120));
      record.first = autoRetryNum(raw.first);
      record.tries = Math.max(0, Math.floor(autoRetryNum(raw.tries) ?? 0));
      record.last = autoRetryNum(raw.last);
      record.stopped = raw.stopped === "hour" || raw.stopped === "cancel" ? raw.stopped : null;
      record.print = typeof raw.print === "string" ? raw.print.slice(0, 200) : "";
      record.row = autoRetryNum(raw.row);
      record.human = typeof raw.human === "string" ? raw.human.slice(0, 80) : "";
      out[chat] = record;
    }
    return out;
  };
  // Потолок: свой чат остаётся всегда; прочие — свежие первыми, не больше AUTO_RETRY_CHATS_MAX и не старше 7 дней.
  // Ошибка записи — false: без записи жать нельзя (попытки не сосчитаны).
  const autoRetryWrite = (map, keep, t) => {
    const out = {};
    if (map[keep]) out[keep] = map[keep];
    const rest = Object.entries(map).filter(([chat, record]) => chat !== keep && t - record.seen < AUTO_RETRY_KEEP_MS)
      .sort((a, b) => b[1].seen - a[1].seen).slice(0, AUTO_RETRY_CHATS_MAX - Object.keys(out).length);
    for (const [chat, record] of rest) out[chat] = record;
    for (const record of Object.values(out)) record.presses = record.presses.filter(at => t - at < AUTO_RETRY_HOUR_MS);
    try { localStorage.setItem(AUTO_RETRY_STORE_KEY, JSON.stringify(out)); return true; } catch { return false; }
  };
  // Сброс эпизода по явному признаку: нажатия последнего часа остаются — потолок их помнит.
  const autoRetryReset = (map, chat, t) => {
    map[chat] = autoRetryBlank(t, map[chat]?.presses ?? []);
    autoRetryState.resets += 1;
    autoRetryState.calmAt = 0;
    return map[chat];
  };

  // ---- лента ----
  // Всё ли после узла (в порядке документа, без его потомков) свободно от selector.
  const autoRetryLaterHas = (node, selector) => {
    for (let el = node; el && el !== document.documentElement; el = el.parentElement) {
      for (let next = el.nextElementSibling; next; next = next.nextElementSibling) {
        if (next.matches?.(selector) || next.querySelector?.(selector)) return true;
      }
    }
    return false;
  };
  const autoRetryRowIndex = node => feedEnterIndex(node?.closest?.(AUTO_RETRY_ROW) ?? node);
  const autoRetryTopRow = () => {
    let top = null;
    let index = null;
    for (const row of document.querySelectorAll(AUTO_RETRY_ROW)) {
      const value = feedEnterIndex(row);
      if (value != null && (index == null || value > index)) { index = value; top = row; }
    }
    return { row: top, index };
  };
  // Последний ход человека: номер строки, а без номера — хэш текста (пусто — не отрисован).
  const autoRetryHuman = () => {
    let last = null;
    let index = null;
    for (const node of document.querySelectorAll(AUTO_RETRY_HUMAN)) {
      const value = autoRetryRowIndex(node);
      if (value != null) { if (index == null || value > index) { index = value; last = node; } } else if (index == null) last = node;
    }
    if (index != null) return String(index);
    const text = String(last?.textContent ?? "").replace(/\s+/g, " ").trim();
    return text ? `#${autoHash(text.slice(0, 500))}` : "";
  };
  // Человек отправил новое сообщение: ход человека ниже строки ошибки; без номеров — другой текст, чем был.
  const autoRetryHumanNewer = (now, record) => {
    if (!now) return false;
    const numeric = /^\d+$/.test(now);
    if (numeric && record.row != null) return Number(now) > record.row;
    if (!record.human || now === record.human) return false;
    return numeric && /^\d+$/.test(record.human) ? Number(now) > Number(record.human) : true;
  };
  // Текст узла без кнопок, клавиш, значков и своей строки.
  const autoRetryText = node => {
    let clone = null;
    try { clone = node.cloneNode(true); } catch { return ""; }
    for (const kid of [...clone.querySelectorAll(`${AUTO_RETRY_BUTTONS},kbd,svg,[${AUTO_RETRY_ATTRIBUTE}]`)]) kid.remove();
    return String(clone.textContent ?? "").replace(/\s+/g, " ").trim();
  };
  const autoRetryBlock = (button, row) => {
    let node = button.parentElement;
    for (let depth = 0; node && depth < AUTO_RETRY_DEPTH; depth += 1) {
      // Сама лента — не блок ошибки: её текст — весь разговор, а строка встала бы за лентой.
      if (node.matches?.(AUTO_RETRY_FEED) || node.querySelector?.(".ProseMirror, textarea")) return null;
      const text = autoRetryText(node);
      if (text.length >= AUTO_RETRY_TEXT_MIN) return { node, text };
      if (node === row) return null;
      node = node.parentElement;
    }
    return null;
  };
  const autoRetryLabelOk = button => {
    const text = autoAllowLabel(button.textContent);
    const aria = button.getAttribute?.("aria-label");
    if (!AUTO_RETRY_BUTTON_RE.test(text || autoAllowLabel(aria))) return false;
    return !aria || AUTO_RETRY_BUTTON_RE.test(autoAllowLabel(aria));
  };
  // Кнопка повтора в ленте: зона — строка ленты или сама лента, второй пояс — AUTO_RETRY_SKIP.
  const autoRetryCandidate = button => {
    if (!button?.isConnected || !autoRetryLabelOk(button)) return null;
    const row = button.closest(AUTO_RETRY_ROW);
    if (!(row ?? button.closest(AUTO_RETRY_FEED)) || button.closest(AUTO_RETRY_SKIP)) return null;
    return { button, row };
  };
  // Последняя видимая кнопка повтора в ленте и её место: why — "" (жать можно), not-bottom, not-last.
  // Для why="" — блок ошибки, текст, вид и отпечаток.
  const autoRetryFind = () => {
    let hit = null;
    for (const button of document.querySelectorAll(AUTO_RETRY_BUTTONS)) {
      const found = autoRetryCandidate(button);
      if (!found || button.disabled || button.getAttribute("aria-disabled") === "true" || !autoAllowVisible(button)) continue;
      hit = found;
    }
    if (!hit) return null;
    let bottom = null;
    try { bottom = progressAtBottom(); } catch {}
    hit.index = feedEnterIndex(hit.row);
    const top = autoRetryTopRow();
    hit.why = bottom === false ? "not-bottom"
      : autoRetryLaterHas(hit.button, AUTO_RETRY_HUMAN) ? "not-last"
      : hit.index != null && top.index != null ? (hit.index < top.index ? "not-last" : "")
      : autoRetryLaterHas(hit.row ?? hit.button, AUTO_RETRY_ROW) ? "not-last" : "";
    if (hit.why) return hit;
    const block = autoRetryBlock(hit.button, hit.row);
    hit.block = block?.node ?? null;
    hit.text = block?.text ?? "";
    hit.kind = autoRetryKind(hit.text);
    hit.print = `${hit.index ?? "-"}:${autoHash(hit.text)}`;
    return hit;
  };
  // Ответ дошёл: хода нет, лента у низа, кнопки повтора внизу нет, последняя строка — ответ новее ошибки.
  const autoRetryCalm = (record, hit, working, t) => {
    const s = autoRetryState;
    if (record?.first == null || record.row == null || working || (hit && hit.why !== "not-last")) { s.calmAt = 0; return false; }
    let bottom = null;
    try { bottom = progressAtBottom(); } catch {}
    const top = autoRetryTopRow();
    const kind = String(top.row?.getAttribute?.("data-perf-row") ?? "");
    if (bottom === false || top.index == null || top.index <= record.row || !kind.startsWith("assistant")) { s.calmAt = 0; return false; }
    if (!s.calmAt) { s.calmAt = t; return false; }
    return t - s.calmAt >= AUTO_RETRY_SETTLE_MS;
  };

  // ---- ритм ----
  // Следующая попытка: не раньше first + (tries+1)·N и last + N; потолок — 60/N нажатий за любые 60 минут.
  // total — сколько попыток всего успеет случиться до конца часа (подпись «попытка k из total», k ≤ total).
  const autoRetryPlan = (record, every, t) => {
    const step = every * 60 * 1000;
    const max = Math.floor(60 / every);
    const recent = record.presses.filter(at => t - at < AUTO_RETRY_HOUR_MS).sort((a, b) => a - b);
    let due = Math.max(record.first + (record.tries + 1) * step, record.last == null ? -Infinity : record.last + step);
    if (recent.length >= max) due = Math.max(due, recent[recent.length - max] + AUTO_RETRY_HOUR_MS);
    const end = record.first + AUTO_RETRY_HOUR_MS;
    const over = due > end || t - end > AUTO_RETRY_LATE_MS;
    const total = Math.max(record.tries, Math.min(max, record.tries + Math.floor((end - due) / step) + 1));
    return { due, over, total };
  };
  // Что мешает нажать сейчас ("" — ничего).
  const autoRetryBusy = () => {
    if (!state.editor?.isConnected) return "no-field";
    let editor = "";
    try { editor = editorText(state.editor); } catch { editor = ""; }
    if (editor) return "field";
    if (!autoQuiet()) return "typing";
    let menu = false;
    try { menu = overlayOpen(AUTO_RETRY_OVERLAY); } catch { menu = true; }
    if (menu) return "menu";
    if (roamState.phase !== "idle") return "roam";
    return "";
  };

  // ---- строка под ошибкой ----
  // Текст — атрибутом и ::before: смена текста не будит наблюдателей ленты (attributeFilter у них свой) и не
  // попадает в textContent строки ответа, который читают другие разделы.
  const autoRetryUnpaint = () => { try { autoRetryState.line?.remove(); } catch {} };
  const autoRetryPaint = (hit, text, cancel) => {
    const anchor = hit.block;
    if (!anchor?.isConnected) { autoRetryUnpaint(); return; }
    let line = autoRetryState.line;
    if (!line) {
      line = document.createElement("div");
      line.setAttribute(AUTO_RETRY_ATTRIBUTE, "");
      autoRetryState.line = line;
    }
    foldSet(line, AUTO_RETRY_TEXT_ATTRIBUTE, text);
    let button = line.querySelector(`[${AUTO_RETRY_CANCEL_ATTRIBUTE}]`);
    if (cancel && !button) {
      button = document.createElement("button");
      button.setAttribute("type", "button");
      button.setAttribute(AUTO_RETRY_CANCEL_ATTRIBUTE, "");
      button.setAttribute("aria-label", "Отменить автоповтор");
      line.appendChild(button);
    }
    if (!cancel && button) button.remove();
    try {
      if (anchor === hit.row) { if (anchor.lastElementChild !== line) anchor.appendChild(line); }
      else if (anchor.nextElementSibling !== line) anchor.parentNode.insertBefore(line, anchor.nextSibling);
    } catch {}
  };
  const autoRetryLeft = ms => (ms < 60 * 1000 ? "меньше чем через минуту" : `через ${Math.max(1, Math.round(ms / 60000))} мин`);

  const autoRetryShow = (name, fields = {}) => {
    Object.assign(autoRetryState, { state: name, reason: "", kind: null, tries: 0, max: 0, next: null, last: null, stoppedBy: null }, fields);
  };
  const autoRetryIdle = name => { autoRetryUnpaint(); autoRetryShow(name); };

  // Исход прошлого нажатия: пошёл ход или ушла кнопка — started; за AUTO_RETRY_CHECK_MS ни того ни другого — press-failed.
  const autoRetryOutcome = (working, t) => {
    const check = autoRetryState.check;
    if (!check) return;
    if (check.chat !== autoRetryState.chat) { autoRetryState.check = null; return; }
    let gone = true;
    try { gone = !check.button.isConnected || !autoAllowVisible(check.button); } catch {}
    if (working || gone) { autoRetryState.outcome = "started"; autoRetryState.check = null; return; }
    if (t - check.at >= AUTO_RETRY_CHECK_MS) { autoRetryState.outcome = "press-failed"; autoRetryState.check = null; }
  };

  // Нажатие: запись перечитывается и пишется тем же шагом, что клик, — второе окно того же чата могло успеть.
  const autoRetryPress = (chat, hit, every, t) => {
    const map = autoRetryRead();
    const record = map[chat];
    if (!record || record.first == null || record.stopped) return "";
    const plan = autoRetryPlan(record, every, t);
    if (plan.over || t < plan.due) return "";
    const button = hit.button;
    let now = null;
    try { now = myChatId(); } catch { now = null; }
    if (!button.isConnected || button.disabled || button.getAttribute("aria-disabled") === "true"
      || !autoAllowVisible(button) || !autoRetryLabelOk(button) || now !== chat) return "";
    record.tries += 1;
    record.last = t;
    record.seen = t;
    record.presses.push(t);
    if (!autoRetryWrite(map, chat, t)) return "storage";
    autoRetryState.presses += 1;
    autoRetryState.outcome = null;
    autoRetryState.check = { chat, button, at: t };
    autoRetryUnpaint();
    autoRetryShow("pressed", { kind: hit.kind, tries: record.tries, max: plan.total, last: t });
    if (AUTO_RETRY_PRESS === "mouse") pressLikeMouse(button); else button.click();
    return "pressed";
  };

  // Ошибка опознана и её можно повторять: эпизод, ритм, строка, нажатие.
  const autoRetryHandle = (chat, map, record, hit, every, t) => {
    let dirty = false;
    if (!record || record.first == null) {
      record = map[chat] = Object.assign(autoRetryBlank(t, record?.presses ?? []),
        { first: t, print: hit.print, row: hit.index, human: autoRetryHuman() });
      dirty = true;
    } else if (record.print !== hit.print) {
      // Новая строка ошибки того же хода (повтор упал снова): час идёт дальше.
      Object.assign(record, { print: hit.print, row: hit.index ?? record.row, seen: t });
      dirty = true;
    } else if (t - record.seen >= 60 * 1000) { record.seen = t; dirty = true; }
    const plan = autoRetryPlan(record, every, t);
    if (!record.stopped && plan.over) { record.stopped = "hour"; dirty = true; }
    if (dirty && !autoRetryWrite(map, chat, t)) { autoRetryIdle("storage"); return; }
    const view = { kind: hit.kind, tries: record.tries, max: plan.total, last: record.last, stoppedBy: record.stopped };
    if (record.stopped) {
      if (record.stopped === "hour") autoRetryPaint(hit, "PMP перестал повторять: прошёл час", false);
      else autoRetryUnpaint();
      autoRetryShow("stopped", view);
      return;
    }
    const attempt = `попытка ${record.tries + 1} из ${Math.max(plan.total, record.tries + 1)}`;
    if (t < plan.due) {
      autoRetryPaint(hit, `PMP повторит ${autoRetryLeft(plan.due - t)} · ${attempt} · `, true);
      autoRetryShow("count", { ...view, next: plan.due });
      return;
    }
    const busy = autoRetryBusy();
    if (busy) {
      autoRetryPaint(hit, `PMP повторит${AUTO_RETRY_WAIT_TEXT[busy] ?? AUTO_RETRY_WAIT_TEXT.field} · ${attempt} · `, true);
      autoRetryShow("wait", { ...view, next: plan.due, reason: busy });
      return;
    }
    const pressed = autoRetryPress(chat, hit, every, t);
    if (pressed === "storage") { autoRetryIdle("storage"); return; }
    if (pressed) return;
    // Второе окно того же чата нажало раньше: запись свежая — строка по ней.
    autoRetryShow("count", { ...view, next: plan.due });
  };

  const autoRetryTick = (t = Date.now()) => {
    const s = autoRetryState;
    if (t - s.tickAt < AUTO_RETRY_TICK_MS && t >= s.tickAt) return;
    s.tickAt = t;
    if (!state.alive) return;
    if (!themable || !autoRetryOn()) { autoRetryIdle("off"); return; }
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    if (!AUTO_RETRY_CHAT_RE.test(chat || "")) { autoRetryIdle("no-chat"); return; }
    if (chat !== s.chat) { s.chat = chat; s.check = null; s.calmAt = 0; autoRetryUnpaint(); }
    const every = autoRetryEvery();
    const working = pageWorking();
    autoRetryOutcome(working, t);
    const hit = autoRetryFind();
    const map = autoRetryRead();
    let record = map[chat] ?? null;
    // Сброс по явным признакам: ход человека новее ошибки; ответ дошёл без ошибки.
    if (record?.first != null) {
      const human = autoRetryHuman();
      let changed = true;
      if (autoRetryHumanNewer(human, record)) record = autoRetryReset(map, chat, t);
      else if (autoRetryCalm(record, hit, working, t)) record = autoRetryReset(map, chat, t);
      else if (!record.human && human) record.human = human;
      else changed = false;
      if (changed) autoRetryWrite(map, chat, t);
    } else s.calmAt = 0;
    if (working) { autoRetryIdle("working"); return; }
    if (!hit) { autoRetryIdle("idle"); return; }
    if (hit.why) { autoRetryIdle(hit.why); return; }
    if (!autoRetryAgain(hit.kind)) { autoRetryUnpaint(); autoRetryShow("skip", { kind: hit.kind }); return; }
    autoRetryHandle(chat, map, record, hit, every, t);
  };

  // Команда auto-retry {on:"true"|"false", every:"2"|"5"|"10"} — всем окнам, копия в localStorage.
  const autoRetrySet = detail => {
    const on = String(detail?.on) === "true";
    try {
      localStorage.setItem(AUTO_RETRY_ON_KEY, on ? "true" : "false");
      localStorage.setItem(AUTO_RETRY_EVERY_KEY, String(autoRetryMinutes(detail?.every)));
    } catch {}
    if (!on) autoRetryIdle("off");
  };

  // «Отменить»: настоящая кнопка — Enter и пробел дают click; клавиши ловим и сами (Claude глушит часть клавиш).
  const autoRetryCancel = () => {
    const chat = autoRetryState.chat;
    const map = autoRetryRead();
    const record = map[chat];
    if (record && record.first != null && !record.stopped) {
      record.stopped = "cancel";
      autoRetryWrite(map, chat, Date.now());
    }
    autoRetryUnpaint();
    autoRetryShow("stopped", { stoppedBy: "cancel", tries: record?.tries ?? 0, last: record?.last ?? null });
  };
  const onAutoRetryClick = event => {
    if (!state.alive) return;
    const target = event?.target;
    if (target?.closest?.(`[${AUTO_RETRY_CANCEL_ATTRIBUTE}]`)) {
      event.preventDefault?.();
      event.stopPropagation?.();
      autoRetryCancel();
      return;
    }
    // Человек сам нажал повтор — новый эпизод: прежний час не держит его ошибку. Наш click() — не доверенный.
    if (event?.isTrusted !== true || !autoRetryOn()) return;
    const found = autoRetryCandidate(target?.closest?.(AUTO_RETRY_BUTTONS));
    if (!found) return;
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    if (!AUTO_RETRY_CHAT_RE.test(chat || "")) return;
    const map = autoRetryRead();
    if (map[chat]?.first == null) return;
    autoRetryReset(map, chat, Date.now());
    autoRetryWrite(map, chat, Date.now());
    autoRetryState.manual += 1;
    autoRetryUnpaint();
  };
  const onAutoRetryKey = event => {
    if (!state.alive) return;
    const key = event?.key;
    if (key !== "Enter" && key !== " " && key !== "Spacebar") return;
    if (!event.target?.closest?.(`[${AUTO_RETRY_CANCEL_ATTRIBUTE}]`)) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    autoRetryCancel();
  };

  // Тихая строка: 12 px, без цвета; «Отменить» — подчёркнутая кнопка с видимым фокусом.
  lateRules.push(
    `[${AUTO_RETRY_ATTRIBUTE}]{display:block;margin:4px 0 2px;font-size:12px;line-height:1.4;opacity:.7;-webkit-app-region:no-drag}`,
    `[${AUTO_RETRY_ATTRIBUTE}]::before{content:attr(${AUTO_RETRY_TEXT_ATTRIBUTE})}`,
    `[${AUTO_RETRY_CANCEL_ATTRIBUTE}]{all:unset;cursor:pointer;text-decoration:underline;text-underline-offset:2px;border-radius:4px;-webkit-app-region:no-drag}`,
    `[${AUTO_RETRY_CANCEL_ATTRIBUTE}]::before{content:"Отменить"}`,
    `[${AUTO_RETRY_CANCEL_ATTRIBUTE}]:focus-visible{outline:2px solid currentColor;outline-offset:2px}`,
  );

  // Сироты прошлой установки.
  try { for (const node of document.querySelectorAll(`[${AUTO_RETRY_ATTRIBUTE}]`)) node.remove(); } catch {}
  on(document, "click", onAutoRetryClick, true);
  on(window, "keydown", onAutoRetryKey, true);
  track(() => {
    autoRetryState.check = null;
    autoRetryUnpaint();
    try { for (const node of document.querySelectorAll(`[${AUTO_RETRY_ATTRIBUTE}]`)) node.remove(); } catch {}
  });
  // Повтор при ошибке сервера (#6936, К-AR): state — см. autoRetryState; next и last — ISO; stoppedBy — hour | cancel;
  // presses — нажатий этой страницей; outcome — started | press-failed | null.
  statusPart("autoRetry", () => {
    const s = autoRetryState;
    return {
      on: autoRetryOn(), every: autoRetryEvery(), state: s.state, reason: s.reason || null, kind: s.kind,
      tries: s.tries, max: s.max, next: autoRetryIso(s.next), last: autoRetryIso(s.last), stoppedBy: s.stoppedBy,
      presses: s.presses, manual: s.manual, outcome: s.outcome,
    };
  });
  HATCH && Object.assign(HATCH, { autoRetryTick, autoRetryKind });
