  // ---- 12в. Кто этот чат ---------------------------------------------------
  // Приложение красит окно цветом ПРОЕКТА, а проект берёт из папки чата. До
  // WF29 окно опознавалось заголовком — и три попапа из четырёх у Элвиса не
  // опознавались вовсе: заголовок попапа это снимок имени чата на момент выноса
  // в окно, а чаты с тех пор переименованы (задача #5455; setPopoutTitle Claude
  // при переименовании не зовёт). Отсюда правило: чат окна называет САМА
  // страница, а приложение только спрашивает.
  //
  // Кто как узнаёт свой чат:
  //   главное окно (claude.ai) — хвост location.pathname (/epitaxy/local_<id>);
  //   попап (about:blank, своего адреса у него нет) — сперва читает СВОЁ
  //     React-волокно (chatFiberId, WF77 #6734): у узлов над панелью чата есть
  //     пропс sessionId, и он про ЭТО окно и ни про какое другое. Волокно
  //     молчит — прежний путь: спрашивает окно-родителя
  //     window.opener.__myclaude.popoutChat(<заголовок>). У claude.ai есть стор
  //     с картой popoutWindows: <id чата> → {title,…}, где title — ровно то, что
  //     стоит в document.title попапа. Стор ищется поведенчески, тот же, что у
  //     «Нового окна» (раздел 12б), и тем же кэшем. Вопрос ПО ЗАГОЛОВКУ и был
  //     бедой: одинаковые заголовки у Элвиса норма, и двум попапам родитель
  //     называл ОДИН чат — «меняю цвет, меняется у обоих» (слово Элвиса 20.09).
  //   чужая страница (data:, file:, localhost) — молчит первой же строкой:
  //     лоадер шлёт probe.js во ВСЕ страницы, а их у Claude больше сорока.
  //
  // Спрашивает приложение через probe.js (канал лоадера): скрипт зовёт
  // window.__myclaude.chats({scan, nonce}), ответ ложится в probe-result.json.
  // Своих таймеров, подписок и наблюдателей раздел не заводит НИ ОДНОГО —
  // лоадер перечитывает файл по mtime и гоняет его в том же окне снова, и
  // каждая подписка здесь стала бы зомби (раздел 0).
  // Карта попапов свежа полминуты: чаще круга probe она всё равно не нужна, а
  // скан исполняет чужие модули (раздел 12б).
  const CHATS_MAP_TTL_MS = 30000;
  // Активную строку сайдбара кладём отдельным полем — ТОЛЬКО для сверки на
  // гейте: data-selected чужой атрибут claude.ai, «focused» может значить не
  // «показан», и поведение на нём не строится (план WF29, решение 5).
  const CHAT_ROW_SELECTOR = '[data-selected="focused"][data-row-key], [data-selected="focused"] [data-row-key]';

  // Карта попапов и её возраст живут в замыкании: спрашиваем стор только по
  // просьбе приложения, между кругами отдаём кэш. store — чем кончился
  // последний вызов chats(), его же показывает status().chat.
  const chatsState = { map: null, at: 0, store: null };
  // Идущий скан: на него садятся все, кто попросил, пока он не кончился.
  let chatsScanInFlight = null;
  // Идущий поиск стора папки (WF37, см. chatsFolder): второго не заводим.
  let chatsFolderScanInFlight = null;
  track(() => { chatsFolderScanInFlight = null; });
  // Неудача поиска запоминается: повтор не чаще раза в CHATS_FOLDER_RETRY_MS —
  // иначе после релиза Claude, сменившего форму стора, скан всех адресов шёл бы
  // каждый круг probe, раз в 4 с (проверка WF37, находка 2).
  const CHATS_FOLDER_RETRY_MS = 60000;
  let chatsFolderScanAt = 0;
  track(() => { chatsFolderScanAt = 0; });

  const chatKind = () => (!themable ? "other" : isMainWindow() ? "main" : "popout");
  // Путь чужой страницы наружу не отдаём: у артефакта это data:-адрес целиком,
  // а такие уже раздули probe-result.json до 3,9 МБ (разведка плана, п. 1).
  const chatPath = () => (themable ? location.pathname : "");
  const chatRowId = () => {
    if (!isMainWindow()) return null;
    try {
      const node = document.querySelector(CHAT_ROW_SELECTOR);
      // Ключи строк — code:local_<uuid> / chat:<uuid>, нам нужен хвост.
      const id = String(node?.getAttribute?.("data-row-key") ?? "").split(":").pop() ?? "";
      return id.startsWith("local_") ? id : null;
    } catch { return null; }
  };

  // Ответ родителя переживает перезапуск инжекта: лоадер перечитывает файл по
  // mtime (каждый гейт после cp, каждое обновление приложения), и замыкание при
  // этом умирает. Команда с полем chat приходит событием и ждать промиса не
  // может — с пустым кэшем попап отверг бы её, а отпечаток в приложении был бы
  // уже записан, и окно осталось бы некрашеным. sessionStorage у попапа свой на
  // окно (about:blank унаследовал origin claude.ai) — так же живут
  // myclaude-theme-v1 и myclaude-live-phase-v1. Запись годна, пока заголовок
  // окна равен сохранённому: сменился — спросим родителя заново.
  // Объявление, а не стрелка: readChatId зовёт chatIdKey (раздел 2а) на инжекте,
  // то есть ВЫШЕ этой строки — `const` там был бы ещё в TDZ (WF35).
  // Заголовок-заглушка («Loading», «Code», «Claude») чата не называет (WF93,
  // #7378): Claude отдаёт скрытое окно закрытого попапа новому чату вместе с
  // sessionStorage, и запись прошлого чата с тем же «Loading» сошлась бы.
  // Объявление, а не стрелка: его зовут readChatId и chatFiberId на инжекте.
  function chatIdTitleOk(title) { return Boolean(title) && !THEME_TITLE_STUBS.has(title.toLowerCase()); }
  function readChatId() {
    try {
      const raw = sessionStorage.getItem(CHAT_ID_KEY);
      if (raw == null) return null;
      const record = JSON.parse(raw);
      const id = typeof record?.id === "string" ? record.id : "";
      const title = typeof record?.title === "string" ? record.title : "";
      if (!id.startsWith("local_") || title !== windowTitle() || !chatIdTitleOk(title)) return null;
      return id;
    } catch { return null; }
  }
  // Объявление, а не стрелка, по той же причине, что и у readChatId: запись
  // кэша случается и на инжекте — лоадер перечитывает inject.js по mtime в ЖИВОМ
  // попапе, где волокно уже отвечает, а раздел 2а идёт раньше этой строки.
  function writeChatId(id) {
    const title = windowTitle();
    if (!chatIdTitleOk(title)) return;
    try { sessionStorage.setItem(CHAT_ID_KEY, JSON.stringify({ id, title })); } catch {}
  }

  // Волокно React у узла: React кладёт его собственным свойством
  // `__reactFiber$<хэш>`. Свой обход, а не openChromeFiber раздела 12г: тот
  // объявлен НИЖЕ по файлу и на инжекте был бы ещё в TDZ.
  function chatFiberOf(node) {
    try {
      for (const key of Object.keys(node)) {
        if (key.startsWith("__reactFiber$")) return node[key];
      }
    } catch {}
    return null;
  }
  // Свой id из React-волокна (WF77, #6734). От контейнеров ИМЕННО ЭТОГО чата
  // вверх по `return` (не дальше CHAT_FIBER_DEPTH): у компонентов над панелью
  // есть пропс sessionId — id открытого в окне чата (проба 20.09).
  // Три ответа: `local_<uuid>` — вот мой чат; `""` — волокно СПОРИТ САМО С
  // СОБОЙ, встретились два разных id, и тогда мы не называем ни одного (чужой
  // чат хуже, чем «не определён», — разбор критика, п. 4); null — волокна нет
  // вовсе, и работает прежний путь через родителя.
  // Объявление, а не стрелка: myChatId() зовут на инжекте (chatIdKey, раздел
  // 2а). Не бросает и на пустом DOM: там просто нет стартовых узлов.
  function chatFiberId() {
    const title = windowTitle();
    // Кэш — только у настоящего имени и живого узла (#7378): иначе окно из
    // запаса Claude называло себя прошлым чатом.
    if (chatFiberState.id && chatFiberState.title === title && chatIdTitleOk(title)
      && chatFiberState.node?.isConnected) return chatFiberState.id;
    let found = null;
    let where = null;
    try {
      for (const node of document.querySelectorAll(CHAT_FIBER_SELECTOR)) {
        let fiber = chatFiberOf(node);
        for (let hop = 0; fiber && hop <= CHAT_FIBER_DEPTH; hop += 1, fiber = fiber.return) {
          // Живая проба гейта 20.09: сам `sessionId` лежит на 63-м прыжке от панели
          // — за пределом; рядом с полосой заголовка тот же id носят `episodeKey`
          // (1-й прыжок) и `initialSessionId` (11-й). Читаем все три, согласие то же.
          const props = fiber.memoizedProps;
          for (const name of CHAT_FIBER_PROPS) {
            const id = props?.[name];
            if (typeof id !== "string" || !id.startsWith("local_")) continue;
            if (found && found !== id) return "";
            found = id;
            where = node;
          }
        }
      }
    } catch { return null; }
    if (found) { chatFiberState.title = title; chatFiberState.id = found; chatFiberState.node = where; }
    return found;
  }

  // Синхронный ответ «какой чат в этом окне» — им пользуются addressed() и ключ
  // темы chatIdKey (раздел 2а). Объявление, а не стрелка: chatIdKey зовёт его на
  // инжекте, а инжект проходит раздел 2а раньше этой строки (WF35).
  function myChatId() {
    if (!themable) return null;
    if (isMainWindow()) return newWindowSessionId() || null;
    // Попап: своё волокно сильнее кэша ответа родителя — родитель ищет чат ПО
    // ЗАГОЛОВКУ и двум одноимённым окнам называет один и тот же (слово Элвиса
    // 20.09). Спорную запись кэша переписываем: она уже увела чужую команду в
    // это окно и сама не исправится. Волокно спорит само с собой ("") — кэш не
    // спасает: он из того же вопроса по заголовку, которому мы больше не верим.
    const own = chatFiberId();
    if (own === "") return null;
    if (!own) return readChatId();
    if (readChatId() !== own) writeChatId(own);
    return own;
  }

  // Карта попапов из стора: [{id, title}]. null — стор ответить не смог (упал
  // или отдал не Map); пустой список — попапов нет, и это тоже ответ.
  const chatsMap = store => {
    try {
      const value = store?.getState?.();
      const map = value?.popoutWindows;
      if (!(map instanceof Map)) return null;
      const out = [];
      for (const [id, record] of map) {
        const key = typeof id === "string" ? id : "";
        if (!key) continue;
        out.push({ id: key, title: String(record?.title ?? "").trim() });
      }
      return out;
    } catch { return null; }
  };
  const chatsNeedScan = () => !chatsState.map || Date.now() - chatsState.at > CHATS_MAP_TTL_MS;
  // Одновременные просьбы (четыре попапа спросили родителя разом) складываются
  // в ОДИН скан: промис держится в замыкании, остальные ждут его. Токен берём
  // ТЕКУЩИЙ и не увеличиваем — начался прогон «Нового окна», скан бросит работу
  // сам, и мы честно скажем "busy", оставив прежнюю карту.
  const chatsScan = () => {
    if (chatsScanInFlight) return chatsScanInFlight;
    const token = newWindowToken;
    const run = (async () => {
      let store = null;
      try { store = await newWindowFindStore(token); } catch { store = null; }
      if (!newWindowLive(token)) return "busy";
      if (!store) return "none";
      const map = chatsMap(store);
      if (!map) return "none";
      chatsState.map = map;
      chatsState.at = Date.now();
      // Inventory уже известен: отложенную на старте уборку делает main.
      if (isMainWindow()) writeThemeMap(readThemeMap(), false);
      return "ok";
    })();
    chatsScanInFlight = run.then(
      result => { chatsScanInFlight = null; return result; },
      () => { chatsScanInFlight = null; return "none"; },
    );
    return chatsScanInFlight;
  };

  // Ответ попапу: id чата с ТАКИМ заголовком. Ноль совпадений или два и больше
  // — null: лучше «не определён», чем чужой проект. Заглушки («Claude», «New
  // chat») в сопоставлении не участвуют вовсе — их носят разные чаты во всех
  // окнах разом.
  const popoutChat = async (title, opts) => {
    try {
      const want = typeof title === "string" ? title.trim() : "";
      if (!want || THEME_TITLE_STUBS.has(want.toLowerCase())) return null;
      // Карта попапов есть только у главного окна; спрашивать попап незачем.
      if (!isMainWindow()) return null;
      if (opts?.scan === true && chatsNeedScan()) await chatsScan();
      const hits = (chatsState.map ?? []).filter(item => item.title === want);
      return hits.length === 1 ? hits[0].id : null;
    } catch { return null; }
  };

  // Попап спрашивает родителя. Кэш — раньше вопроса: он и дешевле, и переживает
  // перезапуск инжекта. "ok" значит «канал сработал», даже если id не нашёлся
  // (это и есть «не определён», приложение такое окно не красит вовсе); "none"
  // — спросить было некого, и приложение падает на старый путь по заголовку.
  const chatsAsk = async scan => {
    // Волокно — раньше всего, даже раньше заголовка: у безымянного попапа
    // («Claude») своего id по заголовку не добыть вовсе, а в волокне он есть.
    // Волокно ответило хоть что-то (id или «согласия нет», см. chatFiberId) —
    // этим и кончаем: "ok" значит «спросили источник», даже когда id не
    // определился (набор значений store не расширяем).
    const own = chatFiberId();
    if (own !== null) return { id: own || null, store: "ok" };
    // Волокна нет — прежний путь, как до WF77: кэш, потом сам родитель.
    const title = windowTitle();
    if (!title || THEME_TITLE_STUBS.has(title.toLowerCase())) return { id: null, store: "none" };
    const cached = readChatId();
    if (cached) return { id: cached, store: "cache" };
    try {
      const parent = window.opener;
      const ask = parent?.__myclaude?.popoutChat;
      if (typeof ask !== "function") return { id: null, store: "none" };
      const answered = await ask.call(parent.__myclaude, title, { scan: scan === true });
      const id = typeof answered === "string" && answered.startsWith("local_") ? answered : null;
      if (id) writeChatId(id);
      return { id, store: "ok" };
    } catch { return { id: null, store: "none" }; }
  };

  // Карта тем в ответ probe (WF35): по ней приложение держит на диске копию
  // хранилища окон и возвращает её после переустановки Claude. Отдаёт её ТОЛЬКО
  // главное окно: лоадер гоняет probe.js во ВСЕХ страницах (их у Claude больше
  // сорока), а карта на origin одна — иначе каждая страница вернула бы её КОПИЮ
  // (ответ и без того весит мегабайты), а артефакт на чужом origin вернул бы
  // ПУСТУЮ карту и подсунул бы приложению ложное «Элвис снял всё сам».
  const chatsThemes = () => (isMainWindow() ? readThemeMap() : null);

  // Рамка окна страницы (WF77, #6734): [screenX, screenY, outerWidth,
  // outerHeight] в тех же глобальных координатах, что у AX (проверено на
  // Odyssey над макбуком). Ею приложение отличает два окна с ОДИНАКОВЫМ
  // заголовком — заголовок у Элвиса перестал быть приметой окна.
  // Целые: у Quartz рамка целая, дробь страницы сверке только мешала бы.
  // Отдают её ТОЛЬКО наши страницы (main и popout): артефакт на data:-адресе
  // живёт в том же окне Claude и подсунул бы приложению его рамку как свою.
  // Чисел нет (браузер их не дал) — поля нет вовсе.
  const chatFrame = kind => {
    if (kind !== "main" && kind !== "popout") return null;
    try {
      const box = [window.screenX, window.screenY, window.outerWidth, window.outerHeight];
      if (!box.every(value => Number.isFinite(value))) return null;
      return box.map(value => Math.round(value));
    } catch { return null; }
  };

  // Папка домашнего экрана (WF37, #5576). Пока чат не открыт, сессии на диске
  // нет, и приложению папку взять неоткуда — окно оставалось некрашеным, хотя
  // чип над полем ввода проект уже показывает. Этот выбор (папка БУДУЩЕГО чата)
  // живёт в сторе claude.ai, и его же ставит цепочка «Нового окна»
  // (newWindowFolderStore, раздел 12б).
  // Отдаёт папку ТОЛЬКО главное окно и ТОЛЬКО на домашнем экране: в открытом
  // чате правду говорит индекс сессий (там выбор чипа не значит ничего), а у
  // попапа своего выбора нет вовсе.
  // Стор ещё не найден — ищем его В ФОНЕ (один скан на все круги, чужие модули
  // исполняются по разу) и честно отвечаем null: скан идёт около секунды, а
  // ответ probe ждать не может. Поле scan команды тут ни при чём — оно про
  // карту попапов; фоновый поиск заводит любой круг probe, а status() — никогда
  // (mayScan = false): он обещан синхронным слепком из кэша.
  const chatsFolder = mayScan => {
    try {
      if (!isMainWindow() || !newWindowAtHome()) return null;
      // Идёт «Новое окно»: чип показывает папку БУДУЩЕГО чата, а не выбор Элвиса, —
      // покраска главного окна по ней мигала бы чужим цветом (проверка WF37, находка 3).
      if (state.newWindow?.busy === true) return null;
      if (newWindowFolderStoreOk(newWindowFolderStore)) return newWindowFolderNow(newWindowFolderStore) || null;
      if (mayScan && !chatsFolderScanInFlight && Date.now() - chatsFolderScanAt >= CHATS_FOLDER_RETRY_MS) {
        // Токен берём ТЕКУЩИЙ и не увеличиваем: начался прогон «Нового окна» —
        // скан бросит работу сам (newWindowLive).
        const token = newWindowToken;
        chatsFolderScanAt = Date.now();
        const done = () => { chatsFolderScanInFlight = null; };
        chatsFolderScanInFlight = Promise.resolve(newWindowFindFolderStore(token)).then(done, done);
      }
      return null;
    } catch { return null; }
  };

  // Ход Workflow из строки состояния последнего ответа (#10315, контракт 510):
  // приложению — «идёт ли Workflow проекта прямо сейчас» для блока Workflow
  // панели. Слепок полосы (раздел 2б) как есть: строки нет — поля нет, и это
  // не «не идёт»; лента не у низа — последнее прочитанное (ряд стоит).
  const chatsFlow = () => {
    try {
      const info = progressState.info;
      if (!info || typeof info.state !== "string") return {};
      return { flow: { state: info.state, project: info.project || null } };
    } catch { return {}; }
  };

  // Ответ probe.js. Контракт (план WF29, решение 4; WF37 дописал folder после
  // store) — побайтно:
  //   {v, nonce, kind, self, path, row, title, popouts:[{id,title}], store, folder, at}
  // WF35 дописывает в ХВОСТ необязательное themes (карта тем главного окна):
  // контракт выше остаётся побайтно прежним, а «поля нет» приложение отличает
  // от «карта пуста». WF77 дописывает туда же frame (рамка окна) — ПОСЛЕ at и
  // ПЕРЕД themes; старое приложение поле игнорирует, новое без поля работает
  // по-старому.
  // store: "ok" — спросили стор/родителя, "cache" — из карты в замыкании,
  // "busy" — идёт «Новое окно», "none" — спросить не вышло, "skip" — не наша
  // страница. Функция НИКОГДА не бросает: probe ждёт объект, а не исключение.
  const chats = async opts => {
    const nonce = typeof opts?.nonce === "string" ? opts.nonce : null;
    const scan = opts?.scan === true;
    const answer = (kind, self, store, popouts) => {
      const themes = chatsThemes();
      const frame = chatFrame(kind);
      return {
        v: 1,
        nonce,
        kind,
        self: self ?? null,
        path: chatPath(),
        row: chatRowId(),
        title: windowTitle(),
        popouts: popouts ?? [],
        store,
        folder: chatsFolder(true),
        at: Date.now(),
        // mic (К4) — после frame и только вместе с ним: наши страницы.
        // micNative (#9681) — место родной кнопки диктовки, тем же правилом.
        ...(frame ? { frame, mic: micSpot(), micNative: micNativeSpot() } : {}),
        // WF87: работает ли чат (наши страницы) и лимиты (только главное окно —
        // оно одно ходит в API, попапы отвечали бы тем же кэшем).
        // #10315: flow — после sendDelaySetting, только когда строка состояния разобрана.
        ...(kind === "main" || kind === "popout" ? { working: pageWorking(), autoContinue: autoOn(), galleryCounted: galleryState.counted, sendDelaySetting: sendDelaySetting(), ...chatsFlow() } : {}),
        ...(kind === "main" ? { limits: limitsNow(true) } : {}),
        ...(themes ? { themes } : {}),
        // Масштаб окна Claude (`ClaudeZoom`): множитель зума виден только по разнице внешней и внутренней ширины.
        ...(kind === "main" || kind === "popout" ? { zoom: Math.round(window.outerWidth / window.innerWidth * 100) } : {}),
      };
    };
    try {
      const kind = chatKind();
      if (kind === "other") {
        chatsState.store = "skip";
        return answer(kind, null, "skip");
      }
      if (kind === "popout") {
        const found = await chatsAsk(scan);
        chatsState.store = found.store;
        return answer(kind, found.id, found.store);
      }
      // Главное окно: свой id берётся из пути и вопроса не требует, а скан нужен
      // ради карты попапов — и только когда карты нет или она старше TTL.
      let store = chatsState.map ? "cache" : "none";
      if (scan && chatsNeedScan()) store = await chatsScan();
      chatsState.store = store;
      return answer(kind, myChatId(), store, (chatsState.map ?? []).map(item => ({ id: item.id, title: item.title })));
    } catch {
      chatsState.store = "none";
      return answer(chatKind(), null, "none");
    }
  };
  // Кто этот чат (раздел 12в) — синхронный слепок, ТОЛЬКО из кэша: скана
  // status() не запускает и промиса не отдаёт. self — id чата этой
  // страницы, popouts — сколько записей в карте попапов, store — чем
  // кончился последний chats(), at — когда снята карта.
  statusPart("chat", () => ({
    kind: chatKind(),
    self: myChatId(),
    path: chatPath(),
    row: chatRowId(),
    popouts: chatsState.map ? chatsState.map.length : 0,
    store: chatsState.store,
    // Папка чипа домашнего экрана (WF37) — только из кэша: скана status()
    // не запускает, стор ещё не найден — null.
    folder: chatsFolder(false),
    at: chatsState.at || null,
  }));
  HATCH && Object.assign(HATCH, { myChatId, readChatId, chatFiberId, chatsScan, popoutChat, chats });

