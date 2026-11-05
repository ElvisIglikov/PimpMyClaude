  // ---- 12х¹. «Работа идёт» одной строкой (слово Элвиса 10.10 10:20, WF231) ----
  // Слово Элвиса по снимку чата: подряд идут ответы из одной строки «Работа идёт» вперемежку со
  // служебными строками Claude — «взамен большого количества… одна штучка, что работа идёт, и там
  // что-нибудь крутилось, одной строкой».
  // Ход ассистента у Claude — список блоков (пропс entries над лентой, у хода items: text — текст
  // ответа, tools — группа инструментов, task_event — фоновая команда; замер живого окна 10.10,
  // Claude 2.31226). Серия — отрезок блоков одного хода без обычного текста, в котором строк «Работа
  // идёт» две и больше: сами строки и всё служебное между ними и по краям, до обычного текста с обеих
  // сторон. Одна строка «Работа идёт» серией не считается и остаётся как есть (облачко).
  // • Полоса хода (WF245): шаг может нести счёт «k/N» («Работа идёт 💭 3/10», N — прогноз, от шага к шагу
  //   уточняется). У живой свёрнутой серии по счёту её последнего шага — тонкая полоса из N секторов,
  //   k залиты, и «· k из N» вместо числа шагов; одиночная строка шага показывает полосу на месте счёта.
  // • Одно и то же один раз (WF245): хвостовой абзац «Работа идёт» обычного ответа спрятан, пока сразу
  //   под ним стоит свёрнутая строка серии; серию раскрыли — абзац виден.
  // • Свёрнутая серия — ОДНА своя строка на её месте: «Работа идёт» с кольцом (серия — хвост чата) или
  //   «Работа шла» (после неё пришёл текст или реплика человека), счёт шагов и «N не вышло», если
  //   фоновая команда серии упала. Нажал (Enter, пробел) — серия раскрыта под полосой, как свёртки
  //   12ф; ещё раз — свёрнута. Раскрытое помнится, пока окно открыто.
  // • Прячутся только строки «Работа идёт», группы инструментов и строки фоновых команд — по разметке
  //   Claude, не по тексту; карточка файла, картинка и всё незнакомое внутри серии остаются на виду.
  // • Узлы Claude не удаляются и не переставляются: метки и правила раздела 4 (высота 0 и
  //   прозрачность — innerText ленты тот же). Лента виртуальная: счёт и границы серии — по списку
  //   ходов; строка ленты называет номер своего блока (data-epitaxy-item-index), ход одной строкой
  //   ленты — блоки подряд, текстовые сверяются со списком по порядку. Не сошлось — ход не трогаем,
  //   причина — в status().work.lastError.
  // • Своих проходов нет: список читает тик «Прочитано», разметку ставит его же проход и колбэк мутаций.
  // Счёт хода «k/N» (WF245) — до облачка или после него: «Работа идёт 💭 3/10», «Работа идёт 3/10 💭».
  const WORK_STEP_RE = /^Работа\s+идёт\s*[.…]?\s*(?:\d{1,3}\s*\/\s*\d{1,3}\s*)?(?:💭️?)?\s*(?:\d{1,3}\s*\/\s*\d{1,3}\s*)?[.…]?$/u;
  // Счёт ещё печатается («… 💭 3», «… 💭 3/»): строка уже шаг, серия не мигает.
  const WORK_TYPING_RE = /^Работа\s+идёт\s*[.…]?\s*(?:💭️?)?\s*\d{1,3}\s*\/?$/u;
  const WORK_COUNT_RE = /(\d{1,3})\s*\/\s*(\d{1,3})/gu;
  const WORK_COUNT_HINT_RE = /Работа\s+идёт[^\n]*\d\s*\/\s*\d/u;
  const WORK_STEP_HEAD = "Работа идёт";
  const WORK_TEXT_MAX = 400;
  const WORK_PROSE = '[data-cds="Prose"]';
  const workState = {
    map: new Map(), cache: new WeakMap(), open: new Set(), only: new Set(), lines: new Map(), marked: new Set(), rows: new Set(),
    count: 0, folded: 0, failed: 0, live: false, error: null, clicks: 0,
    // Полоса хода (WF245): счёт живой серии, есть ли в чате шаги со счётом, абзацы с полосой.
    progress: null, counted: false, bars: new Set(), heads: new Set(), entries: null,
  };
  // Текст блока — только строка «Работа идёт» (чистая функция): с облачком или без, с точкой или без;
  // служебные хвосты К-CA (строка состояния, строки расхода) не в счёт. partial — блок ещё печатается:
  // начало строки «Работа идёт» уже считается ею (серия не мигает, пока дописывается её новая строка).
  const workStepLine = (raw, partial = false) => {
    const text = String(raw ?? "");
    if (text.length > WORK_TEXT_MAX) return null;
    let hit = null;
    for (const part of text.split("\n")) {
      const line = part.replace(/[*_`]/g, "").replace(/\s+/g, " ").trim();
      if (!line || cleanAnswerLine(line) === "hide") continue;
      if (hit != null || !(WORK_STEP_RE.test(line) || (partial && (WORK_STEP_HEAD.startsWith(line) || WORK_TYPING_RE.test(line))))) return null;
      hit = line;
    }
    return hit;
  };
  const workTextIs = (raw, partial = false) => workStepLine(raw, partial) != null;
  // Счёт хода строки шага (чистая функция): {k, n} — «k из N», 0 ≤ k ≤ N, 1 ≤ N ≤ WORK_BAR_MAX; счёта нет,
  // их два или числа не сходятся — null: строка остаётся обычным шагом без полосы.
  const workProgressOf = raw => {
    const line = workStepLine(raw);
    const found = line == null ? [] : [...line.matchAll(WORK_COUNT_RE)];
    if (found.length !== 1) return null;
    const k = Number(found[0][1]);
    const n = Number(found[0][2]);
    return n >= 1 && n <= WORK_BAR_MAX && k <= n ? { k, n } : null;
  };
  // Серии одного хода (чистая функция). items — блоки хода по порядку [{kind, text, status}]; partial —
  // ход ещё пишется (последний блок-текст может быть недописан). Ответ — [{from, to, first, steps,
  // failed, tail}]: границы серии по номерам блоков, первый её шаг, число строк «Работа идёт»,
  // упавших фоновых команд, и tail — серия доходит до конца хода. Обычный текст и блок незнакомого
  // вида серию рвут; одна строка «Работа идёт» — не серия. progress {k, n} — счёт последнего
  // дописанного шага (ключа нет — счёта нет); шаг, который ещё печатается, счёт не меняет.
  // Обычный текст начинается шагом (page-71, слово Элвиса 11.10 07:27: «работа идёт два раза»): первый видимый
  // абзац — строка «Работа идёт», за ним пустая строка и сам ответ. Так пишет Рик: последний шаг хода — первой
  // строкой итогового ответа. Ответ — эта строка или null (чистая функция).
  const workHeadLine = raw => {
    const text = String(raw ?? "");
    let head = null;
    let rest = false;
    for (const part of text.split("\n", 12)) {
      const line = part.replace(/[*_`]/g, "").replace(/\s+/g, " ").trim();
      if (head == null) {
        if (!line || cleanAnswerLine(line) === "hide") continue;
        if (!WORK_STEP_RE.test(line)) return null;
        head = line;
      } else if (line) { if (!rest) return null; return cleanAnswerLine(line) === "hide" ? null : head; }
      else rest = true;
    }
    return null;
  };
  const workSeriesOf = (items, partial = false) => {
    const list = Array.isArray(items) ? items : [];
    const typing = partial && list[list.length - 1]?.kind === "text" ? list.length - 1 : -1;
    const out = [];
    let run = null;
    const close = (to, tail) => { if (run && run.steps >= 2) out.push({ ...run, to, tail }); run = null; };
    list.forEach((item, index) => {
      const kind = item?.kind;
      const step = kind === "text" && workTextIs(item.text, index === typing);
      if (!step && kind !== "tools" && kind !== "task_event") {
        // Шаг первой строкой ответа — последний шаг серии над ним: в счёт и в полосу, сам абзац прячется (head).
        const head = run && kind === "text" ? workHeadLine(item.text) : null;
        if (head) {
          run.steps += 1;
          const progress = workProgressOf(head);
          if (progress) run.progress = progress; else delete run.progress;
        }
        close(index - 1, false);
        return;
      }
      run ??= { from: index, first: index, steps: 0, failed: 0 };
      if (step) {
        if (!run.steps) run.first = index;
        run.steps += 1;
        if (index !== typing) {
          const progress = workProgressOf(item.text);
          if (progress) run.progress = progress; else delete run.progress;
        }
      } else if (kind === "task_event" && item.status === "failed") run.failed += 1;
    });
    close(list.length - 1, true);
    return out;
  };
  // Серии чата по списку ходов ленты (его читает тик «Прочитано»). Разбор хода помнится за его
  // объектом: законченный ход заново не читается. Живая серия — хвост последнего хода чата.
  const workSync = (entries, responding = false) => {
    const list = Array.isArray(entries) ? entries : [];
    const map = new Map();
    const only = new Set();
    let count = 0;
    let folded = 0;
    let failed = 0;
    let live = false;
    let progress = null;
    let counted = false;
    const heads = new Set();
    list.forEach((entry, at) => {
      if (entry?.author !== "assistant" || typeof entry.id !== "string" || !Array.isArray(entry.items)) return;
      const last = at === list.length - 1;
      const partial = last && responding === true;
      const size = entry.items.length;
      let known = workState.cache.get(entry);
      if (!known || partial || known.partial || known.size !== size || known.tail !== entry.items[size - 1]) {
        const series = workSeriesOf(entry.items, partial).map(item => ({ ...item, key: String(entry.items[item.first]?.id ?? `${entry.id}:${item.first}`) }));
        const texts = [];
        entry.items.forEach((item, index) => { if (item?.kind === "text") texts.push(index); });
        // Весь текст хода — шаги одной серии: кроме неё, в ходе читать нечего.
        const whole = series.length === 1 && texts.every(index => index >= series[0].from && index <= series[0].to);
        // Шаг со счётом бывает и хвостовым абзацем обычного ответа — ищем во всех текстах хода.
        const counts = entry.items.some(item => item?.kind === "text" && WORK_COUNT_HINT_RE.test(String(item.text ?? "")));
        // Ответ, начатый строкой шага: её абзац в ленте не показывается (workPaint, метка head).
        const heads = entry.items.some(item => item?.kind === "text" && workHeadLine(item.text) != null);
        known = { size, partial, tail: entry.items[size - 1], series, texts, whole, counts, heads };
        workState.cache.set(entry, known);
      }
      if (known.counts) counted = true;
      if (known.heads) heads.add(entry.id);
      if (!known.series.length) return;
      const series = known.series.map(item => ({ ...item, live: last && item.tail }));
      map.set(entry.id, { series, texts: known.texts, partial, whole: known.whole });
      for (const item of series) {
        count += 1;
        failed += item.failed;
        if (item.live) { live = true; progress = item.progress ?? null; }
        if (!workState.open.has(item.key)) folded += 1;
      }
      if (known.whole && !workState.open.has(series[0].key)) only.add(entry.id);
    });
    // Список ходов — и для своих глав ответов без главы Claude (раздел 12х², #9757): их тик идёт следом.
    Object.assign(workState, { map, only, count, folded, failed, live, progress, counted, heads, entries: Array.isArray(entries) ? entries : null });
    if (!list.length || !map.size) workState.error = null;
  };
  // Колонка блоков хода в строке ленты: первый блочный ребёнок сообщения (перед ним бывает только
  // заголовок для чтения с экрана, после — действия сообщения).
  const workHostOf = row => {
    let message = null;
    try { message = row.querySelector('[data-cds="AssistantMessage"]'); } catch {}
    for (const node of message?.children ?? []) {
      if (node.tagName === "DIV") return node.getAttribute("data-cds") === "Prose" || node.hasAttribute(STAMP_ATTRIBUTE) ? null : node;
    }
    return null;
  };
  // Номер блока хода у строки ленты; у хода, который лента держит одной строкой, номера нет.
  const workIndexOf = row => {
    readEntryOf(row);
    const raw = readEntries.get(row)?.node?.getAttribute("data-epitaxy-item-index");
    return raw == null || raw === "" || !Number.isInteger(Number(raw)) ? null : Number(raw);
  };
  // Блок текста — только строка «Работа идёт»: по абзацам, как их видит человек.
  const workProseIs = (prose, partial = false) => {
    let host = prose;
    for (let depth = 0; depth < 2 && host.children.length === 1 && host.children[0].tagName === "DIV"; depth += 1) host = host.children[0];
    const blocks = [...host.children];
    if (!blocks.length) return workTextIs(prose.textContent, partial);
    if (blocks.some(block => block.tagName !== "P")) return false;
    return workTextIs(blocks.map(block => cleanAnswerLines(block).join("\n")).join("\n"), partial);
  };
  // Что серия прячет в блоке хода — по разметке Claude (замер живого окна 10.10): строка «Работа
  // идёт» — блок с одним текстом (обёртка без своего вида — тогда сам текст); группа инструментов —
  // [data-cds=TurnStatus]; строка фоновых команд — button[data-transcript-keeps-pin] без ключа блока.
  // Ответ — узел для метки; null — блок остаётся на виду (карточка, картинка, незнакомое); false —
  // пустая обёртка, прятать нечего.
  const workTargetOf = (block, prose, partial = false) => {
    if (prose) return workProseIs(prose, partial) ? (/(?:^|\s)contents(?:\s|$)/.test(block.getAttribute("class") ?? "") ? prose : block) : null;
    if (prose === null) return null;
    if (block.getAttribute("data-cds") === "TurnStatus") return block;
    let pin = null;
    let keyed = block.hasAttribute("data-item-key");
    try { pin = block.querySelector("button[data-transcript-keeps-pin]"); keyed ||= Boolean(block.querySelector("[data-item-key]")); } catch {}
    if (pin && !keyed) return block;
    return block.children.length || sayNorm(block.textContent) ? null : false;
  };
  // Блоки строки ленты, которые серия прячет: [{series, block, target}] по порядку; full — в строке
  // не остаётся ничего на виду; null — разметка не сошлась со списком.
  const workMembers = (info, row, host) => {
    const blocks = [...host.children].filter(node => !node.hasAttribute(WORK_LINE_ATTRIBUTE));
    // Текст блока: один — он сам, несколько — null (такой блок не строка «Работа идёт»).
    const proses = new Map();
    try {
      for (const prose of host.querySelectorAll(WORK_PROSE)) {
        let block = prose;
        while (block && block.parentNode !== host) block = block.parentNode;
        if (block) proses.set(block, proses.has(block) ? null : prose);
      }
    } catch {}
    const at = workIndexOf(row);
    const owner = new Map();
    const typing = new Set();
    if (at != null) {
      // Строка ленты одного блока хода: номер блока — в серии или нет.
      const series = info.series.find(item => item.from <= at && at <= item.to) ?? null;
      if (series) for (const block of blocks) owner.set(block, series);
      if (info.partial && series?.live) for (const block of blocks) typing.add(block);
    } else {
      // Ход одной строкой ленты: текстовые блоки — по порядку списка, служебное между ними — к серии
      // соседнего текста.
      let ordinal = -1;
      let prev = null;
      let pending = [];
      for (const block of blocks) {
        if (!proses.has(block)) { pending.push(block); continue; }
        ordinal += 1;
        const index = info.texts[ordinal];
        let series = index == null ? null : info.series.find(item => item.from <= index && index <= item.to) ?? null;
        const last = ordinal >= info.texts.length - 1;
        if (series && last && info.partial) typing.add(block);
        if (series && !workTargetOf(block, proses.get(block), typing.has(block))) {
          // Последний текст хода ещё пишется и уже не «Работа идёт» — он просто остаётся на виду;
          // расхождение в середине хода — порядок блоков не тот, что в списке.
          if (!last) return null;
          series = null;
        }
        for (const item of pending) if (prev ?? series) owner.set(item, prev ?? series);
        pending = [];
        if (series) owner.set(block, series);
        prev = series;
      }
      for (const item of pending) if (prev) owner.set(item, prev);
    }
    const members = [];
    let full = at != null;
    for (const block of blocks) {
      const series = owner.get(block);
      if (!series) { full = false; continue; }
      const target = workTargetOf(block, proses.get(block), typing.has(block));
      if (target) members.push({ series, block, target });
      else if (target === null) full = false;
    }
    return { members, full };
  };
  const workMakeLine = () => {
    const line = document.createElement("div");
    line.setAttribute(WORK_LINE_ATTRIBUTE, "done");
    line.setAttribute("role", "button");
    line.setAttribute("tabindex", "0");
    for (const part of ["arrow", "label", "bar", "steps", "failed"]) {
      const node = document.createElement("span");
      node.setAttribute(WORK_PART_ATTRIBUTE, part);
      node.setAttribute("aria-hidden", "true");
      line.appendChild(node);
    }
    return line;
  };
  const workDress = (line, series, open) => {
    const label = series.live ? "Работа идёт" : "Работа шла";
    // Полоса хода — только у идущей серии: у прошедшей счёт уже ни о чём не говорит.
    const bar = series.live ? series.progress ?? null : null;
    const steps = bar ? `${bar.k} из ${bar.n}` : `${series.steps} ${usagePlural(series.steps, "шаг", "шага", "шагов")}`;
    const failed = series.failed ? `${series.failed} не вышло` : null;
    foldSet(line, WORK_LINE_ATTRIBUTE, series.live ? "live" : "done");
    foldSet(line, "aria-expanded", open ? "true" : "false");
    foldSet(line, "aria-label", `${label}, ${steps}${failed ? `, ${failed}` : ""}`);
    foldSet(line, "title", open ? "Свернуть шаги" : "Показать шаги");
    // Без кольца и точки (page-71: «кругляшок какой-то, потом точка»): идущая со счётом — полоса и «k из N»,
    // остальные — «— N шагов».
    const text = { arrow: open ? "▾" : "▸", label, steps: bar ? steps : `— ${steps}`, failed };
    for (const part of line.children) {
      const name = part.getAttribute(WORK_PART_ATTRIBUTE);
      foldSet(part, WORK_TEXT_ATTRIBUTE, text[name] ?? null);
      if (name === "bar") foldSet(part, WORK_BAR_ATTRIBUTE, bar ? `${bar.k}/${bar.n}` : null);
    }
  };
  // Абзацы блока текста (под обёрткой без своего вида) и его последний видимый: служебные хвосты К-CA
  // (строка состояния, строки расхода) — не в счёт.
  const workTailOf = prose => {
    let host = prose;
    for (let depth = 0; depth < 2 && host.children.length === 1 && host.children[0].tagName === "DIV"; depth += 1) host = host.children[0];
    const blocks = [...host.children];
    for (let index = blocks.length - 1; index >= 0; index -= 1) {
      const block = blocks[index];
      if (block.tagName !== "P") return null;
      const lines = cleanAnswerLines(block);
      if (!lines.length || lines.every(line => cleanAnswerLine(line) === "hide")) continue;
      return lines.length === 1 ? { node: block, line: lines[0], alone: index === 0 } : null;
    }
    return null;
  };
  // Первый видимый абзац блока текста — строка шага, а за ним есть ещё видимое (сам ответ): этот абзац
  // (page-71); иначе null.
  const workHeadOf = prose => {
    let host = prose;
    for (let depth = 0; depth < 2 && host.children.length === 1 && host.children[0].tagName === "DIV"; depth += 1) host = host.children[0];
    let head = null;
    for (const block of host.children) {
      const lines = block.tagName === "P" ? cleanAnswerLines(block) : null;
      if (lines && (!lines.length || lines.every(line => cleanAnswerLine(line) === "hide"))) continue;
      if (head) return head;
      if (!lines || lines.length !== 1 || !workTextIs(lines[0])) return null;
      head = block;
    }
    return null;
  };
  const workEmpty = node => !node.children.length && !sayNorm(node.textContent);
  // Одно и то же один раз (WF245): обычный ответ кончается абзацем «Работа идёт», а сразу под ним
  // стоит свёрнутая строка серии (следующие шаги того же хода) — ответ — этот абзац; иначе null.
  const workEchoOf = (spot, row, rows) => {
    let above = spot.before.previousElementSibling;
    while (above && (above.hasAttribute(WORK_LINE_ATTRIBUTE) || workEmpty(above))) above = above.previousElementSibling;
    if (!above) {
      // Ход строкой ленты на блок: блок над серией — в соседней строке ленты выше.
      const prev = rows[rows.indexOf(row) - 1];
      if (!prev || readKeyOf(prev) !== readKeyOf(row) || workIndexOf(prev) !== spot.series.from - 1) return null;
      above = workHostOf(prev)?.lastElementChild ?? null;
      while (above && workEmpty(above)) above = above.previousElementSibling;
    }
    if (!above) return null;
    let proses = [];
    try { proses = above.matches(WORK_PROSE) ? [above] : [...above.querySelectorAll(WORK_PROSE)]; } catch {}
    const tail = proses.length === 1 ? workTailOf(proses[0]) : null;
    return tail && !tail.alone && workTextIs(tail.line) ? tail.node : null;
  };
  // Одиночная строка шага со счётом (WF245): последний видимый абзац блока текста — «Работа идёт 💭
  // 3/10» — показывает полосу на месте счёта. Блок, который ещё печатается, не трогаем: счёт дописывается.
  const workBars = rows => {
    const want = new Map();
    if (workState.counted) {
      for (const row of rows) {
        const id = readKeyOf(row);
        if (!id || (readState.marks.has(id) && !readState.open.has(id) && id !== readState.busy)) continue;
        let proses = [];
        try {
          proses = [...row.querySelectorAll(WORK_PROSE)];
          if (row.querySelector('[data-cds="AssistantMessage"]')?.getAttribute("data-is-streaming") === "true") proses.pop();
        } catch {}
        for (const prose of proses) {
          const tail = workTailOf(prose);
          const progress = tail ? workProgressOf(tail.line) : null;
          if (progress) want.set(tail.node, { bar: `${progress.k}/${progress.n}`, text: tail.line.replace(WORK_COUNT_RE, " ").replace(/\s+/g, " ").trim() });
        }
      }
    }
    for (const node of workState.bars) if (!want.has(node)) { foldSet(node, WORK_BAR_ATTRIBUTE, null); foldSet(node, WORK_TEXT_ATTRIBUTE, null); }
    for (const [node, made] of want) { foldSet(node, WORK_BAR_ATTRIBUTE, made.bar); foldSet(node, WORK_TEXT_ATTRIBUTE, made.text); }
    workState.bars = new Set(want.keys());
  };
  // Разметка ровно по тому, что сейчас в ленте; ушедшее снято. Раскладку читает, только когда
  // разметка меняется: лента, стоявшая у низа, остаётся у низа.
  const workPaint = (rows = readRowsNow()) => {
    if (workState.counted || workState.bars.size) workBars(rows);
    if (!workState.map.size && !workState.marked.size && !workState.lines.size && !workState.heads.size) { workState.rows.clear(); return; }
    const marks = new Map();
    const spots = new Map();
    const taken = new Set();
    let error = null;
    const found = new Map();
    if (workState.map.size) {
      for (const row of rows) {
        const id = readKeyOf(row);
        const info = id ? workState.map.get(id) : null;
        // Свёрнутый прочитанный ответ показывает свой блок (раздел 12х) — серии в нём не трогаем.
        if (!info || (readState.marks.has(id) && !readState.open.has(id) && id !== readState.busy)) continue;
        const host = workHostOf(row);
        if (!host) continue;
        const made = workMembers(info, row, host);
        if (!made) { error = "ход в ленте не сошёлся со списком блоков: серии в нём не свёрнуты"; continue; }
        for (const member of made.members) {
          const key = member.series.key;
          if (!found.has(key)) found.set(key, { series: member.series, parts: [] });
          const parts = found.get(key).parts;
          if (parts[parts.length - 1]?.row !== row) parts.push({ row, host, members: [], full: made.full && made.members.every(item => item.series === member.series) });
          parts[parts.length - 1].members.push(member);
        }
      }
    }
    // Ответ начат строкой шага: шаг кончился — его абзац не показывается (серия над ним его уже сосчитала).
    if (workState.heads.size) {
      for (const row of rows) {
        const id = readKeyOf(row);
        if (!id || !workState.heads.has(id) || (readState.marks.has(id) && !readState.open.has(id) && id !== readState.busy)) continue;
        let proses = [];
        try { proses = [...row.querySelectorAll(WORK_PROSE)]; } catch {}
        for (const prose of proses) {
          const head = workHeadOf(prose);
          if (head) marks.set(head, "head");
        }
      }
    }
    for (const { series, parts } of found.values()) {
      const open = workState.open.has(series.key);
      // Строка-сводка — в первой строке серии, что есть в DOM, перед её первым блоком.
      const spot = { series, open, host: parts[0].host, before: parts[0].members[0].block };
      spots.set(series.key, spot);
      const echo = open ? null : workEchoOf(spot, parts[0].row, rows);
      if (echo) marks.set(echo, "echo");
      let first = true;
      for (const part of parts) {
        for (const member of part.members) { marks.set(member.target, open ? (first ? "open-first" : "open") : "rest"); first = false; }
        if (open || !part.full) continue;
        taken.add(part.row);
        if (part !== parts[0]) marks.set(part.row, "row");
      }
    }
    let changed = spots.size !== workState.lines.size || marks.size !== workState.marked.size;
    if (!changed) for (const [node, value] of marks) if (node.getAttribute(WORK_ATTRIBUTE) !== value) { changed = true; break; }
    if (!changed) for (const [key, spot] of spots) {
      const line = workState.lines.get(key);
      if (!line || line.parentNode !== spot.host || line.nextElementSibling !== spot.before) { changed = true; break; }
    }
    let feed = null;
    let pinned = false;
    if (changed) {
      feed = readFeed();
      try { pinned = Boolean(feed) && feed.scrollHeight - feed.scrollTop - feed.clientHeight < 2; } catch {}
    }
    for (const node of workState.marked) if (!marks.has(node)) foldSet(node, WORK_ATTRIBUTE, null);
    for (const [node, value] of marks) foldSet(node, WORK_ATTRIBUTE, value);
    workState.marked = new Set(marks.keys());
    for (const [key, line] of workState.lines) if (!spots.has(key)) { try { line.remove(); } catch {} workState.lines.delete(key); }
    for (const [key, spot] of spots) {
      const line = workState.lines.get(key) ?? workMakeLine();
      if (line.parentNode !== spot.host || line.nextElementSibling !== spot.before) {
        try { spot.host.insertBefore(line, spot.before); } catch { continue; }
      }
      line.__myclaudeWork = key;
      workState.lines.set(key, line);
      workDress(line, spot.series, spot.open);
    }
    workState.rows = taken;
    workState.error = error;
    if (pinned) { try { feed.scrollTop = feed.scrollHeight; } catch {} }
  };
  // Раскрыть или свернуть серию. Строка-сводка остаётся там, где её нажали.
  const workToggle = key => {
    const line = key ? workState.lines.get(key) : null;
    if (!line) return false;
    let top = null;
    try { top = line.getBoundingClientRect().top; } catch {}
    const focused = document.activeElement === line;
    if (workState.open.has(key)) workState.open.delete(key); else workState.open.add(key);
    workState.clicks += 1;
    workState.folded += workState.open.has(key) ? -1 : 1;
    // Ход из одной серии: свёрнут — не ответ для «Прочитано», раскрыт — снова ответ.
    for (const [id, info] of workState.map) {
      if (!info.whole || info.series[0].key !== key) continue;
      if (workState.open.has(key)) workState.only.delete(id); else workState.only.add(id);
    }
    readPaint();
    readCount();
    const now = workState.lines.get(key);
    if (!now) return true;
    if (focused && document.activeElement !== now) { try { now.focus({ preventScroll: true }); } catch {} }
    try {
      const feed = readFeed();
      const delta = top == null || !feed ? 0 : Math.round(now.getBoundingClientRect().top - top);
      if (Math.abs(delta) > 1) feed.scrollTop += delta;
    } catch {}
    return true;
  };
  // Сироты прошлой установки — до первой разметки.
  const workSweep = () => {
    try {
      for (const node of document.querySelectorAll(`[${WORK_LINE_ATTRIBUTE}]`)) node.remove();
      for (const node of document.querySelectorAll(`[${WORK_ATTRIBUTE}]`)) node.removeAttribute(WORK_ATTRIBUTE);
      for (const node of document.querySelectorAll(`p[${WORK_BAR_ATTRIBUTE}]`)) { node.removeAttribute(WORK_BAR_ATTRIBUTE); node.removeAttribute(WORK_TEXT_ATTRIBUTE); }
    } catch {}
  };
  workSweep();
  track(() => {
    workState.map.clear();
    workState.lines.clear();
    workState.marked.clear();
    workState.rows.clear();
    workState.only.clear();
    workState.bars.clear();
    workState.entries = null;
    workSweep();
  });
  // «Работа идёт» одной строкой (раздел 12х¹): серий в чате, из них свёрнуто, есть ли живая
  // (хвост чата), упавших фоновых команд в сериях; lastError — ход не сошёлся со списком блоков;
  // progress {k, n} — счёт хода живой серии (WF245; счёта нет — null).
  statusPart("work", () => ({ series: workState.count, folded: workState.folded, live: workState.live, failed: workState.failed, lastError: workState.error, progress: workState.progress }));
  HATCH && Object.assign(HATCH, { workTextIs, workProgressOf, workHeadLine, workSeriesOf, workState });

