  // ---- 2а. Слои чата: тема, шрифт, размер, оформление ----------------------
  // Четыре независимых слоя, у каждого своя ячейка в хранилище и своя таблица
  // стилей: тема (цвета), шрифт, размер текста сообщений и оформление (look).
  // Команда меняет тот слой, поле которого в ней есть, — шрифт без темы окно не
  // красит, тема без шрифта его не сбрасывает, размер не трогает ни того, ни другого.
  // Неоновой рамки окна нет (#9471): поле `frame` в командах и в карте страница
  // молча пропускает — его ещё шлёт гашение приложения и везут старые записи.
  //
  // С WF9 тема закреплена за ЧАТОМ, а не за окном: вернулся в разговор — вернулся
  // его цвет, в каком бы окне он ни открылся. У главного окна сверх того есть
  // своя тема (`main`) — ею красится всякий чат, у которого записи нет, поэтому
  // «Новый чат» и «Обкэшить» цвет окна не меняют. Смену чата ловит сторож
  // заголовка (watchChatTitle): страница при этом не перезагружается, и другого
  // признака у смены разговора нет.
  //
  // С WF35 чат опознаётся не именем, а ID (`id:local_<uuid>`, раздел 12в): имя
  // Элвис меняет, id — нет, и переименование разговора больше не теряет цвет.
  // Имя осталось тенью — под ним живут окна, которые своего id ещё не знают
  // (попап в первые секунды). Вся карта при этом умирает вместе с переустановкой
  // Claude, поэтому её копию держит приложение и присылает командой
  // themes-restore (см. runThemesRestoreCommand).
  //
  // Тема — конструируемая таблица стилей (adoptedStyleSheets) с переменными
  // Claude, собранная из палитры шести цветов. Порт ElvisOS/Resources/claude-theme-manager.mjs
  // (хелперы normalizeHex/rgb/mix/hslTriple и generateThemeCss), урезанный:
  // без Epitaxy-блока Claude Code, без шкал --cds-gray/--cds-blue, без
  // --tw-prose и скроллбаров. Всё с !important — стили самого Claude авторские
  // и без !important, а claude.css лоадер вставляет как user-стили, и цветов в
  // нём нет: конфликта каскада не возникает.
  //
  // Раздел стоит здесь, а не в конце файла, намеренно: сохранённая тема обязана
  // вернуться в окно ДО того, как строится полоска ручки, иначе окно моргает
  // чужими цветами. Ручку, «Обкэшить» и прокрутку модуль не трогает — у него
  // свой узел и свои ключи хранилища myclaude-theme-*.
  // Тема и шрифт этого окна на время его жизни: sessionStorage у каждого окна
  // свой и переживает навигацию внутри окна (как высота поля выше).
  const THEME_SESSION_KEY = "myclaude-theme-v1";
  // Карта на перезапуск Claude: { main: запись главного окна, "w:<заголовок>":
  // запись подчинённого окна, "*": запись для всех }. localStorage у окон общий.
  const THEME_MAP_KEY = "myclaude-themes-v1";
  const THEME_ALL_KEY = "*";
  // Снятые «всем окнам» личные слои (#5743): { <ключ карты>: { theme?, font?, size?, look?, by? } }.
  // Отдельный ключ, а не запись карты: зеркало приложения и themes-restore чужих ключей не знают.
  const THEME_PREV_KEY = "myclaude-themes-prev-v1";
  // Кэш ответа родителя про свой чат (раздел 12в). Константа стоит ЗДЕСЬ, а не
  // в самом разделе: её читает chatIdKey (раздел 2а) уже на инжекте, а раздел
  // 12в лежит ниже по файлу — его `const`-ы к тому мгновению ещё в TDZ.
  const CHAT_ID_KEY = "myclaude-chat-v1";
  // Своё React-волокно (раздел 12в, WF77): откуда начинаем обход и как глубоко
  // идём вверх по `return`. Стоят ЗДЕСЬ по той же причине, что ключ выше.
  // Старт — контейнеры ИМЕННО ЭТОГО чата, глубина — как у «Открыть в Chrome».
  const CHAT_FIBER_SELECTOR = ".epitaxy-titlebar,.epitaxy-chat-panel";
  const CHAT_FIBER_DEPTH = 16;
  const CHAT_FIBER_PROPS = ["sessionId", "initialSessionId", "episodeKey"];
  // Ответ волокна до смены заголовка окна: myChatId() зовут на каждую команду и
  // на каждом круге сторожа заголовка. Промах НЕ запоминается — разметка попапа
  // приходит позже инжекта, и запомненный null остался бы с окном навсегда.
  // node — узел, где id нашёлся (WF93, #7378): Claude держит закрытые попапы
  // скрытыми и отдаёт окно следующему чату, панель при этом монтируется заново,
  // и ответ с отвалившимся узлом — про прошлый чат этого окна.
  const chatFiberState = { title: null, id: null, node: null };
  // Сторож заголовка: подчинённое окно («Open in new window») живёт на
  // about:blank и получает заголовок позже, чем выполняется инжект, а в главном
  // окне заголовок меняется на каждом чате. План просит опрос раз в секунду —
  // берём вдвое чаще, чтобы окно не моргало чужой темой (наблюдатель за <head>
  // ловит смену тем же кадром, опрос — только страховка).
  const THEME_TITLE_TICK_MS = 500;
  // Сколько ждём заголовка, чтобы дописать выбор, сделанный до его появления.
  const THEME_TITLE_WAIT_MS = 10000;
  const THEME_ROOT_SELECTOR =
    ':root, html, body, [data-mode], .cds-root, .dark, .light, .darkTheme, .lightTheme, .dframe-root';
  const THEME_PALETTE_KEYS = ["accent", "background", "foreground", "sidebar", "panel", "muted"];
  const THEME_FALLBACK = {
    dark: { accent: "#60a5fa", background: "#0b1020", foreground: "#e5edff", sidebar: "#070b16", panel: "#121a30", muted: "#91a0bf" },
    light: { accent: "#2563eb", background: "#ffffff", foreground: "#111827", sidebar: "#f3f4f6", panel: "#ffffff", muted: "#64748b" },
  };
  // Шрифт приходит голым именем семейства («SF Mono»), стек дописываем здесь:
  // так меню шлёт одно слово, а страница отвечает за то, чем это слово подпереть.
  const FONT_FAMILY_MAX = 60;
  const FONT_STACK_UI = "-apple-system, system-ui, sans-serif";
  const FONT_STACK_MONO = "ui-monospace, SFMono-Regular, Menlo, monospace";
  // Размер текста сообщений (WF12). Границы — по обе стороны от обычных 15 px:
  // меньше 11 текст не читается, больше 24 в окне помещается пара абзацев.
  const SIZE_MIN = 11;
  const SIZE_MAX = 24;
  // Правило пишется ТОЛЬКО на текст сообщений. Кнопки, сайдбар, поле ввода и
  // шапка живут своим размером: полезли бы туда — поехала бы вся раскладка окна,
  // а вместе с ней и замеры ручки. Приметы взяты те же, что уже проверены живьём
  // в CHAT_STARTED_SELECTOR (раздел 1): .font-claude-response отвечает за ответы
  // и в claude.ai, и в окне Claude Code, .epitaxy-user-turn — за вопросы в Code.
  // Точный селектор ответов Code сверяет probe на гейте (план WF12, п. 1).
  const SIZE_ANSWER_SELECTORS = [
    ".font-claude-response",
    ".font-claude-response-body",
    '[data-testid="assistant-message"] .prose',
    // Окно Claude Code (probe 04.09): ответ — .prose внутри строки сообщения, у вопроса своя обёртка.
    '.epitaxy-transcript-typography [class*="message-row"]:not(:has(.epitaxy-user-turn)) .prose',
  ];
  const SIZE_QUESTION_SELECTORS = ["[data-user-message-bubble]", ".epitaxy-user-turn"];
  // Заголовки и код внутри ответа — в em, то есть долей от заданного размера:
  // так они едут пропорционально сами и не спорят с выбором Элвиса.
  const SIZE_HEADINGS = [["h1", 1.6], ["h2", 1.35], ["h3", 1.18], ["h4", 1.05]];
  const SIZE_CODE_SCALE = 0.9;
  // Вложения ПОЛЯ ВВОДА в узком окне (WF61, #5912). Замер живьём 12.09 23:37
  // (вставили картинку в поле и сняли разметку): плашка вложения — это
  // `div[data-cds=MessageAttachmentsImage][data-cds-attachment]` с классом
  // `size-[120px]`, то есть 120×120 задаёт КЛАСС на самой плашке, а не
  // `[data-cds-tile-media]` — его в композере нет вовсе (он живёт в ленте
  // разговора, там плитки 247×142). Первая версия правила целилась в него и не
  // меняла ничего: молча, без красного теста. В окне 280 на поле остаётся 194
  // точки — в ряд встаёт РОВНО ОДНА плашка. Пять скриншотов = 600 точек, то есть всё окно: ни черновика, ни
  // строки модели, печатать негде. В широком окне те же плитки ложатся сеткой, и
  // трогать её незачем — отсюда порог. 560 стоит далеко и от окон Элвиса
  // (255–259 точек внутри окна 280), и от его широкого окна (829): разметка
  // Claude может подвинуться на десяток точек, решение от этого не поедет.
  const NARROW_WINDOW_MAX = 560;
  // Сторона плашки в узком окне. 56 + зазор 6 (его ставит сам Claude, `gap-xs`) —
  // это три штуки в ряд на 220 точках ряда; меньше уже не картинка, а значок.
  const NARROW_TILE = 56;
  // Ряд плиток плотнее (WF188, слово Элвиса 09.10 03:50: «первый, второй, третий,
  // потом перенос, а место было… Трамбуй посильнее»): зазор 4 вместо gap-xs Claude
  // (6–8), а сторона плитки — доля ширины ряда (контейнер запроса — коробка вложений, её
  // ширина равна ряду; сам ряд контейнером НЕ делать — #11187: с 30.10 у Claude ряд —
  // прокрутка внутри flex-строки, и контейнер схлопывал его до своих полей, 18 точек): пять в
  // ряд, пока плитка не меньше COMPOSER_TILE_MIN и не больше потолка вида (56 узко,
  // WIDE_TILE в колонке). В колонке 330 (ряд ~230) встают пять, на 250 — четыре,
  // на 450 — шесть; перенос — только когда правда не влезает. Номер 16×16 читается и на 32.
  const COMPOSER_TILE_GAP = 4;
  const COMPOSER_TILE_MIN = 32;
  const COMPOSER_TILE_ROW = 5;
  const composerTileSide = max => `clamp(${COMPOSER_TILE_MIN}px, calc((100cqw - ${COMPOSER_TILE_GAP * (COMPOSER_TILE_ROW - 1)}px) / ${COMPOSER_TILE_ROW}), ${max}px)`;
  const COMPOSER_TILE_ROW_SELECTOR = '[data-cds-composer-attachments] [data-cds="MessageAttachments"], [data-cds-composer-attachments] :has(> [data-cds-attachment] + [data-cds-attachment])';
  // Крестик «Remove» (20×20) сидит в углу плашки и вылезает за неё на 8 точек
  // вверх — замер живьём. Коробка с прокруткой обрезает всё, что торчит наружу
  // (overflow-y:auto делает и overflow-x:auto), поэтому даём ей поля: без них у
  // верхнего ряда срезало бы половину кнопки, а ею Элвис снимает вложение.
  const NARROW_ATTACHMENTS_PAD = 12;
  // Потолок блока вложений и потолок области текста (WF62, #5951). Замер живьём
  // 13.09 10:32 в окне Элвиса 653×784: девять вложений — это блок в 386 точек
  // БЕЗ потолка, плюс область текста Claude (`max-h-96`, 384) и строка модели.
  // Низ блока ввода уехал на 853 при высоте окна 784 — Элвис не видел ни конца
  // своего текста, ни кнопки отправки. Оба потолка — доля ОКНА: у него окна и
  // 784, и 394 высотой, и зашитые точки врали бы. Область текста ограничиваем
  // ПОТОЛКОМ (max-height), а не подменой height: подмена уже воевала с пятью
  // скриншотами вечером 12.09 и роняла низ окна (#5886). Больше собственного
  // потолка Claude (384) не разрешаем себе никогда — иначе поле стало бы выше,
  // чем он задумал.
  const ATTACHMENTS_HEIGHT = "min(30vh, 240px)";
  const EDITOR_HEIGHT = "min(384px, 40vh)";
  // Номер скриншота на плитке поля (#7532): атрибут ставит раздел 12
  // (markShotTiles), рисует attachmentsCss. Здесь — потому что лист стилей
  // собирается раньше, чем объявлен раздел 12.
  const SHOT_ATTR = "data-myclaude-shot";
  // Неоновой рамки окна (WF12, #5343) больше нет (#9471): id остался ради уборки
  // её оверлея у тех, кто ставил страницу раньше (раздел 2а). Скругление окна
  // macOS берёт рамка «ждут твоего слова» (12и¹); число сверяет Swift-тест LiveStyle.
  const WINDOW_FRAME_ID = "myclaude-window-frame";
  const WINDOW_FRAME_RADIUS = 10;

  // Цветовая арифметика донора один в один: короткая запись #abc и запись с
  // альфой приводятся к шести знакам, остальное падает на запасной цвет.
  const normalizeHex = (value, fallback) => {
    let source = typeof value === "string" ? value.trim() : fallback;
    if (!/^#[0-9a-f]{3,8}$/i.test(source)) source = fallback;
    let hex = String(source).slice(1);
    if (![3, 4, 6, 8].includes(hex.length)) hex = String(fallback).slice(1);
    if (hex.length === 3 || hex.length === 4) hex = hex.split("").map(part => part + part).join("");
    return `#${hex.slice(0, 6).toLowerCase()}`;
  };
  const rgbOf = color => {
    const hex = normalizeHex(color, "#000000").slice(1);
    return [0, 2, 4].map(offset => Number.parseInt(hex.slice(offset, offset + 2), 16));
  };
  const hexOf = channels => `#${channels
    .map(value => Math.round(Math.max(0, Math.min(255, value))).toString(16).padStart(2, "0"))
    .join("")}`;
  const mixHex = (left, right, ratio) => {
    const from = rgbOf(left);
    const to = rgbOf(right);
    return hexOf(from.map((value, index) => value + (to[index] - value) * ratio));
  };
  // Разбор цвета на части: тон 0…360, насыщенность и светлота долями 0…1.
  // Отсюда же растёт hslTriple — вывод у него обязан остаться прежним побайтно.
  const hslParts = color => {
    const [red, green, blue] = rgbOf(color).map(value => value / 255);
    const max = Math.max(red, green, blue);
    const min = Math.min(red, green, blue);
    const lightness = (max + min) / 2;
    const delta = max - min;
    let hue = 0;
    let saturation = 0;
    if (delta !== 0) {
      saturation = delta / (1 - Math.abs(2 * lightness - 1));
      if (max === red) hue = 60 * (((green - blue) / delta) % 6);
      else if (max === green) hue = 60 * ((blue - red) / delta + 2);
      else hue = 60 * ((red - green) / delta + 4);
    }
    if (hue < 0) hue += 360;
    return [hue, saturation, lightness];
  };
  // Переменные Claude хранят не цвет, а HSL-триплет «H S% L%»: страница сама
  // подставляет его в hsl(...) и добавляет прозрачность.
  const hslTriple = color => {
    const [hue, saturation, lightness] = hslParts(color);
    return `${hue.toFixed(3)} ${(saturation * 100).toFixed(3)}% ${(lightness * 100).toFixed(3)}%`;
  };
  const hexFromHsl = (hue, saturation, lightness) => {
    const turn = ((hue % 360) + 360) % 360;
    const sat = Math.max(0, Math.min(1, saturation));
    const light = Math.max(0, Math.min(1, lightness));
    const chroma = (1 - Math.abs(2 * light - 1)) * sat;
    const second = chroma * (1 - Math.abs(((turn / 60) % 2) - 1));
    const shift = light - chroma / 2;
    const [red, green, blue] = turn < 60 ? [chroma, second, 0]
      : turn < 120 ? [second, chroma, 0]
      : turn < 180 ? [0, chroma, second]
      : turn < 240 ? [0, second, chroma]
      : turn < 300 ? [second, 0, chroma]
      : [chroma, 0, second];
    return hexOf([(red + shift) * 255, (green + shift) * 255, (blue + shift) * 255]);
  };
  // Яркость и контраст по WCAG: подсветка кода обязана читаться и в тёмных, и в
  // светлых темах, а «на глаз» это не проверить — считаем числом (#5365).
  const luminance = color => {
    const [red, green, blue] = rgbOf(color).map(value => {
      const channel = value / 255;
      return channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
  };
  const contrastRatio = (left, right) => {
    const first = luminance(left);
    const second = luminance(right);
    return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
  };
  // Дотянуть цвет до читаемости, НЕ трогая тон и насыщенность: двигаем только
  // светлоту шагом в процент прочь от фона. Так оттенки One Dark остаются
  // узнаваемыми. Контраст уже достаточен — отдаём цвет как есть, без обратного
  // хода hex → hsl → hex (иначе дрожал бы последний знак). Цели не достигли —
  // отдаём лучшего из перепробованных, включая исходный: хуже, чем было, не
  // возвращаем никогда.
  const readableOn = (color, background, target) => {
    const start = normalizeHex(color, "#000000");
    const under = normalizeHex(background, "#000000");
    if (contrastRatio(start, under) >= target) return start;
    const [hue, saturation, lightness] = hslParts(start);
    const step = luminance(under) < 0.5 ? 0.01 : -0.01;
    let best = start;
    let bestRatio = contrastRatio(start, under);
    let level = lightness;
    for (let index = 0; index < 100; index += 1) {
      level += step;
      if (level < 0 || level > 1) break;
      const candidate = hexFromHsl(hue, saturation, level);
      const ratio = contrastRatio(candidate, under);
      if (ratio > bestRatio) { best = candidate; bestRatio = ratio; }
      if (ratio >= target) return candidate;
    }
    return best;
  };

  // Тема приходит снаружи (command.json) и из хранилища, то есть текстом, за
  // который мы не отвечаем. Отсюда разбор: палитра — только шесть цветов и
  // только hex, имя и id — без знаков, которыми можно закрыть комментарий или
  // правило CSS. Не объект или нет палитры — темы нет вовсе.
  const themeText = (raw, fallback) => {
    const result = String(raw ?? "").replace(/[<>{};*\\/"']/g, " ").replace(/\s+/g, " ").trim().slice(0, 80);
    return result || fallback;
  };
  const normalizeTheme = value => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null;
    const palette = value.palette;
    if (!palette || typeof palette !== "object" || Array.isArray(palette)) return null;
    const type = value.type === "light" ? "light" : "dark";
    const base = THEME_FALLBACK[type];
    const clean = {};
    for (const key of THEME_PALETTE_KEYS) clean[key] = normalizeHex(palette[key], base[key]);
    return { id: themeText(value.id, "custom"), name: themeText(value.name, "Тема"), type, palette: clean };
  };

  const themeCss = theme => {
    const light = theme.type === "light";
    const base = THEME_FALLBACK[theme.type === "light" ? "light" : "dark"];
    const background = normalizeHex(theme.palette?.background, base.background);
    const foreground = normalizeHex(theme.palette?.foreground, base.foreground);
    const accent = normalizeHex(theme.palette?.accent, base.accent);
    const sidebar = normalizeHex(theme.palette?.sidebar, mixHex(background, foreground, 0.04));
    const panel = normalizeHex(theme.palette?.panel, mixHex(background, foreground, 0.06));
    const muted = normalizeHex(theme.palette?.muted, mixHex(foreground, background, 0.35));
    // Две ступени поверхностей над фоном: карточки, поповеры, поля.
    const surface1 = mixHex(background, foreground, light ? 0.025 : 0.045);
    const surface2 = mixHex(background, foreground, light ? 0.05 : 0.075);
    const border = mixHex(accent, background, 0.72);
    const accentHot = mixHex(accent, foreground, 0.20);
    // Палитра кода считается ОДИН раз и раздаётся всем, кому нужна: блокам кода,
    // подсветке, инлайну и просмотрщику диффов — иначе коробки в одном окне
    // разъезжаются по цвету (#5365).
    const code = codePalette({ type: theme.type, background, foreground, accent });
    return `/* PimpMyClaude · тема ${themeText(theme.name, "Тема")} · порт ElvisOS */
${THEME_ROOT_SELECTOR} {
  color-scheme: ${theme.type} !important;
  --accent-brand: ${hslTriple(accent)} !important;
  --accent-000: ${hslTriple(accent)} !important;
  --accent-100: ${hslTriple(mixHex(accent, background, 0.12))} !important;
  --accent-200: ${hslTriple(mixHex(accent, background, 0.30))} !important;
  --accent-900: ${hslTriple(mixHex(accent, background, 0.78))} !important;
  --accent-pro-000: ${hslTriple(accent)} !important;
  --accent-pro-100: ${hslTriple(mixHex(accent, background, 0.12))} !important;
  --accent-pro-200: ${hslTriple(mixHex(accent, background, 0.30))} !important;
  --accent-pro-900: ${hslTriple(mixHex(accent, background, 0.78))} !important;
  --bg-000: ${hslTriple(surface2)} !important;
  --bg-100: ${hslTriple(surface1)} !important;
  --bg-200: ${hslTriple(background)} !important;
  --bg-300: ${hslTriple(mixHex(background, light ? "#000000" : "#ffffff", 0.015))} !important;
  --bg-400: ${hslTriple(background)} !important;
  --bg-500: ${hslTriple(background)} !important;
  --text-000: ${hslTriple(foreground)} !important;
  --text-100: ${hslTriple(foreground)} !important;
  --text-200: ${hslTriple(mixHex(foreground, background, 0.15))} !important;
  --text-300: ${hslTriple(mixHex(foreground, background, 0.28))} !important;
  --text-400: ${hslTriple(mixHex(foreground, background, 0.42))} !important;
  --text-500: ${hslTriple(mixHex(foreground, background, 0.55))} !important;
  --border-100: ${hslTriple(mixHex(foreground, background, 0.25))} !important;
  --border-200: ${hslTriple(mixHex(foreground, background, 0.45))} !important;
  --border-300: ${hslTriple(mixHex(accent, background, 0.45))} !important;
  --border-400: ${hslTriple(accent)} !important;
  --oncolor-100: ${hslTriple(background)} !important;
  --oncolor-200: ${hslTriple(background)} !important;
  --oncolor-300: ${hslTriple(background)} !important;
  --claude-accent-clay: ${accent} !important;
  --claude-background-color: ${background} !important;
  --claude-foreground-color: ${foreground} !important;
  --claude-secondary-color: ${muted} !important;
  --claude-border-color: ${mixHex(accent, background, 0.55)} !important;
  --claude-text-color: ${foreground} !important;
  --claude-border: ${border} !important;
  --claude-border-300: ${border} !important;
  --claude-border-300-more: ${mixHex(accent, background, 0.50)} !important;
  --claude-text-100: ${foreground} !important;
  --claude-text-200: ${mixHex(foreground, background, 0.15)} !important;
  --claude-text-400: ${muted} !important;
  --claude-text-500: ${mixHex(muted, background, 0.22)} !important;
  --claude-description-text: ${muted} !important;
  --page-bg: ${background} !important;
  --surface-0: ${background} !important;
  --surface-1: ${panel} !important;
  --surface-2: ${surface2} !important;
  --surface-3: ${mixHex(panel, foreground, 0.04)} !important;
  --clay: ${accent} !important;
  --clay-emphasized: ${mixHex(accent, foreground, 0.24)} !important;
  --border: ${mixHex(accent, background, 0.72)} !important;
  --border-strong: ${mixHex(accent, background, 0.50)} !important;
  --border-stronger: ${mixHex(accent, background, 0.30)} !important;
  --border-accent: ${accent} !important;
  --bg-neutral: ${surface1} !important;
  --bg-neutral-hover: ${surface2} !important;
  --on-primary: ${background} !important;
  --on-accent: ${background} !important;
  --on-brand: ${background} !important;
  --ring-color: ${mixHex(accent, background, 0.42)} !important;
  --cds-page-bg: ${background} !important;
  --cds-surface-0: ${background} !important;
  --cds-surface-1: ${surface1} !important;
  --cds-surface-2: ${surface2} !important;
  --cds-surface-3: ${panel} !important;
  --cds-surface-panel: ${panel} !important;
  --cds-surface-popover: ${surface2} !important;
  --cds-text-primary: ${foreground} !important;
  --cds-text-secondary: ${muted} !important;
  --cds-text-muted: ${mixHex(muted, background, 0.22)} !important;
  --cds-text-accent: ${accent} !important;
  --cds-border: ${mixHex(accent, background, 0.72)} !important;
  --cds-border-strong: ${mixHex(accent, background, 0.50)} !important;
  --cds-border-stronger: ${mixHex(accent, background, 0.30)} !important;
  --cds-border-accent: ${accent} !important;
  --cds-clay: ${accent} !important;
  --cds-clay-emphasized: ${mixHex(accent, foreground, 0.24)} !important;
  --cds-fill-accent: ${accent} !important;
  --cds-fill-accent-hover: ${mixHex(accent, foreground, 0.20)} !important;
  --cds-fill-brand: ${accent} !important;
  --cds-fill-brand-hover: ${mixHex(accent, foreground, 0.20)} !important;
  --cds-fill-primary: ${foreground} !important;
  --cds-fill-primary-hover: ${mixHex(foreground, background, 0.12)} !important;
  --cds-fill-secondary: ${surface2} !important;
  --cds-fill-secondary-hover: ${panel} !important;
  --cds-fill-field: ${surface1} !important;
  --cds-fill-control: ${surface2} !important;
  --cds-fill-control-hover: ${panel} !important;
  --cds-fill-ghost-hover: ${mixHex(accent, background, 0.82)} !important;
  --cds-oncolor-200: ${background} !important;
  --cds-oncolor-300: ${background} !important;
  --surface-panel: ${panel} !important;
  --surface-popover: ${surface2} !important;
  --text-primary: ${foreground} !important;
  --text-secondary: ${muted} !important;
  --text-muted: ${mixHex(muted, background, 0.22)} !important;
  --fill-accent: ${accent} !important;
  --fill-accent-hover: ${accentHot} !important;
  --fill-brand: ${accent} !important;
  --fill-brand-hover: ${accentHot} !important;
  --fill-primary: ${accent} !important;
  --fill-primary-hover: ${accentHot} !important;
  --fill-secondary: ${surface2} !important;
  --fill-secondary-hover: ${panel} !important;
  --fill-field: ${panel} !important;
  --fill-control: ${surface2} !important;
  --fill-control-hover: ${mixHex(accent, background, 0.70)} !important;
  --fill-ghost-hover: ${mixHex(accent, background, 0.82)} !important;
  --df-z0: ${hslTriple(background)} !important;
  --df-z1: ${hslTriple(surface1)} !important;
  --df-z2: ${hslTriple(surface2)} !important;
  --df-z3: ${hslTriple(panel)} !important;
  --df-z4: ${hslTriple(mixHex(panel, foreground, 0.04))} !important;
  --df-z5: ${hslTriple(mixHex(panel, foreground, 0.08))} !important;
  --df-z6: ${hslTriple(mixHex(accent, background, 0.62))} !important;
  --df-bg-page-hsl: ${hslTriple(background)} !important;
  --df-bg-page: ${background} !important;
  --df-bg-sidebar: ${sidebar} !important;
  --df-sidebar-bg: ${sidebar} !important;
  --df-web-sidebar-bg: ${sidebar} !important;
  --df-surface-primary: ${panel} !important;
  --df-hover: ${mixHex(accent, background, 0.82)} !important;
  --df-selected: ${mixHex(accent, background, 0.70)} !important;
  --df-chip-bg: ${surface2} !important;
  --df-tray-hairline: ${mixHex(accent, background, 0.62)} !important;
}
html, body, #root, .dframe-root, .dframe-content, [class*="dframe-content"] { background: ${background} !important; color: ${foreground} !important; }
/* #8845 (WF125), #8880: в главном окне лента лежит прямо на основе (её красит строка выше),
   а Claude 2.19675.0 красит подложкой --epitaxy-transcript-surface (по умолчанию
   --cds-surface-1) и доку поля, и липкую полосу под лентой во всю её ширину (на ней дока
   стоит с отступами колонки) — под полем полоса другого тона, а с одной перекрашенной
   докой — два поля по бокам. Всё, что Claude красит этой подложкой, — цветом основы;
   прозрачным нельзя: лента прокручивается под доку. Примета — сам класс Claude
   bg-[var(--epitaxy-transcript-surface,…)]. Только главное окно (main.dframe-content /
   .dframe-pane-host): в попапе лента лежит на .epitaxy-root цветом surface-1, там всё
   уже совпадает. В широком виде сильнее прозрачность доки из layoutCss. */
:is(main.dframe-content, .dframe-pane-host) [class*="--epitaxy-transcript-surface"] { background-color: ${background} !important; }
/* Левая панель и её части — только внутри самой панели (WF144, класс WF136 п.4): кнопка или плашка
   с «sidebar» в testid над лентой квадратной заливкой больше не красится. */
aside.dframe-sidebar, aside.dframe-sidebar :is([class*="dframe-sidebar"]:not([class*="dframe-sidebar-edge"]), [data-testid*="sidebar"]) { background-color: ${sidebar} !important; background-image: none !important; }
/* Свёрнутая панель — только кнопки «панель · назад · вперёд» над лентой: не угловатый короб, а скруглённая
   плашка (слово Элвиса 08.10 ~21:00: «Угловатые рамки какие-то некрасиво… Хотя бы рамки скруглил»). Дети
   панели в свёрнутом виде прозрачны — их квадратные углы не торчат из скругления; выезжающий список
   (.dframe-sidebar-body) свой цвет держит. */
.dframe-root[data-collapsed] .dframe-sidebar { border-radius: 10px !important; }
.dframe-root[data-collapsed] aside.dframe-sidebar :is([class*="dframe-sidebar"], [data-testid*="sidebar"]):not(.dframe-sidebar-body, .dframe-sidebar-body *) { background-color: transparent !important; }
::selection { color: ${background} !important; background: ${accent} !important; }
input, textarea, select, [contenteditable="true"] { caret-color: ${accent} !important; }
${epitaxyCss({ type: theme.type, background, foreground, accent, panel, muted, code })}
${codeCss(code)}`;
  };

  // Окна Claude Code (Epitaxy) держат свою палитру на .epitaxy-root: серая шкала
  // --_gray-*, альфа-шкала --t*, ступени --z*, поверхности поля ввода
  // (--surface-prompt-*, --prompt-*). Без этого блока поле ввода и панели Code
  // остаются серыми при любой теме. Порт epitaxyThemeCss из ElvisOS, без шрифтов.
  const EPITAXY_GRAY_LEVELS = [0, 10, 30, 60, 90, 100, 150, 300, 450, 500, 600, 650, 700, 750, 800, 830, 860, 890, 900];
  const EPITAXY_T_ALPHA = {
    light: [0, 0.04, 0.06, 0.1, 0.16, 0.25, 0.5, 0.8, 0.9, 1],
    dark: [0, 0.04, 0.08, 0.12, 0.16, 0.25, 0.48, 0.7, 0.8, 1],
  };
  // Тёмно-красная тема (#8128): тон фона 335°…12°, насыщенность от 0,3 — «Красная»,
  // «Малиновая», «Коралл», «Магма» и такие же «Мои темы»; розовые (322°) — нет.
  const FIELD_BORDER_CONTRAST = 3;
  const FIELD_BORDER_FOCUS_CONTRAST = 3.6;
  const fieldBorderRedTheme = background => {
    const [hue, saturation] = hslParts(normalizeHex(background, "#000000"));
    return saturation >= 0.3 && (hue >= 335 || hue <= 12);
  };
  const epitaxyCss = ({ type, background, foreground, accent, panel, muted, code }) => {
    const light = type === "light";
    // Палитру кода даёт themeCss, чтобы диффы и блоки кода были одного цвета.
    // Позвали без неё (старые тесты, прямой вызов) — считаем сами.
    const codeColors = code ?? codePalette({ type, background, foreground, accent });
    const lightEnd = light ? background : foreground;
    const darkEnd = light ? foreground : background;
    const grayScale = EPITAXY_GRAY_LEVELS
      .map(level => `  --_gray-${level}: ${hslTriple(mixHex(lightEnd, darkEnd, level / 900))} !important;`).join("\n");
    const ink = hslTriple(foreground);
    const tScale = EPITAXY_T_ALPHA[light ? "light" : "dark"]
      .map((alpha, index) => `  --t${index}: hsl(${ink} / ${alpha}) !important;`).join("\n");
    const zColors = [
      background, mixHex(background, panel, 0.55), panel, mixHex(panel, foreground, 0.04),
      mixHex(panel, foreground, 0.08), mixHex(panel, foreground, 0.13), mixHex(foreground, background, light ? 0.45 : 0.3),
    ];
    const zScale = zColors.map((color, index) => `  --z${index}: ${color} !important;`).join("\n");
    // Рамка поля ввода. На тёмно-красных темах (фон — красный тон, #8128: «у темы
    // красной, бордовой не видно… рамки поля ввода») замес акцента с фоном
    // сливается с фоном поля (panel): у «Красной» 1,83:1, «Малиновой» 1,64:1.
    // Там рамка дотягивается светлотой до FIELD_BORDER_CONTRAST к фону поля —
    // тон и насыщенность те же (readableOn); остальные темы — как были.
    const redField = !light && fieldBorderRedTheme(background);
    const promptBorder = redField
      ? readableOn(mixHex(accent, background, 0.55), panel, FIELD_BORDER_CONTRAST)
      : mixHex(accent, background, 0.55);
    const promptFocusBorder = redField
      ? readableOn(mixHex(accent, background, 0.32), panel, FIELD_BORDER_FOCUS_CONTRAST)
      : mixHex(accent, background, 0.32);
    return `/* Claude Code · Epitaxy */
.epitaxy-root, [data-mode="dark"] .epitaxy-root, [data-mode="light"] .epitaxy-root {
${grayScale}
${tScale}
${zScale}
  --_brand-clay: ${hslTriple(accent)} !important;
  --accent: ${accent} !important;
  --accent-hover: ${mixHex(accent, foreground, 0.14)} !important;
  --accent-brand: ${accent} !important;
  --accent-20-brightness: ${mixHex(accent, background, 0.72)} !important;
  --surface-primary: ${background} !important;
  --surface-primary-elevated: ${background}f0 !important;
  --surface-hud: ${background}f2 !important;
  --surface-panel: ${panel} !important;
  --surface-panel-elevated: ${mixHex(panel, foreground, 0.04)} !important;
  --surface-popover: ${mixHex(panel, foreground, 0.03)} !important;
  --surface-popover-elevated: ${mixHex(panel, foreground, 0.06)} !important;
  --surface-toast: ${mixHex(panel, foreground, 0.08)} !important;
  --surface-prompt-blur: ${panel} !important;
  --surface-prompt-focus-hover: ${mixHex(panel, foreground, 0.05)} !important;
  --prompt-compact-bg: ${panel} !important;
  --prompt-compact-bg-focus: ${mixHex(panel, foreground, 0.05)} !important;
  --prompt-blur-inner-color: ${promptBorder} !important;
  --prompt-blur-outer-color: ${promptBorder} !important;
  --prompt-focus-inner-color: ${promptFocusBorder} !important;
  --prompt-focus-outer-color: ${promptFocusBorder} !important;
  --fill-primary-hover: ${mixHex(foreground, background, 0.12)} !important;
  --text-muted: hsl(${hslTriple(muted)} / 0.62) !important;
  --ui-tooltip-fill: ${mixHex(panel, foreground, 0.08)} !important;
  --ui-tooltip-text: ${foreground} !important;
}
.epitaxy-root ::placeholder { color: ${muted} !important; -webkit-text-fill-color: ${muted} !important; opacity: 0.78 !important; }
.epitaxy-root [data-theme="claude"] { --accent-brand: ${hslTriple(accent)} !important; }
/* Блоки кода — <diffs-container> с shadow DOM: наши таблицы стилей внутрь не
   попадают, зато его цвета — переменные хоста и схема light-dark(). Без этого
   блок остаётся чёрным на любой теме (#5365). Фон — общая подложка кода (в
   светлых темах старый замес от панели давал почти белое и коробка сливалась
   со страницей), текст — цвет темы; схема — по типу темы, чтобы подсветка
   синтаксиса взяла свой светлый/тёмный набор. */
.epitaxy-root diffs-container, diffs-container {
  color-scheme: ${light ? "light" : "dark"} !important;
  --diffs-light-bg: ${codeColors.surface} !important;
  --diffs-dark-bg: ${codeColors.surface} !important;
  --diffs-light: ${foreground} !important;
  --diffs-dark: ${foreground} !important;
}
`;
  };

  // Блоки кода (#5365). Подсветка у Claude — highlight.js «One Dark»: числа
  // зашиты в его таблицу, светлого набора нет вовсе, и коробка остаётся чёрной
  // при любой теме, а в светлых темах токены на ней не читаются (строка давала
  // контраст 1,65). Держим привычные оттенки One Dark — по цвету читают код, —
  // но подтягиваем светлоту под нашу подложку: тон и насыщенность не трогаем.
  const ONE_DARK_TOKENS = {
    comment: "#5c6370", keyword: "#c678dd", name: "#e06c75", literal: "#56b6c2",
    string: "#98c379", number: "#d19a66", title: "#61aeee", builtin: "#e6c07b",
  };
  // Комментарий приглушён намеренно: на 4,5 он стал бы таким же ярким, как код,
  // и подсветка потеряла бы смысл.
  const CODE_CONTRAST = 4.5;
  const CODE_COMMENT_CONTRAST = 3.5;
  const codePalette = ({ type, background, foreground, accent }) => {
    const light = type === "light";
    const base = THEME_FALLBACK[light ? "light" : "dark"];
    const page = normalizeHex(background, base.background);
    const ink = normalizeHex(foreground, base.foreground);
    const brand = normalizeHex(accent, base.accent);
    // Подложка считается от пары фон↔текст, а НЕ от панели: у всех девяти
    // светлых тем panel = #ffffff, и коробка на нём пропала бы. Такой замес даёт
    // «полочку» чуть светлее страницы в тёмной теме и чуть темнее — в светлой.
    const surface = mixHex(page, ink, light ? 0.06 : 0.09);
    const tokens = {};
    for (const [group, color] of Object.entries(ONE_DARK_TOKENS)) {
      tokens[group] = readableOn(color, surface, group === "comment" ? CODE_COMMENT_CONTRAST : CODE_CONTRAST);
    }
    return {
      surface,
      // Своя рамка коробки: акцент, уведённый к фону. Рамка цитаты берётся
      // готовой var(--cds-border) — второй константы для неё тут нет.
      border: mixHex(brand, page, 0.62),
      ink,
      // Чип считаем против той же подложки: alpha-1 у Claude — те же 5 % сдвига
      // от фона, а одна опорная поверхность на весь код предсказуемее.
      chipInk: readableOn(brand, surface, CODE_CONTRAST),
      tokens,
    };
  };

  // Превью артефактов Claude прикрывает у себя ровно один background у pre —
  // наши чернила, рамка и восемь токенов туда бы попали, и код на «белой бумаге»
  // превью стал бы нечитаемым. Поэтому каждое наше правило кода выключает себя
  // внутри превью само: хвост приписывается к КАЖДОМУ селектору списка.
  const CODE_NOT_PREVIEW = ":not(:is(.artifact-markdown-preview, .channel-artifact-markdown-preview) *)";
  const outsidePreview = list => list.split(",").map(part => `${part.trim()}${CODE_NOT_PREVIEW}`).join(", ");
  // Селекторы групп — дословно из таблиц Claude (разведка WF34), порядок как в
  // его файле. Правила без цвета (курсив, жирный, подчёркивание) не трогаем.
  const CODE_TOKEN_SELECTORS = {
    comment: ".hljs-comment, .hljs-quote",
    keyword: ".hljs-doctag, .hljs-formula, .hljs-keyword",
    name: ".hljs-deletion, .hljs-name, .hljs-section, .hljs-selector-tag, .hljs-subst",
    literal: ".hljs-literal",
    string: ".hljs-addition, .hljs-attribute, .hljs-meta .hljs-string, .hljs-regexp, .hljs-string",
    number: ".hljs-attr, .hljs-number, .hljs-selector-attr, .hljs-selector-class, .hljs-selector-pseudo, .hljs-template-variable, .hljs-type, .hljs-variable",
    title: ".hljs-bullet, .hljs-link, .hljs-meta, .hljs-selector-id, .hljs-symbol, .hljs-title",
    builtin: ".hljs-built_in, .hljs-class .hljs-title, .hljs-title.class_",
  };
  const codeCss = code => {
    const tokens = Object.entries(CODE_TOKEN_SELECTORS)
      .map(([group, selector]) => `${outsidePreview(selector)} { color: ${code.tokens[group]} !important; }`)
      .join("\n");
    // Инлайн-код красится ТРЕМЯ код-только переменными Claude, а не своими
    // фонами: у него развешаны исключения (чип в ссылке, ячейка th, таблица,
    // вложенный код) — любое наше правило фона их затопчет. Прямое правило ниже
    // нужно старому рендеру, который --cds-* не читает вовсе, и служит
    // страховкой полю ввода, где переменная объявлена ближе к элементу.
    return `/* Блоки кода, подсветка и инлайн — из палитры темы (#5365) */
${THEME_ROOT_SELECTOR} {
  --cds-prose-code-color: ${code.chipInk} !important;
  --code-chip-ink: ${code.chipInk} !important;
  --cds-editor-code-ink: ${code.chipInk} !important;
}
${outsidePreview("pre, .hljs, code.hljs, .code-block__code")} { background: ${code.surface} !important; color: ${code.ink} !important; }
${outsidePreview("pre")} { border: 0.5px solid ${code.border} !important; }
${tokens}
${outsidePreview(".ReactMarkdown code, div.ProseMirror > p > code")} { color: ${code.chipInk} !important; }
${outsidePreview(".epitaxy-markdown blockquote")} { border-left-color: var(--cds-border) !important; }
`;
  };

  // Шрифт — свой слой, со своим разбором. Имя семейства попадает в CSS внутрь
  // кавычек, поэтому белый список жёстче темы: только буквы, цифры, пробел и
  // дефис — ни кавычки, ни точки с запятой, ни звёздочки в имени не будет.
  const normalizeFont = value => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null;
    if (typeof value.family !== "string") return null;
    const family = value.family
      .replace(/[^A-Za-z0-9 -]/g, " ").replace(/\s+/g, " ").trim().slice(0, FONT_FAMILY_MAX).trim();
    if (!family) return null;
    return { id: themeText(value.id, family), family, mono: value.mono === true };
  };

  // Отдельная таблица стилей (см. fontSheet ниже): шрифт без темы окно не
  // красит, тема без шрифта его не сбрасывает.
  const fontCss = font => {
    const stack = `"${font.family}", ${font.mono ? FONT_STACK_MONO : FONT_STACK_UI}`;
    // mono:true — тем же шрифтом и код; mono:false — моно-переменные не трогаем,
    // иначе пропорциональный шрифт уехал бы в блоки кода и таблицы.
    const monoVariables = font.mono ? `
  --font-mono: var(--claude-themes-ui-font) !important;
  --cds-font-mono: var(--claude-themes-ui-font) !important;
  --family-monospace: var(--claude-themes-ui-font) !important;` : "";
    const monoRule = font.mono
      ? "\ncode, pre, kbd, samp { font-family: var(--claude-themes-ui-font) !important; }"
      : "";
    return `/* PimpMyClaude · шрифт ${font.family} */
${THEME_ROOT_SELECTOR} {
  --claude-themes-ui-font: ${stack} !important;
  --font-sans: var(--claude-themes-ui-font) !important;
  --font-serif: var(--claude-themes-ui-font) !important;
  --font-system: var(--claude-themes-ui-font) !important;
  --cds-font-sans: var(--claude-themes-ui-font) !important;
  --cds-font-system: var(--claude-themes-ui-font) !important;
  --cds-font-voice: var(--claude-themes-ui-font) !important;
  --default-font-family: var(--claude-themes-ui-font) !important;
  --family-ui: var(--claude-themes-ui-font) !important;
  --font-ui: var(--claude-themes-ui-font) !important;
  --font-claude-response: var(--claude-themes-ui-font) !important;${monoVariables}
}
body, button, input, textarea, select, h1, h2, h3, h4, h5, h6, p, label, li, td, th, .font-claude-response-body, .font-claude-response-title, .font-claude-response, [data-user-message-bubble] { font-family: var(--claude-themes-ui-font) !important; }${monoRule}
`;
  };

  // Размер — третий слой, со своим разбором. Половинки независимы: команда может
  // нести только «размер ответов», и тогда размер вопросов остаётся прежним
  // (контракт WF12: поля нет — не менять). Обе половинки — целые точки в
  // границах SIZE_MIN…SIZE_MAX; мусор равен отсутствию поля, пустой слой — null.
  const sizePx = value => {
    const px = Math.round(Number(value));
    return Number.isFinite(px) && px >= SIZE_MIN && px <= SIZE_MAX ? px : null;
  };
  const normalizeSize = value => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null;
    const clean = {};
    const answer = sizePx(value.answer);
    const question = sizePx(value.question);
    if (answer != null) clean.answer = answer;
    if (question != null) clean.question = question;
    return Object.keys(clean).length ? clean : null;
  };
  // У КОМАНДЫ размера (WF19) половина знает три состояния, у записи в хранилище —
  // по-прежнему два. Поэтому разбор команды живёт отдельной функцией, а
  // normalizeSize и карта LAYER_NORMALIZE остаются нетронутыми: ту же normalizeSize
  // зовёт entryLayer на КАЖДОМ чтении записи карты, и половина со значением null
  // значит там «слоя нет» — тристейт, вкрученный в неё, потёк бы в хранилище
  // (разбор критика WF19, В1).
  //   поля нет    — половину не трогаем;
  //   число 11…24 — поставить;
  //   ровно null  — снять ЭТУ половину, вторая остаётся как была.
  // Дискриминатор снятия строгий (В2): только литеральный null. sizePx одинаково
  // отдаёт null и на null, и на "abc", и мусор вида {"answer":"abc"} без этого
  // читался бы как снятие. Мусор равен отсутствию поля, как и раньше.
  // Ни одного значимого ключа не осталось (пустой объект, один мусор) — слой равен
  // null, то есть полный сброс: ровно так же читался старый {}.
  const SIZE_HALVES = ["answer", "question"];
  const normalizeSizeCommand = value => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null;
    const clean = {};
    for (const half of SIZE_HALVES) {
      if (!(half in value)) continue;
      if (value[half] === null) { clean[half] = null; continue; }
      const px = sizePx(value[half]);
      if (px != null) clean[half] = px;
    }
    return Object.keys(clean).length ? clean : null;
  };
  // Оформление (WF83, #7178–#7180) — слой из трёх тумблеров: живой фон, неон и
  // ретро-экран, плотный текст. Объект всегда целиком: ключа нет — значит false,
  // ни одного true — слоя нет (как сброс). Так запись в карте одна на все три
  // (контракт `look` плана WF83).
  const LOOK_KEYS = ["aurora", "neon", "dense"];
  // Схема цвета живого фона (WF146, #9107, слово Элвиса 08.10 22:27: «цвета должны
  // настраиваться… приятные человеку… успокаивающее в первую очередь»). Ключ
  // `look.scheme` — id строкой из списка ниже; нет ключа или мусор — «violet»
  // (по умолчанию), и такой ключ в объект не пишется: запись без него прежняя.
  // Каждая схема — четыре тона пятен (a, b, c, d — доли 38/32/30/24, как были) и
  // лучи тонами a, b, c (9/7/7). Тона тихие, без кислоты; читаемость текста та же —
  // доли прозрачности не менялись. «theme» — прежний вид: акцент темы окна и его
  // соседние тона. Порядок — порядок пунктов меню Swift (`status().look.schemes`).
  const LOOK_SCHEME_DEFAULT = "violet";
  const LOOK_SCHEMES = [
    { id: "violet", name: "Фиолетовые сумерки", tones: ["#a47cf0", "#6f80ea", "#cf82c8", "#8a84b8"] },
    { id: "aurora", name: "Северное сияние", tones: ["#4ccfb2", "#68c98e", "#4f8fe0", "#6aa9a2"] },
    { id: "sea", name: "Глубокое море", tones: ["#2f7fb8", "#2a5f9a", "#3fa3a8", "#56728e"] },
    { id: "lavender", name: "Лаванда", tones: ["#b29ee6", "#98a4e0", "#d4a6d6", "#a69bc0"] },
    { id: "sunset", name: "Закат", tones: ["#e6a07c", "#d68a9e", "#c79fc2", "#b08a82"] },
    { id: "forest", name: "Лес", tones: ["#7f9f6a", "#9cb89a", "#5f8f7a", "#8a9a78"] },
    { id: "graphite", name: "Графит", tones: ["#8a929c", "#a3a7ae", "#767e88", "#9a9590"] },
    // Тёплое свечение (#10015) — тема «Светлячки в тумане» Диктатора у коллеги: янтарь, мёд, персик, роза
    // (OKLCH 0.77/0.12/62°, 0.82/0.12/80°, 0.79/0.10/45°, 0.74/0.10/5°): сочнее соседей, но без кислоты
    // (насыщенность HSL до 0,8, как у всех схем).
    { id: "warm", name: "Тёплое свечение", tones: ["#eba25f", "#edbb64", "#f1a685", "#e190a2"] },
    { id: "theme", name: "Как у темы", tones: null },
  ];
  const lookScheme = id => LOOK_SCHEMES.find(item => item.id === id) ?? LOOK_SCHEMES[0];
  // Движение живого фона (#9994, слово Элвиса 16.10 19:42: «эту анимацию отключить, чтобы оно не
  // шевелилось… у людей бывают слабые компьютеры… настройку типа анимация, не анимация или просто
  // статическая градиентная картинка»). Ключ `look.motion` — последним, после scheme, и только при
  // aurora:true: "live" — пятна плывут, как было; "still" — тот же рисунок стоит (ни кадров, ни
  // Web Animations); "image" — один статичный градиент тонами схемы, без пятен и слоёв. Нет ключа
  // или мусор — "still": новое умолчание для всех; как scheme, умолчание в объект не пишется (так же шлёт Swift).
  // "fireflies" (#10015) снято 30.10.2026 (#11211, эффект ушёл в Dictator): старое значение у людей — "still".
  const LOOK_MOTIONS = ["live", "still", "image"];
  const LOOK_MOTION_DEFAULT = "still";
  const lookMotion = look => (LOOK_MOTIONS.includes(look?.motion) ? look.motion : LOOK_MOTION_DEFAULT);
  const normalizeLook = value => {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null;
    const clean = {};
    for (const key of LOOK_KEYS) clean[key] = value[key] === true;
    if (!LOOK_KEYS.some(key => clean[key])) return null;
    const scheme = typeof value.scheme === "string" ? value.scheme.trim() : "";
    if (scheme !== LOOK_SCHEME_DEFAULT && LOOK_SCHEMES.some(item => item.id === scheme)) clean.scheme = scheme;
    if (clean.aurora && lookMotion(value) !== LOOK_MOTION_DEFAULT) clean.motion = lookMotion(value);
    return clean;
  };

  // Отдельная таблица стилей (см. sizeSheet ниже). Цветов в ней нет ВОВСЕ: размер
  // и тема — разные слои, и правило размера обязано пережить любую смену темы.
  const sizeRule = (selectors, suffix, body) =>
    `${selectors.map(item => (suffix ? `${item} ${suffix}` : item)).join(", ")} { ${body} }`;
  const sizeCss = size => {
    const rules = ["/* PimpMyClaude · размер текста сообщений */"];
    if (size.answer) {
      rules.push(sizeRule(SIZE_ANSWER_SELECTORS, "",
        `font-size: ${size.answer}px !important; line-height: 1.5 !important;`));
      for (const [tag, scale] of SIZE_HEADINGS) {
        rules.push(sizeRule(SIZE_ANSWER_SELECTORS, tag, `font-size: ${scale}em !important;`));
      }
      rules.push(sizeRule(SIZE_ANSWER_SELECTORS, ":is(code, pre, kbd, samp)",
        `font-size: ${SIZE_CODE_SCALE}em !important;`));
      // Блок кода — <pre><code>: второй проход em гасим, иначе 0.9 × 0.9.
      rules.push(sizeRule(SIZE_ANSWER_SELECTORS, ":is(pre, kbd, samp) :is(code, kbd, samp)",
        "font-size: 1em !important;"));
    }
    if (size.question) {
      rules.push(sizeRule(SIZE_QUESTION_SELECTORS, "",
        `font-size: ${size.question}px !important; line-height: 1.5 !important;`));
    }
    return `${rules.join("\n")}\n`;
  };

  // Отдельная таблица стилей (см. attachmentsSheet ниже) — раскладка вложений
  // ПОЛЯ ВВОДА в узком окне (WF61, #5912). Ни цветов, ни высоты самого поля в
  // ней нет вовсе: высотой поля владеет раздел 7, и лезть туда нельзя —
  // вечером 12.09 подмена высоты уже воевала с пятью скриншотами, и низ окна
  // прыгал.
  //
  // Целимся ТОЛЬКО в потомков `[data-cds-composer-attachments]`. Тем же
  // компонентом Claude рисует вложения В ЛЕНТЕ разговора, и отделяет одно от
  // другого ровно этой приметой: у него самого плитки ленты растут правилом
  // `…[data-fit=natural]:not([data-cds-composer-attachments] *)`. Голый
  // `[data-cds-attachment]` не трогаем никогда — это попало бы в ленту, а там
  // плитки бывают и 247×142, и 427×320, и они не наше дело.
  //
  // Правил три, и два из них — во ВСЕХ окнах (WF62): коробка вложений получает
  // потолок, свою прокрутку и поля под вылет крестика, а область текста —
  // потолок долей окна. Третье, только в узком окне: плашка 120×120 становится
  // 56×56, и в ряд встают три, а не одна (перенос делает Claude сам — у ряда
  // `flex-wrap: wrap`, раскладку трогать не нужно); `min-*: 0` — чтобы правило
  // пережило день, когда он допишет композеру свой `min-width` (в ленте у него
  // он уже есть).
  //
  // Область текста адресуем `div:has(> .ProseMirror)` — это её ПРЯМОЙ родитель
  // (замер живьём: `w-full max-h-96 min-h-[var(--cmp-row-h)] overflow-y-auto`).
  // По классу `max-h-96` целиться нельзя: это служебное имя Tailwind, оно
  // меняется от сборки к сборке, а `.ProseMirror` — имя самого редактора.
  // Переходы и анимации Claude (`view-transition`, `@starting-style`, transition
  // у плашки) не переопределяем — только раскладка и размер. `!important` здесь
  // не про каскад таблиц, а про день, когда Claude уточнит свой селектор:
  // важное правило автора сильнее любого обычного.
  const attachmentsCss = () => `/* PimpMyClaude · поле ввода не уезжает за низ окна */
[data-cds-composer-attachments] {
  max-height: ${ATTACHMENTS_HEIGHT} !important;
  overflow-y: auto !important;
  padding-top: ${NARROW_ATTACHMENTS_PAD}px !important;
  padding-right: ${NARROW_ATTACHMENTS_PAD}px !important;
  container-type: inline-size !important;
}
div:has(> .ProseMirror) {
  max-height: ${EDITOR_HEIGHT} !important;
}
${COMPOSER_TILE_ROW_SELECTOR} {
  gap: ${COMPOSER_TILE_GAP}px !important;
}
@media (max-width: ${NARROW_WINDOW_MAX}px) {
  [data-cds-composer-attachments] [data-cds-attachment] {
    width: ${composerTileSide(NARROW_TILE)} !important;
    height: ${composerTileSide(NARROW_TILE)} !important;
    min-width: 0 !important;
    min-height: 0 !important;
  }
}
/* PimpMyClaude · номер скриншота в левом нижнем углу плитки поля (#7532, раздел 12) */
[data-cds-composer-attachments] [data-cds-attachment][${SHOT_ATTR}] {
  position: relative !important;
}
[data-cds-composer-attachments] [data-cds-attachment][${SHOT_ATTR}]::after {
  content: attr(${SHOT_ATTR}) !important;
  position: absolute !important;
  left: 3px !important;
  bottom: 3px !important;
  z-index: 1 !important;
  min-width: 16px !important;
  height: 16px !important;
  padding: 0 4px !important;
  box-sizing: border-box !important;
  border-radius: 8px !important;
  background: rgba(0, 0, 0, 0.78) !important;
  color: #fff !important;
  font: 600 11px/16px -apple-system, system-ui, sans-serif !important;
  text-align: center !important;
  pointer-events: none !important;
}
`;

  // Пятая таблица (layoutSheet ниже) — широкий вид окна (WF65, #6176–#6179):
  // лента разговора во всю высоту слева, шапка и поле ввода — правой колонкой.
  // Три правила снаружи блока стоят во ВСЕХ окнах: строка репозитория
  // «+3,331 −143 · Create PR» не показывается никогда (#6179), затемнения ленты
  // сверху и снизу убраны и в узком окне тоже (слово Элвиса 16.09 20:33), имя
  // папки в шапке не превращается в значок (#6177) — правило целится только в
  // спрятанное имя чипа, заголовок чата ужимается сам, кнопки прячутся как раньше.
  //
  // Сам широкий вид — контейнерный запрос по плитке чата, а не по окну: обёртка
  // панели у Claude объявлена контейнером `tile-slot` (замер 16.09, главное окно
  // и попап), и с открытой рядом плиткой терминала плитка чата ýже окна — порог
  // меряет именно её. Флаг `--myclaude-wide: 1` на панели — ЕДИНСТВЕННЫЙ оракул
  // для JS (wideLayout): второго порога по innerWidth нет, иначе CSS и JS
  // разошлись бы на десяток точек. Флаг и сетка ставятся только на ПРОВЕРЕННОЙ
  // форме разметки (шапка + .contents с телом ленты + дока) — попап другой сборки
  // остаётся flex-колонкой, и ручка с полоской там живут как в узком окне.
  // Сетка без переноса DOM: оба `div.contents` прозрачны для grid, три узла
  // расставляются как есть. Дочерние правила вложены (`&`) в правило сетки:
  // условие `:has()` написано один раз, и ни одно из них не сработает там, где
  // сетки нет (иначе `margin-left: 0` у шапки съел бы место под кнопки окна).
  //
  // Поле ввода во всю колонку — цепочкой замера, не догадкой: .epitaxy-prompt →
  // ChatComposer → коробка и четыре block-обёртки (у всех ровно один поточный
  // ребёнок, кнопки абсолютные) → ChatComposerEditor (`div:has(> .ProseMirror)`)
  // — каждой flex-колонка и `flex: 1`, `height: 100%` не раздаём никому. Потолок
  // области текста из attachmentsSheet снимается `max-height: none !important` —
  // спор двух !important решает порядок таблиц, эта стоит после. Правило плитки
  // 56×56 продублировано: колонка 300–420 ýже порога 560, а @media там по окну.
  // Широкий вид — только у СТРАНИЦЫ ЧАТА: в теле ленты есть виртуальная лента
  // `[data-testid="epitaxy-virtual-transcript"]`. На домашнем экране (`/epitaxy`)
  // форма панели та же, но вместо ленты — список сессий, и сетка ставила
  // «Welcome back» в левый нижний угол, а поле ввода — вправо с пустым полем
  // (слово Элвиса 17.09 01:35); там остаётся раскладка Claude.
  //
  // Путь к телу ленты от обёртки панели. В 2.2553.13 Claude завернул тело и доку
  // ещё в один `div.contents` (разведка WF82, #7098: «.contents > .contents >
  // .epitaxy-chat-panel-body»), и прежняя примета формы не сходилась ни в одном
  // окне — широкий вид молча не включался. Оба `div.contents` прозрачны для
  // сетки, ячеек по-прежнему три (шапка, тело, дока), поэтому принимаем обе формы:
  // старую сборку и новую.
  // В 2.42304 (#10146) тело ленты легло в две НАСТОЯЩИЕ обёртки (сцена `@container` и полоса с полями под
  // правую панель сессии Claude «Session details»): «колонка > div > div > тело». Третья форма; в сетке обе
  // обёртки растворяются (`display: contents`), панель сессии прячется — справа снова поле ввода.
  const PANEL_BODY_PATHS = ["> .contents > .epitaxy-chat-panel-body", "> .contents > .contents > .epitaxy-chat-panel-body", "> div > div > .epitaxy-chat-panel-body"];
  // Переменные панели сессии Claude 2.42304 (заданы классами на колонке): ширина панели, её отступ от края, поле
  // ленты под неё и запас прокрутки. В сетке — нули: лента и дока без полей под спрятанную панель.
  const SESSION_RAIL_VARIABLES = ["--session-rail-w", "--session-rail-end", "--session-rail-band-start", "--session-rail-scroll-slack"];
  const panelBody = (prefix, tail = "") => PANEL_BODY_PATHS.map(path => `${prefix}${path}${tail}`).join(", ");
  // Путь от панели к колонке с шапкой (WF125, #8846). В 2.19675.0 главное окно
  // получило ещё одну обёртку: «панель > div.contents > колонка > шапка»; попап и
  // прежнее главное — «панель > колонка > шапка». Обёртка `display: contents`
  // прозрачна для раскладки, но не для селекторов: условия «> div > шапка» в
  // главном окне не сходились, и широкий вид молча не включался (как в WF82).
  // `:has()` внутри `:has()` нельзя — правило выпадет целиком, — поэтому флаг
  // идёт списком селекторов по формам, а сетка — на самой колонке через `:is()`.
  const PANEL_COLUMN_PATHS = ["> div", "> .contents > div"];
  const PANEL_TRANSCRIPT = ' [data-testid="epitaxy-virtual-transcript"]';
  const PANEL_DOCK_FORM = ":has(.group\\/approval-dock)";
  // В 3.1623 (слово Элвиса 22.10: «поле ввода справа должно быть, оно вот сейчас не там») шапка легла в две
  // обёртки: «колонка > div.cds-root.contents > div > шапка». Вторая форма пути к шапке; в сетке её div
  // растворяется (`display: contents`), правила сетки ищут шапку потомком колонки, а не ребёнком.
  const PANEL_TITLE_PATHS = ["> .epitaxy-titlebar", "> .contents > div > .epitaxy-titlebar"];
  const panelTitle = prefix => PANEL_TITLE_PATHS.map(path => `${prefix}${path}`).join(", ");
  const panelFlagSelector = () => PANEL_COLUMN_PATHS
    .map(column => `.epitaxy-chat-panel:has(${panelTitle(`${column} `)}):has(${panelBody(`${column} `, PANEL_TRANSCRIPT)})${PANEL_DOCK_FORM}`)
    .join(",\n  ");
  const panelGridSelector = () =>
    `:is(${PANEL_COLUMN_PATHS.map(column => `.epitaxy-chat-panel ${column}`).join(", ")}):has(${panelTitle("")}):has(${panelBody("", PANEL_TRANSCRIPT)})${PANEL_DOCK_FORM}`;
  const WIDE_PANEL_MIN = 640;
  const WIDE_FLAG = "--myclaude-wide";
  const SIDE_VARIABLE = "--myclaude-side";
  // Правая колонка: не шире 60 % панели, умолчание — доля панели с обеими
  // границами. Нижняя граница с WF68 (#6212) не число, а ЗАМЕР строки модели
  // под полем ввода (слово Элвиса 17.09 09:41: «между Auto и Fable 5.1 ещё есть
  // место — поджать, чтобы сошлись, и поле станет поуже»): JS (applySideMin,
  // раздел 2г) кладёт её инлайн-переменной `--myclaude-side-min` на панель, CSS
  // берёт её нижней границей clamp; переменной нет (строка не нашлась, чужая
  // сборка, стенд) — SIDE_MIN, как было. Абсолютный пол SIDE_FLOOR: редактор =
  // колонка − 40 (замер 17.09: колонка 300 → редактор 260; WF66 сняла у обёртки
  // правое поле под кнопку), а поле узнаётся от narrowLimit = 200 — на полу
  // редактору остаётся 208, запас 8 на любое поле Claude (ровно 200 держалось бы
  // только на `>=`, и потерянное поле уносит с собой рейку — расширить колонку
  // мышью было бы нечем).
  const SIDE_MIN_VARIABLE = "--myclaude-side-min";
  const SIDE_MIN = 300;
  const SIDE_FLOOR = 248;
  // Пол по факту (WF183, раздел 2г sideFloorNeed): инлайн-переменная панели, её берёт clamp сетки.
  const SIDE_FLOOR_VARIABLE = "--myclaude-side-floor";
  const SIDE_DEFAULT = `clamp(var(${SIDE_MIN_VARIABLE}, ${SIDE_MIN}px), 36%, 420px)`;
  const SIDE_MAX_SHARE = 0.6;
  // Доля колонки (WF197, #9291, слово Элвиса 09.10 04:22: «Она больше не сжимается… Сделай, чтоб она
  // сжималась»): ширина, выбранная рейкой, — px, а с ним доля сетки на момент тяги. Колонка — меньшее из
  // двух: окно ýже, чем при тяге, — колонка уступает той же долей, шире — снова ширина человека. Нет
  // доли (стенд, чужая сборка) — 100 %, как до WF197.
  const SIDE_SHARE_VARIABLE = "--myclaude-side-share";
  // Зазор между группами строки модели («+ 🎤 ⌄ Auto» и «Fable 5.1 · Extra ·
  // ◑») на нижней границе: у правой группы своё поле слева (8), у кнопок —
  // свои (6), так что визуально между словами остаётся ~20.
  const SIDE_CHIN_GAP = 4;
  // #6625 (слово Элвиса 20.09: «просто сделай, чтобы они сужались»): замер строки
  // модели — нижняя граница только УМОЛЧАНИЯ; рейкой колонку можно увести до
  // SIDE_FLOOR. Ýже замера панель получает этот атрибут — группам строки снова
  // можно ужиматься (как у Claude в узком окне), а замер замирает на последнем
  // натуральном: ужатая строка мерилась бы ужатой.
  const SIDE_TIGHT_ATTRIBUTE = "data-myclaude-side-tight";
  // Строка модели — та, у которой Claude держит боковые поля переменными
  // `--cmp-chin-*` (класс `ps-[var(--cmp-chin-start)]`, замер 17.09; по этой же
  // примете «обёртка по инлайн-переменной» ниже узнаётся `--cmp-wrap-h`); её два
  // ребёнка — левая и правая группы. В широком виде группы НЕ ужимаются
  // (flex-shrink: 0 в layoutCss): нижняя граница колонки считается по их
  // ширине, и ужатая строка мерилась бы ужатой — граница застряла бы на старой,
  // когда имя модели стало длиннее. И JS, и правило CSS смотрят только в доку:
  // композер правки сообщения в ленте несёт ту же разметку, а там строке
  // ужиматься можно, как у Claude.
  const CHIN_ROW_SELECTOR = '[data-cds="ChatComposerChin"] div[class*="--cmp-chin-start"]';
  // Отступ поля ввода от краёв колонки (было 24): «отступы не должны быть такими
  // большими». Поля самой доки НЕ трогаем: их держит `sidePadding` из
  // claude.json — блок `PimpMyClaude:auto` в claude.css ставит их с !important
  // и приходит через insertCSS как USER-стиль, а пользовательский !important
  // сильнее любого авторского, даже инлайнового (замер гейта 16.09 20:58–21:10:
  // computed 24px при любом нашем правиле). Поэтому поле ввода само выезжает в
  // эти поля отрицательным margin: отступ = padding + margin = var + (12 − var)
  // = 12 при любом sidePadding (переменную `--chat-column-gutter-*` дока несёт
  // всегда — ею и задан её padding). Переменная Claude зарегистрирована без
  // наследования (`@property … inherits: false`, у поля ввода она пуста —
  // замер 21:05), поэтому дока переписывает её в свою, наследуемую
  // `--myclaude-dock-pad-*`, и уже её читает поле.
  const DOCK_PAD = 12;
  // Поля правой колонки — из той же настройки «Поля» (#9148, WF156, слово Элвиса 08.10 23:25:
  // «до сорока… у правого столбика… поля не 24, а побольше»). Значение `sidePadding` странице
  // не приходит — JS (applyDockInset) меряет его по полю ленты `.epitaxy-transcript-width`
  // (USER-стиль блока PimpMyClaude:auto ставит ему ровно sidePadding) и кладёт отступ поля
  // ввода от краёв колонки инлайн-переменной на панель: не меньше DOCK_PAD, не больше
  // DOCK_INSET_MAX; замера нет — DOCK_PAD, как до WF156.
  const DOCK_INSET_MAX = 40;
  const DOCK_INSET_VARIABLE = "--myclaude-dock-inset";
  // Ряд ленты: `.epitaxy-transcript-width` — прежние сборки; в 2.26454 его нет, ряд —
  // `[data-transcript-column-row]` (замер 08.10 WF163; без него WF156 вечно брал 12).
  const FEED_ROWS = [".epitaxy-transcript-width", "[data-transcript-column-row]"];
  // Замер — первым рядом по порядку документа (внешний ряд идёт раньше вложенного).
  const DOCK_INSET_SOURCE = FEED_ROWS.join(", ");
  const dockInsetFor = pad => {
    const value = Number(pad);
    if (!Number.isFinite(value)) return DOCK_PAD;
    return Math.round(Math.min(DOCK_INSET_MAX, Math.max(DOCK_PAD, value)));
  };
  // Три столбика (#9148, WF163, вариант 33.5 из docs/33.html): меню | лента | поле ввода —
  // между ними равные просветы, у края окна — p + 16 (#11676; p — `sidePadding`, 24 по умолчанию).
  // Половина просвета = p + 16, просвет = 2p + 32 (80 при 24): от меню (его пункты кончаются
  // за 8 до края боковой панели) до текста ленты, от текста ленты до поля ввода (40 до линии
  // колонки + 40 после неё). Поля самого ряда ленты (p, USER !important) не трогаются —
  // ряд выезжает margin'ами, его потолок Claude 816 снят: края колонок ровные.
  // Узкий широкий вид: прибавка ужимается одной долей share = (лента без прибавки − 520) /
  // прибавка, зажатой в [0, 1] — лента не уже 520, при share 0 всё как в WF156.
  const WIDE_GAP_CUSHION = 16;
  const FEED_MIN = 520;
  const MENU_ITEM_INSET = 8;
  const FEED_START_VARIABLE = "--myclaude-feed-start";
  const FEED_END_VARIABLE = "--myclaude-feed-end";
  const DOCK_INSET_START_VARIABLE = "--myclaude-dock-inset-start";
  // pad — поле ряда ленты; column — ширина левой ячейки сетки (тело ленты); menuGap — от
  // края пунктов меню до левой кромки тела ленты (null: меню нет — попап, панель свёрнута).
  const wideGapsFor = ({ pad, column, menuGap = null } = {}) => {
    const edge = dockInsetFor(pad);
    const half = edge + WIDE_GAP_CUSHION;
    const fullStart = Number.isFinite(menuGap) && menuGap >= 0 ? Math.max(0, 2 * half - menuGap - edge) : 0;
    const fullEnd = Math.max(0, half + COLUMN_PULL - TRANSCRIPT_EDGE_GAP - edge);
    const extra = fullStart + fullEnd;
    const slack = Number.isFinite(column) ? column - TRANSCRIPT_EDGE_GAP - 2 * edge - FEED_MIN : 0;
    const share = extra > 0 ? Math.min(1, Math.max(0, slack / extra)) : 1;
    return {
      edge, gap: 2 * half, share: Math.round(share * 100) / 100,
      feedStart: Math.round(fullStart * share), feedEnd: Math.round(fullEnd * share),
      // #11676 (#11633, слово Элвиса 05.11: «в упор к краю прижата эта штука»): у правого края окна поле не
      // на edge, а на half — как слева у колонки при полном просвете; отправка и кружок не жмутся к краю.
      dockStart: Math.round(edge + (half - edge) * share), dockEnd: half,
    };
  };
  // Полоса под кнопками окна. Когда панель начинается у левого края окна (боковая
  // панель свёрнута, любой попап), над лентой висят кнопки окна и «Show sidebar»,
  // и первые 32 точки ленты под ними пропадали бы. До 17.09 там стоял пустой
  // отступ; по слову Элвиса 17.09 03:25 («место пропадает попусту — заголовок
  // влево переносить») в эту полосу переезжает ШАПКА чата: JS (applyTitleSide)
  // ставит панели атрибут `data-myclaude-title="left"`, и сетка кладёт шапку в
  // левую колонку первой строкой (с родным отступом Claude под кнопки: 112 в
  // главном окне, 68 в попапе — там нет кнопки боковой панели), лента — под ней,
  // а дока — во второй строке правой колонки: первую занимает угол «Проект · чат»
  // (раздел 2ж, #7911; до WF102 дока стояла на обе строки). Главное окно с WF102
  // шапку влево не переносит (#7913). Открыта боковая панель —
  // кнопки над ней, шапка справа, как раньше. Примета `data-top-left` у шапки для
  // этого не годится: Claude держит её «true» и при открытой боковой панели.
  const TITLE_SIDE_ATTRIBUTE = "data-myclaude-title";
  // Шапка колонки над полем (#9135, слово Элвиса 08.10 ~23:00: «это же заголовок, он
  // должен быть крупный… выравнивания нету… вертикальная линия выравнивания»): название
  // чата — заголовком, а значок слева от него — левым краем по тексту и миниатюрам поля.
  // Сдвиг меряет JS (applyTitleAlign) — разметка шапки и поля у Claude своя, числом не
  // угадать; ребёнок шапки со значком получает атрибут, панель — переменную сдвига.
  // С WF179 (#9206, слово Элвиса 09.10 02:50: «мониторчик держать в самом правом углу. Заголовок чата —
  // левее и покрупнее, таким размером, как заголовок проекта „Rick“ слева»): название — первым, текстом
  // по линии текста поля, кеглем и начертанием имени проекта в углу над New (cornerLooks.side, 20/600);
  // значок Remote Control — в правый край строки шапки.
  // WF190 (слово Элвиса 09.10 03:50: шрифт чуть уменьшить — слишком большой, плохо читается и не
  // влезает): название колонки — своим кеглем 16/600, как заголовок блока; имя проекта в углу — 20.
  const CORNER_SIDE_PROJECT_FONT = 20;
  const TITLE_COLUMN_FONT = 16;
  const TITLE_SHIFT_VARIABLE = "--myclaude-title-shift";
  const TITLE_LEAD_ATTRIBUTE = "data-myclaude-title-lead";
  // С WF179 первым стоит название без ячейки значка (32) — сдвиг больше (замер 09.10: 46 при 41 у значка).
  // #10146 (Claude 2.42304): у шапки своя обёртка-панель инструментов с полем слева — сдвиг 81 (замер 17.10, окно Рика).
  const TITLE_SHIFT_MAX = 96;
  // Шапка чата (#7320, #7342): кнопка ⌄ за названием и метка подсказки над ним. Сосед — «~»,
  // как в layoutCss (#9055, WF144): открытое меню вставляет между ними сторож фокуса.
  const TITLE_MENU_SELECTOR = ".epitaxy-titlebar .group\\/lead span:has(> [data-pane-title]) ~ button";
  const TITLE_TIP_ATTRIBUTE = "data-myclaude-title-tip";
  // WF185 (слово Элвиса 09.10 03:20: многоточие не нужно, место ещё есть; 03:35 «как в Today —
  // затемняется, фейд уходит»): хвост текста, который не влез, — затуханием, как у Claude в строках
  // списка слева (замер 09.10: .dframe-fade-label[data-overflowing] — черный до 100% − 24px).
  // Ставится только при настоящем переполнении: метку TITLE_FADE_ATTRIBUTE на названии колонки
  // кладёт applyTitleAlign, угол красит себя сам (cornerFadeEnd).
  const FADE_END_MASK = "linear-gradient(to right, #000 calc(100% - 24px), transparent 100%)";
  const TITLE_FADE_ATTRIBUTE = "data-myclaude-title-fade";
  // Меню проекта из угла (WF197, регресс WF185): пока открыто меню, нажатое на имени проекта над New,
  // снятая плашка проекта стоит невидимой точно на имени в углу (сдвиг — переменными корня): к ней
  // привязана прозрачная ⋮ (#7334), и меню Claude встаёт у имени, а не у края шапки.
  const ORIGIN_OPEN_ATTRIBUTE = "data-myclaude-origin-open";
  const ORIGIN_X_VARIABLE = "--myclaude-origin-x";
  const ORIGIN_Y_VARIABLE = "--myclaude-origin-y";
  // Значок Remote Control — правым краем по правому краю поля ввода (сдвиг меряет applyTitleAlign).
  const TITLE_END_VARIABLE = "--myclaude-title-end";
  const TITLE_END_MAX = 48;
  // Место заголовка над New (раздел 2ж, #9054): отступ сверху у списка чатов — название
  // проекта и чат (с WF166 строки переключателя над ними нет); отступ считает JS (cornerSpot)
  // и пишет в CORNER_SIDE_SPACE_VARIABLE; число — запас.
  const CORNER_SIDE_SPACE = 96;
  const CORNER_SIDE_SPACE_VARIABLE = "--myclaude-side-space";
  // Место head (раздел 2ж, WF209 #9257): проект и часики в строке названия колонки, за его текстом,
  // с зазором CORNER_HEAD_GAP от текста и от значка. Отступа сверху у шапки нет (слово Элвиса 10.10
  // 03:55: шапка не растёт).
  const CORNER_HEAD_GAP = 10;
  // Уже этого «Проект 59:49» целиком не встаёт.
  const CORNER_HEAD_MIN = 64;
  // Надзаголовок — мелко и тихо (решение плана WF209: герой шапки — название чата 16/600).
  const CORNER_HEAD_FONT = 12;
  const CORNER_HEAD_OPACITY = "0.72";
  // Переключатель Claude/Code (WF166, #9164, слово Элвиса 09.10 00:05: «иконки Chat и Code
  // разместить… рядом… где Hide Sidebar, Back и вперёд, сделать их такими же маленькими… всегда
  // маленькие и в "Чате", и в Code… фоны тёмные… уберите»): в строке окна сразу за «вперёд»,
  // две кнопки по 24 с иконкой 16, как у кнопок окна; выбранная — тихая подсветка наведения
  // Claude, без дорожки и бегунка. Место — от «вперёд» по замеру (placeModeSwitch), в точках
  // боковой панели; размеры — в px, а не в rem/плотности Claude: в режиме Chat они у него другие.
  const SIDE_SWITCH_LEFT_VARIABLE = "--myclaude-switch-left";
  const SIDE_SWITCH_TOP_VARIABLE = "--myclaude-switch-top";
  const SIDE_SWITCH_HOLDER = 'aside.dframe-sidebar > .df-titlebar > :has([role="radiogroup"][aria-label="Mode"])';
  const MODE_SWITCH_SELECTOR = '.dframe-root [role="radiogroup"][aria-label="Mode"]';
  // #11618: русский Claude подписывает переключатель «Режим» (каталог claude.ai). Английские правила
  // остаются байт в байт, русские — их двойники (MODE_SWITCH_RU в RULES раздела 4, второй селектор ниже).
  const MODE_SWITCH_RU = MODE_SWITCH_SELECTOR.replace('"Mode"', '"Режим"');
  const MODE_BUTTON = 24;
  const MODE_ICON = 16;
  const MODE_RADIUS = 6;
  const TITLE_INSET_VARIABLE = "--myclaude-title-inset";
  const TITLE_INSET_MAIN = 112;
  const TITLE_INSET_POPOUT = 68;
  // Левее этой точки панели стоят кнопки окна (до ~70) и «Show sidebar» (82–110).
  const TITLEBAR_CLEARANCE_LEFT = 120;
  // Поле ввода в широком виде (WF66, #6187, #6188). Вложения — ПЕРЕД текстом, как
  // у Claude (слово Элвиса 24.09, #7336: «фотки закреплять не внизу, а наверху»;
  // с WF66 до 24.09 они стояли после текста), целиком и без своей прокрутки:
  // потолок WF62 снимается только здесь — в узком окне он спасает черновик от пяти
  // скриншотов. Текст — во всю ширину: Claude держит у обёртки редактора
  // `padding-right: var(--cmp-trail-w)` (30 px под кнопку отправки) и анимирует его,
  // отсюда `!important`; вместо правого поля — нижнее, чтобы последняя строка не
  // ушла под кнопку. Обёртка узнаётся по inline-переменной `--cmp-wrap-h`,
  // которую Claude пишет ей сам (замер 16.09). Полоса прокрутки редактора при
  // этом сама встаёт к правой кромке коробки.
  // Замер 17.09 01:30 с картинкой в поле: коробка `.bg-surface-3` → [слот вложений
  // `div.grid.grid-rows-[1fr].overflow-hidden.-mt-2` → `[data-cds-composer-attachments]`
  // → ряд плиток `flex-wrap`] и [обёртка текста `div.relative.w-full.min-w-0` → … →
  // редактор]; слот появляется ПЕРВЫМ ребёнком коробки, когда есть вложения, и
  // исчезает без них. Кнопка отправки — `absolute bottom-0 right-0` в обёртке
  // текста и с вложениями остаётся у низа текста. Плитки в широком виде мельче
  // узких (слово Элвиса 17.09 01:20: «превьюшки можно помельче»): в колонке 300
  // в ряд встают четыре.
  const EDITOR_SEND_ROOM = 28;
  const WIDE_TILE = 40;
  // Тени у поля в колонке (#9133): широкий мягкий радиус, тёмные и тихие — вдвое
  // слабее родных Claude (0 4px 6px … #0000001a), без светлого кольца.
  const COMPOSER_SOFT_SHADOW = "0 2px 10px rgba(0, 0, 0, 0.09)";
  const COMPOSER_SOFT_RING = "rgba(0, 0, 0, 0.08)";
  // Над плитками — глоток, а не 12 точек (слово Элвиса 17.09 02:05: «место надо
  // экономить, компактненько»): у Claude слот стоит с `-mt-2 pt-2` (это
  // оставляем), а вложениям WF62 давал `padding-top: 12px` под вылет крестика —
  // в широком виде слот не режет (`overflow: visible`), и хватает четырёх точек.
  const ATTACHMENTS_TOP_GAP = 4;
  // Правая колонка подтянута к тексту на 12 точек: справа у ленты своё поле
  // (sidePadding, USER-стиль), слева у доки — своё; между ними пустовало почти
  // полсотни точек, и Элвис принял их за ширину рейки («убрать тянулку огромную
  // и сэкономить место»). Шапка и дока заезжают в это поле отрицательным
  // margin, текст ленты не задет — его край на 24 левее.
  const COLUMN_PULL = 12;
  // Полоса прокрутки ленты рисуется у правой кромки её прокрутки; после подтяжки
  // колонки она упёрлась в поле ввода (слово Элвиса 17.09 02:40: «слишком сильно
  // прижал… должна идти ровно посередине»). Тело ленты (не прокрутка — оно не
  // едет) получает правое поле: правая кромка прокрутки и с ней полоса уходят
  // влево, и полоса встаёт по центру промежутка между текстом (у него свой
  // отступ 24 от кромки, sidePadding) и полем ввода (кромка колонки). Рейка
  // ширины ставится по той же полосе — они одна над другой (placeSideRail).
  // Было 14 («ровно посередине»), но Элвису так не понравилось (17.09 03:20):
  // «как была изначально, прилеплена, — чуть-чуть левее, самую малость».
  // 17.09 04:10: «ещё чуть-чуть поближе к полю» и одинаково с полосой поля ввода — 2.
  // #10110: с широкой полосой (#9845) её 10 точек лежали под подтянутой докой — не схватить. Кромка прокрутки —
  // ровно по левой кромке доки: полоса прилеплена к полю и вся видна; текст на месте (feedEnd меньше на столько же).
  const TRANSCRIPT_EDGE_GAP = COLUMN_PULL;
  // Полоса прокрутки ПОЛЯ ВВОДА стояла в 8 точках от рамки (внутреннее поле
  // коробки); по слову Элвиса 17.09 04:10 («слишком далеко от края, поджать,
  // как у ChatGPT») прокрутка редактора выезжает в это поле отрицательным
  // margin, а текст остаётся на месте — тем же числом добавлено правое поле
  // самой прокрутке. Итог: обе полосы, ленты и поля, в 2 точках от кромки.
  const EDITOR_SCROLL_PULL = 6;
  // Пустой блок Claude в конце ленты (`[data-testid="transcript-spacer"]`) НЕ
  // ТРОГАТЬ: это не отступ под затемнение, а хвост виртуальной ленты — Claude
  // пишет ему inline высоту недорисованных строк (замер 17.09 00:10: 7424 px при
  // прокрутке вверх, 48 у самого низа). Правило `height: 8px !important` (гейт
  // 21:24) ломало геометрию прокрутки — лента «телепортировалась» (слово
  // Элвиса 00:05). Снизу под последней строкой остаётся его собственный воздух.
  // Выключка по ширине (#9148, WF163) — переключаемая (#9168, WF165, слово Элвиса 09.10 00:05:
  // «сделай настройку: выравнивание влево или по ширине»). Контракт К-J1: команда
  // `text-justify` {on:"true"|"false"} строкой всем окнам, флаг — localStorage
  // ["myclaude.textJustify"]: "0" — влево, нет ключа (или иное) — по ширине; метка выключенного —
  // data-myclaude-justify="off" на <html> (правило layoutCss её обходит); status().layout.justify.
  const TEXT_JUSTIFY_KEY = "myclaude.textJustify";
  const TEXT_JUSTIFY_ATTRIBUTE = "data-myclaude-justify";
  const textJustifyOn = () => {
    try { return localStorage.getItem(TEXT_JUSTIFY_KEY) !== "0"; } catch { return true; }
  };
  const textJustifyMark = () => {
    try {
      const root = document.documentElement;
      if (textJustifyOn()) root.removeAttribute(TEXT_JUSTIFY_ATTRIBUTE);
      else if (root.getAttribute(TEXT_JUSTIFY_ATTRIBUTE) !== "off") root.setAttribute(TEXT_JUSTIFY_ATTRIBUTE, "off");
    } catch {}
  };
  const textJustifySet = value => {
    try {
      if (value) localStorage.removeItem(TEXT_JUSTIFY_KEY);
      else localStorage.setItem(TEXT_JUSTIFY_KEY, "0");
    } catch {}
    textJustifyMark();
  };
  textJustifyMark();
  on(window, "storage", event => { if (event.key === TEXT_JUSTIFY_KEY || event.key === null) textJustifyMark(); });
  track(() => { try { document.documentElement.removeAttribute(TEXT_JUSTIFY_ATTRIBUTE); } catch {} });
  const layoutCss = () => `/* PimpMyClaude · широкий вид окна (WF65) */
/* #6186: только текст подтверждённого composer, включая вложенные стили Claude.
   Чипы, кнопки и их потомки сохраняют собственный размер. */
:is(.epitaxy-prompt, [data-cds="ChatComposer"]) .ProseMirror[data-myclaude-composer-font="true"]
  :is(p, span, div, li, ul, ol, blockquote, pre, code, strong, em, a, h1, h2, h3, h4, h5, h6):not(:is([contenteditable="false"], button, svg)):not(:is([contenteditable="false"], button, svg) *) {
  font-size: inherit !important;
}
nav[aria-label="Repository and pull request controls"] {
  display: none !important;
}
/* #11618: то же в русском Claude. */
nav[aria-label="Управление репозиториями и пул-реквестами"] {
  display: none !important;
}
.epitaxy-chat-panel .scroll-fade-strip-top,
.epitaxy-chat-panel .scroll-fade-strip-bottom {
  display: none !important;
}
.epitaxy-titlebar .group\\/lead[data-pills-compact] .group-data-\\[pills-compact\\]\\/lead\\:hidden {
  display: inline-block !important;
}
/* #6736 (слово Элвиса 20.09): имя папки проекта в заголовке видно всегда и целиком —
   сжимается и уходит в многоточие заголовок чата, а не оно. У Claude подпись
   truncate и в тесном заголовке sr-only; обёртки до общего с заголовком чата
   контейнера не сжимаются. */
.epitaxy-titlebar .group\\/lead [data-testid="epitaxy-origin-label"] {
  position: static !important;
  width: auto !important;
  height: auto !important;
  margin: 0 !important;
  clip: auto !important;
  clip-path: none !important;
  overflow: visible !important;
  text-overflow: clip !important;
  white-space: nowrap !important;
  flex-shrink: 0 !important;
}
.epitaxy-titlebar .group\\/lead :is(
  button:has(> [data-testid="epitaxy-origin-label"]),
  span:has(> button > [data-testid="epitaxy-origin-label"]),
  span:has(> span > button > [data-testid="epitaxy-origin-label"])
) {
  flex-shrink: 0 !important;
}
/* #7321 (слово Элвиса 24.09: «у заголовка проекта шрифт нужно уменьшить, и всё влезет»). */
.epitaxy-titlebar .group\\/lead [data-testid="epitaxy-origin-label"] {
  font-size: 0.85em !important;
}
/* #7320 (слово Элвиса 24.09: стрелку ⌄ убрать, меню — нажатием на само название чата):
   кнопка ⌄ растянута под названием, значок её спрятан (подложка наведения осталась —
   она и подсвечивает название), название над ней клики пропускает — нажатие попадает
   в родную кнопку меню Claude, и меню встаёт под названием.
   Идёт переименование (вместо названия поле ввода) — правило не совпадает, ⌄ на месте.
   Сосед — «~», не «+» (#9055, живьём 08.10): открытое меню Base UI вставляет между
   названием и кнопкой span-сторож фокуса, «+» отпадал, кнопка сжималась до 24 px у
   правого края, и отпускание мыши над прежним местом закрывало меню («приходится держать»). */
.epitaxy-titlebar .group\\/lead div:has(> span > [data-pane-title]):has(> button) {
  position: relative;
}
.epitaxy-titlebar .group\\/lead span:has(> [data-pane-title]):has(~ button) {
  position: relative;
  z-index: 1;
  pointer-events: none;
}
.epitaxy-titlebar .group\\/lead span:has(> [data-pane-title]) ~ button {
  position: absolute !important;
  inset: 0 !important;
  width: auto !important;
  height: auto !important;
  min-width: 0 !important;
  aspect-ratio: auto !important;
  margin: 0 !important;
  cursor: pointer;
}
.epitaxy-titlebar .group\\/lead span:has(> [data-pane-title]) ~ button > :not([aria-hidden]) {
  visibility: hidden;
}
/* #7341 (слово Элвиса 24.09: «заголовок слишком большой», потом «размер как у плашки
   проекта, точно»): название чата тем же размером, что имя в плашке. */
.epitaxy-titlebar .group\\/lead [data-pane-title] {
  font-size: calc(var(--cds-font-size-footnote, 13px) * 0.85) !important;
}
/* #7342: подсказка над названием — одно название в одну строку (текст меняет
   titleTipOnMutation, раздел 9); переносится, только если не влезает в окно. */
[${TITLE_TIP_ATTRIBUTE}] {
  max-width: calc(100vw - 16px) !important;
  text-wrap: wrap !important;
}
/* #7335: значок папки в плашке проекта не нужен — только имя. */
.epitaxy-titlebar .group\\/lead :has(> [data-testid="epitaxy-origin-label"]) > span:has(> [data-cds="Icon"]) {
  display: none !important;
}
/* #7334 (слово Элвиса 24.09: «три точки должны уехать и заменить PimpMyClaude, место
   должно стать»): кнопка ⋮ уходит из правого края и ложится прозрачной поверх плашки
   проекта (якорь CSS, у каждой шапки свой — anchor-scope), нажатие на плашку открывает
   родное меню ⋮. Своё меню плашки (Show in Finder, Change folder…) — правым кликом
   (onOriginMenu, раздел 16). Плашки нет — ⋮ стоит где стояла.
   Освободившееся место Claude сам отдал бы значкам Terminal / Changes / Browser, а
   название ужал бы до 100 точек (его замер шапки: значки видны, пока названию
   хватает 100). Поэтому правая группа выпирает за край шапки на всю её ширину
   (padding-right 100% и margin-right −100%: на месте ничего не сдвигается, а замер
   видит нехватку места) — значки уходят в меню ⋮, всё место — названию; вылет
   срезан overflow-x: clip шапки. Выпирает только группа с ⋮ (WF144): новый div в шапке
   сотни процентов отступа не получает. */
.epitaxy-titlebar {
  anchor-scope: --myclaude-origin;
}
.epitaxy-titlebar .group\\/lead :has(> [data-testid="epitaxy-origin-label"]) {
  anchor-name: --myclaude-origin;
}
.epitaxy-titlebar:has(> .group\\/lead [data-testid="epitaxy-origin-label"]) {
  overflow-x: clip;
}
.epitaxy-titlebar:has(> .group\\/lead [data-testid="epitaxy-origin-label"]) > .group\\/lead ~ div:has(> [aria-haspopup="menu"]) {
  position: static !important;
  padding-left: 0 !important;
  padding-right: 100% !important;
  margin-right: -100% !important;
}
.epitaxy-titlebar:has(> .group\\/lead [data-testid="epitaxy-origin-label"]) > .group\\/lead ~ div > :nth-last-child(1 of [aria-haspopup="menu"]) {
  position: absolute !important;
  position-anchor: --myclaude-origin;
  inset: anchor(top) anchor(right) anchor(bottom) anchor(left) !important;
  z-index: 2;
  width: auto !important;
  height: auto !important;
  min-width: 0 !important;
  aspect-ratio: auto !important;
  margin: 0 !important;
}
/* Прозрачна целиком, с подложкой наведения: в тёмной теме она заливала плашку
   сплошным цветом (слово Элвиса 24.09: «красноту убери, сбивает с толку»). */
.epitaxy-titlebar:has(> .group\\/lead [data-testid="epitaxy-origin-label"]) > .group\\/lead ~ div > :nth-last-child(1 of [aria-haspopup="menu"]) > * {
  visibility: hidden;
}
/* #7911 (раздел 2ж): угол «Проект · чат» виден — имя проекта в шапке прозрачно
   (нажатия на месте); угол наехал на название чата в шапке — прозрачно и оно. */
html[data-myclaude-corner] .epitaxy-titlebar .group\\/lead [data-testid="epitaxy-origin-label"],
html[data-myclaude-corner="cover"] .epitaxy-titlebar .group\\/lead span:has(> [data-pane-title]),
html[data-myclaude-corner="row"] .epitaxy-titlebar .group\\/lead span:has(> [data-pane-title]) {
  opacity: 0 !important;
}
/* WF185 (#9206, слово Элвиса 09.10 03:20: многоточие не нужно, справа ещё много места): в шапке
   колонки (группу названия метит applyTitleAlign) место между названием и значком держала невидимая
   плашка проекта — имя проекта уже в углу, плашка прозрачна. Она уходит, название — до значка. */
html[data-myclaude-corner] .epitaxy-titlebar > .group\\/lead[${TITLE_LEAD_ATTRIBUTE}] span:has(> span > button > [data-testid="epitaxy-origin-label"]) {
  display: none !important;
}
/* WF197 (регресс WF185: с плашкой ушли меню ⋮ проекта — Terminal / Changes / Browser — и её «Show in
   Finder / Change folder»): на время меню, открытого с имени проекта в углу, плашка снова в раскладке —
   вне потока, невидимая и без нажатий, ровно на имени (cornerOriginOpen). */
html[data-myclaude-corner][${ORIGIN_OPEN_ATTRIBUTE}] .epitaxy-titlebar > .group\\/lead[${TITLE_LEAD_ATTRIBUTE}] span:has(> span > button > [data-testid="epitaxy-origin-label"]) {
  display: flex !important;
  position: absolute !important;
  left: var(${ORIGIN_X_VARIABLE}, 0px) !important;
  top: var(${ORIGIN_Y_VARIABLE}, 0px) !important;
  opacity: 0 !important;
  pointer-events: none !important;
}
/* #9054 (раздел 2ж): заголовок над New — место ему отступом сверху у списка чатов. */
html[data-myclaude-corner="side"] [data-testid="sidebar"] {
  padding-top: var(${CORNER_SIDE_SPACE_VARIABLE}, ${CORNER_SIDE_SPACE}px) !important;
}
/* WF166 (#9164): переключатель Claude/Code — в строке окна сразу за «вперёд» (место меряет
   placeModeSwitch; запасные числа — замер режима Code: «вперёд» кончается на 156, кнопки с 12). */
.dframe-root:not([data-collapsed]) ${SIDE_SWITCH_HOLDER.replace('"Mode"', '"Режим"')},
.dframe-root:not([data-collapsed]) ${SIDE_SWITCH_HOLDER} {
  position: absolute !important;
  left: var(${SIDE_SWITCH_LEFT_VARIABLE}, 160px) !important;
  top: var(${SIDE_SWITCH_TOP_VARIABLE}, 12px) !important;
  margin: 0 !important;
  padding: 0 !important;
  z-index: 3;
}
/* #8225 (Claude 2.16120): у плашки проекта подложка ::before — без имени она пустым
   прямоугольником стояла рядом с названием чата. */
html[data-myclaude-corner] .epitaxy-titlebar .group\\/lead button:has(> [data-testid="epitaxy-origin-label"])::before {
  opacity: 0 !important;
}
/* #8225: новые кнопки шапки попапа «в главное окно» и «поверх окон» стоят у правого края,
   под углом «Проект · чат», и он срезал им верх — в узком попапе они прячутся. В широком
   шапка слева (data-myclaude-title="left"), кнопки на месте. */
html:is([data-myclaude-corner="on"], [data-myclaude-corner="cover"]) .epitaxy-chat-panel:not([${TITLE_SIDE_ATTRIBUTE}="left"]) .epitaxy-titlebar :is(button[aria-label="Open in main window"], button[aria-label="Keep window on top"], button[aria-label="Открыть в главном окне"], button[aria-label="Закрепить окно поверх других"]) {
  display: none !important;
}
/* #7913 (раздел 2ж): главное окно в узком виде без шапки — сжата до нуля и
   невидима, узел жив (волокно чата, подпись проекта для угла). */
.epitaxy-chat-panel[data-myclaude-headless] .epitaxy-titlebar {
  height: 0 !important;
  min-height: 0 !important;
  padding-top: 0 !important;
  padding-bottom: 0 !important;
  overflow: hidden !important;
  visibility: hidden !important;
}
/* 3.1623: шапки нет — и заход ленты под неё (--epitaxy-behind-title-bar) не нужен, лента от верха окна. */
.epitaxy-chat-panel[data-myclaude-headless] [data-epitaxy-behind-title-bar="body"] {
  --epitaxy-behind-title-bar: 0px !important;
}
/* #9148 (33.5, WF163): абзацы ленты и поля ввода — по ширине с переносами, в обоих видах;
   заголовки, списки, таблицы, код — влево (это не абзацы p или абзацы внутри них).
   Язык переносов — lang="ru" на панели (applyTextLang). Красивый перенос строк (pretty) не ставим — он ломает переносы.
   #9168 (WF165): выключка переключаемая — команда text-justify; выключена — атрибут
   ${TEXT_JUSTIFY_ATTRIBUTE}="off" на <html>, правило не совпадает: влево, как у Claude, без переносов. */
html:not([${TEXT_JUSTIFY_ATTRIBUTE}="off"]) .epitaxy-chat-panel [data-cds="Prose"] p:not(:is(li, td, th, pre) p) {
  text-align: justify;
  -webkit-hyphens: auto;
  hyphens: auto;
  hyphenate-limit-chars: 6 2 2;
}
/* Поле ввода — влево и с воздухом между абзацами (слово Элвиса 09.10 ~02:10, диктовкой в поле Рика:
   «Эти абзацы поближе, между абзацами расстояние чуть побольше, чтоб было понятно, что это за абзац.
   Сливается»): в колонке поля шириной ~200 px выключка по ширине давала дыры между словами. */
:is(.epitaxy-prompt, [data-cds="ChatComposer"]) .ProseMirror p + p { margin-top: 0.6em !important; }
/* #8132 (29.09, слово Элвиса: «нижнее — без скруглений — это неправильно… нижнее
   поле ввода должно остаться, как раньше было»): в узком виде поле снова своё,
   Claude — с рамкой, скруглением и заливкой темы; правила #8098 (поле цветом
   ленты, линия по верху доки) живут только в широком виде (@container ниже). */
@container tile-slot (min-width: ${WIDE_PANEL_MIN}px) {
  ${panelFlagSelector()} {
    ${WIDE_FLAG}: 1;
    ${SIDE_VARIABLE}: ${SIDE_DEFAULT};
  }
  ${panelGridSelector()} {
    display: grid !important;
    grid-template-columns: minmax(0, 1fr) clamp(var(${SIDE_FLOOR_VARIABLE}, ${SIDE_FLOOR}px), min(var(${SIDE_VARIABLE}), var(${SIDE_SHARE_VARIABLE}, 100%)), ${SIDE_MAX_SHARE * 100}%);
    grid-template-rows: auto minmax(0, 1fr);
    ${SESSION_RAIL_VARIABLES.map(name => `${name}: 0px !important;`).join("\n    ")}
    /* #10146 (Claude 2.42304, слово Элвиса 17.10: «мне надо, чтобы справа было»): сцена и полоса ленты —
       прозрачны для сетки, ячейки снова шапка, тело, дока; панель сессии Claude (Environment, Context…) и её
       кнопка в шапке в широком виде спрятаны — на её месте колонка с полем ввода (#9994: «там поле ввода
       своё хочу видеть»). В старых сборках обёртки и так div.contents, панели нет — правила ничего не меняют. */
    & > div:has(> div > .epitaxy-chat-panel-body),
    & > div > div:has(> .epitaxy-chat-panel-body),
    & > .contents > div:has(> .epitaxy-titlebar) {
      display: contents !important;
    }
    /* 3.1623: полоса уведомлений Claude над лентой (data-epitaxy-behind-title-bar="banners") — над лентой
       в её колонке, а не лишней ячейкой сетки. */
    & > [data-epitaxy-behind-title-bar="banners"] {
      grid-column: 1;
      grid-row: 1;
      align-self: start;
      min-width: 0;
      z-index: 1;
    }
    & [data-epitaxy-rail-column],
    & .epitaxy-titlebar button[aria-label$="session rail"],
    & .epitaxy-titlebar button[aria-label$="панель сессий"] {
      display: none !important;
    }
    & .epitaxy-titlebar {
      grid-column: 2;
      grid-row: 1;
      min-width: 0;
      margin-left: -${COLUMN_PULL}px !important;
    }
    /* 3.1623 (слово Элвиса 22.10: «заголовок должен быть слева, не справа»): при свёрнутой боковой панели
       Claude держит в шапке пустую распорку под кнопки окна ([data-lined-row-corner-clearance], 108 px), хотя
       шапку сетка кладёт сама — над полем или со своим отступом слева; название уезжало вправо на её ширину.
       Черта под шапкой — новая линия панели инструментов (::after с --cds-toolbar-line): линий нет (WF128). */
    & .epitaxy-titlebar [data-lined-row-corner-clearance] {
      display: none !important;
    }
    & .epitaxy-titlebar [data-cds="Toolbar"]::after {
      border-bottom-width: 0 !important;
    }
    /* 3.1623: под шапкой — подложка панели инструментов (пустой div, фон страницы 85 % и размытие 12) для ленты,
       заходящей под шапку; в сетке лента под шапку не заходит — подложка рисовала тёмную плашку над полем. */
    & .epitaxy-titlebar [data-cds="Toolbar"] > div:empty {
      background: transparent !important;
      -webkit-backdrop-filter: none !important;
      backdrop-filter: none !important;
    }
    /* 3.1623: лента заходит под шапку (отступ −45 и поле 45 у прокрутки по --epitaxy-behind-title-bar), а в
       сетке шапки над лентой нет — прокрутка начиналась выше окна, затухания угла и верхнего края уходили за
       край, текст светил сквозь кнопки окна. Лента — от своего верха, как до 3.1623. */
    & [data-epitaxy-behind-title-bar="body"] {
      --epitaxy-behind-title-bar: 0px !important;
    }
    ${panelBody("& ")} {
      grid-column: 1;
      grid-row: 1 / 3;
      min-width: 0;
      min-height: 0;
      padding-right: ${TRANSCRIPT_EDGE_GAP}px;
    }
    .epitaxy-chat-panel[${TITLE_SIDE_ATTRIBUTE}="left"] & .epitaxy-titlebar {
      grid-column: 1;
      margin-left: var(${TITLE_INSET_VARIABLE}, ${TITLE_INSET_MAIN}px) !important;
    }
    ${panelBody(`.epitaxy-chat-panel[${TITLE_SIDE_ATTRIBUTE}="left"] & `)} {
      grid-row: 2 / 3;
    }
    /* #9135: шапка над полем — название чата заголовком, значок по линии текста поля. */
    .epitaxy-chat-panel:not([${TITLE_SIDE_ATTRIBUTE}="left"]) & .epitaxy-titlebar [data-pane-title] {
      font-size: ${TITLE_COLUMN_FONT}px !important;
      font-weight: 600 !important;
      line-height: 1.25 !important;
      letter-spacing: -0.01em;
    }
    .epitaxy-chat-panel:not([${TITLE_SIDE_ATTRIBUTE}="left"]) & .epitaxy-titlebar > [${TITLE_LEAD_ATTRIBUTE}] {
      margin-inline-start: var(${TITLE_SHIFT_VARIABLE}, 0px) !important;
    }
    /* WF179 (#9206): группа названия — во всю строку шапки, значок Remote Control (его ячейка) —
       последним, к правому краю; название — первым (его текст applyTitleAlign ставит по линии поля). */
    .epitaxy-chat-panel:not([${TITLE_SIDE_ATTRIBUTE}="left"]) & .epitaxy-titlebar > .group\\/lead {
      flex: 1 1 auto;
    }
    .epitaxy-chat-panel:not([${TITLE_SIDE_ATTRIBUTE}="left"]) & .epitaxy-titlebar > .group\\/lead > :has(> [data-testid="epitaxy-origin-gutter"]) {
      order: 2;
      margin-inline-start: auto !important;
      margin-inline-end: var(${TITLE_END_VARIABLE}, 0px) !important;
      justify-content: flex-end;
    }
    /* WF185 (#9206): не влезло — хвост названия затухает (TITLE_FADE_ATTRIBUTE), а не многоточие. */
    .epitaxy-chat-panel:not([${TITLE_SIDE_ATTRIBUTE}="left"]) & .epitaxy-titlebar [data-pane-title] {
      text-overflow: clip !important;
    }
    .epitaxy-chat-panel:not([${TITLE_SIDE_ATTRIBUTE}="left"]) & .epitaxy-titlebar [data-pane-title][${TITLE_FADE_ATTRIBUTE}] {
      -webkit-mask-image: ${FADE_END_MASK};
      mask-image: ${FADE_END_MASK};
    }
    /* WF209 (#9257, раздел 2ж): отступ шапки сверху под строку «проект + часики» снят (слово Элвиса
       10.10 03:55: шапка не растёт). content-box остался от него: без кадра стенда не сверено, меняет ли
       он высоту шапки (у Claude она задана, 2rem) — снимать вместе с таким кадром. */
    .epitaxy-chat-panel:not([${TITLE_SIDE_ATTRIBUTE}="left"]) & .epitaxy-titlebar {
      box-sizing: content-box !important;
    }
    /* #8225 (Claude 2.16120, 30.09): дока лежит в колонке-обёртке
       [data-epitaxy-chat-column] и в попапе — ячейкой сетки стала обёртка: в попапе
       она легла в первую строку (поле уехало наверх), а её поля sidePadding
       (USER !important, не перебить) сдвинули линию доки на 10 от линии шапки.
       Обёртка растворяется — ячейкой снова служит сама дока. */
    & [data-epitaxy-chat-column]:has(> .group\\/approval-dock) {
      display: contents !important;
    }
    /* #9127: в колонке поле прозрачное насквозь — размытие маски дока (живой фон, WF139) рисовало плашку. */
    & .group\\/approval-dock * {
      -webkit-backdrop-filter: none !important;
      backdrop-filter: none !important;
    }
    & .group\\/approval-dock {
      -webkit-backdrop-filter: none !important;
      backdrop-filter: none !important;
      grid-column: 2;
      grid-row: 2;
      min-width: 0;
      min-height: 0;
      margin-left: -${COLUMN_PULL}px;
      width: calc(100% + ${COLUMN_PULL}px) !important;
      /* #8225: без обёртки полей у доки нет — поле ввода отступает на все 12. */
      --myclaude-dock-pad-start: var(--chat-column-gutter-start, 0px);
      --myclaude-dock-pad-end: var(--chat-column-gutter-end, 0px);
      /* #9133: тени и кольца Claude у поля, кнопок нижней строки и «Вниз» — его же
         переменными, вдвое тише и тёмные, без светлого ореола. */
      --cds-ring-color: ${COMPOSER_SOFT_RING};
      --cds-shadow-sm: ${COMPOSER_SOFT_SHADOW};
      --cds-shadow-md: ${COMPOSER_SOFT_SHADOW};
      --cds-shadow-lg: ${COMPOSER_SOFT_SHADOW};
      --cds-shadow-popover: ${COMPOSER_SOFT_SHADOW};
      background: transparent !important;
      /* #8166: в главном окне дока лежит в своей колонке-обёртке (flex-col, не
         contents) — без flex она высотой в поле, и строка модели уезжала вверх. */
      flex: 1 1 auto;
    }
    & .group\\/approval-dock [aria-label="Scroll to bottom"],
    & .group\\/approval-dock [aria-label="Прокрутить вниз"] {
      left: auto;
      top: auto;
      right: calc(100% + ${DOCK_PAD}px);
      bottom: ${DOCK_PAD}px;
    }
    /* #9377 (раздел 12х): «непрочитанные N» — слева от стрелки «вниз», по её середине. Стрелка 36 px
       у Claude ещё сдвинута на полширины влево и поднята своим отступом 20 (замер 10.10: её правый
       край — в 30 от доки, низ — в 32 от низа доки); между ними зазор 8. */
    & .group\\/approval-dock #${READ_NEXT_ID} {
      right: calc(100% + ${DOCK_PAD + 18 + 36 + 8}px);
      bottom: ${DOCK_PAD + 20 + 5}px;
    }
    .epitaxy-chat-panel:not([${SIDE_TIGHT_ATTRIBUTE}]) & .group\\/approval-dock ${CHIN_ROW_SELECTOR} > * {
      flex-shrink: 0;
    }
    & .epitaxy-prompt {
      display: flex;
      flex-direction: column;
      flex: 1 1 auto;
      min-height: 0;
      width: auto;
      margin-inline: calc(var(${DOCK_INSET_START_VARIABLE}, var(${DOCK_INSET_VARIABLE}, ${DOCK_PAD}px)) - var(--myclaude-dock-pad-start)) calc(var(${DOCK_INSET_VARIABLE}, ${DOCK_PAD}px) - var(--myclaude-dock-pad-end));
    }
    /* #9148 (33.5): ряды ленты — между просветами (wideGapsFor), потолок Claude снят. */
    ${FEED_ROWS.map(row => panelBody("& ", ` ${row}:not([data-transcript-column-row] *)`)).join(", ")} {
      max-width: none !important;
      margin-left: var(${FEED_START_VARIABLE}, 0px) !important;
      margin-right: var(${FEED_END_VARIABLE}, 0px) !important;
    }
    & [data-cds="ChatComposer"] {
      flex: 1 1 auto;
      min-height: 0;
    }
    /* #7974 (WF103): само поле — цветом ленты (прозрачно поверх фона окна, как
       лента; колонка-дока прозрачна правилом выше).
       #8098 (WF106): рамки вокруг поля нет — лента и поле делятся одной
       вертикальной линией по левой кромке колонки (шапка колонки и дока).
       Рамку прячет ЦВЕТ: ширина, стиль и тень остаются — по ним editorFrame
       находит коробку поля, а с ней ряд номеров воркфлоу (#6890). */
    & [data-cds="ChatComposer"] > div[class*="bg-surface"] {
      /* #9127 (WF142): прозрачно и с живым фоном — стекло WF139 Элвис снял («поле ввода было прозрачно»). */
      background: transparent !important;
      border-width: 1px !important;
      border-style: solid !important;
      border-color: transparent !important;
      box-shadow: 0 0 0 0 transparent !important;
    }
    & .group\\/approval-dock,
    .epitaxy-chat-panel:not([${TITLE_SIDE_ATTRIBUTE}="left"]) & .epitaxy-titlebar {
      /* #11216 (слово Элвиса 30.10 17:20: «разделяющая полоса… здесь вообще не нужна… лёгкий интерфейс
         одноцветный. Убери её»): линии между лентой и колонкой поля нет во всех видах — раньше её гасил
         только живой фон (WF128), без него у шапки и доки она шла с разных кромок и выходила кривой. */
      box-shadow: none !important;
    }
    & [data-cds="ChatComposer"] div:has(.ProseMirror):not(:has(> .ProseMirror)) {
      display: flex;
      flex-direction: column;
      flex: 1 1 auto;
      min-height: 0;
    }
    & [data-cds="ChatComposer"] div:has(> .ProseMirror) {
      flex: 1 1 auto;
      min-height: 0;
      max-height: none !important;
      margin-right: -${EDITOR_SCROLL_PULL}px;
      width: calc(100% + ${EDITOR_SCROLL_PULL}px) !important;
      padding-right: ${EDITOR_SCROLL_PULL}px !important;
    }
    & .group\\/approval-dock [data-cds-composer-attachments] [data-cds-attachment] {
      width: ${composerTileSide(WIDE_TILE)} !important;
      height: ${composerTileSide(WIDE_TILE)} !important;
      min-width: 0 !important;
      min-height: 0 !important;
      /* #9133 (слово Элвиса 08.10 ~23:00: «тень… должна быть, но менее выраженная… сильно
         яркие»): у миниатюр — одна мягкая тёмная тень вдвое слабее, без светлого кольца;
         кольца и тени самого Claude внутри плитки (ring, shadow-card-ring) погашены. */
      border-color: transparent !important;
      box-shadow: ${COMPOSER_SOFT_SHADOW} !important;
    }
    & .group\\/approval-dock [data-cds-composer-attachments] [data-cds-attachment] *,
    & .group\\/approval-dock [data-cds-composer-attachments] [data-cds-attachment] *::before,
    & .group\\/approval-dock [data-cds-composer-attachments] [data-cds-attachment] *::after {
      box-shadow: none !important;
    }
    & [data-cds="ChatComposer"] > div > div:has(> [data-cds-composer-attachments]) {
      flex: 0 0 auto;
      overflow: visible !important;
    }
    & [data-cds="ChatComposer"] [data-cds-composer-attachments] {
      max-height: none !important;
      overflow: visible !important;
      padding-top: ${ATTACHMENTS_TOP_GAP}px !important;
      padding-bottom: 0 !important;
    }
    & [data-cds="ChatComposer"] div[style*="--cmp-wrap-h"] {
      padding-right: 0 !important;
      padding-bottom: ${EDITOR_SEND_ROOM}px !important;
    }
  }
}
/* #11203 (WF301, слово Элвиса 30.10: «слишком скриншоты большие… Такие же маленькие сделай… больше скриншотов
   поместится»): плитка чата ýже широкого вида (узкая колонка рядом с панелью материалов, терминалом, узкое окно,
   попап) — плитки поля те же мелкие, что в колонке широкого вида (WIDE_TILE). Порог — по плитке чата, не по окну:
   @media узкого окна в attachmentsCss окно 2518 pt с доком не ловит. Таблица стоит после attachmentsSheet —
   спор двух !important (56 узкого окна) решает порядок. */
@container tile-slot (max-width: ${WIDE_PANEL_MIN - 1}px) {
  [data-cds-composer-attachments] [data-cds-attachment] {
    width: ${composerTileSide(WIDE_TILE)} !important;
    height: ${composerTileSide(WIDE_TILE)} !important;
    min-width: 0 !important;
    min-height: 0 !important;
  }
}
`;

  // Оформление (слой look, WF83) — пятая таблица. Цвета берёт от темы окна, а у
  // окна без темы — от акцента Claude; формат цвета любой (hex, hsl()), поэтому
  // прозрачность и соседние тона считает сам браузер: color-mix и hsl(from …).
  // WF128 (#9044, слово Элвиса 08.10: «на весь клауд… полная подложка»): живой
  // фон — одна подложка на всё окно. Замер 08.10 (1.10.1): у `.dframe-root` фон
  // темы, над ним `main.dframe-content` и `.dframe-content-inner` того же цвета,
  // лента лежит в `.epitaxy-chat-panel` на карточке `rounded-card bg-surface-2`
  // (z -1, обводка 1px). Поэтому подложка — два псевдоэлемента `.dframe-root`
  // (isolate, z -1: над фоном окна, под всем остальным); `main` и его обёртка
  // прозрачны, карточка ленты и левая панель — полупрозрачные, без обводок и
  // линий. В попапе «Open in new window» `.dframe-root` нет — там подложка, как
  // прежде, у самой панели ленты. Ни одного узла в разметку React.
  const LOOK_LAYER = ":is(.dframe-root, .epitaxy-chat-panel:not(.dframe-root *))";
  const LOOK_FEED = ".epitaxy-transcript-typography";
  // Окно скрыто — переливание стоит (К3): атрибут на <html> ставит visibilitychange.
  const LOOK_STILL_ATTRIBUTE = "data-myclaude-look-still";
  const lookTint = (color, share) => `color-mix(in oklab, ${color} ${share}%, transparent)`;
  // Движение живого фона — один источник для CSS-кадров и для Web Animations («Уменьшить движение»).
  // Слой: период, сдвиг начала и три опорных положения [сдвиг X %, сдвиг Y %, масштаб, поворот °,
  // прозрачность]; между опорными — плавно, как ease-in-out.
  // WF241 (заметка Рика 11.10: «Мак греется — WindowServer 39 % и Claude 34 % при живой теме»): плавные
  // кадры заставляли композитор собирать ВСЁ окно на каждый кадр экрана (60–120 раз в секунду) — оба
  // слоя лежат под всем окном, над ними лента, панели, размытие под полем ввода. Теперь положение слоя
  // меняется LOOK_AURORA_FPS раз в секунду: каждый переход разбит на LOOK_AURORA_PARTS отрезков по
  // кривой ease-in-out, внутри отрезка — steps(). Шаг — около точки (пятна мягкие, шириной в сотни
  // точек): глазу плавно, а кадров в 2–4 раза меньше. Замер на стенде — в docs/stand-wf241.
  // Ступеньки 10 раз в секунду (WF128) Элвис видел рывками (#9134) — здесь втрое чаще и по плавной
  // кривой; LOOK_AURORA_FPS = 0 возвращает прежние плавные кадры одной строкой.
  // Отрезков 15: у обоих слоёв (переходы 11 и 14,5 с) в отрезке выходит целое число ступеней ровно по
  // 1/30 с — слои шагают в одни и те же моменты, и кадр окна собирается 30 раз в секунду, а не 44
  // (при 12 отрезках ступени слоёв расходились, замер стенда).
  const LOOK_AURORA_FPS = 30;
  const LOOK_AURORA_PARTS = 15;
  const LOOK_AURORA = [
    { name: "myclaude-aurora-a", pseudo: "::before", ms: 22000, delay: 0, keys: [[-10, -6, 1, -10, 0.45], [8, 9, 1.22, 12, 1], [-4, 11, 1.1, -5, 0.6]] },
    { name: "myclaude-aurora-b", pseudo: "::after", ms: 29000, delay: -11000, keys: [[9, 6, 1.12, 8, 1], [-10, -8, 1, -13, 0.4], [4, -11, 1.24, 6, 0.95]] },
  ];
  // Вдвое тише и без поворота — «низкое зарево» (#9683, ниже). Переходы 17 и 22,5 с: в отрезке целое число
  // ступеней по 1/30 с (34 и 45), слои шагают в одни моменты, как у LOOK_AURORA.
  const LOOK_AURORA_CALM = [
    { name: "myclaude-aurora-calm-a", pseudo: "::before", ms: 34000, delay: 0, keys: [[-4, 1, 1, 0, 0.7], [3, -1, 1.06, 0, 1], [-1, 1.5, 1.03, 0, 0.8]] },
    { name: "myclaude-aurora-calm-b", pseudo: "::after", ms: 45000, delay: -17000, keys: [[4, 1, 1.05, 0, 1], [-3, -1, 1, 0, 0.65], [1, -1.5, 1.07, 0, 0.95]] },
  ];
  // Свой рисунок пятен у темы (#9683, лист docs/43.html; слово Элвиса 11.10.2026 01:40: «сиреневая слишком
  // переход яркий, вот этот шевелящийся, да и фиолетовый тоже. Градиентность надо уменьшить… понижнее переход
  // сделать»; «красный… хотелось бы более интимный»). Ручки — как на стенде листа (docs/stand-wf243/variants.js):
  // k — множитель долей цвета, weights — доля каждого из четырёх пятен, rays:false — без лучей, hue — соседние тона
  // «Как у темы» (вместо −56°/+48°), tones — свои тона при «Как у темы», shapes — эллипсы пятен, calm — LOOK_AURORA_CALM.
  // ★1.4 и ★2.4 «Низкое зарево»: ровная дымка в две трети силы и свет полосой у нижнего края, один тон, тише.
  // ★3.3 «Винная» — ровная дымка одного тона. Темы без записи и «Картинка» — рисунок прежний.
  const LOOK_HAZE = ["ellipse 84% 70% at 30% 34%", "ellipse 78% 66% at 72% 68%", "ellipse 74% 72% at 66% 30%", "ellipse 82% 62% at 34% 74%"];
  const LOOK_LOW_GLOW = { k: 0.7, rays: false, hue: [16, 16], weights: [0.7, 0.7, 2, 1.8], calm: true,
    shapes: [LOOK_HAZE[0], LOOK_HAZE[1], "ellipse 46% 19% at 54% 86%", "ellipse 34% 15% at 26% 88%"] };
  const LOOK_THEME_GLOW = {
    lilac: LOOK_LOW_GLOW,
    violet: LOOK_LOW_GLOW,
    wine: { k: 0.55, rays: false, hue: [16, 16], tones: ["#e2647c", "#d9577a", "#e8707a", "#c96a86"], shapes: LOOK_HAZE },
  };
  const lookLayers = glow => (glow?.calm ? LOOK_AURORA_CALM : LOOK_AURORA);
  // Значение кривой ease-in-out — cubic-bezier(.42, 0, .58, 1) — в доле времени t.
  const lookEase = t => {
    let low = 0;
    let high = 1;
    for (let step = 0; step < 24; step += 1) {
      const mid = (low + high) / 2;
      if (3 * (1 - mid) * (1 - mid) * mid * 0.42 + 3 * (1 - mid) * mid * mid * 0.58 + mid * mid * mid < t) low = mid; else high = mid;
    }
    const at = (low + high) / 2;
    return 3 * (1 - at) * at * at + at * at * at;
  };
  // Кадры слоя: [{offset, transform, opacity, easing}] — easing действует до следующего кадра.
  const lookAuroraFrames = (layer, fps = LOOK_AURORA_FPS, parts = LOOK_AURORA_PARTS) => {
    const round = value => Math.round(value * 1000) / 1000;
    const frame = (offset, [x, y, scale, turn, opacity], easing) => ({
      offset: Math.round(offset * 1e5) / 1e5, transform: `translate3d(${round(x)}%, ${round(y)}%, 0) scale(${round(scale)}) rotate(${round(turn)}deg)`, opacity: round(opacity), easing,
    });
    const spans = layer.keys.length - 1;
    if (!(fps > 0)) return layer.keys.map((key, index) => frame(index / spans, key, "ease-in-out"));
    const easing = `steps(${Math.max(1, Math.round(layer.ms / spans / parts / 1000 * fps))}, end)`;
    const frames = [];
    for (let span = 0; span < spans; span += 1) {
      for (let part = 0; part < parts; part += 1) {
        const share = lookEase(part / parts);
        frames.push(frame((span + part / parts) / spans, layer.keys[span].map((from, index) => from + (layer.keys[span + 1][index] - from) * share), easing));
      }
    }
    frames.push(frame(1, layer.keys[spans], easing));
    return frames;
  };
  // Доля цвета панели у выезжающего списка чатов живого вида (остальное — размытая лента под ним).
  const LOOK_PEEK_SHARE = 94;
  const LOOK_SPOTS = ["ellipse 52% 42% at 26% 30%", "ellipse 46% 40% at 76% 70%", "ellipse 44% 48% at 68% 24%", "ellipse 50% 38% at 32% 78%"];
  // glow — рисунок темы окна из LOOK_THEME_GLOW (#9683) или null.
  const lookCss = (look, colors, glow = null) => {
    const { accent, muted, dark } = colors;
    const rules = ["/* PimpMyClaude · оформление */"];
    if (look.aurora) {
      // Живой фон (#7178, WF128 #9045): большие мягкие пятна цветами палитры —
      // акцент, его соседние тона и приглушённый — и веер тихих лучей из-за
      // края окна. «Переливание магическое, как из будущего», но медленно и не
      // ярче прежнего: доли цвета прежние (38/32/30/24), лучи — 9 и 7. Двигаются
      // только transform и opacity, плавно (ease-in-out, без ступенек — #9134, «резко
      // дёрнулось»): всё на композиторе, без перерисовки; цвета перетекают, потому что
      // слои с разными тонами гаснут и разгораются навстречу друг другу. Периоды
      // 44 и 58 с на круг — узор не повторяется. Слой шире окна на 22 % с каждой
      // стороны: сдвиг и поворот не открывают углы.
      // Кадры — lookAuroraFrames: положение меняется LOOK_AURORA_FPS раз в секунду по кривой
      // ease-in-out (WF241), а не на каждый кадр экрана. Замер 08.10 (M1, GPU-процесс Claude):
      // без анимации 1,7%, плавно 12%, шагом 10 раз в секунду 4%.
      const share = dark ? 1 : 0.6;
      const motion = lookMotion(look);
      // Рисунок темы — только у пятен: «Картинка» одна на все темы.
      const own = motion === "image" ? null : glow;
      const weights = own?.weights ?? [1, 1, 1, 1];
      const spot = (shape, color, alpha, index) =>
        `radial-gradient(${shape}, ${lookTint(color, Math.round(alpha * share * (own?.k ?? 1) * weights[index]))}, transparent 70%)`;
      // Тона пятен — от схемы (WF146): a/b/c/d; «Как у темы» — акцент, его
      // холодный и тёплый соседи и приглушённый, как до WF146.
      const tones = lookScheme(look.scheme).tones ?? own?.tones;
      const [coldBy, warmBy] = own?.hue ?? [56, 48];
      const [base, cold, warm, calm] = tones ?? [accent, `hsl(from ${accent} calc(h - ${coldBy}) s l)`, `hsl(from ${accent} calc(h + ${warmBy}) s l)`, muted];
      const rays = `conic-gradient(from 200deg at 8% 118%, transparent 0deg, ${lookTint(base, Math.round(9 * share))} 18deg, transparent 34deg, ${lookTint(cold, Math.round(7 * share))} 52deg, transparent 70deg, ${lookTint(warm, Math.round(7 * share))} 84deg, transparent 100deg)`;
      const layer = LOOK_LAYER;
      rules.push(`.dframe-root { isolation: isolate; }`);
      // Свёрнутая панель с живым фоном — скруглённая плашка, как в теме (#9071, класс по WF136).
      rules.push(`.dframe-root[data-collapsed] aside.dframe-sidebar { border-radius: 10px !important; }`);
      const pseudo = `content: ""; position: absolute; inset: 0; z-index: -1; pointer-events: none;`;
      if (motion === "image") {
        // Картинка (#9994): один статичный линейный градиент тонами схемы на одном слое — ни
        // пятен, ни лучей, ни ::after, ни transform, ни кадров. Доли ниже пиков пятен: заливка
        // во всё окно, а пятна гасли к краям — так в среднем не ярче живого фона.
        rules.push(`${layer}::before { ${pseudo} background: linear-gradient(135deg, ${lookTint(base, Math.round(20 * share))}, ${lookTint(cold, Math.round(16 * share))} 38%, ${lookTint(warm, Math.round(15 * share))} 70%, ${lookTint(calm, Math.round(12 * share))}); }`);
      } else {
        const live = motion === "live";
        rules.push(`${layer}::before, ${layer}::after { ${pseudo}${live ? " will-change: transform, opacity; animation-iteration-count: infinite; animation-direction: alternate;" : ""} }`);
        rules.push(`:root .dframe-root::before, :root .dframe-root::after { inset: -22%; }`);
        // «Стоит» (#9994) — тот же рисунок без animation-*, @keyframes и will-change: слои не
        // двигаются и в композиторе не живут отдельно, кадров ноль (как при «уменьшить движение»).
        const shapes = own?.shapes ?? LOOK_SPOTS;
        const layers = lookLayers(own);
        rules.push(`${layer}::before { background: ${spot(shapes[0], base, 38, 0)}, ${spot(shapes[1], cold, 32, 1)};${live ? ` animation-name: ${layers[0].name}; animation-duration: ${layers[0].ms / 1000}s;` : ""} }`);
        rules.push(`${layer}::after { background: ${own?.rays === false ? "" : `${rays}, `}${spot(shapes[2], warm, 30, 2)}, ${spot(shapes[3], calm, 24, 3)};${live ? ` animation-name: ${layers[1].name}; animation-duration: ${layers[1].ms / 1000}s; animation-delay: ${layers[1].delay / 1000}s;` : ""} }`);
        if (live) {
          for (const item of layers) {
            rules.push(`@keyframes ${item.name} { ${lookAuroraFrames(item).map(frame => `${Math.round(frame.offset * 1e5) / 1e3}% { transform: ${frame.transform}; opacity: ${frame.opacity}; animation-timing-function: ${frame.easing}; }`).join(" ")} }`);
          }
          rules.push(`:root[${LOOK_STILL_ATTRIBUTE}] ${layer}::before, :root[${LOOK_STILL_ATTRIBUTE}] ${layer}::after { animation-play-state: paused !important; }`);
          // «Уменьшить движение» — CSS-кадров нет (их всё равно ужимает Claude), а
          // переливание крутит auroraCalmSync через Web Animations (ниже, у paintLook).
          rules.push(`@media (prefers-reduced-motion: reduce) { ${layer}::before, ${layer}::after { animation: none !important; } }`);
        }
      }
      // Подложку видно сквозь окно: основа и её обёртка прозрачны, карточка
      // ленты и левая панель — стекло цветом самого Claude (или темы), без
      // обводок и теней-рамок (линии между лентой и колонкой поля нет во всех видах — layoutCss,
      // #11216). Правила сильнее слоя темы (тот ставит фон
      // `!important` на .dframe-content и [class*="dframe-sidebar"]).
      // #9104/#9105 (WF139, слово Элвиса 08.10: «почему прозрачности нормальной нету… под
      // всем должна быть вот эта переливающаяся»): класс ошибки — сплошные «поверхности»
      // Claude поверх подложки. Чиним их источники, а не точки: (1) всё, что Claude
      // заливает цветом ленты, берёт его из своей переменной `--epitaxy-transcript-surface`
      // (запас — surface-1): маска под докой поля ввода, сама дока, шторка перехода —
      // переменная прозрачна, и тёмных полос под полем и у краёв нет; (2) страница во
      // всё окно `bg-surface-1 h-full w-full` внутри `.dframe-root` (попап «Open in new
      // window» с 2.2x закрывал ею подложку целиком) — прозрачна; (3) лента и левая панель
      // — без своей заливки, подложка одна на всё окно (полос «панель | щель | карточка»
      // нет); (4) то, что лежит ПОВЕРХ текста, — стекло: полупрозрачно и с размытием
      // (выезжающий список свёрнутой панели, меню, списки и попапы Claude),
      // текст читается, подложка видна; поле ввода — прозрачно (#9127). Линий и рамок нет (решение WF128).
      const glass = (color, share, blur) => `background-color: ${lookTint(color, share)} !important; background-image: none !important; -webkit-backdrop-filter: blur(${blur}px) saturate(1.25) !important; backdrop-filter: blur(${blur}px) saturate(1.25) !important;`;
      rules.push(`.epitaxy-chat-panel { --epitaxy-transcript-surface: transparent; }`);
      // Слой темы красит эти же узлы цветом основы по классу (#8845) — тут сильнее он.
      rules.push(`:is(main.dframe-content, .dframe-pane-host, .epitaxy-chat-panel) [class*="--epitaxy-transcript-surface"] { background-color: transparent !important; }`);
      rules.push(`.dframe-root :is(.dframe-content, .dframe-content-inner, .bg-surface-1.h-full.w-full) { background: transparent !important; }`);
      // 3.1623 (слово Элвиса 22.10: «анимированный фон перестал работать»): рамка плиток .tiles-shell залита
      // --tile-shell-ground цветом страницы во всё окно и закрыла подложку целиком.
      rules.push(`.dframe-root .tiles-shell { --tile-shell-ground: transparent; background: transparent !important; }`);
      rules.push(`.epitaxy-chat-panel > [class*="rounded-card"][class*="bg-surface"] { background-color: transparent !important; outline: none !important; box-shadow: none !important; border-color: transparent !important; }`);
      rules.push(`.dframe-root aside.dframe-sidebar { background-color: transparent !important; background-image: none !important; box-shadow: none !important; border-color: transparent !important; }`);
      // :root впереди — сильнее правила темы на детях aside (WF144 сузил его до aside, и оно стало точнее этого).
      rules.push(`:root .dframe-root aside.dframe-sidebar :is([class*="dframe-sidebar"], [data-testid*="sidebar"]) { background-color: transparent !important; border-color: transparent !important; }`);
      // Маска под докой прозрачна — лента под полем уходит в дымку, а не в полосу: край мягкий.
      rules.push(`.epitaxy-chat-panel .sticky.bottom-0[class*="epitaxy-transcript-surface"] { -webkit-backdrop-filter: blur(14px) !important; backdrop-filter: blur(14px) !important; -webkit-mask-image: linear-gradient(to bottom, transparent, #000 28px) !important; mask-image: linear-gradient(to bottom, transparent, #000 28px) !important; }`);
      rules.push(`[class*="in-data-cds-dock-masked:bg-page"] { background-color: transparent !important; }`);
      // Режим обычного чата (#10553, слово Элвиса 22.10: «наложение… на текст накладывается»): поле стоит в доке
      // ChatComposerDock поверх ленты, и ленту под ним Claude прячет заливкой bg-page (правило выше её снимает)
      // и полосой from-page под плашками — размытия, как у Code, там нет. Дымка — слоем под липкой обёрткой поля
      // (z-[5], своя стопка): лента под полем размыта, край мягкий в её отступе pt-6; поле остаётся прозрачным.
      rules.push(`[class*="in-data-cds-dock-masked:from-page"] { background-image: none !important; }`);
      rules.push(`[data-chat-input-container]:has([data-cds-dock-masked])::before { content: ""; position: absolute; inset: 0; z-index: -1; pointer-events: none; -webkit-backdrop-filter: blur(14px) !important; backdrop-filter: blur(14px) !important; -webkit-mask-image: linear-gradient(to bottom, transparent, #000 24px) !important; mask-image: linear-gradient(to bottom, transparent, #000 24px) !important; }`);
      // Режим обычного чата, шапка и док (#10399, слово Элвиса 20.10: «чёрные прямоугольники… в режиме кода всё
      // нормально, а в режиме чата нет») — тот же класс, что под полем: сплошные подложки цветом страницы поверх
      // живого фона (бандл claude.ai 24.10). Шапка чата .dframe-header залита bg-surface-1, когда лента под неё не
      // заходит; заходит — под названием и под кнопками справа подложка панели toolbar-ground (фон страницы 85 % и
      // размытие 12); без панелей — полоса df-header-backdrop (тянется влево под левую панель) и затухание
      // data-lifted-row-fade. Всё это — дымка, как под полем: заливки нет, размытие; мягкий край — 12px НИЖЕ шапки, чтобы
      // под названием лента была размыта целиком, а не проступала строкой; черта под шапкой — линия панели (линий нет, WF128). Шапку Code не трогаем: она своя (.epitaxy-titlebar), в широком виде
      // её подложку снимает сетка (WF274). У поля: карточки дока — bg-page и затухание page-fade над ними (::before),
      // подпись «Claude is AI…» — плашка bg-surface-1, заходящая под поле (-mt-10).
      const haze = "-webkit-backdrop-filter: blur(14px) !important; backdrop-filter: blur(14px) !important;";
      const hazeEnd = "-webkit-mask-image: linear-gradient(to top, transparent, #000 12px) !important; mask-image: linear-gradient(to top, transparent, #000 12px) !important;";
      const header = `.dframe-header:is([class~="bg-surface-1"], [class*=":bg-surface-1"])`;
      rules.push(`${header} { background-color: transparent !important; }`);
      rules.push(`${header}::before { content: ""; position: absolute; inset: 0 0 -12px; z-index: -1; pointer-events: none; ${haze} ${hazeEnd} }`);
      rules.push(`:is([data-cds="Toolbar"]:not(.epitaxy-titlebar *) > [data-cds-part="toolbar-ground"], [data-cds="Page"] [data-cds-part="page-header-ground"]) { bottom: -12px !important; background-color: transparent !important; ${haze} ${hazeEnd} }`);
      rules.push(`:is(.df-header-backdrop, [data-lifted-row-fade]) { background-color: transparent !important; ${haze} }`);
      rules.push(`.dframe-header [data-cds="Toolbar"]::after { border-bottom-width: 0 !important; }`);
      rules.push(`[data-cds-dock-masked] .bg-page { background-color: transparent !important; }`);
      rules.push(`[data-cds-dock-masked] [class*="page-fade"]::before { background-image: none !important; }`);
      rules.push(`[class~="-mt-10"][class~="pt-12"][class~="bg-surface-1"] { background-color: transparent !important; }`);
      // Волосок над строкой аккаунта внизу левой панели («снизу узкая полоса»).
      rules.push(`.df-bottom-tray::before { border-color: transparent !important; }`);
      // Поле ввода — ПРОЗРАЧНО во всех видах, без стекла и размытия: подложку видно насквозь
      // (#9127, WF142, слово Элвиса 08.10: «Поле ввода было прозрачно»; плашку дало стекло WF139).
      // Рамки нет — её прячет цвет: по ширине и тени editorFrame находит коробку поля (#6890).
      rules.push(`[data-cds="ChatComposer"] > div[class*="bg-surface"] { background-color: transparent !important; background-image: none !important; -webkit-backdrop-filter: none !important; backdrop-filter: none !important; border-color: transparent !important; box-shadow: 0 0 0 0 transparent !important; }`);
      // Свёрнутая панель: выезжающий список лежит ПОВЕРХ ленты — почти сплошной цвет панели, под ним
      // размытие; кольца нет, тень мягкая. Слово Элвиса 11.10 01:40 (снимок 8: светлое размытое пятно
      // во всю панель, строки не читаются): «какой переход яркий… Во всех темах проверь». Причина: правило
      // выше (`:root … aside … [class*="dframe-sidebar"]`, вес 0,4,1) делало прозрачным и сам список —
      // его заливка (вес 0,4,0) не применялась, оставалось одно размытие: светлая картинка ленты под
      // списком светила насквозь. Здесь вес 0,5,1 и доля цвета панели 94 % (было 52 %, и те не работали).
      // Цвет — панели темы окна (--df-bg-sidebar ставит только слой темы; свою --df-sidebar-bg Claude
      // на самой панели переопределяет: белая в светлом виде); темы нет — цвет панели Claude.
      rules.push(`:root .dframe-root[data-collapsed] aside.dframe-sidebar .dframe-sidebar-body { ${glass("var(--df-bg-sidebar, var(--df-sidebar-bg, var(--cds-surface-1)))", LOOK_PEEK_SHARE, 22)} box-shadow: 0 10px 28px rgba(0, 0, 0, 0.28) !important; }`);
      // Меню, списки и попапы Claude (порталом в body, вне `.dframe-root`).
      rules.push(`:is([role="menu"], [role="listbox"], .cds-root.pointer-events-auto [class*="rounded-card"]):is([class*="bg-surface"], [class*="bg-popover"]) { ${glass("var(--cds-surface-3)", 62, 20)} }`);
      // Фото и вложения в ленте — без обводок (слово 08.10: «рамки вокруг фото… не нужны»).
      rules.push(`.epitaxy-chat-panel :is(.cursor-zoom-in, [data-cds-attachment]) { border-color: transparent !important; box-shadow: none !important; outline: none !important; }`);
      rules.push(...scrollFadeCss());
    }
    // Неон и ретро-экран (#7179) снят (слово Элвиса 08.10: ретро
    // убрать): ключ look.neon в формате и в карте остаётся, страница его не рисует.
    if (look.dense) {
      // Плотный текст (#7180): межстрочный и отступы абзацев, списков и
      // заголовков в ленте — меньше, размер шрифта НЕ трогаем. Правило стоит на
      // самих p/li, а не на .prose: так оно сильнее и слоя размера (тот ставит
      // line-height 1.5 на обёртку, и дети его только наследуют).
      rules.push(`${LOOK_FEED} .prose :is(p, li, blockquote, td, th) { line-height: 1.34 !important; }`);
      rules.push(`${LOOK_FEED} .prose * + :is(p, ul, ol, blockquote, pre, table) { margin-top: 0.45em !important; }`);
      rules.push(`${LOOK_FEED} .prose * + :is(h1, h2, h3, h4) { margin-top: 0.8em !important; }`);
      rules.push(`${LOOK_FEED} .prose :is(h1, h2, h3, h4) { margin-bottom: 0.25em !important; }`);
      rules.push(`${LOOK_FEED} .prose li + li, ${LOOK_FEED} .prose li > :is(ul, ol) { margin-top: 0.1em !important; }`);
      // Между репликами — 10 вместо 20 (класс gap-5 у колонки разговора, замер 23.09).
      rules.push(`${LOOK_FEED} .flex-col.gap-5 { row-gap: 10px !important; }`);
    }
    return `${rules.join("\n")}\n`;
  };

  // Ключи хранилища (WF9, п. 6): тема живёт на ЧАТЕ, а не на окне. Заголовок
  // окна — это и есть имя чата, поэтому ключ `chat:<заголовок>` одинаково годен
  // и главному окну (заголовок меняется с каждым чатом), и подчинённому («Open
  // in new window», заголовок постоянный). Сверх того у главного окна есть
  // ключ `main` — «тема этого окна вообще»: новый чат (⌘N, окно после
  // «Обкэшить») цвет не меняет — чат, родившийся с домашнего экрана, берёт
  // только свою запись, а нет её — окно не трогает ничего. Переход из чата в
  // ДРУГОЙ существующий чат (WF82, #7103) идёт полным порядком слоёв: чат без
  // своей записи берёт тему окна (сессия → `main` → «всем»), а не цвет того
  // чата, откуда пришли (см. syncChatTheme).
  // `w:<заголовок>` — записи подчинённых окон до WF9; читаются как `chat:` и при
  // первой же записи переносятся (контракт WF9). Ключ СЕССИИ, в отличие от
  // ключей карты, всегда оконный (`main`/`w:<заголовок>`): сессия обязана
  // пережить смену чата в окне (см. sessionKey).
  // WF35 добавил к этому `id:<id чата>` и сделал его ГЛАВНЫМ ключом чата:
  // приоритет по слою `id:` → `chat:` → сессия → `main` → `*`, пишутся оба
  // ключа чата разом, а первое совпадение копирует старую запись на `id:`
  // (migrateChatKey). Старую запись не удаляем: по ней ещё живут окна, которые
  // своего id не знают.
  // Красим только окна Claude: claude.ai (главное) и about:blank («Open in new
  // window»). Артефакты, браузерная панель (data:) и file: — не наши.
  const themable = /^(https:\/\/claude\.ai\/|about:blank)/.test(location.href);
  const THEME_MAIN_KEY = "main";
  const THEME_CHAT_PREFIX = "chat:";
  const THEME_LEGACY_PREFIX = "w:";
  // WF35: главный ключ чата — его id (`id:local_<uuid>`), а не имя. Имя чата
  // Элвис меняет, id — нет, и после переименования ключ `chat:<старое имя>`
  // больше никем не читался: окно теряло цвет (пункт 20 списка 05.09).
  const THEME_ID_PREFIX = "id:";
  const isMainWindow = () => themable && location.href.includes("claude.ai");
  // Заголовки-заглушки. Пока у разговора нет имени, окно зовётся «Claude» или
  // «New chat», и такой заголовок носят РАЗНЫЕ чаты во всех окнах разом. Ключа
  // чата у заглушки нет вовсе — ни на чтение, ни на запись: иначе выбор темы в
  // безымянном чате красил бы каждый новый чат в каждом окне (разбор критика,
  // п. 3). Тема такого окна живёт в `main` и в сессии.
  // «Code» (WF88, К19) — заголовок штатного черновика «New Session in New
  // Window» и попапа code-session до имени: иначе все черновики и чат «Code»
  // делили бы тему `chat:Code`.
  // «Loading» (WF93, #7378) — заголовок свежего попапа «Нового чата», пока у
  // сессии нет имени: его носили два тестовых чата подряд, и кэш «кто я» по
  // заголовку отдал новому окну id прошлого.
  const THEME_TITLE_STUBS = new Set(["claude", "new chat", "новый чат", "code", "loading", "загрузка…"]);
  // Метка кнопки «💬 Новый чат» (#7246, раздел 12к) — тот же приём:
  // пока она в document.title, заголовок чата — прежний.
  const continueTitle = { label: "", saved: "" };
  const windowTitle = () => {
    const title = (document.title || "").trim();
    if (continueTitle.label && title === continueTitle.label) return continueTitle.saved.trim();
    return title;
  };
  // Заголовка ещё нет (about:blank сразу после открытия) — ключа чата нет, ждём
  // его (см. watchChatTitle).
  const chatTitleKey = () => {
    if (!themable) return null;
    const title = windowTitle();
    if (!title || THEME_TITLE_STUBS.has(title.toLowerCase())) return null;
    return `${THEME_CHAT_PREFIX}${title}`;
  };
  // Ключ по id чата (WF35). Проверка themable стоит явно, а не достаётся от
  // myChatId: раздел 12в про ключи темы ничего не обещает, а чужая страница
  // (артефакт, браузерная панель) не должна давать ключа вовсе. Заголовок-
  // заглушка при известном id ключом ТЕПЕРЬ становится — у безымянного чата
  // тоже есть id, и выбранный в нём цвет обязан остаться, когда имя появится.
  // Осечка myChatId (раздел 12в лежит ниже, источники id у него чужие) не должна
  // уносить с собой всю тему окна: id неизвестен — работаем по имени чата, ровно
  // как деградирует адресация WF29.
  const chatIdKey = () => {
    if (!themable) return null;
    let id = null;
    try { id = myChatId(); } catch { id = null; }
    return typeof id === "string" && id ? `${THEME_ID_PREFIX}${id}` : null;
  };
  // Действующий ключ чата: id сильнее имени, имя — тень для окон, которые своего
  // id ещё не знают (попап в первые секунды: карту попапов наполняет probe).
  const chatKey = () => chatIdKey() ?? chatTitleKey();
  // Ключ СЕССИИ — по окну, а не по чату: главное окно `main`, подчинённое
  // `w:<заголовок>` (его заголовок при жизни окна не меняется). Сессия обязана
  // пережить смену чата: с ключом чата этот слой умирал бы на каждом ⌘N, а
  // заведён он ровно ради «пока окно живо, оно того цвета, что выбрали».
  const sessionKey = () => {
    if (!themable) return null;
    if (isMainWindow()) return THEME_MAIN_KEY;
    const title = windowTitle();
    return title ? `${THEME_LEGACY_PREFIX}${title}` : null;
  };
  // Ключ ХРАНИЛИЩА окна: чат, а у главного окна без имени чата — `main`.
  const themeKey = () => chatKey() ?? (isMainWindow() ? THEME_MAIN_KEY : null);
  const themeMapReads = new WeakMap();
  const readThemeMap = () => {
    try {
      const raw = localStorage.getItem(THEME_MAP_KEY);
      const data = raw ? JSON.parse(raw) : null;
      const map = data && typeof data === "object" && !Array.isArray(data) ? data : {};
      themeMapReads.set(map, map === data ? raw : "{}");
      return map;
    } catch {
      const map = {}; themeMapReads.set(map, "{}"); return map;
    }
  };
  const THEME_MAP_LIMIT = 200;
  const THEME_USED_MS = 60000;
  const themeStamp = value => Number.isSafeInteger(value?.at) && value.at > 0 ? value.at : 0;
  // Удаляем старый чат вместе с его тенями, а не случайный алфавитный ключ.
  // Действующие окна и общие слои не вытесняются даже при >200 активных ключах.
  const retainThemeMap = map => {
    // Только главное окно с доступным ЖИВЫМ inventory знает, что можно убрать.
    // До скана и в попапе старые записи открытых соседей не рискуем вытеснять.
    if (!isMainWindow()) return map;
    let open = null;
    try { open = chatsMap(newWindowStore); } catch {}
    if (open === null) return map;
    const active = new Set([THEME_ALL_KEY, THEME_MAIN_KEY, chatIdKey(), chatTitleKey(), legacyKey(chatTitleKey())]);
    for (const row of open) {
      active.add(`${THEME_ID_PREFIX}${row.id}`);
      if (row.title) { active.add(`${THEME_CHAT_PREFIX}${row.title}`); active.add(`${THEME_LEGACY_PREFIX}${row.title}`); }
    }
    const groups = new Map();
    for (const [key, entry] of Object.entries(map)) {
      const owner = shadowOwner(entry);
      const groupKey = owner ? `${THEME_ID_PREFIX}${owner}` : key;
      const group = groups.get(groupKey) ?? { keys: [], at: 0, active: false };
      group.keys.push(key);
      group.at = Math.max(group.at, themeStamp(entry));
      group.active ||= active.has(key) || active.has(groupKey);
      groups.set(groupKey, group);
    }
    let count = Object.keys(map).length;
    for (const group of [...groups.values()].sort((a, b) => a.at - b.at || a.keys[0].localeCompare(b.keys[0]))) {
      if (count <= THEME_MAP_LIMIT) break;
      if (group.active) continue;
      for (const key of group.keys) { delete map[key]; count -= 1; }
    }
    return map;
  };
  const writeThemeMap = (map, stampChanges = true, readMap = map) => {
    try {
      // Другой popout мог сохранить слой после нашего чтения. На свежую карту
      // накладываем только собственную разницу, включая удалённые слои.
      const baseText = themeMapReads.get(readMap);
      if (map && baseText !== undefined) {
        const base = JSON.parse(baseText);
        const latest = readThemeMap();
        for (const key of new Set([...Object.keys(base), ...Object.keys(map)])) {
          const before = keepOwner(themeEntry(base[key]), base[key]);
          const wanted = keepOwner(themeEntry(map[key]), map[key]);
          const entry = keepOwner(themeEntry(latest[key]), latest[key]);
          let changed = false;
          for (const field of [...THEME_LAYERS, "by", "at"]) {
            if (JSON.stringify(before[field]) === JSON.stringify(wanted[field])) continue;
            changed = true;
            if (wanted[field] === undefined) delete entry[field];
            else entry[field] = field === "at" ? Math.max(themeStamp(latest[key]), wanted.at) : wanted[field];
          }
          if (!changed) continue;
          if (THEME_LAYERS.some(layer => layer in entry)) latest[key] = entry;
          else delete latest[key];
        }
        map = latest;
      }
      if (map && stampChanges) {
        const stamp = Date.now(); // один выбор — одно время для id и всех его теней
        const old = readThemeMap();
        for (const [key, value] of Object.entries(map)) {
          const changed = JSON.stringify(themeEntry(value)) !== JSON.stringify(themeEntry(old[key]))
            || shadowOwner(value) !== shadowOwner(old[key]) || themeStamp(value) !== themeStamp(old[key]);
          if (changed) map[key] = { ...keepOwner(themeEntry(value), value), at: stamp };
        }
      }
      if (!map || Object.keys(map).length === 0) localStorage.removeItem(THEME_MAP_KEY);
      else localStorage.setItem(THEME_MAP_KEY, JSON.stringify(retainThemeMap(map)));
    } catch {}
  };
  // Собственный чат действительно используется. Не омолаживаем всю карту ни
  // от probe, ни от restore; раз в минуту обновляем только присутствующие ключи.
  let themeUsedKey = null;
  let themeUsedAt = 0;
  const touchThemeMap = () => {
    if (!themable) return;
    const key = chatKey();
    const stamp = Date.now();
    if (key === themeUsedKey && stamp - themeUsedAt < THEME_USED_MS) return;
    themeUsedKey = key; themeUsedAt = stamp;
    const map = readThemeMap();
    const keys = [chatIdKey(), chatTitleKey(), legacyKey(chatTitleKey()), isMainWindow() ? THEME_MAIN_KEY : null];
    let changed = false;
    for (const key of keys) {
      if (!key || map[key] === undefined || themeStamp(map[key]) >= stamp - THEME_USED_MS) continue;
      if (key.startsWith(THEME_CHAT_PREFIX) && !shadowMine(map, key)) continue;
      map[key] = { ...keepOwner(themeEntry(map[key]), map[key]), at: stamp };
      changed = true;
    }
    if (changed || Object.keys(map).length > THEME_MAP_LIMIT) writeThemeMap(map, false);
  };
  // Слоёв четыре, и каждый хранится трёхзначно: значение — оно самое, "none" —
  // явный сброс («Как у Claude» это тоже выбор, иначе окно на следующем инжекте
  // покрасилось бы обратно из карты), поля нет — слоя не касались. Поэтому
  // запись окна — объект { theme, font, size, look }, а не одна тема, как было
  // в WF5. Порядок важен: оформление (WF83) идёт ПОСЛЕ темы, потому что берёт её
  // цвета, и на восстановлении они к тому времени уже на месте. Слоя `frame`
  // (неоновая рамка, #9471) больше нет: его поле в записи и в команде не читается
  // (themeEntry его не переносит), запись без него переписывается при первой правке.
  const THEME_LAYERS = ["theme", "font", "size", "look"];
  const LAYER_NORMALIZE = {
    theme: normalizeTheme, font: normalizeFont, size: normalizeSize, look: normalizeLook,
  };
  // Старый формат WF5 читается обязательно: в живых окнах уже лежат записи, где
  // тема стоит на верхнем уровне, и строки "none". Без этого перевода окна
  // потеряли бы темы на первом же инжекте новой версии.
  const themeEntry = value => {
    if (value === "none") return { theme: "none" };
    if (!value || typeof value !== "object" || Array.isArray(value)) return {};
    if (value.palette) return { theme: value };
    const entry = {};
    for (const layer of THEME_LAYERS) if (layer in value) entry[layer] = value[layer];
    return entry;
  };
  // Слой записи: undefined — слоя нет (не трогаем), null — сброс, объект —
  // значение. Мусор в слое равен его отсутствию: пусть решает следующий уровень.
  const entryLayer = (entry, layer) => {
    if (!entry || !(layer in entry)) return undefined;
    const raw = entry[layer];
    if (raw === "none" || raw == null) return null;
    return LAYER_NORMALIZE[layer](raw) ?? undefined;
  };
  // Ключ старого образца для ключа чата: `chat:Vkusnoff` → `w:Vkusnoff`.
  const legacyKey = key =>
    (typeof key === "string" && key.startsWith(THEME_CHAT_PREFIX)
      ? THEME_LEGACY_PREFIX + key.slice(THEME_CHAT_PREFIX.length)
      : null);
  // Запись карты по ключу. Записи подчинённых окон до WF9 лежат под `w:<title>`,
  // и читаются они как запись чата — иначе окна Элвиса потеряли бы темы на
  // первом же инжекте новой версии.
  const mapEntry = (map, key) => {
    if (!key) return null;
    if (map[key] !== undefined) return themeEntry(map[key]);
    const legacy = legacyKey(key);
    return legacy != null && map[legacy] !== undefined ? themeEntry(map[legacy]) : null;
  };
  // Запись ЭТОГО чата: приоритет `id:` → `chat:` идёт ПО СЛОЮ, а не по записи
  // целиком. Раньше здесь стоял `??`, и он срабатывал на самой записи: запись
  // `id:` с одним слоем закрывала более полную тень `chat:` — остальные слои чата
  // пропадали с экрана, а их место занимала СЕССИЯ, то есть цвет другого
  // разговора (находка ревизии 08.09). Слои разведены — им и решать.
  // Владелец тени `chat:<заголовок>` (z1-r01): одинаковые заголовки у Элвиса —
  // норма, и без владельца цвет чата А доставался чату Б без своей записи, а
  // migrateChatKey копировал его в `id:Б` навсегда. Окно, знающее свой id,
  // пишет в тень `by: <id>`. Брать тень можно без `by` (записал попап, ещё не
  // знавший id, или прежняя версия) или со своим id; окно без id берёт любую —
  // как раньше. Поле лежит рядом со слоями: themeEntry его не отдаёт, хранят
  // его setMapLayers, общая запись и themes-restore (keepOwner).
  const shadowOwner = raw => (raw && typeof raw === "object" && !Array.isArray(raw)
    && typeof raw.by === "string" && raw.by ? raw.by : null);
  const shadowMine = (map, key) => {
    const owner = key ? shadowOwner(map[key]) : null;
    if (!owner) return true;
    const idKey = chatIdKey();
    return !idKey || idKey === `${THEME_ID_PREFIX}${owner}`;
  };
  const keepOwner = (entry, raw) => {
    const owner = shadowOwner(raw);
    const kept = owner ? { ...entry, by: owner } : { ...entry };
    if (themeStamp(raw)) kept.at = themeStamp(raw);
    return kept;
  };
  const chatEntry = map => {
    const byId = mapEntry(map, chatIdKey());
    const titleKey = chatTitleKey();
    const byTitle = shadowMine(map, titleKey) ? mapEntry(map, titleKey) : null;
    if (!byId) return byTitle;
    if (!byTitle) return byId;
    const entry = {};
    for (const layer of THEME_LAYERS) {
      // Мусор в слое равен его отсутствию — решает следующий уровень (entryLayer).
      if (entryLayer(byId, layer) !== undefined) entry[layer] = byId[layer];
      else if (entryLayer(byTitle, layer) !== undefined) entry[layer] = byTitle[layer];
    }
    return entry;
  };
  // Первое совпадение переносит запись имени на id — КОПИЕЙ, старую оставляем:
  // по ней ещё живёт окно, которое своего id не знает (попап в первые секунды,
  // непропатченная страница). Зовётся трижды: на инжекте, в syncChatTheme (у
  // попапа id появляется ПОЗЖЕ инжекта) и первой строкой writeLayers — иначе
  // запись `id:` создалась бы с одним слоем и навсегда закрыла бы более полную
  // тень `chat:`, а остальные слои чата пропали бы с экрана.
  const migrateChatKey = () => {
    const idKey = chatIdKey();
    if (!idKey) return;
    const map = readThemeMap();
    if (map[idKey] !== undefined) return;
    if (!shadowMine(map, chatTitleKey())) return;
    const entry = mapEntry(map, chatTitleKey());
    if (!entry || Object.keys(entry).length === 0) return;
    map[idKey] = entry;
    writeThemeMap(map);
  };

  // Годится ли сессия этому окну. Свой ключ у неё оконный (`main`/`w:<заголовок>`),
  // но в живых окнах лежат записи и от wf9-a-1, где ключом был чат. Принимаем и
  // их — пока окно в том же разговоре, — чтобы окна Элвиса не моргнули чужим
  // цветом на первом инжекте новой версии. Перекрыть запись чата такая сессия
  // больше не может: она стоит В ПОРЯДКЕ восстановления ниже (см. restoreTheme).
  const sameSessionKey = (stored) => {
    if (typeof stored !== "string" || stored === "") return false;
    const key = sessionKey();
    if (key && stored === key) return true;
    // Ключей чата теперь два (WF35), и принимать надо ОБА: сессии, записанные до
    // обновления, лежат под именем чата, свежие — под id. Признай мы только один,
    // окна Элвиса разово потеряли бы слой сессии.
    for (const chat of [chatIdKey(), chatTitleKey()]) if (chat && stored === chat) return true;
    return stored === THEME_MAIN_KEY && isMainWindow();
  };
  // Запись привязана к ключу окна: окно «Open in new window» — попап, и по
  // спецификации HTML оно стартует с КОПИЕЙ sessionStorage главного окна.
  // Без ключа подчинённое окно красилось бы темой главного.
  const readSessionEntry = () => {
    try {
      const raw = sessionStorage.getItem(THEME_SESSION_KEY);
      if (raw == null) return null;
      const record = JSON.parse(raw);
      if (!record || typeof record !== "object" || Array.isArray(record) || !record.key) return null;
      if (!sameSessionKey(record.key)) return null;
      // Сессия старого формата — { key, theme }: слоя font в ней нет, и шрифта
      // у окна тоже нет. Именно это и значит «поля нет».
      return themeEntry(record);
    } catch { return null; }
  };
  const storeSessionLayers = layers => {
    try {
      // Слой, которого команда не касалась, остаётся в записи как был.
      const record = { key: sessionKey(), ...(readSessionEntry() ?? {}) };
      for (const layer of THEME_LAYERS) {
        if (layer in layers) record[layer] = layers[layer] ?? "none";
      }
      sessionStorage.setItem(THEME_SESSION_KEY, JSON.stringify(record));
    } catch {}
  };
  // Снять слои из сессии окна совсем (#5743): «Вернуть» всем окнам отдаёт слой записи чата и `main`,
  // а маркер "none" в сессии закрыл бы `main` у домашнего экрана.
  const dropSessionLayers = list => {
    try {
      const record = readSessionEntry();
      if (!record) return;
      for (const layer of list) delete record[layer];
      sessionStorage.setItem(THEME_SESSION_KEY, JSON.stringify({ key: sessionKey(), ...record }));
    } catch {}
  };
  // Склад снятых «всем окнам» слоёв (#5743): мусор равен пустому складу.
  const readThemePrev = () => {
    try {
      const data = JSON.parse(localStorage.getItem(THEME_PREV_KEY) ?? "null");
      return data && typeof data === "object" && !Array.isArray(data) ? data : {};
    } catch { return {}; }
  };
  const writeThemePrev = prev => {
    try {
      const keys = Object.keys(prev).filter(key => THEME_LAYERS.some(layer => layer in (prev[key] ?? {})));
      if (!keys.length) { localStorage.removeItem(THEME_PREV_KEY); return; }
      const out = {};
      for (const key of keys.slice(-THEME_MAP_LIMIT)) out[key] = prev[key];
      localStorage.setItem(THEME_PREV_KEY, JSON.stringify(out));
    } catch {}
  };

  // previewing — окно сейчас показывает предпросмотр (мышь ведут по подменю), и
  // в хранилище лежит не то, что на экране: см. runThemeCommand.
  // previewLayers — какие именно слои сейчас примерены (WF31, #5453): новая
  // примерка возвращает из хранилища те из них, которых в ней нет, — цвет
  // всегда смотрится с УСТАНОВЛЕННЫМ шрифтом, а шрифт с установленным цветом.
  // chatKey — заголовок, под который окно уже покрашено: сторож (watchChatTitle)
  // сверяет его с нынешним и на смене чата перекрашивает окно. pending — выбор,
  // сделанный до появления заголовка: дописываем его, когда ключ чата появится.
  const themeState = {
    theme: null, source: null, font: null, fontSource: null, previewing: false, previewLayers: [],
    size: null, sizeSource: null, look: null, lookSource: null, lookCss: "",
    chatKey: null, chatTimer: 0, chatObserver: null, pending: null, pendingUntil: 0,
  };
  // Тема — конструируемая таблица стилей (adoptedStyleSheets), а не <style> в
  // <head>: Claude зеркалит <style> из главного окна во все попапы «Open in new
  // window» (проверено живьём 03.09: тема главного окна появилась во всех
  // подчинённых). Adopted-таблицы — не DOM-узлы, зеркало их не видит, а в
  // каскаде они идут после таблиц документа и при равной силе побеждают.
  const themeSheet = new CSSStyleSheet();
  // Шрифт — вторая таблица, независимая от первой: сменить шрифт, не тронув
  // цвета, и наоборот. Одной таблицей это не выходит — её пришлось бы
  // перегенерировать целиком на каждую половину.
  const fontSheet = new CSSStyleSheet();
  // Размер — третья таблица по тому же доводу: сменить размер, не тронув ни
  // цветов, ни шрифта.
  const sizeSheet = new CSSStyleSheet();
  // Четвёртая таблица — вложения поля ввода в узком окне (WF61, #5912). В
  // отличие от трёх верхних она не слой: её содержимое не зависит ни от команды,
  // ни от выбора Элвиса, — поэтому ставится один раз здесь и снимается вместе с
  // экземпляром, а не по applyLayer.
  const attachmentsSheet = new CSSStyleSheet();
  // Пятая — широкий вид окна (WF65): такая же не-слой, ставится один раз и
  // снимается с экземпляром. В массиве стоит ПОСЛЕ attachmentsSheet: спор двух
  // !important за max-height у области текста решает порядок таблиц.
  const layoutSheet = new CSSStyleSheet();
  // Шестая — оформление (слой look, WF83): слой, как тема и размер, и ставится
  // только когда включён хоть один тумблер.
  const lookSheet = new CSSStyleSheet();
  const detachSheet = sheet => {
    try { document.adoptedStyleSheets = document.adoptedStyleSheets.filter(item => item !== sheet); } catch {}
  };
  const adoptSheet = sheet => {
    try {
      document.adoptedStyleSheets = [...document.adoptedStyleSheets.filter(item => item !== sheet), sheet];
      return true;
    } catch { return false; }
  };
  track(() => {
    detachSheet(themeSheet); detachSheet(fontSheet); detachSheet(sizeSheet); detachSheet(attachmentsSheet);
    detachSheet(layoutSheet); detachSheet(lookSheet);
  });
  // Ставим сразу и только в окнах Claude: в артефакте и браузерной панели поля
  // ввода нет вовсе, а лишняя таблица там — лишняя таблица (см. themable).
  if (themable) {
    try { attachmentsSheet.replaceSync(attachmentsCss()); } catch {}
    adoptSheet(attachmentsSheet);
    try { layoutSheet.replaceSync(layoutCss()); } catch {}
    adoptSheet(layoutSheet);
  }
  // Сирота снятой неоновой рамки (#9471): её оверлей от прежних установок.
  for (const orphan of document.querySelectorAll(`#${WINDOW_FRAME_ID}`)) orphan.remove();

  // Акцент окна: у Claude и у наших тем (themeCss выше) --accent-brand хранит не
  // цвет, а тройку HSL — «251.000 40.000% 54.500%». Подставить её как есть
  // нельзя, объявление отбросится, поэтому тройку заворачиваем в hsl() сами, а на
  // всё незнакомое берём фиолетовый донора. Им живут оформление, полоса прогресса
  // (раздел 2б) и отсчёт отправки (12у) — на то он и акцент.
  const ACCENT_FALLBACK = "#8b5cf6";
  const accentColor = () => {
    let raw = "";
    // В окне Claude Code палитра живёт на .epitaxy-root, а не на html.
    try {
      const host = state.composerBlock ?? document.querySelector(".epitaxy-root") ?? document.documentElement;
      raw = getComputedStyle(host).getPropertyValue("--accent-brand").trim();
    } catch {}
    if (!raw) return ACCENT_FALLBACK;
    if (/^(?:#|rgba?\(|hsla?\(|oklch\(|lab\(|lch\(|color\()/i.test(raw)) return raw;
    if (/^[\d.]+(?:deg)?\s+[\d.]+%\s+[\d.]+%$/.test(raw)) return `hsl(${raw})`;
    return ACCENT_FALLBACK;
  };

  // Оформление берёт цвета темы: сменилась тема (и живые цвета) —
  // таблицу пересобираем. Текст тот же — не трогаем вовсе, чтобы живой фон не
  // дёргался на каждом тике круга.
  const lookColors = () => {
    const palette = themeState.theme?.palette ?? null;
    const accent = palette?.accent ?? accentColor();
    let dark = true;
    if (themeState.theme?.type) dark = themeState.theme.type !== "light";
    else { try { dark = matchMedia("(prefers-color-scheme: dark)").matches; } catch {} }
    return { accent, muted: palette?.muted ?? accent, foreground: palette?.foreground ?? "currentColor", dark };
  };
  const lookGlow = () => LOOK_THEME_GLOW[themeState.theme?.id] ?? null;
  const paintLook = () => {
    if (!themeState.look) return;
    const css = lookCss(themeState.look, lookColors(), lookGlow());
    if (css === themeState.lookCss) return;
    try { lookSheet.replaceSync(css); } catch { return; }
    themeState.lookCss = css;
  };
  // Ключ чата, под которым окно хранит тему (раздел 2а): у главного окна это
  // id разговора (`id:local_…`), а пока id неизвестен — его имя.
  statusPart("chatKey", () => chatKey());
  // Ключ сессии — по ОКНУ: `main` у главного, `w:<заголовок>` у подчинённого.
  statusPart("sessionKey", () => sessionKey());
  // Тема и шрифт окна: что применено, под каким ключом хранится и откуда
  // взялось (session — своя сессия окна, window — карта по ключу, all —
  // запись «для всех»). У слоёв источники независимы.
  statusPart("theme", () => ({
    id: themeState.theme?.id ?? null,
    key: themeKey(),
    source: themeState.source,
  }));
  statusPart("font", () => ({
    id: themeState.font?.id ?? null,
    family: themeState.font?.family ?? null,
    mono: themeState.font?.mono ?? false,
    source: themeState.fontSource,
  }));
  // Размер текста сообщений: половинки независимы, любой может не быть.
  statusPart("size", () => ({
    answer: themeState.size?.answer ?? null,
    question: themeState.size?.question ?? null,
    source: themeState.sizeSource,
  }));
  // Оформление (WF83): три тумблера слоя look и откуда он взялся.
  statusPart("look", () => ({
    aurora: themeState.look?.aurora === true,
    neon: themeState.look?.neon === true,
    dense: themeState.look?.dense === true,
    // Схема живого фона (WF146): действующий id и список для меню Swift.
    scheme: lookScheme(themeState.look?.scheme).id,
    schemes: LOOK_SCHEMES.map(item => ({ id: item.id, name: item.name })),
    // Движение живого фона (#9994): live | still | image; нет живого фона — умолчание still.
    motion: lookMotion(themeState.look),
    source: themeState.lookSource,
  }));
  // true — в окне сейчас предпросмотр (мышь в подменю), и хранилище про эти
  // цвета ничего не знает: см. runThemeCommand.
  statusPart("preview", () => themeState.previewing);
  // Сырая запись карты по ключу окна — на гейте видно, что там лежит на
  // самом деле (в том числе запись старого формата `w:` и запись `main`).
  statusPart("raw", () => (() => {
    const key = themeKey();
    if (!key) return null;
    const map = readThemeMap();
    const legacy = legacyKey(key);
    return map[key] ?? (legacy != null ? map[legacy] ?? null : null);
  })());
  statusPart("rawMain", () => isMainWindow() ? readThemeMap()[THEME_MAIN_KEY] ?? null : null);
  HATCH && Object.assign(HATCH, { FADE_END_MASK, themeCss, epitaxyCss, fontCss, sizeCss, attachmentsCss, layoutCss,
    textJustifyOn, dockInsetFor, wideGapsFor, FEED_MIN, DOCK_INSET_MAX, DOCK_INSET_VARIABLE, WIDE_PANEL_MIN,
    SIDE_MIN, SIDE_FLOOR, SIDE_CHIN_GAP, CHIN_ROW_SELECTOR, SIDE_MAX_SHARE, TITLE_SIDE_ATTRIBUTE, TITLE_SHIFT_MAX,
    CORNER_SIDE_PROJECT_FONT, TITLE_COLUMN_FONT, WIDE_TILE, lookAuroraFrames, lookEase, LOOK_AURORA, LOOK_AURORA_CALM, LOOK_THEME_GLOW, LOOK_AURORA_FPS,
    normalizeTheme, normalizeFont, normalizeSize, normalizeSizeCommand, normalizeHex, mixHex, hslTriple, codeCss,
    codePalette, contrastRatio, readableOn, chatKey, chatIdKey, chatTitleKey, sameSessionKey, sessionKey, themeKey,
    legacyKey, mapEntry, entryLayer, readThemeMap, writeThemeMap, touchThemeMap, THEME_TITLE_STUBS, lookCss,
    normalizeLook, LOOK_SCHEMES, windowTitle });

