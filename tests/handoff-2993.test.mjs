// Блок «ОТКРОЙ НОВЫЙ ЧАТ» на Claude 2.9939.2 (#7725). Разметка снята пробой
// живого окна 25.09.2026 и обезличена: testid «assistant-message» больше нет,
// одно сообщение ассистента — несколько строк ленты [data-testid="transcript-row"]
// с общим data-epitaxy-entry; aria-label «Message N» только у первой строки
// (вызов инструмента), текст ответа — в строке data-perf-row="assistant_text",
// markdown — div.prose > div[data-alluvium].contents > h2/p/div.epitaxy-codeblock.
// Инлайн-код и чип файла тоже несут data-code-text (с data-epitaxy-inline-code).
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { loadInject, plain } from "./load.mjs";

const fixture = name => JSON.parse(readFileSync(new URL(`./fixtures/cashout/${name}.json`, import.meta.url), "utf8"));
const HANDOFF = fixture("record-handoff").text;
const HEAD = "🆕 ОТКРОЙ НОВЫЙ ЧАТ";
const LINK = "[data-myclaude-continue-link]";
const BOX = "[data-myclaude-continue]";

// Строка ленты с куском сообщения — как в живом окне.
const row = (rows, index, kind, entry, item, label = null) => {
  const outer = rows.add("div", {
    attrs: {
      "data-index": String(index), "data-testid": "transcript-row", "data-perf-row": kind,
      "data-perf-row-streaming": "false",
    },
    rect: { left: 0, top: 100 + index * 60, width: 800, height: 60 },
  });
  const attrs = { "data-epitaxy-entry": entry, "data-entry-key": entry, "data-transcript-column-row": "" };
  if (item != null) attrs["data-epitaxy-item-index"] = String(item);
  if (label) Object.assign(attrs, { role: "article", "aria-label": label, tabindex: "0" });
  const message = outer.add("div", { attrs, class: "mx-auto" })
    .add("div", {})
    .add("div", { class: "group/msg group/message-row flex flex-col w-full relative" });
  return { outer, message };
};
const prose = message => message
  .add("div", { class: "flex flex-col gap-[var(--chat-item-gap)] select-text" })
  .add("div", {})
  .add("div", { class: "prose", attrs: { "data-cds": "Prose", "data-prose-font": "sans" } })
  .add("div", { class: "contents", attrs: { "data-alluvium": "true" } });
const toolRow = (rows, index, entry, label) => {
  const { message } = row(rows, index, "assistant_tool", entry, 0, label);
  message.add("h2", { class: "sr-only select-none", text: "Claude responded: Готово", attrs: { "data-find-omitted": "" } });
  message.add("button", { attrs: { type: "button", "aria-expanded": "false" } }).add("span", { text: "Ran 2 commands" });
};
// Кусок с блоком передачи: заголовок, фраза с чипом файла, «Модель:», блок кода,
// хвостовой повтор заголовка самой последней строкой (ELVIS.md).
const handoffRow = (rows, index, entry, { code = HANDOFF, heads = true, tail = true, kind = "assistant_text" } = {}) => {
  const { message } = row(rows, index, kind, entry, 1);
  const body = prose(message);
  body.add("p", { text: "Сделано, проверено.", attrs: { dir: "ltr" } });
  const got = { heads: [], block: null, body };
  if (heads) got.heads.push(body.add("h2", { text: HEAD, attrs: { dir: "ltr" } }));
  const phrase = body.add("p", { attrs: { dir: "ltr" } });
  phrase.add("span", { text: "Скопируй блок ниже, план — " });
  phrase.add("button", {
    attrs: {
      type: "button", "data-epitaxy-inline-code": "", "data-epitaxy-file-ref": "", "data-code-text": "@docs/plan.md",
    },
  }).add("span", { text: "plan.md" });
  body.add("p", { text: "Модель: Opus 5.5 · EXTRA", attrs: { dir: "ltr" } });
  if (code) {
    got.block = body.add("div", {}).add("div", { class: "epitaxy-codeblock relative max-w-full w-full" });
    got.block.add("div", { class: "relative" })
      .add("div", { class: "epitaxy-diff epitaxy-fence rounded-lg overflow-clip", attrs: { "data-code-text": code }, text: code });
  }
  if (heads && tail) got.heads.push(body.add("h2", { text: HEAD, attrs: { dir: "ltr" } }));
  return got;
};
const page = build => {
  const got = {};
  const loaded = loadInject({
    href: "about:blank", title: "Проект · чат", hasFocus: false,
    html: dom => {
      const parts = dom.composer();
      const rows = dom.document.body
        .add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed", "aria-label": "Chat messages" } })
        .add("div", { attrs: { "data-testid": "transcript-sizer" }, class: "relative epitaxy-transcript-typography" })
        .add("div", { attrs: { "data-testid": "transcript-rows" } });
      build(rows, got);
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  // База заморожена (z8-r01): часы страницы двигает только тест, иначе
  // настоящее время под нагрузкой утекало бы в отсчёт.
  const base = loaded.win.performance.now();
  let shift = 0;
  loaded.win.performance.now = () => base + shift;
  const pass = ({ timers = true } = {}) => {
    shift += 500;
    loaded.win.dispatchEvent({ type: "resize" });
    if (timers) loaded.dom.fireKind("timeout");
    loaded.dom.fireKind("raf");
  };
  pass();
  return { loaded, got, pass };
};
// Живой порядок: вопрос, вызов инструмента («Message N»), текст с блоком,
// карточка фоновой задачи, маркер «N running tasks».
const live = (rows, got, spec = {}) => {
  const human = row(rows, 0, "human", "0f0e0d0c-0000-4000-8000-000000000035", null, "Message 35");
  human.message.add("div", { text: "Сделай срочно." });
  toolRow(rows, 1, "msg_TEST36", "Message 36");
  got.last = handoffRow(rows, 2, "msg_TEST36", spec);
  row(rows, 3, "assistant_other", "msg_TEST36", 2).message
    .add("button", { attrs: { type: "button" } }).add("span", { text: "Build and run tests in background" });
  rows.add("div", { attrs: { "data-index": "4", "data-testid": "transcript-row", "data-perf-row": "marker" } })
    .add("button", { attrs: { type: "button" }, text: "3 running tasks" });
};

test("#7725: 2.9939.2 — ссылка на обоих заголовках и кнопка под блоком", () => {
  const { loaded, got } = page((rows, into) => live(rows, into));
  // Узлы стенда сравниваем через ===: assert при расхождении печатает узел со
  // всем документом и вешает прогон.
  const links = loaded.dom.queryAll(LINK);
  assert.equal(links.length, 2, "верхний и хвостовой заголовок");
  assert.ok(links.every((link, index) => link === got.last.heads[index]), "ссылка — на заголовках блока");
  const boxes = loaded.dom.queryAll(BOX);
  assert.equal(boxes.length, 1, "кнопка одна");
  assert.ok(boxes[0].previousElementSibling === got.last.block, "стоит сразу под .epitaxy-codeblock");
  const status = plain(loaded.api.status().continue);
  assert.equal(status.shown, 1);
  assert.equal(status.link.shown, 2);
});

test("26.09: законченный ход одной строкой data-perf-row=assistant — ссылка и кнопка есть", () => {
  const { loaded, got } = page((rows, into) => {
    row(rows, 0, "human", "0f0e0d0c-0000-4000-8000-000000000035", null, "Message 35").message.add("div", { text: "Сделай." });
    into.last = handoffRow(rows, 1, "msg_TEST36", { kind: "assistant" });
    rows.add("div", { attrs: { "data-index": "2", "data-testid": "transcript-row", "data-perf-row": "marker" } })
      .add("button", { attrs: { type: "button" }, text: "2 running tasks" });
  });
  const links = loaded.dom.queryAll(LINK);
  assert.equal(links.length, 2, "верхний и хвостовой заголовок");
  assert.ok(links.every((link, index) => link === got.last.heads[index]));
  assert.equal(loaded.dom.queryAll(BOX).length, 1, "кнопка под блоком");
});

test("#7725: ⌘B берёт текст блока, а не чип файла; «Модель:» разобрана", () => {
  const { loaded } = page((rows, into) => live(rows, into));
  loaded.dom.command({ id: "c1", action: "cashout", at: "now", scope: "window", title: "Проект · чат", handoff: true });
  const record = JSON.parse(loaded.win.localStorage.getItem("myclaude-cashout"));
  assert.equal(record.text, HANDOFF);
  assert.equal(record.model, "Opus 5.5");
  assert.equal(record.effort, "Extra");
});

test("#7725: блок только в прошлом сообщении — ни ссылки, ни кнопки", () => {
  const { loaded, got } = page((rows, into) => {
    toolRow(rows, 0, "msg_TEST34", "Message 34");
    into.old = handoffRow(rows, 1, "msg_TEST34");
    row(rows, 2, "human", "0f0e0d0c-0000-4000-8000-000000000035", null, "Message 35").message
      .add("div", { text: "Дальше." });
    toolRow(rows, 3, "msg_TEST36", "Message 36");
    prose(row(rows, 4, "assistant_text", "msg_TEST36", 1).message).add("p", { text: "Просто ответ." });
  });
  assert.equal(loaded.dom.queryAll(LINK).length, 0);
  assert.equal(loaded.dom.queryAll(BOX).length, 0);
  for (const head of got.old.heads) assert.equal(head.hasAttribute("data-myclaude-continue-link"), false);
});

test("#7725: заголовок без блока кода — чип файла блоком не считается", () => {
  const { loaded } = page((rows, into) => live(rows, into, { code: "" }));
  assert.equal(loaded.dom.queryAll(LINK).length, 0);
  assert.equal(loaded.dom.queryAll(BOX).length, 0);
});

// WF93-g: блок и хвостовой повтор заголовка — в разных строках одного сообщения.
test("WF93-g: блок, строка инструмента, строка с хвостовым заголовком — одно сообщение: 2 ссылки, 1 кнопка", () => {
  const { loaded, got } = page((rows, into) => {
    row(rows, 0, "human", "0f0e0d0c-0000-4000-8000-000000000035", null, "Message 35").message
      .add("div", { class: "epitaxy-user-turn", text: "Сделай срочно." });
    toolRow(rows, 1, "msg_TEST36", "Message 36");
    into.block = handoffRow(rows, 2, "msg_TEST36", { tail: false });
    into.top = into.block.heads[0];
    toolRow(rows, 3, "msg_TEST36", null);
    into.tail = prose(row(rows, 4, "assistant_text", "msg_TEST36", 3).message)
      .add("h2", { text: HEAD, attrs: { dir: "ltr" } });
    rows.add("div", { attrs: { "data-index": "5", "data-testid": "transcript-row", "data-perf-row": "marker" } })
      .add("button", { attrs: { type: "button" }, text: "3 running tasks" });
  });
  const links = loaded.dom.queryAll(LINK);
  assert.equal(links.length, 2, "верхний заголовок и хвостовой из другой строки");
  assert.ok(links[0] === got.top && links[1] === got.tail);
  const boxes = loaded.dom.queryAll(BOX);
  assert.equal(boxes.length, 1, "кнопка одна");
  assert.ok(boxes[0].previousElementSibling === got.block.block, "под блоком кода");
  loaded.dom.command({ id: "c2", action: "cashout", at: "now", scope: "window", title: "Проект · чат", handoff: true });
  const record = JSON.parse(loaded.win.localStorage.getItem("myclaude-cashout"));
  assert.equal(record.text, HANDOFF);
  assert.equal(record.model, "Opus 5.5");
});

// WF93-g (К1): после реплики человека старый блок — не ответ.
const answered = (rows, into, next) => {
  toolRow(rows, 0, "msg_TEST34", "Message 34");
  into.old = handoffRow(rows, 1, "msg_TEST34");
  row(rows, 2, "human", "0f0e0d0c-0000-4000-8000-000000000035", null, "Message 35").message
    .add("div", { class: "epitaxy-user-turn", text: "Ок, дальше." });
  if (next) toolRow(rows, 3, "msg_TEST36", "Message 36");
};
for (const [name, next] of [["новый ход пока из одних инструментов", true], ["ход ещё не начался", false]]) {
  test(`WF93-g: Элвис ответил, ${name} — под старым блоком ни ссылки, ни кнопки; ⌘B не шлёт старый текст`, () => {
    const { loaded, got } = page((rows, into) => answered(rows, into, next));
    assert.equal(loaded.dom.queryAll(LINK).length, 0);
    assert.equal(loaded.dom.queryAll(BOX).length, 0);
    for (const head of got.old.heads) assert.equal(head.hasAttribute("data-myclaude-continue-link"), false);
    loaded.dom.command({ id: "c3", action: "cashout", at: "now", scope: "window", title: "Проект · чат", handoff: true });
    const record = JSON.parse(loaded.win.localStorage.getItem("myclaude-cashout"));
    assert.equal(record.handoff, true);
    assert.equal(record.text, "", "старый блок не уехал");
  });
}

test("WF93-g: блок пересобран во время «✓» — новая кнопка сразу «✓» и занята", () => {
  const { loaded, got, pass } = page((rows, into) => live(rows, into));
  loaded.document.dispatchEvent({ type: "click", target: loaded.dom.query(`${BOX} button`), bubbles: true, button: 0, detail: 1 });
  loaded.dom.command({ id: "c4", action: "cashout", at: "now", scope: "window", title: "Проект · чат", handoff: true });
  // React пересобрал блок: наша кнопка пропала, проход раскладки ставит новую.
  loaded.dom.query(BOX).remove();
  // Таймер «✓» не трогаем: иначе подпись вернулась бы по сроку, а не осталась.
  pass({ timers: false });
  const button = loaded.dom.query(`${BOX} button`);
  assert.ok(button && button.parentNode.previousElementSibling === got.last.block);
  assert.equal(button.getAttribute("data-myclaude-continue-label"), "✓ Открываю новый чат…");
  assert.equal(button.getAttribute("aria-disabled"), "true");
});
