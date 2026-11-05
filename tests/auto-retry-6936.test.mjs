// Повтор при ошибке сервера (#6936, раздел 12е², К-AR). Ход Claude упал с ошибкой сети или сервера — страница
// сама жмёт «Try again» раз в N минут, первый раз через N минут, не дольше часа; мешает человек — ждёт.
// Время — настенные часы страницы (Date.now в контексте окна): час общий для окон и переживает перезагрузку.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const ON = "myclaude.autoRetry";
const EVERY = "myclaude.autoRetryEvery";
const STORE = "myclaude-auto-retry-v1";
const INPUT = "myclaude-last-input";
const LINE = "[data-myclaude-auto-retry]";
const CANCEL = "[data-myclaude-auto-retry-cancel]";
const T0 = Date.UTC(2026, 9, 19, 2, 0, 0);
const MIN = 60 * 1000;
const NETWORK = "API Error: Connection error. Can't reach the API server";
const box = (top, height = 40) => ({ left: 10, top, width: 600, height });

// Лента: ход человека (data-index 0), строка ответа с ошибкой и кнопкой повтора (data-index 1); поле ввода ниже.
const page = ({ text = NETWORK, on = "true", every = "5", local = {}, draft = "", label = "Try again" } = {}) => {
  const loaded = loadInject({
    storage: { local: { ...(on == null ? {} : { [ON]: on }), ...(every == null ? {} : { [EVERY]: every }), ...local } },
    html: dom => {
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: box(0, 600) });
      const human = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "human", "data-index": "0" },
        rect: box(10), text: "Сделай отчёт" });
      const { row, wrap, retry } = errorRow(dom, feed, 1, text, label);
      const parts = dom.composer({ text: draft });
      return { ...parts, feed, human, row, wrap, retry };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.run(`globalThis.__now = ${T0}; Date.now = () => globalThis.__now;`);
  loaded.at = ms => { loaded.run(`globalThis.__now = ${ms}`); loaded.inner.autoRetryTick(ms); };
  loaded.ar = () => plain(loaded.api.status().autoRetry);
  loaded.line = () => loaded.dom.query(LINE);
  loaded.text = () => loaded.line()?.getAttribute("data-myclaude-auto-retry-text") ?? null;
  loaded.store = () => JSON.parse(loaded.win.localStorage.getItem(STORE) ?? "{}");
  return loaded;
};
function errorRow(dom, feed, index, text, label = "Try again") {
  const row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant", "data-index": String(index) },
    rect: box(60 * index) });
  const wrap = row.add("div", { rect: box(60 * index) });
  wrap.add("div", { text, rect: box(60 * index, 20) });
  const retry = wrap.add("button", { text: label, rect: { left: 10, top: 60 * index + 24, width: 80, height: 24 } });
  retry.presses = 0;
  retry.addEventListener("click", () => { retry.presses += 1; });
  return { row, wrap, retry };
}

test("сетевая ошибка, 5 мин: не раньше интервала, ровно в срок — нажатие и запись в status()", () => {
  const p = page();
  p.at(T0);
  assert.equal(p.ar().state, "count");
  assert.equal(p.ar().kind, "network");
  assert.equal(p.text(), "PMP повторит через 5 мин · попытка 1 из 12 · ");
  assert.ok(p.line().querySelector(CANCEL), "у строки есть «Отменить»");
  assert.equal(p.parts.wrap.nextElementSibling, p.line(), "строка — сразу под блоком ошибки, внутри строки ленты");
  assert.equal(p.parts.row.textContent.includes("PMP"), false, "текст строки не попадает в textContent ленты");
  p.at(T0 + 4 * MIN + 59000);
  assert.equal(p.parts.retry.presses, 0);
  assert.equal(p.text(), "PMP повторит меньше чем через минуту · попытка 1 из 12 · ");
  p.at(T0 + 5 * MIN);
  assert.equal(p.parts.retry.presses, 1);
  const ar = p.ar();
  assert.equal(ar.state, "pressed");
  assert.equal(ar.tries, 1);
  assert.equal(ar.last, new Date(T0 + 5 * MIN).toISOString());
  assert.equal(ar.presses, 1);
  // Кнопка осталась на месте 5 с — нажатие не взяло; следующая попытка — через интервал от прошлой.
  p.at(T0 + 5 * MIN + 6000);
  assert.equal(p.ar().outcome, "press-failed");
  assert.equal(p.ar().next, new Date(T0 + 10 * MIN).toISOString());
  assert.equal(p.text(), "PMP повторит через 5 мин · попытка 2 из 12 · ");
  p.api.dispose();
});

test("дальше по интервалу, через час — стоп с надписью; интервал 2 и 10 — свои пределы", () => {
  const p = page();
  p.at(T0);
  for (let k = 1; k <= 12; k += 1) {
    p.at(T0 + k * 5 * MIN - 1000);
    assert.equal(p.parts.retry.presses, k - 1, `до попытки ${k}`);
    p.at(T0 + k * 5 * MIN);
    assert.equal(p.parts.retry.presses, k, `попытка ${k}`);
  }
  p.at(T0 + 61 * MIN);
  assert.equal(p.text(), "PMP перестал повторять: прошёл час");
  assert.equal(p.line().querySelector(CANCEL), null, "после часа отменять нечего");
  p.at(T0 + 65 * MIN);
  p.at(T0 + 90 * MIN);
  assert.equal(p.parts.retry.presses, 12);
  assert.equal(p.ar().state, "stopped");
  assert.equal(p.ar().stoppedBy, "hour");
  assert.equal(p.store().local_test.stopped, "hour");
  p.api.dispose();
  for (const [every, max] of [["2", 30], ["10", 6]]) {
    const q = page({ every });
    q.at(T0);
    assert.equal(q.text(), `PMP повторит через ${every} мин · попытка 1 из ${max} · `);
    q.api.dispose();
  }
});

test("человек печатает, текст в поле, открыто меню — нажатия нет; помеха ушла — нажатие", () => {
  const typing = page({ local: { [INPUT]: String(T0 + 5 * MIN - 10000) } });
  typing.at(T0);
  typing.at(T0 + 5 * MIN);
  assert.equal(typing.parts.retry.presses, 0);
  assert.equal(typing.ar().state, "wait");
  assert.equal(typing.ar().reason, "typing");
  assert.equal(typing.text(), "PMP повторит, когда поле освободится · попытка 1 из 12 · ");
  typing.at(T0 + 5 * MIN + 21000);
  assert.equal(typing.parts.retry.presses, 1, "30 с тишины прошли");
  typing.api.dispose();

  const draft = page({ draft: "пишу Claude" });
  draft.at(T0);
  draft.at(T0 + 5 * MIN);
  assert.equal(draft.parts.retry.presses, 0);
  assert.equal(draft.ar().reason, "field");
  draft.parts.editor.textContent = "";
  draft.at(T0 + 5 * MIN + 1000);
  assert.equal(draft.parts.retry.presses, 1);
  draft.api.dispose();

  const menu = page();
  menu.at(T0);
  const open = menu.document.body.add("div", { attrs: { role: "menu" }, rect: { left: 50, top: 50, width: 200, height: 120 } });
  menu.at(T0 + 5 * MIN);
  assert.equal(menu.parts.retry.presses, 0);
  assert.equal(menu.ar().reason, "menu");
  assert.equal(menu.text(), "PMP повторит, когда закроется меню · попытка 1 из 12 · ");
  open.remove();
  menu.at(T0 + 5 * MIN + 1000);
  assert.equal(menu.parts.retry.presses, 1);
  menu.api.dispose();
});

for (const [text, kind] of [
  ["Claude usage limit reached. Your limit will reset at 5pm", "limit"],
  ["API Error: 429 rate_limit_error", "limit"],
  ["Prompt is too long", "too-long"],
  ["API Error: 401 · Please run /login", "auth"],
  ["[Request interrupted by user]", "user-stop"],
  ["Something unexpected happened", "unknown"],
]) {
  test(`«${text}» — не повторяется: ни нажатия, ни строки`, () => {
    const p = page({ text });
    for (const at of [T0, T0 + 5 * MIN, T0 + 30 * MIN]) p.at(at);
    assert.equal(p.parts.retry.presses, 0);
    assert.equal(p.line(), null);
    assert.equal(p.ar().state, "skip");
    assert.equal(p.ar().kind, kind);
    p.api.dispose();
  });
}

test("признаки ошибок: сеть, 5xx и overloaded — повтор; числа целым словом", () => {
  const { autoRetryKind } = page().inner;
  for (const [text, kind] of [
    ['API Error: 529 {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}', "overloaded"],
    ["overloaded_error: please retry at a lower rate", "overloaded"],
    ["API Error: 500 Internal server error", "server"],
    ["API Error: 503 Service Unavailable", "server"],
    ["API Error: Request timed out.", "network"],
    ["connect ECONNREFUSED 127.0.0.1:443", "network"],
    ["Request of 4000 tokens failed: Connection error", "network"],
    // Карточки Claude Desktop 20.10 (кэш фронта): текст ошибки — в свёрнутых деталях, на виду только заголовок.
    ["Connection problem Check your internet connection, VPN, or proxy and try again. View details Try again", "network"],
    ["Connection went idle Try again", "network"],
    ["Response stopped before finishing Try again", "network"],
    ["Service is busy Try again", "overloaded"],
    ["API Error: 400 invalid_request_error", "bad-request"],
    ["Claude declined to continue: usage policy", "refusal"],
    ["", "unknown"],
    ["x".repeat(2001), "unknown"],
  ]) assert.equal(autoRetryKind(text), kind, text);
});

test("выключено или ключа нет — ничего", () => {
  for (const on of [null, "false"]) {
    const p = page({ on });
    for (const at of [T0, T0 + 5 * MIN, T0 + 10 * MIN]) p.at(at);
    assert.equal(p.parts.retry.presses, 0);
    assert.equal(p.line(), null);
    assert.equal(p.ar().state, "off");
    assert.equal(p.ar().on, false);
    p.api.dispose();
  }
});

test("«Отменить» нажатием, Enter и пробелом гасит повторы этого хода и убирает строку", () => {
  for (const how of ["click", "Enter", " "]) {
    const p = page();
    p.at(T0);
    const cancel = p.line().querySelector(CANCEL);
    assert.equal(cancel.tagName, "BUTTON");
    assert.equal(cancel.getAttribute("type"), "button");
    if (how === "click") assert.equal(p.document.dispatchEvent({ type: "click", target: cancel }), false, "клик не уходит в строку ленты");
    else p.win.dispatchEvent({ type: "keydown", key: how, target: cancel });
    assert.equal(p.line(), null, how);
    assert.equal(p.ar().stoppedBy, "cancel", how);
    p.at(T0 + 5 * MIN);
    p.at(T0 + 20 * MIN);
    assert.equal(p.parts.retry.presses, 0, how);
    assert.equal(p.line(), null, how);
    assert.equal(p.store().local_test.stopped, "cancel");
    p.api.dispose();
  }
});

test("перезагрузка окна после часа не возобновляет повторы старой ошибки", () => {
  const p = page();
  p.at(T0);
  assert.equal(p.store().local_test.first, T0);
  const again = p.reload();
  assert.equal(again.error, null, String(again.error?.stack ?? again.error));
  p.at(T0 + 61 * MIN);
  assert.equal(p.parts.retry.presses, 0);
  assert.equal(p.ar().stoppedBy, "hour");
  assert.equal(p.text(), "PMP перестал повторять: прошёл час");
  p.api.dispose();

  // То же с записью, оставленной другим окном 61 минуту назад (три попытки уже было).
  const stored = { local_test: { first: T0 - 61 * MIN, tries: 3, last: T0 - 46 * MIN, stopped: null, print: "1:x", row: 1,
    human: "0", seen: T0 - 46 * MIN, presses: [T0 - 56 * MIN, T0 - 51 * MIN, T0 - 46 * MIN] } };
  const q = page({ local: { [STORE]: JSON.stringify(stored) } });
  q.at(T0);
  q.at(T0 + 10 * MIN);
  assert.equal(q.parts.retry.presses, 0);
  assert.equal(q.ar().stoppedBy, "hour");
  q.api.dispose();
});

test("ход идёт — строки нет; ход кончился ответом без ошибки — запись сброшена", () => {
  const p = page();
  p.at(T0);
  assert.ok(p.line());
  const stop = p.document.body.add("button", { attrs: { "data-testid": "code-prompt-stop" }, rect: { left: 900, top: 700, width: 24, height: 24 } });
  p.at(T0 + MIN);
  assert.equal(p.ar().state, "working");
  assert.equal(p.line(), null);
  // Claude ответил: строки с ошибкой нет, последняя строка — ответ.
  p.parts.row.remove();
  p.parts.feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text", "data-index": "2" },
    rect: box(120), text: "Готово, отчёт в docs/report.md" });
  stop.remove();
  p.at(T0 + 2 * MIN);
  assert.equal(p.store().local_test.first, T0, "ответ без ошибки держится 5 с, прежде чем запись сбросится");
  p.at(T0 + 2 * MIN + 6000);
  assert.equal(p.store().local_test.first, null);
  assert.equal(p.ar().state, "idle");
  assert.equal(p.parts.retry.presses, 0);
  p.api.dispose();
});

test("после ошибки — ход человека: старую ошибку не жмём, эпизод сброшен", () => {
  const p = page();
  p.at(T0);
  p.parts.feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "human", "data-index": "2" },
    rect: box(120), text: "Попробуй ещё раз" });
  p.at(T0 + MIN);
  assert.equal(p.ar().state, "not-last");
  assert.equal(p.line(), null);
  assert.equal(p.store().local_test.first, null, "ход человека новее ошибки — новый эпизод");
  p.at(T0 + 5 * MIN);
  p.at(T0 + 10 * MIN);
  assert.equal(p.parts.retry.presses, 0);
  p.api.dispose();
});

test("лента не у низа (старая ошибка в DOM) и «Retry» вне ленты — нажатия нет", () => {
  const p = page();
  Object.assign(p.parts.feed, { scrollHeight: 3000, clientHeight: 600, scrollTop: 0 });
  for (const at of [T0, T0 + 5 * MIN, T0 + 10 * MIN]) p.at(at);
  assert.equal(p.parts.retry.presses, 0);
  assert.equal(p.ar().state, "not-bottom");
  assert.equal(p.line(), null);
  p.api.dispose();

  const q = page({ label: "Copy" });
  const tile = q.parts.block.add("button", { text: "Retry", rect: { left: 120, top: 640, width: 60, height: 20 } });
  tile.presses = 0;
  tile.addEventListener("click", () => { tile.presses += 1; });
  for (const at of [T0, T0 + 5 * MIN, T0 + 10 * MIN]) q.at(at);
  assert.equal(tile.presses, 0, "повтор загрузки в поле ввода — не наш");
  assert.equal(q.ar().state, "idle");
  q.api.dispose();
});

test("без строк ленты блок ошибки не шире ленты: текст всего разговора — не ошибка", () => {
  const loaded = loadInject({
    storage: { local: { [ON]: "true", [EVERY]: "5" } },
    html: dom => {
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: box(0, 600) });
      feed.add("div", { text: NETWORK, rect: box(10) });
      const retry = feed.add("div", { rect: box(60) }).add("button", { text: "Try again", rect: { left: 10, top: 64, width: 80, height: 24 } });
      retry.presses = 0;
      retry.addEventListener("click", () => { retry.presses += 1; });
      return { ...dom.composer(), feed, retry };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  for (const at of [T0, T0 + 5 * MIN, T0 + 10 * MIN]) loaded.inner.autoRetryTick(at);
  assert.equal(loaded.parts.retry.presses, 0);
  assert.equal(plain(loaded.api.status().autoRetry).kind, "unknown");
  assert.equal(loaded.dom.query(LINE), null, "строка не встаёт за лентой");
  loaded.api.dispose();
});

test("ход после нашего нажатия идёт дольше минуты и падает снова — час не сбрасывается", () => {
  const p = page();
  p.at(T0);
  p.at(T0 + 5 * MIN);
  assert.equal(p.parts.retry.presses, 1);
  const stop = p.document.body.add("button", { attrs: { "data-testid": "code-prompt-stop" }, rect: { left: 900, top: 700, width: 24, height: 24 } });
  p.at(T0 + 5 * MIN + 2000);
  assert.equal(p.ar().outcome, "started");
  p.at(T0 + 7 * MIN);
  p.parts.row.remove();
  const second = errorRow(p.dom, p.parts.feed, 2, 'API Error: 529 {"type":"overloaded_error"}');
  stop.remove();
  p.at(T0 + 7 * MIN + 1000);
  assert.equal(p.ar().state, "count");
  assert.equal(p.ar().kind, "overloaded");
  assert.equal(p.text(), "PMP повторит через 3 мин · попытка 2 из 12 · ");
  assert.equal(p.store().local_test.first, T0);
  p.at(T0 + 10 * MIN);
  assert.equal(second.retry.presses, 1);
  assert.equal(p.ar().tries, 2);
  p.api.dispose();
});

test("потолок: эпизод сброшен, а за последний час нажатий уже 60/N — ждём", () => {
  const presses = Array.from({ length: 12 }, (_, k) => T0 - 12 * MIN + k * MIN);
  const p = page({ local: { [STORE]: JSON.stringify({ local_test: { first: null, tries: 0, last: null, stopped: null, print: "",
    row: null, human: "", seen: T0 - MIN, presses } }) } });
  p.at(T0);
  p.at(T0 + 5 * MIN);
  assert.equal(p.parts.retry.presses, 0);
  assert.equal(p.ar().state, "count");
  assert.equal(p.text(), "PMP повторит через 43 мин · попытка 1 из 3 · ");
  p.at(T0 + 48 * MIN);
  assert.equal(p.parts.retry.presses, 1);
  p.api.dispose();
});

test("второе окно того же чата уже нажало — это окно не жмёт", () => {
  const p = page();
  p.at(T0);
  const store = p.store();
  Object.assign(store.local_test, { tries: 1, last: T0 + 5 * MIN - 500, presses: [T0 + 5 * MIN - 500] });
  p.win.localStorage.setItem(STORE, JSON.stringify(store));
  p.at(T0 + 5 * MIN);
  assert.equal(p.parts.retry.presses, 0);
  assert.equal(p.ar().tries, 1);
  assert.equal(p.text(), "PMP повторит через 5 мин · попытка 2 из 12 · ");
  p.api.dispose();
});

test("человек сам нажал повтор — новый эпизод, прежний час его не держит", () => {
  const p = page();
  p.at(T0);
  p.at(T0 + 61 * MIN);
  assert.equal(p.ar().stoppedBy, "hour");
  p.document.dispatchEvent({ type: "click", target: p.parts.retry, isTrusted: true });
  assert.equal(p.store().local_test.first, null);
  assert.equal(p.ar().manual, 1);
  p.at(T0 + 62 * MIN);
  assert.equal(p.ar().state, "count");
  assert.equal(p.store().local_test.first, T0 + 62 * MIN);
  p.api.dispose();
});

test("команда auto-retry: строки, интервал вне 2/5/10 — 5, выключение снимает строку сразу", () => {
  const p = page({ on: null, every: null });
  p.dom.command({ id: "r1", action: "auto-retry", on: "true", every: "7" });
  assert.equal(p.win.localStorage.getItem(ON), "true");
  assert.equal(p.win.localStorage.getItem(EVERY), "5");
  p.dom.command({ id: "r2", action: "auto-retry", on: "true", every: "10" });
  assert.equal(p.ar().every, 10);
  p.at(T0);
  assert.ok(p.line());
  p.dom.command({ id: "r3", action: "auto-retry", on: "false", every: "10" });
  assert.equal(p.win.localStorage.getItem(ON), "false");
  assert.equal(p.line(), null);
  assert.equal(p.ar().state, "off");
  p.api.dispose();
});

test("тик идёт с сердцебиения; dispose снимает строку", () => {
  const p = page();
  p.dom.fireKind("interval");
  assert.equal(p.ar().state, "count");
  assert.ok(p.line());
  p.api.dispose();
  assert.equal(p.dom.queryAll(LINE).length, 0);
});
