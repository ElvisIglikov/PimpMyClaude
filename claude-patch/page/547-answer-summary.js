  // ---- 12ф³. Сводка свёрнутого ответа — первый шаг «Развернуть ответ» (#9810) -------
  // Слово Элвиса 11.10 ~20:57: «Я нажимаю развернуть ответ. И мне показывается короткая сводка. И там
  // есть внизу подробнее. И потом уже показывается твой вот этот ответ полный… Защити меня от лишней
  // информации». У свёрнутого длинного ответа (раздел 12ф) «▸ Развернуть ответ» открывает не весь
  // ответ, а сводку: свой узел сразу под кнопкой, вид — как у сути сообщения (12ф²: черта слева, серая
  // подложка), внизу тихое «кратко от Пимпа»/«начало ответа» (#11174) и «Подробнее ▾». Нажал на сводку (без выделения), Enter
  // или пробел на «Подробнее» — весь ответ; «▾ Свернуть ответ» над сводкой или Esc на «Подробнее» —
  // снова свёрнут. Сводку даёт Пимп той же ручкой, что суть сообщения (POST /summary, контракт #9806,
  // Claude на этом Маке): текст — то, что прячет кнопка (всё после первого абзаца), hash — sha1 его.
  // Спрашивается при нажатии «Развернуть» у дописанного ответа (не заранее у каждого свёрнутого — подписка
  // тратится только на раскрытые, гейт WF266); пока сути нет — первые предложения (userFoldLead 12ф²),
  // пришла — встаёт на место. Суть нейронки (ai) — в общем кэше 12ф², второй раз не спрашиваем.
  // Состояние шага — в foldState.long раздела 12ф ("brief"); здесь — только сводка и её узел.
  //
  // «Ждёт тебя» — самым верхом (#11000, слово Элвиса 28.10: «все места, которые от меня требовались, были сразу
  // сверху показаны… чтоб я ни один процесс не тормозил»). У свёрнутого ответа (и на шаге сводки) раздел «Ждёт тебя»
  // («сделай») прятался под кнопкой, а сверху стояли первый абзац и сводка. Теперь, если такой раздел есть в
  // спрятанном, его копия — свой узел НАД первым абзацем ответа: заголовок и пункты (у пункта-свёртки — его
  // заголовок, тело свёртки не копируется). Нажал — весь ответ. Развернул целиком — копии нет (виден сам раздел).
  // Раздел — как у 12с² (WAIT_HEAD_RE): заголовок или абзац, текст которого начинается с «Ждёт тебя» или «сделай»
  // (перед ним — значки и имя: «👾 Элвис, сделай»), и всё до следующего заголовка или абзаца-подзаголовка.
  const ANSWER_SUM_ATTRIBUTE = "data-myclaude-asum";
  const ANSWER_SUM_TEXT_ATTRIBUTE = "data-myclaude-asum-text";
  const ANSWER_SUM_BAR_ATTRIBUTE = "data-myclaude-asum-bar";
  const ANSWER_SUM_KIND_ATTRIBUTE = "data-myclaude-asum-kind";
  const ANSWER_SUM_LABEL_ATTRIBUTE = "data-myclaude-asum-label";
  const ANSWER_WAITS_ATTRIBUTE = "data-myclaude-asum-waits";
  const ANSWER_WAITS_HEAD_ATTRIBUTE = "data-myclaude-asum-waits-head";
  const ANSWER_WAITS_DO_RE = /^[^\p{L}\p{N}]*(?:\p{L}+[,\s]+)?сделай(?![\p{L}])/iu;
  const ANSWER_WAITS_LINES = 12;
  const ANSWER_WAITS_LINE_MAX = 240;
  // key — ключ ответа из foldState.long; asked — вопросы Пимпу по хэшу.
  const answerSum = { entries: new Map(), asked: new Map(), waitsPlaced: new Set() };

  // Текст под кнопкой: узлы ответа после неё, без своих заголовков и сырых тегов <details>.
  const answerSumText = nodes => nodes.filter(node => !foldRaw(node)).map(node => userFoldText(node)).filter(Boolean).join("\n").slice(0, USER_FOLD_TEXT_MAX);
  // Раздел «Ждёт тебя» / «сделай» среди узлов ответа → строки копии (первая — заголовок) или [].
  const answerWaitsHead = node => {
    let raw = "";
    try { raw = String(node?.textContent ?? ""); } catch { return false; }
    if (raw.length > WAIT_HEAD_MAX || foldRaw(node)) return false;
    try { if (!node.matches?.(`${ATTN_HEAD_SELECTOR},p`)) return false; } catch { return false; }
    const text = sayNorm(raw);
    return WAIT_HEAD_RE.test(text) || ANSWER_WAITS_DO_RE.test(text);
  };
  // #11478: раздел-свёртка `<summary><b>❗ ЖДЁТ ТЕБЯ — N (🔴 K)</b></summary>` — сырой <p> открытия, чья подпись (своя
  // или следующего <summary>) — заголовок раздела; → { title, skip } (skip — сырых <p> головы) или null.
  const answerWaitsFold = (nodes, index) => {
    const raw = foldRaw(nodes[index]);
    if (raw?.kind !== "open") return null;
    const next = raw.title == null ? foldRaw(nodes[index + 1]) : null;
    const title = raw.title ?? (next?.kind === "summary" ? next.title : null);
    if (title == null) return null;
    const text = foldTitle(title);
    return text.length <= WAIT_HEAD_MAX && (WAIT_HEAD_RE.test(text) || ANSWER_WAITS_DO_RE.test(text)) ? { title: text, skip: next ? 2 : 1 } : null;
  };
  // #11680: теги краёв (#11651) — строки внутри абзаца или плотного пункта, `<li>пункт<br></details></li>`; без них
  // `</details>` раздела в последнем пункте списка не закрывал раздел, и в копию шли пункты следующих разделов.
  const answerWaitsEdges = node => {
    let list = [];
    try { list = node.matches?.(FOLD_LINE_SELECTOR) ? [node, ...node.querySelectorAll(FOLD_LINE_SELECTOR)] : [...node.querySelectorAll(FOLD_LINE_SELECTOR)]; } catch { list = []; }
    const out = { head: [], tail: [], hide: new Set() };
    for (const p of list) {
      const edges = foldEdges(p);
      if (!edges) continue;
      out.head.push(...edges.head);
      out.tail.push(...edges.tail);
      for (const edge of [...edges.head, ...edges.tail]) edge.hide.forEach(part => out.hide.add(part));
    }
    return out;
  };
  // Текст пункта без строк-тегов краёв (пока 12ф их не спрятал, они ещё в textContent).
  const answerWaitsText = (node, hide) => {
    if (!hide.size) return sayNorm(node.textContent);
    const walk = part => hide.has(part) ? "" : part.nodeType === 3 ? String(part.nodeValue ?? "") : [...(part.childNodes ?? [])].map(walk).join("");
    return sayNorm(walk(node));
  };
  const answerWaitsOf = nodes => {
    const start = nodes.findIndex((node, index) => answerWaitsHead(node) || answerWaitsFold(nodes, index));
    if (start < 0) return [];
    // У раздела-свёртки свой уровень: пункты — на 2, текст — на 1, её </details> — конец раздела.
    const fold = answerWaitsFold(nodes, start);
    const lines = [fold?.title ?? sayNorm(nodes[start].textContent)];
    const base = fold ? 1 : 0;
    let depth = base;
    // Тег (целый абзац или строка края) → false, когда раздел кончился.
    const step = raw => {
      if (raw.kind === "open") {
        depth += 1;
        if (depth === base + 1 && raw.title != null) lines.push(foldTitle(raw.title));
      } else if (raw.kind === "summary") {
        if (depth === base + 1) lines.push(foldTitle(raw.title));
      } else if (raw.kind === "close") {
        depth = Math.max(0, depth - 1);
        if (depth < base) return false;
      }
      return true;
    };
    for (const node of nodes.slice(start + (fold?.skip ?? 1))) {
      if (lines.length >= ANSWER_WAITS_LINES) break;
      const raw = foldRaw(node);
      if (!raw && !base && depth === 0) {
        try { if (node.matches?.(ATTN_HEAD_SELECTOR) || node.querySelector?.(ATTN_HEAD_SELECTOR) || waitPseudoHead(node)) break; } catch { break; }
      }
      if (raw) {
        if (!step(raw)) break;
        continue;
      }
      const edges = answerWaitsEdges(node);
      if (!edges.head.every(step)) break;
      if (depth === base) {
        let items = [];
        try { items = node.tagName === "UL" || node.tagName === "OL" ? [...node.querySelectorAll("li")] : [node]; } catch { items = [node]; }
        for (const item of items) {
          const text = answerWaitsText(item, edges.hide);
          if (text) lines.push(text);
        }
      }
      if (!edges.tail.every(step)) break;
    }
    return lines.slice(0, ANSWER_WAITS_LINES).map(line => line.length > ANSWER_WAITS_LINE_MAX ? `${line.slice(0, ANSWER_WAITS_LINE_MAX - 1)}…` : line);
  };
  const answerWaitsMake = () => {
    const own = document.createElement("div");
    own.setAttribute(ANSWER_WAITS_ATTRIBUTE, "");
    own.setAttribute("role", "button");
    own.setAttribute("tabindex", "0");
    own.setAttribute("aria-label", "Ждёт тебя — показать весь ответ");
    return own;
  };
  const answerWaitsPaint = entry => {
    const node = entry.waitsNode;
    const shown = [...(node.children ?? [])].map(line => line.textContent);
    if (shown.length === entry.waits.length && shown.every((line, index) => line === entry.waits[index])) return;
    while (node.firstChild) node.firstChild.remove();
    entry.waits.forEach((line, index) => {
      const row = document.createElement("div");
      if (index === 0) row.setAttribute(ANSWER_WAITS_HEAD_ATTRIBUTE, "");
      row.textContent = line;
      node.appendChild(row);
    });
  };
  // Копия «Ждёт тебя» над первым абзацем (тот стоит прямо перед кнопкой 12ф); нечего или негде — снята.
  const answerWaitsPlace = (entry, whole) => {
    const first = whole.previousElementSibling;
    if (!entry.waits.length || !first || first.parentNode !== whole.parentNode) {
      if (entry.waitsNode?.parentNode) { try { entry.waitsNode.remove(); } catch {} }
      return;
    }
    entry.waitsNode ??= answerWaitsMake();
    answerWaitsPaint(entry);
    if (first.previousElementSibling !== entry.waitsNode) {
      try { first.parentNode.insertBefore(entry.waitsNode, first); } catch { return; }
    }
    answerSum.waitsPlaced.add(entry.key);
  };
  const answerSumMake = () => {
    const own = document.createElement("div");
    own.setAttribute(ANSWER_SUM_ATTRIBUTE, "");
    const text = document.createElement("div");
    text.setAttribute(ANSWER_SUM_TEXT_ATTRIBUTE, "");
    const bar = document.createElement("div");
    bar.setAttribute(ANSWER_SUM_BAR_ATTRIBUTE, "");
    bar.setAttribute(ANSWER_SUM_LABEL_ATTRIBUTE, "Подробнее ▾");
    bar.setAttribute("role", "button");
    bar.setAttribute("tabindex", "0");
    bar.setAttribute("aria-label", "Показать весь ответ");
    own.appendChild(text);
    own.appendChild(bar);
    return own;
  };
  const answerSumPaint = entry => {
    const text = entry.node.firstChild;
    if (text.textContent !== entry.summary) text.textContent = entry.summary;
    foldSet(entry.node.lastChild, ANSWER_SUM_KIND_ATTRIBUTE, entry.kind === "ai" ? "кратко от Пимпа" : "начало ответа");
  };

  // Ответ Пимпа — как у 12ф²: 200 — суть (ai — в кэш), 202 — переспрос; остальное — остаётся начало.
  const answerSumAsk = (hash, text, round = 0) => {
    if (typeof fetch !== "function") return;
    const asked = { at: Date.now(), pending: true, round, timer: 0 };
    answerSum.asked.set(hash, asked);
    const stop = () => { asked.pending = false; };
    let sent = null;
    try {
      sent = fetch(`http://127.0.0.1:${HTML_CHROME_PORT}/summary`, {
        method: "POST", mode: "cors", credentials: "omit", cache: "no-store", body: JSON.stringify({ hash, text }),
      });
    } catch { sent = null; }
    if (!sent || typeof sent.then !== "function") { stop(); return; }
    sent.then(reply => {
      if (!state.alive || answerSum.asked.get(hash) !== asked) return null;
      if (reply?.status === 202 && round < USER_FOLD_RETRIES) {
        asked.timer = setTimeout(() => {
          if (state.alive && answerSum.asked.get(hash) === asked) answerSumAsk(hash, text, round + 1);
        }, USER_FOLD_RETRY_MS);
        return null;
      }
      stop();
      return reply?.status === 200 ? reply.json() : null;
    }).then(data => {
      if (!data || !state.alive || answerSum.asked.get(hash) !== asked) return;
      const summary = typeof data.summary === "string" ? data.summary.trim() : "";
      if (data.hash !== hash || !summary || (data.kind !== "lead" && data.kind !== "ai")) return;
      if (data.kind === "ai") userFoldRemember(hash, summary, Date.now());
      asked.summary = summary;
      asked.kind = data.kind;
      for (const entry of answerSum.entries.values()) {
        if (entry.hash !== hash) continue;
        entry.summary = summary;
        entry.kind = data.kind;
        answerSumPaint(entry);
      }
    }, stop);
  };

  // Из прохода 12ф для свёрнутого ответа или его сводки: текст и хэш (пересчёт — когда сменились узлы
  // или ответ ещё пишется), вопрос Пимпу (дописанному), узел сводки под кнопкой на шаге brief.
  // Возвращает узел сводки, когда он на месте, иначе null.
  const answerSumPlace = (whole, key, brief, live) => {
    const nodes = [];
    for (let node = whole.nextElementSibling; node; node = node.nextElementSibling) if (!foldOwn(node)) nodes.push(node);
    let entry = answerSum.entries.get(key);
    if (!entry) {
      entry = { key, node: answerSumMake(), nodes: [], hash: "", text: "", summary: "", kind: "lead", waits: [], waitsNode: null };
      answerSum.entries.set(key, entry);
    }
    const writing = live();
    if (writing || nodes.length !== entry.nodes.length || nodes.some((node, index) => node !== entry.nodes[index])) {
      entry.nodes = nodes;
      entry.waits = answerWaitsOf(nodes);
      const text = answerSumText(nodes);
      if (text !== entry.text) {
        entry.text = text;
        entry.hash = text ? userFoldSha1(text) : "";
        const cached = entry.hash ? userFoldStore().get(entry.hash) : null;
        const asked = answerSum.asked.get(entry.hash);
        entry.summary = cached?.s ?? asked?.summary ?? userFoldLead(text);
        entry.kind = cached ? "ai" : asked?.kind ?? "lead";
      }
    }
    // Только на шаге сводки (brief) — см. шапку раздела.
    if (entry.hash && !writing && brief && entry.kind !== "ai") {
      const asked = answerSum.asked.get(entry.hash);
      if (!asked || (!asked.pending && !asked.summary && Date.now() - asked.at >= USER_FOLD_AGAIN_MS)) answerSumAsk(entry.hash, entry.text);
    }
    answerSumPaint(entry);
    answerWaitsPlace(entry, whole);
    if (!brief || !entry.text) {
      if (entry.node.parentNode) { try { entry.node.remove(); } catch {} }
      return null;
    }
    if (whole.nextElementSibling !== entry.node) {
      try { whole.parentNode.insertBefore(entry.node, whole.nextSibling); } catch { return null; }
    }
    return entry.node;
  };
  // Есть ли что показать сводкой (иначе «Развернуть ответ» сразу открывает весь ответ).
  const answerSumReady = key => Boolean(answerSum.entries.get(key)?.text);
  // Конец прохода 12ф: сводки не на шаге brief — из ленты; развёрнутые ответы забыты.
  const answerSumSweep = briefs => {
    for (const [key, entry] of answerSum.entries) {
      if (!briefs.has(key) && entry.node.parentNode) { try { entry.node.remove(); } catch {} }
      if (!answerSum.waitsPlaced.has(key) && entry.waitsNode?.parentNode) { try { entry.waitsNode.remove(); } catch {} }
      if (!foldState.long.get(key)) answerSum.entries.delete(key);
    }
    answerSum.waitsPlaced.clear();
  };

  // Шаг из сводки: весь ответ (more) или обратно свёрнут; клавиатура — фокус на кнопку ответа.
  const answerSumStep = (entry, more, focus = false) => {
    foldState.clicks += 1;
    foldState.long.set(entry.key, more ? false : true);
    foldPaint();
    if (focus) { try { [...foldState.wholes.values()].find(whole => whole.__myclaudeFold?.key === entry.key)?.focus?.(); } catch {} }
  };
  const answerSumOf = target => {
    const own = target?.closest?.(`[${ANSWER_SUM_ATTRIBUTE}],[${ANSWER_WAITS_ATTRIBUTE}]`);
    if (!own) return null;
    for (const entry of answerSum.entries.values()) if (entry.node === own || entry.waitsNode === own) return entry;
    return null;
  };
  // Нажатие: по «Подробнее» — всегда; по сводке — без выделения (выделить и скопировать её можно
  // протяжкой). Двойной щелчок — одно нажатие.
  const onAnswerSumClick = event => {
    if (!state.alive) return;
    const entry = answerSumOf(event?.target);
    if (!entry) return;
    if (!event.target.closest?.(`[${ANSWER_SUM_BAR_ATTRIBUTE}]`)) {
      let selected = "";
      try { selected = String(window.getSelection?.()?.toString?.() ?? ""); } catch {}
      if (selected) return;
    }
    event.preventDefault?.();
    event.stopPropagation?.();
    if (Number(event.detail) > 1) return;
    try { answerSumStep(entry, true); } catch {}
  };
  const onAnswerSumKey = event => {
    if (!state.alive) return;
    const key = event?.key;
    if (key !== "Enter" && key !== " " && key !== "Spacebar" && key !== "Escape") return;
    const bar = event.target?.closest?.(`[${ANSWER_SUM_BAR_ATTRIBUTE}],[${ANSWER_WAITS_ATTRIBUTE}]`);
    const entry = bar ? answerSumOf(bar) : null;
    if (!entry) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    try { answerSumStep(entry, key !== "Escape", true); } catch {}
  };

  // Вид — как свёрнутая суть сообщения (12ф²): черта по --myclaude-fold-mid, серая подложка.
  lateRules.push(
    `[${ANSWER_SUM_ATTRIBUTE}]{display:block;box-sizing:border-box;margin:2px 0 8px calc(var(--myclaude-fold-mid, 7.4px) - .75px);padding:4px 12px 4px calc(10.75px - var(--myclaude-fold-mid, 7.4px) + 4px);border-left:1.5px solid currentColor;border-radius:0 8px 8px 0;background:rgba(127,127,127,.12);cursor:pointer;transition:background-color .15s;-webkit-app-region:no-drag}`,
    `[${ANSWER_SUM_ATTRIBUTE}]:hover{background:rgba(127,127,127,.2)}`,
    `[${ANSWER_SUM_ATTRIBUTE}]:active{background:rgba(127,127,127,.3)}`,
    `[${ANSWER_SUM_TEXT_ATTRIBUTE}]{white-space:pre-wrap;overflow-wrap:anywhere}`,
    `[${ANSWER_SUM_BAR_ATTRIBUTE}]{display:block;width:fit-content;margin-top:2px;font-weight:600;cursor:pointer;user-select:none;-webkit-user-select:none;border-radius:6px}`,
    `[${ANSWER_SUM_BAR_ATTRIBUTE}][${ANSWER_SUM_KIND_ATTRIBUTE}]::before{content:attr(${ANSWER_SUM_KIND_ATTRIBUTE}) " · ";font-weight:400;opacity:.6}`,
    `[${ANSWER_SUM_BAR_ATTRIBUTE}]::after{content:attr(${ANSWER_SUM_LABEL_ATTRIBUTE})}`,
    `[${ANSWER_SUM_BAR_ATTRIBUTE}]:focus-visible{outline:2px solid rgba(245,158,11,.7);outline-offset:1px}`,
    // Копия «Ждёт тебя» (#11000): янтарная черта, как фокус «Подробнее», — видно, что это ждёт его.
    `[${ANSWER_WAITS_ATTRIBUTE}]{display:block;box-sizing:border-box;margin:2px 0 8px;padding:4px 12px;border-left:2px solid rgba(245,158,11,.85);border-radius:0 8px 8px 0;background:rgba(245,158,11,.1);cursor:pointer;white-space:pre-wrap;overflow-wrap:anywhere;-webkit-app-region:no-drag}`,
    `[${ANSWER_WAITS_ATTRIBUTE}]:hover{background:rgba(245,158,11,.16)}`,
    `[${ANSWER_WAITS_ATTRIBUTE}]:focus-visible{outline:2px solid rgba(245,158,11,.7);outline-offset:1px}`,
    `[${ANSWER_WAITS_HEAD_ATTRIBUTE}]{font-weight:600}`,
  );

  // Сироты прошлой установки.
  try { for (const node of document.querySelectorAll(`[${ANSWER_SUM_ATTRIBUTE}],[${ANSWER_WAITS_ATTRIBUTE}]`)) node.remove(); } catch {}
  on(document, "click", onAnswerSumClick, true);
  on(window, "keydown", onAnswerSumKey, true);
  track(() => {
    for (const asked of answerSum.asked.values()) if (asked.timer) clearTimeout(asked.timer);
    for (const entry of answerSum.entries.values()) { try { entry.node.remove(); entry.waitsNode?.remove(); } catch {} }
    answerSum.entries.clear();
  });
  HATCH && Object.assign(HATCH, { answerWaitsOf });
