// Панель лимитов по-русски (раздел 12ж inject.js, WF78, задача #6738). Слово
// Элвиса 20.09: «вся панель на русском без единого английского слова», цифры
// короче, строка аккаунта вместо «Plan usage limits», внизу полоса дней недели,
// нижняя строка — «Статистика».
//
// Проверяется контракт раздела, а не разметка Claude:
//   1) чистые разборы — формат чисел, время сброса (включая ловушку полуночи),
//      склонения, отрезки недели, имя аккаунта;
//   2) на стенде по разведке (docs/recon-wf78-usage-panel.md) панель
//      переводится целиком, а повторный проход ничего не меняет;
//   3) подмена идёт ТОЛЬКО в nodeValue существующего узла: узлов в панели не
//      прибавляется и не убавляется, у переведённых элементов стоят src/out, и
//      после «перерисовки React-ом» текст переводится снова;
//   4) панель без примет (нет метра и ссылки на статистику) не трогается вовсе;
//   5) полоса недели одна, с подписями дней от дня сброса; при интервале
//      («Resets in 2 days») подписей нет;
//   6) процент 5-часового спрятан своим атрибутом, недельные — нет;
//   7) status().usage отдаёт opens/swaps/unknown/week, а имени аккаунта в
//      status() нет нигде;
//   8) dispose() снимает наблюдателя, свою полосу и свои атрибуты.
//
// Наблюдатель стаба записей не доставляет, поэтому проходы гоняются кругом
// сторожа (интервал 500 мс) — это и есть та самая страховка из раздела 16;
// поведение живого наблюдателя и мигание проверяются на гейте.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner } from "./load.mjs";

const HEARTBEAT_MS = 500;
const SRC = "data-myclaude-lim-src";
const OUT = "data-myclaude-lim-out";
const HIDE = "data-myclaude-lim-hide";
const WEEK = "data-myclaude-week";
const ACCOUNT_KEY = "myclaude-account-v1";

// Круг сторожа (раздел 16): один querySelector ищет панель и переводит её.
// Интервалов на 500 мс в окне два — сторож и часовой ключа чата, — поэтому
// гоняем оба: держаться за порядок их постановки значило бы краснеть от
// любой правки соседнего раздела.
const beat = loaded => {
  let fired = 0;
  for (const [id, item] of [...loaded.dom.timers.entries()]) {
    if (item.kind !== "interval" || item.ms !== HEARTBEAT_MS) continue;
    loaded.dom.fire(id);
    fired += 1;
  }
  return fired > 0;
};

// Панель Claude, какой её сняла живая разведка 21.09: строка контекста с
// кнопкой-шевроном, метр, шапка лимитов со ссылкой, три блока с полосами,
// «See detailed breakdown» внизу. Тексты — настоящими текстовыми узлами:
// React держит именно их, и раздел 12ж меняет только nodeValue.
const panelOf = (dom, {
  context = "324.7k / 1M (32%)",
  hour5 = "Resets in 4 hr 9 min",
  weekly = "Resets Fri 8:00 AM",
  fable = "Resets Fri 8:00 AM",
  head = "Plan usage limits · Max (20x)",
  meter = true,
  link = true,
} = {}) => {
  const panel = dom.document.body.add("div", {
    attrs: { role: "dialog", "data-cds": "Popover", "data-side": "top", "data-align": "end", id: "usage-panel" },
    rect: { left: 700, top: 300, width: 320, height: 260 },
  });
  const column = panel.add("div", { class: "flex flex-col py-sm" });
  const contextRow = column.add("button", { attrs: { "aria-expanded": "false" } });
  const contextLabel = dom.leaf(contextRow, "span", "Context window", { class: "text-footnote text-muted" });
  const contextValue = dom.leaf(contextRow, "span", context, { class: "text-footnote text-muted tabular-nums ml-auto" });
  contextRow.add("span", { attrs: { "data-cds": "Icon" } });
  if (meter) {
    column.add("div", { attrs: { "data-cds": "StackedMeter", role: "img", "aria-label": "Context window: Messages: 112k" } });
  }
  column.add("div", { class: "h-px bg-alpha-2" });
  const headNode = dom.leaf(column, "span", head, { class: "text-footnote text-muted" });
  if (link) column.add("a", { attrs: { href: "/settings/usage", "aria-label": "View usage in Settings" } });

  const rows = [];
  const limit = (id, label, reset, percent, fill) => {
    const block = column.add("div", { class: "flex flex-col" });
    const row = block.add("div", { class: "flex items-baseline justify-between" });
    const name = dom.leaf(row, "span", label, { id, class: "text-footnote text-primary truncate" });
    const right = row.add("span", { class: "flex items-baseline gap-1.5 text-muted tabular-nums" });
    const when = dom.leaf(right, "span", reset);
    const pct = dom.leaf(right, "span", percent);
    const bar = block.add("div", {
      class: "h-1 w-full overflow-hidden rounded-full bg-alpha-2",
      attrs: { role: "progressbar", "aria-labelledby": id, "aria-valuenow": percent.replace("%", "") },
    });
    const track = bar.add("div", { class: `h-full ${fill}` });
    track.style.setProperty("width", percent);
    rows.push({ block, row, name, when, pct, bar, track });
  };
  limit("lim-hour", "5-hour limit", hour5, "17%", "bg-fill-accent");
  limit("lim-week", "Weekly · all models", weekly, "66%", "bg-fill-warning");
  limit("lim-fable", "Weekly · Fable", fable, "72%", "bg-fill-warning");

  column.add("div", { class: "h-px bg-alpha-2" });
  const more = dom.leaf(column, "button", "See detailed breakdown", { class: "text-footnote text-secondary" });
  return { panel, column, contextRow, contextLabel, contextValue, headNode, rows, more };
};

// Кружок контекста над полем ввода — по нему открывается панель.
const ringOf = dom => dom.document.body.add("button", {
  attrs: {
    "data-cds": "Button", "aria-haspopup": "dialog",
    "aria-label": "Usage: Context 324.7k / 1M (32%), Weekly · all models: 66%, Resets Fri 8:00 AM",
  },
  rect: { left: 1000, top: 560, width: 24, height: 24 },
});

const open = ({ account = null, panel = {}, href } = {}) => {
  let parts = null;
  const loaded = loadInject({
    href,
    storage: { local: account ? { [ACCOUNT_KEY]: account } : {} },
    html: dom => {
      const composer = dom.composer();
      parts = panelOf(dom, panel);
      parts.ring = ringOf(dom);
      return { ...composer, ...parts };
    },
  });
  return { loaded, parts: loaded.parts };
};

const textOf = element => String(element.textContent ?? "");
const nodes = loaded => loaded.dom.queryAll("#usage-panel *").length;

// ---- чистые разборы ---------------------------------------------------------

test("цифры контекста: тысячи без десятых, миллионы и проценты как есть", () => {
  const { inner } = loadInner();
  assert.equal(inner.usageNumber("324.7k / 1M (32%)"), "325k / 1M (32%)");
  assert.equal(inner.usageNumber("112k / 1M (11%)"), "112k / 1M (11%)");
  assert.equal(inner.usageNumber("999.5k / 1M (99%)"), "1000k / 1M (99%)");
  assert.equal(inner.usageNumber("1M"), "1M", "миллионы не трогаем");
  assert.equal(inner.usageNumber("Messages"), "Messages", "текст без чисел не трогаем");
});

test("интервалы: часы с минутами, часы без минут, сутки, tomorrow; незнакомое — null", () => {
  const { inner } = loadInner();
  assert.equal(inner.usageMinutes("4 hr 9 min"), 249);
  assert.equal(inner.usageMinutes("59 min"), 59);
  assert.equal(inner.usageMinutes("2 hr"), 120);
  assert.equal(inner.usageMinutes("1 hr"), 60, "час без «s» тоже час");
  assert.equal(inner.usageMinutes("1 day 3 hr"), 24 * 60 + 180);
  assert.equal(inner.usageMinutes("2 days"), 2 * 24 * 60);
  assert.equal(inner.usageMinutes("tomorrow"), 24 * 60);
  assert.equal(inner.usageMinutes("soon"), null, "незнакомую форму разбирать нельзя");
  assert.equal(inner.usageMinutes("4 hr 9 min later"), null, "разобрали не всё — значит не разобрали");
});

test("часы: полночь 12:00 AM это 00:00, полдень 12:30 PM это 12:30, день недели — числом", () => {
  const { inner } = loadInner();
  assert.deepEqual({ ...inner.usageClockParts("12:00 AM") }, { day: null, hour: 0, minute: 0 });
  assert.deepEqual({ ...inner.usageClockParts("12:30 PM") }, { day: null, hour: 12, minute: 30 });
  assert.deepEqual({ ...inner.usageClockParts("8:00 PM") }, { day: null, hour: 20, minute: 0 });
  assert.deepEqual({ ...inner.usageClockParts("Fri 8:00 AM") }, { day: 5, hour: 8, minute: 0 });
  assert.equal(inner.usageClockParts("25:00"), null);
  assert.equal(inner.usageClockParts("завтра"), null);
});

test("склонения: «4 ч 9 мин» справа и «3 дня 6 часов» над полосой", () => {
  const { inner } = loadInner();
  assert.equal(inner.usageShort(249), "4 ч 9 мин");
  assert.equal(inner.usageShort(59), "59 мин");
  assert.equal(inner.usageShort(120), "2 ч");
  assert.equal(inner.usageShort(2 * 24 * 60), "2 дня");
  assert.equal(inner.usageShort(24 * 60 + 180), "1 день 3 ч");
  assert.equal(inner.usageShort(0), "меньше минуты");
  assert.equal(inner.usageLong(3 * 24 * 60 + 6 * 60), "3 дня 6 часов");
  assert.equal(inner.usageLong(24 * 60 + 60), "1 день 1 час");
  assert.equal(inner.usageLong(5 * 60 + 20), "5 часов 20 минут");
  assert.equal(inner.usageLong(11 * 24 * 60), "11 дней", "11 — это «дней», а не «день»");
  assert.equal(inner.usagePlural(21, "день", "дня", "дней"), "день");
});

test("подписи блоков: «Weekly · X» → «X», «all models» → «Недельный»; чужое — null", () => {
  const { inner } = loadInner();
  assert.deepEqual({ ...inner.usageLabel("5-hour limit") }, { kind: "hour5", text: "5-часовой" });
  assert.deepEqual({ ...inner.usageLabel("Weekly · all models") }, { kind: "weekAll", text: "Недельный" });
  assert.deepEqual({ ...inner.usageLabel("Weekly · Fable") }, { kind: "week", text: "Fable" });
  // С Claude 2.42304 (#9978) подписи короче: «Session limit», «Weekly».
  assert.deepEqual({ ...inner.usageLabel("Session limit") }, { kind: "hour5", text: "5-часовой" });
  assert.deepEqual({ ...inner.usageLabel("Weekly") }, { kind: "weekAll", text: "Недельный" });
});

test("шапка: имя из ключа плюс тариф без скобок; имени нет — один тариф", () => {
  const { inner } = loadInner();
  assert.equal(inner.usageHead("Plan usage limits · Max (20x)", "Alex"), "Alex · Max 20x");
  assert.equal(inner.usageHead("Plan usage limits · Max (20x)", ""), "Max 20x");
  assert.equal(inner.usageHead("Plan usage limits · Pro", "Alex"), "Alex · Pro");
  assert.equal(inner.usageHead("Usage limits", "Alex"), null, "чужую шапку не трогаем");
});

test("время сброса: интервал с часами получает «в HH:MM», суточный — нет", () => {
  const { inner } = loadInner();
  const base = new Date(2026, 8, 21, 21, 16).getTime();
  const short = inner.usageReset("Resets in 4 hr 9 min", base);
  assert.equal(short.minutes, 249);
  assert.equal(short.rough, false);
  assert.equal(new Date(short.at).getHours(), 1, "сброс через 4 ч 9 мин — это следующий час ночи");
  const rough = inner.usageReset("Resets in 2 days", base);
  assert.equal(rough.rough, true, "сутки Claude даёт крупностью в день — часы из них не вытащить");
  const day = inner.usageReset("Resets Fri 8:00 AM", base);
  assert.equal(day.fixed, "Пт 08:00");
  assert.equal(new Date(day.at).getDay(), 5);
  assert.equal(new Date(day.at).getHours(), 8);
  assert.ok(day.at > base, "момент сброса — ближайший будущий, а не прошедший");
  assert.equal(inner.usageReset("Resets at 12:00 AM", base).fixed, "в 00:00");
  assert.equal(inner.usageReset("Resets tomorrow", base).fixed, "завтра");
  assert.equal(inner.usageReset("Resets tomorrow at 8:00 AM", base).fixed, "завтра в 08:00");
  assert.equal(inner.usageReset("Limit reached", base).fixed, "Лимит исчерпан");
  assert.equal(inner.usageReset("Resets soon", base), null, "незнакомую форму не переводим");
});

test("отрезки недели: семь дней, подписи от дня сброса, текущий день найден", () => {
  const { inner } = loadInner();
  // Сброс в пятницу 08:00, сейчас понедельник 21:16 — четвёртый отрезок.
  const at = new Date(2026, 8, 25, 8, 0).getTime();
  const now = new Date(2026, 8, 21, 21, 16).getTime();
  const parts = inner.usageWeekParts(at, now);
  assert.equal(parts.fills.length, 7);
  assert.equal(parts.days.length, 7);
  assert.deepEqual([...parts.days], ["Пт", "Сб", "Вс", "Пн", "Вт", "Ср", "Чт"]);
  assert.deepEqual([...parts.fills].slice(0, 3).map(Math.round), [1, 1, 1], "прошедшие дни залиты целиком");
  assert.equal(parts.on, 3, "сегодняшний отрезок — тот, внутри которого «сейчас»");
  assert.ok(parts.fills[3] > 0.5 && parts.fills[3] < 0.7, `текущий день залит частично: ${parts.fills[3]}`);
  assert.deepEqual([...parts.fills].slice(4), [0, 0, 0], "будущие дни пусты");
});

test("имя аккаунта: буква аватара отдельным узлом и слитно, «Anna» не обкусывается", () => {
  const { inner } = loadInner();
  assert.equal(inner.usageAccountName(["E", "Alex", "·", "Max"]), "Alex");
  assert.equal(inner.usageAccountName(["E", "Alex·Max"]), "Alex");
  assert.equal(inner.usageAccountName(["AAlex·Max"]), "Alex");
  assert.equal(inner.usageAccountName(["Anna"]), "Anna", "первая буква режется только когда повторяет вторую");
  assert.equal(inner.usageAccountName(["AAnna"]), "Anna");
  assert.equal(inner.usageAccountName([]), "");
  // #7203: аватар — инициалы, а не одна буква. «AP» вместо «Anna Petrova» в шапке.
  assert.equal(inner.usageAccountName(["AP", "Anna Petrova", "Max 20x"]), "Anna Petrova");
  assert.equal(inner.usageAccountName(["AP", "Anna Petrova · Max 20x"]), "Anna Petrova");
  assert.equal(inner.usageAccountName(["APAnna Petrova·Max 20x"]), "Anna Petrova", "слитные инициалы");
  assert.equal(inner.usageAccountName(["ЭИ", "Элвис Игликов"]), "Элвис Игликов");
  assert.equal(inner.usageAccountName(["AK"]), "", "одни инициалы — не имя: прежнее не затираем");
  assert.equal(inner.usageAccountName(["Al Kuz"]), "Al Kuz");
});

// ---- панель на стенде -------------------------------------------------------

test("панель переводится целиком: подписи, цифры, время, шапка и «Статистика»", () => {
  const { loaded, parts } = open({ account: "Alex" });
  assert.equal(beat(loaded), true, "круга сторожа нет — панель некому найти");

  assert.equal(textOf(parts.contextLabel), "Контекст");
  assert.equal(textOf(parts.contextValue), "325k / 1M (32%)");
  assert.equal(textOf(parts.headNode), "Alex · Max 20x");
  assert.equal(textOf(parts.rows[0].name), "5-часовой");
  assert.match(textOf(parts.rows[0].when), /^4 ч 9 мин — в \d\d:\d\d$/);
  assert.equal(textOf(parts.rows[1].name), "Недельный");
  // Слово Элвиса 21.09: у недельных процент стоит в той же строке через длинное
  // тире — «Пт 08:00 — 66%», как у 5-часового «4 ч 9 мин — в 01:25».
  assert.equal(textOf(parts.rows[1].when), "Пт 08:00 — 66%");
  assert.equal(textOf(parts.rows[2].name), "Fable");
  assert.equal(textOf(parts.rows[2].when), "Пт 08:00 — 72%");
  assert.equal(textOf(parts.more), "Статистика");
  // Ни одного английского СЛОВА панели: имя аккаунта, тариф и название модели
  // латиницей — это не перевод, их Claude и в русском окне пишет так же.
  const all = [parts.contextLabel, parts.contextValue, parts.headNode, parts.more,
    ...parts.rows.map(row => row.name), ...parts.rows.map(row => row.when)].map(textOf).join(" · ");
  assert.equal(/\b(Context|window|Plan|usage|limits|hour|limit|Weekly|all models|Resets|in|See|detailed|breakdown|Fri|AM|PM|min|hr)\b/.test(all),
    false, `осталось английское: ${all}`);
  assert.equal(loaded.api.status().usage.unknown, 0, "панель разобрана не полностью");
});

test("подмена только в nodeValue: узлов столько же, у элементов src и out", () => {
  const { loaded, parts } = open();
  const before = nodes(loaded);
  beat(loaded);
  assert.equal(nodes(loaded) - nodes(loaded), 0);
  // Своя полоса недели — единственное, что прибавилось; родных узлов не убыло.
  const own = loaded.dom.queryAll(`#usage-panel [${WEEK}]`).length;
  assert.ok(own > 0, "полосы недели нет");
  assert.equal(nodes(loaded), before + own, "панель потеряла или нажила чужие узлы");
  assert.equal(parts.contextLabel.getAttribute(SRC), "Context window");
  assert.equal(parts.contextLabel.getAttribute(OUT), "Контекст");
  assert.equal(parts.rows[0].when.getAttribute(SRC), "Resets in 4 hr 9 min");
  assert.equal(parts.rows[0].when.getAttribute(OUT), textOf(parts.rows[0].when));
  // Текстовый узел тот же самый — React о нём не спотыкается.
  assert.equal(parts.contextLabel.childNodes.length, 1);
  assert.equal(parts.contextLabel.childNodes[0].nodeType, 3);
});

test("повторный проход ничего не меняет: ни текста, ни числа подмен", () => {
  const { loaded, parts } = open({ account: "Alex" });
  beat(loaded);
  const first = loaded.api.status().usage;
  const snapshot = [parts.contextLabel, parts.contextValue, parts.headNode, parts.more,
    ...parts.rows.map(row => row.when)].map(textOf);
  beat(loaded);
  beat(loaded);
  const again = [parts.contextLabel, parts.contextValue, parts.headNode, parts.more,
    ...parts.rows.map(row => row.when)].map(textOf);
  assert.deepEqual(again, snapshot, "второй проход переписал то, что уже наше");
  assert.equal(loaded.api.status().usage.swaps, first.swaps, "холостой проход считает подмены");
  assert.equal(loaded.dom.queryAll(`#usage-panel [${WEEK}="block"]`).length, 1, "полос недели стало больше одной");
});

test("React вернул английское число — следующий проход переводит снова", () => {
  const { loaded, parts } = open();
  beat(loaded);
  assert.equal(textOf(parts.contextValue), "325k / 1M (32%)");
  // Перерисовка: React пишет в ТОТ ЖЕ узел свой текст.
  loaded.dom.retext(parts.contextValue, "412.3k / 1M (41%)");
  loaded.dom.retext(parts.rows[0].when, "Resets in 59 min");
  beat(loaded);
  assert.equal(textOf(parts.contextValue), "412k / 1M (41%)");
  assert.equal(parts.contextValue.getAttribute(SRC), "412.3k / 1M (41%)", "оригинал не обновился");
  assert.match(textOf(parts.rows[0].when), /^59 мин — в \d\d:\d\d$/);
});

test("процент спрятан своим атрибутом: у 5-часового совсем, у недельных — уехал в строку сброса", () => {
  const { loaded, parts } = open();
  beat(loaded);
  assert.equal(parts.rows[0].pct.hasAttribute(HIDE), true, "процент 5-часового виден");
  assert.equal(textOf(parts.rows[0].pct), "17%", "узел процента остаётся на месте — его не удаляют");
  assert.equal(parts.rows[1].pct.hasAttribute(HIDE), true, "процент недельного задвоился: он уже в строке сброса");
  assert.equal(textOf(parts.rows[1].pct), "66%", "узел процента остаётся на месте — его не удаляют");
  assert.equal(parts.rows[2].pct.hasAttribute(HIDE), true);
});

test("время сброса не разобрали — процент остаётся на месте, а не пропадает", () => {
  const { loaded, parts } = open({ panel: { weekly: "Resets when it resets" } });
  beat(loaded);
  assert.equal(textOf(parts.rows[1].when), "Resets when it resets", "незнакомое лучше не трогать");
  assert.equal(parts.rows[1].pct.hasAttribute(HIDE), false, "процент спрятали, а уехать ему было некуда");
});

test("полоса недели: одна, семь отрезков, подписи от дня сброса, сегодняшний ярче", () => {
  const { loaded } = open();
  beat(loaded);
  const boxes = loaded.dom.queryAll(`[${WEEK}="block"]`);
  assert.equal(boxes.length, 1, "полоса недели должна быть ровно одна");
  assert.equal(loaded.dom.queryAll(`[${WEEK}="cell"]`).length, 7);
  const days = loaded.dom.queryAll(`[${WEEK}="day"]`).map(textOf);
  assert.equal(days.length, 7);
  assert.equal(days[0], "Пт", "подписи начинаются со дня сброса");
  assert.deepEqual(days, ["Пт", "Сб", "Вс", "Пн", "Вт", "Ср", "Чт"]);
  assert.equal(loaded.dom.queryAll("[data-myclaude-week-on]").length, 1, "ярче ровно один день");
  // Слово Элвиса 21.09: слева «Сброс», справа срок — тонким шрифтом правой
  // колонки, как у родных строк лимитов.
  const title = loaded.dom.query(`[${WEEK}="title"]`);
  assert.equal(textOf(title), "Сброс");
  const value = loaded.dom.query(`[${WEEK}="value"]`);
  // Сброс по дню недели: меньше суток до него (вечер четверга) срок — часами и минутами, в последний час — минутами.
  assert.match(textOf(value), /^(\d+ (день|дня|дней)( \d+ (час|часа|часов))?|\d+ (час|часа|часов)( \d+ (минута|минуты|минут))?|\d+ (минута|минуты|минут))$/, `срок справа: ${textOf(value)}`);
  assert.equal(value.className, loaded.parts.rows[2].pct.parentElement.className,
    "одежда правой колонки снята не с родной строки лимита");
  // Одежда снята с родных блоков, а не выдумана числами.
  assert.equal(loaded.dom.query(`[${WEEK}="cell"]`).className.includes("rounded-full"), true);
  assert.equal(loaded.api.status().usage.week, true);
});

test("недельная строка интервалом: полоса есть, подписей дней нет", () => {
  const { loaded } = open({ panel: { weekly: "Resets in 2 days", fable: "Resets in 2 days" } });
  beat(loaded);
  assert.equal(loaded.dom.queryAll(`[${WEEK}="block"]`).length, 1);
  assert.deepEqual(loaded.dom.queryAll(`[${WEEK}="day"]`).map(textOf), ["", "", "", "", "", "", ""],
    "из интервала день сброса известен с точностью до суток — подписи врали бы все семь");
  assert.equal(loaded.dom.query(`[${WEEK}="day"]`).parentElement.style.getPropertyValue("display"), "none");
});

test("пустой чат: метра долей контекста нет, панель всё равно переводится", () => {
  // Пока разговора нет, строка контекста рисуется простой полосой без долей —
  // и до 21.09 панель в новом чате оставалась английской (слово Элвиса).
  const { loaded, parts } = open({ account: "Alex", panel: { meter: false } });
  beat(loaded);
  assert.equal(textOf(parts.contextLabel), "Контекст");
  assert.equal(textOf(parts.headNode), "Alex · Max 20x");
  assert.equal(textOf(parts.rows[0].name), "5-часовой");
  assert.equal(textOf(parts.more), "Статистика");
  assert.equal(loaded.api.status().usage.week, true, "полоса недели в новом чате не нарисовалась");
});

test("панель без примет (нет метра и ссылки) не трогается вовсе", () => {
  const { loaded, parts } = open({ panel: { meter: false, link: false } });
  beat(loaded);
  assert.equal(textOf(parts.contextLabel), "Context window", "чужой поповер переведён");
  assert.equal(parts.contextLabel.hasAttribute(OUT), false);
  assert.equal(loaded.dom.queryAll(`[${WEEK}]`).length, 0, "в чужой поповер дорисовали полосу");
  assert.equal(loaded.api.status().usage.opens, 0);
});

test("незнакомая строка остаётся английской и считается в unknown", () => {
  const { loaded, parts } = open({ panel: { hour5: "Resets in a while" } });
  beat(loaded);
  assert.equal(textOf(parts.rows[0].when), "Resets in a while", "незнакомое лучше не трогать");
  assert.equal(parts.rows[0].when.hasAttribute(OUT), false);
  assert.ok(loaded.api.status().usage.unknown >= 1, "нераспознанная строка не сосчитана");
  // Счётчик по РАЗНЫМ строкам: холостые проходы его не надувают.
  const once = loaded.api.status().usage.unknown;
  beat(loaded);
  assert.equal(loaded.api.status().usage.unknown, once);
});

test("имя аккаунта: попап читает ключ, главное окно его пишет, в status() имени нет", () => {
  // Попапу кнопки аккаунта не видно — он живёт ключом от главного окна.
  const popup = open({ account: "Alex", href: "about:blank" });
  beat(popup.loaded);
  assert.equal(textOf(popup.parts.headNode), "Alex · Max 20x");
  assert.equal(JSON.stringify(popup.loaded.api.status()).includes("Alex"), false,
    "имя аккаунта уехало в status() — этот слепок ложится на диск");

  // Ключа нет — строка без имени, но и без английского.
  const bare = open();
  beat(bare.loaded);
  assert.equal(textOf(bare.parts.headNode), "Max 20x");

  // Главное окно перезаписывает ключ на каждом круге сторожа.
  const main = open({ account: "Старое" });
  main.loaded.document.body.add("button", { attrs: { "data-testid": "user-menu-button" } })
    .appendChild(main.loaded.document.createTextNode("AAlex·Max"));
  beat(main.loaded);
  assert.equal(main.loaded.win.localStorage.getItem(ACCOUNT_KEY), "Alex", "имя не обновилось");
});

test("клик по кружку ставит временного наблюдателя со сроком", () => {
  const { loaded, parts } = open();
  const before = { observers: loaded.counters.observers, timers: loaded.counters.timers };
  // Панель ещё не открыта: убираем её из документа, как до нажатия.
  parts.panel.remove();
  const passed = loaded.document.dispatchEvent({ type: "click", target: parts.ring, cancelable: true });
  assert.equal(passed, true, "клик по кружку отменять нельзя — панель открывает Claude");
  assert.equal(loaded.counters.observers, before.observers + 1, "наблюдатель за панелью не встал");
  assert.equal(loaded.counters.timers, before.timers + 1, "у ожидания нет срока");
  loaded.dom.fireKind("timeout");
  assert.equal(loaded.counters.observers, before.observers, "наблюдатель пережил свой срок");
});

test("панель закрылась — наблюдатель снят, полоса не осталась сиротой", () => {
  const { loaded, parts } = open();
  beat(loaded);
  // Отложенная раскладка (кадр) заводит свой наблюдатель вложений поля; без кадра её доводит
  // сердце по настоящим часам (LAYOUT_MIN_GAP) — счёт плавал от скорости прогона (WF248). Доводим заранее.
  loaded.dom.fireKind("raf");
  const held = loaded.counters.observers;
  assert.equal(loaded.api.status().usage.week, true);
  parts.panel.remove();
  beat(loaded);
  assert.equal(loaded.counters.observers, held - 1, "наблюдатель за закрытой панелью остался");
  assert.equal(loaded.api.status().usage.week, false);
  assert.equal(loaded.dom.queryAll(`[${WEEK}]`).length, 0, "полоса недели уехала вместе с панелью");
});

test("status().usage: открытия, подмены, нераспознанное и полоса", () => {
  const { loaded } = open({ account: "Alex" });
  assert.deepEqual({ ...loaded.api.status().usage }, { opens: 0, swaps: 0, unknown: 0, week: false, context: null });
  beat(loaded);
  const usage = loaded.api.status().usage;
  assert.equal(usage.opens, 1);
  assert.ok(usage.swaps >= 7, `подмен должно быть не меньше семи: ${usage.swaps}`);
  assert.equal(usage.unknown, 0);
  assert.equal(usage.week, true);
});

test("dispose(): наблюдатель снят, полоса и атрибуты убраны, текст остаётся", () => {
  const { loaded, parts } = open();
  beat(loaded);
  assert.ok(loaded.dom.queryAll(`[${WEEK}]`).length > 0);
  loaded.api.dispose();
  assert.deepEqual({ ...loaded.counters }, { listeners: 0, observers: 0, timers: 0, intervals: 0, rafs: 0, sheets: 0 },
    "после dispose живых подписок, наблюдателей и таймеров быть не должно");
  assert.equal(loaded.dom.queryAll(`[${WEEK}]`).length, 0, "своя полоса недели осталась в панели");
  assert.equal(loaded.dom.queryAll(`[${SRC}],[${OUT}],[${HIDE}]`).length, 0, "свои атрибуты остались на узлах Claude");
  // Текст назад НЕ откатываем осознанно: панель живёт секунды и пересоздаётся
  // при следующем открытии, а откат — лишняя запись в чужое дерево.
  assert.equal(textOf(parts.contextLabel), "Контекст");
});

// ---- Claude 2.42304 (#9978) -------------------------------------------------
// Живая проба 16.10: шапка «Usage» с двумя значками (ссылка на статистику
// осталась), полосы — role="meter" в обёртке, подпись двумя уровнями выше,
// «3% used» справа от подписи, строка сброса ПОД полосой (aria-describedby).
// Строк контекста и Fable в панели больше нет — Пимп рисует их сам.
const CHAT = "local_aaaa-1111";
const panel2Of = dom => {
  const panel = dom.document.body.add("div", {
    attrs: { role: "dialog", "data-cds": "Popover", "data-side": "top", "data-align": "end", id: "usage-panel" },
    rect: { left: 700, top: 300, width: 312, height: 168 },
  });
  const column = panel.add("div", { class: "flex flex-col py-sm" }).add("div", { class: "flex flex-col gap-sm pt-0.5 pb-sm" });
  const head = column.add("div", { class: "flex items-center justify-between gap-sm px-lg" });
  const headNode = dom.leaf(head, "span", "Usage", { class: "text-heading-medium text-primary" });
  head.add("span").add("a", { attrs: { href: "/settings/usage", "aria-label": "Usage settings" } });
  const host = column.add("div", { attrs: { role: "group", "aria-label": "Usage limits" } }).add("div", { class: "flex flex-col gap-md px-lg" });
  const rows = [];
  const limit = (id, label, reset, percent) => {
    const block = host.add("div", { class: "flex flex-col gap-xs" });
    const row = block.add("div", { class: "flex items-baseline justify-between gap-sm text-body" });
    const name = dom.leaf(row, "span", label, { id, class: "min-w-0 font-medium text-primary" });
    const pct = dom.leaf(row, "span", `${percent}% used`, { class: "shrink-0 whitespace-nowrap text-footnote tabular-nums text-muted-as-secondary" });
    const under = block.add("div", { class: "flex flex-col gap-1" });
    const bar = under.add("div", { attrs: { "data-cds": "Meter" }, class: "w-full" }).add("div", {
      class: "w-full overflow-hidden rounded-full h-2 bg-accent",
      attrs: { role: "meter", "aria-labelledby": id, "aria-describedby": `${id}-d`, "aria-valuenow": String(percent) },
    });
    bar.add("div", { class: "h-full w-full rounded-full bg-fill-accent", attrs: { "data-usage-bar-fill": "" } });
    const when = dom.leaf(under, "span", reset, { id: `${id}-d`, class: "text-footnote text-muted-as-secondary" });
    rows.push({ block, row, name, pct, when, bar });
  };
  limit("lim-hour", "Session limit", "Resets in 4 hr 48 min", 3);
  limit("lim-week", "Weekly", "Resets Fri 8:00 AM", 5);
  return { panel, host, headNode, rows };
};
const open2 = ({ fable = 12 } = {}) => {
  const friday = new Date();
  friday.setHours(8, 0, 0, 0);
  friday.setDate(friday.getDate() + (((5 - friday.getDay()) + 7) % 7 || 7));
  const local = fable == null ? {} : {
    "myclaude-limits-v1": JSON.stringify({ v: 1, at: Date.now(), plan: "Max 20x",
      fiveHour: { used: 3, resetsAt: null }, weekly: { used: 5, resetsAt: friday.getTime() },
      fable: { used: fable, resetsAt: friday.getTime() } }),
  };
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`,
    storage: { local },
    html: dom => ({ ...dom.composer(), ...panel2Of(dom), ring: ringOf(dom) }),
  });
  loaded.fetched = [];
  loaded.win.fetch = url => { loaded.fetched.push(String(url)); return Promise.resolve({}); };
  return loaded;
};

test("2.42304: панель опознана и по-русски, Fable и контекст дописаны своими строками", () => {
  const loaded = open2();
  const { parts } = loaded;
  beat(loaded);
  assert.equal(parts.panel.hasAttribute("data-myclaude-lim-panel"), true, "новая панель не опознана");
  assert.equal(textOf(parts.headNode), "Расход");
  assert.equal(textOf(parts.rows[0].name), "5-часовой");
  assert.match(textOf(parts.rows[0].when), /^4 ч 48 мин — в \d\d:\d\d$/);
  assert.equal(parts.rows[0].pct.hasAttribute(HIDE), true, "у 5-часового только полоса");
  assert.equal(textOf(parts.rows[1].name), "Недельный");
  // Процент справа от подписи, сброс под полосой — как в панели у часов (слово Элвиса 16.10).
  assert.equal(textOf(parts.rows[1].when), "Пт 08:00");
  assert.equal(textOf(parts.rows[1].pct), "5%");
  assert.equal(parts.rows[1].pct.hasAttribute(HIDE), false, "процент недели спрятан");
  assert.equal(loaded.api.status().usage.unknown, 0, "панель разобрана не полностью");
  // Полоса дней недели — под недельным, Fable — под ней.
  const week = loaded.dom.query(`[${WEEK}="block"]`);
  assert.ok(week, "полосы недели нет");
  assert.equal(week.previousSibling, parts.rows[1].block);
  const fable = loaded.dom.query(`[${WEEK}="row-fable"]`);
  assert.ok(fable, "строки Fable нет");
  assert.equal(fable.previousSibling, week, "Fable не под полосой недели");
  assert.equal(textOf(fable.querySelector(`[${WEEK}="title"]`)), "Fable");
  assert.equal(textOf(fable.querySelector(`[${WEEK}="value"]`)), "12%");
  assert.equal(textOf(fable.querySelector(`[${WEEK}="note"]`)), "Пт 08:00");
  assert.equal(fable.querySelector(`[${WEEK}="note"]`).className, parts.rows[1].when.className, "одежда строки сброса не родная");
  assert.equal(fable.querySelector(`[${WEEK}="fill"]`).style.getPropertyValue("width"), "12%");
  assert.equal(fable.className, parts.rows[1].block.className, "одежда Fable не с родного блока");
  // Контекст: спросили у приложения один раз, ответ своего чата — строка над лимитами.
  assert.deepEqual(loaded.fetched, [`http://127.0.0.1:47615/context?chat=${CHAT}`]);
  assert.equal(loaded.dom.query(`[${WEEK}="row-context"]`), null, "контекст нарисован без ответа");
  loaded.dom.command({ id: "ctx-1", action: "chat-context", at: "now", chat: "local_bbbb-2222", tokens: 9000 });
  assert.equal(loaded.dom.query(`[${WEEK}="row-context"]`), null, "принят контекст чужого чата");
  loaded.dom.command({ id: "ctx-2", action: "chat-context", at: "now", chat: CHAT, tokens: 433039 });
  beat(loaded);
  const context = loaded.dom.query(`[${WEEK}="row-context"]`);
  assert.ok(context, "строки контекста нет");
  assert.equal(context.nextSibling, parts.rows[0].block, "контекст не над лимитами");
  assert.equal(textOf(context.querySelector(`[${WEEK}="value"]`)), "43%");
  assert.equal(textOf(context.querySelector(`[${WEEK}="note"]`)), "433k из 1M");
  assert.equal(loaded.api.status().usage.context, 433039);
  // Повторный проход ничего не двигает и не множит.
  beat(loaded);
  assert.equal(loaded.dom.queryAll(`[${WEEK}="row-context"]`).length, 1);
  assert.equal(loaded.dom.queryAll(`[${WEEK}="row-fable"]`).length, 1);
  assert.equal(loaded.dom.query(`[${WEEK}="row-fable"]`).previousSibling, week);
});

test("2.42304: лимитов Fable нет — своей строки нет; dispose() убирает свои строки", () => {
  const loaded = open2({ fable: null });
  beat(loaded);
  assert.equal(loaded.dom.query(`[${WEEK}="row-fable"]`), null);
  loaded.dom.command({ id: "ctx-1", action: "chat-context", at: "now", chat: CHAT, tokens: 120000 });
  assert.ok(loaded.dom.query(`[${WEEK}="row-context"]`));
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`[${WEEK}]`).length, 0, "свои строки пережили dispose()");
});
