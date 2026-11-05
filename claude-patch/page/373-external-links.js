  // ---- 12д³. Внешние ссылки ленты — в системный браузер, не в браузер Claude справа (#11118) ----
  // Слово Элвиса 29.10.2026 (#11118): «А нельзя сразу Google Chrome открывать ссылки, чтобы без вот этого встроенного
  // браузера… Справа, который открывается. Постоянно правой кнопкой приходится открывать».
  //
  // Почему так (разбор app.asar Claude, 30.10): клик по ссылке ленты Claude ловит сам и зовёт мост
  // `Launch.openExternalLinkInPreview` — вкладка браузера справа. `window.open(адрес)` из страницы идёт другой дорогой:
  // обработчик окна главного вида → роутер ссылок (`trigger:"window-open"`) → для чужого http(s) `shell.openExternal`,
  // то есть браузер системы по умолчанию (у Элвиса — Google Chrome, правило 27.09.2026 «Ссылки — в Google Chrome»).
  // Окно Claude пропускает такой `window.open` только в пределах 5 с после нажатия человека.
  //
  // #11323 (31.10, слово Элвиса: «Я чик нажал и перешёл сразу в Хром на нужную вкладку»): сначала Пимп —
  // `/open-link?kind=web&url=…` (К-LINK): уже открытая вкладка Chromium вперёд, нет — новая. Ответ `opened:true` — всё;
  // Пимп молчит EXTERNAL_LINK_WAIT_MS, ошибка, не 2xx (старый Пимп без вида — 400) — прежний `window.open`, ещё в окне 5 с.
  //
  // Ловим левый клик человека без модификаторов по a[href] с http(s) в ленте (`.prose` или ряд transcript-row), не
  // в поле ввода; наши классы (раздел 12д²) не трогаем — их ловит он, адреса самого Claude (claude.ai, claude.com,
  // anthropic.com) — тоже: им место в Claude. Нажатие (pointerdown/mousedown) глушим, как у 12д² (Claude вешает
  // действия и на нажатие), клик — открываем. Модификатор или правая кнопка — у Claude, как было.
  const EXTERNAL_LINK_CLAUDE_HOST_RE = /(?:^|\.)(?:claude\.ai|claude\.com|anthropic\.com)$/i;
  const EXTERNAL_LINK_WAIT_MS = 1500;
  const externalLinksState = { clicks: 0, repeats: 0, failed: 0, pimp: 0, last: null, href: "", at: 0 };
  // Адрес ссылки (как есть в href) → нормализованный http(s)-адрес или null.
  const externalLinkMatch = raw => {
    let url = null;
    try { url = new URL(String(raw ?? "").trim()); } catch { return null; }
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    if (!url.hostname || EXTERNAL_LINK_CLAUDE_HOST_RE.test(url.hostname.replace(/\.+$/, ""))) return null;
    if (ourLinkMatch(url.href)) return null;
    return url.href;
  };
  // Внешняя ссылка ленты под кликом: { href, node } или null.
  const externalLinkAt = target => {
    const node = target?.closest?.("a[href]");
    if (!node || !node.closest?.(OUR_LINK_FEED_SELECTOR) || node.closest?.('[contenteditable="true"]')) return null;
    const href = externalLinkMatch(node.getAttribute?.("href"));
    return href ? { href, node } : null;
  };
  const externalLinkOpen = link => {
    // Тот же адрес второй раз за HTML_CHROME_REPEAT_MS (двойной клик) — одно окно браузера.
    const t = Date.now();
    if (link.href === externalLinksState.href && t - externalLinksState.at < HTML_CHROME_REPEAT_MS) {
      externalLinksState.repeats += 1;
      return;
    }
    externalLinksState.href = link.href;
    externalLinksState.at = t;
    externalLinksState.clicks += 1;
    const host = (() => { try { return new URL(link.href).host; } catch { return ""; } })();
    // Один исход на клик: ответ Пимпа или срок, что раньше.
    let over = false;
    let timer = null;
    const browser = () => {
      if (over) return;
      over = true;
      if (timer) clearTimeout(timer);
      if (!state.alive) return;
      let ok = false;
      try { window.open(link.href, "_blank"); ok = true; } catch { ok = false; }
      if (!ok) externalLinksState.failed += 1;
      externalLinksState.last = { host, ok };
    };
    if (typeof fetch !== "function") { browser(); return; }
    timer = setTimeout(browser, EXTERNAL_LINK_WAIT_MS);
    try {
      fetch(`http://127.0.0.1:${HTML_CHROME_PORT}/open-link?kind=web&url=${encodeURIComponent(link.href)}`,
        { mode: "cors", credentials: "omit", cache: "no-store" })
        .then(reply => (reply?.ok && typeof reply.json === "function" ? reply.json().then(body => body?.opened === true, () => false) : false),
          () => false)
        .then(opened => {
          if (over) return;
          if (!opened) { browser(); return; }
          over = true;
          clearTimeout(timer);
          externalLinksState.pimp += 1;
          externalLinksState.last = { host, ok: true, via: "pimp" };
        });
    } catch { browser(); }
  };
  const onExternalLinkPress = event => {
    if (!ourLinkPlain(event)) return;
    let link = null;
    try { link = externalLinkAt(event.target); } catch { link = null; }
    if (!link) return;
    event.preventDefault();
    event.stopImmediatePropagation();
  };
  const onExternalLinkClick = event => {
    if (!ourLinkPlain(event)) return;
    let link = null;
    try { link = externalLinkAt(event.target); } catch { link = null; }
    if (!link) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    externalLinkOpen(link);
  };
  // Внешние ссылки (раздел 12д³, #11118, #11323): сколько кликов отдали браузеру системы, повторы, отказы window.open,
  // сколько открыл Пимп на вкладке, последний исход { host, ok, via? } (via:"pimp" — Пимп, нет — window.open).
  statusPart("externalLinks", () => ({ clicks: externalLinksState.clicks, repeats: externalLinksState.repeats,
    failed: externalLinksState.failed, pimp: externalLinksState.pimp, last: externalLinksState.last }));
  HATCH && Object.assign(HATCH, { EXTERNAL_LINK_WAIT_MS, externalLinkMatch, externalLinkAt, externalLinksState, onExternalLinkClick,
    onExternalLinkPress });
