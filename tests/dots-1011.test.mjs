// Ответ-точка (слово Элвиса 11.10 05:40, раздел 12х³ inject.js): «А видишь вот эти пустые точки? Можешь
// тоже их убрать… чтобы их не было? Ничего же не стёрлось?» Служебный ответ чата, весь видимый текст
// которого — одна точка, в ленте не показывается вместе со своими отступами; узлы Claude на местах.
// Разметка — по замеру живого окна 11.10 (Claude 2.31226): строка ленты на блок хода, у блока инструментов
// (спрятан разделом 3а) своя строка — от неё оставался отступ; карточка правок — в строке самой точки.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const DOT = "data-myclaude-dot";
const DONE = "data-myclaude-tool-done";

// rows: [{kind, actions, blocks: [...]}]; блок — {text} | {tools, done} | {card} | {img} | {raw}; actions — в строке
// панель кнопок ответа (Claude держит её в строке последнего блока хода).
const page = (rows, { hideTools = true } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_dots-1011", title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off", ...(hideTools ? {} : { "myclaude.hideTools": "0" }) } },
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: { left: 0, top: 0, width: 800, height: 600 } });
      const made = rows.map((spec, index) => {
        const row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-index": String(index), "data-perf-row": spec.kind ?? "assistant" } });
        const column = row.add("div", { attrs: { role: "article" } }).add("div", { attrs: { "data-epitaxy-entry": "msg_A", "data-epitaxy-item-index": String(index) } });
        if (spec.kind === "human") { column.add("div", { class: "epitaxy-user-turn" }).add("p", { text: spec.blocks[0].text }); return row; }
        const message = column.add("div", { attrs: { "data-transcript-row": "" } }).add("div", { attrs: { "data-cds": "AssistantMessage", "data-turn-key": "msg_A" } });
        if (index === 0) message.add("h2", { class: "sr-only", text: "Claude responded: …" });
        const host = message.add("div", { class: "flex min-w-0 flex-col gap-5" });
        for (const block of spec.blocks) {
          if (block.text != null) {
            const prose = host.add("div", { class: "min-w-0" }).add("div", { class: "prose", attrs: { "data-cds": "Prose" } });
            const body = prose.add("div", { class: "contents", attrs: { "data-alluvium": "true" } });
            for (const line of block.text.split("\n\n")) body.add("p", { text: line });
          } else if (block.tools) {
            // Метку «спрятать» ставит сама страница (раздел 3а): законченная группа — да, идущая — нет.
            host.add("div", { attrs: { "data-cds": "TurnStatus", "data-state": block.done ? "done" : "running", "data-tool-anchor": "toolu_1" } })
              .add("div", { attrs: { "data-cds-row": "" }, text: block.tools });
          } else if (block.card) {
            // Карточка правок: строка на файл — кнопка с именем и «+N −M».
            const item = host.add("div", { class: "contents", attrs: { "data-find-omitted": "" } }).add("ul", { attrs: { role: "list" } }).add("li");
            item.add("span", { class: "contents" }).add("button", { attrs: { type: "button", "data-base-ui-tooltip-trigger": "" }, text: block.card });
            item.add("span", { class: "text-git-added", text: "+121" });
          } else if (block.img) {
            host.add("div", { class: "min-w-0" }).add("img", { attrs: { src: block.img } });
          } else if (block.raw != null) {
            host.add("div", { text: block.raw });
          }
        }
        if (spec.actions) message.add("div").add("div", { attrs: { "data-cds": "MessageActions" }, text: "just now" });
        return row;
      });
      return { ...parts, feed, made };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const before = loaded.parts.feed.innerText;
  loaded.inner.dotPaint();
  return { loaded, before, look: () => loaded.parts.made.map(row => row.getAttribute(DOT)) };
};

test("12х³: ответ из одной точки («·», «.», с пробелами) не показывается; текст ленты тот же, узлы на местах", () => {
  for (const dot of ["·", ".", "  · ", " .\n"]) {
    const { loaded, before, look } = page([
      { blocks: [{ text: "Обычный ответ с делом." }] },
      { blocks: [{ text: dot }] },
      { blocks: [{ text: "Ещё ответ." }] },
    ]);
    assert.deepEqual(look(), [null, "row", null], JSON.stringify(dot));
    assert.equal(loaded.parts.feed.innerText, before, "ничего не стёрто");
    assert.equal(loaded.parts.made[1].parentNode, loaded.parts.feed);
  }
});

test("12х³: любой другой текст остаётся — две точки, многоточие, слово, точка и абзац, тире, реплика человека", () => {
  for (const text of ["..", "…", "Ок.", "·\n\nГотово.", "—", "•", "· ·", "1."]) {
    assert.deepEqual(page([{ blocks: [{ text }] }]).look(), [null], text);
  }
  assert.deepEqual(page([{ kind: "human", blocks: [{ text: "." }] }]).look(), [null], "реплика человека из точки — не ответ чата");
  assert.deepEqual(page([{ blocks: [{ raw: "·" }] }]).look(), [null], "точка не в тексте ответа — незнакомая разметка");
});

test("12х³: спрятанное разделом 3а не в счёт, видимое — строка остаётся; пустые строки над точкой уходят с ней", () => {
  // Со снимка: строка спрятанной группы инструментов (оставался отступ), потом точка с карточкой правок.
  const live = [
    { blocks: [{ text: "Лимит недели — 94 %." }] },
    { blocks: [{ tools: "Ответить «Да» чату", done: true }] },
    { blocks: [{ text: "·" }, { card: "slovo.md" }] },
  ];
  assert.deepEqual(page(live).look(), [null, "gap", "row"]);
  assert.equal(page(live).loaded.dom.queryAll(`[${DONE}]`).length, 2, "группу и карточку пометил раздел 3а");
  // Инструменты показываются (выключатель раздела 3а) — карточка на виду, ответ не из одной точки.
  assert.deepEqual(page(live, { hideTools: false }).look(), [null, null, null]);
  // Группа ещё идёт (метки раздела 3а нет) — на виду: ни она, ни точка рядом с ней не прячутся.
  assert.deepEqual(page([{ blocks: [{ tools: "Running…" }] }, { blocks: [{ text: "·" }] }]).look(), [null, "row"]);
  assert.deepEqual(page([{ blocks: [{ tools: "Running 2 commands" }, { text: "·" }] }]).look(), [null]);
  // Пустая строка без точки под ней остаётся как была; картинка — не пустота.
  assert.deepEqual(page([{ blocks: [{ tools: "Ran", done: true }] }, { blocks: [{ text: "Ответ." }] }]).look(), [null, null]);
  assert.deepEqual(page([{ blocks: [{ img: "a.png" }] }, { blocks: [{ text: "·" }] }]).look(), [null, "row"]);
  assert.deepEqual(page([{ blocks: [{ text: "·" }, { img: "a.png" }] }]).look(), [null]);
  // Несколько точек подряд, у каждой свой шаг.
  assert.deepEqual(page([
    { blocks: [{ tools: "Ran", done: true }] }, { blocks: [{ text: "·" }] },
    { blocks: [{ tools: "Ran", done: true }] }, { blocks: [{ tools: "Ran", done: true }] }, { blocks: [{ text: "·" }] },
  ]).look(), ["gap", "row", "gap", "gap", "row"]);
});

test("12х³: точка дописалась до текста — строка возвращается; уход страницы снимает метки", () => {
  const { loaded, look } = page([{ blocks: [{ tools: "Ran", done: true }] }, { blocks: [{ text: "·" }] }]);
  assert.deepEqual(look(), ["gap", "row"]);
  const para = loaded.dom.queryAll("p").find(node => node.textContent === "·");
  para.textContent = "· Готово, смотри файл.";
  loaded.inner.dotPaint();
  assert.deepEqual(look(), [null, null]);
  para.textContent = "·";
  loaded.inner.readPaint();
  assert.deepEqual(look(), ["gap", "row"], "общий проход ленты размечает и точки");
  loaded.api.dispose();
  assert.deepEqual(look(), [null, null]);
});

test("12х³: точка — последний блок хода: панель кнопок ответа остаётся, не видно только текста; правила", () => {
  const { loaded, before, look } = page([
    { blocks: [{ text: "Ждёт тебя: 4 — лимит недели." }] },
    { blocks: [{ tools: "Ran", done: true }] },
    { actions: true, blocks: [{ text: "·" }, { card: "slovo.md" }] },
  ]);
  assert.deepEqual(look(), [null, "gap", "tail"]);
  const row = loaded.parts.made[2];
  const texts = loaded.dom.queryAll(`[${DOT}="text"]`);
  assert.equal(texts.length, 1);
  assert.equal(texts[0].parentNode.getAttribute("data-cds"), "AssistantMessage", "метка — на колонке текста");
  const actions = loaded.dom.queryAll('[data-cds="MessageActions"]')[0];
  assert.equal(row.contains(actions) && !texts[0].contains(actions), true, "панель кнопок вне спрятанного");
  assert.equal(loaded.parts.feed.innerText, before);
  // Обычный ответ с панелью и точка без панели — как раньше.
  assert.deepEqual(page([{ actions: true, blocks: [{ text: "Ответ." }] }, { blocks: [{ text: "·" }] }]).look(), [null, "row"]);
  const css = loaded.dom.queryAll("style").map(node => node.textContent).join("\n");
  assert.match(css, /\[data-myclaude-dot="row"\],\[data-myclaude-dot="gap"\]\{height:0 !important/);
  assert.match(css, /\[data-myclaude-dot="text"\]\{position:absolute !important;height:0 !important/);
  assert.match(css, /\[data-myclaude-dot="tail"\] \[data-transcript-row\]\{margin-top:6px !important\}/);
  assert.doesNotMatch(css, /\[data-myclaude-dot\]\{/, "строку с панелью общее правило не сворачивает");
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`[${DOT}]`).length, 0);
});
