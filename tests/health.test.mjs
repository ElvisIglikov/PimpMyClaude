// #10527 (слово Элвиса 22.10 02:12: «постоянно одни и те же ошибки правлю. То кнопка какая-нибудь отвалится, то
// ещё что-нибудь отвалится»): самопроверка страницы window.__myclaude.health(), контракт К-HEALTH
// (docs/contracts/550-10527-health-live-check.md). Сцены — окно Claude 3.1623 в стенде (tests/stands.mjs,
// claudeWindow): главное широкое и узкое, попап, новый чат — всё зелёное. Потом ломаем по одной опоре и ждём
// красного ровно у своей проверки, с кодом why. И отдельно — health() только читает: ни событий, ни мутаций, ни
// записей в хранилище, ни таймеров.
//
// Что стаб не умеет, сцена делает сама: флаг широкого вида и сетку — по таблице страницы (wideByCss), рамки наших
// узлов — по их инлайн-стилям (ownRects), попадание мышью — по рамкам и z-index (pointHits). Настоящих
// вычисленных стилей (прозрачность, перекрытие настоящими слоями) здесь нет — их проверяет живой прогон
// (pimp.py live-check) и слепки.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { loadInject, plain } from "./load.mjs";
import { claudeWindow, ownRects, pointHits, settle, wideByCss } from "./stands.mjs";

const FIXTURE = JSON.parse(readFileSync(new URL("./fixtures/health.json", import.meta.url), "utf8"));
const CHAT = "local_5b0c7e2a-41d3-4f8e-9a6b-2c1d0e9f7a13";
const IDS = ["anchors", "wide", "fold", "title", "sidebarButton", "look", "ownButtons", "claudeButtons", "install"];
const THEMES = "myclaude-themes-v1";

const HREF = { main: `https://claude.ai/epitaxy/${CHAT}`, popout: "about:blank", new: "https://claude.ai/epitaxy" };
// Окно: строим, ставим страницу, CSS-флаг по форме, раскладку, рамки наших узлов и попадание мышью.
// breakDom — поломка разметки до установки страницы; после — тест ломает сам и зовёт refresh().
const scene = ({ wide = true, kind = "main", look = false, card = false, breakDom = null } = {}) => {
  const local = { "myclaude.mic": "dictator" };
  if (look) local[THEMES] = JSON.stringify({ "*": { look: { aurora: true, motion: "still" } } });
  const loaded = loadInject({
    href: HREF[kind], title: "Сторожи Пимпа", storage: { local },
    geometry: { viewport: wide ? { width: 1200, height: 800 } : { width: 600, height: 800 } },
    html: dom => { const parts = claudeWindow(dom, { wide, kind, look, card }); breakDom?.(parts, dom); return parts; },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.refresh = () => {
    wideByCss(loaded);
    settle(loaded);
    settle(loaded);
    ownRects(loaded.dom);
    pointHits(loaded.dom);
  };
  loaded.refresh();
  return loaded;
};
const health = loaded => plain(loaded.api.health());
const check = (result, id) => result.checks.find(item => item.id === id);
const code = (result, id) => String(check(result, id)?.why ?? "").split(":")[0];
const reds = result => result.checks.filter(item => !item.ok).map(item => item.id);

// ---- форма ответа ---------------------------------------------------------------------------------------------
test("health(): форма ответа — ключи и их порядок как в эталоне, девять проверок по порядку контракта", () => {
  const result = health(scene());
  assert.deepEqual(Object.keys(result), Object.keys(FIXTURE), "ключи ответа и порядок — как tests/fixtures/health.json");
  assert.deepEqual(result.checks.map(item => item.id), FIXTURE.checks.map(item => item.id));
  assert.deepEqual(result.checks.map(item => item.id), IDS);
  assert.equal(result.v, 1);
  assert.match(result.version, /^wf\d+-[a-z]+-\d+$/);
  assert.equal(result.page, `https://claude.ai/epitaxy/${CHAT}`, "без ?… и #…");
  assert.equal(result.kind, "main");
  assert.equal(result.mode, "code");
  assert.equal(result.wide, true);
  assert.equal(result.chat, CHAT);
  assert.equal(result.title, "Сторожи Пимпа");
  assert.match(result.at, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/);
  for (const item of result.checks) {
    const keys = Object.keys(item);
    assert.deepEqual(keys, ["id", "ok", "skip", "why", "at"].filter(key => key in item), `${item.id}: порядок ключей записи`);
    if (item.skip) assert.equal(item.ok, true, `${item.id}: skip — зелёная`);
    if (item.ok) assert.equal(item.why, undefined, `${item.id}: why только у красной`);
  }
  assert.match(check(result, "install").at, /Z$/, "install — с временем установки страницы");
  assert.deepEqual(result.red, []);
});

test("health(): страница не чата отвечает null; попап — about:blank", () => {
  const other = loadInject({ href: "https://example.com/docs", html: dom => claudeWindow(dom, {}) });
  assert.equal(other.api.health(), null, "чужая страница (chatKind other)");
  const popout = health(scene({ kind: "popout" }));
  assert.equal(popout.page, "about:blank");
  assert.equal(popout.kind, "popout");
});

// ---- сцены: всё зелёное ------------------------------------------------------------------------------------
for (const [name, options, expect] of [
  ["главное окно, широкое", { wide: true }, { kind: "main", mode: "code", wide: true, skips: { look: "live-off" } }],
  ["главное окно, узкое", { wide: false }, { kind: "main", mode: "code", wide: false, skips: { title: "narrow", look: "live-off" } }],
  ["попап (вынесенное окно)", { kind: "popout" }, { kind: "popout", mode: "code", wide: true, skips: { look: "live-off" } }],
  ["новый чат (домашний экран Code)", { kind: "new", wide: false }, { kind: "new", mode: "code", wide: false, skips: { title: "no-chat", look: "live-off" } }],
  ["главное широкое, живой фон и карточка файла в ленте", { look: true, card: true }, { kind: "main", mode: "code", wide: true, skips: {} }],
]) {
  test(`health(): ${name} — всё зелёное`, () => {
    const result = health(scene(options));
    assert.deepEqual(result.red, [], JSON.stringify(result.checks.filter(item => !item.ok)));
    assert.equal(result.kind, expect.kind);
    assert.equal(result.mode, expect.mode);
    assert.equal(result.wide, expect.wide);
    const skips = Object.fromEntries(result.checks.filter(item => item.skip).map(item => [item.id, item.skip]));
    assert.deepEqual(skips, expect.skips);
  });
}

test("health(): режим чата (/new) — пять проверок Code пропущены как mode-chat", () => {
  const loaded = loadInject({ href: "https://claude.ai/new", html: dom => claudeWindow(dom, { kind: "new", wide: false }),
    geometry: { viewport: { width: 600, height: 800 } } });
  const result = plain(loaded.api.health());
  assert.equal(result.mode, "chat");
  assert.equal(result.kind, "new");
  for (const id of ["anchors", "wide", "fold", "title", "sidebarButton"]) {
    assert.deepEqual(check(result, id), { id, ok: true, skip: "mode-chat" });
  }
});

// ---- поломки по одной: красное ровно у своей ----------------------------------------------------------------
// pass: false — поломка, которую следующий проход раскладки поправил бы сам: судим кадр сразу после неё.
const broken = (name, options, mutate, expected, { pass = true } = {}) => test(`health() краснеет: ${name}`, () => {
  const loaded = scene(options);
  if (mutate) { mutate(loaded); if (pass) loaded.refresh(); else ownRects(loaded.dom); }
  const result = health(loaded);
  assert.deepEqual(reds(result), Object.keys(expected), JSON.stringify(result.checks.filter(item => !item.ok)));
  for (const [id, why] of Object.entries(expected)) {
    assert.equal(code(result, id), why.split(":")[0], `${id}: код why`);
    if (why.includes(":")) assert.equal(check(result, id).why, why, `${id}: why целиком`);
  }
  assert.deepEqual(result.red, Object.keys(expected), "red — id красных по порядку checks");
});

broken("Claude переименовал кружок Usage (С12: опору не нашли)", {
  breakDom: parts => parts.ring.setAttribute("aria-label", "Context 30%"),
}, null, { anchors: "missing: usageRing" });

broken("строки модели нет (ChatComposerChin убран): опора и цель свёртки разом", {
  breakDom: parts => parts.chin.remove(),
}, null, { anchors: "missing: modelRow, modelButton, usageRing", fold: "no-target: modelRow" });

// #10972 (Claude 3.6556.2, 27.10: «Проверка окна Claude 3.6556.2: 1 красная — опоры окна не найдены»): домашний
// экран строки ChatComposerChin не рисует — модель, кружок и «+» лежат полкой под полем, соседом рамки в доке
// (замер живого окна: anchors «missing: modelRow», цель свёртки страница нашла). Опора — эта полка.
const homeShelf = (parts, { model = true } = {}) => {
  const box = parts.chin.rect;
  const shelf = parts.dock.add("div", { attrs: { "data-chorus-tray-open": "" }, rect: { ...box, top: box.top + 20 } });
  const row = shelf.add("div", { class: "flex h-[60px] items-center", rect: { ...box, top: box.top + 20 } });
  for (const node of [parts.attach, model ? parts.model : null, parts.ring]) if (node) row.appendChild(node);
  parts.chin.remove();
  return shelf;
};
test("health(): домашний экран без ChatComposerChin, модель полкой под полем (#10972) — всё зелёное", () => {
  const result = health(scene({ kind: "new", wide: false, breakDom: parts => homeShelf(parts) }));
  assert.deepEqual(result.red, [], JSON.stringify(result.checks.filter(item => !item.ok)));
  assert.equal(result.kind, "new");
});
broken("домашний экран: полка под полем есть, кнопки модели нет (#10972) — опору не придумываем", {
  kind: "new", wide: false, breakDom: parts => homeShelf(parts, { model: false }),
}, null, { anchors: "missing: modelRow, modelButton" });

broken("шапку завернули в лишнюю обёртку (С1, #10500: широкий вид не включился)", {
  breakDom: parts => {
    const wrap = parts.header.ownerDocument.createElement("div");
    parts.header.parentElement.insertBefore(wrap, parts.header);
    wrap.appendChild(parts.header);
  },
}, null, { wide: "flag: плитка 1192, флаг 0" });

broken("строка модели нулевой высоты (3.1623 рисует её позже поля): свёртке нечего сворачивать (С2)", {
  wide: false,
  breakDom: parts => { parts.chin.rect = { ...parts.chin.rect, height: 0 }; },
}, null, { fold: "no-target: modelRow" });

broken("в узком виде полоски нет: страница её спрятала (поле «без полосок», С2)", { wide: false }, loaded => {
  loaded.document.getElementById("myclaude-input-handle").style.setProperty("display", "none");
}, { fold: "bars: 0" }, { pass: false });

broken("в узком виде полоска есть, а на экране её нет (правило спрятало): и свёртка, и наша кнопка", { wide: false }, loaded => {
  const handle = loaded.document.getElementById("myclaude-input-handle");
  handle.computed = { ...handle.computed, display: "none" };
}, { fold: "bars: 0", ownButtons: "hidden: myclaude-input-handle" });

broken("название уехало вправо от линии поля (С3, распорка под кнопки окна)", {
  breakDom: parts => { parts.title.rect = { ...parts.title.rect, left: parts.title.rect.left + 108 }; },
}, null, { title: "line: название 965, поле 857" });

broken("папка в углу пустая (С3, #9224)", {
  breakDom: parts => parts.header.querySelector('[data-testid="epitaxy-origin-label"]').remove(),
}, null, { title: "folder: пусто" });

broken("кнопку «Show sidebar» закрыл чужой слой (С4, #10359)", {}, loaded => {
  loaded.document.body.add("div", { class: "veil", rect: { left: 70, top: 0, width: 60, height: 50 }, computed: { zIndex: "50" } });
}, { sidebarButton: "covered: div.veil" });

broken("у «Show sidebar» прозрачная подложка (С4: просвечивает)", {}, loaded => {
  loaded.parts.sidebarButton.pseudo = { "::before": { backgroundColor: "rgba(19, 21, 24, 0.4)" } };
}, { sidebarButton: "backing: альфа 0.4" });

broken("живой фон: рамка плиток залита цветом (С5, 3.1623)", { look: true }, loaded => {
  loaded.parts.tiles.computed = { ...loaded.parts.tiles.computed, backgroundColor: "rgb(19, 21, 24)" };
}, { look: "opaque: tile альфа 1" });

broken("живой фон: слоя подложки нет", { look: true }, loaded => {
  loaded.parts.root.pseudo = { "::before": { content: "none" } };
}, { look: "layer: нет слоя" });

broken("живой фон: поле ввода непрозрачно (#9127)", { look: true }, loaded => {
  loaded.parts.frame.computed = { ...loaded.parts.frame.computed, backgroundColor: "rgb(40, 40, 40)" };
}, { look: "opaque: composer альфа 1" });

broken("живой фон: над лентой непрозрачный прямоугольник (#10399)", { look: true }, loaded => {
  loaded.document.body.add("div", { class: "slab", rect: { left: 300, top: 300, width: 300, height: 200 },
    computed: { zIndex: "5", backgroundColor: "rgb(0, 0, 0)" } });
}, { look: "over-feed: div.slab 300×200" });

// Проход раскладки вернул бы её (pmpShow) — судим кадр, где её уже нет.
broken("наша кнопка PMP пропала со страницы (кнопка отвалилась)", {}, loaded => {
  loaded.document.getElementById("myclaude-pmp").remove();
}, { ownButtons: "missing: myclaude-pmp" }, { pass: false });

broken("наша кнопка вдвое (двойной узел)", {}, loaded => {
  loaded.document.body.add("div", { id: "myclaude-gallery" });
}, { ownButtons: "dupe: myclaude-gallery×2" });

broken("PMP показан, а правило прячет (hidden)", {}, loaded => {
  const node = loaded.document.getElementById("myclaude-pmp");
  node.computed = { ...node.computed, visibility: "hidden" };
}, { ownButtons: "hidden: myclaude-pmp" });

broken("PMP закрыт чужим слоем (С7: нажатие не доходит)", {}, loaded => {
  const box = loaded.document.getElementById("myclaude-pmp").getBoundingClientRect();
  loaded.document.body.add("div", { class: "glass", rect: { left: box.left - 4, top: box.top - 4, width: 60, height: 30 },
    computed: { zIndex: "2147483647" } });
}, { ownButtons: "covered: myclaude-pmp под div.glass" });

broken("установка упала (__myclaudeFailure)", {}, loaded => {
  loaded.win.__myclaudeFailure = { message: "boom" };
}, { install: "failure: boom" });

// Две поломки, которые раскладка сама бы поправила, сверяем без прохода: так их видит снимок экрана.
test("health() краснеет без прохода раскладки: полоска в широком виде и наш слой на кнопке модели", () => {
  const bars = scene();
  const bottom = bars.document.getElementById("myclaude-super-bottom");
  for (const [name, value] of [["display", "flex"], ["left", "800px"], ["top", "780px"], ["width", "300px"]]) bottom.style.setProperty(name, value);
  ownRects(bars.dom);
  const first = health(bars);
  assert.deepEqual(first.red, ["fold"]);
  assert.equal(check(first, "fold").why, "bars: 1");

  const cover = scene();
  const pmp = cover.document.getElementById("myclaude-pmp");
  const box = cover.parts.model.getBoundingClientRect();
  for (const [name, value] of [["left", box.left], ["top", box.top], ["width", box.width], ["height", box.height]]) pmp.style.setProperty(name, `${value}px`);
  ownRects(cover.dom);
  const second = health(cover);
  assert.deepEqual(second.red, ["claudeButtons"]);
  assert.equal(check(second, "claudeButtons").why, "covered: modelButton под #myclaude-pmp");
});

test("health(): исключение внутри проверки — только она красная, с кодом error", () => {
  const loaded = scene();
  const status = plain(loaded.api.status());
  // status(), у которого поле угла бросает: так падает чтение внутри title, остальные проверки живут.
  const shaky = new Proxy(status, { get: (target, key) => { if (key === "corner") throw new Error("сломалось чтение угла"); return target[key]; } });
  const result = plain(loaded.inner.healthRun(loaded.win, { ...loaded.inner.HEALTH_PAGE, version: "wf0-test-0", status: shaky }));
  assert.deepEqual(result.red, ["title"], JSON.stringify(result.checks));
  assert.equal(check(result, "title").why, "error: сломалось чтение угла");
});

// ---- только чтение ------------------------------------------------------------------------------------------
// Снимок дерева (атрибуты, инлайн-стили, текст, дети), хранилищ и счётчиков стаба до и после; плюс прямой счёт
// вызовов, которые меняют страницу или шлют наружу.
const snapshot = loaded => {
  const node = item => item.nodeType !== 1 ? `#text:${item.nodeValue}` : {
    t: item.tagName,
    a: Object.fromEntries(item.getAttributeNames().map(name => [name, item.getAttribute(name)])),
    s: item.style.cssText,
    d: JSON.stringify(item.dataset),
    x: item.__text,
    k: [...item.childNodes].map(node),
  };
  return JSON.stringify({
    tree: node(loaded.document.documentElement),
    local: [...loaded.win.localStorage._map], session: [...loaded.win.sessionStorage._map],
    counters: { ...loaded.counters }, timers: loaded.dom.timers.size, title: loaded.document.title,
    active: loaded.document.activeElement ? loaded.document.activeElement.tagName : null,
  });
};
const WRITES = ["setAttribute", "removeAttribute", "appendChild", "insertBefore", "removeChild", "remove", "append",
  "click", "focus", "blur", "dispatchEvent", "scrollIntoView", "animate", "addEventListener", "removeEventListener"];
const spy = loaded => {
  const calls = [];
  const wrap = (owner, name, label) => {
    const real = owner?.[name];
    if (typeof real !== "function") return;
    owner[name] = function (...args) { calls.push(`${label}.${name}`); return real.apply(this, args); };
  };
  for (const item of [loaded.document, ...loaded.dom.queryAll("*"), loaded.document.documentElement]) {
    const label = item.tagName ?? "document";
    for (const name of WRITES) wrap(item, name, label);
    if (item.style) for (const name of ["setProperty", "removeProperty"]) wrap(item.style, name, `${label}.style`);
    if (item.classList) for (const name of ["add", "remove", "toggle"]) wrap(item.classList, name, `${label}.classList`);
  }
  for (const store of ["localStorage", "sessionStorage"]) for (const name of ["setItem", "removeItem", "clear"]) wrap(loaded.win[store], name, store);
  for (const name of ["setTimeout", "setInterval", "requestAnimationFrame", "queueMicrotask", "fetch", "postMessage", "scrollTo", "scrollBy", "dispatchEvent", "open"]) {
    wrap(loaded.win, name, "window");
  }
  return calls;
};

for (const [name, options] of [["главное широкое, живой фон", { look: true, card: true }], ["узкое", { wide: false }], ["попап", { kind: "popout" }]]) {
  test(`health() только читает: ${name} — ни событий, ни мутаций, ни записей, ни таймеров`, () => {
    const loaded = scene(options);
    let fetched = 0;
    loaded.win.fetch = () => { fetched += 1; return Promise.resolve({}); };
    const before = snapshot(loaded);
    const calls = spy(loaded);
    const first = health(loaded);
    const second = health(loaded);
    assert.deepEqual(calls, [], "health() позвал то, что меняет страницу или шлёт наружу");
    assert.equal(fetched, 0);
    assert.equal(snapshot(loaded), before, "дерево, хранилища и счётчики — как до health()");
    assert.deepEqual({ ...first, at: 0 }, { ...second, at: 0 }, "два вызова подряд — один ответ");
  });
}
