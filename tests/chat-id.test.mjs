// «Кто этот чат» (раздел 12в inject.js, план WF29): страница сама называет id
// своего чата, а приложение спрашивает её через probe.js. До WF29 окно
// опознавалось заголовком, и попапы с переименованными чатами не опознавались
// вовсе — отсюда чужие цвета (#5455) и цвет, не поехавший за папкой (#5448).
//
// Стор попапов настоящий по форме (Map из реалма страницы + openPopout), но
// приезжает подставным импортёром: боевой import() в vm без опции
// importModuleDynamically бросает, и его молча съедает catch на каждый адрес —
// поэтому у импортёра есть сиденье (setModuleImporter, решение 4 плана).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const MAIN = "https://claude.ai/epitaxy/local_aaa";

// Главное окно со стором попапов. records — пары [id чата, заголовок окна],
// ровно как в живой карте popoutWindows. counter.imports — сколько раз скан
// дошёл до import(): им и считаются «импортов ноль» и «скан ровно один».
const mainWindow = (records = [], options = {}) => {
  const { throws = false, ...rest } = options;
  const loaded = loadInject({ href: MAIN, title: "Pimp", ...rest });
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  const state = { popoutWindows: loaded.run("new Map()"), openPopout: () => {} };
  for (const [id, title] of records) state.popoutWindows.set(id, { title, sessionId: id, sessionType: "local" });
  const store = () => {};
  store.getState = () => {
    if (throws) throw new Error("чужой модуль упал");
    return state;
  };
  const counter = { imports: 0 };
  loaded.inner.setModuleImporter(() => { counter.imports += 1; return Promise.resolve({ Store: store }); });
  return { loaded, counter, state };
};

test("chats() в главном окне отдаёт id из пути", async () => {
  const { loaded } = mainWindow([], {
    html: dom => {
      const row = dom.document.body.add("div", {
        attrs: { "data-row-key": "code:local_aaa", "data-selected": "focused" },
      });
      return { row };
    },
  });
  const answer = plain(await loaded.api.chats({ nonce: "g1" }));
  assert.equal(answer.v, 1);
  assert.equal(answer.nonce, "g1");
  assert.equal(answer.kind, "main");
  assert.equal(answer.self, "local_aaa");
  assert.equal(answer.path, "/epitaxy/local_aaa");
  assert.equal(answer.title, "Pimp");
  assert.equal(answer.row, "local_aaa", "активная строка сайдбара — только для сверки на гейте");
  assert.equal(typeof answer.at, "number");
  const bare = loadInject({ href: "https://claude.ai/epitaxy", title: "Claude" });
  const home = plain(await bare.api.chats({ nonce: "g1b" }));
  assert.equal(home.self, null, "домашний экран чатом не является");
  assert.equal(home.row, null, "строки сайдбара нет — поля нет");
});

test("chats() на чужой странице молчит", async () => {
  for (const href of [
    "data:text/html,<p>артефакт</p>",
    "file:///Applications/Claude.app/Contents/Resources/app.asar/.vite/renderer/main_window/index.html",
    "http://localhost:5173/",
  ]) {
    const { loaded, counter } = mainWindow([["local_x", "Чат"]], { href });
    const answer = plain(await loaded.api.chats({ scan: true, nonce: "g2" }));
    assert.equal(answer.kind, "other", href);
    assert.equal(answer.self, null, href);
    assert.equal(answer.store, "skip", href);
    assert.deepEqual(answer.popouts, [], href);
    assert.equal(answer.path, "", href, "адрес чужой страницы наружу не отдаём: у артефакта это data: целиком");
    assert.equal(counter.imports, 0, href);
  }
});

test("главное окно отдаёт карту попапов", async () => {
  const { loaded, counter } = mainWindow([
    ["local_c4abc832", "Bro Flow продолжение"],
    ["local_a55be545", "Workflow продолжение"],
  ]);
  const answer = plain(await loaded.api.chats({ scan: true, nonce: "g3" }));
  assert.equal(answer.store, "ok");
  assert.deepEqual(answer.popouts, [
    { id: "local_c4abc832", title: "Bro Flow продолжение" },
    { id: "local_a55be545", title: "Workflow продолжение" },
  ]);
  assert.equal(counter.imports, 1);
  const again = plain(await loaded.api.chats({ scan: true, nonce: "g3b" }));
  assert.equal(again.store, "cache", "карта свежая — второй скан не нужен");
  assert.equal(again.popouts.length, 2);
  assert.equal(counter.imports, 1);
});

test("скан не идёт без флага", async () => {
  const { loaded, counter } = mainWindow([["local_c4abc832", "Bro Flow продолжение"]]);
  const answer = plain(await loaded.api.chats({ nonce: "g4" }));
  assert.deepEqual(answer.popouts, []);
  assert.equal(answer.store, "none");
  assert.equal(counter.imports, 0, "чужие модули без просьбы не исполняем");
  assert.equal(answer.self, "local_aaa", "свой id из пути виден и без скана");
});

test("попап спрашивает родителя", async () => {
  const parent = mainWindow([["local_c4abc832", "Bro Flow продолжение"]]);
  const popup = loadInject({ href: "about:blank", title: "Bro Flow продолжение", opener: parent.loaded.win });
  const answer = plain(await popup.api.chats({ scan: true, nonce: "g5" }));
  assert.equal(answer.kind, "popout");
  assert.equal(answer.self, "local_c4abc832");
  assert.equal(answer.store, "ok");
  assert.equal(answer.path, "blank", "своего адреса у попапа нет — match ему бесполезен");
  assert.deepEqual(answer.popouts, [], "карта попапов есть только у главного окна");
  assert.equal(popup.api.status().chat.self, "local_c4abc832", "ответ лёг в кэш окна");
  // Лоадер перечитывает inject.js по mtime и гоняет его в том же окне снова:
  // кэш в sessionStorage это переживает, кэш в замыкании — нет.
  popup.reload();
  assert.equal(popup.api.status().chat.self, "local_c4abc832");
  assert.equal(popup.api.status().chat.store, null, "после перезапуска карта пуста, а id на месте");
});

test("попап без opener и с чужим заголовком — null", async () => {
  const alone = loadInject({ href: "about:blank", title: "Bro Flow продолжение" });
  const first = plain(await alone.api.chats({ scan: true }));
  assert.equal(first.self, null, "родителя нет — спрашивать некого");
  assert.equal(first.store, "none");

  const mute = loadInject({ href: "about:blank", title: "Bro Flow продолжение", opener: {} });
  const second = plain(await mute.api.chats({ scan: true }));
  assert.equal(second.self, null, "у родителя нет __myclaude");
  assert.equal(second.store, "none");

  const parent = mainWindow([["local_a55be545", "Workflow продолжение"]]);
  const stranger = loadInject({ href: "about:blank", title: "Bro Flow продолжение", opener: parent.loaded.win });
  const third = plain(await stranger.api.chats({ scan: true }));
  assert.equal(third.self, null, "заголовка нет в карте — id нет");
  assert.equal(third.store, "ok", "канал сработал: окно «не определён», а не деградация по заголовку");
});

test("два попапа с одним заголовком — null", async () => {
  const parent = mainWindow([
    ["local_first", "Workflow продолжение"],
    ["local_second", "Workflow продолжение"],
  ]);
  assert.equal(await parent.loaded.api.popoutChat("Workflow продолжение", { scan: true }), null,
    "ничья — лучше не записать выбор, чем записать в чужой проект");
  const popup = loadInject({ href: "about:blank", title: "Workflow продолжение", opener: parent.loaded.win });
  const answer = plain(await popup.api.chats({ scan: true }));
  assert.equal(answer.self, null);
  assert.equal(answer.store, "ok");
});

test("заглушка заголовка id не даёт", async () => {
  const parent = mainWindow([["local_stub", "Claude"], ["local_new", "New chat"]]);
  await parent.loaded.api.chats({ scan: true });
  for (const stub of ["Claude", "New chat", "Новый чат", "claude", "  new chat  "]) {
    assert.equal(await parent.loaded.api.popoutChat(stub, { scan: true }), null, stub);
  }
  assert.equal(await parent.loaded.api.popoutChat("", { scan: true }), null, "пустой заголовок");
  assert.equal(await parent.loaded.api.popoutChat(null, { scan: true }), null, "не строка");
  const popup = loadInject({ href: "about:blank", title: "Claude", opener: parent.loaded.win });
  const answer = plain(await popup.api.chats({ scan: true }));
  assert.equal(answer.self, null);
  assert.equal(answer.store, "none", "у заглушки спрашивать нечего — она у всех окон одна");
});

test("chats() не бросает", async () => {
  const broken = mainWindow([["local_x", "Чат"]], { throws: true });
  const answer = plain(await broken.loaded.api.chats({ scan: true, nonce: "g9" }));
  assert.equal(answer.store, "none", "стор упал — карты нет, но ответ есть");
  assert.equal(answer.self, "local_aaa");
  assert.deepEqual(answer.popouts, []);

  const dead = mainWindow([["local_x", "Чат"]]);
  dead.loaded.inner.setModuleImporter(() => { throw new Error("чанк не загрузился"); });
  const second = plain(await dead.loaded.api.chats({ scan: true }));
  assert.equal(second.store, "none");
  assert.equal(second.kind, "main");
});

test("одновременные scan складываются в один", async () => {
  const many = mainWindow([["local_c4abc832", "Bro Flow продолжение"]]);
  const answers = await Promise.all([
    many.loaded.api.chats({ scan: true }),
    many.loaded.api.chats({ scan: true }),
    many.loaded.api.chats({ scan: true }),
  ]);
  const single = mainWindow([["local_c4abc832", "Bro Flow продолжение"]]);
  await single.loaded.api.chats({ scan: true });
  assert.equal(single.counter.imports, 1, "один скан — один import");
  assert.equal(many.counter.imports, single.counter.imports, "три просьбы разом стоят одного скана");
  for (const answer of answers) {
    assert.equal(plain(answer).popouts.length, 1);
    assert.equal(plain(answer).store, "ok");
  }
});

test("status().chat синхронный и из кэша", async () => {
  const { loaded, counter } = mainWindow([["local_c4abc832", "Bro Flow продолжение"]]);
  const before = loaded.api.status().chat;
  assert.equal(typeof before.then, "undefined", "status() промиса не отдаёт");
  assert.equal(before.kind, "main");
  assert.equal(before.self, "local_aaa");
  assert.equal(before.store, null, "до вопроса карты нет");
  assert.equal(before.popouts, 0);
  assert.equal(before.at, null);
  assert.equal(counter.imports, 0, "status() скана не запускает");
  await loaded.api.chats({ scan: true });
  const after = loaded.api.status().chat;
  assert.equal(after.store, "ok");
  assert.equal(after.popouts, 1);
  assert.equal(typeof after.at, "number");
  assert.equal(counter.imports, 1);
});
