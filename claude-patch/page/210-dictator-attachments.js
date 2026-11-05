  // ---- 5в. Только метаданные вложений для Dictator -----------------------
  // AXDescription содержит JSON; текста, имён, URL и файлов здесь нет.
  // Отсутствующая метка означает unknown, а не пустое поле. Число относится
  // только к карточкам текущего composer, не к серверному лимиту Claude.
  const COMPOSER_ATTACHMENTS_ID = "myclaude-composer-attachments-v1";
  const attachmentSession = globalThis.crypto?.randomUUID?.()
    ?? `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  let attachmentGeneration = 0;
  let attachmentRevision = 0;
  let attachmentNextID = 0;
  let attachmentIDs = new WeakMap();
  let attachmentContext = null;
  let attachmentMembers = [];
  let attachmentMarker = null;
  let attachmentObserver = null;
  const clearAttachmentMarker = () => {
    attachmentMarker?.remove();
    attachmentMarker = null;
  };
  const invalidateAttachments = () => {
    clearAttachmentMarker();
    attachmentGeneration += 1;
    attachmentRevision = 0;
    attachmentMembers = [];
    attachmentIDs = new WeakMap();
  };
  const attachmentRoute = () => {
    const chat = myChatId();
    // Не угадываем попап по заголовку; используем существующее опознание Pimp.
    // У нового чата ещё нет id: DOM + маршрут + поколение задают его жизнь.
    const fresh = isMainWindow() && /^\/(?:epitaxy|new)\/?$/.test(location.pathname);
    // myChatId знает локальные чаты; обычный веб-чат опознаём отдельно.
    // Сам маршрут остаётся внутри замыкания, AX получает только поколение.
    const webChat = isMainWindow() && /^\/chat\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/?$/i.test(location.pathname);
    if (!chat && !fresh && !webChat) return null;
    return `${location.pathname}\n${location.search}\n${location.hash}\n${chat ?? "new"}`;
  };
  const attachmentCardReady = card => {
    if (!["MessageAttachmentsImage", "MessageAttachmentsFile"].includes(card.getAttribute("data-cds")) ||
        !composerImageUndoVisible(card) || card.querySelector('[data-cds-attachment]') ||
        card.matches('[aria-busy="true"],[data-state="loading"],[data-status="uploading"],[data-status="error"]') ||
        card.querySelector('[role="progressbar"],[role="alert"],[aria-busy="true"],[data-state="loading"],[data-status="uploading"],[data-status="error"]')) return false;
    if (card.getAttribute("data-cds") === "MessageAttachmentsImage") {
      const images = [...card.querySelectorAll("img")];
      if (images.length !== 1 || !images[0].complete || !(images[0].naturalWidth > 0)) return false;
    }
    const remove = [...card.querySelectorAll('button[aria-label]')].filter(button => attachRemoveLabel(button.getAttribute("aria-label")));
    return remove.length === 1 && !remove[0].disabled && !remove[0].hasAttribute("disabled") &&
      remove[0].getAttribute("aria-disabled") !== "true" && composerImageUndoVisible(remove[0]);
  };
  const syncComposerAttachments = () => {
    const composer = composerImageUndoScope();
    const route = attachmentRoute();
    const editor = state.editor;
    if (!composer || !route || composer.getAttribute("id") !== COMPOSER_IMAGE_UNDO_SCOPE_ID) {
      if (attachmentContext) invalidateAttachments();
      attachmentContext = null;
      attachmentObserver?.disconnect();
      return;
    }
    if (attachmentContext?.composer !== composer || attachmentContext?.editor !== editor ||
        attachmentContext?.route !== route) {
      invalidateAttachments();
      attachmentContext = { composer, editor, route };
      attachmentObserver?.disconnect();
      attachmentObserver ??= new MutationObserver(records => {
        const relevant = records.filter(record => {
          if (record.target === attachmentMarker) return false;
          const nodes = [...(record.addedNodes ?? []), ...(record.removedNodes ?? [])];
          return record.type !== "childList" || !nodes.length ||
            !nodes.every(node => node.id === COMPOSER_ATTACHMENTS_ID);
        });
        if (!relevant.length) return;
        // Полная замена содержимого редактора — возможный submit/reset.
        // Текст не читаем; лучше новый ticket, чем вставка в новое сообщение.
        if (relevant.some(record => record.target === attachmentContext?.editor &&
            (record.removedNodes?.length ?? 0) > 0)) invalidateAttachments();
        syncComposerAttachments();
      });
      attachmentObserver.observe(composer, { childList: true, subtree: true, attributes: true,
        attributeFilter: ["aria-busy", "aria-disabled", "disabled", "data-state", "data-status", "data-cds", "data-cds-attachment", "hidden", "inert", "aria-hidden", "contenteditable"] });
    }
    const boxes = [...composer.querySelectorAll('[data-cds-composer-attachments]')];
    const cards = boxes.length === 1 ? [...boxes[0].querySelectorAll('[data-cds-attachment]')] : [];
    // Ноль коробок в опознанном composer — нормальное состояние до первого
    // вложения. Чужие карточки без штатной коробки и неизвестная разметка — нет.
    // С 30.10 плитки лежат в коробке через обёртки (столбец → ряд прокрутки, #11187):
    // всё, что не плитка и не внутри неё, обязано держать плитку — заглушка
    // загрузки, чип папки или записи без плитки — неизвестная разметка.
    if (boxes.length > 1 || cards.length > 100 ||
        (boxes.length === 1 && [...boxes[0].querySelectorAll("*")].some(node =>
          !node.closest('[data-cds-attachment]') && !node.querySelector('[data-cds-attachment]'))) ||
        composer.querySelectorAll('[data-cds-attachment]').length !== cards.length ||
        composer.matches('[aria-busy="true"]') ||
        composer.querySelector('[role="progressbar"],[aria-busy="true"]') ||
        !cards.every(attachmentCardReady)) { clearAttachmentMarker(); return; }
    const members = cards.map(card => {
      if (!attachmentIDs.has(card)) attachmentIDs.set(card, `m${++attachmentNextID}`);
      return attachmentIDs.get(card);
    }).sort();
    // Удаление/замена прежней карточки не подтверждает наш paste и закрывает
    // прошлый ticket, даже если общее количество осталось прежним.
    if (attachmentMembers.some(id => !members.includes(id))) {
      invalidateAttachments();
      syncComposerAttachments();
      return;
    }
    if (members.join(",") !== attachmentMembers.join(",")) {
      attachmentRevision += 1;
      attachmentMembers = members;
    }
    if (attachmentMarker && attachmentMarker.parentElement !== composer) clearAttachmentMarker();
    if (!attachmentMarker) {
      if (document.getElementById(COMPOSER_ATTACHMENTS_ID)) return;
      attachmentMarker = document.createElement("span");
      attachmentMarker.id = COMPOSER_ATTACHMENTS_ID;
      attachmentMarker.setAttribute("role", "img");
      Object.assign(attachmentMarker.style, { position: "absolute", width: "1px", height: "1px",
        overflow: "hidden", clipPath: "inset(50%)", pointerEvents: "none" });
      composer.appendChild(attachmentMarker);
    }
    const payload = JSON.stringify({ v: 1, session: attachmentSession, generation: attachmentGeneration,
      revision: attachmentRevision, count: members.length, members });
    if (attachmentMarker.getAttribute("aria-label") !== payload) attachmentMarker.setAttribute("aria-label", payload);
  };
  const onAttachmentBoundary = event => {
    attachUndoMark(event);
    const context = attachmentContext;
    if (!context) return;
    const target = event.target;
    const inside = context.composer.contains(target) || target?.contains?.(context.editor);
    const sendKey = event.type === "keydown" && event.key === "Enter" && !event.shiftKey &&
      !event.metaKey && !event.altKey && !event.isComposing && context.editor.contains(target);
    const sendClick = event.type === "click" && (target?.closest?.('[data-testid="code-prompt-send"]') ||
      (inside && target?.closest?.('button[type="submit"]')));
    if (sendKey || sendClick || (inside && ["submit", "reset"].includes(event.type))) {
      attachUndoClear();
      if (event.type === "reset") { shotDraft().attempt = null; for (const job of shotState.jobs) shotCancel(job); }
      else shotAttempt();
      invalidateAttachments();
      scheduleLayout();
    }
  };
  track(() => { attachmentObserver?.disconnect(); clearAttachmentMarker(); attachmentContext = null; });
  // Скролл-контейнер редактора: высотой управляет он, поэтому кнопки composer
  // остаются на месте, а текст внутри прокручивается штатно.
  const findEditorRoot = editor => {
    let element = editor.parentElement;
    for (let depth = 0; element && depth < 5; depth += 1, element = element.parentElement) {
      const computed = getComputedStyle(element);
      if (computed.overflowY === "auto" || computed.overflowY === "scroll") return element;
    }
    return editor.parentElement;
  };
  // Видимая строка под узлом: строка модели или любая другая полоса. sr-only и
  // пустые обёртки в счёт не идут — по этой же примете разбирается низ блока в
  // findComposerParts.
  const rowUnder = node => {
    for (let sibling = node.nextElementSibling; sibling; sibling = sibling.nextElementSibling) {
      if (sibling.classList.contains("sr-only") || sibling.getAttribute("aria-hidden") === "true") continue;
      if (sibling.getBoundingClientRect().height >= MODEL_ROW_MIN_HEIGHT) return sibling;
    }
    return null;
  };
  // Внешняя рамка composer: полоску ставим на её верхнюю границу — над строкой
  // вложений, а не между вложениями и текстом. В нынешней сборке рамка зовётся
  // .epitaxy-prompt (замер оркестратора), и если она на месте — берём её. Если
  // класс переименуют, остаётся разбор донора по геометрии: признак рамки —
  // скругление, у контейнеров вокруг его нет вовсе. Скруглённый предок не
  // считается рамкой, если поднялся над полем выше, чем помещается строка
  // вложений: это уже разметка страницы.
  //
  // В сборке 12.09.2026 .epitaxy-prompt держит уже не рамку поля, а ВЕСЬ низ
  // окна: рамку и строку модели под ней. Отдать его рамкой — значит остаться
  // без внешнего блока: findComposerBlock возвращает тогда тот же узел,
  // collapseTargets — пустой список, и одинарный клик перестаёт сворачивать
  // поле вовсе (#5857, замер в живом окне: блок ввода на 566 точек из 784).
  // Поэтому рамку ищем ВНУТРИ него — берём самого верхнего предка поля, под
  // которым в том же родителе стоит ещё одна видимая строка. Именно она и есть
  // строка модели, а всё, что выше неё, — рамка со вложениями.
  const framedInside = (named, start) => {
    let frame = null;
    for (let node = start; node && node !== named && named.contains(node); node = node.parentElement) {
      if (rowUnder(node)) frame = node;
    }
    return frame;
  };
  const findShell = (editor, editorRoot) => {
    const named = editor?.closest?.(".epitaxy-prompt");
    if (named?.isConnected) return framedInside(named, editorRoot ?? editor) ?? named;
    const start = editorRoot ?? editor;
    const base = start.getBoundingClientRect();
    let shell = start;
    let frame = null;
    let element = start.parentElement;
    for (let depth = 0; element && depth < 12; depth += 1, element = element.parentElement) {
      const rect = element.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) continue;  // обёртки display:contents
      if (rect.width > base.width + 220 || rect.height > base.height + 260) break;
      if (rect.bottom < base.bottom - 40) break;
      shell = element;
      const radius = parseFloat(getComputedStyle(element).borderTopLeftRadius) || 0;
      if (radius >= FRAME_RADIUS && rect.top >= base.top - FRAME_RISE) frame = element;
    }
    return frame ?? shell;
  };
  // Блок ввода целиком: рамка поля, плашка проекта и строка модели. Сворачиваем
  // не его — иначе вместе с полем уезжает строка модели и effort, а она нужна
  // на виду всегда.
  //
  // Донор искал блок по .epitaxy-composer-width. В сборке 1.40609.1 такого
  // класса уже нет: боковые поля задаёт `ps-[var(--chat-gutter…)]` (тот же
  // контейнер, что известен как group/approval-dock). Поэтому селектора два, а
  // третьим — разбор по дереву: предок рамки, у которого под ней есть ещё один
  // видимый и невысокий сосед. Глубина ограничена: выше начинается лента
  // разговора, и схлопнуть её было бы катастрофой.
  const findComposerBlock = (editor, shell) => {
    const named = editor?.closest?.(".epitaxy-composer-width");
    if (named?.isConnected) return named;
    const gutter = editor?.closest?.('[class*="ps-[var(--chat-gutter"]');
    // Тот же класс носит и широкая обёртка вместе с лентой разговора. Свернуть
    // её значило бы спрятать весь разговор, поэтому кандидата проверяем дважды:
    // по содержимому (нет ли внутри ленты) и по росту.
    if (gutter?.isConnected && gutter !== shell &&
        !gutter.querySelector(TRANSCRIPT_SELECTOR) &&
        gutter.getBoundingClientRect().height <= innerHeight * 0.6) return gutter;
    let child = shell ?? editor;
    for (let depth = 0; child?.parentElement && depth < 3; depth += 1, child = child.parentElement) {
      const block = child.parentElement;
      for (let node = child.nextElementSibling; node; node = node.nextElementSibling) {
        const rect = node.getBoundingClientRect();
        if (rect.height >= MODEL_ROW_MIN_HEIGHT && rect.height <= 200) return block;
      }
    }
    return shell ?? null;
  };

  // Строка модели — единственный обычный сосед рамки ввода снизу внутри блока.
  // Ищем не селектором, а обходом соседей: рамкой может оказаться не прямой
  // ребёнок блока, а .sr-only и пустые обёртки надо пропускать по факту, а не по
  // имени класса. Не нашли — возвращаем null, и всё откатывается к прежнему
  // поведению «схлопнуть одну рамку поля».
  const findComposerParts = (block, shell) => {
    if (!block?.isConnected || !shell?.isConnected) return null;
    if (shell === block || !block.contains(shell)) return null;
    let frameChild = shell;
    while (frameChild && frameChild.parentElement !== block) frameChild = frameChild.parentElement;
    if (!frameChild) return null;
    for (let node = frameChild.nextElementSibling; node; node = node.nextElementSibling) {
      if (node.classList.contains("sr-only") || node.getAttribute("aria-hidden") === "true") continue;
      const computed = getComputedStyle(node);
      if (computed.display === "none" || computed.visibility === "hidden") continue;
      // Высотой отсеиваем пустые обёртки: строка модели место занимает, а
      // технический div между рамкой и ней — нет.
      if (node.getBoundingClientRect().height < MODEL_ROW_MIN_HEIGHT) continue;
      return { frameChild, modelRow: node };
    }
    return null;
  };

