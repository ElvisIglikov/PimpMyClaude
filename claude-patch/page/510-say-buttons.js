  // ---- 12р. Слова-действия кнопками (#7755, WF97) --------------------------
  // Слово Элвиса 26.09 ~04:00: «чтобы слова действия были гиперссылками… нажал —
  // и оно сразу в поле ввода… таймер тикал пять, четыре, три, два, один… через
  // 5 секунд оно отправляется… чтобы с клавиатуры вообще ничего не надо было
  // нажимать, ни энтер, ничего».
  //
  // Блок — заголовок «❗ Скажи — и сделаю ❗» (весь текст заголовка — эта фраза,
  // «Кнопки в „Скажи — и сделаю“» не блок; живой замер 26.09: h3 в строке
  // transcript-row/assistant_text) и всё до следующего заголовка; кнопки — его
  // strong/b, слово — текст без кавычек. В ЛЮБОМ ответе ленты.
  // Клик по слову — оно в выбранных: в поле свой текст Элвиса (что было до
  // первого клика) + выбранные слова, каждое с новой строки (#8687; до WF125 —
  // через пробел, и два ответа слипались в одну фразу), в порядке кликов; клик по
  // выбранному — снято. Своего текста нет — поле пересобрано целиком; есть —
  // он не переписывается, меняется только хвост из слов (находка 6, волна 2). После каждого клика отсчёт SAY_WAIT_MS заново;
  // дотикал и в поле РОВНО выбранные слова — начинается общий настраиваемый
  // отсчёт отправки с Esc/кликом для отмены (#8283). Свой текст в
  // поле, клавиша в поле, клик по пилюле отсчёта — отсчёт гаснет, слова
  // остаются, ничего не шлём. Смена чата и новый ход — всё сброшено.
  // 2 с (слово Элвиса 19.10.2026, #10361: «И 2 секунды у вот этих… согласен»; с WF97 было 5 с).
  const SAY_WAIT_MS = 2000;
  const SAY_STEP_MS = 200;
  const SAY_HEAD_RE = /^[^\p{L}\p{N}]*Скажи\s*[—–-]+\s*и\s+сделаю[^\p{L}\p{N}]*$/iu;
  const SAY_WORD_MAX = 40;
  const sayState = {
    chat: undefined, working: false, words: [], armed: false, until: 0, left: 0, sends: 0, skip: "",
    base: "", expect: null, head: null, timer: 0, marked: new Set(), heads: new Set(),
  };
  const sayWord = node => sayNorm(node?.textContent).replace(/^[«»"“”„'‘’\s]+|[«»"“”„'‘’\s]+$/g, "");
  const sayEditor = () => (state.editor?.isConnected ? state.editor : findEditor());
  // Кнопки ленты: [{node, word, head}].
  const sayButtons = () => {
    const list = [];
    let heads = [];
    try { heads = [...document.querySelectorAll(ATTN_HEAD_SELECTOR)]; } catch { return list; }
    for (const head of heads) {
      if (!SAY_HEAD_RE.test(sayNorm(head.textContent))) continue;
      if (head.closest?.('[contenteditable="true"]') || state.composerBlock?.contains?.(head)) continue;
      for (let node = head.nextElementSibling; node; node = node.nextElementSibling) {
        let inner = [];
        try {
          if (node.matches?.(ATTN_HEAD_SELECTOR) || node.querySelector?.(ATTN_HEAD_SELECTOR)) break;
          inner = node.matches?.("strong,b") ? [node] : [...node.querySelectorAll("strong,b")];
        } catch { inner = []; }
        for (const item of inner) {
          const word = sayWord(item);
          if (word && word.length <= SAY_WORD_MAX) list.push({ node: item, word, head });
        }
      }
    }
    return list;
  };
  // Метки — ровно на кнопках, что сейчас в ленте; у заголовка — цифра отсчёта.
  const sayPaint = () => {
    const buttons = sayButtons();
    const keep = new Set();
    for (const { node, word } of buttons) {
      const mark = sayState.words.includes(word) ? "on" : "";
      if (node.getAttribute(SAY_ATTRIBUTE) !== mark) node.setAttribute(SAY_ATTRIBUTE, mark);
      keep.add(node);
    }
    for (const node of [...sayState.marked]) {
      if (keep.has(node)) continue;
      try { node.removeAttribute(SAY_ATTRIBUTE); } catch {}
      sayState.marked.delete(node);
    }
    for (const node of keep) sayState.marked.add(node);
    let head = null;
    if (sayState.armed) {
      head = sayState.head?.isConnected ? sayState.head
        : buttons.find(item => sayState.words.includes(item.word))?.head ?? null;
      sayState.head = head;
    }
    for (const node of [...sayState.heads]) {
      if (node === head) continue;
      try { node.removeAttribute(SAY_LEFT_ATTRIBUTE); } catch {}
      sayState.heads.delete(node);
    }
    if (head) {
      const left = String(sayState.left);
      if (head.getAttribute(SAY_LEFT_ATTRIBUTE) !== left) head.setAttribute(SAY_LEFT_ATTRIBUTE, left);
      sayState.heads.add(head);
    }
  };
  const sayStopTimer = () => { if (sayState.timer) { clearInterval(sayState.timer); sayState.timer = 0; } };
  const sayDisarm = skip => {
    sayState.armed = false;
    sayState.left = 0;
    sayState.until = 0;
    sayState.editor = null;
    if (skip) sayState.skip = skip;
    sayStopTimer();
  };
  const sayReset = () => {
    sayDisarm("");
    sayState.words = [];
    sayState.base = "";
    sayState.expect = null;
    sayState.head = null;
  };
  // Поле — ровно этот текст: выделить всё и вставить поверх (пусто — стереть).
  // Только когда в поле одни выбранные слова: свой текст так не переписываем.
  // Поле потом прокручивается к концу (#10333) — здесь и в sayWriteTail.
  const sayWrite = (editor, text) => {
    try { editor.focus(); } catch {}
    try { document.execCommand("selectAll"); } catch {}
    try { document.execCommand(text ? "insertText" : "delete", false, text); } catch {}
    composerScrollToEnd(editor);
  };
  // Свой текст в поле (находка 6 проверки гейта 1 WF97): черновик не трогаем —
  // курсор в конец, хвост из выбранных слов (строка removed) выделяется назад
  // и заменяется новым хвостом (пусто — стирается). Абзацы и код черновика
  // остаются побайтно. Шаг «character» в Chromium — графема, а не UTF-16:
  // эмодзи — две единицы .length, но один шаг (z2-r04), поэтому считаем
  // графемы, иначе лишний шаг съедает букву черновика.
  const graphemes = text => {
    try { return [...new Intl.Segmenter("ru", { granularity: "grapheme" }).segment(text)].length; } catch {}
    return [...text].length;
  };
  const sayWriteTail = (editor, removed, tail) => {
    const length = removed ? graphemes(removed) : 0;
    if (editor?.isConnected) { try { editor.focus(); } catch {} caretToEnd(editor); }
    if (length > 0) {
      try {
        const selection = (typeof getSelection === "function" ? getSelection() : null) ?? document.getSelection?.();
        for (let step = 0; step < length; step += 1) selection.modify("extend", "backward", "character");
      } catch {}
    }
    try { document.execCommand(tail ? "insertText" : "delete", false, tail); } catch {}
    composerScrollToEnd(editor);
  };
  const sayToggle = (word, head, t = now(), quiet = false) => {
    if (shotBlocked()) return false;
    sayWatch();
    const editor = sayEditor();
    if (!editor || !word) return false;
    const current = sayNorm(rawText(editor));
    // Поле трогали после нас (или первый клик): свой текст — всё, кроме хвоста
    // из выбранных слов; хвоста нет — выбор забыт, поле главнее.
    if (current !== sayState.expect) {
      const joined = sayState.words.join(" ");
      if (joined && (current === joined || current.endsWith(` ${joined}`))) sayState.base = current.slice(0, current.length - joined.length).trim();
      else { sayState.words = []; sayState.base = current; }
    }
    // В поле слова идут с новой строки (#8687); сверки ниже и выше — через sayNorm,
    // он перевод строки сводит к пробелу, поэтому expect и base считаются как раньше.
    const before = sayState.words.join("\n");
    const at = sayState.words.indexOf(word);
    if (at >= 0) sayState.words.splice(at, 1);
    else sayState.words.push(word);
    const after = sayState.words.join("\n");
    const text = [sayState.base, sayState.words.join(" ")].filter(Boolean).join(" ");
    if (!sayState.base) sayWrite(editor, after);
    else if (at < 0) sayWriteTail(editor, "", `\n${word}`);
    else sayWriteTail(editor, `\n${before}`, after ? `\n${after}` : "");
    sayState.expect = text;
    sayState.skip = "";
    sayState.head = head ?? sayState.head;
    if (sayState.words.length && !sayState.base && !quiet) {
      sayState.armed = true;
      sayState.editor = editor;
      sayState.until = t + SAY_WAIT_MS;
      sayState.left = Math.ceil(SAY_WAIT_MS / 1000);
      if (!sayState.timer) sayState.timer = setInterval(() => { try { sayTick(now()); } catch {} }, SAY_STEP_MS);
    } else sayDisarm(sayState.base ? "свой текст в поле" : "");
    sayPaint();
    return true;
  };
  // Общая граница двух видов фраз: поле меняли — отмена сразу, а не лишь на
  // пятой секунде. Счётчики sends растут только после подтверждённого опустевшего поля.
  const phraseCountdown = (owner, expected, disarm, send, t) => {
    if (!owner.armed) return;
    if (shotBlocked()) { disarm("Ставлю номер…"); return; }
    if (!owner.editor?.isConnected || findEditor() !== owner.editor || sayNorm(rawText(owner.editor)) !== sayNorm(expected)) {
      disarm("свой текст в поле"); return;
    }
    owner.left = Math.max(0, Math.ceil((owner.until - t) / 1000));
    if (t >= owner.until) send();
  };
  const phraseSend = (owner, expected, disarm, reset) => {
    if (shotBlocked()) { disarm("Ставлю номер…"); return false; }
    const editor = owner.editor;
    if (!editor?.isConnected || findEditor() !== editor || sayNorm(rawText(editor)) !== sayNorm(expected)) {
      disarm("свой текст в поле"); return false;
    }
    let send = null;
    try { send = document.querySelector(SEND_SELECTOR); } catch {}
    if (!send || send.disabled === true) { disarm("нет кнопки отправки"); return false; }
    if (sendDelayState.counting) { disarm("отправка уже ждёт"); return false; }
    sendDelayStart(editor, () => { owner.sends += 1; });
    reset();
    return true;
  };
  const saySend = () => phraseSend(sayState, sayState.words.join(" "), sayDisarm, sayReset);
  // Смена чата и начало хода (стоп появился) — выбор и отсчёт сброшены.
  const sayWatch = () => {
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    if (chat !== sayState.chat) { sayState.chat = chat; sayReset(); }
    let working = false;
    try { working = document.querySelector(WORKING_SELECTOR) != null; } catch {}
    if (working && !sayState.working) sayReset();
    sayState.working = working;
  };
  const sayTick = t => {
    if (!themable || !state.alive) return;
    sayWatch();
    phraseCountdown(sayState, sayState.words.join(" "), sayDisarm, saySend, t);
    sayPaint();
  };
  // Нажатие по слову: фокус остаётся в поле, текст не выделяется.
  const onSayPress = event => {
    const target = event?.target;
    if (!target?.closest?.(`[${SAY_ATTRIBUTE}],[${SAY_LEFT_ATTRIBUTE}]`)) return;
    event.preventDefault?.();
  };
  const onSayClick = event => {
    const target = event?.target;
    const button = target?.closest?.(`[${SAY_ATTRIBUTE}]`);
    if (button) {
      event.preventDefault?.();
      event.stopPropagation?.();
      if (!state.alive) return;
      // Двойной клик по слову (#7772) — одно нажатие: второе сняло бы слово
      // сразу после выбора.
      if (Number(event.detail) > 1) return;
      const hit = sayButtons().find(item => item.node === button);
      try { sayToggle(hit?.word ?? sayWord(button), hit?.head ?? null, now(), hit?.quiet === true); } catch {}
      return;
    }
    if (!sayState.armed || !target?.closest?.(`[${SAY_LEFT_ATTRIBUTE}]`)) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    sayDisarm("отменил");
    sayPaint();
  };
  // Элвис сам печатает в поле — отсчёт гаснет.
  const onSayKey = event => {
    if (event?.isTrusted === false || !sayState.armed) return;
    const target = event.target;
    if (target && (state.editor?.contains?.(target) || state.composerBlock?.contains?.(target))) { sayDisarm("печатает"); sayPaint(); }
  };
  // Кнопок «❗ Ждёт тебя» («Не делай», «Понял», «Сделал», «Делай всё»…) больше нет (#10643, слово Элвиса 22.10.2026:
  // «Делай всё, скрой, сделал, понял, вот эти вот штуки. Их убери и кнопки эти») — метки прошлых версий снимаем со страницы.
  try {
    for (const node of document.querySelectorAll(`[${SAY_ATTRIBUTE}]`)) node.removeAttribute(SAY_ATTRIBUTE);
    for (const node of document.querySelectorAll(`[${SAY_LEFT_ATTRIBUTE}]`)) node.removeAttribute(SAY_LEFT_ATTRIBUTE);
    for (const node of document.querySelectorAll(`[${AGREE_ATTRIBUTE}],[${DOALL_ATTRIBUTE}]`)) node.remove();
  } catch {}
  track(() => {
    sayStopTimer();
    for (const node of sayState.marked) { try { node.removeAttribute(SAY_ATTRIBUTE); } catch {} }
    for (const node of sayState.heads) { try { node.removeAttribute(SAY_LEFT_ATTRIBUTE); } catch {} }
    sayState.marked.clear();
    sayState.heads.clear();
  });
  // Слова-действия «Скажи — и сделаю» (#7755, раздел 12р): отсчёт идёт,
  // выбранные слова по порядку кликов, секунд до отправки, сколько отправил.
  statusPart("say", () => ({ armed: sayState.armed, words: [...sayState.words], left: sayState.left, sends: sayState.sends }));
  HATCH && Object.assign(HATCH, { sayTick, sayToggle, sayButtons, sayState });

