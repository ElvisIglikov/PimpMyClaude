// WF120, батч B-P1b (#7533): «▦ Галерея» в просмотре фото (раздел 12л).
//
// Кнопка левее ✕ шлёт тот же запрос, что «▦ Галерея» (К-V1: GET /viewer?chat=<id>&on=1),
// — Pimp Viewer показывает все файлы чата сеткой с номерами, которые понимает чат;
// своей сетки в просмотре нет. Видна, только если у чата есть файлы во Viewer
// (viewer-counts, К-V7). Приложение ответило — просмотр закрывается (Viewer нет —
// приложение говорит это своей плашкой). Пока ждёт — буквы переливаются, второй раз
// не жмётся; отказ или нет ответа 3 с — «⚠️ Пимп не ответил» на кнопке, просмотр
// открыт, через 2,5 с — снова «▦ Галерея». Esc, ✕ и dispose снимают ожидание; поздний
// ответ просмотр не закрывает.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const CHAT = "local_dddd-4444";
const VIEWER = `http://127.0.0.1:47615/viewer?chat=${CHAT}&on=1`;
const BUSY = "data-myclaude-busy";
const settle = () => new Promise(resolve => setImmediate(resolve));

const photo = (parent, src) => {
  const img = parent.add("img", { attrs: { src } });
  img.naturalWidth = 640;
  img.naturalHeight = 1440;
  img.rect = { left: 0, top: 0, width: 71, height: 160 };
  return img;
};
let seq = 0;
const counts = (loaded, chats) => loaded.dom.command({ id: `wf120-${seq += 1}`, action: "viewer-counts", at: "now", scope: "all", chats });

// fetchMode: "ok" — ответ сразу, "fail" — отказ (Пимп не запущен), "manual" — ответ по команде теста.
const page = ({ href = `https://claude.ai/epitaxy/${CHAT}`, files = [5, 0], fetchMode = "ok" } = {}) => {
  const nodes = {};
  const loaded = loadInject({
    href,
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      const row = feed.add("div", { class: "group/message-row" });
      for (const name of ["a", "b"]) {
        const tile = row.add("span", { attrs: { role: "button", tabindex: "0" } });
        nodes[name] = photo(tile, `data:image/png;base64,${name.toUpperCase()}`);
      }
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.replies = [];
  loaded.win.fetch = address => {
    loaded.calls.push(address);
    if (fetchMode === "fail") return Promise.reject(new Error("refused"));
    if (fetchMode === "manual") return new Promise((resolve, reject) => loaded.replies.push({ resolve, reject }));
    return Promise.resolve({ ok: true });
  };
  if (files) counts(loaded, { [CHAT]: files });
  return { loaded, nodes };
};
const open = (loaded, index = 0) => loaded.inner.photoOpen(index);
const all = loaded => loaded.inner.photoState.parts.all;
const shown = loaded => all(loaded).style.getPropertyValue("display") === "block";
const isOpen = loaded => loaded.inner.photoState.open;
const press = (loaded, target = all(loaded)) =>
  loaded.document.querySelector("#myclaude-photo-view").dispatchEvent({ type: "click", target, detail: 1 });
const busy = loaded => all(loaded).getAttribute("aria-disabled") === "true";

test("кнопка левее ✕, видна при файлах чата во Viewer; подсказка с числом", () => {
  const { loaded } = page();
  open(loaded);
  const button = all(loaded);
  assert.equal(button.textContent, "▦ Галерея");
  assert.equal(button.tagName, "BUTTON");
  assert.equal(button.style.getPropertyValue("right"), "48px", "не левее ✕");
  assert.equal(button.style.getPropertyValue("top"), "8px");
  assert.equal(shown(loaded), true);
  assert.match(button.title, /\(5\)$/);
  assert.equal(button.getAttribute("aria-label"), "Файлы этого чата");
});

test("файлов во Viewer нет, счёт только у чужого чата или id чата неизвестен — кнопки нет", () => {
  const none = page({ files: null });
  open(none.loaded);
  assert.equal(shown(none.loaded), false, "viewer-counts ещё не приходил");

  const zero = page({ files: [0, 0] });
  open(zero.loaded);
  assert.equal(shown(zero.loaded), false);

  const stranger = page({ files: null });
  counts(stranger.loaded, { "local_eeee-5555": [7, 1] });
  open(stranger.loaded);
  assert.equal(shown(stranger.loaded), false, "файлы чужого чата");

  const anon = page({ href: "https://claude.ai/epitaxy" });
  counts(anon.loaded, { [CHAT]: [3, 0] });
  open(anon.loaded);
  assert.equal(isOpen(anon.loaded), true);
  assert.equal(shown(anon.loaded), false, "чат неизвестен");
  press(anon.loaded);
  assert.deepEqual(anon.loaded.calls, []);
});

test("счёт пришёл, пока просмотр открыт — кнопка появляется со следующим фото; пропал — клик ничего не шлёт", () => {
  const { loaded } = page({ files: null });
  open(loaded);
  assert.equal(shown(loaded), false);
  counts(loaded, { [CHAT]: [2, 0] });
  loaded.inner.photoStep(1);
  assert.equal(shown(loaded), true);
  counts(loaded, {});
  press(loaded);
  assert.deepEqual(loaded.calls, [], "файлов во Viewer уже нет");
  assert.equal(shown(loaded), false);
  assert.equal(isOpen(loaded), true, "клик по кнопке — не клик по фону");
});

test("клик — тот же запрос, что «▦ Галерея»; ждёт — переливается; HTTP 200 — просмотр остаётся", async () => {
  const { loaded } = page({ fetchMode: "manual" });
  open(loaded);
  press(loaded);
  assert.deepEqual(loaded.calls, [VIEWER]);
  assert.equal(busy(loaded), true);
  const span = all(loaded).querySelector(`span[${BUSY}]`);
  assert.equal(span?.textContent, "▦ Галерея", "буквы не переливаются");
  assert.equal(all(loaded).style.getPropertyValue("cursor"), "progress");
  assert.equal(isOpen(loaded), true, "до ответа просмотр открыт");
  loaded.replies[0].resolve({ ok: true });
  await settle();
  assert.equal(isOpen(loaded), true, "ACK не доказывает открытие Viewer");
  assert.equal(busy(loaded), false, "ACK снял ожидание");
  assert.equal(all(loaded).textContent, "▦ Галерея");
  assert.equal(loaded.inner.photoState.parts.all.querySelector(`[${BUSY}]`), null);
});

test("двойной клик и клик по переливающимся буквам — один запрос, просмотр не закрывается", () => {
  const { loaded } = page({ fetchMode: "manual" });
  open(loaded);
  press(loaded);
  press(loaded);
  press(loaded, all(loaded).querySelector("span"));
  assert.equal(loaded.calls.length, 1);
  assert.equal(isOpen(loaded), true, "клик по буквам кнопки ушёл в «клик по фону»");
  assert.equal(loaded.inner.photoState.parts.all.getAttribute("aria-disabled"), "true");
});

test("Пимп не запущен (отказ) — «⚠️ Пимп не ответил», просмотр открыт; через 2,5 с — «▦ Галерея»; повтор — снова запрос", async () => {
  const { loaded } = page({ fetchMode: "fail" });
  open(loaded);
  press(loaded);
  await settle();
  assert.equal(isOpen(loaded), true);
  assert.equal(busy(loaded), false);
  assert.equal(all(loaded).textContent, "⚠️ Пимп не ответил");
  loaded.dom.fireKind("timeout");
  assert.equal(all(loaded).textContent, "▦ Галерея");
  press(loaded);
  assert.equal(loaded.calls.length, 2, "после отказа кнопка жмётся снова");
});

test("нет ответа 3 с — отказ; поздний ответ просмотр не закрывает", async () => {
  const { loaded } = page({ fetchMode: "manual" });
  open(loaded);
  press(loaded);
  loaded.dom.fireKind("timeout");
  assert.equal(all(loaded).textContent, "⚠️ Пимп не ответил");
  assert.equal(busy(loaded), false);
  loaded.replies[0].resolve({ ok: true });
  await settle();
  assert.equal(isOpen(loaded), true, "поздний ответ закрыл просмотр");
});

test("Esc во время ожидания закрывает просмотр и снимает ожидание; поздний ответ не закрывает открытый заново", async () => {
  const { loaded } = page({ fetchMode: "manual" });
  open(loaded);
  const timers = loaded.counters.timers;
  press(loaded);
  assert.equal(loaded.counters.timers, timers + 1, "у ожидания нет срока");
  const passed = loaded.win.dispatchEvent({ type: "keydown", key: "Escape" });
  assert.equal(passed, false, "Esc ушёл в Claude — остановил бы агента");
  assert.equal(isOpen(loaded), false);
  assert.equal(busy(loaded), false);
  assert.equal(loaded.counters.timers, timers, "срок ожидания пережил закрытие");
  open(loaded, 1);
  loaded.replies[0].resolve({ ok: true });
  await settle();
  assert.equal(isOpen(loaded), true);
  assert.equal(all(loaded).textContent, "▦ Галерея");
});

test("✕ во время ожидания — то же, что Esc", () => {
  const { loaded } = page({ fetchMode: "manual" });
  open(loaded);
  press(loaded);
  press(loaded, loaded.inner.photoState.parts.close);
  assert.equal(isOpen(loaded), false);
  assert.equal(busy(loaded), false);
});

// Таймер, который поставило действие: новые номера таймеров после него.
const newTimers = (loaded, action) => {
  const before = new Set(loaded.dom.ids("timeout"));
  return Promise.resolve(action()).then(() => loaded.dom.ids("timeout").filter(id => !before.has(id)));
};

test("dispose во время ожидания и при надписи отказа — ни слоя, ни своих таймеров", async () => {
  const waiting = page({ fetchMode: "manual" });
  open(waiting.loaded);
  const wait = await newTimers(waiting.loaded, () => press(waiting.loaded));
  assert.equal(wait.length, 1);
  waiting.loaded.api.dispose();
  assert.equal(waiting.loaded.document.querySelector("#myclaude-photo-view"), null);
  assert.ok(!waiting.loaded.dom.ids("timeout").includes(wait[0]), "срок ожидания пережил dispose");
  waiting.loaded.replies[0].resolve({ ok: true });
  await settle();

  const failed = page({ fetchMode: "fail" });
  open(failed.loaded);
  const fail = await newTimers(failed.loaded, async () => { press(failed.loaded); await settle(); });
  assert.equal(all(failed.loaded).textContent, "⚠️ Пимп не ответил");
  assert.equal(fail.length, 1, "срок ожидания снят, остался срок надписи");
  failed.loaded.api.dispose();
  assert.ok(!failed.loaded.dom.ids("timeout").includes(fail[0]), "срок надписи пережил dispose");
});

for (const status of [404, 500]) test(`HTTP ${status}: видимый отказ, фото остаётся`, async () => {
  const { loaded } = page({ fetchMode: "manual" });
  open(loaded);
  press(loaded);
  loaded.replies[0].resolve({ ok: false, status });
  await settle();
  assert.equal(isOpen(loaded), true);
  assert.equal(all(loaded).textContent, "⚠️ Пимп не ответил");
  assert.equal(busy(loaded), false);
});
