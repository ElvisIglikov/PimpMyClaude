  // ---- 12х³. Ответ-точка (слово Элвиса 11.10 05:40) ----
  // Слово Элвиса по снимку ленты: «А видишь вот эти пустые точки? Можешь тоже их убрать… чтобы их не
  // было? Ничего же не стёрлось?» Служебный ответ чата, весь видимый текст которого — одна точка
  // («·» или «.»), в ленте не показывается вместе со своими отступами: строка ленты на месте, высота 0
  // и прозрачность (как строка серии 12х¹) — ничего не удалено, innerText ленты тот же. Пустые строки
  // прямо над ней (спрятанные разделом 3а инструменты того же шага: от них оставался отступ строки)
  // уходят с ней. Любой другой текст, картинка, видимая группа инструментов или карточка — строка
  // остаётся как есть. Раскладку не читает: спрятанное разделом 3а узнаётся по его метке.
  // Починка 11.10 06:20 («у меня перестали отображаться эти…», снимок: под последним ответом пусто):
  // панель кнопок ответа Claude держит в строке ПОСЛЕДНЕГО блока хода — когда им была точка, панель
  // уходила вместе с ней. Строка с панелью не сворачивается: не видно только её текста.
  const DOT_ACTIONS = '[data-cds="MessageActions"]';
  const DOT_MEDIA = "img,video,canvas,svg,iframe,audio";
  const dotState = { marked: new Set() };
  // Что на виду в строке ответа: "dot" — одна точка, "empty" — ничего, null — что-то ещё.
  const dotKindOf = row => {
    if (row.getAttribute("data-perf-row") !== "assistant") return null;
    const host = workHostOf(row);
    if (!host) return null;
    const tools = document.documentElement.hasAttribute(HIDE_TOOLS_ATTRIBUTE);
    let dot = false;
    try {
      for (const block of host.children) {
        if (tools && block.hasAttribute(HIDE_TOOLS_MARK) && !block.hasAttribute(WORK_ATTRIBUTE)) continue;
        if (block.hasAttribute(WORK_LINE_ATTRIBUTE) || block.matches(DOT_MEDIA) || block.querySelector(DOT_MEDIA)) return null;
        const text = sayNorm(block.textContent);
        if (!text) continue;
        if (dot || (text !== "·" && text !== ".")) return null;
        const prose = block.matches(WORK_PROSE) ? block : block.querySelector(WORK_PROSE);
        if (!prose || sayNorm(prose.textContent) !== text) return null;
        dot = true;
      }
    } catch { return null; }
    return dot ? "dot" : "empty";
  };
  const dotPaint = (rows = readRowsNow()) => {
    const marks = new Map();
    rows.forEach((row, index) => {
      if (dotKindOf(row) !== "dot") return;
      let actions = null;
      try { actions = row.querySelector(DOT_ACTIONS); } catch {}
      marks.set(row, actions ? "tail" : "row");
      if (actions) marks.set(workHostOf(row), "text");
      for (let above = index - 1; above >= 0 && !marks.has(rows[above]) && dotKindOf(rows[above]) === "empty"; above -= 1) marks.set(rows[above], "gap");
    });
    let changed = marks.size !== dotState.marked.size;
    if (!changed) for (const [node, value] of marks) if (node.getAttribute(DOT_ATTRIBUTE) !== value) { changed = true; break; }
    if (!changed) return;
    // Лента стояла у низа — у низа и остаётся (строка вернулась на вид: её текст дописался).
    const feed = readFeed();
    let pinned = false;
    try { pinned = Boolean(feed) && feed.scrollHeight - feed.scrollTop - feed.clientHeight < 2; } catch {}
    for (const node of dotState.marked) if (!marks.has(node)) foldSet(node, DOT_ATTRIBUTE, null);
    for (const [node, value] of marks) foldSet(node, DOT_ATTRIBUTE, value);
    dotState.marked = new Set(marks.keys());
    if (pinned) { try { feed.scrollTop = feed.scrollHeight; } catch {} }
  };
  const dotSweep = () => {
    try { for (const node of document.querySelectorAll(`[${DOT_ATTRIBUTE}]`)) node.removeAttribute(DOT_ATTRIBUTE); } catch {}
  };
  dotSweep();
  track(() => { dotState.marked.clear(); dotSweep(); });
  HATCH && Object.assign(HATCH, { dotPaint });

