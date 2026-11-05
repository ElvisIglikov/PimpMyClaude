  // ---- 12 · ⌘Z возвращает снятое вложение (#9193) --------------------------
  // Слово Элвиса 09.10 02:35: «скриншот один удалил по случайке… ⌘Z не работает на
  // удаление скриншотов. Сделай, чтобы можно было отменить». Своей отмены у
  // вложений Claude нет: снятое крестиком (или Backspace) уходит из поля насовсем.
  // Каждый проход раскладки запоминает плитки поля вместе с их File (полка
  // «Обкэшить», номер скриншота); плитка пропала сразу после крестика/Backspace —
  // её File кладём в стек. ⌘Z в поле (или мимо любого поля — фокус после крестика
  // уходит в никуда) возвращает верхнюю той же вставкой, какой страница кладёт
  // вложения, — с тем же именем «Скриншот N», а значит с тем же номером; ⌘⇧Z
  // снимает её снова. Перехват — только когда стек не пуст и текст поля с
  // момента снятия не правили: иначе ⌘Z — обычная отмена текста, а до вложения
  // очередь дойдёт, когда текст вернётся к тому виду. Стек живёт в черновике
  // одного чата: отправка, иная пропажа плиток (не крестик), смена чата и
  // dispose его очищают; Esc — нет (вложений он не трогает).
  const ATTACH_UNDO_MAX = 10;
  // Крестик/Backspace и пропажа плитки — одно действие: столько ждём перерисовку.
  const ATTACH_UNDO_SIGNAL_MS = 3000;
  const attachUndo = { undo: [], redo: [], tiles: [], route: null, signal: null, restored: 0, removed: 0 };
  const attachUndoClear = () => { attachUndo.undo = []; attachUndo.redo = []; attachUndo.signal = null; };
  track(() => { attachUndoClear(); attachUndo.tiles = []; });
  const attachUndoFile = (name, previous) => {
    const issued = shotHome.shots.get(shotRoute())?.issued.get(name)?.file?.deref?.();
    if (issued) return issued;
    const shelf = cashoutHome().shelf;
    for (let at = shelf.length - 1; at >= 0; at -= 1) if (shelf[at].name === name && shelf[at].file) return shelf[at].file;
    return previous.find(tile => tile.name === name)?.file ?? null;
  };
  const attachRemoveButton = node => {
    for (const button of node?.querySelectorAll?.("button[aria-label]") ?? []) {
      const label = String(button.getAttribute("aria-label") ?? "");
      if (attachRemoveLabel(label)) return button;
    }
    return null;
  };
  // Повод снять: крестик плитки поля (имя — из его подписи), Backspace/Delete в
  // блоке ввода (имени нет), отправка — стек прочь.
  const attachUndoMark = event => {
    try {
      const target = event?.target;
      if (event.type === "click") {
        const button = target?.closest?.("button[aria-label]");
        const label = String(button?.getAttribute?.("aria-label") ?? "");
        if (button && attachRemoveLabel(label) &&
            button.closest?.("[data-cds-composer-attachments]") && !attachUndo.signal?.redo) {
          attachUndo.signal = { at: Date.now(), name: attachRemoveName(label) };
        }
      } else if (event.type === "keydown" && (event.key === "Backspace" || event.key === "Delete") && !event.metaKey &&
          (state.editor?.contains?.(target) || cashoutBox()?.contains?.(target))) {
        attachUndo.signal = { at: Date.now(), name: null };
      }
    } catch {}
  };
  const attachUndoSync = () => {
    const route = shotRoute();
    if (attachUndo.route !== route) { attachUndoClear(); attachUndo.route = route; attachUndo.tiles = []; }
    const editor = pasteEditor();
    // Поля нет (пересборка композера) — сверять не с чем: молчание поля не «сняли».
    if (!editor) return;
    const names = shotTiles().map(shotTileName).filter(Boolean);
    const previous = attachUndo.tiles;
    const left = [...names];
    const gone = [];
    for (const tile of previous) {
      const at = left.indexOf(tile.name);
      if (at >= 0) left.splice(at, 1); else gone.push(tile);
    }
    if (gone.length) {
      const signal = attachUndo.signal && Date.now() - attachUndo.signal.at < ATTACH_UNDO_SIGNAL_MS ? attachUndo.signal : null;
      if (!signal) attachUndoClear();
      else {
        const text = rawText(editor);
        for (const tile of gone) {
          if (!tile.file || (signal.name && signal.name !== tile.name)) continue;
          attachUndo.undo.push({ name: tile.name, file: tile.file, route, text });
        }
        if (!signal.redo) attachUndo.redo = [];
        while (attachUndo.undo.length > ATTACH_UNDO_MAX) attachUndo.undo.shift();
        attachUndo.signal = null;
      }
    }
    attachUndo.tiles = names.map(name => ({ name, file: attachUndoFile(name, previous) }));
  };
  const attachUndoRestore = (entry, editor) => {
    if (!attachFresh([entry.file], "undo").length) return false;
    const data = new DataTransfer();
    data.items.add(entry.file);
    cashoutRemember([entry.file]);
    pasteRelaying = true;
    try {
      editor.focus();
      editor.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
    } finally { pasteRelaying = false; }
    attachUndo.redo.push({ ...entry, text: rawText(editor) });
    attachUndo.restored += 1;
    return true;
  };
  const attachUndoRemove = entry => {
    const tile = shotTiles().filter(node => shotTileName(node) === entry.name).pop();
    const button = attachRemoveButton(tile);
    if (!button) return false;
    attachUndo.signal = { at: Date.now(), name: entry.name, redo: true };
    button.click();
    attachUndo.removed += 1;
    return true;
  };
  // ⌘Z / ⌘⇧Z (на русской раскладке та же клавиша — «я»: узнаём и по code).
  const onAttachUndoKey = event => {
    try {
      if (!event?.metaKey || event.altKey || event.ctrlKey || event.isComposing) return;
      if (String(event.key ?? "").toLowerCase() !== "z" && event.code !== "KeyZ") return;
      const redo = Boolean(event.shiftKey);
      const stack = redo ? attachUndo.redo : attachUndo.undo;
      if (!stack.length) return;
      const editor = pasteEditor();
      if (!editor || (!editor.contains(event.target) && !pasteOutside(event.target))) return;
      const entry = stack[stack.length - 1];
      if (entry.route !== shotRoute()) { attachUndoClear(); return; }
      if (rawText(editor) !== entry.text || shotState.pending) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      stack.pop();
      if (redo) attachUndoRemove(entry); else attachUndoRestore(entry, editor);
      scheduleLayout();
    } catch {}
  };

  // Сколько вложений видно в поле ввода. Одной приметы мало: разметка Claude
  // меняется без предупреждения, поэтому считаем тремя независимыми и берём
  // наибольшее — превью есть не у всякого файла (pdf), а кнопка снятия есть у
  // каждого. «Remove from queue» — не вложение, это очередь сообщений.
  const CASHOUT_PILL_CARD = '.epitaxy-attachment-pill,[data-testid$="attachment"],[data-testid$="attachment-pill"],[data-testid$="file-pill"]';
  // Превью считаем разбором src, а не селектором: значок самого композера тоже
  // бывает картинкой data: (svg), и селектор насчитал бы вложений больше, чем
  // их есть, — а лишнее «не доехало» такая же неправда, как молчание.
  const cashoutPreviews = box => {
    let seen = 0;
    for (const node of box.querySelectorAll("img[src]")) {
      const src = String(node.getAttribute("src") ?? "");
      if (src.startsWith("blob:") || /^data:image\/(?!svg)/i.test(src)) seen += 1;
    }
    return seen;
  };
  // Коробка поля ввода: рамка композера, а пока её не нашли — оболочка.
  const cashoutBox = () => (state.composerBlock?.isConnected ? state.composerBlock
    : (state.shell?.isConnected ? state.shell : null));
  const cashoutPills = () => {
    const box = cashoutBox();
    if (!box) return 0;
    try {
      const previews = cashoutPreviews(box);
      const cards = box.querySelectorAll(CASHOUT_PILL_CARD).length;
      let buttons = 0;
      for (const node of box.querySelectorAll("button[aria-label]")) {
        const label = String(node.getAttribute("aria-label") ?? "").trim().toLowerCase();
        if (!attachRemoveLabel(label)) continue;
        buttons += 1;
      }
      return Math.max(previews, cards, buttons);
    } catch { return 0; }
  };
  // Как ПОДПИСАНЫ вложения, видимые в поле. Счёт плашек говорит «сколько», а
  // уборке нужно «какие»: снятое крестиком лежит на полке вперемешку с живым, и
  // по одному числу не понять, какая запись осталась без плашки. Берём подпись
  // кнопки снятия («Remove снимок.png»), а если её сегодня нет — текст самой
  // карточки. Сверяем ВХОЖДЕНИЕМ имени: вокруг него бывает и слово «Remove», и
  // размер файла. Имя — только подсказка: у pdf подписи может не быть вовсе, и
  // тогда за него отвечает общий счёт плашек.
  const cashoutPillNames = () => {
    const box = cashoutBox();
    if (!box) return [];
    try {
      const names = [];
      for (const node of box.querySelectorAll("button[aria-label]")) {
        const label = String(node.getAttribute("aria-label") ?? "").trim();
        if (!attachRemoveLabel(label)) continue;
        names.push(label);
      }
      if (names.length) return names;
      for (const node of box.querySelectorAll(CASHOUT_PILL_CARD)) {
        const text = String(node.textContent ?? "").trim();
        if (text) names.push(text);
      }
      return names;
    } catch { return []; }
  };
  // Уборка полки (#5789, у донора ElvisOS она зовётся sweep). Полка обязана
  // отражать то, что ВИДНО в поле: Элвис снимает плашку крестиком или отправляет
  // сообщение — вложение ушло из поля, а из памяти окна нет. Тогда «Обкэшить»
  // увозит не то, что видно, и снятый файл выигрывает у нового с тем же именем
  // (🟣 Kaban 2869 — месяц отладки у донора). Плюс вес: без уборки в каждом окне
  // висят ссылки на 24 файла и 48 МБ до самого закрытия Claude.
  //
  // Сверяемся не наблюдателем документа (он работал бы на каждом кадре ответа),
  // а редким опросом ПОЛЯ и только пока на полке что-то лежит. Свежая запись
  // неприкосновенна: между вставкой файла и появлением плашки проходит заметное
  // время, и без отсрочки уборка съедала бы только что положенное.
  let cashoutSweepTimer = 0;
  const stopCashoutSweep = () => {
    if (!cashoutSweepTimer) return;
    clearInterval(cashoutSweepTimer);
    cashoutSweepTimer = 0;
  };
  track(stopCashoutSweep);
  const cashoutSweep = () => {
    const home = cashoutHome();
    if (!home.shelf.length) { stopCashoutSweep(); return; }
    // Поля на месте нет (React пересобрал композер, чат переключается) — сверять
    // не с чем, и молчание поля это не «вложений не осталось». Пропускаем тик:
    // полка дождётся следующего, а вычеркнуть живое вложение мы права не имеем.
    if (!cashoutBox()) return;
    const now = Date.now();
    const free = cashoutPillNames();
    // Плашек в поле бывает больше, чем читаемых подписей: незанятые ими места
    // достаются самым свежим записям — ровно тот порядок, каким полку читает
    // cashoutHaul.
    let room = Math.max(0, cashoutPills() - free.length);
    const keep = [];
    for (let at = home.shelf.length - 1; at >= 0; at -= 1) {
      const item = home.shelf[at];
      const hit = item.name
        ? free.findIndex(label => label === item.name || label.includes(item.name))
        : -1;
      if (hit >= 0) { free.splice(hit, 1); keep.unshift(item); continue; }
      if (now - item.at < CASHOUT_SWEEP_GRACE_MS) { keep.unshift(item); continue; }
      if (room > 0) { room -= 1; keep.unshift(item); }
    }
    if (keep.length !== home.shelf.length) home.shelf = keep;
    if (!keep.length) stopCashoutSweep();
  };
  const startCashoutSweep = () => {
    if (!themable || cashoutSweepTimer || !cashoutHome().shelf.length) return;
    cashoutSweepTimer = setInterval(cashoutSweep, CASHOUT_SWEEP_MS);
  };
  // Что уезжает: столько файлов с КОНЦА полки, сколько плашек видно в поле.
  // Счёт штуками, а не именами: восемь скриншотов зовутся одинаково, и проверка
  // по имени засчитывала бы восемь по одной доехавшей. С конца — потому что
  // снятое крестиком и уже отправленное ушло из поля раньше.
  const cashoutHaul = () => {
    const want = cashoutPills();
    if (want <= 0) return { want: 0, files: [] };
    const shelf = cashoutHome().shelf;
    const seen = new Set();
    const files = [];
    for (let at = shelf.length - 1; at >= 0 && files.length < want; at -= 1) {
      const item = shelf[at];
      if (item.hash) {
        if (seen.has(item.hash)) continue;
        seen.add(item.hash);
      }
      files.unshift(item);
    }
    return { want, files };
  };
  // Одинаковые имена Claude склеивает в ОДНО вложение — разводим суффиксом
  // (донор делает это же по той же причине), иначе восемь image.png доедут одной
  // картинкой.
  const cashoutUniqueName = (name, taken) => {
    const base = name || "файл";
    if (!taken.has(base)) return base;
    const dot = base.lastIndexOf(".");
    const stem = dot > 0 ? base.slice(0, dot) : base;
    const tail = dot > 0 ? base.slice(dot) : "";
    for (let copy = 2; copy <= CASHOUT_FILES_MAX + 1; copy += 1) {
      const next = `${stem}-${copy}${tail}`;
      if (!taken.has(next)) return next;
    }
    return `${stem}-${Date.now()}${tail}`;
  };
  // Копию делает то окно, где груз ЛЕЖИТ (главное), своим конструктором File:
  // донора закрывают сразу после доезда текста, и объекты его умершего окна
  // стали бы негодны. Конструктора нет — везём как есть и честно теряем
  // разведение имён, но не файл.
  const cashoutCopyFile = (file, name, type) => {
    if (!file) return null;
    try { return new File([file], name, type ? { type } : undefined); } catch { return file; }
  };
  // Принять груз: зовёт ДОНОР у окна-родителя (или сам у себя, если он главное
  // окно). Возвращает, сколько файлов принято.
  const cashoutCarry = (list, at, want) => {
    const home = cashoutHome();
    const stamp = Number(at);
    const items = Array.isArray(list) ? list : [];
    if (!items.length || !Number.isFinite(stamp)) { home.carry = null; return 0; }
    const files = [];
    const names = new Set();
    let total = 0;
    for (const item of items) {
      if (files.length >= CASHOUT_FILES_MAX) break;
      const size = Number(item?.size) || 0;
      if (!size || total + size > CASHOUT_BYTES_MAX) continue;
      const name = cashoutUniqueName(String(item?.name ?? ""), names);
      const copy = cashoutCopyFile(item?.file, name, String(item?.type ?? ""));
      if (!copy) continue;
      names.add(name);
      total += size;
      files.push(copy);
    }
    home.carry = files.length
      ? { at: stamp, want: Math.max(Number(want) || 0, files.length), files }
      : null;
    return files.length;
  };
  // Забрать груз: зовёт НОВОЕ окно у того же родителя. done:true — груз больше не
  // нужен, байты можно отпустить.
  const cashoutTake = (at, done) => {
    const home = cashoutHome();
    const carry = home.carry;
    if (!carry || !Array.isArray(carry.files) || Number(at) !== carry.at) return null;
    const taken = { at: carry.at, want: carry.want, files: carry.files.slice() };
    if (done === true) home.carry = null;
    return taken;
  };
  // Где лежит груз: у главного окна — у себя, у попапа — у родителя. Родителя
  // нет или он старой версии — груз не поедет, и об этом говорит плашка.
  const cashoutHost = () => {
    try {
      if (isMainWindow()) return { carry: cashoutCarry, take: cashoutTake };
      const parent = window.opener;
      const outside = parent?.__myclaude;
      if (typeof outside?.cashoutCarry !== "function" || typeof outside?.cashoutTake !== "function") return null;
      return {
        carry: (list, at, want) => outside.cashoutCarry(list, at, want),
        take: (at, done) => outside.cashoutTake(at, done),
      };
    } catch { return null; }
  };
  // Курсор в самое начало поля: вставка ложится ПЕРЕД черновиком и не затирает
  // его. Пустому полю это ничего не стоит.
  const caretToStart = (editor) => {
    try {
      const selection = (typeof getSelection === "function" ? getSelection() : null) ?? document.getSelection?.();
      if (!selection) return;
      const range = document.createRange();
      range.setStart(editor, 0);
      range.collapse(true);
      selection.removeAllRanges();
      selection.addRange(range);
    } catch {}
  };
  // Курсор в конец поля (кнопка «Отчёт» панели PMP, 12п³; слова-действия, 12р).
  const caretToEnd = (editor) => {
    try {
      const selection = (typeof getSelection === "function" ? getSelection() : null) ?? document.getSelection?.();
      if (!selection) return;
      const range = document.createRange();
      range.selectNodeContents(editor);
      range.collapse(false);
      selection.removeAllRanges();
      selection.addRange(range);
    } catch {}
  };
  // Приметный кусок вставки: по нему видно, что в поле попал ИМЕННО наш текст.
  // Нужен он только при вставке ПЕРЕД черновиком — там поле непусто и до
  // вставки, и «поле не пусто» ничего не доказывает. В пустое поле критерий
  // прежний: поле стало непустым. Требовать примету и там нельзя — ProseMirror
  // переписывает вставленное по-своему (списки, кавычки, разметка), примета не
  // находится, и второй путь клал бы текст ВТОРОЙ раз: так дублился «Обкэшить».
  const insertProbe = (text) => String(text).replace(/\s+/g, " ").trim().slice(0, 40);
  const insertLength = (editor) => rawText(editor).replace(/\s+/g, " ").length;
  const insertLanded = (editor, probe, before) => {
    const after = rawText(editor).replace(/\s+/g, " ");
    return after.length > before && (probe === "" || after.includes(probe));
  };
  // Вставка текста в редактор. Сначала execCommand — Chromium проводит его через
  // штатный ввод, и ProseMirror видит обычный набор; если тот его проглотил (в
  // разных сборках бывает и так), досылаем то же самое событием paste с
  // DataTransfer. Отправку не трогаем ни в одном из путей: Enter не шлём.
  // atStart: true — перед черновиком, "end" — в конец (курсор туда же), иначе — где курсор.
  // Вставленное потом видно: поле прокручивается к нему (#10333, composerScrollToEnd).
  const insertIntoEditor = (editor, text, atStart) => {
    const landed = insertIntoEditorNow(editor, text, atStart);
    composerScrollToEnd(editor);
    return landed;
  };
  const insertIntoEditorNow = (editor, text, atStart) => {
    const caret = () => { if (atStart === "end") caretToEnd(editor); else if (atStart) caretToStart(editor); };
    const probe = atStart ? insertProbe(text) : "";
    const before = insertLength(editor);
    try { editor.focus(); } catch {}
    caret();
    try { document.execCommand("insertText", false, text); } catch {}
    if (insertLanded(editor, probe, before)) return true;
    // Поле выросло, а примета не нашлась: текст всё-таки лёг, просто редактор
    // переписал его. Второй путь поверх — это ровно дубль, поэтому его нет.
    if (insertLength(editor) > before) return true;
    // ProseMirror не принял execCommand — досылаем то же самое событием paste.
    try { editor.focus(); } catch {}
    caret();
    try {
      const data = new DataTransfer();
      data.setData("text/plain", text);
      editor.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
    } catch {}
    return insertLanded(editor, probe, before);
  };
  // Подтверждение доезда переноса (WF50, #5780) ------------------------------
  // Сравнение нормализованное: NBSP становится пробелом, пробелы схлопываются.
  const cashoutNorm = value => String(value ?? "").replace(/\u00a0/g, " ").replace(/\s+/g, " ").trim();
  // Доехало ли: голова в 40 знаков нашлась ИЛИ длина добрала до 90 % нужной.
  // Второе — про редактор, который переписал вставленное по-своему.
  const cashoutArrived = (editor, text) => {
    const want = cashoutNorm(text);
    if (!want) return true;
    const got = cashoutNorm(rawText(editor));
    const head = want.slice(0, CASHOUT_HEAD);
    return got.length >= Math.min(want.length, CASHOUT_HEAD) &&
      (got.includes(head) || got.length >= want.length * CASHOUT_RATIO);
  };
  // То же, но строго по голове. Спрашивается ДО вставки: длина сама по себе
  // ничего не доказывает (в поле мог лежать чужой черновик той же длины), а
  // голова доказывает, что текст уже лёг, — значит вставлять второй раз нельзя.
  const cashoutHeadHit = (editor, text) => {
    const head = cashoutNorm(text).slice(0, CASHOUT_HEAD);
    return head !== "" && cashoutNorm(rawText(editor)).includes(head);
  };
  // Два способа вставки, между которыми переключается подтверждение. Первый —
  // execCommand (Chromium проводит его через штатный ввод), второй — событие
  // paste с DataTransfer: бывают сборки, где ProseMirror глотает первый.
  // Непустое поле выделяется целиком: черновик Элвиса уже внутри переноса,
  // поэтому вставка ПОВЕРХ ничего не теряет и не задваивает (#5781).
  const cashoutPut = (editor, text, way) => {
    try { editor.focus(); } catch {}
    if (editorText(editor)) { try { document.execCommand("selectAll"); } catch {} }
    // Второй способ — событие paste: поле прокрутит слушатель раздела «Вставка прокручивает поле» (#10333).
    if (way !== 2) { try { document.execCommand("insertText", false, text); } catch {} composerScrollToEnd(editor); return; }
    try {
      const data = new DataTransfer();
      data.setData("text/plain", text);
      editor.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
    } catch {}
  };
  // «Эта запись — мне?» (WF37). true — да, false — точно нет, null — сказать
  // нечего: своего id окно ещё не знает, а заголовок не совпал.
  //
  // Свой id знаем — он и решает ОДИН (#5787): не сошёлся с адресатом, значит
  // запись чужая, и совпадение заголовка её не спасает. Правило WF37 («мой id
  // ИЛИ мой заголовок») писалось, когда id почти никогда не был известен, — а
  // заголовок попапа это снимок имени чата на момент выноса: после
  // переименования его носит уже другое окно, и чужой перенос уезжал бы в чат,
  // где Элвис работает.
  //
  // Заголовок остаётся вторым, запасным признаком ровно там, где первого нет:
  // попап получает имя от сессии в момент выноса, и до первого ответа probe это
  // единственное, чем он себя знает. Заглушки («Claude», «New chat») в
  // сопоставлении не участвуют вовсе — их носят разные чаты во всех окнах разом.
  const cashoutMine = record => {
    const id = myChatId();
    if (id) return id === record.to;
    const title = windowTitle();
    if (title && record.title === title && !THEME_TITLE_STUBS.has(title.toLowerCase())) return true;
    return null;
  };
  // Попап узнаёт свой id только у окна-родителя (раздел 12в), и сторож спрашивает
  // его РОВНО один раз на запись: ответ ложится в кэш myclaude-chat-v1, и
  // следующий тик берёт id уже оттуда. Не ответили — ждём круга probe от
  // приложения, а не долбим родителя каждые 300 мс.
  const cashoutAskParent = () => {
    if (state.cashoutAsked) return;
    state.cashoutAsked = true;
    try { Promise.resolve(chatsAsk(true)).catch(() => {}); } catch {}
  };
  // С какого мгновения в поле стоит чужой черновик и у какой записи (#5781).
  let cashoutDraftFor = 0;
  let cashoutDraftSince = 0;
  // Работа доставки (WF50): одна на окно, свой таймер, две фазы. «text» —
  // вставили и ждём доезда, «files» — текст доехал, ждём карточек вложений.
  // Своего интервала работа не заводит: тикает собственным setTimeout, потому
  // что паузы у фаз разные (150 мс против 200 мс).
  let cashoutJob = null;
  const clearCashoutJob = () => {
    if (!cashoutJob) return;
    if (cashoutJob.timer) clearTimeout(cashoutJob.timer);
    cashoutJob = null;
  };
  track(clearCashoutJob);
  const cashoutLater = () => {
    if (!cashoutJob) return;
    cashoutJob.timer = setTimeout(cashoutTick,
      cashoutJob.phase === "files" ? CASHOUT_ATTACH_MS : CASHOUT_CONFIRM_MS);
  };
  // Приговор: вставить не вышло. Запись НЕ чистим — она умрёт по сроку сама, а
  // приложение по этому слову поймёт, что донора трогать нельзя.
  const cashoutGiveUp = (job, why) => {
    const at = job.at;
    const until = job.until;
    clearCashoutJob();
    clearCashoutWatch();
    cashoutSay(at, until, `${CASHOUT_REFUSED}: ${why}`);
  };
  // Текст доехал: только теперь чистим запись (#5780) и берёмся за вложения.
  const cashoutLanded = (job, editor) => {
    const at = job.at;
    const until = job.until;
    clearCashoutJob();
    clearCashoutWatch();
    clearCashout();
    cashoutSay(at, until, CASHOUT_DONE);
    setStage(STAGE_NORMAL);
    try { cashoutAttach(at, editor); } catch {}
  };
  // Вложения кладём ПОСЛЕ текста: вставка текста идёт с выделением всего поля и
  // смахнула бы прикреплённое. Прикладываем только НЕДОСТАЮЩИЕ — иначе повтор
  // работы приложил бы те же файлы второй раз.
  const cashoutAttach = (at, editor) => {
    const host = cashoutHost();
    const carry = host ? host.take(at, false) : null;
    const files = carry?.files ?? [];
    if (!files.length) return;
    const have = cashoutPills();
    cashoutFilesCount = { want: carry.want, sent: files.length, done: Math.min(have, carry.want) };
    const missing = have < files.length ? attachFresh(files.slice(have), "cashout") : [];
    if (missing.length) {
      try {
        const data = new DataTransfer();
        for (const file of missing) data.items.add(file);
        try { editor.focus(); } catch {}
        editor.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
      } catch {}
    }
    cashoutJob = { at, text: "", editor, phase: "files", way: 0, tries: 0, timer: 0, want: files.length, carry: carry.want };
    cashoutLater();
  };
  const cashoutTick = () => {
    const job = cashoutJob;
    if (!job || !state.alive) { clearCashoutJob(); return; }
    const editor = job.editor?.isConnected ? job.editor : findEditor();
    if (!editor?.isConnected) {
      if (job.phase === "files") { cashoutFinishFiles(job); return; }
      cashoutGiveUp(job, "поле ввода пропало");
      return;
    }
    if (job.phase === "files") {
      const done = cashoutPills();
      cashoutFilesCount = { ...cashoutFilesCount, done: Math.min(done, job.carry) };
      job.tries += 1;
      if (done >= job.want || job.tries >= CASHOUT_ATTACH_TRIES) { cashoutFinishFiles(job); return; }
      cashoutLater();
      return;
    }
    if (cashoutArrived(editor, job.text)) { cashoutLanded(job, editor); return; }
    job.tries += 1;
    if (job.way === 1 && job.tries >= CASHOUT_CONFIRM_FIRST) {
      // Первый способ не взял — досылаем то же самое вторым и ждём ещё.
      job.way = 2;
      job.tries = 0;
      cashoutPut(editor, job.text, 2);
    } else if (job.way === 2 && job.tries >= CASHOUT_CONFIRM_SECOND) {
      cashoutGiveUp(job, "текст не попал в поле");
      return;
    }
    cashoutLater();
  };
  // Конец работы с вложениями: груз отпускаем, недоехавшее называем плашкой —
  // молчаливая потеря вложений и была жалобой Элвиса.
  const cashoutFinishFiles = job => {
    clearCashoutJob();
    const host = cashoutHost();
    try { host?.take(job.at, true); } catch {}
    const done = cashoutFilesCount.done;
    if (done < cashoutFilesCount.want) {
      try { newWindowNote(CASHOUT_NOTE_PART(done, cashoutFilesCount.want)); } catch {}
    }
  };
  const tryPasteCashout = () => {
    const record = readCashout();
    if (record == null) return "нет записи";
    // Работа уже идёт или приговор по ЭТОЙ записи уже вынесен — второй раз не
    // вставляем: дубль текста хуже задержки.
    if (cashoutJob) return "ждём доезда";
    if (cashoutVerdict && record.at === cashoutVerdictAt) return cashoutVerdict;
    // Запись «Нового чата» главного окна (К1, Б2) сторож не вставляет никогда:
    // её забирает цепочка new-window с sendTransfer и стирает сама.
    if (record.handoff && record.to == null) return CASHOUT_HANDOFF_MAIN;
    if (record.to != null) {
      // Перенос из подчинённого окна (WF37, #5575) адресован НОВОМУ окну,
      // которое родит цепочка «Нового окна». Главное окно такие записи не
      // трогает вовсе: ⌘N в нём случается по десять раз на дню, и перенос
      // уехал бы в чат, где Элвис работает.
      if (isMainWindow()) return "перенос не главному окну";
      if (record.to === CASHOUT_PENDING) {
        // Цепочка сорвалась и адресата так и не назвала: запись умирает молча
        // по общему сроку от нажатия (риск 3 плана WF37).
        if (Date.now() - record.at > CASHOUT_FRESH_MS) { clearCashout(); return "запись протухла"; }
        return "адресат не назначен";
      }
      if (record.stampedAt == null || Date.now() - record.stampedAt > CASHOUT_STAMP_FRESH_MS) {
        clearCashout();
        return "перенос протух";
      }
      const mine = cashoutMine(record);
      if (mine === null) { cashoutAskParent(); return "чат не опознан"; }
      if (!mine) return "перенос не в это окно";
      // «Новый чат» (К2, Б2): текст уже ушёл первым сообщением (sent) или его
      // не было вовсе — вставлять нечего, доезд подтверждаем сразу: по этому
      // слову приложение закрывает донора.
      if (record.handoff && (record.sent || record.text === "")) {
        const until = cashoutLife(record);
        clearCashoutWatch();
        clearCashout();
        cashoutSay(record.at, until, CASHOUT_DONE);
        return CASHOUT_DONE;
      }
    } else if (Date.now() - record.at > CASHOUT_FRESH_MS) { clearCashout(); return "запись протухла"; }
    const editor = state.editor?.isConnected ? state.editor : findEditor();
    if (!editor?.isConnected) return "нет редактора";
    // Вставляем только в свежий чат: иначе перенос лёг бы посреди разговора.
    // Свежесть спрашиваем только у записи БЕЗ адресата: у переноса окно названо
    // поимённо, а первым сообщением в нём может оказаться что угодно.
    if (record.to == null && !isFreshChat()) return "чат не свежий";
    // Черновик в поле — больше НЕ отказ (#5781). Раньше перенос из-за него молча
    // протухал, а окно-донор к тому времени уже закрыто (#5768) — терялся текст
    // Элвиса. Свежий чат иногда доезжает с прошлым черновиком, и Claude убирает
    // его сам: столько ждём, а дальше вставляем поверх выделения всего поля.
    if (editorText(editor)) {
      if (cashoutDraftFor !== record.at) { cashoutDraftFor = record.at; cashoutDraftSince = Date.now(); }
      if (Date.now() - cashoutDraftSince < CASHOUT_DRAFT_WAIT_MS) return "ждём черновик";
    }
    // Текст уже в поле (инжект перечитали посреди доставки) — вторую вставку не
    // делаем, только подтверждаем.
    if (!cashoutHeadHit(editor, record.text)) cashoutPut(editor, record.text, 1);
    cashoutJob = { at: record.at, until: cashoutLife(record), text: record.text, editor,
      phase: "text", way: 1, tries: 0, timer: 0 };
    cashoutLater();
    return "ждём доезда";
  };
  const clearCashoutWatch = () => {
    if (!state.cashoutTimer) return;
    clearInterval(state.cashoutTimer);
    state.cashoutTimer = 0;
  };
  track(clearCashoutWatch);
  // Сторож вставки. ⌘N может открыть новый чат и в этом же окне (страница не
  // перезагружается, инжект заново не приходит), поэтому ждём появления свежего
  // чата, а не одного лишь момента установки. Живёт ровно пока запись свежая.
  const CASHOUT_WATCH_DONE = new Set([
    "запись протухла", "нет записи",
    // Перенос протух или достался главному окну — ждать в этом окне больше
    // нечего: свою запись главное окно заведёт заново, вместе со сторожем.
    "перенос протух", "перенос не главному окну",
    // Запись «Нового чата» в главном окне — дело цепочки new-window, не сторожа.
    CASHOUT_HANDOFF_MAIN,
  ]);
  // Дальше сторожу делать нечего: работа доставки вынесла приговор (доехало или
  // не доехало) — она же и гасит сторожа, но повтор тика не должен его заводить.
  const cashoutWatchDone = result => CASHOUT_WATCH_DONE.has(result) ||
    result === CASHOUT_DONE || result.startsWith(`${CASHOUT_REFUSED}:`);
  const armCashoutWatch = () => {
    clearCashoutWatch();
    if (readCashout() == null) return;
    // Вопрос родителю — один на запись, а не на сторожа: новая запись имеет
    // право спросить заново (см. cashoutAskParent).
    state.cashoutAsked = false;
    state.cashoutTimer = setInterval(() => {
      if (!state.alive) { clearCashoutWatch(); return; }
      const result = tryPasteCashout();
      if (cashoutWatchDone(result)) clearCashoutWatch();
    }, CASHOUT_TICK_MS);
  };
  // Текст передачи «Нового чата» (К1, #7072, критик Б3): ТОЛЬКО из последнего
  // ответа — заголовок с «ОТКРОЙ НОВЫЙ ЧАТ», дальше первый блок кода
  // [data-code-text] после него. Блок трёхответной давности или текст панели
  // не годятся: первым сообщением ушёл бы чужой или старый текст. Нет узла —
  // пустая строка, запасного пути нет.
  const CASHOUT_HANDOFF_HEAD_RE = /ОТКРОЙ\s+НОВЫЙ\s+ЧАТ/i;
  // Заголовок и узел блока передачи — их же ищет кнопка «💬 Новый чат» (12к).
  // Берём ПОСЛЕДНИЙ заголовок, у которого после него есть непустой блок кода
  // (WF85, К7.1): по правилу ELVIS.md ответ кончается ещё одним «🆕 ОТКРОЙ
  // НОВЫЙ ЧАТ» без кода, и до WF85 этот хвостовой повтор сбрасывал находку —
  // кнопки под таким ответом не было, ⌘B слал пустой текст.
  // Ищем по всем строкам последнего сообщения (lastAnswerRows) подряд; answer
  // находки — строка с блоком, rows — всё сообщение (на нём ссылки и «Модель:»).
  const cashoutHandoffFind = (answer = lastAnswerRows() ?? lastAnswerNode()) => {
    const rows = Array.isArray(answer) ? answer : answer ? [answer] : [];
    let head = null;
    let hit = null;
    let taken = true;
    // Инлайн-код и чип файла у Claude 2.9939.2 тоже несут data-code-text —
    // с пометкой data-epitaxy-inline-code; блоком передачи они не бывают.
    for (const row of rows) {
      for (const node of row.querySelectorAll('h1,h2,h3,h4,h5,h6,[role="heading"],[data-code-text]:not([data-epitaxy-inline-code])')) {
        if (node.hasAttribute?.("data-code-text")) {
          if (!taken && cashoutCodeText(node)) { hit = { answer: row, rows, head, code: node }; taken = true; }
          continue;
        }
        if (CASHOUT_HANDOFF_HEAD_RE.test(node.textContent ?? "")) { head = node; taken = false; }
      }
    }
    return hit;
  };
  const cashoutCodeText = node => String(node?.getAttribute?.("data-code-text") || node?.textContent || "").trim();
  // Строка «Модель:» между заголовком и блоком (WF85, К7.2, критик В2): фразу и
  // строку модели markdown склеивает в один <p>, поэтому ищем СТРОКУ, а не
  // узел. textContent держит мягкий перенос «\n», innerText — <br>; смотрим оба.
  // Узлы, внутри которых сам блок или заголовок, не берём: иначе строкой
  // «Модель:» могла бы оказаться строка текста передачи.
  const HANDOFF_MODEL_RE = /\b(opus|sonnet|haiku|fable)\s+(\d+(?:\.\d+)?)/i;
  const HANDOFF_EFFORT_RE = /\b(xhigh|extra|low|medium|high|max)\b/i;
  const cashoutHandoffModelLine = hit => {
    if (!hit?.head || !hit.code) return "";
    let after = false;
    for (const row of hit.rows ?? [hit.answer]) {
      for (const node of row.querySelectorAll("*")) {
        if (node === hit.code) return "";
        if (node === hit.head) { after = true; continue; }
        if (!after || node.contains(hit.code) || node.contains(hit.head)) continue;
        for (const text of [node.textContent, node.innerText]) {
          for (const line of String(text ?? "").split("\n")) {
            const clean = line.replace(/^[\s*_>·•-]+/, "");
            if (/^Модель\s*:/i.test(clean)) return clean;
          }
        }
      }
    }
    return "";
  };
  // «Opus 5.5 · 🔥 XHIGH» → {model:"Opus 5.5", effort:"Extra"}; не разобралось — поля нет.
  const cashoutHandoffModel = line => {
    const out = {};
    const model = String(line ?? "").match(HANDOFF_MODEL_RE);
    if (!model) return out;
    out.model = `${model[1][0].toUpperCase()}${model[1].slice(1).toLowerCase()} ${model[2]}`;
    const step = String(line).slice(model.index + model[0].length).match(HANDOFF_EFFORT_RE)?.[1]?.toLowerCase();
    if (step) out.effort = step === "xhigh" || step === "extra" ? "Extra" : `${step[0].toUpperCase()}${step.slice(1)}`;
    return out;
  };
  const runCashout = (detail = null) => {
    if (detail?.handoff === true) return runCashoutHandoff();
    const answer = lastAnswerText();
    const draft = rawText(state.editor).trim();
    const parts = [];
    if (answer) parts.push(answer);
    if (draft) parts.push(draft);
    const text = parts.join("\n\n");
    if (!text) {
      // Молчать нельзя: ⌘N жмёт приложение независимо от нашего ответа, и без
      // плашки Элвис видит только пустой новый чат.
      cashoutRefusal = CASHOUT_NOTE_EMPTY;
      try { newWindowNote(CASHOUT_NOTE_EMPTY); } catch {}
      return false;
    }
    cashoutRefusal = null;
    // Из подчинённого окна перенос уезжает в НОВОЕ окно (WF37, #5575): ⌘N в
    // попапе исполняет главное окно Claude, и старый путь бил по чату, где
    // Элвис ведёт диктовку. Адресата назовёт цепочка «Нового окна»
    // (cashoutStamp), поэтому здесь только пометка «ждёт адресата». Своего
    // сторожа донор не заводит и чужого не оставляет: вставлять перенос ему
    // некуда, а тикать 300 мс впустую незачем.
    const transfer = !isMainWindow();
    const at = Date.now();
    const record = transfer
      ? { at, text, to: CASHOUT_PENDING }
      : { at, text };
    try { localStorage.setItem(CASHOUT_KEY, JSON.stringify(record)); } catch { return false; }
    // Прошлый приговор снимаем: он принадлежал прошлой записи, а новая только
    // поехала (status().cashout.delivery обязан сказать «ждём»).
    cashoutVerdict = "";
    cashoutVerdictAt = 0;
    cashoutVerdictUntil = 0;
    // Вложения (WF50, #5773) уезжают тем же нажатием: File из донора кладём в
    // память главного окна, а забирает их новое окно после доезда текста. Из
    // донора не снимаем НИЧЕГО — только копируем: испорченное окно при отказе и
    // было главной бедой донора ElvisOS.
    const haul = cashoutHaul();
    const host = haul.files.length ? cashoutHost() : null;
    let carried = 0;
    try { carried = host ? host.carry(haul.files, at, haul.want) : 0; } catch { carried = 0; }
    cashoutFilesCount = { want: haul.want, sent: carried, done: 0 };
    // Груз не взяли вовсе (родителя нет или файлов на полке не осталось) —
    // говорим об этом здесь: молча Элвис узнал бы о потере только глазами.
    if (haul.want > 0 && carried === 0) {
      try { newWindowNote(CASHOUT_NOTE_LEFT(haul.want)); } catch {}
    }
    if (transfer) clearCashoutWatch(); else armCashoutWatch();
    return true;
  };
  // «Обкэшить» с handoff (К1): запись без черновика и вложений, сторожа нет ни
  // в попапе, ни в главном окне (Б2). Пустой текст — не отказ: новый чат пустой.
  const runCashoutHandoff = () => {
    const hit = cashoutHandoffFind();
    const text = cashoutCodeText(hit?.code);
    // Кнопка в чате (12к) ждала именно этой команды: приложение её услышало.
    try { continueAck(); } catch {}
    // Ответ ушёл в новый чат (⌘B, кнопка или «сам») — сам его больше не откроет.
    try { autoTaken(hit); } catch {}
    cashoutRefusal = null;
    const at = Date.now();
    const record = isMainWindow() ? { at, text, handoff: true } : { at, text, to: CASHOUT_PENDING, handoff: true };
    // К7.3 (WF85): model и effort — ПОСЛЕ handoff и только разобранные.
    Object.assign(record, cashoutHandoffModel(cashoutHandoffModelLine(hit)));
    try { localStorage.setItem(CASHOUT_KEY, JSON.stringify(record)); } catch { return false; }
    cashoutVerdict = "";
    cashoutVerdictAt = 0;
    cashoutVerdictUntil = 0;
    cashoutFilesCount = { want: 0, sent: 0, done: 0 };
    clearCashoutWatch();
    return true;
  };
  // Штамп переноса (WF37): цепочка «Нового окна» с полем transfer называет
  // адресата записи, оставленной попапом-донором, — id только что рождённого
  // чата и заголовок его строки сайдбара. Записи без пометки «ждёт адресата»
  // не трогаем вовсе: чужой перенос и обычная запись главного окна обязаны
  // остаться как были (критик плана, блокер 2).
  // sent (К2) — текст передачи уже ушёл первым сообщением: эталон record-sent.
  const cashoutStamp = (id, title, sent = false) => {
    const record = readCashout();
    if (record == null || record.to !== CASHOUT_PENDING) return false;
    const chat = typeof id === "string" ? id.trim() : "";
    if (!chat) return false;
    const stamped = {
      at: record.at,
      text: record.text,
      to: chat,
      title: typeof title === "string" ? title.trim() : "",
      stampedAt: Date.now(),
    };
    if (record.handoff) {
      stamped.handoff = true;
      stamped.sent = sent === true;
    }
    try { localStorage.setItem(CASHOUT_KEY, JSON.stringify(stamped)); } catch { return false; }
    return true;
  };
  // ⌘Z снятого вложения (#9193): сколько можно вернуть/снять снова и сколько раз уже.
  statusPart("attachUndo", () => ({ undo: attachUndo.undo.length, redo: attachUndo.redo.length, restored: attachUndo.restored, removed: attachUndo.removed }));
  HATCH && Object.assign(HATCH, { runCashout, tryPasteCashout, cashoutStamp, cashoutPills, cashoutHaul,
    cashoutUniqueName, cashoutSweep, attachUndo });

