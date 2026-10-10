// «Автосвёртка» (#6666): сообщение ушло — поле ввода само сворачивается.
// Флаг ставит команда `auto-collapse`; без него Enter ничего не сворачивает.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const open = () => loadInject({
  html: dom => dom.composer({ top: 620 }),
  title: "Trelvis",
  geometry: { viewport: { width: 1200, height: 800 } },
});
// Enter в непустом поле, затем Claude забирает текст — так выглядит отправка.
const send = loaded => {
  const { editor } = loaded.parts;
  editor.textContent = "привет";
  loaded.dom.document.dispatchEvent({ type: "keydown", key: "Enter", target: editor });
  editor.textContent = "";
  loaded.dom.fireKind("timeout");
};

test("автосвёртка выключена: отправка поле не трогает", () => {
  const loaded = open();
  const before = loaded.api.stage;
  send(loaded);
  assert.equal(loaded.api.stage, before);
  assert.equal(loaded.api.status().autoCollapse, false);
});

test("автосвёртка включена: после отправки поле свёрнуто, выключена снова — нет", () => {
  const loaded = open();
  loaded.dom.command({ action: "auto-collapse", on: "true" });
  assert.equal(loaded.api.status().autoCollapse, true);
  send(loaded);
  assert.equal(loaded.api.stage, loaded.api.stages.COLLAPSED, "поле свернулось само");

  loaded.api.setStage(loaded.api.stages.NORMAL);
  loaded.dom.command({ action: "auto-collapse", on: "false" });
  send(loaded);
  assert.equal(loaded.api.stage, loaded.api.stages.NORMAL, "выключили — не сворачивает");
});

test("Enter, который ничего не отправил (текст остался), поле не сворачивает", () => {
  const loaded = open();
  loaded.dom.command({ action: "auto-collapse", on: "true" });
  const { editor } = loaded.parts;
  editor.textContent = "/com";
  loaded.dom.document.dispatchEvent({ type: "keydown", key: "Enter", target: editor });
  loaded.dom.fireKind("timeout");
  assert.notEqual(loaded.api.stage, loaded.api.stages.COLLAPSED);
});
