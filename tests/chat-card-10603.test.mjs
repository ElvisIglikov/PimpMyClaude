// WF291 #10603, раздел 12м⁴ inject.js (640-heic-preview.js): файлы SendUserFile в ленте — карточками, как в PimpViewer.
// Слово Элвиса 22.10.2026: «Я тебя просил превьюшки сделать HTML, чтобы здесь не просто было вот 65 HDML, а прямо сразу
// превьюшка была… как в PimpViewer… Ой, там вообще все картинки надо: и джипы, и хейки, картинки вот так вот отображать».
//
// Что проверяется:
//   1) плашка HTML (button[title] h-9 max-w-60) после ответа /thumb — карточка plate-doc: превью сверху, плашка Claude
//      и её содержимое на месте, превью прозрачно для мыши; до ответа и без ответа — плашка как была;
//   2) фото и HEIC в плашке — plate-photo, ширина по пропорции высоты 180 (160…320);
//   3) квадрат Claude со своей <img> — высотой 180 по пропорции, без запроса /thumb;
//   4) поле ввода не задето; dispose убирает всё; status().heic.cards.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_card-10603";
const ON = "data-myclaude-heic";
const IMG = "data-myclaude-heic-img";
const GROW = "data-myclaude-heic-grow";
const BOX = "data-myclaude-heic-box";
const WVAR = "--myclaude-heic-w";
const HTML = "/Users/demo/Rick/work/65.html";
const JPG = "/Users/demo/Rick/work/storis.jpg";
const HEIC = "/Users/demo/Downloads/IMG_0472.HEIC";
const OWN = "/Users/demo/Rick/work/pizza.png";
const PLATE = "group flex h-9 max-w-60 items-center gap-2 rounded-lg border px-3";
const wait = () => new Promise(resolve => setImmediate(resolve));
const settle = async () => { for (let i = 0; i < 4; i += 1) await wait(); };
// JPEG с заголовком SOF0: высота и ширина — как в настоящем файле.
const jpeg = (w, h) => new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x4A, 0x46,
  0xFF, 0xC0, 0x00, 0x11, 0x08, h >> 8, h & 255, w >> 8, w & 255, 0x03, 0x01, 0x22, 0x00]);
const SIZES = { [HTML]: [480, 360], [JPG]: [400, 600], [HEIC]: [1600, 400] };

const plate = (row, path, size) => {
  const button = row.add("button", { attrs: { type: "button", title: path, class: PLATE } });
  button.add("span", { attrs: { class: "icon" } });
  button.add("span", { text: path.split("/").pop() });
  button.add("span", { text: size });
  return button;
};

const page = ({ reply } = {}) => {
  const nodes = {};
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    geometry: { frame: [0, 0, 640, 900] },
    html: dom => {
      const parts = dom.composer({});
      const panel = dom.document.body.add("div", { attrs: { class: "epitaxy-chat-panel" } });
      const feed = panel.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      const row = feed.add("div", { attrs: { "data-testid": "transcript-row" } });
      nodes.files = row.add("div", { attrs: { class: "flex flex-wrap gap-2" } });
      nodes.html = plate(nodes.files, HTML, "38.6KB");
      nodes.jpg = plate(nodes.files, JPG, "127KB");
      nodes.heic = plate(nodes.files, HEIC, "2.6MB");
      nodes.own = nodes.files.add("button", { attrs: { type: "button", title: OWN } });
      nodes.ownBox = nodes.own.add("div", { attrs: { class: "size-30 overflow-hidden rounded-lg" } });
      nodes.ownImg = nodes.ownBox.add("img", { attrs: { src: "blob:pizza", "data-image-file-name": "pizza.png" } });
      const draft = panel.add("div", { attrs: { "data-cds-composer-attachments": "" } });
      nodes.draft = plate(draft, HTML, "38.6KB");
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  const answer = reply ?? (address => {
    const path = decodeURIComponent(new URL(address).searchParams.get("path"));
    const bytes = jpeg(...(SIZES[path] ?? [480, 360]));
    return { ok: true, arrayBuffer: async () => bytes.buffer };
  });
  loaded.win.fetch = address => { loaded.calls.push(String(address)); return Promise.resolve().then(() => answer(String(address))); };
  return { loaded, nodes };
};
const imgOf = node => [...node.childNodes].find(kid => kid.nodeType === 1 && kid.hasAttribute(IMG)) ?? null;
const thumbs = loaded => loaded.calls.filter(item => item.includes("/thumb?"));

test("#10603: плашка HTML — карточка с превью над плашкой; до ответа — плашка как была", async () => {
  const { loaded, nodes } = page();
  loaded.inner.heicTick();
  assert.equal(nodes.html.getAttribute(ON), null, "метка до ответа — пустая рамка");
  assert.equal(imgOf(nodes.html), null);
  await settle();
  assert.equal(nodes.html.getAttribute(ON), "plate-doc");
  const img = imgOf(nodes.html);
  assert.ok(img, "превью нет");
  assert.match(img.getAttribute("src"), /^data:image\/jpeg;base64,/);
  assert.equal(img.getAttribute("title"), "65.html");
  assert.equal(nodes.html.style.getPropertyValue(WVAR), "", "HTML — ширина 240 правилом, без переменной");
  assert.equal(nodes.html.getAttribute("class"), PLATE, "классы плашки Claude тронуты");
  assert.deepEqual([...nodes.html.childNodes].filter(kid => kid !== img).map(kid => kid.textContent), ["", "65.html", "38.6KB"],
    "содержимое плашки задето");
  const css = [...loaded.inner.RULES].join("\n");
  assert.match(css, /\[data-myclaude-heic\^="plate"\]\{[^}]*width:var\(--myclaude-heic-w,240px\)[^}]*padding-top:180px/);
  assert.match(css, /\[data-myclaude-heic\^="plate"\]>\[data-myclaude-heic-img\]\{[^}]*height:180px[^}]*object-position:top[^}]*pointer-events:none/,
    "превью забирало бы нажатие у плашки");
  assert.match(css, /border-radius:12px/);
  // Поле ввода — не трогаем.
  assert.equal(nodes.draft.getAttribute(ON), null);
  assert.equal(imgOf(nodes.draft), null);
  assert.equal(thumbs(loaded).filter(item => item.includes(encodeURIComponent(HTML))).length, 1, "поле ввода просило снимок");
  // Повторный проход — та же картинка, без нового запроса.
  const asked = thumbs(loaded).length;
  loaded.inner.heicTick();
  assert.equal(thumbs(loaded).length, asked);
  assert.equal(nodes.html.querySelectorAll(`[${IMG}]`).length, 1);
});

test("#10603: без ответа /thumb плашка нетронута", async () => {
  const { loaded, nodes } = page({ reply: () => ({ ok: false }) });
  loaded.inner.heicTick();
  await settle();
  loaded.inner.heicTick();
  for (const node of [nodes.html, nodes.jpg, nodes.heic]) {
    assert.equal(node.getAttribute(ON), null);
    assert.equal(imgOf(node), null);
    assert.equal(node.style.getPropertyValue(WVAR), "");
  }
  assert.equal(plain(loaded.api.status().heic).cards, 0, "карточек нет: своя картинка Claude ещё не загрузилась");
  assert.equal(nodes.own.getAttribute(GROW), null, "незагруженная картинка — квадрат как был");
});

test("#10603: фото и HEIC — высотой 180 по пропорции (160…320); свой квадрат Claude растёт без /thumb", async () => {
  const { loaded, nodes } = page();
  nodes.ownImg.naturalWidth = 300;
  nodes.ownImg.naturalHeight = 200;
  loaded.inner.heicTick();
  await settle();
  assert.equal(nodes.jpg.getAttribute(ON), "plate-photo");
  assert.equal(nodes.jpg.style.getPropertyValue(WVAR), "160px", "400×600 → 120×180, не уже 160");
  assert.equal(nodes.heic.getAttribute(ON), "plate-photo");
  assert.equal(nodes.heic.style.getPropertyValue(WVAR), "320px", "широкое — не шире 320");
  assert.ok(imgOf(nodes.heic));
  assert.ok(!thumbs(loaded).some(item => item.includes(encodeURIComponent(OWN))), "у своей картинки Claude запросов нет");
  assert.equal(nodes.own.getAttribute(GROW), "");
  assert.equal(nodes.own.style.getPropertyValue(WVAR), "270px", "300×200 → 270×180");
  assert.equal(nodes.ownBox.getAttribute(BOX), "");
  assert.equal(nodes.own.getAttribute(ON), null);
  assert.equal(plain(loaded.api.status().heic).cards, 4);
  const css = [...loaded.inner.RULES].join("\n");
  assert.match(css, /button\[data-myclaude-heic-grow\]\{[^}]*height:180px/);
  assert.match(css, /flex-wrap:wrap/);
  assert.deepEqual(plain(loaded.inner.heicJpegSize(jpeg(480, 360))), { h: 360, w: 480 });
  assert.equal(loaded.inner.heicJpegSize(new Uint8Array([0xFF, 0xD8, 0x00])), null);
  loaded.api.dispose();
  for (const node of [nodes.html, nodes.jpg, nodes.heic, nodes.own]) {
    assert.equal(node.getAttribute(ON), null);
    assert.equal(node.getAttribute(GROW), null);
    assert.equal(node.querySelector(`[${IMG}]`), null);
    assert.equal(node.style.getPropertyValue(WVAR), "", "dispose не убрал ширину");
  }
  assert.equal(nodes.ownBox.getAttribute(BOX), null);
});

// Чат Рика (SendUserMessage, Claude 3.1623): карточка без нажатия — div.opacity-70[title=<имя>], путь у волокна
// компонента над ней (как #10531). Задача #10603 — про этот чат.
test("#10603: чат Рика — div.opacity-70[title=имя] с путём у волокна тоже карточка, в полный цвет", async () => {
  const RICK = "group flex h-9 min-w-0 max-w-60 items-center gap-2 px-2 text-start opacity-70";
  const tile = (row, path, props = {}) => {
    const name = path.split("/").pop();
    const div = row.add("div", { attrs: { class: RICK, title: name } });
    div.add("span", { text: name });
    div.add("span", { text: "146.8KB" });
    div.__reactFiber$test = { memoizedProps: { title: name, children: [] },
      return: { memoizedProps: { name, size: 150323, path, square: false, ...props }, return: null } };
    return div;
  };
  const { loaded, nodes } = page();
  nodes.rick = tile(nodes.files, "/Users/demo/Rick/work/65.html");
  nodes.alien = tile(nodes.files, "/Users/demo/Rick/work/66.html", { name: "другое.html" });
  loaded.inner.heicTick();
  await settle();
  assert.equal(nodes.rick.getAttribute(ON), "plate-doc");
  assert.ok(imgOf(nodes.rick), "превью нет");
  assert.ok(thumbs(loaded).some(item => item.includes(encodeURIComponent("/Users/demo/Rick/work/65.html"))));
  assert.equal(nodes.alien.getAttribute(ON), null, "имя у волокна не то — не своё");
  assert.ok(!thumbs(loaded).some(item => item.includes(encodeURIComponent("/Users/demo/Rick/work/66.html"))));
  const css = [...loaded.inner.RULES].join("\n");
  assert.match(css, /\.opacity-70\[data-myclaude-heic\]\{opacity:1 !important\}/);
  loaded.api.dispose();
  assert.equal(nodes.rick.getAttribute(ON), null);
  assert.equal(imgOf(nodes.rick), null);
});

// Вызов с картинкой: Claude рисует все карточки квадратом 120 (стиль 120×120, значок, имя, размер). HTML в нём —
// снимок 180 сверху, имя Claude внизу; кнопка с путём без квадрата (заголовок инструмента) — не трогается.
test("#10603: квадрат 120 самой карточки — HTML со снимком сверху (square-doc); кнопка без квадрата — нет", async () => {
  const { loaded, nodes } = page();
  const square = nodes.files.add("button", { attrs: { type: "button", title: "/Users/demo/Rick/work/70.html",
    class: "font-sans rounded-lg border-0.5 flex flex-col justify-between gap-2.5 px-2.5 py-2 text-start" } });
  square.style.width = "120px";
  square.style.height = "120px";
  square.add("div", { attrs: { class: "h-[18px] flex items-center px-1" } }).add("span", { text: "html" });
  square.add("div", { attrs: { class: "min-w-0" } }).add("p", { text: "70.html" });
  const photo = nodes.files.add("button", { attrs: { type: "button", title: JPG, class: "font-sans flex flex-col" } });
  photo.style.width = "120px";
  photo.style.height = "120px";
  photo.add("div", { attrs: { class: "h-[18px]" } }).add("span", { text: "jpg" });
  const header = nodes.files.add("button", { attrs: { type: "button", title: "/Users/demo/Rick/work/71.html" } });
  header.add("span", { text: "Write 71.html" });
  loaded.inner.heicTick();
  await settle();
  assert.equal(square.getAttribute(ON), "square-doc");
  assert.ok(imgOf(square));
  assert.equal(header.getAttribute(ON), null);
  assert.equal(photo.getAttribute(ON), "card", "фото в квадрате — миниатюрой во весь квадрат");
  assert.equal(photo.getAttribute(GROW), "", "фото в квадрате — высотой 180, как соседи");
  assert.equal(photo.style.getPropertyValue(WVAR), "160px", "400×600 — не уже 160");
  assert.equal(square.getAttribute(GROW), null, "HTML растёт правилом square-doc, не ростом квадрата");
  assert.ok(!thumbs(loaded).some(item => item.includes(encodeURIComponent("/Users/demo/Rick/work/71.html"))),
    "заголовок инструмента просил снимок");
  const css = [...loaded.inner.RULES].join("\n");
  assert.match(css, /\[data-myclaude-heic="square-doc"\]\{[^}]*width:240px[^}]*padding-top:188px/);
  assert.match(css, /\[data-myclaude-heic="square-doc"\]>\[data-myclaude-heic-img\]\{[^}]*height:180px[^}]*pointer-events:none/);
});
