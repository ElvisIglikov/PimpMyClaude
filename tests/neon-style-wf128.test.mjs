// Вид неоновой рамки (WF128, К2, #9042): команда `neon-style` всем окнам —
// {id, action, at, strength 0…100, blur 0…40, edge 0…6}; вне диапазона — зажим,
// не число — команда мимо. Умолчание тише прежнего: 55/14/1; прежний вид —
// 100/18/2, им по-прежнему светят «ждёт тебя» и «говорю» (frameShadow без
// второго параметра). Память — localStorage["myclaude-neon-style-v1"].
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const MAP_KEY = "myclaude-themes-v1";
const KEY = "myclaude-neon-style-v1";
const open = (local = {}) => loadInject({
  title: "Trelvis",
  storage: { local: { [MAP_KEY]: JSON.stringify({ "chat:Trelvis": { frame: true } }), ...local } },
});
const shadow = loaded => loaded.document.querySelector("#myclaude-window-frame").style.getPropertyValue("box-shadow");
const style = loaded => JSON.parse(JSON.stringify(loaded.api.status().neonStyle));
let seq = 0;
const neon = (loaded, fields) => loaded.dom.command({ id: `wf128-neon-${++seq}`, action: "neon-style", at: "now", ...fields });

test("по умолчанию рамка тише: сила 55, размытие 14, грань 1", () => {
  const loaded = open();
  assert.deepEqual(style(loaded), { strength: 55, blur: 14, edge: 1 });
  const value = shadow(loaded);
  assert.match(value, /^inset 0 0 0 1px color-mix\(in oklab, .+ 55%, transparent\), inset 0 0 14px .+, inset 0 0 5px /);
});

test("команда меняет рамку сразу и запоминается всем окнам; 100 — прежний чистый цвет", () => {
  const loaded = open();
  neon(loaded, { strength: 100, blur: 18, edge: 2 });
  assert.deepEqual(style(loaded), { strength: 100, blur: 18, edge: 2 });
  assert.ok(!shadow(loaded).includes("color-mix"), "на максимуме — прежний вид без примеси");
  assert.match(shadow(loaded), /^inset 0 0 0 2px .+, inset 0 0 18px .+, inset 0 0 6px /);
  assert.deepEqual(JSON.parse(loaded.win.localStorage.getItem(KEY)), { strength: 100, blur: 18, edge: 2 });
  const next = open({ [KEY]: loaded.win.localStorage.getItem(KEY) });
  assert.deepEqual(style(next), { strength: 100, blur: 18, edge: 2 }, "новое окно берёт из памяти");
});

test("вне диапазона — зажим, дробь — к целому; не число — команда мимо целиком", () => {
  const loaded = open();
  neon(loaded, { strength: 250, blur: -3, edge: 2.6 });
  assert.deepEqual(style(loaded), { strength: 100, blur: 0, edge: 3 });
  neon(loaded, { strength: "50", blur: 10, edge: 1 });
  neon(loaded, { strength: 50, blur: 10 });
  neon(loaded, { strength: 50, blur: Number.NaN, edge: 1 });
  assert.deepEqual(style(loaded), { strength: 100, blur: 0, edge: 3 }, "мусор ничего не тронул");
});

test("мусор в памяти — умолчание; frameShadow без вида — прежние 100/18/2", () => {
  const loaded = open({ [KEY]: "{не json" });
  assert.deepEqual(style(loaded), { strength: 55, blur: 14, edge: 1 });
  const { frameShadow, neonStyleOk, NEON_STYLE_DEFAULT } = loaded.inner;
  assert.equal(frameShadow("#ff8800"), "inset 0 0 0 2px #ff8800, inset 0 0 18px #ff8800, inset 0 0 6px #ff8800");
  assert.equal(neonStyleOk(null), null);
  assert.deepEqual({ ...NEON_STYLE_DEFAULT }, { strength: 55, blur: 14, edge: 1 });
});

test("рамка выключена — команда только запоминает вид", () => {
  const loaded = loadInject({ title: "Trelvis" });
  neon(loaded, { strength: 30, blur: 8, edge: 0 });
  assert.equal(loaded.api.status().frame.on, false);
  assert.equal(shadow(loaded), "");
  assert.deepEqual(JSON.parse(loaded.win.localStorage.getItem(KEY)), { strength: 30, blur: 8, edge: 0 });
});
