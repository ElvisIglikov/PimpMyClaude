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

// Решение 👾 Элвиса 22.09.2026 (#7040): список исключений снят целиком, Пимп жмёт ВСЁ.
// Раньше этот файл сторожил обратное — «не жмём удаление, деньги, git push».
test("жмём всё: списка исключений больше нет (решение Элвиса 22.09.2026)", () => {
  for (const text of ["Allow Bash to run rm -rf build?", "git rm -r src", "find . -delete", "cd build&&rm -rf *",
    "git push origin main", "DROP TABLE users", "kaspi_payment_create", "mcp__kaspi__invoice_send",
    "Allow Claude to run Open the 21.09 Ганди Лаваш invoice from debts list?",
    "Claude wants to read refunds.md", "npm test 2>&1 | tail -5", "echo x > file.txt",
    "form_submit", "Allow Bash to run ls -la?"]) {
    assert.ok(!autoAllowBlocked(text), text);
  }
});
