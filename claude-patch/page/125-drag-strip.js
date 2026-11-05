  // ---- 2ж¹. Окно таскается за всю верхнюю полосу (#10984) ----------------------
  // Слово Элвиса 29.10.2026: «у пимпа вот там сверху не за что ухватиться сейчас… Слева, где закрыть, открыть, там
  // можно ухватиться. А где-то посередине сверху, например, вообще не хватается… вот эта вот вся область сверху».
  //
  // Почему так: это делает сам Пимп. У главного окна без шапки (раздел 2ж, #7913) шапка Claude — его полоса
  // перетаскивания — сжата до нуля, а взамен стоит только полоса 76×40 под кнопками окна (MAIN_DRAG_ID). Правее
  // кнопок окна таскать не за что: лента начинается от самого края (060, WF192), у Claude там лишь `.draggable` 7 px.
  //
  // Здесь: пока стоит полоса под кнопками (mainHead.drag), правее неё — своя полоса во всю ширину окна высотой
  // DRAG_STRIP_HEIGHT (верх ленты там всё равно затухает). Левый край — TITLEBAR_CLEARANCE_LEFT: между ними кнопка
  // Claude «Show sidebar» (82–110), её не накрываем. Узел — ПЕРВЫМ в body: Electron считает области окна в порядке
  // дерева, и позднее no-drag вырезает раннее drag, — все кнопки над полосой (угол «Проект · чат», PMP, галерея,
  // ручки поля, кнопки Claude) остаются нажимаемыми. Узел без id (метка DRAG_STRIP_ATTRIBUTE): нажатий у него нет,
  // слой как MAIN_DRAG_ID. Пропал из body (перерисовка) — вернётся на следующем проходе раскладки.
  const DRAG_STRIP_ATTRIBUTE = "data-myclaude-drag-strip";
  const DRAG_STRIP_ON_ATTRIBUTE = "data-myclaude-drag-strip-on";
  const DRAG_STRIP_HEIGHT = 28;
  const dragStrip = { node: null, on: false };
  for (const orphan of document.querySelectorAll(`[${DRAG_STRIP_ATTRIBUTE}]`)) orphan.remove();
  const dragStripMake = () => {
    const node = document.createElement("div");
    node.setAttribute(DRAG_STRIP_ATTRIBUTE, "");
    node.setAttribute("aria-hidden", "true");
    return node;
  };
  // Из прохода раскладки (раздел 4б, сразу после applyMainHead): показ — ровно когда стоит полоса под кнопками.
  const applyDragStrip = () => {
    // С 03.11.2026 полоса стоит у главного окна всегда (слово: «сверху перетягивание не работает»): между боковой
    // колонкой и окном чата у Claude — лишь `.draggable` 8 px.
    const on = isMainWindow();
    dragStrip.on = on;
    if (!on) {
      if (dragStrip.node?.hasAttribute(DRAG_STRIP_ON_ATTRIBUTE)) dragStrip.node.removeAttribute(DRAG_STRIP_ON_ATTRIBUTE);
      return;
    }
    const body = document.body;
    if (!body) return;
    dragStrip.node ??= dragStripMake();
    if (dragStrip.node.parentNode !== body) {
      try { body.insertBefore(dragStrip.node, body.firstChild); } catch { return; }
    }
    if (!dragStrip.node.hasAttribute(DRAG_STRIP_ON_ATTRIBUTE)) dragStrip.node.setAttribute(DRAG_STRIP_ON_ATTRIBUTE, "");
  };
  lateRules.push(
    `[${DRAG_STRIP_ATTRIBUTE}]{position:fixed;display:none;top:0;left:${TITLEBAR_CLEARANCE_LEFT}px;right:0;height:${DRAG_STRIP_HEIGHT}px;margin:0;padding:0;border:0;background:transparent;-webkit-app-region:drag;z-index:29}`,
    `[${DRAG_STRIP_ATTRIBUTE}][${DRAG_STRIP_ON_ATTRIBUTE}]{display:block}`,
  );
  track(() => { try { dragStrip.node?.remove(); } catch {} });
  // Полоса во всю ширину (#10984): стоит ли, первая ли в body (иначе кнопки до неё в дереве она бы накрыла).
  statusPart("dragStrip", () => ({ on: dragStrip.on && Boolean(dragStrip.node?.isConnected),
    first: Boolean(dragStrip.node && document.body?.firstChild === dragStrip.node) }));
  HATCH && Object.assign(HATCH, { applyDragStrip, dragStrip });
