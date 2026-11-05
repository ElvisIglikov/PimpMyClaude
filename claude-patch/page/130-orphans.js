  // ---- 3. Сироты прошлых установок ---------------------------------------
  // Реестра у них могло и не быть (падение до его заполнения), а в окне они уже
  // висят. Сносим по id и по своим атрибутам — иначе полосок в окне остаётся
  // столько же, сколько было падений.
  for (const id of [STYLE_ID, HANDLE_ID, SIDE_RAIL_ID]) {
    for (const orphan of document.querySelectorAll(`#${id}`)) orphan.remove();
  }
  for (const node of document.querySelectorAll(`[${EDITOR_ROOT_ATTRIBUTE}],[${EDITOR_ATTRIBUTE}],[${BLOCK_ATTRIBUTE}],[${RING_PATH_ATTRIBUTE}],[${RING_ATTRIBUTE}]`)) {
    node.removeAttribute(EDITOR_ROOT_ATTRIBUTE);
    node.removeAttribute(EDITOR_ATTRIBUTE);
    node.removeAttribute(BLOCK_ATTRIBUTE);
    node.removeAttribute(RING_PATH_ATTRIBUTE);
    node.removeAttribute(RING_ATTRIBUTE);
    try { node.style.removeProperty(HEIGHT_VARIABLE); } catch {}
  }
  // Блок счёта Workflow у поля ввода (раздел 12п² до page-60) снят: его узлы, отступ под прокруткой
  // текста поля и запомненные фильтр и вид прошлой страницы убираются здесь.
  for (const orphan of document.querySelectorAll(`#${RICK_CELLS_ID},#${RICK_CARD_ID},#${RICK_FLOW_ID}`)) orphan.remove();
  for (const node of document.querySelectorAll(`[${RICK_ROOM_ATTRIBUTE}]`)) {
    node.removeAttribute(RICK_ROOM_ATTRIBUTE);
    try { node.style.removeProperty(RICK_ROOM_VARIABLE); } catch {}
  }
  try { localStorage.removeItem(RICK_FILTER_KEY); localStorage.removeItem(RICK_VIEW_KEY); } catch {}
  // Часики кеша у закреплённых чатов (раздел 2е до page-64) сняты: метки прошлой страницы на подписях
  // строк и её ключ настройки «таймер выключен» убираются здесь.
  // Только подписи строк: ту же метку data-myclaude-clock носит узел часиков угла (раздел 2ж).
  for (const node of document.querySelectorAll(`[data-row-label][${PINNED_CLOCK_ATTRIBUTE}],[data-row-label][${PINNED_CLOCK_LATE_ATTRIBUTE}]`)) {
    node.removeAttribute(PINNED_CLOCK_ATTRIBUTE);
    node.removeAttribute(PINNED_CLOCK_LATE_ATTRIBUTE);
  }
  try { localStorage.removeItem(PINNED_CLOCK_OFF_KEY); } catch {}
  // «Автосвёртка» (#6666) снята вместе с меню жёлтой кнопки (WF248 П2, лист 48 · 2.1): её флаг прошлой
  // страницы (команда auto-collapse) больше никто не читает — стирается здесь.
  try { localStorage.removeItem("myclaude.autoCollapse"); } catch {}

