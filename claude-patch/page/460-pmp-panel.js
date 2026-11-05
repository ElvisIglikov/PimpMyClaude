  // ---- 12п³. Панель оркестрации на кнопке PMP (#9370–#9373, #9405, WF213) ----
  // Слово Элвиса 10.10: «блок по Workflow давай объединим в кнопку Workflow… тот пусть остаётся пока
  // как есть, а мы новый построим»; «работают девять терминалов… коротко перечисляешь… нажимаю —
  // выдвигается плашечка серенькая, как свёрнутые сообщения… что именно делает, сколько процентов
  // прошло, сколько осталось»; счётчик — «1.4 капсулы… делай этот вариант» (макет docs/32.html,
  // разделы 2–3). Старый блок 12п² тогда остался, снят с page-60 (слово владельца 10.10 21:10).
  // Панель — свой узел над полем ввода (поле не закрывает), цвета — от темы окна, как у карточек
  // 12п². Сверху вниз: блок «Идёт Workflow» одной строкой (лист 48 · 1.2, слово Элвиса 17.10 00:37:
  // «делай по рекомендациям»; как у панели у часов, WF258) — «Идут 7 · Pimp 2/3 · PimpV 6/16», что не
  // влезло — «+2» в конце, без многоточия; нажал — список по проектам (имя, «2/3 · 1 идёт», о чём
  // идущий), ещё раз — свернул; идущих проектов нет — «Тихо». Квадратики на Workflow, «Тихо · N» с
  // давно молчащими и подсказка над квадратиком (WF213) ушли вместе со старым видом блока.
  // «Работают N терминалов» — строка на проект, нажал — серая плашка с подробностями (вид — как у
  // свёрток 12ф; там же «Ждёт тебя:» терминала); внизу — команды (с #9552 — три главные с подписями, под
  // ними строкой мелкие). Блока «Ждут тебя · N» нет (#9520,
  // слово Элвиса «убери» трижды), точек и цвета проектов в блоке Workflow тоже нет (лист 48, «Решено»).
  // Данные — общий с блоком Рика запрос /digest (rickFetch): открыли — сразу,
  // открыта — раз в PMP_PANEL_MS; своего опроса у закрытой нет. Закрывают повторное нажатие кнопки,
  // Esc и клик мимо; меню Claude панель уступает (правило в RULES). Tab ходит по пунктам панели
  // по кругу, Enter и пробел — действие (пункты — настоящие кнопки).
  // «Идёт» — как у панели у часов: Workflow считается идущим, только если проект в группе «идут»
  // (сводка свежее суток, К6); давно молчащий проект в блок не попадает вовсе.
  const PMP_NAME_MAX = 96;
  const PMP_FIELD_TEXT = "Не вышло вставить в поле ввода";
  // «Сэкономить подписку» (#9547, до #9552 — «Сократить расход»; слово Элвиса: «сократить расход токенов, и чтобы промт
  // вставлялся… в поле ввода»): промпт-исследование расхода подписки — в поле как есть (слово Рика 10.10), отправляет человек.
  const PMP_SAVE_TITLE = "Вставить в поле промпт: где уходит подписка и как тратить медленнее (отправишь сам)";
  // Три главные команды (#9552; слово Элвиса: «Запустить Work Flow… понятно людям объясняться… общаться в одном чате,
  // все проекты… сэкономить подписку»): название и под ним одна строка объяснения (тексты ТЗ дословно).
  const PMP_MAIN = [
    { act: "kickoff", name: "Запустить Workflow", note: "Большую задачу делит на шаги и раздаёт агентам; ты видишь ход в панели",
      title: "Вставить в поле текст запуска Workflow (отправишь сам)" },
    { act: "one", name: "Всё в одном чате", note: "Один главный чат ведёт все проекты и сам раздаёт работу — меньше окон, подписка тратится почти так же",
      title: "Открыть окно Claude в папке Рика; Рика нет — PMP у часов покажет, как его поставить" },
    { act: "save", name: "Сэкономить подписку", note: "Разберёт твои журналы и даст личные советы", title: PMP_SAVE_TITLE },
  ];
  // Текста запуска нет (/kickoff ответил 404, отказ, старое приложение): кнопка видна, подпись и подсказка — это.
  const PMP_KICKOFF_NONE = "Нужен PMP у часов";
  // «Всё в одном чате» — запрос приложению (К-OC): окно в папке Рика или панель у часов на «Поставить Рика».
  const PMP_ONE_CHAT_PATH = "/one-chat";
  const PMP_ONE_WAIT = "Уже открываю";
  // Ответил ли /kickoff хоть раз: до ответа подпись «Запустить Workflow» обычная.
  let pmpKickKnown = false;
  const PMP_SAVE_TEXT = `Посчитай, куда уходит моя подписка Claude (токены), и скажи, как тратить её медленнее при той же отдаче.

Только чтение и замеры. Ничего не меняй: ни настройки, ни файлы правил, ни чаты. Никому ничего не отправляй. Меня не переспрашивай — что неясно, реши сам и скажи в конце, как решил. Советы не применяй: только покажи.

## Откуда брать цифры

Журналы Claude Code на этом компьютере: \`~/.claude/projects/<проект>/<чат>.jsonl\`. Подагенты лежат рядом, в \`<чат>/subagents/\` (файлы \`agent-*.jsonl\`, описание — в \`agent-*.meta.json\`), агенты Workflow — глубже, в \`subagents/workflows/\`.

Считай своим скриптом на python3 (только стандартная библиотека; файл положи во временную папку), за последние трое суток и отдельно за сегодня. Журналов меньше — возьми сколько есть и скажи об этом. Тексты сообщений не читай и не выводи: нужны только числа и короткие признаки.

Что есть в журнале:
- Записи \`assistant\`: \`message.usage\` (\`input_tokens\`, \`cache_creation_input_tokens\` и его разбивка \`cache_creation.ephemeral_5m_input_tokens\` / \`ephemeral_1h_input_tokens\`, \`cache_read_input_tokens\`, \`output_tokens\`, \`output_tokens_details.thinking_tokens\`), \`message.model\`, \`message.id\`, \`timestamp\`, ступень усилия \`effort\`. Один ответ записан несколькими строками с одним \`message.id\` — бери последнюю, иначе посчитаешь дважды.
- Размер чата на шаге = \`input_tokens\` + \`cache_creation_input_tokens\` + \`cache_read_input_tokens\`.
- Записи \`user\` без \`tool_result\` и без \`isMeta\` — начало хода; в \`origin.kind\` видно, кто его начал: человек или уведомление.
- Записи \`attachment\` с типом \`instructions\`: список файлов, которые грузятся в чат сами (CLAUDE.md, AGENTS.md, память), с их текстом.
- Вызовы инструментов в ответах: \`Read\` с \`file_path\`, \`Bash\` с \`command\`, запуск подагента с \`prompt\` и \`description\`. Картинки — блоки \`image\` в сообщениях человека и в ответах инструментов.

Цена запроса — по актуальным ценам API твоей модели: ввод, вывод, чтение из кеша; запись в кеш — ×1,25 от ввода на 5 минут и ×2 на час. Не знаешь цен — возьми веса: ввод 1, запись 1,25 и 2, чтение 0,1, вывод 5. Подписка считается не в деньгах, но доли будут те же.

## Что посчитать

1. Всего и по дням. По видам: главные чаты, подагенты, Workflow. По проектам. Десять самых дорогих чатов и агентов.
2. На что уходит цена внутри запроса: перечитка чата из кеша, запись нового в чат, вывод (и сколько в нём размышлений), свежий ввод.
3. Длинные чаты: какая доля расхода приходится на чаты длиннее 300 тысяч токенов, цена одного шага при разном размере чата, окупится ли смена чата раньше.
4. Чат, перечитанный заново по полной цене: шаги, где из кеша прочитано меньше половины прошлого размера чата. Раздели по причине: пауза дольше часа, пауза 5–60 минут, догрузка инструментов посреди чата, чистка старого вывода.
5. Файлы правил — обязательно. Что грузится в каждый чат и каждому подагенту само (по записям \`instructions\`): какие файлы, сколько в них токенов, через сколько шагов они прошли и какую долю расхода это дало. Какие файлы правил и документы агенты читают инструментом и сколько раз; десять самых дорогих файлов; файлы, которые читают, хотя они уже загружены сами. Вес файла в токенах не угадывай: измерь по шагам, где прочитан ровно один файл (прирост чата на знак текста).
6. Картинки и снимки экрана: мои и те, что читают сами агенты. Вес картинки ≈ ширина × высота / 784 токена, не больше 4800.
7. Повторяющаяся служебная работа: агенты, которые что-то проверяют по кругу раз в несколько секунд; ходы главного чата на уведомления и почту; заведение и чтение задач; смены чатов; размер поручений подагентам.
8. Ступени усилия и модели: доля каждой, цена шага на каждой.

Цена любого куска, попавшего в чат (файл, картинка, поручение), — первая запись плюс перечитка на каждом следующем шаге до конца чата.

Если можешь прочитать лимиты тарифа — скажи, сколько процентов недели уже ушло и на сколько часов нынешнего темпа хватит остатка. Не можешь — пропусти, не выдумывай.

## Что выдать

Мои личные советы: 5–8 способов тратить меньше при той же отдаче, по убыванию выгоды. У каждого — экономия в процентах от моего расхода, что именно сделать и что изменится для меня. Только то, что видно в моих журналах: общих советов не надо. Не предлагай модель или ступень слабее без цифр. Отдельно напиши, что проверил и что не подтвердилось.

Форма — одна страница: один HTML-файл без внешних ресурсов, читается на телефоне (ширина 420). Сверху три главные цифры крупно. Ниже — куда уходит (4–6 строк с процентами), файлы правил (сколько процентов и что срезать), способы с экономией. Подробности — свёртками: по дням и проектам, длинные чаты, что не подтвердилось, как считал и насколько точно. Пиши простыми словами, без жаргона: не «кеш», а «перечитка чата».

В чат — 5–7 строк: три главные цифры, три лучших способа, насколько точны оценки и путь к файлу.`;
  // Шаги «2/4» → сделано, всего и процент; мусор и ноль шагов — null.
  const pmpSteps = text => {
    const hit = /^\s*(\d+)\s*\/\s*(\d+)\s*$/.exec(String(text ?? ""));
    const total = hit ? Number(hit[2]) : 0;
    if (!(total > 0)) return null;
    const done = Math.min(Number(hit[1]), total);
    return { done, total, percent: Math.round(done / total * 100) };
  };
  // «13:05 → закончит в 13:50 · идёт 25 мин» → «закончит в 13:50 · идёт 25 мин»: время начала человеку не нужно.
  const pmpWhen = text => String(text ?? "").split("→").pop().trim();
  // Роль словами сводки без техники: «кодинг · 2 агента» → «кодинг».
  const pmpRole = text => String(text ?? "").split(/\s+·\s+/u).map(part => part.trim())
    .filter(part => part && !/агент|гейт|батч|opus|fable|sonnet|haiku|gpt|codex/iu.test(part)).join(" · ");
  // Строка сводки для показа: без разметки («**важно**», `код`) — её здесь никто не рисует.
  const pmpPlain = text => (typeof text === "string" ? text.replace(/\*\*|`/g, "").replace(/\s+/g, " ").trim() : "");
  const pmpTerminalsTitle = count => `${usagePlural(count, "Работает", "Работают", "Работают")} ${count} ${usagePlural(count, "терминал", "терминала", "терминалов")}`;
  // Ответ /digest (К6 с добавкой К-DG) → модель панели; чистая функция. Полей К-DG нет (старое
  // приложение) — known: false, «кто что делает» — проекты группы «идут».
  const pmpModel = data => {
    const list = (Array.isArray(data?.projects) ? data.projects : []).filter(item => item && typeof item === "object");
    const titles = list.map(project => String(project.title ?? "").trim() || String(project.name ?? "").trim());
    // Имена — коротко, как в блоке 12п² (rickShortName); совпали у двух — с буквой второй части
    // («PimpM», «PimpV»); совпали и так («PimpMyClaude» и «PimpMyTV») — вся такая семья целиком.
    const family = new Map();
    for (const title of titles) { const word = rickShortName(title); family.set(word, [...(family.get(word) ?? []), rickShortName(title, true)]); }
    const nameOf = title => {
      const word = rickShortName(title);
      const kin = family.get(word);
      if (kin.length < 2) return word;
      return new Set(kin).size === kin.length ? rickShortName(title, true) : title.split(/\s+[—–-]\s+/u)[0].trim() || title;
    };
    const known = list.some(project => typeof project.terminal === "boolean");
    const rows = [];
    const terminals = [];
    let flows = 0;
    let done = 0;
    let running = 0;
    list.forEach((project, index) => {
      const title = titles[index];
      const base = {
        key: String(project.name ?? "").trim() || title, title, name: nameOf(title),
        color: /^#[0-9a-f]{6}$/i.test(String(project.color ?? "")) ? String(project.color) : "",
      };
      // #10315 (К-FL): «идёт» — поле `live` приложения (время изменения содержимого, терминал, страница); группа «идут»
      // считается по mtime сводки, а его обновляют checkout и worktree add. Поля нет (старое приложение) — по группе.
      const live = typeof project.live === "boolean" ? project.live : String(project.group ?? "") === "идут";
      const cells = (Array.isArray(project.workflows) ? project.workflows : []).filter(flow => flow && typeof flow === "object").map(flow => {
        const n = Number.isFinite(Number(flow.n)) ? Number(flow.n) : "?";
        return { n, state: rickKindOf(flow) || "plan", about: pmpPlain(rickAbout(flow.about).text), steps: pmpSteps(flow.steps),
          when: pmpWhen(flow.when), role: pmpRole(flow.role) };
      });
      const count = state => cells.filter(cell => cell.state === state).length;
      // В блок Workflow — только проекты группы «идут» со своими Workflow; «о чём» — идущий, нет его — упавший или ждущий.
      if (live && cells.length) {
        const now = cells.find(cell => cell.state === "run") ?? cells.find(cell => cell.state === "fail" || cell.state === "wait");
        const row = { key: base.key, title, name: base.name, done: count("done"), total: cells.length, running: count("run"),
          failed: count("fail"), waiting: count("wait"), about: now?.about ?? "" };
        rows.push(row);
        flows += row.total; done += row.done; running += row.running;
      }
      const wait = pmpPlain(project.wait);
      const doing = pmpPlain(project.now);
      if (known ? project.terminal === true : live) {
        // #9846 класс (WF260): у давно молчащего проекта «идущих» нет — его сводка устарела.
        const going = live ? cells.filter(cell => cell.state === "run") : [];
        terminals.push({ ...base, text: doing || going[0]?.about || "", wait,
          flows: going.map(({ n, about, steps, when, role }) => ({ n, about, steps, when, role })) });
      }
    });
    return { rows, projects: rows.length, flows, done, running, known, terminals };
  };
  // Блок «Идёт Workflow» (лист 48 · 1.2) словами панели у часов (PanelTiles.nowHead/nowOpenHead, WF258).
  // Свёрнут: «Идут 7», «Идёт 1»; идущих нет, а проекты есть (упал, ждёт) — «Workflow»; проектов нет — «Тихо».
  const PMP_FLOWS_QUIET = "Тихо";
  const pmpFlowsHead = model => (model.running > 0 ? `${usagePlural(model.running, "Идёт", "Идут", "Идут")} ${model.running}`
    : (model.rows.length ? "Workflow" : PMP_FLOWS_QUIET));
  // Раскрыт: «Идут 7 Workflow · 4 проекта».
  const pmpFlowsOpenHead = model => [model.running > 0 ? `${pmpFlowsHead(model)} Workflow` : "Workflow",
    model.rows.length ? `${model.rows.length} ${usagePlural(model.rows.length, "проект", "проекта", "проектов")}` : ""].filter(Boolean).join(" · ");
  // Строка проекта в раскрытом списке: «2/3 · 1 идёт»; идущих нет — «упал» (fail — красным), «ждёт» или «готово».
  const pmpFlowsWords = row => {
    if (row.running > 0) return { text: `${row.running} ${usagePlural(row.running, "идёт", "идут", "идут")}`, fail: false };
    if (row.failed > 0) return { text: "упал", fail: true };
    if (row.waiting > 0) return { text: "ждёт", fail: false };
    return { text: row.done === row.total ? "готово" : "", fail: false };
  };
  // Подсказка и VoiceOver свёрнутой строки — по строке на проект, как у панели у часов (nowHelp).
  const pmpFlowsHelp = model => (model.rows.length ? [pmpFlowsOpenHead(model), ...model.rows.map(row => {
    const words = pmpFlowsWords(row).text;
    return `${row.title}: готово ${row.done} из ${row.total}${words && words !== "готово" ? `, ${words}` : ""}${row.about ? ` — ${row.about}` : ""}`;
  })].join("\n") : "Workflow сейчас не идут");
  // Сколько проектов свёрнутой строки входит в width целиком; не вошли — «+N» за ними (его место тоже считается).
  const PMP_FLOWS_FONT = "400 12px -apple-system, system-ui, sans-serif";
  const PMP_FLOWS_BOLD = "600 12px -apple-system, system-ui, sans-serif";
  const pmpFlowsFit = (model, width) => {
    const items = model.rows.map(row => rickMeasure(` · ${row.name}`, PMP_FLOWS_FONT) + rickMeasure(` ${row.done}/${row.total}`, PMP_FLOWS_BOLD));
    const head = rickMeasure(pmpFlowsHead(model), PMP_FLOWS_BOLD);
    for (let shown = items.length; shown > 0; shown -= 1) {
      const more = shown < items.length ? rickMeasure(` · +${items.length - shown}`, PMP_FLOWS_BOLD) : 0;
      if (head + items.slice(0, shown).reduce((sum, item) => sum + item, 0) + more <= width) return shown;
    }
    return 0;
  };
  const pmpPanelNode = (() => {
    for (const orphan of document.querySelectorAll(`#${PMP_PANEL_ID}`)) orphan.remove();
    const node = document.createElement("div");
    node.id = PMP_PANEL_ID;
    node.setAttribute("role", "group");
    node.setAttribute("aria-label", PMP_TITLE);
    (document.body ?? document.documentElement).appendChild(node);
    track(() => node.remove());
    return node;
  })();
  // Тело с прокруткой и строка команд под ним (всегда на виду).
  const pmpBody = rickAdd(pmpPanelNode, "div");
  const pmpNav = rickAdd(pmpPanelNode, "nav");
  const pmpPart = (parent, k, tag = "span", text = null) => {
    const node = rickAdd(parent, tag, text);
    node.dataset.k = k;
    return node;
  };
  const pmpButton = (parent, act, text) => {
    const node = rickAdd(parent, "button", text);
    node.type = "button";
    node.dataset.act = act;
    return node;
  };
  const pmpHead = (section, text) => rickAdd(section, "h3", text);
  // Блок «Идёт Workflow» (лист 48 · 1.2): строка-кнопка; свёрнута — шапка и проекты «· Pimp 2/3» (что не
  // влезло, прячет pmpFlowsLineFit и пишет «+N»), раскрыта — шапка «Идут 7 Workflow · 4 проекта» и под
  // ней строка на проект: имя колонкой, справа «2/3 · 1 идёт» и о чём идущий. Проектов нет — «Тихо» без нажатия.
  // Ответ — текст свёрнутой строки (его меряет pmpFlowsLineFit), раскрыто или пусто — null.
  const pmpFlowsBlock = (section, model) => {
    if (!model.rows.length) {
      pmpHead(section, PMP_FLOWS_QUIET).title = pmpFlowsHelp(model);
      return null;
    }
    const open = pmpPanel.flows;
    const line = pmpButton(section, "flows", null);
    line.dataset.k = "line";
    line.setAttribute("aria-expanded", open ? "true" : "false");
    line.title = open ? "Свернуть" : pmpFlowsHelp(model);
    const text = pmpPart(line, "ln");
    pmpPart(text, "hd", "b", open ? pmpFlowsOpenHead(model) : pmpFlowsHead(model));
    if (!open) {
      for (const row of model.rows) {
        const item = pmpPart(text, "it");
        rickAdd(item, "span", ` · ${row.name}`);
        rickAdd(item, "b", ` ${row.done}/${row.total}`);
      }
      pmpPart(text, "more", "b");
      return text;
    }
    for (const row of model.rows) {
      const item = pmpPart(section, "row", "div");
      item.dataset.kind = "flow";
      pmpPart(item, "nm", "b", row.name).title = row.title;
      const side = pmpPart(item, "fw", "div");
      const words = pmpFlowsWords(row);
      const count = pmpPart(side, "fc", "p");
      rickAdd(count, "b", `${row.done}/${row.total}`);
      if (words.text) {
        rickAdd(count, "span", " · ");
        const tail = rickAdd(count, "span", words.text);
        if (words.fail) tail.dataset.fail = "true";
      }
      if (row.about) pmpPart(side, "fa", "p", row.about);
    }
    return null;
  };
  // Свёрнутая строка — одной строкой в ширину панели: лишние проекты прячутся, за видимыми — «+N».
  // Меряется по ширине, которую поставил pmpPanelPlace (поля тела — по 14 с боков).
  function pmpFlowsLineFit() {
    const text = pmpPanel.line;
    const model = pmpPanel.model;
    if (!text?.isConnected || !model) return;
    const width = (parseFloat(pmpPanelNode.style.getPropertyValue("width")) || PMP_PANEL_WIDTH) - 28;
    const shown = pmpFlowsFit(model, width);
    const items = [...text.children].filter(node => node.dataset.k === "it");
    items.forEach((node, index) => {
      if (index < shown) node.style.removeProperty("display"); else node.style.setProperty("display", "none");
    });
    const more = [...text.children].find(node => node.dataset.k === "more");
    const tail = shown < items.length ? ` · +${items.length - shown}` : "";
    if (more && more.textContent !== tail) more.textContent = tail;
  }
  // Строка «имя — текст»: есть что раскрыть — кнопка (нажал — текст целиком и плашка под ней), нет — просто строка.
  const pmpTextRow = (section, kind, item, plate) => {
    const id = `${kind}:${item.key}`;
    const fold = Boolean(item.text) || plate;
    const line = fold ? pmpButton(section, "row", null) : pmpPart(section, "row", "div");
    if (fold) { line.dataset.k = "row"; line.dataset.id = id; line.setAttribute("aria-expanded", pmpPanel.rows.has(id) ? "true" : "false"); }
    line.dataset.kind = kind;
    if (item.color) line.style.setProperty("--c", item.color);
    pmpPart(line, "nm", "b", item.name);
    if (item.text) pmpPart(line, "tx", "span", item.text);
    return id;
  };
  // Серая плашка под строкой терминала: идущие Workflow («о чём», роль, шаги и процент, когда закончит), чего ждёт.
  const pmpPlate = (section, id, item) => {
    const plate = pmpPart(section, "plate", "div");
    plate.dataset.id = id;
    plate.dataset.open = pmpPanel.rows.has(id) ? "true" : "false";
    const box = rickAdd(rickAdd(plate, "div"), "div");
    for (const flow of item.flows) {
      pmpPart(box, "pf", "p", flow.about || `Workflow ${flow.n}`);
      const meta = [flow.role, flow.steps ? `шаги ${flow.steps.done} из ${flow.steps.total} · ${flow.steps.percent} %` : "", flow.when].filter(Boolean).join(" · ");
      if (meta) pmpPart(box, "pm", "p", meta);
      if (flow.steps) pmpPart(box, "bar", "u").style.setProperty("--p", `${flow.steps.percent}%`);
    }
    if (item.wait) {
      const wait = pmpPart(box, "pw", "p");
      rickAdd(wait, "b", "Ждёт тебя: ");
      rickAdd(wait, "span", item.wait);
    }
  };
  const pmpPanelState = () => (pmpPanel.error ? "error" : (pmpPanel.model && now() - rickState.okAt < RICK_CELLS_STALE_MS ? "ok" : "load"));
  // Ширина колонки имён — по самому длинному из показанных: имена обоих блоков встают одной колонкой.
  const pmpNameWidth = model => {
    const font = "500 12px -apple-system, system-ui, sans-serif";
    const names = [...(pmpPanel.flows ? model.rows : []), ...model.terminals].map(item => item.name);
    return Math.min(PMP_NAME_MAX, Math.ceil(Math.max(28, ...names.map(name => rickMeasure(name, font))) + 2));
  };
  // Собрать тело и команды заново — только при смене данных или вида: прокрутка и фокус остаются.
  function pmpPanelRender() {
    const view = pmpPanelState();
    const model = view === "ok" ? pmpPanel.model : null;
    const sig = JSON.stringify([view, model, pmpPanel.flows, Boolean(pmpPanel.kickoff), pmpKickKnown]);
    if (sig !== pmpPanel.sig) {
      pmpPanel.sig = sig;
      const focus = pmpPanelNode.contains(document.activeElement) ? document.activeElement : null;
      const held = focus ? { act: focus.dataset?.act ?? "", id: focus.dataset?.id ?? "" } : null;
      const scroll = Number(pmpBody.scrollTop) || 0;
      pmpPanel.line = null;
      while (pmpBody.firstChild) pmpBody.firstChild.remove();
      while (pmpNav.firstChild) pmpNav.firstChild.remove();
      pmpPanelNode.dataset.state = view;
      if (view === "load") pmpPart(pmpBody, "note", "p", "Смотрю, что идёт…");
      if (view === "error") pmpPart(pmpBody, "note", "p", PMP_DOWN_TEXT);
      if (model) {
        pmpPanelNode.style.setProperty("--nm", `${pmpNameWidth(model)}px`);
        if (PMP_FLOWS_SHOWN) {
          pmpPanel.line = pmpFlowsBlock(pmpPart(pmpBody, "flows", "section"), model);
        }
        if (model.terminals.length || model.known) {
          const terms = pmpPart(pmpBody, "terms", "section");
          pmpHead(terms, model.known ? (model.terminals.length ? pmpTerminalsTitle(model.terminals.length) : "Терминалы сейчас не работают") : "Кто что делает");
          for (const item of model.terminals) {
            const plate = item.flows.length > 0 || Boolean(item.wait);
            const id = pmpTextRow(terms, "term", item, plate);
            if (plate) pmpPlate(terms, id, item);
          }
        }
      }
      // Команды (#9552): три главные — всегда, столбцом, с подписью; текста запуска нет (К-KO, контракт 490) — подпись
      // «Нужен PMP у часов». Ниже строкой мелкие; приложение молчит — «Настройки PMP» нет.
      for (const item of PMP_MAIN) {
        const main = pmpButton(pmpNav, item.act, null);
        main.dataset.k = "main";
        main.title = item.title;
        rickAdd(main, "b", item.name);
        rickAdd(main, "span", item.act === "kickoff" && pmpKickKnown && !pmpPanel.kickoff ? PMP_KICKOFF_NONE : item.note);
      }
      const small = (act, text) => { const node = pmpButton(pmpNav, act, text); node.dataset.k = "small"; return node; };
      small("report", "Отчёт").title = `Вставить в поле «${RICK_REPORT_TEXT}» (отправишь сам)`;
      small("ask", "Что происходит").title = `Вставить в поле «${PMP_ASK_TEXT}» (отправишь сам)`;
      if (view !== "error") small("settings", "Настройки PMP").title = "Открыть панель PimpMyClaude у часов";
      pmpBody.scrollTop = scroll;
      pmpPanelPlace();
      pmpPanelFlat();
      pmpFlowsLineFit();
      if (held) {
        const again = pmpPanelItems().find(node => (node.dataset.act ?? "") === held.act && (node.dataset.id ?? "") === held.id);
        try { (again ?? pmpPanelItems()[0])?.focus(); } catch {}
      }
      return;
    }
    pmpPanelPlace();
  }
  // Строка без плашки, чей текст и так виден целиком (до двух строк), раскрывать нечем: стрелки нет,
  // нажатие и Tab её не берут (data-flat). Меряется по живой ширине — после постановки панели.
  function pmpPanelFlat() {
    let rows = [];
    try { rows = [...pmpBody.querySelectorAll("button")].filter(node => node.dataset.k === "row"); } catch { rows = []; }
    for (const row of rows) {
      const text = row.children[1];
      const plate = row.nextElementSibling?.dataset?.k === "plate";
      const flat = !plate && row.getAttribute("aria-expanded") !== "true" && Boolean(text) && Number(text.scrollHeight) <= Number(text.clientHeight) + 1;
      if (flat) row.dataset.flat = "true"; else delete row.dataset.flat;
    }
  }
  const pmpPanelItems = () => { try { return [...pmpPanelNode.querySelectorAll("button")].filter(node => node.dataset.flat !== "true"); } catch { return []; } };
  function pmpPanelFocus(index) { try { pmpPanelItems().at(index)?.focus(); } catch {} }
  // Низ тела затухает, пока есть что прокрутить: обрезанное не выглядит концом списка (как у сводки 12п²).
  const pmpPanelMore = () => {
    const more = Number(pmpBody.scrollHeight) > Number(pmpBody.clientHeight) + Number(pmpBody.scrollTop) + 2;
    if (pmpBody.dataset.more !== String(more)) pmpBody.dataset.more = String(more);
  };
  // Место: над полем ввода по его левому краю, не шире поля и PMP_PANEL_WIDTH; поле свёрнуто — над
  // кнопкой. Высота — до PMP_PANEL_SHARE окна и не выше места над полем; длиннее — прокрутка тела.
  // WF226: над полем тесно (широкий вид — поле колонкой во всю высоту окна; низкое окно; длинный
  // черновик) — панель встаёт сбоку от поля, низом по его нижней грани; нет места и сбоку — над
  // кнопкой, поверх поля. Нижней границы высоты больше нет: панель всегда целиком в окне.
  function pmpPanelPlace() {
    if (!pmpPanel.open) return;
    const folded = state.stage === STAGE_COLLAPSED;
    const frame = folded ? null : (rickRect(state.shell) ?? rickRect(state.composerBlock));
    const read = name => parseFloat(pmpNode.style.getPropertyValue(name));
    const spot = { left: read("left"), top: read("top") };
    const top = Math.min(frame?.top ?? Infinity, Number.isFinite(spot.top) ? spot.top : Infinity);
    const anchor = Number.isFinite(top) ? top : innerHeight - 40;
    // Поле видно — панель по его краю и не шире его (в узком окне — во всю ширину поля); нет — с полями 8 от окна.
    const edge = frame ? Math.max(0, Math.min(8, frame.left)) : 8;
    let width = Math.round(Math.max(120, Math.min(PMP_PANEL_WIDTH, frame?.width ?? PMP_PANEL_WIDTH, innerWidth - 2 * edge)));
    const wish = frame ? frame.left : (Number.isFinite(spot.left) ? spot.left + pmpWidth() - width : edge);
    let left = Math.round(Math.max(edge, Math.min(wish, innerWidth - width - edge)));
    // Пишем только сменившееся: место считается на каждом проходе раскладки.
    const style = pmpPanelNode.style;
    const put = (name, value) => { if (style.getPropertyValue(name) === value) return false; style.setProperty(name, value); return true; };
    // Низ панели — на 6 выше base. Сбоку от поля — слева, а где слева тесно — справа.
    let base = anchor;
    const above = anchor - 6 - PMP_PANEL_EDGE;
    const roomLeft = frame ? frame.left - 6 - PMP_PANEL_EDGE : 0;
    const roomRight = frame ? innerWidth - frame.right - 6 - PMP_PANEL_EDGE : 0;
    const beside = above < PMP_PANEL_ROOM && Math.max(roomLeft, roomRight) >= PMP_PANEL_SIDE;
    if (beside) {
      width = Math.round(Math.min(PMP_PANEL_WIDTH, Math.max(roomLeft, roomRight)));
      left = Math.round(roomLeft >= roomRight ? frame.left - 6 - width : frame.right + 6);
      // Низ — по нижней грани поля; поле короткое и стоит высоко — ниже, чтобы панели хватило высоты.
      base = Math.min(Math.max(frame.bottom, PMP_PANEL_EDGE + PMP_PANEL_ROOM), innerHeight - PMP_PANEL_EDGE) + 6;
    }
    const resized = put("width", `${width}px`);
    const shown = put("display", "flex");
    // Команды меряются уже в своей ширине (в узком окне они в две-три строки) и только когда тесно.
    if (frame && !beside && above < PMP_PANEL_ROOM && Number.isFinite(spot.top)
      && above < (Number(pmpNav.getBoundingClientRect().height) || 0) + PMP_PANEL_BODY) base = spot.top;
    put("left", `${left}px`);
    put("bottom", `${Math.round(innerHeight - base + 6)}px`);
    put("max-height", `${Math.max(0, Math.round(Math.min(Math.max(innerHeight * PMP_PANEL_SHARE, PMP_PANEL_ROOM), base - 6 - PMP_PANEL_EDGE)))}px`);
    const narrow = width < PMP_PANEL_NARROW ? "true" : "false";
    if (pmpPanelNode.dataset.narrow !== narrow) pmpPanelNode.dataset.narrow = narrow;
    // Цвета — от поля ввода: текст и фон поля, обводка — текст 15 %;
    // полоска шагов в плашке — янтарь (макет 32), «упал» — красный.
    const host = state.shell ?? state.composerBlock;
    const dark = progressDark();
    const skin = PROGRESS_CARD_SKIN[dark ? "dark" : "light"];
    const T = progressTextColor(host);
    const F = progressFieldColor(host);
    for (const [name, value] of [["--T", T], ["--F", dark ? `color-mix(in srgb, ${F}, ${T} 7%)` : F],
      ["--Y", dark ? "rgb(245,158,11)" : "rgb(202,120,6)"], ["--R", `rgb(${skin.fail})`], ["--L", progressTint(T, 15)], ["--S", skin.shadow]]) put(name, value);
    // Ширина сменилась (окно тянут) — перемерить, какие строки ещё есть чем раскрыть и сколько проектов входит в строку Workflow.
    if (shown || resized) { pmpPanelFlat(); pmpFlowsLineFit(); }
    pmpPanelMore();
  }
  on(pmpBody, "scroll", () => pmpPanelMore(), { passive: true });
  // «Сэкономить подписку» (#9547): как «Отчёт» — в конец поля с новой строки, черновик остаётся, не отправляет. Повтор
  // второй копии не делает: первая строка промпта уже в хвосте поля (пробелы схлопнуты) — только фокус и курсор в
  // конец. Сверка всего текста с концом поля, как у rickReport, повтор не ловит: редактор переписывает переносы и «## ».
  const pmpFlat = value => String(value ?? "").replace(/\s+/g, " ").trim();
  const PMP_SAVE_HEAD = pmpFlat(PMP_SAVE_TEXT.split("\n")[0]);
  const PMP_SAVE_TAIL = pmpFlat(PMP_SAVE_TEXT).length + 500;
  const pmpSave = () => {
    const editor = state.editor?.isConnected ? state.editor : findEditor();
    if (!editor?.isConnected) return false;
    if (!pmpFlat(rawText(editor)).slice(-PMP_SAVE_TAIL).includes(PMP_SAVE_HEAD)) return rickReport(PMP_SAVE_TEXT);
    if (state.stage === STAGE_COLLAPSED) setStage(STAGE_NORMAL);
    try { editor.focus(); } catch {}
    caretToEnd(editor);
    return true;
  };
  // Команда панели: «Настройки Пимпа» — панель у часов (pmpOpen); остальные кладут текст в поле и не
  // отправляют. «Запустить Workflow» — текст запуска перед черновиком (как 12а), фразы — с новой строки
  // в конец (как «Отчёт» 12п²): набранное человеком не затирается. Поля нет — подсказка у кнопки.
  // «Сэкономить подписку» (#9547) — промпт PMP_SAVE_TEXT тем же путём, что «Отчёт» (pmpSave); «Всё в одном чате»
  // (#9552) — GET /one-chat тем же путём, что «Настройки Пимпа»; текста запуска нет — подсказка, поле не трогаем.
  const pmpCommand = act => {
    pmpPanel.last = act;
    if (act === "settings") { pmpPanelClose(); return pmpOpen(); }
    if (act === "one") {
      pmpPanelClose();
      const sent = pmpOpen(PMP_ONE_CHAT_PATH);
      if (!sent && pmpNode.dataset.state === "wait") micHint(PMP_ONE_WAIT, pmpNode, PMP_WIDTH);
      return sent;
    }
    let ok = false;
    let hint = PMP_FIELD_TEXT;
    if (act === "kickoff") {
      if (pmpPanel.kickoff) ok = runWorkflowCommand({ text: pmpPanel.kickoff });
      else hint = PMP_KICKOFF_NONE;
    } else if (act === "report") ok = rickReport(RICK_REPORT_TEXT);
    else if (act === "ask") ok = rickReport(PMP_ASK_TEXT);
    else if (act === "save") ok = pmpSave();
    else return false;
    pmpPanelClose();
    if (!ok) micHint(hint, pmpNode, PMP_WIDTH);
    return ok;
  };
  on(pmpPanelNode, "click", event => {
    event.preventDefault();
    event.stopPropagation();
    if (!state.alive || !pmpPanel.open || Number(event.detail) > 1) return;
    const button = event.target?.closest?.("button");
    const act = button?.dataset?.act;
    if (!act || !pmpPanelNode.contains(button)) return;
    // Строка Workflow: раскрыть список по проектам или свернуть — пересборкой (шапка у строки другая).
    if (act === "flows") { pmpPanel.flows = !pmpPanel.flows; pmpPanelRender(); return; }
    if (act !== "row") { try { pmpCommand(act); } catch {} return; }
    // Строка: раскрыть или задвинуть — без пересборки, плашка выезжает переходом (правило в RULES).
    if (button.dataset.flat === "true") return;
    const id = button.dataset.id;
    const open = !pmpPanel.rows.has(id);
    if (open) pmpPanel.rows.add(id); else pmpPanel.rows.delete(id);
    button.setAttribute("aria-expanded", open ? "true" : "false");
    const plate = button.nextElementSibling;
    if (plate?.dataset?.k === "plate" && plate.dataset.id === id) plate.dataset.open = open ? "true" : "false";
    pmpPanelMore();
  });
  // Нажатие мышью фокус поля не отнимает и до слушателей Claude не всплывает (как у полосы 12п²).
  on(pmpPanelNode, "pointerdown", rickKeep);
  on(pmpPanelNode, "mousedown", rickKeep);
  // Текст запуска Workflow (К-KO): GET /kickoff при открытии; 404, отказ или старое приложение — подпись
  // «Нужен PMP у часов» (#9552). Первый ответ перерисовывает и тогда, когда текста как не было, так и нет.
  const pmpKickoffAsk = () => {
    const seq = pmpPanel.kickSeq += 1;
    const settle = text => {
      if (seq !== pmpPanel.kickSeq || !state.alive) return;
      const value = typeof text === "string" && text.trim() ? text : null;
      const fresh = !pmpKickKnown || pmpPanel.kickoff !== value;
      pmpKickKnown = true;
      pmpPanel.kickoff = value;
      if (fresh && pmpPanel.open) pmpPanelRender();
    };
    let sent = null;
    if (typeof fetch === "function") {
      try { sent = fetch(`http://127.0.0.1:${HTML_CHROME_PORT}/kickoff`, { mode: "cors", credentials: "omit", cache: "no-store" }); } catch { sent = null; }
    }
    if (!sent || typeof sent.then !== "function") { settle(null); return; }
    sent.then(reply => (reply?.ok && typeof reply.text === "function" ? reply.text() : null)).then(settle, () => settle(null));
  };
  // Ответ общего запроса сводки (rickFetch): data — тело /digest, null — приложение не ответило.
  function pmpPanelFed(data) {
    const before = pmpRunning();
    if (data) { pmpPanel.model = pmpModel(data); pmpPanel.error = null; }
    else pmpPanel.error = PMP_DOWN_TEXT;
    if (pmpPanel.open) pmpPanelRender();
    // Знак «▶N» у кнопки сменился — кнопке другая ширина, место считает раскладка.
    if (pmpRunning() !== before) scheduleLayout();
  }
  // Esc — закрыть (фокус из панели возвращается в поле); Tab — по пунктам панели по кругу. Открыто меню
  // Claude (панель под ним не видна) — клавиши его: панель только закрывается. Зовёт общий слушатель
  // окна (onKeyDown, как pin-bulk и счёт отправки): он глотает Esc на захвате раньше слушателей
  // document, своего слушателя клавиш у панели нет. true — клавиша наша, дальше её не пускать.
  function onPmpPanelKey(event) {
    if (!pmpPanel.open || !state.alive) return false;
    let popup = null;
    try { popup = document.querySelector(CLAUDE_POPUP_SELECTOR); } catch { popup = null; }
    if (event.key === "Escape") {
      const inside = pmpPanelNode.contains(document.activeElement);
      pmpPanelClose();
      if (popup) return false;
      event.preventDefault();
      event.stopImmediatePropagation();
      if (inside) { try { (state.editor?.isConnected ? state.editor : pmpNode).focus(); } catch {} }
      return true;
    }
    if (event.key !== "Tab" || popup) return false;
    const items = pmpPanelItems();
    if (!items.length) return false;
    event.preventDefault();
    event.stopImmediatePropagation();
    const at = items.indexOf(document.activeElement);
    const next = at < 0 ? (event.shiftKey ? items.length - 1 : 0) : (at + (event.shiftKey ? -1 : 1) + items.length) % items.length;
    try { items[next].focus(); } catch {}
    return true;
  }
  const pmpPanelOutside = event => {
    const target = event.target;
    if (target && (pmpPanelNode.contains(target) || pmpNode.contains(target))) return;
    pmpPanelClose();
  };
  // Опрос открытой панели: запрос висит дольше срока опроса — приложение молчит (строка об этом), новый уйдёт позже.
  const pmpPanelPoll = () => {
    if (!pmpPanel.open || document.hidden) return;
    if (rickState.busy && now() - rickState.triedAt >= PMP_PANEL_MS && !pmpPanel.error) pmpPanelFed(null);
    rickFetch();
  };
  const pmpPanelOpen = () => {
    if (pmpPanel.open || !pmpWanted()) return false;
    pmpPanel.open = true;
    pmpPanel.opens += 1;
    pmpPanel.sig = "";
    // Прошлый отказ не показываем: сводку спросим заново прямо сейчас.
    pmpPanel.error = null;
    pmpNode.setAttribute("aria-expanded", "true");
    document.addEventListener("pointerdown", pmpPanelOutside, true);
    pmpPanel.timer = setInterval(() => { try { pmpPanelPoll(); } catch {} }, PMP_PANEL_MS);
    pmpPanelRender();
    pmpPanelPoll();
    pmpKickoffAsk();
    return true;
  };
  function pmpPanelClose() {
    if (!pmpPanel.open) return false;
    pmpPanel.open = false;
    pmpNode.setAttribute("aria-expanded", "false");
    document.removeEventListener("pointerdown", pmpPanelOutside, true);
    if (pmpPanel.timer) { clearInterval(pmpPanel.timer); pmpPanel.timer = 0; }
    pmpPanelNode.style.setProperty("display", "none");
    return true;
  }
  function pmpPanelToggle() { return pmpPanel.open ? (pmpPanelClose(), false) : pmpPanelOpen(); }
  track(() => { pmpPanel.kickSeq += 1; pmpPanelClose(); });
  // Для status().pmp: открыта ли, проектов в блоке Workflow и раскрыт ли он, терминалов, идущих Workflow,
  // чем кончился запрос.
  const pmpPanelStatus = () => {
    const model = pmpPanelState() === "ok" ? pmpPanel.model : null;
    return {
      open: pmpPanel.open, rows: model && PMP_FLOWS_SHOWN ? model.rows.length : 0, flowsOpen: pmpPanel.flows,
      terminals: model ? model.terminals.length : 0, running: pmpRunning(), lastError: pmpPanel.error,
    };
  };
  HATCH && Object.assign(HATCH, { pmpModel, pmpSteps, pmpWhen, pmpRole, pmpTerminalsTitle, pmpFlowsHead,
    pmpFlowsOpenHead, pmpFlowsWords, pmpFlowsHelp, pmpFlowsFit, PMP_SAVE_TEXT, PMP_SAVE_TITLE, PMP_MAIN });
  // Три главные команды (#9552): столбцом во всю ширину, подпись мелко под названием (перебивает nowrap, отступы и
  // жирность «Запустить Workflow» общих правил строки команд); мелкие — ниже строкой, кегль 11.
  lateRules.push(
    `#${PMP_PANEL_ID}>nav>button[data-k="main"]{flex:0 0 100%;display:flex;flex-direction:column;align-items:flex-start;gap:1px;padding:5px 10px 6px;white-space:normal;text-align:left}`,
    `#${PMP_PANEL_ID}>nav>button[data-k="main"]>b{font-weight:500}`,
    `#${PMP_PANEL_ID}>nav>button[data-k="main"]>span{font:400 11px/14px -apple-system,system-ui,sans-serif;opacity:.65;white-space:normal}`,
    `#${PMP_PANEL_ID}>nav>button[data-k="small"]{min-height:22px;padding-top:2px;padding-bottom:2px;font-size:11px}`,
  );

