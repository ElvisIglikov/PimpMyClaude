  // ---- 5а. Размер текста только в поле ввода (Dictator, #6186) -------------
  // Отдельная настройка: size.question принадлежит отправленным вопросам.
  // Один размер на все окна (WF107, #8126, К2): localStorage общий у окон Claude,
  // событие storage ставит новое значение в остальных окнах сразу. Приложение
  // шлёт команду composer-font (px или null); колесо Диктатора (⌃⌥⌘[ ]) и загрузка
  // страницы говорят значение приложению запросом /composer-font — для возврата
  // после переустановки Claude (px=none — приложение пришлёт своё зеркало командой).
  // Примерки размера поля нет (WF248 П2): её слало только меню жёлтой кнопки, а его сняли (лист 48 · 2.1).
  const COMPOSER_FONT_KEY = "myclaude-composer-font-size-v1";
  const COMPOSER_FONT_MIN = 11;
  const COMPOSER_FONT_MAX = 32;
  const composerFontOk = value => (Number.isInteger(value) && value >= COMPOSER_FONT_MIN &&
    value <= COMPOSER_FONT_MAX ? value : undefined);
  const readComposerFont = () => {
    try {
      const raw = localStorage.getItem(COMPOSER_FONT_KEY);
      return raw == null ? null : (composerFontOk(Number(raw)) ?? null);
    } catch { return null; }
  };
  let composerFontPx = readComposerFont();
  // loaded — запрос загрузки ушёл; pinged — сколько запросов ушло приложению.
  const composerFontState = { loaded: false, pinged: 0 };
  const COMPOSER_FONT_MARK = "data-myclaude-composer-font";
  // findEditor имеет геометрический fallback на чужие поля. Здесь он не годится:
  // нужен живой ProseMirror внутри известного блока ввода Claude.
  const isFontComposer = editor => editor?.isConnected &&
    editor.matches('.ProseMirror[contenteditable="true"]') &&
    !!editor.closest('.epitaxy-prompt, [data-cds="ChatComposer"]');
  let composerFontStyle = null;
  const clearComposerFont = () => {
    if (!composerFontStyle) return;
    const { editor, previous, priority, applied, previousMark } = composerFontStyle;
    // Чужую более позднюю правку стиля не откатываем.
    if (editor.style.getPropertyValue("font-size") === applied) {
      if (previous) editor.style.setProperty("font-size", previous, priority);
      else editor.style.removeProperty("font-size");
    }
    if (editor.getAttribute(COMPOSER_FONT_MARK) === "true") {
      if (previousMark == null) editor.removeAttribute(COMPOSER_FONT_MARK);
      else editor.setAttribute(COMPOSER_FONT_MARK, previousMark);
    }
    composerFontStyle = null;
  };
  const applyComposerFont = editor => {
    const px = composerFontPx;
    if (!themable || px == null || !isFontComposer(editor)) {
      clearComposerFont();
      return;
    }
    if (composerFontStyle?.editor !== editor) {
      clearComposerFont();
      composerFontStyle = {
        editor, previous: editor.style.getPropertyValue("font-size"),
        previousMark: editor.getAttribute(COMPOSER_FONT_MARK),
        priority: typeof editor.style.getPropertyPriority === "function"
          ? editor.style.getPropertyPriority("font-size") : "", applied: "",
      };
    }
    if (editor.getAttribute(COMPOSER_FONT_MARK) !== "true") editor.setAttribute(COMPOSER_FONT_MARK, "true");
    const size = `${px}px`;
    if (editor.style.getPropertyValue("font-size") !== size) {
      editor.style.setProperty("font-size", size, "important");
    }
    composerFontStyle.applied = size;
  };
  track(clearComposerFont);
  const onComposerFontKey = event => {
    if (!themable || !state.alive || !document.hasFocus() || event.defaultPrevented || event.isComposing ||
        !event.ctrlKey || !event.altKey || !event.metaKey || event.shiftKey ||
        !["BracketLeft", "BracketRight"].includes(event.code)) return false;
    const editor = state.editor;
    if (!isFontComposer(editor) || editor !== findEditor() || overlayOpen()) return false;
    const current = composerFontPx ?? parseFloat(getComputedStyle(editor).getPropertyValue("font-size"));
    if (!Number.isFinite(current)) return false;
    composerFontPx = Math.max(COMPOSER_FONT_MIN, Math.min(COMPOSER_FONT_MAX,
      Math.round(current) + (event.code === "BracketRight" ? 1 : -1)));
    applyComposerFont(editor);
    try { localStorage.setItem(COMPOSER_FONT_KEY, String(composerFontPx)); } catch {}
    composerFontPing();
    event.preventDefault();
    event.stopImmediatePropagation();
    scheduleLayout();
    return true;
  };
  // GET /composer-font?px=<N|none>&chat=<id> (К2): запрос CORS без credentials,
  // дошёл — и ладно. Без id чата не шлём: приложение без chat ничего не делает.
  const composerFontPing = () => {
    if (!themable || typeof fetch !== "function") return false;
    let chat = null;
    try { chat = myChatId(); } catch { chat = null; }
    if (typeof chat !== "string" || !chat) return false;
    try {
      fetch(`http://127.0.0.1:${HTML_CHROME_PORT}/composer-font?px=${composerFontPx ?? "none"}` +
        `&chat=${encodeURIComponent(chat)}`, { mode: "cors", credentials: "omit", cache: "no-store" }).catch(() => {});
    } catch { return false; }
    composerFontState.pinged += 1;
    composerFontState.loaded = true;
    return true;
  };
  // Один раз за загрузку, как только известен id чата (попап узнаёт его позже);
  // колесо раньше этого — тоже ответ, второго не нужно. fetch нет — и не будет.
  const composerFontLoadPing = () => {
    if (composerFontState.loaded) return;
    if (typeof fetch !== "function") composerFontState.loaded = true;
    else composerFontPing();
  };
  // Команда composer-font (К2). px — целое 11…32 или null («Как у Claude»),
  // прочее — мусор, ничего. Команда с preview:true (её слало снятое меню; старое
  // приложение) — мимо: иначе размер, мимо которого проехала мышь, лёг бы в хранилище.
  const runComposerFontCommand = detail => {
    if (!themable || !detail || typeof detail !== "object" || !("px" in detail) || detail.preview === true) return false;
    const px = detail.px === null ? null : composerFontOk(detail.px);
    if (px === undefined) return false;
    composerFontPx = px;
    try {
      if (px == null) localStorage.removeItem(COMPOSER_FONT_KEY);
      else localStorage.setItem(COMPOSER_FONT_KEY, String(px));
    } catch {}
    applyComposerFont(state.editor);
    scheduleLayout();
    return true;
  };
  // Колесо или команда в другом окне — сразу и здесь. key null — хранилище очищено целиком.
  const onComposerFontStorage = event => {
    if (!themable || (event?.key !== COMPOSER_FONT_KEY && event?.key !== null)) return;
    composerFontPx = readComposerFont();
    applyComposerFont(state.editor);
    scheduleLayout();
  };
  // Размер шрифта поля (WF107, К2): px — что на поле сейчас (null — как у
  // Claude), pinged — запросов приложению.
  statusPart("composerFont", () => ({ px: composerFontPx, pinged: composerFontState.pinged }));

