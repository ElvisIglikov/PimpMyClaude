  // ---- 12т³. Прятать код и планы (#7976, контракт К-HC) ---------------------
  // Слово Элвиса: «код пишет: Edited, Handoff Plan ... программного кода куски. Убрать эти, чтобы код вот этот
  // вообще не писался ... эти виджеты, как настройку, убрать ... И так дефицит внимания». Инструменты и список правок
  // прячет «Прятать инструменты» (3а, К-B1); здесь — длинный код законченных ответов: блок кода Claude
  // (.epitaxy-codeblock, текст и язык — из его пропсов {text, lang, rawLang}, как у 12с и 12т) длиннее
  // HIDE_CODE_LINES строк сворачивается в строку «Код · 24 строки ▸». Нажатие, Enter, пробел — раскрыть и свернуть,
  // Esc на раскрытой — свернуть. Раскрытое помнится по тексту, пока окно открыто (лента виртуальная).
  // Не трогаем: идущий ответ, блоки без языка или «text» («→ в чат», блок передачи), команды (▶ 12т и Run Claude —
  // runCommandOf/runComplexOf), блок передачи «ОТКРОЙ НОВЫЙ ЧАТ» с любым языком и блок с кнопкой 12к за ним, код под
  // заголовками нажималок 12с (ВЫБОР, СДЕЛАЙ, «Нужен…»), инструменты (TurnStatus), сообщения человека, поле ввода,
  // карточки разрешения и диалоги. Признаки — по устройству блока, а не по кнопкам: кнопки 12с ставит позже, на своём
  // тике, и по ним вышло бы «свернул → развернул». План законченного ответа (инструмент ExitPlanMode, опознаётся по
  // пропсам — ниже) — той же строкой «План · N пунктов ▸»; план, что ждёт одобрения, не трогаем.
  // Строка — первым ребёнком внутри узла Claude (не соседом: в теле ответа flex с зазором, сосед и пустой блок дали бы
  // лишний зазор). Остальные дети узла — высота 0 и прозрачность (как К-CA), не display и не visibility: innerText
  // ответа прежний — его читают полоса 2б, рамка «ждут твоего слова» и «Обкэшить». Подпись — из атрибута (копия и
  // выделение её не видят). Сверка — в колбэке своего наблюдателя, до отрисовки; наблюдатель живёт, только пока
  // настройка включена. Команда `hide-code` {on:"true"|"false"} всем окнам; localStorage["myclaude.hideCode"]:
  // "1" — включено, иначе выключено (по умолчанию выключено: команда копирует из ответов код).
  const HIDE_CODE_KEY = "myclaude.hideCode";
  const HIDE_CODE_ATTRIBUTE = "data-myclaude-hide-code";
  const HIDE_CODE_FOLD = "data-myclaude-code-fold";
  const HIDE_CODE_LABEL = "data-myclaude-code-label";
  const HIDE_CODE_HIDDEN = "data-myclaude-code-hidden";
  const HIDE_CODE_LINES = 6;
  const HIDE_CODE_KEEP = 200;
  const HIDE_CODE_SKIP = '.epitaxy-user-turn,[contenteditable="true"],[data-cds="TurnStatus"],.epitaxy-approval-card,[role="dialog"],[role="alertdialog"]';
  const HIDE_CODE_LIVE = '[data-is-streaming="true"],[data-perf-row-streaming="true"]';
  const HIDE_CODE_MARKS = "[data-is-streaming],[data-perf-row-streaming]";
  // Планы (ExitPlanMode). Разметку карточки живьём не снимали (probe.js исполнителю запрещён); по коду Claude (бандл
  // 19.10) инструмент плана — объект {id, name:"ExitPlanMode", input:{plan, planFilePath}, status}, строка ленты и
  // карточка получают его пропсом. Опознаём только по нему и только у компонентов, чей корень — сам узел-кандидат
  // ([data-item-key], [data-cds="Card"] и их первый ребёнок): от волокна узла вверх до волокна родителя в DOM — выше
  // лежат пропсы соседей. Не опознали — не трогаем. Группу инструментов (TurnStatus, строка «Proposed plan») не трогаем:
  // законченную прячет К-B1, а наша role=button в группе сломала бы его отбор.
  const HIDE_CODE_PLAN_TOOL = "ExitPlanMode";
  const HIDE_CODE_PLAN_HOPS = 8;
  const HIDE_CODE_PLAN_CANDIDATES = '[data-item-key],[data-cds="Card"]';
  const HIDE_CODE_DECISION = '.epitaxy-approval-card,[data-approval-card-root],[role="dialog"],[role="alertdialog"],form,textarea,input,select';
  const HIDE_CODE_WATCH = `.epitaxy-codeblock,${RUN_ROW_SELECTOR},${HIDE_CODE_PLAN_CANDIDATES},.epitaxy-approval-card,${WORKING_SELECTOR}`;
  const hideCode = { observer: null, entries: new Map(), open: new Map(), seen: new WeakMap(), plans: new WeakMap() };

  const hideCodeOn = () => {
    try { return localStorage.getItem(HIDE_CODE_KEY) === "1"; } catch { return false; }
  };
  // Что нужно на проход: есть ли на странице метки потока, последняя строка ответа, идёт ли ход, нажималки строк.
  const hideCodeContext = () => {
    const ctx = { nazh: new Map() };
    try { ctx.marks = Boolean(document.querySelector(HIDE_CODE_MARKS)); } catch { ctx.marks = false; }
    try {
      const rows = document.querySelectorAll(RUN_ROW_SELECTOR);
      ctx.lastRow = rows[rows.length - 1] ?? null;
    } catch { ctx.lastRow = null; }
    ctx.working = pageWorking();
    return ctx;
  };
  // Ответ ещё пишется: метка Claude у сообщения или строки; меток на странице нет вовсе — последний ответ, пока идёт
  // ход (как foldLive 12ф).
  const hideCodeLive = (node, ctx) => {
    try { if (node.closest(HIDE_CODE_LIVE)) return true; } catch { return true; }
    if (ctx.marks) return false;
    return ctx.working && node.closest?.(RUN_ROW_SELECTOR) === ctx.lastRow;
  };
  // Узлы нажималок строки ответа: блоки передачи «ОТКРОЙ НОВЫЙ ЧАТ» (любой язык) и всё под заголовками 12с.
  const hideCodeNazhNodes = row => {
    const out = new Set();
    try { for (const node of nazhHandoffCodes(row)) out.add(node); } catch {}
    let heads = [];
    try { heads = [...row.querySelectorAll(ATTN_HEAD_SELECTOR)]; } catch { heads = []; }
    for (const head of heads) {
      try { if (nazhKind(head)) for (const node of nazhBlock(head)) out.add(node); } catch {}
    }
    return out;
  };
  const hideCodeNazh = (block, ctx) => {
    if (block.nextElementSibling?.hasAttribute?.(CONTINUE_ATTRIBUTE)) return true;
    try { if (block.querySelector(`[${NAZH_BUTTON_ATTRIBUTE}],[${RUN_ATTRIBUTE}]`)) return true; } catch { return true; }
    const row = block.closest?.(RUN_ROW_SELECTOR);
    if (!row) return true;
    if (!ctx.nazh.has(row)) ctx.nazh.set(row, hideCodeNazhNodes(row));
    for (const node of ctx.nazh.get(row)) if (node === block || node.contains?.(block)) return true;
    return false;
  };
  // Блок кода, который сворачиваем: {kind:"code", key, count}; иначе null. Число строк и язык считаются заново,
  // только когда сменился объект пропсов блока.
  const hideCodeInfo = (block, ctx = hideCodeContext()) => {
    if (!block?.isConnected || !block.closest?.(RUN_ROW_SELECTOR)) return null;
    // Обвязка инструментов Claude ([data-find-omitted]: список правок, фоновые команды) — не ответ; наша role=button
    // там сломала бы отбор К-B1 (HIDE_TOOLS_DECISION).
    try { if (block.closest(`${HIDE_CODE_SKIP},[data-find-omitted]`)) return null; } catch { return null; }
    if (state.composerBlock?.contains?.(block) || hideCodeLive(block, ctx)) return null;
    const props = runPropsOf(block);
    if (!props) return null;
    let seen = hideCode.seen.get(block);
    if (!seen || seen.props !== props) {
      const text = String(props.text ?? "").replace(/\s+$/, "");
      const tag = String(props.rawLang ?? props.lang ?? "").trim().toLowerCase();
      const count = text ? text.split("\n").length : 0;
      const long = count > HIDE_CODE_LINES && tag !== "" && tag !== "text" && !runCommandOf(props) && !runComplexOf(props);
      seen = { props, long, count, key: `code:${text}` };
      hideCode.seen.set(block, seen);
    }
    if (!seen.long || hideCodeNazh(block, ctx)) return null;
    return { kind: "code", key: seen.key, count: seen.count };
  };

  // Инструмент плана в пропсах: сам объект или его поле tool | item | row | entry | data | call.
  const hideCodePlanTool = props => {
    if (!props || typeof props !== "object") return null;
    for (const item of [props, props.tool, props.item, props.row, props.entry, props.data, props.call]) {
      if (!item || typeof item !== "object" || (item.name ?? item.toolName) !== HIDE_CODE_PLAN_TOOL) continue;
      if (typeof item.input?.plan === "string" && item.input.plan.trim()) return item;
    }
    return null;
  };
  // Только компоненты, чей корень — сам узел: вверх по волокну до первого чужого узла DOM. Пересчёт — когда сменились
  // пропсы самого узла.
  const hideCodePlanOf = node => {
    const host = chatFiberOf(node);
    const props = host?.memoizedProps;
    const seen = hideCode.plans.get(node);
    if (seen && seen.props === props) return seen.tool;
    let tool = null;
    let fiber = host;
    for (let hop = 0; fiber && hop < HIDE_CODE_PLAN_HOPS && !tool; hop += 1, fiber = fiber.return) {
      if (hop > 0 && fiber.stateNode?.nodeType === 1) break;
      tool = hideCodePlanTool(fiber.memoizedProps);
    }
    hideCode.plans.set(node, { props, tool });
    return tool;
  };
  // Пункты плана: строки списков верхнего уровня (вне ```-блоков); списков нет — заголовки, кроме названия плана
  // (заголовок в самом начале, крупнее всех остальных).
  const hideCodePlanCount = plan => {
    const text = String(plan);
    let fence = false;
    let items = 0;
    const heads = [];
    for (const line of text.split("\n")) {
      if (/^\s*(?:```|~~~)/.test(line)) { fence = !fence; continue; }
      if (fence) continue;
      if (/^(?:[-*+]|\d{1,3}[.)])\s+\S/.test(line)) items += 1;
      const head = /^(#{1,6})\s+\S/.exec(line);
      if (head) heads.push(head[1].length);
    }
    if (items) return items;
    const first = text.split("\n").find(line => line.trim()) ?? "";
    const titled = heads.length > 0 && /^#{1,6}\s/.test(first) && heads.slice(1).every(level => level > heads[0]);
    return titled ? heads.length - 1 : heads.length;
  };
  // План ждёт одобрения: инструмент ещё идёт или ждёт; ожидающий ExitPlanMode этого чата в сторе разрешений (как
  // roamVerdict 12е); запасной признак — карточка разрешения у поля, а план в последней строке ответа.
  const hideCodePlanWaiting = (tool, node, ctx) => {
    const status = String(tool.status ?? "");
    if (status === "running" || status === "awaiting_approval" || tool.live === true) return true;
    if (!ctx.waiting) {
      ctx.waiting = { ids: new Set(), any: false, card: false };
      let list = null;
      try { list = roamPermStore?.getState?.()?.permissionsBySessionId?.[myChatId()]; } catch { list = null; }
      for (const item of Array.isArray(list) ? list : []) {
        if (item?.toolName !== HIDE_CODE_PLAN_TOOL || (item.status != null && item.status !== "pending")) continue;
        ctx.waiting.any = true;
        if (item.toolUseId) ctx.waiting.ids.add(item.toolUseId);
      }
      try { ctx.waiting.card = Boolean(document.querySelector(".epitaxy-approval-card")); } catch {}
    }
    if (tool.id && ctx.waiting.ids.has(tool.id)) return true;
    return (ctx.waiting.any || ctx.waiting.card) && node.closest?.(RUN_ROW_SELECTOR) === ctx.lastRow;
  };
  // Планы законченных ответов: [{node, kind:"plan", key, count}] в порядке ленты, внешний узел сильнее внутреннего.
  const hideCodePlans = (ctx = hideCodeContext()) => {
    const list = [];
    let nodes = [];
    try { nodes = [...document.querySelectorAll(HIDE_CODE_PLAN_CANDIDATES)]; } catch { return list; }
    for (const own of nodes) {
      for (const node of [own, own.firstElementChild]) {
        if (!node || node.hasAttribute?.(HIDE_CODE_FOLD) || list.some(item => item.node.contains(node))) continue;
        if (!node.closest?.(RUN_ROW_SELECTOR) || state.composerBlock?.contains?.(node)) continue;
        try { if (node.closest(HIDE_CODE_SKIP) || node.closest(`[${HIDE_TOOLS_MARK}]`)) continue; } catch { continue; }
        const tool = hideCodePlanOf(node);
        if (!tool || hideCodeLive(node, ctx)) continue;
        try { if (node.querySelector(HIDE_CODE_DECISION)) continue; } catch { continue; }
        if (hideCodePlanWaiting(tool, node, ctx)) continue;
        const plan = String(tool.input.plan);
        list.push({ node, kind: "plan", key: `plan:${plan}`, count: hideCodePlanCount(plan) });
        break;
      }
    }
    return list;
  };

  const hideCodeRow = () => {
    const row = document.createElement("div");
    row.setAttribute(HIDE_CODE_FOLD, "closed");
    row.setAttribute("role", "button");
    row.setAttribute("tabindex", "0");
    return row;
  };
  const hideCodePaint = entry => {
    const open = hideCode.open.get(entry.key) === true;
    const what = entry.kind === "plan" ? "План" : "Код";
    const amount = entry.kind === "plan"
      ? (entry.count > 0 ? `${entry.count} ${usagePlural(entry.count, "пункт", "пункта", "пунктов")}` : "")
      : `${entry.count} ${usagePlural(entry.count, "строка", "строки", "строк")}`;
    foldSet(entry.row, HIDE_CODE_FOLD, open ? "open" : "closed");
    foldSet(entry.row, HIDE_CODE_LABEL, `${amount ? `${what} · ${amount}` : what} ${open ? "▾" : "▸"}`);
    foldSet(entry.row, "aria-expanded", open ? "true" : "false");
    foldSet(entry.row, "aria-label", `${amount ? `${what}, ${amount}` : what} — ${open ? "свернуть" : "развернуть"}`);
    foldSet(entry.node, HIDE_CODE_HIDDEN, open ? "open" : "closed");
  };
  // Что свернуть сейчас: узел Claude → {kind, key, count}.
  const hideCodeWant = () => {
    const want = new Map();
    if (!hideCodeOn()) return want;
    const ctx = hideCodeContext();
    const plans = hideCodePlans(ctx);
    for (const plan of plans) want.set(plan.node, plan);
    let blocks = [];
    try { blocks = [...document.querySelectorAll(".epitaxy-codeblock")]; } catch { blocks = []; }
    for (const block of blocks) {
      if (plans.some(plan => plan.node.contains(block))) continue;
      const info = hideCodeInfo(block, ctx);
      if (info) want.set(block, info);
    }
    return want;
  };
  // Разметка ровно по тому, что сейчас в ленте: строки на месте, ушедшие сняты. Пишем только изменения (foldSet) и
  // вставляем только строку не на месте — свои вставки наблюдатель пропускает.
  const hideCodeSync = () => {
    if (!state.alive) return;
    const want = hideCodeWant();
    for (const [node, entry] of [...hideCode.entries]) {
      if (want.has(node)) continue;
      try { entry.row.remove(); } catch {}
      try { node.removeAttribute(HIDE_CODE_HIDDEN); } catch {}
      hideCode.entries.delete(node);
    }
    for (const [node, info] of want) {
      let entry = hideCode.entries.get(node);
      if (!entry) {
        entry = { node, row: hideCodeRow() };
        hideCode.entries.set(node, entry);
      }
      entry.kind = info.kind;
      entry.key = info.key;
      entry.count = info.count;
      hideCodePaint(entry);
      if (entry.row.parentNode !== node || node.firstChild !== entry.row) {
        try { node.insertBefore(entry.row, node.firstChild); } catch {}
      }
    }
  };
  const hideCodeToggle = (entry, open = hideCode.open.get(entry.key) !== true) => {
    hideCode.open.delete(entry.key);
    if (open) {
      hideCode.open.set(entry.key, true);
      while (hideCode.open.size > HIDE_CODE_KEEP) hideCode.open.delete(hideCode.open.keys().next().value);
    }
    for (const item of hideCode.entries.values()) if (item.key === entry.key) hideCodePaint(item);
    // Свернул длинный блок — строка могла уехать выше экрана: вернуть её в поле зрения (как 12ф²).
    if (!open) { try { entry.row.scrollIntoView?.({ block: "nearest" }); } catch {} }
  };
  const hideCodeEntryOf = target => {
    const row = target?.closest?.(`[${HIDE_CODE_FOLD}]`);
    if (!row) return null;
    for (const entry of hideCode.entries.values()) if (entry.row === row) return entry;
    return null;
  };
  // Нажатие — на захвате документа, до Claude; двойной щелчок — одно нажатие.
  const onHideCodeClick = event => {
    if (!state.alive) return;
    const entry = hideCodeEntryOf(event?.target);
    if (!entry) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    if (Number(event.detail) > 1) return;
    try { hideCodeToggle(entry); } catch {}
  };
  // Enter и пробел — переключить; Esc — свернуть раскрытую (свёрнутой Esc не нужен — уходит дальше, Claude).
  const onHideCodeKey = event => {
    if (!state.alive) return;
    const key = event?.key;
    if (key !== "Enter" && key !== " " && key !== "Spacebar" && key !== "Escape") return;
    const entry = hideCodeEntryOf(event.target);
    if (!entry) return;
    const open = hideCode.open.get(entry.key) === true;
    if (key === "Escape" && !open) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    try { hideCodeToggle(entry, key === "Escape" ? false : !open); } catch {}
  };
  // Отбор записей наблюдателя: проход нужен, когда в ленте появился или ушёл блок кода или строка ответа, внутри блока
  // поменялось содержимое, ответ дописан (метка потока), ушла карточка разрешения или кнопка стопа. Свои строки — мимо.
  // Правки внутри ответа, который ещё пишется, — тоже мимо: его не сворачиваем, а дописан — придёт метка потока.
  const hideCodeNeeds = records => {
    for (const record of records) {
      if (record.type === "attributes") return true;
      const target = record.target?.nodeType === 1 ? record.target : record.target?.parentElement;
      try { if (target?.closest(HIDE_CODE_LIVE)) continue; } catch {}
      const inBlock = Boolean(target?.closest?.(".epitaxy-codeblock"));
      if (record.type === "characterData") { if (inBlock) return true; continue; }
      for (const node of [...(record.addedNodes ?? []), ...(record.removedNodes ?? [])]) {
        if (node.nodeType !== 1) { if (inBlock) return true; continue; }
        if (node.hasAttribute?.(HIDE_CODE_FOLD)) continue;
        if (inBlock) return true;
        try { if (node.matches(HIDE_CODE_WATCH) || node.querySelector(HIDE_CODE_WATCH)) return true; } catch {}
      }
    }
    return false;
  };
  const hideCodeObserved = records => {
    if (!state.alive) return;
    try { if (hideCodeNeeds(records)) hideCodeSync(); } catch {}
  };
  const hideCodeMark = () => {
    const root = document.documentElement;
    if (hideCodeOn()) {
      foldSet(root, HIDE_CODE_ATTRIBUTE, "");
      if (!hideCode.observer) {
        hideCode.observer = new MutationObserver(hideCodeObserved);
        hideCode.observer.observe(root, { childList: true, subtree: true, characterData: true, attributes: true,
          attributeFilter: ["data-is-streaming", "data-perf-row-streaming"] });
      }
    } else {
      foldSet(root, HIDE_CODE_ATTRIBUTE, null);
      hideCode.observer?.disconnect();
      hideCode.observer = null;
    }
    hideCodeSync();
  };
  const hideCodeSet = value => {
    try { localStorage.setItem(HIDE_CODE_KEY, value ? "1" : "0"); } catch {}
    hideCodeMark();
  };

  // Прятать: высота 0 и прозрачность (как К-CA), без display:none и visibility — innerText прежний. Обёртка
  // display:contents (класс contents у Claude) высоту не берёт — ей блок. contain:paint обрезает потомков с
  // absolute/sticky (полоса Copy), pointer-events — чтобы невидимое не перехватывало нажатия. !important сильнее
  // анимаций входа ленты (раздел 2и).
  const HIDE_CODE_CLOSED = `html[${HIDE_CODE_ATTRIBUTE}] [${HIDE_CODE_HIDDEN}="closed"]`;
  lateRules.push(
    `${HIDE_CODE_CLOSED}{gap:0 !important}`,
    `${HIDE_CODE_CLOSED}>:not([${HIDE_CODE_FOLD}]){height:0 !important;min-height:0 !important;max-height:0 !important;margin:0 !important;padding:0 !important;border:0 !important;overflow:hidden !important;opacity:0 !important;pointer-events:none !important;contain:paint !important;animation:none !important;transition:none !important}`,
    `${HIDE_CODE_CLOSED}>.contents:not([${HIDE_CODE_FOLD}]){display:block !important}`,
    // Строка — как заголовок свёртки 12ф, но тише: цвет второстепенного текста, шрифт текста ответа (внутри блока
    // кода иначе достался бы моноширинный).
    `[${HIDE_CODE_FOLD}]{display:block;box-sizing:border-box;width:fit-content;max-width:100%;margin:0;padding:2px 8px 2px 4px;border-radius:6px;color:var(--cds-text-secondary, inherit);font-family:var(--font-claude-response, -apple-system, system-ui, sans-serif);font-size:inherit;font-style:normal;font-weight:500;line-height:1.5;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;cursor:pointer;user-select:none;-webkit-user-select:none;-webkit-app-region:no-drag;transition:background-color .15s}`,
    `[${HIDE_CODE_FOLD}]::after{content:attr(${HIDE_CODE_LABEL})}`,
    `[${HIDE_CODE_FOLD}]:hover{background:rgba(127,127,127,.14)}`,
    `[${HIDE_CODE_FOLD}]:active{background:rgba(127,127,127,.24)}`,
    `[${HIDE_CODE_FOLD}]:focus-visible{outline:2px solid rgba(245,158,11,.7);outline-offset:1px}`,
    `[${HIDE_CODE_FOLD}="open"]{margin-bottom:2px}`,
    `@media (prefers-reduced-motion: reduce){[${HIDE_CODE_FOLD}]{transition:none}}`,
  );

  // Сироты прошлой установки — до первого прохода.
  try {
    for (const node of document.querySelectorAll(`[${HIDE_CODE_FOLD}]`)) node.remove();
    for (const node of document.querySelectorAll(`[${HIDE_CODE_HIDDEN}]`)) node.removeAttribute(HIDE_CODE_HIDDEN);
  } catch {}
  hideCodeMark();
  on(document, "click", onHideCodeClick, true);
  on(window, "keydown", onHideCodeKey, true);
  on(window, "storage", event => { if (event.key === HIDE_CODE_KEY || event.key === null) hideCodeMark(); });
  track(() => {
    hideCode.observer?.disconnect();
    hideCode.observer = null;
    for (const [node, entry] of hideCode.entries) {
      try { entry.row.remove(); } catch {}
      try { node.removeAttribute(HIDE_CODE_HIDDEN); } catch {}
    }
    hideCode.entries.clear();
    try { document.documentElement.removeAttribute(HIDE_CODE_ATTRIBUTE); } catch {}
  });
  // «Прятать код и планы» (#7976, К-HC): включено ли, сколько блоков кода и планов свёрнуто сейчас (раскрытые — нет).
  statusPart("hideCode", () => {
    const on = hideCodeOn();
    let folded = 0;
    let plans = 0;
    if (on) {
      for (const entry of hideCode.entries.values()) {
        if (!entry.node.isConnected || hideCode.open.get(entry.key) === true) continue;
        if (entry.kind === "plan") plans += 1;
        else folded += 1;
      }
    }
    return { on, folded, plans };
  });
  HATCH && Object.assign(HATCH, { hideCodeSync, hideCodeInfo, hideCodeNeeds });
