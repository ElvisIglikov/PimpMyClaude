  // ---- 12ф. Свёртки <details> (#9065, WF135) --------------------------------
  // Файл 29, вариант 1.1: Desktop не рисует <details> — теги видны текстом в
  // отдельных <p>. Страница делает из них настоящую свёртку: перед сырым <p>
  // открытия — свой заголовок role=button (подпись — из атрибута, копия и
  // выделение её не видят), сырые <p> открытия, <summary> и </details> —
  // display:none, тело между ними — меткой closed|open. React-узлы не
  // переносим и текст им не меняем; закрывающего нет — тег без пары в
  // законченном ответе не трогаем, а в ответе, который ещё пишется, свёртка
  // встаёт сразу и прячет всё после тега (#9859). Вложенные — стеком: закрытая внешняя прячет и
  // внутренние. По умолчанию закрыто (<details open> — открыто); открытое
  // остаётся открытым, пока чат открыт (ключ — по тексту: лента виртуальная,
  // узлы пересоздаются). Нажатие, Enter, пробел — открыть/закрыть; ⌥-нажатие
  // — все свёртки ответа разом; Esc — закрыть открытую под фокусом. Кнопка
  // Copy копирует исходник с тегами — её не трогаем.
  // Слово Элвиса 08.10 «по возможности сворачивать… чтоб здесь кнопка
  // появилась»: у ответа выше двух экранов под первым абзацем — кнопка
  // «▾ Свернуть ответ / ▸ Развернуть ответ» того же вида (заметная — WF218,
  // #9426); по умолчанию НЕ свёрнут. Развернуть — в два шага (#9810, слово Элвиса 11.10 «показывается
  // короткая сводка. И там есть внизу подробнее»): сначала сводка (раздел 12ф³), «Подробнее» под ней —
  // весь ответ; «Свернуть ответ» с любого шага — обратно. foldState.long: true — свёрнут, "brief" —
  // сводка, нет — весь ответ.
  const FOLD_OPEN_RE = /^<details(\s+open(?:\s*=\s*["']?[^"'>]*["']?)?)?\s*>\s*(?:<summary>([\s\S]*?)<\/summary>)?$/i;
  const FOLD_SUMMARY_RE = /^<summary>([\s\S]*?)<\/summary>$/i;
  const FOLD_CLOSE_RE = /^<\/details>$/i;
  const FOLD_LONG_SCREENS = 2;
  const FOLD_LONG_KEEP = 0.9;
  const FOLD_KEY_CHARS = 80;
  // WF302 (#11226, слово Элвиса 30.10 ~17:45 об «Ответах на твои вопросы»: «пусть он будет свёрнутым, но… очень
  // заметным для меня… в самом начале… Крупный очень»): свёртка с подписью на «💬» (форма Рика
  // `<summary><b>💬 ОТВЕТЫ НА ТВОИ ВОПРОСЫ — N</b></summary>`) — крупная голова, ▾ на той же вертикали, что у прочих
  // (полоса тела — под ней). #11478 (слово Элвиса 01.11: «чтобы оно… заканчивалось цифрой», «скругления были
  // одинаковые», «ждёт тебя сделать таким же блоком свёртываемым»): плашка — по ширине подписи, ▾ — вне её (выступ
  // влево режет скроллер Claude), и «❗ ЖДЁТ ТЕБЯ — N (🔴 K)» — такая же крупная. Прочие свёртки — как были.
  // Фото в свёртке («контекста больше, фоток в этих вопросах»): ссылка на картинку (путь, file://, computer://,
  // относительный — от папки чата; png jpg gif webp heic) в теле ОТКРЫТОЙ свёртки — миниатюрой в конце её абзаца:
  // байты — `GET /thumb` (К-TH, кэш и повтор раздела 12м⁴), дальше это фото ленты — нажатие открывает просмотр 12л.
  // Свёртка закрылась — миниатюр нет.
  const FOLD_BIG_RE = /^(?:💬|❗\uFE0F?\s*Жд[её]т\s+тебя(?![\p{L}]))/iu;
  const FOLD_BIG_ATTRIBUTE = "data-myclaude-fold-big";
  const FOLD_PIC_ATTRIBUTE = "data-myclaude-fold-pic";
  const FOLD_PIC_RE = /\.(png|jpe?g|gif|webp|hei[cf])$/i;
  // #11239 (слово Элвиса 30.10 18:47: «должны быть кнопки сверху… развернуть, свернуть… чтоб я мог всё развернуть и
  // тогда читать всё как одним сообщением группированным… чтобы при этом разворачивании дублирования не было инфы»):
  // у ответа с двумя свёртками и больше — сверху (под заголовком h1–h3, иначе перед первым узлом) строка ссылок
  // «Развернуть всё (N)» и «Свернуть всё». Развернуть — все свёртки ответа, вложенные тоже, и сам ответ целиком: свёрнутый
  // «Свернуть ответ» и сводка 12ф³ уходят (сводка повторила бы текст). Свернуть — все свёртки, ответ не сворачивает.
  // Подписи — из атрибута (::after): копия и «Прочитано» их не видят.
  // #11631 (слово Элвиса 04.11: «Давай ещё внизу ответа сделаем эти же кнопки две… Я буду нажимать»): та же строка —
  // и в конце ответа (последней в том же корне), с меткой FOLD_ALL_END; свёрнутый «Свернуть ответ» прячет её с хвостом.
  // Слово Элвиса 04.11 19:20: «без слова „всё“… просто развернуть и свернуть» — подписи «Развернуть» и «Свернуть».
  const FOLD_ALL_ATTRIBUTE = "data-myclaude-fold-all";
  const FOLD_ALL_END_ATTRIBUTE = "data-myclaude-fold-all-end";
  // #11631 (слово Элвиса 04.11 19:20 об «Ответах на твои вопросы»: «эти полосы разрывающиеся… вертикальные… визуальный
  // шум создают… чтобы ты их убрал»): у свёртки со вложенными своей полосы нет — ни сквозь головы вложенных, ни у её
  // узлов (метка FOLD_FLAT, место то же); раскрытая вложенная — со своей полосой, как любая.
  const FOLD_FLAT_ATTRIBUTE = "data-myclaude-fold-flat";
  const FOLD_ALL_MIN = 2;
  // blank (#11651): спрятанные текстовые узлы строк-тегов → их текст (вернуть, когда тег ушёл, и при dispose).
  const foldState = { chat: undefined, open: new Map(), heads: new Map(), long: new Map(), wholes: new Map(), marked: new Set(), pics: new Map(), bars: new Map(), ends: new Map(), blank: new Map(), count: 0, pending: 0, clicks: 0 };
  const foldOwn = node => Boolean(node?.hasAttribute?.(FOLD_HEAD_ATTRIBUTE) || node?.hasAttribute?.(ANSWER_SUM_ATTRIBUTE) || node?.hasAttribute?.(FOLD_PIC_ATTRIBUTE) || node?.hasAttribute?.(FOLD_ALL_ATTRIBUTE));
  const foldTag = value => {
    const text = sayNorm(value);
    if (!text.startsWith("<")) return null;
    let hit = FOLD_OPEN_RE.exec(text);
    if (hit) return { kind: "open", start: Boolean(hit[1]), title: hit[2] ?? null };
    hit = FOLD_SUMMARY_RE.exec(text);
    if (hit) return { kind: "summary", title: hit[1] };
    return FOLD_CLOSE_RE.test(text) ? { kind: "close" } : null;
  };
  // Текст узла, как его дал React: спрятанный нами — по оригиналу.
  const foldValue = node => (node.nodeValue === "" && foldState.blank.has(node) ? foldState.blank.get(node) : String(node.nodeValue ?? ""));
  const foldBlanked = node => foldState.blank.size > 0 && [...(node.childNodes ?? [])].some(kid => kid.nodeType === 3 && kid.nodeValue === "" && foldState.blank.has(kid));
  const foldText = node => {
    if (node?.nodeType === 3) return foldValue(node);
    if (!foldState.blank.size || ![...foldState.blank.keys()].some(text => node?.contains?.(text))) return node?.textContent ?? "";
    let out = "";
    for (const kid of node.childNodes ?? []) out += kid.nodeType === 1 || kid.nodeType === 3 ? foldText(kid) : "";
    return out;
  };
  // Сырой <p>: только текст тега, без своего кода внутри (`<details>` в
  // строке кода — не тег). Абзац с нашими спрятанными строками (#11651) — не сырой: его остаток прочитался бы тегом.
  const foldRaw = node => {
    if (node?.tagName !== "P") return null;
    try { if (node.querySelector("code")) return null; } catch {}
    if (foldBlanked(node)) return null;
    return foldTag(node.textContent);
  };
  // #11651: `</details>` сразу после списка, цитаты или текста Claude кладёт в тот же абзац строкой —
  // `<p>пункт<br></details></p>`. Строки — прямые дети абзаца между прямыми <br>; строка-тег — теги подряд в начале
  // абзаца (голова) или в конце (хвост), все строки теги — всё хвостом. Строка тега: at — её стабильный узел (хвост —
  // <br> перед ней, голова — первый узел), hide — что спрятать (у головы — и <br> после неё).
  // #11680: в плотном списке абзаца нет — Claude кладёт текст прямо в пункт, `<li>пункт<br></details></li>` (проба
  // окна Рика 05.11: вложенные «8.4», «8.7» и внешняя «💬» стояли сырыми тегами). Строки края — у <p> и у такого <li>.
  const FOLD_LINE_SELECTOR = "p,li";
  const foldLines = p => {
    const lines = [{ nodes: [], br: null }];
    for (const node of p.childNodes ?? []) {
      if (node.nodeType === 1 && node.tagName === "BR") lines.push({ nodes: [], br: node });
      else if (node.nodeType === 3 || (node.nodeType === 1 && !foldOwn(node))) lines[lines.length - 1].nodes.push(node);
    }
    return lines;
  };
  const foldLineTag = line => {
    let text = "";
    for (const node of line.nodes) {
      if (node.nodeType === 3) { text += foldValue(node); continue; }
      try { if (node.tagName === "CODE" || node.querySelector("code")) return null; } catch { return null; }
      text += node.textContent ?? "";
    }
    return line.nodes.length ? foldTag(text) : null;
  };
  const foldEdges = p => {
    if ((p?.tagName !== "P" && p?.tagName !== "LI") || ![...(p.childNodes ?? [])].some(node => node.tagName === "BR") || foldRaw(p)) return null;
    const lines = foldLines(p);
    if (lines.length < 2) return null;
    const tags = lines.map(foldLineTag);
    let head = 0;
    while (head < tags.length && tags[head]) head += 1;
    const all = head === tags.length;
    if (all) head = 0;
    let tail = tags.length;
    while (tail > head && tags[tail - 1]) tail -= 1;
    if (!head && tail === tags.length) return null;
    const group = [];
    const item = (index, side) => {
      const line = lines[index];
      const hide = side === "head" ? [...line.nodes, lines[index + 1]?.br] : [line.br, ...line.nodes];
      const at = side === "head" ? line.nodes[0] : line.br ?? line.nodes[0];
      const entry = { edge: true, side, p, all, group, at, hide: hide.filter(Boolean), ...tags[index] };
      group.push(entry);
      return entry;
    };
    const heads = [];
    for (let index = 0; index < head; index += 1) heads.push(item(index, "head"));
    const tails = [];
    for (let index = tail; index < tags.length; index += 1) tails.push(item(index, "tail"));
    return { head: heads, tail: tails };
  };
  // Хозяин краёв: от абзаца вверх через пункт, список и цитату, пока узел — последний (хвост) / первый (голова)
  // не-свой ребёнок; теги встают в проход его родителя рядом с ним.
  const FOLD_EDGE_UP = new Set(["LI", "UL", "OL", "BLOCKQUOTE"]);
  const foldOwner = (p, last) => {
    let node = p;
    while (node.parentElement && FOLD_EDGE_UP.has(node.parentElement.tagName)) {
      const kids = [...node.parentElement.children].filter(kid => !foldOwn(kid));
      if ((last ? kids[kids.length - 1] : kids[0]) !== node) break;
      node = node.parentElement;
    }
    return node;
  };
  // Свёртка внутри outer — по цепочке стека (up), и когда её открытие — строка абзаца, а не сырой <p>.
  const foldInside = (fold, outer) => {
    for (let up = fold?.up; up; up = up.up) if (up === outer) return true;
    return false;
  };
  const foldTitle = raw => sayNorm(String(raw ?? "").replace(/<[^>]*>/g, "")) || "Подробнее";
  // Ответы ленты — внешние узлы (один ответ даёт несколько совпадений).
  const foldAnswers = () => {
    let list = [];
    try { list = [...document.querySelectorAll(`${RUN_ROW_SELECTOR},${ANSWER_SELECTOR}`)]; } catch { list = []; }
    list = list.filter(node => !node.closest?.(".epitaxy-user-turn") && !state.composerBlock?.contains?.(node));
    return list.filter(node => !list.some(other => other !== node && other.contains(node)));
  };
  // Свёртки одного ответа: по каждому родителю сырых <p> — проход стеком.
  // live() — ответ ещё пишется: открытой без пары телом идёт всё после тега (#9859). Спрашивается
  // только при теге без пары — обычный проход лишних запросов не делает.
  const foldFind = (answer, live = () => false) => {
    const folds = [];
    let paras = [];
    try { paras = [...answer.querySelectorAll(FOLD_LINE_SELECTOR)]; } catch { paras = []; }
    const parents = new Set();
    // #11651: строки-теги краёв абзацев — рядом с хозяином в проходе его родителя.
    const edges = new Map();
    const lay = (owner, side, items) => {
      if (!edges.has(owner)) edges.set(owner, { head: [], tail: [] });
      edges.get(owner)[side].push(...items);
      if (owner.parentElement) parents.add(owner.parentElement);
    };
    for (const p of paras) {
      if (!p.parentElement) continue;
      if (foldRaw(p)) { parents.add(p.parentElement); continue; }
      const edge = foldEdges(p);
      if (!edge) continue;
      for (const item of edge.head) item.owner = foldOwner(p, false);
      for (const item of edge.tail) item.owner = foldOwner(p, true);
      if (edge.head.length) lay(edge.head[0].owner, "head", edge.head);
      if (edge.tail.length) lay(edge.tail[0].owner, "tail", edge.tail);
    }
    for (const parent of parents) {
      const kids = [...(parent.children ?? [])].filter(kid => !foldOwn(kid));
      const seq = kids.flatMap(kid => [...(edges.get(kid)?.head ?? []), kid, ...(edges.get(kid)?.tail ?? [])]);
      const rawOf = item => (item?.edge ? item : foldRaw(item));
      const stack = [];
      const made = [];
      for (let index = 0; index < seq.length; index += 1) {
        const raw = rawOf(seq[index]);
        if (raw?.kind === "open") {
          const entry = { open: raw.edge ? raw.at : seq[index], summary: null, title: raw.title, start: raw.start, from: index + 1, at: index, answer, parent, up: stack[stack.length - 1] ?? null, tags: [seq[index]] };
          const next = raw.title == null ? rawOf(seq[index + 1]) : null;
          if (next?.kind === "summary") { entry.summary = next.edge ? next.at : seq[index + 1]; entry.tags.push(seq[index + 1]); entry.title = next.title; entry.from = index + 2; index += 1; }
          entry.title = foldTitle(entry.title);
          stack.push(entry);
        } else if (raw?.kind === "close" && stack.length) {
          const entry = stack.pop();
          entry.close = raw.edge ? raw.at : seq[index];
          entry.tags.push(seq[index]);
          entry.to = index;
          made.push(entry);
        }
      }
      // Внутренняя без пары — раньше внешней, как и с парой: её заголовок нужен внешней в heads.
      while (stack.length && live()) {
        const entry = stack.pop();
        entry.close = null;
        entry.pending = true;
        entry.to = seq.length;
        made.push(entry);
      }
      // Абзац из одних строк-тегов, все в деле, — прячется целиком (текст не трогаем) и в тело не входит.
      const used = new Set(made.flatMap(entry => entry.tags));
      const spent = new Set();
      for (const item of used) if (item.edge && item.all && item.group.every(other => used.has(other))) spent.add(item.p);
      const end = foldState.ends.get(answer);
      for (const entry of made) {
        entry.hide = [];
        for (const tag of entry.tags) {
          if (!tag.edge) entry.hide.push(tag);
          else if (!spent.has(tag.p)) entry.hide.push(...tag.hide);
          else if (!entry.hide.includes(tag.p)) entry.hide.push(tag.p);
        }
        entry.body = seq.slice(entry.from, entry.to).filter(node => !node.edge && !spent.has(node));
        entry.key = `${entry.title}|${sayNorm(entry.body.map(foldText).join(" ")).slice(0, FOLD_KEY_CHARS)}`;
        // Куда встаёт заголовок: перед сырым <p>; строка головы — перед хозяином; строка хвоста — перед следующим
        // настоящим ребёнком, нет его — перед нижней строкой «Развернуть / Свернуть» (иначе менялись бы местами).
        const first = seq[entry.at];
        if (!first.edge) entry.before = first;
        else if (first.side === "head") entry.before = first.owner;
        else entry.before = seq.slice(entry.at + 1).find(node => !node.edge) ?? (end?.parentNode === parent ? end : null);
        delete entry.tags;
        folds.push(entry);
      }
    }
    return folds;
  };
  // Ответ, который ещё пишется (#9859): метка Claude у сообщения; её нет на странице вовсе — последний
  // ответ, пока идёт ход. Метки ищутся раз на проход.
  const FOLD_LIVE_SELECTOR = '[data-is-streaming="true"]';
  const foldLive = answers => {
    let marks = null;
    return answer => () => {
      try {
        marks ??= [...document.querySelectorAll(FOLD_LIVE_SELECTOR)];
        if (marks.length) return marks.some(mark => mark === answer || mark.contains(answer) || answer.contains(mark));
        return answer === answers[answers.length - 1] && pageWorking();
      } catch { return false; }
    };
  };
  // Корень ответа для «Свернуть ответ»: родитель первого абзаца вне списков и цитат.
  const foldLongRoot = answer => {
    let paras = [];
    try { paras = [...answer.querySelectorAll("p")]; } catch { paras = []; }
    const first = paras.find(p => !p.parentElement?.closest?.("li,blockquote,pre,table") && !foldRaw(p)) ?? null;
    if (!first?.parentElement || !first.nextElementSibling) return null;
    return { root: first.parentElement, first };
  };
  const foldMakeHead = () => {
    const head = document.createElement("div");
    head.setAttribute(FOLD_HEAD_ATTRIBUTE, "closed");
    head.setAttribute("role", "button");
    head.setAttribute("tabindex", "0");
    return head;
  };
  const foldPlace = (head, parent, before) => {
    if (head.parentNode === parent && head.nextElementSibling === before) return true;
    try { parent.insertBefore(head, before); return true; } catch { return false; }
  };
  const foldMakeBar = (end = false) => {
    const bar = document.createElement("div");
    bar.setAttribute(FOLD_ALL_ATTRIBUTE, "bar");
    if (end) bar.setAttribute(FOLD_ALL_END_ATTRIBUTE, "");
    for (const kind of ["open", "close"]) {
      const button = document.createElement("span");
      button.setAttribute(FOLD_ALL_ATTRIBUTE, kind);
      button.setAttribute("role", "button");
      button.setAttribute("tabindex", "0");
      bar.appendChild(button);
    }
    return bar;
  };
  // Подписи и состояние строки: «Развернуть» гаснет, когда всё раскрыто и ответ на виду целиком, «Свернуть» —
  // когда раскрытых нет.
  const foldBarPaint = (bar, answer, folds, opened, whole) => {
    bar.__myclaudeFoldAll = answer;
    const [open, close] = bar.children;
    foldSet(open, FOLD_LABEL_ATTRIBUTE, "Развернуть");
    foldSet(open, "aria-label", `Развернуть все свёртки ответа: ${folds.length}`);
    foldSet(open, "aria-disabled", opened === folds.length && !whole ? "true" : "false");
    foldSet(close, FOLD_LABEL_ATTRIBUTE, "Свернуть");
    foldSet(close, "aria-label", "Свернуть все свёртки ответа");
    foldSet(close, "aria-disabled", opened ? "false" : "true");
  };
  // Строка «Развернуть / Свернуть» (#11239): корень — родитель самой внешней свёртки ответа; под его первым
  // узлом, если это заголовок, иначе перед ним; вторая (#11631) — последней в корне. Ответ на виду целиком — без
  // свёрнутого «Свернуть ответ» и сводки.
  const foldBarPlace = (answer, folds, opened) => {
    const depth = node => { let n = 0; for (let up = node; up; up = up.parentNode) n += 1; return n; };
    const root = folds.map(fold => fold.parent).filter(Boolean).sort((a, b) => depth(a) - depth(b))[0];
    if (!root) return null;
    const bar = foldState.bars.get(answer) ?? foldMakeBar();
    let anchor = root.firstElementChild;
    while (anchor === bar) anchor = anchor.nextElementSibling;
    if (!anchor) return null;
    let before = anchor;
    if (/^H[1-3]$/.test(anchor.tagName ?? "")) {
      before = anchor.nextElementSibling;
      if (before === bar) before = bar.nextElementSibling;
    }
    if (!foldPlace(bar, root, before)) return null;
    const whole = [...foldState.wholes.values()].some(item => item.__myclaudeFold?.answer === answer && foldState.long.get(item.__myclaudeFold.key));
    foldBarPaint(bar, answer, folds, opened, whole);
    const end = foldState.ends.get(answer) ?? foldMakeBar(true);
    if (!foldPlace(end, root, null)) return { bar, end: null };
    foldBarPaint(end, answer, folds, opened, whole);
    return { bar, end };
  };
  // Разметка ровно по тому, что сейчас в ленте; ушедшее снято.
  const foldPaint = () => {
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    if (chat !== foldState.chat) { foldState.chat = chat; foldState.open.clear(); foldState.long.clear(); }
    const marks = new Map();
    const mark = (node, name, value) => {
      if (!marks.has(node)) marks.set(node, new Map());
      const own = marks.get(node);
      if (name === FOLD_BODY_ATTRIBUTE && own.get(name) === "closed") return;
      own.set(name, value);
    };
    const heads = new Map();
    const inside = new Set();
    const wholes = new Map();
    const bars = new Map();
    const ends = new Map();
    const briefs = new Set();
    const blanks = new Set();
    let count = 0;
    let pending = 0;
    const answers = foldAnswers();
    const live = foldLive(answers);
    for (const answer of answers) {
      const folds = foldFind(answer, live(answer));
      count += folds.length;
      pending += folds.filter(fold => fold.pending).length;
      let opened = 0;
      for (const fold of folds) {
        // Тело дописалось (ход пишется, ключ — по началу тела): выбор Элвиса едет за тем же тегом.
        const was = foldState.heads.get(fold.open)?.__myclaudeFold?.key;
        if (was !== undefined && was !== fold.key && !foldState.open.has(fold.key) && foldState.open.has(was)) foldState.open.set(fold.key, foldState.open.get(was));
        const open = foldState.open.has(fold.key) ? foldState.open.get(fold.key) : fold.start;
        if (open) opened += 1;
        const head = foldState.heads.get(fold.open) ?? foldMakeHead();
        // Вложенные с тем же местом (строки хвоста, #11651): внешняя встаёт перед уже поставленными головами своих.
        const kin = folds.filter(other => foldInside(other, fold));
        const kinHeads = new Set(kin.map(other => heads.get(other.open)).filter(Boolean));
        let before = fold.before;
        for (let prev = before ? before.previousElementSibling : fold.parent.lastElementChild; prev && kinHeads.has(prev); prev = prev.previousElementSibling) before = prev;
        if (!foldPlace(head, fold.parent, before)) continue;
        heads.set(fold.open, head);
        foldSet(head, FOLD_HEAD_ATTRIBUTE, open ? "open" : "closed");
        foldSet(head, "aria-expanded", open ? "true" : "false");
        // Крупная — стрелка своим ::before (вне плашки), в подписи её нет.
        const big = FOLD_BIG_RE.test(fold.title);
        foldSet(head, FOLD_LABEL_ATTRIBUTE, big ? fold.title : `${open ? "▾" : "▸"} ${fold.title}`);
        foldSet(head, "aria-label", fold.title);
        foldSet(head, FOLD_BIG_ATTRIBUTE, big ? "" : null);
        head.__myclaudeFold = fold;
        for (const node of fold.hide) if (node.nodeType === 3) blanks.add(node); else mark(node, FOLD_RAW_ATTRIBUTE, "");
        const nested = kin.length > 0 || fold.body.some(node => heads.has(node));
        for (const node of fold.body) {
          mark(node, FOLD_BODY_ATTRIBUTE, open ? "open" : "closed");
          if (nested && !inside.has(node)) mark(node, FOLD_FLAT_ATTRIBUTE, "");
          // Закрытая внешняя прячет и заголовок внутренней (внутренняя
          // закрывается раньше — её заголовок уже в heads); раскрытая ведёт
          // сквозь него свою полосу (WF225, #9426) — та же метка, вид свой; #11631 — полосы нет.
          const inner = heads.get(node);
          if (inner) { mark(inner, FOLD_BODY_ATTRIBUTE, open ? "open" : "closed"); mark(inner, FOLD_FLAT_ATTRIBUTE, ""); }
        }
        for (const inner of kinHeads) { mark(inner, FOLD_BODY_ATTRIBUTE, open ? "open" : "closed"); mark(inner, FOLD_FLAT_ATTRIBUTE, ""); }
        for (const node of fold.body) inside.add(node);
      }
      if (folds.length >= FOLD_ALL_MIN) {
        const placed = foldBarPlace(answer, folds, opened);
        if (placed?.bar) bars.set(answer, placed.bar);
        if (placed?.end) ends.set(answer, placed.end);
      }
      // Длинный ответ.
      let height = 0;
      try { height = answer.getBoundingClientRect().height; } catch {}
      const spot = foldLongRoot(answer);
      if (!spot) continue;
      const key = sayNorm(spot.first.textContent).slice(0, FOLD_KEY_CHARS * 2);
      const step = foldState.long.get(key);
      const shut = step === true;
      const hide = shut || step === "brief";
      // WF225: полоса меняет высоту ответа (отступ, переносы) — кнопка, раз появившись, держится
      // с запасом, иначе у самого порога она мигала бы на каждом проходе.
      const tall = FOLD_LONG_SCREENS * (window.innerHeight || 800) * (foldState.wholes.has(spot.first) ? FOLD_LONG_KEEP : 1);
      if (!hide && !(height > tall)) continue;
      const whole = foldState.wholes.get(spot.first) ?? foldMakeHead();
      const placed = whole.parentNode === spot.root && spot.first.nextElementSibling === whole;
      if (!placed && !foldPlace(whole, spot.root, spot.first.nextElementSibling)) continue;
      wholes.set(spot.first, whole);
      foldSet(whole, FOLD_WHOLE_ATTRIBUTE, shut ? "closed" : "open");
      foldSet(whole, FOLD_HEAD_ATTRIBUTE, shut ? "closed" : "open");
      foldSet(whole, "aria-expanded", shut ? "false" : "true");
      foldSet(whole, FOLD_LABEL_ATTRIBUTE, shut ? "▸ Развернуть ответ" : "▾ Свернуть ответ");
      foldSet(whole, "aria-label", shut ? "Развернуть ответ" : "Свернуть ответ");
      whole.__myclaudeFold = { whole: true, key, answer };
      // Сводка (12ф³): на шаге "brief" — свой узел сразу под кнопкой; спрошена при раскрытии.
      const brief = hide ? answerSumPlace(whole, key, step === "brief", live(answer)) : null;
      if (brief) briefs.add(key);
      // Под свёрнутой кнопкой всё помечено closed (прячет правило раздела 4). Слово Элвиса 10.10 10:47:
      // полосы вдоль всего раскрытого ответа нет — под раскрытой кнопкой ничего не метим.
      if (hide) for (let node = whole.nextElementSibling; node; node = node.nextElementSibling) if (node !== brief) mark(node, FOLD_LONG_ATTRIBUTE, "closed");
    }
    for (const [open, head] of foldState.heads) if (heads.get(open) !== head) { try { head.remove(); } catch {} }
    for (const [first, whole] of foldState.wholes) if (wholes.get(first) !== whole) { try { whole.remove(); } catch {} }
    for (const [answer, bar] of foldState.bars) if (bars.get(answer) !== bar) { try { bar.remove(); } catch {} }
    for (const [answer, end] of foldState.ends) if (ends.get(answer) !== end) { try { end.remove(); } catch {} }
    foldState.bars = bars;
    foldState.ends = ends;
    answerSumSweep(briefs);
    foldState.heads = heads;
    foldState.wholes = wholes;
    for (const node of foldState.marked) {
      const own = marks.get(node);
      for (const name of [FOLD_RAW_ATTRIBUTE, FOLD_BODY_ATTRIBUTE, FOLD_LONG_ATTRIBUTE, FOLD_FLAT_ATTRIBUTE]) if (!own?.has(name)) foldSet(node, name, null);
    }
    for (const [node, own] of marks) for (const [name, value] of own) foldSet(node, name, value);
    foldState.marked = new Set(marks.keys());
    // Строки-теги (#11651): текст прячем записью пустого nodeValue (только непустого — без лишней записи
    // наблюдателю); тег ушёл — вернуть, если узел всё ещё пуст (React мог вписать новый текст).
    for (const [node, value] of foldState.blank) {
      if (blanks.has(node)) continue;
      if (node.nodeValue === "") { try { node.nodeValue = value; } catch {} }
      foldState.blank.delete(node);
    }
    for (const node of blanks) if (node.nodeValue !== "") { foldState.blank.set(node, node.nodeValue); try { node.nodeValue = ""; } catch {} }
    foldState.count = count;
    foldState.pending = pending;
    try { foldPicPaint(); } catch {}
    // Свёрток <details> нет — стрелку меряем по раскрытой кнопке «Свернуть ответ» (WF225). Крупная «💬» — не мерка:
    // её ▾ сама встаёт на вертикаль прочих (правило ниже).
    foldArrowMid([...heads.values()].find(head => !head.hasAttribute(FOLD_BIG_ATTRIBUTE))
      ?? [...wholes.values()].find(whole => whole.getAttribute(FOLD_WHOLE_ATTRIBUTE) === "open"));
  };
  // Миниатюры фото открытых свёрток (WF302): ряд `[FOLD_PIC="row"]` последним ребёнком абзаца (пункта) со ссылкой,
  // в нём по картинке на ссылку; ушедшее снято. Миниатюра ещё идёт — следующий тик сердца перерисует.
  const foldPicPaint = () => {
    const rows = new Map();
    let chat;
    let cwd;
    let waiting = false;
    for (const head of foldState.heads.values()) {
      if (head.getAttribute(FOLD_HEAD_ATTRIBUTE) !== "open" || head.getAttribute(FOLD_BODY_ATTRIBUTE) === "closed") continue;
      for (const node of head.__myclaudeFold?.body ?? []) {
        if (node.getAttribute?.(FOLD_BODY_ATTRIBUTE) !== "open" || foldOwn(node)) continue;
        let links = [];
        try { links = [...(node.matches?.("a[href]") ? [node] : []), ...node.querySelectorAll('a[href],[role="button"]')]; } catch { links = []; }
        for (const link of links) {
          if (link.closest?.(`[${FOLD_BODY_ATTRIBUTE}="closed"],[${FOLD_LONG_ATTRIBUTE}="closed"],[${FOLD_PIC_ATTRIBUTE}]`)) continue;
          let found = null;
          try { found = mentionLinkAt(link); } catch { found = null; }
          if (found?.node !== link) continue;
          if (!/^(?:\/|file:|computer:)/i.test(found.path)) cwd ??= mentionCwd();
          const path = mentionPath(found.path, cwd ?? "");
          if (!path || !FOLD_PIC_RE.test(path)) continue;
          if (chat === undefined) { try { chat = myChatId(); } catch { chat = null; } }
          const entry = heicAsk(path, chat);
          if (entry?.pending) waiting = true;
          if (!entry?.url) continue;
          const block = (link.closest?.("p,li") && node.contains(link.closest("p,li")) ? link.closest("p,li") : null) ?? link.parentElement;
          if (!block) continue;
          if (!rows.has(block)) rows.set(block, []);
          const list = rows.get(block);
          if (!list.some(item => item.path === path)) list.push({ path, url: entry.url });
        }
      }
    }
    for (const [block, row] of foldState.pics) if (!rows.has(block)) { try { row.remove(); } catch {} }
    const pics = new Map();
    for (const [block, list] of rows) {
      let row = foldState.pics.get(block);
      if (!row) {
        row = document.createElement("span");
        row.setAttribute(FOLD_PIC_ATTRIBUTE, "row");
      }
      const kids = [...row.children];
      list.forEach((item, index) => {
        let img = kids.find(kid => kid.__myclaudeFoldPic === item.path);
        if (!img) {
          img = document.createElement("img");
          img.setAttribute(FOLD_PIC_ATTRIBUTE, "img");
          img.setAttribute("alt", "");
          img.__myclaudeFoldPic = item.path;
        }
        foldSet(img, "title", item.path.split("/").pop());
        foldSet(img, "src", item.url);
        if (row.children[index] !== img) row.insertBefore(img, row.children[index] ?? null);
      });
      while (row.children.length > list.length) row.lastElementChild.remove();
      if (row.parentNode !== block || block.lastChild !== row) { try { block.appendChild(row); } catch { continue; } }
      pics.set(block, row);
    }
    foldState.pics = pics;
    if (waiting) state.pageDirty = true;
  };
  // WF176 (#9198, слово Элвиса по снимку отчёта Рика): линия цитаты в свёртке — ровно
  // под стрелкой ▾ заголовка (центр линии = центр ▾), содержимое — вместе с ней.
  // Центр знака — замер его начертания шрифтом заголовка (canvas, без раскладки),
  // плюс левое поле заголовка; итог — переменная на корне, её читает правило цитаты.
  const FOLD_MID_VARIABLE = "--myclaude-fold-mid";
  // #11478: ширина «▾ » тем же шрифтом — висячий отступ подписи (перенос встаёт под текст, а не под ▾ на полосу).
  const FOLD_HANG_VARIABLE = "--myclaude-fold-hang";
  const foldMid = { font: "", value: "" };
  const foldArrowMid = head => {
    if (!head?.isConnected) return;
    try {
      const computed = getComputedStyle(head);
      const font = `${computed.fontWeight} ${computed.fontSize} ${computed.fontFamily}`;
      // Поле слева плюс внешний сдвиг: у заголовка 4 + 0, у раскрытой кнопки 8 − 4 — стрелка там же; висячий
      // отступ заголовка (поле 4 + H, красная строка −H) стрелку не двигает.
      const pad = (Number.parseFloat(computed.paddingLeft) || 0) + (Number.parseFloat(computed.marginLeft) || 0) + (Number.parseFloat(computed.textIndent) || 0);
      if (font !== foldMid.font) {
        const context = document.createElement("canvas").getContext("2d");
        if (!context) return;
        context.font = font;
        const metric = context.measureText("▾");
        const right = Number(metric.actualBoundingBoxRight);
        const left = Number(metric.actualBoundingBoxLeft);
        const center = Number.isFinite(right) && Number.isFinite(left) && right + left > 0 ? (right - left) / 2 : Number(metric.width) / 2;
        if (!Number.isFinite(center) || center <= 0) return;
        foldMid.font = font;
        foldMid.center = center;
        const hang = Number(context.measureText("▾ ").width);
        foldMid.hang = Number.isFinite(hang) && hang > 0 ? `${Math.round(hang * 100) / 100}px` : "";
      }
      if (foldMid.hang && document.documentElement.style.getPropertyValue(FOLD_HANG_VARIABLE) !== foldMid.hang) document.documentElement.style.setProperty(FOLD_HANG_VARIABLE, foldMid.hang);
      const value = `${Math.round((pad + foldMid.center) * 100) / 100}px`;
      if (value === foldMid.value && document.documentElement.style.getPropertyValue(FOLD_MID_VARIABLE) === value) return;
      foldMid.value = value;
      document.documentElement.style.setProperty(FOLD_MID_VARIABLE, value);
    } catch {}
  };
  track(() => { try { for (const name of [FOLD_MID_VARIABLE, FOLD_HANG_VARIABLE]) document.documentElement.style.removeProperty(name); } catch {} });
  const foldTick = () => { foldPaint(); };
  // #9859 (слово Элвиса: «ответы развёрнутыми показываются… а потом резко сворачиваются»): тик
  // сердца — до HEARTBEAT_MS после мутации, и всё это время новый ход ленты виден развёрнутым. Колбэк
  // наблюдателя — микрозадача: отработал до кадра, поэтому разметка встаёт ДО первой отрисовки. Здесь
  // только дешёвый отбор: проход нужен, когда новое могло лечь под свёртку — сырой тег (новый абзац,
  // текст абзаца стал тегом, новый ход с тегами), новый сосед в разметке свёрток (тело, хвост
  // свёрнутого ответа, свёртка, что пишется), пересозданный ход при свёрнутых ответах (лента
  // виртуальная), ответ дописан (метка Claude снялась — свёртка без пары раскрывается). Свои заголовки
  // в отбор не входят — повторного прохода от своей же вставки нет.
  const foldNeeds = records => {
    const shut = () => [...foldState.long.values()].some(Boolean);
    for (const record of records) {
      if (record.type === "attributes") { if (foldState.pending) return true; continue; }
      const target = record.target?.nodeType === 1 ? record.target : record.target?.parentElement;
      if (!target) continue;
      const para = target.closest?.(FOLD_LINE_SELECTOR);
      if (record.type === "characterData") {
        if (para && (para.hasAttribute(FOLD_RAW_ATTRIBUTE) || foldRaw(para) || foldEdges(para))) return true;
        continue;
      }
      const added = [...(record.addedNodes ?? [])].filter(node => !foldOwn(node));
      if (!added.length) continue;
      if (para && (foldRaw(para) || foldEdges(para))) return true;
      for (const kid of target.children ?? []) if (foldOwn(kid) || foldState.marked.has(kid)) return true;
      for (const node of added) {
        if (node.nodeType !== 1) continue;
        let paras = [];
        try { paras = node.matches?.(FOLD_LINE_SELECTOR) ? [node, ...node.querySelectorAll(FOLD_LINE_SELECTOR)] : [...node.querySelectorAll(FOLD_LINE_SELECTOR)]; } catch { paras = []; }
        if (paras.some(p => foldRaw(p) || foldEdges(p)) || (paras.length && shut())) return true;
      }
    }
    return false;
  };
  // Один наблюдатель «до отрисовки» на обе свёртки: ответы (12ф) и свёрнутое поле (раздел 6).
  // Создан раньше общего (раздел 16) — его колбэк идёт первым, «Прочитано» видит заголовки свёрток.
  const prePaintWatch = new MutationObserver(records => {
    if (!state.alive || !state.watching) return;
    try { collapseOnMutation(records); } catch {}
    try { if (foldNeeds(records)) foldPaint(); } catch {}
  });
  prePaintWatch.observe(document.documentElement, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ["data-is-streaming"] });
  track(() => prePaintWatch.disconnect());
  // Переключить свёртку (all — все свёртки того же ответа в то же состояние).
  const foldToggle = (head, all = false) => {
    const fold = head?.__myclaudeFold;
    if (!fold) return false;
    foldState.clicks += 1;
    if (fold.whole) {
      // Свёрнут → сводка (нет текста для сводки — сразу весь ответ); сводка или весь ответ → свёрнут.
      const shut = head.getAttribute(FOLD_WHOLE_ATTRIBUTE) === "closed";
      foldState.long.set(fold.key, !shut ? true : answerSumReady(fold.key) ? "brief" : false);
    } else {
      const next = head.getAttribute(FOLD_HEAD_ATTRIBUTE) !== "open";
      const list = all ? [...foldState.heads.values()].map(item => item.__myclaudeFold).filter(item => item?.answer === fold.answer) : [fold];
      for (const item of list) foldState.open.set(item.key, next);
    }
    foldPaint();
    return true;
  };
  // «Развернуть / Свернуть» (#11239): все свёртки ответа; развернуть — и сам ответ целиком.
  // Нажата нижняя (#11631) — она остаётся под курсором: что над ней выросло или сжалось, ленту сдвигает.
  const foldAll = button => {
    const bar = button?.closest?.(`[${FOLD_ALL_ATTRIBUTE}="bar"]`);
    const answer = bar?.__myclaudeFoldAll;
    if (!answer) return false;
    const open = button.getAttribute(FOLD_ALL_ATTRIBUTE) === "open";
    let top = null;
    if (bar.hasAttribute(FOLD_ALL_END_ATTRIBUTE)) { try { top = bar.getBoundingClientRect().top; } catch {} }
    foldState.clicks += 1;
    for (const head of foldState.heads.values()) if (head.__myclaudeFold?.answer === answer) foldState.open.set(head.__myclaudeFold.key, open);
    if (open) for (const whole of foldState.wholes.values()) if (whole.__myclaudeFold?.answer === answer) foldState.long.set(whole.__myclaudeFold.key, false);
    foldPaint();
    try {
      const now = top == null ? null : foldState.ends.get(answer);
      const feed = now ? readFeed() : null;
      const delta = feed ? Math.round(now.getBoundingClientRect().top - top) : 0;
      if (Math.abs(delta) > 1) feed.scrollTop += delta;
    } catch {}
    return true;
  };
  const foldAllOf = target => target?.closest?.(`[${FOLD_ALL_ATTRIBUTE}="open"],[${FOLD_ALL_ATTRIBUTE}="close"]`) ?? null;
  const foldHeadOf = target => {
    const head = target?.closest?.(`[${FOLD_HEAD_ATTRIBUTE}]`) ?? null;
    return head && (foldState.heads.has(head.__myclaudeFold?.open) || head.__myclaudeFold?.whole) ? head : null;
  };
  const onFoldClick = event => {
    const all = foldAllOf(event?.target);
    if (all && state.alive) {
      event.preventDefault?.();
      event.stopPropagation?.();
      if (Number(event.detail) > 1) return;
      try { foldAll(all); } catch {}
      return;
    }
    const head = foldHeadOf(event?.target);
    if (!head || !state.alive) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    if (Number(event.detail) > 1) return;
    try { foldToggle(head, Boolean(event.altKey)); } catch {}
  };
  // Esc — закрыть открытую под фокусом: свой заголовок или узел её тела;
  // на кнопке «Свернуть ответ» — свернуть ответ (WF218: клавиши как у свёрток).
  const foldUnder = node => {
    let best = null;
    for (const head of foldState.heads.values()) {
      const fold = head.__myclaudeFold;
      if (head.getAttribute(FOLD_HEAD_ATTRIBUTE) !== "open") continue;
      if (head === node || fold.body.some(part => part.contains?.(node))) {
        if (!best || best.__myclaudeFold.body.some(part => part.contains?.(head))) best = head;
      }
    }
    return best;
  };
  const onFoldKey = event => {
    if (!state.alive) return;
    const key = event?.key;
    if (key === "Enter" || key === " " || key === "Spacebar") {
      const all = foldAllOf(event.target);
      if (all) {
        event.preventDefault?.();
        event.stopPropagation?.();
        try { foldAll(all); all.focus?.(); } catch {}
        return;
      }
      const head = foldHeadOf(event.target);
      if (!head) return;
      event.preventDefault?.();
      event.stopPropagation?.();
      try { foldToggle(head, Boolean(event.altKey)); } catch {}
      return;
    }
    if (key !== "Escape") return;
    const focus = document.activeElement ?? event.target;
    if (!focus || state.composerBlock?.contains?.(focus)) return;
    const whole = foldHeadOf(focus);
    const head = foldUnder(focus) ?? (whole?.getAttribute(FOLD_WHOLE_ATTRIBUTE) === "open" ? whole : null);
    if (!head) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    try { foldToggle(head); head.focus?.(); } catch {}
  };
  // Сироты прошлой установки — до первой разметки.
  try {
    for (const node of document.querySelectorAll(`[${FOLD_HEAD_ATTRIBUTE}],[${FOLD_PIC_ATTRIBUTE}="row"],[${FOLD_ALL_ATTRIBUTE}="bar"]`)) node.remove();
    for (const attr of [FOLD_RAW_ATTRIBUTE, FOLD_BODY_ATTRIBUTE, FOLD_LONG_ATTRIBUTE, FOLD_FLAT_ATTRIBUTE]) {
      for (const node of document.querySelectorAll(`[${attr}]`)) node.removeAttribute(attr);
    }
  } catch {}
  track(() => {
    for (const head of [...foldState.heads.values(), ...foldState.wholes.values(), ...foldState.pics.values(), ...foldState.bars.values(), ...foldState.ends.values()]) { try { head.remove(); } catch {} }
    for (const node of foldState.marked) {
      for (const attr of [FOLD_RAW_ATTRIBUTE, FOLD_BODY_ATTRIBUTE, FOLD_LONG_ATTRIBUTE, FOLD_FLAT_ATTRIBUTE]) { try { node.removeAttribute(attr); } catch {} }
    }
    for (const [node, value] of foldState.blank) if (node.nodeValue === "") { try { node.nodeValue = value; } catch {} }
    foldState.blank.clear();
    foldState.heads.clear();
    foldState.wholes.clear();
    foldState.pics.clear();
    foldState.bars.clear();
    foldState.ends.clear();
    foldState.marked.clear();
  });
  // Свёртки <details> (#9065, раздел 12ф): сколько в ленте, открыто, кнопок
  // «Свернуть ответ» и свёрнутых ими ответов, нажатий.
  statusPart("folds", () => ({
    count: foldState.count,
    open: [...foldState.heads.values()].filter(head => head.getAttribute(FOLD_HEAD_ATTRIBUTE) === "open").length,
    long: foldState.wholes.size,
    shut: [...foldState.wholes.values()].filter(head => head.getAttribute(FOLD_WHOLE_ATTRIBUTE) === "closed").length,
    clicks: foldState.clicks,
    brief: [...foldState.wholes.values()].filter(head => foldState.long.get(head.__myclaudeFold?.key) === "brief").length,
    big: [...foldState.heads.values()].filter(head => head.hasAttribute(FOLD_BIG_ATTRIBUTE)).length,
    pics: [...foldState.pics.values()].reduce((sum, row) => sum + row.children.length, 0),
    all: foldState.bars.size,
  }));
  // WF302, #11478: крупная голова — кегль в полтора раза, жирно; ▾ своим ::before на вертикали прочих: у мелкой центр
  // знака = 4 px поля + c, где c = mid − 4, у крупной — поле + 1,5·c, поэтому поле 6 − mid/2. Плашка — ::after по ширине
  // подписи (тонированная, каёмка акцента, скругления 10 px с обеих сторон); сама голова без фона.
  const FOLD_BIG = `[${FOLD_HEAD_ATTRIBUTE}][${FOLD_BIG_ATTRIBUTE}]`;
  const FOLD_BIG_TONE = percent => `color-mix(in srgb,var(--cds-text-accent,rgb(245,158,11)) ${percent}%,transparent)`;
  lateRules.push(
    // #11478: мелкая голова — висячий отступ на «▾ »: длинная подпись переносится под текст (в теле свёртки перенос
    // ложился на её полосу), ▾ — на месте. Кнопка ответа и крупная — своим полем.
    `[${FOLD_HEAD_ATTRIBUTE}]:not([${FOLD_WHOLE_ATTRIBUTE}],[${FOLD_BIG_ATTRIBUTE}]){padding-left:calc(4px + var(${FOLD_HANG_VARIABLE}, .9em));text-indent:calc(0px - var(${FOLD_HANG_VARIABLE}, .9em))}`,
    `${FOLD_BIG}{display:flex;align-items:baseline;box-sizing:border-box;margin:10px 0 12px;padding:0 0 0 calc(6px - var(--myclaude-fold-mid, 7.4px) / 2);font-size:1.5em;line-height:1.3;font-weight:700;background:none}`,
    `${FOLD_BIG}::before{content:"▸";flex:none;position:static;border:0;-webkit-mask-image:none;mask-image:none}`,
    `[${FOLD_HEAD_ATTRIBUTE}="open"][${FOLD_BIG_ATTRIBUTE}]::before{content:"▾"}`,
    `${FOLD_BIG}::after{min-width:0;margin-left:.25em;padding:8px 12px;border-radius:10px;background:${FOLD_BIG_TONE(16)};box-shadow:inset 0 0 0 1.5px ${FOLD_BIG_TONE(45)};transition:background-color .15s}`,
    `${FOLD_BIG}:is(:hover,:active){background:none}`,
    `${FOLD_BIG}:hover::after{background:${FOLD_BIG_TONE(24)}}`,
    `${FOLD_BIG}:active::after{background:${FOLD_BIG_TONE(32)}}`,
    // «Прочитано» (раздел 4) сжимает ответ в строку — там голова без плашки.
    `[${READ_ROW_ATTRIBUTE}="head"] [${READ_LINE_ATTRIBUTE}] ${FOLD_BIG}::after{padding:0;background:none;box-shadow:none}`,
    `[${FOLD_PIC_ATTRIBUTE}="row"]{display:flex;flex-wrap:wrap;gap:8px;margin:8px 0 2px}`,
    `[${FOLD_ALL_ATTRIBUTE}="bar"]{display:flex;flex-wrap:wrap;gap:2px 16px;margin:2px 0 10px;font-size:.9em;line-height:1.5;user-select:none;-webkit-user-select:none}`,
    `[${FOLD_ALL_ATTRIBUTE}="bar"][${FOLD_ALL_END_ATTRIBUTE}]{margin:12px 0 2px}`,
    // #11631: свёртка со вложенными — без полос (линия прозрачная, поля те же; у крупной ::before — её ▸).
    foldStripRule(`${FOLD_STRIP}[${FOLD_FLAT_ATTRIBUTE}]`, "border-left-color:transparent !important"),
    foldStripRule(`table${FOLD_STRIP}[${FOLD_FLAT_ATTRIBUTE}]::before`, "content:none !important"),
    `${FOLD_STRIP_HEAD}[${FOLD_FLAT_ATTRIBUTE}]:not([${FOLD_BIG_ATTRIBUTE}])::before{content:none}`,
    `[${FOLD_ALL_ATTRIBUTE}]:not([${FOLD_ALL_ATTRIBUTE}="bar"]){color:var(--cds-text-accent,rgb(245,158,11));cursor:pointer;text-decoration:underline;text-decoration-color:color-mix(in srgb,currentColor 45%,transparent);text-underline-offset:3px;border-radius:4px;-webkit-app-region:no-drag}`,
    `[${FOLD_ALL_ATTRIBUTE}]:not([${FOLD_ALL_ATTRIBUTE}="bar"])::after{content:attr(${FOLD_LABEL_ATTRIBUTE})}`,
    `[${FOLD_ALL_ATTRIBUTE}]:not([${FOLD_ALL_ATTRIBUTE}="bar"]):hover{text-decoration-color:currentColor}`,
    `[${FOLD_ALL_ATTRIBUTE}][aria-disabled="true"]{color:inherit;opacity:.45;text-decoration:none;cursor:default}`,
    `[${FOLD_ALL_ATTRIBUTE}]:focus-visible{outline:2px solid rgba(245,158,11,.7);outline-offset:2px}`,
    `[${FOLD_PIC_ATTRIBUTE}="img"]{display:block;max-width:100%;max-height:220px;width:auto;height:auto;border-radius:8px;border:1px solid rgba(127,127,127,.25);cursor:zoom-in}`,
  );
  HATCH && Object.assign(HATCH, { foldTick, foldFind, foldNeeds, foldAll, foldEdges });

