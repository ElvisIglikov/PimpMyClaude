// ⌘V из любого места окна (WF64, задача #6030). Слово Элвиса: «можно, я в любом
// месте Command V буду нажимать, и он будет вставлять ебучий скриншот».
//
// До WF64 вставка доставалась тому узлу, где стоит курсор: Элвис копировал
// скриншот, кликал в ленте разговора, жал ⌘V — и не происходило ничего.
//
// Здесь проверяется контракт двух дорог из раздела 12 inject.js:
//   1) ⌘V мимо поля — курсор молча встаёт в поле ввода, и больше НИЧЕГО
//      (ни отмены события, ни синтетики: дальше работает родная вставка Claude);
//   2) если вставка всё же пришла в страницу мимо поля — файлы пересылаются в
//      поле свежим DataTransfer, а текст из буфера не трогается вовсе.
// И то, чего дороги делать не смеют: лезть в чужие поля (поиск чатов Claude),
// ловить собственное пересланное событие, оставаться на чужой странице и
// переживать dispose().
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

// Страница окна Claude: поле ввода, лента разговора (по ней Элвис и кликает
// перед ⌘V), чужое поле поиска чатов и вложенный <p> ВНУТРИ поля ввода —
// именно он приходит целью, когда вставляют в само поле.
const page = ({ href, title = "PimpMyClaude" } = {}) =>
  loadInject({
    href,
    title,
    html: dom => {
      const parts = dom.composer();
      parts.transcript = dom.document.body.add("div", {
        attrs: { "data-testid": "assistant-message" },
        rect: { left: 100, top: 200, width: 1000, height: 300 },
        text: "Последний ответ Claude.",
      });
      parts.search = dom.document.body.add("input", { attrs: { type: "text" } });
      parts.line = parts.editor.add("p", { text: "" });
      return parts;
    },
  });

// Вставка, как её отдаёт браузер: цель — узел под курсором, в буфере файлы
// и/или текст. dispatchEvent возвращает false, если событие отменили, — по нему
// и видно, забрали мы вставку себе или отпустили штатным ходом.
const firePaste = (loaded, { target, files = [], text = "" }) =>
  loaded.document.dispatchEvent({
    type: "paste",
    target,
    clipboardData: { files, getData: () => text },
  });

const fireKey = (loaded, { target, key = "v", code = "KeyV", metaKey = true }) =>
  loaded.document.dispatchEvent({ type: "keydown", key, code, metaKey, target });

// Что доехало в поле ввода: имена файлов каждой пришедшей туда вставки.
const watchEditor = loaded => {
  const seen = [];
  loaded.parts.editor.addEventListener("paste", event => {
    seen.push([...(event.clipboardData?.files ?? [])].map(file => file.name));
  });
  return seen;
};

// Подписки самого document по виду события: общий счётчик стаба сюда не годится
// — тест вешает на поле ввода своего наблюдателя, и в общем числе он неотличим.
const listeners = (loaded, type) => (loaded.document.__listeners.get(type) ?? []).length;

test("⌘V в ленте разговора: скриншот уезжает в поле ввода", () => {
  const loaded = page();
  const seen = watchEditor(loaded);
  const file = loaded.dom.file("снимок.png");
  const passed = firePaste(loaded, { target: loaded.parts.transcript, files: [file] });

  assert.deepEqual(seen, [["снимок.png"]], "вставка не доехала до поля ввода");
  assert.equal(passed, false, "исходную вставку обязаны забрать себе: иначе файл приедет дважды");
  assert.equal(loaded.document.activeElement, loaded.parts.editor, "курсор встал в поле ввода");
});

test("цель внутри поля ввода: пересылки нет — вставка и так пришла куда надо", () => {
  const loaded = page();
  const seen = watchEditor(loaded);
  // Цель — вложенный <p> самого ProseMirror, а не сам редактор: потому цель и
  // проверяется через closest, а не matches.
  const passed = firePaste(loaded, { target: loaded.parts.line, files: [loaded.dom.file("снимок.png")] });

  assert.deepEqual(seen, [], "своя же вставка переслана второй раз");
  assert.equal(passed, true, "родную вставку в поле отменять нельзя");
});

test("цель в поиске чатов: чужое поле не трогаем вовсе", () => {
  const loaded = page();
  const seen = watchEditor(loaded);
  const passed = firePaste(loaded, { target: loaded.parts.search, files: [loaded.dom.file("снимок.png")] });

  assert.deepEqual(seen, [], "вставка в поиск чатов уехала в поле ввода");
  assert.equal(passed, true, "вставка в поиск чатов отменена");
  assert.notEqual(loaded.document.activeElement, loaded.parts.editor, "курсор увели из поиска чатов");
});

test("в буфере только текст: не пересылаем ничего", () => {
  const loaded = page();
  const seen = watchEditor(loaded);
  const passed = firePaste(loaded, { target: loaded.parts.transcript, text: "чужая ссылка" });

  assert.deepEqual(seen, [], "текст из буфера уехал в черновик — откатить его нечем");
  assert.equal(passed, true, "вставку текста отменять не за что");
});

test("своё пересланное событие ловим один раз: сторож — флаг, а не isTrusted", () => {
  const loaded = page();
  const seen = [];
  // Настоящее событие всплывает от поля обратно до document, и наш же
  // обработчик на захвате видит его снова. Стаб всплытия не делает — повторяем
  // его руками, иначе сторож не проверялся бы ничем.
  loaded.parts.editor.addEventListener("paste", event => {
    seen.push([...(event.clipboardData?.files ?? [])].map(file => file.name));
    loaded.document.dispatchEvent(event);
  });
  firePaste(loaded, { target: loaded.parts.transcript, files: [loaded.dom.file("снимок.png")] });

  assert.deepEqual(seen, [["снимок.png"]], "пересылка зациклилась: файл приехал в поле не один раз");
});

test("⌘V мимо поля ставит курсор в поле — и больше ничего", () => {
  const loaded = page();
  const seen = watchEditor(loaded);
  const passed = fireKey(loaded, { target: loaded.parts.transcript });

  assert.equal(loaded.document.activeElement, loaded.parts.editor, "курсор не встал в поле ввода");
  assert.equal(passed, true, "клавишу отменять нельзя — вставку дальше делает сам Claude");
  assert.deepEqual(seen, [], "на клавише синтетических вставок не шлём");

  // Курсор уводит только ⌘V: иначе поле забирало бы фокус на любой клавише.
  loaded.document.activeElement = null;
  fireKey(loaded, { target: loaded.parts.transcript, key: "c", code: "KeyC" });
  assert.equal(loaded.document.activeElement, null, "фокус увела клавиша, которая не ⌘V");
});

// Элвис сидит в русской раскладке, и там та же клавиша отдаёт key «м»: по одному
// key дорога 1 у него не срабатывала бы никогда, и весь ⌘V держался бы на
// запасной дороге. Приметы две, хватает любой — code от раскладки не зависит.
test("русская раскладка: ⌘V узнаётся по code, а не по букве", () => {
  const loaded = page();
  fireKey(loaded, { target: loaded.parts.transcript, key: "м", code: "KeyV" });
  assert.equal(loaded.document.activeElement, loaded.parts.editor, "курсор не встал в поле ввода");

  // А чужая клавиша с ⌘ фокус по-прежнему не уводит — ни буквой, ни кодом.
  loaded.document.activeElement = null;
  fireKey(loaded, { target: loaded.parts.transcript, key: "с", code: "KeyC" });
  assert.equal(loaded.document.activeElement, null, "фокус увела клавиша, которая не ⌘V");
});

test("⌘V в поиске чатов: курсор оттуда не уводим", () => {
  const loaded = page();
  loaded.document.activeElement = loaded.parts.search;
  fireKey(loaded, { target: loaded.parts.search });

  assert.equal(loaded.document.activeElement, loaded.parts.search, "курсор уехал из поиска чатов в поле ввода");
});

test("на чужой странице подписок нет вовсе", () => {
  const mine = page();
  const alien = page({ href: "data:text/html,<p>артефакт</p>", title: "Артефакт" });
  assert.equal(alien.error, null, "чужая страница инжект не роняет");

  assert.equal(listeners(mine, "keydown"), 1, "в окне Claude клавиша слушается");
  assert.equal(listeners(alien, "keydown"), 0, "на чужой странице клавишу слушать незачем");
  assert.equal(listeners(alien, "paste"), listeners(mine, "paste") - 1,
    "на чужой странице осталась только прежняя подписка вложений");

  const seen = watchEditor(alien);
  const passed = firePaste(alien, { target: alien.parts.transcript, files: [alien.dom.file("снимок.png")] });
  assert.deepEqual(seen, [], "чужая страница переслала вставку");
  assert.equal(passed, true, "чужая страница отменила вставку");
});

test("dispose(): обе подписки сняты", () => {
  const loaded = page();
  assert.ok(listeners(loaded, "keydown") > 0 && listeners(loaded, "paste") > 0, "подписки встали");
  loaded.api.dispose();
  assert.equal(listeners(loaded, "keydown"), 0, "клавиша осталась подписанной после dispose");
  assert.equal(listeners(loaded, "paste"), 0, "вставка осталась подписанной после dispose");
});
