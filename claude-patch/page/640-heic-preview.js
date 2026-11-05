  // ---- 12м⁴. Превью HEIC во вложениях чата (К-TH) -----------------------------
  // С #10254/#10229 (слово Элвиса 19.10: «Почему мне JPG-файл пришёл, и я превьюшку его сразу не вижу?»; HTML —
  // «не плашки HTML … 5.2KB, а карточки ФАЙЛ 81 / ФАЙЛ 80 с заголовком») так же — любое фото, которое Claude
  // положил плиткой файла (JPG, PNG…), а HTML и PDF — карточкой: снимок верха страницы (QuickLook приложения,
  // в нём шапка «ФАЙЛ N», заголовок и подзаголовок, как в галерее) над плашкой Claude с именем; снимок мыши не
  // берёт — нажатие, меню и галочка плашки как были (файл в PimpViewer), просмотр фото 12л карточку не берёт.
  // Слово Элвиса 11.10 06:36: «Хэйки эти превьюшки отображаются. Можно сделать как-нибудь?.. отображались
  // нормально, чтобы можно было смотреть, открывать тоже». Фото с айфона (.HEIC/.HEIF) Chromium не
  // читает, и Claude кладёт их в реплику плиткой файла с именем, а не картинкой.
  // • Плитка — FEED_FILE_TILE, в тексте имя на .heic/.heif. Путь файла — в пропсах волокна плитки или
  //   компонентов над ней (не дальше HEIC_HOPS): строка с абсолютным путём, чьё имя файла стоит в
  //   тексте плитки (у реплики с несколькими фото пропсы общие — имя отличает своё).
  // • Миниатюру делает приложение: `GET /thumb?path&chat` на тот же порт, ответ — JPEG (К-TH). Страница
  //   кладёт его в плитку картинкой data: — дальше это обычное фото ленты: нажатие открывает просмотр
  //   12л, тащится как фото (12м²). Имя файла — в подсказке картинки.
  // • Пока миниатюра идёт, приложения нет или оно старое (ответа нет), файл не фото — плитка остаётся
  //   плашкой с именем, как была; повтор запроса — не раньше HEIC_RETRY_MS. Чат неизвестен — запроса нет.
  // • Лента виртуальная: плитка приходит заново — картинка ставится из кэша тем же проходом сердцебиения
  //   (heicTick), своего опроса нет. Узел достался другому файлу — картинка меняется или снимается.
  const HEIC_NAME_RE = /\.(hei[cf]|jpe?g|png|gif|webp|tiff?|bmp|html?|pdf)$/i;
  const HEIC_DOC_RE = /\.(html?|pdf)$/i;
  const HEIC_TEXT_RE = /\.(hei[cf]|jpe?g|png|gif|webp|tiff?|bmp|html?|pdf)\b/i;
  const HEIC_HOPS = 12;
  const HEIC_SCAN_DEPTH = 3;
  const HEIC_SCAN_KEYS = 40;
  const HEIC_CACHE_MAX = 24;
  const HEIC_RETRY_MS = 300000;
  const HEIC_B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  const heicState = { cache: new Map(), asked: 0, failed: 0, shown: 0, cards: 0 };
  // Размер JPEG из его заголовка (маркер SOF): фото в карточке SendUserFile — высотой 180 по пропорции (#10603).
  const heicJpegSize = bytes => {
    for (let i = 2; i + 9 < bytes.length;) {
      if (bytes[i] !== 0xFF) return null;
      const marker = bytes[i + 1];
      if (marker === 0xFF) { i += 1; continue; }
      if (marker >= 0xC0 && marker <= 0xCF && marker !== 0xC4 && marker !== 0xC8 && marker !== 0xCC) {
        return { h: (bytes[i + 5] << 8) | bytes[i + 6], w: (bytes[i + 7] << 8) | bytes[i + 8] };
      }
      i += 2 + ((bytes[i + 2] << 8) | bytes[i + 3]);
    }
    return null;
  };
  // Ширина фото высотой 180 (стенд WF291): по пропорции, не уже 160 (уже — имя под фото налезает на размер, стенд на
  // настоящей разметке) и не шире 320; размера нет — 240.
  const heicWidth = size => (size?.w > 0 && size?.h > 0 ? Math.min(320, Math.max(160, Math.round(180 * size.w / size.h))) : 240);
  const heicBase64 = bytes => {
    const parts = [];
    for (let i = 0; i < bytes.length; i += 3) {
      const a = bytes[i];
      const b = i + 1 < bytes.length ? bytes[i + 1] : 0;
      const c = i + 2 < bytes.length ? bytes[i + 2] : 0;
      parts.push(HEIC_B64[a >> 2] + HEIC_B64[((a & 3) << 4) | (b >> 4)] +
        (i + 1 < bytes.length ? HEIC_B64[((b & 15) << 2) | (c >> 6)] : "=") +
        (i + 2 < bytes.length ? HEIC_B64[c & 63] : "="));
    }
    return parts.join("");
  };
  const heicClean = raw => {
    if (typeof raw !== "string" || raw.length > 4096) return null;
    // Адрес и %XX — общим разбором 12г (WF277): `computer://` с кириллицей раньше не раскрывался.
    const path = filePathFrom(raw);
    return path.startsWith("/") && !path.includes("\0") && HEIC_NAME_RE.test(path) ? path : null;
  };
  // Строка-путь среди пропсов: сами пропсы, их объекты и массивы — не глубже HEIC_SCAN_DEPTH; детей
  // React и узлы DOM не обходим.
  // Своё ли: имя файла в тексте плитки; плитка поля (#10345) режет длинный путь серединой
  // («/Users/dev/Do…HEIC») — тогда куски по краям многоточия сходятся с началом и концом пути.
  const heicTextHas = (text, path) => {
    const low = path.toLowerCase();
    if (text.includes(low.split("/").pop())) return true;
    const cut = text.replace(/\s+/g, "").split(/…|\.\.\./);
    return cut.length === 2 && cut[0].length >= 3 && cut[1].length >= 3 && low.startsWith(cut[0]) && low.endsWith(cut[1]);
  };
  const heicScan = (value, text, depth) => {
    if (typeof value === "string") {
      const path = heicClean(value);
      return path && heicTextHas(text, path) ? path : null;
    }
    if (!value || typeof value !== "object" || depth <= 0 || value.$$typeof || value.nodeType) return null;
    let keys = [];
    try { keys = Object.keys(value); } catch { return null; }
    for (const key of keys.slice(0, HEIC_SCAN_KEYS)) {
      if (key === "children") continue;
      let item = null;
      try { item = value[key]; } catch { continue; }
      const found = heicScan(item, text, depth - 1);
      if (found) return found;
    }
    return null;
  };
  const heicPathOf = (tile, field = false) => {
    const text = String(tile?.textContent ?? "").toLowerCase();
    if (!field && !HEIC_TEXT_RE.test(text)) return null;
    let fiber = openChromeFiber(tile);
    for (let hop = 0; fiber && hop <= HEIC_HOPS; hop += 1, fiber = fiber.return) {
      const found = heicScan(fiber.memoizedProps, text, HEIC_SCAN_DEPTH);
      if (found) return found;
    }
    return null;
  };
  const heicUrl = (path, chat) =>
    `http://127.0.0.1:${HTML_CHROME_PORT}/thumb?path=${encodeURIComponent(path)}&chat=${encodeURIComponent(chat)}`;
  // Запись кэша {url, pending, failAt}; запроса нет (нет чата или fetch) — null.
  const heicAsk = (path, chat) => {
    const have = heicState.cache.get(path);
    if (have && (have.url || have.pending || now() - have.failAt < HEIC_RETRY_MS)) return have;
    if (typeof chat !== "string" || !chat || typeof fetch !== "function") return null;
    const entry = { url: null, pending: true, failAt: -Infinity };
    heicState.cache.delete(path);
    heicState.cache.set(path, entry);
    while (heicState.cache.size > HEIC_CACHE_MAX) heicState.cache.delete(heicState.cache.keys().next().value);
    heicState.asked += 1;
    const fail = () => { entry.pending = false; entry.failAt = now(); heicState.failed += 1; };
    let sent = null;
    try { sent = fetch(heicUrl(path, chat), { mode: "cors", credentials: "omit", cache: "no-store" }); } catch { sent = null; }
    if (!sent || typeof sent.then !== "function") { fail(); return entry; }
    sent.then(reply => (reply?.ok ? reply.arrayBuffer() : null)).then(buffer => {
      const bytes = buffer ? new Uint8Array(buffer) : null;
      // Только JPEG: иного приложение не шлёт, а чужой ответ картинкой не станет.
      if (!bytes || bytes.length < 4 || bytes[0] !== 0xFF || bytes[1] !== 0xD8) { fail(); return; }
      entry.pending = false;
      entry.size = heicJpegSize(bytes);
      entry.url = `data:image/jpeg;base64,${heicBase64(bytes)}`;
      if (state.alive) { try { heicTick(); } catch {} }
    }, fail);
    return entry;
  };
  const heicDrop = tile => {
    try { for (const img of tile.querySelectorAll(`[${HEIC_IMG_ATTRIBUTE}]`)) img.remove(); } catch {}
    try { tile.removeAttribute(HEIC_ATTRIBUTE); } catch {}
    try { tile.style?.removeProperty?.(HEIC_WIDTH_VAR); } catch {}
  };
  // Рост квадрата Claude (#10603): кнопка и узлы от неё до картинки — до высоты 180, ширина — переменной.
  const heicGrow = (button, inner, width) => {
    if (!button.hasAttribute(HEIC_GROW_ATTRIBUTE)) button.setAttribute(HEIC_GROW_ATTRIBUTE, "");
    if (button.style?.getPropertyValue?.(HEIC_WIDTH_VAR) !== `${width}px`) button.style?.setProperty?.(HEIC_WIDTH_VAR, `${width}px`);
    for (let node = inner; node && node !== button && node.nodeType === 1; node = node.parentNode) {
      if (!node.hasAttribute(HEIC_BOX_ATTRIBUTE)) node.setAttribute(HEIC_BOX_ATTRIBUTE, "");
    }
  };
  const heicShrink = button => {
    try { for (const node of button.querySelectorAll(`[${HEIC_BOX_ATTRIBUTE}]`)) node.removeAttribute(HEIC_BOX_ATTRIBUTE); } catch {}
    try { button.removeAttribute(HEIC_GROW_ATTRIBUTE); } catch {}
    try { button.style?.removeProperty?.(HEIC_WIDTH_VAR); } catch {}
  };
  // look: "plate" — плашка SendUserFile, "square" — квадрат 120 самой карточки Claude (#10603).
  const heicShow = (tile, path, url, card = false, field = false, look = "") => {
    let img = null;
    try { img = tile.querySelector(`[${HEIC_IMG_ATTRIBUTE}]`); } catch { img = null; }
    if (!img) {
      img = document.createElement("img");
      img.setAttribute(HEIC_IMG_ATTRIBUTE, "");
      img.setAttribute("alt", "");
      // В поле — первым ребёнком: крестик «Remove» плитки остаётся поверх снимка.
      if (field) tile.insertBefore(img, tile.firstChild); else tile.appendChild(img);
      heicState.shown += 1;
    }
    img.__myclaudeHeic = path;
    const name = path.split("/").pop();
    img.setAttribute("title", name);
    if (img.getAttribute("src") !== url) img.setAttribute("src", url);
    // HTML и PDF — карточка (#10229): снимок верха над плашкой Claude, плашка и её нажатие — как были.
    const doc = HEIC_DOC_RE.test(path);
    const kind = field ? (doc ? "field-doc" : "field") : look === "plate" ? (doc ? "plate-doc" : "plate-photo")
      : look === "square" && doc ? "square-doc" : card ? (doc ? "card-doc" : "card") : doc ? "doc" : "on";
    if (tile.getAttribute(HEIC_ATTRIBUTE) !== kind) tile.setAttribute(HEIC_ATTRIBUTE, kind);
  };
  // Карточки SendUserFile (#10383, слово Элвиса 20.10 ~00:55: «Их нельзя разве показать сразу превьюшками…
  // Зачем ты их вот в таком виде показываешь?»): Рик шлёт фото этим инструментом, Claude рисует
  // button[title=<путь>] с плиткой 120×120, часто без картинки. Фото без своей <img> — миниатюра приложения
  // поверх плитки (самый крупный почти квадратный узел карточки, нет такого — сама карточка); нажатие
  // проходит сквозь неё в карточку, как было (файл в PimpViewer, раздел 12д).
  // Чат Рика (SendUserMessage, Claude 3.1623; #10603 — задача про него): та же карточка без нажатия —
  // div.opacity-70[title=<имя>] (FILE_TILE_SELECTOR, #10531), путь — у волокна (fileTilePath, раздел 12г).
  const HEIC_CARD_ROW = '.epitaxy-chat-panel [data-testid="transcript-row"]';
  const HEIC_CARD_SELECTOR = `${HEIC_CARD_ROW} button[title^="/"],${HEIC_CARD_ROW} ${FILE_TILE_SELECTOR}`;
  const heicCardPath = card => heicClean(card.tagName === "BUTTON" ? card.getAttribute("title") ?? ""
    : fileTilePath(card)?.path ?? "");
  const heicCardTile = button => {
    let best = null;
    let area = 0;
    try {
      for (const node of button.querySelectorAll("div,span")) {
        if (node.hasAttribute(HEIC_IMG_ATTRIBUTE)) continue;
        const box = node.getBoundingClientRect();
        if (box.width < 60 || box.height < 60 || Math.abs(box.width - box.height) > box.width * 0.25) continue;
        if (box.width * box.height > area) { area = box.width * box.height; best = node; }
      }
    } catch {}
    return best ?? button;
  };
  // #10603 (слово Элвиса 22.10.2026: «Я тебя просил превьюшки сделать HTML, чтобы здесь не просто было вот 65 HDML, а
  // прямо сразу превьюшка была… как в PimpViewer… Ой, там вообще все картинки надо: и джипы, и хейки»): плашка
  // SendUserFile (`h-9 max-w-60`: значок, имя, размер) — карточкой: миниатюра 180 сверху, под ней та же плашка.
  // HTML и PDF больше не пропускаем — снимок верха страницы у Пимпа (`/thumb`, сперва снимок карточки PimpViewer).
  // Вызов с картинкой Claude рисует квадратами 120×120 — они растут до высоты 180 по пропорции картинки.
  const heicPlate = button => {
    try { return button.classList.contains("h-9") || button.classList.contains("max-w-60"); } catch { return false; }
  };
  // Квадрат самой карточки Claude (вызов с картинкой: `square`, стиль 120×120): HTML и PDF в нём — снимок сверху,
  // имя и размер Claude под ним; кнопка с путём без квадрата (заголовок инструмента) — не карточка.
  const heicSquare = node => node?.style?.width === "120px" && node?.style?.height === "120px";
  // Общий проход сердцебиения: разметка ровно по плиткам, что сейчас в ленте.
  const heicTick = () => {
    if (!themable) return;
    let tiles = [];
    // Те же плитки, что у FEED_FILE_TILE: в ленте чата; плитки поля ввода (#10345) — отдельно,
    // фото и страницы там — миниатюрой во всю плитку.
    const fields = [];
    try {
      tiles = [...document.querySelectorAll('[data-cds="MessageAttachmentsFile"]')].filter(tile => {
        if (!tile.closest(".epitaxy-chat-panel")) return false;
        if (!tile.closest("[data-cds-composer-attachments]")) return true;
        fields.push(tile);
        return false;
      });
    } catch { tiles = []; }
    let cards = [];
    try { cards = [...document.querySelectorAll(HEIC_CARD_SELECTOR)]; } catch { cards = []; }
    if (!cards.length) heicState.cards = 0;
    if (!tiles.length && !cards.length && !fields.length) return;
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    let cardCount = 0;
    for (const button of cards) {
      const path = heicCardPath(button);
      let own = null;
      try { own = [...button.querySelectorAll("img")].find(img => !img.hasAttribute(HEIC_IMG_ATTRIBUTE)) ?? null; } catch {}
      let tile = null;
      try { tile = button.hasAttribute(HEIC_ATTRIBUTE) ? button : button.querySelector(`[${HEIC_ATTRIBUTE}]`); } catch {}
      if (!path || own) {
        if (tile) heicDrop(tile);
        // Своя картинка Claude (квадрат 120): высотой 180 по пропорции, пока она не загрузилась — квадрат как был.
        const size = own ? { w: own.naturalWidth, h: own.naturalHeight } : null;
        if (path && size.w > 0 && size.h > 0) { heicGrow(button, own.parentNode, heicWidth(size)); cardCount += 1; }
        else if (button.hasAttribute(HEIC_GROW_ATTRIBUTE)) heicShrink(button);
        continue;
      }
      const plate = heicPlate(button);
      if (tile && String(tile.getAttribute(HEIC_ATTRIBUTE)).startsWith("plate") !== plate) { heicDrop(tile); tile = null; }
      const doc = HEIC_DOC_RE.test(path);
      // Не плашка и без квадрата — не карточка файла (кнопка с путём в заголовке инструмента): страницу не трогаем.
      const square = plate ? null : tile ?? heicCardTile(button);
      const own120 = square === button && heicSquare(button);
      if (doc && square === button && !own120) { if (tile) heicDrop(tile); continue; }
      const entry = heicAsk(path, chat);
      if (!entry?.url) continue;
      if (plate) {
        heicShow(button, path, entry.url, false, false, "plate");
        const width = doc ? null : `${heicWidth(entry.size)}px`;
        if (width && button.style?.getPropertyValue?.(HEIC_WIDTH_VAR) !== width) button.style?.setProperty?.(HEIC_WIDTH_VAR, width);
        else if (!width) button.style?.removeProperty?.(HEIC_WIDTH_VAR);
      } else {
        heicShow(square, path, entry.url, true, false, own120 ? "square" : "");
        if (square !== button) heicGrow(button, square, doc ? 240 : heicWidth(entry.size));
        // Фото в квадрате 120 самой карточки — высотой 180, как фото рядом (HTML в нём растёт правилом square-doc).
        else if (own120 && !doc) heicGrow(button, button, heicWidth(entry.size));
      }
      cardCount += 1;
    }
    heicState.cards = cardCount;
    for (const tile of tiles) {
      let path = null;
      try { path = heicPathOf(tile); } catch { path = null; }
      const entry = path ? heicAsk(path, chat) : null;
      if (entry?.url) heicShow(tile, path, entry.url);
      else if (tile.hasAttribute(HEIC_ATTRIBUTE)) heicDrop(tile);
    }
    for (const tile of fields) {
      let path = null;
      try { path = heicPathOf(tile, true); } catch { path = null; }
      const entry = path ? heicAsk(path, chat) : null;
      if (entry?.url) heicShow(tile, path, entry.url, false, true);
      else if (tile.hasAttribute(HEIC_ATTRIBUTE)) heicDrop(tile);
    }
  };
  const heicStatus = () => ({ shown: heicState.shown, asked: heicState.asked, failed: heicState.failed, cached: heicState.cache.size,
    cards: heicState.cards });
  track(() => {
    let tiles = [];
    try { tiles = [...document.querySelectorAll(`[${HEIC_ATTRIBUTE}]`)]; } catch { tiles = []; }
    for (const tile of tiles) heicDrop(tile);
    try { tiles = [...document.querySelectorAll(`[${HEIC_GROW_ATTRIBUTE}]`)]; } catch { tiles = []; }
    for (const button of tiles) heicShrink(button);
    heicState.cache.clear();
  });
  statusPart("heic", () => heicStatus());
  HATCH && Object.assign(HATCH, { heicTick, heicPathOf, heicBase64, heicJpegSize });

