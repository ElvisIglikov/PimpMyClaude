// WF103, батч P2 (раздел 12т inject.js; #7941): своя «▶» у команд в вынесенных окнах.
//
// Слово Элвиса: «нету кнопки „запустить“, есть только кнопка „скопировать“».
// Run у Claude — только в главном окне; в вынесенном — своя «▶» рядом с «Copy
// code», на тех же блоках, что у Claude (его код из живого бандла 27.09):
// bash/sh/shell/shellscript/zsh; без языка — «!команда» или первое слово из его
// белого списка без | & ; < > ( ) ` $ \. Только ответы — не поле ввода и не вывод
// инструментов. Запуск — LocalSessions.runBashCommand(чат, команда) моста (у
// попапа через window.opener): в скрытой оболочке этого чата, ход агента не
// запускается; вывод Пимп показывает под блоком сам.
//
// Разметка блока — по коду Claude: div.epitaxy-codeblock > div.relative >
// [div.epitaxy-fence[data-code-text], div > div.sticky > button[aria-label=
// "Copy code"]]; пропсы {text, lang, rawLang} — у компонента шагом выше.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_4bea9b89-e7d5-47c9-b6da-f8996ba484e5";
const RUN = "[data-myclaude-run]";
const OUT = "[data-myclaude-run-out]";

const settle = () => new Promise(resolve => setImmediate(resolve));

const codeBlock = (parent, { text, lang = "text", rawLang = undefined }) => {
  const block = parent.add("div", { class: "epitaxy-codeblock relative max-w-full" });
  block["__reactFiber$test"] = { memoizedProps: { className: "epitaxy-codeblock" }, return: { memoizedProps: { text, lang, rawLang }, return: null } };
  const inner = block.add("div", { class: "relative" });
  inner.add("div", { class: "epitaxy-diff epitaxy-fence rounded-lg", attrs: { "data-code-text": text.trimEnd() } });
  const bar = inner.add("div", { class: "pointer-events-none absolute" }).add("div", { class: "pointer-events-auto sticky flex gap-0.75" });
  const copy = bar.add("button", { class: "cds-button ghost size-base", attrs: { "aria-label": "Copy code" } });
  return { block, bar, copy };
};

// Вынесенное окно (или главное — popout: false) с лентой: ответ с блоками,
// строка инструмента с bash-блоком и поле ввода с блоком кода внутри.
const page = ({ popout = true, bridge = "opener", run = null, blocks = null } = {}) => {
  const calls = [];
  const sessions = {
    runBashCommand: (chat, command) => {
      calls.push([chat, command]);
      return run ? run(chat, command) : Promise.resolve({ stdout: `pimp-run-test\ndev@mac PimpTest102 % `, stderr: "", code: 0 });
    },
    reportRunFollowUp: () => { calls.push(["reportRunFollowUp"]); },
  };
  const opener = bridge === "opener" ? { "claude.web": { LocalSessions: sessions } } : null;
  const nodes = {};
  const loaded = loadInject({
    href: popout ? "about:blank" : `https://claude.ai/epitaxy/${CHAT}`, title: "Четвёртый тест замены окна", opener,
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({});
      const panel = dom.document.body.add("div", { class: "epitaxy-chat-panel", rect: { left: 0, top: 0, width: 600, height: 700 } });
      const titlebar = panel.add("div", { class: "epitaxy-titlebar", rect: { left: 80, top: 0, width: 300, height: 32 } });
      titlebar["__reactFiber$test"] = { memoizedProps: { episodeKey: CHAT }, return: null };
      nodes.titlebar = titlebar;
      const feed = panel.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } });
      const answer = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" } });
      const list = blocks ?? [
        { text: "echo pimp-run-test\n", lang: "bash" },
        { text: "print(1)", lang: "python" },
        { text: "ls -la\n", lang: "text" },
        { text: "echo not-listed", lang: "text" },
      ];
      nodes.blocks = list.map(spec => codeBlock(answer, spec));
      const tool = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_tool" } });
      nodes.tool = codeBlock(tool, { text: "git status", lang: "bash" });
      nodes.composerBlock = codeBlock(parts.editor, { text: "git log", lang: "bash" });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  if (bridge === "self") loaded.win["claude.web"] = { LocalSessions: sessions };
  let t = 5_000_000;
  loaded.win.performance.now = () => t;
  loaded.advance = ms => { t += ms; };
  loaded.tick = () => loaded.inner.runTick(t);
  loaded.calls = calls;
  loaded.nodes = nodes;
  loaded.tick();
  return loaded;
};
const buttons = loaded => loaded.dom.queryAll(RUN);
const press = (loaded, button, extra = {}) => loaded.document.dispatchEvent({ type: "click", target: button, button: 0, detail: 1, ...extra });
const run = loaded => plain(loaded.api.status().run);

test("#7941: блоки как у Claude — bash/sh/shell/shellscript/zsh; без языка — «!» или белый список без | & ; < > ( ) ` $ \\", () => {
  const { runCommandOf } = page().inner;
  assert.equal(runCommandOf({ text: "echo pimp-run-test\n", lang: "bash" }), "echo pimp-run-test", "без последнего перевода строки");
  for (const lang of ["sh", "shell", "shellscript", "zsh", "Bash"]) assert.equal(runCommandOf({ text: "make all", lang }), "make all", lang);
  assert.equal(runCommandOf({ text: "npm test | tee log", lang: "bash" }), null, "bash тоже без метасимволов");
  assert.equal(runCommandOf({ text: "print(1)", lang: "python" }), null);
  assert.equal(runCommandOf({ text: "ls -la\n", lang: "text" }), "ls -la");
  assert.equal(runCommandOf({ text: "git status", rawLang: "", lang: "text" }), "git status", "``` без языка");
  assert.equal(runCommandOf({ text: "sudo FOO=1 npm i", lang: "text" }), "sudo FOO=1 npm i");
  assert.equal(runCommandOf({ text: "./run.sh", lang: "text" }), "./run.sh");
  assert.equal(runCommandOf({ text: "echo hi", lang: "text" }), null, "echo нет в белом списке Claude");
  for (const bad of ["git log | head", "ls && pwd", "ls; pwd", "cat < a", "ls > a", "rm $(x)", "ls `x`", "cd a\\b", "ls (a)"]) {
    assert.equal(runCommandOf({ text: bad, lang: "text" }), null, bad);
  }
  assert.equal(runCommandOf({ text: "! echo hi\n", lang: "text" }), "echo hi", "«!» — команда без самого «!»");
  assert.equal(runCommandOf({ text: "ls‮ -la", lang: "text" }), null, "скрытые символы — нет");
  assert.equal(runCommandOf({ text: "   \n", lang: "bash" }), null, "пустой блок — нет");
  assert.equal(runCommandOf({ text: "ls\nrm -rf build", lang: "text" }), null, "без языка — одна строка (гейт 2)");
  assert.equal(runCommandOf({ text: "ls\npwd", lang: "bash" }), null, "bash тоже одна строка");
});

test("#7941: кнопка — только в вынесенном окне, только в ответе, рядом с «Copy code» и её стилем", () => {
  const loaded = page();
  const list = buttons(loaded);
  assert.equal(list.length, 2, "bash и «ls -la»; python и echo без языка — нет");
  const [first] = loaded.nodes.blocks;
  const own = [...first.bar.children];
  assert.equal(own.indexOf(list[0]), own.indexOf(first.copy) - 1, "прямо перед «Copy code»");
  assert.equal(list[0].className, first.copy.className, "стиль и размер — как у «Copy code»");
  assert.equal(list[0].textContent, "▶");
  assert.equal(loaded.nodes.tool.bar.querySelector(RUN), null, "вывод инструмента — без кнопки");
  assert.equal(loaded.nodes.composerBlock.bar.querySelector(RUN), null, "поле ввода — без кнопки");
  assert.equal(run(loaded).buttons, 2);
  // Повторный тик кнопок не множит.
  loaded.tick();
  assert.equal(buttons(loaded).length, 2);

  const main = page({ popout: false });
  assert.equal(buttons(main).length, 0, "в главном окне Run у самого Claude");
  assert.equal(run(main).buttons, 0);
});

test("#7941: нажатие — runBashCommand этого чата, «…», повтор пустой; вывод под блоком, снова «▶»", async () => {
  let resolve;
  const loaded = page({ run: () => new Promise(done => { resolve = done; }) });
  const [button] = buttons(loaded);
  press(loaded, button);
  assert.deepEqual(loaded.calls, [[CHAT, "echo pimp-run-test"]]);
  assert.equal(button.textContent, "…");
  assert.equal(button.getAttribute("aria-disabled"), "true");
  press(loaded, button);
  press(loaded, button, { detail: 2 });
  assert.equal(loaded.inner.runStart("echo pimp-run-test"), "busy");
  assert.equal(loaded.calls.length, 1, "пока идёт — повтор ничего не делает");
  resolve({ stdout: "pimp-run-test\ndev@mac PimpTest102 % ", stderr: "", code: 0 });
  await settle();
  loaded.tick();
  assert.equal(button.textContent, "▶");
  const out = loaded.nodes.blocks[0].block.querySelector(OUT);
  assert.ok(out, "вывод под блоком");
  assert.equal(out.textContent, "pimp-run-test", "без строки приглашения оболочки");
  const status = run(loaded);
  assert.equal(status.clicks, 1);
  assert.equal(status.runs, 1);
  assert.equal(status.via, "bash");
  assert.equal(status.fails, 0);
  assert.equal(status.last.command, "echo pimp-run-test");
  assert.equal(status.last.state, "done");
  assert.ok(!loaded.calls.some(call => call[0] === "reportRunFollowUp"), "reportRunFollowUp не зовём никогда");
});

test("#7941: «…» снимается через 60 с, сама команда не трогается", () => {
  const loaded = page({ run: () => new Promise(() => {}) });
  const [button] = buttons(loaded);
  press(loaded, button);
  loaded.advance(59_000);
  loaded.tick();
  assert.equal(button.textContent, "…");
  loaded.advance(1_001);
  loaded.tick();
  assert.equal(button.textContent, "▶");
  assert.equal(button.getAttribute("aria-disabled"), "false");
  assert.equal(loaded.calls.length, 1, "ничего не перезапущено и не прервано");
  press(loaded, button);
  assert.equal(loaded.calls.length, 2, "после 60 с можно снова");
});

test("#7941: агент в чате работает — кнопка неактивна, «агент работает»", () => {
  const loaded = page();
  const stop = loaded.document.body.add("button", { attrs: { "data-testid": "chat-input-stop" } });
  loaded.tick();
  const [button] = buttons(loaded);
  assert.equal(button.getAttribute("aria-disabled"), "true");
  assert.equal(button.getAttribute("title"), "агент работает");
  press(loaded, button);
  assert.equal(loaded.inner.runStart("echo pimp-run-test"), "working");
  assert.equal(loaded.calls.length, 0);
  stop.remove();
  loaded.tick();
  assert.equal(button.getAttribute("aria-disabled"), "false");
});

test("#7941: отказ моста — плашка «Не запустилось», без повтора", async () => {
  const refused = page({ run: () => Promise.resolve({ stdout: "", stderr: "", error: "Session not found" }) });
  const [button] = buttons(refused);
  press(refused, button);
  await settle();
  refused.tick();
  assert.equal(button.textContent, "▶");
  assert.equal(run(refused).fails, 1);
  assert.equal(run(refused).last.state, "fail");
  assert.equal(refused.dom.query("#myclaude-new-window-note")?.textContent, "Не запустилось");
  assert.equal(refused.calls.length, 1, "сама не повторяется");
  assert.equal(refused.nodes.blocks[0].block.querySelector(OUT), null);

  const thrown = page({ run: () => Promise.reject(new Error("ipc")) });
  press(thrown, buttons(thrown)[0]);
  await settle();
  assert.equal(run(thrown).fails, 1);

  const none = page({ bridge: "none" });
  assert.equal(none.inner.runStart("echo pimp-run-test"), "no-bridge");
  assert.equal(run(none).fails, 1);
  assert.equal(none.dom.query("#myclaude-new-window-note")?.textContent, "Не запустилось");
});

test("#7941: runBlock(n) для гейта — n-я кнопка окна; мост своего окна тоже годится", () => {
  const loaded = page({ bridge: "self" });
  assert.equal(loaded.api.runBlock(1), "started");
  assert.deepEqual(loaded.calls, [[CHAT, "ls -la"]]);
  assert.equal(loaded.api.runBlock(7), "no-block");
  assert.equal(run(loaded).clicks, 1);
  assert.equal(page({ popout: false }).api.runBlock(0), "no-block");
});

test("#7941: dispose уносит кнопки и вывод", async () => {
  const loaded = page();
  press(loaded, buttons(loaded)[0]);
  await settle();
  loaded.tick();
  assert.equal(loaded.dom.queryAll(OUT).length, 1);
  loaded.api.dispose();
  assert.equal(buttons(loaded).length, 0);
  assert.equal(loaded.dom.queryAll(OUT).length, 0);
});

test("#7941: синтетический click (isTrusted === false) команду не запускает (гейт 2)", () => {
  const loaded = page();
  const [button] = buttons(loaded);
  press(loaded, button, { isTrusted: false });
  assert.deepEqual(loaded.calls, []);
  press(loaded, button);
  assert.equal(loaded.calls.length, 1);
});

// WF111 (судья page): сложный bash-блок или «!» — ▶ есть, клик открывает окошко
// с полным текстом, запуск только оттуда и только доверенным кликом.
const CONFIRM = "#myclaude-run-confirm";
const confirmButton = (loaded, action) => loaded.dom.query(`${CONFIRM} [data-myclaude-run-confirm="${action}"]`);
const trusted = (loaded, target, extra = {}) => press(loaded, target, { isTrusted: true, ...extra });
const esc = loaded => loaded.win.dispatchEvent({ type: "keydown", key: "Escape", code: "Escape", isTrusted: true, bubbles: true, cancelable: true });

test("▶ сложной команды: окошко с полным текстом; «Выполнить» — запуск ровно этого текста", async () => {
  const text = "cd ~/x && bash tools/test.sh | tail -40\necho \"$HOME\" > /tmp/out.txt # хвост длинной строки виден целиком\n";
  const loaded = page({ blocks: [{ text, lang: "bash" }, { text: "ls -la", lang: "bash" }] });
  const [complex, simple] = buttons(loaded);
  assert.equal(buttons(loaded).length, 2, "сложному блоку ▶ тоже есть");
  assert.equal(complex.textContent, "▶");
  assert.equal(complex.getAttribute("title"), "Показать команду целиком и запустить");
  trusted(loaded, complex);
  assert.deepEqual(loaded.calls, [], "клик по ▶ сложной команды сам не запускает");
  const dialog = loaded.dom.query(CONFIRM);
  assert.ok(dialog, "окошко открыто");
  assert.equal(dialog.getAttribute("role"), "dialog");
  const code = dialog.querySelector("pre");
  assert.equal(code.textContent, text.trimEnd(), "полный текст, без обрезки");
  assert.equal(code.style.getPropertyValue("white-space"), "pre-wrap");
  assert.equal(code.style.getPropertyValue("overflow"), "auto");
  assert.match(code.style.getPropertyValue("font"), /monospace/);
  assert.equal(loaded.document.activeElement, confirmButton(loaded, "cancel"), "фокус на «Отмене»");
  assert.equal(run(loaded).confirm, true);
  // Синтетический клик по «Выполнить» ничего не запускает.
  press(loaded, confirmButton(loaded, "run"));
  press(loaded, confirmButton(loaded, "run"), { isTrusted: false });
  assert.deepEqual(loaded.calls, []);
  trusted(loaded, confirmButton(loaded, "run"));
  assert.deepEqual(loaded.calls, [[CHAT, text.trimEnd()]]);
  assert.equal(loaded.dom.query(CONFIRM), null, "запустилось — окошко закрыто");
  assert.equal(complex.textContent, "…");
  await settle();
  loaded.tick();
  assert.ok(loaded.nodes.blocks[0].block.querySelector(OUT), "вывод под блоком, как у простой");
  // Простая однострочная — по-прежнему сразу, без окошка.
  trusted(loaded, simple);
  assert.deepEqual(loaded.calls.at(-1), [CHAT, "ls -la"]);
  assert.equal(loaded.dom.query(CONFIRM), null);
});

test("▶ сложной команды: Esc, «Отмена» и клик мимо — закрыть, ничего не запускать", () => {
  const loaded = page({ blocks: [{ text: "echo $(id)", lang: "bash" }] });
  const [button] = buttons(loaded);
  trusted(loaded, button);
  esc(loaded);
  assert.equal(loaded.dom.query(CONFIRM), null, "Esc — закрыто");
  trusted(loaded, button);
  trusted(loaded, confirmButton(loaded, "cancel"));
  assert.equal(loaded.dom.query(CONFIRM), null, "«Отмена» — закрыто");
  trusted(loaded, button);
  trusted(loaded, loaded.dom.query(CONFIRM));
  assert.equal(loaded.dom.query(CONFIRM), null, "клик мимо окошка — закрыто");
  trusted(loaded, button);
  trusted(loaded, loaded.dom.query(`${CONFIRM} pre`));
  assert.ok(loaded.dom.query(CONFIRM), "клик по тексту команды окошко не закрывает");
  loaded.api.dispose();
  assert.equal(loaded.dom.query(CONFIRM), null, "dispose уносит окошко");
  assert.deepEqual(loaded.calls, []);
});

test("▶ сложной команды: не запустилось — причина в окошке, окошко остаётся; сменился чат — «Выполнить» гаснет", () => {
  const loaded = page({ blocks: [{ text: "ls\npwd", lang: "bash" }] });
  trusted(loaded, buttons(loaded)[0]);
  const stop = loaded.document.body.add("button", { attrs: { "data-testid": "chat-input-stop" } });
  trusted(loaded, confirmButton(loaded, "run"));
  assert.deepEqual(loaded.calls, []);
  const note = loaded.dom.query(`${CONFIRM} [role="alert"]`);
  assert.equal(note.style.getPropertyValue("display"), "block");
  assert.match(note.textContent, /Агент в чате работает/);
  stop.remove();
  trusted(loaded, confirmButton(loaded, "run"));
  assert.deepEqual(loaded.calls, [[CHAT, "ls\npwd"]], "агент закончил — запуск из того же окошка");

  const none = page({ bridge: "none", blocks: [{ text: "ls | wc -l", lang: "bash" }] });
  trusted(none, buttons(none)[0]);
  trusted(none, confirmButton(none, "run"));
  assert.ok(none.dom.query(CONFIRM), "окошко осталось");
  assert.match(none.dom.query(`${CONFIRM} [role="alert"]`).textContent, /Не запустилось/);

  const moved = page({ blocks: [{ text: "ls | wc -l", lang: "bash" }] });
  trusted(moved, buttons(moved)[0]);
  // Окно перешло на другой чат: шапка перерисована с другим id.
  const panel = moved.nodes.titlebar.parentNode;
  moved.nodes.titlebar.remove();
  const bar = panel.add("div", { class: "epitaxy-titlebar", rect: { left: 80, top: 0, width: 300, height: 32 } });
  bar["__reactFiber$test"] = { memoizedProps: { episodeKey: "local_ffffffff-0000-0000-0000-000000000000" }, return: null };
  trusted(moved, confirmButton(moved, "run"));
  assert.deepEqual(moved.calls, []);
  assert.match(moved.dom.query(`${CONFIRM} [role="alert"]`).textContent, /Чат сменился/);
  assert.equal(confirmButton(moved, "run").getAttribute("aria-disabled"), "true");
});

test("▶: скрытые и управляющие символы, «без языка» с метасимволами — без кнопки; runBlock сложной — только окошко", () => {
  for (const [text, lang] of [["ls\rPWD", "bash"], ["ls\u0000", "bash"], ["ls‮ -la\npwd", "bash"], ["git log | head", "text"], ["ls\npwd", "text"], ["echo $(id)", "python"]]) {
    const loaded = page({ blocks: [{ text, lang }] });
    assert.equal(buttons(loaded).length, 0, `${lang}: ${JSON.stringify(text)}`);
    assert.equal(loaded.api.runBlock(0), "no-block");
    loaded.api.dispose();
  }
  for (const [text, lang] of [["ls\npwd", "bash"], ["echo $(id)", "zsh"], ["! echo $(id)", "text"], ["git status | cat", "sh"]]) {
    const loaded = page({ blocks: [{ text, lang }] });
    assert.equal(buttons(loaded).length, 1, `${lang}: ${text}`);
    assert.equal(loaded.api.runBlock(0), "confirm");
    assert.ok(loaded.dom.query(CONFIRM));
    assert.deepEqual(loaded.calls, [], "runBlock сложную не запускает");
    loaded.api.dispose();
  }
});

test("Обкэшить исключает свои узлы, сохраняя совпадающий текст ответа и inline display", () => {
  const loaded = page();
  const answer = loaded.document.body.add("div", { attrs: { "data-testid": "assistant-message" } });
  answer.add("p", { text: "3 ok … — это текст ответа." });
  const run = answer.add("button", { attrs: { "data-myclaude-run": "" }, text: "…" });
  run.style.setProperty("display", "inline-flex", "important");
  answer.add("pre", { attrs: { "data-myclaude-run-out": "" }, text: "3" });
  answer.add("pre", { attrs: { "data-myclaude-run-out": "" }, text: "ok" });
  assert.equal(loaded.inner.runCashout(), true);
  assert.equal(loaded.inner.readCashout().text, "3 ok … — это текст ответа.");
  assert.equal(run.style.getPropertyValue("display"), "inline-flex");
  assert.equal(run.style.getPropertyPriority("display"), "important");
  for (const output of answer.querySelectorAll(OUT)) assert.equal(output.style.getPropertyValue("display"), "");
});
