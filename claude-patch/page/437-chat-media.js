  // ---- 12п⁵. Ролики и картинки чата — с диска (#10699) -------------------------
  // Слово Элвиса 23.10.2026: «Капец долго грузятся ролики… как будто бы они из интернета откуда-то скачиваются… Они же
  // на диске всё равно лежат». Замер 23.10 (живое окно Рика): ролик в ленте — вложение, которое Claude залил на свои
  // серверы, <video controls preload="none" src="/api/organizations/<org>/files/<id>/contents" title="<имя>"> после
  // текста сообщения; путь на диске — в пропсах волокна над ним (`path` обёртки меню, surface "attachment"). Плеер
  // Claude качает ролик из интернета, а CSP страницы не пускает в <video> адрес 127.0.0.1 (картинки и запросы — пускает).
  //  - Ролик Claude в ленте (адрес не blob:/data: и не наш) прячется меткой MEDIA_ATTRIBUTE="hidden" — узел React
  //    остаётся; рядом встаёт своя кнопка: первый кадр от приложения (`GET /media-thumb?chat&name[&path]` — JPEG) с ▶
  //    поверх; 204 — файл есть, кадра нет: тёмная плашка размером плеера Claude с ▶ и именем. Прячем, только когда
  //    приложение файл нашло; не нашло, молчит или старое — плеер Claude как был, повтор не раньше MEDIA_RETRY_MS.
  //    Ролик, уже запущенный в Claude, не трогаем.
  //  - Нажатие — файл в панель материалов тем же путём, что клик по файлу (12д¹: `click&dock=1` с местом панели; без
  //    панели — `click`, галерея PimpViewer): путь известен — `path`, нет — `name` (путь по имени найдёт PimpViewer).
  //    Пимп не нашёл файл (`found:false`), не ответил или не знает `name` — кнопка уходит, плеер Claude возвращается.
  //  - Картинка-вложение (img с адресом файла Claude и именем) — те же байты с диска (`GET /media-file`): blob: вместо
  //    src (srcset снимается — на ретине он перебил бы src), просмотр 12л открывает уже полный файл; ошибка — исходный
  //    адрес. Снятие экземпляра возвращает всё как было.
  const MEDIA_ATTRIBUTE = "data-myclaude-media";
  const MEDIA_PLAY_ATTRIBUTE = "data-myclaude-media-play";
  const MEDIA_VIDEO_SELECTOR = ".epitaxy-chat-panel video";
  const MEDIA_IMG_SELECTOR = ".epitaxy-chat-panel img[data-image-file-name],.epitaxy-chat-panel img[data-image-original-src],.epitaxy-chat-panel img[alt][src*=\"/files/\"]";
  // Адрес файла Claude: /api/organizations/<org>/files/<id>/contents, превью — /api/<org>/files/<id>/preview.
  const MEDIA_CLAUDE_FILE_RE = /^(?:https:\/\/claude\.ai)?\/api\/(?:organizations\/)?[^/?#]+\/files\/[^/?#]+\/(?:contents|preview|thumbnail)(?:[?#]|$)/;
  const MEDIA_OWN_SRC_RE = /^(?:blob:|data:|https?:\/\/(?:127\.0\.0\.1|localhost):)/i;
  const MEDIA_VIDEO_RE = /\.(mp4|mov|m4v|webm)$/i;
  const MEDIA_IMAGE_RE = /\.(png|jpe?g|gif|webp|bmp)$/i;
  const MEDIA_HOPS = 6;
  const MEDIA_RETRY_MS = 60000;
  const MEDIA_CACHE_MAX = 48;
  // Плеер Claude без кадра (preload="none") — 300×150, замер 23.10.
  const MEDIA_PLATE = [300, 150];
  const MEDIA_GONE_NOTE = "Ролик не нашёлся на диске — открыт плеер Claude";
  const mediaState = { cache: new Map(), videos: new Map(), images: new Map(), blobs: new Set(), asked: 0, failed: 0, opens: 0, given: 0, last: null };
  // Путь файла из пропсов волокна над узлом: строка path с этим же именем файла.
  const mediaPathOf = (node, name) => {
    let fiber = openChromeFiber(node);
    for (let hop = 0; fiber && hop <= MEDIA_HOPS; hop += 1, fiber = fiber.return) {
      const raw = fiber.memoizedProps?.path;
      if (typeof raw !== "string") continue;
      const path = filePathFrom(raw);
      if (path.startsWith("/") && !path.includes("\0") && path.split("/").pop() === name) return path;
    }
    return "";
  };
  const mediaInFeed = node => Boolean(node?.isConnected) && !node.closest?.("[data-cds-composer-attachments]")
    && !node.closest?.(`[${MEDIA_PLAY_ATTRIBUTE}]`);
  // Ролик Claude: {name, path}; не его ролик, не ролик или имени нет — null.
  const mediaVideoFile = video => {
    if (!mediaInFeed(video)) return null;
    const src = String(video.getAttribute?.("src") || video.querySelector?.("source[src]")?.getAttribute?.("src") || "").trim();
    if (!src || MEDIA_OWN_SRC_RE.test(src)) return null;
    let name = String(video.getAttribute?.("title") ?? "").trim();
    let path = name ? mediaPathOf(video, name) : "";
    if (!name) {
      // Без подписи — имя из пропсов или из адреса (не адрес файла Claude).
      let fiber = openChromeFiber(video);
      for (let hop = 0; fiber && hop <= MEDIA_HOPS && !path; hop += 1, fiber = fiber.return) {
        const raw = fiber.memoizedProps?.path;
        if (typeof raw === "string" && filePathFrom(raw).startsWith("/")) path = filePathFrom(raw);
      }
      name = path ? path.split("/").pop() : MEDIA_CLAUDE_FILE_RE.test(src) ? "" : filePathFrom(src.replace(/[?#].*$/s, "")).split("/").pop();
    }
    if (!name || name.includes("/") || !MEDIA_VIDEO_RE.test(name)) return null;
    return { name, path };
  };
  // Картинка-вложение Claude: {name, path}; иначе null.
  const mediaImageFile = img => {
    if (!mediaInFeed(img)) return null;
    const name = String(img.getAttribute?.("data-image-file-name") || img.getAttribute?.("alt") || "").trim();
    if (!name || name.includes("/") || !MEDIA_IMAGE_RE.test(name)) return null;
    const src = String(img.getAttribute?.("src") ?? "");
    const original = String(img.getAttribute?.("data-image-original-src") ?? "");
    if (!MEDIA_CLAUDE_FILE_RE.test(src) && !MEDIA_CLAUDE_FILE_RE.test(original)) return null;
    return { name, path: mediaPathOf(img, name) };
  };
  // Ролик не запускали в Claude: прячем только такой.
  const mediaUntouched = video => video.paused !== false && !(Number(video.currentTime) > 0);
  const mediaKey = (kind, found, chat) => `${kind}|${chat}|${found.path || found.name}`;
  const mediaUrl = (kind, found, chat) => `http://127.0.0.1:${HTML_CHROME_PORT}/media-${kind}?chat=${encodeURIComponent(chat)}` +
    `&name=${encodeURIComponent(found.name)}${found.path ? `&path=${encodeURIComponent(found.path)}` : ""}`;
  // Вид по первым байтам: кадр — только JPEG, картинка — PNG, JPEG, GIF, WebP, BMP; чужой ответ картинкой не станет.
  const mediaMime = (kind, bytes) => {
    if (!bytes || bytes.length < 4) return "";
    const at = (i, value) => bytes[i] === value;
    if (at(0, 0xFF) && at(1, 0xD8)) return "image/jpeg";
    if (kind === "thumb") return "";
    if (at(0, 0x89) && at(1, 0x50) && at(2, 0x4E) && at(3, 0x47)) return "image/png";
    if (at(0, 0x47) && at(1, 0x49) && at(2, 0x46)) return "image/gif";
    if (bytes.length >= 12 && at(0, 0x52) && at(1, 0x49) && at(8, 0x57) && at(9, 0x45) && at(10, 0x42) && at(11, 0x50)) return "image/webp";
    if (at(0, 0x42) && at(1, 0x4D)) return "image/bmp";
    return "";
  };
  const mediaObjectUrl = (bytes, mime) => {
    try {
      if (typeof URL !== "undefined" && typeof URL.createObjectURL === "function" && typeof Blob === "function") {
        const url = URL.createObjectURL(new Blob([bytes], { type: mime }));
        mediaState.blobs.add(url);
        return url;
      }
    } catch {}
    return `data:${mime};base64,${heicBase64(bytes)}`;
  };
  const mediaRevoke = url => {
    if (!mediaState.blobs.delete(url)) return;
    try { URL.revokeObjectURL(url); } catch {}
  };
  const mediaInUse = url => [...mediaState.videos.values(), ...mediaState.images.values()].some(item => item.url === url);
  const mediaTrim = () => {
    while (mediaState.cache.size > MEDIA_CACHE_MAX) {
      const [key, entry] = mediaState.cache.entries().next().value;
      mediaState.cache.delete(key);
      if (entry.url && !mediaInUse(entry.url)) mediaRevoke(entry.url);
    }
  };
  const mediaLater = () => { if (state.alive) { try { mediaTick(); } catch {} } };
  // Запись кэша {url, plate, pending, failAt}; запроса нет (нет fetch) — null.
  const mediaAsk = (kind, found, chat) => {
    const key = mediaKey(kind, found, chat);
    const have = mediaState.cache.get(key);
    if (have && (have.pending || have.url || have.plate || now() - have.failAt < MEDIA_RETRY_MS)) return have;
    if (typeof fetch !== "function") return null;
    const entry = { key, url: null, plate: false, pending: true, failAt: -Infinity };
    mediaState.cache.delete(key);
    mediaState.cache.set(key, entry);
    mediaTrim();
    mediaState.asked += 1;
    const fail = () => { entry.pending = false; entry.failAt = now(); mediaState.failed += 1; mediaLater(); };
    let sent = null;
    try { sent = fetch(mediaUrl(kind, found, chat), { mode: "cors", credentials: "omit", cache: "no-store" }); } catch { sent = null; }
    if (!sent || typeof sent.then !== "function") { fail(); return entry; }
    sent.then(reply => {
      if (kind === "thumb" && Number(reply?.status) === 204) { entry.pending = false; entry.plate = true; mediaLater(); return null; }
      if (!reply?.ok || typeof reply.arrayBuffer !== "function") return fail();
      return reply.arrayBuffer().then(buffer => {
        const bytes = buffer ? new Uint8Array(buffer) : null;
        const mime = mediaMime(kind, bytes);
        if (!mime) return fail();
        entry.pending = false;
        entry.url = mediaObjectUrl(bytes, mime);
        mediaLater();
        return null;
      }, fail);
    }, fail).catch(() => {});
    return entry;
  };
  // Своя кнопка на место ролика: кадр с ▶ или плашка размером плеера Claude.
  const mediaButton = (video, found, entry) => {
    const button = document.createElement("button");
    button.setAttribute("type", "button");
    button.setAttribute(MEDIA_PLAY_ATTRIBUTE, entry.url ? "frame" : "plate");
    // Классы плеера Claude: тот же отступ, скругление и потолок 320×240.
    const classes = String(video.getAttribute("class") ?? "");
    if (classes) button.setAttribute("class", classes);
    button.setAttribute("title", found.name);
    button.setAttribute("aria-label", `▶ ${found.name} — открыть с диска`);
    if (entry.url) {
      const img = document.createElement("img");
      img.setAttribute("src", entry.url);
      img.setAttribute("alt", "");
      img.setAttribute("draggable", "false");
      button.appendChild(img);
    } else {
      let box = null;
      try { box = video.getBoundingClientRect(); } catch { box = null; }
      const width = box?.width > 0 ? box.width : MEDIA_PLATE[0];
      const height = box?.height > 0 ? box.height : MEDIA_PLATE[1];
      button.style.setProperty("width", `${Math.round(width)}px`);
      button.style.setProperty("height", `${Math.round(height)}px`);
      const label = document.createElement("span");
      label.setAttribute("data-k", "name");
      label.textContent = found.name;
      button.appendChild(label);
    }
    const play = document.createElement("span");
    play.setAttribute("data-k", "play");
    play.setAttribute("aria-hidden", "true");
    button.appendChild(play);
    return button;
  };
  const mediaPlace = (video, found, chat, entry) => {
    const parent = video.parentNode;
    if (!parent) return;
    const button = mediaButton(video, found, entry);
    parent.insertBefore(button, video.nextSibling);
    video.setAttribute(MEDIA_ATTRIBUTE, "hidden");
    mediaState.videos.set(video, { button, found, chat, key: entry.key, url: entry.url });
  };
  // Снять кнопку; ролик — снова плеер Claude (claude — этот узел больше не трогаем).
  const mediaUnplace = (video, back = false) => {
    const item = mediaState.videos.get(video);
    mediaState.videos.delete(video);
    try { item?.button?.remove(); } catch {}
    try {
      if (back) video.setAttribute(MEDIA_ATTRIBUTE, "claude");
      else if (video.getAttribute(MEDIA_ATTRIBUTE) === "hidden") video.removeAttribute(MEDIA_ATTRIBUTE);
    } catch {}
  };
  const mediaSwap = (img, entry) => {
    const item = { src: img.getAttribute("src"), srcset: img.getAttribute("srcset"), url: entry.url, key: entry.key };
    mediaState.images.set(img, item);
    if (item.srcset != null) img.removeAttribute("srcset");
    img.setAttribute("src", entry.url);
    img.setAttribute(MEDIA_ATTRIBUTE, "file");
  };
  const mediaRestore = (img, mark = "") => {
    const item = mediaState.images.get(img);
    mediaState.images.delete(img);
    if (!item) return;
    try {
      if (img.getAttribute("src") === item.url) {
        if (item.src == null) img.removeAttribute("src"); else img.setAttribute("src", item.src);
        if (item.srcset != null) img.setAttribute("srcset", item.srcset);
      }
      if (mark) img.setAttribute(MEDIA_ATTRIBUTE, mark); else img.removeAttribute(MEDIA_ATTRIBUTE);
    } catch {}
  };
  // Общий проход сердцебиения (910): разметка ровно по роликам и картинкам, что сейчас в ленте.
  const mediaTick = () => {
    if (!themable || !state.alive) return;
    for (const [video, item] of [...mediaState.videos]) {
      // Узел ушёл, кнопку унесли или ролик стал другим файлом — снять (ролик заново пройдёт ниже).
      const same = video.isConnected && item.button.isConnected && item.button.previousSibling === video
        && mediaVideoFile(video)?.name === item.found.name;
      if (!same) mediaUnplace(video);
    }
    try {
      for (const button of document.querySelectorAll(`[${MEDIA_PLAY_ATTRIBUTE}]`)) {
        if (![...mediaState.videos.values()].some(item => item.button === button)) button.remove();
      }
    } catch {}
    for (const [img, item] of [...mediaState.images]) {
      if (!img.isConnected) { mediaState.images.delete(img); continue; }
      // React сменил адрес — картинка уже не наша, метку снимаем.
      if (img.getAttribute("src") !== item.url) { mediaState.images.delete(img); img.removeAttribute(MEDIA_ATTRIBUTE); }
    }
    const chat = galleryChat();
    if (!chat) return;
    let videos = [];
    try { videos = [...document.querySelectorAll(MEDIA_VIDEO_SELECTOR)]; } catch { videos = []; }
    for (const video of videos) {
      if (mediaState.videos.has(video) || video.getAttribute(MEDIA_ATTRIBUTE) === "claude" || !mediaUntouched(video)) continue;
      const found = mediaVideoFile(video);
      const entry = found ? mediaAsk("thumb", found, chat) : null;
      if (entry && !entry.pending && (entry.url || entry.plate)) mediaPlace(video, found, chat, entry);
    }
    let imgs = [];
    try { imgs = [...document.querySelectorAll(MEDIA_IMG_SELECTOR)]; } catch { imgs = []; }
    for (const img of imgs) {
      if (mediaState.images.has(img) || img.getAttribute(MEDIA_ATTRIBUTE) === "claude") continue;
      const found = mediaImageFile(img);
      const entry = found ? mediaAsk("file", found, chat) : null;
      if (entry?.url) mediaSwap(img, entry);
    }
  };
  // Нажатие: файл в панель материалов (или галерею); не нашёлся — плеер Claude обратно.
  const mediaOpenUrl = (found, chat, dock) => {
    if (found.path) return htmlChromeUrl(found.path, "click", chat, null, "", dock);
    const room = dock ? dockPlaceKeys(dock) : "";
    return `http://127.0.0.1:${HTML_CHROME_PORT}/open-html?mode=click${room ? "&dock=1" : ""}&name=${encodeURIComponent(found.name)}` +
      `&chat=${encodeURIComponent(chat)}${room ? `&${room}` : ""}`;
  };
  const mediaOpen = video => {
    const item = mediaState.videos.get(video);
    if (!item || item.button.getAttribute(BUSY_ATTRIBUTE) != null) return false;
    const { button, found, chat } = item;
    mediaState.opens += 1;
    let dock = null;
    try { dock = dockForFile(); } catch { dock = null; }
    mediaState.last = { name: found.name, path: found.path || null, via: dock ? "dock" : "app", ok: null };
    const last = mediaState.last;
    button.setAttribute(BUSY_ATTRIBUTE, "file");
    const idle = setTimeout(() => { try { button.removeAttribute(BUSY_ATTRIBUTE); } catch {} }, HTML_CHROME_REPEAT_MS);
    const done = ok => {
      clearTimeout(idle);
      try { button.removeAttribute(BUSY_ATTRIBUTE); } catch {}
      last.ok = ok;
      if (!state.alive) return;
      if (dock) { try { dockSync(true); } catch {} }
      if (ok) return;
      // Пимп не нашёл файл, не ответил или не знает `name` (старый) — плеер Claude, как было.
      const entry = mediaState.cache.get(item.key);
      if (entry) { entry.url = null; entry.plate = false; entry.failAt = now(); }
      mediaState.given += 1;
      mediaUnplace(video, true);
      try { newWindowNote(MEDIA_GONE_NOTE); } catch {}
    };
    if (typeof fetch !== "function") { done(false); return true; }
    let sent = null;
    try { sent = fetch(mediaOpenUrl(found, chat, dock), { mode: "cors", credentials: "omit", cache: "no-store" }); } catch { sent = null; }
    if (!sent || typeof sent.then !== "function") { done(false); return true; }
    // Ответ: `{found, taken, opened}` у `name`, `{taken, opened}` у дока, 204 у прежнего `click` с путём. Без тела —
    // верим только запросу с путём (старый Пимп `name` не знает и молчит 204).
    const bare = reply => done(Boolean(found.path) && Boolean(reply?.ok));
    sent.then(reply => {
      if (typeof reply?.json !== "function") return bare(reply);
      return reply.json().then(body => done(body?.found === true || (body?.found !== false && Boolean(found.path) && Boolean(reply.ok))),
        () => bare(reply));
    }, () => done(false)).catch(() => {});
    return true;
  };
  const mediaVideoOf = button => [...mediaState.videos].find(([, item]) => item.button === button)?.[0] ?? null;
  // Захват окна — раньше захватов документа (свёртки, «Прочитано», файлы 12д): нажатие своей кнопки — только своё.
  const onMediaClick = event => {
    const button = event.target?.closest?.(`[${MEDIA_PLAY_ATTRIBUTE}]`);
    if (!button) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (!state.alive || event.isTrusted !== true || (event.button ?? 0) !== 0) return;
    const video = mediaVideoOf(button);
    if (video) mediaOpen(video);
  };
  // Нажатие мышью фокус из поля ввода не уводит.
  const onMediaPress = event => { if (event.target?.closest?.(`[${MEDIA_PLAY_ATTRIBUTE}]`)) event.preventDefault(); };
  // Картинка с диска не загрузилась — исходный адрес Claude.
  const onMediaError = event => {
    const img = event.target;
    if (mediaState.images.has(img)) mediaRestore(img, "claude");
  };
  on(window, "click", onMediaClick, true);
  on(window, "pointerdown", onMediaPress, true);
  on(window, "mousedown", onMediaPress, true);
  on(document, "error", onMediaError, true);
  track(() => {
    for (const video of [...mediaState.videos.keys()]) mediaUnplace(video);
    for (const img of [...mediaState.images.keys()]) mediaRestore(img);
    try { for (const node of document.querySelectorAll(`[${MEDIA_PLAY_ATTRIBUTE}]`)) node.remove(); } catch {}
    try { for (const node of document.querySelectorAll(`[${MEDIA_ATTRIBUTE}]`)) node.removeAttribute(MEDIA_ATTRIBUTE); } catch {}
    for (const url of [...mediaState.blobs]) mediaRevoke(url);
    mediaState.cache.clear();
  });
  // Вид (правила раздела 4 у файла фичи): ролик Claude спрятан, своя кнопка — кадр или плашка с ▶ поверх.
  lateRules.push(
    `video[${MEDIA_ATTRIBUTE}="hidden"]{display:none !important}`,
    `button[${MEDIA_PLAY_ATTRIBUTE}]{position:relative;display:block;box-sizing:border-box;padding:0;border:0;overflow:hidden;line-height:0;background:#000;cursor:pointer;user-select:none;-webkit-user-select:none}`,
    `[${MEDIA_PLAY_ATTRIBUTE}]>img{display:block;width:auto;height:auto;max-width:320px;max-height:240px;pointer-events:none;-webkit-user-drag:none}`,
    `button[${MEDIA_PLAY_ATTRIBUTE}="plate"]{background:var(--cds-surface-2,#232528);box-shadow:inset 0 0 0 1px var(--cds-border,rgba(127,127,127,.3))}`,
    `[${MEDIA_PLAY_ATTRIBUTE}]>[data-k="name"]{position:absolute;left:12px;right:12px;bottom:10px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;font:500 12px/16px var(--cds-font-sans,-apple-system,system-ui,sans-serif);color:var(--cds-text-secondary,rgba(255,255,255,.7));text-align:left}`,
    `[${MEDIA_PLAY_ATTRIBUTE}]>[data-k="play"]{position:absolute;left:50%;top:50%;width:44px;height:44px;margin:-22px 0 0 -22px;border-radius:50%;background:rgba(0,0,0,.55);box-shadow:0 0 0 1px rgba(255,255,255,.35);transition:background-color .15s,transform .15s;pointer-events:none}`,
    `[${MEDIA_PLAY_ATTRIBUTE}]>[data-k="play"]::before{content:"";position:absolute;left:17px;top:13px;border-style:solid;border-width:9px 0 9px 14px;border-color:transparent transparent transparent #fff}`,
    `[${MEDIA_PLAY_ATTRIBUTE}]:hover>[data-k="play"]{background:rgba(0,0,0,.75);transform:scale(1.06)}`,
    `[${MEDIA_PLAY_ATTRIBUTE}]:focus-visible{outline:2px solid var(--cds-text-accent,currentColor);outline-offset:2px}`,
    `[${MEDIA_PLAY_ATTRIBUTE}][${BUSY_ATTRIBUTE}]{cursor:progress}`,
    `[${MEDIA_PLAY_ATTRIBUTE}][${BUSY_ATTRIBUTE}]>[data-k="play"]{animation:myclaude-media-wait 1s ease-in-out infinite}`,
    `@keyframes myclaude-media-wait{0%,100%{opacity:1}50%{opacity:.45}}`,
  );
  // Ролики и картинки с диска (#10699, раздел 12п⁵): своих кнопок на месте роликов (кадром и плашкой), картинок
  // с диска; запросов к приложению, отказов; нажатий; роликов, отданных плееру Claude; последнее нажатие.
  statusPart("chatMedia", () => {
    const items = [...mediaState.videos.values()];
    return {
      videos: items.length, frames: items.filter(item => item.url).length, plates: items.filter(item => !item.url).length,
      images: mediaState.images.size, asked: mediaState.asked, failed: mediaState.failed, opens: mediaState.opens,
      given: mediaState.given, last: mediaState.last ? { ...mediaState.last } : null,
    };
  });
  HATCH && Object.assign(HATCH, { mediaTick, mediaState, mediaVideoFile, mediaImageFile, mediaOpenUrl, MEDIA_RETRY_MS });
