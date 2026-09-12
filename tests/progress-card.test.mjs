// Карточка сегмента полосы прогресса (WF22, раздел 2б inject.js, вариант 3A
// макета docs/mockup-wf22-cards.html): клик по сегменту открывает не строку, а
// карточку одного воркфлоу — «о чём», время, шаги, четыре этапа и кто на каждом.
//
// Главное, ради чего этот набор писался: сегмент соединяется со сводкой ПО
// ЗНАЧКУ, а не по номеру. «WF N из M» считает воркфлоу этого чата, status.md
// нумерует их по проекту (решение Элвиса 05.09, docs/PROGRESS.md), и совпадение
// номеров было бы случайностью.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

// Сводка проекта: два готовых воркфлоу, идущий (💭 у своего этапа) и два
// запланированных. Номера — цепочками клавиш, как в настоящем docs/status.md.
const FEED = [
  "# ⚪PimpMyClaude",
  "обновлено 19:46",
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
// сводки (37) нарочно разные — по ним и видно, что соединение идёт по значку.
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
// Строки этапов карточки: значок, название, кто.
const stageRows = loaded => card(loaded).children[3].children.map(row => ({
  icon: row.children[0].textContent,
  label: row.children[1].textContent,
  who: row.children[2].textContent,
  bold: row.children[2].style.getPropertyValue("font-weight"),
}));

test("клик по идущему сегменту открывает карточку блока с 💭, а не с тем же номером", () => {
  const loaded = open();
  assert.equal(shown(loaded), false, "до клика карточки нет");
  clickSegment(loaded, 2);
  assert.equal(shown(loaded), true, "клик по сегменту открыл карточку");
  const text = card(loaded).textContent;
  assert.match(text, /Воркфлоу 37/, "номер СВОЙ, из сводки проекта, а не третий по чату");
  assert.doesNotMatch(text, /в проекте/, "«в проекте» не пишется (слово Элвиса 08.09)");
  assert.match(text, /💭 идёт/);
  assert.match(text, /полоска v3/, "«о чём» на месте");
  assert.match(text, /18:09 → 18:50 · 25 мин/, "время на месте");
  assert.match(text, /шаги 1 из 3/);
  assert.match(text, /41 воркфлоу, 26 готово · 39 ч/, "в подвале — счёт проекта, собранный из чисел шапки");
});

test("четыре этапа со своим состоянием и «кто»; Fable max — 🔴 и жирным", () => {
  const loaded = open();
  clickSegment(loaded, 2);
  const rows = stageRows(loaded);
  assert.deepEqual(rows.map(row => row.label), ["план", "критик", "кодинг", "проверка"]);
  assert.deepEqual(rows.map(row => row.icon), ["✅", "✅", "💭", "⬜"],
    "пройденные с галочкой, идущий с 💭, будущие пустым квадратом");
  assert.deepEqual(rows.map(row => row.who),
    ["я · Fable Extra", "Opus Max 1", "Opus Max 2", "🔴 Fable Max"],
    "эффорт словами Claude Code, число агентов — после модели (#5907, #5908)");
  assert.equal(rows[3].bold, "700", "Fable max — жирным");
  assert.equal(rows[0].bold, "400");
});

test("готовый сегмент — k-й с хвоста среди ✅ (история), будущий — ⬜ после идущего", () => {
  const loaded = open();
  clickSegment(loaded, 1);
  assert.match(card(loaded).textContent, /Воркфлоу 36/, "второй готовый — последний ✅ сводки");
  assert.match(card(loaded).textContent, /✅ готов/);
  assert.match(card(loaded).textContent, /Пимп, открой окно/);

  clickSegment(loaded, 0);
  assert.match(card(loaded).textContent, /Воркфлоу 35/, "первый готовый — предпоследний ✅");
  assert.match(card(loaded).textContent, /темы по id чата/);

  clickSegment(loaded, 3);
  assert.match(card(loaded).textContent, /Воркфлоу 38/, "будущий — первый ⬜ после идущего");
  assert.match(card(loaded).textContent, /⬜ запланирован/);
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
  assert.equal(card(loaded).children[3].hidden, false, "этапы показаны");
  const rows = stageRows(loaded);
  assert.deepEqual(rows.map(row => row.icon), ["⬜", "⬜", "⬜", "⬜"],
    "ни один этап ещё не пройден");
  assert.deepEqual(rows.map(row => row.who), ["—", "—", "Opus Max 1", "—"],
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
  assert.equal(card(loaded).children[3].hidden, true, "этапов без блока не показываем");

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
const roleFeed = (roles, head = ["2 воркфлоу", "0 готово", "12 мин"]) => [
  "# ⚪PimpMyClaude", "обновлено 19:46", "", ...head, "",
  "7️⃣ Workflow 💭 идёт", "- о чём: карточка словами",
  ...roles,
].join("\n");
const whoRows = (roles, head) => {
  const loaded = open({ feed: roleFeed(roles, head) });
  clickSegment(loaded, 2);
  return stageRows(loaded).map(row => row.who);
};

test("эффорт пишется словами самого Claude Code: xhigh → Extra (#5907)", () => {
  assert.deepEqual(whoRows([
    "- планирование · я · Fable xhigh",
    "- критика · 1 агент · Fable low",
    "- кодинг · 1 агент · Opus medium 💭",
    "- проверка · 1 агент · Opus high",
  ]), ["я · Fable Extra", "Fable Low 1", "Opus Medium 1", "Opus High 1"]);
});

test("слова, которого нет у ползунка Effort, не выдумываем — показываем как есть", () => {
  assert.deepEqual(whoRows([
    "- планирование · я · Fable ultra",
    "- кодинг · 2 агента · Opus 💭",
    "- проверка · 🔴 **Fable max**",
  ]), ["я · Fable ultra", "—", "Opus 2", "🔴 Fable Max"]);
});

test("число агентов стоит после модели, «N агентов» и «×N» в карточку не попадают (#5908)", () => {
  assert.deepEqual(whoRows([
    "- планирование · я · Fable xhigh",
    "- критика · 1 агент · Fable high",
    "- кодинг · 2 агента · Opus max 💭",
    "- проверка · 2 агента · Fable xhigh ×1, Fable high ×1",
  ]), ["я · Fable Extra", "Fable High 1", "Opus Max 2", "Fable Extra 1, Fable High 1"]);
});

test("моделей больше двух — хвост прячется за «и ещё N»", () => {
  // В окне 280 колонка «кто» всего 126 точек: полный список занимает три
  // строчки карточки, сокращённый — две.
  assert.deepEqual(whoRows([
    "- кодинг · 12 агентов · Opus max ×5, Opus high ×6, Opus medium ×1 💭",
  ])[2], "Opus Max 5, Opus High 6 и ещё 1");
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

test("«примерно» из строки времени на показе убрано (#5909)", () => {
  const loaded = open({ feed: roleFeed([
    "- 21:15 → закончит примерно в 23:30 · идёт 45 мин",
    "- кодинг · 1 агент · Opus max 💭",
  ]) });
  clickSegment(loaded, 2);
  const text = card(loaded).textContent;
  assert.match(text, /21:15 → закончит в 23:30 · идёт 45 мин/, "время осталось целым, слово ушло");
  assert.doesNotMatch(text, /примерно/, "«примерно» Элвис на карточке видеть не должен");
});

test("подвал собран из чисел шапки, а слово «воркфлоу» своё (#5910, #5911)", () => {
  // Шапки у проектов написаны вразнобой — карточка берёт из них числа.
  const foot = (head) => {
    const loaded = open({ feed: roleFeed(["- кодинг · 1 агент · Opus max 💭"], head) });
    clickSegment(loaded, 2);
    return card(loaded).children[4].textContent;
  };
  assert.equal(foot(["1 воркфлоу этого чата", "0 готово", "45 мин потрачено"]),
    "PimpMyClaude · 1 воркфлоу, 0 готово · 45 мин");
  assert.equal(foot(["7 воркфлоу в этом чате", "3 готово", "4,2 ч учтено"]),
    "PimpMyClaude · 7 воркфлоу, 3 готово · 4,2 ч");
  assert.equal(foot(["2 воркфлоу", "1 готово", "1,5 суток потрачено"]),
    "PimpMyClaude · 2 воркфлоу, 1 готово · 1,5 суток");
  assert.equal(foot(["2 воркфлоу", "1 готово", "3 макета ждут ответа"]),
    "PimpMyClaude · 2 воркфлоу, 1 готово · 3 макета ждут ответа",
    "строку, из которой числа не достали, показываем как есть — терять нельзя ничего");
});

test("подвалу разрешены две строки: перенос вместо обрыва на полуслове", () => {
  const loaded = open();
  clickSegment(loaded, 2);
  const foot = card(loaded).children[4];
  assert.equal(foot.style.getPropertyValue("white-space"), "", "нет nowrap — текст переносится");
  assert.equal(foot.style.getPropertyValue("-webkit-line-clamp"), "2");
  assert.equal(foot.style.getPropertyValue("display"), "-webkit-box",
    "показ пишется в самом узле: [hidden] слабее объявления в узле");
});
