// WF195 (слова Элвиса 09.10 04:05–04:15: «Op5.5 — мелко написать, только мелко. Bypass permissions — Bp — должно
// называться, чтоб люди понимали. Внизу опять всё едет — давай уже нормально»; #9288 «три колонки», ничего не вылезает).
//   — подписи нижней строки коротко ПРИ ЛЮБОЙ ширине (Bp · Op5.5 · Ex), полное имя — подсказкой title;
//   — пол правой колонки по короткой строке без замкнутого круга: распорка Claude (flex-1, без кнопок) —
//     свободное место; до WF195 запас мерился от её правого края (всегда 0), пол рос на 4 каждый проход
//     (живое окно Рика 09.10: сохранённая ширина 258, пол 407, колонка 419 — docs/live-190.png);
//   — колонка остаётся шириной, которую выбрал человек (myclaude-wide-side-v2), пол — только минимум.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const SIDE_KEY = "myclaude-wide-side-v2";
const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};

// Панель широкого вида в форме замера (как layout.test.mjs), правый край доки — 1100, колонка = дока − 12.
// Нижняя строка — как в окне Рика 09.10 (probe): ряд --cmp-chin-start из трёх детей — левая группа
// (плюс, режим), распорка «flex min-w-0 flex-1 basis-0» без кнопок и правая группа ms-auto (модель, эффорт,
// кружок токенов последним).
const stand = dom => {
  const panel = dom.document.body.add("div", { class: "epitaxy-chat-panel", rect: { left: 200, top: 0, width: 900, height: 800 }, computed: { "--myclaude-wide": "1" } });
  const grid = panel.add("div", { class: "relative h-full min-w-0 flex flex-col", rect: { left: 200, top: 0, width: 900, height: 800 } });
  grid.add("div", { class: "epitaxy-titlebar", attrs: { "data-top-left": "true" }, rect: { left: 780, top: 0, width: 320, height: 32 } });
  const contents = grid.add("div", { class: "contents" });
  contents.add("div", { class: "epitaxy-chat-panel-body", rect: { left: 200, top: 0, width: 580, height: 800 } });
  const dock = contents.add("div", { class: "contents" }).add("div", { class: "group/approval-dock flex flex-col", rect: { left: 780, top: 32, width: 320, height: 768 } });
  const prompt = dock.add("div", { class: "epitaxy-prompt", rect: { left: 792, top: 100, width: 296, height: 690 } });
  const block = prompt.add("div", { class: "flex w-full min-w-0 flex-col font-sans", rect: { left: 792, top: 100, width: 296, height: 690 } });
  const shell = block.add("div", { class: "bg-surface-3", rect: { left: 792, top: 100, width: 296, height: 660 }, computed: { borderBottomWidth: "1px" } });
  const root = shell.add("div", { class: "editor-root", rect: { left: 802, top: 110, width: 276, height: 640 }, computed: { overflowY: "auto" } });
  const editor = root.add("div", { class: "ProseMirror", attrs: { contenteditable: "true" }, rect: { left: 802, top: 110, width: 276, height: 640 } });
  const chin = block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: { left: 792, top: 770, width: 296, height: 20 } });
  const wrap = chin.add("div", { class: "min-h-0", rect: { left: 792, top: 770, width: 296, height: 20 } });
  const row = wrap.add("div", { class: "flex min-h-control items-center gap-0 ps-[var(--cmp-chin-start)] pe-[var(--cmp-chin-end)]", rect: { left: 792, top: 770, width: 296, height: 20 } });
  const lead = row.add("div", { class: "flex items-center self-start", rect: { left: 792, top: 770, width: 100, height: 20 } });
  lead.add("button", { attrs: { "aria-label": "Add" }, rect: { left: 792, top: 772, width: 16, height: 16 } });
  const mode = lead.add("button", { attrs: { "aria-haspopup": "menu" }, rect: { left: 812, top: 772, width: 80, height: 16 } });
  const modeText = dom.leaf(mode, "span", "Bypass permissions");
  const spacer = row.add("span", { class: "flex min-w-0 flex-1 basis-0 items-center justify-end gap-sm", rect: { left: 892, top: 770, width: 0, height: 20 } });
  spacer.add("span", { class: "text-body text-secondary" });
  const end = row.add("div", { class: "ms-auto flex min-w-0 items-center gap-1 ps-2", rect: { left: 892, top: 770, width: 190, height: 20 } });
  const model = end.add("button", { attrs: { "data-testid": "epitaxy-cds-model-selector", "aria-haspopup": "menu" } });
  const modelText = dom.leaf(model, "span", "Opus 5.5");
  const effort = end.add("button", { attrs: { "aria-label": "Effort: Extra", "aria-haspopup": "dialog" } });
  const effortText = dom.leaf(effort, "span", "Extra");
  const ring = end.add("button", { attrs: { "aria-haspopup": "dialog", "aria-label": "Usage: Context 180k / 1M (18%)" } });
  return { panel, dock, prompt, block, shell, root, editor, chin, wrap, row, lead, mode, modeText, spacer, end, model, modelText, effort, effortText, ring };
};

// Раскладка как у Chromium при колонке column: дока шире на 12 (выезд влево), строка — дока − 24 от 792-го
// сдвига; группы натуральной ширины (тесная строка — уже: поля и зазоры ужаты), распорка — всё свободное
// место, нет его — правая группа вылезает за край.
const lay = (parts, column, { lead = 100, end = 200, leadTight = 90, endTight = 180 } = {}) => {
  const tight = parts.chin.hasAttribute("data-myclaude-chin-narrow");
  const dock = column + 12;
  const left = 1100 - dock;
  const rowLeft = left + 12;
  const rowWidth = dock - 24;
  const leadWidth = tight ? leadTight : lead;
  const endWidth = tight ? endTight : end;
  const free = Math.max(0, rowWidth - leadWidth - endWidth);
  parts.dock.rect = { left, top: 32, width: dock, height: 768 };
  for (const node of [parts.prompt, parts.block, parts.chin, parts.wrap, parts.row]) node.rect = { ...node.rect, left: rowLeft, width: rowWidth };
  parts.lead.rect = { left: rowLeft, top: 770, width: leadWidth, height: 20 };
  parts.spacer.rect = { left: rowLeft + leadWidth, top: 770, width: free, height: 20 };
  const endLeft = rowLeft + leadWidth + free;
  parts.end.rect = { left: endLeft, top: 770, width: endWidth, height: 20 };
  parts.ring.rect = { left: endLeft + endWidth - 20, top: 770, width: 20, height: 20 };
  return { tight, over: Math.max(0, leadWidth + endWidth - rowWidth) };
};
// Ширина колонки по CSS сетки: clamp(пол, своя переменная, 60 %) — без своей переменной 300.
const columnOf = panel => {
  const floor = Number.parseFloat(panel.style.getPropertyValue("--myclaude-side-floor")) || 248;
  const side = Number.parseFloat(panel.style.getPropertyValue("--myclaude-side")) || 300;
  return Math.min(540, Math.max(floor, side));
};
const run = (loaded, passes, sizes) => {
  const seen = [];
  for (let pass = 0; pass < passes; pass += 1) {
    const column = columnOf(loaded.parts.panel);
    lay(loaded.parts, column, sizes);
    settle(loaded);
    seen.push({ column, floor: loaded.parts.panel.style.getPropertyValue("--myclaude-side-floor"), tight: loaded.parts.chin.hasAttribute("data-myclaude-chin-narrow") });
  }
  return seen;
};
const open = (stored = "300") => {
  const loaded = loadInject({ title: "Rick", html: stand, storage: { local: stored == null ? {} : { [SIDE_KEY]: stored } } });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.win.fetch = () => Promise.resolve({});
  return loaded;
};

test("WF195: подписи нижней строки коротко при ЛЮБОЙ ширине — правила без метки тесной строки; тесная — только поля и зазоры", () => {
  const loaded = open();
  const css = plain(loaded.inner.RULES).join("\n");
  assert.ok(css.includes('[data-cds="ChatComposerChin"] [data-myclaude-short]{font-size:0 !important;letter-spacing:0 !important}'), "полная подпись Claude не прячется в широкой строке");
  assert.ok(css.includes('[data-cds="ChatComposerChin"] [data-myclaude-short]::after{content:attr(data-myclaude-short);font-size:11px;line-height:16px}'));
  assert.ok(css.includes('[data-cds="ChatComposerChin"] [data-myclaude-short-tail]::before{content:attr(data-myclaude-short);font-size:10px !important;line-height:16px}'), "«Op» — не мелко");
  assert.ok(css.includes('[data-cds="ChatComposerChin"] [data-myclaude-short-tail]::after{content:attr(data-myclaude-short-tail);font-size:8px !important;line-height:12px;margin-left:0}'), "«5.5» — не мелко и не слитно");
  // WF226: у держателя с кеглем 0 распорки строки нет — иначе подпись стоит на 2 px выше цифр и значков рядом.
  assert.ok(css.includes('[data-cds="ChatComposerChin"] [data-myclaude-short]{line-height:0 !important}'), "распорка держателя поднимает подписи над строкой");
  assert.doesNotMatch(css, /\[data-myclaude-chin-narrow\] \[data-myclaude-short/, "короткие подписи снова зависят от тесноты строки — в широкой вернутся длинные");
  assert.match(css, /\[data-myclaude-chin-narrow\] \[data-myclaude-chin="text"\]\{padding-left:3px !important;padding-right:3px !important\}/, "тесная строка по-прежнему ужимает поля");
  // Широкая строка (не тесная) — короткие формы стоят на всех трёх подписях.
  run(loaded, 3, { end: 150, endTight: 140 });
  const { chin, modeText, modelText, effortText } = loaded.parts;
  assert.equal(chin.hasAttribute("data-myclaude-chin-narrow"), false);
  const short = node => node.getAttribute("data-myclaude-short");
  assert.deepEqual([short(modeText), short(modelText), modelText.getAttribute("data-myclaude-short-tail"), short(effortText)], ["Bp", "Op", "5.5", "Ex"]);
});

test("WF195: короткая подпись — с подсказкой полным именем; сменился режим — подсказка за ним; чужую не трогаем; dispose снимает свою", () => {
  const loaded = open();
  run(loaded, 2);
  const { mode, model, effort, modeText } = loaded.parts;
  assert.equal(mode.getAttribute("title"), "Bypass permissions", "«Bp» без подсказки — людям непонятно (04:10)");
  assert.equal(model.getAttribute("title"), "Opus 5.5");
  assert.equal(effort.getAttribute("title"), "Extra");
  loaded.dom.retext(modeText, "Auto mode");
  run(loaded, 1);
  assert.equal(loaded.parts.modeText.getAttribute("data-myclaude-short"), "Au");
  assert.equal(mode.getAttribute("title"), "Auto mode", "осталась подсказка «Bypass permissions» у другого режима");
  loaded.dom.retext(modeText, "Что-то своё");
  run(loaded, 1);
  assert.equal(mode.getAttribute("title"), null, "подписи коротко нет — и нашей подсказки нет");
  effort.setAttribute("title", "Claude: усилие");
  loaded.dom.retext(loaded.parts.effortText, "High");
  run(loaded, 1);
  assert.equal(effort.getAttribute("title"), "Claude: усилие", "чужая подсказка перезаписана");
  loaded.api.dispose();
  assert.equal(model.getAttribute("title"), null, "dispose не снял свою подсказку");
  assert.equal(effort.getAttribute("title"), "Claude: усилие");
});

test("WF195: пол колонки — по свободному месту распорки, без круга: колонка остаётся шириной человека (300), пол стоит", () => {
  const loaded = open("300");
  // Колонка 300: полные группы 100 + 200 в строку 288 не встают (вылет 12) — строка тесная; тесные 90 + 180,
  // свободно 18 (распорка) — пол 312 − 12 + 4 − 18 = 286, ниже выбранных 300.
  const seen = run(loaded, 12);
  const last = seen.at(-1);
  assert.equal(last.tight, true);
  assert.equal(last.floor, "286px", JSON.stringify(seen.map(item => [item.column, item.floor])));
  assert.ok(seen.every(item => item.column === 300), `колонку раздуло полом: ${seen.map(item => item.column).join(" → ")}`);
  assert.equal(new Set(seen.slice(1).map(item => item.floor)).size, 1, "пол меняется от прохода к проходу — круг");
  assert.equal(loaded.parts.panel.style.getPropertyValue("--myclaude-side"), "300px", "ширина человека подменена");
  assert.equal(loaded.win.localStorage.getItem(SIDE_KEY), "300", "сохранённая ширина переписана");
});

test("WF195: человек выбрал ýже пола — колонка стоит на полу (кружок не за краем); подписи сменились короче — пол ниже, колонка возвращается к выбранной", () => {
  const loaded = open("260");
  // Колонка 260: строка 248, тесные 90 + 180 = 270 — вылет 22 даже коротко; пол 272 − 12 + 4 + 22 = 286.
  const seen = run(loaded, 10);
  assert.equal(seen.at(-1).floor, "286px", JSON.stringify(seen));
  assert.equal(seen.at(-1).column, 286, "колонка не поднялась до пола — кружок за краем");
  const settled = seen.at(-1);
  lay(loaded.parts, settled.column);
  assert.equal(lay(loaded.parts, settled.column).over, 0, "на полу кружок всё ещё за краем");
  // Модель сменилась на короче (правая группа тесно 140): подпись другая — пол меряется заново, колонка — 260.
  loaded.dom.retext(loaded.parts.modelText, "Haiku 4.5");
  const after = run(loaded, 10, { end: 150, endTight: 140 });
  assert.equal(after.at(-1).column, 260, `колонка не вернулась к выбранной: ${after.map(item => `${item.column}/${item.floor}`).join(" ")}`);
  assert.equal(loaded.win.localStorage.getItem(SIDE_KEY), "260");
});

test("WF195: ширина по умолчанию (своей нет) — тесная строка, пол 286 не толкает колонку выше прежних 300", () => {
  const loaded = open(null);
  const seen = run(loaded, 10);
  assert.equal(seen.at(-1).tight, true);
  assert.ok(seen.every(item => item.column === 300), seen.map(item => `${item.column}/${item.floor}`).join(" "));
});
