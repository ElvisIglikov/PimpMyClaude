// #11310: перетаскивание картинки из Telegram в окно Claude не вставляет её.
// Слово Элвиса: «Я вот с Telegram беру картинку, перетаскиваю dragdrop в окно клауда.
// Она же должна вставляться… Какого хера она не вставляется?»
//
// Проверяется, что Пимп ЧУЖОЙ бросок (без своего маркера application/x-pimpmyclaude-drag)
// пропускает к родному обработчику Claude нетронутым: ни preventDefault, ни
// stopImmediatePropagation, ни dropEffect. Типы — какие кладут Telegram для macOS,
// Finder и браузеры: Files (при dragover files пустые), text/uri-list, text/html,
// public.file-url. Единственное, что Пимп берёт себе из чужого, — доверенный бросок
// png/jpeg/webp НА БЛОК ВВОДА (#7532, номер на скриншот): картинка всё равно
// доезжает в поле — пересланной вставкой «Скриншот N».
//
// Стенд: события шлём на document (стаб не всплывает); «Claude» — слушатель на
// document, поставленный после страницы: видит событие, только если мы его пропустили.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

// Плитка вложения, как у Claude: по ней Пимп узнаёт, что вставка доехала.
const tile = (box, name) => {
  const node = box.add("div", { attrs: { "data-cds-attachment": "", "data-cds": "MessageAttachmentsImage" } });
  node.add("img", { attrs: { src: `blob:claude/${name}` } });
  node.add("button", { attrs: { "aria-label": `Remove ${name}` } });
  return node;
};

const page = () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_tg",
    html: dom => {
      const parts = dom.composer();
      parts.box = parts.shell.add("div", { attrs: { "data-cds-composer-attachments": "" } });
      parts.feed = dom.document.body.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" },
        rect: { left: 100, top: 200, width: 1000, height: 300 },
      });
      parts.line = parts.editor.add("p", { text: "" });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
  loaded.native = [];
  for (const type of ["dragenter", "dragover", "drop"]) {
    loaded.document.addEventListener(type, event => loaded.native.push(event.type));
  }
  loaded.got = [];
  loaded.parts.editor.addEventListener("paste", event => {
    const files = [...(event.clipboardData?.files ?? [])];
    loaded.got.push(files.map(file => file.name));
    for (const file of files) tile(loaded.parts.box, file.name);
  });
  return loaded;
};

// dataTransfer как у Chromium: types, files, getData; dropEffect пишется обработчиком.
const transfer = (types, { files = [], data = {} } = {}) => ({
  types, files, dropEffect: "none", effectAllowed: "all",
  getData: type => data[type] ?? "",
});
const fire = (loaded, type, target, dataTransfer) =>
  loaded.document.dispatchEvent({ type, target, isTrusted: true, cancelable: true, bubbles: true, dataTransfer });

const FOREIGN = [
  ["Telegram: Files без файлов на dragover", ["Files"], {}],
  ["Telegram: file promise + uri-list", ["public.file-url", "text/uri-list"], { data: { "text/uri-list": "file:///Users/dev/Downloads/photo_2026-10-31.jpg" } }],
  ["браузер: картинка ссылкой и разметкой", ["text/uri-list", "text/html"], { data: { "text/html": "<img src=\"https://t.me/x.jpg\">" } }],
];

test("чужой бросок картинки: dragenter/dragover/drop на ленте и в поле доходят до Claude нетронутыми", () => {
  for (const [label, types, extra] of FOREIGN) {
    const loaded = page();
    for (const target of [loaded.parts.feed, loaded.parts.editor, loaded.parts.line, loaded.parts.modelRow]) {
      for (const type of ["dragenter", "dragover", "drop"]) {
        loaded.native.length = 0;
        const data = transfer(types, extra);
        assert.equal(fire(loaded, type, target, data), true, `${label}: ${type} погашен Пимпом`);
        assert.deepEqual(loaded.native, [type], `${label}: ${type} не дошёл до Claude`);
        assert.equal(data.dropEffect, "none", `${label}: ${type} — Пимп тронул dropEffect`);
      }
    }
    assert.deepEqual(loaded.got, [], `${label}: Пимп сам ничего не вставлял`);
  }
});

test("чужой бросок файла не-скриншотного типа (gif, heic, без типа) на блок ввода — дело Claude", () => {
  const loaded = page();
  for (const [name, type] of [["a.gif", "image/gif"], ["b.heic", "image/heic"], ["c", ""]]) {
    const file = loaded.dom.image(name, { type });
    loaded.native.length = 0;
    assert.equal(fire(loaded, "dragover", loaded.parts.modelRow, transfer(["Files"])), true);
    assert.equal(fire(loaded, "drop", loaded.parts.modelRow, transfer(["Files"], { files: [file] })), true, `${name}: погашен`);
    assert.deepEqual(loaded.native, ["dragover", "drop"], `${name}: не дошёл до Claude`);
  }
  assert.deepEqual(loaded.got, []);
});

test("доверенный бросок jpeg из Telegram на блок ввода: Пимп берёт его и картинка доезжает в поле с номером", async () => {
  const loaded = page();
  const file = loaded.dom.image("photo_2026-10-31.jpg", { type: "image/jpeg" });
  assert.equal(fire(loaded, "dragover", loaded.parts.modelRow, transfer(["Files"])), true, "dragover Пимп не трогает");
  assert.equal(fire(loaded, "drop", loaded.parts.modelRow, transfer(["Files"], { files: [file] })), false);
  await loaded.inner.shotState.chain;
  assert.deepEqual(loaded.got, [["Скриншот 1.jpg"]], "картинка обязана доехать в поле");
});
