// Полоса прогресса воркфлоу (раздел 2б inject.js): разбор строки состояния из
// SkilZZZ/AGENTS.md, доли сегментов и сводка проектов для подсказки.
// Образцы строк взяты из самого AGENTS.md — формат меняется там, а не здесь.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";

const { inner } = loadInner({ title: "Trelvis" });
const parse = text => plain(inner.parseProgressText(text));
const shares = (info, width) => plain(inner.progressShares(info, width));

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

test("progressShares: доли слева направо, готовые полные, будущие пустые", () => {
  assert.deepEqual(shares({ wf: 3, of: 5, pct: 40, total: 52, state: "run" }, 400), [100, 100, 40, 0, 0]);
  // WF22: идущий сегмент никогда не пуст — без процентов и без сводки ему
  // достаётся минимум в 8 %, иначе текущего воркфлоу на полосе не видно (#5543).
  assert.deepEqual(shares({ wf: 1, of: 3, pct: 0, total: 0, state: "run" }, 400), [8, 0, 0]);
  assert.deepEqual(shares({ wf: 2, of: 4, pct: 10, total: 37, state: "done" }, 400), [100, 100, 100, 100],
    "✅ закрашивает все сегменты");
});

test("progressShares: в узком окне сегменты сливаются в одну долю", () => {
  // Слитая полоса тоже считает долю по заливке текущего сегмента: (2 + 0,4) / 5 = 48 % (гейт WF22).
  assert.deepEqual(shares({ wf: 3, of: 5, pct: 40, total: 52, state: "run" }, 30), [48]);
  assert.equal(shares({ wf: 3, of: 5, pct: 40, total: 52, state: "run" }, 400).length, 5, "в широком окне — все пять");
});

test("progressShares: сегментов не больше сорока и не меньше одного", () => {
  assert.equal(shares({ wf: 1, of: 100, pct: 0, total: 0, state: "run" }, 4000).length, 40);
  assert.equal(shares({ wf: 1, of: 0, pct: 50, total: 50, state: "run" }, 400).length, 1);
});

test("statusLines разбирает сводку: номер, значок, «о чём» и роли", () => {
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
  const lines = plain(inner.statusLines(text));
  assert.equal(lines.length, 2);
  assert.equal(lines[0], "1️⃣ ✅ · задачник и карточки · кодинг · проверка");
  assert.equal(lines[1], "2️⃣ 💭 · бот · кодинг");
  assert.ok(!lines[0].includes("шаги"), "шаги и время в подсказку не идут");
  assert.ok(!lines[0].includes("→"));
});

test("statusLines: без значка блок помечается «запланирован», список не длиннее двенадцати", () => {
  assert.ok(plain(inner.statusLines("3️⃣ Workflow\n- о чём: ещё не начат"))[0].startsWith("3️⃣ ⬜"));
  const many = Array.from({ length: 20 }, (unused, index) => `1️⃣ Workflow ✅\n- о чём: номер ${index}`).join("\n");
  const lines = plain(inner.statusLines(many));
  assert.equal(lines.length, 12);
  assert.ok(lines[11].includes("номер 19"), "оставляем последние, а не первые");
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
  assert.deepEqual(plain(loaded.inner.statusFeedLines("Trelvis")), ["1️⃣ 💭 · задачник · кодинг"]);
  assert.equal(plain(loaded.inner.statusFeedLines("Pimp")).length, 1, "имя сходится по началу");
  assert.deepEqual(plain(loaded.inner.statusFeedLines("Нетакого")), [], "чужого проекта в сводке нет");
  assert.deepEqual(plain(loaded.inner.statusFeedLines("")), []);
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
const cellsOf = loaded => loaded.dom.query("#myclaude-progress-bar").children;
const fillOf = (loaded, index) => cellsOf(loaded)[index].children[1];
const glowOf = (loaded, index) => cellsOf(loaded)[index].children[2];
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

test("statusLine остаётся прежней: строки подсказки знак в знак", () => {
  const lines = plain(inner.statusLines(FEED));
  assert.equal(lines[2], "3️⃣7️⃣ 💭 · полоска v3 — идущий этап дышит · планирование · критика · кодинг · проверка");
  assert.equal(lines[3], "3️⃣8️⃣ ⬜ · перестройка страницы · кодинг");
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

test("пульс: дышит слой свечения идущего сегмента, а не тень заливки", () => {
  const loaded = open(RUN_LINE);
  const live = loaded.dom.running();
  assert.equal(live.length, 1, "дышит ровно один сегмент");
  assert.equal(live[0].node, glowOf(loaded, 2), "и это слой свечения третьего сегмента");
  assert.equal(live[0].options.duration, 2400);
  assert.equal(live[0].options.iterations, Infinity);
  assert.deepEqual(plain(live[0].frames).map(frame => frame.opacity), ["0.35", "0.8", "0.35"]);
  assert.ok(plain(live[0].frames).every(frame => Object.keys(frame).join() === "opacity"),
    "в кадрах только прозрачность: box-shadow не анимируем");
  assert.equal(glowOf(loaded, 7).style.getPropertyValue("box-shadow"), "none", "пустому сегменту светиться нечем");

  loaded.api.dispose();
  assert.equal(loaded.dom.running().length, 0, "dispose() гасит анимацию");
});

test("пульс: ждёт и упал стоят, «готово» дышит всей зелёной полосой", () => {
  const wait = open("✋⚪[PimpMyClaude](docs/status.md) · WF 3 из 8 · жду✋");
  assert.equal(wait.dom.running().length, 0, "жёлтый сегмент не дышит");
  assert.equal(fillOf(wait, 2).style.getPropertyValue("background"), "#f5c542");

  const fail = open("🛑⚪[PimpMyClaude](docs/status.md) · WF 3 из 8 · упал🛑");
  assert.equal(fail.dom.running().length, 0, "красный сегмент не дышит");
  assert.equal(fillOf(fail, 2).style.getPropertyValue("background"), "#ef4444");

  const done = open("✅⚪[PimpMyClaude](docs/status.md) · WF 8 из 8 · готово✅");
  assert.equal(done.dom.running().length, 8, "готово дышит целиком — это сигнал продолжать");
  assert.equal(fillOf(done, 0).style.getPropertyValue("background"), "#4dbb7d", "и вся полоса зелёная");
  assert.equal(fillOf(done, 7).style.getPropertyValue("background"), "#4dbb7d");
});

test("пульс гаснет в скрытом окне и при «поменьше движения»", () => {
  const loaded = open(RUN_LINE);
  assert.equal(loaded.dom.running().length, 1);
  loaded.document.hidden = true;
  loaded.document.dispatchEvent({ type: "visibilitychange" });
  assert.equal(loaded.dom.running().length, 0, "в скрытом окне полоса не дышит");
  loaded.document.hidden = false;
  loaded.document.dispatchEvent({ type: "visibilitychange" });
  assert.equal(loaded.dom.running().length, 1, "окно вернулось — вернулся и пульс");

  loaded.win.__reducedMotion = true;
  const again = loaded.reload();
  assert.equal(again.error, null);
  assert.equal(loaded.dom.running().length, 0, "prefers-reduced-motion — пульса нет вовсе");
});

test("новый чат без строки состояния: один пустой контур, а не пропавшая полоса", () => {
  const loaded = open(null);
  const bar = loaded.dom.query("#myclaude-progress-bar");
  assert.equal(bar.style.getPropertyValue("display"), "flex", "полоса на месте");
  assert.deepEqual(plain(loaded.api.status().progress.segments), [0], "один сегмент и тот пустой");
  assert.equal(fillOf(loaded, 0).style.getPropertyValue("width"), "0%");
  assert.equal(loaded.dom.running().length, 0, "контуру дышать нечем");
  assert.match(loaded.api.status().progress.reason, /пустой контур/, "причина названа честно");
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
  assert.match(plain(loaded.inner.statusFeedLines("VkusnoffKz"))[0], /сайт/, "точное имя сильнее алфавита");
  assert.match(plain(loaded.inner.statusFeedLines("VkusnoffKz-deploy"))[0], /деплой/);
  assert.deepEqual(plain(loaded.inner.statusFeedLines("Vkusnoff")), [],
    "два соседа по началу имени — молчим, а не выбираем случайного");
});
