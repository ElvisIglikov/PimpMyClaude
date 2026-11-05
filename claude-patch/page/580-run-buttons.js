  // ---- 12т. Своя ▶ у команд в вынесенных окнах (#7941, WF103) ---------------
  // Слово Элвиса: «нету кнопки „запустить“, есть только кнопка „скопировать“…
  // отсюда же удобней запускать». Run у Claude есть только в главном окне
  // (провайдер терминала, CONTRACTS WF102 «Run (#7914)»); в вынесенном — своя «▶»
  // рядом с «Copy code» Claude, её стиль и размер, на тех же блоках, что у Claude
  // (его код, живой бандл 27.09): язык bash/sh/shell/shellscript/zsh; или блок
  // без языка («text»), где команда начинается с «!» либо первое слово — из его
  // белого списка (или «./…»). Для любого языка — одна простая строка без
  // | & ; < > ( ) ` $ \, скрытых и управляющих символов — запуск сразу. Сложный
  // bash-блок или «!» (метасимволы, несколько строк; WF111, судья page) — ▶ тоже
  // есть, но клик открывает своё окошко с полным текстом, запуск только оттуда.
  // Только блоки ответа (строка ленты assistant_text/assistant) — не поле ввода и
  // не вывод инструментов. Команда — текст блока без хвостовых пробелов и
  // переводов строки (у Claude trimEnd), у «!» — без самого «!».
  // Разведка P2 27.09 (тестовый чат PimpTest102): LocalSessions.runBashCommand(
  // chat, command) моста (у попапа — window.opener) исполняет команду в скрытой
  // оболочке ЭТОГО чата, в его папке, и отдаёт {stdout, stderr, code} или
  // {error}; в ленту чата сам ничего не кладёт и хода агента не запускает (так
  // Claude делает свои «!»-команды, в чат ответ шлёт уже он сам). Терминала у
  // вынесенного окна нет. Поэтому вывод показываем сами — под блоком, в этом окне.
  // reportRunFollowUp не зовём никогда. Enter не шлём, поле ввода не трогаем.
  // Нажатие: пока идёт — «…», повтор ничего не делает; через RUN_WAIT_MS — снова
  // «▶» (сама команда не трогается); ошибка — плашка «Не запустилось», без
  // повтора. Агент в чате работает — кнопка неактивна («агент работает»).
  const RUN_ATTRIBUTE = "data-myclaude-run";
  const RUN_OUT_ATTRIBUTE = "data-myclaude-run-out";
  const RUN_WAIT_MS = 60000;
  const RUN_OUT_MAX = 4000;
  const RUN_KEEP = 20;
  const RUN_LANGS = new Set(["bash", "sh", "shell", "shellscript", "zsh"]);
  const RUN_WORDS = new Set("aws brew bun bunx cargo cd chmod claude cp curl deno docker gcloud gh git grep kubectl ls mkdir mv node npm npx pip pip3 pnpm python python3 rg rm sed ssh tar uv wget yarn".split(" "));
  const RUN_LEAD_RE = /^(?:sudo\s+)?(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(\S+)/;
  const RUN_BAD_RE = /[|&;<>()`$\\]/;
  const RUN_HIDDEN_RE = /[­؜᠎​-‏‪-‮⁠-⁩﻿]/;
  const RUN_ROW_SELECTOR = '[data-testid="transcript-row"][data-perf-row="assistant_text"],[data-testid="transcript-row"][data-perf-row="assistant"]';
  // #11618: надпись на обоих языках перечислением через запятую, не uiAria: :is() стаб DOM тестов не понимает.
  const RUN_COPY_SELECTOR = ["Copy code", "Копировать код", "Copied", "Скопирован", "Скопировано"]
    .map(word => `button[aria-label="${word}"]`).join(",");
  const runState = { buttons: 0, clicks: 0, runs: 0, via: null, fails: 0, last: null, going: new Map(), outputs: new Map(), nodes: new Map(), confirm: null };
  // Команда блока по пропсам Claude {text, lang, rawLang}; не его блок — null.
  const runCommandOf = props => {
    const whole = String(props?.text ?? "").trimEnd();
    const tag = String(props?.rawLang ?? props?.lang ?? "").trim().toLowerCase();
    const plainText = tag === "text" || tag === "";
    const command = plainText ? whole.replace(/^![ \t]*/, "") : whole;
    const bang = command !== whole;
    let simple = false;
    // Без языка — одна строка (гейт 2): «ls\nrm -rf build» не одна простая команда.
    if (plainText && !RUN_BAD_RE.test(command) && !/[\r\n]/.test(command)) {
      const lead = RUN_LEAD_RE.exec(command.trimStart())?.[1] ?? "";
      simple = lead.startsWith("./") || RUN_WORDS.has(lead);
    }
    if (!(RUN_LANGS.has(tag) || bang || simple)) return null;
    if (!command.trim() || RUN_HIDDEN_RE.test(command) || RUN_BAD_RE.test(command) || /[\r\n\0-\x08\x0b-\x1f\x7f]/.test(command)) return null;
    return command;
  };
  // Сложная команда (WF111, security P2-2, судья page): блок bash/sh/shell/
  // shellscript/zsh или «!» с | & ; < > ( ) ` $ \ или в несколько строк. ▶ у неё
  // есть, запуск — только из окошка с полным текстом (runConfirmOpen). Скрытые и
  // управляющие символы (кроме \n и \t), \r — без ▶: окошко показало бы не то,
  // что уйдёт в оболочку. Простая команда — null (её берёт runCommandOf).
  const runComplexOf = props => {
    if (runCommandOf(props)) return null;
    const whole = String(props?.text ?? "").trimEnd();
    const tag = String(props?.rawLang ?? props?.lang ?? "").trim().toLowerCase();
    const command = tag === "text" || tag === "" ? whole.replace(/^![ \t]*/, "") : whole;
    if (!(RUN_LANGS.has(tag) || command !== whole)) return null;
    if (!command.trim() || RUN_HIDDEN_RE.test(command) || /[\0-\x08\x0b-\x1f\x7f]/.test(command)) return null;
    return command;
  };
  // Пропсы блока — у компонента в нескольких шагах над div.epitaxy-codeblock.
  const runPropsOf = block => {
    let fiber = chatFiberOf(block);
    for (let hop = 0; fiber && hop < 8; hop += 1, fiber = fiber.return) {
      const props = fiber.memoizedProps;
      if (props && typeof props.text === "string" && ("lang" in props || "rawLang" in props)) return props;
    }
    return null;
  };
  // Блоки ответа с командой: [{block, copy, command, complex}] в порядке ленты.
  const runBlocks = () => {
    const list = [];
    let blocks = [];
    try { blocks = [...document.querySelectorAll(".epitaxy-codeblock")]; } catch { return list; }
    for (const block of blocks) {
      if (!block.closest?.(RUN_ROW_SELECTOR)) continue;
      if (block.closest?.('[contenteditable="true"]') || state.composerBlock?.contains?.(block)) continue;
      const props = runPropsOf(block);
      const simple = runCommandOf(props);
      const command = simple ?? runComplexOf(props);
      if (!command) continue;
      let copy = null;
      try { copy = block.querySelector(RUN_COPY_SELECTOR); } catch {}
      if (!copy?.parentElement) continue;
      list.push({ block, copy, command, complex: !simple });
    }
    return list;
  };
  const runSessions = () => {
    let sessions = null;
    try { sessions = window["claude.web"]?.LocalSessions ?? null; } catch { sessions = null; }
    if (!sessions?.runBashCommand) { try { sessions = window.opener?.["claude.web"]?.LocalSessions ?? null; } catch { sessions = null; } }
    return sessions?.runBashCommand ? sessions : null;
  };
  const runRemember = (map, key, value) => {
    map.delete(key);
    map.set(key, value);
    while (map.size > RUN_KEEP) map.delete(map.keys().next().value);
  };
  // Хвост вывода без строки приглашения оболочки («dev@mac папка % »).
  const runOutputText = answer => {
    let out = String(answer?.stdout ?? "").replace(/\r\n?/g, "\n");
    out = out.replace(/\n?[^\n]*@[^\n]*[%$#]\s*$/, "");
    const err = String(answer?.stderr ?? "").trim();
    const text = [out.trimEnd(), err].filter(Boolean).join("\n");
    return text.length > RUN_OUT_MAX ? `…${text.slice(-RUN_OUT_MAX)}` : text;
  };
  const runFail = (command, why) => {
    runState.fails += 1;
    runState.going.delete(command);
    runState.last = { command, at: new Date().toISOString(), state: "fail", error: String(why ?? "").slice(0, 200) };
    try { newWindowNote("Не запустилось"); } catch {}
  };
  // Запуск команды в скрытой оболочке этого чата. Ответ — что случилось.
  const runStart = (command, t = now()) => {
    if (chatKind() !== "popout") return "not-popout";
    if (pageWorking()) return "working";
    const going = runState.going.get(command);
    if (going && t < going.until) return "busy";
    const chat = myChatId();
    const sessions = runSessions();
    if (!chat || !sessions) { runFail(command, !chat ? "чат не опознан" : "нет моста"); return "no-bridge"; }
    runState.going.set(command, { until: t + RUN_WAIT_MS });
    runState.runs += 1;
    runState.via = "bash";
    runState.last = { command, at: new Date().toISOString(), state: "running", error: null };
    const last = runState.last;
    let answer;
    try { answer = sessions.runBashCommand(chat, command); } catch (error) { runFail(command, error?.message ?? error); return "fail"; }
    Promise.resolve(answer).then(result => {
      if (!state.alive) return;
      if (result?.error) { runFail(command, result.error); return; }
      runState.going.delete(command);
      runRemember(runState.outputs, command, runOutputText(result));
      if (runState.last === last) last.state = "done";
      runPaint();
    }, error => { if (state.alive) runFail(command, error?.message ?? error); });
    runPaint();
    return "started";
  };
  const runButton = copy => {
    const button = document.createElement("button");
    button.setAttribute(RUN_ATTRIBUTE, "");
    button.setAttribute("type", "button");
    button.className = copy.className;
    for (const [name, value] of Object.entries({ "font-size": "11px", "line-height": "1", "font-family": "-apple-system, system-ui, sans-serif", "user-select": "none", "-webkit-user-select": "none" })) button.style.setProperty(name, value);
    return button;
  };
  const runSet = (node, name, value) => { if (node.getAttribute(name) !== value) node.setAttribute(name, value); };
  const runOutNode = () => {
    const out = document.createElement("pre");
    out.setAttribute(RUN_OUT_ATTRIBUTE, "");
    for (const [name, value] of Object.entries({
      margin: "5px 0 0", padding: "6px 10px", "max-height": "160px", overflow: "auto", "white-space": "pre-wrap",
      "word-break": "break-word", "font-size": "12px", "line-height": "1.4", "border-radius": "8px",
      border: "0.5px solid color-mix(in srgb, currentColor 22%, transparent)", opacity: "0.85",
    })) out.style.setProperty(name, value);
    return out;
  };
  // Кнопки и вывод — ровно у блоков, что сейчас в ленте вынесенного окна.
  const runPaint = (t = now()) => {
    const blocks = chatKind() === "popout" ? runBlocks() : [];
    const working = blocks.length ? pageWorking() : false;
    const keep = new Set();
    for (const { block, copy, command, complex } of blocks) {
      let item = runState.nodes.get(block);
      if (!item?.button?.isConnected || item.button.parentElement !== copy.parentElement) {
        try { item?.button?.remove(); } catch {}
        item = { button: runButton(copy), out: item?.out ?? null };
        try { copy.parentElement.insertBefore(item.button, copy); } catch { continue; }
        runState.nodes.set(block, item);
      }
      item.command = command;
      item.complex = complex;
      keep.add(block);
      const going = runState.going.get(command);
      const busy = Boolean(going) && t < going.until;
      const label = busy ? "…" : "▶";
      const ask = complex ? "Показать команду целиком и запустить" : "Запустить в этом чате";
      if (item.button.textContent !== label) item.button.textContent = label;
      runSet(item.button, "aria-label", busy ? "Команда идёт" : ask);
      runSet(item.button, "title", working ? "агент работает" : busy ? "идёт" : ask);
      runSet(item.button, "aria-disabled", working || busy ? "true" : "false");
      item.button.style.setProperty("opacity", working ? "0.4" : "1");
      const text = runState.outputs.get(command);
      if (text === undefined) {
        if (item.out) { try { item.out.remove(); } catch {} item.out = null; }
      } else {
        if (!item.out) item.out = runOutNode();
        if (item.out.parentElement !== block) { try { block.appendChild(item.out); } catch {} }
        const shown = text || "(нет вывода)";
        if (item.out.textContent !== shown) item.out.textContent = shown;
      }
    }
    for (const [block, item] of [...runState.nodes]) {
      if (keep.has(block)) continue;
      try { item.button?.remove(); } catch {}
      try { item.out?.remove(); } catch {}
      runState.nodes.delete(block);
    }
    runState.buttons = keep.size;
  };
  // Тик сердцебиения: истёкшие «…» снова «▶», кнопки по ленте.
  const runTick = (t = now()) => {
    for (const [command, going] of [...runState.going]) if (t >= going.until) runState.going.delete(command);
    runPaint(t);
  };
  // Окошко сложной команды (WF111, правило «Элемент управления — целиком»):
  // полный текст моноширинно, с прокруткой и переносом (хвост длинной строки не
  // прячется за горизонтальной прокруткой), «Выполнить» и «Отмена». Esc, клик
  // мимо окошка и «Отмена» — закрыть, ничего не запускать. «Выполнить» — только
  // доверенный клик; запустилось — окошко закрывается, ▶ блока показывает «…» и
  // вывод, как у простой; не запустилось — причина красной строкой в окошке,
  // окошко остаётся. Чат сменился, пока окошко открыто, — «Выполнить» гаснет.
  const RUN_CONFIRM_ID = "myclaude-run-confirm";
  const RUN_CONFIRM_ATTRIBUTE = "data-myclaude-run-confirm";
  const RUN_CONFIRM_WHY = {
    working: "Агент в чате работает — запусти после его хода.",
    busy: "Эта команда уже идёт.",
    "no-bridge": "Не запустилось: нет связи с этим чатом.",
    "not-popout": "Не запустилось: окно уже не вынесенное.",
    chat: "Чат сменился — команду не запускаю.",
  };
  const runConfirmClose = () => {
    const confirm = runState.confirm;
    runState.confirm = null;
    try { confirm?.node?.remove(); } catch {}
  };
  const runConfirmOpen = command => {
    runConfirmClose();
    const dark = progressDark();
    const style = (node, rules) => { for (const [name, value] of Object.entries(rules)) node.style.setProperty(name, value); };
    const layer = document.createElement("div");
    layer.id = RUN_CONFIRM_ID;
    layer.setAttribute("role", "dialog");
    layer.setAttribute("aria-modal", "true");
    layer.setAttribute("aria-label", "Запустить команду в этом чате");
    style(layer, {
      position: "fixed", inset: "0", "z-index": "2147483645", display: "flex", "align-items": "center",
      "justify-content": "center", padding: "16px", "box-sizing": "border-box", background: "rgba(0,0,0,.35)",
    });
    const panel = document.createElement("div");
    style(panel, {
      display: "flex", "flex-direction": "column", gap: "8px", width: "min(560px, 100%)", "max-height": "100%",
      "box-sizing": "border-box", padding: "12px", "border-radius": "10px", "border-width": "1px", "border-style": "solid",
      font: "13px/1.4 -apple-system, system-ui, sans-serif",
      ...(dark ? { background: "#12151c", color: "#e7e9f0", "border-color": "#2a2f3a", "box-shadow": "0 8px 24px rgba(0,0,0,.45)" }
        : { background: "#ffffff", color: "#14181f", "border-color": "#d7dbe3", "box-shadow": "0 8px 24px rgba(15,20,30,.18)" }),
    });
    const head = document.createElement("div");
    head.textContent = "Выполнить в этом чате? Команда целиком:";
    style(head, { "font-weight": "600" });
    const code = document.createElement("pre");
    code.textContent = command;
    style(code, {
      margin: "0", padding: "8px 10px", "min-height": "0", "max-height": "50vh", overflow: "auto",
      "white-space": "pre-wrap", "overflow-wrap": "anywhere", "word-break": "break-all", "border-radius": "6px",
      font: "12px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace", background: dark ? "#0b0d12" : "#f4f5f7",
    });
    const note = document.createElement("div");
    note.setAttribute("role", "alert");
    style(note, { display: "none", color: "#e5484d" });
    const controls = document.createElement("div");
    style(controls, { display: "flex", "justify-content": "flex-end", gap: "8px" });
    const button = (action, text, main) => {
      const node = document.createElement("button");
      node.setAttribute("type", "button");
      node.setAttribute(RUN_CONFIRM_ATTRIBUTE, action);
      node.textContent = text;
      style(node, {
        padding: "4px 12px", "border-radius": "6px", "border-width": "1px", "border-style": "solid", font: "inherit", cursor: "pointer",
        ...(main ? { background: "#2563eb", color: "#ffffff", "border-color": "#2563eb" } : { background: "transparent", color: "inherit", "border-color": "currentColor" }),
      });
      return node;
    };
    const cancel = button("cancel", "Отмена", false);
    const go = button("run", "Выполнить", true);
    controls.append(cancel, go);
    panel.append(head, code, note, controls);
    layer.appendChild(panel);
    (document.body ?? document.documentElement).appendChild(layer);
    runState.confirm = { command, chat: myChatId(), node: layer, note, go };
    // Фокус на «Отмене»: случайный Enter ничего не запустит.
    try { cancel.focus(); } catch {}
  };
  const runConfirmGo = () => {
    const confirm = runState.confirm;
    if (!confirm) return;
    const result = myChatId() !== confirm.chat ? "chat" : runStart(confirm.command);
    if (result === "started") { runConfirmClose(); return; }
    confirm.note.textContent = RUN_CONFIRM_WHY[result] ?? "Не запустилось.";
    confirm.note.style.setProperty("display", "block");
    if (result === "chat") {
      confirm.go.disabled = true;
      confirm.go.setAttribute("aria-disabled", "true");
      confirm.go.style.setProperty("opacity", "0.5");
    }
  };
  const onRunConfirmClick = (event, confirm) => {
    const target = event.target;
    // Имя не action: сверка контракта команд в ClaudeAXTests ищет по файлу сравнения с этим именем.
    const pick = target?.closest?.(`[${RUN_CONFIRM_ATTRIBUTE}]`)?.getAttribute(RUN_CONFIRM_ATTRIBUTE) ?? (target === confirm.node ? "cancel" : "");
    // Клик по тексту команды — выделение, как обычно.
    if (!pick) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    if (!state.alive || event.isTrusted !== true) return;
    if (pick === "cancel") { runConfirmClose(); return; }
    if (Number(event.detail) > 1 || confirm.go.disabled) return;
    runConfirmGo();
  };
  const onRunConfirmKey = event => {
    if (event?.key !== "Escape" || !runState.confirm) return false;
    event.preventDefault?.();
    event.stopImmediatePropagation?.();
    runConfirmClose();
    return true;
  };
  // Для гейта: n-я кнопка окна (с нуля) — как нажатие; у сложной — окошко, не запуск.
  const runBlock = n => {
    const blocks = chatKind() === "popout" ? runBlocks() : [];
    const found = blocks[Math.trunc(Number(n))];
    if (!found) return "no-block";
    runState.clicks += 1;
    if (found.complex) { runConfirmOpen(found.command); return "confirm"; }
    return runStart(found.command);
  };
  const onRunPress = event => {
    if (!event?.target?.closest?.(`[${RUN_ATTRIBUTE}]`)) return;
    event.preventDefault?.();
  };
  const onRunClick = event => {
    const confirm = runState.confirm;
    if (confirm?.node?.contains?.(event?.target)) { onRunConfirmClick(event, confirm); return; }
    const button = event?.target?.closest?.(`[${RUN_ATTRIBUTE}]`) ?? null;
    if (!button) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    // Только клик человека (гейт 2): синтетический click команду не запускает.
    if (!state.alive || Number(event.detail) > 1 || event.isTrusted === false) return;
    let found = null;
    for (const item of runState.nodes.values()) if (item.button === button) found = item;
    if (!found?.command || button.getAttribute("aria-disabled") === "true") return;
    runState.clicks += 1;
    if (found.complex) runConfirmOpen(found.command);
    else runStart(found.command);
  };
  // Сироты прошлой установки — до первой разметки.
  try { for (const node of document.querySelectorAll(`[${RUN_ATTRIBUTE}],[${RUN_OUT_ATTRIBUTE}],#${RUN_CONFIRM_ID}`)) node.remove(); } catch {}
  track(() => {
    runConfirmClose();
    for (const item of runState.nodes.values()) {
      try { item.button?.remove(); } catch {}
      try { item.out?.remove(); } catch {}
    }
    runState.nodes.clear();
  });
  // Угол «Проект · чат» (раздел 2ж, #7911): виден ли, что в нём, спрятано ли
  // название чата в шапке под углом (cover); затухания у угла нет (WF103, решение 12).
  // Своя ▶ (раздел 12т, #7941): кнопок в окне, нажатий, запусков, путь (bash —
  // runBashCommand моста), отказов, последний запуск {command, at, state, error}.
  statusPart("run", () => ({
    buttons: runState.buttons, clicks: runState.clicks, runs: runState.runs, via: runState.via,
    fails: runState.fails, last: runState.last ? { ...runState.last } : null, confirm: Boolean(runState.confirm),
  }));
  HATCH && Object.assign(HATCH, { runTick, runStart, runCommandOf });

