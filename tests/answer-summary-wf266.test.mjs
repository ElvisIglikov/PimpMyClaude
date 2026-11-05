// #9810 (страница, раздел 12ф³, файл page/547-answer-summary.js): «Развернуть ответ» — в два шага.
// Слово Элвиса 11.10: «Я нажимаю развернуть ответ. И мне показывается короткая сводка. И там есть внизу
// подробнее. И потом уже показывается твой вот этот ответ полный». Свёрнутый длинный ответ (12ф)
// разворачивается сначала в сводку — свой узел под кнопкой, «Подробнее» под ней — весь ответ;
// «Свернуть ответ» — обратно. Сводка — от Пимпа (POST /summary, контракт #9806), пока её нет —
// первые предложения спрятанного текста.
import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { loadInject, plain } from "./load.mjs";

const WHOLE = "data-myclaude-fold-whole";
const LABEL = "data-myclaude-fold-label";
const LONG = "data-myclaude-fold-long";
const SUM = "data-myclaude-asum";
const TEXT = "data-myclaude-asum-text";
const BAR = "data-myclaude-asum-bar";
const KIND = "data-myclaude-asum-kind";
const SUM_LABEL = "data-myclaude-asum-label";
const STORE = "myclaude-ufold-v1";

const sha1 = text => createHash("sha1").update(text, "utf8").digest("hex");
const settle = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };

// Ответ Рика выше двух экранов: первый абзац остаётся на виду, остальное прячет кнопка.
const HIDDEN = [
  "Сайт выложен, ошибка оплаты исправлена. Проверил заказ с телефона — дошёл до кухни.",
  "Дальше — меню на завтра.",
];
const HIDDEN_TEXT = `${HIDDEN[0]}\n${HIDDEN[1]}\nпункт один\nпункт два`;
const LEAD = HIDDEN[0];
const longAnswer = (box, dom) => {
  const first = box.add("p", { text: "Коротко: всё готово." });
  const second = box.add("p", { text: HIDDEN[0] });
  const third = box.add("p", { text: HIDDEN[1] });
  const list = box.add("ul");
  list.add("li", { text: "пункт один" });
  list.add("li", { text: "пункт два" });
  return { first, second, third, list };
};

const pimp = replies => {
  const calls = [];
  const fetch = (url, options) => {
    calls.push({ url, options, body: JSON.parse(options.body) });
    const reply = replies[Math.min(calls.length - 1, replies.length - 1)];
    if (reply === "down") return Promise.reject(new TypeError("Failed to fetch"));
    const data = typeof reply.data === "function" ? reply.data(calls.at(-1).body) : reply.data;
    return Promise.resolve({ ok: reply.status < 300, status: reply.status, json: () => Promise.resolve(data) });
  };
  return { fetch, calls };
};

const page = ({ build = longAnswer, fetch = null, local = {}, streaming = false } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_asum-9810", title: "Rick", storage: { local },
    html: dom => {
      if (fetch) dom.window.fetch = fetch;
      const parts = dom.composer({ text: "" });
      const feed = dom.document.body.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript" },
        rect: { left: 0, top: 0, width: 1200, height: 500 },
      });
      const row = feed.add("div", {
        attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text", ...(streaming ? { "data-is-streaming": "true" } : {}) },
        rect: { left: 0, top: 0, width: 800, height: 1700 },
      });
      parts.row = row;
      parts.box = row.add("div", { class: "contents" });
      parts.nodes = build(parts.box, dom) ?? {};
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.inner.foldTick();
  const click = (node, extra = {}) => loaded.dom.document.dispatchEvent({ type: "click", target: node, detail: 1, isTrusted: true, ...extra });
  const key = (name, target) => ({ defaultPrevented: !loaded.win.dispatchEvent({ type: "keydown", key: name, target, isTrusted: true, bubbles: true, cancelable: true }) });
  const whole = () => loaded.dom.queryAll(`[${WHOLE}]`)[0];
  const sum = () => loaded.dom.queryAll(`[${SUM}]`)[0] ?? null;
  return { loaded, n: loaded.parts.nodes, click, key, whole, sum, tick: () => loaded.inner.foldTick() };
};
const folds = loaded => plain(loaded.api.status().folds);

test("12ф³: свёрнут → «Развернуть» — сводка под кнопкой и «Подробнее»; «Подробнее» — весь ответ; «Свернуть» — обратно", async () => {
  const server = pimp([{ status: 200, data: body => ({ hash: body.hash, summary: "Сайт работает, оплата чинена.", kind: "ai", at: "2026-10-17T10:00:00Z" }) }]);
  const { loaded, n, click, whole, sum } = page({ fetch: server.fetch });
  assert.equal(server.calls.length, 0, "развёрнутый ответ Пимпа не спрашивает");
  click(whole());
  assert.equal(whole().getAttribute(LABEL), "▸ Развернуть ответ");
  assert.equal(sum(), null, "свёрнут — сводки на виду нет");
  // Свернул — Claude не спрашиваем: подписка тратится только на ответы, которые раскрыли (гейт WF266).
  assert.equal(server.calls.length, 0, "свёрнутый ответ Пимпа не спрашивает");
  loaded.inner.foldTick();
  assert.equal(server.calls.length, 0);
  // Развернул — спросили: текст — то, что прячет кнопка, hash — sha1 его; пока суть пишется — начало.
  click(whole());
  assert.equal(server.calls.length, 1);
  assert.equal(server.calls[0].url, "http://127.0.0.1:47615/summary");
  assert.equal(server.calls[0].options.method, "POST");
  assert.equal(server.calls[0].options.headers, undefined, "простой CORS-запрос");
  assert.equal(server.calls[0].body.text, HIDDEN_TEXT);
  assert.equal(server.calls[0].body.hash, sha1(HIDDEN_TEXT));
  await settle();
  loaded.inner.foldTick();
  // Суть пришла — сводка, весь ответ ещё спрятан.
  const own = sum();
  assert.ok(own);
  assert.equal(whole().nextElementSibling, own, "сводка — сразу под кнопкой");
  assert.equal(whole().getAttribute(WHOLE), "open");
  assert.equal(whole().getAttribute(LABEL), "▾ Свернуть ответ");
  assert.equal(whole().getAttribute("aria-expanded"), "true");
  assert.equal(own.querySelector(`[${TEXT}]`).textContent, "Сайт работает, оплата чинена.");
  const bar = own.querySelector(`[${BAR}]`);
  assert.equal(bar.getAttribute(SUM_LABEL), "Подробнее ▾");
  assert.equal(bar.getAttribute(KIND), "кратко от Пимпа");
  assert.equal(bar.getAttribute("role"), "button");
  assert.equal(bar.getAttribute("tabindex"), "0");
  assert.equal(own.hasAttribute(LONG), false, "сводка — не спрятанное");
  for (const node of [n.second, n.third, n.list]) assert.equal(node.getAttribute(LONG), "closed");
  assert.equal(n.first.hasAttribute(LONG), false);
  assert.equal(folds(loaded).brief, 1);
  // Проход ещё раз — ничего не меняется, второго запроса нет.
  loaded.inner.foldTick();
  assert.equal(sum(), own);
  assert.equal(server.calls.length, 1);
  // «Подробнее» — весь ответ, сводки нет.
  click(bar);
  assert.equal(sum(), null);
  for (const node of [n.second, n.third, n.list]) assert.equal(node.hasAttribute(LONG), false);
  assert.equal(whole().getAttribute(LABEL), "▾ Свернуть ответ");
  assert.equal(folds(loaded).brief, 0);
  // «Свернуть ответ» — свёрнут; «Развернуть» — снова сводка (из кэша, без запроса).
  click(whole());
  assert.equal(whole().getAttribute(WHOLE), "closed");
  click(whole());
  assert.equal(sum().querySelector(`[${TEXT}]`).textContent, "Сайт работает, оплата чинена.");
  assert.equal(server.calls.length, 1);
  // «Свернуть ответ» над сводкой — обратно свёрнут, сводка ушла.
  click(whole());
  assert.equal(whole().getAttribute(WHOLE), "closed");
  assert.equal(sum(), null);
  for (const node of [n.second, n.third, n.list]) assert.equal(node.getAttribute(LONG), "closed");
  const stored = JSON.parse(loaded.win.localStorage.getItem(STORE));
  assert.equal(stored.items[sha1(HIDDEN_TEXT)].s, "Сайт работает, оплата чинена.", "суть нейронки — в общем кэше 12ф²");
});

test("12ф³: Пимпа нет — сводка из первых предложений, метка «начало»; суть пришла позже — встаёт на место", async () => {
  const none = page();
  none.click(none.whole());
  none.click(none.whole());
  assert.equal(none.sum().querySelector(`[${TEXT}]`).textContent, LEAD);
  assert.equal(none.sum().querySelector(`[${BAR}]`).getAttribute(KIND), "начало ответа");
  const server = pimp([
    { status: 202, data: body => ({ hash: body.hash, pending: true }) },
    { status: 200, data: body => ({ hash: body.hash, summary: "Суть готова.", kind: "ai", at: "2026-10-17T10:00:03Z" }) },
  ]);
  const { loaded, click, whole, sum } = page({ fetch: server.fetch });
  click(whole());
  click(whole());
  await settle();
  assert.equal(sum().querySelector(`[${TEXT}]`).textContent, LEAD, "202 — пока начало");
  const wait = [...loaded.dom.timers.entries()].find(([, item]) => item.kind === "timeout" && item.ms === 3000);
  assert.ok(wait, "переспрос через 3 с");
  loaded.dom.fire(wait[0]);
  await settle();
  assert.equal(server.calls.length, 2);
  assert.equal(sum().querySelector(`[${TEXT}]`).textContent, "Суть готова.");
  assert.equal(sum().querySelector(`[${BAR}]`).getAttribute(KIND), "кратко от Пимпа");
});

test("12ф³: нажатие на сводку — весь ответ; с выделением — нет; клавиши на «Подробнее»: пробел — весь, Esc — свёрнут", () => {
  const { loaded, n, click, key, whole, sum } = page();
  click(whole());
  click(whole());
  loaded.win.getSelection = () => ({ toString: () => "Сайт выложен" });
  click(sum().querySelector(`[${TEXT}]`));
  assert.ok(sum(), "выделил протяжкой — сводка на месте");
  loaded.win.getSelection = () => ({ toString: () => "" });
  click(sum().querySelector(`[${TEXT}]`));
  assert.equal(sum(), null, "нажал на сводку — весь ответ");
  assert.equal(n.second.hasAttribute(LONG), false);
  click(whole());
  click(whole());
  assert.equal(key("Escape", sum().querySelector(`[${BAR}]`)).defaultPrevented, true);
  assert.equal(whole().getAttribute(WHOLE), "closed", "Esc на «Подробнее» — свёрнут");
  assert.equal(loaded.dom.document.activeElement, whole(), "фокус — на кнопку ответа");
  click(whole());
  key(" ", sum().querySelector(`[${BAR}]`));
  assert.equal(sum(), null);
  assert.equal(n.second.hasAttribute(LONG), false, "пробел на «Подробнее» — весь ответ");
  assert.equal(loaded.dom.document.activeElement, whole());
});

test("12ф³: ответ ещё пишется — Пимпа не спрашиваем; спрятанного текста нет — «Развернуть» сразу весь ответ", () => {
  const server = pimp([{ status: 500, data: null }]);
  const live = page({ fetch: server.fetch, streaming: true });
  live.click(live.whole());
  assert.equal(server.calls.length, 0, "пишется — текст ещё растёт");
  live.loaded.parts.row.removeAttribute("data-is-streaming");
  live.tick();
  assert.equal(server.calls.length, 0, "дописан, но свёрнут — не спрашиваем");
  live.click(live.whole());
  assert.equal(server.calls.length, 1, "дописан и развёрнут — спросили");
  const bare = page({
    build: box => ({ first: box.add("p", { text: "Только картинка ниже." }), img: box.add("div", { text: "" }) }),
  });
  bare.click(bare.whole());
  bare.click(bare.whole());
  assert.equal(bare.sum(), null);
  assert.equal(bare.whole().getAttribute(WHOLE), "open");
  assert.equal(bare.n.img.hasAttribute(LONG), false);
});

test("12ф³: dispose снимает сводку", () => {
  const { loaded, click, whole, sum } = page();
  click(whole());
  click(whole());
  assert.ok(sum());
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`[${SUM}]`).length, 0);
});
