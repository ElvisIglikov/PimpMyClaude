  // ---- 17. Снятие экземпляра ---------------------------------------------
  // CSS новых фич (lateRules) — в тот же <style> после RULES: их файлы стоят ниже раздела 4.
  if (lateRules.length) style.textContent = RULES.concat(lateRules).join("\n");

  const dispose = () => {
    state.alive = false;
    // Штатная высота редактора возвращается здесь: снимаем переменную, атрибуты
    // и свёрнутость. Дальше по реестру уходят подписки, наблюдатель, таймеры,
    // <style> и сама полоска.
    try { clearResizer(); } catch {}
    try {
      for (const node of document.querySelectorAll(`[${EDITOR_ROOT_ATTRIBUTE}],[${EDITOR_ATTRIBUTE}],[${BLOCK_ATTRIBUTE}],[${RING_PATH_ATTRIBUTE}],[${RING_ATTRIBUTE}]`)) {
        node.removeAttribute(EDITOR_ROOT_ATTRIBUTE);
        node.removeAttribute(EDITOR_ATTRIBUTE);
        node.removeAttribute(BLOCK_ATTRIBUTE);
        // Метки кружка в режиме чтения (#6737): без них ветка осталась бы с
        // absolute-кружком и спрятанными соседями уже без наших правил.
        node.removeAttribute(RING_PATH_ATTRIBUTE);
        node.removeAttribute(RING_ATTRIBUTE);
        try { node.style.removeProperty(HEIGHT_VARIABLE); } catch {}
      }
    } catch {}
    if (state.dragging) {
      state.dragging = false;
      try {
        document.documentElement.style.cursor = "";
        document.documentElement.style.userSelect = "";
      } catch {}
    }
    for (const undo of undoList.splice(0).reverse()) { try { undo(); } catch {} }
  };

  // status() — для probe на гейте и приложения (ChatProbe читает send, newWindow, cashout, attention.want).
  // Поле регистрирует файл своей фичи: statusPart("ключ", () => значение) — WF248 П4. Порядок полей
  // прежний (STATUS_ORDER; его сверяет tests/status-order.test.mjs), новое поле встаёт в конец само.
  const STATUS_ORDER = [
    "version", "url", "stage", "height", "ceiling", "natural", "cssOk", "cssViolations", "watching", "editor",
    "shell", "composerBlock", "composerFont", "composerImageUndo", "attachUndo", "modelRow", "collapsedNodes",
    "hideTools", "cleanAnswers", "pinnedLook", "jumps", "escapesBlocked", "handleVisible", "superVisible",
    "superBottomVisible", "handleCovered", "mic", "gallery", "pmp", "wide", "restored", "autoAllow", "trust",
    "layout", "run", "send", "sendDelay", "corner", "head", "htmlChrome", "photo", "bypassChats", "mention",
    "openInChrome", "usage", "limits", "working", "autoContinue", "layoutRuns", "mutationBatches", "mutationSkipped",
    "scrollRuns", "timeRuns", "timeWatched", "cashout", "progress", "statusFeed", "workflow", "newWindow",
    "continue", "chat", "restore", "chatKey", "sessionKey", "theme", "font", "size", "wait", "attention", "dim",
    "say", "nazh", "folds", "userFold", "read", "seen", "heic", "chapters", "work", "signal", "look", "lookStill",
    "scrollFades", "live", "preview", "raw", "rawMain",
  ];
  const statusView = () => {
    const view = {};
    for (const key of STATUS_ORDER) if (statusParts.has(key)) view[key] = statusParts.get(key)();
    for (const [key, get] of statusParts) if (!(key in view)) view[key] = get();
    return view;
  };
  statusPart("version", () => VERSION);
  statusPart("url", () => location.href);
  statusPart("stage", () => state.stage);
  statusPart("height", () => state.height);
  statusPart("ceiling", () => state.ceiling);
  statusPart("natural", () => state.natural);
  statusPart("cssOk", () => state.cssOk);
  statusPart("cssViolations", () => state.cssViolations);
  statusPart("watching", () => state.watching);
  statusPart("editor", () => Boolean(state.editor?.isConnected));
  statusPart("shell", () => Boolean(state.shell?.isConnected));
  statusPart("composerBlock", () => Boolean(state.composerBlock?.isConnected));
  statusPart("modelRow", () => Boolean(state.modelRow?.isConnected));
  statusPart("collapsedNodes", () => state.collapsedNodes.length);
  // Сторож Esc (раздел 16): сколько Esc проглочено — не дошли до Claude и не остановили ход.
  statusPart("escapesBlocked", () => state.escapesBlocked || 0);
  statusPart("handleCovered", () => state.handleCovered);
  // Сколько раз сторож возвращал свои узлы в body (#6766).
  statusPart("restored", () => state.restored);
  // Широкий вид (раздел 2г, WF65): включён ли, ширина панели чата и правой
  // колонки в точках (в узком виде колонки нет — null); sideMin (WF68) —
  // действующая нижняя граница колонки по строке модели.
  // Авто-«Trust workspace» (#7498, раздел 12е; К-A5 WF119 — бывшее autoAllow.trust):
  // нажатия, отказы, последний случай {at, path, verdict}, корень автодоверия.
  statusPart("autoAllow", () => ({
    on: autoAllowEnabled(), switched: autoAllowState.switched, mutationRuns: autoAllowState.mutationRuns,
    presses: autoAllowState.presses.slice(0, 5), blocked: autoAllowState.blocked, blockedLog: autoAllowState.blockedLog.slice(0, 5),
    journal: autoAllowJournal().slice(0, 10),
    tickAt: autoAllowState.tickAt ? roamIso(autoAllowState.tickAt) : null,
    roam: roamStatus(),
    // #9998: чат окна в Bypass permissions — Allow once жмётся и при выключенном тумблере.
    bypass: autoAllowBypassHere(),
  }));
  statusPart("trust", () => ({ presses: autoTrustState.presses, refused: autoTrustState.refused, last: autoTrustState.last, root: autoTrustRoot() }));
  statusPart("layoutRuns", () => state.layoutRuns);
  statusPart("mutationBatches", () => state.mutationBatches);
  statusPart("mutationSkipped", () => state.mutationSkipped);
  statusPart("scrollRuns", () => state.scrollRuns);
  statusPart("timeRuns", () => state.timeRuns);
  statusPart("timeWatched", () => Boolean(state.timeTarget));

  const api = {
    version: VERSION,
    stages: { COLLAPSED: STAGE_COLLAPSED, NORMAL: STAGE_NORMAL, STRETCHED: STAGE_STRETCHED },
    dispose,
    setStage,
    get stage() { return state.stage; },
    // Раздел 12в. chats() зовёт probe.js приложения (ответ — промис), а
    // popoutChat() зовёт ПОПАП у своего родителя через window.opener.
    chats,
    popoutChat,
    // Лимиты подписки (раздел 12ж¹, WF87).
    limits: () => limitsNow(true),
    // Просмотр фото (раздел 12л, WF87): открыть с N-го фото чата, листать, закрыть.
    viewer: {
      open: (at = 0) => photoOpen(Number(at) || 0),
      step: delta => photoStep(Number(delta) || 0),
      close: () => photoClose(),
      state: () => photoView(),
    },
    // Перетаскивание вложений (раздел 12м², WF90): счётчики для probe на гейте.
    dnd: () => ddView(),
    // Файл — в окне чата (раздел 12д¹, WF103): то же, что клик по карточке; для probe гейта.
    viewFile: path => { try { return viewOpen(String(path ?? ""), null); } catch { return false; } },
    // Своя ▶ (раздел 12т, #7941): n-я кнопка вынесенного окна (с нуля) — как нажатие.
    runBlock: n => { try { return runBlock(n); } catch { return "fail"; } },
    // Груз вложений «Обкэшить» (WF50, раздел 12): обе ручки зовёт ДРУГОЕ окно
    // через window.opener.__myclaude — донор кладёт File, новое окно забирает.
    cashoutCarry,
    cashoutTake,
    // Для probe.js на гейте: видно, приехал ли инжект, применились ли стили
    // (CSP) и нашлось ли поле.
    status: () => statusView(),
    // Самопроверка (раздел 18, #10527): девять проверок того, что видно на экране, только чтением.
    health: () => healthNow(),
  };
  window.__myclaude = api;
  track(() => { if (window.__myclaude === api) { try { delete window.__myclaude; } catch { window.__myclaude = undefined; } } });

  // Тестовый люк: в бою этой функции нет, объект даже не собирается (HATCH = null, 000-head).
  // Ставит её только tests/load.mjs, чтобы дотянуться до чистых функций замыкания. Имена кладёт каждый файл
  // в своём конце (HATCH && Object.assign…); глушителя ошибок нет намеренно: переименовали функцию — люк
  // обязан кричать, а не отдавать тестам undefined. Здесь — имена 12е и обхода: их файлы в «НЕ ТРОГАТЬ» (#9998).
  if (HATCH) globalThis.__myclaudeTest(Object.assign(HATCH, { autoAllowLabel, autoAllowBlockReason, autoAllowState,
    autoAllowCycle, trustCycle, autoAllowOnMutation, setAutoAllowClock, roamState, roamStart, roamSession }));

  // Всё, что ниже, трогает живую страницу и может бросить на неготовой
  // разметке. Такое падение не должно оставлять в окне зомби: установка
  // откатывается целиком, а причина остаётся в окне для разбора.
  try {
    touchThemeMap();
    armCashoutWatch();
    // Полка вложений переживает перезапись inject.js — значит и уборщик обязан
    // вернуться вместе с новым экземпляром (#5789).
    startCashoutSweep();
    // Первый проход по времени — сразу: те сообщения, что уже на экране, ждать
    // ближайшей мутации не должны.
    runShortTime();
    layout();
    // Полоса прогресса — сразу после первой раскладки: блок ввода к этому
    // моменту уже найден, и ждать ближайшей мутации ленты ей нечего.
    progressRefresh();
  } catch (error) {
    try { dispose(); } catch {}
    window.__myclaudeFailure = {
      at: new Date().toISOString(),
      message: String(error?.message ?? error),
      stack: String(error?.stack ?? "").slice(0, 900),
    };
    throw error;
  }

  return VERSION;
})();
