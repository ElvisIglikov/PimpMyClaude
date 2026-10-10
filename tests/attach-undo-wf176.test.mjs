// WF176: ⌘Z возвращает снятое вложение (#9193) и номер у каждого пути добавления
// скриншота (#9184).
// Элвис 09.10 02:35: «скриншот один удалил по случайке… ⌘Z не работает на
// удаление скриншотов. Сделай, чтобы можно было отменить ⌘Z».
// Элвис 08.10 21:06: «Что он не пронумеровался? Кстати, все скриншоты должны
// нумероваться, когда я их добавляю».
//
// Стенд — как в shot-numbers-wf120: события шлём на документ с нужной целью
// (стаб не всплывает); Claude изображает слушатель paste на поле — на каждый
// файл плитка с кнопкой «Remove <имя>».
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const ATTR = "data-myclaude-shot";
const CHAT_A = "https://claude.ai/epitaxy/local_a";
const CHAT_B = "https://claude.ai/epitaxy/local_b";

const tile = (box, name) => {
  const node = box.add("div", { attrs: { "data-cds-attachment": "", "data-cds": "MessageAttachmentsImage" } });
  node.add("img", { attrs: { src: `blob:claude/${name}` } });
  node.add("button", { attrs: { "aria-label": `Remove ${name}` } });
  return node;
};
const tick = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const page = ({ href = CHAT_A, box = true, claude = true } = {}) => {
  const loaded = loadInject({
    href,
    title: "PimpMyClaude",
    html: dom => {
      const parts = dom.composer();
      if (box) parts.box = parts.shell.add("div", { attrs: { "data-cds-composer-attachments": "" } });
      parts.line = parts.editor.add("p", { text: "" });
      return parts;
    },
  });
  assert.equal(loaded.error, null);
  tick(loaded);
  loaded.got = [];
  if (claude) loaded.parts.editor.addEventListener("paste", event => {
    const files = [...(event.clipboardData?.files ?? [])];
    loaded.got.push(files);
    // Первое вложение: коробки вложений у Claude до него нет — появляется с ним.
    loaded.parts.box ??= loaded.parts.shell.add("div", { attrs: { "data-cds-composer-attachments": "" } });
    for (const file of files) tile(loaded.parts.box, file.name);
  });
  return loaded;
};
const clip = (files, text = "") => ({ files, getData: type => (type === "text/plain" ? text : "") });
const paste = (loaded, files, target = loaded.parts.line) =>
  loaded.document.dispatchEvent({ type: "paste", target, isTrusted: true, cancelable: true, clipboardData: clip(files) });
const settle = loaded => loaded.inner.shotState.chain;
const tiles = loaded => [...loaded.parts.box.querySelectorAll("[data-cds-attachment]")];
const tileNames = loaded => tiles(loaded).map(node => node.querySelector("button").getAttribute("aria-label").slice(7));
const marks = loaded => tiles(loaded).map(node => node.getAttribute(ATTR));
// Крестик плитки: наш захват видит клик, Claude снимает плитку.
const cross = (loaded, index) => {
  const node = tiles(loaded)[index];
  const button = node.querySelector("button");
  loaded.document.dispatchEvent({ type: "click", target: button, isTrusted: true });
  node.remove();
  tick(loaded);
};
const key = (loaded, { shift = false, target = loaded.parts.line, code = "KeyZ", name = "z" } = {}) => {
  const passed = loaded.document.dispatchEvent({ type: "keydown", key: name, code, metaKey: true, shiftKey: shift, target, isTrusted: true, cancelable: true });
  tick(loaded);
  return { defaultPrevented: passed === false };
};
const undoState = loaded => loaded.api.status().attachUndo;

test("#9193: снятый крестиком скриншот возвращается по ⌘Z тем же файлом и с тем же номером", async () => {
  const loaded = page();
  for (const name of ["a.png", "b.png", "c.png"]) paste(loaded, [loaded.dom.image(name)]);
  await settle(loaded);
  tick(loaded);
  assert.deepEqual(marks(loaded), ["1", "2", "3"]);
  const second = loaded.got[1][0];

  cross(loaded, 1);
  assert.deepEqual(tileNames(loaded), ["Скриншот 1.png", "Скриншот 3.png"]);
  assert.equal(undoState(loaded).undo, 1, "снятое крестиком — в стеке отмены");

  // Полка «Обкэшить» убирает снятое со своей уборкой — стек держит File сам.
  loaded.inner.cashoutHome().shelf.splice(0);
  const event = key(loaded);
  assert.equal(event.defaultPrevented, true, "⌘Z забран: родная отмена текста не нужна");
  assert.equal(loaded.got.at(-1)[0], second, "вернулся тот же File — с номером в пикселях");
  assert.deepEqual(tileNames(loaded), ["Скриншот 1.png", "Скриншот 3.png", "Скриншот 2.png"]);
  assert.deepEqual(marks(loaded), ["1", "3", "2"], "номер на плитке — прежний");
  assert.equal(undoState(loaded).undo, 0);
  assert.equal(undoState(loaded).redo, 1);

  // Стек пуст — ⌘Z больше не наш: обычная отмена текста поля.
  const plain = key(loaded);
  assert.equal(plain.defaultPrevented, false);

  // Следующий новый снимок — 4: возврат счёт не трогает.
  paste(loaded, [loaded.dom.image("d.png")]);
  await settle(loaded);
  assert.equal(loaded.got.at(-1)[0].name, "Скриншот 4.png");
});

test("#9193: ⌘⇧Z снимает возвращённое снова, ⌘Z — возвращает опять; русская раскладка (code KeyZ)", async () => {
  const loaded = page();
  paste(loaded, [loaded.dom.image("a.png")]);
  await settle(loaded);
  tick(loaded);
  // Claude снимает плитку по нажатию её кнопки.
  const wire = () => {
    for (const node of tiles(loaded)) {
      const button = node.querySelector("button");
      if (button.__wired) continue;
      button.__wired = true;
      button.addEventListener("click", () => node.remove());
    }
  };
  wire();
  cross(loaded, 0);
  assert.deepEqual(tileNames(loaded), []);
  key(loaded, { name: "я" });
  assert.deepEqual(tileNames(loaded), ["Скриншот 1.png"]);
  wire();
  const redo = key(loaded, { shift: true, name: "Я" });
  assert.equal(redo.defaultPrevented, true);
  assert.deepEqual(tileNames(loaded), [], "⌘⇧Z — снова снято");
  assert.equal(undoState(loaded).undo, 1);
  key(loaded);
  assert.deepEqual(tileNames(loaded), ["Скриншот 1.png"]);
  assert.deepEqual(marks(loaded), ["1"]);
});

test("#9193: Backspace в поле снял плитку — ⌘Z возвращает; фокус ушёл с крестика — ⌘Z всё равно наш", async () => {
  const loaded = page();
  paste(loaded, [loaded.dom.image("a.png")]);
  await settle(loaded);
  // pdf не наш — Claude кладёт его сам; полка «Обкэшить» его запомнила.
  const pdf = loaded.dom.file("отчёт.pdf", { type: "application/pdf" });
  paste(loaded, [pdf]);
  tile(loaded.parts.box, pdf.name);
  tick(loaded);
  loaded.document.dispatchEvent({ type: "keydown", key: "Backspace", target: loaded.parts.line, isTrusted: true });
  tiles(loaded)[1].remove();
  tick(loaded);
  assert.equal(undoState(loaded).undo, 1);
  // После крестика фокус в никуда — целью приходит body.
  key(loaded, { target: loaded.document.body });
  assert.deepEqual(tileNames(loaded), ["Скриншот 1.png", "отчёт.pdf"], "pdf вернулся тоже");
});

test("#9193: текст правили после снятия — ⌘Z сперва отменяет текст (не перехватываем)", async () => {
  const loaded = page();
  paste(loaded, [loaded.dom.image("a.png")]);
  await settle(loaded);
  tick(loaded);
  cross(loaded, 0);
  loaded.parts.line.textContent = "дописал";
  const first = key(loaded);
  assert.equal(first.defaultPrevented, false, "это ⌘Z текста");
  assert.deepEqual(tileNames(loaded), []);
  // Родная отмена вернула текст к виду на момент снятия — теперь очередь вложения.
  loaded.parts.line.textContent = "";
  const second = key(loaded);
  assert.equal(second.defaultPrevented, true);
  assert.deepEqual(tileNames(loaded), ["Скриншот 1.png"]);
});

test("#9193: чужое поле (поиск) — ⌘Z его; отправка, иная пропажа плиток и смена чата очищают стек", async () => {
  const loaded = page();
  const search = loaded.document.body.add("input", { attrs: { type: "text" } });
  for (const name of ["a.png", "b.png"]) paste(loaded, [loaded.dom.image(name)]);
  await settle(loaded);
  tick(loaded);
  cross(loaded, 0);
  assert.equal(key(loaded, { target: search }).defaultPrevented, false, "поиск чатов — своя отмена");
  assert.equal(undoState(loaded).undo, 1);

  // Отправка: Enter глотает отсчёт 12у, сообщение уходит позже вместе с плитками —
  // плитки пропали без крестика, и стек уходит с ними.
  for (const node of tiles(loaded)) node.remove();
  tick(loaded);
  assert.equal(undoState(loaded).undo, 0);

  // Плитка пропала без крестика (ушла с сообщением, Claude очистил поле) — тоже прочь.
  paste(loaded, [loaded.dom.image("c.png")]);
  paste(loaded, [loaded.dom.image("c2.png")]);
  await settle(loaded);
  tick(loaded);
  cross(loaded, 0);
  assert.equal(undoState(loaded).undo, 1);
  for (const node of tiles(loaded)) node.remove();
  tick(loaded);
  assert.equal(undoState(loaded).undo, 0);
  assert.equal(key(loaded).defaultPrevented, false);

  // Смена чата.
  paste(loaded, [loaded.dom.image("d.png")]);
  await settle(loaded);
  tick(loaded);
  cross(loaded, 0);
  assert.equal(undoState(loaded).undo, 1);
  loaded.win.location.href = CHAT_B;
  loaded.win.location.pathname = "/epitaxy/local_b";
  tick(loaded);
  assert.equal(undoState(loaded).undo, 0);
  assert.equal(key(loaded).defaultPrevented, false);
});

test("#9193: Esc стек не трогает; dispose — очищает", async () => {
  const loaded = page();
  paste(loaded, [loaded.dom.image("a.png")]);
  await settle(loaded);
  tick(loaded);
  cross(loaded, 0);
  loaded.document.dispatchEvent({ type: "keydown", key: "Escape", target: loaded.parts.line, isTrusted: true });
  loaded.win.dispatchEvent({ type: "keydown", key: "Escape", isTrusted: true });
  tick(loaded);
  assert.equal(undoState(loaded).undo, 1);
  assert.equal(key(loaded).defaultPrevented, true);
  assert.deepEqual(tileNames(loaded), ["Скриншот 1.png"]);
  loaded.api.dispose();
  assert.equal(loaded.inner.attachUndo.redo.length, 0);
});

test("#9184: первый скриншот в пустом поле — коробки вложений ещё нет — получает номер на плитке", async () => {
  const loaded = page({ box: false });
  paste(loaded, [loaded.dom.image("first.png")]);
  await settle(loaded);
  tick(loaded);
  assert.equal(loaded.got[0][0].name, "Скриншот 1.png");
  assert.deepEqual(marks(loaded), ["1"]);
  paste(loaded, [loaded.dom.image("second.png")]);
  await settle(loaded);
  tick(loaded);
  assert.deepEqual(marks(loaded), ["1", "2"]);
});

test("#9184: первая плитка пересобирает поле (новый редактор) — номер всё равно встаёт, без плашки «не вставлен»", async () => {
  const loaded = page({ box: false, claude: false });
  // Claude на первом вложении пересобирает композер: старый редактор уходит,
  // плитка появляется позже и уже в новом блоке.
  const old = loaded.parts;
  old.editor.addEventListener("paste", event => {
    const files = [...event.clipboardData.files];
    loaded.got.push(files);
    queueMicrotask(() => {
      const next = loaded.dom.composer();
      next.line = next.editor.add("p", { text: "" });
      next.box = next.shell.add("div", { attrs: { "data-cds-composer-attachments": "" } });
      old.block.remove();
      loaded.parts = next;
      loaded.inner.onMutated([{ type: "childList", target: loaded.document.body, removedNodes: [old.block], addedNodes: [next.block] }]);
      for (const file of files) tile(next.box, file.name);
    });
  });
  paste(loaded, [loaded.dom.image("first.png")]);
  // Плитки ждут по таймеру — стаб крутит его руками, пока цепочка не кончится.
  let done = false;
  settle(loaded).then(() => { done = true; });
  for (let round = 0; round < 40 && !done; round += 1) {
    for (let i = 0; i < 12; i += 1) await Promise.resolve();
    loaded.dom.fireKind("timeout");
  }
  assert.equal(done, true);
  tick(loaded);
  assert.equal(loaded.got[0][0].name, "Скриншот 1.png");
  assert.deepEqual(marks(loaded), ["1"]);
  const note = loaded.document.getElementById("myclaude-new-window-note");
  assert.ok(!note || note.style.getPropertyValue("display") === "none" || !/не вставлен/.test(note.textContent),
    "картинка у Claude — плашка «не вставлен» была бы неправдой");
});

test("#9184: «+» Claude → файл: картинка едет в поле с номером, pdf и чужая синтетика — как есть", async () => {
  const loaded = page();
  const picker = loaded.parts.shell.add("input");
  picker.type = "file";
  picker.value = "C:\\fakepath\\shot.png";
  const native = [];
  loaded.document.addEventListener("change", event => native.push(event));
  picker.files = [loaded.dom.image("Снимок экрана.png")];
  loaded.document.dispatchEvent({ type: "change", target: picker, isTrusted: true });
  await settle(loaded);
  tick(loaded);
  assert.equal(native.length, 0, "Claude не видит оригинал — иначе две картинки");
  assert.equal(loaded.got[0][0].name, "Скриншот 1.png");
  assert.equal(picker.value, "", "поле выбора очищено: тот же файл выбирается снова");
  assert.deepEqual(marks(loaded), ["1"]);

  picker.files = [loaded.dom.file("отчёт.pdf", { type: "application/pdf" })];
  loaded.document.dispatchEvent({ type: "change", target: picker, isTrusted: true });
  assert.equal(native.length, 1, "pdf — к Claude как есть");
  picker.files = [loaded.dom.image("x.png")];
  loaded.document.dispatchEvent({ type: "change", target: picker });
  assert.equal(native.length, 2, "своя синтетика — не наша");

  // Поле выбора вне блока ввода (настройки, проект) — не трогаем.
  const other = loaded.document.body.add("input");
  other.type = "file";
  other.files = [loaded.dom.image("avatar.png")];
  loaded.document.dispatchEvent({ type: "change", target: other, isTrusted: true });
  assert.equal(native.length, 3);
});

test("#9184: новый чат — счёт под адресом страницы; Claude дал чату id с плитками в поле — номера остаются", async () => {
  const loaded = page({ href: "https://claude.ai/epitaxy" });
  paste(loaded, [loaded.dom.image("a.png")]);
  await settle(loaded);
  tick(loaded);
  assert.deepEqual(marks(loaded), ["1"]);
  loaded.win.location.href = CHAT_A;
  loaded.win.location.pathname = "/epitaxy/local_a";
  tick(loaded);
  assert.deepEqual(marks(loaded), ["1"], "черновик переехал вместе с плитками");
  paste(loaded, [loaded.dom.image("b.png")]);
  await settle(loaded);
  assert.equal(loaded.got.at(-1)[0].name, "Скриншот 2.png");
});
