// #11304, раздел 12л inject.js (620-photo-viewer.js): снимок HTML в карточке SendUserFile — превью, не фото.
// Слово Элвиса 30.10: «HTML открываю, ты эту HTML как картинку открываешь. Я ни прокрутить ничего, скопировать с неё
// не могу… она там должна отображаться, но при нажатии на неё HTML должна открываться».
//
// Что проверяется:
//   1) плашка HTML с превью (plate-doc, #10603): клик по самой плашке и по превью — путь открытия файла (fileClick →
//      /open-html?mode=click), просмотр фото 12л не открыт, превью на месте;
//   2) превью HTML не входит в список фото (листание ‹ ›), а превью JPG (plate-photo) — входит;
//   3) клик по обычному фото ленты — просмотр 12л, как раньше;
//   4) перетаскивание 12м²: карточка HTML со снимком тащится файлом (путь .html), не снимком.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_html-11304";
const ON = "data-myclaude-heic";
const IMG = "data-myclaude-heic-img";
const HTML = "/Users/demo/Rick/work/65.html";
const JPG = "/Users/demo/Rick/work/storis.jpg";
const PLATE = "group flex h-9 max-w-60 items-center gap-2 rounded-lg border px-3";
const wait = () => new Promise(resolve => setImmediate(resolve));
const settle = async () => { for (let i = 0; i < 4; i += 1) await wait(); };
const jpeg = (w, h) => new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x4A, 0x46,
  0xFF, 0xC0, 0x00, 0x11, 0x08, h >> 8, h & 255, w >> 8, w & 255, 0x03, 0x01, 0x22, 0x00]);

const plate = (row, path, size) => {
  const button = row.add("button", { attrs: { type: "button", title: path, class: PLATE } });
  button.add("span", { attrs: { class: "icon" } });
  button.add("span", { text: path.split("/").pop() });
  button.add("span", { text: size });
  // Как у Claude (разведка #7860): пропсы {name,size,path} — шагом выше волокна кнопки.
  button["__reactFiber$test"] = { memoizedProps: { type: "button" }, return: { memoizedProps: { name: path.split("/").pop(), size, path }, return: null } };
  return button;
};
const photo = (parent, src) => {
  const img = parent.add("img", { attrs: { src } });
  img.naturalWidth = 640;
  img.naturalHeight = 1440;
  img.rect = { left: 0, top: 0, width: 71, height: 160 };
  return img;
};

const page = async () => {
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
      nodes.tile = row.add("span", { attrs: { role: "button" } });
      nodes.photo = photo(nodes.tile, "data:image/png;base64,QUJD");
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.win.fetch = address => {
    loaded.calls.push(String(address));
    const bytes = jpeg(480, 360);
    return Promise.resolve({ ok: true, arrayBuffer: async () => bytes.buffer });
  };
  loaded.inner.heicTick();
  await settle();
  loaded.inner.heicTick();
  // Превью — как живое фото по размеру: так его и брал просмотр 12л.
  for (const key of ["html", "jpg"]) {
    const img = [...nodes[key].childNodes].find(kid => kid.nodeType === 1 && kid.hasAttribute(IMG));
    assert.ok(img, `превью ${key} нет`);
    img.naturalWidth = 480;
    img.naturalHeight = 360;
    img.rect = { left: 0, top: 0, width: 240, height: 180 };
    nodes[`${key}Img`] = img;
  }
  return { loaded, nodes };
};
const opens = loaded => loaded.calls.filter(item => item.includes("/open-html?"));
const click = (loaded, target) => {
  for (const type of ["pointerdown", "mousedown"]) loaded.document.dispatchEvent({ type, isTrusted: true, target, button: 0 });
  loaded.document.dispatchEvent({ type: "click", isTrusted: true, target, button: 0, detail: 1 });
};

test("#11304: клик по плашке HTML с превью — открывается сам HTML, не просмотр фото", async () => {
  const { loaded, nodes } = await page();
  assert.equal(nodes.html.getAttribute(ON), "plate-doc");
  assert.equal(loaded.inner.photoAt(nodes.html), null, "плашка HTML — не фото");
  assert.equal(loaded.inner.photoAt(nodes.htmlImg), null, "превью HTML — не фото");
  click(loaded, nodes.html);
  assert.equal(loaded.api.status().photo.open, false, "открылся просмотр фото 1/1");
  assert.equal(opens(loaded).length, 1, "файл не открывался");
  assert.match(opens(loaded)[0], new RegExp(`mode=click.*path=${encodeURIComponent(HTML)}`));
  assert.equal(plain(loaded.api.status().htmlChrome.last).path, HTML);
  assert.ok(nodes.htmlImg.isConnected, "превью картинкой пропало");
});

test("#11304: клик прямо по превью HTML — тоже сам HTML", async () => {
  const { loaded, nodes } = await page();
  click(loaded, nodes.htmlImg);
  assert.equal(loaded.api.status().photo.open, false);
  assert.equal(opens(loaded).length, 1);
  assert.match(opens(loaded)[0], new RegExp(`path=${encodeURIComponent(HTML)}`));
});

test("#11304: превью HTML не листается в просмотре; превью JPG и фото ленты — листаются", async () => {
  const { loaded, nodes } = await page();
  const list = loaded.inner.photoList();
  assert.ok(!list.some(item => item.img === nodes.htmlImg), "превью HTML в списке фото");
  assert.ok(list.some(item => item.img === nodes.jpgImg), "превью JPG выпало из фото");
  assert.ok(list.some(item => item.img === nodes.photo), "фото ленты выпало");
});

test("#11304: клик по обычному фото ленты — просмотр 12л, как раньше", async () => {
  const { loaded, nodes } = await page();
  click(loaded, nodes.tile);
  assert.equal(loaded.api.status().photo.open, true, "просмотр фото не открылся");
  assert.equal(opens(loaded).length, 0, "фото ушло в открытие файла");
});

test("#11304: карточка HTML со снимком тащится файлом (12м²), а не снимком-фото", async () => {
  const { loaded, nodes } = await page();
  assert.equal(loaded.inner.ddCardAt(nodes.html)?.found?.path, HTML, "карточка HTML не тащится");
  assert.equal(loaded.inner.ddCardAt(nodes.htmlImg)?.found?.path, HTML, "с превью карточка HTML не тащится");
  assert.equal(loaded.inner.ddCardAt(nodes.jpg), null, "плашка JPG со снимком — фото, не карточка");
});
