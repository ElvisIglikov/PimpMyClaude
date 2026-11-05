  // ---- 14а. Время под каждым сообщением (#7747, WF94) ----------------------
  // Claude 2.9939.2 рисует строку действий с <time> только у последнего ответа,
  // у реплик человека и под мышью (замер 26.09); Элвис: «раньше ты писал
  // время… постоянно выводил… надо показывать». Под каждой строкой сообщения
  // Пимп держит свой тихий узел, всегда видный. Время — из данных сообщения:
  // пропс entry.timestamp у React-волокна над строкой (проба 26.09: у ответа —
  // компонент прямо над ней, у реплики человека — несколькими уровнями выше);
  // волокна нет — datetime родного <time> в строке. Строки одного хода Claude
  // делят entry.id, а время у каждого текста своё (проба 26.09: ход в 12
  // строк — шесть разных времён, строки инструментов носят время последнего
  // обновления); строки с одинаковыми id и временем — одно сообщение, время
  // только под последней по itemIdx. Текст — в атрибуте, рисует правило раздела 4; раз в минуту
  // меняется только атрибут, лента не перерисовывается.
  const STAMP_FIBER_DEPTH = 10;
  const STAMP_TICK_MS = 60000;
  const stampPad = value => String(value).padStart(2, "0");
  // «just now», «38 min ago», «3 h ago» (как раздел 14 сокращает родное),
  // старше суток — «25.09 23:10» по местному времени.
  const stampText = (iso, at = Date.now()) => {
    const time = Date.parse(String(iso ?? ""));
    if (!Number.isFinite(time)) return null;
    const ago = at - time;
    if (ago < 60000) return "just now";
    if (ago < 3600000) return `${Math.floor(ago / 60000)} min ago`;
    if (ago < 86400000) return `${Math.floor(ago / 3600000)} h ago`;
    const date = new Date(time);
    return `${stampPad(date.getDate())}.${stampPad(date.getMonth() + 1)} ${stampPad(date.getHours())}:${stampPad(date.getMinutes())}`;
  };
  const stampEntry = row => {
    let fiber = chatFiberOf(row);
    for (let depth = 0; fiber && depth < STAMP_FIBER_DEPTH; depth += 1, fiber = fiber.return) {
      const props = fiber.memoizedProps;
      const entry = props?.entry;
      if (entry && typeof entry.timestamp === "string") {
        return { key: `${entry.id ?? ""}|${entry.timestamp}`, at: entry.timestamp, order: Number(props.itemIdx) || 0 };
      }
    }
    const at = row.querySelector?.("time[datetime]")?.getAttribute("datetime");
    return at ? { key: row, at, order: 0 } : null;
  };
  const stampTimes = () => {
    if (!state.alive) return;
    let rows = [];
    try { rows = [...document.querySelectorAll(MESSAGE_ROW_SELECTOR)]; } catch {}
    const best = new Map();
    for (const row of rows) {
      // Пузырь внутри .epitaxy-user-turn носит тот же класс — он часть внешней строки.
      if (row.parentElement?.closest?.(MESSAGE_ROW_SELECTOR)) continue;
      const found = stampEntry(row);
      if (!found) continue;
      const prev = best.get(found.key);
      if (!prev || found.order >= prev.order) best.set(found.key, { row, at: found.at, order: found.order });
    }
    const at = Date.now();
    const keep = new Set();
    for (const { row, at: iso } of best.values()) {
      // Время последнего сообщения — разделу 12о (кэш стынет — время краснеет).
      signalNoteLast(iso, row);
      const text = stampText(iso, at);
      if (!text) continue;
      let node = [...(row.children ?? [])].find(kid => kid.hasAttribute?.(STAMP_ATTRIBUTE)) ?? null;
      if (!node) {
        node = document.createElement("div");
        // Вид родного времени Claude: те же классы, что у его <time>.
        node.className = "text-body text-muted tabular-nums";
        node.setAttribute("aria-hidden", "true");
      }
      if (node.getAttribute(STAMP_ATTRIBUTE) !== text) node.setAttribute(STAMP_ATTRIBUTE, text);
      // Всегда последним: React дописывает новые узлы строки в конец.
      if (row.lastElementChild !== node) row.appendChild(node);
      keep.add(node);
    }
    // Лишние (строка перестала быть последней у записи, сироты прошлой установки) — долой.
    try {
      for (const node of document.querySelectorAll(`[${STAMP_ATTRIBUTE}]`)) if (!keep.has(node)) node.remove();
    } catch {}
  };
  // Время реплики Элвиса над строкой ленты row (#10764): ближайшая выше строка человека (не дальше STAMP_BACK
  // строк) и её строка времени — родная «✓✓ 8 min ago · копировать · …» (<time datetime>), нет её — свой узел
  // времени; нет и его — null. Слово Элвиса 23.10 19:30 (скрин №2): при переходе сверху видна эта строка, под
  // ней ответ — она встаёт на STAMP_TOP от верха ленты.
  const STAMP_BACK = 40;
  const STAMP_TOP = 12;
  // Лента под кнопками окна (светофор, «Show sidebar», PMP — до CORNER_FADE_DROP от верха, там же угловой фейд,
  // раздел 6): на 12 px время уходило под светофор (снимок окна Рика 23.10 22:17). Тогда — ниже кнопок на STAMP_CLEAR.
  // Отступ от верха ленты (view — её рамка).
  const STAMP_CLEAR = 6;
  const stampTop = (feed, view) => {
    let under = false;
    try { under = Boolean(feed?.hasAttribute?.(CORNER_FADE_ATTRIBUTE)); } catch {}
    return under ? Math.max(STAMP_TOP, CORNER_FADE_DROP + STAMP_CLEAR - (Number(view?.top) || 0)) : STAMP_TOP;
  };
  const stampAbove = row => {
    let prev = row?.previousElementSibling ?? null;
    for (let step = 0; prev && step < STAMP_BACK; step += 1, prev = prev.previousElementSibling) {
      let human = false;
      try { human = prev.getAttribute?.("data-perf-row") === "human" || Boolean(prev.querySelector?.(".epitaxy-user-turn")); } catch {}
      if (human) { try { return prev.querySelector("time[datetime]") ?? prev.querySelector(`[${STAMP_ATTRIBUTE}]`) ?? null; } catch { return null; } }
    }
    return null;
  };
  // На сколько выше верха строки row (её рамка box) стоит время реплики над ней; дальше половины экрана (height)
  // или нет его — 0: тогда на место встаёт сама строка.
  const stampLead = (row, box, height) => {
    const mark = stampAbove(row);
    if (!mark) return 0;
    let gap = 0;
    try { gap = Math.round(Number(box.top) - Number(mark.getBoundingClientRect().top)); } catch { return 0; }
    return Number.isFinite(gap) && gap > 0 && gap < height / 2 ? gap : 0;
  };
  const stampTimer = setInterval(() => {
    if (state.alive && state.watching) { try { stampTimes(); } catch {} }
  }, STAMP_TICK_MS);
  track(() => {
    clearInterval(stampTimer);
    try { for (const node of document.querySelectorAll(`[${STAMP_ATTRIBUTE}]`)) node.remove(); } catch {}
  });
  HATCH && Object.assign(HATCH, { stampText, stampTimes, stampAbove, stampLead });

