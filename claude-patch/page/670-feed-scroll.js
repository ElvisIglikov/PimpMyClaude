  // ---- 13. Прокрутка ленты ------------------------------------------------
  // Команда «Прокрутить»: поставить ленту разговора на последнее сообщение.
  // В отличие от collapse/expand она адресована ВСЕМ окнам сразу, поэтому
  // фокуса не спрашивает (см. onCommand).
  //
  // Лента Claude Code — сама себе скролл-контейнер и помечена
  // epitaxy-virtual-transcript. В обычном чате claude.ai такой приметы нет, и
  // там работает запасной путь донора: ближайший прокручиваемый предок
  // последнего сообщения.
  const SCROLL_SELECTOR = '[data-testid="epitaxy-virtual-transcript"]';
  // Меньше этого запаса — контейнер не прокручивается вовсе, брать его незачем.
  const SCROLL_MIN_ROOM = 8;
  // Виртуальная лента дорисовывает хвост уже после первого скролла: кадр плюс
  // до пяти доборов по 120 мс покрывают и самое медленное досчитывание высоты.
  const SCROLL_STEPS = 5;
  const SCROLL_STEP_MS = 120;

  const scrollRoom = node => {
    const height = Number(node?.scrollHeight);
    const view = Number(node?.clientHeight);
    if (!Number.isFinite(height) || !Number.isFinite(view)) return 0;
    return height - view;
  };
  const scrollerFor = node => {
    let current = node?.parentElement ?? null;
    while (current && current !== document.body && current !== document.documentElement) {
      if (scrollRoom(current) > SCROLL_MIN_ROOM) {
        let overflow = "";
        try { overflow = getComputedStyle(current).overflowY ?? ""; } catch {}
        if (/(auto|scroll)/.test(overflow)) return current;
      }
      current = current.parentElement;
    }
    return null;
  };
  // Последнее сообщение. Ответ ассистента — самая надёжная примета; если его
  // ещё нет (первый вопрос в свежем чате), годится любой узел ленты.
  const lastMessageNode = () => {
    let answer = null;
    try { answer = lastAnswerNode(); } catch {}
    if (answer?.isConnected) return answer;
    try {
      const nodes = document.querySelectorAll(TRANSCRIPT_SELECTOR);
      return nodes[nodes.length - 1] ?? null;
    } catch { return null; }
  };
  const findScroller = () => {
    let virtual = null;
    try { virtual = document.querySelector(SCROLL_SELECTOR); } catch {}
    if (virtual?.isConnected && scrollRoom(virtual) > SCROLL_MIN_ROOM) return virtual;
    return scrollerFor(lastMessageNode()) ?? (virtual?.isConnected ? virtual : null);
  };
  const clearScrollWatch = () => {
    if (state.scrollRaf) { cancelAnimationFrame(state.scrollRaf); state.scrollRaf = 0; }
    if (state.scrollTimer) { clearTimeout(state.scrollTimer); state.scrollTimer = 0; }
    state.scrollSteps = 0;
    state.scroller = null;
  };
  track(clearScrollWatch);
  // Ниже scrollHeight браузер сам зажимает до предела прокрутки — целимся в
  // него, а не в разницу с clientHeight: та врёт, пока хвост ещё дорисовывают.
  const scrollDown = target => {
    const height = Number(target?.scrollHeight);
    if (!Number.isFinite(height)) return 0;
    try { target.scrollTop = height; } catch {}
    return height;
  };
  const scrollTail = () => {
    state.scrollTimer = 0;
    if (!state.alive) return;
    const target = state.scroller;
    if (!target?.isConnected) { clearScrollWatch(); return; }
    const height = Number(target.scrollHeight) || 0;
    // Лента перестала расти — хвост на месте, дёргать её дальше незачем.
    if (height <= state.scrollSeen) { clearScrollWatch(); return; }
    state.scrollSeen = height;
    state.scrollSteps -= 1;
    scrollDown(target);
    if (state.scrollSteps <= 0) { clearScrollWatch(); return; }
    state.scrollTimer = setTimeout(scrollTail, SCROLL_STEP_MS);
  };
  const runScroll = () => {
    // Прошлая прокрутка (двойной клик по пункту меню) свои доборы доигрывать не
    // должна: цель могла смениться, а два ряда таймеров спорили бы друг с другом.
    clearScrollWatch();
    const target = findScroller();
    if (!target?.isConnected) return false;
    state.scrollRuns += 1;
    // Своя прокрутка с доборами — не «лента уехала сама» (раздел 13а).
    feedHold.ownUntil = now() + (SCROLL_STEPS + 2) * SCROLL_STEP_MS;
    state.scroller = target;
    state.scrollSeen = scrollDown(target);
    state.scrollSteps = SCROLL_STEPS;
    state.scrollRaf = requestAnimationFrame(() => {
      state.scrollRaf = 0;
      if (!state.alive) return;
      const node = state.scroller;
      if (!node?.isConnected) { clearScrollWatch(); return; }
      // Кадр скроллит без условий: он и есть тот самый добор за подставленной
      // высотой последнего сообщения.
      state.scrollSeen = Math.max(state.scrollSeen, scrollDown(node));
      state.scrollTimer = setTimeout(scrollTail, SCROLL_STEP_MS);
    });
    return true;
  };

