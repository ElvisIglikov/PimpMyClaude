// WF120, батч B-P1a (раздел 3а inject.js; #7976): «🙈 Прятать инструменты» —
// контракт К-B1. Команда `hide-tools` {on:"true"|"false"} всем окнам; флаг —
// localStorage["myclaude.hideTools"] = "1" | нет ключа; метка — атрибут
// data-myclaude-hide-tools на <html>; прячет правило раздела 4;
// status().hideTools = {on, hidden}.
//
// Разметка — снимок разведки на Маке коллеги 03.10 (recon-7976b.json): своих строк у
// инструментов нет, они ВНУТРИ строки ответа assistant → AssistantMessage →
// div.gap-5: группа TurnStatus (data-state, data-tool-anchor, data-find-omitted)
// и список «Edited N files» (div[data-find-omitted].contents > div > ul[role=list]
// > li > button). Прячутся только законченная группа и список; идёт, ждёт,
// ошибка и всё, где есть чем решать, — видно всегда; текст и блоки кода ответа —
// не трогаем. Сам display:none ставит браузер по правилу (в стабе :has нет):
// здесь проверяем метку, число спрятанного (тот же отбор, что у правила) и правило.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const KEY = "myclaude.hideTools";
const MARK = "data-myclaude-hide-tools";

// Строка ленты с ответом, как на снимке: article → entry → row-gap → transcript-row
// → AssistantMessage → div.gap-5 → [группы, текст, список правок, блок кода].
const answerRow = (feed, index) => {
  const row = feed.add("div", { attrs: { "data-rs-index": String(index), "data-index": String(index), "data-testid": "transcript-row", "data-perf-row": "assistant", "data-perf-row-streaming": "false" } });
  const message = row.add("div", { class: "rounded-lg", attrs: { role: "article", "aria-label": `Message ${index}` } })
    .add("div", { class: "mx-auto", attrs: { "data-epitaxy-entry": `e${index}`, "data-transcript-column-row": "" } })
    .add("div").add("div", { attrs: { "data-row-gap": "own" } })
    .add("div", { attrs: { "data-transcript-row": "" } })
    .add("div", { class: "group/message-row relative flex w-full min-w-0", attrs: { "data-cds": "AssistantMessage", "data-testid": "assistant-message", "data-is-streaming": "false" } });
  return message.add("div", { class: "flex min-w-0 flex-col gap-5 compact:gap-4" });
};
const group = (body, state, text) => {
  const node = body.add("div", {
    class: "group/status flex w-full min-w-0 flex-col",
    attrs: { "data-closed": "", "data-cds": "TurnStatus", "data-item-key": "dfbb51a4:grp", "data-tool-anchor": "toolu_01P9 toolu_016", "data-find-omitted": "", "data-state": state },
  });
  node.add("span", { class: "sr-only", attrs: { role: "status", "aria-live": "polite" }, text });
  node.add("div", { class: "flex min-w-0 gap-xs text-start font-sans", attrs: { "data-cds-row": "" } }).add("bdi", { text });
  return node;
};
const edited = (body, count) => {
  const node = body.add("div", { class: "contents", attrs: { "data-find-omitted": "" } });
  node.add("div", { class: "mt-pad-xs flex w-full select-text flex-col" })
    .add("ul", { class: "flex w-full min-w-0 flex-col", attrs: { role: "list" } })
    .add("li", { class: "relative -mx-pad-xs flex min-w-0 items-center" })
    .add("button", { attrs: { "data-base-ui-tooltip-trigger": "" } })
    .add("span", { class: "min-w-0 truncate text-body text-primary", text: `Edited ${count} files` });
  return node;
};

const page = ({ storage = {} } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_540d6e5d-054b-44d1-8978-d0c457fe55ee", title: "Сайт",
    storage: { local: { "myclaude-auto-allow-roam": "off", ...storage } },
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } });
      const one = answerRow(feed, 40);
      parts.done = group(one, "done", "Ran 2 commands, edited 2 files, finished a background task");
      parts.text = one.add("p", { text: "Отчёт выше." });
      parts.edited = edited(one, 3);
      parts.code = one.add("div", { class: "epitaxy-codeblock relative max-w-full" });
      parts.code.add("div", { class: "epitaxy-fence", attrs: { "data-code-text": "Сними сторис" } });
      feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "human" } }).add("p", { text: "Сделай отчёт" });
      const two = answerRow(feed, 42);
      parts.running = group(two, "running", "Running 1 command…");
      parts.waiting = group(two, "waiting", "Waiting for permission");
      parts.failed = group(two, "error", "Command failed");
      // Законченная группа, а внутри есть чем решать, — видна всегда.
      parts.decision = group(two, "done", "Asked a question");
      parts.decision.add("div", { attrs: { role: "radiogroup" } }).add("button", { attrs: { role: "radio" }, text: "Да" });
      // Пустая обёртка data-find-omitted без списка — не список правок.
      parts.other = two.add("div", { class: "contents", attrs: { "data-find-omitted": "" } });
      parts.other.add("p", { text: "что-то своё" });
      parts.second = group(two, "done", "Read and edited BOARD.md, ran a command");
      // Карточка разрешения живёт у поля ввода, не в ленте.
      parts.card = parts.block.add("div", { class: "epitaxy-approval-card" });
      group(parts.card, "done", "в доке у поля");
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return loaded;
};
const hide = loaded => plain(loaded.api.status().hideTools);
const marked = loaded => loaded.document.documentElement.hasAttribute(MARK);

test("#7976: по умолчанию выключено — ни метки, ни спрятанного", () => {
  const loaded = page();
  assert.deepEqual(hide(loaded), { on: false, hidden: 0 });
  assert.equal(marked(loaded), false);
});

test("#7976: команда on — флаг, метка на <html>; спрятаны две законченные группы и список правок, остальное видно", () => {
  const loaded = page();
  loaded.dom.command({ action: "hide-tools", on: "true" });
  assert.equal(loaded.win.localStorage.getItem(KEY), "1");
  assert.equal(marked(loaded), true);
  assert.deepEqual(hide(loaded), { on: true, hidden: 3 }, "done, second и список «Edited 3 files»; не running/waiting/error, не с выбором, не в доке");
});

test("#7976: команда off — флага и метки нет; мусор в on — выключено", () => {
  const loaded = page({ storage: { [KEY]: "1" } });
  assert.equal(marked(loaded), true, "флаг из прошлого — метка с установки");
  loaded.dom.command({ action: "hide-tools", on: "false" });
  assert.equal(loaded.win.localStorage.getItem(KEY), null);
  assert.equal(marked(loaded), false);
  assert.deepEqual(hide(loaded), { on: false, hidden: 0 });
  loaded.dom.command({ action: "hide-tools", on: "true" });
  loaded.dom.command({ action: "hide-tools", on: "да" });
  assert.equal(marked(loaded), false);
});

test("#7976: группа стала не done или в ней появилось чем решать — уже не спрятана", () => {
  const loaded = page({ storage: { [KEY]: "1" } });
  assert.equal(hide(loaded).hidden, 3);
  loaded.parts.done.setAttribute("data-state", "running");
  assert.equal(hide(loaded).hidden, 1, "Edited тоже виден, пока в этом ответе есть running");
  loaded.parts.second.add("div", { class: "epitaxy-approval-card" }).add("button", { text: "Allow once" });
  assert.equal(hide(loaded).hidden, 0);
  loaded.parts.edited.add("form");
  assert.equal(hide(loaded).hidden, 0);
});

test("#7976: dispose снимает метку, повторный инжект ставит её по флагу", () => {
  const loaded = page({ storage: { [KEY]: "1" } });
  loaded.api.dispose();
  assert.equal(marked(loaded), false);
  const again = loaded.reload();
  assert.equal(again.error, null, String(again.error?.stack ?? again.error));
  assert.equal(marked(loaded), true);
  assert.deepEqual(plain(again.api.status().hideTools), { on: true, hidden: 3 });
});

test("#7976: неизвестные группы, Allow/вопрос/план без form остаются видимыми", () => {
  for (const label of ["Allow once", "Always allow", "AskUserQuestion", "ExitPlanMode", "Выбрать", "Утвердить план"]) {
    const loaded = page({ storage: { [KEY]: "1" } });
    loaded.parts.done.add("button", { text: label });
    assert.equal(hide(loaded).hidden, 2, label);
  }
  const loaded = page({ storage: { [KEY]: "1" } });
  loaded.parts.done.removeAttribute("data-tool-anchor");
  loaded.parts.edited.querySelector("button").textContent = "Выбрать вариант";
  assert.equal(hide(loaded).hidden, 1);
});

test("#7976: storage из соседнего окна сразу включает/выключает настройку", () => {
  const loaded = page();
  loaded.win.localStorage.setItem(KEY, "1");
  loaded.win.dispatchEvent({ type: "storage", key: KEY });
  assert.equal(marked(loaded), true);
  assert.equal(hide(loaded).hidden, 3);
  loaded.win.localStorage.removeItem(KEY);
  loaded.win.dispatchEvent({ type: "storage", key: KEY });
  assert.equal(marked(loaded), false);
  assert.equal(hide(loaded).hidden, 0);
});

test("#7976: Edited рядом с планом и роль alert на самой группе остаются видимыми", () => {
  const loaded = page();
  loaded.parts.edited.add("p", { text: "План: сначала проверь результат, затем продолжай." });
  loaded.parts.done.setAttribute("role", "alert");
  loaded.dom.command({ action: "hide-tools", on: "true" });
  assert.equal(loaded.parts.edited.hasAttribute("data-myclaude-tool-done"), false);
  assert.equal(loaded.parts.done.hasAttribute("data-myclaude-tool-done"), false);
  assert.equal(hide(loaded).hidden, 1);
});
