  // ---- 12д. HTML-файлы — в Chrome, а не в панель Browser (#6618) -------------
  // Слово Элвиса 20.09.2026: «одно нажатие на HTML-ку открывает его в Хроме… и
  // панелька, если даже открылась, чтобы она закрылась сразу… если файл уже
  // открыт — новую вкладку не открывал, ту же показывал».
  //
  // Клик по карточке .html/.htm (кнопка, путь — из того же волокна, что у 12г)
  // глушится на захвате: Claude панель не открывает. Панель открылась сама (файл
  // только что собран) — раз в HTML_CHROME_TICK_MS смотрим поле «Page URL»
  // панели Browser: там абсолютный путь .html — закрываем эту вкладку панели, а
  // если других настоящих вкладок нет — и саму панель.
  //
  // Открывает приложение (HtmlChromeOpener.swift): запрос на 127.0.0.1, оно ищет
  // вкладку с этим файлом в Chrome и выводит её вперёд (`click`). Вкладку, которую
  // панель открыла сама, страница только закрывает (#8177, ниже). Приложения нет —
  // мост Claude, как в 12г (новая вкладка). Ответ CORS: дошёл запрос — и хорошо.
  const HTML_CHROME_PORT = 47615;
  const HTML_CHROME_TICK_MS = 400;
  const HTML_CHROME_REPEAT_MS = 3000;
  // #11618: надпись на обоих языках перечислением через запятую, не uiAria: :is() стаб DOM тестов не понимает.
  const HTML_CHROME_URL_SELECTOR = 'input[aria-label="Page URL"],input[aria-label="URL страницы"]';
  const HTML_CHROME_TAB_SELECTOR = "[data-vtb-id]";
  const HTML_CHROME_NEW_TAB_RE = /^(?:New tab|Новая вкладка)$/i;
  // Что уходит из панели наружу (#6621): страницы и PDF — в Chrome, картинки — в
  // «Просмотр»; куда именно — решает приложение по расширению.
  const HTML_CHROME_FILE_RE = /\.(html?|pdf|png|jpe?g|gif|webp|heic|tiff?|bmp)$/i;
  // Что клик по файлу из чата забирает у Claude (WF277, #10644, слово Элвиса: «любая ссылка… html, картинка, md,
  // pdf, ролик» — в панели, а не справа): виды панели Пимпа плюс md/markdown/txt, видео и звук (контракт
  // 560-wf277-dock, «Виды файлов»). Один фильтр на карточку (12д) и ссылку в тексте (12д¹) — только пока панель
  // материалов годна (dockUsable, раздел 12п⁴); без неё у новых видов прежних путей нет, их клик остаётся Claude.
  // zip (#11347) — галерея показывает архив деревом.
  const FILE_OPEN_RE = /\.(html?|pdf|png|jpe?g|gif|webp|heic|tiff?|bmp|md|markdown|txt|mp4|mov|m4v|webm|mp3|m4a|aac|wav|zip)$/i;
  const fileOpenable = (path, before = HTML_CHROME_FILE_RE) => (dockUsable() ? FILE_OPEN_RE : before).test(path);
  const htmlChromeState = { clicks: 0, closed: 0, last: null, timer: 0, clickPath: "", clickAt: 0, repeats: 0, views: 0, viewPath: "", viewAt: 0 };
  // Просмотр в окне чата (WF103, #7939): `view` — html/htm по клику Элвиса.
  // Своя защита от повтора — 1 с на тот же путь (у `click` — прежние 3 с).
  const HTML_VIEW_REPEAT_MS = 1000;
  const HTML_VIEW_PAGE_RE = /\.html?$/i;
  // Фото-файлы карточек (WF103, решение 3) — в просмотр 12л этого окна.
  const HTML_VIEW_PHOTO_RE = /\.(png|jpe?g|gif|webp)$/i;
  // Рамка окна чата для `view` (контракт волны 1 WF103): x,y — целые со знаком,
  // w,h — целые > 0; иначе ключа нет. bg — 6 hex без «#»; иначе ключа нет.
  const htmlChromeFrameKey = frame => (Array.isArray(frame) && frame.length === 4 && frame.every(Number.isInteger)
    && frame[2] > 0 && frame[3] > 0 ? frame.join(",") : "");
  const htmlChromeBgKey = bg => {
    const match = /^#?([0-9a-f]{6})$/i.exec(typeof bg === "string" ? bg.trim() : "");
    return match ? match[1].toLowerCase() : "";
  };
  // Адрес запроса (К-V1, WF97): `chat` — id этого чата, по нему приложение
  // кладёт файл в ленту Pimp Viewer; id неизвестен — ключа нет вовсе. Порядок
  // ключей: mode, path, chat, frame, bg (frame и bg — у `view`, WF103, и у клика
  // по странице или фото, WF107). dock (WF277, К-DOCK-1) — файл в панель материалов: место панели и рамка окна
  // в том же запросе, `mode, dock=1, path, chat, x, y, w, h, wx, wy, ww, wh`, и прежние frame и bg — для запасного
  // пути приложения (док не взял страницу — окно просмотра поверх чата, как до WF277).
  const htmlChromeUrl = (path, mode, chat, frame = null, bg = "", dock = null) => {
    const box = htmlChromeFrameKey(frame);
    const paint = htmlChromeBgKey(bg);
    const room = dock ? dockPlaceKeys(dock) : "";
    return `http://127.0.0.1:${HTML_CHROME_PORT}/open-html?mode=${mode}${room ? "&dock=1" : ""}&path=${encodeURIComponent(path)}` +
      (typeof chat === "string" && chat ? `&chat=${encodeURIComponent(chat)}` : "") +
      (room ? `&${room}` : "") + (box ? `&frame=${box}` : "") + (paint ? `&bg=${paint}` : "");
  };
  // extra (WF107, К3): frame — рамка и фон окна и у клика (запасной путь
  // приложения — просмотр в окне чата), settle — ответ пришёл или ушли в мост.
  // reply (WF288, раздел 12д²) — ответ порта целиком (Response; не дошёл — null) вместо моста: свой запасной путь у
  // того, кто спросил. Запрос ушёл — true, повтор того же файла — false.
  const htmlChromeAsk = (path, mode, done, extra = null) => {
    // Тот же файл нажат ещё раз, пока первый только открывается (двойной клик
    // по карточке или пункту меню, #7772), — второй вкладки нет. done не зовём:
    // меню закроет первый ответ, а лишний Escape оборвал бы ответ Claude.
    if (mode === "click" || mode === "browser") {
      const t = Date.now();
      if (path === htmlChromeState.clickPath && t - htmlChromeState.clickAt < HTML_CHROME_REPEAT_MS) {
        htmlChromeState.repeats += 1;
        return false;
      }
      htmlChromeState.clickPath = path;
      htmlChromeState.clickAt = t;
    }
    // Просмотр (WF103): тот же файл второй раз за секунду — одно окно.
    let frame = null;
    let bg = "";
    if (mode === "view") {
      const t = Date.now();
      if (path === htmlChromeState.viewPath && t - htmlChromeState.viewAt < HTML_VIEW_REPEAT_MS) {
        htmlChromeState.repeats += 1;
        return false;
      }
      htmlChromeState.viewPath = path;
      htmlChromeState.viewAt = t;
      htmlChromeState.views += 1;
    }
    if (mode === "view" || extra?.frame) {
      // Рамка — готовая chatFrame (сверена с AX), фон — фон темы окна (как у угла).
      try { frame = chatFrame(chatKind()); } catch { frame = null; }
      try { bg = progressHex(cornerBackground()) ?? ""; } catch { bg = ""; }
    }
    htmlChromeState.last = { path, mode, via: extra?.dock ? "dock" : "app" };
    const settle = () => { try { extra?.settle?.(); } catch {} };
    const fallback = () => {
      if (extra?.reply) {
        htmlChromeState.last = { path, mode, via: "none" };
        settle();
        try { extra.reply(null); } catch {}
        return;
      }
      htmlChromeState.last = { path, mode, via: "bridge" };
      try { openChromeOpen(path); } catch {}
      settle();
    };
    if (typeof fetch !== "function") { fallback(); return true; }
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    try {
      fetch(htmlChromeUrl(path, mode, chat, frame, bg, extra?.dock ?? null), { mode: "cors", credentials: "omit", cache: "no-store" })
        .then(reply => {
          if (!extra?.holdOnReply) settle();
          try { done?.(); } catch {}
          try { extra?.reply?.(reply); } catch {}
        }, fallback);
    } catch { fallback(); }
    return true;
  };
  const onHtmlChromeClick = event => {
    // Только клик человека (PimpViewer 1.6: «файлы открываются сами»): синтетический клик по
    // карточке — не просьба открыть файл.
    if (event.isTrusted !== true) return;
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    // Карточка HTML/PDF (#10229, раздел 12м⁴): снимок над плашкой мышь пропускает — попали в саму плитку, путь
    // у снимка. С #11304 — любой вид карточки со снимком (plate-doc SendUserFile, card-doc, square-doc), кроме поля
    // ввода: там кнопка в плитке — «убрать вложение»; волокно пути не дало — путь снимка своей карточки.
    const card = event.target?.closest?.(`[${HEIC_ATTRIBUTE}$="doc"]:not([${HEIC_ATTRIBUTE}^="field"])`);
    const tile = card ? null : event.target?.closest?.(FILE_TILE_SELECTOR);
    const button = event.target?.closest?.("button") ?? card ?? tile;
    if (!button) return;
    const shotPath = () => ({ path: card?.querySelector(`[${HEIC_IMG_ATTRIBUTE}]`)?.__myclaudeHeic });
    let found = null;
    try {
      found = button === card ? shotPath() : button === tile ? fileTilePath(tile) : openChromePath(button);
      if (typeof found?.path !== "string" && card && button.contains(card)) found = shotPath();
    } catch { found = null; }
    if (typeof found?.path !== "string") return;
    if (!found || !fileOpenable(found.path)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    htmlChromeState.clicks += 1;
    fileClick(found.path, button);
  };
  // «Открыть в Chrome» (раздел 12г, WF67): ждём ли меню после правого клика,
  // какой путь нашли, сколько пунктов вставили, чем кончился последний вызов.
  statusPart("htmlChrome", () => ({ clicks: htmlChromeState.clicks, repeats: htmlChromeState.repeats, closed: htmlChromeState.closed, views: htmlChromeState.views, last: htmlChromeState.last }));
  HATCH && Object.assign(HATCH, { htmlChromeUrl, FILE_OPEN_RE });
