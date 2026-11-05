  // ---- 12з¹. Нижняя строка поля ввода: мельче и короче (#7206, WF84) ---------
  // Макет docs/8-footer-opus-5.5.html, вариант 8.1 (рекомендованный): шрифт
  // 10 px в узком окне и 11 в широком, кнопки 16×16, в окне уже 300 (до WF94 —
  // 480) или в строке, куда полные не влезли (#7638, #8732), подписи коротко — модель «O55»
  // (первая буква и цифры номера без точки, слова Элвиса 23.09 «O55, F51, S5 и H45» и 04.10
  // «O55, а не просто О5»), эффорт и режим двумя заглавными (EX, AU; Max — «MX»); уже 260 (до WF94 — 320) — ещё и поля/зазоры по 1 px. Микрофон Claude и его стрелка ⌄ спрятаны всегда
  // (ответ Элвиса 8.2), плюсик и кружок на месте.
  //
  // Кнопки мы только помечаем атрибутом, рисуют правила раздела 4: подпись
  // Claude держит React, и переписанный текст он вернул бы на следующей же
  // перерисовке (а то и споткнулся бы о чужой узел). Клик по «O55», «HI», «AU»
  // открывает те же меню Claude — меняется подпись, не кнопка.
  //
  // Живой разметки строки под рукой нет (замер S0 23.09: модель —
  // [data-testid=epitaxy-cds-model-selector], эффорт — «Effort: High», режим —
  // кнопка с текстом «Accept edits» и aria-haspopup=menu), поэтому узнаём по
  // приметам, а чего не узнали — не трогаем. Стрелку ⌄ — только рядом с
  // микрофоном и только кнопкой без текста.
  const CHIN_MODES = [
    [/^auto(?:\s+mode)?$/i, "Au"], [/^accept\s+edits$/i, "Ac"], [/^ask(?:\s+(?:permissions|before\s+edits))?$/i, "As"],
    [/^plan(?:\s+mode)?$/i, "Pl"], [/^bypass(?:\s+permissions)?$/i, "By"],
    // #11618: Claude на русском — каталог claude.ai («Авто», «Принимать правки», «План», «Обход разрешений»); имени
    // «Ask permissions» в каталоге нет — «Спрашивать…»/«Запрашивать…» по смыслу.
    [/^авто(?:матический\s+режим)?$/i, "Au"], [/^(?:принимать\s+правки|принятие\s+правок)$/i, "Ac"],
    [/^(?:спрашивать|запрашивать)(?:\s+разрешени[ея])?$/i, "As"], [/^(?:план|режим\s+планирования)$/i, "Pl"],
    [/^обход(?:\s+(?:запросов\s+)?разрешений)?$/i, "By"],
  ];
  // С WF183 (слово Элвиса 09.10 03:15: «Bp — B большая, p маленькая; Ex — E большая, x маленькая; и так со
  // всеми… эффорт — две буквы, первая большая, вторая маленькая»): коды режимов и эффорта — «Хх».
  const CHIN_EFFORTS = { low: "Lo", medium: "Me", high: "Hi", xhigh: "Ex", extra: "Ex", max: "Mx",
    низкий: "Lo", средний: "Me", высокий: "Hi", сверхвысокий: "Ex", максимальный: "Mx" };
  // Слово над кодом эффорта (#9813) — как в меню Claude.
  const CHIN_EFFORT_WORD = "Effort";
  // Подпись режима, где она не код (код «By» остаётся для сторожей режима).
  // Слово Элвиса 22.10.2026: «вот где BP написано, там должно быть написано ByPass» — как в меню Claude.
  const CHIN_MODE_LABELS = { By: "Bypass" };
  const CHIN_MODEL_SELECTOR = '[data-testid="epitaxy-cds-model-selector"]';
  const CHIN_EFFORT_SELECTOR = 'button[aria-label^="Effort:"],button[aria-label^="Усилия:"]';
  const chinText = node => String(node?.textContent ?? "").replace(/\s+/g, " ").trim();
  // Подпись модели — имя полностью и номер (#9813, слово Элвиса 11.10 ~21:02: «Зачем экономить на названии
  // модели? … модель мелко написать, а версию там крупно. Ну, как циферки… чтоб они полностью влезали в две
  // строки»): Opus 5.5 → «Opus» + «5.5», Fable 5.1 → «Fable» + «5.1», Sonnet 5 → «Sonnet» + «5», Haiku 4.5 →
  // «Haiku» + «4.5», любая другая модель с номером — так же. Слово — мелкой верхней строкой, номер — под ним
  // кеглем соседей (правила раздела 4). До WF266 — «Op» + мелкий хвост (#9181, WF172–WF195). Номера нет — не
  // трогаем, подпись Claude как есть. Ответ — [слово, номер] или null.
  const chinModelParts = text => {
    const hit = String(text ?? "").trim().match(/^([\p{L}][\p{L}]*)\s+(\d+(?:\.\d+)*)/u);
    return hit ? [hit[1], hit[2]] : null;
  };
  const chinModelShort = text => chinModelParts(text)?.join(" ") ?? null;
  const chinTwo = text => {
    const word = String(text ?? "").trim().match(/[\p{L}]+/u)?.[0] ?? "";
    return word.length > 2 ? `${word[0].toUpperCase()}${word[1].toLowerCase()}` : null;
  };
  const chinEffortShort = text => {
    const word = String(text ?? "").trim().toLowerCase();
    return CHIN_EFFORTS[word] ?? chinTwo(word);
  };
  const chinModeShort = text => {
    const line = String(text ?? "").trim();
    const hit = CHIN_MODES.find(([re]) => re.test(line));
    return hit ? hit[1] : null;
  };
  // Узел, в котором лежит подпись: родитель единственного непустого текста.
  const chinHolder = button => {
    let found = null;
    const take = node => {
      if (found && found !== node) { found = false; return; }
      found = node;
    };
    const walk = node => {
      const kids = node.childNodes ?? [];
      // Узел без детей, но с текстом (стенд тестов) — сам себе держатель.
      if (kids.length === 0 && chinText(node)) { take(node); return; }
      for (const kid of kids) {
        if (kid.nodeType === 3) {
          if (String(kid.nodeValue ?? kid.textContent ?? "").trim()) take(node);
        } else if (kid.nodeType === 1) {
          walk(kid);
        }
        if (found === false) return;
      }
    };
    walk(button);
    return found || null;
  };
  const chinMarked = new Set();
  const chinMark = (node, name, value) => {
    if (!node) return;
    if (node.getAttribute(name) !== value) node.setAttribute(name, value);
    chinMarked.add(node);
  };
  // Подсказки, что поставили мы (WF195): снимаем только свою — чужую title не трогаем.
  const chinTitled = new Map();
  const chinTitle = (button, hint) => {
    // Кнопку режима держит карточка PMP (раздел 12з², #6591) — подсказка браузера рядом с ней лишняя.
    if (button.hasAttribute?.(MODE_HINT_HOLD_ATTRIBUTE)) hint = null;
    const own = chinTitled.get(button);
    if (!hint) {
      if (own != null) { if (button.getAttribute?.("title") === own) button.removeAttribute?.("title"); chinTitled.delete(button); }
      return;
    }
    const now = button.getAttribute?.("title");
    // Чужая подсказка — не наша; «Bypass permissions» — наша же от прошлой установки (page-41/42).
    if (now != null && now !== own && now !== "Bypass permissions") return;
    if (now !== hint) button.setAttribute?.("title", hint);
    chinTitled.set(button, hint);
  };
  const chinClear = () => {
    for (const [button, hint] of chinTitled) { try { if (button.getAttribute("title") === hint) button.removeAttribute("title"); } catch {} }
    chinTitled.clear();
    for (const node of chinMarked) {
      try { node.removeAttribute(CHIN_ATTRIBUTE); node.removeAttribute(CHIN_SHORT_ATTRIBUTE); node.removeAttribute(CHIN_TAIL_ATTRIBUTE); } catch {}
    }
    chinMarked.clear();
    try { for (const node of document.querySelectorAll(`[${CHIN_ROW_ATTRIBUTE}]`)) node.removeAttribute(CHIN_ROW_ATTRIBUTE); } catch {}
  };
  // Сироты прошлой установки: метки на чужих узлах переживают перезагрузку
  // inject.js — снимаем их до первой разметки.
  try {
    for (const node of document.querySelectorAll(`[${CHIN_ATTRIBUTE}],[${CHIN_SHORT_ATTRIBUTE}]`)) {
      node.removeAttribute(CHIN_ATTRIBUTE);
      node.removeAttribute(CHIN_SHORT_ATTRIBUTE);
      node.removeAttribute(CHIN_TAIL_ATTRIBUTE);
    }
  } catch {}
  track(chinClear);
  // Стрелка ⌄ настроек диктовки: следующий сосед микрофона (или его обёртки,
  // не выше двух уровней) — кнопка без текста с меню или с подписью про голос.
  const chinChevron = (mic, chin) => {
    let node = mic;
    for (let depth = 0; depth < 3 && node && node !== chin; depth += 1, node = node.parentElement) {
      const next = nextReal(node);
      if (!next) continue;
      const buttons = next.tagName === "BUTTON" ? [next] : [...(next.querySelectorAll?.("button") ?? [])];
      if (buttons.length !== 1 || chinText(next) !== "") return null;
      const label = String(buttons[0].getAttribute("aria-label") ?? "");
      return buttons[0].hasAttribute("aria-haspopup") || /dictation|voice|microphone|speech|language|diktat/i.test(label)
        ? next : null;
    }
    return null;
  };
  // Обёртка микрофона, в которой больше ничего нет, прячется вместе с ним — не
  // выше двух уровней и не саму строку.
  const chinMicShell = (mic, chin) => {
    let node = mic;
    for (let depth = 0; depth < 2; depth += 1) {
      const parent = node.parentElement;
      if (!parent || parent === chin || realKids(parent).length !== 1 || chinText(parent) !== "") break;
      node = parent;
    }
    return node;
  };
  // Влезают ли полные подписи (#7638, #8732). Кнопки строки не ужимаются (правила
  // раздела 4), поэтому в тесной строке правая группа вылезает за край и кружок
  // режется. Меряем вылет; есть — подписи коротко и помним, какой ширины строке
  // хватило бы. Назад к полным — когда строка шире этого с запасом или сменились
  // сами подписи (тогда меряем заново). Замер в том же проходе: кадра между
  // снятием и возвратом метки нет.
  const chinFit = new WeakMap();
  // Замер 04.10 (Claude 2.9939): строка → три обёртки по одному ребёнку → ряд
  // (flex, padding-right 10) из левой группы, распорки (flex-1, min-w-0 — в ней
  // место значка галереи) и правой группы. Тесно — правая группа вылезает за
  // поле ряда, распорка сжата до нуля. Считаем худшее из трёх: вылет группы за
  // поле ряда, прокрутку ряда и прокрутку любого его ребёнка. С WF261 (#9272) тесный
  // ряд выпирает влево (правило ниже: кружок стоит у своего края), поэтому вылет
  // меряется с обеих сторон: за правое поле и за левое.
  const chinOver = chin => {
    let host = chin;
    for (let kids = realKids(host); kids.length === 1 && kids[0].children?.length; kids = realKids(host)) host = kids[0];
    const box = host.getBoundingClientRect?.();
    if (!box) return 0;
    let pad = 0;
    let padStart = 0;
    try { const style = getComputedStyle(host); pad = parseFloat(style.paddingRight) || 0; padStart = parseFloat(style.paddingLeft) || 0; } catch {}
    const spill = node => {
      const value = Number(node.scrollWidth) - Number(node.clientWidth);
      return Number.isFinite(value) ? value : 0;
    };
    let over = spill(host);
    for (const kid of host.children ?? []) {
      const rect = kid.getBoundingClientRect?.();
      if (rect && rect.width > 0) over = Math.max(over, rect.right - (box.right - pad), box.left + padStart - rect.left);
      over = Math.max(over, spill(kid));
    }
    return over;
  };
  // Запас строки при короткой подписи (WF183): свободное место строки минус вылет. Меньше нуля — кружок
  // за краем; пол колонки (2г) берёт столько. Распорка Claude (ребёнок ряда без кнопок, flex-1 basis-0 —
  // замер 09.10, окно Рика) съедает ВСЁ свободное место: свободно ровно столько, сколько она шириной. До
  // WF195 запас мерился от её правого края — всегда 0, и пол рос на 4 каждый проход, пока строка не
  // переставала быть тесной (колонка 258 → 407, docs/live-190.png). Распорки нет — промежуток между
  // последней группой и соседом слева.
  const chinSlack = chin => {
    let host = chin;
    for (let kids = realKids(host); kids.length === 1 && kids[0].children?.length; kids = realKids(host)) host = kids[0];
    const spacers = [...(host.children ?? [])].filter(kid => !kid.querySelector?.("button"));
    const groups = [...(host.children ?? [])].filter(kid => !spacers.includes(kid));
    if (groups.length >= 2 && spacers.length) {
      const free = spacers.reduce((sum, kid) => sum + Math.max(0, kid.getBoundingClientRect?.()?.width ?? 0), 0);
      return free - Math.max(0, chinOver(chin));
    }
    const kids = [...(host.children ?? [])].map(kid => [kid, kid.getBoundingClientRect?.()]).filter(([, rect]) => rect && rect.width > 0);
    if (kids.length < 2) return null;
    const [last, lastRect] = kids.at(-1);
    let before = -Infinity;
    for (const [kid, rect] of kids) if (kid !== last) before = Math.max(before, rect.right);
    return lastRect.left - before - Math.max(0, chinOver(chin));
  };
  const chinRowFit = (chin, sig) => {
    const box = chin.getBoundingClientRect?.();
    if (!box || !(box.width > 0)) return;
    let fit = chinFit.get(chin);
    // Пол — только у строки доки с кружком токенов: ради него он и есть.
    const docked = (() => { try { return Boolean(wideState.on && sideDock(wideState.panel)?.contains?.(chin) && chin.querySelector(USAGE_RING_SELECTOR)); } catch { return false; } })();
    if (!fit || fit.sig !== sig) { fit = { sig, need: 0 }; chinFit.set(chin, fit); if (docked) sideFloorDrop("chin"); }
    const narrow = chin.hasAttribute(CHIN_ROW_ATTRIBUTE);
    // Пол колонки по короткой строке (WF183): кружок токенов не уходит за край ни при какой ширине.
    if (narrow && docked) { const slack = chinSlack(chin); if (slack != null) sideFloorNeed("chin", CHIN_FLOOR_SLACK - slack); }
    if (narrow && fit.need && box.width < fit.need + CHIN_ROW_SLACK) return;
    if (narrow) chin.removeAttribute(CHIN_ROW_ATTRIBUTE);
    const over = chinOver(chin);
    if (over > 0.5) { fit.need = box.width + over; chin.setAttribute(CHIN_ROW_ATTRIBUTE, ""); }
  };
  const markChin = () => {
    let rows = [];
    try { rows = [...document.querySelectorAll(CHIN_SELECTOR)]; } catch {}
    const seen = new Set();
    // Спрятанное: кнопки внутри него метки не получают.
    const hidden = new Set();
    for (const chin of rows) {
      const labels = [];
      // Микрофон и ⌄ ищем во всём поле: с Claude 4.29 микрофон стоит у отправки, вне строки (#11173).
      const field = chin.closest?.(COMPOSER_SELECTOR) ?? chin;
      let mics = [];
      try { mics = [...field.querySelectorAll(DICTATE_SELECTOR)]; } catch {}
      for (const mic of mics) {
        const shell = chinMicShell(mic, chin);
        chinMark(shell, CHIN_ATTRIBUTE, "hide");
        seen.add(shell);
        hidden.add(shell);
        const chevron = chinChevron(shell, chin);
        if (chevron) { chinMark(chevron, CHIN_ATTRIBUTE, "hide"); seen.add(chevron); hidden.add(chevron); }
      }
      let settings = [];
      try { settings = [...field.querySelectorAll(DICTATE_SETTINGS_SELECTOR)]; } catch {}
      for (const button of settings) {
        const shell = chinMicShell(button, chin);
        chinMark(shell, CHIN_ATTRIBUTE, "hide");
        seen.add(shell);
        hidden.add(shell);
      }
      for (const button of chin.querySelectorAll("button")) {
        if (seen.has(button) || [...hidden].some(node => node.contains?.(button))) continue;
        const label = String(button.getAttribute("aria-label") ?? "");
        // Кружок контекста — свой раздел (6, 12з): его размер не трогаем.
        if (/^(?:Usage|Использование):/.test(label)) continue;
        const text = chinText(button);
        if (!text) { chinMark(button, CHIN_ATTRIBUTE, "icon"); seen.add(button); continue; }
        chinMark(button, CHIN_ATTRIBUTE, "text");
        seen.add(button);
        labels.push(text);
        // Обёртки кнопки до самой строки — «ряд»: им нельзя ужиматься уже
        // своих кнопок (замер 23.09, окно 177: 14/22/22 px и видна одна буква).
        for (let node = button.parentElement; node && node !== chin; node = node.parentElement) {
          if (seen.has(node)) break;
          chinMark(node, CHIN_ATTRIBUTE, "row");
          seen.add(node);
        }
        let short = null;
        let tail = "";
        let hint = "";
        if (button.matches?.(CHIN_MODEL_SELECTOR) || button.closest?.(CHIN_MODEL_SELECTOR)) {
          const parts = chinModelParts(text);
          if (parts) [short, tail] = parts;
        }
        // Эффорт — тоже в две строки, в пару к модели (#9813): «Effort» мелко, код «Хх» крупно (WF183).
        else if (button.matches?.(CHIN_EFFORT_SELECTOR)) { const code = chinEffortShort(text); if (code) [short, tail] = [CHIN_EFFORT_WORD, code]; }
        // Код режима («Au», «Ac») — ещё и имя для разделов 12ц и «Включить»; в подпись — как есть, «Хх» (WF183);
        // Bypass permissions — «Bp», не «By» (#9195, слово Элвиса 09.10: «Где Bypass permissions? Там BY — должно быть BP»).
        else {
          const code = chinModeShort(text); short = code ? (CHIN_MODE_LABELS[code] ?? code) : null;
          if (code === "By") hint = "Bypass permissions";
        }
        // Короткая подпись — с подсказкой полным именем (слово Элвиса 09.10 04:10: «Bp — должно называться,
        // чтоб люди понимали»; WF195 — у всех: подписи коротко всегда). Сменилась подпись — за ней и подсказка.
        chinTitle(button, short ? hint || text : null);
        const holder = short ? chinHolder(button) : null;
        // Прежняя короткая подпись внутри кнопки, которой больше нет (сменилась
        // модель, подпись переехала в другой узел), снимается.
        for (const node of chinMarked) {
          if (node !== holder && (node === button || button.contains?.(node)) && node.hasAttribute?.(CHIN_SHORT_ATTRIBUTE)) {
            node.removeAttribute(CHIN_SHORT_ATTRIBUTE);
            node.removeAttribute(CHIN_TAIL_ATTRIBUTE);
          }
        }
        if (holder) {
          chinMark(holder, CHIN_SHORT_ATTRIBUTE, short);
          if (tail) { if (holder.getAttribute(CHIN_TAIL_ATTRIBUTE) !== tail) holder.setAttribute(CHIN_TAIL_ATTRIBUTE, tail); }
          else if (holder.hasAttribute?.(CHIN_TAIL_ATTRIBUTE)) holder.removeAttribute(CHIN_TAIL_ATTRIBUTE);
          seen.add(holder);
        }
      }
      try { chinRowFit(chin, labels.join("|")); } catch {}
    }
    // Узлы, которые больше не наши (строку пересобрал React, подпись сменилась
    // и короткой формы нет), метку теряют.
    for (const button of [...chinTitled.keys()]) if (!button.isConnected) chinTitled.delete(button);
    for (const node of [...chinMarked]) {
      if (seen.has(node) && node.isConnected) continue;
      try { node.removeAttribute(CHIN_ATTRIBUTE); node.removeAttribute(CHIN_SHORT_ATTRIBUTE); node.removeAttribute(CHIN_TAIL_ATTRIBUTE); } catch {}
      chinMarked.delete(node);
    }
  };

  // Enter над кружком (WF183, слово Элвиса 09.10 03:15–03:30: «центр кружка отправки и Enter на одной
  // вертикали… Enter должен быть правее, центр ровно над кружочком»): кнопка отправки (или «Стоп» на её
  // месте) сдвигается по горизонтали свойством translate так, чтобы её середина встала над серединой
  // кружка токенов строки под ней. Кружок не под ней (широкое поле — Enter в строке модели), поле свёрнуто,
  // сдвиг больше SEND_RING_MAX — не трогаем. Сдвиг считается от места без нашего сдвига.
  const SEND_RING_MAX = 24;
  const sendRing = { node: null, shift: 0 };
  const sendRingClear = () => {
    try { sendRing.node?.style?.removeProperty("translate"); } catch {}
    sendRing.node = null;
    sendRing.shift = 0;
  };
  track(sendRingClear);
  const alignSendToRing = () => {
    let send = null;
    try {
      for (const node of document.querySelectorAll(`${SEND_SELECTOR},[data-testid="code-prompt-stop"]`)) {
        const rect = node.getBoundingClientRect?.();
        if (rect && rect.width > 0 && rect.height > 0) { send = node; break; }
      }
    } catch { send = null; }
    if (sendRing.node && sendRing.node !== send) sendRingClear();
    if (!send || state.stage === STAGE_COLLAPSED) { sendRingClear(); return null; }
    const own = sendRing.node === send ? sendRing.shift : 0;
    const box = send.getBoundingClientRect();
    const mid = (box.left + box.right) / 2 - own;
    let ring = null;
    try {
      for (const node of document.querySelectorAll(USAGE_RING_SELECTOR)) {
        const rect = node.getBoundingClientRect?.();
        if (!(rect && rect.width > 0 && rect.height > 0)) continue;
        if (rect.top < box.bottom - 1 || rect.top - box.bottom > 60) continue;
        if (Math.abs((rect.left + rect.right) / 2 - mid) > SEND_RING_MAX) continue;
        if (!ring || rect.top < ring.top) ring = rect;
      }
    } catch { ring = null; }
    if (!ring) { sendRingClear(); return null; }
    const shift = Math.round(((ring.left + ring.right) / 2 - mid) * 2) / 2;
    sendRing.node = send;
    sendRing.shift = shift;
    const value = shift ? `${shift}px 0px` : "";
    if ((send.style.getPropertyValue("translate") || "") !== value) {
      if (value) send.style.setProperty("translate", value); else send.style.removeProperty("translate");
    }
    return shift;
  };
  // Кружок токенов — целиком у своего края (#9272, #9259; слово Элвиса 09.10 03:50: «кругленькая внизу почему-то
  // обрезана… что-то с марджинами, с впадинами в этих контейнерах»). Класс «свой элемент у края окна или колонки
  // режется контейнером»: обёртки строки на пути к кружку (и сама строка) его не режут — overflow: visible;
  // свёрнутые узлы (метка свёртки раздела 6) не трогаем, их обрез — сама свёртка. Строке не хватило места и
  // при коротких подписях — ряд выпирает влево, к плюсику, а кружок остаётся на месте у правого поля (запас —
  // поле MIC_ROOM_INSET правилом раздела 4). Пока место есть, его забирает распорка Claude (flex-1), и
  // flex-end ничего не сдвигает. Тесноту по-прежнему ловит chinOver (с обеих сторон) — подписи коротко, пол колонки.
  lateRules.push(
    `${CHIN_SELECTOR}:not([${BLOCK_ATTRIBUTE}]),${CHIN_SELECTOR} :has(${USAGE_RING_SELECTOR}):not([${BLOCK_ATTRIBUTE}]){overflow:visible !important}`,
    `${CHIN_ROW_SELECTOR}{justify-content:flex-end !important}`,
    // Микрофон Claude вне нижней строки (у отправки, #11173) — та же метка "hide", правило — по всему полю.
    `${COMPOSER_SELECTOR} [${CHIN_ATTRIBUTE}="hide"]{display:none !important}`,
  );
  HATCH && Object.assign(HATCH, { chinModelShort, chinModelParts, chinEffortShort, chinModeShort });

