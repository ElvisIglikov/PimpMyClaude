// #11201 (WF303) — шов 13в при открытой панели материалов (12п⁴, слово Элвиса 31.10 14:06: «Когда этот открыт
// PimpViewer… сквозняк этот не работает»). Корень шва — сосед скроллера, position:fixed, а у предков Claude
// contain/container-type (плитки): fixed считается от них. Панель слева сдвигает колонку (padding-left у
// .dframe-pane-host) — координаты окна уезжали на этот сдвиг: стенд 1022×669, панель 479 px — корень с x 966 вместо
// 487, второй жест уходил в пустоту над лентой (h 294 из 504, «внутри» не дойти). Стаб: коробка корня считается, как у
// браузера, — от левого верхнего угла содержащего блока (DOCK, 0) по style.left/top.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { loadInject, plain } from "./load.mjs";

const TAIL = JSON.parse(fs.readFileSync(new URL("./fixtures/seam-wf303/tail.json", import.meta.url), "utf8"));
const DIR = "/work/line";
const PREV = "local_40000000-0000-4000-8000-000000000004";
const CUR = "local_50000000-0000-4000-8000-000000000005";
const T0 = Date.parse("2026-10-15T09:00:00Z");
const LIST = [
  { sessionId: PREV, cwd: DIR, originCwd: DIR, createdAt: T0, title: "Прошлый чат" },
  { sessionId: CUR, cwd: DIR, originCwd: DIR, createdAt: T0 + 3600e3, title: "Этот чат" },
];
// Место панели материалов слева (CSS px): у плиток Claude левый край содержащего блока — здесь.
const DOCK = 480;
const flush = () => new Promise(resolve => setImmediate(resolve));

const stand = (dock = DOCK) => {
  const clock = { t: 1_000_000, q: new Map(), seq: 1 };
  let scrollTop = 1200;
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CUR}`, title: "Line",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    geometry: { viewport: { width: 1022, height: 669 } },
    html: dom => {
      const win = dom.window;
      win.performance.now = () => clock.t;
      const put = (fn, ms, every) => { const id = clock.seq++; clock.q.set(id, { fn, at: clock.t + Math.max(0, Number(ms) || 0), every }); return id; };
      win.setTimeout = (fn, ms) => put(fn, ms, 0);
      win.setInterval = (fn, ms) => put(fn, ms, Math.max(1, Number(ms) || 1));
      win.requestAnimationFrame = fn => put(() => fn(clock.t), 16, 0);
      win.clearTimeout = win.clearInterval = win.cancelAnimationFrame = id => { clock.q.delete(id); };
      const body = dom.document.body;
      const width = 1022 - dock;
      const feedRect = { left: dock, top: 45, width, height: 504 };
      const panel = body.add("div", { class: "epitaxy-chat-panel", rect: { left: dock, top: 0, width, height: 669 } });
      panel.add("div", { class: "epitaxy-titlebar", rect: { left: dock, top: 0, width, height: 45 } });
      const feed = panel.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: feedRect, computed: { overflowY: "auto" } });
      const column = feed.add("div", { class: "epitaxy-transcript-column", rect: { left: dock + 20, top: 45, width: width - 40, height: 504 } });
      column.add("div", { attrs: { "data-cds": "AssistantMessage" }, rect: { left: dock + 28, top: 45, width: width - 56, height: 200 } });
      Object.assign(feed, { clientHeight: feedRect.height, scrollHeight: 3000 });
      Object.defineProperty(feed, "scrollTop", {
        get: () => scrollTop,
        set: value => { scrollTop = Math.max(0, Math.min(feed.scrollHeight - feed.clientHeight, Number(value) || 0)); },
      });
      panel.add("div", { class: "epitaxy-prompt", rect: { left: dock, top: 549, width, height: 120 } });
      // Корень шва встаёт соседом ленты: его коробка — как у браузера под содержащим блоком плитки (dock, 0).
      const insert = panel.insertBefore.bind(panel);
      panel.insertBefore = (node, before) => {
        if (node?.id === "myclaude-seam" && !node.__box) {
          node.__box = true;
          node.getBoundingClientRect = () => {
            const left = dock + (Number.parseFloat(node.style.left) || 0);
            const top = Number.parseFloat(node.style.top) || 0;
            const w = Number.parseFloat(node.style.width) || 0;
            const h = Number.parseFloat(node.style.height) || 0;
            return { left, top, width: w, height: h, right: left + w, bottom: top + h, x: left, y: top };
          };
        }
        return insert(node, before);
      };
      const host = { olderHistoryAbove: false, isPoolPending: false, isResponding: false };
      feed.__reactFiber$stand = { memoizedProps: {}, return: { memoizedProps: host, return: null } };
      win["claude.web"] = {
        LocalSessions: {
          getAll: async () => LIST.map(s => ({ ...s })),
          getTranscriptTail: async id => structuredClone(id === PREV ? { messages: TAIL, hasMore: false } : { messages: [], hasMore: false }),
          getTranscriptPage: async () => ({ messages: [], hasMore: false, found: false }),
        },
      };
      return { feed, row: column };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const { win } = loaded;
  loaded.dom.router();
  const advance = async ms => {
    const end = clock.t + ms;
    for (let guard = 0; guard < 200000; guard += 1) {
      let next = null;
      for (const entry of clock.q) if (entry[1].at <= end && (!next || entry[1].at < next[1].at)) next = entry;
      if (!next) break;
      const [id, item] = next;
      clock.t = Math.max(clock.t, item.at);
      if (item.every) item.at += item.every; else clock.q.delete(id);
      try { item.fn(); } catch {}
      await flush();
    }
    clock.t = end;
    await flush();
  };
  const feed = loaded.parts.feed;
  const root = () => loaded.document.getElementById("myclaude-seam");
  const to = top => { win.dispatchEvent({ type: "pointerdown", target: feed }); feed.scrollTop = top; win.dispatchEvent({ type: "scroll", target: feed }); };
  const wheelNow = dy => {
    const event = { __event: true, type: "wheel", deltaY: dy, deltaX: 0, deltaMode: 0, target: loaded.parts.row, defaultPrevented: false };
    event.preventDefault = () => { event.defaultPrevented = true; };
    win.dispatchEvent(event);
    feed.dispatchEvent(event);
    return event;
  };
  const st = () => plain(loaded.api.status().seam);
  return { loaded, advance, feed, root, to, wheelNow, st };
};

test("панель материалов слева: корень шва — ровно над видимой лентой, не уехал на ширину панели", async () => {
  const s = stand();
  await s.advance(400);
  s.to(0);
  await s.advance(700);
  assert.ok(s.root(), "у верха блок собран заранее");
  let box = s.root().getBoundingClientRect();
  assert.deepEqual([box.left, box.top, box.width, box.height], [DOCK, 45, 1022 - DOCK, 504], "закрытый шов уже стоит над лентой");
  const ev = s.wheelNow(-100);
  assert.equal(ev.defaultPrevented, true);
  assert.deepEqual([s.st().phase, s.st().h, s.st().H], ["reveal", 100, 504]);
  box = s.root().getBoundingClientRect();
  assert.equal(box.left, DOCK, "открытый шов — с левого края ленты (без поправки был бы DOCK × 2)");
  assert.equal(box.right, 1022, "и до её правого края, не за окном");
  assert.equal(box.top, 45, "верх — под строкой заголовка");
  assert.equal(s.loaded.inner.seamState.col.style.marginLeft, "28px", "колонка — от края корня, как строка ответа");
  s.loaded.api.dispose();
});

test("без панели содержащий блок у края окна — поправки нет, место как было", async () => {
  const s = stand(0);
  await s.advance(400);
  s.to(0);
  await s.advance(700);
  s.wheelNow(-100);
  assert.equal(s.st().phase, "reveal");
  assert.equal(s.root().style.left, "0px");
  assert.equal(s.root().style.top, "45px");
  assert.deepEqual(Object.values(s.root().getBoundingClientRect()).slice(0, 4), [0, 45, 1022, 504]);
  s.loaded.api.dispose();
});
