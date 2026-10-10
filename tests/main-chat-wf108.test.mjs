// «Чат в главное окно» (WF108, #8148, раздел 12б inject.js): команда main-chat
// главному окну — открыть названный чат у себя и вынести прежний своим окном.
// Окно названного чата закрывает приложение до команды; здесь — только страница.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const drain = () => new Promise(resolve => setImmediate(resolve));
const settle = async (times = 6) => { for (let index = 0; index < times; index += 1) await drain(); };

const command = (extra = {}) => ({
  id: "m1", action: "main-chat", at: "now", scope: "window", title: "",
  x: 1000, y: 38, chat: "local_rick", ...extra,
});

// Стор попапов по форме настоящий (Map из реалма страницы + openPopout) — как в new-window.test.mjs.
const withStore = (loaded, { ready = true } = {}) => {
  const box = { ready, calls: [] };
  const value = { popoutWindows: loaded.run("new Map()"), openPopout: options => box.calls.push(options) };
  const store = () => {};
  store.getState = () => value;
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  loaded.inner.setModuleImporter(() => Promise.resolve(box.ready ? { Store: store } : {}));
  return box;
};
// Сайдбар: клик по строке открывает чат в главном окне — ровно это делает Claude.
const sidebar = (dom, rows) => {
  const list = dom.document.body.add("div", { attrs: { "data-testid": "sidebar-recents" } });
  for (const [id, title] of rows) {
    const row = list.add("div", { attrs: { "data-row-key": `code:${id}` }, text: title });
    row.addEventListener("click", () => { dom.window.location.pathname = `/epitaxy/${id}`; });
  }
  return {};
};
const rows = [["local_mine", "ВкусУчёт"], ["local_rick", "Рик"]];

test("главное окно открывает чат у себя и выносит прежний в точку команды", async () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_mine", title: "Claude", html: dom => sidebar(dom, rows),
  });
  const store = withStore(loaded);
  loaded.dom.command(command());
  await settle();
  const mark = loaded.api.status().newWindow;
  assert.equal(mark.state, "ok");
  assert.equal(mark.id, "local_mine", "id — вынесенный прежний чат: по нему приложение ждёт окно");
  assert.equal(mark.busy, false);
  assert.equal(loaded.win.location.pathname, "/epitaxy/local_rick");
  assert.equal(store.calls.length, 1);
  assert.equal(store.calls[0].sessionId, "local_mine");
  assert.equal(store.calls[0].title, "ВкусУчёт", "заголовок — строка сайдбара прежнего чата");
  assert.deepEqual({ ...store.calls[0].initialPosition }, { x: 1000, y: 38 });
});

test("чат уже в главном окне — ничего не трогаем", async () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_rick", title: "Claude", html: dom => sidebar(dom, rows),
  });
  const store = withStore(loaded);
  loaded.dom.command(command());
  await settle();
  assert.equal(loaded.api.status().newWindow.state, "already");
  assert.equal(store.calls.length, 0);
});

test("с домашнего экрана выносить нечего — только переход", async () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy", title: "Claude", html: dom => sidebar(dom, rows),
  });
  const store = withStore(loaded);
  loaded.dom.command(command());
  await settle();
  const mark = loaded.api.status().newWindow;
  assert.equal(mark.state, "ok");
  assert.equal(mark.id, null);
  assert.equal(loaded.win.location.pathname, "/epitaxy/local_rick");
  assert.equal(store.calls.length, 0);
});

test("строки нет и роутера нет — chat-missing, главное окно на месте", async () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_mine", title: "Claude", html: dom => sidebar(dom, [rows[0]]),
  });
  const store = withStore(loaded);
  loaded.dom.command(command());
  await settle();
  const mark = loaded.api.status().newWindow;
  assert.equal(mark.state, "chat-missing");
  assert.equal(mark.busy, false);
  assert.equal(loaded.win.location.pathname, "/epitaxy/local_mine");
  assert.equal(store.calls.length, 0);
});

test("битая команда и чужое окно", async () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_mine", title: "Claude", html: dom => sidebar(dom, rows),
  });
  withStore(loaded);
  for (const detail of [command({ chat: "Rick" }), command({ x: "1000" }), command({ scope: "all" })]) {
    loaded.dom.command(detail);
    await settle(2);
    assert.equal(loaded.api.status().newWindow.state, "bad-command", JSON.stringify(detail));
  }
  assert.equal(loaded.win.location.pathname, "/epitaxy/local_mine");
  const popup = loadInject({ href: "about:blank", title: "Рик" });
  popup.dom.command(command());
  await settle(2);
  assert.equal(popup.api.status().newWindow, null, "попап команду не берёт вовсе");
});

test("пока идёт «Новое окно» — busy", async () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_mine", title: "Claude", html: dom => sidebar(dom, rows),
  });
  withStore(loaded);
  loaded.dom.command({ id: "n1", action: "new-window", at: "now", scope: "window", title: "Claude",
    x: 100, y: 200, text: "Привет" });
  assert.equal(loaded.api.status().newWindow.busy, true);
  loaded.dom.command(command({ id: "m2" }));
  assert.equal(loaded.api.status().newWindow.state, "busy");
  assert.equal(loaded.win.location.pathname, "/epitaxy/local_mine");
  await settle();
});
