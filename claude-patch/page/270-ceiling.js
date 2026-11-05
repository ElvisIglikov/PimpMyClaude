  // ---- 11. Разворот до потолка -------------------------------------------
  // Пустой чат: разговора ещё нет, и над полем висит шапка с приветствием и
  // выбором проекта. В Claude Code своя разметка разговора, без классов обычного
  // чата (замер донора: ноль .font-claude-response даже посреди переписки),
  // поэтому примет несколько — см. CHAT_STARTED_SELECTOR. Прежние три приметы
  // в сборке 1.40609.1 не срабатывали ни одна, и разговор считался пустым чатом:
  // из-за этого двойной клик целился в «низ шапки», найденный вплотную к полю,
  // и не растягивал поле вовсе.
  const isFreshChat = () => document.querySelectorAll(CHAT_STARTED_SELECTOR).length === 0;
  // Низ шапки пустого чата: самый нижний осмысленный блок над рамкой ввода. Не
  // по классам — Claude их перегенерирует, — а по геометрии: строка выбора
  // проекта стоит прямо над полем и попадает сюда сама.
  const freshHeaderBottom = () => {
    if (state.shell == null) return null;
    const limit = state.shell.getBoundingClientRect().top - 2;
    let bottom = null;
    for (const node of document.querySelectorAll("main h1,main h2,main button,main a,main p")) {
      // Сам блок ввода шапкой не является ни одной своей частью.
      if (state.composerBlock?.contains(node)) continue;
      const rect = node.getBoundingClientRect();
      if (rect.height < 12 || rect.width < 40) continue;
      if (rect.bottom > limit || rect.top < SAFE_TOP_INSET) continue;
      if (bottom == null || rect.bottom > bottom) bottom = rect.bottom;
    }
    return bottom == null ? null : Math.round(bottom + 12);
  };
  // Примета вида окна для замеренного упора: в пустом чате и в разговоре, в
  // узком окне и в широком контейнер держит верх поля на разной высоте, и чужой
  // замер только навредил бы.
  const ceilingFloorKey = () =>
    `${isFreshChat() ? 1 : 0}:${Math.round(innerWidth)}x${Math.round(innerHeight)}`;
  const ceilingFloorTop = () => {
    const memo = state.ceilingFloor;
    return memo != null && memo.key === ceilingFloorKey() ? memo.top : null;
  };
  // Годится ли отметка в цель. Мерим не «насколько выше нынешнего верха» (эта
  // разница у растянутого поля своя, и atCeiling с разворотом разошлись бы), а
  // сколько места отметка оставляет полю до низа рамки: низ рамки прибит к
  // строке модели и от ступени не зависит. Меньше обычной высоты с запасом —
  // отметка вырожденная, и целиться в неё нельзя.
  const aimUsable = aim => {
    if (aim == null || !state.shell?.isConnected) return false;
    return state.shell.getBoundingClientRect().bottom - aim >= naturalHeight() + CEILING_MIN_ROOM;
  };
  // Куда целимся верхом поля: обычно в низ титульной полосы, в пустом чате — в
  // низ шапки, но только пока шапка оставляет полю место. Одна точка на всех:
  // atCeiling и разворот обязаны считать одинаково, иначе двойной клик начинает
  // мигать между «растянуть» и «вернуть обычную».
  const stretchLimit = () => {
    const limit = topLimit();
    if (!isFreshChat()) return limit;
    const header = freshHeaderBottom();
    return header != null && header > limit && aimUsable(header) ? header : limit;
  };
  // Верх поля уже у потолка — значит тянуть дальше некуда. Мерим не до
  // расчётного потолка, а до замеренного упора контейнера: выше него верх поля
  // не поднимется, сколько ни тяни, и без этого повторный двойной клик перестал
  // бы возвращать обычную высоту — намеренный недобор съел бы весь допуск.
  const atCeiling = () => {
    if (state.shell == null || state.stage !== STAGE_STRETCHED) return false;
    const limit = stretchLimit();
    const floor = ceilingFloorTop();
    // Пол берём без aimUsable: в очень низком окне отвергнутый пол уводил бы цель на
    // титульную полосу, и растянутое поле никогда не считалось бы «у потолка».
    const aim = floor != null && floor > limit ? floor : limit;
    return state.shell.getBoundingClientRect().top <= aim + CEILING_UNDERSHOOT + 10;
  };
  // До упора — одним шагом и с намеренным недобором. Формуле maximumHeight()
  // верить нельзя: она считает, что прибавка высоты целиком уходит вверх, а
  // контейнер Claude верх дальше своего края не пускает, и лишние точки уходят
  // вниз, выдавливая строку модели. Поэтому целимся в ранее замеренный упор, а
  // промах разбираем по факту: второй шаг разрешён только на грубом промахе и
  // всегда последний — лесенки из трёх подходов быть не должно.
  const stretchToCeiling = ceilingTop => {
    const shell = state.shell;
    if (shell == null) return;
    // setStage перерисовывает низ окна, и рамка под руками может смениться или
    // исчезнуть. Дальше меряем только ту, с которой начинали, и на каждой смене
    // уходим: замеры от чужой рамки бессмысленны, а от исчезнувшей — падение.
    const gone = () => state.shell !== shell || !shell.isConnected;
    const limit = ceilingTop ?? topLimit();
    const floor = ceilingFloorTop();
    const aim = floor != null && floor > limit && aimUsable(floor) ? floor : limit;
    const before = shell.getBoundingClientRect().top;
    // Опорная высота годится только осмысленная: свёрнутое поле даёт нули, и от
    // нуля цель вышла бы вдвое больше нужного.
    const measured = state.editorRoot?.isConnected
      ? Math.round(state.editorRoot.getBoundingClientRect().height) : 0;
    const base = state.height ?? (measured >= MIN_HEIGHT ? measured : naturalHeight());
    const target = Math.max(base, Math.round(base + (before - aim) - CEILING_UNDERSHOOT));
    setStage(STAGE_STRETCHED, { height: target });
    state.stretchSteps = 1;
    if (gone()) return;
    // clampHeight внутри setStage мог урезать запрошенное — дальше считаем по
    // тому, что реально применилось.
    const applied = state.height ?? target;
    const after = shell.getBoundingClientRect().top;
    const grew = applied - base;
    const moved = before - after;
    // Прибавка, не ушедшая вверх. Она и показывает настоящий упор контейнера.
    const wasted = grew - moved;
    if (wasted > CEILING_WASTE_SLACK) {
      // Упор запоминаем, только если рамка вообще сдвинулась. Замер по
      // неподвижной рамке равен её нынешнему верху, а он потом идёт целью —
      // и разворот запирается на обычной высоте навсегда. Причин не сдвинуться
      // хватает и без упора контейнера: черновик выше поля, подрезка по низу
      // окна, чужая раскладка. Тогда высоту так же отдаём назад, но память
      // чистим — следующая попытка начнёт с чистого листа.
      state.ceilingFloor = moved > 0 ? { key: ceilingFloorKey(), top: Math.round(after) } : null;
      // Контейнер не пустил заметно выше: поджимаем ровно на пустоту — один раз
      // и всё. В следующий раз этот же упор возьмётся из памяти.
      setStage(STAGE_STRETCHED, { height: Math.max(base, applied - wasted - CEILING_UNDERSHOOT) });
      state.stretchSteps = 2;
    } else if (grew > 0 && after - limit > CEILING_RETRY_GAP) {
      // Прибавка уходила вверх целиком, а до настоящего потолка всё равно
      // далеко. Меряем именно до limit, а не до запомненного упора: иначе
      // однажды записанная память навсегда запирает разворот низко. Раз места
      // оказалось больше, память устарела — стираем её.
      state.ceilingFloor = null;
      setStage(STAGE_STRETCHED, { height: applied + (after - limit) - CEILING_UNDERSHOOT });
      state.stretchSteps = 2;
    }
    if (gone()) return;
    state.ceiling = state.height ?? applied;
    // Отступление от донора: он писал высоту только по концу тяги, и разворот
    // двойным кликом перезагрузку страницы не переживал. Раз высота теперь
    // сессионная (своя у каждого окна), сохранить её здесь ничего не стоит.
    storeHeight(state.height);
  };
  // Разворот до упора одним движением. Вынесен отдельно от обработчика двойного
  // клика: тем же путём поле разворачивает вставка «Обкэшить».
  const stretchToMax = () => {
    // Пока поле свёрнуто, мерить нечего — сначала молча возвращаем обычный вид.
    // Именно обычный, а не растянутый: setStage(STRETCHED) без высоты подставил
    // бы запомненный чужой размер, и это лишний скачок на глазах.
    if (state.stage === STAGE_COLLAPSED) setStage(STAGE_NORMAL, { silent: true });
    // В пустом чате шапку не съедаем: над полем стоят приветствие и кнопки
    // проекта, и без них непонятно даже, в какой папке откроется разговор.
    // Низ шапки меряем уже по возвращённому полю: у свёрнутого верх стоит ниже,
    // и в замер попали бы блоки, которые поле собой закроет. Разбор «шапка или
    // титульная полоса» — в stretchLimit(), общий с atCeiling.
    stretchToCeiling(stretchLimit());
    layout();
  };
  // Двойной клик — сразу максимум, без лесенки. Ступени остались за одиночным
  // кликом и тягой. Повторный двойной клик по уже развёрнутому до упора полю
  // возвращает обычную высоту: иначе из максимума не выйти тем же жестом.
  // «Уже до упора» решаем по верху поля, а не по высоте: у высоты цифра пляшет
  // от прохода к проходу, а верх на упоре стоит намертво.
  const onDoubleClick = event => {
    event.preventDefault();
    cancelClickStep();
    state.moved = false;
    if (atCeiling()) { setStage(STAGE_NORMAL); return; }
    stretchToMax();
  };

