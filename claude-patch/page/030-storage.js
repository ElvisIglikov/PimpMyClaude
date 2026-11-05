  // ---- 2. Хранилище -------------------------------------------------------
  const readStoredHeight = () => {
    try {
      const stored = Number(sessionStorage.getItem(HEIGHT_STORAGE_KEY));
      return Number.isFinite(stored) && stored >= MIN_HEIGHT ? stored : null;
    } catch { return null; }
  };
  const storeHeight = value => {
    try {
      if (value == null) sessionStorage.removeItem(HEIGHT_STORAGE_KEY);
      else sessionStorage.setItem(HEIGHT_STORAGE_KEY, String(Math.round(value)));
    } catch {}
  };
  const readStoredStage = () => {
    try {
      const raw = sessionStorage.getItem(STAGE_STORAGE_KEY);
      const stage = Number(raw);
      if (raw != null && Number.isInteger(stage) && stage >= STAGE_COLLAPSED && stage <= STAGE_STRETCHED) return stage;
    } catch {}
    return null;
  };
  const storeStage = value => {
    try { sessionStorage.setItem(STAGE_STORAGE_KEY, String(value)); } catch {}
  };

  // Стартовая ступень. Ступень «растянуто» без сохранённой высоты невозможна,
  // поэтому она откатывается к обычной (донор).
  const initialHeight = readStoredHeight();
  const storedStage = readStoredStage();
  const initialStage = (() => {
    if (storedStage === STAGE_STRETCHED || storedStage == null) return initialHeight == null ? STAGE_NORMAL : STAGE_STRETCHED;
    return storedStage;
  })();
  // Откат записываем сразу. Иначе он живёт только в памяти: setStage в ту же
  // ступень выходит на равенстве и хранилище не поправит, и в сессии остаётся
  // «растянуто», которому поле уже не соответствует. Заодно убираем негодную
  // высоту — из-за неё откат и случился.
  storeStage(initialStage);
  if (storedStage === STAGE_STRETCHED && initialStage !== STAGE_STRETCHED) storeHeight(null);

  const state = {
    alive: true,
    watching: true,
    editorFound: false,
    cssOk: false,
    cssViolations: [],
    editor: null,
    editorRoot: null,
    shell: null,
    composerBlock: null,
    // Прямой ребёнок блока ввода, внутри которого лежит рамка поля, и строка
    // модели под ним: сворачиваем всё до рамки включительно, строку оставляем.
    frameChild: null,
    modelRow: null,
    collapsedNodes: [],
    stage: initialStage,
    height: initialStage === STAGE_STRETCHED ? initialHeight : null,
    // Последняя высота, которую натянули рукой. Живёт в памяти окна и переживает
    // уход на другие ступени: без неё возврат в «растянуто» терял бы размер.
    lastStretched: initialHeight,
    // Снимок ленты на время тяги: сама лента и стояла ли она внизу.
    dragTail: null,
    dragTailDown: false,
    // Высота, на которой верх поля перестаёт подниматься; живёт до выхода из
    // растянутого вида.
    ceiling: null,
    // Замеренный упор самого контейнера вместе с приметой вида окна: выше этой
    // отметки он верх поля не пускает, а в другом размере замер не годится.
    ceilingFloor: null,
    stretchSteps: 0,
    natural: null,
    handleCovered: false,
    dragging: false,
    moved: false,
    startY: 0,
    startHeight: 0,
    dragNatural: NATURAL_FALLBACK,
    clickTimer: 0,
    cashoutTimer: 0,
    // Спрашивал ли сторож переноса окно-родителя, какой в нём чат (WF37).
    // Один вопрос на запись, а не на каждый тик (см. cashoutAskParent).
    cashoutAsked: false,
    giveUpTimer: 0,
    // Прокрутка ленты: кто едет, до какой высоты доехали и сколько доборов
    // осталось. Кадр и таймер добора снимаются вместе, одним clearScrollWatch.
    scroller: null,
    scrollRaf: 0,
    scrollTimer: 0,
    scrollSteps: 0,
    scrollSeen: 0,
    scrollRuns: 0,
    // Короткое время под сообщениями: за кем смотрим и когда был последний
    // проход (троттлинг, см. TIME_MIN_GAP).
    timeTarget: null,
    timeTimer: 0,
    timeAt: 0,
    timeRuns: 0,
    // Кнопка «Workflow»: сколько раз вставляли текст запуска и чем кончилось
    // в последний раз (видно в status() на гейте).
    workflowRuns: 0,
    workflowResult: null,
    // «Новое окно» и «В отдельное окно» (раздел 12б): запись последнего запуска
    // любой из двух команд — {state, step, id, at, busy, runs, back} и, с WF16,
    // ещё {folder, chip, name, rename, title, layers}; она же уходит наружу
    // полем newWindow в status().
    newWindow: null,
    scheduled: false,
    rafId: 0,
    layoutTimer: 0,
    layoutAt: 0,
    layoutRuns: 0,
    pageDirty: true, pageScanAt: 0, pageKey: "", pageWorking: null,
    mutationBatches: 0,
    mutationSkipped: 0,
    // Сколько своих узлов сторож вернул в body после того, как Claude пересобрал
    // его содержимое (#6766, restoreOwnNodes в разделе 16). Ноль — болезни не
    // было; растёт — значит окно теряет наши узлы и это видно, а не гадается.
    restored: 0,
  };

