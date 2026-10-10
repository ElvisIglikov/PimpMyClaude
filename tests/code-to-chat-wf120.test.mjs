// WF120, батч B-P1a (раздел 12с inject.js; #7980): кнопка «→ в чат» у ```-блока
// без языка (или text) в ответе. Блок — текст для чата, не команда: ▶ раздела 12т
// его не берёт (runCommandOf и runComplexOf — null), и не блок передачи «ОТКРОЙ
// НОВЫЙ ЧАТ». Клик — строка «отчёта» через nazhToggle с send: текст в поле, отсчёт
// 5 с, общий отсчёт отправки 12у, отправка; свой текст в поле — только дописать;
// ещё клик или Esc — отмена; двойной клик — одно нажатие; агент работает — кнопка
// неактивна; нет кнопки отправки — плашка; отсчёт выключен — «→ в поле».
//
// Разметка блока — как в run-wf103 (по коду Claude): div.epitaxy-codeblock >
// div.relative > [div.epitaxy-fence[data-code-text], … > div.sticky > button
// [aria-label="Copy code"]]; пропсы {text, lang, rawLang} — у компонента шагом выше.
// Поле и выделение — как в nazhimalki-wf98 (заглушки внутри теста: dom.mjs не трогаем).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_c0de-7980";
const BUTTON = "data-myclaude-nazh-button";
const LABEL = "data-myclaude-nazh-label";
const ON = "data-myclaude-nazh-on";
const TEXT = "Сними сторис с доставки на 10:00";

const codeBlock = (parent, { text, lang = "text", rawLang = "" }) => {
  const block = parent.add("div", { class: "epitaxy-codeblock relative max-w-full" });
  block["__reactFiber$test"] = { memoizedProps: { className: "epitaxy-codeblock" }, return: { memoizedProps: { text, lang, rawLang }, return: null } };
  const inner = block.add("div", { class: "relative" });
  inner.add("div", { class: "epitaxy-diff epitaxy-fence rounded-lg", attrs: { "data-code-text": text.trimEnd() } });
  const bar = inner.add("div", { class: "pointer-events-none absolute" }).add("div", { class: "pointer-events-auto sticky flex gap-0.75" });
  const copy = bar.add("button", { class: "cds-button ghost size-base", attrs: { "aria-label": "Copy code" } });
  return { block, bar, copy };
};

// Главное окно: лента (строка transcript-row/assistant_text), поле ввода, кнопка
// отправки. build(row, dom, parts) кладёт в строку ответа что нужно.
const page = ({ text = "", build = null, send = true, working = false, storage = {} } = {}) => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Trelvis",
    storage: { local: { "myclaude-auto-allow-roam": "off", ...storage } },
    html: dom => {
      const parts = dom.composer({ text });
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } });
      parts.row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" } });
      if (build) build(parts.row, dom, parts);
      else parts.code = codeBlock(parts.row, { text: TEXT });
      if (send) {
        parts.send = parts.modelRow.add("button", { attrs: { "data-testid": "code-prompt-send" }, rect: { left: 1150, top: 700, width: 24, height: 24 } });
        parts.send.__presses = 0;
        parts.send.addEventListener("pointerdown", () => { parts.send.__presses += 1; parts.editor.__text = ""; });
      }
      if (working) parts.stop = dom.document.body.add("button", { attrs: { "data-testid": "code-prompt-stop" } });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  caret(loaded);
  let t = Date.now();
  loaded.inner.nazhTick(t);
  const tick = (step = 500) => { t += step; loaded.inner.nazhTick(t); };
  const click = (node, extra = {}) => {
    loaded.dom.document.dispatchEvent({ type: "click", target: node, detail: 1, isTrusted: true, ...extra });
    t = Date.now();
  };
  return { loaded, parts: loaded.parts, tick, click };
};
// Курсор и выделение в поле, как в Chromium (образец — nazhimalki-wf98): свой текст
// пишется с курсора в конце, хвост выделяется назад Selection.modify.
const caret = loaded => {
  const doc = loaded.dom.document;
  const editor = loaded.parts.editor;
  let start = 0;
  let end = 0;
  doc.createRange = () => {
    const range = {
      end: false, setStart() {}, setEnd() {}, selectNodeContents() {},
      collapse(toStart) { range.end = !toStart; },
      getBoundingClientRect: () => ({ left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0 }),
    };
    return range;
  };
  const selection = {
    rangeCount: 1, getRangeAt: () => null, toString: () => editor.__text.slice(start, end), removeAllRanges() {},
    addRange(range) { start = end = range.end ? editor.__text.length : 0; },
    modify(alter, direction) { if (alter === "extend" && direction === "backward") start = Math.max(0, start - 1); },
  };
  loaded.win.getSelection = () => selection;
  doc.getSelection = () => selection;
  const stock = doc.execCommand;
  doc.execCommand = (name, ui, value) => {
    if ((name !== "insertText" && name !== "delete") || doc.__selectedAll) return stock(name, ui, value);
    if (doc.activeElement !== editor) return false;
    const put = name === "insertText" ? String(value) : "";
    editor.__text = editor.__text.slice(0, start) + put + editor.__text.slice(end);
    start = end = start + put.length;
    return true;
  };
};
const nazh = loaded => plain(loaded.api.status().nazh);
const field = loaded => loaded.parts.editor.textContent;
const codeButtons = loaded => loaded.dom.queryAll(`[${BUTTON}="code"]`);
const label = node => node.getAttribute(LABEL);
// Отсчёт нажималки дотикал (5 с) — пошёл общий счёт 12у; его таймеры — до отправки.
const release = (loaded, tick) => {
  tick(5200);
  assert.equal(loaded.api.status().sendDelay.counting, true, "после 5 с — общий отсчёт отправки");
  for (let n = 0; n < 7; n += 1) loaded.dom.fireKind("timeout");
};

test("#7980: «→ в чат» — у блока без языка и у text, в полосе прямо перед «Copy code»", () => {
  const { loaded, parts } = page({
    build: (row, dom, parts2) => {
      parts2.bare = codeBlock(row, { text: TEXT });
      parts2.text = codeBlock(row, { text: "Проверь окно Рика", rawLang: "text" });
    },
  });
  const list = codeButtons(loaded);
  assert.equal(list.length, 2);
  for (const [block, button] of [[parts.bare, list[0]], [parts.text, list[1]]]) {
    const own = [...block.bar.children];
    assert.equal(own.indexOf(button), own.indexOf(block.copy) - 1, "прямо перед «Copy code»");
    assert.equal(label(button), "→ в чат");
    assert.equal(button.getAttribute("aria-disabled"), null);
    assert.equal(button.textContent, "", "подпись — из атрибута: в копию и «Обкэшить» не попадает");
  }
  // Повторный тик кнопок не множит.
  loaded.inner.nazhTick(Date.now());
  assert.equal(codeButtons(loaded).length, 2);
});

test("#7980: без кнопки — команды (bash, белый список, «!»), другие языки, блок передачи, поле ввода, инструменты, другие строки", () => {
  const { loaded, parts } = page({
    build: (row, dom, parts2) => {
      codeBlock(row, { text: "echo hi\n", lang: "bash", rawLang: "bash" });
      codeBlock(row, { text: "ls -la\n" });
      codeBlock(row, { text: "! echo hi" });
      codeBlock(row, { text: "npm test | tee log", lang: "bash", rawLang: "bash" });
      codeBlock(row, { text: "print(1)", lang: "python", rawLang: "python" });
      codeBlock(row, { text: "   \n" });
      row.add("h2", { text: "🆕 ОТКРОЙ НОВЫЙ ЧАТ" });
      row.add("p", { text: "Модель: Opus 5.5 · 🔥 XHIGH" });
      parts2.handoff = codeBlock(row, { text: "Продолжи работу над WF120 с гейта 1" });
      parts2.after = codeBlock(row, { text: "Второй блок после передачи — обычный" });
      const group = row.add("div", { attrs: { "data-cds": "TurnStatus", "data-state": "done" } });
      codeBlock(group, { text: "вывод инструмента" });
      const tool = row.parentElement.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_tool" } });
      codeBlock(tool, { text: "вывод в строке инструмента" });
      codeBlock(parts2.editor, { text: "блок в поле ввода" });
      // Без пропсов Claude язык неизвестен — кнопки нет.
      const bare = codeBlock(row, { text: "без пропсов" });
      delete bare.block["__reactFiber$test"];
    },
  });
  const list = codeButtons(loaded);
  assert.equal(list.length, 1, "только обычный блок после блока передачи");
  assert.equal(list[0].parentNode, parts.after.bar);
  assert.equal(parts.handoff.bar.querySelector(`[${BUTTON}]`), null, "блок передачи — без кнопки");
});

test("#7980: клик — текст в поле, «→ в чат · 5», через 5 с общий отсчёт, потом отправка", () => {
  const { loaded, parts, tick, click } = page();
  const [button] = codeButtons(loaded);
  click(button);
  assert.equal(field(loaded), TEXT);
  assert.deepEqual([nazh(loaded).armed, nazh(loaded).left, nazh(loaded).lines], [true, 5, [TEXT]]);
  assert.equal(label(button), "→ в чат · 5");
  assert.equal(button.hasAttribute(ON), true, "нажатая — залита");
  tick(1200);
  assert.equal(label(button), "→ в чат · 4");
  tick(3000);
  assert.equal(parts.send.__presses, 0, "рано");
  release(loaded, tick);
  assert.equal(parts.send.__presses, 1);
  assert.deepEqual([nazh(loaded).sends, nazh(loaded).armed, nazh(loaded).lines], [1, false, []]);
  assert.equal(label(codeButtons(loaded)[0]), "→ в чат");
});

test("#7980: многострочный блок сохраняет строки и пробелы при вставке и отправке", () => {
  const { loaded, parts, tick, click } = page({
    build: (row, dom, parts2) => { parts2.code = codeBlock(row, { text: "Сними сторис с доставки\nи поставь новую на 10:00\n" }); },
  });
  click(codeButtons(loaded)[0]);
  assert.equal(field(loaded), "Сними сторис с доставки\nи поставь новую на 10:00\n");
  for (let step = 0; step < 8; step += 1) tick(500);
  assert.equal(nazh(loaded).armed, true, "первый же тик не разоружил («свой текст в поле»)");
  assert.equal(nazh(loaded).skip, null);
  release(loaded, tick);
  assert.equal(parts.send.__presses, 1);
});

test("#7980: свой текст в поле — только дописать, без отсчёта и отправки", () => {
  const { loaded, parts, tick, click } = page({ text: "подожди" });
  click(codeButtons(loaded)[0]);
  assert.equal(field(loaded), `подожди ${TEXT}`);
  assert.equal(nazh(loaded).armed, false);
  assert.equal(nazh(loaded).skip, "свой текст в поле");
  for (let step = 0; step < 30; step += 1) tick();
  assert.equal(parts.send.__presses, 0);
  assert.equal(field(loaded), `подожди ${TEXT}`, "свой текст не тронут");
});

test("#7980: ещё клик — снять текст и отсчёт; двойной клик — одно нажатие", () => {
  const again = page();
  again.click(codeButtons(again.loaded)[0]);
  again.tick(2000);
  again.click(codeButtons(again.loaded)[0]);
  assert.equal(field(again.loaded), "");
  assert.equal(nazh(again.loaded).armed, false);
  for (let step = 0; step < 20; step += 1) again.tick();
  assert.equal(again.parts.send.__presses, 0);

  const double = page();
  const [button] = codeButtons(double.loaded);
  double.click(button);
  double.click(button, { detail: 2 });
  assert.equal(field(double.loaded), TEXT, "второй щелчок двойного не снял строку");
  assert.equal(nazh(double.loaded).armed, true);
  assert.equal(nazh(double.loaded).clicks, 1);
});

test("#7980: Esc в поле во время отсчёта — отмена, текст остаётся, ничего не уходит", () => {
  const { loaded, parts, tick, click } = page();
  click(codeButtons(loaded)[0]);
  loaded.win.dispatchEvent({ type: "keydown", key: "Escape", target: parts.editor, isTrusted: true });
  assert.equal(nazh(loaded).armed, false);
  for (let step = 0; step < 20; step += 1) tick();
  assert.equal(parts.send.__presses, 0);
  assert.equal(field(loaded), TEXT);
});

test("#7980: агент работает — кнопка неактивна, «агент работает», клик ничего не делает; закончил — снова жмётся", () => {
  const { loaded, parts, click } = page({ working: true });
  const [button] = codeButtons(loaded);
  assert.equal(button.getAttribute("aria-disabled"), "true");
  assert.equal(button.getAttribute("title"), "агент работает");
  click(button);
  assert.equal(field(loaded), "");
  assert.equal(nazh(loaded).clicks, 0);
  parts.stop.remove();
  loaded.inner.nazhTick(Date.now());
  assert.equal(button.getAttribute("aria-disabled"), null);
  assert.match(button.getAttribute("title"), /отправлю после отсчёта/);
  click(button);
  assert.equal(field(loaded), TEXT);
});

test("#7980: отсчёт дотикал, а кнопки отправки нет — плашка, текст остаётся", () => {
  const { loaded, tick, click } = page({ send: false });
  click(codeButtons(loaded)[0]);
  tick(5200);
  assert.equal(nazh(loaded).skip, "нет кнопки отправки");
  assert.equal(nazh(loaded).armed, false);
  assert.equal(loaded.document.querySelector("#myclaude-new-window-note")?.textContent, "Нет кнопки отправки — текст в поле, отправь сам");
  assert.equal(field(loaded), TEXT);
  assert.equal(loaded.api.status().sendDelay.counting, false);
});

test("#7980: отсчёт отправки выключен — «→ в поле», подсказка «только впишу»; клик только вписывает", () => {
  const { loaded, parts, tick, click } = page({ storage: { "myclaude-send-delay-off": "1" } });
  const [button] = codeButtons(loaded);
  assert.equal(label(button), "→ в поле");
  assert.match(button.getAttribute("title"), /только впишу/);
  click(button);
  assert.equal(field(loaded), TEXT);
  assert.equal(nazh(loaded).armed, false);
  assert.equal(label(button), "→ в поле", "без цифр отсчёта");
  for (let step = 0; step < 30; step += 1) tick();
  for (let n = 0; n < 7; n += 1) loaded.dom.fireKind("timeout");
  assert.equal(parts.send.__presses, 0);
  assert.equal(field(loaded), TEXT);
  click(codeButtons(loaded)[0]);
  assert.equal(field(loaded), "", "ещё клик — снять");
});

test("#7980: «отчёт» и «→ в чат» сменяют друг друга — в поле одна отправляемая строка", () => {
  const { loaded, click } = page({
    build: (row, dom, parts2) => {
      parts2.code = codeBlock(row, { text: TEXT });
      row.add("h2", { text: "📄 НУЖЕН ОТЧЁТ?" });
      parts2.phrase = row.add("p", { text: "Сделать отчёт файлом? Скажи „отчёт“" });
    },
  });
  click(loaded.dom.queryAll(`[${BUTTON}="report"]`)[0]);
  assert.equal(field(loaded), "отчёт");
  click(codeButtons(loaded)[0]);
  assert.equal(field(loaded), TEXT);
  assert.deepEqual(nazh(loaded).lines, [TEXT]);
  assert.equal(nazh(loaded).armed, true);
});

test("#7980: dispose снимает кнопки, повторный инжект ставит заново и без дублей", () => {
  const { loaded, parts } = page();
  assert.equal(codeButtons(loaded).length, 1);
  loaded.api.dispose();
  assert.equal(codeButtons(loaded).length, 0);
  assert.equal(parts.code.bar.children.length, 1, "в полосе снова только «Copy code»");
  const again = loaded.reload();
  assert.equal(again.error, null, String(again.error?.stack ?? again.error));
  again.inner.nazhTick(Date.now());
  assert.equal(codeButtons(loaded).length, 1);
});

// Вынесенное окно (как в run-wf103): у блока не бывает сразу ▶ из 12т и «→ в чат».
test("#7980: в вынесенном окне — ▶ у команды, «→ в чат» у текста, вместе — никогда", () => {
  const POPOUT = "local_4bea9b89-e7d5-47c9-b6da-f8996ba484e5";
  const sessions = { runBashCommand: () => Promise.resolve({ stdout: "", stderr: "", code: 0 }) };
  const nodes = {};
  const loaded = loadInject({
    href: "about:blank", title: "Вынесенный чат", opener: { "claude.web": { LocalSessions: sessions } },
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({});
      const panel = dom.document.body.add("div", { class: "epitaxy-chat-panel", rect: { left: 0, top: 0, width: 600, height: 700 } });
      const titlebar = panel.add("div", { class: "epitaxy-titlebar", rect: { left: 80, top: 0, width: 300, height: 32 } });
      titlebar["__reactFiber$test"] = { memoizedProps: { episodeKey: POPOUT }, return: null };
      const feed = panel.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } });
      const answer = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" } });
      nodes.blocks = [
        codeBlock(answer, { text: "ls -la\n" }),
        codeBlock(answer, { text: "echo hi\n", lang: "bash", rawLang: "bash" }),
        codeBlock(answer, { text: TEXT }),
      ];
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.inner.runTick(Date.now());
  loaded.inner.nazhTick(Date.now());
  const marks = nodes.blocks.map(({ bar }) => [Boolean(bar.querySelector("[data-myclaude-run]")), Boolean(bar.querySelector(`[${BUTTON}="code"]`))]);
  assert.deepEqual(marks, [[true, false], [true, false], [false, true]]);
});

test("#7980: многострочный свой черновик, пробелы и снятие только своего хвоста", () => {
  const original = "Мой план:\n  один  два\n\tтри  ";
  const code = "Сделай:\n  первый  шаг\n\tвторой\n";
  const { loaded, click } = page({ text: original, build: row => codeBlock(row, { text: code }) });
  click(codeButtons(loaded)[0]);
  assert.equal(field(loaded), `${original} ${code}`);
  assert.equal(nazh(loaded).armed, false);
  click(codeButtons(loaded)[0]);
  assert.equal(field(loaded), original);
});

for (const seconds of [3, 5, 10]) test(`#7980: второй этап ${seconds} с; повторный клик отменяет без дублирования`, () => {
  const { loaded, tick, click, parts } = page();
  loaded.dom.command({ action: "send-delay", on: true, seconds });
  click(codeButtons(loaded)[0]);
  tick(5200);
  assert.equal(loaded.api.status().sendDelay.left, seconds);
  click(codeButtons(loaded)[0]);
  for (let n = 0; n < 12; n++) loaded.dom.fireKind("timeout");
  assert.equal(field(loaded), "");
  assert.equal(parts.send.__presses, 0);
  assert.equal(loaded.api.status().sendDelay.counting, false);
});
