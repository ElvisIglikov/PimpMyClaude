  // ---- 7. Высота ----------------------------------------------------------
  // Куда именно упирается верх поля: в низ титульной полосы. Меряем её саму —
  // на части экранов Claude полосы просто нет, и константа врала бы.
  // Полоса есть, но нулевой высоты (замер 05.11, #11693: строка «Инструменты сессии» спрятана) — над полем пусто,
  // потолок — сам верх окна, ручка встаёт на место верхнего дубля (он уступает, раздел placeSuperRails).
  const topLimit = () => {
    const bar = document.querySelector(".epitaxy-titlebar");
    const rect = bar?.isConnected ? bar.getBoundingClientRect() : null;
    if (rect && rect.height > 0) return Math.round(rect.top + rect.height + 2);
    return rect && rect.width > 0 ? Math.round(Math.max(0, rect.top) + HANDLE_HEIGHT / 2) : SAFE_TOP_INSET;
  };
  const maximumHeight = () => {
    if (!state.shell) return 640;
    const top = state.shell.getBoundingClientRect().top;
    const current = state.height ?? state.editorRoot?.getBoundingClientRect().height ?? 0;
    return Math.max(MIN_HEIGHT, Math.floor(current + top - topLimit()));
  };
  const clampHeight = value => Math.round(Math.min(maximumHeight(), Math.max(MIN_HEIGHT, value)));
  // Обычная высота поля — та, которую Claude держит сам, без нашей подмены.
  // Меряем её только на ступени «обычная высота» и запоминаем: на других
  // ступенях померить нечего, а порог ступеней без неё не посчитать.
  const naturalHeight = () =>
    state.natural != null && state.natural >= MIN_HEIGHT ? state.natural : NATURAL_FALLBACK;

  const clearResizer = () => {
    if (state.editorRoot?.isConnected) {
      state.editorRoot.style.removeProperty(HEIGHT_VARIABLE);
      state.editorRoot.removeAttribute(EDITOR_ROOT_ATTRIBUTE);
    }
    if (state.editor?.isConnected) state.editor.removeAttribute(EDITOR_ATTRIBUTE);
    clearCollapsedNodes();
    handle.style.display = "none";
  };

  // Низ всего блока ввода: рамка поля, а под ней строка модели с кругляшком.
  const composerBottom = () => {
    const node = state.composerBlock?.isConnected
      ? state.composerBlock : (state.shell?.isConnected ? state.shell : null);
    if (node == null) return null;
    const rect = node.getBoundingClientRect();
    return rect.height > 0 ? rect.bottom : null;
  };
  const setHeightVariable = () => {
    state.height = clampHeight(state.height);
    state.editorRoot.setAttribute(EDITOR_ROOT_ATTRIBUTE, "true");
    state.editor?.setAttribute(EDITOR_ATTRIBUTE, "true");
    state.editorRoot.style.setProperty(HEIGHT_VARIABLE, `${state.height}px`);
  };
  // maximumHeight() считает место от ВЕРХА рамки: пока верх не упёрся в потолок,
  // формула разрешает расти. Но контейнер Claude верх выше своего края не
  // пускает, и лишние точки уходят ВНИЗ — вместе со строкой модели и кругляшком
  // отправки. Поэтому после каждой подстановки смотрим не на формулу, а на факт:
  // низ блока ввода обязан остаться в окне. Вылез — срезаем ровно на выступ.
  const trimToViewport = () => {
    if (state.height == null || !state.editorRoot?.isConnected) return;
    // Двух подходов хватает: первый срезает выступ, второй добирает остаток,
    // если контейнер отдал не всю высоту. Дальше ждём следующего прохода —
    // лесенка из бесконечных подрезаний хуже одной лишней точки.
    for (let step = 0; step < 2; step += 1) {
      const bottom = composerBottom();
      if (bottom == null) return;
      const over = Math.round(bottom - (innerHeight - BOTTOM_SAFE_INSET));
      if (over <= BOTTOM_TRIM_SLACK) return;
      const before = state.height;
      state.height = Math.max(MIN_HEIGHT, before - over);
      if (state.height >= before) { state.height = before; return; }
      setHeightVariable();
      // Срез не поднял низ — значит держит его не наша высота, и дальше мы
      // просто отбираем поле ни за что. Возвращаем как было.
      const after = composerBottom();
      if (after == null || after > bottom - BOTTOM_TRIM_SLACK) {
        state.height = before;
        setHeightVariable();
        return;
      }
    }
  };
  const applyHeight = () => {
    if (!state.editorRoot?.isConnected) return;
    if (state.height == null) {
      state.editorRoot.style.removeProperty(HEIGHT_VARIABLE);
      state.editorRoot.removeAttribute(EDITOR_ROOT_ATTRIBUTE);
      state.editor?.removeAttribute(EDITOR_ATTRIBUTE);
      return;
    }
    setHeightVariable();
    trimToViewport();
  };
  HATCH && Object.assign(HATCH, { clampHeight });

