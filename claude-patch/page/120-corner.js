  // ---- 2ж. Угол «Проект · чат» и главное окно без шапки (#7911, #7913, WF102) ----
  // #7911 (слово Элвиса 26.09, приоритет номер один): «чтобы всегда в правом углу
  // это место было занято под название проекта… заголовок чата — аккуратненько там
  // же справа… как плавающий элемент… фейд какой-то наложить». В КАЖДОМ окне Claude
  // правый верхний угол — своя плашка в body: имя проекта целиком, чат — сколько
  // влезет, хвост — многоточием; фон — сплошной цвет фона окна (тема). WF103,
  // решение 12 (слово Элвиса 27.09: «этот фейд… сильно отвлекает глаза… тем же
  // цветом, что и чат… полоску… к самому верху прижимать… текст… максимально
  // близко к верхнему краю»): без затухания, плашка у верхнего края окна. Мышь её не ловит, окно таскать не мешает (без app-region), слой
  // ниже меню Claude (у них z 50) и попапов Пимпа. Стили — в самом узле: CSP
  // страницы нашу таблицу может не пустить (довод раздела 2б).
  // Имя проекта — как у чипа закреплённых (pinnedFolderName: репозиторий, иначе
  // папка) по строке своего чата в списке слева; строки нет (попап, список свёрнут)
  // — подпись плашки проекта в шапке Claude: она показывает то же имя репозитория,
  // а узел шапки жив и в главном окне без шапки (он только сжат). Чат —
  // [data-pane-title]: в главном окне document.title — «Claude» (живьём 26.09).
  // Дубль имени проекта в шапке прозрачен, пока угол виден (нажатия — ⋮ и меню
  // папки правым кликом — остаются); название чата в шапке прячется, только когда
  // угол на него наехал («дубль убрать, только если мешает», решение 2 плана WF102).
  const CORNER_ID = "myclaude-corner";
  const MAIN_DRAG_ID = "myclaude-main-drag";
  const CORNER_ATTRIBUTE = "data-myclaude-corner";
  const CORNER_TITLE_SELECTOR = ".epitaxy-titlebar [data-pane-title]";
  const CORNER_ORIGIN_SELECTOR = '.epitaxy-titlebar [data-testid="epitaxy-origin-label"]';
  // Плашка прижата к верху окна (top 0), текст по центру её 20 px — у самого края.
  const CORNER_HEIGHT = 20;
  // Слева от угла — место под кнопки окна: в окне 282 угол не шире 198.
  const CORNER_KEEP_LEFT = 84;
  // #9054 (слово Элвиса 08.10: «в правом верхнем углу жутко выглядит… слева, вот
  // где New, над New… красивой типографикой… название проекта, там название чата и
  // таймер… если эта штука свёрнута… там, где Remote Control»). Три места одного
  // узла: side — главное окно, список чатов открыт: над кнопкой New, место ей
  // даёт отступ сверху у списка (правило layoutCss; в дерево React узлов не
  // вставляем); row — список свёрнут или попап: строка шапки правее Remote Control,
  // поверх прозрачных названия и плашки проекта (нажатия — их, меню открывается);
  // corner — прежний угол, когда нет ни того ни другого (узкое окно без шапки).
  // WF209 (#9257, слово Элвиса 10.10 00:45: «сверху вот этот заголовок маленький… он должен крупненько
  // там быть по красоте»; 02:07 — эталон: крупное название чата в шапке колонки, значок справа).
  // Четвёртое место — head: широкий вид, списка над New нет, шапка колонки над полем есть. С WF179
  // значок Remote Control стоит у ПРАВОГО края шапки, строка «правее значка» там не набиралась (12 px),
  // угол падал в полоску corner и через cover гасил родное название 16/600. В head название видно
  // всегда (cover и row там не бывает), а угол — только проект и часики мелким тихим надзаголовком
  // над названием, по левой линии его текста (она же линия текста поля); имя чата в углу не дублируется.
  const CORNER_NEW_SELECTOR = 'button[aria-keyshortcuts="Meta+n"]';
  const CORNER_GUTTER_SELECTOR = '[data-testid="epitaxy-origin-gutter"]';
  // Ритм левой колонки (#9147, слово Элвиса 08.10 23:25: «выровнять всё… название чата и проекта
  // должно быть больше… типографика должна быть очень красивая»): от верха списка 4 — название
  // проекта 20 px и чат 14 px (две строки, 44), 8 — до New (у Claude над ним ещё свои 4). Левый
  // край обоих — линия значков New/Projects. Переключатель Claude/Code с WF166 — в строке окна.
  const CORNER_SIDE_TOP = 4;
  const CORNER_SIDE_TEXT = 44;
  const CORNER_SIDE_BOTTOM = 8;
  // WF190: правый край текста — на 4 левее правого края строк списка (их подложки); подсветка имени чата
  // под курсором выходит на эти 4 вправо и на 11 влево (поле строки Claude) — ровно в рамку подложки
  // строки списка: одна правая и одна левая граница колонки.
  const CORNER_SIDE_RIGHT = 12;
  // WF190 (слово Элвиса 09.10 03:50: «Разреши в две строки писать. Название чата можно и в три строки…
  // должен быть перенос, чтобы не вылезать справа: портит принцип приближенности»): имя чата над New
  // переносится по словам до трёх строк (14 px × 1.35 ≈ 19 на строку), хвост третьей затухает.
  const CORNER_SIDE_CHAT_LINES = 3;
  const CORNER_SIDE_CHAT_LINE = 19;
  const CORNER_LINES_MASK = {
    image: "linear-gradient(#000, #000), linear-gradient(to right, #000 calc(100% - 48px), transparent 100%)",
    size: "100% calc(100% - 1.35em), 100% 1.35em", position: "0 0, 0 100%", repeat: "no-repeat",
  };
  // Линия значков: кружок «+» у New, иначе слот значка; нет и его — поле строки Claude.
  const CORNER_LINE_SELECTOR = ".df-new-circle, .df-leading-slot, [data-cds=\"Icon\"]";
  const CORNER_LINE_FALLBACK = 10;
  // Часики (#9144, слово Элвиса 08.10 23:25: «таймер… поменьше… 10 минут — жёлтым… 5 минут —
  // красным. И тикать, и жирненьким стать»): ступени по оставшимся секундам.
  const CORNER_CLOCK_WARN_S = 600;
  const CORNER_CLOCK_ALARM_S = 300;
  const CORNER_CLOCK_ATTRIBUTE = "data-myclaude-clock";
  const CORNER_CLOCK_LOOKS = {
    calm: { color: "inherit", opacity: "0.5", "font-weight": "400" },
    warn: { color: "#f0c049", opacity: "1", "font-weight": "500" },
    alarm: { color: "#ff6b6b", opacity: "1", "font-weight": "700" },
    out: { color: "#ff6b6b", opacity: "1", "font-weight": "700" },
  };
  // Уже 150 строку шапки не делим: имя проекта с часиками не влезет целиком — прежний угол.
  const CORNER_ROW_MIN = 150;
  const cornerState = { on: false, project: "", chat: "", cover: false, clock: null, late: false, stage: null, mode: null, line: null, switch: null, lines: null, menu: null };
  const cornerNode = document.createElement("div");
  cornerNode.id = CORNER_ID;
  cornerNode.setAttribute("aria-hidden", "true");
  // Часики кеша (#7943, слово Элвиса 27.09: «в каждом чате… в одном и том же
  // месте, предсказуемо видеть время»); пороги — как у закреплённых
  // (pinnedClockText, раздел 2е). #9106 (слово Элвиса 08.10: «чтобы таймер был
  // возле… названия проекта, и чтобы таймер был маленьким») — сразу за именем
  // проекта в его строке, мелко и тихо, во всех трёх местах. Порядок в DOM
  // прежний (проект, чат, часики) — на месте их ставит order.
  const cornerClock = document.createElement("span");
  const cornerProject = document.createElement("b");
  const cornerChat = document.createElement("span");
  const cornerDot = document.createElement("i");
  cornerDot.textContent = "·";
  cornerChat.appendChild(cornerDot);
  const cornerChatText = document.createElement("span");
  cornerChat.appendChild(cornerChatText);
  cornerNode.appendChild(cornerProject);
  cornerNode.appendChild(cornerChat);
  cornerNode.appendChild(cornerClock);
  const cornerStyle = (node, props) => { for (const [name, value] of Object.entries(props)) node.style.setProperty(name, value); };
  cornerStyle(cornerNode, {
    position: "fixed", display: "none", "align-items": "center", "justify-content": "flex-end",
    "box-sizing": "border-box", top: "0px", right: "0px", height: `${CORNER_HEIGHT}px`,
    "max-width": `calc(100vw - ${CORNER_KEEP_LEFT}px)`, padding: "0 12px 0 8px",
    "pointer-events": "none", "user-select": "none", "-webkit-user-select": "none", "z-index": "30",
    font: "11px/1 -apple-system, system-ui, sans-serif", "white-space": "nowrap", color: "inherit",
    background: "var(--myclaude-corner-bg, transparent)",
  });
  // Имя проекта не сжимается никогда — сжимается чат. С WF185 (слово Элвиса 09.10 03:35: «должно быть
  // так же, как в Today — затемняется, фейд уходит») хвост не многоточием, а затуханием, как у строк
  // списка слева: маску ставит cornerFadeEnd, только когда текст правда не влез.
  cornerStyle(cornerProject, { flex: "0 0 auto", "font-weight": "600", opacity: "0.92" });
  cornerStyle(cornerChat, { flex: "0 1 auto", "min-width": "0", overflow: "hidden", "text-overflow": "clip", opacity: "0.62" });
  cornerStyle(cornerDot, { "font-style": "normal", padding: "0 5px" });
  // Вид каждого места (#9054) — полный набор свойств, смена места их переписывает.
  // side и row — сетка в две строки: «Проект 59:49», ниже — чат (#9106). Сетка, а
  // не перенос флекса: флекс с переносом при длинном имени сбрасывал бы часики на
  // свою строку; колонка minmax(0, max-content) режет имя, а колонка часиков не уже их
  // текста — часики всегда видны и всегда рядом с именем.
  // WF185 (слово Элвиса 09.10 03:20: «где название проекта, папки? Там же было»): чат во всю
  // строку (grid-column 1 / -1) отдавал свою ширину колонкам — длинное имя чата уходило в
  // колонку часиков (max-content), колонка проекта (минимум 0) сжималась в ноль, и «Rick»
  // пропадал при любом длинном чате (живьём: проект 0 px, часики 210, чат 218 при угле 189 —
  // он же «вылезал» за список слева). Чат теперь в размер колонок не вкладывается (contain:
  // inline-size) и берёт ширину сетки, а сетка во всю ширину угла: часики — 1fr у левого края.
  // corner — прежняя полоска; фон под ней размыт (#9054: в узких окнах сплошная
  // полоса «накладывается» на живой фон и текст ленты).
  const cornerLooks = (() => {
    const two = (project, chat, clock, lines = 0, quiet = "0.92") => ({
      display: "grid",
      node: {
        "grid-template-columns": "minmax(0, max-content) minmax(max-content, 1fr)", "align-items": "baseline",
        "flex-wrap": "nowrap", "align-content": "center", "justify-content": "start", height: "auto",
        "max-width": "none", padding: "0", font: `${project}px/1.3 -apple-system, system-ui, sans-serif`,
        background: "transparent", "border-bottom-left-radius": "0", "-webkit-backdrop-filter": "none",
      },
      // WF197: имя проекта кликабельно (родные меню проекта, cornerOriginOpen); подсветка — как у чата.
      // WF204: и в строке шапки (широкий вид) — меню проекта открывает имя, а не невидимая плашка у края.
      project: {
        flex: "", "min-width": "0", overflow: "hidden", "text-overflow": "clip", "letter-spacing": project >= 18 ? "-0.02em" : "-0.01em", "line-height": "1.25",
        "pointer-events": "auto", cursor: "pointer", "-webkit-app-region": "no-drag", margin: lines ? "0 -4px 0 -11px" : "", padding: lines ? "0 4px 0 11px" : "",
        "border-radius": lines ? "6px" : "4px", transition: "background-color 120ms ease-out", opacity: quiet,
      },
      chat: {
        flex: "", order: "3", "grid-column": "1 / -1", contain: "inline-size", "font-size": `${chat}px`, "line-height": "1.35", "font-weight": "400",
        // WF190: над New — перенос по словам до lines строк, имя кликабельно (меню чата Claude); в строке шапки — одна строка.
        "white-space": lines ? "normal" : "nowrap", "overflow-wrap": lines ? "break-word" : "", "max-height": lines ? `${Math.round(lines * 135) / 100}em` : "",
        "pointer-events": lines ? "auto" : "", cursor: lines ? "pointer" : "", margin: lines ? "0 -4px 0 -11px" : "", padding: lines ? "0 4px 0 11px" : "",
        "border-radius": lines ? "6px" : "", transition: lines ? "background-color 120ms ease-out" : "",
      },
      dot: { display: "none" },
      clock: { "font-size": `${clock}px`, "justify-self": "start" },
    });
    return {
      corner: {
        display: "flex",
        node: {
          "grid-template-columns": "", "align-items": "center",
          "flex-wrap": "nowrap", "align-content": "normal", "justify-content": "flex-end", height: `${CORNER_HEIGHT}px`,
          "max-width": `calc(100vw - ${CORNER_KEEP_LEFT}px)`, padding: "0 12px 0 8px", font: "11px/1 -apple-system, system-ui, sans-serif",
          background: "var(--myclaude-corner-bg, transparent)", "border-bottom-left-radius": "8px", "-webkit-backdrop-filter": "blur(12px)",
        },
        // WF204: имя проекта в углу — то же меню проекта, что над New (cornerOriginOpen).
        project: {
          flex: "0 0 auto", "min-width": "", overflow: "", "text-overflow": "", "letter-spacing": "", "line-height": "",
          "pointer-events": "auto", cursor: "pointer", "-webkit-app-region": "no-drag", margin: "", padding: "", "border-radius": "4px", transition: "background-color 120ms ease-out", opacity: "0.92",
        },
        chat: {
          flex: "0 1 auto", order: "2", "grid-column": "", contain: "", "font-size": "", "line-height": "", "font-weight": "",
          "white-space": "", "overflow-wrap": "", "max-height": "", "pointer-events": "", cursor: "", margin: "", padding: "", "border-radius": "", transition: "",
        },
        dot: { display: "" },
        clock: { "font-size": "10px", "justify-self": "" },
      },
      side: two(CORNER_SIDE_PROJECT_FONT, 14, 10, CORNER_SIDE_CHAT_LINES),
      row: two(13, 11, 10),
      // WF209 (#9257): «Проект 59:49» одной тихой строкой за названием колонки; имени чата в углу нет
      // (оно — само родное название рядом; его display гасит placeCorner).
      head: two(CORNER_HEAD_FONT, 11, 10, 0, CORNER_HEAD_OPACITY),
    };
  })();
  const cornerLook = mode => {
    if (cornerState.mode === mode) return;
    cornerState.mode = mode;
    const look = cornerLooks[mode];
    cornerStyle(cornerNode, look.node);
    cornerStyle(cornerProject, look.project);
    cornerStyle(cornerChat, look.chat);
    cornerStyle(cornerDot, look.dot);
    cornerStyle(cornerClock, look.clock);
    // Подсветка наведения — только над New (WF190): сменилось место — снимаем.
    if (mode !== "side" && cornerChat.style.getPropertyValue("background-color")) cornerChat.style.removeProperty("background-color");
    if (cornerProject.style.getPropertyValue("background-color")) cornerProject.style.removeProperty("background-color");
  };
  // Где стоять (#9054): место и рамка узла в точках окна.
  const cornerSpot = () => {
    const box = node => {
      try { return node?.isConnected ? node.getBoundingClientRect() : null; } catch { return null; }
    };
    if (isMainWindow()) {
      const bar = document.querySelector('[data-testid="sidebar"]');
      const newNode = bar?.querySelector?.(CORNER_NEW_SELECTOR);
      const next = box(newNode);
      const list = box(bar);
      const panel = box(document.querySelector(".epitaxy-chat-panel"));
      // Список пристыкован (панель чата правее него), а не всплыл поверх ленты. Свёрнутая панель (`data-collapsed`)
      // — не пристыкована, даже если лента правее списка: её сдвинула панель материалов (#10644, WF277), а список
      // прозрачен за левым краем — угол уходил под светофор.
      const collapsed = document.querySelector(".dframe-root")?.getAttribute?.("data-collapsed") === "true";
      if (next && list && panel && next.width > 0 && !collapsed && panel.left >= list.right - 1) {
        // #9147: одна вертикаль — значки New/Projects; по ней проект и чат.
        // Сам кружок «+» (на линии значков Projects/Artifacts), а не обёртка .df-leading-slot — она левее
        // на 3 px (замер 08.10: обёртка 14, кружок 17); querySelector со списком отдаёт первую по документу.
        const icon = box(newNode.querySelector?.(".df-new-circle") ?? newNode.querySelector?.(CORNER_LINE_SELECTOR));
        // +2: видимый край значков (Projects, Artifacts) правее рамки кружка на 2 px — выравниваем по глазу (снимок 08.10).
        const line = icon && icon.width > 0 ? icon.left + 2 : next.left + CORNER_LINE_FALLBACK;
        return {
          mode: "side", left: line, top: list.top + CORNER_SIDE_TOP, width: Math.max(0, list.right - CORNER_SIDE_RIGHT - line), height: CORNER_SIDE_TEXT,
          space: CORNER_SIDE_TOP + CORNER_SIDE_TEXT + CORNER_SIDE_BOTTOM,
        };
      }
    }
    // WF209 (#9257): шапка колонки широкого вида (не перенесённая влево) с названием чата — место head:
    // строка над названием, от левой линии его текста до правого края значка Remote Control (края поля).
    const chatPanel = document.querySelector(".epitaxy-chat-panel");
    const title = document.querySelector(CORNER_TITLE_SELECTOR);
    const head = title?.closest?.(".epitaxy-titlebar") ?? null;
    const titleBox = box(title);
    const headBox = box(head);
    if (titleBox && headBox && titleBox.width > 0 && titleBox.height > 0 && headBox.height > 0 &&
        wideLayout(chatPanel) && !titleGoesLeft(chatPanel, true)) {
      // Слово Элвиса 10.10 03:55 про page-51 («здоровенная полоса… интерфейс же лёгким должен быть… мне
      // она не нужна»): шапка не растёт. Проект и часики — тихо в строке самого названия, сразу за его
      // текстом и до значка Remote Control; названию места не хватает — им места нет, название важнее.
      // #10146 (Claude 2.42304): справа в шапке — кнопки Terminal, Changes, Browser, Files, View options; край —
      // самая левая из того, что правее названия (значок Remote Control или кнопка), иначе угол наезжал на них.
      const ends = [...head.querySelectorAll(`${CORNER_GUTTER_SELECTOR}, button`)].map(box)
        .filter(item => item && item.width > 0 && item.left >= titleBox.right).map(item => item.left);
      const end = (ends.length ? Math.min(...ends) : headBox.right) - CORNER_HEAD_GAP;
      const left = titleBox.right + CORNER_HEAD_GAP;
      return { mode: "head", left, top: titleBox.top, width: Math.max(0, end - left), height: titleBox.height };
    }
    const gutter = document.querySelector(`.epitaxy-titlebar ${CORNER_GUTTER_SELECTOR}`);
    const titlebar = gutter?.closest?.(".epitaxy-titlebar") ?? null;
    const lead = box(gutter);
    const bar = box(titlebar);
    if (lead && bar && lead.width > 0 && lead.height > 0 && bar.height > 0) {
      // Пока открыто меню проекта с имени (WF204), плашка стоит на имени (ORIGIN_OPEN_ATTRIBUTE) — край
      // строки берём прежний, иначе строка сжалась бы до имени и угол уехал бы из-под меню.
      const open = document.documentElement.hasAttribute(ORIGIN_OPEN_ATTRIBUTE) && cornerState.rowEnd != null;
      const pill = open ? null : box(titlebar.querySelector('[data-testid="epitaxy-origin-label"]')?.closest?.("button"));
      const end = open ? cornerState.rowEnd : pill && pill.width > 0 ? pill.right : bar.right - 8;
      cornerState.rowEnd = end;
      const left = lead.right + 4;
      if (end - left >= CORNER_ROW_MIN) return { mode: "row", left, top: bar.top, width: end - left, height: bar.height };
    }
    return { mode: "corner" };
  };
  // Часики не сжимаются и стоят сразу за именем (order 1, #9106): шрифт окна, не
  // моноширинный (с ним часики выглядели плохо), цифры одной ширины, тихие, 10–11 px.
  cornerStyle(cornerClock, {
    display: "none", flex: "0 0 auto", order: "1", "margin-left": "8px", "white-space": "nowrap",
    "font-weight": "400", "font-variant-numeric": "tabular-nums", "letter-spacing": "0.01em",
    color: "inherit", opacity: "0.5",
  });
  // Сироты упавшей установки — до вставки своих (раздел 3 идёт уже после неё).
  for (const orphan of document.querySelectorAll(`#${CORNER_ID}, #${MAIN_DRAG_ID}`)) orphan.remove();
  (document.body ?? document.documentElement).appendChild(cornerNode);
  track(() => cornerNode.remove());
  // WF190 (слово Элвиса 09.10 03:50: по нажатию на имя чата должно открываться то же самое меню,
  // что при нажатии наверху (Open in, Rename, Fork…), — это тоже название чата): имя чата
  // над New жмёт родную кнопку меню названия в шапке колонки (TITLE_MENU_SELECTOR, «More options for…»)
  // тем же нажатием, что и мышь (pressLikeMouse, раздел 12з) — меню Claude встаёт у своей кнопки.
  // Меню уже открыто — наше нажатие его закрыло (Claude закрывает по нажатию мимо), второй раз не
  // открываем. Только над New: в строке шапки угол прозрачен для мыши, жмут сами родные кнопки.
  const cornerMenuState = { wasOpen: false };
  // Та же кнопка, что у TITLE_MENU_SELECTOR (сосед «~» обёртки названия), — обходом соседей.
  const cornerMenuButton = () => {
    try {
      let node = document.querySelector(CORNER_TITLE_SELECTOR)?.parentElement?.nextElementSibling ?? null;
      while (node && node.tagName !== "BUTTON") node = node.nextElementSibling;
      return node;
    } catch { return null; }
  };
  const cornerHover = hot => {
    const value = hot && cornerState.mode === "side" ? "color-mix(in srgb, currentColor 10%, transparent)" : "";
    if (value) cornerSet(cornerChat, "background-color", value);
    else if (cornerChat.style.getPropertyValue("background-color")) cornerChat.style.removeProperty("background-color");
  };
  on(cornerChat, "pointerenter", () => cornerHover(true));
  on(cornerChat, "pointerleave", () => cornerHover(false));
  on(cornerChat, "pointerdown", () => {
    cornerMenuState.wasOpen = cornerMenuButton()?.getAttribute?.("aria-expanded") === "true";
  });
  on(cornerChat, "click", event => {
    if (cornerState.mode !== "side") return;
    try { event.preventDefault(); event.stopPropagation(); } catch {}
    const button = cornerMenuButton();
    const wasOpen = cornerMenuState.wasOpen;
    cornerMenuState.wasOpen = false;
    if (!button?.isConnected) { cornerState.menu = "no-button"; return; }
    if (wasOpen) { cornerState.menu = "closed"; return; }
    cornerState.menu = pressLikeMouse(button) ? "opened" : "no-button";
  });
  // Имя проекта над New (WF197, регресс WF185) — родные меню проекта Claude, как у плашки в шапке до
  // WF185 (#7334): левый клик — ⋮ шапки (Terminal / Changes / Browser, она привязана к плашке), правый —
  // меню самой плашки (Show in Finder / Change folder; так правый клик по плашке и работал, onOriginMenu).
  // Нажимаем родные кнопки тем же нажатием, что и мышь; плашку на время меню ставим на имя в углу
  // (ORIGIN_OPEN_ATTRIBUTE), чтобы меню встало у имени. Меню закрылось — плашка снова снята.
  const cornerOrigin = { timer: 0, at: 0, seen: false };
  const cornerOriginButtons = () => {
    try {
      const pill = document.querySelector(CORNER_ORIGIN_SELECTOR)?.closest?.("button") ?? null;
      // Группа названия — ребёнок шапки, в котором плашка; ⋮ — последняя кнопка-меню в группах правее.
      const bar = pill?.closest?.(".epitaxy-titlebar") ?? null;
      let lead = pill;
      while (lead && lead.parentElement !== bar) lead = lead.parentElement;
      let dots = null;
      for (let node = lead?.nextElementSibling; node; node = node.nextElementSibling) {
        const menus = [...node.children].filter(kid => kid.getAttribute?.("aria-haspopup") === "menu");
        if (menus.length) dots = menus.at(-1);
      }
      return { pill, dots };
    } catch { return { pill: null, dots: null }; }
  };
  const cornerOriginClose = () => {
    if (cornerOrigin.timer) { clearInterval(cornerOrigin.timer); cornerOrigin.timer = 0; }
    const root = document.documentElement;
    if (root.hasAttribute(ORIGIN_OPEN_ATTRIBUTE)) root.removeAttribute(ORIGIN_OPEN_ATTRIBUTE);
    root.style.removeProperty(ORIGIN_X_VARIABLE);
    root.style.removeProperty(ORIGIN_Y_VARIABLE);
  };
  track(cornerOriginClose);
  const cornerOriginOpen = (event, kind) => {
    try { event.preventDefault(); event.stopPropagation(); } catch {}
    const { pill, dots } = cornerOriginButtons();
    const button = kind === "finder" ? pill : dots ?? pill;
    if (!button?.isConnected) { cornerState.originMenu = "no-button"; return; }
    // Своё меню уже открыто — нажатие мимо его закрыло (как у имени чата), второй раз не открываем.
    if (cornerOrigin.timer && button.getAttribute?.("aria-expanded") === "true") { cornerOriginClose(); cornerState.originMenu = "closed"; return; }
    const root = document.documentElement;
    root.setAttribute(ORIGIN_OPEN_ATTRIBUTE, "");
    root.style.setProperty(ORIGIN_X_VARIABLE, "0px");
    root.style.setProperty(ORIGIN_Y_VARIABLE, "0px");
    try {
      const shell = pill.parentElement?.parentElement ?? pill;
      const from = shell.getBoundingClientRect();
      const to = cornerProject.getBoundingClientRect();
      if (from.width > 0 && to.width > 0) {
        root.style.setProperty(ORIGIN_X_VARIABLE, `${Math.round(to.left - from.left)}px`);
        root.style.setProperty(ORIGIN_Y_VARIABLE, `${Math.round(to.top - from.top)}px`);
      }
    } catch {}
    cornerState.originMenu = pressLikeMouse(button) ? (kind === "finder" ? "finder" : "project") : "no-button";
    if (cornerOrigin.timer) clearInterval(cornerOrigin.timer);
    // Меню было открыто и закрылось — плашку снимаем; не открылось вовсе — через 1,5 с.
    cornerOrigin.at = Date.now();
    cornerOrigin.seen = false;
    cornerOrigin.timer = setInterval(() => {
      const open = [pill, dots].some(node => node?.isConnected && node.getAttribute?.("aria-expanded") === "true");
      if (open) cornerOrigin.seen = true;
      else if (cornerOrigin.seen || Date.now() - cornerOrigin.at > 1500) cornerOriginClose();
    }, 250);
  };
  on(cornerProject, "pointerenter", () => cornerSet(cornerProject, "background-color", "color-mix(in srgb, currentColor 10%, transparent)"));
  on(cornerProject, "pointerleave", () => { if (cornerProject.style.getPropertyValue("background-color")) cornerProject.style.removeProperty("background-color"); });
  on(cornerProject, "click", event => cornerOriginOpen(event, "project"));
  on(cornerProject, "contextmenu", event => cornerOriginOpen(event, "finder"));
  track(() => { try { document.documentElement.removeAttribute(CORNER_ATTRIBUTE); } catch {} });
  // Отступ над New — переменная корня (#9147): правило layoutCss её читает.
  const cornerSideVars = spot => {
    const root = document.documentElement.style;
    const put = (name, value) => {
      if (value == null) { if (root.getPropertyValue(name)) root.removeProperty(name); return; }
      if (root.getPropertyValue(name) !== value) root.setProperty(name, value);
    };
    put(CORNER_SIDE_SPACE_VARIABLE, spot?.mode === "side" ? `${Math.round(spot.space)}px` : null);
    // WF209: у названия колонки (head) линия — левый край текста названия.
    cornerState.line = spot?.mode === "side" || spot?.mode === "head" ? Math.round(spot.left) : null;
  };
  track(() => { try { cornerSideVars(null); } catch {} });
  const cornerText = node => String(node?.textContent ?? "").replace(/\s+/g, " ").trim();
  // WF185 (класс «имя проекта пустое — угол пропадает»): у главного окна — строка своего чата, нет
  // её — подпись плашки проекта в шапке; у попапа наоборот (подпись — его собственная), а нет
  // подписи — строка своего чата в списке главного окна (window.opener, как у часиков).
  const cornerProjectName = () => {
    const main = isMainWindow();
    const label = () => cornerText(document.querySelector(CORNER_ORIGIN_SELECTOR)).slice(0, PINNED_FOLDER_MAX);
    if (!main) { const own = label(); if (own) return own; }
    const id = myChatId();
    if (id) {
      try {
        let doc = null;
        try { doc = main ? document : window.opener?.document; } catch {}
        const row = doc?.querySelector?.(`[data-testid="sidebar"] [data-row-key="code:${id}"]`);
        const name = row ? pinnedFolderName(row, id) : "";
        if (name) return name;
      } catch {}
    }
    return main ? label() : "";
  };
  const cornerChatTitle = () => {
    const pane = cornerText(document.querySelector(CORNER_TITLE_SELECTOR));
    if (pane) return pane.slice(0, 200);
    const title = windowTitle();
    return title && !THEME_TITLE_STUBS.has(title.toLowerCase()) ? title.slice(0, 200) : "";
  };
  const cornerHide = () => {
    cornerState.on = false;
    cornerState.lines = null;
    cornerState.cover = false;
    if (cornerNode.style.getPropertyValue("display") !== "none") cornerNode.style.setProperty("display", "none");
    if (document.documentElement.hasAttribute(CORNER_ATTRIBUTE)) document.documentElement.removeAttribute(CORNER_ATTRIBUTE);
    cornerSideVars(null);
  };
  const cornerSet = (node, name, value) => {
    if (node.style.getPropertyValue(name) !== value) node.style.setProperty(name, value);
  };
  // Фон окна: у тем Пимпа и у Claude он на body; прозрачный — берём корень.
  const cornerBackground = () => {
    const see = node => {
      try { return String(getComputedStyle(node).backgroundColor ?? "").trim(); } catch { return ""; }
    };
    const clear = color => !color || color === "transparent" || /^rgba\([^)]*,\s*0\)$/.test(color);
    // Живой фон слоя «Оформление» (WF139, #9104): плашка угла — только размытие, без сплошной заливки.
    if (themeState.look?.aurora === true) return "";
    // Живой фон картинкой (градиент) — сплошной полосой поверх не закрываем (#9054).
    // Под углом тогда только размытие.
    try {
      const image = document.body ? String(getComputedStyle(document.body).backgroundImage ?? "") : "";
      if (image && image !== "none") return "";
    } catch {}
    const body = document.body ? see(document.body) : "";
    if (!clear(body)) return body;
    const root = see(document.documentElement);
    return clear(root) ? "" : root;
  };
  // Время чата для часиков угла — updatedAtMs сессии его строки в списке слева,
  // то же поле, что у закреплённых. У попапа своего списка нет, но он открыт из
  // главного окна (разведка 27.09: window.opener — главное окно, его список
  // чатов виден попапу, строка своего чата в нём есть, волокно строки несёт ту же
  // сессию). Строки нет (список свёрнут, чат не показан) — источника нет, часиков нет.
  const cornerUpdatedAt = () => {
    const id = myChatId();
    if (!id) return 0;
    let doc = null;
    try { doc = isMainWindow() ? document : window.opener?.document; } catch {}
    const row = doc?.querySelector?.(`[data-testid="sidebar"] [data-row-key="code:${id}"]`);
    const last = row ? Number(roamSession(row, id)?.updatedAtMs) : 0;
    return last > 0 ? last : 0;
  };
  // Ступени (#9144): больше 10 минут — тихо; 10:00 и меньше — жёлтым; 5:00 и меньше — красным,
  // жирно и мягко «тикает» (пульс раз в секунду — правило листа по атрибуту, при «Уменьшить
  // движение» без пульса); время вышло — «вышло» красным, без пульса.
  const cornerClockStage = left => left <= 0 ? "out" : left <= CORNER_CLOCK_ALARM_S ? "alarm" : left <= CORNER_CLOCK_WARN_S ? "warn" : "calm";
  const markCornerClock = (nowMs = Date.now()) => {
    const last = cornerState.on ? cornerUpdatedAt() : 0;
    if (!last) {
      cornerState.clock = null;
      cornerState.late = false;
      cornerState.stage = null;
      cornerSet(cornerClock, "display", "none");
      if (cornerClock.hasAttribute(CORNER_CLOCK_ATTRIBUTE)) cornerClock.removeAttribute(CORNER_CLOCK_ATTRIBUTE);
      return;
    }
    const left = Math.max(0, Math.ceil((PINNED_CLOCK_HOUR_MS - (nowMs - last)) / 1000));
    const stage = cornerClockStage(left);
    const text = stage === "out" ? "вышло" : pinnedClockText(left);
    if (cornerClock.textContent !== text) cornerClock.textContent = text;
    for (const [name, value] of Object.entries(CORNER_CLOCK_LOOKS[stage])) cornerSet(cornerClock, name, value);
    if (cornerClock.getAttribute(CORNER_CLOCK_ATTRIBUTE) !== stage) cornerClock.setAttribute(CORNER_CLOCK_ATTRIBUTE, stage);
    cornerState.clock = text;
    cornerState.late = stage === "alarm" || stage === "out";
    cornerState.stage = stage;
    cornerSet(cornerClock, "display", "inline-block");
  };
  // Затухание хвоста (WF185): текст шире своего места — маска, влез — без маски. wrap (WF190, имя чата
  // над New в три строки): текст выше своих строк — первые строки целиком, хвост последней затухает.
  const cornerFadeEnd = (node, wrap = false) => {
    let over = false;
    try {
      over = wrap ? Number(node.scrollHeight) - Number(node.clientHeight) > 1 : Number(node.scrollWidth) - Number(node.clientWidth) > 1;
    } catch {}
    const look = !over ? null : wrap ? CORNER_LINES_MASK : { image: FADE_END_MASK, size: "", position: "", repeat: "" };
    for (const part of ["image", "size", "position", "repeat"]) {
      const value = look?.[part] ?? "";
      for (const name of [`-webkit-mask-${part}`, `mask-${part}`]) {
        if (value) cornerSet(node, name, value);
        else if (node.style.getPropertyValue(name)) node.style.removeProperty(name);
      }
    }
  };
  // Строк имени чата над New (WF190): по высоте текста, 1…3.
  const cornerChatLines = () => {
    if (!cornerState.chat) return 1;
    let height = 0;
    try { height = Number(cornerChat.scrollHeight); } catch {}
    return height > 0 ? Math.max(1, Math.min(CORNER_SIDE_CHAT_LINES, Math.round(height / CORNER_SIDE_CHAT_LINE))) : 1;
  };
  const placeCorner = () => {
    const project = themable ? cornerProjectName() : "";
    if (!project) { cornerHide(); return; }
    const chat = cornerChatTitle();
    if (cornerProject.textContent !== project) cornerProject.textContent = project;
    if (cornerChatText.textContent !== chat) cornerChatText.textContent = chat;
    cornerState.project = project;
    cornerState.chat = chat;
    const spot = cornerSpot();
    // #11676 (#11637, слово Элвиса 05.11: «справа в углу Рик написано… убери»): «Проект 59:06 · чат» справа
    // вверху (row, head, corner) не показывается, над New (side) — как был. Угол считается дальше (папка для
    // «здоровья», часики в status), метка корня "off": плашка проекта Claude в шапке спрятана, как при угле, а
    // название чата и кнопки попапа видны (правила cover/row/on их больше не гасят).
    if (spot.mode !== "side") {
      cornerLook(spot.mode);
      cornerSideVars(null);
      cornerState.lines = null;
      cornerState.on = true;
      cornerState.cover = false;
      cornerSet(cornerNode, "display", "none");
      if (document.documentElement.getAttribute(CORNER_ATTRIBUTE) !== "off") document.documentElement.setAttribute(CORNER_ATTRIBUTE, "off");
      markCornerClock();
      return;
    }
    // WF209: над названием колонки (head) имени чата в углу нет — оно крупно стоит прямо под ним.
    cornerSet(cornerChat, "display", chat && spot.mode !== "head" ? "block" : "none");
    cornerLook(spot.mode);
    if (spot.mode !== "corner") {
      cornerSet(cornerNode, "left", `${Math.round(spot.left)}px`);
      cornerSet(cornerNode, "top", `${Math.round(spot.top)}px`);
      cornerSet(cornerNode, "right", "auto");
      cornerSet(cornerNode, "width", `${Math.round(spot.width)}px`);
      // WF190: над New угол растёт на строки имени чата (ширина уже стоит — перенос по ней), отступ списка — с ним.
      cornerState.lines = spot.mode === "side" ? cornerChatLines() : null;
      if (cornerState.lines > 1) {
        spot.height += (cornerState.lines - 1) * CORNER_SIDE_CHAT_LINE;
        spot.space += (cornerState.lines - 1) * CORNER_SIDE_CHAT_LINE;
      }
      cornerSideVars(spot);
      cornerSet(cornerNode, "height", `${Math.round(spot.height)}px`);
      // head: за длинным названием места нет — проекта и часиков не видно вовсе (иначе часики, которым
      // сжиматься нельзя, вылезали на значок Remote Control; живьём 10.10 04:55).
      cornerSet(cornerNode, "display", spot.mode === "head" && spot.width < CORNER_HEAD_MIN ? "none" : cornerLooks[spot.mode].display);
      cornerState.on = true;
      cornerState.cover = false;
      if (document.documentElement.getAttribute(CORNER_ATTRIBUTE) !== spot.mode) document.documentElement.setAttribute(CORNER_ATTRIBUTE, spot.mode);
      markCornerClock();
      cornerFadeEnd(cornerProject);
      cornerFadeEnd(cornerChat, spot.mode === "side");
      return;
    }
    cornerSideVars(null);
    cornerState.lines = null;
    cornerSet(cornerNode, "left", "auto");
    cornerSet(cornerNode, "top", "0px");
    cornerSet(cornerNode, "width", "auto");
    // Верх — край окна (решение 12 WF103), правый край — по панели чата.
    let box = null;
    try {
      const panel = document.querySelector(".epitaxy-chat-panel");
      box = panel?.isConnected ? panel.getBoundingClientRect() : null;
    } catch {}
    const right = box && box.width > 0 ? Math.max(0, Math.round(innerWidth - box.right)) : 0;
    cornerSet(cornerNode, "right", `${right}px`);
    // Целиком в окне (#9272, класс «свой элемент у края режется»): угол отступил от правого края за панелью —
    // на столько же уже, иначе левый край уходил бы под кнопки окна и за левую кромку узкого окна.
    cornerSet(cornerNode, "max-width", `calc(100vw - ${CORNER_KEEP_LEFT + right}px)`);
    const bg = cornerBackground();
    if (bg) cornerSet(cornerNode, "--myclaude-corner-bg", bg);
    else if (cornerNode.style.getPropertyValue("--myclaude-corner-bg")) cornerNode.style.removeProperty("--myclaude-corner-bg");
    cornerSet(cornerNode, "display", "flex");
    cornerState.on = true;
    // Угол наехал на название чата в шапке — то прячется (см. layoutCss).
    let cover = false;
    try {
      const own = cornerNode.getBoundingClientRect();
      const title = document.querySelector(CORNER_TITLE_SELECTOR)?.getBoundingClientRect();
      cover = own.width > 0 && Boolean(title) && title.width > 0 && title.height > 0 &&
        title.right > own.left && title.top < own.bottom && title.bottom > own.top;
    } catch {}
    cornerState.cover = cover;
    const mark = cover ? "cover" : "on";
    if (document.documentElement.getAttribute(CORNER_ATTRIBUTE) !== mark) document.documentElement.setAttribute(CORNER_ATTRIBUTE, mark);
    markCornerClock();
    cornerFadeEnd(cornerChat);
  };

  // #7913 (слово Элвиса 26.09: «этот хедер нужно вообще убрать у главного… чтобы
  // по высоте освободить место»; кнопки окна — «пусть текст за ними ходит, фейд на
  // углы под цвет темы»). Только главное окно. Широкий вид: шапка всегда во второй
  // колонке, над полем ввода (applyTitleSide её влево не переносит), лента во всю
  // высоту. Узкий: шапка сжата до нуля и невидима (правило в layoutCss) — узел НЕ
  // убираем и не display:none: на нём держатся CHAT_FIBER_SELECTOR (кто этот чат) и
  // подпись проекта для угла. Меню названия (#7320) и ⋮ плашки проекта (#7334) в
  // узком главном окне уходят вместе с шапкой — переименовать можно из списка
  // чатов. Панель у левого края окна (список чатов свёрнут) — текст ленты под
  // кнопками окна затухает (applyCornerFade), а под самими кнопками — полоса, за
  // которую окно таскается: у главного окна своей там нет, была только шапка.
  const MAIN_HEADLESS_ATTRIBUTE = "data-myclaude-headless";
  const MAIN_DRAG_WIDTH = 76;
  const MAIN_DRAG_HEIGHT = 40;
  const mainHead = { panel: null, headless: false, drag: false };
  const mainDrag = document.createElement("div");
  mainDrag.id = MAIN_DRAG_ID;
  mainDrag.setAttribute("aria-hidden", "true");
  cornerStyle(mainDrag, {
    position: "fixed", display: "none", left: "0px", top: "0px",
    width: `${MAIN_DRAG_WIDTH}px`, height: `${MAIN_DRAG_HEIGHT}px`, "-webkit-app-region": "drag", "z-index": "29",
  });
  (document.body ?? document.documentElement).appendChild(mainDrag);
  track(() => mainDrag.remove());
  const clearMainHead = () => {
    try { mainHead.panel?.removeAttribute(MAIN_HEADLESS_ATTRIBUTE); } catch {}
    mainHead.panel = null;
    mainHead.headless = false;
  };
  track(clearMainHead);
  const applyMainHead = (panel, wide) => {
    const main = isMainWindow() && Boolean(panel?.isConnected);
    const headless = main && !wide;
    if (mainHead.panel && mainHead.panel !== panel) clearMainHead();
    if (headless) {
      mainHead.panel = panel;
      if (!panel.hasAttribute(MAIN_HEADLESS_ATTRIBUTE)) panel.setAttribute(MAIN_HEADLESS_ATTRIBUTE, "");
    } else if (panel?.hasAttribute?.(MAIN_HEADLESS_ATTRIBUTE)) panel.removeAttribute(MAIN_HEADLESS_ATTRIBUTE);
    mainHead.headless = headless;
    let left = Infinity;
    try { left = main ? panel.getBoundingClientRect().left : Infinity; } catch {}
    mainHead.drag = main && left < TITLEBAR_CLEARANCE_LEFT;
    cornerSet(mainDrag, "display", mainHead.drag ? "block" : "none");
  };
  statusPart("corner", () => ({
    on: cornerState.on && cornerNode.isConnected, project: cornerState.project || null,
    chat: cornerState.chat || null, cover: cornerState.cover,
    clock: cornerState.clock, late: cornerState.late, stage: cornerState.stage, mode: cornerState.mode,
    line: cornerState.line, switch: cornerState.switch ? { ...cornerState.switch } : null,
    // WF185: хвост имени проекта / чата затухает (не влез).
    tail: { project: Boolean(cornerProject.style.getPropertyValue("mask-image")), chat: Boolean(cornerChat.style.getPropertyValue("mask-image")) },
    // WF190: строк имени чата над New (null — не над New); чем кончилось нажатие на имя.
    lines: cornerState.lines, menu: cornerState.menu, originMenu: cornerState.originMenu ?? null,
  }));
  // Шапка (#7913): main — главное окно; headless — шапка сжата (узкий вид);
  // drag — полоса под кнопками окна; titleSide — шапка влево (только попапы).
  statusPart("head", () => ({
    main: isMainWindow(), headless: mainHead.headless, drag: mainHead.drag,
    titleSide: wideState.panel?.getAttribute?.(TITLE_SIDE_ATTRIBUTE) ?? null,
    // #9135: сдвиг значка шапки колонки до линии текста поля, px (null — не выравниваем).
    titleShift: titleAlign.shift,
    // WF185: отступ значка до правого края поля, px; хвост названия затухает (не влез).
    titleEnd: titleAlign.end, titleFade: titleAlign.fade,
  }));
  HATCH && Object.assign(HATCH, { markCornerClock });

