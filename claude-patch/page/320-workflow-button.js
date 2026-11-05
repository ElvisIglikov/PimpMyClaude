  // ---- 12а. Кнопка «Workflow» ---------------------------------------------
  // Пункт меню «🚀 Workflow» присылает готовый текст запуска (KICKOFF.md) —
  // страница кладёт его в поле ввода и НЕ отправляет: последнее слово за Элвисом,
  // он дописывает задачу и жмёт сам.
  //
  // Черновик не затираем: текст ложится ПЕРЕД ним (курсор в начало поля) и
  // отделяется пустой строкой. Иначе кнопка съедала бы недописанную мысль.
  const WORKFLOW_TEXT_MAX = 64000;
  const runWorkflowCommand = (detail) => {
    const raw = typeof detail?.text === "string" ? detail.text : "";
    const text = raw.slice(0, WORKFLOW_TEXT_MAX).replace(/\s+$/, "");
    if (!text) { state.workflowResult = "пустой текст"; return false; }
    const editor = state.editor?.isConnected ? state.editor : findEditor();
    if (!editor?.isConnected) { state.workflowResult = "нет редактора"; return false; }
    // Свёрнутое поле сначала возвращаем: вставлять в невидимое поле — значит
    // потерять текст из виду.
    if (state.stage === STAGE_COLLAPSED) setStage(STAGE_NORMAL);
    // Повторный клик (Элвис нажал дважды или команда доехала второй раз): первая
    // строка запуска уже стоит в поле — второй копии там делать нечего.
    const head = text.split("\n").find(line => line.trim() !== "")?.trim() ?? "";
    if (head && rawText(editor).replace(/\s+/g, " ").includes(head.replace(/\s+/g, " "))) {
      state.workflowRuns += 1;
      state.workflowResult = "уже вставлено";
      return true;
    }
    const draft = editorText(editor) !== "";
    const ok = insertIntoEditor(editor, draft ? `${text}\n\n` : text, draft);
    state.workflowRuns += 1;
    state.workflowResult = ok ? (draft ? "вставлено перед черновиком" : "вставлено") : "вставка не удалась";
    if (ok) scheduleLayout();
    return ok;
  };
  // Кнопка «Workflow»: вставок и чем кончилась последняя.
  statusPart("workflow", () => ({ runs: state.workflowRuns, result: state.workflowResult }));
  HATCH && Object.assign(HATCH, { runWorkflowCommand });

