  // ---- 12м³. «Просмотрено» у карточек файлов (WF239) --------------------------
  // Слово владельца 10.10 21:10: «сделал бы кнопку „просмотрено“… чтобы я как-то помечал те файлы,
  // которые я просмотрел, галочкой. В правом углу в карточках… чтоб серыми становились, чтоб они
  // внимание не отвлекали, чтоб я понимал, что я уже нажал».
  // Карточка — кнопка файла в ответе (button[title=<абсолютный путь>] в строке ассистента — та же, что
  // знают разделы 12г, 12д¹ и 12м²; файл и фото). Плитки вложений поля ввода и вложения реплик человека
  // не трогаем: свои файлы он знает.
  // • Галочка — своя настоящая кнопка внутри карточки, в правом верхнем углу (замер 10.10, Claude
  //   2.31226: у файла там пусто — плашка типа слева вверху, имя и размер снизу; у фото — картинка;
  //   своих кнопок Claude при наведении и меню «⋯» в карточке нет, её меню — по правому клику).
  //   Нажал (мышь, Enter, пробел) — карточка серая, галочка залита; ещё раз — как была, без вопроса.
  //   Карточка остаётся рабочей: открывается, тащится, меню 12г открывается и с галочки. Нажатие
  //   мышью фокус поля ввода не отнимает; пока файл открывается (⏳ в углу, 12д¹) — галочки не видно.
  // • Ключ отметки — путь файла и его размер из пропсов карточки (размер неизвестен — один путь):
  //   тот же файл, показанный в чате дважды, отмечен в обоих местах, а новая редакция по тому же пути
  //   (размер другой) приходит неотмеченной — её ещё не смотрели.
  // • Отметки — localStorage[SEEN_KEY] = {<ключ чата раздела 2а>: {at, ids}}, как у «Прочитано»
  //   (12х), общие у окон, переживают перезапуск; потолок — readStoreTrim со своими числами. Запись
  //   не удалась — отметки живут до закрытия окна, причина — в status().seen.lastError.
  // • Лента виртуальная: карточки вне экрана в DOM отсутствуют и приходят заново. Отмеченные серыми
  //   возвращаются в том же колбэке мутаций, до отрисовки (seenOnMutation, пока в чате есть отметки);
  //   галочки неотмеченных ставит общий проход сердцебиения (seenTick) — своего опроса нет. Размеры
  //   карточки и ленты отметка не меняет: место чтения и прокрутка на месте.
  const SEEN_KEY = "myclaude-seen-v1";
  const SEEN_CHATS_MAX = 40;
  const SEEN_IDS_MAX = 300;
  const SEEN_TOTAL_MAX = 3000;
  const SEEN_CARD_SELECTOR = '[data-testid="transcript-row"][data-perf-row^="assistant"] button[title^="/"]';
  const SEEN_ON_TEXT = "Снять отметку «просмотрено»";
  const SEEN_OFF_TEXT = "Отметить просмотренным";
  // Клавиша уже поставила отметку — щелчок, который браузер шлёт кнопке следом за ней, не в счёт.
  const SEEN_KEY_CLICK_MS = 600;
  const seenState = { chat: undefined, marks: new Set(), kept: new Map(), cards: new Map(), error: null, clicks: 0, keyAt: -Infinity };
  // Ключ файла карточки: путь из title и размер из пропсов её компонента (не дальше DD_CARD_HOPS
  // волокон, как у 12м²); пропсы не про этот путь или размера нет — один путь.
  const seenKeyOf = card => {
    const path = String(card?.getAttribute?.("title") ?? "");
    if (!path.startsWith("/")) return "";
    let size = 0;
    try {
      let fiber = openChromeFiber(card);
      for (let hop = 0; fiber && hop <= DD_CARD_HOPS; hop += 1, fiber = fiber.return) {
        const found = openChromePathOf(fiber.memoizedProps);
        if (!found) continue;
        if (found.path === path) size = Number(fiber.memoizedProps.size) || 0;
        break;
      }
    } catch { size = 0; }
    return size > 0 ? `${path}|${size}` : path;
  };
  const seenStoreLoad = () => {
    try {
      const data = JSON.parse(localStorage.getItem(SEEN_KEY) ?? "null");
      return data && typeof data === "object" && !Array.isArray(data) ? data : {};
    } catch { return {}; }
  };
  // Поставить или снять одну отметку. Чтение — заново: другое окно того же чата могло отметить своё.
  // Ответ — отметки чата после записи; null — запись не удалась (отметки остаются на сеанс).
  const seenStoreApply = (chat, key, marked) => {
    try {
      const map = seenStoreLoad();
      const ids = readIdsOf(map[chat]).filter(item => item !== key);
      if (marked) ids.push(key);
      map[chat] = { at: Date.now(), ids };
      const next = readStoreTrim(map, chat, SEEN_IDS_MAX, SEEN_CHATS_MAX, SEEN_TOTAL_MAX);
      if (Object.keys(next).length) localStorage.setItem(SEEN_KEY, JSON.stringify(next));
      else localStorage.removeItem(SEEN_KEY);
      return next[chat]?.ids ?? [];
    } catch (error) {
      seenState.error = `отметки не сохранены, действуют до закрытия окна: ${String(error?.name ?? error).slice(0, 60)}`;
      return null;
    }
  };
  // Знак: контур круга с галочкой (не отмечено) и залитый круг с галочкой-просветом (отмечено) —
  // оба цветом текста, просвет показывает фон под кнопкой: своих цветов у знака нет.
  const seenMake = () => {
    const check = document.createElement("button");
    check.type = "button";
    check.setAttribute(SEEN_CHECK_ATTRIBUTE, "");
    try {
      const ns = "http://www.w3.org/2000/svg";
      const svg = document.createElementNS(ns, "svg");
      svg.setAttribute("viewBox", "0 0 18 18");
      svg.setAttribute("aria-hidden", "true");
      const part = (tag, attrs) => {
        const node = document.createElementNS(ns, tag);
        for (const [name, value] of Object.entries(attrs)) node.setAttribute(name, value);
        svg.appendChild(node);
      };
      part("circle", { "data-k": "line", cx: "9", cy: "9", r: "8.25", fill: "none", stroke: "currentColor", "stroke-width": "1.5" });
      part("path", { "data-k": "line", d: "M5 9.35L7.75 12.05L13 6.25", fill: "none", stroke: "currentColor", "stroke-width": "1.7", "stroke-linecap": "round", "stroke-linejoin": "round" });
      part("path", { "data-k": "fill", "fill-rule": "evenodd", fill: "currentColor", d: "M9 0a9 9 0 1 0 0 18a9 9 0 1 0 0-18ZM4.37 9.99L7.79 13.35L13.67 6.85L12.33 5.65L7.71 10.75L5.63 8.71Z" });
      check.appendChild(svg);
    } catch {}
    return check;
  };
  const seenDrop = (card, check) => {
    try { check.remove(); } catch {}
    try { card.removeAttribute(SEEN_ATTRIBUTE); } catch {}
    seenState.cards.delete(card);
  };
  // Галочка и вид одной карточки — по её нынешнему файлу (узел ленты мог достаться другому файлу).
  const seenSync = card => {
    const key = seenKeyOf(card);
    let check = seenState.cards.get(card) ?? null;
    if (!key) { if (check) seenDrop(card, check); return false; }
    if (check?.parentNode !== card) {
      check ??= seenMake();
      try { card.appendChild(check); } catch { return false; }
      seenState.cards.set(card, check);
    }
    check.__myclaudeSeen = key;
    const on = seenState.marks.has(key);
    foldSet(card, SEEN_ATTRIBUTE, on ? "on" : "");
    foldSet(check, "aria-pressed", String(on));
    foldSet(check, "title", on ? SEEN_ON_TEXT : SEEN_OFF_TEXT);
    foldSet(check, "aria-label", on ? SEEN_ON_TEXT : SEEN_OFF_TEXT);
    return true;
  };
  // Разметка ровно по тому, что сейчас в ленте; ушедшее снято. Раскладку не читает.
  const seenPaint = () => {
    let cards = [];
    if (themable && seenState.chat) { try { cards = [...document.querySelectorAll(SEEN_CARD_SELECTOR)]; } catch { cards = []; } }
    const live = new Set();
    for (const card of cards) if (seenSync(card)) live.add(card);
    for (const [card, check] of seenState.cards) if (!live.has(card)) seenDrop(card, check);
  };
  // Общий проход сердцебиения (лента менялась или прошло 5 с): чат сменился — отметки его.
  const seenTick = () => {
    let chat = null;
    try { chat = chatKey(); } catch { chat = null; }
    if (chat !== seenState.chat) {
      seenState.chat = chat;
      seenState.marks = new Set(chat ? seenState.kept.get(chat) ?? readIdsOf(seenStoreLoad()[chat]) : []);
    }
    seenPaint();
  };
  // Строки ленты приходят заново при прокрутке: пока в чате есть отметки, пришедшие карточки
  // размечаются в том же колбэке мутаций, до отрисовки, — серая не мигает обычной. Смотрим только
  // добавленное; свои вставки (галочка) второго круга не дают.
  const seenOnMutation = records => {
    if (!seenState.marks.size || !seenState.chat || !themable) return;
    for (const record of records) {
      if (record.type !== "childList") continue;
      for (const node of record.addedNodes ?? []) {
        if (node?.nodeType !== 1 || node.hasAttribute?.(SEEN_CHECK_ATTRIBUTE)) continue;
        if (node.matches?.(SEEN_CARD_SELECTOR)) { seenSync(node); continue; }
        for (const card of node.querySelectorAll?.(SEEN_CARD_SELECTOR) ?? []) seenSync(card);
      }
    }
  };
  // Поставить или снять отметку файла этой галочки; все карточки того же файла перекрашиваются разом.
  const seenToggle = check => {
    const key = check?.__myclaudeSeen;
    const chat = seenState.chat;
    if (!key || !chat) return false;
    const was = seenState.marks.has(key);
    seenState.clicks += 1;
    seenState.error = null;
    const stored = seenStoreApply(chat, key, !was);
    if (stored) { seenState.marks = new Set(stored); seenState.kept.delete(chat); }
    else {
      if (was) seenState.marks.delete(key); else seenState.marks.add(key);
      seenState.kept.set(chat, seenState.marks);
    }
    seenPaint();
    return true;
  };
  const seenCheckAt = target => target?.closest?.(`[${SEEN_CHECK_ATTRIBUTE}]`) ?? null;
  // Щелчок по галочке — только наш (захват документа): карточка под ней файл не открывает, фото не
  // раскрывается. Второй щелчок двойного нажатия отметку обратно не снимает.
  const onSeenClick = event => {
    const check = state.alive ? seenCheckAt(event?.target) : null;
    if (!check) return;
    event.preventDefault?.();
    event.stopImmediatePropagation?.();
    if (Number(event.detail) > 1) return;
    if (!Number(event.detail) && now() - seenState.keyAt < SEEN_KEY_CLICK_MS) return;
    try { seenToggle(check); } catch {}
  };
  // Нажатие мышью фокус поля ввода не отнимает и до карточки не доходит.
  const onSeenPress = event => {
    if (!state.alive || !seenCheckAt(event?.target)) return;
    event.preventDefault?.();
    event.stopImmediatePropagation?.();
  };
  // Enter и пробел на галочке (Tab до неё доходит сам: это кнопка). Удержание клавиши не мигает.
  const onSeenKey = event => {
    const key = event?.key;
    if (key !== "Enter" && key !== " " && key !== "Spacebar") return;
    const check = state.alive && event.target?.hasAttribute?.(SEEN_CHECK_ATTRIBUTE) ? event.target : null;
    if (!check) return;
    event.preventDefault?.();
    event.stopImmediatePropagation?.();
    if (event.repeat) return;
    seenState.keyAt = now();
    try { seenToggle(check); } catch {}
  };
  const seenStatus = () => ({ marked: seenState.marks.size, cards: seenState.cards.size, lastError: seenState.error });
  // Сироты прошлой установки — до первой разметки; при снятии — всё своё.
  const seenSweep = () => {
    try {
      for (const node of document.querySelectorAll(`[${SEEN_CHECK_ATTRIBUTE}]`)) node.remove();
      for (const node of document.querySelectorAll(`[${SEEN_ATTRIBUTE}]`)) node.removeAttribute(SEEN_ATTRIBUTE);
    } catch {}
  };
  seenSweep();
  track(() => {
    for (const [card, check] of [...seenState.cards]) seenDrop(card, check);
    seenSweep();
  });
  // «Просмотрено» у карточек файлов (раздел 12м³): отметок в этом чате, карточек с галочкой в
  // ленте сейчас; lastError — запись отметки не удалась.
  statusPart("seen", () => seenStatus());
  HATCH && Object.assign(HATCH, { seenKeyOf, seenTick });

