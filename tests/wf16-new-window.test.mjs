// «Новое окно» с папкой и именем (WF16): шаги «цвет», «папка» и «имя».
// Перенесено из двух скретч-тестов волны WF16 (wf16-newwindow, wf16-rename).
//
// С WF101 (z8-r02) шаги берутся из тестового люка боевой страницы, а не
// нарезкой текста inject.js: безопасная правка текста (комментарий, имя
// локальной) тест не красит. Чужой стор папки подставляется импортёром модулей
// (setModuleImporter), меню и поле имени — заглушками на документе стенда.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const MAP_KEY = "myclaude-themes-v1";
const readMap = loaded => JSON.parse(loaded.win.localStorage.getItem(MAP_KEY) ?? "null");

// Страница с часами, которые двигает тест: ожидания шага идут по now() и
// таймерам, settle прокручивает их, пока обещание не решится.
const open = (options = {}) => {
  const loaded = loadInject({ title: "", ...options });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const base = Date.now();
  let shift = 0;
  loaded.win.performance.now = () => base + shift;
  const settle = async promise => {
    let done = false;
    promise.then(() => { done = true; }, () => { done = true; });
    for (let round = 0; round < 500 && !done; round += 1) {
      shift += 100;
      loaded.dom.fireKind("timeout");
      await new Promise(resolve => setImmediate(resolve));
    }
    return promise;
  };
  return { loaded, settle };
};
const mark = loaded => plain(loaded.api.status().newWindow ?? {});

// ---- шаг «цвет»: обе записи чата (id и тень имени) ------------------------
const layers = {
  theme: {
    id: "ocean", name: "Океан", type: "dark",
    palette: { accent: "#4488ff", background: "#101820", foreground: "#e8eef6", sidebar: "#0c1219", panel: "#16202c", muted: "#8fa3b8" },
  },
  size: { answer: 16 },
};
const before = {
  "chat:Прошлый чат": {
    theme: {
      id: "sand", name: "Песок", type: "light",
      palette: { accent: "#a06020", background: "#faf5ee", foreground: "#241a10", sidebar: "#f0e6d8", panel: "#fdfaf5", muted: "#8b7a63" },
    },
  },
  main: { font: { id: "inter", family: "Inter", mono: false } },
};
const colorPage = () => open({ storage: { local: { [MAP_KEY]: JSON.stringify(before) } } });
const sessionDump = loaded => JSON.stringify([...loaded.win.sessionStorage._map.entries()]);

test("цвет нового окна пишется в ОБА ключа его чата — id и тень имени", () => {
  const { loaded } = colorPage();
  const session = sessionDump(loaded);
  const soft = loaded.inner.newWindowPaintChat("local_new", "Dictatorik", "Dictatorik", layers);
  const after = readMap(loaded);
  assert.equal(soft, null, "имя настоящее — мягкой пометки нет");
  assert.deepEqual(Object.keys(after).sort(),
                   ["chat:Dictatorik", "chat:Прошлый чат", "id:local_new", "main"]);
  assert.deepEqual(after["chat:Прошлый чат"], before["chat:Прошлый чат"], "чат главного окна тронут");
  const { at, ...mainAppearance } = after.main;
  assert.deepEqual(mainAppearance, before.main, "вид main тронут");
  assert.ok(Number.isSafeInteger(at) && at > 0, "использование main имеет timestamp");
  assert.equal(after["id:local_new"].theme.id, "ocean");
  assert.deepEqual(after["id:local_new"].size, { answer: 16 });
  const { by, ...shadow } = after["chat:Dictatorik"];
  assert.deepEqual(shadow, after["id:local_new"], "слои у ключа и тени совпали");
  assert.equal(by, "local_new", "тень помечена своим чатом (z1-r01)");
  assert.equal(sessionDump(loaded), session, "sessionStorage тронут");
  assert.deepEqual(mark(loaded).layers, ["theme", "size"]);
  assert.equal(mark(loaded).state, undefined);
});

test("заголовок-заглушка: ключ id всё равно записан, тени имени нет", () => {
  const { loaded } = colorPage();
  const soft = loaded.inner.newWindowPaintChat("local_new", "Claude", "Claude", layers);
  const after = readMap(loaded);
  assert.deepEqual(Object.keys(after).sort(), ["chat:Прошлый чат", "id:local_new", "main"],
                   "тень под заглушкой не заведена, ключ id записан");
  assert.equal(after["id:local_new"].theme.id, "ocean");
  assert.equal(soft, "no-title", "мягкая пометка осталась");
  assert.equal(mark(loaded).state, "no-title");
  assert.deepEqual(mark(loaded).layers, ["theme", "size"]);
});

test("заголовок-заглушка ключом чата не становится", () => {
  const { loaded } = open();
  for (const stub of ["Claude", "New chat", "Новый чат", "claude"]) {
    assert.ok(loaded.inner.THEME_TITLE_STUBS.has(stub.toLowerCase()), `${stub} — не заглушка`);
  }
});

// ---- шаг «папка» ----------------------------------------------------------
const folderStore = (selected, { trusted = true, deaf = false } = {}) => {
  const value = {
    selectedFolder: selected,
    trustedSelectedFolder: selected,
    setLocalSelectedFolder(path) {
      if (deaf) return;
      value.selectedFolder = path;
      value.trustedSelectedFolder = null;
    },
  };
  if (trusted) value.setTrustedSelectedFolder = path => { value.trustedSelectedFolder = path; };
  const store = () => {};
  store.getState = () => value;
  return store;
};
// Стор кладётся в модуль, который найдёт скан страницы; чипы — кнопки на экране.
const pick = async (found, want, chips) => {
  const page = open();
  page.loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  page.loaded.inner.setModuleImporter(() => Promise.resolve(found ? { Zt: found } : {}));
  for (const text of chips) page.loaded.document.body.add("button", { text });
  const result = await page.settle(page.loaded.inner.newWindowPickFolder(want, 0));
  return { result, chip: mark(page.loaded).chip, api: page.loaded.inner };
};

test("папка: стора нет — выбирать нечем", async () => {
  assert.equal((await pick(null, "/Users/dev/Projects/Dictatorik", [])).result, "no-folder-ui");
});

test("папка: стор есть, чипа не видно — верим стору, но доверие ставим сами", async () => {
  const store = folderStore("/Users/dev/Projects/PimpMyClaude");
  assert.equal((await pick(store, "/Users/dev/Projects/Dictatorik", [])).result, "ok");
  assert.equal(store.getState().selectedFolder, "/Users/dev/Projects/Dictatorik");
  assert.equal(store.getState().trustedSelectedFolder, "/Users/dev/Projects/Dictatorik",
    "без доверия папке Claude поднял бы окно вопроса");
});

// WF36, #5544: правда о папке — стор, а не чип. Глухой стор по-прежнему отказ;
// отставший чип — только пометка, и шаг папки проходит.
test("папка: глухой стор — отказ, отставший чип — пометка stale и шаг проходит", async () => {
  const deaf = await pick(folderStore("/Users/dev/Projects/PimpMyClaude", { deaf: true }),
    "/Users/dev/Projects/Dictatorik", []);
  assert.equal(deaf.result, "folder-missing", "стор папку не принял — дальше идти нельзя");

  const store = folderStore("/Users/dev/Projects/PimpMyClaude");
  const stale = await pick(store, "/Users/dev/Projects/Dictatorik", ["PimpMyClaude"]);
  assert.equal(stale.result, "ok", "стор принял папку — чип отстал, но шаг проходит (#5544)");
  assert.equal(store.getState().selectedFolder, "/Users/dev/Projects/Dictatorik");
  assert.equal(stale.chip, "stale", "отставший чип обязан быть помечен stale");

  // Сравнение чипа точное: «Dictator» на месте «Dictatorik» — не совпадение.
  const prefix = await pick(folderStore("/Users/dev/Projects/PimpMyClaude"),
    "/Users/dev/Projects/Dictatorik", ["PimpMyClaude", "Dictator"]);
  assert.equal(prefix.result, "ok");
  assert.equal(prefix.chip, "stale", "чип по префиксу засчитан — сравнение смягчили");
});

test("папка: чип сменился — сошлось; хвостовой слэш пути не меняет", async () => {
  const done = await pick(folderStore("/Users/dev/Projects/PimpMyClaude"),
    "/Users/dev/Projects/Dictatorik/", ["PimpMyClaude", " Dictatorik "]);
  assert.equal(done.result, "ok");
  assert.equal(done.chip, "ok");
  assert.equal(done.api.newWindowFolderPath("/a/b/"), "/a/b");
  assert.equal(done.api.newWindowFolderName("/a/b/"), "b");
});

test("папка: стор без нужных действий не годится", () => {
  const { loaded } = open();
  const bare = () => {};
  bare.getState = () => ({ selectedFolder: "/a" });
  assert.equal(loaded.inner.newWindowFolderStoreOk(bare), false);
  assert.equal(loaded.inner.newWindowFolderStoreOk(folderStore("/a")), true);
});

test("поле имени: композер чата полем имени не считается", () => {
  const { loaded } = open();
  const composer = { isConnected: true, tagName: "DIV", isContentEditable: true, closest: () => composer };
  const dialogField = { isConnected: true, tagName: "INPUT", isContentEditable: false, getAttribute: () => "text", closest: () => null };
  assert.equal(loaded.inner.newWindowNameField(composer), false, "композер приняли за поле имени");
  assert.equal(loaded.inner.newWindowNameField(dialogField), true);
  assert.equal(loaded.inner.newWindowNameField(null), false);
});

// ---- шаг «имя»: переименование строки сайдбара ----------------------------
// Путь через контекстное меню заведомо хрупкий (живьём не снят), поэтому
// проверяем именно деградацию: не нашли меню или поля — false, меню за собой
// погашено, и имя проекта НИКУДА не напечатано.
class FakeInput {
  constructor(host) { this.tagName = "INPUT"; this._v = "Привет"; this.gone = false; this.host = host ?? null; this.sent = []; }
  get isConnected() { return !this.gone; }
  get value() { return this._v; }
  set value(v) { this._v = String(v); }
  getAttribute() { return "text"; }
  closest() { return null; }
  focus() {}
  select() {}
  dispatchEvent(event) { this.sent.push(event.key || event.type); return true; }
}
const renameWorld = () => {
  const page = open();
  const { loaded } = page;
  const world = { menu: [], dialogs: [], rows: null, active: null, closes: 0 };
  const doc = loaded.document;
  const stockAll = doc.querySelectorAll.bind(doc);
  const stockOne = doc.querySelector.bind(doc);
  doc.querySelectorAll = selector => {
    if (selector.includes("menuitem")) return world.menu;
    if (selector === '[role="dialog"]') return world.dialogs;
    return stockAll(selector);
  };
  doc.querySelector = selector => (selector.includes("sidebar-recents") ? world.rows : stockOne(selector));
  Object.defineProperty(doc, "activeElement", { configurable: true, get: () => world.active, set: () => {} });
  doc.body.click = () => { world.closes += 1; };
  loaded.win.HTMLInputElement = FakeInput;
  loaded.win.HTMLTextAreaElement = class extends FakeInput {};
  world.rename = (row, name) => page.settle(loaded.inner.newWindowRename(row, name, 0));
  world.field = host => new FakeInput(host);
  world.row = () => ({
    isConnected: true, menuOpened: 0,
    getBoundingClientRect: () => ({ left: 10, top: 20, width: 200, height: 30 }),
    dispatchEvent(event) { if (event.type === "contextmenu") this.menuOpened += 1; return true; },
    contains: node => node?.host === "rows",
    querySelector: () => null,
  });
  return world;
};
const menuItem = text => ({ text, clicks: 0, textContent: text, click() { this.clicks += 1; } });
const dialogOf = field => ({ contains: node => node === field, querySelector: () => field });

test("имя: меню не открылось — отказ, и меню за собой погашено", async () => {
  const world = renameWorld();
  const row = world.row();
  assert.equal(await world.rename(row, "Dictatorik"), false);
  assert.equal(row.menuOpened, 1, "контекстное меню строке не послали");
  assert.equal(world.closes, 1, "меню за собой не погасили");
});

test("имя: в меню нет пункта «Переименовать» — тот же честный отказ", async () => {
  const world = renameWorld();
  world.menu = [menuItem("Открыть в отдельном окне"), menuItem("Удалить")];
  assert.equal(await world.rename(world.row(), "Dictatorik"), false);
  assert.equal(world.closes, 1);
});

test("имя: пункт есть, поля нет — пункт нажат, имя никуда не уехало", async () => {
  const world = renameWorld();
  const rename = menuItem("Rename");
  world.menu = [menuItem("Delete"), rename];
  assert.equal(await world.rename(world.row(), "Dictatorik"), false);
  assert.equal(rename.clicks, 1, "пункт «Rename» не нажали");
  assert.equal(world.closes, 1);
});

test("имя: поле в модалке — родной сеттер, событие input и Enter", async () => {
  const world = renameWorld();
  world.menu = [menuItem("Переименовать")];
  const box = world.field();
  box.dispatchEvent = function (event) {
    this.sent.push(event.key || event.type);
    if (event.key === "Enter") this.gone = true;   // модалка закрылась
    return true;
  };
  world.dialogs = [dialogOf(box)];
  assert.equal(await world.rename(world.row(), "Dictatorik"), true);
  assert.equal(box.value, "Dictatorik");
  assert.ok(box.sent.includes("input"), "React не увидел бы значения без события input");
  assert.ok(box.sent.includes("Enter"), "подтверждения Enter не было");
  assert.equal(world.closes, 0, "успешное переименование гасить меню не должно");
});

test("имя: поле осталось на экране — отказ и уборка за собой", async () => {
  const world = renameWorld();
  world.menu = [menuItem("Rename")];
  world.dialogs = [dialogOf(world.field())];
  assert.equal(await world.rename(world.row(), "Dictatorik"), false);
  assert.equal(world.closes, 1, "зависшую модалку за собой не погасили");
});

test("имя: фокус в чужом поле — имя проекта туда не печатается", async () => {
  const world = renameWorld();
  world.menu = [menuItem("Rename")];
  const stranger = world.field("search");
  world.active = stranger;
  world.rows = { contains: node => node?.host === "rows", querySelector: () => null };
  assert.equal(await world.rename(world.row(), "Dictatorik"), false);
  assert.equal(stranger.value, "Привет", "имя проекта уехало в чужое поле");
  assert.equal(world.closes, 1);
});

test("имя: инлайн-поле внутри списка чатов — наше", async () => {
  const world = renameWorld();
  world.menu = [menuItem("Rename")];
  const inline = world.field("rows");
  inline.dispatchEvent = function (event) {
    this.sent.push(event.key || event.type);
    if (event.key === "Enter") this.gone = true;
    return true;
  };
  world.active = inline;
  world.rows = { contains: node => node === inline, querySelector: () => inline };
  assert.equal(await world.rename(world.row(), "Dictatorik"), true);
  assert.equal(inline.value, "Dictatorik");
});
