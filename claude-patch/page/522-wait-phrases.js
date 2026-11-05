  // ---- 12с². Фразы «Ждёт тебя» нажимаются (#10910) -------------------------
  // Слово Элвиса 24.10: «где ты просишь меня. Удалить у коллеги что-то… ты делай их кликабельными, чтобы я
  // мог на них понажимать. Тик-тык-тык-тык, чтоб я пронажимал, и это всё в поле ввода ставилось».
  // Раздел «Ждёт тебя» — заголовок или абзац, текст которого начинается с «Ждёт тебя» (перед ним — значки), и всё
  // до следующего заголовка или абзаца-подзаголовка (весь — одна жирная фраза не в «ёлочках»); в ЛЮБОМ ответе
  // ленты. Жирная фраза в «ёлочках» (или жирное предложение со «скажи «…»») в нём (**«выкладывай магнит»**) нажимается сама: метка WAIT_PHRASE_ATTRIBUTE на
  // родном strong — текст React не режем, своих кнопок и окошек нет (решение 22.10, #10643); копия и выделение как
  // были. Нажал — фраза без кавычек встаёт в поле отдельной строкой (хвост нажималок 12с, nazhToggle: свой текст
  // Элвиса не трогается, НЕ отправляется), ещё раз — строка снята. Двойной клик — одно нажатие (#7772); выделял
  // протяжкой — не нажатие; ссылка внутри — открывается как обычно. Выбранная — подсвечена. Смена чата и новый
  // ход — строки забыты (nazhWatch). Фраза вне «Ждёт тебя» и в реплике человека не ловится. Раздел-свёртка «❗ ЖДЁТ
  // ТЕБЯ» (#11478) — её тело.
  const WAIT_PHRASE_ATTRIBUTE = "data-myclaude-wait-phrase";
  const WAIT_HEAD_RE = /^[^\p{L}\p{N}]*Жд[её]т\s+тебя(?![\p{L}])/iu;
  const WAIT_QUOTED_RE = /^«([^«»]+)»[.,;:!?]*$/u;
  // Жирная фраза-предложение со «скажи «…»» внутри (живьём 24.10: «Магнит раньше часа — починено, скажи
  // «выкладывай».») — нажимается вся, в поле — слово в «ёлочках». «жми «Подтверждение»» — кнопка, не фраза.
  const WAIT_SAY_RE = /(?<![\p{L}])(?:скажи|скажешь|напиши|ответь)\s+«([^«»]+)»/iu;
  const WAIT_BUTTON_RE = /(?<![\p{L}])(?:жми|нажми|нажать|нажимай|кнопк\p{L}*)\s*$/iu;
  const WAIT_HEAD_MAX = 200;
  const waitPhrase = { marks: new Map(), clicks: 0 };
  const waitPhraseLine = phrase => ({ key: `wait:${phrase}`, group: `wait:${phrase}`, text: phrase, nl: true });
  const waitPhraseOf = node => {
    const text = sayNorm(node?.textContent);
    const exact = WAIT_QUOTED_RE.exec(text);
    if (exact) {
      const lead = node?.previousSibling?.nodeType === 3 ? String(node.previousSibling.nodeValue ?? "") : String(node?.previousSibling?.textContent ?? "");
      return WAIT_BUTTON_RE.test(lead) ? "" : exact[1].trim();
    }
    return WAIT_SAY_RE.exec(text)?.[1]?.trim() ?? "";
  };
  // Абзац-подзаголовок («**Дальше делаю я**»): весь текст — одна жирная фраза, и она не в «ёлочках».
  const waitPseudoHead = node => {
    if (node?.tagName !== "P") return false;
    const bold = node.querySelector?.("strong,b");
    return Boolean(bold) && sayNorm(bold.textContent) === sayNorm(node.textContent) && !waitPhraseOf(bold);
  };
  // Разделы «Ждёт тебя» ленты: у каждого — заголовок и узлы до следующего (общий разбор с 12с³, #10617).
  const waitSections = () => {
    const sections = [];
    let heads = [];
    try { heads = [...document.querySelectorAll(`${ATTN_HEAD_SELECTOR},p`)]; } catch { heads = []; }
    for (const head of heads) {
      const raw = String(head.textContent ?? "");
      if (raw.length > WAIT_HEAD_MAX || !WAIT_HEAD_RE.test(sayNorm(raw))) continue;
      if (head.closest?.('[contenteditable="true"],.epitaxy-user-turn,[data-testid="user-message"],li') || state.composerBlock?.contains?.(head)) continue;
      const block = [head];
      for (let node = head.nextElementSibling; node; node = node.nextElementSibling) {
        try { if (node.matches?.(ATTN_HEAD_SELECTOR) || node.querySelector?.(ATTN_HEAD_SELECTOR) || waitPseudoHead(node)) break; } catch { break; }
        block.push(node);
      }
      sections.push(block);
    }
    // #11478: с 01.11 раздел — свёртка `<summary><b>❗ ЖДЁТ ТЕБЯ — N (🔴 K)</b></summary>` (голова раздела 12ф, подпись —
    // в атрибуте): блок — её тело до </details>, без самой головы (12с³ сделал бы ссылкой «ЖДЁТ ТЕБЯ»). DOM, не
    // foldState: раздел 12ф склеен ниже.
    try { heads = [...document.querySelectorAll(`[${FOLD_HEAD_ATTRIBUTE}]`)]; } catch { heads = []; }
    for (const head of heads) {
      const fold = head.__myclaudeFold;
      if (!fold || fold.whole || !WAIT_HEAD_RE.test(fold.title)) continue;
      // Блок — от головы до последнего узла тела (#11651: теги бывают строками абзаца), свои сырые теги мимо.
      const block = [];
      const last = fold.body[fold.body.length - 1];
      const skip = new Set(fold.hide ?? []);
      if (last) for (let node = head.nextElementSibling; node && node !== fold.close; node = node.nextElementSibling) { if (!skip.has(node)) block.push(node); if (node === last) break; }
      sections.push(block);
    }
    return sections;
  };
  // Фразы в разделах «Ждёт тебя» ленты: родной strong → фраза.
  const waitPhraseScan = () => {
    const found = new Map();
    for (const block of waitSections()) {
      for (const node of block) {
        let bolds = [];
        try { bolds = [...(node.matches?.("strong,b") ? [node] : []), ...node.querySelectorAll("strong,b")]; } catch { bolds = []; }
        for (const bold of bolds) {
          if (found.has(bold) || bold.closest?.("a")) continue;
          const phrase = waitPhraseOf(bold);
          if (phrase) found.set(bold, phrase);
        }
      }
    }
    return found;
  };
  // Метки — ровно на фразах, что сейчас в ленте; «on» — фраза стоит в поле.
  const waitPhrasePaint = () => {
    if (!themable || !state.alive) return;
    const found = waitPhraseScan();
    for (const node of waitPhrase.marks.keys()) {
      if (!found.has(node)) { try { node.removeAttribute(WAIT_PHRASE_ATTRIBUTE); } catch {} }
    }
    for (const [node, phrase] of found) foldSet(node, WAIT_PHRASE_ATTRIBUTE, nazhHas(waitPhraseLine(phrase).key) ? "on" : "");
    waitPhrase.marks = found;
  };
  const onWaitPhraseClick = event => {
    if (event?.isTrusted !== true) return;
    const target = event.target;
    const bold = target?.closest?.(`[${WAIT_PHRASE_ATTRIBUTE}]`);
    const phrase = bold ? waitPhrase.marks.get(bold) : "";
    if (!phrase || target.closest?.("a")) return;
    let selected = "";
    try { selected = String(window.getSelection?.()?.toString?.() ?? ""); } catch {}
    if (selected) return;
    event.preventDefault?.();
    event.stopPropagation?.();
    if (!state.alive || Number(event.detail) > 1) return;
    waitPhrase.clicks += 1;
    try { nazhToggle(waitPhraseLine(phrase)); } catch {}
    try { waitPhrasePaint(); } catch {}
  };
  on(document, "click", onWaitPhraseClick, true);
  // Сироты прошлой установки — до первой разметки.
  try { for (const node of document.querySelectorAll(`[${WAIT_PHRASE_ATTRIBUTE}]`)) node.removeAttribute(WAIT_PHRASE_ATTRIBUTE); } catch {}
  try { waitPhrasePaint(); } catch {}
  track(() => {
    for (const node of waitPhrase.marks.keys()) { try { node.removeAttribute(WAIT_PHRASE_ATTRIBUTE); } catch {} }
    waitPhrase.marks.clear();
  });
  // Вид тихий: рука, при наведении — подчёркивание и лёгкая подсветка; выбранная — подсвечена.
  lateRules.push(
    `[${WAIT_PHRASE_ATTRIBUTE}]{cursor:pointer;border-radius:4px;-webkit-box-decoration-break:clone;box-decoration-break:clone;text-decoration-line:underline;text-decoration-style:dotted;text-decoration-color:transparent;text-underline-offset:3px;transition:background-color .15s,text-decoration-color .15s}`,
    `[${WAIT_PHRASE_ATTRIBUTE}]:hover{text-decoration-color:currentColor;background-color:rgba(245,158,11,.12)}`,
    `[${WAIT_PHRASE_ATTRIBUTE}="on"]{background-color:rgba(245,158,11,.28);text-decoration-color:currentColor}`,
  );
  // Фразы «Ждёт тебя» (раздел 12с²): сколько в ленте, сколько из них в поле, нажатий.
  statusPart("waitPhrases", () => ({
    count: waitPhrase.marks.size,
    on: [...waitPhrase.marks.values()].filter(phrase => nazhHas(waitPhraseLine(phrase).key)).length,
    clicks: waitPhrase.clicks,
  }));
  HATCH && Object.assign(HATCH, { waitPhrasePaint, waitPhrase });
