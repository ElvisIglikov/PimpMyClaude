// Минимальный DOM для тестов inject.js. Зависимостей нет: node + vm, как просит
// план WF24 (решение 2). Настоящего браузера здесь нет и быть не может — стаб
// отдаёт ровно то, что файл спрашивает: дерево узлов, разбор селекторов,
// геометрию (её задаёт тест, а не нули), хранилища, таймеры и счётчики.
//
// Счётчики — главное, ради чего стаб писался вручную: подписки, наблюдатели,
// таймеры, интервалы и кадры считаются живыми, и после dispose() их должно
// остаться ноль. Ни jsdom, ни happy-dom такого счёта наружу не дают.
//
// Геометрия: у каждого узла есть поле rect ({left, top, width, height}), и
// getBoundingClientRect() считает по нему right/bottom. Не задал тест — узел
// нулевой, и это видно в тесте, а не притворяется рабочей раскладкой.

// ---- разбор селекторов ----------------------------------------------------
// Поддержано ровно то, чем пользуется inject.js: тег, .класс, #id, [атрибут],
// [атрибут="значение"] с ^= $= *=, потомки через пробел, перечисление запятой,
// :root и :not(...) с простым содержимым. Остальное (:has, :is) селектором
// ничего не находит — это честнее выдуманного совпадения: такие селекторы живут
// в тексте CSS, а не в querySelector.
//
// :not(...) стаб понимает с WF43 (#5758). До этого он не находил НИЧЕГО, и шаг
// «отправить первое сообщение» у нового окна не проверялся ничем: кнопка
// ищется как [data-testid="code-prompt-send"]:not([disabled]), стаб отдавал
// null, и подмена селектора на несуществующий не роняла ни одной проверки.
const splitTop = (text, separator) => {
  const parts = [];
  let depth = 0;
  let quote = "";
  let current = "";
  for (const char of String(text)) {
    if (quote) {
      current += char;
      if (char === quote) quote = "";
      continue;
    }
    if (char === '"' || char === "'") { quote = char; current += char; continue; }
    if (char === "[" || char === "(") depth += 1;
    if (char === "]" || char === ")") depth -= 1;
    if (depth === 0 && (separator === "," ? char === "," : /\s/.test(char))) {
      if (current.trim()) parts.push(current.trim());
      current = "";
      continue;
    }
    current += char;
  }
  if (current.trim()) parts.push(current.trim());
  return parts;
};

const TOKEN_RE = /\*|[.#]?[A-Za-z_][\w-]*|\[[^\]]*\]|:[a-z-]+(?:\([^)]*\))?/g;
const ATTR_RE = /^\[\s*([\w-]+)\s*(?:([~^$*|]?=)\s*("([^"]*)"|'([^']*)'|[^\]]*?)\s*)?\]$/;

const attrHit = (node, token) => {
  const parsed = token.match(ATTR_RE);
  if (!parsed) return false;
  const [, name, operator, rawValue, doubleQuoted, singleQuoted] = parsed;
  const actual = node.getAttribute(name);
  if (actual == null) return false;
  if (!operator) return true;
  const value = doubleQuoted ?? singleQuoted ?? String(rawValue ?? "").trim();
  if (operator === "=") return actual === value;
  if (operator === "^=") return actual.startsWith(value);
  if (operator === "$=") return actual.endsWith(value);
  if (operator === "*=") return actual.includes(value);
  if (operator === "~=") return actual.split(/\s+/).includes(value);
  if (operator === "|=") return actual === value || actual.startsWith(`${value}-`);
  return false;
};

const compoundHit = (node, compound) => {
  if (!node || node.nodeType !== 1) return false;
  const tokens = String(compound).match(TOKEN_RE);
  if (!tokens || tokens.join("") !== String(compound)) return false;
  for (const token of tokens) {
    if (token === "*") continue;
    if (token.startsWith("#")) { if (node.id !== token.slice(1)) return false; continue; }
    if (token.startsWith(".")) { if (!node.classList.contains(token.slice(1))) return false; continue; }
    if (token.startsWith("[")) { if (!attrHit(node, token)) return false; continue; }
    if (token.startsWith(":")) {
      // :not(...) — единственный псевдокласс с содержимым, который боевой файл
      // отдаёт в querySelector. Внутри разбираем тем же compoundHit: там живут
      // [disabled] и [type], а не вложенные :has.
      const negated = token.match(/^:not\((.+)\)$/);
      if (negated) {
        if (splitTop(negated[1], ",").some(part => compoundHit(node, part))) return false;
        continue;
      }
      if (token !== ":root" || node !== node.ownerDocument?.documentElement) return false;
      continue;
    }
    if (node.tagName !== token.toUpperCase()) return false;
  }
  return true;
};

const selectorHit = (node, selector) => {
  for (const group of splitTop(selector, ",")) {
    const parts = splitTop(group, " ").filter(part => part !== ">");
    if (!parts.length) continue;
    let current = node;
    if (!compoundHit(current, parts[parts.length - 1])) continue;
    let ok = true;
    for (let index = parts.length - 2; index >= 0; index -= 1) {
      let parent = current.parentElement;
      let found = false;
      while (parent) {
        if (compoundHit(parent, parts[index])) { found = true; current = parent; break; }
        parent = parent.parentElement;
      }
      if (!found) { ok = false; break; }
    }
    if (ok) return true;
  }
  return false;
};

// ---- окно ------------------------------------------------------------------
export const createDom = ({
  title = "",
  href = "https://claude.ai/epitaxy/local_test",
  local = {},
  session = {},
  viewport = { width: 1200, height: 800 },
  hasFocus = true,
  // Окно-родитель для попапа (WF29, раздел 12в): попап about:blank спрашивает
  // свой чат у window.opener.__myclaude. Тест кладёт сюда либо окно второго
  // стенда (loadInject(...).win — тогда у родителя настоящий __myclaude из
  // боевого файла), либо любой объект-заглушку, либо ничего: без opener окно
  // ведёт себя как первое окно браузера.
  opener = null,
} = {}) => {
  // sheets считается на лету: тема, шрифт и размер живут конструируемыми
  // таблицами (adoptedStyleSheets), и их число — тот же счётчик утечки.
  const counters = { listeners: 0, observers: 0, timers: 0, intervals: 0, rafs: 0 };
  // Поиски по дереву (querySelector/querySelectorAll, свои и у узлов) — мера
  // РАБОТЫ, а не времени: ею живые цвета доказывают, что тик не обходит
  // страницу (#5683). Отдельной переменной, а не полем counters: на counters
  // стоит deepEqual в tests/idempotent.test.mjs, и лишний ключ его свалил бы.
  let queries = 0;
  const timers = new Map();
  let timerSeq = 1;
  // Живые анимации Web Animations (element.animate): пульс полосы прогресса —
  // единственный, кто их заводит, и после dispose() их должно остаться ноль.
  // Счётчик отдельным списком, а не в counters: узлы у анимации свои, и тесту
  // важно, НА ЧЁМ она висит, а не только сколько их.
  const animations = [];

  const makeStyle = () => {
    const map = new Map();
    const api = {
      setProperty: (name, value) => { map.set(name, String(value)); },
      removeProperty: name => { map.delete(name); },
      getPropertyValue: name => map.get(name) ?? "",
      get cssText() { return [...map].map(([key, value]) => `${key}:${value}`).join(";"); },
      _map: map,
    };
    return new Proxy(api, {
      get(target, prop) {
        if (prop in target) return target[prop];
        if (typeof prop !== "string") return undefined;
        return map.get(prop) ?? "";
      },
      set(target, prop, value) {
        if (typeof prop === "string" && !(prop in target)) { map.set(prop, String(value)); return true; }
        target[prop] = value;
        return true;
      },
    });
  };

  const listenersOf = target => (target.__listeners ??= new Map());
  const addListener = (target, type, handler, options) => {
    const map = listenersOf(target);
    if (!map.has(type)) map.set(type, []);
    map.get(type).push({ handler, options });
    counters.listeners += 1;
  };
  const removeListener = (target, type, handler, options) => {
    const map = listenersOf(target);
    const list = map.get(type) ?? [];
    // Снятие ищем по самому обработчику: options при снятии могут быть записаны
    // иначе (true вместо {capture:true}) — браузер их сравнивает по capture,
    // и держаться за объект нельзя.
    const index = list.findIndex(item => item.handler === handler);
    if (index < 0) return;
    list.splice(index, 1);
    counters.listeners -= 1;
    void options;
  };
  const fireListeners = (target, event) => {
    for (const item of [...(listenersOf(target).get(event.type) ?? [])]) {
      if (event.__stopped) break;
      try { item.handler.call(target, event); } catch (error) { event.__error = error; }
    }
    return !event.defaultPrevented;
  };

  const document = {};

  const makeNode = tag => {
    const attributes = new Map();
    const node = {
      nodeType: 1,
      tagName: String(tag).toUpperCase(),
      ownerDocument: document,
      style: makeStyle(),
      dataset: {},
      rect: { left: 0, top: 0, width: 0, height: 0 },
      // Ответ getComputedStyle: тест кладёт сюда только то, что ему важно.
      computed: {},
      childNodes: [],
      parentNode: null,
      scrollTop: 0,
      scrollHeight: 0,
      clientHeight: 0,
      disabled: false,
      __text: "",
      __listeners: new Map(),
    };
    node.classList = {
      add: (...names) => {
        const set = new Set(String(attributes.get("class") ?? "").split(/\s+/).filter(Boolean));
        for (const name of names) set.add(name);
        attributes.set("class", [...set].join(" "));
      },
      remove: (...names) => {
        const set = new Set(String(attributes.get("class") ?? "").split(/\s+/).filter(Boolean));
        for (const name of names) set.delete(name);
        attributes.set("class", [...set].join(" "));
      },
      contains: name => String(attributes.get("class") ?? "").split(/\s+/).includes(name),
      toggle: (name, force) => {
        const has = node.classList.contains(name);
        if (force === true || (force === undefined && !has)) node.classList.add(name);
        else node.classList.remove(name);
        return node.classList.contains(name);
      },
    };
    Object.defineProperties(node, {
      className: {
        get: () => String(attributes.get("class") ?? ""),
        set: value => { attributes.set("class", String(value)); },
      },
      id: {
        get: () => String(attributes.get("id") ?? ""),
        set: value => { attributes.set("id", String(value)); },
      },
      children: { get: () => node.childNodes.filter(kid => kid.nodeType === 1) },
      firstElementChild: { get: () => node.children[0] ?? null },
      lastElementChild: { get: () => node.children[node.children.length - 1] ?? null },
      parentElement: { get: () => (node.parentNode?.nodeType === 1 ? node.parentNode : null) },
      nextElementSibling: {
        get: () => {
          const siblings = node.parentNode?.children ?? [];
          return siblings[siblings.indexOf(node) + 1] ?? null;
        },
      },
      previousElementSibling: {
        get: () => {
          const siblings = node.parentNode?.children ?? [];
          return siblings[siblings.indexOf(node) - 1] ?? null;
        },
      },
      isConnected: {
        get: () => {
          let current = node;
          while (current) {
            if (current === document.documentElement) return true;
            current = current.parentNode;
          }
          return false;
        },
      },
      textContent: {
        get: () => node.__text + node.children.map(kid => kid.textContent).join(""),
        set: value => { node.__text = String(value); node.childNodes = []; },
      },
      innerText: {
        get: () => node.textContent,
        set: value => { node.__text = String(value); node.childNodes = []; },
      },
      innerHTML: {
        get: () => node.textContent,
        set: value => { node.__text = String(value); node.childNodes = []; },
      },
      // У <style> браузер отдаёт разобранные правила — по ним inject.js судит,
      // пустила ли страница его стили (CSP). Считаем закрывающие скобки: точный
      // разбор CSS тут не нужен, нужен непустой список.
      sheet: {
        get: () => (node.tagName === "STYLE"
          ? { cssRules: { length: (String(node.__text).match(/\}/g) ?? []).length } }
          : null),
      },
    });
    Object.assign(node, {
      setAttribute(name, value) {
        attributes.set(name, String(value));
        if (name.startsWith("data-")) {
          const key = name.slice(5).replace(/-([a-z])/g, (all, letter) => letter.toUpperCase());
          node.dataset[key] = String(value);
        }
      },
      getAttribute(name) { return attributes.has(name) ? attributes.get(name) : null; },
      hasAttribute(name) { return attributes.has(name); },
      removeAttribute(name) {
        attributes.delete(name);
        if (name.startsWith("data-")) {
          const key = name.slice(5).replace(/-([a-z])/g, (all, letter) => letter.toUpperCase());
          delete node.dataset[key];
        }
      },
      appendChild(kid) {
        kid.parentNode?.removeChild?.(kid);
        kid.parentNode = node;
        node.childNodes.push(kid);
        return kid;
      },
      insertBefore(kid, anchor) {
        kid.parentNode?.removeChild?.(kid);
        kid.parentNode = node;
        const index = anchor ? node.childNodes.indexOf(anchor) : -1;
        if (index < 0) node.childNodes.push(kid); else node.childNodes.splice(index, 0, kid);
        return kid;
      },
      removeChild(kid) {
        node.childNodes = node.childNodes.filter(item => item !== kid);
        kid.parentNode = null;
        return kid;
      },
      remove() { node.parentNode?.removeChild(node); },
      contains(other) {
        let current = other;
        while (current) { if (current === node) return true; current = current.parentNode; }
        return false;
      },
      matches(selector) { return selectorHit(node, selector); },
      closest(selector) {
        let current = node;
        while (current) {
          if (current.nodeType === 1 && selectorHit(current, selector)) return current;
          current = current.parentNode;
        }
        return null;
      },
      querySelector(selector) { return queryAll(node, selector)[0] ?? null; },
      querySelectorAll(selector) { return queryAll(node, selector); },
      getElementsByClassName(name) { return descendants(node).filter(item => item.classList.contains(name)); },
      getBoundingClientRect() {
        const { left, top, width, height } = node.rect;
        return { left, top, width, height, right: left + width, bottom: top + height, x: left, y: top };
      },
      getClientRects() { return [node.getBoundingClientRect()]; },
      addEventListener(type, handler, options) { addListener(node, type, handler, options); },
      removeEventListener(type, handler, options) { removeListener(node, type, handler, options); },
      dispatchEvent(event) { return fireListeners(node, makeEvent(event)); },
      focus() { document.activeElement = node; },
      blur() { if (document.activeElement === node) document.activeElement = null; },
      click() { node.dispatchEvent({ type: "click" }); },
      scrollIntoView() {},
      // Настоящий Animation отдаёт playState и умеет cancel()/finish(); стаб
      // отдаёт то же самое и запоминает себя в списке окна, чтобы тест видел,
      // на каком узле и с какими кадрами крутится пульс.
      animate(frames, options) {
        const animation = {
          node, frames, options, playState: "running",
          finished: Promise.resolve(),
          cancel() { animation.playState = "idle"; },
          finish() { animation.playState = "finished"; },
        };
        animations.push(animation);
        return animation;
      },
      // Удобство тестов: собрать поддерево одной строкой.
      add(tag2, options = {}) {
        const kid = makeNode(tag2);
        if (options.class) kid.className = options.class;
        if (options.id) kid.id = options.id;
        if (options.text) kid.__text = String(options.text);
        if (options.rect) kid.rect = { ...kid.rect, ...options.rect };
        if (options.computed) kid.computed = options.computed;
        for (const [name, value] of Object.entries(options.attrs ?? {})) kid.setAttribute(name, value);
        node.appendChild(kid);
        return kid;
      },
    });
    return node;
  };

  const descendants = root => {
    const out = [];
    const walk = node => {
      for (const kid of node.childNodes) {
        if (kid.nodeType === 1) { out.push(kid); walk(kid); }
      }
    };
    walk(root);
    return out;
  };
  const queryAll = (root, selector) => {
    queries += 1;
    return descendants(root).filter(node => selectorHit(node, selector));
  };

  const makeEvent = source => {
    if (source && typeof source === "object" && source.__event) return source;
    const event = {
      __event: true,
      type: String(source?.type ?? ""),
      detail: source?.detail,
      target: source?.target ?? null,
      defaultPrevented: false,
      bubbles: Boolean(source?.bubbles),
      cancelable: Boolean(source?.cancelable),
      preventDefault() { event.defaultPrevented = true; },
      stopPropagation() {},
      stopImmediatePropagation() { event.__stopped = true; },
      ...source,
    };
    event.preventDefault = () => { event.defaultPrevented = true; };
    event.stopImmediatePropagation = () => { event.__stopped = true; };
    return event;
  };

  const makeStorage = data => {
    const map = new Map(Object.entries(data));
    return {
      get length() { return map.size; },
      key: index => [...map.keys()][index] ?? null,
      getItem: key => (map.has(key) ? map.get(key) : null),
      setItem: (key, value) => { map.set(key, String(value)); },
      removeItem: key => { map.delete(key); },
      clear: () => { map.clear(); },
      _map: map,
    };
  };

  const documentElement = makeNode("html");
  const head = makeNode("head");
  const body = makeNode("body");
  documentElement.rect = { left: 0, top: 0, width: viewport.width, height: viewport.height };
  body.rect = { left: 0, top: 0, width: viewport.width, height: viewport.height };
  documentElement.appendChild(head);
  documentElement.appendChild(body);

  Object.assign(document, {
    nodeType: 9,
    documentElement,
    head,
    body,
    title,
    hidden: false,
    activeElement: null,
    adoptedStyleSheets: [],
    __listeners: new Map(),
    createElement: tag => makeNode(tag),
    createTextNode: text => ({ nodeType: 3, textContent: String(text), parentNode: null }),
    createRange: () => ({
      setStart() {}, setEnd() {}, collapse() {}, selectNodeContents() {},
      getBoundingClientRect: () => ({ left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0 }),
    }),
    getSelection: () => ({
      rangeCount: 0,
      removeAllRanges() {},
      addRange() {},
      getRangeAt: () => null,
      toString: () => "",
    }),
    // Вставка текста, как её делает Chromium: в узел под фокусом, в его конец
    // (курсор в начало команда caretToStart в стабе не двигает — тесту важен
    // сам факт вставки и её однократность).
    execCommand: (name, showUi, value) => {
      if (name !== "insertText") return false;
      const target = document.activeElement;
      if (!target) return false;
      target.__text = `${value}${target.__text}`;
      void showUi;
      return true;
    },
    querySelector: selector => queryAll(documentElement, selector)[0] ?? null,
    querySelectorAll: selector => queryAll(documentElement, selector),
    getElementsByClassName: name => descendants(documentElement).filter(node => node.classList.contains(name)),
    getElementById: id => descendants(documentElement).find(node => node.id === id) ?? null,
    hasFocus: () => hasFocus,
    elementFromPoint: () => null,
    elementsFromPoint: () => [],
    addEventListener(type, handler, options) { addListener(document, type, handler, options); },
    removeEventListener(type, handler, options) { removeListener(document, type, handler, options); },
    dispatchEvent(event) { return fireListeners(document, makeEvent(event)); },
  });

  Object.defineProperty(counters, "sheets", {
    enumerable: true,
    get: () => document.adoptedStyleSheets.length,
  });

  class CSSStyleSheet {
    constructor() { this.cssText = ""; }
    replaceSync(text) { this.cssText = String(text); }
    replace(text) { this.cssText = String(text); return Promise.resolve(this); }
  }
  class MutationObserver {
    constructor(fn) { this.fn = fn; this.live = false; }
    observe() { if (!this.live) { this.live = true; counters.observers += 1; } }
    disconnect() { if (this.live) { this.live = false; counters.observers -= 1; } }
    takeRecords() { return []; }
  }
  class DataTransfer {
    constructor() { this.__data = new Map(); }
    setData(type, value) { this.__data.set(type, String(value)); }
    getData(type) { return this.__data.get(type) ?? ""; }
  }
  const eventClass = extra => class {
    constructor(type, init = {}) {
      Object.assign(this, { type: String(type), defaultPrevented: false }, extra, init);
      this.preventDefault = () => { this.defaultPrevented = true; };
      this.stopPropagation = () => {};
      this.stopImmediatePropagation = () => { this.__stopped = true; };
      this.__event = true;
    }
  };

  const timerHandle = (kind, fn, ms) => {
    const id = timerSeq++;
    timers.set(id, { kind, fn, ms: Number(ms) || 0 });
    if (kind === "interval") counters.intervals += 1;
    else if (kind === "raf") counters.rafs += 1;
    else counters.timers += 1;
    return id;
  };
  const timerDrop = id => {
    const item = timers.get(id);
    if (!item) return;
    timers.delete(id);
    if (item.kind === "interval") counters.intervals -= 1;
    else if (item.kind === "raf") counters.rafs -= 1;
    else counters.timers -= 1;
  };

  // Node нужен одной проверке в разделе 9 (`node instanceof Node`): свой класс
  // узлам стаба не родня, поэтому опознаём их по nodeType.
  const Node = class {};
  Object.defineProperty(Node, Symbol.hasInstance, {
    value: value => Boolean(value && typeof value === "object" && "nodeType" in value),
  });

  // Встроенные объекты языка (Map, JSON, Promise…) в песочницу НЕ кладём: у
  // контекста vm они свои, а хостовые ломали бы `instanceof Map` в разборе
  // стора popout (раздел 12б). Кладём только то, чего у контекста нет.
  const win = {
    console,
    URL,
    document,
    Node,
    location: {
      href,
      pathname: (() => { try { return new URL(href).pathname; } catch { return href; } })(),
      hostname: (() => { try { return new URL(href).hostname; } catch { return ""; } })(),
      origin: (() => { try { return new URL(href).origin; } catch { return ""; } })(),
      search: "", hash: "",
      assign() {}, replace() {}, reload() {},
    },
    history: { length: 1, state: null, pushState() {}, replaceState() {}, back() {}, forward() {}, go() {} },
    localStorage: makeStorage(local),
    sessionStorage: makeStorage(session),
    innerWidth: viewport.width,
    innerHeight: viewport.height,
    devicePixelRatio: 2,
    performance: { now: () => Date.now(), getEntriesByType: () => [] },
    CSSStyleSheet,
    MutationObserver,
    DataTransfer,
    KeyboardEvent: eventClass({ key: "" }),
    ClipboardEvent: eventClass({ clipboardData: null }),
    PopStateEvent: eventClass({ state: null }),
    CustomEvent: eventClass({ detail: null }),
    Event: eventClass({}),
    queueMicrotask: fn => queueMicrotask(fn),
    getComputedStyle: node => {
      const own = node?.computed ?? {};
      const style = node?.style;
      const read = name => own[name] ?? style?.getPropertyValue?.(name) ?? style?.[name] ?? "";
      return {
        display: own.display ?? (style?.display || "block"),
        visibility: own.visibility ?? (style?.visibility || "visible"),
        overflowY: own.overflowY ?? (style?.overflowY || "visible"),
        position: own.position ?? (style?.position || "static"),
        zIndex: own.zIndex ?? (style?.zIndex || "auto"),
        borderTopLeftRadius: own.borderTopLeftRadius ?? "0px",
        borderBottomWidth: own.borderBottomWidth ?? "0px",
        boxShadow: own.boxShadow ?? "none",
        backgroundColor: own.backgroundColor ?? "rgba(0, 0, 0, 0)",
        colorScheme: own.colorScheme ?? "dark",
        paddingBottom: own.paddingBottom ?? "0px",
        getPropertyValue: name => own[name] ?? read(name),
      };
    },
    // prefers-reduced-motion читается ЛЕНИВО, из win.__reducedMotion: тест
    // ставит флаг уже после установки инжекта и гонит перечёт полосы — ровно
    // так системная настройка меняется и в бою.
    matchMedia: query => {
      const media = String(query);
      const matches = /prefers-reduced-motion/.test(media)
        ? (/reduce/.test(media) ? Boolean(win.__reducedMotion) : !win.__reducedMotion)
        : media.includes("dark");
      return {
        matches, media,
        addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {},
      };
    },
    getSelection: () => document.getSelection(),
    requestAnimationFrame: fn => timerHandle("raf", fn, 16),
    cancelAnimationFrame: id => timerDrop(id),
    setTimeout: (fn, ms) => timerHandle("timeout", fn, ms),
    clearTimeout: id => timerDrop(id),
    setInterval: (fn, ms) => timerHandle("interval", fn, ms),
    clearInterval: id => timerDrop(id),
    alert() {}, focus() {}, blur() {}, close() {},
    open: () => null,
    opener: opener ?? null,
    __timers: timers,
    __counters: counters,
  };
  win.window = win;
  win.globalThis = win;
  win.self = win;
  win.top = win;
  win.__listeners = new Map();
  win.addEventListener = (type, handler, options) => addListener(win, type, handler, options);
  win.removeEventListener = (type, handler, options) => removeListener(win, type, handler, options);
  win.dispatchEvent = event => fireListeners(win, makeEvent(event));

  // ---- ручки для тестов -----------------------------------------------------
  const dom = {
    window: win,
    document,
    counters,
    timers,
    // Все анимации окна и только живые (пульс полосы прогресса, WF22).
    animations,
    running: () => animations.filter(item => item.playState === "running"),
    node: makeNode,
    // Сколько раз страницу искали по дереву за всё время жизни окна.
    queries: () => queries,
    query: selector => document.querySelector(selector),
    queryAll: selector => document.querySelectorAll(selector),
    // Число живых таймеров нужного вида.
    count: kind => [...timers.values()].filter(item => item.kind === kind).length,
    // Их номера — по порядку постановки: тику живых цветов достаётся последний.
    ids: kind => [...timers.entries()].filter(([, item]) => item.kind === kind).map(([id]) => id),
    // Прогнать один таймер по id или все таймеры вида.
    fire: id => timers.get(id)?.fn(),
    fireKind: kind => {
      for (const [id, item] of [...timers.entries()]) {
        if (item.kind !== kind) continue;
        if (item.kind !== "interval") timerDrop(id);
        item.fn();
      }
    },
    command: detail => win.dispatchEvent({ type: "myclaude-command", detail }),
    // Адреса модулей для поиска стора (раздел 12б inject.js): их берут из
    // link[rel=modulepreload]. Читается СВОЙСТВО link.href, а не атрибут, —
    // поэтому ставим именно свойство, как это делает браузер.
    modules: (...urls) => urls.map(url => {
      const link = head.add("link", { attrs: { rel: "modulepreload", href: String(url) } });
      link.href = String(url);
      return link;
    }),
    sheets: () => document.adoptedStyleSheets.map(sheet => sheet.cssText).join("\n"),
    // Композер Claude Code: рамка поля, редактор .ProseMirror и строка модели —
    // ровно то дерево, которое ищут findEditor/findShell/findComposerBlock.
    composer: ({ text = "", top = 620 } = {}) => {
      const block = body.add("div", { class: "epitaxy-composer-width", rect: { left: 100, top, width: 1000, height: 160 } });
      const shell = block.add("div", {
        class: "epitaxy-prompt",
        rect: { left: 100, top, width: 1000, height: 120 },
        computed: { borderTopLeftRadius: "10px" },
      });
      const root = shell.add("div", {
        class: "editor-root",
        rect: { left: 110, top: top + 10, width: 980, height: 100 },
        computed: { overflowY: "auto" },
      });
      const editor = root.add("div", {
        class: "ProseMirror",
        attrs: { contenteditable: "true" },
        rect: { left: 110, top: top + 10, width: 980, height: 100 },
      });
      editor.__text = text;
      const modelRow = block.add("div", {
        class: "model-row",
        rect: { left: 100, top: top + 124, width: 1000, height: 28 },
      });
      return { block, shell, root, editor, modelRow };
    },
  };
  return dom;
};

export { selectorHit };
