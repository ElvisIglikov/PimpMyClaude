// Кнопка «🚀 Workflow» (раздел 12а inject.js): текст запуска ложится в поле
// ввода и НЕ отправляется. Черновик Элвиса при этом обязан уцелеть — из-за
// этого вставка идёт перед ним и с пустой строкой между.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const KICKOFF = "🚀 Запуск воркфлоу\nПрочитай правила и предложи план.";
const withComposer = (options = {}) => loadInject({ title: "Trelvis", html: "composer", ...options });

test("пустой текст — вставлять нечего", () => {
  const loaded = withComposer();
  assert.equal(loaded.inner.runWorkflowCommand({ text: "" }), false);
  assert.equal(loaded.api.status().workflow.result, "пустой текст");
  assert.equal(loaded.inner.runWorkflowCommand({ text: "   \n  " }), false, "одни пробелы — тоже пусто");
  assert.equal(loaded.inner.runWorkflowCommand({}), false, "поля text нет вовсе");
  assert.equal(loaded.api.status().workflow.runs, 0, "неудачные попытки не считаются вставками");
});

test("поля ввода на странице нет — команда честно говорит об этом", () => {
  const loaded = loadInject({ title: "Trelvis" });
  assert.equal(loaded.inner.runWorkflowCommand({ text: KICKOFF }), false);
  assert.equal(loaded.api.status().workflow.result, "нет редактора");
});

test("чистое поле: текст ложится целиком", () => {
  const loaded = withComposer();
  assert.equal(loaded.inner.runWorkflowCommand({ text: KICKOFF }), true);
  assert.equal(loaded.api.status().workflow.result, "вставлено");
  assert.equal(loaded.api.status().workflow.runs, 1);
  assert.equal(loaded.parts.editor.innerText, KICKOFF);
});

test("поле с черновиком: вставка ПЕРЕД ним и пустая строка между", () => {
  const loaded = withComposer();
  loaded.parts.editor.innerText = "моя недописанная мысль";
  assert.equal(loaded.inner.runWorkflowCommand({ text: KICKOFF }), true);
  assert.equal(loaded.api.status().workflow.result, "вставлено перед черновиком");
  const text = loaded.parts.editor.innerText;
  assert.equal(text, `${KICKOFF}\n\nмоя недописанная мысль`);
  assert.ok(text.includes("моя недописанная мысль"), "черновик не затёрт");
});

test("повторная команда второй копии не делает", () => {
  const loaded = withComposer();
  loaded.inner.runWorkflowCommand({ text: KICKOFF });
  assert.equal(loaded.inner.runWorkflowCommand({ text: KICKOFF }), true, "повтор не считается ошибкой");
  assert.equal(loaded.api.status().workflow.result, "уже вставлено");
  const copies = loaded.parts.editor.innerText.split("🚀 Запуск воркфлоу").length - 1;
  assert.equal(copies, 1, "в поле ровно одна копия текста запуска");
  assert.equal(loaded.api.status().workflow.runs, 2, "обе команды посчитаны");
});

test("свёрнутое поле разворачивается: вставлять в невидимое поле нельзя", () => {
  const loaded = withComposer();
  loaded.api.setStage(loaded.api.stages.COLLAPSED);
  assert.equal(loaded.api.stage, loaded.api.stages.COLLAPSED);
  assert.equal(loaded.inner.runWorkflowCommand({ text: KICKOFF }), true);
  assert.equal(loaded.api.stage, loaded.api.stages.NORMAL, "поле вернулось на обычную ступень");
  assert.equal(loaded.parts.editor.innerText, KICKOFF);
});

test("длинный текст обрезается до 64000 знаков", () => {
  const loaded = withComposer();
  const long = `${KICKOFF}\n${"я".repeat(70000)}`;
  assert.equal(loaded.inner.runWorkflowCommand({ text: long }), true);
  const text = loaded.parts.editor.innerText;
  assert.equal(text.length, 64000);
  assert.ok(!/\s$/.test(text), "хвостовые пробелы срезаны");
});

test("команда снаружи доходит до поля и адресуется окну", () => {
  const loaded = withComposer();
  loaded.dom.command({ id: "w1", action: "workflow", at: "now", scope: "window", title: "Trelvis", text: KICKOFF });
  assert.equal(loaded.api.status().workflow.runs, 1);
  assert.equal(loaded.parts.editor.innerText, KICKOFF);
  loaded.dom.command({ id: "w2", action: "workflow", at: "now", scope: "window", title: "Другое окно", text: "чужой текст" });
  assert.equal(loaded.api.status().workflow.runs, 1, "команда чужому окну этим окном не берётся");
  assert.ok(!loaded.parts.editor.innerText.includes("чужой текст"));
});

test("текст запуска не отправляется — Enter в поле не летит", () => {
  const loaded = withComposer();
  const keys = [];
  loaded.parts.editor.addEventListener("keydown", event => keys.push(event.key));
  loaded.inner.runWorkflowCommand({ text: KICKOFF });
  assert.deepEqual(keys, [], "ни одного нажатия клавиши");
});
