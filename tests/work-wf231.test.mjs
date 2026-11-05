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
  assert.deepEqual(split.work(), { series: 0, folded: 0, live: false, failed: 0, lastError: null, progress: null });
  assert.equal(split.lines().length, 0);
  // Серия — хвост чата: работа идёт.
  const tail = page({ entries: TAIL() });
  assert.deepEqual(tail.work(), { series: 1, folded: 1, live: true, failed: 0, lastError: null, progress: null });
  // После серии пришёл ответ, потом реплика: работа шла.
  const middle = page({ entries: MIDDLE() });
  assert.deepEqual(middle.work(), { series: 1, folded: 1, live: false, failed: 0, lastError: null, progress: null });
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
  assert.equal(say(line), "▸ Работа идёт — 4 шага");
  assert.equal(part(line, "failed").hasAttribute(TEXT), false, "неудачи нет — метки нет");
  assert.equal(part(line, "ring"), undefined, "кольцо вернулось (page-71: «кругляшок какой-то» — без него)");
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
  assert.deepEqual(work(), { series: 1, folded: 1, live: true, failed: 0, lastError: null, progress: null });
});

test("12х¹: серия уже не хвост — та же строка без вращения: «Работа шла · N шагов»; ход по строке ленты на блок", () => {
  const { of, at, lines, say, look } = page({ entries: MIDDLE() });
  assert.equal(lines().length, 1);
  const line = lines()[0];
  assert.equal(line.getAttribute(LINE), "done");
  assert.equal(say(line), "▸ Работа шла — 4 шага");
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
  assert.equal(live.say(live.lines()[0]), "▸ Работа идёт — 5 шагов 1 не вышло");
  assert.equal(live.lines()[0].getAttribute("aria-label"), "Работа идёт, 5 шагов, 1 не вышло");
  assert.deepEqual(live.work(), { series: 1, folded: 1, live: true, failed: 1, lastError: null, progress: null });
  const done = page({ entries: MIDDLE(true) });
  assert.equal(done.say(done.lines()[0]), "▸ Работа шла — 5 шагов 1 не вышло");
  // Упало две — так и сказано; счёт шагов склоняется.
  const two = page({ entries: [user("u1"), answer("msg_A", "whole", R(), task("failed"), R(), task("failed"), task())] });
  assert.equal(two.say(two.lines()[0]), "▸ Работа идёт — 2 шага 2 не вышло");
  const many = page({ entries: [user("u1"), answer("msg_A", "whole", ...Array.from({ length: 21 }, () => R()))] });
  assert.equal(many.say(many.lines()[0]), "▸ Работа идёт — 21 шаг");
});

test("12х¹: одиночный «Работа идёт» и ответ с текстом не трогаются; карточка файла внутри серии остаётся на виду", () => {
  // Один шаг — облачко как было; обычный ответ с «Работа идёт» в конце — тоже.
  const one = page({ entries: [user("u1"), answer("msg_A", "whole", T(), tools(), R(), task()), user("u2"), answer("msg_B", "split", T("Сделал.\n\nРабота идёт 💭"), R())] });
  assert.equal(one.lines().length, 0);
  assert.equal(one.loaded.dom.queryAll(`[${WORK}]`).length, 0);
  assert.deepEqual(one.work(), { series: 0, folded: 0, live: false, failed: 0, lastError: null, progress: null });
  // Карточка файла между шагами — содержимое, а не служебная строка: серия её не прячет.
  for (const layout of ["whole", "split"]) {
    const made = page({ entries: [user("u1"), answer("msg_A", layout, T(), R(), card("50.html"), task(), R(), tools())] });
    assert.equal(made.lines().length, 1, layout);
    assert.equal(made.say(made.lines()[0]), "▸ Работа идёт — 2 шага");
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
  assert.deepEqual(work(), { series: 1, folded: 0, live: true, failed: 1, lastError: null, progress: null });
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
  assert.equal(on.say(on.lines()[0]), "▸ Работа шла — 5 шагов 1 не вышло");
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
  assert.ok(!rules.some(rule => rule.includes(`[${PART}="ring"]`)), "правила кольца остались");
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
  assert.equal(say(lines()[0]), "▸ Работа идёт — 2 шага", "шаг со служебным хвостом К-CA — тоже шаг");
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
  assert.equal(say(lines()[0]), "▸ Работа шла — 5 шагов 1 не вышло", "шагов пять, хотя в DOM их три");
  assert.equal(lines()[0].parentNode, at("msg_A", 21).host, "сводка — в первой строке серии из тех, что в DOM");
  assert.equal(at("msg_A", 21).row.hasAttribute(WORK), false);
  assert.equal(at("msg_A", 22).row.getAttribute(WORK), "row");
  assert.equal(at("msg_A", 28).row.getAttribute(WORK), "row");
  assert.deepEqual(work(), { series: 1, folded: 1, live: false, failed: 1, lastError: null, progress: null });
  assert.equal(of("msg_A").blocks.filter(Boolean).length, 4);
  // Серии в DOM нет вовсе (вся вне экрана) — строки нет, счёт по списку тот же, ничего не падает.
  const away = page({ entries: MIDDLE(true), mount: (index, entry) => entry.id !== "msg_A" });
  assert.equal(away.lines().length, 0);
  assert.deepEqual(away.work(), { series: 1, folded: 1, live: false, failed: 1, lastError: null, progress: null });
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
  assert.equal(say(line), "▸ Работа шла — 4 шага");
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
  assert.equal(made.say(line), "▸ Работа идёт — 5 шагов");
  assert.equal(step.getAttribute(WORK), "rest", "новый шаг ушёл под строку");
  const real = add("Готово: всё разложено по терминалам.");
  made.tick();
  assert.equal(made.say(line), "▸ Работа шла — 5 шагов");
  assert.equal(line.getAttribute(LINE), "done");
  assert.equal(real.hasAttribute(WORK), false, "обычный ответ на виду");
  assert.equal(made.work().live, false);
});

test("12х¹: ход пишется — недописанный последний блок серию не разворачивает; список отстал от ленты — блок просто на виду", () => {
  // Идёт ответ, последний блок-текст пока «Работа и»: строка та же, счёт уже с ним.
  const typing = page({ entries: [user("u1"), answer("msg_A", "whole", T(), R(), task(), R(), T("Работа и"))], responding: true });
  assert.equal(typing.say(typing.lines()[0]), "▸ Работа идёт — 3 шага");
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
  assert.deepEqual(bare.work(), { series: 0, folded: 0, live: false, failed: 0, lastError: null, progress: null });
});

// ---- полоса слева -------------------------------------------------------------------
test("12х: в покое у дорожки «Прочитано» не видно ничего — длинной полосы слева нет; под курсором — подложка всего блока (#9506)", () => {
  const rules = [...inner.RULES];
  const veil = rules.find(rule => rule.startsWith(`[${ZONE}]::before`));
  assert.ok(veil, "правила подложки блока нет");
  assert.match(veil, /opacity:0;/, "в покое подложка не видна");
  assert.ok(!/opacity:\.[1-9]/.test(veil));
  assert.ok(!/width:1\.5px|border-left/.test(veil), "у дорожки снова волосок-полоса (слово Элвиса 10.10 10:47)");
  // Под курсором — подложка всего блока (с задержкой) и галочка.
  assert.ok(rules.includes(`[${ZONE}][data-myclaude-read-hot]::before{opacity:1;transition:opacity .2s ease .3s}`));
  assert.ok(rules.includes(`[${ZONE}]:hover::after{opacity:.75}`));
  // У помеченного — галочка без линии: линии во весь ответ у пометки нет ни в каком окне.
  assert.ok(rules.includes(`[${ZONE}="on"][tabindex="0"]::after{opacity:.75}`));
  assert.ok(!rules.some(rule => rule.startsWith(`[${ZONE}="on"]::before`)));
  assert.ok(!rules.some(rule => rule.startsWith(`html[data-myclaude-read-tight] [${ZONE}="on"]`) && rule.includes("::before")), "риска у раскрытого в узком окне");
  // Пишущийся ответ — без подложки.
  assert.ok(rules.includes(`[${ZONE}][aria-disabled="true"]::before{opacity:0 !important}`));
});

// ---- WF245 (слово Элвиса 11.10 01:40): «Работа идёт» один раз и полоса хода секторами -------------
const BAR = "data-myclaude-work-bar";

test("WF245: счёт «k/N» у строки шага — до облачка или после; мусор — обычный шаг без счёта; текст с делом — не шаг", () => {
  for (const [text, want] of [
    ["Работа идёт 💭 3/10", { k: 3, n: 10 }], ["Работа идёт 3/10 💭", { k: 3, n: 10 }], ["Работа идёт 3/10", { k: 3, n: 10 }],
    ["**Работа идёт** 💭 7 / 7", { k: 7, n: 7 }], ["Работа идёт 💭 0/4", { k: 0, n: 4 }], ["Работа идёт 💭 30/30.", { k: 30, n: 30 }],
    ["Работа идёт 💭 3/10\n\n⚪PimpMyClaude · WF 2 из 3 · идёт 💭", { k: 3, n: 10 }],
    // Мусор: больше, чем всего; ноль всего; секторов больше потолка; два счёта — шаг есть, счёта нет.
    ["Работа идёт 💭 12/10", null], ["Работа идёт 💭 0/0", null], ["Работа идёт 💭 3/31", null], ["Работа идёт 1/4 💭 2/4", null],
    ["Работа идёт 💭", null],
  ]) {
    assert.equal(inner.workTextIs(text), true, text);
    assert.deepEqual(plain(inner.workProgressOf(text)), want, text);
  }
  for (const text of ["Работа идёт 💭 3/10 осталось чуть", "Работа идёт 💭 3/", "Работа идёт 💭 3 из 10", "Сделал 3/10.\n\nРабота идёт 💭 3/10", "Работа идёт 💭 1234/5000"]) {
    assert.equal(inner.workTextIs(text), false, text);
    assert.equal(inner.workProgressOf(text), null, text);
  }
  // «Чистые ответы» (К-CA): облачко со счётом — то же облачко: остаётся на виду и служебный хвост не обрывает.
  for (const text of ["Работа идёт 💭 3/10", "Работа идёт 3/10 💭"]) assert.equal(inner.cleanAnswerLine(text), "keep", text);
  // Счёт ещё печатается — строка уже шаг (серия не мигает), но счёта у неё пока нет.
  assert.equal(inner.workTextIs("Работа идёт 💭 3", true), true);
  assert.equal(inner.workTextIs("Работа идёт 💭 3/", true), true);
  assert.equal(inner.workTextIs("Работа идёт 💭 3/"), false);
});

test("WF245: серия помнит счёт последнего дописанного шага; прогноз N уточняется; шаг без счёта счёт снимает", () => {
  assert.deepEqual(series([R("Работа идёт 💭 1/7"), tools(), R("Работа идёт 💭 2/7")]), [{ from: 0, first: 0, steps: 2, failed: 0, progress: { k: 2, n: 7 }, to: 2, tail: true }]);
  // Прогноз вырос с 7 до 10 — верим последнему шагу.
  assert.deepEqual(series([R("Работа идёт 💭 2/7"), R("Работа идёт 💭 3/10")])[0].progress, { k: 3, n: 10 });
  // Последний шаг без счёта или с мусором — полосы нет, серия остаётся серией.
  assert.equal("progress" in series([R("Работа идёт 💭 2/7"), R()])[0], false);
  assert.equal("progress" in series([R("Работа идёт 💭 2/7"), R("Работа идёт 💭 9/7")])[0], false);
  assert.equal(series([R("Работа идёт 💭 2/7"), R("Работа идёт 💭 9/7")])[0].steps, 2);
  // Шаг ещё печатается («3/1» станет «3/10») — счёт прежнего шага стоит, пока блок не дописан.
  assert.deepEqual(series([R("Работа идёт 💭 2/10"), R("Работа идёт 💭 3/1")], true)[0].progress, { k: 2, n: 10 });
  assert.deepEqual(series([R("Работа идёт 💭 2/10"), R("Работа идёт 💭 3/")], true)[0], { from: 0, first: 0, steps: 2, failed: 0, progress: { k: 2, n: 10 }, to: 1, tail: true });
  assert.deepEqual(series([R("Работа идёт 💭 2/10"), R("Работа идёт 💭 3/10")])[0].progress, { k: 3, n: 10 });
});

test("WF245: живая серия со счётом — полоса «k/N» и «· k из N» вместо числа шагов; status().work.progress", () => {
  const steps = (...counts) => counts.flatMap(count => [tools(), R(`Работа идёт 💭 ${count}`)]);
  const live = page({ entries: [user("u1"), answer("msg_A", "whole", T("Раздаю дела."), ...steps("1/10", "2/10", "3/10"))] });
  const line = live.lines()[0];
  assert.equal(line.getAttribute(LINE), "live");
  assert.equal(live.say(line), "▸ Работа идёт 3 из 10");
  assert.equal(line.getAttribute("aria-label"), "Работа идёт, 3 из 10");
  assert.equal(live.part(line, "bar").getAttribute(BAR), "3/10");
  assert.equal(line.textContent, "", "текста в строке по-прежнему нет");
  assert.deepEqual(live.work(), { series: 1, folded: 1, live: true, failed: 0, lastError: null, progress: { k: 3, n: 10 } });
  // Все сектора залиты — 7 из 7.
  const full = page({ entries: [user("u1"), answer("msg_A", "split", ...steps("6/7", "7/7"))] });
  assert.equal(full.say(full.lines()[0]), "▸ Работа идёт 7 из 7");
  assert.equal(full.part(full.lines()[0], "bar").getAttribute(BAR), "7/7");
  // Счёта нет или он мусорный — строка как раньше, полосы нет.
  for (const tail of ["Работа идёт 💭", "Работа идёт 💭 12/10"]) {
    const plainLine = page({ entries: [user("u1"), answer("msg_A", "whole", ...steps("1/10"), tools(), R(tail))] });
    assert.equal(plainLine.say(plainLine.lines()[0]), "▸ Работа идёт — 2 шага", tail);
    assert.equal(plainLine.part(plainLine.lines()[0], "bar").hasAttribute(BAR), false, tail);
    assert.equal(plainLine.work().progress, null, tail);
  }
  // Серия кончилась («Работа шла») — полосы нет, счёт шагов как был; progress — только живой серии.
  const done = page({ entries: [user("u1"), answer("msg_A", "whole", ...steps("1/3", "2/3", "3/3"), T("Готово, всё сделано.")), user("u2")] });
  assert.equal(done.say(done.lines()[0]), "▸ Работа шла — 3 шага");
  assert.equal(done.part(done.lines()[0], "bar").hasAttribute(BAR), false);
  assert.equal(done.work().progress, null);
  // Раскрытая живая серия полосу на своей строке держит.
  live.click(line);
  assert.equal(live.say(live.lines()[0]), "▾ Работа идёт 3 из 10");
  assert.equal(live.part(live.lines()[0], "bar").getAttribute(BAR), "3/10");
});

test("WF245: одиночная строка шага со счётом — полоса на месте счёта, innerText ленты тот же; печатается — не трогаем", () => {
  const made = page({ entries: [
    user("u1"), answer("msg_A", "whole", T("Раздаю дела.\n\nРабота идёт 💭 1/10"), tools(), R("Работа идёт 💭 2/10")),
    user("u2"), answer("msg_B", "whole", T("Обычный ответ про 3/10 задач."), tools(), R("Работа идёт 3/4 💭"), tools(), T("Счёт мусорный.\n\nРабота идёт 💭 9/4")),
  ] });
  assert.equal(made.lines().length, 0, "серий нет: в каждом ходе по одному шагу");
  // Хвостовой абзац обычного ответа и одиночный шаг — оба с полосой; подпись — строка без счёта.
  const tail = made.at("msg_A", 0).paras[1];
  const single = made.at("msg_A", 2).paras[0];
  assert.equal(tail.getAttribute(BAR), "1/10");
  assert.equal(tail.getAttribute(TEXT), "Работа идёт 💭");
  assert.equal(single.getAttribute(BAR), "2/10");
  assert.equal(made.at("msg_B", 2).paras[0].getAttribute(BAR), "3/4");
  assert.equal(made.at("msg_B", 2).paras[0].getAttribute(TEXT), "Работа идёт 💭");
  // Обычный текст с дробью и мусорный счёт — как были.
  assert.equal(made.at("msg_A", 0).paras[0].hasAttribute(BAR), false);
  assert.equal(made.at("msg_B", 0).paras[0].hasAttribute(BAR), false);
  assert.equal(made.at("msg_B", 4).paras[1].hasAttribute(BAR), false);
  // Узлы и текст Claude на месте.
  assert.equal(single.textContent, "Работа идёт 💭 2/10");
  assert.equal(made.parts.feed.innerText, made.before);
  assert.equal(made.loaded.dom.queryAll(`[${LINE}]`).length, 0);
  // Ответ ещё печатается — последний блок текста не трогаем (счёт дописывается); дописан — полоса.
  const typing = page({ entries: [user("u1"), answer("msg_A", "whole", T("Раздаю дела."), tools(), R("Работа идёт 💭 1/1"))], responding: true, tick: false });
  const message = typing.of("msg_A").rows[0].querySelector('[data-cds="AssistantMessage"]');
  message.setAttribute("data-is-streaming", "true");
  typing.tick();
  assert.equal(typing.at("msg_A", 2).paras[0].hasAttribute(BAR), false);
  message.setAttribute("data-is-streaming", "false");
  typing.tick();
  assert.equal(typing.at("msg_A", 2).paras[0].getAttribute(BAR), "1/1");
  // Чат без единого счёта — абзацы не размечаются вовсе.
  const quiet = page({ entries: [user("u1"), answer("msg_A", "whole", T("Раздаю дела."), tools(), R())] });
  assert.equal(quiet.loaded.dom.queryAll(`[${BAR}]`).length, 0);
});

test("WF245: «Работа идёт» один раз — хвостовой абзац ответа спрятан, пока сразу под ним свёрнутая серия", () => {
  const SHOT = layout => [user("u1"), answer("msg_A", layout,
    T("✅ От тебя ничего не нужно.\n\n✅ Я в новом чате: распродажа открыта гостям.\n\nРабота идёт 💭"), ...SERIES(false))];
  for (const layout of ["whole", "split"]) {
    const made = page({ entries: SHOT(layout) });
    const paras = made.at("msg_A", 0).paras;
    assert.equal(made.lines().length, 1, layout);
    assert.equal(paras[2].getAttribute(WORK), "echo", `${layout}: хвостовой абзац спрятан`);
    assert.equal(paras[0].hasAttribute(WORK), false, layout);
    assert.equal(paras[1].hasAttribute(WORK), false, layout);
    assert.equal(made.look("msg_A", 0), null, `${layout}: сам ответ на виду`);
    assert.equal(made.parts.feed.innerText, made.before, `${layout}: innerText ленты тот же`);
    assert.ok(paras[2].isConnected);
    // Серию раскрыли — абзац виден как был; свернули — снова спрятан.
    made.click(made.lines()[0]);
    assert.equal(paras[2].hasAttribute(WORK), false, `${layout}: раскрыто`);
    made.click(made.lines()[0]);
    assert.equal(paras[2].getAttribute(WORK), "echo", `${layout}: свёрнуто`);
  }
  // За «Работа идёт» в том же блоке — служебный хвост К-CA: он не мешает.
  const footer = page({ entries: [user("u1"), answer("msg_A", "whole", T("Сделал шапку.\n\nРабота идёт 💭\n\n⚪PimpMyClaude · WF 2 из 3 · идёт 💭"), ...SERIES(false))] });
  assert.equal(footer.at("msg_A", 0).paras[1].getAttribute(WORK), "echo");
  assert.equal(footer.at("msg_A", 0).paras[2].hasAttribute(WORK), false);
  // Со счётом — тот же абзац: под ним полоса серии, сам он спрятан.
  const counted = page({ entries: [user("u1"), answer("msg_A", "whole", T("Сделал шапку.\n\nРабота идёт 💭 1/9"), tools(), R("Работа идёт 💭 2/9"), tools(), R("Работа идёт 💭 3/9"))] });
  assert.equal(counted.at("msg_A", 0).paras[1].getAttribute(WORK), "echo");
  assert.equal(counted.say(counted.lines()[0]), "▸ Работа идёт 3 из 9");
});

test("WF245: абзац остаётся, когда серии под ним нет, между ними карточка или ответ кончается не «Работа идёт»", () => {
  // Серии нет: за ответом один шаг.
  const single = page({ entries: [user("u1"), answer("msg_A", "whole", T("Сделал шапку.\n\nРабота идёт 💭"), tools(), R())] });
  assert.equal(single.lines().length, 0);
  assert.equal(single.at("msg_A", 0).paras[1].hasAttribute(WORK), false);
  // Ответ кончается обычным текстом — хвоста для серии нет; шаг первой строкой ответа прячется сам (page-71).
  const other = page({ entries: [user("u1"), answer("msg_A", "whole", T("Работа идёт 💭\n\nСделал шапку."), ...SERIES(false))] });
  assert.equal(other.lines().length, 1);
  assert.equal(other.at("msg_A", 0).paras[0].getAttribute(WORK), "head");
  assert.equal(other.at("msg_A", 0).paras[1].hasAttribute(WORK), false);
  // Между ответом и строкой серии осталась на виду карточка файла — строка серии стоит не сразу под абзацем.
  const carded = page({ entries: [user("u1"), answer("msg_A", "whole", T("Сделал шапку.\n\nРабота идёт 💭"), card(), R(), tools(), R())] });
  assert.equal(carded.lines().length, 1);
  assert.equal(carded.at("msg_A", 0).paras[1].hasAttribute(WORK), false);
  // Лента виртуальная: строки с ответом над серией в DOM нет — трогать нечего, ошибки нет.
  const far = page({ entries: [user("u1"), answer("msg_A", "split", T("Сделал шапку.\n\nРабота идёт 💭"), ...SERIES(false))], mount: (index, entry, item) => !(entry.id === "msg_A" && item?.index === 0) });
  assert.equal(far.lines().length, 1);
  assert.equal(far.work().lastError, null);
  // Серия другого хода под ответом — не «сразу под ним».
  const next = page({ entries: [user("u1"), answer("msg_A", "whole", T("Сделал шапку.\n\nРабота идёт 💭")), user("u2"), answer("msg_B", "whole", R(), tools(), R())] });
  assert.equal(next.lines().length, 1);
  assert.equal(next.at("msg_A", 0).paras[1].hasAttribute(WORK), false);
});

test("page-71: как пишет Рик — шаг блоком, инструменты, ответ первой строкой «Работа идёт k/N»: одна строка на ход, без повтора", () => {
  // Слово Элвиса 11.10 07:27: «работа идёт, работа идёт два раза… Вот здесь тоже как-то странно, два облачка».
  const FINAL = "Работа идёт 💭 2/2\n\n**Готово.** Сделал оба дела.";
  assert.equal(inner.workHeadLine(FINAL), "Работа идёт 💭 2/2");
  for (const text of ["Работа идёт 💭 2/2", "Работа идёт 💭 2/2\nи сразу текст", "Сделал.\n\nРабота идёт 💭", "Работа идёт над отчётом\n\nТекст", ""]) {
    assert.equal(inner.workHeadLine(text), null, text);
  }
  // Шаг первой строкой ответа — в счёт серии над ним и в её полосу; серия уже не хвост.
  assert.deepEqual(series([R("Работа идёт 💭 1/2"), tools(), T(FINAL)]), [{ from: 0, first: 0, steps: 2, failed: 0, progress: { k: 2, n: 2 }, to: 1, tail: false }]);
  assert.deepEqual(series([T("Привет."), R("Работа идёт 💭 1/3"), tools(), R("Работа идёт 💭 2/3"), tools(), T("Работа идёт 💭 3/3\n\nИтог.")]).map(item => [item.steps, item.progress]), [[3, { k: 3, n: 3 }]]);
  // Над ответом серии нет — одна строка шага серией не становится.
  assert.deepEqual(series([tools(), T(FINAL)]), []);
  for (const layout of ["whole", "split"]) {
    const done = page({ entries: [user("u1"), answer("msg_A", layout, R("Работа идёт 💭 1/2"), tools(), T(FINAL)), user("u2")] });
    assert.equal(done.lines().length, 1, layout);
    assert.equal(done.say(done.lines()[0]), "▸ Работа шла — 2 шага", layout);
    const paras = done.at("msg_A", 2).paras;
    assert.equal(paras[0].getAttribute(WORK), "head", `${layout}: «Работа идёт 2/2» над ответом осталась на виду`);
    assert.equal(paras[1].hasAttribute(WORK), false, layout);
    assert.equal(done.parts.feed.innerText, done.before, "innerText ленты изменился");
  }
  // Ответ ещё печатается: последний блок пока одна строка шага — серия живая, на той же строке; счёт
  // недописанного шага полосу не двигает (WF245).
  const typing = page({ entries: [user("u1"), answer("msg_A", "whole", R("Работа идёт 💭 1/2"), tools(), R("Работа идёт 💭 2/2"))], responding: true });
  assert.equal(typing.lines().length, 1);
  assert.equal(typing.say(typing.lines()[0]), "▸ Работа идёт 1 из 2");
  // Шаг первой строкой без серии над ним (один инструмент и ответ) — тоже не показывается: шаг кончился.
  const lone = page({ entries: [user("u1"), answer("msg_A", "whole", tools(), T(FINAL)), user("u2")] });
  assert.equal(lone.lines().length, 0);
  assert.equal(lone.at("msg_A", 1).paras[0].getAttribute(WORK), "head");
  // Правило: абзац шага — высота 0, ответ под ним без верхнего отступа.
  const rules = [...inner.RULES];
  assert.ok(rules.some(rule => rule.startsWith(`[${WORK}="echo"],[${WORK}="head"]{height:0 !important`)));
  assert.ok(rules.includes(`[${WORK}="head"]+*{margin-top:0 !important}`));
});

test("WF245: правила — абзац прячется высотой 0 и прозрачностью; полоса 2 px секторами, дышит только у живой серии", () => {
  const rules = [...inner.RULES];
  const echo = rules.find(rule => rule.startsWith(`[${WORK}="echo"]`));
  assert.ok(echo, "правила echo нет");
  assert.match(echo, /height:0 !important/);
  assert.match(echo, /opacity:0 !important/);
  assert.ok(!/display|visibility/.test(echo), "display и visibility innerText пропускает — ими прятать нельзя");
  const bar = rules.find(rule => rule.startsWith(`[${PART}="bar"],p[${BAR}]::after`));
  assert.ok(bar, "правила полосы нет");
  assert.match(bar, /height:2px/);
  assert.match(bar, /-webkit-mask:/);
  assert.match(bar, /var\(--cds-text-accent,currentColor\)/, "залитые сектора — акцент темы");
  // Числа счёта — из атрибута: по правилу на каждое k и N до потолка.
  const numbers = rules.find(rule => rule.startsWith(`[${BAR}^="0/"]{--myclaude-work-k:0}`));
  assert.ok(numbers.includes(`[${BAR}^="30/"]{--myclaude-work-k:30}`) && numbers.includes(`[${BAR}$="/30"]{--myclaude-work-n:30}`));
  assert.ok(!numbers.includes(`$="/0"`) && !numbers.includes(`"31/"`));
  // Абзац одиночной строки: display не none, текст на месте (увезён отступом), перенос запрещён.
  const para = rules.find(rule => rule.startsWith(`p[${BAR}]{`));
  assert.match(para, /display:grid !important/);
  assert.match(para, /white-space:nowrap !important/);
  assert.match(para, /text-indent:-9999px/);
  assert.ok(!/display:none|visibility|font-size:0/.test(para));
  // Дышит последний залитый сектор живой серии; «Уменьшить движение» — стоит.
  assert.ok(rules.some(rule => rule.startsWith(`[${LINE}="live"] [${PART}="bar"]::before`) && rule.includes("animation:myclaude-work-breath")));
  assert.ok(rules.some(rule => rule.startsWith("@media (prefers-reduced-motion: reduce)") && rule.includes(`[${LINE}="live"] [${PART}="bar"]::before{animation:none}`)));
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
  // WF245: метка спрятанного абзаца и полоса одиночной строки — тоже свои.
  const bars = page({ entries: [user("u1"), answer("msg_A", "whole", T("Сделал шапку.\n\nРабота идёт 💭 1/5"), ...SERIES(false)), user("u2"), answer("msg_B", "whole", tools(), R("Работа идёт 💭 2/5"))] });
  assert.equal(bars.at("msg_A", 0).paras[1].getAttribute(WORK), "echo");
  assert.equal(bars.at("msg_B", 1).paras[0].getAttribute(BAR), "2/5");
  bars.loaded.api.dispose();
  assert.equal(bars.loaded.dom.queryAll(`[${WORK}]`).length, 0);
  assert.equal(bars.loaded.dom.queryAll(`[${BAR}]`).length, 0);
  assert.equal(bars.at("msg_B", 1).paras[0].hasAttribute(TEXT), false);
  // Перезапись inject.js тем же окном: сироты прошлой установки убраны, серия снова свёрнута одной строкой.
  const again = page({ entries: TAIL() });
  const stale = again.lines()[0];
  const reloaded = again.loaded.reload();
  assert.equal(reloaded.error, null, String(reloaded.error?.stack ?? reloaded.error));
  reloaded.inner.readTick();
  assert.equal(again.loaded.dom.queryAll(`[${LINE}]`).length, 1);
  assert.notEqual(again.loaded.dom.queryAll(`[${LINE}]`)[0], stale);
});
