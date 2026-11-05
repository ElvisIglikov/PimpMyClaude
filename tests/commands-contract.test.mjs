// Команды command.json ↔ ветки разбора страницы (WF248, П1): общий эталон tests/fixtures/commands.json
// (его форму сторожит tests/pimp_fixtures_test.py, Swift-конец — testCommandContractMatchesInjectJS).
//   swift / page-only — у команды есть живой отправитель, ветка `if (action === "…"` в inject.js обязана быть;
//   ax-only — исполняет AX, ветки на странице быть не должно;
//   legacy — живого отправителя нет: ветка может остаться, а может уже отсутствовать (WF248 сняла dictating,
//   neon-style и draft-setup; записи из эталона убирает гейт 1).
// И обратно: каждая ветка страницы записана в эталоне — новая команда без строки в нём краснеет здесь.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { INJECT_PATH } from "./load.mjs";

const SENDERS = new Set(["swift", "page-only", "ax-only", "legacy"]);
const fixture = JSON.parse(readFileSync(new URL("./fixtures/commands.json", import.meta.url), "utf8")).commands;
const inject = readFileSync(INJECT_PATH, "utf8");
// Скобка в примете обязательна, как у Swift-теста: иначе в список попадёт `typeof detail?.action === "string"`.
const branches = new Set([...inject.matchAll(/if \(action === "([^"]+)"/g)].map(hit => hit[1]));

test("эталон команд читается: у каждой записи известный отправитель, команды не повторяются", () => {
  assert.ok(fixture.length > 0);
  assert.equal(new Set(fixture.map(entry => entry.action)).size, fixture.length, "команда дважды");
  for (const entry of fixture) assert.ok(SENDERS.has(entry.sender), `${entry.action}: отправитель «${entry.sender}»`);
  assert.ok(branches.size > 0, "в inject.js не нашлось ни одной ветки if (action === \"…\"");
});

test("у команды с живым отправителем есть ветка страницы; у ax-only — нет", () => {
  for (const { action, sender } of fixture) {
    if (sender === "swift" || sender === "page-only") assert.ok(branches.has(action), `«${action}» (${sender}): ветки в inject.js нет`);
    if (sender === "ax-only") assert.equal(branches.has(action), false, `«${action}» исполняет AX, а ветка в inject.js есть`);
  }
});

test("каждая ветка страницы записана в эталоне; legacy может отсутствовать", () => {
  const known = new Map(fixture.map(entry => [entry.action, entry.sender]));
  for (const branch of [...branches].sort()) {
    assert.ok(known.has(branch), `ветка «${branch}» в inject.js без записи в tests/fixtures/commands.json`);
  }
  // Снятые WF248 ветки — именно legacy: отправителя у них нет, и страница их больше не знает.
  for (const action of ["dictating", "neon-style", "draft-setup"]) {
    if (!known.has(action)) continue;
    assert.equal(known.get(action), "legacy", action);
    assert.equal(branches.has(action), false, `«${action}»: ветка снова в inject.js`);
  }
});
