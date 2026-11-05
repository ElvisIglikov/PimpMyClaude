  // ---- 2е. Папка проекта у закреплённых чатов (#7102, WF82) ----------------
  // Слово Элвиса 22.09: у закреплённых «непонятно, к кому относится… папку в
  // начале имени, как в шапке». Список Recents в Claude Code разбит по проектам,
  // а Pinned — плоский. Имя берём там же, откуда его берёт шапка: у строки в
  // React-волокне лежит сессия (roamSession, раздел 12е), в ней source.data —
  // имя репозитория (repoInfo.name, его и показывает чип шапки) и папка (cwd).
  // Нет ни того, ни другого — чипа нет.
  //
  // Рисует CSS (правило в разделе 4): атрибут на подписи строки и ::before с
  // attr(). Текст строки не трогаем: первую строку innerText читают
  // переименование и сверка заголовка «Нового окна» (newWindowRowTitle) и обход
  // 12е, а сгенерированный ::before в innerText не попадает. Подпись React
  // пересоздаёт — атрибут ставится заново в каждом проходе раскладки (раздел 9),
  // своего наблюдателя и таймера у раздела нет.
  const PINNED_FOLDER_ATTRIBUTE = "data-myclaude-folder";
  const PINNED_LABEL_SELECTOR = "[data-row-label] > .dframe-fade-label";
  const PINNED_FOLDER_MAX = 80;
  // Настройка «Закреплённые» (#8743, слово Элвиса 04.10: «настройку, чтобы эти
  // штучки можно было отключить… название проекта и таймер»): команда
  // `pinned-look` {folder: true|false} всем окнам; в localStorage
  // лежит только «выключено» — нет ключа значит показывать, как было до настройки.
  // Выключенный чип снимает тот же проход раскладки, что ставит. Часиков у закреплённых с
  // page-64 нет (см. ниже): поле clock команды принимается и ничего не меняет.
  const PINNED_OFF_KEYS = { folder: "myclaude.pinnedFolderOff" };
  const pinnedShows = part => {
    try { return localStorage.getItem(PINNED_OFF_KEYS[part]) !== "1"; } catch { return true; }
  };
  const pinnedFolderName = (row, id) => {
    const data = roamSession(row, id)?.source?.data;
    const repo = typeof data?.repoInfo?.name === "string" ? data.repoInfo.name.trim() : "";
    return (repo || newWindowFolderName(typeof data?.cwd === "string" ? data.cwd : "")).slice(0, PINNED_FOLDER_MAX);
  };
  // Цвет плашки проекта у закреплённых (#7213) и у заголовков групп проектов (#7244) снят словом
  // Элвиса 11.10 01:40: «названия проектов не надо цветом выводить… сделай маленькими… чтоб они
  // оставались, но были маленькими, не мешались» — имя папки без цвета и плашки, мелко и тихо
  // (правило раздела 4); заголовки групп — как у Claude.
  const markPinnedFolders = () => {
    if (!isMainWindow()) return;
    const shown = pinnedShows("folder");
    for (const row of document.querySelectorAll(`${NEW_WINDOW_PINNED_SELECTOR} [data-row-key^="code:local_"]`)) {
      const label = row.querySelector(PINNED_LABEL_SELECTOR);
      if (!label) continue;
      const id = String(row.getAttribute("data-row-key") ?? "").split(":").pop() ?? "";
      const name = shown ? pinnedFolderName(row, id) : "";
      if (name) {
        if (label.getAttribute(PINNED_FOLDER_ATTRIBUTE) !== name) label.setAttribute(PINNED_FOLDER_ATTRIBUTE, name);
      } else if (label.hasAttribute(PINNED_FOLDER_ATTRIBUTE)) label.removeAttribute(PINNED_FOLDER_ATTRIBUTE);
    }
  };
  track(() => {
    for (const node of document.querySelectorAll(`[${PINNED_FOLDER_ATTRIBUTE}]`)) node.removeAttribute(PINNED_FOLDER_ATTRIBUTE);
  });
  // Часики кеша у закреплённых (#7912, WF102: «60:00 → 0:00» левее чипа папки) сняты целиком — слово
  // Элвиса 11.10 01:40: «отключи вот этот таймер… таймеры убери, это уже неактуальная тема». Узла у них
  // не было: метки на подписи строки и правила раздела 4; метки и ключ настройки прошлой страницы
  // убирает раздел 3. Отсчёт часа остался одному углу «Проект · чат» (раздел 2ж): его и считают.
  const PINNED_CLOCK_ATTRIBUTE = "data-myclaude-clock";
  const PINNED_CLOCK_LATE_ATTRIBUTE = "data-myclaude-clock-late";
  const PINNED_CLOCK_OFF_KEY = "myclaude.pinnedClockOff";
  const PINNED_CLOCK_HOUR_MS = 3600000;
  // Остаток часа в секундах → «59:07».
  const pinnedClockText = left => `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}`;
  // Поле folder команды — true|false (булево или строкой); поля нет или оно другое — ничего
  // не меняется. Ответ виден сразу, не дожидаясь прохода раскладки.
  const runPinnedLookCommand = detail => {
    for (const part of Object.keys(PINNED_OFF_KEYS)) {
      const value = String(detail?.[part]);
      if (value !== "true" && value !== "false") continue;
      try {
        if (value === "true") localStorage.removeItem(PINNED_OFF_KEYS[part]);
        else localStorage.setItem(PINNED_OFF_KEYS[part], "1");
      } catch {}
    }
    try { markPinnedFolders(); } catch {}
  };
  // Секундный тик ведёт часики угла (раздел 2ж, #7943): markCornerClock объявлен
  // ниже, но зовётся только из таймера — к тому времени он уже есть.
  const pinnedClockTimer = setInterval(() => {
    try { markCornerClock(); } catch {}
    // Края прокрутки живого вида (WF185): лента выросла без прокрутки — нижнее затухание.
    try { scrollFadeScan(); } catch {}
  }, 1000);
  track(() => clearInterval(pinnedClockTimer));
  // «Закреплённые» (#8743, раздел 2е): показывается ли имя папки (часиков с page-64 нет).
  statusPart("pinnedLook", () => ({ folder: pinnedShows("folder") }));

