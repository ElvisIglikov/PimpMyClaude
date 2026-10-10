// WF209 (#9398, раздел 3а¹ inject.js): «чистые ответы» — контракт К-CA плана WF209 с правками
// критика 1 и 2. Слово Элвиса 10.10 02:05: «не смотрю ни на контекст, ни кэши, ни новых. Ни ответ, ни
// чат, ни опус… визуальным шумом… „Rick · идёт“ мне тоже не нужна. Давай ответы ещё чище делать»;
// облачко «работа идёт» — «мне нравится».
// Команда `clean-answers` {on:"true"|"false"} всем окнам; команды не было — включено
// (localStorage["myclaude.cleanAnswers"]: "0" — показывать, ключа нет — прятать); метка режима —
// data-myclaude-clean-answers на <html>, метка абзаца — data-myclaude-clean-line; прячет правило
// раздела 4 видом, который innerText оставляет; status().cleanAnswers = {on, hidden}.
// Прячется только хвост блока текста ответа: подряд идущие последние абзацы верхнего уровня, и только
// если каждая строка абзаца служебная — строка расхода (вывод SkilZZZ/scripts/claude_footer.py) или
// строка состояния (шаблон ELVIS.md). «Работа идёт 💭» и «❗ Перечитка» остаются.
//
// Разметка — замер живого окна 10.10 (Claude 2.31226): строка ленты transcript-row → AssistantMessage
// (data-is-streaming) → колонка → блоки текста div[data-cds=Prose].prose → div.contents → p, ol, …;
// перенос строки внутри абзаца — <br>; у одного ответа блоков текста несколько (между ними инструменты).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const KEY = "myclaude.cleanAnswers";
const ROOT_MARK = "data-myclaude-clean-answers";
const MARK = "data-myclaude-clean-line";

const STATUS = "⚪PimpMyClaude · WF 2 из 3 · идёт 💭";
const USAGE = ["Контекст 226K", "Из кэша 96% · Новых 238K", "Ответ 6.0M · Чат 6.0M · Opus 5.5 HIGH 💭"];

// ---- разбор строки: чистая функция через люк ---------------------------------
const { inner } = loadInject({ title: "Trelvis" });
const kind = line => inner.cleanAnswerLine(line);

test("К-CA: строки расхода claude_footer.py — служебные (тремя строками, одной строкой, без модели и значка)", () => {
  for (const line of [
    ...USAGE,
    "Контекст 87K",
    "Контекст 1.3M",
    "Из кэша 100% · Новых 5K",
    "Ответ 412K · Чат 1.3M · Opus 5.5 Extra 💭",
    "Ответ 928K · Чат 48.4M · Opus 5.5 🔥 MAX ✅",
    "Ответ 412K · Чат 1.3M",
    "Ответ 412K · Чат 1.3M ❓",
    "Ответ 12K · Чат 40K · Fable 5.1 HIGH 🛑",
    // Просмотрщик склеил три строки в одну — через пробел или через «·».
    USAGE.join(" "),
    USAGE.join(" · "),
    "  Контекст 226K  ",
    "расход: нет данных",
  ]) assert.equal(kind(line), "hide", line);
});

test("К-CA: строка состояния «<маркер>Проект · [WF N из M ·] слово значок» — служебная", () => {
  for (const line of [
    STATUS,
    "🔰Rick · идёт 💭",
    "🟠VkusnoffKz · жду ❓",
    "🎛️MenuMaker · WF 1 из 1 · готово ✅",
    "📦ElvisOS · WF 12 из 34 · упал 🛑",
    "🧾ВкусУчёт · готово ✅",
    "⚪ Другое · идёт 💭",
    // Имя проекта — ссылка: в ленте она уже текст, но и сырой вид разбирается.
    "🟣[Trelvis](docs/status.md) · WF 1 из 3 · идёт 💭",
  ]) assert.equal(kind(line), "hide", line);
});

test("К-CA: «Работа идёт 💭» и «❗ Перечитка» — служебные, но остаются на виду", () => {
  assert.equal(kind("Работа идёт 💭"), "keep");
  assert.equal(kind("❗ Перечитка 860K мимо кэша"), "keep");
  assert.equal(kind("❗️ Перечитка 1.2M мимо кэша"), "keep", "значок с селектором вида");
  // Просмотрщик склеил расход с «Перечиткой» в одну строку — вся строка остаётся.
  assert.equal(kind(`${USAGE[2]} ❗ Перечитка 860K мимо кэша`), "keep");
  assert.equal(kind(`${USAGE.join(" ")} ❗ Перечитка 860K мимо кэша`), "keep");
});

test("К-CA: обычный текст и строки отчёта служебными не становятся", () => {
  for (const line of [
    "",
    "   ",
    // Строки отчётов: без маркера проекта, с ролью посередине, с галочкой впереди.
    "WF209 · кодинг · готово ✅",
    "WF209 · готово ✅",
    "✅ WF209 · готово ✅",
    "❗ Проект · жду ❓",
    "Rick · идёт 💭",
    "Итого: 5 из 5 · готово ✅",
    "— Итог · готово ✅",
    "⚪PimpMyClaude · кодинг · готово ✅",
    "⚪PimpMyClaude · WF 2 из 3 · идёт",
    "⚪PimpMyClaude · WF 2 из 3 · 40%",
    "⚪PimpMyClaude · идёт 💭 и ещё слово",
    // Похоже на расход, но не он.
    "Контекст задачи понятен",
    "Контекст 226K и ещё слово",
    "Из кэша ничего не пришло",
    "Ответ на вопрос · Чат закрыт",
    "Ответ 6.0M",
    "Сделал ❗ Перечитка была большая",
    "Перечитка 860K мимо кэша",
    "Работа идёт",
    "Работа идёт полным ходом 💭",
  ]) assert.equal(kind(line), null, JSON.stringify(line));
});

// ---- лента ---------------------------------------------------------------------
// Абзац: строки через <br>; кусок-объект { link } — ссылка (имя проекта в строке состояния).
const para = (dom, host, lines) => {
  const node = host.add("p", { attrs: { dir: "ltr" } });
  lines.forEach((line, index) => {
    if (index) node.add("br");
    for (const piece of [].concat(line)) {
      if (typeof piece === "string") node.appendChild(dom.document.createTextNode(piece));
      else node.add("a", { attrs: { href: "docs/status.md" } }).appendChild(dom.document.createTextNode(piece.link));
    }
  });
  // Между блоками в ленте — перевод строки (так их отдаёт innerText браузера).
  host.appendChild(dom.document.createTextNode("\n"));
  return node;
};
// Блок текста ответа: div.min-w-0 → div[data-cds=Prose].prose → div.contents.
const prose = column => column.add("div", { class: "min-w-0" })
  .add("div", { class: "prose", attrs: { "data-cds": "Prose" } }).add("div", { class: "contents" });
const answerRow = (feed, index, streaming = "false") => {
  const row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-index": String(index) } });
  const message = row.add("div", { class: "group/message-row", attrs: { "data-cds": "AssistantMessage", "data-testid": "assistant-message", "data-is-streaming": streaming } });
  return { message, column: message.add("div", { class: "flex min-w-0 flex-col gap-5" }) };
};
const page = (build, { storage = {} } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_abc", title: "PimpMyClaude",
    storage: { local: { "myclaude-auto-allow-roam": "off", ...storage } },
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } });
      return { ...parts, feed, ...build(dom, feed) };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return loaded;
};
const clean = loaded => plain(loaded.api.status().cleanAnswers);
const hidden = node => node.hasAttribute(MARK);
// Обычный ответ: текст, отчёт со строкой «… · готово ✅» посреди, список, а в хвосте — строка состояния
// (имя проекта ссылкой) и абзац расхода в три строки.
const usual = (dom, feed) => {
  const { column } = answerRow(feed, 40);
  const host = prose(column);
  const text = para(dom, host, ["Сделал шапку и поле."]);
  const report = para(dom, host, ["⚪PimpMyClaude · WF 1 из 3 · готово ✅"]);
  const more = para(dom, host, ["Дальше — чистые ответы."]);
  const list = host.add("ul");
  const item = para(dom, list.add("li"), ["🔰Rick · идёт 💭"]);
  const status = para(dom, host, [["⚪", { link: "PimpMyClaude" }, " · WF 2 из 3 · идёт 💭"]]);
  const usage = para(dom, host, USAGE);
  return { column, host, text, report, more, item, status, usage };
};

test("К-CA: по умолчанию включено — хвост ответа (строка состояния и абзац расхода) спрятан, остальное видно", () => {
  const loaded = page(usual);
  const { parts } = loaded;
  assert.equal(loaded.win.localStorage.getItem(KEY), null, "команды не было — ключа нет");
  assert.equal(loaded.document.documentElement.hasAttribute(ROOT_MARK), true);
  assert.deepEqual(clean(loaded), { on: true, hidden: 2 });
  assert.equal(hidden(parts.status), true, "строка состояния — имя проекта ссылкой");
  assert.equal(hidden(parts.usage), true, "абзац расхода — три строки через <br>");
  assert.equal(hidden(parts.report), false, "строка отчёта «… · готово ✅» посреди ответа — не хвост");
  assert.equal(hidden(parts.item), false, "пункт списка — не абзац верхнего уровня");
  assert.equal(hidden(parts.text), false);
  assert.equal(hidden(parts.more), false);
});

test("К-CA: прячет видом, который innerText оставляет, — узлы на месте, полоса 2б читает ту же строку", () => {
  const read = loaded => {
    loaded.win.dispatchEvent({ type: "resize" });
    loaded.dom.fireKind("timeout");
    loaded.dom.fireKind("raf");
    const { wf, of, state, source } = plain(loaded.api.status().progress);
    return { wf, of, state, source, text: loaded.parts.column.innerText };
  };
  const off = page(usual, { storage: { [KEY]: "0" } });
  const on = page(usual);
  assert.equal(clean(off).hidden, 0);
  assert.equal(clean(on).hidden, 2);
  assert.deepEqual(read(on), read(off), "чтение ответа с «чистыми ответами» и без них — одно и то же");
  assert.deepEqual(read(on).wf, 2);
  assert.deepEqual(read(on).of, 3);
  assert.equal(read(on).state, "run");
  assert.ok(read(on).text.includes(USAGE[1]) && read(on).text.includes("WF 2 из 3 · идёт 💭"), "спрятанное по-прежнему в тексте ответа («Обкэшить»)");
  // Узлы не удаляются и инлайн-стилей не получают: прячет только правило таблицы по метке.
  assert.ok(on.parts.status.isConnected && on.parts.usage.isConnected);
  for (const node of [on.parts.status, on.parts.usage]) {
    assert.equal(node.style.getPropertyValue("display"), "");
    assert.equal(node.style.getPropertyValue("visibility"), "");
  }
  const rule = [...on.inner.RULES].find(item => item.includes(`[${MARK}]`));
  assert.ok(rule, "правила раздела 4 нет");
  assert.ok(rule.startsWith(`html[${ROOT_MARK}] `), "правило — только при включённом режиме");
  assert.match(rule, /height:0 !important/);
  assert.match(rule, /overflow:hidden !important/);
  assert.match(rule, /opacity:0 !important/);
  assert.match(rule, /margin:0 !important/, "пустого просвета на месте абзаца нет");
  assert.ok(!/display|visibility/.test(rule), "display и visibility innerText пропускает — ими прятать нельзя");
});

test("К-CA: слитый абзац — состояние и расход вместе прячутся; с обычной строкой внутри — виден целиком и хвост обрывает", () => {
  const loaded = page((dom, feed) => {
    const one = prose(answerRow(feed, 40).column);
    const text = para(dom, one, ["Готово."]);
    const merged = para(dom, one, [STATUS, ...USAGE]);
    const two = prose(answerRow(feed, 42).column);
    const above = para(dom, two, [STATUS]);
    const mixed = para(dom, two, ["Зарегистрировал: #9398", "🔰Rick · идёт 💭", ...USAGE]);
    return { text, merged, above, mixed };
  });
  const { parts } = loaded;
  assert.equal(hidden(parts.merged), true, "все четыре строки служебные");
  assert.equal(hidden(parts.text), false);
  assert.equal(hidden(parts.mixed), false, "в абзаце есть обычная строка — он остаётся целиком");
  assert.equal(hidden(parts.above), false, "абзац над ним — уже не хвост: «подряд идущие последние»");
  assert.equal(clean(loaded).hidden, 1);
});

test("К-CA: «❗ Перечитка» и «Работа идёт 💭» остаются, хвост над ними прячется", () => {
  const loaded = page((dom, feed) => {
    const one = prose(answerRow(feed, 40).column);
    const status = para(dom, one, [STATUS]);
    const reread = para(dom, one, [...USAGE, "❗ Перечитка 860K мимо кэша"]);
    const two = prose(answerRow(feed, 42).column);
    const text = para(dom, two, ["✅ Печать пошла."]);
    const rick = para(dom, two, ["🔰Rick · идёт 💭"]);
    const cloud = para(dom, two, ["Работа идёт 💭"]);
    return { status, reread, text, rick, cloud };
  });
  const { parts } = loaded;
  assert.equal(hidden(parts.reread), false, "абзац с «Перечиткой» виден целиком — она значит «кеш остыл»");
  assert.equal(hidden(parts.status), true, "строка состояния над ним — хвост");
  assert.equal(hidden(parts.cloud), false, "облачко «Работа идёт 💭» Элвису нравится");
  assert.equal(hidden(parts.rick), true, "«Rick · идёт» над облачком — прячется");
  assert.equal(hidden(parts.text), false);
  assert.equal(clean(loaded).hidden, 2);
});

test("К-CA: не абзацы не трогаем — таблица, код и цитата в хвосте останавливают разбор", () => {
  const loaded = page((dom, feed) => {
    const one = prose(answerRow(feed, 40).column);
    const before = para(dom, one, [STATUS]);
    const cell = para(dom, one.add("table").add("tr").add("td"), USAGE);
    const two = prose(answerRow(feed, 42).column);
    const code = two.add("pre", { text: USAGE.join("\n") });
    const three = prose(answerRow(feed, 44).column);
    const quote = para(dom, three.add("blockquote"), [STATUS]);
    // Реплика человека с такой же строкой — не ответ.
    const human = para(dom, feed.add("div", { attrs: { "data-testid": "transcript-row" } })
      .add("div", { class: "prose", attrs: { "data-cds": "Prose" } }).add("div", { class: "contents" }), [STATUS]);
    return { before, cell, code, quote, human };
  });
  assert.deepEqual(clean(loaded), { on: true, hidden: 0 });
  for (const name of ["before", "cell", "code", "quote", "human"]) assert.equal(hidden(loaded.parts[name]), false, name);
});

test("К-CA: идущий ответ — последний блок текста ещё печатается и не трогается; законченные блоки выше и конец ответа — прячутся", () => {
  const loaded = page((dom, feed) => {
    const { message, column } = answerRow(feed, 40, "true");
    const first = prose(column);
    para(dom, first, ["Первая часть готова."]);
    const done = para(dom, first, [STATUS]);
    const last = prose(column);
    para(dom, last, ["Вторая часть."]);
    const typing = para(dom, last, ["🔰Rick · идёт 💭"]);
    return { message, done, typing };
  });
  const { parts } = loaded;
  assert.equal(hidden(parts.done), true, "блок текста выше уже закончен");
  assert.equal(hidden(parts.typing), false, "последний блок идущего ответа не мигает");
  parts.message.setAttribute("data-is-streaming", "false");
  loaded.inner.cleanAnswersSync();
  assert.equal(hidden(parts.typing), true, "ответ закончился — хвост спрятан");
  assert.deepEqual(clean(loaded), { on: true, hidden: 2 });
  // Строку дописали (ответ продолжился) — она больше не служебная, метка снята.
  parts.typing.appendChild(loaded.document.createTextNode(" и ещё слово"));
  loaded.inner.cleanAnswersSync();
  assert.equal(hidden(parts.typing), false);
});

test("К-CA: команда off — всё видно, ключ «0»; on — снова спрятано, ключа нет; мусор в on — выключено", () => {
  const loaded = page(usual);
  loaded.dom.command({ action: "clean-answers", on: "false" });
  assert.equal(loaded.win.localStorage.getItem(KEY), "0");
  assert.equal(loaded.document.documentElement.hasAttribute(ROOT_MARK), false);
  assert.deepEqual(clean(loaded), { on: false, hidden: 0 });
  assert.equal(hidden(loaded.parts.status), false, "метки с абзацев сняты");
  assert.equal(hidden(loaded.parts.usage), false);
  loaded.dom.command({ action: "clean-answers", on: "true" });
  assert.equal(loaded.win.localStorage.getItem(KEY), null);
  assert.equal(loaded.document.documentElement.hasAttribute(ROOT_MARK), true);
  assert.deepEqual(clean(loaded), { on: true, hidden: 2 });
  loaded.dom.command({ action: "clean-answers", on: "да" });
  assert.deepEqual(clean(loaded), { on: false, hidden: 0 }, "как у hide-tools: on — только «true»");
});

test("К-CA: storage из соседнего окна сразу включает и выключает; dispose снимает метки, повторный инжект ставит по ключу", () => {
  const loaded = page(usual);
  loaded.win.localStorage.setItem(KEY, "0");
  loaded.win.dispatchEvent({ type: "storage", key: KEY });
  assert.deepEqual(clean(loaded), { on: false, hidden: 0 });
  loaded.win.localStorage.removeItem(KEY);
  loaded.win.dispatchEvent({ type: "storage", key: KEY });
  assert.deepEqual(clean(loaded), { on: true, hidden: 2 });
  loaded.api.dispose();
  assert.equal(loaded.document.documentElement.hasAttribute(ROOT_MARK), false);
  assert.equal(loaded.dom.queryAll(`[${MARK}]`).length, 0);
  const again = loaded.reload();
  assert.equal(again.error, null, String(again.error?.stack ?? again.error));
  assert.deepEqual(plain(again.api.status().cleanAnswers), { on: true, hidden: 2 });
});
