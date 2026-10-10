// Карточка воркфлоу 9.1 «дорожка в столбик» (WF84, #7205, ТЗ
// docs/design-card-wf84.md, макет docs/9-card-opus-5.5.html): состояния строк
// этапов, строка «сейчас» / «Твой ход» из шапки сводки, цвета от темы окна,
// место над полем ввода, дыхание в общий такт с номером в ряду.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";

const RUN = "⚪[PimpMyClaude](docs/status.md) · WF 3 из 4 · идёт 💭";
const WAIT = "⚪[PimpMyClaude](docs/status.md) · WF 3 из 4 · жду ❓";
const FAIL = "⚪[PimpMyClaude](docs/status.md) · WF 3 из 4 · упал 🛑";
const NOW_TEXT = "кодинг — пишу разбор строки «сейчас»";
const WAIT_TEXT = "ответ на вопрос 8.1";
// Сводка этого чата в том виде, в каком её шлёт приложение с правкой S-K:
// «Сейчас:» и «Ждёт Элвиса:» стоят в шапке, перед первым блоком.
const feed = ({
  updated = "обновлено 12:00", now = `Сейчас: ${NOW_TEXT}`, wait = `Ждёт Элвиса: ${WAIT_TEXT}`,
  third = "💭 идёт", thirdRoles = null, fourthRoles = [],
} = {}) => [
  "# ⚪PimpMyClaude", updated, now, wait, "",
  "1️⃣ Workflow ✅ готово", "- о чём: первый", "- 09:00 → 09:40 · 40 мин",
  "- планирование · я · Opus max", "- кодинг · 2 агента · Opus max", "- проверка · 1 агент · Opus max",
  "2️⃣ Workflow ✅ готово", "- о чём: второй",
  "- планирование · я · Opus max", "- критика · 1 агент · Fable xhigh", "- кодинг · 1 агент · Opus max",
  "- проверка · 1 агент · Opus max",
  `3️⃣ Workflow ${third}`, "- о чём: третий — карточка 9.1", "- шаги 2 из 4", "- 11:00 → закончит в 13:00 · идёт 1 ч",
  ...(thirdRoles ?? [
    "- планирование · я · Opus max", "- критика · 1 агент · Fable xhigh",
    "- кодинг · 2 агента · Opus max 💭", "- проверка · 🔴 **Fable max**",
  ]),
  "4️⃣ Workflow ⬜ запланирован", "- о чём: четвёртый", ...fourthRoles,
].filter(line => line !== null && line !== undefined).join("\n");

const open = ({ line = RUN, text = feed(), top = 620, viewport = { width: 1200, height: 800 }, build = null } = {}) => {
  const loaded = loadInject({
    title: "PimpMyClaude", geometry: { viewport },
    html: dom => {
      const parts = dom.composer({ top });
      dom.document.body.add("div", {
        attrs: { "data-testid": "assistant-message" },
        rect: { left: 100, top: 20, width: 1000, height: 90 }, text: `Готово.\n\n${line}`,
      });
      return { ...parts, ...(build ? build(dom, parts) ?? {} : {}) };
    },
  });
  if (text) loaded.dom.command({ id: "s91", action: "status", at: "now", scope: "all", projects: [{ name: "PimpMyClaude", text }] });
  return loaded;
};
const bar = loaded => loaded.dom.query("#myclaude-progress-bar");
const tipNode = loaded => loaded.dom.query("#myclaude-progress-tip");
const card = loaded => loaded.dom.query("#myclaude-progress-card");
const px = (node, name) => Number(node.style.getPropertyValue(name).replace("px", ""));
const click = (loaded, index) => {
  const row = bar(loaded);
  let x = px(row, "left");
  for (let order = 0; order < index; order += 1) x += px(row.children[order], "width") + px(row, "gap");
  loaded.document.dispatchEvent({ type: "pointerdown", clientX: x + 2, clientY: px(row, "top") + 1 });
};
const tip = loaded => plain(loaded.api.status().progress.tip);
const stages = loaded => card(loaded).children[2];
// Строка этапа: [подсветка, дорожка[отрезок, кружок[знак, ореол]], этап, кто, сейчас].
const row = (loaded, index) => stages(loaded).children[index];
const nodeOf = (loaded, index) => row(loaded, index).children[1].children[1];
const haloOf = (loaded, index) => nodeOf(loaded, index).children[1];
const noteOf = (loaded, index) => row(loaded, index).children[4];
const inside = (root, node) => {
  for (let current = node; current; current = current.parentNode) if (current === root) return true;
  return false;
};
const cardAnims = loaded => loaded.dom.running().filter(item => inside(card(loaded), item.node));

test("идущий N: этапы готов, готов, идёт, впереди; плашка «идёт кодинг»; под кодингом — «Сейчас» из сводки; дышит", () => {
  const loaded = open();
  click(loaded, 2);
  const state = tip(loaded);
  assert.equal(state.open, true);
  assert.deepEqual(state.rows, ["done", "done", "run", "todo"]);
  assert.equal(card(loaded).children[0].children[2].textContent, "идёт кодинг");
  assert.equal(state.note, NOW_TEXT, "строка «Сейчас:» — без приставки");
  assert.equal(noteOf(loaded, 2).style.getPropertyValue("display"), "block", "строка стоит под этапом «кодинг»");
  assert.equal(noteOf(loaded, 1).style.getPropertyValue("display"), "none");
  assert.equal(state.pulse, true);
  assert.equal(cardAnims(loaded).length, 3, "дышат ореол кружка, подсветка строки и точка плашки");
  assert.equal(nodeOf(loaded, 0).children[0].textContent, "✓", "пройденный — галочка на зелёном");
  assert.equal(haloOf(loaded, 2).style.getPropertyValue("display"), "block", "ореол — только у идущего");
  assert.equal(haloOf(loaded, 0).style.getPropertyValue("display"), "none");
  assert.match(state.card, /Воркфлоу 3 · идёт кодинг · третий — карточка 9\.1 · план done я · Opus Max/);
  assert.ok(/ · Начался [^·]*в 11:00 · закончит в 13:00$/.test(state.card), `последней в слепке — строка «когда»: ${state.card}`);
});

test("строка «жду ❓» на N: кружок текущего жёлтый, под ним «Твой ход: …»; карточка не дышит", () => {
  const loaded = open({ line: WAIT });
  click(loaded, 2);
  const state = tip(loaded);
  assert.deepEqual(state.rows, ["done", "done", "wait", "todo"]);
  assert.equal(state.note, `Твой ход: ${WAIT_TEXT}`);
  assert.equal(noteOf(loaded, 2).children[0].textContent, "Твой ход: ", "приставка — отдельным узлом, жирно");
  assert.equal(noteOf(loaded, 2).children[0].style.getPropertyValue("font-weight"), "650");
  assert.equal(nodeOf(loaded, 2).children[0].textContent, "!");
  assert.equal(cardAnims(loaded).length, 0, "«ждёт тебя» в карточке не дышит");
  assert.equal(state.pulse, false);
});

test("«упал 🛑» строки на 💭-блоке и 🛑 в заголовке блока: видно, на каком этапе упал", () => {
  const byLine = open({ line: FAIL });
  click(byLine, 2);
  assert.deepEqual(tip(byLine).rows, ["done", "done", "fail", "todo"]);
  assert.equal(tip(byLine).note, NOW_TEXT, "у упавшего — строка «Сейчас»");
  assert.equal(nodeOf(byLine, 2).children[0].textContent, "✕");
  assert.equal(cardAnims(byLine).length, 0);

  const byBlock = open({ text: feed({ third: "🛑 упал" }) });
  click(byBlock, 2);
  assert.deepEqual(tip(byBlock).rows, ["done", "done", "fail", "todo"], "раньше блок с 🛑 рисовался целиком «впереди»");
  assert.equal(card(byBlock).children[0].children[2].textContent, "упал");
});

test("готовый блок без роли «критика»: строки «критик» нет — три этапа, все ✓ (WF198, #9159: «шаги три из трёх… я четыре шага вижу»); строки «сейчас» нет; готовый не дышит", () => {
  const loaded = open();
  click(loaded, 0);
  assert.deepEqual(tip(loaded).rows, ["done", "done", "done"]);
  assert.equal(tip(loaded).note, null, "«сейчас» — только у воркфлоу N");
  assert.deepEqual([0, 1, 2].map(index => row(loaded, index).children[2].textContent), ["план", "кодинг", "тест"]);
  assert.equal(row(loaded, 3).style.getPropertyValue("display"), "none", "четвёртая строка спрятана");
  assert.equal(row(loaded, 1).children[3].textContent, "Opus Max ×2");
  assert.equal(nodeOf(loaded, 1).children[0].textContent, "✓");
  assert.equal(nodeOf(loaded, 1).style.getPropertyValue("width"), "14px");
  assert.equal(row(loaded, 2).children[1].children[0].style.getPropertyValue("display"), "none", "отрезок дорожки после последнего этапа");
  assert.equal(cardAnims(loaded).length, 0, "раньше плашка «готов» дышала");
  // «Пропущен» точкой — только когда роль так и записана.
  const skipped = open({ text: feed().replace("- 09:00 → 09:40 · 40 мин\n- планирование · я · Opus max\n", "- 09:00 → 09:40 · 40 мин\n- планирование · я · Opus max\n- критика · пропущен\n") });
  click(skipped, 0);
  assert.deepEqual(tip(skipped).rows, ["done", "skip", "done", "done"]);
  assert.equal(nodeOf(skipped, 1).style.getPropertyValue("width"), "6px", "пропущенный — точка 6 × 6");
});

test("запланированный: записанные этапы впереди, «кто» показан, 🔴 Fable Max жирным, «Ещё не начат»", () => {
  const loaded = open({ text: feed({ fourthRoles: ["- кодинг · Opus max", "- проверка · 🔴 **Fable max**"] }) });
  click(loaded, 3);
  assert.deepEqual(tip(loaded).rows, ["todo", "todo"]);
  assert.equal(row(loaded, 1).children[3].textContent, "🔴 Fable Max");
  assert.equal(row(loaded, 1).children[3].style.getPropertyValue("font-weight"), "700");
  assert.equal(card(loaded).children[3].textContent, "Ещё не начат");
  assert.equal(nodeOf(loaded, 0).style.getPropertyValue("width"), "12px", "впереди — пустой контур 12 × 12");
});

test("два 💭-блока при «WF 2 из 4»: карточка 3 идёт на своей 💭-роли без строки «сейчас»; всё дышит в один такт", () => {
  const text = [
    "# ⚪PimpMyClaude", "обновлено 12:00", `Сейчас: ${NOW_TEXT}`, "",
    "1️⃣ Workflow ✅ готово", "- о чём: первый",
    "2️⃣ Workflow 💭 идёт", "- о чём: второй", "- кодинг · Opus max 💭",
    "3️⃣ Workflow 💭 идёт", "- о чём: третий", "- планирование · я · Opus max 💭",
    "4️⃣ Workflow ⬜ запланирован", "- о чём: четвёртый",
  ].join("\n");
  const loaded = open({ line: "⚪[PimpMyClaude](docs/status.md) · WF 2 из 4 · идёт 💭", text });
  click(loaded, 2);
  assert.deepEqual(tip(loaded).rows, ["run"], "в блоке записан один этап — одна строка (WF198)");
  assert.equal(tip(loaded).note, null, "k ≠ N — строки «сейчас» нет");
  const live = loaded.dom.running();
  assert.equal(live.length, 5, "два номера в ряду и три слоя карточки");
  assert.ok(live.every(item => item.options.duration === 3600 && item.startTime === 0), "один такт, одна фаза");
});

test("сводка вчерашняя — «сейчас» нет, остальное на месте; без «Ждёт Элвиса» ждущая карточка без строки", () => {
  const old = open({ text: feed({ updated: "обновлено вчера 12:00" }) });
  click(old, 2);
  assert.equal(tip(old).note, null);
  assert.deepEqual(tip(old).rows, ["done", "done", "run", "todo"]);

  const bare = open({ line: WAIT, text: feed({ wait: null }) });
  click(bare, 2);
  assert.equal(tip(bare).note, null, "старое приложение без S-K — строки нет, а не пустая «Твой ход:»");
  assert.deepEqual(tip(bare).rows, ["done", "done", "wait", "todo"]);
});

test("строка «сейчас» — целиком, без «…» и line-clamp (WF160), разметка остаётся текстом", () => {
  const long = `<b>x</b> ${"очень длинная строка про то, что сейчас делает оркестратор ".repeat(5)}`;
  const loaded = open({ text: feed({ now: `Сейчас: ${long}` }) });
  click(loaded, 2);
  const note = tip(loaded).note;
  assert.equal(note, long.replace(/\s+/g, " ").trim(), "срезано");
  assert.ok(!note.endsWith("…"));
  assert.ok(note.startsWith("<b>x</b>"), "текст как есть — только textContent");
  assert.equal(noteOf(loaded, 2).children[1].textContent, note);
  assert.equal(noteOf(loaded, 2).style.getPropertyValue("-webkit-line-clamp"), "");
  assert.equal(noteOf(loaded, 2).style.getPropertyValue("white-space"), "normal");
});

test("все четыре роли без 💭 и «шаги 0 из 4»: идёт первый этап, а не «проверка»", () => {
  const loaded = open({
    text: feed({
      thirdRoles: ["- шаги 0 из 4", "- планирование · я · Opus max", "- критика · 1 агент · Fable xhigh",
        "- кодинг · 2 агента · Opus max", "- проверка · 1 агент · Opus max"],
    }).replace("- шаги 2 из 4\n", ""),
  });
  click(loaded, 2);
  assert.deepEqual(tip(loaded).rows, ["run", "todo", "todo", "todo"]);
  assert.equal(card(loaded).children[0].children[2].textContent, "идёт план");
});

test("цвета от темы окна: кольцо — акцент, фон — поле + 7 % текста; светлая — само поле; прозрачное поле — --bg-000", () => {
  const themed = (scheme, frame) => open({
    build: (dom, parts) => {
      parts.block.computed = { ...parts.block.computed, "--accent-brand": "120 100% 50%" };
      parts.shell.computed = { ...parts.shell.computed, ...frame };
      dom.document.body.add("div", { class: "epitaxy-root", computed: { "--bg-000": "30 10% 20%" } });
      if (scheme) dom.document.documentElement.computed = { colorScheme: scheme };
    },
  });
  const dark = themed(null, { color: "rgb(230, 230, 230)", backgroundColor: "rgb(40, 40, 40)" });
  click(dark, 2);
  assert.equal(nodeOf(dark, 2).style.getPropertyValue("box-shadow"), "inset 0 0 0 2px hsl(120 100% 50%)");
  assert.equal(tipNode(dark).style.getPropertyValue("background"), "color-mix(in srgb, rgb(40, 40, 40), rgb(230, 230, 230) 7%)");
  assert.equal(tipNode(dark).style.getPropertyValue("color"), "rgb(230, 230, 230)");
  assert.equal(nodeOf(dark, 0).style.getPropertyValue("background"), "rgb(77,187,125)", "готово — зелёный");
  assert.equal(row(dark, 2).children[2].style.getPropertyValue("color"), "hsl(120 100% 50%)", "идущий этап — акцентом");

  const light = themed("light", { color: "rgb(20, 20, 20)", backgroundColor: "rgb(255, 255, 255)" });
  click(light, 2);
  assert.equal(tipNode(light).style.getPropertyValue("background"), "rgb(255, 255, 255)", "в светлой — само поле");
  assert.equal(nodeOf(light, 0).style.getPropertyValue("background"), "rgb(31,154,90)", "G из светлой кожи");

  const clear = themed(null, { color: "rgb(230, 230, 230)" });
  click(clear, 2);
  assert.equal(tipNode(clear).style.getPropertyValue("background"),
    "color-mix(in srgb, hsl(30 10% 20%), rgb(230, 230, 230) 7%)", "прозрачный фон рамки — --bg-000 палитры");
});

test("место: над полем ввода, по его левому краю, шириной min(400, поле); поле у потолка — над номерами", () => {
  const loaded = open();
  tipNode(loaded).rect = { left: 0, top: 0, width: 400, height: 200 };
  click(loaded, 2);
  assert.equal(px(tipNode(loaded), "width"), 400);
  assert.equal(px(tipNode(loaded), "left"), 100, "левый край — край поля");
  assert.equal(px(tipNode(loaded), "top"), 620 - 200 - 8, "низ карточки — на 8 выше поля");
  assert.equal(tip(loaded).anchor, "поле");

  const high = open({ top: 150 });
  tipNode(high).rect = { left: 0, top: 0, width: 400, height: 200 };
  click(high, 2);
  assert.equal(tip(high).anchor, "номера", "поле растянуто до потолка — по-старому, над номерами");
  assert.equal(px(tipNode(high), "top"), Math.max(6, px(bar(high), "top") - 200 - 8));

  const narrow = open({ top: 250, viewport: { width: 280, height: 394 } });
  click(narrow, 2);
  assert.equal(px(tipNode(narrow), "width"), 268, "не шире окна минус поля");
  assert.equal(row(narrow, 0).children[2].style.getPropertyValue("line-height"), "24px", "узкая: строки 24 вместо 28");
  assert.equal(noteOf(narrow, 2).style.getPropertyValue("-webkit-line-clamp"), "", "«сейчас» и в узкой — целиком, с переносом (WF160)");
});

test("«поменьше движения» — ни одной анимации, ореол .6; скрытое окно гасит, вернулось — в той же фазе", () => {
  const loaded = open();
  loaded.win.__reducedMotion = true;
  click(loaded, 2);
  assert.equal(cardAnims(loaded).length, 0, "карточка стоит");
  assert.equal(haloOf(loaded, 2).style.getPropertyValue("opacity"), "0.6");
  assert.equal(tip(loaded).pulse, false);

  const live = open();
  click(live, 2);
  assert.equal(cardAnims(live).length, 3);
  live.document.hidden = true;
  live.document.dispatchEvent({ type: "visibilitychange" });
  assert.equal(cardAnims(live).length, 0, "в скрытом окне карточка не дышит");
  live.document.hidden = false;
  live.document.dispatchEvent({ type: "visibilitychange" });
  assert.equal(cardAnims(live).length, 3);
  assert.ok(cardAnims(live).every(item => item.startTime === 0), "в той же фазе");
});

test("устройство: четыре верхних куска, в этапах четыре строки и запасная строка «сейчас», у последней строки нет отрезка", () => {
  const loaded = open();
  click(loaded, 2);
  assert.equal(card(loaded).children.length, 4);
  assert.equal(stages(loaded).children.length, 5);
  assert.equal(row(loaded, 3).children[1].children[0].style.getPropertyValue("display"), "none");
  assert.equal(row(loaded, 2).children[1].children[0].style.getPropertyValue("display"), "block");
  assert.equal(row(loaded, 1).children[1].children[0].style.getPropertyValue("background"),
    "linear-gradient(color-mix(in srgb, rgb(77,187,125) 85%, transparent), #8b5cf6)", "отрезок к идущему — от зелёного к акценту");
  assert.equal(card(loaded).textContent.includes("💭"), false, "эмодзи в строках больше нет");
});

test("statusParse: «Сейчас:» и «Ждёт Элвиса:» — последние каждого вида; блоки и строки подсказки как без них", () => {
  const { inner } = loadInner();
  const base = feed({ now: null, wait: null });
  const withTail = [feed({ now: "Сейчас: раз", wait: "Ждёт Элвиса: ответ" }), "", "Сейчас: два", "Ждёт Элвиса: **ответ 2**"].join("\n");
  const parsed = plain(inner.statusParse(withTail));
  assert.equal(parsed.now, "два");
  assert.equal(parsed.waitFor, "ответ 2");
  const bare = plain(inner.statusParse(base));
  assert.deepEqual(parsed.blocks, bare.blocks);
  assert.equal(bare.now, "");
});

test("statusParse: «Ждёт пользователя:» — то же, что «Ждёт Элвиса:»; строкой не становится ни блоком, ни ролью", () => {
  const { inner } = loadInner();
  const bare = plain(inner.statusParse(feed({ wait: null })));
  const parsed = plain(inner.statusParse(feed({ wait: "Ждёт пользователя: **ответ на 8.1**" })));
  assert.equal(parsed.waitFor, "ответ на 8.1");
  assert.deepEqual(parsed.blocks, bare.blocks);
  const last = plain(inner.statusParse([feed({ wait: "Ждёт Элвиса: раз" }), "- Ждёт пользователя: два"].join("\n")));
  assert.equal(last.waitFor, "два", "берётся последняя строка любого из двух видов");
});

test("progressCardData: поля для карточки из существующих разборов", () => {
  const loaded = open({ line: WAIT });
  const info = loaded.api.status().progress;
  const data = plain(loaded.inner.progressCardData(3, { wf: 3, of: 4, pct: null, state: "wait", project: "PimpMyClaude" }));
  assert.equal(info.wf, 3);
  assert.equal(data.number, 3);
  assert.equal(data.of, 4);
  assert.equal(data.state, "wait");
  assert.equal(data.word, "ждёт");
  assert.equal(data.about, "третий — карточка 9.1");
  assert.deepEqual(data.steps, { done: 2, total: 4 });
  assert.deepEqual(data.stages.map(stage => stage.name), ["план", "критик", "кодинг", "тест"]);
  assert.equal(data.stages[2].running, true);
  assert.equal(data.waitFor, WAIT_TEXT);
  assert.equal(data.now, NOW_TEXT);
  assert.equal(data.chatWord, "ждёт");
  assert.equal(data.source, "низ ленты");
  assert.equal(data.frozen, false);
  const done = plain(loaded.inner.progressCardData(1, { wf: 3, of: 4, pct: null, state: "wait", project: "PimpMyClaude" }));
  assert.equal(done.waitFor, "", "«Ждёт Элвиса» — только у ждущего N");
  assert.equal(done.now, "");
});

test("#7205: «о чём» — целиком, без многоточия и line-clamp; длинная строка переносится", () => {
  const about = "третий — карточка 9.1, где строка о чём длиннее девяноста знаков и раньше обрезалась многоточием на полуслове";
  assert.ok(about.length > 90);
  const loaded = open({ text: feed().replace("- о чём: третий — карточка 9.1", `- о чём:   ${about}`) });
  click(loaded, 2);
  const node = card(loaded).children[1];
  assert.equal(node.textContent, about, "текст полностью, пробелы — в один");
  assert.equal(node.textContent.includes("…"), false);
  assert.equal(node.style.getPropertyValue("-webkit-line-clamp"), "");
  assert.equal(node.style.getPropertyValue("display"), "block");
  assert.equal(node.style.getPropertyValue("overflow"), "", "ничего не прячется");
  assert.equal(node.style.getPropertyValue("overflow-wrap"), "anywhere", "длинное слово переносится, а не режется");
});
