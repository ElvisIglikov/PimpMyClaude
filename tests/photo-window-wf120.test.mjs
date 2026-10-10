// WF120, батч B-P1b (#7689): правый клик по фото-карточке — «🖼 Открыть в новом окне».
//
// Пункт встаёт в меню Claude (раздел 12г) только у фото (png jpg jpeg gif webp) и шлёт
// тот же запрос, что клик по карточке (fileClick, К3): GET /open-html?mode=click с
// рамкой и фоном — PimpViewer с листанием, без него приложение откроет «Просмотр».
// Меню закрывает ровно один Escape: по ответу приложения или (Пимп не запущен) мостом
// Claude. Повтор того же файла за 3 с — ничего. Вставленные скриншоты без пути — без
// пункта (меню на них не трогаем).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_cccc-3333";
const PNG = "/Users/dev/Projects/Risovalka/out/hero.png";
const JPG = "/Users/dev/Desktop/Снимок экрана.jpg";
const HTML = "/Users/dev/Projects/PimpMyClaude/docs/16.html";
const PDF = "/Users/dev/Projects/PimpMyClaude/docs/offer.pdf";
const LABEL = "🖼 Открыть в новом окне";
const ATTRIBUTE = "data-myclaude-open-chrome";
const FRAME = "&frame=-1512,-982,640,900&bg=1c1917";
const url = path => `http://127.0.0.1:47615/open-html?mode=click&path=${encodeURIComponent(path)}&chat=${CHAT}${FRAME}`;
const settle = () => new Promise(resolve => setImmediate(resolve));

const card = (parent, path) => {
  const button = parent.add("button", { attrs: { type: "button", title: path } });
  const name = path.split("/").pop();
  button.add("span", { text: name });
  button.__reactFiber$test = { memoizedProps: { children: [] }, return: { memoizedProps: { name, size: 4096, path }, return: null } };
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
      for (const [key, path] of Object.entries({ png: PNG, jpg: JPG, html: HTML, pdf: PDF })) nodes[key] = card(row, path);
      // Вставленный скриншот: <img data:> в плитке, пути нет.
      const tile = row.add("span", { attrs: { role: "button" } });
      nodes.pasted = tile.add("img", { attrs: { src: "data:image/png;base64,UEFTVEU=" } });
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
  loaded.opened = [];
  loaded.win["claude.web"] = { LocalSessions: {
    readSessionImageAsDataUrl: () => Promise.resolve("data:image/png;base64,SU1H"),
    openSessionFileInDefaultApp: (chat, path) => { loaded.opened.push([chat, path]); return Promise.resolve({ ok: true }); },
  } };
  loaded.document.body.computed = { backgroundColor: "rgb(28, 25, 23)" };
  loaded.escapes = [];
  loaded.document.addEventListener("keydown", event => loaded.escapes.push(event.key));
  return { loaded, nodes };
};
// Меню Claude по правому клику с «Show in Finder» — как в file-click-wf107.
const menuFor = (loaded, node) => {
  const menu = loaded.document.body.add("div", { attrs: { role: "menu", "data-cds": "ContextMenu" } });
  const list = menu.add("div");
  list.add("div", { attrs: { role: "separator" } });
  list.add("div", { attrs: { role: "menuitem" } }).add("span", { text: "Show in Finder" });
  assert.equal(loaded.inner.openChromeInsert(menu, loaded.inner.openChromePath(node)), true);
  return list;
};
const ours = list => [...list.children].filter(node => node.hasAttribute(ATTRIBUTE)).map(node => node.textContent);
const item = list => [...list.children].find(node => node.textContent === LABEL);
const press = list => item(list).dispatchEvent({ type: "click" });
const clock = loaded => {
  loaded.run("globalThis.__shift = 0; (() => { const real = Date.now; Date.now = () => real() + globalThis.__shift; })();");
  return ms => loaded.run(`globalThis.__shift += ${Number(ms)};`);
};

test("пункт есть у фото (png, jpg) и только у них: у html и pdf его нет", () => {
  const { loaded, nodes } = page();
  assert.deepEqual(ours(menuFor(loaded, nodes.png)), ["👁 Посмотреть в окне чата", "📋 Копировать в буфер", LABEL, ""]);
  assert.deepEqual(ours(menuFor(loaded, nodes.jpg)), ["👁 Посмотреть в окне чата", "📋 Копировать в буфер", LABEL, ""]);
  assert.deepEqual(ours(menuFor(loaded, nodes.html)), ["🌐 Открыть в браузере", "👁 Посмотреть в окне чата", "📋 Копировать в буфер", ""]);
  assert.deepEqual(ours(menuFor(loaded, nodes.pdf)), ["📋 Копировать в буфер", ""]);
});

test("jpeg, gif, webp и заглавное расширение — тоже фото; heic — нет", () => {
  const { loaded } = page();
  const labels = path => {
    const menu = loaded.document.body.add("div", { attrs: { role: "menu", "data-cds": "ContextMenu" } });
    const list = menu.add("div");
    list.add("div", { attrs: { role: "menuitem" } }).add("span", { text: "Show in Finder" });
    loaded.inner.openChromeInsert(menu, { path, name: path.split("/").pop(), page: false });
    return ours(list);
  };
  for (const ext of ["jpeg", "gif", "webp", "PNG"]) assert.ok(labels(`/tmp/a.${ext}`).includes(LABEL), `.${ext}: пункта нет`);
  assert.ok(!labels("/tmp/a.heic").includes(LABEL), ".heic — не фото 12л/Viewer, пункта нет");
});

test("клик — тот же click, что у карточки (рамка и фон), 12л не открывается; меню закрыто одним Escape", async () => {
  const { loaded, nodes } = page();
  // Эталон — клик по самой карточке в другом окне.
  const ref = page();
  ref.loaded.document.dispatchEvent({ type: "click", isTrusted: true, target: ref.nodes.png, button: 0, detail: 1 });
  await settle();

  press(menuFor(loaded, nodes.png));
  assert.deepEqual(loaded.escapes, [], "Escape до ответа приложения — меню закрыто раньше времени");
  await settle();
  assert.deepEqual(loaded.calls, [url(PNG)]);
  assert.deepEqual(loaded.calls, ref.loaded.calls, "запрос не тот, что у клика по карточке");
  assert.deepEqual(loaded.escapes, ["Escape"], "меню закрывает ровно один Escape");
  assert.deepEqual(loaded.opened, [], "мост не зовём — открыло приложение");
  assert.equal(loaded.api.status().photo.open, false, "это не просмотр в окне чата");
  assert.deepEqual(plain(loaded.api.status().htmlChrome.last), { path: PNG, mode: "click", via: "app" });
});

test("двойной клик и повтор того же файла за 3 с — ничего; через 3 с — снова", async () => {
  const { loaded, nodes } = page();
  const tick = clock(loaded);
  const list = menuFor(loaded, nodes.png);
  press(list);
  press(list);
  await settle();
  assert.equal(loaded.calls.length, 1, "двойной клик — два запроса");
  assert.deepEqual(loaded.escapes, ["Escape"], "лишний Escape оборвал бы ответ Claude");

  tick(1500);
  press(menuFor(loaded, nodes.png));
  await settle();
  assert.equal(loaded.calls.length, 1, "повтор за 3 с ушёл в приложение");
  assert.deepEqual(loaded.escapes, ["Escape"], "на повторе Escape не шлём — меню закроет Esc Элвиса");

  // Другой файл в это время — свой запрос.
  press(menuFor(loaded, nodes.jpg));
  await settle();
  assert.equal(loaded.calls.length, 2);

  tick(2000);
  press(menuFor(loaded, nodes.png));
  await settle();
  assert.equal(loaded.calls.length, 3, "через 3 с — снова");
});

test("клик по карточке и сразу пункт меню того же фото — одно окно", async () => {
  const { loaded, nodes } = page();
  loaded.document.dispatchEvent({ type: "click", isTrusted: true, target: nodes.png, button: 0, detail: 1 });
  press(menuFor(loaded, nodes.png));
  await settle();
  assert.equal(loaded.calls.length, 1);
});

test("Пимп не запущен (fetch упал) — мост Claude открывает файл; Escape — один", async () => {
  const { loaded, nodes } = page({ fetchMode: "fail" });
  press(menuFor(loaded, nodes.png));
  await settle();
  await settle();
  assert.deepEqual(loaded.opened, [[CHAT, PNG]]);
  assert.deepEqual(loaded.escapes, ["Escape"]);
  assert.deepEqual(plain(loaded.api.status().htmlChrome.last), { path: PNG, mode: "click", via: "bridge" });
});

test("приложение молчит — меню не закрываем сами (закроет ответ или Esc), второго запроса нет", async () => {
  const { loaded, nodes } = page({ fetchMode: "hang" });
  const list = menuFor(loaded, nodes.png);
  press(list);
  await settle();
  press(list);
  assert.deepEqual(loaded.escapes, []);
  assert.equal(loaded.calls.length, 1);
});

test("вставленный скриншот без пути — меню Claude не трогаем", () => {
  const { loaded, nodes } = page();
  const observers = loaded.counters.observers;
  loaded.document.dispatchEvent({ type: "contextmenu", target: nodes.pasted });
  assert.equal(plain(loaded.api.status().openInChrome).pending, false);
  assert.equal(loaded.counters.observers, observers, "наблюдатель за меню встал без файла");
});

test("dispose снимает пункт из меню", () => {
  const { loaded, nodes } = page();
  const list = menuFor(loaded, nodes.png);
  assert.ok(item(list));
  loaded.api.dispose();
  assert.equal(item(list), undefined);
  assert.equal(ours(list).length, 0);
});
