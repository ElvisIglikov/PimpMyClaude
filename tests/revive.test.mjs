// Возврат к наблюдению после отказа (задача #5474).
//
// Окно «Open in new window» рождается пустым about:blank, а чат въезжает в него
// позже. Сторож GIVE_UP_MS (60 с) признавал такую страницу чужой и снимал
// наблюдателей НАВСЕГДА: у окна «Bro Flow продолжение» (05.09) поле ввода к
// тому времени ещё не приехало, а когда приехало — будить страницу было уже
// нечем. Снаружи это выглядело как «полоска прогресса не рисуется»:
// status().progress.reason === «нет блока композера» при живом [contenteditable].
//
// Здесь проверяется весь путь: отказ → дешёвая сторожевая проверка → возврат.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const GIVE_UP_MS = 60000;
const REVIVE_MS = 5000;
// Строка состояния из SkilZZZ/AGENTS.md: без неё полосе нечего рисовать.
const STATUS_LINE = "💭🟣[Trelvis](docs/status.md) · WF 3 из 8 · идёт💭";

// Пустая страница на about:blank — ровно то, чем окно попапа живёт первые
// секунды: ни .ProseMirror, ни .epitaxy-prompt, и URL не claude.ai.
const emptyPopout = () => loadInject({ href: "about:blank", title: "Bro Flow продолжение" });

const timerId = (loaded, kind, ms) => {
  for (const [id, item] of loaded.dom.timers.entries()) {
    if (item.kind === kind && item.ms === ms) return id;
  }
  return null;
};

// Проход планируется не сразу, а через LAYOUT_MIN_GAP: сперва отложенный
// таймер, потом кадр. Прокручиваем оба, иначе геометрию никто не пересчитает.
const settle = loaded => {
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};

test("сторож чужой страницы: пустой попап перестаёт наблюдаться", () => {
  const loaded = emptyPopout();
  assert.equal(loaded.api.status().watching, true, "до срока сторожа страница наблюдается");
  const giveUp = timerId(loaded, "timeout", GIVE_UP_MS);
  assert.notEqual(giveUp, null, "таймер отказа не поставлен");
  loaded.dom.fire(giveUp);
  assert.equal(loaded.api.status().watching, false, "пустая страница осталась под наблюдением");
  assert.notEqual(timerId(loaded, "interval", REVIVE_MS), null,
    "после отказа не осталось сторожевой проверки — страницу нечем будить");
});

test("разметка приехала позже отказа — страница просыпается и находит блок", () => {
  const loaded = emptyPopout();
  loaded.dom.fire(timerId(loaded, "timeout", GIVE_UP_MS));
  assert.equal(loaded.api.status().watching, false);

  // Чат въехал в окно: composer собрался, строка состояния в ленте есть.
  loaded.dom.composer({ top: 620 });
  const revive = timerId(loaded, "interval", REVIVE_MS);
  assert.notEqual(revive, null, "сторожевой проверки нет");
  loaded.dom.fire(revive);
  settle(loaded);

  const status = loaded.api.status();
  assert.equal(status.watching, true, "разметка Claude приехала, а страница не проснулась");
  assert.equal(status.composerBlock, true, "блок композера не нашёлся после пробуждения");
  assert.equal(status.editor, true, "поле ввода не нашлось после пробуждения");
  assert.equal(status.progress.reason !== "нет блока композера", true,
    "полоса всё ещё считает, что блока композера нет");
  assert.equal(timerId(loaded, "interval", REVIVE_MS), null,
    "сторожевая проверка не снялась после пробуждения");
});

test("проснувшаяся страница рисует полосу по строке состояния", () => {
  const loaded = emptyPopout();
  loaded.dom.fire(timerId(loaded, "timeout", GIVE_UP_MS));
  const parts = loaded.dom.composer({ top: 620 });
  // Ответ со строкой состояния — там же, где его ищет раздел 2б.
  loaded.document.body.add("div", {
    class: "font-claude-response",
    rect: { left: 100, top: 100, width: 1000, height: 200 },
    text: `Готово.\n${STATUS_LINE}`,
  });
  loaded.dom.fire(timerId(loaded, "interval", REVIVE_MS));
  settle(loaded);

  const status = loaded.api.status();
  assert.equal(status.watching, true);
  assert.equal(status.progress.reason, null, `полосы нет: ${status.progress.reason}`);
  assert.equal(status.progress.wf, 3, "номер воркфлоу вычитан неверно");
  assert.equal(status.progress.of, 8, "число воркфлоу вычитано неверно");
  assert.equal(status.progress.segments.length > 0, true, "сегментов не нарисовано");
  assert.equal(parts.block.isConnected, true);
});

test("dispose снимает сторожевую проверку вместе со всем остальным", () => {
  const loaded = emptyPopout();
  loaded.dom.fire(timerId(loaded, "timeout", GIVE_UP_MS));
  assert.notEqual(timerId(loaded, "interval", REVIVE_MS), null);
  loaded.api.dispose();
  assert.equal(timerId(loaded, "interval", REVIVE_MS), null,
    "после dispose остался интервал сторожевой проверки — окно копит таймеры");
});

test("страница claude.ai сторожем не трогается и проверки не заводит", () => {
  const loaded = loadInject({ href: "https://claude.ai/epitaxy/local_test" });
  loaded.dom.fire(timerId(loaded, "timeout", GIVE_UP_MS));
  assert.equal(loaded.api.status().watching, true, "своя страница попала под отказ");
  assert.equal(timerId(loaded, "interval", REVIVE_MS), null,
    "на своей странице завелась лишняя сторожевая проверка");
});
