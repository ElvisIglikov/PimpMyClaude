  // ---- 12к. Кнопка «💬 Новый чат» в самом чате (#7246, WF84) -----
  // Слово Элвиса 23.09: «кнопку „Продолжить в новом чате“ в самом чате, где блок
  // продолжения… чтоб всё автоматически было под рукой». Под блоком кода с
  // текстом передачи ПОСЛЕДНЕГО ответа (тот же поиск, что у «Обкэшить» с
  // handoff, К1) страница рисует кнопку; клик — то же, что пункт меню ⌘B
  // «💬 Новый чат» (ClaudeActions.handoffNewChat).
  //
  // Канал «страница → приложение» — ЗАГОЛОВОК ОКНА, как у замка К6 (спайк S0:
  // смена document.title видна в AX за 3–13 мс). Формат побайтно:
  // `PMP: продолжить в новом чате · <метка>`, метка — Date.now() в base36,
  // новая на каждый клик. Держим CONTINUE_HOLD_MS и возвращаем прежний
  // заголовок; приложение (ContinueWatch, опрос 0,25 с) по метке запоминает
  // ОКНО, ждёт, пока метка уйдёт (иначе прочитало бы её вместо имени чата), и
  // зовёт handoffNewChat. Ответ приложения — сама команда cashout с handoff:
  // пришла — кнопка «✓ открываю»; не пришла за CONTINUE_WAIT_MS — кнопка снова
  // живая, плашка «Пимп пока не взялся». Срок не короче законной очереди
  // приложения (замок пустого окна до ~9,5 с, z2-r03). Контракт —
  // docs/CONTRACTS.md, раздел WF84.
  //
  // Подпись рисует CSS из атрибута (::after): innerText ответа её не видит, и в
  // «Обкэшить» без handoff, копию ответа и выделение текста она не попадёт.
  // Подпись кнопки с 23.09 ~21:05 — «💬 Новый чат» (слово Элвиса: «длинно»);
  // метка заголовка ниже — контракт с ContinueWatch.swift: с #9604 начинается
  // с «PMP» (в интерфейсе только PMP), менять только парой.
  const CONTINUE_TITLE_PREFIX = "PMP: продолжить в новом чате";
  const CONTINUE_LABEL = "💬 Новый чат";
  const CONTINUE_LABEL_WAIT = `⏳ ${CONTINUE_WAIT_TEXT}`;
  const CONTINUE_LABEL_ACK = "✓ Открываю новый чат…";
  const CONTINUE_NOTE_SILENT = "PMP пока не взялся — проверь, что он запущен и у него есть доступ, и нажми ещё раз";
  const CONTINUE_LINK_TITLE = "Открыть новый чат с этим текстом (PMP)";
  const CONTINUE_HOLD_MS = 1200;
  const CONTINUE_KEEP_MS = 100;
  const CONTINUE_WAIT_MS = 12000;
  const CONTINUE_SCAN_MS = 400;
  // Клик по ссылке ждёт, не двойной ли он (WF93): двойной и тройной выделяют
  // текст заголовка, а первый их клик иначе уже открыл бы чат.
  const CONTINUE_LINK_DELAY_MS = 500;
  const continueState = {
    at: -Infinity, shown: 0, clicks: 0, pending: false, acked: 0, silent: 0, timers: new Set(),
    linkState: "", linkShown: 0, linkClicks: 0, acking: false, linkTimer: 0,
  };
  // Занято — ждём ответа приложения или показываем «✓» (WF93): клик в это
  // время открыл бы второй чат.
  const continueBusy = () => continueState.pending || continueState.acking;
  const continueLater = (fn, ms) => {
    const id = setTimeout(() => { continueState.timers.delete(id); fn(); }, ms);
    continueState.timers.add(id);
    return id;
  };
  // «Сам» (WF85, К7.5, #7347): под блоком передачи идёт отсчёт «💬 Новый чат
  // через N с», и по нему страница жмёт кнопку сама. Рядом «✕» — со СВОИМ
  // атрибутом (критик Б1): иначе клик по ней ловился бы как клик по кнопке и
  // открывал чат. Всё, что про основную кнопку, берёт только её.
  const CONTINUE_CANCEL_ATTRIBUTE = "data-myclaude-continue-cancel";
  const autoState = {
    chat: undefined, armed: false, armPrint: "", stopGoneAt: 0, print: "", counting: false, left: 0, tickAt: 0,
    state: "off", reason: "", fired: 0, cancelled: 0, inputAt: 0,
  };
  const continueButtons = () => {
    try {
      return [...document.querySelectorAll(`[${CONTINUE_ATTRIBUTE}] button:not([${CONTINUE_CANCEL_ATTRIBUTE}])`)];
    } catch { return []; }
  };
  const continueLinks = () => {
    try { return [...document.querySelectorAll(`[${CONTINUE_LINK_ATTRIBUTE}]`)]; } catch { return []; }
  };
  // Занято (⏳ или ✓) — буквы переливаются, ссылка aria-disabled (#7772).
  const busyMark = (node, busy) => {
    if (busy) {
      if (node.getAttribute(BUSY_ATTRIBUTE) !== "1") node.setAttribute(BUSY_ATTRIBUTE, "1");
      if (node.getAttribute("aria-disabled") !== "true") node.setAttribute("aria-disabled", "true");
    } else {
      node.removeAttribute(BUSY_ATTRIBUTE);
      node.removeAttribute("aria-disabled");
    }
  };
  const continueLinkPaint = link => {
    if (continueState.linkState) {
      link.setAttribute(CONTINUE_LINK_STATE_ATTRIBUTE, continueState.linkState);
      const text = String(link.textContent ?? "").trim();
      if (link.getAttribute(CONTINUE_LINK_TEXT_ATTRIBUTE) !== text) link.setAttribute(CONTINUE_LINK_TEXT_ATTRIBUTE, text);
    } else {
      link.removeAttribute(CONTINUE_LINK_STATE_ATTRIBUTE);
      link.removeAttribute(CONTINUE_LINK_TEXT_ATTRIBUTE);
    }
    busyMark(link, continueState.linkState !== "");
  };
  const continueLinkOff = link => {
    link.removeAttribute(CONTINUE_LINK_ATTRIBUTE);
    link.removeAttribute(CONTINUE_LINK_STATE_ATTRIBUTE);
    link.removeAttribute(CONTINUE_LINK_TEXT_ATTRIBUTE);
    busyMark(link, false);
    if (link.getAttribute("title") === CONTINUE_LINK_TITLE) link.removeAttribute("title");
  };
  const continueLabel = text => {
    continueState.linkState = text === CONTINUE_LABEL_WAIT ? "wait" : text === CONTINUE_LABEL_ACK ? "ack" : "";
    for (const link of continueLinks()) continueLinkPaint(link);
    for (const button of continueButtons()) {
      if (button.getAttribute(CONTINUE_LABEL_ATTRIBUTE) !== text) button.setAttribute(CONTINUE_LABEL_ATTRIBUTE, text);
      // Подпись отсчёта не «занята»: клик во время счёта открывает чат сразу.
      busyMark(button, text === CONTINUE_LABEL_WAIT || text === CONTINUE_LABEL_ACK);
    }
  };
  const autoText = () => (autoState.counting && autoState.state === "count"
    ? `${CONTINUE_LABEL} через ${Math.max(1, Math.ceil(autoState.left / 1000))} с`
    : CONTINUE_LABEL);
  const continueCancelMake = () => {
    const cancel = document.createElement("button");
    cancel.setAttribute("type", "button");
    cancel.setAttribute(CONTINUE_CANCEL_ATTRIBUTE, "");
    cancel.setAttribute("aria-label", "Не открывать новый чат сам");
    cancel.setAttribute(CONTINUE_LABEL_ATTRIBUTE, "✕");
    cancel.style.setProperty("margin-left", "6px");
    return cancel;
  };
  // React пересобрал блок посреди счёта — подпись и «✕» встают сразу, а не
  // со следующим тиком (заметка критика).
  const continueMake = () => {
    const box = document.createElement("div");
    box.setAttribute(CONTINUE_ATTRIBUTE, "");
    const button = document.createElement("button");
    button.setAttribute("type", "button");
    button.setAttribute("aria-label", CONTINUE_LABEL.replace(/^\S+\s/, ""));
    // Перерисовка во время «⏳» или «✓» — подпись и запрет клика те же.
    const label = continueState.pending || continueState.linkTimer ? CONTINUE_LABEL_WAIT
      : continueState.acking ? CONTINUE_LABEL_ACK : autoText();
    button.setAttribute(CONTINUE_LABEL_ATTRIBUTE, label);
    if (label === CONTINUE_LABEL_WAIT || label === CONTINUE_LABEL_ACK) busyMark(button, true);
    box.appendChild(button);
    if (autoState.counting) box.appendChild(continueCancelMake());
    return box;
  };
  // Кнопка стоит ровно под блоком передачи последнего ответа; старые (ответ
  // сменился, React пересобрал блок) убираем. Проход раскладки зовёт часто —
  // ищем не чаще CONTINUE_SCAN_MS.
  const markContinue = () => {
    const t = now();
    if (t - continueState.at < CONTINUE_SCAN_MS) return;
    continueState.at = t;
    const hit = cashoutHandoffFind();
    markContinueLinks(hit);
    const code = hit?.code ?? null;
    const host = code ? (code.closest?.(".epitaxy-codeblock") ?? code) : null;
    let kept = null;
    for (const box of document.querySelectorAll(`[${CONTINUE_ATTRIBUTE}]`)) {
      if (!kept && host && box.previousElementSibling === host) { kept = box; continue; }
      box.remove();
    }
    if (kept || !host?.parentNode) return;
    host.parentNode.insertBefore(continueMake(), host.nextElementSibling);
    continueState.shown += 1;
  };
  // Ссылка (WF88, К15): каждый заголовок «ОТКРОЙ НОВЫЙ ЧАТ» сообщения с
  // найденным блоком — верхний и хвостовой повтор, хоть в другой строке ленты
  // (2.9939.2); со всех прочих — снять.
  const markContinueLinks = hit => {
    const heads = new Set();
    for (const row of hit ? (hit.rows ?? [hit.answer]) : []) {
      for (const node of row.querySelectorAll('h1,h2,h3,h4,h5,h6,[role="heading"]')) {
        if (CASHOUT_HANDOFF_HEAD_RE.test(node.textContent ?? "")) heads.add(node);
      }
    }
    for (const link of continueLinks()) if (!heads.has(link)) continueLinkOff(link);
    for (const head of heads) {
      if (!head.hasAttribute(CONTINUE_LINK_ATTRIBUTE)) {
        head.setAttribute(CONTINUE_LINK_ATTRIBUTE, "1");
        head.setAttribute("title", CONTINUE_LINK_TITLE);
        continueState.linkShown += 1;
      }
      continueLinkPaint(head);
    }
  };
  const continueMarkOff = () => {
    const label = continueTitle.label;
    if (!label) return;
    continueTitle.label = "";
    try { if (document.title === label) document.title = continueTitle.saved; } catch {}
  };
  // Метка держится весь срок: Claude сам переписывает заголовок (попап, смена
  // чата) — ставим обратно, а его заголовок запоминаем, его и вернём.
  const continueMarkOn = () => {
    const label = `${CONTINUE_TITLE_PREFIX} · ${Date.now().toString(36)}`;
    if (!continueTitle.label) continueTitle.saved = String(document.title ?? "");
    continueTitle.label = label;
    try { document.title = label; } catch {}
    const until = now() + CONTINUE_HOLD_MS;
    const keep = () => {
      if (continueTitle.label !== label) return;
      if (now() >= until) { continueMarkOff(); return; }
      let title = "";
      try { title = String(document.title ?? ""); } catch { return; }
      if (title !== label) {
        continueTitle.saved = title;
        try { document.title = label; } catch {}
      }
      continueLater(keep, CONTINUE_KEEP_MS);
    };
    continueLater(keep, CONTINUE_KEEP_MS);
  };
  const continueClick = () => {
    if (continueBusy()) return;
    continueState.pending = true;
    continueState.clicks += 1;
    continueLabel(CONTINUE_LABEL_WAIT);
    continueMarkOn();
    continueLater(() => {
      if (!continueState.pending) return;
      continueState.pending = false;
      continueState.silent += 1;
      continueMarkOff();
      continueLabel(CONTINUE_LABEL);
      try { newWindowNote(CONTINUE_NOTE_SILENT); } catch {}
    }, CONTINUE_WAIT_MS);
  };
  // Команда cashout с handoff дошла — приложение взялось за работу.
  const continueAck = () => {
    if (!continueState.pending) return;
    continueState.pending = false;
    continueState.acked += 1;
    continueState.acking = true;
    continueMarkOff();
    continueLabel(CONTINUE_LABEL_ACK);
    continueLater(() => { continueState.acking = false; continueLabel(CONTINUE_LABEL); }, CONTINUE_WAIT_MS);
  };
  // ---- «Сам»: взвод, оценка, отсчёт, срабатывание (WF85, К7.5, #7347) ----
  // Взвод (критик Б2): страница видела кнопку стоп хода в СВОЁМ чате, она
  // пропала и не вернулась AUTO_SETTLE_MS — тогда ОДНА оценка, флаг гаснет
  // сразу после неё. Отсчёт живёт только для отпечатка ответа, на котором ход
  // кончился (`<чат>:<хэш текста передачи>`): листал ленту вверх, и последним
  // отрисован старый ответ со своим блоком — его отпечаток другой.
  // Тишина (критик В3): общий для окон штамп последнего ввода; считаем, только
  // пока с него прошло AUTO_QUIET_MS, — иначе новый чат отнял бы фокус у Элвиса
  // посреди набора. Тик — от сердца (setTimeout-интервал раздела 16), не от
  // кадра: скрытый попап кадров не получает, а досчитать обязан.
  const AUTO_KEY = "myclaude-auto-continue";
  const AUTO_SWITCH_KEY = "myclaude.autoContinue";
  const AUTO_INPUT_KEY = "myclaude-last-input";
  const AUTO_STOP_SELECTOR = '[data-testid="code-prompt-stop"]';
  const AUTO_SETTLE_MS = 3000;
  const AUTO_COUNT_MS = 15000;
  const AUTO_QUIET_MS = 30000;
  const AUTO_RATE_MAX = 3;
  const AUTO_RATE_MS = 10 * 60 * 1000;
  const AUTO_AGAIN_MS = 20000;
  const AUTO_DONE_MAX = 50;
  const AUTO_INPUT_GAP_MS = 1000;
  // F07: чистая установка выключена; прежний выбор переносит Swift явной
  // командой migrate:true. Ошибка хранилища не разрешает автоматическое действие.
  let autoStorageFailed = false;
  const autoOn = () => { try { return !autoStorageFailed && localStorage.getItem(AUTO_SWITCH_KEY) === "true"; } catch { return false; } };
  // Хранилище общее для окон: {"done":{"<отпечаток>":<ms>},"recent":[<ms>]}.
  const autoRead = () => {
    let data = null;
    try { data = JSON.parse(localStorage.getItem(AUTO_KEY) ?? "null"); } catch { data = null; }
    const t = Date.now();
    const done = {};
    if (data?.done && typeof data.done === "object") {
      for (const [key, at] of Object.entries(data.done)) if (Number.isFinite(Number(at))) done[key] = Number(at);
    }
    const recent = (Array.isArray(data?.recent) ? data.recent : []).map(Number)
      .filter(at => Number.isFinite(at) && t - at < AUTO_RATE_MS);
    return { done, recent };
  };
  const autoWrite = data => {
    const done = Object.fromEntries(Object.entries(data.done).sort((a, b) => a[1] - b[1]).slice(-AUTO_DONE_MAX));
    try { localStorage.setItem(AUTO_KEY, JSON.stringify({ done, recent: data.recent })); } catch {}
  };
  const autoRemember = print => {
    if (!print) return;
    const data = autoRead();
    data.done[print] = Date.now();
    autoWrite(data);
  };
  const autoHash = text => {
    let hash = 5381;
    for (let index = 0; index < text.length; index += 1) hash = ((hash * 33) ^ text.charCodeAt(index)) >>> 0;
    return hash.toString(36);
  };
  const autoPrint = hit => {
    const text = cashoutCodeText(hit?.code);
    if (!text) return "";
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    return `${chat || location.pathname}:${autoHash(text)}`;
  };
  const autoQuiet = () => {
    let stamp = NaN;
    try { stamp = Number(localStorage.getItem(AUTO_INPUT_KEY) ?? NaN); } catch {}
    return !Number.isFinite(stamp) || Date.now() - stamp >= AUTO_QUIET_MS;
  };
  const autoPaint = () => {
    if (!continueBusy() && !continueState.linkTimer) continueLabel(autoText());
    try {
      for (const box of document.querySelectorAll(`[${CONTINUE_ATTRIBUTE}]`)) {
        const cancel = box.querySelector(`[${CONTINUE_CANCEL_ATTRIBUTE}]`);
        if (autoState.counting && !cancel) box.appendChild(continueCancelMake());
        if (!autoState.counting && cancel) cancel.remove();
      }
    } catch {}
  };
  const autoStop = (name, reason) => {
    const was = autoState.counting;
    autoState.counting = false;
    autoState.left = 0;
    autoState.state = name;
    autoState.reason = reason;
    if (was) autoPaint();
  };
  const autoDisable = () => {
    autoState.armed = false;
    autoState.armPrint = "";
    autoState.stopGoneAt = 0;
    autoStop("off", "выключено");
  };
  const autoSet = detail => {
    if (!themable || typeof detail?.on !== "boolean") return;
    try {
      if (detail.migrate !== true || localStorage.getItem(AUTO_SWITCH_KEY) === null) {
        localStorage.setItem(AUTO_SWITCH_KEY, String(detail.on));
        autoStorageFailed = false;
      }
    } catch { autoStorageFailed = true; }
    if (!autoOn()) autoDisable();
  };
  const onAutoStorage = event => {
    if ((event?.key === AUTO_SWITCH_KEY || event?.key === null) && !autoOn()) autoDisable();
  };
  // Отменённый отпечаток — в done: повтора на тот же ответ нет.
  const autoCancel = reason => {
    if (!autoState.counting) return;
    autoRemember(autoState.print);
    autoState.cancelled += 1;
    autoStop("cancelled", reason);
  };
  // Ответ пошёл в новый чат руками (кнопка, ⌘B) — сам его больше не откроет.
  const autoTaken = hit => {
    autoRemember(autoPrint(hit));
    if (autoState.counting) autoStop("off", "нажато руками");
  };
  const autoDonorHeavy = line => {
    const want = cashoutHandoffModel(line);
    let model = "";
    let effort = "";
    try { model = want.model ?? newWindowModelNow() ?? ""; } catch {}
    try { effort = want.effort ?? newWindowEffortShown() ?? ""; } catch {}
    return /fable/i.test(model) || newWindowEffortKey(effort) === "max";
  };
  const autoJudge = t => {
    const hit = cashoutHandoffFind();
    const print = autoPrint(hit);
    const line = cashoutHandoffModelLine(hit);
    const data = autoRead();
    let bottom = null;
    try { bottom = progressAtBottom(); } catch {}
    let editor = "";
    try { editor = editorText(state.editor); } catch {}
    const why = !autoOn() ? "выключено"
      : bottom === false ? "лента не у низа"
      : !print ? "нет блока"
      : waitState.kind === "awaiting" ? "чат ждёт ответа"
      // «running» строки списка слева в судьи не берём (живой гейт WF85): у строки
      // в «Recents» он висел минутами после конца хода, когда сессия давно стояла.
      // Конец хода говорит только кнопка стоп своего поля.
      : data.done[print] ? "уже было"
      : print === autoState.armPrint ? "ответ старый"
      : data.recent.length >= AUTO_RATE_MAX ? "частота"
      // Fable и Max — только по нажатию Элвиса (WORKFLOW.md).
      : /\bfable\b|\bmax\b/i.test(line) ? "Fable/Max — руками"
      // Чего в строке нет, то новый чат возьмёт у донора (проверка WF85, D2):
      // донор на Fable или Max — тоже только руками.
      : autoDonorHeavy(line) ? "Fable/Max — руками"
      // Попап-донор закроется вместе с черновиком (критик В3).
      : editor ? "черновик в поле"
      : roamState.phase !== "idle" ? "обход Авто-Allow"
      : continueBusy() ? "уже нажато"
      : "";
    if (why) { autoStop("off", why); return; }
    autoState.print = print;
    autoState.counting = true;
    autoState.left = AUTO_COUNT_MS;
    autoState.tickAt = t;
    autoCount(t);
  };
  // Срабатывание (критик В4): страниц одного чата бывает две — перечитываем
  // хранилище и пишем done и recent тем же синхронным шагом, что и жмём.
  const autoFire = () => {
    const print = autoState.print;
    const data = autoRead();
    const t = Date.now();
    if (!autoOn()) { autoStop("off", "выключено"); return; }
    if (data.done[print]) { autoStop("wait", "уже открыт"); return; }
    if (data.recent.some(at => t - at < AUTO_AGAIN_MS)) { autoStop("wait", "только что открывали"); return; }
    // Вставку мышью keydown не ловит (проверка WF85, D4) — поле смотрим ещё раз.
    let editor = "";
    try { editor = editorText(state.editor); } catch {}
    if (editor) { autoCancel("черновик в поле"); return; }
    data.done[print] = t;
    data.recent.push(t);
    autoWrite(data);
    autoState.fired += 1;
    autoStop("fired", "");
    continueClick();
  };
  const autoCount = t => {
    const step = Math.max(0, t - autoState.tickAt);
    autoState.tickAt = t;
    // Обход Авто-Allow посреди счёта (критик В9) и смена ответа — отмена.
    if (roamState.phase !== "idle") { autoCancel("обход Авто-Allow"); return; }
    if (autoPrint(cashoutHandoffFind()) !== autoState.print) { autoCancel("ответ сменился"); return; }
    if (!autoQuiet()) {
      autoState.left = AUTO_COUNT_MS;
      autoState.state = "wait";
      autoState.reason = "Элвис работает";
      autoPaint();
      return;
    }
    autoState.left -= step;
    autoState.state = "count";
    autoState.reason = "";
    if (autoState.left > 0) { autoPaint(); return; }
    autoFire();
  };
  const autoTick = t => {
    if (!themable) return;
    if (!autoOn()) { autoDisable(); return; }
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    if (chat !== autoState.chat) {
      autoState.chat = chat;
      autoState.armed = false;
      autoState.armPrint = "";
      autoState.stopGoneAt = 0;
      autoCancel("чат сменился");
    }
    let stop = null;
    try { stop = document.querySelector(AUTO_STOP_SELECTOR); } catch {}
    if (stop) {
      // Отпечаток ответа, что был последним, когда ход начался (проверка WF85,
      // D1): ход прервали или он упал без нового ответа — последним остаётся
      // старый ответ с блоком, и открывать его сам отсчёт не должен.
      if (!autoState.armed) autoState.armPrint = autoPrint(cashoutHandoffFind());
      autoState.armed = true;
      autoState.stopGoneAt = 0;
      autoCancel("ход пошёл снова");
      return;
    }
    if (autoState.counting) { autoCount(t); return; }
    if (!autoState.armed) return;
    if (!autoState.stopGoneAt) { autoState.stopGoneAt = t; return; }
    if (t - autoState.stopGoneAt < AUTO_SETTLE_MS) return;
    autoState.armed = false;
    autoState.stopGoneAt = 0;
    autoJudge(t);
  };
  // Ввод Элвиса в любой странице Claude — штамп тишины (не чаще раза в
  // секунду); клавиша в поле ввода ЭТОГО окна — отмена насовсем. Свои
  // синтетические клавиши (Escape, стрелки цепочки) штампом не считаем.
  const onAutoInput = event => {
    if (event?.isTrusted === false) return;
    const t = Date.now();
    if (t - autoState.inputAt >= AUTO_INPUT_GAP_MS) {
      autoState.inputAt = t;
      try { localStorage.setItem(AUTO_INPUT_KEY, String(t)); } catch {}
    }
    if (event?.type !== "keydown" || !autoState.counting) return;
    const target = event.target;
    if (target && (state.editor?.contains?.(target) || state.composerBlock?.contains?.(target))) autoCancel("клавиша в поле");
  };
  const continueSelected = () => {
    try { return String(((typeof getSelection === "function" ? getSelection() : null) ?? document.getSelection?.())?.toString?.() ?? "") !== ""; } catch { return false; }
  };
  // Ждущий клик снят (двойной, выделение) — «⏳» было только обещанием,
  // подпись возвращается.
  const continueLinkDrop = () => {
    if (!continueState.linkTimer) return;
    clearTimeout(continueState.linkTimer);
    continueState.timers.delete(continueState.linkTimer);
    continueState.linkTimer = 0;
    if (!continueBusy()) continueLabel(autoText());
  };
  const onContinueClick = event => {
    if (event.target?.closest?.(`[${CONTINUE_CANCEL_ATTRIBUTE}]`)) {
      event.preventDefault?.();
      event.stopPropagation?.();
      autoCancel("✕");
      return;
    }
    const link = event.target?.closest?.(`[${CONTINUE_LINK_ATTRIBUTE}]`);
    if (link) {
      // Второй и третий клик (event.detail) — выделение слова и строки: ждущий
      // первый клик снимается, чат не открывается (WF93).
      if (Number(event.detail) > 1) { continueLinkDrop(); return; }
      // Левая кнопка без модификаторов и без выделения: выделить текст
      // заголовка или ⌘-клик — не открытие чата. Занято — ничего.
      if ((event.button ?? 0) !== 0 || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return;
      if (continueSelected()) return;
      event.preventDefault?.();
      event.stopPropagation?.();
      if (continueBusy() || continueState.linkTimer) return;
      // «⏳ Зову Пимпа…» и перелив — сразу, а не через полсекунды ожидания
      // двойного клика (#7772): нажатие видно, повтор ничего не делает.
      continueLabel(CONTINUE_LABEL_WAIT);
      continueState.linkTimer = continueLater(() => {
        continueState.linkTimer = 0;
        if (continueBusy()) return;
        if (continueSelected()) { continueLabel(autoText()); return; }
        continueState.linkClicks += 1;
        autoTaken(cashoutHandoffFind());
        continueClick();
      }, CONTINUE_LINK_DELAY_MS);
      return;
    }
    const button = event.target?.closest?.(`[${CONTINUE_ATTRIBUTE}] button`);
    if (!button) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    // Ссылку уже нажали и ждём, не двойной ли клик (#7772), — кнопка молчит.
    if (continueBusy() || continueState.linkTimer) return;
    // Ручной клик тоже пишет отпечаток в done (критик Б2).
    autoTaken(cashoutHandoffFind());
    continueClick();
  };
  // Сироты прошлой установки — до первой разметки.
  try { for (const box of document.querySelectorAll(`[${CONTINUE_ATTRIBUTE}]`)) box.remove(); } catch {}
  for (const link of continueLinks()) continueLinkOff(link);
  on(document, "click", onContinueClick, true);
  track(() => {
    for (const id of continueState.timers) clearTimeout(id);
    continueState.timers.clear();
    continueState.pending = false;
    continueState.acking = false;
    continueState.linkTimer = 0;
    // Своих таймеров у отсчёта нет (тик — сердце раздела 16): снять счёт и кнопки.
    autoState.counting = false;
    continueMarkOff();
    try { for (const box of document.querySelectorAll(`[${CONTINUE_ATTRIBUTE}]`)) box.remove(); } catch {}
    for (const link of continueLinks()) continueLinkOff(link);
  });
  statusPart("autoContinue", () => autoOn());
  // Кнопка «💬 Новый чат» (раздел 12к, #7246): стоит ли сейчас,
  // сколько раз ставилась, нажата, дошла ли команда приложения, молчание.
  statusPart("continue", () => ({
    button: continueButtons().length, shown: continueState.shown, clicks: continueState.clicks,
    pending: continueState.pending, acked: continueState.acked, silent: continueState.silent,
    mark: continueTitle.label || null,
    // Ссылка на заголовках «ОТКРОЙ НОВЫЙ ЧАТ» (WF88, К15).
    link: { shown: continueState.linkShown, clicks: continueState.linkClicks },
    // «Сам» (WF85, К7.5): state — off | wait | count | fired | cancelled.
    auto: {
      on: autoOn(), state: autoState.state, reason: autoState.reason || null,
      left: autoState.counting ? Math.ceil(autoState.left / 1000) : 0,
      fired: autoState.fired, cancelled: autoState.cancelled,
    },
  }));

