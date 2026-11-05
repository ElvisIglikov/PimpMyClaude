  // ---- 12 · Вставка прокручивает поле ввода до конца (#10333) ----------------
  // Слово Элвиса 19.10 14:30: когда происходит вставка в поле ввода, PMP не прокручивает до конца поле
  // ввода, которое справа; нужно, чтобы прокручивал — вставленное должно быть видно. У поля свой
  // прокручиваемый контейнер: в широком виде (WF65, поле — колонкой справа) это `div:has(> .ProseMirror)`
  // раздела 2г, в узком окне — корень поля с ручкой высоты ([data-myclaude-editor-root], overflow-y:auto).
  // Вставка его не двигала, и текст уходил вниз за край. Теперь после вставки контейнер едет к концу, а
  // если курсор стоит не в конце (Workflow перед черновиком, вставка в середину) — ровно настолько, чтобы
  // курсор стал виден, и только внутри самого контейнера: лента и окно не двигаются.
  //
  // Кто зовёт. Слушатель paste на захвате document — настоящий ⌘V (Диктатор, pimp.py paste-*, AirDrop) и
  // все свои вставки событием paste (запасной путь insertIntoEditor, второй способ и вложения «Обкэшить»,
  // номерованные скриншоты, пересылка вставки мимо поля, перетаскивание, ⌘Z вложения): событие,
  // отправленное в поле, проходит захват document так же, как настоящее. Вставки через execCommand
  // события paste не дают — их пути зовут composerScrollToEnd сами: insertIntoEditor («🚀 Workflow»,
  // «Отчёт», новое окно, путь перетащенного файла), cashoutPut («Обкэшить»), sayWrite и sayWriteTail
  // (слова-действия, нажималки, send-text). Набор с клавиатуры не трогаем: paste он не шлёт.
  //
  // Мерим через два кадра: ProseMirror и React дорисовывают вставку не сразу. Вставки подряд, пока
  // прокрутка ждёт кадра, сливаются в одну.
  // Контейнер — само поле или ближайший предок с overflow-y auto|scroll, которому есть куда ехать. Ищем
  // не выше блока ввода (cashoutBox) и не дальше пяти предков (как findEditorRoot): выше — разметка окна
  // и лента, их вставка в поле двигать не должна.
  const COMPOSER_SCROLL_DEPTH = 5;
  const composerScrollState = { frame: 0, editor: null, runs: 0, last: null };
  const composerScrollBox = editor => {
    const block = cashoutBox();
    let node = editor;
    for (let depth = 0; node && depth <= COMPOSER_SCROLL_DEPTH; depth += 1, node = node.parentElement) {
      if (node === document.body || node === document.documentElement) return null;
      const overflow = getComputedStyle(node).overflowY;
      if ((overflow === "auto" || overflow === "scroll") && node.scrollHeight > node.clientHeight) return node;
      if (node === block) return null;
    }
    return null;
  };
  // Курсор этого поля: выделение, чей фокус внутри поля; иначе null — тогда считаем, что курсор в конце.
  const composerCaret = editor => {
    try {
      const selection = (typeof getSelection === "function" ? getSelection() : null) ?? document.getSelection?.();
      const node = selection?.rangeCount ? selection.focusNode : null;
      return node && editor.contains(node) ? selection : null;
    } catch { return null; }
  };
  // За курсором до конца поля только пробелы и пустые строки (у ProseMirror в конце <br>) — курсор в конце.
  const composerCaretAtEnd = (editor, selection) => {
    try {
      const range = document.createRange();
      range.setStart(selection.focusNode, selection.focusOffset);
      range.setEnd(editor, editor.childNodes.length);
      return !String(range.toString()).trim();
    } catch { return true; }
  };
  // Рамка курсора. У свёрнутого выделения Chromium отдаёт строку, но в начале строки и у границы узлов —
  // нули; тогда рамка соседнего знака (курсор — его кромка). Знака нет (пустая строка) — узел строки, но не
  // выше одной строки: у длинного абзаца рамка во весь абзац увела бы курсор за верхний край.
  const composerCaretRect = selection => {
    try {
      const rect = selection.getRangeAt(0).getBoundingClientRect();
      if (rect?.height > 0) return rect;
    } catch {}
    const node = selection.focusNode;
    const offset = Number(selection.focusOffset) || 0;
    if (node?.nodeType === 3) {
      try {
        const length = String(node.data ?? "").length;
        const range = document.createRange();
        if (offset < length) { range.setStart(node, offset); range.setEnd(node, offset + 1); }
        else if (offset > 0) { range.setStart(node, offset - 1); range.setEnd(node, offset); }
        const rect = range.getBoundingClientRect();
        if (rect?.height > 0) return rect;
      } catch {}
    }
    const element = node?.nodeType === 1 ? node : node?.parentElement;
    const rect = element?.getBoundingClientRect?.();
    if (!rect) return null;
    let line = 0;
    try { line = parseFloat(getComputedStyle(element).getPropertyValue("line-height")) || 0; } catch {}
    return line > 0 && rect.height > line ? { top: rect.top, bottom: rect.top + line } : rect;
  };
  const composerScrollNow = () => {
    const wanted = composerScrollState.editor;
    composerScrollState.editor = null;
    const editor = wanted?.isConnected ? wanted : findEditor();
    if (!editor?.isConnected) return;
    composerScrollState.runs += 1;
    const box = composerScrollBox(editor);
    if (!box) { composerScrollState.last = { mode: "none", at: Date.now() }; return; }
    const selection = composerCaret(editor);
    let mode = "end";
    if (selection && !composerCaretAtEnd(editor, selection)) {
      mode = "caret";
      const rect = composerCaretRect(selection);
      if (rect) {
        const frame = box.getBoundingClientRect();
        const style = getComputedStyle(box);
        const top = frame.top + (parseFloat(style.paddingTop) || 0);
        const bottom = frame.bottom - (parseFloat(style.paddingBottom) || 0);
        if (rect.bottom > bottom) box.scrollTop += rect.bottom - bottom;
        else if (rect.top < top) box.scrollTop -= top - rect.top;
      }
    } else box.scrollTop = box.scrollHeight;
    composerScrollState.last = { mode, top: Math.round(Number(box.scrollTop) || 0), height: box.scrollHeight,
      client: box.clientHeight, at: Date.now() };
  };
  // editor — поле, куда вставляли; нет его или пропал к кадру — findEditor().
  const composerScrollToEnd = editor => {
    if (!state.alive) return;
    if (editor?.isConnected) composerScrollState.editor = editor;
    if (composerScrollState.frame) return;
    try {
      composerScrollState.frame = requestAnimationFrame(() => {
        composerScrollState.frame = requestAnimationFrame(() => {
          composerScrollState.frame = 0;
          if (!state.alive) return;
          try { composerScrollNow(); } catch {}
        });
      });
    } catch { composerScrollState.frame = 0; }
  };
  track(() => {
    if (composerScrollState.frame) { try { cancelAnimationFrame(composerScrollState.frame); } catch {} }
    composerScrollState.frame = 0;
    composerScrollState.editor = null;
  });
  // Вставка в само поле ввода (цель — оно или узел внутри). Чужие поля (поиск чатов, правка старого
  // сообщения) не трогаем. Событие не отменяем и ничего в нём не меняем.
  const onComposerPaste = event => {
    try {
      const target = event?.target;
      const editor = findEditor();
      if (!target || !editor?.isConnected || !editor.contains(target)) return;
      composerScrollToEnd(editor);
    } catch {}
  };
  // На чужой странице (артефакт, логин) поля ввода нет — и подписки нет, как у вставки раздела 12.
  if (themable) on(document, "paste", onComposerPaste, true);
  // Сколько раз прокручивали и чем кончилась последняя: mode end | caret | none (контейнеру некуда ехать);
  // top — scrollTop контейнера после прокрутки, height и client — его scrollHeight и clientHeight.
  statusPart("composerScroll", () => ({ runs: composerScrollState.runs, last: composerScrollState.last }));
  HATCH && Object.assign(HATCH, { composerScrollToEnd });
