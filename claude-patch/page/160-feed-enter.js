  // ---- 3б. Плавное появление нового в ленте (#9165, WF165) ------------------
  // Слово Элвиса 09.10 00:05: новый ответ появляется слишком резко, рывком, и это
  // раздражает. Новая строка ленты (transcript-row с номером data-index больше
  // всех виденных в этом чате) проявляется: прозрачность 0→1 и подъём на FEED_ENTER_SHIFT за
  // FEED_ENTER_MS. Новый блок внутри идущего ответа (абзац, список, строка инструмента,
  // дописанный В КОНЕЦ без замены соседей) — только прозрачностью, без сдвига: текст не прыгает.
  // Не играет: при прокрутке (лента виртуальная — старые строки монтируются заново с меньшим
  // номером или далеко от хвоста), первые FEED_ENTER_QUIET мс после входа в чат и инжекта
  // (лента грузится целиком), при «Уменьшить движение». Узлы React не меняются — Web Animations
  // на самом узле (`translate` складывается с чужим transform); DOM-атрибутов нет.
  const FEED_ENTER_ROW = '[data-testid="transcript-row"]';
  const FEED_ENTER_MS = 220;
  const FEED_ENTER_BLOCK_MS = 180;
  const FEED_ENTER_SHIFT = 5;
  const FEED_ENTER_QUIET = 1200;
  const FEED_ENTER_TAIL = 2;
  // Только блоки: строчные куски (span) идущего текста не мигают по одному.
  const FEED_ENTER_BLOCKS = /^(?:P|UL|OL|PRE|BLOCKQUOTE|TABLE|H[1-6]|DIV)$/i;
  const FEED_ENTER_STREAM = '[data-cds="AssistantMessage"][data-is-streaming="true"]';
  const feedEnterState = { path: null, top: -1, quietUntil: 0, rows: 0, blocks: 0, still: 0 };
  const feedEnterIndex = row => {
    const raw = row?.getAttribute?.("data-index");
    const value = raw == null || raw === "" ? NaN : Number(raw);
    return Number.isInteger(value) && value >= 0 ? value : null;
  };
  const feedEnterTop = () => {
    let top = -1;
    for (const row of document.querySelectorAll(FEED_ENTER_ROW)) {
      const index = feedEnterIndex(row);
      if (index != null && index > top) top = index;
    }
    return top;
  };
  const feedEnterReset = () => {
    feedEnterState.path = location.pathname;
    feedEnterState.top = feedEnterTop();
    feedEnterState.quietUntil = now() + FEED_ENTER_QUIET;
  };
  const feedEnterPlay = (node, frames, duration) => {
    let still = false;
    try { still = matchMedia("(prefers-reduced-motion: reduce)").matches; } catch {}
    if (still || typeof node?.animate !== "function") { feedEnterState.still += 1; return false; }
    try { node.animate(frames, { duration, easing: "cubic-bezier(0.2, 0.7, 0.3, 1)" }); return true; } catch { return false; }
  };
  const feedEnterRow = row => {
    const index = feedEnterIndex(row);
    if (index == null || index <= feedEnterState.top) return;
    feedEnterState.top = index;
    if (now() < feedEnterState.quietUntil) return;
    // Хвост ленты: Claude метит строку расстоянием до конца; далеко от хвоста — это прокрутка.
    const tail = Number(row.getAttribute?.("data-perf-row-from-tail"));
    if (Number.isFinite(tail) && tail > FEED_ENTER_TAIL) return;
    if (feedEnterPlay(row, [{ opacity: 0, translate: `0 ${FEED_ENTER_SHIFT}px` }, { opacity: 1, translate: "0 0" }], FEED_ENTER_MS)) feedEnterState.rows += 1;
  };
  const feedEnterOnMutation = records => {
    if (feedEnterState.path !== location.pathname) { feedEnterReset(); return; }
    for (const record of records) {
      if (record.type !== "childList") continue;
      for (const node of record.addedNodes ?? []) {
        if (node?.nodeType !== 1) continue;
        if (node.matches?.(FEED_ENTER_ROW)) { feedEnterRow(node); continue; }
        const rows = node.querySelectorAll?.(FEED_ENTER_ROW) ?? [];
        if (rows.length) { for (const row of rows) feedEnterRow(row); continue; }
        // Блок идущего ответа: дописан в конец, соседей не заменял.
        if (now() < feedEnterState.quietUntil || (record.removedNodes?.length ?? 0) > 0) continue;
        if (!FEED_ENTER_BLOCKS.test(node.tagName ?? "")) continue;
        if (node.parentElement?.lastElementChild !== node || !node.closest?.(FEED_ENTER_STREAM)) continue;
        if (feedEnterPlay(node, [{ opacity: 0 }, { opacity: 1 }], FEED_ENTER_BLOCK_MS)) feedEnterState.blocks += 1;
      }
    }
  };
  feedEnterReset();
  HATCH && Object.assign(HATCH, { feedEnterOnMutation, feedEnterState, FEED_ENTER_MS });

