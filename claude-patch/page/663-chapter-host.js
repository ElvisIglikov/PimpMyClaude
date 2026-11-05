  // ---- 12х²ᵈ. Своя дорожка глав, когда у Claude её нет (пожелания 03.11.2026, п. 9) --------
  // Слово Оли 03.11.2026: «на Windows при идущем чате есть заголовки-зарубки, на Маке их нет». В PimpWinTray своего
  // элемента нет: зарубки — родная дорожка Claude `.epitaxy-toc > nav` (там раздел 12х² — старая копия этого, без
  // своих глав). Claude 4.4212 рисует её, только если в чате есть глава не от сессии: модель вызвала mark_chapter
  // или человек закрепил ответ (`chapters.some(c => c.source !== "session")`). На Маке Оли таких вызовов нет ни
  // одного, поэтому нет и дорожки, а свои главы раздела 660 («каждый ответ — глава», #9757) встают только в неё.
  //  - Нет родной дорожки и в ленте не меньше CH_HOST_MIN ответов с названием — страница ставит пустую основу той же
  //    формы (.epitaxy-toc > nav > ol[aria-hidden] + div > ol) в тело панели чата. Дальше всё делает 660: свои главы,
  //    меню, галочки, закладки, текущая глава, переход; 662 ставит полоски посередине.
  //  - Появилась родная дорожка — основа снята, свои главы переезжают в неё тем же проходом.
  //  - Классы полосок и строк — с дорожки Claude 4.4212 (родных строк, с которых их снял бы chOwnLook, здесь нет).
  //  - React основу не знает и не трогает; выбросит тело панели — она уйдёт с ним и встанет заново на проходе.
  const CH_HOST_ATTRIBUTE = "data-myclaude-ch-host";
  const CH_HOST_SELECTOR = `.epitaxy-toc[${CH_HOST_ATTRIBUTE}]`;
  const CH_HOST_PANEL = ".epitaxy-chat-panel-body";
  const CH_HOST_MIN = 2;
  const CH_HOST_LABEL = "Главы чата";
  const CH_HOST_LOOK = {
    line: "h-[8px] flex items-center",
    idle: "block h-[2px] rounded-full transition-[scale,background-color] duration-200 w-[calc(var(--chat-gutter)*3/8+2px)] origin-left scale-x-[calc(9/14)] bg-alpha-3",
    now: "block h-[2px] rounded-full transition-[scale,background-color] duration-200 w-[calc(var(--chat-gutter)*3/8+2px)] origin-left bg-alpha-8",
    button: "group/ch hit-row-main w-full flex items-center gap-sm px-1.25 h-control app-list-row rounded-[5px] text-start text-body hover:bg-fill-ghost-hover text-secondary hover:text-primary",
    bar: "block h-[2px] rounded-full shrink-0 w-[9px] bg-alpha-3",
    name: "flex-1 min-w-0",
  };
  const chHostState = { node: null, on: false, plan: 0, why: null };
  const chHostIs = nav => { try { return Boolean(nav?.parentElement?.hasAttribute(CH_HOST_ATTRIBUTE)); } catch { return false; } };
  const chHostDrop = () => {
    chHostState.node = null;
    chHostState.on = false;
    try { for (const node of document.querySelectorAll(CH_HOST_SELECTOR)) node.remove(); } catch {}
  };
  const chHostMake = () => {
    const host = document.createElement("div");
    host.className = "epitaxy-toc epitaxy-toc-fade-in";
    host.setAttribute(CH_HOST_ATTRIBUTE, "");
    const nav = document.createElement("nav");
    nav.setAttribute("aria-label", CH_HOST_LABEL);
    nav.setAttribute("tabindex", "0");
    const rail = document.createElement("ol");
    rail.setAttribute("aria-hidden", "true");
    const menu = document.createElement("div");
    menu.className = "rounded-card bg-surface-3 shadow-panel";
    const list = document.createElement("ol");
    list.setAttribute("role", "list");
    menu.appendChild(list);
    nav.append(rail, menu);
    host.appendChild(nav);
    return host;
  };
  // Ответов с названием в ленте — те же правила, что у своих глав 660; родных глав здесь нет.
  const chHostPlan = () => {
    const skip = new Set(workState.only);
    if (readState.busy) skip.add(readState.busy);
    return chOwnPlan(workState.entries, [], skip, chState.titles);
  };
  // Проход перед разметкой глав: основа стоит ровно тогда, когда родной дорожки нет и есть что показать.
  const chHostTick = () => {
    const off = why => { chHostState.why = why; if (chHostState.node || chHostState.on) chHostDrop(); };
    if (!themable || !state.alive) return off("не окно чата");
    const native = [...document.querySelectorAll(".epitaxy-toc")].some(node => !node.hasAttribute(CH_HOST_ATTRIBUTE));
    chHostState.plan = chHostPlan().length;
    if (native) return off("есть дорожка Claude");
    if (!chatKey()) return off("нет чата");
    if (chHostState.plan < CH_HOST_MIN) return off("мало ответов");
    const panel = readFeed()?.closest(CH_HOST_PANEL) ?? null;
    if (!panel) return off("нет тела панели");
    chHostState.why = null;
    chHostState.on = true;
    const host = chHostState.node;
    if (host?.parentNode === panel) return;
    if (host) { try { host.remove(); } catch {} }
    chHostState.node = chHostMake();
    panel.appendChild(chHostState.node);
  };
  chHostDrop();
  track(chHostDrop);
  // Форма дорожки Claude: классы своей основы не держим на случай новой сборки, ключевое — здесь.
  // Верх — общее правило .epitaxy-toc (ниже кнопок окна), вид полосок и меню — правила раздела 4.
  lateRules.push(
    `${CH_HOST_SELECTOR}{position:absolute;inset-inline-start:0;bottom:32px;z-index:11;width:var(--chat-gutter,32px);pointer-events:none}`,
    `${CH_HOST_SELECTOR}>nav{position:relative;height:100%;outline:none}`,
    `${CH_HOST_SELECTOR}>nav>ol[aria-hidden="true"]{display:flex;flex-direction:column;box-sizing:border-box;width:max-content;max-height:100%;margin:0;overflow:hidden;list-style:none;pointer-events:auto}`,
    `${CH_HOST_SELECTOR}>nav>div{position:absolute;display:flex;flex-direction:column;box-sizing:border-box;max-height:100%}`,
    `${CH_HOST_SELECTOR}>nav>div>ol{display:flex;flex:1;flex-direction:column;min-height:0;margin:0;overflow-y:auto;list-style:none}`,
  );
  statusPart("chHost", () => ({ on: chHostState.on, plan: chHostState.plan, why: chHostState.why }));
  HATCH && Object.assign(HATCH, { chHostTick, chHostIs, chHostState });
