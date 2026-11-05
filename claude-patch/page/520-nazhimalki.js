  // ---- 12с. Нажималки в ответах (#7843, #7842, WF98) ------------------------
  // Слово Элвиса 26.09 ~05:50: «оно не должно отправлять, оно просто должно
  // вписать, какой вариант брать»; «разрешаю» и «сделал» — «тоже не
  // отправляли»; «переключать сам режим тоже делаем»; «пусть будет отчёт»;
  // новый чат — с отсчётом, «чтобы не нажимать по ошибке».
  //
  // Блок — заголовок, весь текст которого служебная фраза (как у 12р), и всё
  // до следующего заголовка; в ЛЮБОМ ответе ленты:
  //   «🔘 ВЫБОР» — строки «⚪ …» нажимаются: в поле «Решение N: бери другой
  //     вариант — <вариант до „ — “>»; N — номер решения: ol.start + место li
  //     (Markdown рвёт список на несколько <ol start>), запасной — число в
  //     начале строки решения;
  //   «👾 ЭЛВИС, СДЕЛАЙ» — у пункта кнопка «✓ сделал»: «Сделал: пункт N — <начало>»;
  //   «🦾 Нужен …» — «разрешаю» / «нет»: «Разрешаю: <задача>» / «Не разрешаю: …»;
  //   «❗ Включи Accept Edits» / «❗ Верни режим Авто» — «Включить» / «Вернуть»:
  //     сами жмут переключатель режима под полем (ниже);
  //   «📄 НУЖЕН ОТЧЁТ?» — кнопка «отчёт» после блока (слово там в „кавычках“,
  //     текст React не режем — своя кнопка, как у 12к): в поле, отсчёт, отправка.
  // #7842: последний ответ законченного хода (стопа нет, после ответа нет
  // реплики Элвиса, блока «ОТКРОЙ НОВЫЙ ЧАТ» нет) в одном из двух последних
  // абзацев (служебные строки состояния и расхода не в счёт; код, цитаты и
  // заголовки не в счёт) ПРЕДЛАГАЕТ продолжить в новом/другом чате — под этим
  // абзацем «💬 Новый чат»: в поле просьба дать блок «ОТКРОЙ НОВЫЙ ЧАТ»,
  // отсчёт, отправка; дальше работает кнопка 12к со своим автоотсчётом.
  //
  // Поле — как у 12р: свой текст Элвиса (что было до первого нажатия) не
  // переписывается, меняется только хвост из вписанных строк (через «; »; строка с nl — с новой
  // строки, фразы «Ждёт тебя» раздела 12с², #10910; сверка поля — через sayNorm, как у 12р);
  // повторное нажатие снимает строку; варианты одного решения, «разрешаю» и
  // «нет», «отчёт» и «💬 Новый чат» сменяют друг друга. Сами отправляют только
  // «отчёт» и «💬 Новый чат» и только когда в поле больше ничего нет: отсчёт
  // NAZH_WAIT_MS, дотикал и в
  // поле РОВНО эта строка — запускаем общий настраиваемый отсчёт с отменой.
  // Поле поменяли, клавиша в поле, нажатие ещё раз — отсчёт гаснет. Отсчёт
  // один на окно, свой (не sayState). Смена чата и новый ход — всё сброшено.
  // Двойной клик — одно нажатие (#7772); занятая кнопка приглушена, без
  // перелива (#7852). Подписи — из атрибута: копия, выделение и «Обкэшить» их
  // не видят.
  const NAZH_WAIT_MS = 5000;
  const NAZH_STEP_MS = 200;
  const NAZH_MENU_MS = 1500;
  const NAZH_POLL_MS = 50;
  const NAZH_WORDS = 8;
  const NAZH_TASK_MAX = 140;
  const NAZH_SEP = "; ";
  const NAZH_HEADS = [
    ["pick", /^[^\p{L}\p{N}]*ВЫБОР[^\p{L}\p{N}]*$/iu],
    ["done", /^[^\p{L}\p{N}]*(?:ЭЛВИС,?\s+)?СДЕЛАЙ[^\p{L}\p{N}]*$/iu],
    ["permit", /^[^\p{L}\p{N}]*Нужен\s+(?:Opus|Fable)(?![\p{L}])/iu],
    ["accept", /^[^\p{L}\p{N}]*Включи\s+(?:режим\s+)?Accept\s+Edits[^\p{L}\p{N}]*$/iu],
    ["auto", /^[^\p{L}\p{N}]*Верни\s+режим\s+(?:Авто|Auto)[^\p{L}\p{N}]*$/iu],
    ["report", /^[^\p{L}\p{N}]*НУЖЕН\s+ОТЧ[ЁЕ]Т[^\p{L}\p{N}]*$/iu],
  ];
  const NAZH_CHAT_TEXT = "Дай блок «ОТКРОЙ НОВЫЙ ЧАТ» с текстом передачи";
  const NAZH_ACCEPT_TEXT = "Включил Accept Edits — делай";
  // Предложение продолжить в другом чате: «предлагаю / давай / лучше …
  // продолжить в новом чате», «продолжим в другом чате», «предлагаю новый чат».
  // Перед ним «не» — не предложение; «не» внутри прокладки — тоже (wf98-g-2).
  // «Чат» — единственное число целым словом («другие чаты» — не предложение),
  // «в новом чате браузера / Chrome» — про вкладку, не про чат Claude.
  const NAZH_CHAT_PLACE = "(?:нов(?:ый|ом|ого)|друг(?:ой|ом|ого)|свеж(?:ий|ем|его)|отдельн(?:ый|ом|ого))\\s+чат(?:е|а|у|ом)?(?![\\p{L}])(?!\\s+(?:браузер\\p{L}*|Chrome|Хром\\p{L}*|Safari|вкладк\\p{L}*))";
  const NAZH_PAD = "(?:(?!не\\s)[\\p{L}-]+\\s+)";
  const NAZH_OFFER_RES = [
    new RegExp(`(?<!\\p{L})(?:предлагаю|давай(?:те)?|лучше|стоит|советую|пора|можно)\\s+${NAZH_PAD}{0,3}?(?:продолж\\p{L}*|перейти|переехать|перенести|открыть|начать|уйти)\\s+${NAZH_PAD}{0,2}?в\\s+${NAZH_CHAT_PLACE}`, "iu"),
    new RegExp(`(?<!\\p{L})(?:продолжим|перейд[её]м|переед[её]м)\\s+${NAZH_PAD}{0,2}?в\\s+${NAZH_CHAT_PLACE}`, "iu"),
    new RegExp(`(?<!\\p{L})(?:предлагаю|давай(?:те)?|лучше|пора)\\s+(?:открыть\\s+|откроем\\s+|завести\\s+|заведём\\s+|начать\\s+|начнём\\s+)?${NAZH_CHAT_PLACE}`, "iu"),
  ];
  // Служебные строки конца ответа (ELVIS.md): состояние и расход.
  const NAZH_SERVICE_RE = /·\s*(?:идёт|жду|готово|упал)\s*\S*\s*$|^Контекст\s+[\d.]+\s*[KM]?|^Из\s+кэша\s+\d|^Ответ\s+[\d.]+\s*[KM]|^❗\s*Перечитка/iu;
  // Режимы под полем (CHIN_MODES, раздел 12з¹) → пункт их меню. Bypass и Plan
  // не жмём никогда: их здесь нет, и меню с ними сверяется отдельно.
  // #11618: и пункты меню по-русски (каталог claude.ai: «Авто», «Принимать правки»; «Ask…» — «Спрашивать…» по смыслу).
  const NAZH_MODE_ITEM = { Au: /^(?:auto(?:\s+mode)?|авто(?:матический\s+режим)?)(?![\p{L}-])/iu,
    Ac: /^(?:accept\s+edits|принимать\s+правки|принятие\s+правок)/i, As: /^(?:ask|спрашивать|запрашивать)/i };
  const NAZH_MODE_NAME = { Au: "Auto", Ac: "Accept edits", As: "Ask" };
  const nazhState = {
    chat: undefined, working: false, lines: [], base: "", expect: null,
    armed: false, until: 0, left: 0, timer: 0, sends: 0, clicks: 0, skip: "",
    slots: [], info: new Map(), picks: new Map(), offer: null, offers: 0,
    modeBusy: "", modeBefore: new Map(), modes: 0, modeFails: 0, modeNote: "", timers: new Set(),
  };
  // Текст узла без вложенных списков (и что ещё передали), без своих кнопок.
  // Узел без детей, но с текстом (стенд тестов) — сам себе текст.
  const nazhOwnText = (node, skip = "ul,ol") => {
    if (!node) return "";
    if (!(node.childNodes ?? []).length) return sayNorm(node.textContent);
    let out = "";
    const walk = item => {
      for (const kid of item.childNodes ?? []) {
        if (kid.nodeType === 3) { out += String(kid.nodeValue ?? kid.textContent ?? ""); continue; }
        if (kid.nodeType !== 1) continue;
        if (kid.hasAttribute?.(NAZH_BUTTON_ATTRIBUTE) || kid.hasAttribute?.(NAZH_BOX_ATTRIBUTE)) continue;
        try { if (kid.matches?.(skip)) continue; } catch {}
        if (!(kid.childNodes ?? []).length) { out += String(kid.textContent ?? ""); continue; }
        walk(kid);
      }
    };
    walk(node);
    return sayNorm(out);
  };
  const nazhKind = head => {
    const text = sayNorm(head?.textContent);
    for (const [kind, re] of NAZH_HEADS) if (re.test(text)) return kind;
    return null;
  };
  // Блок заголовка: соседи до следующего заголовка, свои обёртки — мимо.
  const nazhDoneNodes = new Set();
  const nazhDoneClear = () => {
    for (const node of nazhDoneNodes) {
      for (const attr of [DONE_LIST_ATTRIBUTE, DONE_ITEM_ATTRIBUTE, DONE_CONT_ATTRIBUTE]) node.removeAttribute(attr);
    }
    nazhDoneNodes.clear();
  };
  const nazhAnswer = node => node?.closest?.(`[data-testid="transcript-row"],${ANSWER_SELECTOR}`);
  const nazhBlock = head => {
    const list = [];
    const done = nazhKind(head) === "done";
    const answer = nazhAnswer(head);
    for (let node = head.nextElementSibling; node; node = node.nextElementSibling) {
      if (node.hasAttribute?.(NAZH_BOX_ATTRIBUTE)) continue;
      try { if (node.matches?.(ATTN_HEAD_SELECTOR) || node.querySelector?.(ATTN_HEAD_SELECTOR)) break; } catch { break; }
      if (done && (node.tagName === "HR" || NAZH_SERVICE_RE.test(nazhOwnText(node)) ||
        node.matches?.('.epitaxy-user-turn,form,[role="dialog"],[contenteditable="true"]') ||
        node.querySelector?.('.epitaxy-user-turn,form,[role="dialog"],[contenteditable="true"],input,textarea') ||
        (answer && nazhAnswer(node) !== answer))) break;
      // Отдельная интерактивная область не продолжает пункт; родные Copy/Run у кода допустимы.
      if (done && node.tagName === "DIV" && !node.querySelector?.("pre")) break;
      if (done && node.tagName !== "PRE" && !node.querySelector?.("pre") &&
        (node.matches?.('button,[role="button"],[role="menu"]') ||
          node.querySelector?.(`button:not([${NAZH_BUTTON_ATTRIBUTE}]),[role="button"],[role="menu"]`))) break;
      list.push(node);
    }
    return list;
  };
  const nazhItems = block => {
    const list = [];
    for (const node of block) {
      if (node.matches?.("li")) list.push(node);
      try { list.push(...node.querySelectorAll("li")); } catch {}
    }
    return list;
  };
  const nazhIsLi = node => node?.tagName === "LI";
  // Родной номер: start, затем возможные li.value (в том числе после разрыва Markdown).
  const nazhIndex = li => {
    const list = li?.parentElement;
    if (!list || list.tagName !== "OL") return null;
    const start = Number.parseInt(String(list.getAttribute?.("start") ?? ""), 10);
    let number = Number.isFinite(start) ? start : 1;
    for (const item of [...list.children].filter(nazhIsLi)) {
      const value = Number.parseInt(String(item.getAttribute?.("value") ?? ""), 10);
      if (Number.isFinite(value)) number = value;
      if (item === li) return number;
      number += 1;
    }
    return null;
  };
  // Число в начале строки: «1.», «2)», «Решение 3 —».
  const nazhLead = node => {
    const hit = nazhOwnText(node).match(/^[^\p{L}\p{N}]*(?:Решение\s+)?(\d{1,3})(?:[.):]|\s+[—–-])/iu);
    return hit ? Number(hit[1]) : null;
  };
  // Номер решения строки «⚪»: пункт <ol>, внутри которого её список; список
  // стоит сам по себе — ближайший сосед выше (последний пункт <ol> или строка
  // с числом); запасной — число в тексте самой строки.
  const nazhPickNumber = li => {
    const list = li.parentElement;
    const outer = list?.parentElement?.closest?.("li") ?? null;
    if (outer) return nazhIndex(outer) ?? nazhLead(outer);
    for (let node = list?.previousElementSibling; node; node = node.previousElementSibling) {
      try { if (node.matches?.(ATTN_HEAD_SELECTOR)) break; } catch { break; }
      if (node.tagName === "OL") {
        const items = [...node.children].filter(nazhIsLi);
        if (items.length) return nazhIndex(items[items.length - 1]);
      }
      if (node.tagName === "UL") continue;
      const lead = nazhLead(node);
      if (lead != null) return lead;
    }
    return nazhLead(li);
  };
  const nazhCut = (text, max) => (text.length > max ? `${text.slice(0, max - 1).trimEnd()}…` : text);
  // Первая строка блока (задача «🦾 Нужен …»): первый абзац или пункт.
  const nazhFirstLine = block => {
    for (const node of block) {
      const item = node.matches?.("ul,ol") ? node.querySelector?.("li") : node;
      const raw = String(item?.innerText ?? item?.textContent ?? "").split("\n").map(sayNorm).find(Boolean) ?? "";
      const text = raw.replace(/^[-•*\s]*(?:Задача\s*:\s*)?/iu, "").trim();
      if (text) return nazhCut(text, NAZH_TASK_MAX);
    }
    return "";
  };
  const nazhHas = key => nazhState.lines.some(line => line.key === key);
  // «→ в чат» (#7980, WF120): ```-блок без языка (или text) в ответе — это текст для
  // чата, а не команда (▶ раздела 12т его не берёт: runCommandOf и runComplexOf — null)
  // и не блок передачи «ОТКРОЙ НОВЫЙ ЧАТ» (раздел 12к). Кнопка — в полосе блока перед
  // «Copy code»; строка — как у «отчёт» (тоже отправляет сама): nazhToggle с send, общий
  // отсчёт отправки, Esc и ещё клик — отмена, свой текст в поле — только дописать.
  // В поле идёт исходный текст с переносами; sayNorm — только для сравнения.
  // Вывод инструментов (TurnStatus) — мимо.
  // Блок передачи — первый непустой блок после заголовка «ОТКРОЙ НОВЫЙ ЧАТ» в той же
  // строке ленты (как cashoutHandoffFind, но в любом ответе, не только в последнем).
  const nazhHandoffCodes = row => {
    const out = new Set();
    let open = false;
    try {
      for (const node of row.querySelectorAll('h1,h2,h3,h4,h5,h6,[role="heading"],[data-code-text]:not([data-epitaxy-inline-code])')) {
        if (!node.hasAttribute("data-code-text")) { if (CASHOUT_HANDOFF_HEAD_RE.test(node.textContent ?? "")) open = true; continue; }
        if (open && cashoutCodeText(node)) { out.add(node.closest?.(".epitaxy-codeblock") ?? node); open = false; }
      }
    } catch {}
    return out;
  };
  const nazhCodeBlocks = () => {
    const list = [];
    let blocks = [];
    try { blocks = [...document.querySelectorAll(".epitaxy-codeblock")]; } catch { return list; }
    const handoffs = new Map();
    for (const block of blocks) {
      const row = block.closest?.(RUN_ROW_SELECTOR);
      if (!row || block.closest?.('[contenteditable="true"],[data-cds="TurnStatus"]') || state.composerBlock?.contains?.(block)) continue;
      const props = runPropsOf(block);
      const tag = String(props?.rawLang ?? props?.lang ?? "?").trim().toLowerCase();
      if ((tag !== "" && tag !== "text") || runCommandOf(props) || runComplexOf(props)) continue;
      const text = String(props.text ?? "");
      if (!text.trim()) continue;
      if (!handoffs.has(row)) handoffs.set(row, nazhHandoffCodes(row));
      if (handoffs.get(row).has(block)) continue;
      let copy = null;
      try { copy = block.querySelector(RUN_COPY_SELECTOR); } catch {}
      if (copy?.parentElement) list.push({ block, copy, text });
    }
    return list;
  };
  // Что должно стоять в ленте: строки «⚪» и места под кнопки. Место — узел,
  // «после» которого обёртка, или узел, «внутрь» которого кнопка.
  const nazhScan = () => {
    const picks = [];
    const wanted = [];
    const doneMarks = new Map();
    let heads = [];
    try { heads = [...document.querySelectorAll(ATTN_HEAD_SELECTOR)]; } catch { heads = []; }
    for (const head of heads) {
      if (head.closest?.('[contenteditable="true"]') || state.composerBlock?.contains?.(head)) continue;
      const kind = nazhKind(head);
      if (!kind) continue;
      const block = nazhBlock(head);
      if (kind === "pick") {
        for (const li of nazhItems(block)) {
          const own = nazhOwnText(li);
          if (!own.startsWith("⚪")) continue;
          const variant = own.replace(/^[^\p{L}\p{N}]+/u, "").split(/\s+[—–]\s+/)[0].replace(/[.;:,\s]+$/, "").trim();
          if (!variant) continue;
          const number = nazhPickNumber(li);
          const lead = number == null ? "Решение" : `Решение ${number}`;
          picks.push({ node: li, line: { key: `pick:${number}:${variant}`, group: `pick:${number ?? variant}`, text: `${lead}: бери другой вариант — ${variant}` } });
        }
      } else if (kind === "done") {
        if (head.closest?.('.epitaxy-user-turn') || !answerUsable(head)) continue;
        for (const li of nazhItems(block)) {
          const number = nazhIndex(li);
          if (number == null || li.parentElement?.parentElement?.closest?.("li")) continue;
          const first = [...(li.children ?? [])].find(kid => kid.tagName === "P") ?? null;
          const words = nazhOwnText(first ?? li, "ul,ol,pre").replace(/^[^\p{L}\p{N}]+/u, "").split(/\s+/).filter(Boolean);
          if (!words.length) continue;
          const lead = words.slice(0, NAZH_WORDS).join(" ").replace(/[.;:,]+$/, "");
          const text = `Сделал: пункт ${number} — ${lead}${words.length > NAZH_WORDS ? "…" : ""}`;
          doneMarks.set(li.parentElement, DONE_LIST_ATTRIBUTE);
          doneMarks.set(li, DONE_ITEM_ATTRIBUTE);
          wanted.push({ anchor: li, name: "done", place: "inside", target: li, before: nazhDoneBefore(li),
            buttons: [{ action: "done", label: "✓ сделал", line: { key: `done:${number}`, group: `done:${number}`, text } }] });
        }
        // Только доказанные соседи того же ответа, после обработанного списка.
        let continuation = false;
        const answer = nazhAnswer(head);
        for (const node of block) {
          if (node.tagName === "OL") { continuation = doneMarks.has(node); continue; }
          if (!continuation || !answer || nazhAnswer(node) !== answer) continue;
          if (/^(?:P|PRE|UL)$/.test(node.tagName) || (node.tagName === "DIV" && node.querySelector?.("pre"))) {
            doneMarks.set(node, DONE_CONT_ATTRIBUTE);
          } else continuation = false;
        }
      } else if (kind === "permit") {
        const task = nazhFirstLine(block);
        if (!task) continue;
        const group = `permit:${task}`;
        wanted.push({ anchor: head, name: "permit", place: "after", buttons: [
          { action: "yes", label: "разрешаю", line: { key: `${group}:yes`, group, text: `Разрешаю: ${task}` } },
          { action: "no", label: "нет", line: { key: `${group}:no`, group, text: `Не разрешаю: ${task}` } },
        ] });
      } else if (kind === "accept" || kind === "auto") {
        wanted.push({ anchor: head, name: kind, place: "after", buttons: [
          { action: kind, label: kind === "accept" ? "Включить" : "Вернуть", mode: kind },
        ] });
      } else if (kind === "report") {
        wanted.push({ anchor: block[block.length - 1] ?? head, name: "report", place: "after", buttons: [
          { action: "report", label: "отчёт", line: { key: "report", group: "send", text: "отчёт", send: true } },
        ] });
      }
    }
    // «→ в чат» (#7980): агент работает — кнопка неактивна; отсчёт отправки выключен —
    // «→ в поле»: строка без send, только впишу (подпись не врёт и до общего «выкл» WF119).
    const codes = nazhCodeBlocks();
    if (codes.length) {
      const busy = pageWorking();
      const off = sendDelayOff();
      const hint = busy ? "агент работает" : off ? "Отсчёт отправки выключен — только впишу в поле"
        : "Впишу в поле и отправлю после отсчёта (Esc или ещё клик — отмена); есть свой текст — только допишу";
      for (const { block, copy, text } of codes) {
        wanted.push({ anchor: block, name: "code", place: "inside", target: copy.parentElement, before: copy, buttons: [
          { action: "code", label: off ? "→ в поле" : "→ в чат", busy, hint, line: { key: `code:${text}`, group: "send", text, send: !off } },
        ] });
      }
    }
    const offer = nazhOfferNode();
    if (offer) {
      let anchor = offer;
      while (anchor.parentElement && /^(?:UL|OL|LI)$/.test(anchor.parentElement.tagName)) anchor = anchor.parentElement;
      if (nazhIsLi(anchor)) anchor = anchor.parentElement ?? anchor;
      wanted.push({ anchor, name: "chat", place: "after", buttons: [
        { action: "chat", label: "💬 Новый чат", line: { key: "chat", group: "send", text: NAZH_CHAT_TEXT, send: true } },
      ] });
    }
    return { picks, wanted, offer, doneMarks };
  };
  const nazhOffer = text => NAZH_OFFER_RES.some(re => {
    const hit = re.exec(text);
    return hit != null && !/(?:^|[^\p{L}])не\s+$/iu.test(text.slice(Math.max(0, hit.index - 6), hit.index));
  });
  // #7842: абзац последнего ответа законченного хода с предложением новый чат.
  const nazhOfferNode = () => {
    let working = false;
    try { working = document.querySelector(WORKING_SELECTOR) != null; } catch {}
    if (working || roamState.phase !== "idle") return null;
    let rows = null;
    try { rows = lastAnswerRows(); } catch { rows = null; }
    if (rows == null) {
      let answer = null;
      try { answer = lastAnswerNode(); } catch { answer = null; }
      if (!answer || !attnIsLast(answer)) return null;
      rows = [answer];
    }
    const paras = [];
    for (const row of rows) {
      let heads = [];
      let nodes = [];
      try {
        heads = [...row.querySelectorAll(ATTN_HEAD_SELECTOR)];
        nodes = [...row.querySelectorAll("p,li")];
      } catch { continue; }
      if (heads.some(node => CASHOUT_HANDOFF_HEAD_RE.test(node.textContent ?? ""))) return null;
      for (const node of nodes) {
        if (node.closest?.(`pre,code,blockquote,${ATTN_HEAD_SELECTOR},[${NAZH_BOX_ATTRIBUTE}]`)) continue;
        if (nazhIsLi(node) && node.querySelector?.("p")) continue;
        const text = nazhOwnText(node, "ul,ol,pre,code,blockquote");
        if (text && !NAZH_SERVICE_RE.test(text)) paras.push([node, text]);
      }
    }
    for (const [node, text] of paras.slice(-2).reverse()) if (nazhOffer(text)) return node;
    return null;
  };
  // Сосед выше, свои обёртки — мимо: две обёртки у одного узла не мешают друг другу.
  const nazhPrev = node => {
    let prev = node.previousElementSibling;
    while (prev?.hasAttribute?.(NAZH_BOX_ATTRIBUTE)) prev = prev.previousElementSibling;
    return prev ?? null;
  };
  const nazhPlaced = (slot, want) => slot.node.isConnected && (want.place === "after"
    ? nazhPrev(slot.node) === want.anchor
    : slot.node.parentNode === want.target && (want.name !== "done" || slot.node.nextSibling === want.before));
  // Место «✓ сделал» в пункте (WF176, #9198): под первой строкой — после первого абзаца
  // пункта, а у пункта без абзаца — перед первым блоком (код, подсписок); одни строки —
  // в конце. Своя кнопка в счёт не идёт: место то же, есть она уже или нет.
  const NAZH_DONE_BLOCK = /^(?:P|PRE|UL|OL|DIV|BLOCKQUOTE|TABLE|H[1-6])$/;
  const nazhDoneBefore = li => {
    const kids = [...(li.childNodes ?? [])].filter(node => !(node.nodeType === 1 && node.hasAttribute?.(NAZH_BUTTON_ATTRIBUTE)));
    const first = kids.find(node => node.nodeType === 1 || String(node.textContent ?? "").trim());
    if (first?.nodeType === 1 && first.tagName === "P") return kids[kids.indexOf(first) + 1] ?? null;
    return kids.find(node => node.nodeType === 1 && NAZH_DONE_BLOCK.test(node.tagName)) ?? null;
  };
  const nazhButtonMake = spec => {
    const button = document.createElement("button");
    button.setAttribute("type", "button");
    button.setAttribute(NAZH_BUTTON_ATTRIBUTE, spec.action);
    button.setAttribute(NAZH_LABEL_ATTRIBUTE, spec.label);
    button.setAttribute("aria-label", spec.label);
    return button;
  };
  const nazhMake = want => {
    const buttons = want.buttons.map(nazhButtonMake);
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    if (want.place === "inside") {
      try { want.target.insertBefore(buttons[0], want.before); } catch { return null; }
      return { anchor: want.anchor, name: want.name, node: buttons[0], buttons, chat };
    }
    const box = document.createElement("div");
    box.setAttribute(NAZH_BOX_ATTRIBUTE, want.name);
    for (const button of buttons) box.appendChild(button);
    if (!want.anchor.parentNode) return null;
    try { want.anchor.parentNode.insertBefore(box, want.anchor.nextElementSibling); } catch { return null; }
    return { anchor: want.anchor, name: want.name, node: box, buttons, chat };
  };
  const nazhSet = (node, name, value) => {
    if (value == null) { if (node.hasAttribute(name)) node.removeAttribute(name); return; }
    if (node.getAttribute(name) !== value) node.setAttribute(name, value);
  };
  const nazhLabel = spec => {
    if (spec.mode && nazhState.modeBusy === spec.mode) return spec.mode === "accept" ? "Включаю…" : "Возвращаю…";
    if (spec.line?.send && nazhState.armed && nazhState.lines[0]?.key === spec.line.key) return `${spec.label} · ${nazhState.left}`;
    return spec.label;
  };
  // Метки строк «⚪» и кнопки — ровно на том, что сейчас в ленте; старое снято.
  const nazhPaint = () => {
    const { picks, wanted, offer, doneMarks } = nazhScan();
    for (const node of nazhDoneNodes) {
      if (!doneMarks.has(node)) {
        for (const attr of [DONE_LIST_ATTRIBUTE, DONE_ITEM_ATTRIBUTE, DONE_CONT_ATTRIBUTE]) nazhSet(node, attr, null);
        nazhDoneNodes.delete(node);
      }
    }
    for (const [node, attr] of doneMarks) { nazhSet(node, attr, ""); nazhDoneNodes.add(node); }
    const lines = new Map();
    for (const { node, line } of picks) {
      nazhSet(node, NAZH_PICK_ATTRIBUTE, nazhHas(line.key) ? "on" : "");
      lines.set(node, line);
    }
    for (const node of nazhState.picks.keys()) {
      if (!lines.has(node)) { try { node.removeAttribute(NAZH_PICK_ATTRIBUTE); } catch {} }
    }
    nazhState.picks = lines;
    const old = [...nazhState.slots];
    const next = [];
    const info = new Map();
    for (const want of wanted) {
      let slot = old.find(item => item.anchor === want.anchor && item.name === want.name && nazhPlaced(item, want)) ?? null;
      if (slot) old.splice(old.indexOf(slot), 1);
      else slot = nazhMake(want);
      if (!slot) continue;
      next.push(slot);
      want.buttons.forEach((spec, index) => {
        const button = slot.buttons[index];
        if (!button) return;
        info.set(button, { ...spec, chat: slot.chat });
        const label = nazhLabel(spec);
        nazhSet(button, NAZH_LABEL_ATTRIBUTE, label);
        nazhSet(button, "aria-label", label);
        nazhSet(button, NAZH_ON_ATTRIBUTE, spec.line && nazhHas(spec.line.key) ? "" : null);
        nazhSet(button, "aria-disabled", (spec.mode && nazhState.modeBusy) || spec.busy ? "true" : null);
        nazhSet(button, "title", spec.hint ?? null);
      });
    }
    for (const slot of old) { try { slot.node.remove(); } catch {} }
    nazhState.slots = next;
    nazhState.info = info;
    if (offer && offer !== nazhState.offer) nazhState.offers += 1;
    nazhState.offer = offer;
  };
  const nazhStopTimer = () => { if (nazhState.timer) { clearInterval(nazhState.timer); nazhState.timer = 0; } };
  const nazhDisarm = skip => {
    nazhState.armed = false;
    nazhState.left = 0;
    nazhState.until = 0;
    nazhState.editor = null;
    if (skip) nazhState.skip = skip;
    // Отсчёт дотикал, а отправить нечем (#7980): сказать словами, текст остаётся в поле.
    if (skip === "нет кнопки отправки") { try { newWindowNote("Нет кнопки отправки — текст в поле, отправь сам"); } catch {} }
    nazhStopTimer();
  };
  const nazhReset = () => {
    nazhDisarm("");
    nazhState.lines = [];
    nazhState.base = "";
    nazhState.expect = null;
  };
  const nazhWatch = () => {
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    if (chat !== nazhState.chat) { nazhState.chat = chat; nazhReset(); nazhDoneClear(); }
    let working = false;
    try { working = document.querySelector(WORKING_SELECTOR) != null; } catch {}
    if (working && !nazhState.working) nazhReset();
    nazhState.working = working;
  };
  const nazhJoined = (lines = nazhState.lines) => lines.map((line, at) => (at ? (line.nl || lines[at - 1].nl ? "\n" : NAZH_SEP) : "") + line.text).join("");
  // Между своим текстом Элвиса и хвостом: пробел, а у строки с nl — перевод строки.
  const nazhGlue = (lines = nazhState.lines) => (lines[0]?.nl ? "\n" : " ");
  // Вписать или снять строку. Поле трогали после нас (или первое нажатие):
  // свой текст — всё, кроме хвоста из вписанных строк; хвоста нет — строки
  // забыты, поле главнее (как sayToggle).
  const nazhToggle = (line, t = now()) => {
    if (shotBlocked()) return false;
    if (line?.key?.startsWith("code:") && pageWorking()) return false;
    nazhWatch();
    const editor = sayEditor();
    if (!editor || !line?.text) return false;
    const delayed = nazhState.codeDelay;
    if (delayed?.key === line.key && delayed.editor === editor && delayed.chat === myChatId() &&
        sendDelayState.counting && rawText(editor) === delayed.text) {
      sendDelayStop("cancelled", "code-repeat");
      sayWrite(editor, "");
      nazhState.codeDelay = null;
      return true;
    }
    // Сверка — через sayNorm: перевод строки ProseMirror отдаёт абзацем («\n\n»), пробелы по краям — тоже не текст.
    const current = sayNorm(rawText(editor));
    if (current !== sayNorm(nazhState.expect)) {
      const joined = sayNorm(nazhJoined());
      if (joined && (current === joined || current.endsWith(` ${joined}`))) {
        nazhState.base = current === joined ? "" : current.slice(0, -joined.length - 1);
      } else { nazhState.lines = []; nazhState.base = current; }
    }
    const before = nazhJoined();
    const glueBefore = nazhGlue();
    const at = nazhState.lines.findIndex(item => item.key === line.key);
    if (at >= 0) nazhState.lines.splice(at, 1);
    else {
      const same = nazhState.lines.findIndex(item => item.group === line.group);
      if (same >= 0) nazhState.lines.splice(same, 1, line);
      else nazhState.lines.push(line);
    }
    const after = nazhJoined();
    const glue = nazhGlue();
    const text = nazhState.base && after ? `${nazhState.base}${glue}${after}` : nazhState.base || after;
    if (!nazhState.base) sayWrite(editor, text);
    else sayWriteTail(editor, before ? `${glueBefore}${before}` : "", after ? `${glue}${after}` : "");
    nazhState.expect = text;
    nazhState.skip = "";
    // Слова «Скажи — и сделаю» ждали отправки — в поле теперь не только они.
    if (sayState.armed) { sayDisarm("свой текст в поле"); sayPaint(); }
    if (!nazhState.base && nazhState.lines.length === 1 && nazhState.lines[0].send) {
      nazhState.armed = true;
      nazhState.editor = editor;
      nazhState.until = t + NAZH_WAIT_MS;
      nazhState.left = Math.ceil(NAZH_WAIT_MS / 1000);
      if (!nazhState.timer) nazhState.timer = setInterval(() => { try { nazhTick(now()); } catch {} }, NAZH_STEP_MS);
    } else nazhDisarm(nazhState.base && line.send && at < 0 ? "свой текст в поле" : "");
    nazhPaint();
    return true;
  };
  const nazhSend = () => {
    const line = nazhState.lines[0];
    const choice = line?.key?.startsWith("code:") ? { key: line.key, editor: nazhState.editor, chat: myChatId(), text: rawText(nazhState.editor) } : null;
    const sent = phraseSend(nazhState, nazhState.expect, nazhDisarm, nazhReset);
    if (sent && sendDelayState.counting) nazhState.codeDelay = choice;
    return sent;
  };
  const nazhTick = t => {
    if (!themable || !state.alive) return;
    nazhWatch();
    phraseCountdown(nazhState, nazhState.expect, nazhDisarm, nazhSend, t);
    nazhPaint();
    // «На картинке — …» (раздел 12д¹, #7860): метки слов — тем же тиком.
    try { mentionPaint(); } catch {}
    // Фразы «Ждёт тебя» (раздел 12с², #10910) — тем же тиком.
    try { waitPhrasePaint(); } catch {}
  };
  // Ожидание опросом (меню режима открывается не сразу); экземпляр ушёл — null.
  const nazhWait = (check, ms, live = () => state.alive) => new Promise(resolve => {
    const until = now() + ms;
    const step = () => {
      if (!live() || now() >= until) { resolve(null); return; }
      let hit = null;
      try { hit = check(); } catch { hit = null; }
      if (hit || now() >= until) { resolve(hit ?? null); return; }
      const id = setTimeout(() => { nazhState.timers.delete(id); step(); }, NAZH_POLL_MS);
      nazhState.timers.add(id);
    };
    step();
  });
  // Переключатель режима под полем: кнопка нижней строки, чей текст — режим
  // (CHIN_MODES; textContent полный и в узком окне, коротко там только ::after).
  const nazhModeButton = () => {
    try {
      const buttons = [...document.querySelectorAll(`${CHIN_SELECTOR} button`)].filter(button => chinModeShort(chinText(button)));
      return buttons.length === 1 ? buttons[0] : null;
    } catch { return null; }
  };
  // #7973: право ровно одной коррекции только от собственной ручной кнопки.
  // Содержимое ответа, начальный Ac и modeBefore не означают согласия Элвиса.
  const modeGuard = { token: 0, chat: null, button: null, armed: false, autoAt: null, quietUntil: 0, attempts: 0, result: "off" };
  const modeGuardDrop = () => {
    modeGuard.token += 1; modeGuard.armed = false; modeGuard.autoAt = null;
    modeGuard.chat = null; modeGuard.button = null; modeGuard.quietUntil = 0;
  };
  const modeMenus = () => [...document.querySelectorAll('[role="menu"], [role="listbox"]')];
  const modeSwitch = async (goal, chat, button, token) => {
    const until = now() + NAZH_MENU_MS * 2;
    const live = () => state.alive && modeGuard.token === token && myChatId() === chat
      && /^local_[A-Za-z0-9_-]+$/.test(chat || "") && roamState.phase === "idle"
      && button?.isConnected && nazhModeButton() === button && now() < until;
    if (!live() || modeMenus().length || newWindowMenuItems().length) return "gone";
    const before = chinModeShort(chinText(button));
    if (before === goal) return "already";
    pressLikeMouse(button);
    const find = () => {
      if (!live() || chinModeShort(chinText(button)) !== before) return null;
      const menus = modeMenus();
      if (menus.length !== 1) return null;
      const items = newWindowMenuItems().filter(node => menus[0].contains(node) && NAZH_MODE_ITEM[goal]?.test(newWindowLabel(node)));
      return items.length === 1 ? items[0] : null;
    };
    const item = await nazhWait(find, NAZH_MENU_MS, live);
    if (!live()) return "gone";
    if (!item) { newWindowEscape(); return "no-item"; }
    if (!item.isConnected || find() !== item) return "gone";
    pressLikeMouse(item);
    const ok = await nazhWait(() => chinModeShort(chinText(button)) === goal ? true : null,
      Math.max(0, until - now()), live);
    if (!live()) return "gone";
    if (!ok) { newWindowEscape(); return "not-set"; }
    return "ok";
  };
  const onModeInteraction = event => {
    if (event.isTrusted !== true || (!modeGuard.armed && !nazhState.modeBusy)) return;
    const own = event.target?.closest?.(`[${NAZH_BUTTON_ATTRIBUTE}]`);
    // Нажатие уже занятой ручной кнопки не делает второго выбора. Но начатая
    // коррекция отменяется ЛЮБЫМ вводом: попытка уже потреблена.
    if (own && nazhState.modeBusy && nazhState.modeBusy !== "repair") return;
    if (nazhState.modeBusy) { modeGuardDrop(); return; }
    const modeButton = event.target?.closest?.(`${CHIN_SELECTOR} button`);
    const choosing = (own && nazhState.info.get(own)?.mode)
      || (modeButton && chinModeShort(chinText(modeButton)))
      || event.target?.closest?.('[role="menu"], [role="listbox"], [role^="menuitem"]')
      || (event.type === "keydown" && event.key === "Tab" && event.shiftKey);
    if (choosing) { modeGuardDrop(); return; }
    // Обычный набор, Enter и касание поля — пауза, не новый выбор режима.
    modeGuard.autoAt = null;
    modeGuard.quietUntil = now() + 2000;
  };
  const modeGuardTick = t => {
    if (!modeGuard.armed || nazhState.modeBusy) return;
    const button = nazhModeButton();
    if (!state.alive || myChatId() !== modeGuard.chat || roamState.phase !== "idle"
      || !button || button !== modeGuard.button || !button.isConnected
      || button.closest?.(COLLAPSED_BLOCK_SELECTOR) || modeMenus().length || newWindowMenuItems().length) { modeGuardDrop(); return; }
    const mode = chinModeShort(chinText(button));
    if (mode === "Ac") { modeGuard.autoAt = null; return; }
    if (mode !== "Au") { modeGuardDrop(); return; }
    if (t < modeGuard.quietUntil) { modeGuard.autoAt = null; return; }
    if (modeGuard.autoAt === null) { modeGuard.autoAt = t; return; }
    if (t - modeGuard.autoAt < 1000) return;
    // Потребляем попытку ДО первого клика; отказ и следующий сброс не повторяем.
    modeGuard.armed = false; modeGuard.attempts += 1; modeGuard.result = "pending";
    nazhState.modeBusy = "repair";
    const token = modeGuard.token, chat = modeGuard.chat;
    modeSwitch("Ac", chat, button, token).then(result => { modeGuard.result = result; })
      .catch(() => { modeGuard.result = "fail"; }).finally(() => {
        nazhState.modeBusy = "";
        if (state.alive) nazhPaint();
      });
  };
  track(modeGuardDrop);

  const nazhModeFail = text => {
    nazhState.modeFails += 1;
    nazhState.modeNote = text;
    try { newWindowNote(text); } catch {}
    return "fail";
  };
  // «Включить» / «Вернуть»: открыть меню режима, нажать пункт, дождаться новой
  // подписи. Жмём только в своём чате и не во время обхода Авто-Allow (12е).
  // Прежний режим до «Включить» помним по чату, «Вернуть» — к нему (Ask или
  // Auto; прочее и незнакомое — Auto).
  const nazhMode = async (which, chat = null, trusted = false) => {
    if (nazhState.modeBusy) return "busy";
    if (roamState.phase !== "idle") return nazhModeFail("Окно сейчас в другом чате (Авто-Allow) — нажми, когда вернётся");
    let mine = null;
    try { mine = myChatId(); } catch { mine = null; }
    if (chat !== mine || !/^local_[A-Za-z0-9_-]+$/.test(mine || "")) return nazhModeFail("Это кнопка другого чата — режим не трогаю");
    const button = nazhModeButton();
    if (!button) return nazhModeFail("Не нашёл переключатель режима под полем");
    if (button.closest?.(COLLAPSED_BLOCK_SELECTOR)) return nazhModeFail("Разверни поле ввода — переключатель режима спрятан");
    modeGuardDrop();
    const token = modeGuard.token;
    const key = mine;
    const was = chinModeShort(chinText(button));
    let goal = "Ac";
    if (which === "accept") { if (was !== "Ac") nazhState.modeBefore.set(key, was); }
    else goal = nazhState.modeBefore.get(key) === "As" ? "As" : "Au";
    const done = () => {
      nazhState.modes += 1;
      if (which === "accept" && !nazhHas("mode:accept")) {
        try { nazhToggle({ key: "mode:accept", group: "mode", text: NAZH_ACCEPT_TEXT }); } catch {}
      }
      if (which === "auto") nazhState.modeBefore.delete(key);
      if (which === "accept" && trusted && modeGuard.token === token && myChatId() === mine
        && nazhModeButton() === button && chinModeShort(chinText(button)) === "Ac" && roamState.phase === "idle") {
        Object.assign(modeGuard, { armed: true, chat: mine, button, autoAt: null, result: "armed" });
      }
    };
    if (was === goal) {
      nazhState.modeNote = `Режим уже ${NAZH_MODE_NAME[goal]}`;
      try { newWindowNote(nazhState.modeNote); } catch {}
      done();
      return "already";
    }
    nazhState.modeBusy = which;
    nazhPaint();
    try {
      const result = await modeSwitch(goal, mine, button, token);
      if (!state.alive || modeGuard.token !== token || myChatId() !== mine || roamState.phase !== "idle") return "gone";
      if (result === "no-item") return nazhModeFail(`Не нашёл «${NAZH_MODE_NAME[goal]}» в меню режима`);
      if (result !== "ok" && result !== "already") return nazhModeFail(`Режим не переключился на ${NAZH_MODE_NAME[goal]}`);
      nazhState.modeNote = "";
      done();
      return "ok";
    } finally {
      nazhState.modeBusy = "";
      if (state.alive) { try { nazhPaint(); } catch {} }
    }
  };
  // Нажатие по кнопке и строке «⚪»: фокус остаётся в поле, текст не выделяется.
  const onNazhPress = event => {
    if (!event?.target?.closest?.(`[${NAZH_BUTTON_ATTRIBUTE}],li[${NAZH_PICK_ATTRIBUTE}]`)) return;
    event.preventDefault?.();
  };
  const onNazhClick = event => {
    if (event?.isTrusted !== true) return;
    const target = event?.target;
    const button = target?.closest?.(`[${NAZH_BUTTON_ATTRIBUTE}]`) ?? null;
    const pick = button ? null : target?.closest?.(`li[${NAZH_PICK_ATTRIBUTE}]`) ?? null;
    if (!button && !pick) return;
    // Ссылка внутри строки «⚪» открывается как обычно.
    if (pick && target.closest?.("a")) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    if (!state.alive || Number(event.detail) > 1) return;
    const spec = button ? nazhState.info.get(button) : { line: nazhState.picks.get(pick) };
    if (!spec?.line && !spec?.mode) return;
    if (button?.getAttribute("aria-disabled") === "true") return;
    nazhState.clicks += 1;
    if (spec.mode) { nazhMode(spec.mode, spec.chat ?? null, true).catch(() => {}); return; }
    try { nazhToggle(spec.line); } catch {}
  };
  // Элвис сам печатает в поле — отсчёт гаснет, строки остаются.
  const onNazhKey = event => {
    if (event?.isTrusted === false || !nazhState.armed) return;
    const target = event.target;
    if (target && (state.editor?.contains?.(target) || state.composerBlock?.contains?.(target))) { nazhDisarm("печатает"); nazhPaint(); }
  };
  // Сироты прошлой установки — до первой разметки.
  try {
    for (const node of document.querySelectorAll(`[${NAZH_BOX_ATTRIBUTE}],[${NAZH_BUTTON_ATTRIBUTE}]`)) node.remove();
    for (const attr of [NAZH_PICK_ATTRIBUTE, DONE_LIST_ATTRIBUTE, DONE_ITEM_ATTRIBUTE, DONE_CONT_ATTRIBUTE]) {
      for (const node of document.querySelectorAll(`[${attr}]`)) node.removeAttribute(attr);
    }
  } catch {}
  track(() => {
    nazhStopTimer();
    nazhDoneClear();
    for (const id of nazhState.timers) clearTimeout(id);
    nazhState.timers.clear();
    for (const slot of nazhState.slots) { try { slot.node.remove(); } catch {} }
    for (const node of nazhState.picks.keys()) { try { node.removeAttribute(NAZH_PICK_ATTRIBUTE); } catch {} }
    nazhState.slots = [];
    nazhState.info.clear();
    nazhState.picks.clear();
  });
  // Нажималки (#7843, #7842, раздел 12с): вписанные строки по порядку, идёт
  // ли отсчёт «отчёт»/«💬 Новый чат» и сколько секунд, сколько отправил и
  // нажатий, строк «⚪» и кнопок в ленте, стоит ли «💬 Новый чат» под
  // предложением (offers — сколько раз вставал), режим: переключений,
  // отказов, последняя плашка, что сейчас переключается.
  statusPart("nazh", () => ({
    lines: nazhState.lines.map(line => line.text), armed: nazhState.armed, left: nazhState.left,
    sends: nazhState.sends, clicks: nazhState.clicks, skip: nazhState.skip || null,
    picks: nazhState.picks.size, buttons: nazhState.info.size, offer: nazhState.offer != null, offers: nazhState.offers,
    modes: nazhState.modes, modeFails: nazhState.modeFails, modeNote: nazhState.modeNote || null, modeBusy: nazhState.modeBusy || null,
  }));
  HATCH && Object.assign(HATCH, { modeGuard, modeGuardTick, nazhTick, nazhToggle, nazhState, nazhOffer });

