// #11323, раздел 12д³ inject.js: клик по внешней ссылке ленты — сначала Пимп (/open-link?kind=web, К-LINK: уже
// открытая вкладка Chromium вперёд), молчит или отказал — прежний window.open (#11118), один раз.
// Слово Элвиса 31.10.2026: «Я чик нажал и перешёл сразу в Хром на нужную вкладку».
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_a6b6fb8a-03e0-45a5-af2e-30d1d800bd1e";
const EXTERNAL = "https://github.com/ElvisIglikov/PimpMyClaude/pull/7";
const ASK = `http://127.0.0.1:47615/open-link?kind=web&url=${encodeURIComponent(EXTERNAL)}`;
const settle = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };

const page = reply => {
  const nodes = {};
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`,
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    geometry: { frame: [-1512, -982, 640, 900] },
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      const prose = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "1" } })
        .add("div", { attrs: { class: "prose" } });
      nodes.external = prose.add("a", { attrs: { href: EXTERNAL, target: "_blank" }, text: "PR" });
      nodes.claude = prose.add("a", { attrs: { href: "https://claude.ai/settings" }, text: "настройки" });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.win.fetch = address => { loaded.calls.push(String(address)); return reply(); };
  loaded.opened = [];
  loaded.win.open = (url, target) => { loaded.opened.push([url, target]); return null; };
  return { loaded, nodes };
};
const click = (loaded, target, extra = {}) =>
  loaded.document.dispatchEvent({ type: "click", isTrusted: true, target, button: 0, detail: 1, ...extra });
const ext = loaded => plain(loaded.api.status().externalLinks);

test("11323: Пимп ответил opened:true — window.open не зван", async () => {
  const { loaded, nodes } = page(() => Promise.resolve({ ok: true, status: 200, json: async () => ({ opened: true, via: "web" }) }));
  assert.equal(click(loaded, nodes.external), false, "Claude клика не видит");
  await settle();
  assert.deepEqual(loaded.calls, [ASK]);
  assert.deepEqual(loaded.opened, []);
  assert.deepEqual(ext(loaded), { clicks: 1, repeats: 0, failed: 0, pimp: 1, last: { host: "github.com", ok: true, via: "pimp" } });
  loaded.api.dispose();
});

test("11323: старый Пимп (400 opened:false) и отказ fetch — window.open ровно раз", async () => {
  for (const reply of [
    () => Promise.resolve({ ok: false, status: 400, json: async () => ({ opened: false }) }),
    () => Promise.resolve({ ok: true, status: 200, json: async () => ({ opened: false }) }),
    () => Promise.reject(new TypeError("Failed to fetch")),
    () => { throw new TypeError("Failed to fetch"); },
  ]) {
    const { loaded, nodes } = page(reply);
    assert.equal(click(loaded, nodes.external), false);
    await settle();
    assert.deepEqual(loaded.opened, [[EXTERNAL, "_blank"]]);
    assert.equal(ext(loaded).pimp, 0);
    loaded.api.dispose();
  }
});

test("11323: Пимп молчит — window.open один раз по сроку, поздний ответ второго не открывает", async () => {
  let answer = null;
  const { loaded, nodes } = page(() => new Promise(resolve => { answer = resolve; }));
  assert.ok(loaded.inner.EXTERNAL_LINK_WAIT_MS <= 2000, "короткое ожидание — успеть в окно Claude 5 с");
  click(loaded, nodes.external);
  await settle();
  assert.deepEqual(loaded.opened, [], "ждём Пимпа");
  // Таймеры страницы — стаб dom.mjs: срок ожидания зовём руками.
  const wait = [...loaded.win.__timers.entries()].filter(([, item]) => item.kind === "timeout"
    && item.ms === loaded.inner.EXTERNAL_LINK_WAIT_MS);
  assert.equal(wait.length, 1, "один срок на клик");
  loaded.win.__timers.delete(wait[0][0]);
  wait[0][1].fn();
  await settle();
  assert.deepEqual(loaded.opened, [[EXTERNAL, "_blank"]]);
  answer({ ok: true, status: 200, json: async () => ({ opened: true, via: "web" }) });
  await settle();
  assert.equal(loaded.opened.length, 1);
  assert.equal(ext(loaded).pimp, 0);
  loaded.api.dispose();
});

test("11323: адрес Claude — не трогаем, к Пимпу не ходим", async () => {
  const { loaded, nodes } = page(() => Promise.resolve({ ok: true, status: 200, json: async () => ({ opened: true }) }));
  assert.equal(click(loaded, nodes.claude), true);
  await settle();
  assert.deepEqual(loaded.calls, []);
  assert.deepEqual(loaded.opened, []);
  loaded.api.dispose();
});
