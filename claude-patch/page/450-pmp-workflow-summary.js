  // ---- 12п². Сводка Workflow для кнопки и панели PMP (#9077, WF134; блок у поля снят — WF239) ----
  // До page-60 здесь жил блок у поля ввода чата папки Rick: счёт Workflow по проектам (строка на проект,
  // полоска-клетки, «1 из 7») и кнопки «В работе · Сделано · Всё · Отчёт». Слово владельца 10.10 21:10:
  // «зачем это всё? Я понял, что это мне не надо… убери всю» — блок снят целиком: узла, стилей,
  // обработчиков, своего опроса и места под него в поле нет ни в одном окне (сироту прошлой страницы
  // снимает раздел 3). Здесь остались запрос сводки GET /digest (К6) и помощники, которыми живут кнопка
  // PMP (12п¹) и панель оркестрации (12п³): спрашивают сводку только они.
  const RICK_STATES = { "готово": "done", "идёт": "run", "ждёт": "wait", "упал": "fail", "впереди": "plan", "план": "plan" };
  const rickState = { okAt: -Infinity, triedAt: -Infinity, busy: false, seq: 0 };
  // Ширина подписи шрифтом font: холст страницы, нет его — по 0,56 кегля на знак.
  let rickPen = null;
  const rickMeasure = (text, font) => {
    try {
      rickPen ??= document.createElement("canvas").getContext?.("2d") ?? false;
      if (rickPen) { rickPen.font = font; return Number(rickPen.measureText(String(text)).width) || 0; }
    } catch { rickPen = false; }
    return String(text).length * (Number(/(\d+(?:\.\d+)?)px/.exec(font)?.[1]) || 9) * 0.56;
  };
  track(() => { rickState.seq += 1; });
  const rickUrl = () => `http://127.0.0.1:${HTML_CHROME_PORT}/digest`;
  // Запрос сводки: ответ и отказ слышит панель оркестрации (pmpPanelFed), по ней же — число у кнопки PMP.
  const rickFetch = () => {
    const at = now();
    if (rickState.busy && at - rickState.triedAt < RICK_CELLS_MS) return false;
    if (!(rickWanted() || pmpWanted()) || document.hidden || typeof fetch !== "function") return false;
    const seq = rickState.seq += 1;
    rickState.busy = true;
    rickState.triedAt = at;
    const done = () => { if (seq === rickState.seq) rickState.busy = false; };
    let sent = null;
    try { sent = fetch(rickUrl(), { mode: "cors", credentials: "omit", cache: "no-store" }); } catch { sent = null; }
    if (!sent || typeof sent.then !== "function") { done(); return false; }
    const failed = () => { done(); if (seq === rickState.seq && state.alive) { try { pmpPanelFed(null); } catch {} } };
    sent.then(reply => (reply?.ok ? reply.json() : null)).then(data => {
      if (seq !== rickState.seq || !state.alive) return;
      done();
      if (!data || typeof data !== "object") { try { pmpPanelFed(null); } catch {} return; }
      rickState.okAt = now();
      try { pmpPanelFed(data); } catch {}
    }, failed);
    return true;
  };
  const rickRect = node => {
    const rect = node?.isConnected ? node.getBoundingClientRect() : null;
    return rect && rect.width > 0 && rect.height > 0 ? rect : null;
  };
  const rickKindOf = flow => RICK_STATES[String(flow.state ?? "").trim()] ?? "";
  // Короткое имя проекта (WF183, слово Элвиса 09.10 03:35: «Не PimpMyClaude, а „Pimp“, VkusnoffKz —
  // „Vkus“. Сокращённо»): хвост « — ночь 09.10» и всё после тире отбрасывается; имя длиннее
  // RICK_NAME_SHORT знаков из нескольких частей (ВерблюжийРегистр, дефис, пробел, _) — первая часть, и та
  // длиннее — её первые 4 знака; одно слово («Dictator», «Trelvis») — как есть. Полное — в подсказке.
  // twin — у двух видимых проектов одно короткое имя («PimpMyClaude», «PimpViewer»): к нему первая буква
  // второй части («PimpM», «PimpV»).
  const RICK_NAME_SHORT = 6;
  const rickShortName = (text, twin = false) => {
    const whole = String(text ?? "").split(/\s+[—–-]\s+/u)[0].trim() || String(text ?? "").trim();
    if (whole.length <= RICK_NAME_SHORT) return whole;
    const parts = whole.split(/[\s_\-–—.]+|(?<=[\p{Ll}\d])(?=\p{Lu})/u).filter(Boolean);
    if (parts.length < 2) return whole;
    const head = parts[0].length > RICK_NAME_SHORT ? parts[0].slice(0, 4) : parts[0];
    return twin ? `${head}${parts[1][0]}` : head;
  };
  // «Отчёт» (#9163): ровно RICK_REPORT_TEXT — тем же путём, что «🚀 Workflow» (12а, insertIntoEditor):
  // в пустое поле — фраза, в непустое — с новой строки в конец; фокус в поле, курсор в конце; не
  // отправляет — Enter жмёт человек. Фраза уже в конце поля (двойной клик) — второй не будет.
  // С WF213 тем же путём — фразы команд панели оркестрации (12п³): text — что вставить.
  const rickReport = (text = RICK_REPORT_TEXT) => {
    const editor = state.editor?.isConnected ? state.editor : findEditor();
    if (!editor?.isConnected) return false;
    if (state.stage === STAGE_COLLAPSED) setStage(STAGE_NORMAL);
    if (rawText(editor).replace(/\s+$/u, "").endsWith(text)) {
      try { editor.focus(); } catch {}
      caretToEnd(editor);
      return true;
    }
    const draft = editorText(editor) !== "";
    const ok = insertIntoEditor(editor, draft ? `\n${text}` : text, draft ? "end" : false);
    if (ok) scheduleLayout();
    return ok;
  };
  const rickAdd = (parent, tag, text) => {
    const node = document.createElement(tag);
    if (text != null) node.textContent = text;
    parent.appendChild(node);
    return node;
  };
  // «О чём» из /digest срезано до 60 знаков с «…» (К6): показываем до последнего целого слова, без «…»
  // (слово Элвиса 08.10: многоточие не нужно); cut — текст неполный, карточка скажет, где полный.
  const rickAbout = text => {
    const line = progressLine(text);
    if (!/(?:…|\.\.\.)$/u.test(line)) return { text: line, cut: false };
    let body = line.replace(/(?:…|\.\.\.)$/u, "");
    const space = body.search(/\s\S*$/u);
    if (space > 0) body = body.slice(0, space);
    return { text: body.replace(/[\s,;:·—–-]+$/u, ""), cut: true };
  };
  // Нажатие по панели оркестрации — только наше: фокус поля не уходит, до слушателей Claude на document
  // (закрыть или открыть своё меню по нажатию) событие не всплывает (#9181).
  const rickKeep = event => { event.preventDefault(); event.stopPropagation(); };
  HATCH && Object.assign(HATCH, { rickShortName });

