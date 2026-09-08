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
  assert.match(text, /Workflow 37/, "номер СВОЙ, из сводки проекта, а не третий по чату");
  assert.doesNotMatch(text, /в проекте/, "«в проекте» не пишется (слово Элвиса 08.09)");
  assert.match(text, /💭 идёт/);
  assert.match(text, /полоска v3/, "«о чём» на месте");
  assert.match(text, /18:09 → 18:50 · 25 мин/, "время на месте");
  assert.match(text, /шаги 1 из 3/);
  assert.match(text, /41 воркфлоу · 26 готово · 39 ч/, "в подвале — счёт проекта из шапки сводки");
});

test("четыре этапа со своим состоянием и «кто»; Fable max — 🔴 и жирным", () => {
  const loaded = open();
  clickSegment(loaded, 2);
  const rows = stageRows(loaded);
  assert.deepEqual(rows.map(row => row.label), ["план", "критик", "кодинг", "проверка"]);
  assert.deepEqual(rows.map(row => row.icon), ["✅", "✅", "💭", "⬜"],
    "пройденные с галочкой, идущий с 💭, будущие пустым квадратом");
  assert.deepEqual(rows.map(row => row.who),
    ["я · Fable xhigh", "1 агент · Opus max", "2 агента · Opus max", "🔴 Fable max"]);
  assert.equal(rows[3].bold, "700", "Fable max — жирным");
  assert.equal(rows[0].bold, "400");
});

test("готовый сегмент — k-й с хвоста среди ✅ (история), будущий — ⬜ после идущего", () => {
  const loaded = open();
  clickSegment(loaded, 1);
  assert.match(card(loaded).textContent, /Workflow 36/, "второй готовый — последний ✅ сводки");
  assert.match(card(loaded).textContent, /✅ готов/);
  assert.match(card(loaded).textContent, /Пимп, открой окно/);

  clickSegment(loaded, 0);
  assert.match(card(loaded).textContent, /Workflow 35/, "первый готовый — предпоследний ✅");
  assert.match(card(loaded).textContent, /темы по id чата/);

  clickSegment(loaded, 3);
  assert.match(card(loaded).textContent, /Workflow 38/, "будущий — первый ⬜ после идущего");
  assert.match(card(loaded).textContent, /⬜ запланирован/);
});

test("сводки на сегмент нет — карточка говорит это прямо", () => {
  const loaded = open();
  // Пятый сегмент: ⬜-блок в сводке только один, второму взяться неоткуда.
  clickSegment(loaded, 4);
  assert.equal(shown(loaded), true);
  const text = card(loaded).textContent;
  assert.match(text, /Воркфлоу 5/, "номер остаётся счётом чата");
  assert.match(text, /сводки нет/);
  assert.equal(card(loaded).children[3].hidden, true, "этапов без сводки не показываем");

  const bare = open({ feed: null });
  clickSegment(bare, 2);
  assert.match(card(bare).textContent, /сводки нет/, "проекта в сводке нет вовсе — то же самое");
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
  assert.match(state.card, /Workflow 36/, "и её слепок тоже");
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
