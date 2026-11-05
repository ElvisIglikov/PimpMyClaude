  // ---- 6. Сворачивание ----------------------------------------------------
  // Что именно схлопывать: рамка поля, всё, что стоит над ней (плашка проекта,
  // вложения, строка окружения), строка модели под ней и шапка чата сверху —
  // свёрнутое поле с 20.09 это режим чтения (#6651, слово Элвиса: «скрывалось
  // вообще всё внизу… и всё, что сверху, чтобы текст шёл на самый верх»). На виду
  // остаётся одна полоска: она живёт в body и садится на нижний край окна.
  const collapseTargets = () => {
    const block = state.composerBlock;
    if (!block?.isConnected) return [];
    // Блок целиком не схлопываем ни при каких обстоятельствах: вместе с ним
    // уезжает строка модели («Auto · Opus 5 · Max»), низ окна превращается в
    // чёрную полосу, и вернуть поле мышью становится нечем. Разбор низа
    // composer не удался — сворачиваем одну рамку поля, а если и её нет, не
    // сворачиваем вовсе: открытое поле лучше слепого окна.
    if (!state.frameChild?.isConnected || !state.modelRow?.isConnected) {
      const shell = state.shell;
      return shell?.isConnected && block.contains(shell) && shell !== block ? [shell] : [];
    }
    const targets = [];
    for (let node = block.firstElementChild; node; node = node.nextElementSibling) {
      if (isFocusGuard(node)) continue;
      targets.push(node);
      if (node !== state.modelRow) continue;
      const titlebar = document.querySelector(".epitaxy-titlebar");
      if (titlebar?.isConnected) targets.push(titlebar);
      return targets;
    }
    const shell = state.shell;
    return shell?.isConnected && block.contains(shell) && shell !== block ? [shell] : [];
  };

  // Режим чтения: лента идёт от самого верха окна, и первые строки просвечивали
  // сквозь кнопки окна и «Show sidebar» (слово Элвиса 20.09 06:10: «угловой фейд,
  // не на всю длину»). Не накладка, а маска самой ленты: текст в углу плавно
  // сходит на нет, цвет фона подбирать не надо и кнопки Claude ничем не закрыты.
  const CORNER_FADE_ATTRIBUTE = "data-myclaude-corner-fade";
  const CORNER_FADE_REACH_MAIN = 118;
  const CORNER_FADE_REACH_POPOUT = 78;
  const CORNER_FADE_DROP = 40;
  // Зеркальный фейд под кружком (#6737) МЕНЬШЕ левого верхнего намеренно: слева
  // под фейдом пустая шапка окна, а справа внизу — свежий текст, который Элвис
  // прямо сейчас читает; зеркало 118×40 съело бы конец последнего ответа.
  const CORNER_FADE_RING_REACH = 72;
  const CORNER_FADE_RING_RISE = 30;
  const cornerFade = { node: null };
  const clearRingFade = node => {
    if (!node) return;
    try {
      node.removeAttribute(RING_FADE_ATTRIBUTE);
      node.style.removeProperty("--myclaude-ring-fade-w");
      node.style.removeProperty("--myclaude-ring-fade-h");
    } catch {}
  };
  const clearCornerFade = () => {
    const node = cornerFade.node;
    cornerFade.node = null;
    if (!node) return;
    clearRingFade(node);
    try {
      node.removeAttribute(CORNER_FADE_ATTRIBUTE);
      node.style.removeProperty("--myclaude-fade-w");
      node.style.removeProperty("--myclaude-fade-h");
    } catch {}
  };
  track(clearCornerFade);
  const applyCornerFade = panel => {
    let scroller = null;
    // Главное окно (#7913) без шапки всегда: затухание и без режима чтения.
    const reading = state.stage === STAGE_COLLAPSED || (isMainWindow() && Boolean(panel?.isConnected));
    try { scroller = reading ? panel?.querySelector?.('[data-testid="epitaxy-virtual-transcript"]') ?? null : null; } catch {}
    const box = scroller?.isConnected ? scroller.getBoundingClientRect() : null;
    const reach = location.href === "about:blank" ? CORNER_FADE_REACH_POPOUT : CORNER_FADE_REACH_MAIN;
    const width = box ? reach - box.left : 0;
    const height = box ? CORNER_FADE_DROP - box.top : 0;
    // Открыта боковая панель — кнопки стоят над ней, а не над лентой.
    if (!box || box.width <= 0 || box.left >= TITLEBAR_CLEARANCE_LEFT || width <= 0 || height <= 0) { clearCornerFade(); return; }
    if (cornerFade.node !== scroller) clearCornerFade();
    cornerFade.node = scroller;
    const w = `${Math.round(width * 1.25)}px`;
    const h = `${Math.round(height * 1.35)}px`;
    if (scroller.style.getPropertyValue("--myclaude-fade-w") !== w) scroller.style.setProperty("--myclaude-fade-w", w);
    if (scroller.style.getPropertyValue("--myclaude-fade-h") !== h) scroller.style.setProperty("--myclaude-fade-h", h);
    if (!scroller.hasAttribute(CORNER_FADE_ATTRIBUTE)) scroller.setAttribute(CORNER_FADE_ATTRIBUTE, "");
    // Второй угол — только когда кружок и правда всплыл (#6737): нет кружка —
    // нет и фейда, и правило с двумя масками не применяется вовсе.
    const ringWidth = ringState.button?.isConnected ? CORNER_FADE_RING_REACH - (innerWidth - box.right) : 0;
    const ringHeight = ringState.button?.isConnected ? CORNER_FADE_RING_RISE - (innerHeight - box.bottom) : 0;
    if (ringWidth <= 0 || ringHeight <= 0) { clearRingFade(scroller); return; }
    const rw = `${Math.round(ringWidth * 1.25)}px`;
    const rh = `${Math.round(ringHeight * 1.35)}px`;
    if (scroller.style.getPropertyValue("--myclaude-ring-fade-w") !== rw) scroller.style.setProperty("--myclaude-ring-fade-w", rw);
    if (scroller.style.getPropertyValue("--myclaude-ring-fade-h") !== rh) scroller.style.setProperty("--myclaude-ring-fade-h", rh);
    if (!scroller.hasAttribute(RING_FADE_ATTRIBUTE)) scroller.setAttribute(RING_FADE_ATTRIBUTE, "");
  };

  // Кружок контекста в режиме чтения (#6737, WF78). Слово Элвиса 20.09: «кружок
  // — правый нижний угол, там же, где он и сейчас, он на своём месте остаётся
  // стоять, тот же кружок, просто плавает».
  //
  // Кружок НЕ вынимается из дерева и не клонируется — React потерял бы свой
  // узел. Вместо этого сужается действие свёртки на одну ветку: тому ОДНОМУ
  // прямому ребёнку блока ввода, внутри которого лежит кнопка, достаётся
  // «collapsed-ring» (свёртка без opacity, с overflow:visible и relative),
  // путь от него вниз до кнопки метится RING_PATH_ATTRIBUTE, соседи по пути
  // прячутся правилом, а сама кнопка метится RING_ATTRIBUTE и встаёт absolute
  // в правый нижний угол. Метки ставятся заново на каждом проходе: React
  // пересоздаёт узлы, как и для углового фейда.
  const ringState = { nodes: [], button: null };
  const clearRingPath = () => {
    for (const node of ringState.nodes) {
      if (node.isConnected) node.removeAttribute(RING_PATH_ATTRIBUTE);
    }
    if (ringState.button?.isConnected) ringState.button.removeAttribute(RING_ATTRIBUTE);
    ringState.nodes = [];
    ringState.button = null;
  };
  track(clearRingPath);
  // Прямой ребёнок блока ввода, внутри которого лежит кружок. Ищем подъёмом ОТ
  // КНОПКИ, а не по имени строки: разведка сама себе противоречит («над полем
  // ввода» и «в нижней строке поля ввода»), и класс тут был бы гаданием.
  // Кнопка, оказавшаяся прямым ребёнком блока, в счёт не идёт: путь до неё
  // пустой, а свёртка нулевой высоты срезала бы сам значок.
  const ringChild = block => {
    if (!block?.isConnected) return null;
    let button = null;
    try { button = block.querySelector(USAGE_RING_SELECTOR); } catch {}
    if (!button?.isConnected) return null;
    let child = button;
    while (child?.parentElement && child.parentElement !== block) child = child.parentElement;
    if (child?.parentElement !== block || child === button) return null;
    return { child, button };
  };
  const applyRingPath = ring => {
    if (!ring) { clearRingPath(); return; }
    const nodes = [];
    // Сама кнопка в путь НЕ входит: правило прячет всё, что внутри пути и не
    // помечено, а внутри кнопки лежит её собственный значок.
    for (let node = ring.button.parentElement; node && node !== ring.child; node = node.parentElement) nodes.push(node);
    nodes.push(ring.child);
    for (const node of ringState.nodes) {
      if (node.isConnected && !nodes.includes(node)) node.removeAttribute(RING_PATH_ATTRIBUTE);
    }
    if (ringState.button?.isConnected && ringState.button !== ring.button) ringState.button.removeAttribute(RING_ATTRIBUTE);
    for (const node of nodes) {
      if (!node.hasAttribute(RING_PATH_ATTRIBUTE)) node.setAttribute(RING_PATH_ATTRIBUTE, "");
    }
    if (!ring.button.hasAttribute(RING_ATTRIBUTE)) ring.button.setAttribute(RING_ATTRIBUTE, "");
    ringState.nodes = nodes;
    ringState.button = ring.button;
  };

  const clearCollapsedNodes = () => {
    for (const node of state.collapsedNodes) {
      if (node.isConnected) node.removeAttribute(BLOCK_ATTRIBUTE);
    }
    state.collapsedNodes = [];
    clearRingPath();
  };

  const applyCollapse = () => {
    const collapsed = state.stage === STAGE_COLLAPSED;
    const next = collapsed ? collapseTargets() : [];
    // Сворачивать нечего: в свёрнутой ступени не залипаем, иначе полоска
    // рисовалась бы поверх открытого поля и врала о состоянии.
    if (collapsed && next.length === 0) {
      clearCollapsedNodes();
      state.stage = STAGE_NORMAL;
      storeStage(STAGE_NORMAL);
      handle.dataset.collapsed = "false";
      return;
    }
    for (const node of state.collapsedNodes) {
      if (node.isConnected && !next.includes(node)) node.removeAttribute(BLOCK_ATTRIBUTE);
    }
    // Ветка с кружком контекста сворачивается по-своему (#6737): без opacity,
    // чтобы кружок остался виден и нажимаем. В широком виде ступень всегда
    // обычная (syncWide), поэтому сюда мы там просто не заходим.
    const ring = collapsed ? ringChild(state.composerBlock) : null;
    for (const node of next) node.setAttribute(BLOCK_ATTRIBUTE, node === ring?.child ? "collapsed-ring" : "collapsed");
    applyRingPath(next.includes(ring?.child) ? ring : null);
    state.collapsedNodes = next;
    handle.dataset.collapsed = collapsed ? "true" : "false";
    handle.setAttribute("aria-label", collapsed ? "Вернуть поле ввода" : "Изменить высоту поля ввода");
  };
  // #9859: новый узел свёрнутого поля прячется до первой отрисовки — из колбэка наблюдателя (раздел
  // 12ф, prePaintWatch), не через раскладку: та ждёт кадр, а то и LAYOUT_MIN_GAP, и пересобранная
  // React-ом строка поля мелькала раскрытой. Метится только бесспорное — прямой ребёнок блока не ниже
  // строки модели и шапка окна; ветку с кружком контекста (свой вид) и всё прочее сверит раскладка.
  const collapseOnMutation = records => {
    if (state.stage !== STAGE_COLLAPSED || !state.collapsedNodes.length) return;
    const block = state.composerBlock;
    const model = state.modelRow;
    if (!block?.isConnected || model?.parentElement !== block || !state.collapsedNodes.includes(model)) return;
    const hide = node => {
      if (node.hasAttribute(BLOCK_ATTRIBUTE)) return;
      node.setAttribute(BLOCK_ATTRIBUTE, "collapsed");
      state.collapsedNodes.push(node);
    };
    for (const record of records) {
      if (record.type !== "childList") continue;
      for (const node of record.addedNodes ?? []) {
        if (node?.nodeType !== 1 || !node.isConnected) continue;
        if (node.parentElement === block) {
          if (isFocusGuard(node)) continue;
          try { if (node.querySelector(USAGE_RING_SELECTOR)) continue; } catch { continue; }
          let above = node === model;
          for (let next = node.nextElementSibling; next && !above; next = next.nextElementSibling) above = next === model;
          if (above) hide(node);
          continue;
        }
        let bar = null;
        try { bar = node.matches?.(".epitaxy-titlebar") ? node : node.querySelector?.(".epitaxy-titlebar"); } catch {}
        if (bar?.isConnected) hide(bar);
      }
    }
  };
  HATCH && Object.assign(HATCH, { collapseTargets, collapseOnMutation });

