// «Новое окно» и «В отдельное окно» (раздел 12б inject.js) — только чистые
// помощники и охраны команды. Полный сценарий (⌘N → «Привет» → отправка →
// popout → возврат главного окна) в node не воспроизводим: он весь про
// асинхронную вёрстку claude.ai. Это работа живого гейта, а не стаба
// (план WF24, решение 3).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner } from "./load.mjs";

const command = (extra = {}) => ({
  id: "n1", action: "new-window", at: "now", scope: "window", title: "Claude",
  x: 100, y: 200, text: "Привет", ...extra,
});

test("newWindowSegment берёт последний кусок пути", () => {
  const { inner } = loadInner({ href: "https://claude.ai/epitaxy/local_abc" });
  assert.equal(inner.newWindowSegment("/epitaxy/local_f44e46bb"), "local_f44e46bb");
  assert.equal(inner.newWindowSegment("/epitaxy/local_abc/"), "local_abc", "хвостовой слэш не мешает");
  assert.equal(inner.newWindowSegment("/epitaxy"), "epitaxy");
  assert.equal(inner.newWindowSegment("/"), "");
  assert.equal(inner.newWindowSegment(""), "");
  assert.equal(inner.newWindowSegment(null), "");
  assert.equal(inner.newWindowSegment(42), "42");
});

test("сессия popout берётся только с /epitaxy/local_<id>", () => {
  const open = loadInner({ href: "https://claude.ai/epitaxy/local_f44e46bb" });
  assert.equal(open.inner.newWindowSessionId(), "local_f44e46bb");
  for (const href of ["https://claude.ai/epitaxy", "https://claude.ai/chat/abc", "https://claude.ai/"]) {
    const other = loadInner({ href });
    assert.equal(other.inner.newWindowSessionId(), "", href);
  }
});

test("домашний экран узнаётся по пути и полю ввода", () => {
  const home = loadInject({
    href: "https://claude.ai/epitaxy",
    html: dom => ({ input: dom.document.body.add("div", { attrs: { "data-testid": "code-prompt-input" } }) }),
  });
  assert.equal(home.inner.newWindowAtHome(), true);
  const bare = loadInner({ href: "https://claude.ai/epitaxy" });
  assert.equal(bare.inner.newWindowAtHome(), false, "путь тот, а поля ввода нет — не домашний экран");
  const chat = loadInject({
    href: "https://claude.ai/epitaxy/local_abc",
    html: dom => ({ input: dom.document.body.add("div", { attrs: { "data-testid": "code-prompt-input" } }) }),
  });
  assert.equal(chat.inner.newWindowAtHome(), false, "открытый чат домашним экраном не считается");
});

test("стор popout признаётся только с popoutWindows и openPopout", () => {
  const { inner, win } = loadInner({ href: "https://claude.ai/epitaxy/local_abc" });
  // Map обязана быть из ТОГО ЖЕ реалма: страница проверяет instanceof Map.
  const makeMap = () => win.eval("new Map()");
  assert.equal(inner.newWindowStoreOk({ getState: () => ({ popoutWindows: makeMap(), openPopout: () => {} }) }), true);
  assert.equal(inner.newWindowStoreOk({ getState: () => ({ popoutWindows: makeMap() }) }), false, "нет openPopout");
  assert.equal(inner.newWindowStoreOk({ getState: () => ({ openPopout: () => {} }) }), false, "нет popoutWindows");
  assert.equal(inner.newWindowStoreOk({ getState: () => ({ popoutWindows: {}, openPopout: () => {} }) }), false,
    "popoutWindows не Map");
  assert.equal(inner.newWindowStoreOk({}), false, "нет getState");
  assert.equal(inner.newWindowStoreOk(null), false);
  assert.equal(inner.newWindowStoreOk({ getState: () => { throw new Error("чужой модуль упал"); } }), false,
    "падение чужого модуля не выходит наружу");
});

test("битая команда до работы не доходит", async () => {
  const loaded = loadInject({ href: "https://claude.ai/epitaxy/local_abc", title: "Claude" });
  for (const [what, detail] of [
    ["scope не window", command({ scope: "all" })],
    ["нет текста", command({ text: "" })],
    ["координаты строками", command({ x: "100", y: "200" })],
    ["координаты не пришли", command({ x: undefined, y: undefined })],
  ]) {
    assert.equal(await loaded.inner.runNewWindowCommand(detail), false, what);
    assert.equal(loaded.api.status().newWindow.state, "bad-command", what);
  }
});

test("папка — только абсолютный путь", async () => {
  const loaded = loadInject({ href: "https://claude.ai/epitaxy/local_abc", title: "Claude" });
  assert.equal(await loaded.inner.runNewWindowCommand(command({ folder: "относительный/путь" })), false);
  const mark = loaded.api.status().newWindow;
  assert.equal(mark.state, "bad-command");
  assert.equal(mark.step, "folder", "видно, на чём споткнулись");
});

test("второй клик, пока идёт первый, метится busy", async () => {
  const loaded = loadInject({ href: "https://claude.ai/epitaxy/local_abc", title: "Claude" });
  // Первый запуск уходит искать стор (его на пустой странице нет) и остаётся
  // занятым; второй обязан отбиться сразу.
  loaded.inner.runNewWindowCommand(command()).catch(() => {});
  assert.equal(loaded.api.status().newWindow.busy, true, "первый запуск занял кнопку");
  assert.equal(await loaded.inner.runNewWindowCommand(command({ id: "n2" })), false);
  assert.equal(loaded.api.status().newWindow.state, "busy");
});

test("команду берёт только главное окно", async () => {
  const popup = loadInject({ href: "about:blank", title: "Второе окно" });
  assert.equal(await popup.inner.runNewWindowCommand(command({ title: "Второе окно" })), false);
  assert.equal(popup.api.status().newWindow, null, "подчинённое окно даже не помечает запуск");
});

test("адресация окна: поле match сверяется с путём страницы", async () => {
  const loaded = loadInject({ href: "https://claude.ai/epitaxy/local_f44e46bb", title: "Claude", hasFocus: false });
  assert.equal(await loaded.inner.runNewWindowCommand(command({ match: "/epitaxy/local_zzz", x: "нет" })), false);
  assert.equal(loaded.api.status().newWindow, null, "чужой путь — команда не наша, метки нет");
  assert.equal(await loaded.inner.runNewWindowCommand(command({ match: "/epitaxy/local_f44e46bb", text: "" })), false);
  assert.equal(loaded.api.status().newWindow.state, "bad-command", "свой путь — команда наша, отбили по контракту");
});
