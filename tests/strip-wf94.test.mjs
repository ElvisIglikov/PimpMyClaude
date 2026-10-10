// Состояние чата (раздел 12о inject.js, #7750, WF94): status().signal.mode —
// need (нужен Элвис), warm (кэш стынет, 50+ мин тишины), cold (60+ мин), work
// (чат работает, fill — процент марафона). Приоритет: need > warm/cold > work.
// Время последнего сообщения при warm/cold — красное. Три полоски окна (ручка
// поля и дубли у краёв) с #7848 не красятся и не мигают — серые.
//
// Стенд: строка сайдбара с сессией чата (как wait-glow.test.mjs) и лента
// сообщений с entry.timestamp в волокне (как times-wf94.test.mjs). Время —
// аргументы signalTick(t, wall): монотонное и настенное, часы подменены.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";

const A = "local_aaaa-1111";
const MIN = 60000;
const ROW = "group/msg group/message-row flex flex-col w-full relative gap-sm";
const RAILS = ["#myclaude-input-handle", "#myclaude-super-top", "#myclaude-super-bottom"];
const BASE = Date.parse("2026-09-26T12:00:00Z");

const session = extra => ({
  ref: { kind: "code", id: A }, title: A, liveStatus: "idle", isRunning: false,
  hasPendingApproval: false, pendingPermissions: 0, hasCompleted: false, isUnread: false, ...extra,
});
const addAnswer = (feed, id, at) => {
  const row = feed.add("div", { class: ROW });
  row.add("div", { class: "flex flex-col select-text", text: "ответ" });
  row["__reactFiber$test"] = { memoizedProps: { className: ROW }, return: { memoizedProps: { entry: { id, author: "assistant", timestamp: at }, itemIdx: 0 }, return: null } };
  return row;
};

const page = ({ s = session(), rows = [] } = {}) => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${A}`, title: "Claude", hasFocus: false,
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({});
      const bar = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
      const row = bar.add("div", { attrs: { "data-row-key": `code:${A}` } });
      row["__reactFiber$test"] = { memoizedProps: { "data-row-key": `code:${A}` }, return: { memoizedProps: { session: s }, return: null } };
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } });
      parts.feed = feed;
      parts.rows = rows.map(([id, at]) => addAnswer(feed, id, at));
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return { loaded, s };
};
const signal = loaded => plain(loaded.api.status().signal);
// Режим — из status(); полоски при этом серые: ни атрибута, ни своего стиля (#7848).
const modes = loaded => {
  for (const sel of RAILS) {
    const node = loaded.document.querySelector(sel);
    assert.ok(node, sel);
    assert.equal(node.hasAttribute("data-myclaude-signal"), false, `${sel} не красится`);
    assert.equal(node.style.getPropertyValue("--myclaude-signal-fill"), "");
  }
  const mode = signal(loaded).mode;
  return [mode, mode, mode];
};
const iso = ms => new Date(ms).toISOString();

test("#7750: приоритет — нужен Элвис > кэш стынет > работает", () => {
  const { inner } = loadInner();
  const { signalMode, CACHE_WARN_MS, CACHE_TTL_MS } = inner;
  assert.equal(CACHE_WARN_MS, 50 * MIN);
  assert.equal(CACHE_TTL_MS, 60 * MIN);
  assert.equal(signalMode({}), "");
  assert.equal(signalMode({ working: true }), "work");
  assert.equal(signalMode({ ago: 49 * MIN }), "");
  assert.equal(signalMode({ ago: 50 * MIN }), "warm");
  assert.equal(signalMode({ ago: 60 * MIN }), "cold");
  assert.equal(signalMode({ need: true, ago: 55 * MIN }), "need", "нужен Элвис сильнее кэша");
  assert.equal(signalMode({ need: true, working: true }), "need");
  assert.equal(signalMode({ working: true, ago: 70 * MIN }), "work", "чат работает — кэш не стынет");
});

test("#7750: вопрос человеку — need; касание окна не снимает", () => {
  const { loaded, s } = page({ s: session({ liveStatus: "awaiting" }) });
  const { waitTick, signalTick } = loaded.inner;
  let t = 1e6;
  waitTick(t); signalTick(t, BASE);
  assert.deepEqual(modes(loaded), [null, null, null], "не сразу: держится WAIT_HOLD_MS — Авто-Allow не мигает");
  t += 2000; waitTick(t); signalTick(t, BASE);
  assert.deepEqual(modes(loaded), ["need", "need", "need"]);
  loaded.win.dispatchEvent({ type: "keydown", key: "a" });
  t += 1000; waitTick(t); signalTick(t, BASE);
  assert.equal(modes(loaded)[2], "need", "ответить всё равно надо");
  Object.assign(s, { liveStatus: "running", isRunning: true });
  t += 1000; waitTick(t); signalTick(t, BASE);
  assert.deepEqual(modes(loaded), ["work", "work", "work"], "ответил — чат работает");
  assert.equal(signal(loaded).mode, "work");
});

test("#7750: конец хода (свечение 12и) и «Скажи — и сделаю» (12м) — зелёный", () => {
  const { loaded, s } = page({ s: session({ liveStatus: "running", isRunning: true }) });
  const { waitTick, signalTick, attnState } = loaded.inner;
  let t = 1e6;
  waitTick(t);
  Object.assign(s, { liveStatus: "idle", isRunning: false });
  for (let i = 0; i < 4; i += 1) waitTick(t += 1000);
  signalTick(t, BASE);
  assert.equal(modes(loaded)[2], "need");
  loaded.win.dispatchEvent({ type: "pointerdown" });
  waitTick(t += 1000); signalTick(t, BASE);
  assert.equal(modes(loaded)[2], null, "увидел конец хода — свечение и полоска гаснут вместе");
  attnState.blink = true;
  signalTick(t += 1000, BASE);
  assert.equal(modes(loaded)[2], "need", "мигают заголовки «нужен Элвис» — полоска тоже");
  attnState.blink = false;
});

test("#7750: работает — work и процент марафона в status(); полоски серые (#7848)", () => {
  const { loaded } = page({ s: session({ liveStatus: "running", isRunning: true }) });
  const { waitTick, signalTick, progressState } = loaded.inner;
  let t = 1e6;
  waitTick(t); signalTick(t, BASE);
  assert.equal(modes(loaded)[2], "work");
  assert.equal(signal(loaded).fill, null);
  progressState.info = { wf: 2, of: 4, pct: 50, total: 37.5, state: "run" };
  signalTick(t += 1000, BASE);
  assert.equal(modes(loaded)[2], "work");
  assert.equal(signal(loaded).fill, 37.5);
  progressState.info = null;
});

test("#7750: стоп на месте — работает, даже если сайдбар молчит", () => {
  const { loaded } = page();
  loaded.document.body.add("button", { attrs: { "data-testid": "chat-input-stop" } });
  loaded.inner.signalTick(1e6, BASE);
  assert.equal(modes(loaded)[2], "work");
});

test("#7750: 50 мин тишины — warm, время последнего сообщения красное; 60 — cold", () => {
  const { loaded } = page({ rows: [["e1", iso(BASE - 70 * MIN)], ["e2", iso(BASE)]] });
  const { stampTimes, signalTick } = loaded.inner;
  const [old, last] = loaded.parts.rows;
  stampTimes();
  let t = 1e6;
  signalTick(t, BASE + 49 * MIN);
  assert.deepEqual(modes(loaded), [null, null, null], "49 минут — ещё тихо");
  assert.equal(last.hasAttribute("data-myclaude-stale"), false);
  signalTick(t += 1000, BASE + 50 * MIN);
  assert.deepEqual(modes(loaded), ["warm", "warm", "warm"]);
  assert.equal(last.getAttribute("data-myclaude-stale"), "warm", "время под ПОСЛЕДНИМ сообщением краснеет");
  assert.equal(old.hasAttribute("data-myclaude-stale"), false, "старое сообщение не трогаем");
  assert.equal(signal(loaded).ago, Math.floor((Date.now() - BASE) / MIN));
  signalTick(t += 1000, BASE + 61 * MIN);
  assert.equal(modes(loaded)[2], "cold");
  assert.equal(last.getAttribute("data-myclaude-stale"), "cold");
});

test("#7750: новое сообщение снимает красное", () => {
  const { loaded } = page({ rows: [["e1", iso(BASE)]] });
  const { stampTimes, signalTick } = loaded.inner;
  const [first] = loaded.parts.rows;
  stampTimes();
  signalTick(1e6, BASE + 55 * MIN);
  assert.equal(modes(loaded)[2], "warm");
  assert.equal(first.getAttribute("data-myclaude-stale"), "warm");
  const next = addAnswer(loaded.parts.feed, "e2", iso(BASE + 55 * MIN));
  stampTimes();
  signalTick(1e6 + 1000, BASE + 55 * MIN);
  assert.equal(modes(loaded)[2], null);
  assert.equal(first.hasAttribute("data-myclaude-stale"), false);
  assert.equal(next.hasAttribute("data-myclaude-stale"), false);
});

test("#7750: лента пролистана вверх — старые строки не сбивают счёт; вопрос сильнее кэша", () => {
  const { loaded, s } = page({ rows: [["e1", iso(BASE)]] });
  const { stampTimes, signalTick, waitTick } = loaded.inner;
  const [row] = loaded.parts.rows;
  stampTimes();
  // Виртуальная лента: последняя строка ушла, на экране старая.
  row.remove();
  addAnswer(loaded.parts.feed, "e0", iso(BASE - 120 * MIN));
  stampTimes();
  signalTick(1e6, BASE + 10 * MIN);
  assert.equal(modes(loaded)[2], null, "последнее сообщение — 10 минут назад, а не два часа");
  s.liveStatus = "awaiting";
  let t = 2e6;
  waitTick(t); signalTick(t, BASE + 55 * MIN);
  waitTick(t += 2000); signalTick(t, BASE + 55 * MIN);
  assert.equal(modes(loaded)[2], "need");
});

test("#7848: правила — полоски без сигналов и мигания, красное время осталось", () => {
  const { inner } = loadInner();
  const css = plain(inner.RULES).join("\n");
  assert.doesNotMatch(css, /data-myclaude-signal|myclaude-signal-blink|myclaude-signal-run/);
  assert.match(css, /\[data-myclaude-stale\]>\[data-myclaude-stamp\],[^{]*\[data-myclaude-stale\] \[aria-label="Message actions"\] time\{color:#ef4444 !important\}/);
});

test("#7750: dispose снимает красное время", () => {
  const { loaded } = page({ rows: [["e1", iso(BASE)]] });
  const { stampTimes, signalTick } = loaded.inner;
  const [row] = loaded.parts.rows;
  stampTimes();
  signalTick(1e6, BASE + 55 * MIN);
  assert.equal(row.getAttribute("data-myclaude-stale"), "warm");
  loaded.api.dispose();
  assert.equal(row.hasAttribute("data-myclaude-stale"), false);
  assert.equal(loaded.dom.queryAll("[data-myclaude-signal]").length, 0);
});
