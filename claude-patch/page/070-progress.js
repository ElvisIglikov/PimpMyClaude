  // ---- 2б. Полоса прогресса воркфлоу --------------------------------------
  // С WF84 (#7204, docs/design-strip-wf84.md) это ряд «мелких номеров» внутри
  // рамки поля, слева под строкой ввода: номер 12 точек на каждый воркфлоу
  // марафона, цвет — состояние (готов акцентом, идёт — контур с дышащей линией
  // шагов, ждёт тебя — жёлтый, упал — красный, впереди — пустой контур; весь
  // марафон «готово ✅» — зелёный). Состояние каждого номера — из двух вестей:
  // строки состояния чата (счёт и слово текущего) и сводки status.md (блок на
  // каждый номер, progressBadgeStates). Строка читается ТОЛЬКО у низа ленты:
  // прокрутил вверх — ряд стоит (progressRefresh). До WF84 были тонкая линия
  // (WF9–WF81) и капсулы с подписями (WF82, #7105) — их история в git log; от
  // них остались пул узлов, плавная заливка, пульс и попадание мышью.
  //
  // Источник — сам чат, а не хранилище: последняя строка состояния в ответах
  // ассистента («💭⚪[Проект](docs/status.md) · WF 6 из 7 · 40%💭», формат из
  // SkilZZZ/AGENTS.md). Поэтому каждое окно считает по своему разговору, ничего
  // не хранит и ни с кем не синхронизируется.
  //
  // Строки состояния нет — полосы нет вовсе (довод донора): пустая полоса
  // утверждала бы «марафон только начался» ровно там, где марафона нет.
  //
  // Подсказка — свой div, а не title: у полосы pointer-events:none (иначе она
  // ловила бы клики по полю ввода), а без указателя title не показывается вовсе.
  // По той же причине и наведение, и клик ловятся общими слушателями документа,
  // а не прозрачной накладкой над линией: накладка стояла бы поверх низа поля
  // ввода и съедала клики по нему.
  //
  // WF12 (подсказка по клику): наведение больше ничего не показывает — только
  // ставит «руку» в ±4 точках от линии. Подсказка открывается кликом по сегменту
  // и рассказывает про ОДИН воркфлоу, а не про весь марафон разом: раньше она
  // выскакивала сама, стоило мыши пройти над полем ввода, и закрывала пол-окна
  // сводкой. Повторный клик по тому же сегменту, Escape и клик мимо — закрывают.
  //
  // Отступление от плана: полоса не absolute внутри блока ввода, а fixed по
  // координатам — как и сама ручка. Довод записан в разделе 4 прямым текстом:
  // рамка поля живёт в чужом дереве, и свой узел туда лучше не вставлять. React
  // пересобирает низ окна на каждую смену модели, а position:absolute потребовал
  // бы ещё и менять position у чужого контейнера. Место на экране от этого не
  // меняется: считаем его по boundingClientRect рамки поля.
  const PROGRESS_ID = "myclaude-progress-bar";
  const PROGRESS_TIP_ID = "myclaude-progress-tip";
  const PROGRESS_CARD_ID = "myclaude-progress-card";
  // Вид карточки — по макету docs/9-card-opus-5.5.html (WF84, #7205), 9.1
  // «дорожка в столбик»: строки этапов рисует progressCardPaint, данные —
  // progressCardView.
  // Перечитывать ленту чаще раза в секунду незачем: строка состояния меняется
  // раз в ответ, а innerText сообщения — это принудительный reflow.
  const PROGRESS_MIN_GAP = 1000;
  // Страховочный перечёт: в тихом окне мутаций ленты может не быть вовсе.
  const PROGRESS_IDLE_MS = 10000;
  // Сколько последних ответов просматриваем. Строку состояния пишет каждый
  // ответ, поэтому дальше десятка забираться незачем, а перечитывать весь
  // длинный разговор раз в секунду — уже заметная работа.
  const PROGRESS_LOOKBACK = 12;
  // Цвет по состоянию: ждём Элвиса — жёлтый, упало — красный, «готово» —
  // зелёный (буква Элвиса 1A, WF22); «идёт» берёт акцент темы окна (её красит
  // раздел 2а). Жёлтый и красный достаются ТЕКУЩЕМУ сегменту — красным метится
  // ровно то место, где марафон встал; зелёное «готово» красит всю полосу.
  const PROGRESS_PAINT = { done: "#4dbb7d", wait: "#f5c542", fail: "#ef4444" };
  // ---- «мелкие номера» (WF84, #7204, макет docs/7-strip-opus-5.5.html) --------
  // Слово Элвиса 23.09: «Мелкие номера — прикольно… Зачем много места отнимать?».
  // Ряд капсул во всю ширину с подписями (#7105) сменился рядом маленьких
  // номеров слева, по левому краю текста поля: номер 12 точек высотой, без
  // подписей (время и слово — в карточку). Зазор 4, в тесноте 3; всё равно не
  // влезает — первые подряд готовые сливаются в один номер «1–9».
  const PROGRESS_BADGE_GAP = 4;
  const PROGRESS_BADGE_GAP_TIGHT = 3;
  // Предел номеров: марафон длиннее сорока воркфлоу — уже не марафон.
  const PROGRESS_SEG_MAX = 40;
  const PROGRESS_BADGE_HEIGHT = 12;
  const PROGRESS_BADGE_MIN = 18;
  // Ширина номера ставится узлу явно, по числу знаков: цифра 9-м кеглем —
  // около 5,5 точки, поля по 3. Явная ширина нужна подгонке («влезает ли
  // ряд») и попаданию мышью — у обоих одна и та же арифметика, что и на экране.
  const progressBadgeWidth = label => Math.max(PROGRESS_BADGE_MIN, Math.ceil(String(label ?? "").length * 5.5 + 6));
  // Место под ряд (#7189: «воздух между скриншотами и полоской»): от строки
  // ввода до номеров 6, от плиток вложений 8, плюс сам номер 12. Добавка к
  // нижнему полю рамки — 18 без вложений и 20 с ними (было 35).
  const PROGRESS_ROOM_TEXT = 6 + PROGRESS_BADGE_HEIGHT;
  const PROGRESS_ROOM_TILES = 8 + PROGRESS_BADGE_HEIGHT;
  // Плитки вложений в поле ввода: та же примета, что у раскладки вложений
  // (раздел 2а, attachmentsCss), и плашка вложения старой разметки.
  const PROGRESS_TILES_SELECTOR = "[data-cds-composer-attachments] [data-cds-attachment],.epitaxy-attachment-pill";
  // Зона попадания номера: его прямоугольник плюс 4 точки вверх и вниз (ТЗ
  // WF84, п. 5). Над номерами 6 точек пустого поля — текст поля не задет.
  const PROGRESS_HIT_SLACK = 4;
  // «При прокручивании чата вверх-вниз это поле не менялось» (слово Элвиса
  // 23.09): строку состояния читаем, только когда лента у низа. Допуск свой,
  // не TAIL_SLACK = 2: у низа лента дрожит на пару точек при стриминге.
  const PROGRESS_TAIL_SLACK = 64;
  // Запомненные строки по ключу чата (смена чата при ленте не у низа).
  const PROGRESS_KEYS_MAX = 32;
  // Смена цвета номера и появление нового — 200 мс.
  const PROGRESS_BADGE_MS = 200;
  // Уже этого якорь считается вырожденным: React как раз пересобирает низ окна,
  // и рамка на кадр съезжает в ноль. Тогда полоса садится на запасной якорь.
  const PROGRESS_MIN_WIDTH = 80;
  // ---- ряд с прокруткой (WF85, #7356) ----------------------------------------
  // Слово Элвиса 24.09: «когда workflow много, нужно сделать прокрутку
  // горизонтальную и желательно показывать под номер последнего с
  // многоточием… Нельзя же столько по высоте занимать». Ряд всегда одна
  // строка: не влез и после слияния «1–k» — справа слот хвоста «… N», номера
  // едут вбок под колесом. За краем колесо идёт с сопротивлением 0,35 и не
  // дальше 32 точек; кадр ведёт ряд к цели долей 0,22; 140 мс без колеса —
  // цель пружиной возвращается в границы; 8 с после колеса ряд сам к текущему
  // номеру не едет. Строка колеса (deltaMode 1) — 16 точек.
  const PROGRESS_TAIL_ID = "myclaude-progress-tail";
  const PROGRESS_SCROLL_RESIST = 0.35;
  const PROGRESS_SCROLL_OVER = 32;
  const PROGRESS_SCROLL_EASE = 0.22;
  const PROGRESS_SCROLL_SPRING_MS = 140;
  const PROGRESS_SCROLL_HOLD_MS = 8000;
  const PROGRESS_SCROLL_LINE = 16;
  // Между окном номеров и хвостом — зазор ряда плюс поле обрезки ряда
  // (overflow-clip-margin 3): иначе обрезанный номер залезал бы вплотную к хвосту.
  const PROGRESS_SCROLL_CLIP = 3;

  // Разбор строки состояния.
  // Значки состояния из шаблона строки. Порядок — старшинство: 🛑 сильнее ✋,
  // ✋ сильнее ✅, ✅ сильнее 💭. Шаблон несёт один и тот же значок по краям,
  // поэтому спорить им обычно не о чем; старшинство решает те случаи, когда в
  // строку попало два разных.
  // ⚠️ — «жду» по правилу AGENTS.md 08.09 (#5663, «рука непонятна»); ✋ остаётся для старых строк.
  // Сверяем без селектора VS16 («⚠»): в строку он попадает не всегда.
  // ❓ — «жду» строки нового образца (ELVIS.md 23.09, #7188).
  const PROGRESS_STATES = [["🛑", "fail"], ["✋", "wait"], ["⚠", "wait"], ["❓", "wait"], ["✅", "done"], ["💭", "run"]];
  // Строка состояния НОВОГО образца (ELVIS.md 23.09, #7188): слово и значок в
  // КОНЦЕ — «⚪[Проект](docs/status.md) · WF 2 из 3 · идёт 💭». Слово перед
  // значком обязательно: строка расхода под ней («… · Opus 5.5 Extra 💭»)
  // кончается тем же значком, но слова у неё нет (критик WF84, Б1).
  const PROGRESS_TAIL_RE = /[·•]\s*(идёт|жду|готово|упал)\s*(💭|❓|✅|🛑)\s*$/u;
  const PROGRESS_TAIL_WORDS = { "идёт": "run", "жду": "wait", "готово": "done", "упал": "fail" };
  const PROGRESS_TAIL_WF_RE = /WF\s+(\d+)\s+из\s+(\d+)/;
  // «WF 6 из 7 · 40%»: счёт марафона и процент текущего воркфлоу. Процента может
  // не быть (готовый воркфлоу пишется без него). «WF» — тоже необязательно, но
  // без него счёт засчитывается только рядом с ✅: «5 из 5» без значка — это
  // обычная фраза из ответа, а не строка состояния.
  const PROGRESS_RE = /(WF\s+)?(\d+)\s+из\s+(\d+)(?:\s*[·•]\s*(\d+)\s*%)?/g;
  // Имя проекта в строке состояния — markdown-ссылка `[Имя](docs/status.md)`.
  // Просмотрщик обычно уже развернул её в текст, но в сыром виде она встречается.
  const PROGRESS_LINK_RE = /\[([^\]]{1,80})\]\([^)\s]*\)/g;
  // Имя проекта — текст между маркером-кружком и первым « · ». По нему подсказка
  // ищет сводку, присланную командой status.
  const projectFromLine = (line) => {
    const head = String(line ?? "").replace(PROGRESS_LINK_RE, "$1").split(/\s+[·•]\s+/)[0] ?? "";
    const hit = head.match(/[\p{L}\p{N}][^\n]*/u);
    return hit ? hit[0].trim().slice(0, 80) : "";
  };
  // Берём ПОСЛЕДНЕЕ совпадение в тексте: строка состояния стоит последней
  // строкой ответа, а выше по тексту легко встречается пересказ чужой строки.
  // Разбор текста целиком: info — что рисовать, stop — «строка состояния есть,
  // и воркфлоу в ней нет» (#7188): поиск по старым ответам на этом кончается,
  // иначе чат, закончивший марафон строкой «· готово ✅», показывал бы полосу
  // трёхответной давности.
  const progressScan = (text) => {
    const source = String(text ?? "");
    if (source === "") return { info: null, stop: false };
    let tail = null;
    let tailAt = -1;
    let offset = 0;
    for (const raw of source.split("\n")) {
      if (PROGRESS_TAIL_RE.test(raw)) { tail = raw; tailAt = offset; }
      offset += raw.length + 1;
    }
    const old = progressParseOld(source);
    // Берётся та строка, что стоит НИЖЕ: у одной и той же строки обе формы
    // совпадают по началу, и тогда слово в конце сильнее значка в начале.
    if (tail == null || (old && old.at > tailAt)) {
      if (old) delete old.at;
      return { info: old, stop: false };
    }
    const word = tail.match(PROGRESS_TAIL_RE)[1];
    const count = tail.match(PROGRESS_TAIL_WF_RE);
    // Строка без «WF N из M» (воркфлоу нет) полоске не годится, но её слово нужно рамке
    // «ждут твоего слова» (#8282): «жду ❓» чаще всего как раз без счёта.
    if (!count) return { info: null, stop: true, word: PROGRESS_TAIL_WORDS[word] ?? null };
    const wf = Number(count[1]);
    const of = Number(count[2]);
    if (!(wf >= 1 && of >= 1)) return { info: null, stop: true };
    const state = PROGRESS_TAIL_WORDS[word];
    const done = state === "done";
    const share = done ? 1 : (wf - 1) / of;
    const total = Math.round(Math.min(1, Math.max(0, share)) * 1000) / 10;
    return { info: { wf, of, pct: done ? 100 : null, total, state, project: projectFromLine(tail) }, stop: false };
  };
  const parseProgressText = (text) => progressScan(text).info;
  // Старые формы: значок в НАЧАЛЕ строки, «WF N из M» без значка, одиночный
  // воркфлоу со значком по краям. at — начало строки находки (для спора с
  // новой формой в progressScan).
  const progressParseOld = (source) => {
    let found = null;
    PROGRESS_RE.lastIndex = 0;
    for (let match = PROGRESS_RE.exec(source); match; match = PROGRESS_RE.exec(source)) {
      // Значок засчитывается только в НАЧАЛЕ той же строки — по шаблону AGENTS.md
      // он там и стоит. Раньше хватало значка где угодно в строке, и «Тесты: 222
      // из 222 ✅» или «- шаги 3 из 3 ✅» из обычного ответа красили всю полосу
      // зелёным «готово» посреди работы (находка ревизии 08.09). Ведущие пробелы
      // допускаем: в попапах строка приезжает из текста всего окна, с отступом.
      const from = source.lastIndexOf("\n", match.index) + 1;
      const end = source.indexOf("\n", match.index);
      const line = source.slice(from, end === -1 ? source.length : end);
      const head = line.trimStart();
      // ⚠️ — это «⚠» + VS16, и селектор в строку попадает не всегда: сверяем по
      // голому значку, как и весь PROGRESS_STATES.
      const hit = PROGRESS_STATES.find(([icon]) => head.startsWith(icon));
      const mark = hit ? hit[1] : null;
      // Хвост #5714, решено 08.09: «WF N из M» ВОВСЕ без значка так и остаётся «идёт».
      // Слово «WF» пишем только мы, а берётся ПОСЛЕДНЕЕ совпадение — настоящая строка
      // состояния в конце ответа перебивает случайное упоминание выше по тексту, и
      // требовать значок незачем. Строгость нужна там, где «WF» нет: «5 из 5» без
      // значка — обычная фраза, и её пускает только ✅.
      if (!match[1] && mark !== "done") continue;
      const wf = Number(match[2]);
      const count = Number(match[3]);
      if (!Number.isFinite(wf) || !Number.isFinite(count) || wf < 1 || count < 1) continue;
      const done = mark === "done";
      const raw = match[4] === undefined ? null : Number(match[4]);
      const pct = done ? 100 : (raw == null ? null : Math.min(100, Math.max(0, raw)));
      // Прогресс марафона: закрытые воркфлоу целиком плюс доля текущего.
      // Готово — сразу полная полоса, сколько бы процентов ни было написано
      // рядом.
      const share = done ? 1 : ((wf - 1) + (pct ?? 0) / 100) / count;
      const total = Math.round(Math.min(1, Math.max(0, share)) * 1000) / 10;
      found = { wf, of: count, pct, total, state: mark ?? "run", project: projectFromLine(line), at: from };
    }
    if (found) return found;
    // Одиночный воркфлоу: марафона нет, и кусок «WF N из M» в строке опущен
    // (AGENTS.md) — остаётся «💭⚪Проект · 40%💭». Такую строку узнаём строго, по
    // одному и тому же значку с обоих краёв: иначе «✅ покрытие 80%» из любого
    // ответа стало бы прогрессом. Сегмент у неё один.
    let at = 0;
    for (const raw of source.split("\n")) {
      const from = at;
      at += raw.length + 1;
      const line = raw.trim();
      if (line.length < 3) continue;
      const hit = PROGRESS_STATES.find(([icon]) => line.startsWith(icon) && line.endsWith(icon));
      if (!hit) continue;
      const percent = line.match(/(\d+)\s*%/);
      const done = hit[1] === "done";
      if (!percent && !done) continue;
      const pct = done ? 100 : Math.min(100, Math.max(0, Number(percent[1])));
      found = { wf: 1, of: 1, pct, total: pct, state: hit[1], project: projectFromLine(line), at: from };
    }
    return found;
  };

  // ---- сводка проектов (команда status) ------------------------------------
  // Страница файлов не читает — сводку присылает приложение командой
  // {action:"status", scope:"all", projects:[{name, text}]}, где text — сырой
  // markdown status.md проекта. Держим её в памяти окна (не в хранилище: сводка
  // живёт минуту до следующей команды и общей для окон быть не обязана) и
  // показываем в подсказке полосы для того проекта, чьё имя стоит в строке
  // состояния этого чата.
  // С WF201 (класс #9159: до страницы доходили ~5 свежих проектов) — 64 проекта и 128 КБ: Swift
  // (StatusFeed.totalLimit) поднимет свой потолок отдельным батчем; разбор — один раз на приход команды.
  const STATUS_MAX_PROJECTS = 64;
  const STATUS_MAX_TEXT = 8000;
  // Общий потолок на команду со стороны страницы: приложение своё режет само, но
  // верить ему на слово нельзя — разбор сводки идёт в главном потоке окна.
  const STATUS_MAX_TOTAL = 128 * 1024;
  // Блок воркфлоу в сводке начинается с номера-клавиши: «1️⃣ Workflow ✅ готово».
  // Номер — ЦЕПОЧКА клавиш, а не одна (WF22): «2️⃣9️⃣» это 29, «4️⃣0️⃣» — 40, «🔟» — 10.
  // Читалась первая клавиша, и весь четвёртый десяток сводки числился четвёртым
  // воркфлоу.
  const STATUS_HEAD_RE = /^((?:\d\uFE0F?\u20E3|\u{1F51F})+)\s*(.*)$/u;
  const STATUS_KEYCAP_RE = /\d\uFE0F?\u20E3|\u{1F51F}/gu;
  const STATUS_DEFAULT_ICON = "⬜";
  // Состояние блока по заголовку — ОДНО правило на всех разборщиков status.md (WF145 свёл его в Swift
  // PanelProjects.stateMarks/stateWords и tools/pimp.py DIGEST_MARKS/WORDS; WF152 — страница). Значок
  // сильнее слова, порядок — по силе: упал → ждёт Элвиса → впереди → готово → идёт. ⏳ — идёт (до WF152
  // его страница не знала, и идущий блок выходил «впереди»); ⬜ — впереди, не «ждёт». Слова — кусок
  // слова строчными, тот же порядок: «запланирован» — впереди раньше «планирования» — идёт. Ни значка,
  // ни слова — впереди. Состояния страницы: fail/wait/todo/done/run. PROGRESS_STATES (строка чата)
  // этим не заменяется: там значок стоит в начале строки, и ❌/⬜ из обычного ответа полосой не станут.
  const STATUS_HEAD_MARKS = [
    [["🛑", "❌"], "fail"],
    [["✋", "⚠", "❓", "🙋", "⏸"], "wait"],
    [["⬜"], "todo"],
    [["✅", "🟢"], "done"],
    [["💭", "⏳"], "run"],
  ];
  const STATUS_HEAD_WORDS = [
    [["упал", "стоп", "сломал"], "fail"],
    [["заплан", "впереди", "в очереди"], "todo"],
    [["ждёт", "жду", "пауз"], "wait"],
    [["готов", "выложен"], "done"],
    [["идёт", "кодинг", "критик", "проверк", "исследов", "планирован", "ревизи"], "run"],
  ];
  const statusHeadState = (heading) => {
    const head = String(heading ?? "");
    for (const [marks, state] of STATUS_HEAD_MARKS) {
      const mark = marks.find(item => head.includes(item));
      if (mark) return { icon: mark, state };
    }
    const text = head.toLowerCase();
    for (const [words, state] of STATUS_HEAD_WORDS) {
      if (words.some(word => text.includes(word))) return { icon: "", state };
    }
    return { icon: "", state: "todo" };
  };
  // Четыре этапа воркфлоу (AGENTS.md): по ним заливается идущий сегмент и
  // строится карточка. Пятая роль в сводке («макет» и подобные) на заливку не
  // влияет и в карточку не идёт — этапов по букве Элвиса ровно четыре. Имена — его
  // словами (WF160, #9159: «планирование, критик, кодинг и тест»); роль «проверка» — тот же «тест».
  const STATUS_STAGES = [
    // «план», не «планирование» (#9195, слово Элвиса 09.10 02:35: «мне важно знать не „планирование“, а „план“»).
    { key: "plan", label: "план", re: /^план/i },
    // «ревизия», «ревью» — тот же критик, «гейт» — тот же тест (WF198:
    // роль «ревизия · 1 агент · Opus 5.5 high» у Dictator не попадала ни в один этап — модели не было видно).
    { key: "critic", label: "критик", re: /^(?:критик|ревизи|ревью|review)/i },
    { key: "code", label: "кодинг", re: /^кодинг/i },
    { key: "check", label: "тест", re: /^(?:проверк|тест|гейт)/i },
  ];
  // Колонка имени этапа в карточке: самое длинное — «кодинг» 13 px 600, ~48 точек (WF175: «план»
  // вместо «планирование», колонка была 100 под него).
  const PROGRESS_CARD_LABEL = 60;
  // Хвост строки роли — эффорт. Слово `extra` стоит здесь ради уже написанных
  // файлов (#5907): карточка показывает `xhigh` словами Claude Code («Extra»), и
  // где-то в сводке это слово могли записать сразу так — без него «Fable Extra»
  // перестало бы читаться как модель с эффортом вовсе.
  const STATUS_EFFORT_RE = /\s(low|medium|high|xhigh|extra|max)$/i;
  // Строка «обновлено 12:40» под заголовком сводки — единственная дата в
  // файле (AGENTS.md: не сегодня — «вчера 03:10» или число «15.09»). По ней
  // карточка решает, можно ли сказать «15 мин назад» (progressWhen, WF70):
  // относительные слова честны только у сегодняшнего файла. Шапка счёта
  // («4 воркфлоу», «2 готово», «1,4 ч») больше не читается: подвал с ней
  // Элвис убрал (#6247) — он путал, цифры про проект стояли под карточкой
  // одного воркфлоу.
  const STATUS_UPDATED_RE = /^обновлено:?\s+(.+)$/iu;
  const STATUS_UPDATED_DATE_RE = /^(\d{1,2}[./]\d{1,2}(?:[./]\d{2,4})?)/;
  const STATUS_UPDATED_CLOCK_RE = /^\d{1,2}:\d{2}(?![\d:])/;
  // «12:40» и «сегодня 12:40» → сегодня, «вчера 03:10» → вчера, «15.09» → дата;
  // ничего из этого не разобрали — null, и карточка говорит абсолютным временем.
  // Границу слова даёт взгляд вперёд: `\b` кириллицы не знает.
  const statusUpdated = (text) => {
    const tail = String(text ?? "").trim();
    const yesterday = tail.match(/^вчера(?![\p{L}])\s*(.*)$/iu);
    if (yesterday) return { kind: "yesterday", time: yesterday[1].trim() };
    const today = tail.match(/^сегодня(?![\p{L}])\s*(.*)$/iu);
    if (today) return { kind: "today", time: today[1].trim() };
    const date = tail.match(STATUS_UPDATED_DATE_RE);
    if (date) return { kind: "date", time: date[1] };
    const clock = tail.match(STATUS_UPDATED_CLOCK_RE);
    if (clock) return { kind: "today", time: clock[0] };
    return null;
  };
  const statusFeed = { at: 0, projects: new Map() };
  // «Сейчас: …» и «Ждёт Элвиса: …» (или «Ждёт пользователя: …» — так пишет
  // чат не у Элвиса) — строкой, не пунктом списка; жирное начертание и маркер
  // пункта на всякий случай прощаем.
  const STATUS_TAIL_LINE_RE = /^(?:[-*]\s+)?(?:\*\*)?(Сейчас|Ждёт (?:Элвиса|пользователя)):(?:\*\*)?\s*(.*)$/u;

  // Номер воркфлоу, с которого начинается строка сводки: «3️⃣ …» → 3, «🔟 …» → 10,
  // «2️⃣9️⃣ …» → 29. Разбираем по цифрам клавиш, а не по готовому значку: в сводке
  // встречается и запись без вариационного селектора («3⃣»), и та и другая — один
  // и тот же номер.
  const statusLineNumber = (line) => {
    const head = String(line ?? "").match(STATUS_HEAD_RE);
    if (!head) return null;
    let digits = "";
    for (const cap of head[1].match(STATUS_KEYCAP_RE) ?? []) {
      digits += cap === "\u{1F51F}" ? "10" : (cap.match(/\d/)?.[0] ?? "");
    }
    const number = Number(digits);
    return digits !== "" && Number.isFinite(number) ? number : null;
  };
  // Строка роли: «- кодинг · 2 агента · Opus max». Кто (агенты) и на чём (модель,
  // эффорт) стоят в любом порядке, части может не быть вовсе («- кодинг · Opus
  // max», «- проверка · 🔴 **Fable max**»). Значок 💭 в конце — необязательная
  // пометка идущего этапа (правило AGENTS.md пишет чат Max).
  const statusRole = (item) => {
    const running = /💭\s*$/.test(item);
    const parts = item.replace(/💭\s*$/, "").split(/\s*[·•]\s*/).map(part => part.trim()).filter(Boolean);
    const rest = parts.slice(1);
    const agentsAt = rest.findIndex(part => /аген/i.test(part) || part === "я" || part.startsWith("я "));
    // Жирное начертание и красный кружок «Fable max» — разметка сводки, а не имя
    // модели: снимаем их здесь, рисует их карточка сама.
    const who = rest.filter((part, index) => index !== agentsAt).join(" · ")
      .replace(/\*\*/g, "").replace(/^[^\p{L}\p{N}]+/u, "").trim();
    const effort = who.match(STATUS_EFFORT_RE);
    return {
      role: parts[0] ?? "",
      agents: agentsAt >= 0 ? rest[agentsAt] : "",
      model: effort ? who.slice(0, who.length - effort[0].length).trim() : who,
      effort: effort ? effort[1] : "",
      running,
    };
  };
  // Сводка написана списками, а не таблицей, поэтому разбираем построчно:
  // заголовок блока даёт номер и значок, первый пункт — «о чём», пункты с
  // разделителем и словом впереди — роли, «шаги N из M» и время — свои поля.
  // Разбор ОДИН на двух читателей (WF22): объекты блоков для карточки и
  // заливки и дата обновления файла (updated, WF70). Порядок проверок внутри
  // цикла менять нельзя — на нём стоят блоки и роли.
  const statusParse = (text) => {
    const blocks = [];
    let updated = null;
    let current = null;
    // Хвостовые строки для Элвиса (WF84, #7205): «Сейчас: …» и «Ждёт Элвиса: …».
    // Их пишет чат где угодно в файле, приложение с правкой S-K переносит их в
    // шапку сводки. Берётся ПОСЛЕДНЯЯ каждого вида; блоки и роли от них не
    // меняются.
    let nowLine = "";
    let waitFor = "";
    const flush = () => { if (current) blocks.push(current); current = null; };
    for (const raw of String(text ?? "").split("\n")) {
      const line = raw.trim();
      const title = line.match(STATUS_HEAD_RE);
      if (title) {
        flush();
        const head = statusHeadState(title[2]);
        current = {
          number: statusLineNumber(line), mark: title[1],
          icon: head.icon || STATUS_DEFAULT_ICON, state: head.state,
          about: "", steps: null, time: "", roles: [], past: [],
        };
        continue;
      }
      const tail = line.match(STATUS_TAIL_LINE_RE);
      if (tail) {
        const value = tail[2].replace(/\*\*/g, "").trim();
        if (value) { if (/^Сейчас/u.test(tail[1])) nowLine = value; else waitFor = value; }
        continue;
      }
      if (!current) {
        // До первого блока — строка «обновлено …», первая и единственная.
        const stamp = updated ? null : line.match(STATUS_UPDATED_RE);
        if (stamp) updated = statusUpdated(stamp[1]);
        continue;
      }
      if (!/^[-*]\s/.test(line)) continue;
      const item = line.replace(/^[-*]\s*/, "").trim();
      if (!item) continue;
      const steps = item.match(/^шаги\s+(\d+)\s+из\s+(\d+)/i);
      if (steps && !current.steps) current.steps = { done: Number(steps[1]), total: Number(steps[2]) };
      // «- прошлые шаги: планирование · я · Opus max; критика · 1 агент · Fable xhigh»
      // (шаблон AGENTS.md). Раньше вся строка становилась одной ролью с именем
      // «прошлые шаги: планирование», и на карточке у закрытых этапов стоял
      // прочерк — Элвис 13.09: «галочки стоят, а кто это делал, непонятно»
      // (#5977). Режем по «;» и разбираем каждый кусок как обычную роль. Ветка
      // стоит ДО «о чём»: сводку пишут люди и агенты, порядок пунктов в блоке
      // не гарантирован. Примета без `\w`: кириллицы он не знает вовсе.
      if (/^прошл\S*\s+шаг/i.test(item)) {
        current.past = item.replace(/^[^:]*:\s*/, "").split(/\s*;\s*/)
          .map(part => part.trim()).filter(part => part.includes("·"))
          .map(statusRole);
        continue;
      }
      if (!current.about && !/^шаги\b/i.test(item) && !/\d\s*:\s*\d/.test(item)) {
        current.about = item.replace(/^о\s+чём\s*:\s*/i, "");
        continue;
      }
      if (!current.time && /\d\s*:\s*\d/.test(item)) { current.time = item; continue; }
      const role = item.split(/\s*[·•]\s*/)[0] ?? "";
      if (item.includes("·") && !item.includes("→") && role && !/\d/.test(role)) current.roles.push(statusRole(item));
    }
    flush();
    return { blocks, updated, now: nowLine, waitFor };
  };
  const statusBlocks = (text) => statusParse(text).blocks;
  // Имя проекта в строке состояния и имя папки, которое прислало приложение,
  // совпадают не побуквенно (регистр, дефисы). Сравниваем по буквам и цифрам.
  const statusKey = (name) => String(name ?? "").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "");
  // Точное имя выигрывает всегда, а по началу имени отвечаем ТОЛЬКО когда такой
  // сосед один (WF22): «VkusnoffKz» рядом с «VkusnoffKz-deploy» выбирался
  // алфавитом, то есть случайно.
  const statusFeedProject = (project) => {
    const key = statusKey(project);
    if (!key) return null;
    let near = null;
    let count = 0;
    for (const [name, item] of statusFeed.projects) {
      const other = statusKey(name);
      if (!other) continue;
      if (other === key) return item;
      if (other.startsWith(key) || key.startsWith(other)) { near = item; count += 1; }
    }
    return count === 1 ? near : null;
  };
  // Команда снаружи: разбираем сразу, а не при показе карточки — разбор дешевле
  // раза в минуту, чем на каждое движение мыши.
  const runStatusCommand = (detail) => {
    const list = Array.isArray(detail?.projects) ? detail.projects : null;
    if (!list) return false;
    const next = new Map();
    let budget = STATUS_MAX_TOTAL;
    for (const item of list.slice(0, STATUS_MAX_PROJECTS)) {
      const name = typeof item?.name === "string" ? item.name.trim().slice(0, 80) : "";
      const text = typeof item?.text === "string" ? item.text.slice(0, STATUS_MAX_TEXT) : "";
      if (!name || !text) continue;
      // Потолок выбран — остальные проекты отбрасываем целиком: половина сводки
      // в карточке хуже, чем её отсутствие.
      budget -= name.length + text.length;
      if (budget < 0) break;
      next.set(name, statusParse(text));
    }
    statusFeed.projects = next;
    statusFeed.at = Date.now();
    progressState.cardText = "";
    progressCardUI.text = "";
    // Со сводкой меняется и заливка идущего сегмента — она считается по этапам
    // блока (WF22). Перерисовываем полосу сразу, а не ждём страховочного
    // перечёта через десять секунд.
    try { placeProgress(); } catch {}
    if (progressState.tipOpen) { try { progressTipShow(); } catch {} }
    return true;
  };

  const progressState = {
    info: null, reason: "полоса ещё не считалась", at: 0, runs: 0, timer: 0, pulse: 0,
    // Найденная рамка поля, доли номеров (segments — для гейта: 100 готовый,
    // доля шагов у идущего, 0 впереди), номера как нарисованы (badges), место
    // ряда на экране и наведение (только курсор).
    frame: null, shell: null, segments: [], badges: [], gap: PROGRESS_BADGE_GAP, box: null, hovering: false,
    // Подсказка: какой номер открыт кликом (порядок в ряду, с нуля) и открыта ли
    // она вообще. Наведение карточку не показывает — только клик (WF12, п. 3).
    tipSegment: null, tipOpen: false, tipTick: 0,
    // Карточка (WF84, 9.1): её слепок, дышит ли она, строки этапов, строка
    // «сейчас», на что она встала — над полем или над номерами — и сколько
    // шагов подгонки под потолок сделано.
    cardText: "", cardPulse: false, cardBreathe: false, cardRows: [], cardNote: null, cardAnchor: null, cardFit: 0,
    // На чём сейчас сидит ряд: "рамка" или запасное "строка инструментов".
    anchor: null,
    // Место под ряд: рамка, которой добавили нижнее поле, её собственное поле
    // до нашей правки и сколько точек добавили сверху.
    roomNode: null, roomBase: 0, room: 0,
    // «Замереть у низа» (WF84): строка читается только у низа ленты. key — чей
    // чат прочитан, lastByKey — последнее прочитанное по ключу чата (потолок
    // PROGRESS_KEYS_MAX), source — откуда info на экране, frozen — ряд стоит,
    // потому что лента не у низа, atBottom — лента у низа (или её нет), blocks —
    // принята ли сводка (сверка номеров, progressFeedBlocks).
    key: null, lastByKey: new Map(), source: "нет", frozen: false, atBottom: true, blocks: false,
  };
  // Прокрутка ряда (WF85, #7356): on — режим прокрутки, x — сдвиг номеров
  // сейчас, target — куда их ведёт кадр, max — предел сдвига, view — окно
  // номеров на экране {left, right}, tail — хвост «… N» виден, user — последний
  // сдвиг от колеса, wheelAt — когда было колесо, key — для чего последний раз
  // ставилось «своё место» (номер, окно, число номеров), raf/spring — кадр и
  // пружина, wheel — висит ли слушатель колеса.
  const progressScroll = {
    on: false, x: 0, target: 0, max: 0, view: null, tail: false, user: false, wheelAt: 0, key: null,
    raf: 0, spring: 0, wheel: false,
  };

  // Полосу, подсказку и карточку сносим по id, как ручку и стили: упавшая на
  // середине установка оставляет их в окне, а реестра отмены у них уже нет.
  // Нижнее поле рамки — по метке: рамка чужая, сносить её нельзя, только
  // вернуть ей своё поле.
  for (const id of [PROGRESS_ID, PROGRESS_TIP_ID, PROGRESS_CARD_ID, PROGRESS_TAIL_ID]) {
    for (const orphan of document.querySelectorAll(`#${id}`)) orphan.remove();
  }
  for (const node of document.querySelectorAll(`[${PROGRESS_ROOM_ATTRIBUTE}]`)) {
    node.style.removeProperty("padding-bottom");
    node.style.removeProperty(PROGRESS_ROOM_VARIABLE);
    node.removeAttribute(PROGRESS_ROOM_ATTRIBUTE);
  }

  const progressBar = document.createElement("div");
  progressBar.id = PROGRESS_ID;
  // Никакого aria-live: ряд меняется на каждом ответе, и VoiceOver проговаривал
  // бы его без остановки (довод донора). Подпись ряда (aria-label) — словами:
  // «Воркфлоу: 1 готов, 2 идёт, 3 ждёт тебя» (ТЗ WF84, п. 5).
  progressBar.setAttribute("role", "img");
  // Стили — прямо в узел, без <style>: CSP страницы может не пустить нашу
  // таблицу (см. state.cssOk в разделе 4), а element.style ей неподвластен.
  for (const [name, value] of Object.entries({
    position: "fixed", display: "none", left: "0px", top: "0px", width: "0px",
    height: `${PROGRESS_BADGE_HEIGHT}px`, "align-items": "center", "justify-content": "flex-start",
    // Лишнее по ширине (длинный марафон в узком окне) обрезаем, но с полями
    // в 3 точки: обводка выбранного номера лежит на точку снаружи номера.
    gap: `${PROGRESS_BADGE_GAP}px`, overflow: "clip", "overflow-clip-margin": "3px",
    "pointer-events": "none", "z-index": "2147483645",
    // Ряд чуть приглушён, наведение — во всю силу (ТЗ WF84, п. 5).
    opacity: "0.85",
    // Сама коробка не анимируется НИКОГДА: место и ширину ей задаёт геометрия
    // окна (resize, ручка, смена якоря), и переход тут означал бы, что ряд
    // ползёт за краем поля ввода с опозданием. Пишем это прямым объявлением, а
    // не молчанием: страница вправе объявить переход на всё подряд.
    transition: "none",
  })) progressBar.style.setProperty(name, value);
  (document.body ?? document.documentElement).appendChild(progressBar);
  track(() => progressBar.remove());

  // Коробка карточки. Потолок высоты — 60 % окна, прокрутки нет намеренно:
  // узел прозрачен для мыши, колесо до него не доходит. Ширину и место считает
  // progressTipShow — над полем ввода и не шире его (WF84, 9.1).
  //
  // Карточка воркфлоу (WF84, вариант 9.1 макета docs/9-card-opus-5.5.html,
  // ТЗ docs/design-card-wf84.md): шапка «номер · плашка», «о чём», слева
  // дорожка этапов в столбик — кружок на этап и отрезки между ними (пройденное
  // зелёное, идущее акцентом и дышит, ждёт — жёлтое, упал — красное, впереди —
  // пустой контур), под текущим этапом одна строка из status.md («Твой ход: …»
  // или «Сейчас:»), внизу строка «когда» (WF70). Действий в карточке нет (слово
  // Элвиса 23.09: «Чат, план, отчёт, пауза — что такое?»). Узлы строим один раз
  // и потом только переписываем текст и стили.
  //
  // С WF160 (#9159, слово Элвиса 08.10 ~23:38: «стандартное подменю Workflow… какие модели, кто что
  // делает… Раньше было пизже») — этапы и модели; рисует узлы progressCardPaint. Номер в шапке —
  // капсулой, как в ряду, а не словом «Воркфлоу N» (правило №2 SkilZZZ/INTERFACES.md: один знак на объект).
  // Свой aria-hidden и никаких role/data-state: и раздел 16 (Escape), и
  // progressCovered ловят открытые накладки по role="dialog"/data-state="open" —
  // назовись карточка так, она сама себя и накрыла бы.
  const cardNode = (parent, styles) => {
    const node = document.createElement("div");
    for (const [name, value] of Object.entries(styles)) node.style.setProperty(name, value);
    parent.appendChild(node);
    return node;
  };
  // Строка «сейчас»: 12px, приставка «Твой ход:» отдельным узлом. Пустая —
  // display:none в самом узле (hidden слабее объявленного display). С WF160 (критик: «…» в узком
  // поле) — целиком, с переносом, без line-clamp и без среза: карточка растёт вверх.
  const progressNoteNode = (parent, extra = {}) => {
    const note = cardNode(parent, {
      "font-size": "12px", "line-height": "1.35", margin: "-3px 0 7px", padding: "0", position: "relative",
      display: "none", "white-space": "normal", "overflow-wrap": "anywhere", ...extra,
    });
    const prefix = document.createElement("span");
    prefix.style.setProperty("font-weight", "650");
    note.appendChild(prefix);
    const text = document.createElement("span");
    note.appendChild(text);
    return { note, prefix, text };
  };
  const progressCardUI = (() => {
    const tip = document.createElement("div");
    tip.id = PROGRESS_TIP_ID;
    tip.setAttribute("aria-hidden", "true");
    for (const [name, value] of Object.entries({
      position: "fixed", display: "none", left: "0px", top: "0px",
      // box-sizing своим объявлением: ширину карточке считаем сами, и хозяйская
      // раскладка страницы (content-box) вынесла бы её за край на поля и рамку.
      "box-sizing": "border-box",
      padding: "11px 13px 10px", "border-radius": "12px", "border-width": "1px", "border-style": "solid",
      font: "13px/1.4 -apple-system, system-ui, sans-serif", "white-space": "normal",
      "overflow-wrap": "anywhere", overflow: "hidden", "pointer-events": "none", "z-index": "2147483646",
    })) tip.style.setProperty(name, value);
    (document.body ?? document.documentElement).appendChild(tip);
    track(() => tip.remove());
    const card = document.createElement("div");
    card.id = PROGRESS_CARD_ID;
    card.setAttribute("aria-hidden", "true");
    // Верхних детей карточки ровно четыре: шапка, «о чём», этапы, «когда».
    const head = cardNode(card, {
      display: "flex", "align-items": "center", "column-gap": "10px", "row-gap": "4px", "flex-wrap": "wrap",
    });
    // Номер — капсула ряда, крупнее (цвета — progressCardPaint: цветом состояния, как номер в ряду).
    const title = cardNode(head, {
      display: "inline-block", "box-sizing": "border-box", height: "18px", "min-width": "22px", padding: "0 5px",
      "border-radius": "4px", font: "600 12px/18px -apple-system, system-ui, sans-serif",
      "font-variant-numeric": "tabular-nums", "text-align": "center", "white-space": "nowrap",
    });
    const where = cardNode(head, { "font-size": "12px" });
    // Плашка: точка цвета состояния и слово без эмодзи («идёт кодинг», «ждёт тебя»).
    const pill = cardNode(head, {
      display: "inline-flex", "align-items": "center", gap: "6px",
      "border-radius": "999px", padding: "1px 10px 1px 8px", "font-size": "12px", "font-weight": "650",
      "white-space": "nowrap",
    });
    const dot = cardNode(pill, {
      width: "6px", height: "6px", "border-radius": "50%", flex: "0 0 auto", "box-sizing": "border-box",
    });
    const pillText = cardNode(pill, {});
    // «О чём» — полностью, без многоточия и line-clamp (слово Элвиса 23.09, #7205):
    // это одна строка status.md, обычно до трёх строк карточки; длиннее — просто
    // переносится, не режется. Подгонка под потолок (progressCardFit) её не трогает.
    const about = cardNode(card, {
      "margin-top": "5px", display: "block", "white-space": "normal", "overflow-wrap": "anywhere",
    });
    const stages = cardNode(card, { "margin-top": "7px" });
    // Четыре строки этапов: [подсветка, дорожка[отрезок, кружок[знак, ореол]],
    // этап, кто, сейчас[приставка, текст]]. Колонка этапа — под самое длинное слово
    // («кодинг»; WF175); «кто» переносится, а не режется многоточием (#9158).
    const rows = STATUS_STAGES.map(() => {
      const row = cardNode(stages, {
        display: "grid", "grid-template-columns": `20px ${PROGRESS_CARD_LABEL}px minmax(0, 1fr)`, "column-gap": "8px",
        position: "relative",
      });
      const hl = cardNode(row, {
        position: "absolute", left: "24px", right: "-7px", top: "0", bottom: "0", "border-radius": "7px",
        display: "none", "pointer-events": "none", transition: "background-color 200ms",
      });
      const track = cardNode(row, { "grid-row": "1 / span 2", "grid-column": "1", position: "relative", "min-height": "28px" });
      const line = cardNode(track, { position: "absolute", left: "9px", width: "2px", top: "23px", bottom: "-5px", "border-radius": "1px" });
      const node = cardNode(track, {
        position: "absolute", left: "3px", top: "7px", width: "14px", height: "14px", "border-radius": "50%",
        display: "flex", "align-items": "center", "justify-content": "center", "box-sizing": "border-box",
        font: "800 9px/1 -apple-system, system-ui, sans-serif",
        transition: "background-color 200ms, color 200ms, box-shadow 200ms",
      });
      const glyph = cardNode(node, { "border-radius": "50%" });
      const halo = cardNode(node, { position: "absolute", inset: "-4px", "border-radius": "50%", display: "none", "pointer-events": "none" });
      const label = cardNode(row, {
        "grid-column": "2", "grid-row": "1", "line-height": "28px", "font-size": "13px", "font-weight": "600",
        "white-space": "nowrap", position: "relative", transition: "color 200ms",
      });
      const who = cardNode(row, {
        // Кто и модель — мельче, кеглем подписей (#9195: «модель ты сильно крупно сделал»; было 12).
        "grid-column": "3", "grid-row": "1", "line-height": "16px", padding: "6px 0", "font-size": "11px",
        "white-space": "normal", "overflow-wrap": "anywhere", "min-width": "0", position: "relative",
      });
      const note = progressNoteNode(row, { "grid-column": "2 / -1", "grid-row": "2" });
      return { row, hl, track, line, node, glyph, halo, label, who, ...note };
    });
    // Пятый узел этапов: строка «сейчас», когда этапа у воркфлоу нет (ролей в
    // блоке не записано) — встаёт под этапами отдельной строкой.
    const spare = progressNoteNode(stages, { margin: "2px 0 0" });
    // «Когда» — одна человеческая строка про ЭТОТ воркфлоу («Завершился 15 мин
    // назад · занял 50 мин», progressWhen, WF70, #6247). С переносом и без среза
    // (WF160: «…» нет нигде): в окне 280 она просто встаёт в две строки. Подвал —
    // второстепенное (правило №15 INTERFACES): обычным начертанием, приглушённо.
    // Показ (display) переписывается при каждой смене текста: атрибут hidden прячет
    // узел правилом `[hidden]{display:none}`, а оно слабее объявления в самом узле.
    const when = cardNode(card, {
      "margin-top": "8px", "padding-top": "7px", "border-top-width": "1px", "border-top-style": "solid",
      "font-size": "12.5px", "font-weight": "400", display: "block", "white-space": "normal",
    });
    tip.appendChild(card);
    // Дыхание карточки (ТЗ 9.1, п. 7): ореол кружка идущего этапа, подсветка его
    // строки и точка в плашке — три слота, такт общий с номером в ряду. text — слепок
    // показанного (ключ перерисовки), fit — шаг подгонки, states — состояния строк этапов.
    return {
      tip, card, head, title, where, pill, dot, pillText, about, stages, rows, spare, when,
      slots: { halo: { anim: null }, hl: { anim: null }, dot: { anim: null } },
      text: "", fit: 0, states: [], note: null, breathe: false,
    };
  })();
  const {
    tip: progressTip, card: progressCard, title: progressCardTitle, where: progressCardWhere, pill: progressCardPill,
    dot: progressCardDot, pillText: progressCardPillText, about: progressCardAbout, stages: progressCardStages,
    rows: progressCardRows, spare: progressCardSpare, when: progressCardWhen,
  } = progressCardUI;

  // Цвет полосы — акцент окна (accentColor, раздел 2а): оформление красится им
  // ещё на восстановлении слоёв — то есть до этого раздела.
  const progressAccent = accentColor;
  // Номер на залитой капсуле по макету тёмный — но только там, где он читается:
  // у светлых тем акцент тёмный («Апельсин» #a31000), и чёрная цифра на нём
  // пропадает. Из двух цветов берём тот, что контрастнее (WCAG, contrastRatio).
  // Акцент приходит тройкой в hsl(…) (accentColor) или hex; иное — тёмный.
  const PROGRESS_INK_DARK = "#0b0d10";
  const PROGRESS_INK_LIGHT = "#ffffff";
  const progressHex = color => {
    const text = String(color ?? "").trim();
    if (/^#[0-9a-f]{3,8}$/i.test(text)) return normalizeHex(text, "#000000");
    const hsl = text.match(/^hsla?\(\s*([\d.]+)(?:deg)?[\s,]+([\d.]+)%[\s,]+([\d.]+)%/i);
    if (hsl) return hexFromHsl(Number(hsl[1]), Number(hsl[2]) / 100, Number(hsl[3]) / 100);
    // rgb(…) и голая тройка «77,187,125» (тона кожи карточки) — тоже цвет.
    const rgb = text.match(/^(?:rgba?\(\s*)?(\d{1,3})[\s,]+(\d{1,3})[\s,]+(\d{1,3})\s*(?:[,/)]|$)/i);
    if (!rgb) return null;
    return `#${rgb.slice(1, 4).map(part => Math.min(255, Number(part)).toString(16).padStart(2, "0")).join("")}`;
  };
  const progressInk = paint => {
    const hex = progressHex(paint);
    if (!hex) return PROGRESS_INK_DARK;
    return contrastRatio(hex, PROGRESS_INK_DARK) >= contrastRatio(hex, PROGRESS_INK_LIGHT)
      ? PROGRESS_INK_DARK : PROGRESS_INK_LIGHT;
  };

  // Кромка, на которой сидит полоса. Сама .epitaxy-prompt бывает обёрткой без
  // границы, а рамку рисует её потомок (border или box-shadow) — садиться надо
  // на ту кромку, которую видит глаз. Ищем неглубоко и с ограничением по числу
  // узлов: проход зовётся до четырёх раз в секунду.
  const PROGRESS_FRAME_SELECTOR = ".epitaxy-prompt";
  const PROGRESS_FRAME_DEPTH = 3;
  const PROGRESS_FRAME_BUDGET = 32;
  const PROGRESS_FRAME_SLACK = 24;
  const framePainted = (node) => {
    let computed = null;
    try { computed = getComputedStyle(node); } catch { return false; }
    if (!computed) return false;
    if ((parseFloat(computed.borderBottomWidth) || 0) > 0) return true;
    const shadow = String(computed.boxShadow ?? "");
    return shadow !== "" && shadow !== "none";
  };
  const paintedChild = (root) => {
    const base = root.getBoundingClientRect();
    let level = [root];
    let budget = PROGRESS_FRAME_BUDGET;
    for (let depth = 0; depth < PROGRESS_FRAME_DEPTH && level.length > 0 && budget > 0; depth += 1) {
      const next = [];
      for (const node of level) {
        for (const kid of node.children ?? []) {
          if (budget <= 0) break;
          budget -= 1;
          const rect = kid.getBoundingClientRect();
          // Рамка — во всю ширину поля и с тем же низом. Всё, что заметно уже
          // (кнопки, значки), не рамка и внутрь себя её не прячет.
          if (rect.width < base.width - PROGRESS_FRAME_SLACK) continue;
          if (Math.abs(rect.bottom - base.bottom) <= PROGRESS_FRAME_SLACK && framePainted(kid)) return kid;
          next.push(kid);
        }
      }
      level = next;
    }
    return null;
  };
  // Коробка, в которой живёт САМО поле: от редактора вверх до первой
  // обведённой (border или box-shadow) коробки во всю ширину. Её низ глаз и
  // видит низом поля, и к нему липнет полоса (#6890).
  //
  // Почему не ищем сверху вниз: у paintedChild рамкой считается только та
  // коробка, чей низ совпадает с низом .epitaxy-prompt (допуск 24 точки), а под
  // полем стоит строка модели. Живой замер 21.09: расхождение 26 точек — и
  // рамкой становился сам .epitaxy-prompt, полоса съезжала ПОД строку модели.
  // Стоило строке стать на пару точек ниже — и полоса прыгала обратно на поле.
  const editorFrame = (root) => {
    const start = state.editorRoot?.isConnected ? state.editorRoot
      : (state.editor?.isConnected ? state.editor : null);
    if (!start || !root.contains(start)) return null;
    const base = root.getBoundingClientRect();
    for (let node = start; node && node !== root; node = node.parentElement) {
      const rect = node.getBoundingClientRect();
      if (rect.width < base.width - PROGRESS_FRAME_SLACK) continue;
      if (framePainted(node)) return node;
    }
    return null;
  };

  const progressFrame = (block) => {
    const shell = state.shell?.isConnected && block.contains(state.shell) ? state.shell : null;
    const cached = progressState.frame;
    // Кэш годится, пока жива и сама найденная рамка, и та рамка поля, от которой
    // мы её нашли: React пересобирает низ окна целиком.
    if (cached?.isConnected && block.contains(cached) && progressState.shell === shell) return cached;
    progressState.shell = shell;
    let root = shell?.closest?.(PROGRESS_FRAME_SELECTOR) ?? null;
    if (!root?.isConnected) root = block.querySelector(PROGRESS_FRAME_SELECTOR);
    if (!root?.isConnected) root = shell;
    if (!root?.isConnected) return null;
    // Коробка поля сильнее общего поиска: она и есть та кромка, к которой
    // полоса липнет. Нет её (чужая разметка, Claude Code) — прежний путь.
    progressState.frame = editorFrame(root) ??
      (framePainted(root) ? root : (paintedChild(root) ?? root));
    return progressState.frame;
  };

  // Меню модели и effort раскрываются вверх ровно над этой границей, а полоса
  // висит поверх страницы и рисовалась бы сквозь них. Хит-тест, как у ручки
  // (раздел 8), здесь не нужен: полоса ничего не ловит мышью, хватает
  // пересечения с открытым меню или модалкой. Сверяем всю высоту ряда.
  const progressCovered = (top, bottom, left, right) => {
    for (const node of document.querySelectorAll(OVERLAY_SELECTOR)) {
      const rect = node.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) continue;
      if (rect.top <= bottom + 2 && rect.bottom >= top - 2 && rect.left <= right && rect.right >= left) return true;
    }
    return false;
  };

  // ---- сегмент ↔ блок сводки (WF22, по номеру с WF70) ------------------------
  // Сперва ПО НОМЕРУ: с 15.09 status.md держит воркфлоу только ЭТОГО чата и
  // нумерует их с единицы (AGENTS.md), так что номер сегмента «WF N из M» и
  // номер блока — один и тот же счёт. Пока сводка нумеровала по проекту,
  // соединяли по значку, и готовый или запланированный сегмент часто
  // оставался без блока: карточка писала «ещё не расписан», хотя в status.md
  // всё есть (#6130, #5884). Блока с таким номером нет (старые и архивные
  // сводки) — прежний путь по значку.
  const progressBlockAt = (info, number) => {
    if (!info) return null;
    const blocks = statusFeedProject(info.project)?.blocks ?? [];
    if (blocks.length === 0) return null;
    const own = blocks.find(block => block.number === number);
    if (own) return own;
    // Идущий блок — ПОСЛЕДНИЙ с 💭 в заголовке: в сводке рядом легко висит
    // недописанный старый.
    let runAt = -1;
    for (let index = 0; index < blocks.length; index += 1) if (blocks[index].state === "run") runAt = index;
    // Идущий сегмент — он же. ✋ и 🛑 в сводке значков не имеют: чат ждёт Элвиса
    // или упал на том же самом блоке, который в сводке помечен 💭.
    if (info.state !== "done" && number === info.wf) return runAt >= 0 ? blocks[runAt] : null;
    // Готовый сегмент k из D — k-й с ХВОСТА среди ✅: последние готовые блоки
    // проекта и есть воркфлоу этого чата. Свой номер карточка называет честно.
    const doneCount = info.state === "done" ? info.of : info.wf - 1;
    if (number <= doneCount) {
      const done = blocks.filter(block => block.state === "done");
      return done[done.length - 1 - (doneCount - number)] ?? null;
    }
    // Будущий — ⬜ с головы, но только те, что стоят ПОСЛЕ идущего.
    const todo = blocks.filter((block, index) => block.state === "todo" && index > runAt);
    return todo[number - info.wf - 1] ?? null;
  };
  // Четыре этапа блока и который из них идёт. Явная пометка 💭 в строке роли
  // сильнее порядка записи; её нет — идущим считаем ПОСЛЕДНИЙ записанный этап
  // (по шаблону AGENTS.md роли дописывают по мере прохождения).
  const progressStages = (block) => {
    const rows = STATUS_STAGES.map(stage => ({
      key: stage.key, label: stage.label,
      // Роль ищем сперва среди текущих, потом среди прошлых шагов: у закрытых
      // этапов «кто» живёт только там (#5977).
      role: block?.roles.find(role => stage.re.test(role.role))
        ?? block?.past?.find(role => stage.re.test(role.role)) ?? null,
    }));
    let now = rows.findIndex(row => row.role?.running);
    if (now < 0) for (let index = 0; index < rows.length; index += 1) if (rows[index].role) now = index;
    return { rows, now };
  };
  // Какие этапы показывает карточка (WF198, #9159, слово Элвиса 08.10 ~23:38: «шаги три из трёх…
  // Я там четыре шага вижу»): только те, что у Workflow есть, — записанные ролью; ролей меньше, чем
  // «шаги N из M», — добираем до M по частоте в сводках (кодинг, тест, критик, план). Ни ролей, ни
  // числа шагов — все четыре, как было. Ответ — номера строк progressStages по порядку.
  const PROGRESS_STAGE_FILL = [2, 3, 1, 0];
  const progressStagesShown = (rows, steps) => {
    const shown = new Set(rows.flatMap((row, index) => (row.role ? [index] : [])));
    const total = Number(steps?.total);
    if (!(total > 0) && !shown.size) return rows.map((row, index) => index);
    for (const index of PROGRESS_STAGE_FILL) if (shown.size < total && index < rows.length) shown.add(index);
    return [...shown].sort((x, y) => x - y);
  };
  // Заливка идущего сегмента (буква 1A): не проценты — их в строке состояния
  // больше нет (AGENTS.md 07.09), — а ПРОЙДЕННЫЕ ЭТАПЫ из четырёх. Каждый этап
  // четверть, идущий даёт половину своей четверти. Ролей в блоке нет — считаем
  // по «шаги N из M»; нет и их — минимум, чтобы сегмент вообще был виден (#5543).
  const PROGRESS_MIN_FILL = 8;
  // Потолок ширины карточки: в широком окне она остаётся такой же компактной, как в
  // узком (слово Элвиса 07.09 22:50).
  const PROGRESS_CARD_MAX_WIDTH = 400;
  // «О чём» с WF84 (#7205) не режется — только пробелы в одну строку (progressLine); с WF160
  // и «сейчас» тоже (срез «…» по числу знаков — progressClip — снят).
  const progressLine = text => String(text ?? "").replace(/\s+/g, " ").trim();
  const progressBlockFill = (block) => {
    if (!block) return null;
    if (block.state === "done") return 100;
    const { rows, now } = progressStages(block);
    // Роли записаны все разом и без 💭, а «шаги 0 из M» — этапы ещё не пройдены:
    // без этого сводка WF22 давала 87,5 % на нулевом шаге (проверка WF22, риск 1).
    const marked = rows.some(row => row.role?.running);
    const unstarted = !marked && block.steps != null && block.steps.done === 0;
    if (now >= 0 && !unstarted) return (now + 0.5) * (100 / rows.length);
    if (block.steps && block.steps.total > 0) return block.steps.done / block.steps.total * 100;
    return null;
  };
  const progressFill = (info) => {
    if (!info) return 0;
    if (info.state === "done") return 100;
    // Процент из строки состояния сильнее сводки: его пишут чаты, которые ещё не
    // перечитали правила, и врать про них незачем.
    const share = info.pct != null ? info.pct : progressBlockFill(progressBlockAt(info, info.wf));
    return Math.max(PROGRESS_MIN_FILL, Math.min(100, share ?? 0));
  };

  // ---- состояние каждого номера (WF84, ТЗ docs/design-strip-wf84.md, п. 2) ----
  // Две вести, и ни одна не зависит от места в ленте. Чат сообщает строкой
  // состояния (счёт M, текущий N, слово текущего), проект — сводкой status.md
  // (блок на каждый номер со своим значком — в том числе два 💭 разом).
  //
  // Сводку берём, только если она СЕГОДНЯШНЯЯ (строка «обновлено 12:40» или
  // сегодняшнее число) и её номера ровно покрывают 1…M: блоков меньше M, больше
  // M или номер повторился — это сводка чужого чата того же проекта или старая
  // форма, и номера рисуются по одной строке (не выдумываем, чего нет в обоих).
  const progressFeedToday = (feed, nowMs = Date.now()) => {
    const updated = feed?.updated;
    if (!updated) return false;
    if (updated.kind === "today") return true;
    if (updated.kind !== "date") return false;
    const at = new Date(nowMs);
    return Number.isFinite(at.getTime()) && progressDateIsToday(updated.time, at);
  };
  const progressFeedBlocks = (info, count) => {
    const feed = statusFeedProject(info?.project);
    if (!feed || !progressFeedToday(feed)) return null;
    const numbered = feed.blocks.filter(block => block.number != null);
    if (numbered.length !== count) return null;
    const seen = new Set();
    for (const block of numbered) {
      if (block.number < 1 || block.number > count || seen.has(block.number)) return null;
      seen.add(block.number);
    }
    return numbered;
  };
  // Состояние блока → вид номера. ⬜ в сводке — «впереди» (plan).
  const PROGRESS_BADGE_OF = { done: "done", run: "run", wait: "wait", fail: "fail", todo: "plan" };
  // Правило слияния на КАЖДЫЙ номер k (ТЗ, п. 2): «готово ✅» строки закрывает
  // все; есть блок k принятой сводки — его состояние (для k = N строка сильнее
  // по правилу WF70, progressBlockState); блока нет — по строке: до N готов,
  // N — слово строки, после — впереди. share — ширина линии шагов идущего
  // (100 у готового, 0 впереди).
  const progressBadgeStates = (info) => {
    const count = Math.max(1, Math.min(PROGRESS_SEG_MAX, Math.round(info.of) || 1));
    const wf = Math.max(1, Math.min(count, Math.round(info.wf) || 1));
    const blocks = info.state === "done" ? null : progressFeedBlocks(info, count);
    const states = [];
    const shares = [];
    for (let number = 1; number <= count; number += 1) {
      const block = blocks ? blocks.find(item => item.number === number) ?? null : null;
      let state = "plan";
      if (info.state === "done") state = "done";
      else if (block) state = PROGRESS_BADGE_OF[number === wf ? progressBlockState(block, info, number) : block.state] ?? "plan";
      else state = number < wf ? "done" : (number === wf ? (PROGRESS_BADGE_OF[info.state] ?? "run") : "plan");
      let share = state === "done" ? 100 : 0;
      if (state === "run") {
        share = number === wf ? progressFill(info)
          : Math.max(PROGRESS_MIN_FILL, Math.min(100, progressBlockFill(block) ?? 0));
      }
      states.push(state);
      shares.push(share);
    }
    return { states, shares, blocks: Boolean(blocks) };
  };
  // Номера ряда с подгонкой под ширину (ТЗ, п. 3): зазор 4, не влезает — 3,
  // всё равно не влезает — первые подряд готовые сливаются в один «1–9» (вид
  // готового, клик — карточка последнего из слитых). Идущие, ждущие и упавшие
  // не сливаются никогда. avail — ширина ряда в точках (нет рамки — без
  // предела). Чистая функция: её гоняют тесты.
  // Ширина ряда номеров с зазорами — та же арифметика у подгонки и у прокрутки.
  const progressRowNeed = (list, gap) => list.reduce((sum, item) => sum + progressBadgeWidth(item.label), 0) +
    gap * Math.max(0, list.length - 1);
  const progressBadges = (info, avail = Infinity) => {
    if (!info) return { items: [], gap: PROGRESS_BADGE_GAP, blocks: false };
    const { states, shares, blocks } = progressBadgeStates(info);
    let items = states.map((state, index) => ({
      n: index + 1, first: index + 1, last: index + 1, label: String(index + 1), state, share: shares[index],
    }));
    const need = progressRowNeed;
    let gap = PROGRESS_BADGE_GAP;
    if (need(items, gap) > avail) {
      gap = PROGRESS_BADGE_GAP_TIGHT;
      if (need(items, gap) > avail) {
        let lead = 0;
        while (lead < items.length && items[lead].state === "done") lead += 1;
        if (lead >= 2) {
          const label = `1–${lead}`;
          items = [{ n: label, first: 1, last: lead, label, state: "done", share: 100, merged: true }, ...items.slice(lead)];
        }
      }
    }
    return { items, gap, blocks };
  };
  // Подпись ряда словами (ТЗ, п. 5): «Воркфлоу: 1 готов, 2 идёт, 3 ждёт тебя».
  const PROGRESS_BADGE_WORDS = { done: "готов", run: "идёт", wait: "ждёт тебя", fail: "упал", plan: "впереди" };
  const progressAria = items => `Воркфлоу: ${items.map(item => `${item.label} ${PROGRESS_BADGE_WORDS[item.state] ?? ""}`.trim()).join(", ")}`;

  // ---- пульс идущего этапа (WF22, буква 1A) --------------------------------
  // Дышит ОТДЕЛЬНЫЙ слой, а не тень или фон: анимировать box-shadow значит
  // перерисовывать тень каждый кадр, а прозрачность composited-слоя ничего не
  // стоит. Ключевые кадры — Web Animations (element.animate): своей таблицы
  // стилей у полосы нет и заводить её нельзя (CSP страницы, раздел 4), а
  // @keyframes без таблицы не бывает.
  // Вдох и выдох за 3600 мс — примерно 17 дыханий в минуту, спокойный
  // человеческий ритм (слово Элвиса 08.09 вечер: «очень плавное, не
  // отвлекающее»). Прежние 2400 читались подмигиванием. Такт ОДИН на всё окно —
  // номер в ряду и карточка (решение WF84: ТЗ полоски писало 2400, карточки —
  // 3600, согласовано 3600).
  const PROGRESS_PULSE_MS = 3600;
  // Синусоида, а не мигание: easing стоит у КАЖДОГО кадра, а не в options.
  // Общий easing растянул бы весь круг разом, и на вершине вышел бы угол —
  // ровно то моргание, от которого уходим; покадровый ease-in-out даёт нулевую
  // скорость и в нижней точке, и в верхней. Все кадры идут от выдоха к вдоху и
  // обратно — вершина у всех слоёв в одной точке такта.
  const progressBreath = (low, high = "1") => [
    { opacity: low, easing: "ease-in-out" }, { opacity: high, easing: "ease-in-out" }, { opacity: low },
  ];
  // Линия шагов идущего номера: 0,45 → 1 (ТЗ, п. 3).
  const PROGRESS_LINE_FRAMES = progressBreath("0.45");
  // Карточка (ТЗ 9.1, п. 7): ореол кружка, подсветка строки, точка в плашке.
  const PROGRESS_HALO_FRAMES = progressBreath("0.18");
  const PROGRESS_HL_FRAMES = progressBreath("0.35");
  const PROGRESS_DOT_FRAMES = progressBreath("0.3");
  // Скрытое окно и «поменьше движения» в системе гасят пульс: Electron всё равно
  // придушит таймеры перекрытого окна, а анимация останется висеть.
  const progressMotionOk = () => {
    if (document.hidden) return false;
    try { return !matchMedia("(prefers-reduced-motion: reduce)").matches; } catch { return true; }
  };
  // slot — любой объект с полем anim (номер или слот карточки): вторую анимацию
  // на тот же узел не заводим, а снимаем ровно свою.
  //
  // Фаза общая (ТЗ 9.1, п. 7): у каждой анимации startTime = 0 — все с одной
  // длительностью идут от начала шкалы документа, и два идущих номера, кружок,
  // строка и точка вдыхают вместе, даже если открыты в разное время.
  const progressPulse = (slot, node, on, frames, rest) => {
    if (!node) return;
    if (!on || !progressMotionOk()) {
      if (slot.anim) { try { slot.anim.cancel(); } catch {} slot.anim = null; }
      node.style.setProperty("opacity", rest);
      return;
    }
    if (slot.anim) return;
    try {
      slot.anim = node.animate(frames, { duration: PROGRESS_PULSE_MS, iterations: Infinity });
      try { slot.anim.startTime = 0; } catch {}
    } catch { slot.anim = null; node.style.setProperty("opacity", rest); }
  };
  // Живые номера слева направо.
  const progressCells = [];
  // Покой слоёв карточки, когда она не дышит (ТЗ 9.1, п. 7).
  const progressCardRest = { halo: "0.6", hl: "1", dot: "1" };
  const progressCardPulse = on => {
    const ui = progressCardUI;
    const row = ui.rows[ui.states.findIndex(state => state === "run")] ?? null;
    progressPulse(ui.slots.halo, row?.halo ?? null, on && row != null, PROGRESS_HALO_FRAMES, progressCardRest.halo);
    progressPulse(ui.slots.hl, row?.hl ?? null, on && row != null, PROGRESS_HL_FRAMES, progressCardRest.hl);
    progressPulse(ui.slots.dot, ui.dot, on, PROGRESS_DOT_FRAMES, progressCardRest.dot);
  };
  const progressCardPulseStop = () => {
    for (const slot of Object.values(progressCardUI.slots)) {
      if (slot.anim) { try { slot.anim.cancel(); } catch {} slot.anim = null; }
    }
  };
  // Пересобрать пульсы по тому, что уже решил последний проход: зовётся на
  // visibilitychange, где меняется не ряд, а только право двигаться.
  const progressPulseSync = () => {
    for (const item of progressCells) progressPulse(item, item.line, item.pulse, PROGRESS_LINE_FRAMES, "1");
    if (!progressState.tipOpen) { progressCardPulseStop(); return; }
    progressCardPulseStop();
    progressCardPulse(progressState.cardBreathe === true);
    progressState.cardPulse = Boolean(progressCardUI.slots.dot.anim);
  };
  on(document, "visibilitychange", () => { try { progressPulseSync(); } catch {} });
  // Снятие: анимация переживает и удаление узла из разметки, и dispose().
  track(() => {
    for (const item of progressCells) {
      if (item.anim) { try { item.anim.cancel(); } catch {} item.anim = null; }
    }
    progressCardPulseStop();
  });

  // Узел номера: цифра и линия шагов идущего (2 точки у нижнего края, ширина —
  // доля шагов). Рождается прозрачным и без переходов: цвета ему впишет тот же
  // проход progressApply, и вписать их надо мгновенно, а проявиться — за
  // 200 мс (ТЗ, п. 3).
  const PROGRESS_BADGE_TRANS = `background-color ${PROGRESS_BADGE_MS}ms ease, color ${PROGRESS_BADGE_MS}ms ease, ` +
    `box-shadow ${PROGRESS_BADGE_MS}ms ease, opacity ${PROGRESS_BADGE_MS}ms ease`;
  const progressCell = () => {
    const cell = document.createElement("div");
    for (const [name, value] of Object.entries({
      position: "relative", flex: "0 0 auto", "box-sizing": "border-box", height: `${PROGRESS_BADGE_HEIGHT}px`,
      "min-width": `${PROGRESS_BADGE_MIN}px`, padding: "0 3px", "border-radius": "3px", overflow: "hidden",
      "text-align": "center", font: `600 9px/${PROGRESS_BADGE_HEIGHT}px -apple-system, system-ui, sans-serif`,
      "font-variant-numeric": "tabular-nums", "white-space": "nowrap", "pointer-events": "none",
      "outline-offset": "1px", opacity: "0", transition: "none",
    })) cell.style.setProperty(name, value);
    const num = document.createElement("span");
    num.style.setProperty("position", "relative");
    const line = document.createElement("div");
    for (const [name, value] of Object.entries({
      position: "absolute", left: "0", bottom: "0", height: "2px", width: "0%", display: "none",
      "pointer-events": "none", transition: "width 400ms linear",
    })) line.style.setProperty(name, value);
    cell.appendChild(num);
    cell.appendChild(line);
    return { cell, num, line, anim: null, pulse: false, born: true };
  };
  // Пул: число номеров меняется только с марафоном, но узел — это и его цвет с
  // переходом; лишние хвостом уходят сразу, недостающие проявляются.
  const progressBuild = (count) => {
    while (progressCells.length > count) {
      const item = progressCells.pop();
      if (item.anim) { try { item.anim.cancel(); } catch {} item.anim = null; }
      item.cell.remove();
    }
    while (progressCells.length < count) {
      const item = progressCell();
      progressBar.appendChild(item.cell);
      progressCells.push(item);
    }
  };

  // Гасим карточку И забываем выбранный сегмент. Раньше снимался только display,
  // а `tipOpen` оставался true — и хвост progressApply (`if (progressState.tipOpen)
  // progressTipShow()`) возвращал карточку на экран САМ, без клика, как только в
  // ленте снова появлялась строка состояния: перешёл по сайдбару в другой чат — и
  // она выскочила поверх поля ввода с чужим воркфлоу (находка ревизии 08.09).
  // Открывается карточка только кликом Элвиса.
  const progressTipHide = () => {
    progressState.tipOpen = false;
    progressState.tipSegment = null;
    progressState.cardRows = [];
    progressState.cardNote = null;
    progressState.cardAnchor = null;
    progressCardUI.states = [];
    progressTipTickStop();
    progressState.cardPulse = false;
    progressState.cardBreathe = false;
    progressCardPulseStop();
    // Закрытие мгновенное (ТЗ 9.1, п. 7): переход появления снимаем.
    progressTip.style.setProperty("transition", "none");
    if (progressTip.style.display !== "none") progressTip.style.setProperty("display", "none");
    // Обводка выбранного номера уходит вместе с карточкой.
    for (const item of progressCells) item.cell.style.setProperty("outline", "none");
  };
  // Коробки номеров на экране: живой прямоугольник узла, а в стенде (узлы без
  // раскладки) — та же арифметика, что поставила им ширину (progressApply).
  // Сдвиг прокрутки (WF85) живой прямоугольник уже несёт в себе (translateX) —
  // вычитаем его только в арифметике, иначе номер сдвинулся бы дважды.
  const progressBadgeBoxes = () => {
    const box = progressState.box;
    const items = progressState.badges;
    if (!box || items.length === 0) return [];
    const boxes = [];
    let left = box.left - (progressScroll.on ? progressScroll.x : 0);
    for (let index = 0; index < items.length; index += 1) {
      const width = progressBadgeWidth(items[index].label);
      let rect = null;
      try { rect = progressCells[index]?.cell.getBoundingClientRect() ?? null; } catch {}
      if (rect && rect.width > 0) boxes.push({ left: rect.left, right: rect.right });
      else boxes.push({ left, right: left + width });
      left += width + (progressState.gap ?? PROGRESS_BADGE_GAP);
    }
    return boxes;
  };
  // Номер под точкой x: его прямоугольник плюс половина зазора с каждой
  // стороны (ТЗ, п. 5). Мимо номеров, но в ряду — номер текущего воркфлоу N.
  // В режиме прокрутки (WF85) ловятся только номера, видные в окне номеров, а
  // мимо них — ничего: текущий мог уехать за край, и карточка встала бы к
  // номеру, которого не видно.
  const progressSegmentAt = (x) => {
    const items = progressState.badges;
    if (!progressState.box || items.length === 0) return null;
    const half = (progressState.gap ?? PROGRESS_BADGE_GAP) / 2;
    const boxes = progressBadgeBoxes();
    const view = progressScroll.on ? progressScroll.view : null;
    if (view && (x < view.left || x > view.right)) return null;
    for (let index = 0; index < boxes.length; index += 1) {
      if (view && (boxes[index].right <= view.left || boxes[index].left >= view.right)) continue;
      if (x >= boxes[index].left - half && x <= boxes[index].right + half) return index;
    }
    if (view) return null;
    const wf = progressState.info?.wf ?? 1;
    const current = items.findIndex(item => wf >= item.first && wf <= item.last);
    return current >= 0 ? current : items.length - 1;
  };
  // Состояние ОДНОГО воркфлоу словом: до текущего — готов, после — запланирован,
  // сам текущий — по значку строки состояния. ✅ у всего марафона закрывает всё.
  // Так считается, когда блока сводки на сегмент нет; нашёлся — состояние даёт
  // блок (progressBlockState).
  const PROGRESS_WORDS = { done: "готов", run: "идёт", wait: "ждёт", fail: "упал", todo: "запланирован" };
  const progressWord = (info, number) => {
    if (info.state === "done" || number < info.wf) return "готов";
    if (number > info.wf) return "запланирован";
    return PROGRESS_WORDS[info.state] ?? "идёт";
  };
  // Состояние найденного блока — из ЕГО заголовка, а не из счёта чата (WF70):
  // у VkusnoffKz три блока 💭 при строке «WF 1 из 3», и второй сегмент по счёту
  // выходил «запланирован», хотя в сводке он идёт. Одно исключение — текущий
  // сегмент при ⚠️/🛑 в строке состояния: в сводке таких значков нет, чат ждёт
  // Элвиса или упал на том же блоке, что помечен 💭, и бейдж обязан сказать
  // «ждёт тебя» (слово Элвиса 07.09 22:50).
  const progressBlockState = (block, info, number) => {
    if (block.state === "run" && number === info.wf && (info.state === "wait" || info.state === "fail")) {
      return info.state;
    }
    // Строка чата уже говорит 💭/⚠️/🛑 на этом воркфлоу, а заголовок блока ещё ⬜
    // (оркестратор не переписал) — верим строке: иначе полоса пульсирует «идёт», а
    // карточка на том же сегменте твердит «Ещё не начат» (проверка WF70).
    if (block.state === "todo" && number === info.wf && ["run", "wait", "fail"].includes(info.state)) {
      return info.state;
    }
    return block.state;
  };
  // Номер воркфлоу по номеру в ряду: обычно это его порядок, а у слитого «1–9»
  // — последний из слитых (ТЗ, п. 3).
  const progressNumberAt = (index) => {
    const info = progressState.info;
    if (!info) return null;
    const items = progressState.badges;
    if (items.length === 0) return Math.max(1, Math.min(info.of || 1, (index ?? 0) + 1));
    const item = items[Math.min(items.length - 1, Math.max(0, index ?? 0))];
    return item.last;
  };
  // Эмодзи в карточке с WF84 нет (9.1: состояние читается кружком дорожки и
  // точкой плашки). Слово плашки — по состоянию.
  const PROGRESS_CARD_PILL = { done: "готов", run: "идёт", wait: "ждёт тебя", fail: "упал", todo: "запланирован" };
  // Блока про этот воркфлоу в присланных сводках не нашлось. Раньше здесь стояло
  // «сводки нет», и Элвис читал это как поломку (08.09, #5807: «он же неспроста
  // там ячейка стоит»). Ячейка правда есть: её место в счёте чата уже написано в
  // заголовке и строке под ним, и остаётся сказать честно — про сам воркфлоу
  // ещё ничего не записано. Ключ — слово состояния из progressWord.
  const PROGRESS_CARD_BLANK = {
    "запланирован": "ещё не расписан — что в нём будет, запишем, когда дойдёт очередь",
    "готов": "уже сделан — что в нём было, не записали",
  };
  // Идущий (ждущий, упавший) без блока — ничего не пишем (#7188: «пока не
  // записан» Элвис читал как «воркфлоу нет, а полоска врёт»).
  const PROGRESS_CARD_BLANK_ANY = "";
  // Кожа карточки — ЗАПАСНАЯ (цвета темы не прочитались) и источник тонов G/Y/R
  // тройками (готово, ждёт, упал). С WF84 фон, текст и акцент берутся от темы
  // окна (progressTextColor, progressFieldColor, accentColor); синий `run`
  // отсюда больше не рисуется.
  const PROGRESS_CARD_SKIN = {
    dark: {
      back: "#33373f", line: "rgba(255,255,255,.16)", text: "#eef0f4", dim: "#aab0bc",
      shadow: "0 18px 44px rgba(0,0,0,.62),0 2px 6px rgba(0,0,0,.45)",
      run: "126,160,255", ok: "77,187,125", wait: "245,197,66", fail: "238,106,95", todo: "150,155,165",
    },
    light: {
      back: "#ffffff", line: "rgba(20,24,32,.16)", text: "#171a20", dim: "#666c7a",
      shadow: "0 18px 44px rgba(20,24,32,.24),0 2px 6px rgba(20,24,32,.12)",
      run: "47,98,216", ok: "31,154,90", wait: "196,138,0", fail: "204,58,48", todo: "130,136,150",
    },
  };
  // Эффорт словами самого Claude Code (#5907). У ползунка Effort пять делений —
  // Low · Medium · High · Extra · Max, — а сводки пишут «xhigh»: Элвис это слово
  // не читает («он не выкупит, короче»). Переводим ТОЛЬКО на показе: файлы
  // сводок пишут и читают агенты, и там слово остаётся прежним. Чего в списке
  // нет, не выдумываем — показываем как написано.
  const PROGRESS_EFFORT_WORDS = {
    low: "Low", medium: "Medium", high: "High", xhigh: "Extra", extra: "Extra", max: "Max",
  };
  // «×1» в конце записи модели: «Fable xhigh ×1». Знак берём и математический, и
  // латинскую «x», и кириллическую «х» — диктуется голосом, пишется по-разному.
  const PROGRESS_TIMES_RE = /\s*[×xх*]\s*(\d+)\s*$/i;
  // Сколько моделей помещается в колонку «кто»: в окне 280 она 126 точек, и
  // третья запись уводит строку на третью строчку карточки. Остаток прячем за
  // «и ещё N».
  const PROGRESS_WHO_MODELS = 2;
  // Одна запись «кто»: «Fable xhigh ×1» → Fable Extra, счёт 1. Счёт здесь
  // необязателен — у «- проверка · 🔴 **Fable max**» его нет вовсе.
  const progressModel = (text) => {
    const line = String(text ?? "").replace(/\s+/g, " ").trim();
    if (!line) return null;
    const times = line.match(PROGRESS_TIMES_RE);
    const name = (times ? line.slice(0, line.length - times[0].length) : line).trim();
    if (!name) return null;
    const effort = name.match(STATUS_EFFORT_RE);
    const model = effort ? name.slice(0, name.length - effort[0].length).trim() : name;
    const word = effort ? (PROGRESS_EFFORT_WORDS[effort[1].toLowerCase()] ?? effort[1]) : "";
    return {
      text: [model, word].filter(Boolean).join(" "),
      count: times ? Number(times[1]) : null,
      // Fable max — красный кружок и жирным (слово Элвиса 04.09 21:10): по нему
      // видно, где потрачена дорогая модель. Примета считается по записи, так
      // что и в списке из двух моделей она не теряется.
      fable: /fable/i.test(model) && /^max$/i.test(effort?.[1] ?? ""),
    };
  };
  // Сколько агентов стояло на этапе: «1 агент», «2 агента» → число. «я» числа не
  // даёт — это слово Элвиса про себя, оно и остаётся словом.
  const progressAgentsCount = (text) => {
    const digits = String(text ?? "").match(/\d+/);
    return digits ? Number(digits[0]) : null;
  };
  // Кто делал этап. Раньше строка читалась как «2 агента · Opus max» и «2 агента
  // · Fable xhigh ×1, Fable high ×1» — Элвис попросил убрать и «N агентов», и
  // «×N» (#5908): число стоит ПОСЛЕ модели, «Opus Max 2», «Fable Extra 1, Fable
  // High 1». Нет ни того ни другого — показываем модель без числа.
  // Этап, пропущенный явно: роль записана словом «пропущен» / «пропуск» («- критик · пропущен»).
  const progressSkipped = role => Boolean(role) && /(?:^|[\s·])пропу(?:щ|ск)/iu.test(` ${role.agents ?? ""} ${role.model ?? ""} ${role.effort ?? ""}`);
  const progressWho = (role) => {
    if (!role) return { text: "—", fable: false };
    // Режем список ТОЛЬКО по запятой и точке с запятой. Раньше в разделители
    // входила и «·», а ею Codex/Astra разделяет части одной записи («project_audit
    // независимо, root по интерфейсу · gpt-6-astra») — половинки занимали оба
    // места, и имя модели пропадало с карточки вовсе.
    const models = [role.model, role.effort].filter(Boolean).join(" ")
      .split(/\s*[,;]\s*/).map(progressModel).filter(Boolean);
    const agents = progressAgentsCount(role.agents);
    // Счёт агентов из строки роли годится, только когда модель одна и своего
    // числа у неё нет: у списка «×1, ×1» числа уже стоят при моделях, а сумма их
    // и есть те самые «2 агента».
    if (models.length === 1 && models[0].count === null && agents !== null) models[0].count = agents;
    // Знак «×» перед числом вернул Элвис 13.09 (#5976): «Opus Max 1» он читает
    // как номер версии модели, а «Opus Max ×1» — как «одна штука». Само
    // «N агентов» при этом не возвращается, уходил именно счётчик словами.
    const shown = models.slice(0, PROGRESS_WHO_MODELS)
      .map(item => [item.fable ? `🔴 ${item.text}` : item.text, item.count === null ? "" : `×${item.count}`]
        .filter(Boolean).join(" "));
    const rest = models.length - shown.length;
    const list = [shown.join(", "), rest > 0 ? `и ещё ${rest}` : ""].filter(Boolean).join(" ");
    // «я» остаётся впереди и через точку: «я · Fable Extra» (слово Элвиса).
    // Число агентов уходит к модели — но только если модель вообще написана:
    // у голого «- кодинг · 2 агента» сказать больше нечего, и строку показываем
    // как есть, а не прочерком.
    // «я» остаётся, даже когда рядом стоит число («я + 1 агент»): иначе Элвис
    // пропадал бы со своей же строки плана.
    const mine = /(^|[\s+])я([\s+]|$)/u.test(String(role.agents ?? ""));
    const word = mine ? "я"
      : (models.length === 0 || agents === null ? String(role.agents ?? "").trim() : "");
    const text = [word, list].filter(Boolean).join(" · ");
    // Красный кружок и жирное — примета ПОКАЗАННЫХ записей: спряталась за «и ещё
    // N» — и жирной строки быть не должно, иначе непонятно, за что она жирная.
    return { text: text || "—", fable: models.slice(0, PROGRESS_WHO_MODELS).some(item => item.fable) };
  };
  // Строка времени блока: «21:15 → закончит примерно в 23:30 · идёт 45 мин». Слово
  // «примерно» Элвис попросил убрать (#5909) — в шаблоне правил его больше нет,
  // но в десятках уже написанных сводок оно осталось, поэтому чистим на показе.
  // Границу слова тут даёт взгляд вперёд, а не `\b`: `\b` в JS считает словом
  // только латиницу с цифрами, и у кириллицы он не срабатывает вовсе.
  const progressTime = (text) => String(text ?? "")
    .replace(/\s*примерно(?![\p{L}\p{N}])/giu, "").replace(/\s+/g, " ").trim();
  // ---- строка «когда» (WF70, #6247) ------------------------------------------
  // Внизу карточки — одна человеческая строка про ЭТОТ воркфлоу: «Завершился
  // 15 мин назад · занял 50 мин», «Идёт 25 мин · начался в 13:05 · закончит в
  // 13:50», «Ждёт тебя · идёт 40 мин», «Ещё не начат». Стояли счёт проекта
  // («2 воркфлоу, 2 готово · 1,4 ч» — цифры про весь проект под карточкой одного
  // воркфлоу) и «09:45 → 10:35 · 50 мин · шаги 1 из 1» — Элвис: «оно путает»,
  // и что он сам эту строку не понимает. Часы «сейчас» функция получает снаружи и
  // сама их не спрашивает — чистая, тесты ставят любое «сейчас».
  //
  // Относительные слова («только что», «15 мин назад», «идёт 25 мин») — ТОЛЬКО
  // когда сводка обновлена сегодня (updated.kind === "today", строка «обновлено
  // 12:40» без даты) и отметка блока не позже «сейчас»; иначе честно абсолютом:
  // «Завершился вчера в 10:35», «Идёт · начался в 13:05». Отметка позже
  // «сейчас» у сегодняшнего файла — часы в сводке чужие (файл от вчера, который
  // не переписали), и считать от них назад нельзя.
  const PROGRESS_CLOCK_RE = /(\d{1,2})\s*:\s*(\d{2})/;
  // Часы «10:35» → минуты от полуночи и текст как написан; часов нет — null.
  const progressClock = (text) => {
    const hit = String(text ?? "").match(PROGRESS_CLOCK_RE);
    if (!hit) return null;
    const hours = Number(hit[1]);
    const minutes = Number(hit[2]);
    if (hours > 23 || minutes > 59) return null;
    return { at: hours * 60 + minutes, text: `${hit[1]}:${hit[2]}` };
  };
  // Длительность словами сводки (AGENTS.md): минуты до часа, дальше часы с
  // одним знаком и запятой — «50 мин», «1,5 ч», «2 ч».
  const progressSpan = (minutes) => {
    const whole = Math.max(0, Math.round(minutes));
    if (whole < 60) return `${whole} мин`;
    return `${String(Math.round(whole / 6) / 10).replace(".", ",")} ч`;
  };
  // Части строки времени: начало — часы слева от стрелки; справа либо конец
  // («10:35»), либо срок («закончит в 16:00»); хвост после последнего « · » —
  // длительность, как её записали («50 мин», «идёт 1,8 ч»).
  const progressTimeParts = (text) => {
    const line = progressTime(text);
    const arrow = line.indexOf("→");
    const dot = line.lastIndexOf("·");
    const body = dot >= 0 ? line.slice(0, dot) : line;
    const left = arrow >= 0 ? body.slice(0, arrow) : body;
    const right = arrow >= 0 ? body.slice(arrow + 1) : "";
    const finish = /закончит/iu.test(right);
    return {
      start: progressClock(left),
      end: finish ? null : progressClock(right),
      until: finish ? progressClock(right) : null,
      tail: dot >= 0 ? line.slice(dot + 1).trim() : "",
    };
  };
  // Когда файл не сегодняшний, «Завершился в 10:35» получает день: «вчера в
  // 10:35», «15.09 в 10:35».
  const progressDay = (updated) => {
    if (updated?.kind === "yesterday") return "вчера ";
    if (updated?.kind === "date" && updated.time) return `${updated.time} `;
    return "";
  };
  // «17.09», «17.09.2026», «17.09.26» — это дата `at`? Год без цифр — считаем этот.
  const progressDateIsToday = (text, at) => {
    const m = String(text ?? "").match(/^(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?/);
    if (!m) return false;
    const year = m[3] ? (m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3])) : at.getFullYear();
    return Number(m[1]) === at.getDate() && Number(m[2]) === at.getMonth() + 1 && year === at.getFullYear();
  };
  const progressWhen = (block, now, updated) => {
    if (!block) return "";
    if (block.state === "todo") return "Ещё не начат";
    const { start, end, until, tail } = progressTimeParts(block.time);
    const at = new Date(now);
    // «обновлено 17.09.2026» сегодняшним числом — тоже сегодня (проверка WF70):
    // Dictator и NightWolf пишут в шапку дату, а не часы.
    const today = Number.isFinite(at.getTime())
      && (updated?.kind === "today" || (updated?.kind === "date" && progressDateIsToday(updated.time, at)));
    const nowAt = at.getHours() * 60 + at.getMinutes();
    // Сколько минут прошло от отметки до «сейчас»; нельзя сказать — null.
    const since = (clock) => (today && clock && clock.at <= nowAt ? nowAt - clock.at : null);
    if (block.state === "done") {
      const gone = since(end);
      const head = gone === null
        ? (end ? `Завершился ${progressDay(updated)}в ${end.text}` : "Завершился")
        : (gone < 1 ? "Завершился только что" : `Завершился ${progressSpan(gone)} назад`);
      // «занял» — хвост строки, если это длительность («50 мин»); хвоста нет или
      // он не про то («идёт 1,8 ч» у блока, который закрыли, не переписав
      // время) — разница часов, через полночь с добавкой суток.
      const took = /^\d/.test(tail) ? tail
        : (start && end ? progressSpan((end.at - start.at + 1440) % 1440) : "");
      return took ? `${head} · занял ${took}` : head;
    }
    // Идёт, ждёт, упал: состояние уже на плашке шапки («идёт кодинг», «ждёт тебя», «упал») — здесь
    // его не повторяем (правило №5 INTERFACES, WF160), только когда: «Начался 25 мин назад, в 13:05»,
    // не сегодня — с днём («Начался вчера в 13:05»). Ждёт или упал — срок «закончит» ни о чём.
    const gone = since(start);
    const head = !start ? ""
      : (gone === null ? `Начался ${progressDay(updated)}в ${start.text}`
        : (gone < 1 ? "Начался только что" : `Начался ${progressSpan(gone)} назад, в ${start.text}`));
    if (block.state !== "run" || !until) return head;
    return head ? `${head} · закончит в ${until.text}` : `Закончит в ${until.text}`;
  };
  // ---- карточка 9.1: данные и вид (WF84, #7205) ------------------------------
  // Карточка не ýже 240 и не шире поля, ýже 320 — «узкая» (строки этапов 24 вместо 28).
  const PROGRESS_CARD_MIN_WIDTH = 240;
  const PROGRESS_CARD_NARROW = 320;
  const PROGRESS_CARD_WAIT_PREFIX = "Твой ход: ";
  // Воркфлоу k по одной строке чата, когда блока нет: до текущего — готов,
  // после — впереди, сам текущий — слово строки.
  const progressLineState = (info, number) => {
    if (info.state === "done" || number < info.wf) return "done";
    if (number > info.wf) return "todo";
    return info.state ?? "run";
  };
  // Данные карточки воркфлоу k (ТЗ полоски, п. 6) — всё из уже существующих
  // разборов (statusBlocks, statusParse, progressStages, progressWho); новых
  // разборов status.md здесь нет. waitFor — строка «Ждёт Элвиса:» сводки (только
  // у ждущего), now — строка «Сейчас:»; обе только у воркфлоу N из строки чата
  // и только у сегодняшней сводки. Приходят они в шапке команды status, если
  // её шлёт приложение с правкой S-K (StatusFeed.compact); без неё — пусто.
  const progressCardData = (number, info = progressState.info, nowMs = Date.now()) => {
    if (!info || number == null) return null;
    const feed = statusFeedProject(info.project);
    const block = progressBlockAt(info, number);
    const blockState = block ? progressBlockState(block, info, number) : null;
    const state = blockState ?? progressLineState(info, number);
    const stages = progressStages(block);
    const own = number === info.wf && progressFeedToday(feed, nowMs);
    return {
      number: block ? (block.number ?? number) : number, of: info.of, state,
      word: block ? (PROGRESS_WORDS[blockState] ?? "идёт") : progressWord(info, number),
      about: block?.about ?? "", steps: block?.steps ?? null,
      stages: stages.rows.map(row => ({
        name: row.label, who: progressWho(row.role).text,
        model: row.role?.model ?? "", effort: row.role?.effort ?? "", running: Boolean(row.role?.running),
      })),
      when: block ? progressWhen(blockState === block.state ? block : { ...block, state: blockState }, nowMs, feed?.updated) : "",
      waitFor: own && state === "wait" ? (feed?.waitFor ?? "") : "",
      now: own ? (feed?.now ?? "") : "",
      project: info.project ?? "", chatWord: PROGRESS_WORDS[info.state] ?? "идёт",
      source: progressState.source, frozen: progressState.frozen,
    };
  };
  // Вид карточки (ТЗ 9.1, п. 6): чистая функция без DOM, её гоняют тесты;
  // рисование (progressTipShow) только переносит результат в узлы.
  //
  // Состояние строк этапов — от СЫРОГО состояния блока: готовый — пройдены все
  // этапы (WF160, критик: этап без записанной роли — тоже пройден ✓, как было на
  // карточке у Элвиса; «пропущен» точкой — только когда роль так и записана:
  // «- критик · пропущен»); идёт, ждёт, упал (💭, ✋/⚠️/❓,
  // 🛑 в заголовке) — до текущего пройдены, текущий — состояние воркфлоу (так
  // ⚠️/🛑 строки чата красят кружок), после — впереди; запланированный (и ⬜,
  // который строка чата подняла в «идёт») — все впереди. Нет 💭 ни на одной
  // роли и «шаги 0 из M» — текущий первый этап (как `unstarted` у заливки):
  // запланированный блок пишет все роли разом, и без правила идущей
  // становилась «проверка».
  const progressCardView = (info, number, nowMs = Date.now()) => {
    const data = progressCardData(number, info, nowMs);
    if (!data) return null;
    const block = progressBlockAt(info, number);
    const state = data.state;
    const stages = progressStages(block);
    const marked = stages.rows.some(row => row.role?.running);
    // Строки — только этапы этого Workflow (progressStagesShown, WF198); состояние считается по всем четырём,
    // «не начат» — первый показанный этап.
    const shown = progressStagesShown(stages.rows, block?.steps);
    const now = !marked && block?.steps && block.steps.done === 0 ? shown[0] : stages.now;
    const raw = block?.state ?? null;
    const live = raw === "run" || raw === "wait" || raw === "fail";
    const passed = row => (progressSkipped(row.role) ? "skip" : "done");
    const rows = stages.rows.map((row, index) => {
      let rowState = "todo";
      if (raw === "done") rowState = passed(row);
      else if (live && now >= 0) {
        if (index < now) rowState = passed(row);
        else if (index === now) rowState = state === "done" || state === "todo" ? raw : state;
      }
      // Роли нет — «кто» пусто, а не «—» (критик WF160: прочерк читался «не делали»).
      const who = row.role ? progressWho(row.role) : { text: "", fable: false };
      return { label: row.label, who: who.text, fable: who.fable, state: rowState };
    }).filter((row, index) => shown.includes(index));
    const at = rows.findIndex(row => row.state === "run" || row.state === "wait" || row.state === "fail");
    let note = null;
    // «Сейчас» и «Твой ход» — целиком (WF160: без «…»), только пробелы в одну строку.
    if (block && data.waitFor && state === "wait") {
      note = { row: at, kind: "wait", prefix: PROGRESS_CARD_WAIT_PREFIX, text: progressLine(data.waitFor) };
    } else if (block && data.now && (state === "run" || state === "fail")) {
      note = { row: at, kind: "now", prefix: "", text: progressLine(data.now) };
    }
    const pill = state === "run" && at >= 0 && rows[at].state === "run" ? `идёт ${rows[at].label}`
      : (PROGRESS_CARD_PILL[state] ?? "идёт");
    return {
      // Слово одно на всю карточку — русское (#5911). С WF160 на экране вместо него капсула
      // номера (number, progressCardPaint); слово остаётся в слепке карточки для гейта.
      title: `Воркфлоу ${data.number}`, number: data.number,
      // «В проекте» на карточке не пишется (слово Элвиса 08.09): подпись
      // остаётся только у чата без блока.
      where: block ? "" : `${number}-й из ${info.of} в этом чате`,
      pill: { tone: state, text: pill },
      about: block ? (progressLine(block.about) || "—") : (PROGRESS_CARD_BLANK[data.word] ?? PROGRESS_CARD_BLANK_ANY),
      stages: Boolean(block), rows, note, when: data.when,
      // Дышит только то, что работает (готовый больше не дышит).
      breathe: state === "run",
    };
  };
  // Слепок карточки — он же ключ перерисовки (status().progress.tip.card):
  // последней стоит «когда», на гейте её сверяют по краям.
  const progressCardKey = view => [
    view.title, view.where, view.pill.text, view.about,
    ...(view.stages ? view.rows.map(row => `${row.label} ${row.state} ${row.who}`) : []),
    view.note ? `${view.note.prefix}${view.note.text}` : "", view.when,
  ].filter(Boolean).join(" · ");
  // Подгонка под потолок (ТЗ 9.1, п. 3). С WF160 ничего не режется «…» (ни «сейчас», ни «когда»):
  // единственный шаг — не влезла карточка — спрятать строку «сейчас» целиком.
  const progressCardFit = (level, note) => {
    const ui = progressCardUI;
    const target = note ? (note.row >= 0 ? ui.rows[note.row] : ui.spare) : null;
    for (const item of [...ui.rows, ui.spare]) {
      item.note.style.setProperty("display", item === target && level < 1 ? "block" : "none");
    }
  };
  // Нарисовать карточку view (progressCardUI): тексты, цвета темы окна, капсула номера, дорожка
  // этапов, подгонка под потолок maxHeight. cap — капсула номера {label, paint}: paint — её цвета
  // (как номер в ряду). Место на экране — у вызывающего (progressTipShow); ответ — появляется ли
  // карточка только что (тогда после места — progressCardReveal).
  const progressCardPaint = (view, frame, width, maxHeight, cap) => {
    const ui = progressCardUI;
    const narrow = width < PROGRESS_CARD_NARROW;
    // Цвета от темы окна — на каждом показе (ТЗ 9.1, п. 5).
    const dark = progressDark();
    const skin = PROGRESS_CARD_SKIN[dark ? "dark" : "light"];
    const T = progressTextColor(frame);
    const F = progressFieldColor(frame);
    const A = progressAccent();
    const G = `rgb(${skin.ok})`;
    const Y = `rgb(${skin.wait})`;
    const R = `rgb(${skin.fail})`;
    const Yt = dark ? Y : "rgb(150,104,0)";
    const tone = { done: G, run: A, wait: Y, fail: R, todo: T, skip: T };
    const tint = progressTint;
    const key = progressCardKey(view);
    const fresh = ui.text !== key;
    if (fresh) {
      ui.text = key;
      ui.fit = 0;
      // Только textContent: сводку пишут чаты, разметки в ней быть не может.
      ui.title.textContent = cap.label;
      ui.where.textContent = view.where;
      ui.where.hidden = view.where === "";
      ui.where.style.setProperty("display", view.where === "" ? "none" : "block");
      ui.pillText.textContent = view.pill.text;
      ui.about.textContent = view.about;
      ui.about.hidden = view.about === "";
      ui.about.style.setProperty("display", view.about === "" ? "none" : "block");
      ui.when.textContent = view.when;
      ui.when.hidden = view.when === "";
      ui.when.style.setProperty("display", view.when === "" ? "none" : "block");
      ui.stages.hidden = !view.stages;
      ui.stages.style.setProperty("display", view.stages ? "block" : "none");
      for (let order = 0; order < ui.rows.length; order += 1) {
        const node = ui.rows[order];
        const row = view.rows[order];
        // Этапов у Workflow меньше четырёх (WF198) — лишние строки прячутся.
        node.row.style.setProperty("display", row ? "grid" : "none");
        if (!row) continue;
        node.label.textContent = row.label;
        node.who.textContent = row.who;
        node.glyph.textContent = { done: "✓", wait: "!", fail: "✕" }[row.state] ?? "";
        const mine = view.note && view.note.row === order;
        node.prefix.textContent = mine ? view.note.prefix : "";
        node.text.textContent = mine ? view.note.text : "";
      }
      const spare = view.note && view.note.row < 0;
      ui.spare.prefix.textContent = spare ? view.note.prefix : "";
      ui.spare.text.textContent = spare ? view.note.text : "";
      // Смена содержимого — пульс пересобирается: идущая строка могла смениться.
      progressCardPulseStop();
    }
    for (const [name, value] of Object.entries(cap.paint)) ui.title.style.setProperty(name, value);
    // Коробка: фон — поле плюс 7 % текста (в светлой теме само поле), обводка —
    // текст 15 %, тень кожи.
    for (const [name, value] of Object.entries({
      background: dark ? `color-mix(in srgb, ${F}, ${T} 7%)` : F, color: T,
      "border-color": tint(T, 15), "box-shadow": skin.shadow,
      width: `${width}px`, "max-height": `${maxHeight}px`,
    })) ui.tip.style.setProperty(name, value);
    ui.where.style.setProperty("color", tint(T, 60));
    ui.about.style.setProperty("color", tint(T, 84));
    ui.when.style.setProperty("color", tint(T, 62));
    ui.when.style.setProperty("border-top-color", tint(T, 14));
    // Плашка: фон — цвет состояния 15 %, текст — цвет состояния (у «ждёт» — Yt),
    // точка — цвет состояния; у «запланирован» точка пустым контуром.
    const pillTone = view.pill.tone;
    const todoPill = pillTone === "todo";
    for (const [name, value] of Object.entries({
      background: todoPill ? tint(T, 8) : tint(tone[pillTone] ?? A, 15),
      color: todoPill ? tint(T, 62) : (pillTone === "wait" ? Yt : (tone[pillTone] ?? A)),
    })) ui.pill.style.setProperty(name, value);
    ui.dot.style.setProperty("background", todoPill ? "transparent" : (tone[pillTone] ?? A));
    ui.dot.style.setProperty("box-shadow", todoPill ? `inset 0 0 0 1.5px ${tint(T, 45)}` : "none");
    // Строки этапов: дорожка, этап, кто, подсветка текущей.
    const lineTo = state => ({
      done: tint(G, 85), skip: tint(G, 85), todo: tint(T, 24),
      run: `linear-gradient(${tint(G, 85)}, ${A})`, wait: `linear-gradient(${tint(G, 85)}, ${Y})`,
      fail: `linear-gradient(${tint(G, 85)}, ${R})`,
    })[state] ?? tint(T, 24);
    const rowHeight = narrow ? 24 : 28;
    for (let order = 0; order < ui.rows.length; order += 1) {
      const node = ui.rows[order];
      const row = view.rows[order];
      if (!row) continue;
      const state = row.state;
      const hot = state === "run" || state === "wait" || state === "fail";
      node.track.style.setProperty("min-height", `${rowHeight}px`);
      node.label.style.setProperty("line-height", `${rowHeight}px`);
      // «Кто» переносится (#9158, без «…»): первая строка — на линии этапа.
      node.who.style.setProperty("padding", `${(rowHeight - 16) / 2}px 0`);
      const next = view.rows[order + 1];
      node.line.style.setProperty("display", next ? "block" : "none");
      node.line.style.setProperty("top", narrow ? "21px" : "23px");
      node.line.style.setProperty("bottom", narrow ? "-3px" : "-5px");
      if (next) node.line.style.setProperty("background", lineTo(next.state));
      // Кружок: 14×14, у «впереди» — контур 12×12, у «пропущен» — точка 6×6.
      const size = state === "todo" ? 12 : (state === "skip" ? 6 : 14);
      const shift = state === "todo" ? 1 : (state === "skip" ? 4 : 0);
      const top = (narrow ? 5 : 7) + shift;
      const paint = {
        done: { background: G, color: progressInk(G), "box-shadow": "none" },
        run: { background: "transparent", color: A, "box-shadow": `inset 0 0 0 2px ${A}` },
        wait: { background: Y, color: progressInk(Y), "box-shadow": `0 0 0 3px ${tint(Y, 22)}` },
        fail: { background: R, color: progressInk(R), "box-shadow": `0 0 0 3px ${tint(R, 20)}` },
        todo: { background: "transparent", color: T, "box-shadow": `inset 0 0 0 1.5px ${tint(T, 34)}` },
        skip: { background: tint(T, 30), color: T, "box-shadow": "none" },
      }[state];
      for (const [name, value] of Object.entries({
        ...paint, width: `${size}px`, height: `${size}px`, left: `${3 + shift}px`, top: `${top}px`,
      })) node.node.style.setProperty(name, value);
      // Ядро идущего — точка 6×6 акцентом; у остальных знак — просто текст.
      node.glyph.style.setProperty("width", state === "run" ? "6px" : "auto");
      node.glyph.style.setProperty("height", state === "run" ? "6px" : "auto");
      node.glyph.style.setProperty("background", state === "run" ? A : "transparent");
      node.halo.style.setProperty("display", state === "run" ? "block" : "none");
      node.halo.style.setProperty("box-shadow", `0 0 0 2px ${tint(A, 32)}, 0 0 9px 2px ${tint(A, 42)}`);
      node.label.style.setProperty("color", {
        done: tint(T, 90), run: A, wait: Yt, fail: R,
      }[state] ?? tint(T, 50));
      node.who.style.setProperty("font-weight", row.fable ? "700" : "400");
      node.who.style.setProperty("color", row.fable || hot ? T : (state === "done" ? tint(T, 62) : tint(T, 45)));
      node.hl.style.setProperty("display", hot ? "block" : "none");
      node.hl.style.setProperty("background", hot ? tint(tone[state], 16) : "transparent");
      node.note.style.setProperty("color", tint(T, 76));
      node.prefix.style.setProperty("color", Yt);
    }
    ui.spare.note.style.setProperty("color", tint(T, 76));
    ui.spare.prefix.style.setProperty("color", Yt);
    ui.states = view.stages ? view.rows.map(row => row.state) : [];
    ui.note = view.note ? `${view.note.prefix}${view.note.text}` : null;
    ui.breathe = view.breathe;
    progressCardFit(ui.fit, view.note);
    // Появление: прозрачность 0 → 1 и сдвиг на 4 точки, 140 мс; при «поменьше
    // движения» — сразу. Закрытие мгновенное (progressTipHide).
    const appearing = ui.tip.style.getPropertyValue("display") !== "block";
    if (appearing) {
      ui.tip.style.setProperty("transition", "none");
      ui.tip.style.setProperty("opacity", progressMotionOk() ? "0" : "1");
      ui.tip.style.setProperty("transform", progressMotionOk() ? "translateY(4px)" : "none");
    }
    ui.tip.style.setProperty("display", "block");
    // Подгонка под потолок — только при смене содержимого и не больше одного
    // замера за показ.
    if (fresh) {
      let level = 0;
      try {
        while (level < 1 && ui.tip.scrollHeight > maxHeight) {
          level += 1;
          progressCardFit(level, view.note);
        }
      } catch {}
      ui.fit = level;
    }
    return appearing;
  };
  // Проявить карточку, уже стоящую на месте, и завести дыхание: дышит только идущий, при
  // разрешённом движении; иначе всё стоит — ореол .6, подсветка 1, точка 1.
  const progressCardReveal = appearing => {
    const ui = progressCardUI;
    if (appearing) {
      if (progressMotionOk()) {
        try { ui.tip.getBoundingClientRect(); } catch {}
        ui.tip.style.setProperty("transition", "opacity 140ms ease-out, transform 140ms ease-out");
      }
      ui.tip.style.setProperty("opacity", "1");
      ui.tip.style.setProperty("transform", "none");
    }
    for (const node of ui.rows) {
      if (node !== ui.rows[ui.states.indexOf("run")] || !ui.breathe) {
        node.halo.style.setProperty("opacity", progressCardRest.halo);
        node.hl.style.setProperty("opacity", progressCardRest.hl);
      }
    }
    progressCardPulse(ui.breathe);
  };
  const progressTipShow = () => {
    const info = progressState.info;
    const segment = progressState.tipSegment;
    if (!progressState.tipOpen || segment == null || !info ||
        !progressState.box || progressBar.style.display === "none") { progressTipHide(); return; }
    const number = progressNumberAt(segment);
    const view = progressCardView(info, number, Date.now());
    if (!view) { progressTipHide(); return; }
    const frame = progressState.frame?.isConnected ? progressState.frame : null;
    let frameRect = null;
    try { frameRect = frame ? frame.getBoundingClientRect() : null; } catch {}
    if (frameRect && !(frameRect.width > 0)) frameRect = null;
    // Ширина — по полю ввода: не шире его и не шире 400, не ýже 240 и не шире
    // окна минус поля.
    const width = Math.round(Math.min(innerWidth - 12,
      Math.max(PROGRESS_CARD_MIN_WIDTH, Math.min(PROGRESS_CARD_MAX_WIDTH, frameRect?.width ?? PROGRESS_CARD_MAX_WIDTH))));
    const maxHeight = Math.round(innerHeight * 0.6);
    // Капсула номера — номер и вид номера в ряду (progressBadgePaint): у старой сводки с номерами по
    // проекту номер блока другой (view.number), но на экране один знак на объект — номер ряда.
    const T = progressTextColor(frame);
    const accent = progressAccent();
    const badge = PROGRESS_BADGE_OF[view.pill.tone] ?? "plan";
    const cap = { label: String(number), paint: progressBadgePaint(badge, {
      accent, text: T, light: !progressDark(), done: info.state === "done" ? PROGRESS_PAINT.done : accent,
    }) };
    const appearing = progressCardPaint(view, frame, width, maxHeight, cap);
    progressState.cardText = progressCardUI.text;
    progressState.cardFit = progressCardUI.fit;
    progressState.cardRows = progressCardUI.states;
    progressState.cardNote = progressCardUI.note;
    // Место — уже по показанной карточке: до показа высоты у неё нет. Над полем
    // ввода, по его левому краю (ТЗ 9.1, п. 3); поле растянуто до потолка —
    // по-старому, над рядом номеров.
    const rect = progressTip.getBoundingClientRect();
    const height = rect.height || 0;
    const left = Math.max(6, Math.min(frameRect ? frameRect.left : progressState.box.left, innerWidth - width - 6));
    let top = frameRect ? frameRect.top - height - 8 : -1;
    progressState.cardAnchor = "поле";
    if (top < 6) {
      top = Math.max(6, progressState.box.top - height - 8);
      progressState.cardAnchor = "номера";
    }
    progressTip.style.setProperty("left", `${Math.round(left)}px`);
    progressTip.style.setProperty("top", `${Math.round(top)}px`);
    // Обводка выбранного номера — текст 55 % с отступом 1 точка (ТЗ, п. 5).
    for (let index = 0; index < progressCells.length; index += 1) {
      progressCells[index].cell.style.setProperty("outline", index === segment ? `1.5px solid ${progressTint(T, 55)}` : "none");
    }
    progressState.cardBreathe = view.breathe;
    progressCardReveal(appearing);
    progressState.cardPulse = Boolean(progressCardUI.slots.dot.anim);
  };
  // Строка «когда» на открытой карточке считает минуты от часов, а перерисовка
  // приходит только с командой status — та едет лишь когда сводка изменилась
  // (StatusFeed шлёт по смене digest). Открытая карточка говорила бы «15 мин
  // назад» и через час. Поэтому пока карточка открыта — свой тик раз в минуту
  // (проверка WF70); закрылась — тика нет.
  const PROGRESS_TIP_TICK_MS = 60000;
  const progressTipTickStop = () => {
    if (progressState.tipTick) { clearInterval(progressState.tipTick); progressState.tipTick = 0; }
  };
  const progressTipTickStart = () => {
    if (progressState.tipTick) return;
    progressState.tipTick = setInterval(() => {
      if (!progressState.tipOpen) { progressTipTickStop(); return; }
      try { progressTipShow(); } catch {}
    }, PROGRESS_TIP_TICK_MS);
  };
  track(progressTipTickStop);
  // Закрыть = погасить: выбор снимает сам progressTipHide.
  const progressTipClose = () => { progressTipHide(); };
  // Клик по полосе: по тому же сегменту — закрыть, по другому — переключить.
  // Пустой контур (строки состояния нет) карточке рассказать нечего.
  const progressTipToggle = (segment) => {
    if (segment == null || !progressState.info) { progressTipClose(); return; }
    if (progressState.tipOpen && progressState.tipSegment === segment) { progressTipClose(); return; }
    progressState.tipSegment = segment;
    progressState.tipOpen = true;
    progressTipShow();
    progressTipTickStart();
  };
  // Попадание в открытую карточку. Своя проверка нужна потому, что узел
  // прозрачен для мыши (pointer-events:none, чтобы не съедать клики по полю
  // ввода под ним): без неё клик по самой карточке гасил бы её же.
  const progressCardHit = (x, y) => {
    if (!progressState.tipOpen || progressTip.style.display === "none") return false;
    try {
      const rect = progressTip.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) return false;
      return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
    } catch { return false; }
  };

  // ---- прокрутка ряда (WF85, #7356) ---------------------------------------
  // Хвост «… N» — свой fixed-узел рядом с рядом, а не его ребёнок: номера
  // считают детьми ряда клик, тесты и карточка, а ряд режет всё за окном
  // номеров. Узел — тот же, что у номера (шрифт, скругление, цвета по
  // состоянию номера N), прозрачен для мыши: клик по нему ловит progressHit.
  const progressTailItem = progressCell();
  const progressTail = progressTailItem.cell;
  progressTail.id = PROGRESS_TAIL_ID;
  progressTail.setAttribute("aria-hidden", "true");
  for (const [name, value] of Object.entries({
    position: "fixed", display: "none", left: "0px", top: "0px", "z-index": "2147483645",
    transition: PROGRESS_BADGE_TRANS,
  })) progressTail.style.setProperty(name, value);
  (document.body ?? document.documentElement).appendChild(progressTail);
  track(() => progressTail.remove());
  // Хвост гаснет, когда ряд доехал до конца (слот остаётся — ряд не прыгает),
  // и светится вместе с рядом на наведении.
  const progressTailShade = () => {
    if (!progressScroll.on) return;
    progressTail.style.setProperty("opacity", progressScroll.tail ? (progressState.hovering ? "1" : "0.85") : "0");
  };
  // Сдвиг номеров — translateX у каждого: сама коробка ряда стоит и режет.
  const progressScrollPaint = () => {
    const scroll = progressScroll;
    const shift = scroll.on && scroll.x !== 0 ? `translateX(${-Math.round(scroll.x * 100) / 100}px)` : "";
    for (const item of progressCells) {
      if (shift) item.cell.style.setProperty("transform", shift);
      else item.cell.style.removeProperty("transform");
    }
    scroll.tail = scroll.on && scroll.x < scroll.max - 1;
    progressTailShade();
  };
  const progressScrollClamp = value => Math.max(0, Math.min(progressScroll.max, value));
  // Кадр: x догоняет цель долей 0,22, ближе полуточки — встаёт на неё.
  const progressScrollFrame = () => {
    const scroll = progressScroll;
    scroll.raf = 0;
    if (!scroll.on) return;
    const diff = scroll.target - scroll.x;
    scroll.x = Math.abs(diff) < 0.5 ? scroll.target : scroll.x + diff * PROGRESS_SCROLL_EASE;
    progressScrollPaint();
    if (scroll.x !== scroll.target) scroll.raf = requestAnimationFrame(progressScrollFrame);
  };
  // «Поменьше движения» и скрытое окно — сразу на место, без кадров.
  const progressScrollRun = () => {
    const scroll = progressScroll;
    if (!scroll.on) return;
    if (!progressMotionOk()) {
      if (scroll.raf) { cancelAnimationFrame(scroll.raf); scroll.raf = 0; }
      scroll.x = scroll.target;
      progressScrollPaint();
      return;
    }
    if (!scroll.raf) scroll.raf = requestAnimationFrame(progressScrollFrame);
  };
  // Колесо за краем: цель переводим обратно в «сырой» путь колеса, прибавляем
  // сдвиг и снова сжимаем всё, что за краем, — так переход через край ровный.
  const progressScrollPush = (target, delta) => {
    const max = progressScroll.max;
    const k = PROGRESS_SCROLL_RESIST;
    const raw = target < 0 ? target / k : (target > max ? max + (target - max) / k : target);
    const next = raw + delta;
    if (next < 0) return Math.max(-PROGRESS_SCROLL_OVER, next * k);
    if (next > max) return Math.min(max + PROGRESS_SCROLL_OVER, max + (next - max) * k);
    return next;
  };
  const onProgressWheel = (event) => {
    const scroll = progressScroll;
    if (!scroll.on || !progressHit(event.clientX, event.clientY)) return;
    event.preventDefault();
    event.stopPropagation();
    const dx = Number(event.deltaX) || 0;
    const dy = Number(event.deltaY) || 0;
    let delta = Math.abs(dx) > Math.abs(dy) ? dx : dy;
    if (event.deltaMode === 1) delta *= PROGRESS_SCROLL_LINE;
    else if (event.deltaMode === 2) delta *= Math.max(1, (scroll.view?.right ?? 0) - (scroll.view?.left ?? 0));
    if (delta === 0) return;
    // Карточка стоит на месте, номера уезжают из-под неё — закрываем (критик WF85).
    if (progressState.tipOpen) progressTipClose();
    scroll.user = true;
    scroll.wheelAt = Date.now();
    scroll.target = progressScrollPush(scroll.target, delta);
    if (scroll.spring) clearTimeout(scroll.spring);
    scroll.spring = setTimeout(() => {
      scroll.spring = 0;
      scroll.target = progressScrollClamp(scroll.target);
      progressScrollRun();
    }, PROGRESS_SCROLL_SPRING_MS);
    progressScrollRun();
  };
  // Не-пассивный wheel на документе отнимает у Chromium быструю прокрутку ленты
  // на потоке композитора (критик WF85, В6) — слушатель висит ТОЛЬКО в режиме
  // прокрутки.
  const progressWheel = (want) => {
    if (want === progressScroll.wheel) return;
    progressScroll.wheel = want;
    if (want) document.addEventListener("wheel", onProgressWheel, { capture: true, passive: false });
    else document.removeEventListener("wheel", onProgressWheel, { capture: true });
  };
  const progressScrollOff = () => {
    const scroll = progressScroll;
    if (scroll.raf) { cancelAnimationFrame(scroll.raf); scroll.raf = 0; }
    if (scroll.spring) { clearTimeout(scroll.spring); scroll.spring = 0; }
    progressWheel(false);
    const was = scroll.on;
    Object.assign(scroll, { on: false, x: 0, target: 0, max: 0, view: null, tail: false, user: false, wheelAt: 0, key: null });
    if (progressTail.style.display !== "none") progressTail.style.setProperty("display", "none");
    if (was) progressScrollPaint();
  };
  track(progressScrollOff);
  // Клик по хвосту — плавно к концу ряда.
  const progressScrollEnd = () => {
    if (progressState.tipOpen) progressTipClose();
    progressScroll.user = false;
    progressScroll.target = progressScroll.max;
    progressScrollRun();
  };
  // Своё место: номер текущего воркфлоу (с соседями, если влезают) в окне —
  // при появлении ряда, смене номера, окна или числа номеров. Было колесо
  // меньше 8 с назад — не вмешиваемся; «своё место» догонит на следующем проходе.
  const progressScrollOwn = (items, gap, view, wf, instant) => {
    const scroll = progressScroll;
    const key = `${wf}|${view}|${items.length}`;
    if (!instant && scroll.key === key) return;
    if (!instant && Date.now() - scroll.wheelAt < PROGRESS_SCROLL_HOLD_MS) return;
    scroll.key = key;
    const current = items.findIndex(item => wf >= item.first && wf <= item.last);
    if (current < 0) return;
    const starts = [];
    let left = 0;
    for (const item of items) { starts.push(left); left += progressBadgeWidth(item.label) + gap; }
    const span = (from, to) => [starts[from], starts[to] + progressBadgeWidth(items[to].label)];
    let [a, b] = span(Math.max(0, current - 1), Math.min(items.length - 1, current + 1));
    if (b - a > view) [a, b] = span(current, current);
    let target = progressScrollClamp(scroll.target);
    if (a < target) target = a;
    else if (b > target + view) target = b - view;
    scroll.target = progressScrollClamp(target);
    scroll.user = false;
    if (instant) {
      if (scroll.raf) { cancelAnimationFrame(scroll.raf); scroll.raf = 0; }
      scroll.x = scroll.target;
    } else progressScrollRun();
  };

  const progressHide = () => {
    progressScrollOff();
    progressState.box = null;
    progressState.anchor = null;
    progressState.badges = [];
    progressState.segments = [];
    // Ряд ушёл с экрана (меню накрыло его, окно уехало) — дышать нечему.
    for (const item of progressCells) {
      item.pulse = false;
      progressPulse(item, item.line, false, PROGRESS_LINE_FRAMES, "1");
    }
    // Полосы нет — не о чем и подсказке: держать её открытой над пустым местом
    // (меню накрыло линию, окно уехало) не за что.
    progressTipClose();
    if (progressBar.style.display !== "none") progressBar.style.setProperty("display", "none");
  };

  // ---- место под ряд номеров (#7105, WF84) ---------------------------------
  // Рамка поля растёт вниз ровно на ряд номеров. Не своим узлом
  // внутри рамки — её дерево пересобирает React, и чужой узел там лишний риск
  // (довод раздела 4), — а её же нижним полем: инлайном и с important, как
  // всё наше на чужих узлах (CSP может не пустить таблицу, раздел 4). Поле, а
  // не прозрачная граница: обводку рамки Claude рисует тенью ВНУТРЬ (inset,
  // замер 23.09), и граница вынесла бы низ рамки за её же обводку. Своё поле
  // Claude (8 точек, класс py-2) читаем ДО нашей правки и только дополняем до
  // нужного: меньше, чем было у Claude, не ставим никогда.
  const progressRoomClear = () => {
    const node = progressState.roomNode;
    progressState.roomNode = null;
    progressState.roomBase = 0;
    progressState.room = 0;
    if (!node) return;
    try {
      node.style.removeProperty("padding-bottom");
      node.style.removeProperty(PROGRESS_ROOM_VARIABLE);
      node.removeAttribute(PROGRESS_ROOM_ATTRIBUTE);
    } catch {}
  };
  track(progressRoomClear);
  // room — сколько точек добавить к СВОЕМУ нижнему полю рамки (WF84: 18 без
  // вложений, 20 с ними); рамки нет или 0 — вернуть рамке её собственное.
  // Ответ — поменялась ли геометрия рамки.
  const progressRoomSet = (node, room) => {
    let base = 0;
    if (node && room > 0) {
      if (progressState.roomNode === node) base = progressState.roomBase;
      else { try { base = parseFloat(getComputedStyle(node).paddingBottom) || 0; } catch {} }
    }
    const extra = node && room > 0 ? Math.max(0, Math.round(room)) : 0;
    const target = extra > 0 ? node : null;
    const value = `${base + extra}px`;
    if (progressState.roomNode === target && (!target || (progressState.room === extra &&
        target.style.getPropertyValue("padding-bottom") === value))) return false;
    // Лента за полем не следит (#5869, раздел 10): место под капсулы поле
    // отнимает у неё снизу, и последние строки уехали бы под поле. Стояла
    // лента внизу — вернём вниз, как на смене ступени.
    let tail = null;
    let down = false;
    try { tail = tailScroller(); down = tailAtBottom(tail); } catch {}
    if (progressState.roomNode !== target) progressRoomClear();
    if (target) {
      target.style.setProperty("padding-bottom", value, "important");
      // Добавку — ещё и переменной: по ней широкий вид поднимает кнопку
      // отправки над рядом (layoutCss, раздел 2а).
      target.style.setProperty(PROGRESS_ROOM_VARIABLE, `${extra}px`);
      if (!target.hasAttribute(PROGRESS_ROOM_ATTRIBUTE)) target.setAttribute(PROGRESS_ROOM_ATTRIBUTE, "");
      progressState.roomNode = target;
      progressState.roomBase = base;
      progressState.room = extra;
    }
    if (down && tail?.isConnected) { try { tail.scrollTop = tail.scrollHeight; } catch {} }
    return true;
  };

  // Плитки вложений в поле: над номерами тогда воздух 8, а не 6 (#7189).
  // Один запрос на проход (раскладка зовёт ряд до четырёх раз в секунду) —
  // по блоку ввода: плитки живут в коробке поля, а она внутри блока.
  const progressHasTiles = (frame) => {
    const box = state.composerBlock?.isConnected ? state.composerBlock : frame;
    try { return Boolean(box?.querySelector?.(PROGRESS_TILES_SELECTOR)); } catch { return false; }
  };
  // Цвета номера (ТЗ, п. 3) — от темы, не константы: A — акцент, T — цвет
  // текста поля, жёлтый и красный — PROGRESS_PAINT. Готовые в идущем марафоне
  // — акцентом; весь марафон «готово ✅» — зелёным (буква Элвиса 1A: готово —
  // сигнал продолжать). Светлая тема: жёлтый плотнее, красный бледнее, а его
  // цифра — тёмно-красная (белая на светлом пропала бы).
  const progressBadgePaint = (state, { accent, text, light, done }) => {
    const tint = progressTint;
    switch (state) {
      case "done": return { background: tint(done, 30), "box-shadow": "none", color: tint(text, 72) };
      case "run": return { background: "transparent", "box-shadow": `inset 0 0 0 1px ${tint(accent, 85)}`, color: accent };
      case "wait": return { background: tint(PROGRESS_PAINT.wait, light ? 75 : 48), "box-shadow": "none", color: tint(text, 92) };
      case "fail": return {
        background: tint(PROGRESS_PAINT.fail, light ? 30 : 52), "box-shadow": "none",
        color: light ? "rgb(150,20,20)" : tint(text, 95),
      };
      default: return { background: "transparent", "box-shadow": `inset 0 0 0 1px ${tint(text, 22)}`, color: tint(text, 42) };
    }
  };

  // Одно место решает и про причину, и про видимость: иначе status().progress
  // рассказывал бы одно, а окно показывало другое. Ряда нет совсем (рамки нет,
  // поле свёрнуто) — рамка получает своё поле назад; ряд лишь спрятался под
  // открытым меню — место остаётся, иначе поле прыгало бы с каждым меню.
  const progressOff = (reason) => {
    progressState.reason = reason;
    progressRoomSet(null, 0);
    progressHide();
  };
  const progressApply = () => {
    const block = state.composerBlock?.isConnected ? state.composerBlock : null;
    if (!block) { progressOff("нет блока композера"); return; }
    // Якорь основной — рамка поля: ряд живёт в её нижнем поле. Запасной — верх
    // строки инструментов (там полоса стояла до WF9): рамки может не оказаться
    // вовсе (чужая разметка) или она вырождается на кадр, пока React
    // пересобирает низ окна. Лучше на пару точек ниже, чем пропасть.
    const frame = progressFrame(block);
    let frameRect = frame?.isConnected ? frame.getBoundingClientRect() : null;
    const onFrame = frameRect != null && frameRect.width >= PROGRESS_MIN_WIDTH;
    const rowRect = onFrame || !state.modelRow?.isConnected
      ? null
      : state.modelRow.getBoundingClientRect();
    const rect = onFrame ? frameRect : rowRect;
    if (!rect) { progressOff("нет рамки поля"); return; }
    const info = progressState.info;
    if (rect.width < PROGRESS_MIN_WIDTH || rect.bottom <= 0 || rect.top >= innerHeight) {
      progressOff("рамка поля вне окна");
      return;
    }
    // Свёрнутое поле — режим чтения (#6651, слово Элвиса 20.09: «всё скрывай,
    // даже полоску внизу, чтобы оставалась одна полосочка»): ряда нет вовсе.
    if (state.stage === STAGE_COLLAPSED) { progressOff("поле свёрнуто — режим чтения"); return; }
    // Строки состояния нет или в ней нет воркфлоу — ряда нет (#7188, слово
    // Элвиса 23.09: выводить её незачем).
    if (!info) { progressOff("нет строки состояния"); return; }
    // Место под ряд — нижним полем рамки: 18 точек, с плитками вложений 20
    // (воздух 6 и 8 над номером в 12). Рамка выросла — мерим её заново.
    const tiles = onFrame && progressHasTiles(frame);
    if (progressRoomSet(onFrame ? frame : null, tiles ? PROGRESS_ROOM_TILES : PROGRESS_ROOM_TEXT) && onFrame) {
      frameRect = frame.getBoundingClientRect();
    }
    // Слева — по левому краю ТЕКСТА поля (макет 7), справа — столько же от
    // правого края рамки. Край текста — редактор; он чужой или вне рамки —
    // отступ по скруглению рамки, как у ручки.
    let left = Math.round(rect.left);
    let width = Math.round(rect.width);
    if (onFrame) {
      let textLeft = null;
      try {
        const node = state.editor?.isConnected ? state.editor : (state.editorRoot?.isConnected ? state.editorRoot : null);
        const box = node ? node.getBoundingClientRect() : null;
        if (box && box.width > 0 && box.left >= frameRect.left && box.left < frameRect.left + frameRect.width / 2) textLeft = box.left;
      } catch {}
      const inset = textLeft == null ? handleInset(progressState.frame ?? state.shell) : textLeft - frameRect.left;
      left = Math.round(frameRect.left + inset);
      width = Math.max(0, Math.round(frameRect.width - inset * 2));
    }
    const { items, gap, blocks } = progressBadges(info, width);
    // Номер садится над СВОИМ полем рамки Claude (у низа рамки остаётся её
    // родное поле, 8 точек): от текста до номера — наша добавка минус номер.
    // На запасном якоре — над кромкой строки инструментов.
    const top = onFrame
      ? Math.round(frameRect.top + frameRect.height - progressState.roomBase - PROGRESS_BADGE_HEIGHT)
      : Math.round(rect.top) - PROGRESS_BADGE_HEIGHT - 1;
    if (progressCovered(top, top + PROGRESS_BADGE_HEIGHT, left, left + width)) {
      progressState.reason = "полосу закрыло меню";
      progressHide();
      return;
    }
    progressState.reason = null;
    progressState.anchor = onFrame ? "рамка" : "строка инструментов";
    progressState.badges = items;
    progressState.segments = items.map(item => item.share);
    progressState.gap = gap;
    progressState.blocks = blocks;
    // Ряд сейчас спрятан — значит это его появление: ни первый показ при
    // открытии окна, ни возврат из-под закрывшегося меню анимировать нечего,
    // всё пишется сразу набело.
    const instant = progressBar.style.display !== "flex";
    progressBuild(items.length);
    const colors = {
      accent: progressAccent(), text: progressTextColor(onFrame ? frame : null), light: !progressDark(),
    };
    colors.done = info.state === "done" ? PROGRESS_PAINT.done : colors.accent;
    // Узлы, которым этот проход пишется без переходов: свежерождённые и все
    // подряд на появлении ряда. Переходы им вернём одним махом ниже.
    const quiet = [];
    for (let index = 0; index < items.length; index += 1) {
      const item = progressCells[index];
      const badge = items[index];
      if (instant || item.born) {
        item.cell.style.setProperty("transition", "none");
        quiet.push(item);
      }
      for (const [name, value] of Object.entries(progressBadgePaint(badge.state, colors))) {
        item.cell.style.setProperty(name, value);
      }
      item.cell.style.setProperty("width", `${progressBadgeWidth(badge.label)}px`);
      if (item.num.textContent !== badge.label) item.num.textContent = badge.label;
      // Линия шагов идущего: 2 точки у нижнего края, ширина — доля шагов (не
      // меньше PROGRESS_MIN_FILL), дышит 0,45 → 1 в общий такт 3,6 с.
      const running = badge.state === "run";
      item.line.style.setProperty("display", running ? "block" : "none");
      item.line.style.setProperty("background", colors.accent);
      item.line.style.setProperty("width", `${running ? Math.max(PROGRESS_MIN_FILL, badge.share) : 0}%`);
      item.pulse = running;
      progressPulse(item, item.line, item.pulse, PROGRESS_LINE_FRAMES, "1");
      if (!progressState.tipOpen || progressState.tipSegment !== index) item.cell.style.setProperty("outline", "none");
      if (instant) item.cell.style.setProperty("opacity", "1");
    }
    if (quiet.length > 0) {
      // Принудительная раскладка одна на весь проход: без неё браузер сведёт обе
      // записи стиля в один пересчёт и проиграет движение от старых значений.
      try { progressBar.getBoundingClientRect(); } catch {}
      for (const item of quiet) {
        item.born = false;
        item.cell.style.setProperty("transition", PROGRESS_BADGE_TRANS);
        // Новый номер проявляется за 200 мс; на появлении ряда он всплыл выше.
        item.cell.style.setProperty("opacity", "1");
      }
    }
    // Не влезли и после слияния (WF85, #7356) — режим прокрутки: ряд режет
    // окно номеров, справа слот хвоста «… N» (U+2026, узкий неразрывный
    // пробел, последний номер; вид — состояние номера N).
    let view = width;
    const need = progressRowNeed(items, gap);
    if (need > width && items.length > 1) {
      const last = items[items.length - 1];
      const tailLabel = `…\u202F${last.last}`;
      const tailWidth = progressBadgeWidth(tailLabel);
      view = Math.max(0, width - tailWidth - gap - PROGRESS_SCROLL_CLIP);
      const entering = instant || !progressScroll.on;
      progressScroll.on = true;
      progressScroll.max = Math.max(0, need - view);
      progressScroll.view = { left, right: left + view };
      progressWheel(true);
      for (const [name, value] of Object.entries(progressBadgePaint(last.state, colors))) {
        progressTail.style.setProperty(name, value);
      }
      if (progressTailItem.num.textContent !== tailLabel) progressTailItem.num.textContent = tailLabel;
      progressTail.style.setProperty("width", `${tailWidth}px`);
      progressTail.style.setProperty("left", `${left + width - tailWidth}px`);
      progressTail.style.setProperty("top", `${top}px`);
      progressTail.style.setProperty("display", "block");
      progressScrollOwn(items, gap, view, info.wf, entering);
      // Окно сузилось или номеров стало меньше — сдвиг обратно в границы; пока
      // пружина не отпустила колесо, за краем стоять можно.
      if (!progressScroll.spring) {
        progressScroll.target = progressScrollClamp(progressScroll.target);
        if (progressScroll.x !== progressScrollClamp(progressScroll.x)) progressScrollRun();
      }
      progressScrollPaint();
    } else if (progressScroll.on) progressScrollOff();
    progressBar.style.setProperty("left", `${left}px`);
    progressBar.style.setProperty("top", `${top}px`);
    progressBar.style.setProperty("width", `${view}px`);
    progressBar.style.setProperty("gap", `${gap}px`);
    progressBar.style.setProperty("opacity", progressState.hovering ? "1" : "0.85");
    const label = progressAria(items);
    if (progressBar.getAttribute("aria-label") !== label) progressBar.setAttribute("aria-label", label);
    const title = `Воркфлоу ${info.wf} из ${info.of}` + (info.pct == null ? "" : ` · ${info.pct} %`);
    // Указателя ряд не ловит, и родной title на нём не покажется — он остаётся
    // для разбора окна (probe на гейте).
    if (progressBar.title !== title) progressBar.title = title;
    progressBar.style.setProperty("display", "flex");
    progressState.box = { left, right: left + width, top, bottom: top + PROGRESS_BADGE_HEIGHT };
    if (progressState.tipOpen) progressTipShow();
  };
  // Раскладку ручки полоса не имеет права уронить: её зовут из чужого кода.
  const placeProgress = () => { try { progressApply(); } catch {} };

  // Попадание по ряду (WF84, ТЗ п. 5): номера и ±4 точки по вертикали, по
  // горизонтали — весь ряд: клик по номеру открывает его карточку, клик по
  // пустому месту ряда — карточку текущего воркфлоу (progressSegmentAt).
  const progressHit = (x, y) => {
    const box = progressState.box;
    // Пустой контур (строки состояния нет) — только украшение: мышь не ловит,
    // клик под ним доходит до страницы (проверка WF22).
    if (!progressState.info) return false;
    if (!box || progressBar.style.display === "none") return false;
    if (y < box.top - PROGRESS_HIT_SLACK || y > box.bottom + PROGRESS_HIT_SLACK) return false;
    if (x < box.left || x > box.right) return false;
    // Меню, список или окно Claude над полосой сильнее неё (WF144, класс «наши слои уступают
    // меню», WF136 п.7): полоса прячется только на проходе раскладки и с другим запасом,
    // а нажатие по пункту, съеденное здесь на захвате, закрывало меню.
    try { if (document.elementFromPoint(x, y)?.closest?.(OVERLAY_SELECTOR)) return false; } catch {}
    // Ручка сильнее полосы: кликом по ней возвращают свёрнутое поле, и не уступи
    // мы здесь, вернуть его стало бы нечем — наш обработчик глушит клик на
    // захвате, до самой ручки. С 12.09 линии разведены (ручка на кромке строки
    // модели, полоса на низе блока), но уступка остаётся: их разводит
    // геометрия, а она у Claude меняется без предупреждения.
    // Дубли у краёв окна (#6743) стоят там же, где полоса на свёрнутом поле, и
    // уступка им нужна ровно по той же причине, что и ручке.
    try {
      for (const node of [handle, superTop, superBottom]) {
        if (node.style.display === "none") continue;
        const rect = node.getBoundingClientRect();
        if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) return false;
      }
    } catch {}
    return true;
  };
  // Курсор — единственное, что даёт наведение (план WF12, п. 3): подсказка
  // открывается кликом. Полоса ничего не ловит мышью (pointer-events:none), и
  // своего курсора у неё быть не может, поэтому «руку» ставим корню документа и
  // снимаем ровно её же — чужой курсор (перетаскивание ручки) не трогаем.
  const progressCursor = (hand) => {
    try {
      const root = document.documentElement;
      if (hand) { if (root.style.cursor !== "pointer") root.style.cursor = "pointer"; }
      else if (root.style.cursor === "pointer") root.style.cursor = "";
    } catch {}
  };
  track(() => progressCursor(false));
  const onProgressMove = (event) => {
    // Над карточкой «руку» не ставим: кликать по ней нечего, а линия под ней
    // может оказаться на том же месте у самого края окна.
    const inside = !state.dragging && !progressCardHit(event.clientX, event.clientY) &&
      progressHit(event.clientX, event.clientY);
    if (inside === progressState.hovering) return;
    progressState.hovering = inside;
    progressCursor(inside);
    // Наведение на ряд — во всю силу (ТЗ WF84, п. 5).
    progressBar.style.setProperty("opacity", inside ? "1" : "0.85");
    progressTailShade();
  };
  on(document, "mousemove", onProgressMove, { passive: true, capture: true });
  // Клик по полосе. Ловим на ЗАХВАТЕ и только внутри линии: там событие наше
  // целиком (preventDefault + stopPropagation), и полю ввода под ней оно не
  // достаётся. Мимо линии — не трогаем событие вовсе, только закрываем подсказку.
  const onProgressDown = (event) => {
    // Попадание в карточку проверяем ДО закрытия: она прозрачна для мыши, и без
    // этой проверки любой клик по ней самой её же и гасил бы. Событие при этом
    // не трогаем — под карточкой живёт лента, и выделять в ней текст Элвису
    // никто не мешает.
    if (progressCardHit(event.clientX, event.clientY)) return;
    if (!progressHit(event.clientX, event.clientY)) { progressTipClose(); return; }
    event.preventDefault();
    event.stopPropagation();
    // Правее окна номеров — хвост «… N» (WF85): плавно к концу ряда.
    if (progressScroll.on && event.clientX > (progressScroll.view?.right ?? Infinity)) {
      try { progressScrollEnd(); } catch {}
      return;
    }
    try { progressTipToggle(progressSegmentAt(event.clientX)); } catch {}
  };
  on(document, "pointerdown", onProgressDown, { capture: true });
  // Escape закрывает подсказку. Слушатель свой, а не ветка в разделе 16: там
  // Escape ГЛОТАЕТСЯ насовсем, и подсказка обязана закрыться раньше. Этот
  // слушатель встаёт первым (раздел 2б идёт по файлу выше) и потому успевает.
  const onProgressKey = (event) => {
    if (event.key === "Escape" && progressState.tipOpen) progressTipClose();
  };
  on(window, "keydown", onProgressKey, { capture: true });
  // Указатель ушёл из окна — движений больше не будет, и «рука» осталась бы
  // висеть. То же на потере фокуса окном. Подсказку это не закрывает: её
  // открыли кликом, и родное меню приложения как раз отнимает фокус.
  const onProgressLeave = () => {
    if (!progressState.hovering) return;
    progressState.hovering = false;
    progressCursor(false);
    progressBar.style.setProperty("opacity", "0.85");
    progressTailShade();
  };
  on(document, "mouseleave", onProgressLeave, { passive: true });
  on(window, "blur", onProgressLeave, { passive: true });

  // Идём от последнего ответа к более старым и останавливаемся на первом, где
  // строка нашлась: это и есть «последняя по ленте».
  // Слово строки состояния последнего ответа («жду», «упал»…), и без «WF N из M» (#8282).
  let progressTailWord = null;
  const progressRead = () => {
    progressTailWord = null;
    // Сторожа «чат пустой» здесь нет намеренно (#5855): приметы разговора
    // (CHAT_STARTED_SELECTOR, isFreshChat) в главном окне с десятью ответами на
    // экране дают НОЛЬ — «Message actions» живёт только под мышью (замер 12.09
    // 17:51). Чужое из окна отсекает не он, а панель разговора в запасном пути.
    // Те же приметы ответа, что у «Обкэшить» (ANSWER_SELECTOR + answerUsable): разметка
    // claude.ai и окна Claude Code разная, свой узкий селектор в 1.40609.1 не находил ничего.
    let nodes = [];
    try {
      // Плюс строки виртуальной ленты Claude Code: у ответа с шагами инструментов
      // aria-label «Message N» достаётся строке шагов, а итоговый текст (со строкой
      // состояния) лежит отдельной строкой без приметы (замер 04.09 21:00).
      const all = [...document.querySelectorAll(`${ANSWER_SELECTOR},[data-testid="transcript-row"]`)]
        .filter(answerUsable);
      nodes = all.filter(node => !all.some(other => other !== node && other.contains(node)));
    } catch {}
    const stop = Math.max(0, nodes.length - PROGRESS_LOOKBACK);
    for (let index = nodes.length - 1; index >= stop; index -= 1) {
      const node = nodes[index];
      if (!node?.isConnected) continue;
      // Черновик в поле ввода ответом не считается: там Элвис вполне может
      // держать недописанную строку состояния.
      if (state.composerBlock?.contains(node)) continue;
      const scan = progressScan(node.innerText ?? node.textContent ?? "");
      if (scan.info || scan.stop) { progressTailWord = scan.info?.state ?? scan.word ?? null; return scan.info; }
    }
    // Примет хватило (не меньше PROGRESS_LOOKBACK ответов), а строки в последних нет — её и нет. Запасной
    // путь здесь читал innerText всей панели в каждом таком чате (до раза в секунду) и показывал ряд из
    // ответа старше PROGRESS_LOOKBACK (ревизия WF247).
    if (nodes.length >= PROGRESS_LOOKBACK) return null;
    // Запасной путь: в окнах «Open in new window» приметы ответа почти не совпадают
    // (проверено 04.09: 0–3 узла на сотню сообщений, лента виртуальная). Тогда читаем
    // текст ПАНЕЛИ РАЗГОВОРА без черновика в поле ввода — в нём строка состояния есть.
    //
    // Панели, а не всего окна (#5855): в текст body попадает сайдбар с ЧУЖИМИ чатами и
    // наша же карточка подсказки со строками сводки — чат без своей строки состояния брал
    // этот текст за свой. Замер 12.09 17:47: панель есть во всех окнах Claude Code
    // (главном и вынесенных), поле ввода, сайдбар и наши слои лежат ВНЕ её.
    //
    // Панели нет вовсе — значит и разговора нет (домашний экран после ⌘N): читать нечего,
    // и полоска остаётся пустым контуром. Прежнее падение на body делало ровно то, от чего
    // затевалась правка (находка проверяющего 12.09): «новый чат» Элвиса — это и есть
    // домашний экран, где панели не бывает.
    //
    // Селекторов два, и в живом окне они попадают в ДВА ВЛОЖЕННЫХ узла одной и той же
    // панели (замер 12.09 18:30: .epitaxy-chat-panel-body и лента внутри неё) — поэтому
    // сперва оставляем только внешние. Их больше одной — окно разделено на два чата, и
    // своя панель та, что стоит над нашим полем ввода: первая по документу показывала бы
    // чужой чат всему окну.
    try {
      const found = [...document.querySelectorAll('.epitaxy-chat-panel-body,[data-testid="epitaxy-virtual-transcript"]')];
      const panels = found.filter(node => !found.some(other => other !== node && other.contains(node)));
      let panel = panels[0] ?? null;
      const box = state.composerBlock?.isConnected ? state.composerBlock.getBoundingClientRect() : null;
      if (panels.length > 1 && box) {
        let best = -Infinity;
        for (const node of panels) {
          const rect = node.getBoundingClientRect();
          const share = Math.min(rect.right, box.right) - Math.max(rect.left, box.left);
          if (share > best) { best = share; panel = node; }
        }
      }
      if (panel == null) return null;
      let text = panel.innerText ?? "";
      const draft = (state.composerBlock?.innerText ?? "").trim();
      if (draft && text.endsWith(draft)) text = text.slice(0, -draft.length);
      else if (draft) text = text.replace(draft, "");
      const scan = progressScan(text);
      progressTailWord = scan.info?.state ?? scan.word ?? null;
      return scan.info;
    } catch { return null; }
  };

  // «Замереть у низа» (WF84, ТЗ п. 2; слово Элвиса 23.09: «при прокручивании
  // чата вверх-вниз это поле не менялось… показывалось реально, что сейчас
  // происходит»). Лента виртуальная: прокрутил вверх — последних ответов в DOM
  // нет, и «последней» становилась старая строка. Поэтому строку читаем только
  // у низа ленты; ленты нет (домашний экран, чужая разметка) — читаем как
  // раньше. Ответ: true — у низа, false — не у низа, null — ленты нет.
  const progressAtBottom = () => {
    const tail = tailScroller();
    if (!tail?.isConnected) return null;
    return Number(tail.scrollHeight) - Number(tail.clientHeight) - Number(tail.scrollTop) <= PROGRESS_TAIL_SLACK;
  };
  // Ключ чата для запомненной строки: id чата, у окна без него — ключ окна.
  // Не sessionKey() сам по себе: у главного окна он один на все чаты («main»), и
  // смена чата в окне была бы незаметна.
  const progressKey = () => {
    try { return chatKey() ?? sessionKey() ?? "окно"; } catch { return "окно"; }
  };
  const progressRemember = (key, info) => {
    const map = progressState.lastByKey;
    map.delete(key);
    map.set(key, { info, at: Date.now() });
    while (map.size > PROGRESS_KEYS_MAX) map.delete(map.keys().next().value);
  };
  const progressRefresh = () => {
    if (!state.alive || !state.watching) return;
    progressState.at = now();
    progressState.runs += 1;
    const key = progressKey();
    let bottom = null;
    try { bottom = progressAtBottom(); } catch {}
    progressState.atBottom = bottom !== false;
    if (bottom === false) {
      // Лента не у низа — чтения НЕТ, ряд стоит. Сменился чат в окне — берём
      // запомненное для ЭТОГО чата; нет его — ряда нет (не строка прежнего).
      progressState.frozen = true;
      if (key !== progressState.key) {
        progressState.info = progressState.lastByKey.get(key)?.info ?? null;
        progressState.key = key;
      }
      progressState.source = progressState.info ? "запомнено" : "нет";
    } else {
      progressState.frozen = false;
      progressState.info = progressRead();
      progressState.key = key;
      progressRemember(key, progressState.info);
      progressState.source = progressState.info ? "низ ленты" : "нет";
    }
    progressApply();
  };
  // Троттлинг откладыванием, а не пропуском: последняя мутация ленты — как раз
  // та, что дописала строку состояния, и терять её нельзя.
  const progressSchedule = () => {
    if (progressState.timer || !state.alive || !state.watching) return;
    const wait = Math.max(0, PROGRESS_MIN_GAP - (now() - progressState.at));
    if (wait === 0) { progressRefresh(); return; }
    progressState.timer = setTimeout(() => {
      progressState.timer = 0;
      try { progressRefresh(); } catch {}
    }, wait);
  };
  track(() => { if (progressState.timer) { clearTimeout(progressState.timer); progressState.timer = 0; } });
  // Тихое окно мутаций не даёт вовсе (чат открыт и не двигается), поэтому сверх
  // тика ленты — редкий страховочный перечёт.
  progressState.pulse = setInterval(() => { try { progressRefresh(); } catch {} }, PROGRESS_IDLE_MS);
  track(() => { clearInterval(progressState.pulse); progressState.pulse = 0; });
  // Полоса прогресса воркфлоу (раздел 2б): что вычитано из строки состояния
  // последнего ответа и почему полосы нет (или почему она пустым контуром). total — доля всего
  // марафона в процентах, pct — процент текущего воркфлоу, segments — доли
  // нарисованных сегментов слева направо (в узком окне их сливают в один).
  statusPart("progress", () => ({
    wf: progressState.info?.wf ?? null,
    of: progressState.info?.of ?? null,
    pct: progressState.info?.pct ?? null,
    total: progressState.info?.total ?? null,
    state: progressState.info?.state ?? null,
    segments: progressState.segments.slice(),
    // Мелкие номера (WF84, #7204): номер (слитый — строкой «1–9»), его
    // состояние (done | run | wait | fail | plan) и доля шагов.
    badges: progressState.badges.map(item => ({ n: item.n, state: item.state, share: item.share })),
    // Откуда строка на экране: "низ ленты" | "запомнено" | "нет"; frozen —
    // лента не у низа и ряд стоит; atBottom — лента у низа (или её нет);
    // blocks — сводка принята сверкой номеров 1…M.
    source: progressState.source,
    frozen: progressState.frozen,
    atBottom: progressState.atBottom,
    blocks: progressState.blocks,
    // Сколько точек нижнего поля рамка отдала под ряд сверх своего (18, с
    // плитками вложений 20).
    room: progressState.room,
    // На чём сидит ряд: "рамка" или запасное "строка инструментов".
    anchor: progressState.anchor,
    reason: progressState.reason,
    // Прокрутка ряда (WF85, #7356): сдвиг номеров и его предел в точках,
    // виден ли хвост «… N», был ли последний сдвиг от колеса. Вне режима
    // прокрутки — {x:0, max:0, tail:false, user:false}.
    scroll: {
      x: Math.round(progressScroll.x), max: Math.round(progressScroll.max),
      tail: progressScroll.tail, user: progressScroll.user,
    },
    // Карточка (WF84, 9.1): какой номер открыт кликом (порядок в ряду, с
    // нуля), открыта ли, дышит ли, её слепок через « · »
    // (последней — строка «когда», WF70; тикает с часами, на гейте сверять
    // по краям), состояния строк этапов, строка «сейчас» и на что она
    // встала — "поле" или "номера".
    tip: {
      segment: progressState.tipSegment, open: progressState.tipOpen,
      pulse: progressState.cardPulse,
      card: progressState.tipOpen ? (progressState.cardText || null) : null,
      rows: progressState.tipOpen ? progressState.cardRows.slice() : [],
      note: progressState.tipOpen ? progressState.cardNote : null,
      anchor: progressState.tipOpen ? progressState.cardAnchor : null,
    },
  }));
  // Сводка проектов из команды status: имя проекта, взятое из строки
  // состояния этого чата. at и projects — для гейта: видно, дошла ли
  // команда и под какими именами.
  statusPart("statusFeed", () => ({
    project: progressState.info?.project ?? null,
    at: statusFeed.at,
    projects: [...statusFeed.projects.keys()],
  }));
  HATCH && Object.assign(HATCH, { parseProgressText, progressScan, progressBadges, progressBadgeStates,
    progressBadgeWidth, progressFill, progressWhen, progressInk, progressCardData, statusBlocks, statusParse,
    statusHeadState, statusLineNumber, statusKey, statusFeedProject, progressState, progressRefresh });

