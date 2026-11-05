  // ---- 14. Короткое время под сообщениями ---------------------------------
  // Под каждым сообщением Claude пишет «3 minutes ago» — по слову Элвиса, это
  // визуальный шум. Сокращаем в самом тексте: minutes → min, seconds → sec,
  // hours → h, days → d. Всё остальное («Just now», числа, «ago») не трогаем.
  const TIME_SELECTOR = '[aria-label="Message actions"] time,[aria-label="Действия с сообщением"] time';
  const TIME_LONG = /\b(?:seconds?|minutes?|hours?|days?)\b/;
  // Часики тикают: Claude сам перерисовывает текст, и правку приходится
  // повторять. Проход — обход всех строк действий, поэтому не чаще раза в
  // 250 мс, как и раскладка.
  const TIME_MIN_GAP = 250;
  const shortenTime = text => text
    .replace(/\bminutes?\b/g, "min")
    .replace(/\bseconds?\b/g, "sec")
    .replace(/\bhours?\b/g, "h")
    .replace(/\bdays?\b/g, "d");
  // Правим текстовые узлы, а не textContent целиком: внутри <time> у Claude
  // бывает своя разметка, и перезапись текстом снесла бы её.
  const shortenTextNodes = node => {
    if (node == null) return;
    if (node.nodeType === 3) {
      const text = node.nodeValue ?? "";
      // Уже коротко — молчим. Правка порождает мутацию, мутация зовёт нас
      // обратно, и без этой проверки круг наблюдатель ↔ правка не разорвать.
      if (!TIME_LONG.test(text)) return;
      node.nodeValue = shortenTime(text);
      return;
    }
    const kids = node.childNodes;
    if (!kids) return;
    for (let index = 0; index < kids.length; index += 1) shortenTextNodes(kids[index]);
  };
  const timeObserver = new MutationObserver(() => scheduleShortTime());
  const stopTimeWatch = () => {
    try { timeObserver.disconnect(); } catch {}
    state.timeTarget = null;
  };
  track(stopTimeWatch);
  // Лента приезжает позже инжекта, поэтому до неё смотрим за body, а как
  // появится — переезжаем на неё: мимо body идут ещё и поле ввода с боковой
  // панелью, а строки действий живут только в ленте.
  const watchTime = () => {
    if (!state.alive || !state.watching) return false;
    let target = null;
    try { target = document.querySelector(SCROLL_SELECTOR); } catch {}
    if (!target?.isConnected) target = document.body ?? null;
    if (!target || target === state.timeTarget) return false;
    try { timeObserver.disconnect(); } catch {}
    state.timeTarget = target;
    try {
      timeObserver.observe(target, { characterData: true, childList: true, subtree: true });
    } catch { state.timeTarget = null; }
    return state.timeTarget != null;
  };
  const runShortTime = () => {
    state.timeTimer = 0;
    if (!state.alive || !state.watching) return;
    state.timeAt = now();
    state.timeRuns += 1;
    try {
      for (const node of document.querySelectorAll(TIME_SELECTOR)) shortenTextNodes(node);
    } catch {}
    try { stampTimes(); } catch {}
    watchTime();
    // Тик времени сообщений заодно двигает полосу прогресса (раздел 2б): он
    // приходит от наблюдателя за лентой, то есть ровно тогда, когда в разговоре
    // что-то изменилось. Свой троттлинг у полосы отдельный, в секунду.
    try { progressSchedule(); } catch {}
  };
  const cancelShortTime = () => {
    if (!state.timeTimer) return;
    clearTimeout(state.timeTimer);
    state.timeTimer = 0;
  };
  track(cancelShortTime);
  const scheduleShortTime = () => {
    if (state.timeTimer || !state.alive || !state.watching) return;
    const wait = Math.max(0, TIME_MIN_GAP - (now() - state.timeAt));
    if (wait === 0) { runShortTime(); return; }
    state.timeTimer = setTimeout(runShortTime, wait);
  };

