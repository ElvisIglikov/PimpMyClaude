  // ---- 3а. Завершённые инструменты (#7976, WF120) -------------------------
  // Неизвестная разметка и любой выбор остаются видимыми. Edited опознаётся
  // по структуре и подписи, а не по одному data-find-omitted.
  const HIDE_TOOLS_KEY = "myclaude.hideTools";
  const HIDE_TOOLS_ATTRIBUTE = "data-myclaude-hide-tools";
  const HIDE_TOOLS_MARK = "data-myclaude-tool-done";
  const HIDE_TOOLS_GROUP = '[data-testid="transcript-row"] [data-cds="AssistantMessage"] [data-cds="TurnStatus"][data-tool-anchor][data-state="done"]';
  const HIDE_TOOLS_FILES = '[data-testid="transcript-row"] [data-cds="AssistantMessage"]:not([data-is-streaming="true"]) [data-find-omitted].contents:not([data-cds])';
  // Строка фоновых команд (слово Элвиса 11.10 06:27 по снимку «Background command completed · …»: «Я не
  // могу понять, ты закончил это делать или ещё чё-то думаешь дальше?»): обёртка без своего вида с одной
  // кнопкой [data-transcript-keeps-pin]. Прячется только законченное — «N running» и «N failed» на виду.
  const HIDE_TOOLS_TASKS = '[data-testid="transcript-row"] [data-cds="AssistantMessage"] div[data-find-omitted]:not([data-cds]):not(.contents)';
  const HIDE_TOOLS_TASKS_DONE = /^(?:\d+ background commands? completed|background command completed(?: ?·.*)?)$/i;
  const HIDE_TOOLS_DECISION = '.epitaxy-approval-card,[role="dialog"],[role="alertdialog"],[role="radiogroup"],[role="listbox"],form,textarea,input,select,[role="button"],a,[data-state="running"],[data-state="error"],[data-state="waiting"],[role="alert"]';
  // Claude 2.31226 (замер 11.10): у строки группы своя стрелка (button[data-cds-row-toggle]) и миниатюры
  // снимков (в [data-cds-row-media]) — это не выбор; карточка правок — строка на файл: имя и «+3 −0»
  // (кнопка файла — в li > span.contents). Прежняя разметка («Edited N files», группа без кнопок) жива.
  // Имя правленого файла в строке группы — span[role=button] внутри [data-cds-row]: ссылка, не выбор.
  const HIDE_TOOLS_GROUP_UNSAFE = 'button:not([data-cds-row-toggle],[data-cds-row-media] button)';
  const HIDE_TOOLS_GROUP_LINK = '[data-cds-row] span[role="button"]';
  const HIDE_TOOLS_GROUP_DECISION = HIDE_TOOLS_DECISION.replace('[role="button"]', `[role="button"]:not(${HIDE_TOOLS_GROUP_LINK})`);
  const HIDE_TOOLS_FILES_BUTTON = 'ul[role="list"] > li button[data-base-ui-tooltip-trigger]';
  const HIDE_TOOLS_FILES_DIFF = '.text-git-added,.text-git-removed';
  const HIDE_TOOLS_UNSAFE_BUTTON = `button:not([data-base-ui-tooltip-trigger])`;
  // Коробка поля ввода Claude (#9166а): правило в RULES раздела 4.
  const COMPOSER_BOX = '[data-cds="ChatComposer"] > div[class*="bg-surface"]';
  // Тихое выделение чата в списке слева (#9166б): доля цвета текста, прозрачно поверх фона.
  // WF182 (слово Элвиса 09.10 03:15 по снимку Pinned: «слишком яркая… выделение»): вдвое тише
  // (было 9 % и 6 %), наведение тише выделения.
  const SIDEBAR_SELECTED = "color-mix(in oklab, var(--cds-text-primary, currentColor) 4.5%, transparent)";
  const SIDEBAR_HOVER = "color-mix(in oklab, var(--cds-text-primary, currentColor) 3%, transparent)";
  // WF182 (#9166б для ленты, «выделение у текстов… слишком контрастное»): подложка реплики
  // человека — у Claude 5 % белого (--cds-bg-user-message), у нас вдвое тише и цветом текста темы.
  const USER_BUBBLE_FILL = "color-mix(in oklab, var(--cds-text-primary, currentColor) 2.5%, transparent)";
  // WF182 (#9164, «значок Code, активная вкладка — белое, яркое, бросается в глаза»): выбранный
  // значок Claude/Code — цветом соседних кнопок окна, чуть ярче их, и тонкая подложка; не белым.
  const MODE_ACTIVE_TINT = "color-mix(in oklab, var(--cds-text-secondary, currentColor) 75%, var(--cds-text-primary, currentColor))";
  const MODE_ACTIVE_FILL = "color-mix(in oklab, var(--cds-text-primary, currentColor) 6%, transparent)";
  // Точки чатов — тоном текста темы (page-64; акцент PMP #9166в снят словом Элвиса 11.10 01:40).
  const SIDEBAR_DOT_INK = "var(--cds-text-primary, currentColor)";
  const SIDEBAR_DOT_QUIET = "var(--cds-text-muted, currentColor)";
  // Поле «Search» под курсором: чуть плотнее покоя (покой — как выбранная строка).
  const SIDEBAR_SEARCH_HOVER = "color-mix(in oklab, var(--cds-text-primary, currentColor) 7%, transparent)";
  // Плашки ленты ответа (#9167), замер 09.10 (Claude 2.26454): строка инструментов
  // TurnStatus > [data-cds-row]; кнопка group/tool («Claude Code notice», «N background
  // commands completed»); карточка self-start isolate (318 px, «N background commands running»);
  // карточка Card ответа (файл, вложение) — не вложенная в другую карточку.
  const FEED_PLATES = [
    '[data-cds="TurnStatus"] > [data-cds-row]',
    'button[class~="group/tool"]',
    'button[class~="self-start"][class~="isolate"]',
    '[data-cds="Card"]:not([data-cds="Card"] *)',
  ].map(plate => `.epitaxy-chat-panel [data-cds="AssistantMessage"] ${plate}`).join(",");
  let hideToolsObserver = null;
  // Слово Элвиса 11.10 01:40 по карточке правок и строке «Ran N commands»: «Скрой… чтоб он мне это не
  // писал. Всё лишнее сейчас будем убирать» — без команды включено; выключено — только "0".
  const hideToolsOn = () => {
    try { return localStorage.getItem(HIDE_TOOLS_KEY) !== "0"; } catch { return true; }
  };
  const hideToolsSquash = node => (node.textContent ?? "").replace(/\s/g, "");
  const hideToolsEligible = node => {
    const group = node.matches(HIDE_TOOLS_GROUP);
    if (node.matches(HIDE_TOOLS_DECISION) || [...node.querySelectorAll(HIDE_TOOLS_DECISION)].some(item => !(group && item.matches(HIDE_TOOLS_GROUP_LINK))) ||
        node.closest('.epitaxy-approval-card,[role="dialog"],[role="alertdialog"],[role="alert"]') ||
        /\b(?:AskUserQuestion|ExitPlanMode|Asked a question)\b|Задан вопрос/i.test(node.textContent ?? "")) return false;
    if (group) return Boolean(node.getAttribute("data-tool-anchor")?.trim()) &&
      ![...node.querySelectorAll('button')].some(button => !button.hasAttribute("data-cds-row-toggle") && !button.closest("[data-cds-row-media]"));
    if (node.matches(HIDE_TOOLS_TASKS)) {
      const pins = [...node.querySelectorAll('button')];
      return pins.length === 1 && pins[0].hasAttribute("data-transcript-keeps-pin") && pins[0].getAttribute("aria-expanded") !== "true" &&
        HIDE_TOOLS_TASKS_DONE.test((pins[0].textContent ?? "").replace(/\s+/g, " ").trim()) && hideToolsSquash(node) === hideToolsSquash(pins[0]);
    }
    if (!node.matches(HIDE_TOOLS_FILES)) return false;
    const message = node.closest('[data-cds="AssistantMessage"]');
    if (message?.querySelector('[data-cds="TurnStatus"]:not([data-state="done"])')) return false;
    const buttons = [...node.querySelectorAll('button')];
    if (!buttons.length || !buttons.every(button => button.matches(HIDE_TOOLS_FILES_BUTTON))) return false;
    // The wrapper may also contain a plan or reply after a transcript update.
    // #11618: русский Claude — формы plural из каталога («Изменен 1 файл», «Изменено 2 файла / 5 файлов», «Изменено файлов: N»).
    if (buttons.every(button => /^(?:Edited \d+ files?|Изменено? \d+ файл(?:а|ов)?|Изменено файлов: \d+)$/.test((button.textContent ?? "").trim()))) return hideToolsSquash(node) === buttons.map(hideToolsSquash).join("");
    const rows = [...node.querySelectorAll('ul[role="list"] > li')];
    return rows.length > 0 && rows.every(row => row.querySelector(HIDE_TOOLS_FILES_DIFF)) && hideToolsSquash(node) === rows.map(hideToolsSquash).join("");
  };
  const hideToolsSync = () => {
    for (const node of document.querySelectorAll(`[${HIDE_TOOLS_MARK}],${HIDE_TOOLS_GROUP},${HIDE_TOOLS_FILES},${HIDE_TOOLS_TASKS}`)) {
      const safe = hideToolsOn() && hideToolsEligible(node);
      if (safe && !node.hasAttribute(HIDE_TOOLS_MARK)) node.setAttribute(HIDE_TOOLS_MARK, "");
      else if (!safe && node.hasAttribute(HIDE_TOOLS_MARK)) node.removeAttribute(HIDE_TOOLS_MARK);
    }
  };
  const hideToolsMark = () => {
    const root = document.documentElement;
    if (hideToolsOn()) {
      if (!root.hasAttribute(HIDE_TOOLS_ATTRIBUTE)) root.setAttribute(HIDE_TOOLS_ATTRIBUTE, "");
      if (!hideToolsObserver) {
        hideToolsObserver = new MutationObserver(hideToolsSync);
        hideToolsObserver.observe(root, { childList: true, subtree: true, characterData: true, attributes: true,
          attributeFilter: ["data-state", "data-is-streaming", "data-tool-anchor", "data-cds", "role", "class", "data-base-ui-tooltip-trigger"] });
      }
    } else {
      root.removeAttribute(HIDE_TOOLS_ATTRIBUTE);
      hideToolsObserver?.disconnect();
      hideToolsObserver = null;
    }
    hideToolsSync();
  };
  const hideToolsSet = value => {
    try {
      localStorage.setItem(HIDE_TOOLS_KEY, value ? "1" : "0");
    } catch {}
    hideToolsMark();
  };
  const hideToolsHidden = () => hideToolsOn() ? [...document.querySelectorAll(`[${HIDE_TOOLS_MARK}]`)]
    .filter(hideToolsEligible).length : 0;
  hideToolsMark();
  on(window, "storage", event => { if (event.key === HIDE_TOOLS_KEY || event.key === null) hideToolsMark(); });
  track(() => {
    hideToolsObserver?.disconnect();
    document.documentElement.removeAttribute(HIDE_TOOLS_ATTRIBUTE);
    for (const node of document.querySelectorAll(`[${HIDE_TOOLS_MARK}]`)) node.removeAttribute(HIDE_TOOLS_MARK);
  });
  // «Прятать инструменты» (#7976, раздел 3а): включено ли, сколько групп и списков правок спрятано сейчас.
  statusPart("hideTools", () => ({ on: hideToolsOn(), hidden: hideToolsHidden() }));
  HATCH && Object.assign(HATCH, { FEED_PLATES });

