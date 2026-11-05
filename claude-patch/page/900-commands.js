  // ---- 15. Команды снаружи ------------------------------------------------
  // command.json доставляется лоадером во ВСЕ страницы разом, поэтому команду
  // берёт только окно под фокусом — и только то, где вообще есть поле ввода
  // (в оболочке file://…/main_window и на логине его нет).
  const onCommand = event => {
    const detail = event?.detail;
    const action = typeof detail?.action === "string" ? detail.action : "";
    if (!action || !state.alive) return;
    // «Прокрутить» — исключение: она адресована всем окнам, а не одному под
    // фокусом, и поля ввода ей не нужно — нужна лента. На чужой странице ленты
    // нет, и команда там тихо ничего не делает.
    if (action === "scroll") { runScroll(); return; }
    // «Тема» — тоже до проверки поля ввода: красить окно можно и пока composer
    // ещё не нашёлся, а окно с scope:"all" красится вообще любое.
    if (action === "theme") { try { runThemeCommand(detail); } catch {} return; }
    // Размер шрифта в поле (WF107, К2) — всем окнам, примерка — одному; поля ввода
    // команде ждать не нужно: значение ляжет, поле возьмёт его при появлении.
    if (action === "composer-font") { try { runComposerFontCommand(detail); } catch {} return; }
    // Вид и размер счёта отправки (WF114, раздел 12у) — всем окнам, показ — одному.
    if (action === "send-delay") { try { runSendDelayCommand(detail); } catch {} return; }
    if (action === "send-look") { try { runSendLookCommand(detail); } catch {} return; }
    // Притемнение попапов (WF113, #8256, раздел 12и¹) — всем окнам, поля ввода не нужно.
    if (action === "dim") { try { runDimCommand(detail); } catch {} return; }
    // «Сводка» (scope:"all") — приложение раз в минуту присылает status.md
    // проектов. Поля ввода ей не нужно: она ложится в память окна и всплывает в
    // подсказке полосы прогресса (раздел 2б). Стоит ДО отмены примерки нарочно:
    // сводка приходит сама по часам и меню не закрывает — иначе она сбивала бы
    // предпросмотр темы прямо под рукой у Элвиса.
    if (action === "status") { try { runStatusCommand(detail); } catch {} return; }
    // «Живые цвета» (раздел 2в) — по тем же доводам, что тема: команда адресована
    // всем окнам разом (scope:"all"), поля ввода ей не нужно, а своё окно
    // страница отбирает сама. И до отмены примерки: гасить её здесь незачем.
    if (action === "live-colors") { try { runLiveCommand(detail); } catch {} return; }
    // «Возврат тем» (scope:"all", WF35) — по тем же доводам и ДО отмены примерки:
    // команда приезжает сама, по часам приложения, а не из меню, и гасить ею
    // подменю под рукой у Элвиса нельзя.
    if (action === "themes-restore") { try { runThemesRestoreCommand(detail); } catch {} return; }
    // «Прятать инструменты» (#7976, раздел 3а) — настройка на все окна, поля ввода ей не нужно.
    if (action === "hide-tools") { hideToolsSet(String(detail?.on) === "true"); return; }
    // «Прятать код и планы» (#7976, раздел 12т³, К-HC) — настройка на все окна, как hide-tools; без команды — выключено.
    if (action === "hide-code") { hideCodeSet(String(detail?.on) === "true"); return; }
    // «Чистые ответы» (#9398, раздел 3а¹, К-CA) — настройка на все окна, как hide-tools; без команды — включено.
    if (action === "clean-answers") { cleanAnswersSet(String(detail?.on) === "true"); return; }
    // Выключка по ширине (#9168, К-J1) — настройка на все окна, как hide-tools.
    if (action === "text-justify") { textJustifySet(String(detail?.on) === "true"); return; }
    // «Bypass permissions во всех чатах» (#9060, раздел 12с¹) — настройка на все окна, как hide-tools.
    if (action === "bypass-chats") { bypassSet(String(detail?.on) === "true"); return; }
    // «Закреплённые» (#8743, раздел 2е) — настройка на все окна, поля ввода ей не нужно.
    if (action === "pinned-look") { runPinnedLookCommand(detail); return; }
    if (action === "auto-allow-once") { autoAllowSet(detail?.on); return; }
    if (action === "auto-continue") { autoSet(detail); return; }
    // Повтор при ошибке сервера (#6936, раздел 12е², К-AR) — настройка на все окна, как hide-tools.
    if (action === "auto-retry") { autoRetrySet(detail); return; }
    // Корень автодоверия (К WF108) — на все окна, поля ввода не нужно.
    if (action === "trust-root") { runTrustRootCommand(detail); return; }
    // Режим кружка-микрофона (К4, #7054) — тоже на все окна.
    if (action === "mic") {
      micModeSet(detail?.mode);
      if (micMode() !== "dictator") micState.dictating = false;
      // Значок переезжает сразу: в режиме Диктатора он есть и в открытом поле.
      scheduleLayout();
      return;
    }
    // Отказ Диктатора (WF92): идёт во все страницы, своё окно узнаёт себя само.
    if (action === "mic-refused") { try { micRefused(detail); } catch {} return; }
    // Фильтр чата в Pimp Viewer (К-V2, WF97, раздел 12п): идёт во все страницы,
    // каждая зажигает или гасит свою «Галерею» сама.
    if (action === "viewer-chat") { try { galleryFromViewer(detail); } catch {} return; }
    // Числа файлов по чатам (К-V7): кнопка видна, только если у чата есть файлы.
    if (action === "viewer-counts") { try { galleryFromCounts(detail); } catch {} scheduleLayout(); return; }
    // Панель материалов слева (К-DOCK, WF277, раздел 12п⁴): {on:true|false} — как кнопка «PMP» у «Show sidebar»;
    // берёт только главное окно. Шлёт её человек на гейте (живая проверка без клика), приложение — нет.
    if (action === "dock") { try { dockCommand(detail); } catch {} return; }
    // «Отправь текст в чат» (раздел 12т¹, WF103): окно отбирает себя по chat само,
    // поле ищет само (нет — no-field), до примерки.
    if (action === "send-text") { try { runSendText(detail); } catch {} return; }
    // Число токенов перечитки остывшего чата (раздел 12у, WF106): только свой
    // чат и только во время счёта — страница отбирает сама.
    // Тем же числом — дуга кружка (раздел 12з², #10317).
    if (action === "chat-context") { try { sendDelayContext(detail); } catch {} try { usageContextTake(detail); } catch {} try { ctxRingPaint(); } catch {} return; }
    // Фото с AirDrop (раздел 12т², #9358): всем окнам; ⌘V придёт только в окно Рика.
    if (action === "airdrop-guard") { try { airdropArm(detail); } catch {} return; }
    // Неизвестная или снятая команда старого приложения не должна отменять примерку.
    if (!["new-window", "popout-window", "main-chat", "collapse", "expand", "cashout", "workflow"].includes(action)) return;
    // Команда, адресующая прежний чат, исполняется только после возврата обхода.
    if (["new-window", "popout-window", "main-chat", "cashout", "workflow"].includes(action)
      && roamDefer(() => onCommand(event))) return;
    // Оставшиеся команды меню закрывают примерку: меню ушло, выбора темы не было.
    if (themeState.previewing) {
      try { restoreTheme(true); themeState.previewing = false; themeState.previewLayers = []; } catch {}
    }
    // «Новое окно» и «В отдельное окно» — ДО проверки поля ввода: композер
    // страница дожидается сама (после ⌘N он ещё не тот, что в state.editor), и
    // команда не должна умирать молча на окне без поля. Обе адресованы одному
    // главному окну — отбор внутри (isMainWindow + addressed).
    if (action === "new-window") { newWindowStart(runNewWindowCommand, detail); return; }
    if (action === "popout-window") { newWindowStart(runPopoutCommand, detail); return; }
    if (action === "main-chat") { newWindowStart(runMainChatCommand, detail); return; }
    if (!state.editor?.isConnected) return;
    // «Свернуть»/«Развернуть» — тоже на все окна (ElvisOS: «убирает поле ввода во
    // всех окнах»; слово Элвиса 03.09 13:30). Только «Обкэшить» адресована окну в фокусе.
    if (action === "collapse") { setStage(STAGE_COLLAPSED); return; }
    if (action === "expand") { setStage(STAGE_NORMAL); return; }
    // «Обкэшить» адресована одному окну — с WF37 через общий addressed()
    // (match → chat → заголовок/фокус, #5535), а не своей проверкой заголовка.
    // Заголовок один на два окна разом: главное окно с открытым названным чатом
    // и безымянный попап носят его одинаково, и команда уходила веером им обоим
    // (критик плана, блокер 3).
    if (action === "cashout") {
      if (addressed(detail)) runCashout(detail);
      return;
    }
    // «Workflow» — тоже одному окну (заголовок из AX, запасной критерий — фокус):
    // текст запуска ложится в поле ввода этого окна и не отправляется.
    if (action === "workflow" && addressed(detail)) { try { runWorkflowCommand(detail); } catch {} }
    // Неизвестные команды игнорируем молча: их может слать не только наш модуль.
  };

