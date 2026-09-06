// Ключ темы по id чата (раздел 2а inject.js, план WF35, пункт 20 списка Элвиса
// 05.09). До WF35 тема лежала под именем чата — `chat:<заголовок>`, — и любое
// переименование разговора теряло цвет: ключа со старым именем больше никто не
// читал. Теперь главный ключ — id (`id:local_<uuid>`), а имя осталось тенью для
// окон, которые своего id ещё не знают (попап в первые секунды: карту попапов
// наполняет probe приложения, раздел 12в).
//
// Умолчание стенда — https://claude.ai/epitaxy/local_test, поэтому у главного
// окна в наборах всегда есть известный id `local_test`.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";

const MAP_KEY = "myclaude-themes-v1";
const SESSION_KEY = "myclaude-theme-v1";
const ID_KEY = "id:local_test";

const theme = (id, accent = "#2299ff") => ({
  id, name: id, type: "dark",
  palette: { accent, background: "#001122", foreground: "#eeffff", sidebar: "#000811", panel: "#00223a", muted: "#88aabb" },
});
const font = (family = "SF Mono") => ({ id: family, family, mono: true });
const map = value => ({ [MAP_KEY]: JSON.stringify(value) });
const sessionOf = (key, entry) => ({ [SESSION_KEY]: JSON.stringify({ key, ...entry }) });
const readMap = win => JSON.parse(win.localStorage.getItem(MAP_KEY) ?? "null");

// Главное окно со стором попапов — родитель для попапов ниже (образец из
// tests/chat-id.test.mjs: боевой import() в vm бросает, поэтому импортёр
// подставной).
const parentWindow = (records = []) => {
  const loaded = loadInject({ href: "https://claude.ai/epitaxy/local_aaa", title: "Главное" });
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  const state = { popoutWindows: loaded.run("new Map()"), openPopout: () => {} };
  for (const [id, title] of records) state.popoutWindows.set(id, { title, sessionId: id, sessionType: "local" });
  const store = () => {};
  store.getState = () => state;
  loaded.inner.setModuleImporter(() => Promise.resolve({ Store: store }));
  return loaded;
};

test("id чата сильнее заголовка", () => {
  const { api } = loadInject({
    title: "Trelvis",
    storage: { local: map({ [ID_KEY]: { theme: theme("по id") }, "chat:Trelvis": { theme: theme("по имени") } }) },
  });
  assert.equal(api.status().theme.id, "по id");
  assert.equal(api.status().theme.source, "chat");
  assert.equal(api.status().chatKey, ID_KEY);
});

test("нет записи по id — берётся заголовок", () => {
  const { api } = loadInject({
    title: "Trelvis",
    storage: { local: map({ "chat:Trelvis": { theme: theme("по имени") } }) },
  });
  assert.equal(api.status().theme.id, "по имени", "старая карта красит как раньше");
  assert.equal(api.status().theme.source, "chat");
});

test("первое совпадение переносит запись на id, старую оставляет", () => {
  const loaded = loadInject({
    title: "Trelvis",
    storage: { local: map({ "chat:Trelvis": { theme: theme("цвет"), font: font("Menlo") } }) },
  });
  const stored = readMap(loaded.win);
  assert.deepEqual(Object.keys(stored).sort(), ["chat:Trelvis", ID_KEY].sort());
  assert.deepEqual(stored[ID_KEY], stored["chat:Trelvis"], "запись скопирована слой в слой");
  assert.equal(stored[ID_KEY].theme.id, "цвет");
  assert.equal(stored[ID_KEY].font.family, "Menlo");
});

test("перенос не трогает уже готовую запись по id", () => {
  const loaded = loadInject({
    title: "Trelvis",
    storage: { local: map({ [ID_KEY]: { theme: theme("по id") }, "chat:Trelvis": { theme: theme("по имени"), font: font("Menlo") } }) },
  });
  const stored = readMap(loaded.win);
  assert.equal(stored[ID_KEY].theme.id, "по id");
  assert.equal(stored[ID_KEY].font, undefined, "чужие слои тени не доливаются");
});

test("переименование чата ничего не сбивает", () => {
  // Под новым именем в карте нарочно лежит ЧУЖАЯ запись: по старой модели ключей
  // сторож заголовка перекрасил бы окно ею — значит проверка ловит и то, что
  // сторож вообще тикнул.
  const loaded = loadInject({
    title: "Trelvis",
    storage: { local: map({ "chat:Trelvis": { theme: theme("цвет") }, "chat:Совсем другое имя": { theme: theme("чужой") } }) },
  });
  assert.equal(loaded.api.status().theme.id, "цвет");
  loaded.document.title = "Совсем другое имя";
  loaded.dom.fireKind("interval");
  assert.equal(loaded.api.status().theme.id, "цвет", "id тот же — цвет остался");
  assert.equal(loaded.api.status().chatKey, ID_KEY, "ключ не изменился");
});

test("выбор пишется в оба ключа чата и в main", () => {
  const loaded = loadInject({ title: "Trelvis" });
  loaded.dom.command({ id: "1", action: "theme", at: "now", scope: "window", title: "Trelvis", theme: theme("цвет") });
  const stored = readMap(loaded.win);
  assert.deepEqual(Object.keys(stored), [ID_KEY, "chat:Trelvis", "main"]);
  for (const key of Object.keys(stored)) assert.equal(stored[key].theme.id, "цвет", key);
});

test("окно без id живёт на заголовке, переноса нет", () => {
  const popup = loadInject({
    href: "about:blank",
    title: "Trelvis",
    storage: { local: map({ "chat:Trelvis": { theme: theme("цвет") } }) },
  });
  assert.equal(popup.inner.chatIdKey(), null, "родителя нет — id спрашивать не у кого");
  assert.equal(popup.api.status().chatKey, "chat:Trelvis");
  assert.deepEqual(Object.keys(readMap(popup.win)), ["chat:Trelvis"], "ключа по id не появилось");
  assert.equal(popup.api.status().theme.id, "цвет");
});

test("id появился позже инжекта — перенос случился в syncChatTheme", async () => {
  const parent = parentWindow([["local_pop", "Trelvis"]]);
  const popup = loadInject({
    href: "about:blank",
    title: "Trelvis",
    opener: parent.win,
    storage: { local: map({ "chat:Trelvis": { theme: theme("цвет"), font: font("Menlo") } }) },
  });
  assert.deepEqual(Object.keys(readMap(popup.win)), ["chat:Trelvis"], "на инжекте id ещё нет");
  // Приложение спросило страницу — ответ родителя лёг в кэш окна.
  assert.equal(plain(await popup.api.chats({ scan: true })).self, "local_pop");
  assert.equal(popup.inner.chatIdKey(), "id:local_pop");
  // Страница не перезагружалась: перенос обязан случиться на стороже заголовка.
  popup.dom.fireKind("interval");
  const stored = readMap(popup.win);
  assert.deepEqual(Object.keys(stored).sort(), ["chat:Trelvis", "id:local_pop"].sort());
  assert.equal(stored["id:local_pop"].theme.id, "цвет");
  assert.equal(stored["id:local_pop"].font.family, "Menlo");
});

test("запись не обрезает запись по заголовку", async () => {
  const parent = parentWindow([["local_pop", "Trelvis"]]);
  const popup = loadInject({
    href: "about:blank",
    title: "Trelvis",
    opener: parent.win,
    storage: { local: map({ "chat:Trelvis": { theme: theme("цвет"), font: font("Menlo"), frame: true } }) },
  });
  assert.equal(plain(await popup.api.chats({ scan: true })).self, "local_pop");
  // Сторож заголовка ещё не тикнул: переноса не было, а команда уже приехала.
  popup.dom.command({ id: "2", action: "theme", at: "now", scope: "window", title: "Trelvis", font: font("Monaco") });
  const entry = readMap(popup.win)["id:local_pop"];
  assert.equal(entry.font.family, "Monaco", "слой команды записан");
  assert.equal(entry.theme.id, "цвет", "тема чата не потерялась");
  assert.equal(entry.frame, true, "рамка чата не потерялась");
});

test("сессия под старым ключом чата признаётся своей", () => {
  const { api, inner } = loadInject({
    title: "Trelvis",
    storage: {
      local: map({ main: { theme: theme("окно") } }),
      session: sessionOf("chat:Trelvis", { theme: theme("сессия") }),
    },
  });
  assert.equal(api.status().theme.id, "сессия");
  assert.equal(api.status().theme.source, "session");
  assert.equal(inner.sameSessionKey("chat:Trelvis"), true, "имя чата принимается");
  assert.equal(inner.sameSessionKey(ID_KEY), true, "id чата принимается");
  assert.equal(inner.sameSessionKey("chat:Чужой"), false);
});

test("чужая страница ключей не даёт вовсе", () => {
  for (const href of ["data:text/html,<p>артефакт</p>", "http://localhost:5173/"]) {
    const { inner } = loadInner({ title: "Артефакт", href });
    assert.equal(inner.chatIdKey(), null, href);
    assert.equal(inner.chatTitleKey(), null, href);
    assert.equal(inner.chatKey(), null, href);
    assert.equal(inner.sessionKey(), null, href);
    assert.equal(inner.themeKey(), null, href);
  }
});

test("themes в ответ probe кладёт только главное окно", async () => {
  const main = loadInject({ title: "Trelvis", storage: { local: map({ [ID_KEY]: { theme: theme("цвет") } }) } });
  const answer = plain(await main.api.chats({ nonce: "t1" }));
  assert.ok("themes" in answer, "главное окно карту отдаёт");
  assert.equal(answer.themes[ID_KEY].theme.id, "цвет");

  const parent = parentWindow([["local_pop", "Trelvis"]]);
  const popup = loadInject({ href: "about:blank", title: "Trelvis", opener: parent.win });
  assert.equal("themes" in plain(await popup.api.chats({ scan: true, nonce: "t2" })), false, "попап карту не шлёт");

  const alien = loadInject({ href: "data:text/html,<p>артефакт</p>", title: "Артефакт" });
  assert.equal("themes" in plain(await alien.api.chats({ nonce: "t3" })), false, "чужая страница карту не шлёт");
});
