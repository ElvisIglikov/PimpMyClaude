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
import { readFileSync } from "node:fs";
import { loadInject, plain } from "./load.mjs";

const MAIN = "https://claude.ai/epitaxy/local_aaa";
// Кэш ответа про свой чат — sessionStorage окна (раздел 12в inject.js).
const CHAT_ID_KEY = "myclaude-chat-v1";
// Рамки окон Элвиса в шестых долях Odyssey (замер 20.09): [screenX, screenY,
// outerWidth, outerHeight]. Ими ответ probe отличает одноимённые окна (WF77).
const FRAME_MAIN = [-792, -842, 496, 838];
const FRAME_POPOUT = [-290, -842, 496, 838];

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

// ---- Папка домашнего экрана (WF37, задача #5576) ----------------------------
// Пока чат не открыт, сессии на диске нет и приложению папку взять неоткуда —
// главное окно оставалось некрашеным, хотя чип над полем ввода проект уже
// показывает. Этот выбор живёт в сторе claude.ai, и ответ chats() теперь его
// называет — но только у главного окна и только на домашнем экране.
const fixture = name => JSON.parse(readFileSync(new URL(`./fixtures/cashout/${name}.json`, import.meta.url), "utf8"));
const drain = async () => { for (let step = 0; step < 4; step += 1) await new Promise(setImmediate); };

// Домашний экран со стором папки. folder === null — стор, который нам не
// годится (папку выбирать нечем): такой же ответ null, только навсегда.
const homeWindow = (folder = "/Users/elvis/_ElvisProjects/PimpMyClaude", options = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy",
    title: "Claude",
    html: dom => ({ input: dom.document.body.add("div", { attrs: { "data-testid": "code-prompt-input" } }) }),
    ...options,
  });
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  const state = folder == null
    ? { theme: "dark" }
    : { selectedFolder: folder, setLocalSelectedFolder: () => {}, setTrustedSelectedFolder: () => {} };
  const store = () => {};
  store.getState = () => state;
  const counter = { imports: 0 };
  loaded.inner.setModuleImporter(() => { counter.imports += 1; return Promise.resolve({ Store: store }); });
  return { loaded, counter, state };
};

test("папка домашнего экрана: первый круг — скан, второй — путь", async () => {
  const home = homeWindow("/Users/elvis/_ElvisProjects/PimpMyClaude/");
  const first = plain(await home.loaded.api.chats({ nonce: "f1" }));
  assert.equal(first.folder, null, "скан идёт около секунды — ответ probe его не ждёт");
  await drain();
  const second = plain(await home.loaded.api.chats({ nonce: "f2" }));
  assert.equal(second.folder, "/Users/elvis/_ElvisProjects/PimpMyClaude", "хвостовой слэш папку не меняет");
  assert.equal(home.loaded.api.status().chat.folder, second.folder, "то же поле в status()");
  const third = plain(await home.loaded.api.chats({ nonce: "f3" }));
  assert.equal(third.folder, second.folder);
  assert.equal(home.counter.imports, 1, "стор ищется один раз — чужие модули по разу");
});

test("папки нет: стор не годится — null и молчание", async () => {
  const home = homeWindow(null);
  assert.equal(plain(await home.loaded.api.chats({ nonce: "f4" })).folder, null);
  await drain();
  assert.equal(plain(await home.loaded.api.chats({ nonce: "f5" })).folder, null, "выбирать папку нечем");
  assert.equal(home.loaded.api.status().chat.folder, null);

  const empty = homeWindow("");
  await drain();
  await empty.loaded.api.chats({ nonce: "f6" });
  await drain();
  assert.equal(plain(await empty.loaded.api.chats({ nonce: "f7" })).folder, null, "пустой выбор — не папка");
});

test("status() папку из кэша берёт, а скана не запускает", async () => {
  const home = homeWindow();
  assert.equal(home.loaded.api.status().chat.folder, null, "стор ещё не найден");
  assert.equal(home.counter.imports, 0, "status() чужих модулей не исполняет");
  await home.loaded.api.chats({ nonce: "f8" });
  await drain();
  assert.equal(home.loaded.api.status().chat.folder, "/Users/elvis/_ElvisProjects/PimpMyClaude");
});

test("папку называет только главное окно и только на домашнем экране", async () => {
  const chat = homeWindow("/Users/elvis/_ElvisProjects/PimpMyClaude", { href: MAIN, title: "Pimp" });
  await chat.loaded.api.chats({ nonce: "f9" });
  await drain();
  const open = plain(await chat.loaded.api.chats({ nonce: "f10" }));
  assert.equal(open.folder, null, "в открытом чате правду говорит индекс сессий");
  assert.equal(chat.counter.imports, 0, "и стор папки в открытом чате не ищется вовсе");

  const parent = mainWindow([["local_c4abc832", "Bro Flow продолжение"]]);
  const popup = loadInject({ href: "about:blank", title: "Bro Flow продолжение", opener: parent.loaded.win });
  assert.equal(plain(await popup.api.chats({ scan: true, nonce: "f11" })).folder, null, "у попапа своего выбора нет");

  const stranger = homeWindow("/Users/elvis/_ElvisProjects/PimpMyClaude", { href: "data:text/html,<p>артефакт</p>" });
  assert.equal(plain(await stranger.loaded.api.chats({ scan: true, nonce: "f12" })).folder, null, "чужая страница");
});

test("порядок ключей ответа — по эталонам probe-answer-*", async () => {
  const home = homeWindow(undefined, { geometry: { frame: FRAME_MAIN } });
  await home.loaded.api.chats({ nonce: "f13" });
  await drain();
  assert.deepEqual(
    Object.keys(plain(await home.loaded.api.chats({ nonce: "f14" }))),
    Object.keys(fixture("probe-answer-home")),
    "folder стоит после store и перед at, дальше frame, themes — в хвосте",
  );

  const parent = mainWindow([["local_4dae798d-aed9-42d7-bd1b-3631eb360c07", "VkusnoffKz 2"]], {
    geometry: { frame: FRAME_MAIN },
  });
  assert.deepEqual(
    Object.keys(plain(await parent.loaded.api.chats({ scan: true, nonce: "f15" }))),
    Object.keys(fixture("probe-answer-chat")),
  );

  const popup = loadInject({
    href: "about:blank",
    title: "VkusnoffKz 2",
    opener: parent.loaded.win,
    geometry: { frame: FRAME_POPOUT },
  });
  assert.deepEqual(
    Object.keys(plain(await popup.api.chats({ scan: true, nonce: "f16" }))),
    Object.keys(fixture("probe-answer-popout")),
    "карты тем у попапа нет — и поля themes тоже, frame стоит последним",
  );
});

// ---- Своё волокно и рамка окна (WF77, задача #6734) -------------------------
// У Элвиса одинаковые заголовки окон — норма («Ожидание задачи» у каждого
// попапа), а попап спрашивал свой чат у родителя ПО ЗАГОЛОВКУ: обоим доставался
// один и тот же id, и команда уходила в оба окна разом — «меняю цвет, меняется
// у обоих» (слово Элвиса 20.09). Теперь попап сперва читает свой sessionId из
// СОБСТВЕННОГО React-волокна, а в ответ probe кладёт ещё и рамку окна: по ней
// приложение различает одноимённые окна.
const SAME_TITLE = "Ожидание задачи";
const FIRST_ID = "local_abe07c3d";
const SECOND_ID = "local_a4c290f1";

// Цепочка волокон снизу вверх: у самого узла пропсов нет, sessionId лежит у
// компонентов НАД панелью — как в живом Claude (проба 20.09).
const fiberChain = (...ids) => {
  let top = null;
  for (const id of [...ids].reverse()) top = { memoizedProps: { sessionId: id }, return: top };
  return { memoizedProps: { children: [] }, return: top };
};

// Попап с разметкой панели чата. ids — что лежит в волокне; пусто — волокна нет
// вовсе (так выглядит релиз Claude, переименовавший пропс). fiberAt — на каком
// из двух стартовых узлов оно висит: обход начинается с обоих.
const popupWindow = ({ title = SAME_TITLE, ids = [], fiberAt = "panel", opener = null, storage, geometry } = {}) =>
  loadInject({
    href: "about:blank",
    title,
    opener,
    storage,
    geometry,
    html: dom => {
      const panel = dom.document.body.add("div", { class: "epitaxy-chat-panel" });
      const bar = panel.add("div", { class: "epitaxy-titlebar" });
      if (ids.length) (fiberAt === "panel" ? panel : bar).__reactFiber$test = fiberChain(...ids);
      return { panel, bar };
    },
  });

test("два попапа с одним заголовком называют РАЗНЫЕ чаты", async () => {
  const parent = mainWindow([[FIRST_ID, SAME_TITLE], [SECOND_ID, SAME_TITLE]]);
  const first = popupWindow({ ids: [FIRST_ID], opener: parent.loaded.win });
  // Второй держит волокно на титульной полосе — обход стартует и оттуда.
  const second = popupWindow({ ids: [SECOND_ID], fiberAt: "titlebar", opener: parent.loaded.win });
  assert.equal(await parent.loaded.api.popoutChat(SAME_TITLE, { scan: true }), null,
    "родитель по заголовку не назвал бы ни одного — с него и начиналась беда");

  const answer = plain(await first.api.chats({ scan: true, nonce: "w1" }));
  assert.equal(answer.self, FIRST_ID);
  assert.equal(answer.store, "ok", "спросили источник — своё волокно");
  assert.equal(plain(await second.api.chats({ scan: true, nonce: "w2" })).self, SECOND_ID);
  assert.equal(first.api.status().chat.self, FIRST_ID, "и синхронный слепок тот же");
  assert.equal(second.api.status().chat.self, SECOND_ID);
  assert.equal(JSON.parse(first.win.sessionStorage.getItem(CHAT_ID_KEY)).id, FIRST_ID,
    "ответ волокна лёг в кэш ещё на инжекте — переживёт перезапись inject.js");
});

test("кэш, спорящий с волокном, отбрасывается и переписывается", async () => {
  const popup = popupWindow({
    ids: [SECOND_ID],
    storage: { session: { [CHAT_ID_KEY]: JSON.stringify({ id: FIRST_ID, title: SAME_TITLE }) } },
  });
  assert.equal(popup.inner.chatFiberId(), SECOND_ID);
  assert.equal(popup.api.status().chat.self, SECOND_ID, "волокно сильнее кэша");
  assert.equal(JSON.parse(popup.win.sessionStorage.getItem(CHAT_ID_KEY)).id, SECOND_ID,
    "спорная запись переписана: она уже уводила чужую команду в это окно");
  assert.equal(plain(await popup.api.chats({ scan: true })).self, SECOND_ID);
});

test("в волокне два разных id — ответ null, на заголовок не падаем", async () => {
  const parent = mainWindow([[FIRST_ID, SAME_TITLE]]);
  const popup = popupWindow({ ids: [SECOND_ID, FIRST_ID], opener: parent.loaded.win });
  assert.equal(popup.inner.chatFiberId(), "", "согласия нет — волокно отвечает «не знаю»");
  const answer = plain(await popup.api.chats({ scan: true, nonce: "w3" }));
  assert.equal(answer.self, null, "чужой чат хуже, чем «не определён»");
  assert.equal(answer.store, "ok");
  assert.equal(popup.api.status().chat.self, null);
});

test("волокна нет — прежний путь через родителя", async () => {
  const parent = mainWindow([["local_c4abc832", "Bro Flow продолжение"]]);
  const popup = popupWindow({ title: "Bro Flow продолжение", opener: parent.loaded.win });
  assert.equal(popup.inner.chatFiberId(), null, "панель есть, волокна у неё нет");
  const answer = plain(await popup.api.chats({ scan: true, nonce: "w4" }));
  assert.equal(answer.self, "local_c4abc832");
  assert.equal(answer.store, "ok");
});

test("myChatId() на инжекте с пустым DOM не бросает", () => {
  const bare = loadInject({ href: "about:blank", title: "" });
  assert.equal(bare.error, null, "инжект прошёл целиком");
  assert.equal(bare.failure, null);
  assert.equal(bare.inner.chatFiberId(), null, "стартовых узлов нет — и ошибки нет");
  assert.equal(bare.inner.myChatId(), null);
  assert.equal(bare.api.status().chat.self, null);

  // Разметка попапа приезжает ПОЗЖЕ инжекта: промах не запоминается, иначе окно
  // осталось бы без своего id навсегда.
  const panel = bare.document.body.add("div", { class: "epitaxy-chat-panel" });
  panel.__reactFiber$test = fiberChain(SECOND_ID);
  assert.equal(bare.inner.myChatId(), SECOND_ID, "панель появилась — id нашёлся");
});

test("ответ несёт рамку окна, у чужой страницы её нет", async () => {
  const main = mainWindow([], { geometry: { frame: FRAME_MAIN } });
  assert.deepEqual(plain(await main.loaded.api.chats({ nonce: "w5" })).frame, FRAME_MAIN,
    "[screenX, screenY, outerWidth, outerHeight]");

  const popup = popupWindow({ ids: [SECOND_ID], geometry: { frame: [-290.4, -842, 495.6, 838] } });
  assert.deepEqual(plain(await popup.api.chats({ nonce: "w6" })).frame, FRAME_POPOUT, "числа целые");

  const alien = loadInject({ href: "data:text/html,<p>артефакт</p>", geometry: { frame: FRAME_MAIN } });
  assert.equal("frame" in plain(await alien.api.chats({ nonce: "w7" })), false,
    "артефакт живёт в чужом окне — его рамку за свою не выдаём");

  const blind = mainWindow([]);
  assert.equal("frame" in plain(await blind.loaded.api.chats({ nonce: "w8" })), false,
    "чисел браузер не дал — поля нет вовсе");
});
