// #5721: возврат главного окна после «Нового окна» ждал смены адреса одну секунду на путь. Строка
// сайдбара, доехавшая позже секунды, ловила следующий путь (историю) уже в пути — и окно уезжало не
// туда. Теперь каждый путь ждёт 2,5 с; запасные пути (история, роутер) на месте.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const PREV = "local_prev-1111";
const NEW = "local_new";
const drain = () => new Promise(resolve => setImmediate(resolve));
const settle = async (times = 6) => { for (let index = 0; index < times; index += 1) await drain(); };

// Главное окно на чате Элвиса; строка прежнего чата открывает его через lagMs (Claude тормозит).
const stand = ({ lagMs = 0 } = {}) => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${PREV}`, title: "Claude",
    html: dom => ({
      input: dom.document.body.add("div", { attrs: { "data-testid": "code-prompt-input", contenteditable: "true" } }),
      send: dom.document.body.add("button", { attrs: { "data-testid": "code-prompt-send" } }),
      recents: dom.document.body.add("div", { attrs: { "data-testid": "sidebar-recents" } }),
    }),
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const router = loaded.dom.router();
  const { parts } = loaded;
  const rect = { left: 8, top: 100, width: 260, height: 26 };
  const bench = { loaded, router, clock: loaded.win.performance.now(), due: null, traversed: 0, popouts: 0 };
  const addRow = (id, title) => {
    const row = parts.recents.add("div", { attrs: { "data-row-key": `code:${id}` }, rect });
    const main = row.add("button", { attrs: { "data-row-main-button": "" }, text: title, rect });
    main.addEventListener("click", () => {
      if (id === PREV && lagMs) bench.due = { at: bench.clock + lagMs, path: `/epitaxy/${id}` };
      else router.navigate(`/epitaxy/${id}`);
    });
  };
  addRow(PREV, "Чат Элвиса");
  parts.send.addEventListener("click", () => {
    loaded.win.history.replaceState(null, "", `/epitaxy/${NEW}`);
    addRow(NEW, "Новый чат");
  });
  const traverse = loaded.win.navigation.traverseTo.bind(loaded.win.navigation);
  loaded.win.navigation.traverseTo = key => { bench.traversed += 1; return traverse(key); };
  const value = { popoutWindows: loaded.run("new Map()"), openPopout: () => { bench.popouts += 1; } };
  const hook = () => {};
  hook.getState = () => value;
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  loaded.inner.setModuleImporter(() => Promise.resolve({ Store: hook }));
  return bench;
};
// Часы по 100 мс на круг; запоздалая навигация строки доезжает в свой срок.
const run = async (bench, rounds) => {
  bench.loaded.win.performance.now = () => bench.clock;
  for (let index = 0; index < rounds; index += 1) {
    bench.clock += 100;
    if (bench.due && bench.clock >= bench.due.at) { bench.router.navigate(bench.due.path); bench.due = null; }
    await settle(4);
    const ids = bench.loaded.dom.ids("timeout");
    if (ids.length) bench.loaded.dom.fire(ids[ids.length - 1]);
  }
  await settle();
};
const start = bench => {
  bench.loaded.dom.command({
    id: "n1", action: "new-window", at: "now", scope: "window", title: "Claude",
    x: 100, y: 200, text: "Окно открыто. Жди задачу.", folder: "", name: "",
  });
  bench.router.navigate("/epitaxy");
};

test("#5721: строка сайдбара довела за 1,5 с — возврат строкой, история не дёргается", async () => {
  const bench = stand({ lagMs: 1500 });
  start(bench);
  await run(bench, 80);
  const mark = plain(bench.loaded.api.status().newWindow);
  assert.equal(bench.popouts, 1, "чат вынесен");
  assert.equal(mark.back, "row");
  assert.equal(bench.traversed, 0, "второй навигации поверх первой нет");
  assert.equal(bench.loaded.win.location.pathname, `/epitaxy/${PREV}`);
});

test("#5721: строка так и не довела — запасной путь историей на месте", async () => {
  const bench = stand({ lagMs: 60000 });
  start(bench);
  await run(bench, 120);
  const mark = plain(bench.loaded.api.status().newWindow);
  assert.equal(mark.back, "history");
  assert.equal(bench.loaded.win.location.pathname, `/epitaxy/${PREV}`);
});
