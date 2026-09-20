// Авто-Allow в странице (раздел 12е inject.js, #6645): имя кнопки и список «не жму сам».
import test from "node:test";
import assert from "node:assert/strict";
import { loadInner } from "./load.mjs";

const { autoAllowLabel, autoAllowBlocked } = loadInner({ title: "Trelvis" }).inner;

test("имя кнопки — без хвоста-подсказки клавиши", () => {
  assert.equal(autoAllowLabel("Always allow 2"), "Always allow");
  assert.equal(autoAllowLabel("  Allow\n 1 "), "Allow");
  assert.equal(autoAllowLabel("Allow once ⌘⏎"), "Allow once");
});

test("не жмём сам: удаление, деньги, git push, запись в файл", () => {
  for (const text of ["Allow Bash to run rm -rf build?", "git rm -r src", "find . -delete", "cd build&&rm -rf *",
    "git push origin main", "DROP TABLE users", "echo x > file.txt", "kaspi_payment_create", "edit invoice"]) {
    assert.ok(autoAllowBlocked(text), text);
  }
});

test("жмём: имена файлов, стрелки и 2>&1 кнопку не глушат", () => {
  for (const text of ["Claude wants to read refunds.md", "cat delete-old.sql", "npm test 2>&1 | tail -5",
    "a -> b => c", "git pushes", "form_submit", "Allow Bash to run ls -la?"]) {
    assert.ok(!autoAllowBlocked(text), text);
  }
});
