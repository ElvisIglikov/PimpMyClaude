// #10617 (страница, раздел 12с³, page/546-wait-files.js): в разделе «Ждёт тебя» название пункта, у которого есть файл,
// — ссылка. Слово Элвиса 22.10: «баннер-пицца должна быть ссылка, чтоб я на неё нажимаю, и баннер пицца открывался»;
// ответ 31.10 04:00 (файл 204, 3.3 ★А): «пункт — ссылкой на файл да, кнопку-слово нет».
//
// Что проверяется:
//   1) пункт-свёртка с файлом в теле — вещь подписи ссылкой (свои узлы без текста), клик — путь открытия файла
//      (fileClick → /open-html?mode=click&path=…), свёртка при этом не переключается; клик по началу подписи —
//      свернуть/развернуть, как было;
//   2) пункт списка с путём в `коде` — его жирное название ссылкой (метка на родном strong), фраза 12с² — не ссылка;
//   3) пункт без файла — как был; кнопок-слов нет; dispose снимает своё.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_wait-10617";
const HEAD = "data-myclaude-fold-head";
const MARK = "data-myclaude-wait-file";
const PART = "data-myclaude-wait-file-part";
const TEXT = "data-myclaude-wait-file-text";
const REST = "data-myclaude-wait-file-rest";
const SALE = "/Users/demo/Rick/work/sale-01-11.html";
const BANNER = "/Users/demo/Rick/out/banner-pizza.png";

const answer = box => {
  const n = {};
  n.wait = box.add("h2", { text: "❗ Ждёт тебя 3" });
  n.sOpen = box.add("p", { text: "<details>" });
  n.sSum = box.add("p", { text: "<summary><b>17 · 🔴 Распродажа 01.11 — «да» на цену</b></summary>" });
  n.sBody = box.add("p", { text: "Цена 3 290 ₸, страница: " });
  n.sLink = n.sBody.add("a", { attrs: { href: SALE }, text: "распродажа" });
  n.sClose = box.add("p", { text: "</details>" });
  n.oOpen = box.add("p", { text: "<details>" });
  n.oSum = box.add("p", { text: "<summary><b>18 · Оля — «да» на отпуск</b></summary>" });
  n.oBody = box.add("p", { text: "Оля просит неделю с 3.11, файла нет." });
  n.oClose = box.add("p", { text: "</details>" });
  const list = box.add("ul");
  const one = list.add("li");
  n.banner = one.add("strong", { text: "Баннер пиццы" });
  one.add("span", { text: " — " });
  one.add("code", { text: BANNER });
  one.add("span", { text: ", скажи " });
  n.phrase = one.add("strong", { text: "«да баннеру»" });
  const two = list.add("li");
  n.ola = two.add("strong", { text: "Отпуск Оли" });
  two.add("span", { text: " — скажи " });
  n.olaPhrase = two.add("strong", { text: "«да Оле»" });
  box.add("h3", { text: "Дальше делаю я" });
  const after = box.add("ul").add("li");
  n.after = after.add("strong", { text: "Не отсюда" });
  after.add("code", { text: BANNER });
  return n;
};

const page = () => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({ text: "" });
      const panel = dom.document.body.add("div", { attrs: { class: "epitaxy-chat-panel" } });
      const feed = panel.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      const row = feed.add("div", {
        attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" },
        rect: { left: 0, top: 0, width: 800, height: 300 },
      });
      parts.n = answer(row.add("div", { attrs: { class: "prose" } }));
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.win.fetch = address => { loaded.calls.push(String(address)); return Promise.resolve({ ok: true }); };
  const paint = () => { loaded.inner.foldTick(); loaded.inner.waitFilePaint(); };
  paint();
  const click = (node, extra = {}) => loaded.dom.document.dispatchEvent({ type: "click", target: node, button: 0, detail: 1, isTrusted: true, ...extra });
  return { loaded, n: loaded.parts.n, click, paint };
};
const headOf = (loaded, raw) => loaded.dom.queryAll(`[${HEAD}]`).find(head => head.nextElementSibling === raw);
const opens = loaded => loaded.calls.filter(item => item.includes("/open-html?"));
const status = loaded => plain(loaded.api.status().waitFiles);

test("#10617: пункт-свёртка с файлом — вещь подписи ссылкой; клик открывает файл, свёртка не переключается", () => {
  const { loaded, n, click, paint } = page();
  const head = headOf(loaded, n.sOpen);
  assert.ok(head, "голова свёртки стоит");
  const [pre, link] = head.children;
  assert.equal(pre.getAttribute(PART), "pre");
  assert.equal(pre.getAttribute(TEXT), "17 · 🔴 ");
  assert.equal(link.getAttribute(MARK), "fold");
  assert.equal(link.getAttribute(TEXT), "Распродажа 01.11");
  assert.equal(head.getAttribute(REST), " — «да» на цену");
  assert.equal(head.textContent, "", "подпись — из атрибутов: копия и ключи свёрток текста не видят");
  click(link);
  assert.equal(opens(loaded).length, 1);
  assert.match(opens(loaded)[0], new RegExp(`^http://127\\.0\\.0\\.1:47615/open-html\\?mode=click&path=${encodeURIComponent(SALE).replace(/[.]/g, "\\.")}&chat=${CHAT}`));
  assert.equal(head.getAttribute(HEAD), "closed", "свёртка не переключилась");
  click(pre);
  assert.equal(head.getAttribute(HEAD), "open", "начало подписи — свернуть/развернуть, как было");
  paint();
  assert.equal(head.children[1], link, "узлы головы те же после прохода");
  assert.deepEqual(status(loaded), { count: 2, clicks: 1, last: SALE });
  loaded.api.dispose();
  assert.equal(head.children?.length ?? 0, 0);
});

test("#10617: пункт списка с путём — жирное название ссылкой, фраза — не ссылка; без файла — как был", () => {
  const { loaded, n, click } = page();
  assert.equal(n.banner.getAttribute(MARK), "name");
  assert.equal(n.banner.textContent, "Баннер пиццы", "текст React не тронут");
  for (const node of [n.phrase, n.ola, n.olaPhrase, n.after]) assert.equal(node.hasAttribute(MARK), false);
  const ola = headOf(loaded, n.oOpen);
  assert.equal(ola.children.length, 0, "свёртка без файла — как была");
  assert.equal(ola.hasAttribute(REST), false);
  click(n.banner);
  assert.equal(opens(loaded).length, 1);
  assert.ok(opens(loaded)[0].includes(`mode=click&path=${encodeURIComponent(BANNER)}`));
  click(n.banner, { detail: 2 });
  assert.equal(opens(loaded).length, 1, "второй щелчок двойного — мимо");
  click(n.ola);
  assert.equal(opens(loaded).length, 1, "без файла — не ссылка");
  assert.equal(loaded.dom.queryAll("[data-myclaude-nazh-button],[data-myclaude-nazh-box],[data-myclaude-say-button]").length, 0, "кнопок-слов нет");
  const css = loaded.dom.queryAll("style").map(node => node.textContent).join("\n");
  assert.match(css, /\[data-myclaude-wait-file\]\{color:var\(--cds-text-accent/);
  loaded.api.dispose();
  assert.equal(n.banner.hasAttribute(MARK), false, "dispose снимает метки");
});

test("#10617: разбор подписи свёртки", () => {
  const { loaded } = page();
  const { waitFileSplit } = loaded.inner;
  assert.deepEqual(plain(waitFileSplit("3 · 🆕 · Баннер пиццы — скажи «да»")), { pre: "3 · 🆕 · ", name: "Баннер пиццы", rest: " — скажи «да»" });
  assert.deepEqual(plain(waitFileSplit("Баннер пиццы")), { pre: "", name: "Баннер пиццы", rest: "" });
  loaded.api.dispose();
});
