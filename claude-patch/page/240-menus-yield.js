  // ---- 8. Полоска уступает всплывающим меню -------------------------------
  // Полоска живёт на самом верхнем z-index, поэтому меню Effort и модели она
  // перечёркивала насквозь. Ищем не по классам, а хит-тестом: стек элементов под
  // точкой уже отсортирован по z и не содержит прозрачных контейнеров
  // (pointer-events:none). Дошли до composer раньше чужого слоя — над полоской
  // ничего нет.
  const ownNode = node =>
    (state.shell?.isConnected === true && (state.shell.contains(node) || node.contains(state.shell))) ||
    (state.composerBlock?.isConnected === true &&
      (state.composerBlock.contains(node) || node.contains(state.composerBlock)));
  const popupCoversHandle = () => {
    const rect = handle.getBoundingClientRect();
    if (rect.width < 1) return false;
    const y = Math.round(rect.top + rect.height / 2);
    const points = [rect.left + 4, (rect.left + rect.right) / 2, rect.right - 4];
    for (const x of points) {
      for (const node of document.elementsFromPoint(Math.round(x), y)) {
        if (node === handle || handle.contains(node)) continue;
        if (node === document.body || node === document.documentElement) break;
        if (ownNode(node)) break;
        const computed = getComputedStyle(node);
        if (computed.position !== "fixed" && computed.position !== "absolute") continue;
        // z-index:auto — тоже слой: у попапа Effort числового z-index нет вовсе,
        // и полоска рисовалась НАСКВОЗЬ через его карточку. Безопасно, потому
        // что всё своё уже отсеяно, прозрачные обёртки в elementsFromPoint не
        // попадают, а хит-тест идёт ровно по трём точкам полоски.
        const z = Number(computed.zIndex);
        if (Number.isFinite(z)) {
          if (z >= POPUP_MIN_Z) return true;
          continue;
        }
        if (computed.position === "fixed") return true;
      }
    }
    return false;
  };
  // Есть ли вообще что прятать: открытое меню, список или модалка. Считаются только видимые узлы:
  // скрытый узел с ролью накладки (закрытая панель, постоянный [data-state="open"]) — не накладка.
  const overlayOpen = (selector = OVERLAY_SELECTOR) => {
    for (const node of document.querySelectorAll(selector)) {
      const rect = node.getBoundingClientRect();
      if (rect.width > 0 && rect.height > 0) return true;
    }
    return false;
  };
  // Отступ свёрнутой полоски от краёв рамки — её собственное скругление плюс
  // пара точек.
  const handleInset = node => {
    const radius = node?.isConnected
      ? parseFloat(getComputedStyle(node).borderTopLeftRadius) || 0
      : 0;
    return Math.max(HANDLE_MIN_INSET, Math.round(radius) + 2);
  };

  // Место всех трёх полосок: ось и ширина у них общие (#6891, слово Элвиса
  // 21.09: «они все три должны быть соосными, все в одном месте… все одной
  // толщиной»). Одна функция — единственный способ не дать им разъехаться:
  // полоска поля ходит за полем, дубли стоят у краёв окна, и до 21.09 каждая
  // считала ширину и центр по-своему — расходились на несколько точек.
  //
  // Ось — центр ОКНА (слово Элвиса 21.09 про дубли: «чтобы они всегда были по
  // центру окна»), но сойти с поля полоска не имеет права: открытая боковая
  // панель уводит поле вправо, и по центру окна линия села бы на список чатов,
  // а её зона захвата съела бы нажатия по нему. Тогда ось прижимается к краю
  // поля — и все три едут вместе, иначе соосность теряется.
  //
  // Ширина — узкая полоска донора: во всю ширину рамки зона захвата накрывает
  // кнопки и надписи по краям поля («широченная», слово Элвиса). В узком окне
  // ужимается по самому полю, но не уже RAIL_MIN_WIDTH. Берём чётной: при
  // нечётной центр приходится на половину точки.
  const railSeat = () => {
    const shell = state.shell?.isConnected ? state.shell : null;
    const block = state.composerBlock?.isConnected ? state.composerBlock : null;
    const shellBox = shell ? shell.getBoundingClientRect() : null;
    // Рамка свёрнутого поля схлопнута в ноль, но ширину держит блок ввода; нет
    // и его — считаем по окну: дубли у краёв окна нужны и такому окну.
    const onShell = shellBox != null && shellBox.width >= RAIL_HOST_MIN;
    const box = onShell ? shellBox : (block ? block.getBoundingClientRect() : null);
    const rect = box != null && box.width >= RAIL_HOST_MIN ? box : null;
    const inset = rect ? handleInset(onShell ? shell : block) : HANDLE_MIN_INSET;
    const left = rect ? rect.left + inset : HANDLE_MIN_INSET;
    const right = rect ? rect.right - inset : innerWidth - HANDLE_MIN_INSET;
    const width = Math.round(Math.max(RAIL_MIN_WIDTH,
      Math.min(HANDLE_NARROW_WIDTH, right - left)) / 2) * 2;
    const half = width / 2;
    // Ось — центр ПОЛЯ (#7201, 23.09: «должно же быть по центру… и у верхнего и
    // нижнего тоже по центру, соосно»): при открытой боковой панели центр окна
    // уводил все три к краю поля. Поля нет — центр окна.
    const axis = rect ? (left + right) / 2 : innerWidth / 2;
    return { left: Math.round(axis - half), width };
  };

