  // ---- 3а¹. Чистые ответы (#9398, WF209, контракт К-CA) ---------------------
  // Слово Элвиса 10.10 02:05: «не смотрю ни на контекст, ни кэши, ни новых. Ни ответ, ни чат, ни
  // опус… визуальным шумом… „Rick · идёт“ мне тоже не нужна. Давай ответы ещё чище делать»; облачко
  // «работа идёт» — «мне нравится». Прячется только ХВОСТ блока текста ответа: подряд идущие последние
  // абзацы верхнего уровня (не пункт списка, не таблица, не код), и только если КАЖДАЯ строка абзаца
  // служебная — строка состояния (ELVIS.md) или строки расхода (claude_footer.py). «Работа идёт 💭» и
  // «❗ Перечитка» остаются: абзац с ними виден целиком, но хвост они не обрывают. Строка отчёта
  // «… · готово ✅» посреди ответа — не хвост и не строка состояния, её не трогаем.
  // Узлы не удаляются: метка на абзаце + правило раздела 4. Вид — высота 0 и прозрачность, НЕ display
  // и не visibility: innerText такой абзац по-прежнему отдаёт, а через него ответ читают полоса 2б,
  // рамка «ждут твоего слова» и «Обкэшить». В идущем ответе последний блок текста ещё печатается — его
  // не трогаем (строка мигала бы на каждом слове); законченные блоки выше — можно.
  // Команда `clean-answers` {on:"true"|"false"} всем окнам; хранится в localStorage
  // ["myclaude.cleanAnswers"]: "0" — показывать, нет ключа (команды не было) — прятать.
  const CLEAN_ANSWERS_KEY = "myclaude.cleanAnswers";
  const CLEAN_ANSWERS_ATTRIBUTE = "data-myclaude-clean-answers";
  const CLEAN_ANSWERS_MARK = "data-myclaude-clean-line";
  const CLEAN_ANSWERS_MESSAGE = '[data-testid="transcript-row"] [data-cds="AssistantMessage"]';
  const CLEAN_ANSWERS_PROSE = '[data-cds="Prose"]';
  const CLEAN_NUMBER = "\\d+(?:[.,]\\d+)?\\s*[KM]?";
  const CLEAN_STATE_MARK = "(?:💭|❓|✅|🛑)";
  // Строки расхода: «Контекст 226K» / «Из кэша 96% · Новых 238K» / «Ответ 6.0M · Чат 6.0M · Opus 5.5
  // HIGH 💭» — каждая своей строкой или все одной (просмотрщик склеил); модели и значка может не быть.
  const CLEAN_USAGE_RE = new RegExp(`^(?:Контекст\\s+${CLEAN_NUMBER})?(?:\\s*[·•]?\\s*Из\\s+кэша\\s+\\d+\\s*%\\s*[·•]\\s*Новых\\s+${CLEAN_NUMBER})?` +
    `(?:\\s*[·•]?\\s*Ответ\\s+${CLEAN_NUMBER}\\s*[·•]\\s*Чат\\s+${CLEAN_NUMBER}(?:\\s*[·•]\\s*[^·•❗]{1,48}?)?(?:\\s*${CLEAN_STATE_MARK})?)?$`, "u");
  const CLEAN_NO_USAGE_RE = /^расход:\s*нет\s+данных$/iu;
  // Строка состояния: «<маркер>Проект · [WF N из M ·] идёт|жду|готово|упал <значок>». Маркер проекта
  // (эмодзи, не значок состояния) обязателен — по нему она отличается от строки отчёта «WF209 · готово ✅».
  const CLEAN_STATUS_RE = new RegExp(`^(?!${CLEAN_STATE_MARK}|❗)\\p{Extended_Pictographic}[\\uFE0F\\u200D\\p{Extended_Pictographic}]{0,6}\\s?` +
    `[\\p{L}\\p{N}][^·•]{0,59}?\\s+[·•]\\s+(?:WF\\s+\\d+\\s+из\\s+\\d+\\s+[·•]\\s+)?(?:идёт|жду|готово|упал)\\s*${CLEAN_STATE_MARK}$`, "u");
  // Остаются на виду: облачко «Работа идёт 💭» и «❗ Перечитка N мимо кэша» — своей строкой или слитая
  // со строками расхода в одну (тогда остаётся вся строка).
  const CLEAN_CLOUD_RE = /^Работа\s+идёт\s*(?:\d{1,3}\s*\/\s*\d{1,3}\s*)?💭(?:\s*\d{1,3}\s*\/\s*\d{1,3})?$/u;
  const CLEAN_REREAD_RE = /^(.*?)\s*❗\uFE0F?\s*Перечитка(?![\p{L}]).*$/u;
  // Разбор одной строки хвоста (чистая функция): "hide" — служебная, прятать; "keep" — служебная, но
  // остаётся на виду; null — обычный текст ответа.
  const cleanAnswerLine = raw => {
    const line = String(raw ?? "").replace(PROGRESS_LINK_RE, "$1").replace(/\s+/g, " ").trim();
    if (!line) return null;
    if (CLEAN_CLOUD_RE.test(line)) return "keep";
    const reread = line.match(CLEAN_REREAD_RE);
    if (reread) return !reread[1] || CLEAN_USAGE_RE.test(reread[1]) ? "keep" : null;
    if (CLEAN_USAGE_RE.test(line) || CLEAN_NO_USAGE_RE.test(line) || CLEAN_STATUS_RE.test(line)) return "hide";
    return null;
  };
  // Строки абзаца: перенос — <br> или перевод строки в тексте. Узел без детей, но с текстом
  // (стенд тестов) — сам себе текст.
  const cleanAnswerLines = node => {
    const lines = [""];
    const put = text => {
      const parts = String(text ?? "").split("\n");
      lines[lines.length - 1] += parts[0];
      for (const part of parts.slice(1)) lines.push(part);
    };
    const walk = item => {
      const kids = [...(item.childNodes ?? [])];
      if (!kids.length) { put(item.textContent); return; }
      for (const kid of kids) {
        if (kid.nodeType === 3) put(kid.nodeValue);
        else if (kid.nodeType === 1 && kid.tagName === "BR") lines.push("");
        else if (kid.nodeType === 1) walk(kid);
      }
    };
    walk(node);
    return lines.map(line => line.trim()).filter(Boolean);
  };
  // Хвост одного блока текста: абзацы верхнего уровня с конца, пока каждый — только из служебных строк.
  const cleanAnswerTail = prose => {
    // Абзацы лежат под обёрткой без своего вида (у Claude — div.contents).
    let host = prose;
    for (let depth = 0; depth < 2 && host.children.length === 1 && host.children[0].tagName === "DIV"; depth += 1) host = host.children[0];
    const hide = [];
    const blocks = [...host.children];
    for (let index = blocks.length - 1; index >= 0; index -= 1) {
      const block = blocks[index];
      if (block.tagName !== "P") break;
      const kinds = cleanAnswerLines(block).map(cleanAnswerLine);
      if (!kinds.length || kinds.includes(null)) break;
      if (kinds.every(kind => kind === "hide")) hide.push(block);
    }
    return hide;
  };
  const cleanAnswers = { on: true, observer: null };
  const cleanAnswersOn = () => {
    try { return localStorage.getItem(CLEAN_ANSWERS_KEY) !== "0"; } catch { return true; }
  };
  const cleanAnswersSync = () => {
    const want = new Set();
    if (cleanAnswers.on) {
      for (const message of document.querySelectorAll(CLEAN_ANSWERS_MESSAGE)) {
        const proses = [...message.querySelectorAll(CLEAN_ANSWERS_PROSE)];
        if (message.getAttribute("data-is-streaming") === "true") proses.pop();
        for (const prose of proses) for (const node of cleanAnswerTail(prose)) want.add(node);
      }
    }
    for (const node of document.querySelectorAll(`[${CLEAN_ANSWERS_MARK}]`)) {
      if (!want.has(node)) node.removeAttribute(CLEAN_ANSWERS_MARK);
    }
    for (const node of want) if (!node.hasAttribute(CLEAN_ANSWERS_MARK)) node.setAttribute(CLEAN_ANSWERS_MARK, "");
  };
  const cleanAnswersMark = () => {
    const root = document.documentElement;
    cleanAnswers.on = cleanAnswersOn();
    if (cleanAnswers.on) {
      if (!root.hasAttribute(CLEAN_ANSWERS_ATTRIBUTE)) root.setAttribute(CLEAN_ANSWERS_ATTRIBUTE, "");
      if (!cleanAnswers.observer) {
        // Сверка сразу в колбэке наблюдателя, до отрисовки (как у 3а): новая строка ленты не мелькает
        // служебным хвостом и не меняет высоту после первого замера. Своя метка в фильтр не входит.
        cleanAnswers.observer = new MutationObserver(() => { try { cleanAnswersSync(); } catch {} });
        cleanAnswers.observer.observe(root, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ["data-is-streaming"] });
      }
    } else {
      root.removeAttribute(CLEAN_ANSWERS_ATTRIBUTE);
      cleanAnswers.observer?.disconnect();
      cleanAnswers.observer = null;
    }
    cleanAnswersSync();
  };
  const cleanAnswersSet = value => {
    try {
      if (value) localStorage.removeItem(CLEAN_ANSWERS_KEY);
      else localStorage.setItem(CLEAN_ANSWERS_KEY, "0");
    } catch {}
    cleanAnswersMark();
  };
  const cleanAnswersHidden = () => cleanAnswers.on ? document.querySelectorAll(`[${CLEAN_ANSWERS_MARK}]`).length : 0;
  cleanAnswersMark();
  on(window, "storage", event => { if (event.key === CLEAN_ANSWERS_KEY || event.key === null) cleanAnswersMark(); });
  track(() => {
    cleanAnswers.observer?.disconnect();
    document.documentElement.removeAttribute(CLEAN_ANSWERS_ATTRIBUTE);
    for (const node of document.querySelectorAll(`[${CLEAN_ANSWERS_MARK}]`)) node.removeAttribute(CLEAN_ANSWERS_MARK);
  });
  statusPart("cleanAnswers", () => ({ on: cleanAnswers.on, hidden: cleanAnswersHidden() }));
  HATCH && Object.assign(HATCH, { cleanAnswerLine, cleanAnswersSync });

