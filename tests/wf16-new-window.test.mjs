// «Новое окно» с папкой и именем (WF16): шаги «цвет», «папка» и «имя».
// Перенесено из двух скретч-тестов волны WF16 (wf16-newwindow, wf16-rename).
//
// Эти три шага живут в замыкании и в тестовый люк не входят: они не чистые —
// ходят по DOM и по чужому стору. Поэтому куски настоящего файла берутся
// ТЕКСТОМ по приметам и исполняются в vm. Приём хрупкий: переименование
// функции в inject.js ломает разбор — это осознанная цена (см. README, раздел
// «Тесты»), и падает он громко, а не молча.
import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { injectSource } from "./load.mjs";

const lines = injectSource().split("\n");
const at = needle => {
  const index = lines.findIndex(line => line.includes(needle));
  assert.notEqual(index, -1, `не нашёл в inject.js: ${needle}`);
  return index;
};
const slice = (from, to) => lines.slice(at(from), at(to)).join("\n");
const constant = name => lines[at(`  const ${name} = `)];
// Определение по имени: от «  const ИМЯ = » до строки «  };» того же отступа.
const grab = name => {
  const start = at(`  const ${name} = `);
  if (/;\s*$/.test(lines[start]) && !lines[start].trim().endsWith("= {")) {
    let end = start;
    while (!/;\s*$/.test(lines[end])) end += 1;
    return lines.slice(start, end + 1).join("\n");
  }
  let end = start;
  while (lines[end] !== "  };" && lines[end] !== "  });") end += 1;
  return lines.slice(start, end + 1).join("\n");
};
const fakeStorage = map => ({
  getItem: key => (map.has(key) ? map.get(key) : null),
  setItem: (key, value) => { map.set(key, String(value)); },
  removeItem: key => { map.delete(key); },
});

// ---- шаг «цвет»: одна запись нового чата ----------------------------------
const colorApi = (title = "Прошлый чат") => {
  const store = new Map();
  const session = new Map();
  const context = {
    console,
    localStorage: fakeStorage(store),
    sessionStorage: fakeStorage(session),
    location: { href: "https://claude.ai/epitaxy/local_1", pathname: "/epitaxy/local_1" },
    document: { get title() { return title; }, querySelectorAll: () => [] },
    now: () => Date.now(),
    state: { alive: true },
    track: () => {},
  };
  vm.createContext(context);
  vm.runInContext([
    slice("---- 1. Постоянные", "const themeSheet = new CSSStyleSheet"),
    grab("setMapLayers"), grab("writeKeys"), grab("writeLayers"),
    "globalThis.api = { readThemeMap, writeThemeMap, setMapLayers, writeLayers, THEME_CHAT_PREFIX, THEME_TITLE_STUBS };",
  ].join("\n"), context);
  // Разбор постоянных попутно пишет ступень поля ввода (раздел 2) — к шагу
  // «цвет» это отношения не имеет, поэтому начинаем с чистой сессии.
  session.clear();
  return { api: context.api, store, session };
};

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

test("цвет нового окна пишется РОВНО в запись его чата", () => {
  const { api, store, session } = colorApi();
  store.set("myclaude-themes-v1", JSON.stringify(before));
  const map = api.readThemeMap();
  api.setMapLayers(map, `${api.THEME_CHAT_PREFIX}Dictatorik`, layers);
  api.writeThemeMap(map);
  const after = JSON.parse(store.get("myclaude-themes-v1"));
  assert.deepEqual(Object.keys(after).sort(), ["chat:Dictatorik", "chat:Прошлый чат", "main"]);
  assert.deepEqual(after["chat:Прошлый чат"], before["chat:Прошлый чат"], "чат главного окна тронут");
  assert.deepEqual(after.main, before.main, "запись main тронута");
  assert.equal(after["chat:Dictatorik"].theme.id, "ocean");
  assert.deepEqual(after["chat:Dictatorik"].size, { answer: 16 });
  assert.equal(session.size, 0, "sessionStorage тронут");
});

test("контроль: «очевидная» writeLayers на том же месте испортила бы main и сессию", () => {
  const { api, store, session } = colorApi();
  store.set("myclaude-themes-v1", JSON.stringify(before));
  api.writeLayers(layers);
  const bad = JSON.parse(store.get("myclaude-themes-v1"));
  assert.equal(bad.main.theme.id, "ocean", "контроль сломался: writeLayers обязан портить main");
  assert.equal(bad["chat:Прошлый чат"].theme.id, "ocean");
  assert.ok(session.size > 0, "контроль сломался: writeLayers обязан писать сессию");
});

test("заголовок-заглушка ключом чата не становится", () => {
  const { api } = colorApi();
  for (const stub of ["Claude", "New chat", "Новый чат", "claude"]) {
    assert.ok(api.THEME_TITLE_STUBS.has(stub.toLowerCase()), `${stub} — не заглушка`);
  }
});

// ---- шаг «папка» ----------------------------------------------------------
const folderWorld = () => {
  const world = { chips: [], marks: [], state: { alive: true } };
  const context = {
    console,
    document: { querySelectorAll: () => world.chips },
    state: world.state,
    newWindowMark: patch => { world.marks.push(patch); },
    newWindowLive: () => world.state.alive,
    // Ожидание без таймеров: несколько попыток подряд.
    newWindowWait: async check => {
      for (let index = 0; index < 20; index += 1) {
        let hit = null;
        try { hit = check(); } catch { hit = null; }
        if (hit) return hit;
        await Promise.resolve();
      }
      return null;
    },
  };
  vm.createContext(context);
  vm.runInContext([
    constant("NEW_WINDOW_FOLDER_MS"), constant("NEW_WINDOW_CHIP_SELECTOR"), constant("NEW_WINDOW_INPUT_SELECTOR"),
    grab("newWindowFolderStoreOk"), grab("newWindowFolderPath"), grab("newWindowFolderName"),
    grab("newWindowFolderNow"), grab("newWindowChipShows"), grab("newWindowPickFolder"),
    grab("newWindowNameField"), grab("newWindowNameText"),
    "globalThis.folderApi = { newWindowPickFolder, newWindowFolderPath, newWindowFolderName,"
    + " newWindowFolderStoreOk, newWindowNameField, newWindowNameText };",
  ].join("\n"), context);
  world.api = context.folderApi;
  world.pick = async (found, want, chips) => {
    world.chips = chips;
    context.newWindowFindFolderStore = async () => found;
    return world.api.newWindowPickFolder(want, 1);
  };
  return world;
};
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
  return { getState: () => value };
};
const chip = text => ({ textContent: text });

test("папка: стора нет — выбирать нечем", async () => {
  const world = folderWorld();
  assert.equal(await world.pick(null, "/Users/elvis/_ElvisProjects/Dictatorik", []), "no-folder-ui");
});

test("папка: стор есть, чипа не видно — верим стору, но доверие ставим сами", async () => {
  const world = folderWorld();
  const store = folderStore("/Users/elvis/_ElvisProjects/PimpMyClaude");
  assert.equal(await world.pick(store, "/Users/elvis/_ElvisProjects/Dictatorik", []), "ok");
  assert.equal(store.getState().selectedFolder, "/Users/elvis/_ElvisProjects/Dictatorik");
  assert.equal(store.getState().trustedSelectedFolder, "/Users/elvis/_ElvisProjects/Dictatorik",
    "без доверия папке Claude поднял бы окно вопроса");
});

test("папка: глухой стор и не сменившийся чип — честный отказ", async () => {
  const deaf = folderWorld();
  assert.equal(
    await deaf.pick(folderStore("/Users/elvis/_ElvisProjects/PimpMyClaude", { deaf: true }), "/Users/elvis/_ElvisProjects/Dictatorik", []),
    "folder-missing");
  const stale = folderWorld();
  assert.equal(
    await stale.pick(folderStore("/Users/elvis/_ElvisProjects/PimpMyClaude"), "/Users/elvis/_ElvisProjects/Dictatorik", [chip("PimpMyClaude")]),
    "folder-missing", "чип был и не сменился — стор нашли не тот");
});

test("папка: чип сменился — сошлось; хвостовой слэш пути не меняет", async () => {
  const world = folderWorld();
  assert.equal(
    await world.pick(folderStore("/Users/elvis/_ElvisProjects/PimpMyClaude"), "/Users/elvis/_ElvisProjects/Dictatorik/",
      [chip("PimpMyClaude"), chip(" Dictatorik ")]),
    "ok");
  assert.equal(world.api.newWindowFolderPath("/a/b/"), "/a/b");
  assert.equal(world.api.newWindowFolderName("/a/b/"), "b");
});

test("папка: стор без нужных действий не годится", () => {
  const world = folderWorld();
  assert.equal(world.api.newWindowFolderStoreOk({ getState: () => ({ selectedFolder: "/a" }) }), false);
  assert.equal(world.api.newWindowFolderStoreOk(folderStore("/a")), true);
});

test("поле имени: композер чата полем имени не считается", () => {
  const world = folderWorld();
  const composer = { isConnected: true, tagName: "DIV", isContentEditable: true, closest: () => composer };
  const dialogField = { isConnected: true, tagName: "INPUT", isContentEditable: false, getAttribute: () => "text", closest: () => null };
  assert.equal(world.api.newWindowNameField(composer), false, "композер приняли за поле имени");
  assert.equal(world.api.newWindowNameField(dialogField), true);
  assert.equal(world.api.newWindowNameField(null), false);
});

// ---- шаг «имя»: переименование строки сайдбара ----------------------------
// Путь через контекстное меню заведомо хрупкий (живьём не снят), поэтому
// проверяем именно деградацию: не нашли меню или поля — false, меню за собой
// погашено, и имя проекта НИКУДА не напечатано.
const renameWorld = () => {
  const dom = { menu: [], dialogs: [], rows: null, active: null, closes: 0 };
  const context = { console, state: { alive: true } };
  context.newWindowLive = () => context.state.alive;
  context.newWindowWait = async check => {
    for (let index = 0; index < 30; index += 1) {
      let hit = null;
      try { hit = check(); } catch { hit = null; }
      if (hit) return hit;
      await Promise.resolve();
    }
    return null;
  };
  context.window = {};
  context.document = {
    querySelectorAll: selector => {
      if (selector.includes("menuitem")) return dom.menu;
      if (selector === '[role="dialog"]') return dom.dialogs;
      return [];
    },
    querySelector: selector => (selector.includes("sidebar-recents") ? dom.rows : null),
    get activeElement() { return dom.active; },
    body: { click: () => { dom.closes += 1; } },
    dispatchEvent: () => true,
    execCommand: () => true,
  };
  vm.createContext(context);
  vm.runInContext(`
    class Event { constructor(type) { this.type = type; } }
    class KeyboardEvent { constructor(type, init) { this.type = type; Object.assign(this, init ?? {}); } }
    class MouseEvent extends KeyboardEvent {}
    class HTMLInputElement {
      constructor(host) { this.tagName = "INPUT"; this._v = "Привет"; this.gone = false; this.host = host ?? null; this.sent = []; }
      get isConnected() { return !this.gone; }
      get value() { return this._v; }
      set value(v) { this._v = String(v); }
      getAttribute() { return "text"; }
      closest() { return null; }
      focus() {} select() {}
      dispatchEvent(event) { this.sent.push(event.key ?? event.type); return true; }
    }
    class HTMLTextAreaElement extends HTMLInputElement {}
    globalThis.Event = Event; globalThis.KeyboardEvent = KeyboardEvent; globalThis.MouseEvent = MouseEvent;
    globalThis.HTMLInputElement = HTMLInputElement; globalThis.HTMLTextAreaElement = HTMLTextAreaElement;
  `, context);
  vm.runInContext([
    constant("NEW_WINDOW_MENU_MS"), constant("NEW_WINDOW_RENAME_MS"), constant("NEW_WINDOW_RENAME_RE"),
    constant("NEW_WINDOW_MENU_SELECTOR"), constant("NEW_WINDOW_NAME_SELECTOR"),
    constant("NEW_WINDOW_INPUT_SELECTOR"), constant("NEW_WINDOW_ROWS_SELECTOR"),
    grab("newWindowMenuClose"), grab("newWindowNameField"), grab("newWindowNameText"),
    grab("newWindowNameSet"), grab("newWindowRename"),
    "globalThis.rename = newWindowRename;",
  ].join("\n"), context);
  return {
    dom,
    rename: context.rename,
    field: host => new context.HTMLInputElement(host),
    row: () => ({
      isConnected: true, menuOpened: 0,
      getBoundingClientRect: () => ({ left: 10, top: 20, width: 200, height: 30 }),
      dispatchEvent(event) { if (event.type === "contextmenu") this.menuOpened += 1; return true; },
      contains: node => node?.host === "rows",
      querySelector: () => null,
    }),
  };
};
const menuItem = text => ({ text, clicks: 0, textContent: text, click() { this.clicks += 1; } });
const dialogOf = field => ({ contains: node => node === field, querySelector: () => field });

test("имя: меню не открылось — отказ, и меню за собой погашено", async () => {
  const world = renameWorld();
  const row = world.row();
  assert.equal(await world.rename(row, "Dictatorik", 1), false);
  assert.equal(row.menuOpened, 1, "контекстное меню строке не послали");
  assert.equal(world.dom.closes, 1, "меню за собой не погасили");
});

test("имя: в меню нет пункта «Переименовать» — тот же честный отказ", async () => {
  const world = renameWorld();
  world.dom.menu = [menuItem("Открыть в отдельном окне"), menuItem("Удалить")];
  assert.equal(await world.rename(world.row(), "Dictatorik", 1), false);
  assert.equal(world.dom.closes, 1);
});

test("имя: пункт есть, поля нет — пункт нажат, имя никуда не уехало", async () => {
  const world = renameWorld();
  const rename = menuItem("Rename");
  world.dom.menu = [menuItem("Delete"), rename];
  assert.equal(await world.rename(world.row(), "Dictatorik", 1), false);
  assert.equal(rename.clicks, 1, "пункт «Rename» не нажали");
  assert.equal(world.dom.closes, 1);
});

test("имя: поле в модалке — родной сеттер, событие input и Enter", async () => {
  const world = renameWorld();
  world.dom.menu = [menuItem("Переименовать")];
  const box = world.field();
  box.dispatchEvent = function (event) {
    this.sent.push(event.key ?? event.type);
    if (event.key === "Enter") this.gone = true;   // модалка закрылась
    return true;
  };
  world.dom.dialogs = [dialogOf(box)];
  assert.equal(await world.rename(world.row(), "Dictatorik", 1), true);
  assert.equal(box.value, "Dictatorik");
  assert.ok(box.sent.includes("input"), "React не увидел бы значения без события input");
  assert.ok(box.sent.includes("Enter"), "подтверждения Enter не было");
  assert.equal(world.dom.closes, 0, "успешное переименование гасить меню не должно");
});

test("имя: поле осталось на экране — отказ и уборка за собой", async () => {
  const world = renameWorld();
  world.dom.menu = [menuItem("Rename")];
  world.dom.dialogs = [dialogOf(world.field())];
  assert.equal(await world.rename(world.row(), "Dictatorik", 1), false);
  assert.equal(world.dom.closes, 1, "зависшую модалку за собой не погасили");
});

test("имя: фокус в чужом поле — имя проекта туда не печатается", async () => {
  const world = renameWorld();
  world.dom.menu = [menuItem("Rename")];
  const stranger = world.field("search");
  world.dom.active = stranger;
  world.dom.rows = { contains: node => node?.host === "rows", querySelector: () => null };
  assert.equal(await world.rename(world.row(), "Dictatorik", 1), false);
  assert.equal(stranger.value, "Привет", "имя проекта уехало в чужое поле");
  assert.equal(world.dom.closes, 1);
});

test("имя: инлайн-поле внутри списка чатов — наше", async () => {
  const world = renameWorld();
  world.dom.menu = [menuItem("Rename")];
  const inline = world.field("rows");
  inline.dispatchEvent = function (event) {
    this.sent.push(event.key ?? event.type);
    if (event.key === "Enter") this.gone = true;
    return true;
  };
  world.dom.active = inline;
  world.dom.rows = { contains: node => node === inline, querySelector: () => inline };
  assert.equal(await world.rename(world.row(), "Dictatorik", 1), true);
  assert.equal(inline.value, "Dictatorik");
});
