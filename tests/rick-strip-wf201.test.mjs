// WF201 (#9095, слово Элвиса: «сайт: 1 марафон, 10 Workflow, 1 готов, 9 идут… мне нужно наглядно это видеть»;
// макет docs/35.html, вар. 35.1 «Полоска»): в строке проекта поля Рика — полоска марафона, клетка на Workflow
// (залито — готово, дышит — идёт), соседние одного состояния сливаются, когда клетки узкие; за полоской —
// ячейки упавших «26 ✕» и ждущих «4 !»; справа у ↵ — «1 из 10»; наведение — ячейка клетки над ней; клик по
// клетке — карточка Workflow; клик по счёту — строка по одному (как «1–N ✓»). Нет `total` в /digest —
// строка ячейками, как раньше. Фильтр отбирает проекты.
// Потолок команды status на странице — 128 КБ (класс #9159). Карточка Workflow не закрывает строку своей
// капсулы (№13).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const LAYER = "#myclaude-rick-cells";
const CHAT = "local_bbbb-2222";
const DIGEST = "http://127.0.0.1:47615/digest";
// Рамка поля 100..1100 × 600..720, Enter 1060..1084 × 660..680 (как rick-cells-wf134).
const FRAME = { left: 100, top: 600 };
const SEND = { left: 1060, top: 660, width: 24, height: 20 };
const CHIN = { left: 100, top: 690, width: 1000, height: 28 };

const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const tick = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };
const digest = (...projects) => ({ v: 1, at: "2026-10-09T05:00:00Z", projects });
const ok = data => () => Promise.resolve({ ok: true, json: () => Promise.resolve(data) });
// Марафон: states — строка знаков (d готово, r идёт, w ждёт, f упал, p впереди), total — их число.
const KIND = { d: "готово", r: "идёт", w: "ждёт", f: "упал", p: "впереди" };
const M = (name, states, extra = {}) => {
  const workflows = [...states].map((mark, i) => ({ n: i + 1, state: KIND[mark], about: `работа ${i + 1}`, steps: "1/3", phase: mark === "r" ? "кодинг" : "" }));
  return { name, title: name, group: "идут", done: workflows.filter(flow => flow.state === "готово").length, total: workflows.length, workflows, ...extra };
};

const page = async ({ reply, filter = "all", shell = null } = {}) => {
  const loaded = loadInject({
    title: "Rick", href: `https://claude.ai/epitaxy/${CHAT}`, storage: { local: { "myclaude-rick-filter": filter } },
    html: dom => {
      const parts = dom.composer({ top: 600 });
      parts.root.rect = { left: 110, top: 610, width: 980, height: 45 };
      parts.editor.rect = { left: 110, top: 610, width: 980, height: 45 };
      parts.chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: CHIN });
      parts.send = parts.block.add("button", { attrs: { "data-testid": "code-prompt-send" }, rect: SEND });
      const side = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
      const item = side.add("div", { attrs: { "data-row-key": `code:${CHAT}` } });
      item.__reactFiber$test = { memoizedProps: { session: { ref: { id: CHAT }, source: { data: { cwd: "/Users/dev/Projects/Rick" } } } }, return: null };
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.win.fetch = url => (url === DIGEST ? reply() : Promise.resolve({ ok: true }));
  if (shell) loaded.parts.shell.rect = shell;
  settle(loaded);
  await tick();
  settle(loaded);
  return loaded;
};
const kids = (node, tag) => [...node.childNodes].filter(kid => kid.nodeType === 1 && (!tag || kid.tagName.toLowerCase() === tag));
const layer = loaded => loaded.dom.query(LAYER);
const list = loaded => kids(layer(loaded), "p")[0];
const rows = loaded => kids(list(loaded), "s");
const row = (loaded, key) => rows(loaded).find(item => item.dataset.key === key);
const caps = item => kids(item, "i");
const strip = item => kids(item, "span").find(node => node.dataset.strip);
const tally = item => kids(item, "span").find(node => node.dataset.count);
const parts = item => kids(strip(item), "u").filter(node => !node.dataset.mark);
const px = (node, name) => Number(String(node.style.getPropertyValue(name)).replace("px", ""));
const rick = loaded => plain(loaded.api.status().rickCells);
const click = (loaded, target, extra = {}) => layer(loaded).dispatchEvent({ type: "click", detail: 1, target, ...extra });
// Окно → x клетки k полоски строки (середина клетки).
const cellX = (loaded, item, k) => px(layer(loaded), "left") + px(strip(item), "left") + k * Number(strip(item).dataset.pitch) + 0.5;
const tip = loaded => kids(layer(loaded), "i").find(node => node.dataset.tip);
const flowOpen = loaded => loaded.dom.query("#myclaude-rick-flow")?.style.getPropertyValue("display") === "block";

test("#9095: марафон «1 из 10» — полоска из 10 клеток (1 залита, 9 дышат), счёт у ↵; нет `total` — ячейки, как раньше", async () => {
  const old = { name: "Old", title: "Old", workflows: [{ n: 1, state: "готово" }, { n: 2, state: "идёт", phase: "кодинг" }] };
  const loaded = await page({ reply: ok(digest(M("Vkus", "drrrrrrrrr"), old)) });
  const vkus = row(loaded, "Vkus");
  assert.ok(strip(vkus), "полоски нет");
  assert.deepEqual(parts(vkus).map(node => node.dataset.state), ["done", ...Array(9).fill("run")]);
  // Широко — клетка на Workflow, не сливаются; шаг 12, зазор 1,5.
  assert.equal(strip(vkus).dataset.pitch, "12");
  assert.deepEqual(parts(vkus).map(node => px(node, "left")), Array.from({ length: 10 }, (_, k) => k * 12));
  assert.ok(parts(vkus).every(node => px(node, "width") === 10.5));
  // Идущие дышат волной: задержка растёт по порядку, у готовой её нет.
  assert.equal(parts(vkus)[0].style.getPropertyValue("animation-delay"), "");
  assert.deepEqual(parts(vkus).slice(1, 4).map(node => node.style.getPropertyValue("animation-delay")), ["0.00s", "0.16s", "0.32s"].map((v, k) => (k ? v : "")));
  // Ячеек в строке нет (упавших и ждущих нет); счёт — «1 из 10», числа отдельно от «из».
  assert.deepEqual(caps(vkus), []);
  assert.equal(tally(vkus).textContent, "1 из 10");
  assert.deepEqual(kids(tally(vkus), "b").map(node => node.textContent), ["1", "10"]);
  // Колонки (№14): полоска — с линии капсул соседа-ячеек; правый край счёта — правый край ↵.
  const legacy = row(loaded, "Old");
  assert.equal(strip(legacy), undefined, "без total — полоска");
  assert.deepEqual(caps(legacy).map(cap => cap.textContent), ["1 ✓", "2"]);
  assert.equal(px(strip(vkus), "left"), px(caps(legacy)[0], "left"));
  assert.equal(px(layer(loaded), "left") + px(tally(vkus), "left") + px(tally(vkus), "width"), SEND.left + SEND.width);
  assert.equal(rick(loaded).strips, 1);
  // `total` не сходится со списком — тоже ячейками.
  const odd = await page({ reply: ok(digest(M("Odd", "dr", { total: 5 }))) });
  assert.equal(strip(row(odd, "Odd")), undefined);
  assert.deepEqual(caps(row(odd, "Odd")).map(cap => cap.textContent), ["1 ✓", "2"]);
});

test("#9095: длинный марафон в узкой колонке — соседние одного состояния сливаются, полоска не налезает на счёт; ✕ и ! — ячейками за полоской", async () => {
  // 48: 1–25 готово, 26 упал, 27–42 готово, 43 идёт, 44 готово, 45–48 идут; второй — «4 !».
  const states = `${"d".repeat(25)}f${"d".repeat(16)}rd${"r".repeat(4)}`;
  const loaded = await page({ reply: ok(digest(M("Dictator", states), M("Trelvis", "rddw"))), shell: { left: 100, top: 600, width: 300, height: 120 } });
  const dict = row(loaded, "Dictator");
  const pitch = Number(strip(dict).dataset.pitch);
  assert.ok(pitch < 6 && pitch >= 1.5, `шаг ${pitch}`);
  // Слились: отрезки идут подряд, покрывают все 48, соседние разного состояния.
  const runs = parts(dict).map(node => [node.dataset.state, Number(node.dataset.from), Number(node.dataset.to)]);
  // WF204: идущие — каждый своей клеткой и в узкой колонке.
  assert.deepEqual(runs, [["done", 0, 24], ["fail", 25, 25], ["done", 26, 41], ["run", 42, 42], ["done", 43, 43], ["run", 44, 44], ["run", 45, 45], ["run", 46, 46], ["run", 47, 47]]);
  // Ячейка упавшего — за полоской, с зазором; счёт — правее неё, в границах строки.
  const fail = caps(dict);
  assert.deepEqual(fail.map(cap => [cap.textContent, cap.dataset.state, cap.dataset.n]), [["26 ✕", "fail", "26"]]);
  const stripEnd = px(strip(dict), "left") + px(strip(dict), "width");
  assert.ok(px(fail[0], "left") >= stripEnd + 5, `ячейка налезла на полоску: ${px(fail[0], "left")} < ${stripEnd}`);
  assert.ok(px(tally(dict), "left") >= px(fail[0], "left") + px(fail[0], "width"), "счёт налез на ячейку");
  assert.equal(tally(dict).textContent, "42 из 48");
  // Enter вне узкой рамки — счёт у правого края строк (ширина 300 − 12 − 3).
  assert.equal(px(tally(dict), "left") + px(tally(dict), "width"), 285);
  // Счёт — одной колонкой: у обоих правый край один.
  const trel = row(loaded, "Trelvis");
  assert.equal(px(tally(trel), "left") + px(tally(trel), "width"), 285);
  assert.equal(px(tally(trel), "width"), px(tally(dict), "width"));
  assert.deepEqual(caps(trel).map(cap => cap.textContent), ["4 !"]);
  assert.equal(tally(trel).textContent, "2 из 4");
  // Короткий марафон: готовые подряд слиты всегда (WF204), идущий и ждущий — своими клетками.
  assert.deepEqual(parts(trel).map(node => node.dataset.state), ["run", "done", "wait"]);
});

test("#9095: наведение на клетку — её ячейка «45» над клеткой и свет клетки; уход — гаснет; клик — карточка этого Workflow, ещё клик — закрыть", async () => {
  const states = `${"d".repeat(44)}${"r".repeat(4)}`;
  const loaded = await page({ reply: ok(digest(M("Dictator", states))) });
  const dict = row(loaded, "Dictator");
  const bar = strip(dict);
  const x = cellX(loaded, dict, 44);
  layer(loaded).dispatchEvent({ type: "pointermove", target: parts(dict).at(-1), clientX: x });
  assert.deepEqual(rick(loaded).hover, { key: "Dictator", n: 45 });
  assert.equal(tip(loaded).style.getPropertyValue("display"), "block");
  assert.equal(tip(loaded).textContent, "45");
  assert.equal(tip(loaded).dataset.state, "run");
  // Ячейка — над клеткой (низ ячейки выше полоски), ножка смотрит в середину клетки.
  const tipBottom = px(tip(loaded), "top") + 12;
  const rowTop = px(list(loaded), "top") + px(dict, "top");
  assert.ok(tipBottom <= rowTop + 4.5 - 3, `ячейка на полоске: ${tipBottom} > ${rowTop + 4.5}`);
  const mid = px(bar, "left") + 44 * Number(bar.dataset.pitch) + (Number(bar.dataset.pitch) - Number(bar.dataset.gap)) / 2;
  assert.equal(px(tip(loaded), "left") + px(tip(loaded), "--sx"), Math.round(mid * 2) / 2);
  const mark = kids(bar, "u").find(node => node.dataset.mark === "hover");
  assert.equal(px(mark, "left"), 44 * Number(bar.dataset.pitch));
  // Готовая клетка — в слитом отрезке 1–44 (WF204): ячейка диапазона.
  layer(loaded).dispatchEvent({ type: "pointermove", target: parts(dict)[0], clientX: cellX(loaded, dict, 2) });
  assert.equal(tip(loaded).textContent, "WF1–WF44 · готово");
  assert.equal(kids(bar, "u").filter(node => node.dataset.mark === "hover").length, 1, "свет остался на прежней клетке");
  // Ушёл с полоски — гаснет.
  layer(loaded).dispatchEvent({ type: "pointerout", target: bar, relatedTarget: null });
  assert.equal(rick(loaded).hover, null);
  assert.equal(tip(loaded).style.getPropertyValue("display"), "none");
  // Клик по клетке 45 — карточка Workflow 45; клетка светится открытой.
  click(loaded, parts(dict).at(-1), { clientX: x });
  assert.equal(rick(loaded).card, "flow");
  assert.equal(flowOpen(loaded), true);
  assert.match(rick(loaded).flow, /^Воркфлоу 45 ·/);
  const picked = kids(strip(row(loaded, "Dictator")), "u").find(node => node.dataset.mark === "picked");
  assert.equal(px(picked, "left"), 44 * Number(bar.dataset.pitch));
  click(loaded, parts(row(loaded, "Dictator")).at(-1), { clientX: x });
  assert.equal(rick(loaded).card, null, "повторный клик не закрыл");
  // Ячейка упавшего за полоской — та же карточка.
  const fell = await page({ reply: ok(digest(M("A", "dfr"))) });
  click(fell, caps(row(fell, "A"))[0]);
  assert.equal(rick(fell).card, "flow");
  assert.match(rick(fell).flow, /^Воркфлоу 2 ·/);
});

test("#9095: клик по счёту «1 из 10» — строка по одному (как «1–N ✓»), Esc — назад к полоске", async () => {
  const loaded = await page({ reply: ok(digest(M("Vkus", "drrrrrrrrr"))) });
  click(loaded, kids(tally(row(loaded, "Vkus")), "b")[0]);
  const open = row(loaded, "Vkus");
  assert.equal(strip(open), undefined, "раскрытая строка — всё ещё полоска");
  assert.deepEqual(caps(open).map(cap => cap.textContent), ["1 ✓", "2", "3", "4", "5", "6", "7", "8", "9", "10"]);
  assert.equal(rick(loaded).open, 1);
  loaded.win.dispatchEvent({ type: "keydown", key: "Escape", preventDefault() {}, stopPropagation() {} });
  loaded.document.dispatchEvent?.({ type: "keydown", key: "Escape", preventDefault() {}, stopPropagation() {} });
  settle(loaded);
  assert.equal(rick(loaded).open, 0);
  assert.ok(strip(row(loaded, "Vkus")));
});

test("#9095: фильтр отбирает проекты — «В работе» живые, «Сделано» кончённые, «Всё» все; полоска у всех одна", async () => {
  const data = digest(M("Live", "ddrp"), M("Done", "ddd"), M("Wait", "dw"), M("Plan", "pp"));
  const keys = loaded => rows(loaded).map(item => item.dataset.key);
  const shell = { left: 100, top: 300, width: 1000, height: 420 };
  const run = await page({ reply: ok(data), filter: "run", shell });
  assert.deepEqual(keys(run).sort(), ["Live", "Wait"]);
  // Полоска «В работе» — весь марафон, не только живые (готовые подряд — одной полосой, WF204).
  assert.deepEqual(parts(row(run, "Live")).map(node => [node.dataset.state, node.dataset.from, node.dataset.to]), [["done", "0", "1"], ["run", "2", "2"], ["plan", "3", "3"]]);
  const done = await page({ reply: ok(data), filter: "done", shell });
  assert.deepEqual(keys(done), ["Done"]);
  assert.equal(tally(row(done, "Done")).textContent, "3 из 3");
  const all = await page({ reply: ok(data), filter: "all", shell });
  assert.deepEqual(keys(all).sort(), ["Done", "Live", "Plan", "Wait"]);
});

test("WF201 (класс #9159): потолок команды status на странице — 128 КБ: 20 проектов по 6 КБ доходят все, разбор быстрый", async () => {
  const loaded = await page({ reply: ok(digest(M("A", "d"))) });
  const block = n => `${[...String(n)].map(d => `${d}\uFE0F\u20E3`).join("")} Workflow ✅ готово\n- о чём: ${"длинное описание работы ".repeat(8)}\n- шаги 3 из 3\n- 10:00 → 10:30 · 30 мин\n- кодинг · Opus 5.5 high ×1\n`;
  const text = name => `# ${name}\n\nобновлено 05:00\n\n${Array.from({ length: 22 }, (_, k) => block(k + 1)).join("\n")}`.slice(0, 6000);
  const projects = Array.from({ length: 20 }, (_, k) => ({ name: `P${k + 1}`, text: text(`P${k + 1}`) }));
  const size = projects.reduce((sum, item) => sum + item.name.length + item.text.length, 0);
  assert.ok(size > 100 * 1024 && size < 128 * 1024, `размер ${size}`);
  const started = performance.now();
  loaded.dom.command({ id: "s201", action: "status", at: "now", scope: "all", projects });
  const spent = performance.now() - started;
  assert.equal(plain(loaded.api.status().statusFeed.projects).length, 20, "проекты за 32 КБ отброшены");
  assert.ok(spent < 1500, `разбор ${Math.round(spent)} мс`);
  assert.equal(loaded.inner.statusFeedProject("P20").blocks.length > 10, true);
  // Раскладка после прихода сводки не разбирает её заново: 20 проходов — быстро.
  const again = performance.now();
  for (let i = 0; i < 20; i += 1) settle(loaded);
  assert.ok(performance.now() - again < 1500, "раскладка медленная");
  // Больше 128 КБ — лишние отбрасываются целиком (половина сводки хуже, чем ничего).
  const more = Array.from({ length: 30 }, (_, k) => ({ name: `Q${k + 1}`, text: text(`Q${k + 1}`) }));
  loaded.dom.command({ id: "s201b", action: "status", at: "now", scope: "all", projects: more });
  const kept = plain(loaded.api.status().statusFeed.projects).length;
  assert.ok(kept >= 20 && kept < 30, `осталось ${kept}`);
});

test("WF201 (№13): карточка Workflow не закрывает строку своей капсулы — над её первой строкой с зазором, нет места — под строкой", async () => {
  // Раскрытая строка в две строки: капсула 30 — на второй; карточка — над первой (имя видно).
  const flows = Array.from({ length: 30 }, (_, k) => ({ n: k + 1, state: k === 29 ? "идёт" : "готово", about: `р ${k + 1}`, phase: k === 29 ? "кодинг" : "" }));
  const reply = ok(digest({ name: "Long", title: "Long", group: "идут", workflows: flows }));
  const loaded = await page({ reply, shell: { left: 100, top: 300, width: 500, height: 420 } });
  click(loaded, caps(row(loaded, "Long")).find(cap => cap.dataset.act === "open"));
  settle(loaded);
  const line = row(loaded, "Long");
  assert.ok(px(line, "height") > 16, "строка не в две строки");
  const cap = caps(line).find(item => item.textContent === "30");
  assert.ok(px(cap, "top") > 10, "капсула 30 не на второй строке");
  click(loaded, cap);
  const card = loaded.dom.query("#myclaude-rick-flow");
  const rowTop = px(layer(loaded), "top") + px(list(loaded), "top") + px(line, "top");
  assert.equal(px(card, "bottom"), 800 - rowTop + 6, "карточка не над первой строкой ряда");
  // Места над строкой и полем нет — под строкой, с зазором.
  const low = await page({ reply, shell: { left: 100, top: 20, width: 500, height: 140 } });
  const first = row(low, "Long");
  click(low, caps(first).find(cap => cap.textContent === "30"));
  const under = low.dom.query("#myclaude-rick-flow");
  const top = px(layer(low), "top") + px(list(low), "top") + px(first, "top");
  assert.equal(under.style.getPropertyValue("bottom"), "auto");
  assert.equal(px(under, "top"), Math.round(top + px(first, "height") + 6));
});
