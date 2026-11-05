// #10315 (К-FL, поле `live` в /digest): кнопка PMP на странице, раздел 460-pmp-panel.js. «Идёт» — по `live`
// приложения (время изменения содержимого сводки, терминал, страница), а не по группе «идут»: группа считается по mtime
// status.md, а его обновляют checkout, pull и `git worktree add`. Поля нет (старое приложение) — по группе, как раньше.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInner, plain } from "./load.mjs";

const NOW = Date.parse("2026-10-20T04:00:00Z");
const flow = (n, state, extra = {}) => ({ n, state, about: `дело ${n}`, steps: "", phase: "", ...extra });
const project = (name, extra) => ({ name, title: name, color: "#336699", workflows: [flow(1, "готово"), flow(2, "идёт", { steps: "1/3" })], ...extra });

test("#10315: live:false при группе «идут» — не «идёт»: ни строки блока Workflow, ни идущих у терминала", () => {
  const { inner } = loadInner();
  const model = plain(inner.pmpModel({ v: 1, projects: [
    project("Stale", { group: "идут", terminal: true, live: false, now: "старое «Сейчас»" }),
    project("Fresh", { group: "идут", terminal: true, live: true }),
  ] }, NOW));
  assert.deepEqual(model.rows.map(row => row.key), ["Fresh"]);
  assert.deepEqual([model.projects, model.flows, model.running], [1, 2, 1]);
  const stale = model.terminals.find(item => item.key === "Stale");
  assert.ok(stale, "живой терминал проекта остаётся в «кто что делает»");
  assert.deepEqual(stale.flows, [], "идущих Workflow у старой сводки нет");
  assert.equal(model.terminals.find(item => item.key === "Fresh").flows.length, 1);
});

test("#10315: live:true при группе не «идут» (сводка по mtime старше суток) — идёт", () => {
  const { inner } = loadInner();
  const model = plain(inner.pmpModel({ v: 1, projects: [project("Run", { group: "тихо", terminal: false, live: true })] }, NOW));
  assert.deepEqual(model.rows.map(row => row.key), ["Run"]);
});

test("#10315: поля live нет (старое приложение) — по группе «идут», как раньше; не boolean — тоже по группе", () => {
  const { inner } = loadInner();
  const model = plain(inner.pmpModel({ v: 1, projects: [
    project("Old", { group: "идут" }),
    project("Quiet", { group: "тихо" }),
    project("Junk", { group: "идут", live: "false" }),
  ] }, NOW));
  assert.deepEqual(model.rows.map(row => row.key), ["Old", "Junk"]);
  assert.deepEqual(model.terminals.map(item => item.key), ["Old", "Junk"], "без поля terminal — «кто что делает» по группе");
});
