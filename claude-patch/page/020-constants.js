  // ---- 1. Постоянные ------------------------------------------------------
  // #11618: Claude бывает на русском (config.json locale «ru» — у Элвиса с 04.11.2026), и кнопки подписаны
  // по-русски. Надпись ищем на обоих языках: uiAria(["Mode", "Режим"]) → :is([aria-label="Mode"],[aria-label="Режим"]).
  // Перевод — дословно из каталога claude.ai (/i18n/ru.json рядом с /i18n/en-US.json), не на глаз.
  const uiAria = (words, op = "=") => `:is(${words.map(word => `[aria-label${op}"${word}"]`).join(",")})`;
  // Кнопка снятия вложения: «Remove <имя>» / «Удалить <имя>» («Remove {files}» → «Удалить: {files}»); очередь
  // сообщений («Remove queued message» → «Удалить сообщение из очереди») — не вложение.
  const ATTACH_REMOVE_RE = /^(?:remove|удалить)(?=[\s:]|$)/i;
  const attachRemoveLabel = label => ATTACH_REMOVE_RE.test(String(label ?? "").trim()) && !/queue|очеред/i.test(String(label ?? ""));
  const attachRemoveName = label => String(label ?? "").trim().replace(/^(?:remove|удалить):?\s+/i, "");
  const HANDLE_ID = "myclaude-input-handle";
  const STYLE_ID = "myclaude-input-handle-style";
  const EDITOR_ROOT_ATTRIBUTE = "data-myclaude-editor-root";
  const EDITOR_ATTRIBUTE = "data-myclaude-editor";
  const BLOCK_ATTRIBUTE = "data-myclaude-composer-block";
  // Кружок контекста в режиме чтения (#6737, раздел 6) и панель лимитов
  // (#6738, раздел 12ж). Константы стоят ЗДЕСЬ, а не в самих разделах: их
  // читают уборка сирот (раздел 3) и правила стилей (раздел 4) — то есть
  // раньше, чем разделы объявлены, и оттуда их `const`-ы ещё в TDZ.
  const RING_ATTRIBUTE = "data-myclaude-ring";
  const RING_PATH_ATTRIBUTE = "data-myclaude-ring-path";
  const RING_FADE_ATTRIBUTE = "data-myclaude-ring-fade";
  // Маски угловых затуханий ленты (applyCornerFade): их же складывает с краями прокрутки живой вид (WF185).
  const CORNER_FADE_MASK = "radial-gradient(ellipse var(--myclaude-fade-w) var(--myclaude-fade-h) at 0 0,rgba(0,0,0,.15) 55%,#000 100%)";
  const RING_FADE_MASK = "radial-gradient(ellipse var(--myclaude-ring-fade-w) var(--myclaude-ring-fade-h) at 100% 100%,rgba(0,0,0,.15) 55%,#000 100%)";
  // Пока мышь на кружке, родная подсказка Claude не показывается (#6906).
  const RING_HOVER_ATTRIBUTE = "data-myclaude-ring-hover";
  const USAGE_RING_SELECTOR = `[aria-haspopup="dialog"]${uiAria(["Usage:", "Использование:"], "^=")}`;
  // Куда кружок садится в свёрнутом поле: «на своём месте остаётся стоять,
  // просто плавает» (слово Элвиса 20.09) — то есть у правого нижнего угла, где
  // он и живёт в открытом поле. Отступы маленькие: ближе к углу — дальше от
  // полоски возврата, которая стоит по центру низа.
  const RING_INSET_RIGHT = 10;
  // Ниже нуля намеренно (#6905, слово Элвиса 21.09: «по вертикали его ещё
  // пониже можно»): считается отступ от низа СВЁРНУТОГО блока ввода, а он сам
  // стоит на 9 точек выше низа окна — при нуле кружок висел бы в воздухе.
  // Ветке кружка правило свёртки оставляет overflow:visible, вылезти ему есть
  // куда.
  const RING_INSET_BOTTOM = -5;
  // Свой микрофон рядом с кружком (#6907, слово Элвиса 21.09: «рядышком левее
  // этого кругляшка, значок микрофона… нажал — включилась диктовка, нажал ещё
  // раз — отправилось»). Кнопку диктовки и отправку жмёт Claude — мы только
  // нажимаем их за Элвиса, когда поле ввода свёрнуто и своей строки не видно.
  const MIC_ID = "myclaude-mic";
  const MIC_SIZE = 20;
  const MIC_GAP = 6;
  // Микрофон Диктатора в ОТКРЫТОМ поле (#7704, WF92; слово Элвиса 25.09: «этот
  // микрофон переносить влево, в поле ввода… верни его назад, но у него
  // поведение меняется… вызывает программу „Диктатор“»): значок встаёт у ЛЕВОГО
  // края нижней строки поля, строке слева добавляется место под него (метка —
  // правило раздела 4). Подсказка отказа (команда mic-refused) — свой узел.
  // Замер 25.09 (окно 350): строка [data-cds=ChatComposerChin] — display:block,
  // padding-left 8, шире рамки поля (левее на 8 pt); первая кнопка «Add» — на 7
  // pt правее левого края рамки .epitaxy-prompt. Значок встаёт на MIC_ROOM_INSET
  // от края рамки, а строке отступ 8 → 30: кнопки уезжают на 22 (значок + 2).
  const MIC_ROOM_ATTRIBUTE = "data-myclaude-mic-room";
  const MIC_ROOM_INSET = 6;
  const MIC_ROOM_PAD = 8 + MIC_SIZE + 2;
  // Окно у нижнего предела (строка CHIN_TINY, WF92-ap2): 22 pt сдвига выталкивали
  // правые кнопки строки за край. Значок жмётся к рамке (1 pt), строке — отступ
  // впритык под него: «Add» стоит на pad−1 от рамки, значок кончается на 21.
  const MIC_ROOM_INSET_TINY = 1;
  const MIC_ROOM_PAD_TINY = MIC_ROOM_INSET_TINY + MIC_SIZE + 2;
  const MIC_HINT_ID = "myclaude-mic-hint";
  // Кнопка «▦ Галерея» (#7724, раздел 12п; волна 2 WF97 — слово Элвиса
  // 26.09 ~04:23): в открытом поле — в нижней строке сразу правее левой группы
  // «+ Auto» (левее модели), у кружка в свёрнутом. Место под кнопку (с зазорами)
  // получает левая группа полем справа (метка GALLERY_ROOM_ATTRIBUTE и переменная
  // GALLERY_ROOM_VARIABLE), и модель отъезжает, не наезжая на кнопку.
  // WF103 (#7965, слово Элвиса 27.09): слова «Галерея» не видно нигде — только
  // значок 2×2 (слово — в title/aria-label), без рамки и заливки; ширина
  // одна и в широком, и в узком окне.
  // WF106 (#8099, слово Элвиса 29.09: «больно большие… чуть-чуть поменьше… яркие,
  // жёлтые»): значок на ~20 % меньше, «свежий» и «нажатый» — не
  // янтарём, а цветом текста окна; у свежего — маленькая точка-акцент.
  // #9507 (слово Элвиса 10.10 ~11:00 по снимку «10 ⊞ 54 ▶6»: «весь функционал кнопки… подменили, оно
  // сейчас не нужно»): числа файлов у значка нет — оно в подсказке.
  const GALLERY_ID = "myclaude-gallery";
  const GALLERY_ROOM_ATTRIBUTE = "data-myclaude-gallery-room";
  const GALLERY_ROOM_VARIABLE = "--myclaude-gallery-room";
  const GALLERY_WIDTH = 20;
  const GALLERY_HEIGHT = 20;
  const GALLERY_INSET = 6;
  const GALLERY_COMPACT_MAX = 360;
  const GALLERY_ICON = 12;
  // Кнопка «PMP» (#8894, WF125, раздел 12п¹; до того на её месте — «повторить
  // голос Рика», #7960): рядом с «Галереей»; с WF213 — во всех чатах главного окна
  // (в попапе — только в чате папки Rick) и открывает панель оркестрации страницы
  // (раздел 12п³); панель PimpMyClaude у часов — её командой «Настройки Пимпа»,
  // ответа ждём PMP_WAIT_MS.
  const PMP_ID = "myclaude-pmp";
  // Кнопка — тихая надпись «PMP» цветом соседних подписей, без серой плашки (#9136). Чисел у неё нет
  // (#9507, слово Элвиса 10.10 ~11:00 по снимку «10 ⊞ 54 ▶6»): процент недели с полоской (был с 08.10)
  // и «▶N» ушли — неделю показывает панель лимитов, идущие Workflow — панель на этой кнопке.
  const PMP_WIDTH = 24;
  const PMP_HEIGHT = 14;
  const PMP_FOLDER = "Rick";
  const PMP_CWD_MS = 3000;
  const PMP_WAIT_MS = 3000;
  const PMP_SILENT_TEXT = "PimpMyClaude не отвечает";
  const PMP_TITLE = "Workflow и терминалы";
  // Панель материалов слева в окне Claude (раздел 12п⁴, WF277, #10644): кнопка «PMP» у «Show/Hide sidebar»,
  // подложка места панели, рейка ширины и полоса перетаскивания окна над местом. Здесь — ради правил раздела 4.
  const DOCK_BUTTON_ID = "myclaude-dock-button";
  const DOCK_PLACE_ID = "myclaude-dock-place";
  const DOCK_RAIL_ID = "myclaude-dock-rail";
  const DOCK_DRAG_ID = "myclaude-dock-drag";
  // Три кнопки размера панели справа от «PMP» (#10759, WF282): узкая, пол-окна, всё окно.
  const DOCK_SIZES_ID = "myclaude-dock-sizes";
  // Панель оркестрации на кнопке PMP (#9370–#9373, #9405, WF213, раздел 12п³): пока открыта — сводка
  // /digest раз в PMP_PANEL_MS; закрыта — число идущих в подсказке кнопки не чаще раза в
  // PMP_COUNT_MS. Не шире PMP_PANEL_WIDTH и не выше PMP_PANEL_SHARE окна; ýже PMP_PANEL_NARROW —
  // текст строки под именем во всю ширину.
  const PMP_PANEL_ID = "myclaude-pmp-panel";
  const PMP_PANEL_MS = 10000;
  const PMP_COUNT_MS = 60000;
  const PMP_PANEL_WIDTH = 480;
  const PMP_PANEL_NARROW = 340;
  const PMP_PANEL_SHARE = 0.7;
  // WF226 (снимок Элвиса 10.10: поле — колонкой во всю высоту окна, панель ушла под верх окна, а
  // «Настройки Пимпа» выпали под её рамку). Над полем меньше PMP_PANEL_ROOM (команды в три строки и
  // PMP_PANEL_BODY тела) — панель встаёт сбоку от поля (сбоку не ýже PMP_PANEL_SIDE); нет места и
  // сбоку, а над полем не помещаются команды и PMP_PANEL_BODY — над кнопкой, поверх поля. От краёв
  // окна — PMP_PANEL_EDGE: за окно панель не выходит никогда. С #9552 команды — три кнопки с подписями и строка
  // мелких (~200–230 в ширину 480–360) плюс PMP_PANEL_BODY: отсюда 300 (было 180 при одной строке команд).
  const PMP_PANEL_ROOM = 300;
  const PMP_PANEL_BODY = 72;
  const PMP_PANEL_SIDE = 240;
  const PMP_PANEL_EDGE = 8;
  const PMP_ASK_TEXT = "Рик, что сейчас происходит и что висит из моих просьб — коротко, списком";
  const PMP_DOWN_TEXT = "PMP у часов не отвечает";
  // Кружок-подложка «+» у New (#9145, WF156) — снимает правило в RULES.
  const NEW_PLUS_SELECTOR = 'button[aria-keyshortcuts="Meta+n"] .df-new-circle';
  // Сводка Workflow всех проектов (GET /digest, К6; раздел 12п²) — для кнопки и панели PMP: запрос идёт
  // не дольше RICK_CELLS_MS, сводка старше RICK_CELLS_STALE_MS — числа у кнопки нет.
  const RICK_CELLS_MS = 30000;
  const RICK_CELLS_STALE_MS = 300000;
  // Блок счёта Workflow у поля ввода (12п², до page-60) снят по слову владельца 10.10 21:10. Его id, метка
  // и переменная на прокрутке поля и ключи хранилища остались только затем, чтобы раздел 3 убрал сирот
  // прошлой страницы.
  const RICK_CELLS_ID = "myclaude-rick-cells";
  const RICK_CARD_ID = "myclaude-rick-card";
  const RICK_FLOW_ID = "myclaude-rick-flow";
  const RICK_ROOM_ATTRIBUTE = "data-myclaude-rick-room";
  const RICK_ROOM_VARIABLE = "--myclaude-rick-room";
  const RICK_FILTER_KEY = "myclaude-rick-filter";
  const RICK_VIEW_KEY = "myclaude-rick-view";
  // «Отчёт» (#9163) — команда панели оркестрации: вставляет в поле ровно эту фразу и не отправляет. Фраза —
  // #9374 (слово Элвиса 09.10 23:50: «Только workflow по-русски… Вот как я написал сейчас, так пусть будет»).
  const RICK_REPORT_TEXT = "Рик, сделай отчёт по воркфлоу по правилам PMP";
  // Кегль и гарнитура подписей нижней строки поля, когда их не удалось прочитать (chinInk, раздел 12п).
  const RICK_TEXT_SIZE = 11;
  const RICK_FONT_FALLBACK = "-apple-system, system-ui, sans-serif";
  // «Скажи — и сделаю» и другие заголовки «нужен Элвис» мигают (#7703, раздел
  // 12м): метка заголовка, рисуют правила раздела 4.
  const ATTN_ATTRIBUTE = "data-myclaude-attn";
  // Слова-действия блока «Скажи — и сделаю» кнопками (#7755, раздел 12р):
  // метка слова ("" — кнопка, "on" — выбрано) и цифра отсчёта у заголовка.
  const SAY_ATTRIBUTE = "data-myclaude-say";
  const SAY_LEFT_ATTRIBUTE = "data-myclaude-say-left";
  // «Согласен» у пункта «❗ Ждёт тебя» (#10361): своя метка в начале пункта.
  const AGREE_ATTRIBUTE = "data-myclaude-agree";
  const DOALL_ATTRIBUTE = "data-myclaude-doall";
  // Нажималки в ответах (#7843, #7842, раздел 12с): строка «⚪» блока «🔘 ВЫБОР»
  // ("" — можно нажать, "on" — вписана в поле), своя обёртка кнопок, кнопка
  // (подпись — из атрибута, как у «💬 Новый чат» 12к) и её «нажато».
  const NAZH_PICK_ATTRIBUTE = "data-myclaude-nazh-pick";
  const NAZH_BOX_ATTRIBUTE = "data-myclaude-nazh";
  const NAZH_BUTTON_ATTRIBUTE = "data-myclaude-nazh-button";
  const NAZH_LABEL_ATTRIBUTE = "data-myclaude-nazh-label";
  const NAZH_ON_ATTRIBUTE = "data-myclaude-nazh-on";
  const DONE_LIST_ATTRIBUTE = "data-myclaude-done-list";
  const DONE_ITEM_ATTRIBUTE = "data-myclaude-done-item";
  const DONE_CONT_ATTRIBUTE = "data-myclaude-done-continuation";
  // Свёртки <details> (#9065, раздел 12ф): свой заголовок (closed|open, подпись
  // из атрибута), сырые <p> тегов, тело (closed|open); кнопка «Свернуть ответ»
  // длинного ответа (closed|open) и спрятанное ею.
  const FOLD_HEAD_ATTRIBUTE = "data-myclaude-fold-head";
  const FOLD_LABEL_ATTRIBUTE = "data-myclaude-fold-label";
  const FOLD_RAW_ATTRIBUTE = "data-myclaude-fold-raw";
  const FOLD_BODY_ATTRIBUTE = "data-myclaude-fold-body";
  const FOLD_WHOLE_ATTRIBUTE = "data-myclaude-fold-whole";
  const FOLD_LONG_ATTRIBUTE = "data-myclaude-fold-long";
  // «Прочитано» (#9377, раздел 12х): метка строки ленты прочитанного ответа (open — раскрыт,
  // head — первая строка свёрнутого блока, bare — то же у ответа без текста, rest — остальные
  // строки свёрнутого), блок текста с первой строкой, своя дорожка слева ("" | on), своя кнопка
  // поверх свёрнутого блока, наведение и подсветка после перехода, кнопка «непрочитанные N»; метка корня — поле слева от
  // текста уже дорожки. Край (top, bottom, оба) — у дорожек первой и последней строки ответа, что на виду: там
  // подложка всего блока скруглена; её ширина от левого края дорожки — переменная на корне (#9506).
  const READ_ROW_ATTRIBUTE = "data-myclaude-read";
  const READ_LINE_ATTRIBUTE = "data-myclaude-read-line";
  const READ_ZONE_ATTRIBUTE = "data-myclaude-read-zone";
  const READ_OPEN_ATTRIBUTE = "data-myclaude-read-open";
  const READ_HOT_ATTRIBUTE = "data-myclaude-read-hot";
  const READ_HIT_ATTRIBUTE = "data-myclaude-read-hit";
  const READ_EDGE_ATTRIBUTE = "data-myclaude-read-edge";
  const READ_LABEL_ATTRIBUTE = "data-myclaude-read-label";
  const READ_NEXT_ID = "myclaude-read-next";
  const READ_LEFT_VARIABLE = "--myclaude-read-left";
  const READ_WIDTH_VARIABLE = "--myclaude-read-width";
  const READ_SPAN_VARIABLE = "--myclaude-read-span";
  const READ_TIGHT_ATTRIBUTE = "data-myclaude-read-tight";
  // «Просмотрено» у карточек файлов (WF239, раздел 12м³): метка карточки ("" — галочка стоит, on —
  // просмотрено) и своя кнопка-галочка в её правом верхнем углу.
  const SEEN_ATTRIBUTE = "data-myclaude-seen";
  const SEEN_CHECK_ATTRIBUTE = "data-myclaude-seen-check";
  // Главы чата (WF241, раздел 12х²): родная дорожка Claude `.epitaxy-toc > nav` — полоски (ol
  // aria-hidden) и меню с названиями (div > ol[role=list]). Метки: меню открыто (на nav), глава
  // прочитана (на строке дорожки и строке меню), своя кнопка-галочка в строке меню; свои узлы —
  // затемнение окна и панель настройки вида; вид — три переменные на <html>.
  const CH_NAV_SELECTOR = ".epitaxy-toc > nav";
  const CH_RAIL = `${CH_NAV_SELECTOR} > ol[aria-hidden="true"]`;
  const CH_MENU = `${CH_NAV_SELECTOR} > div`;
  const CH_OPEN_ATTRIBUTE = "data-myclaude-ch-open";
  const CH_ROOM_VARIABLE = "--myclaude-ch-room";
  const CH_READ_ATTRIBUTE = "data-myclaude-ch-read";
  const CH_CHECK_ATTRIBUTE = "data-myclaude-ch-check";
  const CH_DIM_ID = "myclaude-ch-dim";
  const CH_SET_ID = "myclaude-ch-settings";
  const CH_STEP_VARIABLE = "--myclaude-ch-step";
  const CH_THICK_VARIABLE = "--myclaude-ch-thick";
  const CH_INK_VARIABLE = "--myclaude-ch-ink";
  const CH_OK_VARIABLE = "--myclaude-ch-ok";
  // #9758: звёздочка-закладка в строке меню (кнопка) и метка «в закладках» на строках дорожки и меню; своя
  // глава ответа без главы Claude (#9757: li в обоих списках); на nav — текущая глава своя, не Claude.
  const CH_STAR_ATTRIBUTE = "data-myclaude-ch-star";
  const CH_STARRED_ATTRIBUTE = "data-myclaude-ch-starred";
  const CH_OWN_ATTRIBUTE = "data-myclaude-ch-own";
  const CH_MINE_ATTRIBUTE = "data-myclaude-ch-mine";
  // Вид по умолчанию: шаг — строка меню с названием («на таком же расстоянии, как тексты»), толщина 2 px.
  // Яркость тише Claude (#9758, слово Элвиса 11.10 08:24: «главы сильно яркие… более тусклыми… текущую
  // главу сделай менее яркой»): 12 % цвета текста у обычной (у Claude 20), у текущей — на 30 пунктов ярче.
  // #10764 (слово Элвиса 23.10 19:30, скрин №3: «надо увидеть эти полосочки… должны быть левее, они должны быть
  // крупнее»): толщина 3 px, яркость 35 % (текущая — 65 %).
  const CH_LOOK = {
    step: { min: 14, max: 40, by: 1, base: 26, name: "Расстояние", unit: "" },
    thick: { min: 1, max: 6, by: 0.5, base: 3, name: "Толщина", unit: "" },
    ink: { min: 8, max: 70, by: 1, base: 35, name: "Яркость", unit: " %" },
  };
  const CH_STEP = `var(${CH_STEP_VARIABLE},${CH_LOOK.step.base}px)`;
  const CH_THICK = `var(${CH_THICK_VARIABLE},${CH_LOOK.thick.base}px)`;
  const CH_INK = `var(${CH_INK_VARIABLE},${CH_LOOK.ink.base / 100})`;
  const CH_OK = `var(${CH_OK_VARIABLE},rgb(77,187,125))`;
  // «Работа идёт» одной строкой (слово Элвиса 10.10 10:20, раздел 12х¹): метка спрятанного серией —
  // на блоке хода (rest — свёрнут, open — раскрыт, open-first — первый раскрытый под строкой) и на
  // строке ленты, занятой серией целиком (row); своя строка-сводка (live — работа идёт, done — шла),
  // её части (arrow | label | ring | steps | failed) и подпись части (текста в узлах нет).
  const WORK_ATTRIBUTE = "data-myclaude-work";
  const WORK_LINE_ATTRIBUTE = "data-myclaude-work-line";
  const WORK_PART_ATTRIBUTE = "data-myclaude-work-part";
  const WORK_TEXT_ATTRIBUTE = "data-myclaude-work-text";
  // Полоса хода (WF245, слово Элвиса 11.10 01:40: «полосу загрузки… поделена на семь секторов… тоненькие
  // линии»): счёт «k/N» строки шага — на части bar строки-сводки и на абзаце одиночной строки шага
  // (у абзаца подпись без счёта — в WORK_TEXT_ATTRIBUTE). Метка echo — хвостовой абзац «Работа идёт»
  // ответа, сразу под которым стоит свёрнутая серия: одно и то же один раз.
  const WORK_BAR_ATTRIBUTE = "data-myclaude-work-bar";
  // Ответ-точка (слово Элвиса 11.10 05:40, раздел 12х³): метка строки ленты, которой не видно, —
  // row — сам ответ-точка, gap — пустая строка прямо над ним. Точка — последний блок хода (в её строке
  // панель кнопок ответа): строка остаётся (tail), не видно только колонки текста (text).
  const DOT_ATTRIBUTE = "data-myclaude-dot";
  const WORK_BAR_MAX = 30;
  // Bypass во всех чатах (#9060, раздел 12с¹): пока страница сама выбирает режим, меню
  // режимов Claude невидимо — без мигания.
  const BYPASS_QUIET_ATTRIBUTE = "data-myclaude-bypass-quiet";
  const DICTATE_SELECTOR = 'button[aria-label="Press and hold to record"],button[aria-label="Stop dictation"],' +
    'button[aria-label="Нажмите и удерживайте для записи"],button[aria-label="Остановить диктовку"]';
  // Стрелка ⌄ настроек диктовки (живой замер 23.09: aria-label «Dictation
  // settings», display:flex, 18 px — поиск «кнопка без текста рядом с
  // микрофоном» её не находил). Ищем по подписи, как и сам микрофон.
  const DICTATE_SETTINGS_SELECTOR = 'button[aria-label="Dictation settings"],button[aria-label="Настройки диктовки"]';
  const DICTATE_LIVE_LABEL = "Stop dictation";
  const SEND_SELECTOR = '[data-testid="code-prompt-send"]';
  // Нижняя строка поля ввода (#7206, WF84, вариант 8.1 макета
  // docs/8-footer-opus-5.5.html): мельче (10 px в узком окне, 11 в широком),
  // кнопки 16×16, в узком окне подписи коротко — «O55 · Hi · Au». Микрофон
  // Claude и его стрелка ⌄ спрятаны СТИЛЕМ (ответ Элвиса 8.2: «микрофон убрать
  // совсем») — кнопка остаётся в разметке: её жмёт наш микрофон у кружка в
  // режиме «claude» (раздел 12з, #7054). Константы здесь: их читают правила
  // раздела 4. Метки ставит раздел 12з¹ (markChin): что за кнопка — "text",
  // "icon" или "hide"; у подписи — её короткая форма.
  const CHIN_SELECTOR = '[data-cds="ChatComposerChin"]';
  // Поле ввода целиком: с Claude 4.29 (замер WF297, #11173) микрофон не в нижней строке, а рядом с отправкой
  // ([data-testid="code-prompt-trailing-controls"]) — ищем его во всём поле, где стоит строка.
  const COMPOSER_SELECTOR = '[data-cds="ChatComposer"]';
  const CHIN_ATTRIBUTE = "data-myclaude-chin";
  const CHIN_SHORT_ATTRIBUTE = "data-myclaude-short";
  // Нижняя строка подписи в две строки («5.5» под «Opus», «Ex» под «Effort») — крупно, слово над ней мелко (#9813).
  const CHIN_TAIL_ATTRIBUTE = "data-myclaude-short-tail";
  // Кнопку режима держит карточка PMP «что делает каждый режим» (раздел 12з², #6591): пока метка стоит, своей
  // подсказки браузера (title, chinTitle) у кнопки нет — две всплывашки разом не нужны.
  const MODE_HINT_HOLD_ATTRIBUTE = "data-myclaude-mode-hint";
  // Уже этого окна подписи коротко. WF94 (#7745, слово Элвиса 26.09 ~01:20:
  // «место позволяет… опус 55, экстра и Авто… коротко — только в самых крайних
  // случаях, когда окно супер узкое»): было 479, замер 26.09 — окно 399 CSS px,
  // строка 386, свободно ~220, полным подписям нужно ещё ~56…100.
  const CHIN_NARROW_MAX = 299;
  // Тесная СТРОКА, а не окно (#7638, #8732; слова Элвиса 04.10: «правая панелька
  // не влезает… справа не хватает места для кругляшка» и следом «зачем ты
  // сократил, здесь же хватает места, чтобы написать Opus 5.5 Extra, и нужно
  // писать O55, а не просто О5»): при открытой боковой панели окно 776 оставляет
  // строке 317 — порог по окну этого не видит. Подписи коротко (AU · O55 · EX)
  // только когда полные вылезли за край строки — по замеру (chinRowFit, 12з¹).
  const CHIN_ROW_ATTRIBUTE = "data-myclaude-chin-narrow";
  // Запас против дребезга: к полным подписям — когда строка шире нужного на столько.
  const CHIN_ROW_SLACK = 8;
  // Короткой строке у пола колонки — столько точек между группами (WF183): кружок не прижат к соседу.
  const CHIN_FLOOR_SLACK = 4;
  // Совсем узкое окно (слово Элвиса 23.09 ~21:05, #7206: «сворачивать ещё…
  // чтоб настолько маленьким можно было сделать»): поля кнопок 1 px, зазоры
  // 1 px. WF94: было 319, вслед за узким порогом — 259.
  const CHIN_TINY_MAX = 259;
  // Значок Диктатора жмётся к рамке в окнах уже 320 (WF92-ap2) — свой порог:
  // до WF94 он делил число с CHIN_TINY_MAX, подписи его не двигают.
  const MIC_ROOM_TINY_MAX = 319;
  // Время под каждым сообщением (#7747, WF94, раздел 14): строка сообщения
  // Claude Code (у реплики человека — .epitaxy-user-turn с тем же классом) и
  // метка нашего узла с текстом времени. Константы здесь: их читают правила
  // раздела 4.
  const MESSAGE_ROW_SELECTOR = '[class*="group/message-row"]';
  const STAMP_ATTRIBUTE = "data-myclaude-stamp";
  // Состояние чата (#7750, WF94, раздел 12о): у последнего сообщения — warm |
  // cold (его время красное). Константа здесь: её читают правила раздела 4.
  const STALE_ATTRIBUTE = "data-myclaude-stale";
  // Кнопка «💬 Новый чат» под блоком передачи (#7246, раздел 12к):
  // метка обёртки и атрибут с подписью — здесь, их читают правила раздела 4.
  const CONTINUE_ATTRIBUTE = "data-myclaude-continue";
  const CONTINUE_LABEL_ATTRIBUTE = "data-myclaude-continue-label";
  // Ссылка на заголовках «ОТКРОЙ НОВЫЙ ЧАТ» (WF88, К15) и её состояние wait|ack.
  const CONTINUE_LINK_ATTRIBUTE = "data-myclaude-continue-link";
  const CONTINUE_LINK_STATE_ATTRIBUTE = "data-myclaude-continue-state";
  // Текст заголовка-ссылки для блика по буквам (#7865): ::before рисует его копию поверх с бегущей
  // светлой полосой — свои узлы в заголовок React не вставляем, эмодзи заголовка не портятся.
  const CONTINUE_LINK_TEXT_ATTRIBUTE = "data-myclaude-continue-text";
  // Подпись кнопки, пока зовём Пимпа, без ⏳ — её рисует CSS (правила раздела 4) рядом с кружком.
  const CONTINUE_WAIT_TEXT = "Зову PMP…";
  // Занято (#7772, WF97): атрибут ставят подписи «⏳ Зову Пимпа…» и родня —
  // повтор нажатия ничего не делает. Переливаются буквы только у плашки
  // «Новое окно»: ссылка «ОТКРОЙ НОВЫЙ ЧАТ» и кнопка под блоком с WF98 — простые
  // (#7852, слово Элвиса: «дискотеку убери… просто ссылочку, как была»).
  const BUSY_ATTRIBUTE = "data-myclaude-busy";
  // Место под ряд номеров полосы прогресса (раздел 2б): метка рамки поля,
  // которой добавлено нижнее поле, и сколько точек добавлено. Константы ЗДЕСЬ:
  // их читает правило широкого вида (layoutCss, раздел 2а) — раньше, чем
  // объявлен раздел 2б.
  const PROGRESS_ROOM_ATTRIBUTE = "data-myclaude-progress-room";
  const PROGRESS_ROOM_VARIABLE = "--myclaude-progress-room";
  // Расшифровка приезжает не сразу и печатается кусками: ждём её до 12 с и жмём
  // «отправить», когда текст постоял неизменным три круга.
  const MIC_WAIT_MS = 12000;
  const MIC_TICK_MS = 150;
  const MIC_STEADY = 3;
  // Режим кружка (К4, #7054): "claude" — родная диктовка Claude, "dictator" —
  // клавишу Диктатора (F5 у Элвиса) жмёт ПРИЛОЖЕНИЕ по клику в кружок, а
  // страница только держит фокус и взводит отправку. Ключ шлёт приложение
  // командой mic, и "dictator" — только пока Диктатор запущен. Расшифровка
  // Диктатора длиннее родной — ждём её дольше.
  const MIC_MODE_KEY = "myclaude.mic";
  const MIC_DICTATOR_WAIT_MS = 30000;
  // Отказ приложения (команда mic-refused, WF92): Диктатор уже пишет — в это
  // или в другое окно. Своим считает отказ окно, где микрофон нажали не раньше
  // MIC_REFUSED_MS назад (команда идёт во все страницы); подсказка — MIC_HINT_MS.
  const MIC_REFUSED_MS = 4000;
  const MIC_HINT_MS = 3000;
  const MIC_REFUSED_TEXT = "Сначала останови запись в Диктаторе";
  // Наведение на кружок открывает панель лимитов (#6906): столько держим, чтобы
  // случайный проход мышью её не дёргал, и столько ждём после ухода мыши.
  const RING_HOVER_OPEN_MS = 320;
  const RING_HOVER_CLOSE_MS = 260;
  const HEIGHT_VARIABLE = "--myclaude-input-height";
  // Высота и ступень — в sessionStorage. Отступление от донора (у него высота в
  // localStorage) намеренное: профиль у всех окон Claude общий, и новое окно
  // поднималось бы уже растянутым. sessionStorage у каждого окна свой и
  // переживает перезагрузку страницы.
  const HEIGHT_STORAGE_KEY = "myclaude-input-height-v1";
  const STAGE_STORAGE_KEY = "myclaude-input-stage-v1";
  // «Обкэшить» кладёт перенос в localStorage: забирает его ДРУГОЕ окно (⌘N).
  const CASHOUT_KEY = "myclaude-cashout";

  // Зона захвата полоски — как у донора. Заметность даёт не зона (она
  // прозрачная), а сама линия в 2 точки, поэтому «полоска едва заметная» от
  // высокой зоны не толстеет, зато мышью в неё попадаешь. Полоска сидит верхом
  // на кромке рамки, то есть выше кромки её ровно половина — донорские 9 точек,
  // больше не поднимаемся.
  const HANDLE_HEIGHT = 18;
  // Полоска узкая и строго по центру поля (донор): во всю ширину рамки её зона
  // захвата накрывает кнопки и параметры по краям поля, и Элвис назвал такую
  // полоску «широченной». Сотни точек хватает, чтобы схватить её мышью.
  const HANDLE_NARROW_WIDTH = 96;
  // Уже этого полоска не ужимается ни в каком окне: мышью в неё уже не попасть.
  const RAIL_MIN_WIDTH = 64;
  // Уже этого рамка поля считается вырожденной: React как раз пересобирает низ
  // окна, и мерить по ней ось полосок нельзя — считаем по окну.
  const RAIL_HOST_MIN = 200;
  // Отступ свёрнутой полоски от краёв рамки: её собственное скругление плюс
  // пара точек, но не меньше этого.
  const HANDLE_MIN_INSET = 10;
  // Дубли полоски у краёв окна (#6743, слово Элвиса 20.09 и 21.09: «полос три —
  // снизу, на поле ввода и сверху… прижал, нажал, прижал, нажал»). Только
  // нажималки: тянуть за них нельзя — рука ушла бы за край окна вместе с полем.
  // С 21.09 (#6891) все три полоски — одна и та же полоска: общая ось, ширина,
  // высота зоны захвата и сама линия («они все три должны быть соосными, все в
  // одном месте… все одной толщиной»). Считает место railSeat, раздел 9.
  const SUPER_TOP_ID = "myclaude-super-top";
  const SUPER_BOTTOM_ID = "myclaude-super-bottom";
  // Потолок высоты поля, запасное значение: плитка окна отступает от края на 9
  // точек, титульная полоса .epitaxy-titlebar занимает 32. Меряем саму полосу —
  // на части экранов Claude её просто нет, и константа врала бы.
  const SAFE_TOP_INSET = 42;
  const MIN_HEIGHT = 38;
  // Обычная высота поля, пока её ни разу не удалось замерить (поле свёрнуто с
  // самого открытия окна). Только запасное значение.
  const NATURAL_FALLBACK = 96;
  // Насколько ниже минимума надо протянуть, чтобы поле свернулось: случайный
  // перелёт на пару точек сворачивать не должен.
  const COLLAPSE_DRAG_SLACK = 44;
  // Упор у своей высоты Claude при тяге (#11693): дальше этого от неё — поле растянуто или сжато рукой,
  // ближе половины — снова «обычная высота»; разные пороги — дрожь руки на границе ступень не перещёлкивает.
  const STAGE_DRAG_SLACK = 12;
  // Двойной клик метит чуть НИЖЕ упора: недобор на несколько точек глазами не
  // виден, а перелёт приходится подтягивать обратно — вот это уже видно как
  // лесенка.
  const CEILING_UNDERSHOOT = 8;
  // Насколько грубо надо промахнуться, чтобы разрешить второй — и последний —
  // шаг разворота. Порог заметно больше недобора: иначе второй шаг срабатывал
  // бы всегда и лесенка вернулась бы.
  const CEILING_RETRY_GAP = 28;
  // Прибавка высоты, ушедшая не вверх, а в пустоту. Больше этого — значит
  // контейнер Claude верх поля дальше не пустил, и замеренный пол пора
  // запомнить: в следующий раз целимся сразу в него.
  const CEILING_WASTE_SLACK = 3;
  // Сколько места сверх обычной высоты обязана оставлять полю отметка, чтобы
  // считаться потолком. Меньше — это не потолок, а промах замера: низ шапки,
  // найденный вплотную к полю, или пол, записанный по рамке, которая и не
  // думала двигаться. Целиться в такую отметку — значит не делать ничего, и
  // именно так двойной клик и умирал в главном окне.
  const CEILING_MIN_ROOM = 80;
  // Сдвиг в пределах этого допуска — ещё клик, а не перетаскивание.
  const CLICK_SLACK = 4;
  // Одиночный клик ждёт возможного второго: без задержки каждый двойной клик
  // успевал бы сначала сделать лишний шаг по лестнице.
  const CLICK_STEP_DELAY = 260;
  // Лестница ровно из трёх положений: полоска → обычная высота → растянуто.
  const STAGE_COLLAPSED = 0;
  const STAGE_NORMAL = 1;
  const STAGE_STRETCHED = 2;
  // Полный проход раскладки — это обход документа с замерами, то есть
  // принудительный reflow. Пока Claude печатает ответ, мутаций сотни в секунду,
  // поэтому проход не чаще раза в 250 мс плюс фильтр affectsComposer.
  const LAYOUT_MIN_GAP = 250;
  // Страховочный проход: в спрятанном или перекрытом окне macOS не даёт кадров
  // вовсе, и requestAnimationFrame молчит — тогда доводим руками.
  const HEARTBEAT_MS = 500;
  // Сколько ждём появления поля ввода, прежде чем признать страницу чужой.
  const GIVE_UP_MS = 60000;
  // Отказ не окончательный: раз в столько проверяем, не приехала ли разметка
  // Claude позже (окно «Open in new window» рождается пустым about:blank).
  const REVIVE_MS = 5000;
  const CASHOUT_FRESH_MS = 90000;
  const CASHOUT_TICK_MS = 300;
  // Перенос из подчинённого окна (WF37): пока цепочка «Нового окна» не назвала
  // адресата, запись помечена этим словом. Своё окно она узнаёт по id чата, а
  // срок ей считается от ШТАМПА, а не от нажатия: между нажатием и рождением
  // нового чата проходит несколько секунд работы цепочки.
  const CASHOUT_PENDING = "pending";
  const CASHOUT_STAMP_FRESH_MS = 60000;
  // Отказ «Обкэшить» виден плашкой, как у соседних пунктов: раньше он молчал, а
  // новый чат всё равно открывался — Элвис получал пустое окно без объяснений
  // (находка ревизии 08.09). Плашку рисует newWindowNote раздела 12б.
  const CASHOUT_NOTE_EMPTY = "Нечего переносить";
  // Доезд ПОДТВЕРЖДАЕТСЯ, а не предполагается (WF50, #5780). Урок донора
  // ElvisOS (claude-handoff-main.js:1185-1213): мгновенная проверка врала «не
  // попал» уже после удачной вставки — редактор применяет большой текст не
  // сразу. Ждём паузами, потом пробуем ВТОРЫМ способом и ждём ещё. Теперь цена
  // ошибки выросла: по подтверждению приложение закрывает окно-донор (#5768),
  // и молчаливый промах стоил бы Элвису текста, а не пустого чата.
  const CASHOUT_CONFIRM_MS = 150;
  const CASHOUT_CONFIRM_FIRST = 12;
  const CASHOUT_CONFIRM_SECOND = 20;
  // Сравниваем нормализованно и не побайтно: редактор переписывает вставленное
  // по-своему (списки, кавычки, разметка). Совпала голова — доехало; не совпала,
  // но длина близка к нужной — тоже доехало.
  const CASHOUT_HEAD = 40;
  const CASHOUT_RATIO = 0.9;
  // Чужой черновик в поле — не приговор (#5781). Свежий чат иногда доезжает с
  // прошлым черновиком, и Claude убирает его сам (ElvisOS :1424): столько ждём,
  // а дальше вставляем ПОВЕРХ выделения всего поля (:1199) — черновик донора и
  // так уже внутри переноса.
  const CASHOUT_DRAFT_WAIT_MS = CASHOUT_CONFIRM_MS * CASHOUT_CONFIRM_FIRST;
  // Вложения переноса (#5773). Потолки полки и груза — донорские; байты никуда
  // не сериализуются, File едет ссылкой через память ГЛАВНОГО окна.
  const CASHOUT_FILES_MAX = 24;
  const CASHOUT_BYTES_MAX = 48 * 1024 * 1024;
  // Дешёвый ключ содержимого: djb2 по первым 8 КБ (ElvisOS contentKey). Восемь
  // скриншотов macOS все зовутся image.png — отличить их можно только байтами.
  const CASHOUT_HASH_BYTES = 8192;
  // Уборка полки (#5789, ElvisOS SWEEP_MS/GRACE_MS): как часто сверяем полку с
  // полем и сколько неприкосновенна свежая запись — между вставкой файла и
  // появлением его плашки у Claude проходит заметное время.
  const CASHOUT_SWEEP_MS = 2000;
  const CASHOUT_SWEEP_GRACE_MS = 10000;
  // Карточки вложений рисуются не мгновенно: столько ждём их появления.
  const CASHOUT_ATTACH_MS = 200;
  const CASHOUT_ATTACH_TRIES = 40;
  // Груз переживает и запись (90 с от нажатия), и её штамп (60 с от штампа).
  const CASHOUT_CARRY_FRESH_MS = CASHOUT_FRESH_MS + CASHOUT_STAMP_FRESH_MS;
  // Слова приговора доставки — их читает приложение (status().cashout.delivery).
  const CASHOUT_WAIT = "ждём";
  const CASHOUT_DONE = "вставлено";
  // Ответ сторожа на запись «Нового чата» в главном окне (К1): не его дело.
  const CASHOUT_HANDOFF_MAIN = "перенос «Нового чата»";
  const CASHOUT_REFUSED = "отказ";
  // Полка вложений — ОТДЕЛЬНЫЙ глобал окна, а не замыкание экземпляра: лоадер
  // перечитывает inject.js по mtime, и полка в замыкании умирала бы вместе с
  // экземпляром, унося всё, что Элвис уже положил в поле (урок ElvisOS
  // claude-chat-cleaner-inject.js:121-126). dispose её не трогает намеренно.
  const CASHOUT_FILES_GLOBAL = "__myclaudeFiles";
  // Плашки про вложения: молчать нельзя — потеря вложения молчаливой уже была.
  const CASHOUT_NOTE_LEFT = count => `Вложения останутся здесь: ${count}`;
  const CASHOUT_NOTE_PART = (done, want) => `Вложения доехали не все: ${done} из ${want}`;
  // Ниже этой высоты сосед рамки — пустая обёртка, а не строка модели.
  const MODEL_ROW_MIN_HEIGHT = 8;
  // Признак рамки поля — скругление: у Claude Code это 10px, у контейнеров
  // вокруг скруглений нет вовсе.
  const FRAME_RADIUS = 6;
  const FRAME_RISE = 140;
  const POPUP_MIN_Z = 20;
  const BOTTOM_SAFE_INSET = 2;
  // Выступ меньше этого — дрожь замера, а не уехавший за край окна низ.
  const BOTTOM_TRIM_SLACK = 1;
  const EDITOR_SELECTOR = '.ProseMirror[contenteditable],[contenteditable="true"],textarea';
  // Обе свёртки разом («collapsed» и «collapsed-ring», #6737): по этой примете
  // свёрнутое поле остаётся НАЙДЕННЫМ, хотя геометрия у него нулевая, — и
  // ветка с кружком тут ничем не отличается от остальных.
  const COLLAPSED_BLOCK_SELECTOR = `[${BLOCK_ATTRIBUTE}^="collapsed"]`;
  // Роли — самое устойчивое, что есть у меню и модалок: классы Claude
  // перегенерирует каждый релиз, а role держит доступность.
  const OVERLAY_SELECTOR = '[role="menu"],[role="listbox"],[role="dialog"]';
  // Открытые поповеры и меню Claude для правил «наши слои уступают» (WF136/WF144, WF179): кроме меню и
  // списков — диалоги и поповеры (панель «Контекст / лимиты» — `[role="dialog"][data-cds="Popover"]`,
  // recon WF78; снимок 09.10 02:30: ячейки Рика читались сквозь неё), открытое содержимое Radix-поппера
  // (подсказки — `delayed-open`/`instant-open` — не в счёт: иначе полоса мигала бы от наведения). Свои
  // диалоги (`#myclaude-…`: просмотр фото, «Запустить?») — не Claude.
  const CLAUDE_POPUP_SELECTOR = '[role="menu"],[role="listbox"],[role="alertdialog"],[role="dialog"]:not([id^="myclaude-"]),[data-cds="Popover"],[data-radix-popper-content-wrapper] > [data-state="open"]';
  // Сторож фокуса (#9055, класс по WF136 п.11–12): открытое меню Base UI / Floating UI
  // вставляет рядом со своей кнопкой пустой span. Соседи и счёт детей, по которым мы
  // узнаём узлы Claude, его не видят — иначе разметка перескакивает, пока меню открыто.
  const FOCUS_GUARD_SELECTOR = "[data-base-ui-focus-guard],[data-floating-ui-focus-guard]";
  const isFocusGuard = node => {
    try { return Boolean(node?.matches?.(FOCUS_GUARD_SELECTOR)); } catch { return false; }
  };
  const realKids = node => [...(node?.children ?? [])].filter(kid => !isFocusGuard(kid));
  const nextReal = node => {
    let next = node?.nextElementSibling ?? null;
    while (next && isFocusGuard(next)) next = next.nextElementSibling ?? null;
    return next;
  };
  // Последний ответ ассистента для «Обкэшить». Селекторов три: разметка чата
  // Claude Code и обычного claude.ai различается, и какой из них жив сегодня —
  // видно только в живом окне.
  // '[aria-label^="Message"]' цепляет заодно строку действий под ответом
  // ('[aria-label="Message actions"]' с «3 minutes ago») и вложенные куски
  // одного ответа — отсев и выбор внешнего узла живут в lastAnswerText.
  const ANSWER_SELECTOR = '[data-testid="assistant-message"],[aria-label^="Message"],[aria-label^="Сообщение"],div.font-claude-response';
  // Приметы ленты разговора: если хоть одна внутри кандидата в блок ввода —
  // кандидат не тот, и сворачивать его нельзя.
  const TRANSCRIPT_SELECTOR = '.epitaxy-transcript-width,[data-testid="assistant-message"],.font-claude-response,[data-testid="epitaxy-virtual-transcript"]';
  // Приметы того, что разговор уже идёт. Список широкий намеренно: разметка
  // чата в claude.ai и в окне Claude Code разная, и в сборке 1.40609.1 живой
  // оказалась не всякая — `.epitaxy-transcript-width` там нет вовсе (замер
  // оркестратора), из-за чего разговор считался пустым чатом. Ленты
  // `[data-testid="epitaxy-virtual-transcript"]` в списке нет намеренно: она
  // висит в окне и до первого сообщения, и пустой чат перестал бы быть пустым.
  const CHAT_STARTED_SELECTOR = '.font-claude-response,[data-user-message-bubble],' +
    '[data-testid="assistant-message"],.epitaxy-user-turn,.epitaxy-transcript-width,' +
    '[aria-label="Message actions"],[aria-label="Действия с сообщением"]';

  const now = () => (typeof performance?.now === "function" ? performance.now() : Date.now());
  HATCH && Object.assign(HATCH, { NEW_PLUS_SELECTOR, PMP_ASK_TEXT, RICK_REPORT_TEXT, attachRemoveLabel, attachRemoveName });

