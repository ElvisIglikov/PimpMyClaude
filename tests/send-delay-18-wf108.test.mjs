// WF119: единственная спокойная цифра; с WF128 (К1 v3) — вид 1.5, выбранный ключом v2.
// Отправка и её защиты — send-delay-wf105, aliases и preview — send-look-wf114.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const DIGITS = "myclaude-send-delay-digits";
const page = () => loadInject({
  storage: { local: { "myclaude-send-look-v2": JSON.stringify({ style: "1.5", size: 100 }) } },
  html: dom => {
    const parts = dom.composer({ text: "привет" });
    parts.send = parts.modelRow.add("button", { attrs: { "data-testid": "code-prompt-send" },
      rect: { left: 260, top: 700, width: 24, height: 24 } });
    parts.enters = 0;
    parts.editor.addEventListener("keydown", event => {
      if (event.key === "Enter") { parts.enters += 1; parts.editor.__text = ""; }
    });
    return parts;
  },
});
const enter = p => p.document.dispatchEvent({ type: "keydown", key: "Enter", target: p.parts.editor, isTrusted: true });
const advance = (p, n) => { for (let i = 0; i < n; i++) p.dom.fireKind("timeout"); };
const digits = p => p.document.getElementById(DIGITS);
const quiet = p => {
  assert.equal(p.document.querySelectorAll("#myclaude-send-delay-rocket,.myclaude-send-look-fly").length, 0);
  assert.equal(p.dom.animations.filter(a => a.node.id.startsWith("myclaude-send-")).length, 0);
};

test("спокойная цифра: один неподвижный узел ровно на кнопке, только секунды в тексте", () => {
  const p = page();
  assert.equal(p.error, null);
  enter(p);
  const node = digits(p);
  assert.equal(node.getAttribute("role"), "timer");
  assert.equal(node.title, "Отменить отправку");
  assert.equal(node.textContent, "3", "по умолчанию — 3 с (слово Элвиса 07.10)");
  assert.equal(node.children.length, 0);
  assert.equal(node.style.getPropertyValue("pointer-events"), "auto");
  assert.deepEqual(["left", "top", "width", "height"].map(k => node.style.getPropertyValue(k)), ["260px", "700px", "24px", "24px"]);
  assert.notEqual(node.style.getPropertyValue("background"), node.style.getPropertyValue("color"));
  advance(p, 1);
  assert.ok(digits(p) === node);
  assert.equal(node.textContent, "2");
  quiet(p);
  p.api.dispose();
});

test("отпускание отправляет один раз, цифра гаснет без полёта", () => {
  const p = page(); enter(p); advance(p, 5);
  assert.equal(p.parts.enters, 1);
  assert.equal(digits(p).style.getPropertyValue("display"), "none");
  quiet(p); p.api.dispose();
});

test("холодный чат: красный фон и белая цифра, предупреждение сохранено", () => {
  const p = page();
  p.inner.sigState.chat = "local_test";
  p.inner.sigState.lastAt = Date.now() - 61 * 60000;
  p.win.fetch = () => Promise.resolve({});
  enter(p);
  assert.equal(digits(p).style.getPropertyValue("background"), "#e5484d");
  assert.equal(digits(p).style.getPropertyValue("color"), "#ffffff");
  assert.match(p.document.getElementById("myclaude-send-delay").textContent, /Кеш остыл/);
  quiet(p); p.api.dispose();
});

test("Esc отменяет; reduced-motion тоже без эффектов; dispose/reinject убирают сирот", () => {
  const p = page(); p.win.__reducedMotion = true; enter(p);
  p.win.dispatchEvent({ type: "keydown", key: "Escape", target: p.parts.editor, isTrusted: true });
  advance(p, 5);
  assert.equal(p.parts.enters, 0);
  quiet(p);
  p.document.body.add("div", { attrs: { id: "myclaude-send-delay-rocket" } });
  p.document.body.add("div", { class: "myclaude-send-look-fly" });
  assert.equal(p.reload().error, null);
  assert.equal(digits(p), null); quiet(p);
  enter(p); p.api.dispose();
  assert.equal(digits(p), null);
});
