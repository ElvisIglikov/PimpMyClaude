  // ---- 12м. Финальный ответ: лента вниз, «нужен Элвис» мигает (#7702, #7703, WF92)
  // Слово Элвиса 25.09: «чтобы чат проматывался вниз, но только если последний
  // самый ответ… финальные уже, не вот эти промежуточные»; «если там написано
  // „Скажи, сделаю“ — надо, чтобы это мигало… у меня много чатов открыто,
  // внимание рассеянное, мне важно видеть, когда от меня что-то требуется».
  //
  // Финальный ответ — конец хода, увиденный этим окном: кнопка стопа была
  // (WORKING_SELECTOR, раздел 12ж¹), её нет, и текст последнего ответа не
  // менялся ATTN_SETTLE_MS. Промежуточные ответы посреди хода (стоп на месте)
  // ничего не делают. Окно открыли на уже законченном ходе — тоже ничего.
  //
  // Прокрутка (#7702), правило: ответ последний в ленте (после него нет реплики
  // Элвиса) и лента не у низа — ставим её на низ тем же путём, что команда
  // «Прокрутить» (раздел 13). НЕ крутим, если Элвис читает (attnReading): двигал
  // ленту сам (колесо/трекпад над лентой в любую сторону, PageUp/PageDown, Home/End,
  // ↑/↓, пробел вне поля ввода, нажатие в ленте или её полосе прокрутки) и лента с
  // тех пор не возвращалась к низу (WF92-ap2: вернулась — «читает» снято); или
  // двигал её только что (ATTN_HOLD_MS — и у низа); или в ленте выделен текст.
  // #9319 (слово Элвиса: «читал что-то, новое сообщение пришло, и у меня сбилось»):
  // до него «читает» ставила только прокрутка ВВЕРХ — дочитывая вниз, по главам или
  // с выделением он оставался «не читает», и лента уезжала. Потолок —
  // ATTN_READING_MS от ПОСЛЕДНЕГО жеста: двигал давно — окно брошено, а ответ ждёт: крутим. #10360 (слово
  // Элвиса 19.10: «когда ответы новые приходят, Пимп должен позиционироваться на них… прокручиваться вниз»):
  // потолок — минута, а не пять: за пять минут без жеста он уже не читает, а ждёт ответ и листал бы руками. Лента и так у низа — ничего не трогаем. Один раз на ход.
  //
  // Мигание (#7703): заголовки «❗ Скажи — и сделаю ❗», «👾 ЭЛВИС, СДЕЛАЙ»,
  // «❗ Включи Accept Edits», «❗ Верни режим Авто» (WF98), «🦾 Нужен …»
  // ФИНАЛЬНОГО ответа мягко мигают
  // янтарём (метка ATTN_ATTRIBUTE, правило раздела 4) — пока окно не тронули
  // (клавиша, нажатие в этом окне; фокус окна — не касание: окна поднимает и
  // само приложение, WF92-ap2) и не дольше ATTN_BLINK_MS от конца хода. Рамка
  // «ждут твоего слова» (12и¹) живёт своим чередом: она про окно, мигание — про блок.
  // Не прокрутили, потому что Элвис читает выше, — мигание ждёт, пока лента
  // дойдёт до низа (иначе мигал бы старый заголовок, что на экране). Новый ход
  // (стоп снова есть) или смена чата — мигание снято. Таймеров своих нет:
  // шагает тиком сердца.
  // Устоялся — дольше, чем ждёт «Новый чат» сам (12к, AUTO_SETTLE_MS): тот
  // судит ленту нетронутой (WF85, Б2 — «лента не у низа» = отсчёта нет), и
  // только потом мы её двигаем.
  const ATTN_SETTLE_MS = AUTO_SETTLE_MS + 500;
  const ATTN_READING_MS = 60000;
  // Колесо приходит раньше самой прокрутки: столько метка «читает» не
  // снимается, даже если лента ещё у низа.
  const ATTN_READING_GRACE_MS = 1000;
  // Двигал ленту только что — читает и у самого низа: новое её не уводит (#9319).
  const ATTN_HOLD_MS = 30000;
  const ATTN_BLINK_MS = 120000;
  const ATTN_HEAD_SELECTOR = 'h1,h2,h3,h4,h5,h6,[role="heading"]';
  const ATTN_HEAD_RE = /Скажи\s*[—–-]+\s*и\s+сделаю|ЭЛВИС,?\s+СДЕЛАЙ|👤\s*СДЕЛАЙ|Включи\s+Accept\s+Edits|Верни\s+режим\s+(?:Авто|Auto)|🦾\s*Нужен/iu;
  const ATTN_READ_KEYS = ["PageUp", "PageDown", "Home", "End", "ArrowUp", "ArrowDown", " "];
  // readAt — последний жест чтения в ленте (readHref — в каком чате), readBottom — лента с тех пор дошла до низа;
  // inputAt — последнее касание окна вообще (прокрутка сразу после него — его, не Claude: раздел 13а).
  const attnState = {
    chat: undefined, armed: false, goneAt: 0, print: "", turns: 0, scrolls: 0, skip: "",
    readAt: -Infinity, readHref: "", readBottom: true, inputAt: -Infinity,
    blink: false, pending: false, until: 0, heads: 0, blinks: 0, marked: new Set(),
  };
  // Отпечаток ответа: длина и хвост текста — «устоялся» значит «не менялся».
  const attnPrint = node => {
    if (!node) return "";
    const text = rawText(node);
    return `${text.length}:${text.slice(-80)}`;
  };
  // После ответа в ленте нет реплики Элвиса.
  const attnIsLast = answer => {
    let list = [];
    try { list = [...document.querySelectorAll(`.epitaxy-user-turn,${ANSWER_SELECTOR}`)]; } catch { return true; }
    const at = list.lastIndexOf(answer);
    if (at < 0) return true;
    return !list.slice(at + 1).some(node => !answer.contains(node) && node.closest?.(".epitaxy-user-turn") != null);
  };
  const attnHeads = answer => {
    if (!answer) return [];
    try { return [...answer.querySelectorAll(ATTN_HEAD_SELECTOR)].filter(node => ATTN_HEAD_RE.test(node.textContent ?? "")); }
    catch { return []; }
  };
  // Метки — ровно на заголовках нынешнего ответа: React пересобрал узел —
  // новый получит метку на следующем тике, старый её теряет.
  const attnMark = answer => {
    const heads = attnHeads(answer);
    for (const node of [...attnState.marked]) {
      if (heads.includes(node) && node.isConnected) continue;
      try { node.removeAttribute(ATTN_ATTRIBUTE); } catch {}
      attnState.marked.delete(node);
    }
    for (const node of heads) {
      if (!node.hasAttribute(ATTN_ATTRIBUTE)) node.setAttribute(ATTN_ATTRIBUTE, "");
      attnState.marked.add(node);
    }
    attnState.heads = heads.length;
    return heads.length;
  };
  const attnBlinkStop = () => {
    attnState.blink = false;
    attnState.pending = false;
    attnState.heads = 0;
    for (const node of attnState.marked) { try { node.removeAttribute(ATTN_ATTRIBUTE); } catch {} }
    attnState.marked.clear();
  };
  try { for (const node of document.querySelectorAll(`[${ATTN_ATTRIBUTE}]`)) node.removeAttribute(ATTN_ATTRIBUTE); } catch {}
  track(attnBlinkStop);
  const attnBlinkStart = answer => {
    attnState.pending = false;
    attnState.blink = true;
    attnState.blinks += 1;
    attnMark(answer);
  };
  const attnAtBottom = () => { try { return progressAtBottom(); } catch { return null; } };
  // Выделен текст в ленте — читает (копирует), что бы ни было со временем.
  const attnSelecting = () => {
    try {
      const selection = getSelection();
      if (!selection || selection.isCollapsed !== false || !selection.rangeCount) return false;
      return findScroller()?.contains?.(selection.anchorNode) === true;
    } catch { return false; }
  };
  // Жест — в этом же чате: «читает» про прежний чат новому не передаётся.
  const attnReading = t => attnSelecting() || (attnState.readHref === location.href &&
    (t - attnState.readAt < ATTN_HOLD_MS || (!attnState.readBottom && t - attnState.readAt < ATTN_READING_MS)));
  // Ход кончен и ответ устоялся: прокрутка и мигание.
  const attnFinal = t => {
    attnState.turns += 1;
    let answer = null;
    try { answer = lastAnswerNode(); } catch { answer = null; }
    if (!answer || !attnIsLast(answer)) { attnState.skip = "нет последнего ответа"; return; }
    let seen = attnAtBottom() !== false;
    attnState.skip = "";
    if (!seen) {
      // Ответ уже встал на своё время и проявился (раздел 14б, #10764) — к низу не тянем.
      if (revealPlaced(t)) { attnState.skip = "ответ встал на своё время"; seen = true; }
      else if (attnReading(t)) attnState.skip = "читает выше";
      else if (runScroll()) { attnState.scrolls += 1; seen = true; }
      else attnState.skip = "нет ленты";
    }
    if (!attnHeads(answer).length) return;
    attnState.until = t + ATTN_BLINK_MS;
    if (seen) attnBlinkStart(answer);
    else attnState.pending = true;
  };
  const attnBlinkStep = t => {
    if (t >= attnState.until) { attnBlinkStop(); return; }
    if (attnState.pending) {
      if (attnAtBottom() === false) return;
      attnState.pending = false;
      attnState.blink = true;
      attnState.blinks += 1;
    }
    let answer = null;
    try { answer = lastAnswerNode(); } catch { answer = null; }
    attnMark(answer);
  };
  const attnTick = t => {
    if (!themable) return;
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    // Лента вернулась к низу — Элвис дочитал, «читает выше» снято.
    if (!attnState.readBottom && t - attnState.readAt > ATTN_READING_GRACE_MS && attnAtBottom() === true) {
      attnState.readBottom = true;
    }
    if (chat !== attnState.chat) {
      attnState.chat = chat;
      attnState.armed = false;
      attnState.goneAt = 0;
      attnBlinkStop();
    }
    // Окно ушло в чужой чат за Allow (обход 12е) — ждём, пока вернётся.
    if (roamState.phase !== "idle") return;
    let working = null;
    try { working = document.querySelector(WORKING_SELECTOR); } catch { working = null; }
    if (working) {
      attnState.armed = true;
      attnState.goneAt = 0;
      if (attnState.blink || attnState.pending) attnBlinkStop();
      return;
    }
    if (attnState.blink || attnState.pending) attnBlinkStep(t);
    if (!attnState.armed) return;
    let print = "";
    try { print = attnPrint(lastAnswerNode()); } catch { print = ""; }
    if (!attnState.goneAt || print !== attnState.print) {
      attnState.goneAt = t;
      attnState.print = print;
      return;
    }
    if (t - attnState.goneAt < ATTN_SETTLE_MS) return;
    attnState.armed = false;
    attnState.goneAt = 0;
    attnFinal(t);
  };
  // Касание окна снимает мигание (свои синтетические нажатия — не касание).
  const onAttnTouch = event => {
    if (event?.isTrusted === false) return;
    attnState.inputAt = now();
    if (attnState.blink || attnState.pending) attnBlinkStop();
  };
  const attnReadMark = () => { attnState.readAt = now(); attnState.readHref = location.href; attnState.readBottom = false; };
  const attnInFeed = node => {
    let feed = null;
    try { feed = findScroller(); } catch { feed = null; }
    return Boolean(feed && node && feed.contains?.(node));
  };
  // Элвис листает ленту сам (вверх или вниз) — читает.
  const onAttnWheel = event => {
    if (event?.isTrusted === false || !Number(event?.deltaY)) return;
    attnState.inputAt = now();
    if (attnInFeed(event.target)) attnReadMark();
  };
  // Нажатие в ленте: текст, «Прочитано», полоса прокрутки (цель — сама лента).
  const onAttnFeedPress = event => {
    if (event?.isTrusted === false) return;
    if (attnInFeed(event.target)) attnReadMark();
  };
  const onAttnKey = event => {
    if (event?.isTrusted === false || !ATTN_READ_KEYS.includes(event?.key)) return;
    try { if (event.target?.closest?.('[contenteditable="true"],input,textarea')) return; } catch {}
    attnReadMark();
  };
  // Финальный ответ (WF92, раздел 12м): ход идёт или устаивается (armed),
  // сколько ходов кончилось, сколько раз лента поехала вниз, почему нет
  // (skip), читает ли Элвис (reading, attnReading), сколько раз место чтения
  // удержано и сколько раз уступили спору (held, yielded — раздел 13а), карточка
  // разрешения слоем над лентой (card: «on» — дока помечена, «off» — слой закрыли или
  // обрезали, карточка в потоке; cards — сколько карточек легло слоем; раздел 9), мигают ли заголовки
  // «нужен Элвис» (blink; pending — ждут, пока лента дойдёт до низа),
  // сколько их и сколько раз мигание начиналось.
  statusPart("attention", () => ({
    armed: attnState.armed, turns: attnState.turns, scrolls: attnState.scrolls,
    skip: attnState.skip || null, reading: attnReading(now()), held: feedHold.holds, yielded: feedHold.yields,
    card: cardFloat.broken ? "off" : cardFloat.dock ? "on" : null, cards: cardFloat.cards,
    blink: attnState.blink, pending: attnState.pending, heads: attnState.heads, blinks: attnState.blinks,
    // Рамка «ждут твоего слова» (#8282, раздел 12и¹): горит ли и с какого времени (Date.now()).
    // want — ждут ли слова Элвиса (Allow/вопрос или «жду»/«упал» в строке состояния, выдержка 2 с;
    // без гашения касанием): по нему приложение разворачивает спрятанное окно.
    on: attnFrame.on, since: attnFrame.since, want: attnFrame.want,
  }));
  HATCH && Object.assign(HATCH, { attnTick });

