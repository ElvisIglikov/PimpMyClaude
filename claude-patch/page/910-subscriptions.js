  // ---- 16. Подписки -------------------------------------------------------
  on(handle, "pointerdown", onPointerDown);
  on(handle, "click", onClick);
  on(handle, "dblclick", onDoubleClick);
  // Дубли у краёв окна (#6743): только нажатие — ни тяги, ни двойного.
  on(superTop, "click", onSuperClick);
  on(superBottom, "click", onSuperClick);
  on(document, "pointermove", onPointerMove, { capture: true });
  on(document, "pointerup", finishDrag, { capture: true });
  on(document, "pointercancel", finishDrag, { capture: true });
  // Рейка ширины правой колонки (раздел 2г) — тем же набором, что и ручка.
  on(rail, "pointerdown", onRailDown);
  on(rail, "dblclick", onRailReset);
  on(document, "pointermove", onRailMove, { capture: true });
  on(document, "pointerup", onRailUp, { capture: true });
  on(document, "pointercancel", onRailUp, { capture: true });
  on(document, "pointerdown", onLeftDown, { capture: true });
  on(document, "dblclick", onLeftReset, { capture: true });
  on(document, "pointermove", onLeftMove, { capture: true });
  on(document, "pointerup", onLeftUp, { capture: true });
  on(document, "pointercancel", onLeftUp, { capture: true });
  on(window, "resize", scheduleLayout);
  on(document, "input", () => { state.pageDirty = true; scheduleLayout(); }, true);
  on(document, "visibilitychange", () => { state.pageDirty = true; scheduleLayout(); });
  on(window, "scroll", onScrolled, true);
  on(window, "myclaude-command", onCommand);
  on(document, "click", onPinBulkClick, true);
  on(document, "change", onPinBulkChange, true);
  // Размер шрифта поля из другого окна (WF107, К2): localStorage общий.
  on(window, "storage", onComposerFontStorage);
  // Вид счёта отправки из другого окна (WF114).
  on(window, "storage", onSendLookStorage);
  // Притемнение попапов из другого окна (WF113, раздел 12и¹); фокус снимает вуаль сразу.
  on(window, "storage", onDimStorage);
  on(window, "storage", onAutoStorage);
  on(window, "focus", onDimFocus);
  on(window, "blur", onDimFocus);
  on(dimNode, "transitionend", onDimFaded);
  // Ввод в поле гасит рамку «ждут твоего слова» (#8282) — на захвате, как 12и.
  on(window, "keydown", onAttnFrameKey, true);
  // Галерея вышла вперёд — окно чата ушло назад: переливание карточки гаснет (WF107, К3).
  on(window, "blur", fileClickIdleAll, { passive: true });
  // Касание окна гасит «done» раздела 12и (а с ним рамку 12и¹). На захвате: Claude
  // глушит часть клавиш и нажатий, и на всплытии они до нас не доходят.
  on(window, "keydown", onWaitTouch, true);
  on(window, "pointerdown", onWaitTouch, true);
  on(window, "focus", onWaitTouch);
  // Финальный ответ (раздел 12м, WF92): касание снимает мигание «нужен Элвис»,
  // жест в ленте (колесо, клавиша, нажатие; #9319) — «читает», прокрутки не будет.
  on(window, "keydown", onAttnTouch, true);
  on(window, "pointerdown", onAttnTouch, true);
  on(window, "pointerdown", onAttnFeedPress, true);
  on(window, "wheel", onAttnWheel, { capture: true, passive: true });
  on(window, "keydown", onAttnKey, true);
  // Слова-действия «Скажи — и сделаю» (раздел 12р, #7755): нажатие — на
  // захвате документа, клавиша в поле гасит отсчёт.
  on(document, "pointerdown", onSayPress, true);
  on(document, "mousedown", onSayPress, true);
  on(document, "click", onSayClick, true);
  on(window, "keydown", onSayKey, true);
  // Нажималки (раздел 12с): так же — нажатие на захвате, клавиша в поле гасит отсчёт.
  on(document, "pointerdown", onNazhPress, true);
  on(document, "mousedown", onNazhPress, true);
  on(document, "click", onModeInteraction, true);
  on(document, "input", onModeInteraction, true);
  on(window, "pointerdown", onModeInteraction, true);
  on(window, "keydown", onModeInteraction, true);
  // Bypass во всех чатах (раздел 12с¹): ручной выбор режима — чат человека.
  on(window, "pointerdown", onBypassInput, true);
  on(window, "keydown", onBypassInput, true);
  on(document, "click", onNazhClick, true);
  on(document, "pointerdown", onRunPress, true);
  on(document, "mousedown", onRunPress, true);
  on(document, "click", onRunClick, true);
  on(window, "keydown", onNazhKey, true);
  // Свёртки <details> (раздел 12ф): нажатие и клавиши на захвате.
  on(document, "click", onFoldClick, true);
  on(window, "keydown", onFoldKey, true);
  // «Прочитано» (раздел 12х): дорожка, свёрнутый блок и «непрочитанные N»; колесо, нажатие мыши и
  // клавиша мимо своих узлов снимают идущий переход.
  on(document, "click", onReadClick, true);
  on(document, "mousedown", onReadPress, true);
  on(window, "keydown", onReadKey, true);
  on(document, "pointerover", onReadHover, true);
  on(document, "pointerout", onReadHover, true);
  on(document, "focusin", onReadHover, true);
  on(document, "focusout", onReadHover, true);
  on(window, "wheel", readSeekStop, { capture: true, passive: true });
  on(window, "storage", event => { if (event.key === READ_KEY || event.key === null) { readState.chat = undefined; try { readTick(); } catch {} } });
  // «Просмотрено» у карточек файлов (раздел 12м³): галочка — раньше слушателей карточки (фото 12л,
  // файл 12д), клавиши — на захвате окна; отметку из другого окна того же чата приносит storage.
  on(document, "click", onSeenClick, true);
  on(document, "mousedown", onSeenPress, true);
  on(window, "keydown", onSeenKey, true);
  on(window, "storage", event => { if (event.key === SEEN_KEY || event.key === null) { seenState.chat = undefined; try { seenTick(); } catch {} } });
  // Главы чата (раздел 12х²): курсор над дорожкой и меню, нажатие мимо, галочка и двойное нажатие
  // (раньше слушателей Claude — переименование не запускается), правая кнопка — настройка вида, Esc
  // и клавиши галочки — на захвате окна; отметки и вид из другого окна приносит storage.
  // На чужой странице (не Claude) подписок нет.
  if (themable) {
    on(document, "mouseover", onChOver, true);
    on(document, "mouseout", onChOut, true);
    on(document, "mousedown", onChPress, true);
    on(document, "click", onChClick, true);
    on(document, "dblclick", onChDouble, true);
    on(document, "contextmenu", onChMenu, true);
    on(document, "input", onChInput, true);
    on(document, "focusin", onChFocus, true);
    on(document, "focusout", onChFocus, true);
    on(document, "scroll", onChScroll, { capture: true, passive: true });
    on(window, "keydown", onChKey, true);
    on(window, "resize", () => { if (chState.open) chPlace(); });
    on(window, "resize", () => { try { chCenterTick(); } catch {} });
    on(window, "storage", event => {
      if (event.key === CH_READ_KEY || event.key === CH_STAR_KEY || event.key === null) { chState.chat = undefined; try { chTick(); } catch {} }
      if (event.key === CH_LOOK_KEY || event.key === null) { try { chLookApply(chLookRead()); if (chState.open) chPlace(); } catch {} }
    });
  }
  // Штамп тишины и отмена отсчёта клавишей в своём поле (раздел 12к, WF85).
  on(window, "keydown", onAutoInput, true);
  on(window, "pointerdown", onAutoInput, true);
  // Просмотр фото (раздел 12л, WF87): нажатие по фото ленты — на захвате
  // документа, раньше корня React; Esc и стрелки — на захвате окна.
  on(document, "pointerdown", onPhotoPress, true);
  on(document, "mousedown", onPhotoPress, true);
  on(document, "click", onPhotoPress, true);
  on(window, "keydown", onPhotoKey, true);
  on(window, "keyup", onPhotoKey, true);
  on(window, "wheel", onPhotoClaudeWheel, { capture: true, passive: false });
  on(document, "pointermove", onPhotoHover, true);
  on(document, "pointerout", onPhotoHover, true);
  // Перетаскивание вложений (раздел 12м², #7685): всё на захвате документа.
  if (themable) {
    on(document, "pointerover", onDragHover, true);
    on(document, "pointerdown", onDragPress, true);
    on(document, "pointermove", onDragMove, true);
    on(document, "pointerup", onDragRelease, true);
    on(document, "pointercancel", onDragRelease, true);
    on(document, "dragstart", onDragOut, true);
    on(document, "dragend", onDragDone, true);
    on(document, "dragover", onDragOverIn, true);
    on(document, "drop", onDropIn, true);
  }
  // Вложения поля ввода (раздел 12) ловятся НА ЗАХВАТЕ: Claude зовёт
  // preventDefault, и на всплытии события до нас доходят не всегда. Сама полка
  // лежит глобалом окна и dispose переживает — снимаются только подписки.
  on(document, "paste", onCashoutPaste, true);
  on(document, "drop", onCashoutDrop, true);
  on(document, "change", onCashoutPick, true);
  // ⌘V из любого места окна (раздел 12, WF64). На чужой странице — артефакт,
  // логин, встроенный браузер — этих подписок нет вовсе: поля ввода там не
  // бывает, и перехватывать вставку не для чего.
  //
  // Порядок важен: пересылка стоит ПОСЛЕ onCashoutPaste, и к её ходу свёрнутое
  // поле уже развёрнуто (#5870) — иначе вложение приехало бы в схлопнутую рамку
  // и Элвис снова решил бы, что скриншот «не вставился».
  if (themable) {
    // Отсрочка отправки (раздел 12у) — ПЕРВОЙ на захвате document: отложенный
    // Enter не должен дойти до onPasteKey (вложения, автосвёртка) и до Claude.
    on(document, "submit", event => {
      if (!cashoutBox()?.contains(event.target) && !event.target?.contains?.(state.editor)) return;
      if (shotBlocked()) { event.preventDefault(); event.stopImmediatePropagation(); }
    }, true);
    on(document, "keydown", onSendDelayKey, true);
    on(document, "input", onSendDelayInput, true);
    for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) on(document, type, onSendDelayPress, true);
    for (const type of ["click", "submit", "reset"]) {
      on(document, type, onAttachmentBoundary, true);
    }
    const routeChanged = () => {
      shotSync();
      if (attachmentContext && attachmentRoute() !== attachmentContext.route) {
        invalidateAttachments();
        scheduleLayout();
      }
    };
    on(window, "popstate", routeChanged);
    on(window, "hashchange", routeChanged);
    // push/replace не посылают popstate. Только наблюдение: оригинальные
    // аргументы, this, результат и исключение; dispose снимает только своё.
    for (const name of ["pushState", "replaceState"]) {
      const previous = history[name];
      const wrapped = function (...args) {
        const result = previous.apply(this, args);
        routeChanged();
        return result;
      };
      history[name] = wrapped;
      track(() => { if (history[name] === wrapped) history[name] = previous; });
    }
    on(document, "keydown", onPasteKey, true);
    on(document, "paste", onPasteAnywhere, true);
    // Бросок картинки на блок ввода — с номером (раздел 12, #7532): после полки
    // «Обкэшить» (оригинал она запомнит) и после своего броска (12м²).
    on(document, "drop", onShotDrop, true);
    on(document, "change", onShotPick, true);
    // «Открыть в Chrome» (раздел 12г, WF67): правый клик по карточке файла
    // запоминает путь и ждёт меню Claude; само событие не отменяется.
    on(document, "contextmenu", onOpenChromeMenu, true);
    // HTML-файлы — в Chrome (раздел 12д, #6618): клик по карточке глушим на захвате.
    on(document, "click", onHtmlChromeClick, true);
    // Ссылки на файлы и «на картинке» в тексте ответа (раздел 12д¹, #7860).
    on(document, "click", onMentionClick, true);
    on(document, "pointerdown", onMentionPress, true);
    on(document, "mousedown", onMentionPress, true);
    // Наши ссылки (раздел 12д², WF288): отчёты VkusStatBot — в панель слева, задачи Trelvis — через Пимп.
    on(document, "click", onOurLinkClick, true);
    on(document, "pointerdown", onOurLinkPress, true);
    on(document, "mousedown", onOurLinkPress, true);
    // Внешние ссылки ленты (раздел 12д³, #11118) — в браузер системы; после 12д²: наши классы он забирает первым.
    on(document, "click", onExternalLinkClick, true);
    on(document, "pointerdown", onExternalLinkPress, true);
    on(document, "mousedown", onExternalLinkPress, true);
    // Панель лимитов (раздел 12ж, #6738): клик по кружку контекста — повод
    // подождать панель; событие не отменяется, панель открывает Claude.
    on(document, "click", onUsageRing, true);
    // Плашка проекта (#7334): поверх неё лежит ⋮ (правило в layoutCss), поэтому
    // её собственное меню открывается правым кликом по ней. Правый клик по кнопке
    // боковой панели больше не глушится (К19 снят вместе с меню Пимпа на ⌘B, WF220).
    const onOriginMenu = event => {
      const bar = event.target instanceof Element ? event.target.closest(".epitaxy-titlebar") : null;
      const origin = bar?.querySelector('button:has(> [data-testid="epitaxy-origin-label"])');
      if (!origin) return;
      const rect = origin.getBoundingClientRect();
      if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) return;
      event.preventDefault();
      event.stopPropagation();
      origin.click();
    };
    on(document, "contextmenu", onOriginMenu, true);
    // Родная кнопка диктовки (#9681, раздел 12з): в режиме Диктатора — его, правой кнопкой — меню приложения.
    for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) on(document, type, micNativeCatch, true);
    on(document, "contextmenu", micNativeMenu, true);
  }
  // Escape не должен останавливать выполнение (слово Элвиса 03.09 14:00: F1/F2 рядом,
  // «постоянно боюсь нажать Escape»). Глотаем Escape на захвате, но только когда на
  // странице нет открытого диалога/меню/списка — там Escape нужен, чтобы их закрыть.
  // Открытый — значит ВИДИМЫЙ узел Claude (CLAUDE_POPUP_SELECTOR и палитра cmdk, rect > 0): голый
  // селектор ловил закрытую панель глав с role="dialog" и постоянные [data-state="open"] — и Esc
  // снова останавливал агента (ревизия WF247, P1). Свои открытые слои (фото, главы, PMP, «Запустить?»)
  // ловят Esc своими обработчиками раньше этого.
  const ESC_OVERLAY_SELECTOR = `${CLAUDE_POPUP_SELECTOR},[cmdk-root]`;
  const onKeyDown = (event) => {
    if (onPinBulkKey(event)) return;
    if (onRunConfirmKey(event)) return;
    if (onComposerFontKey(event)) return;
    // Esc и Tab открытой панели оркестрации (раздел 12п³, WF213).
    if (onPmpPanelKey(event)) return;
    // Esc во время счёта отправки (раздел 12у) — отмена. Глотаем всегда, кроме
    // видимого меню подсказок: `[data-state="open"]` (до WF248 — в ESC_OVERLAY_SELECTOR)
    // бывает и на постоянных узлах, а Esc мимо счёта остановил бы идущий ход
    // (проверка WF105).
    if (onSendDelayEsc(event)) {
      if (!sendDelayMenuOpen(state.editor)) { event.preventDefault(); event.stopImmediatePropagation(); }
      return;
    }
    if (event.key !== "Escape" || event.defaultPrevented) return;
    if (overlayOpen(ESC_OVERLAY_SELECTOR)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    state.escapesBlocked = (state.escapesBlocked || 0) + 1;
  };
  on(window, "keydown", onKeyDown, { capture: true });

  const observer = new MutationObserver(onMutated);
  observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true });
  track(() => observer.disconnect());
  // Наблюдатель за временем — отдельный: у него свои цель (лента, а не весь
  // документ), свой набор мутаций (ещё и characterData) и свой троттлинг.
  watchTime();

  // Тик вынесен в функцию: после отказа от наблюдения интервал снимают, а при
  // возврате заводят заново — тем же телом.
  // Сторож дёрганья (#5978, слово Элвиса 13.09: «вверх-вниз, вверх-вниз», дёрганье
  // вернулось). Болезнь неуловимая: на двенадцати вложениях и длинном
  // черновике в двух окнах подряд низ окна стоит намертво, а у Элвиса скачет.
  // Поэтому не чиним вслепую, а КОПИМ факты: последние смены высоты блока ввода
  // с метками времени. По ним будет видно, кто её меняет и как часто —
  // `status().jumps`. Сам сторож ничего не меняет и ничего не рисует.
  const JUMP_LOG_MAX = 24;
  const JUMP_MIN = 2;
  const jumpLog = [];
  let jumpLast = null;
  const noteJump = () => {
    const block = state.composerBlock?.isConnected ? state.composerBlock
      : (state.shell?.isConnected ? state.shell : null);
    if (!block) { jumpLast = null; return; }
    const height = Math.round(block.getBoundingClientRect().height);
    if (jumpLast === null) { jumpLast = height; return; }
    if (Math.abs(height - jumpLast) < JUMP_MIN) return;
    jumpLog.push({ at: Date.now(), from: jumpLast, to: height, pills: cashoutPills() });
    if (jumpLog.length > JUMP_LOG_MAX) jumpLog.shift();
    jumpLast = height;
  };

  // Самовосстановление своих узлов (#6766, слово Элвиса 21.09 00:35: «в окне
  // ChinaAI поля ввода нету и элементов управления… разобраться, чтобы в будущем
  // так не происходило»). Живой случай: Claude пересоздал содержимое body
  // попапа, у body остался один ребёнок из шести — наши узлы уехали вместе со
  // старым деревом. Страница этого не замечала (status().handleVisible говорил
  // «есть», хотя узла в документе не было), и возвращались они только повторным
  // запуском инжекта.
  //
  // Лечение дешёвое и без новых таймеров: проверка isConnected на уже
  // существующем стороже. Узел возвращается ТОТ ЖЕ САМЫЙ — с детьми, стилями и
  // подписками, — поэтому «поставить заново» это ровно тот же appendChild, что
  // на инжекте, и повторять его безопасно сколько угодно раз.
  const ownNodes = [dimNode, attnFrameNode, progressBar, progressTail, progressTip, handle, rail, superTop, superBottom, micNode, galleryNode, cornerNode, mainDrag,
    dockNodes.button, dockNodes.place, dockNodes.rail, dockNodes.drag];
  const restoreOwnNodes = () => {
    const host = document.body ?? document.documentElement;
    if (!host) return false;
    let back = 0;
    for (const node of ownNodes) {
      if (node.isConnected) continue;
      host.appendChild(node);
      back += 1;
    }
    // Карточка живёт внутри коробки-подсказки, а не в body: её возвращаем туда же.
    if (!progressCard.isConnected && progressTip.isConnected) { progressTip.appendChild(progressCard); back += 1; }
    if (!back) return false;
    state.restored += back;
    return true;
  };

  const heartbeatTick = () => {
    if (!state.alive) return;
    try { noteJump(); } catch {}
    // Узлы Пимпа пропали из body — вернуть и пересчитать раскладку, не дожидаясь
    // мутации: та могла и не прийти, окно осталось бы без поля ввода.
    let restored = false;
    try { restored = restoreOwnNodes(); } catch {}
    // Панель лимитов (раздел 12ж): один querySelector — страховка вместо
    // постоянного наблюдателя. Заодно главное окно обновляет имя аккаунта.
    try { usageTick(); } catch {}
    try { usageAccountSave(); } catch {}
    // Кружок контекста (раздел 12з², #10317): смена чата и когда спросить число у приложения.
    try { ctxRingTick(now()); } catch {}
    // «Ждёт тебя» (раздел 12и): сам решает, пора ли смотреть.
    try { waitTick(now()); } catch {}
    // Живой фон при «уменьшить движение» (auroraCalmSync, у paintLook): узлы подложки на месте.
    try { auroraCalmSync(); } catch {}
    // Рамка «ждут твоего слова» и вуаль попапа (раздел 12и¹, #8282, #8256): после 12и — берёт его вывод.
    try { attnFrameTick(now()); } catch {}
    // «💬 Новый чат» сам (раздел 12к, WF85): взвод, оценка и отсчёт.
    try { autoTick(now()); } catch {}
    // Повтор при ошибке сервера (раздел 12е², #6936): по настенным часам — час общий для окон и перезагрузок.
    try { autoRetryTick(Date.now()); } catch {}
    // Финальный ответ (раздел 12м, WF92): прокрутка вниз и мигание «нужен Элвис».
    // После autoTick: «Новый чат» судит ленту раньше, чем мы её тронем.
    try { attnTick(now()); } catch {}
    // Красное время (раздел 12о, #7750): после 12и — берёт его waitState.kind.
    try { signalTick(now()); } catch {}
    // Ленту в покое не перечитываем каждые 500 мс. Мутации, смена чата и
    // начало/конец ответа будят её; 5 с — страховка для изменений только в
    // React props/геометрии. Активные отсчёты и команды продолжают тикать.
    const pageKey = `${location.href}|${windowTitle()}`;
    const working = pageWorking();
    const pageDirty = state.pageDirty || restored || pageKey !== state.pageKey || working !== state.pageWorking
      || now() - state.pageScanAt >= 5000;
    if (pageDirty) {
      state.pageDirty = false;
      state.pageScanAt = now();
      state.pageKey = pageKey;
      state.pageWorking = working;
    }
    if (pageDirty || sayState.armed) { try { sayTick(now()); } catch {} }
    if (pageDirty || nazhState.armed) { try { nazhTick(now()); } catch {} }
    if (pageDirty) { try { foldTick(); } catch {} }
    // Пункты «Ждёт тебя» — ссылкой на файл (раздел 12с³, #10617): после свёрток — их головы уже стоят.
    if (pageDirty) { try { waitFilePaint(); } catch {} }
    // «Прочитано» (раздел 12х): после свёрток — их заголовки в строке уже стоят.
    if (pageDirty) { try { readTick(); } catch {} }
    // Фоновые задачи (раздел 12х⁴): после «Прочитано» — его тик уже прочёл список ходов; подписи времени — каждый тик.
    try { tasksTick(pageDirty); } catch {}
    // «Просмотрено» у карточек файлов (раздел 12м³): тем же проходом, своего опроса нет.
    if (pageDirty) { try { seenTick(); } catch {} }
    // Превью HEIC во вложениях (раздел 12м⁴): тем же проходом, своего опроса нет.
    if (pageDirty) { try { heicTick(); } catch {} }
    // Ролики и картинки чата с диска (раздел 12п⁵, #10699): тем же проходом, своего опроса нет.
    if (pageDirty) { try { mediaTick(); } catch {} }
    // Главы чата (раздел 12х²): отметки «прочитано» и галочки — тем же проходом, своего опроса нет.
    if (pageDirty) { try { chOkSync(); chHostTick(); chTick(); } catch {} }
    // Полоски глав посередине между краем и текстом (#10848): тем же проходом и на смене размера окна.
    if (pageDirty) { try { chCenterTick(); } catch {} }
    try { modeGuardTick(now()); } catch { modeGuardDrop(); }
    // Bypass во всех чатах (раздел 12с¹, #9060): после сторожа режима — уступает ему.
    try { bypassTick(now()); } catch { bypassDrop(); }
    if (pageDirty || runState.going.size) { try { runTick(now()); } catch {} }
    // Лента могла смениться целиком (React пересобрал разговор): наблюдатель за
    // временем остался бы висеть на выброшенном узле и оглох — мутаций оттуда
    // больше не придёт, а значит и переехать сам он уже не сможет.
    if (state.timeTarget && !state.timeTarget.isConnected && watchTime()) scheduleShortTime();
    // Узлы вернулись — раскладку гоняем сразу, а не через кадр: без неё ручка
    // осталась бы стоять там, где её застало исчезновение (#6766).
    if (restored) { try { layout(); } catch {} return; }
    if (state.scheduled) {
      // Запланированный кадр так и не пришёл (окно спрятано или перекрыто, и
      // macOS остановил requestAnimationFrame) — доводим руками.
      if (now() - state.layoutAt >= LAYOUT_MIN_GAP) { cancelPendingLayout(); layout(); }
      return;
    }
    if (pageDirty) scheduleLayout();
  };
  let heartbeat = setInterval(heartbeatTick, HEARTBEAT_MS);
  track(() => clearInterval(heartbeat));

  // Инжект попадает и в оболочку file://…/main_window, и на страницы логина —
  // там поля ввода нет и не будет. Через минуту ожидания перестаём смотреть за
  // документом, если страница явно не claude.ai и на ней нет ни одной приметы
  // интерфейса Claude (последняя проверка — сверх плана: окна «Open in new
  // window» живут на about:blank, и терять в них полоску из-за одного лишь URL
  // было бы обиднее, чем лишний наблюдатель на пустой странице).
  // Примета интерфейса Claude: по ней страница признаётся своей — и когда мы от
  // неё отказываемся, и когда возвращаемся.
  const CLAUDE_MARK_SELECTOR = ".ProseMirror,.epitaxy-prompt,.epitaxy-titlebar,.epitaxy-composer-width";
  let reviveTimer = 0;
  const stopWatching = () => {
    state.watching = false;
    observer.disconnect();
    clearInterval(heartbeat);
    cancelPendingLayout();
    // Страница признана чужой — строк действий с временем на ней нет и не
    // будет, так что и второй наблюдатель уходит вместе с первым.
    cancelShortTime();
    stopTimeWatch();
    clearInterval(progressState.pulse);
    progressState.pulse = 0;
    // Отказ не окончательный. Окно «Open in new window» рождается пустым
    // about:blank, а чат в него въезжает позже; тяжёлый чат в фоновом окне
    // не успевал за GIVE_UP_MS, и страница оставалась мёртвой навсегда — без
    // ручки и без полоски прогресса, хотя поле ввода в ней уже стояло (окно
    // «Bro Flow продолжение», 05.09). Наблюдателей обратно не заводим: остаётся
    // самая дешёвая сторожевая проверка — один querySelector раз в REVIVE_MS.
    if (!reviveTimer) reviveTimer = setInterval(() => {
      if (!state.alive) return;
      if (!document.querySelector(CLAUDE_MARK_SELECTOR)) return;
      resumeWatching();
    }, REVIVE_MS);
  };
  // Разметка Claude всё-таки приехала: поднимаем ровно то, что снял stopWatching.
  const resumeWatching = () => {
    if (reviveTimer) { clearInterval(reviveTimer); reviveTimer = 0; }
    if (!state.alive || state.watching) return;
    state.watching = true;
    observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true });
    heartbeat = setInterval(heartbeatTick, HEARTBEAT_MS);
    if (!progressState.pulse) {
      progressState.pulse = setInterval(() => { try { progressRefresh(); } catch {} }, PROGRESS_IDLE_MS);
    }
    watchTime();
    scheduleShortTime();
    scheduleLayout();
    try { progressSchedule(); } catch {}
  };
  track(() => { if (reviveTimer) { clearInterval(reviveTimer); reviveTimer = 0; } });
  state.giveUpTimer = setTimeout(() => {
    state.giveUpTimer = 0;
    if (state.editorFound || !state.alive) return;
    if (location.href.startsWith("https://claude.ai")) return;
    if (document.querySelector(CLAUDE_MARK_SELECTOR)) return;
    stopWatching();
  }, GIVE_UP_MS);
  track(() => { if (state.giveUpTimer) { clearTimeout(state.giveUpTimer); state.giveUpTimer = 0; } });
  // Сторож дёрганья (#5978): последние смены высоты блока ввода.
  statusPart("jumps", () => jumpLog.slice());
  HATCH && Object.assign(HATCH, { heartbeatTick });

