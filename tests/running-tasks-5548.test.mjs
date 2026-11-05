// #5548 (раздел 12х⁴ inject.js): фоновые задачи серым списком под последним сообщением. Слово Элвиса: «Здесь
// Running Task — непонятно, что за задача выполняется… все задания выводились ниже списком сереньким шрифтом
// всегда, в одном и том же месте под сообщением… чтобы понимать, какие работают, какие не работают».
//
// Разметка — по замеру 19.10.2026 (Claude 2.42304, веб-сборка ленты): фоновая задача — блок хода в списке entries
// {kind: "task_event", id, taskId, description, taskType, status, summary, durationMs, startedAt}; Claude правит его
// на месте. Задача за открытой группой инструментов — в ней: items[kind="tools"].taskEvents = [{at, ev}]. Карточка
// «N background commands running» — кнопка [data-transcript-keeps-pin]; её задачи — в React-пропсах (focusTaskId,
// events). Стенд ленты — тот же, что у 12х¹ (tests/work-wf231.test.mjs), урезанный.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const BLOCK = "data-myclaude-tasks";
const ROW = "data-myclaude-tasks-row";
const TEXT = "data-myclaude-tasks-text";
const LINE = "data-myclaude-work-line";
const T0 = Date.UTC(2026, 9, 19, 9, 0, 0);
const SEC = 1000;
const MIN = 60 * SEC;
const CLOUD = "Работа идёт 💭";

const T = (text = "Обычный ответ.") => ({ kind: "text", text });
const R = () => ({ kind: "text", text: CLOUD });
const tools = (label = "Ran 2 commands", extra = {}) => ({ kind: "tools", label, ...extra });
// Задача, как её кладёт Claude: started — status running и startedAt; конец — тот же блок, статус и durationMs.
const task = (taskId, status = "running", extra = {}) => ({
  kind: "task_event", taskId, description: `sleep ${taskId}`, taskType: "local_bash", status, startedAt: T0 - 3 * MIN, ...extra,
});
const user = (id, text = "вопрос") => ({ id, author: "user", text });
const answer = (id, layout, ...items) => ({ id, author: "assistant", layout, items });

// Блоки хода: подряд идущие задачи — одной карточкой (как у Claude).
const blocksOf = entry => {
  const out = [];
  entry.items.forEach((item, index) => {
    const last = out[out.length - 1];
    if (item.kind === "task_event" && last?.group) { last.group.push(item); return; }
    out.push(item.kind === "task_event" ? { index, group: [item] } : { index, item });
  });
  return out;
};

// mount(entry, block) — строка ленты в DOM или нет; fiber: false — списка ходов нет; atBottom — лента у низа;
// cards: false — у карточки задач нет React-пропсов.
// store — список задач Claude в пропсе value узла выше ленты (замер 21.10.2026).
const page = ({ entries, mount = () => true, fiber = true, atBottom = false, cards = true, clock = T0, store = null } = {}) => {
  const clicks = [];
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_tasks-5548", title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({});
      dom.document.body.add("div", { class: "group/approval-dock relative", rect: { left: 0, top: 600, width: 800, height: 180 } });
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: { left: 0, top: 0, width: 800, height: 600 } });
      feed.clientHeight = 600;
      feed.scrollHeight = atBottom ? 600 : 9000;
      const made = new Map();
      let index = 0;
      const block = (host, entry, item) => {
        if (item.group) {
          const wrap = host.add("div", { class: "flex min-w-0 flex-col", attrs: { "data-find-omitted": "" } });
          const button = wrap.add("div", { class: "flex min-w-0 flex-col" }).add("button", { class: "group/tool self-start isolate", attrs: { type: "button", "data-transcript-keeps-pin": "" } });
          const running = item.group.filter(one => one.status === "running").length;
          button.add("span", { text: running ? `${running} background commands running` : `${item.group.length} background commands completed` });
          // Кнопка карточки → zX (focusTaskId — первая задача) → VX (events — все задачи карточки).
          if (cards) button.__reactFiber$test = { memoizedProps: { type: "button" }, return: { memoizedProps: { asCard: true, focusTaskId: item.group[0].taskId }, return: { memoizedProps: { events: item.group }, return: null } } };
          button.addEventListener("click", () => clicks.push(item.group.map(one => one.taskId).join(",")));
          return { node: wrap, button, group: item.group };
        }
        const one = item.item;
        if (one.kind === "text") {
          const node = host.add("div", { class: "min-w-0" });
          node.add("div", { class: "prose", attrs: { "data-cds": "Prose" } }).add("div", { class: "contents" }).add("p", { text: one.text });
          return { node };
        }
        const node = host.add("div", { class: "group/status flex w-full min-w-0 flex-col", attrs: { "data-cds": "TurnStatus", "data-closed": "", "data-state": "done" } });
        node.add("div", { attrs: { "data-cds-row": "" } }).add("button", { attrs: { type: "button", "data-cds-row-toggle": "", "aria-expanded": "false" }, text: one.label });
        return { node };
      };
      entries.forEach((entry, at) => {
        const row = (kind, itemIndex) => {
          const node = feed.add("div", {
            attrs: { "data-testid": "transcript-row", "data-index": String(index), "data-perf-row": kind, "data-perf-row-streaming": "false" },
            rect: { left: 0, top: 20 + index * 40, width: 800, height: 40 },
          });
          index += 1;
          const column = node.add("div", { attrs: { role: "article" } }).add("div", {
            attrs: { "data-epitaxy-entry": entry.id, "data-epitaxy-entry-index": String(at), ...(itemIndex == null ? {} : { "data-epitaxy-item-index": String(itemIndex) }), "data-transcript-column-row": "" },
          });
          return { node, column };
        };
        const message = (made2, actions) => {
          const node = made2.column.add("div", { attrs: { "data-row-gap": "own" } }).add("div", { attrs: { "data-transcript-row": "" } }).add("div", {
            class: "group/message-row relative flex w-full min-w-0 flex-col gap-xs",
            attrs: { "data-cds": "AssistantMessage", "data-testid": "assistant-message", "data-turn-key": entry.id },
          });
          const host = node.add("div", { class: "flex min-w-0 flex-col gap-5" });
          if (actions) node.add("div").add("div", { attrs: { "data-cds": "MessageActions" } });
          return { node, host };
        };
        if (entry.author === "user") {
          const info = { rows: [], columns: [], blocks: [] };
          made.set(entry.id, info);
          if (!mount(entry, null)) { index += 1; return; }
          const made2 = row("human", null);
          made2.column.add("div", { class: "epitaxy-user-turn" }).add("p", { text: entry.text });
          info.rows.push(made2.node);
          info.columns.push(made2.column);
          return;
        }
        const blocks = blocksOf(entry);
        const info = { rows: [], columns: [], hosts: [], blocks: [] };
        made.set(entry.id, info);
        const split = entry.layout === "split";
        (split ? blocks.map(item => [item]) : [blocks]).forEach((list, k, all) => {
          if (!mount(entry, list[0])) { index += 1; return; }
          const made2 = row("assistant", split ? list[0].index : null);
          const box = message(made2, k === all.length - 1);
          info.rows.push(made2.node);
          info.columns.push(made2.column);
          info.hosts.push(box.host);
          for (const item of list) info.blocks.push({ ...block(box.host, entry, item), index: item.index, row: made2.node });
        });
      });
      if (fiber) {
        feed.__reactFiber$test = { memoizedProps: {}, return: { memoizedProps: {
          entries: entries.map(entry => ({
            id: entry.id, author: entry.author,
            // Блоки — те же объекты, что у теста: Claude правит задачу на месте, тест — тоже.
            items: entry.author === "user" ? [{ id: entry.id, kind: "text", text: entry.text }]
              : entry.items.map((item, k) => Object.assign(item, { id: item.id ?? `${entry.id}-i${k}` })),
          })),
          isResponding: false, olderHistoryAbove: false,
        }, return: { memoizedProps: {}, return: store ? { memoizedProps: { value: store }, return: null } : null } } };
      }
      return { ...parts, feed, made };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  // Часы Unix страницы (отметки задач — в них); now() раздела 1 — свои, от загрузки страницы.
  loaded.win.__clock = clock;
  loaded.run("Date.now = () => globalThis.__clock");
  const before = loaded.parts.feed.innerText;
  const of = id => loaded.parts.made.get(id);
  const blocks = () => loaded.dom.queryAll(`[${BLOCK}]`);
  const rows = () => (blocks()[0] ? [...blocks()[0].children] : []);
  const say = () => rows().map(row => row.getAttribute(TEXT));
  const sync = () => { loaded.inner.readTick(); loaded.inner.tasksTick(true); };
  const tick = () => loaded.inner.tasksTick(false);
  const at = ms => { loaded.win.__clock = ms; };
  const status = () => plain(loaded.api.status().runningTasks);
  const card = (id, k = 0) => of(id).blocks.filter(item => item.button)[k] ?? null;
  const click = node => loaded.dom.document.dispatchEvent({ type: "click", target: node, detail: 1, isTrusted: true });
  const key = (name, node, extra = {}) => ({ defaultPrevented: !loaded.dom.document.dispatchEvent({ type: "keydown", key: name, target: node, isTrusted: true, cancelable: true, ...extra }) });
  sync();
  return { loaded, parts: loaded.parts, before, of, blocks, rows, say, sync, tick, at, status, card, click, key, clicks };
};

const RUN = () => [user("u1"), answer("msg_A", "whole", T("Запускаю sleep в фоне."), task("300"))];

// ---- чистые функции -------------------------------------------------------------------
const { inner } = loadInject({ title: "Rick" });

test("12х⁴: имя — до 60 знаков по целому слову, без многоточия; время — «с», «мин», «ч»", () => {
  assert.equal(inner.tasksName("sleep 300"), "sleep 300");
  assert.equal(inner.tasksName("  npm   run   build  "), "npm run build");
  const long = "Собрать приложение, прогнать все тесты страницы и сверить склейку inject.js с разделами";
  const cut = inner.tasksName(long);
  assert.equal(cut, "Собрать приложение, прогнать все тесты страницы и сверить");
  assert.ok(cut.length <= 60 && !cut.includes("…") && !cut.endsWith(" "));
  assert.ok(long.startsWith(cut));
  // Одно длинное слово — режется по 60 знакам.
  assert.equal(inner.tasksName("x".repeat(90)), "x".repeat(60));
  assert.equal(inner.tasksAge(0), "0 с");
  assert.equal(inner.tasksAge(12 * SEC), "12 с");
  assert.equal(inner.tasksAge(59 * SEC + 999), "59 с");
  assert.equal(inner.tasksAge(3 * MIN + 20 * SEC), "3 мин");
  assert.equal(inner.tasksAge(65 * MIN), "1 ч 5 мин");
  assert.equal(inner.tasksAge(120 * MIN), "2 ч");
  assert.equal(inner.tasksAge(-5 * SEC), "0 с", "часы разошлись — не «минус»");
});

test("12х⁴: задача из блока хода — поля Claude и их snake_case; Workflow и не задача — мимо; незнакомый статус — null", () => {
  const info = plain(inner.tasksInfoOf({ kind: "task_event", id: "m1", taskId: "b1", description: "sleep 300", taskType: "local_bash", status: "running", startedAt: T0 }));
  assert.deepEqual(info, { key: "b1", item: "m1", status: "run", raw: "running", name: "sleep 300", named: true, start: T0, end: null, duration: null });
  const snake = plain(inner.tasksInfoOf({ kind: "task_event", task_id: "b2", status: "completed", started_at: new Date(T0).toISOString(), duration_ms: 61000, task_type: "local_agent" }));
  assert.deepEqual([snake.key, snake.status, snake.name, snake.named, snake.start, snake.duration], ["b2", "done", "агент", false, T0, 61000]);
  // Имени нет — первая строка summary; нет и её — вид задачи.
  assert.equal(inner.tasksInfoOf({ kind: "task_event", taskId: "b3", status: "failed", summary: "\nnpm test упал\nподробности" }).name, "npm test упал");
  assert.equal(inner.tasksInfoOf({ kind: "task_event", taskId: "b4", status: "stopped", taskType: "local_workflow" }).name, "Workflow");
  assert.equal(inner.tasksInfoOf({ kind: "task_event", taskId: "b5", status: "stopped" }).name, "фоновая задача");
  assert.deepEqual(["failed", "stopped", "killed", "in_progress", "success"].map(status => inner.tasksInfoOf({ kind: "task_event", taskId: "x", status }).status), ["fail", "stop", "stop", "run", "done"]);
  assert.equal(inner.tasksInfoOf({ kind: "task_event", taskId: "x", status: "weird" }).status, null);
  assert.equal(inner.tasksInfoOf({ kind: "task_event", taskId: "x", status: "running", suppressedByWorkflow: true }), null, "задачи Workflow Claude прячет сам");
  assert.equal(inner.tasksInfoOf({ kind: "tools" }), null);
  assert.equal(inner.tasksInfoOf(null), null);
});

// ---- блок -----------------------------------------------------------------------------------
test("12х⁴: идёт фоновая команда — серая строка «● имя · 3 мин» последним ребёнком колонки последней строки; текста в узлах нет", () => {
  const made = page({ entries: RUN() });
  assert.equal(made.blocks().length, 1);
  const block = made.blocks()[0];
  const column = made.of("msg_A").columns[0];
  assert.equal(block.parentNode, column, "блок — в колонке строки, вне сообщения Claude");
  assert.equal(column.lastElementChild, block);
  assert.deepEqual(made.say(), ["● sleep 300 · 3 мин"]);
  const row = made.rows()[0];
  assert.equal(row.getAttribute(ROW), "run");
  assert.equal(row.getAttribute("role"), "button");
  assert.equal(row.getAttribute("tabindex"), "0");
  assert.equal(row.getAttribute("aria-label"), "Идёт: sleep 300, 3 мин");
  assert.match(row.getAttribute("title"), /^sleep 300\n/);
  assert.equal(block.textContent, "", "подпись — в атрибуте: копия и разбор ленты её не видят");
  assert.equal(made.parts.feed.innerText, made.before, "innerText ленты тот же");
  assert.deepEqual(made.status(), { shown: true, running: 1, done: 0, failed: 0, error: null, stale: 0 });
  // Вид: 12 px, тихий цвет темы, подпись через ::after.
  const rules = [...made.loaded.inner.RULES];
  const own = String(made.loaded.dom.queryAll("style").map(node => node.textContent).join("\n"));
  assert.match(own, new RegExp(`\\[${BLOCK}\\]\\{[^}]*font-size:12px[^}]*color:var\\(--cds-text-muted,currentColor\\)`));
  assert.ok(own.includes(`[${ROW}]::after{content:attr(${TEXT})}`));
  assert.ok(!rules.some(rule => rule.includes(BLOCK)), "правила блока — в lateRules, не в RULES раздела 4");
});

test("12х⁴: время растёт от сердцебиения — меняется только подпись, узлы те же, своих таймеров нет", () => {
  const made = page({ entries: RUN() });
  const block = made.blocks()[0];
  const row = made.rows()[0];
  const timers = ["interval", "timeout", "raf"].map(kind => made.loaded.dom.count(kind));
  made.at(T0 + MIN);
  made.tick();
  assert.deepEqual(made.say(), ["● sleep 300 · 4 мин"]);
  assert.equal(made.blocks()[0], block);
  assert.equal(made.rows()[0], row, "узел строки тот же");
  assert.equal(block.children.length, 1);
  assert.deepEqual(["interval", "timeout", "raf"].map(kind => made.loaded.dom.count(kind)), timers, "тик блока таймеров не заводит");
  // Через сердцебиение страницы — тоже.
  made.at(T0 + 2 * MIN);
  made.loaded.inner.heartbeatTick();
  assert.deepEqual(made.say(), ["● sleep 300 · 5 мин"]);
});

test("12х⁴: часы страницы now() — от загрузки, отметки задач — Unix: время считается по Unix", () => {
  const made = page({ entries: RUN() });
  made.loaded.win.performance.now = () => 1500;
  made.sync();
  assert.deepEqual(made.say(), ["● sleep 300 · 3 мин"]);
  made.at(T0 + 90 * SEC);
  made.tick();
  assert.deepEqual(made.say(), ["● sleep 300 · 4 мин"]);
});

test("12х⁴: закончилась — «✓ … · 1 мин»; упала — «✕ … · не вышло»; остановлена — «✕ … · остановлена»; через 2 мин блока нет", () => {
  const entries = RUN();
  const item = entries[1].items[1];
  const made = page({ entries });
  const row = made.rows()[0];
  // Claude правит тот же блок: статус и сколько шла.
  Object.assign(item, { status: "completed", durationMs: 61 * SEC });
  made.at(T0 - 2 * MIN + 2 * SEC);
  made.sync();
  assert.deepEqual(made.say(), ["✓ sleep 300 · 1 мин"]);
  assert.equal(made.rows()[0], row, "строка та же");
  assert.equal(row.getAttribute(ROW), "done");
  assert.equal(row.getAttribute("aria-label"), "Готово: sleep 300, 1 мин");
  assert.deepEqual(made.status(), { shown: true, running: 0, done: 1, failed: 0, error: null, stale: 0 });
  // Конец — startedAt + durationMs = T0 − 1 мин 59 с: через 2 мин после него блок уходит сам, без сверки списка.
  made.at(T0 + 2 * SEC);
  made.tick();
  assert.equal(made.blocks().length, 0);
  assert.deepEqual(made.status(), { shown: false, running: 0, done: 0, failed: 0, error: null, stale: 0 });

  const fail = RUN();
  const failed = page({ entries: fail });
  Object.assign(fail[1].items[1], { status: "failed" });
  failed.sync();
  assert.deepEqual(failed.say(), ["✕ sleep 300 · не вышло"]);
  assert.equal(failed.rows()[0].getAttribute(ROW), "fail");
  assert.equal(failed.rows()[0].getAttribute("aria-label"), "Не вышло: sleep 300");
  assert.deepEqual(failed.status(), { shown: true, running: 0, done: 0, failed: 1, error: null, stale: 0 });
  // Конца в задаче нет — он по первому взгляду страницы: ещё 2 мин на виду, потом нет.
  failed.at(T0 + 119 * SEC);
  failed.tick();
  assert.equal(failed.blocks().length, 1);
  failed.at(T0 + 121 * SEC);
  failed.tick();
  assert.equal(failed.blocks().length, 0);

  const stop = RUN();
  const stopped = page({ entries: stop });
  Object.assign(stop[1].items[1], { status: "stopped" });
  stopped.sync();
  assert.deepEqual(stopped.say(), ["✕ sleep 300 · остановлена"]);
  assert.equal(stopped.rows()[0].getAttribute(ROW), "fail");
  assert.equal(stopped.rows()[0].getAttribute("aria-label"), "Остановлена: sleep 300");
  assert.equal(stopped.status().failed, 1, "остановленные — в счёте «не вышло»");
});

test("12х⁴: идущие — все, давние сверху; готовых — три последних; упавшие — между ними по времени конца", () => {
  const entries = [user("u1"), answer("msg_A", "whole", T("Пачка задач."),
    task("a", "completed", { startedAt: T0 - 5 * MIN, durationMs: 4 * MIN }),
    task("b", "completed", { startedAt: T0 - 5 * MIN, durationMs: 4 * MIN + 10 * SEC }),
    task("c", "failed", { startedAt: T0 - 5 * MIN, durationMs: 4 * MIN + 20 * SEC }),
    task("d", "completed", { startedAt: T0 - 5 * MIN, durationMs: 4 * MIN + 30 * SEC }),
    task("e", "completed", { startedAt: T0 - 2 * MIN, durationMs: 90 * SEC }),
    task("f", "running", { startedAt: T0 - 30 * SEC }),
    task("g", "running", { startedAt: T0 - 10 * MIN }))];
  const made = page({ entries });
  assert.deepEqual(made.say(), [
    "● sleep g · 10 мин", "● sleep f · 30 с",
    "✓ sleep b · 4 мин", "✕ sleep c · не вышло", "✓ sleep d · 4 мин", "✓ sleep e · 1 мин",
  ]);
  assert.deepEqual(made.status(), { shown: true, running: 2, done: 3, failed: 1, error: null, stale: 0 });
});

test("12х⁴: блоки одной задачи — одна строка; задача внутри группы инструментов тоже видна", () => {
  // Начало — в первом ходе (running), конец — новым блоком во втором (Claude так кладёт конец задачи из прошлого хода).
  const entries = [
    user("u1"), answer("msg_A", "whole", T("Запускаю."), task("300", "running", { startedAt: T0 - 3 * MIN })),
    user("u2"), answer("msg_B", "whole", T("Жду."), task("300", "completed", { description: undefined, startedAt: undefined, durationMs: 150 * SEC }),
      tools("Ran a command", { taskEvents: [{ at: 1, ev: task("srv", "running", { description: "npm run dev", startedAt: T0 - MIN }) }] })),
  ];
  const made = page({ entries });
  assert.deepEqual(made.say(), ["● npm run dev · 1 мин", "✓ sleep 300 · 2 мин"], "имя — первое настоящее, начало — раннее, статус — последний");
  assert.equal(made.blocks()[0].parentNode, made.of("msg_B").columns[0], "блок — под последним сообщением");
});

test("12х⁴: перезагрузка — давно законченная задача без отметок не всплывает; новая в последнем ходе — видна", () => {
  const entries = [user("u1"), answer("msg_A", "whole", T("Готово."), task("old", "completed", { startedAt: undefined }))];
  const made = page({ entries });
  assert.equal(made.blocks().length, 0);
  assert.deepEqual(made.status(), { shown: false, running: 0, done: 0, failed: 0, error: null, stale: 0 });
  // Пришла новая законченная задача (конец прошлой, начатой до открытия окна) — 2 мин на виду.
  const host = made.parts.feed.__reactFiber$test.return.memoizedProps;
  host.entries[1].items.push({ id: "msg_A-new", kind: "task_event", taskId: "fresh", status: "failed", description: "npm test" });
  made.sync();
  assert.deepEqual(made.say(), ["✕ npm test · не вышло"]);
});

test("12х⁴: смена чата — список другого чата (тот же адрес ещё не сменился) — его законченные задачи не новость", () => {
  const made = page({ entries: RUN() });
  assert.deepEqual(made.say(), ["● sleep 300 · 3 мин"]);
  // React уже отдал ленту другого чата: первый ход другой, в последнем ходе — давно законченная задача без отметок.
  const host = made.parts.feed.__reactFiber$test.return.memoizedProps;
  host.entries = [{ id: "u9", author: "user", items: [{ id: "u9", kind: "text", text: "другой чат" }] },
    { id: "msg_Z", author: "assistant", items: [{ id: "z1", kind: "text", text: "Готово." }, { id: "z2", kind: "task_event", taskId: "old", status: "completed", description: "npm run build" }] }];
  made.sync();
  assert.equal(made.blocks().length, 0);
  assert.deepEqual(made.status(), { shown: false, running: 0, done: 0, failed: 0, error: null, stale: 0 }, "чужая законченная задача не всплыла");
  // А новая законченная в том же списке — новость (строк этого чата в стенде нет — счёт без блока).
  host.entries[1].items.push({ id: "z3", kind: "task_event", taskId: "fresh", status: "failed", description: "npm test" });
  made.sync();
  assert.deepEqual(made.status(), { shown: false, running: 0, done: 0, failed: 1, error: null, stale: 0 });
});

test("12х⁴: «идёт» дольше 12 ч — сирота прошлого сеанса: не показана, счёт в stale; задача без ключа — только в последнем ходе", () => {
  const entries = [
    user("u1"), answer("msg_A", "whole", T("Давно."), { kind: "task_event", status: "running", description: "без ключа" }),
    user("u2"), answer("msg_B", "whole", T("Сейчас."), task("zombie", "running", { startedAt: T0 - 13 * 60 * MIN })),
  ];
  const made = page({ entries });
  assert.equal(made.blocks().length, 0);
  assert.deepEqual(made.status(), { shown: false, running: 0, done: 0, failed: 0, error: null, stale: 1 });
  // Тот же блок без ключа в последнем ходе — виден.
  const tail = [user("u1"), answer("msg_A", "whole", T("Сейчас."), { kind: "task_event", status: "running", description: "без ключа" })];
  const shown = page({ entries: tail });
  assert.deepEqual(shown.say(), ["● без ключа · 0 с"]);
});

test("12х⁴: не узнал разметку — блока нет, причина в error; незнакомый статус — задача пропущена", () => {
  // Списка ходов нет, а карточка «running» есть.
  const blind = page({ entries: RUN(), fiber: false });
  assert.equal(blind.blocks().length, 0);
  assert.equal(blind.status().error, "лента не отдала список ходов, а карточка «running» есть");
  assert.equal(blind.status().shown, false);
  // Список есть, задач в нём нет (Claude переименовал вид блока), а карточка «running» есть.
  const renamed = [user("u1"), answer("msg_A", "whole", T("Запускаю."), task("300"))];
  const other = page({ entries: renamed, fiber: false });
  other.parts.feed.__reactFiber$test = { memoizedProps: {}, return: { memoizedProps: {
    entries: [{ id: "u1", author: "user", items: [] }, { id: "msg_A", author: "assistant", items: [{ id: "x1", kind: "text", text: "Запускаю." }, { id: "x2", kind: "background_task", taskId: "300", status: "running" }] }],
    isResponding: false, olderHistoryAbove: false,
  }, return: null } };
  other.sync();
  assert.equal(other.blocks().length, 0);
  assert.equal(other.status().error, "в списке ходов нет фоновых задач, а карточка «running» есть");
  // Задач нет и карточки нет — не ошибка.
  const calm = page({ entries: [user("u1"), answer("msg_A", "whole", T("Просто ответ."))] });
  assert.deepEqual(calm.status(), { shown: false, running: 0, done: 0, failed: 0, error: null, stale: 0 });
  // Незнакомый статус: задача пропущена, остальные на месте.
  const odd = page({ entries: [user("u1"), answer("msg_A", "whole", T("Две."), task("a"), task("b", "paused"))] });
  assert.deepEqual(odd.say(), ["● sleep a · 3 мин"]);
  assert.equal(odd.status().error, "статус фоновой задачи не узнан: paused");
});

test("12х⁴: низа ленты нет в DOM (читают выше) — блока нет и это не ошибка; строка без колонки — error", () => {
  const away = page({ entries: [...RUN(), user("u2"), answer("msg_B", "whole", T("Ответ ниже экрана."))], mount: entry => entry.id !== "msg_B" });
  assert.equal(away.blocks().length, 0);
  assert.deepEqual(away.status(), { shown: false, running: 1, done: 0, failed: 0, error: null, stale: 0 });
  const bare = page({ entries: RUN() });
  assert.equal(bare.blocks().length, 1);
  bare.of("msg_A").columns[0].removeAttribute("data-transcript-column-row");
  bare.sync();
  assert.equal(bare.blocks().length, 0, "строка без колонки — блок снят, узлы Claude не тронуты");
  assert.equal(bare.status().error, "у строки ленты нет колонки [data-transcript-column-row]: блок не поставлен");
  assert.equal(bare.status().shown, false);
});

test("12х⁴: серия «Работа идёт» в хвосте — блок под её строкой, разметка 12х¹ прежняя", () => {
  const entries = [user("u1"), answer("msg_A", "whole", T("Раздаю дела."), R(), task("300"), R())];
  const made = page({ entries });
  const lines = made.loaded.dom.queryAll(`[${LINE}]`);
  assert.equal(lines.length, 1);
  const block = made.blocks()[0];
  assert.equal(block.parentNode, made.of("msg_A").columns[0]);
  assert.ok(block.previousElementSibling.contains(lines[0]), "строка серии — выше, в сообщении");
  assert.deepEqual(plain(made.loaded.api.status().work), { series: 1, folded: 1, live: true, failed: 0, lastError: null, progress: null });
  assert.deepEqual(made.say(), ["● sleep 300 · 3 мин"]);
  // Ход строкой на блок: блок — в последней строке ленты.
  const split = page({ entries: [user("u1"), answer("msg_A", "split", T("Раздаю дела."), task("300"), T("Жду."))] });
  const rows = split.of("msg_A").rows;
  assert.equal(split.blocks()[0].parentNode, split.of("msg_A").columns[rows.length - 1]);
});

test("12х⁴: лента у низа — остаётся у низа; читают выше — прокрутка не трогается", () => {
  const bottom = page({ entries: RUN(), atBottom: true });
  assert.equal(bottom.blocks().length, 1);
  assert.equal(bottom.parts.feed.scrollTop, bottom.parts.feed.scrollHeight);
  const above = page({ entries: RUN() });
  assert.equal(above.blocks().length, 1);
  assert.equal(above.parts.feed.scrollTop, 0);
  // Снятие блока у низа — тоже у низа.
  const entries = RUN();
  const gone = page({ entries, atBottom: true });
  gone.parts.feed.scrollTop = 0;
  Object.assign(entries[1].items[1], { status: "completed", durationMs: MIN });
  gone.at(T0 + 10 * MIN);
  gone.sync();
  assert.equal(gone.blocks().length, 0);
  assert.equal(gone.parts.feed.scrollTop, gone.parts.feed.scrollHeight);
});

test("12х⁴: лента пересоздала строку — блок встаёт заново на следующем тике; на месте — не переставляется", () => {
  const made = page({ entries: RUN() });
  const block = made.blocks()[0];
  const column = made.of("msg_A").columns[0];
  // На месте: тик ничего не двигает (своя вставка не будит обходы зря).
  const tail = column.add("div", { class: "claude-extra" });
  made.tick();
  assert.equal(column.lastElementChild, tail, "без сверки блок не бегает за чужими узлами");
  made.sync();
  assert.equal(column.lastElementChild, block, "на сверке — снова последний");
  // Строку убрали из DOM вместе с блоком и вернули новой — блок в ней.
  made.of("msg_A").rows[0].remove();
  made.tick();
  assert.equal(made.status().shown, false);
});

test("12х⁴: нажатие и Enter — нажатие на родную карточку задачи (её задачи — в React-пропсах); карточки нет в DOM — лента едет к ходу и жмёт, когда она придёт", () => {
  const entries = [user("u1"), answer("msg_A", "whole", T("Две задачи."), task("a"), task("b", "running", { startedAt: T0 - MIN }))];
  const made = page({ entries });
  assert.deepEqual(made.say(), ["● sleep a · 3 мин", "● sleep b · 1 мин"]);
  const [first, second] = made.rows();
  made.click(second);
  assert.deepEqual(made.clicks, ["a,b"], "карточка «2 running» нажата: b — во второй задаче её events");
  assert.equal(made.key("Enter", first).defaultPrevented, true);
  assert.deepEqual(made.clicks, ["a,b", "a,b"]);
  assert.equal(made.key("Enter", first, { repeat: true }).defaultPrevented, true);
  made.key("a", first);
  made.click(made.blocks()[0]);
  assert.equal(made.clicks.length, 2, "удержание, чужая клавиша и нажатие мимо строки — мимо");
  assert.equal(made.loaded.inner.tasksState.clicks, 2);
  // Карточки нет в DOM (строка хода ушла из ленты): лента едет к ходу, нажатие ждёт карточку.
  const row = made.of("msg_A").rows[0];
  const feed = made.parts.feed;
  row.remove();
  feed.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "9", "data-perf-row": "human" } })
    .add("div", { attrs: { role: "article" } }).add("div", { attrs: { "data-epitaxy-entry": "u1", "data-transcript-column-row": "" } });
  made.click(first);
  assert.equal(made.loaded.inner.readState.seek?.key, "msg_A", "лента едет к ходу задачи");
  assert.equal(made.loaded.inner.tasksState.pending?.key, "a");
  assert.equal(made.clicks.length, 2);
  feed.appendChild(row);
  made.tick();
  assert.deepEqual(made.clicks, ["a,b", "a,b", "a,b"], "карточка пришла — нажата");
  assert.equal(made.loaded.inner.tasksState.pending, null);
  // Переход довёл ход до места и кончился между тиками — карточка в DOM: последняя попытка жмёт.
  row.remove();
  made.click(first);
  const read = made.loaded.inner.readState;
  read.seek.settle = 2;
  read.seek = null;
  feed.appendChild(row);
  made.tick();
  assert.equal(made.clicks.length, 4, "переход дошёл — нажато");
  assert.equal(made.loaded.inner.tasksState.pending, null);
  // Человек взялся за ленту сам (нажал мышью — переход снят): карточка, пришедшая потом, не жмётся.
  row.remove();
  made.click(first);
  assert.equal(made.loaded.inner.tasksState.pending?.key, "a");
  made.loaded.dom.document.dispatchEvent({ type: "mousedown", target: feed, detail: 1, isTrusted: true });
  assert.equal(made.loaded.inner.readState.seek, null);
  feed.appendChild(row);
  made.tick();
  assert.equal(made.clicks.length, 4, "переход снят — нажатия нет");
  assert.equal(made.loaded.inner.tasksState.pending, null);
});

test("12х⁴: карточку не узнали (нет React-пропсов) — нажатие только ведёт ленту к ходу, чужое не жмёт", () => {
  const made = page({ entries: RUN(), cards: false });
  made.click(made.rows()[0]);
  assert.deepEqual(made.clicks, []);
  assert.equal(made.loaded.inner.readState.seek?.key, "msg_A");
});

test("12х⁴: сердцебиение ставит блок само; dispose убирает блок, повторный инжект — без сирот", () => {
  const made = page({ entries: RUN() });
  made.loaded.inner.tasksTick(true);
  assert.equal(made.blocks().length, 1);
  made.loaded.api.dispose();
  assert.equal(made.blocks().length, 0);
  // Сирота прошлой установки (dispose не дошёл) — убирается при загрузке.
  const again = page({ entries: RUN() });
  const orphan = again.of("msg_A").columns[0].add("div", { attrs: { [BLOCK]: "" } });
  const next = again.loaded.reload();
  assert.equal(next.error, null);
  assert.equal(orphan.isConnected, false);
  again.loaded.inner.readTick();
  again.loaded.inner.heartbeatTick();
  assert.equal(again.blocks().length, 1, "новая установка ставит свой блок от сердцебиения");
});

test("12х⁴: блока хода нет, а в списке задач Claude задача есть — строка по списку; чужой вызов и вложенная — мимо", () => {
  // Замер 21.10.2026: «sleep 120» в фоне, ход кончился раньше команды — task_event в ходе не появился вовсе.
  const store = [
    { taskId: "bk1", toolUseId: "toolu_1", description: "Run sleep 120", taskType: "local_bash", status: "running", startedAt: T0 - MIN },
    { taskId: "bk2", toolUseId: "toolu_other", description: "чужой чат", taskType: "local_bash", status: "running", startedAt: T0 - MIN },
    { taskId: "bk3", toolUseId: "toolu_1", parentTaskId: "a1", description: "вложенная", taskType: "local_bash", status: "running", startedAt: T0 - MIN },
    { taskId: "wf1", toolUseId: "toolu_1", description: "задача Workflow", taskType: "local_workflow", status: "running", startedAt: T0 - MIN },
  ];
  // Задачу wf1 Claude в ходе прячет как задачу Workflow — из списка её тоже не берём.
  const entries = [user("u1"), answer("msg_A", "whole", tools("Ran 1 command", { tools: [{ id: "toolu_1", name: "Bash" }] }), T("Запустил."),
    task("wf1", "running", { suppressedByWorkflow: true }))];
  const made = page({ entries, store });
  assert.deepEqual(made.say(), ["● Run sleep 120 · 1 мин"]);
  Object.assign(store[0], { status: "completed", completedAt: T0 + MIN });
  made.at(T0 + MIN);
  made.sync();
  assert.deepEqual(made.say(), ["✓ Run sleep 120 · 2 мин"]);
  made.at(T0 + 4 * MIN);
  made.sync();
  assert.deepEqual(made.say(), [], "законченная — 2 мин, потом пропадает");
});
