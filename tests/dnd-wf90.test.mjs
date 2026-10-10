// Перетаскивание вложений (раздел 12м² inject.js, #7685, WF90). Слово Элвиса
// 25.09 (пересказ): перетаскивание не работает совсем — нужно между чатами,
// внутри чата и в другие программы.
//
// Проверяется контракт раздела:
//   1) наведение делает плитку фото и карточку файла draggable (картинку внутри
//      плитки — нет), dispose возвращает атрибуты как были;
//   2) dragstart кладёт DownloadURL «mime:имя:адрес» (фото — его data:, карточка —
//      прочитанный заранее data: или file://), у карточки ещё uri-list и путь
//      текстом, и свой маркер application/x-pimpmyclaude-drag;
//   3) бросок с маркером в окно Claude: dragover разрешён, drop погашен и файл
//      уехал в поле ввода синтетическим paste; не читается — путь текстом;
//   4) в своём окне бросок на свою ленту не принимается, чужие броски не трогаем.
//
// Стенд: события шлём прямо на документ с нужной целью (стаб не всплывает);
// dataTransfer — свой объект с types, как у Chromium.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const TYPE = "application/x-pimpmyclaude-drag";
const PATH = "/Users/dev/Projects/VkusStatBot/docs/1.html";
const ZIP = "/Users/dev/Projects/VkusStatBot/out/report.zip";

const photo = (parent, src, { w = 640, h = 1440, shown = [71, 160] } = {}) => {
  const img = parent.add("img", { attrs: { src } });
  img.naturalWidth = w;
  img.naturalHeight = h;
  img.rect = { left: 0, top: 0, width: shown[0], height: shown[1] };
  return img;
};

// Карточка файла, как у Claude 2.9939.2: кнопка, пропсы {name, size, path} у
// компонента на шаг выше.
const card = (parent, path, size = 25902, { hops = 1, text } = {}) => {
  const button = parent.add("button", { class: "font-sans rounded-lg" });
  const name = path.split("/").pop();
  button.add("span", { text: text ?? `${name} ${size}B` });
  let fiber = { memoizedProps: { name, size, path, href: null }, return: null };
  for (let hop = 1; hop < hops; hop += 1) fiber = { memoizedProps: { className: "wrap" }, return: fiber };
  button.__reactFiber$test = { memoizedProps: { children: [] }, return: fiber };
  return button;
};

const page = ({ href = "https://claude.ai/epitaxy/local_src", bridge = true, composer = true, extra = null } = {}) => {
  const nodes = {};
  const loaded = loadInject({
    href,
    html: dom => {
      const parts = composer ? dom.composer({}) : null;
      const feed = dom.document.body.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" },
      });
      const row = feed.add("div", { class: "group/message-row" });
      nodes.tile = row.add("span", { attrs: { role: "button", tabindex: "0" } });
      nodes.img = photo(nodes.tile, "data:image/webp;base64,QUJD");
      nodes.view = row.add("button", { attrs: { "aria-label": "View image preview.png" } });
      nodes.viewImg = photo(nodes.view, "data:image/png;base64,WFla", { w: 1312, h: 540 });
      nodes.card = card(row, PATH);
      nodes.cardText = nodes.card.querySelector("span");
      nodes.zip = card(row, ZIP, 1024);
      nodes.text = row.add("p", { text: "просто текст" });
      nodes.parts = parts;
      extra?.(row, nodes, dom);
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.win.atob = value => Buffer.from(value, "base64").toString("binary");
  const reads = [];
  if (bridge) {
    const answer = (method, path) => {
      if (method === "readSessionFile" && path === PATH) return { contents: "<p>привет</p>", fileSize: 13 };
      if (method === "readSessionFile" && path === ZIP) return { contents: "PK\u0003\u0004��" };
      if (method === "readSessionImageAsDataUrl") return loaded.win.__bigImage ?? "data:image/png;base64,SU1H";
      return null;
    };
    const sessions = {};
    for (const method of ["readSessionFile", "readSessionImageAsDataUrl", "readSessionMediaAsDataUrl", "readSessionPanelDocumentAsDataUrl"]) {
      sessions[method] = (chat, path) => { reads.push([method, chat, path]); return Promise.resolve(answer(method, path)); };
    }
    loaded.win["claude.web"] = { LocalSessions: sessions };
  }
  return { loaded, nodes, reads };
};

const transfer = (entries = {}) => {
  const map = new Map(Object.entries(entries));
  return {
    map,
    effectAllowed: "uninitialized",
    dropEffect: "none",
    get types() { return [...map.keys()]; },
    setData(type, value) { map.set(type, String(value)); },
    getData(type) { return map.get(type) ?? ""; },
  };
};
const fire = (loaded, type, target, extra = {}) => loaded.document.dispatchEvent({ type, target, button: 0, ...extra });
const settle = () => new Promise(resolve => setImmediate(resolve));
const pasted = editor => {
  const got = [];
  editor.addEventListener("paste", event => got.push([...(event.clipboardData?.files ?? [])]));
  return got;
};

test("наведение делает плитку фото и карточку перетаскиваемыми, dispose возвращает как было", () => {
  const { loaded, nodes } = page();
  fire(loaded, "pointerover", nodes.tile);
  assert.equal(nodes.tile.getAttribute("draggable"), "true");
  assert.equal(nodes.img.getAttribute("draggable"), "false", "тащится плитка, а не родная картинка Chromium");
  fire(loaded, "pointerover", nodes.cardText);
  assert.equal(nodes.card.getAttribute("draggable"), "true");
  fire(loaded, "pointerover", nodes.text);
  assert.equal(nodes.text.getAttribute("draggable"), null, "текст ленты не трогаем");
  loaded.api.dispose();
  for (const node of [nodes.tile, nodes.img, nodes.card]) {
    assert.equal(node.getAttribute("draggable"), null);
    assert.equal(node.getAttribute("data-myclaude-dd"), null);
  }
});

test("фото: DownloadURL с data:-адресом и маркер, без пути текстом", () => {
  const { loaded, nodes } = page();
  const data = transfer();
  fire(loaded, "dragstart", nodes.tile, { dataTransfer: data });
  assert.equal(data.getData("DownloadURL"), "image/webp:photo-1.webp:data:image/webp;base64,QUJD");
  assert.equal(data.getData("text/plain"), "");
  const marker = JSON.parse(data.getData(TYPE));
  assert.deepEqual(marker, { v: 1, kind: "photo", name: "photo-1.webp", mime: "image/webp", src: "data:image/webp;base64,QUJD", chat: "local_src" });
  assert.equal(data.effectAllowed, "copy");
  // Попап: имя фото — из подписи кнопки «View image …».
  const again = transfer();
  fire(loaded, "dragstart", nodes.viewImg, { dataTransfer: again });
  assert.equal(again.getData("DownloadURL"), "image/png:preview.png:data:image/png;base64,WFla");
  assert.equal(plain(loaded.api.dnd()).starts, 2);
});

test("карточка: прочитанный заранее файл едет data:-адресом, путь — uri-list и текстом", async () => {
  const { loaded, nodes, reads } = page();
  fire(loaded, "pointerdown", nodes.cardText, { clientX: 10, clientY: 10 });
  fire(loaded, "pointermove", nodes.cardText, { clientX: 14, clientY: 11, buttons: 1 });
  await settle();
  assert.deepEqual(reads, [["readSessionFile", "local_src", PATH]]);
  const data = transfer();
  fire(loaded, "dragstart", nodes.card, { dataTransfer: data });
  assert.equal(data.getData("DownloadURL"),
    `text/html:1.html:data:text/html;charset=utf-8,${encodeURIComponent("<p>привет</p>")}`);
  assert.equal(data.getData("text/uri-list"), `file://${encodeURI(PATH)}`);
  assert.equal(data.getData("text/plain"), PATH);
  assert.deepEqual(JSON.parse(data.getData(TYPE)), { v: 1, kind: "card", name: "1.html", mime: "text/html", path: PATH, chat: "local_src", size: 25902 });
});

test("файл читается только когда карточку тянут: клик и дрожь мыши мост не трогают", async () => {
  const { loaded, nodes, reads } = page();
  // Обычный клик: нажал, отпустил, click.
  fire(loaded, "pointerdown", nodes.cardText, { clientX: 10, clientY: 10 });
  fire(loaded, "pointerup", nodes.cardText, { clientX: 10, clientY: 10 });
  fire(loaded, "click", nodes.cardText, { clientX: 10, clientY: 10 });
  // Сдвиг меньше 3 px с зажатой кнопкой и движение без кнопки.
  fire(loaded, "pointerdown", nodes.cardText, { clientX: 10, clientY: 10 });
  fire(loaded, "pointermove", nodes.cardText, { clientX: 11, clientY: 11, buttons: 1 });
  fire(loaded, "pointermove", nodes.cardText, { clientX: 30, clientY: 30, buttons: 0 });
  fire(loaded, "pointermove", nodes.cardText, { clientX: 40, clientY: 40, buttons: 1 });
  await settle();
  assert.deepEqual(reads, []);
  assert.equal(plain(loaded.api.dnd()).reads, 0);
  // Потянул — читает ровно один раз.
  fire(loaded, "pointerdown", nodes.cardText, { clientX: 10, clientY: 10 });
  fire(loaded, "pointermove", nodes.cardText, { clientX: 10, clientY: 14, buttons: 1 });
  fire(loaded, "pointermove", nodes.cardText, { clientX: 10, clientY: 20, buttons: 1 });
  await settle();
  assert.deepEqual(reads, [["readSessionFile", "local_src", PATH]]);
});

test("dragstart раньше pointermove начинает чтение сам; потолки: 20 МБ, неизвестный размер, кэш 60 МБ", async () => {
  const { loaded, nodes, reads } = page();
  const first = transfer();
  fire(loaded, "dragstart", nodes.card, { dataTransfer: first });
  assert.equal(first.getData("DownloadURL"), `text/html:1.html:file://${encodeURI(PATH)}`, "чтение не успело — file://");
  await settle();
  assert.deepEqual(reads, [["readSessionFile", "local_src", PATH]]);
  const second = transfer();
  fire(loaded, "dragstart", nodes.card, { dataTransfer: second });
  assert.match(second.getData("DownloadURL"), /^text\/html:1\.html:data:text\/html;charset=utf-8,/);
  assert.equal(reads.length, 1, "второй раз — из кэша");
  const { ddPrefetch, ddState } = loaded.inner;
  reads.length = 0;
  assert.equal(ddPrefetch("/x/big.html", "big.html", 21 * 1024 * 1024), null, "больше 20 МБ — не читаем");
  for (const name of ["movie.mp4", "doc.pdf", "notes.md"]) {
    assert.equal(ddPrefetch(`/x/${name}`, name, 0), null, `${name} неизвестного размера — не читаем`);
  }
  await settle();
  assert.deepEqual(reads, []);
  // Картинка неизвестного размера читается; кэш держит не больше 60 МБ суммарно.
  loaded.win.__bigImage = `data:image/png;base64,${"A".repeat(25 * 1024 * 1024)}`;
  for (const name of ["a.png", "b.png", "c.png"]) ddPrefetch(`/x/${name}`, name, 0);
  await settle();
  await settle();
  assert.equal(reads.length, 3);
  assert.equal(ddState.cache.has("/x/a.png"), false, "самая старая ушла");
  assert.equal(ddState.cache.has("/x/b.png") && ddState.cache.has("/x/c.png"), true);
  let total = 0;
  for (const entry of ddState.cache.values()) total += entry.url?.length ?? 0;
  assert.ok(total <= 60 * 1024 * 1024);
});

test("перетаскиваются только карточки: служебные кнопки блока инструмента — нет", () => {
  const { loaded, nodes } = page({
    extra: (row, box) => {
      box.tool = card(row, PATH, 100, { hops: 6, text: "Copy" });
      box.named = card(row, "/x/report.md", 100, { hops: 6, text: "report.md 100B" });
      box.near = card(row, "/x/near.md", 100, { hops: 3, text: "Open" });
    },
  });
  assert.equal(loaded.inner.ddCardAt(nodes.tool), null, "path далеко, имени в кнопке нет");
  fire(loaded, "pointerover", nodes.tool);
  assert.equal(nodes.tool.getAttribute("draggable"), null);
  assert.equal(loaded.inner.ddCardAt(nodes.named).found.path, "/x/report.md", "имя файла в тексте кнопки");
  assert.equal(loaded.inner.ddCardAt(nodes.near).found.path, "/x/near.md", "ближайший компонент над кнопкой");
  const data = transfer();
  fire(loaded, "dragstart", nodes.tool, { dataTransfer: data });
  assert.equal(data.getData(TYPE), "");
});

test("окно без поля ввода: бросок с маркером запрещён и погашен, путь в чужое поле не ложится", () => {
  const { loaded, nodes } = page({
    href: "https://claude.ai/epitaxy/local_dst",
    composer: false,
    extra: (row, box, dom) => { box.rename = dom.document.body.add("input", { attrs: { type: "text" } }); },
  });
  const seen = [];
  loaded.document.addEventListener("drop", () => seen.push("drop"));
  const marker = { v: 1, kind: "card", name: "1.html", mime: "text/html", path: PATH, chat: "local_src" };
  const data = transfer({ [TYPE]: JSON.stringify(marker), "text/plain": PATH });
  assert.equal(fire(loaded, "dragover", nodes.rename, { dataTransfer: data }), false);
  assert.equal(data.dropEffect, "none");
  assert.equal(fire(loaded, "drop", nodes.rename, { dataTransfer: data }), false, "drop погашен — браузер путь не вставит");
  assert.deepEqual(seen, []);
  assert.equal(loaded.inner.ddState.landing, null);
  // Чужой бросок (текст) в этом окне не трогаем.
  const foreign = transfer({ "text/plain": "x" });
  assert.equal(fire(loaded, "dragover", nodes.rename, { dataTransfer: foreign }), true);
  assert.equal(fire(loaded, "drop", nodes.rename, { dataTransfer: foreign }), true);
});

test("карточка без чтения заранее и двоичный zip: DownloadURL с file://, мост zip не читает", async () => {
  const { loaded, nodes, reads } = page();
  fire(loaded, "pointerdown", nodes.zip);
  await settle();
  assert.deepEqual(reads, [], "zip мостом не читается — байты испортились бы в utf-8");
  const data = transfer();
  fire(loaded, "dragstart", nodes.zip, { dataTransfer: data });
  assert.equal(data.getData("DownloadURL"), `application/zip:report.zip:file://${encodeURI(ZIP)}`);
  // Текст с U+FFFD — это двоичное: не берём.
  assert.equal(await loaded.inner.ddReadUrl("local_src", ZIP, "report.txt"), null);
  assert.equal(loaded.inner.ddReadWay("a.PNG"), "image");
  assert.equal(loaded.inner.ddReadWay("a.mp4"), "media");
  assert.equal(loaded.inner.ddReadWay("a.pdf"), "pdf");
  assert.equal(loaded.inner.ddReadWay("a.md"), "text");
});

test("попап берёт мост чтения у родителя", async () => {
  const parent = page();
  const { loaded } = page({ href: "about:blank", bridge: false });
  loaded.win.opener = parent.loaded.win;
  const url = await loaded.inner.ddReadUrl("local_x", PATH, "1.html");
  assert.match(url, /^data:text\/html;charset=utf-8,/);
  assert.deepEqual(parent.reads, [["readSessionFile", "local_x", PATH]]);
});

test("бросок фото в другое окно Claude: dragover разрешён, drop погашен, файл уехал в поле paste'ом", async () => {
  const { loaded, nodes } = page({ href: "https://claude.ai/epitaxy/local_dst" });
  const editor = nodes.parts.editor;
  const got = pasted(editor);
  const claude = [];
  loaded.document.addEventListener("drop", () => claude.push("drop"));
  const marker = { v: 1, kind: "photo", name: "photo-1.png", mime: "image/png", src: "data:image/png;base64,QUJD", chat: "local_src" };
  const over = transfer({ [TYPE]: JSON.stringify(marker) });
  assert.equal(fire(loaded, "dragover", nodes.text, { dataTransfer: over }), false, "dragover отменён — бросок разрешён");
  assert.equal(over.dropEffect, "copy");
  assert.equal(fire(loaded, "drop", nodes.text, { dataTransfer: over }), false);
  assert.deepEqual(claude, [], "ProseMirror и Claude броска не видят");
  assert.equal(await loaded.inner.ddState.landing, true);
  assert.equal(got.length, 1);
  const [file] = got[0];
  assert.equal(file.name, "photo-1.png");
  assert.equal(file.type, "image/png");
  assert.deepEqual(file.__bytes, [...Buffer.from("ABC")]);
  assert.deepEqual(plain(loaded.api.dnd().last), { kind: "photo", name: "photo-1.png", how: "file", ok: true });
});

test("бросок карточки: текстовый файл читается мостом по чату-источнику, zip — путь текстом", async () => {
  const { loaded, nodes, reads } = page({ href: "https://claude.ai/epitaxy/local_dst" });
  const editor = nodes.parts.editor;
  const got = pasted(editor);
  const card1 = { v: 1, kind: "card", name: "1.html", mime: "text/html", path: PATH, chat: "local_src" };
  fire(loaded, "drop", nodes.parts.editor, { dataTransfer: transfer({ [TYPE]: JSON.stringify(card1) }) });
  assert.equal(await loaded.inner.ddState.landing, true);
  assert.deepEqual(reads, [["readSessionFile", "local_src", PATH]]);
  assert.equal(got[0][0].name, "1.html");
  assert.equal(got[0][0].type, "text/html");
  const zip = { v: 1, kind: "card", name: "report.zip", mime: "application/zip", path: ZIP, chat: "local_src" };
  fire(loaded, "drop", nodes.parts.editor, { dataTransfer: transfer({ [TYPE]: JSON.stringify(zip) }) });
  assert.equal(await loaded.inner.ddState.landing, true);
  assert.equal(got.length, 1, "zip файлом не приложить");
  assert.equal(editor.__text, `${ZIP} `, "путь лёг текстом — Claude Code прочтёт файл сам");
  assert.equal(plain(loaded.api.dnd()).drops, 2);
});

test("своё окно: на свою ленту бросок не принимается, в поле — принимается; чужие броски не трогаем", async () => {
  const { loaded, nodes } = page();
  const got = pasted(nodes.parts.editor);
  const data = transfer();
  fire(loaded, "dragstart", nodes.tile, { dataTransfer: data });
  assert.equal(fire(loaded, "dragover", nodes.text, { dataTransfer: data }), true, "над своей лентой — «передумал»");
  assert.equal(fire(loaded, "drop", nodes.text, { dataTransfer: data }), true);
  assert.equal(loaded.inner.ddState.landing, null);
  assert.equal(fire(loaded, "dragover", nodes.parts.editor, { dataTransfer: data }), false);
  fire(loaded, "drop", nodes.parts.editor, { dataTransfer: data });
  assert.equal(await loaded.inner.ddState.landing, true);
  assert.equal(got[0][0].name, "photo-1.webp");
  fire(loaded, "dragend", nodes.tile);
  assert.equal(loaded.api.dnd().dragging, false);
  // Файлы из Finder и текст — не наши: Claude принимает их сам.
  const foreign = transfer({ Files: "", "text/plain": "x" });
  assert.equal(fire(loaded, "dragover", nodes.parts.editor, { dataTransfer: foreign }), true);
  assert.equal(fire(loaded, "drop", nodes.parts.editor, { dataTransfer: foreign }), true);
});

test("нажатие по фото не отменяет pointerdown (иначе Chromium не начнёт перетаскивание), клик открывает просмотр", () => {
  const { loaded, nodes } = page();
  assert.equal(fire(loaded, "pointerdown", nodes.tile), true);
  assert.equal(fire(loaded, "mousedown", nodes.tile), true);
  assert.equal(fire(loaded, "click", nodes.tile), false);
  assert.equal(loaded.api.viewer.state().open, true);
});

test("после закрытия просмотра фокус возвращается в поле ввода, где был до нажатия по фото", () => {
  const { loaded, nodes } = page();
  const editor = nodes.parts.editor;
  editor.focus();
  fire(loaded, "pointerdown", nodes.tile);
  nodes.tile.focus(); // mousedown по плитке с tabindex уводит фокус на неё
  fire(loaded, "click", nodes.tile);
  assert.equal(loaded.api.viewer.state().open, true);
  assert.notEqual(loaded.document.activeElement, editor);
  loaded.api.viewer.close();
  assert.equal(loaded.document.activeElement, editor);
});
