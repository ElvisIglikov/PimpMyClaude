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

// ---- канал между окнами ----------------------------------------------------
// BroadcastChannel: им окна Claude передают друг другу шаг ступени (раздел 10
// inject.js, #6900). Реестр каналов общий на МОДУЛЬ, а не на окно: два
// loadInject в одном тесте — это два окна одного Claude, и канал у них обязан
// быть один, иначе проверять «нажал с Shift в одном окне — повторили все»
// нечем. Правила как в браузере: своего сообщения отправитель не слышит,
// close() снимает канал с реестра.
const broadcastChannels = new Map();
class BroadcastChannel {
  constructor(name) {
    this.name = String(name);
    this.onmessage = null;
    this.closed = false;
    const list = broadcastChannels.get(this.name) ?? [];
    list.push(this);
    broadcastChannels.set(this.name, list);
  }
  postMessage(data) {
    if (this.closed) return;
    for (const other of [...(broadcastChannels.get(this.name) ?? [])]) {
      if (other === this || other.closed) continue;
      other.onmessage?.({ data });
    }
  }
  close() {
    this.closed = true;
    broadcastChannels.set(this.name, (broadcastChannels.get(this.name) ?? []).filter(item => item !== this));
  }
}

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
  // Рамка окна на экране (WF77, раздел 12в): [screenX, screenY, outerWidth,
  // outerHeight]. Не задал тест — свойств у окна НЕТ вовсе, как у страницы,
  // которой браузер их не дал: ответ chats() тогда идёт без поля frame.
  frame = null,
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
  // Картинки, разобранные createImageBitmap (#7532): тест видит, закрыты ли они.
  const bitmaps = [];

  const makeStyle = () => {
    const map = new Map();
    const priorities = new Map();
    const api = {
      setProperty: (name, value, priority = "") => { map.set(name, String(value)); priorities.set(name, priority); },
      removeProperty: name => { map.delete(name); priorities.delete(name); },
      getPropertyValue: name => map.get(name) ?? "",
      getPropertyPriority: name => priorities.get(name) ?? "",
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

  // Холст 2D (#7532, номера скриншотов): пикселей нет, есть ровно то, чем
  // рисуется номер. Вызовы контекста пишутся в canvas.__ops, а toBlob отдаёт
  // Blob, чьи байты — JSON {width, height, type, ops}: тест читает, ЧТО
  // нарисовано. Отказы браузера задаёт тест: win.__canvasFail = "context"
  // (getContext → null) или "toBlob" (callback(null)). toBlob, как у браузера,
  // отвечает не сразу.
  const makeCanvas = node => {
    node.width = 300;
    node.height = 150;
    node.__ops = [];
    const context = {
      font: "10px sans-serif", fillStyle: "#000000", strokeStyle: "#000000", lineWidth: 1,
      textAlign: "start", textBaseline: "alphabetic",
      measureText: text => ({ width: String(text).length * (Number(/(\d+(?:\.\d+)?)px/.exec(context.font)?.[1]) || 10) * 0.6 }),
    };
    for (const name of ["drawImage", "beginPath", "roundRect", "fill", "stroke", "fillText"]) {
      context[name] = (...args) => {
        node.__ops.push({
          op: name,
          args: args.map(arg => (arg && typeof arg === "object" ? arg.__label ?? "object" : arg)),
          font: context.font,
          fillStyle: context.fillStyle,
        });
      };
    }
    node.getContext = kind => (kind === "2d" && win.__canvasFail !== "context" ? context : null);
    node.toBlob = (callback, type = "image/png", quality) => {
      const failed = win.__canvasFail === "toBlob";
      queueMicrotask(() => callback(failed ? null : new Blob(
        [JSON.stringify({ width: node.width, height: node.height, type, quality, ops: node.__ops })], { type })));
    };
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
  // Порядок — как в браузере на самой цели: слушатели захвата (capture) первыми,
  // остальные — в порядке подписки. На этом стоит «Копировать в буфер»: его
  // обработчик copy на захвате обязан идти раньше чужих (WF69).
  const isCapture = options => options === true || Boolean(options && options.capture);
  const fireListeners = (target, event) => {
    const list = [...(listenersOf(target).get(event.type) ?? [])];
    const ordered = [...list.filter(item => isCapture(item.options)), ...list.filter(item => !isCapture(item.options))];
    for (const item of ordered) {
      if (event.__stopped) break;
      try { item.handler.call(target, event); } catch (error) { event.__error = error; }
    }
    return !event.defaultPrevented;
  };

  const document = {};

  // Настоящий текстовый узел (WF78): nodeValue — источник правды, textContent
  // ходит за ним. Без этого раздел 12ж (панель лимитов) стендом не проверить:
  // он меняет ИМЕННО nodeValue существующего узла — присваивание textContent
  // уничтожило бы узел, за который держится React.
  const makeText = value => {
    const text = {
      nodeType: 3,
      nodeValue: String(value ?? ""),
      ownerDocument: document,
      parentNode: null,
      remove() { text.parentNode?.removeChild?.(text); },
      cloneNode() { return makeText(text.nodeValue); },
    };
    Object.defineProperties(text, {
      textContent: { get: () => text.nodeValue, set: next => { text.nodeValue = String(next); } },
      data: { get: () => text.nodeValue, set: next => { text.nodeValue = String(next); } },
      isConnected: {
        get: () => Boolean(text.parentNode?.isConnected),
      },
      parentElement: { get: () => (text.parentNode?.nodeType === 1 ? text.parentNode : null) },
      nextSibling: { get: () => siblingOf(text, 1) },
      previousSibling: { get: () => siblingOf(text, -1) },
    });
    return text;
  };
  const siblingOf = (item, step) => {
    const kids = item.parentNode?.__kids;
    if (!kids) return null;
    const at = kids.indexOf(item);
    return at < 0 ? null : kids[at + step] ?? null;
  };

  // children и childNodes — как в Chromium: HTMLCollection / NodeList, а не
  // массив. Индексы, length, item(), перебор for…of и [...x]; у NodeList ещё
  // forEach; filter/map/find/indexOf НЕТ — страница, которая их зовёт, падает
  // и в тесте, а не только вживую (WF144, класс ошибки foldFind #9055).
  // Вид привязан к самому массиву: тот же массив — тот же объект (как живой
  // NodeList), переписали детей — новый.
  const listViews = new WeakMap();
  const listView = (items, nodeList) => {
    const cached = nodeList ? listViews.get(items) : null;
    if (cached) return cached;
    const view = new Proxy(Object.create(null), {
      get(target, key) {
        if (key === "length") return items.length;
        if (key === Symbol.iterator) return () => items[Symbol.iterator]();
        if (key === "item") return index => items[index] ?? null;
        if (nodeList && key === "forEach") return (fn, self) => items.forEach((kid, index) => fn.call(self, kid, index, view));
        if (key === Symbol.toStringTag) return nodeList ? "NodeList" : "HTMLCollection";
        if (typeof key === "string" && /^\d+$/.test(key)) return items[key];
        return undefined;
      },
      has(target, key) { return key === "length" || (typeof key === "string" && /^\d+$/.test(key) && Number(key) < items.length); },
      ownKeys() { return [...items.keys()].map(String); },
      getOwnPropertyDescriptor(target, key) {
        return typeof key === "string" && /^\d+$/.test(key) && Number(key) < items.length
          ? { value: items[key], enumerable: true, configurable: true, writable: false } : undefined;
      },
      set() { return false; },
    });
    if (nodeList) listViews.set(items, view);
    return view;
  };

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
      __kids: [],
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
      childNodes: { get: () => listView(node.__kids, true), set: value => { node.__kids = [...value]; } },
      children: { get: () => listView(node.__kids.filter(kid => kid.nodeType === 1), false) },
      firstChild: { get: () => node.__kids[0] ?? null },
      // Соседи с текстовыми узлами — как в Chromium (WF176: место «✓ сделал» в пункте).
      lastChild: { get: () => node.__kids[node.__kids.length - 1] ?? null },
      nextSibling: { get: () => siblingOf(node, 1) },
      previousSibling: { get: () => siblingOf(node, -1) },
      firstElementChild: { get: () => node.children[0] ?? null },
      lastElementChild: { get: () => node.children[node.children.length - 1] ?? null },
      parentElement: { get: () => (node.parentNode?.nodeType === 1 ? node.parentNode : null) },
      nextElementSibling: {
        get: () => {
          const siblings = [...(node.parentNode?.children ?? [])];
          return siblings[siblings.indexOf(node) + 1] ?? null;
        },
      },
      previousElementSibling: {
        get: () => {
          const siblings = [...(node.parentNode?.children ?? [])];
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
      // Обходим childNodes, а не children: у узла бывают и текстовые дети
      // (makeText), и порядок между ними и элементами важен.
      textContent: {
        get: () => node.__text + node.__kids.map(kid => (kid.nodeType === 3 ? String(kid.nodeValue ?? "") : kid.textContent)).join(""),
        set: value => { node.__text = String(value); node.__kids = []; },
      },
      innerText: {
        get: () => node.__text + node.__kids.map(kid => kid.nodeType === 3 ? String(kid.nodeValue ?? "")
          : kid.style.getPropertyValue("display") === "none" ? "" : kid.innerText).join(""),
        set: value => { node.__text = String(value); node.__kids = []; },
      },
      innerHTML: {
        get: () => node.textContent,
        set: value => { node.__text = String(value); node.__kids = []; },
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
      getAttributeNames() { return [...attributes.keys()]; },
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
        node.__kids.push(kid);
        return kid;
      },
      // Значок микрофона (раздел 12з) складывает свои три фигуры одним append.
      append(...kids) {
        for (const kid of kids) node.appendChild(kid);
      },
      insertBefore(kid, anchor) {
        kid.parentNode?.removeChild?.(kid);
        kid.parentNode = node;
        const index = anchor ? node.__kids.indexOf(anchor) : -1;
        if (index < 0) node.__kids.push(kid); else node.__kids.splice(index, 0, kid);
        return kid;
      },
      removeChild(kid) {
        node.__kids = node.__kids.filter(item => item !== kid);
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
      // Клон, как у браузера: атрибуты, текст, стили и (при deep) дети — да;
      // слушатели и свойства-расширения (React-волокно) — нет. Им живёт
      // «Открыть в Chrome» (раздел 12г, WF67): клон пункта меню Claude.
      cloneNode(deep = false) {
        const copy = makeNode(node.tagName);
        for (const [name, value] of attributes) copy.setAttribute(name, value);
        copy.__text = node.__text;
        for (const [name, value] of node.style._map) copy.style.setProperty(name, value);
        copy.rect = { ...node.rect };
        copy.computed = { ...node.computed };
        if (deep) for (const kid of node.childNodes) {
          copy.appendChild(kid.nodeType === 1 ? kid.cloneNode(true) : makeText(kid.nodeValue ?? kid.textContent));
        }
        return copy;
      },
      closest(selector) {
        let current = node;
        while (current) {
          if (current.nodeType === 1 && selectorHit(current, selector)) return current;
          current = current.parentNode;
        }
        return null;
      },
      querySelector(selector) { return queryAll(node, selector)[0] ?? null; },
      // NodeList / HTMLCollection, как в Chromium: без filter/map (WF144).
      querySelectorAll(selector) { return listView(queryAll(node, selector), true); },
      getElementsByClassName(name) { return listView(descendants(node).filter(item => item.classList.contains(name)), false); },
      // Свойство translate (своё и предков) сдвигает коробку, как в Chromium (WF183: Enter над кружком).
      getBoundingClientRect() {
        let { left, top } = node.rect;
        const { width, height } = node.rect;
        for (let item = node; item && item.nodeType === 1; item = item.parentNode) {
          const shift = String(item.style?.getPropertyValue?.("translate") ?? "").trim().match(/^(-?[\d.]+)px(?:\s+(-?[\d.]+)px)?$/);
          if (shift) { left += Number(shift[1]); top += Number(shift[2] ?? 0); }
        }
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
    if (node.tagName === "CANVAS") makeCanvas(node);
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
    // Значок микрофона (раздел 12з) рисуется узлами SVG: пространство имён стабу
    // безразлично, узел тот же.
    createElementNS: (ns, tag) => makeNode(tag),
    createTextNode: text => makeText(text),
    // Курсор, как в Chromium, — только «в начало» и «в конец» поля: setStart(узел, 0) и collapse(true) —
    // начало, selectNodeContents + collapse(false) — конец; addRange ставит его (document.__caret).
    createRange: () => ({
      __at: "start",
      setStart(node, offset) { this.__at = offset === 0 ? "start" : "end"; },
      setEnd() {},
      collapse(toStart) { if (toStart === false) this.__at = "end"; else if (toStart === true && this.__whole) this.__at = "start"; },
      selectNodeContents() { this.__whole = true; },
      getBoundingClientRect: () => ({ left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0 }),
    }),
    getSelection: () => ({
      rangeCount: 0,
      removeAllRanges() {},
      addRange(range) { document.__caret = range?.__at ?? null; },
      getRangeAt: () => null,
      toString: () => "",
    }),
    // Вставка текста, как её делает Chromium: в узел под фокусом, в его конец
    // (курсор в начало команда caretToStart в стабе не двигает — тесту важен
    // сам факт вставки и её однократность).
    // selectAll помечает поле «выделено целиком»: следующая вставка заменяет
    // его текст, а не дописывает. Так «Обкэшить» кладёт перенос поверх чужого
    // черновика (WF50, #5781).
    execCommand: (name, showUi, value) => {
      if (name === "selectAll") {
        document.__selectedAll = document.activeElement;
        return Boolean(document.activeElement);
      }
      // Копия, как её делает Chromium: событие copy на document с DataTransfer;
      // обработчик, вызвавший preventDefault, сам задаёт содержимое буфера
      // («Копировать в буфер», WF69). Что легло — в document.__clipboard;
      // никто не задал — буфер не тронут, команда отвечает false.
      if (name === "copy") {
        const data = new DataTransfer();
        const event = makeEvent({ type: "copy", clipboardData: data, cancelable: true });
        const passed = fireListeners(document, event);
        if (!passed) document.__clipboard = { text: data.getData("text/plain"), html: data.getData("text/html") };
        return !passed;
      }
      // delete по выделенному целиком полю — поле пустеет (стирание своей заглушки, 26.09).
      if (name === "delete") {
        const target = document.activeElement;
        if (!target || document.__selectedAll !== target) return false;
        target.__text = "";
        document.__selectedAll = null;
        return true;
      }
      if (name !== "insertText") return false;
      const target = document.activeElement;
      if (!target) return false;
      if (document.__selectedAll === target) {
        target.__text = String(value);
        document.__selectedAll = null;
      } else if (document.__caret === "end") {
        // Курсор в конце — текст ложится в конец, курсор остаётся за ним.
        target.__text = `${target.__text}${value}`;
      } else {
        target.__text = `${value}${target.__text}`;
      }
      void showUi;
      return true;
    },
    querySelector: selector => queryAll(documentElement, selector)[0] ?? null,
    querySelectorAll: selector => listView(queryAll(documentElement, selector), true),
    getElementsByClassName: name => listView(descendants(documentElement).filter(node => node.classList.contains(name)), false),
    getElementById: id => descendants(documentElement).find(node => node.id === id) ?? null,
    // Фокус читается лениво: тест может сменить его на лету через win.__hasFocus (WF113).
    hasFocus: () => (typeof win.__hasFocus === "boolean" ? win.__hasFocus : hasFocus),
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
    constructor() {
      this.__data = new Map();
      // files и items.add — ими едут вложения переноса (WF50, #5773).
      this.files = [];
      this.items = { add: file => { this.files.push(file); return file; } };
    }
    setData(type, value) { this.__data.set(type, String(value)); }
    getData(type) { return this.__data.get(type) ?? ""; }
  }
  // Blob и File — ровно столько, сколько спрашивает inject.js: размер, тип, имя,
  // slice() и arrayBuffer() (по ним считается ключ содержимого — djb2 по первым
  // 8 КБ). Байты держим массивом чисел: тесту важны их равенство и длина.
  class Blob {
    constructor(parts = [], options = {}) {
      const bytes = [];
      for (const part of parts ?? []) {
        if (part && Array.isArray(part.__bytes)) bytes.push(...part.__bytes);
        else if (typeof part === "string") for (const char of part) bytes.push(char.charCodeAt(0) & 255);
        else if (part && typeof part.length === "number") bytes.push(...part);
      }
      this.__bytes = bytes;
      this.size = bytes.length;
      this.type = String(options?.type ?? "");
    }
    slice(from = 0, to = this.size) {
      const cut = new Blob([], { type: this.type });
      cut.__bytes = this.__bytes.slice(from, to);
      cut.size = cut.__bytes.length;
      return cut;
    }
    arrayBuffer() { return Promise.resolve(Uint8Array.from(this.__bytes).buffer); }
  }
  class File extends Blob {
    constructor(parts, name, options = {}) {
      super(parts, options);
      this.name = String(name);
      this.lastModified = Number(options?.lastModified ?? Date.now());
    }
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
    ...(frame ? { screenX: frame[0], screenY: frame[1], outerWidth: frame[2], outerHeight: frame[3] } : {}),
    devicePixelRatio: 2,
    performance: { now: () => Date.now(), getEntriesByType: () => [] },
    CSSStyleSheet,
    BroadcastChannel,
    PointerEvent: eventClass({ pointerId: 0, pointerType: "mouse", isPrimary: true, button: 0, buttons: 0, clientX: 0, clientY: 0 }),
    // «Как мышью» (pressLikeMouse): меню модели «Нового чата» (#7072) ждёт и click.
    MouseEvent: eventClass({ button: 0, buttons: 0, clientX: 0, clientY: 0, detail: 0 }),
    MutationObserver,
    DataTransfer,
    Blob,
    File,
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
        opacity: own.opacity ?? (style?.opacity || "1"),
        textOverflow: own.textOverflow ?? (style?.textOverflow || "clip"),
        webkitLineClamp: own.webkitLineClamp ?? (style?.webkitLineClamp || "none"),
        overflowY: own.overflowY ?? (style?.overflowY || "visible"),
        position: own.position ?? (style?.position || "static"),
        zIndex: own.zIndex ?? (style?.zIndex || "auto"),
        borderTopLeftRadius: own.borderTopLeftRadius ?? "0px",
        borderBottomWidth: own.borderBottomWidth ?? "0px",
        boxShadow: own.boxShadow ?? "none",
        backgroundColor: own.backgroundColor ?? "rgba(0, 0, 0, 0)",
        // Цвет текста (WF84: номера и карточка красятся от темы поля). Не задал
        // тест — пусто, и страница берёт запасной цвет кожи карточки.
        color: own.color ?? "",
        // Шрифт (WF172: полоса Рика берёт гарнитуру и кегль подписей нижней строки поля). Не задал тест —
        // пусто («не знаю»), и страница берёт свой запасной шрифт.
        fontFamily: own.fontFamily ?? "",
        fontSize: own.fontSize ?? "",
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
    // Разбор картинки (#7532): размеры — из file.__image (dom.image); без них —
    // отказ, как у битого файла. win.__bitmapHang — разбор не кончается никогда
    // (проверка срока). Выданное копится в dom.bitmaps.
    createImageBitmap: source => {
      if (win.__bitmapHang) return new Promise(() => {});
      const image = source?.__image;
      if (!image) return Promise.reject(new Error("InvalidStateError: The source image could not be decoded."));
      const bitmap = {
        width: image.width, height: image.height, __label: `bitmap ${image.width}x${image.height}`, closed: false,
        close() { bitmap.closed = true; },
      };
      bitmaps.push(bitmap);
      return Promise.resolve(bitmap);
    },
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
    // Элемент с НАСТОЯЩИМ текстовым узлом внутри — так устроена панель лимитов
    // Claude (раздел 12ж): страница меняет nodeValue этого узла и только его.
    // Возвращает сам элемент; текстовый узел у него один, как у React.
    leaf: (parent, tag, text, options = {}) => {
      const node = parent.add(tag, options);
      node.appendChild(makeText(text));
      return node;
    },
    // Перерисовка React-ом: текст узла возвращается к английскому оригиналу
    // ровно тем же способом, каким это делает React, — записью в nodeValue.
    retext: (element, text) => {
      const node = [...element.childNodes].find(kid => kid.nodeType === 3);
      if (node) node.nodeValue = String(text);
      return node;
    },
    // Сколько раз страницу искали по дереву за всё время жизни окна.
    queries: () => queries,
    query: selector => document.querySelector(selector),
    // Тестам — обычный массив (страница видит NodeList).
    queryAll: selector => [...document.querySelectorAll(selector)],
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
    // Роутер по требованию (WF82, обход чатов раздела 12е): у history появляется
    // стек записей, а pushState/replaceState/go двигают location.pathname. Зовёт
    // его только тест, которому он нужен: умолчание стенда — прежние пустые
    // заглушки, а тик 12е гоняют и чужие наборы (fireKind("interval")).
    // Вызывать ПОСЛЕ loadInject: инжект оборачивает pushState своим
    // наблюдателем, и роутер ставит свои методы поверх.
    // Как у Chromium (проверяющий WF82): у записи ключ, window.navigation
    // отдаёт записи и traverseTo(key); cap — потолок записей (у Chromium 50,
    // лишняя старейшая выпадает, и history.length дальше не растёт).
    router: ({ cap = Infinity } = {}) => {
      const history = win.history;
      let seq = 0;
      const entry = path => ({ path: String(path), key: `key-${seq += 1}` });
      const entries = [entry(win.location.pathname)];
      let index = 0;
      const show = () => {
        const path = entries[index].path;
        win.location.pathname = path;
        win.location.href = `${win.location.origin}${path}`;
      };
      Object.defineProperty(history, "length", { configurable: true, enumerable: true, get: () => entries.length });
      history.pushState = (data, title, url) => {
        entries.splice(index + 1);
        entries.push(entry(url));
        while (entries.length > cap) entries.shift();
        index = entries.length - 1;
        history.state = data ?? null;
        show();
      };
      // replace меняет адрес записи, ключ остаётся тем же — как у Navigation API.
      history.replaceState = (data, title, url) => {
        entries[index] = { ...entries[index], path: String(url) };
        history.state = data ?? null;
        show();
      };
      history.go = delta => {
        const step = Number(delta) || 0;
        const next = index + step;
        if (!step || next < 0 || next >= entries.length) return;
        index = next;
        show();
      };
      history.back = () => history.go(-1);
      history.forward = () => history.go(1);
      const view = (item, at) => ({ key: item.key, url: `${win.location.origin}${item.path}`, index: at, sameDocument: true });
      win.navigation = {
        get currentEntry() { return view(entries[index], index); },
        entries: () => entries.map(view),
        // Неизвестный ключ — отказ промисом, как у браузера (InvalidStateError).
        traverseTo: key => {
          const at = entries.findIndex(item => item.key === key);
          if (at < 0) {
            const refused = Promise.reject(new Error("InvalidStateError"));
            refused.catch(() => {});
            return { committed: refused, finished: refused };
          }
          history.go(at - index);
          const done = Promise.resolve();
          return { committed: done, finished: done };
        },
      };
      return {
        navigate: path => history.pushState(null, "", path),
        entries: () => entries.map(item => item.path),
        index: () => index,
      };
    },
    // Файл, как его кладёт Элвис в поле ввода. body — содержимое: по нему
    // считается ключ содержимого, и два разных файла с одним именем в тесте
    // отличаются именно им.
    file: (name, { type = "image/png", body = name } = {}) => new File([body], name, { type }),
    // Картинка из буфера обмена (#7532): тот же File, но с размерами — её
    // разбирает createImageBitmap. Файл из dom.file() «не разбирается».
    image: (name, { width = 1600, height = 1000, type = "image/png", body = name } = {}) => {
      const file = new File([body], name, { type });
      file.__image = { width, height };
      return file;
    },
    bitmaps,
    // Плашка вложения в поле ввода: превью и кнопка снятия — те самые приметы,
    // по которым inject.js считает вложения ШТУКАМИ (WF50).
    pill: (block, { name = "image.png" } = {}) => {
      const pill = block.add("div", { class: "epitaxy-attachment-pill" });
      pill.add("img", { attrs: { src: `blob:claude/${name}` } });
      pill.add("button", { attrs: { "aria-label": `Remove ${name}` } });
      return pill;
    },
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
    // left и width — для тех проверок, где поле стоит НЕ по центру окна
    // (открытая боковая панель уводит его вправо): по умолчанию стенд прежний.
    composer: ({ text = "", top = 620, left = 100, width = 1000 } = {}) => {
      const block = body.add("div", { class: "epitaxy-composer-width", rect: { left, top, width, height: 160 } });
      const shell = block.add("div", {
        class: "epitaxy-prompt",
        rect: { left, top, width, height: 120 },
        computed: { borderTopLeftRadius: "10px" },
      });
      const root = shell.add("div", {
        class: "editor-root",
        rect: { left: left + 10, top: top + 10, width: width - 20, height: 100 },
        computed: { overflowY: "auto" },
      });
      const editor = root.add("div", {
        class: "ProseMirror",
        attrs: { contenteditable: "true" },
        rect: { left: left + 10, top: top + 10, width: width - 20, height: 100 },
      });
      editor.__text = text;
      const modelRow = block.add("div", {
        class: "model-row",
        rect: { left, top: top + 124, width, height: 28 },
      });
      return { block, shell, root, editor, modelRow };
    },
  };
  return dom;
};

export { selectorHit };
