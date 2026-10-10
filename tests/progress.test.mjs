// Полоса прогресса воркфлоу (раздел 2б inject.js): разбор строки состояния из
// SkilZZZ/AGENTS.md, доли сегментов и сводка проектов для подсказки.
// Образцы строк взяты из самого AGENTS.md — формат меняется там, а не здесь.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";

const { inner } = loadInner({ title: "Trelvis" });
const parse = text => plain(inner.parseProgressText(text));
const badges = (info, avail) => plain(inner.progressBadges(info, avail));

test("образец из AGENTS.md: идёт, марафон и проценты", () => {
  const info = parse("💭🟣[Trelvis](docs/status.md) · WF 3 из 8 · 70%💭");
  assert.equal(info.wf, 3);
  assert.equal(info.of, 8);
  assert.equal(info.pct, 70);
  assert.equal(info.state, "run");
  assert.equal(info.project, "Trelvis", "имя вынимается из markdown-ссылки");
  assert.equal(info.total, 33.8, "доля марафона: два закрытых воркфлоу плюс 70 % третьего");
});

test("образец «готово»: без «WF» и без процентов", () => {
  const info = parse("✅⚪[PimpMyClaude](docs/status.md) · 4 из 4✅");
  assert.equal(info.state, "done");
  assert.equal(info.pct, 100);
  assert.equal(info.total, 100);
  assert.equal(info.project, "PimpMyClaude");
});

test("значки ✋ и 🛑 читаются как «жду» и «упал»", () => {
  assert.equal(parse("✋🟢[Dictatorik](audit/status.md) · WF 4 из 7 · 50%✋").state, "wait");
  assert.equal(parse("⚠️⚪[PimpMyClaude](docs/status.md) · WF 3 из 5 · жду⚠️").state, "wait",
    "⚠️ — тот же «жду» (правило AGENTS.md 08.09)");
  assert.equal(parse("🛑🔵[VkusnoffKz](audit/status.md) · WF 1 из 3 · 40%🛑").state, "fail");
});

test("одиночный воркфлоу: «WF N из M» опущено, значок с обоих краёв", () => {
  const info = parse("💭⚪Проект · 40%💭");
  assert.equal(info.wf, 1);
  assert.equal(info.of, 1);
  assert.equal(info.pct, 40);
  assert.equal(info.total, 40);
  assert.equal(info.project, "Проект");
  assert.equal(parse("💭⚪Проект · 40%"), null, "значок только слева — не строка состояния");
  assert.equal(parse("✅ покрытие 80%"), null, "фраза из ответа строкой состояния не становится");
});

test("«2 из 2» без значка строкой состояния не становится", () => {
  assert.equal(parse("шаги 2 из 2"), null);
  assert.equal(parse("- шаги 2 из 2\n- время 1 ч"), null);
  // Обратная сторона того же правила (хвост #5714, решено 08.09): со словом «WF»
  // строка принимается и БЕЗ значка. Значок здесь не пропуск, а уточнение: «WF»
  // пишем только мы, а берётся последнее совпадение — настоящая строка состояния
  // в конце ответа перебивает случайное упоминание выше по тексту.
  assert.equal(parse("WF 2 из 3")?.state, "run", "«WF N из M» без значка — это счёт, и он «идёт»");
  assert.equal(parse("сейчас идём WF 2 из 3\n💭⚪[Проект](docs/status.md) · WF 1 из 3 · идёт💭").wf, 1,
    "строка состояния стоит последней и перебивает упоминание выше");
});

// Значок засчитывается только в НАЧАЛЕ строки. Раньше хватало значка где угодно
// в ней, и обычная фраза с ✅ и «N из M» красила всю полосу зелёным «готово»
// посреди работы — самый сильный сигнал в окне врал (находка ревизии 08.09).
test("обычная фраза с ✅ и «N из M» строкой состояния не становится", () => {
  assert.equal(parse("Здесь 5 из 7 тестов зелёные ✅"), null);
  assert.equal(parse("- шаги 3 из 3 ✅"), null);
  assert.equal(parse("Тесты: 222 из 222 ✅"), null);
  assert.equal(parse("закрыл 5 из 7 пунктов ✅"), null);
  assert.equal(parse("## Я сделал:\n1. тесты ✅ 2 из 2\n2. и всё"), null,
    "список сделанного полосу не красит");
});

test("настоящие строки чатов Элвиса разбираются как прежде", () => {
  const run = parse("💭⚪[Проект](docs/status.md) · WF 2 из 3 · идёт💭");
  assert.equal(run.wf, 2);
  assert.equal(run.of, 3);
  assert.equal(run.state, "run");
  assert.equal(run.project, "Проект");
  const done = parse("✅⚪[Проект](docs/status.md) · WF 2 из 2 · готово✅");
  assert.equal(done.state, "done");
  assert.equal(done.pct, 100);
  assert.equal(done.total, 100);
  // В попапах строка приезжает из текста всего окна — с отступом.
  assert.equal(parse("   ✅⚪[Проект](docs/status.md) · WF 2 из 2 · готово✅").state, "done");
  // «Жду» пишется и с селектором VS16, и без него.
  assert.equal(parse("⚠️⚪[Проект](docs/status.md) · WF 1 из 2 · жду⚠️").state, "wait");
  assert.equal(parse("⚠⚪[Проект](docs/status.md) · WF 1 из 2 · жду⚠").state, "wait");
  assert.equal(parse("✋⚪[Проект](docs/status.md) · WF 1 из 2 · жду✋").state, "wait");
  assert.equal(parse("🛑⚪[Проект](docs/status.md) · WF 1 из 2 · упал🛑").state, "fail");
});

test("берётся ПОСЛЕДНЕЕ совпадение — строка состояния стоит последней", () => {
  const answer = [
    "## Я сделал:",
    "1. тесты ✅ 2 из 2",
    "",
    "💭🟣[Trelvis](docs/status.md) · WF 5 из 8 · 20%💭",
  ].join("\n");
  const info = parse(answer);
  assert.equal(info.wf, 5, "пересказ выше по тексту не перебивает строку состояния");
  assert.equal(info.of, 8);
  assert.equal(info.state, "run");
});

test("проценты зажимаются в 0…100", () => {
  assert.equal(parse("💭⚪X · WF 2 из 4 · 150%💭").pct, 100);
  assert.equal(parse("💭⚪X · WF 2 из 4 · 0%💭").pct, 0);
  assert.equal(parse("💭⚪X · WF 2 из 4 · 0%💭").total, 25, "доля марафона считается по закрытым");
  assert.equal(parse("💭⚪X · WF 2 из 4💭").pct, null, "процента может не быть вовсе");
});

test("«готово» даёт полную полосу независимо от процента рядом", () => {
  const info = parse("✅⚪X · WF 2 из 5 · 10%✅");
  assert.equal(info.state, "done");
  assert.equal(info.pct, 100);
  assert.equal(info.total, 100);
});

test("мусор и пустота разбор не роняют", () => {
  for (const value of ["", null, undefined, "привет", "WF из", "💭💭", "0 из 0"]) {
    assert.equal(parse(value), null, JSON.stringify(value));
  }
});

// ---- мелкие номера (WF84, #7204): чистая арифметика ряда ---------------------
test("progressBadges: готовые, идущий с долей шагов, впереди; «готово ✅» закрывает все", () => {
  const run = badges({ wf: 3, of: 5, pct: 40, total: 52, state: "run" });
  assert.deepEqual(run.items.map(item => item.state), ["done", "done", "run", "plan", "plan"]);
  assert.deepEqual(run.items.map(item => item.share), [100, 100, 40, 0, 0], "доля шагов — только у идущего");
  assert.deepEqual(run.items.map(item => item.n), [1, 2, 3, 4, 5]);
  assert.equal(run.gap, 4, "зазор 4");
  // WF22: идущий никогда не пуст — без процентов и без сводки ему достаётся
  // минимум в 8 %, иначе линии шагов не видно (#5543).
  assert.deepEqual(badges({ wf: 1, of: 3, pct: 0, total: 0, state: "run" }).items.map(item => item.share), [8, 0, 0]);
  assert.deepEqual(badges({ wf: 2, of: 4, pct: 10, total: 37, state: "done" }).items.map(item => item.state),
    ["done", "done", "done", "done"], "✅ закрывает все номера");
  assert.deepEqual(badges({ wf: 2, of: 3, pct: null, state: "wait" }).items.map(item => item.state), ["done", "wait", "plan"]);
  assert.deepEqual(badges({ wf: 2, of: 3, pct: null, state: "fail" }).items.map(item => item.state), ["done", "fail", "plan"]);
});

test("progressBadges: номеров не больше сорока и не меньше одного", () => {
  assert.equal(badges({ wf: 1, of: 100, pct: 0, total: 0, state: "run" }).items.length, 40);
  assert.equal(badges({ wf: 1, of: 0, pct: 50, total: 50, state: "run" }).items.length, 1);
  assert.deepEqual(badges(null).items, [], "строки нет — номеров нет");
});

test("progressBadges: не влезает — зазор 3, потом первые готовые сливаются в «1–9»; идущий не сливается", () => {
  assert.equal(inner.progressBadgeWidth("7"), 18, "номер 18 точек");
  assert.equal(inner.progressBadgeWidth("12"), 18, "и две цифры влезают в те же 18");
  // 7 номеров в окне 300: 7 × 18 + 6 × 4 = 150 при ~250 доступных.
  const seven = badges({ wf: 4, of: 7, pct: null, state: "run" }, 256);
  assert.equal(seven.items.length, 7, "семь номеров порознь");
  assert.equal(seven.gap, 4);
  // 12 × 18 + 11 × 4 = 260; с зазором 3 — 249.
  const tight = badges({ wf: 10, of: 12, pct: null, state: "run" }, 250);
  assert.equal(tight.items.length, 12, "зазор 3 — и влезли без слияния");
  assert.equal(tight.gap, 3);
  const merged = badges({ wf: 10, of: 12, pct: null, state: "run" }, 180);
  assert.deepEqual(merged.items.map(item => item.n), ["1–9", 10, 11, 12], "первые девять готовых — одним номером");
  assert.equal(merged.items[0].state, "done");
  assert.equal(merged.items[0].last, 9, "клик по слитому — карточка последнего из слитых");
  assert.deepEqual(merged.items.slice(1).map(item => item.state), ["run", "plan", "plan"], "идущий не слит");
  const waiting = badges({ wf: 1, of: 12, pct: null, state: "wait" }, 100);
  assert.equal(waiting.items.length, 12, "сливать нечего — ждущий и будущие не сливаются никогда");
});
test("statusParse разбирает сводку: номер, значок, «о чём» и роли", () => {
  const text = [
    "# 🟣Trelvis",
    "обновлено 11:50",
    "",
    "1️⃣ Workflow ✅ готово",
    "- о чём: задачник и карточки",
    "- шаги 2 из 2",
    "- 00:17 → 01:20 · 1 ч",
    "- кодинг · 2 агента · Opus max",
    "- проверка · 1 агент · Opus max",
    "",
    "2️⃣ Workflow 💭 идёт",
    "- о чём: бот",
    "- кодинг · 1 агент · Opus max",
  ].join("\n");
  const blocks = plain(inner.statusParse(text).blocks);
  assert.equal(blocks.length, 2);
  assert.deepEqual([blocks[0].mark, blocks[0].icon, blocks[0].about], ["1️⃣", "✅", "задачник и карточки"]);
  assert.deepEqual(blocks[0].roles.map(role => role.role), ["кодинг", "проверка"]);
  assert.deepEqual(blocks[0].steps, { done: 2, total: 2 }, "шаги — своё поле, не роль");
  assert.equal(blocks[0].time, "00:17 → 01:20 · 1 ч", "время — своё поле, не роль");
  assert.deepEqual([blocks[1].mark, blocks[1].icon, blocks[1].about], ["2️⃣", "💭", "бот"]);
  assert.deepEqual(blocks[1].roles.map(role => role.role), ["кодинг"]);
});

test("statusParse: без значка блок помечается «запланирован»", () => {
  const [block] = plain(inner.statusParse("3️⃣ Workflow\n- о чём: ещё не начат").blocks);
  assert.deepEqual([block.mark, block.icon], ["3️⃣", "⬜"]);
});

test("сводка находится по имени проекта из строки состояния", () => {
  const loaded = loadInject({ title: "Trelvis" });
  loaded.dom.command({
    id: "s1", action: "status", at: "now", scope: "all",
    projects: [
      { name: "PimpMyClaude", text: "1️⃣ Workflow ✅ готово\n- о чём: прокачка\n- кодинг · 1 агент · Opus max" },
      { name: "Trelvis", text: "1️⃣ Workflow 💭 идёт\n- о чём: задачник\n- кодинг · 2 агента · Opus max" },
    ],
  });
  const about = name => loaded.inner.statusFeedProject(name)?.blocks.map(block => block.about) ?? null;
  assert.deepEqual(plain(about("Trelvis")), ["задачник"]);
  assert.deepEqual(plain(about("Pimp")), ["прокачка"], "имя сходится по началу");
  assert.equal(about("Нетакого"), null, "чужого проекта в сводке нет");
  assert.equal(about(""), null);
  assert.deepEqual(plain(loaded.api.status().statusFeed.projects), ["PimpMyClaude", "Trelvis"]);
});

test("имя проекта сверяется по буквам и цифрам, а не побуквенно", () => {
  assert.equal(inner.statusKey("PimpMyClaude"), "pimpmyclaude");
  assert.equal(inner.statusKey("Vkusnoff-Kz"), "vkusnoffkz");
  assert.equal(inner.statusKey("⚪ Другое!"), "другое");
  assert.equal(inner.statusKey(null), "");
});

// ---- WF22: разбор сводки в объекты, заливка по этапам, пульс ---------------
// Сводка-образец: два готовых воркфлоу, идущий с пометкой 💭 у своего этапа и
// запланированный. Номера трёхзначной цепочкой — их и читает statusBlocks.
const FEED = [
  "# ⚪PimpMyClaude",
  "обновлено 19:46",
  "",
  "41 воркфлоу",
  "26 готово",
  "39 ч",
  "",
  "3️⃣5️⃣ Workflow ✅ готово",
  "- о чём: темы по id чата",
  "- шаги 3 из 3",
  "- 10:45 → 11:00 · 15 мин",
  "- планирование · 3 агента · Opus max",
  "- кодинг · 2 агента · Opus max",
  "- проверка · 1 агент · Opus max",
  "",
  "3️⃣6️⃣ Workflow ✅ готово",
  "- о чём: «Пимп, открой окно»",
  "- шаги 3 из 3",
  "- 16:00 → 17:20 · 1,3 ч",
  "- планирование · я · Fable high",
  "- критика · 1 агент · Opus max",
  "- кодинг · 2 агента · Opus max",
  "- проверка · 2 агента · Opus max",
  "",
  "3️⃣7️⃣ Workflow 💭 идёт",
  "- о чём: полоска v3 — идущий этап дышит",
  "- шаги 1 из 3",
  "- 18:09 → 18:50 · 25 мин",
  "- планирование · я · Fable xhigh",
  "- критика · 1 агент · Opus max",
  "- кодинг · 2 агента · Opus max 💭",
  "- проверка · 🔴 **Fable max**",
  "",
  "3️⃣8️⃣ Workflow ⬜ запланирован",
  "- о чём: перестройка страницы",
  "- кодинг · 1 агент · Opus max",
].join("\n");

// Страница для живых проверок: композер Claude Code и последний ответ со строкой
// состояния. Строки нет — полоса обязана стоять пустым контуром (PROGRESS.md, п. 1).
const page = line => dom => {
  const parts = dom.composer({ top: 620 });
  dom.document.body.add("div", {
    attrs: { "data-testid": "assistant-message" },
    rect: { left: 100, top: 200, width: 1000, height: 300 },
    text: line ? `Готово.\n\n${line}` : "Привет, чем займёмся?",
  });
  return parts;
};
const open = line => loadInject({
  html: page(line), title: "PimpMyClaude", geometry: { viewport: { width: 1200, height: 800 } },
});
const cellsOf = loaded => [...loaded.dom.query("#myclaude-progress-bar").children];
// Узлы номера по порядку (WF84): цифра и линия шагов идущего.
const cellOf = (loaded, index) => cellsOf(loaded)[index];
const numOf = (loaded, index) => cellsOf(loaded)[index].children[0];
const lineOf = (loaded, index) => cellsOf(loaded)[index].children[1];
const withFeed = (text, name = "PimpMyClaude") => {
  const loaded = loadInject({ title: name });
  loaded.dom.command({ id: `s-${name}`, action: "status", at: "now", scope: "all", projects: [{ name, text }] });
  return loaded;
};
const RUN_LINE = "💭⚪[PimpMyClaude](docs/status.md) · WF 3 из 8 · идёт💭";

test("statusBlocks: номер — цепочка клавиш, а не первая из них", () => {
  const text = [
    "2️⃣9️⃣ Workflow ✅ готово", "- о чём: чат по id",
    "🔟 Workflow ✅ готово", "- о чём: автопокраска",
    "4️⃣0️⃣ Workflow ⬜ запланирован", "- о чём: голосом",
  ].join("\n");
  assert.deepEqual(plain(inner.statusBlocks(text)).map(block => block.number), [29, 10, 40]);
  assert.equal(inner.statusLineNumber("1️⃣2️⃣ ✅ · размер шрифта"), 12);
  assert.equal(inner.statusLineNumber("- о чём: это не заголовок"), null);
});

test("statusBlocks: состояние, «о чём», шаги, время и роли объектами", () => {
  const blocks = plain(inner.statusBlocks(FEED));
  assert.deepEqual(blocks.map(block => block.number), [35, 36, 37, 38]);
  assert.deepEqual(blocks.map(block => block.state), ["done", "done", "run", "todo"]);
  const run = blocks[2];
  assert.equal(run.icon, "💭");
  assert.equal(run.about, "полоска v3 — идущий этап дышит");
  assert.deepEqual(run.steps, { done: 1, total: 3 });
  assert.equal(run.time, "18:09 → 18:50 · 25 мин");
  assert.deepEqual(run.roles.map(role => role.role), ["планирование", "критика", "кодинг", "проверка"]);
  assert.deepEqual(run.roles[0], { role: "планирование", agents: "я", model: "Fable", effort: "xhigh", running: false });
  assert.deepEqual(run.roles[2], { role: "кодинг", agents: "2 агента", model: "Opus", effort: "max", running: true },
    "💭 в конце строки роли — пометка идущего этапа");
  assert.deepEqual(run.roles[3], { role: "проверка", agents: "", model: "Fable", effort: "max", running: false },
    "🔴 и **жирное** — разметка сводки, а не имя модели");
});

test("заливка идущего сегмента: по этапам, по шагам, минимум восемь процентов", () => {
  const byStages = withFeed(FEED);
  const info = { wf: 3, of: 5, pct: null, total: 0, state: "run", project: "PimpMyClaude" };
  assert.equal(byStages.inner.progressFill(info), 62.5,
    "план и критик пройдены, кодинг идёт — две четверти плюс половина третьей");

  const bySteps = withFeed(["9️⃣ Workflow 💭 идёт", "- о чём: ролей ещё нет", "- шаги 1 из 4"].join("\n"));
  assert.equal(bySteps.inner.progressFill(info), 25, "ролей нет — считаем по «шаги N из M»");

  const bare = withFeed(["9️⃣ Workflow 💭 идёт", "- о чём: ни ролей, ни шагов"].join("\n"));
  assert.equal(bare.inner.progressFill(info), 8, "нечем считать — минимум, чтобы сегмент был виден");
  assert.equal(bare.inner.progressFill({ ...info, pct: 40 }), 40, "процент из строки состояния сильнее сводки");
  assert.equal(bare.inner.progressFill({ ...info, state: "done" }), 100);
});

// Узел сравниваем через assert.ok(a === b): при промахе assert.equal печатал бы
// оба узла целиком, а у стаба они связаны со всем деревом — вывод без дна.
test("пульс: дышит линия шагов идущего номера, такт 3600, фаза общая", () => {
  const loaded = open(RUN_LINE);
  const live = loaded.dom.running();
  assert.equal(live.length, 1, "дышит ровно один номер");
  assert.ok(live[0].node === lineOf(loaded, 2), "и это линия шагов третьего номера");
  assert.equal(live[0].options.duration, 3600, "такт 3,6 с — общий с карточкой (решение WF84)");
  assert.equal(live[0].options.iterations, Infinity);
  assert.equal(live[0].startTime, 0, "фаза от начала шкалы документа — все дышащие в такт");
  assert.deepEqual(plain(live[0].frames).map(frame => frame.opacity), ["0.45", "1", "0.45"]);
  // Синусоида, а не мигание: easing у каждого кадра, а не общий на круг.
  assert.deepEqual(plain(live[0].frames).map(frame => frame.easing ?? null),
    ["ease-in-out", "ease-in-out", null], "вдох и выдох сглажены по отдельности");
  assert.equal(live[0].options.easing, undefined, "общего easing нет — он дал бы угол на вершине");
  assert.ok(plain(live[0].frames).every(frame => Object.keys(frame).every(key => key === "opacity" || key === "easing")),
    "в кадрах только прозрачность");

  loaded.api.dispose();
  assert.equal(loaded.dom.running().length, 0, "dispose() гасит анимацию");
});

test("линия шагов: ширина — доля шагов идущего, у готовых и будущих линии нет", () => {
  const loaded = open(RUN_LINE);
  assert.equal(lineOf(loaded, 2).style.getPropertyValue("display"), "block");
  assert.equal(lineOf(loaded, 2).style.getPropertyValue("width"), "8%", "сводки нет — минимум 8 %");
  assert.equal(lineOf(loaded, 2).style.getPropertyValue("height"), "2px");
  assert.equal(lineOf(loaded, 2).style.getPropertyValue("background"), ACCENT, "цвет — акцент темы");
  assert.equal(lineOf(loaded, 0).style.getPropertyValue("display"), "none", "у готового линии нет");
  assert.equal(lineOf(loaded, 7).style.getPropertyValue("display"), "none", "у будущего — тоже");

  const wait = open("✋⚪[PimpMyClaude](docs/status.md) · WF 3 из 8 · жду✋");
  assert.equal(wait.dom.running().length, 0, "жёлтый не дышит");
  assert.equal(lineOf(wait, 2).style.getPropertyValue("display"), "none", "и линии шагов у ждущего нет");
});

test("ждёт тебя — жёлтый, упал — красный, стоят; «готово ✅» не дышит, весь ряд зелёный", () => {
  const wait = open("⚪[PimpMyClaude](docs/status.md) · WF 3 из 8 · жду ❓");
  assert.equal(wait.dom.running().length, 0, "ждущий номер не дышит");
  assert.equal(cellOf(wait, 2).style.getPropertyValue("background"), tint("#f5c542", 48), "жёлтый 48 %");
  assert.equal(cellOf(wait, 2).style.getPropertyValue("color"), tint(INK, 92));

  const fail = open("🛑⚪[PimpMyClaude](docs/status.md) · WF 3 из 8 · упал🛑");
  assert.equal(fail.dom.running().length, 0, "упавший не дышит");
  assert.equal(cellOf(fail, 2).style.getPropertyValue("background"), tint("#ef4444", 52), "красный 52 %");

  const done = open("✅⚪[PimpMyClaude](docs/status.md) · WF 8 из 8 · готово✅");
  assert.equal(done.dom.running().length, 0, "готово не дышит (решение WF84: дышит только то, что работает)");
  assert.equal(cellOf(done, 0).style.getPropertyValue("background"), tint("#4dbb7d", 30), "весь ряд зелёный");
  assert.equal(cellOf(done, 7).style.getPropertyValue("background"), tint("#4dbb7d", 30));
  assert.deepEqual(plain(done.api.status().progress.badges).map(item => item.state), Array(8).fill("done"));
});

// В вынесенном окне приметы ответа почти не совпадают, и строка состояния
// приезжает запасным путём — из текста панели. Дыхание обязано работать и там:
// у Элвиса рабочие чаты как раз в попапах.
test("дыхание работает и в вынесенном окне", () => {
  const popout = loadInject({
    href: "about:blank",
    title: "Bro Flow продолжение",
    geometry: { viewport: { width: 1200, height: 800 } },
    html: dom => {
      const parts = dom.composer({ top: 620 });
      const panel = dom.document.body.add("div", {
        class: "epitaxy-chat-panel-body",
        rect: { left: 100, top: 100, width: 1000, height: 420 },
      });
      panel.add("div", {
        rect: { left: 100, top: 200, width: 1000, height: 300 },
        text: `Готово.\n\n${RUN_LINE}`,
      });
      return parts;
    },
  });
  assert.equal(popout.error, null);
  const live = popout.dom.running();
  assert.equal(live.length, 1, "в попапе дышит тот же один номер");
  assert.ok(live[0].node === lineOf(popout, 2));
  assert.equal(live[0].options.duration, 3600);
});

test("пульс гаснет в скрытом окне и при «поменьше движения»", () => {
  const loaded = open(RUN_LINE);
  assert.equal(loaded.dom.running().length, 1);
  loaded.document.hidden = true;
  loaded.document.dispatchEvent({ type: "visibilitychange" });
  assert.equal(loaded.dom.running().length, 0, "в скрытом окне ряд не дышит");
  loaded.document.hidden = false;
  loaded.document.dispatchEvent({ type: "visibilitychange" });
  assert.equal(loaded.dom.running().length, 1, "окно вернулось — вернулся и пульс");
  assert.equal(loaded.dom.running()[0].startTime, 0, "в той же фазе");

  loaded.win.__reducedMotion = true;
  const again = loaded.reload();
  assert.equal(again.error, null);
  assert.equal(loaded.dom.running().length, 0, "prefers-reduced-motion — пульса нет вовсе");
});

// #7188 (слово Элвиса 23.09): нет строки состояния — нет полосы. Пустой контур
// нового чата (PROGRESS.md п. 1 до WF84) снят.
test("новый чат без строки состояния: полосы нет", () => {
  const loaded = open(null);
  const bar = loaded.dom.query("#myclaude-progress-bar");
  assert.notEqual(bar.style.getPropertyValue("display"), "flex", "полосы нет");
  assert.equal(loaded.dom.running().length, 0, "дышать нечему");
  assert.equal(loaded.api.status().progress.reason, "нет строки состояния", "причина названа честно");
  assert.equal(loaded.parts.shell.style.getPropertyValue("padding-bottom"), "", "и места рамка не отдаёт");
});

// ---- чат считает только свой разговор (#5855, WF58) -------------------------
// Замер живьём 12.09 17:47: в главном окне document.body.innerText — это сайдбар
// со списком ЧУЖИХ чатов плюс разговор, а сам разговор лежит в
// .epitaxy-chat-panel-body (поле ввода и сайдбар — вне её). Полоса читала весь
// текст окна, и новый чат показывал зелёными девять чужих воркфлоу.
const FOREIGN_LINE = "✅⚪[PimpMyClaude](docs/status.md) · WF 9 из 9 · готово✅";
// Окно Claude Code: сайдбар с чужим чатом и панель разговора. build(panel)
// дописывает в панель то, что видно в ЭТОМ чате.
const claudeWindow = (build = null, { sidebar = true } = {}) => dom => {
  const parts = dom.composer({ top: 620 });
  if (sidebar) dom.document.body.add("div", {
    class: "sidebar", rect: { left: 0, top: 0, width: 260, height: 800 },
    text: `Recents\nPimpMyClaude\n${FOREIGN_LINE}`,
  });
  const panel = dom.document.body.add("div", {
    class: "epitaxy-chat-panel-body", rect: { left: 260, top: 0, width: 940, height: 600 },
  });
  // Внутри панели — сама лента, и она тоже попадает в наш селектор: в живом окне
  // узлов поэтому ДВА, вложенных друг в друга (замер 12.09 18:30). Выбор «своей»
  // панели обязан их различать, иначе запасное чтение умирает совсем.
  const lane = panel.add("div", {
    attrs: { "data-testid": "epitaxy-virtual-transcript" },
    rect: { left: 260, top: 0, width: 940, height: 600 },
  });
  if (build) build(lane);
  return parts;
};

test("новый чат не берёт чужую строку состояния из окна (#5855)", () => {
  const loaded = loadInject({ html: claudeWindow(), title: "PimpMyClaude" });
  const progress = plain(loaded.api.status().progress);
  assert.equal(progress.wf, null, "в новом чате своей строки нет — и чужой не место");
  assert.equal(progress.reason, "нет строки состояния", "полосы нет");
});

test("чужая сводка проектов сегментов не рисует (#5855)", () => {
  // Окно БЕЗ сайдбара нарочно: иначе тест зелен из-за него, а не из-за сводки,
  // и кто-нибудь потом заведёт чтение сводки в марафон незамеченным (находка
  // проверяющего 12.09).
  const loaded = loadInject({ html: claudeWindow(null, { sidebar: false }), title: "PimpMyClaude" });
  loaded.dom.command({
    id: "s58", action: "status", at: "now", scope: "all",
    projects: [{ name: "PimpMyClaude", text: FEED }],
  });
  const progress = plain(loaded.api.status().progress);
  assert.equal(progress.wf, null, "сводка — текст для подсказки, а не марафон этого чата");
  assert.equal(progress.reason, "нет строки состояния", "и после сводки полосы нет");
});

test("разговор идёт, своей строки нет — полоса пустая, хотя в окне чужая есть (#5855)", () => {
  const loaded = loadInject({
    title: "PimpMyClaude",
    html: claudeWindow(panel => panel.add("div", {
      attrs: { "data-testid": "assistant-message" },
      rect: { left: 300, top: 200, width: 800, height: 200 },
      text: "Готово, проверь.",
    })),
  });
  assert.equal(plain(loaded.api.status().progress).wf, null, "чужая строка из сайдбара не считается");
});

test("окно без примет ответа: своя строка из панели читается, чужая из окна — нет (#5855)", () => {
  const own = "💭⚪[PimpMyClaude](docs/status.md) · WF 2 из 4 · идёт💭";
  const loaded = loadInject({
    title: "PimpMyClaude",
    html: claudeWindow(panel => {
      // В вынесенном окне приметы ответа почти не совпадают (замер 04.09) —
      // остаётся строка действий под ответом: по ней видно, что разговор идёт.
      panel.add("div", { attrs: { "aria-label": "Message actions" }, text: "3 minutes ago\n" });
      panel.add("div", {
        rect: { left: 300, top: 200, width: 800, height: 200 },
        text: `Готово.\n\n${own}`,
      });
    }),
  });
  const progress = plain(loaded.api.status().progress);
  assert.equal(progress.wf, 2, "запасной путь живёт — но читает панель, а не окно");
  assert.equal(progress.of, 4, "счёт свой, а не девять чужих");
});

test("сводка: точное имя проекта выигрывает, префикс — только когда он один", () => {
  const loaded = loadInject({ title: "X" });
  loaded.dom.command({
    id: "s2", action: "status", at: "now", scope: "all",
    projects: [
      { name: "VkusnoffKz-deploy", text: "1️⃣ Workflow ✅ готово\n- о чём: деплой" },
      { name: "VkusnoffKz", text: "1️⃣ Workflow ✅ готово\n- о чём: сайт" },
    ],
  });
  const about = name => loaded.inner.statusFeedProject(name)?.blocks[0].about ?? null;
  assert.equal(about("VkusnoffKz"), "сайт", "точное имя сильнее алфавита");
  assert.equal(about("VkusnoffKz-deploy"), "деплой");
  assert.equal(about("Vkusnoff"), null,
    "два соседа по началу имени — молчим, а не выбираем случайного");
});

// ---- WF84: мелкие номера (#7204, docs/design-strip-wf84.md, макет файла 7) ----
// Слово Элвиса 23.09: «Мелкие номера — прикольно… Зачем много места отнимать?».
// Стенд прежний: рамка поля 1000 × 120 с верхом на 620 (низ 740), редактор —
// от 110 (край текста). Темы в стенде нет — акцент запасной, фиолетовый донора,
// цвет текста — запасной светлый кожи карточки.
const ACCENT = "#8b5cf6";
const INK = "#eef0f4";
const tint = (color, share) => `color-mix(in srgb, ${color} ${share}%, transparent)`;
const barOf = loaded => loaded.dom.query("#myclaude-progress-bar");
const px = (node, name) => Number(node.style.getPropertyValue(name).replace("px", ""));
// Сводка этого чата с часами: два готовых, идущий со сроком «закончит в» и
// запланированный. Вчерашняя — ряд её не берёт (сверка — только сегодняшняя).
const TIMED_FEED = [
  "# ⚪PimpMyClaude", "обновлено вчера 14:45", "",
  "1️⃣ Workflow ✅ готово", "- о чём: первый", "- 9:05 → 9:40 · 35 мин",
  "2️⃣ Workflow ✅ готово", "- о чём: второй", "- 12:00 → 12:40 · 40 мин",
  "3️⃣ Workflow 💭 идёт", "- о чём: третий", "- 13:00 → закончит в 16:00 · идёт 1,8 ч",
  "4️⃣ Workflow ⬜ запланирован", "- о чём: четвёртый",
].join("\n");
const TIMED_LINE = "💭⚪[PimpMyClaude](docs/status.md) · WF 3 из 4 · идёт💭";
const feedTo = (loaded, text, id = "k1") => loaded.dom.command({
  id, action: "status", at: "now", scope: "all", projects: [{ name: "PimpMyClaude", text }],
});
const openFed = line => {
  const loaded = open(line);
  feedTo(loaded, TIMED_FEED);
  return loaded;
};
// Своя разметка поверх стандартной страницы: builder(dom, parts) дописывает
// то, что нужно проверке (цвет поля, плитки вложений, светлую тему).
const openWith = (line, builder, viewport = { width: 1200, height: 800 }) => loadInject({
  title: "PimpMyClaude", geometry: { viewport },
  html: dom => {
    const parts = page(line)(dom);
    return { ...parts, ...(builder(dom, parts) ?? {}) };
  },
});
// Клик по номеру index: ширины номеров стоят на узлах, зазор — на ряду.
const badgeX = (loaded, index) => {
  const bar = barOf(loaded);
  let x = px(bar, "left");
  for (let order = 0; order < index; order += 1) x += px(cellsOf(loaded)[order], "width") + px(bar, "gap");
  return x + 2;
};

test("мелкие номера: высота 12, зазор 4, номер 9px в каждом, подписей нет (#7204)", () => {
  const loaded = open(RUN_LINE);
  const bar = barOf(loaded);
  assert.equal(bar.style.getPropertyValue("height"), "12px", "номера высотой 12");
  assert.equal(bar.style.getPropertyValue("gap"), "4px", "зазор 4");
  assert.deepEqual(cellsOf(loaded).map((cell, index) => numOf(loaded, index).textContent),
    ["1", "2", "3", "4", "5", "6", "7", "8"], "номер воркфлоу в каждом");
  const cell = cellOf(loaded, 0);
  assert.equal(cell.style.getPropertyValue("font"), "600 9px/12px -apple-system, system-ui, sans-serif");
  assert.equal(cell.style.getPropertyValue("font-variant-numeric"), "tabular-nums");
  assert.equal(cell.style.getPropertyValue("width"), "18px");
  assert.equal(cell.style.getPropertyValue("border-radius"), "3px");
  assert.equal(cell.children.length, 2, "цифра и линия шагов — подписей под номерами нет");
  assert.equal(bar.style.getPropertyValue("opacity"), "0.85", "ряд чуть приглушён, наведение — во всю силу");
  assert.match(bar.getAttribute("aria-label"), /^Воркфлоу: 1 готов, 2 готов, 3 идёт, 4 впереди/);
});

test("цвета номера — от темы (макет 7): готов акцентом, идёт контуром, впереди — пустой контур", () => {
  const loaded = open(RUN_LINE);
  // Готовый — фон акцент 30 %, цифра — текст 72 %.
  assert.equal(cellOf(loaded, 0).style.getPropertyValue("background"), tint(ACCENT, 30));
  assert.equal(cellOf(loaded, 0).style.getPropertyValue("color"), tint(INK, 72));
  assert.equal(cellOf(loaded, 0).style.getPropertyValue("box-shadow"), "none");
  // Идущий — обводка акцент 85 %, цифра акцентом.
  assert.equal(cellOf(loaded, 2).style.getPropertyValue("background"), "transparent");
  assert.equal(cellOf(loaded, 2).style.getPropertyValue("box-shadow"), `inset 0 0 0 1px ${tint(ACCENT, 85)}`);
  assert.equal(cellOf(loaded, 2).style.getPropertyValue("color"), ACCENT);
  // Впереди — обводка текст 22 %, цифра текст 42 %.
  assert.equal(cellOf(loaded, 5).style.getPropertyValue("box-shadow"), `inset 0 0 0 1px ${tint(INK, 22)}`);
  assert.equal(cellOf(loaded, 5).style.getPropertyValue("color"), tint(INK, 42));

  // Цвет текста поля — из самой рамки: цифра готового = цвет текста рамки.
  const themed = openWith(RUN_LINE, (dom, parts) => { parts.shell.computed = { ...parts.shell.computed, color: "rgb(20, 24, 39)" }; });
  assert.equal(cellOf(themed, 0).style.getPropertyValue("color"), tint("rgb(20, 24, 39)", 72));

  // Светлая тема: жёлтый плотнее, красный бледнее и цифра тёмно-красная.
  const light = dom => { dom.document.documentElement.computed = { colorScheme: "light" }; };
  const wait = openWith("⚪[PimpMyClaude](docs/status.md) · WF 3 из 8 · жду ❓", light);
  assert.equal(cellOf(wait, 2).style.getPropertyValue("background"), tint("#f5c542", 75));
  const fail = openWith("⚪[PimpMyClaude](docs/status.md) · WF 3 из 8 · упал 🛑", light);
  assert.equal(cellOf(fail, 2).style.getPropertyValue("background"), tint("#ef4444", 30));
  assert.equal(cellOf(fail, 2).style.getPropertyValue("color"), "rgb(150,20,20)", "не белая цифра на светлом");
});

test("номер на залитой заливке читается и на светлых темах: тёмный на ярком, белый на тёмном", () => {
  assert.equal(inner.progressInk("#62ff62"), "#0b0d10", "неоновый зелёный — тёмная цифра, как в макете");
  assert.equal(inner.progressInk("#4dbb7d"), "#0b0d10", "зелёное «готово» — тоже");
  assert.equal(inner.progressInk("#a31000"), "#ffffff", "«Апельсин»: акцент тёмный — цифра белая");
  assert.equal(inner.progressInk("hsl(120.000 100.000% 70.000%)"), "#0b0d10", "тройка темы в hsl() разбирается");
  assert.equal(inner.progressInk("hsl(0 100% 25%)"), "#ffffff");
  assert.equal(inner.progressInk("rgb(204,58,48)"), "#ffffff", "rgb(…) — тоже (тона кожи карточки)");
  assert.equal(inner.progressInk("oklch(0.7 0.1 200)"), "#0b0d10", "незнакомая запись — тёмный, как в макете");
});

test("место под ряд (#7189): добавка 18, номер слева по краю текста; режим чтения, чат без строки и dispose возвращают поле", () => {
  const loaded = open(RUN_LINE);
  const { shell } = loaded.parts;
  assert.equal(shell.style.getPropertyValue("padding-bottom"), "18px", "воздух 6 + номер 12");
  assert.equal(shell.hasAttribute("data-myclaude-progress-room"), true, "рамка помечена для уборки сирот");
  assert.equal(shell.style.getPropertyValue("--myclaude-progress-room"), "18px",
    "добавка — и переменной: по ней широкий вид поднимает кнопку отправки");
  assert.equal(plain(loaded.api.status().progress).room, 18);
  assert.equal(px(barOf(loaded), "top"), 740 - 12, "номер — над своим полем рамки (у стенда оно 0)");
  assert.equal(px(barOf(loaded), "left"), 110, "слева — по краю текста поля");
  assert.equal(px(barOf(loaded), "width"), 980, "справа — столько же от края рамки");

  loaded.api.setStage(loaded.api.stages.COLLAPSED);
  assert.equal(shell.style.getPropertyValue("padding-bottom"), "", "режим чтения — поле рамке вернули");
  assert.equal(shell.style.getPropertyValue("--myclaude-progress-room"), "");
  assert.equal(shell.hasAttribute("data-myclaude-progress-room"), false);
  assert.equal(plain(loaded.api.status().progress).room, 0);
  loaded.api.setStage(loaded.api.stages.NORMAL);
  assert.equal(shell.style.getPropertyValue("padding-bottom"), "18px", "поле открыли — место снова отдано");
  loaded.api.dispose();
  assert.equal(shell.style.getPropertyValue("padding-bottom"), "", "dispose — рамка как была");
  assert.equal(shell.hasAttribute("data-myclaude-progress-room"), false);

  const empty = open(null);
  assert.equal(empty.parts.shell.style.getPropertyValue("padding-bottom"), "", "чат без строки места не просит (#7188)");
  assert.equal(plain(empty.api.status().progress).room, 0, "и рамка с родным полем");
});

test("своё поле рамки Claude не отнимаем, с плитками вложений воздух 8 (#7189)", () => {
  const loaded = openWith(RUN_LINE, (dom, parts) => { parts.shell.computed = { ...parts.shell.computed, paddingBottom: "8px" }; });
  assert.equal(loaded.parts.shell.style.getPropertyValue("padding-bottom"), "26px", "8 Claude + 18 наших");
  assert.equal(plain(loaded.api.status().progress).room, 18);
  assert.equal(px(barOf(loaded), "top"), 740 - 8 - 12, "номер — над родным полем Claude: от текста воздух 6");

  const tiles = openWith(RUN_LINE, (dom, parts) => {
    parts.shell.computed = { ...parts.shell.computed, paddingBottom: "8px" };
    dom.pill(parts.block);
  });
  assert.equal(tiles.parts.shell.style.getPropertyValue("padding-bottom"), "28px", "с плиткой — 8 + 20");
  assert.equal(plain(tiles.api.status().progress).room, 20, "от плиток до номеров — 8, а не 6");
});

test("узкое поле: номера порознь, пока влезают; дальше первые готовые сливаются в «1–9»", () => {
  // Окно на 20 точек шире поля; редактор — на 10 от края рамки.
  const narrow = (width, line = RUN_LINE) => loadInject({
    title: "PimpMyClaude", geometry: { viewport: { width: width + 20, height: 800 } },
    html: dom => {
      const parts = dom.composer({ top: 620, left: 10, width });
      dom.document.body.add("div", {
        attrs: { "data-testid": "assistant-message" },
        rect: { left: 10, top: 200, width, height: 300 },
        text: `Готово.\n\n${line}`,
      });
      return parts;
    },
  });
  // Ряд 180: 8 × 18 + 7 × 4 = 172 — влезают.
  let progress = plain(narrow(200).api.status().progress);
  assert.equal(progress.badges.length, 8, "номера порознь");
  // Ряд 130: не влезают и с зазором 3 — два готовых сливаются.
  const tight = narrow(150);
  progress = plain(tight.api.status().progress);
  assert.deepEqual(progress.badges.map(item => item.n), ["1–2", 3, 4, 5, 6, 7, 8]);
  assert.equal(progress.badges[1].state, "run", "идущий не сливается");
  // И слитые не влезают (23 + 6 × 18 + 6 × 3 = 149 > 130) — с WF85 это режим
  // прокрутки (#7356): номера те же, справа хвост «… 8», ряд режет окно номеров.
  assert.equal(progress.scroll.max > 0, true, "режим прокрутки: есть куда ехать");
  assert.equal(progress.scroll.tail, true, "хвост виден");
  assert.equal(tight.dom.query("#myclaude-progress-tail").textContent, "…\u202F8");
  assert.equal(px(barOf(tight), "width"), 130 - 23 - 3 - 3, "окно номеров = ряд − хвост − зазор − поле обрезки");
  const twelve = narrow(200, "⚪[PimpMyClaude](docs/status.md) · WF 10 из 12 · идёт 💭");
  progress = plain(twelve.api.status().progress);
  assert.deepEqual(progress.badges.map(item => item.n), ["1–9", 10, 11, 12], "двенадцать в ряду 180");
  assert.equal(barOf(twelve).style.getPropertyValue("gap"), "3px");
  assert.equal(numOf(twelve, 0).textContent, "1–9");
  // Клик по слитому — карточка последнего из слитых.
  twelve.document.dispatchEvent({ type: "pointerdown", clientX: badgeX(twelve, 0), clientY: px(barOf(twelve), "top") + 1 });
  assert.match(plain(twelve.api.status().progress.tip).card, /^Воркфлоу 9/);
});

test("клик по номеру — его карточка; второй клик закрывает; мимо номеров в ряду — текущий; над рядом клик остаётся полю", () => {
  const loaded = openFed(TIMED_LINE);
  const top = px(barOf(loaded), "top");
  const press = (x, y) => loaded.document.dispatchEvent({ type: "pointerdown", clientX: x, clientY: y });
  assert.equal(press(badgeX(loaded, 1), top + 1), false, "клик по номеру 2 забирает ряд");
  let tip = plain(loaded.api.status().progress.tip);
  assert.equal(tip.open, true);
  assert.equal(tip.segment, 1);
  assert.equal(cellOf(loaded, 1).style.getPropertyValue("outline"), `1.5px solid ${tint(INK, 55)}`, "выбранный номер обведён");
  assert.equal(cellOf(loaded, 0).style.getPropertyValue("outline"), "none");
  press(badgeX(loaded, 1), top + 1);
  assert.equal(plain(loaded.api.status().progress.tip).open, false, "второй клик по нему — закрыть");
  assert.equal(cellOf(loaded, 1).style.getPropertyValue("outline"), "none");
  press(px(barOf(loaded), "left") + 600, top + PROGRESS_HIT);
  tip = plain(loaded.api.status().progress.tip);
  assert.equal(tip.segment, 2, "пустое место ряда — карточка текущего воркфлоу N (+4 точки по вертикали — ещё ряд)");
  loaded.win.dispatchEvent({ type: "keydown", key: "Escape" });
  assert.equal(plain(loaded.api.status().progress.tip).open, false, "Escape закрывает");
  assert.equal(press(badgeX(loaded, 2), top - 5), true, "выше ряда больше чем на 4 — текст поля, клик ему");
  assert.equal(plain(loaded.api.status().progress.tip).open, false);
});

// WF144 (класс WF136 п.7, «наши слои уступают меню»): меню Claude над рядом — нажатие
// по пункту меню ряд не забирает, даже если раскладка ещё не спрятала полосу.
test("WF144: под точкой меню Claude — нажатие уходит меню, ряд его не ест", () => {
  const loaded = openFed(TIMED_LINE);
  const top = px(barOf(loaded), "top");
  const press = (x, y) => loaded.document.dispatchEvent({ type: "pointerdown", clientX: x, clientY: y });
  const menu = loaded.document.body.add("div", { attrs: { role: "menu" }, rect: { left: 0, top: 0, width: 2000, height: 2000 } });
  const item = menu.add("div", { attrs: { role: "menuitem" } });
  loaded.document.elementFromPoint = () => item;
  assert.equal(press(badgeX(loaded, 1), top + 1), true, "пункт меню получил нажатие");
  assert.equal(plain(loaded.api.status().progress.tip).open, false, "карточка не открылась");
  loaded.document.elementFromPoint = () => null;
  assert.equal(press(badgeX(loaded, 1), top + 1), false, "меню нет — ряд снова свой");
});

test("ряд появился — лента, стоявшая внизу, остаётся внизу (#5869)", () => {
  const withTail = (line, scrollTop) => openWith(line, dom => {
    const tail = dom.document.body.add("div", {
      attrs: { "data-testid": "epitaxy-virtual-transcript" },
      rect: { left: 0, top: 0, width: 1200, height: 500 },
      computed: { overflowY: "auto" },
    });
    tail.clientHeight = 500;
    tail.scrollHeight = 900;
    tail.scrollTop = scrollTop;
    return { tail };
  });
  assert.equal(withTail(RUN_LINE, 400).parts.tail.scrollTop, 900, "стояла внизу — поле выросло, вернули вниз");
  const up = withTail(RUN_LINE, 100);
  assert.equal(up.parts.tail.scrollTop, 100, "человек ушёл наверх — не трогаем");
  assert.equal(plain(up.api.status().progress).frozen, true, "и строку не читаем: лента не у низа");
  assert.equal(withTail(null, 400).parts.tail.scrollTop, 400, "без строки места не отняли — и ленту не трогаем");
});

// ---- WF84: ряд стоит, когда ленту листают (ТЗ полоски, п. 1–2) -------------
// Слово Элвиса 23.09: «при прокручивании чата вверх-вниз это поле не менялось…
// показывалось реально, что сейчас происходит». Лента виртуальная: прокрутил
// вверх — в DOM старые ответы со старыми строками. Строку читаем только у низа.
const PROGRESS_HIT = 4;
const scrollStand = (texts, { scrollTop = 1500 } = {}) => loadInject({
  title: "PimpMyClaude", geometry: { viewport: { width: 1200, height: 800 } },
  html: dom => {
    const parts = dom.composer({ top: 620 });
    const tail = dom.document.body.add("div", {
      attrs: { "data-testid": "epitaxy-virtual-transcript" },
      rect: { left: 100, top: 0, width: 1000, height: 500 }, computed: { overflowY: "auto" },
    });
    tail.clientHeight = 500;
    tail.scrollHeight = 2000;
    tail.scrollTop = scrollTop;
    const answers = texts.map((text, index) => tail.add("div", {
      attrs: { "data-testid": "assistant-message" },
      rect: { left: 100, top: 20 + index * 100, width: 1000, height: 90 }, text,
    }));
    return { ...parts, tail, answers };
  },
});
const states = loaded => plain(loaded.api.status().progress.badges).map(item => item.state);
const TODAY = "обновлено 12:00";

test("у низа ленты — строка последнего ответа; прокрутил вверх — ряд стоит, «запомнено»", () => {
  const loaded = scrollStand(["⚪[PimpMyClaude](docs/status.md) · WF 3 из 3 · идёт 💭"]);
  assert.deepEqual(states(loaded), ["done", "done", "run"]);
  let progress = plain(loaded.api.status().progress);
  assert.equal(progress.source, "низ ленты");
  assert.equal(progress.frozen, false);
  assert.equal(progress.atBottom, true);

  // Прокрутили на три экрана вверх: в DOM теперь старый ответ со старой строкой.
  loaded.parts.tail.scrollTop = 200;
  loaded.parts.answers[0].textContent = "⚪[PimpMyClaude](docs/status.md) · WF 1 из 3 · идёт 💭";
  loaded.dom.fireKind("interval");
  progress = plain(loaded.api.status().progress);
  assert.deepEqual(states(loaded), ["done", "done", "run"], "ряд не поменялся");
  assert.equal(progress.frozen, true);
  assert.equal(progress.source, "запомнено");
  assert.equal(progress.atBottom, false);
  assert.equal(progress.wf, 3, "страховочный перечёт тоже не читает ленту не у низа");

  // Вернулись к низу — там новая строка «жду ❓».
  loaded.parts.tail.scrollTop = 1500;
  loaded.parts.answers[0].textContent = "⚪[PimpMyClaude](docs/status.md) · WF 3 из 3 · жду ❓";
  loaded.dom.fireKind("interval");
  assert.deepEqual(states(loaded), ["done", "done", "wait"], "у низа — снова читаем");
  assert.equal(plain(loaded.api.status().progress).frozen, false);
});

test("сменился чат в окне, лента не у низа — ряда нет, а не строка прежнего чата", () => {
  const loaded = scrollStand(["⚪[PimpMyClaude](docs/status.md) · WF 2 из 3 · идёт 💭"]);
  assert.deepEqual(states(loaded), ["done", "run", "plan"]);
  const before = loaded.inner.chatKey();
  const router = loaded.dom.router();
  router.navigate("/epitaxy/local_other");
  assert.notEqual(loaded.inner.chatKey(), before, "ключ чата сменился");
  loaded.parts.tail.scrollTop = 200;
  loaded.dom.fireKind("interval");
  const progress = plain(loaded.api.status().progress);
  assert.equal(progress.wf, null, "про этот чат ничего не запомнено");
  assert.equal(progress.source, "нет");
  assert.equal(barOf(loaded).style.getPropertyValue("display"), "none");
  // Вернулись в прежний чат, лента всё ещё не у низа — его строка запомнена.
  router.navigate("/epitaxy/local_test");
  loaded.dom.fireKind("interval");
  assert.deepEqual(states(loaded), ["done", "run", "plan"], "свой чат — запомненная строка");
  assert.equal(plain(loaded.api.status().progress).source, "запомнено");
});

test("сводка сегодняшняя и покрывает 1…M: номера по её блокам, даже когда ряд стоит", () => {
  const feed = (third) => [
    "# ⚪PimpMyClaude", TODAY, "",
    "1️⃣ Workflow ✅ готово", "- о чём: первый",
    "2️⃣ Workflow ✅ готово", "- о чём: второй",
    `3️⃣ Workflow ${third}`, "- о чём: третий", "- кодинг · 1 агент · Opus max 💭",
  ].join("\n");
  const loaded = scrollStand(["⚪[PimpMyClaude](docs/status.md) · WF 3 из 3 · идёт 💭"]);
  feedTo(loaded, feed("💭 идёт"));
  assert.equal(plain(loaded.api.status().progress).blocks, true, "сводка принята");
  assert.deepEqual(states(loaded), ["done", "done", "run"]);
  loaded.parts.tail.scrollTop = 200;
  loaded.dom.fireKind("interval");
  feedTo(loaded, feed("✅ готово"), "k2");
  assert.deepEqual(states(loaded), ["done", "done", "done"], "блок 3 стал ✅ — номер 3 готов без чтения ленты");
  assert.equal(plain(loaded.api.status().progress).frozen, true);
});

test("два 💭 блока разом: оба номера идут и дышат в один такт", () => {
  const loaded = scrollStand(["⚪[PimpMyClaude](docs/status.md) · WF 2 из 4 · идёт 💭"]);
  feedTo(loaded, [
    "# ⚪PimpMyClaude", TODAY, "",
    "1️⃣ Workflow ✅ готово", "- о чём: первый",
    "2️⃣ Workflow 💭 идёт", "- о чём: второй", "- кодинг · Opus max 💭",
    "3️⃣ Workflow 💭 идёт", "- о чём: третий", "- план · я · Opus max 💭",
    "4️⃣ Workflow ⬜ запланирован", "- о чём: четвёртый",
  ].join("\n"));
  assert.deepEqual(states(loaded), ["done", "run", "run", "plan"]);
  const live = loaded.dom.running();
  assert.equal(live.length, 2, "дышат оба идущих");
  assert.ok(live.every(item => item.options.duration === 3600 && item.startTime === 0), "в одной фазе одного такта");
  assert.equal(plain(loaded.api.status().progress.badges)[2].share, 12.5, "у второго идущего своя доля шагов");
});

test("сверка сводки: блоков больше M — они чужие, номера по одной строке; вчерашняя — тоже мимо", () => {
  const five = ["1️⃣ Workflow ✅ готово", "2️⃣ Workflow ✅ готово", "3️⃣ Workflow ✅ готово",
    "4️⃣ Workflow 💭 идёт", "5️⃣ Workflow ⬜ запланирован"];
  const loaded = open("⚪[PimpMyClaude](docs/status.md) · WF 2 из 3 · идёт 💭");
  feedTo(loaded, ["# ⚪PimpMyClaude", TODAY, "", ...five].join("\n"));
  assert.equal(plain(loaded.api.status().progress).blocks, false, "пять блоков при M = 3 — не наша сводка");
  assert.deepEqual(states(loaded), ["done", "run", "plan"], "и номера — по строке");

  const old = open("⚪[PimpMyClaude](docs/status.md) · WF 2 из 3 · идёт 💭");
  feedTo(old, ["# ⚪PimpMyClaude", "обновлено вчера 12:00", "",
    "1️⃣ Workflow ✅ готово", "2️⃣ Workflow ✅ готово", "3️⃣ Workflow ✅ готово"].join("\n"));
  assert.equal(plain(old.api.status().progress).blocks, false, "вчерашняя сводка — не про сейчас");
  assert.deepEqual(states(old), ["done", "run", "plan"]);
});

// ---- строка состояния нового образца (ELVIS.md 23.09, #7188, критик WF84 Б1) ----
const FOOTER = ["Контекст 248K", "Из кэша 100% · Новых 222K", "Ответ 5.2M · Чат 5.2M · Opus 5.5 Extra 💭"].join("\n");
const answersStand = texts => loadInject({
  title: "PimpMyClaude", geometry: { viewport: { width: 1200, height: 800 } },
  html: dom => {
    const parts = dom.composer({ top: 620 });
    texts.forEach((text, index) => dom.document.body.add("div", {
      attrs: { "data-testid": "assistant-message" },
      rect: { left: 100, top: 100 + index * 120, width: 1000, height: 100 }, text,
    }));
    return parts;
  },
});

test("новый образец: слово и значок в конце, ❓ — «жду»", () => {
  const run = parse("⚪[PimpMyClaude](docs/status.md) · WF 2 из 3 · идёт 💭");
  assert.deepEqual([run.wf, run.of, run.state, run.project], [2, 3, "run", "PimpMyClaude"]);
  assert.equal(parse("⚪[P](docs/status.md) · WF 2 из 3 · жду ❓").state, "wait", "❓ = жду");
  assert.equal(parse("⚪[P](docs/status.md) · WF 1 из 3 · упал 🛑").state, "fail");
  const done = parse("⚪[P](docs/status.md) · WF 3 из 3 · готово ✅");
  assert.equal(done.state, "done", "«готово» не рисуется «идёт»");
  assert.equal(done.total, 100);
});

test("три строки расхода под строкой состояния её не перебивают", () => {
  const info = parse(`Сделал.\n\n⚪[P](docs/status.md) · WF 2 из 4 · жду ❓\n${FOOTER}`);
  assert.equal(info.wf, 2);
  assert.equal(info.state, "wait", "💭 строки расхода «жду» не перебил");
  assert.equal(parse(`Сделал.\n${FOOTER}`), null, "одна строка расхода — не строка состояния");
});

test("строка без WF — воркфлоу нет: полосы нет, и старые ответы не ищутся", () => {
  assert.equal(parse(`⚪[P](docs/status.md) · WF 2 из 3 · идёт 💭\nпотом\n⚪[P](docs/status.md) · готово ✅\n${FOOTER}`), null,
    "последняя строка без WF гасит полосу из того же текста");
  assert.equal(inner.progressScan("🟣[Trelvis](docs/status.md) · жду ❓").stop, true);
  const loaded = answersStand([
    "⚪[PimpMyClaude](docs/status.md) · WF 3 из 3 · идёт 💭",
    `Всё.\n⚪[PimpMyClaude](docs/status.md) · готово ✅\n${FOOTER}`,
  ]);
  const progress = plain(loaded.api.status().progress);
  assert.equal(progress.wf, null, "старый ответ полосу не воскрешает");
  assert.equal(progress.reason, "нет строки состояния");
});

test("ответ без строки состояния поиск назад не останавливает", () => {
  const loaded = answersStand([`⚪[PimpMyClaude](docs/status.md) · WF 2 из 5 · идёт 💭\n${FOOTER}`, "Да."]);
  assert.equal(plain(loaded.api.status().progress).wf, 2);
});
