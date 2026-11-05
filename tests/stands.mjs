// Общие помощники стендов страницы (WF248 П4): то, что наборы копировали к себе по файлам. Здесь, а не в горячем
// dom.mjs, — параллельные батчи страницы не спорят за один файл. Переводить наборы сюда — по мере правки, без
// отдельного большого переписывания; правка помощника меняет все наборы разом — тела не трогать без нужды.

// Дать странице дойти: ресайз окна, таймеры и кадры (дословная копия жила в 12 наборах).
export const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};

// Строка списка чатов слева: ключ `code:<id>` и React-волокно с сессией — так страница читает чат строки.
export const sidebarRow = (bar, id, session) => {
  const row = bar.add("div", { attrs: { "data-row-key": `code:${id}` } });
  row["__reactFiber$test"] = {
    memoizedProps: { "data-row-key": `code:${id}` },
    return: { memoizedProps: { session }, return: null },
  };
};

// Нижняя строка поля (ChatComposerChin) под полем left…left+width с верхом top: группа «+» слева, справа
// кнопка модели и кружок лимитов. Кладёт в parts chin и left.
export const chin = (parts, { left = 100, top = 600, width = 1000 } = {}) => {
  const y = top + 148;
  parts.chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: { left, top: y - 4, width, height: 28 } });
  const row = parts.chin.add("div", { class: "flex items-center", rect: { left, top: y, width, height: 20 } });
  parts.left = row.add("div", { class: "flex items-center self-start", rect: { left, top: y + 2, width: 60, height: 16 } });
  parts.left.add("button", { attrs: { "aria-label": "Add" }, rect: { left, top: y + 2, width: 20, height: 16 } });
  const right = row.add("div", { class: "ms-auto flex items-center", rect: { left: left + width - 100, top: y, width: 100, height: 20 } });
  const grid = right.add("div", { class: "grid", rect: { left: left + width - 100, top: y, width: 100, height: 20 } });
  grid.add("button", { attrs: { "data-testid": "epitaxy-cds-model-selector" }, text: "Opus 5.5", rect: { left: left + width - 100, top: y + 2, width: 60, height: 16 } });
  grid.add("button", { attrs: { "aria-haspopup": "dialog", "aria-label": "Usage: Context 300k / 1M (30%)" }, rect: { left: left + width - 20, top: y, width: 20, height: 20 } });
  return parts;
};

// ---- Окно Claude 3.1623 для health() (#10527) ----------------------------------------------------------------
// Форма — как в слепке живого окна (tests/fixtures/claude-dom/3.1623-main-wide.json): шапка в обёртках
// «div.contents > div», лента, дока с рамкой поля, нижняя строка ChatComposerChin, свёрнутая боковая панель с
// «Show sidebar». CSS стаб не считает: флаг широкого вида и сетку ставит wideByCss (ниже) по таблице самой
// страницы; рамки — как на экране с нашими стилями (wide — геометрия широкого вида). kind: main | popout | new.
// Окно — viewport стенда (широкое 1200×800, узкое 600×800). Возвращает узлы сцены.
export const claudeWindow = (dom, { wide = true, kind = "main", look = false, card = false } = {}) => {
  const W = dom.window.innerWidth;
  const H = dom.window.innerHeight;
  const rect = (left, top, width, height) => ({ left, top, width, height });
  const parts = {};
  const root = parts.root = dom.document.body.add("div", { class: "dframe-root", rect: rect(0, 0, W, H) });
  // Подложка живого фона (раздел 2а): слой ::before на .dframe-root; у плиток и поля фон прозрачный.
  if (look) root.pseudo = { "::before": { content: '""', display: "block", opacity: "1", width: `${W}px`, height: `${H}px` } };
  const aside = parts.aside = root.add("aside", { class: "dframe-sidebar", rect: rect(0, 0, 0, H) });
  const chrome = aside.add("div", { class: "df-collapsed-chrome flex", rect: rect(76, 0, 44, 44) });
  // Свёрнутая панель с кнопкой лежит над плитками (у Claude — слой над рамкой плиток).
  parts.sidebarButton = chrome.add("button", { attrs: { "aria-label": "Show sidebar", type: "button" }, rect: rect(84, 8, 28, 28),
    computed: { zIndex: "10" } });
  parts.sidebarButton.pseudo = { "::before": { backgroundColor: "rgb(19, 21, 24)" } };
  const tiles = parts.tiles = root.add("div", { class: "tiles-shell", rect: rect(0, 0, W, H) });
  const panelBox = rect(8, 0, W - 8, H - 8);
  const panel = parts.panel = tiles.add("div", { class: "relative isolate epitaxy-chat-panel", rect: panelBox });
  const column = parts.column = panel.add("div", { class: "relative h-full min-w-0 flex", rect: panelBox });
  // Геометрия: широкий — лента слева, колонка поля справа (шапка над полем); узкий — шапка, лента, поле снизу.
  const side = wide ? 400 : 0;
  const feedBox = wide ? rect(8, 0, W - 8 - side, H - 8) : rect(8, 54, W - 8, H - 8 - 54 - 240);
  const dockBox = wide ? rect(W - side, 54, side, H - 8 - 54) : rect(8, H - 8 - 240, W - 8, 240);
  const headBox = wide ? rect(W - side, 9, side, 45) : rect(8, 9, W - 8, 45);
  // Начало текста поля: рамка + 45 (место под «+» слева); название шапки — по этой линии (сдвиг раздела 2г уже
  // применён, как на экране), его текст — после поля 12 внутри кнопки.
  const textLeft = dockBox.left + 12 + 45;
  if (kind !== "new") {
    const head = column.add("div", { class: "cds-root contents" }).add("div");
    parts.header = head.add("div", { class: "epitaxy-titlebar relative flex", rect: headBox });
    const titleLeft = wide ? textLeft - 12 : headBox.left + 12;
    const lead = parts.header.add("div", { class: "group/lead flex", rect: rect(titleLeft, 17, 220, 28) });
    parts.title = lead.add("button", { attrs: { "data-pane-title": "", type: "button" }, text: "Сторожи Пимпа",
      rect: rect(titleLeft, 17, 160, 28), computed: { "padding-left": "12px" } });
    // Плашка проекта — у правого края шапки (как кнопки шапки 3.1623): между ней и названием — место угла (head).
    const chip = headBox.left + headBox.width - 72;
    parts.header.add("button", { attrs: { type: "button" }, rect: rect(chip, 17, 60, 28) })
      .add("span", { attrs: { "data-testid": "epitaxy-origin-label" }, text: "PimpMyClaude", rect: rect(chip + 4, 21, 52, 20) });
  }
  const outer = column.add("div", { class: "relative flex min-h-0 flex-1" });
  if (kind !== "new") {
    const body = outer.add("div", { class: "relative flex min-h-0 flex-1" })
      .add("div", { class: "epitaxy-chat-panel-body flex-1", rect: feedBox });
    parts.feed = body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" }, rect: feedBox });
    parts.row = parts.feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant" },
      rect: rect(feedBox.left, feedBox.top + 40, feedBox.width, 200) });
    if (card) parts.card = parts.row.add("button", { attrs: { type: "button", title: "/Users/dev/Projects/PimpMyClaude/docs/16.html" },
      rect: rect(feedBox.left + 40, feedBox.top + 60, 240, 56) });
  }
  const dock = parts.dock = outer.add("div", { class: "w-full mx-auto" })
    .add("div", { class: "group/approval-dock pointer-events-auto relative", rect: dockBox });
  // Поле — в доке с отступом 12: рамка, под ней нижняя строка 40.
  const field = rect(dockBox.left + 12, dockBox.top, dockBox.width - 24, dockBox.height - 40);
  const prompt = dock.add("div", { class: "epitaxy-prompt", rect: rect(field.left, field.top, field.width, dockBox.height) });
  const composer = prompt.add("div", { class: "flex w-full flex-col", attrs: { "data-cds": "ChatComposer", role: "group" },
    rect: rect(field.left, field.top, field.width, dockBox.height) });
  parts.frame = composer.add("div", { class: "bg-surface-3 relative z-[1]", rect: field });
  const inner = parts.frame.add("div", { class: "relative w-full", rect: rect(field.left + 9, field.top + 9, field.width - 18, field.height - 18) });
  // Редактор и кнопки поля — как в слепке: кнопки в обёртке ChatComposerActions (display: contents, рамки нет),
  // соседом редактора видимой строки нет.
  const editorBox = inner.add("div", { class: "relative min-w-0 break-words", rect: rect(field.left + 45, field.top + 9, field.width - 54, field.height - 50) });
  parts.editorRoot = editorBox.add("div", { attrs: { "data-cds": "ChatComposerEditor" }, computed: { overflowY: "auto" },
    rect: rect(field.left + 45, field.top + 9, field.width - 54, field.height - 50) });
  parts.editor = parts.editorRoot.add("div", { class: "tiptap ProseMirror", attrs: { contenteditable: "true" },
    rect: rect(field.left + 45, field.top + 12, field.width - 54, 21) });
  parts.send = inner.add("div", { class: "contents", attrs: { "data-cds": "ChatComposerActions" } })
    .add("div", { class: "absolute bottom-0 end-0 flex", rect: rect(field.left + field.width - 45, field.top + field.height - 37, 36, 28) })
    .add("button", { attrs: { "data-testid": "code-prompt-send", type: "button" },
    rect: rect(field.left + field.width - 37, field.top + field.height - 37, 28, 28) });
  const chinTop = dockBox.top + dockBox.height - 40;
  parts.chin = composer.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: rect(field.left - 8, chinTop, field.width + 16, 40) });
  const row = parts.chin.add("div", { class: "flex min-h-control items-center", rect: rect(field.left, chinTop + 8, field.width, 24) });
  // Левая группа «+» — правее места под микрофон Диктатора (его отступ ставит правило раздела 4).
  const group = row.add("div", { class: "flex items-center self-start", rect: rect(field.left + 30, chinTop + 12, 52, 16) });
  parts.attach = group.add("button", { attrs: { type: "button" }, rect: rect(field.left + 30, chinTop + 12, 20, 16) });
  const right = row.add("div", { class: "ms-auto flex items-center", rect: rect(field.left + field.width - 131, chinTop + 8, 131, 24) });
  parts.model = right.add("button", { attrs: { "data-testid": "epitaxy-cds-model-selector", "aria-label": "Model: Opus 5.5", type: "button" },
    text: "Opus 5.5", rect: rect(field.left + field.width - 123, chinTop + 12, 94, 16) });
  if (kind !== "popout") parts.ring = right.add("button", { attrs: { "aria-haspopup": "dialog", "aria-label": "Usage: Context 300k / 1M (30%)", type: "button" },
    rect: rect(field.left + field.width - 24, chinTop + 8, 24, 24) });
  return parts;
};

// Рамки наших узлов по их инлайн-стилям (стаб CSS не считает): узлы в body ставятся left/top/width/height или
// right/bottom; чего нет в инлайне (высоту ручки и рейки даёт таблица раздела 4) — fallback.
export const ownRects = (dom, fallback = 12) => {
  const px = value => (/^-?[\d.]+px$/.test(String(value).trim()) ? Number.parseFloat(value) : null);
  const W = dom.window.innerWidth;
  const H = dom.window.innerHeight;
  for (const node of dom.queryAll('[id^="myclaude-"]')) {
    const style = node.style;
    const display = style.getPropertyValue("display");
    if (!display || display === "none") continue;
    const width = px(style.getPropertyValue("width")) ?? (node.rect.width || fallback);
    const height = px(style.getPropertyValue("height")) ?? (node.rect.height || fallback);
    const left = px(style.getPropertyValue("left")) ?? (px(style.getPropertyValue("right")) != null ? W - px(style.getPropertyValue("right")) - width : null);
    const top = px(style.getPropertyValue("top")) ?? (px(style.getPropertyValue("bottom")) != null ? H - px(style.getPropertyValue("bottom")) - height : null);
    if (left == null || top == null) continue;
    node.rect = { left, top, width, height };
  }
};

// Попадание по рамкам (стаб elementFromPoint не умеет): верхний — последний по порядку документа среди узлов с
// бóльшим z-index (инлайн или computed); узлы с display:none у себя или предка и pointer-events:none — насквозь.
export const pointHits = dom => {
  const win = dom.window;
  const all = () => dom.queryAll("*");
  const style = node => win.getComputedStyle(node);
  const hidden = node => {
    for (let item = node; item && item.nodeType === 1; item = item.parentElement) {
      const own = style(item);
      if (own.display === "none" || own.visibility === "hidden") return true;
    }
    return false;
  };
  const z = node => Number.parseInt(node.style.getPropertyValue("z-index") || node.computed?.zIndex || "0", 10) || 0;
  const stack = (x, y) => all()
    .map((node, order) => ({ node, order }))
    .filter(({ node }) => {
      const box = node.getBoundingClientRect();
      if (!(box.width > 0 && box.height > 0 && x >= box.left && x < box.right && y >= box.top && y < box.bottom)) return false;
      return style(node).getPropertyValue("pointer-events") !== "none" && !hidden(node);
    })
    .sort((a, b) => (z(b.node) - z(a.node)) || (b.order - a.order))
    .map(item => item.node);
  dom.document.elementFromPoint = (x, y) => stack(x, y)[0] ?? null;
  dom.document.elementsFromPoint = (x, y) => stack(x, y);
};

// ---- Широкий вид по форме разметки (#10527) ------------------------------------------------------------------
// Стаб CSS не считает, а флаг широкого вида и сетку ставит именно CSS — контейнерный запрос раздела 2а. Здесь их
// ставит сама таблица страницы: из её текста (dom.sheets()) берутся правило флага и правило сетки внутри
// `@container tile-slot (min-width: N)`, их селекторы (с :has, :is, :not) сверяются с деревом стенда, и
// совпавшим узлам кладётся computed. Так «шапку завернули в лишнюю обёртку» ломает вид в стенде так же, как
// в окне, а слепок прошлой страницы получает ровно её примету. Ширина контейнера — рамка плитки.
const splitTopLevel = (text, separator) => {
  const out = [];
  let depth = 0;
  let quote = "";
  let current = "";
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (char === "\\") { current += char + (text[index + 1] ?? ""); index += 1; continue; }
    if (quote) { current += char; if (char === quote) quote = ""; continue; }
    if (char === '"' || char === "'") { quote = char; current += char; continue; }
    if (char === "(" || char === "[") depth += 1;
    if (char === ")" || char === "]") depth -= 1;
    if (depth === 0 && char === separator) { out.push(current.trim()); current = ""; continue; }
    current += char;
  }
  if (current.trim()) out.push(current.trim());
  return out;
};
// Сложный селектор → [{comb, tokens}] слева направо; ведущий «>» (относительный селектор в :has) — comb первого.
const parseComplex = text => {
  const parts = [];
  let comb = " ";
  let index = 0;
  const source = String(text).trim();
  while (index < source.length) {
    const char = source[index];
    if (/\s/.test(char)) { index += 1; continue; }
    if (char === ">") { comb = ">"; index += 1; continue; }
    let depth = 0;
    let compound = "";
    while (index < source.length) {
      const next = source[index];
      if (next === "\\") { compound += next + (source[index + 1] ?? ""); index += 2; continue; }
      if (next === "(" || next === "[") depth += 1;
      if (next === ")" || next === "]") depth -= 1;
      if (depth === 0 && (/\s/.test(next) || next === ">")) break;
      compound += next;
      index += 1;
    }
    parts.push({ comb, tokens: parseCompound(compound) });
    comb = " ";
  }
  return parts;
};
const IDENT = /^(?:\\.|[\w-])+/;
const unescape = text => text.replace(/\\(.)/g, "$1");
const parseCompound = text => {
  const tokens = [];
  let rest = text;
  while (rest) {
    if (rest[0] === "*") { rest = rest.slice(1); continue; }
    if (rest[0] === "." || rest[0] === "#") {
      const name = rest.slice(1).match(IDENT)?.[0] ?? "";
      tokens.push({ kind: rest[0], name: unescape(name) });
      rest = rest.slice(1 + name.length);
      continue;
    }
    if (rest[0] === "[") {
      const end = rest.indexOf("]");
      tokens.push({ kind: "[", text: rest.slice(0, end + 1) });
      rest = rest.slice(end + 1);
      continue;
    }
    if (rest[0] === ":") {
      const name = rest.slice(1).match(/^[\w-]+/)?.[0] ?? "";
      rest = rest.slice(1 + name.length);
      let args = null;
      if (rest[0] === "(") {
        let depth = 0;
        let end = 0;
        for (; end < rest.length; end += 1) {
          if (rest[end] === "\\") { end += 1; continue; }
          if (rest[end] === "(") depth += 1;
          if (rest[end] === ")") { depth -= 1; if (depth === 0) break; }
        }
        args = rest.slice(1, end);
        rest = rest.slice(end + 1);
      }
      tokens.push({ kind: ":", name, args });
      continue;
    }
    const tag = rest.match(/^[a-zA-Z][\w-]*/)?.[0];
    if (!tag) throw new Error(`селектор не разобран: ${text}`);
    tokens.push({ kind: "tag", name: tag.toUpperCase() });
    rest = rest.slice(tag.length);
  }
  return tokens;
};
const ATTR = /^\[\s*([\w-]+)\s*(?:([~^$*|]?=)\s*(?:"([^"]*)"|'([^']*)'|([^\]\s]*)))?\s*\]$/;
const compoundHits = (node, tokens) => tokens.every(token => {
  if (token.kind === "tag") return node.tagName === token.name;
  if (token.kind === ".") return node.classList.contains(token.name);
  if (token.kind === "#") return node.id === token.name;
  if (token.kind === "[") {
    const [, name, op, a, b, c] = token.text.match(ATTR) ?? [];
    const actual = name ? node.getAttribute(name) : null;
    if (actual == null) return false;
    const value = a ?? b ?? c ?? "";
    if (!op) return true;
    if (op === "=") return actual === value;
    if (op === "~=") return actual.split(/\s+/).includes(value);
    if (op === "^=") return actual.startsWith(value);
    if (op === "$=") return actual.endsWith(value);
    if (op === "*=") return actual.includes(value);
    return false;
  }
  if (token.name === "has") return splitTopLevel(token.args, ",").some(rel => relativeHit(node, parseComplex(rel)));
  if (token.name === "is" || token.name === "where") return splitTopLevel(token.args, ",").some(item => cssMatch(node, item));
  if (token.name === "not") return !splitTopLevel(token.args, ",").some(item => cssMatch(node, item));
  if (token.name === "root") return node === node.ownerDocument?.documentElement;
  return false;
});
const fromRight = (node, parts, index, scope) => {
  if (!compoundHits(node, parts[index].tokens)) return false;
  if (index === 0) {
    if (!scope) return true;
    return parts[0].comb === ">" ? node.parentElement === scope : node !== scope && scope.contains(node);
  }
  if (parts[index].comb === ">") {
    const parent = node.parentElement;
    return Boolean(parent && parent !== scope && fromRight(parent, parts, index - 1, scope));
  }
  for (let parent = node.parentElement; parent && parent !== scope; parent = parent.parentElement) {
    if (fromRight(parent, parts, index - 1, scope)) return true;
  }
  return false;
};
const descendantsOf = node => {
  const out = [];
  const walk = item => { for (const kid of item.children) { out.push(kid); walk(kid); } };
  walk(node);
  return out;
};
const relativeHit = (scope, parts) => descendantsOf(scope).some(node => fromRight(node, parts, parts.length - 1, scope));
export const cssMatch = (node, selector) => splitTopLevel(selector, ",")
  .some(item => { const parts = parseComplex(item); return parts.length > 0 && fromRight(node, parts, parts.length - 1, null); });

// Правила флага и сетки из таблиц страницы: первые два правила блока `@container tile-slot (min-width: N)`.
export const wideRules = css => {
  const at = css.match(/@container tile-slot \(min-width: (\d+)px\) \{/);
  if (!at) return null;
  const tail = css.slice(at.index + at[0].length);
  const flagOpen = tail.indexOf("{");
  const flag = tail.slice(0, flagOpen).trim();
  const afterFlag = tail.slice(tail.indexOf("}", flagOpen) + 1);
  const grid = afterFlag.slice(0, afterFlag.indexOf("{")).trim();
  return { min: Number(at[1]), flag, grid };
};
export const wideByCss = loaded => {
  const rules = wideRules(loaded.dom.sheets());
  if (!rules) throw new Error("в таблицах страницы нет блока @container tile-slot");
  const panels = loaded.dom.queryAll(".epitaxy-chat-panel");
  for (const panel of panels) {
    const wide = panel.getBoundingClientRect().width >= rules.min && cssMatch(panel, rules.flag);
    if (wide) panel.computed = { ...panel.computed, "--myclaude-wide": "1" };
    else { const { "--myclaude-wide": drop, ...rest } = panel.computed ?? {}; void drop; panel.computed = rest; }
    for (const node of descendantsOf(panel)) {
      if (wide && cssMatch(node, rules.grid)) node.computed = { ...node.computed, display: "grid" };
      else if (node.computed?.display === "grid") { const { display, ...rest } = node.computed; void display; node.computed = rest; }
    }
  }
  return rules;
};
