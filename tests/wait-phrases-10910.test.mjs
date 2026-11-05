// #10910 (страница, раздел 12с², page/522-wait-phrases.js): в разделе «Ждёт тебя» ответа жирные фразы в «ёлочках»
// (**«выкладывай магнит»**) нажимаются сами. Слово Элвиса 24.10: «ты делай их кликабельными, чтобы я мог на
// них понажимать. Тик-тык-тык-тык, чтоб я пронажимал, и это всё в поле ввода ставилось». Клик — фраза без кавычек
// в поле отдельной строкой, НЕ отправляется; ещё клик — строка снята; свой текст Элвиса не трогается. Своих кнопок
// нет (решение 22.10, #10643): метка на родном strong. Поле и курсор — стенд нажималок (nazhimalki-wf98).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const MARK = "data-myclaude-wait-phrase";

const page = ({ text = "", build = () => {} } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_wait-10910", title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off", "myclaude-send-delay-seconds": "5" } },
    html: dom => {
      const parts = dom.composer({ text });
      parts.feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: { left: 0, top: 0, width: 1200, height: 500 } });
      const row = parts.feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" } });
      parts.box = row.add("div", { class: "contents" });
      build(parts.box, dom, parts);
      parts.send = parts.modelRow.add("button", { attrs: { "data-testid": "code-prompt-send" }, rect: { left: 1150, top: 700, width: 24, height: 24 } });
      parts.send.__presses = 0;
      parts.send.addEventListener("pointerdown", () => { parts.send.__presses += 1; parts.editor.__text = ""; });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  caret(loaded);
  let t = Date.now();
  loaded.inner.nazhTick(t);
  const tick = (step = 500) => { t += step; loaded.inner.nazhTick(t); };
  const click = (node, extra = {}) => loaded.dom.document.dispatchEvent({ type: "click", target: node, detail: 1, isTrusted: true, ...extra });
  return { loaded, parts: loaded.parts, tick, click };
};
// Курсор и выделение в поле, как в Chromium (как в nazhimalki-wf98): хвост выделяется назад Selection.modify.
const caret = loaded => {
  const doc = loaded.dom.document;
  const editor = loaded.parts.editor;
  let start = 0;
  let end = 0;
  doc.createRange = () => {
    const range = {
      end: false, setStart() {}, setEnd() {}, selectNodeContents() {},
      collapse(toStart) { range.end = !toStart; },
      getBoundingClientRect: () => ({ left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0 }),
    };
    return range;
  };
  const selection = {
    rangeCount: 1, getRangeAt: () => null, toString: () => editor.__text.slice(start, end), removeAllRanges() {},
    addRange(range) { start = end = range.end ? editor.__text.length : 0; },
    modify(alter, direction) { if (alter === "extend" && direction === "backward") start = Math.max(0, start - 1); },
  };
  loaded.win.getSelection = () => selection;
  doc.getSelection = () => selection;
  const stock = doc.execCommand;
  doc.execCommand = (name, ui, value) => {
    if ((name !== "insertText" && name !== "delete") || doc.__selectedAll) return stock(name, ui, value);
    if (doc.activeElement !== editor) return false;
    const put = name === "insertText" ? String(value) : "";
    editor.__text = editor.__text.slice(0, start) + put + editor.__text.slice(end);
    start = end = start + put.length;
    return true;
  };
};
const field = loaded => loaded.parts.editor.textContent;
const status = loaded => plain(loaded.api.status().waitPhrases);

// Ответ Рика: фраза до раздела, раздел «❗ Ждёт тебя» заголовком, пункты с фразами, следующий заголовок, фраза после.
const answer = (box, dom, parts) => {
  parts.before = box.add("p").add("strong", { text: "«не отсюда»" });
  box.add("h3", { text: "❗ Ждёт тебя" });
  const list = box.add("ul");
  const one = list.add("li");
  dom.leaf(one, "span", "Магнит готов, скажи ");
  parts.magnet = one.add("strong", { text: "«выкладывай магнит»" });
  const two = list.add("li");
  dom.leaf(two, "span", "Остальные три — ");
  parts.rest = two.add("strong", { text: "«давай остальные»." });
  parts.plainBold = two.add("strong", { text: "без ёлочек" });
  parts.link = list.add("li").add("a", { attrs: { href: "https://example.com" } }).add("strong", { text: "«ссылка»" });
  // Живьём 24.10 (окно Рика): жирное предложение со «скажи «…»» и название кнопки после «жми».
  parts.say = list.add("li").add("strong", { text: "Магнит раньше часа — починено, скажи «выкладывай»." });
  const press = list.add("li");
  dom.leaf(press, "span", "Гиннес: в Chrome открыта накладная, жми ");
  parts.button = press.add("strong", { text: "«Подтверждение»" });
  box.add("h3", { text: "Дальше делаю я" });
  parts.after = box.add("ul").add("li").add("strong", { text: "«не моё»" });
};

test("#10910: в разделе «Ждёт тебя» нажимаются только жирные фразы в «ёлочках»; своих кнопок нет", () => {
  const { loaded, parts } = page({ build: answer });
  assert.equal(parts.magnet.getAttribute(MARK), "");
  assert.equal(parts.rest.getAttribute(MARK), "");
  assert.equal(parts.say.getAttribute(MARK), "", "жирное предложение со «скажи «…»» — тоже");
  for (const node of [parts.before, parts.after, parts.plainBold, parts.link, parts.button]) assert.equal(node.hasAttribute(MARK), false);
  assert.equal(parts.magnet.textContent, "«выкладывай магнит»", "текст React не тронут");
  assert.deepEqual(loaded.dom.queryAll("[data-myclaude-nazh-button],[data-myclaude-nazh-box]").length, 0, "ни кнопок, ни окошек");
  const css = loaded.dom.queryAll("style").map(node => node.textContent).join("\n");
  assert.match(css, /\[data-myclaude-wait-phrase\]\{cursor:pointer;/);
  assert.match(css, /\[data-myclaude-wait-phrase\]:hover\{text-decoration-color:currentColor;/);
  assert.match(css, /\[data-myclaude-wait-phrase\]\{[^}]*\}/);
  assert.doesNotMatch(css.match(/\[data-myclaude-wait-phrase\]\{[^}]*\}/)[0], /user-select/, "выделение и копия как были");
  assert.deepEqual(status(loaded), { count: 3, on: 0, clicks: 0 });
  loaded.api.dispose();
  assert.equal(parts.magnet.hasAttribute(MARK), false, "dispose снимает метки");
});

test("#10910: клик — фраза без кавычек в поле с новой строки, повтор снимает, двойной — одно нажатие, не отправляется", () => {
  const { loaded, parts, click, tick } = page({ build: answer });
  click(parts.magnet);
  assert.equal(field(loaded), "выкладывай магнит");
  assert.equal(parts.magnet.getAttribute(MARK), "on", "выбранная отмечена");
  click(parts.rest);
  assert.equal(field(loaded), "выкладывай магнит\nдавай остальные");
  click(parts.rest, { detail: 2 });
  assert.equal(field(loaded), "выкладывай магнит\nдавай остальные", "второй щелчок двойного — мимо");
  click(parts.magnet);
  assert.equal(field(loaded), "давай остальные", "повтор снимает свою строку");
  assert.equal(parts.magnet.getAttribute(MARK), "");
  for (let step = 0; step < 16; step += 1) tick(500);
  assert.equal(parts.send.__presses, 0, "не отправляется");
  assert.equal(field(loaded), "давай остальные");
  assert.deepEqual(status(loaded), { count: 3, on: 1, clicks: 3 }, "двойной щелчок — не нажатие");
  click(parts.say);
  assert.equal(field(loaded), "давай остальные\nвыкладывай", "из предложения — слово в «ёлочках»");
  loaded.api.dispose();
});

test("#10910: свой текст Элвиса в поле не трогается — меняется только хвост из вписанных строк", () => {
  const { loaded, parts, click } = page({ text: "Привет, Рик", build: answer });
  click(parts.magnet);
  assert.equal(field(loaded), "Привет, Рик\nвыкладывай магнит");
  click(parts.rest);
  assert.equal(field(loaded), "Привет, Рик\nвыкладывай магнит\nдавай остальные");
  click(parts.magnet);
  assert.equal(field(loaded), "Привет, Рик\nдавай остальные");
  click(parts.rest);
  assert.equal(field(loaded), "Привет, Рик");
  loaded.api.dispose();
});

test("#10910: раздел абзацем «❗ Ждёт тебя» — до абзаца-подзаголовка; в реплике человека не ловится", () => {
  const { loaded, parts } = page({
    build: (box, dom, own) => {
      box.add("p").add("strong", { text: "❗ Ждёт тебя" });
      const item = box.add("ol").add("li");
      dom.leaf(item, "span", "Скажи ");
      own.other = item.add("strong", { text: "«удали у Лены»" });
      own.para = box.add("p").add("strong", { text: "«и вот это»" });
      box.add("p").add("strong", { text: "Дальше делаю я" });
      own.later = box.add("ul").add("li").add("strong", { text: "«не моё»" });
      const human = own.feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "human" } }).add("div", { class: "epitaxy-user-turn" });
      human.add("p", { text: "❗ Ждёт тебя" });
      own.human = human.add("p").add("strong", { text: "«моя фраза»" });
    },
  });
  assert.equal(parts.other.getAttribute(MARK), "");
  assert.equal(parts.para.getAttribute(MARK), "", "абзац из одной фразы в «ёлочках» — пункт раздела, а не подзаголовок");
  assert.equal(parts.later.hasAttribute(MARK), false, "после подзаголовка — не раздел");
  assert.equal(parts.human.hasAttribute(MARK), false, "реплика человека — мимо");
  loaded.api.dispose();
});
