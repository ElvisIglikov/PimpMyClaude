  // ---- 13в. Бесшовная лента: прошлый чат линии над верхом текущего (#11201, WF303) ----
  // Слово Элвиса 30.10 12:22 (#11201): «я в последнем чате… могу вверх начать крутить… полоса предыдущий чат…
  // хлоп и смотрю уже то, что было в предыдущем чате… автоматически подгружается сверху ещё один чат предыдущий…
  // вниз вернуться, и они… из-за оперативки уйдут… не придётся цитировать последний ответ Рика из прежнего чата».
  //  • Лента Claude внутри не меняется. «Шов» — свой блок поверх верха видимой ленты; саму ленту сдвигает вниз
  //    трансформ скроллера (translateY(h) и обрезка clip-path по строке заголовка и верху поля ввода): размеры,
  //    scrollTop и окно виртуализатора те же, ResizeObserver трансформа не видит (docs/razvedka-11201-virtualizer.md).
  //  • Данные — из страницы: LocalSessions.getTranscriptTail/Page (раздел 13б знает линию: links.prev, ids). Хвост
  //    прошлого чата берётся заранее, при смене чата; ходы (вопрос, подходы, ответ) — чистой функцией seamTurns, вид —
  //    своим маленьким Markdown (seamMarkdown: только createElement и textContent, ссылки — http/https/mailto).
  //  • Колесо — «один жест — один хозяин»: у верха ленты шов открывает только новый жест (колесо помолчало
  //    SEAM_QUIET_MS), погашенный жест — наш до конца; пока h > 0, у ленты overflow-y:hidden. h = H (видимая высота
  //    ленты) — «внутри»: блок крутится сам, у его верха подгружается ещё порция, потом чат выше по линии; потолок —
  //    SEAM_MAX_CHATS чатов или SEAM_MAX_TURNS ходов. Лента сдвинулась не нами (отправил сообщение, 12х, главы, End) —
  //    шов закрыт. Ушли вниз дальше SEAM_UNLOAD_SCREENS экранов — подгруженное снято, хвост остаётся.
  //  • Наши узлы — без data-cds, data-testid, role, h1–h6, классов строк Claude: разделы ленты Пимпа (свёртки, «Ответ»,
  //    метки, главы, время, кнопки «Ждёт тебя») их не видят. Вид — классы живых узлов (prose, пузырь вопроса),
  //    CSS Claude и Пимпа (.epitaxy-transcript-typography .prose …) ложится сам.
  //  • Шов только при узле React над лентой (chainState.host): без него край «догружено ли всё» не знаем — работает 676.
  //    Пока шов готов, раздел 13б уступает верх (chainState.seamTop): нет плашки «↑», зазора и натяжки вверх;
  //    автопереход ждёт, пока шов закрыт (chainState.seamPhase).
  const SEAM_ROOT_ID = "myclaude-seam";
  const SEAM_ATTRIBUTE = "data-myclaude-seam";
  const SEAM_GO_ATTRIBUTE = "data-myclaude-seam-go";
  const SEAM_HOME_ATTRIBUTE = "data-myclaude-seam-home";
  const SEAM_TICK_MS = 150;
  const SEAM_TAIL_LIMIT = 40;
  const SEAM_PAGE_LIMIT = 60;
  const SEAM_STALE_MS = 30000;
  const SEAM_RETRY_MS = 5000;
  const SEAM_QUIET_MS = CHAIN_QUIET_MS;
  const SEAM_GESTURE_END_MS = 120;
  const SEAM_OWN_MS = 250;
  const SEAM_LOAD_SCREENS = 1.5;
  const SEAM_UNLOAD_SCREENS = 3;
  const SEAM_MAX_CHATS = 3;
  const SEAM_MAX_TURNS = 150;
  const SEAM_MAX_ROWS = 3000;
  // Закрыт и помолчал — подгруженное сверх хвоста снято и в коротком чате («вниз вернуться… из-за оперативки уйдут»).
  const SEAM_SHED_MS = 1500;
  // Отправка, клик мимо шва, клавиша вне поля — «человек»: прокрутка ленты после него закрывает шов и во время ответа.
  const SEAM_HUMAN_MS = 1500;
  const SEAM_CACHE_MAX = 4;
  const SEAM_TEXT_MAX = 40000;
  const SEAM_INLINE_MAX = 8000;
  const SEAM_DEPTH_MAX = 6;
  const SEAM_HOME_MS = 240;
  const SEAM_NOTE_MAX = 160;
  const SEAM_TEXT = {
    prev: "↑ Предыдущий чат", open: "Открыть {t}", home: "↓ К этому чату", work: "Работа", image: "🖼 снимок",
    note: "Уведомление", loading: "Загружаю…", start: "Начало линии",
  };
  // Не человек: служебные строки user (команды, прерывания, хуки); напоминание вырезается, уведомление — метка.
  const SEAM_NOT_HUMAN = ["<command-", "<local-command", "<bash-", "<user-prompt-submit-hook>", "[Request interrupted"];
  // Запасные классы — из разведки (живых узлов нет: пустая лента).
  const SEAM_BUBBLE_FALLBACK = "relative flex min-w-0 flex-col gap-xs rounded-[var(--cds-message-bubble-radius)] px-[var(--cds-message-bubble-pad-x)] py-[var(--cds-message-bubble-pad-y)] text-heading font-normal break-words select-text text-primary max-w-[var(--cds-message-bubble-measure)] bg-[var(--cds-bg-user-message)]";
  const SEAM_PROSE_FALLBACK = "prose";
  // Классы, по которым нас подхватили бы разделы ленты (690, 500, 290, 280, 040), — с живых узлов не берём.
  const seamClassOk = name => name && name !== "group/message-row" && name !== "epitaxy-user-turn"
    && name !== "epitaxy-transcript-width" && !name.startsWith("font-claude-response");
  const seamClasses = raw => String(raw ?? "").split(/\s+/).filter(seamClassOk).join(" ");
  const seamApi = () => { const api = chainSessions(); return typeof api?.getTranscriptTail === "function" ? api : null; };

  // ---- ходы (чистые функции; люк — HATCH.seamTurns) ----
  const seamContent = row => row?.message?.content ?? row?.content;
  const seamBlocks = content => (typeof content === "string" ? [{ type: "text", text: content }]
    : Array.isArray(content) ? content.filter(b => b && typeof b === "object") : []);
  const seamTime = row => { const t = Date.parse(String(row?.timestamp ?? "")); return Number.isFinite(t) ? t : NaN; };
  // Вырезать куски open…close (без регулярок); незакрытый — до конца.
  const seamCut = (text, open, close) => {
    let out = "";
    let i = 0;
    for (;;) {
      const a = text.indexOf(open, i);
      if (a < 0) return out + text.slice(i);
      out += text.slice(i, a);
      const b = text.indexOf(close, a + open.length);
      if (b < 0) return out;
      i = b + close.length;
    }
  };
  // Снять обёртку <pasted_content …>…</pasted_content …>: теги прочь, текст внутри — остаётся.
  const seamUnwrap = text => {
    let out = text;
    for (const tag of ["</pasted_content", "<pasted_content"]) {
      for (let a = out.indexOf(tag); a >= 0; a = out.indexOf(tag, a)) {
        const b = out.indexOf(">", a);
        if (b < 0) break;
        out = out.slice(0, a) + out.slice(b + 1);
      }
    }
    return out;
  };
  const seamBetween = (text, open, close) => {
    const a = text.indexOf(open);
    const b = a < 0 ? -1 : text.indexOf(close, a + open.length);
    return b < 0 ? "" : text.slice(a + open.length, b);
  };
  // Строка user → {kind: skip | tool | note | other | human, …}. skip — мимо совсем (isMeta), tool — вывод
  // инструмента (не граница подхода), note — уведомление задачи (граница, тихая метка), other — служебная (граница).
  const seamUserKind = row => {
    if (row.isMeta === true) return { kind: "skip" };
    if (row.isCompactSummary === true) return { kind: "other" };
    const blocks = seamBlocks(seamContent(row));
    if (blocks.some(b => b.type === "tool_result")) return { kind: "tool" };
    const raw = blocks.filter(b => b.type === "text").map(b => String(b.text ?? "")).join("\n");
    const images = blocks.filter(b => b.type === "image").length;
    const lead = raw.trimStart();
    if (lead.startsWith("<task-notification>")) {
      const label = sayNorm(seamBetween(lead, "<summary>", "</summary>")) || SEAM_TEXT.note;
      return { kind: "note", label: label.length > SEAM_NOTE_MAX ? `${label.slice(0, SEAM_NOTE_MAX - 1)}…` : label };
    }
    // Напоминание вырезаем, а не отбрасываем строку: Claude Code кладёт его и перед словами человека.
    const text = seamUnwrap(seamCut(raw, "<system-reminder>", "</system-reminder>")).trim();
    if (SEAM_NOT_HUMAN.some(p => text.startsWith(p))) return { kind: "other" };
    return text || images ? { kind: "human", text, images } : { kind: "other" };
  };
  // Подход: ответ — тексты после последнего tool_use; кончился на tool_use — последний текст; раньше — «Работа».
  const seamApproach = ap => {
    let last = -1;
    ap.items.forEach((item, i) => { if (item.kind === "tool") last = i; });
    const answer = ap.items.slice(last + 1).filter(x => x.kind === "text").map(x => x.text);
    const work = ap.items.slice(0, last + 1).filter(x => x.kind === "text").map(x => x.text);
    if (!answer.length && work.length) answer.push(work.pop());
    if (!answer.length && !ap.tools && !ap.note) return null;
    return { note: ap.note, answer: answer.join("\n\n"), work, tools: ap.tools, done: ap.stop === "end_turn" };
  };
  // Строки JSONL Claude Code (старые → новые) → ходы [{key, at, q: {text, images} | null, aps: [подход]}].
  // Повтор uuid — мимо; блоки одного message.id склеиваются, повтор блока внутри него — мимо.
  const seamTurns = rows => {
    const seen = new Set();
    const byMessage = new Map();
    const turns = [];
    let turn = null;
    let ap = null;
    const open = (q, row) => { turn = { key: String(row.uuid ?? ""), at: seamTime(row), q, aps: [] }; turns.push(turn); ap = null; };
    const fresh = note => { ap = { note, items: [], tools: 0, stop: null }; turn.aps.push(ap); };
    for (const row of Array.isArray(rows) ? rows : []) {
      if (!row || typeof row !== "object" || row.isSidechain === true) continue;
      const uuid = typeof row.uuid === "string" ? row.uuid : "";
      if (uuid) { if (seen.has(uuid)) continue; seen.add(uuid); }
      if (row.type === "user") {
        const k = seamUserKind(row);
        if (k.kind === "skip" || k.kind === "tool") continue;
        if (k.kind === "human") { open({ text: k.text, images: k.images }, row); continue; }
        if (!turn) open(null, row);
        fresh(k.kind === "note" ? k.label : null);
        continue;
      }
      if (row.type !== "assistant") continue;
      if (!turn) open(null, row);
      if (!ap) fresh(null);
      const id = typeof row.message?.id === "string" ? row.message.id : "";
      const keys = id ? byMessage.get(id) ?? new Set() : null;
      if (id) byMessage.set(id, keys);
      for (const b of seamBlocks(seamContent(row))) {
        const key = b.type === "text" ? `t:${b.text}` : b.type === "tool_use" ? `u:${b.id ?? ""}:${b.name ?? ""}` : "";
        if (!key || (keys && keys.has(key))) continue;
        keys?.add(key);
        if (b.type === "text") { if (String(b.text ?? "").trim()) ap.items.push({ kind: "text", text: String(b.text) }); }
        else { ap.items.push({ kind: "tool" }); ap.tools += 1; }
      }
      const stop = row.message?.stop_reason ?? row.stop_reason;
      if (typeof stop === "string" && stop) ap.stop = stop;
    }
    return turns.map(t => ({ key: t.key, at: t.at, q: t.q, aps: t.aps.map(seamApproach).filter(Boolean) }))
      .filter(t => t.q || t.aps.length);
  };

  // ---- Markdown (люк — HATCH.seamMarkdown) ----
  // Только createElement и textContent. Из HTML — белый список (details summary b strong i em br code kbd) без
  // атрибутов (кроме open у details); любой другой тег — текстом как есть. Ссылка — только http/https/mailto по
  // new URL(…).protocol. Заголовки — div своим классом (не h1–h6: их ищут 510/520), абзац «Ждёт тебя» — div (522).
  const seamEl = (tag, cls, text) => {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text != null) node.textContent = String(text);
    return node;
  };
  const seamLinkOk = raw => {
    try {
      const url = new URL(String(raw ?? "").trim());
      return url.protocol === "http:" || url.protocol === "https:" || url.protocol === "mailto:" ? url.href : "";
    } catch { return ""; }
  };
  const seamLink = (href, parent) => {
    const a = seamEl("a");
    a.setAttribute("href", href);
    a.setAttribute("target", "_blank");
    a.setAttribute("rel", "noopener noreferrer");
    parent.appendChild(a);
    return a;
  };
  const seamWordChar = c => typeof c === "string" && /[\p{L}\p{N}]/u.test(c);
  const seamSpace = c => typeof c !== "string" || /\s/.test(c);
  const SEAM_INLINE_TAGS = { b: "strong", strong: "strong", i: "em", em: "em", code: "code", kbd: "kbd" };
  const SEAM_ESCAPABLE = "\\`*_~[]()<>#|!-+.";
  // Закрывающий разделитель эмфазы: не после пробела, одиночный — не половина двойного, «_» — не внутри слова.
  const seamEmClose = (text, d, from) => {
    for (let j = text.indexOf(d, from + 1); j >= 0; j = text.indexOf(d, j + 1)) {
      if (seamSpace(text[j - 1])) continue;
      if (d.length === 1 && (text[j + 1] === d || text[j - 1] === d)) { j += 1; continue; }
      if (d[0] === "_" && seamWordChar(text[j + d.length])) continue;
      return j;
    }
    return -1;
  };
  const seamBracket = (text, i) => {
    let depth = 0;
    for (let j = i; j < text.length; j += 1) {
      const c = text[j];
      if (c === "\\") { j += 1; continue; }
      if (c === "\n") return -1;
      if (c === "[") depth += 1;
      else if (c === "]" && --depth === 0) return j;
    }
    return -1;
  };
  const seamParen = (text, i) => {
    let depth = 0;
    for (let j = i; j < text.length; j += 1) {
      const c = text[j];
      if (c === "\n") return -1;
      if (c === "(") depth += 1;
      else if (c === ")" && --depth === 0) return j;
    }
    return -1;
  };
  const seamCount = (s, c) => { let n = 0; for (const x of s) if (x === c) n += 1; return n; };
  const seamInline = (text, parent, depth = 0) => {
    let buf = "";
    const flush = () => {
      if (!buf) return;
      const parts = buf.split("\n");
      parts.forEach((part, k) => {
        if (k) parent.appendChild(document.createElement("br"));
        if (part) parent.appendChild(document.createTextNode(part));
      });
      buf = "";
    };
    if (text.length > SEAM_INLINE_MAX || depth > SEAM_DEPTH_MAX) { buf = text; flush(); return; }
    const miss = new Set();
    const put = (tag, inner, raw = false) => {
      flush();
      const node = seamEl(tag);
      if (raw) node.textContent = inner; else seamInline(inner, node, depth + 1);
      parent.appendChild(node);
    };
    let i = 0;
    while (i < text.length) {
      const c = text[i];
      if (c === "\\" && i + 1 < text.length && SEAM_ESCAPABLE.includes(text[i + 1])) { buf += text[i + 1]; i += 2; continue; }
      if (c === "`") {
        let n = 1;
        while (text[i + n] === "`") n += 1;
        const fence = "`".repeat(n);
        const j = miss.has(fence) ? -1 : text.indexOf(fence, i + n);
        if (j < 0) { miss.add(fence); buf += fence; i += n; continue; }
        let inner = text.slice(i + n, j);
        if (inner.length > 2 && inner[0] === " " && inner[inner.length - 1] === " ") inner = inner.slice(1, -1);
        put("code", inner, true);
        i = j + n;
        continue;
      }
      if (c === "*" || c === "_" || c === "~") {
        const two = text[i + 1] === c;
        const d = two ? c + c : c;
        if ((c === "~" && !two) || (c === "_" && seamWordChar(text[i - 1])) || seamSpace(text[i + d.length])) { buf += d; i += d.length; continue; }
        const j = miss.has(d) ? -1 : seamEmClose(text, d, i + d.length - 1);
        if (j < 0 || j <= i + d.length - 1) { miss.add(d); buf += d; i += d.length; continue; }
        put(c === "~" ? "s" : two ? "strong" : "em", text.slice(i + d.length, j));
        i = j + d.length;
        continue;
      }
      if (c === "[") {
        const close = seamBracket(text, i);
        const end = close > 0 && text[close + 1] === "(" ? seamParen(text, close + 1) : -1;
        if (end > 0) {
          let raw = text.slice(close + 2, end).trim();
          const sp = raw.search(/\s/);
          if (sp > 0) raw = raw.slice(0, sp);
          if (raw.startsWith("<") && raw.endsWith(">")) raw = raw.slice(1, -1);
          const href = seamLinkOk(raw);
          if (href) { flush(); seamInline(text.slice(i + 1, close), seamLink(href, parent), depth + 1); }
          else buf += text.slice(i, end + 1);
          i = end + 1;
          continue;
        }
        buf += c;
        i += 1;
        continue;
      }
      if ((c === "h" || c === "H") && (text.startsWith("https://", i) || text.startsWith("http://", i)) && !seamWordChar(text[i - 1])) {
        let j = i;
        while (j < text.length && !/[\s<>"`]/.test(text[j])) j += 1;
        let url = text.slice(i, j);
        while (url && /[.,;:!?»'")\]]/.test(url[url.length - 1])) {
          if (url.endsWith(")") && seamCount(url, "(") >= seamCount(url, ")")) break;
          url = url.slice(0, -1);
        }
        const href = seamLinkOk(url);
        if (href && url.length > 8) { flush(); seamLink(href, parent).textContent = url; i += url.length; continue; }
        buf += c;
        i += 1;
        continue;
      }
      if (c === "<") {
        const m = /^<(\/?)([a-z]{1,6})\s*(\/?)>/.exec(text.slice(i, i + 12));
        const tag = m?.[2] ?? "";
        if (m && tag === "br" && !m[1]) { flush(); parent.appendChild(document.createElement("br")); i += m[0].length; continue; }
        if (m && !m[1] && !m[3] && SEAM_INLINE_TAGS[tag]) {
          const end = text.indexOf(`</${tag}>`, i + m[0].length);
          if (end > 0) {
            const raw = tag === "code" || tag === "kbd";
            put(SEAM_INLINE_TAGS[tag], text.slice(i + m[0].length, end), raw);
            i = end + tag.length + 3;
            continue;
          }
        }
        buf += c;
        i += 1;
        continue;
      }
      buf += c;
      i += 1;
    }
    flush();
  };
  const seamIndent = line => { let n = 0; for (const c of line) { if (c === " ") n += 1; else if (c === "\t") n += 4; else break; } return n; };
  const SEAM_ITEM_RE = /^([ \t]*)([-*+]|\d{1,9}[.)])(?:[ \t]+(.*))?$/;
  const SEAM_FENCE_RE = /^[ \t]*(`{3,}|~{3,})/;
  const seamCells = line => {
    let s = line.trim();
    if (s.startsWith("|")) s = s.slice(1);
    if (s.endsWith("|") && !s.endsWith("\\|")) s = s.slice(0, -1);
    const cells = [];
    let cur = "";
    let code = false;
    for (let k = 0; k < s.length; k += 1) {
      const ch = s[k];
      if (ch === "\\" && s[k + 1] === "|") { cur += "|"; k += 1; continue; }
      if (ch === "`") code = !code;
      if (ch === "|" && !code) { cells.push(cur.trim()); cur = ""; continue; }
      cur += ch;
    }
    cells.push(cur.trim());
    return cells;
  };
  const seamTableSep = line => line.includes("|") && line.includes("-") && seamCells(line).every(c => /^:?-+:?$/.test(c));
  const seamHr = t => { const bare = t.replace(/[ \t]+/g, ""); return bare.length >= 3 && /^(?:-+|\*+|_+)$/.test(bare); };
  const seamBlockStart = t => t.startsWith("#") || t.startsWith(">") || SEAM_FENCE_RE.test(t) || t.startsWith("<details") || t.startsWith("</details") || t.startsWith("|") || seamHr(t);
  const seamWaitHead = text => { const s = sayNorm(text); return s.length <= WAIT_HEAD_MAX && WAIT_HEAD_RE.test(s); };
  // Код ``` … ``` с позиции i → [pre, следующая строка].
  const seamFence = (lines, i) => {
    const mark = SEAM_FENCE_RE.exec(lines[i])[1];
    const body = [];
    let j = i + 1;
    for (; j < lines.length; j += 1) {
      const t = lines[j].trim();
      if (t.startsWith(mark[0].repeat(mark.length)) && !t.slice(mark.length).replace(new RegExp(`\\${mark[0]}`, "g"), "").trim()) { j += 1; break; }
      body.push(lines[j]);
    }
    const pre = seamEl("pre", "myclaude-seam-code");
    pre.appendChild(seamEl("code", "", body.join("\n")));
    return [pre, j];
  };
  const seamList = (lines, i, parent) => {
    const stack = [];
    while (i < lines.length) {
      const line = lines[i];
      if (!line.trim()) {
        let k = i + 1;
        while (k < lines.length && !lines[k].trim()) k += 1;
        if (k < lines.length && stack.length && (SEAM_ITEM_RE.test(lines[k]) || seamIndent(lines[k]) > stack[0].indent)) { i = k; continue; }
        break;
      }
      const m = SEAM_ITEM_RE.exec(line);
      if (m && !seamHr(line.trim())) {
        const indent = seamIndent(m[1]);
        const ordered = /\d/.test(m[2][0]);
        while (stack.length > 1 && indent < stack[stack.length - 1].indent) stack.pop();
        let cur = stack[stack.length - 1];
        if (cur && indent > cur.indent + 1 && cur.li) {
          const list = seamEl(ordered ? "ol" : "ul");
          cur.li.appendChild(list);
          cur = { indent, list, li: null, ordered };
          stack.push(cur);
        } else if (!cur || cur.ordered !== ordered) {
          const holder = stack.length > 1 ? stack[stack.length - 2].li : parent;
          if (cur) stack.pop();
          const list = seamEl(ordered ? "ol" : "ul");
          if (ordered && Number.parseInt(m[2], 10) > 1) list.setAttribute("start", String(Number.parseInt(m[2], 10)));
          (holder ?? parent).appendChild(list);
          cur = { indent, list, li: null, ordered };
          stack.push(cur);
        }
        const li = seamEl("li");
        seamInline(String(m[3] ?? ""), li);
        cur.list.appendChild(li);
        cur.li = li;
        i += 1;
        continue;
      }
      const t = line.trim();
      const li = stack[stack.length - 1]?.li;
      if (li && SEAM_FENCE_RE.test(t)) { const [pre, next] = seamFence(lines, i); li.appendChild(pre); i = next; continue; }
      if (li && (seamIndent(line) > 0 || !seamBlockStart(t))) { li.appendChild(document.createElement("br")); seamInline(t, li); i += 1; continue; }
      break;
    }
    return i;
  };
  const seamTable = (lines, i, parent) => {
    const head = seamCells(lines[i]);
    const align = seamCells(lines[i + 1]).map(c => (c.endsWith(":") ? (c.startsWith(":") ? "center" : "right") : ""));
    const wrap = seamEl("div", "myclaude-seam-scroll");
    const table = seamEl("table");
    const row = (cells, tag) => {
      const tr = seamEl("tr");
      for (let k = 0; k < Math.max(cells.length, head.length); k += 1) {
        const cell = seamEl(tag);
        if (align[k]) cell.style.textAlign = align[k];
        seamInline(cells[k] ?? "", cell);
        tr.appendChild(cell);
      }
      return tr;
    };
    const thead = seamEl("thead");
    thead.appendChild(row(head, "th"));
    table.appendChild(thead);
    const tbody = seamEl("tbody");
    let j = i + 2;
    for (; j < lines.length && lines[j].trim() && lines[j].includes("|"); j += 1) tbody.appendChild(row(seamCells(lines[j]), "td"));
    table.appendChild(tbody);
    wrap.appendChild(table);
    parent.appendChild(wrap);
    return j;
  };
  const seamBlocksInto = (lines, root, depth) => {
    // Стек свёрток <details>: тела, в которые идут блоки.
    const stack = [root];
    const top = () => stack[stack.length - 1];
    let para = [];
    const flush = () => {
      if (!para.length) return;
      const text = para.join("\n");
      para = [];
      let p = seamEl("p");
      seamInline(text, p);
      if (seamWaitHead(p.textContent)) {
        const div = seamEl("div", "myclaude-seam-p");
        while (p.firstChild) div.appendChild(p.firstChild);
        p = div;
      }
      top().appendChild(p);
    };
    let i = 0;
    while (i < lines.length) {
      const line = lines[i];
      const t = line.trim();
      if (!t) { flush(); i += 1; continue; }
      const details = /^<details(\s+open)?\s*>/.exec(t);
      if (details) {
        flush();
        const d = seamEl("details", "myclaude-seam-fold");
        if (details[1]) d.setAttribute("open", "");
        const body = seamEl("div", "myclaude-seam-fold-body");
        d.appendChild(body);
        top().appendChild(d);
        stack.push(body);
        const rest = t.slice(details[0].length).trim();
        lines = rest ? [...lines.slice(0, i), rest, ...lines.slice(i + 1)] : lines;
        if (!rest) i += 1;
        continue;
      }
      if (t.startsWith("<summary>") && stack.length > 1) {
        flush();
        let text = t.slice(9);
        let j = i;
        while (!text.includes("</summary>") && j + 1 < lines.length) { j += 1; text += ` ${lines[j].trim()}`; }
        const end = text.indexOf("</summary>");
        const rest = end >= 0 ? text.slice(end + 10).trim() : "";
        const summary = seamEl("summary", "myclaude-seam-fold-head");
        seamInline((end >= 0 ? text.slice(0, end) : text).trim(), summary);
        const body = top();
        body.parentNode.insertBefore(summary, body);
        lines = rest ? [...lines.slice(0, j), rest, ...lines.slice(j + 1)] : lines;
        i = rest ? j : j + 1;
        continue;
      }
      if (t.startsWith("</details>") && stack.length > 1) {
        flush();
        stack.pop();
        const rest = t.slice(10).trim();
        lines = rest ? [...lines.slice(0, i), rest, ...lines.slice(i + 1)] : lines;
        if (!rest) i += 1;
        continue;
      }
      if (SEAM_FENCE_RE.test(line)) { flush(); const [pre, next] = seamFence(lines, i); top().appendChild(pre); i = next; continue; }
      const heading = /^(#{1,6})[ \t]+(.*)$/.exec(t);
      if (heading) {
        flush();
        let s = heading[2];
        while (s.endsWith("#")) s = s.slice(0, -1);
        const h = seamEl("div", `myclaude-seam-h myclaude-seam-h${heading[1].length}`);
        seamInline(s.trim(), h);
        top().appendChild(h);
        i += 1;
        continue;
      }
      if (seamHr(t)) { flush(); top().appendChild(seamEl("hr")); i += 1; continue; }
      if (t.startsWith(">")) {
        flush();
        const inner = [];
        while (i < lines.length && lines[i].trim().startsWith(">")) {
          const s = lines[i].trim().slice(1);
          inner.push(s.startsWith(" ") ? s.slice(1) : s);
          i += 1;
        }
        const quote = seamEl("blockquote");
        if (depth < SEAM_DEPTH_MAX) seamBlocksInto(inner, quote, depth + 1); else quote.textContent = inner.join("\n");
        top().appendChild(quote);
        continue;
      }
      if (t.includes("|") && i + 1 < lines.length && seamTableSep(lines[i + 1])) { flush(); i = seamTable(lines, i, top()); continue; }
      if (SEAM_ITEM_RE.test(line)) { flush(); i = seamList(lines, i, top()); continue; }
      para.push(line);
      i += 1;
    }
    flush();
  };
  const seamMarkdown = (text, into = seamEl("div", "myclaude-seam-md")) => {
    const src = String(text ?? "");
    if (src.length > SEAM_TEXT_MAX) { into.appendChild(seamEl("div", "myclaude-seam-plain", src)); return into; }
    seamBlocksInto(src.replace(/\r\n?/g, "\n").split("\n"), into, 0);
    return into;
  };

  // ---- вид хода ----
  const seamPlural = n => {
    const a = n % 10;
    const b = n % 100;
    return a === 1 && b !== 11 ? "действие" : a >= 2 && a <= 4 && (b < 12 || b > 14) ? "действия" : "действий";
  };
  // Классы живых узлов ленты: ответ (.prose) и пузырь вопроса — без data-* и без классов строк Claude.
  // Переменные CSS Claude живут на строке ленты ([data-cds=…]), вне её не определены: пузырь без них — плоская
  // полоса, абзацы — без отступов строки (стенд WF303). Значения — с живой строки на корень шва, нет живой — запас.
  const SEAM_ROW_VARS = {
    "--cds-assistant-message-text-inset": ["a", "4px"],
    "--cds-assistant-message-text-stop": ["a", "clamp(0px, (100% - 384px) * .175, 56px)"],
    "--cds-message-bubble-radius": ["u", "12px"],
    "--cds-message-bubble-pad-x": ["u", "16px"],
    "--cds-message-bubble-pad-y": ["u", "12px"],
    "--cds-message-bubble-measure": ["u", "85%"],
  };
  const seamLook = feed => {
    let prose = null;
    let bubble = null;
    let rowA = null;
    let rowU = null;
    let strong = null;
    try { prose = feed?.querySelector('[data-cds="Prose"]'); } catch {}
    try { bubble = feed?.querySelector('[data-cds="UserMessage"] > div'); } catch {}
    try { rowA = feed?.querySelector('[data-cds="AssistantMessage"]'); } catch {}
    try { rowU = feed?.querySelector('[data-cds="UserMessage"]'); } catch {}
    try { strong = prose?.querySelector("strong, b"); } catch {}
    let proseCls = seamClasses(prose?.className) || SEAM_PROSE_FALLBACK;
    if (!proseCls.split(" ").includes("prose")) proseCls = `prose ${proseCls}`;
    const read = (node, name) => { try { return node ? String(getComputedStyle(node).getPropertyValue(name) ?? "").trim() : ""; } catch { return ""; } };
    const vars = {};
    for (const [name, [from, fallback]] of Object.entries(SEAM_ROW_VARS)) vars[name] = read(from === "a" ? rowA : rowU, name) || fallback;
    // Ширина пузыря у Claude — своим style на узле (замер стенда: 479 px при 85 %): берём её, если есть.
    const measure = String(bubble?.style?.maxWidth ?? "").trim();
    if (/^\d+(\.\d+)?px$/.test(measure)) vars["--cds-message-bubble-measure"] = measure;
    // Размер и межстрочный заголовков — переменные живого ответа (у h1/h2 — calc(1em + .125rem), правило Claude по
    // [data-cds-reply-type] [data-cds=Prose]); наш .prose без data-* берёт умолчания .prose (1.75em / 1.375em) —
    // заголовки шва в полтора раза крупнее живых (стенд WF303). Кладутся на каждый .prose шва (seamProse).
    for (let level = 1; level <= 6; level += 1) {
      for (const name of [`--_prose-h${level}-size`, `--_prose-h${level}-leading`]) {
        const value = read(prose ?? rowA, name);
        if (value) vars[name] = value;
      }
    }
    // Вес жирного в ответе — со своего правила Claude по [data-cds-reply-type] (501, не 600).
    const weight = read(strong, "font-weight");
    if (/^\d{3}$/.test(weight)) vars["--myclaude-seam-strong-w"] = weight;
    return { prose: proseCls, font: prose?.getAttribute?.("data-prose-font") || "sans", bubble: seamClasses(bubble?.className) || SEAM_BUBBLE_FALLBACK, vars };
  };
  const seamLookApply = () => {
    const root = seamState.root;
    const vars = seamState.look?.vars;
    if (!root || !vars) return;
    for (const [name, value] of Object.entries(vars)) root.style.setProperty(name, value);
  };
  const seamProse = (text, look) => {
    const prose = seamEl("div", look.prose);
    prose.setAttribute("data-prose-font", look.font);
    for (const [name, value] of Object.entries(look.vars ?? {})) if (name.startsWith("--_prose-")) prose.style.setProperty(name, value);
    seamMarkdown(text, prose);
    return prose;
  };
  // Стартовое сообщение renew (#10904): ответ прежнего чата до «———» — вёрсткой ответа (#11399), низ — текстом.
  const seamLastAnswer = text => {
    if (!USER_FOLD_LAST.test(text)) return null;
    const lines = text.split("\n");
    const cut = lines.findIndex(line => line.trim() === USER_FOLD_CUT);
    if (cut < 2) return null;
    return { title: lines[0], head: lines.slice(1, cut).join("\n").trim(), rest: lines.slice(cut + 1).join("\n").trim() };
  };
  const seamTurnNode = (turn, look) => {
    const box = seamEl("div", "myclaude-seam-turn");
    if (turn.q) {
      const row = seamEl("div", "myclaude-seam-q");
      const when = chainWhen(turn.at);
      if (when) row.appendChild(seamEl("div", "myclaude-seam-when", when));
      const bubble = seamEl("div", look.bubble);
      const body = seamEl("div", "myclaude-seam-qtext");
      const text = turn.q.text;
      if (text && userFoldLong(text)) {
        const d = seamEl("details", "myclaude-seam-fold myclaude-seam-qfold");
        const last = seamLastAnswer(text);
        d.appendChild(seamEl("summary", "myclaude-seam-fold-head", userFoldLead(last ? last.title : text)));
        if (last) d.appendChild(seamProse(last.head, look));
        d.appendChild(seamEl("div", "myclaude-seam-qfull", last ? last.rest : text));
        body.appendChild(d);
      } else if (text) body.textContent = text;
      for (let k = 0; k < turn.q.images; k += 1) body.appendChild(seamEl("span", "myclaude-seam-pic", SEAM_TEXT.image));
      bubble.appendChild(body);
      row.appendChild(bubble);
      box.appendChild(row);
    }
    for (const ap of turn.aps) {
      if (ap.note) box.appendChild(seamEl("div", "myclaude-seam-note", `⚙ ${ap.note}`));
      if (ap.tools || ap.work.length) {
        const d = seamEl("details", "myclaude-seam-fold myclaude-seam-work");
        d.appendChild(seamEl("summary", "myclaude-seam-fold-head", ap.tools ? `${SEAM_TEXT.work} · ${ap.tools} ${seamPlural(ap.tools)}` : SEAM_TEXT.work));
        const body = seamEl("div", "myclaude-seam-fold-body");
        for (const text of ap.work) body.appendChild(seamProse(text, look));
        d.appendChild(body);
        box.appendChild(d);
      }
      if (ap.answer) {
        // «message-row» в имени класса — для слоя размера Пимпа (раздел 4: [class*="message-row"] … .prose);
        // MESSAGE_ROW_SELECTOR (group/message-row) его не видит.
        const a = seamEl("div", "myclaude-seam-a myclaude-seam-message-row");
        a.appendChild(seamProse(ap.answer, look));
        box.appendChild(a);
      }
    }
    return box;
  };

  // ---- шаг колеса (чистая функция; люк — HATCH.seamWheelStep) ----
  // s — {phase, h, H, owned, lastAt}; e — {dy (px, вниз > 0), t, atTop, ready, innerTop, innerMax}.
  // Ответ: {s, prevent, feedBy, innerBy, pin}: feedBy/innerBy — сдвиг scrollTop ленты/блока, pin — блок к низу.
  const seamWheelStep = (s, e) => {
    const n = { phase: s.phase, h: s.h, H: s.H, owned: s.owned, lastAt: e.t };
    const out = { s: n, prevent: false, feedBy: 0, innerBy: 0, pin: false };
    const gap = e.t - s.lastAt;
    if (n.owned && gap >= SEAM_GESTURE_END_MS) n.owned = false;
    const dy = Number(e.dy) || 0;
    // Сдвиг h на d (вверх — рост): дошли до H — «внутри», остаток — в блок; до 0 — закрыт, остаток — в ленту.
    const move = d => {
      const was = n.phase;
      const h = n.h + d;
      if (h >= n.H) {
        n.phase = "inside";
        n.h = n.H;
        out.innerBy = -(h - n.H);
        if (was !== "inside") out.pin = true;
      } else if (h <= 0) {
        n.phase = "idle";
        n.h = 0;
        out.feedBy = -h;
      } else {
        n.phase = "reveal";
        n.h = h;
        if (was !== "reveal") out.pin = true;
      }
      return out;
    };
    if (!dy || n.H <= 0) return out;
    if (n.phase === "idle") {
      if (n.owned) {
        out.prevent = true;
        if (dy < 0 && e.atTop && e.ready) return move(-dy);
        out.feedBy = dy;
        return out;
      }
      if (dy < 0 && e.atTop && e.ready && gap >= SEAM_QUIET_MS) { n.owned = true; out.prevent = true; return move(-dy); }
      return out;
    }
    if (n.phase === "reveal") { n.owned = true; out.prevent = true; return move(-dy); }
    // inside: блок крутится сам; наш жест — крутим сами; у низа блока вниз — шов съезжает.
    const room = Math.max(0, (Number(e.innerMax) || 0) - (Number(e.innerTop) || 0));
    if (dy > 0 && room <= 1) { n.owned = true; out.prevent = true; return move(-dy); }
    if (n.owned) {
      out.prevent = true;
      if (dy > 0 && dy > room) { out.innerBy = room; const rest = move(-(dy - room)); rest.innerBy = room; return rest; }
      out.innerBy = dy;
    }
    return out;
  };

  // ---- состояние ----
  const seamLive = chainLive;
  const seamState = {
    chat: "", prev: "", phase: "idle", h: 0, H: 0, T: 0, B: 0, owned: false, lastAt: -Infinity,
    tails: new Map(), busy: null, segs: [], built: false, ceiling: false, start: false, loads: 0, lastLoadMs: null,
    error: null, retryAt: 0, disposed: false, feed: null, armed: null, root: null, pane: null, col: null, top: null,
    home: null, raf: 0, box: null, look: null, idleAt: -Infinity, humanAt: -Infinity,
  };
  const seamSafe = fn => (...args) => {
    try { return fn(...args); } catch (error) { seamState.error = String(error?.message ?? error).slice(0, 160); return undefined; }
  };
  const seamBrief = id => {
    if (chainState.links?.prev?.id === id) return chainState.links.prev;
    return chainBrief(chainState.list?.find(s => s?.sessionId === id)) ?? { id, title: "", at: NaN };
  };
  const seamOlder = id => {
    const ids = chainState.links?.ids ?? [];
    const k = ids.indexOf(id);
    return k > 0 ? seamBrief(ids[k - 1]) : null;
  };
  const seamTurnCount = () => seamState.segs.reduce((n, seg) => n + seg.turns.length, 0);
  const seamTail = () => (seamState.prev ? seamState.tails.get(seamState.prev) ?? null : null);
  // Шов для чата: главное окно, /epitaxy/, у чата есть прошлый по линии (не боковой), API, узел React над лентой,
  // нет обхода и перехода 676, хвост прошлого взят и в нём есть ходы.
  const seamEligible = () => {
    const links = chainState.links;
    if (!seamLive || !chainState.chat || !links || links.side || !links.prev || !seamApi()) return false;
    if (roamState.phase !== "idle" || chainState.going || !chainState.host) return false;
    return Boolean(seamTail()?.turns.length);
  };
  const seamCanEnter = () => seamEligible() && chainState.seamTop === chainState.chat && chainReady("up");

  // ---- данные ----
  const seamRows = res => (Array.isArray(res?.messages) ? res.messages : null);
  const seamRequest = (ask, done) => {
    if (seamState.busy) return seamState.busy;
    const t0 = now();
    // Ответ не массив — отказ в отдельном звене: его ловит обработчик ошибки ниже (повтор через SEAM_RETRY_MS).
    seamState.busy = Promise.resolve().then(ask).then(res => {
      const rows = seamRows(res);
      if (!rows) throw new Error("not-array");
      return [rows, res];
    }).then(([rows, res]) => {
      seamState.loads += 1;
      seamState.lastLoadMs = Math.round(now() - t0);
      seamState.error = null;
      if (!seamState.disposed) seamSafe(done)(rows, res);
    }, error => {
      seamState.error = String(error?.message ?? error).slice(0, 120);
      seamState.retryAt = now() + SEAM_RETRY_MS;
    }).finally(() => { seamState.busy = null; });
    return seamState.busy;
  };
  const seamFetchTail = id => {
    const api = seamApi();
    if (!api || !id) return null;
    return seamRequest(() => api.getTranscriptTail(id, SEAM_TAIL_LIMIT), rows => {
      const tail = { id, rows, hasMore: true, at: now(), turns: seamTurns(rows) };
      seamState.tails.delete(id);
      seamState.tails.set(id, tail);
      while (seamState.tails.size > SEAM_CACHE_MAX) seamState.tails.delete(seamState.tails.keys().next().value);
      // Собранный шов: свежий хвост — в низ своего чата (новые ходы — снизу, место чтения не двигаем).
      const seg = seamState.segs.find(x => x.id === id);
      if (seg && seamState.built) {
        const have = new Set(seg.rows.map(r => r?.uuid));
        seg.rows = seg.rows.concat(rows.filter(r => !have.has(r?.uuid)));
        seamSegUpdate(seg, "bottom");
      }
    });
  };
  const seamFetchHasMore = (res, rows) => res?.hasMore === true && rows.length > 0 && res?.found !== false;

  // ---- блок ----
  // Вёрстка ответа (типографика и свёртки) — и в шве, и в верхе стартового сообщения нового чата (545, #11399).
  const SEAM_MD = `:is(#${SEAM_ROOT_ID},[${USER_FOLD_ATTRIBUTE}="head"])`;
  lateRules.push(
    `${CHAIN_FEED_SELECTOR}[${SEAM_ATTRIBUTE}]{transform:translateY(var(--myclaude-seam-h,0px)) !important;clip-path:inset(var(--myclaude-seam-ct,0px) 0 var(--myclaude-seam-cb,0px) 0) !important;overflow-y:hidden !important;overscroll-behavior-y:none !important;scrollbar-gutter:stable;will-change:transform}`,
    // Закрытый шов — разложен, но не виден (visibility, не display:none): первое колесо не платит раскладкой блока, а
    // scrollTop блока ставится и до показа. Корень мимо мыши — ниже h видна и нажимается лента; мышь ловит сам блок.
    `#${SEAM_ROOT_ID}{position:fixed;display:block;visibility:hidden;overflow:hidden;z-index:2;box-sizing:border-box;margin:0;padding:0;background:transparent;pointer-events:none}`,
    `#${SEAM_ROOT_ID}:not([data-phase="idle"]){visibility:visible}`,
    `#${SEAM_ROOT_ID}>.myclaude-seam-pane{position:absolute;inset:0;overflow-x:hidden;overflow-y:hidden;overscroll-behavior:contain;transform:translateY(calc(var(--myclaude-seam-h,0px) - 100%));will-change:transform;pointer-events:auto}`,
    `#${SEAM_ROOT_ID}[data-phase="inside"]>.myclaude-seam-pane{overflow-y:auto}`,
    `#${SEAM_ROOT_ID} .myclaude-seam-col{box-sizing:border-box;min-height:100%;display:flex;flex-direction:column;justify-content:flex-end;padding-bottom:4px}`,
    `#${SEAM_ROOT_ID} .myclaude-seam-top{flex:none;height:44px;display:flex;align-items:center;justify-content:center;color:var(--cds-text-secondary,inherit);opacity:.75;font-size:12.5px}`,
    `#${SEAM_ROOT_ID} .myclaude-seam-turn{content-visibility:auto;contain-intrinsic-size:auto 400px;display:flex;flex-direction:column;gap:12px;margin-top:20px}`,
    `#${SEAM_ROOT_ID} .myclaude-seam-q{display:flex;flex-direction:column;align-items:flex-end;gap:4px}`,
    `#${SEAM_ROOT_ID} .myclaude-seam-when{font-size:11.5px;color:var(--cds-text-secondary,inherit);opacity:.7}`,
    `#${SEAM_ROOT_ID} .myclaude-seam-qtext{white-space:pre-wrap;overflow-wrap:anywhere}`,
    `#${SEAM_ROOT_ID} .myclaude-seam-pic{display:inline-block;margin:2px 6px 0 0;opacity:.8}`,
    `#${SEAM_ROOT_ID} .myclaude-seam-note{font-size:12px;color:var(--cds-text-secondary,inherit);opacity:.7;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}`,
    // Типографика ответа — правила Claude для [data-cds=AssistantMessage] [data-cds=Prose] (замер стенда WF303) на своих
    // узлах: межстрочный 1.45 и отступ 0.8em у абзацев, отступы строки, заголовки и жирный — переменными Claude.
    `${SEAM_MD} .prose :is(p,li,blockquote,.myclaude-seam-p){line-height:1.45 !important}`,
    `${SEAM_MD} .prose * + :is(p,ul,ol,blockquote,.myclaude-seam-p){margin-top:.8em !important}`,
    `${SEAM_MD} .prose :is(p,.myclaude-seam-p,.myclaude-seam-h){padding-inline-start:var(--cds-assistant-message-text-inset,0px)}`,
    `${SEAM_MD} .prose :is(p,.myclaude-seam-p,.myclaude-seam-h,ul,ol){padding-inline-end:var(--cds-assistant-message-text-stop,0px)}`,
    `${SEAM_MD} .prose :is(strong,b){font-weight:var(--myclaude-seam-strong-w,var(--cds-font-weight-bold,600))}`,
    `${SEAM_MD} .myclaude-seam-h{font-weight:var(--cds-font-weight-header,var(--cds-font-weight-semibold,580));margin:calc(var(--_prose-flow,.75em) * 2.5) 0 0}`,
    `${SEAM_MD} .myclaude-seam-h:first-child{margin-top:0}`,
    // Абзацы — по ширине с переносами, как лента (#9148, 040); выключка снята командой text-justify — влево.
    `html:not([${TEXT_JUSTIFY_ATTRIBUTE}="off"]) ${SEAM_MD} .prose p:not(:is(li, td, th, pre) p){text-align:justify;-webkit-hyphens:auto;hyphens:auto;hyphenate-limit-chars:6 2 2}`,
    `${SEAM_MD} .myclaude-seam-h1{font-size:var(--_prose-h1-size,1.6em);line-height:var(--_prose-h1-leading,1.3)}${SEAM_MD} .myclaude-seam-h2{font-size:var(--_prose-h2-size,1.35em);line-height:var(--_prose-h2-leading,1.3)}${SEAM_MD} :is(.myclaude-seam-h3,.myclaude-seam-h4,.myclaude-seam-h5,.myclaude-seam-h6){font-size:var(--_prose-h3-size,1.1em);line-height:var(--_prose-h3-leading,1.3)}`,
    `${SEAM_MD} .myclaude-seam-p{margin:0}`,
    `${SEAM_MD} :is(pre.myclaude-seam-code,.myclaude-seam-scroll){max-width:100%;overflow-x:auto}`,
    `${SEAM_MD} .myclaude-seam-plain{white-space:pre-wrap;overflow-wrap:anywhere}`,
    // Свёртки — видом раздела 12ф (540): строка с ▸/▾, тело с волоском слева.
    `${SEAM_MD} details.myclaude-seam-fold>summary{display:block;list-style:none;width:fit-content;max-width:100%;margin:6px 0;padding:2px 8px 2px 4px;border-radius:6px;font-weight:600;cursor:pointer;user-select:none;-webkit-user-select:none}`,
    `${SEAM_MD} details.myclaude-seam-fold>summary::-webkit-details-marker{display:none}`,
    `${SEAM_MD} details.myclaude-seam-fold>summary::before{content:"▸ "}${SEAM_MD} details.myclaude-seam-fold[open]>summary::before{content:"▾ "}`,
    `${SEAM_MD} details.myclaude-seam-fold>summary:hover{background:rgba(127,127,127,.14)}`,
    `${SEAM_MD} .myclaude-seam-fold-body{margin-left:6.65px;padding-left:10px;border-left:1.5px solid currentColor}`,
    // #11658 (слово Элвиса 05.11: «серо-серую полосу… убрать… как будто она здесь лишняя»): цитата прямо в теле
    // свёртки — без своей серой линии и отступа: её полоса — волосок тела, как у тела-цитаты в ответе (170, WF176).
    `${SEAM_MD} .myclaude-seam-fold-body>blockquote{border-left:0 !important;margin-left:0 !important;margin-inline-start:0 !important;padding-left:0 !important;padding-inline-start:0 !important}`,
    `#${SEAM_ROOT_ID} details.myclaude-seam-work>summary{font-weight:500;color:var(--cds-text-secondary,inherit)}`,
    `#${SEAM_ROOT_ID} .myclaude-seam-qfull{white-space:pre-wrap}#${SEAM_ROOT_ID} .myclaude-seam-qfold>.prose{white-space:normal;margin:4px 0 8px}`,
    // Полоса между чатами: волосок во всю колонку, посередине таблетка (вид 13б).
    `#${SEAM_ROOT_ID} .myclaude-seam-strip{position:relative;flex:none;display:flex;justify-content:center;margin:28px 0 8px;font-size:12.5px;line-height:18px}`,
    `#${SEAM_ROOT_ID} .myclaude-seam-strip::before{content:"";position:absolute;left:0;right:0;top:50%;border-top:1px solid var(--cds-border,rgba(127,127,127,.35))}`,
    `#${SEAM_ROOT_ID} :is(.myclaude-seam-pill,.myclaude-seam-home){position:relative;display:inline-flex;align-items:center;gap:6px;max-width:min(560px,calc(100% - 16px));height:30px;margin:0;padding:0 12px;border:1px solid var(--cds-border,rgba(127,127,127,.35));border-radius:15px;background:var(--cds-surface-1,#262624);color:var(--cds-text-primary,inherit);white-space:nowrap;overflow:hidden;cursor:pointer;font:inherit;font-size:12.5px;-webkit-app-region:no-drag}`,
    `#${SEAM_ROOT_ID} :is(.myclaude-seam-pill,.myclaude-seam-home):hover{background:color-mix(in srgb,currentColor 9%,var(--cds-surface-1,#262624))}`,
    `#${SEAM_ROOT_ID} .myclaude-seam-pill>b{flex:none;font-weight:500}#${SEAM_ROOT_ID} .myclaude-seam-pill>span{min-width:0;overflow:hidden;text-overflow:ellipsis}#${SEAM_ROOT_ID} .myclaude-seam-pill>i{flex:none;font-style:normal;opacity:.75}`,
    `#${SEAM_ROOT_ID}>.myclaude-seam-home{position:absolute;right:16px;bottom:var(--myclaude-seam-home-bottom,12px);display:none;box-shadow:0 2px 10px rgba(0,0,0,.18);pointer-events:auto}`,
    `#${SEAM_ROOT_ID}[data-phase="inside"]>.myclaude-seam-home{display:inline-flex}`,
  );
  const seamPill = (label, title, date, go) => {
    const b = seamEl("button", "myclaude-seam-pill");
    b.type = "button";
    if (go) b.setAttribute(SEAM_GO_ATTRIBUTE, go);
    b.appendChild(seamEl("b", "", label));
    if (title) b.appendChild(seamEl("span", "", title));
    if (date) b.appendChild(seamEl("i", "", date));
    return b;
  };
  const seamStrip = seg => {
    const strip = seamEl("div", "myclaude-seam-strip");
    strip.appendChild(seamPill(SEAM_TEXT.prev, chainQuoted(seg.title), chainWhen(seg.at), seg.id));
    return strip;
  };
  // Верх блока — постоянной высоты (подгрузка не двигает ходы): «Загружаю…», потолок «Открыть «…»», начало линии.
  const seamTopPaint = () => {
    const top = seamState.top;
    if (!top) return;
    const ceiling = seamState.ceiling ? seamCeilingTarget() : null;
    const print = ceiling ? `c:${ceiling.id}` : seamState.busy ? "l" : seamState.start ? "s" : "";
    if (top.getAttribute("data-print") === print) return;
    top.setAttribute("data-print", print);
    top.textContent = "";
    if (ceiling) top.appendChild(seamPill(SEAM_TEXT.open.replace("{t}", chainQuoted(ceiling.title)), "", "", ceiling.id));
    else if (print === "l") top.textContent = SEAM_TEXT.loading;
    else if (print === "s") top.textContent = SEAM_TEXT.start;
  };
  const seamCeilingTarget = () => {
    const first = seamState.segs[0];
    if (!first) return null;
    return first.hasMore ? seamBrief(first.id) : seamOlder(first.id);
  };
  const seamBuild = () => {
    const feed = seamState.feed;
    const tail = seamTail();
    if (seamState.built || !feed || !tail) return seamState.built;
    seamState.look = seamLook(feed);
    let root = seamState.root;
    if (!root) {
      root = seamEl("div", "epitaxy-transcript-typography myclaude-seam");
      root.id = SEAM_ROOT_ID;
      root.setAttribute("data-phase", "idle");
      const pane = seamEl("div", "myclaude-seam-pane");
      const col = seamEl("div", "myclaude-seam-col");
      const top = seamEl("div", "myclaude-seam-top");
      col.appendChild(top);
      pane.appendChild(col);
      root.appendChild(pane);
      const home = seamPill(SEAM_TEXT.home, "", "", "");
      home.className = "myclaude-seam-home";
      home.setAttribute(SEAM_HOME_ATTRIBUTE, "");
      root.appendChild(home);
      Object.assign(seamState, { root, pane, col, top, home });
    }
    // Соседом скроллера: наследует шрифт, цвет и переменные колонки ленты.
    const parent = feed.parentElement ?? document.body ?? document.documentElement;
    if (root.parentNode !== parent) parent.insertBefore(root, feed.nextSibling);
    seamLookApply();
    // Место — до ходов: блок раскладывается сразу своей шириной, пока закрыт.
    seamPlace();
    const brief = chainState.links.prev;
    const seg = { id: brief.id, title: brief.title, at: brief.at, rows: tail.rows.slice(), hasMore: tail.hasMore, turns: [], sigs: [], nodes: [], el: null, strip: null };
    seamSegMount(seg, null);
    seamState.segs = [seg];
    seamState.built = true;
    seamState.ceiling = false;
    seamState.start = false;
    seamArmRoot(true);
    seamTopPaint();
    return true;
  };
  // Новый чат в блоке: его ходы и полоса под ним; before — узел, перед которым встать (null — в самый низ).
  const seamSegMount = (seg, before) => {
    seg.el = seamEl("div", "myclaude-seam-chat");
    seg.strip = seamStrip(seg);
    seg.turns = seamTurns(seg.rows);
    seg.sigs = seg.turns.map(t => JSON.stringify(t));
    seg.nodes = seg.turns.map(t => seamTurnNode(t, seamState.look));
    for (const node of seg.nodes) seg.el.appendChild(node);
    seamState.col.insertBefore(seg.el, before);
    seamState.col.insertBefore(seg.strip, before);
  };
  // Ходы чата поменялись (порция сверху, свежий хвост снизу): меняем только разошедшиеся; сверху — блок не прыгает.
  const seamSegUpdate = (seg, where) => {
    const pane = seamState.pane;
    const beforeH = Number(pane?.scrollHeight) || 0;
    const beforeTop = Number(pane?.scrollTop) || 0;
    const turns = seamTurns(seg.rows);
    const sigs = turns.map(t => JSON.stringify(t));
    let p = 0;
    while (p < seg.sigs.length && p < sigs.length && seg.sigs[p] === sigs[p]) p += 1;
    let q = 0;
    while (q < seg.sigs.length - p && q < sigs.length - p && seg.sigs[seg.sigs.length - 1 - q] === sigs[sigs.length - 1 - q]) q += 1;
    const anchor = seg.nodes[seg.sigs.length - q] ?? null;
    for (const node of seg.nodes.slice(p, seg.sigs.length - q)) node.remove();
    const fresh = turns.slice(p, turns.length - q).map(t => seamTurnNode(t, seamState.look));
    for (const node of fresh) seg.el.insertBefore(node, anchor);
    seg.nodes = [...seg.nodes.slice(0, p), ...fresh, ...seg.nodes.slice(seg.sigs.length - q)];
    seg.turns = turns;
    seg.sigs = sigs;
    seamAfterChange(where, beforeH, beforeTop);
  };
  const seamAfterChange = (where, beforeH, beforeTop) => {
    const pane = seamState.pane;
    if (!pane) return;
    if (seamState.phase === "reveal") { pane.scrollTop = pane.scrollHeight; return; }
    if (where === "top") pane.scrollTop = beforeTop + ((Number(pane.scrollHeight) || 0) - beforeH);
  };
  // Потолок и по строкам: в агентской сессии ходов мало, а строк (инструменты) — тысячи; разбор — по всем строкам.
  const seamRowCount = () => seamState.segs.reduce((n, seg) => n + seg.rows.length, 0);
  const seamCeilingHit = () => seamState.segs.length >= SEAM_MAX_CHATS || seamTurnCount() >= SEAM_MAX_TURNS || seamRowCount() >= SEAM_MAX_ROWS;
  // У верха блока ближе SEAM_LOAD_SCREENS экрана — порция того же чата, кончился — хвост чата выше по линии.
  const seamMaybeLoad = () => {
    const pane = seamState.pane;
    if (seamState.phase === "idle" || !seamState.built || !pane || seamState.busy || seamState.ceiling || seamState.start) return;
    if (now() < seamState.retryAt) return;
    if (!(Number(pane.scrollTop) < SEAM_LOAD_SCREENS * (Number(pane.clientHeight) || 0))) return;
    const api = seamApi();
    const first = seamState.segs[0];
    if (!api || !first) return;
    if (first.hasMore) {
      const uuid = first.rows.find(r => typeof r?.uuid === "string" && r.uuid)?.uuid;
      if (!uuid || typeof api.getTranscriptPage !== "function") { first.hasMore = false; return; }
      seamRequest(() => api.getTranscriptPage(first.id, uuid, SEAM_PAGE_LIMIT), (rows, res) => {
        if (!seamState.built || seamState.segs[0] !== first) return;
        const have = new Set(first.rows.map(r => r?.uuid));
        const fresh = rows.filter(r => !have.has(r?.uuid));
        // Порция из одних виденных строк — дальше этого чата не пройти: к чату выше по линии.
        first.hasMore = seamFetchHasMore(res, rows) && fresh.length > 0;
        first.rows = fresh.concat(first.rows);
        seamSegUpdate(first, "top");
        if (seamCeilingHit()) seamState.ceiling = true;
        seamTopPaint();
      });
      seamTopPaint();
      return;
    }
    if (seamCeilingHit()) { seamState.ceiling = true; seamTopPaint(); return; }
    const older = seamOlder(first.id);
    if (!older) { seamState.start = true; seamTopPaint(); return; }
    seamRequest(() => api.getTranscriptTail(older.id, SEAM_TAIL_LIMIT), (rows, res) => {
      if (!seamState.built || seamState.segs[0] !== first) return;
      const beforeH = Number(seamState.pane?.scrollHeight) || 0;
      const beforeTop = Number(seamState.pane?.scrollTop) || 0;
      const seg = { id: older.id, title: older.title, at: older.at, rows, hasMore: res?.hasMore === true && rows.length > 0, turns: [], sigs: [], nodes: [], el: null, strip: null };
      seamSegMount(seg, first.el);
      seamState.segs.unshift(seg);
      seamAfterChange("top", beforeH, beforeTop);
      if (seamCeilingHit()) seamState.ceiling = true;
      seamTopPaint();
    });
    seamTopPaint();
  };
  // Снять подгруженное (DOM блока и чаты выше), хвост прошлого — остаётся в кэше.
  const seamUnload = () => {
    seamArmRoot(false);
    try { seamState.root?.remove(); } catch {}
    for (const seg of seamState.segs) { try { seg.el?.remove(); seg.strip?.remove(); } catch {} }
    seamState.segs = [];
    seamState.built = false;
    seamState.ceiling = false;
    seamState.start = false;
    if (seamState.top) { seamState.top.textContent = ""; seamState.top.removeAttribute("data-print"); }
  };

  // ---- место и вид ----
  // Видимая часть ленты (без строки заголовка, до верха поля) — без нашего сдвига.
  const seamMeasure = el => {
    const shifted = el.hasAttribute(SEAM_ATTRIBUTE);
    if (shifted) el.style.setProperty("--myclaude-seam-h", "0px");
    const box = chainVisibleBox(el);
    const r = el.getBoundingClientRect();
    if (shifted) el.style.setProperty("--myclaude-seam-h", `${Math.round(seamState.h)}px`);
    return { box, r };
  };
  const seamPlace = () => {
    const el = seamState.feed;
    const root = seamState.root;
    if (!el || !root) return;
    const { box, r } = seamMeasure(el);
    seamState.H = Math.max(0, Math.round(box.bottom - box.top));
    seamState.T = Math.max(0, Math.round(box.top - r.top));
    seamState.B = Math.max(0, Math.round(r.bottom - box.bottom));
    seamState.box = { left: Math.round(r.left), width: Math.round(r.width), height: Math.round(r.height), prompt: seamPromptTop(el) };
    root.style.left = `${Math.round(box.left)}px`;
    root.style.top = `${Math.round(box.top)}px`;
    root.style.width = `${Math.round(box.width)}px`;
    root.style.height = `${seamState.H}px`;
    // Корень — сосед скроллера, а у предков Claude contain/container-type (плитки): fixed считается от них, не от окна.
    // Колонка сдвинута (панель материалов слева 12п⁴, открытая боковая панель) — координаты окна уехали бы на этот
    // сдвиг вправо, блок — мимо ленты, жест — в пустоту над ней. Поправка замером (не разложен — нечего мерить).
    const at = root.getBoundingClientRect();
    const laid = at.width > 0 || at.height > 0;
    const dx = laid ? Math.round(at.left - box.left) : 0;
    const dy = laid ? Math.round(at.top - box.top) : 0;
    if (dx) root.style.left = `${Math.round(box.left) - dx}px`;
    if (dy) root.style.top = `${Math.round(box.top) - dy}px`;
    // Колонка — краями строки сообщения ленты (без отступов обёртки колонки: стенд — 20/28 px), её нет — колонкой.
    let c = null;
    try {
      for (const row of el.querySelectorAll('[data-cds="AssistantMessage"], [data-cds="UserMessage"]')) {
        const rr = row.getBoundingClientRect();
        if (rr.width > 0 && rr.height > 0) { c = rr; break; }
      }
    } catch {}
    if (!c) {
      let column = null;
      try { column = el.querySelector(".epitaxy-transcript-column") ?? el.querySelector('[data-testid="transcript-rows"]'); } catch {}
      c = column?.getBoundingClientRect?.() ?? null;
    }
    const col = seamState.col;
    if (c && c.width > 0) {
      col.style.marginLeft = `${Math.round(c.left - box.left)}px`;
      col.style.width = `${Math.round(c.width)}px`;
      col.style.removeProperty("padding");
    } else {
      col.style.removeProperty("margin-left");
      col.style.width = "auto";
      col.style.padding = "0 16px 4px";
    }
    if (seamState.phase === "inside") seamState.h = seamState.H;
    else if (seamState.h > seamState.H) seamState.h = seamState.H;
    seamHomePlace();
    // Видимой ленты не осталось (поле ввода выросло до заголовка) — шов закрыт, у ленты не остаётся overflow:hidden.
    if (seamState.H <= 0 && seamState.phase !== "idle") seamClose();
  };
  // Верх поля ввода — сторож его роста (набор ответа при открытом шве): сменился — место пересчитать.
  const seamPromptTop = el => {
    try {
      const panel = el.closest?.(".epitaxy-chat-panel") ?? null;
      const p = (panel?.querySelector(".epitaxy-prompt") ?? document.querySelector(".epitaxy-prompt"))?.getBoundingClientRect();
      return p && p.height > 0 ? Math.round(p.top) : null;
    } catch { return null; }
  };
  // «↓ К этому чату» не накрывает «непрочитанные N» (12х): та у правого края над полем — встаём выше.
  const seamHomePlace = () => {
    const root = seamState.root;
    if (!root) return;
    let lift = 12;
    try {
      const read = document.getElementById(READ_NEXT_ID)?.getBoundingClientRect();
      const at = root.getBoundingClientRect();
      const top = at.width > 0 || at.height > 0 ? at.top : Number.parseFloat(root.style.top) || 0;
      if (read && read.width > 0 && read.height > 0 && read.top < top + seamState.H) lift = Math.max(12, Math.round(top + seamState.H - read.top + 8));
    } catch {}
    root.style.setProperty("--myclaude-seam-home-bottom", `${lift}px`);
  };
  // Сдвиг на каждое событие — только переменные (трансформ, без раскладки).
  const seamPaint = () => {
    const el = seamState.feed;
    const root = seamState.root;
    const h = Math.round(seamState.h);
    if (seamState.phase === "idle" || !el) {
      if (el) seamFeedClear(el);
      if (root && root.getAttribute("data-phase") !== "idle") root.setAttribute("data-phase", "idle");
      chainState.seamPhase = "idle";
      return;
    }
    if (!el.hasAttribute(SEAM_ATTRIBUTE)) el.setAttribute(SEAM_ATTRIBUTE, "");
    el.style.setProperty("--myclaude-seam-ct", `${seamState.T}px`);
    el.style.setProperty("--myclaude-seam-h", `${h}px`);
    el.style.setProperty("--myclaude-seam-cb", `${seamState.B + h}px`);
    if (root) {
      root.style.setProperty("--myclaude-seam-h", `${h}px`);
      if (root.getAttribute("data-phase") !== seamState.phase) root.setAttribute("data-phase", seamState.phase);
    }
    chainState.seamPhase = seamState.phase;
  };
  const seamFeedClear = el => {
    if (!el) return;
    el.removeAttribute(SEAM_ATTRIBUTE);
    for (const name of ["--myclaude-seam-h", "--myclaude-seam-ct", "--myclaude-seam-cb"]) el.style.removeProperty(name);
  };
  // Открыть: собран, на месте, хвост не старше SEAM_STALE_MS.
  const seamOpen = () => {
    if (!seamBuild()) return false;
    seamPlace();
    const tail = seamTail();
    if (tail && now() - tail.at > SEAM_STALE_MS) seamFetchTail(tail.id);
    return seamState.H > 0;
  };
  const seamClose = () => {
    seamHomeStop();
    if (seamState.phase !== "idle") seamState.idleAt = now();
    seamState.phase = "idle";
    seamState.h = 0;
    seamState.owned = false;
    seamPaint();
  };

  // ---- колесо ----
  const seamOwn = () => { feedHold.ownUntil = Math.max(feedHold.ownUntil, now() + SEAM_OWN_MS); };
  const onSeamWheel = event => {
    const el = seamState.feed;
    if (!el || seamState.disposed || event?.ctrlKey) return;
    const dy = chainDelta(event, el);
    if (!dy || Math.abs(Number(event.deltaX) || 0) > Math.abs(dy)) return;
    const pane = seamState.pane;
    const node = event.target;
    const inBlock = Boolean(seamState.root?.contains?.(node));
    // Над лентой — вложенный блок, который сам ещё крутится (вывод инструмента), — его жест.
    if (seamState.phase === "idle" && !seamState.owned && !inBlock && chainNestedTakes(node, el, dy)) { seamState.lastAt = now(); return; }
    if (seamState.phase !== "idle") seamHomeStop();
    const wasIdle = seamState.phase === "idle";
    // Открыть (замер места) — только если шаг может войти: новый жест после паузы или свой жест; хвосты инерции — мимо.
    const gap = now() - seamState.lastAt;
    const mayEnter = gap >= SEAM_QUIET_MS || (seamState.owned && gap < SEAM_GESTURE_END_MS);
    let ready = false;
    if (wasIdle && dy < 0 && mayEnter && chainAtTop(el)) {
      ready = seamCanEnter() && seamOpen();
    }
    const step = seamWheelStep(seamState, {
      dy, t: now(), atTop: chainAtTop(el), ready,
      innerTop: Number(pane?.scrollTop) || 0, innerMax: Math.max(0, (Number(pane?.scrollHeight) || 0) - (Number(pane?.clientHeight) || 0)),
    });
    Object.assign(seamState, step.s);
    if (step.prevent) { event.preventDefault?.(); chainState.seamHeld = now() + SEAM_GESTURE_END_MS; }
    if (!wasIdle && seamState.phase === "idle") seamState.idleAt = now();
    // Сперва показать (фаза на корне), потом крутить блок: скрытому узлу scrollTop может не встать (стенд WF303).
    seamPaint();
    if (step.pin && pane) pane.scrollTop = pane.scrollHeight;
    if (step.innerBy && pane) pane.scrollTop = (Number(pane.scrollTop) || 0) + step.innerBy;
    if (step.feedBy) { seamOwn(); el.scrollTop = (Number(el.scrollTop) || 0) + step.feedBy; }
    if (seamState.phase !== "idle") { seamOwn(); seamMaybeLoad(); }
  };
  // Блокирующий слушатель (passive:false) — только на ленте у верха и на блоке и только пока шов взведён.
  const SEAM_WHEEL_OPTIONS = { passive: false };
  const seamArmFeed = el => {
    const armed = seamState.armed;
    if (armed === el) return;
    if (armed) { try { armed.removeEventListener("wheel", onSeamWheelSafe, SEAM_WHEEL_OPTIONS); } catch {} }
    seamState.armed = el ?? null;
    if (el) el.addEventListener("wheel", onSeamWheelSafe, SEAM_WHEEL_OPTIONS);
  };
  let seamRootArmed = null;
  const seamArmRoot = yes => {
    const root = yes ? seamState.root : null;
    if (seamRootArmed === root) return;
    if (seamRootArmed) { try { seamRootArmed.removeEventListener("wheel", onSeamWheelSafe, SEAM_WHEEL_OPTIONS); } catch {} }
    seamRootArmed = root;
    if (root) root.addEventListener("wheel", onSeamWheelSafe, SEAM_WHEEL_OPTIONS);
  };
  const onSeamWheelSafe = seamSafe(onSeamWheel);
  // Взвод: шов годен для чата, лента ближе экрана к верху (или шов открыт).
  const seamArmCheck = () => {
    const el = seamState.feed;
    const near = Boolean(el) && chainState.seamTop === chainState.chat && Boolean(chainState.chat)
      && (seamState.phase !== "idle" || (Number(el.scrollTop) || 0) < (Number(el.clientHeight) || 0));
    seamArmFeed(near ? el : null);
    if (near && !seamState.built) seamBuild();
  };
  // Сверх хвоста подгружено: ещё порции прошлого чата или чаты выше по линии.
  const seamExtra = () => {
    const tail = seamTail();
    return seamState.segs.length > 1 || Boolean(tail && seamState.segs[0] && seamState.segs[0].rows.length > tail.rows.length);
  };
  const seamUnloadCheck = () => {
    const el = seamState.feed;
    if (!seamState.built || seamState.phase !== "idle" || !el) return;
    if ((Number(el.scrollTop) || 0) > SEAM_UNLOAD_SCREENS * (Number(el.clientHeight) || 0)) { seamUnload(); return; }
    // Короткий чат вниз дальше не уходит: закрыт и помолчал — подгруженное сверх хвоста снято, хвост соберётся снова.
    if (now() - seamState.idleAt >= SEAM_SHED_MS && seamExtra()) seamUnload();
  };

  // ---- «↓ К этому чату» ----
  const seamHomeStop = () => { if (seamState.raf) { cancelAnimationFrame(seamState.raf); seamState.raf = 0; } };
  const seamHome = () => {
    if (seamState.phase === "idle") return;
    seamHomeStop();
    const pane = seamState.pane;
    if (pane) pane.scrollTop = pane.scrollHeight;
    const from = seamState.h;
    const start = now();
    seamState.phase = "reveal";
    seamState.owned = false;
    const frame = seamSafe(() => {
      seamState.raf = 0;
      const p = Math.min(1, (now() - start) / SEAM_HOME_MS);
      seamState.h = from * (1 - (1 - (1 - p) ** 3));
      seamOwn();
      if (p >= 1 || seamState.h <= 0.5) { seamClose(); return; }
      seamPaint();
      seamState.raf = requestAnimationFrame(frame);
    });
    seamPaint();
    seamState.raf = requestAnimationFrame(frame);
  };

  // ---- события и тик ----
  const onSeamScroll = event => {
    const node = event?.target;
    if (!node || seamState.disposed) return;
    if (node === seamState.pane) { seamMaybeLoad(); return; }
    const el = seamState.feed;
    if (!el || node !== el) return;
    // Лента сдвинулась не нами (отправил сообщение, 12х, главы 660, «↓» Claude, End) — шов закрыт. Прилипание Claude
    // к низу, пока он пишет ответ, а человек ничего не делал, — не закрывает: читаешь прошлый чат, ответ растёт ниже.
    const sticky = chainState.host?.isResponding === true && now() - seamState.humanAt >= SEAM_HUMAN_MS;
    if (seamState.phase !== "idle" && !sticky && (Number(el.scrollTop) || 0) > CHAIN_EDGE_PX && now() >= feedHold.ownUntil) seamClose();
    seamArmCheck();
    seamUnloadCheck();
  };
  const seamEditable = node => {
    try { return Boolean(node?.closest?.('[contenteditable="true"],input,textarea,select')); } catch { return false; }
  };
  // PageUp/Home/PageDown внутри — блоку; End и ⌘↓ — закрыть шов. В поле ввода — не наше. Esc не ловим (раздел 16).
  // Действие человека: клавиша вне поля, Enter в поле (отправка), нажатие мимо шва.
  const onSeamHuman = event => {
    const node = event?.target;
    if (event?.type === "keydown") {
      if (!seamEditable(node) || (event.key === "Enter" && !event.shiftKey)) seamState.humanAt = now();
      return;
    }
    if (!seamState.root?.contains?.(node)) seamState.humanAt = now();
  };
  const onSeamKey = event => {
    onSeamHuman(event);
    if (seamState.phase === "idle" || seamEditable(event?.target)) return;
    const pane = seamState.pane;
    const key = event.key;
    if (key === "End" || (key === "ArrowDown" && event.metaKey)) { seamClose(); return; }
    if (seamState.phase !== "inside" || !pane) return;
    const page = Math.max(40, (Number(pane.clientHeight) || 0) * 0.9);
    if (key === "PageUp") pane.scrollTop = Math.max(0, (Number(pane.scrollTop) || 0) - page);
    else if (key === "Home") pane.scrollTop = 0;
    else if (key === "PageDown") pane.scrollTop = (Number(pane.scrollTop) || 0) + page;
    else return;
    event.preventDefault?.();
    seamMaybeLoad();
  };
  const onSeamClick = event => {
    const root = seamState.root;
    const node = event?.target;
    if (!root || !node || !root.contains(node)) return;
    const go = node.closest?.(`[${SEAM_GO_ATTRIBUTE}]`);
    if (go && root.contains(go)) {
      event.preventDefault();
      event.stopPropagation();
      const id = go.getAttribute(SEAM_GO_ATTRIBUTE);
      seamClose();
      chainGo(seamBrief(id), "bottom", "up");
      return;
    }
    if (node.closest?.(`[${SEAM_HOME_ATTRIBUTE}]`)) { event.preventDefault(); event.stopPropagation(); seamHome(); }
  };
  const onSeamResize = () => { if (seamState.phase !== "idle") { seamPlace(); seamPaint(); } };
  const seamReset = () => {
    seamClose();
    seamFeedClear(seamState.feed);
    seamArmFeed(null);
    seamUnload();
    seamState.feed = null;
  };
  const seamTick = seamSafe(() => {
    if (seamState.disposed) return;
    const chat = chainState.chat;
    const prev = chainState.links && !chainState.links.side ? chainState.links.prev?.id ?? "" : "";
    if (chat !== seamState.chat || prev !== seamState.prev) {
      seamReset();
      seamState.chat = chat;
      seamState.prev = prev;
      seamState.retryAt = 0;
    }
    // Хвост прошлого — заранее (данные, не DOM).
    if (prev && seamApi() && !seamState.busy && now() >= seamState.retryAt && !seamState.tails.has(prev)) seamFetchTail(prev);
    const el = chat ? chainFeed() : null;
    // Узел ленты заменён — шов с прежней снят.
    if (seamState.feed && seamState.feed !== el) seamReset();
    seamState.feed = el;
    const eligible = seamEligible();
    const top = eligible ? chat : "";
    if (chainState.seamTop !== top) { chainState.seamTop = top; chainSafe(chainRender)(); }
    if (!eligible && seamState.phase !== "idle") seamClose();
    seamArmCheck();
    if (seamState.phase !== "idle") {
      // Широкий вид 090 и прочие сдвиги колонки — пересчёт места.
      // Поле ввода или лента выросли или сжались — тоже (H, обрезка снизу, место «↓ К этому чату»).
      const r = el?.getBoundingClientRect?.();
      const b = seamState.box;
      if (r && b && (Math.round(r.left) !== b.left || Math.round(r.width) !== b.width || Math.round(r.height) !== b.height || seamPromptTop(el) !== b.prompt)) { seamPlace(); seamPaint(); }
      seamMaybeLoad();
    }
    seamTopPaint();
    seamUnloadCheck();
    chainState.seamPhase = seamState.phase;
  });
  // Сирота прошлой установки — снять до своей.
  try {
    for (const node of document.querySelectorAll(`#${SEAM_ROOT_ID}`)) node.remove();
    for (const node of document.querySelectorAll(`[${SEAM_ATTRIBUTE}]`)) seamFeedClear(node);
  } catch {}
  track(() => {
    seamState.disposed = true;
    seamHomeStop();
    try { seamFeedClear(seamState.feed); } catch {}
    try { for (const node of document.querySelectorAll(`[${SEAM_ATTRIBUTE}]`)) seamFeedClear(node); } catch {}
    seamArmFeed(null);
    seamArmRoot(false);
    try { seamState.root?.remove(); } catch {}
    try { for (const node of document.querySelectorAll(`#${SEAM_ROOT_ID}`)) node.remove(); } catch {}
    seamState.segs = [];
    seamState.built = false;
    chainState.seamTop = "";
    chainState.seamPhase = "idle";
    chainState.seamHeld = -Infinity;
  });
  if (seamLive) {
    on(window, "scroll", seamSafe(onSeamScroll), { capture: true, passive: true });
    on(window, "keydown", seamSafe(onSeamKey), true);
    on(window, "pointerdown", seamSafe(onSeamHuman), { capture: true, passive: true });
    on(document, "click", seamSafe(onSeamClick), true);
    on(window, "resize", seamSafe(onSeamResize));
    const seamTimer = setInterval(seamTick, SEAM_TICK_MS);
    track(() => clearInterval(seamTimer));
    seamTick();
  }
  // Шов (раздел 13в): годен ли для чата, фаза и сдвиг, что собрано, подгрузки, ошибка.
  statusPart("seam", () => ({
    on: Boolean(chainState.chat) && chainState.seamTop === chainState.chat, chat: seamState.chat || null, prev: seamState.prev || null,
    phase: seamState.phase, h: Math.round(seamState.h), H: seamState.H, ready: seamCanEnter(), armed: Boolean(seamState.armed),
    chats: seamState.segs.length, turns: seamState.built ? seamTurnCount() : seamTail()?.turns.length ?? 0,
    nodes: seamState.segs.reduce((n, seg) => n + seg.nodes.length, 0), ceiling: seamState.ceiling, start: seamState.start,
    loading: Boolean(seamState.busy), loads: seamState.loads, lastLoadMs: seamState.lastLoadMs, error: seamState.error,
  }));
  HATCH && Object.assign(HATCH, { seamTurns, seamMarkdown, seamState, seamWheelStep, seamTurnNode, seamLastAnswer });
