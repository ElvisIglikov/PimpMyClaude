// Три полоски: у верхнего края окна, на поле ввода и у нижнего края (#6743,
// слово Элвиса 20.09 и 21.09). С 21.09 они одна и та же полоска: общая ось,
// ширина и высота зоны захвата (#6891 — «все три должны быть соосными, все в
// одном месте… все одной толщиной»). Верхняя и нижняя — только нажималки:
// тянуть за них нельзя.
//
// Проверяется контракт раздела, а не разметка Claude:
//   1) полоски есть по одной, стоят у самых краёв окна и соосны полоске поля;
//   2) поле ушло вбок — ось всё равно одна на все три;
//   3) нажатие сворачивает поле, следующее — возвращает, и так подряд;
//   4) тянуть за них нельзя: нажатие мышью не начинает тягу;
//   5) свёрнутое поле — нижняя уступает основной: внизу одна полоска (#6892);
//   6) поля в окне нет — полосок нет вовсе;
//   7) нажатие с Shift повторяют все окна Claude разом (#6900);
//   8) dispose() уносит обе.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const TOP = "#myclaude-super-top";
const BOTTOM = "#myclaude-super-bottom";
const MAIN = "#myclaude-input-handle";
// Высота зоны захвата у всех трёх одна (HANDLE_HEIGHT в inject.js).
const RAIL_HEIGHT = 18;
const WIDTH = 1200;
const HEIGHT = 800;

const open = (composer = {}, geometry = { viewport: { width: WIDTH, height: HEIGHT } }) => loadInject({
  title: "Trelvis",
  html: dom => dom.composer({ top: 620, ...composer }),
  geometry,
});
const px = (node, name) => Number(String(node.style.getPropertyValue(name)).replace("px", ""));
const seat = (loaded, selector) => {
  const node = loaded.dom.query(selector);
  return { left: px(node, "left"), width: px(node, "width"), top: px(node, "top") };
};
// Проход раскладки планируется через таймер, потом кадр (как в layout.test.mjs).
const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};

test("полоски по одной, у самых краёв окна и соосны полоске поля", () => {
  const loaded = open();
  const top = loaded.dom.query(TOP);
  const bottom = loaded.dom.query(BOTTOM);
  assert.ok(top && bottom, "полосок у краёв окна нет");
  assert.equal(loaded.dom.queryAll(TOP).length, 1);
  assert.equal(loaded.dom.queryAll(BOTTOM).length, 1);
  assert.equal(top.style.getPropertyValue("display"), "flex");
  assert.equal(bottom.style.getPropertyValue("display"), "flex");

  // Соосны и одной ширины — с полоской поля и между собой.
  const main = seat(loaded, MAIN);
  assert.deepEqual(
    { left: seat(loaded, TOP).left, width: seat(loaded, TOP).width },
    { left: main.left, width: main.width },
    "верхняя не соосна полоске поля",
  );
  assert.deepEqual(
    { left: seat(loaded, BOTTOM).left, width: seat(loaded, BOTTOM).width },
    { left: main.left, width: main.width },
    "нижняя не соосна полоске поля",
  );
  assert.equal(main.width % 2, 0, "нечётная ширина уводит полоску с оси на полточки");
  assert.equal(seat(loaded, TOP).top, 0, "верхняя не у самого верха");
  assert.equal(seat(loaded, BOTTOM).top + RAIL_HEIGHT, HEIGHT, "нижняя не у самого низа");
  assert.equal(loaded.api.status().superVisible, true);
  assert.equal(loaded.api.status().superBottomVisible, true);

  // Совсем узкое окно: полоски ужимаются по полю, а не вылезают за него.
  const narrow = open({ left: 10, width: 260 }, { viewport: { width: 300, height: 600 } });
  const slim = seat(narrow, TOP);
  assert.ok(slim.width <= 260, `в узком окне полоска шире поля: ${slim.width}`);
  assert.ok(slim.left >= 0);
  assert.equal(slim.width, seat(narrow, MAIN).width, "и в узком окне ширина у всех одна");
});

test("поле ушло вбок — ось всё равно одна на все три", () => {
  // Поле у правого края окна: центр окна до него не достаёт, и по центру окна
  // полоска села бы на боковую панель. Ось прижимается к полю — все три вместе.
  const loaded = open({ left: 900, width: 280 });
  settle(loaded);
  const main = seat(loaded, MAIN);
  assert.equal(seat(loaded, TOP).left, main.left, "верхняя уехала со своей оси");
  assert.equal(seat(loaded, BOTTOM).left, main.left, "нижняя уехала со своей оси");
  assert.ok(main.left >= 900, `полоска сошла с поля: left ${main.left}`);
  assert.ok(main.left + main.width <= 1180, `полоска вылезла за поле: right ${main.left + main.width}`);
});

test("нажатие сворачивает поле, следующее возвращает — и так подряд", () => {
  const loaded = open();
  const top = loaded.dom.query(TOP);
  const bottom = loaded.dom.query(BOTTOM);
  assert.equal(loaded.api.stage, loaded.api.stages.NORMAL);
  bottom.dispatchEvent({ type: "click", detail: 1 });
  assert.equal(loaded.api.stage, loaded.api.stages.COLLAPSED, "нижняя не свернула поле");
  bottom.dispatchEvent({ type: "click", detail: 1 });
  assert.equal(loaded.api.stage, loaded.api.stages.NORMAL, "нижняя не вернула поле");
  top.dispatchEvent({ type: "click", detail: 1 });
  assert.equal(loaded.api.stage, loaded.api.stages.COLLAPSED, "верхняя не свернула поле");
  // Подряд, без ожидания двойного клика: полоски у краёв не «двоят».
  top.dispatchEvent({ type: "click", detail: 1 });
  top.dispatchEvent({ type: "click", detail: 1 });
  assert.equal(loaded.api.stage, loaded.api.stages.COLLAPSED);
});

test("тянуть за них нельзя: нажатие мышью поле не двигает", () => {
  const loaded = open();
  const bottom = loaded.dom.query(BOTTOM);
  const before = loaded.api.status();
  bottom.dispatchEvent({ type: "pointerdown", clientY: HEIGHT - 4, button: 0, pointerId: 1 });
  loaded.dom.document.dispatchEvent({ type: "pointermove", clientY: HEIGHT - 200, buttons: 1, pointerId: 1 });
  const after = loaded.api.status();
  assert.equal(after.stage, before.stage, "за дубль потянули поле");
  assert.equal(after.height, before.height, "за дубль изменили высоту поля");
});

test("свёрнутое поле: внизу одна полоска — нижняя уступает основной (#6892)", () => {
  const loaded = open();
  loaded.api.setStage(loaded.api.stages.COLLAPSED);
  assert.equal(loaded.dom.query(BOTTOM).style.getPropertyValue("display"), "none",
    "нижняя осталась под основной — две линии в точку друг от друга");
  assert.equal(loaded.api.status().superBottomVisible, false);
  // Основная на месте: вернуть поле есть чем. В живом окне она у самой нижней
  // кромки (режим чтения прячет строку модели), в стенде — на кромке строки
  // модели; куда именно она садится, проверяет stage.test.mjs.
  const main = seat(loaded, MAIN);
  assert.equal(loaded.dom.query(MAIN).style.getPropertyValue("display"), "flex");
  // Верхняя никуда не девается: ею поле возвращают с другого края окна.
  assert.equal(loaded.dom.query(TOP).style.getPropertyValue("display"), "flex");
  assert.equal(seat(loaded, TOP).left, main.left, "и верхняя соосна свёрнутой основной");

  // Поле вернули — вернулась и нижняя.
  loaded.api.setStage(loaded.api.stages.NORMAL);
  assert.equal(loaded.dom.query(BOTTOM).style.getPropertyValue("display"), "flex");
});

test("поля ввода в окне нет — полосок тоже нет", () => {
  const bare = loadInject({ title: "Trelvis", geometry: { viewport: { width: WIDTH, height: HEIGHT } } });
  assert.equal(bare.dom.query(TOP).style.getPropertyValue("display"), "none");
  assert.equal(bare.api.status().superVisible, false);
});

test("Shift по полоске: шаг повторяют все окна Claude разом (#6900)", () => {
  const first = open();
  const second = open();
  assert.equal(first.api.stage, first.api.stages.NORMAL);
  assert.equal(second.api.stage, second.api.stages.NORMAL);

  // Обычное нажатие — только своё окно.
  first.dom.query(TOP).dispatchEvent({ type: "click", detail: 1 });
  assert.equal(first.api.stage, first.api.stages.COLLAPSED);
  assert.equal(second.api.stage, second.api.stages.NORMAL, "обычное нажатие тронуло соседнее окно");

  // С Shift — соседнее окно повторяет ступень ЭТОГО окна, а не свою.
  first.dom.query(TOP).dispatchEvent({ type: "click", detail: 1, shiftKey: true });
  assert.equal(first.api.stage, first.api.stages.NORMAL);
  assert.equal(second.api.stage, second.api.stages.NORMAL);
  first.dom.query(BOTTOM).dispatchEvent({ type: "click", detail: 1, shiftKey: true });
  assert.equal(first.api.stage, first.api.stages.COLLAPSED);
  assert.equal(second.api.stage, second.api.stages.COLLAPSED, "нижняя с Shift не дошла до соседнего окна");

  // Полоска поля с Shift шагает так же и ждать двойного клика не заставляет.
  first.dom.query(MAIN).dispatchEvent({ type: "click", detail: 1, shiftKey: true });
  assert.equal(first.api.stage, first.api.stages.NORMAL);
  assert.equal(second.api.stage, second.api.stages.NORMAL, "полоска поля с Shift не дошла до соседнего окна");

  // Окно сняли — чужие команды ему больше не приходят.
  second.api.dispose();
  first.dom.query(MAIN).dispatchEvent({ type: "click", detail: 1, shiftKey: true });
  assert.equal(first.api.stage, first.api.stages.COLLAPSED, "своё окно шагает и в одиночку");
});

test("dispose(): обе полоски уходят из окна", () => {
  const loaded = open();
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(TOP).length, 0);
  assert.equal(loaded.dom.queryAll(BOTTOM).length, 0);
});
