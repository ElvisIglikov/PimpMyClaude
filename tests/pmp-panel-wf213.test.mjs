// WF213 (#9370–#9373, #9405; раздел 12п³ inject.js): панель оркестрации на кнопке PMP.
//
// Что проверяется (карточка WF213, контракты К-DG и К-KO):
//   1) чистая часть — разбор /digest в модель панели: строка итога, строки счётчика и «Тихо»,
//      проценты из шагов, счёт терминалов, «ждут тебя», работа без новых полей (старое приложение);
//   2) открытие и закрытие — кнопка, повторное нажатие, Esc, клик мимо; опрос, пока открыта;
//   3) вид каждого состояния — загрузка, данные, пусто, приложение не отвечает;
//   4) команды — «Запустить Workflow» (GET /kickoff; 404 — пункта нет), «Отчёт», «Что происходит»
//      (в пустое и непустое поле, набранное не затирается), «Настройки Пимпа» (GET /panel);
//   5) число «▶N» у кнопки и редкий запрос ради него там, где блока Рика нет;
//   6) status().pmp — open, rows, terminals, running, lastError.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";

const PMP = "#myclaude-pmp";
const PANEL = "#myclaude-pmp-panel";
const CHAT = "local_aaaa-1111";
const PORT = "http://127.0.0.1:47615";
const KICKOFF = "🚀 Запуск воркфлоу\nПрочитай правила и предложи план.";
const NOW = Date.parse("2026-10-10T04:00:00Z");

const flow = (n, state, extra = {}) => ({ n, state, about: `дело ${n}`, steps: "", phase: "", ...extra });
// Сводка с добавкой К-DG: два идущих проекта, ждущий, давно молчащий и терминал без сводки.
const DIGEST = {
  v: 1, at: "2026-10-10T03:59:00Z", projects: [
    { name: "PimpMyClaude", title: "PimpMyClaude", marker: "⚪", color: "#ff2d55", group: "идут", done: 2, total: 5, at: "2026-10-10T03:58:00Z",
      now: "идёт панель на кнопке PMP.", wait: "файл 37 — четыре вопроса.", terminal: true,
      workflows: [flow(1, "готово", { steps: "3/3" }), flow(2, "готово"),
        flow(3, "идёт", { about: "панель оркестрации", steps: "2/4", phase: "кодинг", role: "кодинг · 2 агента", when: "03:40 → закончит в 04:30 · идёт 20 мин" }),
        flow(4, "упал"), flow(5, "впереди")] },
    { name: "PimpViewer", title: "PimpViewer", marker: "🖼", color: "#ed5e79", group: "идут", done: 0, total: 1, at: "2026-10-10T03:50:00Z",
      terminal: true, workflows: [flow(1, "идёт", { about: "архив вместо «закрыть»", steps: "1/3" })] },
    { name: "MenuMaker", title: "MenuMaker", marker: "🎛️", color: "#98a6c8", group: "ждут", done: 1, total: 2, at: "2026-10-09T20:00:00Z",
      terminal: false, workflows: [flow(1, "готово"), flow(2, "ждёт", { about: "выбрать шрифт меню" })] },
    { name: "PlaudClaud", title: "PlaudClaud — ночь 01.10", marker: "🎙️", color: "bad", group: "тихо", done: 1, total: 2, at: "2026-09-20T10:00:00Z",
      wait: "старое слово", terminal: false, workflows: [flow(1, "готово"), flow(2, "идёт")] },
    { name: "Bambubek", title: "Bambubek", marker: "", color: "#19a2e1", group: "тихо", done: 0, total: 0, at: "", terminal: true, workflows: [] },
  ],
};
// Тот же ответ от старого приложения: полей К-DG нет.
const OLD = {
  v: 1, at: DIGEST.at, projects: DIGEST.projects.filter(project => project.total > 0).map(({ now, wait, terminal, ...project }) => ({
    ...project, workflows: project.workflows.map(({ when, role, ...item }) => item),
  })),
};

test("К-DG: шаги «2/4» — процент; время без начала; роль без техники; «работают N терминалов» по числу", () => {
  const { inner } = loadInner();
  assert.deepEqual(plain(inner.pmpSteps("2/4")), { done: 2, total: 4, percent: 50 });
  assert.deepEqual(plain(inner.pmpSteps("1/3")), { done: 1, total: 3, percent: 33 });
  assert.deepEqual(plain(inner.pmpSteps(" 5 / 4 ")), { done: 4, total: 4, percent: 100 }, "сделано больше, чем шагов, — не больше 100 %");
  for (const junk of ["", "0/0", "2", "a/b", null, undefined]) assert.equal(inner.pmpSteps(junk), null, String(junk));
  assert.equal(inner.pmpWhen("13:05 → закончит в 13:50 · идёт 25 мин"), "закончит в 13:50 · идёт 25 мин");
  assert.equal(inner.pmpWhen("идёт 5 мин"), "идёт 5 мин");
  assert.equal(inner.pmpWhen(undefined), "");
  assert.equal(inner.pmpRole("кодинг · 2 агента"), "кодинг");
  assert.equal(inner.pmpRole("проверка"), "проверка");
  assert.equal(inner.pmpRole("критик · 1 агент · Opus 5.5 high"), "критик");
  assert.equal(inner.pmpRole(undefined), "");
  assert.equal(inner.pmpTerminalsTitle(1), "Работает 1 терминал");
  assert.equal(inner.pmpTerminalsTitle(3), "Работают 3 терминала");
  assert.equal(inner.pmpTerminalsTitle(9), "Работают 9 терминалов");
  assert.equal(inner.pmpTerminalsTitle(21), "Работает 21 терминал");
});

test("К-DG: /digest → модель панели — итог, строки счётчика, «Тихо», терминалы, «ждут тебя»", () => {
  const { inner } = loadInner();
  const model = plain(inner.pmpModel(DIGEST, NOW));
  // Итог — по проектам, где сейчас идёт (группа «идут»): давно молчащий проект в счёт не идёт.
  assert.deepEqual([model.projects, model.flows, model.done, model.running], [2, 6, 2, 2]);
  assert.deepEqual(model.rows.map(row => [row.name, row.done, row.total, row.running, row.failed]), [["PimpM", 2, 5, 1, 1], ["PimpV", 0, 1, 1, 0]]);
  assert.deepEqual(model.rows[0].cells.map(cell => cell.state), ["done", "done", "run", "fail", "plan"]);
  assert.equal(model.rows[0].color, "#ff2d55");
  assert.equal(model.rows[0].cells[2].tip, "PimpMyClaude · Workflow 3 · идёт · шаги 2/4\nпанель оркестрации");
  assert.equal(model.rows[0].cells[0].tip, "PimpMyClaude · Workflow 1 · готово · шаги 3/3\nдело 1");
  // «Тихо»: всё, где сейчас не идёт; идущий там — янтарный, но не в счёте, и подсказка говорит почему.
  assert.deepEqual(model.quiet.map(row => [row.name, row.done, row.total, row.running]), [["Menu", 1, 2, 0], ["Plaud", 1, 2, 0]]);
  assert.equal(model.quiet[0].cells[1].state, "wait");
  assert.equal(model.quiet[1].color, "", "мусорный цвет не берём");
  assert.equal(model.quiet[1].cells[1].tip, "PlaudClaud — ночь 01.10 · Workflow 2 · идёт · сводка старше суток\nдело 2");
  // Терминалы — проекты с terminal: true; что делает — «Сейчас», нет её — «о чём» идущего, нет ничего — имя.
  assert.equal(model.known, true);
  assert.deepEqual(model.terminals.map(item => [item.name, item.text]), [["PimpM", "идёт панель на кнопке PMP."], ["PimpV", "архив вместо «закрыть»"], ["Bambubek", ""]]);
  assert.deepEqual(model.terminals[0].flows, [{ n: 3, about: "панель оркестрации", steps: { done: 2, total: 4, percent: 50 }, when: "закончит в 04:30 · идёт 20 мин", role: "кодинг" }]);
  assert.equal(model.terminals[0].wait, "файл 37 — четыре вопроса.");
  assert.deepEqual(model.terminals[2].flows, []);
  // «Ждут тебя»: строка «Ждёт…», нет её — Workflow в состоянии «ждёт»; сводка старше недели — не показываем.
  assert.deepEqual(model.waits.map(item => [item.name, item.text]), [["PimpM", "файл 37 — четыре вопроса."], ["Menu", "выбрать шрифт меню"]]);
});

test("К-DG: старое приложение (новых полей нет) — «кто что делает» по группе «идут», остальное как было", () => {
  const { inner } = loadInner();
  const model = plain(inner.pmpModel(OLD, NOW));
  assert.equal(model.known, false);
  assert.deepEqual([model.projects, model.flows, model.done, model.running], [2, 6, 2, 2]);
  assert.deepEqual(model.terminals.map(item => [item.name, item.text, item.wait]), [["PimpM", "панель оркестрации", ""], ["PimpV", "архив вместо «закрыть»", ""]]);
  assert.deepEqual(plain(model.terminals[0].flows[0]), { n: 3, about: "панель оркестрации", steps: { done: 2, total: 4, percent: 50 }, when: "", role: "" });
  assert.deepEqual(model.waits.map(item => item.name), ["Menu"]);
  // Имена: два проекта с одним коротким именем — с буквой второй части; три, где и так совпало, — целиком;
  // разметка сводки («**важно**») на экран не идёт.
  const names = list => plain(inner.pmpModel({ projects: list.map(title => ({ name: title, title, group: "идут", terminal: true, now: "чат на **Opus** — `сборка`", workflows: [flow(1, "идёт")] })) }, NOW)).terminals;
  assert.deepEqual(names(["PimpMyClaude", "PimpViewer", "Dictator"]).map(item => item.name), ["PimpM", "PimpV", "Dictator"]);
  assert.deepEqual(names(["PimpMyClaude", "PimpViewer", "PimpMyTV"]).map(item => item.name), ["PimpMyClaude", "PimpViewer", "PimpMyTV"]);
  assert.equal(names(["A"])[0].text, "чат на Opus — сборка");
  // Мусор вместо ответа — пустая модель, без падения.
  for (const junk of [null, {}, { projects: "нет" }, { projects: [null, 5, "x"] }]) {
    const empty = plain(inner.pmpModel(junk, NOW));
    assert.deepEqual([empty.rows, empty.quiet, empty.terminals, empty.waits, empty.running], [[], [], [], [], 0]);
  }
});

// ---- страница --------------------------------------------------------------
const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const tick = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };
const okJson = body => () => Promise.resolve({ ok: true, json: async () => body });
// Окно стенда: поле left…left+width с верхом top, под ним нижняя строка с группой «+» и кнопкой модели.
const page = async ({ cwd = "/Users/dev/Projects/Trelvis", digest = okJson(DIGEST), kickoff = () => Promise.resolve({ ok: false, status: 404 }), panel = () => Promise.resolve({ ok: true }), text = "",
  viewport = { width: 1200, height: 800 }, left = 100, width = 1000, top = 600 } = {}) => {
  const loaded = loadInject({
    title: "Чат", href: `https://claude.ai/epitaxy/${CHAT}`, geometry: { viewport },
    html: dom => {
      const parts = dom.composer({ top, left, width, text });
      const y = top + 148;
      parts.chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: { left, top: y - 4, width, height: 28 } });
      const row = parts.chin.add("div", { class: "flex items-center", rect: { left, top: y, width, height: 20 } });
      parts.left = row.add("div", { class: "flex items-center self-start", rect: { left, top: y + 2, width: 60, height: 16 } });
      parts.left.add("button", { attrs: { "aria-label": "Add" }, rect: { left, top: y + 2, width: 20, height: 16 } });
      const right = row.add("div", { class: "ms-auto flex items-center", rect: { left: left + width - 100, top: y, width: 100, height: 20 } });
      const grid = right.add("div", { class: "grid", rect: { left: left + width - 100, top: y, width: 100, height: 20 } });
      grid.add("button", { attrs: { "data-testid": "epitaxy-cds-model-selector" }, text: "Opus 5.5", rect: { left: left + width - 100, top: y + 2, width: 60, height: 16 } });
      grid.add("button", { attrs: { "aria-haspopup": "dialog", "aria-label": "Usage: Context 300k / 1M (30%)" }, rect: { left: left + width - 20, top: y, width: 20, height: 20 } });
      const side = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
      const item = side.add("div", { attrs: { "data-row-key": `code:${CHAT}` } });
      item.__reactFiber$test = { memoizedProps: { session: { ref: { id: CHAT }, source: { data: { cwd } } } }, return: null };
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.replies = { digest, kickoff, panel };
  loaded.win.fetch = url => {
    const path = String(url).replace(PORT, "");
    loaded.calls.push(path);
    return (loaded.replies[path.slice(1)] ?? (() => Promise.reject(new Error(path))))();
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
const button = loaded => loaded.dom.query(PMP);
const panel = loaded => loaded.dom.query(PANEL);
const shown = loaded => panel(loaded).style.getPropertyValue("display") === "flex";
const pmp = loaded => plain(loaded.api.status().pmp);
const press = loaded => button(loaded).dispatchEvent({ type: "click", detail: 1 });
const open = async loaded => { press(loaded); await tick(); };
const all = loaded => [...panel(loaded).querySelectorAll("*")];
const parts = (loaded, k) => all(loaded).filter(node => node.dataset.k === k);
const heads = loaded => all(loaded).filter(node => node.tagName === "H3").map(node => node.textContent);
const acts = loaded => all(loaded).filter(node => node.tagName === "BUTTON" && node.parentNode.tagName === "NAV").map(node => node.textContent);
// Стаб событий не всплывает: слушатель панели получает нажатие с целью — нужным узлом.
const click = (loaded, target) => panel(loaded).dispatchEvent({ type: "click", detail: 1, target });
const act = (loaded, name) => click(loaded, all(loaded).find(node => node.tagName === "BUTTON" && node.dataset.act === name));
const count = (loaded, path) => loaded.calls.filter(item => item === path).length;
// Клавиши слушает общий слушатель окна (onKeyDown): он на захвате раньше всех слушателей document.
const key = (loaded, name, extra = {}) => loaded.win.dispatchEvent({ type: "keydown", key: name, ...extra });

test("#9373: нажатие открывает панель над полем и сразу спрашивает сводку и текст запуска; повторное — закрывает", async () => {
  const loaded = await page();
  assert.equal(count(loaded, "/digest"), 1, "закрыта, блока Рика нет — один запрос ради числа у кнопки");
  assert.equal(shown(loaded), false);
  assert.equal(panel(loaded).getAttribute("role"), "group", "роль dialog держали бы за открытое окно Claude");
  await open(loaded);
  assert.equal(shown(loaded), true);
  assert.equal(button(loaded).getAttribute("aria-expanded"), "true");
  assert.deepEqual([count(loaded, "/digest"), count(loaded, "/kickoff"), count(loaded, "/panel")], [2, 1, 0]);
  // Над полем (верх поля — 600), по его левому краю, не шире 480 и не выше 70 % окна.
  const style = panel(loaded).style;
  assert.equal(style.getPropertyValue("left"), "100px");
  assert.equal(style.getPropertyValue("width"), "480px");
  assert.equal(style.getPropertyValue("bottom"), `${800 - 600 + 6}px`);
  assert.equal(style.getPropertyValue("max-height"), "560px");
  assert.equal(panel(loaded).dataset.narrow, "false");
  assert.deepEqual(pmp(loaded), { button: true, clicks: 0, last: null, state: null, open: true, rows: 2, terminals: 3, running: 2, lastError: null });
  press(loaded);
  assert.equal(shown(loaded), false);
  assert.equal(button(loaded).getAttribute("aria-expanded"), "false");
  assert.equal(pmp(loaded).open, false);
});

test("#9373: Esc и клик мимо закрывают; нажатие внутри — нет и фокус поля не отнимает; двойной клик — одно нажатие", async () => {
  const loaded = await page();
  await open(loaded);
  assert.equal(key(loaded, "Escape"), false, "Esc дошёл бы до Claude и остановил ответ");
  assert.equal(shown(loaded), false);
  key(loaded, "Escape");
  assert.equal(shown(loaded), false, "закрытая панель клавишу не слушает");
  await open(loaded);
  assert.equal(panel(loaded).dispatchEvent({ type: "pointerdown" }), false, "нажатие в панели отняло бы фокус у поля");
  assert.equal(panel(loaded).dispatchEvent({ type: "mousedown" }), false);
  loaded.document.dispatchEvent({ type: "pointerdown", target: all(loaded)[0] });
  assert.equal(shown(loaded), true, "нажатие внутри панели закрыло её");
  loaded.document.dispatchEvent({ type: "pointerdown", target: button(loaded) });
  assert.equal(shown(loaded), true, "нажатие по самой кнопке — её дело: закроет клик");
  loaded.document.dispatchEvent({ type: "pointerdown", target: loaded.parts.editor });
  assert.equal(shown(loaded), false, "клик мимо не закрыл");
  button(loaded).dispatchEvent({ type: "click", detail: 2 });
  assert.equal(shown(loaded), false, "второй щелчок двойного клика");
});

test("#9373: клавиатура — Enter на кнопке открывает и ставит фокус на первый пункт; Tab ходит по пунктам по кругу; Esc возвращает фокус в поле", async () => {
  const loaded = await page();
  button(loaded).dispatchEvent({ type: "keydown", key: "Enter" });
  await tick();
  assert.equal(shown(loaded), true);
  // Строки, которым нечего раскрывать (текст виден целиком), Tab не берёт — у них метка data-flat.
  const items = all(loaded).filter(node => node.tagName === "BUTTON" && node.dataset.flat !== "true");
  assert.ok(items.length >= 5, "пункты панели — настоящие кнопки");
  const waits = parts(loaded, "row").filter(node => node.dataset.kind === "wait");
  assert.deepEqual(waits.map(node => node.dataset.flat), ["true", "true"], "стенд: текст в две строки влезает — стрелки и нажатия нет");
  click(loaded, waits[0]);
  assert.equal(waits[0].getAttribute("aria-expanded"), "false");
  assert.equal(loaded.document.activeElement, items[0]);
  key(loaded, "Tab");
  assert.equal(loaded.document.activeElement, items[1]);
  key(loaded, "Tab", { shiftKey: true });
  key(loaded, "Tab", { shiftKey: true });
  assert.equal(loaded.document.activeElement, items.at(-1), "с первого назад — на последний");
  key(loaded, "Tab");
  assert.equal(loaded.document.activeElement, items[0], "с последнего вперёд — на первый");
  key(loaded, "Escape");
  assert.equal(shown(loaded), false);
  assert.equal(loaded.document.activeElement, loaded.parts.editor);
  button(loaded).dispatchEvent({ type: "keydown", key: " " });
  assert.equal(shown(loaded), true, "пробел — то же нажатие");
});

test("#9405, #9371: живые данные — «Идёт Workflow сейчас · N», итог, квадратики, «Тихо», терминалы с плашкой, «Ждут тебя»", async () => {
  const loaded = await page();
  await open(loaded);
  assert.equal(panel(loaded).dataset.state, "ok");
  assert.deepEqual(heads(loaded), ["Идёт Workflow сейчас · 2", "Работают 3 терминала", "Ждут тебя · 2"]);
  assert.deepEqual(parts(loaded, "sum").map(node => node.textContent), ["2 проекта · 6 Workflow · 2 готово · 2 идут"]);
  assert.ok(!panel(loaded).textContent.includes("марафон"), "слово «марафон» не пишем");
  const rows = parts(loaded, "row").filter(node => node.parentNode.dataset.k === "flows");
  assert.deepEqual(rows.map(node => node.textContent), ["PimpM2/5 ▶1 ✕1", "PimpV0/1 ▶1"]);
  assert.equal(rows[0].style.getPropertyValue("--c"), "#ff2d55");
  assert.deepEqual([...parts(loaded, "caps")[0].children].map(node => node.dataset.state), ["done", "done", "run", "fail", "plan"]);
  // «Тихо» свёрнуто строкой с числом; нажал — строки проектов под ней, приглушённые.
  const quiet = all(loaded).find(node => node.dataset.act === "quiet");
  assert.equal(quiet.textContent, "Тихо · 2");
  assert.equal(quiet.getAttribute("aria-expanded"), "false");
  assert.equal(pmp(loaded).rows, 2);
  click(loaded, quiet);
  assert.deepEqual(all(loaded).filter(node => node.dataset.quiet === "true").map(node => node.textContent), ["Menu1/2", "Plaud1/2"]);
  assert.equal(pmp(loaded).rows, 4);
  // Терминалы: строка «имя — что делает»; есть что раскрыть — кнопка; без сведений — просто имя.
  const terms = parts(loaded, "row").filter(node => node.dataset.kind === "term");
  assert.deepEqual(terms.map(node => [node.tagName, node.textContent]), [["BUTTON", "PimpMидёт панель на кнопке PMP."], ["BUTTON", "PimpVархив вместо «закрыть»"], ["DIV", "Bambubek"]]);
  const plate = terms[0].nextElementSibling;
  assert.deepEqual([terms[0].getAttribute("aria-expanded"), plate.dataset.k, plate.dataset.open], ["false", "plate", "false"]);
  click(loaded, terms[0].children[1]);
  assert.deepEqual([terms[0].getAttribute("aria-expanded"), plate.dataset.open], ["true", "true"], "нажатие по строке плашку не выдвинуло");
  assert.equal(plate.textContent, "панель оркестрациикодинг · шаги 2 из 4 · 50 % · закончит в 04:30 · идёт 20 минЖдёт тебя: файл 37 — четыре вопроса.");
  assert.equal(all(loaded).find(node => node.dataset.k === "bar").style.getPropertyValue("--p"), "50%");
  for (const word of ["агент", "гейт", "батч", "Opus", "wf209"]) assert.ok(!plate.textContent.includes(word), word);
  click(loaded, terms[0]);
  assert.deepEqual([terms[0].getAttribute("aria-expanded"), plate.dataset.open], ["false", "false"], "повторное нажатие не задвинуло");
  // «Ждут тебя»: имя — чего ждут.
  assert.deepEqual(parts(loaded, "row").filter(node => node.dataset.kind === "wait").map(node => node.textContent), ["PimpMфайл 37 — четыре вопроса.", "Menuвыбрать шрифт меню"]);
  assert.deepEqual(acts(loaded), ["Отчёт", "Что происходит", "Настройки Пимпа"], "текста запуска нет (404) — пункта «Запустить Workflow» нет");
});

test("#9405: наведение на квадратик — какой это Workflow, состояние, шаги и о чём; ушёл — подсказки нет", async () => {
  const loaded = await page();
  await open(loaded);
  const tip = parts(loaded, "tip")[0];
  const box = parts(loaded, "caps")[0].children[2];
  panel(loaded).dispatchEvent({ type: "pointerover", target: box });
  assert.equal(tip.style.getPropertyValue("display"), "block");
  assert.equal(tip.textContent, "PimpMyClaude · Workflow 3 · идёт · шаги 2/4\nпанель оркестрации");
  panel(loaded).dispatchEvent({ type: "pointerover", target: parts(loaded, "sum")[0] });
  assert.equal(tip.style.getPropertyValue("display"), "none");
});

test("#9371: старое приложение — заголовок «Кто что делает», строки по группе «идут»", async () => {
  const loaded = await page({ digest: okJson(OLD) });
  await open(loaded);
  assert.deepEqual(heads(loaded), ["Идёт Workflow сейчас · 2", "Кто что делает", "Ждут тебя · 1"]);
  assert.deepEqual(parts(loaded, "row").filter(node => node.dataset.kind === "term").map(node => node.textContent), ["PimpMпанель оркестрации", "PimpVархив вместо «закрыть»"]);
});

test("состояния: загрузка — «Смотрю, что идёт…»; пусто — «Сейчас ничего не идёт»; приложение молчит — одна строка и только команды, которым оно не нужно", async () => {
  // Загрузка: первый ответ ещё не пришёл.
  const slow = await page({ digest: () => new Promise(() => {}) });
  await open(slow);
  assert.equal(panel(slow).dataset.state, "load");
  assert.deepEqual(parts(slow, "note").map(node => node.textContent), ["Смотрю, что идёт…"]);
  assert.deepEqual(acts(slow), ["Отчёт", "Что происходит", "Настройки Пимпа"]);
  // Тишина дольше срока опроса — приложение не отвечает.
  slow.later(10000);
  slow.dom.fireKind("interval");
  assert.equal(panel(slow).dataset.state, "error");
  assert.equal(pmp(slow).lastError, "Пимп у часов не отвечает");
  // Пусто: проектов нет; терминалы спросили — их нет.
  const empty = await page({ digest: okJson({ v: 1, at: DIGEST.at, projects: [{ name: "A", title: "A", group: "тихо", color: "#112233", terminal: false, workflows: [flow(1, "готово")] }] }) });
  await open(empty);
  assert.deepEqual(heads(empty), ["Идёт Workflow сейчас", "Терминалы сейчас не работают"]);
  assert.deepEqual(parts(empty, "note").map(node => node.textContent), ["Сейчас ничего не идёт"]);
  assert.equal(all(empty).find(node => node.dataset.act === "quiet").textContent, "Тихо · 1");
  assert.deepEqual(pmp(empty), { button: true, clicks: 0, last: null, state: null, open: true, rows: 0, terminals: 0, running: 0, lastError: null });
  // Ошибка: отказ сети и ответ не 200.
  for (const digest of [() => Promise.reject(new Error("net")), () => Promise.resolve({ ok: false, status: 500 })]) {
    const down = await page({ digest, kickoff: () => Promise.resolve({ ok: true, text: async () => KICKOFF }) });
    await open(down);
    assert.equal(panel(down).dataset.state, "error");
    assert.deepEqual(parts(down, "note").map(node => node.textContent), ["Пимп у часов не отвечает"]);
    assert.deepEqual(heads(down), []);
    assert.deepEqual(acts(down), ["Отчёт", "Что происходит"]);
    assert.equal(pmp(down).lastError, "Пимп у часов не отвечает");
    // Приложение вернулось — следующий опрос возвращает вид.
    down.replies.digest = okJson(DIGEST);
    down.later(10000);
    down.dom.fireKind("interval");
    await tick();
    assert.equal(panel(down).dataset.state, "ok");
    assert.equal(pmp(down).lastError, null);
    assert.deepEqual(acts(down), ["Запустить Workflow", "Отчёт", "Что происходит", "Настройки Пимпа"]);
  }
});

test("опрос: открыта — раз в 10 с; закрыта и блока Рика нет — не чаще раза в минуту и только пока окно видно", async () => {
  const loaded = await page();
  await open(loaded);
  assert.equal(count(loaded, "/digest"), 2);
  loaded.later(10000);
  loaded.dom.fireKind("interval");
  await tick();
  assert.equal(count(loaded, "/digest"), 3, "открытая панель не обновилась");
  press(loaded);
  for (let step = 0; step < 5; step += 1) { loaded.later(10000); loaded.dom.fireKind("interval"); settle(loaded); await tick(); }
  assert.equal(count(loaded, "/digest"), 3, "закрытая панель спрашивает сводку чаще раза в минуту");
  loaded.later(10000);
  settle(loaded);
  await tick();
  assert.equal(count(loaded, "/digest"), 4, "минута прошла — число у кнопки не обновилось");
  loaded.document.hidden = true;
  loaded.later(120000);
  settle(loaded);
  await tick();
  assert.equal(count(loaded, "/digest"), 4, "окно скрыто — запросов нет");
});

test("К-KO: «Запустить Workflow» — текст /kickoff в поле, как у 12а; набранное не затирается; 404 — пункта нет", async () => {
  const kickoff = () => Promise.resolve({ ok: true, text: async () => KICKOFF });
  const loaded = await page({ kickoff });
  await open(loaded);
  assert.deepEqual(acts(loaded), ["Запустить Workflow", "Отчёт", "Что происходит", "Настройки Пимпа"]);
  act(loaded, "kickoff");
  assert.equal(loaded.parts.editor.innerText, KICKOFF);
  assert.equal(loaded.api.status().workflow.result, "вставлено");
  assert.equal(shown(loaded), false, "команда выполнена — панель закрыта");
  // Поле с черновиком: текст запуска — перед ним, с пустой строкой.
  const draft = await page({ kickoff, text: "моя недописанная мысль" });
  await open(draft);
  act(draft, "kickoff");
  assert.equal(draft.parts.editor.innerText, `${KICKOFF}\n\nмоя недописанная мысль`);
  // Адреса нет (старое приложение: отказ без CORS) или текста нет — пункта нет.
  for (const none of [() => Promise.reject(new TypeError("Failed to fetch")), () => Promise.resolve({ ok: false, status: 404 }), () => Promise.resolve({ ok: true, text: async () => "  \n" })]) {
    const old = await page({ kickoff: none });
    await open(old);
    assert.deepEqual(acts(old), ["Отчёт", "Что происходит", "Настройки Пимпа"]);
  }
});

test("#9370: «Отчёт» и «Что происходит» — фраза в пустое поле, в непустое — с новой строки в конец; повтор — без дубля; не отправляет", async () => {
  const { inner } = loadInner();
  assert.equal(inner.RICK_REPORT_TEXT, "Рик, сделай отчёт по воркфлоу по правилам PMP");
  assert.equal(inner.PMP_ASK_TEXT, "Рик, что сейчас происходит и что висит из моих просьб — коротко, списком");
  for (const [name, phrase] of [["report", inner.RICK_REPORT_TEXT], ["ask", inner.PMP_ASK_TEXT]]) {
    const loaded = await page();
    await open(loaded);
    act(loaded, name);
    assert.equal(loaded.parts.editor.innerText, phrase, name);
    assert.equal(shown(loaded), false);
    await open(loaded);
    act(loaded, name);
    assert.equal(loaded.parts.editor.innerText, phrase, "вторая копия фразы");
    const draft = await page({ text: "уже пишу Рику" });
    await open(draft);
    act(draft, name);
    assert.equal(draft.parts.editor.innerText, `уже пишу Рику\n${phrase}`, "набранное затёрто");
    assert.equal(count(draft, "/panel"), 0);
  }
});

test("#9373: «Настройки Пимпа» — панель у часов прежним запросом /panel; панель страницы закрывается", async () => {
  const loaded = await page();
  await open(loaded);
  act(loaded, "settings");
  assert.equal(count(loaded, "/panel"), 1);
  assert.equal(shown(loaded), false);
  assert.deepEqual([pmp(loaded).clicks, pmp(loaded).last], [1, `${PORT}/panel`]);
});

test("#9373: у кнопки — «▶N», сколько Workflow идёт; нет идущих — знака нет и кнопка прежней ширины", async () => {
  const loaded = await page();
  const [, , run] = button(loaded).children;
  assert.equal(run.textContent, "▶2");
  assert.equal(button(loaded).style.getPropertyValue("width"), `${24 + 11 + 6}px`);
  assert.equal(button(loaded).title, "Workflow и терминалы · 2 идут");
  assert.equal(loaded.parts.left.getAttribute("data-myclaude-gallery-room"), `${6 + 41 + 6}px`, "месту в строке не дали ширину знака");
  assert.equal(pmp(loaded).running, 2);
  const calm = await page({ digest: okJson({ v: 1, projects: [] }) });
  assert.equal(button(calm).children[2].textContent, "");
  assert.equal(button(calm).style.getPropertyValue("width"), "24px");
  assert.equal(button(calm).title, "Workflow и терминалы");
});

test("вид: панель уступает меню Claude и выдвинутому списку слева; плашка — волосок и серая подложка, как у свёрток", () => {
  const { inner } = loadInner();
  const css = plain(inner.RULES).join("\n");
  assert.match(css, /body:has\(\[role="menu"\][^{]*\) :is\([^)]*#myclaude-pmp-panel[^)]*\)\{visibility:hidden!important\}/);
  assert.match(css, /data-hovering\]\) :is\([^)]*#myclaude-pmp-panel\)\{visibility:hidden !important\}/);
  assert.match(css, /#myclaude-pmp-panel \[data-k="plate"\]>div>div\{[^}]*border-left:1\.5px solid [^;]+;[^}]*background:rgba\(127,127,127,\.12\)/);
  assert.match(css, /#myclaude-pmp-panel \[data-k="plate"\]\{display:grid;grid-template-rows:0fr;transition:grid-template-rows/);
  assert.match(css, /#myclaude-pmp-panel \[data-k="caps"\]>i\[data-state="wait"\]\{background:transparent;box-shadow:inset 0 0 0 1\.5px var\(--R\)\}/);
  assert.match(css, /#myclaude-pmp-panel\[data-narrow="true"\] \[data-k="caps"\]\{order:3;flex:0 0 100%/);
});

// WF226 (снимок Элвиса 10.10, замер живого окна 889×514): поле стояло колонкой справа во всю высоту
// окна (верх поля — 41), панель висела над ним с высотой «не меньше 96» — ушла под верх окна, а
// команды в три строки (106) выпали под её рамку.
const inWindow = loaded => {
  const style = panel(loaded).style;
  const num = name => Number(style.getPropertyValue(name).replace("px", ""));
  const bottom = loaded.win.innerHeight - num("bottom");
  return { left: num("left"), right: num("left") + num("width"), top: bottom - num("max-height"), bottom, width: num("width") };
};

test("WF226: над полем места нет (поле колонкой во всю высоту окна) — панель сбоку от поля, целиком в окне", async () => {
  const loaded = await page({ viewport: { width: 889, height: 514 }, left: 603, width: 261, top: 41 });
  const field = loaded.parts.shell.rect = { left: 603, top: 41, width: 261, height: 438 };
  await open(loaded);
  const box = inWindow(loaded);
  assert.equal(box.right, 603 - 6, "не слева от поля, вплотную к нему");
  assert.equal(box.width, 480, "сбоку места на всю ширину панели — она не узкая");
  assert.equal(panel(loaded).dataset.narrow, "false");
  assert.equal(box.bottom, Math.min(field.top + field.height, 514 - 8), "низ — по нижней грани поля");
  assert.ok(box.top >= 8 && box.bottom <= 514 - 8 && box.left >= 8, `панель вышла за окно: ${JSON.stringify(box)}`);
  assert.equal(box.bottom - box.top, 360, "высота — до 70 % окна, как над полем");
  // Слева тесно, справа свободно — панель справа от поля.
  const right = await page({ viewport: { width: 889, height: 514 }, left: 20, width: 261, top: 41 });
  await open(right);
  assert.equal(inWindow(right).left, 20 + 261 + 6);
  assert.ok(inWindow(right).right <= 889 - 8);
});

test("WF226: низкое окно без места сбоку — панель над кнопкой, не выше окна; команды меряются в своей ширине", async () => {
  // Над полем 140 − 14 = 126: командам в одну строку (46) и телу (72) хватает — панель над полем, как всегда.
  const loaded = await page({ viewport: { width: 280, height: 300 }, left: 5, width: 270, top: 140 });
  await open(loaded);
  const nav = panel(loaded).children[1];
  nav.rect = { left: 6, top: 0, width: 268, height: 46 };
  settle(loaded);
  assert.equal(inWindow(loaded).bottom, 140 - 6, "места над полем хватает — панель над полем");
  assert.equal(inWindow(loaded).top, 8);
  // Команды переносятся в три строки (106): над полем им и телу тесно — панель над кнопкой, поверх поля.
  nav.rect = { left: 6, top: 0, width: 268, height: 106 };
  settle(loaded);
  const spot = Number(button(loaded).style.getPropertyValue("top").replace("px", ""));
  const box = inWindow(loaded);
  assert.equal(box.bottom, spot - 6, "низ панели — над кнопкой: кнопка и нижняя строка видны");
  assert.ok(box.top >= 8, `панель ушла под верх окна: ${JSON.stringify(box)}`);
  assert.ok(box.bottom - box.top >= 106 + 72, "командам в три строки и телу места хватает");
  // Совсем низкое окно: высота — сколько есть, нижней границы «не меньше 96» больше нет.
  const tiny = await page({ viewport: { width: 280, height: 150 }, left: 5, width: 270, top: 20 });
  await open(tiny);
  const low = inWindow(tiny);
  assert.ok(low.top >= 8 && low.bottom <= 150, `панель вышла за окно: ${JSON.stringify(low)}`);
});

test("WF226: команды не выпадают из рамки — сжимается тело, команды прокручиваются последними", () => {
  const { inner } = loadInner();
  const css = plain(inner.RULES).join("\n");
  assert.match(css, /#myclaude-pmp-panel>div\{flex:1 9999 auto;min-height:0;overflow-y:auto/, "тело обязано сжиматься раньше команд");
  assert.match(css, /#myclaude-pmp-panel>nav\{flex:0 1 auto;min-height:0;overflow-y:auto/, "команды без сжатия выпадают под рамку низкой панели");
});

test("узкое окно 280 — панель во всю ширину поля, квадратики под именем; поле свёрнуто — над кнопкой; dispose — узла нет", async () => {
  const loaded = await page({ viewport: { width: 280, height: 700 }, left: 5, width: 270, top: 500 });
  await open(loaded);
  const style = panel(loaded).style;
  assert.deepEqual([style.getPropertyValue("left"), style.getPropertyValue("width")], ["5px", "270px"]);
  assert.equal(panel(loaded).dataset.narrow, "true");
  assert.equal(style.getPropertyValue("bottom"), `${700 - 500 + 6}px`);
  assert.equal(style.getPropertyValue("max-height"), `${500 - 14}px`, "выше места над полем панель не растёт");
  // Поле свёрнуто: кнопка у кружка, панель — над ней.
  loaded.api.setStage(loaded.api.stages.COLLAPSED);
  settle(loaded);
  assert.equal(button(loaded).dataset.spot, "ring");
  assert.equal(shown(loaded), true);
  assert.equal(style.getPropertyValue("bottom"), `${700 - Number(button(loaded).style.getPropertyValue("top").replace("px", "")) + 6}px`);
  loaded.api.dispose();
  assert.equal(loaded.dom.query(PANEL), null);
  assert.equal(loaded.inner.pmpPanel.open, false);
});
