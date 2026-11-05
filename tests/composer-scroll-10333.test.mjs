// Вставка прокручивает поле ввода до конца (#10333). Слово Элвиса 19.10 14:30: когда происходит вставка в
// поле ввода, PMP не прокручивает до конца поле справа — вставленное должно быть видно. У поля свой
// прокручиваемый контейнер (широкий вид — колонка справа, узкое окно — корень поля с ручкой высоты); после
// вставки он оставался на месте, и текст уходил вниз за край.
//
// Здесь: ⌘V в поле (слушатель paste на захвате document), свои вставки через execCommand («🚀 Workflow»,
// «Обкэшить», слова-действия), курсор не в конце — видна строка курсора, поле без прокрутки, чужие поля,
// набор руками и dispose().
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

// Поле, как в узком окне: редактор внутри корня с overflow-y:auto (dom.composer), текста больше, чем видно.
const page = ({ text = "", scroll = 2000, client = 300, href, storage } = {}) =>
  loadInject({
    href,
    storage,
    html: dom => {
      const parts = dom.composer({ text });
      Object.assign(parts.root, { scrollHeight: scroll, clientHeight: client });
      parts.line = parts.editor.add("p", { text: "" });
      parts.search = dom.document.body.add("input", { attrs: { type: "text" } });
      return parts;
    },
  });

const paste = (loaded, target) => loaded.document.dispatchEvent({
  type: "paste",
  target,
  clipboardData: { files: [], getData: () => "длинный текст" },
});
// Прокрутка ждёт два кадра: после первого контейнер ещё на месте.
const frames = loaded => { loaded.dom.fireKind("raf"); loaded.dom.fireKind("raf"); };
const last = loaded => plain(loaded.api.status().composerScroll.last);

test("⌘V в поле: контейнер поля прокручен до конца через два кадра", () => {
  const loaded = page();
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  assert.equal(paste(loaded, loaded.parts.line), true, "вставку не отменяем — её делает Claude");
  loaded.dom.fireKind("raf");
  assert.equal(loaded.parts.root.scrollTop, 0, "после первого кадра ещё рано: вставка дорисовывается");
  loaded.dom.fireKind("raf");
  assert.equal(loaded.parts.root.scrollTop, 2000, "последняя строка вставки видна");
  assert.equal(last(loaded).mode, "end");
  assert.equal(loaded.api.status().composerScroll.runs, 1);
  loaded.api.dispose();
});

test("широкий вид: контейнер — предок поля через обёртку без прокрутки", () => {
  const loaded = loadInject({
    html: dom => {
      const parts = dom.composer();
      // Колонка справа: поле → обёртка без прокрутки → `div:has(> .ProseMirror)` с прокруткой.
      const column = parts.shell.add("div", { computed: { overflowY: "auto" } });
      const wrap = column.add("div");
      parts.root.computed = {};
      wrap.appendChild(parts.editor);
      Object.assign(column, { scrollHeight: 1800, clientHeight: 600 });
      parts.column = column;
      return parts;
    },
  });
  paste(loaded, loaded.parts.editor);
  frames(loaded);
  assert.equal(loaded.parts.column.scrollTop, 1800);
});

test("поле без прокрутки: ничего не двигаем и не падаем", () => {
  const loaded = page({ scroll: 100, client: 300 });
  paste(loaded, loaded.parts.editor);
  frames(loaded);
  assert.equal(loaded.parts.root.scrollTop, 0);
  assert.equal(last(loaded).mode, "none", "контейнеру некуда ехать");
});

test("выше блока ввода не ищем: ленту и страницу вставка в поле не двигает", () => {
  const loaded = page({ scroll: 100, client: 300 });
  const { body } = loaded.document;
  body.computed = { overflowY: "auto" };
  Object.assign(body, { scrollHeight: 5000, clientHeight: 800 });
  paste(loaded, loaded.parts.editor);
  frames(loaded);
  assert.equal(body.scrollTop, 0);
});

test("чужое поле (поиск чатов) и набор руками — поле не прокручиваем", () => {
  const loaded = page();
  paste(loaded, loaded.parts.search);
  loaded.document.dispatchEvent({ type: "keydown", key: "а", code: "KeyF", target: loaded.parts.line });
  loaded.document.dispatchEvent({ type: "input", inputType: "insertText", target: loaded.parts.line });
  frames(loaded);
  assert.equal(loaded.parts.root.scrollTop, 0);
  assert.equal(loaded.api.status().composerScroll.runs, 0);
});

test("вставки подряд в один кадр — одна прокрутка", () => {
  const loaded = page();
  paste(loaded, loaded.parts.line);
  paste(loaded, loaded.parts.line);
  loaded.inner.composerScrollToEnd(loaded.parts.editor);
  frames(loaded);
  assert.equal(loaded.parts.root.scrollTop, 2000);
  assert.equal(loaded.api.status().composerScroll.runs, 1);
});

// Курсор не в конце (Workflow перед черновиком, вставка в середину): контейнер едет ровно до строки курсора.
// node — узел курсора (по умолчанию строка <p>), charRect — рамка соседнего знака (диапазон в один знак).
const ZERO = { top: 0, bottom: 0, height: 0 };
const caretAt = (loaded, { rect, tail, node, charRect = ZERO }) => {
  const focus = node ?? loaded.parts.line;
  loaded.document.getSelection = () => ({
    rangeCount: 1,
    focusNode: focus,
    focusOffset: 0,
    getRangeAt: () => ({ getBoundingClientRect: () => rect }),
  });
  loaded.document.createRange = () => ({
    setStart() {}, setEnd() {}, toString: () => tail, getBoundingClientRect: () => charRect,
  });
};

test("курсор в середине ниже края: видна строка курсора, а не конец поля", () => {
  const loaded = page();
  // Корень поля в стабе — с 630 по 730 по высоте экрана.
  loaded.parts.root.scrollTop = 500;
  caretAt(loaded, { rect: { top: 760, bottom: 780, height: 20 }, tail: "черновик дальше" });
  paste(loaded, loaded.parts.line);
  frames(loaded);
  assert.equal(loaded.parts.root.scrollTop, 550, "ровно на выступ строки курсора");
  assert.equal(last(loaded).mode, "caret");
});

test("курсор в середине выше края: контейнер едет вверх до строки", () => {
  const loaded = page();
  loaded.parts.root.scrollTop = 500;
  caretAt(loaded, { rect: { top: 600, bottom: 620, height: 20 }, tail: "черновик дальше" });
  paste(loaded, loaded.parts.line);
  frames(loaded);
  assert.equal(loaded.parts.root.scrollTop, 470);
});

test("курсор в середине и виден: контейнер на месте", () => {
  const loaded = page();
  loaded.parts.root.scrollTop = 500;
  caretAt(loaded, { rect: { top: 660, bottom: 680, height: 20 }, tail: "черновик дальше" });
  paste(loaded, loaded.parts.line);
  frames(loaded);
  assert.equal(loaded.parts.root.scrollTop, 500);
});

test("курсор в начале строки, Chromium отдал нули: строка — по рамке соседнего знака", () => {
  const loaded = page();
  loaded.parts.root.scrollTop = 500;
  const text = loaded.document.createTextNode("черновик дальше");
  loaded.parts.line.appendChild(text);
  caretAt(loaded, { rect: ZERO, node: text, charRect: { top: 760, bottom: 780, height: 20 }, tail: "черновик дальше" });
  paste(loaded, loaded.parts.line);
  frames(loaded);
  assert.equal(loaded.parts.root.scrollTop, 550);
  assert.equal(last(loaded).mode, "caret");
});

test("пустая строка без рамки курсора: узел строки, но не выше одной строки", () => {
  const loaded = page();
  loaded.parts.root.scrollTop = 500;
  // Узел курсора высотой в 18 строк, его верх виден (630…730): курсор в его начале — контейнер на месте.
  Object.assign(loaded.parts.line, { rect: { left: 110, top: 640, width: 980, height: 360 },
    computed: { "line-height": "20px" } });
  caretAt(loaded, { rect: ZERO, tail: "черновик дальше" });
  paste(loaded, loaded.parts.line);
  frames(loaded);
  assert.equal(loaded.parts.root.scrollTop, 500, "низ узла за краем, а курсор в его первой строке — виден");
});

test("за курсором одни пробелы: курсор в конце — едем до конца", () => {
  const loaded = page();
  caretAt(loaded, { rect: { top: 660, bottom: 680, height: 20 }, tail: " \n " });
  paste(loaded, loaded.parts.line);
  frames(loaded);
  assert.equal(loaded.parts.root.scrollTop, 2000);
  assert.equal(last(loaded).mode, "end");
});

test("«🚀 Workflow» (execCommand, без события paste) прокручивает поле", () => {
  const loaded = page();
  assert.equal(loaded.inner.runWorkflowCommand({ text: "Работаем по WORKFLOW.md" }), true);
  assert.match(loaded.parts.editor.textContent, /Работаем по WORKFLOW\.md/);
  frames(loaded);
  assert.equal(loaded.parts.root.scrollTop, 2000);
});

test("«Обкэшить» (перенос ложится execCommand) прокручивает поле", () => {
  const loaded = page({
    href: "https://claude.ai/epitaxy/local_aaa",
    storage: { local: { "myclaude-cashout": JSON.stringify({ at: Date.now(), text: "Перенос из прошлого чата" }) } },
  });
  assert.equal(loaded.inner.tryPasteCashout(), "ждём доезда");
  assert.match(loaded.parts.editor.textContent, /Перенос из прошлого чата/);
  frames(loaded);
  assert.equal(loaded.parts.root.scrollTop, 2000);
});

test("слова-действия (sayWrite) прокручивают поле", () => {
  const loaded = page();
  loaded.inner.sayToggle("Да");
  assert.match(loaded.parts.editor.textContent, /Да/);
  frames(loaded);
  assert.equal(loaded.parts.root.scrollTop, 2000);
});

test("dispose снимает слушатель и ждущий кадр", () => {
  const loaded = page();
  paste(loaded, loaded.parts.line);
  loaded.api.dispose();
  frames(loaded);
  assert.equal(loaded.parts.root.scrollTop, 0, "кадр после dispose не прокручивает");
  paste(loaded, loaded.parts.line);
  frames(loaded);
  assert.equal(loaded.parts.root.scrollTop, 0, "слушателя больше нет");
});
