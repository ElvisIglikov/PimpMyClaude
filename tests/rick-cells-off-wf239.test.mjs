// WF239 (page-60): блок счёта Workflow у поля ввода (раздел 12п² inject.js) снят целиком.
// Слово владельца 10.10 21:10 о блоке «PimpM 1 из 7… В работе / Сделано / Всё / Отчёт»: «зачем это
// всё? Я понял, что это мне не надо… убери всю».
//
// До page-60 этот файл назывался rick-cells-wf134.test.mjs и вместе с rick-strip-wf201 и
// rick-strip-wf204 проверял сам блок. Теперь проверяется обратное и то, что от раздела осталось:
//   1) сирота прошлой страницы (узлы, отступ у прокрутки текста, ключи хранилища) снимается;
//   2) сводку /digest спрашивают только кнопка и панель PMP — и в чате папки Rick тоже: редко,
//      пока окно видно; панель оркестрации жива (её набор — pmp-panel-wf213.test.mjs).
// WF248: проверки «блока нет» (надгробие status().rickCells) сняты; короткие имена проектов —
// в pmp-panel-wf213.test.mjs, «+» у New — в layout.test.mjs.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const LAYER = "#myclaude-rick-cells";
const CARD = "#myclaude-rick-card";
const FLOW = "#myclaude-rick-flow";
const PMP = "#myclaude-pmp";
const PANEL = "#myclaude-pmp-panel";
const CHAT = "local_bbbb-2222";
const DIGEST = "http://127.0.0.1:47615/digest";
const RICK = "/Users/dev/Projects/Rick";

const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const tick = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };
const flows = (count, state = "готово", from = 1) => Array.from({ length: count }, (_, i) => ({ n: i + from, state, about: `работа ${i + from}`, steps: "1/3", phase: "кодинг" }));
// Сводка, на которой блок рисовал две строки-полоски («марафоны») и строку ячейками.
const BUSY = { v: 1, at: "2026-10-10T21:00:00Z", projects: [
  { name: "PimpMyClaude", title: "PimpMyClaude", group: "идут", total: 7, workflows: [...flows(1), ...flows(3, "идёт", 2), ...flows(3, "впереди", 5)] },
  { name: "Dictator", title: "Dictator", group: "идут", total: 2, workflows: [...flows(1), { n: 2, state: "ждёт", about: "макет" }] },
  { name: "Menu", title: "Menu", group: "ждут", workflows: [...flows(2), { n: 3, state: "упал", about: "шрифт" }] },
] };
const ok = data => () => Promise.resolve({ ok: true, json: () => Promise.resolve(data) });

// Окно стенда: поле 100..1100 × 600..720 с нижней строкой и Enter — то самое, где жил блок.
const page = async ({ cwd = RICK, reply = ok(BUSY), text = "", local = {}, before = null } = {}) => {
  const loaded = loadInject({
    title: "Rick", href: `https://claude.ai/epitaxy/${CHAT}`, storage: { local },
    html: dom => {
      const parts = dom.composer({ top: 600, text });
      parts.root.rect = { left: 110, top: 610, width: 980, height: 45 };
      parts.editor.rect = { left: 110, top: 610, width: 980, height: 45 };
      parts.chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: { left: 100, top: 690, width: 1000, height: 28 } });
      const row = parts.chin.add("div", { class: "flex items-center", rect: { left: 100, top: 694, width: 1000, height: 20 } });
      parts.left = row.add("div", { class: "flex items-center self-start", rect: { left: 100, top: 696, width: 60, height: 16 } });
      parts.left.add("button", { attrs: { "aria-label": "Add" }, rect: { left: 100, top: 696, width: 20, height: 16 } });
      const right = row.add("div", { class: "ms-auto flex items-center", rect: { left: 1000, top: 694, width: 100, height: 20 } });
      right.add("button", { attrs: { "data-testid": "epitaxy-cds-model-selector" }, text: "Opus 5.5", rect: { left: 1000, top: 696, width: 60, height: 16 } });
      parts.send = parts.block.add("button", { attrs: { "data-testid": "code-prompt-send" }, rect: { left: 1060, top: 660, width: 24, height: 20 } });
      const side = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
      const item = side.add("div", { attrs: { "data-row-key": `code:${CHAT}` } });
      item.__reactFiber$test = { memoizedProps: { session: { ref: { id: CHAT }, source: { data: { cwd } } } }, return: null };
      before?.(dom, parts);
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.reply = reply;
  loaded.win.fetch = (url, options) => {
    loaded.calls.push([url, options?.mode]);
    return url === DIGEST ? loaded.reply() : Promise.resolve({ ok: true });
  };
  const base = loaded.win.performance.now();
  let shift = 0;
  loaded.win.performance.now = () => base + shift;
  loaded.later = ms => { shift += ms; };
  settle(loaded);
  await tick();
  settle(loaded);
  return loaded;
};
const digests = loaded => loaded.calls.filter(([url]) => url === DIGEST).length;
const pmp = loaded => plain(loaded.api.status().pmp);
const css = loaded => [...loaded.inner.RULES].join("\n");
const gone = (loaded, note) => {
  for (const id of [LAYER, CARD, FLOW]) assert.equal(loaded.dom.query(id), null, `${note}: узел ${id} есть`);
  assert.equal(loaded.dom.queryAll("[data-myclaude-rick-room]").length, 0, `${note}: у прокрутки текста отнято место`);
};

test("WF239: сирота прошлой страницы — узлы блока, отступ у прокрутки текста и запомненные фильтр и вид — снимается при установке", async () => {
  let scroller = null;
  const loaded = await page({
    local: { "myclaude-rick-filter": "done", "myclaude-rick-view": "none", "myclaude-side": "480" },
    before: (dom, parts) => {
      // То, что оставила бы page-59, упади она до своего dispose.
      for (const id of ["myclaude-rick-cells", "myclaude-rick-card", "myclaude-rick-flow"]) dom.document.body.add("div", { attrs: { id }, text: "PimpM 1 из 7" });
      scroller = parts.root;
      scroller.setAttribute("data-myclaude-rick-room", "true");
      scroller.style.setProperty("--myclaude-rick-room", "20px");
    },
  });
  gone(loaded, "после установки");
  assert.equal(scroller.style.getPropertyValue("--myclaude-rick-room"), "", "переменная отступа осталась");
  assert.equal(loaded.win.localStorage.getItem("myclaude-rick-filter"), null);
  assert.equal(loaded.win.localStorage.getItem("myclaude-rick-view"), null);
  assert.equal(loaded.win.localStorage.getItem("myclaude-side"), "480", "чужой ключ хранилища задет");
});

test("WF239: сводку спрашивает только кнопка PMP — и в чате папки Rick: сразу, потом не чаще раза в минуту, скрытое окно — нет; число идущих живо (знака «▶N» у кнопки нет — лист 48 · 1.2, #9507)", async () => {
  const loaded = await page();
  assert.deepEqual(loaded.calls[0], [DIGEST, "cors"]);
  assert.equal(digests(loaded), 1);
  // Идущих Workflow в проектах группы «идут» три — число в status() и подсказке; знака у кнопки нет.
  assert.equal(loaded.dom.query(PMP).textContent, "PMP");
  assert.equal(pmp(loaded).running, 3);
  // Своего опроса раз в 30 с (он был у блока) нет: полминуты — тихо.
  loaded.later(30000);
  loaded.dom.fireKind("interval");
  settle(loaded);
  await tick();
  assert.equal(digests(loaded), 1, "сводку спросили раньше минуты — опрос блока остался");
  loaded.later(30000);
  settle(loaded);
  await tick();
  assert.equal(digests(loaded), 2, "минута прошла — число в подсказке кнопки не обновилось");
  // Возврат окна из скрытого сам запроса не шлёт (это делал блок) — число обновится своим редким запросом.
  loaded.document.hidden = true;
  loaded.later(120000);
  settle(loaded);
  await tick();
  assert.equal(digests(loaded), 2, "скрытое окно спросило сводку");
  loaded.document.hidden = false;
  loaded.document.dispatchEvent({ type: "visibilitychange" });
  await tick();
  assert.equal(digests(loaded), 2, "возврат окна шлёт запрос помимо кнопки");
  settle(loaded);
  await tick();
  assert.equal(digests(loaded), 3);
});

test("WF239: панель оркестрации на кнопке PMP жива в чате папки Rick — открывается, показывает счёт по проектам и команды", async () => {
  const loaded = await page();
  loaded.dom.query(PMP).dispatchEvent({ type: "click", detail: 1 });
  await tick();
  const panel = loaded.dom.query(PANEL);
  assert.equal(panel.style.getPropertyValue("display"), "flex");
  assert.equal(pmp(loaded).open, true);
  assert.equal(pmp(loaded).lastError, null);
  const all = [...panel.querySelectorAll("*")];
  // Блок «Идёт Workflow» одной строкой (лист 48 · 1.2): «Идут 3 · Pimp 1/7 · Dictator 1/2».
  const line = all.find(node => node.dataset.k === "line");
  assert.equal(line.textContent, "Идут 3 · Pimp 1/7 · Dictator 1/2");
  // Короткие имена проектов — общий помощник раздела (rickShortName).
  const text = String(panel.textContent ?? "");
  for (const name of ["Pimp", "Dictator"]) assert.ok(text.includes(name), `в панели нет проекта ${name}`);
  const acts = all.filter(node => node.tagName === "BUTTON" && node.parentNode.tagName === "NAV").map(node => node.textContent);
  assert.ok(acts.includes("Отчёт"), `команды панели: ${acts.join(", ")}`);
  gone(loaded, "панель открыта");
  loaded.api.dispose();
  assert.equal(loaded.dom.query(PANEL), null);
});

test("WF239: dispose — поздний ответ сводки ничего не рисует", async () => {
  let answer = null;
  const loaded = await page({ reply: () => new Promise(resolve => { answer = resolve; }) });
  loaded.api.dispose();
  answer({ ok: true, json: () => Promise.resolve(BUSY) });
  await tick();
  for (const id of [LAYER, CARD, FLOW, PMP, PANEL]) assert.equal(loaded.dom.query(id), null, `после dispose остался ${id}`);
});
