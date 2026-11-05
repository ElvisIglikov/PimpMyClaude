  // ---- 12п. Кнопка «Галерея» (#7724, WF97) ---------------------------------
  // Слово Элвиса 26.09: «там в правом углу под кнопкой Enter должна быть кнопка
  // „Галерея“. Нажимаешь, и то окошко фильтруется сразу же… по артефактам
  // текущего чата только… и там могу снять фильтр, и здесь… они должны
  // жениться». Макет docs/11.html, раздел 6.
  //
  // Волна 2 (слово Элвиса 26.09 ~04:23, по живой кнопке): «выводить не справа,
  // а слева… правее „+ Auto“ (левее Opus 5.5); если в чате нет артефактов —
  // кнопки нет; название Галерея нормальное; кнопку осветить».
  //
  // Кнопка — свой узел в body (как микрофон 12з): в открытом поле — в нижней
  // строке сразу правее левой группы «+ Auto» (живой замер 26.09: строка — flex,
  // левая группа — ближайший предыдущий сосед с кнопками у предка кнопки
  // модели, правая — ms-auto); группе дано поле справа под кнопку (метка
  // GALLERY_ROOM_ATTRIBUTE — правило раздела 4), модель отъезжает вправо. Нет
  // кнопки модели — нет и места, кнопки нет. В свёрнутом — «▦» левее
  // микрофона у кружка (нет микрофона — левее кружка). id чата неизвестен —
  // кнопки нет. Видна, только если у чата есть файлы в Viewer: числа шлёт
  // приложение командой viewer-counts (К-V7, раздел 15); на кнопке — только значок
  // (#9507), число файлов и непросмотренных — в подсказке; есть непросмотренные —
  // метка data-fresh (у кружка — точка).
  // Нажатие (К-V1): GET /viewer?chat=<id>&on=1|0 на порт приложения, кнопка
  // горит сразу. Фильтр живёт в Viewer: команда viewer-chat (К-V2, раздел 15)
  // зажигает кнопку, только если в фильтре этот чат, иначе гасит. Горит она
  // по чату, а не по окну: окно ушло в другой чат — гаснет само.
  const galleryState = { on: false, chat: null, clicks: 0, repeats: 0, heard: 0, last: null, counts: null, counted: 0, answer: null };
  const galleryNode = (() => {
    for (const orphan of document.querySelectorAll(`#${GALLERY_ID}`)) orphan.remove();
    const node = document.createElement("div");
    node.id = GALLERY_ID;
    node.setAttribute("role", "button");
    node.setAttribute("aria-label", "Галерея: файлы этого чата в Pimp Viewer");
    node.title = "Галерея — Pimp Viewer: только файлы этого чата";
    // WF103 (#7965): значок — четыре квадрата 2×2 узлами SVG (как у микрофона 12з: без innerHTML), цвет —
    // текущий. С WF183 (слово Элвиса 09.10 03:15: «значок сильно яркий — линии не заполненные, а
    // пустые»): квадраты — контуром, без заливки. С #9507 числа рядом со значком нет.
    try {
      const ns = "http://www.w3.org/2000/svg";
      const svg = document.createElementNS(ns, "svg");
      svg.setAttribute("viewBox", "0 0 16 16");
      svg.setAttribute("fill", "none");
      svg.setAttribute("stroke", "currentColor");
      svg.setAttribute("stroke-width", "1.3");
      for (const [x, y] of [[1.65, 1.65], [9.35, 1.65], [1.65, 9.35], [9.35, 9.35]]) {
        const cell = document.createElementNS(ns, "rect");
        cell.setAttribute("x", String(x)); cell.setAttribute("y", String(y));
        cell.setAttribute("width", "5"); cell.setAttribute("height", "5");
        cell.setAttribute("rx", "1.2");
        svg.appendChild(cell);
      }
      node.appendChild(svg);
    } catch {}
    (document.body ?? document.documentElement).appendChild(node);
    track(() => node.remove());
    return node;
  })();
  // Место под кнопку — поле справа у левой группы строки: метка и ширина.
  let galleryRoomNode = null;
  const galleryUnroom = node => {
    try { node?.removeAttribute(GALLERY_ROOM_ATTRIBUTE); node?.style.removeProperty(GALLERY_ROOM_VARIABLE); } catch {}
  };
  const galleryRoom = (node, room) => {
    if (galleryRoomNode !== node) {
      galleryUnroom(galleryRoomNode);
      galleryRoomNode = node;
    }
    if (!node) return;
    const value = `${Math.round(room)}px`;
    if (node.getAttribute(GALLERY_ROOM_ATTRIBUTE) !== value) node.setAttribute(GALLERY_ROOM_ATTRIBUTE, value);
    if (node.style.getPropertyValue(GALLERY_ROOM_VARIABLE) !== value) node.style.setProperty(GALLERY_ROOM_VARIABLE, value);
  };
  try { for (const node of document.querySelectorAll(`[${GALLERY_ROOM_ATTRIBUTE}]`)) galleryUnroom(node); } catch {}
  track(() => galleryRoom(null));
  const galleryChat = () => {
    try { return myChatId() || null; } catch { return null; }
  };
  const galleryLit = () => galleryState.on && galleryState.chat != null && galleryState.chat === galleryChat();
  // Числа этого чата из viewer-counts (К-V7): [файлов, непросмотренных].
  const galleryNumbers = () => {
    const chat = galleryChat();
    const pair = chat && galleryState.counts ? galleryState.counts[chat] : null;
    const files = Array.isArray(pair) && Number.isFinite(pair[0]) ? Math.max(0, Math.floor(pair[0])) : 0;
    const unseen = Array.isArray(pair) && Number.isFinite(pair[1]) ? Math.max(0, Math.floor(pair[1])) : 0;
    return { files, unseen: Math.min(unseen, files) };
  };
  const galleryPaint = () => {
    const value = galleryLit() ? "true" : "false";
    if (galleryNode.dataset.on !== value) galleryNode.dataset.on = value;
    galleryNode.setAttribute("aria-pressed", value);
    // Числа на кнопке нет (#9507): сколько файлов и сколько не смотрел — в подсказке.
    const { files, unseen } = galleryNumbers();
    const fresh = unseen > 0 ? "true" : "false";
    if (galleryNode.dataset.fresh !== fresh) galleryNode.dataset.fresh = fresh;
    const title = unseen > 0 ? `Галерея — Pimp Viewer: только файлы этого чата (${files}, не смотрел ${unseen})`
      : `Галерея — Pimp Viewer: только файлы этого чата (${files})`;
    if (galleryNode.title !== title) galleryNode.title = title;
  };
  const galleryHide = () => {
    galleryRoom(null);
    if (galleryNode.style.getPropertyValue("display") !== "none") galleryNode.style.setProperty("display", "none");
  };
  const galleryShow = (left, top, spot, compact) => {
    galleryNode.style.setProperty("display", "flex");
    galleryNode.style.setProperty("left", `${Math.round(left)}px`);
    galleryNode.style.setProperty("top", `${Math.round(top)}px`);
    if (galleryNode.dataset.spot !== spot) galleryNode.dataset.spot = spot;
    const flag = compact ? "true" : "false";
    if (galleryNode.dataset.compact !== flag) galleryNode.dataset.compact = flag;
  };
  // Левая группа нижней строки («+ Auto»): у предков кнопки модели — ближайший
  // предыдущий сосед с кнопками (живой замер 26.09: ms-auto-группа модели и
  // перед ней группа «Add» + режим).
  const galleryAnchor = chin => {
    let model = null;
    try { model = chin?.querySelector(CHIN_MODEL_SELECTOR); } catch { model = null; }
    for (let node = model; node && node !== chin; node = node.parentElement) {
      for (let prev = node.previousElementSibling; prev; prev = prev.previousElementSibling) {
        try { if (prev.querySelector("button")) return prev; } catch {}
      }
    }
    return null;
  };
  // Кнопка «PMP» (12п¹) встаёт рядом: в открытом поле — правее «Галереи» (место
  // у левой группы — на обе), у кружка — между микрофоном и «Галереей».
  const galleryOff = () => {
    if (galleryNode.style.getPropertyValue("display") !== "none") galleryNode.style.setProperty("display", "none");
  };
  // Шрифт подписей нижней строки поля (#9181) — для полосы Рика (12п²), «Галереи» и PMP в строке:: гарнитура, кегль и цвет подписей нижней строки поля (кнопка «BY», «O 5.5»,
  // «EX» — метка CHIN_ATTRIBUTE="text"); их нет (свёрнуто, чужая сборка, стенд) — системный 11 px и
  // цвет текста поля. Кегль зажат 9…13: чужая разметка не раздует полосу.
  const chinInk = () => {
    let style = null;
    try {
      const node = micChin()?.querySelector?.(`[${CHIN_ATTRIBUTE}="text"]`) ?? null;
      style = node ? getComputedStyle(node) : null;
    } catch { style = null; }
    const size = parseFloat(style?.fontSize);
    return {
      family: String(style?.fontFamily ?? "").trim() || RICK_FONT_FALLBACK,
      size: Number.isFinite(size) && size > 0 ? Math.max(9, Math.min(13, size)) : RICK_TEXT_SIZE,
      color: String(style?.color ?? "").trim(),
    };
  };
  const placeGallery = () => {
    galleryPaint();
    const { files } = galleryNumbers();
    const pmp = pmpWanted();
    const basic = state.alive && state.watching && galleryChat();
    // Чата или кнопки здесь больше нет — открытой панели оркестрации (12п³) не от чего висеть.
    if (pmpPanel.open && !(basic && pmp)) { try { pmpPanelClose(); } catch {} }
    const shown = basic && files >= 1;
    if (!basic || (!shown && !pmp)) { galleryHide(); pmpHide(); return; }
    if (state.stage !== STAGE_COLLAPSED) {
      const chin = micChin();
      const group = chin?.isConnected ? galleryAnchor(chin) : null;
      const rect = group ? group.getBoundingClientRect() : null;
      if (!(rect && rect.width > 0 && rect.height > 0 && rect.top >= 0 && rect.bottom <= innerHeight + GALLERY_HEIGHT)) {
        galleryHide();
        pmpHide();
        return;
      }
      const compact = innerWidth <= GALLERY_COMPACT_MAX;
      const room = GALLERY_INSET + (shown ? GALLERY_WIDTH + GALLERY_INSET : 0) + (pmp ? pmpWidth() + GALLERY_INSET : 0);
      galleryRoom(group, room);
      // Значок и надпись — цветом, гарнитурой и кеглем подписей строки (BY, EX), не белее их (#9181).
      const ink = chinInk();
      for (const node of [galleryNode, pmpNode]) {
        if (ink.color) node.style.setProperty("--k", ink.color); else node.style.removeProperty("--k");
        node.style.setProperty("--rf", ink.family);
        node.style.setProperty("--rs", `${ink.size}px`);
      }
      // По середине строки подписей (кнопка модели, строка 16): надпись «PMP» — на одной базовой
      // линии с «O 5.5» и «BP», значок — по её середине (#9195: «всё плавает»); подписи нет — по группе.
      let line = null;
      try {
        const model = '[data-testid="epitaxy-cds-model-selector"]';
        const node = chin.querySelector?.(`${model} [${CHIN_ATTRIBUTE}="text"],${model}[${CHIN_ATTRIBUTE}="text"]`);
        line = node?.isConnected ? node.getBoundingClientRect() : null;
      } catch { line = null; }
      const mid = line && line.height > 0 ? line.top + line.height / 2 : rect.top + rect.height / 2;
      let left = rect.right + GALLERY_INSET;
      if (shown) {
        galleryShow(left, mid - GALLERY_HEIGHT / 2, "field", compact);
        left += GALLERY_WIDTH + GALLERY_INSET;
      } else galleryOff();
      if (pmp) pmpShow(left, mid - PMP_HEIGHT / 2, "field");
      else pmpHide();
      return;
    }
    galleryRoom(null);
    const ring = ringNode();
    const rect = ring?.isConnected ? ring.getBoundingClientRect() : null;
    if (!(rect && rect.width > 0 && rect.height > 0 && rect.top >= 0 && rect.bottom <= innerHeight + GALLERY_HEIGHT)) {
      galleryHide();
      pmpHide();
      return;
    }
    // Микрофон у кружка стоит — встаём левее него, иначе левее самого кружка.
    const micLeft = parseFloat(micNode.style.getPropertyValue("left"));
    const micThere = micNode.style.getPropertyValue("display") !== "none" && micNode.dataset.spot === "ring" && Number.isFinite(micLeft);
    let right = micThere ? micLeft : rect.left;
    if (pmp) {
      pmpShow(right - MIC_GAP - pmpWidth(), rect.top + (rect.height - PMP_HEIGHT) / 2, "ring");
      right -= MIC_GAP + pmpWidth();
    } else pmpHide();
    if (!shown) { galleryOff(); return; }
    galleryShow(right - MIC_GAP - GALLERY_WIDTH, rect.top + (rect.height - GALLERY_HEIGHT) / 2, "ring", true);
  };
  // Запрос приложению (К-V1): запрос CORS без credentials, дошёл — и ладно.
  const galleryUrl = (chat, on) =>
    `http://127.0.0.1:${HTML_CHROME_PORT}/viewer?chat=${encodeURIComponent(chat)}&on=${on ? 1 : 0}`;
  // Нажатие не молчит (#9631, жалоба коллеги 10.10: «нажимаю и ничего не открывается»): приложение отвечает
  // словом исхода (ViewerClient.GalleryOutcome), отказ — плашкой с причиной, кнопка возвращается как была.
  // opened/off — видно и так (окно галереи, кнопка); 204 без слова — старое приложение, молчим, как раньше.
  const GALLERY_NOTES = {
    launching: "PimpViewer не запущен — открываю",
    "no-window": "Галерея ответила, но окна не видно: чат ей неизвестен или окно на другом рабочем столе",
    missing: "Галерея недоступна: PimpViewer не установлен",
    foreign: "Галерея недоступна: порт 47616 занят другой программой",
    "no-token": "Галерея недоступна: нет ключа канала — перезапусти PimpViewer",
    silent: "Галерея недоступна: PimpViewer не отвечает",
    refused: "Галерея недоступна: PimpViewer отказал",
  };
  const GALLERY_NOTE_NO_PIMP = "Галерея недоступна: PMP не отвечает (порт 47615)";
  const galleryAnswered = (chat, was, status, word) => {
    if (!state.alive || chat !== galleryChat()) return;
    galleryState.answer = word || (status ? String(status) : "network");
    const ok = word === "opened" || word === "off" || word === "launching";
    if (ok) {
      galleryState.on = word !== "off";
      galleryState.chat = galleryState.on ? chat : null;
      galleryPaint();
    } else if (word || !status || status >= 400) {
      // Отказ: кнопка — как была до нажатия; фильтр Viewer пришлёт сам, если он есть.
      galleryState.on = was;
      galleryState.chat = was ? chat : null;
      galleryPaint();
    }
    const note = GALLERY_NOTES[word] ?? (!status ? GALLERY_NOTE_NO_PIMP
      : status >= 400 && !word ? `Галерея недоступна: PMP ответил ${status}` : "");
    if (note) { try { newWindowNote(note); } catch {} }
  };
  const galleryToggle = () => {
    const chat = galleryChat();
    if (!chat) return false;
    const was = galleryLit();
    const on = !was;
    galleryState.on = on;
    galleryState.chat = chat;
    galleryState.clicks += 1;
    galleryState.last = galleryUrl(chat, on);
    galleryState.answer = null;
    galleryPaint();
    if (typeof fetch === "function") {
      try {
        fetch(galleryState.last, { mode: "cors", credentials: "omit", cache: "no-store" }).then(response => {
          const status = Number(response?.status) || 0;
          if (typeof response?.text !== "function") return;
          return response.text().then(word => galleryAnswered(chat, was, status, String(word ?? "").trim()),
            () => galleryAnswered(chat, was, status, ""));
        }, () => galleryAnswered(chat, was, 0, "")).catch(() => {});
      } catch { galleryAnswered(chat, was, 0, ""); }
    }
    return true;
  };
  // Команда viewer-chat (К-V2): какой чат сейчас в фильтре Viewer (null — никакой).
  const galleryFromViewer = detail => {
    galleryState.heard += 1;
    const chat = typeof detail?.chat === "string" && detail.chat ? detail.chat : null;
    const mine = galleryChat();
    galleryState.on = chat != null && chat === mine;
    galleryState.chat = galleryState.on ? chat : null;
    galleryPaint();
    return galleryState.on;
  };
  // Команда viewer-counts (К-V7): {"chats":{"local_…":[файлов, непросмотренных]}}
  // — только чаты с файлами; своего чата нет — файлов нет, кнопки нет.
  const galleryFromCounts = detail => {
    galleryState.counted += 1;
    const chats = detail?.chats;
    galleryState.counts = chats && typeof chats === "object" && !Array.isArray(chats) ? chats : {};
    galleryPaint();
    return galleryNumbers();
  };
  // Двойной и тройной клик (event.detail > 1, #7772) — одно нажатие: иначе
  // второе тут же снимало бы фильтр, и Viewer дёргался дважды.
  on(galleryNode, "click", event => {
    event.preventDefault();
    if (!state.alive) return;
    if (Number(event.detail) > 1) { galleryState.repeats += 1; return; }
    try { galleryToggle(); } catch {}
  });
  // Нажатие не отнимает фокус у поля ввода: черновик и курсор остаются.
  const galleryKeepFocus = event => { event.preventDefault(); };
  on(galleryNode, "pointerdown", galleryKeepFocus);
  on(galleryNode, "mousedown", galleryKeepFocus);
  // Кнопка «Галерея» (#7724, раздел 12п): видна ли, где ("field" — у правого
  // края открытого поля, "ring" — у кружка), значком ли, горит ли (фильтр
  // Viewer — этот чат), нажатия, сколько команд viewer-chat пришло, адрес
  // последнего запроса приложению.
  statusPart("gallery", () => ({
    visible: galleryNode.isConnected && galleryNode.style.display !== "none",
    spot: galleryNode.style.display !== "none" ? galleryNode.dataset.spot ?? null : null,
    compact: galleryNode.dataset.compact === "true",
    on: galleryLit(), clicks: galleryState.clicks, repeats: galleryState.repeats, heard: galleryState.heard, last: galleryState.last,
    // #9631: слово исхода последнего нажатия (opened/off/launching/no-window/missing/…; код ответа; network), null — ждём.
    answer: galleryState.answer,
    // К-V7: файлов и непросмотренных у этого чата, сколько viewer-counts пришло.
    ...galleryNumbers(), fresh: galleryNode.dataset.fresh === "true", counted: galleryState.counted,
  }));

