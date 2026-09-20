// Авто-Allow в странице (раздел 12е inject.js, #6645): имя кнопки и список «не жму сам».
import test from "node:test";
import assert from "node:assert/strict";
import { loadInner } from "./load.mjs";

const { autoAllowLabel, autoAllowBlocked } = loadInner({ title: "Trelvis" }).inner;

test("имя кнопки — без хвоста-подсказки клавиши", () => {
  assert.equal(autoAllowLabel("Always allow 2"), "Always allow");
  assert.equal(autoAllowLabel("  Allow\n 1 "), "Allow");
  assert.equal(autoAllowLabel("Allow once ⌘⏎"), "Allow once");
  assert.equal(autoAllowLabel("Always allow2⇧Shift⌘Command⏎Enter"), "Always allow");
  assert.equal(autoAllowLabel("Allow1⏎Enter"), "Allow");
});

test("не жмём сам: удаление, деньги, git push", () => {
  for (const text of ["Allow Bash to run rm -rf build?", "git rm -r src", "find . -delete", "cd build&&rm -rf *",
    "git push origin main", "DROP TABLE users", "kaspi_payment_create", "edit invoice"]) {
    assert.ok(autoAllowBlocked(text), text);
  }
});

test("жмём: имена файлов, стрелки и 2>&1 кнопку не глушат", () => {
  for (const text of ["Claude wants to read refunds.md", "cat delete-old.sql", "npm test 2>&1 | tail -5", "ls x 2>/dev/null | head", "mdfind 'date >= $time.now(-7200)'",
    "a -> b => c", "echo x > file.txt", "s=re.sub(r'<h1>.*?</h1>', x, s)", "git pushes", "form_submit", "Allow Bash to run ls -la?"]) {
    assert.ok(!autoAllowBlocked(text), text);
  }
});
