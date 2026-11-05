  // ---- 12с³. Пункт «Ждёт тебя» — ссылкой на свой файл (#10617) ------------------
  // Слово Элвиса 22.10: «баннер-пицца должна быть ссылка, чтоб я на неё нажимаю, и баннер пицца открывался»; ответ
  // 31.10 04:00 (файл 204, 3.3 ★А): «пункт — ссылкой на файл да, кнопку-слово нет». Кнопок-слов («да баннеру»…) нет,
  // кнопки «Понял» и прочие сняты 22.10 (#10643) и не возвращаются.
  // Раздел «Ждёт тебя» — как у 12с² (waitSections). Пункт — свёртка раздела (форма ELVIS.md с 30.10:
  // «N · метка · вещь — что от него») или пункт списка `li`. Файл пункта — первый, что открывает клик по файлу
  // из чата (fileOpenable раздела 12д): ссылка на файл (путь, file://, computer://, относительная — от папки чата,
  // как у 12д¹), ссылка Claude на файл (fileRef), путь в `коде` или абсолютный путь в тексте. У свёртки файл ищется
  // в её теле, у `li` — в нём самом (без вложенных списков). Номер файла PimpViewer («ФАЙЛ 204») в путь не
  // превращается — у страницы нет его карты.
  // Название: у свёртки — «вещь» её подписи (последний кусок до « — » после « · »); голова свёртки рисует подпись
  // своими узлами без текста (стрелка, начало, ссылка, хвост — из атрибутов: копия, «Прочитано» и ключи свёрток
  // текста не видят), нажатие на начало и хвост — свернуть/развернуть как было. У `li` — его первый жирный (не
  // фраза 12с² и не ссылка) — метка на родном strong, текст React не режем. Нажал — файл открывается тем же путём,
  // что клик по файлу в чате (fileClick, /open-html?mode=click). Файла нет — пункт как был.
  const WAIT_FILE_ATTRIBUTE = "data-myclaude-wait-file";
  const WAIT_FILE_PART_ATTRIBUTE = "data-myclaude-wait-file-part";
  const WAIT_FILE_TEXT_ATTRIBUTE = "data-myclaude-wait-file-text";
  const WAIT_FILE_REST_ATTRIBUTE = "data-myclaude-wait-file-rest";
  const WAIT_FILE_ABS_RE = /(?:^|[\s(«"'])(\/[^\s«»"'()<>]+?\.[a-z0-9]{1,8})(?=$|[\s).,;:!?»"'])/iu;
  const WAIT_FILE_NAME_RE = /^[^\s:«»"'()<>]+\.[a-z0-9]{1,8}$/i;
  const WAIT_FILE_SCHEME_RE = /^[a-z][a-z0-9+.-]*:/i;
  const WAIT_FILE_LOCAL_RE = /^(?:file|computer):\/\//i;
  const waitFile = { marks: new Map(), heads: new Map(), clicks: 0, last: null };
  // Путь, который откроет клик по файлу из чата, или "".
  const waitFileResolve = raw => {
    const text = sayNorm(raw);
    if (!text || (WAIT_FILE_SCHEME_RE.test(text) && !WAIT_FILE_LOCAL_RE.test(text)) || /^[#?]/.test(text)) return "";
    try { return mentionLinkPath({ path: text }); } catch { return ""; }
  };
  // Файл среди узлов пункта; own — узел годится (у `li` — не из вложенного пункта).
  const waitFileOf = (nodes, own = () => true) => {
    for (const node of nodes) {
      let found = [];
      try { found = [...(node.matches?.("a[href],[role=\"button\"],code") ? [node] : []), ...node.querySelectorAll("a[href],[role=\"button\"],code")]; } catch { found = []; }
      for (const el of found) {
        if (!own(el) || foldOwn(el)) continue;
        let path = "";
        if (el.tagName === "A") path = waitFileResolve(el.getAttribute("href"));
        else if (el.tagName === "CODE") {
          const text = sayNorm(el.textContent);
          path = text.startsWith("/") || WAIT_FILE_NAME_RE.test(text) ? waitFileResolve(text) : "";
        } else {
          let link = null;
          try { link = mentionLinkAt(el); } catch { link = null; }
          try { path = link ? mentionLinkPath(link) : ""; } catch { path = ""; }
        }
        if (path) return path;
      }
    }
    for (const node of nodes) {
      if (foldOwn(node) || foldRaw(node)) continue;
      const hit = WAIT_FILE_ABS_RE.exec(String(node.textContent ?? ""));
      const path = hit ? waitFileResolve(hit[1]) : "";
      if (path) return path;
    }
    return "";
  };
  // Подпись свёртки «N · метка · вещь — что» → { pre, name, rest }; вещи нет — null.
  const waitFileSplit = title => {
    const text = sayNorm(title);
    const dash = text.search(/\s[—–]\s/u);
    const lead = dash < 0 ? text : text.slice(0, dash);
    const rest = dash < 0 ? "" : text.slice(dash);
    const cut = lead.lastIndexOf(" · ");
    const tail = cut < 0 ? lead : lead.slice(cut + 3);
    // Значки перед вещью («🔴 Распродажа») — к началу, не в ссылку.
    const marks = /^[^\p{L}\p{N}]*/u.exec(tail)[0];
    const pre = (cut < 0 ? "" : lead.slice(0, cut + 3)) + marks;
    const name = tail.slice(marks.length).trim();
    return name ? { pre, name, rest } : null;
  };
  // Голова свёртки рисует подпись своими узлами: стрелка+начало, ссылка, хвост (::after головы).
  const waitFileHead = (head, split) => {
    let [pre, link] = head.children ?? [];
    if (pre?.getAttribute?.(WAIT_FILE_PART_ATTRIBUTE) !== "pre" || link?.getAttribute?.(WAIT_FILE_ATTRIBUTE) !== "fold") {
      while (head.firstChild) head.firstChild.remove();
      pre = document.createElement("span");
      pre.setAttribute(WAIT_FILE_PART_ATTRIBUTE, "pre");
      link = document.createElement("span");
      link.setAttribute(WAIT_FILE_ATTRIBUTE, "fold");
      link.setAttribute("role", "link");
      head.appendChild(pre);
      head.appendChild(link);
    }
    foldSet(pre, WAIT_FILE_TEXT_ATTRIBUTE, split.pre);
    foldSet(link, WAIT_FILE_TEXT_ATTRIBUTE, split.name);
    foldSet(link, "aria-label", `Открыть файл: ${split.name}`);
    foldSet(head, WAIT_FILE_REST_ATTRIBUTE, split.rest);
    return link;
  };
  const waitFileHeadOff = head => {
    try {
      for (const kid of [...(head.children ?? [])]) if (kid.hasAttribute?.(WAIT_FILE_PART_ATTRIBUTE) || kid.hasAttribute?.(WAIT_FILE_ATTRIBUTE)) kid.remove();
      head.removeAttribute(WAIT_FILE_REST_ATTRIBUTE);
    } catch {}
  };
  // Метки — ровно на пунктах с файлом, что сейчас в ленте; ушедшее снято.
  const waitFilePaint = () => {
    if (!themable || !state.alive) return waitFile.marks.size;
    const marks = new Map();
    const heads = new Map();
    for (const block of waitSections()) {
      const folds = block.filter(node => node.hasAttribute?.(FOLD_HEAD_ATTRIBUTE) && node.__myclaudeFold && !node.__myclaudeFold.whole);
      // Пункт — свёртка самого раздела; вложенная (внутри тела пункта) — часть пункта.
      const items = folds.filter(head => !folds.some(other => other !== head && (other.__myclaudeFold.body.includes(head.__myclaudeFold.open) || foldInside(head.__myclaudeFold, other.__myclaudeFold))));
      const inside = new Set(items.flatMap(head => head.__myclaudeFold.body));
      for (const head of items) {
        const split = waitFileSplit(head.__myclaudeFold.title);
        const path = split ? waitFileOf(head.__myclaudeFold.body) : "";
        if (!path) continue;
        const link = waitFileHead(head, split);
        heads.set(head, link);
        marks.set(link, path);
      }
      for (const node of block) {
        if (inside.has(node) || foldOwn(node) || foldRaw(node)) continue;
        let lis = [];
        try { lis = [...(node.tagName === "LI" ? [node] : []), ...node.querySelectorAll("li")]; } catch { lis = []; }
        for (const li of lis) {
          const own = el => el.closest?.("li") === li;
          let bolds = [];
          try { bolds = [...li.querySelectorAll("strong,b")]; } catch { bolds = []; }
          const name = bolds.find(bold => own(bold) && !bold.closest?.("a") && sayNorm(bold.textContent) && !waitPhraseOf(bold));
          const path = name ? waitFileOf([li], own) : "";
          if (path) marks.set(name, path);
        }
      }
    }
    for (const [node] of waitFile.marks) {
      if (!marks.has(node) && node.getAttribute?.(WAIT_FILE_ATTRIBUTE) === "name") { try { node.removeAttribute(WAIT_FILE_ATTRIBUTE); } catch {} }
    }
    for (const head of waitFile.heads.keys()) if (!heads.has(head)) waitFileHeadOff(head);
    for (const [node] of marks) if (!heads.has(node) && node.getAttribute?.(WAIT_FILE_ATTRIBUTE) !== "fold") foldSet(node, WAIT_FILE_ATTRIBUTE, "name");
    waitFile.marks = marks;
    waitFile.heads = heads;
    return marks.size;
  };
  const waitFileAt = target => {
    const node = target?.closest?.(`[${WAIT_FILE_ATTRIBUTE}]`) ?? null;
    return node && waitFile.marks.has(node) ? node : null;
  };
  const waitFileOpen = node => {
    const path = waitFile.marks.get(node);
    if (!path) return false;
    waitFile.clicks += 1;
    waitFile.last = path;
    try { fileClick(path, node); } catch {}
    return true;
  };
  // Нажатие на название (захват документа, раньше свёрток 12ф): файл открыт, свёртка не переключается. Клавиатура —
  // у головы свёртки, как была (Enter — свернуть/развернуть); своей подписки на клавиши нет.
  const onWaitFileClick = event => {
    if (event?.isTrusted !== true || !state.alive) return;
    if ((event.button ?? 0) !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const node = waitFileAt(event.target);
    if (!node) return;
    let selected = "";
    try { selected = String(window.getSelection?.()?.toString?.() ?? ""); } catch {}
    if (selected && node.getAttribute(WAIT_FILE_ATTRIBUTE) === "name") return;
    event.preventDefault?.();
    event.stopImmediatePropagation?.();
    if (Number(event.detail) > 1) return;
    waitFileOpen(node);
  };
  on(document, "click", onWaitFileClick, true);
  // Сироты прошлой установки.
  try {
    for (const node of document.querySelectorAll(`[${WAIT_FILE_PART_ATTRIBUTE}],[${WAIT_FILE_ATTRIBUTE}="fold"]`)) node.remove();
    for (const node of document.querySelectorAll(`[${WAIT_FILE_ATTRIBUTE}],[${WAIT_FILE_REST_ATTRIBUTE}]`)) { node.removeAttribute(WAIT_FILE_ATTRIBUTE); node.removeAttribute(WAIT_FILE_REST_ATTRIBUTE); }
  } catch {}
  track(() => {
    for (const head of waitFile.heads.keys()) waitFileHeadOff(head);
    for (const node of waitFile.marks.keys()) { try { node.removeAttribute(WAIT_FILE_ATTRIBUTE); } catch {} }
    waitFile.marks.clear();
    waitFile.heads.clear();
  });
  // Вид — как ссылка: цвет акцента, подчёркивание; у свёртки подпись — из атрибутов, стрелка — по её состоянию.
  lateRules.push(
    `[${WAIT_FILE_ATTRIBUTE}]{color:var(--cds-text-accent,rgb(245,158,11));cursor:pointer;text-decoration:underline;text-decoration-color:color-mix(in srgb,currentColor 45%,transparent);text-underline-offset:3px;border-radius:4px}`,
    `[${WAIT_FILE_ATTRIBUTE}]:hover{text-decoration-color:currentColor}`,
    `[${WAIT_FILE_ATTRIBUTE}="fold"]::after,[${WAIT_FILE_PART_ATTRIBUTE}="pre"]::after{content:attr(${WAIT_FILE_TEXT_ATTRIBUTE})}`,
    `[${FOLD_HEAD_ATTRIBUTE}="closed"]>[${WAIT_FILE_PART_ATTRIBUTE}="pre"]::before{content:"▸ "}`,
    `[${FOLD_HEAD_ATTRIBUTE}="open"]>[${WAIT_FILE_PART_ATTRIBUTE}="pre"]::before{content:"▾ "}`,
    `[${FOLD_HEAD_ATTRIBUTE}][${WAIT_FILE_REST_ATTRIBUTE}]::after{content:attr(${WAIT_FILE_REST_ATTRIBUTE})}`,
  );
  // Пункты «Ждёт тебя» со ссылкой на файл (раздел 12с³): сколько в ленте, нажатий, последний открытый путь.
  statusPart("waitFiles", () => ({ count: waitFile.marks.size, clicks: waitFile.clicks, last: waitFile.last }));
  HATCH && Object.assign(HATCH, { waitFilePaint, waitFile, waitFileOf, waitFileSplit });
