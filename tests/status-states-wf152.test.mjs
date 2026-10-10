// WF152: страница — последний разборщик status.md, приведённый к ОДНОМУ правилу состояний (WF145 свёл его в
// Swift PanelProjects.stateMarks/stateWords и в tools/pimp.py DIGEST_MARKS/WORDS). Значок сильнее слова, порядок
// силы: упал 🛑❌ → ждёт Элвиса ✋⚠❓🙋⏸ → впереди ⬜ → готово ✅🟢 → идёт 💭⏳; без значка — слова тем же
// порядком; ни того ни другого — впереди. Таблица заголовков — та же, что в Swift StatusStatesWF145Tests.
// Состояния страницы: fail / wait / todo (впереди) / done / run.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";

const SWIFT_TABLE = [
  ["1️⃣ Workflow ⏳ идёт", "run"],
  ["2️⃣ Workflow 💭 идёт", "run"],
  ["3️⃣ Workflow ✅ готово", "done"],
  ["4️⃣ Workflow ✅ готово, выложено", "done"],
  ["5️⃣ Workflow ⬜ запланирован", "todo"],
  ["6️⃣ Workflow ❓ ждёт Элвиса", "wait"],
  ["7️⃣ Workflow ✋ ждёт", "wait"],
  ["8️⃣ Workflow ⚠️ глянь", "wait"],
  ["9️⃣ Workflow 🙋 ответь", "wait"],
  ["🔟 Workflow ⏸️ пауза", "wait"],
  ["1️⃣ Workflow 🛑 упал", "fail"],
  ["2️⃣ Workflow ❌ стоп", "fail"],
  ["3️⃣ Workflow 🟢 готов", "done"],
  ["4️⃣ Workflow кодинг", "run"],
  ["5️⃣ Workflow критика", "run"],
  ["6️⃣ Workflow запланирован", "todo"],
  ["7️⃣ Workflow впереди", "todo"],
  ["8️⃣ Workflow ждёт Элвиса", "wait"],
  ["9️⃣ Workflow упал на гейте", "fail"],
  ["1️⃣ Workflow", "todo"],
];

test("statusParse: таблица заголовков Swift WF145 даёт те же состояния", () => {
  const { inner } = loadInner();
  for (const [heading, state] of SWIFT_TABLE) {
    const blocks = plain(inner.statusParse(`обновлено 12:40\n${heading}\n- о чём: x`)).blocks;
    assert.equal(blocks.length, 1, heading);
    assert.equal(blocks[0].state, state, heading);
  }
});

test("statusHeadState: значок сильнее слова, порядок силы значков и слов", () => {
  const { inner } = loadInner();
  const state = heading => inner.statusHeadState(heading).state;
  assert.equal(state("Workflow ⬜ ждёт очереди"), "todo", "⬜ — впереди, даже рядом со словом «ждёт»");
  assert.equal(state("Workflow ⏳ запланирован"), "run", "значок ⏳ сильнее слова «запланирован»");
  assert.equal(state("Workflow ✅ упал и поднят"), "done", "значок сильнее слова");
  assert.equal(state("Workflow ✅ готово ⚠️"), "wait", "ждёт сильнее готово");
  assert.equal(state("Workflow ❓ ❌"), "fail", "упал сильнее ждёт");
  assert.equal(state("Workflow ⬜ 💭"), "todo", "впереди сильнее идёт");
  assert.equal(state("Workflow 🟢 ⏳"), "done", "готово сильнее идёт");
  assert.equal(state("Workflow планирование"), "run", "«планирование» — идёт");
  assert.equal(state("Workflow в очереди, ждёт"), "todo", "впереди сильнее ждёт среди слов");
  assert.equal(state("Workflow Стоп"), "fail", "слова без регистра");
  assert.equal(state("Workflow ревизия"), "run");
  assert.equal(state("Workflow исследование"), "run");
  assert.equal(state("Workflow выложен"), "done");
  assert.equal(state("Workflow на паузе"), "wait");
  assert.equal(state("Workflow ⚠ глянь"), "wait", "⚠ без VS16 — тот же значок");
  assert.equal(inner.statusHeadState("Workflow ⏳ идёт").icon, "⏳");
  assert.equal(inner.statusHeadState("Workflow кодинг").icon, "");
});

test("statusParse: эталонная сводка (как docs/status.md 08.10) — ⏳ идёт, ⬜ впереди, ❓ ждёт; блок без значка — ⬜ по умолчанию", () => {
  const { inner } = loadInner();
  const text = [
    "# ⚪PimpMyClaude", "обновлено 12:40", "",
    "1️⃣ Workflow ✅ готово, выложено", "- о чём: раз",
    "2️⃣ Workflow ⏳ идёт", "- о чём: два", "- шаги 2 из 4",
    "3️⃣ Workflow ❓ ждёт Элвиса", "- о чём: три",
    "4️⃣ Workflow ⬜ запланирован", "- о чём: четыре",
    "5️⃣ Workflow", "- о чём: пять",
  ].join("\n");
  const blocks = plain(inner.statusParse(text)).blocks;
  assert.deepEqual(blocks.map(block => block.state), ["done", "run", "wait", "todo", "todo"]);
  assert.deepEqual(blocks.map(block => block.icon), ["✅", "⏳", "❓", "⬜", "⬜"]);
  assert.deepEqual(blocks.map(block => block.about), ["раз", "два", "три", "четыре", "пять"]);
});

test("полоска: ⏳ в сводке — номер идёт, ⬜ — впереди, не «ждёт тебя»", () => {
  const loaded = loadInject({ title: "PimpMyClaude" });
  const text = [
    "# ⚪PimpMyClaude", "обновлено 12:40",
    "1️⃣ Workflow ✅ готово", "- о чём: раз",
    "2️⃣ Workflow ⏳ идёт", "- о чём: два",
    "3️⃣ Workflow ⏳ идёт", "- о чём: три",
    "4️⃣ Workflow ⬜ запланирован", "- о чём: четыре",
  ].join("\n");
  loaded.dom.command({ id: "s152", action: "status", at: "now", scope: "all", projects: [{ name: "PimpMyClaude", text }] });
  const info = { wf: 2, of: 4, pct: null, total: 25, state: "run", project: "PimpMyClaude" };
  const badges = plain(loaded.inner.progressBadgeStates(info));
  assert.equal(badges.blocks, true, "сводка сегодняшняя и покрывает 1…4");
  assert.deepEqual(badges.states, ["done", "run", "run", "plan"]);
  const card = plain(loaded.inner.progressCardData(3, info));
  assert.equal(card.state, "run");
  assert.equal(card.word, "идёт");
  const ahead = plain(loaded.inner.progressCardData(4, info));
  assert.equal(ahead.state, "todo");
  assert.equal(ahead.word, "запланирован");
});
