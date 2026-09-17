// Карточка сегмента полосы прогресса (WF22, раздел 2б inject.js, вариант 3A
// макета docs/mockup-wf22-cards.html): клик по сегменту открывает не строку, а
// карточку одного воркфлоу — «о чём», четыре этапа и кто на каждом, внизу
// строка «когда» (WF70, docs/mockup-wf70-menu-card.html).
//
// Сегмент соединяется со сводкой ПО НОМЕРУ (WF70): с 15.09 status.md держит
// воркфлоу только этого чата и нумерует их с единицы, так что «WF N из M» и
// номер блока — один счёт. Старые сводки нумеровали по проекту — для них
// остался запасной путь по значку («3 vs 37» ниже): готовый сегмент — k-й с
// хвоста среди ✅, идущий — последний 💭, будущий — ⬜ после идущего.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";

// Сводка проекта: два готовых воркфлоу, идущий (💭 у своего этапа) и два
// запланированных. Номера — цепочками клавиш, как в старом docs/status.md
// (по проекту, а не по чату) — на них проверяется запасной путь по значку.
// «обновлено вчера»: у вчерашнего файла строка «когда» пишется абсолютным
// временем и не зависит от часов, в которые гоняют тесты; относительные слова
// проверяются на progressWhen с подставленным «сейчас».
const FEED = [
  "# ⚪PimpMyClaude",
  "обновлено вчера 19:46",
  "",
  "41 воркфлоу",
  "26 готово",
  "39 ч",
  "",
  "3️⃣5️⃣ Workflow ✅ готово",
  "- о чём: темы по id чата",
  "- шаги 3 из 3",
  "- 10:45 → 11:00 · 15 мин",
  "- планирование · 3 агента · Opus max",
  "- кодинг · 2 агента · Opus max",
  "- проверка · 1 агент · Opus max",
  "",
  "3️⃣6️⃣ Workflow ✅ готово",
  "- о чём: «Пимп, открой окно»",
  "- шаги 3 из 3",
  "- 16:00 → 17:20 · 1,3 ч",
  "- планирование · я · Fable high",
  "- критика · 1 агент · Opus max",
  "- кодинг · 2 агента · Opus max",
  "- проверка · 2 агента · Opus max",
  "",
  "3️⃣7️⃣ Workflow 💭 идёт",
  "- о чём: полоска v3 — идущий этап дышит, сегмент заполняется по этапам",
  "- шаги 1 из 3",
  "- 18:09 → 18:50 · 25 мин",
  "- планирование · я · Fable xhigh",
  "- критика · 1 агент · Opus max",
  "- кодинг · 2 агента · Opus max 💭",
  "- проверка · 🔴 **Fable max**",
  "",
  "3️⃣8️⃣ Workflow ⬜ запланирован",
  "- о чём: перестройка страницы",
  "- кодинг · 1 агент · Opus max",
].join("\n");

// Строка состояния этого чата: третий воркфлоу из пяти, идёт. Номера чата (3) и
// сводки (37) нарочно разные — блока № 3 в сводке нет, и работает запасной
// путь по значку.
const LINE = "💭⚪[PimpMyClaude](docs/status.md) · WF 3 из 5 · идёт💭";

const page = line => dom => {
  const parts = dom.composer({ top: 620 });
  dom.document.body.add("div", {
    attrs: { "data-testid": "assistant-message" },
    rect: { left: 100, top: 200, width: 1000, height: 300 },
    text: `Готово.\n\n${line}`,
  });
  return parts;
};

// Окно с полосой и присланной сводкой. width — ширина окна: узкое (367) нужно
// проверке «карточка влезает».
const open = ({ line = LINE, feed = FEED, width = 1200 } = {}) => {
  const loaded = loadInject({
    html: page(line), title: "PimpMyClaude",
    geometry: { viewport: { width, height: 800 } },
  });
  if (feed) {
    loaded.dom.command({
      id: "s1", action: "status", at: "now", scope: "all",
      projects: [{ name: "PimpMyClaude", text: feed }],
    });
  }
  return loaded;
};

const bar = loaded => loaded.dom.query("#myclaude-progress-bar");
const tip = loaded => loaded.dom.query("#myclaude-progress-tip");
const card = loaded => loaded.dom.query("#myclaude-progress-card");
const shown = loaded => tip(loaded).style.getPropertyValue("display") === "block";
// Клик по сегменту: полоса стоит на нижней кромке поля, попадание — ±4 точки.
const clickSegment = (loaded, index) => {
  const box = plain(loaded.api.status().progress);
  const left = Number(bar(loaded).style.getPropertyValue("left").replace("px", ""));
  const width = Number(bar(loaded).style.getPropertyValue("width").replace("px", ""));
  const top = Number(bar(loaded).style.getPropertyValue("top").replace("px", ""));
  const count = box.segments.length || 1;
  const step = (width + 3) / count;
  loaded.document.dispatchEvent({
    type: "pointerdown", clientX: left + step * index + 2, clientY: top + 1,
  });
};
// Прямоугольник карточки стаб сам не считает — задаём его тесту руками, как и
// прочую геометрию (dom.mjs: не задал тест — узел нулевой).
const placeCard = (loaded, rect = { left: 6, top: 300, width: 1188, height: 160 }) => {
  tip(loaded).rect = rect;
};
// Узлы карточки по порядку: шапка, «о чём», этапы, «когда» (WF70: строки
// «время · шаги» и подвала со счётом проекта больше нет).
const stagesNode = loaded => card(loaded).children[2];
const whenNode = loaded => card(loaded).children[3];
// Строки этапов карточки: значок, название, кто.
const stageRows = loaded => stagesNode(loaded).children.map(row => ({
  icon: row.children[0].textContent,
  label: row.children[1].textContent,
  who: row.children[2].textContent,
  bold: row.children[2].style.getPropertyValue("font-weight"),
}));

test("старая сводка (номера по проекту): идущий сегмент открывает блок с 💭, а не с тем же номером", () => {
  const loaded = open();
  assert.equal(shown(loaded), false, "до клика карточки нет");
  clickSegment(loaded, 2);
  assert.equal(shown(loaded), true, "клик по сегменту открыл карточку");
  const text = card(loaded).textContent;
  assert.match(text, /Воркфлоу 37/, "блока № 3 в сводке нет — запасной путь по значку, номер СВОЙ");
  assert.doesNotMatch(text, /в проекте/, "«в проекте» не пишется (слово Элвиса 08.09)");
  assert.match(text, /💭 идёт/);
  assert.match(text, /полоска v3/, "«о чём» на месте");
  assert.equal(whenNode(loaded).textContent, "Идёт · начался в 18:09",
    "внизу строка «когда»: файл вчерашний — без счёта минут");
  assert.equal(card(loaded).children.length, 4, "шапка, «о чём», этапы, «когда» — и больше ничего");
  assert.doesNotMatch(text, /шаги/, "строки «шаги 1 из 3» на карточке нет (#6247)");
  assert.doesNotMatch(text, /18:09 → 18:50/, "и строки «время → время · длительность» нет");
  assert.doesNotMatch(text, /воркфлоу,|готово|39 ч/, "и счёта проекта нет: цифры про проект путали под карточкой одного воркфлоу");
});

test("четыре этапа со своим состоянием и «кто»; Fable max — 🔴 и жирным", () => {
  const loaded = open();
  clickSegment(loaded, 2);
  const rows = stageRows(loaded);
  assert.deepEqual(rows.map(row => row.label), ["план", "критик", "кодинг", "проверка"]);
  assert.deepEqual(rows.map(row => row.icon), ["✅", "✅", "💭", "⬜"],
    "пройденные с галочкой, идущий с 💭, будущие пустым квадратом");
  assert.deepEqual(rows.map(row => row.who),
    ["я · Fable Extra", "Opus Max ×1", "Opus Max ×2", "🔴 Fable Max"],
    "эффорт словами Claude Code, число агентов — после модели (#5907, #5908)");
  assert.equal(rows[3].bold, "700", "Fable max — жирным");
  assert.equal(rows[0].bold, "400");
});

test("старая сводка: готовый сегмент — k-й с хвоста среди ✅ (история), будущий — ⬜ после идущего", () => {
  const loaded = open();
  clickSegment(loaded, 1);
  assert.match(card(loaded).textContent, /Воркфлоу 36/, "второй готовый — последний ✅ сводки");
  assert.match(card(loaded).textContent, /✅ готов/);
  assert.match(card(loaded).textContent, /Пимп, открой окно/);
  assert.equal(whenNode(loaded).textContent, "Завершился вчера в 17:20 · занял 1,3 ч",
    "готовый по вчерашней сводке — «вчера в», длительность из хвоста строки времени");

  clickSegment(loaded, 0);
  assert.match(card(loaded).textContent, /Воркфлоу 35/, "первый готовый — предпоследний ✅");
  assert.match(card(loaded).textContent, /темы по id чата/);

  clickSegment(loaded, 3);
  assert.match(card(loaded).textContent, /Воркфлоу 38/, "будущий — первый ⬜ после идущего");
  assert.match(card(loaded).textContent, /⬜ запланирован/);
  assert.equal(whenNode(loaded).textContent, "Ещё не начат");
});

// ---- блок по номеру (WF70, #6130, #5884) -------------------------------------
// Живая форма docs/status.md с 15.09: только этот чат, номера с единицы. Раньше
// готовый и запланированный сегменты часто оставались без блока («ещё не
// расписан», «уже сделан — не записали»), хотя в файле всё есть.
const OWN_FEED = (updated = "обновлено вчера 14:45") => [
  "# ⚪PimpMyClaude", updated, "", "4 воркфлоу", "2 готово", "1,4 ч потрачено", "",
  "1️⃣ Workflow ✅ готово",
  "- о чём: правая колонка широкого окна не шире строки модели — «Auto» и «Fable 5.1» рядом",
  "- шаги 1 из 1",
  "- 09:45 → 10:35 · 50 мин",
  "- планирование · я · Opus xhigh",
  "- кодинг · я · Opus xhigh",
  "- проверка · 2 агента · Opus max",
  "",
  "2️⃣ Workflow ✅ готово",
  "- о чём: «📋 Копировать в буфер» правой кнопкой по файлу в чате",
  "- шаги 1 из 1",
  "- 12:00 → 12:40 · 40 мин",
  "- планирование · я · Opus max",
  "",
  "3️⃣ Workflow 💭 идёт",
  "- о чём: карточка воркфлоу — внизу «завершился 15 мин назад · занял 50 мин»",
  "- шаги 2 из 4",
  "- 13:00 → закончит в 16:00 · идёт 1,8 ч",
  "- прошлые шаги: планирование · я · Opus max; критика · 1 агент · Fable xhigh",
  "- кодинг · 1 агент · Opus max 💭",
  "- проверка · 1 агент · Fable high",
  "",
  "4️⃣ Workflow ⬜ запланирован",
  "- о чём: вход гостя по SMS — чтобы бонусы со старого сайта заработали",
  "- кодинг · Opus max",
  "- проверка · 🔴 **Fable max**",
].join("\n");
const OWN_LINE = "💭⚪[PimpMyClaude](docs/status.md) · WF 3 из 4 · идёт💭";

test("сводка этого чата: сегмент открывает блок с ТЕМ ЖЕ номером, готовый и будущий — с «о чём» и «кто»", () => {
  const loaded = open({ line: OWN_LINE, feed: OWN_FEED() });
  clickSegment(loaded, 0);
  let text = card(loaded).textContent;
  assert.match(text, /Воркфлоу 1/, "первый сегмент — блок 1️⃣, а не «предпоследний ✅»");
  assert.match(text, /✅ готов/);
  assert.match(text, /правая колонка широкого окна/, "«о чём» готового — из его блока");
  assert.deepEqual(stageRows(loaded).map(row => row.who), ["я · Opus Extra", "—", "я · Opus Extra", "Opus Max ×2"],
    "кто делал готовый — тоже из блока (#5884)");
  assert.equal(whenNode(loaded).textContent, "Завершился вчера в 10:35 · занял 50 мин");

  clickSegment(loaded, 2);
  text = card(loaded).textContent;
  assert.match(text, /Воркфлоу 3/);
  assert.match(text, /💭 идёт кодинг/, "бейдж называет идущий этап");
  assert.deepEqual(stageRows(loaded).map(row => row.icon), ["✅", "✅", "💭", "⬜"]);
  assert.equal(whenNode(loaded).textContent, "Идёт · начался в 13:00 · закончит в 16:00");

  clickSegment(loaded, 3);
  text = card(loaded).textContent;
  assert.match(text, /Воркфлоу 4/);
  assert.match(text, /⬜ запланирован/);
  assert.match(text, /вход гостя по SMS/, "«о чём» запланированного — из блока, а не «ещё не расписан» (#6130)");
  assert.deepEqual(stageRows(loaded).map(row => row.who), ["—", "—", "Opus Max", "🔴 Fable Max"],
    "слово Элвиса 17.09 14:20: в запланированном видно, кто будет делать");
  assert.equal(whenNode(loaded).textContent, "Ещё не начат");
});

test("сводка обновлена сегодня: строка «когда» считает от часов и не падает", () => {
  // Часы тут настоящие, поэтому сверяем по краям — как и гейт по probe.
  const loaded = open({ line: OWN_LINE, feed: OWN_FEED("обновлено 14:45") });
  clickSegment(loaded, 0);
  const when = whenNode(loaded).textContent;
  assert.match(when, /^Завершился /, `готовый: «${when}»`);
  assert.match(when, / · занял 50 мин$/);
  assert.match(when, /только что|назад|в 10:35/, "минуты назад — или абсолютом, если 10:35 ещё не наступило");
  clickSegment(loaded, 2);
  const run = whenNode(loaded).textContent;
  assert.match(run, /^(Идёт|Начался только что)/, `идущий: «${run}»`);
  assert.match(run, / · закончит в 16:00$/);
  assert.equal(plain(loaded.api.status().progress.tip).card.endsWith(run), true,
    "слепок для гейта кончается строкой «когда»");
});

test("живая форма VkusnoffKz: три блока 💭 при «WF 1 из 3» — второй сегмент идёт, а не «запланирован»", () => {
  const feed = [
    "# 🟠VkusnoffKz", "обновлено вчера 15:05", "", "3 воркфлоу", "0 готово", "2 ч потрачено", "",
    "1️⃣ Workflow 💭 идёт", "- о чём: статус заказа для гостя", "- кодинг · 4 агента · Opus max 💭",
    "2️⃣ Workflow 💭 идёт", "- о чём: бот диспетчера — номер кассы правкой сообщения", "- кодинг · 2 агента · Opus max 💭",
    "3️⃣ Workflow 💭 идёт", "- о чём: каталог — герой-карточка", "- кодинг · 5 агентов · Opus max 💭",
  ].join("\n");
  const loaded = loadInject({
    html: page("💭🟠[VkusnoffKz](audit/status.md) · WF 1 из 3 · идёт💭"), title: "VkusnoffKz",
    geometry: { viewport: { width: 1200, height: 800 } },
  });
  loaded.dom.command({ id: "s2", action: "status", at: "now", scope: "all", projects: [{ name: "VkusnoffKz", text: feed }] });
  clickSegment(loaded, 1);
  const text = card(loaded).textContent;
  assert.match(text, /Воркфлоу 2/);
  assert.match(text, /💭 идёт кодинг/, "слово бейджа — из блока, а не из счёта чата");
  assert.doesNotMatch(text, /запланирован/);
  assert.match(text, /бот диспетчера/);
  assert.equal(plain(loaded.api.status().progress.tip).pulse, true, "идущий дышит");
  assert.equal(whenNode(loaded).textContent, "Идёт", "времени в блоке нет — одним словом");
  clickSegment(loaded, 2);
  assert.match(card(loaded).textContent, /Воркфлоу 3/);
});

test("⚠️ в строке состояния сильнее 💭 блока на текущем сегменте: «ждёт тебя», а не «идёт»", () => {
  const loaded = open({ line: "⚠️⚪[PimpMyClaude](docs/status.md) · WF 3 из 4 · жду⚠️", feed: OWN_FEED() });
  clickSegment(loaded, 2);
  const text = card(loaded).textContent;
  assert.match(text, /Воркфлоу 3/);
  assert.match(text, /⚠️ ждёт тебя/, "в сводке значка ⚠️ нет — чат ждёт Элвиса на блоке с 💭");
  assert.equal(whenNode(loaded).textContent, "Ждёт тебя · начался в 13:00");
  assert.equal(plain(loaded.api.status().progress.tip).pulse, false, "ждущая не дышит");
  clickSegment(loaded, 0);
  assert.match(card(loaded).textContent, /✅ готов/, "а готовый сегмент остаётся готовым");
});

// Слово Элвиса 08.09 вечер (#5807): «он же неспроста там ячейка стоит — давай по
// будущему тоже выводить инфу». Блок запланированного воркфлоу в сводке есть —
// значит на карточке обязаны быть и «о чём», и кто его будет делать.
test("будущий воркфлоу: «о чём» и кто будет делать — из своего блока", () => {
  const loaded = open();
  clickSegment(loaded, 3);
  const text = card(loaded).textContent;
  assert.match(text, /Воркфлоу 38/, "номер СВОЙ, из сводки");
  assert.match(text, /⬜ запланирован/);
  assert.match(text, /перестройка страницы/, "«о чём» будущего воркфлоу на месте");
  assert.equal(stagesNode(loaded).hidden, false, "этапы показаны");
  const rows = stageRows(loaded);
  assert.deepEqual(rows.map(row => row.icon), ["⬜", "⬜", "⬜", "⬜"],
    "ни один этап ещё не пройден");
  assert.deepEqual(rows.map(row => row.who), ["—", "—", "Opus Max ×1", "—"],
    "кто будет кодить — уже известно");
});

// Блока на эту ячейку в сводке нет вовсе. Раньше карточка отвечала «сводки нет»,
// и Элвис читал это как поломку (#5807). Теперь она говорит то, что про ячейку
// правда известно: место в счёте чата и что про сам воркфлоу ещё не написали.
test("блока на сегмент нет — карточка говорит словами, а не пустотой", () => {
  const loaded = open();
  // Пятый сегмент: ⬜-блок в сводке только один, второму взяться неоткуда.
  clickSegment(loaded, 4);
  assert.equal(shown(loaded), true);
  const text = card(loaded).textContent;
  assert.match(text, /Воркфлоу 5/, "номер остаётся счётом чата");
  assert.match(text, /5-й из 5 в этом чате/, "и место в счёте названо по-человечески (#5911)");
  assert.match(text, /⬜ запланирован/);
  assert.match(text, /ещё не расписан — что в нём будет, запишем, когда дойдёт очередь/);
  assert.doesNotMatch(text, /сводк/i, "слова «сводка» Элвис на карточке видеть не должен");
  assert.equal(stagesNode(loaded).hidden, true, "этапов без блока не показываем");
  assert.equal(whenNode(loaded).hidden, true, "и строки «когда» без блока нет — про время сказать нечего");
  assert.equal(whenNode(loaded).style.getPropertyValue("display"), "none");

  const bare = open({ feed: null });
  clickSegment(bare, 2);
  const idle = card(bare).textContent;
  assert.match(idle, /что в нём — пока не записали/, "идущий без блока — тем же спокойным тоном");
  assert.doesNotMatch(idle, /сводк/i);
});

// То же у готовых сегментов: ✅-блоков в сводке меньше, чем закрытых воркфлоу у
// чата, — и первый сегмент оставался без блока (#5807, п. 3).
test("готовый сегмент без блока — «уже сделан», а не пустота", () => {
  const feed = [
    "# ⚪PimpMyClaude", "обновлено 19:46", "", "41 воркфлоу", "26 готово", "39 ч", "",
    "3️⃣6️⃣ Workflow ✅ готово", "- о чём: «Пимп, открой окно»", "",
    "3️⃣7️⃣ Workflow 💭 идёт", "- о чём: полоска v3",
  ].join("\n");
  const loaded = open({ feed });
  clickSegment(loaded, 0);
  const text = card(loaded).textContent;
  assert.match(text, /Воркфлоу 1/, "✅-блок на него в сводке не нашёлся");
  assert.match(text, /✅ готов/);
  assert.match(text, /уже сделан — что в нём было, не записали/);
  assert.doesNotMatch(text, /сводк/i);

  clickSegment(loaded, 1);
  assert.match(card(loaded).textContent, /Воркфлоу 36/, "а второму готовому блок достался");
  assert.match(card(loaded).textContent, /Пимп, открой окно/);
});

test("карточка влезает в узкое окно: ширина = окно − 12, потолок 60 % высоты", () => {
  const loaded = open({ width: 367 });
  clickSegment(loaded, 2);
  const style = tip(loaded).style;
  assert.equal(style.getPropertyValue("width"), "355px", "367 − 12");
  assert.equal(style.getPropertyValue("max-height"), "480px", "60 % от 800");
  assert.equal(style.getPropertyValue("left"), "6px", "в узком окне карточке места у полосы нет — к краю");
  assert.equal(style.getPropertyValue("white-space"), "normal", "текст переносится, а не режется");
  assert.equal(style.getPropertyValue("overflow"), "hidden", "прокрутки нет — лишнее уходит под обрез");
});

test("низкое окно 280×394 (#5915): у готового воркфлоу на карточке ровно четыре куска под потолком 236", () => {
  // Высоту стенд не считает (раскладки у стаба нет) — замер живьём на гейте:
  // scrollHeight карточки против clientHeight. Здесь — что на ней осталось
  // после WF70: шапка, «о чём», четыре этапа, «когда»; узлов больше нет.
  // Поле ввода — внутри низкого окна, иначе полосе не на чем стоять.
  const low = dom => {
    const parts = dom.composer({ top: 250 });
    dom.document.body.add("div", {
      attrs: { "data-testid": "assistant-message" },
      rect: { left: 10, top: 20, width: 260, height: 200 }, text: `Готово.\n\n${OWN_LINE}`,
    });
    return parts;
  };
  const loaded = loadInject({
    html: low, title: "PimpMyClaude", geometry: { viewport: { width: 280, height: 394 } },
  });
  loaded.dom.command({ id: "s3", action: "status", at: "now", scope: "all", projects: [{ name: "PimpMyClaude", text: OWN_FEED() }] });
  clickSegment(loaded, 0);
  const style = tip(loaded).style;
  assert.equal(style.getPropertyValue("width"), "268px", "280 − 12");
  assert.equal(style.getPropertyValue("max-height"), "236px", "60 % от 394");
  const kids = card(loaded).children;
  assert.equal(kids.length, 4);
  assert.deepEqual(kids.map(node => Boolean(node.hidden)), [false, false, false, false], "все четыре куска показаны");
  assert.equal(kids[1].style.getPropertyValue("-webkit-line-clamp"), "2", "«о чём» — не выше двух строк");
  assert.equal(kids[3].style.getPropertyValue("-webkit-line-clamp"), "2", "«когда» — тоже");
});

test("клик по самой карточке её не закрывает, клик мимо и Escape — закрывают", () => {
  const loaded = open();
  clickSegment(loaded, 2);
  placeCard(loaded);
  loaded.document.dispatchEvent({ type: "pointerdown", clientX: 200, clientY: 380 });
  assert.equal(shown(loaded), true, "клик внутри карточки её не гасит");

  loaded.document.dispatchEvent({ type: "pointerdown", clientX: 600, clientY: 120 });
  assert.equal(shown(loaded), false, "клик мимо закрывает");

  clickSegment(loaded, 2);
  assert.equal(shown(loaded), true);
  loaded.win.dispatchEvent({ type: "keydown", key: "Escape" });
  assert.equal(shown(loaded), false, "Escape закрывает");
});

test("повторный клик по тому же сегменту закрывает, по другому — переключает", () => {
  const loaded = open();
  clickSegment(loaded, 2);
  assert.equal(plain(loaded.api.status().progress.tip).segment, 2);
  clickSegment(loaded, 2);
  assert.equal(shown(loaded), false);
  clickSegment(loaded, 1);
  const state = plain(loaded.api.status().progress.tip);
  assert.equal(state.open, true);
  assert.equal(state.segment, 1);
  assert.equal(state.variant, "3A", "вариант карточки виден гейту");
  assert.match(state.card, /Воркфлоу 36/, "и её слепок тоже");
});

test("карточка идущего и готового дышит, ждущая — нет; dispose() гасит", () => {
  const loaded = open();
  clickSegment(loaded, 2);
  assert.equal(plain(loaded.api.status().progress.tip).pulse, true, "«идёт» дышит");
  assert.ok(loaded.dom.running().some(item => item.node === card(loaded).children[0].children[2]),
    "дышит именно плашка состояния");
  clickSegment(loaded, 3);
  assert.equal(plain(loaded.api.status().progress.tip).pulse, false, "«запланирован» стоит");

  const wait = open({ line: "✋⚪[PimpMyClaude](docs/status.md) · WF 3 из 5 · жду✋" });
  clickSegment(wait, 2);
  assert.equal(plain(wait.api.status().progress.tip).pulse, false, "«ждёт Элвиса» не дышит");

  clickSegment(loaded, 2);
  loaded.api.dispose();
  assert.equal(loaded.dom.running().length, 0, "после dispose ни одной живой анимации");
  assert.equal(loaded.dom.queryAll("#myclaude-progress-card").length, 0, "и узла карточки в окне нет");
});

test("строка состояния пропала — карточка закрыта совсем и сама не всплывает", () => {
  // Переход по сайдбару в другой чат заменяет ленту целиком: строка состояния
  // пропадает, а потом появляется снова — уже чужая. Раньше карточка на этом
  // возвращалась САМА, без клика, поверх поля ввода (находка ревизии 08.09).
  const loaded = open();
  clickSegment(loaded, 2);
  assert.equal(shown(loaded), true, "клик открыл карточку");
  const message = loaded.dom.query('[data-testid="assistant-message"]');
  message.textContent = "Привет, чем займёмся?";
  loaded.dom.fireKind("interval");
  assert.equal(shown(loaded), false, "строки нет — карточки нет");
  assert.equal(plain(loaded.api.status().progress.tip).open, false,
    "и гейту она больше не рассказывает про открытую");
  message.textContent = `Готово.\n\n${LINE}`;
  loaded.dom.fireKind("interval");
  assert.equal(shown(loaded), false, "строка вернулась — карточка ждёт клика");
  clickSegment(loaded, 2);
  assert.equal(shown(loaded), true, "по клику открывается как прежде");
});

// ---- карточка говорит человеческими словами (WF60, #5907–#5911) -------------
// Сводку пишут агенты своими словами и по своему шаблону; карточку читает
// Элвис. Всё, что ниже, — про ПОКАЗ: файлы сводок остаются как есть, меняется
// то, что видно глазами.

// Сводка на один идущий воркфлоу: роли подставляются строками.
const roleFeed = (roles) => [
  "# ⚪PimpMyClaude", "обновлено вчера 19:46", "", "2 воркфлоу", "0 готово", "12 мин", "",
  "7️⃣ Workflow 💭 идёт", "- о чём: карточка словами",
  ...roles,
].join("\n");
const whoRows = (roles) => {
  const loaded = open({ feed: roleFeed(roles) });
  clickSegment(loaded, 2);
  return stageRows(loaded).map(row => row.who);
};

test("эффорт пишется словами самого Claude Code: xhigh → Extra (#5907)", () => {
  assert.deepEqual(whoRows([
    "- планирование · я · Fable xhigh",
    "- критика · 1 агент · Fable low",
    "- кодинг · 1 агент · Opus medium 💭",
    "- проверка · 1 агент · Opus high",
  ]), ["я · Fable Extra", "Fable Low ×1", "Opus Medium ×1", "Opus High ×1"]);
});

test("слова, которого нет у ползунка Effort, не выдумываем — показываем как есть", () => {
  assert.deepEqual(whoRows([
    "- планирование · я · Fable ultra",
    "- кодинг · 2 агента · Opus 💭",
    "- проверка · 🔴 **Fable max**",
  ]), ["я · Fable ultra", "—", "Opus ×2", "🔴 Fable Max"]);
});

test("число агентов стоит после модели со знаком ×, «N агентов» в карточку не попадает (#5908, #5976)", () => {
  assert.deepEqual(whoRows([
    "- планирование · я · Fable xhigh",
    "- критика · 1 агент · Fable high",
    "- кодинг · 2 агента · Opus max 💭",
    "- проверка · 2 агента · Fable xhigh ×1, Fable high ×1",
  ]), ["я · Fable Extra", "Fable High ×1", "Opus Max ×2", "Fable Extra ×1, Fable High ×1"]);
});

test("моделей больше двух — хвост прячется за «и ещё N»", () => {
  // В окне 280 колонка «кто» всего 126 точек: полный список занимает три
  // строчки карточки, сокращённый — две.
  assert.deepEqual(whoRows([
    "- кодинг · 12 агентов · Opus max ×5, Opus high ×6, Opus medium ×1 💭",
  ])[2], "Opus Max ×5, Opus High ×6 и ещё 1");
});

test("у закрытых этапов видно, кто их делал — из строки «прошлые шаги» (#5977)", () => {
  // Так пишет сводка, когда прогон ушёл дальше: роли текущего шага отдельными
  // строками, а пройденные — одной строкой через «;». До правки у плана и
  // критика на карточке стоял прочерк, хотя галочки были.
  assert.deepEqual(whoRows([
    "- прошлые шаги: планирование · я · Opus max; критика · 1 агент · Fable xhigh",
    "- кодинг · 1 агент · Opus max 💭",
  ]), ["я · Opus Max", "Fable Extra ×1", "Opus Max ×1", "—"]);
});

test("«я» остаётся, даже когда рядом стоит число: «я + 1 агент»", () => {
  // Реальная строка из docs/status.md самого проекта. До правки гейта Элвис
  // пропадал со своей же строки плана — оставались одни модели.
  assert.deepEqual(whoRows(["- планирование · я + 1 агент · Fable xhigh, Opus max"])[0],
    "я · Fable Extra, Opus Max");
});

test("части одной записи, разделённые «·», за две модели не считаются", () => {
  // Так пишет Codex/Astra в 🟡DrStrange: «·» у него разделяет части ОДНОЙ
  // записи, и когда мы резали список ещё и по ней, имя модели пропадало совсем.
  const who = whoRows([
    "- проверка · project_audit независимо, root по интерфейсу · gpt-6-astra 💭",
  ])[3];
  assert.ok(who.includes("gpt-6-astra"), `модель потерялась: «${who}»`);
});

test("Fable max спрятался за «и ещё N» — строка не жирная", () => {
  const loaded = open({ feed: roleFeed([
    "- кодинг · Opus max ×2, Opus high ×3, 🔴 **Fable max** ×1 💭",
  ]) });
  clickSegment(loaded, 2);
  const row = stageRows(loaded)[2];
  assert.ok(!row.who.includes("🔴"), `кружок показан у спрятанной записи: «${row.who}»`);
  assert.notEqual(row.weight, "700", "строка жирная, а красного кружка в ней не видно");
});

test("модели нет вовсе — строка роли показывается как написана, а не прочерком", () => {
  assert.deepEqual(whoRows(["- кодинг · 2 агента 💭"])[2], "2 агента");
});

// ---- строка «когда» (WF70, #6247) --------------------------------------------
// Слово Элвиса 17.09 12:50: подвал «2 воркфлоу, 2 готово · 1,4 ч» и строка
// «09:45 → 10:35 · 50 мин · шаги 1 из 1» путают — вместо них одна человеческая
// строка про этот воркфлоу. progressWhen чистая: «сейчас» и дата файла
// подставляются, поэтому здесь проверяются точные слова.
const when = (block, at, updated = { kind: "today", time: "12:00" }) =>
  loadInner().inner.progressWhen(block, at, updated);
const clock = (hours, minutes) => new Date(2026, 8, 17, hours, minutes).getTime();
const DONE = { state: "done", time: "09:45 → 10:35 · 50 мин" };
const RUN = { state: "run", time: "13:05 → закончит в 16:00 · идёт 1,8 ч" };

test("готовый по сегодняшней сводке: «только что», «N мин назад», «N ч назад» · «занял»", () => {
  assert.equal(when(DONE, clock(10, 35)), "Завершился только что · занял 50 мин");
  assert.equal(when(DONE, clock(10, 50)), "Завершился 15 мин назад · занял 50 мин");
  assert.equal(when(DONE, clock(12, 35)), "Завершился 2 ч назад · занял 50 мин");
  assert.equal(when(DONE, clock(12, 5)), "Завершился 1,5 ч назад · занял 50 мин",
    "часы с одним знаком и запятой — как в сводке");
});

test("готовый не по сегодняшней сводке — абсолютом: «вчера в», дата, просто «в»", () => {
  assert.equal(when(DONE, clock(12, 0), { kind: "yesterday", time: "03:10" }), "Завершился вчера в 10:35 · занял 50 мин");
  assert.equal(when(DONE, clock(12, 0), { kind: "date", time: "15.09" }), "Завершился 15.09 в 10:35 · занял 50 мин");
  assert.equal(when(DONE, clock(12, 0), null), "Завершился в 10:35 · занял 50 мин", "строки «обновлено» нет — считать не от чего");
  assert.equal(when(DONE, clock(9, 0)), "Завершился в 10:35 · занял 50 мин",
    "сегодня, но 10:35 позже «сейчас» — часы в сводке чужие, «назад» не пишем");
});

test("«занял» без хвоста — разница часов, через полночь с добавкой суток; времени нет — одно слово", () => {
  assert.equal(when({ state: "done", time: "23:50 → 00:20" }, clock(0, 30)), "Завершился 10 мин назад · занял 30 мин");
  assert.equal(when({ state: "done", time: "09:45 → 11:15" }, clock(9, 0), null), "Завершился в 11:15 · занял 1,5 ч");
  assert.equal(when({ state: "done", time: "13:05 → 14:00 · идёт 1,8 ч" }, clock(9, 0), null),
    "Завершился в 14:00 · занял 55 мин", "хвост не длительность (закрыли, не переписав время) — считаем сами");
  assert.equal(when({ state: "done", time: "" }, clock(12, 0)), "Завершился");
  assert.equal(when({ state: "done", time: "10:00 · 40 мин" }, clock(12, 0), null), "Завершился · занял 40 мин");
});

test("идущий: «Идёт N мин · начался в · закончит в», без сегодняшней сводки — без счёта минут", () => {
  assert.equal(when(RUN, clock(13, 30)), "Идёт 25 мин · начался в 13:05 · закончит в 16:00");
  assert.equal(when(RUN, clock(15, 0)), "Идёт 1,9 ч · начался в 13:05 · закончит в 16:00");
  assert.equal(when(RUN, clock(13, 5)), "Начался только что · закончит в 16:00");
  assert.equal(when(RUN, clock(13, 30), { kind: "yesterday", time: "" }), "Идёт · начался в 13:05 · закончит в 16:00");
  assert.equal(when({ state: "run", time: "18:09 → 18:50 · 25 мин" }, clock(18, 30)), "Идёт 21 мин · начался в 18:09",
    "справа не «закончит», а конец, как пишут старые сводки, — срок не выдумываем");
  assert.equal(when({ state: "run", time: "" }, clock(12, 0)), "Идёт");
});

test("«примерно» из строки времени на показе убрано (#5909)", () => {
  // В шаблоне правил слова больше нет, в десятках написанных сводок — есть.
  assert.equal(when({ state: "run", time: "21:15 → закончит примерно в 23:30 · идёт 45 мин" }, clock(22, 0)),
    "Идёт 45 мин · начался в 21:15 · закончит в 23:30");
});

test("ждёт тебя, упал, запланирован, блока нет", () => {
  assert.equal(when({ ...RUN, state: "wait" }, clock(13, 45)), "Ждёт тебя · идёт 40 мин");
  assert.equal(when({ ...RUN, state: "wait" }, clock(13, 45), null), "Ждёт тебя · начался в 13:05",
    "срока «закончит» у ждущего нет — работа стоит");
  assert.equal(when({ state: "wait", time: "" }, clock(13, 45)), "Ждёт тебя");
  assert.equal(when({ ...RUN, state: "fail" }, clock(13, 45)), "Упал · начался в 13:05");
  assert.equal(when({ state: "todo", time: "" }, clock(13, 45)), "Ещё не начат");
  assert.equal(when({ state: "todo", time: "13:05 → закончит в 16:00" }, clock(13, 45)), "Ещё не начат");
  assert.equal(when(null, clock(13, 45)), "");
});

test("statusParse: дата файла из строки «обновлено» — сегодня, вчера, число; нет строки — null", () => {
  const { inner } = loadInner();
  const updated = text => plain(inner.statusParse(text)).updated;
  assert.deepEqual(updated("# ⚪PimpMyClaude\nобновлено 12:40\n\n1️⃣ Workflow ✅ готово"), { kind: "today", time: "12:40" });
  assert.deepEqual(updated("# ⚪PimpMyClaude\nОбновлено: сегодня 12:40\n"), { kind: "today", time: "12:40" });
  assert.deepEqual(updated("# ⚪PimpMyClaude\nобновлено вчера 03:10\n"), { kind: "yesterday", time: "03:10" });
  assert.deepEqual(updated("# ⚪PimpMyClaude\nОбновлено вчера\n"), { kind: "yesterday", time: "" });
  assert.deepEqual(updated("# ⚪PimpMyClaude\nобновлено 15.09\n"), { kind: "date", time: "15.09" });
  assert.deepEqual(updated("# ⚪PimpMyClaude\nобновлено 15.09.2026 22:10\n"), { kind: "date", time: "15.09.2026" });
  assert.equal(updated("# ⚪PimpMyClaude\n\n4 воркфлоу\n"), null);
  assert.equal(updated("# ⚪PimpMyClaude\nобновлено давно\n"), null, "непонятное слово — не сегодня и не дата");
  assert.equal(updated("1️⃣ Workflow ✅ готово\n- обновлено 12:40"), null, "строка внутри блока — пункт блока, а не дата файла");
  assert.deepEqual(plain(inner.statusBlocks("1️⃣ Workflow ✅ готово\n- о чём: раз")).map(block => block.about), ["раз"],
    "разбор блоков не тронут");
});

test("строке «когда» разрешены две строки: перенос вместо обрыва на полуслове", () => {
  const loaded = open();
  clickSegment(loaded, 2);
  const node = whenNode(loaded);
  assert.equal(node.style.getPropertyValue("white-space"), "", "нет nowrap — текст переносится");
  assert.equal(node.style.getPropertyValue("-webkit-line-clamp"), "2");
  assert.equal(node.style.getPropertyValue("display"), "-webkit-box",
    "показ пишется в самом узле: [hidden] слабее объявления в узле");
  assert.equal(node.style.getPropertyValue("font-weight"), "600", "полужирная, как в макете");
});

// ---- Гейт WF70: три правки по проверке Fable high ------------------------

test("сводка с сегодняшней датой в «обновлено» считается сегодняшней: «N мин назад», а не «17.09.2026 в»", () => {
  assert.equal(when(DONE, clock(10, 50), { kind: "date", time: "17.09.2026" }), "Завершился 15 мин назад · занял 50 мин");
  assert.equal(when(DONE, clock(10, 50), { kind: "date", time: "17.09" }), "Завершился 15 мин назад · занял 50 мин");
  assert.equal(when(DONE, clock(10, 50), { kind: "date", time: "17.09.26" }), "Завершился 15 мин назад · занял 50 мин");
  assert.equal(when(DONE, clock(10, 50), { kind: "date", time: "16.09.2026" }), "Завершился 16.09.2026 в 10:35 · занял 50 мин",
    "вчерашняя дата — абсолютом, как и раньше");
});

test("строка чата уже 💭 на воркфлоу, чей блок ещё ⬜: карточка идёт за строкой, а не твердит «Ещё не начат»", () => {
  const feed = OWN_FEED().replace("3️⃣ Workflow 💭 идёт", "3️⃣ Workflow ⬜ запланирован");
  const loaded = open({ line: OWN_LINE, feed });
  clickSegment(loaded, 2);
  const text = card(loaded).textContent;
  assert.match(text, /Воркфлоу 3/);
  assert.match(text, /💭 идёт/, "бейдж остался «запланирован» при 💭 в строке чата");
  assert.match(whenNode(loaded).textContent, /^Идёт/, "«когда» твердит «Ещё не начат»");
  // Другой запланированный блок (не текущий) строке чата не подчиняется.
  clickSegment(loaded, 3);
  assert.match(card(loaded).textContent, /⬜ запланирован/);
  assert.equal(whenNode(loaded).textContent, "Ещё не начат");
});

test("открытая карточка тикает раз в минуту своим интервалом; закрылась или dispose — интервала нет", () => {
  const loaded = open({ line: OWN_LINE, feed: OWN_FEED() });
  const base = loaded.counters.intervals;
  clickSegment(loaded, 0);
  assert.ok(shown(loaded));
  assert.equal(loaded.counters.intervals, base + 1, "интервал не завёлся вместе с карточкой");
  clickSegment(loaded, 2);
  assert.equal(loaded.counters.intervals, base + 1, "переключение сегмента завело второй интервал");
  loaded.dom.fireKind("interval");
  assert.ok(shown(loaded), "тик закрыл карточку");
  clickSegment(loaded, 2);
  assert.ok(!shown(loaded));
  assert.equal(loaded.counters.intervals, base, "интервал пережил закрытие карточки");
  clickSegment(loaded, 1);
  assert.equal(loaded.counters.intervals, base + 1);
  loaded.api.dispose();
  assert.equal(loaded.counters.intervals, 0, "интервал пережил dispose()");
});
