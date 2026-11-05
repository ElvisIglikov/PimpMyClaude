  // ---- 12з. Микрофон у кружка и панель лимитов по наведению (#6906, #6907) --

  // Родная кнопка диктовки Claude. В свёрнутом поле она спрятана вместе со всей
  // строкой, но живая: нажатие до неё доходит (проверено живьём 21.09).
  const dictateButton = () => {
    try { return document.querySelector(DICTATE_SELECTOR); } catch { return null; }
  };
  const dictateLive = node => {
    const label = node?.getAttribute?.("aria-label") ?? "";
    return label === DICTATE_LIVE_LABEL || /stop dictation|остановить диктовку/i.test(label);
  };
  // base — текст поля на первом нажатии (К4, критик WF84 «Важное» 6): счёт
  // устойчивости идёт, только когда текст стал другим, — черновик, что уже
  // лежал в поле, сам по себе не уходит. dictating — своё «идёт запись» режима
  // dictator: родной кнопки там нет, спросить не у кого.
  // clickAt — последнее нажатие в режиме dictator (по нему окно узнаёт свой
  // отказ mic-refused), kept — сколько раз текст Диктатора лёг в видимое поле
  // без отправки, refused — сколько отказов, hintTimer — подсказка отказа.
  const micState = {
    timer: 0, until: 0, last: null, steady: 0, sends: 0, starts: 0, base: null, dictating: false,
    hiddenOnly: false, clickAt: -Infinity, kept: 0, refused: 0, hintTimer: 0,
  };
  const micMode = () => {
    try { return localStorage.getItem(MIC_MODE_KEY) === "dictator" ? "dictator" : "claude"; } catch { return "claude"; }
  };
  const micModeSet = value => {
    try { localStorage.setItem(MIC_MODE_KEY, value === "dictator" ? "dictator" : "claude"); } catch {}
  };
  const micText = () => {
    const editor = state.editor?.isConnected ? state.editor : findEditor();
    return String(editor?.textContent ?? "").trim();
  };
  const micStopWait = () => {
    if (micState.timer) { clearTimeout(micState.timer); micState.timer = 0; }
    micState.last = null;
    micState.steady = 0;
    micState.hiddenOnly = false;
  };
  track(micStopWait);

  const micNode = (() => {
    const node = document.createElement("div");
    node.id = MIC_ID;
    node.setAttribute("role", "button");
    node.setAttribute("aria-label", "Диктовка: нажать — начать, ещё раз — остановить (в свёрнутом поле — и отправить)");
    // Значок рисуем узлами, а не разметкой строкой: у страницы Claude свой CSP,
    // и innerHTML — лишний повод в него упереться. Осечка рисования не имеет
    // права утащить за собой всю установку: без значка кнопка просто пустая.
    try {
      const ns = "http://www.w3.org/2000/svg";
      const svg = document.createElementNS(ns, "svg");
      svg.setAttribute("viewBox", "0 0 24 24");
      svg.setAttribute("fill", "none");
      svg.setAttribute("stroke", "currentColor");
      svg.setAttribute("stroke-width", "2");
      svg.setAttribute("stroke-linecap", "round");
      svg.setAttribute("stroke-linejoin", "round");
      const body = document.createElementNS(ns, "rect");
      body.setAttribute("x", "9"); body.setAttribute("y", "2");
      body.setAttribute("width", "6"); body.setAttribute("height", "11");
      body.setAttribute("rx", "3");
      const arc = document.createElementNS(ns, "path");
      arc.setAttribute("d", "M5 11a7 7 0 0 0 14 0");
      const stand = document.createElementNS(ns, "path");
      stand.setAttribute("d", "M12 18v3");
      svg.append(body, arc, stand);
      node.appendChild(svg);
    } catch {}
    (document.body ?? document.documentElement).appendChild(node);
    track(() => node.remove());
    return node;
  })();

  // Кружок контекста этого окна — по нему считается место значка.
  const ringNode = () => {
    if (ringState.button?.isConnected) return ringState.button;
    try { return document.querySelector(USAGE_RING_SELECTOR); } catch { return null; }
  };

  // Нижняя строка открытого поля этого окна: та, что в своём блоке ввода, иначе
  // первая видимая.
  const micChin = () => {
    let rows = [];
    try { rows = [...document.querySelectorAll(CHIN_SELECTOR)]; } catch { return null; }
    const block = state.composerBlock?.isConnected ? state.composerBlock : null;
    const own = block ? rows.find(row => block.contains(row)) : null;
    return own ?? rows.find(row => {
      const rect = row.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    }) ?? null;
  };
  // Место под значок в строке — метка ровно на одной строке и только пока
  // значок там стоит.
  let micRoomNode = null;
  const micRoom = node => {
    if (micRoomNode !== node) {
      try { micRoomNode?.removeAttribute(MIC_ROOM_ATTRIBUTE); } catch {}
      micRoomNode = node;
    }
    if (node && !node.hasAttribute(MIC_ROOM_ATTRIBUTE)) node.setAttribute(MIC_ROOM_ATTRIBUTE, "");
  };
  try { for (const node of document.querySelectorAll(`[${MIC_ROOM_ATTRIBUTE}]`)) node.removeAttribute(MIC_ROOM_ATTRIBUTE); } catch {}
  track(() => micRoom(null));
  // Значок — целиком в окне (#9272, класс «свой элемент у края режется»): строка или кружок у самого края
  // (низ окна, узкое окно) — значок прижат внутрь, а не срезан краем. Место для приложения (micSpot) — та же рамка.
  const micShow = (left, top, spot) => {
    micNode.style.setProperty("display", "flex");
    micNode.style.setProperty("left", `${Math.round(Math.max(0, Math.min(left, innerWidth - MIC_SIZE)))}px`);
    micNode.style.setProperty("top", `${Math.round(Math.max(0, Math.min(top, innerHeight - MIC_SIZE)))}px`);
    if (micNode.dataset.spot !== spot) micNode.dataset.spot = spot;
  };

  // Значок стоит ровно слева от кружка и по его середине — «чтоб они выровнены
  // были». В режиме claude виден только в режиме чтения: в открытом поле слева
  // от кружка стоят «Opus 5» и «Max», и зона значка съедала бы нажатия по ним.
  // В режиме Диктатора (#7704) открытое поле значок тоже получает — у ЛЕВОГО
  // края рамки поля, по середине его нижней строки (там, где была «Add»).
  const placeMic = () => {
    const field = state.alive && state.watching && state.stage !== STAGE_COLLAPSED && micMode() === "dictator";
    const chin = field ? micChin() : null;
    const row = chin?.isConnected ? chin.getBoundingClientRect() : null;
    if (row && row.width > 0 && row.height > 0 && row.top >= 0 && row.bottom <= innerHeight + MIC_SIZE) {
      const frame = state.shell?.isConnected ? state.shell.getBoundingClientRect() : null;
      const edge = frame && frame.width > 0 && frame.left >= row.left ? frame.left : row.left + MIC_ROOM_PAD - MIC_SIZE - 2;
      micRoom(chin);
      // WF226 (замер живого окна 10.10): кнопки стоят в нижней строке не по середине (сверху у их ряда
      // отступ 6), и значок по середине всей строки висел на 3 px выше «+», подписей и кружка. Середина —
      // по кнопке модели, как у числа галереи и недели; кнопки нет — по строке, как было.
      let line = null;
      try { line = chin.querySelector(CHIN_MODEL_SELECTOR)?.getBoundingClientRect() ?? null; } catch { line = null; }
      const mid = line && line.height > 0 ? line.top + line.height / 2 : row.top + row.height / 2;
      micShow(edge + (innerWidth <= MIC_ROOM_TINY_MAX ? MIC_ROOM_INSET_TINY : MIC_ROOM_INSET), mid - MIC_SIZE / 2, "field");
      return;
    }
    micRoom(null);
    const ring = state.stage === STAGE_COLLAPSED ? ringNode() : null;
    const rect = ring?.isConnected ? ring.getBoundingClientRect() : null;
    // В режиме Диктатора родная кнопка не нужна: жмёт приложение.
    const live = state.alive && state.watching && rect != null && rect.width > 0 && rect.height > 0 &&
      rect.top >= 0 && rect.bottom <= innerHeight + MIC_SIZE && (micMode() === "dictator" || dictateButton() != null);
    if (!live) {
      if (micNode.style.getPropertyValue("display") !== "none") micNode.style.setProperty("display", "none");
      return;
    }
    micShow(rect.left - MIC_GAP - MIC_SIZE, rect.top + (rect.height - MIC_SIZE) / 2, "ring");
  };

  // Расшифровка приезжает после остановки и печатается кусками: ждём, пока
  // текст появится и постоит неизменным, и только тогда жмём «отправить».
  // Пусто за всё ожидание — не шлём ничего: пустое сообщение хуже молчания.
  // hiddenOnly (Диктатор, #7704): поле успели открыть до отправки — Элвис хочет
  // видеть и править текст, не шлём.
  const micSendWhenReady = (wait = MIC_WAIT_MS, hiddenOnly = false) => {
    const base = micState.base;
    micStopWait();
    micState.hiddenOnly = hiddenOnly;
    micState.until = now() + wait;
    const tick = () => {
      micState.timer = 0;
      if (!state.alive) return;
      if (micState.hiddenOnly && state.stage !== STAGE_COLLAPSED) { micStopWait(); return; }
      const text = micText();
      // Текст тот же, что на первом нажатии, — расшифровки ещё нет.
      const fresh = text !== "" && (base == null || text !== base);
      if (fresh && text === micState.last) micState.steady += 1;
      else micState.steady = 0;
      micState.last = text;
      if (micState.steady >= MIC_STEADY) {
        let send = null;
        try { send = document.querySelector(SEND_SELECTOR); } catch {}
        // И диктовка — через отсчёт (слово Элвиса 09.10 04:10: «Никаких быстрых отправок. Всё на таймере всегда»).
        const editor = state.editor;
        if (send && send.disabled !== true) {
          micState.sends += 1;
          if (editor?.isConnected) sendDelayStart(editor);
          else pressLikeMouse(send);
        }
        micStopWait();
        return;
      }
      if (now() >= micState.until) { micStopWait(); return; }
      micState.timer = setTimeout(tick, MIC_TICK_MS);
    };
    micState.timer = setTimeout(tick, MIC_TICK_MS);
  };

  const micToggle = () => {
    // Диктатор (К4): клавишу жмёт приложение, здесь — только счёт нажатий.
    // Первое — запись пошла, второе — остановка: Диктатор вставит расшифровку
    // (⌘V в переднее окно, её ловит «⌘V из любого места», раздел 12). Поле
    // спрятано (режим чтения) — отправим, когда текст сменится и постоит; поле
    // видно — текст просто ложится в поле, без отправки (#7704).
    if (micMode() === "dictator") {
      micState.clickAt = now();
      if (micState.dictating) {
        micState.dictating = false;
        if (state.stage === STAGE_COLLAPSED) micSendWhenReady(MIC_DICTATOR_WAIT_MS, true);
        else { micStopWait(); micState.kept += 1; }
      } else {
        micStopWait();
        micState.dictating = true;
        micState.base = micText();
        micState.starts += 1;
      }
      return;
    }
    const button = dictateButton();
    if (!button) return;
    const live = dictateLive(button);
    if (!live) micState.base = micText();
    if (!pressLikeMouse(button)) return;
    if (live) { micSendWhenReady(); return; }
    micState.starts += 1;
    micStopWait();
  };
  on(micNode, "click", event => {
    event.preventDefault();
    // #7873: второй щелчок двойного клика (системный счёт > 1) — не новое
    // нажатие, иначе запись тут же останавливается. Так же молчит Swift-конец
    // (MicMonitor, clickCount > 1).
    if (Number(event.detail) > 1) return;
    if (!state.alive) return;
    try { micToggle(); } catch {}
    // Мигание — сразу, не дожидаясь прохода раскладки.
    try { micPaint(); } catch {}
  });
  // Диктатор вставляет в то, что в фокусе: нажатие по кружку фокус у поля
  // отнимать не должно (К4) — гасим умолчание нажатия.
  const micKeepFocus = event => { if (micMode() === "dictator") event.preventDefault(); };
  on(micNode, "pointerdown", micKeepFocus);
  on(micNode, "mousedown", micKeepFocus);
  // Место значка для приложения (К4, поле mic в chats()): левый верхний угол
  // значка — от края и НИЗА окна, [dx, dyBottom, w, h, anchor] в точках; так
  // оно переживает сдвиг и ресайз окна, пока карта не обновилась. anchor 0 — dx
  // от ПРАВОГО края (значок у кружка), 1 — от ЛЕВОГО (значок в открытом поле,
  // WF92-ap2: поле растёт вправо, левый край стоит). Не видно — null.
  const micSpot = () => {
    if (!micNode.isConnected || micNode.style.getPropertyValue("display") === "none") return null;
    try {
      const rect = micNode.getBoundingClientRect();
      if (!(rect.width > 0 && rect.height > 0)) return null;
      const left = micNode.dataset.spot === "field";
      return [left ? rect.left : innerWidth - rect.left, innerHeight - rect.top, rect.width, rect.height]
        .map(value => Math.round(value)).concat(left ? 1 : 0);
    } catch { return null; }
  };
  // Родная кнопка диктовки Claude (#9681, слово Элвиса 11.10: «чтобы диктатор её
  // перехватывал эту кнопку… правой кнопкой… выбирать диктовка какая»): её место —
  // приложению полем micNative того же вида, что mic (anchor 0 — от правого края).
  // В режиме dictator клавишу жмёт приложение (оно ловит клик по этому месту), а
  // здесь родное «нажми и держи» гасится и идёт тот же счёт, что у кружка. Правая
  // кнопка — меню приложения: своё меню страницы ему не мешает.
  const micNativeSpot = () => {
    const button = dictateButton();
    if (!button?.isConnected) return null;
    try {
      const rect = button.getBoundingClientRect();
      if (!(rect.width > 0 && rect.height > 0) || rect.bottom <= 0 || rect.top >= innerHeight) return null;
      return [innerWidth - rect.left, innerHeight - rect.top, rect.width, rect.height]
        .map(value => Math.round(value)).concat(0);
    } catch { return null; }
  };
  const micNativeHit = event => {
    try { return event.target?.closest?.(DICTATE_SELECTOR) ?? null; } catch { return null; }
  };
  const micNativeCatch = event => {
    if (!state.alive || micMode() !== "dictator" || !micNativeHit(event)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (event.type !== "click" || Number(event.detail) > 1) return;
    try { micToggle(); } catch {}
    try { micPaint(); } catch {}
  };
  const micNativeMenu = event => {
    if (state.alive && micNativeHit(event)) event.preventDefault();
  };
  // Подписки — в разделе 16 (только наши страницы).

  // Значок горит красным, пока идёт запись. Спрашиваем у самой кнопки Claude, а
  // не у своей памяти: диктовку могли включить и выключить мимо нас.
  // В режиме Диктатора значок, пока идёт запись, ещё и ярко мигает (правило
  // раздела 4 по data-mode="dictator", #7704).
  const micPaint = () => {
    const mode = micMode();
    const on = mode === "dictator" ? micState.dictating : dictateLive(dictateButton());
    const value = on ? "true" : "false";
    if (micNode.dataset.live !== value) micNode.dataset.live = value;
    if (micNode.dataset.mode !== mode) micNode.dataset.mode = mode;
  };

  // Отказ приложения (команда mic-refused, WF92): Диктатор уже пишет, клавишу
  // приложение не нажало. Своё окно — то, где нажимали недавно: счёт нажатий
  // сбрасывается (не мигаем, отправку не взводим), у значка на MIC_HINT_MS —
  // подсказка. Остальные окна команду не замечают.
  const micHintNode = (() => {
    for (const orphan of document.querySelectorAll(`#${MIC_HINT_ID}`)) orphan.remove();
    const node = document.createElement("div");
    node.id = MIC_HINT_ID;
    node.setAttribute("role", "status");
    node.style.setProperty("display", "none");
    (document.body ?? document.documentElement).appendChild(node);
    track(() => node.remove());
    return node;
  })();
  const micHintHide = () => {
    if (micState.hintTimer) { clearTimeout(micState.hintTimer); micState.hintTimer = 0; }
    micHintNode.style.setProperty("display", "none");
  };
  track(micHintHide);
  // Адрес отказа (контракт WF92-ap2): chat — id чата нажатого окна, при
  // chat=null — match, заголовок нажатого окна. Нажатие своего микрофона не
  // старше MIC_REFUSED_MS — второе условие: два окна, нажатые подряд, отказ
  // получает только то, чей чат (заголовок) в команде.
  const micRefusedMine = detail => {
    if (typeof detail?.chat === "string" && detail.chat) {
      let id = null;
      try { id = myChatId(); } catch { id = null; }
      return id === detail.chat;
    }
    const title = typeof detail?.match === "string" ? detail.match.trim() : "";
    return Boolean(title) && windowTitle() === title;
  };
  const micRefused = detail => {
    if (!micRefusedMine(detail)) return false;
    if (!(now() - micState.clickAt <= MIC_REFUSED_MS)) return false;
    micState.clickAt = -Infinity;
    micStopWait();
    micState.dictating = false;
    micState.base = null;
    micState.refused += 1;
    micPaint();
    micHint(MIC_REFUSED_TEXT);
    return true;
  };

  // Панель лимитов по наведению (#6906). Родная подсказка на время наведения
  // глушится правилом в разделе 4, а вместо неё открывается сама панель: мышь
  // ушла — панель закрылась, нажали рукой — держится до следующего нажатия.
  const ringHoverStop = () => {
    if (usageState.hoverTimer) { clearTimeout(usageState.hoverTimer); usageState.hoverTimer = 0; }
    if (usageState.leaveTimer) { clearTimeout(usageState.leaveTimer); usageState.leaveTimer = 0; }
  };
  const ringHoverMark = on => {
    try {
      const root = document.documentElement;
      if (on) root.setAttribute(RING_HOVER_ATTRIBUTE, "");
      else root.removeAttribute(RING_HOVER_ATTRIBUTE);
    } catch {}
  };
  track(() => { ringHoverStop(); ringHoverMark(false); });
  const ringPanelClose = () => {
    const ring = ringNode();
    if (usageState.panel?.isConnected && ring) pressLikeMouse(ring);
    usageState.hoverOpen = false;
    usageClose();
  };
  const onRingOver = event => {
    let ring = null;
    let panel = null;
    try { ring = event.target?.closest?.(USAGE_RING_SELECTOR) ?? null; } catch {}
    try { panel = event.target?.closest?.(USAGE_PANEL_SELECTOR) ?? null; } catch {}
    if (!ring && !panel) return;
    usageState.over = true;
    if (usageState.leaveTimer) { clearTimeout(usageState.leaveTimer); usageState.leaveTimer = 0; }
    if (ring) ringHoverMark(true);
    if (!ring || usageState.pinned || usageState.panel?.isConnected || usageState.hoverTimer) return;
    usageState.hoverTimer = setTimeout(() => {
      usageState.hoverTimer = 0;
      const node = ringNode();
      if (!usageState.over || !node || usageState.panel?.isConnected) return;
      usageState.hoverOpen = true;
      usageWatch();
      pressLikeMouse(node);
    }, RING_HOVER_OPEN_MS);
  };
  const onRingOut = event => {
    let from = null;
    try { from = event.target?.closest?.(`${USAGE_RING_SELECTOR},${USAGE_PANEL_SELECTOR}`) ?? null; } catch {}
    if (!from) return;
    // Ушли внутрь той же кнопки или в саму панель — это не уход.
    let to = null;
    try { to = event.relatedTarget?.closest?.(`${USAGE_RING_SELECTOR},${USAGE_PANEL_SELECTOR}`) ?? null; } catch {}
    if (to) return;
    usageState.over = false;
    ringHoverMark(false);
    if (usageState.hoverTimer) { clearTimeout(usageState.hoverTimer); usageState.hoverTimer = 0; }
    if (usageState.pinned || !usageState.hoverOpen || usageState.leaveTimer) return;
    usageState.leaveTimer = setTimeout(() => {
      usageState.leaveTimer = 0;
      if (usageState.over || usageState.pinned) return;
      ringPanelClose();
    }, RING_HOVER_CLOSE_MS);
  };
  on(document, "pointerover", onRingOver, true);
  on(document, "pointerout", onRingOut, true);
  // Микрофон у кружка (#6907): виден ли значок, идёт ли запись, сколько раз
  // он включал диктовку и отправлял расшифровку.
  statusPart("mic", () => ({
    mode: micMode(), dictating: micState.dictating,
    visible: micNode.isConnected && micNode.style.display !== "none",
    live: micNode.dataset.live === "true",
    starts: micState.starts,
    sends: micState.sends,
    button: dictateButton() != null,
    // WF92 (#7704): где стоит значок ("ring" — у кружка, "field" — у
    // левого края открытого поля), мигает ли, сколько раз текст лёг в
    // видимое поле без отправки, отказы Диктатора и подсказка отказа.
    spot: micNode.style.display !== "none" ? micNode.dataset.spot ?? null : null,
    blink: micNode.dataset.live === "true" && micNode.dataset.mode === "dictator",
    kept: micState.kept,
    refused: micState.refused,
    hint: micHintNode.isConnected && micHintNode.style.display === "block",
  }));
  HATCH && Object.assign(HATCH, { micSpot, micNativeSpot });

