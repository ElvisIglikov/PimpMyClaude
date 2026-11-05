  // ---- 12д². Наши ссылки — в панель слева или в Trelvis (WF288, #10891, #10892) ----
  // Слово Элвиса 24.10.2026 (#10891): ссылка отчёта https://vkusstatbot-production.up.railway.app/r/<токен> в чате
  // Рика открылась во встроенном браузере Claude справа, а «должен был в левом окошке открыться» (решение 22.10,
  // #10644: «Любая ссылка в чате Claude (картинка, md, ролик) открывается в этой панели, а не справа — справа
  // открытие ломает раскладку»). #10892: ссылка задачи Trelvis https://vlusnoff-production.up.railway.app/#t/<N> —
  // «Нажимаю, ничего не происходит».
  //
  // Класс ссылок — строка OUR_LINK_CLASSES (контракт docs/contracts/600-wf288-our-links.md, К-LINK):
  //  - «report» и «picture» — отчёт VkusStatBot и его картинка превью: файл лежит на диске
  //    `<корень проектов>VkusStatBot/reports/<токен>.html|.png` (SkilZZZ/CHARTS.md; сервер statbot/app.py отдаёт
  //    ровно его). Клик — тем же путём, что клик по файлу из чата (fileClick, 12д¹: панель материалов или галерея).
  //    Корня нет (его присылает приложение командой trust-root, раздел 12е) — ссылку не трогаем;
  //  - «task» — задача Trelvis: ручка Пимпа `/open-link` (Trelvis.app по trelvis://, без него — Google Chrome).
  //    Сама страница не может: свою схему Claude молча выбрасывает, https — в браузер справа.
  // Запасной путь — window.open(адрес) (у Claude это браузер системы, не панель справа — разбор #11118, раздел 12д³),
  // клик молча не пропадает: Пимп не ответил за
  // OUR_LINK_WAIT_MS, ответил не 2xx (404 — файла нет или старый Пимп без `/open-link`), у задачи — не opened:true.
  // Ловим только левый клик человека без модификаторов по a[href] в ленте (.prose или ряд transcript-row), не в
  // поле ввода; нажатие (pointerdown/mousedown) своих классов глушим, как у ссылок на файлы 12д¹ (у ссылок Claude
  // вешает действия и на нажатие), клик — открывает.
  const OUR_LINK_CLASSES = [
    { kind: "report", re: /^https:\/\/vkusstatbot-production\.up\.railway\.app\/r\/([A-Za-z0-9_-]{8,64})\/?(?:[?#].*)?$/,
      file: token => `VkusStatBot/reports/${token}.html` },
    { kind: "picture", re: /^https:\/\/vkusstatbot-production\.up\.railway\.app\/r\/([A-Za-z0-9_-]{8,64})\.png(?:[?#].*)?$/,
      file: token => `VkusStatBot/reports/${token}.png` },
    { kind: "task", re: /^https:\/\/vlusnoff-production\.up\.railway\.app\/#(?:t|task)\/([1-9]\d{0,8})$/ },
    { kind: "task", re: /^(?:trelvis|kaban):\/\/task\/([1-9]\d{0,8})$/ },
  ];
  const OUR_LINK_FEED_SELECTOR = `.prose,${MENTION_ROW_SELECTOR}`;
  // Дольше ожидания дока у Пимпа (6 с): поздний ответ после запасного пути не открывает второй раз.
  const OUR_LINK_WAIT_MS = 8000;
  const ourLinksState = { clicks: 0, fallbacks: 0, repeats: 0, last: null, href: "", at: 0 };
  // Адрес ссылки (как есть в href) → { kind, href, path? | task? } или null. Корня проектов нет — файлы не наши.
  const ourLinkMatch = raw => {
    let href = "";
    try { href = new URL(String(raw ?? "").trim()).href; } catch { return null; }
    for (const item of OUR_LINK_CLASSES) {
      const match = item.re.exec(href);
      if (!match) continue;
      if (!item.file) return { kind: item.kind, href, task: Number(match[1]) };
      const root = autoTrustRoot();
      return root ? { kind: item.kind, href, path: `${root}${item.file(match[1])}` } : null;
    }
    return null;
  };
  // Ссылка нашего класса под кликом: { kind, href, path?|task?, node } или null.
  const ourLinkAt = target => {
    const node = target?.closest?.("a[href]");
    if (!node || !node.closest?.(OUR_LINK_FEED_SELECTOR) || node.closest?.('[contenteditable="true"]')) return null;
    const found = ourLinkMatch(node.getAttribute?.("href"));
    return found ? { ...found, node } : null;
  };
  const ourLinkPlain = event => event.isTrusted === true && event.button === 0
    && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey;
  const ourLinkFallback = (link, why) => {
    ourLinksState.fallbacks += 1;
    ourLinksState.last = { kind: link.kind, via: "claude", why };
    try { window.open(link.href, "_blank"); } catch {}
  };
  // Ответ порта → открыл ли Пимп. Файл: любой 2xx (204 прежнего клика, {taken…} дока — док не взял, Пимп открыл
  // сам), 404 — файла нет. Задача: 2xx и opened:true.
  const ourLinkOpened = (reply, json) => {
    if (!reply?.ok) return Promise.resolve(false);
    if (!json) return Promise.resolve(true);
    if (typeof reply.json !== "function") return Promise.resolve(false);
    return reply.json().then(body => body?.opened === true, () => false);
  };
  // Один исход на клик: ответ или срок OUR_LINK_WAIT_MS, что раньше.
  const ourLinkOutcome = link => {
    let over = false;
    const timer = setTimeout(() => { if (!over && state.alive) { over = true; ourLinkFallback(link, "late"); } }, OUR_LINK_WAIT_MS);
    const outcome = (reply, json) => {
      if (over) return;
      ourLinkOpened(reply, json).then(ok => {
        if (over) return;
        over = true;
        clearTimeout(timer);
        if (!state.alive) return;
        if (ok) ourLinksState.last = { kind: link.kind, via: "pimp" };
        else ourLinkFallback(link, reply ? `http ${reply.status}` : "no-reply");
      });
    };
    // Запрос не ушёл (тот же файл уже открывается) — исход решит первый.
    outcome.cancel = () => { over = true; clearTimeout(timer); };
    return outcome;
  };
  const ourLinkOpen = link => {
    // Тот же адрес второй раз, пока первый открывается (двойной клик), — ничего.
    const t = Date.now();
    if (link.href === ourLinksState.href && t - ourLinksState.at < HTML_CHROME_REPEAT_MS) {
      ourLinksState.repeats += 1;
      return;
    }
    ourLinksState.href = link.href;
    ourLinksState.at = t;
    ourLinksState.clicks += 1;
    ourLinksState.last = { kind: link.kind, via: "asked" };
    const outcome = ourLinkOutcome(link);
    if (link.path) {
      if (!fileClick(link.path, link.node, reply => outcome(reply, false))) outcome.cancel();
      return;
    }
    if (typeof fetch !== "function") { outcome(null, true); return; }
    try {
      fetch(`http://127.0.0.1:${HTML_CHROME_PORT}/open-link?url=${encodeURIComponent(link.href)}`,
        { mode: "cors", credentials: "omit", cache: "no-store" })
        .then(reply => outcome(reply, true), () => outcome(null, true));
    } catch { outcome(null, true); }
  };
  const onOurLinkPress = event => {
    if (!ourLinkPlain(event)) return;
    let link = null;
    try { link = ourLinkAt(event.target); } catch { link = null; }
    if (!link) return;
    event.preventDefault();
    event.stopImmediatePropagation();
  };
  const onOurLinkClick = event => {
    if (!ourLinkPlain(event)) return;
    let link = null;
    try { link = ourLinkAt(event.target); } catch { link = null; }
    if (!link) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    ourLinkOpen(link);
  };
  // Наши ссылки (раздел 12д², WF288): сколько кликов забрали, сколько отдали Claude запасным путём, повторы,
  // последний исход { kind, via: asked|pimp|claude, why? }.
  statusPart("ourLinks", () => ({ clicks: ourLinksState.clicks, fallbacks: ourLinksState.fallbacks,
    repeats: ourLinksState.repeats, last: ourLinksState.last }));
  HATCH && Object.assign(HATCH, { OUR_LINK_CLASSES, ourLinkMatch, ourLinkAt, ourLinksState, onOurLinkClick,
    onOurLinkPress });

