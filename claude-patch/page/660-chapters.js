  // ---- 12х². Главы чата: меню с затемнением, «прочитано», настройка вида (WF241) ----
  // Слово Элвиса 11.10 01:40 о родной дорожке глав Claude (2.31226; `.epitaxy-toc > nav`: полоски —
  // ol[aria-hidden], меню с названиями — div > ol[role=list] > li > button): «как я навожу на главы,
  // они как вылетают, расширяются… главы изначально ты разделяешь на вот такую высоту, и они идут
  // слева по порядку: все серенькие, но которая текущая — жирненькая. И когда навожу — открывай
  // подменю с названиями, оно так выезжает. И пусть весь интерфейс плавно затемнится… Если я главу
  // прочитал, то я могу на неё нажать, и она зелёным окрасится… правой кнопкой понажимал, и там была
  // настройка… расстояние… толщину… и яркость».
  // • Вид — правила раздела 4: шаг полосок равен шагу строк меню, дорожка лежит поверх меню, свои
  //   полоски меню спрятаны — при открытии ни одна полоска не двигается. Узлы Claude на местах.
  // • Меню открывает страница меткой на nav: наведение на дорожку (через CH_OPEN_MS — мимоходом не
  //   срабатывает) или фокус с клавиатуры; уход курсора (через CH_CLOSE_MS), нажатие мимо, Esc —
  //   закрывают. Пока открыто — окно притемнено своим узлом (тень от прямоугольника меню).
  // • «Прочитано» — галочка в строке меню (кнопка: мышь, Enter, пробел) и двойное нажатие по строке
  //   (переименование Claude при этом не запускается); одиночное нажатие по названию — переход, как у
  //   Claude. Отметки — localStorage[CH_READ_KEY] = {<ключ чата раздела 2а>: {at, ids}}, как у
  //   «Прочитано» (12х), общие у окон; потолок — readStoreTrim. Глава — id из пропсов её строки
  //   (chapter.id); пропсов нет — номер и название.
  // • Настройка — правая кнопка по дорожке или меню: своя панель с тремя ползунками, вид меняется
  //   сразу; значения — localStorage[CH_LOOK_KEY] (только отличные от умолчания), общие у окон.
  //   Родное меню Claude «Rename · Delete» по правой кнопке на главах при этом не открывается.
  // • Закладка (#9758, слово Элвиса 11.10 08:24: «чтобы я мог звёздочкой пометить… галочки рядом и звёздочки сделай
  //   рядом… просто очертание звёздочки… как закладка») — звёздочка сразу за галочкой: контур, в закладках — залита
  //   янтарным, и полоска главы на дорожке янтарная. Отметки — localStorage[CH_STAR_KEY], как «прочитано».
  // • Каждый ответ — глава (#9757, слово Элвиса 11.10 07:27: «каждый твой ответ — это глава. Я по ним, чтобы мне по
  //   ним удобно было ходить»). Ответу без главы Claude страница даёт свою: li в обоих списках дорожки на месте
  //   по порядку ленты (место глав Claude — entryIndex из пропсов их строк), название — первая целиком жирная строка
  //   ответа (итог), нет её — первая строка текста; короткий служебный ответ (меньше CH_TEXT_MIN знаков), шаги
  //   «Работа идёт», ответ, который ещё пишется, — без главы. Нажатие — переход к ответу (как «непрочитанные»),
  //   галочка, звёздочка и двойное нажатие — как у глав Claude. Текущей своя глава становится по линии чтения
  //   ленты (как у Claude: верх + 64): тогда текущая Claude показана обычной. Узлы Claude не трогаются — свои
  //   li только встают между ними. Мест глав Claude нет (другая версия) — своих глав нет, причина в lastError.
  const CH_READ_KEY = "myclaude-chapters-read-v1";
  const CH_STAR_KEY = "myclaude-chapters-star-v1";
  const CH_LOOK_KEY = "myclaude-chapters-look-v1";
  const CH_CHATS_MAX = 40;
  const CH_IDS_MAX = 300;
  const CH_TOTAL_MAX = 3000;
  const CH_OPEN_MS = 160;
  const CH_CLOSE_MS = 240;
  // Claude 2.32 обернул строки с названием от модели в своё контекстное меню: пропсы главы встали на ~20-й
  // прыжок над кнопкой (живая проба 23.10, #10764; у «Session start» — на 6-м). Поиск идёт до списка строк.
  const CH_FIBER_HOPS = 40;
  const CH_KEY_CLICK_MS = 600;
  const CH_ON_TEXT = "Снять отметку «прочитано»";
  const CH_OFF_TEXT = "Отметить главу прочитанной";
  const CH_STAR_ON_TEXT = "Убрать главу из закладок";
  const CH_STAR_OFF_TEXT = "Добавить главу в закладки";
  const CH_STAR_PATH = "M9 1.6L11.06 6.77L16.61 7.13L12.33 10.68L13.7 16.07L9 13.1L4.3 16.07L5.67 10.68L1.39 7.13L6.94 6.77Z";
  const CH_STAR_INK = "rgb(245,158,11)";
  const CH_TEXT_MIN = 40;
  const CH_TITLE_MAX = 160;
  const CH_HERE_INSET = 64;
  const CH_BOTTOM_PX = 8;
  const chState = {
    nav: null, open: false, openTimer: 0, closeTimer: 0, settings: false, back: null, chat: undefined,
    marks: new Set(), kept: new Map(), checks: new Map(), count: 0, read: 0, error: null, keyAt: -Infinity,
    look: null, dim: null, panel: null, inputs: {}, clicks: 0,
    stars: new Set(), keptStars: new Map(), starButtons: new Map(), starred: 0,
    own: new Map(), plan: [], natives: [], titles: new WeakMap(), mine: null, hereRaf: 0, ownError: null, jumps: 0,
  };
  // Вид: числа в своих пределах и с шагом ползунка; мусор и умолчание в записи не держатся.
  const chLookClean = raw => {
    const out = {};
    for (const [name, spec] of Object.entries(CH_LOOK)) {
      const value = Number(raw?.[name]);
      out[name] = Number.isFinite(value) && raw?.[name] != null && raw[name] !== ""
        ? Math.min(spec.max, Math.max(spec.min, Math.round(value / spec.by) * spec.by)) : spec.base;
    }
    return out;
  };
  const chLookRead = () => {
    try { return chLookClean(JSON.parse(localStorage.getItem(CH_LOOK_KEY) ?? "null")); } catch { return chLookClean(null); }
  };
  const chLookPlain = look => Object.keys(CH_LOOK).every(name => look[name] === CH_LOOK[name].base);
  // Переменные вида на <html>; умолчание — без переменной (правила раздела 4 берут запасное значение).
  const chLookApply = look => {
    chState.look = look;
    const put = (name, value) => {
      try {
        const style = document.documentElement.style;
        if (value == null) { if (style.getPropertyValue(name)) style.removeProperty(name); }
        else if (style.getPropertyValue(name) !== value) style.setProperty(name, value);
      } catch {}
    };
    put(CH_STEP_VARIABLE, look.step === CH_LOOK.step.base ? null : `${look.step}px`);
    put(CH_THICK_VARIABLE, look.thick === CH_LOOK.thick.base ? null : `${look.thick}px`);
    put(CH_INK_VARIABLE, look.ink === CH_LOOK.ink.base ? null : String(look.ink / 100));
    for (const [name, input] of Object.entries(chState.inputs)) {
      const text = String(look[name]);
      if (input.value !== text) input.value = text;
      const shown = `${text.replace(".", ",")}${CH_LOOK[name].unit}`;
      if (input.__myclaudeNum && input.__myclaudeNum.textContent !== shown) input.__myclaudeNum.textContent = shown;
    }
    if (chState.panel) foldSet(chState.panel.__myclaudeReset, "aria-disabled", String(chLookPlain(look)));
  };
  // Запись вида. Не удалась — вид действует до закрытия окна, причина — в status().chapters.lastError.
  const chLookSave = look => {
    chState.error = null;
    try {
      if (chLookPlain(look)) localStorage.removeItem(CH_LOOK_KEY);
      else localStorage.setItem(CH_LOOK_KEY, JSON.stringify(look));
    } catch (error) {
      chState.error = `вид глав не сохранён, действует до закрытия окна: ${String(error?.name ?? error).slice(0, 60)}`;
    }
    chLookApply(look);
    if (chState.open) chPlace();
  };
  const chStoreLoad = (store = CH_READ_KEY) => {
    try {
      const data = JSON.parse(localStorage.getItem(store) ?? "null");
      return data && typeof data === "object" && !Array.isArray(data) ? data : {};
    } catch { return {}; }
  };
  // Поставить или снять одну отметку (store — «прочитано» или закладки). Ответ — отметки чата после записи;
  // null — запись не удалась.
  const chStoreApply = (chat, key, marked, store = CH_READ_KEY) => {
    try {
      const map = chStoreLoad(store);
      const ids = readIdsOf(map[chat]).filter(item => item !== key);
      if (marked) ids.push(key);
      map[chat] = { at: Date.now(), ids };
      const next = readStoreTrim(map, chat, CH_IDS_MAX, CH_CHATS_MAX, CH_TOTAL_MAX);
      if (Object.keys(next).length) localStorage.setItem(store, JSON.stringify(next));
      else localStorage.removeItem(store);
      return next[chat]?.ids ?? [];
    } catch (error) {
      const what = store === CH_STAR_KEY ? "закладки" : "отметки";
      chState.error = `${what} глав не сохранены, действуют до закрытия окна: ${String(error?.name ?? error).slice(0, 60)}`;
      return null;
    }
  };
  const chNav = () => { try { return themable ? document.querySelector(CH_NAV_SELECTOR) : null; } catch { return null; } };
  const chRailOf = nav => { try { return nav?.querySelector('ol[aria-hidden="true"]') ?? null; } catch { return null; } };
  const chMenuOf = nav => { try { return [...(nav?.children ?? [])].find(node => node.tagName === "DIV") ?? null; } catch { return null; } };
  const chListOf = nav => { try { return chMenuOf(nav)?.querySelector("ol") ?? null; } catch { return null; } };
  const chButtonOf = row => {
    try { return [...(row?.children ?? [])].find(node => node.tagName === "BUTTON" && !node.hasAttribute(CH_CHECK_ATTRIBUTE) && !node.hasAttribute(CH_STAR_ATTRIBUTE)) ?? null; } catch { return null; }
  };
  // Глава Claude строки меню — объект из пропсов её компонента (не дальше CH_FIBER_HOPS волокон над кнопкой и не
  // выше списка строк): {id, title, source, entryId, entryIndex, …}; у своей строки и без пропсов — null.
  const chChapterOf = row => {
    const button = row?.__myclaudeOwn ? null : chButtonOf(row);
    if (!button) return null;
    try {
      const list = row.parentNode ?? null;
      let fiber = openChromeFiber(button);
      for (let hop = 0; fiber && hop <= CH_FIBER_HOPS && (!list || fiber.stateNode !== list); hop += 1, fiber = fiber.return) {
        const chapter = fiber.memoizedProps?.chapter;
        if (typeof chapter?.id === "string" && chapter.id) return chapter;
      }
    } catch {}
    return null;
  };
  // Ключ главы: id главы Claude; своя глава — id её ответа; пропсов нет — номер и название.
  const chKeyOf = (row, index) => {
    if (row?.__myclaudeOwn) return `a:${row.__myclaudeOwn}`.slice(0, 160);
    const button = chButtonOf(row);
    if (!button) return "";
    const chapter = chChapterOf(row);
    if (chapter) return `id:${chapter.id}`.slice(0, 160);
    const title = String(button.textContent ?? "").replace(/\s+/g, " ").trim().slice(0, 120);
    return title ? `n${index + 1}:${title}` : "";
  };
  const chMakeCheck = () => {
    const check = seenMake();
    check.removeAttribute(SEEN_CHECK_ATTRIBUTE);
    check.setAttribute(CH_CHECK_ATTRIBUTE, "");
    return check;
  };
  const chMakeStar = () => {
    const star = document.createElement("button");
    star.type = "button";
    star.setAttribute(CH_STAR_ATTRIBUTE, "");
    try {
      const ns = "http://www.w3.org/2000/svg";
      const svg = document.createElementNS(ns, "svg");
      svg.setAttribute("viewBox", "0 0 18 18");
      svg.setAttribute("aria-hidden", "true");
      for (const [kind, attrs] of [["line", { fill: "none", stroke: "currentColor", "stroke-width": "1.4", "stroke-linejoin": "round" }], ["fill", { fill: "currentColor" }]]) {
        const path = document.createElementNS(ns, "path");
        path.setAttribute("data-k", kind);
        path.setAttribute("d", CH_STAR_PATH);
        for (const [name, value] of Object.entries(attrs)) path.setAttribute(name, value);
        svg.appendChild(path);
      }
      star.appendChild(svg);
    } catch {}
    return star;
  };
  // Своя кнопка строки (галочка или звёздочка) — на месте; ответ — она, null — вставить не вышло.
  const chPlaceButton = (map, row, make) => {
    let node = map.get(row) ?? null;
    if (node?.parentNode !== row) {
      node ??= make();
      try { row.appendChild(node); } catch { return null; }
      map.set(row, node);
    }
    return node;
  };
  const chDropCheck = row => {
    for (const map of [chState.checks, chState.starButtons]) {
      const node = map.get(row);
      if (node) { try { node.remove(); } catch {} }
      map.delete(row);
    }
  };
  // Название своей главы (чистая функция) — по блокам текста ответа: первая целиком жирная строка (итог Рика:
  // «**✅ …**», значок перед ней — тоже), нет её — первая строка текста, нет и её — первый заголовок. Шаги «Работа
  // идёт», служебные строки К-CA и теги <details> не в счёт; видимого текста меньше CH_TEXT_MIN знаков — null
  // (служебный ответ, точка). Длиннее CH_TITLE_MAX — по слову и «…».
  const CH_BOLD_RE = /^(?:#{1,6}\s+)?(?:[-+*]\s+|\d{1,3}[.)]\s+)?((?:[\p{Extended_Pictographic}\u2600-\u27BF]\uFE0F?\s*)*)\*\*((?:(?!\*\*).)+)\*\*[.:!]?$/u;
  const chPlain = line => String(line ?? "")
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/<[^>]*>/g, "")
    .replace(/^(?:>\s*)+/, "")
    .replace(/^#{1,6}\s+/, "")
    .replace(/^(?:[-+*]\s+|\d{1,3}[.)]\s+)/, "")
    .replace(/\*\*|__|`/g, "")
    .replace(/\s+/g, " ")
    .trim();
  const chTitleOf = items => {
    let bold = null;
    let first = null;
    let head = null;
    let size = 0;
    for (const item of Array.isArray(items) ? items : []) {
      if (item?.kind !== "text") continue;
      for (const raw of String(item.text ?? "").split("\n")) {
        const line = raw.trim();
        const text = chPlain(line);
        if (!text || workTextIs(text) || cleanAnswerLine(text) === "hide") continue;
        size += text.length;
        const hit = bold == null ? line.match(CH_BOLD_RE) : null;
        if (hit) bold = chPlain(`${hit[1]}${hit[2]}`);
        if (/^#{1,6}\s/.test(line)) head ??= text;
        else first ??= text;
      }
    }
    const title = size < CH_TEXT_MIN ? null : bold || first || head;
    if (!title || title.length <= CH_TITLE_MAX) return title;
    const cut = title.slice(0, CH_TITLE_MAX);
    const space = cut.lastIndexOf(" ");
    return `${(space > CH_TITLE_MAX * 0.6 ? cut.slice(0, space) : cut).trimEnd()}…`;
  };
  // Свои главы (чистая функция): ответы ленты без главы Claude по порядку — [{id, index, title}]. entries — ходы
  // ленты, chapters — главы Claude (entryId — их ход), skip — ходы без своей главы (пишется, одни шаги).
  // Ход с главой Claude (в нём блок chapter, в том числе удалённый человеком) своей не получает.
  const chOwnPlan = (entries, chapters, skip = new Set(), titles = null) => {
    const taken = new Set((chapters ?? []).map(chapter => chapter?.entryId).filter(Boolean));
    const out = [];
    (Array.isArray(entries) ? entries : []).forEach((entry, index) => {
      if (entry?.author !== "assistant" || typeof entry.id !== "string" || !entry.id || !Array.isArray(entry.items)) return;
      if (taken.has(entry.id) || skip.has(entry.id) || entry.items.some(item => item?.kind === "chapter")) return;
      let title = titles?.get(entry);
      if (title === undefined) { title = chTitleOf(entry.items); titles?.set(entry, title); }
      if (title) out.push({ id: entry.id, index, title });
    });
    return out;
  };
  // Классы своих узлов — с узлов Claude рядом (вид тот же, что у его глав): строка дорожки, полоска обычная и
  // текущая, кнопка строки меню (цвет — обычной главы), её полоска и название. null — взять не с чего.
  const chOwnLook = (lines, rows) => {
    const strips = lines.map(line => line.firstElementChild).filter(Boolean);
    const isNow = strip => strip.classList?.contains("bg-alpha-8");
    const now = strips.find(isNow)?.getAttribute("class") ?? null;
    const idle = strips.find(strip => !isNow(strip))?.getAttribute("class") ?? null;
    const buttons = rows.map(chButtonOf).filter(Boolean);
    const button = buttons.find(node => !node.hasAttribute("aria-current")) ?? buttons[0];
    if (!(now || idle) || !button) return null;
    const scale = "scale-x-[calc(9/14)]";
    const parts = [...button.children];
    return {
      line: lines[0].getAttribute("class") ?? "",
      idle: idle ?? now.replace("bg-alpha-8", `${scale} bg-alpha-3`),
      now: now ?? idle.replace(scale, "").replace("bg-alpha-3", "bg-alpha-8").replace(/\s+/g, " ").trim(),
      button: `${String(button.getAttribute("class") ?? "").replace(/(^|\s)(?:hover:)?text-(?:primary|secondary)(?=\s|$)/g, " ").replace(/\s+/g, " ").trim()} text-secondary hover:text-primary`,
      bar: parts.find(node => node.getAttribute("aria-hidden") === "true")?.getAttribute("class") ?? "",
      name: parts.find(node => node.tagName === "SPAN" && node.getAttribute("aria-hidden") !== "true")?.getAttribute("class") ?? "",
    };
  };
  const chOwnMake = id => {
    const line = document.createElement("li");
    line.setAttribute(CH_OWN_ATTRIBUTE, "");
    const strip = document.createElement("span");
    line.appendChild(strip);
    const row = document.createElement("li");
    row.setAttribute(CH_OWN_ATTRIBUTE, "");
    row.__myclaudeOwn = id;
    const button = document.createElement("button");
    button.type = "button";
    const bar = document.createElement("span");
    bar.setAttribute("aria-hidden", "true");
    const name = document.createElement("span");
    button.append(bar, name);
    row.appendChild(button);
    return { id, line, strip, row, button, bar, name, look: null };
  };
  const chOwnDrop = id => {
    const own = chState.own.get(id);
    if (!own) return;
    chDropCheck(own.row);
    for (const node of [own.line, own.row]) { try { node.remove(); } catch {} }
    chState.own.delete(id);
  };
  // Свой узел — сразу за prev (null — первым) в списке list; узлы Claude не двигаются.
  const chOwnPut = (list, node, prev) => {
    if (node.parentNode === list && (node.previousElementSibling ?? null) === prev) return;
    try { list.insertBefore(node, prev ? prev.nextElementSibling : list.firstElementChild); } catch {}
  };
  // Свои главы дорожки — ровно по плану: лишние сняты, новые сделаны, все на своих местах между главами Claude.
  const chOwnSync = nav => {
    const lines = chRailOf(nav);
    const list = chListOf(nav);
    const entries = workState.entries;
    let plan = [];
    let natives = [];
    let look = null;
    chState.ownError = null;
    if (lines && list && chState.chat && Array.isArray(entries)) {
      const rails = [...lines.children].filter(node => !node.hasAttribute(CH_OWN_ATTRIBUTE));
      const rows = [...list.children].filter(node => !node.hasAttribute(CH_OWN_ATTRIBUTE));
      natives = rows.map(row => ({ row, rail: null, chapter: chChapterOf(row) }));
      if (rails.length !== rows.length || natives.some(item => !Number.isInteger(item.chapter?.entryIndex))) {
        natives = [];
        chState.ownError = "у глав Claude нет места в ленте: своих глав у ответов нет";
      } else {
        natives.forEach((item, index) => { item.rail = rails[index]; });
        // Своя основа дорожки (раздел 12х²ᵈ): родных строк, с которых снять вид, в ней нет.
        look = chOwnLook(rails, rows) ?? (chHostIs(nav) ? CH_HOST_LOOK : null);
        const skip = new Set(workState.only);
        if (readState.busy) skip.add(readState.busy);
        if (look) plan = chOwnPlan(entries, natives.map(item => item.chapter), skip, chState.titles);
      }
    }
    const want = new Set(plan.map(item => item.id));
    for (const id of [...chState.own.keys()]) if (!want.has(id)) chOwnDrop(id);
    chState.plan = plan;
    chState.natives = natives.map(item => item.chapter.entryIndex);
    if (!plan.length) return;
    let at = 0;
    let prevLine = null;
    let prevRow = null;
    for (const item of plan) {
      while (at < natives.length && natives[at].chapter.entryIndex <= item.index) {
        prevLine = natives[at].rail;
        prevRow = natives[at].row;
        at += 1;
      }
      let own = chState.own.get(item.id);
      if (!own) { own = chOwnMake(item.id); chState.own.set(item.id, own); }
      own.look = look;
      foldSet(own.line, "class", look.line);
      foldSet(own.button, "class", look.button);
      foldSet(own.bar, "class", look.bar);
      foldSet(own.name, "class", look.name);
      foldSet(own.strip, "class", own.id === chState.mine ? look.now : look.idle);
      if (own.name.textContent !== item.title) own.name.textContent = item.title;
      foldSet(own.button, "title", item.title);
      chOwnPut(lines, own.line, prevLine);
      chOwnPut(list, own.row, prevRow);
      prevLine = own.line;
      prevRow = own.row;
    }
  };
  // Ход у линии чтения ленты (её верх + CH_HERE_INSET, как у Claude): номер хода; лента у низа — Infinity; выше
  // первой строки — -1; ленты нет — null.
  const chHereIndex = () => {
    const feed = readFeed();
    if (!feed) return null;
    try {
      if (feed.scrollHeight > feed.clientHeight && feed.scrollHeight - feed.scrollTop - feed.clientHeight <= CH_BOTTOM_PX) return Infinity;
      const line = feed.getBoundingClientRect().top + CH_HERE_INSET;
      let here = -1;
      for (const row of readRowsNow()) {
        const box = row.getBoundingClientRect();
        if (!box.height) continue;
        if (box.top > line) break;
        const raw = row.querySelector("[data-epitaxy-entry-index]")?.getAttribute("data-epitaxy-entry-index");
        if (raw != null && raw !== "" && Number.isInteger(Number(raw))) here = Number(raw);
      }
      return here;
    } catch { return null; }
  };
  // Текущая глава — своя, если ближайшая сверху от линии чтения глава — своя: её полоска и строка — текущие,
  // текущая Claude показана обычной (метка на nav).
  const chNowPaint = () => {
    chState.hereRaf = 0;
    let mine = null;
    const here = chState.own.size ? chHereIndex() : null;
    if (here != null) {
      let best = null;
      for (const item of chState.plan) if (item.index <= here) best = item;
      if (best && !chState.natives.some(index => index > best.index && index <= here)) mine = best.id;
    }
    chState.mine = mine;
    for (const own of chState.own.values()) {
      const now = own.id === mine;
      if (own.look) foldSet(own.strip, "class", now ? own.look.now : own.look.idle);
      foldSet(own.button, "aria-current", now ? "true" : null);
    }
    if (chState.nav) foldSet(chState.nav, CH_MINE_ATTRIBUTE, mine ? "" : null);
  };
  // Разметка ровно по тому, что сейчас в дорожке: отметки на строках меню и полосках, галочки в
  // строках; ушедшее снято. Текущая глава дорожки, не влезшая в окно, остаётся на виду.
  const chPaint = () => {
    const nav = chNav();
    if (nav !== chState.nav) {
      if (chState.open || chState.openTimer) chClose();
      chState.nav = nav;
    }
    try { chOwnSync(nav); } catch (error) { chState.ownError = `свои главы: ${String(error?.message ?? error).slice(0, 80)}`; }
    const rail = [...(chRailOf(nav)?.children ?? [])];
    const rows = chState.chat ? [...(chListOf(nav)?.children ?? [])] : [];
    const live = new Set();
    let read = 0;
    let starred = 0;
    const press = (button, key, on, onText, offText) => {
      button.__myclaudeCh = key;
      foldSet(button, "aria-pressed", String(on));
      foldSet(button, "title", on ? onText : offText);
      foldSet(button, "aria-label", on ? onText : offText);
    };
    rows.forEach((row, index) => {
      const key = chKeyOf(row, index);
      const on = Boolean(key) && chState.marks.has(key);
      const star = Boolean(key) && chState.stars.has(key);
      if (on) read += 1;
      if (star) starred += 1;
      for (const node of [row, rail[index]]) {
        if (!node) continue;
        foldSet(node, CH_READ_ATTRIBUTE, on ? "" : null);
        foldSet(node, CH_STARRED_ATTRIBUTE, star ? "" : null);
      }
      if (!key) { chDropCheck(row); return; }
      const check = chPlaceButton(chState.checks, row, chMakeCheck);
      const mark = chPlaceButton(chState.starButtons, row, chMakeStar);
      if (!check || !mark) return;
      live.add(row);
      press(check, key, on, CH_ON_TEXT, CH_OFF_TEXT);
      press(mark, key, star, CH_STAR_ON_TEXT, CH_STAR_OFF_TEXT);
    });
    for (const line of rail.slice(rows.length)) { foldSet(line, CH_READ_ATTRIBUTE, null); foldSet(line, CH_STARRED_ATTRIBUTE, null); }
    for (const row of new Set([...chState.checks.keys(), ...chState.starButtons.keys()])) {
      if (live.has(row)) continue;
      chDropCheck(row);
      try { row.removeAttribute(CH_READ_ATTRIBUTE); row.removeAttribute(CH_STARRED_ATTRIBUTE); } catch {}
    }
    chState.count = Math.max(rail.length, rows.length);
    chState.read = read;
    chState.starred = starred;
    chAlign(rail, rows);
    chNowPaint();
    if (!chState.open) chFollow(nav);
  };
  // Название с переносом делает строку меню выше шага дорожки (page-71): полоска этой главы получает высоту
  // своей строки — полоски стоят против названий и при открытии не двигаются. Строка в один ряд — как было.
  const chAlign = (rail, rows) => {
    const step = Number(chState.look?.step) || CH_LOOK.step.base;
    rail.forEach((line, index) => {
      let height = 0;
      try { height = rows[index] ? Math.round(Number(rows[index].getBoundingClientRect().height) || 0) : 0; } catch { height = 0; }
      const want = height > step + 1 ? `${height}px` : "";
      try {
        if (line.style.getPropertyValue("height") === want) return;
        if (want) line.style.setProperty("height", want, "important"); else line.style.removeProperty("height");
      } catch {}
    });
  };
  track(() => { try { for (const line of chRailOf(chNav())?.children ?? []) line.style.removeProperty("height"); } catch {} });
  // Длинная дорожка обрезана окном (у Claude — тоже): текущая глава держится на виду. Закрытое меню
  // прокручивается вместе с дорожкой — при открытии строки стоят против своих полосок.
  const chFollow = nav => {
    try {
      const rail = chRailOf(nav);
      if (!rail || !(rail.scrollHeight > rail.clientHeight + 1)) return;
      const now = item => item.firstElementChild?.classList?.contains("bg-alpha-8");
      const line = [...rail.children].find(item => now(item) && (!chState.mine || item.hasAttribute(CH_OWN_ATTRIBUTE)));
      if (!line) return;
      const top = line.offsetTop - (rail.clientHeight - line.offsetHeight) / 2;
      const want = Math.max(0, Math.min(rail.scrollHeight - rail.clientHeight, Math.round(top)));
      if (Math.abs(rail.scrollTop - want) > 1) rail.scrollTop = want;
    } catch {}
  };
  // Общий проход сердцебиения (лента менялась или прошло 5 с): чат сменился — отметки его.
  const chTick = () => {
    let chat = null;
    try { chat = chatKey(); } catch { chat = null; }
    if (chat !== chState.chat) {
      chState.chat = chat;
      chState.marks = new Set(chat ? chState.kept.get(chat) ?? readIdsOf(chStoreLoad()[chat]) : []);
      chState.stars = new Set(chat ? chState.keptStars.get(chat) ?? readIdsOf(chStoreLoad(CH_STAR_KEY)[chat]) : []);
    }
    chPaint();
  };
  // Поставить или снять отметку главы: kind "read" — «прочитано», "star" — закладка.
  const chToggle = (key, kind = "read") => {
    const chat = chState.chat;
    if (!key || !chat) return false;
    const star = kind === "star";
    const kept = star ? chState.keptStars : chState.kept;
    let marks = star ? chState.stars : chState.marks;
    const was = marks.has(key);
    chState.clicks += 1;
    chState.error = null;
    const stored = chStoreApply(chat, key, !was, star ? CH_STAR_KEY : CH_READ_KEY);
    if (stored) { marks = new Set(stored); kept.delete(chat); }
    else {
      if (was) marks.delete(key); else marks.add(key);
      kept.set(chat, marks);
    }
    if (star) chState.stars = marks; else chState.marks = marks;
    chPaint();
    return true;
  };
  // Затемнение — по прямоугольнику меню (место nav, размер меню без сдвига выезда).
  const chPlace = () => {
    const dim = chState.dim;
    const menu = chMenuOf(chState.nav);
    if (!dim || !menu) return;
    // Запас меню — от его левого края до правого края чата, а не окна: слева может стоять панель.
    // Считается и здесь, на каждую расстановку: меню бывает открыто, пока окно сужается.
    try { const right = chState.nav.closest(".epitaxy-chat-panel")?.getBoundingClientRect().right ?? innerWidth; chState.nav.style.setProperty(CH_ROOM_VARIABLE, `${Math.round(right - chState.nav.getBoundingClientRect().left)}px`); } catch {}
    try {
      const box = chState.nav.getBoundingClientRect();
      const put = (name, value) => { if (dim.style.getPropertyValue(name) !== value) dim.style.setProperty(name, value); };
      put("left", `${Math.round(box.left)}px`);
      put("top", `${Math.round(box.top)}px`);
      put("width", `${Math.round(Number(menu.offsetWidth) || 0)}px`);
      put("height", `${Math.round(Number(menu.offsetHeight) || 0)}px`);
      const radius = String(getComputedStyle(menu).borderRadius ?? "").trim();
      if (radius) put("border-radius", radius);
    } catch {}
  };
  const chStopTimers = () => {
    if (chState.openTimer) { clearTimeout(chState.openTimer); chState.openTimer = 0; }
    if (chState.closeTimer) { clearTimeout(chState.closeTimer); chState.closeTimer = 0; }
  };
  const chOpen = nav => {
    chStopTimers();
    if (!state.alive || !nav?.isConnected) return false;
    if (chState.open && chState.nav === nav) return true;
    chState.nav = nav;
    chState.open = true;
    if (!chState.dim) {
      const dim = document.createElement("div");
      dim.id = CH_DIM_ID;
      dim.setAttribute("aria-hidden", "true");
      (document.body ?? document.documentElement).appendChild(dim);
      chState.dim = dim;
    }
    try { chPaint(); } catch {}
    // Строки меню — против своих полосок и при прокрученной дорожке.
    try { const list = chListOf(nav); const rail = chRailOf(nav); if (list && rail && list.scrollTop !== rail.scrollTop) list.scrollTop = rail.scrollTop; } catch {}
    foldSet(nav, CH_OPEN_ATTRIBUTE, "");
    chPlace();
    // Узел только что создан: без замера его невидимое состояние не успело бы стать началом перехода.
    try { void chState.dim.offsetWidth; } catch {}
    chState.dim.dataset.on = "true";
    return true;
  };
  const chClose = () => {
    chStopTimers();
    if (chState.settings) chSettingsClose(false);
    if (!chState.open) return;
    chState.open = false;
    try { chState.nav?.removeAttribute(CH_OPEN_ATTRIBUTE); } catch {}
    if (chState.dim) chState.dim.dataset.on = "false";
  };
  // Панель настройки: три ползунка одной сеткой «имя · ползунок · число» и «Как было».
  const chPanel = () => {
    if (chState.panel) return chState.panel;
    const panel = document.createElement("div");
    panel.id = CH_SET_ID;
    // role="dialog" — только пока открыта (chSettingsOpen/Close), как слой фото 12л: скрытая панель
    // с этой ролью выключала сторож Esc (раздел 16) и «Bypass во всех чатах» (12с¹) до перезагрузки.
    panel.setAttribute("aria-label", "Вид глав");
    const head = document.createElement("h3");
    head.textContent = "Главы";
    panel.appendChild(head);
    for (const [name, spec] of Object.entries(CH_LOOK)) {
      const row = document.createElement("label");
      const text = document.createElement("span");
      text.textContent = spec.name;
      const input = document.createElement("input");
      input.type = "range";
      for (const [attr, value] of [["min", spec.min], ["max", spec.max], ["step", spec.by], ["aria-label", spec.name]]) input.setAttribute(attr, String(value));
      input.__myclaudeCh = name;
      const num = document.createElement("span");
      num.setAttribute("data-k", "num");
      input.__myclaudeNum = num;
      row.append(text, input, num);
      panel.appendChild(row);
      chState.inputs[name] = input;
    }
    const foot = document.createElement("div");
    foot.setAttribute("data-k", "foot");
    const reset = document.createElement("button");
    reset.type = "button";
    reset.textContent = "Как было";
    reset.title = "Вернуть расстояние, толщину и яркость как были";
    foot.appendChild(reset);
    panel.appendChild(foot);
    panel.__myclaudeReset = reset;
    (document.body ?? document.documentElement).appendChild(panel);
    chState.panel = panel;
    return panel;
  };
  const chOwn = node => Boolean(chState.panel && node && (node === chState.panel || chState.panel.contains?.(node)));
  // Панель встаёт правее меню на высоте нажатия; не влезла — у нажатия, в пределах окна.
  const chSettingsOpen = (x, y) => {
    const panel = chPanel();
    chState.settings = true;
    chStopTimers();
    const put = (name, value) => { if (panel.style.getPropertyValue(name) !== value) panel.style.setProperty(name, value); };
    // Цвета — от поля ввода, как у панели PMP (12п³).
    const host = state.shell ?? state.composerBlock;
    const dark = progressDark();
    const skin = PROGRESS_CARD_SKIN[dark ? "dark" : "light"];
    const T = progressTextColor(host);
    const F = progressFieldColor(host);
    for (const [name, value] of [["--T", T], ["--F", dark ? `color-mix(in srgb, ${F}, ${T} 7%)` : F], ["--L", progressTint(T, 15)], ["--S", skin.shadow]]) put(name, value);
    panel.setAttribute("role", "dialog");
    put("display", "block");
    chLookApply(chState.look ?? chLookRead());
    let width = 236;
    let height = 150;
    let edge = 0;
    try {
      width = Number(panel.offsetWidth) || width;
      height = Number(panel.offsetHeight) || height;
      const menu = chMenuOf(chState.nav);
      edge = menu ? Math.round(chState.nav.getBoundingClientRect().left + (Number(menu.offsetWidth) || 0)) : 0;
    } catch {}
    const wide = Number(window.innerWidth) || 0;
    const tall = Number(window.innerHeight) || 0;
    let left = Math.max(Math.round(Number(x) || 0) + 12, edge + 8);
    if (left + width > wide - 8) left = Math.max(8, wide - 8 - width);
    const top = Math.max(8, Math.min(Math.round(Number(y) || 0) - 12, tall - 8 - height));
    put("left", `${left}px`);
    put("top", `${top}px`);
    // Tab ходит по ползункам: фокус — на первом, прежний вернётся при закрытии.
    try { chState.back = document.activeElement ?? null; chState.inputs.step?.focus?.({ preventScroll: true }); } catch {}
  };
  const chSettingsClose = (refocus = true) => {
    if (!chState.settings) return;
    chState.settings = false;
    try { chState.panel?.style.setProperty("display", "none"); chState.panel?.removeAttribute("role"); } catch {}
    const back = chState.back;
    chState.back = null;
    if (refocus && back?.isConnected) { try { back.focus?.({ preventScroll: true }); } catch {} }
  };
  const chNavAt = target => { try { return target?.closest?.(CH_NAV_SELECTOR) ?? null; } catch { return null; } };
  const chLeaveSoon = () => {
    if (chState.openTimer) { clearTimeout(chState.openTimer); chState.openTimer = 0; }
    if (chState.open && !chState.settings && !chState.closeTimer) chState.closeTimer = setTimeout(() => { chState.closeTimer = 0; chClose(); }, CH_CLOSE_MS);
  };
  // Курсор: над дорожкой или меню — открыть (с задержкой) и держать; ушёл — закрыть (с задержкой).
  const onChOver = event => {
    if (!state.alive || (!chState.nav && !chState.open)) return;
    const nav = chNavAt(event?.target);
    if (nav || chOwn(event?.target)) {
      if (chState.closeTimer) { clearTimeout(chState.closeTimer); chState.closeTimer = 0; }
      if (nav && !chState.open && !chState.openTimer) chState.openTimer = setTimeout(() => { chState.openTimer = 0; chOpen(nav); }, CH_OPEN_MS);
      return;
    }
    chLeaveSoon();
  };
  // Курсор ушёл из окна совсем.
  const onChOut = event => { if (state.alive && (chState.open || chState.openTimer) && event?.relatedTarget == null) chLeaveSoon(); };
  // Нажатие мимо: панель настройки закрывается, меню — если нажали вне его. Само нажатие идёт дальше.
  const onChPress = event => {
    if (!state.alive || !(chState.open || chState.settings)) return;
    const target = event?.target;
    if (chOwn(target)) return;
    const inside = Boolean(chNavAt(target));
    // Второе нажатие двойного: решает оно, а не отпускание, иначе меню уйдёт из-под него на 240 мс.
    if (inside && chState.closeTimer) { clearTimeout(chState.closeTimer); chState.closeTimer = 0; }
    if (chState.settings && Number(event?.button) !== 2) chSettingsClose(false);
    if (!inside) { chClose(); return; }
    // Галочка и звёздочка: нажатие мышью фокус поля ввода не отнимает и до строки не доходит.
    if (target?.closest?.(`[${CH_CHECK_ATTRIBUTE}],[${CH_STAR_ATTRIBUTE}]`)) { event.preventDefault?.(); event.stopImmediatePropagation?.(); }
  };
  const onChClick = event => {
    if (!state.alive) return;
    const target = event?.target;
    if (chState.settings && chOwn(target)) {
      if (target === chState.panel.__myclaudeReset || chState.panel.__myclaudeReset.contains?.(target)) {
        event.preventDefault?.();
        chLookSave(chLookClean(null));
      }
      return;
    }
    const check = target?.closest?.(`[${CH_CHECK_ATTRIBUTE}],[${CH_STAR_ATTRIBUTE}]`) ?? null;
    // Своя глава: нажатие по строке — переход к её ответу (у глав Claude переход — его собственный).
    const own = check ? null : target?.closest?.(`li[${CH_OWN_ATTRIBUTE}]`) ?? null;
    if (own?.__myclaudeOwn && chNavAt(own)) {
      event.preventDefault?.();
      event.stopImmediatePropagation?.();
      if (Number(event.detail) > 1) return;
      chState.jumps += 1;
      // Переход — к месту «N min ago» над ответом (#10764): время реплики Элвиса встаёт на линию чтения.
      try { readSeek(own.__myclaudeOwn, { flash: true, smooth: true, stamp: true }); } catch {}
      // Меню уходит с задержкой: подсветку ответа видно, а второе нажатие двойного снимает уход (onChPress).
      // С клавиатуры меню остаётся: Enter шлёт click с detail 0, а обход глав держится на фокусе в строке.
      if (Number(event.detail) > 0) chLeaveSoon();
      return;
    }
    if (!check) {
      // Родная строка в том же меню: переход делает Claude, событие не гасим, меню уходит как после своей.
      const line = target?.closest?.("li");
      const home = line && chNavAt(line);
      if (home && line.parentNode === chListOf(home) && Number(event.detail) === 1) chLeaveSoon();
      return;
    }
    event.preventDefault?.();
    event.stopImmediatePropagation?.();
    // Второй щелчок двойного нажатия отметку обратно не снимает; щелчок следом за клавишей — не в счёт.
    if (Number(event.detail) > 1) return;
    if (!Number(event.detail) && now() - chState.keyAt < CH_KEY_CLICK_MS) return;
    try { chToggle(check.__myclaudeCh, check.hasAttribute(CH_STAR_ATTRIBUTE) ? "star" : "read"); } catch {}
  };
  // Двойное нажатие по строке меню — «прочитано»; до Claude не доходит (он бы начал переименование).
  const onChDouble = event => {
    if (!state.alive) return;
    const row = event?.target?.closest?.("li") ?? null;
    if (!row || !chNavAt(row) || row.parentNode !== chListOf(chNavAt(row))) return;
    event.preventDefault?.();
    event.stopImmediatePropagation?.();
    if (event.target?.closest?.(`[${CH_CHECK_ATTRIBUTE}],[${CH_STAR_ATTRIBUTE}]`)) return;
    const index = [...row.parentNode.children].indexOf(row);
    chStopTimers();
    try { chToggle(chKeyOf(row, index)); } catch {}
  };
  // Правая кнопка по дорожке или меню — настройка вида; родное меню Claude не открывается.
  const onChMenu = event => {
    if (!state.alive) return;
    const nav = chNavAt(event?.target);
    if (!nav) { if (chState.settings && !chOwn(event?.target)) chSettingsClose(false); return; }
    event.preventDefault?.();
    event.stopImmediatePropagation?.();
    chOpen(nav);
    chSettingsOpen(event.clientX, event.clientY);
  };
  const onChKey = event => {
    if (!state.alive) return;
    const key = event?.key;
    if (key === "Escape") {
      // Esc — только когда открыта настройка или фокус стоит в главах: иначе это Esc самого Claude.
      const focused = chNavAt(document.activeElement);
      if (!chState.settings && !(chState.open && focused)) return;
      event.preventDefault?.();
      event.stopImmediatePropagation?.();
      if (chState.settings) chSettingsClose(true);
      else { try { document.activeElement?.blur?.(); } catch {} chClose(); }
      return;
    }
    if (key !== "Enter" && key !== " " && key !== "Spacebar") return;
    const target = event.target;
    const kind = target?.hasAttribute?.(CH_CHECK_ATTRIBUTE) ? "read" : target?.hasAttribute?.(CH_STAR_ATTRIBUTE) ? "star" : null;
    if (!kind) return;
    event.preventDefault?.();
    event.stopImmediatePropagation?.();
    if (event.repeat) return;
    chState.keyAt = now();
    try { chToggle(target.__myclaudeCh, kind); } catch {}
  };
  // Ползунок: вид меняется сразу и сразу же записан.
  const onChInput = event => {
    const input = event?.target;
    const name = state.alive && chOwn(input) ? input.__myclaudeCh : null;
    if (!name || !CH_LOOK[name]) return;
    chLookSave(chLookClean({ ...(chState.look ?? chLookRead()), [name]: input.value }));
  };
  // Фокус с клавиатуры в главах открывает меню сразу; ушёл наружу — закрывает, как уход курсора.
  const onChFocus = event => {
    if (!state.alive) return;
    const nav = chNavAt(event?.target);
    if (event.type === "focusin") {
      let keyboard = false;
      try { keyboard = Boolean(nav && event.target.matches?.(":focus-visible")); } catch { keyboard = false; }
      if (keyboard) chOpen(nav);
      return;
    }
    if (nav && chState.open && !chNavAt(event.relatedTarget) && !chOwn(event.relatedTarget)) chLeaveSoon();
  };
  // Меню прокрутили — дорожка едет вместе с ним; окно тянут — затемнение по новому месту меню.
  const onChScroll = event => {
    // Своя глава может стать текущей: сверка линии чтения — раз в кадр.
    if (chState.own.size && !chState.hereRaf) { try { chState.hereRaf = requestAnimationFrame(chNowPaint); } catch {} }
    if (!chState.open) return;
    try {
      const list = chListOf(chState.nav);
      const rail = chRailOf(chState.nav);
      if (list && rail && event?.target === list && rail.scrollTop !== list.scrollTop) rail.scrollTop = list.scrollTop;
    } catch {}
  };
  const chStatus = () => ({
    count: chState.count, read: chState.read, starred: chState.starred, own: chState.own.size, open: chState.open, settings: chState.settings,
    lastError: chState.error ?? chState.ownError,
  });
  // Сироты прошлой установки — до первой разметки; при снятии — всё своё.
  const chSweep = () => {
    try {
      for (const node of document.querySelectorAll(`#${CH_DIM_ID},#${CH_SET_ID},[${CH_CHECK_ATTRIBUTE}],[${CH_STAR_ATTRIBUTE}],[${CH_OWN_ATTRIBUTE}]`)) node.remove();
      for (const node of document.querySelectorAll(`[${CH_READ_ATTRIBUTE}],[${CH_OPEN_ATTRIBUTE}],[${CH_STARRED_ATTRIBUTE}],[${CH_MINE_ATTRIBUTE}]`)) {
        for (const name of [CH_READ_ATTRIBUTE, CH_OPEN_ATTRIBUTE, CH_STARRED_ATTRIBUTE, CH_MINE_ATTRIBUTE]) node.removeAttribute(name);
      }
      for (const name of [CH_STEP_VARIABLE, CH_THICK_VARIABLE, CH_INK_VARIABLE, CH_OK_VARIABLE]) document.documentElement.style.removeProperty(name);
    } catch {}
  };
  chSweep();
  chLookApply(themable ? chLookRead() : chLookClean(null));
  // Зелёный «прочитано» — тот же, что «готово» у панели PMP: свой у тёмной и светлой темы.
  const chOkSync = () => {
    try {
      const value = `rgb(${PROGRESS_CARD_SKIN[progressDark() ? "dark" : "light"].ok})`;
      const style = document.documentElement.style;
      if (style.getPropertyValue(CH_OK_VARIABLE) !== value) style.setProperty(CH_OK_VARIABLE, value);
    } catch {}
  };
  track(() => {
    chStopTimers();
    if (chState.hereRaf) { try { cancelAnimationFrame(chState.hereRaf); } catch {} chState.hereRaf = 0; }
    chState.open = false;
    chState.settings = false;
    chState.checks.clear();
    chState.starButtons.clear();
    chState.own.clear();
    chState.dim = null;
    chState.panel = null;
    chState.inputs = {};
    chSweep();
  });
  // Звёздочка-закладка и свои главы ответов (#9758, #9757) — в языке галочки и строк меню Claude.
  lateRules.push(
    `[${CH_STAR_ATTRIBUTE}]{position:absolute;top:0;left:calc(var(--chat-gutter,32px)*9/16 + 31px);display:flex;align-items:center;justify-content:center;box-sizing:border-box;width:24px;height:100%;margin:0;padding:0;border:0;border-radius:5px;background:transparent;color:var(--cds-text-secondary,currentColor);opacity:.5;cursor:pointer;-webkit-app-region:no-drag;transition:opacity .15s,color .15s}`,
    `[${CH_STAR_ATTRIBUTE}]>svg{display:block;width:min(15px,calc(${CH_STEP} - 4px));height:min(15px,calc(${CH_STEP} - 4px));overflow:visible;pointer-events:none}`,
    `[${CH_STAR_ATTRIBUTE}]>svg>[data-k="fill"]{display:none}`,
    `[${CH_STAR_ATTRIBUTE}][aria-pressed="true"]>svg>[data-k="fill"]{display:inline}`,
    `[${CH_STAR_ATTRIBUTE}][aria-pressed="true"]{color:${CH_STAR_INK};opacity:1}`,
    `[${CH_STAR_ATTRIBUTE}]:is(:hover,:focus-visible){opacity:1}`,
    `[${CH_STAR_ATTRIBUTE}]:active{opacity:.65}`,
    `[${CH_STAR_ATTRIBUTE}]:focus-visible{outline:2px solid rgba(245,158,11,.7);outline-offset:-2px}`,
    // Глава в закладках — янтарная полоска на дорожке (сильнее зелёной «прочитано»).
    `${CH_RAIL}>li[${CH_STARRED_ATTRIBUTE}]>span{background-color:${CH_STAR_INK} !important;opacity:max(.7,${CH_INK})}`,
    // Текущая — своя глава: текущая Claude показана обычной (тоньше, тише, короче), строка меню — тоже.
    `${CH_NAV_SELECTOR}[${CH_MINE_ATTRIBUTE}]>ol[aria-hidden="true"]>li:not([${CH_OWN_ATTRIBUTE}])>span[class~="bg-alpha-8"]{height:${CH_THICK} !important;opacity:${CH_INK};scale:calc(9/14) 1 !important}`,
    // Закладка на ней сильнее (#10111): обычная по форме, но янтарная полоска — не тише 70 %.
    `${CH_NAV_SELECTOR}[${CH_MINE_ATTRIBUTE}]>ol[aria-hidden="true"]>li[${CH_STARRED_ATTRIBUTE}]:not([${CH_OWN_ATTRIBUTE}])>span[class~="bg-alpha-8"]{opacity:max(.7,${CH_INK})}`,
    `${CH_NAV_SELECTOR}[${CH_MINE_ATTRIBUTE}]>div>ol>li:not([${CH_OWN_ATTRIBUTE}])>button[aria-current]{color:var(--cds-text-secondary) !important}`,
    `${CH_MENU}>ol>li[${CH_OWN_ATTRIBUTE}]>button[aria-current]{color:var(--cds-text-primary) !important}`,
    `@media (prefers-reduced-motion: reduce){[${CH_STAR_ATTRIBUTE}]{transition:none !important}}`,
  );
  // Главы чата (раздел 12х²): глав в дорожке (с своими), отмечено прочитанными и в закладках, своих глав ответов,
  // открыто ли меню и панель настройки.
  statusPart("chapters", () => chStatus());
  HATCH && Object.assign(HATCH, { chTick, chKeyOf, chLookClean, chTitleOf, chOwnPlan, chToggle, chState });

