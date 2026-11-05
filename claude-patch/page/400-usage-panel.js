  // ---- 12ж. Панель лимитов по-русски (#6738, WF78) --------------------------
  // Слово Элвиса 20.09: окошко лимитов (открывается кружком контекста над полем
  // ввода) — «вся панель на русском без единого английского слова», цифры
  // короче, вместо «Plan usage limits» строка аккаунта, внизу новая полоса дней
  // недели, нижняя строка — «Статистика» (страница за ней остаётся английской).
  // Макет — файл 1 `docs/mockup-wf78-limits.html`, решения — MOCKUPS.md,
  // устройство панели — `docs/recon-wf78-usage-panel.md`.
  //
  // Панель рисует React, и трогать её можно ровно одним способом: менять
  // nodeValue УЖЕ СУЩЕСТВУЮЩЕГО текстового узла (так же, как раздел 14 сокращает
  // «3 minutes ago»). Присваивание textContent/innerHTML уничтожает старый узел,
  // а React держит на него ссылку в своём волокне: при закрытии панели он зовёт
  // removeChild того, чего там уже нет, — и дерево Claude рвётся. Узлов не
  // создаём, не удаляем и не переставляем; «спрятать» — своим атрибутом и
  // правилом в RULES (раздел 4), не style и не remove().
  //
  // Что написали — помним на самом элементе: …-lim-src английский оригинал,
  // …-lim-out наш текст. Проход: nodeValue === out → ничего не делаем; иначе
  // React вернул своё, разбираем заново от nodeValue. dispose() атрибуты
  // снимает, но текст назад НЕ откатывает: панель живёт секунды и пересоздаётся
  // при следующем открытии.
  //
  // Постоянного наблюдателя за body нет — он стоил бы второго комплекта записей
  // на каждую мутацию в каждом окне (раздел 9 про цену прохода). Панель
  // открывается кликом по кружку: ловим повод и ставим ВРЕМЕННОГО наблюдателя,
  // как openChromeWatch ждёт меню (раздел 12г), потом переезжаем на саму панель,
  // а страховка — один querySelector в heartbeatTick (раздел 16).
  //
  // Не опознали строку — не трогаем: родной английский лучше сломанного. Такие
  // строки считаются в status().usage.unknown, и это событие, а не норма.
  // USAGE_RING_SELECTOR — в разделе 1: его читает ещё и свёртка (раздел 6).
  const USAGE_PANEL_SELECTOR = '[role="dialog"][data-cds="Popover"]';
  // Опознание панели по УСТРОЙСТВУ, не по английскому тексту: цветной метр
  // контекста и ссылка на страницу статистики есть только у неё.
  const USAGE_METER_SELECTOR = '[data-cds="StackedMeter"]';
  const USAGE_LINK_SELECTOR = 'a[href="/settings/usage"]';
  // С Claude 2.42304 (#9978) полоса — role="meter", до того — progressbar.
  const USAGE_BAR_SELECTOR = '[role="progressbar"],[role="meter"]';
  const USAGE_ACCOUNT_SELECTOR = 'button[data-testid="user-menu-button"]';
  const USAGE_SRC_ATTRIBUTE = "data-myclaude-lim-src";
  const USAGE_OUT_ATTRIBUTE = "data-myclaude-lim-out";
  const USAGE_HIDE_ATTRIBUTE = "data-myclaude-lim-hide";
  const USAGE_WEEK_ATTRIBUTE = "data-myclaude-week";
  // Метка опознанной панели (#7064): по ней правило в RULES делает дорожки полос видимыми на
  // любой теме. Ставится только на панель, которую мы уже разобрали, снимается в dispose().
  const USAGE_PANEL_ATTRIBUTE = "data-myclaude-lim-panel";
  const USAGE_WEEK_ON = "data-myclaude-week-on";
  // Имя аккаунта: кнопка с ним есть только в ГЛАВНОМ окне и только при открытой
  // боковой панели, а localStorage у окон Claude общий — главное окно кладёт имя
  // сюда, попапы читают. Наружу (status, probe-result.json, журналы) имя не
  // уходит: эти файлы лежат на диске и их читают агенты.
  const USAGE_ACCOUNT_KEY = "myclaude-account-v1";
  const USAGE_ACCOUNT_MAX = 40;
  // Сколько ждём панель после клика по кружку — как меню в 12г.
  const USAGE_WAIT_MS = 1500;
  // Время сброса считается от «сейчас» и на границе минуты прыгало бы туда-сюда:
  // пока новый ответ ближе этого к запомненному, держим запомненный.
  const USAGE_STEADY_MS = 90000;
  const USAGE_WEEK_PARTS = 7;
  const USAGE_DAYS = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"];
  const USAGE_WEEKDAYS = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6 };
  // Процент лимита отдельным узлом справа. У 5-часового он спрятан (слово
  // Элвиса 20.09: «только полоса»), у недельных с 21.09 уезжает в конец строки
  // сброса через длинное тире — «Пт 08:00 — 92%», как у 5-часового «11 мин — в 14:10».
  // С 2.42304 — «5% used» (#9978): «used» срезаем, процент остаётся.
  // #11618: русский Claude пишет «Использовано 5%» / «Использовано: 5%» — приставку срезаем так же.
  const USAGE_PERCENT_RE = /^\s*(?:использовано:?\s*)?\d+(?:[.,]\d+)?\s*%(?:\s+used)?\s*$/i;
  // Словарь панели. Отдельного слоя, конфига и файла с текстами не заводим
  // (правило «Раздувание»): десяток строк живёт прямо здесь. Совпадение точное —
  // чего в словаре нет, остаётся как есть.
  const USAGE_WORDS = new Map([
    ["Context window", "Контекст"],
    ["See detailed breakdown", "Статистика"],
    // Раскрытый «Контекст» (шеврон): список долей внутри панели.
    ["Messages", "Сообщения"],
    ["System tools", "Системные инструменты"],
    ["MCP tools", "Инструменты MCP"],
    ["Memory files", "Файлы памяти"],
    ["Other", "Прочее"],
    ["Autocompact buffer", "Запас автосжатия"],
    ["System prompt", "Системный промпт"],
    ["Free space", "Свободно"],
    ["MCP tools (deferred)", "Инструменты MCP (отложенные)"],
    ["System tools (deferred)", "Системные инструменты (отложенные)"],
    ["Usage", "Расход"],
    ["Skills", "Скиллы"],
    ["Custom agents", "Свои агенты"],
    // #11618: русский Claude — те же строки по каталогу claude.ai (совпавшие с нашими не повторяем).
    ["Контекстное окно", "Контекст"],
    ["Посмотреть подробную разбивку", "Статистика"],
    ["Другое", "Прочее"],
    ["Использование", "Расход"],
    ["Собственные агенты", "Свои агенты"],
  ]);
  // Потолок множества нераспознанных строк: страница живёт часами, а панель
  // может смениться не раз — расти без края этому счётчику незачем.
  const USAGE_UNKNOWN_MAX = 20;
  const usageState = {
    observer: null, timer: 0, panel: null,
    // Наведение на кружок (#6906): hoverOpen — панель открыли мы, pinned —
    // Элвис нажал рукой и панель держится до следующего нажатия.
    hoverTimer: 0, leaveTimer: 0, hoverOpen: false, pinned: false, over: false,
    opens: 0, swaps: 0, week: false,
    // Контекст чата от приложения (#9978): {chat, tokens}; спрошен не чаще USAGE_CONTEXT_ASK_MS
    // (contextChat — о каком чате спросили последним).
    context: null, contextAsked: 0, contextChat: "",
    // Нераспознанные строки — множеством: счётчик «сколько раз» рос бы каждым
    // проходом и ничего не значил. Сами строки наружу не отдаём, только число.
    unknown: new Set(),
    // Устоявшиеся моменты сброса по видам лимитов — от дрожи «в 01:25».
    resets: new Map(),
  };

  // ---- чистые разборы (тестируются через люк) ----
  const usageTwo = value => String(value).padStart(2, "0");
  const usageClock = at => {
    const point = new Date(at);
    return `${usageTwo(point.getHours())}:${usageTwo(point.getMinutes())}`;
  };
  // «324.7k / 1M (32%)» → «325k / 1M (32%)»: тысячи без десятых, миллионы как
  // есть. Проценты и косая не трогаются.
  const usageNumber = text => String(text ?? "")
    .replace(/(\d+(?:[.,]\d+)?)k/g, (all, num) => `${Math.round(Number(String(num).replace(",", ".")))}k`);
  // «4 hr 9 min», «2 hr», «59 min», «1 day 3 hr», «2 days», «tomorrow» → минуты.
  // Разобрали не всё — null: незнакомую строку лучше оставить английской.
  // #11618: и русские «3 ч 49 мин», «2 дн.», «1 день» (каталог: {n} ч, {n} мин, {n} дн., # день/дня/дней);
  // \b кириллицу не видит — конец слова через lookahead.
  const USAGE_SPAN_RE = /(\d+(?:\.\d+)?)\s*(days?|d|hours?|hrs?|h|minutes?|mins?|m|дн\.?|дней|дня|день|ч|мин)(?![\wа-яё])/g;
  const usageMinutes = text => {
    const raw = String(text ?? "").trim().toLowerCase();
    if (!raw) return null;
    if (raw === "tomorrow" || raw === "завтра") return 24 * 60;
    let total = 0;
    let found = false;
    USAGE_SPAN_RE.lastIndex = 0;
    for (let match = USAGE_SPAN_RE.exec(raw); match; match = USAGE_SPAN_RE.exec(raw)) {
      const value = Number(match[1]);
      if (!Number.isFinite(value)) return null;
      if (/^[dд]/.test(match[2])) total += value * 24 * 60;
      else if (/^[hч]/.test(match[2])) total += value * 60;
      else total += value;
      found = true;
    }
    if (!found) return null;
    // Осталось что-то, кроме разобранных кусков и пробелов, — значит это не та
    // строка, которую мы понимаем.
    if (raw.replace(USAGE_SPAN_RE, " ").replace(/[\s,]+/g, "")) return null;
    return Math.round(total);
  };
  // «Fri 8:00 AM» → {day:5,hour:8,minute:0}; «12:00 AM» → полночь (00:00), а не
  // полдень — на этой ловушке и ломаются разборы AM/PM.
  const usageClockParts = text => {
    const match = /^(?:(sun|mon|tue|wed|thu|fri|sat)[a-z]*\.?\s+)?(\d{1,2}):(\d{2})\s*(am|pm)?$/i.exec(String(text ?? "").trim());
    if (!match) return null;
    let hour = Number(match[2]);
    const minute = Number(match[3]);
    if (minute > 59) return null;
    const suffix = match[4] ? match[4].toLowerCase() : "";
    if (suffix) {
      if (hour < 1 || hour > 12) return null;
      hour = (hour % 12) + (suffix === "pm" ? 12 : 0);
    } else if (hour > 23) return null;
    return { day: match[1] ? USAGE_WEEKDAYS[match[1].slice(0, 3).toLowerCase()] : null, hour, minute };
  };
  // Ближайший БУДУЩИЙ момент «день недели + время» от base. Дни прибавляются
  // календарно (setDate), чтобы перевод стрелок не сдвигал час.
  const usageNext = (parts, base) => {
    const at = new Date(base);
    at.setHours(parts.hour, parts.minute, 0, 0);
    if (parts.day == null) {
      if (at.getTime() <= base) at.setDate(at.getDate() + 1);
      return at.getTime();
    }
    let shift = (parts.day - at.getDay() + 7) % 7;
    if (shift === 0 && at.getTime() <= base) shift = 7;
    at.setDate(at.getDate() + shift);
    return at.getTime();
  };
  // Короткая длительность, как в правой колонке панели: «4 ч 9 мин», «59 мин»,
  // «2 ч», «1 день 3 ч», «2 дня».
  const usageShort = minutes => {
    const total = Math.max(0, Math.round(minutes));
    const days = Math.floor(total / (24 * 60));
    const hours = Math.floor((total - days * 24 * 60) / 60);
    const mins = total - days * 24 * 60 - hours * 60;
    const parts = [];
    if (days) parts.push(`${days} ${usagePlural(days, "день", "дня", "дней")}`);
    if (hours) parts.push(`${hours} ч`);
    // Минуты при сутках не пишем: такой интервал Claude и сам даёт с точностью
    // до дня, и «2 дня 17 мин» обещало бы точность, которой нет.
    if (!days && mins) parts.push(`${mins} мин`);
    return parts.length ? parts.join(" ") : "меньше минуты";
  };
  // Длительность словами — для своей строки над полосой недели: «3 дня
  // 6 часов», «1 день 1 час», «5 часов 20 минут».
  const usageLong = minutes => {
    const total = Math.max(0, Math.round(minutes));
    const days = Math.floor(total / (24 * 60));
    const hours = Math.floor((total - days * 24 * 60) / 60);
    const mins = total - days * 24 * 60 - hours * 60;
    const parts = [];
    if (days) parts.push(`${days} ${usagePlural(days, "день", "дня", "дней")}`);
    if (hours) parts.push(`${hours} ${usagePlural(hours, "час", "часа", "часов")}`);
    if (!days && mins) parts.push(`${mins} ${usagePlural(mins, "минута", "минуты", "минут")}`);
    return parts.length ? parts.join(" ") : "меньше минуты";
  };
  // Подпись блока лимита. kind нужен, чтобы спрятать процент у 5-часового и
  // взять неделю из строки «all models»: «Weekly · X» → «X».
  const usageLabel = text => {
    const raw = String(text ?? "").trim();
    // #11618: русские подписи по каталогу claude.ai; «5-часового лимита» — из кружка «4% от 5-часового лимита» (12ж¹).
    if (/^(?:(?:5-hour|session) limit|5-часовой лимит|лимит на 5 часов|5-часового лимита)$/i.test(raw)) return { kind: "hour5", text: "5-часовой" };
    if (/^(?:weekly(?: limit)?|недельный лимит|еженедельно)$/i.test(raw)) return { kind: "weekAll", text: "Недельный" };
    const weekly = /^(?:weekly|еженедельно)\s*·\s*(.+)$/i.exec(raw);
    if (!weekly) return null;
    const rest = weekly[1].trim();
    if (/^(?:all models|все модели)$/i.test(rest)) return { kind: "weekAll", text: "Недельный" };
    return rest ? { kind: "week", text: rest } : null;
  };
  // Шапка лимитов: «Plan usage limits · Max (20x)» → «Alex · Max 20x».
  // Имени нет — «Max 20x» без имени; нет и тарифа — строку не трогаем вовсе.
  const usageHead = (text, name) => {
    const match = /^(?:plan usage limits|лимиты использования плана)(?:\s*·\s*(.+))?$/i.exec(String(text ?? "").trim());
    if (!match) return null;
    const plan = String(match[1] ?? "").replace(/\s*\(([^)]*)\)\s*$/, " $1").trim();
    const parts = [String(name ?? "").trim(), plan].filter(Boolean);
    return parts.length ? parts.join(" · ") : null;
  };
  // Правая часть блока лимита. Возвращает момент сброса (at), интервал в
  // минутах, признак «крупность в сутки» и готовый текст для форм, где времени
  // считать не надо. Незнакомая форма — null.
  const usageReset = (text, base) => {
    const raw = String(text ?? "").trim();
    // #11618: русские формы по каталогу: «Лимит достигнут», «сброс через {left}», «Сброс в {time}», «Сброс: {time}».
    if (/^(?:limit reached|лимит достигнут)$/i.test(raw)) return { at: null, minutes: null, rough: true, fixed: "Лимит исчерпан" };
    const inside = /^(?:resets?\s+in|сброс\s+через)\s+(.+)$/i.exec(raw);
    if (inside) {
      const minutes = usageMinutes(inside[1]);
      if (minutes == null) return null;
      // Сутки и больше Claude даёт крупностью в день («Resets in 2 days»), то
      // есть момент известен с точностью ±12 часов: часы сброса из него не
      // вытащить, и мы их не пишем — иначе панель врёт уверенным голосом.
      return { at: base + minutes * 60000, minutes, rough: minutes >= 24 * 60, fixed: null };
    }
    const rest = /^(?:resets?|сброс:?)\s+(.+)$/i.exec(raw);
    if (!rest) return null;
    let tail = rest[1].trim();
    const when = /^(today|tomorrow|сегодня|завтра)(?![\wа-яё])(?:\s+(?:at|в)(?![\wа-яё]))?\s*(.*)$/i.exec(tail);
    if (when) {
      const shift = /^(?:tomorrow|завтра)$/i.test(when[1]) ? 1 : 0;
      const word = shift ? "завтра" : "сегодня";
      tail = when[2].trim().replace(/^(?:at|в)\s+/i, "");
      if (!tail) return { at: null, minutes: null, rough: true, fixed: word };
      const parts = usageClockParts(tail);
      if (!parts) return null;
      const at = new Date(base);
      at.setDate(at.getDate() + shift);
      at.setHours(parts.hour, parts.minute, 0, 0);
      return { at: at.getTime(), minutes: null, rough: false, fixed: `${word} в ${usageTwo(parts.hour)}:${usageTwo(parts.minute)}` };
    }
    const parts = usageClockParts(tail.replace(/^(?:at|в)\s+/i, ""));
    if (!parts) return null;
    const at = usageNext(parts, base);
    const clock = `${usageTwo(parts.hour)}:${usageTwo(parts.minute)}`;
    return {
      at, minutes: null, rough: false,
      fixed: parts.day == null ? `в ${clock}` : `${USAGE_DAYS[parts.day]} ${clock}`,
    };
  };
  // Семь суток до сброса: доля каждого дня, подписи и какой день идёт сейчас.
  // Границы календарные (setDate), а не «минус 24 часа»: у того, кто живёт с
  // переводом стрелок, сетка иначе съезжает на час.
  const usageWeekParts = (at, now) => {
    const edges = [];
    for (let step = USAGE_WEEK_PARTS; step >= 0; step -= 1) {
      const point = new Date(at);
      point.setDate(point.getDate() - step);
      edges.push(point);
    }
    const fills = [];
    const days = [];
    let on = -1;
    for (let index = 0; index < USAGE_WEEK_PARTS; index += 1) {
      const from = edges[index].getTime();
      const to = edges[index + 1].getTime();
      const span = to - from;
      fills.push(span > 0 ? Math.max(0, Math.min(1, (now - from) / span)) : 0);
      days.push(USAGE_DAYS[edges[index].getDay()]);
      if (now >= from && now < to) on = index;
    }
    return { fills, days, on };
  };
  // Имя аккаунта из кнопки левого меню. На входе — тексты её листьев: буква
  // аватара и имя чаще лежат отдельными узлами («E», «Alex», «·», «Max»),
  // но бывают и слитно («AAlex·Max»). Слитную первую букву срезаем ТОЛЬКО
  // когда она повторяет вторую: у имени «Anna» отъели бы букву ни за что.
  // Аватар — это ИНИЦИАЛЫ, а не одна буква (#7203: в шапке стояло «AP»
  // вместо «Anna Petrova»): до трёх заглавных букв. Слитные инициалы срезаем,
  // только когда они — первые буквы слов имени за ними. Одни инициалы (боковая
  // панель свёрнута, имени не видно) — не имя: отдаём "", и прежнее имя в
  // хранилище не затирается.
  const USAGE_INITIALS_RE = /^\p{Lu}{1,3}$/u;
  const usageInitialsOf = (initials, name) => {
    const heads = String(name).split(/\s+/).filter(Boolean).map(word => word[0]).join("").slice(0, initials.length);
    return heads.toLowerCase() === initials.toLowerCase();
  };
  const usageAccountName = parts => {
    const list = (Array.isArray(parts) ? parts : [parts]).map(item => String(item ?? "").trim()).filter(Boolean);
    if (!list.length) return "";
    const split = list.length > 1 && USAGE_INITIALS_RE.test(list[0]);
    let name = split ? list[1] : list[0];
    const dot = name.indexOf("·");
    if (dot >= 0) name = name.slice(0, dot);
    name = name.trim();
    if (!split) {
      for (let size = 3; size >= 1; size -= 1) {
        const head = name.slice(0, size);
        const rest = name.slice(size);
        if (rest.length >= 2 && USAGE_INITIALS_RE.test(head) && usageInitialsOf(head, rest)) { name = rest; break; }
      }
    }
    if (USAGE_INITIALS_RE.test(name) && name.length > 1) return "";
    return name.trim().slice(0, USAGE_ACCOUNT_MAX);
  };

  // ---- узлы панели ----
  // Лист — элемент, у которого РОВНО один текстовый ребёнок и ни одного
  // элемента. Всё прочее — «не опознали»: смешанное содержимое мы не разбираем.
  // Текстовые узлы листа. Живая проба гейта 21.09: шапку лимитов React держит ТРЕМЯ
  // текстовыми узлами («Plan usage limits», « · », «Max (20x)») — лист тот, у кого нет
  // детей-элементов; читаем склейку, пишем всё в первый узел, остальным — пусто.
  const usageTextNodes = element => {
    const out = [];
    const kids = element?.childNodes;
    if (!kids) return out;
    for (let index = 0; index < kids.length; index += 1) {
      const kid = kids[index];
      if (kid.nodeType === 1) return [];
      if (kid.nodeType === 3) out.push(kid);
    }
    return out;
  };
  const usageTextNode = element => usageTextNodes(element)[0] ?? null;
  const usageTextRead = element => usageTextNodes(element).map(node => String(node.nodeValue ?? "")).join("");
  const usageLeaves = root => {
    const out = [];
    const walk = node => {
      const kids = node?.childNodes;
      if (!kids) return;
      for (let index = 0; index < kids.length; index += 1) {
        const kid = kids[index];
        if (kid.nodeType !== 1) continue;
        // Свою полосу недели не обходим: её текст наш и разбирать его нечем.
        if (kid.hasAttribute?.(USAGE_WEEK_ATTRIBUTE)) continue;
        if (usageTextNode(kid)) out.push(kid);
        else walk(kid);
      }
    };
    walk(root);
    return out;
  };
  // Английский оригинал этого листа: запомненный (мы уже писали сюда, и текст с
  // тех пор не менялся) или то, что лежит в узле сейчас.
  const usageRaw = element => {
    const node = usageTextNode(element);
    if (!node) return null;
    const value = usageTextRead(element);
    if (element.getAttribute(USAGE_OUT_ATTRIBUTE) !== value) return value;
    const src = element.getAttribute(USAGE_SRC_ATTRIBUTE);
    return src == null ? value : src;
  };
  const usageWrite = (element, src, out) => {
    const node = usageTextNode(element);
    if (!node || out == null) return;
    if (usageTextRead(element) !== out) {
      const nodes = usageTextNodes(element);
      nodes.forEach((each, index) => { each.nodeValue = index === 0 ? out : ""; });
      usageState.swaps += 1;
    }
    if (element.getAttribute(USAGE_SRC_ATTRIBUTE) !== src) element.setAttribute(USAGE_SRC_ATTRIBUTE, src);
    if (element.getAttribute(USAGE_OUT_ATTRIBUTE) !== out) element.setAttribute(USAGE_OUT_ATTRIBUTE, out);
  };
  // Текст СВОЕГО узла (полоса недели): у него ни оригинала, ни атрибутов.
  const usageOwnText = (element, text) => {
    const node = usageTextNode(element);
    if (node && String(node.nodeValue ?? "") !== text) node.nodeValue = text;
  };
  // «Не разобрали» — событие, а не норма: строку оставляем английской, но
  // считаем. Само слово наружу не отдаём (status() ложится на диск).
  const usageUnknown = text => {
    const value = String(text ?? "").trim();
    if (value && usageState.unknown.size < USAGE_UNKNOWN_MAX) usageState.unknown.add(value);
  };
  const usageHide = (element, hidden) => {
    if (!element) return;
    if (hidden) { if (!element.hasAttribute(USAGE_HIDE_ATTRIBUTE)) element.setAttribute(USAGE_HIDE_ATTRIBUTE, ""); }
    else if (element.hasAttribute(USAGE_HIDE_ATTRIBUTE)) element.removeAttribute(USAGE_HIDE_ATTRIBUTE);
  };
  // Примет две: ссылка на страницу статистики и хоть одна полоса. Метр цветных
  // долей контекста был обязательным до 21.09 — и в ПУСТОМ чате панель
  // оставалась английской (слово Элвиса 21.09: «если чат новенький, окошко
  // старое»): пока разговора нет, строка контекста рисуется простой полосой без
  // долей, и метра в панели нет вовсе (живая проба 21.09, главное окно).
  const usagePanelOk = panel => {
    if (!panel?.isConnected) return false;
    try {
      if (!panel.querySelector(USAGE_LINK_SELECTOR)) return false;
      return Boolean(panel.querySelector(USAGE_METER_SELECTOR) || panel.querySelector(USAGE_BAR_SELECTOR));
    } catch { return false; }
  };
  const usagePanelIn = node => {
    if (!node || node.nodeType !== 1) return null;
    try {
      const panel = node.matches(USAGE_PANEL_SELECTOR) ? node : node.querySelector(USAGE_PANEL_SELECTOR);
      return usagePanelOk(panel) ? panel : null;
    } catch { return null; }
  };
  const usageFind = () => {
    try {
      for (const panel of document.querySelectorAll(USAGE_PANEL_SELECTOR)) {
        if (usagePanelOk(panel)) return panel;
      }
    } catch {}
    return null;
  };
  // Блоки лимитов — по устройству: у каждого внутри своя полоса, а подпись
  // названа её aria-labelledby. Классы Claude перегенерирует каждый релиз, и
  // держаться за них нельзя.
  const usageBlocks = panel => {
    const out = [];
    let bars = [];
    try { bars = [...panel.querySelectorAll(USAGE_BAR_SELECTOR)]; } catch { return out; }
    for (const bar of bars) {
      let block = bar.parentElement;
      if (!block) continue;
      const named = bar.getAttribute("aria-labelledby");
      let label = null;
      try { label = named ? block.querySelector(`[id="${named}"]`) : null; } catch {}
      if (!label) { try { label = block.querySelector("span[id]"); } catch {} }
      // С 2.42304 (#9978) полоса сидит в своей обёртке, подпись — уровнем-двумя
      // выше: блок — ближайший предок с подписью, только по aria-labelledby
      // (span[id] там же — строка сброса, её за подпись не брать).
      for (let up = 0; !label && named && up < 3 && block.parentElement && block.parentElement !== panel; up += 1) {
        block = block.parentElement;
        try { label = block.querySelector(`[id="${named}"]`); } catch {}
      }
      const row = label?.parentElement ?? null;
      if (!label || !row) continue;
      // Строка сброса с 2.42304 — вне строки подписи, под полосой (aria-describedby).
      const described = bar.getAttribute("aria-describedby");
      let desc = null;
      try { desc = described ? block.querySelector(`[id="${described}"]`) : null; } catch {}
      if (desc && row.contains(desc)) desc = null;
      out.push({ block, bar, label, row, desc });
    }
    return out;
  };
  // Момент сброса устаивается: пока новый ответ рядом с запомненным, держим
  // запомненный — иначе «в 01:25» дёргается на минуту при каждой перерисовке.
  // Момент привязан к СТРОКЕ, из которой посчитан (проверка WF78, блокер 1): React
  // строку не перерисовал — время сброса не двигается, сколько бы панель ни была
  // открыта; иначе «в 01:25» уползало вперёд вместе с часами каждые 90 с.
  const usageSteady = (key, src, at) => {
    const kept = usageState.resets.get(key);
    if (kept && kept.src === src) return kept.at;
    const held = kept && Math.abs(at - kept.at) <= USAGE_STEADY_MS ? kept.at : at;
    usageState.resets.set(key, { src, at: held });
    return held;
  };
  // Старое «AK», записанное до #7203, за имя не считаем.
  const usageAccountRead = () => {
    let value = "";
    try { value = String(localStorage.getItem(USAGE_ACCOUNT_KEY) ?? "").slice(0, USAGE_ACCOUNT_MAX); } catch { return ""; }
    return value.length > 1 && USAGE_INITIALS_RE.test(value) ? "" : value;
  };
  // Главное окно перезаписывает имя на каждом круге сторожа: аккаунт меняют и
  // из него выходят, а ключ пережил бы и то и другое.
  const usageAccountSave = () => {
    if (!isMainWindow()) return;
    let button = null;
    try { button = document.querySelector(USAGE_ACCOUNT_SELECTOR); } catch {}
    if (!button) return;
    const own = usageTextNode(button);
    const parts = own
      ? [String(own.nodeValue ?? "")]
      : usageLeaves(button).map(node => String(usageTextNode(node)?.nodeValue ?? ""));
    const name = usageAccountName(parts.length ? parts : [String(button.textContent ?? "")]);
    if (!name) return;
    try { if (localStorage.getItem(USAGE_ACCOUNT_KEY) !== name) localStorage.setItem(USAGE_ACCOUNT_KEY, name); } catch {}
  };

  // ---- полоса недели ----
  // Единственное, что мы в панели РИСУЕМ: строка «Сброс через 3 дня 6 часов» и
  // под ней семь отрезков по дням лимитной недели. Одежду (классы) снимаем с
  // родных блоков, чтобы полоса была той же высоты и того же цвета: свои числа
  // тут врали бы с первым же релизом Claude.
  const usageWeekSkin = blocks => {
    const last = blocks[blocks.length - 1];
    const fills = blocks.map(item => item.bar.firstElementChild).filter(Boolean);
    const fill = fills.find(node => /accent/.test(String(node.className ?? ""))) ?? fills[0] ?? null;
    // Правая колонка (слово Элвиса 21.09: «шрифт сделай тоненький, как справа»):
    // одежду берём с ГРУППЫ справа в родной строке — это она держит и размер, и
    // приглушённый цвет. Лист там последний (процент или время), группа — его
    // родитель; лежит лист прямо в строке — значит группы нет, и берём его.
    const leaves = usageLeaves(last.row);
    const tail = leaves[leaves.length - 1] ?? null;
    const group = tail && tail.parentElement && tail.parentElement !== last.row ? tail.parentElement : tail;
    return {
      block: String(last.block.className ?? ""),
      row: String(last.row.className ?? ""),
      title: String(last.label.className ?? ""),
      value: String(group?.className ?? ""),
      track: String(last.bar.className ?? ""),
      fill: String(fill?.className ?? ""),
    };
  };
  const usageWeekBox = (panel, blocks) => {
    const last = blocks[blocks.length - 1];
    const host = last.block.parentElement;
    if (!host?.isConnected) return null;
    let box = null;
    try { box = panel.querySelector(`[${USAGE_WEEK_ATTRIBUTE}="block"]`); } catch {}
    if (box && box.parentElement !== host) { box.remove(); box = null; }
    // Коробка от прежнего инжекта без правого узла (до 21.09 срок стоял в самом
    // слове «Сброс») — пересобираем: дописать узел в чужую по возрасту коробку
    // стоило бы отдельной ветки, а живёт она секунды.
    if (box && !box.querySelector(`[${USAGE_WEEK_ATTRIBUTE}="value"]`)) { box.remove(); box = null; }
    if (box) {
      // Строка лимита доехала после коробки (Fable) — «Сброс» всё равно последний (слово 03.11.2026: «Сброс должен внизу быть»).
      if (last.block.nextSibling !== box) host.insertBefore(box, last.block.nextSibling);
      return box;
    }
    const skin = usageWeekSkin(blocks);
    const make = (tag, kind, className) => {
      const node = document.createElement(tag);
      node.setAttribute(USAGE_WEEK_ATTRIBUTE, kind);
      if (className) node.className = className;
      return node;
    };
    box = make("div", "block", skin.block);
    // VoiceOver про полосу молчит: родные строки и так называют сброс, а наша
    // читалась бы семью пустыми отрезками (как полоса прогресса, раздел 2б).
    box.setAttribute("aria-hidden", "true");
    const row = make("div", "row", skin.row);
    const title = make("span", "title", skin.title);
    title.appendChild(document.createTextNode(""));
    row.appendChild(title);
    const value = make("span", "value", skin.value);
    value.appendChild(document.createTextNode(""));
    row.appendChild(value);
    box.appendChild(row);
    const bar = make("div", "bar", "");
    const days = make("div", "days", "");
    for (let index = 0; index < USAGE_WEEK_PARTS; index += 1) {
      const cell = make("div", "cell", skin.track);
      cell.appendChild(make("div", "fill", skin.fill));
      bar.appendChild(cell);
      const day = make("span", "day", "");
      day.appendChild(document.createTextNode(""));
      days.appendChild(day);
    }
    box.appendChild(bar);
    box.appendChild(days);
    host.insertBefore(box, last.block.nextSibling);
    return box;
  };
  const usageWeekClear = panel => {
    try {
      for (const node of panel.querySelectorAll(`[${USAGE_WEEK_ATTRIBUTE}="block"]`)) node.remove();
    } catch {}
  };
  const usageWeekDraw = (panel, blocks, week, base) => {
    // CSP не пустила наш <style> — полоса вылезла бы неоформленным блоком
    // посреди панели; без недельной строки её не от чего считать.
    if (!state.cssOk || !blocks.length || week?.at == null) { usageWeekClear(panel); return false; }
    const box = usageWeekBox(panel, blocks);
    if (!box) return false;
    const parts = usageWeekParts(week.at, base);
    const minutes = Math.round((week.at - base) / 60000);
    let title = null;
    let value = null;
    let fills = [];
    let days = [];
    try {
      title = box.querySelector(`[${USAGE_WEEK_ATTRIBUTE}="title"]`);
      value = box.querySelector(`[${USAGE_WEEK_ATTRIBUTE}="value"]`);
      fills = [...box.querySelectorAll(`[${USAGE_WEEK_ATTRIBUTE}="fill"]`)];
      days = [...box.querySelectorAll(`[${USAGE_WEEK_ATTRIBUTE}="day"]`)];
    } catch { return false; }
    // Слово слева, срок справа — как в родных строках лимитов (слово Элвиса
    // 21.09). До этого вся фраза стояла слева одним куском.
    if (title) usageOwnText(title, "Сброс");
    if (value) usageOwnText(value, minutes > 0 ? usageLong(minutes) : "вот-вот");
    for (let index = 0; index < fills.length; index += 1) {
      const width = `${Math.round((parts.fills[index] ?? 0) * 1000) / 10}%`;
      if (fills[index].style.getPropertyValue("width") !== width) fills[index].style.setProperty("width", width);
    }
    // Подписи дней — ТОЛЬКО когда неделя пришла абсолютным моментом («Resets Fri
    // 8:00 AM»). Из интервала («Resets in 2 days») день сброса известен с
    // точностью до суток, и все семь подписей врали бы разом: молча врущая
    // полоса хуже полосы без подписей (макет, вариант 2).
    const row = days[0]?.parentElement ?? null;
    if (row) {
      const hidden = week.rough ? "none" : "";
      if (row.style.getPropertyValue("display") !== hidden) {
        if (hidden) row.style.setProperty("display", hidden);
        else row.style.removeProperty("display");
      }
    }
    for (let index = 0; index < days.length; index += 1) {
      usageOwnText(days[index], week.rough ? "" : (parts.days[index] ?? ""));
      const on = !week.rough && index === parts.on;
      if (on) { if (days[index].getAttribute(USAGE_WEEK_ON) !== "true") days[index].setAttribute(USAGE_WEEK_ON, "true"); }
      else if (days[index].hasAttribute(USAGE_WEEK_ON)) days[index].removeAttribute(USAGE_WEEK_ON);
    }
    return true;
  };

  // ---- свои строки: контекст и Fable (#9978) ----
  // Claude 2.42304 убрал из панели строку контекста и недельный лимит Fable (слово
  // Элвиса 16.10: «Раньше там… писалось контекстное окно, сколько, потом… фейбол
  // писался… А сейчас стало не так»). Рисуем их сами в одежде родного блока:
  // Fable — из лимитов 12ж¹ (запрос /usage главного окна или его кэш), контекст —
  // от приложения (команда chat-context на запрос /context, как у отсчёта
  // отправки, раздел 12о). Есть родная строка — своей нет.
  const USAGE_CONTEXT_WINDOW = 1000000;
  const USAGE_CONTEXT_ASK_MS = 5000;
  const usageRowBox = (panel, blocks, kind, place) => {
    const host = blocks[blocks.length - 1].block.parentElement;
    if (!host?.isConnected) return null;
    let box = null;
    try { box = panel.querySelector(`[${USAGE_WEEK_ATTRIBUTE}="row-${kind}"]`); } catch {}
    if (box && box.parentElement !== host) { box.remove(); box = null; }
    if (!box) {
      const skin = usageWeekSkin(blocks);
      const make = (tag, part, className) => {
        const node = document.createElement(tag);
        node.setAttribute(USAGE_WEEK_ATTRIBUTE, part);
        if (className) node.className = className;
        return node;
      };
      box = make("div", `row-${kind}`, skin.block);
      const row = make("div", "row", skin.row);
      for (const [part, className] of [["title", skin.title], ["value", skin.value]]) {
        const node = make("span", part, className);
        node.appendChild(document.createTextNode(""));
        row.appendChild(node);
      }
      box.appendChild(row);
      const cell = make("div", "cell", skin.track);
      cell.appendChild(make("div", "fill", skin.fill));
      box.appendChild(cell);
      // Строка под полосой — одежда родной строки сброса (есть только с 2.42304).
      const note = make("span", "note", blocks.find(block => block.desc)?.desc.className ?? "");
      note.appendChild(document.createTextNode(""));
      box.appendChild(note);
    }
    // Место: контекст — над лимитами, Fable — под полосой недели (как в панели у часов).
    const placed = box.parentElement === host && (place === "top" ? box.nextSibling === blocks[0].block : place.nextSibling === box);
    if (!placed) host.insertBefore(box, place === "top" ? blocks[0].block : place.nextSibling);
    return box;
  };
  const usageRowPaint = (box, title, value, pct, note = "") => {
    try {
      usageOwnText(box.querySelector(`[${USAGE_WEEK_ATTRIBUTE}="title"]`), title);
      usageOwnText(box.querySelector(`[${USAGE_WEEK_ATTRIBUTE}="value"]`), value);
      const under = box.querySelector(`[${USAGE_WEEK_ATTRIBUTE}="note"]`);
      usageOwnText(under, note);
      if (under) usageHide(under, !note);
      const fill = box.querySelector(`[${USAGE_WEEK_ATTRIBUTE}="fill"]`);
      const width = `${Math.max(0, Math.min(100, Math.round(pct)))}%`;
      if (fill && fill.style.getPropertyValue("width") !== width) fill.style.setProperty("width", width);
    } catch {}
  };
  const usageRowDrop = (panel, kind) => {
    try { panel.querySelector(`[${USAGE_WEEK_ATTRIBUTE}="row-${kind}"]`)?.remove(); } catch {}
  };
  // gap — зазор с прошлым запросом о том же чате (кружок, раздел 12з², задаёт свой); о другом чате — сразу.
  // true — запрос ушёл.
  const usageContextAsk = (gap = USAGE_CONTEXT_ASK_MS) => {
    let chat = "";
    try { chat = myChatId() || ""; } catch {}
    const now = Date.now();
    if (!chat || typeof fetch !== "function" || (chat === usageState.contextChat && now - usageState.contextAsked < gap)) return false;
    usageState.contextAsked = now;
    usageState.contextChat = chat;
    try {
      fetch(`http://127.0.0.1:${HTML_CHROME_PORT}/context?chat=${encodeURIComponent(chat)}`, { mode: "cors", credentials: "omit", cache: "no-store" })
        .catch(() => {});
    } catch {}
    return true;
  };
  const usageContextTake = detail => {
    const chat = typeof detail?.chat === "string" ? detail.chat : "";
    const tokens = Number(detail?.tokens);
    if (!chat || chat !== myChatId() || !Number.isFinite(tokens) || tokens <= 0) return;
    usageState.context = { chat, tokens: Math.round(tokens) };
    if (usageState.panel?.isConnected) { try { usageApply(usageState.panel); } catch {} }
  };
  const usageExtras = (panel, blocks) => {
    if (!state.cssOk || !blocks.length) { usageRowDrop(panel, "context"); usageRowDrop(panel, "fable"); return; }
    const names = blocks.map(block => String(usageRaw(block.label) ?? ""));
    const ownContext = usageLeaves(panel).some(leaf => /^(?:context window|контекстное окно)$/i.test(String(usageRaw(leaf) ?? "").trim()));
    let chat = "";
    try { chat = myChatId() || ""; } catch {}
    const context = usageState.context && usageState.context.chat === chat ? usageState.context.tokens : null;
    // Раскладка 2.42304: число справа, подробность под полосой; прежняя — всё справа.
    const under = blocks.some(block => block.desc);
    if (ownContext || context == null) usageRowDrop(panel, "context");
    else {
      const pct = context / USAGE_CONTEXT_WINDOW * 100;
      const box = usageRowBox(panel, blocks, "context", "top");
      const size = `${Math.round(context / 1000)}k из 1M`;
      if (box) {
        if (under) usageRowPaint(box, "Контекст", `${Math.round(pct)}%`, pct, size);
        else usageRowPaint(box, "Контекст", `${size} — ${Math.round(pct)}%`, pct);
      }
    }
    let fable = null;
    try { fable = limitsNow(false)?.fable ?? null; } catch {}
    if (names.some(name => /fable/i.test(name)) || !fable) { usageRowDrop(panel, "fable"); return; }
    let anchor = null;
    try { anchor = panel.querySelector(`[${USAGE_WEEK_ATTRIBUTE}="block"]`); } catch {}
    const box = usageRowBox(panel, blocks, "fable", anchor ?? blocks[blocks.length - 1].block);
    if (!box) return;
    const used = Math.round(fable.used);
    const when = fable.resetsAt != null ? `${USAGE_DAYS[new Date(fable.resetsAt).getDay()]} ${usageClock(fable.resetsAt)}` : "";
    if (under) usageRowPaint(box, "Fable", `${used}%`, used, when);
    else usageRowPaint(box, "Fable", when ? `${when} — ${used}%` : `${used}%`, used);
  };

  // ---- проход по панели ----
  const usageApply = panel => {
    if (!usagePanelOk(panel)) return false;
    if (!panel.hasAttribute(USAGE_PANEL_ATTRIBUTE)) panel.setAttribute(USAGE_PANEL_ATTRIBUTE, "");
    const base = Date.now();
    const name = usageAccountRead();
    const done = new Set();
    const blocks = usageBlocks(panel);
    let week = null;
    for (const block of blocks) {
      done.add(block.label);
      const raw = usageRaw(block.label);
      const label = raw == null ? null : usageLabel(raw);
      if (label) usageWrite(block.label, raw, label.text);
      else if (raw != null) usageUnknown(raw);
      const key = label ? (label.kind === "week" ? `week:${label.text}` : label.kind) : null;
      // Процент читаем ДО прохода: в строке он стоит после времени сброса, а
      // уехать должен в конец этого самого времени («Пт 08:00 — 92%»).
      const leaves = [...usageLeaves(block.row), ...(block.desc && usageTextNode(block.desc) ? [block.desc] : [])]
        .filter(leaf => !done.has(leaf));
      const pctLeaf = leaves.find(leaf => USAGE_PERCENT_RE.test(String(usageRaw(leaf) ?? ""))) ?? null;
      const pct = pctLeaf ? String(usageRaw(pctLeaf) ?? "").replace(/\s*used\s*$/i, "").replace(/^\s*использовано:?\s*/i, "").trim() : "";
      // Процент прячем только когда он и правда уехал в строку сброса: время не
      // разобрали — пусть остаётся на месте, иначе процент пропал бы ни за что.
      let merged = false;
      for (const leaf of leaves) {
        done.add(leaf);
        const value = usageRaw(leaf);
        if (value == null) continue;
        if (leaf === pctLeaf) continue;
        const reset = usageReset(value, base);
        if (!reset) { usageUnknown(value); continue; }
        const at = reset.at != null && key ? usageSteady(key, value, reset.at) : reset.at;
        const plain = reset.fixed ?? (reset.minutes == null ? null
          : (reset.rough || at == null ? usageShort(reset.minutes) : `${usageShort(reset.minutes)} — в ${usageClock(at)}`));
        if (plain == null) { usageUnknown(value); continue; }
        // С 2.42304 (#9978) сброс — своей строкой под полосой, а процент остаётся
        // справа от подписи («Неделя 5 %», под полосой «сброс пт 08:00» — как в
        // панели у часов, на которую Элвис показал 16.10).
        const text = label && label.kind !== "hour5" && pct && !block.desc ? `${plain} — ${pct}` : plain;
        if (text !== plain) merged = true;
        usageWrite(leaf, value, text);
        // Неделю задаёт строка «all models»; её нет — первая недельная
        // (недельных строк ДВЕ: «all models» и «Fable»).
        if (at != null && (label?.kind === "weekAll" || (label?.kind === "week" && !week))) {
          week = { at, rough: Boolean(reset.rough) };
        }
      }
      // Процент прячем своим атрибутом, ПОСЛЕ строки сброса: с 2.42304 он стоит
      // раньше неё, и «уехал ли» до прохода ещё не известно. У 5-часового Элвис
      // его не хочет («только полоса»), у недельных он в строке сброса.
      if (pctLeaf) {
        const value = usageRaw(pctLeaf);
        if (value != null && pct && value.trim() !== pct) usageWrite(pctLeaf, value, pct);
        usageHide(pctLeaf, label?.kind === "hour5" || merged);
      }
    }
    // Всё остальное в панели: контекст, шапка аккаунта, «Статистика» и словарь
    // раскрытого «Контекста».
    for (const leaf of usageLeaves(panel)) {
      if (done.has(leaf)) continue;
      const raw = usageRaw(leaf);
      if (raw == null) continue;
      const text = raw.trim();
      if (!text) continue;
      const word = USAGE_WORDS.get(text);
      if (word) { usageWrite(leaf, raw, raw.replace(text, word)); continue; }
      const head = usageHead(text, name);
      if (head) { usageWrite(leaf, raw, head); continue; }
      const short = usageNumber(raw);
      if (short !== raw) { usageWrite(leaf, raw, short); continue; }
      // Осталось английское слово — это событие, а не норма: строку не трогаем
      // (родной текст лучше сломанного), но считаем.
      if (/[A-Za-z]{2,}/.test(text)) usageUnknown(text);
    }
    usageState.week = usageWeekDraw(panel, blocks, week, base);
    usageExtras(panel, blocks);
    return true;
  };

  // ---- наблюдатели ----
  const usageStop = () => {
    if (usageState.observer) { try { usageState.observer.disconnect(); } catch {} usageState.observer = null; }
    if (usageState.timer) { clearTimeout(usageState.timer); usageState.timer = 0; }
  };
  const usageClose = () => {
    usageStop();
    usageState.panel = null;
    usageState.week = false;
    usageState.hoverOpen = false;
    usageState.pinned = false;
  };
  // Наблюдатель за самой панелью: React перерисовывает числа, мы переводим их
  // снова. Колбэк — микрозадача в конце той же задачи, где React сделал коммит,
  // то есть ДО кадра: английскому мелькнуть негде. takeRecords() в конце —
  // чтобы свои же characterData-записи не вернулись вторым холостым проходом.
  const usageHold = panel => {
    usageStop();
    if (typeof MutationObserver !== "function") return;
    const observer = new MutationObserver(() => {
      if (!usagePanelOk(panel)) { usageClose(); return; }
      try { usageApply(panel); } catch {}
      try { observer.takeRecords(); } catch {}
    });
    try { observer.observe(panel, { childList: true, subtree: true, characterData: true }); } catch { return; }
    usageState.observer = observer;
  };
  const usageOpen = panel => {
    usageState.panel = panel;
    usageState.opens += 1;
    usageContextAsk();
    usageHold(panel);
    try { usageApply(panel); } catch {}
  };
  // Клик по кружку: ждём панель временным наблюдателем за body — ровно как
  // openChromeWatch ждёт меню. Само событие не отменяется: панель открывает
  // Claude, наше дело — успеть встать до того, как React её смонтирует.
  const usageWatch = () => {
    usageStop();
    if (typeof MutationObserver !== "function") return;
    const host = document.body ?? document.documentElement;
    if (!host) return;
    const observer = new MutationObserver(records => {
      for (const record of records) {
        for (const node of record.addedNodes ?? []) {
          const panel = usagePanelIn(node);
          if (panel) { usageOpen(panel); return; }
        }
      }
    });
    observer.observe(host, { childList: true, subtree: true });
    usageState.observer = observer;
    usageState.timer = setTimeout(() => { usageState.timer = 0; if (!usageState.panel) usageStop(); }, USAGE_WAIT_MS);
  };
  const onUsageRing = event => {
    let ring = null;
    try { ring = event.target?.closest?.(USAGE_RING_SELECTOR) ?? null; } catch {}
    if (!ring) return;
    // Настоящее нажатие по кружку, пока панель открыта наведением, её
    // ЗАКРЕПЛЯЕТ (#6906: «нажал — появилось и исчезнет только после повторного
    // нажатия»): клик гасим, иначе Claude тут же свернул бы свою же панель.
    if (event.isTrusted === true && usageState.hoverOpen && !usageState.pinned &&
      usageState.panel?.isConnected) {
      usageState.pinned = true;
      usageState.hoverOpen = false;
      event.preventDefault();
      event.stopPropagation();
      return;
    }
    // Панель открыта — этот клик её закрывает, ждать нечего.
    if (usageState.panel?.isConnected) {
      usageState.pinned = false;
      usageState.hoverOpen = false;
      usageClose();
      return;
    }
    // Открыли рукой — держим до следующего нажатия; открыли наведением —
    // отпускаем, когда мышь уйдёт.
    usageState.pinned = event.isTrusted === true;
    usageWatch();
  };
  // Страховка вместо постоянного наблюдателя: один querySelector на круге
  // сторожа (раздел 16). Ею же панель подхватывается, когда её открыли не
  // кликом (клавиатурой) или когда инжект перезапустился при открытой панели.
  const usageTick = () => {
    if (usageState.panel && !usageState.panel.isConnected) usageClose();
    const panel = usageFind();
    if (!panel) { if (usageState.panel) usageClose(); return; }
    if (panel !== usageState.panel) { usageOpen(panel); return; }
    usageApply(panel);
  };
  // Одно снятие на весь раздел: наблюдатель со сроком, своя полоса и свои
  // атрибуты. Текст назад не откатываем — см. шапку раздела.
  track(() => {
    usageClose();
    usageState.resets.clear();
    try {
      for (const node of document.querySelectorAll(`[${USAGE_WEEK_ATTRIBUTE}]`)) node.remove();
      for (const node of document.querySelectorAll(`[${USAGE_SRC_ATTRIBUTE}],[${USAGE_OUT_ATTRIBUTE}],[${USAGE_HIDE_ATTRIBUTE}]`)) {
        node.removeAttribute(USAGE_SRC_ATTRIBUTE);
        node.removeAttribute(USAGE_OUT_ATTRIBUTE);
        node.removeAttribute(USAGE_HIDE_ATTRIBUTE);
      }
      for (const node of document.querySelectorAll(`[${USAGE_PANEL_ATTRIBUTE}]`)) {
        node.removeAttribute(USAGE_PANEL_ATTRIBUTE);
      }
    } catch {}
  });
  // Панель лимитов (раздел 12ж, #6738): сколько раз панель открывали при
  // нас, сколько текстов подменили, сколько РАЗНЫХ строк не разобрали и
  // стоит ли сейчас полоса недели. Самих строк и имени аккаунта здесь нет
  // намеренно: status() уезжает в probe-result.json на диск.
  statusPart("usage", () => ({
    opens: usageState.opens,
    swaps: usageState.swaps,
    unknown: usageState.unknown.size,
    week: usageState.week,
    context: usageState.context ? usageState.context.tokens : null,
  }));
  HATCH && Object.assign(HATCH, { usageNumber, usageMinutes, usageClockParts, usageShort, usageLong, usageLabel,
    usageHead, usageReset, usageWeekParts, usageAccountName });

