// WF231 (слово Элвиса 10.10 10:20, раздел 12х¹ inject.js): «Работа идёт» одной строкой. В чате подряд идут
// ответы из одной строки «Работа идёт» вперемежку со служебными строками Claude — вместо них одна
// строка: «Работа идёт» с кольцом и счётом шагов (серия — хвост чата) или «Работа шла» (после неё
// пришёл текст или реплика человека); неудача фоновой команды — заметной меткой; нажатие раскрывает.
// Заодно — длинной полосы слева у дорожки «Прочитано» в покое больше нет.
//
// Разметка — по замеру живого окна 10.10 (Claude 2.31226): ход ассистента — список блоков (пропс
// entries над лентой, у хода items: text | tools | task_event). Старый ход лента держит строкой на
// блок (у колонки data-epitaxy-item-index), последний — одной строкой: блоки подряд в колонке сообщения.
// Текст — блок с [data-cds=Prose] (в обёртке .min-w-0 или в обёртке без своего вида); группа
// инструментов — [data-cds=TurnStatus]; строка фоновых команд — button[data-transcript-keeps-pin].
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const WORK = "data-myclaude-work";
const LINE = "data-myclaude-work-line";
const PART = "data-myclaude-work-part";
const TEXT = "data-myclaude-work-text";
const ZONE = "data-myclaude-read-zone";
const READ_KEY = "myclaude-read-v1";
const CHAT = "id:local_work-2310";
const CLOUD = "Работа идёт 💭";

const T = (value = "Обычный ответ с делом.") => ({ kind: "text", text: value });
const R = (value = CLOUD) => ({ kind: "text", text: value, step: true });
const tools = (label = "Ran 2 commands") => ({ kind: "tools", label });
const task = (status = "completed") => ({ kind: "task_event", status });
const card = (file = "50.html") => ({ kind: "tools", card: file });
const user = (id, text = "вопрос") => ({ id, author: "user", text });
const answer = (id, layout, ...items) => ({ id, author: "assistant", layout, items });

// Блоки хода, как их кладёт Claude: подряд идущие фоновые команды — одной строкой.
const blocksOf = entry => {
  const out = [];
  entry.items.forEach((item, index) => {
    const last = out[out.length - 1];
    if (item.kind === "task_event" && last?.group) { last.group.push(item); return; }
    out.push(item.kind === "task_event" ? { index, group: [item] } : { index, item });
  });
  return out;
};

// mount(index, entry, block) — строка ленты в DOM или нет (виртуальная лента); fiber: false — списка
// ходов нет; responding — идёт ответ; atBottom — лента стоит у низа.
const page = ({ entries, mount = () => true, fiber = true, responding = false, storage = {}, title = "Rick", atBottom = false, tick = true } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_work-2310", title,
    storage: { local: { "myclaude-auto-allow-roam": "off", ...storage } },
    html: dom => {
      const parts = dom.composer({});
      const dock = dom.document.body.add("div", { class: "group/approval-dock relative", rect: { left: 0, top: 600, width: 800, height: 180 } });
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: { left: 0, top: 0, width: 800, height: 600 } });
      feed.clientHeight = 600;
      feed.scrollHeight = atBottom ? 600 : 9000;
      const made = new Map();
      let index = 0;
      let top = 20;
      let textForm = 0;
      const block = (host, entry, item, k) => {
        const out = { item, index: k };
        if (item.group) {
          const wrap = host.add("div", { class: "flex min-w-0 flex-col", attrs: { "data-find-omitted": "" } });
          const button = wrap.add("div", { class: "flex min-w-0 flex-col" }).add("button", { class: "group/tool", attrs: { type: "button", "data-transcript-keeps-pin": "" } });
          const failed = item.group.filter(one => one.status === "failed").length;
          const running = item.group.filter(one => one.status === "running").length;
          button.add("span", { text: `${item.group.length - failed - running} background commands completed` });
          if (running) button.add("span", { text: `, ${running} running` });
          if (failed) button.add("span", { class: "whitespace-nowrap text-danger", text: `, ${failed} failed` });
          return { ...out, node: wrap, button };
        }
        const one = item.item;
        if (one.kind === "text") {
          // Две формы текста живого окна — по очереди.
          const wrapped = (textForm += 1) % 2 === 1;
          const node = wrapped ? host.add("div", { class: "min-w-0" })
            : host.add("div", { class: "contents", attrs: { "data-transcript-engine-root": "", "data-item-key": `${entry.id}:t${k << 16 | 1}` } });
          const inner = wrapped ? node : node.add("div", { class: "contents" }).add("div", { attrs: { "data-engine-native": "AssistantMessage" } });
          const prose = inner.add("div", { class: "prose", attrs: { "data-cds": "Prose", "data-prose-font": "sans" } });
          const body = prose.add("div", { class: "contents", attrs: { "data-alluvium": "true" } });
          const paras = [];
          for (const line of [].concat(one.html ?? one.text.split("\n\n"))) {
            paras.push(typeof line === "function" ? line(body, dom) : body.add("p", { attrs: { dir: "ltr" }, text: line }));
            body.appendChild(dom.document.createTextNode("\n"));
          }
          return { ...out, node, prose, paras, target: wrapped ? node : prose };
        }
        if (one.card) {
          const wrap = host.add("div", { class: "flex min-w-0 flex-col", attrs: { "data-find-omitted": "" } });
          const keyed = wrap.add("div", { attrs: { "data-item-key": `${entry.id}:card:toolu_${k}`, "data-tool-anchor": `toolu_${k}` } });
          keyed.add("div", { class: "epitaxy-markdown" }).add("p", { text: "Файл готов" });
          keyed.add("button", { attrs: { type: "button", title: `/docs/${one.card}` }, text: one.card });
          return { ...out, node: wrap, card: true };
        }
        const node = host.add("div", { class: "group/status flex w-full min-w-0 flex-col", attrs: { "data-cds": "TurnStatus", "data-closed": "", "data-state": "done", "data-item-key": `${entry.id}:grp:toolu_${k}` } });
        node.add("div", { attrs: { "data-cds-row": "" } }).add("button", { attrs: { type: "button", "data-cds-row-toggle": "", "aria-expanded": "false" }, text: one.label });
        // Пустая обёртка без своего вида — Claude кладёт её после группы.
        host.add("div", { class: "contents", attrs: { "data-find-omitted": "" } });
        return { ...out, node };
      };
      entries.forEach((entry, at) => {
        const row = (kind, itemIndex, height = 40) => {
          const mine = index;
          const place = top;
          index += 1;
          top += height;
          const node = feed.add("div", {
            attrs: { "data-testid": "transcript-row", "data-index": String(mine), "data-perf-row": kind, "data-perf-row-streaming": "false" },
            rect: { left: 0, top: place, width: 800, height },
          });
          const column = node.add("div", { attrs: { role: "article" } }).add("div", {
            attrs: { "data-epitaxy-entry": entry.id, "data-epitaxy-entry-index": String(at), ...(itemIndex == null ? {} : { "data-epitaxy-item-index": String(itemIndex) }), "data-transcript-column-row": "" },
          });
          return { node, column, place, height };
        };
        const message = (made2, first, actions) => {
          const node = made2.column.add("div", { attrs: { "data-row-gap": "own" } }).add("div", { attrs: { "data-transcript-row": "" } }).add("div", {
            class: "group/message-row relative flex w-full min-w-0 flex-col gap-xs",
            attrs: { "data-cds": "AssistantMessage", "data-testid": "assistant-message", "data-turn-key": entry.id },
            rect: { left: 24, top: made2.place, width: 752, height: made2.height },
          });
          if (first) node.add("h2", { class: "sr-only select-none", attrs: { "data-find-omitted": "" } });
          const host = node.add("div", { class: "flex min-w-0 flex-col gap-5" });
          const tail = actions ? node.add("div").add("div", { attrs: { "data-cds": "MessageActions", "data-testid": "message-actions" } }) : null;
          return { node, host, tail };
        };
        if (entry.author === "user") {
          const made2 = row("human", null);
          made2.column.add("div", { class: "epitaxy-user-turn" }).add("p", { text: entry.text });
          made.set(entry.id, { rows: [made2.node], blocks: [] });
          return;
        }
        const blocks = blocksOf(entry);
        const info = { rows: [], blocks: [], hosts: [] };
        made.set(entry.id, info);
        if (entry.layout === "split") {
          blocks.forEach((item, k) => {
            if (!mount(index, entry, item)) { index += 1; top += 40; info.blocks.push(null); return; }
            const made2 = row("assistant", item.index);
            const box = message(made2, k === 0, k === blocks.length - 1);
            info.rows.push(made2.node);
            info.hosts.push(box.host);
            info.blocks.push({ ...block(box.host, entry, item, item.index), row: made2.node, host: box.host });
          });
        } else {
          if (!mount(index, entry, null)) { index += 1; return; }
          const made2 = row("assistant", null, 40 * blocks.length);
          const box = message(made2, true, true);
          info.rows.push(made2.node);
          info.hosts.push(box.host);
          for (const item of blocks) info.blocks.push({ ...block(box.host, entry, item, item.index), row: made2.node, host: box.host });
        }
      });
      if (fiber) {
        feed.__reactFiber$test = { memoizedProps: {}, return: { memoizedProps: {
          entries: entries.map(entry => ({
            id: entry.id, author: entry.author,
            items: entry.author === "user" ? [{ id: entry.id, kind: "text", text: entry.text }]
              : entry.items.map((item, k) => ({ id: `${entry.id}-i${k}`, kind: item.kind, ...(item.kind === "text" ? { text: item.text } : {}), ...(item.kind === "task_event" ? { status: item.status } : {}) })),
          })),
          isResponding: responding, olderHistoryAbove: false,
        }, return: null } };
      }
      return { ...parts, dock, feed, made };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const before = loaded.parts.feed.innerText;
  if (tick) loaded.inner.readTick();
  const of = id => loaded.parts.made.get(id);
  // Блок хода по номеру его первого item.
  const at = (id, index) => of(id).blocks.find(item => item?.index === index) ?? null;
  const lines = () => loaded.dom.queryAll(`[${LINE}]`);
  const part = (line, name) => [...line.children].find(node => node.getAttribute(PART) === name);
  const say = line => ["arrow", "label", "steps", "failed"].map(name => part(line, name).getAttribute(TEXT)).filter(Boolean).join(" ");
  const look = (id, index) => { const item = at(id, index); return (item.target ?? item.node).getAttribute(WORK); };
  const click = (node, extra = {}) => loaded.dom.document.dispatchEvent({ type: "click", target: node, detail: 1, isTrusted: true, ...extra });
  const key = (name, target, extra = {}) => ({ defaultPrevented: !loaded.win.dispatchEvent({ type: "keydown", key: name, target, isTrusted: true, bubbles: true, cancelable: true, ...extra }) });
  const work = () => plain(loaded.api.status().work);
  return { loaded, parts: loaded.parts, before, of, at, lines, part, say, look, click, key, work, tick: () => loaded.inner.readTick() };
};

// Серия со снимка: шаги — блоки 2, 5, 21, 27 и (с неудачей) 34.
const SERIES = fail => [
  tools("Ran an agent, finished a background command"), R(),
  task(), tools("Used 2 tools"), R(),
  ...Array.from({ length: 15 }, () => task()), R(),
  ...Array.from({ length: 4 }, () => task()), task("running"), R(),
  ...(fail ? [...Array.from({ length: 5 }, () => task()), task("failed"), R()] : []),
];
const TAIL = (fail = false, layout = "whole") => [user("u1"), answer("msg_A", layout, T("Раздаю утренние дела."), ...SERIES(fail))];
const MIDDLE = (fail = false, layout = "split") => [
  user("u1"), answer("msg_A", layout, T("Раздаю утренние дела."), ...SERIES(fail), tools("Ran 2 commands"), T("Текст для ноута проверен.")),
  user("u2"), answer("msg_B", "whole", tools("Read 2 files"), T("Текст — в файле 58.")),
];

// ---- модель: чистые функции через люк -----------------------------------------
const { inner } = loadInject({ title: "Rick" });
const series = (items, partial) => plain(inner.workSeriesOf(items, partial));

test("12х¹: строка «Работа идёт» — с облачком или без, с точкой или без; служебные хвосты К-CA не в счёт; текст с делом — нет", () => {
  for (const text of ["Работа идёт 💭", "Работа идёт", "Работа идёт.", "Работа идёт 💭.", "Работа идёт… 💭", "  Работа  идёт 💭  ", "**Работа идёт** 💭",
    "Работа идёт 💭\n\n⚪PimpMyClaude · WF 2 из 3 · идёт 💭", "Работа идёт 💭\nКонтекст 226K\nИз кэша 96% · Новых 238K\nОтвет 6.0M · Чат 6.0M · Opus 5.5 HIGH 💭"]) {
    assert.equal(inner.workTextIs(text), true, text);
  }
  for (const text of ["", "Работа", "Работа идёт полным ходом", "Сделал шапку.\n\nРабота идёт 💭", "Работа идёт 💭\n\nЖду твоего слова.", "Работа идёт 💭\nРабота идёт 💭",
    "работа стоит", `${"Длинный ответ. ".repeat(40)}\nРабота идёт 💭`, null, undefined]) {
    assert.equal(inner.workTextIs(text), false, String(text).slice(0, 40));
  }
  // Блок ещё печатается: начало строки уже считается ею, готовая строка — и подавно; текст с делом — нет.
  assert.equal(inner.workTextIs("Работа и", true), true);
  assert.equal(inner.workTextIs("Работа идёт 💭", true), true);
  assert.equal(inner.workTextIs("Работаю над", true), false);
  assert.equal(inner.workTextIs("Работа и"), false, "законченный блок — только целая строка");
});

test("12х¹: серия — два и больше «Работа идёт» без обычного текста между ними; один — не серия", () => {
  assert.deepEqual(series([T(), tools(), R()]), [], "один шаг — облачко остаётся как есть");
  assert.deepEqual(series([R()]), []);
  assert.deepEqual(series([]), []);
  assert.deepEqual(series(null), []);
  assert.deepEqual(series([R(), R()]), [{ from: 0, first: 0, steps: 2, failed: 0, to: 1, tail: true }]);
  // Служебное между шагами и по краям — в серии: от блока после прошлого текста до блока перед следующим.
  assert.deepEqual(series([T(), task(), tools(), R(), task(), task(), R(), tools(), T()]), [{ from: 1, first: 3, steps: 2, failed: 0, to: 7, tail: false }]);
  // Со снимка: пять шагов, упавшая фоновая команда, серия — хвост хода.
  assert.deepEqual(series([T(), ...SERIES(true)]), [{ from: 1, first: 2, steps: 5, failed: 1, to: 34, tail: true }]);
});

test("12х¹: обычный ответ рвёт серию; ответ с текстом и «Работа идёт» в конце — не шаг; незнакомый блок рвёт", () => {
  // Шаг, обычный ответ, шаг — серии нет ни с одной стороны.
  assert.deepEqual(series([R(), task(), T(), task(), R()]), []);
  // Две серии в одном ходе, между ними обычный ответ.
  assert.deepEqual(series([R(), R(), T(), R(), task("failed"), R(), R()]), [
    { from: 0, first: 0, steps: 2, failed: 0, to: 1, tail: false },
    { from: 3, first: 3, steps: 3, failed: 1, to: 6, tail: true },
  ]);
  // Длинный текст, где «Работа идёт» — последняя строка, — обычный ответ: рвёт и сам в серию не входит.
  assert.deepEqual(series([R(), T("Сделал шапку и поле.\n\nРабота идёт 💭"), R()]), []);
  assert.deepEqual(series([R(), R(), T("Сделал шапку.\n\nРабота идёт 💭")]), [{ from: 0, first: 0, steps: 2, failed: 0, to: 1, tail: false }]);
  // Блок незнакомого вида (картинка человека, что-то новое у Claude) рвёт серию и в неё не входит.
  assert.deepEqual(series([R(), { kind: "image" }, R()]), []);
  assert.deepEqual(series([R(), R(), { kind: "thinking" }, tools()]), [{ from: 0, first: 0, steps: 2, failed: 0, to: 1, tail: false }]);
  // Недописанная строка считается шагом, только пока ход пишется и она — последний блок.
  assert.deepEqual(series([R(), T("Работа ид")]), []);
  assert.deepEqual(series([R(), T("Работа ид")], true), [{ from: 0, first: 0, steps: 2, failed: 0, to: 1, tail: true }]);
  assert.deepEqual(series([R(), T("Работа ид"), tools()], true), [], "за недописанным уже пришёл блок — это обычный текст");
});

test("12х¹: реплика человека рвёт серию — счёт идёт по ходам; живая — только серия в хвосте последнего хода", () => {
  // Шаг, реплика, шаг: в каждом ходе по одному — серии нет.
  const split = page({ entries: [user("u1"), answer("msg_A", "whole", R()), user("u2"), answer("msg_B", "whole", R())] });
  assert.deepEqual(split.work(), { series: 0, folded: 0, live: false, failed: 0, lastError: null });
  assert.equal(split.lines().length, 0);
  // Серия — хвост чата: работа идёт.
  const tail = page({ entries: TAIL() });
  assert.deepEqual(tail.work(), { series: 1, folded: 1, live: true, failed: 0, lastError: null });
  // После серии пришёл ответ, потом реплика: работа шла.
  const middle = page({ entries: MIDDLE() });
  assert.deepEqual(middle.work(), { series: 1, folded: 1, live: false, failed: 0, lastError: null });
  // Серия дошла до конца своего хода, но после него — реплика человека: уже не хвост чата.
  const answered = page({ entries: [...TAIL(), user("u2")] });
  assert.equal(answered.work().live, false);
  assert.equal(answered.lines()[0].getAttribute(LINE), "done");
});

// ---- одна строка на месте серии ---------------------------------------------------
test("12х¹: серия в хвосте чата — одна строка «Работа идёт» с кольцом и счётом шагов; узлы Claude на местах", () => {
  const { parts, of, at, lines, part, say, look, work } = page({ entries: TAIL() });
  assert.equal(lines().length, 1, "строка одна");
  const line = lines()[0];
  assert.equal(line.getAttribute(LINE), "live");
  assert.equal(say(line), "▸ Работа идёт · 4 шага");
  assert.equal(part(line, "failed").hasAttribute(TEXT), false, "неудачи нет — метки нет");
  assert.ok(part(line, "ring"), "кольцо — своя часть строки");
  assert.equal(line.getAttribute("role"), "button");
  assert.equal(line.getAttribute("tabindex"), "0");
  assert.equal(line.getAttribute("aria-expanded"), "false");
  assert.equal(line.getAttribute("aria-label"), "Работа идёт, 4 шага");
  assert.equal(line.getAttribute("title"), "Показать шаги");
  assert.equal(line.textContent, "", "текста в строке нет: копия и разбор ленты её не видят");
  // Стоит в колонке блоков хода, перед первым блоком серии (группа инструментов, блок 1).
  const host = of("msg_A").hosts[0];
  assert.equal(line.parentNode, host);
  assert.equal(line.nextElementSibling, at("msg_A", 1).node);
  // Спрятаны шаги, группы инструментов и строки фоновых команд; обычный ответ — нет.
  assert.equal(look("msg_A", 0), null, "обычный ответ перед серией на виду");
  for (const index of [1, 2, 3, 4, 5, 6, 21, 22, 27]) assert.equal(look("msg_A", index), "rest", `блок ${index}`);
  // Шаг в обёртке без своего вида помечен на самом тексте, шаг в своей обёртке — на ней.
  assert.equal(at("msg_A", 5).target, at("msg_A", 5).node, "блок 5 — текст в обёртке .min-w-0");
  assert.notEqual(at("msg_A", 2).target, at("msg_A", 2).node, "блок 2 — обёртка без своего вида: метка на тексте");
  assert.equal(at("msg_A", 2).node.hasAttribute(WORK), false);
  // Строка ленты одна на весь ход — она не прячется.
  assert.equal(of("msg_A").rows[0].hasAttribute(WORK), false);
  // Узлы Claude не удалены и не переставлены: блоки — те же и в том же порядке, своя строка — между ними.
  const kids = [...host.children].filter(node => !node.hasAttribute(LINE));
  assert.deepEqual(kids.filter(node => of("msg_A").blocks.some(item => item.node === node)), of("msg_A").blocks.map(item => item.node));
  assert.ok(parts.feed.isConnected);
  assert.deepEqual(work(), { series: 1, folded: 1, live: true, failed: 0, lastError: null });
});

test("12х¹: серия уже не хвост — та же строка без вращения: «Работа шла · N шагов»; ход по строке ленты на блок", () => {
  const { of, at, lines, say, look } = page({ entries: MIDDLE() });
  assert.equal(lines().length, 1);
  const line = lines()[0];
  assert.equal(line.getAttribute(LINE), "done");
  assert.equal(say(line), "▸ Работа шла · 4 шага");
  assert.equal(line.getAttribute("aria-label"), "Работа шла, 4 шага");
  // Строка-сводка — в первой строке ленты серии; остальные строки серии — нулевой высоты.
  const head = at("msg_A", 1);
  assert.equal(line.parentNode, head.host);
  assert.equal(head.row.hasAttribute(WORK), false, "строка со сводкой видна");
  assert.equal(look("msg_A", 1), "rest", "её блок спрятан");
  for (const index of [2, 3, 4, 5, 6, 21, 22, 27, 28]) assert.equal(at("msg_A", index).row.getAttribute(WORK), "row", `строка блока ${index}`);
  // Обычные ответы до и после — на виду.
  assert.equal(at("msg_A", 0).row.hasAttribute(WORK), false);
  assert.equal(at("msg_A", 29).row.hasAttribute(WORK), false);
  assert.equal(look("msg_A", 29), null);
  assert.equal(of("msg_B").rows[0].hasAttribute(WORK), false);
  assert.equal(look("msg_B", 1), null);
});

test("12х¹: в серии упала фоновая команда — на строке метка «N не вышло»", () => {
  const live = page({ entries: TAIL(true) });
  assert.equal(live.say(live.lines()[0]), "▸ Работа идёт · 5 шагов 1 не вышло");
  assert.equal(live.lines()[0].getAttribute("aria-label"), "Работа идёт, 5 шагов, 1 не вышло");
  assert.deepEqual(live.work(), { series: 1, folded: 1, live: true, failed: 1, lastError: null });
  const done = page({ entries: MIDDLE(true) });
  assert.equal(done.say(done.lines()[0]), "▸ Работа шла · 5 шагов 1 не вышло");
  // Упало две — так и сказано; счёт шагов склоняется.
  const two = page({ entries: [user("u1"), answer("msg_A", "whole", R(), task("failed"), R(), task("failed"), task())] });
  assert.equal(two.say(two.lines()[0]), "▸ Работа идёт · 2 шага 2 не вышло");
  const many = page({ entries: [user("u1"), answer("msg_A", "whole", ...Array.from({ length: 21 }, () => R()))] });
  assert.equal(many.say(many.lines()[0]), "▸ Работа идёт · 21 шаг");
});

test("12х¹: одиночный «Работа идёт» и ответ с текстом не трогаются; карточка файла внутри серии остаётся на виду", () => {
  // Один шаг — облачко как было; обычный ответ с «Работа идёт» в конце — тоже.
  const one = page({ entries: [user("u1"), answer("msg_A", "whole", T(), tools(), R(), task()), user("u2"), answer("msg_B", "split", T("Сделал.\n\nРабота идёт 💭"), R())] });
  assert.equal(one.lines().length, 0);
  assert.equal(one.loaded.dom.queryAll(`[${WORK}]`).length, 0);
  assert.deepEqual(one.work(), { series: 0, folded: 0, live: false, failed: 0, lastError: null });
  // Карточка файла между шагами — содержимое, а не служебная строка: серия её не прячет.
  for (const layout of ["whole", "split"]) {
    const made = page({ entries: [user("u1"), answer("msg_A", layout, T(), R(), card("50.html"), task(), R(), tools())] });
    assert.equal(made.lines().length, 1, layout);
    assert.equal(made.say(made.lines()[0]), "▸ Работа идёт · 2 шага");
    assert.equal(made.look("msg_A", 1), "rest");
    assert.equal(made.look("msg_A", 2), null, `карточка на виду (${layout})`);
    assert.equal(made.at("msg_A", 2).row.hasAttribute(WORK), false, "и её строка ленты тоже");
    assert.equal(made.look("msg_A", 3), "rest");
    assert.equal(made.look("msg_A", 5), "rest");
  }
});

test("12х¹: нажатие, Enter и пробел раскрывают серию и сворачивают обратно; раскрытое помнится; плашка «running» доступна", () => {
  const { loaded, at, lines, part, look, click, key, work, tick } = page({ entries: TAIL(true) });
  const line = lines()[0];
  click(part(line, "label"));
  assert.equal(line.getAttribute("aria-expanded"), "true");
  assert.equal(part(line, "arrow").getAttribute(TEXT), "▾");
  assert.equal(line.getAttribute("title"), "Свернуть шаги");
  assert.equal(lines()[0], line, "строка та же и на том же месте");
  assert.equal(line.nextElementSibling, at("msg_A", 1).node);
  // Раскрытое — под полосой: первый блок помечен особо (линия от его верха).
  assert.equal(look("msg_A", 1), "open-first");
  for (const index of [2, 3, 5, 6, 21, 22, 27, 28, 34]) assert.equal(look("msg_A", index), "open", `блок ${index}`);
  assert.equal(loaded.dom.queryAll(`[${WORK}="rest"]`).length, 0);
  // Плашка с идущей командой — на виду и нажимается: кнопка Claude на месте, меток «спрятано» на пути нет.
  const pill = at("msg_A", 22);
  assert.ok(pill.button.isConnected);
  assert.equal(pill.node.getAttribute(WORK), "open");
  assert.deepEqual(work(), { series: 1, folded: 0, live: true, failed: 1, lastError: null });
  // Раскрытое остаётся раскрытым на следующих проходах.
  tick(); tick();
  assert.equal(line.getAttribute("aria-expanded"), "true");
  assert.equal(look("msg_A", 2), "open");
  // Enter — свернуть, пробел — раскрыть; удержание клавиши и чужая клавиша — мимо.
  assert.equal(key("Enter", line).defaultPrevented, true);
  assert.equal(line.getAttribute("aria-expanded"), "false");
  assert.equal(look("msg_A", 2), "rest");
  assert.equal(work().folded, 1);
  assert.equal(key(" ", line).defaultPrevented, true);
  assert.equal(line.getAttribute("aria-expanded"), "true");
  assert.equal(key("Enter", line, { repeat: true }).defaultPrevented, true);
  assert.equal(line.getAttribute("aria-expanded"), "true", "удержание не мигает");
  key("a", line);
  assert.equal(line.getAttribute("aria-expanded"), "true");
  // Двойное нажатие — одно.
  click(line);
  click(line, { detail: 2 });
  assert.equal(line.getAttribute("aria-expanded"), "false");
  assert.equal(loaded.inner.workState.clicks, 4);
});

test("12х¹: раскрытие и сворачивание не дёргают прокрутку — строка остаётся там, где её нажали; низ ленты остаётся низом", () => {
  const { parts, lines, click } = page({ entries: MIDDLE() });
  const line = lines()[0];
  parts.feed.scrollTop = 500;
  line.rect = { left: 24, top: 120, width: 200, height: 24 };
  click(line);
  assert.equal(parts.feed.scrollTop, 500, "строка на месте — лента не прокручивается");
  // Строка уехала (лента стояла у низа и подтянулась) — прокрутка возвращает её под курсор.
  let moved = false;
  const node = line;
  const real = node.getBoundingClientRect.bind(node);
  node.getBoundingClientRect = () => { const box = real(); if (!moved) { moved = true; return box; } return { ...box, top: box.top + 60 }; };
  click(line);
  assert.equal(parts.feed.scrollTop, 560);
  // Серия свернулась сама (пришёл второй шаг), лента стояла у низа — остаётся у низа.
  const bottom = page({ entries: TAIL(), atBottom: true });
  assert.equal(bottom.lines().length, 1);
  assert.equal(bottom.parts.feed.scrollTop, bottom.parts.feed.scrollHeight);
  // Лента не у низа — прокрутку не трогаем.
  const above = page({ entries: TAIL() });
  assert.equal(above.parts.feed.scrollTop, 0);
});

// ---- соседи: разбор ленты не меняется -------------------------------------------
test("12х¹: свёртка — метками: innerText ленты тот же, полоса 2б, «Скажи — и сделаю» и статус «работает» читают то же", () => {
  const entries = () => [
    user("u1"),
    answer("msg_A", "whole", T("Сделал шапку и поле."), ...SERIES(true), {
      kind: "text", text: "❗ Скажи — и сделаю ❗\n\nда\n\n⚪PimpMyClaude · WF 2 из 3 · идёт 💭", html: [
        host => host.add("h3", { text: "❗ Скажи — и сделаю ❗" }),
        host => { const p = host.add("p"); p.add("strong", { text: "да" }); return p; },
        "⚪PimpMyClaude · WF 2 из 3 · идёт 💭",
      ],
    }),
  ];
  const snapshot = made => {
    made.loaded.win.dispatchEvent({ type: "resize" });
    made.loaded.dom.fireKind("timeout");
    made.loaded.dom.fireKind("raf");
    const { wf, of, state, source } = plain(made.loaded.api.status().progress);
    return {
      progress: { wf, of, state, source },
      say: [...made.loaded.inner.sayButtons()].map(item => item.word),
      working: made.loaded.inner.pageWorking(),
      feed: made.parts.feed.innerText,
      text: made.parts.feed.textContent,
    };
  };
  // Та же лента без списка блоков (серии не считаются) и со списком (серия свёрнута).
  const off = page({ entries: entries(), title: "PimpMyClaude", atBottom: true, fiber: false });
  const on = page({ entries: entries(), title: "PimpMyClaude", atBottom: true });
  assert.equal(off.lines().length, 0);
  assert.equal(on.lines().length, 1);
  assert.equal(on.say(on.lines()[0]), "▸ Работа шла · 5 шагов 1 не вышло");
  const before = snapshot(off);
  const after = snapshot(on);
  assert.deepEqual(after, before, "разбор ленты со свёрнутой серией и без неё — один и тот же");
  assert.equal(after.progress.wf, 2);
  assert.equal(after.progress.of, 3);
  assert.equal(after.progress.state, "run");
  assert.deepEqual(after.say, ["да"]);
  assert.equal(on.parts.feed.innerText, on.before, "innerText ленты до свёртки и после — один и тот же");
  assert.equal((after.feed.match(/Работа идёт 💭/g) ?? []).length, 5, "спрятанные строки по-прежнему в тексте ленты («Обкэшить»)");
  assert.ok(after.feed.includes("1 failed") && after.feed.includes("1 running"));
  // Раскрыл — тоже ничего не поменялось.
  on.click(on.lines()[0]);
  assert.equal(on.parts.feed.innerText, on.before);
  // Узлы Claude инлайн-стилей не получают.
  for (const item of on.of("msg_A").blocks) {
    for (const node of [item.node, item.target].filter(Boolean)) {
      for (const name of ["display", "visibility", "height", "position"]) assert.equal(node.style.getPropertyValue(name), "");
    }
  }
  // Правила раздела 4: спрятанное — высотой и прозрачностью, не display и не visibility.
  const rules = [...on.loaded.inner.RULES];
  for (const value of ["rest", "row"]) {
    const rule = rules.find(item => item.startsWith(`[${WORK}="${value}"]`));
    assert.ok(rule, `правила ${value} нет`);
    assert.match(rule, /height:0 !important/);
    assert.match(rule, /overflow:hidden !important/);
    assert.match(rule, /opacity:0 !important/);
    assert.ok(!/display|visibility/.test(rule), "display и visibility innerText пропускает — ими прятать нельзя");
  }
  // Кольцо вращается только у идущей серии и стоит при «Уменьшить движение».
  assert.ok(rules.some(rule => rule.startsWith(`[${LINE}="live"] [${PART}="ring"]`) && rule.includes("animation:myclaude-work-spin")));
  assert.ok(rules.some(rule => rule.startsWith("@media (prefers-reduced-motion: reduce)") && rule.includes(`[${LINE}="live"] [${PART}="ring"]{animation:none}`)));
  // Раскрытая серия — под полосой, как свёртки 12ф (линия 1,5 px цветом текста).
  assert.ok(rules.some(rule => rule.startsWith(`[${WORK}^="open"]::before`) && rule.includes("border-left:1.5px solid currentColor")));
});

test("12х¹: «Прочитано» — строки свёрнутой серии без дорожки; ход из одной серии не считается непрочитанным, пока свёрнут", () => {
  // Ход A — ответ с серией; ход B — одна серия без обычного текста; ход C — обычный ответ.
  const entries = [
    user("u1"), answer("msg_A", "split", T("Раздаю дела."), ...SERIES(false), T("Готово.")),
    user("u2"), answer("msg_B", "split", tools(), R(), task(), R()),
    user("u3"), answer("msg_C", "whole", T("Обычный ответ.")),
  ];
  const zoneOf = row => [...row.childNodes].find(node => node.nodeType === 1 && node.hasAttribute(ZONE)) ?? null;
  const made = page({ entries, storage: { [READ_KEY]: JSON.stringify({ [CHAT]: { at: 1, ids: ["msg_old"] } }) } });
  assert.equal(made.lines().length, 2);
  // Дорожка — у строк обычного ответа; у строк, занятых серией, её нет.
  assert.ok(zoneOf(made.at("msg_A", 0).row));
  assert.equal(zoneOf(made.at("msg_A", 0).row).getAttribute("role"), "button", "кнопка ответа — на его первой видимой строке");
  for (const index of [1, 2, 5, 21]) assert.equal(zoneOf(made.at("msg_A", index).row), null, `блок ${index}`);
  assert.ok(zoneOf(made.at("msg_A", 28).row), "ответ после серии — с дорожкой");
  for (const row of made.of("msg_B").rows) assert.equal(zoneOf(row), null, "ход из одной серии — без дорожек вовсе");
  assert.ok(zoneOf(made.of("msg_C").rows[0]));
  // Счёт непрочитанных: помечен A — дальше только C, ход-серия B не в счёт.
  made.loaded.inner.readToggle("msg_C");
  made.loaded.inner.readToggle("msg_C");
  made.click(zoneOf(made.at("msg_A", 0).row));
  assert.equal(made.loaded.api.status().read.unread, 1, "B — не ответ: читать в нём нечего");
  assert.deepEqual(plain(made.loaded.inner.readState.unread), ["msg_C"]);
  // Помеченный и свёрнутый «Прочитано» ответ показывает свой блок — серия в нём не размечается.
  assert.equal(made.lines().length, 1, "строка серии хода A ушла под блок «Прочитано»");
  assert.equal(made.at("msg_A", 1).row.hasAttribute(WORK), false);
  assert.equal(made.at("msg_A", 1).row.getAttribute("data-myclaude-read"), "rest");
  // Раскрыл серию хода B — он снова ответ: дорожки на месте, в счёте непрочитанных.
  made.click(made.lines()[0]);
  for (const row of made.of("msg_B").rows) assert.ok(zoneOf(row), "у раскрытой серии дорожки есть");
  assert.deepEqual(plain(made.loaded.inner.readState.unread), ["msg_B", "msg_C"]);
  made.click(made.lines()[0]);
  assert.deepEqual(plain(made.loaded.inner.readState.unread), ["msg_C"]);
});

test("12х¹: «чистые ответы» и свёртки 12ф рядом живы: метки К-CA на месте, заголовок свёртки стоит", () => {
  const entries = [user("u1"), answer("msg_A", "whole",
    T("Сейчас: сайт первым.\n\n<details><summary>Подробно</summary>\n\nСкрытое тело.\n\n</details>\n\n🟠Сайт · готово ✅"),
    R("Работа идёт 💭\n\n⚪Rick · идёт 💭"), task(), R())];
  const { loaded, at, lines, say, look } = page({ entries });
  loaded.inner.foldTick();
  loaded.inner.cleanAnswersSync();
  assert.equal(say(lines()[0]), "▸ Работа идёт · 2 шага", "шаг со служебным хвостом К-CA — тоже шаг");
  assert.equal(look("msg_A", 1), "rest");
  assert.equal(at("msg_A", 1).paras[1].hasAttribute("data-myclaude-clean-line"), true, "хвост шага помечен К-CA как и был");
  assert.equal(at("msg_A", 0).paras[4].hasAttribute("data-myclaude-clean-line"), true);
  assert.ok(loaded.dom.query("[data-myclaude-fold-head]"), "заголовок свёртки 12ф стоит");
  assert.equal(loaded.api.status().folds.count, 1);
  assert.equal(look("msg_A", 0), null);
});

// ---- виртуальная лента -------------------------------------------------------------
test("12х¹: лента виртуальная — счёт и границы серии по списку ходов; строка-сводка — в первой строке серии, что есть в DOM", () => {
  // Ход по строке на блок; в DOM — только строки блоков 21…28 (конец серии): начало выше экрана.
  const { at, of, lines, say, work } = page({ entries: MIDDLE(true), mount: (index, entry, item) => entry.id !== "msg_A" || (item.index >= 21 && item.index <= 28) });
  assert.equal(lines().length, 1);
  assert.equal(say(lines()[0]), "▸ Работа шла · 5 шагов 1 не вышло", "шагов пять, хотя в DOM их три");
  assert.equal(lines()[0].parentNode, at("msg_A", 21).host, "сводка — в первой строке серии из тех, что в DOM");
  assert.equal(at("msg_A", 21).row.hasAttribute(WORK), false);
  assert.equal(at("msg_A", 22).row.getAttribute(WORK), "row");
  assert.equal(at("msg_A", 28).row.getAttribute(WORK), "row");
  assert.deepEqual(work(), { series: 1, folded: 1, live: false, failed: 1, lastError: null });
  assert.equal(of("msg_A").blocks.filter(Boolean).length, 4);
  // Серии в DOM нет вовсе (вся вне экрана) — строки нет, счёт по списку тот же, ничего не падает.
  const away = page({ entries: MIDDLE(true), mount: (index, entry) => entry.id !== "msg_A" });
  assert.equal(away.lines().length, 0);
  assert.deepEqual(away.work(), { series: 1, folded: 1, live: false, failed: 1, lastError: null });
});

test("12х¹: строки ленты пришли заново — метки возвращаются в том же колбэке мутаций; ушла строка со сводкой — сводка в следующей", () => {
  const { loaded, parts, at, lines, say } = page({ entries: MIDDLE() });
  const line = lines()[0];
  // Claude пересоздал строку (узел тот же, меток нет): метка возвращается сразу.
  const row = at("msg_A", 5).row;
  row.removeAttribute(WORK);
  loaded.inner.onMutated([{ type: "childList", target: parts.feed, addedNodes: [row], removedNodes: [] }]);
  assert.equal(row.getAttribute(WORK), "row", "метка вернулась до отрисовки");
  // Лента убрала из DOM первую строку серии (со сводкой): сводка — та же, в следующей строке; высота не скачет.
  const head = at("msg_A", 1).row;
  head.remove();
  loaded.inner.onMutated([{ type: "childList", target: parts.feed, addedNodes: [], removedNodes: [head] }]);
  assert.equal(lines().length, 1);
  assert.equal(lines()[0], line, "узел строки тот же");
  assert.equal(line.parentNode, at("msg_A", 2).host);
  assert.equal(at("msg_A", 2).row.hasAttribute(WORK), false, "строка со сводкой видна");
  assert.equal(at("msg_A", 3).row.getAttribute(WORK), "row");
  assert.equal(say(line), "▸ Работа шла · 4 шага");
  // Своя вставка второго круга разметки не даёт: счётчик проходов мутаций растёт, строка на месте.
  loaded.inner.onMutated([{ type: "childList", target: line.parentNode, addedNodes: [line], removedNodes: [] }]);
  assert.equal(lines().length, 1);
  // Claude убрал саму сводку вместе с содержимым колонки — следующий проход ставит её заново.
  line.remove();
  loaded.inner.readTick();
  assert.equal(lines().length, 1);
  assert.equal(lines()[0].parentNode, at("msg_A", 2).host);
});

test("12х¹: пришёл новый шаг — счёт растёт на той же строке; пришёл обычный ответ — «Работа шла»", () => {
  const made = page({ entries: TAIL() });
  const line = made.lines()[0];
  const host = made.parts.feed.__reactFiber$test.return.memoizedProps;
  const entry = host.entries[1];
  // Claude отдаёт новый список (ход — новый объект с новым блоком) и дописывает блок в колонку.
  const add = text => {
    host.entries = [host.entries[0], { ...entry, items: [...host.entries[1].items, { id: `new-${text.length}`, kind: "text", text }] }];
    const block = made.of("msg_A").hosts[0].add("div", { class: "min-w-0" });
    block.add("div", { class: "prose", attrs: { "data-cds": "Prose" } }).add("div", { class: "contents" }).add("p", { text });
    return block;
  };
  const step = add(CLOUD);
  made.tick();
  assert.equal(made.lines()[0], line);
  assert.equal(made.say(line), "▸ Работа идёт · 5 шагов");
  assert.equal(step.getAttribute(WORK), "rest", "новый шаг ушёл под строку");
  const real = add("Готово: всё разложено по терминалам.");
  made.tick();
  assert.equal(made.say(line), "▸ Работа шла · 5 шагов");
  assert.equal(line.getAttribute(LINE), "done");
  assert.equal(real.hasAttribute(WORK), false, "обычный ответ на виду");
  assert.equal(made.work().live, false);
});

test("12х¹: ход пишется — недописанный последний блок серию не разворачивает; список отстал от ленты — блок просто на виду", () => {
  // Идёт ответ, последний блок-текст пока «Работа и»: строка та же, счёт уже с ним.
  const typing = page({ entries: [user("u1"), answer("msg_A", "whole", T(), R(), task(), R(), T("Работа и"))], responding: true });
  assert.equal(typing.say(typing.lines()[0]), "▸ Работа идёт · 3 шага");
  assert.equal(typing.look("msg_A", 4), "rest");
  // Список говорит «Работа и» (прошлый тик), а в ленте уже обычный текст: он на виду, серия свёрнута, ошибки нет.
  const ahead = page({ entries: [user("u1"), answer("msg_A", "whole", T(), R(), task(), R(), T("Работа и"))], responding: true, tick: false });
  ahead.at("msg_A", 4).paras[0].textContent = "Работаю над шапкой";
  ahead.tick();
  assert.equal(ahead.lines().length, 1);
  assert.equal(ahead.look("msg_A", 4), null);
  assert.equal(ahead.look("msg_A", 1), "rest");
  assert.equal(ahead.work().lastError, null);
});

test("12х¹: лента не сошлась со списком блоков — ход не трогаем, причина в status().work.lastError; списка нет — серий нет", () => {
  // В середине хода по списку шаг, а в ленте на его месте обычный текст (порядок блоков другой).
  const made = page({ entries: [user("u1"), answer("msg_A", "whole", T(), R(), task(), R(), T("Конец."))], tick: false });
  made.at("msg_A", 1).paras[0].textContent = "Совсем другой текст";
  made.tick();
  assert.equal(made.lines().length, 0, "ход оставлен как есть");
  assert.equal(made.loaded.dom.queryAll(`[${WORK}]`).length, 0);
  assert.match(made.work().lastError, /не сошёлся со списком блоков/);
  assert.equal(made.work().series, 1, "по списку серия есть");
  // Лента не отдала список ходов вовсе — ничего не сворачиваем и не выдумываем.
  const bare = page({ entries: TAIL(true), fiber: false });
  assert.equal(bare.lines().length, 0);
  assert.deepEqual(bare.work(), { series: 0, folded: 0, live: false, failed: 0, lastError: null });
});

// ---- полоса слева -------------------------------------------------------------------
test("12х: в покое у дорожки «Прочитано» не видно ничего — длинной полосы слева нет; под курсором — как было", () => {
  const rules = [...inner.RULES];
  const hair = rules.find(rule => rule.startsWith(`[${ZONE}]::before`));
  assert.ok(hair, "правила волоска дорожки нет");
  assert.match(hair, /opacity:0;/, "в покое волосок не виден");
  assert.ok(!/opacity:\.[1-9]/.test(hair));
  // Под курсором — подложка, её край и галочка.
  assert.ok(rules.includes(`[${ZONE}][data-myclaude-read-hot]{background:rgba(127,127,127,.14)}`));
  assert.ok(rules.includes(`[${ZONE}][data-myclaude-read-hot]::before{opacity:.5}`));
  assert.ok(rules.includes(`[${ZONE}]:hover::after{opacity:.75}`));
  // У помеченного — галочка без линии: линии во весь ответ у пометки нет ни в каком окне.
  assert.ok(rules.includes(`[${ZONE}="on"][tabindex="0"]::after{opacity:.75}`));
  assert.ok(!rules.some(rule => rule.startsWith(`[${ZONE}="on"]::before`)));
  const tight = rules.find(rule => rule.startsWith(`html[data-myclaude-read-tight] [${ZONE}="on"]`) && rule.includes("::before"));
  assert.match(tight, /height:14px/, "в узком окне пометку раскрытого несёт короткая риска, а не линия");
  // Пишущийся ответ — тоже без волоска.
  assert.ok(rules.includes(`[${ZONE}][aria-disabled="true"]::before{opacity:0 !important}`));
});

// ---- уборка ---------------------------------------------------------------------
test("12х¹: dispose убирает всё своё — строки-сводки и метки; узлы Claude остаются", () => {
  const made = page({ entries: [...MIDDLE(true), user("u9"), answer("msg_Z", "whole", R(), task(), R())] });
  assert.equal(made.lines().length, 2);
  made.click(made.lines()[0]);
  assert.ok(made.loaded.dom.queryAll(`[${WORK}]`).length > 0);
  const blocks = made.of("msg_A").blocks.map(item => item.node);
  made.loaded.api.dispose();
  assert.equal(made.loaded.dom.queryAll(`[${LINE}]`).length, 0);
  assert.equal(made.loaded.dom.queryAll(`[${WORK}]`).length, 0);
  assert.equal(made.loaded.dom.queryAll(`[${PART}]`).length, 0);
  for (const node of blocks) assert.ok(node.isConnected);
  // Перезапись inject.js тем же окном: сироты прошлой установки убраны, серия снова свёрнута одной строкой.
  const again = page({ entries: TAIL() });
  const stale = again.lines()[0];
  const reloaded = again.loaded.reload();
  assert.equal(reloaded.error, null, String(reloaded.error?.stack ?? reloaded.error));
  reloaded.inner.readTick();
  assert.equal(again.loaded.dom.queryAll(`[${LINE}]`).length, 1);
  assert.notEqual(again.loaded.dom.queryAll(`[${LINE}]`)[0], stale);
});
