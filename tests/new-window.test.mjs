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
// «В отдельное окно», порядок ключей по контракту: scope, title, match?, x, y,
// с WF41 — chat?, name?.
const popout = (extra = {}) => ({
  id: "p1", action: "popout-window", at: "now", scope: "window", title: "Claude",
  x: 100, y: 200, ...extra,
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

// ---- Названный чат (WF41) ---------------------------------------------------
// Главное окно выносит в окно ЧУЖОЙ разговор — тот, что сейчас не открыт («Вернуть
// эти чаты» ставит по ячейкам то, чего на экране нет). Стор попапов настоящий по
// форме (Map из реалма страницы + openPopout), но приезжает подставным импортёром:
// боевой import() в vm бросает (приём tests/chat-id.test.mjs).
const withStore = (loaded, { ready = true } = {}) => {
  const box = { ready, calls: [] };
  const value = { popoutWindows: loaded.run("new Map()"), openPopout: options => box.calls.push(options) };
  const store = () => {};
  store.getState = () => value;
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  loaded.inner.setModuleImporter(() => Promise.resolve(box.ready ? { Store: store } : {}));
  return box;
};
// Сайдбар: строка чата открывает его в главном окне — ровно это делает клик.
const sidebar = (dom, rows) => {
  const list = dom.document.body.add("div", { attrs: { "data-testid": "sidebar-recents" } });
  const made = {};
  for (const [id, title] of rows) {
    const row = list.add("div", { attrs: { "data-row-key": `code:${id}` }, text: title });
    row.addEventListener("click", () => { dom.window.location.pathname = `/epitaxy/${id}`; });
    made[id] = row;
  }
  return made;
};

test("названный чат выносится сразу стором, и главное окно на него не уходит", async () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_mine", title: "Claude",
    html: dom => sidebar(dom, [["local_mine", "Чат Элвиса"]]),
  });
  const store = withStore(loaded);
  // Команда адресована заголовком, а chat называет ЧУЖОЙ разговор: адресом это
  // поле у popout-window не бывает, иначе окно решило бы, что команда не его.
  loaded.dom.command(popout({ chat: "local_gone", name: "Утро · Вкуснофф" }));
  await drain();
  assert.equal(loaded.api.status().newWindow.state, "ok");
  assert.equal(store.calls.length, 1, "окно открыли ровно одно");
  assert.equal(store.calls[0].sessionId, "local_gone", "вынесли названный чат, а не свой");
  assert.equal(store.calls[0].title, "Утро · Вкуснофф", "заголовок окна — имя из команды");
  assert.equal(store.calls[0].initialPosition.x, 100);
  assert.equal(store.calls[0].initialPosition.y, 200);
  assert.equal(loaded.win.location.pathname, "/epitaxy/local_mine", "чат Элвиса остался на месте");
});

test("стора нет — чат открывается строкой сайдбара, и главное окно возвращается", async () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_mine", title: "Claude",
    html: dom => sidebar(dom, [["local_mine", "Чат Элвиса"], ["local_gone", "Утро · Вкуснофф"]]),
  });
  const store = withStore(loaded, { ready: false });
  // Чанк со стором догружается вместе с открытым разговором — в этом и смысл
  // запасного пути.
  loaded.parts.local_gone.addEventListener("click", () => { store.ready = true; });
  loaded.dom.command(popout({ chat: "local_gone", name: "Утро · Вкуснофф" }));
  await drain();
  const mark = loaded.api.status().newWindow;
  assert.equal(mark.state, "ok");
  assert.equal(store.calls.length, 1);
  assert.equal(store.calls[0].sessionId, "local_gone");
  assert.equal(mark.back, "row", "возврат — строкой сайдбара");
  assert.equal(loaded.win.location.pathname, "/epitaxy/local_mine", "чат Элвиса вернулся в главное окно");
});

test("чат не нашёлся — окна нет, и нового чата тоже", async () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy", title: "Claude",
    html: dom => sidebar(dom, [["local_mine", "Чат Элвиса"]]),
  });
  const store = withStore(loaded, { ready: false });
  loaded.dom.command(popout({ chat: "local_gone", name: "Утро · Вкуснофф" }));
  await drain();
  assert.equal(loaded.api.status().newWindow.state, "chat-missing",
    "домашний экран без своего чата команду с chat всё равно берёт");
  assert.equal(store.calls.length, 0, "пустая ячейка честнее подмены");
  assert.equal(loaded.win.location.pathname, "/epitaxy", "главное окно не сдвинулось");
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

// ---- Шаг «отправить первое сообщение» (WF43, #5758) -------------------------
// Шаги 3 и 4 цепочки — текст в поле и клик по кнопке отправки — не проверялись
// ничем: кнопка ищется как `[data-testid="code-prompt-send"]:not([disabled])`,
// а стаб DOM :not(...) не понимал и отдавал null. Подмена селектора не роняла
// ни одной проверки при 233 зелёных (находка ревизии 08.09). Стаб научен, шаг
// закрыт здесь.
//
// Домашний экран: поле ввода и кнопка отправки — ровно те два узла, которыми
// цепочка живёт на этих шагах.
const homeScreen = ({ disabled = false } = {}) => dom => {
  const input = dom.document.body.add("div", {
    attrs: { "data-testid": "code-prompt-input", contenteditable: "true" },
  });
  const send = dom.document.body.add("button", { attrs: { "data-testid": "code-prompt-send" } });
  if (disabled) send.setAttribute("disabled", "");
  return { input, send };
};
// Клик по кнопке рождает сессию — ровно это делает Claude на первом сообщении.
const countClicks = loaded => {
  const clicks = { count: 0 };
  loaded.parts.send.addEventListener("click", () => {
    clicks.count += 1;
    loaded.win.location.pathname = "/epitaxy/local_new";
  });
  return clicks;
};
// Цепочка асинхронная: между шагами она отдаёт ход микрозадачам.
const settle = async (times = 4) => { for (let index = 0; index < times; index += 1) await drain(); };
// Один круг ожидания: newWindowWait перепроверяет условие таймером. Толкаем
// САМЫЙ свежий — сторож всей цепочки поставлен раньше, и будить его нельзя.
const poll = async loaded => {
  const ids = loaded.dom.ids("timeout");
  loaded.dom.fire(ids[ids.length - 1]);
  await drain();
};

test("стаб понимает :not(...) — без этого шаг отправки не проверяется вовсе", () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy", title: "Claude",
    html: dom => ({
      bare: dom.document.body.add("input"),
      typed: dom.document.body.add("input", { attrs: { type: "text" } }),
      off: dom.document.body.add("button", { attrs: { "data-testid": "b", disabled: "" } }),
      on: dom.document.body.add("button", { attrs: { "data-testid": "b" } }),
    }),
  });
  assert.equal(loaded.document.querySelector("input:not([type])"), loaded.parts.bare,
    "поле без type находится — на этом стоит поиск имени чата");
  assert.equal(loaded.document.querySelectorAll('[data-testid="b"]:not([disabled])').length, 1,
    "погашенная кнопка отсеивается, живая находится");
  assert.equal(loaded.document.querySelector('[data-testid="b"]:not([disabled])'), loaded.parts.on);
});

test("первое сообщение уходит: текст лёг в поле, кнопка нажата ровно раз", async () => {
  const loaded = loadInject({ href: "https://claude.ai/epitaxy", title: "Claude", html: homeScreen() });
  withStore(loaded);
  const clicks = countClicks(loaded);
  loaded.dom.command(command());
  await settle();
  const mark = loaded.api.status().newWindow;
  assert.equal(loaded.parts.input.textContent, "Привет", "текст запуска лёг в поле");
  assert.equal(clicks.count, 1, "кнопку отправки жмут ровно один раз");
  assert.equal(mark.id, "local_new", "сессия родилась на первом сообщении");
  assert.notEqual(mark.step, "send", "цепочка ушла дальше отправки");
});

test("кнопка ещё погашена — цепочка ждёт её, а не жмёт вслепую", async () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy", title: "Claude", html: homeScreen({ disabled: true }),
  });
  withStore(loaded);
  const clicks = countClicks(loaded);
  loaded.dom.command(command());
  await settle();
  assert.equal(loaded.api.status().newWindow.step, "send", "стоим на отправке");
  assert.equal(clicks.count, 0, "по погашенной кнопке не бьём: папка и модель ещё не выбраны");
  assert.equal(loaded.api.status().newWindow.id, null, "и сессии, значит, нет");
  loaded.parts.send.removeAttribute("disabled");
  await poll(loaded);
  await settle();
  assert.equal(clicks.count, 1, "кнопка ожила — нажали, и только теперь");
  assert.equal(loaded.api.status().newWindow.id, "local_new");
});
