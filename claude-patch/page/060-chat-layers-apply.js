  // ---- 2а, продолжение. Покой живого фона, применение слоёв и команды тем ----
  // «Уменьшить движение» в macOS (стоит на Маке коллеги, замер 08.10 — живой фон из-за
  // него и «не шевелился»): Claude при нём ужимает любую CSS-анимацию до 1e-5 с и
  // одного раза правилом, которого страница не видит в CSSOM и не пересилит. Тогда
  // переливание крутят Web Animations на тех же псевдоэлементах (композитор, без
  // JS-кадров) теми же кадрами, что CSS: пятна плывут и при нём (#9115, слово Элвиса
  // 08.10 22:38: фон совсем не живой, шевелиться должен побыстрее; было — только тон). Узлы
  // сверяет и тик сердца: React может пересоздать панель ленты попапа.
  const auroraCalm = { hosts: [], anims: [], layers: LOOK_AURORA };
  // Живой фон стоит: окно скрыто или дольше LOOK_IDLE_MS без фокуса.
  const LOOK_IDLE_MS = 20000;
  const lookIdle = { timer: 0, still: false };
  const lookStill = () => Boolean(document.hidden || lookIdle.still);
  // Живой фон движется только при motion "live" (#9994): у «стоит» и «картинки» ни кадров, ни отсчёта.
  const lookMoving = () => themeState.look?.aurora === true && lookMotion(themeState.look) === "live";
  const auroraCalmStop = () => {
    for (const anim of auroraCalm.anims) { try { anim.cancel(); } catch {} }
    auroraCalm.anims = [];
    auroraCalm.hosts = [];
  };
  const auroraCalmSync = () => {
    let reduce = false;
    // Стоит и картинка (#9994) — Web Animations не заводим, прежние отменяет auroraCalmStop.
    if (lookMoving()) { try { reduce = matchMedia("(prefers-reduced-motion: reduce)").matches; } catch {} }
    // Анимация, заведённая до появления псевдоэлемента (таблица ещё не принята),
    // к нему потом не цепляется (живьём 08.10) — узел без него ждёт следующего тика.
    const hosts = reduce
      ? [...document.querySelectorAll(".dframe-root, .epitaxy-chat-panel")].filter(node => node.matches(".dframe-root") || !node.closest(".dframe-root"))
      : [];
    // Слои — по теме окна (#9683): сменилась тема с тихим рисунком — кадры заводятся заново.
    const layers = lookLayers(lookGlow());
    if (layers !== auroraCalm.layers || hosts.length !== auroraCalm.hosts.length || hosts.some((node, index) => node !== auroraCalm.hosts[index])) {
      auroraCalmStop();
      auroraCalm.layers = layers;
      for (const host of hosts) {
        try { if (getComputedStyle(host, "::before").content === "none") continue; } catch { continue; }
        for (const item of layers) {
          try { auroraCalm.anims.push(host.animate(lookAuroraFrames(item), { duration: item.ms, delay: item.delay, iterations: Infinity, direction: "alternate", pseudoElement: item.pseudo })); } catch {}
        }
        auroraCalm.hosts.push(host);
      }
    }
    // Скрытое окно и окно, давно оставшееся без фокуса, — стоят и они.
    const still = lookStill();
    for (const anim of auroraCalm.anims) {
      try {
        if (still && anim.playState === "running") anim.pause();
        else if (!still && anim.playState === "paused") anim.play();
      } catch {}
    }
  };
  track(auroraCalmStop);
  // Скрытое окно — живой фон стоит (К3): композитор не крутит кадры впустую.
  // WF241: стоит он и в окне, которое дольше LOOK_IDLE_MS без фокуса — у Элвиса открыто несколько окон
  // Claude разом, и каждое переливалось, пока он работал в одном. Вернулся фокус — идёт дальше с того
  // же места; отсчёт заводится только при живом фоне.
  const lookStillSync = () => {
    try {
      if (lookStill()) document.documentElement.setAttribute(LOOK_STILL_ATTRIBUTE, "");
      else document.documentElement.removeAttribute(LOOK_STILL_ATTRIBUTE);
    } catch {}
    auroraCalmSync();
  };
  const lookFocusSync = () => {
    let focused = true;
    try { focused = document.hasFocus(); } catch {}
    if (focused || !lookMoving()) {
      if (lookIdle.timer) { clearTimeout(lookIdle.timer); lookIdle.timer = 0; }
      if (lookIdle.still) { lookIdle.still = false; lookStillSync(); }
      return;
    }
    if (lookIdle.timer || lookIdle.still) return;
    lookIdle.timer = setTimeout(() => {
      lookIdle.timer = 0;
      let back = false;
      try { back = document.hasFocus(); } catch {}
      if (back || !state.alive) return;
      lookIdle.still = true;
      lookStillSync();
    }, LOOK_IDLE_MS);
  };
  lookStillSync();
  on(document, "visibilitychange", lookStillSync);
  on(window, "blur", lookFocusSync);
  on(window, "focus", lookFocusSync);
  track(() => {
    if (lookIdle.timer) { clearTimeout(lookIdle.timer); lookIdle.timer = 0; }
    try { document.documentElement.removeAttribute(LOOK_STILL_ATTRIBUTE); } catch {}
  });
  const removeLook = source => {
    detachSheet(lookSheet);
    try { lookSheet.replaceSync(""); } catch {}
    themeState.look = null;
    themeState.lookSource = source ?? null;
    themeState.lookCss = "";
    lookFocusSync();
    auroraCalmSync();
    try { scrollFadeScan(); } catch {}
  };
  const applyLook = (value, source) => {
    const clean = normalizeLook(value);
    if (!clean || !themable) { removeLook(source); return null; }
    themeState.look = clean;
    themeState.lookSource = source ?? null;
    themeState.lookCss = "";
    paintLook();
    if (!adoptSheet(lookSheet)) return null;
    lookFocusSync();
    auroraCalmSync();
    try { scrollFadeScan(); } catch {}
    return clean;
  };

  const removeTheme = source => {
    detachSheet(themeSheet);
    try { themeSheet.replaceSync(""); } catch {}
    themeState.theme = null;
    themeState.source = source ?? null;
    paintLook();
  };
  const applyTheme = (theme, source) => {
    const clean = normalizeTheme(theme);
    if (!clean) { removeTheme(source); return null; }
    try { themeSheet.replaceSync(themeCss(clean)); } catch { return null; }
    if (!adoptSheet(themeSheet)) return null;
    themeState.theme = clean;
    themeState.source = source ?? null;
    paintLook();
    return clean;
  };
  // Другой шрифт — другая высота строки, а обычная высота поля закэширована
  // (state.natural, раздел 9). Без сброса кэша ручка осталась бы стоять по
  // старому замеру, а поле — прежней высоты.
  const refreshAfterFont = () => {
    state.natural = null;
    try { scheduleLayout(); } catch {}
  };
  const removeFont = source => {
    detachSheet(fontSheet);
    try { fontSheet.replaceSync(""); } catch {}
    themeState.font = null;
    themeState.fontSource = source ?? null;
    refreshAfterFont();
  };
  const applyFont = (font, source) => {
    const clean = normalizeFont(font);
    if (!clean) { removeFont(source); return null; }
    try { fontSheet.replaceSync(fontCss(clean)); } catch { return null; }
    if (!adoptSheet(fontSheet)) return null;
    themeState.font = clean;
    themeState.fontSource = source ?? null;
    refreshAfterFont();
    return clean;
  };
  // Размер поля ввода и ручки не касается — трогает только текст сообщений, —
  // поэтому кэш обычной высоты (state.natural), в отличие от шрифта, не сбрасываем.
  const removeSize = source => {
    detachSheet(sizeSheet);
    try { sizeSheet.replaceSync(""); } catch {}
    themeState.size = null;
    themeState.sizeSource = source ?? null;
  };
  const applySize = (size, source) => {
    const clean = normalizeSize(size);
    if (!clean) { removeSize(source); return null; }
    try { sizeSheet.replaceSync(sizeCss(clean)); } catch { return null; }
    if (!adoptSheet(sizeSheet)) return null;
    themeState.size = clean;
    themeState.sizeSource = source ?? null;
    return clean;
  };
  // «Живой» панели — главный (WF204, решение Элвиса 09.10 02:50; как Swift
  // `ProjectPaint.liveLook` WF200): живой фон и его схема у окна ВСЕГДА из look
  // у `*` (нет его там — фон выключен), а неон и плотность — свои, по обычной
  // цепочке. Без этого сброс окна («🧹 Всё как у Claude» пишет look "none",
  // который сильнее `*`) и старые записи чатов с aurora:false навсегда гасили
  // «Живой» у чата. Одна точка — applyLayer: через неё идут восстановление, смена
  // чата, команда окна и «всем окнам»; примерка показывает ровно то, что примеряют.
  const liveLookOver = value => {
    const all = entryLayer(themeEntry(readThemeMap()[THEME_ALL_KEY]), "look");
    const own = value && typeof value === "object" ? value : {};
    const aurora = all?.aurora === true;
    return normalizeLook({ neon: own.neon, dense: own.dense, aurora, scheme: aurora ? all.scheme : undefined, motion: aurora ? all.motion : undefined });
  };
  // Своя часть look окна — то, что сброс окна вправе перекрыть у `*`.
  const lookOwnPart = look => Boolean(look && (look.neon === true || look.dense === true));
  const applyLayer = (layer, value, source) => {
    if (layer === "font") { if (value) applyFont(value, source); else removeFont(source); return; }
    if (layer === "size") { if (value) applySize(value, source); else removeSize(source); return; }
    if (layer === "look") { applyLook(source === "preview" ? value : liveLookOver(value), source); return; }
    if (value) applyTheme(value, source); else removeTheme(source);
  };
  const applyLayers = (layers, source) => {
    for (const layer of THEME_LAYERS) if (layer in layers) applyLayer(layer, layers[layer], source);
  };

  // Порядок восстановления у КАЖДОГО слоя свой: запись чата (`id:<id>`, а нет её
  // — `chat:<заголовок>`; см. chatEntry) → своя сессия окна → у главного окна
  // запись окна (`main`) → запись «для всех». Чат стоит ПЕРВЫМ нарочно: сессия у
  // окна одна на все разговоры, и
  // стоя выше она перекрывала бы цвет чата, в который окно только что вернулось
  // (разбор критика, п. 2). Тема у окна своя, а шрифт общий — законная пара,
  // поэтому слои и разведены. Явный сброс («none») сильнее следующего уровня и
  // переживает перезапуск. Возвращает true, когда ждать больше нечего (ключ уже
  // известен). clear=true — «конец предпросмотра»: слой, которого в хранилище
  // нет, надо не оставить как есть (на экране сейчас примеренные цвета), а
  // снять. Смена чата сюда не ходит — у неё свой путь, applyChatEntry.
  const restoreTheme = (clear, onlyLayers) => {
    if (!themable) return true;
    const session = readSessionEntry();
    const map = readThemeMap();
    const chat = chatEntry(map);
    // Запись окна берёт только главное окно: у подчинённого своего `main` нет,
    // и чужой он не касается.
    const own = isMainWindow() ? mapEntry(map, THEME_MAIN_KEY) : null;
    const all = themeEntry(map[THEME_ALL_KEY]);
    for (const layer of (onlyLayers ?? THEME_LAYERS)) {
      const fromChat = entryLayer(chat, layer);
      if (fromChat !== undefined) { applyLayer(layer, fromChat, "chat"); continue; }
      const fromSession = entryLayer(session, layer);
      if (fromSession !== undefined) { applyLayer(layer, fromSession, "session"); continue; }
      const fromWindow = entryLayer(own, layer);
      if (fromWindow !== undefined) { applyLayer(layer, fromWindow, "window"); continue; }
      const fromAll = entryLayer(all, layer);
      if (fromAll !== undefined) applyLayer(layer, fromAll, "all");
      else if (clear) applyLayer(layer, null, null);
    }
    return themeKey() != null;
  };

  // То же значение слоя, что взяло бы восстановление, но БЕЗ применения: нужно
  // размеру, у которого половинки независимы, — команда «размер ответов 16» без
  // этого стёрла бы выбранный размер вопросов.
  const storedLayer = layer => {
    if (!themable) return null;
    const map = readThemeMap();
    const chain = [
      chatEntry(map),
      readSessionEntry(),
      isMainWindow() ? mapEntry(map, THEME_MAIN_KEY) : null,
      themeEntry(map[THEME_ALL_KEY]),
    ];
    for (const entry of chain) {
      const value = entryLayer(entry, layer);
      if (value !== undefined) return value;
    }
    return null;
  };

  // Запись по ключу и по слоям. Сброс пишем маркером "none" только когда у ЭТОГО
  // слоя есть запись «для всех» — иначе запись лишняя. Пустая запись не хранится.
  // Основа записи — mapEntry: у ключа чата это может быть старая запись `w:`, и
  // взять её обязательно, иначе перенос потерял бы второй слой.
  const setMapLayers = (map, key, layers) => {
    const entry = mapEntry(map, key) ?? {};
    const all = themeEntry(map[THEME_ALL_KEY]);
    for (const layer of THEME_LAYERS) {
      if (!(layer in layers)) continue;
      if (layers[layer]) entry[layer] = layers[layer];
      // Сброс look перекрывает у `*` лишь неон и плотность: живой фон — всегда от `*` (WF204).
      else if (layer === "look" ? lookOwnPart(entryLayer(all, layer)) : entryLayer(all, layer)) entry[layer] = "none";
      else delete entry[layer];
    }
    if (Object.keys(entry).length) map[key] = { ...keepOwner(entry, map[key]), at: Date.now() }; else delete map[key];
    // Перенос старой записи: всё, что в ней было, уже в entry.
    const legacy = legacyKey(key);
    if (legacy != null) delete map[legacy];
  };

  // Куда пишется выбор «тема этого окна»: запись чата — её увидит любое окно с
  // этим разговором, — и у главного окна ещё и `main`, чтобы окно «в целом»
  // помнило цвет и не теряло его на новом чате. У безымянного чата ключа нет
  // (chatKey отдаёт null на заголовках-заглушках), и выбор ложится только в
  // `main` да в сессию — иначе он достался бы всем безымянным чатам разом.
  // WF35: пока id известен, пишем ОБА ключа чата — id главный, имя остаётся
  // тенью для окон, которые id ещё не знают.
  const writeKeys = () => {
    const keys = [];
    const id = chatIdKey();
    if (id) keys.push(id);
    const title = chatTitleKey();
    if (title) keys.push(title);
    if (isMainWindow()) keys.push(THEME_MAIN_KEY);
    return keys;
  };
  const writeLayers = layers => {
    // Перенос ДО записи обязателен: setMapLayers начинает с mapEntry(map, key),
    // и без переноса запись `id:` родилась бы с одним слоем этой команды.
    migrateChatKey();
    const keys = writeKeys();
    if (keys.length) {
      const map = readThemeMap();
      for (const key of keys) setMapLayers(map, key, layers);
      // Тень теперь этого чата (z1-r01): окно знает id — ставит себя владельцем.
      const id = chatIdKey();
      const title = chatTitleKey();
      if (id && title && map[title] && typeof map[title] === "object") map[title].by = id.slice(THEME_ID_PREFIX.length);
      writeThemeMap(map);
    }
    storeSessionLayers(layers);
  };
  // Выбор сделан до того, как у окна появился заголовок (about:blank сразу после
  // открытия) или пока чат ещё безымянный: записываем, когда ключ чата появится,
  // но не дольше десяти секунд — дальше это уже не «тот самый выбор». Заголовок-
  // заглушка ключом не считается, и ждать под ней нечего — она не запись чата.
  const flushPendingLayers = () => {
    const layers = themeState.pending;
    if (!layers) return;
    if (now() > themeState.pendingUntil) { themeState.pending = null; return; }
    if (!chatKey()) return;
    themeState.pending = null;
    writeLayers(layers);
  };

  const stopChatWatch = () => {
    if (themeState.chatTimer) { clearInterval(themeState.chatTimer); themeState.chatTimer = 0; }
    if (themeState.chatObserver) {
      try { themeState.chatObserver.disconnect(); } catch {}
      themeState.chatObserver = null;
    }
  };
  track(stopChatWatch);
  // Смена чата в главном окне — это смена document.title, больше ничего: страница
  // не перезагружается, инжект заново не приходит. Поэтому за заголовком следим
  // всё время жизни окна и на каждую смену перечитываем хранилище. В подчинённом
  // окне тот же сторож ловит момент, когда заголовок наконец появился.
  //
  // Чат, родившийся в окне (прежнего ключа нет: домашний экран, безымянный чат),
  // берёт ТОЛЬКО свою запись, и только те слои, которые в ней есть. Записи нет —
  // на экране не трогаем ничего: ⌘N и «Обкэшить» открывают чат без записи, и
  // окно обязано остаться того же цвета (слово Элвиса; разбор критика WF9, п. 3).
  //
  // Переход из чата в ДРУГОЙ чат (WF82, #7103) — полный порядок слоёв, как на
  // инжекте: запись чата → сессия окна → `main` → «всем», а слоя нет нигде —
  // снять. Слово Элвиса 22.09: «у двух нижних [закреплённых] тема меняется: пришли
  // из зелёного — зелёная, из „Ночи кода“ — оранжевая… своей темы что ли нет?».
  // Записей у этих чатов не было вовсе (замер WF82: в копии карты у приложения —
  // 121 запись, последняя 23.09 01:27 — их id нет), и правило «не трогать ничего»
  // оставляло им цвет того чата, откуда пришли. Теперь такой чат — в цвете окна, и вид его не
  // зависит от пути. Цвет проекта окну приносит приложение (покраска по проекту,
  // 4–15 с после перехода), и та же команда пишет чату его запись — со второго
  // захода чат сразу в своём цвете. Двойная смена возможна один раз на чат: если
  // окно было в цвете записи прошлого чата, а тема окна и проекта другие.
  // Живые цвета слой темы держат сами — его здесь не трогаем, иначе окно мигало
  // бы до следующего тика круга.
  const applyChatEntry = () => {
    const entry = chatEntry(readThemeMap());
    if (!entry) return;
    for (const layer of THEME_LAYERS) {
      const value = entryLayer(entry, layer);
      if (value !== undefined) applyLayer(layer, value, "chat");
    }
  };
  const syncChatTheme = () => {
    if (!state.alive || !themable) return;
    const key = chatKey();
    touchThemeMap();
    if (key === themeState.chatKey) return;
    // Пока идёт предпросмотр, на экране намеренно не то, что в хранилище: ключ не
    // запоминаем, чтобы смена чата не «съелась» и применилась после конца примерки.
    if (themeState.previewing) return;
    const from = themeState.chatKey;
    themeState.chatKey = key;
    // Сначала дописываем несохранённый выбор: иначе восстановление затрёт на
    // экране только что выбранную тему.
    flushPendingLayers();
    // У попапа id приезжает ПОЗЖЕ инжекта (карту попапов наполняет probe), и без
    // этого вызова перенос записи на `id:` в попапе не случился бы никогда.
    try { migrateChatKey(); } catch {}
    // Из чата в чат — полный порядок слоёв (#7103). Цепочка «Нового окна» (12б)
    // проходит домашний экран быстрее круга сторожа и возвращает окно назад —
    // пока она идёт, окно живёт по старому правилу, как при ⌘N.
    if (from && key && state.newWindow?.busy !== true) {
      try { restoreTheme(true, liveState.on ? THEME_LAYERS.filter(layer => layer !== "theme") : THEME_LAYERS); } catch {}
      return;
    }
    try { applyChatEntry(); } catch {}
  };
  const watchChatTitle = () => {
    stopChatWatch();
    themeState.chatKey = chatKey();
    if (!themable) return;
    // Наблюдатель ловит смену заголовка тем же кадром, опрос — страховка на
    // случай, когда <title> подменили целиком или наблюдатель не встал.
    try {
      const host = document.head ?? null;
      if (host && typeof MutationObserver === "function") {
        const watcher = new MutationObserver(() => { try { syncChatTheme(); } catch {} });
        watcher.observe(host, { childList: true, subtree: true, characterData: true });
        themeState.chatObserver = watcher;
      }
    } catch { themeState.chatObserver = null; }
    themeState.chatTimer = setInterval(() => {
      if (!state.alive) { stopChatWatch(); return; }
      try { syncChatTheme(); } catch {}
      try { syncHomeFolderTheme(); } catch {}
    }, THEME_TITLE_TICK_MS);
  };

  // Вид домашнего экрана по папке (#6845, слово Элвиса: «когда я меняю здесь название проекта, чтобы
  // тема сразу менялась под название проекта»). Вид проекта знает только приложение (покраска по
  // проекту, план WF37 C2): папку чипа оно узнаёт кругом probe раз в 4 с — это и было «не сразу».
  // Страница помнит, каким видом приложение (или выбор Элвиса) покрасило домашний экран при этой
  // папке, и на смене папки в списке показывает его сама, тем же тиком сторожа заголовка. Запись
  // карты не трогаем — её сделает команда приложения следом; папки ещё не видели — ждём её, как раньше.
  // Пока идёт «Новое окно», чип показывает папку БУДУЩЕГО чата: chatsFolder тогда молчит, и смену
  // после цепочки мы сменой не считаем.
  const HOME_FOLDER_THEMES_KEY = "myclaude-home-folders-v1";
  const HOME_FOLDER_THEMES_LIMIT = 40;
  const homeFolderState = { folder: null };
  const readHomeFolderThemes = () => {
    try {
      const data = JSON.parse(localStorage.getItem(HOME_FOLDER_THEMES_KEY) ?? "null");
      return data && typeof data === "object" && !Array.isArray(data) ? data : {};
    } catch { return {}; }
  };
  // Выбор лёг в `main` на домашнем экране — запоминаем его за папкой чипа (зовёт runThemeCommand).
  const homeFolderRemember = () => {
    if (!isMainWindow() || location.pathname !== NEW_WINDOW_HOME_PATH) return;
    const folder = chatsFolder(false);
    if (!folder) return;
    homeFolderState.folder = folder;
    const entry = mapEntry(readThemeMap(), THEME_MAIN_KEY);
    const saved = readHomeFolderThemes();
    delete saved[folder];
    if (entry && Object.keys(entry).length) saved[folder] = entry;
    const keys = Object.keys(saved).slice(-HOME_FOLDER_THEMES_LIMIT);
    try {
      if (!keys.length) localStorage.removeItem(HOME_FOLDER_THEMES_KEY);
      else localStorage.setItem(HOME_FOLDER_THEMES_KEY, JSON.stringify(Object.fromEntries(keys.map(key => [key, saved[key]]))));
    } catch {}
  };
  const syncHomeFolderTheme = () => {
    if (!themable || !isMainWindow() || location.pathname !== NEW_WINDOW_HOME_PATH || themeState.previewing) {
      homeFolderState.folder = null;
      return;
    }
    const folder = chatsFolder(true);
    if (!folder) { if (state.newWindow?.busy === true) homeFolderState.folder = null; return; }
    if (folder === homeFolderState.folder) return;
    const from = homeFolderState.folder;
    homeFolderState.folder = folder;
    // Первый взгляд (пришли на домашний экран) — не смена: окно держит свой цвет, как при ⌘N.
    if (!from) return;
    const entry = readHomeFolderThemes()[folder];
    if (!entry || typeof entry !== "object") return;
    const all = themeEntry(readThemeMap()[THEME_ALL_KEY]);
    for (const layer of THEME_LAYERS) {
      // Живые цвета держат слой темы сами (как у смены чата).
      if (layer === "theme" && liveState.on) continue;
      const own = entryLayer(entry, layer);
      if (own !== undefined) { applyLayer(layer, own, "window"); continue; }
      const fromAll = entryLayer(all, layer);
      applyLayer(layer, fromAll ?? null, fromAll !== undefined ? "all" : null);
    }
  };

  // Окно адресуют заголовком, как в «Обкэшить»; заголовка нет — берёт окно под
  // фокусом. Подчинённое окно (about:blank) себя в фокусе может и не считать.
  // Необязательное поле match (WF15) адресует окно ПУТЁМ страницы
  // ("/epitaxy/local_<id>" — приложение берёт его из status.json лоадера) и
  // сильнее заголовка: у главного окна на вкладке Claude Code заголовок —
  // заглушка «Claude», и такой же носят безымянные попапы, так что команда
  // по заголовку ушла бы веером им всем. Поля нет — поведение прежнее.
  // Необязательное поле chat (WF29) адресует окно ID ЧАТА и стоит МЕЖДУ match и
  // заголовком: у попапа путь — "blank", и match ему бесполезен, а заголовок он
  // носит снимком имени чата на момент выноса в окно — чат с тех пор могли
  // переименовать, и по заголовку окно не опознаётся вовсе (задача #5455).
  // Свой id страница знает синхронно (myChatId(), раздел 12в): главное окно —
  // из пути, попап — из кэша ответа родителя. Команда приходит событием, ждать
  // промиса ей нечем; id неизвестен — команда не наша, и приложение пришлёт её
  // заголовком на следующем тике. Лучше не покраситься, чем покраситься чужим
  // проектом. match и chat разом приложение не шлёт никогда.
  const addressed = detail => {
    if (typeof detail.match === "string") return location.pathname === detail.match;
    if (typeof detail.chat === "string") {
      const id = myChatId();
      return Boolean(detail.chat) && id === detail.chat;
    }
    const title = typeof detail.title === "string" ? detail.title.trim() : "";
    return title ? windowTitle() === title : document.hasFocus();
  };

  // Команда меню, порядок полей по контракту WF12: {id, action:"theme", at,
  // scope:"window"|"all", title, preview, theme|null, font|null,
  // size:{answer?,question?}|null, look:{aurora,neon,dense,scheme?,motion?}|null}
  // (look — WF83; ключа в объекте нет — тумблер выключен; scheme — WF146; motion — #9994; fly* — #10015).
  // Поле frame (снятая рамка, #9471; его ещё шлёт гашение приложения) не читается: команда с одним frame — мимо.
  // Поля слоя нет — слой не трогаем, null — сброс слоя, значение — применить.
  // У размера то же правило действует и на КАЖДУЮ половину (WF19): поля половины
  // нет — не трогаем, число — поставить, null — снять её одну («Как у Claude» в
  // «Размер ответов ▸» не уносит с собой размер вопросов). "size":null по-прежнему
  // снимает обе — этим ходит «🧹 Всё как у Claude».
  // «Для всех» перекрывает СВОЙ слой у всех окон и чужой не трогает: «шрифт
  // всем» не снимает тем у окон, «тема всем» не снимает их шрифтов.
  // «Для окна» адресуется заголовком, как «Обкэшить», либо необязательным
  // полем match — путём страницы (WF15, см. addressed()).
  // Примерка была, а закрепили не все слои: остальные — назад из хранилища.
  const endPreviewExcept = committedLayers => {
    if (!themeState.previewing) return;
    themeState.previewing = false;
    themeState.previewLayers = [];
    const rest = THEME_LAYERS.filter(layer => !committedLayers.includes(layer));
    if (rest.length) restoreTheme(true, rest);
  };

  const runThemeCommand = detail => {
    if (!themable || !detail || typeof detail !== "object") return false;
    const layers = {};
    for (const layer of THEME_LAYERS) {
      if (!(layer in detail)) continue;
      // Размер — единственный слой, у которого команда богаче записи: половину
      // можно снять по отдельности (WF19, normalizeSizeCommand). Остальные слои
      // разбирает общая карта.
      layers[layer] = layer === "size"
        ? normalizeSizeCommand(detail[layer])
        : LAYER_NORMALIZE[layer](detail[layer]);
    }
    // Размер — единственный слой с половинками: «Размер ответов ▸ 16» приходит
    // без поля question, и оно обязано остаться прежним. Недостающую половину
    // дописываем здесь, и дальше слой ходит по коду цельным, как тема и шрифт.
    // Основа у примерки — то, что сейчас на экране (мышь ведут по подменю и
    // половинки примеряются одна за другой), у закрепления — хранилище: иначе
    // выбор «размер вопросов» утащил бы за собой примеренный размер ответов.
    if (layers.size) {
      const base = detail.preview === true
        ? themeState.size
        : (detail.scope === "all"
          ? entryLayer(themeEntry(readThemeMap()[THEME_ALL_KEY]), "size")
          : storedLayer("size"));
      const merged = { ...(base ?? {}), ...layers.size };
      // Единственное место, где снятая половина исчезает, — сразу после слияния и
      // ДО экрана (applyLayers), карты (writeLayers), сессии (storeSessionLayers) и
      // отложенной записи (themeState.pending): в хранилище половина со значением
      // null читается как «слоя нет» (entryLayer), и запись вышла бы неверной.
      for (const half of SIZE_HALVES) if (merged[half] == null) delete merged[half];
      // Снята последняя половина — слоя больше нет вовсе: это полный сброс, как
      // "size":null (и как старый пустой {}).
      layers.size = Object.keys(merged).length ? merged : null;
    }
    // Предпросмотр (мышь ведут по подменю тем и шрифтов): слои из команды идут
    // ТОЛЬКО в таблицы стилей, хранилища они не касаются вовсе — иначе проход
    // по списку записал бы в карту каждую тему, мимо которой проехала мышь.
    // Предпросмотр всегда адресован одному окну, scope тут не при чём.
    if (detail.preview === true) {
      if (Object.keys(layers).length === 0 || !addressed(detail)) return false;
      // Новая примерка перекрывает прежнюю (WF31, #5453): слои, которые примерялись
      // до неё и в эту команду не попали, возвращаются из хранилища. Иначе проезд по
      // «🔤 Шрифт ▸» оставлял бы чужой шрифт на всех цветах, мимо которых мышь пойдёт
      // дальше. Возврат стоит ПОСЛЕ guard нарочно: команда, адресованная ЧУЖОМУ окну,
      // наши слои не трогает вовсе.
      const rest = themeState.previewLayers.filter(layer => !(layer in layers));
      if (rest.length) restoreTheme(true, rest);
      applyLayers(layers, "preview");
      themeState.previewing = true;
      themeState.previewLayers = Object.keys(layers);
      return true;
    }
    // Конец предпросмотра: меню закрылось, ничего не выбрав. Оба слоя
    // возвращаем из хранилища, а слой, записи о котором нигде нет, снимаем.
    if (detail.preview === false && Object.keys(layers).length === 0) {
      if (!addressed(detail)) return false;
      restoreTheme(true);
      themeState.previewing = false;
      themeState.previewLayers = [];
      return true;
    }
    if (Object.keys(layers).length === 0) return false;
    if (detail.scope === "all") {
      const map = readThemeMap();
      const next = {};
      const all = themeEntry(map[THEME_ALL_KEY]);
      // #5743: «всем окнам» — подложка. Свой слой у окна снимаем (теперь его задаёт общая
      // запись), но не насовсем: снятое ложится на склад, а снятие общего слоя
      // («Как у Claude» → «Вернуть» в «Оформлении» панели) отдаёт его окнам назад.
      // Склад слоя заводится заново, только когда общего слоя не было: смена темы всем
      // с синей на красную снимать уже нечего, и склад первой смены обязан уцелеть.
      // Команду исполняет каждое окно, поэтому всё идемпотентно: второе окно снимать
      // уже нечего, а возврат не трогает слой, который у записи есть.
      const setting = Object.keys(layers).filter(layer => layers[layer]);
      const clearing = Object.keys(layers).filter(layer => !layers[layer]);
      const prev = readThemePrev();
      const prevBefore = JSON.stringify(prev);
      for (const layer of setting) {
        if (entryLayer(all, layer) !== undefined) continue;
        for (const saved of Object.values(prev)) if (saved && typeof saved === "object") delete saved[layer];
      }
      for (const entryKey of new Set([...Object.keys(map), ...Object.keys(prev)])) {
        if (entryKey === THEME_ALL_KEY) continue;
        const value = map[entryKey];
        const entry = themeEntry(value);
        const saved = prev[entryKey] && typeof prev[entryKey] === "object" ? prev[entryKey] : null;
        for (const layer of setting) {
          if (!(layer in entry)) continue;
          const owner = shadowOwner(value);
          prev[entryKey] = { ...(prev[entryKey] ?? {}), [layer]: entry[layer], ...(owner ? { by: owner } : {}) };
          delete entry[layer];
        }
        for (const layer of clearing) if (!(layer in entry) && saved && layer in saved) entry[layer] = saved[layer];
        if (!Object.keys(entry).length) continue;
        next[entryKey] = value === undefined && saved?.by ? { ...entry, by: saved.by } : keepOwner(entry, value);
      }
      for (const [layer, value] of Object.entries(layers)) {
        if (value) all[layer] = value; else delete all[layer];
      }
      if (Object.keys(all).length) next[THEME_ALL_KEY] = all;
      writeThemeMap(next, true, map);
      if (JSON.stringify(prev) !== prevBefore) writeThemePrev(prev);
      // Сессия окна: общий слой — в неё, снятый — из неё совсем (иначе "none" закрыл бы `main`).
      const setLayers = {};
      for (const layer of setting) setLayers[layer] = layers[layer];
      if (setting.length) storeSessionLayers(setLayers);
      if (clearing.length) dropSessionLayers(clearing);
      // Закрепление гасит предпросмотр: слой, которого в команде нет, возвращаем из
      // хранилища (примерили тему, закрепили шрифт — тема не должна зависнуть).
      endPreviewExcept(Object.keys(layers));
      applyLayers(setLayers, "all");
      // Снятый общий слой — порядком восстановления: личный слой чата вернулся со склада.
      if (clearing.length) restoreTheme(true, clearing);
      return true;
    }
    if (!addressed(detail)) return false;
    endPreviewExcept(Object.keys(layers));
    writeLayers(layers);
    applyLayers(layers, "window");
    try { homeFolderRemember(); } catch {}
    // Ключа чата ещё нет (about:blank без заголовка): запись чата дописываем,
    // когда заголовок появится (см. syncChatTheme).
    if (!chatKey()) {
      themeState.pending = layers;
      themeState.pendingUntil = now() + THEME_TITLE_WAIT_MS;
    }
    return true;
  };

  // Возврат тем после переустановки Claude (WF35). Переустановка стирает
  // localStorage страниц — вместе с ним умирает вся карта тем, и пять окон
  // Элвиса становятся серыми (#5473). Копию карты держит приложение в файле
  // ~/Library/Application Support/MyClaude/window-themes.json и присылает её
  // одной командой на все окна:
  //   {id, action:"themes-restore", at, scope:"all", entries:{<ключ>:{theme?,font?,size?,look?}}}
  // (frame из старых записей приложения не читается — слоя нет, #9471).
  // Страница НЕ заменяет свою память присланной, а ДОЛИВАЕТ недостающие слои:
  // так команда идемпотентна (память цела — не меняется ни байта), и спрашивать
  // окно «ты пуста?» не нужно вовсе. Явный сброс приезжает маркером "none" и
  // остаётся сбросом — «Как у Claude» переживает переустановку наравне с цветом.
  const RESTORE_KEY_LIMIT = 200;
  const RESTORE_KEY_MAX_LENGTH = 200;
  // Ключ из чужих рук: только наши пять видов и без пустого хвоста у префикса.
  const restoreKeyOk = key => {
    if (typeof key !== "string" || !key.length || key.length > RESTORE_KEY_MAX_LENGTH) return false;
    if (key === THEME_ALL_KEY || key === THEME_MAIN_KEY) return true;
    for (const prefix of [THEME_ID_PREFIX, THEME_CHAT_PREFIX, THEME_LEGACY_PREFIX]) {
      if (key.startsWith(prefix)) return key.length > prefix.length;
    }
    return false;
  };
  // Слой из чужих рук: "none"/null — сброс, значение — через ту же нормализацию,
  // что и команда меню; мусор равен отсутствию слоя.
  const restoreLayer = (entry, layer) => {
    if (!(layer in entry)) return undefined;
    const raw = entry[layer];
    if (raw === "none" || raw == null) return "none";
    return LAYER_NORMALIZE[layer](raw) ?? undefined;
  };
  const restoreState = { at: 0, keys: 0, merged: 0, painted: false };
  const runThemesRestoreCommand = detail => {
    if (!themable || !detail || typeof detail !== "object") return false;
    const entries = detail.entries;
    if (!entries || typeof entries !== "object" || Array.isArray(entries)) return false;
    const map = readThemeMap();
    let keys = 0;
    let merged = 0;
    for (const [key, value] of Object.entries(entries)) {
      if (keys >= RESTORE_KEY_LIMIT) break;
      if (!restoreKeyOk(key)) continue;
      const incoming = themeEntry(value);
      keys += 1;
      const mapEntryBefore = map[key];
      const current = mapEntry(map, key);
      const entry = current ? { ...current } : {};
      let added = 0;
      for (const layer of THEME_LAYERS) {
        // Всё, что у страницы уже есть, не трогаем вовсе — в том числе "none".
        if (current && layer in current) continue;
        const next = restoreLayer(incoming, layer);
        if (next === undefined) continue;
        entry[layer] = next;
        added += 1;
      }
      if (!added) continue;
      // Владелец тени (z1-r01): свой сильнее присланного; мусор не берём.
      const owner = shadowOwner(map[key]) ?? shadowOwner(value);
      map[key] = owner && key.startsWith(THEME_CHAT_PREFIX) && owner.length <= RESTORE_KEY_MAX_LENGTH
        ? { ...entry, by: owner } : entry;
      const stamp = themeStamp(current ? mapEntryBefore : value);
      if (stamp) map[key].at = stamp;
      merged += added;
    }
    if (merged) writeThemeMap(map, false);
    restoreState.at = now();
    restoreState.keys = keys;
    restoreState.merged = merged;
    // Экран трогаем, только если он наш: примерка мышью и живые цвета показывают
    // не то, что в хранилище, и перекраска сбила бы их обоих.
    restoreState.painted = !themeState.previewing && !liveState.on;
    if (restoreState.painted) { try { restoreTheme(false); } catch {} }
    return true;
  };
  // -- Края прокрутки живого вида (WF185) ----
  // Слово Элвиса 09.10 03:40: «Полосу прокрутки в режиме живом убери вообще, она только отвлекает»;
  // 03:42: «и сверху и снизу сделай плавный тоненький фейд, чтобы текст плавно терялся, а не обрезался
  // жёстко». Только живой фон (look.aurora): полос прокрутки нет нигде (прокрутка колесом и тачпадом
  // та же), у прокручиваемой области — тонкое затухание с той стороны, куда ещё есть что крутить:
  // у самого верха верхнего нет, у самого низа — нижнего, так первая и последняя строки целы.
  // Сторону знает метка SCROLL_FADE_ATTRIBUTE = top | bottom | both: её ставит прокрутка любой
  // области (событие ловим на документе) и раз в секунду обход известных областей Claude — лента,
  // список чатов, поле ввода, панели (их Tailwind-классы overflow-*-auto). Классический вид — правил
  // нет, метки снимаются: всё как у Claude.
  const SCROLL_FADE_ATTRIBUTE = "data-myclaude-scroll-fade";
  const SCROLL_FADE_PX = 14;
  const SCROLL_FADE_SELECTOR = [
    '[data-testid="epitaxy-virtual-transcript"]', ".dframe-nav-scroll",
    '[class~="overflow-y-auto"]', '[class~="overflow-auto"]', '[class~="overflow-y-scroll"]',
  ].join(",");
  // Поле и рамка, снятые сверху с рамки плиток (WF192), — шапке колонки обратно.
  const SCROLL_TOP_RETURN = "calc(var(--tiles-padding, 8px) + 1px)";
  // Низ видимой части (WF197): лента Claude длиннее своей ячейки (инлайн height: calc(100% + высота доки),
  // замер 09.10 в окне Рика: лента 1012 при ячейке 527) — в широком виде её низ за краем окна, и нижнее
  // затухание у 100 % уходило туда. Сколько ленты ниже видимого края, страница кладёт переменной узлу
  // (scrollFadeMark); затухание кончается на видимом крае, ниже — прозрачно (там ничего не видно).
  const SCROLL_FADE_CUT_VARIABLE = "--myclaude-scroll-cut";
  const SCROLL_FADE_BOTTOM = `var(${SCROLL_FADE_CUT_VARIABLE}, 0px)`;
  const SCROLL_FADE_MASKS = {
    top: `linear-gradient(to bottom, transparent 0, #000 ${SCROLL_FADE_PX}px)`,
    bottom: `linear-gradient(to bottom, #000 calc(100% - ${SCROLL_FADE_BOTTOM} - ${SCROLL_FADE_PX}px), transparent calc(100% - ${SCROLL_FADE_BOTTOM}))`,
    both: `linear-gradient(to bottom, transparent 0, #000 ${SCROLL_FADE_PX}px, #000 calc(100% - ${SCROLL_FADE_BOTTOM} - ${SCROLL_FADE_PX}px), transparent calc(100% - ${SCROLL_FADE_BOTTOM}))`,
  };
  const scrollFadeCss = () => {
    const rules = [
      // Полос прокрутки нет (Chromium: scrollbar-width сильнее ::-webkit-scrollbar — пишем оба).
      "* { scrollbar-width: none !important; }",
      "::-webkit-scrollbar { display: none !important; width: 0 !important; height: 0 !important; }",
      // WF192 (слово Элвиса 09.10 04:10: «там сейчас полоска, по ней режется фейд… фейд сделать от самого края окна
      // Claude»): рамка плиток Claude (инлайн-стиль с --tiles-padding) держит сверху поле 8 px и рамку 1 px — лента
      // начиналась ниже края окна и резалась о него. Сверху их нет: лента и её затухание — от самого края. Полоса
      // перетаскивания окна Claude (.draggable, 7 px сверху) остаётся: область окна Electron считает по стилю
      // app-region, а не по тому, что лежит поверх, — окно таскается за верх, как было. Шапку правой колонки (и
      // шапку над лентой при названии слева) возвращаем на прежнее место — сдвигается только лента.
      `div[style*="--tiles-padding"]:has(.tiles-shell) { padding-top: 0 !important; border-top-width: 0 !important; }`,
      `div[style*="--tiles-padding"] .epitaxy-chat-panel:not([data-myclaude-headless]) .epitaxy-titlebar { margin-top: ${SCROLL_TOP_RETURN} !important; }`,
    ];
    const mask = layers => `-webkit-mask-image: ${layers.join(", ")} !important; mask-image: ${layers.join(", ")} !important;` +
      (layers.length > 1 ? " -webkit-mask-composite: source-in !important; mask-composite: intersect !important;" : "");
    for (const [side, edge] of Object.entries(SCROLL_FADE_MASKS)) {
      const at = `[${SCROLL_FADE_ATTRIBUTE}="${side}"]`;
      rules.push(`${at} { ${mask([edge])} }`);
      // Лента с угловым затуханием под кнопками окна и кружком (applyCornerFade) — маски складываются.
      rules.push(`${at}[data-myclaude-corner-fade] { ${mask([CORNER_FADE_MASK, edge])} }`);
      rules.push(`${at}[data-myclaude-corner-fade][${RING_FADE_ATTRIBUTE}] { ${mask([CORNER_FADE_MASK, RING_FADE_MASK, edge])} }`);
    }
    return rules;
  };
  // Полоса прокрутки классического вида — шире и удобнее (#9845, слово Элвиса: «полосу прокрутки тоненькую эту
  // прожать, чтобы было удобно»). Только лента чата — там читают и листают; список чатов, поле ввода и меню —
  // как у Claude. Дорожка SCROLL_BAR_PX — в неё легко попасть мышью; ползунок в покое тоньше (поле прозрачной
  // рамкой), под курсором и при захвате — почти во всю дорожку и плотнее; цвет — вторичный текст темы, светлая
  // и тёмная одним правилом. Живой фон — полос нет, как было: правила выше с !important сильнее (WF185). Вес
  // (0,0,1) — сильнее только общего `* { scrollbar-width: thin }` Claude и унаследованного scrollbar-color
  // (Chromium рисует ::-webkit-scrollbar лишь при auto у обоих). Место под полосу Claude держит с обеих сторон
  // (`scrollbar-gutter: stable both-edges`) — с широкой полосой колонка текста теряла 24 px, слева впустую (#10111).
  // #11216 (слово Элвиса 30.10 17:20: «полоса прокрутки здесь слишком широкая… поуже сделать, суперпрозрачную…
  // едва-едва заметная»): дорожка 8, ползунок в покое — нитка 2 px в 18 % цвета; под курсором и при захвате
  // шире и плотнее, как было, — попасть мышью по-прежнему можно. Та же нитка — у поля ввода (его прокрутка в широком
  // виде — div:has(> .ProseMirror), в узком — корень поля с ручкой): серая полоса Claude стояла рядом и отвлекала так же.
  const SCROLL_BAR_PX = 8;
  const SCROLL_TRACK_CUT_VARIABLE = "--myclaude-track-cut";
  const SCROLL_BAR_AREA = 'html :where([data-testid="epitaxy-virtual-transcript"], [data-cds="ChatComposer"] div:has(> .ProseMirror), [data-myclaude-editor-root])';
  const SCROLL_BAR_INK = share => `color-mix(in srgb, var(--cds-text-secondary, currentColor) ${share}%, transparent)`;
  lateRules.push(
    `${SCROLL_BAR_AREA}{scrollbar-width:auto;scrollbar-color:auto;scrollbar-gutter:auto}`,
    `${SCROLL_BAR_AREA}::-webkit-scrollbar{width:${SCROLL_BAR_PX}px;height:${SCROLL_BAR_PX}px;background:transparent}`,
    `${SCROLL_BAR_AREA}::-webkit-scrollbar-track,${SCROLL_BAR_AREA}::-webkit-scrollbar-corner{background:transparent}`,
    `${SCROLL_BAR_AREA}::-webkit-scrollbar-track:hover{background:${SCROLL_BAR_INK(4)}}`,
    `${SCROLL_BAR_AREA}::-webkit-scrollbar-thumb{min-height:40px;min-width:40px;border:3px solid transparent;border-radius:${SCROLL_BAR_PX}px;background:${SCROLL_BAR_INK(18)} padding-box}`,
    `${SCROLL_BAR_AREA}::-webkit-scrollbar-thumb:hover{border-width:1px;background-color:${SCROLL_BAR_INK(40)}}`,
    `${SCROLL_BAR_AREA}::-webkit-scrollbar-thumb:active{border-width:1px;background-color:${SCROLL_BAR_INK(55)}}`,
    `${SCROLL_BAR_AREA}::-webkit-scrollbar-button{display:none}`,
    // #10110: лента длиннее ячейки на высоту доки (её низ за краем окна или под докой) — дорожка кончается на
    // видимом крае (запас — переменная SCROLL_TRACK_CUT_VARIABLE), у конца чата ползунок виден. Саму ленту не
    // укорачиваем: с ней на текст ложилась размытая полоса Claude под доку (page-88).
    `${SCROLL_BAR_AREA}::-webkit-scrollbar-track{margin-bottom:var(${SCROLL_TRACK_CUT_VARIABLE},0px)}`,
  );
  const scrollFadeOn = () => themeState.look?.aurora === true;
  // Сторона затухания по прокрутке узла: "" — крутить некуда (или живой вид выключен).
  const scrollFadeOf = node => {
    const room = Number(node?.scrollHeight) - Number(node?.clientHeight);
    if (!(room > 1)) return "";
    const top = Number(node.scrollTop) > 1;
    const bottom = Number(node.scrollTop) < room - 1;
    return top && bottom ? "both" : top ? "top" : bottom ? "bottom" : "";
  };
  // Сколько узла ниже видимого края: его ячейки (родителя) и окна.
  const scrollFadeCut = node => {
    try {
      const box = node.getBoundingClientRect();
      const cell = node.parentElement?.getBoundingClientRect?.();
      let edge = Number(window.innerHeight) || Infinity;
      if (cell && cell.height > 0) edge = Math.min(edge, cell.bottom);
      const cut = Math.round(box.bottom - edge);
      return cut > 1 && cut < box.height ? cut : 0;
    } catch { return 0; }
  };
  const scrollFadeMark = node => {
    if (node?.nodeType !== 1) return;
    const side = scrollFadeOn() ? scrollFadeOf(node) : "";
    if (side) { if (node.getAttribute(SCROLL_FADE_ATTRIBUTE) !== side) node.setAttribute(SCROLL_FADE_ATTRIBUTE, side); }
    else if (node.hasAttribute(SCROLL_FADE_ATTRIBUTE)) node.removeAttribute(SCROLL_FADE_ATTRIBUTE);
    const cut = side === "bottom" || side === "both" ? scrollFadeCut(node) : 0;
    const value = cut ? `${cut}px` : "";
    if ((node.style?.getPropertyValue(SCROLL_FADE_CUT_VARIABLE) ?? "") !== value) {
      if (value) node.style.setProperty(SCROLL_FADE_CUT_VARIABLE, value);
      else node.style?.removeProperty(SCROLL_FADE_CUT_VARIABLE);
    }
  };
  const scrollFadeState = { marks: 0 };
  const scrollFadeScan = () => {
    for (const node of document.querySelectorAll(`[${SCROLL_FADE_ATTRIBUTE}]`)) scrollFadeMark(node);
    if (scrollFadeOn()) for (const node of document.querySelectorAll(SCROLL_FADE_SELECTOR)) scrollFadeMark(node);
    scrollFadeState.marks = document.querySelectorAll(`[${SCROLL_FADE_ATTRIBUTE}]`).length;
    // Низ дорожки полосы ленты (#10110) — во всех видах: полоса видна там, где живого фона нет.
    for (const node of document.querySelectorAll('[data-testid="epitaxy-virtual-transcript"]')) {
      const cut = scrollFadeCut(node);
      const value = cut ? `${cut}px` : "";
      if ((node.style?.getPropertyValue(SCROLL_TRACK_CUT_VARIABLE) ?? "") !== value) {
        if (value) node.style.setProperty(SCROLL_TRACK_CUT_VARIABLE, value);
        else node.style?.removeProperty(SCROLL_TRACK_CUT_VARIABLE);
      }
    }
  };
  on(document, "scroll", event => { if (scrollFadeOn()) { try { scrollFadeMark(event.target); } catch {} } }, { capture: true, passive: true });
  track(() => { for (const node of document.querySelectorAll(`[${SCROLL_FADE_ATTRIBUTE}]`)) { node.removeAttribute(SCROLL_FADE_ATTRIBUTE); node.style?.removeProperty(SCROLL_FADE_CUT_VARIABLE); } });
  track(() => { for (const node of document.querySelectorAll('[data-testid="epitaxy-virtual-transcript"]')) node.style?.removeProperty(SCROLL_TRACK_CUT_VARIABLE); });

  // Осечка темы не должна утащить за собой ручку: раздел стоит выше её
  // постройки, и без этой обёртки любое падение на неготовой разметке оставило
  // бы окно вовсе без полоски.
  try { migrateChatKey(); restoreTheme(); watchChatTitle(); } catch {}
  // Возврат тем (WF35): когда приезжала команда themes-restore, сколько
  // ключей приняли, сколько слоёв долили и красилось ли окно (примерка и
  // живые цвета красить запрещают).
  statusPart("restore", () => ({
    at: restoreState.at || null,
    keys: restoreState.keys,
    merged: restoreState.merged,
    painted: restoreState.painted,
  }));
  // WF241: живой фон стоит — окно скрыто или дольше LOOK_IDLE_MS без фокуса.
  statusPart("lookStill", () => lookStill());
  // WF185: сколько областей прокрутки сейчас с затуханием края (живой вид; классический — 0).
  statusPart("scrollFades", () => scrollFadeState.marks);
  HATCH && Object.assign(HATCH, { scrollFadeOf, auroraCalm, LOOK_IDLE_MS, syncHomeFolderTheme });

