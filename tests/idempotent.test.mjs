// Сторож идемпотентности (план WF24, решение 4) — сердце набора.
//
// Лоадер v6 перезапускает inject.js в той же странице на каждое изменение файла
// и на каждый dom-ready: за рабочий день это десятки прогонов в одном окне.
// Файл обязан снимать сам себя первой строкой (`window.__myclaude?.dispose?.()`,
// inject.js:43) и уходить без следа по `dispose()`. Регресс здесь видно только
// глазами и только через час работы — окно с двумя полосками, залипший курсор
// `col-resize`, не снятый интервал. Ловит его этот файл.
//
// Все девять проверок гоняются на одном окне-стабе с настоящей геометрией:
// нулевые прямоугольники сделали бы «одну полоску» зелёной на выдуманной
// странице (план, п. 9).
//
// Проверка «умеет ли сторож краснеть» — снять `track(...)` у `on()` на КОПИИ
// inject.js и прогнать по ней: `MYCLAUDE_INJECT=/путь/копия.js node --test
// tests/idempotent.test.mjs`. Боевой файл при этом не трогается.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

// Четыре узла, которые инжект держит в окне. Ручка ставится разделом 9, полоса
// прогресса и подсказка — разделом 2б, рамка окна — разделом 2а; узлы живут
// независимо от того, включён ли слой, поэтому счёт «ровно один» верен всегда.
const NODE_IDS = [
  "myclaude-input-handle",
  "myclaude-progress-bar",
  "myclaude-progress-tip",
  "myclaude-window-frame",
];
// Атрибуты подмены высоты поля: раздел 7 ставит их на редактор, dispose обязан
// снять все три вместе с переменной.
const EDITOR_ATTRIBUTES = "[data-myclaude-editor-root],[data-myclaude-editor],[data-myclaude-composer-block]";
const HEIGHT_VARIABLE = "--myclaude-input-height";
const THEME_STYLE_ID = "myclaude-theme";
const MAP_KEY = "myclaude-themes-v1";
const HEIGHT_KEY = "myclaude-input-height-v1";
const STAGE_KEY = "myclaude-input-stage-v1";
// Строка состояния из SkilZZZ/AGENTS.md: без неё полоса прогресса прячется и
// геометрию мерить нечем.
const STATUS_LINE = "💭🟣[Trelvis](docs/status.md) · WF 3 из 8 · 70%💭";

const THEME = {
  id: "сторож", name: "сторож", type: "dark",
  palette: {
    accent: "#2299ff", background: "#001122", foreground: "#eeffff",
    sidebar: "#000811", panel: "#00223a", muted: "#88aabb",
  },
};
// Четыре слоя разом: тема, шрифт и размер живут таблицами adoptedStyleSheets
// (счётчик sheets), рамка — своим узлом. Утечка любого слоя видна в счётчиках.
const LAYERS = {
  theme: THEME,
  font: { id: "SF Mono", family: "SF Mono", mono: true },
  size: { answer: 16, question: 14 },
  frame: true,
};

// Страница: композер Claude Code + последний ответ со строкой состояния.
// Геометрия задаётся числами теста — от неё считают layout() и placeProgress().
const page = ({ composerTop = 620, sabotage = null } = {}) => dom => {
  const parts = dom.composer({ top: composerTop });
  dom.document.body.add("div", {
    attrs: { "data-testid": "assistant-message" },
    rect: { left: 100, top: 200, width: 1000, height: 300 },
    text: `Готово.\n\n${STATUS_LINE}`,
  });
  if (sabotage) sabotage(parts);
  return parts;
};

const open = (options = {}) => loadInject({
  html: page(options),
  title: "Trelvis",
  storage: {
    local: { [MAP_KEY]: JSON.stringify({ "*": LAYERS }) },
    // Своя высота поля: без неё раздел 7 переменную не ставит и снимать после
    // dispose было бы нечего.
    session: { [HEIGHT_KEY]: "220", [STAGE_KEY]: "stretched" },
  },
  geometry: { viewport: { width: 1200, height: 800 } },
});

const counters = loaded => ({ ...loaded.counters });
const nodes = loaded => Object.fromEntries(NODE_IDS.map(id => [id, loaded.dom.queryAll(`#${id}`).length]));
const one = Object.fromEntries(NODE_IDS.map(id => [id, 1]));
const none = Object.fromEntries(NODE_IDS.map(id => [id, 0]));
const myclaudeKeys = win => Object.keys(win).filter(key => key.startsWith("__myclaude")).sort();

test("установка встаёт: объект в окне, версия — метка воркфлоу и та же на втором прогоне", () => {
  const loaded = open();
  assert.equal(loaded.error, null, "чистая страница инжект не роняет");
  assert.ok(loaded.api, "window.__myclaude на месте");
  // Число воркфлоу в тест не вшиваем (план, К13): проверяем ВИД метки —
  // иначе файл краснел бы в каждом следующем воркфлоу по inject.js.
  assert.match(loaded.api.status().version, /^wf\d+-[a-z]-\d+$/, "версия — метка воркфлоу");
  assert.equal(loaded.api.status().version, loaded.version, "status() и возвращённая версия сходятся");
  const again = loaded.reload();
  assert.equal(again.error, null);
  assert.equal(again.version, loaded.version, "версия та же, что вернула первая установка");
});

test("второй прогон: по одному узлу ручки, полосы, подсказки и рамки; листы не растут, сирота снята", () => {
  const loaded = open();
  assert.deepEqual(nodes(loaded), one, "после первой установки — ровно по одному узлу");
  const sheets = loaded.counters.sheets;
  assert.ok(sheets > 0, "слои живут таблицами adoptedStyleSheets, а не <style>");
  // Осиротевший <style id="myclaude-theme"> от старой установки (или зеркальная
  // копия из главного окна) обязан уйти на следующем прогоне — раздел 2а.
  const orphan = loaded.document.createElement("style");
  orphan.id = THEME_STYLE_ID;
  orphan.textContent = ":root{--myclaude-orphan:1}";
  loaded.document.body.appendChild(orphan);
  assert.equal(loaded.dom.queryAll(`#${THEME_STYLE_ID}`).length, 1, "сирота подброшена");

  const again = loaded.reload();
  assert.equal(again.error, null);
  assert.deepEqual(nodes(loaded), one, "второй прогон узлы не удвоил");
  assert.equal(loaded.counters.sheets, sheets, "число таблиц стилей не выросло");
  assert.equal(loaded.dom.queryAll(`#${THEME_STYLE_ID}`).length, 0, "сирота снята вторым прогоном");
});

test("счётчики стаба после второго прогона: подписок, наблюдателей и интервалов столько же", () => {
  const loaded = open();
  const first = counters(loaded);
  assert.ok(first.listeners > 0 && first.observers > 0 && first.intervals > 0, "первой установке есть что снимать");
  const again = loaded.reload();
  assert.equal(again.error, null);
  assert.deepEqual(counters(loaded), first, "второй прогон не оставил ни подписки, ни наблюдателя, ни интервала");
});

test("dispose(): счётчики на нуле, узлы сняты, ушёл только window.__myclaude, реестр опустел", () => {
  const loaded = open();
  const before = myclaudeKeys(loaded.win);
  loaded.api.dispose();
  assert.deepEqual(counters(loaded), { listeners: 0, observers: 0, timers: 0, intervals: 0, rafs: 0, sheets: 0 },
    "после dispose ни одной живой подписки, наблюдателя, таймера, кадра и таблицы");
  assert.deepEqual(nodes(loaded), none, "узлы сняты со страницы");
  assert.equal(loaded.win.__myclaude, undefined, "объекта в окне нет");
  const after = myclaudeKeys(loaded.win);
  assert.deepEqual(before.filter(key => !after.includes(key)), ["__myclaude"], "удалён ровно один ключ окна");
  // Реестр уборки — именно ПУСТОЙ МАССИВ, а не undefined: dispose делает
  // undoList.splice(0), и следующий прогон рассчитывает найти массив (план, К16).
  assert.ok(Array.isArray(loaded.win.__myclaudeUndo), "__myclaudeUndo остался массивом");
  assert.equal(loaded.win.__myclaudeUndo.length, 0, "реестр отмен пуст");
  // Чужого dispose не трогает: слои и высота остаются в хранилищах.
  assert.ok(loaded.win.localStorage.getItem(MAP_KEY), "запись слоёв на месте");
  assert.equal(loaded.win.sessionStorage.getItem(HEIGHT_KEY), "220", "высота окна на месте");
});

test("dispose() дважды подряд не бросает", () => {
  const loaded = open();
  // Ссылку держим свою: после первого вызова window.__myclaude уже нет, и
  // loaded.api вернул бы undefined — проверка выродилась бы в пустышку.
  const api = loaded.api;
  api.dispose();
  assert.doesNotThrow(() => api.dispose(), "второй dispose проходит молча");
  assert.deepEqual(counters(loaded), { listeners: 0, observers: 0, timers: 0, intervals: 0, rafs: 0, sheets: 0 });
  assert.deepEqual(nodes(loaded), none);
});

test("dispose() снимает атрибуты композера и переменную --myclaude-input-height", () => {
  const stretched = open();
  const { root, editor } = stretched.parts;
  assert.equal(root.getAttribute("data-myclaude-editor-root"), "true", "редактор подменён");
  assert.equal(editor.getAttribute("data-myclaude-editor"), "true");
  assert.equal(root.style.getPropertyValue(HEIGHT_VARIABLE), "220px", "высота стоит переменной");
  stretched.api.dispose();
  assert.equal(stretched.dom.queryAll(EDITOR_ATTRIBUTES).length, 0, "атрибуты подмены сняты");
  assert.equal(root.style.getPropertyValue(HEIGHT_VARIABLE), "", "переменная высоты снята");

  // Свёрнутое поле метится третьим атрибутом — его снимает тот же dispose.
  const collapsed = open();
  collapsed.dom.command({ action: "collapse" });
  assert.equal(collapsed.dom.queryAll("[data-myclaude-composer-block]").length, 1, "поле свёрнуто");
  collapsed.api.dispose();
  assert.equal(collapsed.dom.queryAll(EDITOR_ATTRIBUTES).length, 0, "свёрнутость снята вместе с экземпляром");
});

test("упавшая установка: __myclaudeFailure заполнен, зомби-подписок нет, следующий прогон встаёт чисто", () => {
  // Брошенный узел: рамка поля не отдаёт прямоугольник, и layout() падает уже
  // после того, как половина подписок и узлов расставлена.
  const loaded = open({
    sabotage: parts => { parts.shell.getBoundingClientRect = () => { throw new Error("брошенный узел"); }; },
  });
  assert.ok(loaded.error, "падение установки наружу видно");
  const failure = loaded.win.__myclaudeFailure;
  assert.ok(failure && typeof failure.message === "string", "причина осталась в окне");
  assert.match(failure.message, /брошенный узел/);
  assert.deepEqual(counters(loaded), { listeners: 0, observers: 0, timers: 0, intervals: 0, rafs: 0, sheets: 0 },
    "упавшая установка не оставила зомби-подписок");
  assert.deepEqual(nodes(loaded), none, "и ни одного узла");
  assert.equal(loaded.win.__myclaude, undefined, "полуживого объекта в окне нет");
  assert.ok(Array.isArray(loaded.win.__myclaudeUndo) && loaded.win.__myclaudeUndo.length === 0, "реестр отмен пуст");

  // Узел починился (разметка Claude доехала) — следующий прогон встаёт как на здоровой странице.
  const shell = loaded.parts.shell;
  shell.getBoundingClientRect = () => {
    const { left, top, width, height } = shell.rect;
    return { left, top, width, height, right: left + width, bottom: top + height, x: left, y: top };
  };
  const again = loaded.reload();
  assert.equal(again.error, null, "следующий прогон встаёт чисто");
  assert.deepEqual(nodes(loaded), one, "узлы расставлены по одному");
  assert.ok(loaded.counters.listeners > 0 && loaded.counters.intervals > 0, "экземпляр живой");
});

test("три прогона подряд без ручного dispose(): узлы и счётчики те же, что после одного", () => {
  const loaded = open();
  const first = counters(loaded);
  // Ручного dispose здесь нет намеренно: снятие делает сам файл первой строкой
  // (inject.js:43) — ровно так его перезапускает лоадер по mtime (план, К17).
  for (const run of [2, 3]) {
    const again = loaded.reload();
    assert.equal(again.error, null, `прогон ${run} прошёл`);
    assert.deepEqual(counters(loaded), first, `прогон ${run}: счётчики не выросли`);
    assert.deepEqual(nodes(loaded), one, `прогон ${run}: по одному узлу`);
  }
  loaded.api.dispose();
  assert.deepEqual(counters(loaded), { listeners: 0, observers: 0, timers: 0, intervals: 0, rafs: 0, sheets: 0 },
    "после трёх прогонов окно убирается за собой полностью");
  assert.deepEqual(nodes(loaded), none);
});

test("геометрия стаба не нулевая: окно, композер и полоса прогресса меряются по-настоящему", () => {
  const loaded = open();
  const window = loaded.document.documentElement.getBoundingClientRect();
  assert.deepEqual({ width: window.width, height: window.height }, { width: 1200, height: 800 }, "окно померено");
  const shell = loaded.parts.shell.getBoundingClientRect();
  assert.deepEqual({ top: shell.top, width: shell.width, height: shell.height }, { top: 620, width: 1000, height: 120 },
    "композер померен");

  // Ручка садится на кромку рамки поля: место считается от прямоугольника
  // композера, и по нулям такая проверка была бы зелёной на пустой странице.
  const handle = loaded.dom.query("#myclaude-input-handle");
  assert.equal(handle.style.getPropertyValue("display"), "flex", "ручка видна");
  assert.equal(handle.style.getPropertyValue("top"), "611px", "ручка стоит на кромке поля (620 − 9)");
  assert.equal(handle.style.getPropertyValue("left"), "552px", "и по центру поля: 100 + (1000 − 96) / 2");

  // Полоса прогресса — по нижней кромке того же блока, с сегментом на воркфлоу.
  const bar = loaded.dom.query("#myclaude-progress-bar");
  assert.equal(bar.style.getPropertyValue("display"), "flex", "полоса видна");
  assert.equal(bar.style.getPropertyValue("left"), "112px", "полоса села по краям рамки поля");
  assert.equal(bar.style.getPropertyValue("width"), "976px", "и во всю её ширину");
  assert.equal(loaded.api.status().progress.segments.length, 8, "сегменты посчитаны по строке состояния");

  // Другая раскладка — другие числа: раскладку считает layout(), а не константы.
  const higher = loadInject({
    html: page({ composerTop: 500 }),
    title: "Trelvis",
    geometry: { viewport: { width: 1200, height: 800 } },
  });
  assert.equal(higher.dom.query("#myclaude-input-handle").style.getPropertyValue("top"), "491px",
    "ручка поехала за композером");
});
