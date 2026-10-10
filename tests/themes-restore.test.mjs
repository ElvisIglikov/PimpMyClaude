// Возврат тем после переустановки Claude — команда themes-restore (раздел 2а
// inject.js, план WF35, задача #5473). Переустановка Claude стирает localStorage
// страниц, и пять окон Элвиса становятся серыми. Копию карты приложение держит
// на диске (window-themes.json) и присылает одной командой на все окна:
//   {id, action:"themes-restore", at, scope:"all", entries:{<ключ>:{theme?,font?,size?,frame?}}}
//
// Главное правило — страница НЕ заменяет свою память присланной, а доливает
// недостающие СЛОИ. Отсюда идемпотентность: память цела — команда не меняет ни
// байта, и спрашивать окно «ты пуста?» не нужно вовсе.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const MAP_KEY = "myclaude-themes-v1";
const ID_KEY = "id:local_test";

const theme = (id, accent = "#2299ff") => ({
  id, name: id, type: "dark",
  palette: { accent, background: "#001122", foreground: "#eeffff", sidebar: "#000811", panel: "#00223a", muted: "#88aabb" },
});
const font = (family = "SF Mono") => ({ id: family, family, mono: true });
const map = value => ({ [MAP_KEY]: JSON.stringify(value) });
const readMap = win => JSON.parse(win.localStorage.getItem(MAP_KEY) ?? "null");
const rawMap = win => win.localStorage.getItem(MAP_KEY);
const restore = (entries, extra = {}) =>
  ({ id: "r1", action: "themes-restore", at: "now", scope: "all", entries, ...extra });

// Живые цвета — ровно та же команда, что в tests/live-colors.test.mjs.
const ring = Array.from({ length: 12 }, (unused, index) => ({
  accent: `#${(index * 0x10).toString(16).padStart(2, "0")}0000`,
  background: "#001010", foreground: "#ffffff", sidebar: "#111111", panel: "#222222", muted: "#888888",
}));
const liveCommand = {
  id: "L1", action: "live-colors", at: "now", scope: "all", on: true,
  mode: "solo", period: 300, epoch: Date.now(), light: false,
  titles: ["Trelvis"], ring: { dark: ring, light: ring },
};

test("доливает недостающий ключ и красит окно", () => {
  const loaded = loadInject({ title: "Trelvis" });
  assert.equal(loaded.api.status().theme.id, null, "до команды окно серое");
  loaded.dom.command(restore({ "chat:Trelvis": { theme: theme("вернулась") } }));
  const status = loaded.api.status();
  assert.equal(status.theme.id, "вернулась");
  assert.equal(status.theme.source, "chat");
  assert.equal(readMap(loaded.win)["chat:Trelvis"].theme.id, "вернулась", "ключ лёг в localStorage");
  assert.equal(status.restore.keys, 1);
  assert.equal(status.restore.merged, 1);
  assert.equal(status.restore.painted, true);
  assert.equal(typeof status.restore.at, "number");
});

test("свой слой страницы сильнее присланного", () => {
  const loaded = loadInject({
    title: "Trelvis",
    storage: { local: map({ "chat:Trelvis": { theme: theme("своя") } }) },
  });
  loaded.dom.command(restore({ "chat:Trelvis": { theme: theme("присланная") } }));
  assert.equal(loaded.api.status().theme.id, "своя");
  assert.equal(readMap(loaded.win)["chat:Trelvis"].theme.id, "своя");
  assert.equal(loaded.api.status().restore.merged, 0, "доливать было нечего");
});

test("доливается по слоям, а не по записи", () => {
  const loaded = loadInject({
    title: "Trelvis",
    storage: { local: map({ "chat:Trelvis": { font: font("Menlo") } }) },
  });
  loaded.dom.command(restore({ "chat:Trelvis": { theme: theme("присланная"), font: font("Monaco") } }));
  const entry = readMap(loaded.win)["chat:Trelvis"];
  assert.equal(entry.theme.id, "присланная", "недостающий слой долит");
  assert.equal(entry.font.family, "Menlo", "свой слой не тронут");
  assert.equal(loaded.api.status().restore.merged, 1);
});

test("«none» из команды остаётся сбросом", () => {
  const loaded = loadInject({ title: "Trelvis", storage: { local: map({ "*": { theme: theme("всем") } }) } });
  assert.equal(loaded.api.status().theme.id, "всем");
  loaded.dom.command(restore({ "chat:Trelvis": { theme: "none" } }));
  assert.equal(loaded.api.status().theme.id, null, "«Как у Claude» пережило переустановку");
  assert.equal(readMap(loaded.win)["chat:Trelvis"].theme, "none");
});

test("мусор отбрасывается, валидное из той же команды принимается", () => {
  const loaded = loadInject({ title: "Trelvis" });
  const longKey = `chat:${"я".repeat(200)}`;
  loaded.dom.command(restore({
    hack: { theme: theme("чужой ключ") },
    "": { theme: theme("пустой ключ") },
    "chat:": { theme: theme("префикс без имени") },
    [longKey]: { theme: theme("длинный ключ") },
    "chat:Строка": "не объект",
    "chat:Слой": { theme: "мусор", font: 42 },
    "chat:Хороший": { theme: theme("годная") },
  }));
  const stored = readMap(loaded.win);
  assert.deepEqual(Object.keys(stored), ["chat:Хороший"]);
  assert.equal(stored["chat:Хороший"].theme.id, "годная");
});

test("потолок 200 ключей", () => {
  const loaded = loadInject({ title: "Trelvis" });
  const entries = {};
  for (let index = 0; index < 250; index += 1) entries[`chat:Чат ${index}`] = { theme: theme(`т${index}`) };
  loaded.dom.command(restore(entries));
  const stored = readMap(loaded.win);
  assert.equal(Object.keys(stored).length, 200, "лишние ключи отброшены");
  assert.equal(loaded.api.status().restore.keys, 200);
  assert.equal(stored["chat:Чат 0"].theme.id, "т0", "карта осталась валидным JSON");
});

test("примерка не гасится и экран не трогается", () => {
  const loaded = loadInject({ title: "Trelvis" });
  loaded.dom.command({ id: "p1", action: "theme", at: "now", scope: "window", title: "Trelvis", preview: true, theme: theme("примерка") });
  assert.equal(loaded.api.status().preview, true);
  loaded.dom.command(restore({ "chat:Trelvis": { theme: theme("присланная") } }));
  const status = loaded.api.status();
  assert.equal(status.preview, true, "подменю под рукой у Элвиса не закрылось");
  assert.equal(status.theme.id, "примерка", "на экране прежний примеренный цвет");
  assert.equal(status.restore.painted, false);
  assert.equal(readMap(loaded.win)["chat:Trelvis"].theme.id, "присланная", "карта долита");
});

test("живые цвета не перебиваются", () => {
  const loaded = loadInject({ title: "Trelvis" });
  loaded.dom.command(liveCommand);
  const before = loaded.api.status().theme.id;
  assert.equal(loaded.api.status().theme.source, "live");
  loaded.dom.command(restore({ "chat:Trelvis": { theme: theme("присланная") } }));
  const status = loaded.api.status();
  assert.equal(status.theme.source, "live", "крутёж на экране остался");
  assert.equal(status.theme.id, before);
  assert.equal(status.restore.painted, false);
  assert.equal(readMap(loaded.win)["chat:Trelvis"].theme.id, "присланная", "карта долита");
});

test("команда идемпотентна", () => {
  const loaded = loadInject({ title: "Trelvis" });
  const entries = {
    "chat:Trelvis": { theme: theme("цвет"), font: font("Menlo") },
    main: { size: { answer: 16 } },
    "*": { frame: true },
  };
  loaded.dom.command(restore(entries));
  const first = rawMap(loaded.win);
  loaded.dom.command(restore(entries, { id: "r2" }));
  assert.equal(rawMap(loaded.win), first, "карта после второго раза байт в байт та же");
  assert.equal(loaded.api.status().restore.merged, 0, "второй раз доливать нечего");
});

test("чужая страница команду не берёт", () => {
  const loaded = loadInject({ title: "Артефакт", href: "data:text/html,<p>артефакт</p>" });
  loaded.dom.command(restore({ "chat:Trelvis": { theme: theme("присланная") } }));
  assert.equal(rawMap(loaded.win), null, "карта не тронута");
  assert.equal(loaded.api.status().restore.at, null, "команды тут не было вовсе");
});

test("запись по id тоже принимается и красит окно", () => {
  const loaded = loadInject({ title: "Trelvis" });
  loaded.dom.command(restore({ [ID_KEY]: { theme: theme("по id") }, "chat:Trelvis": { theme: theme("по имени") } }));
  assert.equal(loaded.api.status().theme.id, "по id", "id сильнее имени и после возврата");
  assert.deepEqual(Object.keys(readMap(loaded.win)).sort(), [ID_KEY, "chat:Trelvis"].sort());
});
