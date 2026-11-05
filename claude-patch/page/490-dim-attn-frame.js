  // ---- 12и¹. Притемнение попапов и рамка «ждут твоего слова» (#8256, #8282, WF113)
  // Слово Элвиса #8256: «все окна Клауда, кроме твоего, главного, притемнить…
  // Не хочу вот эту суету видеть»; #8282 (через Рика 30.09 ~19:10): чат, где
  // ждут слова Элвиса, ярко мигает — видно, в каком окне что сказать.
  //
  // Вуаль #myclaude-dim — только в попапе (chatKind() === "popout"), только при
  // включённом притемнении, не в фокусе и не при горящей рамке; главное окно —
  // никогда. Выбор {on, level} — localStorage["myclaude-dim-v1"] (команда `dim`
  // от приложения, остальные окна — storage-событием). Плавно 200 мс, мимо
  // мыши (pointer-events: none).
  //
  // Рамка #myclaude-attn-frame — янтарь по краю окна, пульс 1,2 с (reduced-motion —
  // ровная), поверх вуали. Признак — «ждёт тебя» раздела 12и (waitState.why)
  // без его гашения касанием, и не всякий: awaiting (Allow, вопрос Claude) или
  // кончен ход (ready / done) И строка состояния ответа говорит «жду» / «упал»
  // (раздел 2б) — просто законченный ход рамки не даёт (слово Элвиса 29.09,
  // #8112: «все чаты мигают… вырубай»). Причина держится, пока чат не
  // поработает снова (running) или окно не сменит чат. Загорается, продержавшись
  // WAIT_HOLD_MS (Авто-Allow не мигает). Гаснет от ввода в поле или от фокуса
  // окна дольше ATTN_FRAME_FOCUS_MS (окна поднимает и само приложение — миг
  // фокуса не в счёт) и не возвращается до нового ожидания. Шаг — тиком сердца.
  //
  // `keep` (гейт WF111, #8284: главное окно Claude маленькое в углу, Рик —
  // попапом впереди) — id чатов окон главного проекта (`mainProject` в
  // claude.json, шлёт приложение). Непуст — вуаль на ВСЕХ окнах, и главном,
  // кроме окон, чей myChatId() в keep; пуст — как было, только попапы. Рамки на
  // окнах keep нет никогда: Рик и так перед глазами.
  const DIM_ID = "myclaude-dim";
  const DIM_KEY = "myclaude-dim-v1";
  const DIM_Z = "2147483646";
  const ATTN_FRAME_ID = "myclaude-attn-frame";
  const ATTN_FRAME_Z = "2147483647";
  const ATTN_FRAME_AMBER = "#f59e0b";
  const ATTN_FRAME_MS = 1200;
  const ATTN_FRAME_FOCUS_MS = 3000;
  const DIM_KEEP_MAX = 32;
  // Негодное поле — умолчание (выкл, 0,5, keep пуст); keep — массив строк local_…,
  // не длиннее 32, иначе пуст целиком.
  const dimKeepOk = keep => Array.isArray(keep) && keep.length <= DIM_KEEP_MAX &&
    keep.every(id => typeof id === "string" && /^local_[\w-]{1,200}$/.test(id)) ? [...keep] : [];
  const dimOk = raw => ({
    on: raw?.on === true,
    level: typeof raw?.level === "number" && Number.isFinite(raw.level) && raw.level >= 0.2 && raw.level <= 0.8 ? raw.level : 0.5,
    keep: dimKeepOk(raw?.keep),
  });
  const readDim = (fallback = null) => {
    try {
      const raw = localStorage.getItem(DIM_KEY);
      if (raw != null) return dimOk(JSON.parse(raw));
    } catch {}
    return { ...dimOk(fallback), on: false };
  };
  let dimSetting = { ...readDim(previousDim), on: false };
  previousDim = null;
  try { localStorage.removeItem(DIM_KEY); } catch {}
  const dimNode = document.createElement("div");
  dimNode.id = DIM_ID;
  const attnFrameNode = document.createElement("div");
  attnFrameNode.id = ATTN_FRAME_ID;
  for (const orphan of document.querySelectorAll(`#${DIM_ID}, #${ATTN_FRAME_ID}`)) orphan.remove();
  for (const [node, z, extra] of [
    [dimNode, DIM_Z, { opacity: "0", transition: "opacity 200ms ease" }],
    [attnFrameNode, ATTN_FRAME_Z, {
      "border-radius": `${WINDOW_FRAME_RADIUS}px`,
      "box-shadow": `inset 0 0 0 4px ${ATTN_FRAME_AMBER}, inset 0 0 32px rgba(245,158,11,.75)`,
    }],
  ]) {
    node.setAttribute("aria-hidden", "true");
    for (const [name, value] of Object.entries({ position: "fixed", inset: "0px", display: "none", "pointer-events": "none", "z-index": z, ...extra })) {
      node.style.setProperty(name, value);
    }
    (document.body ?? document.documentElement).appendChild(node);
    track(() => node.remove());
  }
  const attnFrame = { reason: "", chat: undefined, holdAt: 0, focusAt: 0, dismissed: false, on: false, since: null, anim: null, want: false };
  // Ждут ли слова Элвиса: Allow или вопрос — всегда; кончен ход — только когда
  // строка состояния ответа говорит «жду» или «упал» (PROGRESS_TAIL_WORDS, 2б).
  const attnWanted = why => why === "awaiting" ||
    ((why === "ready" || why === "done") && ["wait", "fail"].includes(progressState.info?.state ?? progressTailWord));
  const attnFrameStopAnim = () => {
    try { attnFrame.anim?.cancel?.(); } catch {}
    attnFrame.anim = null;
  };
  track(attnFrameStopAnim);
  const dimFocused = () => { try { return document.hasFocus(); } catch { return false; } };
  // Окно главного проекта (keep): ни вуали, ни рамки.
  const dimKept = () => {
    if (dimSetting.keep.length === 0) return false;
    let id = null;
    try { id = myChatId(); } catch { id = null; }
    return id != null && dimSetting.keep.includes(id);
  };
  // Кого вообще темнить: keep непуст — всех, кроме keep; пуст — только попапы.
  const dimScope = () => dimSetting.keep.length > 0 ? !dimKept() : chatKind() === "popout";
  const dimWanted = () => themable && dimSetting.on && !dimFocused() && !attnFrame.on && dimScope();
  // Пишем только разницу: тик сердца зовёт каждую секунду, стиль зря не трогаем.
  const dimSet = (name, value) => {
    if (dimNode.style.getPropertyValue(name) !== value) dimNode.style.setProperty(name, value);
  };
  const dimPaint = () => {
    const want = dimWanted();
    dimSet("background", `rgba(0,0,0,${dimSetting.level})`);
    if (want) {
      if (dimNode.style.getPropertyValue("display") !== "block") {
        dimNode.style.setProperty("display", "block");
        void dimNode.offsetWidth; // из display:none переход не идёт без перерасчёта
      }
      dimSet("opacity", "1");
    } else {
      dimSet("opacity", "0");
      if (!dimSetting.on || !dimScope()) dimSet("display", "none");
    }
  };
  // Вуаль угасла совсем — узел прочь из раскладки до следующего раза.
  const onDimFaded = () => {
    if (!dimWanted() && dimNode.style.getPropertyValue("opacity") === "0") dimNode.style.setProperty("display", "none");
  };
  const attnFramePaint = on => {
    if (on === attnFrame.on) return;
    attnFrame.on = on;
    attnFrameStopAnim();
    if (!on) {
      attnFrame.since = null;
      attnFrameNode.style.setProperty("display", "none");
    } else {
      attnFrame.since = Date.now();
      attnFrameNode.style.setProperty("opacity", "1");
      attnFrameNode.style.setProperty("display", "block");
      let still = false;
      try { still = matchMedia("(prefers-reduced-motion: reduce)").matches; } catch {}
      if (!still) {
        try {
          attnFrame.anim = attnFrameNode.animate([{ opacity: 0.3 }, { opacity: 1 }], {
            duration: ATTN_FRAME_MS / 2, iterations: Infinity, direction: "alternate", easing: "ease-in-out",
          });
        } catch { attnFrame.anim = null; }
      }
    }
    dimPaint();
  };
  const attnFrameTick = t => {
    if (!themable) return;
    const a = attnFrame;
    // Окно ушло в чужой чат за Allow (обход 12е) или сменило чат — ожидание не наше.
    const roaming = roamState.phase !== "idle";
    if (roaming || waitState.id !== a.chat) {
      a.chat = roaming ? a.chat : waitState.id;
      Object.assign(a, { reason: "", holdAt: 0, dismissed: false });
    }
    if (!roaming) {
      if (waitState.why) a.reason = waitState.why;
      else if (waitState.kind !== "idle") a.reason = "";
    }
    if (!a.reason) { Object.assign(a, { holdAt: 0, dismissed: false, want: false }); attnFramePaint(false); dimPaint(); return; }
    // Ход кончен без «жду» — не ждут: рамки нет, счёт выдержки с нуля.
    if (!attnWanted(a.reason)) { Object.assign(a, { holdAt: 0, want: false }); attnFramePaint(false); dimPaint(); return; }
    if (!a.holdAt) a.holdAt = t;
    // Для приложения (status().attention.want): ждут, и выдержка прошла — Авто-Allow не в счёт.
    a.want = t - a.holdAt >= WAIT_HOLD_MS;
    if (dimFocused()) { if (!a.focusAt) a.focusAt = t; } else a.focusAt = 0;
    if (a.focusAt && t - a.focusAt >= ATTN_FRAME_FOCUS_MS) a.dismissed = true;
    attnFramePaint(a.want && !a.dismissed && !dimKept());
    dimPaint();
  };
  // Ввод в поле — Элвис уже отвечает: рамка гаснет до нового ожидания.
  const onAttnFrameKey = event => {
    if (event?.isTrusted === false || !attnFrame.reason) return;
    try { if (!event.target?.closest?.('[contenteditable="true"],textarea,input')) return; } catch { return; }
    attnFrame.dismissed = true;
    attnFramePaint(false);
  };
  // Фокус пришёл или ушёл: вуаль — сразу; счёт 3 с начинает тик сердца.
  const onDimFocus = () => {
    if (!dimFocused()) attnFrame.focusAt = 0;
    dimPaint();
  };
  // Команда dim (всем окнам): недостающее поле — прежнее, негодное — умолчание.
  const runDimCommand = detail => {
    if (!themable || !detail || typeof detail !== "object") return false;
    dimSetting = dimOk({
      on: "on" in detail ? detail.on : dimSetting.on,
      level: "level" in detail ? detail.level : dimSetting.level,
      keep: "keep" in detail ? detail.keep : dimSetting.keep,
    });
    try { localStorage.setItem(DIM_KEY, JSON.stringify(dimSetting)); } catch {}
    dimPaint();
    return true;
  };
  const onDimStorage = event => {
    if (!themable || (event?.key !== DIM_KEY && event?.key !== null)) return;
    dimSetting = readDim(dimSetting);
    dimPaint();
  };
  dimPaint();
  // Притемнение (WF113, #8256): выбор и лежит ли вуаль на этом окне сейчас.
  statusPart("dim", () => ({ on: dimSetting.on, level: dimSetting.level, keep: [...dimSetting.keep], veil: dimWanted() }));
  HATCH && Object.assign(HATCH, { attnFrameTick });

