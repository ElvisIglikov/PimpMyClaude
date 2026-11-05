// #11304, разделы 12л (620-photo-viewer.js) и 12д (360-html-in-chrome.js): снимок файла в чате — не фото.
// Слово Элвиса 31.10 ~01:55: «эту HTML, как картинку открываешь… Я ни прокрутить ничего, скопировать с неё не могу…
// при нажатии на неё… должна открываться». Живой след: карточка SendUserFile 11.html в чате Рика — plate-doc со
// снимком 1080×1080; нажатие открывало просмотр фото («1 / 1, 84 %, По ширине»), до 12д клик не доходил.
//
// Что проверяется:
//   1) снимок HTML во всех видах карточки (plate-doc, card-doc) и своя картинка Claude в карточке не-картинки — не фото
//      просмотра 12л (ни нажатие, ни наведение, ни перетаскивание как фото);
//   2) нажатие по карточке plate-doc — файл: /open-html?mode=click с путём HTML, просмотр фото закрыт;
//   3) фото (JPG plate-photo) — как было: нажатие открывает просмотр 12л.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const CHAT = "local_shot-11304";
const ON = "data-myclaude-heic";
const IMG = "data-myclaude-heic-img";
const HTML = "/Users/demo/VkusOborudovanie/kofemashina/11.html";
const PDF = "/Users/demo/Rick/work/list.pdf";
const JPG = "/Users/demo/Rick/work/storis.jpg";
const OWN = "/Users/demo/Rick/work/report.html";
const PLATE = "font-sans rounded-lg flex h-9 min-w-0 max-w-60 items-center gap-2 px-2";
const wait = () => new Promise(resolve => setImmediate(resolve));
const settle = async () => { for (let i = 0; i < 4; i += 1) await wait(); };
const jpeg = (w, h) => new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x4A, 0x46,
  0xFF, 0xC0, 0x00, 0x11, 0x08, h >> 8, h & 255, w >> 8, w & 255, 0x03, 0x01, 0x22, 0x00]);

const plate = (row, path) => {
  const button = row.add("button", { attrs: { type: "button", title: path, class: PLATE }, rect: { left: 0, top: 0, width: 240, height: 216 } });
  button.add("span", { text: path.split("/").pop() });
  return button;
};

const page = () => {
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
      nodes.html = plate(row, HTML);
      nodes.jpg = plate(row, JPG);
      nodes.pdf = row.add("button", { attrs: { type: "button", title: PDF } });
      nodes.pdfSquare = nodes.pdf.add("div", { rect: { left: 0, top: 0, width: 120, height: 120 } });
      // Своя картинка Claude в карточке HTML (рендер страницы) — снимок, не фото.
      nodes.own = row.add("button", { attrs: { type: "button", title: OWN } });
      nodes.ownImg = nodes.own.add("img", { attrs: { src: "data:image/png;base64,UkVOREVS" } });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.win.fetch = address => {
    loaded.calls.push(String(address));
    if (String(address).includes("/thumb?")) {
      const bytes = jpeg(1080, 1080);
      return Promise.resolve({ ok: true, arrayBuffer: async () => bytes.buffer });
    }
    return Promise.resolve({ ok: true });
  };
  return { loaded, nodes };
};
// Снимок в плитке — размера настоящей картинки (как живой 1080×1080, на экране 240×180).
const sized = img => {
  img.naturalWidth = 1080;
  img.naturalHeight = 1080;
  img.rect = { left: 0, top: 0, width: 240, height: 180 };
  return img;
};
const shotOf = node => sized(node.querySelector(`[${IMG}]`));
const press = (loaded, target) => {
  for (const type of ["pointerdown", "mousedown", "click"]) {
    loaded.document.dispatchEvent({ type, target, button: 0, isTrusted: true, detail: 1, clientX: 10, clientY: 10 });
  }
};
const opens = loaded => loaded.calls.filter(item => item.includes("/open-html?"));

test("#11304: снимок HTML/PDF в карточке и рендер Claude не-картинки — не фото; JPG — фото", async () => {
  const { loaded, nodes } = page();
  loaded.inner.heicTick();
  await settle();
  assert.equal(nodes.html.getAttribute(ON), "plate-doc");
  assert.equal(nodes.jpg.getAttribute(ON), "plate-photo");
  assert.equal(nodes.pdfSquare.getAttribute(ON), "card-doc");
  const shots = [shotOf(nodes.html), shotOf(nodes.pdfSquare)];
  sized(nodes.ownImg);
  const photo = shotOf(nodes.jpg);
  for (const img of [...shots, nodes.ownImg]) assert.equal(loaded.inner.photoList().some(item => item.img === img), false, "снимок файла в списке фото");
  assert.equal(loaded.inner.photoAt(nodes.html), null, "plate-doc: нажатие раскрыло бы снимок");
  assert.equal(loaded.inner.photoAt(nodes.pdf), null, "card-doc: нажатие раскрыло бы снимок");
  assert.equal(loaded.inner.photoAt(nodes.own), null, "рендер Claude у HTML: нажатие раскрыло бы картинку");
  assert.equal(loaded.inner.photoAt(nodes.jpg), photo, "фото в плашке перестало быть фото");
});

test("#11304: нажатие по карточке HTML — сам файл в панель, а не снимок в просмотре фото", async () => {
  const { loaded, nodes } = page();
  loaded.inner.heicTick();
  await settle();
  shotOf(nodes.html);
  shotOf(nodes.jpg);
  loaded.calls.length = 0;
  press(loaded, nodes.html);
  assert.equal(loaded.inner.photoState.open, false, "открылся просмотр фото со снимком страницы");
  const asked = opens(loaded);
  assert.equal(asked.length, 1, `файл не открыт: ${loaded.calls.join(" | ")}`);
  assert.match(asked[0], /\/open-html\?mode=click/);
  assert.ok(asked[0].includes(`path=${encodeURIComponent(HTML)}`), asked[0]);
  // Фото — как было: просмотр 12л.
  loaded.calls.length = 0;
  press(loaded, nodes.jpg);
  assert.equal(loaded.inner.photoState.open, true, "фото в плашке не открылось просмотром");
  assert.equal(opens(loaded).length, 0);
  loaded.api.dispose();
});
