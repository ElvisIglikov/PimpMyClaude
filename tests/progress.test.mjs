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
  assert.deepEqual(shares({ wf: 1, of: 3, pct: 0, total: 0, state: "run" }, 400), [0, 0, 0]);
  assert.deepEqual(shares({ wf: 2, of: 4, pct: 10, total: 37, state: "done" }, 400), [100, 100, 100, 100],
    "✅ закрашивает все сегменты");
});

test("progressShares: в узком окне сегменты сливаются в одну долю", () => {
  assert.deepEqual(shares({ wf: 3, of: 5, pct: 40, total: 52, state: "run" }, 30), [52]);
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
