// «Новое окно» и «В отдельное окно» (раздел 12б inject.js) — только чистые
// помощники и охраны команды. Полный сценарий (⌘N → «Привет» → отправка →
// popout → возврат главного окна) в node не воспроизводим: он весь про
// асинхронную вёрстку claude.ai. Это работа живого гейта, а не стаба
// (план WF24, решение 3).
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { loadInject, loadInner } from "./load.mjs";

const CASHOUT_KEY = "myclaude-cashout";
const fixture = name => JSON.parse(readFileSync(new URL(`./fixtures/cashout/${name}.json`, import.meta.url), "utf8"));
// Запись донора «Обкэшить», которая ждёт адресата (WF37).
const pending = () => JSON.stringify({ ...fixture("record-pending"), at: Date.now() });

// Команда «нового окна» асинхронная и запускается «в фон» (newWindowStart), так
// что после отправки события даём микрозадачам добежать до первой охраны.
const drain = () => new Promise(resolve => setImmediate(resolve));

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
  const loaded = loadInner({ href: "https://claude.ai/epitaxy/local_abc" });
  const { inner } = loaded;
  // Map обязана быть из ТОГО ЖЕ реалма: страница проверяет instanceof Map.
  const makeMap = () => loaded.run("new Map()");
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
    loaded.dom.command(detail);
    await drain();
    assert.equal(loaded.api.status().newWindow.state, "bad-command", what);
    assert.equal(loaded.api.status().newWindow.busy, undefined, `${what}: кнопка не занята`);
  }
});

test("папка — только абсолютный путь", async () => {
  const loaded = loadInject({ href: "https://claude.ai/epitaxy/local_abc", title: "Claude" });
  loaded.dom.command(command({ folder: "относительный/путь" }));
  await drain();
  const mark = loaded.api.status().newWindow;
  assert.equal(mark.state, "bad-command");
  assert.equal(mark.step, "folder", "видно, на чём споткнулись");
});

test("второй клик, пока идёт первый, метится busy", async () => {
  const loaded = loadInject({ href: "https://claude.ai/epitaxy/local_abc", title: "Claude" });
  // Кнопку первый запуск занимает СИНХРОННО, до первого await, — поэтому второй
  // клик проверяем тем же ходом, не давая первому добежать.
  loaded.dom.command(command());
  assert.equal(loaded.api.status().newWindow.busy, true, "первый запуск занял кнопку");
  assert.equal(loaded.api.status().newWindow.runs, 1);
  loaded.dom.command(command({ id: "n2" }));
  assert.equal(loaded.api.status().newWindow.state, "busy", "второй «Привет» в второй чат никому не нужен");
  assert.equal(loaded.api.status().newWindow.runs, 1, "второй запуск не начинался");
  await drain();
  assert.equal(loaded.api.status().newWindow.busy, false, "первый запуск кнопку отпустил");
});

test("команду берёт только главное окно", async () => {
  const popup = loadInject({ href: "about:blank", title: "Второе окно" });
  popup.dom.command(command({ title: "Второе окно" }));
  await drain();
  assert.equal(popup.api.status().newWindow, null, "подчинённое окно даже не помечает запуск");
});

test("адресация окна: поле match сверяется с путём страницы", async () => {
  const loaded = loadInject({ href: "https://claude.ai/epitaxy/local_f44e46bb", title: "Claude", hasFocus: false });
  loaded.dom.command(command({ match: "/epitaxy/local_zzz", x: "нет" }));
  await drain();
  assert.equal(loaded.api.status().newWindow, null, "чужой путь — команда не наша, метки нет");
  loaded.dom.command(command({ match: "/epitaxy/local_f44e46bb", text: "" }));
  await drain();
  assert.equal(loaded.api.status().newWindow.state, "bad-command", "свой путь — команда наша, отбили по контракту");
});

test("попап «В отдельное окно» отвечает плашкой, а не молчанием", async () => {
  const popup = loadInject({ href: "about:blank", title: "Второе окно" });
  popup.dom.command({ id: "p1", action: "popout-window", at: "now", scope: "window", title: "Второе окно", x: 10, y: 20 });
  await drain();
  const mark = popup.api.status().newWindow;
  assert.equal(mark.state, "already", "чат уже в отдельном окне");
  assert.equal(mark.step, "popout");
  assert.ok(popup.document.body.textContent.includes("уже в отдельном окне"), "плашка показана");
});

test("popout проверяет контракт команды раньше, чем показывает плашку", async () => {
  const popup = loadInject({ href: "about:blank", title: "Второе окно" });
  popup.dom.command({ id: "p2", action: "popout-window", at: "now", scope: "window", title: "Второе окно", x: "10", y: "20" });
  await drain();
  assert.equal(popup.api.status().newWindow.state, "bad-command", "строки вместо чисел — это битая команда");
});

// ---- Перенос «Обкэшить» (WF37) ---------------------------------------------
// Цепочка «Нового окна» с полем transfer называет адресата записи, оставленной
// попапом-донором: id только что рождённого чата и заголовок его строки
// сайдбара. Полный прогон цепочки в стабе не воспроизвести (он весь про
// асинхронную вёрстку claude.ai) — проверяем разбор поля и сам штамп.

test("штамп переноса: to, title и stampedAt поверх записи «ждёт адресата»", () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_abc", title: "Claude",
    storage: { local: { [CASHOUT_KEY]: pending() } },
  });
  const before = Date.now();
  assert.equal(loaded.inner.cashoutStamp("local_9f1c2a3b-5d6e-4f70-8a9b-0c1d2e3f4a5b", "VkusnoffKz 3"), true);
  const record = JSON.parse(loaded.win.localStorage.getItem(CASHOUT_KEY));
  const sample = fixture("record-stamped");
  assert.deepEqual(Object.keys(record), Object.keys(sample), "порядок ключей — по эталону");
  assert.equal(record.to, sample.to);
  assert.equal(record.title, sample.title);
  assert.equal(record.text, sample.text, "текст переноса донора не переписывается");
  assert.ok(record.stampedAt >= before, "свежесть переноса считается от штампа");
});

test("штамп трогает только запись «ждёт адресата»", () => {
  const cases = [
    ["обычная запись главного окна", JSON.stringify({ ...fixture("record-main"), at: Date.now() })],
    ["чужой перенос, уже штампованный", JSON.stringify({ ...fixture("record-stamped"), at: Date.now() })],
  ];
  for (const [what, raw] of cases) {
    const loaded = loadInject({
      href: "https://claude.ai/epitaxy/local_abc", title: "Claude", storage: { local: { [CASHOUT_KEY]: raw } },
    });
    assert.equal(loaded.inner.cashoutStamp("local_new", "Новый чат 2"), false, what);
    assert.equal(loaded.win.localStorage.getItem(CASHOUT_KEY), raw, `${what}: запись не тронута`);
  }
  const empty = loadInject({ href: "https://claude.ai/epitaxy/local_abc", title: "Claude" });
  assert.equal(empty.inner.cashoutStamp("local_new", "Новый чат 2"), false, "записи нет вовсе");
  const noId = loadInject({
    href: "https://claude.ai/epitaxy/local_abc", title: "Claude",
    storage: { local: { [CASHOUT_KEY]: pending() } },
  });
  assert.equal(noId.inner.cashoutStamp("", "Новый чат 2"), false, "адресата без id не бывает");
  assert.equal(JSON.parse(noId.win.localStorage.getItem(CASHOUT_KEY)).to, "pending");
});

test("поле transfer разбирается строго", async () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_abc", title: "Claude",
    storage: { local: { [CASHOUT_KEY]: pending() } },
  });
  const mark = async detail => {
    loaded.dom.command(command(detail));
    const snapshot = loaded.api.status().newWindow.transfer;
    await drain();
    return snapshot;
  };
  assert.equal(await mark({ transfer: true }), true, "ветка «Обкэшить»");
  for (const [what, value] of [["поля нет", undefined], ["строка", "true"], ["число", 1], ["ложь", false]]) {
    assert.equal(await mark({ transfer: value }), null, what);
  }
  // Прогон без transfer чужую запись переноса не трогает вовсе: ⌥⌘N, «▸ проект»,
  // «Здесь же» и канал «Пимп» поля не шлют (критик плана, блокер 2).
  assert.equal(JSON.parse(loaded.win.localStorage.getItem(CASHOUT_KEY)).to, "pending");
  assert.equal(loaded.api.status().newWindow.stamped, null, "до штампа цепочка не дошла — стора нет");
});
