// WF103, батч P1 (раздел 12д¹ inject.js; #7939, #7860): файл — в окне чата.
//
// Контракт волны 1 (план WF103):
//   GET /open-html?mode=view&path=<enc>&chat=<local_…>[&frame=x,y,w,h][&bg=rrggbb]
//   — порядок ключей mode, path, chat, frame, bg; x,y со знаком, w,h > 0; мусор —
//   ключа нет. Повтор view того же пути — не чаще раза в секунду; fetch упал —
//   мост Claude (openSessionFileInDefaultApp), как у click.
// Фото-карточка (png jpg jpeg gif webp) — чтение мостом (ddReadUrl, кэш ddState)
// и просмотр 12л с этим фото первым; больше DD_MAX_BYTES или не прочиталось —
// прежний click. Ссылка на файл в тексте ответа (span.prose-link с fileRef) —
// как карточка; «на картинке — …» — открывает ближайшую карточку выше.
// С WF107 (#8127, К3) клик по файлу — `click` в PimpViewer (file-click-wf107),
// а `view` и 12л — пункт правого клика «👁 Посмотреть в окне чата» и viewFile().
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";

const CHAT = "local_aaaa-1111";
const HTML = "/Users/dev/Projects/Marketolog/docs/1.html";
const PNG = "/Users/dev/Projects/Risovalka/out/hero-feed-ru.webp";
const CWD = "/Users/dev/Projects/PimpViewer";

const settle = () => new Promise(resolve => setImmediate(resolve));

// Карточка SendUserFile по разведке 27.09: button[title=<путь>], пропсы
// {name, size, path} у компонента шагом выше.
const card = (parent, path, size = 102810) => {
  const button = parent.add("button", { attrs: { type: "button", title: path } });
  const name = path.split("/").pop();
  button.add("span", { text: name });
  button.__reactFiber$test = { memoizedProps: { children: [] }, return: { memoizedProps: { name, size, path, href: undefined }, return: null } };
  return button;
};
// Ссылка на файл в тексте ответа: span[role=button].prose-link, fileRef двумя шагами выше.
const link = (dom, parent, text, path) => {
  const span = dom.leaf(parent, "span", text, { class: "inline-block prose-link", attrs: { role: "button", tabindex: "0" } });
  span.__reactFiber$test = { memoizedProps: { role: "button" }, return: { memoizedProps: { trigger: {} }, return: { memoizedProps: { fileRef: { path } }, return: null } } };
  return span;
};

const page = ({ bridge = true, image = "data:image/webp;base64,SU1H", frame = [-1512, -982, 640, 900], build = null, fetchFails = false } = {}) => {
  const nodes = {};
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`,
    geometry: { frame },
    html: dom => {
      const parts = dom.composer({});
      // Список слева: строка чата с сессией (cwd — папка чата).
      const side = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
      const row = side.add("div", { attrs: { "data-row-key": `code:${CHAT}` } });
      row.__reactFiber$test = { memoizedProps: { session: { ref: { id: CHAT }, source: { data: { cwd: CWD } } } }, return: null };
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      nodes.feed = feed;
      nodes.tools = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "13" } });
      nodes.html = card(nodes.tools, HTML, 17715);
      nodes.png = card(nodes.tools, PNG);
      build?.(dom, feed, nodes);
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.win.fetch = url => { loaded.calls.push(url); return fetchFails ? Promise.reject(new Error("refused")) : Promise.resolve({}); };
  loaded.reads = [];
  loaded.opened = [];
  if (bridge) {
    const sessions = {
      readSessionImageAsDataUrl: (chat, path) => { loaded.reads.push([chat, path]); return Promise.resolve(typeof image === "function" ? image(path) : image); },
      openSessionFileInDefaultApp: (chat, path) => { loaded.opened.push([chat, path]); return Promise.resolve({ ok: true }); },
    };
    loaded.win["claude.web"] = { LocalSessions: sessions };
  }
  loaded.body = loaded.document.body;
  loaded.body.computed = { backgroundColor: "rgb(28, 25, 23)" };
  return { loaded, nodes };
};
const click = (loaded, target, extra = {}) => loaded.document.dispatchEvent({ type: "click", isTrusted: true, target, button: 0, detail: 1, ...extra });
const status = loaded => plain(loaded.api.status());
// Часы страницы: Date.now в песочнице двигаем сами.
const clock = loaded => {
  loaded.run("globalThis.__shift = 0; (() => { const real = Date.now; Date.now = () => real() + globalThis.__shift; })();");
  return ms => loaded.run(`globalThis.__shift += ${Number(ms)};`);
};

test("адрес view: порядок ключей, frame со знаком, frame/bg с мусором — ключа нет", () => {
  const { htmlChromeUrl } = loadInner().inner;
  const base = "http://127.0.0.1:47615/open-html?mode=view&path=%2Ftmp%2Fa%20b%2F1.html";
  assert.equal(htmlChromeUrl("/tmp/a b/1.html", "view", CHAT, [-1512, -982, 640, 900], "#1C1917"),
    `${base}&chat=${CHAT}&frame=-1512,-982,640,900&bg=1c1917`);
  assert.equal(htmlChromeUrl("/tmp/a b/1.html", "view", CHAT, [10, 20, 0, 900], "1c1917"), `${base}&chat=${CHAT}&bg=1c1917`, "w = 0 — рамки нет");
  assert.equal(htmlChromeUrl("/tmp/a b/1.html", "view", CHAT, [1.5, 2, 3, 4], "red"), `${base}&chat=${CHAT}`, "дробь и не-hex — ключей нет");
  assert.equal(htmlChromeUrl("/tmp/a b/1.html", "view", CHAT, "1,2,3,4", "#12345"), `${base}&chat=${CHAT}`);
  assert.equal(htmlChromeUrl("/tmp/a b/1.html", "view", null), base, "без чата, рамки и фона — только mode и path");
  assert.equal(htmlChromeUrl("/tmp/a b/1.html", "view", null, [0, 0, 800, 600]), `${base}&frame=0,0,800,600`);
  // Прежние вызовы (click/auto) не меняются.
  assert.equal(htmlChromeUrl("/tmp/x.png", "auto", null), "http://127.0.0.1:47615/open-html?mode=auto&path=%2Ftmp%2Fx.png");
});

test("просмотр html — view с рамкой окна и фоном темы", async () => {
  const { loaded } = page();
  loaded.api.viewFile(HTML);
  await settle();
  assert.deepEqual(loaded.calls, [`http://127.0.0.1:47615/open-html?mode=view&path=${encodeURIComponent(HTML)}&chat=${CHAT}&frame=-1512,-982,640,900&bg=1c1917`]);
  const chrome = status(loaded).htmlChrome;
  assert.deepEqual([chrome.views, chrome.clicks, chrome.last.mode, chrome.last.via], [1, 0, "view", "app"]);
});

test("два view за 300 мс — один запрос, через 1,2 с — второй", async () => {
  const { loaded } = page();
  const tick = clock(loaded);
  loaded.api.viewFile(HTML);
  tick(300);
  loaded.api.viewFile(HTML);
  await settle();
  assert.equal(loaded.calls.length, 1);
  assert.equal(status(loaded).htmlChrome.repeats, 1);
  tick(1200);
  loaded.api.viewFile(HTML);
  await settle();
  assert.equal(loaded.calls.length, 2);
  assert.equal(status(loaded).htmlChrome.views, 2);
});

test("fetch упал (Пимп не запущен) — прежний запасной путь моста", async () => {
  const { loaded } = page({ fetchFails: true });
  loaded.api.viewFile(HTML);
  await settle();
  await settle();
  assert.deepEqual(loaded.opened, [[CHAT, HTML]]);
  assert.deepEqual(plain(status(loaded).htmlChrome.last), { path: HTML, mode: "view", via: "bridge" });
});

test("просмотр фото — прочитано мостом, 12л с ним первым; повтор во время чтения пустой", async () => {
  const { loaded, nodes } = page();
  const view = () => loaded.inner.viewOpen(PNG, nodes.png);
  view();
  view();
  assert.equal(loaded.inner.viewState.skips, 1, "второй вызов во время чтения — ничего");
  await settle();
  await settle();
  assert.deepEqual(loaded.reads, [[CHAT, PNG]]);
  const photo = status(loaded).photo;
  assert.deepEqual([photo.open, photo.index, photo.from], [true, 0, "card"]);
  assert.equal(loaded.inner.photoState.list[0].src, "data:image/webp;base64,SU1H");
  assert.equal(loaded.calls.length, 0, "в приложение ничего не ушло");
  // Второй раз — из кэша, сразу.
  loaded.api.viewer.close();
  view();
  assert.equal(status(loaded).photo.open, true);
  assert.equal(loaded.reads.length, 1);
});

test("просмотр фото больше DD_MAX_BYTES и нечитаемого — прежний click", async () => {
  const big = page();
  const huge = card(big.nodes.tools, "/tmp/huge.png", 30 * 1024 * 1024);
  big.loaded.inner.viewOpen("/tmp/huge.png", huge);
  await settle();
  assert.equal(big.loaded.reads.length, 0);
  assert.match(big.loaded.calls[0], /mode=click&path=%2Ftmp%2Fhuge\.png/);

  const bad = page({ image: null });
  bad.loaded.inner.viewOpen(PNG, bad.nodes.png);
  await settle();
  await settle();
  assert.equal(bad.loaded.reads.length, 1);
  assert.equal(status(bad.loaded).photo.open, false);
  assert.match(bad.loaded.calls[0], /mode=click/);

  const none = page({ bridge: false });
  none.loaded.inner.viewOpen(PNG, none.nodes.png);
  await settle();
  assert.match(none.loaded.calls[0], /mode=click/, "моста нет — click");
});

test("viewFile(path) гейта — то же, что пункт «Посмотреть в окне чата»", async () => {
  const { loaded } = page();
  loaded.api.viewFile(HTML);
  await settle();
  assert.match(loaded.calls[0], /mode=view/);
  assert.equal(loaded.api.viewFile("docs/x.html"), false, "только абсолютный путь");
});

test("ссылка на файл в тексте: html и фото — click в PimpViewer, относительная — от папки чата; прочие не трогаем", async () => {
  const { loaded, nodes } = page({
    build: (dom, feed, n) => {
      const row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "14" } });
      const p = row.add("div", { class: "prose" }).add("p");
      n.rel = link(dom, p, "отчёт", "docs/report.html");
      n.abs = link(dom, p, "баннер", "/tmp/b.jpg");
      n.md = link(dom, p, "статус", "docs/status.md");
    },
  });
  click(loaded, nodes.rel);
  await settle();
  assert.equal(loaded.calls[0], `http://127.0.0.1:47615/open-html?mode=click&path=${encodeURIComponent(`${CWD}/docs/report.html`)}&chat=${CHAT}&frame=-1512,-982,640,900&bg=1c1917`);
  click(loaded, nodes.abs);
  await settle();
  assert.equal(loaded.calls[1], `http://127.0.0.1:47615/open-html?mode=click&path=${encodeURIComponent("/tmp/b.jpg")}&chat=${CHAT}&frame=-1512,-982,640,900&bg=1c1917`);
  assert.deepEqual(loaded.reads, [], "мостом не читали — файл ушёл приложению");
  const md = { type: "click", isTrusted: true, target: nodes.md, button: 0, stopped: false };
  md.stopImmediatePropagation = () => { md.stopped = true; };
  md.preventDefault = () => {};
  loaded.document.dispatchEvent(md);
  assert.equal(md.stopped, false, ".md — клик остаётся Claude");
  const mention = status(loaded).mention;
  assert.deepEqual([mention.links, mention.last.via], [2, "link"]);
  const { mentionPath } = loaded.inner;
  assert.equal(mentionPath("./a/../b/x.html", "/r"), "/r/b/x.html");
  assert.equal(mentionPath("x.html", ""), "", "папки нет — относительную не открываем");
  assert.equal(mentionPath("file:///tmp/a%20b.html"), "/tmp/a b.html");
});

test("«на картинке — …» с карточкой выше: слова размечены и открывают её; без карточки — обычные", async () => {
  const { loaded, nodes } = page({
    build: (dom, feed, n) => {
      const row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "14" } });
      n.p = dom.leaf(row.add("div", { class: "prose" }), "p", "Готово, на картинке — баннер в красном.");
      n.text = n.p.childNodes[0];
      const user = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "15" } });
      user.add("div", { attrs: { "data-take-back-entry": "x" } });
      const later = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "16" } });
      n.lone = dom.leaf(later.add("div", { class: "prose" }), "p", "Смотри: на картинках — два варианта.");
    },
  });
  assert.equal(loaded.inner.mentionPaint(true), 1, "размечено одно место: у второго карточки нет (выше — реплика Элвиса)");
  assert.equal(nodes.p.getAttribute("data-myclaude-pic"), "");
  assert.equal(nodes.lone.hasAttribute("data-myclaude-pic"), false);
  assert.equal(nodes.p.textContent, "Готово, на картинке — баннер в красном.", "текст не меняется");
  loaded.document.caretRangeFromPoint = () => ({ startContainer: nodes.text, startOffset: 12 });
  click(loaded, nodes.p, { clientX: 5, clientY: 5 });
  await settle();
  assert.match(loaded.calls[0], new RegExp(`mode=click&path=${encodeURIComponent(PNG).replace(/[.]/g, "\\.")}&chat=`), "открылась ближайшая карточка выше — в PimpViewer");
  const mention = status(loaded).mention;
  assert.deepEqual([mention.words, mention.opens, mention.last.path, mention.last.via], [1, 1, PNG, "word"]);
  // Клик по тексту мимо слов — не наш.
  loaded.document.caretRangeFromPoint = () => ({ startContainer: nodes.text, startOffset: 30 });
  click(loaded, nodes.p);
  assert.equal(status(loaded).mention.opens, 1);
  // dispose снимает метки.
  loaded.api.dispose();
  assert.equal(nodes.p.hasAttribute("data-myclaude-pic"), false);
});
