  // ---- 12ф². Длинное сообщение Элвиса — свёрнуто в суть (#9806, WF262) ------
  // Слово Элвиса 11.10 ~20:47: «мой текст… меняешь на вот эти короткие… основную суть… И когда я
  // раскрываю его, тогда уже виден весь мой текст… заодно я буду… понимать, что ты меня правильно
  // понял». Сообщение человека в ленте ([data-testid="user-message"], не ответ Claude) длиннее
  // USER_FOLD_CHARS знаков или USER_FOLD_LINES строк сворачивается в суть: свой узел сразу под ним,
  // вид — как у свёрнутого ответа (раздел 12ф: черта слева по --myclaude-fold-mid, серая подложка),
  // под сутью — тихое «начало сообщения» (или «кратко от Пимпа», когда её написала нейронка; до WF297 — «начало» и
  // «суть», #11174: одно слово не объясняло себя) и «Развернуть ▾». Нажал на
  // блок, Enter или пробел на кнопке — весь исходный текст и «Свернуть ▴» под ним; Esc на кнопке —
  // свернуть. Узлы Claude не трогаются: исходник прячет метка + правило ниже, родной обрез Claude
  // (max-height 200 px, маска и «Show more») у свёрнутых нами снят — раскрытый текст виден целиком.
  // Суть — текстом в своём узле: выделяется и копируется; подписи кнопки — из атрибутов (копия их
  // не видит). Сворачивается в колбэке своего наблюдателя мутаций — до отрисовки, развёрнутого кадра
  // нет (как 3а¹). Раскрытое помнится по хэшу, пока окно открыто (лента виртуальная).
  // Суть даёт Пимп: POST 127.0.0.1:47615/summary {hash: sha1 текста, text} → 200 {hash, summary,
  // kind: lead|ai, at} или 202 {hash, pending} — тогда переспрос через USER_FOLD_RETRY_MS, не больше
  // USER_FOLD_RETRIES раз. Тело — строкой без Content-Type (text/plain — простой CORS-запрос, без
  // OPTIONS). Пимпа нет, ошибка, не дождались — первые предложения считает сама страница
  // (userFoldLead, то же правило, что «lead» у Пимпа). Суть нейронки (ai) — в localStorage по хэшу.
  // Последний ответ Рика в стартовом сообщении нового чата (#10904, `pimp.py renew`): сообщение, которое начинается
  // с «Последний ответ … тебе (из прежнего чата…», делится по первой строке «———». Верх — ответ дословно — своим
  // узлом (USER_FOLD_ATTRIBUTE = "head") над свёрткой: целиком, без свёртки, без родного обреза 200 px и основным
  // цветом (тихий цвет 12ф⁴ его не касается). Низ — служебный текст для нового Рика — сворачивается по прежним
  // правилам; короткий — виден как есть (свёртка "plain": без кнопки и подложки). Раскрыл — исходник целиком.
  const USER_FOLD_SELECTOR = '[data-testid="user-message"]';
  const USER_FOLD_ATTRIBUTE = "data-myclaude-ufold";
  const USER_FOLD_SOURCE_ATTRIBUTE = "data-myclaude-ufold-src";
  const USER_FOLD_CLAMP_ATTRIBUTE = "data-myclaude-ufold-clamp";
  const USER_FOLD_TEXT_ATTRIBUTE = "data-myclaude-ufold-text";
  const USER_FOLD_BAR_ATTRIBUTE = "data-myclaude-ufold-bar";
  const USER_FOLD_KIND_ATTRIBUTE = "data-myclaude-ufold-kind";
  const USER_FOLD_LABEL_ATTRIBUTE = "data-myclaude-ufold-label";
  const USER_FOLD_CHARS = 700;
  const USER_FOLD_LINES = 8;
  const USER_FOLD_LEAD_MAX = 180;
  const USER_FOLD_TEXT_MAX = 20000;
  const USER_FOLD_RETRY_MS = 3000;
  const USER_FOLD_RETRIES = 5;
  // Пимп молчал — тот же текст переспрашиваем не раньше чем через 10 минут (он мог встать позже).
  const USER_FOLD_AGAIN_MS = 600000;
  const USER_FOLD_KEY = "myclaude-ufold-v1";
  const USER_FOLD_KEEP = 200;
  const USER_FOLD_LAST = /^Последний ответ .{1,20} тебе \(из прежнего чата/u;
  const USER_FOLD_CUT = "———";
  // headPaint — вёрстка верха ответом (раздел 13в¹, 678, #11399); нет его или упал — верх простым текстом.
  const userFold = { seen: new WeakMap(), entries: new Map(), open: new Map(), asked: new Map(), store: null, observer: null, headPaint: null };

  // Текст сообщения строками: <br> и блоки — перенос; узел без детей (стенд тестов) — сам себе текст.
  // keep — с пустыми строками между абзацами (не больше одной подряд): так показывается верх #10904.
  const userFoldText = (message, keep = false) => {
    const lines = [""];
    const put = text => {
      const parts = String(text ?? "").split("\n");
      lines[lines.length - 1] += parts[0];
      for (const part of parts.slice(1)) lines.push(part);
    };
    // keep: между абзацами — пустая строка (строки списка и таблицы — без неё).
    const breakLine = gap => { if (lines[lines.length - 1].trim()) { lines.push(""); if (gap) lines.push(""); } };
    const walk = item => {
      const kids = [...(item.childNodes ?? [])];
      if (!kids.length) { put(item.textContent); return; }
      for (const kid of kids) {
        if (kid.nodeType === 3) put(kid.nodeValue);
        else if (kid.nodeType !== 1 || kid.hasAttribute?.(USER_FOLD_ATTRIBUTE)) continue;
        else if (kid.tagName === "BR") lines.push("");
        else {
          const block = /^(P|DIV|LI|UL|OL|H[1-6]|PRE|BLOCKQUOTE|TABLE|TR)$/.test(kid.tagName);
          const gap = keep && block && kid.tagName !== "LI" && kid.tagName !== "TR";
          if (block) breakLine(gap);
          walk(kid);
          if (block) breakLine(gap);
        }
      }
    };
    walk(message);
    const trimmed = lines.map(line => line.replace(/\s+$/u, ""));
    if (keep) return trimmed.join("\n").replace(/\n{3,}/g, "\n\n").replace(/^\n+|\n+$/g, "");
    return trimmed.filter(line => line.trim()).join("\n");
  };
  // #10904: верх (дословно, с абзацами) и низ по первой строке «———»; не тот вид сообщения — null.
  const userFoldSplit = (message, full) => {
    if (!USER_FOLD_LAST.test(full)) return null;
    const cutAt = lines => lines.findIndex(line => line.trim() === USER_FOLD_CUT);
    const flat = full.split("\n");
    const kept = userFoldText(message, true).split("\n");
    const flatAt = cutAt(flat);
    const keptAt = cutAt(kept);
    if (flatAt < 1 || keptAt < 1) return null;
    return { head: kept.slice(0, keptAt).join("\n").trim(), rest: flat.slice(flatAt + 1).join("\n"), restKept: kept.slice(keptAt + 1).join("\n").trim() };
  };
  const userFoldLong = text => text.length > USER_FOLD_CHARS || text.split("\n").length > USER_FOLD_LINES;
  // Начало: первое предложение и второе, если вместе влезают в USER_FOLD_LEAD_MAX знаков; первое
  // длиннее — режем по слову и ставим «…».
  const userFoldLead = text => {
    const flat = sayNorm(text);
    const sentences = flat.split(/(?<=[.!?…][»"”)\]]*)\s+/u).filter(Boolean);
    let lead = sentences[0] ?? "";
    if (sentences.length > 1 && lead.length + 1 + sentences[1].length <= USER_FOLD_LEAD_MAX) lead = `${lead} ${sentences[1]}`;
    if (lead.length <= USER_FOLD_LEAD_MAX) return lead;
    const cut = lead.slice(0, USER_FOLD_LEAD_MAX - 1);
    const space = cut.lastIndexOf(" ");
    return `${(space > USER_FOLD_LEAD_MAX / 2 ? cut.slice(0, space) : cut).replace(/[\s,;:—–-]+$/u, "")}…`;
  };
  // SHA-1 (hex) по UTF-8 — синхронно: хэш нужен в колбэке наблюдателя, до отрисовки, а
  // crypto.subtle только асинхронный.
  const userFoldSha1 = text => {
    const bytes = [];
    for (const char of String(text)) {
      const code = char.codePointAt(0);
      if (code < 0x80) bytes.push(code);
      else if (code < 0x800) bytes.push(0xc0 | code >> 6, 0x80 | code & 63);
      else if (code < 0x10000) bytes.push(0xe0 | code >> 12, 0x80 | code >> 6 & 63, 0x80 | code & 63);
      else bytes.push(0xf0 | code >> 18, 0x80 | code >> 12 & 63, 0x80 | code >> 6 & 63, 0x80 | code & 63);
    }
    const bits = bytes.length * 8;
    bytes.push(0x80);
    while (bytes.length % 64 !== 56) bytes.push(0);
    const high = Math.floor(bits / 0x100000000);
    for (const word of [high, bits >>> 0]) bytes.push(word >>> 24 & 255, word >>> 16 & 255, word >>> 8 & 255, word & 255);
    const hash = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0];
    const w = new Array(80);
    for (let at = 0; at < bytes.length; at += 64) {
      for (let t = 0; t < 16; t += 1) w[t] = bytes[at + 4 * t] << 24 | bytes[at + 4 * t + 1] << 16 | bytes[at + 4 * t + 2] << 8 | bytes[at + 4 * t + 3];
      for (let t = 16; t < 80; t += 1) { const x = w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16]; w[t] = x << 1 | x >>> 31; }
      let [a, b, c, d, e] = hash;
      for (let t = 0; t < 80; t += 1) {
        const f = t < 20 ? (b & c) | (~b & d) : t < 40 ? b ^ c ^ d : t < 60 ? (b & c) | (b & d) | (c & d) : b ^ c ^ d;
        const k = t < 20 ? 0x5a827999 : t < 40 ? 0x6ed9eba1 : t < 60 ? 0x8f1bbcdc : 0xca62c1d6;
        const next = ((a << 5 | a >>> 27) + f + e + k + w[t]) | 0;
        e = d; d = c; c = b << 30 | b >>> 2; b = a; a = next;
      }
      hash[0] = hash[0] + a | 0; hash[1] = hash[1] + b | 0; hash[2] = hash[2] + c | 0; hash[3] = hash[3] + d | 0; hash[4] = hash[4] + e | 0;
    }
    return hash.map(value => (value >>> 0).toString(16).padStart(8, "0")).join("");
  };

  // Кэш сутей нейронки: {v:1, items:{hash:{s, at}}}; потолок — USER_FOLD_KEEP, старые уходят.
  const userFoldStore = () => {
    if (userFold.store) return userFold.store;
    userFold.store = new Map();
    try {
      const record = JSON.parse(localStorage.getItem(USER_FOLD_KEY) ?? "null");
      for (const [hash, item] of Object.entries(record?.items ?? {})) {
        if (/^[0-9a-f]{40}$/.test(hash) && typeof item?.s === "string" && item.s) userFold.store.set(hash, { s: item.s, at: Number(item.at) || 0 });
      }
    } catch {}
    return userFold.store;
  };
  const userFoldRemember = (hash, summary, at) => {
    const store = userFoldStore();
    store.delete(hash);
    store.set(hash, { s: summary, at });
    const list = [...store].sort((x, y) => x[1].at - y[1].at).slice(-USER_FOLD_KEEP);
    userFold.store = new Map(list);
    try { localStorage.setItem(USER_FOLD_KEY, JSON.stringify({ v: 1, items: Object.fromEntries(list) })); } catch {}
  };

  // Суть на виду: нейронки (кэш или ответ) — «кратко от Пимпа», иначе — «начало сообщения» (#11174).
  // Короткий низ #10904 (bare) — свёртки нет: верх и низ видны своими узлами, исходник спрятан.
  const userFoldPaint = entry => {
    const own = entry.node;
    const open = !entry.bare && userFold.open.get(entry.hash) === true;
    const text = own.firstChild;
    const bar = own.lastChild;
    if (text.textContent !== entry.summary) text.textContent = entry.summary;
    foldSet(own, USER_FOLD_ATTRIBUTE, entry.bare ? "plain" : open ? "open" : "closed");
    foldSet(entry.message, USER_FOLD_SOURCE_ATTRIBUTE, open ? "open" : "closed");
    if (entry.head) foldSet(entry.head, USER_FOLD_ATTRIBUTE, open ? "head-open" : "head");
    foldSet(bar, USER_FOLD_KIND_ATTRIBUTE, open || entry.bare ? null : entry.kind === "ai" ? "кратко от Пимпа" : "начало сообщения");
    foldSet(bar, USER_FOLD_LABEL_ATTRIBUTE, entry.bare ? null : open ? "Свернуть ▴" : "Развернуть ▾");
    foldSet(bar, "aria-expanded", open ? "true" : "false");
    foldSet(bar, "aria-label", open ? "Свернуть сообщение" : "Развернуть сообщение");
  };
  const userFoldMake = () => {
    const own = document.createElement("div");
    own.setAttribute(USER_FOLD_ATTRIBUTE, "closed");
    const text = document.createElement("div");
    text.setAttribute(USER_FOLD_TEXT_ATTRIBUTE, "");
    const bar = document.createElement("div");
    bar.setAttribute(USER_FOLD_BAR_ATTRIBUTE, "");
    bar.setAttribute("role", "button");
    bar.setAttribute("tabindex", "0");
    own.appendChild(text);
    own.appendChild(bar);
    return own;
  };
  const userFoldHeadMake = head => {
    const own = document.createElement("div");
    own.setAttribute(USER_FOLD_ATTRIBUTE, "head");
    own.textContent = head;
    try { userFold.headPaint?.(own, head); } catch {}
    return own;
  };
  // Родной обрез Claude над сообщением: кнопка «Show more» (aria-controls) и коробка, которой она
  // управляет. Метки ставятся каждый проход: React добавляет кнопку заново, когда текст снова высокий.
  const userFoldClamp = message => {
    const bubble = message.closest?.('[data-cds="UserMessage"]');
    if (!bubble) return;
    for (const button of bubble.querySelectorAll("button[aria-controls]")) {
      const box = document.getElementById(button.getAttribute("aria-controls"));
      if (!box?.contains?.(message)) continue;
      foldSet(box, USER_FOLD_CLAMP_ATTRIBUTE, "box");
      foldSet(button, USER_FOLD_CLAMP_ATTRIBUTE, "button");
    }
  };

  // Ответ Пимпа: 200 — суть (ai — в кэш), 202 — переспрос; остальное — остаётся начало.
  const userFoldAsk = (hash, text, round = 0) => {
    if (typeof fetch !== "function") return false;
    const asked = { at: Date.now(), pending: true, round, timer: 0 };
    userFold.asked.set(hash, asked);
    const stop = () => { asked.pending = false; };
    let sent = null;
    try {
      sent = fetch(`http://127.0.0.1:${HTML_CHROME_PORT}/summary`, {
        method: "POST", mode: "cors", credentials: "omit", cache: "no-store", body: JSON.stringify({ hash, text }),
      });
    } catch { sent = null; }
    if (!sent || typeof sent.then !== "function") { stop(); return false; }
    sent.then(reply => {
      if (!state.alive || userFold.asked.get(hash) !== asked) return null;
      if (reply?.status === 202 && round < USER_FOLD_RETRIES) {
        asked.timer = setTimeout(() => {
          if (state.alive && userFold.asked.get(hash) === asked) userFoldAsk(hash, text, round + 1);
        }, USER_FOLD_RETRY_MS);
        return null;
      }
      stop();
      return reply?.status === 200 ? reply.json() : null;
    }).then(data => {
      if (!data || !state.alive || userFold.asked.get(hash) !== asked) return;
      const summary = typeof data.summary === "string" ? data.summary.trim() : "";
      if (data.hash !== hash || !summary || (data.kind !== "lead" && data.kind !== "ai")) return;
      if (data.kind === "ai") userFoldRemember(hash, summary, Date.now());
      asked.summary = summary;
      asked.kind = data.kind;
      for (const entry of userFold.entries.values()) {
        if (entry.hash !== hash) continue;
        entry.summary = summary;
        entry.kind = data.kind;
        userFoldPaint(entry);
      }
    }, stop);
    return true;
  };

  // Проход: каждое сообщение в ленте один раз читается и, если длинное, сворачивается тут же.
  const userFoldSync = () => {
    if (!state.alive) return;
    let messages = [];
    try { messages = [...document.querySelectorAll(USER_FOLD_SELECTOR)]; } catch { messages = []; }
    const live = new Set();
    for (const message of messages) {
      if (state.composerBlock?.contains?.(message)) continue;
      let seen = userFold.seen.get(message);
      if (!seen) {
        const full = userFoldText(message);
        const split = userFoldSplit(message, full);
        seen = { long: split ? true : userFoldLong(full) };
        if (split) Object.assign(seen, { head: split.head, bare: !userFoldLong(split.rest), restKept: split.restKept });
        if (seen.long) {
          seen.text = (split ? split.rest : full).slice(0, USER_FOLD_TEXT_MAX);
          seen.hash = userFoldSha1(seen.text);
        }
        userFold.seen.set(message, seen);
      }
      if (!seen.long) continue;
      live.add(message);
      let entry = userFold.entries.get(message);
      if (!entry) {
        const cached = userFoldStore().get(seen.hash);
        const asked = userFold.asked.get(seen.hash);
        const kind = cached ? "ai" : asked?.kind ?? "lead";
        entry = { message, hash: seen.hash, node: userFoldMake(), summary: cached?.s ?? asked?.summary ?? userFoldLead(seen.text), kind };
        if (seen.head != null) Object.assign(entry, { head: userFoldHeadMake(seen.head), bare: seen.bare });
        if (entry.bare) entry.summary = seen.restKept;
        userFold.entries.set(message, entry);
        userFoldPaint(entry);
        const again = !asked || (!asked.pending && !asked.summary && Date.now() - asked.at >= USER_FOLD_AGAIN_MS);
        if (!cached && again && !entry.bare) userFoldAsk(seen.hash, seen.text);
      }
      // Свои узлы — сразу под сообщением: верх #10904 (если есть), потом свёртка.
      const parent = message.parentNode;
      const chain = entry.head ? [entry.head, entry.node] : [entry.node];
      if (parent && chain.some((node, at) => node.parentNode !== parent || (chain[at - 1] ?? message).nextSibling !== node)) {
        try { let after = message; for (const node of chain) { parent.insertBefore(node, after.nextSibling); after = node; } } catch {}
      }
      userFoldClamp(message);
    }
    for (const [message, entry] of userFold.entries) {
      if (live.has(message)) continue;
      try { entry.node.remove(); } catch {}
      try { entry.head?.remove(); } catch {}
      userFold.entries.delete(message);
    }
  };

  const userFoldToggle = entry => {
    const open = userFold.open.get(entry.hash) !== true;
    userFold.open.set(entry.hash, open);
    for (const item of userFold.entries.values()) if (item.hash === entry.hash) userFoldPaint(item);
    // Свернул снизу длинного текста — блок мог уехать выше экрана: вернуть его в поле зрения.
    if (!open) { try { entry.node.scrollIntoView?.({ block: "nearest" }); } catch {} }
    return true;
  };
  const userFoldEntryOf = target => {
    const own = target?.closest?.(`[${USER_FOLD_ATTRIBUTE}]`);
    if (!own) return null;
    for (const entry of userFold.entries.values()) if (entry.node === own) return entry;
    return null;
  };
  // Нажатие: по кнопке — всегда; по сути — только свёрнутой и без выделения (выделить и скопировать
  // суть можно протяжкой). Двойной щелчок — одно нажатие.
  const onUserFoldClick = event => {
    if (!state.alive) return;
    const entry = userFoldEntryOf(event?.target);
    if (!entry || entry.bare) return;
    const onBar = Boolean(event.target.closest?.(`[${USER_FOLD_BAR_ATTRIBUTE}]`));
    if (!onBar) {
      if (userFold.open.get(entry.hash) === true) return;
      let selected = "";
      try { selected = String(window.getSelection?.()?.toString?.() ?? ""); } catch {}
      if (selected) return;
    }
    event.preventDefault?.();
    event.stopPropagation?.();
    if (Number(event.detail) > 1) return;
    try { userFoldToggle(entry); } catch {}
  };
  const onUserFoldKey = event => {
    if (!state.alive) return;
    const key = event?.key;
    if (key !== "Enter" && key !== " " && key !== "Spacebar" && key !== "Escape") return;
    const bar = event.target?.closest?.(`[${USER_FOLD_BAR_ATTRIBUTE}]`);
    const entry = bar ? userFoldEntryOf(bar) : null;
    if (!entry || entry.bare) return;
    if (key === "Escape" && userFold.open.get(entry.hash) !== true) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    try { userFoldToggle(entry); } catch {}
  };

  lateRules.push(
    `[${USER_FOLD_SOURCE_ATTRIBUTE}="closed"],[${USER_FOLD_CLAMP_ATTRIBUTE}="button"]{display:none !important}`,
    `[${USER_FOLD_CLAMP_ATTRIBUTE}="box"]{max-height:none !important;-webkit-mask-image:none !important;mask-image:none !important}`,
    `[${USER_FOLD_ATTRIBUTE}]{display:block;box-sizing:border-box;-webkit-app-region:no-drag}`,
    `[${USER_FOLD_ATTRIBUTE}="closed"]{margin:2px 0 2px calc(var(--myclaude-fold-mid, 7.4px) - .75px);padding:4px 12px 4px calc(10.75px - var(--myclaude-fold-mid, 7.4px) + 4px);border-left:1.5px solid currentColor;border-radius:0 8px 8px 0;background:rgba(127,127,127,.12);cursor:pointer;transition:background-color .15s}`,
    `[${USER_FOLD_ATTRIBUTE}="closed"]:hover{background:rgba(127,127,127,.2)}`,
    `[${USER_FOLD_ATTRIBUTE}="closed"]:active{background:rgba(127,127,127,.3)}`,
    `[${USER_FOLD_TEXT_ATTRIBUTE}]{white-space:pre-wrap;overflow-wrap:anywhere}`,
    `[${USER_FOLD_ATTRIBUTE}="open"] [${USER_FOLD_TEXT_ATTRIBUTE}]{display:none}`,
    `[${USER_FOLD_BAR_ATTRIBUTE}]{display:block;width:fit-content;margin-top:2px;font-weight:600;cursor:pointer;user-select:none;-webkit-user-select:none;border-radius:6px}`,
    `[${USER_FOLD_BAR_ATTRIBUTE}][${USER_FOLD_KIND_ATTRIBUTE}]::before{content:attr(${USER_FOLD_KIND_ATTRIBUTE}) " · ";font-weight:400;opacity:.6}`,
    `[${USER_FOLD_BAR_ATTRIBUTE}]::after{content:attr(${USER_FOLD_LABEL_ATTRIBUTE})}`,
    `[${USER_FOLD_BAR_ATTRIBUTE}]:focus-visible{outline:2px solid rgba(245,158,11,.7);outline-offset:1px}`,
    // Раскрыто: одна кнопка «Свернуть ▴» под текстом — вид раскрытой «▾ Свернуть ответ» (12ф).
    `[${USER_FOLD_ATTRIBUTE}="open"]{margin:8px 0 2px -4px}`,
    `[${USER_FOLD_ATTRIBUTE}="open"] [${USER_FOLD_BAR_ATTRIBUTE}]{margin:0;padding:4px 12px 4px 8px;border-radius:8px;background:rgba(127,127,127,.12);transition:background-color .15s}`,
    `[${USER_FOLD_ATTRIBUTE}="open"] [${USER_FOLD_BAR_ATTRIBUTE}]:hover{background:rgba(127,127,127,.2)}`,
    `[${USER_FOLD_ATTRIBUTE}="open"] [${USER_FOLD_BAR_ATTRIBUTE}]:active{background:rgba(127,127,127,.3)}`,
    // #10904: верх — ответ Рика основным цветом и целиком; раскрыто — его показывает исходник. Короткий низ — как текст.
    `[${USER_FOLD_ATTRIBUTE}="head"]{white-space:pre-wrap;overflow-wrap:anywhere;color:var(--cds-text-primary, currentColor) !important;margin:0 0 8px}`,
    `[${USER_FOLD_ATTRIBUTE}="head-open"]{display:none}`,
    `[${USER_FOLD_ATTRIBUTE}="plain"] [${USER_FOLD_BAR_ATTRIBUTE}]{display:none}`,
  );

  // Сироты прошлой установки — до первого прохода.
  try {
    for (const node of document.querySelectorAll(`[${USER_FOLD_ATTRIBUTE}]`)) node.remove();
    for (const attr of [USER_FOLD_SOURCE_ATTRIBUTE, USER_FOLD_CLAMP_ATTRIBUTE]) {
      for (const node of document.querySelectorAll(`[${attr}]`)) node.removeAttribute(attr);
    }
  } catch {}
  // Свой наблюдатель: сворачивает в том же колбэке, до отрисовки (общий тик раз в 500 мс опоздал бы
  // на кадр). Свои вставки будят его ещё раз — проход видит всё знакомым и ничего не делает.
  const userFoldObserved = () => { try { userFoldSync(); } catch {} };
  userFold.observer = new MutationObserver(userFoldObserved);
  userFold.observer.observe(document.documentElement, { childList: true, subtree: true });
  userFoldObserved();
  on(document, "click", onUserFoldClick, true);
  on(window, "keydown", onUserFoldKey, true);
  track(() => {
    userFold.observer?.disconnect();
    for (const asked of userFold.asked.values()) if (asked.timer) clearTimeout(asked.timer);
    for (const entry of userFold.entries.values()) {
      try { entry.node.remove(); } catch {}
      try { entry.head?.remove(); } catch {}
      try { entry.message.removeAttribute(USER_FOLD_SOURCE_ATTRIBUTE); } catch {}
    }
    try { for (const node of document.querySelectorAll(`[${USER_FOLD_CLAMP_ATTRIBUTE}]`)) node.removeAttribute(USER_FOLD_CLAMP_ATTRIBUTE); } catch {}
    userFold.entries.clear();
  });
  // Сколько длинных сообщений в ленте свёрнуто нами, сколько из них раскрыто, сколько сутей ждём от Пимпа.
  statusPart("userFold", () => ({
    count: userFold.entries.size,
    open: [...userFold.entries.values()].filter(entry => userFold.open.get(entry.hash) === true).length,
    pending: [...userFold.asked.values()].filter(asked => asked.pending).length,
  }));
  HATCH && Object.assign(HATCH, { userFoldObserved, userFoldLead, userFoldSha1, userFoldText });
