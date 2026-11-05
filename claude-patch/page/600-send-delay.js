  // ---- 12у. Пять секунд на отмену отправки (#8069 WF105, #8103 WF106) -------
  // Слово Элвиса 29.09 12:15: «когда я отправляю сообщение, нужно, чтобы таймер
  // трёхсекундный тикал… чтоб я мог эскап нажать… и отменилась отправка».
  // WF106 (#8103, слово 29.09 ~16:00): «5 сек… на этой кнопке… Если я на неё
  // нажму ещё раз, то отправка отменится. Или Escape… Единственный способ, чтобы
  // отправка произошла, это дождаться… двойной Enter не будет отправку делать…
  // красным… предупреждать, что… контекста будет перечитано заново».
  // Ушедшее не отменить, поэтому Enter ловится ДО Claude: на захвате document
  // первым, раньше onPasteKey, — тогда вложения (раздел 12) и автосвёртка видят
  // только настоящую отправку. Откладывается лишь доверенный (isTrusted) Enter
  // без Shift и модификаторов, вне IME, в редакторе, при непустом поле
  // (composerFilled — одни вложения тоже) и закрытом меню подсказок: там Enter
  // выбирает пункт. Доверенный клик по кнопке отправки при непустом поле —
  // тоже счёт с выбранной длительностью: на захвате document глушатся
  // pointerdown/mousedown/pointerup/mouseup/click по кнопке, Claude их не видит.
  // Отправки самого Пимпа (send-text, pressLikeMouse) синтетические и идут мимо.
  // WF119: неподвижная цифра N→1, интервал 3/5/10 с или off. Свой fixed-узел
  // поверх кнопки (React не трогаем), без кнопки — плашка над рамкой поля.
  // Цвета — от темы; холодный кеш — красная кнопка и предупреждение.
  // Отмена — Esc (ветка onKeyDown, до глотания Esc), клик по
  // цифрам, кнопке или плашке, правка поля; текст остаётся. Повторный Enter во
  // время счёта — по настройке (#8917); ⌘↩/⌥↩ — перенос строки, ⌃↩ — как Enter, ⇧↩ во
  // время счёта шлёт сразу только явным выбором (WF192). Кеш чата остыл (sendDelayCold) —
  // кнопка красная, над ней плашка с «Отменить»; число токенов
  // присылает приложение командой chat-context на запрос /context.
  // Отпускание — синтетическим Enter в редактор
  // (так Claude ставит сообщение и в очередь идущего хода); поле не опустело за
  // SEND_DELAY_CHECK_MS — нажать кнопку, и так не ушло — плашка «Не ушло».
  // Сменился чат, начался обход чатов, заменён редактор, экземпляр снят — счёт
  // гаснет, ничего не уходит.
  const SEND_DELAY_TICK_MS = 1000;
  const SEND_DELAY_CHECK_MS = 1500;
  const SEND_DELAY_NOTE_MS = 3000;
  const SEND_DELAY_ID = "myclaude-send-delay";
  // WF119: прежний off-ключ остаётся ручным выключателем; чтение не пишет умолчания.
  const SEND_DELAY_OFF_KEY = "myclaude-send-delay-off";
  const SEND_DELAY_SECONDS_KEY = "myclaude-send-delay-seconds";
  // По умолчанию — 2 с (слово Элвиса 19.10.2026, #10361: «У ракеты… 2 секунды сделай»; с 07.10 было 3 с).
  const sendDelaySecondsOk = value => Number.isInteger(value) && [2, 3, 5, 10].includes(value);
  const sendDelaySetting = () => {
    try {
      const seconds = localStorage.getItem(SEND_DELAY_SECONDS_KEY);
      return { on: localStorage.getItem(SEND_DELAY_OFF_KEY) !== "1", seconds: ["2", "3", "5", "10"].includes(seconds) ? Number(seconds) : 2 };
    } catch { return { on: true, seconds: 2 }; }
  };
  const sendDelayOff = () => !sendDelaySetting().on;
  // Второй Enter во время счёта (#8917, слово Элвиса 07.10 ~03:10: «в настройках должно быть действие на повторное
  // нажатие Enter, по умолчанию повторное нажатие Enter должно отменять… ещё раз Enter нажал — отмена отправки»):
  // cancel — отмена, текст остаётся в поле (умолчание); send — отправить сразу (как #8338); none — ничего (как #8773).
  const SEND_DELAY_SECOND_KEY = "myclaude-send-delay-second";
  const SEND_DELAY_SECOND_VALUES = ["cancel", "send", "none"];
  const sendDelaySecond = () => {
    try {
      const value = localStorage.getItem(SEND_DELAY_SECOND_KEY);
      return SEND_DELAY_SECOND_VALUES.includes(value) ? value : "cancel";
    } catch { return "cancel"; }
  };
  // ⇧Enter во время счёта (WF126 §7.2, поправка критика 2): newline — перенос строки, как без счёта (правка поля
  // гасит счёт); send — отправить сразу (#8114), только явным выбором человека.
  // WF192 (слово Элвиса 09.10 04:10: «Никаких быстрых отправок. Всё на таймере всегда»): умолчание — newline,
  // ключа нет; «send» лежит в ключе строкой (до WF192 умолчанием был send, а ключ хранил только newline).
  const SEND_DELAY_SHIFT_KEY = "myclaude-send-delay-shift";
  const SEND_DELAY_SHIFT_VALUES = ["send", "newline"];
  const sendDelayShift = () => {
    try { return localStorage.getItem(SEND_DELAY_SHIFT_KEY) === "send" ? "send" : "newline"; } catch { return "newline"; }
  };
  // ⌘↩ и ⌥↩ (с ⇧ или без, но без ⌃) — перенос строки в поле, никогда не отправка (WF192, слово Элвиса 09.10 04:10:
  // «Command-Enter, Option-Enter — они должны переносить на новую строку»). Claude по ⌘↩ шлёт сразу — клавишу
  // глушим на захвате document и отдаём редактору синтетический ⇧↩: им Claude сам ставит перенос строки в позицию
  // курсора. Редактор его не взял (событие не погашено) — insertLineBreak. ⌃↩ — как Enter, через отсчёт.
  const sendDelayNewlineCombo = event => !event.ctrlKey && (event.metaKey === true || event.altKey === true);
  const sendDelayNewline = (event, editor) => {
    event.preventDefault();
    event.stopImmediatePropagation();
    sendDelayState.newlines += 1;
    let taken = false;
    try {
      taken = !editor.dispatchEvent(new KeyboardEvent("keydown", {
        key: "Enter", code: "Enter", keyCode: 13, which: 13, shiftKey: true, bubbles: true, cancelable: true, composed: true,
      }));
    } catch {}
    if (!taken) { try { document.execCommand("insertLineBreak"); } catch {} }
  };
  // Звук отсчёта (WF147, #9108, слово Элвиса 08.10 22:27: «обратный отсчёт, когда цифры тикают, можно со звуками…
  // синхронно с цифрами… Хотя это уже, наверное, излишне»). Короткий тихий звук ровно на показе каждой цифры, свой
  // завершающий — на отпускании; отмена — тишина. Только WebAudio-синтез (без файлов и сети), один AudioContext —
  // лениво при первом звуке, suspended → resume. Выбор — localStorage (ставит команда send-delay полем sound; приложение
  // берёт его из claude.json countdownSound); нет/мусор — bell. Скрытое окно, off, preview чужого окна — тишина.
  const SEND_DELAY_SOUND_KEY = "myclaude-send-delay-sound";
  const SEND_DELAY_SOUND_VALUES = ["bell", "tick", "drop", "retro", "off"];
  const SEND_DELAY_SOUND_VOLUME = 0.07;
  const sendDelaySound = () => {
    try {
      const value = localStorage.getItem(SEND_DELAY_SOUND_KEY);
      return SEND_DELAY_SOUND_VALUES.includes(value) ? value : "bell";
    } catch { return "bell"; }
  };
  const sendDelaySoundState = { ctx: null, played: 0, last: null, failed: 0 };
  const sendDelayAudio = () => {
    const s = sendDelaySoundState;
    if (s.ctx && s.ctx.state !== "closed") return s.ctx;
    const Ctor = window.AudioContext || window.webkitAudioContext;
    if (typeof Ctor !== "function") return null;
    s.ctx = new Ctor();
    return s.ctx;
  };
  // Одна нота: осциллятор (или шум) → фильтр? → огибающая → общий выход. t — смещение от «сейчас», с.
  const sendDelayVoice = (ctx, out, { type = "sine", freq = 880, to = null, at = 0, dur = 0.2, gain = 1, attack = 0.004, noise = false, band = 0 }) => {
    const t0 = ctx.currentTime + at;
    const env = ctx.createGain();
    env.gain.setValueAtTime(0.0001, t0);
    env.gain.linearRampToValueAtTime(gain, t0 + attack);
    env.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    let src;
    if (noise) {
      const length = Math.max(1, Math.floor(ctx.sampleRate * dur));
      const buffer = ctx.createBuffer(1, length, ctx.sampleRate);
      const data = buffer.getChannelData(0);
      for (let i = 0; i < length; i += 1) data[i] = Math.random() * 2 - 1;
      src = ctx.createBufferSource();
      src.buffer = buffer;
    } else {
      src = ctx.createOscillator();
      src.type = type;
      src.frequency.setValueAtTime(freq, t0);
      if (to) src.frequency.exponentialRampToValueAtTime(to, t0 + dur * 0.8);
    }
    let head = src;
    if (band > 0) {
      const filter = ctx.createBiquadFilter();
      filter.type = "bandpass";
      filter.frequency.setValueAtTime(band, t0);
      filter.Q.setValueAtTime(4, t0);
      src.connect(filter);
      head = filter;
    }
    head.connect(env);
    env.connect(out);
    src.start(t0);
    src.stop(t0 + dur + 0.02);
  };
  // Наборы: step — смена цифры, done — отпускание. gain — доля общей тихой громкости.
  const SEND_DELAY_SOUNDS = {
    // Мягкий колокольчик: чистый синус с октавным обертоном, затухание ~0,35 с; финал — две ноты вверх (ми → ля).
    bell: {
      step: [{ freq: 1318.5, dur: 0.35, gain: 0.8 }, { freq: 2637, dur: 0.18, gain: 0.15 }],
      done: [{ freq: 1318.5, dur: 0.4, gain: 0.7 }, { freq: 1760, at: 0.11, dur: 0.6, gain: 0.8 }, { freq: 3520, at: 0.11, dur: 0.25, gain: 0.12 }],
    },
    // Тик часов: щелчок шума в полосе 3,2 кГц, 30 мс; финал — «так» ниже и длиннее.
    tick: {
      step: [{ noise: true, band: 3200, dur: 0.03, gain: 1, attack: 0.001 }],
      done: [{ noise: true, band: 1600, dur: 0.06, gain: 1, attack: 0.001 }, { freq: 1046.5, at: 0.02, dur: 0.12, gain: 0.35 }],
    },
    // Капля: синус, падающий 1100 → 520 Гц за ~0,1 с; финал — «плюх» пониже и вторая капля.
    drop: {
      step: [{ freq: 1100, to: 520, dur: 0.13, gain: 0.9, attack: 0.002 }],
      done: [{ freq: 1500, to: 700, dur: 0.14, gain: 0.8, attack: 0.002 }, { freq: 900, to: 380, at: 0.12, dur: 0.2, gain: 0.8, attack: 0.002 }],
    },
    // Ретро-бип: квадрат 880 Гц, 70 мс (8-бит); финал — бип октавой выше, длиннее.
    retro: {
      step: [{ type: "square", freq: 880, dur: 0.07, gain: 0.35, attack: 0.001 }],
      done: [{ type: "square", freq: 1760, dur: 0.22, gain: 0.35, attack: 0.001 }],
    },
  };
  // kind: "step" | "done". Тихо и молча при любой беде: звук не должен ломать отправку.
  const sendDelayBeep = kind => {
    const id = sendDelaySound();
    const set = SEND_DELAY_SOUNDS[id];
    if (!set || !set[kind]) return false;
    try { if (document.hidden || document.visibilityState === "hidden") return false; } catch {}
    try {
      const ctx = sendDelayAudio();
      if (!ctx) return false;
      if (ctx.state === "suspended") { try { ctx.resume()?.catch?.(() => {}); } catch {} }
      const out = ctx.createGain();
      out.gain.setValueAtTime(SEND_DELAY_SOUND_VOLUME, ctx.currentTime);
      out.connect(ctx.destination);
      for (const voice of set[kind]) sendDelayVoice(ctx, out, voice);
      sendDelaySoundState.played += 1;
      sendDelaySoundState.last = { id, kind };
      return true;
    } catch { sendDelaySoundState.failed += 1; return false; }
  };
  const SEND_DELAY_FAIL_TEXT = "Не ушло — Enter отправит сразу";
  // После «Не ушло» следующий доверенный Enter идёт к Claude сам, без счёта:
  // иначе повтор снова встал бы в счёт и снова не ушёл (гейт WF105).
  const SEND_DELAY_BYPASS_MS = 15000;
  const SEND_DELAY_DROP_CHAT_TEXT = "Не отправлено — чат сменился";
  const SEND_DELAY_DROP_TEXT = "Не отправлено";
  const sendDelayLabel = left => {
    const second = sendDelaySecond();
    const shift = sendDelayShift() === "send" ? " · ⇧Enter — сразу" : "";
    if (second === "cancel") return `Отправка через ${left} · Enter или Esc — отмена${shift}`;
    if (second === "send") return `Отправка через ${left} · Enter — сразу · Esc — отмена`;
    return `Отправка через ${left}${shift} · Esc — отмена`;
  };
  const SEND_DELAY_DIGITS_ID = "myclaude-send-delay-digits";
  const SEND_DELAY_RED = "#e5484d";
  const SEND_DELAY_COLD_TEXT = "Кеш остыл — весь чат перечитается заново";
  const SEND_DELAY_CANCEL_TEXT = "Отменить";
  const sendDelayColdLabel = tokens => (tokens > 0
    ? `Кеш остыл — перечитается ~${String(tokens).replace(/\B(?=(\d{3})+(?!\d))/g, " ")} токенов`
    : SEND_DELAY_COLD_TEXT);
  const sendDelayState = {
    counting: false, left: 0, chat: null, editor: null, text: "", attachments: [], onSent: null, token: 0,
    started: 0, cancelled: 0, immediate: 0, dropped: 0, released: 0, sent: 0, failed: 0, last: null,
    bypassUntil: 0, cold: false, tokens: null, asks: 0, setting: null, newlines: 0,
  };
  const sendDelayTimers = new Set();
  const sendDelayLater = (fn, ms) => {
    const timer = setTimeout(() => { sendDelayTimers.delete(timer); fn(); }, ms);
    sendDelayTimers.add(timer);
  };
  let sendDelayNode = null;
  let sendDelayDigits = null;
  // Сироты семи прежних видов снимаются и при обновлении со старой страницы.
  for (const selector of ["#myclaude-send-delay", "#myclaude-send-delay-digits", "#myclaude-send-delay-rocket", ".myclaude-send-look-fly"]) {
    try { for (const node of document.querySelectorAll(selector)) node.remove(); } catch {}
  }
  // Анимации вида на секунду счёта: снимаются следующим тиком, отменой и концом.
  const sendDelayAnims = [];
  let sendDelayParts = null;
  let sendDelayRocket = null;
  const sendDelayCalm = () => {
    for (const anim of sendDelayAnims.splice(0)) { try { anim.cancel(); } catch {} }
  };
  // Отмена — узел гаснет без движения: кнопка Claude снова видна как была,
  // ничего не похоже на отправку. Взлёт (отпускание) живёт своим узлом.
  // WF188 (слово Элвиса 09.10 04:00: «прерывается — некрасиво»): узел прячется
  // сразу (нажатия идут кнопке Claude, состояние то же), а на его месте за
  // SEND_DELAY_FADE_MS тает его снимок — без id и роли, мимо мыши; снимается сам
  // по концу таяния, новый показ счёта снимает его сразу.
  const SEND_DELAY_FADE_MS = 180;
  const sendDelayGhosts = new Set();
  const sendDelayGhostsDrop = () => {
    for (const ghost of sendDelayGhosts) { try { ghost.remove(); } catch {} }
    sendDelayGhosts.clear();
  };
  const sendDelayFadeOut = node => {
    if (!node?.isConnected || node.style.getPropertyValue("display") === "none") return;
    if (!document.hidden) {
      try {
        const ghost = node.cloneNode(true);
        for (const name of ["id", "role", "title"]) ghost.removeAttribute(name);
        for (const kid of ghost.querySelectorAll("[id]")) kid.removeAttribute("id");
        ghost.setAttribute("aria-hidden", "true");
        ghost.style.setProperty("pointer-events", "none");
        (document.body ?? document.documentElement).appendChild(ghost);
        sendDelayGhosts.add(ghost);
        const gone = () => { sendDelayGhosts.delete(ghost); try { ghost.remove(); } catch {} };
        const anim = ghost.animate?.([{ opacity: 1 }, { opacity: 0 }], { duration: SEND_DELAY_FADE_MS, easing: "ease-out", fill: "forwards" });
        if (anim?.finished?.then) anim.finished.then(gone, gone); else gone();
      } catch {}
    }
    node.style.setProperty("display", "none");
  };
  const sendDelayHide = () => {
    sendDelayCalm();
    try { sendDelayFadeOut(sendDelayNode); } catch {}
    try { sendDelayFadeOut(sendDelayDigits); } catch {}
  };
  const sendDelayCss = (node, styles) => {
    for (const [name, value] of Object.entries(styles)) node.style.setProperty(name, value);
  };
  const sendDelayRun = (node, frames, options) => {
    try { const anim = node?.animate?.(frames, options); if (anim) sendDelayAnims.push(anim); return anim ?? null; } catch { return null; }
  };
  // -- WF128 К1 v3 (#9041): виды счёта снова разные --------------------------
  // Набор (слово Элвиса 08.10): 1.8 «Взлёт» (умолчание), 1.9 «Пульс», 1.10
  // «Мерцание», 1.1 «Штрих по кругу», 1.2 «Удар», 1.4 «Кольцо», 1.6 «Шнур»,
  // 1.5 «Спокойная цифра». 1.3 и 1.7 (летящие цифры, огни) не принимаются.
  // Ключ v2 (v1 у всех хранит 1.5 с WF119): нет v2 — 1.8 и размер из v1.
  // Всё движение — на кнопке отправки и рядом с ней; узел, что ловит нажатие, —
  // ровно её прямоугольник, части — pointer-events:none. «Уменьшить движение» и
  // скрытое окно — спокойная цифра 1.5. Код видов — WF114 (git 4b7c573^).
  const SEND_LOOK_KEY = "myclaude-send-look-v2";
  const SEND_LOOK_V1_KEY = "myclaude-send-look-v1";
  const SEND_LOOK_STYLES = ["1.8", "1.9", "1.10", "1.1", "1.2", "1.4", "1.6", "1.5"];
  const SEND_DELAY_ROCKET_ID = "myclaude-send-delay-rocket";
  const SEND_DELAY_AMBER = "#f59e0b";
  const SEND_DELAY_ARROW = "M12 18.5V6.2M6.6 11.4 12 6l5.4 5.4";
  const sendLookOk = raw => ({
    style: SEND_LOOK_STYLES.includes(raw?.style) ? raw.style : "1.8",
    size: typeof raw?.size === "number" && Number.isFinite(raw.size) && raw.size >= 60 && raw.size <= 200 ? Math.round(raw.size) : 150,
  });
  const sendLookJson = key => { try { return JSON.parse(localStorage.getItem(key) ?? "null"); } catch { return null; } };
  const readSendLook = () => {
    const v2 = sendLookJson(SEND_LOOK_KEY);
    return sendLookOk(v2 && typeof v2 === "object" ? v2 : { size: sendLookJson(SEND_LOOK_V1_KEY)?.size });
  };
  let sendLook = readSendLook();
  // Длина идущего счёта или показа (3/5/10) — от неё доля круга, шнура, пламени.
  let sendLookTotal = 3;
  const sendLookPreview = { on: false, left: 0, token: 0, shown: 0, chat: null, editor: null, text: "", attachments: [] };
  // Вид выбран человеком (ключ v2 есть) — играется и при «Уменьшить движение» (WF179, слово Элвиса 09.10
  // 02:50: «я отсчёт „Ракета“ поставил — не отрабатывает»; замер: у Мака reduceMotion=1, страница
  // показывала 1.5 при выбранном виде; класс #9115 — живой фон тоже плывёт). Выбора нет — как было:
  // «Уменьшить движение» — спокойная цифра. Скрытое окно — всегда 1.5.
  const sendLookChosen = () => { try { return localStorage.getItem(SEND_LOOK_KEY) != null; } catch { return false; } };
  const sendLookMotionOk = () => !document.hidden && (sendLookChosen() || progressMotionOk());
  const sendLookShown = () => (sendLookMotionOk() ? sendLook.style : "1.5");
  const sendLookSvg = (tag, attrs) => {
    const node = document.createElementNS("http://www.w3.org/2000/svg", tag);
    for (const [name, value] of Object.entries(attrs)) node.setAttribute(name, String(value));
    return node;
  };
  const sendLookSpan = styles => {
    const node = document.createElement("span");
    sendDelayCss(node, { position: "absolute", "pointer-events": "none", ...styles });
    return node;
  };
  const sendLookPx = value => `${Math.round(value * 100) / 100}px`;
  // Переход свойства за секунду: итог ставится стилем сразу, движение — анимацией.
  const sendLookTween = (node, from, to) => {
    if (!node) return;
    sendDelayCss(node, to);
    const frame = map => Object.fromEntries(Object.entries(map)
      .map(([name, value]) => [name.replace(/-([a-z])/g, (_, c) => c.toUpperCase()), value]));
    sendDelayRun(node, [frame(from), frame(to)], { duration: SEND_DELAY_TICK_MS, easing: "linear" });
  };
  // Волна от кнопки: кольцо расходится и тает (transform/opacity), снимается само.
  const sendLookShock = (host, color, scale, duration, width, delay = 0) => {
    const ring = sendLookSpan({ inset: "0", "border-radius": "50%", "border-style": "solid",
      "border-color": color, "border-width": sendLookPx(width), opacity: "0" });
    host.appendChild(ring);
    const anim = ring.animate?.([{ transform: "scale(1)", opacity: 0.9 }, { transform: `scale(${scale})`, opacity: 0 }],
      { duration, delay, easing: "cubic-bezier(.2,.7,.3,1)" });
    const gone = () => { try { ring.remove(); } catch {} };
    if (anim?.finished?.then) anim.finished.then(gone, gone); else gone();
    return anim ?? null;
  };
  const sendDelayArrow = (size, width) => {
    const svg = sendLookSvg("svg", { viewBox: "0 0 24 24", width: size, height: size, fill: "none", stroke: "currentColor",
      "stroke-width": width, "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": "true" });
    svg.appendChild(sendLookSvg("path", { d: SEND_DELAY_ARROW }));
    sendDelayCss(svg, { position: "relative", "z-index": "1", display: "block", overflow: "visible", "pointer-events": "none" });
    return svg;
  };
  // Цвета — от темы чата: акцент поверх фона поля; кеш остыл — красный.
  const sendLookAccent = cold => (cold ? SEND_DELAY_RED : accentColor());
  const sendLookLight = cold => `color-mix(in srgb, ${sendLookAccent(cold)} 55%, #ffffff)`;
  const sendLookColors = (style, cold) => {
    const field = progressFieldColor(state.shell);
    const ink = progressTextColor(state.shell);
    const acc = sendLookAccent(cold);
    const base = cold
      ? { background: `color-mix(in srgb, ${SEND_DELAY_RED} 22%, ${field})`, color: SEND_DELAY_RED, "border-color": SEND_DELAY_RED }
      : { background: `color-mix(in srgb, ${acc} 22%, ${field})`, color: `color-mix(in srgb, ${acc} 45%, ${ink})`, "border-color": progressTint(acc, 55) };
    const fire = cold ? SEND_DELAY_RED : SEND_DELAY_AMBER;
    // 1.5 — светлая кнопка (цвет текста поля) с цифрой цветом поля (WF119); остыл — красная.
    if (style === "1.5") return cold ? { background: SEND_DELAY_RED, color: "#ffffff", "border-color": "transparent" }
      : { background: ink, color: field, "border-color": "transparent" };
    // 1.2: сплошной акцент на своём диске (face), узел держит место.
    if (style === "1.2") return { background: field, color: "#ffffff", "border-color": "transparent" };
    // 1.4: без заливки — фон поля, цифра цветом текста.
    if (style === "1.4") return { background: field, color: cold ? SEND_DELAY_RED : ink, "border-color": "transparent" };
    // 1.6: тёмная кнопка с янтарной цифрой и ободком.
    if (style === "1.6") return { background: field, color: fire, "border-color": progressTint(fire, 60) };
    // 1.9: цифра цветом акцента на кнопке с лёгкой заливкой.
    if (style === "1.9") return { ...base, color: cold ? SEND_DELAY_RED : `color-mix(in srgb, ${acc} 70%, ${ink})` };
    return base;
  };
  // Доля круга 1.1 (растёт с хвостом и головой) и 1.4 (тает) на доле p.
  const sendLookRingAt = (style, p) => {
    const a = Math.max(0.001, 100 * p);
    if (style === "1.4") return { arc: { "stroke-dasharray": `${(100 - a).toFixed(2)} 100`, "stroke-dashoffset": (-a).toFixed(2) } };
    const t = Math.min(a, 20);
    return {
      arc: { "stroke-dasharray": `${a.toFixed(2)} 100` },
      tail: { "stroke-dasharray": `${t.toFixed(2)} 100`, "stroke-dashoffset": (-(a - t)).toFixed(2) },
      head: { transform: `rotate(${(360 * p).toFixed(1)}deg)` },
    };
  };
  // Смена цифры: 1.2 — удар из крупного, 1.4/1.10 — тихо проявляется, 1.9 — дыханием
  // (ниже), остальные — коротко снизу.
  const sendLookDigit = (parts, style) => {
    if (!parts.dig || style === "1.9") return;
    if (style === "1.4" || style === "1.10") { sendDelayRun(parts.dig, [{ opacity: 0 }, { opacity: 1 }], { duration: 220 }); return; }
    if (style === "1.2") {
      sendDelayRun(parts.dig, [{ transform: "scale(1.8)", opacity: 0.3 }, { transform: "scale(1)", opacity: 1 }],
        { duration: 280, easing: "cubic-bezier(.2,1.5,.4,1)" });
      return;
    }
    sendDelayRun(parts.dig, [{ opacity: 0, transform: "translateY(5px) scale(.8)" }, { opacity: 1, transform: "none" }],
      { duration: 200, easing: "ease-out" });
  };
  // Шнур 1.6: искра бежит по рамке поля к кнопке, искры сыплются у неё.
  const sendLookFuse = (parts, p0, p1, cold) => {
    const fire = cold ? SEND_DELAY_RED : SEND_DELAY_AMBER;
    sendDelayCss(parts.rope, { stroke: fire });
    sendDelayCss(parts.wrap, { filter: `drop-shadow(0 0 3px ${progressTint(fire, 75)})` });
    const rope = p => ({ "stroke-dasharray": `${(100 * (1 - p)).toFixed(2)} 100`, "stroke-dashoffset": (-100 * p).toFixed(2) });
    sendLookTween(parts.rope, rope(p0), rope(p1));
    sendLookTween(parts.spark, { "offset-distance": `${(100 * p0).toFixed(2)}%` }, { "offset-distance": `${(100 * p1).toFixed(2)}%` });
    const k = sendLook.size / 100;
    for (const dot of parts.dots) {
      dot.style.setProperty("background", cold ? "#ffc2c4" : "#ffd27a");
      const angle = Math.random() * Math.PI * 2;
      const speed = 40 + Math.random() * 90;
      const life = 0.22 + Math.random() * 0.25;
      const dx = Math.cos(angle) * speed * life * k;
      const dy = (Math.sin(angle) * speed - 40) * life * k + 130 * life * life * k;
      sendDelayRun(dot, [
        { transform: "translate(0px, 0px)", opacity: 1 },
        { transform: `translate(${dx.toFixed(1)}px, ${dy.toFixed(1)}px)`, opacity: 0 },
      ], { duration: Math.round(life * 1000), iterations: Math.max(1, Math.floor(1 / life)), easing: "ease-out" });
    }
  };
  // Кадр секунды вида. p0→p1 — доля пройденного за эту секунду; последняя
  // секунда (left 1) — у 1.9/1.10 вдвое чаще, у 1.8 пламя и дрожь на пределе,
  // круг 1.1 замыкается, кольцо 1.4 тает в ноль, искра 1.6 у кнопки.
  const sendDelayFire = (left, cold) => {
    const parts = sendDelayParts;
    if (!parts || parts.style === "1.5") return;
    sendDelayCalm();
    const total = Math.max(1, sendLookTotal);
    const p0 = Math.min(1, Math.max(0, (total - left) / total));
    const p1 = Math.min(1, Math.max(0, (total - left + 1) / total));
    const last = left <= 1;
    const style = parts.style;
    const acc = sendLookAccent(cold);
    sendLookDigit(parts, style);
    if (style === "1.8") {
      const fire = cold ? SEND_DELAY_RED : SEND_DELAY_AMBER;
      sendDelayCss(parts.flame, {
        background: `linear-gradient(${cold ? "#ffe1e1" : "#fff6d0"}, ${fire} 45%, rgba(229,72,77,0))`,
        opacity: (0.45 + 0.55 * p1).toFixed(2), transform: `scaleY(${(0.35 + 0.95 * p1).toFixed(2)})`,
      });
      const jitter = () => Math.random() * 2 - 1;
      const shake = 0.25 + 2.3 * p1 * p1;
      sendDelayRun(parts.badge, [{ transform: "scale(1.5)" }, { transform: "scale(1)" }], { duration: 260, easing: "cubic-bezier(.2,1.5,.4,1)" });
      sendDelayRun(parts.arrow, Array.from({ length: 13 }, (_, index) => ({
        transform: index === 0 || index === 12 ? "translate(0px, 0px)"
          : `translate(${(jitter() * shake).toFixed(2)}px, ${(jitter() * shake * 0.6 - (last ? 1.5 : 0)).toFixed(2)}px)`,
      })), { duration: SEND_DELAY_TICK_MS, easing: "linear" });
      sendDelayRun(parts.flame, Array.from({ length: 9 }, () => ({
        transform: `scaleY(${(0.35 + 0.95 * p1 + Math.random() * 0.3).toFixed(2)}) scaleX(${(0.8 + Math.random() * 0.3).toFixed(2)})`,
      })), { duration: SEND_DELAY_TICK_MS, easing: "linear" });
      return;
    }
    if (style === "1.9") {
      const peak = (1.18 + 0.22 * p1).toFixed(2);
      sendDelayRun(parts.dig, [{ transform: "scale(1)" }, { transform: `scale(${peak})`, offset: 0.45 }, { transform: "scale(1)" }],
        { duration: last ? SEND_DELAY_TICK_MS / 2 : SEND_DELAY_TICK_MS, iterations: last ? 2 : 1, easing: "ease-in-out" });
      return;
    }
    if (style === "1.10") {
      sendDelayCss(parts.halo, { "box-shadow": `0 0 ${sendLookPx(10 * sendLook.size / 100)} ${sendLookPx(3 * sendLook.size / 100)} ${progressTint(acc, 80)}` });
      const high = Math.min(1, 0.55 + 0.4 * p1).toFixed(2);
      sendDelayRun(parts.halo, [{ opacity: 0.2 }, { opacity: Number(high), offset: 0.5 }, { opacity: 0.2 }],
        { duration: last ? SEND_DELAY_TICK_MS / 2 : SEND_DELAY_TICK_MS, iterations: last ? 2 : 1, easing: "ease-in-out" });
      return;
    }
    if (style === "1.1" || style === "1.4") {
      const from = sendLookRingAt(style, p0);
      const to = sendLookRingAt(style, p1);
      for (const name of Object.keys(to)) sendLookTween(parts[name], from[name], to[name]);
      if (style === "1.1") {
        sendDelayCss(parts.arc, { stroke: acc });
        sendDelayCss(parts.tail, { stroke: sendLookLight(cold) });
        sendDelayCss(parts.ring, { filter: `drop-shadow(0 0 4px ${acc}) drop-shadow(0 0 1px #ffffff)` });
      } else {
        const ink = cold ? SEND_DELAY_RED : progressTextColor(state.shell);
        sendDelayCss(parts.arc, { stroke: `color-mix(in srgb, ${ink} 80%, transparent)` });
        sendDelayCss(parts.trk, { stroke: `color-mix(in srgb, ${ink} 8%, transparent)` });
      }
      return;
    }
    if (style === "1.2") {
      sendDelayCss(parts.face, { background: acc });
      sendDelayRun(parts.face, [
        { transform: "scale(1)" }, { transform: "scale(.72)", offset: 0.08 }, { transform: "scale(1.12)", offset: 0.22 },
        { transform: "scale(.88)", offset: 0.34 }, { transform: "scale(1.04)", offset: 0.48 }, { transform: "scale(1)", offset: 0.7 },
        { transform: "scale(1)" },
      ], { duration: 820, easing: "linear" });
      const shock = sendLookShock(sendDelayDigits, progressTint(acc, 95), 2.8, 700, 2 * sendLook.size / 100);
      if (shock) sendDelayAnims.push(shock);
      return;
    }
    if (style === "1.6") sendLookFuse(parts, p0, p1, cold);
  };
  // Отправлено: 1.8 — ракета уходит вверх за край окна и оставляет яркую линию,
  // которая потом плавно тает (WF188, слово Элвиса 09.10 04:00: «оборвалась
  // ракета… Она должна вверху лететь, как раньше, и линию ставить яркую, которая
  // затухнуть должна»; «как раньше» — взлёт WF108 за верхний край, WF153 гасил её
  // на 120 pt посреди полёта — это и был обрыв). 1.1/1.2/1.6/1.9/1.10 — волна от
  // кнопки; 1.4 и 1.5 — тихо гаснут. Узел свой (fixed на body, вне узлов Claude),
  // снимается только когда доиграли ВСЕ его анимации.
  const SEND_DELAY_FLY_MS = 820;
  const SEND_DELAY_TRAIL_FADE_MS = 650;
  const sendDelayLaunch = cold => {
    try { sendDelayRocket?.remove(); } catch {}
    sendDelayRocket = null;
    try {
      const style = sendDelayParts?.style ?? "1.5";
      if (style === "1.4" || style === "1.5" || !sendLookMotionOk() || sendDelayDigits?.style.getPropertyValue("display") !== "flex") return;
      const rect = document.querySelector(SEND_SELECTOR)?.getBoundingClientRect?.();
      if (!(rect && rect.width > 0 && rect.height > 0)) return;
      const k = sendLook.size / 100;
      const node = document.createElement("div");
      node.id = SEND_DELAY_ROCKET_ID;
      node.setAttribute("aria-hidden", "true");
      (document.body ?? document.documentElement).appendChild(node);
      sendDelayRocket = node;
      const gone = () => { try { node.remove(); } catch {} if (sendDelayRocket === node) sendDelayRocket = null; };
      const goneAfter = anims => {
        const done = anims.filter(anim => anim?.finished?.then).map(anim => anim.finished.catch(() => {}));
        if (done.length) Promise.all(done).then(gone, gone); else gone();
      };
      if (style !== "1.8") {
        sendDelayCss(node, {
          position: "fixed", left: `${Math.round(rect.left)}px`, top: `${Math.round(rect.top)}px`,
          width: `${Math.round(rect.width)}px`, height: `${Math.round(rect.height)}px`,
          "border-radius": "50%", "pointer-events": "none", "z-index": "2147483644",
        });
        const acc = sendLookAccent(cold);
        const waves = {
          "1.1": [[acc, 1.5, 420, 2.8, 0], [sendLookLight(cold), 2.3, 520, 2, 0]],
          "1.2": [[progressTint(acc, 95), 3.8, 800, 3, 0], [sendLookLight(cold), 3, 650, 2, 130]],
          "1.6": [[progressTint(cold ? SEND_DELAY_RED : SEND_DELAY_AMBER, 95), 3.2, 650, 3, 0]],
          "1.9": [[progressTint(acc, 90), 1.9, 520, 2.4, 0]],
          "1.10": [[sendLookLight(cold), 2.2, 600, 3, 0], [progressTint(acc, 60), 1.6, 480, 6, 60]],
        }[style] ?? [];
        goneAfter(waves.map(([paint, scale, duration, width, delay]) => sendLookShock(node, paint, scale, duration, width * k, delay)));
        return;
      }
      const half = 13 * k;
      const color = sendDelayDigits.style.getPropertyValue("color");
      const cx = rect.left + rect.width / 2;
      const cy = rect.top + rect.height / 2;
      // Ракета уходит целиком за верхний край окна (WF108): центр — на cy + запас.
      const rise = Math.round(cy + 30 * k + 24);
      // Точка отсчёта — центр кнопки; линия и ракета — от неё, без своих рамок.
      sendDelayCss(node, {
        position: "fixed", left: `${Math.round(cx)}px`, top: `${Math.round(cy)}px`, width: "0px", height: "0px",
        overflow: "visible", color, "pointer-events": "none", "z-index": "2147483644",
      });
      const flame = cold ? "rgba(229,72,77,.95)" : "rgba(245,158,11,.95)";
      // Линия — яркая полоса от кнопки до ракеты: растёт ровно за ней (те же
      // кадры и кривая, что у полёта), стоит, пока ракета уходит, и тает.
      const line = sendLookSpan({
        left: sendLookPx(-1.5 * k), top: `${-rise}px`, width: sendLookPx(3 * k), height: `${rise}px`,
        "border-radius": sendLookPx(2 * k), "transform-origin": "50% 100%", transform: "scaleY(0)",
        background: `linear-gradient(to top, ${flame.replace(".95", ".35")}, ${flame} 45%, ${sendLookLight(cold)})`,
        "box-shadow": `0 0 ${sendLookPx(6 * k)} ${flame}`,
      });
      const rocket = sendLookSpan({ left: `${-half}px`, top: `${-half}px`, width: sendLookPx(26 * k), height: sendLookPx(26 * k) });
      const exhaust = sendLookSpan({ left: "50%", top: "70%", width: sendLookPx(4 * k), height: sendLookPx(22 * k),
        "margin-left": sendLookPx(-2 * k), "border-radius": "2px", background: `linear-gradient(${flame}, transparent)` });
      const arrow = sendDelayArrow(Math.round(26 * k), 2.6);
      arrow.style.setProperty("filter", `drop-shadow(0 0 6px ${color})`);
      rocket.append(exhaust, arrow);
      node.append(line, rocket);
      const lift = Math.min(36, rise);
      const fly = { duration: SEND_DELAY_FLY_MS, easing: "cubic-bezier(.5,0,.8,.6)", fill: "forwards" };
      const total = SEND_DELAY_FLY_MS + SEND_DELAY_TRAIL_FADE_MS;
      const anims = [
        rocket.animate?.([
          { transform: "translateY(0px) scale(1)" },
          { transform: `translateY(${-lift}px) scale(1.25)`, offset: 0.28 },
          { transform: `translateY(${-rise}px) scale(1.5)` },
        ], fly),
        line.animate?.([
          { transform: "scaleY(0)" },
          { transform: `scaleY(${(lift / rise).toFixed(4)})`, offset: 0.28 },
          { transform: "scaleY(1)" },
        ], fly),
        line.animate?.([
          { opacity: 1 },
          { opacity: 1, offset: SEND_DELAY_FLY_MS / total, easing: "cubic-bezier(.3,0,.5,1)" },
          { opacity: 0 },
        ], { duration: total, fill: "forwards" }),
      ];
      goneAfter(anims);
    } catch {}
  };
  // Части вида внутри узла счёта; k — размер (0,6…2), множит только видимое.
  const sendLookBuild = (node, style, k) => {
    if (style === "1.8") {
      // Пламя под стрелкой, стрелка, метка с секундами в углу кнопки.
      const flame = sendLookSpan({
        left: "50%", top: "58%", width: sendLookPx(7 * k), height: sendLookPx(13 * k), "margin-left": sendLookPx(-3.5 * k),
        "border-radius": "50% 50% 50% 50% / 25% 25% 75% 75%", "transform-origin": "50% 0",
      });
      const arrow = sendDelayArrow(Math.round(17 * k), 2.3);
      const badge = document.createElement("span");
      sendDelayCss(badge, {
        position: "absolute", right: sendLookPx(-8 * k), top: sendLookPx(-9 * k), "min-width": sendLookPx(17 * k),
        height: sendLookPx(17 * k), padding: `0 ${sendLookPx(3 * k)}`, "box-sizing": "border-box",
        "border-radius": sendLookPx(9 * k), font: `800 ${sendLookPx(10.5 * k)}/${sendLookPx(17 * k)} -apple-system, system-ui, sans-serif`,
        "text-align": "center", "z-index": "2", "pointer-events": "none",
      });
      node.append(flame, arrow, badge);
      return { style, flame, arrow, badge };
    }
    const parts = { style };
    const dig = document.createElement("span");
    sendDelayCss(dig, { position: "relative", "z-index": "2", display: "block", "pointer-events": "none",
      "font-weight": style === "1.4" ? "600" : style === "1.9" ? "800" : "700", "line-height": "1",
      "font-family": "-apple-system, system-ui, sans-serif", "font-variant-numeric": "tabular-nums" });
    parts.dig = dig;
    parts.px = { "1.2": 14, "1.4": 12, "1.9": 14 }[style] ?? 13;
    if (style === "1.2") node.append(parts.face = sendLookSpan({ inset: "0", "border-radius": "50%" }));
    if (style === "1.10") node.append(parts.halo = sendLookSpan({ inset: "0", "border-radius": "50%", opacity: "0.2" }));
    if (style === "1.1" || style === "1.4") {
      const ring = sendLookSvg("svg", { "aria-hidden": "true", fill: "none" });
      sendDelayCss(ring, { position: "absolute", overflow: "visible", "pointer-events": "none" });
      parts.ring = ring;
      parts.trk = sendLookSvg("circle", { fill: "none" });
      parts.arc = sendLookSvg("circle", { fill: "none", pathLength: 100, "stroke-linecap": "round" });
      ring.append(parts.trk, parts.arc);
      if (style === "1.1") {
        parts.tail = sendLookSvg("circle", { fill: "none", pathLength: 100, "stroke-linecap": "round" });
        parts.head = sendLookSvg("g", {});
        parts.dot = sendLookSvg("circle", { fill: "#ffffff" });
        parts.head.appendChild(parts.dot);
        ring.append(parts.tail, parts.head);
      }
      node.append(ring);
    }
    if (style === "1.6") {
      parts.wrap = sendLookSpan({ display: "block" });
      const svg = sendLookSvg("svg", { "aria-hidden": "true", fill: "none" });
      sendDelayCss(svg, { position: "absolute", left: "0px", top: "0px", overflow: "visible", "pointer-events": "none" });
      parts.svg = svg;
      parts.rope = sendLookSvg("path", { fill: "none", pathLength: 100, "stroke-linecap": "round", "stroke-width": 2 * k });
      svg.appendChild(parts.rope);
      parts.spark = sendLookSpan({ left: "0px", top: "0px", width: sendLookPx(6.4 * k), height: sendLookPx(6.4 * k),
        "border-radius": "50%", background: "#fff8e6", "offset-rotate": "0deg" });
      parts.dots = Array.from({ length: 8 }, () => sendLookSpan({ left: "50%", top: "50%", width: sendLookPx(2.6 * k),
        height: sendLookPx(2.6 * k), "margin-left": sendLookPx(-1.3 * k), "margin-top": sendLookPx(-1.3 * k),
        "border-radius": "50%", opacity: "0" }));
      parts.spark.append(...parts.dots);
      parts.wrap.append(svg, parts.spark);
      node.append(parts.wrap);
    }
    node.append(dig);
    return parts;
  };
  // Две цифры (10 с) помещаются в кнопку при любом размере (WF119).
  const sendLookFontPx = (px, rect, left) => Math.min(px * sendLook.size / 100, (rect.width - 4) / (String(left).length * 0.65), rect.height - 4);
  // Геометрия вида под кнопку — на каждом тике (окно могли растянуть).
  const sendLookPlace = (parts, rect, left) => {
    const k = sendLook.size / 100;
    if (parts.dig) parts.dig.style.setProperty("font-size", `${Math.round(sendLookFontPx(parts.px, rect, left) * 100) / 100}px`);
    if (parts.ring) {
      const wide = parts.style === "1.1";
      const r = (Math.min(rect.width, rect.height) / 2 + (wide ? 4 : 1.2)) * k;
      const size = 2 * (r + 4 * k);
      const c = size / 2;
      const round = value => Math.round(value * 100) / 100;
      for (const [name, value] of Object.entries({ width: round(size), height: round(size), viewBox: `0 0 ${round(size)} ${round(size)}` })) {
        parts.ring.setAttribute(name, String(value));
      }
      sendDelayCss(parts.ring, { left: sendLookPx((rect.width - 2 - size) / 2), top: sendLookPx((rect.height - 2 - size) / 2) });
      for (const circle of [parts.trk, parts.arc, parts.tail]) {
        if (!circle) continue;
        for (const [name, value] of Object.entries({ cx: c, cy: c, r, "stroke-width": (circle === parts.tail ? 3 : wide ? 2.8 : 1.5) * k })) {
          circle.setAttribute(name, String(Math.round(value * 100) / 100));
        }
        if (circle !== parts.trk) circle.setAttribute("transform", `rotate(-90 ${c} ${c})`);
      }
      if (wide) {
        sendDelayCss(parts.trk, { stroke: `color-mix(in srgb, ${progressTextColor(state.shell)} 8%, transparent)` });
        for (const [name, value] of Object.entries({ cx: c, cy: c - r, r: 2.6 * k })) parts.dot.setAttribute(name, String(Math.round(value * 100) / 100));
        sendDelayCss(parts.head, { "transform-origin": `${sendLookPx(c)} ${sendLookPx(c)}` });
      }
    }
    if (parts.wrap) {
      // Шнур идёт по рамке поля; рамки нет — шнура нет, цифра остаётся.
      let shell = null;
      try { shell = state.shell?.isConnected ? state.shell.getBoundingClientRect() : null; } catch {}
      if (!(shell && shell.width > 0 && shell.height > 0)) { parts.wrap.style.setProperty("display", "none"); return; }
      const inner = Math.min(rect.width, rect.height) - 2;
      const W = Math.round(shell.width);
      const H = Math.round(shell.height);
      const R = Math.max(1, Math.min(17, H / 2, W / 2));
      const bx = rect.left + rect.width / 2 - shell.left;
      const by = rect.top + rect.height / 2 - shell.top;
      const d = `M0.75 ${H - R} V${R} A${R} ${R} 0 0 1 ${R} 0.75 H${W - R} A${R} ${R} 0 0 1 ${W - 0.75} ${R} ` +
        `V${by.toFixed(1)} H${(bx + inner / 2 + 2).toFixed(1)}`;
      sendDelayCss(parts.wrap, { display: "block", left: sendLookPx(shell.left - rect.left - 1), top: sendLookPx(shell.top - rect.top - 1),
        width: `${W}px`, height: `${H}px` });
      for (const [name, value] of Object.entries({ width: W, height: H, viewBox: `0 0 ${W} ${H}` })) parts.svg.setAttribute(name, String(value));
      parts.rope.setAttribute("d", d);
      sendDelayCss(parts.spark, { "offset-path": `path("${d}")` });
    }
  };
  // Плашка и цифры — наши: нажатие по ним идёт веткой отмены.
  const sendDelayOurs = target => {
    try {
      return Boolean((sendDelayNode?.isConnected && sendDelayNode.contains(target)) ||
        (sendDelayDigits?.isConnected && sendDelayDigits.contains(target)));
    } catch { return false; }
  };
  const sendDelayPalette = () => (progressDark()
    ? { background: "#12151c", color: "#e7e9f0", "border-color": "#2a2f3a", "box-shadow": "0 6px 18px rgba(0,0,0,.45)" }
    : { background: "#ffffff", color: "#14181f", "border-color": "#d7dbe3", "box-shadow": "0 6px 18px rgba(15,20,30,.18)" });
  // Узел счёта ровно на прямоугольнике кнопки — цель нажатия; без кнопки — false,
  // счёт покажет плашка. Вид или размер сменились — узел собирается заново.
  const sendDelayShowDigits = (left, cold) => {
    try {
      const rect = document.querySelector(SEND_SELECTOR)?.getBoundingClientRect?.();
      if (!(rect && rect.width > 0 && rect.height > 0)) {
        sendDelayDigits?.style.setProperty("display", "none");
        return false;
      }
      const style = sendLookShown();
      const look = `${style}/${sendLook.size}`;
      if (!sendDelayDigits?.isConnected || sendDelayDigits.getAttribute("data-look") !== look) {
        sendDelayCalm();
        try { sendDelayDigits?.remove(); } catch {}
        const node = document.createElement("div");
        node.id = SEND_DELAY_DIGITS_ID;
        node.setAttribute("role", "timer");
        node.setAttribute("data-look", look);
        sendDelayCss(node, {
          position: "fixed", "box-sizing": "border-box", "align-items": "center", "justify-content": "center",
          "border-radius": "50%", "border-width": "1px", "border-style": "solid", "line-height": "1", "font-weight": "700",
          "font-family": "-apple-system, system-ui, sans-serif", "font-variant-numeric": "tabular-nums",
          cursor: "pointer", "user-select": "none", "pointer-events": "auto", "z-index": "2147483644",
        });
        sendDelayParts = style === "1.5" ? { style } : sendLookBuild(node, style, sendLook.size / 100);
        (document.body ?? document.documentElement).appendChild(node);
        sendDelayDigits = node;
      }
      const node = sendDelayDigits;
      const parts = sendDelayParts;
      sendDelayGhostsDrop();
      node.title = sendLookPreview.on ? "Остановить показ" : "Отменить отправку";
      sendDelayCss(node, {
        ...sendLookColors(style, cold), display: "flex", left: `${Math.round(rect.left)}px`, top: `${Math.round(rect.top)}px`,
        width: `${Math.round(rect.width)}px`, height: `${Math.round(rect.height)}px`,
      });
      // 1.5 — одна неподвижная цифра прямо в узле (WF119).
      if (style === "1.5") {
        node.textContent = String(left);
        node.style.setProperty("font-size", `${sendLookFontPx(13, rect, left)}px`);
        return true;
      }
      if (parts.badge) {
        sendDelayCss(parts.badge, {
          background: cold ? SEND_DELAY_RED : SEND_DELAY_AMBER, color: cold ? "#ffffff" : "#1f1e1d",
          "box-shadow": `0 0 0 2px ${progressFieldColor(state.shell)}`,
        });
        parts.badge.textContent = String(left);
      }
      if (parts.dig) parts.dig.textContent = String(left);
      sendLookPlace(parts, rect, left);
      sendDelayFire(left, cold);
      return true;
    } catch { return false; }
  };
  const sendDelayShow = (text, { cold = false } = {}) => {
    try {
      if (!sendDelayNode?.isConnected) {
        const node = document.createElement("div");
        node.id = SEND_DELAY_ID;
        node.setAttribute("role", "status");
        for (const [name, value] of Object.entries({
          position: "fixed", display: "none", width: "max-content", padding: "5px 9px",
          "border-radius": "8px", "border-width": "1px", "border-style": "solid",
          font: "12px/1.4 -apple-system, system-ui, sans-serif", "white-space": "normal",
          "box-sizing": "border-box",
          cursor: "pointer", "user-select": "none", "pointer-events": "auto", "z-index": "2147483644",
        })) node.style.setProperty(name, value);
        (document.body ?? document.documentElement).appendChild(node);
        sendDelayNode = node;
      }
      const node = sendDelayNode;
      const paint = sendDelayPalette();
      // Остывший кеш — красная плашка с кнопкой «Отменить» (нажатие по плашке
      // целиком — отмена, кнопка — для глаза).
      if (cold) Object.assign(paint, { background: SEND_DELAY_RED, color: "#ffffff", "border-color": SEND_DELAY_RED });
      for (const [name, value] of Object.entries(paint)) node.style.setProperty(name, value);
      node.textContent = text;
      if (cold) {
        const cancel = document.createElement("button");
        cancel.type = "button";
        cancel.textContent = SEND_DELAY_CANCEL_TEXT;
        for (const [name, value] of Object.entries({
          "margin-left": "8px", padding: "1px 8px", "border-radius": "6px", border: "1px solid rgba(255,255,255,.75)",
          background: "transparent", color: "inherit", font: "inherit", cursor: "pointer",
        })) cancel.style.setProperty(name, value);
        node.appendChild(cancel);
      }
      // Над кнопкой отправки, правым краем по ней; кнопки нет — над рамкой поля.
      let rect = null;
      const send = document.querySelector(SEND_SELECTOR);
      const own = send?.getBoundingClientRect?.();
      if (own && own.width > 0 && own.height > 0) rect = own;
      else if (state.shell?.isConnected) {
        const shell = state.shell.getBoundingClientRect();
        if (shell.width > 0 && shell.height > 0) rect = shell;
      }
      const width = window.innerWidth || 0;
      const height = window.innerHeight || 0;
      const place = rect && width && height
        // Узкое окно (280–360 pt): плашка переносится и не уходит за левый край (проверка WF106).
        ? { left: "auto", transform: "none", right: `${Math.max(8, Math.round(width - rect.right))}px`,
          "max-width": `${Math.max(120, Math.round(width - 8 - Math.max(8, Math.round(width - rect.right))))}px`,
          bottom: `${Math.max(8, Math.round(height - rect.top + 6))}px` }
        : { right: "auto", left: "50%", transform: "translateX(-50%)", bottom: "96px", "max-width": "calc(100vw - 16px)" };
      for (const [name, value] of Object.entries(place)) node.style.setProperty(name, value);
      sendDelayGhostsDrop();
      node.style.setProperty("display", "block");
    } catch {}
  };
  // Кадр счёта: цифры на кнопке; остыл кеш — и красная плашка над ней.
  const sendDelayPaint = () => {
    const s = sendDelayState;
    const onButton = sendDelayShowDigits(s.left, s.cold);
    if (s.cold) {
      const text = sendDelayColdLabel(s.tokens);
      sendDelayShow(onButton ? text : `${text} · через ${s.left}`, { cold: true });
    } else if (onButton) {
      try { sendDelayNode?.style.setProperty("display", "none"); } catch {}
    } else sendDelayShow(sendDelayLabel(s.left));
  };
  // Кеш чата остыл: с последней активности чата (часики угла cornerUpdatedAt,
  // запасной — время последнего сообщения ленты sigState.lastAt) прошёл час
  // (CACHE_TTL_MS), и чат не работает. Нет ни того, ни другого — тёплый, без
  // ложной тревоги. CACHE_TTL_MS и sigState объявлены ниже (12о) — читаются
  // здесь только в обработчике, не при загрузке.
  const sendDelayCold = (wall = Date.now()) => {
    try {
      if (waitState.kind === "running" || document.querySelector(WORKING_SELECTOR) != null) return false;
    } catch {}
    let last = 0;
    try { last = cornerUpdatedAt(); } catch { last = 0; }
    if (!(last > 0)) { try { last = sigState.lastAt > 0 ? sigState.lastAt : 0; } catch { last = 0; } }
    return last > 0 && wall - last >= CACHE_TTL_MS;
  };
  // Число токенов перечитки — у приложения (К WF106): раз за счёт и только для
  // холодного чата, ответ — командой chat-context.
  const sendDelayAskContext = chat => {
    if (typeof chat !== "string" || !chat || typeof fetch !== "function") return;
    sendDelayState.asks += 1;
    try {
      fetch(`http://127.0.0.1:${HTML_CHROME_PORT}/context?chat=${encodeURIComponent(chat)}`, { mode: "cors", credentials: "omit", cache: "no-store" })
        .catch(() => {});
    } catch {}
  };
  const sendDelayContext = detail => {
    const s = sendDelayState;
    if (!s.counting || !s.cold) return;
    const chat = typeof detail?.chat === "string" ? detail.chat : "";
    if (!chat || chat !== s.chat || chat !== myChatId()) return;
    const tokens = Number(detail?.tokens);
    if (!Number.isFinite(tokens) || tokens <= 0) return;
    s.tokens = Math.round(tokens);
    sendDelayPaint();
  };
  // Меню подсказок (/-команды, @-файлы) и любое открытое меню или список: Enter
  // там выбирает пункт и ничего не шлёт (DECISIONS «Автосвёртка»).
  const sendDelayMenuOpen = editor => {
    try {
      if (overlayOpen()) return true;
      for (const node of document.querySelectorAll("[cmdk-root]")) {
        const rect = node.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) return true;
      }
      return editor?.getAttribute?.("aria-expanded") === "true";
    } catch { return true; }
  };
  const sendDelayNote = (what, why) => {
    const s = sendDelayState;
    s[what] += 1;
    s.last = { what, why: why || "", at: new Date().toISOString() };
  };
  const sendDelayStop = (what, why) => {
    const s = sendDelayState;
    if (!s.counting) return;
    s.token += 1;
    Object.assign(s, { counting: false, left: 0, chat: null, editor: null, text: "", attachments: [], onSent: null, cold: false, tokens: null });
    sendDelayNote(what, why);
    sendDelayHide();
  };
  // Почему счёт больше не про это поле: пусто — всё на месте.
  const sendDelayLost = () => {
    const s = sendDelayState;
    if (!state.alive) return "gone";
    if (state.editor !== s.editor || !s.editor?.isConnected || findEditor() !== s.editor) return "editor";
    if (myChatId() !== s.chat) return "chat";
    if (roamState.phase !== "idle") return "roam";
    return "";
  };
  // Вложения поля — число плиток и их имена (composerTileNames, раздел 12т¹):
  // перерисованная плитка с тем же именем счёт не гасит.
  const sendDelayAttachments = () => composerTileNames();
  const sendDelaySameAttachments = saved => {
    const current = sendDelayAttachments();
    return current.length === saved.length && current.every((name, index) => name === saved[index]);
  };
  const sendDelayRelease = (why = "timer") => {
    const s = sendDelayState;
    if (shotBlocked() || sendDelayLost() || rawText(s.editor) !== s.text || !sendDelaySameAttachments(s.attachments)) {
      sendDelayStop("dropped", "draft-changed"); return;
    }
    if (sendDelaySettingChanged()) { sendDelayStop("cancelled", "setting"); return; }
    const { editor, text, chat, attachments, onSent, cold } = s;
    const sent = via => { sendDelayNote("sent", via); onSent?.(); };
    const sameTarget = () => !shotState.pending && editor.isConnected && findEditor() === editor && myChatId() === chat && roamState.phase === "idle";
    s.token += 1;
    const token = s.token;
    Object.assign(s, { counting: false, left: 0, chat: null, editor: null, text: "", attachments: [], onSent: null, cold: false, tokens: null });
    sendDelayNote("released", why);
    // Отправлено — взлёт/волна вида (off: узла счёта не было, взлёта нет).
    sendDelayLaunch(Boolean(cold));
    sendDelayHide();
    // Финальный звук — только когда счёт был (off отпускает сразу и молча).
    if (why !== "off") sendDelayBeep("done");
    try {
      editor.dispatchEvent(new KeyboardEvent("keydown", {
        key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true, cancelable: true, composed: true,
      }));
    } catch {}
    // Поле держит ровно отложенный текст — значит, Claude Enter не принял.
    const stuck = () => sameTarget() && composerFilled(editor) && rawText(editor) === text && sendDelaySameAttachments(attachments);
    sendDelayLater(() => {
      if (token !== s.token || !state.alive || !sameTarget()) return;
      if (!stuck()) { if (!composerFilled(editor) && !sendDelayAttachments().length) sent("enter"); return; }
      let send = null;
      try { send = document.querySelector(`${SEND_SELECTOR}:not([disabled])`); } catch {}
      if (send && send.disabled !== true) pressLikeMouse(send);
      sendDelayLater(() => {
        if (token !== s.token || !state.alive || !sameTarget()) return;
        if (!stuck()) { if (!composerFilled(editor) && !sendDelayAttachments().length) sent("button"); return; }
        sendDelayNote("failed", send ? "button" : "no-send");
        s.bypassUntil = Date.now() + SEND_DELAY_BYPASS_MS;
        sendDelayShow(SEND_DELAY_FAIL_TEXT);
        sendDelayLater(() => { if (token === s.token) sendDelayHide(); }, SEND_DELAY_NOTE_MS);
      }, SEND_DELAY_CHECK_MS);
    }, SEND_DELAY_CHECK_MS);
  };
  const sendDelayTick = token => {
    const s = sendDelayState;
    if (!s.counting || token !== s.token) return;
    if (sendDelaySettingChanged()) { sendDelayStop("cancelled", "setting"); return; }
    const lost = sendDelayLost();
    if (lost) {
      sendDelayStop("dropped", lost);
      // Плашка просто пропала бы — Элвис решил бы, что ушло (проверка WF105).
      if (lost !== "gone") {
        sendDelayShow(lost === "chat" ? SEND_DELAY_DROP_CHAT_TEXT : SEND_DELAY_DROP_TEXT);
        const shown = s.token;
        sendDelayLater(() => { if (shown === s.token) sendDelayHide(); }, SEND_DELAY_NOTE_MS);
      }
      return;
    }
    if (rawText(s.editor) !== s.text || !sendDelaySameAttachments(s.attachments)) { sendDelayStop("cancelled", "edit"); return; }
    s.left -= 1;
    if (s.left > 0) {
      sendDelayPaint();
      sendDelayBeep("step");
      sendDelayLater(() => sendDelayTick(token), SEND_DELAY_TICK_MS);
      return;
    }
    sendDelayRelease();
  };
  // Показ: свой флаг и свой жетон, N→1 без отправки. Идёт настоящий счёт —
  // показа нет; новый показ сменяет старый. Кнопки нет — плашкой над полем.
  const sendLookPreviewPaint = () => {
    const left = sendLookPreview.left;
    if (sendDelayShowDigits(left, false)) { try { sendDelayNode?.style.setProperty("display", "none"); } catch {} }
    else sendDelayShow(`Показ: отправка через ${left} · Esc — стоп`);
  };
  const sendLookPreviewStop = () => {
    const v = sendLookPreview;
    if (!v.on) return false;
    v.on = false;
    v.token += 1;
    sendDelayHide();
    return true;
  };
  const sendLookPreviewTick = token => {
    const v = sendLookPreview;
    if (!v.on || token !== v.token) return;
    if (sendDelayState.counting || !state.alive || myChatId() !== v.chat || state.editor !== v.editor ||
      (v.editor && !v.editor.isConnected) ||
      rawText(v.editor) !== v.text || !sendDelaySameAttachments(v.attachments)) { sendLookPreviewStop(); return; }
    v.left -= 1;
    if (v.left > 0) {
      sendLookPreviewPaint();
      sendDelayBeep("step");
      sendDelayLater(() => sendLookPreviewTick(token), SEND_DELAY_TICK_MS);
      return;
    }
    v.on = false;
    v.token += 1;
    // Показ кончается как настоящий счёт — взлётом выбранного вида.
    sendDelayLaunch(false);
    sendDelayHide();
    // Показ слышен как настоящий счёт — по нему выбирают звук.
    sendDelayBeep("done");
  };
  const sendLookPreviewStart = (seconds = sendDelaySetting().seconds) => {
    const v = sendLookPreview;
    if (sendDelayState.counting) return false;
    v.token += 1;
    const token = v.token;
    sendLookTotal = seconds;
    Object.assign(v, { on: true, left: seconds, chat: myChatId(), editor: state.editor, text: rawText(state.editor), attachments: sendDelayAttachments() });
    v.shown += 1;
    sendDelayHide();
    sendLookPreviewPaint();
    sendDelayBeep("step");
    sendDelayLater(() => sendLookPreviewTick(token), SEND_DELAY_TICK_MS);
    return true;
  };
  // Команда send-look (WF114): выбор — в localStorage всем окнам; показ — только
  // адресованному: match/chat — по ним, без них — главное окно (Пимп шлёт её,
  // когда фокус у панели, и hasFocus тут не годится).
  const runSendLookCommand = detail => {
    if (!themable || !detail || typeof detail !== "object") return false;
    if ("style" in detail && !SEND_LOOK_STYLES.includes(detail.style)) return false;
    // Недостающее поле остаётся прежним: показ не сбрасывает размер.
    sendLook = sendLookOk({
      style: "style" in detail ? detail.style : sendLook.style,
      size: "size" in detail ? detail.size : sendLook.size,
    });
    try { localStorage.setItem(SEND_LOOK_KEY, JSON.stringify(sendLook)); } catch {}
    if (detail.preview !== true) return true;
    if ("seconds" in detail && !sendDelaySecondsOk(detail.seconds)) return false;
    const mine = typeof detail.match === "string" || typeof detail.chat === "string" ? addressed(detail) : isMainWindow();
    if (mine) sendLookPreviewStart(detail.seconds ?? sendDelaySetting().seconds);
    return true;
  };
  // Выбор из другого окна — сразу и здесь: узел счёта соберётся заново на следующем кадре.
  const onSendLookStorage = event => {
    if (!themable || (event?.key !== SEND_LOOK_KEY && event?.key !== SEND_LOOK_V1_KEY && event?.key !== null)) return;
    sendLook = readSendLook();
  };
  const sendDelaySettingChanged = () => {
    const current = sendDelaySetting();
    const saved = sendDelayState.setting;
    return saved != null && (current.on !== saved.on || current.seconds !== saved.seconds);
  };
  const runSendDelayCommand = detail => {
    const timing = typeof detail?.on === "boolean" && sendDelaySecondsOk(detail?.seconds);
    const second = SEND_DELAY_SECOND_VALUES.includes(detail?.second) ? detail.second : null;
    const shift = SEND_DELAY_SHIFT_VALUES.includes(detail?.shift) ? detail.shift : null;
    const sound = SEND_DELAY_SOUND_VALUES.includes(detail?.sound) ? detail.sound : null;
    if (!themable || (!timing && !second && !shift && !sound)) return false;
    try {
      if (timing) {
        localStorage.setItem(SEND_DELAY_SECONDS_KEY, String(detail.seconds));
        if (detail.on) localStorage.removeItem(SEND_DELAY_OFF_KEY);
        else localStorage.setItem(SEND_DELAY_OFF_KEY, "1");
      }
      if (second) localStorage.setItem(SEND_DELAY_SECOND_KEY, second);
      if (shift === "send") localStorage.setItem(SEND_DELAY_SHIFT_KEY, "send");
      else if (shift === "newline") localStorage.removeItem(SEND_DELAY_SHIFT_KEY);
      // Звук (WF147): bell — умолчание, ключ снят; остальные пишутся строкой.
      if (sound === "bell") localStorage.removeItem(SEND_DELAY_SOUND_KEY);
      else if (sound) localStorage.setItem(SEND_DELAY_SOUND_KEY, sound);
    } catch {}
    if (sendDelayState.counting && sendDelaySettingChanged()) sendDelayStop("cancelled", "setting");
    return true;
  };
  const sendDelayStart = (editor, onSent = null) => {
    if (shotBlocked()) return;
    sendLookPreviewStop();
    const s = sendDelayState;
    s.token += 1;
    const token = s.token;
    const setting = sendDelaySetting();
    sendLookTotal = setting.seconds;
    Object.assign(s, { counting: true, left: setting.seconds, setting, chat: myChatId(), editor, text: rawText(editor), attachments: sendDelayAttachments(), onSent, tokens: null });
    if (!setting.on) { sendDelayRelease("off"); return; }
    s.cold = sendDelayCold();
    if (s.cold) sendDelayAskContext(s.chat);
    s.started += 1;
    sendDelayPaint();
    sendDelayBeep("step");
    sendDelayLater(() => sendDelayTick(token), SEND_DELAY_TICK_MS);
  };
  // Enter (захват document, первым). Условие «чужое — мимо» — `isTrusted !== true`.
  const onSendDelayKey = event => {
    try {
      if (event?.isTrusted !== true || event.key !== "Enter") return;
      const s = sendDelayState;
      // ⌘↩/⌥↩ — перенос строки в поле, и во время счёта тоже (правка поля гасит счёт, как любая); IME — мимо.
      if (sendDelayNewlineCombo(event) && !event.isComposing && event.keyCode !== 229) {
        const field = s.counting && s.editor?.contains?.(event.target) ? s.editor : state.editor;
        if (field?.isConnected && field.contains(event.target)) { sendDelayNewline(event, field); return; }
      }
      // ⌃↩ (с чем угодно) — как Enter: через отсчёт, мимо него не отправляет.
      const shift = event.shiftKey && !event.ctrlKey;
      if (!shift && !event.isComposing && state.editor?.contains(event.target) && shotBlocked()) {
        event.preventDefault(); event.stopImmediatePropagation(); return;
      }
      if (s.counting) {
        // Повторный Enter в поле — по настройке, умолчание «отмена» (#8917; до того — «ничего» #8773, «сразу» #8338,
        // отмена #8149, «ничего» WF106);
        // автоповтор зажатой клавиши — тоже. Меню подсказок успело открыться — Enter его, счёт гаснет.
        // С модификаторами и в IME — мимо, счёт тоже идёт.
        if (event.repeat === true) { event.preventDefault(); event.stopImmediatePropagation(); return; }
        // Shift+Enter во время счёта — отправить сразу (#8114, слово Элвиса 29.09: «Enter… второй раз не
        // делает отправку. Вот Shift+Enter пусть делает»). Без счёта Shift+Enter — перенос строки, как всегда.
        // Выбор «новая строка» (WF126) — мимо: Enter уходит к редактору, правка поля гасит счёт.
        if (shift && sendDelayShift() === "send" && !event.altKey && !event.metaKey && !event.isComposing &&
          event.keyCode !== 229 && s.editor?.contains?.(event.target) && !sendDelayMenuOpen(s.editor)) {
          event.preventDefault();
          event.stopImmediatePropagation();
          sendDelayNote("immediate", "shift-enter");
          sendDelayRelease();
          return;
        }
        if (shift || event.isComposing || event.keyCode === 229 || !s.editor?.contains?.(event.target)) return;
        if (sendDelayMenuOpen(s.editor)) { sendDelayStop("cancelled", "menu"); return; }
        // Второй Enter — по настройке (#8917): отмена (умолчание), сразу или ничего (#8773).
        event.preventDefault();
        event.stopImmediatePropagation();
        const second = sendDelaySecond();
        if (second === "cancel") sendDelayStop("cancelled", "enter");
        else if (second === "send") { sendDelayNote("immediate", "enter"); sendDelayRelease(); }
        return;
      }
      if (shift || event.isComposing || event.keyCode === 229) return;
      if (s.bypassUntil && Date.now() < s.bypassUntil) { s.bypassUntil = 0; sendDelayHide(); return; }
      const editor = state.editor;
      if (!editor?.isConnected || !editor.contains(event.target)) return;
      if (!composerFilled(editor) || sendDelayMenuOpen(editor) || roamState.phase !== "idle" || sendDelayOff()) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      sendDelayStart(editor);
    } catch {}
  };
  // Esc — ветка onKeyDown (захват window): true — Esc наш, счёт отменён.
  const onSendDelayEsc = event => {
    if (event?.key !== "Escape" || event.isTrusted !== true) return false;
    // Показ вида (WF114) — Esc его гасит и глушится; без показа и счёта — Claude, как было.
    if (shotState.pending) {
      for (const job of shotState.jobs) shotCancel(job);
      shotBusyEnd();
      return true;
    }
    if (!sendDelayState.counting) return sendLookPreviewStop();
    sendDelayStop("cancelled", "esc");
    return true;
  };
  // Нажатие (захват document; pointerdown/mousedown/pointerup/mouseup/click): по
  // плашке или цифрам — отмена; по кнопке отправки — глушится целиком, Claude
  // его не видит: во время счёта click — отмена, без счёта при непустом поле
  // click — начало счёта, как Enter. Синтетика (pressLikeMouse, send-text
  // Пимпа) — мимо по isTrusted. После «Не ушло» кнопка, как Enter, — сразу.
  const onSendDelayPress = event => {
    try {
      if (event?.isTrusted !== true) return;
      const target = event.target;
      const s = sendDelayState;
      if (sendDelayOurs(target)) {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (s.counting) sendDelayStop("cancelled", "plate");
        else if (!sendLookPreviewStop()) sendDelayHide();
        return;
      }
      if (!target?.closest?.(SEND_SELECTOR)) return;
      if (shotBlocked()) { event.preventDefault(); event.stopImmediatePropagation(); return; }
      if (sendLookPreview.on) {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (event.type === "click") sendLookPreviewStop();
        return;
      }
      if (s.counting) {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (event.type === "click") sendDelayStop("cancelled", "button");
        return;
      }
      if (s.bypassUntil && Date.now() < s.bypassUntil) {
        if (event.type === "click") { s.bypassUntil = 0; sendDelayHide(); }
        return;
      }
      const editor = state.editor;
      if (!editor?.isConnected || !composerFilled(editor) || sendDelayMenuOpen(editor) || roamState.phase !== "idle" || sendDelayOff()) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      if (event.type === "click") sendDelayStart(editor);
    } catch {}
  };
  // Правка поля во время счёта — отмена (текст остаётся, как Элвис его правит).
  const onSendDelayInput = event => {
    if (event?.isTrusted !== true) return;
    // Правка поля гасит и показ вида (WF114); ввод не глушится.
    if (sendLookPreview.on && state.editor?.contains?.(event.target)) sendLookPreviewStop();
    if (!sendDelayState.counting) return;
    if (sendDelayState.editor?.contains?.(event.target)) sendDelayStop("cancelled", "edit");
  };
  track(() => {
    sendDelayState.token += 1;
    sendDelayState.counting = false;
    sendDelayState.editor = null;
    sendLookPreview.token += 1;
    sendLookPreview.on = false;
    for (const timer of sendDelayTimers) clearTimeout(timer);
    sendDelayTimers.clear();
    try { sendDelayNode?.remove(); } catch {}
    try { sendDelayDigits?.remove(); } catch {}
    try { sendDelayRocket?.remove(); } catch {}
    sendDelayGhostsDrop();
    sendDelayNode = null;
    sendDelayDigits = null;
    sendDelayRocket = null;
    sendDelayParts = null;
    try { sendDelaySoundState.ctx?.close?.()?.catch?.(() => {}); } catch {}
    sendDelaySoundState.ctx = null;
  });
  // Отсрочка отправки (раздел 12у, WF105): идёт ли счёт и чем кончались прошлые.
  statusPart("sendDelay", () => ({
    off: sendDelayOff(), seconds: sendDelaySetting().seconds, second: sendDelaySecond(), shift: sendDelayShift(), counting: sendDelayState.counting, left: sendDelayState.left, started: sendDelayState.started,
    cancelled: sendDelayState.cancelled, immediate: sendDelayState.immediate, dropped: sendDelayState.dropped,
    released: sendDelayState.released, sent: sendDelayState.sent, failed: sendDelayState.failed,
    last: sendDelayState.last ? { ...sendDelayState.last } : null,
    cold: sendDelayState.cold, tokens: sendDelayState.tokens, asks: sendDelayState.asks, newlines: sendDelayState.newlines,
    // Вид и размер счёта (WF114); preview — идёт ли показ вида.
    look: { style: sendLook.style, size: sendLook.size, preview: sendLookPreview.on },
    // Звук отсчёта (WF147): выбранный id, сколько прозвучало, последний (id, kind), сбои синтеза.
    sound: { id: sendDelaySound(), played: sendDelaySoundState.played, last: sendDelaySoundState.last ? { ...sendDelaySoundState.last } : null, failed: sendDelaySoundState.failed },
  }));
  HATCH && Object.assign(HATCH, { SEND_DELAY_FLY_MS, SEND_DELAY_TRAIL_FADE_MS, SEND_DELAY_FADE_MS });

