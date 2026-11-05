// WF288, #10891 и #10892, раздел 12д² inject.js: наши ссылки в чате — не в браузер Claude справа.
// Слово Элвиса 24.10.2026: ссылка отчёта https://vkusstatbot-production.up.railway.app/r/<токен> «должен был в левом
// окошке открыться» (решение 22.10, #10644); ссылка задачи Trelvis https://vlusnoff-production.up.railway.app/#t/<N> —
// «Нажимаю, ничего не происходит».
//
// Что проверяется:
//   1) классы OUR_LINK_CLASSES: отчёт, его картинка .png, задача Trelvis (#t/N, #task/N, trelvis://, kaban://);
//      чужие адреса, похожие хосты и адреса без корня проектов — не наши;
//   2) клик по отчёту — `/open-html?mode=click&path=<корень>VkusStatBot/reports/<токен>.html`, Claude клика не видит;
//      нажатие (pointerdown, mousedown) глушится;
//   3) задача — `/open-link?url=<адрес>`; opened:true — window.open не зовём;
//   4) запасной путь: 404, opened:false, отказ fetch — window.open(адрес) ровно раз;
//   5) ссылка с модификатором, синтетический клик, ссылка в поле ввода, чужая ссылка — не трогаем;
//   6) status().ourLinks.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_a6b6fb8a-03e0-45a5-af2e-30d1d800bd1e";
const ROOT = "/Users/dev/Projects/";
const REPORT = "https://vkusstatbot-production.up.railway.app/r/tP77pRg5";
const PICTURE = "https://vkusstatbot-production.up.railway.app/r/tP77pRg5.png";
const TASK = "https://vlusnoff-production.up.railway.app/#t/10850";
const settle = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };
const reply = (status, body = null) => ({ ok: status >= 200 && status < 300, status,
  json: async () => { if (body === null) throw new SyntaxError("empty"); return body; } });

const page = ({ root = ROOT, answer = () => reply(204) } = {}) => {
  const nodes = {};
  const local = { "myclaude-auto-allow-roam": "off" };
  if (root) local["myclaude-trust-root-v1"] = root;
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`,
    storage: { local },
    geometry: { frame: [-1512, -982, 640, 900] },
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      const row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "3" } });
      const prose = row.add("div", { attrs: { class: "prose" } });
      nodes.report = prose.add("a", { attrs: { href: REPORT, target: "_blank" }, text: "отчёт" });
      nodes.picture = prose.add("a", { attrs: { href: PICTURE }, text: "картинка" });
      nodes.task = prose.add("a", { attrs: { href: TASK }, text: "#10850" });
      nodes.other = prose.add("a", { attrs: { href: "https://example.com/r/tP77pRg5" }, text: "чужая" });
      const box = dom.document.body.add("div", { attrs: { contenteditable: "true" } });
      const quote = box.add("div", { attrs: { class: "prose" } });
      nodes.typed = quote.add("a", { attrs: { href: TASK }, text: "в поле ввода" });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.box = { answer };
  loaded.win.fetch = address => {
    const url = String(address);
    loaded.calls.push(url);
    return Promise.resolve().then(() => loaded.box.answer(url));
  };
  loaded.opened = [];
  loaded.win.open = (url, target) => { loaded.opened.push([url, target]); return null; };
  return { loaded, nodes };
};
const click = (loaded, target, extra = {}) =>
  loaded.document.dispatchEvent({ type: "click", isTrusted: true, target, button: 0, detail: 1, ...extra });
const links = loaded => plain(loaded.api.status().ourLinks);

test("12д²: классы ссылок — отчёт, картинка, задача Trelvis; чужие и похожие — не наши", () => {
  const { loaded } = page();
  const match = href => plain(loaded.inner.ourLinkMatch(href));
  assert.deepEqual(match(REPORT), { kind: "report", href: REPORT, path: `${ROOT}VkusStatBot/reports/tP77pRg5.html` });
  assert.deepEqual(match(`${REPORT}/?utm=tg#top`).path, `${ROOT}VkusStatBot/reports/tP77pRg5.html`);
  assert.deepEqual(match(PICTURE), { kind: "picture", href: PICTURE, path: `${ROOT}VkusStatBot/reports/tP77pRg5.png` });
  assert.deepEqual(match(TASK), { kind: "task", href: TASK, task: 10850 });
  assert.deepEqual(match("https://vlusnoff-production.up.railway.app#task/7"),
    { kind: "task", href: "https://vlusnoff-production.up.railway.app/#task/7", task: 7 }, "адрес приводится к виду URL");
  assert.equal(match("trelvis://task/12").task, 12);
  assert.equal(match("kaban://task/12").task, 12);
  for (const href of [
    "https://example.com/r/tP77pRg5", "https://vkusstatbot-production.up.railway.app.evil.test/r/tP77pRg5",
    "http://vkusstatbot-production.up.railway.app/r/tP77pRg5", "https://vkusstatbot-production.up.railway.app/r/short",
    "https://vkusstatbot-production.up.railway.app/r/tP77pRg5.html", "https://vkusstatbot-production.up.railway.app/version",
    "https://vlusnoff-production.up.railway.app/#t/0", "https://vlusnoff-production.up.railway.app/#tasks/1-3",
    "https://vlusnoff-production.up.railway.app/x#t/5", "trelvis://card/5", "/Users/dev/a.html", "", null,
  ]) assert.equal(loaded.inner.ourLinkMatch(href), null, String(href));
  assert.equal(loaded.inner.OUR_LINK_CLASSES.length, 4);
  loaded.api.dispose();
});

test("12д²: корня проектов нет — ссылки отчётов не наши, задачи — наши", () => {
  const { loaded } = page({ root: null });
  assert.equal(loaded.inner.ourLinkMatch(REPORT), null);
  assert.equal(loaded.inner.ourLinkMatch(TASK).task, 10850);
  loaded.api.dispose();
});

test("12д²: клик по отчёту — файл с диска тем же путём, что клик по файлу; Claude клика не видит", async () => {
  const { loaded, nodes } = page();
  for (const type of ["pointerdown", "mousedown"]) {
    assert.equal(loaded.document.dispatchEvent({ type, isTrusted: true, target: nodes.report, button: 0 }), false, type);
  }
  assert.deepEqual(loaded.calls, [], "нажатие само ничего не открывает");
  assert.equal(click(loaded, nodes.report), false, "клик ушёл Claude — открылся бы браузер справа");
  await settle();
  assert.equal(loaded.calls.length, 1);
  assert.ok(loaded.calls[0].startsWith(`http://127.0.0.1:47615/open-html?mode=click&path=${encodeURIComponent(`${ROOT}VkusStatBot/reports/tP77pRg5.html`)}&chat=${CHAT}`),
    loaded.calls[0]);
  assert.deepEqual(loaded.opened, [], "Пимп ответил 204 — открыл сам");
  assert.deepEqual(links(loaded), { clicks: 1, fallbacks: 0, repeats: 0, last: { kind: "report", via: "pimp" } });
  // Двойной клик — один запрос.
  click(loaded, nodes.report);
  await settle();
  assert.equal(loaded.calls.length, 1);
  assert.equal(links(loaded).repeats, 1);
  loaded.api.dispose();
});

test("12д²: файла нет (404) или Пимпа нет — запасной путь window.open, клик не пропадает", async () => {
  const { loaded, nodes } = page({ answer: () => reply(404, { taken: false, opened: false }) });
  click(loaded, nodes.picture);
  await settle();
  assert.ok(loaded.calls[0].includes(encodeURIComponent(`${ROOT}VkusStatBot/reports/tP77pRg5.png`)), loaded.calls[0]);
  assert.deepEqual(loaded.opened, [[PICTURE, "_blank"]]);
  assert.deepEqual(links(loaded).last, { kind: "picture", via: "claude", why: "http 404" });
  loaded.win.fetch = address => { loaded.calls.push(String(address)); return Promise.reject(new TypeError("Failed to fetch")); };
  click(loaded, nodes.report);
  await settle();
  assert.deepEqual(loaded.opened, [[PICTURE, "_blank"], [REPORT, "_blank"]], "мост Claude не зовём — адрес как был");
  assert.deepEqual(links(loaded).last, { kind: "report", via: "claude", why: "no-reply" });
  loaded.api.dispose();
});

test("12д²: задача Trelvis — /open-link; opened:true — всё, opened:false, 404 и отказ — window.open", async () => {
  const { loaded, nodes } = page({ answer: () => reply(200, { opened: true, via: "trelvis" }) });
  assert.equal(click(loaded, nodes.task), false);
  await settle();
  assert.deepEqual(loaded.calls, [`http://127.0.0.1:47615/open-link?url=${encodeURIComponent(TASK)}`]);
  assert.deepEqual(loaded.opened, []);
  assert.deepEqual(links(loaded).last, { kind: "task", via: "pimp" });
  const cases = [
    [() => reply(400, { opened: false }), "http 400"],
    [() => reply(404), "http 404"],
    [() => reply(200, { opened: false }), "http 200"],
    [() => { throw new TypeError("Failed to fetch"); }, "no-reply"],
  ];
  for (const [answer, why] of cases) {
    loaded.inner.ourLinksState.at = 0;
    loaded.box.answer = answer;
    click(loaded, nodes.task);
    await settle();
    assert.deepEqual(loaded.opened.at(-1), [TASK, "_blank"], why);
    assert.equal(links(loaded).last.why, why);
  }
  assert.equal(loaded.opened.length, cases.length);
  assert.equal(links(loaded).fallbacks, cases.length);
  loaded.api.dispose();
});

test("12д²: модификатор, синтетический клик, правая кнопка, поле ввода, чужая ссылка — не трогаем", async () => {
  const { loaded, nodes } = page();
  for (const extra of [{ metaKey: true }, { ctrlKey: true }, { shiftKey: true }, { altKey: true }, { button: 1 }, { isTrusted: false }]) {
    assert.equal(click(loaded, nodes.task, extra), true, JSON.stringify(extra));
    assert.equal(loaded.document.dispatchEvent({ type: "pointerdown", isTrusted: true, target: nodes.task, button: 0, ...extra }),
      true, `pointerdown ${JSON.stringify(extra)}`);
  }
  assert.equal(click(loaded, nodes.typed), true, "ссылка в поле ввода — не лента");
  // С #11118 чужой http(s)-адрес ленты берёт раздел 12д³ (с #11323 — Пимп kind=web, отказ — браузер системы),
  // 12д² его по-прежнему не трогает.
  loaded.box.answer = () => ({ ok: false, status: 400 });
  assert.equal(click(loaded, nodes.other), false, "чужой адрес — 12д³");
  await settle();
  assert.deepEqual(loaded.calls, [`http://127.0.0.1:47615/open-link?kind=web&url=${encodeURIComponent("https://example.com/r/tP77pRg5")}`]);
  assert.deepEqual(loaded.opened, [["https://example.com/r/tP77pRg5", "_blank"]]);
  assert.deepEqual(links(loaded), { clicks: 0, fallbacks: 0, repeats: 0, last: null });
  assert.equal(loaded.inner.ourLinkAt(nodes.report).kind, "report");
  loaded.api.dispose();
  // После dispose слушателей нет.
  assert.equal(click(loaded, nodes.report), true);
  assert.equal(typeof loaded.inner.onOurLinkClick, "function");
  assert.equal(typeof loaded.inner.onOurLinkPress, "function");
});
