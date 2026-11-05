// Красное время последнего сообщения (раздел 12о inject.js, #7750, WF94): 50+ мин тишины — warm,
// 60+ — cold, время под последним сообщением краснеет (status().signal.stale); чат работает —
// не краснеет. Три полоски окна (ручка поля и дубли у краёв) с #7848 не красятся и не мигают —
// серые; режимы need/warm/cold/work полоски (status().signal.mode, fill, changes) сняты в WF248.
//
// Стенд: строка сайдбара с сессией чата и лента сообщений с entry.timestamp в волокне (как
// times-wf94.test.mjs). Время — аргументы signalTick(t, wall): монотонное и настенное, часы подменены.
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
// Красное время — из status(); полоски при этом серые: ни атрибута, ни своего стиля (#7848).
const stale = loaded => {
  for (const sel of RAILS) {
    const node = loaded.document.querySelector(sel);
    assert.ok(node, sel);
    assert.equal(node.hasAttribute("data-myclaude-signal"), false, `${sel} не красится`);
    assert.equal(node.style.getPropertyValue("--myclaude-signal-fill"), "");
  }
  return signal(loaded).stale;
};
const iso = ms => new Date(ms).toISOString();

test("#7750: пороги — 50 и 60 минут; режимов полоски больше нет (WF248)", () => {
  const { inner } = loadInner();
  assert.equal(inner.CACHE_WARN_MS, 50 * MIN);
  assert.equal(inner.CACHE_TTL_MS, 60 * MIN);
  assert.equal(inner.signalMode, undefined, "signalMode снят");
  const { loaded } = page();
  loaded.inner.signalTick(1e6, BASE);
  assert.deepEqual(Object.keys(signal(loaded)).sort(), ["ago", "stale"], "в status().signal — только время");
});

test("#7750: чат работает — время не краснеет и через 70 минут тишины; полоски серые (#7848)", () => {
  const { loaded, s } = page({ s: session({ liveStatus: "running", isRunning: true }), rows: [["e1", iso(BASE)]] });
  const { waitTick, signalTick, stampTimes } = loaded.inner;
  const [row] = loaded.parts.rows;
  stampTimes();
  let t = 1e6;
  waitTick(t); signalTick(t, BASE + 70 * MIN);
  assert.equal(stale(loaded), null);
  assert.equal(row.hasAttribute("data-myclaude-stale"), false);
  Object.assign(s, { liveStatus: "idle", isRunning: false });
  waitTick(t += 1000); signalTick(t, BASE + 70 * MIN);
  assert.equal(stale(loaded), "cold", "ход кончился — кэш уже холодный");
});

test("#7750: стоп на месте — работает, даже если сайдбар молчит: время не краснеет", () => {
  const { loaded } = page({ rows: [["e1", iso(BASE)]] });
  loaded.inner.stampTimes();
  loaded.document.body.add("button", { attrs: { "data-testid": "chat-input-stop" } });
  loaded.inner.signalTick(1e6, BASE + 70 * MIN);
  assert.equal(stale(loaded), null);
});

test("#7750: 50 мин тишины — warm, время последнего сообщения красное; 60 — cold", () => {
  const { loaded } = page({ rows: [["e1", iso(BASE - 70 * MIN)], ["e2", iso(BASE)]] });
  const { stampTimes, signalTick } = loaded.inner;
  const [old, last] = loaded.parts.rows;
  stampTimes();
  let t = 1e6;
  signalTick(t, BASE + 49 * MIN);
  assert.equal(stale(loaded), null, "49 минут — ещё тихо");
  assert.equal(last.hasAttribute("data-myclaude-stale"), false);
  signalTick(t += 1000, BASE + 50 * MIN);
  assert.equal(stale(loaded), "warm");
  assert.equal(last.getAttribute("data-myclaude-stale"), "warm", "время под ПОСЛЕДНИМ сообщением краснеет");
  assert.equal(old.hasAttribute("data-myclaude-stale"), false, "старое сообщение не трогаем");
  assert.equal(signal(loaded).ago, Math.floor((Date.now() - BASE) / MIN));
  signalTick(t += 1000, BASE + 61 * MIN);
  assert.equal(stale(loaded), "cold");
  assert.equal(last.getAttribute("data-myclaude-stale"), "cold");
});

test("#7750: новое сообщение снимает красное", () => {
  const { loaded } = page({ rows: [["e1", iso(BASE)]] });
  const { stampTimes, signalTick } = loaded.inner;
  const [first] = loaded.parts.rows;
  stampTimes();
  signalTick(1e6, BASE + 55 * MIN);
  assert.equal(stale(loaded), "warm");
  assert.equal(first.getAttribute("data-myclaude-stale"), "warm");
  const next = addAnswer(loaded.parts.feed, "e2", iso(BASE + 55 * MIN));
  stampTimes();
  signalTick(1e6 + 1000, BASE + 55 * MIN);
  assert.equal(stale(loaded), null);
  assert.equal(first.hasAttribute("data-myclaude-stale"), false);
  assert.equal(next.hasAttribute("data-myclaude-stale"), false);
});

test("#7750: лента пролистана вверх — старые строки не сбивают счёт; висящий вопрос — время всё равно краснеет", () => {
  const { loaded, s } = page({ rows: [["e1", iso(BASE)]] });
  const { stampTimes, signalTick, waitTick } = loaded.inner;
  const [row] = loaded.parts.rows;
  stampTimes();
  // Виртуальная лента: последняя строка ушла, на экране старая.
  row.remove();
  addAnswer(loaded.parts.feed, "e0", iso(BASE - 120 * MIN));
  stampTimes();
  signalTick(1e6, BASE + 10 * MIN);
  assert.equal(stale(loaded), null, "последнее сообщение — 10 минут назад, а не два часа");
  assert.equal(signal(loaded).ago, Math.floor((Date.now() - BASE) / MIN));
  // Долистал назад — строка последнего сообщения снова на экране; вопрос висит 55 минут — время под ним красное.
  s.liveStatus = "awaiting";
  const back = addAnswer(loaded.parts.feed, "e1", iso(BASE));
  stampTimes();
  let t = 2e6;
  waitTick(t); signalTick(t, BASE + 55 * MIN);
  waitTick(t += 2000); signalTick(t, BASE + 55 * MIN);
  assert.equal(stale(loaded), "warm");
  assert.equal(back.getAttribute("data-myclaude-stale"), "warm");
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
