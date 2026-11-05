  // ---- 9. Раскладка -------------------------------------------------------
  // Свёрнутая рамка занимает нулевую высоту, поэтому её геометрия для
  // расстановки уже не годится: полоска садится над строкой модели — она
  // осталась на виду и держит низ блока. Строки нет — полоска возвращается на
  // нижний край окна.
  const placeCollapsedHandle = () => {
    // Место общее на все три полоски (railSeat, #6891): и ось, и ширина у
    // свёрнутой полоски те же, что у открытой и у дублей у краёв окна. Полной
    // шириной она наезжала бы зоной захвата на надпись «Opus 5 · Max» и
    // кругляшок рядом с ней, поэтому узкая — как у донора.
    const spot = railSeat();
    const row = state.modelRow?.isConnected ? state.modelRow.getBoundingClientRect() : null;
    handle.style.display = "flex";
    handle.style.left = `${spot.left}px`;
    handle.style.width = `${spot.width}px`;
    // Линия садится ровно на верхнюю кромку строки модели — так же, как на
    // открытом поле она садится на кромку рамки: зона захвата стоит верхом на
    // кромке, то есть выше неё ровно половина. Выше (на целую высоту зоны, как
    // было до 12.09) полоска висела над строкой модели поверх кнопки Claude
    // «вниз к последнему сообщению» и казалась оторванной от поля (#5866,
    // #5867). Сливаться с полосой прогресса ей больше нечем: на свёрнутом поле
    // та переехала на низ блока ввода (progressApply).
    // Кнопку Claude «вниз к последнему сообщению» зона захвата не ест: где та
    // прижата к строке модели, полоска встаёт под её низом. Ищем кнопку только
    // в свёрнутом виде и только по её собственной примете.
    let below = null;
    try {
      const down = document.querySelector('[aria-label="Scroll to bottom"],[aria-label="Прокрутить вниз"]');
      const box = down?.isConnected ? down.getBoundingClientRect() : null;
      if (box && box.height > 0) below = box.bottom;
    } catch {}
    const seat = row && row.height > 0
      ? row.top - HANDLE_HEIGHT / 2
      : innerHeight - HANDLE_HEIGHT - 4;
    handle.style.top = `${Math.round(below != null ? Math.max(seat, below) : seat)}px`;
    // Хит-тест нужен и здесь: меню модели и effort раскрываются вверх ровно над
    // этим местом. Но одного хит-теста мало: свёрнутая полоска сидит верхом на
    // кромке строки модели, то есть половиной уже вне блока ввода, и любой
    // градиент расшифровки с position:absolute спрятал бы её навсегда — а
    // вернуть поле мышью больше нечем. Поэтому прячем только когда меню
    // действительно открыто.
    state.handleCovered = !state.dragging && overlayOpen() && popupCoversHandle();
    if (state.handleCovered) handle.style.display = "none";
  };

  // Есть ли у поля в этом окне ступени: редактор нашёлся (или поле уже
  // свёрнуто) и вид узкий. В широком виде ступеней нет вовсе (syncWide), и
  // нажималка свернула бы поле, которое нечем вернуть. Поле спрашиваем САМИ, а
  // не ждём, пока его найдёт проход раскладки: полоски ставятся до всех ранних
  // выходов, и на первом же проходе после установки state.editor ещё пуст — без
  // своего вопроса они появлялись бы только со второго прохода. findEditor
  // держит свой кэш, так что вопрос дешёвый.
  const stagesLive = () => state.alive && state.watching && !wideState.on &&
    ((state.editor?.isConnected ? state.editor : findEditor()) != null || state.stage === STAGE_COLLAPSED);

  // Дубли полоски у краёв окна (#6743). Место берут у railSeat — то же, что у
  // полоски поля: ось, ширина и высота зоны у всех трёх одни (#6891).
  const placeSuperRails = () => {
    const live = stagesLive();
    const seat = live ? railSeat() : null;
    // Свёрнутое поле — режим чтения: основная полоска садится на нижнюю кромку
    // окна, ровно туда же, где стоит нижний дубль, и линии шли две в точку
    // друг от друга. Слово Элвиса 21.09 (#6892): «они не должны конфликтовать…
    // одна полоска должна по итогу быть». Уступает дубль: за основную ещё и
    // тянут, и она заметнее.
    const collapsed = state.stage === STAGE_COLLAPSED;
    // Поле развёрнуто до верха окна (#11693) — ручка поля легла на место верхнего дубля: уступает и он.
    let atTop = false;
    if (live && state.stage === STAGE_STRETCHED && state.shell?.isConnected) {
      try { atTop = state.shell.getBoundingClientRect().top - HANDLE_HEIGHT / 2 < HANDLE_HEIGHT; } catch {}
    }
    const seats = [[superTop, 0, atTop], [superBottom, Math.round(innerHeight - HANDLE_HEIGHT), collapsed]];
    for (const [node, top, yields] of seats) {
      if (!live || yields) {
        if (node.style.getPropertyValue("display") !== "none") node.style.setProperty("display", "none");
        continue;
      }
      node.style.setProperty("display", "flex");
      node.style.setProperty("left", `${seat.left}px`);
      node.style.setProperty("width", `${seat.width}px`);
      node.style.setProperty("top", `${top}px`);
    }
  };

  // Карточка разрешения — слоем над лентой (#6590). Слово Элвиса: «вот эти вот Allow,
  // которые окошки появляются... сдвигают вверх чат весь. И он скачет вверх-вниз, как на
  // лошади. Пусть появляются так же, просто сверху, над чатом, чтоб чат на месте оставался».
  // Карточка Claude (.epitaxy-approval-card) встаёт в доке над полем и отнимает у ленты свою
  // высоту: лента у низа догоняет низ (вверх), а уходя карточка отдаёт место, и лента падает
  // обратно (вниз). В узком виде дока помечена заранее, и CSS кладёт карточку слоем у верхней
  // кромки доки тем же кадром, что её вставка: место ленты не меняется ни на кадр. Сама
  // карточка, её кнопки и клавиши — Claude-овские. Переменные доки: место над ней до верха
  // ленты (потолок карточки) и края поля ввода (её ширина). Метки нет — карточка встаёт, как
  // у Claude: широкий вид (дока — своя колонка, ленту она не двигает), ленты над полем меньше
  // CARD_FLOAT_MIN (поле растянуто), слой не виден (его закрыло или обрезало чужое — тогда
  // до перезагрузки страницы: карточка в потоке лучше невидимой).
  const CARD_SELECTOR = ".epitaxy-approval-card";
  const CARD_FLOAT_ATTRIBUTE = "data-myclaude-card-float";
  const CARD_SOLID_ATTRIBUTE = "data-myclaude-card-solid";
  const CARD_FLOAT_MIN = 160;
  const CARD_FLOAT_GAP = 6;
  const CARD_VARS = ["--myclaude-card-room", "--myclaude-card-start", "--myclaude-card-end"];
  const cardFloat = { dock: null, broken: false, cards: 0 };
  const clearCardFloat = () => {
    const dock = cardFloat.dock;
    cardFloat.dock = null;
    if (!dock) return;
    try {
      dock.removeAttribute(CARD_FLOAT_ATTRIBUTE);
      for (const name of CARD_VARS) dock.style.removeProperty(name);
      for (const card of dock.querySelectorAll(`[${CARD_SOLID_ATTRIBUTE}]`)) card.removeAttribute(CARD_SOLID_ATTRIBUTE);
    } catch {}
  };
  track(clearCardFloat);
  // Слой виден: в его середине — он сам или наш узел поверх окна, а не лента под ним.
  const cardShown = (card, panel, box) => {
    if (box.top < 0 || box.bottom > innerHeight) return false;
    let hit = null;
    try { hit = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2); } catch { return true; }
    return !hit || card.contains(hit) || !panel.contains(hit);
  };
  const placeCardFloat = (panel, wide) => {
    const dock = wide || cardFloat.broken || !panel?.isConnected ? null : sideDock(panel);
    let body = null;
    try { body = dock ? panel.querySelector(".epitaxy-chat-panel-body") : null; } catch {}
    if (cardFloat.dock && cardFloat.dock !== dock) clearCardFloat();
    if (!dock?.isConnected || !body?.isConnected) { clearCardFloat(); return; }
    const own = dock.getBoundingClientRect();
    const room = Math.round(own.top - body.getBoundingClientRect().top - CARD_FLOAT_GAP);
    if (room < CARD_FLOAT_MIN) { clearCardFloat(); return; }
    let card = null;
    try { card = dock.querySelector(CARD_SELECTOR); } catch {}
    // Края поля — от той коробки, от которой карточку ставит CSS: ближайший позиционированный
    // предок (у Claude — сама дока; пока карточки нет, считаем от доки).
    const base = card?.offsetParent?.getBoundingClientRect ? card.offsetParent.getBoundingClientRect() : own;
    let field = null;
    try { field = dock.querySelector(".epitaxy-prompt")?.getBoundingClientRect() ?? null; } catch {}
    const vars = [`${room}px`, field ? `${Math.round(field.left - base.left)}px` : null, field ? `${Math.round(base.right - field.right)}px` : null];
    CARD_VARS.forEach((name, index) => {
      const value = vars[index];
      if (value == null) dock.style.removeProperty(name);
      else if (dock.style.getPropertyValue(name) !== value) dock.style.setProperty(name, value);
    });
    if (!dock.hasAttribute(CARD_FLOAT_ATTRIBUTE)) dock.setAttribute(CARD_FLOAT_ATTRIBUTE, "");
    cardFloat.dock = dock;
    if (!card?.isConnected) return;
    const box = card.getBoundingClientRect();
    if (!(box.height > 0)) return;
    if (!cardShown(card, panel, box)) { cardFloat.broken = true; clearCardFloat(); return; }
    if (card.__myclaudeCard !== true) { card.__myclaudeCard = true; cardFloat.cards += 1; }
    // Прозрачная карточка слоем легла бы текстом на текст ленты — даём ей фон доки.
    let clear = false;
    try { clear = /^(?:transparent|rgba\([^)]*,\s*0\))$/.test(getComputedStyle(card).backgroundColor); } catch {}
    if (clear && !card.hasAttribute(CARD_SOLID_ATTRIBUTE)) card.setAttribute(CARD_SOLID_ATTRIBUTE, "");
  };
  lateRules.push(`[${CARD_FLOAT_ATTRIBUTE}] ${CARD_SELECTOR}{position:absolute !important;inset:auto var(--myclaude-card-end,0px) calc(100% + ${CARD_FLOAT_GAP}px) var(--myclaude-card-start,0px) !important;width:auto !important;margin:0 !important;max-height:var(--myclaude-card-room,50vh) !important;overflow-y:auto !important;z-index:40 !important;box-shadow:0 8px 28px rgba(0,0,0,.32) !important}`,
    `[${CARD_FLOAT_ATTRIBUTE}] ${CARD_SELECTOR}[${CARD_SOLID_ATTRIBUTE}]{background-color:var(--epitaxy-transcript-surface,var(--cds-surface-1)) !important}`);

  const noteEditorFound = () => {
    if (state.editorFound) return;
    state.editorFound = true;
    if (state.giveUpTimer) { clearTimeout(state.giveUpTimer); state.giveUpTimer = 0; }
  };

  const layout = () => {
    // Проход мог прийти в обход плана (heartbeat, команда, старт): снимаем всё
    // запланированное, иначе кадр и таймер сработают ещё раз впустую, а id
    // старого таймера потеряется и снять его будет уже нечем.
    cancelPendingLayout();
    state.scheduled = false;
    state.layoutAt = now();
    state.layoutRuns += 1;
    // Полоса прогресса (раздел 2б) переезжает вместе с полем. Зовём её дважды:
    // здесь — чтобы её достали и те проходы, что кончатся ранним выходом
    // (свёрнутое поле, потерянный редактор), и в самом конце — чтобы во время
    // тяги она не отставала на проход от только что изменённой высоты.
    placeProgress();
    // Дубли полоски стоят по окну, а не по полю: им всё равно, каким путём
    // кончится этот проход, — поэтому ставим их здесь, до всех ранних выходов.
    placeSuperRails();
    // Микрофон у кружка (#6907) — там же и по той же причине: он привязан к
    // кружку, а не к полю. Раздел 12з объявлен ниже, но зовётся он только из
    // живого прохода, а тот идёт уже после установки.
    try { placeMic(); micPaint(); } catch {}
    // Кружок — только контекст этого чата (раздел 12з², #10317): тоже по кружку, до ранних выходов.
    try { ctxRingPlace(); } catch {}
    // «▦ Галерея» (раздел 12п) — после микрофона: в свёрнутом поле встаёт левее него.
    try { placeGallery(); } catch {}
    // Enter — над кружком токенов (WF183).
    try { alignSendToRing(); } catch {}
    try { placeModeSwitch(); } catch {}
    restoreLeft();
    // Панель материалов слева (раздел 12п⁴) — после ширины боковой панели: кнопка в её строке, место правее неё.
    try { placeDock(); } catch {}
    // Чип папки у закреплённых чатов (раздел 2е) — по списку слева, а не по полю,
    // поэтому тоже до ранних выходов. Осечка волокна не должна ронять раскладку.
    try { markPinnedFolders(); pinBulkMount(); } catch {}
    // Угол «Проект · чат» (раздел 2ж, #7911) — во всех окнах, при любом поле.
    try { placeCorner(); } catch {}
    // Нижняя строка поля ввода (раздел 12з¹, #7206) — тоже до ранних выходов:
    // свёрнутое поле строку прячет, но метки ей нужны к развороту.
    try { markChin(); } catch {}
    // Кнопка «💬 Новый чат» под блоком передачи (раздел 12к, #7246).
    try { markContinue(); } catch {}
    const editor = findEditor();
    // Страховка от мигания: даже если редактор потерялся, свёрнутое состояние не
    // сбрасываем, пока жив хоть один схлопнутый узел.
    const keepCollapsed = !editor && state.stage === STAGE_COLLAPSED &&
      state.collapsedNodes.some(node => node.isConnected);
    if (keepCollapsed) { clearComposerImageUndo(); invalidateAttachments(); placeCollapsedHandle(); return; }
    if (editor !== state.editor) {
      clearComposerFont();
      clearResizer();
      state.editor = editor;
      state.editorRoot = editor ? findEditorRoot(editor) : null;
      state.shell = editor ? findShell(editor, state.editorRoot) : null;
    } else if (editor && !state.collapsedNodes.length && (!state.shell?.isConnected || !state.modelRow?.isConnected)) {
      // Рамка искалась раз на поле — а в 3.1623 строка модели (ChatComposerChin) рисуется позже поля: рамкой
      // осталась вся .epitaxy-prompt, блок совпал с ней, и свёртке нечего было сворачивать (слово Элвиса 22.10:
      // «кнопка свёртки перестала работать… один раз развернулось»). Пока строки модели нет — ищем заново;
      // свёрнутое не трогаем: там строка схлопнута и рамка нашлась бы не та.
      state.shell = findShell(editor, state.editorRoot);
    }
    syncComposerImageUndo();
    syncComposerAttachments();
    // Номера скриншотов на плитках поля (раздел 12, #7532).
    try { markShotTiles(); } catch {}
    // ⌘Z снятого вложения (раздел 12, #9193): что сейчас в поле и что из него сняли.
    try { attachUndoSync(); } catch {}
    if (!editor) { handle.style.display = "none"; placeSideRail(null, false); return; }
    noteEditorFound();
    applyComposerFont(editor);
    composerFontLoadPing();
    // Свёрнутая строка модели нулевой высоты: ни блок (он узнаётся по соседу
    // рамки ростом со строку), ни сама строка заново не нашлись бы, и поле тут
    // же развернулось бы обратно. Пока она жива и схлопнута, держим найденное.
    const rowCollapsed = state.modelRow?.isConnected && state.collapsedNodes.includes(state.modelRow) &&
      state.composerBlock?.isConnected;
    const block = rowCollapsed ? state.composerBlock : findComposerBlock(editor, state.shell);
    if (block !== state.composerBlock) {
      clearCollapsedNodes();
      state.composerBlock = block;
    }
    // Рамку и строку модели пересчитываем каждый проход: Claude перерисовывает
    // низ окна целиком (смена модели, вложения), и закэшированные узлы после
    // этого указывали бы в пустоту.
    if (!state.collapsedNodes.includes(block) && !rowCollapsed) {
      const parts = findComposerParts(block, state.shell);
      state.frameChild = parts?.frameChild ?? null;
      state.modelRow = parts?.modelRow ?? null;
    }
    // Широкий вид (раздел 2г) решается ДО сворачивания: ступень там одна,
    // обычная, — и applyCollapse ниже обязан видеть уже её. Открытие боковой
    // панели меняет ширину плитки без resize, но флаг спрашивается на каждом
    // проходе, а контейнерный запрос CSS перестраивает сетку сам.
    const panel = layoutPanel(editor);
    const wide = wideLayout(panel);
    syncWide(wide);
    applyTitleSide(panel, wide);
    applyTitleAlign(panel, wide, editor);
    applyMainHead(panel, wide);
    applyDragStrip();
    applySideMin(panel, wide);
    applyDockInset(panel, wide);
    try { placeCardFloat(panel, wide); } catch {}
    applyTextLang(panel);
    placeSideRail(panel, wide);
    applyCollapse();
    applyCornerFade(panel);
    if (!state.shell?.isConnected) { handle.style.display = "none"; return; }
    if (state.stage === STAGE_COLLAPSED) { placeCollapsedHandle(); return; }
    applyHeight();
    // В широком виде ручки нет (слово Элвиса: «давай их пока не будем вообще»),
    // а замер обычной высоты пропускается: поле растянуто на всю колонку, и туда
    // легла бы высота колонки — после возврата в узкий вид порог «растянуто»
    // стал бы недостижим.
    if (wide) { handle.style.display = "none"; placeProgress(); return; }
    // Обычная высота известна только здесь: на этой ступени подмены высоты нет и
    // поле показывает свой собственный размер.
    if (state.stage === STAGE_NORMAL && state.editorRoot?.isConnected) {
      const measured = Math.round(state.editorRoot.getBoundingClientRect().height);
      if (measured >= MIN_HEIGHT) state.natural = measured;
    }
    const rect = state.shell.getBoundingClientRect();
    if (rect.width < narrowLimit() || rect.bottom <= 0 || rect.top >= innerHeight) { handle.style.display = "none"; return; }
    handle.style.display = "flex";
    // Узкая полоска верхом на кромке рамки (донор), место — общее на все три
    // полоски (railSeat, #6891): в узком окне ужимаются все три одинаково и на
    // скругления не выезжают. Поле выше своего контейнера всё равно не
    // поднимается, поэтому кромке ничего не мешает.
    const seat = railSeat();
    handle.style.left = `${seat.left}px`;
    handle.style.width = `${seat.width}px`;
    handle.style.top = `${Math.round(Math.max(topLimit() - HANDLE_HEIGHT / 2, rect.top - HANDLE_HEIGHT / 2))}px`;
    // Проверяем после расстановки: хит-тест идёт по новому месту полоски. Во
    // время перетаскивания не прячем — курсор держит именно её.
    state.handleCovered = !state.dragging && popupCoversHandle();
    if (state.handleCovered) handle.style.display = "none";
    placeProgress();
  };

  const cancelPendingLayout = () => {
    if (state.rafId) { cancelAnimationFrame(state.rafId); state.rafId = 0; }
    if (state.layoutTimer) { clearTimeout(state.layoutTimer); state.layoutTimer = 0; }
  };
  const runLayout = () => { state.rafId = 0; if (state.alive) layout(); };
  // Проход планируется через кадр, но не чаще раза в LAYOUT_MIN_GAP: во время
  // ответа Claude мутаций сотни в секунду, а каждый проход — принудительный
  // reflow в каждом из открытых окон.
  const scheduleLayout = () => {
    // После отбоя (страница оказалась чужой) проходов больше нет: подписки на
    // resize/scroll/указатель снять нельзя — они держат ручку и команды, — но
    // работы им уже не даём.
    if (state.scheduled || !state.alive || !state.watching) return;
    state.scheduled = true;
    const wait = Math.max(0, LAYOUT_MIN_GAP - (now() - state.layoutAt));
    if (wait === 0) { state.rafId = requestAnimationFrame(runLayout); return; }
    state.layoutTimer = setTimeout(() => {
      state.layoutTimer = 0;
      state.rafId = requestAnimationFrame(runLayout);
    }, wait);
  };
  track(cancelPendingLayout);

  // Блок ввода прибит к низу окна, и лента его не двигает, поэтому реагируем
  // только на то, что задело сам блок или его предка. Всё остальное подберёт
  // страховочный проход.
  const affectsComposer = node => {
    const anchor = state.composerBlock?.isConnected ? state.composerBlock
      : (state.shell?.isConnected ? state.shell : null);
    if (anchor == null || !(node instanceof Node)) return true;
    return anchor.contains(node) || node.contains(anchor);
  };
  const onScrolled = event => {
    if (!state.watching) return;
    // Прокрутка внутри шва (раздел 13в) — не лента и не поле ввода: findScroller на каждом её scroll — пересчёт стилей.
    try { if (event.target?.closest?.(`#${SEAM_ROOT_ID}`)) return; } catch {}
    // Место чтения (раздел 13а): лента уехала к низу сама, а Элвис читает.
    try { feedHoldOnScroll(event); } catch {}
    if (!affectsComposer(event.target)) return;
    scheduleLayout();
  };
  // Подсказка над названием чата (#7342, слово Элвиса 24.09: «не надо писать More
  // options for, надо просто название, в одну строку»). Под названием лежит ⌄
  // (layoutCss), и Claude подписывает её своей строкой «More options for
  // <название>» — она же aria-label кнопки. Нашли открытую подсказку ровно с этой
  // строкой — пишем в неё одно название и метим для правила «в одну строку».
  const titleTipOnMutation = () => {
    const tips = document.querySelectorAll('[data-cds="Tooltip"] [role="tooltip"]');
    if (tips.length === 0) return;
    for (const button of document.querySelectorAll(TITLE_MENU_SELECTOR)) {
      const label = button.getAttribute("aria-label");
      const title = button.parentElement?.querySelector("[data-pane-title]")?.textContent;
      if (!label || !title) continue;
      for (const tip of tips) {
        if (tip.textContent !== label) continue;
        const walker = document.createTreeWalker(tip, NodeFilter.SHOW_TEXT);
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          if (node.nodeValue !== label) continue;
          node.nodeValue = title;
          tip.setAttribute(TITLE_TIP_ATTRIBUTE, "");
        }
      }
    }
  };

  const ownClockText = record => {
    const label = record.type === "characterData" ? record.target?.parentNode : record.target;
    if (!label || label !== cornerClock) return false;
    return record.type === "characterData" || (record.type === "childList"
      && [...(record.addedNodes ?? []), ...(record.removedNodes ?? [])].every(node => node.nodeType === 3));
  };
  const onMutated = records => {
    state.mutationBatches += 1;
    // Только текст своего индикатора — секундных часиков угла. Удаление самого
    // узла/структурная замена проходят обычным путём.
    records = records.filter(record => !ownClockText(record));
    if (!records.length) { state.mutationSkipped += 1; return; }
    state.pageDirty = true;
    if (shotHome.shots.get(shotRoute())?.attempt) shotSync();
    if (shotState.pending) {
      for (const job of shotState.jobs) {
        // Отданная Claude вставка ждёт только плитку: пересборка поля её не отменяет (#9184).
        if (job.dispatched) { if (!shotSent(job)) shotCancel(job); continue; }
        if (!shotLive(job) || records.some(record => record.type === "childList" &&
            [...(record.removedNodes ?? [])].some(node => node === job.editor || node.contains?.(job.editor) ||
              (!job.dispatched && record.target === job.editor && job.nodes.includes(node))))) shotCancel(job);
      }
    }
    // Авто-Allow (раздел 12е) — до фильтра поля ввода: карточка разрешения живёт вне его.
    try { autoAllowOnMutation(records); } catch {}
    try { feedEnterOnMutation(records); } catch {}
    try { readOnMutation(records); } catch {}
    try { seenOnMutation(records); } catch {}
    try { titleTipOnMutation(); } catch {}
    for (const record of records) {
      if (!affectsComposer(record.target)) continue;
      // До отложенной раскладки прежняя кнопка уже может быть не последней.
      clearComposerImageUndo();
      syncComposerImageUndo();
      syncComposerAttachments();
      scheduleLayout();
      return;
    }
    state.mutationSkipped += 1;
  };
  statusPart("layout", () => (() => {
    const panel = layoutPanel(state.editor);
    const wide = wideLayout(panel);
    let width = null;
    try { width = panel ? Math.round(panel.getBoundingClientRect().width) : null; } catch {}
    return { wide, panel: width, side: wide ? sideWidth(panel) : null, sideMin: wide ? sideMinOf(panel) : null, gaps: wide ? wideState.gaps : null, justify: textJustifyOn() };
  })());
  HATCH && Object.assign(HATCH, { onMutated });

