  // ---- 10. Ступени --------------------------------------------------------
  const finishDrag = () => {
    if (!state.dragging) return;
    // Тяга меняет высоту мимо setStage (высота едет прямо в applyHeight), и без
    // этих строк лента после жеста осталась бы недокрученной: поле отняло у неё
    // место, а прокрутку никто не двинул (#5869, находка проверяющего 12.09).
    if (state.dragTailDown) {
      const tail = state.dragTail;
      if (tail?.isConnected) { try { tail.scrollTop = tail.scrollHeight; } catch {} }
    }
    state.dragTail = null;
    state.dragTailDown = false;
    state.dragging = false;
    handle.dataset.dragging = "false";
    document.documentElement.style.cursor = "";
    document.documentElement.style.userSelect = "";
    storeHeight(state.height);
    scheduleLayout();
  };

  // Лента разговора за полем не следит: место, которое поле у неё отняло, она
  // отдаёт снизу, а прокрутку никто не двигает — последние строки уезжают под
  // поле, и мышью их уже не достать (#5869; замер 12.09: недокрут ленты 0 → 40
  // точек, стоило открыть поле). Поэтому на каждой смене ступени: стояла лента
  // внизу — вернём её вниз.
  //
  // Ленту ищем ТЕМ ЖЕ искателем, что и команда «Прокрутить» (раздел 13): он
  // знает виртуальную ленту по примете и иначе идёт от последнего сообщения
  // вверх. Свой обход «самый высокий прокручиваемый узел» держался в главном
  // окне на восьми точках: лента 668, боковая панель 660 — двухстрочный
  // черновик, и мы крутили бы список чатов (находка проверяющего 12.09).
  // findScroller объявлен ниже по файлу — на смене ступени он уже есть, а
  // try прикрывает единственный случай, когда ступень тронули на самом старте.
  const TAIL_SLACK = 2;
  const tailScroller = () => {
    try { return findScroller(); } catch { return null; }
  };
  const tailAtBottom = node => node != null &&
    Number(node.scrollHeight) - Number(node.clientHeight) - Number(node.scrollTop) <= TAIL_SLACK;

  // Единственная точка смены ступени: и тяга, и клики, и команды снаружи ходят
  // только через неё, поэтому ступень и высота не могут разъехаться.
  const setStage = (next, options) => {
    const value = Math.max(STAGE_COLLAPSED, Math.min(STAGE_STRETCHED, next));
    const height = options?.height;
    if (state.stage === value && (value !== STAGE_STRETCHED || height == null)) return;
    // Меряем ДО правки высоты: после неё «стояла ли лента внизу» уже не узнать.
    const tail = tailScroller();
    const tailDown = tailAtBottom(tail);
    state.stage = value;
    storeStage(value);
    if (value === STAGE_STRETCHED) {
      // Возврат в «растянуто» без явной высоты — это возврат к своему размеру, а
      // не к потолку окна: сначала последняя натянутая рукой высота и только
      // потом максимум.
      state.height = clampHeight(height ?? state.height ?? state.lastStretched ?? maximumHeight());
      state.lastStretched = state.height;
    } else {
      // Обычная высота и полоска своей высоты не хранят: подмену снимаем, и поле
      // снова слушается самого Claude. Саму цифру помним в памяти окна, иначе
      // возврат в «растянуто» открывал бы поле во всё окно вместо прежнего.
      state.lastStretched = state.height ?? state.lastStretched;
      state.height = null;
      // Достигнутый упор верен только для текущего вида: сменилась ступень —
      // считать заново.
      state.ceiling = null;
      storeHeight(null);
      if (state.editorRoot?.isConnected) {
        state.editorRoot.style.removeProperty(HEIGHT_VARIABLE);
        state.editorRoot.removeAttribute(EDITOR_ROOT_ATTRIBUTE);
      }
    }
    applyCollapse();
    applyHeight();
    if (!options?.silent) layout();
    // Доскручиваем последним: до этого высота поля ещё едет, и целиться было бы
    // не во что. Не стояла лента внизу — не трогаем: человек сам ушёл наверх.
    if (tailDown && tail?.isConnected) {
      try { tail.scrollTop = tail.scrollHeight; } catch {}
    }
  };

  // ---- Полоски и все окна разом (#6900) ------------------------------------
  // Слово Элвиса 21.09: «нажал шифт на полосочку — они все, например,
  // раскрылись, все свернулись… удобно так всеми чатами управлять». Обычное
  // нажатие по любой из трёх полосок работает с этим окном, нажатие с Shift —
  // со всеми окнами Claude разом.
  //
  // Окна разговаривают между собой напрямую, через BroadcastChannel: профиль у
  // страниц Claude общий, и канал слышат все окна. Проверено живьём 21.09:
  // всплывающие окна (about:blank) и главное окно claude.ai слышат друг друга;
  // подложки (data:) и оболочка приложения (file://) — нет, но полосок там и
  // нет вовсе. Приложение в этом не участвует: команда идёт из страницы в
  // страницу, и работает это на живом inject.js, без пересборки Пимпа.
  const RAIL_CHANNEL = "myclaude-rails";
  const railChannel = (() => {
    try { return new BroadcastChannel(RAIL_CHANNEL); } catch { return null; }
  })();
  if (railChannel) track(() => { try { railChannel.close(); } catch {} });
  // Шаг ступени по нажатию на любую из трёх полосок. Ступень считает ЭТО окно,
  // а остальные её повторяют — поэтому после Shift все окна стоят одинаково, а
  // не каждое по-своему («они все, например, раскрылись, все свернулись»).
  const railStep = all => {
    const next = state.stage === STAGE_COLLAPSED ? STAGE_NORMAL : STAGE_COLLAPSED;
    setStage(next);
    if (!all) return;
    try { railChannel?.postMessage({ kind: "stage", stage: next }); } catch {}
  };
  if (railChannel) {
    railChannel.onmessage = event => {
      const detail = event?.data;
      if (!detail || detail.kind !== "stage") return;
      const stage = Number(detail.stage);
      // Ступеней в окне нет (широкий вид, поля не нашлось) — повторять нечего:
      // чужой шаг свернул бы поле, которое нечем вернуть.
      if (!Number.isFinite(stage) || !stagesLive()) return;
      try { setStage(Math.max(STAGE_COLLAPSED, Math.min(STAGE_STRETCHED, stage))); } catch {}
    };
  }

  // В поле есть что отправить: текст или вложение (счёт отправки 12у, «Новое окно» 12б).
  const composerFilled = editor => {
    try {
      if (String(editor.textContent ?? "").trim()) return true;
      return Boolean(state.composerBlock?.querySelector?.("[data-cds-attachment]"));
    } catch { return false; }
  };

  const onPointerDown = event => {
    if (event.button !== 0 || !state.editorRoot) return;
    // Любое новое нажатие обесценивает отложенный шаг предыдущего клика: иначе
    // «щёлкнул и сразу потянул» доводит поле руками до нужной ступени, а через
    // 260 мс таймер делает ещё один шаг прямо посреди тяги.
    cancelClickStep();
    state.moved = false;
    event.preventDefault();
    state.dragging = true;
    state.startY = event.clientY;
    // Снимок высоты на момент захвата. Дальше во время тяги живую геометрию не
    // трогаем: пороги, посчитанные от неё, опрокидывали бы решение обратно.
    // Свёрнутое поле — это ноль, и тяга вверх поднимает его с нуля.
    state.startHeight = state.stage === STAGE_COLLAPSED
      ? 0
      : (state.height ?? state.editorRoot.getBoundingClientRect().height);
    state.dragNatural = naturalHeight();
    // Снимок ленты на момент захвата: стояла внизу — вернём вниз по концу тяги.
    state.dragTail = tailScroller();
    state.dragTailDown = tailAtBottom(state.dragTail);
    document.documentElement.style.cursor = "ns-resize";
    document.documentElement.style.userSelect = "none";
    handle.dataset.dragging = "true";
    try { handle.setPointerCapture(event.pointerId); } catch {}
  };
  const onPointerMove = event => {
    if (!state.dragging || !state.editorRoot) return;
    event.preventDefault();
    // Дрожь руки на пару точек — это всё ещё клик, а не перетаскивание.
    if (Math.abs(event.clientY - state.startY) > CLICK_SLACK) state.moved = true;
    // Всё решает курсор: desired — это снимок высоты плюс пройденный мышью путь,
    // живой геометрии здесь нет ни в одном пороге. Ступени разведены
    // гистерезисом, поэтому на границе они не дребезжат.
    const desired = state.startHeight - (event.clientY - state.startY);
    const natural = state.dragNatural;
    // Протянул заметно ниже минимума — значит хотел убрать поле совсем. Тягу не
    // обрываем: обратным движением вверх поле возвращается тем же жестом.
    if (state.stage !== STAGE_COLLAPSED && desired < MIN_HEIGHT - COLLAPSE_DRAG_SLACK) {
      setStage(STAGE_COLLAPSED);
      return;
    }
    // Свёрнутое ждёт минимума, дальше поле идёт за курсором с первой же точки.
    if (state.stage === STAGE_COLLAPSED && desired <= MIN_HEIGHT) return;
    // Высота непрерывная (#11693, Элвис 05.11: «оно же ниже должно иметь возможность встать… и полностью
    // разворачиваться»): и ниже своей высоты Claude — текст прокрутится (у корня overflow-y:auto), и выше. Своя
    // высота Claude — упор: в его пределах ступень «обычная», подмены нет; выйти из упора дальше, чем войти, — без дрожи.
    const snap = state.stage === STAGE_NORMAL ? STAGE_DRAG_SLACK : STAGE_DRAG_SLACK / 2;
    if (Math.abs(desired - natural) <= snap) { setStage(STAGE_NORMAL); return; }
    if (state.stage !== STAGE_STRETCHED) { setStage(STAGE_STRETCHED, { height: desired }); return; }
    state.height = clampHeight(desired);
    applyHeight();
    layout();
  };

  // Одиночный клик — шаг по лестнице: полоску разворачивает до обычной высоты,
  // любое развёрнутое поле сворачивает. Шаг отложен: второй клик двойного
  // приходит сюда же, и без задержки каждый двойной клик успевал бы сначала
  // сделать лишний шаг.
  //
  // Открывать поле на три фиксированные строки (#5868) пробовали 12.09 и сняли
  // в тот же день: жёсткая высота воюет с вложениями. Стоило положить в поле
  // пять скриншотов, как блок ввода перестал влезать в окно, trimToViewport
  // подрезал высоту, Claude перерисовывал вложения — и низ окна запрыгал вверх-
  // вниз (слово Элвиса 12.09 19:00). Ограничивать высоту надо не подменой
  // height, а потолком max-height — это отдельная задача.
  const cancelClickStep = () => {
    if (!state.clickTimer) return;
    clearTimeout(state.clickTimer);
    state.clickTimer = 0;
  };
  track(cancelClickStep);
  const onClick = event => {
    // Полоску только что тащили — это не клик. Отложенный шаг гасим и здесь:
    // после длинной тяги Chromium присылает click с detail=1, и без отмены поле
    // сделало бы лишний шаг сразу после того, как его растянули рукой.
    if (state.moved) { state.moved = false; cancelClickStep(); return; }
    event.preventDefault();
    cancelClickStep();
    if (event.detail > 1) return;
    // Shift — тот же шаг, но всеми окнами сразу (#6900). Второго клика тут не
    // ждём вовсе: двойным кликом по всем окнам никто не целится, а задержка на
    // общей команде читалась бы как «не сработало».
    if (event.shiftKey === true) { railStep(true); return; }
    state.clickTimer = setTimeout(() => {
      state.clickTimer = 0;
      // За 260 мс ожидания всё могло измениться: началась новая тяга или
      // экземпляр сняли — тогда шаг свернул бы поле, а полоски для возврата уже
      // нет.
      if (state.dragging || !state.alive) return;
      railStep(false);
    }, CLICK_STEP_DELAY);
  };

  // Дубли у краёв окна (#6743): тот же шаг, что и одиночный клик по основной
  // полоске, но без задержки на двойной — за них не тянут и не «двоят», Элвис
  // жмёт их подряд («прижал, нажал, прижал, нажал»).
  const onSuperClick = event => {
    event.preventDefault();
    cancelClickStep();
    if (!state.alive) return;
    // Shift — команда всем окнам Claude разом (#6900).
    railStep(event.shiftKey === true);
  };
  HATCH && Object.assign(HATCH, { setStage });

