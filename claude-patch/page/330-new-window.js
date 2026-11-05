  // ---- 12б. «Новое окно» и «В отдельное окно» -----------------------------
  // Пункт меню «🪟 Новое окно»: новый чат Claude Code сразу отдельным окном.
  // Одним вызовом это не делается — окно-попап живёт поверх СУЩЕСТВУЮЩЕЙ сессии,
  // а локальная сессия рождается только на первом сообщении (свежий local_<uuid>
  // даёт «This session couldn't be found»). Поэтому порядок ровно тот, что Элвис
  // проходит руками: ⌘N → «Привет» → отправка → вынести получившийся чат в окно
  // → вернуть главное окно на прежний разговор.
  //
  // Само окно открывает не страница, а приложение claude.ai: у него есть стор с
  // действием openPopout({type:"code-session", sessionId, …}) — тот же, что за
  // пунктом «Open in new window» и за ⌘-кликом по строке чата в сайдбаре. Стор
  // ищем ПОВЕДЕНЧЕСКИ (по наличию popoutWindows и openPopout), а не по имени
  // экспорта: имена чанков и экспортов claude.ai меняются каждый релиз.
  //
  // Второй пункт, «🪟 В отдельное окно» (команда popout-window), — последний шаг
  // того же пути в отдельности: вынести ТЕКУЩИЙ чат. Он же честная деградация:
  // не сложилось у «Нового окна» уже после создания чата — плашка зовёт его.
  //
  // ⌘N жмёт Swift штатной клавишей: синтетический KeyboardEvent на document
  // Claude не слышит вовсе (проверено 04.09), поэтому страница только ЖДЁТ.
  const NEW_WINDOW_NOTE_ID = "myclaude-new-window-note";
  const NEW_WINDOW_HOME_PATH = "/epitaxy";
  const NEW_WINDOW_INPUT_SELECTOR = '[data-testid="code-prompt-input"]';
  const NEW_WINDOW_SEND_SELECTOR = '[data-testid="code-prompt-send"]';
  const NEW_WINDOW_ROWS_SELECTOR = '[data-testid="sidebar-recents"]';
  const NEW_WINDOW_PINNED_SELECTOR = '[data-testid="sidebar-pinned"]';
  // Шаг опроса: смену адреса роутер делает без события, ловить её нечем.
  const NEW_WINDOW_POLL_MS = 100;
  // Сколько ждём домашний экран после ⌘N от приложения.
  const NEW_WINDOW_HOME_MS = 5000;
  // Кнопка отправки бывает disabled, пока не выбраны папка и модель.
  const NEW_WINDOW_SEND_MS = 3000;
  // Сессия заводится не мгновенно: адрес становится /epitaxy/local_<uuid>.
  const NEW_WINDOW_SESSION_MS = 15000;
  // Строка сайдбара появляется, когда сессия уже создана; её имя уходит в окно.
  const NEW_WINDOW_ROW_MS = 20000;
  // Строки так и нет — даём ей последний вздох и идём дальше без имени.
  const NEW_WINDOW_ROW_GRACE_MS = 1500;
  // Возврат главного окна на прежний чат — на каждый путь (строка, история, роутер). Секунды не
  // хватало (#5721): навигация, доехавшая позже, ловила следующий путь уже в пути, и окно оставалось
  // на чужом чате. Тем же сроком «В отдельное окно» ждёт чат, открытый строкой сайдбара.
  const NEW_WINDOW_BACK_MS = 2500;
  // «Чат в главное окно» (WF108) ждёт открытия названного чата прежние 3 с.
  const NEW_WINDOW_MAIN_CHAT_MS = 3000;
  // Папка проекта (WF16): сколько ждём, пока выбор дойдёт до стора, а потом до
  // чипа на домашнем экране.
  const NEW_WINDOW_FOLDER_MS = 5000;
  // Переименование чата (WF16): контекстное меню строки, поле имени, закрытие.
  const NEW_WINDOW_MENU_MS = 1500;
  const NEW_WINDOW_RENAME_MS = 2000;
  // Сколько ждём, пока новое имя доедет до строки сайдбара (критик WF16, В3).
  const NEW_WINDOW_TITLE_MS = 2000;
  // Страховка: сорвавшийся прогон не должен выключить кнопку навсегда.
  // С WF16 к цепочке добавились папка (до 10 с) и имя (до 7,5 с).
  // Худшая цепочка ожиданий ≈ 65 с (verify WF13, находка 2) плюс К2 (#7072):
  // модель с «More models» и сверкой ≈ 4,5 с, эффорт ≈ 4 с, запись передачи 3 с.
  // WF102 (#7905): ожидание диалога доверия (до 20 + 3 + 15 с) в запас не
  // вписано — авто-Trust жмёт за секунду; от этого числа считает сроки Swift
  // (ClaudeActions.cashoutWaitSeconds), менять — вместе с ним.
  const NEW_WINDOW_GUARD_MS = 110000;
  const NEW_WINDOW_NOTE_MS = 3000;
  const NEW_WINDOW_NOTE_FAIL = "Новое окно не открылось";
  // Меню «⋯ Ещё ▸ 🪟 Вынести этот чат в окно» снято (WF248 П2, лист 48 · 2.1) — плашка зовёт к пути самого
  // Claude: ⌘-клик по строке чата в списке слева (тот же openPopout, что у шага 7).
  const NEW_WINDOW_NOTE_CREATED = "Отдельным окном не вышло, чат создан здесь.\n⌘-клик по нему в списке слева — откроется окном";
  const NEW_WINDOW_NOTE_DRAFT = "В поле ввода черновик — новый чат не открываю";
  const NEW_WINDOW_NOTE_FOLDER = "Сообщение не ушло: не выбрана папка";
  // Папку выбрать не вышло (макет WF16): чат в чужой папке хуже отказа — там
  // работает авто-Allow, и агент стартовал бы в чужом проекте.
  const NEW_WINDOW_NOTE_FOLDER_PICK = "Не смог выбрать папку — чат не создавал";
  const NEW_WINDOW_NOTE_CHAT = "Сначала открой чат — выносить нечего";
  const NEW_WINDOW_NOTE_POPOUT = "Отдельным окном не вышло";
  // Пункт нажали в самом окне-попапе: этот чат уже вынесен, выносить его некуда.
  // Раньше команда там тихо умирала (слово Элвиса 05.09: «ничего не произошло»).
  const NEW_WINDOW_NOTE_ALREADY = "Этот чат уже в отдельном окне";
  // Пункт нажали ещё раз, пока первый идёт (#7772): второго окна нет, а что
  // работа идёт — видно переливом букв.
  const NEW_WINDOW_NOTE_BUSY = "⏳ Уже открываю окно…";
  // Пункт «Переименовать» ищем по началу текста: у claude.ai он английский, но
  // сборка бывает и русской.
  const NEW_WINDOW_RENAME_RE = /^(rename|переимен)/i;
  const NEW_WINDOW_MENU_SELECTOR = '[role="menuitem"], [role="menu"] button, [role="menu"] [role="button"]';
  // Чип папки на домашнем экране («Local / <папка> / <ветка>»): своего селектора
  // у него мы не снимали, узнаём по тексту среди кнопок и списков.
  const NEW_WINDOW_CHIP_SELECTOR = 'button, [role="button"], [role="combobox"]';
  // Поле имени у переименования: модалка, инлайн-поле строки или contenteditable.
  const NEW_WINDOW_NAME_SELECTOR = 'input[type="text"], input:not([type]), textarea, [contenteditable="true"]';

  // Все таймеры раздела — в одном наборе: снимаются разом на dispose, а реестр
  // уборки не пухнет от сотен опросов по 100 мс.
  const newWindowTimers = new Set();
  const newWindowLater = (fn, ms) => {
    const timer = setTimeout(() => { newWindowTimers.delete(timer); fn(); }, ms);
    newWindowTimers.add(timer);
    return timer;
  };
  const newWindowClearTimers = () => {
    for (const timer of newWindowTimers) { try { clearTimeout(timer); } catch {} }
    newWindowTimers.clear();
  };
  // У каждого запуска свой номер. Живой inject.js перечитывается по mtime, и
  // `cp` посреди работы кнопки поднял бы второй экземпляр: старая цепочка ждёт
  // адреса ещё десятки секунд и открыла бы ВТОРОЕ окно. Номер и state.alive
  // проверяет каждый шаг.
  let newWindowToken = 0;
  const newWindowLive = token => state.alive && token === newWindowToken;
  const newWindowMark = patch => {
    state.newWindow = { ...(state.newWindow ?? {}), ...patch, at: Date.now() };
  };
  const newWindowRuns = () => (Number(state.newWindow?.runs) || 0) + 1;
  const newWindowError = error => String(error?.message ?? error).slice(0, 200);

  // Плашка отказа. Молчать нельзя: со стороны пункт меню выглядит сломанным
  // (прецедент MenuModel.workflowKitMissingAlert). Стиль — подсказки полосы
  // прогресса (раздел 2б), слой на единицу ниже неё: подсказка Элвиса важнее.
  let newWindowNoteNode = null;
  let newWindowNoteTimer = 0;
  const newWindowNoteHide = drop => {
    if (newWindowNoteTimer) {
      clearTimeout(newWindowNoteTimer);
      newWindowTimers.delete(newWindowNoteTimer);
      newWindowNoteTimer = 0;
    }
    if (!newWindowNoteNode) return;
    if (drop) { try { newWindowNoteNode.remove(); } catch {} newWindowNoteNode = null; return; }
    newWindowNoteNode.style.setProperty("display", "none");
  };
  const newWindowNote = (text, busy = false, ms = NEW_WINDOW_NOTE_MS) => {
    if (!text) return;
    newWindowNoteHide(false);
    if (!newWindowNoteNode) {
      const node = document.createElement("div");
      node.id = NEW_WINDOW_NOTE_ID;
      node.setAttribute("aria-hidden", "true");
      // Стили прямо в узел, без <style>: CSP страницы может не пустить нашу
      // таблицу, а element.style ей неподвластен (довод раздела 2б).
      for (const [name, value] of Object.entries({
        // width max-content: у блока с left 50% ширина по содержимому иначе
        // упирается в половину окна (z2-r06), в узком окне текст рвётся.
        position: "fixed", display: "none", width: "max-content", "max-width": "min(420px, calc(100vw - 24px))",
        padding: "8px 10px", "border-radius": "8px", "border-width": "1px", "border-style": "solid",
        font: "12px/1.45 -apple-system, system-ui, sans-serif", "white-space": "pre-line",
        "pointer-events": "none", "z-index": "2147483644",
        left: "50%", transform: "translateX(-50%)", bottom: "96px",
      })) node.style.setProperty(name, value);
      (document.body ?? document.documentElement).appendChild(node);
      newWindowNoteNode = node;
    }
    // Только textContent: текст свой, но разметке в плашке делать нечего.
    // Подпись ожидания — во внутреннем узле с переливом (#7772): таблица
    // страницы не встала — просто текст.
    newWindowNoteNode.textContent = "";
    if (busy) {
      const span = document.createElement("span");
      span.setAttribute(BUSY_ATTRIBUTE, "1");
      span.textContent = text;
      newWindowNoteNode.appendChild(span);
    } else newWindowNoteNode.textContent = text;
    for (const [name, value] of Object.entries(progressDark()
      ? { background: "#12151c", color: "#e7e9f0", "border-color": "#2a2f3a", "box-shadow": "0 8px 24px rgba(0,0,0,.45)" }
      : { background: "#ffffff", color: "#14181f", "border-color": "#d7dbe3", "box-shadow": "0 8px 24px rgba(15,20,30,.18)" })) {
      newWindowNoteNode.style.setProperty(name, value);
    }
    newWindowNoteNode.style.setProperty("display", "block");
    newWindowNoteTimer = newWindowLater(() => { newWindowNoteTimer = 0; newWindowNoteHide(false); }, ms);
  };
  // Экземпляр уходит — с ним уходят таймеры, плашка и признак занятости: иначе
  // `cp inject.js` посреди работы оставил бы кнопку «занятой» навсегда.
  track(() => {
    newWindowClearTimers();
    newWindowNoteHide(true);
    if (state.newWindow) state.newWindow.busy = false;
  });

  // Ожидание опросом: вернёт найденное или null, когда время вышло либо
  // экземпляр сменился.
  const newWindowWait = (check, limitMs, token) => new Promise(resolve => {
    const deadline = now() + limitMs;
    const tick = () => {
      if (!newWindowLive(token)) { resolve(null); return; }
      let hit = null;
      try { hit = check(); } catch { hit = null; }
      if (hit) { resolve(hit); return; }
      if (now() >= deadline) { resolve(null); return; }
      newWindowLater(tick, NEW_WINDOW_POLL_MS);
    };
    tick();
  });
  const newWindowSleep = ms => new Promise(resolve => { newWindowLater(resolve, ms); });

  // Диалог «Trust this workspace?» (#7905, WF102). Встаёт на отправке первого
  // сообщения в папке, которой Claude ещё не доверял, и закрывает собой отправку:
  // до WF102 цепочка жала Enter вхолостую и через 15 с отказывала no-send/no-folder
  // (живьём 26.09: PimpViewer — ни с одной из пяти попыток). Теперь ждём, пока
  // диалог уйдёт (жмёт авто-Trust — раздел 12е, вне выключателя Авто-Allow; папка
  // вне корня автодоверия — жмёт человек по плашке), и шлём заново. Не ушёл за
  // NEW_WINDOW_TRUST_MS — прежний отказ, новых исходов нет (C2 плана WF102);
  // state.newWindow.trust: "waited" | "timeout" | null (диалога не было).
  const NEW_WINDOW_TRUST_MS = 20000;
  const NEW_WINDOW_NOTE_TRUST = "Нажми Trust workspace";
  const newWindowTrustShown = () => {
    try {
      for (const button of document.querySelectorAll("button")) {
        if (!AUTO_TRUST_BUTTON.test(autoAllowLabel(button.textContent))) continue;
        const box = button.getBoundingClientRect();
        if (box.width > 0 && box.height > 0) return true;
      }
    } catch {}
    return false;
  };
  // true — диалога нет или он ушёл; false — не ушёл за срок (или экземпляр сменился).
  const newWindowTrustPass = async token => {
    if (!newWindowTrustShown()) return true;
    newWindowMark({ trust: "wait" });
    newWindowNote(NEW_WINDOW_NOTE_TRUST, true, NEW_WINDOW_TRUST_MS);
    const gone = await newWindowWait(() => (newWindowTrustShown() ? null : true), NEW_WINDOW_TRUST_MS, token);
    if (!newWindowLive(token)) return false;
    newWindowNoteHide(false);
    newWindowMark({ trust: gone ? "waited" : "timeout" });
    return Boolean(gone);
  };

  // Объявления, а не стрелки в `const`: обе функции нужны ключу темы по id чата
  // (chatIdKey, раздел 2а) уже на инжекте, а он стоит ВЫШЕ по файлу — `const` к
  // тому мгновению ещё в TDZ, а объявление поднимается (WF35).
  function newWindowSegment(path) { return String(path ?? "").split("/").filter(Boolean).pop() ?? ""; }
  // Открытый чат Claude Code — /epitaxy/local_<uuid>. Всё прочее (обычный чат
  // claude.ai, домашний экран) сессии popout не даёт.
  function newWindowSessionId() {
    const id = newWindowSegment(location.pathname);
    return id.startsWith("local_") ? id : "";
  }
  const newWindowAtHome = () =>
    location.pathname === NEW_WINDOW_HOME_PATH && Boolean(document.querySelector(NEW_WINDOW_INPUT_SELECTOR));
  // Ключи строк сайдбара — chat:<uuid> / code:… / local_…, поэтому ищем по концу.
  // Значение внутри кавычек селектора экранируем сами: CSS.escape пишет по
  // правилам идентификатора и в строке в кавычках только испортил бы ключ.
  // Закреплённые чаты живут не в списке недавних, а в разделе Pinned (разведка
  // WF82, 2.2553.13), а у сайдбара бывают и другие группы. Второй аргумент
  // true — строка из ЛЮБОЙ группы, видимая первой (обход чатов 12е и с #7113
  // возврат и вынос этого раздела): без него главное окно из закреплённого
  // чата оставалось на новом. Без него — только недавние, как прежде.
  const newWindowRow = (id, any = false) => {
    if (!id) return null;
    try {
      const key = String(id).replace(/["\\]/g, "\\$&");
      if (!any) return document.querySelector(`${NEW_WINDOW_ROWS_SELECTOR} [data-row-key$="${key}"]`);
      const rows = [...document.querySelectorAll(`[data-row-key$="${key}"]`)];
      return rows.find(newWindowRowShown) ?? rows[0] ?? null;
    } catch { return null; }
  };
  const newWindowRowShown = row => {
    try {
      const box = row.getBoundingClientRect();
      return box.width > 0 && box.height > 0;
    } catch { return false; }
  };
  // Нажатие по строке — кнопкой перехода [data-row-main-button] (2.2553.13,
  // разведка WF82): первый «a,button» строки бывает кнопкой «…».
  const newWindowRowClick = row => {
    try { (row.querySelector("[data-row-main-button]") ?? row.querySelector("a,button") ?? row).click(); } catch {}
  };
  // Метка истории на старте цепочки: ключ записи Navigation API и длина.
  // Шаги по history.length не считаются, когда Chromium упёрся в потолок 50
  // записей (#7113, замер WF82): после перехода длина не растёт. Ключ ведёт
  // ровно в прежнюю запись; без API — прежний счёт по длине.
  const navEntryKey = () => {
    try { return String(window.navigation?.currentEntry?.key ?? ""); } catch { return ""; }
  };
  const navMark = () => ({ key: navEntryKey(), length: history.length });
  const navBackTo = mark => {
    let nav = null;
    try { nav = window.navigation?.currentEntry ? window.navigation : null; } catch { nav = null; }
    if (nav) {
      const key = mark?.key;
      try {
        if (!key || nav.currentEntry.key === key || !nav.entries().some(entry => entry?.key === key)) return false;
        const run = nav.traverseTo(key);
        // Отказ Navigation API приходит промисом, а не броском: глушим, чтобы не сорить в консоль.
        run?.committed?.catch?.(() => {});
        run?.finished?.catch?.(() => {});
        return true;
      } catch { return false; }
    }
    const steps = history.length - (mark?.length ?? history.length);
    // history.go(0) — это перезагрузка страницы, а не шаг назад.
    if (steps <= 0) return false;
    try { history.go(-steps); } catch { return false; }
    return true;
  };
  const newWindowRowTitle = row => {
    const raw = String(row?.innerText ?? row?.textContent ?? "").trim();
    return (raw.split("\n").map(line => line.trim()).find(Boolean) ?? "").slice(0, 200);
  };

  // Стор ищем ТОЛЬКО по приходу команды и останавливаемся на первом совпадении:
  // import() исполняет те модули, которые страница ещё не выполняла (preload —
  // не исполнение), а это чужая инициализация в чужой странице. Найденное — в
  // кэш замыкания; кэш перепроверяем, вдруг стор пересобрали.
  let newWindowStore = null;
  const newWindowStoreOk = store => {
    try {
      const value = store?.getState?.();
      return Boolean(value && value.popoutWindows instanceof Map && typeof value.openPopout === "function");
    } catch { return false; }
  };
  const newWindowModuleUrls = () => {
    const urls = [];
    const seen = new Set();
    const add = href => {
      const url = typeof href === "string" ? href : "";
      if (!url || seen.has(url)) return;
      seen.add(url);
      urls.push(url);
    };
    try { for (const link of document.querySelectorAll('link[rel="modulepreload"]')) add(link.href); } catch {}
    // Запасной источник адресов: ссылок modulepreload в окне может не оказаться.
    try {
      for (const entry of performance.getEntriesByType("resource")) {
        const name = String(entry?.name ?? "");
        if (/\/assets\/v1\/[^?#]*\.js(\?|#|$)/.test(name)) add(name);
      }
    } catch {}
    return urls;
  };
  // Сиденье импортёра модулей. В бою — тот же самый import(), байт в байт; в
  // стенде тестов его подменяют через люк (setModuleImporter). Иначе скан в
  // тестах не проверить вовсе: tests/load.mjs гоняет файл через
  // vm.runInContext БЕЗ опции importModuleDynamically, живой import() там
  // бросает ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING, а бросок молча съедает
  // catch на каждый адрес — скан не нашёл бы ничего никогда и «импортов ровно
  // столько же» считать было бы нечем (план WF29, решение 4).
  let moduleImporter = url => import(url);
  const setModuleImporter = fn => { moduleImporter = typeof fn === "function" ? fn : url => import(url); };
  // Обход модулей общий на оба стора раздела (попапы и папка проекта): проход
  // один и тот же, разный только предикат.
  const newWindowScanStores = async (token, ok) => {
    for (const url of newWindowModuleUrls()) {
      if (!newWindowLive(token)) return null;
      let chunk = null;
      // Каждый import в своём try: чужой модуль вправе упасть на исполнении.
      try { chunk = await moduleImporter(url); } catch { continue; }
      try {
        for (const key of Object.keys(chunk)) {
          const value = chunk[key];
          if (typeof value !== "function" || typeof value.getState !== "function") continue;
          if (ok(value)) return value;
        }
      } catch {}
    }
    return null;
  };
  const newWindowFindStore = async token => {
    if (newWindowStoreOk(newWindowStore)) return newWindowStore;
    newWindowStore = await newWindowScanStores(token, newWindowStoreOk);
    return newWindowStore;
  };

  // Папка проекта (WF16, ступень b). Домашний экран /epitaxy держит выбранную
  // папку в СВОЁМ сторе (разведка П2, снято живьём 04.09): состояние с полями
  // selectedFolder и trustedSelectedFolder, действия setLocalSelectedFolder(path)
  // и setTrustedSelectedFolder(path). Имя экспорта у него своё («Zt» в сборке
  // 04.09) и меняется с каждым релизом — ищем ПОВЕДЕНЧЕСКИ, как и стор попапов,
  // и держим в кэше замыкания с перепроверкой.
  //
  // Доверие ставим сразу вторым вызовом: setLocalSelectedFolder обнуляет
  // trustedSelectedFolder, и без него Claude поднял бы модальное окно доверия к
  // папке, на котором вся цепочка встала бы (разведка WF16, п. 6). Папки в меню
  // — только те, где сессии уже были, то есть доверенные.
  let newWindowFolderStore = null;
  const newWindowFolderStoreOk = store => {
    try {
      const value = store?.getState?.();
      return Boolean(value && typeof value === "object"
        && typeof value.setLocalSelectedFolder === "function"
        && "selectedFolder" in value);
    } catch { return false; }
  };
  const newWindowFindFolderStore = async token => {
    if (newWindowFolderStoreOk(newWindowFolderStore)) return newWindowFolderStore;
    // Присваиваем только находку: прерванный по токену скан отдаёт null, и он не
    // должен затирать стор, который тем временем нашла цепочка «Нового окна»
    // (сканеров с WF37 два — проверка WF37, находка 1).
    const found = await newWindowScanStores(token, newWindowFolderStoreOk);
    if (found) newWindowFolderStore = found;
    return newWindowFolderStore;
  };
  // Хвостовой слэш путь не меняет: «…/Dictatorik» и «…/Dictatorik/» — одна папка.
  const newWindowFolderPath = value => {
    let path = typeof value === "string" ? value.trim() : "";
    while (path.length > 1 && path.endsWith("/")) path = path.slice(0, -1);
    return path;
  };
  const newWindowFolderName = path => newWindowFolderPath(path).split("/").filter(Boolean).pop() ?? "";
  const newWindowFolderNow = store => {
    try { return newWindowFolderPath(store?.getState?.()?.selectedFolder); } catch { return ""; }
  };
  // Чип папки виден на домашнем экране, и по нему проверяется, что стор мы нашли
  // ТОТ: своего селектора у чипа нет, поэтому узнаём его по тексту — имени папки.
  const newWindowChipShows = name => {
    if (!name) return false;
    try {
      for (const node of document.querySelectorAll(NEW_WINDOW_CHIP_SELECTOR)) {
        if (String(node.textContent ?? "").replace(/\s+/g, " ").trim() === name) return true;
      }
    } catch {}
    return false;
  };
  // Шаг «папка»: поставить папку проекта и СВЕРИТЬ обратно. Отдаёт "ok",
  // "no-folder-ui" (нечем выбирать — стора нет) или "folder-missing" (выбор не
  // встал). Правда одна — значение в сторе: он и есть то, с чем Claude заведёт
  // сессию. Чип на экране — только пометка (WF36, #5544): его текст рисуется
  // своим тактом и на глазах Элвиса отставал, а шаг из-за этого откатывался
  // целиком. Чип спрашиваем там, где он нашёлся до переключения (с прежней
  // папкой), и кладём в state.newWindow.chip: "ok" (сменился), "stale" (стор
  // принял, а чип не догнал), "none" (чипа не видно вовсе). Сравнение остаётся
  // ТОЧНЫМ: по префиксу «Dictator» совпал бы с «Dictatorik» — ложное ok.
  const newWindowPickFolder = async (folder, token) => {
    const store = await newWindowFindFolderStore(token);
    if (!newWindowLive(token) || !store) return "no-folder-ui";
    const want = newWindowFolderPath(folder);
    const before = newWindowFolderNow(store);
    const chipBefore = before !== "" && newWindowChipShows(newWindowFolderName(before));
    try {
      const actions = store.getState();
      actions.setLocalSelectedFolder(folder);
      if (typeof actions.setTrustedSelectedFolder === "function") actions.setTrustedSelectedFolder(folder);
    } catch { return "folder-missing"; }
    const picked = await newWindowWait(
      () => (newWindowFolderNow(store) === want ? true : null), NEW_WINDOW_FOLDER_MS, token);
    if (!newWindowLive(token) || !picked) return "folder-missing";
    if (!chipBefore) { newWindowMark({ chip: "none" }); return "ok"; }
    const chip = await newWindowWait(
      () => (newWindowChipShows(newWindowFolderName(want)) ? true : null), NEW_WINDOW_FOLDER_MS, token);
    if (!newWindowLive(token)) return "folder-missing";
    newWindowMark({ chip: chip ? "ok" : "stale" });
    return "ok";
  };

  // Модель и эффорт нового чата (К2, #7072; спайк S0 на 2.2553.13). Кнопка
  // модели — [data-testid=epitaxy-cds-model-selector], aria-label «Model: Opus
  // 5.5», меню открывается только «как мышью» (pointerdown/mousedown с buttons:1
  // … click; голый .click() не открывает). Пункты [role^=menuitem]: подпись
  // модели, к которой ПРИКЛЕЕНА цифра клавиши («Fable 5.12» — это «Fable 5.1» и
  // клавиша 2; у текущей цифры нет). Сверка ЦЕЛИКОМ после срезания одной цифры:
  // по префиксу «Opus 5» совпал бы с «Opus 5.5». Не нашли наверху — «More
  // models». Эффорт — кнопка «Effort: High» с диалогом-ползунком, ступень — по
  // aria-valuetext, двигаем стрелками. Ставятся до первого сообщения.
  // #10261: с Claude 2.42304 кнопки «Effort:» нет — ступень хвостом у кнопки модели («Model: Opus 5.5 High»),
  // ставится меню модели (newWindowEffortByMenu, ниже); кнопка модели после выбора папки рождается не сразу.
  // #10261 (renew 05:32 снова «no-model-button», хотя в чате кнопка есть): на домашнем экране testid у кнопки
  // может быть без «epitaxy-» — узнаём её и по data-cds, и по подписи «Model:», которую всё равно читаем.
  const NEW_WINDOW_MODEL_SELECTOR = '[data-testid="epitaxy-cds-model-selector"],[data-testid$="model-selector"],button[data-cds="ModelSelector"],button[aria-label^="Model:"],button[aria-label^="Модель:"]';
  const NEW_WINDOW_EFFORT_SELECTOR = 'button[aria-label^="Effort:"],button[aria-label^="Усилия:"]';
  const NEW_WINDOW_PICK_MS = 1500;
  const NEW_WINDOW_BUTTON_MS = 6000;
  // #11618: Claude на русском — ступень хвостом по-русски («Opus 5.5 Сверхвысокий»); «Сверхвысокий» = xhigh (живьём 04.11).
  const NEW_WINDOW_TAIL_RE = /\s(low|medium|high|xhigh|extra|max|ultracode|низкий|средний|высокий|сверхвысокий|максимальный)$/i;
  const NEW_WINDOW_EFFORT_RU = { низкий: "low", средний: "medium", высокий: "high", сверхвысокий: "extra", максимальный: "max" };
  const NEW_WINDOW_EFFORTS = ["low", "medium", "high", "extra", "max", "ultracode"];
  const NEW_WINDOW_SLIDER_SELECTOR = '[role="slider"][aria-valuetext],input[type="range"][aria-valuetext]';
  const NEW_WINDOW_NOTE_MODEL = model => `Модель «${model}» не выбралась — текст передачи не отправлял`;
  // Без sendTransfer (renew-window, обычный new-window) текст всё равно уходит
  // первым сообщением — на той модели, что стояла (находка Б2a WF102).
  const NEW_WINDOW_NOTE_MODEL_SENT = model => `Модель «${model}» не выбралась — текст отправлен на той, что стояла`;
  const newWindowLabel = node => String(node?.textContent ?? "").replace(/\s+/g, " ").trim();
  const newWindowAria = (selector, prefixes) => {
    try {
      const label = String(document.querySelector(selector)?.getAttribute("aria-label") ?? "");
      const prefix = prefixes.find(word => label.startsWith(word));
      return prefix ? label.slice(prefix.length).trim() : null;
    } catch { return null; }
  };
  const newWindowModelNow = () => newWindowAria(NEW_WINDOW_MODEL_SELECTOR, ["Model:", "Модель:"]);
  const newWindowEffortNow = () => newWindowAria(NEW_WINDOW_EFFORT_SELECTOR, ["Effort:", "Усилия:"]);
  // Модель без хвоста ступени и ступень — с кнопки «Effort:», а нет её — хвостом кнопки модели.
  const newWindowModelName = () => newWindowModelNow()?.replace(NEW_WINDOW_TAIL_RE, "").trim() ?? null;
  const newWindowEffortShown = () => newWindowEffortNow() ?? newWindowModelNow()?.match(NEW_WINDOW_TAIL_RE)?.[1] ?? null;
  const newWindowModelMatch = (label, want) => {
    const text = String(label ?? "").replace(/\s+/g, " ").trim();
    return text === want || (text.length === want.length + 1 && text.startsWith(want) && /\d$/.test(text));
  };
  const newWindowMenuItems = () => {
    try { return [...document.querySelectorAll('[role^="menuitem"]')]; } catch { return []; }
  };
  const newWindowEscape = () => {
    const target = document.activeElement ?? document.body;
    try {
      target?.dispatchEvent(new KeyboardEvent("keydown", {
        key: "Escape", code: "Escape", keyCode: 27, which: 27, bubbles: true, cancelable: true,
      }));
    } catch {}
  };
  // Кнопки меню на экране, когда кнопки модели не нашли (#10261): чем Claude её заменил — в status().newWindow.model.seen.
  const newWindowMissState = { seen: null };
  const newWindowModelMiss = () => {
    try {
      newWindowMissState.seen = [...document.querySelectorAll('button[aria-haspopup="menu"],button[aria-haspopup="listbox"]')].slice(0, 8)
        .map(node => [node.getAttribute("data-testid"), node.getAttribute("data-cds"), node.getAttribute("aria-label"), newWindowLabel(node)]
          .map(part => String(part ?? "").slice(0, 60)).join(" | "));
    } catch { newWindowMissState.seen = null; }
  };
  // "ok" | "no-model-button" | "no-model" | "model-not-set".
  const newWindowSetModel = async (want, token) => {
    const button = await newWindowWait(() => document.querySelector(NEW_WINDOW_MODEL_SELECTOR), NEW_WINDOW_BUTTON_MS, token);
    if (!newWindowLive(token)) return "no-model";
    if (!button) { newWindowModelMiss(); return "no-model-button"; }
    if (newWindowModelName() === want) return "ok";
    pressLikeMouse(button);
    const find = () => newWindowMenuItems().find(item => newWindowModelMatch(newWindowLabel(item), want)) ?? null;
    let item = await newWindowWait(find, NEW_WINDOW_PICK_MS, token);
    if (!newWindowLive(token)) return "no-model";
    if (!item) {
      const more = newWindowMenuItems().find(node => /^(?:more models|другие модели)/i.test(newWindowLabel(node)));
      if (more) {
        pressLikeMouse(more);
        item = await newWindowWait(find, NEW_WINDOW_PICK_MS, token);
        if (!newWindowLive(token)) return "no-model";
      }
    }
    if (!item) { newWindowEscape(); return "no-model"; }
    pressLikeMouse(item);
    const ok = await newWindowWait(() => (newWindowModelName() === want ? true : null), NEW_WINDOW_PICK_MS, token);
    if (!ok) { newWindowEscape(); return "model-not-set"; }
    return "ok";
  };
  const newWindowEffortKey = value => {
    const word = String(value ?? "").trim().toLowerCase();
    return word === "xhigh" ? "extra" : NEW_WINDOW_EFFORT_RU[word] ?? word;
  };
  // #10268: кнопки «Effort:» нет — эффорт в меню модели: пункт «Effort ▸» (подменю) или группа «Effort» прямо в
  // меню, ступени [role=menuitemradio][data-effort-id]. Меню открываем «как мышью» (как newWindowSetModel), клик
  // по ступени применяет сразу; ждём смены хвоста кнопки модели. Встал диалог «Change effort level?» — не жмём,
  // оставляем человеку. Меню закрываем кликом мимо, НЕ Escape: в Claude Code Escape может остановить ход агента.
  // "ok" | "no-effort" | "effort-locked" | "effort-not-set" | "effort-confirm".
  const NEW_WINDOW_EFFORT_ITEM = '[role="menuitemradio"][data-effort-id]';
  const NEW_WINDOW_DIALOG = '[role="dialog"],[role="alertdialog"]';
  const newWindowEffortItem = goal => {
    try { return [...document.querySelectorAll(NEW_WINDOW_EFFORT_ITEM)].find(item => newWindowEffortKey(item.getAttribute("data-effort-id")) === goal) ?? null; } catch { return null; }
  };
  const newWindowModelEffort = () => newWindowEffortKey(newWindowModelNow()?.match(NEW_WINDOW_TAIL_RE)?.[1]);
  const newWindowMenuDismiss = () => {
    if (!newWindowMenuItems().length) return;
    const target = document.body ?? document.documentElement;
    const at = { clientX: 1, clientY: 1, screenX: 1, screenY: 1, bubbles: true, cancelable: true, composed: true, view: window, button: 0, buttons: 1 };
    try { target.dispatchEvent(new PointerEvent("pointerdown", { ...at, pointerId: 1, isPrimary: true, pointerType: "mouse" })); } catch {}
    try { target.dispatchEvent(new MouseEvent("mousedown", at)); } catch {}
    try { target.dispatchEvent(new PointerEvent("pointerup", { ...at, buttons: 0, pointerId: 1, isPrimary: true, pointerType: "mouse" })); } catch {}
    try { target.dispatchEvent(new MouseEvent("mouseup", { ...at, buttons: 0 })); } catch {}
  };
  const newWindowEffortByMenu = async (goal, token) => {
    const button = document.querySelector(NEW_WINDOW_MODEL_SELECTOR);
    if (!button) return "no-effort";
    let before;
    try { before = new Set(document.querySelectorAll(NEW_WINDOW_DIALOG)); } catch { before = new Set(); }
    const isTrigger = node => !node.hasAttribute("data-effort-id") && /^(?:effort|уровень усилий|усилия)/i.test(newWindowLabel(node));
    pressLikeMouse(button);
    let item = await newWindowWait(() => newWindowEffortItem(goal) ?? newWindowMenuItems().find(isTrigger) ?? null, NEW_WINDOW_PICK_MS, token);
    if (!newWindowLive(token)) return "no-effort";
    if (item && isTrigger(item)) {
      pressLikeMouse(item);
      try {
        item.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", code: "ArrowRight", keyCode: 39, which: 39, bubbles: true, cancelable: true }));
      } catch {}
      item = await newWindowWait(() => newWindowEffortItem(goal), NEW_WINDOW_PICK_MS, token);
      if (!newWindowLive(token)) return "no-effort";
    }
    if (!item) { newWindowMenuDismiss(); return "no-effort"; }
    if (item.getAttribute("aria-disabled") === "true" || item.hasAttribute("data-disabled") || item.disabled) {
      newWindowMenuDismiss();
      return "effort-locked";
    }
    pressLikeMouse(item);
    const fresh = () => { try { return [...document.querySelectorAll(NEW_WINDOW_DIALOG)].some(node => !before.has(node)); } catch { return false; } };
    const result = await newWindowWait(() => (fresh() ? "effort-confirm" : newWindowModelEffort() === goal ? "ok" : null), NEW_WINDOW_PICK_MS, token);
    if (result === "effort-confirm") return result;
    newWindowMenuDismiss();
    return result ?? "effort-not-set";
  };
  // "ok" | "no-effort-button" | "no-effort" | "effort-not-set" | "effort-confirm".
  const newWindowSetEffort = async (want, token) => {
    const goal = newWindowEffortKey(want);
    const found = await newWindowWait(() => document.querySelector(NEW_WINDOW_EFFORT_SELECTOR) ?? document.querySelector(NEW_WINDOW_MODEL_SELECTOR),
      NEW_WINDOW_BUTTON_MS, token);
    if (!newWindowLive(token)) return "no-effort";
    if (newWindowEffortKey(newWindowEffortShown()) === goal) return "ok";
    const button = document.querySelector(NEW_WINDOW_EFFORT_SELECTOR);
    if (!button) return found ? newWindowEffortByMenu(goal, token) : "no-effort-button";
    pressLikeMouse(button);
    // С Claude 24.09 ползунок — <input type="range"> Base UI (шестая ступень
    // Ultracode), до того — [role="slider"]; оба с aria-valuetext (живой гейт WF85).
    const slider = await newWindowWait(() => document.querySelector(NEW_WINDOW_SLIDER_SELECTOR), NEW_WINDOW_PICK_MS, token);
    if (!newWindowLive(token)) return "no-effort";
    if (!slider) { newWindowEscape(); return "no-effort"; }
    const goalAt = NEW_WINDOW_EFFORTS.indexOf(goal);
    try { slider.focus(); } catch {}
    for (let step = 0; step < NEW_WINDOW_EFFORTS.length * 2; step += 1) {
      const now = newWindowEffortKey(slider.getAttribute("aria-valuetext"));
      if (now === goal) break;
      const at = NEW_WINDOW_EFFORTS.indexOf(now);
      // Ступень не из списка — идём вправо, упёрлись — влево.
      const key = goalAt >= 0 && at >= 0 && goalAt < at ? "ArrowLeft" : (step < NEW_WINDOW_EFFORTS.length ? "ArrowRight" : "ArrowLeft");
      try {
        slider.dispatchEvent(new KeyboardEvent("keydown", { key, code: key, bubbles: true, cancelable: true }));
      } catch {}
      await newWindowSleep(NEW_WINDOW_POLL_MS);
      if (!newWindowLive(token)) return "no-effort";
    }
    // Claude спросил подтверждение (MAX — платный, предупреждение Fable) — не жмём и не гасим Esc: решает человек (#10265).
    try { if (document.querySelector('[role="alertdialog"]')) return "effort-confirm"; } catch {}
    newWindowEscape();
    const ok = await newWindowWait(
      () => (newWindowEffortKey(newWindowEffortNow()) === goal ? true : null), NEW_WINDOW_PICK_MS, token);
    return ok ? "ok" : "effort-not-set";
  };
  // Запись «Обкэшить» с handoff (К1) для sendTransfer: донор пишет её командой
  // cashout, которая уходит ПЕРЕД new-window, — ждём её недолго. Годится только
  // свежая и ничья: главного окна (без to) или попапа, ждущего адресата.
  const NEW_WINDOW_HANDOFF_MS = 3000;
  const newWindowHandoff = token => newWindowWait(() => {
    const record = readCashout();
    if (!record?.handoff || Date.now() - record.at > CASHOUT_FRESH_MS) return null;
    return record.to == null || record.to === CASHOUT_PENDING ? record : null;
  }, NEW_WINDOW_HANDOFF_MS, token);

  // Имя чата (WF16). Штатного действия в предзагруженных сторах claude.ai нет
  // (разведка П2: у попапов есть setPopoutTitle, но renameSession/setSessionTitle
  // там не лежит), поэтому переименовываем тем же путём, каким это делает Элвис
  // руками, — контекстным меню строки сайдбара. Путь заведомо хрупкий, и вся
  // цепочка от него не зависит: не нашли пункта или поля — молча идём дальше
  // (статус no-rename), имя чата остаётся авто-заголовком Claude, а ключ темы и
  // заголовок окна берутся из ФАКТИЧЕСКОЙ строки сайдбара (критик WF16, В3).
  const newWindowMenuClose = () => {
    try {
      document.dispatchEvent(new KeyboardEvent("keydown", {
        key: "Escape", code: "Escape", keyCode: 27, which: 27, bubbles: true, cancelable: true,
      }));
    } catch {}
    try { document.body?.click(); } catch {}
  };
  // Поле имени: живое, редактируемое и заведомо НЕ поле ввода чата — иначе имя
  // проекта уехало бы в композер только что созданного разговора.
  const newWindowNameField = node => {
    if (!node?.isConnected) return false;
    try { if (node.closest?.(NEW_WINDOW_INPUT_SELECTOR)) return false; } catch {}
    if (node.tagName === "INPUT") return /^(text|search|)$/i.test(node.getAttribute("type") ?? "");
    if (node.tagName === "TEXTAREA") return true;
    return node.isContentEditable === true;
  };
  const newWindowNameText = node => String(node?.value ?? node?.innerText ?? node?.textContent ?? "").trim();
  // React слушает не .value, а событие input: присвоение напрямую он не видит,
  // поэтому значение ставим родным сеттером прототипа и досылаем события сами.
  const newWindowNameSet = (node, value) => {
    try {
      const proto = node.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      const setter = Object.getOwnPropertyDescriptor(proto, "value")?.set;
      if (setter) setter.call(node, value); else node.value = value;
      node.dispatchEvent(new Event("input", { bubbles: true }));
      node.dispatchEvent(new Event("change", { bubbles: true }));
    } catch {}
  };
  // Контекстное меню строки сайдбара — как правой кнопкой мыши.
  const newWindowRowMenu = row => {
    try {
      const box = row.getBoundingClientRect();
      row.dispatchEvent(new MouseEvent("contextmenu", {
        bubbles: true, cancelable: true, view: window,
        clientX: Math.round(box.left + box.width / 2), clientY: Math.round(box.top + box.height / 2),
      }));
      return true;
    } catch { return false; }
  };
  const newWindowRename = async (row, name, token) => {
    if (!row?.isConnected || !name) return false;
    if (!newWindowRowMenu(row)) return false;
    const item = await newWindowWait(() => {
      try {
        for (const node of document.querySelectorAll(NEW_WINDOW_MENU_SELECTOR)) {
          if (NEW_WINDOW_RENAME_RE.test(String(node.textContent ?? "").trim())) return node;
        }
      } catch {}
      return null;
    }, NEW_WINDOW_MENU_MS, token);
    // Меню за собой гасим ВСЕГДА: команда идёт в живом окне Элвиса, и открытое
    // контекстное меню там оставлять нельзя.
    if (!item) { newWindowMenuClose(); return false; }
    try { item.click(); } catch { newWindowMenuClose(); return false; }
    // Где появится поле имени — в модалке или прямо в строке, — зависит от
    // сборки claude.ai, поэтому берём то, что под фокусом, а нет его — первое
    // поле внутри модалки или списка чатов. Дальше этих двух мест не смотрим
    // НАРОЧНО: промахнись мы полем — имя проекта уехало бы в чужую строку
    // живого окна Элвиса (поиск по чатам, поле ввода).
    const field = await newWindowWait(() => {
      const hosts = [];
      try { hosts.push(...document.querySelectorAll('[role="dialog"]')); } catch {}
      try {
        const rows = document.querySelector(NEW_WINDOW_ROWS_SELECTOR);
        if (rows) hosts.push(rows);
      } catch {}
      const active = document.activeElement;
      if (newWindowNameField(active) && hosts.some(host => host.contains(active))) return active;
      for (const host of hosts) {
        let found = null;
        try { found = host.querySelector(NEW_WINDOW_NAME_SELECTOR); } catch {}
        if (newWindowNameField(found)) return found;
      }
      return null;
    }, NEW_WINDOW_RENAME_MS, token);
    if (!field) { newWindowMenuClose(); return false; }
    try { field.focus(); } catch {}
    if (typeof field.value === "string") {
      try { field.select?.(); } catch {}
      newWindowNameSet(field, name);
    } else {
      try { document.execCommand("selectAll", false, null); } catch {}
      try { document.execCommand("insertText", false, name); } catch {}
    }
    if (newWindowNameText(field) !== name) { newWindowMenuClose(); return false; }
    // Подтверждение — Enter в самом поле: кнопки «Сохранить» у переименования
    // может и не быть, а Enter понимают обе разметки.
    try {
      for (const type of ["keydown", "keypress", "keyup"]) {
        field.dispatchEvent(new KeyboardEvent(type, {
          key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true, cancelable: true,
        }));
      }
    } catch {}
    // Поле ушло из документа — переименование приняли. Осталось на месте —
    // гасим за собой и честно говорим «не вышло».
    const closed = await newWindowWait(() => (field.isConnected ? null : true), NEW_WINDOW_RENAME_MS, token);
    if (!closed) { newWindowMenuClose(); return false; }
    return true;
  };

  // 6в. Цвет и размер нового окна — ДО openPopout: попап читает ту же карту
  // (localStorage у окон Claude общий), и запись под ключом его чата успевает
  // лечь раньше, чем окно откроется, — оно рисуется уже покрашенным.
  // Пишем РОВНО записи ЧАТА. Ни writeLayers, ни storeSessionLayers, ни
  // applyLayer тут звать нельзя: команду исполняет ГЛАВНОЕ окно, и writeKeys()
  // добавил бы к ключу чата ещё и `main` с сессией — один клик по «Новое окно
  // ▸ Dictatorik» перекрасил бы окно Элвиса в чужой цвет (критик WF16, Б3).
  // Слои на экран здесь тоже не применяются: они не про это окно.
  // Отдельной функцией — для люка тестов (z8-r02): шаг проверяется поведением,
  // а не нарезкой текста файла. Отдаёт "no-title" (мягкая пометка) или null.
  const newWindowPaintChat = (id, title, rowTitle, layers) => {
    // Заголовок-заглушка тенью `chat:` быть не может: запись под ней досталась бы
    // каждому безымянному чату разом. А ключ `id:` заголовка не требует вовсе —
    // с ним цвет ложится и безымянному чату (находка ревизии 08.09).
    const stub = !rowTitle || !title || THEME_TITLE_STUBS.has(title.toLowerCase());
    if (stub) newWindowMark({ state: "no-title" });
    try {
      const map = readThemeMap();
      // Оба ключа чата, как в writeLayers: id главный, имя — тень для окна,
      // которое своего id ещё не знает. Раньше писалась одна тень, и цвет окна
      // держался на имени — ровно на том, что WF35 объявил ненадёжным.
      setMapLayers(map, `${THEME_ID_PREFIX}${id}`, layers);
      if (!stub) {
        setMapLayers(map, `${THEME_CHAT_PREFIX}${title}`, layers);
        // Тень — этого чата (z1-r01), как в writeLayers.
        const shadow = map[`${THEME_CHAT_PREFIX}${title}`];
        if (shadow && typeof shadow === "object") shadow.by = id;
      }
      writeThemeMap(map);
      newWindowMark({ layers: Object.keys(layers) });
    } catch {
      // Квота или битая карта — не повод ронять окно, как и no-rename.
      newWindowMark({ layers: "failed" });
    }
    return stub ? "no-title" : null;
  };

  // Общий шаг обоих пунктов: вынести сессию в отдельное окно. Заголовок берём
  // тот, что показывает сайдбар (константу «Новый чат» передавать нельзя — это
  // заглушка из THEME_TITLE_STUBS, и ключа темы chat: у окна не будет вовсе).
  const newWindowOpenPopout = (store, id, title, x, y) => {
    // Claude 2.16120 (30.09): запись попапа может остаться в сторе без окна (не
    // показан, рамки нет) — тогда openPopout молча ничего не делает («не открылось
    // за 15 с»). Такую запись снимаем, и окно рождается заново.
    try {
      const now = store.getState();
      if (now.popoutWindows?.has?.(id) && typeof now.isPopoutShowing === "function" && !now.isPopoutShowing(id) &&
        typeof now.getPopoutHandleBounds === "function" && !now.getPopoutHandleBounds(id)) now.closePopout?.(id);
    } catch {}
    store.getState().openPopout({
      type: "code-session",
      sessionId: id,
      sessionType: "local",
      isSsh: false,
      title,
      entryPoint: "context_menu",
      initialPosition: { x, y },
    });
  };

  // Стереть из поля РОВНО свой текст: поле держит что-то другое — не трогаем.
  const newWindowClearOwn = (editor, own) => {
    const want = cashoutNorm(own);
    if (!want || !editor?.isConnected || cashoutNorm(rawText(editor)) !== want) return false;
    try { editor.focus(); } catch {}
    try { document.execCommand("selectAll", false, null); } catch {}
    try { document.execCommand("delete", false, null); } catch {}
    return editorText(editor) === "";
  };

  // Копия первого сообщения в поле нового чата (живьём 31.10 07:29, renew окна Рика): сообщение ушло и
  // стоит в ленте, а поле так и держит тот же текст — следующий renew увёз бы его переносом черновика
  // (12ч). Сообщение в ленте — даём Claude опустошить поле самому, не опустошил — стираем РОВНО свой
  // текст. Дописано в поле что-то ещё или в ленте его нет — не трогаем. Исход — newWindow.ghost:
  // "cleared" | "left"; поле пустое — поля нет.
  const NEW_WINDOW_GHOST_MS = 1500;
  const NEW_WINDOW_SENT_SELECTOR = '[data-testid="user-message"]';
  const newWindowGhost = async (first, token) => {
    const want = cashoutNorm(first);
    const head = want.slice(0, CASHOUT_HEAD);
    const field = () => document.querySelector(NEW_WINDOW_INPUT_SELECTOR);
    const same = () => cashoutNorm(rawText(field())) === want;
    if (!head || !same()) return null;
    const sent = [...document.querySelectorAll(NEW_WINDOW_SENT_SELECTOR)]
      .some(node => cashoutNorm(node.textContent).includes(head));
    if (!sent) return "left";
    const clean = await newWindowWait(() => (same() ? null : true), NEW_WINDOW_GHOST_MS, token);
    if (!newWindowLive(token) || clean) return null;
    return newWindowClearOwn(field(), first) ? "cleared" : "left";
  };

  // Возврат главного окна на прежний разговор. Основной путь — клик по строке
  // сайдбара: это собственная навигация приложения. Запасной — history: после
  // ⌘N и отправки окно прошло ДВЕ навигации, поэтому шагов назад тоже два.
  // pushState для возврата не годится: он затирает служебный history.state
  // роутера и ломает back/forward до перезагрузки страницы.
  // Третий путь возврата (verify #7727): строки нет (сайдбар свёрнут, список
  // виртуальный), а запись истории выпала за потолок 50 (#7113) — тогда
  // строка и история срываются каждый раз одинаково. Claude 2.9939.2 держит
  // свой TanStack Router в window.__TSR_ROUTER__ (разведка 26.09): navigate —
  // навигация самого приложения, служебный history.state он пишет сам.
  const navRouterTo = path => {
    let router = null;
    try { router = window.__TSR_ROUTER__; } catch { router = null; }
    if (!path || typeof router?.navigate !== "function") return false;
    try {
      const run = router.navigate({ to: path });
      run?.catch?.(() => {});
      return true;
    } catch { return false; }
  };
  const newWindowBack = async (prev, prevId, before, token) => {
    if (location.pathname === prev) { newWindowMark({ back: "stay" }); return; }
    const reached = () => newWindowWait(() => (location.pathname === prev ? true : null), NEW_WINDOW_BACK_MS, token);
    const row = newWindowRow(prevId, true);
    let ok = false;
    if (row) { newWindowRowClick(row); ok = await reached(); }
    // Строки нет или не довела — историей (как обход чатов 12е).
    if (!ok && newWindowLive(token) && navBackTo(before)) {
      ok = await reached();
      if (ok) { newWindowMark({ back: "history" }); return; }
    }
    // И роутером страницы.
    if (!ok && newWindowLive(token) && navRouterTo(prev)) {
      ok = await reached();
      if (ok) { newWindowMark({ back: "router" }); return; }
    }
    // Не вернулось — оставляем как есть: лучше остаться на новом чате, чем
    // ломать роутер главного окна.
    newWindowMark({ back: ok ? "row" : "back-failed" });
  };

  // Сторож возврата (#7727, слово Элвиса 25.09 23:30: «почему вообще два чата ты
  // открыл?»). Вынесенный чат «Pimp Viewer макет» остался и в главном окне:
  // возврат не случился (back-failed) или Claude 2.9939.2 увёл главное окно на
  // новый чат уже ПОСЛЕ возврата. Чат в двух окнах сразу — всегда ошибка, поэтому
  // NEW_WINDOW_RETURN_MS после выноса главное окно, оказавшееся на вынесенном
  // чате, Пимп возвращает на прежний сам (не больше двух раз). Ушло окно в третий
  // чат (Элвис, обход Авто-Allow) или началась новая цепочка — сторож молчит.
  // Не ждётся цепочкой: кнопка «Нового окна» свободна, пока он смотрит.
  const NEW_WINDOW_RETURN_MS = 12000;
  const NEW_WINDOW_RETURN_TRIES = 2;
  const newWindowReturnGuard = async (id, prev, prevId, before, token) => {
    if (!id || prevId === id || !prev.startsWith(NEW_WINDOW_HOME_PATH)) return;
    const deadline = now() + NEW_WINDOW_RETURN_MS;
    let tries = 0;
    while (tries < NEW_WINDOW_RETURN_TRIES && newWindowLive(token)) {
      const left = deadline - now();
      if (left <= 0) break;
      // "shown" — главное окно на вынесенном чате; "gone" — ушло в третий.
      const seen = await newWindowWait(() => {
        const path = location.pathname;
        if (newWindowSegment(path) === id) return "shown";
        return path === prev ? null : "gone";
      }, left, token);
      if (seen !== "shown") break;
      tries += 1;
      newWindowMark({ returned: tries });
      await newWindowBack(prev, prevId, before, token);
    }
  };

  // Команда «Новое окно», контракт WF16 (расширение WF13), с WF37 —
  // необязательное transfer после name: {id, action:"new-window", at,
  // scope:"window", title, match?, x, y, text, folder, name, transfer?,
  // theme?, font?, size?, frame?}. Исполняет только ГЛАВНОЕ окно и только
  // адресованное заголовком: страниц claude.ai может оказаться две, и обе
  // завели бы по чату.
  //
  // folder и name — всегда есть, пустая строка = «не трогать» (это и есть
  // поведение WF13). Слои — по правилам команды theme: поля нет — слой не
  // трогаем, null — сброс. Уникальность имени считает приложение по всем
  // сессиям на диске: страница номер не придумывает и сайдбар на совпадения не
  // проверяет (критик WF16, В4).
  const newWindowChain = async detail => {
    if (!isMainWindow() || !addressed(detail)) return false;
    const text = typeof detail?.text === "string" ? detail.text.trim() : "";
    // Координаты — именно ЧИСЛА, не строки: CommandChannel.write(action:extra:)
    // делает все значения строками, и такую команду мы обязаны отбить, а не
    // молча склеить (контракт WF13 требует write(action:fields:) с .number).
    const x = detail?.x;
    const y = detail?.y;
    const folder = typeof detail?.folder === "string" ? detail.folder.trim() : "";
    // Папка — только абсолютный путь (Swift шлёт standardizedFileURL.path); мусор
    // отсекаем сразу, а не поздним no-folder (verify WF16, находка 5).
    if (folder && !folder.startsWith("/")) { newWindowMark({ state: "bad-command", step: "folder", ...(state.newWindow?.busy ? {} : { actual: null }) }); return false; }
    // Длину имени режем ровно так же, как её режет строка сайдбара
    // (newWindowRowTitle): иначе сверка заголовка не сошлась бы никогда.
    const name = typeof detail?.name === "string" ? detail.name.trim().slice(0, 200) : "";
    // Перенос «Обкэшить» (WF37): поле есть ТОЛЬКО у ветки «Обкэшить» из попапа
    // и разбирается строго. Любая другая правда (строка "true", 1, объект)
    // переносом не считается: ⌥⌘N, «▸ проект», «Здесь же» и канал «Пимп» чужую
    // запись переноса не трогают вовсе (критик плана, блокер 2).
    const transfer = detail?.transfer === true;
    // «Новый чат» (К2, #7072): модель и эффорт до первого сообщения, текст
    // передачи первым сообщением (sendTransfer), stay — без попапа и возврата.
    const model = typeof detail?.model === "string" ? detail.model.replace(/\s+/g, " ").trim().slice(0, 80) : "";
    const effort = typeof detail?.effort === "string" ? detail.effort.trim().slice(0, 20) : "";
    const sendTransfer = detail?.sendTransfer === true;
    const stay = detail?.stay === true;
    // Закрепка (#7246): pin — закрепить новый чат, unpin — id старого (донора).
    const pin = detail?.pin === true;
    const unpin = typeof detail?.unpin === "string" && /^[\w-]{1,100}$/.test(detail.unpin.trim()) ? detail.unpin.trim() : "";
    const layers = {};
    for (const layer of THEME_LAYERS) {
      if (detail && layer in detail) layers[layer] = LAYER_NORMALIZE[layer](detail[layer]);
    }
    if (detail?.scope !== "window" || (!text && !stay) || !Number.isFinite(x) || !Number.isFinite(y)) {
      newWindowMark({ state: "bad-command", step: null, ...(state.newWindow?.busy ? {} : { actual: null }) });
      return false;
    }
    // Второй клик, пока идёт первый: два «Привета» в два чата никому не нужны.
    if (state.newWindow?.busy === true) { newWindowMark({ state: "busy" }); newWindowNote(NEW_WINDOW_NOTE_BUSY, true); return false; }
    const token = ++newWindowToken;
    newWindowMark({
      state: "run", step: "store", id: null, actual: null, back: null, pushed: false, busy: true, runs: newWindowRuns(),
      // Поля WF16 — начисто на каждый запуск: иначе на гейте не отличить, что
      // от этого прогона, а что осталось от прошлого.
      folder: folder || null, chip: null, name: name || null, rename: null, title: null,
      layers: Object.keys(layers).length ? Object.keys(layers) : null,
      // WF37: разобрано ли поле transfer и удалось ли штампануть перенос.
      transfer: transfer || null, stamped: null,
      // К2: что просили и что вышло; handoff — ушёл ли текст передачи первым сообщением.
      model: model || effort ? { want: model || null, effort: effort || null, was: null, got: null, note: null, from: null } : null,
      stay: stay || null, handoff: sendTransfer ? "wait" : null, trust: null,
      pin: pin ? "wait" : null, unpin: pin && unpin ? "wait" : null, pinWay: null, pinPlace: null,
      carry: null, ghost: null,
    });
    // Мягкая осечка: чат создан и вынесен, но имя или цвет не задались. Роняет
    // не цепочку, а только итоговый статус — плашки у неё нет.
    let soft = null;
    const guard = newWindowLater(() => {
      if (token !== newWindowToken) return;
      newWindowMark({ state: "timeout", busy: false, actual: null });
    }, NEW_WINDOW_GUARD_MS);
    // Чат уже заведён — возвращать главное окно на прежний разговор нельзя:
    // новый чат живёт именно здесь, и плашка зовёт вынести его вторым пунктом.
    let created = false;
    // Чат вынесен — сторож возврата (#7727) стартует из finally: и когда после
    // выноса что-то бросило (verify #7727).
    let returnGuard = null;
    // Черновик прежнего чата (#11201, раздел 12ч) — только у renew главного окна.
    let carry = null;
    try {
      // Прежний разговор запоминаем ДО поиска стора: поиск идёт около секунды,
      // а Swift жмёт ⌘N через 0,9 с — иначе «прежним» окажется уже /epitaxy
      // (verify WF13, находка 1).
      const prev = location.pathname;
      // Домашний экран прежним разговором не считается: возвращаться будем
      // историей, а не по строке сайдбара (её у /epitaxy нет).
      const prevId = prev === NEW_WINDOW_HOME_PATH ? "" : newWindowSegment(prev);
      const before = navMark();
      if (stay && !sendTransfer) carry = draftCarryStart(prev);
      const store = await newWindowFindStore(token);
      if (!newWindowLive(token)) return false;
      if (!store) {
        newWindowMark({ state: "no-store" });
        newWindowNote(NEW_WINDOW_NOTE_FAIL);
        return false;
      }

      // 1. Новый чат открывает Swift штатным ⌘N — ждём домашний экран.
      newWindowMark({ step: "home" });
      draftCarryRefresh(carry);
      let home = await newWindowWait(() => { draftCarryRefresh(carry); return newWindowAtHome() ? true : null; }, NEW_WINDOW_HOME_MS, token);
      if (!newWindowLive(token)) return false;
      if (!home) {
        // Последний запасной путь: pushState портит history.state роутера, но
        // без него команда просто умерла бы. Пометка pushed — для гейта.
        let pushed = false;
        try {
          history.pushState({}, "", NEW_WINDOW_HOME_PATH);
          window.dispatchEvent(new PopStateEvent("popstate", { state: history.state }));
          pushed = true;
        } catch {}
        newWindowMark({ pushed });
        home = pushed ? await newWindowWait(() => (newWindowAtHome() ? true : null), NEW_WINDOW_HOME_MS, token) : null;
        if (!newWindowLive(token)) return false;
        if (!home) {
          newWindowMark({ state: "no-home" });
          newWindowNote(NEW_WINDOW_NOTE_FAIL);
          return false;
        }
      }

      // 2. Композер обязан быть ПУСТ, иначе «Привет» приклеится к недописанной
      // мысли Элвиса и уедет в модель. Узел берём прямым селектором: в
      // state.editor/findEditor лежит кэш поля прошлого чата.
      newWindowMark({ step: "draft" });
      const editor = document.querySelector(NEW_WINDOW_INPUT_SELECTOR);
      // Заглушка, оставленная прошлой сорвавшейся цепочкой (26.09: диалог
      // доверия не дал отправить, и черновик Claude держал её, запирая все
      // следующие «Новые окна»), — наша, её стираем. Черновик Элвиса — никогда.
      if (location.pathname === NEW_WINDOW_HOME_PATH && editor?.isConnected) newWindowClearOwn(editor, text);
      if (location.pathname !== NEW_WINDOW_HOME_PATH || !editor?.isConnected || editorText(editor) !== "") {
        newWindowMark({ state: "draft" });
        newWindowNote(NEW_WINDOW_NOTE_DRAFT);
        await newWindowBack(prev, prevId, before, token);
        return false;
      }

      // 2б. Папка проекта (WF16). Шаг стоит ДО первого сообщения нарочно:
      // отправить «Привет» и только потом обнаружить, что папка не та, уже
      // нельзя — в этой сессии работает авто-Allow, и агент стартовал бы в
      // чужом проекте. Не вышло — сообщение НЕ отправляем, чат НЕ создаём,
      // плашка, главное окно назад (решение 1 плана WF16).
      if (folder) {
        newWindowMark({ step: "folder" });
        const picked = await newWindowPickFolder(folder, token);
        if (!newWindowLive(token)) return false;
        if (picked !== "ok") {
          newWindowMark({ state: picked });
          newWindowNote(NEW_WINDOW_NOTE_FOLDER_PICK);
          await newWindowBack(prev, prevId, before, token);
          return false;
        }
      }

      // 2в. Запись передачи (К2) — с WF85 ДО шага модели (К7.4): модель и
      // ступень из строки «Модель:» блока сильнее донорских полей команды.
      let handoff = null;
      if (sendTransfer) {
        newWindowMark({ step: "handoff" });
        handoff = await newWindowHandoff(token);
        if (!newWindowLive(token)) return false;
      }
      const wantModel = handoff?.model || model;
      const wantEffort = handoff?.effort || effort;
      const from = handoff?.model || handoff?.effort ? "блок" : "донор";

      // 2г. Модель и эффорт (К2) — до первого сообщения: на чужой модели текст
      // передачи не уходит (критик WF84, «Важное» 1). Эффорт после модели:
      // смена модели может сбросить ступень.
      let modelOk = true;
      if (wantModel || wantEffort) {
        newWindowMark({ step: "model" });
        const was = { model: newWindowModelName(), effort: newWindowEffortShown() };
        let asked = wantModel;
        let source = from;
        let fallback = null;
        const got = { model: asked ? await newWindowSetModel(asked, token) : null };
        if (!newWindowLive(token)) return false;
        // Модели из блока нет в меню (опечатка, модель снята) — откат на
        // донорскую модель команды, текст уходит (критик WF85, В5): ночью авто
        // иначе оставило бы пустой чат. «model-not-set» — как в К2.
        if (handoff?.model && got.model === "no-model" && handoff.model !== model) {
          fallback = "блок: no-model";
          source = "донор";
          asked = model;
          got.model = model ? await newWindowSetModel(model, token) : null;
          if (!newWindowLive(token)) return false;
        }
        modelOk = !asked || got.model === "ok";
        got.effort = wantEffort && modelOk ? await newWindowSetEffort(wantEffort, token) : null;
        if (!newWindowLive(token)) return false;
        const note = modelOk ? (fallback ?? (got.effort && got.effort !== "ok" ? got.effort : null)) : got.model;
        const seen = got.model === "no-model-button" ? newWindowMissState.seen : null;
        newWindowMark({ model: { want: asked || null, effort: wantEffort || null, was, got, note, from: source, ...(seen ? { seen } : {}) } });
        if (!modelOk) newWindowNote((sendTransfer || stay ? NEW_WINDOW_NOTE_MODEL : NEW_WINDOW_NOTE_MODEL_SENT)(asked));
      }

      // Текст передачи уходит первым сообщением ВМЕСТО заглушки — только на
      // той модели, что просили.
      // stay без sendTransfer (renew главного окна, WF181) — текст renew уходит первым сообщением.
      let first = stay && sendTransfer ? "" : text;
      if (sendTransfer) {
        if (handoff?.text && modelOk) first = handoff.text;
        newWindowMark({ handoff: handoff ? (handoff.text ? (modelOk ? "send" : "held") : "empty") : "none" });
      }
      // stay (главное окно): заглушку не шлём никогда. Текста передачи нет —
      // остаётся домашний экран с папкой и моделью; модель не встала — текст
      // ложится в поле неотправленным. Запись цепочка стирает сама (Б2).
      if (stay && first === "") {
        const held = handoff?.text && !modelOk ? handoff.text : "";
        const input = document.querySelector(NEW_WINDOW_INPUT_SELECTOR) ?? editor;
        if (held && input?.isConnected) insertIntoEditor(input, held, false);
        if (handoff) clearCashout();
        newWindowMark({ state: modelOk ? "ok" : "model", step: "stay" });
        return true;
      }

      // 3. Первое сообщение. Узел поля перечитываем: смена папки перерисовывает
      // домашний экран, и запомненный на шаге 2 узел мог отвалиться.
      newWindowMark({ step: "insert" });
      const input = document.querySelector(NEW_WINDOW_INPUT_SELECTOR) ?? editor;
      try { window.focus(); } catch {}
      try { window.electronWindowControl?.focus?.(); } catch {}
      if (!input?.isConnected || !insertIntoEditor(input, first, false)) {
        newWindowMark({ state: "no-insert" });
        newWindowNote(NEW_WINDOW_NOTE_FAIL);
        await newWindowBack(prev, prevId, before, token);
        return false;
      }

      // 4. Отправка. Кнопку ждём живой: пока не выбраны папка и модель, она
      // disabled, и клик вслепую ничего не даст. Диалог доверия (#7905) закрывает
      // её — сперва ждём его ухода, потом живую кнопку.
      newWindowMark({ step: "send" });
      const liveSend = () => document.querySelector(`${NEW_WINDOW_SEND_SELECTOR}:not([disabled])`);
      let send = await newWindowWait(() => (newWindowTrustShown() ? "trust" : liveSend()), NEW_WINDOW_SEND_MS, token);
      if (!newWindowLive(token)) return false;
      if (send === "trust") {
        newWindowMark({ step: "trust" });
        const passed = await newWindowTrustPass(token);
        if (!newWindowLive(token)) return false;
        newWindowMark({ step: "send" });
        send = passed ? await newWindowWait(liveSend, NEW_WINDOW_SEND_MS, token) : null;
        if (!newWindowLive(token)) return false;
      }
      if (send) { try { send.click(); } catch {} }
      else {
        // Кнопка так и не ожила — пробуем Enter в самом редакторе.
        try {
          input.dispatchEvent(new KeyboardEvent("keydown", {
            key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true, cancelable: true,
          }));
        } catch {}
      }

      // 5. Сессия рождается на первом сообщении: ждём /epitaxy/local_<uuid>.
      // Прежний чат за новую сессию не принимаем: мигни роутер старым адресом —
      // и в отдельное окно уехал бы не тот разговор.
      newWindowMark({ step: "session" });
      const newSession = () => {
        const found = newWindowSessionId();
        return found && found !== prevId ? found : null;
      };
      let id = await newWindowWait(() => newSession() ?? (newWindowTrustShown() ? "trust" : null), NEW_WINDOW_SESSION_MS, token);
      if (!newWindowLive(token)) return false;
      // Диалог встал уже после отправки (#7905): ждём его ухода и жмём отправку
      // ещё раз — если наш текст так и лежит в поле, а кнопка ожила. Ушёл сам
      // текст — сообщение Claude отправил сам, второго клика не нужно.
      if (id === "trust") {
        newWindowMark({ step: "trust" });
        const passed = await newWindowTrustPass(token);
        if (!newWindowLive(token)) return false;
        id = null;
        if (passed) {
          newWindowMark({ step: "send" });
          const again = newSession() ? null : await newWindowWait(() => newSession() ?? liveSend(), NEW_WINDOW_SEND_MS, token);
          if (!newWindowLive(token)) return false;
          const box = document.querySelector(NEW_WINDOW_INPUT_SELECTOR) ?? input;
          if (again && !newSession() && again.nodeType === 1 && cashoutNorm(rawText(box)) === cashoutNorm(first)) {
            send = again;
            try { again.click(); } catch {}
          }
          newWindowMark({ step: "session" });
          id = await newWindowWait(newSession, NEW_WINDOW_SESSION_MS, token);
          if (!newWindowLive(token)) return false;
        }
      }
      if (!id) {
        // Кнопка не ожила — почти всегда это несуществующая последняя папка.
        const reason = send ? "no-send" : "no-folder";
        newWindowMark({ state: reason });
        newWindowNote(send ? NEW_WINDOW_NOTE_FAIL : NEW_WINDOW_NOTE_FOLDER);
        // Чата нет — своё из поля убираем и главное окно возвращаем, как при no-insert.
        newWindowClearOwn(document.querySelector(NEW_WINDOW_INPUT_SELECTOR) ?? input, first);
        await newWindowBack(prev, prevId, before, token);
        return false;
      }
      created = true;

      // 6. Строка сайдбара: по ней видно, что сессия действительно создана, и
      // из неё же берём имя для окна.
      newWindowMark({ step: "row", id });
      const row = await newWindowWait(() => newWindowRow(id), NEW_WINDOW_ROW_MS, token);
      if (!newWindowLive(token)) return false;
      if (!row) await newWindowSleep(NEW_WINDOW_ROW_GRACE_MS);
      if (!newWindowLive(token)) return false;

      // 6а. Имя чата (WF16). Пока чат не переименован, его заголовок — это текст
      // первого сообщения, и приложение позже перепишет его своей сводкой; после
      // переименования заголовок становится «пользовательским» и больше не
      // меняется — а значит, не съедет и цвет окна, привязанный к заголовку.
      // Отказ переименования цепочку не роняет: чат создан и назван правильно.
      if (name) {
        newWindowMark({ step: "rename" });
        const renamed = await newWindowRename(newWindowRow(id) ?? row, name, token);
        if (!newWindowLive(token)) return false;
        newWindowMark({ rename: renamed });
        if (!renamed) { soft = "no-rename"; newWindowMark({ state: soft }); }
      }

      // 6б. Сверка заголовка (критик WF16, В3). В ключ темы и в openPopout
      // обязана уйти ОДНА И ТА ЖЕ строка — та, что реально показывает сайдбар:
      // заголовок попапа приходит из сессии, а красится окно по нему
      // (applyChatEntry). Ждём до двух секунд, пока имя доедет до строки, и
      // дальше берём фактическое.
      if (name) {
        newWindowMark({ step: "title" });
        await newWindowWait(
          () => (newWindowRowTitle(newWindowRow(id)) === name ? true : null), NEW_WINDOW_TITLE_MS, token);
        if (!newWindowLive(token)) return false;
      }
      // Ключ темы — ТОЛЬКО из строки сайдбара: без неё (сайдбар свёрнут) document.title
      // главного окна может ещё быть заголовком чата Элвиса, и слои легли бы под него
      // (verify WF16, находка 1). Для openPopout заголовок окна как запасной годится.
      const rowTitle = newWindowRowTitle(newWindowRow(id) ?? row);
      const title = rowTitle || windowTitle();
      newWindowMark({ title: title || null });

      // 6в. Цвет и размер нового окна — ДО openPopout (newWindowPaintChat).
      if (Object.keys(layers).length) {
        const painted = newWindowPaintChat(id, title, rowTitle, layers);
        if (painted) soft = painted;
      }

      // 6г. Перенос «Обкэшить» (WF37): запись донора ждала адресата — теперь он
      // есть. Штамп стоит ДО openPopout, чтобы новое окно нашло готовую запись
      // уже на инжекте, и только при transfer: обычное «Новое окно» чужой
      // перенос не трогает вовсе.
      const sent = Boolean(handoff?.text) && first === handoff.text;
      if (transfer) newWindowMark({ stamped: cashoutStamp(id, title, sent) });

      // #7379: readback нового чата до возврата главного окна. Requested и
      // donor не факты: неизвестная/неоднозначная подпись остаётся null.
      // Helpers уже срезают краевые пробелы; ограничиваем канонический readback.
      const bounded = (value, max) => typeof value === "string" && value.trim().length > 0
        && value.trim().length <= max && !/[\x00-\x1f\x7f]/.test(value) ? value.trim() : null;
      const commandId = bounded(detail?.id, 64);
      try {
        if (newWindowLive(token) && state.newWindow?.busy === true && newWindowSessionId() === id
          && commandId && /^local_[A-Za-z0-9_-]+$/.test(id) && id.length <= 128) {
          newWindowMark({ actual: {
            commandId, chat: id,
            model: document.querySelectorAll(NEW_WINDOW_MODEL_SELECTOR).length === 1 ? bounded(newWindowModelNow(), 100) : null,
            effort: document.querySelectorAll(NEW_WINDOW_EFFORT_SELECTOR).length === 1 ? bounded(newWindowEffortNow(), 32) : null,
          } });
        }
      } catch { /* Диагностика не меняет ход создания окна. */ }

      // stay (К2, «Новый чат» из главного окна): чат остаётся здесь — ни попапа,
      // ни возврата; запись переноса стираем сами (Б2).
      if (stay) {
        if (handoff) clearCashout();
        const ghost = await newWindowGhost(first, token);
        if (!newWindowLive(token)) return false;
        if (ghost) newWindowMark({ ghost });
        if (carry) await draftCarryPut(carry, first, token);
        if (!newWindowLive(token)) return false;
        if (pin) await newWindowPinSteps(id, unpin, token);
        newWindowMark({ state: soft ?? (modelOk ? "ok" : "model"), step: "stay" });
        return true;
      }

      // 7. Отдельное окно.
      newWindowMark({ step: "popout" });
      try { newWindowOpenPopout(store, id, title, x, y); }
      catch (error) {
        newWindowMark({ state: "popout-failed", actual: null, error: newWindowError(error) });
        newWindowNote(NEW_WINDOW_NOTE_CREATED);
        return false;
      }

      // 8. Главное окно — обратно на прежний разговор (П1: openPopout само его
      // никуда не уводит).
      returnGuard = () => newWindowReturnGuard(id, prev, prevId, before, token);
      newWindowMark({ state: soft ?? "ok", step: "back" });
      await newWindowBack(prev, prevId, before, token);
      // Закрепка — после выноса и возврата: окно нового чата не ждёт меню.
      if (pin && newWindowLive(token)) {
        await newWindowPinSteps(id, unpin, token);
        newWindowMark({ step: "back" });
      }
      return true;
    } catch (error) {
      newWindowMark({ state: "error", actual: null, error: newWindowError(error) });
      newWindowNote(created ? NEW_WINDOW_NOTE_CREATED : NEW_WINDOW_NOTE_FAIL);
      return false;
    } finally {
      clearTimeout(guard);
      newWindowTimers.delete(guard);
      // #7727: чат не должен остаться в двух окнах — сторож возврата, не ждём его.
      if (returnGuard) {
        newWindowMark({ returned: 0 });
        returnGuard().catch(() => {});
      }
      if (token === newWindowToken) newWindowMark({ busy: false });
      draftCarryKeep(carry);
    }
  };
  // Перенос «Обкэшить» из попапа (#5592): цепочка отказала — причину в запись донора
  // (cashoutRefuse, раздел 12), иначе донор и приложение ждут до потолка. Занятость, пока идёт
  // перенос, — не отказ: идущая цепочка и есть этот перенос.
  const NEW_WINDOW_TRANSFER_WHY = {
    draft: "в главном окне в поле черновик", busy: "новое окно уже открывается",
    "no-folder": "не выбрана папка", "no-home": "главное окно не ушло на новый чат",
  };
  const runNewWindowCommand = async detail => {
    const ok = await newWindowChain(detail);
    if (ok || detail?.transfer !== true || !state.alive || !isMainWindow() || !addressed(detail)) return ok;
    const run = state.newWindow ?? {};
    if (run.state === "busy" && run.transfer === true) return ok;
    const why = NEW_WINDOW_TRANSFER_WHY[run.state] ?? (run.step === "folder" ? "не выбралась папка" : "новое окно не открылось");
    try { cashoutRefuse(why, run.stamped === true ? run.id ?? "" : ""); } catch {}
    return ok;
  };

  // Закрепка (#7246, решение Элвиса 23.09 по умолчанию: «наверху только живой
  // чат»): «💬 Новый чат» закрепляет НОВЫЙ чат и открепляет старый.
  // Штатного действия в сторах нет под рукой, поэтому тем же путём, что
  // переименование, — контекстное меню строки сайдбара, пункт «Pin» / «Unpin»
  // (Claude 2.2553, меню сессии кода: подпись и приклеенная клавиша «p» —
  // «PinP»). Не вышло — цепочку не роняем: чат создан, только не закреплён.
  const NEW_WINDOW_PIN_RE = /^(?:pin|закрепить)(?:\s*p)?$/i;
  const NEW_WINDOW_UNPIN_RE = /^(?:unpin|открепить)(?:\s*p)?$/i;
  const newWindowPinnedRow = id => {
    if (!id) return null;
    try {
      const key = String(id).replace(/["\\]/g, "\\$&");
      return document.querySelector(`${NEW_WINDOW_PINNED_SELECTOR} [data-row-key$="${key}"]`);
    } catch { return null; }
  };
  // "ok" | "already" | "no-row" | "no-menu" | "not-done".
  const newWindowPin = async (id, pin, token) => {
    const pinnedNow = () => Boolean(newWindowPinnedRow(id));
    if (pinnedNow() === pin) return "already";
    const row = pin ? newWindowRow(id, true) : newWindowPinnedRow(id);
    if (!row?.isConnected || !newWindowRowMenu(row)) return "no-row";
    const item = await newWindowWait(() => {
      try {
        for (const node of document.querySelectorAll(NEW_WINDOW_MENU_SELECTOR)) {
          const text = String(node.textContent ?? "").replace(/\s+/g, " ").trim();
          if (NEW_WINDOW_PIN_RE.test(text) || NEW_WINDOW_UNPIN_RE.test(text)) return node;
        }
      } catch {}
      return null;
    }, NEW_WINDOW_MENU_MS, token);
    const text = String(item?.textContent ?? "").replace(/\s+/g, " ").trim();
    if (!item || !(pin ? NEW_WINDOW_PIN_RE : NEW_WINDOW_UNPIN_RE).test(text)) {
      newWindowMenuClose();
      return item ? "already" : "no-menu";
    }
    try { item.click(); } catch { newWindowMenuClose(); return "no-menu"; }
    const done = await newWindowWait(() => (pinnedNow() === pin ? true : null), NEW_WINDOW_MENU_MS, token);
    return done ? "ok" : "not-done";
  };
  // Закрепка на МЕСТО старого (WF85, К9, #7366; слово Элвиса 24.09: новый чат
  // встаёт в закреплённых ровно туда, где был старый). Меню так не умеет — оно
  // кладёт новый наверх. Так делает сам Claude при телепорте (carriedPin): два
  // стора zustand — звёздочки (starredIds, setStarred(id, bool)) и порядок
  // закреплённых (pinnedOrder — строки "code:<id>", setPinnedOrder(array)).
  // Ищем ПОВЕДЕНЧЕСКИ, как стор попапов; не нашли — прежний путь меню.
  let newWindowStarStore = null;
  let newWindowOrderStore = null;
  const newWindowStarOk = store => {
    try {
      const value = store?.getState?.();
      return Boolean(value && Array.isArray(value.starredIds) && typeof value.setStarred === "function");
    } catch { return false; }
  };
  const newWindowOrderOk = store => {
    try {
      const value = store?.getState?.();
      return Boolean(value && Array.isArray(value.pinnedOrder) && typeof value.setPinnedOrder === "function");
    } catch { return false; }
  };
  const newWindowStarred = (store, id) => {
    try { const list = store.getState().starredIds; return list.includes(id) || list.includes(`code:${id}`); } catch { return false; }
  };
  const newWindowOrder = store => {
    try { return [...store.getState().pinnedOrder].map(String); } catch { return []; }
  };
  // true — сделано сторами (итог в pin/unpin), false — сторов нет, нужен путь меню.
  const newWindowPinStore = async (id, unpin, token) => {
    if (!newWindowStarOk(newWindowStarStore)) {
      const found = await newWindowScanStores(token, newWindowStarOk);
      if (found) newWindowStarStore = found;
    }
    if (!newWindowLive(token)) return true;
    if (!newWindowOrderOk(newWindowOrderStore)) {
      const found = await newWindowScanStores(token, newWindowOrderOk);
      if (found) newWindowOrderStore = found;
    }
    if (!newWindowLive(token)) return true;
    const star = newWindowStarStore;
    const order = newWindowOrderStore;
    if (!newWindowStarOk(star) || !newWindowOrderOk(order)) return false;
    newWindowMark({ pinWay: "стор" });
    const fresh = `code:${id}`;
    const old = `code:${unpin}`;
    const before = newWindowOrder(order);
    const already = newWindowStarred(star, id);
    const donor = Boolean(unpin) && unpin !== id && newWindowStarred(star, unpin);
    // Порядок пишем, только если донор в нём есть (проверка WF85, D5): иначе
    // запись снятого ДО setStarred порядка выкинула бы свежий «code:<новый>».
    const next = before.includes(old) ? before.filter(key => key !== fresh).map(key => (key === old ? fresh : key)) : null;
    try {
      if (!already) star.getState().setStarred(id, true);
      if (donor) {
        star.getState().setStarred(unpin, false);
        if (next) order.getState().setPinnedOrder(next);
      }
    } catch {}
    // Проверка — по самим сторам: новый в звёздочках, донор снят, новый стоит
    // на месте донора (если донор был в порядке).
    const place = next ? next.indexOf(fresh) : -1;
    const done = await newWindowWait(() => {
      if (!newWindowStarred(star, id)) return null;
      if (!donor) return true;
      if (newWindowStarred(star, unpin)) return null;
      const now = newWindowOrder(order);
      return place < 0 || (now.indexOf(fresh) === place && now.filter(key => key === fresh).length === 1) ? true : null;
    }, NEW_WINDOW_MENU_MS, token);
    const at = newWindowOrder(order).indexOf(fresh);
    newWindowMark({
      pin: already ? "already" : (newWindowStarred(star, id) ? "ok" : "not-done"),
      pinPlace: at < 0 ? null : at,
    });
    if (unpin && unpin !== id) newWindowMark({ unpin: donor ? (done ? "ok" : "not-done") : "already" });
    return true;
  };
  const newWindowPinSteps = async (id, unpin, token) => {
    newWindowMark({ step: "pin" });
    if (await newWindowPinStore(id, unpin, token)) return;
    if (!newWindowLive(token)) return;
    newWindowMark({ pinWay: "меню" });
    newWindowMark({ pin: await newWindowPin(id, true, token) });
    if (!unpin || unpin === id || !newWindowLive(token)) return;
    newWindowMark({ unpin: await newWindowPin(unpin, false, token) });
  };

  // #8224: выбор закреплённых чатов Code. Заголовки — только подписи;
  // действие адресовано неизменным id из starredIds. Меню и порядок не пишем.
  const PIN_BULK_ID = "myclaude-pin-bulk";
  const PIN_BULK_ACTION = "data-myclaude-pin-action";
  const PIN_BULK_CHAT = "data-myclaude-pin-chat";
  const pinBulk = { node: null, phase: "closed", token: 0, store: null, rows: [], selected: new Set(),
    done: 0, skipped: 0, ignored: 0, pending: null, message: "", timers: new Map() };
  const pinBulkRead = store => {
    try {
      const value = store?.getState?.();
      if (!Array.isArray(value?.starredIds) || typeof value.setStarred !== "function") return null;
      const canonical = value.starredIds.map(id => typeof id === "string" ? id.replace(/^code:/, "") : "");
      const valid = id => /^local_[A-Za-z0-9_-]+$/.test(id);
      const ids = [...new Set(canonical.filter(valid))];
      return { ids, ignored: canonical.filter(id => !valid(id)).length, set: id => value.setStarred(id, false) };
    } catch { return null; }
  };
  const pinBulkLive = token => state.alive && isMainWindow() && token === pinBulk.token && pinBulk.node?.isConnected;
  const pinBulkStopTimers = () => {
    for (const [id, finish] of pinBulk.timers) { clearTimeout(id); finish("cancelled"); }
    pinBulk.timers.clear();
  };
  const pinBulkCancel = () => {
    const running = pinBulk.phase === "running";
    pinBulk.token += 1;
    pinBulkStopTimers();
    pinBulk.phase = running ? "cancelled" : "closed";
    pinBulk.message = `Откреплено ${pinBulk.done}.${pinBulk.pending ? " Не подтверждено: 1 — отправленная операция ещё может завершиться." : ""} Остальные оставлены.`;
    pinBulk.selected.clear();
    pinBulkPaint();
  };
  const pinBulkButton = (parent, operation, text, disabled = false) => {
    const button = document.createElement("button");
    button.type = "button";
    button.setAttribute(PIN_BULK_ACTION, operation);
    button.textContent = text;
    button.disabled = disabled;
    for (const [key, value] of Object.entries({ font: "inherit", color: "inherit", background: "var(--cds-alpha-2, #80808020)", border: "1px solid #80808050", "border-radius": "6px", padding: "4px 7px", cursor: disabled ? "default" : "pointer" })) button.style.setProperty(key, value);
    parent.appendChild(button);
    return button;
  };
  const pinBulkPaint = () => {
    const node = pinBulk.node;
    if (!node) return;
    const scroll = node.querySelector("[data-myclaude-pin-list]")?.scrollTop ?? 0;
    const focus = document.activeElement;
    const focusChat = focus?.getAttribute?.(PIN_BULK_CHAT);
    const focusAction = focus?.getAttribute?.(PIN_BULK_ACTION);
    while (node.childNodes.length) node.removeChild(node.childNodes[0]);
    if (pinBulk.phase === "closed") {
      const open = pinBulkButton(node, "open", "Выбрать чаты Code");
      if (focusChat || focusAction) open.focus();
      return;
    }
    const title = document.createElement("b"); title.textContent = "Закреплённые чаты Code"; node.appendChild(title);
    const message = document.createElement("div"); message.setAttribute("role", "status");
    message.textContent = pinBulk.phase === "loading" ? "Загружаю список…"
      : pinBulk.phase === "select" ? (pinBulk.rows.length ? `Выбрано: ${pinBulk.selected.size} из ${pinBulk.rows.length}` : "Закреплённых чатов Code нет")
      : pinBulk.phase === "running" ? `Открепляю… Готово: ${pinBulk.done}` : pinBulk.message;
    node.appendChild(message);
    if (pinBulk.phase === "select" && pinBulk.ignored) {
      const note = document.createElement("div"); note.textContent = `Другие закрепления пропущены: ${pinBulk.ignored}.`; node.appendChild(note);
    }
    if (pinBulk.phase === "select") {
      const list = document.createElement("div"); list.setAttribute("data-myclaude-pin-list", "");
      list.style.setProperty("max-height", "min(320px, 45vh)"); list.style.setProperty("overflow", "auto");
      for (const row of pinBulk.rows) {
        const label = document.createElement("label"); label.setAttribute("title", row.id); label.style.setProperty("display", "flex"); label.style.setProperty("gap", "5px");
        label.style.setProperty("align-items", "start"); label.style.setProperty("padding", "4px 0");
        const input = document.createElement("input"); input.type = "checkbox"; input.setAttribute(PIN_BULK_CHAT, row.id);
        input.checked = pinBulk.selected.has(row.id); input.setAttribute("aria-label", row.title);
        const text = document.createElement("span"); text.textContent = row.title; text.style.setProperty("overflow-wrap", "anywhere");
        label.append(input, text); list.appendChild(label);
      }
      node.appendChild(list); list.scrollTop = scroll;
    }
    const controls = document.createElement("div");
    controls.style.setProperty("display", "flex"); controls.style.setProperty("flex-wrap", "wrap"); controls.style.setProperty("gap", "5px");
    node.appendChild(controls);
    if (pinBulk.phase === "select") {
      const all = pinBulk.rows.length > 0 && pinBulk.selected.size === pinBulk.rows.length;
      pinBulkButton(controls, "all", all ? "Снять выбор" : "Выбрать все", !pinBulk.rows.length);
      pinBulkButton(controls, "unpin", `Открепить (${pinBulk.selected.size})`, !pinBulk.selected.size);
    } else if (["error", "done", "cancelled"].includes(pinBulk.phase)) pinBulkButton(controls, "open", "Обновить список");
    pinBulkButton(controls, "cancel", pinBulk.phase === "running" ? "Остановить" : ["select", "loading"].includes(pinBulk.phase) ? "Отмена" : "Закрыть");
    if (focusChat) node.querySelector(`[${PIN_BULK_CHAT}="${focusChat}"]`)?.focus();
    else if (focusAction) node.querySelector(`[${PIN_BULK_ACTION}="${focusAction}"]`)?.focus();
  };
  const pinBulkMount = () => {
    if (!isMainWindow()) return;
    if (pinBulk.node?.isConnected) return;
    if (pinBulk.phase !== "closed") { pinBulk.token += 1; pinBulkStopTimers(); pinBulk.phase = "closed"; }
    const pinned = document.querySelector(NEW_WINDOW_PINNED_SELECTOR);
    if (!pinned?.parentNode) return;
    pinBulk.node?.remove();
    const node = document.createElement("div"); node.id = PIN_BULK_ID;
    for (const [key, value] of Object.entries({ display: "flex", "flex-direction": "column", gap: "6px", padding: "6px 8px", font: "12px/1.4 -apple-system, system-ui, sans-serif", color: "var(--cds-text-primary, inherit)" })) node.style.setProperty(key, value);
    pinned.parentNode.insertBefore(node, pinned); pinBulk.node = node; pinBulkPaint();
  };
  const pinBulkOpen = async () => {
    if (!state.alive || !isMainWindow() || !pinBulk.node?.isConnected || pinBulk.phase === "running") return;
    const token = ++pinBulk.token;
    pinBulkStopTimers();
    Object.assign(pinBulk, { phase: "loading", rows: [], selected: new Set(), done: 0, skipped: 0, pending: null, message: "" });
    pinBulkPaint();
    let store = newWindowStarStore;
    if (!pinBulkRead(store)) store = await newWindowScanStores(newWindowToken, newWindowStarOk);
    if (!pinBulkLive(token)) return;
    const pins = pinBulkRead(store);
    if (!pins) { pinBulk.phase = "error"; pinBulk.message = "Не удалось прочитать закреплённые чаты. Можно обновить список."; pinBulkPaint(); return; }
    newWindowStarStore = store; pinBulk.store = store; pinBulk.ignored = pins.ignored;
    const names = new Map();
    for (const row of document.querySelectorAll(`${NEW_WINDOW_PINNED_SELECTOR} [data-row-key]`)) {
      const key = row.getAttribute("data-row-key");
      if (typeof key === "string" && key.startsWith("code:")) names.set(key.slice(5), newWindowRowTitle(row));
    }
    const counts = new Map();
    for (const id of pins.ids) { const name = names.get(id) || ""; counts.set(name, (counts.get(name) || 0) + 1); }
    pinBulk.rows = pins.ids.map(id => {
      const name = names.get(id) || "";
      if (name && counts.get(name) === 1) return { id, title: name };
      const tail = id.slice(6);
      let length = Math.min(4, tail.length);
      while (length < tail.length && pins.ids.some(other => other !== id && other.slice(6).slice(-length) === tail.slice(-length))) length += 1;
      return { id, title: `${name || "Название недоступно"} · …${tail.slice(-length)}` };
    });
    pinBulk.phase = "select"; pinBulkPaint();
    pinBulk.node.querySelector(`[${PIN_BULK_CHAT}]`)?.focus();
  };
  const pinBulkAck = (token, store, id, outcome, started) => new Promise(resolve => {
    const check = () => {
      if (!pinBulkLive(token)) { resolve("cancelled"); return; }
      const pins = store === newWindowStarStore ? pinBulkRead(store) : null;
      if (!pins || outcome() === "error") { resolve("error"); return; }
      if (now() - started >= 2000) { resolve("timeout"); return; }
      if (outcome() === "ok" && !pins.ids.includes(id)) { resolve("ok"); return; }
      const timer = setTimeout(() => { pinBulk.timers.delete(timer); check(); }, 100);
      pinBulk.timers.set(timer, resolve);
    };
    check();
  });
  const pinBulkRun = async () => {
    if (pinBulk.phase !== "select" || !pinBulk.selected.size) return;
    const ids = pinBulk.rows.filter(row => pinBulk.selected.has(row.id)).map(row => row.id);
    const store = pinBulk.store;
    const token = ++pinBulk.token;
    pinBulk.phase = "running"; pinBulkPaint();
    for (const id of ids) {
      if (!pinBulkLive(token)) return;
      const pins = store === newWindowStarStore ? pinBulkRead(store) : null;
      if (!pins) { pinBulk.phase = "error"; pinBulk.message = `Список изменился. Откреплено ${pinBulk.done}, остальные оставлены.`; break; }
      if (!pins.ids.includes(id)) { pinBulk.skipped += 1; continue; }
      let outcome = "pending";
      pinBulk.pending = id;
      const started = now();
      // Оптимистичное удаление из стора ещё не успех: thenable тоже должен
      // завершиться успешно. Оба подтверждения ждём в одном пределе 2 секунд.
      try {
        const result = pins.set(id);
        if (result && typeof result.then === "function") Promise.resolve(result).then(
          () => { outcome = "ok"; }, () => { outcome = "error"; },
        );
        else outcome = "ok";
      } catch { outcome = "error"; }
      const result = await pinBulkAck(token, store, id, () => outcome, started);
      if (!pinBulkLive(token)) return;
      if (result !== "ok") {
        pinBulk.phase = "error";
        pinBulk.message = `Не удалось подтвердить открепление «${pinBulk.rows.find(row => row.id === id)?.title || "Название недоступно"}». Откреплено ${pinBulk.done}. Не подтверждено: 1 — отправленная операция ещё может завершиться. Остальные оставлены.`;
        break;
      }
      pinBulk.pending = null;
      pinBulk.done += 1;
      pinBulk.selected.delete(id);
      pinBulkPaint();
    }
    if (pinBulk.phase === "running") {
      pinBulk.phase = "done";
      pinBulk.message = `Откреплено ${pinBulk.done}.${pinBulk.skipped ? ` Уже были откреплены: ${pinBulk.skipped}.` : ""}`;
    }
    pinBulkPaint();
  };
  const onPinBulkClick = event => {
    if (event.isTrusted === false || !pinBulk.node?.contains(event.target)) return;
    const button = event.target?.closest?.(`[${PIN_BULK_ACTION}]`);
    if (!button || button.disabled) return;
    event.preventDefault(); event.stopImmediatePropagation();
    const operation = button.getAttribute(PIN_BULK_ACTION);
    if (operation === "open") { void pinBulkOpen(); return; }
    if (operation === "cancel") { pinBulkCancel(); return; }
    if (operation === "unpin") { void pinBulkRun(); return; }
    if (operation === "all" && pinBulk.phase === "select") {
      pinBulk.selected = pinBulk.selected.size === pinBulk.rows.length ? new Set() : new Set(pinBulk.rows.map(row => row.id));
      pinBulkPaint();
    }
  };
  const onPinBulkChange = event => {
    const id = event.target?.getAttribute?.(PIN_BULK_CHAT);
    if (event.isTrusted === false || pinBulk.phase !== "select" || !pinBulk.node?.contains(event.target)
      || !pinBulk.rows.some(row => row.id === id)) return;
    if (event.target.checked) pinBulk.selected.add(id); else pinBulk.selected.delete(id);
    pinBulkPaint();
  };
  const onPinBulkKey = event => {
    if (event.key !== "Escape" || pinBulk.phase === "closed" || !pinBulk.node?.isConnected) return false;
    event.preventDefault(); event.stopImmediatePropagation(); pinBulkCancel(); return true;
  };
  track(() => { pinBulk.token += 1; pinBulkStopTimers(); pinBulk.node?.remove(); pinBulk.node = null; });

  // Команда «В отдельное окно», контракт WF13, с WF41 — необязательные chat и
  // name ПОСЛЕ y: {id, action:"popout-window", at, scope:"window", title,
  // match?, x, y, chat?, name?}. Тот же стор и тот же openPopout, только по уже
  // открытому чату — мгновенно и без сообщения.
  //
  // Поле chat называет ЧУЖОЙ разговор: главное окно выносит его в отдельное
  // окно, к себе не открывая (так «Вернуть эти чаты» расставляет по ячейкам то,
  // чего на экране нет). Здесь это ГРУЗ команды, а не адрес: у addressed() поле
  // chat значит «эта страница и есть тот чат» (WF29), и команда на закрытый
  // разговор не досталась бы никому — адрес считаем без него.
  //
  // Отказы у неё видимые, все три (WF19): нет чата (домашний экран /epitaxy —
  // в адресе нет local_<uuid>), окно уже попап и стор не нашёлся. Молчащий пункт
  // читается как сломанный — тот же довод, что у плашек «Нового окна». У
  // названного чата плашки нет: команду шлёт не рука Элвиса, а приложение, и
  // ответ ему — состояние chat-missing, из которого выйдет пустая ячейка.
  const runPopoutCommand = async detail => {
    // Отвечаем только на страницах Claude: в оболочке (file://…/main_window), на
    // логине и в браузерной панели плашке делать нечего.
    if (!themable || !addressed({ ...detail, chat: null })) return false;
    // Координаты — числа, а не строки (разбор у runNewWindowCommand).
    const x = detail?.x;
    const y = detail?.y;
    if (detail?.scope !== "window" || !Number.isFinite(x) || !Number.isFinite(y)) {
      newWindowMark({ state: "bad-command", step: null, ...(state.newWindow?.busy ? {} : { actual: null }) });
      return false;
    }
    // Окно «Open in new window» (about:blank) — это и есть отдельное окно: чат
    // в нём уже вынесен, второго openPopout у него нет (стор попапов живёт на
    // claude.ai). Приложение адресует пункт главному окну, но нажимают его и
    // здесь — отвечаем плашкой, а не молчанием.
    if (!isMainWindow()) {
      newWindowMark({ state: "already", step: "popout", id: null, actual: null, runs: newWindowRuns() });
      newWindowNote(NEW_WINDOW_NOTE_ALREADY);
      return false;
    }
    const token = newWindowToken;
    const chat = typeof detail?.chat === "string" ? detail.chat.trim() : "";
    // Имя режем так же, как строка сайдбара (newWindowRowTitle), — заголовок
    // окна и ключ темы обязаны совпасть.
    const name = typeof detail?.name === "string" ? detail.name.trim().slice(0, 200) : "";
    // Назвали чат — выносим его, не назвали — разговор этого окна, как в WF13.
    const id = chat || newWindowSessionId();
    // Запись в state.newWindow одна на оба пункта: она про ПОСЛЕДНИЙ запуск
    // раздела. Признак занятости чужого прогона мы не трогаем — вынести
    // текущий чат можно и пока «Новое окно» ещё ждёт свою сессию.
    newWindowMark({ state: "run", step: "popout", id: id || null,
      ...(state.newWindow?.busy ? {} : { actual: null }), runs: newWindowRuns() });
    if (!id) {
      newWindowMark({ state: "no-chat" });
      newWindowNote(NEW_WINDOW_NOTE_CHAT);
      return false;
    }
    // Заголовок будущего окна считаем поздно, перед самым openPopout: строка
    // сайдбара могла дорисоваться за время поиска стора. У названного чата
    // windowTitle() не годится вовсе — это имя ДРУГОГО, открытого сейчас
    // разговора, и окно уехало бы с чужим именем.
    const popoutTitle = () => (chat
      ? (name || newWindowRowTitle(newWindowRow(id, true)))
      : (newWindowRowTitle(newWindowRow(id, true)) || windowTitle()));
    const store = await newWindowFindStore(token);
    if (!newWindowLive(token)) return false;
    if (store) {
      newWindowMark({ actual: null });
      try { newWindowOpenPopout(store, id, popoutTitle(), x, y); }
      catch (error) {
        newWindowMark({ state: "popout-failed", error: newWindowError(error) });
        newWindowNote(NEW_WINDOW_NOTE_POPOUT);
        return false;
      }
      newWindowMark({ state: "ok" });
      return true;
    }
    if (!chat) {
      newWindowMark({ state: "no-store" });
      newWindowNote(NEW_WINDOW_NOTE_POPOUT);
      return false;
    }
    // Запасной путь (WF41): стор ищется по загруженным чанкам, а на домашнем
    // экране чанка чата может и не быть. Тогда открываем названный разговор его
    // же строкой сайдбара — это штатная навигация приложения, после неё чанк
    // есть, — и выносим уже текущий чат. Строки нет или чат по ней не открылся:
    // окна НЕ будет (chat-missing), нового чата вместо старого не заводим —
    // пустая ячейка честнее подмены (#5455).
    // Запасной путь уводит ГЛАВНОЕ окно на чужой чат: пока идём, «Новое окно» не
    // стартует, а chats() молчит (иначе окно на секунду опознается чужим проектом).
    if (state.newWindow?.busy === true) { newWindowMark({ state: "busy" }); newWindowNote(NEW_WINDOW_NOTE_BUSY, true); return false; }
    const row = newWindowRow(id, true);
    if (!row) { newWindowMark({ state: "chat-missing", step: "row" }); return false; }
    const prev = location.pathname;
    // Домашний экран прежним разговором не считается: возвращаться будем
    // историей, а не по строке сайдбара (её у /epitaxy нет).
    const prevId = prev === NEW_WINDOW_HOME_PATH ? "" : newWindowSegment(prev);
    const before = navMark();
    newWindowMark({ step: "row", busy: true });
    // Клик по строке и та же секунда на смену адреса, что у возврата: это одна
    // и та же навигация роутера, только в другую сторону.
    newWindowRowClick(row);
    const here = await newWindowWait(() => (newWindowSessionId() === id ? true : null), NEW_WINDOW_BACK_MS, token);
    if (!newWindowLive(token)) return false;
    let done = false;
    if (!here) newWindowMark({ state: "chat-missing", step: "row" });
    else {
      newWindowMark({ step: "store" });
      const opened = await newWindowFindStore(token);
      if (!newWindowLive(token)) return false;
      if (!opened) newWindowMark({ state: "no-store" });
      else {
        newWindowMark({ step: "popout" });
        try { newWindowOpenPopout(opened, id, popoutTitle(), x, y); done = true; }
        catch (error) { newWindowMark({ state: "popout-failed", error: newWindowError(error) }); }
      }
      if (done) newWindowMark({ state: "ok" });
      else newWindowNote(NEW_WINDOW_NOTE_POPOUT);
    }
    // Возврат главного окна — ВСЕГДА, вышло вынести или нет: чат Элвиса мы
    // увели отсюда своими руками (у newWindowBack на месте — «stay»).
    newWindowMark({ step: "back" });
    await newWindowBack(prev, prevId, before, token);
    if (token === newWindowToken) newWindowMark({ busy: false });
    return done;
  };
  // Команда «Чат в главное окно» (WF108, #8148): {id, action:"main-chat", at,
  // scope:"window", title, match?, x, y, chat}. Исполняет только главное окно:
  // открывает названный чат у себя (строкой сайдбара, нет строки — роутером) и
  // выносит прежний свой чат отдельным окном в точку x,y — тем же стором, что
  // «В отдельное окно». Окно названного чата закрыло приложение ДО команды:
  // чат в двух окнах сразу — всегда ошибка (#7727). chat здесь — ГРУЗ, как у
  // popout-window, адрес считаем без него. Исход — state.newWindow: already
  // (чат уже тут), ok (id — вынесенный прежний чат, null — выносить было нечего:
  // домашний экран), chat-missing (не открылся — главное окно не сдвинулось),
  // no-store / popout-failed (чат открыт тут, прежний не вынесся), busy.
  const runMainChatCommand = async detail => {
    if (!themable || !addressed({ ...detail, chat: null }) || !isMainWindow()) return false;
    const x = detail?.x;
    const y = detail?.y;
    const id = typeof detail?.chat === "string" ? detail.chat.trim() : "";
    if (detail?.scope !== "window" || !Number.isFinite(x) || !Number.isFinite(y) || !id.startsWith("local_")) {
      newWindowMark({ state: "bad-command", step: null, ...(state.newWindow?.busy ? {} : { actual: null }) });
      return false;
    }
    if (state.newWindow?.busy === true) { newWindowMark({ state: "busy" }); return false; }
    const token = newWindowToken;
    const prevId = newWindowSessionId();
    newWindowMark({ state: "run", step: "main", id, actual: null, runs: newWindowRuns() });
    if (prevId === id) { newWindowMark({ state: "already", id: null }); return true; }
    // Имя прежнего чата — строкой сайдбара ДО ухода: после перехода заголовок окна уже чужой.
    const prevTitle = prevId ? (newWindowRowTitle(newWindowRow(prevId, true)) || windowTitle()) : "";
    newWindowMark({ step: "row", busy: true });
    const row = newWindowRow(id, true);
    const moved = row ? (newWindowRowClick(row), true) : navRouterTo(`${NEW_WINDOW_HOME_PATH}/${id}`);
    const here = moved &&
      await newWindowWait(() => (newWindowSessionId() === id ? true : null), NEW_WINDOW_MAIN_CHAT_MS, token);
    if (!newWindowLive(token)) return false;
    const finish = patch => { if (token === newWindowToken) newWindowMark({ ...patch, busy: false }); };
    if (!here) { finish({ state: "chat-missing", id: null }); return false; }
    if (!prevId) { finish({ state: "ok", id: null }); return true; }
    newWindowMark({ step: "store" });
    const store = await newWindowFindStore(token);
    if (!newWindowLive(token)) return false;
    if (!store) { finish({ state: "no-store", id: prevId }); return false; }
    try { newWindowOpenPopout(store, prevId, prevTitle, x, y); }
    catch (error) {
      finish({ state: "popout-failed", id: prevId, error: newWindowError(error) });
      return false;
    }
    finish({ state: "ok", id: prevId });
    return true;
  };
  // Обе команды асинхронные: отказ промиса не должен всплывать в консоль страницы.
  const newWindowStart = (run, detail) => { try { run(detail).catch(() => {}); } catch {} };
  // «Новое окно» и «В отдельное окно» (раздел 12б): чем кончился последний
  // запуск, на каком он шаге, какая сессия уехала в окно, занята ли кнопка
  // и как вернулось главное окно.
  statusPart("newWindow", () => state.newWindow ? { ...state.newWindow } : null);
  HATCH && Object.assign(HATCH, { pinBulk, newWindowModelMatch, newWindowModelName, newWindowEffortShown, newWindowRow, newWindowSegment, newWindowSessionId,
    newWindowAtHome, newWindowStoreOk, setModuleImporter, newWindowPaintChat, newWindowPickFolder,
    newWindowFolderPath, newWindowFolderName, newWindowFolderStoreOk, newWindowNameField, newWindowRename,
    NEW_WINDOW_NOTE_CREATED });

