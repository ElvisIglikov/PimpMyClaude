  // ---- 12г. Открыть в Chrome и Копировать в буфер (WF67 #6190, WF69 #6236) --
  // Слово Элвиса 17.09: «правой кнопкой открываю, а здесь не вижу до сих пор
  // открыть в Хром… приходится через Файндер идти». У Claude в контекстном меню
  // карточки файла есть «Show in Finder», а открыть файл браузером негде.
  //
  // Мост есть у самого Claude (разведка WF67):
  //   window["claude.web"].LocalSessions.openSessionFileInDefaultApp(sessionId, path)
  // — имя свойства окна с точкой, доступ только скобками; аргументы ПОЗИЦИОННЫЕ
  // (объект `{sessionId, path}` — ошибка «Argument sessionId at position 0»);
  // sessionId — id чата `local_<uuid>`, тот же, что даёт myChatId() раздела 12в.
  // `FileSystem.openLocalFile` НЕ годится: это сессии Cowork, ответ INVALID_SESSION.
  //
  // Устройство: `contextmenu` на захвате НИЧЕГО не отменяет — меню Claude
  // открывается само. Мы только запоминаем путь файла (из React-волокна
  // карточки: пропс `path`) и на 1,5 с ставим наблюдателя за body: появилось
  // меню с пунктом «Show in Finder» — ставим в него ПЕРВЫМИ свои пункты (клоны
  // «Show in Finder» без React-обработчиков и без id) и клон разделителя.
  // Постоянного наблюдателя нет: правый клик по тексту меню не трогает вовсе.
  //
  // Второй пункт — «📋 Копировать в буфер» (WF69, #6236, слово Элвиса 17.09:
  // «правой кнопкой — копировать в буфер, сам файл скопирует, потом в Telegram
  // „вставить“ — и он вставит файл; а то приходится Finder открывать»). Он есть
  // у ЛЮБОГО файла с путём, не только у страниц. Страница положить в буфер ФАЙЛ
  // не может — только текст; файл (public.file-url, как «Скопировать» в Finder)
  // кладёт приложение по запросу на порт 47615 (WF106): см. copyFileToClipboard ниже.
  const OPEN_CHROME_ATTRIBUTE = "data-myclaude-open-chrome";
  // Браузер выбирает приложение: браузер по умолчанию (WF108, #8146) — страница
  // этого не знает, поэтому подпись без имени браузера.
  const OPEN_CHROME_LABEL = "🌐 Открыть в браузере";
  const COPY_FILE_LABEL = "📋 Копировать в буфер";
  // Прежний клик по карточке (WF103, #7939) — с WF107 (#8127) пунктом правого клика.
  const VIEW_FILE_LABEL = "👁 Посмотреть в окне чата";
  const OPEN_WINDOW_LABEL = "🖼 Открыть в новом окне";
  const OPEN_CHROME_MENU_SELECTOR = '[role="menu"][data-cds="ContextMenu"]';
  const OPEN_CHROME_ITEM_SELECTOR = '[role="menuitem"]';
  const OPEN_CHROME_SEPARATOR_SELECTOR = '[role="separator"]';
  // Пункт Claude, рядом с которым наш уместен: имя зависит от системы.
  const OPEN_CHROME_FINDER_RE = /^(Show in Finder|Show in folder|Show in Explorer|Show in file manager|Показать в Finder|Показать в папке|Показать в Проводнике|Показать в файловом менеджере)$/i;
  const OPEN_CHROME_WAIT_MS = 1500;
  // Глубина обхода: предков DOM от цели клика и волокон вверх по `return`.
  const OPEN_CHROME_DEPTH = 12;
  const OPEN_CHROME_ERROR_MAX = 120;
  const OPEN_CHROME_NOTE_NO_CHAT = "Не знаю, какой это чат — открой через Finder";
  const OPEN_CHROME_NOTE_NO_BRIDGE = "Claude не даёт открыть файл";
  const openState = { pending: null, observer: null, timer: 0, inserted: 0, last: null, copies: 0, lastCopy: null };

  // Путь файла из пропсов карточки. Пропс `path` — абсолютный путь или
  // `computer://<путь>` (префикс снимается); `name` — имя файла, для плашки.
  // `page` — страница ли это (.html/.htm): мост открывает файл в программе ПО
  // УМОЛЧАНИЮ для его типа — у html это Chrome, а .md на Маке Элвиса уехал в
  // Xcode (гейт 17.09 05:20, два раза). Пункт «Открыть в Chrome» обещает именно
  // Chrome, поэтому у прочих файлов его нет; «Копировать в буфер» есть у всех.
  const OPEN_CHROME_FILE_RE = /\.html?$/i;
  // Путь файла из любой формы ссылки (WF277, #10644 — «Couldn't find this file» на папке с кириллицей и пробелом):
  // `file://` и `computer://` — адрес (хост localhost, ?запрос и #якорь снимаются), голый путь — как есть; %XX
  // раскрываются во всех формах (разметка ссылки кодирует кириллицу и пробелы: /Users/…/%D0%9F%D0%B0 a%20b.md).
  // Битая последовательность (имя «100% готово.md») остаётся буквами, целые рядом раскрываются.
  const filePathDecode = text => {
    if (!/%[0-9a-f]{2}/i.test(text)) return text;
    try { return decodeURIComponent(text); } catch {}
    return text.replace(/(?:%[0-9a-f]{2})+/gi, run => { try { return decodeURIComponent(run); } catch { return run; } });
  };
  const filePathFrom = raw => {
    let text = String(raw ?? "").trim();
    const scheme = /^(?:file|computer):\/\//i.exec(text);
    if (scheme) {
      text = text.slice(scheme[0].length).replace(/[?#].*$/s, "");
      if (/^localhost\//i.test(text)) text = text.slice("localhost".length);
    }
    return filePathDecode(text);
  };
  const openChromePathOf = props => {
    const raw = props?.path;
    if (typeof raw !== "string") return null;
    const path = filePathFrom(raw);
    if (!path.startsWith("/")) return null;
    return { path, name: typeof props.name === "string" ? props.name : "", page: OPEN_CHROME_FILE_RE.test(path) };
  };
  const openChromeFiber = node => {
    try {
      for (const key of Object.keys(node)) {
        if (key.startsWith("__reactFiber$")) return node[key];
      }
    } catch {}
    return null;
  };
  // От цели клика вверх по DOM (не дальше OPEN_CHROME_DEPTH предков), у первого
  // узла с волокном — вверх по `return` на ту же глубину: карточка файла —
  // это кнопка, а её пропсы лежат у компонента над ней.
  const openChromePath = target => {
    let node = target;
    for (let depth = 0; node && depth <= OPEN_CHROME_DEPTH; depth += 1, node = node.parentElement) {
      if (node.nodeType !== 1) continue;
      let fiber = openChromeFiber(node);
      for (let hop = 0; fiber && hop <= OPEN_CHROME_DEPTH; hop += 1, fiber = fiber.return) {
        const found = openChromePathOf(fiber.memoizedProps);
        if (found) return found;
      }
    }
    return null;
  };
  // Карточка файла без нажатия (#10531, Claude 3.1623): в чате на SendUserMessage (чат Рика) Claude рисует карточку
  // SendUserFile как div[title=<имя>] с opacity-70 — без onOpen, и клик по ней уходит полю ввода (Элвис 22.10 03:50:
  // «нажимаю… ничего не происходит… в поле ввода встаёт»). Путь — у волокна, как у кнопки; имя пропсов = title.
  const FILE_TILE_SELECTOR = "div.opacity-70[title]";
  const fileTilePath = node => {
    let found = null;
    try { found = openChromePath(node); } catch { found = null; }
    return found && found.name && found.name === node?.getAttribute?.("title") ? found : null;
  };

  const openChromeStop = () => {
    if (openState.observer) { try { openState.observer.disconnect(); } catch {} openState.observer = null; }
    if (openState.timer) { clearTimeout(openState.timer); openState.timer = 0; }
  };
  // Меню среди добавленных узлов: сам узел или его потомок.
  const openChromeMenuIn = node => {
    if (!node || node.nodeType !== 1) return null;
    try {
      if (node.matches(OPEN_CHROME_MENU_SELECTOR)) return node;
      return node.querySelector(OPEN_CHROME_MENU_SELECTOR);
    } catch { return null; }
  };
  // Свой пункт — клон «Show in Finder» без React-обработчиков (их у клона нет
  // по устройству), без id и без чужой подсветки; метка — чтобы второй раз в то
  // же меню не встать и чтобы dispose() снял.
  const openChromeItem = (finder, text, action) => {
    const item = finder.cloneNode(true);
    item.removeAttribute("id");
    for (const kid of item.querySelectorAll("[id]")) kid.removeAttribute("id");
    item.removeAttribute("data-highlighted");
    item.setAttribute(OPEN_CHROME_ATTRIBUTE, "");
    const label = [...item.querySelectorAll("span")]
      .find(span => OPEN_CHROME_FINDER_RE.test(String(span.textContent ?? "").trim())) ?? item;
    label.textContent = text;
    // «Жирненькая, выделенная» — слово Элвиса.
    item.style.setProperty("font-weight", "600");
    // Подсветку base-ui ставит атрибутом data-highlighted, а класс Claude
    // рисует по нему фон; нашему клону атрибут ставим сами.
    item.addEventListener("pointerenter", () => { try { item.setAttribute("data-highlighted", ""); } catch {} });
    item.addEventListener("pointerleave", () => { try { item.removeAttribute("data-highlighted"); } catch {} });
    item.addEventListener("click", event => {
      // Не всплывает в меню Claude: делегированные обработчики React живут у
      // корня, и клик по клону им не достаётся.
      try { event.stopPropagation(); } catch {}
      action();
    });
    return item;
  };
  // Свои пункты в меню Claude: «Открыть в Chrome» (только у страниц), под ним
  // «Копировать в буфер» (у всех) — порядок слова Элвиса («ещё ниже команду
  // скопировать»). Возвращает true, когда пункты встали; в меню без «Show in
  // Finder» (чужое меню) и в меню с уже стоящими пунктами — false.
  const openChromeInsert = (menu, found) => {
    if (!menu || !found) return false;
    if (menu.querySelector(`[${OPEN_CHROME_ATTRIBUTE}]`)) return false;
    const items = [...menu.querySelectorAll(OPEN_CHROME_ITEM_SELECTOR)];
    const finder = items.find(item => OPEN_CHROME_FINDER_RE.test(String(item.textContent ?? "").trim()));
    const list = finder?.parentNode;
    if (!list) return false;
    const first = list.firstElementChild;
    if (found.page) list.insertBefore(openChromeItem(finder, OPEN_CHROME_LABEL, () => {
      // Тем же путём, что клик по карточке (раздел 12д): приложение ведёт вкладку
      // и браузер; приложения нет — мост Claude, программа по умолчанию.
      // Меню закрывает ровно один Escape: лишний, при уже закрытом меню, оборвал
      // бы ответ Claude. На запасном пути его шлёт сам openChromeOpen.
      // `browser` (WF107): с К3 клик ведёт в галерею, а пункт обещает браузер —
      // приложение открывает браузер, минуя галерею (старое приложение — как click).
      htmlChromeAsk(found.path, "browser", openChromeClose);
    }), first);
    // «Посмотреть в окне чата» (WF107, К3) — у страниц и фото: страница — окном
    // приложения поверх монитора чата (`view`), фото — просмотр 12л этого окна.
    // Меню фото закрываем сразу: Escape после открытия закрыл бы и просмотр.
    if (mentionViewable(found.path)) list.insertBefore(openChromeItem(finder, VIEW_FILE_LABEL, () => {
      if (HTML_VIEW_PAGE_RE.test(found.path)) { htmlChromeAsk(found.path, "view", openChromeClose); return; }
      openChromeClose();
      viewOpen(found.path, null);
    }), first);
    list.insertBefore(openChromeItem(finder, COPY_FILE_LABEL, () => copyFileToClipboard(found)), first);
    // «🖼 Открыть в новом окне» (WF120, #7689) — у фото: тот же `click`, что клик
    // по карточке (fileClick): PimpViewer с листанием, без него — «Просмотр».
    // Меню закрывает ответ приложения (или мост на запасном пути) — ровно один
    // Escape; повтор того же файла за 3 с — ничего (защита click в htmlChromeAsk).
    // Панель материалов этого окна стоит (WF277) — сперва она закрывается: галерея одна на окно и панель, иначе фото
    // открылось бы в панели, а не окном (dockLeave, раздел 12п⁴).
    if (HTML_VIEW_PHOTO_RE.test(found.path)) list.insertBefore(openChromeItem(finder, OPEN_WINDOW_LABEL, () => {
      const ask = () => htmlChromeAsk(found.path, "click", openChromeClose, { frame: true });
      let left = false;
      try { left = dockLeave(ask); } catch { left = false; }
      if (!left) ask();
    }), first);
    const separator = menu.querySelector(OPEN_CHROME_SEPARATOR_SELECTOR);
    if (separator) {
      const line = separator.cloneNode(true);
      line.removeAttribute("id");
      line.setAttribute(OPEN_CHROME_ATTRIBUTE, "");
      list.insertBefore(line, first);
    }
    openState.inserted += 1;
    return true;
  };
  const openChromeWatch = found => {
    openChromeStop();
    if (typeof MutationObserver !== "function") return;
    const host = document.body ?? document.documentElement;
    if (!host) return;
    const observer = new MutationObserver(records => {
      for (const record of records) {
        for (const node of record.addedNodes ?? []) {
          const menu = openChromeMenuIn(node);
          if (menu && openChromeInsert(menu, found)) { openChromeStop(); return; }
        }
      }
    });
    observer.observe(host, { childList: true, subtree: true });
    openState.observer = observer;
    openState.timer = setTimeout(() => { openState.timer = 0; openChromeStop(); }, OPEN_CHROME_WAIT_MS);
  };
  const onOpenChromeMenu = event => {
    let found = null;
    try { found = openChromePath(event.target); } catch { found = null; }
    if (!found) { openChromeStop(); openState.pending = null; return; }
    openState.pending = { path: found.path, name: found.name, at: Date.now() };
    openChromeWatch(found);
  };

  // Меню закрывается Escape ПОСЛЕ вызова моста — так же его закрыл бы сам
  // Claude по своему пункту.
  const openChromeClose = () => {
    try { document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })); } catch {}
  };
  const openChromeFail = (path, error) => {
    const text = String(error?.message ?? error ?? "").slice(0, OPEN_CHROME_ERROR_MAX);
    openState.last = { path, ok: false, error: text };
    try { newWindowNote(text || OPEN_CHROME_NOTE_NO_BRIDGE); } catch {}
  };
  const openChromeOpen = path => {
    const chat = myChatId();
    if (!chat) {
      openState.last = { path, ok: false, error: "no-chat" };
      try { newWindowNote(OPEN_CHROME_NOTE_NO_CHAT); } catch {}
      openChromeClose();
      return;
    }
    let sessions = null;
    try { sessions = window["claude.web"]?.LocalSessions ?? null; } catch { sessions = null; }
    const bridge = sessions?.openSessionFileInDefaultApp;
    if (typeof bridge !== "function") {
      openState.last = { path, ok: false, error: "no-bridge" };
      try { newWindowNote(OPEN_CHROME_NOTE_NO_BRIDGE); } catch {}
      openChromeClose();
      return;
    }
    let result;
    try { result = bridge.call(sessions, chat, path); } catch (error) {
      openChromeFail(path, error);
      openChromeClose();
      return;
    }
    openChromeClose();
    // Мост отвечает промисом `{ok}`; ответ без промиса тоже разбираем.
    Promise.resolve(result).then(value => {
      if (value && value.ok === false) { openChromeFail(path, value.error ?? OPEN_CHROME_NOTE_NO_BRIDGE); return; }
      openState.last = { path, ok: true, error: "" };
    }, error => openChromeFail(path, error));
  };

  // «📋 Копировать в буфер» (WF69, #6236; WF106, #8102). Текстом в буфер уходит
  // ПУТЬ (вставка в терминал даёт путь, как после «Скопировать» в Finder; и запас,
  // когда приложения нет), а сам файл кладёт приложение: страница шлёт ему путь
  // по порту 47615 — `GET /copy-file?path=<путь>&chat=<id чата>` (id неизвестен —
  // запроса нет: приложение без chat ничего не делает). Приложение кладёт файл
  // (public.file-url + имена файлов + путь строкой) и говорит плашкой. До WF106
  // вместо запроса в HTML-слое лежала метка `<!--pimpmyclaude:copy-file:…-->`, и
  // приложение ЧИТАЛО буфер, а macOS 26 на чтение спрашивает разрешение — отказ
  // или закрытый вопрос оставляли в буфере путь (слово Элвиса 29.09). Метки
  // больше нет. Ответ CORS: дошёл запрос — и хорошо.
  //
  // Кладёт execCommand("copy") со своим обработчиком copy: он есть в любом
  // Chromium, разрешений не спрашивает, работает синхронно по клику (клик по
  // пункту — жест человека). navigator.clipboard.write — асинхронный и с
  // разрешением clipboard-sanitized-write, которое Claude может и не дать.
  const COPY_FILE_NOTE_FAIL = "Не смог положить файл в буфер";
  const copyFileUrl = (path, chat) => (typeof chat === "string" && chat
    ? `http://127.0.0.1:${HTML_CHROME_PORT}/copy-file?path=${encodeURIComponent(path)}&chat=${encodeURIComponent(chat)}`
    : null);
  const copyFileToClipboard = found => {
    const path = String(found?.path ?? "");
    const good = path.startsWith("/");
    let filled = false;
    let done = false;
    if (good) {
      const onCopy = event => {
        try {
          event.clipboardData.setData("text/plain", path);
          event.preventDefault();
          // Дальше событие не идёт: обработчики copy самого Claude (у корня
          // React) могли бы переписать слои поверх наших.
          event.stopImmediatePropagation();
          filled = true;
        } catch {}
      };
      // На захвате: наш обработчик первый и единственный.
      try { document.addEventListener("copy", onCopy, true); } catch {}
      try { done = document.execCommand("copy") !== false; } catch { done = false; }
      try { document.removeEventListener("copy", onCopy, true); } catch {}
    }
    const ok = good && filled && done;
    if (ok) openState.copies += 1;
    openState.lastCopy = { path, ok };
    if (!ok) { try { newWindowNote(COPY_FILE_NOTE_FAIL); } catch {} }
    // Файл — приложению: и когда текст в буфер не лёг, файл оно положит само.
    if (good && typeof fetch === "function") {
      let chat = null;
      try { chat = myChatId(); } catch { chat = null; }
      const url = copyFileUrl(path, chat);
      if (url) { try { fetch(url, { mode: "cors", credentials: "omit", cache: "no-store" }).catch(() => {}); } catch {} }
    }
    openChromeClose();
    return ok;
  };
  // Снятие экземпляра: наблюдатель, таймер и уже вставленные пункты (меню
  // Claude живёт своей жизнью, но наш узел в нём — наш).
  track(() => {
    openChromeStop();
    try { for (const node of document.querySelectorAll(`[${OPEN_CHROME_ATTRIBUTE}]`)) node.remove(); } catch {}
  });
  statusPart("openInChrome", () => ({
    pending: Boolean(openState.observer),
    path: openState.pending?.path ?? null,
    inserted: openState.inserted,
    last: openState.last,
    // «Копировать в буфер» (WF69): сколько раз положили и чем кончился последний.
    copies: openState.copies,
    lastCopy: openState.lastCopy,
  }));
  HATCH && Object.assign(HATCH, { openChromePath, openChromeInsert, openChromeOpen, copyFileUrl, copyFileToClipboard, filePathFrom });

