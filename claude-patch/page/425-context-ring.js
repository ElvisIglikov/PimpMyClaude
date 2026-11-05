  // ---- 12з². Кружок у поля ввода — только контекст этого чата (#10317) -------
  // Слово Элвиса 19.10 (12:40 и 14:30): кружок справа внизу у поля ввода, там, где «Opus 5.5», показывает «как будто
  // недельный лимит, то краснеет, то зеленеет», а должен всегда показывать только контекст — сколько контекста
  // занято в этом чате. Решение — docs/decisions/2026-10-19-kruzhok-kontekst-10317.md.
  //
  // Кружок — родная кнопка Claude (USAGE_RING_SELECTOR, раздел 1): какой лимит в нём показать и каким цветом, решает
  // Claude. Родной svg не удаляем и не меняем — React держит его узлы (шапка раздела 12ж). Прячем его своим правилом,
  // и именно opacity:0, а не display или visibility: нажатие «как мышью» бьёт в elementFromPoint и должно попасть в
  // родной svg (раздел 12з). Поверх — свой svg без нажатий: серая дорожка и дуга цвета акцента темы, дуга = токены
  // контекста этого чата / USAGE_CONTEXT_WINDOW. Число даёт приложение (/context → команда chat-context, раздел 12ж,
  // «свои строки») — то же, что строка «Контекст» в панели лимитов. Числа своего чата нет — пустая дорожка, а не
  // родной лимит. aria-label кнопки не трогаем: его читают лимиты для Пимпа (12ж¹) и свёртка (раздел 6).
  //
  // Не опознали — не трогаем, родной вид лучше сломанного: нет кружка; в нём нет родного svg; кнопка сама стоит
  // absolute или fixed (свой слой встаёт по её рамке, ей нужен position:relative); не встал наш <style> (CSP:
  // родную дугу не спрятать, вышло бы два кружка).
  //
  // Когда спрашивать приложение. Ответ едет командой через command.json — одна запись в 0,6 с на ВСЕ окна
  // (CommandChannel.minInterval), и опрос каждого окна раз в 5 с забил бы канал уже при десятке окон. Контекст растёт
  // только ходом агента, поэтому: сменился чат — сразу; идёт ход — раз в CTX_RING_WORK_MS; ход кончился — ещё раз через
  // CTX_RING_SETTLE_MS (расшифровка дописана); числа нет — раз в CTX_RING_RETRY_MS (без числа приложение команды не
  // пишет, канал это не грузит). Чат молчит и число есть — не спрашиваем.
  const CTX_RING_ATTRIBUTE = "data-myclaude-ctx-ring";
  const CTX_LAYER_ATTRIBUTE = "data-myclaude-ctx-layer";
  const CTX_PART_ATTRIBUTE = "data-myclaude-ctx-part";
  const CTX_RING_WORK_MS = 15000;
  const CTX_RING_SETTLE_MS = 2000;
  const CTX_RING_RETRY_MS = 30000;
  // layers — кнопка кружка → {layer, arc, native}; batches — state.mutationBatches на последнем поиске кружков
  // (-1 — не искали); chat — чат окна на прошлом тике (undefined — тика ещё не было); working — шёл ли ход на
  // прошлом тике; settleAt — когда спросить после конца хода (0 — не надо).
  const ctxRing = { layers: new Map(), batches: -1, chat: undefined, working: false, settleAt: 0 };
  // Сироты прошлого экземпляра (его dispose() не дошёл до конца) — до первого прохода.
  try {
    for (const orphan of document.querySelectorAll(`[${CTX_LAYER_ATTRIBUTE}]`)) orphan.remove();
    for (const node of document.querySelectorAll(`[${CTX_RING_ATTRIBUTE}]`)) node.removeAttribute(CTX_RING_ATTRIBUTE);
  } catch {}

  // Число своего чата: {chat, tokens, pct}; ответ про другой чат не в счёт — tokens и pct null.
  const ctxRingView = () => {
    let chat = null;
    try { chat = myChatId() || null; } catch { chat = null; }
    const tokens = chat && usageState.context?.chat === chat ? usageState.context.tokens : null;
    return { chat, tokens, pct: tokens == null ? null : Math.min(100, tokens / USAGE_CONTEXT_WINDOW * 100) };
  };

  // Свой слой узлами, без innerHTML (CSP, как значок 12з): круг 20×20, дуга — с 12 часов по часовой, pathLength 100 —
  // длина штриха и есть процент.
  const ctxRingLayer = () => {
    const make = (tag, attrs) => {
      const node = document.createElementNS("http://www.w3.org/2000/svg", tag);
      for (const [name, value] of Object.entries(attrs)) node.setAttribute(name, String(value));
      return node;
    };
    const layer = make("svg", { [CTX_LAYER_ATTRIBUTE]: "", viewBox: "0 0 20 20", fill: "none", "aria-hidden": "true", focusable: "false" });
    const circle = { cx: 10, cy: 10, r: 8, fill: "none", "stroke-width": 2.5 };
    const lane = make("circle", { ...circle, [CTX_PART_ATTRIBUTE]: "track" });
    const arc = make("circle", { ...circle, [CTX_PART_ATTRIBUTE]: "arc", pathLength: 100, "stroke-linecap": "round",
      transform: "rotate(-90 10 10)", "stroke-dasharray": "0 100", display: "none" });
    layer.append(lane, arc);
    return { layer, arc, native: null };
  };
  const ctxRingDrop = button => {
    const held = ctxRing.layers.get(button);
    ctxRing.layers.delete(button);
    try { held?.layer.remove(); } catch {}
    try { button.removeAttribute(CTX_RING_ATTRIBUTE); } catch {}
  };
  const ctxRingClaim = button => {
    let held = ctxRing.layers.get(button);
    let native = held?.native ?? null;
    if (!native?.isConnected || !button.contains(native)) {
      try { native = button.querySelector(`svg:not([${CTX_LAYER_ATTRIBUTE}])`); } catch { native = null; }
    }
    if (!native) { if (held) ctxRingDrop(button); return; }
    if (!held) {
      // Свёрнутое поле ставит кружок absolute само (раздел 6) — это наше; родной absolute или fixed — нет.
      if (!button.hasAttribute(RING_ATTRIBUTE)) {
        let place = "";
        try { place = getComputedStyle(button).position; } catch { place = ""; }
        if (place && place !== "static" && place !== "relative") return;
      }
      held = ctxRingLayer();
      ctxRing.layers.set(button, held);
    }
    held.native = native;
    if (!button.hasAttribute(CTX_RING_ATTRIBUTE)) button.setAttribute(CTX_RING_ATTRIBUTE, "");
    if (held.layer.parentNode !== button) button.appendChild(held.layer);
    // Рамка слоя — рамка родного svg внутри кнопки (кружок рисует он); у svg её нет — вся кнопка.
    const box = button.getBoundingClientRect();
    if (!(box.width > 0 && box.height > 0)) return;
    const art = native.getBoundingClientRect();
    const frame = art.width > 0 && art.height > 0 ? art : box;
    const px = value => `${Math.round(value * 100) / 100}px`;
    const spot = {
      left: px(frame.left - box.left - (button.clientLeft || 0)),
      top: px(frame.top - box.top - (button.clientTop || 0)),
      width: px(frame.width),
      height: px(frame.height),
    };
    for (const [name, value] of Object.entries(spot)) {
      if (held.layer.style.getPropertyValue(name) !== value) held.layer.style.setProperty(name, value);
    }
  };

  // Дуга и подсказка — по числу своего чата. Зовут раскладка, смена чата и команда chat-context (раздел 15).
  const ctxRingPaint = () => {
    if (!ctxRing.layers.size) return;
    const view = ctxRingView();
    const dash = view.pct == null ? null : `${view.pct.toFixed(2)} 100`;
    const title = view.tokens == null ? "Контекст: нет данных" : `Контекст: ${Math.round(view.tokens / 1000)}k из 1M`;
    for (const { layer, arc } of ctxRing.layers.values()) {
      if (dash == null) {
        if (arc.getAttribute("display") !== "none") arc.setAttribute("display", "none");
      } else {
        if (arc.hasAttribute("display")) arc.removeAttribute("display");
        if (arc.getAttribute("stroke-dasharray") !== dash) arc.setAttribute("stroke-dasharray", dash);
      }
      if (layer.getAttribute("title") !== title) layer.setAttribute("title", title);
    }
  };

  // Проход раскладки (раздел 9): React пересоздаёт кнопку и её детей — слой встаёт заново. Кружки ищем заново,
  // только когда DOM менялся (state.mutationBatches) или свой кружок пропал: покой страницы не стоит ни одного
  // поиска (сторож F09, tests/idle-dom.test.mjs).
  const ctxRingPlace = () => {
    const live = state.alive && state.cssOk;
    let rings = [...ctxRing.layers.keys()];
    if (!live || ctxRing.batches !== state.mutationBatches || rings.some(button => !button.isConnected)) {
      ctxRing.batches = state.mutationBatches;
      rings = [];
      if (live) { try { rings = [...document.querySelectorAll(USAGE_RING_SELECTOR)]; } catch { rings = []; } }
    }
    for (const button of [...ctxRing.layers.keys()]) {
      if (!button.isConnected || !rings.includes(button)) ctxRingDrop(button);
    }
    for (const button of rings) { try { ctxRingClaim(button); } catch {} }
    ctxRingPaint();
  };

  // Круг сторожа (раздел 16): смена чата и когда спросить приложение (шапка раздела).
  const ctxRingTick = t => {
    let chat = null;
    try { chat = myChatId() || null; } catch { chat = null; }
    if (chat !== ctxRing.chat) {
      ctxRing.chat = chat;
      ctxRing.working = false;
      ctxRing.settleAt = 0;
      ctxRingPaint();
      // Другой чат — сразу; тот же после мелькнувшего null — с зазором 12ж.
      if (chat) usageContextAsk();
      return;
    }
    if (!chat || !ctxRing.layers.size) return;
    const working = pageWorking();
    if (ctxRing.working && !working) ctxRing.settleAt = t + CTX_RING_SETTLE_MS;
    ctxRing.working = working;
    if (ctxRing.settleAt && t >= ctxRing.settleAt) {
      ctxRing.settleAt = 0;
      usageContextAsk(0);
      return;
    }
    if (working) usageContextAsk(CTX_RING_WORK_MS);
    else if (usageState.context?.chat !== chat) usageContextAsk(CTX_RING_RETRY_MS);
  };

  track(() => {
    for (const button of [...ctxRing.layers.keys()]) ctxRingDrop(button);
    try {
      for (const node of document.querySelectorAll(`[${CTX_LAYER_ATTRIBUTE}]`)) node.remove();
      for (const node of document.querySelectorAll(`[${CTX_RING_ATTRIBUTE}]`)) node.removeAttribute(CTX_RING_ATTRIBUTE);
    } catch {}
  });
  // Свёрнутое поле держит кружок absolute (раздел 6) — relative только вне его. Дорожка — цвет текста кнопки
  // бледно, дуга — акцент темы: один спокойный цвет при любом лимите.
  lateRules.push(
    `[${CTX_RING_ATTRIBUTE}]:not([${RING_ATTRIBUTE}]){position:relative !important}`,
    `[${CTX_RING_ATTRIBUTE}] svg:not([${CTX_LAYER_ATTRIBUTE}]){opacity:0 !important}`,
    `[${CTX_LAYER_ATTRIBUTE}]{position:absolute !important;display:block !important;margin:0 !important;padding:0 !important;pointer-events:none !important;overflow:visible !important;opacity:1 !important}`,
    `[${CTX_LAYER_ATTRIBUTE}] [${CTX_PART_ATTRIBUTE}="track"]{stroke:currentColor;stroke-opacity:.25}`,
    `[${CTX_LAYER_ATTRIBUTE}] [${CTX_PART_ATTRIBUTE}="arc"]{stroke:var(--cds-text-accent,#d97757)}`,
  );
  // Кружок контекста (#10317): стоит ли свой слой хоть на одном кружке, процент своего чата (null — числа нет) и чат.
  statusPart("contextRing", () => {
    const view = ctxRingView();
    let found = false;
    for (const button of ctxRing.layers.keys()) if (button.isConnected) { found = true; break; }
    return { found, pct: view.pct == null ? null : Math.round(view.pct), chat: view.chat };
  });
