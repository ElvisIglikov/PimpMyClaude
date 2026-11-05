  // ---- 12. «Обкэшить» -----------------------------------------------------
  // Переносит в поле ввода нового чата последний ответ Claude и текущий
  // черновик. Само открытие нового чата делает Hammerspoon (⌘N) — здесь только
  // запись переноса и вставка на другой стороне. Донор тут не помощник: у него
  // для этого свой канал наружу.
  const rawText = node => {
    if (!node?.isConnected) return "";
    if (typeof node.value === "string") return node.value;
    return node.innerText ?? node.textContent ?? "";
  };
  // Пустой ProseMirror держит переносы и невидимые заполнители — они не текст.
  const editorText = (node = state.editor) => rawText(node).replace(/[\s\u200B\uFEFF]+/g, "");
  // Примета реплики самого Элвиса — .epitaxy-user-turn внутри или снаружи; ещё
  // отсеиваем строку действий под ответом (там «3 minutes ago», а не текст) и
  // само поле ввода.
  const answerUsable = node =>
    !node.closest('[aria-label="Message actions"],[aria-label="Действия с сообщением"]') &&
    !node.closest(".epitaxy-user-turn") &&
    !node.querySelector(".epitaxy-user-turn") &&
    !state.composerBlock?.contains(node) &&
    Boolean((node.textContent ?? "").trim());
  // Последний по документу — но только среди внешних узлов: один ответ даёт
  // несколько совпадений (вложенные куски), и «просто последний» брал бы кусок.
  const pickAnswer = list => {
    const nodes = [...list].filter(answerUsable);
    const outer = nodes.filter(node => !nodes.some(other => other !== node && other.contains(node)));
    return outer[outer.length - 1] ?? null;
  };
  // Строгая примета разметки, если она сегодня жива, надёжнее общего списка.
  // Claude 2.9939.2 (#7725): testid «assistant-message» пропал, ответ разбит на
  // строки ленты [data-testid="transcript-row"] (data-perf-row assistant_tool,
  // assistant_text, …), aria-label «Message N» — только у первой, обычно у
  // вызова инструмента. Запасной селектор брал её — без текста ответа, и блок
  // «ОТКРОЙ НОВЫЙ ЧАТ» не находился. Текст — в последней строке assistant_text.
  // Живьём 26.09 ~07:20 (попап VkusnoffKz): законченный ход бывает ОДНОЙ строкой data-perf-row="assistant"
  // (текст, инструменты и блок вместе, «Claude responded: …»), без «_text» — блок передачи не находился, ни
  // ссылки на «ОТКРОЙ НОВЫЙ ЧАТ», ни кнопки. Такая строка — ответ наравне с assistant_text.
  const lastAnswerNode = () =>
    pickAnswer(document.querySelectorAll('[data-testid="assistant-message"]'))
    ?? pickAnswer(document.querySelectorAll('[data-testid="transcript-row"][data-perf-row="assistant_text"],[data-testid="transcript-row"][data-perf-row="assistant"]'))
    ?? pickAnswer(document.querySelectorAll(ANSWER_SELECTOR));
  // Последнее сообщение агента на 2.9939.2 целиком (WF93-g): одно сообщение —
  // несколько строк ленты подряд с общим data-epitaxy-entry (текст, вызов
  // инструмента, снова текст), и блок «ОТКРОЙ НОВЫЙ ЧАТ» с хвостовым повтором
  // заголовка может лечь в разные строки. Отдаём строки текста агента
  // (assistant_text и assistant) всего хода после последней реплики человека,
  // по порядку. Ниже последнего сообщения агента реплика человека
  // (data-perf-row="human", живая проба 25.09) — ответа на неё ещё нет: [], и
  // старый блок над ней не наш (К1). Строк ленты нет — null, старая разметка.
  const ANSWER_ROW_SELECTOR = '[data-testid="transcript-row"][data-perf-row]';
  const answerRowKind = row => String(row.getAttribute("data-perf-row") ?? "");
  const answerRowAgent = kind => kind === "assistant" || kind.startsWith("assistant_");
  const lastAnswerRows = () => {
    let rows = [];
    try { rows = [...document.querySelectorAll(ANSWER_ROW_SELECTOR)]; } catch { return null; }
    let at = rows.length - 1;
    for (; at >= 0; at -= 1) {
      const kind = answerRowKind(rows[at]);
      if (kind === "human") return [];
      if (answerRowAgent(kind)) break;
    }
    if (at < 0) return null;
    // Весь ход агента после последней реплики человека, а не одно сообщение (entry): после
    // текста с блоком агент часто зовёт ещё инструмент, и 2.9939.2 кладёт его новым entry —
    // блок тогда оказывался «не в последнем ответе» (живьём 26.09, попап VkusnoffKz).
    const parts = [];
    for (; at >= 0; at -= 1) {
      const kind = answerRowKind(rows[at]);
      if (kind === "human") break;
      if ((kind === "assistant_text" || kind === "assistant") && answerUsable(rows[at])) parts.unshift(rows[at]);
    }
    return parts;
  };
  const lastAnswerText = () => {
    const hit = lastAnswerNode();
    if (hit == null) return "";
    // innerText исключает именно свои узлы: совпавшие «3», «ok», «…» в ответе
    // остаются. Inline display и его приоритет возвращаем даже при ошибке чтения.
    const hidden = [];
    try {
      for (const node of hit.querySelectorAll(`[${RUN_ATTRIBUTE}],[${RUN_OUT_ATTRIBUTE}]`)) {
        hidden.push([node, node.style.getPropertyValue("display"), node.style.getPropertyPriority?.("display") ?? ""]);
        node.style.setProperty("display", "none", "important");
      }
      return rawText(hit).trim();
    } finally {
      for (const [node, display, priority] of hidden) {
        if (display) node.style.setProperty("display", display, priority);
        else node.style.removeProperty("display");
      }
    }
  };
  const clearCashout = () => { try { localStorage.removeItem(CASHOUT_KEY); } catch {} };
  const readCashout = () => {
    try {
      const raw = localStorage.getItem(CASHOUT_KEY);
      if (!raw) return null;
      const data = JSON.parse(raw);
      const at = Number(data?.at);
      const text = typeof data?.text === "string" ? data.text : "";
      // Запись «Нового чата» (К1, #7072) живёт и с пустым текстом: блока
      // «ОТКРОЙ НОВЫЙ ЧАТ» в последнем ответе нет — новый чат пустой, а не отказ.
      const handoff = data?.handoff === true;
      if ((!text && !handoff) || !Number.isFinite(at)) return null;
      const record = { at, text };
      if (handoff) {
        record.handoff = true;
        record.sent = data?.sent === true;
        // Модель и ступень из строки «Модель:» блока (WF85, К7.3, критик В1):
        // без них цепочка new-window не узнала бы, что просил блок.
        const model = typeof data?.model === "string" ? data.model.trim().slice(0, 80) : "";
        const effort = typeof data?.effort === "string" ? data.effort.trim().slice(0, 20) : "";
        if (model) record.model = model;
        if (effort) record.effort = effort;
      }
      // Поля переноса (WF37, эталоны tests/fixtures/cashout): to — кому запись
      // предназначена (CASHOUT_PENDING — адресата ещё нет), title — заголовок
      // строки сайдбара нового чата, stampedAt — когда штамповали. Поля to нет
      // — это обычная запись главного окна, и правила у неё прежние.
      const to = typeof data?.to === "string" ? data.to.trim() : "";
      if (!to) return record;
      record.to = to;
      record.title = typeof data?.title === "string" ? data.title.trim() : "";
      const stampedAt = Number(data?.stampedAt);
      record.stampedAt = Number.isFinite(stampedAt) ? stampedAt : null;
      // Отказ цепочки «Нового окна» (#5592, cashoutRefuse): почему перенос не уедет.
      const refused = typeof data?.refused === "string" ? data.refused.trim().slice(0, 200) : "";
      if (refused) record.refused = refused;
      return record;
    } catch { return null; }
  };
  // Последний отказ «Обкэшить» — то же слово, что показала плашка. Гейту по нему
  // видно, почему записи нет; удачный перенос его снимает.
  let cashoutRefusal = null;
  // Приговор доставки ЭТОГО окна и запись, которой он принадлежит (WF50, #5779).
  // Живёт в памяти окна и переживает снос записи: приложение спрашивает страницу
  // уже после того, как перенос лёг и запись стёрта.
  //
  // `cashoutVerdictUntil` — докуда могла бы дожить САМА запись (#5788): дольше
  // неё приговор не живёт ни при каких условиях.
  let cashoutVerdict = "";
  let cashoutVerdictAt = 0;
  let cashoutVerdictUntil = 0;
  const cashoutSay = (at, until, word) => {
    cashoutVerdict = word;
    cashoutVerdictAt = Number(at) || 0;
    cashoutVerdictUntil = Number(until) || 0;
  };
  // Срок жизни записи: у переноса он считается от ШТАМПА (адресата называют
  // через несколько секунд после нажатия), у обычной записи главного окна — от
  // нажатия. Те же два срока проверяет tryPasteCashout, когда решает, не
  // протухла ли запись.
  const cashoutLife = record => (record.stampedAt != null
    ? record.stampedAt + CASHOUT_STAMP_FRESH_MS
    : record.at + CASHOUT_FRESH_MS);
  // Один понятный ответ приложению: доехал текст или нет (#5779). До WF50
  // приложение знало только, что новое окно появилось, — и закрывало донора по
  // факту появления окна, хотя между «окно есть» и «текст в поле» пять путей
  // отказа.
  //   «ждём»          — запись переноса есть, доезд не подтверждён;
  //   «вставлено»     — это окно подтвердило доезд;
  //   «отказ: <что>»  — приговор: вставить не вышло, ждать нечего, донора
  //                     трогать НЕЛЬЗЯ;
  //   «»              — этой странице сказать нечего (записи нет и не было).
  // Приговор принадлежит СВОЕЙ записи (находка гейта WF50) и умирает вместе с
  // ней: другая запись на месте — забываем сразу, записи нет вовсе — держим
  // слово ровно до того мгновения, когда УМЕРЛА БЫ САМА ЗАПИСЬ (#5788). Раньше
  // тут стоял общий срок в 150 с, ни к какой записи не привязанный: окно, куда
  // перенос лёг две минуты назад, отвечало «вставлено» и на следующее нажатие —
  // а если то нажатие вовсе не дошло до страницы (записи никто не создал),
  // приложение закрывало донора по ответу про ПРОШЛЫЙ перенос и теряло текст.
  const cashoutForget = record => {
    if (!cashoutVerdict) return;
    const stale = record != null
      ? record.at !== cashoutVerdictAt
      : Date.now() > cashoutVerdictUntil;
    if (stale) { cashoutVerdict = ""; cashoutVerdictAt = 0; cashoutVerdictUntil = 0; }
  };
  const cashoutDelivery = record => {
    cashoutForget(record);
    if (cashoutVerdict && (record == null || record.at === cashoutVerdictAt)) return cashoutVerdict;
    if (record?.refused) return `${CASHOUT_REFUSED}: ${record.refused}`;
    return record == null ? "" : CASHOUT_WAIT;
  };
  // Отказ переноса из попапа (#5592). Перенос едет цепочкой «Нового окна» главного окна; та
  // отказала (черновик в поле домашнего экрана, стор, папка, отправка) — раньше плашка вставала
  // в главном окне, а донор и приложение ждали до потолка (90 и 135 с). Теперь главное окно
  // пишет причину в саму запись (её localStorage общий): слово доезда у всех окон становится
  // «отказ: <причина>» — приложение бросает ожидание на ближайшем круге probe, — а донор
  // показывает плашку у себя сразу, по событию storage. chat — запись уже штампована этим
  // чатом (чат создан, а в окно не вынесся): она тоже не доедет.
  const cashoutRefuse = (why, chat = "") => {
    const record = readCashout();
    if (record == null || record.refused || !why) return false;
    if (record.to !== CASHOUT_PENDING && !(chat && record.to === chat)) return false;
    try {
      const raw = JSON.parse(localStorage.getItem(CASHOUT_KEY));
      localStorage.setItem(CASHOUT_KEY, JSON.stringify({ ...raw, refused: String(why).slice(0, 200) }));
    } catch { return false; }
    return true;
  };
  // Донор узнаёт себя по тексту записи — тем же правилом, каким его собрал runCashout (ответ и
  // черновик) или «Новый чат» (блок передачи); черновик успели поправить — хватает ответа.
  // Двойник того же чата в другом окне тоже узнает — плашка там не во вред.
  const cashoutDonorMine = record => {
    if (isMainWindow() || !record?.text) return false;
    if (record.handoff) {
      try { return cashoutCodeText(cashoutHandoffFind()?.code) === record.text; } catch { return false; }
    }
    const answer = lastAnswerText();
    const draft = rawText(state.editor).trim();
    if ([answer, draft].filter(Boolean).join("\n\n") === record.text) return true;
    return Boolean(answer) && record.text.startsWith(answer);
  };
  const CASHOUT_REFUSED_NOTE_MS = 6000;
  let cashoutRefusedShown = 0;
  const cashoutRefusedShow = () => {
    const record = readCashout();
    if (!record?.refused || cashoutRefusedShown === record.at || !cashoutDonorMine(record)) return;
    cashoutRefusedShown = record.at;
    cashoutRefusal = record.refused;
    try { newWindowNote(`Перенос не уехал: ${record.refused}.\nТекст остался здесь`, false, CASHOUT_REFUSED_NOTE_MS); } catch {}
  };
  on(window, "storage", event => {
    if (event?.key !== CASHOUT_KEY && event?.key !== null) return;
    try { cashoutRefusedShow(); } catch {}
  });
  // Счёт вложений для гейта: сколько плашек видел донор (want), сколько уехало
  // грузом (sent) и сколько доехало карточками в новом окне (done).
  let cashoutFilesCount = { want: 0, sent: 0, done: 0 };
  // Слепок записи для гейта (status().cashout): есть ли она, кому адресована,
  // под каким заголовком её ждут, когда штамповали, почему отказали, доехала ли
  // и что с вложениями. `deliveryAt` — время нажатия ТОЙ записи, о которой
  // сказано слово (#5788): по нему видно, о каком именно переносе речь.
  const cashoutState = () => {
    // Запасной путь плашки донора (#5592): storage не дошёл — скажем на вопросе приложения.
    try { cashoutRefusedShow(); } catch {}
    const record = readCashout();
    const delivery = cashoutDelivery(record);
    return {
      record: record != null,
      to: record?.to ?? null,
      title: record?.title || null,
      stampedAt: record?.stampedAt ?? null,
      refusal: cashoutRefusal,
      delivery,
      deliveryAt: cashoutVerdict ? cashoutVerdictAt : null,
      files: { ...cashoutFilesCount },
    };
  };

  // Вложения переноса (WF50, #5773) -----------------------------------------
  // File из разметки не достать: у картинки в плашке живёт одно blob-превью, а у
  // pdf и txt нет и его — сам File лежит во внутреннем состоянии Claude (замер
  // донора ElvisOS). Поэтому ловим файлы НА ВХОДЕ в поле — вставку, перетаскивание
  // и выбор через «Add», — и держим их на полке окна.
  //
  // Везём их НЕ через localStorage (квота origin ~5 МБ на все наши ключи разом,
  // base64 раздувает на треть, а setItem у нас под глухим try/catch — один
  // retina-скриншот съел бы молча даже текст) и НЕ через probe.js (канал общий и
  // ответ уже весит мегабайты). Все окна Claude — окна ОДНОГО экземпляра и
  // одного origin, поэтому File едет ссылкой через память ГЛАВНОГО окна: тем же
  // путём, каким попап спрашивает у родителя свой чат (раздел 12в).
  const cashoutHome = () => {
    let home = window[CASHOUT_FILES_GLOBAL];
    if (!home || typeof home !== "object") { home = {}; window[CASHOUT_FILES_GLOBAL] = home; }
    if (!Array.isArray(home.shelf)) home.shelf = [];
    // Протухший груз освобождает байты сам: цепочка «Обкэшить» рвётся регулярно,
    // и без этой строки десятки мегабайт висели бы в главном окне до следующего
    // переноса.
    if (home.carry && Date.now() - home.carry.at > CASHOUT_CARRY_FRESH_MS) home.carry = null;
    return home;
  };
  const cashoutFileHash = async file => {
    const head = new Uint8Array(await file.slice(0, CASHOUT_HASH_BYTES).arrayBuffer());
    let hash = 5381;
    for (let at = 0; at < head.length; at += 1) hash = (((hash << 5) + hash) ^ head[at]) >>> 0;
    return `${file.size}:${file.type}:${hash}`;
  };
  // Положить файлы на полку. Дедуп двойной: сразу по ссылке (одно действие
  // Элвиса приходит двумя событиями — paste и change — тем же объектом File) и
  // позже по содержимому, уже на сборе груза. Именем с размером на полке не
  // сравниваем: два РАЗНЫХ скриншота одного веса схлопнулись бы молча.
  const cashoutRemember = list => {
    if (!themable || !list || !list.length) return;
    const home = cashoutHome();
    shotIncoming(list);
    const at = Date.now();
    for (const file of Array.from(list)) {
      const size = Number(file?.size) || 0;
      if (!size) continue;
      const already = home.shelf.findIndex(item => item.file === file);
      if (already >= 0) home.shelf.splice(already, 1);
      const item = { name: String(file.name ?? ""), size, type: String(file.type ?? ""), file, at, hash: null };
      home.shelf.push(item);
      try { Promise.resolve(cashoutFileHash(file)).then(value => { item.hash = value; }, () => {}); } catch {}
    }
    while (home.shelf.length > CASHOUT_FILES_MAX) home.shelf.shift();
    let total = home.shelf.reduce((sum, item) => sum + item.size, 0);
    while (total > CASHOUT_BYTES_MAX && home.shelf.length > 1) total -= home.shelf.shift().size;
    startCashoutSweep();
  };
  // Файлы на входе в поле: положить на полку и — если поле свёрнуто — открыть
  // его. Свёрнутая рамка схлопнута в ноль (height:0, opacity:0), и вложение
  // прикрепляется невидимо: Элвис видит, что скриншот «не вставился», хотя
  // Claude его уже взял (#5870). Перехватывать событие нам нечем и незачем —
  // открыли поле и отпустили его своим ходом к Claude.
  const cashoutFiles = list => {
    cashoutRemember(list);
    if (list?.length && state.stage === STAGE_COLLAPSED) setStage(STAGE_NORMAL);
  };
  // Слушатели ставятся на ЗАХВАТЕ (раздел 16): Claude зовёт preventDefault, и на
  // всплытии события до нас доходят не всегда.
  const onCashoutPaste = event => { try { cashoutFiles(event?.clipboardData?.files); } catch {} };
  const onCashoutDrop = event => { try { cashoutFiles(event?.dataTransfer?.files); } catch {} };
  const onCashoutPick = event => {
    try {
      const target = event?.target;
      // Кнопка «+» живёт в строке модели, а она видна и при свёрнутом поле:
      // выбранный ею файл прикреплялся так же невидимо, как вставленный (#5870).
      if (target?.tagName === "INPUT" && target.type === "file") cashoutFiles(target.files);
    } catch {}
  };

  // ⌘V из любого места окна (WF64, #6030). Слово Элвиса (пересказ): жать Command V
  // в любом месте окна, и скриншот должен вставляться.
  // Вставку Claude отдаёт тому узлу, где стоит курсор: кликнул в ленте разговора
  // — скриншот уезжал в никуда, и приходилось сперва вставать в поле ввода.
  //
  // Дорог две, и спорить им не о чем. Неизвестно, шлёт ли Electron `paste` в
  // страницу, когда фокус стоит вне редактируемого узла, и неизвестно, доходит
  // ли `keydown` до страницы мимо меню «Правка», — каждая дорога закрывает
  // провал другой. Задвоения по устройству не бывает: сработала первая — фокус
  // уже в поле, у вставки цель редактируемая, и вторая выходит первой проверкой.
  //
  // Редактируемая цель — это и само поле ввода, и поиск чатов, и любое чужое
  // поле: туда вставка идёт как раньше, мы её не трогаем вовсе. Спрашиваем
  // closest, а не matches: при вставке В поле целью приходит вложенный <p>
  // самого ProseMirror. Цель бывает и пустой (событие без узла) — отсюда `?.`.
  const PASTE_EDITABLE_SELECTOR = "input,textarea,[contenteditable]";
  const pasteOutside = target => !target?.closest?.(PASTE_EDITABLE_SELECTOR);
  // Поле, куда уводим вставку, — строго .ProseMirror: EDITOR_SELECTOR пускает
  // ещё и чужую textarea, и на странице без композера скриншот уехал бы в
  // соседнее поле вместо того, чтобы никуда не поехать.
  const pasteEditor = () => {
    const editor = findEditor();
    return editor?.isConnected && editor.classList.contains("ProseMirror") ? editor : null;
  };
  // Дорога 1 — фокус на клавише: курсор встаёт в поле ДО того, как браузер
  // решит, куда класть вставку, и событие отпускается своим ходом. Ни
  // preventDefault, ни синтетики здесь нет намеренно — дальше работает родная
  // вставка Claude со всеми её повадками.
  //
  // Клавишу узнаём ДВУМЯ приметами. `key` зависит от раскладки: на русской та же
  // физическая клавиша отдаёт «м», и по одному `key` дорога 1 у Элвиса не
  // срабатывала бы никогда — а он в русской раскладке и сидит. `code` от
  // раскладки не зависит; так же (обеими приметами) в этом файле выставляются
  // все синтетические клавиши.
  const onPasteKey = event => {
    onAttachUndoKey(event);
    onAttachmentBoundary(event);
    try {
      if (!event?.metaKey) return;
      const isV = String(event.key ?? "").toLowerCase() === "v" || event.code === "KeyV";
      if (!isV) return;
      if (!pasteOutside(event.target)) return;
      pasteEditor()?.focus();
    } catch {}
  };
  // Дорога 2 — пересылка вставки: нужна, если фокус увести не вышло, а `paste`
  // до страницы всё же дошёл. clipboardData живёт только внутри обработчика
  // (после него files пустеют), поэтому файлы перекладываются в свежий
  // DataTransfer СИНХРОННО, прямо здесь, и уезжают в поле тем же способом,
  // каким их кладёт перенос «Обкэшить» (cashoutAttach).
  //
  // Едут только ФАЙЛЫ. Текст из буфера не трогаем вовсе: Элвис просил про
  // скриншот, а текст, упавший в черновик от случайного ⌘V, откатить нечем.
  //
  // Сторож «это наше событие» — флаг на время пересылки, а НЕ isTrusted: своей
  // синтетике его не выставить, и отличить по нему свою вставку от чужой
  // нельзя. Без флага наше же событие, всплыв обратно до document, уехало бы в
  // поле второй раз.
  let pasteRelaying = false;
  const onPasteAnywhere = event => {
    try {
      // Живой скриншот едет с номером (#7532) — и в поле, и мимо поля: ниже.
      if (!pasteRelaying && shotPaste(event)) return;
      if (pasteRelaying || !pasteOutside(event?.target)) return;
      const files = event?.clipboardData?.files;
      if (!files?.length) return;
      const editor = pasteEditor();
      if (!editor) return;
      const fresh = attachFresh(Array.from(files), "relay");
      event.preventDefault();
      if (!fresh.length) { newWindowNote(ATTACH_DUP_NOTE); return; }
      const data = new DataTransfer();
      for (const file of fresh) data.items.add(file);
      pasteRelaying = true;
      try {
        editor.focus();
        editor.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
      } finally { pasteRelaying = false; }
    } catch {}
  };
  // «Обкэшить»: есть ли запись переноса, кому она адресована (id чата или
  // «ждёт адресата»), под каким заголовком её ждут и когда штамповали (WF37).
  statusPart("cashout", () => cashoutState());
  HATCH && Object.assign(HATCH, { readCashout, cashoutHome, cashoutRefuse });

