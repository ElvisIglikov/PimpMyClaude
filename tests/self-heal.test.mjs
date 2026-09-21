// Самовосстановление узлов Пимпа (раздел 16 inject.js, WF78, задача #6766).
//
// Слово Элвиса 21.09 00:35: «в окне ChinaAI поля ввода нету и элементов
// управления… разобраться, чтобы в будущем так не происходило». Разбор живьём:
// Claude пересобрал содержимое body попапа, у body остался один ребёнок из
// шести — наши узлы уехали вместе со старым деревом. Страница этого не
// замечала: status().handleVisible отвечал «полоска есть», хотя узла в
// документе не было, и возвращалось всё только повторным запуском инжекта.
//
// Проверяется:
//   1) снесли узлы из body — следующий круг сторожа вернул их все, по одному;
//   2) вернувшаяся полоска снова работает: клик по ней разворачивает поле;
//   3) handleVisible считается по ЖИВОМУ узлу, а не по одному только display;
//   4) счётчик status().restored растёт ровно на число возвращённых узлов, а на
//      здоровом окне не растёт вовсе;
//   5) dispose() после восстановления уносит всё — ни узлов, ни таймеров.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const HEARTBEAT_MS = 500;
// Девять узлов, которые инжект держит в окне (тот же список, что стережёт
// tests/idempotent.test.mjs). Карточка сегмента живёт внутри подсказки.
const NODE_IDS = [
  "myclaude-input-handle",
  "myclaude-super-top",
  "myclaude-super-bottom",
  "myclaude-mic",
  "myclaude-side-rail",
  "myclaude-progress-bar",
  "myclaude-progress-tip",
  "myclaude-progress-card",
  "myclaude-window-frame",
];
const STATUS_LINE = "💭🟣[Trelvis](docs/status.md) · WF 3 из 8 · 70%💭";

const open = () => loadInject({
  title: "Trelvis",
  html: dom => {
    const parts = dom.composer({ top: 620 });
    dom.document.body.add("div", {
      attrs: { "data-testid": "assistant-message" },
      rect: { left: 100, top: 200, width: 1000, height: 300 },
      text: `Готово.\n\n${STATUS_LINE}`,
    });
    return parts;
  },
  geometry: { viewport: { width: 1200, height: 800 } },
});

const beat = loaded => {
  for (const [id, item] of [...loaded.dom.timers.entries()]) {
    if (item.kind === "interval" && item.ms === HEARTBEAT_MS) loaded.dom.fire(id);
  }
};
const found = loaded => Object.fromEntries(NODE_IDS.map(id => [id, loaded.dom.queryAll(`#${id}`).length]));
const one = Object.fromEntries(NODE_IDS.map(id => [id, 1]));
// Претензия Claude на body: он пересоздал содержимое окна и снёс всё, что в нём
// было, вместе с нашими узлами.
const wipeBody = loaded => {
  const body = loaded.document.body;
  const gone = [...body.childNodes];
  for (const node of gone) body.removeChild(node);
  return gone;
};

test("узлы снесли из body — круг сторожа вернул их все по одному", () => {
  const loaded = open();
  assert.deepEqual(found(loaded), one, "до сноса узлов должно быть по одному");
  wipeBody(loaded);
  assert.deepEqual(found(loaded), Object.fromEntries(NODE_IDS.map(id => [id, 0])), "снос не удался");

  beat(loaded);
  assert.deepEqual(found(loaded), one, "сторож не вернул узлы Пимпа в body");
  // Считаются узлы, возвращённые в body: карточка сегмента приезжает внутри
  // своей коробки-подсказки, отдельной записи ей не нужно.
  assert.equal(loaded.api.status().restored, NODE_IDS.length - 1, "вернулось не столько узлов, сколько пропало");
});

test("карточка сегмента вылетела из подсказки — сторож вернул её на место", () => {
  const loaded = open();
  const card = loaded.dom.query("#myclaude-progress-card");
  card.remove();
  assert.equal(loaded.dom.queryAll("#myclaude-progress-card").length, 0, "снос не удался");
  beat(loaded);
  assert.equal(card.parentElement?.id, "myclaude-progress-tip", "карточка вернулась не в подсказку");
  assert.equal(loaded.api.status().restored, 1);
});

test("вернувшаяся полоска работает: клик по ней сворачивает поле", () => {
  const loaded = open();
  const parts = loaded.parts;
  // Композер возвращаем на место: его снёс тот же удар по body.
  wipeBody(loaded);
  loaded.document.body.appendChild(parts.block);
  beat(loaded);

  const handle = loaded.dom.query("#myclaude-input-handle");
  assert.ok(handle, "полоски нет");
  assert.equal(handle.isConnected, true);
  handle.dispatchEvent({ type: "click", detail: 1 });
  loaded.dom.fireKind("timeout");
  assert.equal(loaded.api.stage, loaded.api.stages.COLLAPSED, "подписки вернувшейся полоски мертвы");
});

test("handleVisible считается по живому узлу, а не по одному display", () => {
  const loaded = open();
  const handle = loaded.dom.query("#myclaude-input-handle");
  assert.equal(loaded.api.status().handleVisible, true, "на здоровом окне полоска видна");
  // Узел вынесло из документа, а его display остался прежним: до WF78 status()
  // в этом месте врал.
  handle.remove();
  assert.equal(handle.style.display, "flex", "в стенде display остался прежним — иначе проверка пустая");
  assert.equal(loaded.api.status().handleVisible, false, "status() всё ещё считает пропавшую полоску видимой");
  beat(loaded);
  assert.equal(loaded.api.status().handleVisible, true, "сторож не вернул полоску");
});

test("на здоровом окне сторож ничего не трогает: restored остаётся нулём", () => {
  const loaded = open();
  beat(loaded);
  beat(loaded);
  assert.equal(loaded.api.status().restored, 0, "сторож перекладывает узлы без нужды");
  assert.deepEqual(found(loaded), one);
});

test("dispose() после восстановления уносит и узлы, и таймеры", () => {
  const loaded = open();
  wipeBody(loaded);
  beat(loaded);
  assert.deepEqual(found(loaded), one);
  loaded.api.dispose();
  assert.deepEqual({ ...loaded.counters }, { listeners: 0, observers: 0, timers: 0, intervals: 0, rafs: 0, sheets: 0 },
    "после dispose живых подписок и таймеров быть не должно");
  assert.deepEqual(found(loaded), Object.fromEntries(NODE_IDS.map(id => [id, 0])), "узлы остались в окне");
});
