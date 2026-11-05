  // ---- 12о. Красное время последнего сообщения (#7750, WF94) ---------------
  // Слово Элвиса 26.09 ~02:05: «после 50 минут мигать красным… и время
  // „19 min ago“ тоже красным». Полоски окна больше не красятся (#7848, 26.09
  // ~06:10: «убери у них анимацию… дискотека не надо… оставь их серыми») — их
  // режимы need/warm/cold/work сняты; осталось красное время: строка
  // последнего сообщения получает STALE_ATTRIBUTE — warm после CACHE_WARN_MS
  // (50 мин, тёплый кэш живёт час — пора писать), cold после CACHE_TTL_MS
  // (60 мин, кэш уже холодный), — пока чат не работает.
  // Время последнего сообщения — наибольший entry.timestamp, что видел раздел
  // 14а в этом чате (лента виртуальная: пролистал вверх — старые строки не
  // сбивают счёт); его же берёт запасным временем кеша отсчёт отправки
  // (sendDelayCold, sigState.lastAt). Таймеров нет — шаг тиком сердца.
  const CACHE_WARN_MS = 50 * 60000;
  const CACHE_TTL_MS = 60 * 60000;
  const sigState = { chat: undefined, lastAt: 0, row: null, marked: null };
  // Раздел 14а сообщает время строк, что сейчас в ленте; смена чата — счёт заново.
  const signalChat = () => {
    let id = null;
    try { id = myChatId(); } catch { id = null; }
    if (id === sigState.chat) return;
    sigState.chat = id;
    sigState.lastAt = 0;
    sigState.row = null;
  };
  const signalNoteLast = (iso, row) => {
    const at = Date.parse(String(iso ?? ""));
    if (!Number.isFinite(at)) return;
    signalChat();
    if (at > sigState.lastAt) { sigState.lastAt = at; sigState.row = row; }
    else if (at === sigState.lastAt) sigState.row = row;
  };
  const signalMark = row => {
    const prev = sigState.marked;
    if (prev && prev !== row) { try { prev.removeAttribute(STALE_ATTRIBUTE); } catch {} }
    sigState.marked = row ?? null;
  };
  const signalTick = (t, wall = Date.now()) => {
    if (!state.alive) return;
    signalChat();
    let working = waitState.kind === "running";
    if (!working) { try { working = document.querySelector(WORKING_SELECTOR) != null; } catch {} }
    const ago = sigState.lastAt > 0 ? wall - sigState.lastAt : null;
    // Время краснеет по кэшу и при висящем вопросе: вопрос, висящий 55 минут, — время под ним красное.
    const stale = !working && Number.isFinite(ago) && ago >= CACHE_WARN_MS ? (ago >= CACHE_TTL_MS ? "cold" : "warm") : "";
    const row = stale && sigState.row?.isConnected ? sigState.row : null;
    signalMark(row);
    if (row && row.getAttribute(STALE_ATTRIBUTE) !== stale) row.setAttribute(STALE_ATTRIBUTE, stale);
  };
  try { for (const node of document.querySelectorAll(`[${STALE_ATTRIBUTE}]`)) node.removeAttribute(STALE_ATTRIBUTE); } catch {}
  track(() => signalMark(null));
  // Красное время (#7750, раздел 12о): минут с последнего сообщения чата и
  // красное ли время у последнего сообщения (warm | cold | null).
  statusPart("signal", () => ({
    ago: sigState.lastAt > 0 ? Math.floor((Date.now() - sigState.lastAt) / 60000) : null,
    stale: sigState.marked?.getAttribute?.(STALE_ATTRIBUTE) ?? null,
  }));
  HATCH && Object.assign(HATCH, { signalTick, sigState, CACHE_WARN_MS, CACHE_TTL_MS });

