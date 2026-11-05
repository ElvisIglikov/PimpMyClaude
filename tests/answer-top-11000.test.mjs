// #11000 (страница, раздел 12ф³, файл page/547-answer-summary.js): у свёрнутого ответа «Ждёт тебя» — самым верхом.
// Слово Элвиса 28.10: «все места, которые от меня требовались, были сразу сверху показаны… чтоб я ни один процесс
// не тормозил». Раздел «Ждёт тебя» («сделай») прятался под «Развернуть ответ»; теперь его копия стоит над первым
// абзацем ответа, пока ответ свёрнут или на шаге сводки; развёрнут целиком — копии нет.
//
// Что проверяется:
//   1) answerWaitsOf: заголовок и пункты; пункт-свёртка — только заголовок; до следующего заголовка; «сделай»;
//      нет раздела — пусто;
//   2) свёрнут — копия над первым абзацем, не спрятана; шаг сводки — копия на месте, сводка под кнопкой;
//      весь ответ — копии нет; снова свёрнут — вернулась (один узел);
//   3) нажатие на копию — весь ответ;
//   4) «Ждёт тебя» уже на виду (до кнопки) или его нет — копии нет; после dispose — узлов нет.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const WHOLE = "data-myclaude-fold-whole";
const LONG = "data-myclaude-fold-long";
const SUM = "data-myclaude-asum";
const WAITS = "data-myclaude-asum-waits";
const WAITS_HEAD = "data-myclaude-asum-waits-head";

// Ответ по форме ELVIS.md: первый абзац, длинный рассказ, «❗ Ждёт тебя 2» пунктами-свёртками, итог.
const rickAnswer = (box) => {
  const first = box.add("p", { text: "Дописываю ответ про сайт." });
  box.add("p", { text: "Сайт выложен, оплата чинена." });
  box.add("p", { text: "Дальше — меню на завтра." });
  const head = box.add("h2", { text: "❗ Ждёт тебя 2 (🔴 1)" });
  box.add("p", { text: "<details>" });
  box.add("p", { text: "<summary><b>1 · 🆕 Оплата — скажи «выкладывай»</b></summary>" });
  box.add("p", { text: "Внутри свёртки — подробности, не копируются." });
  box.add("p", { text: "</details>" });
  box.add("p", { text: "<details><summary>2 · Меню — нужно фото</summary>" });
  box.add("p", { text: "тело" });
  box.add("p", { text: "</details>" });
  const tail = box.add("ul");
  tail.add("li", { text: "Строка списком" });
  box.add("p").add("strong", { text: "✅ Готово два дела" });
  box.add("p", { text: "После итога — не в копии." });
  return { first, head };
};

const page = ({ build = rickAnswer } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_asum-11000", title: "Rick", storage: { local: {} },
    html: dom => {
      dom.window.fetch = () => Promise.reject(new TypeError("Failed to fetch"));
      const parts = dom.composer({ text: "" });
      const feed = dom.document.body.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript" },
        rect: { left: 0, top: 0, width: 1200, height: 500 },
      });
      const row = feed.add("div", {
        attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" },
        rect: { left: 0, top: 0, width: 800, height: 1700 },
      });
      parts.box = row.add("div", { class: "contents" });
      parts.nodes = build(parts.box) ?? {};
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.inner.foldTick();
  const click = node => loaded.dom.document.dispatchEvent({ type: "click", target: node, detail: 1, isTrusted: true });
  const whole = () => loaded.dom.queryAll(`[${WHOLE}]`)[0];
  const waits = () => loaded.dom.queryAll(`[${WAITS}]`);
  const lines = () => [...(waits()[0]?.children ?? [])].map(row => row.textContent);
  return { loaded, n: loaded.parts.nodes, click, whole, waits, lines, tick: () => loaded.inner.foldTick() };
};

test("#11000: answerWaitsOf — заголовок, заголовки пунктов-свёрток, список; до итога; «сделай»; нет — пусто", () => {
  const { loaded, n } = page();
  const nodes = [];
  for (let node = n.first.nextElementSibling; node; node = node.nextElementSibling) {
    if (!node.hasAttribute(WHOLE) && !node.hasAttribute(SUM)) nodes.push(node);
  }
  assert.deepEqual(plain(loaded.inner.answerWaitsOf(nodes)), [
    "❗ Ждёт тебя 2 (🔴 1)", "1 · 🆕 Оплата — скажи «выкладывай»", "2 · Меню — нужно фото", "Строка списком",
  ]);
  assert.deepEqual(plain(loaded.inner.answerWaitsOf(nodes.slice(0, 2))), [], "раздела нет — пусто");
  loaded.api.dispose();
  const other = page({
    build: box => {
      const first = box.add("p", { text: "Начало." });
      box.add("p", { text: "Рассказ." });
      box.add("p").add("strong", { text: "👾 Элвис, сделай" });
      box.add("p", { text: "Открой ссылку оплаты." });
      box.add("h3", { text: "Дальше без тебя" });
      box.add("p", { text: "не в копии" });
      return { first };
    },
  });
  const rest = [];
  for (let node = other.n.first.nextElementSibling; node; node = node.nextElementSibling) if (!node.hasAttribute(WHOLE)) rest.push(node);
  assert.deepEqual(plain(other.loaded.inner.answerWaitsOf(rest)), ["👾 Элвис, сделай", "Открой ссылку оплаты."]);
  other.loaded.api.dispose();
});

test("#11000: свёрнут — «Ждёт тебя» над первым абзацем; сводка — на месте; весь ответ — копии нет", () => {
  const { loaded, n, click, whole, waits, lines, tick } = page();
  assert.equal(waits().length, 0, "развёрнутый ответ — копии нет");
  click(whole());
  assert.equal(whole().getAttribute(WHOLE), "closed");
  assert.equal(waits().length, 1);
  const own = waits()[0];
  assert.equal(own.nextElementSibling, n.first, "над первым абзацем");
  assert.equal(n.first.nextElementSibling, whole(), "кнопка — как была, под первым абзацем");
  assert.equal(own.hasAttribute(LONG), false, "копия не спрятана");
  assert.equal(n.head.getAttribute(LONG), "closed", "сам раздел — под кнопкой");
  assert.deepEqual(lines(), ["❗ Ждёт тебя 2 (🔴 1)", "1 · 🆕 Оплата — скажи «выкладывай»", "2 · Меню — нужно фото", "Строка списком"]);
  assert.ok(own.firstElementChild.hasAttribute(WAITS_HEAD));
  tick();
  assert.equal(waits().length, 1);
  assert.equal(waits()[0], own, "проход ещё раз — тот же узел");
  // Шаг сводки: копия на месте, сводка — под кнопкой.
  click(whole());
  assert.equal(whole().getAttribute(WHOLE), "open");
  assert.equal(whole().nextElementSibling?.hasAttribute(SUM), true);
  assert.equal(waits()[0], own);
  // «Подробнее» — весь ответ: копии нет.
  click(whole().nextElementSibling.lastChild);
  assert.equal(waits().length, 0);
  assert.equal(n.head.hasAttribute(LONG), false);
  // Снова свёрнут — копия вернулась, одна.
  click(whole());
  assert.equal(waits().length, 1);
  assert.equal(waits()[0].nextElementSibling, n.first);
  loaded.api.dispose();
  assert.equal(waits().length, 0, "dispose — узлов нет");
});

test("#11000: нажатие на копию — весь ответ", () => {
  const { loaded, click, whole, waits } = page();
  click(whole());
  assert.equal(waits().length, 1);
  click(waits()[0].lastChild);
  assert.equal(whole().getAttribute(WHOLE), "open");
  assert.equal(waits().length, 0);
  assert.equal(loaded.dom.queryAll(`[${SUM}]`).length, 0, "сразу весь ответ, не сводка");
  loaded.api.dispose();
});

test("#11000: «Ждёт тебя» уже на виду или его нет — копии нет", () => {
  for (const build of [
    box => {
      const first = box.add("p", { text: "❗ Ждёт тебя 1" });
      box.add("p", { text: "Рассказ." });
      box.add("p", { text: "Ещё рассказ." });
      return { first };
    },
    box => {
      const first = box.add("p", { text: "Начало." });
      box.add("p", { text: "Рассказ без просьб." });
      box.add("p", { text: "Ещё." });
      return { first };
    },
  ]) {
    const { loaded, click, whole, waits } = page({ build });
    click(whole());
    assert.equal(whole().getAttribute(WHOLE), "closed");
    assert.equal(waits().length, 0);
    loaded.api.dispose();
  }
});
