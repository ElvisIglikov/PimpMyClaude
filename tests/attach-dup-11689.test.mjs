// #11689: слово Элвиса 05.11 ~18:13 — «Картинка была вставлена, я диктовку начал, она опять вставляется… Ты каждый
// раз перед вставкой проверяй, картинка вставлена ли уже или нет». Журнал Диктатора: снимок shot-18 вставлен файлом
// из папки снимков («Снимок 2026-11-05 в 18.13.08-762774.png»), через 3 с на старте записи Диктатор понёс его же
// копией из стопки («shot-2026-11-05-18-13-08-763337.png») — байты те же (sha256 сверен), имя другое. К-ATTACH-DUP
// сверял только ключ «вес:тип:имя» — и пропустил. Теперь сверяется ещё содержимое.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const NOTE = "myclaude-new-window-note";
const DUP = "Эти файлы уже в поле — второй раз не кладу";

const tile = (box, name) => {
  const node = box.add("div", { attrs: { "data-cds-attachment": "", "data-cds": "MessageAttachmentsImage" } });
  node.add("img", { attrs: { src: `blob:claude/${name}` } });
  node.add("button", { attrs: { "aria-label": `Remove ${name}` } });
  return node;
};
const page = () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_a",
    title: "PimpMyClaude",
    html: dom => {
      const parts = dom.composer();
      parts.box = parts.shell.add("div", { attrs: { "data-cds-composer-attachments": "" } });
      parts.line = parts.editor.add("p", { text: "" });
      return parts;
    },
  });
  assert.equal(loaded.error, null);
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
  loaded.got = [];
  loaded.parts.editor.addEventListener("paste", event => {
    const files = [...(event.clipboardData?.files ?? [])];
    loaded.got.push(files.map(file => file.name));
    for (const file of files) tile(loaded.parts.box, file.name);
  });
  return loaded;
};
const paste = async (loaded, files) => {
  loaded.document.dispatchEvent({
    type: "paste", target: loaded.parts.line, isTrusted: true, cancelable: true,
    clipboardData: { files, getData: () => "" },
  });
  await loaded.inner.shotState.chain;
};
const note = loaded => {
  const node = loaded.document.getElementById(NOTE);
  return node && node.style.getPropertyValue("display") !== "none" ? node.textContent : null;
};
const tiles = loaded => [...loaded.parts.box.querySelectorAll("button")].map(node => node.getAttribute("aria-label").slice(7));
const BYTES = "PNG снимка 3248×2160 — одни и те же байты";

test("тот же снимок под другим именем (Диктатор на старте записи) — второй раз в поле не ложится", async () => {
  const loaded = page();
  await paste(loaded, [loaded.dom.image("Снимок 2026-11-05 в 18.13.08-762774.png", { width: 3248, height: 2160, body: BYTES })]);
  assert.deepEqual(tiles(loaded), ["Скриншот 1.png"]);

  await paste(loaded, [loaded.dom.image("shot-2026-11-05-18-13-08-763337.png", { width: 3248, height: 2160, body: BYTES })]);
  assert.deepEqual(tiles(loaded), ["Скриншот 1.png"], "ровно жалоба Элвиса: картинка вставлялась второй раз");
  assert.equal(loaded.got.length, 1);
  assert.equal(note(loaded), DUP);
  const dup = plain(loaded.api.status().attachDup);
  assert.equal(dup.skipped, 1);
  assert.equal(dup.last.where, "shot");
  assert.deepEqual(dup.last.names, ["shot-2026-11-05-18-13-08-763337.png"]);

  // Следующий снимок Элвиса — 2, без дыры в счёте.
  await paste(loaded, [loaded.dom.image("Снимок 2026-11-05 в 18.13.30-591545.png", { width: 199, height: 61 })]);
  assert.deepEqual(tiles(loaded), ["Скриншот 1.png", "Скриншот 2.png"]);
  loaded.api.dispose();
});

test("два разных снимка одного веса и типа — оба в поле", async () => {
  const loaded = page();
  await paste(loaded, [loaded.dom.image("image.png", { body: "AAAAAAAA" })]);
  await paste(loaded, [loaded.dom.image("image.png", { body: "BBBBBBBB" })]);
  assert.deepEqual(tiles(loaded), ["Скриншот 1.png", "Скриншот 2.png"]);
  assert.equal(plain(loaded.api.status().attachDup).skipped, 0);
  loaded.api.dispose();
});

test("один снимок дважды в одной вставке — едет один раз", async () => {
  const loaded = page();
  await paste(loaded, [loaded.dom.image("a.png", { body: BYTES }), loaded.dom.image("b.png", { body: BYTES })]);
  assert.deepEqual(tiles(loaded), ["Скриншот 1.png"]);
  assert.deepEqual(plain(loaded.api.status().attachDup).last.names, ["b.png"]);
  loaded.api.dispose();
});

test("значок без номера под другим именем — тоже дубль; снял плитку — вставляется снова", async () => {
  const loaded = page();
  await paste(loaded, [loaded.dom.image("icon.png", { width: 32, height: 32, body: "иконка" })]);
  assert.deepEqual(tiles(loaded), ["icon.png"], "значок кладётся как есть");
  await paste(loaded, [loaded.dom.image("icon copy.png", { width: 32, height: 32, body: "иконка" })]);
  assert.deepEqual(tiles(loaded), ["icon.png"]);

  loaded.parts.box.children[0].remove();
  await paste(loaded, [loaded.dom.image("icon copy.png", { width: 32, height: 32, body: "иконка" })]);
  assert.deepEqual(tiles(loaded), ["icon copy.png"], "в поле его уже нет — вставка законная");
  loaded.api.dispose();
});
