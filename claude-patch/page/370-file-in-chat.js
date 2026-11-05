  // ---- 12д¹. Файл — в окне чата (WF103, #7939, #7860) -----------------------
  // Слово Элвиса (#7939): «нажимал и прямо внутри чата окно открывалось… между
  // мониторами неохота переключаться». С WF107 (#8127) это пункт правого клика
  // «👁 Посмотреть в окне чата», сам клик — в PimpViewer (fileClick ниже).
  // .html/.htm — `view`: приложение показывает файл своим окном поверх монитора чата (рамка окна и
  // фон темы — в адресе). Фото-карточка (png jpg jpeg gif webp) — в просмотр
  // 12л этого окна: файл читается мостом тем же ddReadUrl и кэшем ddState
  // (раздел 12м²), он первый, дальше фото ленты. Больше DD_MAX_BYTES, не
  // прочиталось за DD_READ_MS, нет чата или моста — прежний `click`. Пока фото
  // читается, повторный клик по нему ничего не делает. Прочее — `click`.
  const viewState = { reading: "", skips: 0 };
  const viewPhoto = (path, node = null) => {
    if (viewState.reading === path) { viewState.skips += 1; return false; }
    // У карточки есть превью полного размера — это фото ленты, 12л берёт его сам.
    const img = node ? photoAt(node) : null;
    if (img) { photoOpen(img); return true; }
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    let size = 0;
    try { size = node ? Number(ddCardAt(node)?.size) || 0 : 0; } catch { size = 0; }
    if (!chat || !ddBridge() || size > DD_MAX_BYTES) return htmlChromeAsk(path, "click");
    const entry = ddPrefetch(path, path.split("/").pop(), size);
    if (!entry) return htmlChromeAsk(path, "click");
    if (entry.url) { photoOpen(0, entry.url); return true; }
    viewState.reading = path;
    Promise.resolve(entry.done).then(() => {
      if (viewState.reading === path) viewState.reading = "";
      if (!state.alive) return;
      if (entry.url) photoOpen(0, entry.url);
      else htmlChromeAsk(path, "click");
    });
    return true;
  };
  // Просмотр в окне чата: пункт «👁 Посмотреть в окне чата» и viewFile() гейта.
  const viewOpen = (path, node = null) => {
    if (typeof path !== "string" || !path.startsWith("/")) return false;
    if (HTML_VIEW_PAGE_RE.test(path)) return htmlChromeAsk(path, "view");
    if (HTML_VIEW_PHOTO_RE.test(path)) return viewPhoto(path, node);
    return htmlChromeAsk(path, "click");
  };
  // Клик по файлу — сразу в PimpViewer (WF107, #8127, К3; Рик 29.09: «Я … должен
  // нажать и PimpViewer открыть»). Карточка, ссылка в тексте, «на картинке»:
  // `click` — приложение отдаёт файл галерее, она не взяла — страница в окне
  // чата (рамка и фон — в адресе), фото — «Просмотр», иначе браузер. Пока ответа
  // нет (≤ HTML_CHROME_REPEAT_MS) — узел занят и переливается (#7772); повтор того
  // же файла — ничего (защита click в htmlChromeAsk). Приложения нет — мост.
  // С WF277 (#10644, слово Элвиса: «открыл файл — панель открылась сама»): в главном окне при живом PimpViewer файл
  // идёт в панель материалов слева (раздел 12п⁴) — `click&dock=1` с местом панели, панель встаёт сама, а «⏳»
  // гаснет по ответу (окно чата не уходит назад: панель без фокуса).
  const fileClickState = { busy: new Map() };
  const fileClickIdle = node => {
    if (!fileClickState.busy.has(node)) return;
    clearTimeout(fileClickState.busy.get(node));
    fileClickState.busy.delete(node);
    try { if (node.getAttribute(BUSY_ATTRIBUTE) === "file") node.removeAttribute(BUSY_ATTRIBUTE); } catch {}
  };
  // reply (WF288, раздел 12д²) — ответ порта тому, у кого свой запасной путь (htmlChromeAsk).
  const fileClick = (path, node = null, reply = null) => {
    if (typeof path !== "string" || !path.startsWith("/")) return false;
    const mark = node?.isConnected ? node : null;
    const fresh = Boolean(mark) && !fileClickState.busy.has(mark);
    if (fresh) {
      try { mark.setAttribute(BUSY_ATTRIBUTE, "file"); } catch {}
      fileClickState.busy.set(mark, setTimeout(() => fileClickIdle(mark), HTML_CHROME_REPEAT_MS));
    }
    // Ответ порта (204) приходит сразу, до галереи (проверка WF107): по нему не снимаем —
    // переливание держится, пока окно не ушло назад (галерея вышла вперёд) или 3 с.
    const settle = () => { if (mark) fileClickIdle(mark); };
    let dock = null;
    try { dock = dockForFile(); } catch { dock = null; }
    // В панель: рамка и фон — для запасного пути приложения; по ответу — сразу место (док мог уйти от другого окна).
    const started = htmlChromeAsk(path, "click", null, dock
      ? { dock, frame: mentionViewable(path), settle: () => { settle(); try { dockSync(true); } catch {} }, reply }
      : { frame: mentionViewable(path), holdOnReply: true, settle, reply });
    if (!started && fresh) fileClickIdle(mark);
    return started;
  };
  const fileClickIdleAll = () => { for (const node of [...fileClickState.busy.keys()]) fileClickIdle(node); };
  track(fileClickIdleAll);

  // #7860 — файлы, упомянутые в ответе. Разведка 27.09 (Claude 2.9939.2, probe):
  //  - ссылка на файл в тексте ответа — span[role=button].prose-link внутри
  //    .prose, путь — пропс fileRef {path, line?} волокна на 2–3 шага выше;
  //    путь бывает относительным — от папки чата (cwd сессии строки списка
  //    слева, как у часиков угла). Её клик у Claude открывает файл в панели
  //    превью. Html/htm/фото мы берём на захвате — как карточку; прочие не трогаем;
  //  - карточка SendUserFile — button[title=<абсолютный путь>] в ряду
  //    [data-testid=transcript-row] ленты (пропсы {name,size,path} шагом выше);
  //    у фото с превью внутри — <img> data:, у прочих — плитка 120×120 без img;
  //  - текст «на картинке — …» — в СЛЕДУЮЩЕМ ряду того же ответа, карточка — в
  //    ряду инструментов над ним. Значит, ближайшая карточка — ВЫШЕ: сначала в
  //    своём ряду до текста, потом в рядах над ним до реплики Элвиса
  //    ([data-take-back-entry]). Карточки нет — слова обычные.
  // Слова не оборачиваем: свой атрибут на узле текста (подпись не меняется,
  // копия и «Обкэшить» его не видят), подсветка — CSS Custom Highlight, попадание
  // клика — caretRangeFromPoint.
  const MENTION_ATTRIBUTE = "data-myclaude-pic";
  const MENTION_HIGHLIGHT = "myclaude-pic";
  const MENTION_STYLE_ID = "myclaude-pic-style";
  const MENTION_WORDS_RE = /(?<![\p{L}\p{N}])на\s+картинк(?:е|ах)(?=\s*[—–-])/giu;
  const MENTION_ROW_SELECTOR = '[data-testid="transcript-row"]';
  const MENTION_TURN_SELECTOR = "[data-take-back-entry]";
  const MENTION_CARD_SELECTOR = `button[title^="/"],${FILE_TILE_SELECTOR}`;
  const MENTION_BLOCK_SELECTOR = `${MENTION_ROW_SELECTOR} .prose p,${MENTION_ROW_SELECTOR} .prose li`;
  const MENTION_ROWS = 8;
  const MENTION_EVERY_MS = 700;
  const MENTION_FIBER_HOPS = 4;
  const mentionState = { links: 0, words: 0, opens: 0, last: null, marks: new Map(), at: -Infinity };
  const mentionViewable = path => HTML_VIEW_PAGE_RE.test(path) || HTML_VIEW_PHOTO_RE.test(path);
  // Ссылка на файл под кликом: { node, path } из fileRef, или null.
  const mentionLinkAt = target => {
    // Markdown-ссылка на локальный файл (путь, file://, computer://) — тоже файл (PimpViewer 1.7:
    // «ссылки на файлы в чате… открываются через Finder → PDF Viewer перехватывает»).
    const anchor = target?.closest?.(".prose a[href]");
    const href = anchor?.getAttribute?.("href") ?? "";
    if (anchor && (/^(file|computer):\/\//.test(href) || href.startsWith("/"))) return { node: anchor, path: href };
    // #11175: относительная (`docs/NN.html`, без схемы, не #якорь, не ?запрос) — от папки чата в mentionLinkPath.
    if (anchor && href && !/^[a-z][a-z0-9+.-]*:/i.test(href) && !/^[#?]/.test(href)) return { node: anchor, path: href };
    const node = target?.closest?.('[role="button"]');
    if (!node || !node.closest?.(".prose")) return null;
    let fiber = openChromeFiber(node);
    for (let hop = 0; fiber && hop <= MENTION_FIBER_HOPS; hop += 1, fiber = fiber.return) {
      const ref = fiber.memoizedProps?.fileRef;
      if (ref && typeof ref.path === "string" && ref.path) return { node, path: ref.path };
    }
    return null;
  };
  // Папка чата: cwd сессии его строки в списке слева (у попапа — список родителя).
  const mentionCwd = () => {
    let id = null;
    try { id = myChatId(); } catch { id = null; }
    if (!id) return "";
    let doc = null;
    try { doc = isMainWindow() ? document : window.opener?.document; } catch { doc = null; }
    const row = doc?.querySelector?.(`[data-testid="sidebar"] [data-row-key="code:${id}"]`);
    const cwd = row ? roamSession(row, id)?.source?.data?.cwd : "";
    return typeof cwd === "string" && cwd.startsWith("/") ? cwd : "";
  };
  // Абсолютный путь ссылки; относительный — от папки чата; не вышло — "". Формы ссылки (file://, computer://,
  // голый путь с %XX) — общим разбором filePathFrom (раздел 12г, WF277).
  const mentionPath = (raw, cwd = "") => {
    let path = filePathFrom(raw);
    if (!path) return "";
    if (!path.startsWith("/")) {
      if (!cwd || path.startsWith("~")) return "";
      path = `${cwd}/${path}`;
    }
    const parts = [];
    for (const part of path.split("/")) {
      if (!part || part === ".") continue;
      if (part === "..") parts.pop(); else parts.push(part);
    }
    return `/${parts.join("/")}`;
  };
  // Путь карточки, если это карточка файла, который мы умеем показать.
  const mentionCardPath = node => {
    const title = String(node?.getAttribute?.("title") ?? "");
    let found = null;
    try { found = node?.matches?.(FILE_TILE_SELECTOR) ? fileTilePath(node) : openChromePath(node); } catch { found = null; }
    if (!found || !mentionViewable(found.path)) return "";
    return found.path === title || found.name === title ? found.path : "";
  };
  // Узлы поддерева по порядку документа; visit вернул true — стоп.
  const mentionWalk = (root, visit) => {
    const step = node => {
      for (const kid of node?.childNodes ?? []) {
        if (visit(kid)) return true;
        if (kid.nodeType === 1 && step(kid)) return true;
      }
      return false;
    };
    return step(root);
  };
  // Ближайшая карточка выше текста в том же ответе: { node, path } или null.
  const mentionCardFor = text => {
    const row = text?.parentElement?.closest?.(MENTION_ROW_SELECTOR);
    if (!row || row.querySelector?.(MENTION_TURN_SELECTOR)) return null;
    let best = null;
    mentionWalk(row, node => {
      if (node === text) return true;
      if (node.nodeType === 1 && node.matches?.(MENTION_CARD_SELECTOR)) {
        const path = mentionCardPath(node);
        if (path) best = { node, path };
      }
      return false;
    });
    if (best) return best;
    let hops = 0;
    for (let above = row.previousElementSibling; above && hops < MENTION_ROWS; above = above.previousElementSibling) {
      if (!above.matches?.(MENTION_ROW_SELECTOR)) continue;
      hops += 1;
      if (above.querySelector?.(MENTION_TURN_SELECTOR)) break;
      const cards = [...(above.querySelectorAll?.(MENTION_CARD_SELECTOR) ?? [])]
        .map(node => ({ node, path: mentionCardPath(node) })).filter(item => item.path);
      if (cards.length) return cards[cards.length - 1];
    }
    return null;
  };
  // Текстовые узлы блока, без вложенных абзацев и пунктов (у них свой проход).
  const mentionTexts = block => {
    const out = [];
    const step = node => {
      for (const kid of node?.childNodes ?? []) {
        if (kid.nodeType === 3) { out.push(kid); continue; }
        if (kid.nodeType !== 1) continue;
        try { if (kid.matches?.("p,li,ul,ol,pre,code")) continue; } catch {}
        step(kid);
      }
    };
    step(block);
    return out;
  };
  const mentionHighlight = marks => {
    try {
      const registry = globalThis.CSS?.highlights;
      if (!registry || typeof Highlight !== "function" || typeof document.createRange !== "function") return;
      const ranges = [];
      for (const list of marks.values()) {
        for (const item of list) {
          const range = document.createRange();
          range.setStart(item.text, item.start);
          range.setEnd(item.text, item.end);
          ranges.push(range);
        }
      }
      if (!ranges.length) { registry.delete(MENTION_HIGHLIGHT); return; }
      registry.set(MENTION_HIGHLIGHT, new Highlight(...ranges));
      if (!document.getElementById(MENTION_STYLE_ID)) {
        const style = document.createElement("style");
        style.id = MENTION_STYLE_ID;
        style.textContent = `::highlight(${MENTION_HIGHLIGHT}){color:rgb(245,158,11);text-decoration:underline dotted rgb(245,158,11);text-underline-offset:3px}`;
        (document.head ?? document.documentElement).appendChild(style);
      }
    } catch {}
  };
  // Разметка «на картинке — …» (из тика 12с): метки ровно на тех узлах, где
  // слова есть и у них нашлась карточка.
  const mentionPaint = (force = false) => {
    if (!themable || !state.alive) return mentionState.words;
    const t = now();
    if (!force && t - mentionState.at < MENTION_EVERY_MS) return mentionState.words;
    mentionState.at = t;
    const marks = new Map();
    let blocks = [];
    try { blocks = [...document.querySelectorAll(MENTION_BLOCK_SELECTOR)]; } catch { blocks = []; }
    let words = 0;
    for (const block of blocks) {
      if (!/картинк/iu.test(String(block.textContent ?? ""))) continue;
      for (const text of mentionTexts(block)) {
        const value = String(text.nodeValue ?? "");
        MENTION_WORDS_RE.lastIndex = 0;
        let card;
        for (let match = MENTION_WORDS_RE.exec(value); match; match = MENTION_WORDS_RE.exec(value)) {
          if (card === undefined) card = mentionCardFor(text);
          if (!card) break;
          const host = text.parentElement;
          if (!host) break;
          if (!marks.has(host)) marks.set(host, []);
          marks.get(host).push({ text, start: match.index, end: match.index + match[0].length, path: card.path, card: card.node });
          words += 1;
        }
      }
    }
    for (const host of mentionState.marks.keys()) {
      if (!marks.has(host)) { try { host.removeAttribute(MENTION_ATTRIBUTE); } catch {} }
    }
    for (const host of marks.keys()) {
      if (host.getAttribute(MENTION_ATTRIBUTE) == null) host.setAttribute(MENTION_ATTRIBUTE, "");
    }
    const same = marks.size === mentionState.marks.size && [...marks].every(([host, list]) => {
      const was = mentionState.marks.get(host);
      return was?.length === list.length
        && list.every((item, i) => item.text === was[i].text && item.start === was[i].start && item.end === was[i].end);
    });
    mentionState.marks = marks;
    mentionState.words = words;
    // Метки те же — подсветку не пересоздаём (гейт 1 WF103: перерисовка раз в 0,7 с).
    if (!same) mentionHighlight(marks);
    return words;
  };
  // Слово под кликом: запись разметки или null.
  const mentionWordAt = event => {
    const host = event?.target?.closest?.(`[${MENTION_ATTRIBUTE}]`);
    const list = host ? mentionState.marks.get(host) : null;
    if (!list?.length) return null;
    let caret = null;
    try { caret = document.caretRangeFromPoint?.(event.clientX, event.clientY) ?? null; } catch { caret = null; }
    if (!caret) return null;
    return list.find(item => item.text === caret.startContainer
      && caret.startOffset >= item.start && caret.startOffset <= item.end) ?? null;
  };
  // Клик по ссылке на файл или по словам «на картинке» (захват документа).
  // Ссылка на файл, у которой Claude вешает меню («Open in Files pane / Show in Finder», у PDF —
  // триггер меню Radix, открывается на pointerdown): нажатие глушим на захвате, файл откроет клик.
  // Вид — по разобранному пути (WF277): у адреса бывают %XX, ?запрос и #якорь; фильтр — fileOpenable раздела 12д,
  // без панели материалов — прежний: страницы, фото и PDF.
  const MENTION_BEFORE_RE = /\.(html?|png|jpe?g|gif|webp|pdf)$/i;
  const mentionLinkPath = link => {
    if (!link) return "";
    const path = mentionPath(link.path, /^(?:\/|file:|computer:)/i.test(link.path) ? "" : mentionCwd());
    return path && fileOpenable(path, MENTION_BEFORE_RE) ? path : "";
  };
  const onMentionPress = event => {
    if (event.isTrusted !== true || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    let path = "";
    try { path = mentionLinkPath(mentionLinkAt(event.target)); } catch { path = ""; }
    if (!path) return;
    event.preventDefault();
    event.stopImmediatePropagation();
  };
  const onMentionClick = event => {
    if (event.isTrusted !== true) return;
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    let link = null;
    try { link = mentionLinkAt(event.target); } catch { link = null; }
    if (link) {
      let path = "";
      try { path = mentionLinkPath(link); } catch { path = ""; }
      if (!path) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      mentionState.links += 1;
      mentionState.last = { path, via: "link" };
      fileClick(path, link.node);
      return;
    }
    // Выделял текст мышью или щёлкнул дважды — это не нажатие на слова.
    try { if (event.detail > 1 || window.getSelection?.()?.isCollapsed === false) return; } catch {}
    let word = null;
    try { word = mentionWordAt(event); } catch { word = null; }
    if (!word) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    mentionState.opens += 1;
    mentionState.last = { path: word.path, via: "word" };
    fileClick(word.path, word.card?.isConnected ? word.card : null);
  };
  track(() => {
    for (const host of mentionState.marks.keys()) { try { host.removeAttribute(MENTION_ATTRIBUTE); } catch {} }
    mentionState.marks = new Map();
    try { globalThis.CSS?.highlights?.delete?.(MENTION_HIGHLIGHT); } catch {}
    try { document.getElementById(MENTION_STYLE_ID)?.remove(); } catch {}
  });

  // Путь из поля панели: абсолютный или file://, только страницы.
  const htmlChromePanePath = value => {
    let text = String(value ?? "").trim();
    if (text.startsWith("file://")) { try { text = decodeURIComponent(text.slice(7)); } catch { return null; } }
    return text.startsWith("/") && HTML_CHROME_FILE_RE.test(text) ? text : null;
  };
  const htmlChromePane = input => {
    let pane = input;
    for (let depth = 0; pane && depth < 12; depth += 1, pane = pane.parentElement) {
      if (pane.querySelector?.(HTML_CHROME_TAB_SELECTOR)) return pane;
    }
    return null;
  };
  const htmlChromeClosePane = input => {
    const pane = htmlChromePane(input);
    if (!pane) return false;
    // #11618: «Close tab» / «Закрыть вкладку» — перечислением (:is() стаб DOM тестов не понимает).
    const tab = pane.querySelector(["Close tab", "Закрыть вкладку"]
      .map(word => `${HTML_CHROME_TAB_SELECTOR}[data-selected="true"] button[aria-label="${word}"]`).join(","));
    if (!tab) return false;
    tab.click();
    htmlChromeState.closed += 1;
    htmlChromeState.emptyUntil = Date.now() + HTML_CHROME_REPEAT_MS;
    return true;
  };
  // После закрытия нашей вкладки в панели остался один «New tab» — панель не нужна.
  // Только в первые секунды после НАШЕГО закрытия: пустую панель, открытую человеком, не трогаем.
  const htmlChromeCloseEmpty = input => {
    if (!(Date.now() < (htmlChromeState.emptyUntil ?? 0)) || String(input.value ?? "").trim()) return;
    const pane = htmlChromePane(input);
    if (!pane) return;
    const tabs = [...pane.querySelectorAll(HTML_CHROME_TAB_SELECTOR)];
    if (!tabs.every(node => HTML_CHROME_NEW_TAB_RE.test(String(node.textContent ?? "").trim()))) return;
    const close = pane.querySelector('button[aria-label="Close"],button[aria-label="Закрыть"]');
    if (!close) return;
    htmlChromeState.emptyUntil = 0;
    close.click();
  };
  const htmlChromeTick = () => {
    const input = document.querySelector(HTML_CHROME_URL_SELECTOR);
    if (!input) return;
    const path = htmlChromePanePath(input.value);
    if (!path) { htmlChromeCloseEmpty(input); return; }
    htmlChromeClosePane(input);
    // Файл, который Claude сам развернул в панели (SendUserFile «render», браузер агента), дальше
    // не отдаём: галерея открывала его поверх того, что Элвис читает (#8177: «я только что читал, ты
    // мне на этом экране другой файл открыл — нельзя так»). Панель закрыта, карточка в чате —
    // клик по ней откроет файл в галерее (К3).
  };
  htmlChromeState.timer = setInterval(() => { try { htmlChromeTick(); } catch {} }, HTML_CHROME_TICK_MS);
  track(() => { clearInterval(htmlChromeState.timer); htmlChromeState.timer = 0; });
  // Файлы, упомянутые в ответе (#7860, раздел 12д¹): кликов по ссылкам,
  // размеченных слов «на картинке», их нажатий, последнее открытие.
  statusPart("mention", () => ({ links: mentionState.links, words: mentionState.words, opens: mentionState.opens, last: mentionState.last }));
  HATCH && Object.assign(HATCH, { htmlChromePanePath, viewOpen, viewState, fileClick, fileClickState, mentionPaint,
    mentionPath });

