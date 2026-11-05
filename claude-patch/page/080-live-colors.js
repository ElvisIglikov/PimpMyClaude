  // ---- 2в. Живые цвета ----------------------------------------------------
  // Окна плавно едут по цветовому кругу. Приложение шлёт ОДНУ команду
  // live-colors на все окна разом, дальше каждое окно считает свой цвет само.
  // Крутить цвет командами из Swift нельзя: канал (command.json) держит зазор
  // 0,6 с между записями, а лоадер раз в 500 мс берёт из файла только ПОСЛЕДНЮЮ
  // запись — на «плавненько» этого не хватит, зато очередь меню и сводки такой
  // поток задушил бы.
  //
  // Цвет считается ОТ СТЕННЫХ ЧАСОВ, а не накоплением тиков. Отсюда два
  // свойства даром: epoch и period у всех окон одни, поэтому в режиме «все одним
  // цветом» окна сходятся сами, без единого байта между ними; а придушенное
  // фоновое окно (Electron режет таймеры перекрытых окон до 1 Гц) после
  // пробуждения оказывается на правильном цвете, а не отстаёт на всё время сна.
  //
  // Палитры страница не считает: их присылает приложение кольцом опорных точек
  // из того же генератора, что и «Раскрасить по кругу» (AutoPaint с его
  // подтяжкой контраста), а страница между соседними точками смешивает цвета
  // покомпонентно. Вторая копия формул контраста в JS через месяц разъехалась бы
  // со Swift.
  //
  // Хранилища тем живые цвета не касаются вовсе: идут через applyTheme(…, "live")
  // мимо writeLayers. Выключили — restoreTheme поднял тему чата/окна по обычному
  // приоритету, как будто ничего не было. Своё состояние (кольцо, скорость,
  // режим) лежит отдельным ключом в localStorage: он у окон Claude общий, и
  // окно, открытое во время крутёжа, подхватывает цвет само, без команды —
  // в том числе когда приложение уже не запущено.
  const LIVE_KEY = "myclaude-live-v1";
  const LIVE_PHASE_KEY = "myclaude-live-phase-v1";
  // Круг за минуту — предел снизу: при тике 500 мс это 3° за шаг, быстрее уже
  // не «цвет едет», а мигание. Медленнее часа — цвет стоит на месте.
  const LIVE_PERIOD_MIN = 60;
  const LIVE_PERIOD_MAX = 3600;
  const LIVE_PERIOD_DEFAULT = 300;
  // Шаг по кругу и потолок частоты. Тик считается ОТ СКОРОСТИ, от 500 мс до
  // секунды, шаг ≤ 3°. Чаще 500 мс нельзя — каждый тик это ≈200 строк CSS и
  // полный пересчёт стилей окна (гейт WF18); реже — видны ступени.
  const LIVE_STEP_DEG = 1.5;
  const LIVE_TICK_MIN_MS = 500; // гейт WF18: при 250 мс (круг за минуту) рендереры +100–160 % CPU, при 500 — вдвое легче; шаг ≤ 3°
  const LIVE_TICK_MAX_MS = 1000;
  // Полоса прогресса берёт акцент один раз при отрисовке и за темой сама не
  // едет (её пульс — 10 с), то есть рядом с уехавшим окном держала бы старый
  // цвет. Зовём её перекраску на ГРУБОМ шаге: раз в 30° глазу не отличить от
  // непрерывной, а обмер низа окна четыре раза в секунду не нужен никому.
  const LIVE_COARSE_DEG = 30;
  // Кольцо приходит снаружи: три точки — уже круг, больше семи десятков не
  // бывает и разбирать незачем.
  const LIVE_RING_MIN = 3;
  const LIVE_RING_MAX = 72;

  const liveState = {
    on: false, mode: "sync", period: LIVE_PERIOD_DEFAULT, epoch: 0, light: null,
    useLight: false, ring: null, phase: 0, phased: false, hue: null, coarse: null,
    timer: 0, source: null, paints: 0,
  };

  // Устойчивый хэш заголовка (FNV-1a) — запасной способ развести окна по кругу,
  // когда окна нет в присланном списке (открылось позже). Одно и то же имя
  // всегда даёт одну и ту же точку круга.
  const liveHash = text => {
    let hash = 2166136261;
    for (let index = 0; index < text.length; index += 1) {
      hash = Math.imul(hash ^ text.charCodeAt(index), 16777619) >>> 0;
    }
    return hash;
  };
  // Сдвиг окна по кругу в режиме «каждое своим цветом»: место в списке окон
  // (слева направо, как у «Расставить») делит круг поровну. Окна с одинаковым
  // заголовком получат одну фазу — ровно как в автопокраске, где адресация тоже
  // по заголовку.
  const livePhaseFor = titles => {
    const title = windowTitle();
    const list = Array.isArray(titles) ? titles.filter(item => typeof item === "string") : [];
    const index = list.indexOf(title);
    if (list.length > 0 && index >= 0) return (360 * index) / list.length;
    return liveHash(title) % 360;
  };
  const liveReadPhase = () => {
    try {
      const raw = sessionStorage.getItem(LIVE_PHASE_KEY);
      if (raw == null) return null;
      const record = JSON.parse(raw);
      // Окно «Open in new window» стартует с КОПИЕЙ sessionStorage главного окна
      // (см. readSessionEntry): без сверки ключа попап взял бы его фазу и сел
      // на ту же точку круга.
      if (!record || typeof record !== "object" || record.key !== sessionKey()) return null;
      const phase = Number(record.phase);
      return Number.isFinite(phase) ? ((phase % 360) + 360) % 360 : null;
    } catch { return null; }
  };
  const liveWritePhase = phase => {
    const key = sessionKey();
    if (!key) return;
    try { sessionStorage.setItem(LIVE_PHASE_KEY, JSON.stringify({ key, phase })); } catch {}
  };
  // Фаза защёлкивается ОДИН раз на жизнь окна и дальше от заголовка не зависит:
  // у главного окна заголовок меняется на каждом чате (watchChatTitle), и
  // считай мы фазу каждый раз заново — окно перескакивало бы на другую точку
  // круга при каждой смене разговора. Список titles задаёт только начальное
  // распределение. Ключа сессии может ещё не быть (about:blank без заголовка) —
  // тогда фаза живёт в памяти окна, а на диск ляжет при следующем случае.
  //
  // Но защёлкивать НЕ ПО ЧЕМУ, пока имени у окна нет: попап («Новое окно») в
  // первые мгновения сидит на about:blank без заголовка, а безымянный чат носит
  // заглушку («Claude», «New chat») — по такому имени и хэш, и место в списке у
  // ВСЕХ окон одинаковые. Заперлись бы на нём — окна, открытые во время
  // крутёжа, поехали бы одним цветом навсегда, и меню это уже не чинило бы.
  // Поэтому фаза от ненастоящего имени временная: красим ею, но замок не ставим
  // (livePaint пересчитает, как только заголовок появится) и на диск не пишем.
  // Присланный список окон авторитетнее памяти окна и сильнее замка: нашли себя
  // в нём — считаем фазу заново даже при phased, иначе повторное «каждое окно
  // своим цветом» не развело бы окна, слипшиеся по заглушке.
  const liveLatchPhase = titles => {
    const title = windowTitle();
    const real = title !== "" && !THEME_TITLE_STUBS.has(title.toLowerCase());
    const listed = real && Array.isArray(titles) && titles.indexOf(title) >= 0;
    if (liveState.phased && !listed) { liveWritePhase(liveState.phase); return; }
    liveState.phase = (listed ? null : liveReadPhase()) ?? livePhaseFor(titles);
    // Место в списке бывает только у настоящего имени, поэтому «фаза
    // авторитетная ИЛИ имя настоящее» и сводится к одному условию.
    liveState.phased = real;
    if (real) liveWritePhase(liveState.phase);
  };

  // Кольцо — текст снаружи, за который мы не отвечаем: палитра только из шести
  // известных цветов и только hex. Шаг по кругу берём из самой длины кольца
  // (12 точек — 30°), чтобы приложение могло сгустить кольцо, не трогая страницу.
  const liveRing = (list, type) => {
    if (!Array.isArray(list) || list.length < LIVE_RING_MIN) return null;
    const base = THEME_FALLBACK[type];
    const ring = [];
    for (const item of list.slice(0, LIVE_RING_MAX)) {
      if (!item || typeof item !== "object" || Array.isArray(item)) return null;
      const stop = {};
      for (const key of THEME_PALETTE_KEYS) stop[key] = normalizeHex(item[key], base[key]);
      ring.push(stop);
    }
    return ring;
  };
  // Разбор команды и записи из хранилища — один и тот же: в localStorage лежит
  // ровно то, что пришло командой. Кольца нет вовсе — крутить нечем.
  const liveConfig = raw => {
    if (!raw || typeof raw !== "object") return null;
    const rings = raw.ring && typeof raw.ring === "object" ? raw.ring : {};
    const dark = liveRing(rings.dark, "dark");
    const light = liveRing(rings.light, "light");
    if (!dark && !light) return null;
    const period = Number(raw.period);
    const epoch = Number(raw.epoch);
    return {
      mode: raw.mode === "solo" ? "solo" : "sync",
      period: Number.isFinite(period)
        ? Math.min(LIVE_PERIOD_MAX, Math.max(LIVE_PERIOD_MIN, Math.round(period)))
        : LIVE_PERIOD_DEFAULT,
      // Часы окна и часы приложения — одни и те же; epoch не наш, но и не чужой.
      epoch: Number.isFinite(epoch) ? epoch : Date.now(),
      light: raw.light === true ? true : (raw.light === false ? false : null),
      ring: { dark: dark ?? light, light: light ?? dark },
    };
  };
  const liveRead = () => {
    try {
      const raw = JSON.parse(localStorage.getItem(LIVE_KEY) ?? "null");
      return raw?.on === true ? liveConfig(raw) : null;
    } catch { return null; }
  };
  const liveWrite = config => {
    try {
      if (!config) localStorage.removeItem(LIVE_KEY);
      else localStorage.setItem(LIVE_KEY, JSON.stringify({ on: true, ...config }));
    } catch {}
  };

  const liveHue = () => {
    const turns = (Date.now() - liveState.epoch) / (liveState.period * 1000);
    // В режиме «все одним цветом» фаза не участвует вовсе, но защёлкнутое
    // значение сохраняется: переключили режим — окно встало на свою точку круга,
    // а не пересчитало её заново.
    const phase = liveState.mode === "solo" ? liveState.phase : 0;
    return (((turns * 360 + phase) % 360) + 360) % 360;
  };
  // Между опорными точками кольца — прямая в sRGB, покомпонентно (mixHex,
  // раздел 2а). На шаге в 30° контраст промежуточных цветов лежит между
  // контрастами соседей, и глазу это заметно не больше самой смены цвета.
  const livePalette = (ring, hue) => {
    const place = hue / (360 / ring.length);
    const first = Math.floor(place) % ring.length;
    const second = (first + 1) % ring.length;
    const ratio = place - Math.floor(place);
    const palette = {};
    for (const key of THEME_PALETTE_KEYS) palette[key] = mixHex(ring[first][key], ring[second][key], ratio);
    return palette;
  };
  const livePaint = () => {
    if (!liveState.on) return;
    const ring = liveState.useLight ? liveState.ring?.light : liveState.ring?.dark;
    if (!ring || ring.length === 0) return;
    // Замка ещё нет — окно красится временной фазой (при первом мазке имени не
    // было). Пробуем на каждом мазке: заголовок появился — фаза села сама, новой
    // команды из меню для этого не нужно.
    if (!liveState.phased) liveLatchPhase(null);
    const hue = liveHue();
    const type = liveState.useLight ? "light" : "dark";
    // id виден в status().theme.id — на гейте по нему сразу читается, где окно
    // на круге и живой ли это слой вообще.
    const applied = applyTheme({
      id: `live-${type}-${Math.round(hue)}`, name: "Живые цвета", type,
      palette: livePalette(ring, hue),
    }, "live");
    if (!applied) return;
    liveState.hue = hue;
    liveState.paints += 1;
    const coarse = Math.floor(hue / LIVE_COARSE_DEG);
    if (coarse !== liveState.coarse) {
      liveState.coarse = coarse;
      try { placeProgress(); } catch {}
    }
  };
  // evenHidden — первый мазок (команда, подъём из памяти): его пускаем и в
  // спрятанное окно, чтобы к показу цвет был уже верный, но примерку темы он,
  // как и обычный тик, не трогает.
  const liveTick = evenHidden => {
    if (!liveState.on || !state.alive) return;
    // Предпросмотр сильнее: мышь ведут по подменю тем, и затирать примерку через
    // четверть секунды нельзя. Меню закрылось — крутёж продолжился сам.
    if (themeState.previewing) return;
    // Окна не видно — цвет не крутим (батарея). Догонит одним шагом, когда
    // вернётся: цвет считается от часов, а не копится тиками.
    if (document.hidden && !evenHidden) return;
    livePaint();
  };
  const liveInterval = () => Math.round(Math.min(LIVE_TICK_MAX_MS,
    Math.max(LIVE_TICK_MIN_MS, (liveState.period * 1000 * LIVE_STEP_DEG) / 360)));
  const liveStopTimer = () => {
    if (liveState.timer) { clearInterval(liveState.timer); liveState.timer = 0; }
  };
  // Снятие экземпляра (новый инжект по mtime) обязано погасить интервал: иначе в
  // окне крутили бы цвет два таймера сразу.
  track(liveStopTimer);
  const liveStop = restore => {
    liveStopTimer();
    const was = liveState.on;
    liveState.on = false;
    liveState.hue = null;
    liveState.coarse = null;
    liveState.source = null;
    if (!was || !restore) return;
    // Выключение — это ровно «вернуть прежнее»: слой темы поднимается из
    // хранилища по обычному приоритету (чат → сессия → окно → всем), а нет
    // записи нигде — снимается вовсе. Своей ветки отката у живых цветов нет,
    // потому что и запоминать было нечего.
    try { restoreTheme(true, ["theme"]); } catch {}
    try { placeProgress(); } catch {}
  };
  const liveRun = (config, source) => {
    liveStopTimer();
    liveState.on = true;
    liveState.mode = config.mode;
    liveState.period = config.period;
    liveState.epoch = config.epoch;
    liveState.light = config.light;
    // «Как окно сейчас» решается ОДИН раз, на приёме команды: дальше на экране
    // уже живая тема, и спрашивать её тип — спрашивать самих себя.
    liveState.useLight = config.light === null ? themeState.theme?.type === "light" : config.light;
    liveState.ring = config.ring;
    liveState.source = source;
    liveState.coarse = null;
    liveTick(true);
    liveState.timer = setInterval(() => { try { liveTick(); } catch {} }, liveInterval());
  };

  // Контракт WF18: {id, action:"live-colors", at, scope:"all", on, mode, period,
  // epoch, light, titles, ring:{dark,light}}. Выключение — {scope, on:false}, и
  // больше в нём полей нет. Команда одна на все окна, адресации по заголовку у
  // неё нет: своё окно каждая страница отбирает сама (themable).
  const runLiveCommand = detail => {
    if (!themable || !detail || typeof detail !== "object") return false;
    if (detail.on !== true) { liveWrite(null); liveStop(true); return true; }
    const config = liveConfig(detail);
    if (!config) return false;
    liveWrite(config);
    liveLatchPhase(detail.titles);
    liveRun(config, "command");
    return true;
  };
  // Окно, открытое во время крутёжа, поднимает его само: команды ему ждать
  // неоткуда — приложение шлёт её один раз, на нажатие в меню.
  const liveRestore = () => {
    if (!themable) return;
    const config = liveRead();
    if (!config) return;
    liveLatchPhase(null);
    liveRun(config, "storage");
  };
  // Догоняем цвет, как только окно снова видно: тик всё это время молчал.
  on(document, "visibilitychange", () => { try { liveTick(); } catch {} });
  // Осечка живых цветов не должна утащить за собой ручку и полоску — как и у
  // восстановления темы выше.
  try { liveRestore(); } catch {}
  // Живые цвета (раздел 2в): крутится ли круг, в каком режиме и с какой
  // скоростью, где на круге стоит окно (phase — его защёлкнутый сдвиг,
  // hue — тон прямо сейчас), из скольких точек кольцо, сколько раз окно
  // перекрашено и откуда взялся крутёж — из команды или из памяти окон.
  statusPart("live", () => ({
    on: liveState.on,
    mode: liveState.mode,
    period: liveState.period,
    light: liveState.on ? liveState.useLight : null,
    phase: Math.round(liveState.phase * 10) / 10,
    hue: liveState.hue == null ? null : Math.round(liveState.hue * 10) / 10,
    ring: liveState.ring?.dark?.length ?? 0,
    paints: liveState.paints,
    source: liveState.source,
  }));

