// Слои примерки (WF31, задача #5453): новая примерка перекрывает предыдущую.
// Слово Элвиса: «когда я цвета выбираю, не надо мне из темы Пудра показывать
// шрифты. Цвет выбирается со стандартным шрифтом, который сейчас стоит. Также и
// шрифт — с тем, что установлено». До WF31 примеренные слои копились до самого
// закрытия меню: проехал по «🔤 Шрифт ▸» — и все цвета дальше смотрелись чужим
// шрифтом. Теперь `themeState.previewLayers` помнит примеренное, и слой, которого
// в новой команде нет, возвращается из хранилища (раздел 2а inject.js).
//
// Проверяем настоящим путём: команда идёт через dom.command, экран читается
// dom.sheets(), состояние — api.status(). Источник слоя («preview» против
// «chat») и есть доказательство: «preview» — на экране примерка, «chat» — окно
// вернулось к сохранённому.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, injectSource } from "./load.mjs";

const MAP_KEY = "myclaude-themes-v1";

const theme = (id, accent) => ({
  id, name: id, type: "dark",
  palette: { accent, background: "#001122", foreground: "#eeffff", sidebar: "#000811", panel: "#00223a", muted: "#88aabb" },
});
const font = family => ({ id: family, family, mono: false });

// Сохранённое окно: «то, что сейчас установлено» из слов Элвиса.
const SAVED_THEME = theme("сохранённая", "#2299ff");
const SAVED_FONT = font("Menlo");
const PUDRA = theme("пудра", "#ee88aa");
const NOTEWORTHY = font("Noteworthy");

const painted = () => loadInject({
  title: "Trelvis",
  storage: { local: { [MAP_KEY]: JSON.stringify({ "chat:Trelvis": { theme: SAVED_THEME, font: SAVED_FONT, size: { answer: 18 } } }) } },
});

let seq = 0;
const send = (loaded, detail) => loaded.dom.command({
  id: `wf31-${++seq}`, action: "theme", at: "now", scope: "window", title: "Trelvis", ...detail,
});

test("примерка цвета не трогает шрифт", () => {
  const loaded = painted();
  send(loaded, { preview: true, theme: PUDRA });
  const status = loaded.api.status();
  assert.equal(status.theme.id, "пудра", "цвет примерен");
  assert.equal(status.theme.source, "preview");
  assert.equal(status.preview, true);
  assert.equal(status.font.family, "Menlo", "шрифт остался установленный");
  assert.equal(status.font.source, "chat", "шрифт по-прежнему из хранилища, а не из примерки");
  assert.equal(status.size.answer, 18, "размер не тронут");
  assert.ok(loaded.dom.sheets().includes("Menlo"), "на экране тот же шрифт");
  assert.ok(loaded.dom.sheets().includes("#ee88aa"), "на экране пудровый акцент");
});

test("новая примерка возвращает прежний примеренный слой", () => {
  // Шрифт → цвет: цвет смотрится с УСТАНОВЛЕННЫМ шрифтом.
  const one = painted();
  send(one, { preview: true, font: NOTEWORTHY });
  assert.equal(one.api.status().font.family, "Noteworthy", "шрифт примерен");
  assert.equal(one.api.status().font.source, "preview");
  send(one, { preview: true, theme: PUDRA });
  const after = one.api.status();
  assert.equal(after.theme.id, "пудра", "новый цвет на экране");
  assert.equal(after.theme.source, "preview");
  assert.equal(after.font.family, "Menlo", "рукописный шрифт ушёл вместе с прежней примеркой");
  assert.equal(after.font.source, "chat");
  assert.equal(after.preview, true, "примерка идёт дальше");
  assert.ok(!one.dom.sheets().includes("Noteworthy"), "на экране чужого шрифта не осталось");

  // Цвет → шрифт: шрифт смотрится с УСТАНОВЛЕННЫМ цветом.
  const two = painted();
  send(two, { preview: true, theme: PUDRA });
  send(two, { preview: true, font: NOTEWORTHY });
  const back = two.api.status();
  assert.equal(back.font.family, "Noteworthy", "новый шрифт на экране");
  assert.equal(back.font.source, "preview");
  assert.equal(back.theme.id, "сохранённая", "цвет вернулся к установленному");
  assert.equal(back.theme.source, "chat");
  assert.ok(!two.dom.sheets().includes("#ee88aa"), "пудровый акцент с экрана ушёл");

  // Тот же слой подряд (мышь ведут по списку цветов) — возвращать нечего.
  const three = painted();
  send(three, { preview: true, theme: PUDRA });
  send(three, { preview: true, theme: theme("арктика", "#66ddee") });
  assert.equal(three.api.status().theme.id, "арктика");
  assert.equal(three.api.status().font.family, "Menlo", "шрифт всё это время установленный");
});

test("конец примерки возвращает всё", () => {
  const loaded = painted();
  send(loaded, { preview: true, font: NOTEWORTHY });
  send(loaded, { preview: true, theme: PUDRA });
  send(loaded, { preview: false });
  const status = loaded.api.status();
  assert.equal(status.preview, false, "примерки нет");
  assert.equal(status.theme.id, "сохранённая");
  assert.equal(status.theme.source, "chat");
  assert.equal(status.font.family, "Menlo");
  assert.equal(status.font.source, "chat");
  assert.equal(status.size.answer, 18);
  send(loaded, { preview: false });
  assert.deepEqual(loaded.api.status().theme.id, "сохранённая", "второй «конец примерки» ничего не ломает");
  assert.equal(loaded.api.status().preview, false);
  // Список примеренного обнулён: следующая примерка одного слоя второго не трогает.
  send(loaded, { preview: true, font: NOTEWORTHY });
  assert.equal(loaded.api.status().font.family, "Noteworthy");
  assert.equal(loaded.api.status().theme.id, "сохранённая");
});

test("закрепление гасит остальное", () => {
  const loaded = painted();
  send(loaded, { preview: true, theme: PUDRA });
  // Обычная команда шрифта (клик по пункту): endPreviewExcept возвращает цвет.
  send(loaded, { font: NOTEWORTHY });
  const status = loaded.api.status();
  assert.equal(status.font.family, "Noteworthy", "шрифт закреплён");
  assert.equal(status.font.source, "window");
  assert.equal(status.theme.id, "сохранённая", "примеренный цвет вернулся из хранилища");
  assert.equal(status.theme.source, "chat");
  assert.equal(status.preview, false);
  const stored = JSON.parse(loaded.win.localStorage.getItem(MAP_KEY))["chat:Trelvis"];
  assert.equal(stored.font.family, "Noteworthy", "в хранилище лёг только закреплённый слой");
  assert.equal(stored.theme.id, "сохранённая", "примерка в хранилище не попала");
  // После закрепления список примеренного пуст: новая примерка цвета шрифт не сносит.
  send(loaded, { preview: true, theme: PUDRA });
  assert.equal(loaded.api.status().font.family, "Noteworthy", "закреплённый шрифт на месте");
});

test("примерка, адресованная чужому окну, наших слоёв не трогает", () => {
  const loaded = painted();
  send(loaded, { preview: true, font: NOTEWORTHY });
  loaded.dom.command({
    id: "wf31-чужая", action: "theme", at: "now", scope: "window", title: "Другое окно", preview: true, theme: PUDRA,
  });
  const status = loaded.api.status();
  assert.equal(status.font.family, "Noteworthy", "наша примерка жива");
  assert.equal(status.font.source, "preview");
  assert.equal(status.theme.id, "сохранённая", "чужой цвет к нам не приехал");
  assert.equal(status.preview, true);
  // Список примеренного чужая команда тоже не переписала: своя примерка цвета
  // по-прежнему возвращает наш шрифт.
  send(loaded, { preview: true, theme: PUDRA });
  assert.equal(loaded.api.status().font.family, "Menlo", "шрифт вернулся из хранилища");
});

test("status() не расширен, обнуление стоит во всех трёх местах", () => {
  const loaded = painted();
  assert.ok(!("previewLayers" in loaded.api.status()), "список слоёв наружу не торчит — контракт status() прежний");

  const source = injectSource();
  // Обнуление живёт рядом с КАЖДЫМ гашением примерки: endPreviewExcept, ветка
  // preview:false и «любая другая команда закрывает примерку» (раздел 15).
  const offs = [...source.matchAll(/themeState\.previewing = false;/g)].map(match => match.index);
  assert.equal(offs.length, 3, "мест, где гаснет примерка, по-прежнему три");
  for (const at of offs) {
    assert.match(source.slice(at, at + 160), /themeState\.previewLayers = \[\];/,
      `рядом с гашением примерки (смещение ${at}) не обнуляется previewLayers`);
  }

  // Возврат непокрытых слоёв стоит ПОСЛЕ guard (иначе чужая команда красила бы
  // наше окно) и ДО applyLayers (иначе возврат стёр бы только что примеренное).
  const branch = source.slice(source.indexOf("if (detail.preview === true) {"));
  const guard = branch.indexOf("if (Object.keys(layers).length === 0 || !addressed(detail)) return false;");
  const rest = branch.indexOf("const rest = themeState.previewLayers.filter(layer => !(layer in layers));");
  const restore = branch.indexOf("if (rest.length) restoreTheme(true, rest);");
  const apply = branch.indexOf('applyLayers(layers, "preview");');
  assert.ok(guard >= 0 && rest > guard, "возврат слоёв обязан стоять после guard адресации");
  assert.ok(restore > rest && apply > restore, "возврат обязан стоять до applyLayers");
  assert.match(source, /const VERSION = "wf\d+-[a-z]-\d+";/, "метка версии на месте");
});
