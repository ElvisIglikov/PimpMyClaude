  // ---- 5б. Последняя картинка поля ввода для Back в Dictator --------------
  // Метки границы поля и штатной кнопки: Dictator видит их через AX.
  // Нет перехвата Cmd+Z, команд в файлах, нового таймера или смены фокуса.
  const COMPOSER_IMAGE_UNDO_ID = "myclaude-remove-last-composer-image-v1";
  const COMPOSER_IMAGE_UNDO_SCOPE_ID = "myclaude-image-undo-composer-v1";
  let composerImageUndoMark = null;
  let composerImageUndoScopeMark = null;
  const clearComposerImageUndo = () => {
    for (const [mark, id] of [[composerImageUndoMark, COMPOSER_IMAGE_UNDO_ID],
      [composerImageUndoScopeMark, COMPOSER_IMAGE_UNDO_SCOPE_ID]]) {
      if (!mark || mark.node.getAttribute("id") !== id) continue;
      if (mark.previous == null) mark.node.removeAttribute("id");
      else mark.node.setAttribute("id", mark.previous);
    }
    if (composerImageUndoScopeMark?.addedRole &&
        composerImageUndoScopeMark.node.getAttribute("role") === "group") {
      composerImageUndoScopeMark.node.removeAttribute("role");
    }
    composerImageUndoMark = null;
    composerImageUndoScopeMark = null;
  };
  const composerImageUndoVisible = element => {
    if (!element?.isConnected) return false;
    // opacity:0 — нормальный крестик до наведения; display:none/hidden — нет.
    for (let node = element; node; node = node.parentElement) {
      const style = getComputedStyle(node);
      if (node.hasAttribute("hidden") || node.hasAttribute("inert") ||
          node.getAttribute("aria-hidden") === "true" || style.display === "none" ||
          style.visibility === "hidden" || style.visibility === "collapse") return false;
    }
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  };
  const composerImageUndoScope = () => {
    if (!themable || !state.alive || overlayOpen()) return null;
    // findEditor выбирает по геометрии; отмена при двух полях выбирать не смеет.
    const editors = [...document.querySelectorAll('.ProseMirror[contenteditable="true"]')]
      .filter(editor => isFontComposer(editor) && visibleEditor(editor));
    if (editors.length !== 1 || editors[0] !== state.editor) return null;
    const editor = editors[0];
    const composer = editor.closest('[data-cds="ChatComposer"]') ?? editor.closest('.epitaxy-prompt');
    const role = composer.getAttribute("role");
    // Явно скрытый от AX контейнер не переопределяем. У div без роли ставим
    // временную group ниже, иначе Chromium вправе пропустить его в AXParent.
    if (role != null && (!role.trim() || /(?:^|\s)(?:generic|none|presentation)(?:\s|$)/i.test(role))) return null;
    // Метка нужна ещё ДО первой картинки. Высота широкого поля не ограничена:
    // оно занимает всю колонку, а блок вложений — сосед редактора внутри него.
    return composerImageUndoVisible(composer) &&
      composer.querySelectorAll('[data-cds-composer-attachments]').length <= 1 ? composer : null;
  };
  const composerImageUndoButton = (composer = composerImageUndoScope()) => {
    if (!composer) return null;
    const boxes = composer.querySelectorAll('[data-cds-composer-attachments]');
    if (boxes.length !== 1) return null;
    const images = boxes[0].querySelectorAll('[data-cds="MessageAttachmentsImage"][data-cds-attachment]');
    const last = images[images.length - 1];
    if (!last) return null;
    const buttons = [...last.querySelectorAll('button[aria-label]')].filter(button => {
      const label = String(button.getAttribute("aria-label") ?? "").trim();
      return attachRemoveLabel(label);
    });
    if (buttons.length !== 1) return null;
    const button = buttons[0];
    if (!button.isConnected || button.disabled || button.hasAttribute("disabled") ||
        button.getAttribute("aria-disabled") === "true") return null;
    return composerImageUndoVisible(button) ? button : null;
  };
  const syncComposerImageUndo = () => {
    const composer = composerImageUndoScope();
    const button = composerImageUndoButton(composer);
    if (composer && composer === composerImageUndoScopeMark?.node &&
        composer.getAttribute("id") === COMPOSER_IMAGE_UNDO_SCOPE_ID &&
        button === (composerImageUndoMark?.node ?? null) &&
        (!button || button.getAttribute("id") === COMPOSER_IMAGE_UNDO_ID)) return;
    clearComposerImageUndo();
    if (!composer || document.getElementById(COMPOSER_IMAGE_UNDO_SCOPE_ID)) return;
    const addedRole = !composer.hasAttribute("role");
    composerImageUndoScopeMark = { node: composer, previous: composer.getAttribute("id"), addedRole };
    composer.setAttribute("id", COMPOSER_IMAGE_UNDO_SCOPE_ID);
    if (addedRole) composer.setAttribute("role", "group");
    if (!button || document.getElementById(COMPOSER_IMAGE_UNDO_ID)) return;
    composerImageUndoMark = { node: button, previous: button.getAttribute("id") };
    button.setAttribute("id", COMPOSER_IMAGE_UNDO_ID);
  };
  track(clearComposerImageUndo);
  statusPart("composerImageUndo", () => ({
    version: 1,
    composer: Boolean(composerImageUndoScopeMark &&
      composerImageUndoScopeMark.node === composerImageUndoScope() &&
      composerImageUndoScopeMark.node.getAttribute("id") === COMPOSER_IMAGE_UNDO_SCOPE_ID),
    available: Boolean(composerImageUndoMark &&
      composerImageUndoMark.node === composerImageUndoButton() &&
      composerImageUndoMark.node.getAttribute("id") === COMPOSER_IMAGE_UNDO_ID),
  }));

