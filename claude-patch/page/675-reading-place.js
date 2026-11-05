  // ---- 13а. Место чтения (#9319, #6590) -------------------------------------
  // Слово Элвиса (#9319): «читал что-то, новое сообщение пришло, и у меня сбилось,
  // и мне приходится опять искать». Лента уехала к самому низу САМА — Claude
  // догоняет новое, наши «стояла у низа — к низу» (раздел 10, 2б, 12ф), — а Элвис
  // читает (attnReading, раздел 12м): возвращаем ей прежний верх. Сама — это не
  // через FEED_USER_MS после касания окна (колесо, клавиша, нажатие — его прокрутка,
  // и всё, что тянется за ней кадр за кадром, — плавный ход стрелки Claude «вниз»),
  // не своя прокрутка (runScroll, переход «Прочитано», обход 12е, тяга поля). Не
  // читает — лента едет за новым, как было. Сменился адрес (другой чат, обход 12е) —
  // прежний верх не в счёт (а «читает» — про прежний чат, attnReading).
  // Держим только сдвиг ВНИЗ до самого низа: прочие (якорь прокрутки Chromium,
  // виртуальная лента досчитала строки выше) место чтения правят, а не сбивают.
  // Claude спорит — возвращает низ снова и снова — после FEED_FIGHT_MAX раз за
  // FEED_FIGHT_MS уступаем до следующего жеста: дёрганье хуже одного сдвига.
  const FEED_USER_MS = 800;
  const FEED_CHAIN_MS = 200;
  const FEED_FIGHT_MAX = 3;
  const FEED_FIGHT_MS = 2000;
  const feedHold = {
    href: location.href, node: null, top: 0, ownUntil: -Infinity, userUntil: -Infinity, quit: -Infinity, recent: [], holds: 0, yields: 0,
  };
  track(() => { feedHold.node = null; feedHold.recent = []; });
  const feedHoldOnScroll = event => {
    const node = event?.target;
    if (!node || node.nodeType !== 1) return;
    let feed = null;
    try { feed = findScroller(); } catch { feed = null; }
    if (node !== feed) return;
    if (feedHold.href !== location.href) { feedHold.href = location.href; feedHold.node = null; }
    const t = now();
    const top = Number(node.scrollTop) || 0;
    const was = feedHold.node === node ? feedHold.top : null;
    feedHold.node = node;
    feedHold.top = top;
    if (t - attnState.inputAt < FEED_USER_MS || t < feedHold.userUntil) { feedHold.userUntil = t + FEED_CHAIN_MS; return; }
    if (was == null || top - was <= TAIL_SLACK || !tailAtBottom(node)) return;
    if (t < feedHold.ownUntil || state.dragging || roamState.phase !== "idle" || readState.seek) return;
    if (feedHold.quit > attnState.readAt || !attnReading(t)) return;
    feedHold.recent = feedHold.recent.filter(at => t - at < FEED_FIGHT_MS);
    if (feedHold.recent.length >= FEED_FIGHT_MAX) { feedHold.quit = t; feedHold.yields += 1; return; }
    feedHold.recent.push(t);
    feedHold.holds += 1;
    try { node.scrollTop = was; } catch {}
    feedHold.top = Number(node.scrollTop) || 0;
  };

