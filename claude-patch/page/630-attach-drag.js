  // ---- 12м². Перетаскивание вложений (#7685, WF90) ---------------------------
  // Слово Элвиса 25.09 22:45 (пересказ): перетаскивание не работает совсем — нужно
  // между чатами, внутри чата и в другие программы. Фото и
  // карточки файлов из ленты чата тащатся мышью: в поле ввода этого или
  // другого окна Claude, в Finder, в Telegram, в ChatGPT.
  //
  // Почему не работало: фото в главном окне лежит под ::after плитки
  // span[role=button] — нажатие приходит в span, а он не перетаскивается; да и
  // 12л гасил preventDefault'ом pointerdown, а отменённый pointerdown в
  // Chromium отменяет и начало перетаскивания. Карточка файла — кнопка без
  // draggable, и ни у кого из них нет данных перетаскивания.
  //
  // Устройство. Наведение (pointerover, захват) ставит плитке фото или карточке
  // draggable="true" (картинке внутри плитки — "false", чтобы тащилась плитка,
  // а не родная картинка Chromium). dragstart кладёт:
  //   DownloadURL  «mime:имя:адрес» — Chromium отдаёт в Finder и прочие
  //                программы ФАЙЛ (file promise) и сам скачивает его по адресу;
  //   text/uri-list, text/plain — file:// и путь (только у карточек с путём);
  //   DD_TYPE      свой маркер JSON {v, kind, name, mime, src|path, chat} —
  //                по нему любое окно Claude принимает бросок само.
  // Адрес у фото — его data: (полный размер, раздел 12л). У карточки страница
  // читает файл мостом Claude (разведка 25.09, Claude 2.9939.2):
  //   LocalSessions.readSessionImageAsDataUrl(chat, path)        — картинки;
  //   LocalSessions.readSessionMediaAsDataUrl(chat, path)        — видео, звук;
  //   LocalSessions.readSessionPanelDocumentAsDataUrl(chat, path) — pdf;
  //   LocalSessions.readSessionFile(chat, path) → {contents}      — текст (utf-8:
  //                бинарное там портится в U+FFFD — такой ответ не берём).
  // Мост асинхронный, а dragstart — нет: читаем заранее, но только когда
  // карточку уже тянут — pointermove с зажатой кнопкой дальше DD_MOVE_PX от
  // нажатия (Chromium начинает перетаскивание позже), или сам dragstart, если
  // успел раньше. Обычный клик по карточке файла не читает (проверка WF90).
  // Не успело или не читается (zip и прочее двоичное, больше DD_MAX_BYTES,
  // видео/pdf/текст неизвестного размера) — в DownloadURL идёт file://.
  // Мост есть только у главного окна (window["claude.web"]); попап about:blank
  // берёт его у родителя, window.opener — один экземпляр, один origin.
  //
  // Окно без поля ввода (попап артефакта, настройки): бросок с маркером
  // запрещён (dropEffect none) и погашен — иначе путь текстом лёг бы в чужое
  // поле, например в input переименования.
  // Бросок в окно Claude: маркер в types — dragover разрешаем (copy), drop
  // гасим на захвате (иначе ProseMirror вставил бы путь текстом) и кладём
  // файл в поле ввода тем же путём, что перенос «Обкэшить» (раздел 12):
  // DataTransfer с File → синтетический paste в редактор. Файл не читается —
  // в поле ложится его путь текстом: Claude Code прочтёт файл по пути сам.
  // В СВОЁМ окне бросок на ленту не принимается: отпустил, не донеся до
  // поля, — ничего не случилось. Enter не шлём никогда.
  const DD_TYPE = "application/x-pimpmyclaude-drag";
  const DD_ATTRIBUTE = "data-myclaude-dd";
  const DD_CARD_TARGET = `button,[role="button"],a,${FILE_TILE_SELECTOR}`;
  // Потолки: больше DD_MAX_BYTES — не читаем заранее (мост гонит base64 через
  // IPC), кэш держит последние файлы не больше DD_CACHE_BYTES суммарно (по длине
  // data:-адресов), чтение ждём не дольше DD_READ_MS. DD_MOVE_PX — сдвиг с
  // зажатой кнопкой, после которого считаем, что карточку тянут.
  const DD_MAX_BYTES = 20 * 1024 * 1024;
  const DD_CACHE_BYTES = 60 * 1024 * 1024;
  const DD_READ_MS = 8000;
  const DD_MOVE_PX = 3;
  // Служебные кнопки блоков инструментов тоже сидят под компонентом с path:
  // карточка — только если path у ближайшего компонента над кнопкой (не дальше
  // DD_CARD_HOPS волокон) или имя файла написано в самой кнопке.
  const DD_CARD_HOPS = 3;
  const DD_NOTE_FAIL = "Не смог положить файл в поле";
  const DD_MIME = {
    png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp",
    bmp: "image/bmp", heic: "image/heic", svg: "image/svg+xml",
    mp4: "video/mp4", mov: "video/quicktime", m4v: "video/x-m4v", webm: "video/webm",
    mp3: "audio/mpeg", m4a: "audio/mp4", wav: "audio/wav", ogg: "audio/ogg",
    pdf: "application/pdf", zip: "application/zip", gz: "application/gzip", tar: "application/x-tar",
    html: "text/html", htm: "text/html", md: "text/markdown", txt: "text/plain", csv: "text/csv",
    json: "application/json", js: "text/javascript", mjs: "text/javascript", css: "text/css",
    xml: "application/xml", py: "text/x-python", swift: "text/x-swift", sh: "text/x-sh",
  };
  // Чем читать файл по расширению: image / media / pdf / none (двоичное без
  // моста) / text (всё прочее — пробуем текстом).
  const DD_BINARY_RE = /^(zip|gz|tgz|tar|7z|rar|dmg|pkg|app|docx?|xlsx?|pptx?|key|pages|numbers|psd|sketch|fig|sqlite|db|bin|exe|woff2?|ttf|otf|ico|icns|heic)$/;
  const DD_IMAGE_RE = /^(png|jpe?g|gif|webp|bmp|svg)$/;
  const DD_MEDIA_RE = /^(mp4|mov|m4v|webm|mp3|m4a|wav|ogg|aac|flac)$/;
  const ddState = { out: null, cache: new Map(), press: null, reads: 0, starts: 0, drops: 0, last: null, landing: null };
  const ddExt = name => {
    const match = /\.([a-z0-9]{1,8})$/i.exec(String(name ?? ""));
    return match ? match[1].toLowerCase() : "";
  };
  const ddMimeOf = name => DD_MIME[ddExt(name)] ?? "application/octet-stream";
  const ddReadWay = name => {
    const ext = ddExt(name);
    if (DD_IMAGE_RE.test(ext)) return "image";
    if (DD_MEDIA_RE.test(ext)) return "media";
    if (ext === "pdf") return "pdf";
    if (DD_BINARY_RE.test(ext)) return "none";
    return "text";
  };
  // Имя для DownloadURL: двоеточие делит его поля, слэш — путь.
  const ddSafeName = name => String(name ?? "").replace(/[:/\\\u0000-\u001f]/g, "-").trim() || "file";
  const ddInFeed = node => Boolean(node?.closest?.(PHOTO_FEED_SELECTOR)) && !node.closest(PHOTO_SKIP_DRAG_SELECTOR);
  // Карточка файла под курсором: ближайшая кнопка/ссылка в ленте, у чьего
  // волокна (или его предков) есть пропс path — как у «Открыть в Chrome». Но
  // только сама карточка: path у компонента не дальше DD_CARD_HOPS над кнопкой
  // или имя файла в тексте кнопки. «Copy», «Expand» и прочие кнопки блока
  // инструмента, у которого path лежит выше, перетаскиваемыми не становятся.
  const ddCardAt = target => {
    if (!target || target.nodeType !== 1 || !ddInFeed(target)) return null;
    const node = target.closest(DD_CARD_TARGET);
    if (!node || !ddInFeed(node) || photoAt(node)) return null;
    let fiber = openChromeFiber(node);
    for (let hop = 0; fiber && hop <= OPEN_CHROME_DEPTH; hop += 1, fiber = fiber.return) {
      const found = openChromePathOf(fiber.memoizedProps);
      if (!found) continue;
      const named = Boolean(found.name) && String(node.textContent ?? "").includes(found.name);
      if (hop > DD_CARD_HOPS && !named) return null;
      return { node, found, size: Number(fiber.memoizedProps?.size) || 0 };
    }
    return null;
  };
  // Что тащим: фото ({kind:"photo", node — что делаем draggable, img}) или
  // карточку ({kind:"card", node, found, size}).
  const ddItemAt = target => {
    if (!themable || !target || target.nodeType !== 1) return null;
    const img = photoAt(target);
    if (img) {
      const press = img.closest('button,[role="button"]');
      return { kind: "photo", node: press && press.contains(img) ? press : img, img };
    }
    const card = ddCardAt(target);
    return card ? { kind: "card", ...card } : null;
  };
  const ddMark = (node, value) => {
    if (!node || node.getAttribute(DD_ATTRIBUTE) != null) {
      if (node && node.getAttribute("draggable") !== value) node.setAttribute("draggable", value);
      return;
    }
    const was = node.getAttribute("draggable");
    node.setAttribute(DD_ATTRIBUTE, was == null ? "-" : was);
    node.setAttribute("draggable", value);
  };
  const ddUnmarkAll = () => {
    let nodes = [];
    try { nodes = [...document.querySelectorAll(`[${DD_ATTRIBUTE}]`)]; } catch { nodes = []; }
    for (const node of nodes) {
      const was = node.getAttribute(DD_ATTRIBUTE);
      node.removeAttribute(DD_ATTRIBUTE);
      if (was === "-") node.removeAttribute("draggable");
      else node.setAttribute("draggable", was);
    }
  };
  const onDragHover = event => {
    try {
      const item = ddItemAt(event.target);
      if (!item) return;
      ddMark(item.node, "true");
      if (item.kind === "photo" && item.node !== item.img) ddMark(item.img, "false");
    } catch {}
  };
  // Мост чтения файлов: свой у главного окна, у попапа — родителя.
  const ddBridge = () => {
    let sessions = null;
    try { sessions = window["claude.web"]?.LocalSessions ?? null; } catch { sessions = null; }
    if (!sessions) { try { sessions = window.opener?.["claude.web"]?.LocalSessions ?? null; } catch { sessions = null; } }
    return sessions;
  };
  const ddWithin = (promise, ms) => new Promise(resolve => {
    const timer = setTimeout(() => resolve(null), ms);
    Promise.resolve(promise).then(value => { clearTimeout(timer); resolve(value); }, () => { clearTimeout(timer); resolve(null); });
  });
  // Файл с диска → data:-адрес (или null). Текст — data:<mime>;charset=utf-8,…
  const ddReadUrl = async (chat, path, name) => {
    const sessions = ddBridge();
    const way = ddReadWay(name || path);
    if (!sessions || !chat || way === "none") return null;
    const call = method => (typeof sessions[method] === "function"
      ? ddWithin(sessions[method].call(sessions, chat, path), DD_READ_MS) : Promise.resolve(null));
    if (way !== "text") {
      const method = way === "image" ? "readSessionImageAsDataUrl"
        : way === "media" ? "readSessionMediaAsDataUrl" : "readSessionPanelDocumentAsDataUrl";
      const url = await call(method);
      return typeof url === "string" && url.startsWith("data:") ? url : null;
    }
    const file = await call("readSessionFile");
    const text = file?.contents;
    if (typeof text !== "string" || text.includes("�")) return null;
    return `data:${ddMimeOf(name || path)};charset=utf-8,${encodeURIComponent(text)}`;
  };
  // Вес записи кэша: длина data:-адреса, пока читается — заявленный размер.
  const ddCacheWeight = entry => (entry.url ? entry.url.length : entry.pending ? entry.size : 0);
  // Кэш по сумме байт: старые записи уходят первыми, свежая (keep) остаётся.
  const ddCacheTrim = keep => {
    let total = 0;
    for (const entry of ddState.cache.values()) total += ddCacheWeight(entry);
    for (const [path, entry] of [...ddState.cache]) {
      if (total <= DD_CACHE_BYTES) break;
      if (path === keep) continue;
      total -= ddCacheWeight(entry);
      ddState.cache.delete(path);
    }
  };
  // Заранее, когда карточку уже тянут: dragstart читать не умеет. Размер
  // неизвестен — читаем только картинку (видео, pdf и текст бывают огромными).
  const ddPrefetch = (path, name, size) => {
    const chat = (() => { try { return myChatId(); } catch { return null; } })();
    const have = ddState.cache.get(path);
    if (have && (have.pending || have.url)) return have;
    const bytes = Number(size) || 0;
    if (bytes > DD_MAX_BYTES) return null;
    const way = ddReadWay(name || path);
    if (way === "none" || (bytes <= 0 && way !== "image")) return null;
    const entry = { url: null, pending: true, chat, size: bytes, done: null };
    ddState.cache.delete(path);
    ddState.cache.set(path, entry);
    ddState.reads += 1;
    ddCacheTrim(path);
    // done — конец чтения: его ждёт просмотр фото-карточки (раздел 12д¹, WF103).
    entry.done = Promise.resolve(ddReadUrl(chat, path, name)).then(url => {
      entry.url = url;
      entry.pending = false;
      if (!url && ddState.cache.get(path) === entry) ddState.cache.delete(path);
      ddCacheTrim(path);
    }, () => { entry.pending = false; });
    return entry;
  };
  // Нажатие по карточке только запоминаем: клик — не перетаскивание.
  const onDragPress = event => {
    ddState.press = null;
    try {
      if ((Number(event.button) || 0) !== 0) return;
      const card = ddCardAt(event.target);
      if (card) ddState.press = { card, x: Number(event.clientX) || 0, y: Number(event.clientY) || 0 };
    } catch {}
  };
  const onDragMove = event => {
    const press = ddState.press;
    if (!press) return;
    try {
      if (!((Number(event.buttons) || 0) & 1)) { ddState.press = null; return; }
      const dx = (Number(event.clientX) || 0) - press.x;
      const dy = (Number(event.clientY) || 0) - press.y;
      if (Math.hypot(dx, dy) < DD_MOVE_PX) return;
      ddState.press = null;
      ddPrefetch(press.card.found.path, press.card.found.name, press.card.size);
    } catch { ddState.press = null; }
  };
  const onDragRelease = () => { ddState.press = null; };
  const ddFileUrl = path => `file://${encodeURI(path)}`;
  // Данные перетаскивания для фото или карточки; возвращает маркер.
  const ddPayload = item => {
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    if (item.kind === "photo") {
      const src = photoSrc(item.img);
      const mime = /^data:([^;,]+)/.exec(src)?.[1] ?? "image/png";
      const ext = mime.split("/")[1]?.replace("jpeg", "jpg").replace(/\+.*$/, "") || "png";
      const label = item.node.getAttribute?.("aria-label") ?? "";
      // #11618: «View image {name}» по-русски — «Посмотреть изображение {name}» (каталог claude.ai).
      const named = /^(?:View image|Посмотреть изображение)\s+(.+\.[a-z0-9]{2,5})$/i.exec(label)?.[1] ?? "";
      let index = -1;
      try { index = photoList().findIndex(entry => entry.src === src); } catch { index = -1; }
      const name = ddSafeName(named || `photo-${index >= 0 ? index + 1 : 1}.${ext}`);
      return { v: 1, kind: "photo", name, mime, src, chat, url: src };
    }
    const { path, name: rawName } = item.found;
    const name = ddSafeName(rawName || path.split("/").pop());
    // dragstart опередил pointermove — начинаем чтение сейчас: к броску в
    // окно Claude файл уже будет в кэше, а в Finder уйдёт file://.
    let cached = ddState.cache.get(path);
    if (!cached) { try { cached = ddPrefetch(path, rawName, item.size); } catch { cached = null; } }
    const marker = { v: 1, kind: "card", name, mime: ddMimeOf(name), path, chat };
    if (item.size > 0) marker.size = item.size;
    return { ...marker, url: cached?.url || ddFileUrl(path) };
  };
  const onDragOut = event => {
    try {
      const data = event.dataTransfer;
      ddState.press = null;
      const item = data ? ddItemAt(event.target) : null;
      if (!item) return;
      const payload = ddPayload(item);
      const { url, ...marker } = payload;
      data.setData("DownloadURL", `${payload.mime}:${payload.name}:${url}`);
      if (payload.path) {
        data.setData("text/uri-list", ddFileUrl(payload.path));
        data.setData("text/plain", payload.path);
      }
      data.setData(DD_TYPE, JSON.stringify(marker));
      try { data.effectAllowed = "copy"; } catch {}
      ddState.out = { kind: payload.kind, name: payload.name };
      ddState.starts += 1;
      ddState.last = { kind: payload.kind, name: payload.name, how: url.startsWith("data:") ? "data" : "file", ok: null };
    } catch {}
  };
  const onDragDone = () => { ddState.out = null; };
  const ddCarries = data => {
    try { return [...(data?.types ?? [])].includes(DD_TYPE); } catch { return false; }
  };
  // Своё окно и курсор над своей лентой — не бросок, а «передумал».
  const ddRefuse = event => Boolean(ddState.out) && ddInFeed(event.target);
  const onDragOverIn = event => {
    if (!themable || !ddCarries(event.dataTransfer) || ddRefuse(event)) return;
    const editor = pasteEditor();
    event.preventDefault();
    event.stopImmediatePropagation();
    try { event.dataTransfer.dropEffect = editor ? "copy" : "none"; } catch {}
  };
  // data: → File. base64 — через atob; прочее — percent-encoding.
  const ddDataFile = (url, name, fallbackType) => {
    const match = /^data:([^,]*?),(.*)$/s.exec(String(url ?? ""));
    if (!match) return null;
    const head = match[1];
    const type = head.split(";")[0] || fallbackType || "application/octet-stream";
    let part;
    if (/;base64$/i.test(head)) {
      const raw = window.atob(match[2]);
      part = new Uint8Array(raw.length);
      for (let at = 0; at < raw.length; at += 1) part[at] = raw.charCodeAt(at);
    } else {
      part = decodeURIComponent(match[2]);
    }
    return new File([part], name, { type });
  };
  const ddFileOf = async marker => {
    if (marker.kind === "photo") {
      const src = String(marker.src ?? "");
      if (src.startsWith("data:")) return ddDataFile(src, marker.name, marker.mime);
      const blob = await ddWithin(fetch(src).then(answer => answer.blob()), DD_READ_MS);
      return blob ? new File([blob], marker.name, { type: blob.type || marker.mime }) : null;
    }
    if (!marker.path) return null;
    const cached = ddState.cache.get(marker.path)?.url;
    // Известно, что файл больше потолка, — мостом не гоним, ляжет путём.
    if (!cached && Number(marker.size) > DD_MAX_BYTES) return null;
    const url = cached || await ddReadUrl(marker.chat, marker.path, marker.name);
    return url ? ddDataFile(url, marker.name, marker.mime) : null;
  };
  // Положить в поле: файл — вставкой, как «Обкэшить»; нет файла — путь текстом.
  const ddLand = async (marker, editor) => {
    let file = null;
    try { file = await ddFileOf(marker); } catch { file = null; }
    const live = editor?.isConnected ? editor : pasteEditor();
    if (!live) { ddState.last = { ...ddState.last, ok: false }; return false; }
    if (state.stage === STAGE_COLLAPSED) setStage(STAGE_NORMAL);
    if (file && !attachFresh([file], "drag").length) { try { newWindowNote(ATTACH_DUP_NOTE); } catch {} return true; }
    let ok = false;
    if (file) {
      try {
        const data = new DataTransfer();
        data.items.add(file);
        live.focus();
        live.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
        ok = true;
      } catch { ok = false; }
    } else if (marker.path) {
      try { ok = insertIntoEditor(live, `${marker.path} `, false); } catch { ok = false; }
    }
    ddState.last = { kind: marker.kind, name: marker.name, how: file ? "file" : "path", ok };
    if (ok) ddState.drops += 1;
    else { try { newWindowNote(DD_NOTE_FAIL); } catch {} }
    return ok;
  };
  const onDropIn = event => {
    if (!themable || !ddCarries(event.dataTransfer) || ddRefuse(event)) return;
    const editor = pasteEditor();
    if (!editor) {
      // Поля ввода нет — бросок никуда: ни путь в чужое поле, ни Claude.
      event.preventDefault();
      event.stopImmediatePropagation();
      try { event.dataTransfer.dropEffect = "none"; } catch {}
      ddState.out = null;
      return;
    }
    let marker = null;
    try { marker = JSON.parse(event.dataTransfer.getData(DD_TYPE)); } catch { marker = null; }
    if (!marker || marker.v !== 1) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    ddState.out = null;
    ddState.landing = ddLand(marker, editor);
  };
  const ddView = () => ({
    starts: ddState.starts, drops: ddState.drops, cache: ddState.cache.size, reads: ddState.reads,
    dragging: Boolean(ddState.out), last: ddState.last,
  });
  track(() => {
    ddUnmarkAll();
    ddState.cache.clear();
    ddState.out = null;
    ddState.press = null;
  });
  HATCH && Object.assign(HATCH, { ddCardAt, ddPrefetch, ddReadUrl, ddReadWay, ddState });

