// #7727 (слово Элвиса 25.09 23:30): вынесенный «Новым окном» чат остался и в
// главном окне — «почему вообще два чата ты открыл?». Сторож возврата цепочки
// new-window (раздел 12б inject.js): после выноса главное окно, оказавшееся на
// вынесенном чате, Пимп сам возвращает на прежний.
//
// Стенд: главное окно на чате Элвиса (prev) с роутером (dom.router), строка
// прежнего чата в сайдбаре ведёт на него; ⌘N приложения тест делает сам —
// переходом на /epitaxy; отправка заводит сессию local_new; стор попапов
// считает openPopout.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const PREV = "local_prev-1111";
const NEW = "local_new";
const OTHER = "local_other-2222";
const drain = () => new Promise(resolve => setImmediate(resolve));
const settle = async (times = 6) => { for (let index = 0; index < times; index += 1) await drain(); };

// deaf — сколько первых кликов по строке прежнего чата Claude пропускает мимо.
const stand = ({ deaf = 0 } = {}) => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${PREV}`, title: "Claude",
    html: dom => {
      const input = dom.document.body.add("div", { attrs: { "data-testid": "code-prompt-input", contenteditable: "true" } });
      const send = dom.document.body.add("button", { attrs: { "data-testid": "code-prompt-send" } });
      const recents = dom.document.body.add("div", { attrs: { "data-testid": "sidebar-recents" } });
      return { input, send, recents };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const router = loaded.dom.router();
  const { parts } = loaded;
  const rect = { left: 8, top: 100, width: 260, height: 26 };
  const clicks = {};
  const addRow = (id, title) => {
    const row = parts.recents.add("div", { attrs: { "data-row-key": `code:${id}` }, rect });
    const main = row.add("button", { attrs: { "data-row-main-button": "" }, text: title, rect });
    main.addEventListener("click", () => {
      clicks[id] = (clicks[id] ?? 0) + 1;
      if (id === PREV && clicks[id] <= deaf) return;
      router.navigate(`/epitaxy/${id}`);
    });
    return row;
  };
  addRow(PREV, "Чат Элвиса");
  addRow(OTHER, "Третий чат");
  const box = { sent: [], popouts: [] };
  parts.send.addEventListener("click", () => {
    box.sent.push(parts.input.textContent);
    // Сессия рождается заменой записи домашнего экрана, как у Claude.
    loaded.win.history.replaceState(null, "", `/epitaxy/${NEW}`);
    addRow(NEW, "Pimp Viewer макет");
  });
  const value = { popoutWindows: loaded.run("new Map()"), openPopout: options => box.popouts.push(options) };
  const hook = () => {};
  hook.getState = () => value;
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  loaded.inner.setModuleImporter(() => Promise.resolve({ Store: hook }));
  return { loaded, router, box, clicks };
};

// Микрозадачи плюс самый свежий таймер ожиданий; часы идут по 100 мс на круг.
const run = async (loaded, rounds) => {
  let clock = loaded.win.performance.now();
  loaded.win.performance.now = () => clock;
  for (let index = 0; index < rounds; index += 1) {
    clock += 100;
    await settle(4);
    const ids = loaded.dom.ids("timeout");
    if (ids.length) loaded.dom.fire(ids[ids.length - 1]);
  }
  await settle();
};

const start = ({ loaded, router }) => {
  loaded.dom.command({
    id: "n1", action: "new-window", at: "now", scope: "window", title: "Claude",
    x: 100, y: 200, text: "Окно открыто. Жди задачу.", folder: "", name: "",
  });
  // ⌘N приложения: главное окно уходит на домашний экран.
  router.navigate("/epitaxy");
};

test("#7727: после выноса главное окно вернулось на прежний чат", async () => {
  const bench = stand();
  start(bench);
  await run(bench.loaded, 60);
  const mark = plain(bench.loaded.api.status().newWindow);
  assert.equal(bench.box.popouts.length, 1, "чат вынесен");
  assert.equal(bench.box.popouts[0].sessionId, NEW);
  assert.equal(mark.back, "row");
  assert.equal(bench.loaded.win.location.pathname, `/epitaxy/${PREV}`);
});

test("#7727: Claude увёл главное окно на вынесенный чат после возврата — Пимп возвращает сам", async () => {
  const bench = stand();
  start(bench);
  await run(bench.loaded, 60);
  assert.equal(bench.loaded.win.location.pathname, `/epitaxy/${PREV}`);
  // Главное окно само ушло на новый чат — тот, что уже в отдельном окне.
  bench.router.navigate(`/epitaxy/${NEW}`);
  await run(bench.loaded, 20);
  const mark = plain(bench.loaded.api.status().newWindow);
  assert.equal(bench.loaded.win.location.pathname, `/epitaxy/${PREV}`, "чат не остался в двух окнах");
  assert.equal(mark.returned, 1);
  assert.equal(bench.box.popouts.length, 1, "второго выноса нет");
});

test("#7727: возврат цепочки не удался (back-failed) — сторож дожимает", async () => {
  const bench = stand({ deaf: 1 });
  // Историей назад тоже не выйти: Navigation API отказывает.
  bench.loaded.win.navigation.traverseTo = () => {
    const refused = Promise.reject(new Error("InvalidStateError"));
    refused.catch(() => {});
    return { committed: refused, finished: refused };
  };
  start(bench);
  await run(bench.loaded, 80);
  const mark = plain(bench.loaded.api.status().newWindow);
  assert.equal(bench.loaded.win.location.pathname, `/epitaxy/${PREV}`, "главное окно на прежнем чате");
  assert.equal(mark.returned, 1, "вернул сторож, а не цепочка");
  assert.equal(bench.clicks[PREV], 2);
});

test("#7727: строка и история срываются всегда — возвращает роутер страницы", async () => {
  const bench = stand({ deaf: Infinity });
  bench.loaded.win.navigation.traverseTo = () => {
    const refused = Promise.reject(new Error("InvalidStateError"));
    refused.catch(() => {});
    return { committed: refused, finished: refused };
  };
  // Роутер Claude 2.9939.2 (TanStack): navigate({to}) — своя навигация приложения.
  const went = [];
  bench.loaded.win.__TSR_ROUTER__ = { navigate: ({ to }) => { went.push(to); bench.router.navigate(to); return Promise.resolve(); } };
  start(bench);
  await run(bench.loaded, 80);
  const mark = plain(bench.loaded.api.status().newWindow);
  assert.equal(bench.loaded.win.location.pathname, `/epitaxy/${PREV}`, "главное окно на прежнем чате");
  assert.equal(mark.back, "router");
  assert.deepEqual(went, [`/epitaxy/${PREV}`]);
  assert.equal(mark.returned, 0, "сторожу дожимать нечего");
});

test("26.09: заглушка прошлой сорвавшейся цепочки в поле — стираем и идём дальше; чужой черновик — нет", async () => {
  for (const [draft, opened] of [["Окно открыто. Жди задачу.", 1], ["мой черновик", 0]]) {
    const bench = stand();
    bench.loaded.dom.focus?.(bench.loaded.parts.input);
    bench.loaded.parts.input.__text = draft;
    start(bench);
    await run(bench.loaded, 60);
    assert.equal(bench.box.popouts.length, opened, draft);
    if (!opened) assert.equal(bench.loaded.parts.input.__text, draft, "черновик Элвиса цел");
  }
});

test("#7727: окно ушло в третий чат — сторож молчит и назад не тянет", async () => {
  const bench = stand();
  start(bench);
  await run(bench.loaded, 60);
  bench.router.navigate(`/epitaxy/${OTHER}`);
  await run(bench.loaded, 5);
  bench.router.navigate(`/epitaxy/${NEW}`);
  await run(bench.loaded, 20);
  assert.equal(bench.loaded.win.location.pathname, `/epitaxy/${NEW}`, "Элвис сам открыл чат — его выбор");
  assert.equal(plain(bench.loaded.api.status().newWindow).returned, 0);
});

test("#7727: через 12 с после выноса сторож снят", async () => {
  const bench = stand();
  start(bench);
  await run(bench.loaded, 60);
  await run(bench.loaded, 130);
  bench.router.navigate(`/epitaxy/${NEW}`);
  await run(bench.loaded, 20);
  assert.equal(bench.loaded.win.location.pathname, `/epitaxy/${NEW}`);
});
