// WF107, батч Б2 (#8127, контракт К3): клик по файлу — сразу в PimpViewer.
//
// Рик 29.09: «Я … должен нажать и PimpViewer открыть». Клик по карточке файла
// (html/htm, png jpg jpeg gif webp), по ссылке на файл в тексте и по «на картинке»
// шлёт GET /open-html?mode=click&path=…&chat=…&frame=…&bg=… (рамка и фон — для
// запасного пути приложения: просмотр в окне чата). PDF — click без рамки, как было.
// Пока ответа нет (≤ 3 с) — карточка занята (data-myclaude-busy="file", блик и ⏳),
// повтор того же файла — ничего. fetch упал — мост Claude. Прежний `view` и 12л —
// пункт правого клика «👁 Посмотреть в окне чата».
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_bbbb-2222";
const HTML = "/Users/dev/Projects/PimpMyClaude/docs/16.html";
const PNG = "/Users/dev/Projects/Risovalka/out/hero.png";
const PDF = "/Users/dev/Projects/PimpMyClaude/docs/offer.pdf";
const FRAME = "&frame=-1512,-982,640,900&bg=1c1917";
const BUSY = "data-myclaude-busy";
const url = (path, mode = "click", tail = FRAME) =>
  `http://127.0.0.1:47615/open-html?mode=${mode}&path=${encodeURIComponent(path)}&chat=${CHAT}${tail}`;
const settle = () => new Promise(resolve => setImmediate(resolve));

const card = (parent, path, size = 4096) => {
  const button = parent.add("button", { attrs: { type: "button", title: path } });
  const name = path.split("/").pop();
  button.add("span", { text: name });
  button.__reactFiber$test = { memoizedProps: { children: [] }, return: { memoizedProps: { name, size, path }, return: null } };
  return button;
};

// fetchMode: "ok" — ответ сразу, "fail" — отказ (Пимп не запущен), "hang" — ответа нет.
const page = ({ fetchMode = "ok" } = {}) => {
  const nodes = {};
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`,
    geometry: { frame: [-1512, -982, 640, 900] },
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      const row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "3" } });
      nodes.html = card(row, HTML);
      nodes.png = card(row, PNG);
      nodes.pdf = card(row, PDF);
      const prose = row.add("div", { class: "prose" });
      nodes.mdPdf = prose.add("a", { attrs: { href: `file://${PDF}` }, text: "offer.pdf" });
      nodes.mdHtml = prose.add("a", { attrs: { href: HTML }, text: "16.html" });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.win.fetch = address => {
    loaded.calls.push(address);
    if (fetchMode === "fail") return Promise.reject(new Error("refused"));
    if (fetchMode === "hang") return new Promise(() => {});
    return Promise.resolve({});
  };
  loaded.reads = [];
  loaded.opened = [];
  loaded.win["claude.web"] = { LocalSessions: {
    readSessionImageAsDataUrl: (chat, path) => { loaded.reads.push([chat, path]); return Promise.resolve("data:image/png;base64,SU1H"); },
    openSessionFileInDefaultApp: (chat, path) => { loaded.opened.push([chat, path]); return Promise.resolve({ ok: true }); },
  } };
  loaded.document.body.computed = { backgroundColor: "rgb(28, 25, 23)" };
  return { loaded, nodes };
};
const click = (loaded, target) => loaded.document.dispatchEvent({ type: "click", isTrusted: true, target, button: 0, detail: 1 });
const chrome = loaded => plain(loaded.api.status().htmlChrome);
const clock = loaded => {
  loaded.run("globalThis.__shift = 0; (() => { const real = Date.now; Date.now = () => real() + globalThis.__shift; })();");
  return ms => loaded.run(`globalThis.__shift += ${Number(ms)};`);
};
// Меню Claude по правому клику с «Show in Finder» — как в busy-wf97.
const menuFor = (loaded, node) => {
  const menu = loaded.document.body.add("div", { attrs: { role: "menu", "data-cds": "ContextMenu" } });
  const list = menu.add("div");
  list.add("div", { attrs: { role: "separator" } });
  list.add("div", { attrs: { role: "menuitem" } }).add("span", { text: "Show in Finder" });
  assert.equal(loaded.inner.openChromeInsert(menu, loaded.inner.openChromePath(node)), true);
  return list;
};
const labels = list => [...list.children].map(node => node.textContent).filter(Boolean);

test("markdown-ссылка на локальный PDF и HTML в тексте — click в галерею, не Finder (PimpViewer 1.7)", async () => {
  const { loaded, nodes } = page();
  const passed = loaded.document.dispatchEvent({ type: "click", isTrusted: true, target: nodes.mdPdf, button: 0, detail: 1 });
  assert.equal(passed, false, "клик ушёл Claude — открылся бы Finder");
  await settle();
  loaded.document.dispatchEvent({ type: "click", isTrusted: true, target: nodes.mdHtml, button: 0, detail: 1 });
  await settle();
  assert.deepEqual(loaded.calls, [url(PDF, "click", ""), url(HTML)]);
});

test("нажатие на ссылку PDF глушится — меню Claude «Open in Files pane / Show in Finder» не открывается", () => {
  const { loaded, nodes } = page();
  for (const type of ["pointerdown", "mousedown"]) {
    const passed = loaded.document.dispatchEvent({ type, isTrusted: true, target: nodes.mdPdf, button: 0 });
    assert.equal(passed, false, `${type} дошёл до Claude`);
  }
  assert.deepEqual(loaded.calls, [], "нажатие само открыло файл — открывает клик");
});

test("синтетический клик по карточке (не человек) — файл не открывается (PimpViewer 1.6: «файлы открываются сами»)", async () => {
  const { loaded, nodes } = page();
  loaded.document.dispatchEvent({ type: "click", target: nodes.html.querySelector("span"), button: 0, detail: 1 });
  await settle();
  assert.deepEqual(loaded.calls, [], "синтетический клик ушёл в галерею");
  assert.equal(nodes.html.getAttribute(BUSY), null);
});

test("клик по html-карточке — click в PimpViewer с рамкой и фоном; Claude клика не видит", async () => {
  const { loaded, nodes } = page();
  const passed = click(loaded, nodes.html.querySelector("span"));
  assert.equal(passed, false, "клик ушёл Claude — открылась бы панель Browser");
  assert.equal(nodes.html.getAttribute(BUSY), "file", "пока ответа нет — карточка занята");
  await settle();
  assert.deepEqual(loaded.calls, [url(HTML)]);
  assert.equal(nodes.html.getAttribute(BUSY), "file", "ответ порта мгновенный — занятость ещё держится");
  loaded.win.dispatchEvent({ type: "blur" });
  assert.equal(nodes.html.getAttribute(BUSY), null, "окно ушло назад (галерея впереди) — занятость снята");
  const state = chrome(loaded);
  assert.deepEqual([state.clicks, state.views, state.last.mode, state.last.via], [1, 0, "click", "app"]);
});

test("фото-карточка — тоже click в PimpViewer, мостом не читаем, 12л не открываем", async () => {
  const { loaded, nodes } = page();
  click(loaded, nodes.png);
  await settle();
  await settle();
  assert.deepEqual(loaded.calls, [url(PNG)]);
  assert.deepEqual(loaded.reads, []);
  assert.equal(loaded.api.status().photo.open, false);
});

test("PDF — click без рамки и фона, как было", async () => {
  const { loaded, nodes } = page();
  click(loaded, nodes.pdf);
  await settle();
  assert.deepEqual(loaded.calls, [url(PDF, "click", "")]);
});

test("повтор того же файла, пока ждём, — ничего; через 3 с — снова", async () => {
  const { loaded, nodes } = page({ fetchMode: "hang" });
  const tick = clock(loaded);
  click(loaded, nodes.html);
  tick(400);
  click(loaded, nodes.html);
  assert.equal(loaded.calls.length, 1, "второй запрос за время ожидания");
  assert.equal(chrome(loaded).repeats, 1);
  assert.equal(nodes.html.getAttribute(BUSY), "file", "повтор занятость не снял");
  // Другой файл в это время — свой запрос.
  click(loaded, nodes.png);
  assert.equal(loaded.calls.length, 2);
  // Ответа нет 3 с — занятость снимается сама.
  loaded.dom.fireKind("timeout");
  assert.equal(nodes.html.getAttribute(BUSY), null);
  assert.equal(nodes.png.getAttribute(BUSY), null);
  tick(3200);
  click(loaded, nodes.html);
  assert.equal(loaded.calls.length, 3);
  assert.equal(nodes.html.getAttribute(BUSY), "file");
});

test("Пимп не запущен (fetch упал) — мост Claude, занятость снята", async () => {
  const { loaded, nodes } = page({ fetchMode: "fail" });
  click(loaded, nodes.html);
  await settle();
  await settle();
  assert.deepEqual(loaded.opened, [[CHAT, HTML]]);
  assert.deepEqual(chrome(loaded).last, { path: HTML, mode: "click", via: "bridge" });
  assert.equal(nodes.html.getAttribute(BUSY), null);
});

test("dispose снимает занятость и её таймер", () => {
  const { loaded, nodes } = page({ fetchMode: "hang" });
  click(loaded, nodes.html);
  assert.equal(nodes.html.getAttribute(BUSY), "file");
  loaded.api.dispose();
  assert.equal(nodes.html.getAttribute(BUSY), null);
  assert.equal(loaded.inner.fileClickState.busy.size, 0);
});

test("вид занятой карточки: блик и ⏳, без движения при «уменьшить движение»", () => {
  const { loaded } = page();
  const css = loaded.dom.queryAll("style").map(style => style.textContent).join("\n");
  assert.match(css, /button\[data-myclaude-busy="file"\]\{position:relative;cursor:progress\}/);
  assert.match(css, /button\[data-myclaude-busy="file"\]::after\{content:"⏳";[^}]*animation:myclaude-shim/);
  assert.match(css, /prefers-reduced-motion: reduce\)\{button\[data-myclaude-busy="file"\]::after\{animation:none/);
});

test("правый клик: у страницы — браузер, «Посмотреть в окне чата», копия; пункт шлёт view", async () => {
  const { loaded, nodes } = page();
  const list = menuFor(loaded, nodes.html);
  assert.deepEqual(labels(list).slice(0, 3), ["🌐 Открыть в браузере", "👁 Посмотреть в окне чата", "📋 Копировать в буфер"]);
  [...list.children].find(node => node.textContent === "👁 Посмотреть в окне чата").dispatchEvent({ type: "click" });
  await settle();
  assert.deepEqual(loaded.calls, [url(HTML, "view")]);
  assert.equal(chrome(loaded).views, 1);
});

test("правый клик по фото — «Посмотреть в окне чата» открывает просмотр 12л; у PDF пункта нет", async () => {
  const { loaded, nodes } = page();
  const list = menuFor(loaded, nodes.png);
  assert.deepEqual(labels(list).slice(0, 2), ["👁 Посмотреть в окне чата", "📋 Копировать в буфер"]);
  [...list.children].find(node => node.textContent === "👁 Посмотреть в окне чата").dispatchEvent({ type: "click" });
  await settle();
  await settle();
  assert.deepEqual(loaded.reads, [[CHAT, PNG]]);
  assert.equal(loaded.api.status().photo.open, true);
  assert.deepEqual(loaded.calls, [], "в приложение ничего не ушло");

  const other = page();
  const pdf = menuFor(other.loaded, other.nodes.pdf);
  assert.ok(!labels(pdf).includes("👁 Посмотреть в окне чата"));
});
