// #11618: Claude на русском (config.json locale «ru», у Элвиса с 04.11.2026) — Пимп узнаёт кнопки и по русским
// подписям из каталога claude.ai. Скриншот: плитка «Удалить Скриншот 1.png» (или «Удалить: …») — доехала, плашки
// «Скриншот не вставлен…» нет; номер на плитке — из её имени. Строка модели: «Авто» → Au, «Усилия: Высокий» → Hi.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner } from "./load.mjs";

const NOTE = "myclaude-new-window-note";

const page = label => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_ru",
    title: "PimpMyClaude",
    html: dom => {
      const parts = dom.composer();
      parts.box = parts.shell.add("div", { attrs: { "data-cds-composer-attachments": "" } });
      parts.line = parts.editor.add("p", { text: "" });
      return parts;
    },
  });
  assert.equal(loaded.error, null);
  loaded.got = [];
  // Claude на русском: что пришло вставкой — плиткой с кнопкой «Удалить <имя>».
  loaded.parts.editor.addEventListener("paste", event => {
    for (const file of [...(event.clipboardData?.files ?? [])]) {
      loaded.got.push(file.name);
      const tile = loaded.parts.box.add("div", { attrs: { "data-cds-attachment": "", "data-cds": "MessageAttachmentsImage" } });
      tile.add("img", { attrs: { src: `blob:claude/${file.name}` } });
      tile.add("button", { attrs: { "aria-label": label(file.name) } });
    }
  });
  return loaded;
};
const tick = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const paste = (loaded, file) => loaded.document.dispatchEvent({
  type: "paste", target: loaded.parts.line, isTrusted: true, cancelable: true,
  clipboardData: { files: [file], getData: () => "" },
});
const note = loaded => {
  const node = loaded.document.getElementById(NOTE);
  return node && node.style.getPropertyValue("display") !== "none" ? node.textContent : null;
};

for (const [form, label] of [["«Удалить <имя>»", name => `Удалить ${name}`], ["«Удалить: <имя>»", name => `Удалить: ${name}`]]) {
  test(`#11618: скриншот в русском Claude — плитка ${form} доехала, плашки «не вставлен» нет`, async () => {
    const loaded = page(label);
    tick(loaded);
    paste(loaded, loaded.dom.image("a.png"));
    paste(loaded, loaded.dom.image("b.png", { width: 900, height: 600 }));
    await loaded.inner.shotState.chain;
    assert.deepEqual(loaded.got, ["Скриншот 1.png", "Скриншот 2.png"]);
    assert.equal(note(loaded), null, "плитка с русской подписью — та же плитка: без плашки SHOT_NOTE_LOST");
    tick(loaded);
    assert.deepEqual([...loaded.parts.box.querySelectorAll("[data-cds-attachment]")].map(node => node.getAttribute("data-myclaude-shot")),
      ["1", "2"], "номер плитки — из русского имени");
  });
}

test("#11618: подпись снятия вложения — на обоих языках; очередь сообщений — не вложение", () => {
  const { inner } = loadInner();
  for (const label of ["Remove a.png", "Удалить a.png", "Удалить: a.png"]) {
    assert.equal(inner.attachRemoveLabel(label), true, label);
    assert.equal(inner.attachRemoveName(label), "a.png", label);
  }
  for (const label of ["Remove queued message", "Удалить сообщение из очереди", "Удалённый", ""]) {
    assert.equal(inner.attachRemoveLabel(label), false, label);
  }
});

test("#11618: строка модели по-русски — «Авто» → Au, режимы и усилия — прежние коды", () => {
  const { inner } = loadInner();
  assert.deepEqual(["Авто", "Принимать правки", "План", "Обход разрешений"].map(inner.chinModeShort), ["Au", "Ac", "Pl", "By"]);
  assert.deepEqual(["Низкий", "Средний", "Высокий", "Сверхвысокий", "Максимальный"].map(inner.chinEffortShort),
    ["Lo", "Me", "Hi", "Ex", "Mx"]);
  assert.equal(inner.chinModeShort("Автор"), null, "чужое слово режимом не считаем");
});
