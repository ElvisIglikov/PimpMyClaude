// #11399 (page/678-user-fold-md.js, раздел 13в¹): верх стартового сообщения renew (#10904) — последний ответ
// прежнего Рика — рисуется вёрсткой ответа (Markdown шва 13в): заголовок, жирный, список и свёртка <details>
// вместо сырых тегов. Тот же ответ в шве (стартовое сообщение прошлого чата) — так же. Текст выдуман, форма — Рика.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const FOLD = "data-myclaude-ufold";
const MD = "data-myclaude-ufold-md";
const TITLE = "Последний ответ Рика тебе (из прежнего чата, 15:06):";
const ANSWER = [
  "# Страницу заказа собрал — проверь кнопку",
  "",
  "<details>",
  "<summary><b>💬 ОТВЕТЫ НА ТВОИ ВОПРОСЫ — 2</b></summary>",
  "",
  "1. **Цвет** — оставил синий.",
  "2. **Шрифт** — крупнее на шаг.",
  "",
  "</details>",
  "",
  "Дальше: сборка к вечеру.",
].join("\n");
const SERVICE = Array.from({ length: 10 }, (_, at) => `Служебное для нового Рика, пункт ${at + 1}: прочитай паспорт и журнал прежнего чата.`).join("\n");
const RENEW = `${TITLE}\n\n${ANSWER}\n\n———\n${SERVICE}`;

// Сообщение — один <p> с переводами строк (у Claude — <br>; userFoldText читает их одинаково).
const addMessage = (feed, text) => {
  const card = feed.add("div", { attrs: { "data-testid": "transcript-row" } }).add("div", { attrs: { "data-cds": "UserMessage" } });
  const body = card.add("div", { class: "relative flex" }).add("div", { class: "cds-user-message-body" });
  const message = body.add("div", { attrs: { "data-testid": "user-message" } });
  message.add("div", { class: "flex" }).add("p", { text });
  return message;
};
const page = texts => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_md-11399", title: "Rick",
    html: dom => {
      dom.window.fetch = () => Promise.reject(new TypeError("Failed to fetch"));
      const parts = dom.composer({ text: "" });
      parts.feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } });
      parts.messages = texts.map(text => addMessage(parts.feed, text));
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return loaded;
};
const checkAnswer = (box, where) => {
  assert.equal(box.querySelector(".myclaude-seam-h1")?.textContent, "Страницу заказа собрал — проверь кнопку", `${where}: заголовок`);
  const fold = box.querySelector("details.myclaude-seam-fold");
  assert.ok(fold, `${where}: свёртка`);
  assert.equal(fold.hasAttribute("open"), false, `${where}: закрыта, как у ответа`);
  assert.equal(fold.querySelector("summary strong")?.textContent, "💬 ОТВЕТЫ НА ТВОИ ВОПРОСЫ — 2", `${where}: подпись свёртки жирным`);
  assert.deepEqual([...fold.querySelectorAll("li strong")].map(node => node.textContent), ["Цвет", "Шрифт"], `${where}: список внутри свёртки`);
  assert.doesNotMatch(box.textContent, /<\/?(details|summary|b)>|\*\*|^#/m, `${where}: сырых тегов и звёздочек нет`);
};

test("#11399: верх стартового сообщения — вёрсткой ответа: заголовок, свёртка, список; стили общим охватом", () => {
  const loaded = page([RENEW]);
  const [message] = loaded.parts.messages;
  const head = message.nextSibling;
  assert.equal(head.getAttribute(FOLD), "head");
  assert.equal(head.hasAttribute(MD), true);
  assert.equal(head.firstChild.className.split(" ").includes("prose"), true, "внутри — .prose, как у ответа");
  assert.equal(head.querySelector(".prose > p")?.textContent, TITLE, "первая строка — подпись «Последний ответ…»");
  checkAnswer(head, "верх");
  assert.equal([...head.querySelectorAll(".prose > p")].at(-1)?.textContent, "Дальше: сборка к вечеру.");
  assert.equal(head.nextSibling.getAttribute(FOLD), "closed", "низ — служебное — свёрнут, как раньше");
  const css = loaded.dom.queryAll("style").map(node => node.textContent).join("\n");
  assert.ok(css.includes(`[${FOLD}="head"][${MD}]{white-space:normal}`), "верх — без pre-wrap");
  assert.ok(css.includes(`:is(#myclaude-seam,[${FOLD}="head"]) details.myclaude-seam-fold>summary{`), "свёртки — видом шва");
  assert.ok(css.includes(`:is(#myclaude-seam,[${FOLD}="head"]) .prose :is(p,li,blockquote,.myclaude-seam-p){line-height:1.45`), "типографика ответа");
  assert.deepEqual(plain(loaded.api.status().userFoldMd), { on: true, painted: 1, error: null });
  loaded.api.dispose();
});

test("#11399: сообщение, пришедшее после установки, — тоже вёрсткой (крючок 545 → 678)", () => {
  const loaded = page(["Короткое."]);
  const message = addMessage(loaded.parts.feed, RENEW);
  loaded.inner.userFoldObserved();
  const head = message.nextSibling;
  assert.equal(head?.getAttribute(FOLD), "head");
  assert.equal(head.hasAttribute(MD), true);
  checkAnswer(head, "новое сообщение");
  assert.equal(plain(loaded.api.status().userFoldMd).painted, 1);
  loaded.api.dispose();
});

test("#11399: шов — стартовое сообщение прошлого чата: под заголовком ответ вёрсткой, служебное — текстом", () => {
  const loaded = page([]);
  const { seamTurnNode, seamLastAnswer } = loaded.inner;
  const look = { prose: "prose", font: "sans", bubble: "bubble", vars: {} };
  const box = seamTurnNode({ q: { text: RENEW, images: 0 }, aps: [], at: Date.parse("2026-10-31T10:00:00Z") }, look);
  const fold = box.querySelector(".myclaude-seam-qfold");
  assert.equal(fold.firstChild.textContent, TITLE, "свёрнуто под подписью «Последний ответ…»");
  checkAnswer(fold.querySelector(".prose"), "шов");
  assert.equal(fold.querySelector(".myclaude-seam-qfull").textContent, SERVICE, "служебное — как было, текстом");
  // Не renew — как раньше: суть и весь текст.
  const other = `Обычное длинное сообщение.\n${SERVICE}`;
  const plainBox = seamTurnNode({ q: { text: other, images: 0 }, aps: [], at: 0 }, look);
  assert.equal(plainBox.querySelector(".myclaude-seam-qfold > .prose"), null);
  assert.equal(plainBox.querySelector(".myclaude-seam-qfull").textContent, other);
  assert.equal(seamLastAnswer(`${TITLE}\nбез черты`), null, "нет строки «———» — не renew");
  loaded.api.dispose();
});
