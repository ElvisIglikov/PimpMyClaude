// WF262 (страница, раздел 12ф² inject.js, файл page/545-user-fold.js): длинное сообщение Элвиса в
// ленте свёрнуто в суть (#9806). Порог — больше 700 знаков или 8 строк; суть — от Пимпа
// (POST 127.0.0.1:47615/summary), Пимп молчит — первые предложения сама страница.
// Разметка сообщения — как в Claude 1.40609 (снимок стенда WF251): [data-cds="UserMessage"] →
// пузырь → коробка обреза (#id, max-height 200) → .cds-user-message-body → [data-testid="user-message"],
// рядом родная «Show more» (aria-controls = id коробки).
import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { loadInject, plain } from "./load.mjs";

const FOLD = "data-myclaude-ufold";
const SRC = "data-myclaude-ufold-src";
const CLAMP = "data-myclaude-ufold-clamp";
const TEXT = "data-myclaude-ufold-text";
const BAR = "data-myclaude-ufold-bar";
const KIND = "data-myclaude-ufold-kind";
const LABEL = "data-myclaude-ufold-label";
const STORE = "myclaude-ufold-v1";

const sha1 = text => createHash("sha1").update(text, "utf8").digest("hex");
const settle = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };

// Диктовка Элвиса (из снимка стенда, сокращена): абзацы — отдельные <p>.
const DICTATION = [
  "Вот этот чувак, который будет инфографику всю эту мне показывать в виде роликов динамичных, как вот, Клауды сейчас делает вот эти модные. Он выводы должен за меня делать. Например, кафе там, кассы низкие, сегодня, вчера, позавчера, и он такой: «блин, точка безубыточности».",
  "Чё, согласен? Если согласен, начинаем работу. И мне просто нужно там сказать ему: «Да, начинай». И он начинает спасать мой бизнес за меня. Понятно, что мне там тоже во многих вещах нужно включаться.",
  "И он должен постоянно. Я ему рассказываю что-то по работе, какие-то, вот я ищу, например, оборудование там или ещё что-то через него, он должен сечь эту тему.",
  "А тебе нужно выручку повышать, поэтому давай-ка ты там вот это по маркетингу там чё-нибудь двигайся. Вот такой, чтоб пинальщик был для предпринимателей.",
];
const DICTATION_TEXT = DICTATION.join("\n");
const LEAD = "Вот этот чувак, который будет инфографику всю эту мне показывать в виде роликов динамичных, как вот, Клауды сейчас делает вот эти модные. Он выводы должен за меня делать.";

let clampSeq = 0;
// Одно сообщение человека в ленте; paragraphs — абзацы (<p>).
const addMessage = (feed, paragraphs) => {
  const row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "human" } });
  const card = row.add("div", { attrs: { "data-cds": "UserMessage" } });
  const bubble = card.add("div", { class: "relative flex" });
  const id = `_r_clamp${clampSeq += 1}_`;
  const clamp = bubble.add("div", { id, class: "overflow-hidden" });
  clamp.style.setProperty("max-height", "200px");
  const body = clamp.add("div", { class: "cds-user-message-body" });
  const message = body.add("div", { attrs: { "data-testid": "user-message" } });
  const column = message.add("div", { class: "flex" });
  for (const text of paragraphs) column.add("p", { text });
  const more = bubble.add("button", { attrs: { type: "button", "aria-controls": id, "aria-expanded": "false" }, text: "Show more" });
  const actions = card.add("div", { attrs: { "data-cds": "MessageActions" } });
  actions.add("button", { attrs: { type: "button", "aria-label": "Copy" } });
  return { row, card, clamp, body, message, more };
};

// Страница с лентой; fetch — подмена ответа Пимпа (нет — fetch отсутствует, как без сети).
const page = ({ messages = [[...DICTATION]], fetch = null, local = {} } = {}) => {
  const observers = [];
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_ufold-262", title: "Rick", storage: { local },
    html: dom => {
      const Observer = dom.window.MutationObserver;
      dom.window.MutationObserver = class extends Observer {
        constructor(callback) { super(callback); observers.push(this); }
      };
      if (fetch) dom.window.fetch = fetch;
      const parts = dom.composer({ text: "" });
      parts.feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } });
      parts.items = messages.map(list => addMessage(parts.feed, list));
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  // Колбэк наблюдателя мутаций раздела 12ф² — тот, что браузер зовёт до отрисовки.
  const mutated = () => {
    for (const observer of observers) if (observer.live && observer.fn === loaded.inner.userFoldObserved) observer.fn([]);
  };
  const click = (target, extra = {}) => loaded.dom.document.dispatchEvent({ type: "click", target, detail: 1, isTrusted: true, ...extra });
  const key = (name, target) => ({ defaultPrevented: !loaded.win.dispatchEvent({ type: "keydown", key: name, target, isTrusted: true, bubbles: true, cancelable: true }) });
  return { loaded, parts: loaded.parts, observers, mutated, click, key };
};
const status = loaded => plain(loaded.api.status().userFold);
const ownOf = item => item.message.nextSibling;

// Подмена Пимпа: ответы по очереди (последний повторяется), запросы копятся в calls.
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

test("12ф²: порог — больше 700 знаков или 8 строк; короткое не трогается", () => {
  const short = ["Коротко: сделай сайт."];
  const eight = Array.from({ length: 8 }, (_, i) => `Строка ${i + 1}.`);
  const nine = Array.from({ length: 9 }, (_, i) => `Строка ${i + 1}.`);
  const exact = ["а".repeat(700)];
  const over = ["а".repeat(701)];
  const { loaded, parts } = page({ messages: [short, eight, nine, exact, over] });
  const folded = parts.items.map(item => item.message.getAttribute(SRC));
  assert.deepEqual(folded, [null, null, "closed", null, "closed"]);
  assert.equal(loaded.dom.queryAll(`[${FOLD}]`).length, 2);
  assert.deepEqual(status(loaded), { count: 2, open: 0, pending: 0 });
  // Счёт строк — по абзацам и <br>, не по знакам.
  assert.equal(loaded.inner.userFoldText(parts.items[2].message).split("\n").length, 9);
});

test("12ф²: свёрнуто сразу — суть под сообщением, исходник спрятан меткой, родной обрез снят", () => {
  const { loaded, parts } = page();
  const item = parts.items[0];
  const own = ownOf(item);
  assert.equal(own?.getAttribute(FOLD), "closed", "свой узел — сразу за сообщением, в той же обёртке");
  assert.equal(own.parentNode, item.body);
  assert.equal(item.message.getAttribute(SRC), "closed");
  const text = own.querySelector(`[${TEXT}]`);
  const bar = own.querySelector(`[${BAR}]`);
  assert.equal(text.textContent, LEAD, "суть — первые два предложения, ≤ 180 знаков");
  assert.ok(LEAD.length <= 180);
  assert.equal(bar.getAttribute(KIND), "начало сообщения");
  assert.equal(bar.getAttribute(LABEL), "Развернуть ▾");
  assert.equal(bar.getAttribute("role"), "button");
  assert.equal(bar.getAttribute("tabindex"), "0");
  assert.equal(bar.getAttribute("aria-expanded"), "false");
  assert.equal(bar.textContent, "", "подписи — из атрибутов: копия и выделение берут только суть");
  // React-узлы на месте, их текст не тронут.
  assert.equal(item.message.textContent, DICTATION.join(""));
  assert.equal(item.clamp.getAttribute(CLAMP), "box");
  assert.equal(item.more.getAttribute(CLAMP), "button");
  // Кнопка действий сообщения — не родной обрез.
  assert.equal(item.card.querySelector('[aria-label="Copy"]').hasAttribute(CLAMP), false);
});

test("12ф²: новое сообщение сворачивается в колбэке наблюдателя — без таймера и кадра (развёрнутого кадра нет)", () => {
  const { loaded, parts, mutated } = page({ messages: [] });
  assert.equal(loaded.dom.queryAll(`[${FOLD}]`).length, 0);
  const rafs = loaded.dom.count("raf");
  const timers = loaded.dom.count("timeout");
  const item = addMessage(parts.feed, DICTATION);
  mutated();
  assert.equal(item.message.getAttribute(SRC), "closed", "свёрнуто в том же колбэке");
  assert.equal(ownOf(item).getAttribute(FOLD), "closed");
  assert.equal(loaded.dom.count("raf"), rafs, "кадр не нужен");
  assert.equal(loaded.dom.count("timeout"), timers, "таймер не нужен");
  // Повторный колбэк (своя вставка будит наблюдателя) ничего не дублирует.
  mutated(); mutated();
  assert.equal(loaded.dom.queryAll(`[${FOLD}]`).length, 1);
  // Строка ушла из ленты (виртуальная лента) — свой узел тоже.
  item.row.remove();
  mutated();
  assert.equal(status(loaded).count, 0);
});

test("12ф²: нажатие по блоку — раскрыто, «Свернуть ▴» — свёрнуто; Enter, пробел, Esc; двойной щелчок — одно нажатие", () => {
  const { loaded, parts, click, key, mutated } = page();
  const item = parts.items[0];
  const own = ownOf(item);
  const text = own.querySelector(`[${TEXT}]`);
  const bar = own.querySelector(`[${BAR}]`);
  click(text);
  assert.equal(item.message.getAttribute(SRC), "open", "весь исходный текст на виду");
  assert.equal(own.getAttribute(FOLD), "open");
  assert.equal(bar.getAttribute(LABEL), "Свернуть ▴");
  assert.equal(bar.hasAttribute(KIND), false, "раскрыто — только кнопка");
  assert.equal(bar.getAttribute("aria-expanded"), "true");
  assert.deepEqual(status(loaded), { count: 1, open: 1, pending: 0 });
  // Нажатие по раскрытому тексту ничего не сворачивает (там выделяют).
  click(item.message);
  assert.equal(item.message.getAttribute(SRC), "open");
  click(bar);
  assert.equal(item.message.getAttribute(SRC), "closed");
  assert.equal(bar.getAttribute(LABEL), "Развернуть ▾");
  assert.equal(key("Enter", bar).defaultPrevented, true);
  assert.equal(item.message.getAttribute(SRC), "open");
  key(" ", bar);
  assert.equal(item.message.getAttribute(SRC), "closed");
  // Esc сворачивает только раскрытое (свёрнутое Esc не раскрывает).
  key("Escape", bar);
  assert.equal(item.message.getAttribute(SRC), "closed");
  key("Enter", bar);
  assert.equal(key("Escape", bar).defaultPrevented, true);
  assert.equal(item.message.getAttribute(SRC), "closed");
  click(text, { detail: 2 });
  assert.equal(item.message.getAttribute(SRC), "closed", "второй щелчок двойного — не нажатие");
  // Enter мимо своего узла — мимо.
  assert.equal(key("Enter", item.message).defaultPrevented, false);
  // Раскрытое помнится по тексту: лента пересоздала строку — снова раскрыто.
  click(bar);
  item.row.remove();
  mutated();
  const again = addMessage(parts.feed, DICTATION);
  mutated();
  assert.equal(again.message.getAttribute(SRC), "open");
});

test("12ф²: выделил суть протяжкой — нажатие не раскрывает (выделение и копия работают)", () => {
  const { loaded, parts, click } = page();
  const item = parts.items[0];
  const text = ownOf(item).querySelector(`[${TEXT}]`);
  loaded.win.getSelection = () => ({ toString: () => "Вот этот чувак" });
  click(text);
  assert.equal(item.message.getAttribute(SRC), "closed");
  // По кнопке — раскрывается и при выделении.
  click(ownOf(item).querySelector(`[${BAR}]`));
  assert.equal(item.message.getAttribute(SRC), "open");
});

test("12ф²: запрос к Пимпу по контракту; суть нейронки заменяет начало и ложится в кэш", async () => {
  const server = pimp([{ status: 200, data: body => ({ hash: body.hash, summary: "Нужен советник-пинальщик для бизнеса.", kind: "ai", at: "2026-10-17T10:00:00Z" }) }]);
  const { loaded, parts } = page({ fetch: server.fetch });
  const item = parts.items[0];
  assert.equal(server.calls.length, 1);
  const call = server.calls[0];
  assert.equal(call.url, "http://127.0.0.1:47615/summary");
  assert.equal(call.options.method, "POST");
  assert.equal(call.options.mode, "cors");
  assert.equal(call.options.credentials, "omit");
  assert.equal(call.options.headers, undefined, "без Content-Type — простой CORS-запрос, без OPTIONS");
  assert.equal(call.body.text, DICTATION_TEXT);
  assert.equal(call.body.hash, sha1(DICTATION_TEXT), "hash — sha1 текста, hex");
  assert.equal(status(loaded).pending, 1);
  await settle();
  const bar = ownOf(item).querySelector(`[${BAR}]`);
  assert.equal(ownOf(item).querySelector(`[${TEXT}]`).textContent, "Нужен советник-пинальщик для бизнеса.");
  assert.equal(bar.getAttribute(KIND), "кратко от Пимпа");
  assert.equal(status(loaded).pending, 0);
  const stored = JSON.parse(loaded.win.localStorage.getItem(STORE));
  assert.equal(stored.items[sha1(DICTATION_TEXT)].s, "Нужен советник-пинальщик для бизнеса.");
});

test("12ф²: кэш — суть из localStorage сразу, Пимпа не спрашиваем", () => {
  const hash = sha1(DICTATION_TEXT);
  const server = pimp([{ status: 500, data: null }]);
  const local = { [STORE]: JSON.stringify({ v: 1, items: { [hash]: { s: "Суть из кэша.", at: 1 } } }) };
  const { parts } = page({ fetch: server.fetch, local });
  const own = ownOf(parts.items[0]);
  assert.equal(own.querySelector(`[${TEXT}]`).textContent, "Суть из кэша.");
  assert.equal(own.querySelector(`[${BAR}]`).getAttribute(KIND), "кратко от Пимпа");
  assert.equal(server.calls.length, 0);
});

test("12ф²: суть «lead» от Пимпа в кэш не ложится (включат нейронку — спросим заново)", async () => {
  const server = pimp([{ status: 200, data: body => ({ hash: body.hash, summary: LEAD, kind: "lead", at: "2026-10-17T10:00:00Z" }) }]);
  const { loaded, parts, mutated } = page({ fetch: server.fetch });
  await settle();
  assert.equal(ownOf(parts.items[0]).querySelector(`[${BAR}]`).getAttribute(KIND), "начало сообщения");
  assert.equal(loaded.win.localStorage.getItem(STORE), null);
  // Строка пересоздана — ответ уже есть, второго запроса нет.
  parts.items[0].row.remove();
  mutated();
  addMessage(parts.feed, DICTATION);
  mutated();
  assert.equal(server.calls.length, 1);
});

test("12ф²: 202 — переспрос через 3 с; дождались — суть на месте", async () => {
  const server = pimp([
    { status: 202, data: body => ({ hash: body.hash, pending: true }) },
    { status: 200, data: body => ({ hash: body.hash, summary: "Суть готова.", kind: "ai", at: "2026-10-17T10:00:03Z" }) },
  ]);
  const { loaded, parts } = page({ fetch: server.fetch });
  await settle();
  assert.equal(server.calls.length, 1);
  assert.equal(status(loaded).pending, 1, "ждём");
  const waits = [...loaded.dom.timers.entries()].filter(([, item]) => item.kind === "timeout" && item.ms === 3000);
  assert.equal(waits.length, 1, "переспрос — через 3000 мс");
  loaded.dom.fire(waits[0][0]);
  await settle();
  assert.equal(server.calls.length, 2);
  assert.equal(ownOf(parts.items[0]).querySelector(`[${TEXT}]`).textContent, "Суть готова.");
  assert.equal(status(loaded).pending, 0);
});

test("12ф²: 202 без конца — не больше 5 переспросов, остаётся начало", async () => {
  const server = pimp([{ status: 202, data: body => ({ hash: body.hash, pending: true }) }]);
  const { loaded, parts } = page({ fetch: server.fetch });
  for (let round = 0; round < 8; round += 1) {
    await settle();
    const wait = [...loaded.dom.timers.entries()].find(([, item]) => item.kind === "timeout" && item.ms === 3000);
    if (!wait) break;
    loaded.dom.timers.delete(wait[0]);
    wait[1].fn();
  }
  await settle();
  assert.equal(server.calls.length, 6, "первый запрос и 5 переспросов");
  assert.equal(status(loaded).pending, 0);
  assert.equal(ownOf(parts.items[0]).querySelector(`[${TEXT}]`).textContent, LEAD);
});

test("12ф²: Пимп молчит или нет fetch — первые предложения сама страница", async () => {
  const server = pimp(["down"]);
  const down = page({ fetch: server.fetch });
  await settle();
  assert.equal(server.calls.length, 1);
  assert.equal(ownOf(down.parts.items[0]).querySelector(`[${TEXT}]`).textContent, LEAD);
  assert.equal(status(down.loaded).pending, 0);
  const none = page();
  assert.equal(ownOf(none.parts.items[0]).querySelector(`[${TEXT}]`).textContent, LEAD);
  // Чужой hash в ответе — мимо.
  const wrong = pimp([{ status: 200, data: { hash: "0".repeat(40), summary: "Чужое.", kind: "ai" } }]);
  const other = page({ fetch: wrong.fetch });
  await settle();
  assert.equal(ownOf(other.parts.items[0]).querySelector(`[${TEXT}]`).textContent, LEAD);
});

test("12ф²: начало — по границе предложения; длинное первое — по слову с «…»; sha1 как у node", () => {
  const { loaded } = page({ messages: [] });
  const { userFoldLead: lead, userFoldSha1: hash } = loaded.inner;
  assert.equal(lead("Первое. Второе! Третье?"), "Первое. Второе!");
  assert.equal(lead("Сказал: «Готово.» Дальше идём."), "Сказал: «Готово.» Дальше идём.");
  const first = `${"слово ".repeat(27)}конец.`;
  const second = "Второе предложение тут.";
  assert.equal(lead(`${first} ${second}`), first, "второе не влезает в 180 — только первое");
  const long = lead(`${"длинноеслово ".repeat(30)}.`);
  assert.ok(long.length <= 180, long);
  assert.ok(long.endsWith("длинноеслово…"), "обрез — по целому слову");
  for (const text of ["", "abc", "Привет, мир 👾", "х".repeat(20000), DICTATION_TEXT]) assert.equal(hash(text), sha1(text));
});

test("12ф²: снятие — свои узлы и метки уходят; повторная установка не двоит", () => {
  const { loaded, parts } = page();
  const item = parts.items[0];
  assert.equal(loaded.reload().error, null);
  assert.equal(loaded.dom.queryAll(`[${FOLD}]`).length, 1, "после повторной установки — один свой узел");
  assert.equal(item.message.getAttribute(SRC), "closed");
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`[${FOLD}]`).length, 0);
  assert.equal(item.message.hasAttribute(SRC), false);
  assert.equal(item.clamp.hasAttribute(CLAMP), false);
  assert.equal(item.more.hasAttribute(CLAMP), false);
});
