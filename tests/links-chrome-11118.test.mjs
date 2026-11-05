// #11118, раздел 12д³ inject.js: внешние ссылки ленты — в браузер системы (window.open), не в браузер Claude справа.
// Слово Элвиса 29.10.2026: «А нельзя сразу Google Chrome открывать ссылки, чтобы без вот этого встроенного браузера».
//
// Что проверяется:
//   1) externalLinkMatch: http(s) чужих сайтов — да; адреса Claude, наши классы 12д², не-веб схемы, мусор — нет;
//   2) клик по внешней ссылке ленты — Claude клика не видит; Пимп не ответил (старый Пимп, #11323 — свой тест
//      links-webtab-11323) — window.open(адрес, "_blank"); нажатие глушится; двойной клик — одно окно;
//   3) наша ссылка (задача Trelvis) — по-прежнему 12д² (/open-link), 12д³ её не трогает;
//   4) модификатор, синтетический клик, правая кнопка, поле ввода, ссылка вне ленты — не трогаем;
//   5) status().externalLinks; после dispose слушателей нет.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_a6b6fb8a-03e0-45a5-af2e-30d1d800bd1e";
const EXTERNAL = "https://github.com/ElvisIglikov/PimpMyClaude/pull/7";
const TASK = "https://vlusnoff-production.up.railway.app/#t/10850";
const settle = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };

const page = () => {
  const nodes = {};
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`,
    storage: { local: { "myclaude-auto-allow-roam": "off", "myclaude-trust-root-v1": "/Users/dev/Projects/" } },
    geometry: { frame: [-1512, -982, 640, 900] },
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      const row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "3" } });
      const prose = row.add("div", { attrs: { class: "prose" } });
      nodes.external = prose.add("a", { attrs: { href: EXTERNAL, target: "_blank" }, text: "PR" });
      nodes.plainHttp = prose.add("a", { attrs: { href: "http://example.com/a?b=1#c" }, text: "http" });
      nodes.claude = prose.add("a", { attrs: { href: "https://claude.ai/settings" }, text: "настройки" });
      nodes.task = prose.add("a", { attrs: { href: TASK }, text: "#10850" });
      nodes.mail = prose.add("a", { attrs: { href: "mailto:a@b.c" }, text: "почта" });
      const box = dom.document.body.add("div", { attrs: { contenteditable: "true" } });
      nodes.typed = box.add("div", { attrs: { class: "prose" } }).add("a", { attrs: { href: EXTERNAL }, text: "в поле" });
      nodes.outside = dom.document.body.add("a", { attrs: { href: EXTERNAL }, text: "вне ленты" });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.win.fetch = address => {
    loaded.calls.push(String(address));
    if (String(address).includes("kind=web")) return Promise.reject(new TypeError("Failed to fetch"));
    return Promise.resolve({ ok: true, status: 200, json: async () => ({ opened: true, via: "trelvis" }) });
  };
  loaded.opened = [];
  loaded.win.open = (url, target) => { loaded.opened.push([url, target]); return null; };
  return { loaded, nodes };
};
const click = (loaded, target, extra = {}) =>
  loaded.document.dispatchEvent({ type: "click", isTrusted: true, target, button: 0, detail: 1, ...extra });
const ext = loaded => plain(loaded.api.status().externalLinks);

test("12д³: какие адреса — внешние", () => {
  const { loaded } = page();
  const match = href => loaded.inner.externalLinkMatch(href);
  assert.equal(match(EXTERNAL), EXTERNAL);
  assert.equal(match("http://example.com"), "http://example.com/");
  assert.equal(match("  https://x.ru/путь  "), "https://x.ru/%D0%BF%D1%83%D1%82%D1%8C");
  for (const href of [
    "https://claude.ai/new", "https://www.claude.com/x", "https://docs.anthropic.com/a", "https://claude.ai./x",
    TASK, "trelvis://task/5", "mailto:a@b.c", "file:///Users/dev/a.html", "/Users/dev/a.html", "docs/65.html",
    "javascript:alert(1)", "", null,
  ]) assert.equal(match(href), null, String(href));
  assert.equal(match("https://notclaude.ai/x"), "https://notclaude.ai/x", "похожий хост — чужой сайт");
  loaded.api.dispose();
});

test("12д³: клик по внешней ссылке — Пимп молчит → window.open, Claude клика не видит; двойной — одно окно", async () => {
  const { loaded, nodes } = page();
  for (const type of ["pointerdown", "mousedown"]) {
    assert.equal(loaded.document.dispatchEvent({ type, isTrusted: true, target: nodes.external, button: 0 }), false, type);
  }
  assert.deepEqual(loaded.opened, [], "нажатие само ничего не открывает");
  assert.equal(click(loaded, nodes.external), false, "клик ушёл Claude — открылся бы браузер справа");
  await settle();
  assert.deepEqual(loaded.opened, [[EXTERNAL, "_blank"]], "Пимп не ответил — сразу window.open, окно Claude пускает 5 с");
  assert.deepEqual(loaded.calls, [`http://127.0.0.1:47615/open-link?kind=web&url=${encodeURIComponent(EXTERNAL)}`]);
  click(loaded, nodes.external);
  await settle();
  assert.equal(loaded.opened.length, 1);
  assert.equal(click(loaded, nodes.plainHttp), false);
  await settle();
  assert.deepEqual(loaded.opened.at(-1), ["http://example.com/a?b=1#c", "_blank"]);
  assert.deepEqual(ext(loaded), { clicks: 2, repeats: 1, failed: 0, pimp: 0, last: { host: "example.com", ok: true } });
  loaded.api.dispose();
});

test("12д³: window.open бросил — счётчик отказов, клик не роняет страницу", async () => {
  const { loaded, nodes } = page();
  loaded.win.open = () => { throw new Error("denied"); };
  assert.equal(click(loaded, nodes.external), false);
  await settle();
  assert.deepEqual(ext(loaded).last, { host: "github.com", ok: false });
  assert.equal(ext(loaded).failed, 1);
  loaded.api.dispose();
});

test("12д³: наша ссылка — у 12д², адрес Claude и почта — у Claude", async () => {
  const { loaded, nodes } = page();
  assert.equal(click(loaded, nodes.task), false);
  await settle();
  assert.deepEqual(loaded.calls, [`http://127.0.0.1:47615/open-link?url=${encodeURIComponent(TASK)}`]);
  assert.deepEqual(loaded.opened, []);
  assert.equal(click(loaded, nodes.claude), true, "claude.ai — Claude");
  assert.equal(click(loaded, nodes.mail), true, "mailto — Claude");
  assert.deepEqual(loaded.opened, []);
  assert.equal(ext(loaded).clicks, 0);
  loaded.api.dispose();
});

test("12д³: модификатор, синтетический клик, правая кнопка, поле ввода, вне ленты — не трогаем; после dispose — тишина", () => {
  const { loaded, nodes } = page();
  for (const extra of [{ metaKey: true }, { ctrlKey: true }, { shiftKey: true }, { altKey: true }, { button: 1 }, { button: 2 }, { isTrusted: false }]) {
    assert.equal(click(loaded, nodes.external, extra), true, JSON.stringify(extra));
    assert.equal(loaded.document.dispatchEvent({ type: "pointerdown", isTrusted: true, target: nodes.external, button: 0, ...extra }),
      true, `pointerdown ${JSON.stringify(extra)}`);
  }
  assert.equal(click(loaded, nodes.typed), true, "поле ввода");
  assert.equal(click(loaded, nodes.outside), true, "вне ленты");
  assert.deepEqual(loaded.opened, []);
  assert.deepEqual(ext(loaded), { clicks: 0, repeats: 0, failed: 0, pimp: 0, last: null });
  assert.equal(loaded.inner.externalLinkAt(nodes.external).href, EXTERNAL);
  loaded.api.dispose();
  assert.equal(click(loaded, nodes.external), true);
  assert.deepEqual(loaded.opened, []);
});
