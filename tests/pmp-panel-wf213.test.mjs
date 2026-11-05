// WF213 (#9370–#9373, #9405; раздел 12п³ inject.js): панель оркестрации на кнопке PMP.
//
// Что проверяется (карточка WF213, контракты К-DG и К-KO; блок Workflow — лист 48 · 1.2, WF248 П2):
//   1) чистая часть — разбор /digest в модель панели: проекты блока Workflow (только группа «идут»),
//      слова блока («Идут 7», «Идут 7 Workflow · 4 проекта», «2/3 · 1 идёт»), сколько проектов входит в строку,
//      проценты из шагов, счёт терминалов, работа без новых полей (старое приложение); «Ждут тебя» снят (#9520);
//   2) открытие и закрытие — кнопка, повторное нажатие, Esc, клик мимо; опрос, пока открыта;
//   3) вид каждого состояния — загрузка, данные, пусто, приложение не отвечает;
//   4) команды — три главные с подписями (#9552): «Запустить Workflow» (GET /kickoff; 404 — подпись «Нужен PMP у
//      часов»), «Всё в одном чате» (GET /one-chat), «Сэкономить подписку» (#9547); ниже мелкие «Отчёт», «Что
//      происходит» (в пустое и непустое поле, набранное не затирается), «Настройки Пимпа» (GET /panel);
//   5) число «▶N» у кнопки и редкий запрос ради него там, где блока Рика нет;
//   6) status().pmp — open, rows, flowsOpen, terminals, running, lastError;
//   7) блок «Идёт Workflow» одной строкой: свёрнут — «Идут 2 · PimpM 2/5 · PimpV 0/1», не влезло — «+N»;
//      нажал — список по проектам, ещё раз — свернул; проектов нет — «Тихо» без нажатия.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";
import { chin, settle } from "./stands.mjs";

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

test("К-DG: /digest → модель панели — проекты блока Workflow, итог, терминалы", () => {
  const { inner } = loadInner();
  const model = plain(inner.pmpModel(DIGEST, NOW));
  // Итог — по проектам, где сейчас идёт (группа «идут»): давно молчащий и ждущий проекты в блок не идут.
  assert.deepEqual([model.projects, model.flows, model.done, model.running], [2, 6, 2, 2]);
  assert.deepEqual(model.rows.map(row => [row.name, row.done, row.total, row.running, row.failed, row.waiting, row.about]),
    [["PimpM", 2, 5, 1, 1, 0, "панель оркестрации"], ["PimpV", 0, 1, 1, 0, 0, "архив вместо «закрыть»"]]);
  assert.equal(model.rows[0].title, "PimpMyClaude");
  assert.equal("quiet" in model, false, "«Тихо · N» с давно молчащими снят вместе с квадратиками (лист 48 · 1.2)");
  assert.equal("cells" in model.rows[0], false, "квадратиков на Workflow больше нет");
  // Терминалы — проекты с terminal: true; что делает — «Сейчас», нет её — «о чём» идущего, нет ничего — имя.
  assert.equal(model.known, true);
  assert.deepEqual(model.terminals.map(item => [item.name, item.text]), [["PimpM", "идёт панель на кнопке PMP."], ["PimpV", "архив вместо «закрыть»"], ["Bambubek", ""]]);
  assert.deepEqual(model.terminals[0].flows, [{ n: 3, about: "панель оркестрации", steps: { done: 2, total: 4, percent: 50 }, when: "закончит в 04:30 · идёт 20 мин", role: "кодинг" }]);
  assert.equal(model.terminals[0].wait, "файл 37 — четыре вопроса.");
  assert.deepEqual(model.terminals[2].flows, []);
  assert.equal("waits" in model, false, "«Ждут тебя» снят (#9520): списка в модели нет");
});

// Слова блока — те же, что у панели у часов (PanelTiles.nowHead / nowOpenHead / ringWords, WF258).
test("лист 48 · 1.2: слова блока — «Идут 2», «Идут 2 Workflow · 2 проекта», «2/5 · 1 идёт»; идущих нет — «Workflow», проектов нет — «Тихо»", () => {
  const { inner } = loadInner();
  const model = inner.pmpModel(DIGEST, NOW);
  assert.equal(inner.pmpFlowsHead(model), "Идут 2");
  assert.equal(inner.pmpFlowsOpenHead(model), "Идут 2 Workflow · 2 проекта");
  const one = inner.pmpModel({ projects: [{ name: "A", title: "A", group: "идут", workflows: [flow(1, "идёт"), flow(2, "готово")] }] }, NOW);
  assert.deepEqual([inner.pmpFlowsHead(one), inner.pmpFlowsOpenHead(one)], ["Идёт 1", "Идёт 1 Workflow · 1 проект"]);
  const stopped = inner.pmpModel({ projects: [{ name: "A", title: "A", group: "идут", workflows: [flow(1, "упал")] }] }, NOW);
  assert.deepEqual([inner.pmpFlowsHead(stopped), inner.pmpFlowsOpenHead(stopped)], ["Workflow", "Workflow · 1 проект"]);
  const none = inner.pmpModel({ projects: [] }, NOW);
  assert.deepEqual([inner.pmpFlowsHead(none), inner.pmpFlowsOpenHead(none), inner.pmpFlowsHelp(none)], ["Тихо", "Workflow", "Workflow сейчас не идут"]);
  const words = row => plain(inner.pmpFlowsWords({ done: 0, total: 3, running: 0, failed: 0, waiting: 0, ...row }));
  assert.deepEqual(words({ running: 3 }), { text: "3 идут", fail: false });
  assert.deepEqual(words({ running: 1, failed: 1 }), { text: "1 идёт", fail: false });
  assert.deepEqual(words({ failed: 1 }), { text: "упал", fail: true });
  assert.deepEqual(words({ waiting: 1 }), { text: "ждёт", fail: false });
  assert.deepEqual(words({ done: 3 }), { text: "готово", fail: false });
  assert.deepEqual(words({ done: 1 }), { text: "", fail: false });
  assert.equal(inner.pmpFlowsHelp(model), "Идут 2 Workflow · 2 проекта\nPimpMyClaude: готово 2 из 5, 1 идёт — панель оркестрации\nPimpViewer: готово 0 из 1, 1 идёт — архив вместо «закрыть»");
});

// Пять проектов по «Alpha 0/1»: стенд меряет 0,6 кегля на знак (tests/dom.mjs) — 7,2 на знак шрифта 12.
const FIVE = ["Alpha", "Bravo", "Charl", "Delta", "Echoo", "Foxtr"];
const many = (names = FIVE) => ({ v: 1, at: DIGEST.at, projects: names.map(name => ({ name, title: name, group: "идут", terminal: false, workflows: [flow(1, "идёт")] })) });
test("лист 48 · 1.2: сколько проектов входит в строку — целиком, за ними «+N» (его место тоже считается), без многоточия", () => {
  const { inner } = loadInner();
  const model = inner.pmpModel(many(), NOW);
  // «Идут 6» — 43,2; « · Alpha» + « 0/1» — 86,4; « · +2» — 36.
  assert.equal(inner.pmpFlowsFit(model, 1000), 6, "всё входит — «+N» нет");
  assert.equal(inner.pmpFlowsFit(model, 452), 4, "43,2 + 4 × 86,4 + 36 = 424,8 ≤ 452; пятый с «+1» — 511");
  assert.equal(inner.pmpFlowsFit(model, 242), 1);
  assert.equal(inner.pmpFlowsFit(model, 60), 0, "ни один не входит — одна шапка и «+6»");
});

test("К-DG: старое приложение (новых полей нет) — «кто что делает» по группе «идут», остальное как было", () => {
  const { inner } = loadInner();
  const model = plain(inner.pmpModel(OLD, NOW));
  assert.equal(model.known, false);
  assert.deepEqual([model.projects, model.flows, model.done, model.running], [2, 6, 2, 2]);
  assert.deepEqual(model.terminals.map(item => [item.name, item.text, item.wait]), [["PimpM", "панель оркестрации", ""], ["PimpV", "архив вместо «закрыть»", ""]]);
  assert.deepEqual(plain(model.terminals[0].flows[0]), { n: 3, about: "панель оркестрации", steps: { done: 2, total: 4, percent: 50 }, when: "", role: "" });
  // Имена: два проекта с одним коротким именем — с буквой второй части; три, где и так совпало, — целиком;
  // разметка сводки («**важно**») на экран не идёт.
  const names = list => plain(inner.pmpModel({ projects: list.map(title => ({ name: title, title, group: "идут", terminal: true, now: "чат на **Opus** — `сборка`", workflows: [flow(1, "идёт")] })) }, NOW)).terminals;
  assert.deepEqual(names(["PimpMyClaude", "PimpViewer", "Dictator"]).map(item => item.name), ["PimpM", "PimpV", "Dictator"]);
  assert.deepEqual(names(["PimpMyClaude", "PimpViewer", "PimpMyTV"]).map(item => item.name), ["PimpMyClaude", "PimpViewer", "PimpMyTV"]);
  assert.equal(names(["A"])[0].text, "чат на Opus — сборка");
  // Мусор вместо ответа — пустая модель, без падения.
  for (const junk of [null, {}, { projects: "нет" }, { projects: [null, 5, "x"] }]) {
    const empty = plain(inner.pmpModel(junk, NOW));
    assert.deepEqual([empty.rows, empty.terminals, empty.running], [[], [], 0]);
  }
});

// ---- страница --------------------------------------------------------------
const tick = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };
const okJson = body => () => Promise.resolve({ ok: true, json: async () => body });
// Окно стенда: поле left…left+width с верхом top, под ним нижняя строка с группой «+» и кнопкой модели.
const page = async ({ cwd = "/Users/dev/Projects/Trelvis", digest = okJson(DIGEST), kickoff = () => Promise.resolve({ ok: false, status: 404 }), panel = () => Promise.resolve({ ok: true }), oneChat = () => Promise.resolve({ ok: true }), text = "",
  viewport = { width: 1200, height: 800 }, left = 100, width = 1000, top = 600 } = {}) => {
  const loaded = loadInject({
    title: "Чат", href: `https://claude.ai/epitaxy/${CHAT}`, geometry: { viewport },
    html: dom => {
      const parts = dom.composer({ top, left, width, text });
      chin(parts, { left, top, width });
      const side = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
      const item = side.add("div", { attrs: { "data-row-key": `code:${CHAT}` } });
      item.__reactFiber$test = { memoizedProps: { session: { ref: { id: CHAT }, source: { data: { cwd } } } }, return: null };
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  // Часы стенда — на время сводки (NOW): данные 10.10 не стареют вместе с настоящими часами (ревизия WF247).
  loaded.run(`{ const real = Date.now, start = real(); Date.now = () => ${NOW} + (real() - start); }`);
  loaded.calls = [];
  loaded.replies = { digest, kickoff, panel, "one-chat": oneChat };
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
// Команды панели: у главных (#9552) название — в <b>, под ним подпись.
const acts = loaded => all(loaded).filter(node => node.tagName === "BUTTON" && node.parentNode.tagName === "NAV")
  .map(node => (node.dataset.k === "main" ? node.children[0].textContent : node.textContent));
const note = (loaded, name) => all(loaded).find(node => node.dataset.k === "main" && node.dataset.act === name)?.children[1]?.textContent;
// Стаб событий не всплывает: слушатель панели получает нажатие с целью — нужным узлом.
const click = (loaded, target) => panel(loaded).dispatchEvent({ type: "click", detail: 1, target });
const act = (loaded, name) => click(loaded, all(loaded).find(node => node.tagName === "BUTTON" && node.dataset.act === name));
const count = (loaded, path) => loaded.calls.filter(item => item === path).length;
// Клавиши слушает общий слушатель окна (onKeyDown): он на захвате раньше всех слушателей document.
const key = (loaded, name, extra = {}) => loaded.win.dispatchEvent({ type: "keydown", key: name, ...extra });
const line = loaded => all(loaded).find(node => node.dataset.k === "line");
const shownItems = loaded => parts(loaded, "it").filter(node => node.style.getPropertyValue("display") !== "none").map(node => node.textContent);

// Лист 48 · 1.2 (слово Элвиса 17.10 00:37: «делай по рекомендациям»): блок «Идёт Workflow» вернулся одной
// строкой — как у панели у часов (WF258); «Ждут тебя» не вернулся.
test("лист 48 · 1.2: блок Workflow одной строкой «Идут 2 · PimpM 2/5 · PimpV 0/1»; нажал — список по проектам; ещё раз — свернул", async () => {
  const loaded = await page();
  await open(loaded);
  assert.equal(shown(loaded), true);
  const row = line(loaded);
  assert.equal(row.tagName, "BUTTON", "строка — настоящая кнопка: Tab, Enter и пробел");
  assert.equal(row.parentNode.dataset.k, "flows");
  assert.equal(row.textContent, "Идут 2 · PimpM 2/5 · PimpV 0/1");
  assert.equal(row.getAttribute("aria-expanded"), "false");
  assert.equal(row.title, "Идут 2 Workflow · 2 проекта\nPimpMyClaude: готово 2 из 5, 1 идёт — панель оркестрации\nPimpViewer: готово 0 из 1, 1 идёт — архив вместо «закрыть»");
  assert.deepEqual(parts(loaded, "more").map(node => node.textContent), [""], "всё вошло — «+N» нет");
  assert.deepEqual(heads(loaded), ["Работают 3 терминала"], "заголовка «Идёт Workflow сейчас» и строки итога больше нет");
  for (const gone of ["Идёт Workflow сейчас", "Ждут тебя", "Тихо", "▶1", "✕1"]) assert.equal(panel(loaded).textContent.includes(gone), false, gone);
  assert.equal(parts(loaded, "caps").length, 0, "квадратиков нет");
  assert.equal(pmp(loaded).flowsOpen, false);
  // Нажал — шапка «Идут 2 Workflow · 2 проекта», под ней строка на проект: имя, «2/5 · 1 идёт», о чём идущий.
  click(loaded, row);
  const open1 = line(loaded);
  assert.equal(open1.getAttribute("aria-expanded"), "true");
  assert.equal(open1.textContent, "Идут 2 Workflow · 2 проекта");
  assert.equal(open1.title, "Свернуть");
  const rows = parts(loaded, "row").filter(node => node.dataset.kind === "flow");
  assert.deepEqual(rows.map(node => [...node.children].map(child => child.textContent)),
    [["PimpM", "2/5 · 1 идётпанель оркестрации"], ["PimpV", "0/1 · 1 идётархив вместо «закрыть»"]]);
  assert.equal(rows[0].children[0].title, "PimpMyClaude", "полное имя — в подсказке");
  assert.equal(rows[0].style.getPropertyValue("--c"), "", "цвета проекта в блоке нет (лист 48, «Решено»)");
  assert.equal(pmp(loaded).flowsOpen, true);
  // Ещё раз — свернул; раскрытость живёт, пока жива страница: закрыл и открыл панель — список на месте.
  press(loaded);
  await open(loaded);
  assert.equal(line(loaded).getAttribute("aria-expanded"), "true");
  click(loaded, line(loaded));
  assert.equal(line(loaded).getAttribute("aria-expanded"), "false");
  assert.deepEqual(parts(loaded, "row").filter(node => node.dataset.kind === "flow"), []);
  // Знака «▶N» у кнопки нет (лист 48 · 1.2; счётчики у кнопок сняты, #9507) — число в строке блока.
  assert.equal(button(loaded).textContent, "PMP");
});

test("лист 48 · 1.2: не влезло — проекты прячутся с конца, за видимыми «+N»; окно сузили — перемерено", async () => {
  const loaded = await page({ digest: okJson(many()) });
  await open(loaded);
  assert.equal(panel(loaded).style.getPropertyValue("width"), "480px");
  assert.deepEqual(shownItems(loaded), [" · Alpha 0/1", " · Bravo 0/1", " · Charl 0/1", " · Delta 0/1"]);
  assert.deepEqual(parts(loaded, "more").map(node => node.textContent), [" · +2"]);
  assert.equal(line(loaded).title.split("\n").length, 7, "в подсказке — все шесть проектов");
  // Окно сузили до 280: поле 270 — панель 270, в строку входит один проект.
  loaded.win.innerWidth = 280;
  loaded.parts.shell.rect = { left: 5, top: 600, width: 270, height: 140 };
  settle(loaded);
  assert.equal(panel(loaded).style.getPropertyValue("width"), "270px");
  assert.deepEqual(shownItems(loaded), [" · Alpha 0/1"]);
  assert.deepEqual(parts(loaded, "more").map(node => node.textContent), [" · +5"]);
});

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
  // Блок «Идёт Workflow» виден (лист 48 · 1.2): два проекта, идут два Workflow.
  assert.deepEqual(pmp(loaded), { button: true, clicks: 0, last: null, state: null, open: true, rows: 2, flowsOpen: false, terminals: 3, running: 2, lastError: null });
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
  // Терминал, которому раскрывать нечего (идущих Workflow нет, «Ждёт тебя» нет), — строка с data-flat.
  const quiet = { name: "Quiet", title: "Quiet", group: "тихо", color: "#336699", terminal: true, now: "читаю отчёт", workflows: [] };
  const loaded = await page({ digest: okJson({ ...DIGEST, projects: [...DIGEST.projects, quiet] }) });
  button(loaded).dispatchEvent({ type: "keydown", key: "Enter" });
  await tick();
  assert.equal(shown(loaded), true);
  // Строки, которым нечего раскрывать (текст виден целиком), Tab не берёт — у них метка data-flat.
  const items = all(loaded).filter(node => node.tagName === "BUTTON" && node.dataset.flat !== "true");
  assert.ok(items.length >= 5, "пункты панели — настоящие кнопки");
  const flat = parts(loaded, "row").filter(node => node.dataset.flat === "true");
  assert.deepEqual(flat.map(node => node.textContent), ["Quietчитаю отчёт"], "стенд: текст влезает — стрелки и нажатия нет");
  click(loaded, flat[0]);
  assert.equal(flat[0].getAttribute("aria-expanded"), "false");
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

test("#9405, #9371: живые данные — строка Workflow, терминалы с плашкой; «Ждут тебя» нет", async () => {
  const loaded = await page();
  await open(loaded);
  assert.equal(panel(loaded).dataset.state, "ok");
  assert.deepEqual(heads(loaded), ["Работают 3 терминала"], "блока «Ждут тебя» нет (#9520)");
  assert.ok(!panel(loaded).textContent.includes("марафон"), "слово «марафон» не пишем");
  assert.equal(line(loaded).textContent, "Идут 2 · PimpM 2/5 · PimpV 0/1");
  // Терминалы: строка «имя — что делает»; есть что раскрыть — кнопка; без сведений — просто имя.
  const terms = parts(loaded, "row").filter(node => node.dataset.kind === "term");
  assert.deepEqual(terms.map(node => [node.tagName, node.textContent]), [["BUTTON", "PimpMидёт панель на кнопке PMP."], ["BUTTON", "PimpVархив вместо «закрыть»"], ["DIV", "Bambubek"]]);
  assert.equal(terms[0].style.getPropertyValue("--c"), "#ff2d55", "имя терминала — цветом проекта, как было");
  const plate = terms[0].nextElementSibling;
  assert.deepEqual([terms[0].getAttribute("aria-expanded"), plate.dataset.k, plate.dataset.open], ["false", "plate", "false"]);
  click(loaded, terms[0].children[1]);
  assert.deepEqual([terms[0].getAttribute("aria-expanded"), plate.dataset.open], ["true", "true"], "нажатие по строке плашку не выдвинуло");
  assert.equal(plate.textContent, "панель оркестрациикодинг · шаги 2 из 4 · 50 % · закончит в 04:30 · идёт 20 минЖдёт тебя: файл 37 — четыре вопроса.");
  assert.equal(all(loaded).find(node => node.dataset.k === "bar").style.getPropertyValue("--p"), "50%");
  for (const word of ["агент", "гейт", "батч", "Opus", "wf209"]) assert.ok(!plate.textContent.includes(word), word);
  click(loaded, terms[0]);
  assert.deepEqual([terms[0].getAttribute("aria-expanded"), plate.dataset.open], ["false", "false"], "повторное нажатие не задвинуло");
  assert.deepEqual(parts(loaded, "row").filter(node => node.dataset.kind === "wait"), [], "строк «Ждут тебя» нет");
  assert.deepEqual(acts(loaded), ["Запустить Workflow", "Всё в одном чате", "Сэкономить подписку", "Отчёт", "Что происходит", "Настройки PMP"], "текста запуска нет (404) — «Запустить Workflow» всё равно видна (#9552)");
});

test("#9371: старое приложение — заголовок «Кто что делает», строки по группе «идут»", async () => {
  const loaded = await page({ digest: okJson(OLD) });
  await open(loaded);
  assert.deepEqual(heads(loaded), ["Кто что делает"]);
  assert.equal(line(loaded).textContent, "Идут 2 · PimpM 2/5 · PimpV 0/1", "блок Workflow старому приложению тот же");
  assert.deepEqual(parts(loaded, "row").filter(node => node.dataset.kind === "term").map(node => node.textContent), ["PimpMпанель оркестрации", "PimpVархив вместо «закрыть»"]);
});

test("состояния: загрузка — «Смотрю, что идёт…»; пусто — «Сейчас ничего не идёт»; приложение молчит — одна строка и только команды, которым оно не нужно", async () => {
  // Загрузка: первый ответ ещё не пришёл.
  const slow = await page({ digest: () => new Promise(() => {}) });
  await open(slow);
  assert.equal(panel(slow).dataset.state, "load");
  assert.deepEqual(parts(slow, "note").map(node => node.textContent), ["Смотрю, что идёт…"]);
  assert.deepEqual(acts(slow), ["Запустить Workflow", "Всё в одном чате", "Сэкономить подписку", "Отчёт", "Что происходит", "Настройки PMP"]);
  // Тишина дольше срока опроса — приложение не отвечает.
  slow.later(10000);
  slow.dom.fireKind("interval");
  assert.equal(panel(slow).dataset.state, "error");
  assert.equal(pmp(slow).lastError, "PMP у часов не отвечает");
  // Пусто: идущих проектов нет — «Тихо» без нажатия; терминалы спросили — их нет.
  const empty = await page({ digest: okJson({ v: 1, at: DIGEST.at, projects: [{ name: "A", title: "A", group: "тихо", color: "#112233", terminal: false, workflows: [flow(1, "готово")] }] }) });
  await open(empty);
  assert.deepEqual(heads(empty), ["Тихо", "Терминалы сейчас не работают"]);
  assert.equal(all(empty).find(node => node.tagName === "H3").title, "Workflow сейчас не идут");
  assert.equal(line(empty), undefined, "нажимать нечего");
  assert.deepEqual(parts(empty, "note").map(node => node.textContent), []);
  assert.deepEqual(pmp(empty), { button: true, clicks: 0, last: null, state: null, open: true, rows: 0, flowsOpen: false, terminals: 0, running: 0, lastError: null });
  // Ошибка: отказ сети и ответ не 200.
  for (const digest of [() => Promise.reject(new Error("net")), () => Promise.resolve({ ok: false, status: 500 })]) {
    const down = await page({ digest, kickoff: () => Promise.resolve({ ok: true, text: async () => KICKOFF }) });
    await open(down);
    assert.equal(panel(down).dataset.state, "error");
    assert.deepEqual(parts(down, "note").map(node => node.textContent), ["PMP у часов не отвечает"]);
    assert.deepEqual(heads(down), []);
    assert.deepEqual(acts(down), ["Запустить Workflow", "Всё в одном чате", "Сэкономить подписку", "Отчёт", "Что происходит"], "три главные видны и без приложения; «Настройки PMP» — нет");
    assert.equal(pmp(down).lastError, "PMP у часов не отвечает");
    // Приложение вернулось — следующий опрос возвращает вид.
    down.replies.digest = okJson(DIGEST);
    down.later(10000);
    down.dom.fireKind("interval");
    await tick();
    assert.equal(panel(down).dataset.state, "ok");
    assert.equal(pmp(down).lastError, null);
    assert.deepEqual(acts(down), ["Запустить Workflow", "Всё в одном чате", "Сэкономить подписку", "Отчёт", "Что происходит", "Настройки PMP"]);
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

test("К-KO: «Запустить Workflow» — текст /kickoff в поле, как у 12а; набранное не затирается; текста нет — кнопка видна, подпись «Нужен PMP у часов» (#9552)", async () => {
  const kickoff = () => Promise.resolve({ ok: true, text: async () => KICKOFF });
  const loaded = await page({ kickoff });
  await open(loaded);
  assert.deepEqual(acts(loaded), ["Запустить Workflow", "Всё в одном чате", "Сэкономить подписку", "Отчёт", "Что происходит", "Настройки PMP"]);
  assert.equal(note(loaded, "kickoff"), "Большую задачу делит на шаги и раздаёт агентам; ты видишь ход в панели");
  act(loaded, "kickoff");
  assert.equal(loaded.parts.editor.innerText, KICKOFF);
  assert.equal(loaded.api.status().workflow.result, "вставлено");
  assert.equal(shown(loaded), false, "команда выполнена — панель закрыта");
  // Поле с черновиком: текст запуска — перед ним, с пустой строкой.
  const draft = await page({ kickoff, text: "моя недописанная мысль" });
  await open(draft);
  act(draft, "kickoff");
  assert.equal(draft.parts.editor.innerText, `${KICKOFF}\n\nмоя недописанная мысль`);
  // Адреса нет (старое приложение: отказ без CORS) или текста нет — кнопка видна, подпись честная; нажатие — та же
  // подсказка над кнопкой PMP, поле не тронуто (и черновик в нём).
  for (const none of [() => Promise.reject(new TypeError("Failed to fetch")), () => Promise.resolve({ ok: false, status: 404 }), () => Promise.resolve({ ok: true, text: async () => "  \n" })]) {
    const old = await page({ kickoff: none, text: "черновик" });
    await open(old);
    assert.deepEqual(acts(old), ["Запустить Workflow", "Всё в одном чате", "Сэкономить подписку", "Отчёт", "Что происходит", "Настройки PMP"]);
    assert.equal(note(old, "kickoff"), "Нужен PMP у часов");
    act(old, "kickoff");
    assert.equal(old.parts.editor.innerText, "черновик", "поле тронуто");
    assert.equal(shown(old), false);
    assert.equal(old.dom.query("#myclaude-mic-hint")?.textContent, "Нужен PMP у часов");
    assert.equal(old.api.status().workflow.runs, 0);
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

// #9547 (слово Элвиса: «сократить расход токенов, и чтобы промт вставлялся… в поле ввода»): промпт-исследование —
// в поле как есть, как «Отчёт»: в конец с новой строки, черновик остаётся, Enter жмёт человек.
test("#9547: «Сэкономить подписку» (до #9552 — «Сократить расход») — промпт целиком в поле, не отправляет; черновик остаётся; повтор — без второй копии; поля нет — подсказка", async () => {
  const { inner } = loadInner();
  const SAVE = inner.PMP_SAVE_TEXT;
  assert.ok(SAVE.startsWith("Посчитай, куда уходит моя подписка Claude (токены), и скажи, как тратить её медленнее при той же отдаче.\n\n"));
  assert.ok(SAVE.endsWith("В чат — 5–7 строк: три главные цифры, три лучших способа, насколько точны оценки и путь к файлу."));
  for (const part of ["## Откуда брать цифры", "## Что посчитать", "## Что выдать", "`~/.claude/projects/<проект>/<чат>.jsonl`",
    "5. Файлы правил — обязательно.", "`message.usage` (`input_tokens`"]) assert.ok(SAVE.includes(part), part);
  assert.equal(SAVE.split("`").length - 1, 72, "обратные кавычки текста целы");
  assert.equal(SAVE.length, 4843);
  // Пустое поле — текст целиком; панель закрыта; панель у часов не звали.
  const loaded = await page();
  await open(loaded);
  const button = all(loaded).find(node => node.tagName === "BUTTON" && node.dataset.act === "save");
  assert.equal(button.title, "Вставить в поле промпт: где уходит подписка и как тратить медленнее (отправишь сам)");
  act(loaded, "save");
  assert.equal(loaded.parts.editor.innerText, SAVE);
  assert.equal(shown(loaded), false, "команда выполнена — панель закрыта");
  assert.equal(count(loaded, "/panel"), 0);
  assert.equal(loaded.api.status().workflow.result, null, "не путь «Запустить Workflow»");
  // Повтор — промпт уже в конце поля: второй копии нет.
  await open(loaded);
  act(loaded, "save");
  assert.equal(loaded.parts.editor.innerText, SAVE, "вторая копия промпта");
  // Редактор переписал разметку («## » стал заголовком, переносы — по-своему): повтор всё равно без копии.
  const rewritten = SAVE.replace(/^## /gmu, "").replace(/\n\n/gu, "\n");
  loaded.parts.editor.innerText = rewritten;
  await open(loaded);
  act(loaded, "save");
  assert.equal(loaded.parts.editor.innerText, rewritten, "переписанное поле — вторая копия");
  // Черновик человека — остаётся, промпт с новой строки в конце.
  const draft = await page({ text: "моя недописанная мысль" });
  await open(draft);
  act(draft, "save");
  assert.equal(draft.parts.editor.innerText, `моя недописанная мысль\n${SAVE}`, "набранное затёрто");
  // Старая копия далеко выше длинного черновика — не мешает вставить новую в конец.
  const long = `${SAVE}\n${"слово ".repeat(200)}`;
  const far = await page({ text: long });
  await open(far);
  act(far, "save");
  assert.equal(far.parts.editor.innerText, `${long}\n${SAVE}`);
  // Поля нет — подсказка у кнопки PMP, ошибки нет.
  const gone = await page();
  await open(gone);
  gone.parts.editor.remove();
  assert.doesNotThrow(() => act(gone, "save"));
  assert.equal(shown(gone), false);
  assert.equal(gone.dom.query("#myclaude-mic-hint")?.textContent, "Не вышло вставить в поле ввода");
});

// #9552 (слово Элвиса: «Запустить Work Flow… понятно людям объясняться… общаться в одном чате, все проекты…
// сэкономить подписку»): три главные кнопки с объяснением под названием, ниже строкой мелкие.
test("#9552: три главные кнопки с подписями — порядок и тексты ТЗ дословно; ниже мелкие «Отчёт», «Что происходит», «Настройки PMP»; «Пимп» не пишем", async () => {
  const { inner } = loadInner();
  assert.deepEqual(plain(inner.PMP_MAIN).map(item => [item.act, item.name, item.note]), [
    ["kickoff", "Запустить Workflow", "Большую задачу делит на шаги и раздаёт агентам; ты видишь ход в панели"],
    ["one", "Всё в одном чате", "Один главный чат ведёт все проекты и сам раздаёт работу — меньше окон, подписка тратится почти так же"],
    ["save", "Сэкономить подписку", "Разберёт твои журналы и даст личные советы"],
  ]);
  const loaded = await page({ kickoff: () => Promise.resolve({ ok: true, text: async () => KICKOFF }) });
  await open(loaded);
  const nav = panel(loaded).children[1];
  assert.equal(nav.tagName, "NAV");
  const buttons = [...nav.children];
  assert.deepEqual(buttons.map(node => [node.tagName, node.dataset.k, node.dataset.act]), [
    ["BUTTON", "main", "kickoff"], ["BUTTON", "main", "one"], ["BUTTON", "main", "save"],
    ["BUTTON", "small", "report"], ["BUTTON", "small", "ask"], ["BUTTON", "small", "settings"],
  ], "кнопки — прямые дети строки команд: главные сверху, мелкие ниже");
  for (const [index, item] of plain(inner.PMP_MAIN).entries()) {
    const main = buttons[index];
    assert.deepEqual([...main.children].map(node => [node.tagName, node.textContent]), [["B", item.name], ["SPAN", item.note]], item.act);
    assert.equal(main.title, item.title);
  }
  assert.equal(buttons[2].title, "Вставить в поле промпт: где уходит подписка и как тратить медленнее (отправишь сам)");
  assert.deepEqual(buttons.slice(3).map(node => node.textContent), ["Отчёт", "Что происходит", "Настройки PMP"]);
  assert.equal(String(nav.textContent).includes("Пимп"), false, "в интерфейсе — PMP");
  // «Сэкономить подписку» — то же действие, что «Сократить расход» (#9547).
  act(loaded, "save");
  assert.equal(loaded.parts.editor.innerText, inner.PMP_SAVE_TEXT);
});

test("#9552: «Всё в одном чате» — GET /one-chat тем же путём, что «Настройки PMP»; приложение молчит — подсказка; ждём ответа — «Уже открываю»", async () => {
  const loaded = await page();
  await open(loaded);
  act(loaded, "one");
  assert.equal(shown(loaded), false, "панель закрыта");
  assert.deepEqual([count(loaded, "/one-chat"), count(loaded, "/panel")], [1, 0]);
  assert.deepEqual([pmp(loaded).clicks, pmp(loaded).last], [1, `${PORT}/one-chat`]);
  await tick();
  assert.equal(pmp(loaded).state, null, "ответ пришёл — вид кнопки обычный");
  assert.equal(loaded.parts.editor.innerText, "", "поле не тронуто");
  // Приложение не отвечает (или старое — адреса не знает, 404 без CORS): подсказка над кнопкой PMP.
  const down = await page({ oneChat: () => Promise.reject(new TypeError("Failed to fetch")) });
  await open(down);
  act(down, "one");
  await tick();
  assert.equal(pmp(down).state, "silent");
  assert.equal(down.dom.query("#myclaude-mic-hint")?.textContent, "PimpMyClaude не отвечает");
  // Первый запрос ещё ждёт ответа — второго нет, подсказка «Уже открываю».
  const slow = await page({ oneChat: () => new Promise(() => {}) });
  await open(slow);
  act(slow, "one");
  assert.equal(pmp(slow).state, "wait");
  await open(slow);
  act(slow, "one");
  assert.equal(count(slow, "/one-chat"), 1);
  assert.equal(shown(slow), false);
  assert.equal(slow.dom.query("#myclaude-mic-hint")?.textContent, "Уже открываю");
});

test("#9552: «Запустить Workflow» — ответа /kickoff ещё нет — подпись обычная; первый же 404 — «Нужен PMP у часов»; приложение молчит — три главные видны", async () => {
  let answer = null;
  const loaded = await page({ kickoff: () => new Promise(resolve => { answer = resolve; }) });
  await open(loaded);
  assert.equal(note(loaded, "kickoff"), "Большую задачу делит на шаги и раздаёт агентам; ты видишь ход в панели");
  // Первый ответ — 404: текста как не было, так и нет, но подпись обязана смениться.
  answer({ ok: false, status: 404 });
  await tick();
  assert.equal(note(loaded, "kickoff"), "Нужен PMP у часов");
  // Сводка не пришла и /kickoff молчит — главные кнопки на месте, «Настроек PMP» нет.
  const down = await page({ digest: () => Promise.reject(new Error("net")), kickoff: () => Promise.reject(new Error("net")) });
  await open(down);
  assert.equal(panel(down).dataset.state, "error");
  assert.deepEqual(acts(down), ["Запустить Workflow", "Всё в одном чате", "Сэкономить подписку", "Отчёт", "Что происходит"]);
  assert.equal(note(down, "kickoff"), "Нужен PMP у часов");
});

test("#9373: «Настройки Пимпа» — панель у часов прежним запросом /panel; панель страницы закрывается", async () => {
  const loaded = await page();
  await open(loaded);
  act(loaded, "settings");
  assert.equal(count(loaded, "/panel"), 1);
  assert.equal(shown(loaded), false);
  assert.deepEqual([pmp(loaded).clicks, pmp(loaded).last], [1, `${PORT}/panel`]);
});

test("#9373, лист 48 · 1.2: знака «▶N» у кнопки нет и ширина прежняя; сколько идёт — в подсказке и status().pmp.running", async () => {
  const loaded = await page();
  assert.equal(button(loaded).textContent, "PMP");
  assert.equal(button(loaded).children.length, 1, "#9507: узла под «▶N» нет");
  assert.equal(button(loaded).style.getPropertyValue("width"), "", "ширина — из листа стилей, от числа не растёт");
  assert.equal(button(loaded).title, "Workflow и терминалы · 2 идут");
  assert.equal(loaded.parts.left.getAttribute("data-myclaude-gallery-room"), `${6 + 24 + 6}px`, "место в строке — под кнопку без знака");
  assert.equal(pmp(loaded).running, 2);
  const calm = await page({ digest: okJson({ v: 1, projects: [] }) });
  assert.equal(button(calm).textContent, "PMP");
  assert.equal(button(calm).style.getPropertyValue("width"), "");
  assert.equal(button(calm).title, "Workflow и терминалы");
});

test("вид: панель уступает меню Claude и выдвинутому списку слева; плашка — волосок и серая подложка, как у свёрток; строка Workflow — без переноса и многоточия", () => {
  const { inner } = loadInner();
  const css = plain(inner.RULES).join("\n");
  assert.match(css, /body:has\(\[role="menu"\][^{]*\) :is\([^)]*#myclaude-pmp-panel[^)]*\)\{visibility:hidden!important\}/);
  assert.match(css, /data-hovering\]\) :is\([^)]*#myclaude-pmp-panel\)\{visibility:hidden !important\}/);
  assert.match(css, /#myclaude-pmp-panel \[data-k="plate"\]>div>div\{[^}]*border-left:1\.5px solid [^;]+;[^}]*background:rgba\(127,127,127,\.12\)/);
  assert.match(css, /#myclaude-pmp-panel \[data-k="plate"\]\{display:grid;grid-template-rows:0fr;transition:grid-template-rows/);
  assert.match(css, /#myclaude-pmp-panel \[data-k="ln"\]\{display:block;overflow:hidden;white-space:nowrap;text-overflow:clip\}/);
  assert.match(css, /#myclaude-pmp-panel button\[data-k="line"\]::before\{content:"▸"/);
  assert.match(css, /#myclaude-pmp-panel button\[data-k="line"\]\[aria-expanded="true"\]::before\{content:"▾"\}/);
  assert.match(css, /#myclaude-pmp-panel\[data-narrow="true"\] :is\(\[data-k="tx"\],\[data-k="fw"\]\)\{flex:0 0 100%\}/);
  assert.doesNotMatch(css, /myclaude-pmp-panel [^{]*(?:caps|data-quiet|"tip"|"sum")/, "правила квадратиков, «Тихо · N», подсказки и итога сняты");
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

// #9552: строка команд выросла (три кнопки с подписями и строка мелких) — правила вида и место панели.
const panelCss = loaded => String(loaded.dom.document.getElementById("myclaude-input-handle-style")?.textContent ?? "");
test("#9552: окно 380 — главные кнопки во всю ширину, с переносом подписи, панель целиком в окне; над полем 236 — панель сбоку от поля", async () => {
  const loaded = await page({ viewport: { width: 380, height: 800 }, left: 10, width: 360, top: 500 });
  await open(loaded);
  const box = inWindow(loaded);
  assert.equal(box.width, 360, "не шире поля");
  assert.ok(box.left >= 8 && box.right <= 380 - 8 && box.top >= 8, `панель вышла за окно: ${JSON.stringify(box)}`);
  const css = panelCss(loaded);
  assert.match(css, /#myclaude-pmp-panel>nav>button\[data-k="main"\]\{flex:0 0 100%;[^}]*white-space:normal/, "главная кнопка не во всю ширину или без переноса");
  assert.match(css, /#myclaude-pmp-panel>nav>button\[data-k="main"\]>span\{font:400 11px\/14px [^}]*white-space:normal/, "подпись не мелко или жирная, как «Запустить Workflow»");
  assert.match(css, /#myclaude-pmp-panel>nav>button\[data-k="small"\]\{min-height:22px;[^}]*font-size:11px/);
  const rules = plain(loaded.inner.RULES).join("\n");
  assert.ok(css.indexOf('button[data-k="main"]{') > css.indexOf(rules.slice(-40)), "правила главных кнопок — после общих (каскад)");
  // Поле ниже середины невысокого окна: над ним 236 — командам (~220) и телу тесно; сбоку места хватает — панель слева.
  const side = await page({ viewport: { width: 1000, height: 520 }, left: 500, width: 380, top: 250 });
  side.parts.shell.rect = { left: 500, top: 250, width: 380, height: 200 };
  await open(side);
  const at = inWindow(side);
  assert.equal(at.right, 500 - 6, "панель не сбоку от поля");
  assert.equal(at.bottom, 450, "низ — по нижней грани поля");
  assert.ok(at.top >= 8 && at.left >= 8, `панель вышла за окно: ${JSON.stringify(at)}`);
});

test("узкое окно 280 — панель во всю ширину поля; поле свёрнуто — над кнопкой; dispose — узла нет", async () => {
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

// Перенесено из rick-cells-off-wf239 (WF248): короткие имена — общий помощник панели (rickShortName).
test("WF183: короткие имена проектов — «Pimp», «Vkus»; одно короткое имя у двух — с буквой второй части", () => {
  const { inner } = loadInner();
  assert.deepEqual(["PimpMyClaude", "VkusnoffKz", "VkusnoffKz — ночь 09.10", "Dictator", "Trelvis", "Rick", "Rick voice", "Вкуснофф", "Проект1"].map(text => inner.rickShortName(text)),
    ["Pimp", "Vkus", "Vkus", "Dictator", "Trelvis", "Rick", "Rick", "Вкуснофф", "Проект1"]);
  assert.deepEqual(["PimpMyClaude", "PimpViewer", "Dictator"].map(text => inner.rickShortName(text, true)), ["PimpM", "PimpV", "Dictator"]);
});
