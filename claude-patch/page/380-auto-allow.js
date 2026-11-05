  // ---- 12е. Разовое Авто-Allow и Авто-Trust (WF121) ------------------------
  const AUTO_ALLOW_TICK_MS = 700;
  // #11618: и по-русски — дословно из каталога claude.ai.
  const AUTO_ALLOW_LABELS = ["Allow once", "Allow", "Yes, allow", "Разрешить один раз", "Разрешить"];
  const AUTO_ALLOW_REASONS = new Set(["deletion", "publication", "money", "credentials", "external",
    "unreadable", "unknown-tool", "unknown-request", "no-once", "ambiguous", "manual-required", "navigation"]);
  const AUTO_ALLOW_TOOLS = new Set(["Bash", "Read", "Grep", "Glob", "Edit", "Write", "AskUserQuestion", "ExitPlanMode"]);
  const AUTO_ALLOW_BLOCK_WORDS = [
    ["deletion", /^(?:rm|rmdir|unlink|delete|remove|удалить|удаление)$/u],
    ["publication", /^(?:deploy|railway|vercel|publish|notarytool|altool|notarize|нотаризация|release\.sh)$/u],
    ["money", /^(?:kaspi|payment|pay|refund|charge|transfer|оплата|платеж|платёж)$/u],
    ["credentials", /^(?:secret|token|password|credential|credentials|keychain|security|пароль|секрет|ключи)$/u],
    ["external", /^(?:curl|wget|submit|отправить|опубликовать)$/u],
  ];
  const AUTO_ALLOW_BLOCK_PHRASES = [
    ["deletion", /\bgit\b[^\n;&|]*\b(?:rm|clean)\b|\bgit\b[^\n;&|]*\breset\s+[^\n;&|]*--hard\b|\bgit\b[^\n;&|]*\bbranch\s+[^\n;&|]*-[dD]\b|\bdrop\s+(?:table|database)\b/iu],
    ["publication", /\bgit\b[^\n;&|]*\b(?:push|merge)\b|\bgh\s+pr\s+merge\b/u],
    ["credentials", /(?:^|[\s/"'=])\.env(?:[.\/\s"']|$)|(?:^|\/)\.ssh(?:\/|$)|(?:^|\/)\.aws\/credentials\b|pimp-voice\.env\b|\.credentials\.json\b/iu],
    ["money", /возврат\s+денег/iu],
    ["external", /\bsend[_\s-]+message\b/iu],
  ];
  const AUTO_ALLOW_BLOCK_TOOLS = [
    ["deletion", /^(?:delete|remove|unlink|rm)$/],
    ["publication", /^(?:publish|deploy|merge|push|release|notarize)$/],
    ["money", /^(?:kaspi|payment|pay|refund|charge|transfer)$/],
    ["credentials", /^(?:secret|token|password|credential|credentials|keychain)$/],
    ["external", /^(?:send|submit|post|upload)$/],
  ];
  let autoAllowClock = () => Date.now();
  const autoAllowNow = () => autoAllowClock();
  const autoAllowState = { timer: 0, lastPressAt: -Infinity, presses: [], blocked: 0, blockedLog: [],
    pressCount: 0, tickAt: 0, switched: 0, mutationRuns: 0, mutationAt: -Infinity, storageFailed: false };
  // Снимается только ЦЕЛЫЙ известный shortcut-хвост; смысловой хвост остаётся.
  // Те же исторические подписи Trust workspace, без расширения его разрешений.
  const autoAllowLabel = text => String(text ?? "").replace(/\s+/g, " ").trim()
    .replace(/\s*(?:[12]\s*(?:(?:⇧(?:Shift)?|⌘(?:Command)?|⏎(?:Enter)?)\s*)*|(?:(?:⇧(?:Shift)?|⌘(?:Command)?|⏎(?:Enter)?)\s*)+)$/u, "").trim();
  const autoAllowSafeButton = text => {
    const label = autoAllowLabel(text);
    return [...AUTO_ALLOW_LABELS, "Always allow", "Allow always", "Cancel", "Deny", "Всегда разрешать", "Отмена", "Отменить", "Отклонить"].find(item => item.toLowerCase() === label.toLowerCase()) ?? "unrecognized";
  };
  const autoAllowOnce = button => {
    const raw = String(button.textContent ?? "");
    const aria = button.getAttribute("aria-label");
    const label = AUTO_ALLOW_LABELS.find(item => item.toLowerCase() === autoAllowLabel(raw).toLowerCase());
    if (!label || (aria && autoAllowLabel(aria).toLowerCase() !== label.toLowerCase())) return "";
    return label;
  };
  const autoAllowVisible = node => {
    if (!node?.isConnected) return false;
    const box = node.getBoundingClientRect();
    if (!(box.width > 0 && box.height > 0)) return false;
    for (let el = node; el && el !== document; el = el.parentElement) {
      if (el.hidden || el.hasAttribute?.("hidden") || el.hasAttribute?.("inert") || el.getAttribute?.("aria-hidden") === "true") return false;
      const style = getComputedStyle(el);
      if (style.display === "none" || /^(hidden|collapse)$/.test(style.visibility) || style.opacity === "0") return false;
    }
    return true;
  };
  // Диалог Trust: прежний подъём НЕ используется для карточки Allow.
  const autoAllowDialog = button => {
    let node = button;
    for (let depth = 0; depth < 8; depth += 1) {
      const parent = node.parentElement;
      if (!parent || parent === document.body || parent.querySelector?.(".ProseMirror, textarea")) break;
      node = parent;
    }
    return node;
  };
  // Запрос читаем из самой опознанной карточки, как в 1314f48.
  // WF121 Б1: разовое разрешение не требует отсутствующих в карточке метаданных.
  // Не берём input из соседнего permissionsBySessionId и не выдумываем DOM-поля.
  const autoAllowRequest = button => {
    const request = { card: null, button, chat: null, label: "", tool: "unknown", input: "", text: "",
      readable: false, reason: "unreadable" };
    try {
      const card = button?.closest?.(".epitaxy-approval-card");
      request.card = card;
      request.chat = myChatId();
      request.label = button ? autoAllowOnce(button) : "";
      if (!card?.isConnected || !autoAllowVisible(card) || !autoAllowVisible(button)
        || button.disabled || button.getAttribute("aria-disabled") === "true"
        || !/^local_[A-Za-z0-9_-]+$/.test(request.chat || "")) return request;
      // Клон не трогает React. Удаляем подписи действий/shortcuts и composer.
      const clone = card.cloneNode(true);
      for (const node of clone.querySelectorAll("button, kbd, .ProseMirror, textarea")) node.remove();
      request.text = String(clone.textContent ?? "");
      if (request.text.length > 65536) { request.text = ""; return request; }
      // textContent содержит весь запрос даже при CSS-обрезке или прокрутке.
      const parsed = request.text.trim().match(/^(?:Allow Claude|Claude wants) to run ([A-Za-z][A-Za-z0-9_]*):\s*([\s\S]+)$/);
      request.tool = parsed?.[1] ?? "unknown";
      request.input = parsed?.[2] ?? request.text; // Исходные переносы не схлопываем.
      request.readable = Boolean(request.input.trim());
      request.reason = "";
    } catch { request.reason = "unreadable"; }
    return request;
  };
  // Один классификатор для клика и диагностики: запреты по всему тексту,
  // вопросы человеку остаются ручными, остальные запросы — разовый Allow.
  const autoAllowBlockReason = request => {
    const text = String(request?.text ?? request?.input ?? "");
    const tool = String(request?.tool ?? "unknown");
    const words = text.toLowerCase().split(/[\s;|&`()\[\]{}"'=,<>]+/u)
      .map(word => word.replace(/^-+/, "").split("/").pop());
    for (const [reason, pattern] of AUTO_ALLOW_BLOCK_WORDS) if (words.some(word => pattern.test(word))) return reason;
    for (const [reason, pattern] of AUTO_ALLOW_BLOCK_PHRASES) if (pattern.test(text)) return reason;
    // canonical MCP-имя и вложенные имена; payment.txt не денежная операция.
    // Разбор линейный (ревизия WF247): прежний /[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)+/g на длинном
    // куске без «_» шёл квадратично — 64 КБ замораживали страницу на секунды каждый тик. Цепочка берётся
    // от начала слова, имя в ней — с первой буквы, как у прежнего: ведущие цифры и чисто цифровые части
    // срезаются (2kaspi_payment → kaspi_payment, 12_pay_x → pay_x), без второй части имени нет.
    const names = [tool];
    for (const chain of text.match(/(?<![A-Za-z0-9])[A-Za-z0-9]+(?:_[A-Za-z0-9]+)+/g) ?? []) {
      const name = chain.replace(/^[0-9_]+/, "");
      if (name.includes("_")) names.push(name);
    }
    for (const name of names) {
      const parts = name.toLowerCase().split(/[_-]+/);
      for (const [reason, pattern] of AUTO_ALLOW_BLOCK_TOOLS) if (parts.some(part => pattern.test(part))) return reason;
    }
    if (request?.reason) return AUTO_ALLOW_REASONS.has(request.reason) ? request.reason : "unreadable";
    if (!request?.readable || !request.input) return "unreadable";
    if (tool === "AskUserQuestion" || tool === "ExitPlanMode") return "manual-required";
    return "";
  };
  const autoAllowSummary = (reason, tool) => `${AUTO_ALLOW_REASONS.has(reason) ? reason : "manual-required"}:${AUTO_ALLOW_TOOLS.has(tool) ? tool : "unknown"}`;
  // Только отпечаток для дедупликации; сырой input в status/storage не попадает.
  const autoAllowFingerprint = request => {
    let hash = 2166136261;
    const raw = JSON.stringify([request.chat, request.text, request.tool, request.input,
      request.reason, request.readable, request.label,
      [...request.card?.querySelectorAll("button") ?? []].map(node => [node.textContent, node.getAttribute("aria-label")])]);
    for (let i = 0; i < raw.length; i += 1) hash = Math.imul(hash ^ raw.charCodeAt(i), 16777619);
    return `${raw.length}:${hash >>> 0}`;
  };
  const AUTO_ALLOW_TOAST_ID = "myclaude-auto-allow-toast";
  let autoAllowToastTimer = 0;
  const autoAllowToast = (text, ms) => {
    document.getElementById(AUTO_ALLOW_TOAST_ID)?.remove();
    const toast = document.createElement("div");
    toast.id = AUTO_ALLOW_TOAST_ID;
    toast.textContent = text;
    for (const [name, value] of Object.entries({
      position: "fixed", left: "50%", bottom: "72px", transform: "translateX(-50%)", "max-width": "80%",
      padding: "6px 12px", "border-radius": "8px", background: "rgba(0,0,0,.82)", color: "#fff",
      font: "12px/1.35 system-ui", "pointer-events": "none", "z-index": "2147483647",
    })) toast.style.setProperty(name, value);
    (document.body ?? document.documentElement).appendChild(toast);
    clearTimeout(autoAllowToastTimer);
    autoAllowToastTimer = setTimeout(() => toast.remove(), ms);
  };
  track(() => { clearTimeout(autoAllowToastTimer); document.getElementById(AUTO_ALLOW_TOAST_ID)?.remove(); });
  const AUTO_ALLOW_JOURNAL_KEY = "myclaude-auto-allow-journal-v2";
  const AUTO_ALLOW_JOURNAL_MAX = 30;
  const autoAllowJournal = () => {
    try {
      const list = JSON.parse(localStorage.getItem(AUTO_ALLOW_JOURNAL_KEY) ?? "[]");
      if (!Array.isArray(list)) return [];
      return list.slice(0, AUTO_ALLOW_JOURNAL_MAX).filter(item => item && AUTO_ALLOW_REASONS.has(item.reason)).map(item => ({
        at: /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(item.at) ? item.at : null,
        version: item.version === VERSION ? VERSION : "unknown", reason: item.reason,
        buttons: (Array.isArray(item.buttons) ? item.buttons : []).slice(0, 10).map(autoAllowSafeButton),
        dialog: autoAllowSummary(item.reason, String(item.dialog ?? "").split(":")[1]),
      }));
    } catch { return []; }
  };
  const autoAllowNote = (reason, tool, buttons) => {
    try {
      const list = autoAllowJournal();
      list.unshift({ at: new Date(autoAllowNow()).toISOString(), version: VERSION,
        reason: AUTO_ALLOW_REASONS.has(reason) ? reason : "navigation",
        buttons: buttons.slice(0, 10).map(autoAllowSafeButton), dialog: autoAllowSummary(reason, tool) });
      localStorage.setItem(AUTO_ALLOW_JOURNAL_KEY, JSON.stringify(list.slice(0, AUTO_ALLOW_JOURNAL_MAX)));
    } catch {}
  };
  // Отдельный К3: старые страницы не должны включаться новой командой/ключом.
  const AUTO_ALLOW_ON_KEY = "myclaude.autoAllowOnce";
  const autoAllowEnabled = () => {
    if (autoAllowState.storageFailed) return false;
    try { return localStorage.getItem(AUTO_ALLOW_ON_KEY) === "true"; } catch { return false; }
  };
  // #9998 (слово Элвиса 16.10 20:38: «bypass permission стоит, и всё равно он allow запрашивает… Сделай,
  // чтобы автоматом пимп сам нажимал эту штуку»): в чате, который стоит в режиме Bypass permissions,
  // разовое «Allow once» жмётся само и при выключенном тумблере — человек сам выбрал «не спрашивать».
  // Тот же тик, тот же список «не жму сам», журнал и плашка; «Always allow» не жмётся никогда. Режим
  // чата — подпись кнопки режима под полем (раздел 12с¹: nazhModeButton, код «By»); пока поля не видно
  // (карточка встала на его место), действует последний замер ЭТОГО чата. Обход чатов (ниже) — только
  // по тумблеру: режим чужого чата страница не знает, пока его не откроет.
  const autoAllowBypass = { chat: null, on: false };
  const autoAllowBypassHere = () => {
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    if (!/^local_[A-Za-z0-9_-]+$/.test(chat || "")) return false;
    let button = null;
    try { button = nazhModeButton(); } catch { button = null; }
    if (button) {
      autoAllowBypass.chat = chat;
      autoAllowBypass.on = chinModeShort(chinText(button)) === "By";
    }
    return autoAllowBypass.chat === chat && autoAllowBypass.on;
  };
  const autoAllowActive = () => autoAllowEnabled() || autoAllowBypassHere();
  const autoAllowSet = value => {
    const on = value === true || value === "true";
    try {
      localStorage.setItem(AUTO_ALLOW_ON_KEY, on ? "true" : "false");
      autoAllowState.storageFailed = false;
    } catch { autoAllowState.storageFailed = true; }
    autoAllowState.switched += 1;
    if (!autoAllowEnabled() && roamState.phase !== "idle") roamAbort("Авто-Allow выключен");
  };
  const AUTO_ALLOW_MESSAGES = {
    deletion: "удаление", publication: "выкладка", money: "деньги или доступы", credentials: "деньги или доступы",
    unreadable: "не прочитал запрос", "unknown-tool": "не прочитал запрос", "unknown-request": "не прочитал запрос",
    "no-once": "нет разового Allow", ambiguous: "нужно ручное подтверждение", "manual-required": "нужно ручное подтверждение",
    external: "нужно ручное подтверждение", navigation: "нужно ручное подтверждение",
  };
  const autoAllowRefuse = (request, reason, fingerprint, t) => {
    const card = request.card;
    if (card.__myclaudeAllowRefused !== `${fingerprint}:${reason}`) {
      card.__myclaudeAllowRefused = `${fingerprint}:${reason}`;
      const dialog = autoAllowSummary(reason, request.tool);
      autoAllowState.blocked += 1;
      autoAllowState.blockedLog.unshift({ at: new Date(t).toISOString(), reason, dialog });
      autoAllowState.blockedLog.length = Math.min(autoAllowState.blockedLog.length, 10);
      autoAllowNote(reason, request.tool, [...card.querySelectorAll("button")].map(node => node.textContent));
      autoAllowToast(`Жду тебя: ${AUTO_ALLOW_MESSAGES[reason]}`, 6000);
    }
    if (roamState.phase !== "idle" && roamState.phase !== "back" && request.chat === roamState.chat) {
      roamState.blockedRequests.set(request.chat, { fingerprint, permissions: roamPermissionStamp(request.chat) });
      roamSkip({ id: request.chat, title: roamState.title }, reason, t);
      roamBack(reason, t);
    }
  };
  const autoAllowTick = () => {
    const t = autoAllowNow();
    autoAllowState.tickAt = t;
    if (!state.alive || !autoAllowActive() || roamState.phase === "back") return;
    for (const card of document.querySelectorAll(".epitaxy-approval-card")) {
      if (!autoAllowVisible(card)) continue;
      const buttons = [...card.querySelectorAll("button")].filter(button => button.closest(".epitaxy-approval-card") === card);
      const active = buttons.filter(button => !button.disabled && button.getAttribute("aria-disabled") !== "true" && autoAllowVisible(button));
      const candidates = active.filter(autoAllowOnce);
      const button = candidates[0] ?? active[0];
      if (!button) continue;
      const request = autoAllowRequest(button);
      const fingerprint = autoAllowFingerprint(request);
      let reason = autoAllowBlockReason(request);
      if (!["deletion", "publication", "money", "credentials", "external"].includes(reason)) {
        if (!candidates.length) reason = "no-once";
        else if (candidates.length > 1) reason = "ambiguous";
      }
      if (reason) { autoAllowRefuse(request, reason, fingerprint, t); continue; }
      if (card.__myclaudeAllowPressed === fingerprint || t - autoAllowState.lastPressAt < AUTO_ALLOW_TICK_MS) continue;
      const again = autoAllowRequest(button);
      // Повторное чтение непосредственно перед кликом; stale DOM/чат/off/dispose — отказ.
      if (!state.alive || !autoAllowActive() || myChatId() !== request.chat || again.card !== card
        || autoAllowBlockReason(again) || autoAllowFingerprint(again) !== fingerprint || !autoAllowOnce(button)
        || button.disabled || button.getAttribute("aria-disabled") === "true" || !autoAllowVisible(button)) continue;
      card.__myclaudeAllowPressed = fingerprint;
      autoAllowState.lastPressAt = t;
      autoAllowState.pressCount += 1;
      autoAllowState.presses.unshift({ at: new Date(t).toISOString(), button: request.label,
        dialog: `${AUTO_ALLOW_TOOLS.has(request.tool) ? request.tool : "unknown"}:once` });
      autoAllowState.presses.length = Math.min(autoAllowState.presses.length, 20);
      button.click();
      return;
    }
  };

  // Авто-«Trust workspace» (#7498, слово Элвиса 25.09 ~23:55: «что этот Trust
  // workspace автоматически не нажимается? Сделай, как авто-Allow… Я разрешаю»).
  // Диалог Claude «Trust this workspace?» с путём папки и кнопками «Trust
  // workspace» / «Cancel» встаёт при новом чате в папке, которой Claude ещё не
  // доверял — на отправке первого сообщения (тексты Claude 26.09: «If you trust
  // this workspace, send a message and choose Trust workspace when asked»).
  // Жмём ТОЛЬКО когда путь папки в диалоге лежит внутри папки проектов Элвиса.
  // С WF102 (#7905, слово Элвиса: «чтобы Trust workspace автоматически
  // нажималась») — и при выключенном тумблере Авто-Allow: autoAllowCycle зовёт
  // этот тик всегда, отдельной строкой. Путь не найден, чужой, с «..» — не
  // трогаем: доверие папке значит, что агент читает и запускает всё в ней.
  // С WF108 корень не зашит: его присылает приложение командой trust-root
  // (projectsRoot из claude.json, только если ключ задан явно; раздел 15), а
  // страница держит его в localStorage[AUTO_TRUST_ROOT_KEY] — общем для всех
  // окон. Корня нет — автодоверие ВЫКЛ (любой путь — "outside"): у чужого
  // человека Пимп папкам сам не доверяет. «~/» раскрывается домом из корня
  // (/Users/<имя>/); корень не под /Users/ — пути с «~» не наши.
  const AUTO_TRUST_ROOT_KEY = "myclaude-trust-root-v1";
  // Корень годен: абсолютный, без «.»/«..», без переводов строк, не «/»; «/» на конце.
  const autoTrustCleanRoot = raw => {
    if (typeof raw !== "string") return null;
    let root = raw.trim();
    if (!root.startsWith("/") || root.length > 1024 || /[\r\n\0]/.test(root)) return null;
    if (/(^|\/)\.\.?(\/|$)/.test(root)) return null;
    if (!root.endsWith("/")) root += "/";
    return /[^\/]/.test(root) ? root : null;
  };
  const autoTrustRoot = () => {
    try { return autoTrustCleanRoot(localStorage.getItem(AUTO_TRUST_ROOT_KEY)); } catch { return null; }
  };
  // Команда trust-root (К WF108): root — строка или null (ключа нет — корень снят).
  const runTrustRootCommand = detail => {
    const root = autoTrustCleanRoot(detail?.root);
    try {
      if (root) localStorage.setItem(AUTO_TRUST_ROOT_KEY, root);
      else localStorage.removeItem(AUTO_TRUST_ROOT_KEY);
    } catch {}
  };
  const AUTO_TRUST_BUTTON = /^(?:trust (?:this )?workspace|доверять рабочей области)$/i;
  const autoTrustState = { presses: 0, refused: 0, last: null, lastRefused: "", lastAt: 0 };
  // Путь папки — ЦЕЛЫЙ текст первого элемента диалога, что начинается с «/» или
  // «~/» (живьём 26.09, Claude 2.9939.2: div.text-code под описанием; ниже
  // список «Execution allowed by:» с относительными .claude/settings…). Путь
  // по словам из текста не выковыриваем (verify #7498: пробел, кавычка,
  // «Folder:/tmp», срез на 2000 знаков ломали разбор). Обход — в порядке
  // документа, поэтому первым попадается самый внешний такой элемент.
  const autoTrustPath = dialog => {
    let nodes = [];
    try { nodes = [...dialog.querySelectorAll("*")]; } catch { nodes = []; }
    for (const node of nodes) {
      const text = String(node.innerText ?? node.textContent ?? "").trim();
      if (/^(?:~\/|\/)/.test(text) && !/[\r\n]/.test(text)) return text;
    }
    return null;
  };
  // "" — жать можно; иначе причина отказа. Симлинк внутри папки проектов,
  // ведущий наружу, страница не видит (realpath ей недоступен) — известная
  // граница, записана в DECISIONS.
  const autoTrustVerdict = raw => {
    let path = String(raw ?? "").trim();
    if (!path) return "no-path";
    const root = autoTrustRoot();
    if (!root) return "outside";
    if (path.startsWith("~/")) {
      const home = root.match(/^\/Users\/[^\/]+\//)?.[0];
      if (!home) return "outside";
      path = home + path.slice(2);
    }
    if (/(^|\/)\.\.?(\/|$)/.test(path)) return "dots";
    if (!path.startsWith(root) || !/[^\/]/.test(path.slice(root.length))) return "outside";
    return "";
  };
  const autoTrustTick = now => {
    if (now - autoTrustState.lastAt < AUTO_ALLOW_TICK_MS) return;
    for (const button of document.querySelectorAll("button")) {
      if (button.disabled || button.getAttribute("aria-disabled") === "true") continue;
      const label = autoAllowLabel(button.textContent);
      if (!AUTO_TRUST_BUTTON.test(label)) continue;
      const box = button.getBoundingClientRect();
      if (box.width <= 0 || box.height <= 0) continue;
      let dialog = null;
      try { dialog = button.closest('[role="dialog"], [role="alertdialog"]'); } catch {}
      const host = dialog ?? autoAllowDialog(button);
      const text = String(host.innerText ?? "").replace(/\s+/g, " ").trim().slice(0, 2000);
      const path = autoTrustPath(host);
      const reason = /trust/i.test(text) ? autoTrustVerdict(path) : "no-dialog";
      if (reason) {
        if (text !== autoTrustState.lastRefused) {
          autoTrustState.lastRefused = text;
          autoTrustState.refused += 1;
          autoTrustState.last = { at: new Date(now).toISOString(), path, verdict: reason };
        }
        continue;
      }
      autoTrustState.lastAt = now;
      autoTrustState.presses += 1;
      autoTrustState.last = { at: new Date(now).toISOString(), path, verdict: "pressed" };
      button.click();
      return;
    }
  };

