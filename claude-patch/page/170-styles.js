  // ---- 4. Стили и сама полоска -------------------------------------------
  // WF173: текст ответа Claude (не реплики человека) и карточки файлов ленты (не поля ввода).
  const ANSWER_PROSE = '.epitaxy-chat-panel [data-cds="AssistantMessage"] [data-cds="Prose"]';
  // WF225 (#9426, слово Элвиса 10.10 по снимку раскрытой свёртки с полосой слева: при развороте
  // свёрнутые группы выделять так же — большая группа или небольшая, «так смотреть удобнее»).
  // Узел полосы — тело раскрытой <details> (метка open); под раскрытой кнопкой «Свернуть ответ»
  // полосы нет (слово Элвиса 10.10 10:47, page-61). Свои заголовки свёрток в полосе — отдельным
  // правилом (стрелка не сдвигается); в свёрнутом блоке «Прочитано» полосы нет — там узлы нулевой высоты.
  const FOLD_STRIP = `[${FOLD_BODY_ATTRIBUTE}="open"]:not([${FOLD_HEAD_ATTRIBUTE}],[${FOLD_RAW_ATTRIBUTE}],:is([${READ_ROW_ATTRIBUTE}="head"],[${READ_ROW_ATTRIBUTE}="bare"]) *)`;
  const FOLD_STRIP_HEAD = `[${FOLD_HEAD_ATTRIBUTE}][${FOLD_BODY_ATTRIBUTE}="open"]`;
  const FOLD_STRIP_LEFT = "calc(var(--myclaude-fold-mid, 7.4px) - .75px)";
  // В прозе Code — весом выше правил WF173, в прочих видах ленты — без неё (как у цитаты WF182).
  const foldStripRule = (tail, body) => `${ANSWER_PROSE} ${tail},${tail}{${body}}`;
  // «Работа идёт» одной строкой (раздел 12х¹): стрелка её строки стоит на 4 px левее стрелки свёрток.
  const WORK_STRIP_LEFT = "calc(var(--myclaude-fold-mid, 7.4px) - 4.75px)";
  // Полоса хода (WF245): шаг сектора вместе с зазором, ширина полосы (сжимается), тона.
  const WORK_BAR_GAP = 3;
  const WORK_BAR_STEP = `calc((100% + ${WORK_BAR_GAP}px) / var(--myclaude-work-n))`;
  const WORK_BAR_WIDTH = `min(calc(var(--myclaude-work-n) * 12px - ${WORK_BAR_GAP}px),180px)`;
  const WORK_BAR_FILL = "var(--cds-text-accent,currentColor)";
  const WORK_BAR_TONE = "color-mix(in srgb,currentColor 24%,transparent)";
  const FEED_FILE_TILE = '.epitaxy-chat-panel [data-cds="MessageAttachmentsFile"]:not([data-cds-composer-attachments] *)';
  // Превью HEIC (раздел 12м⁴): метка плитки с картинкой и самой картинки.
  const HEIC_ATTRIBUTE = "data-myclaude-heic";
  const HEIC_IMG_ATTRIBUTE = "data-myclaude-heic-img";
  // Карточки SendUserFile (#10603): квадрат Claude растёт до высоты 180 (метка кнопки и узлов до картинки),
  // ширина — переменной на кнопке.
  const HEIC_GROW_ATTRIBUTE = "data-myclaude-heic-grow";
  const HEIC_BOX_ATTRIBUTE = "data-myclaude-heic-box";
  const HEIC_WIDTH_VAR = "--myclaude-heic-w";
  const RULES = [
    // Полоска висит поверх всего и позиционируется координатами: рамка поля
    // живёт в чужом дереве, и вставлять в него свой узел — лишний риск.
    // Три полоски — одна и та же полоска (#6891, слово Элвиса 21.09: «все три
    // должны быть соосными… все одной толщиной»): зона захвата, линия и её
    // поведение общие, разница только в курсоре — за основную тянут, дубли у
    // краёв окна жмут.
    // `-webkit-app-region:no-drag` нужен всем трём. Верхний дубль садится на
    // титульную полосу Claude, а основная полоска заезжает на неё же, когда
    // поле растянуто до потолка (#6893, слово Элвиса 21.09: «хоть у меня стрелка
    // вниз — всё равно полоска должна отрабатывать»): титульная полоса таскает
    // окно, и без no-drag нажатие уходило в перетаскивание окна, а не в шаг.
    `#${HANDLE_ID},#${SUPER_TOP_ID},#${SUPER_BOTTOM_ID}{position:fixed;display:none;align-items:center;justify-content:center;height:${HANDLE_HEIGHT}px;padding:0;border:0;background:transparent;user-select:none;-webkit-user-select:none;-webkit-app-region:no-drag;touch-action:none;z-index:2147483646}`,
    `#${HANDLE_ID}{cursor:ns-resize}`,
    `#${SUPER_TOP_ID},#${SUPER_BOTTOM_ID}{cursor:pointer}`,
    // Едва заметная линия в цвет текста: 0.10 — слово Элвиса «полоска едва
    // заметная, при наведении видимая».
    // Линия в покое — .22 (#7201: при .10 на тёмных темах их «нету» вовсе).
    `#${HANDLE_ID}>span,#${SUPER_TOP_ID}>span,#${SUPER_BOTTOM_ID}>span{display:block;width:100%;height:2px;border-radius:999px;background:currentColor;opacity:.22;pointer-events:none;transition:height 120ms ease,opacity 120ms ease}`,
    `#${HANDLE_ID}:hover>span,#${HANDLE_ID}[data-dragging="true"]>span,#${SUPER_TOP_ID}:hover>span,#${SUPER_BOTTOM_ID}:hover>span{height:3px;opacity:.45}`,
    // Свёрнутое поле чаще возвращают кликом, поэтому курсор там не «тянуть», а
    // обычная рука, и сама полоска заметнее. Тяга вверх при этом тоже работает.
    `#${HANDLE_ID}[data-collapsed="true"]{cursor:pointer}`,
    `#${HANDLE_ID}[data-collapsed="true"]>span{height:3px;opacity:.30}`,
    `#${HANDLE_ID}[data-collapsed="true"]:hover>span{height:4px;opacity:.45}`,
    // Рейка ширины правой колонки (WF65, раздел 2г): прозрачная, при наведении и
    // тяге — акцентом (color ставит placeSideRail), как рейка боковой панели у
    // Claude.
    // Зона захвата 8 точек невидима; на наведении и тяге в её середине
    // проявляется линия в 3 точки — как рейка боковой панели у самого Claude
    // (слово Элвиса 17.09 02:00: «чтобы везде одинаково»).
    `#${SIDE_RAIL_ID}{position:fixed;display:none;width:${SIDE_RAIL_WIDTH}px;padding:0;border:0;background:transparent;cursor:col-resize;user-select:none;-webkit-user-select:none;touch-action:none;z-index:2147483646}`,
    // Линия проявляется не сразу, а после паузы — курсор и так каждую минуту
    // пересекает промежуток по дороге к полю ввода, и мгновенная линия «мигает,
    // бесит» (слово Элвиса 17.09 03:20); гаснет сразу. Яркость — вполсилы.
    // WF176 (#9182): пилюля как у рейки левой панели Claude — 3×48 по центру, цвет
    // text-muted (ставит placeSideRail замером пилюли Claude), появление 200 мс через 200 мс.
    `#${SIDE_RAIL_ID}{color:rgba(127,127,127,.75)}`,
    `#${SIDE_RAIL_ID}>span{position:absolute;left:50%;top:50%;width:3px;height:100%;max-height:${SIDE_RAIL_PILL}px;transform:translate(-50%,-50%);border-radius:999px;background:currentColor;opacity:0;pointer-events:none;transition:opacity 200ms cubic-bezier(.4,0,.2,1)}`,
    `#${SIDE_RAIL_ID}:hover>span{opacity:1;transition-delay:${SIDE_RAIL_REVEAL_MS}ms}`,
    `#${SIDE_RAIL_ID}[data-dragging="true"]>span{opacity:1;transition-delay:0ms}`,
    // Угловой фейд ленты в режиме чтения (раздел 6). Не в ноль и без резкой кромки
    // (слово Элвиса 20.09 06:30: «чтобы чуть-чуть просвечивал, ненавязчивый»; первая
    // редакция съедала две строки и гасила текст целиком).
    `[data-myclaude-corner-fade]{-webkit-mask-image:${CORNER_FADE_MASK};mask-image:${CORNER_FADE_MASK}}`,
    // Зеркальный фейд под кружком в режиме чтения (#6737, раздел 6). Отдельным
    // правилом с ДВУМЯ приметами, а не вторым слоем в правиле выше: слои маски
    // по умолчанию складываются (mask-composite:add), и там, где левый верхний
    // прозрачен, правый нижний непрозрачен — левый фейд #6656/#6658 пропал бы
    // совсем. Здесь слоёв два и composite intersect, а без кружка правило не
    // применяется вовсе и верхний фейд остаётся ровно таким, как был.
    `[data-myclaude-corner-fade][${RING_FADE_ATTRIBUTE}]{-webkit-mask-image:${CORNER_FADE_MASK},${RING_FADE_MASK};-webkit-mask-composite:source-in;mask-image:${CORNER_FADE_MASK},${RING_FADE_MASK};mask-composite:intersect}`,
    // Панель лимитов (раздел 12ж). Процент 5-часового прячем СВОИМ атрибутом:
    // узел остаётся на месте, React о нём не спотыкается. Своя полоса недели —
    // отрезки в ряд и подписи дней под ними; всё остальное (высота, цвет,
    // скругление) снято классами с родных полос, здесь этих чисел нет.
    // Прозрачность у каждой подписи своя, а не у ряда: opacity на родителе
    // создаёт группу, и сегодняшний день из неё уже не «ярче».
    `[data-myclaude-lim-hide]{display:none !important}`,
    // Дорожки полос видны на ЛЮБОЙ теме (#7064, слово Элвиса 22.09: «на розовой не видно
    // полосок, а важно, чтобы их было видно»). Цвет дорожки у Claude свой, и светлые темы
    // Пимпа красят фон панели почти в него — полоса пропадала целиком. Берём не фиксированный
    // серый (он потерялся бы на тёмных), а 14 % ТЕКУЩЕГО ЦВЕТА ТЕКСТА: на светлой теме текст
    // тёмный и дорожка тёмная, на тёмной — наоборот. Одно правило на все темы разом, проверять
    // каждую не нужно. Заливка внутри — своя, её не трогаем.
    `[data-myclaude-lim-panel] [role="progressbar"],[data-myclaude-lim-panel] [role="meter"],[data-myclaude-week="cell"]{background-color:color-mix(in srgb,currentColor 14%,transparent) !important;background-image:none !important}`,
    `[data-myclaude-week="bar"]{display:flex;gap:1px;align-items:stretch;margin-bottom:3px}`,
    `[data-myclaude-week="bar"]>*{flex:1 1 0;min-width:0}`,
    `[data-myclaude-week="days"]{display:flex;gap:1px;font-size:10px;line-height:1.5}`,
    `[data-myclaude-week="days"]>*{flex:1 1 0;min-width:0;text-align:center;opacity:.5}`,
    `[data-myclaude-week="days"]>[data-myclaude-week-on="true"]{opacity:1;font-weight:600}`,
    // Левая панель Claude ýже его минимума (раздел 2д) — только пристыкованная. У свёрнутой
    // этой же переменной Claude меряет выезжающий список и полосу над ним с переключателем
    // Claude/Code у правого края: при 190 вместо 242 переключатель вставал между «назад» и
    // «вперёд» (WF155, #9146: «когда подменюшку показываю, кнопки друг на друга накладываются»).
    `.dframe-root[${LEFT_ATTRIBUTE}]:not([data-collapsed]){--df-sidebar-width:var(${LEFT_VARIABLE}) !important}`,
    // Переключатель Claude/Code как кнопки окна (WF166, #9164; плашки WF155 сняты — «не надо под
    // ними делать эти фоны тёмные»): без дорожки и бегунка, кнопки 24 и иконка 16 в px — в обоих
    // режимах одного размера; невыбранная — цвет кнопок окна, выбранная и наведение — чуть ярче
    // их и тонкая подложка (WF182; было белым на --df-hover). Жирность иконки одна: Claude утолщает выбранный Code.
    `${MODE_SWITCH_SELECTOR}{--cds-segmented-control-track:transparent;height:${MODE_BUTTON}px !important;padding:0 !important;gap:0 !important;background:transparent !important;border:0 !important;box-shadow:none !important;-webkit-backdrop-filter:none !important;backdrop-filter:none !important}`,
    `${MODE_SWITCH_SELECTOR}>[aria-hidden="true"]{display:none !important}`,
    `${MODE_SWITCH_SELECTOR} [role="radio"]{width:${MODE_BUTTON}px !important;height:${MODE_BUTTON}px !important;min-width:0 !important;aspect-ratio:1 !important;padding:0 !important;border-radius:${MODE_RADIUS}px !important;background:transparent !important;color:var(--cds-text-secondary) !important}`,
    `${MODE_SWITCH_SELECTOR} [role="radio"]:is([data-checked],:hover){background:${MODE_ACTIVE_FILL} !important;color:${MODE_ACTIVE_TINT} !important}`,
    `${MODE_SWITCH_SELECTOR} [data-cds="Icon"]{font-size:${MODE_ICON}px !important;font-weight:533.3 !important}`,
    `${MODE_SWITCH_SELECTOR} svg{width:${MODE_ICON}px !important;height:${MODE_ICON}px !important}`,
    // #11618: те же правила для русского «Режим».
    `${MODE_SWITCH_RU}{--cds-segmented-control-track:transparent;height:${MODE_BUTTON}px !important;padding:0 !important;gap:0 !important;background:transparent !important;border:0 !important;box-shadow:none !important;-webkit-backdrop-filter:none !important;backdrop-filter:none !important}`,
    `${MODE_SWITCH_RU}>[aria-hidden="true"]{display:none !important}`,
    `${MODE_SWITCH_RU} [role="radio"]{width:${MODE_BUTTON}px !important;height:${MODE_BUTTON}px !important;min-width:0 !important;aspect-ratio:1 !important;padding:0 !important;border-radius:${MODE_RADIUS}px !important;background:transparent !important;color:var(--cds-text-secondary) !important}`,
    `${MODE_SWITCH_RU} [role="radio"]:is([data-checked],:hover){background:${MODE_ACTIVE_FILL} !important;color:${MODE_ACTIVE_TINT} !important}`,
    `${MODE_SWITCH_RU} [data-cds="Icon"]{font-size:${MODE_ICON}px !important;font-weight:533.3 !important}`,
    `${MODE_SWITCH_RU} svg{width:${MODE_ICON}px !important;height:${MODE_ICON}px !important}`,
    // Значок Remote Control у названия чата (WF166, #9164, снимок 18): включённый Claude красит
    // тёмной заливкой и цветом акцента — у нас просто значок цвета текста; наведение — как у Claude.
    `.epitaxy-titlebar [data-testid="epitaxy-origin-gutter"]{color:var(--cds-text-primary) !important}`,
    `.epitaxy-titlebar [data-testid="epitaxy-origin-gutter"] [data-cds-part="paint"]{background-color:transparent !important}`,
    `.epitaxy-titlebar [data-testid="epitaxy-origin-gutter"]:hover [data-cds-part="paint"]{background-color:var(--cds-fill-ghost-hover) !important}`,
    // Кнопка «Show sidebar» у светофора (слово Элвиса 22.10.2026: «просвечивает — раньше вокруг неё была
    // рамочка»): в 3.1623 она прозрачная поверх ленты — подложка цветом страницы и тонкая рамка. Подложка —
    // псевдоэлементом: фон самой кнопки перебивает правило прозрачности живого фона.
    `.df-collapsed-chrome ${uiAria(["Show sidebar", "Показать боковую панель"])}{box-shadow:0 0 0 1px var(--cds-border) !important;border-radius:8px !important}`,
    `.df-collapsed-chrome ${uiAria(["Show sidebar", "Показать боковую панель"])}::before{content:"";position:absolute;inset:0;z-index:-1;border-radius:8px;background:var(--cds-page-bg,#131518)}`,
    // Часики угла (#9144): пять минут и меньше — мягкий пульс раз в секунду; «Уменьшить движение» — без него.
    `#${CORNER_ID}>[${CORNER_CLOCK_ATTRIBUTE}="alarm"]{animation:myclaude-clock-tick 1s ease-in-out infinite}`,
    `@keyframes myclaude-clock-tick{0%,100%{opacity:1}50%{opacity:.45}}`,
    `@media (prefers-reduced-motion: reduce){#${CORNER_ID}>[${CORNER_CLOCK_ATTRIBUTE}]{animation:none !important}}`,
    // Выезжающий список чатов (#7097, 2.2553.13, скрин Элвиса к задаче): у свёрнутой
    // левой панели Claude по наведению выдвигает её поверх ленты и поля ввода —
    // `.dframe-root[data-collapsed][data-hovering] .dframe-sidebar-body {opacity:1}`.
    // Фон у панели непрозрачный (замер WF82: rgb(23,23,26) при любой нашей теме),
    // а «просвечивали» сквозь неё НАШИ полоски: ручка, полоса прогресса, дубль у
    // нижнего края. Они живут в body над всем деревом Claude (его корень —
    // `isolation: isolate`), и z-index их под панель не спрячет. Пока панель
    // выдвинута — прячем их одним правилом, без замеров и таймеров: наведение и
    // уход мыши Claude отмечает атрибутом, и правило срабатывает тем же кадром.
    // visibility, а не display: display полосок ведёт раскладка (раздел 9), и
    // после ухода мыши они встают на место сами; спрятанные мышь не ловят.
    // С WF277 — и место панели материалов (12п⁴): подложка, рейка и полоса над ней. Кнопка «PMP» остаётся, как
    // «Show sidebar» рядом с ней: список выезжает от него же, и спрятанную кнопку было бы не нажать.
    `body:has(.dframe-root[data-collapsed][data-hovering]) :is(#${HANDLE_ID},#${SUPER_TOP_ID},#${SUPER_BOTTOM_ID},#${PROGRESS_ID},#${PROGRESS_TIP_ID},#${SIDE_RAIL_ID},#${MIC_ID},#${GALLERY_ID},#${PMP_ID},#${DOCK_PLACE_ID},#${DOCK_RAIL_ID},#${DOCK_DRAG_ID},#${PMP_PANEL_ID}){visibility:hidden !important}`,
    // Наши слои уступают меню Claude (WF144, класс WF136 п.5–6): пока открыто меню или список,
    // ручка, дубли полосы, микрофон, галерея и PMP мышь не ловят — сразу, тем же кадром, а не
    // на проходе раскладки (он не чаще LAYOUT_MIN_GAP): нажатие по пункту над ними не
    // сворачивает поле и не закрывает меню.
    // С WF179 — и при открытом поповере/диалоге Claude (CLAUDE_POPUP_SELECTOR).
    `body:has(${CLAUDE_POPUP_SELECTOR}) :is(#${HANDLE_ID},#${SUPER_TOP_ID},#${SUPER_BOTTOM_ID},#${MIC_ID},#${GALLERY_ID},#${PMP_ID},#${SIDE_RAIL_ID},#${DOCK_BUTTON_ID},#${DOCK_SIZES_ID},#${DOCK_RAIL_ID}),body:has(${CLAUDE_POPUP_SELECTOR}) :is(#${HANDLE_ID},#${SUPER_TOP_ID},#${SUPER_BOTTOM_ID},#${MIC_ID},#${GALLERY_ID},#${PMP_ID},#${SIDE_RAIL_ID},#${DOCK_BUTTON_ID},#${DOCK_SIZES_ID},#${DOCK_RAIL_ID}) *{pointer-events:none !important}`,
    // Папка проекта перед именем закреплённого чата (раздел 2е, #7102). С page-64 (слово Элвиса 11.10
    // 01:40: «названия проектов не надо цветом выводить… сделай маленькими… не мешались») — не плашка,
    // а мелкая тихая подпись: без заливки и цвета проекта, 10 px, приглушённый тон текста темы. На
    // узкой панели (#6625) не шире половины строки и режется многоточием, а имя чата уходит под родной
    // градиент Claude. По высоте — на базовой линии имени чата: у inline-block с overflow базовая линия —
    // нижний край поля, поэтому строка высотой в кегль и нижнее поле −0,12 em (выносные под линией; сверено снимком стенда ×4).
    `[data-testid="sidebar-pinned"] .dframe-fade-label[${PINNED_FOLDER_ATTRIBUTE}]::before{content:attr(${PINNED_FOLDER_ATTRIBUTE});display:inline-block;vertical-align:baseline;box-sizing:border-box;max-width:50%;margin:0 6px -.12em 0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:10px;line-height:1;font-weight:400;color:var(--cds-text-secondary);opacity:.72}`,
    // Кнопка «💬 Новый чат» под блоком передачи (раздел 12к, #7246):
    // подпись — из атрибута, в innerText ответа её нет.
    `[${CONTINUE_ATTRIBUTE}]{display:flex;margin:6px 0 4px}`,
    `[${CONTINUE_ATTRIBUTE}]>button{display:inline-flex;align-items:center;padding:4px 10px;border:1px solid color-mix(in srgb,currentColor 25%,transparent);border-radius:8px;background:color-mix(in srgb,currentColor 6%,transparent);color:inherit;font:inherit;font-size:13px;line-height:18px;cursor:pointer;-webkit-app-region:no-drag}`,
    `[${CONTINUE_ATTRIBUTE}]>button:hover{background:color-mix(in srgb,currentColor 12%,transparent)}`,
    `[${CONTINUE_ATTRIBUTE}]>button[aria-disabled="true"]{opacity:.6;cursor:default}`,
    `[${CONTINUE_ATTRIBUTE}]>button::after{content:attr(${CONTINUE_LABEL_ATTRIBUTE})}`,
    // Заголовок «ОТКРОЙ НОВЫЙ ЧАТ» — ссылка (WF88, К15): текст прежний,
    // пунктир цвета акцента, сплошной при наведении; ⏳/✓ — из ::after.
    `[${CONTINUE_LINK_ATTRIBUTE}]{cursor:pointer;color:var(--cds-text-accent,currentColor);text-decoration:underline dotted;text-underline-offset:3px}`,
    `[${CONTINUE_LINK_ATTRIBUTE}]:hover{text-decoration-style:solid}`,
    // Ждём Пимпа (#7865, макет 13 — выбор Элвиса 26.09 ~08:40: основа 1.1 «блик по буквам», вместо ⏳ —
    // крутящийся кружок из 1.5, кнопка наливается, как 1.7): по буквам ссылки бежит светлая полоса (копия
    // текста в ::before), в конце — кружок; «✓» — ровно.
    `@keyframes myclaude-shim{from{background-position:100% 0}to{background-position:0 0}}`,
    `@keyframes myclaude-spin{to{transform:rotate(360deg)}}`,
    `@keyframes myclaude-fill{from{background-size:0% 100%}to{background-size:88% 100%}}`,
    `[${CONTINUE_LINK_ATTRIBUTE}][${CONTINUE_LINK_STATE_ATTRIBUTE}]{position:relative}`,
    `[${CONTINUE_LINK_ATTRIBUTE}][${CONTINUE_LINK_STATE_ATTRIBUTE}="wait"]::before{content:attr(${CONTINUE_LINK_TEXT_ATTRIBUTE});position:absolute;left:0;top:0;right:0;pointer-events:none;background:linear-gradient(100deg,transparent 36%,rgba(255,255,255,.9) 50%,transparent 64%) 0 0/250% 100% no-repeat;-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent;color:transparent;animation:myclaude-shim 1.7s linear infinite}`,
    `[${CONTINUE_LINK_ATTRIBUTE}][${CONTINUE_LINK_STATE_ATTRIBUTE}="wait"]::after{content:"";display:inline-block;width:.6em;height:.6em;margin-left:.4em;border:.12em solid currentColor;border-right-color:transparent;border-radius:50%;vertical-align:.04em;animation:myclaude-spin .8s linear infinite}`,
    `[${CONTINUE_LINK_ATTRIBUTE}][${CONTINUE_LINK_STATE_ATTRIBUTE}="ack"]::after{content:" ✓"}`,
    // Кнопка: пока «⏳ Зову Пимпа…» — наливается акцентом до 88 % за 3 с, слева кружок, по буквам блик
    // (подпись без ⏳ — строка CONTINUE_LABEL_WAIT без первого слова); «✓» — налита целиком.
    `[${CONTINUE_ATTRIBUTE}]>button[${BUSY_ATTRIBUTE}]{opacity:1;background-image:linear-gradient(color-mix(in srgb,var(--cds-text-accent,#d97757) 30%,transparent),color-mix(in srgb,var(--cds-text-accent,#d97757) 30%,transparent));background-repeat:no-repeat;background-size:100% 100%}`,
    `[${CONTINUE_ATTRIBUTE}]>button[${BUSY_ATTRIBUTE}][${CONTINUE_LABEL_ATTRIBUTE}^="⏳"]{background-size:88% 100%;animation:myclaude-fill 3s cubic-bezier(.25,.7,.3,1) both}`,
    `[${CONTINUE_ATTRIBUTE}]>button[${BUSY_ATTRIBUTE}][${CONTINUE_LABEL_ATTRIBUTE}^="⏳"]::before{content:"";display:inline-block;width:.8em;height:.8em;margin-right:.45em;border:2px solid currentColor;border-right-color:transparent;border-radius:50%;animation:myclaude-spin .8s linear infinite}`,
    `[${CONTINUE_ATTRIBUTE}]>button[${BUSY_ATTRIBUTE}][${CONTINUE_LABEL_ATTRIBUTE}^="⏳"]::after{content:"${CONTINUE_WAIT_TEXT}";background:linear-gradient(100deg,currentColor 36%,color-mix(in srgb,currentColor 20%,#fff) 50%,currentColor 64%) 0 0/250% 100% no-repeat;-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent;animation:myclaude-shim 1.7s linear infinite}`,
    // Идёт работа (#7772, WF97): ссылка и кнопка в это время aria-disabled,
    // курсор обычный; ссылка — прежняя простая, с ⏳/✓ из ::after (#7852, WF98:
    // перелива у неё и у кнопки больше нет, кнопка приглушена правилом выше).
    // Буквы переливаются только в плашке «⏳ Уже открываю окно…» (раздел 12б);
    // «уменьшить движение» — и там без перелива, просто приглушённо.
    `[${BUSY_ATTRIBUTE}]:not(button):not([${CONTINUE_LINK_ATTRIBUTE}]){background:linear-gradient(100deg,var(--cds-text-accent,#d97757) 36%,#fff 50%,var(--cds-text-accent,#d97757) 64%) 0 0/250% 100% no-repeat;-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent;color:transparent;animation:myclaude-shim 1.7s linear infinite}`,
    `[${CONTINUE_LINK_ATTRIBUTE}][${BUSY_ATTRIBUTE}]{cursor:default}`,
    // Карточка файла, пока приложение не ответило на клик (WF107, К3, #7772):
    // по плитке бежит блик, в углу ⏳; ссылка в тексте переливается правилом выше.
    `button[${BUSY_ATTRIBUTE}="file"]{position:relative;cursor:progress}`,
    `button[${BUSY_ATTRIBUTE}="file"]::after{content:"⏳";position:absolute;inset:0;display:flex;align-items:flex-start;justify-content:flex-end;padding:4px 6px;font-size:13px;line-height:1;border-radius:inherit;pointer-events:none;background:linear-gradient(100deg,transparent 36%,rgba(255,255,255,.28) 50%,transparent 64%) 0 0/250% 100% no-repeat;animation:myclaude-shim 1.7s linear infinite}`,
    `@media (prefers-reduced-motion: reduce){button[${BUSY_ATTRIBUTE}="file"]::after{animation:none !important;background:none !important}}`,
    // «Просмотрено» у карточек файлов (раздел 12м³, WF239). Галочка — круглая кнопка 24×24 в правом верхнем углу
    // карточки (знак 18 — по высоте плашки типа файла, от краёв 8, как поля карточки): в покое едва видна, под
    // курсором на карточке — видна, под курсором на ней самой — подложка; цвет — текста карточки, значит темы.
    // На фото — на тёмном кружке белым: читается на любой картинке. Просмотренная карточка — серая: всё её
    // содержимое, кроме галочки, приглушено и обесцвечено, рамка и размеры те же (лента не сдвигается); под
    // курсором и с фокусом проявляется, чтобы её можно было прочитать. Пока файл открывается, в углу ⏳ — галочки нет.
    `button[${SEEN_ATTRIBUTE}]{position:relative}`,
    `[${SEEN_CHECK_ATTRIBUTE}]{position:absolute;top:5px;right:5px;z-index:1;box-sizing:border-box;width:24px;height:24px;margin:0;padding:3px;border:0;border-radius:50%;background:transparent;color:inherit;line-height:0;cursor:pointer;opacity:.3;transition:opacity .15s,background-color .15s;-webkit-app-region:no-drag;user-select:none;-webkit-user-select:none}`,
    `[${SEEN_CHECK_ATTRIBUTE}]>svg{display:block;width:18px;height:18px;pointer-events:none}`,
    `[${SEEN_CHECK_ATTRIBUTE}] [data-k="fill"],[${SEEN_CHECK_ATTRIBUTE}][aria-pressed="true"] [data-k="line"]{display:none}`,
    `[${SEEN_CHECK_ATTRIBUTE}][aria-pressed="true"] [data-k="fill"]{display:inline}`,
    `[${SEEN_CHECK_ATTRIBUTE}][aria-pressed="true"]{opacity:.62}`,
    `button[${SEEN_ATTRIBUTE}]:hover>[${SEEN_CHECK_ATTRIBUTE}],button[${SEEN_ATTRIBUTE}]:focus-visible>[${SEEN_CHECK_ATTRIBUTE}]{opacity:.8}`,
    `[${SEEN_CHECK_ATTRIBUTE}]:hover,[${SEEN_CHECK_ATTRIBUTE}]:focus-visible{opacity:1 !important;background:color-mix(in srgb,currentColor 14%,transparent)}`,
    `[${SEEN_CHECK_ATTRIBUTE}]:active{background:color-mix(in srgb,currentColor 24%,transparent)}`,
    `[${SEEN_CHECK_ATTRIBUTE}]:focus-visible{outline:2px solid rgba(245,158,11,.7);outline-offset:-1px}`,
    `button[${SEEN_ATTRIBUTE}]:has(img)>[${SEEN_CHECK_ATTRIBUTE}]{color:#fff;background:rgba(0,0,0,.42);opacity:.45}`,
    `button[${SEEN_ATTRIBUTE}]:has(img)>[${SEEN_CHECK_ATTRIBUTE}][aria-pressed="true"]{opacity:.85}`,
    `button[${SEEN_ATTRIBUTE}]:has(img)>[${SEEN_CHECK_ATTRIBUTE}]:is(:hover,:focus-visible){background:rgba(0,0,0,.62)}`,
    `button[${SEEN_ATTRIBUTE}="on"]>:not([${SEEN_CHECK_ATTRIBUTE}]){opacity:.5;filter:grayscale(1);transition:opacity .15s,filter .15s}`,
    `button[${SEEN_ATTRIBUTE}="on"]:is(:hover,:focus-visible)>:not([${SEEN_CHECK_ATTRIBUTE}]){opacity:.85;filter:grayscale(.35)}`,
    `button[${BUSY_ATTRIBUTE}="file"]>[${SEEN_CHECK_ATTRIBUTE}]{visibility:hidden}`,
    `@media (prefers-reduced-motion: reduce){[${SEEN_CHECK_ATTRIBUTE}],button[${SEEN_ATTRIBUTE}="on"]>*{transition:none !important}}`,
    `@media (prefers-reduced-motion: reduce){[${BUSY_ATTRIBUTE}]:not(button):not([${CONTINUE_LINK_ATTRIBUTE}]){animation:none !important;background-image:none !important;-webkit-text-fill-color:currentColor !important;color:inherit !important;opacity:.6}[${CONTINUE_LINK_ATTRIBUTE}]::before,[${CONTINUE_LINK_ATTRIBUTE}]::after,[${CONTINUE_ATTRIBUTE}]>button::before,[${CONTINUE_ATTRIBUTE}]>button::after,[${CONTINUE_ATTRIBUTE}]>button{animation:none !important}}`,
    // Схлопнутый узел: не display:none, а полоска нулевой высоты — редактор
    // остаётся живым, черновик и фокус переживают сворачивание.
    `[${BLOCK_ATTRIBUTE}="collapsed"]{height:0 !important;min-height:0 !important;max-height:0 !important;padding-top:0 !important;padding-bottom:0 !important;margin-top:0 !important;margin-bottom:0 !important;overflow:hidden !important;opacity:0 !important;pointer-events:none !important}`,
    // Ветка с кружком контекста (#6737, раздел 6): та же свёртка, но БЕЗ
    // opacity — она создаёт группу прозрачности, и никакой opacity:1 на
    // потомке кружок из неё уже не вытащит, — с overflow:visible (иначе
    // кружок срежет) и position:relative (чтобы absolute внутри считался от
    // неё, а не от неизвестно чего).
    `[${BLOCK_ATTRIBUTE}="collapsed-ring"]{height:0 !important;min-height:0 !important;max-height:0 !important;padding-top:0 !important;padding-bottom:0 !important;margin-top:0 !important;margin-bottom:0 !important;overflow:visible !important;position:relative !important;pointer-events:none !important}`,
    // Внутри пути к кружку остаётся только сам путь и кружок: модель, счётчики
    // и кнопка отправки уходят. Редактор и черновик не задеты — они в ДРУГОМ
    // ребёнке блока ввода и живут обычным collapsed (opacity:0, фокус цел).
    `[${RING_PATH_ATTRIBUTE}]>*:not([${RING_PATH_ATTRIBUTE}]):not([${RING_ATTRIBUTE}]){display:none !important}`,
    // Сам кружок: на своём месте справа внизу, видимый и нажимаемый. z-index
    // НИЖЕ ручки (2147483646) намеренно: иначе кружок перехватил бы клик по
    // полоске возврата, и вернуть поле стало бы нечем.
    // Свой микрофон у кружка (#6907) и глушилка родной подсказки на кружке
    // (#6906: «при наведении не надо показывать стандартную подсказку» —
    // вместо неё открывается сама панель лимитов).
    `#${MIC_ID}{position:fixed;display:none;align-items:center;justify-content:center;width:${MIC_SIZE}px;height:${MIC_SIZE}px;padding:0;border:0;background:transparent;cursor:pointer;opacity:.45;-webkit-app-region:no-drag;user-select:none;-webkit-user-select:none;touch-action:none;z-index:2147483645}`,
    `#${MIC_ID}:hover{opacity:.95}`,
    `#${MIC_ID}[data-live="true"]{opacity:1;color:#ef4444}`,
    // Диктатор пишет в это окно — значок ЯРКО мигает (#7704): красный с
    // ореолом, раз в секунду; «уменьшить движение» — горит без мигания.
    `@keyframes myclaude-mic-blink{0%{opacity:1}100%{opacity:.2}}`,
    `#${MIC_ID}[data-live="true"][data-mode="dictator"]{border-radius:50%;background:rgba(239,68,68,.18);filter:drop-shadow(0 0 4px rgba(239,68,68,.95));animation:myclaude-mic-blink .5s ease-in-out infinite alternate}`,
    // Место под значок у левого края нижней строки открытого поля (#7704).
    `${CHIN_SELECTOR}[${MIC_ROOM_ATTRIBUTE}]{padding-left:${MIC_ROOM_PAD}px !important}`,
    // Кнопка «▦ Галерея» (#7724, раздел 12п; макет docs/11.html, раздел 6): значок 2×2 без числа,
    // рамки и заливки (#9507 — число файлов только в подсказке); под курсором — плашка, как у соседней
    // PMP; нажата (фильтр этого чата) — плашка держится. Место под неё в нижней строке открытого поля
    // — полем справа у левой группы «+ Auto» (ширину ставит placeGallery).
    `#${GALLERY_ID}{position:fixed;display:none;align-items:center;justify-content:center;box-sizing:border-box;width:${GALLERY_WIDTH}px;height:${GALLERY_HEIGHT}px;padding:0;border:0;border-radius:4px;background:transparent;box-shadow:none;color:inherit;cursor:pointer;opacity:.75;-webkit-app-region:no-drag;user-select:none;-webkit-user-select:none;z-index:2147483645;transition:background-color .15s,opacity .2s}`,
    `#${GALLERY_ID}>svg{display:block;flex:none;width:${GALLERY_ICON}px;height:${GALLERY_ICON}px;pointer-events:none}`,
    `#${GALLERY_ID}:hover{opacity:1;background:rgba(127,127,127,.14)}`,
    `#${GALLERY_ID}:active{background:rgba(127,127,127,.24)}`,
    `#${GALLERY_ID}[data-fresh="true"],#${GALLERY_ID}[data-on="true"]{opacity:.9;color:inherit}`,
    `#${GALLERY_ID}[data-on="true"]{background:rgba(127,127,127,.2)}`,
    // В нижней строке поля (#9181: «квадратик сильно ярко») — цветом подписей строки (--k, как BY);
    // у кружка — как было. Значок в строке — тише подписей (WF183: «значок сильно яркий»).
    `#${GALLERY_ID}[data-spot="field"]{color:var(--k,inherit);opacity:1}`,
    `#${GALLERY_ID}[data-spot="field"]>svg{opacity:.7}`,
    `#${GALLERY_ID}[data-spot="field"]:hover>svg{opacity:1}`,
    `#${GALLERY_ID}[data-fresh="true"]::after{content:"";position:absolute;top:1px;right:0;width:4px;height:4px;border-radius:50%;background:rgba(245,158,11,.75);pointer-events:none}`,
    // В нижней строке поля точки «есть непросмотренные» нет (#9195: «светится сверху точка…»):
    // сколько не смотрел — в подсказке.
    `#${GALLERY_ID}[data-spot="field"][data-fresh="true"]::after{display:none}`,
    // Кнопка «PMP» (раздел 12п¹, #9136; #9507 — без чисел): тихая надпись «PMP» цветом текста окна,
    // без серой плашки и тени; под курсором и у открытой панели — плашка. Ждёт ответа — как есть,
    // приложение молчит — бледнее и контуром.
    `#${PMP_ID}{position:fixed;display:none;align-items:center;justify-content:center;box-sizing:border-box;width:${PMP_WIDTH}px;height:${PMP_HEIGHT}px;padding:0;border:0;background:transparent;box-shadow:none;color:inherit;cursor:pointer;opacity:1;-webkit-app-region:no-drag;user-select:none;-webkit-user-select:none;z-index:2147483645;transition:background-color .15s,opacity .2s}`,
    `#${PMP_ID}>.p{display:flex;align-items:center;height:100%;padding:0;border-radius:3px;background:transparent;color:inherit;font:600 10px/1 -apple-system,system-ui,sans-serif;letter-spacing:.2px;opacity:.7}`,
    // WF226 (снимок Элвиса 10.10): плашка под курсором и у открытой панели — по содержимому, с полями 5
    // слева и справа и высотой 20, как у соседних значков. Надпись с места не сходит: поле слева и
    // сверху взято наружу.
    `#${PMP_ID}[data-spot="field"]{width:fit-content !important;min-width:24px;height:20px;margin:-3px 0 0 -5px;padding:0 5px;justify-content:center}`,
    `#${PMP_ID}[data-spot="field"]{color:var(--k,inherit)}`,
    // В нижней строке поля надпись — цветом, гарнитурой и кеглем подписей строки (#9181: «все шрифты
    // разные»), строка 16, как у них (BP, O 5.5): базовая линия общая (#9195).
    `#${PMP_ID}[data-spot="field"]>.p{font:400 var(--rs,11px)/16px var(--rf,${RICK_FONT_FALLBACK});letter-spacing:0;opacity:1}`,
    `#${PMP_ID}:hover{background:rgba(127,127,127,.14);border-radius:4px}`,
    `#${PMP_ID}:hover>.p{opacity:1}`,
    `#${PMP_ID}:active{background:rgba(127,127,127,.24);border-radius:4px}`,
    `#${PMP_ID}[data-state="silent"]{opacity:.45}`,
    `#${PMP_ID}[data-state="silent"]>.p{padding:0 3px;box-shadow:inset 0 0 0 1px currentColor}`,
    `#${PMP_ID}[aria-expanded="true"]{background:rgba(127,127,127,.2);border-radius:4px}`,
    `#${PMP_ID}:focus-visible{outline:2px solid rgba(245,158,11,.7);outline-offset:2px;border-radius:4px}`,
    // Панель оркестрации на кнопке PMP (раздел 12п³, WF213; макет счётчика — docs/32.html, вариант 1.4).
    // Коробка — как у сводки проекта 12п²: фон и текст поля (--F, --T), обводка — текст 15 % (--L).
    // Тело прокручивается (полосы нет, низ затухает — data-more), команды под ним всегда на виду.
    // Одна колонка имён на оба блока (--nm). Жирное — заголовки блоков и шапка строки Workflow; имя
    // терминала — цветом проекта, смешанным с цветом текста (читается и на светлой теме); в блоке Workflow
    // цвета проектов нет (лист 48 · 1.2). Строка Workflow — одной строкой без переноса и многоточия
    // (лишнее прячет pmpFlowsLineFit), числа ярче имён; в раскрытом списке строки делит волосок, «упал» — красный (--R).
    // Плашка под строкой терминала — как тело свёртки 12ф: волосок 1,5 px под стрелкой строки, серая
    // подложка, выезжает сменой grid-template-rows. Строка длиннее двух строк режется, раскрытая — целиком.
    // WF226: команды из рамки не выпадают ни при какой высоте — сжимается тело (вес сжатия 9999 против 1),
    // а когда от него остались одни поля, команды прокручиваются сами (окно ниже их трёх строк).
    `#${PMP_PANEL_ID}{position:fixed;display:none;flex-direction:column;box-sizing:border-box;border-radius:12px;border:1px solid var(--L);background:var(--F);color:var(--T);box-shadow:var(--S);font:400 12px/16px -apple-system,system-ui,sans-serif;font-variant-numeric:tabular-nums;text-align:left;overflow-wrap:anywhere;z-index:2147483646;pointer-events:auto;-webkit-app-region:no-drag;user-select:none;-webkit-user-select:none}`,
    `#${PMP_PANEL_ID}>div{flex:1 9999 auto;min-height:0;overflow-y:auto;overscroll-behavior:contain;scrollbar-width:none;padding:11px 14px 8px}`,
    `#${PMP_PANEL_ID}>div[data-more="true"]{-webkit-mask-image:linear-gradient(#000 calc(100% - 22px),transparent);mask-image:linear-gradient(#000 calc(100% - 22px),transparent)}`,
    `#${PMP_PANEL_ID} section+section{margin-top:12px}`,
    `#${PMP_PANEL_ID} h3{margin:0 0 3px;padding:0;font:600 12px/16px -apple-system,system-ui,sans-serif;color:inherit}`,
    `#${PMP_PANEL_ID} h3>span{font-weight:400;opacity:.6}`,
    `#${PMP_PANEL_ID} p{margin:0;padding:0}`,
    `#${PMP_PANEL_ID} [data-k="note"]{opacity:.65}`,
    `#${PMP_PANEL_ID} [data-k="row"]{position:relative;display:flex;align-items:flex-start;gap:8px;box-sizing:border-box;width:100%;min-height:22px;margin:0;padding:3px 0;border:0;border-radius:6px;background:transparent;color:inherit;font:inherit;text-align:left}`,
    `#${PMP_PANEL_ID} [data-k="nm"]{flex:0 0 var(--nm,64px);min-width:0;overflow:hidden;white-space:nowrap;font-weight:500;color:color-mix(in srgb,var(--c,currentColor) 70%,var(--T))}`,
    // Узкая панель (окно от 280): текст строки терминала и «2/3 · 1 идёт» проекта Workflow — под именем:
    // в колонке справа от имени им тесно.
    `#${PMP_PANEL_ID}[data-narrow="true"] [data-k="row"]{flex-wrap:wrap;row-gap:1px}`,
    `#${PMP_PANEL_ID}[data-narrow="true"] :is([data-k="tx"],[data-k="fw"]){flex:0 0 100%}`,
    `#${PMP_PANEL_ID} button{cursor:pointer;-webkit-app-region:no-drag}`,
    `#${PMP_PANEL_ID} button:focus-visible{outline:2px solid rgba(245,158,11,.7);outline-offset:1px}`,
    `#${PMP_PANEL_ID} button[data-k="row"]::before{content:"▸";position:absolute;left:-11px;top:3px;font-size:10px;line-height:16px;opacity:.6}`,
    `#${PMP_PANEL_ID} button[data-k="row"][aria-expanded="true"]::before{content:"▾"}`,
    `#${PMP_PANEL_ID} button[data-k="row"]:hover{background:color-mix(in srgb,currentColor 8%,transparent);box-shadow:-12px 0 0 color-mix(in srgb,currentColor 8%,transparent),6px 0 0 color-mix(in srgb,currentColor 8%,transparent)}`,
    `#${PMP_PANEL_ID} button[data-k="row"][data-flat="true"]{cursor:default}`,
    `#${PMP_PANEL_ID} button[data-k="row"][data-flat="true"]::before{content:none}`,
    `#${PMP_PANEL_ID} button[data-k="row"][data-flat="true"]:hover{background:transparent;box-shadow:none}`,
    `#${PMP_PANEL_ID} [data-k="tx"]{flex:1 1 0;min-width:0;display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2;overflow:hidden;opacity:.85}`,
    `#${PMP_PANEL_ID} [aria-expanded="true"]>[data-k="tx"]{display:block;-webkit-line-clamp:unset}`,
    `#${PMP_PANEL_ID} button[data-k="line"]{position:relative;display:block;box-sizing:border-box;width:100%;min-height:22px;margin:0;padding:3px 0;border:0;border-radius:6px;background:transparent;color:inherit;font:inherit;text-align:left}`,
    `#${PMP_PANEL_ID} button[data-k="line"]::before{content:"▸";position:absolute;left:-11px;top:3px;font-size:10px;line-height:16px;opacity:.6}`,
    `#${PMP_PANEL_ID} button[data-k="line"][aria-expanded="true"]::before{content:"▾"}`,
    `#${PMP_PANEL_ID} button[data-k="line"]:hover{background:color-mix(in srgb,currentColor 8%,transparent);box-shadow:-12px 0 0 color-mix(in srgb,currentColor 8%,transparent),6px 0 0 color-mix(in srgb,currentColor 8%,transparent)}`,
    `#${PMP_PANEL_ID} [data-k="ln"]{display:block;overflow:hidden;white-space:nowrap;text-overflow:clip}`,
    `#${PMP_PANEL_ID} [data-k="hd"]{font-weight:600}`,
    `#${PMP_PANEL_ID} [data-k="it"]>span{opacity:.65}`,
    `#${PMP_PANEL_ID} [data-k="it"]>b,#${PMP_PANEL_ID} [data-k="more"]{font-weight:600}`,
    `#${PMP_PANEL_ID} [data-kind="flow"]{padding:5px 0}`,
    `#${PMP_PANEL_ID} [data-kind="flow"]+[data-kind="flow"]{border-top:1px solid color-mix(in srgb,currentColor 10%,transparent);border-radius:0}`,
    `#${PMP_PANEL_ID} [data-k="fw"]{flex:1 1 0;min-width:0}`,
    `#${PMP_PANEL_ID} [data-k="fc"]>b{font-weight:600}`,
    `#${PMP_PANEL_ID} [data-k="fc"]>span{opacity:.65}`,
    `#${PMP_PANEL_ID} [data-k="fc"]>[data-fail]{opacity:1;color:var(--R)}`,
    `#${PMP_PANEL_ID} [data-k="fa"]{opacity:.85}`,
    `#${PMP_PANEL_ID} [data-k="plate"]{display:grid;grid-template-rows:0fr;transition:grid-template-rows .18s ease}`,
    `#${PMP_PANEL_ID} [data-k="plate"][data-open="true"]{grid-template-rows:1fr}`,
    `#${PMP_PANEL_ID} [data-k="plate"]>div{min-height:0;overflow:hidden;margin-left:-8px}`,
    `#${PMP_PANEL_ID} [data-k="plate"]>div>div{margin:2px 0 5px;padding:6px 10px 7px 6.5px;border-left:1.5px solid color-mix(in srgb,currentColor 45%,transparent);border-radius:0 8px 8px 0;background:rgba(127,127,127,.12)}`,
    `#${PMP_PANEL_ID} [data-k="pf"]+[data-k="pf"],#${PMP_PANEL_ID} [data-k="bar"]+p,#${PMP_PANEL_ID} [data-k="pm"]+[data-k="pf"],#${PMP_PANEL_ID} [data-k="pm"]+[data-k="pw"],#${PMP_PANEL_ID} [data-k="pf"]+[data-k="pw"]{margin-top:7px}`,
    `#${PMP_PANEL_ID} [data-k="pm"]{font-size:11px;opacity:.65}`,
    `#${PMP_PANEL_ID} [data-k="bar"]{display:block;height:2px;margin-top:4px;border-radius:1px;text-decoration:none;background:linear-gradient(90deg,var(--Y) var(--p,0%),color-mix(in srgb,currentColor 17%,transparent) var(--p,0%))}`,
    `#${PMP_PANEL_ID} [data-k="pw"]>b{font-weight:500}`,
    `#${PMP_PANEL_ID} [data-k="pw"]>span{opacity:.85}`,
    `#${PMP_PANEL_ID}>nav{flex:0 1 auto;min-height:0;overflow-y:auto;overscroll-behavior:contain;scrollbar-width:none;display:flex;flex-wrap:wrap;gap:6px;padding:9px 14px 12px;border-top:1px solid color-mix(in srgb,currentColor 10%,transparent)}`,
    `#${PMP_PANEL_ID}>nav>button{box-sizing:border-box;min-height:24px;margin:0;padding:3px 10px;border:1px solid var(--L);border-radius:8px;background:transparent;color:inherit;font:400 12px/16px -apple-system,system-ui,sans-serif;white-space:nowrap}`,
    `#${PMP_PANEL_ID}>nav>button:hover{background:color-mix(in srgb,currentColor 10%,transparent)}`,
    `#${PMP_PANEL_ID}>nav>button:active{background:color-mix(in srgb,currentColor 18%,transparent)}`,
    // Главное действие одно — «Запустить Workflow»: залито; фразы Рику — контуром; «Настройки Пимпа»
    // (уводит из окна к панели у часов) — текстом у правого края.
    `#${PMP_PANEL_ID}>nav>button[data-act="settings"]{margin-left:auto;padding:3px 4px;border-color:transparent;opacity:.75}`,
    `#${PMP_PANEL_ID}>nav>button[data-act="settings"]:hover{opacity:1}`,
    `#${PMP_PANEL_ID}>nav>button[data-act="kickoff"]{border-color:transparent;background:color-mix(in srgb,currentColor 14%,transparent);font-weight:500}`,
    `#${PMP_PANEL_ID}>nav>button[data-act="kickoff"]:hover{background:color-mix(in srgb,currentColor 22%,transparent)}`,
    `@media (prefers-reduced-motion:reduce){#${PMP_PANEL_ID} [data-k="plate"]{transition:none}}`,
    // «+» у кнопки New в списке чатов (#9145, WF156): только значок, без серого кружка-заливки
    // Claude (`.df-new-circle`, rgb(44,44,42) по замеру 08.10) — и при наведении.
    `${NEW_PLUS_SELECTOR}{background:transparent!important;box-shadow:none!important}`,
    // Меню Claude раскрывается вверх поверх рамки поля — свои слои над полем уступают ему, иначе нажатие пункта
    // уходит в них (WF136). С WF179 (#9205, слово Элвиса 09.10 02:35: «смотри панель — всё просвечивает»): и
    // поповерам/диалогам Claude (панель лимитов над полем): панель оркестрации, полоска 2б, её подсказка,
    // карточка и хвост.
    `body:has(${CLAUDE_POPUP_SELECTOR}) :is(#${PMP_PANEL_ID},#${PROGRESS_ID},#${PROGRESS_TIP_ID},#${PROGRESS_CARD_ID},#${PROGRESS_TAIL_ID}){visibility:hidden!important}`,
    `${CHIN_SELECTOR} [${GALLERY_ROOM_ATTRIBUTE}]{margin-inline-end:var(${GALLERY_ROOM_VARIABLE},0px) !important;flex-shrink:0 !important}`,
    `#${MIC_HINT_ID}{position:fixed;display:none;max-width:calc(100vw - 16px);padding:5px 9px;border-radius:8px;background:rgba(24,24,27,.94);color:#fff;font:12px/16px -apple-system,system-ui,sans-serif;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;pointer-events:none;box-shadow:0 2px 10px rgba(0,0,0,.35);z-index:2147483646}`,
    // Заголовки «нужен Элвис» в финальном ответе мигают мягко (#7703, раздел
    // 12м): подсветка янтарём туда-обратно, цикл 1,4 с.
    `@keyframes myclaude-attn-blink{0%{background-color:rgba(245,158,11,0);box-shadow:0 0 0 0 rgba(245,158,11,0)}100%{background-color:rgba(245,158,11,.34);box-shadow:0 0 0 3px rgba(245,158,11,.34)}}`,
    `[${ATTN_ATTRIBUTE}]{border-radius:6px;animation:myclaude-attn-blink .7s ease-in-out infinite alternate}`,
    `@media (prefers-reduced-motion: reduce){#${MIC_ID}[data-live="true"][data-mode="dictator"],[${ATTN_ATTRIBUTE}]{animation:none !important}[${ATTN_ATTRIBUTE}]{background-color:rgba(245,158,11,.3)}}`,
    // Слова-действия «Скажи — и сделаю» (#7755, раздел 12р): фраза янтарём в
    // тон мигания 12м, выбранное — залито; отсчёт — пилюля с цифрой у заголовка.
    // Подчёркивания нет ни в каком состоянии (#9505, слово Элвиса 10.10 ~11:00: «жёлтые… такими же
    // жирненькими, но без подчёркивания… когда наводишь, понятно»): покой — цвет и жирность (фраза —
    // strong ответа), под курсором и при нажатии — подложка.
    `[${SAY_ATTRIBUTE}]{color:rgb(245,158,11) !important;text-decoration:none !important;cursor:pointer;border-radius:5px;padding:0 3px;margin:0 -3px;user-select:none;-webkit-user-select:none;transition:background-color .15s,color .15s}`,
    `[${SAY_ATTRIBUTE}]:hover{background-color:rgba(245,158,11,.18)}`,
    `[${SAY_ATTRIBUTE}]:active{background-color:rgba(245,158,11,.3)}`,
    `[${SAY_ATTRIBUTE}="on"]{background-color:rgb(245,158,11) !important;color:#1c1917 !important}`,
    `[${SAY_LEFT_ATTRIBUTE}]::after{content:attr(${SAY_LEFT_ATTRIBUTE});display:inline-block;vertical-align:middle;margin-left:10px;min-width:24px;height:24px;padding:0 6px;box-sizing:border-box;border-radius:12px;background:rgb(245,158,11);color:#1c1917;font:700 14px/24px ui-monospace,SFMono-Regular,Menlo,monospace;text-align:center;cursor:pointer;box-shadow:0 0 0 3px rgba(245,158,11,.3)}`,
    // Нажималки (#7843, #7842, раздел 12с): строка «⚪» нажимается — без подчёркивания (то же слово
    // #9505; до того — пунктир янтарём во всю строку): под курсором и при нажатии — подложка тем же
    // янтарём, вписанная — залита; кнопки — как «💬 Новый чат» 12к, подпись
    // из атрибута (в innerText, копию и «Обкэшить» не попадает), нажатая —
    // залита; занятая — приглушена, без перелива (#7852).
    `li[${NAZH_PICK_ATTRIBUTE}]{cursor:pointer;border-radius:5px;text-decoration:none !important;user-select:none;-webkit-user-select:none;transition:background-color .15s}`,
    `li[${NAZH_PICK_ATTRIBUTE}]:hover{background-color:rgba(245,158,11,.14)}`,
    `li[${NAZH_PICK_ATTRIBUTE}]:active{background-color:rgba(245,158,11,.22)}`,
    `li[${NAZH_PICK_ATTRIBUTE}="on"]{background-color:rgba(245,158,11,.3)}`,
    `[${NAZH_BOX_ATTRIBUTE}]{display:flex;flex-wrap:wrap;gap:6px;margin:4px 0 8px}`,
    `[${NAZH_BUTTON_ATTRIBUTE}]{display:inline-flex;align-items:center;padding:2px 9px;border:1px solid rgba(245,158,11,.55);border-radius:8px;background:rgba(245,158,11,.08);color:inherit;font:inherit;font-size:12px;line-height:18px;cursor:pointer;user-select:none;-webkit-user-select:none;-webkit-app-region:no-drag;vertical-align:middle}`,
    `[${NAZH_BUTTON_ATTRIBUTE}]:hover{background:rgba(245,158,11,.2)}`,
    `[${NAZH_BUTTON_ATTRIBUTE}]::after{content:attr(${NAZH_LABEL_ATTRIBUTE})}`,
    `[${NAZH_BUTTON_ATTRIBUTE}][${NAZH_ON_ATTRIBUTE}]{background:rgb(245,158,11);border-color:rgb(245,158,11);color:#1c1917}`,
    `[${NAZH_BUTTON_ATTRIBUTE}][aria-disabled="true"]{opacity:.6;cursor:default}`,
    `li>[${NAZH_BUTTON_ATTRIBUTE}],p>[${NAZH_BUTTON_ATTRIBUTE}]{margin-left:8px;padding:0 7px;font-size:11px}`,
    // «→ в чат» у блока кода (#7980, раздел 12с): в полосе «Copy code» — по центру, в одну строку.
    `[${NAZH_BUTTON_ATTRIBUTE}="code"]{align-self:center;white-space:nowrap}`,
    // Свёртки <details> (#9065, раздел 12ф): заголовок — строка с ▸/▾, подпись
    // из атрибута (копия и выделение её не видят).
    `[${FOLD_RAW_ATTRIBUTE}],[${FOLD_BODY_ATTRIBUTE}="closed"],[${FOLD_LONG_ATTRIBUTE}="closed"]{display:none !important}`,
    `[${FOLD_HEAD_ATTRIBUTE}]{display:block;width:fit-content;max-width:100%;margin:6px 0;padding:2px 8px 2px 4px;border-radius:6px;color:inherit;font-weight:600;cursor:pointer;user-select:none;-webkit-user-select:none;-webkit-app-region:no-drag;transition:background-color .15s,opacity .15s}`,
    `[${FOLD_HEAD_ATTRIBUTE}]::after{content:attr(${FOLD_LABEL_ATTRIBUTE})}`,
    `[${FOLD_HEAD_ATTRIBUTE}]:hover{background:rgba(127,127,127,.14)}`,
    `[${FOLD_HEAD_ATTRIBUTE}]:focus-visible{outline:2px solid rgba(245,158,11,.7);outline-offset:1px}`,
    `[${FOLD_HEAD_ATTRIBUTE}]:active{background:rgba(127,127,127,.24)}`,
    `[${FOLD_HEAD_ATTRIBUTE}="open"]:not([${FOLD_WHOLE_ATTRIBUTE}]){margin-bottom:2px}`,
    // WF218 (#9426, слово Элвиса 10.10: «„Свернуть ответ“… мизерная, я её не вижу вообще… должно быть
    // лучше сделано, заметнее»): кнопка — плашка размером текста ответа, со стрелкой как у свёрток
    // (стрелка на той же вертикали: поле слева 8 px, сдвиг −4 px); у свёрнутого ответа — строка во
    // всю ширину с полоской слева, под первым абзацем.
    `[${FOLD_WHOLE_ATTRIBUTE}]{margin:8px 0 8px -4px;padding:4px 12px 4px 8px;border-radius:8px;background:rgba(127,127,127,.12)}`,
    `[${FOLD_WHOLE_ATTRIBUTE}="closed"]{width:auto;margin-left:calc(var(--myclaude-fold-mid, 7.4px) - .75px);padding-left:calc(10.75px - var(--myclaude-fold-mid, 7.4px) + 4px);border-left:1.5px solid currentColor;border-radius:0 8px 8px 0}`,
    `[${FOLD_WHOLE_ATTRIBUTE}]:hover{background:rgba(127,127,127,.2)}`,
    `[${FOLD_WHOLE_ATTRIBUTE}]:active{background:rgba(127,127,127,.3)}`,
    // WF173 (слово Элвиса 09.10 02:00 по снимку ответа Рика: «зачем эта фиолетовая линия… тоненькую,
    // цветом как эти надписи… кругляшки не нужны… отступ сильно большой… абзацы поближе, между
    // абзацами расстояние чуть побольше… сливается»). Только ответы Claude, реплики человека — нет.
    // Цитата: волосок 1,5 px цветом своего текста (не акцент темы), отступ 10 px.
    `${ANSWER_PROSE} blockquote{border-left:1.5px solid currentColor !important;padding-left:10px !important;margin-left:0 !important;margin-inline-start:0 !important}`,
    // WF176 (#9198): цитата — тело свёртки: волосок под центром ▾ заголовка (замер —
    // --myclaude-fold-mid, раздел 12ф), содержимое сдвигается вместе с ним.
    // WF182: волосок 1,5 px у тела свёртки в любом виде ленты (не только в прозе Code) — иначе
    // чужая ширина рамки сдвигала бы центр линии с центра ▾.
    `${ANSWER_PROSE} blockquote[${FOLD_BODY_ATTRIBUTE}],blockquote[${FOLD_BODY_ATTRIBUTE}]{margin-left:calc(var(--myclaude-fold-mid, 7.4px) - .75px) !important;margin-inline-start:calc(var(--myclaude-fold-mid, 7.4px) - .75px) !important;border-left-width:1.5px !important}`,
    // Строки абзаца плотнее, сами абзацы, списки и цитаты — врозь.
    `${ANSWER_PROSE} :is(p,li,blockquote){line-height:1.45 !important}`,
    `${ANSWER_PROSE} * + :is(p,ul,ol,blockquote){margin-top:.8em !important}`,
    `${ANSWER_PROSE} li + li{margin-top:.5em !important}`,
    // Маркеры списков тише: цветом второстепенного текста и мельче.
    `${ANSWER_PROSE} li::marker{color:var(--cds-text-secondary,currentColor);font-size:.8em}`,
    // В свёртке кругляшков нет вовсе и отступа под них — тоже: структуру держат интервалы.
    `${ANSWER_PROSE} :is(ul[${FOLD_BODY_ATTRIBUTE}],[${FOLD_BODY_ATTRIBUTE}] ul){list-style:none !important;padding-inline-start:0 !important;margin-inline-start:0 !important}`,
    // WF218 (#9426, слово Элвиса 10.10: «Почему оно полоской не отделяется, что свёрнуто?.. когда мы
    // workflow делаем, там же специальная полоска и отступ, а здесь-то почему этого нет»): волосок под ▾
    // и отступ 10 px были только у тела-цитаты (отчёты Workflow, WF176) — теперь у любого тела свёртки:
    // абзаца, списка, кода. У нумерованного списка поле под цифры своё; у блока со своим фоном (код)
    // линия прямая, фон начинается после отступа. Стоит после правила списков — при равном весе побеждает.
    foldStripRule(`${FOLD_STRIP}:not(blockquote,table)`, `margin-left:${FOLD_STRIP_LEFT} !important;margin-inline-start:${FOLD_STRIP_LEFT} !important;border-left:1.5px solid currentColor !important;border-top-left-radius:0 !important;border-bottom-left-radius:0 !important;background-clip:content-box !important`),
    // WF225: под кнопкой «Свернуть ответ» списки остаются списками — маркеры и цифры в своём поле
    // (в теле <details> кругляшков нет — правило WF173 выше); разделитель — своим правилом ниже.
    foldStripRule(`${FOLD_STRIP}:not(blockquote,ol,hr,table,ul:not([${FOLD_BODY_ATTRIBUTE}]))`, "padding-left:10px !important;padding-inline-start:10px !important"),
    // Полоска идёт вдоль всего раскрытого без разрывов: зазор между соседними узлами — их внутренним
    // полем (внешний отступ, верхний или нижний, рвал бы линию). WF225: у любого узла полосы и с обеих
    // сторон — заголовок h1–h3, код и таблица приходят со своими отступами.
    foldStripRule(FOLD_STRIP, "margin-top:0 !important;margin-bottom:0 !important;padding-top:.8em !important"),
    // #11478 (слово Элвиса 01.11: «заголовок… прижат к верхнему абзацу… а заголовок-то нижнего абзаца» — принцип
    // близости): первый узел тела под раскрытой головой (за её сырыми <p>) — почти вплотную к ней, последний перед
    // следующей головой или </details> — с полем снизу; полоса идёт сквозь поля.
    foldStripRule(`:is([${FOLD_HEAD_ATTRIBUTE}="open"]+[${FOLD_RAW_ATTRIBUTE}],[${FOLD_HEAD_ATTRIBUTE}="open"]+[${FOLD_RAW_ATTRIBUTE}]+[${FOLD_RAW_ATTRIBUTE}])+${FOLD_STRIP}:not(hr,table)`, "padding-top:.2em !important"),
    foldStripRule(`${FOLD_STRIP}:not(hr,table):has(+:is([${FOLD_RAW_ATTRIBUTE}],[${FOLD_HEAD_ATTRIBUTE}]))`, "padding-bottom:.8em !important"),
    // Разделитель: высота вместо внешних отступов (полоса не рвётся), сама черта — тихой линией после отступа.
    foldStripRule(`hr${FOLD_STRIP}`, "box-sizing:border-box !important;height:1.6em !important;padding:0 !important;border-width:0 0 0 1.5px !important;color:inherit !important;overflow:visible !important;background:linear-gradient(color-mix(in srgb,currentColor 25%,transparent),color-mix(in srgb,currentColor 25%,transparent)) no-repeat 10px 50%/calc(100% - 10px) 1px !important"),
    // Таблица без обёртки: поле у неё не работает (границы ячеек слиты) — отступ внешний, а линию
    // на всю высоту вместе с зазором сверху ведёт свой слой.
    foldStripRule(`table${FOLD_STRIP}`, `position:relative !important;margin-left:calc(${FOLD_STRIP_LEFT} + 11.5px) !important;margin-inline-start:calc(${FOLD_STRIP_LEFT} + 11.5px) !important;margin-top:.8em !important;padding-top:0 !important`),
    foldStripRule(`table${FOLD_STRIP}::before`, `content:"";position:absolute;left:-11.5px;top:calc(-.8em - 1px);bottom:-1px;border-left:1.5px solid currentColor;pointer-events:none`),
    // Свой заголовок свёртки внутри раскрытой (вложенная <details>; любая — под кнопкой «Свернуть
    // ответ»): место и стрелка те же, полоса внешней идёт сквозь его строку по вертикали ▾ и
    // расступается только вокруг самой стрелки — одна линия сверху донизу, без двойной и без сдвига.
    // Вложенная своей полосы правее не получает: узкому окну второй отступ дороже, чем граница
    // внутренней группы.
    `${FOLD_STRIP_HEAD}{position:relative}`,
    `${FOLD_STRIP_HEAD}::before{content:"";position:absolute;left:${FOLD_STRIP_LEFT};top:-6px;bottom:-6px;border-left:1.5px solid currentColor;pointer-events:none;-webkit-mask-image:linear-gradient(#000 calc(8px + .5lh - .5em),transparent calc(8px + .5lh - .5em) calc(8px + .5lh + .5em),#000 calc(8px + .5lh + .5em));mask-image:linear-gradient(#000 calc(8px + .5lh - .5em),transparent calc(8px + .5lh - .5em) calc(8px + .5lh + .5em),#000 calc(8px + .5lh + .5em))}`,
    `${FOLD_STRIP_HEAD}[${FOLD_HEAD_ATTRIBUTE}="open"]::before{bottom:-2px}`,
    // Раскрытая кнопка «Свернуть ответ»: полоса начинается сразу под ней, как под заголовком свёртки.
    `[${FOLD_WHOLE_ATTRIBUTE}="open"]{margin-bottom:2px}`,
    // «Прочитано» (#9377, раздел 12х; слово Элвиса 10.10: «слева нажимать… на зону… сереньким»,
    // «большими блоками… заметные, но всё же свёрнутые»). Дорожка — свой узел в строке ленты, слева
    // от текста; место и ширину даёт замер поля строки (переменные на корне). Текст ответа не сдвигается.
    // У самой дорожки не видно ничего ни в каком состоянии — ни волоска, ни края, ни подложки-полосы
    // (слово Элвиса 10.10 10:20 и 10:47: полоса слева — визуальный шум). Курсор на дорожке или фокус с
    // клавиатуры — тихой подложкой светится ВЕСЬ блок ответа: все его строки ленты, от дорожки до
    // правого края текста (#9506, слово Элвиса 10.10 ~11:00: «когда я на край навожу… должно
    // выделяться»), с задержкой, не сразу (#9649: «фоном со скруглёнными краешками… только с
    // задержкой») — уход гасит сразу. Подложка — слой дорожки цветом текста окна (светлая тема —
    // темнее фона, тёмная — светлее), без линии, скруглена у первой и последней строки; нажатий не
    // ловит — под ней текст как был.
    `[${READ_ZONE_ATTRIBUTE}]{position:absolute;top:0;bottom:0;left:var(${READ_LEFT_VARIABLE},2px);width:var(${READ_WIDTH_VARIABLE},20px);z-index:1;outline:none;cursor:pointer;user-select:none;-webkit-user-select:none;-webkit-app-region:no-drag}`,
    `[${READ_ZONE_ATTRIBUTE}]::before{content:"";position:absolute;top:0;bottom:0;left:0;width:var(${READ_SPAN_VARIABLE},100%);background:color-mix(in srgb,currentColor 8%,transparent);opacity:0;pointer-events:none;transition:opacity .15s}`,
    `[${READ_ZONE_ATTRIBUTE}][${READ_EDGE_ATTRIBUTE}~="top"]::before{border-top-left-radius:8px;border-top-right-radius:8px}`,
    `[${READ_ZONE_ATTRIBUTE}][${READ_EDGE_ATTRIBUTE}~="bottom"]::before{border-bottom-left-radius:8px;border-bottom-right-radius:8px}`,
    `[${READ_ZONE_ATTRIBUTE}]::after{content:"✓";position:sticky;top:8px;display:block;margin-right:4px;border-radius:4px;text-align:center;font-size:11px;line-height:16px;opacity:0;pointer-events:none;transition:opacity .15s}`,
    `[${READ_ZONE_ATTRIBUTE}][${READ_HOT_ATTRIBUTE}]::before{opacity:1;transition:opacity .2s ease .3s}`,
    `[${READ_ZONE_ATTRIBUTE}]:hover::after{opacity:.75}`,
    // Фокус с клавиатуры: блок подсвечен так же (метку ставит onReadHover), кольцо — у галочки, не вдоль дорожки.
    `[${READ_ZONE_ATTRIBUTE}]:focus-visible::after{opacity:.75;outline:2px solid rgba(245,158,11,.7);outline-offset:-1px}`,
    // Помечено: галочка у первой дорожки ответа (она же стоит в порядке Tab), линии нет.
    `[${READ_ZONE_ATTRIBUTE}="on"][tabindex="0"]::after{opacity:.75}`,
    // Поле слева от текста уже дорожки (узкое окно, «Поля» 5): галочке рядом с текстом места нет —
    // она только у свёрнутого блока; раскрытый ответ под курсором показывает подложка блока.
    `html[${READ_TIGHT_ATTRIBUTE}] [${READ_ZONE_ATTRIBUTE}]::after{margin-right:2px;font-size:10px}`,
    `html[${READ_TIGHT_ATTRIBUTE}] :not([${READ_ROW_ATTRIBUTE}="head"],[${READ_ROW_ATTRIBUTE}="bare"])>[${READ_ZONE_ATTRIBUTE}]::after{opacity:0 !important}`,
    // Ответ ещё пишется — пометить нельзя: дорожка молчит.
    `[${READ_ZONE_ATTRIBUTE}][aria-disabled="true"]{cursor:default}`,
    `[${READ_ZONE_ATTRIBUTE}][aria-disabled="true"]::before{opacity:0 !important}`,
    `[${READ_ZONE_ATTRIBUTE}][aria-disabled="true"]::after{opacity:0 !important}`,
    // После перехода по «непрочитанные N» блок ответа коротко горит янтарём — той же подложкой.
    `@keyframes myclaude-read-hit{0%,40%{opacity:1;background-color:rgba(245,158,11,.16)}100%{opacity:0;background-color:rgba(245,158,11,0)}}`,
    `[${READ_ZONE_ATTRIBUTE}][${READ_HIT_ATTRIBUTE}]::before{animation:myclaude-read-hit 1.4s ease-out}`,
    // Свёрнутый прочитанный ответ. Узлы на местах, вид — высота 0 и прозрачность, НЕ display: innerText
    // такие строки отдаёт по-прежнему (полоса 2б, «Обкэшить», «ждут твоего слова», «Скажи — и сделаю»).
    `[${READ_ROW_ATTRIBUTE}="rest"]{height:0 !important;min-height:0 !important;overflow:hidden !important;opacity:0 !important;pointer-events:none !important}`,
    // Блок — как свёрнутый ответ 12ф (WF218): полоска под ▾ свёрток, отступ 10 px, серая плашка; внутри —
    // первая строка ответа (затухает к правому краю) и тихая подпись. Своя полоска 12ф остаётся под срезом.
    `:is([${READ_ROW_ATTRIBUTE}="head"],[${READ_ROW_ATTRIBUTE}="bare"]) [data-cds="AssistantMessage"]{position:relative;box-sizing:border-box !important;width:auto !important;min-height:0 !important;margin-left:calc(var(--myclaude-fold-mid, 7.4px) - .75px) !important;padding:4px 86px 4px 10px !important;gap:0 !important;border-left:1.5px solid currentColor;border-radius:0 8px 8px 0;background:rgba(127,127,127,.12);overflow:hidden !important;transition:background-color .15s}`,
    `:is([${READ_ROW_ATTRIBUTE}="head"],[${READ_ROW_ATTRIBUTE}="bare"]) [data-cds="AssistantMessage"]::after{content:"прочитано";position:absolute;right:10px;top:0;bottom:0;display:flex;align-items:center;font-size:11px;line-height:1;opacity:.78;pointer-events:none}`,
    `[${READ_ROW_ATTRIBUTE}="bare"] [data-cds="AssistantMessage"]::before{content:"Ответ без текста";display:block;height:1.45em;padding-left:4px;overflow:hidden;opacity:.78}`,
    `:is([${READ_ROW_ATTRIBUTE}="head"],[${READ_ROW_ATTRIBUTE}="bare"]) [data-cds="AssistantMessage"] :not([${READ_LINE_ATTRIBUTE}],[${READ_LINE_ATTRIBUTE}] *,:has([${READ_LINE_ATTRIBUTE}])){height:0 !important;min-height:0 !important;margin:0 !important;padding:0 !important;border:0 !important;overflow:hidden !important;opacity:0 !important;pointer-events:none !important}`,
    `[${READ_ROW_ATTRIBUTE}="head"] [data-cds="AssistantMessage"] :has([${READ_LINE_ATTRIBUTE}]){gap:0 !important;margin-top:0 !important;margin-bottom:0 !important;padding-top:0 !important;padding-bottom:0 !important;min-height:0 !important}`,
    `[${READ_ROW_ATTRIBUTE}="head"] [${READ_LINE_ATTRIBUTE}]{height:1.45em !important;margin:0 !important;overflow:hidden !important;opacity:.78;-webkit-mask-image:linear-gradient(90deg,#000 calc(100% - 40px),transparent);mask-image:linear-gradient(90deg,#000 calc(100% - 40px),transparent)}`,
    `[${READ_ROW_ATTRIBUTE}="head"] [${READ_LINE_ATTRIBUTE}] *{white-space:nowrap !important}`,
    `[${READ_ROW_ATTRIBUTE}="head"] [${READ_LINE_ATTRIBUTE}] :is(h1,h2,h3,h4,h5,h6,[${FOLD_HEAD_ATTRIBUTE}]){margin:0 !important;padding-top:0 !important;padding-bottom:0 !important;border:0 !important;background:none !important;font-size:inherit !important}`,
    `[${READ_ROW_ATTRIBUTE}="head"] [${READ_LINE_ATTRIBUTE}]>:first-child,[${READ_ROW_ATTRIBUTE}="head"] [${READ_LINE_ATTRIBUTE}]>.contents>:first-child{margin-top:0 !important}`,
    // У свёрнутого блока галочка — на строке блока; курсор на дорожке подсвечивает его той же подложкой.
    `:is([${READ_ROW_ATTRIBUTE}="head"],[${READ_ROW_ATTRIBUTE}="bare"])>[${READ_ZONE_ATTRIBUTE}]::after{position:absolute;left:0;right:0;top:auto;bottom:6px}`,
    // Своя кнопка поверх блока: нажал — ответ раскрыт (пометка остаётся). Наведение, нажатие и фокус рисует плашка.
    `[${READ_OPEN_ATTRIBUTE}]{position:absolute;top:0;bottom:0;left:calc(var(${READ_LEFT_VARIABLE},2px) + var(${READ_WIDTH_VARIABLE},20px) + 2px);right:0;z-index:1;outline:none;cursor:pointer;-webkit-app-region:no-drag}`,
    `:is([${READ_ROW_ATTRIBUTE}="head"],[${READ_ROW_ATTRIBUTE}="bare"]):has(>[${READ_OPEN_ATTRIBUTE}]:hover) [data-cds="AssistantMessage"]{background:rgba(127,127,127,.2)}`,
    `:is([${READ_ROW_ATTRIBUTE}="head"],[${READ_ROW_ATTRIBUTE}="bare"]):has(>[${READ_OPEN_ATTRIBUTE}]:active) [data-cds="AssistantMessage"]{background:rgba(127,127,127,.3)}`,
    `:is([${READ_ROW_ATTRIBUTE}="head"],[${READ_ROW_ATTRIBUTE}="bare"]):has(>[${READ_OPEN_ATTRIBUTE}]:focus-visible) [data-cds="AssistantMessage"]{outline:2px solid rgba(245,158,11,.7);outline-offset:1px}`,
    // «непрочитанные N» — у правого края над полем ввода, на одной высоте со стрелкой «вниз» Claude
    // (в широком виде — слева от неё, правило в layoutCss). Подпись — из атрибута.
    `.group\\/approval-dock{--myclaude-read-pad-end:var(--chat-column-gutter-end,0px)}`,
    `#${READ_NEXT_ID}{position:absolute;right:var(--myclaude-read-pad-end,0px);bottom:calc(100% + 25px);z-index:1;display:flex;align-items:center;box-sizing:border-box;height:26px;padding:0 10px;border:1px solid var(--cds-border,rgba(127,127,127,.35));border-radius:13px;background:var(--cds-surface-3,rgba(127,127,127,.24));color:inherit;font-size:11px;line-height:1;font-variant-numeric:tabular-nums;white-space:nowrap;cursor:pointer;pointer-events:auto;user-select:none;-webkit-user-select:none;-webkit-app-region:no-drag;opacity:.8;transition:opacity .15s,border-color .15s}`,
    `#${READ_NEXT_ID}::after{content:attr(${READ_LABEL_ATTRIBUTE})}`,
    // Узкое окно: рядом со стрелкой «вниз» (она по середине) кнопке тесно — встаёт строкой выше.
    `@container tile-slot (max-width:399px){#${READ_NEXT_ID}{bottom:calc(100% + 64px)}}`,
    `@media (max-width:399px){#${READ_NEXT_ID}{bottom:calc(100% + 64px)}}`,
    `#${READ_NEXT_ID}:hover{opacity:1;border-color:currentColor}`,
    `#${READ_NEXT_ID}:active{opacity:.65}`,
    `#${READ_NEXT_ID}:focus-visible{opacity:1;outline:2px solid rgba(245,158,11,.7);outline-offset:1px}`,
    `@media (prefers-reduced-motion: reduce){[${READ_ZONE_ATTRIBUTE}]::before,[${READ_ZONE_ATTRIBUTE}]::after,#${READ_NEXT_ID}{transition:none !important}[${READ_ZONE_ATTRIBUTE}][${READ_HIT_ATTRIBUTE}]::before{animation:none;opacity:1;background-color:rgba(245,158,11,.16)}}`,
    // «Работа идёт» одной строкой (слово Элвиса 10.10 10:20, раздел 12х¹). Спрятанное серией — узлы на
    // местах, вид — высота 0 и прозрачность, НЕ display и не visibility: innerText ленты тот же (полоса
    // 2б, «Обкэшить», «ждут твоего слова», «Скажи — и сделаю»). Блок хода ещё и вне потока: пустые блоки
    // держали бы зазоры колонки; строка ленты — как свёрнутая строка «Прочитано».
    `[${WORK_ATTRIBUTE}="rest"]{position:absolute !important;height:0 !important;min-height:0 !important;margin:0 !important;padding:0 !important;border:0 !important;overflow:hidden !important;opacity:0 !important;pointer-events:none !important}`,
    `[${WORK_ATTRIBUTE}="row"]{height:0 !important;min-height:0 !important;overflow:hidden !important;opacity:0 !important;pointer-events:none !important}`,
    // Ответ-точка (раздел 12х³) — так же: строка ленты на месте, высота 0; ничего не удаляется.
    `[${DOT_ATTRIBUTE}="row"],[${DOT_ATTRIBUTE}="gap"]{height:0 !important;min-height:0 !important;overflow:hidden !important;opacity:0 !important;pointer-events:none !important}`,
    // Точка — последний блок хода: панель кнопок ответа (копия, ветка, глава, вслух, время) остаётся и
    // встаёт под текст выше с тем же зазором 6 px, что у обычного ответа; колонка текста — вне потока.
    `[${DOT_ATTRIBUTE}="text"]{position:absolute !important;height:0 !important;min-height:0 !important;margin:0 !important;padding:0 !important;border:0 !important;overflow:hidden !important;opacity:0 !important;pointer-events:none !important}`,
    `[${DOT_ATTRIBUTE}="tail"] [data-transcript-row]{margin-top:6px !important}`,
    // Строка-сводка — в системе свёрток 12ф: тот же знак ▸/▾ тем же весом, плашка под курсором, раскрытое
    // под полосой. Стрелка стоит на левой линии текста ответа (поле плашки вынесено влево). Подписи —
    // из атрибутов частей: текста в узле нет, копия и разбор ленты его не видят.
    `[${WORK_LINE_ATTRIBUTE}]{display:flex;align-items:center;gap:6px;box-sizing:border-box;width:fit-content;max-width:calc(100% + 4px);margin:0 0 0 -4px;padding:2px 6px 2px 4px;border-radius:6px;color:inherit;font-weight:400;white-space:nowrap;cursor:pointer;user-select:none;-webkit-user-select:none;-webkit-app-region:no-drag;transition:background-color .15s}`,
    `[${WORK_LINE_ATTRIBUTE}]:hover{background:rgba(127,127,127,.14)}`,
    `[${WORK_LINE_ATTRIBUTE}]:active{background:rgba(127,127,127,.24)}`,
    `[${WORK_LINE_ATTRIBUTE}]:focus-visible{outline:2px solid rgba(245,158,11,.7);outline-offset:1px}`,
    `[${WORK_PART_ATTRIBUTE}]{flex:none}`,
    `[${WORK_PART_ATTRIBUTE}]::after{content:attr(${WORK_TEXT_ATTRIBUTE})}`,
    `[${WORK_PART_ATTRIBUTE}="arrow"]{font-weight:600}`,
    // Тихое — счёт шагов и вся строка прошедшей серии; цветом — только неудача (её отделяет цвет, без точки).
    `[${WORK_PART_ATTRIBUTE}="steps"],[${WORK_LINE_ATTRIBUTE}="done"] [${WORK_PART_ATTRIBUTE}="label"]{color:var(--cds-text-secondary,currentColor)}`,
    // Тесно (узкое окно, крупный шрифт) — сжимается счёт шагов; подпись и неудача остаются целыми.
    `[${WORK_PART_ATTRIBUTE}="steps"]{flex:0 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;font-variant-numeric:tabular-nums}`,
    // Красный подмешан к цвету текста: на тёмной теме светлее, на светлой темнее — контраст с фоном от 4,5 : 1.
    `[${WORK_PART_ATTRIBUTE}="failed"]{color:color-mix(in srgb,#ef4444 65%,currentColor)}`,
    `[${WORK_PART_ATTRIBUTE}="failed"]:not([${WORK_TEXT_ATTRIBUTE}]){display:none}`,
    `@media (prefers-reduced-motion: reduce){[${WORK_LINE_ATTRIBUTE}]{transition:none}}`,
    // Одно и то же один раз (WF245): хвостовой абзац «Работа идёт» над свёрнутой серией — как хвосты К-CA;
    // так же — шаг первой строкой ответа (page-71), ответ под ним встаёт без своего верхнего отступа.
    `[${WORK_ATTRIBUTE}="head"]+*{margin-top:0 !important}`,
    `[${WORK_ATTRIBUTE}="echo"],[${WORK_ATTRIBUTE}="head"]{height:0 !important;min-height:0 !important;margin:0 !important;padding:0 !important;border:0 !important;overflow:hidden !important;opacity:0 !important;pointer-events:none !important}`,
    // Полоса хода (WF245): N секторов по 2 px высотой, k залиты акцентом темы, остальные — тоном текста.
    // Числа счёта — из атрибута «k/N» в переменные; сектора режет маска, заливка — один переход.
    Array.from({ length: WORK_BAR_MAX + 1 }, (_, k) => `[${WORK_BAR_ATTRIBUTE}^="${k}/"]{--myclaude-work-k:${k}}${k ? `[${WORK_BAR_ATTRIBUTE}$="/${k}"]{--myclaude-work-n:${k}}` : ""}`).join(""),
    `[${WORK_PART_ATTRIBUTE}="bar"],p[${WORK_BAR_ATTRIBUTE}]::after{content:"";box-sizing:border-box;height:2px;border-radius:1px;background:linear-gradient(90deg,${WORK_BAR_FILL} calc((var(--myclaude-work-k) - var(--myclaude-work-live,0)) * ${WORK_BAR_STEP}),${WORK_BAR_TONE} 0);-webkit-mask:linear-gradient(90deg,#000 calc(100% - ${WORK_BAR_GAP}px),transparent 0) 0 0/${WORK_BAR_STEP} 100% repeat-x}`,
    `[${WORK_PART_ATTRIBUTE}="bar"]{position:relative;flex:0 1 auto;width:${WORK_BAR_WIDTH};min-width:0}`,
    `[${WORK_PART_ATTRIBUTE}="bar"]:not([${WORK_BAR_ATTRIBUTE}]){display:none}`,
    // Тесно — сжимается полоса (до нуля), счёт «k из N» остаётся целым.
    `[${WORK_PART_ATTRIBUTE}="bar"][${WORK_BAR_ATTRIBUTE}]~[${WORK_PART_ATTRIBUTE}="steps"]{flex:none}`,
    // Идущая серия: последний залитый сектор мягко дышит (свой слой поверх полосы); «Уменьшить движение» — стоит.
    `@keyframes myclaude-work-breath{from{opacity:1}to{opacity:.35}}`,
    `[${WORK_LINE_ATTRIBUTE}="live"] [${WORK_PART_ATTRIBUTE}="bar"]{--myclaude-work-live:1}`,
    `[${WORK_LINE_ATTRIBUTE}="live"] [${WORK_PART_ATTRIBUTE}="bar"]::before{content:"";position:absolute;top:0;bottom:0;left:calc((var(--myclaude-work-k) - 1) * ${WORK_BAR_STEP});width:calc(${WORK_BAR_STEP} - ${WORK_BAR_GAP}px);background:${WORK_BAR_FILL};animation:myclaude-work-breath 1.4s ease-in-out infinite alternate}`,
    `[${WORK_LINE_ATTRIBUTE}="live"] [${WORK_PART_ATTRIBUTE}="bar"][${WORK_BAR_ATTRIBUTE}^="0/"]::before{display:none}`,
    `@media (prefers-reduced-motion: reduce){[${WORK_LINE_ATTRIBUTE}="live"] [${WORK_PART_ATTRIBUTE}="bar"]::before{animation:none}}`,
    // Одиночная строка шага: абзац Claude на месте, его текст увезён за край (innerText тот же), на виду —
    // подпись без счёта и полоса; в узком окне полоса сжимается, строка не переносится.
    `p[${WORK_BAR_ATTRIBUTE}]{display:grid !important;grid-template:auto/max-content 0 minmax(0,${WORK_BAR_WIDTH});grid-auto-rows:0;align-items:center;white-space:nowrap !important;overflow:hidden !important;text-indent:-9999px}`,
    `p[${WORK_BAR_ATTRIBUTE}]::before{content:attr(${WORK_TEXT_ATTRIBUTE});grid-area:1/1;margin-right:8px;text-indent:0}`,
    `p[${WORK_BAR_ATTRIBUTE}]::after{grid-area:1/3}`,
    // Раскрытая серия — под полосой, как раскрытые свёртки (WF225): линия под стрелкой строки, отступ
    // 10 px; линия идёт сквозь зазоры между блоками и строками ленты, у первого блока — от его верха.
    `[${WORK_ATTRIBUTE}^="open"]{position:relative !important;box-sizing:border-box !important;padding-left:calc(${WORK_STRIP_LEFT} + 11.5px) !important}`,
    `[${WORK_ATTRIBUTE}^="open"]::before{content:"";position:absolute;left:${WORK_STRIP_LEFT};top:-16px;bottom:0;border-left:1.5px solid currentColor;pointer-events:none}`,
    `[${WORK_ATTRIBUTE}="open-first"]::before{top:-2px}`,
    // Карточки файлов в ленте (#9181, «восемь артефактов… ужасно выглядит»): у Claude каждая —
    // квадрат 120×120 с именем, размером и плашкой «HTML». Здесь — плашка в одну строку
    // «имя · размер», ряд плашек переносится; ссылка карточки та же — клик как у Claude.
    `${FEED_FILE_TILE}{width:auto !important;height:auto !important;min-width:0 !important;max-width:min(100%,240px) !important}`,
    `${FEED_FILE_TILE}>*{width:auto !important;height:auto !important;padding:3px 9px !important}`,
    `${FEED_FILE_TILE} .justify-between,${FEED_FILE_TILE} .justify-between>.flex-col{flex-direction:row !important;align-items:baseline !important;gap:6px !important}`,
    `${FEED_FILE_TILE} .justify-between>.flex-col .flex-col{flex-direction:row !important;gap:0 !important}`,
    `${FEED_FILE_TILE} .justify-between>:not(:first-child){display:none !important}`,
    `${FEED_FILE_TILE} .line-clamp-2{-webkit-line-clamp:1 !important;line-clamp:1 !important;font-size:12px !important}`,
    `${FEED_FILE_TILE} .text-caption{font-size:11px !important;flex-shrink:0}`,
    // Плитка .HEIC с пришедшей миниатюрой (раздел 12м⁴): вместо плашки с именем — фото высотой 120,
    // как плитки фото Claude; имя — в подсказке картинки. Миниатюры нет — плашка как была.
    `${FEED_FILE_TILE}[${HEIC_ATTRIBUTE}="on"]{padding:0 !important;overflow:hidden !important;cursor:pointer !important}`,
    `${FEED_FILE_TILE}[${HEIC_ATTRIBUTE}="on"]>:not([${HEIC_IMG_ATTRIBUTE}]){display:none !important}`,
    `${FEED_FILE_TILE}[${HEIC_ATTRIBUTE}="on"]>[${HEIC_IMG_ATTRIBUTE}]{display:block !important;width:auto !important;height:120px !important;max-width:100% !important;padding:0 !important;object-fit:cover;border-radius:inherit}`,
    // HTML и PDF (#10229) — карточка как в галерее: снимок верха страницы 260×170 над плашкой Claude (имя, размер);
    // снимок прозрачен для мыши — нажатие, правый клик и галочка «просмотрено» у плашки как были.
    // Карточка SendUserFile (#10383): миниатюра поверх плитки, нажатие проходит в карточку.
    `[${HEIC_ATTRIBUTE}^="card"]{position:relative !important;overflow:hidden !important}`,
    `[${HEIC_ATTRIBUTE}^="card"]>[${HEIC_IMG_ATTRIBUTE}]{position:absolute !important;inset:0;display:block !important;width:100% !important;height:100% !important;padding:0 !important;object-fit:cover;border-radius:inherit;pointer-events:none}`,
    `[${HEIC_ATTRIBUTE}="card-doc"]>[${HEIC_IMG_ATTRIBUTE}]{object-position:top}`,
    // #10603 (слово Элвиса 22.10: «превьюшки сделать HTML… как в PimpViewer… и джипы, и хейки, картинки вот так вот
    // отображать»): плашка SendUserFile (h-9 max-w-60) — карточка: превью 180 сверху (HTML и PDF — 240 в ширину, верх
    // страницы; фото — по пропорции 160…320), под ним та же плашка; превью прозрачно для мыши — нажатие, меню и
    // галочка у плашки как были. Квадраты Claude (вызов с картинкой) — высотой 180 по пропорции.
    `[${HEIC_ATTRIBUTE}^="plate"]{position:relative !important;width:var(${HEIC_WIDTH_VAR},240px) !important;max-width:100% !important;height:216px !important;padding-top:180px !important;border:1px solid rgba(255,255,255,.12) !important;border-radius:12px !important;overflow:hidden !important}`,
    `[${HEIC_ATTRIBUTE}^="plate"]>[${HEIC_IMG_ATTRIBUTE}]{position:absolute !important;top:0;left:0;display:block !important;width:100% !important;height:180px !important;max-width:none !important;margin:0 !important;padding:0 !important;object-fit:cover;object-position:top;border-bottom:1px solid rgba(255,255,255,.08);pointer-events:none}`,
    `[${HEIC_ATTRIBUTE}="plate-photo"]>[${HEIC_IMG_ATTRIBUTE}]{object-position:center}`,
    // Квадрат 120 самой карточки (вызов с картинкой): HTML и PDF — 240 в ширину, снимок 180 сверху, значок типа под
    // ним не нужен, имя и размер Claude — внизу.
    `[${HEIC_ATTRIBUTE}="square-doc"]{position:relative !important;width:240px !important;max-width:100% !important;height:auto !important;min-height:120px !important;padding-top:188px !important;justify-content:flex-end !important;border-radius:12px !important}`,
    `[${HEIC_ATTRIBUTE}="square-doc"]>[${HEIC_IMG_ATTRIBUTE}]{position:absolute !important;top:0;left:0;display:block !important;width:100% !important;height:180px !important;margin:0 !important;padding:0 !important;object-fit:cover;object-position:top;border-bottom:1px solid rgba(255,255,255,.08);pointer-events:none}`,
    `[${HEIC_ATTRIBUTE}="square-doc"]>div:first-child{display:none !important}`,
    // Чат Рика: карточку без нажатия Claude приглушает (opacity-70) — у Пимпа она нажимается (#10531), снимок — в полный цвет.
    `.opacity-70[${HEIC_ATTRIBUTE}]{opacity:1 !important}`,
    `:is(div,span):has(>:is([${HEIC_ATTRIBUTE}^="plate"],[${HEIC_ATTRIBUTE}="square-doc"],button[${HEIC_GROW_ATTRIBUTE}])){flex-wrap:wrap !important;align-items:flex-end !important}`,
    `button[${HEIC_GROW_ATTRIBUTE}]{width:var(${HEIC_WIDTH_VAR},120px) !important;max-width:100% !important;height:180px !important;max-height:none !important}`,
    `button[${HEIC_GROW_ATTRIBUTE}] [${HEIC_BOX_ATTRIBUTE}]{width:100% !important;height:100% !important;max-width:none !important;max-height:none !important}`,
    `button[${HEIC_GROW_ATTRIBUTE}] img:not([${HEIC_IMG_ATTRIBUTE}]){width:100% !important;height:100% !important;object-fit:cover !important}`,
    `${FEED_FILE_TILE}[${HEIC_ATTRIBUTE}="doc"]{position:relative !important;width:260px !important;max-width:min(100%,260px) !important;padding-top:170px !important;overflow:hidden !important}`,
    `${FEED_FILE_TILE}[${HEIC_ATTRIBUTE}="doc"]>[${HEIC_IMG_ATTRIBUTE}]{position:absolute !important;top:0;left:0;display:block !important;width:100% !important;height:170px !important;padding:0 !important;object-fit:cover;object-position:top;pointer-events:none}`,
    // Файл в поле ввода (#10345, снимок Элвиса 19.10: плитка 40 pt, а в ней путь крупным шрифтом
    // столбиком и вылезает за край): имя — мелко, одной строкой, обрезано. Пришла миниатюра (12м⁴) —
    // снимок во всю плитку под крестиком «Remove», текст спрятан.
    `[data-cds-composer-attachments] [data-cds="MessageAttachmentsFile"] :is(p,span,div):not(:has(button)):not(button *){min-width:0 !important;max-width:100% !important;overflow:hidden !important;white-space:nowrap !important;text-overflow:ellipsis !important;font-size:9px !important;line-height:12px !important}`,
    `[${HEIC_ATTRIBUTE}^="field"]{position:relative !important;isolation:isolate !important;padding:0 !important}`,
    `[${HEIC_ATTRIBUTE}^="field"] :is(p,span,div):not(:has(button)):not(button *):not([${HEIC_IMG_ATTRIBUTE}]){visibility:hidden !important}`,
    `[${HEIC_ATTRIBUTE}^="field"]>[${HEIC_IMG_ATTRIBUTE}]{position:absolute !important;inset:0;z-index:-1;display:block !important;width:100% !important;height:100% !important;padding:0 !important;object-fit:cover;border-radius:inherit;pointer-events:none}`,
    `[${HEIC_ATTRIBUTE}="field-doc"]>[${HEIC_IMG_ATTRIBUTE}]{object-position:top}`,
    // Bypass во всех чатах (#9060, раздел 12с¹): меню режимов, пока его открыла страница.
    `html[${BYPASS_QUIET_ATTRIBUTE}] :is([role="menu"],[role="listbox"]){opacity:0 !important;pointer-events:none !important}`,
    // Прятать инструменты (#7976, раздел 3а): законченная группа и список «Edited N
    // files» в строках ленты; где есть чем решать — видно (:has браузер сверяет вживую).
    // Группа внутри раскрытой серии «Работа идёт» (12х¹) видна: серию раскрывают, чтобы посмотреть шаги.
    `html[${HIDE_TOOLS_ATTRIBUTE}] ${HIDE_TOOLS_GROUP}[${HIDE_TOOLS_MARK}]:not([${WORK_ATTRIBUTE}^="open"]):not(:has(${HIDE_TOOLS_GROUP_DECISION},${HIDE_TOOLS_GROUP_UNSAFE})),html[${HIDE_TOOLS_ATTRIBUTE}] ${HIDE_TOOLS_FILES}[${HIDE_TOOLS_MARK}]:not(:has(${HIDE_TOOLS_DECISION},${HIDE_TOOLS_UNSAFE_BUTTON})){display:none !important}`,
    // Законченная строка фоновых команд — так же; внутри раскрытой серии «Работа идёт» видна.
    `html[${HIDE_TOOLS_ATTRIBUTE}] ${HIDE_TOOLS_TASKS}[${HIDE_TOOLS_MARK}]:not([${WORK_ATTRIBUTE}^="open"]){display:none !important}`,
    // Полоски глав Claude (nav «Session chapters») — ниже кнопок окна: при убранной боковой панели они
    // вставали под красную, жёлтую и зелёную (слово Элвиса 11.10 01:40, снимок 6).
    `.epitaxy-toc{top:48px !important}`,
    // Главы чата (раздел 12х², слово Элвиса 11.10 01:40: «чтоб главы были на таком же расстоянии, как
    // тексты… чтобы они не расширялись… все серенькие, но которая текущая — жирненькая. И когда навожу —
    // открывай подменю с названиями, оно так выезжает. И пусть весь интерфейс плавно затемнится»).
    // Дорожка: шаг полосок — шаг строк меню, поэтому названия выезжают РЯДОМ с полосками, а сами
    // полоски стоят на месте: дорожка лежит поверх меню, свои полоски строк меню спрятаны. Шаг,
    // толщина и яркость — переменные (настройка правой кнопкой); текущая — толще на 1 px и ярче на 30 пунктов
    // (#9758: было на 65 — «текущая глава сильно всё ещё яркая»), прочитанная зелёная — не ярче 60 %.
    // #10764 (скрин №3: полоски лежали на первых буквах текста — «должны быть левее… крупнее»): у Claude дорожка
    // с отступом 3/16 колонки, полоска 3/8 (короткие — 9/14 от неё, по центру), начало текста — около 9–10 px правее
    // края дорожки. Отступ снят, дорожка сдвинута на 4 px влево: полоска той же длины кончается до текста; крупнее —
    // толщиной и яркостью (CH_LOOK). Длиннее нельзя: длина растёт вправо, на текст.
    `${CH_RAIL}{position:relative;z-index:1;padding-block:6px !important;padding-inline-start:0 !important;translate:-4px 0;scrollbar-width:none}`,
    `${CH_RAIL}>li{flex:none;height:${CH_STEP} !important}`,
    `${CH_RAIL}>li>span{height:${CH_THICK} !important;width:calc(var(--chat-gutter,32px)*3/8) !important;background-color:var(--cds-text-primary,currentColor) !important;opacity:${CH_INK};transition:scale .2s,opacity .2s,height .2s,background-color .2s !important}`,
    `${CH_RAIL}>li>span[class~="bg-alpha-8"]{height:calc(${CH_THICK} + 1px) !important;opacity:min(1,calc(${CH_INK} + .3))}`,
    `${CH_RAIL}>li[${CH_READ_ATTRIBUTE}]>span{background-color:${CH_OK} !important;opacity:max(.6,${CH_INK})}`,
    // Меню показывает только страница (метка на nav): у Claude оно вылетает сразу и поверх полосок —
    // здесь с задержкой, выезжает слева; закрытое мышь не ловит. Пока открыто — дорожка пропускает
    // нажатия к строкам под ней.
    `${CH_MENU}{left:0 !important;top:0 !important;max-width:calc(100vw - 16px);padding-block:6px !important;translate:0 0 !important;transition:opacity .16s ease-out,transform .16s ease-out,visibility 0s linear .16s !important}`,
    `${CH_NAV_SELECTOR}:not([${CH_OPEN_ATTRIBUTE}])>div{visibility:hidden !important;opacity:0 !important;transform:translateX(-10px) !important;pointer-events:none !important}`,
    `${CH_NAV_SELECTOR}[${CH_OPEN_ATTRIBUTE}]>div{visibility:visible !important;opacity:1 !important;transform:none !important;pointer-events:auto !important;transition-delay:0s !important}`,
    `${CH_NAV_SELECTOR}[${CH_OPEN_ATTRIBUTE}]>ol[aria-hidden="true"]{pointer-events:none !important}`,
    `${CH_MENU}>ol{gap:0 !important;padding-inline:0 !important;scrollbar-width:none}`,
    // Панель шире, названия целиком (page-71, слово Элвиса 11.10 07:27: «многоточия-то эти не нужны… чтобы они
    // пошире, вот эта панель была… чтобы заголовки видел»): ширина — по самому длинному названию, не шире 560 и
    // окна; длиннее — перенос, строка растёт, а её полоска дорожки встаёт против неё (chAlign).
    `${CH_MENU}{width:max-content !important;min-width:min(240px,calc(var(${CH_ROOM_VARIABLE},100vw) - 16px)) !important;max-width:min(560px,calc(var(${CH_ROOM_VARIABLE},100vw) - 16px)) !important}`,
    `${CH_MENU}>ol>li{position:relative;flex:none;height:auto !important;min-height:${CH_STEP}}`,
    // Строка (тот же день: «галочки… справа… до них далеко тянуться. Давай галочки поставим вот: минус, потом
    // галочка… ну и название»): полоска дорожки, галочка, звёздочка (#9758), название. Название начинается правее
    // звёздочки (отступ дорожки 3/16 колонки + полоска 3/8 + 2, галочка 26, звёздочка 24, зазор 4); кегль не больше
    // 13 и не выше строки.
    `${CH_MENU}>ol>li>button:not([${CH_CHECK_ATTRIBUTE}],[${CH_STAR_ATTRIBUTE}]){height:auto !important;min-height:${CH_STEP} !important;gap:0 !important;padding-block:0 !important;padding-inline:calc(var(--chat-gutter,32px)*9/16 + 58px) 12px !important;text-align:left !important}`,
    `${CH_MENU}>ol>li>button>span[aria-hidden="true"]{display:none !important}`,
    `${CH_MENU}>ol>li>button>span:not([aria-hidden]){display:block !important;white-space:normal !important;overflow:visible !important;text-overflow:clip !important;overflow-wrap:anywhere;-webkit-line-clamp:unset !important;font-size:clamp(10px,calc(${CH_STEP} - 6px),13px) !important;line-height:min(18px,${CH_STEP}) !important}`,
    // Галочка «прочитано» — настоящая кнопка сразу за полоской: контур круга с галочкой, отмеченная — залита зелёным.
    `[${CH_CHECK_ATTRIBUTE}]{position:absolute;top:0;left:calc(var(--chat-gutter,32px)*9/16 + 6px);display:flex;align-items:center;justify-content:center;box-sizing:border-box;width:26px;height:100%;margin:0;padding:0;border:0;border-radius:5px;background:transparent;color:var(--cds-text-secondary,currentColor);opacity:.5;cursor:pointer;-webkit-app-region:no-drag;transition:opacity .15s,color .15s}`,
    `[${CH_CHECK_ATTRIBUTE}]>svg{display:block;width:min(15px,calc(${CH_STEP} - 4px));height:min(15px,calc(${CH_STEP} - 4px));pointer-events:none}`,
    `[${CH_CHECK_ATTRIBUTE}]>svg>[data-k="fill"],[${CH_CHECK_ATTRIBUTE}][aria-pressed="true"]>svg>[data-k="line"]{display:none}`,
    `[${CH_CHECK_ATTRIBUTE}][aria-pressed="true"]>svg>[data-k="fill"]{display:inline}`,
    `[${CH_CHECK_ATTRIBUTE}][aria-pressed="true"]{color:${CH_OK};opacity:1}`,
    `[${CH_CHECK_ATTRIBUTE}]:is(:hover,:focus-visible){opacity:1}`,
    `[${CH_CHECK_ATTRIBUTE}]:active{opacity:.65}`,
    `[${CH_CHECK_ATTRIBUTE}]:focus-visible{outline:2px solid rgba(245,158,11,.7);outline-offset:-2px}`,
    // Затемнение окна: свой узел размером с меню, тень от него — на всё окно. Сам узел прозрачен и мышь
    // не ловит: меню под ним светлое и рабочее, остальное притемнено и нажимается как обычно.
    `#${CH_DIM_ID}{position:fixed;left:0;top:0;width:0;height:0;box-sizing:border-box;border-radius:8px;background:transparent;box-shadow:0 0 0 200vmax rgba(0,0,0,.42);pointer-events:none;visibility:hidden;opacity:0;transition:opacity .2s ease-out,visibility 0s linear .2s;z-index:2147483647}`,
    `#${CH_DIM_ID}[data-on="true"]{visibility:visible;opacity:1;transition-delay:0s}`,
    // Панель настройки вида (правая кнопка по дорожке или меню) — в языке панели PMP: те же цвета
    // (--F, --T, --L, --S), скругление 12, текст 12/16; три строки «имя · ползунок · число» одной сеткой.
    `#${CH_SET_ID}{position:fixed;display:none;box-sizing:border-box;width:236px;max-width:calc(100vw - 16px);padding:10px 12px;border-radius:12px;border:1px solid var(--L);background:var(--F);color:var(--T);box-shadow:var(--S);font:400 12px/16px -apple-system,system-ui,sans-serif;font-variant-numeric:tabular-nums;text-align:left;z-index:2147483647;pointer-events:auto;-webkit-app-region:no-drag;user-select:none;-webkit-user-select:none}`,
    `#${CH_SET_ID} h3{margin:0 0 6px;padding:0;font:600 12px/16px -apple-system,system-ui,sans-serif;color:inherit}`,
    `#${CH_SET_ID} label{display:grid;grid-template-columns:76px minmax(0,1fr) 34px;align-items:center;column-gap:8px;height:24px;margin:0;padding:0;font:inherit;color:inherit}`,
    `#${CH_SET_ID} label>[data-k="num"]{text-align:right;opacity:.65;white-space:nowrap}`,
    `#${CH_SET_ID} input{box-sizing:border-box;width:100%;min-width:0;height:16px;margin:0;padding:0;accent-color:var(--T);cursor:pointer}`,
    `#${CH_SET_ID} input:focus-visible,#${CH_SET_ID} button:focus-visible{outline:2px solid rgba(245,158,11,.7);outline-offset:2px}`,
    `#${CH_SET_ID} [data-k="foot"]{display:flex;justify-content:flex-end;margin-top:6px}`,
    `#${CH_SET_ID} button{box-sizing:border-box;height:24px;margin:0;padding:0 10px;border:1px solid var(--L);border-radius:6px;background:transparent;color:inherit;font:inherit;font-size:11px;line-height:1;cursor:pointer;transition:background-color .15s,opacity .15s}`,
    `#${CH_SET_ID} button:hover{background:color-mix(in srgb,var(--T) 10%,transparent)}`,
    `#${CH_SET_ID} button:active{background:color-mix(in srgb,var(--T) 18%,transparent)}`,
    `#${CH_SET_ID} button[aria-disabled="true"]{opacity:.45;cursor:default;background:transparent}`,
    `@media (prefers-reduced-motion: reduce){${CH_MENU},${CH_RAIL}>li>span,#${CH_DIM_ID},[${CH_CHECK_ATTRIBUTE}],#${CH_SET_ID} button{transition:none !important}}`,
    // Чистые ответы (#9398, раздел 3а¹): служебный хвост ответа — высота 0 и прозрачность, а НЕ display и
    // не visibility: innerText такой абзац по-прежнему отдаёт (полоса 2б, «ждут твоего слова», «Обкэшить»).
    `html[${CLEAN_ANSWERS_ATTRIBUTE}] ${CLEAN_ANSWERS_PROSE} p[${CLEAN_ANSWERS_MARK}]{height:0 !important;min-height:0 !important;margin:0 !important;padding:0 !important;border:0 !important;overflow:hidden !important;opacity:0 !important;pointer-events:none !important}`,
    // #9166а (WF165, слово Элвиса 09.10 00:05: «всё должно быть прозрачно… из-за того, что есть
    // сейчас рамка, я ничего не понимаю»): коробка поля ввода прозрачна и без обводки, кольца
    // и тени ВО ВСЕХ видах и состояниях (наведение, фокус — shadow-composer-*), не только с живым
    // фоном и не только в широком виде (#8132 отменён этим словом). Рамку прячет цвет: ширина и
    // тень «0 0 0 0» остаются — по ним editorFrame находит коробку (#6890).
    `${COMPOSER_BOX}{background-color:transparent !important;background-image:none !important;-webkit-backdrop-filter:none !important;backdrop-filter:none !important;border-color:transparent !important;box-shadow:0 0 0 0 transparent !important;outline:none !important}`,
    // #9993 (слово Элвиса 16.10 19:40: «именно в вертикальном режиме… рамка есть такая, которая поле
    // ввода символизирует, её нужно ставить… когда это поле внизу находится»): в главном окне, где поле
    // внизу, у прозрачной коробки видна её же рамка — 1 px сплошной, как у коробки в широком виде, цветом
    // линии темы (--cds-border, им же делится колонка широкого вида), скругление — Claude. Сильнее правила
    // выше и правила живого фона (.dframe-root впереди); широкий вид (правило колонки в @container сильнее
    // этого), свёрнутое поле (метка BLOCK_ATTRIBUTE на коробке или её предке) и попап «Open in new window»
    // (в нём .dframe-root нет) — без рамки, как были.
    `.dframe-root ${COMPOSER_BOX}:not([${BLOCK_ATTRIBUTE}^="collapsed"],[${BLOCK_ATTRIBUTE}^="collapsed"] *){border-width:1px !important;border-style:solid !important;border-color:var(--cds-border) !important}`,
    // #9166б: выбранный и наведённый чат в списке слева — тихая подложка цветом текста (4,5 % и 3 %, WF182),
    // без заливки акцентом (тема ставила 30 % акцента — «слишком ярко выделено») и без свечения.
    // Переменные Claude переопределены на панели и на самой строке — ближе, чем у темы (корень,
    // .cds-root, [data-mode]), и сильнее её; кольцо-свечение фокуса строки (focus-visible) снято.
    `aside.dframe-sidebar,aside.dframe-sidebar [data-row]{--df-selected:${SIDEBAR_SELECTED} !important;--df-hover:${SIDEBAR_HOVER} !important}`,
    `aside.dframe-sidebar [data-row],aside.dframe-sidebar [data-row-main-button]{box-shadow:none !important}`,
    // WF182: подложка реплики человека в ленте — переменная Claude на самой реплике (ближе корня темы).
    `[data-cds="UserMessage"]{--cds-bg-user-message:${USER_BUBBLE_FILL} !important}`,
    // Точки чатов — белые, тоном текста темы (слово Элвиса 11.10 01:40: «цветами не надо красить вот эти
    // кругляшки… фиолетовый кругляшок… Белые же должны быть просто»; акцент PMP #9166в снят). У Claude
    // «готов» — акцент, «ждёт» — жёлтая: здесь обе цветом текста; «идёт» — приглушённым, как у Claude, и
    // мигает по-прежнему; кружок «простаивает» — родной контур цветом строки. Цвет остался одной
    // ошибке (data-kind=error) — её пропустить нельзя; значок clay — картинка, не точка.
    `aside.dframe-sidebar .status-dot:not([data-kind="error"],[data-kind="clay"]){background:${SIDEBAR_DOT_INK} !important}`,
    `aside.dframe-sidebar .status-dot[data-kind="running"]{background:${SIDEBAR_DOT_QUIET} !important}`,
    // Поле «Search» списка слева — в тон панели (то же слово: «поиск очень жирный… не должно так
    // контрастно быть»): вместо тёмной плашки --cds-fill-field — подложка выбранной строки (4,5 % цвета
    // текста), под курсором чуть плотнее; кольца и тени нет (правило [data-row] выше), вес обычный.
    `aside.dframe-sidebar .df-search-field{background-color:${SIDEBAR_SELECTED} !important;background-image:none !important;font-weight:400 !important}`,
    `aside.dframe-sidebar .df-search-field:hover{background-color:${SIDEBAR_SEARCH_HOVER} !important}`,
    // #9167 (слово Элвиса: «все элементы должны прижиматься к правому. Либо они крошечные, либо
    // прижимаются к правому краю»): плашки ленты ответа — строки инструментов («Ran N commands»,
    // «Claude Code notice»), карточка «N background commands», карточки-вложения — по правому
    // краю колонки ленты, ширина по содержимому. Текст ответа не трогаем.
    `${FEED_PLATES}{width:fit-content !important;max-width:100% !important;align-self:flex-end !important;margin-inline-start:auto !important;justify-content:flex-end}`,
    // WF119 → WF176 (#9198): «✓ сделал» — маленькая кнопка под первой строкой пункта, без своей
    // колонки слева (она отъедала у списка до 9 rem пустого места); список и продолжения —
    // на родных отступах. Наведение, нажатие и «сделано» (амбер) — общие правила кнопок выше.
    `[${DONE_LIST_ATTRIBUTE}],[${DONE_CONT_ATTRIBUTE}]{box-sizing:border-box;min-width:0}`,
    `li[${DONE_ITEM_ATTRIBUTE}]{min-width:0;max-width:100%;overflow-wrap:anywhere}`,
    `li[${DONE_ITEM_ATTRIBUTE}]>[${NAZH_BUTTON_ATTRIBUTE}="done"]{display:flex;width:fit-content;margin:.3em 0 .2em;padding:0 7px;font-size:11px;line-height:18px;white-space:nowrap;transition:background-color .15s,border-color .15s}`,
    `li[${DONE_ITEM_ATTRIBUTE}]>[${NAZH_BUTTON_ATTRIBUTE}="done"]:active{background:rgba(245,158,11,.32)}`,
    `li[${DONE_ITEM_ATTRIBUTE}]>[${NAZH_BUTTON_ATTRIBUTE}="done"]:focus-visible{outline:2px solid rgba(245,158,11,.7);outline-offset:1px}`,
    `li[${DONE_ITEM_ATTRIBUTE}]>[${NAZH_BUTTON_ATTRIBUTE}="done"][${NAZH_ON_ATTRIBUTE}]:hover{background:rgb(250,176,51)}`,
    `li[${DONE_ITEM_ATTRIBUTE}] :is(p,pre,div,ul,ol){box-sizing:border-box;min-width:0;max-width:100%}`,
    `li[${DONE_ITEM_ATTRIBUTE}] pre,[${DONE_CONT_ATTRIBUTE}] pre,pre[${DONE_CONT_ATTRIBUTE}]{overflow-x:auto}`,
    `#${MIC_ID}>svg{display:block;width:14px;height:14px;pointer-events:none}`,
    `html[data-myclaude-ring-hover] [role="tooltip"],html[data-myclaude-ring-hover] [data-cds="Tooltip"]{display:none !important}`,
    // Нижняя строка поля ввода (#7206, вариант 8.1). Правила бьют только в
    // помеченные узлы (markChin, раздел 12з¹): чужое в строке не трогаем.
    // Микрофон Claude и стрелку ⌄ прячем стилем — узлы живы, и наш микрофон у
    // кружка в режиме «claude» жмёт родную кнопку и спрятанной (#7054).
    `${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="hide"]{display:none !important}`,
    // Кнопки с подписью (режим, модель, эффорт): 11 px, строка 16.
    `${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="text"]{font-size:11px !important;line-height:16px !important;height:16px !important;min-height:16px !important;padding-top:0 !important;padding-bottom:0 !important}`,
    `${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="text"] *{font-size:inherit !important;line-height:inherit !important}`,
    // Короткие подписи не режутся (#7206, замер 23.09: в окне 177 кнопки ужаты
    // до 14/22/22 px, видна одна буква): кнопка не уже своего текста, текст в
    // одну строку и без обреза; обёртки кнопок («row») не уже содержимого. Не
    // хватает места — ужимаются зазоры (правило узкого окна ниже), не текст.
    `${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="text"]{flex-shrink:0 !important;min-width:max-content !important;max-width:none !important;white-space:nowrap !important;overflow:visible !important}`,
    `${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="text"] *{flex-shrink:0 !important;max-width:none !important;white-space:nowrap !important;overflow:visible !important;text-overflow:clip !important}`,
    // Обёртки кнопок — по середине строки (#9195: левая группа Claude прижата кверху, «BP» стоял выше
    // «O 5.5» на 2 точки); цифры — табличные.
    `${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="row"]{min-width:min-content !important;align-self:center !important}`,
    `${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="text"]{font-variant-numeric:tabular-nums}`,
    // Все подписи строки — одним цветом, притемнённым цветом темы (WF183, слово Элвиса 09.10 03:05:
    // «нижняя строка — всё разными цветами»: режим Bypass у Claude — свой яркий, модель и эффорт — белые).
    // От этого цвета (chinInk) берут свой и полоса Рика, «Галерея» и число недели.
    `${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="text"],${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="text"] *{color:var(--cds-text-secondary,currentColor) !important}`,
    // Кружок токенов не ужимается и не уходит за край (WF183: «ему нельзя пропадать»): правое поле строки —
    // как левое у значка микрофона (MIC_ROOM_INSET); тесная строка ужимает поля подписей и зазоры, не кружок.
    `${CHIN_ROW_SELECTOR}{padding-inline-end:${MIC_ROOM_INSET}px !important}`,
    `${CHIN_SELECTOR} ${USAGE_RING_SELECTOR}{flex-shrink:0 !important}`,
    `${CHIN_SELECTOR}[${CHIN_ROW_ATTRIBUTE}] [${CHIN_ATTRIBUTE}="text"]{padding-left:3px !important;padding-right:3px !important}`,
    `${CHIN_SELECTOR}[${CHIN_ROW_ATTRIBUTE}] [${CHIN_ATTRIBUTE}="row"]:not(${CHIN_ROW_SELECTOR.replace(CHIN_SELECTOR, "").trim()}){gap:2px !important;column-gap:2px !important}`,
    `${CHIN_SELECTOR}[${CHIN_ROW_ATTRIBUTE}] [${CHIN_ATTRIBUTE}="row"][class*="ms-auto"]{padding-inline-start:2px !important}`,
    // Кнопки-значки (плюс): 16×16, значок 13.
    `${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="icon"]{width:16px !important;min-width:16px !important;height:16px !important;min-height:16px !important;padding:0 !important}`,
    `${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="icon"] svg{width:13px !important;height:13px !important}`,
    // Подписи коротко ВСЕГДА — при любой ширине строки и окна (WF195, слово Элвиса 09.10 04:05–04:10:
    // «Op5.5 — мелко написать, только мелко… Bp… внизу опять всё едет»; до WF195 — только в тесной строке,
    // и широкая строка с длинными подписями раздувала пол колонки). Полное имя — подсказкой (title, markChin).
    // Тесная строка (метка chinRowFit) ужимает только поля и зазоры; кегль узкого окна ниже сильнее.
    `${CHIN_SELECTOR} [${CHIN_SHORT_ATTRIBUTE}]{font-size:0 !important;letter-spacing:0 !important}`,
    // WF226 (снимок Элвиса 10.10, замер живого окна): «Bp», «Op5.5», «Ex» стояли на 1,5–2 px выше цифр
    // галереи и недели и середины значков строки. Причина — распорка строки у держателя с кеглем 0: при
    // высоте строки 16 она раздувала строку подписи с 16 до 20, и подпись уезжала вверх. Без распорки
    // строка — ровно 16: базовая линия та же, что у родной подписи Claude и у цифр рядом. Хвост «5.5»
    // мельче головы — его строка 12, а не 16: иначе он один раздувал бы строку подписи модели вниз.
    `${CHIN_SELECTOR} [${CHIN_SHORT_ATTRIBUTE}]{line-height:0 !important}`,
    `${CHIN_SELECTOR} [${CHIN_SHORT_ATTRIBUTE}]::after{content:attr(${CHIN_SHORT_ATTRIBUTE});font-size:11px;line-height:16px}`,
    // Модель и эффорт в две строки (#9813, WF266; до того — «Op5.5» слитно, #9181): слово мелко сверху —
    // ::before («Opus», «Effort»), номер или код крупно снизу — ::after («5.5», «Ex») кеглем и строкой соседних
    // подписей (11/16), на одной базовой линии с «Bp», «PMP» и цифрами галереи. Держатель — inline-block: его
    // базовая линия — нижняя строка, ширина — по длинной из двух («Sonnet» над «5»). Слово поднято над строкой
    // отрицательным полем: высота подписи — те же 16, строка не растёт (узкое окно — правило ниже, 10 и 7).
    `${CHIN_SELECTOR} [${CHIN_TAIL_ATTRIBUTE}]{display:inline-block !important;vertical-align:baseline;text-align:center}`,
    `${CHIN_SELECTOR} [${CHIN_TAIL_ATTRIBUTE}]::before{content:attr(${CHIN_SHORT_ATTRIBUTE});display:block;margin-top:-8px;font-size:7.5px !important;line-height:8px}`,
    `${CHIN_SELECTOR} [${CHIN_TAIL_ATTRIBUTE}]::after{content:attr(${CHIN_TAIL_ATTRIBUTE});display:block;font-size:11px !important;line-height:16px;margin-left:0}`,
    // Узкое окно: 10 px. Подпись Claude не переписываем (её держит React) — она спрятана
    // кеглем 0 правилом выше (всегда, WF195), своя рисуется из атрибута. Полное имя
    // остаётся в aria-label и подсказке Claude.
    `@media (max-width:${CHIN_NARROW_MAX}px){${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="text"]{font-size:10px !important;padding-left:3px !important;padding-right:3px !important}${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="row"],${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="text"]{gap:2px !important;column-gap:2px !important}${CHIN_SELECTOR} [${CHIN_SHORT_ATTRIBUTE}]::after{content:attr(${CHIN_SHORT_ATTRIBUTE});font-size:10px !important;line-height:16px}}`,
    `@media (max-width:${CHIN_NARROW_MAX}px){${CHIN_SELECTOR} [${CHIN_TAIL_ATTRIBUTE}][${CHIN_SHORT_ATTRIBUTE}]::after{content:attr(${CHIN_TAIL_ATTRIBUTE});font-size:10px !important;line-height:16px;margin-left:0}${CHIN_SELECTOR} [${CHIN_TAIL_ATTRIBUTE}]::before{font-size:7px !important}}`,
    // Совсем узкое окно (#7206, 23.09 ~21:05): поля подписей и зазоры — 1 px.
    `@media (max-width:${CHIN_TINY_MAX}px){${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="text"]{padding-left:1px !important;padding-right:1px !important}${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="row"],${CHIN_SELECTOR} [${CHIN_ATTRIBUTE}="text"]{gap:1px !important;column-gap:1px !important}}`,
    // Значок Диктатора в поле узкого окна (WF92-ap2): отступ строки меньше.
    `@media (max-width:${MIC_ROOM_TINY_MAX}px){${CHIN_SELECTOR}[${MIC_ROOM_ATTRIBUTE}]{padding-left:${MIC_ROOM_PAD_TINY}px !important}}`,
    // Время под сообщением (#7747, раздел 14): текст рисуется из атрибута, в
    // textContent строки его нет — чтение ответов (полоса, «Обкэшить», копия)
    // его не видит. Родное время Claude в строке есть (последний ответ, реплика
    // человека, строка действий под мышью) — наше прячется, дубля рядом нет.
    `[${STAMP_ATTRIBUTE}]{display:block !important;pointer-events:none;user-select:none;-webkit-user-select:none}`,
    `[${STAMP_ATTRIBUTE}]::after{content:attr(${STAMP_ATTRIBUTE})}`,
    `${MESSAGE_ROW_SELECTOR}:has([aria-label="Message actions"] time)>[${STAMP_ATTRIBUTE}]{display:none !important}`,
    // #11618: строка действий русского Claude — «Действия с сообщением».
    `${MESSAGE_ROW_SELECTOR}:has([aria-label="Действия с сообщением"] time)>[${STAMP_ATTRIBUTE}]{display:none !important}`,
    // Время последнего сообщения при warm/cold — красное (и наше, и родное;
    // #7750, раздел 12о). Полоски окна не красятся и не мигают — серые (#7848).
    `${MESSAGE_ROW_SELECTOR}[${STALE_ATTRIBUTE}]>[${STAMP_ATTRIBUTE}],${MESSAGE_ROW_SELECTOR}[${STALE_ATTRIBUTE}] [aria-label="Действия с сообщением"] time,${MESSAGE_ROW_SELECTOR}[${STALE_ATTRIBUTE}] [aria-label="Message actions"] time{color:#ef4444 !important}`,
    `[${RING_ATTRIBUTE}]{position:absolute !important;right:${RING_INSET_RIGHT}px !important;bottom:${RING_INSET_BOTTOM}px !important;opacity:1 !important;pointer-events:auto !important;z-index:2147483645 !important}`,
    // Растягиваем скролл-контейнер, а сам редактор освобождаем от его
    // собственного максимума (в Claude Code это max-h-[218px] на .tiptap) —
    // иначе текст остаётся полосой сверху. Прокрутка одна: у контейнера,
    // редактор внутри не скроллит, поэтому вторая полоса не появляется.
    `[${EDITOR_ROOT_ATTRIBUTE}="true"]{box-sizing:border-box !important;height:var(${HEIGHT_VARIABLE}) !important;min-height:var(${HEIGHT_VARIABLE}) !important;max-height:var(${HEIGHT_VARIABLE}) !important;overflow-y:auto !important}`,
    `[${EDITOR_ROOT_ATTRIBUTE}="true"] [${EDITOR_ATTRIBUTE}="true"],[${EDITOR_ROOT_ATTRIBUTE}="true"][${EDITOR_ATTRIBUTE}="true"]{max-height:none !important;min-height:100% !important;height:auto !important;overflow-y:visible !important}`,
  ];

  const style = document.createElement("style");
  style.id = STYLE_ID;
  style.textContent = RULES.join("\n");
  (document.head ?? document.documentElement).appendChild(style);
  track(() => style.remove());
  // CSP страницы может не пустить наш <style>. Молча это выглядит как
  // «полоски нет», поэтому проверяем сразу и отдаём наружу через
  // __myclaude.status(): резерв — перенести правила в claude.css, его лоадер
  // вставляет как cssOrigin:"user" и CSP страницы его не касается.
  state.cssOk = (() => {
    try { return (style.sheet?.cssRules?.length ?? 0) > 0; } catch { return false; }
  })();
  if (!state.cssOk) {
    try { console.warn("[MyClaude] стили ручки не применились (CSP?) — правила надо перенести в claude.css"); } catch {}
  }
  on(document, "securitypolicyviolation", event => {
    if (state.cssViolations.length >= 5) return;
    state.cssViolations.push({
      directive: String(event?.effectiveDirective ?? ""),
      blocked: String(event?.blockedURI ?? "").slice(0, 120),
    });
  });

  const handle = document.createElement("div");
  handle.id = HANDLE_ID;
  handle.setAttribute("role", "separator");
  handle.setAttribute("aria-orientation", "horizontal");
  handle.setAttribute("aria-label", "Изменить высоту поля ввода");
  // Подсказки при наведении нет: всплывающее «Потяни вверх или вниз» мешало
  // читать переписку и закрывало строку модели (слово Элвиса 12.09.2026,
  // #5857). Слепым полоска не стала — её называет aria-label.
  // Кнопки на полоске нет: стрелка получалась крошечной, сидела у правого края
  // и попасть в неё было нечем. Свёрнутое поле разворачивает одиночный клик по
  // любому месту полоски.
  handle.appendChild(document.createElement("span"));
  (document.body ?? document.documentElement).appendChild(handle);
  track(() => handle.remove());
  // Дубли полоски у краёв окна (#6743) — тем же приёмом, что и ручка: свой узел
  // в body, ставится по координатам. Роль у них кнопочная: тянуть нельзя.
  const makeSuperRail = id => {
    const node = document.createElement("div");
    node.id = id;
    node.setAttribute("role", "button");
    node.setAttribute("aria-label", "Свернуть или вернуть поле ввода");
    node.appendChild(document.createElement("span"));
    (document.body ?? document.documentElement).appendChild(node);
    track(() => node.remove());
    return node;
  };
  const superTop = makeSuperRail(SUPER_TOP_ID);
  const superBottom = makeSuperRail(SUPER_BOTTOM_ID);
  // Рейка ширины правой колонки (раздел 2г) — тем же приёмом: один узел на окно,
  // в body, ставится по координатам; в узком виде спрятана.
  const rail = document.createElement("div");
  rail.id = SIDE_RAIL_ID;
  rail.setAttribute("role", "separator");
  rail.setAttribute("aria-orientation", "vertical");
  rail.setAttribute("aria-label", "Изменить ширину правой колонки");
  rail.appendChild(document.createElement("span"));
  (document.body ?? document.documentElement).appendChild(rail);
  track(() => rail.remove());
  // Резерв на случай, когда CSP страницы не пустила наш <style>: положение
  // полоски и саму линию ставим напрямую через CSSOM — его CSP не касается
  // (запрещён бывает <style> и атрибут style, а не element.style.setProperty).
  // Без этого незастилованная полоска встала бы обычным блоком в поток страницы.
  // Сворачивание и высота этим не спасаются: их правила переносит в claude.css
  // оркестратор.
  if (!state.cssOk) {
    const box = {
      position: "fixed", display: "none", "align-items": "center", "justify-content": "center",
      height: `${HANDLE_HEIGHT}px`, padding: "0", border: "0", background: "transparent",
      cursor: "ns-resize", "user-select": "none", "-webkit-app-region": "no-drag",
      "touch-action": "none", "z-index": "2147483646",
    };
    const line = {
      display: "block", width: "100%", height: "2px", "border-radius": "999px",
      background: "currentColor", opacity: ".10", "pointer-events": "none",
    };
    for (const [name, value] of Object.entries(box)) handle.style.setProperty(name, value);
    const span = handle.firstElementChild;
    if (span) for (const [name, value] of Object.entries(line)) span.style.setProperty(name, value);
    // Дубли у краёв окна — та же полоска, только курсор не «тянуть» (#6891).
    for (const node of [superTop, superBottom]) {
      for (const [name, value] of Object.entries({ ...box, cursor: "pointer" })) node.style.setProperty(name, value);
      const own = node.firstElementChild;
      if (own) for (const [name, value] of Object.entries(line)) own.style.setProperty(name, value);
    }
    for (const [name, value] of Object.entries({
      position: "fixed", display: "none", width: `${SIDE_RAIL_WIDTH}px`, padding: "0", border: "0",
      background: "transparent", cursor: "col-resize", "user-select": "none", "touch-action": "none",
      "z-index": "2147483646",
    })) rail.style.setProperty(name, value);
  }
  // По ЖИВОМУ узлу (#6766): до WF78 здесь стояло одно только display, и
  // окно, из которого узел вынесло вместе с содержимым body, бодро
  // отвечало «полоска есть».
  statusPart("handleVisible", () => handle.isConnected && handle.style.display !== "none");
  // Дубли полоски у краёв окна (#6743): на гейте по ним видно, что полоска
  // на месте. Нижняя у свёрнутого поля уступает основной (#6892) — там
  // false и есть «как задумано».
  statusPart("superVisible", () => superTop.isConnected && superTop.style.display !== "none");
  statusPart("superBottomVisible", () => superBottom.isConnected && superBottom.style.display !== "none");
  HATCH && Object.assign(HATCH, { RULES });

