// WF134 (#9077, раздел 12п² inject.js): ячейки Workflow всех проектов в поле Рика;
// WF140 (#9113): полоса по проектам — строка на проект «Имя:» + капсулы-номера;
// WF142 (#9128, #9125): минимализм — без цвета состояний: готово «N ✓», идёт — дышит, ждёт «N !»,
// упал «N ✕», впереди — бледно; готовые подряд — одна капсула «1–14 ✓», клик раскрывает,
// «−», клик по готовой или Esc — сворачивают; «+K» раскрывает строку; видны все проекты
// (без «+N проектов»), лишнее по высоте — прокрутка в блоке; фильтр «Все · Идут · Готово»
// (localStorage); только в чате, чья папка — Rick.
//
// Контракт К6 (план WF128, «Добавка 08.10 ~22:05»): GET http://127.0.0.1:47615/digest
// (cors) раз в 30 с и при возврате окна из скрытого, только в чате проекта Rick.
// Блок снизу вверх над нижней строкой кнопок и выше Enter; ошибка — прежние, 5 мин без
// ответа — гаснут; status().rickCells.
// WF149 (#9130–#9132): клик по капсуле — карточка Workflow, по имени — сводка проекта с «Открыть
// в PMP» (сама панель не открывается), Esc/клик мимо — закрыть; поле пустое — все проекты, что
// влезли в рамку, остальное «+N проектов»; текст — свёртка в строку-итог с «Показать все» (поднять
// поверх текста); строка-итог «Идёт N Workflow · этапы»; строки без подложек и линий.
// WF160 (#9158–#9160): фильтр и итог — ВНИЗУ полосы с левого края, на месте при любом числе строк и
// фильтре; итог без «…» (короче словами или строкой над фильтром); имена шириной по замеру; клик по
// капсуле — та же карточка, что у полоски 2б (капсула номера, этапы и кто на них, «когда»), без «WF» и
// «шаги»; готовая в раскрытой строке — карточка, свернуть — «Свернуть» внизу справа (одна на всё раскрытое) или Esc.
// WF160 после критика: готовые склеиваются только подряд по номеру; свёрнутая строка не прячет живые;
// итог словами целиком (без «пл», «кр»), с ждущими; зазор над нижней строкой 12; у готового без блока —
// все четыре этапа ✓ и «о чём» без «…»; сводка проекта — готовые за «Показать готовые ▾».
// WF172 (#9181): нижняя строка — «Показать»/«Свернуть» и «Все · В работе · Готовы» в строке Enter слева
// от него (места нет или Enter в нижней строке поля — внизу полосы); итога словами нет; шрифт полосы —
// подписей нижней строки поля; карточка Workflow — над своей капсулой; клик не всплывает до Claude.
// WF175 (#9191, #9194, #9195, #9163): кнопки и текст поля не пересекаются никогда — у Enter (лишние строки
// вверх, место отнято у прокрутки текста) или своей полосой под текстом; «В работе N» (умолчание) · «Готовы» ·
// «Все» · «Показать»/«Свернуть» · «Отчёт»; итога словами нет нигде; идущий — кружок мигает; этап «план».
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const LAYER = "#myclaude-rick-cells";
const CHAT = "local_bbbb-2222";
const DIGEST = "http://127.0.0.1:47615/digest";
const PANEL = "http://127.0.0.1:47615/panel";
// Рамка поля 100..1100 × 600..720 (стенд dom.composer), нижняя строка 690..718,
// Enter над ней справа 1060..1084 × 660..680.
const FRAME = { left: 100, right: 1100, top: 600, bottom: 720 };
const CHIN = { left: 100, top: 690, width: 1000, height: 28 };
const SEND = { left: 1060, top: 660, width: 24, height: 20 };

const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const tick = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };
const flows = (count, state = "готово", from = 1) => Array.from({ length: count }, (_, i) => ({ n: i + from, state, about: `работа ${i + from}`, steps: "1/3", phase: "кодинг" }));
const digest = (...projects) => ({ v: 1, at: "2026-10-08T22:00:00Z", projects });
const ok = data => () => Promise.resolve({ ok: true, json: () => Promise.resolve(data) });

// Прежние проверки раскладки писались при фильтре «Все» — он и задан; умолчание «В работе» (WF175) — своей проверкой.
const page = async ({ cwd = "/Users/dev/Projects/Rick", reply = ok(digest()), text = "", local = { "myclaude-rick-filter": "all" } } = {}) => {
  const loaded = loadInject({
    title: "Rick", href: `https://claude.ai/epitaxy/${CHAT}`, storage: { local },
    html: dom => {
      const parts = dom.composer({ top: 600, text });
      // Как у Claude (замер 09.10): прокрутка текста кончается над полосой Enter (поле снизу 28).
      parts.root.rect = { left: 110, top: 610, width: 980, height: 45 };
      parts.editor.rect = { left: 110, top: 610, width: 980, height: 45 };
      parts.chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: CHIN });
      const row = parts.chin.add("div", { class: "flex items-center", rect: { left: 100, top: 694, width: 1000, height: 20 } });
      parts.left = row.add("div", { class: "flex items-center self-start", rect: { left: 100, top: 696, width: 60, height: 16 } });
      parts.left.add("button", { attrs: { "aria-label": "Add" }, rect: { left: 100, top: 696, width: 20, height: 16 } });
      const right = row.add("div", { class: "ms-auto flex items-center", rect: { left: 1000, top: 694, width: 100, height: 20 } });
      right.add("button", { attrs: { "data-testid": "epitaxy-cds-model-selector" }, text: "Opus 5.5", rect: { left: 1000, top: 696, width: 60, height: 16 } });
      parts.send = parts.block.add("button", { attrs: { "data-testid": "code-prompt-send" }, rect: SEND });
      const side = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
      const item = side.add("div", { attrs: { "data-row-key": `code:${CHAT}` } });
      item.__reactFiber$test = { memoizedProps: { session: { ref: { id: CHAT }, source: { data: { cwd } } } }, return: null };
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.reply = reply;
  loaded.win.fetch = (url, options) => {
    loaded.calls.push([url, options?.mode]);
    return url === DIGEST ? loaded.reply() : Promise.resolve({ ok: true });
  };
  const base = loaded.win.performance.now();
  let shift = 0;
  loaded.win.performance.now = () => base + shift;
  loaded.later = ms => { shift += ms; };
  settle(loaded);
  await tick();
  return loaded;
};
const kids = (node, tag) => [...node.childNodes].filter(kid => kid.nodeType === 1 && kid.tagName.toLowerCase() === tag);
const layer = loaded => loaded.dom.query(LAYER);
const list = loaded => kids(layer(loaded), "p")[0];
const nav = loaded => kids(layer(loaded), "nav")[0];
const rows = loaded => kids(list(loaded), "s");
const caps = row => kids(row, "i");
const nameOf = row => kids(row, "b")[0]?.textContent;
// Всё, что видно: «Имя: 1 2 3» построчно сверху вниз.
const lines = loaded => rows(loaded).map(row => [nameOf(row), ...caps(row).map(cap => cap.textContent)].join(" "));
const px = (node, name) => Number(String(node.style.getPropertyValue(name)).replace("px", ""));
// Прямоугольник строки в координатах окна (без прокрутки).
const box = (loaded, row) => {
  const left = px(layer(loaded), "left");
  const top = px(layer(loaded), "top") + px(list(loaded), "top") + px(row, "top");
  return { left, top, right: left + px(row, "width"), bottom: top + px(row, "height") };
};
const rick = loaded => plain(loaded.api.status().rickCells);
const CARD = "#myclaude-rick-card";
const card = loaded => loaded.dom.query(CARD);
const FLOW = "#myclaude-rick-flow";
const flowTip = loaded => loaded.dom.query(FLOW);
const flowCard = loaded => kids(flowTip(loaded), "div")[0];
const flowOpen = loaded => flowTip(loaded)?.style.getPropertyValue("display") === "block";
// Шапка карточки Workflow (та же, что у полоски 2б): [капсула номера, проект, плашка].
const flowHead = loaded => kids(kids(flowCard(loaded), "div")[0], "div").map(node => node.textContent);
// Этапы: [этап, кто] по строкам; «когда» — последний узел.
// Строки этапов — только показанные (WF198: этапа, которого у Workflow нет, в карточке нет).
const flowRows = loaded => kids(kids(flowCard(loaded), "div")[2], "div").slice(0, 4).filter(row => row.style.getPropertyValue("display") !== "none");
const flowStages = loaded => flowRows(loaded).map(row => [row.children[2].textContent, row.children[3].textContent]);
const flowWhen = loaded => kids(flowCard(loaded), "div")[3].textContent;
// Знак в кружке этапа: «✓» пройден, «» — идёт или впереди.
const flowGlyphs = loaded => flowRows(loaded).map(row => row.children[1].children[1].children[0].textContent);
const cardOpen = loaded => card(loaded)?.style.getPropertyValue("display") === "block" || flowOpen(loaded);
const panels = loaded => loaded.calls.filter(([url]) => url === PANEL).length;
// Нижняя строка в координатах окна: верх, низ, левый и правый край.
const navBox = loaded => {
  const top = px(layer(loaded), "top") + px(nav(loaded), "top");
  const left = px(layer(loaded), "left") + px(nav(loaded), "left");
  return { top, bottom: top + px(nav(loaded), "height"), left, right: left + px(nav(loaded), "width") };
};
// Шеврон (WF183) — без текста: «˄»/«˅» по data-dir.
const words = loaded => kids(nav(loaded), "a").map(item => (item.dataset.chevron ? (item.dataset.dir === "up" ? "˄" : "˅") : item.textContent));
// Низ строк (без нижней строки кнопок) в координатах окна.
const listBottom = loaded => px(layer(loaded), "top") + px(list(loaded), "top") + px(list(loaded), "height");
const raiseButton = loaded => kids(nav(loaded), "a").find(item => item.dataset.raise);
// Кнопка вида (WF179; с WF183 — шеврон) — первая в строке: вид (data-view) или подъём (data-raise).
const viewButton = loaded => kids(nav(loaded), "a")[0];
// Высокая рамка поля 100..1100 × 300..720: места на ~18 строк.
const tall = loaded => { loaded.parts.shell.rect = { left: 100, top: 300, width: 1000, height: 420 }; settle(loaded); };
const digests = loaded => loaded.calls.filter(([url]) => url === DIGEST).length;
const click = (loaded, target) => layer(loaded).dispatchEvent({ type: "click", detail: 1, target });
const P = (name, color, workflows, extra = {}) => ({ name, title: name, color, workflows, ...extra });

test("#9128: окно Рика — GET /digest (cors), строка на проект; состояние знаком, без цвета; подсказка словами", async () => {
  const loaded = await page({ reply: ok(digest(
    { name: "PimpMyClaude", title: "Пимп", marker: "⚪", color: "#3366ff", group: "идут", workflows: [
      { n: 134, state: "идёт", about: "ячейки в поле Рика", steps: "2/5", phase: "кодинг" },
      { n: 133, state: "готово", about: "/digest", steps: "5/5", phase: "гейт" },
      { n: 135, state: "упал", about: "свёртки", steps: "1/4", phase: "тесты" },
      { n: 136, state: "впереди", about: "потом" }] },
    { name: "Vkusnoff", title: "Вкуснофф", marker: "🟠", color: "#ff8800", group: "ждут", workflows: [
      { n: 7, state: "ждёт", about: "меню", steps: "3/3", phase: "показ" }] },
    { name: "Empty", color: "#00ff00", workflows: [] },
  )) });
  tall(loaded);
  assert.deepEqual(loaded.calls[0], [DIGEST, "cors"]);
  assert.equal(layer(loaded).style.getPropertyValue("display"), "block");
  // Без эмодзи и «WF»: имя (с WF156 без двоеточия), номера по возрастанию, знак — состояние.
  assert.deepEqual(lines(loaded), ["Пимп 133 ✓ 134 135 ✕ 136", "Вкуснофф 7 !"]);
  const [pimp, food] = rows(loaded);
  assert.deepEqual(caps(pimp).map(cap => cap.dataset.state), ["done", "run", "fail", "plan"]);
  assert.equal(caps(food)[0].dataset.state, "wait");
  // С WF156 (#9145) и у имени цвета проекта нет — цвет текста поля приглушённо (CSS); у капсул своего цвета нет.
  assert.equal(pimp.style.getPropertyValue("--c"), "");
  assert.equal(food.style.getPropertyValue("--c"), "");
  for (const cap of [...caps(pimp), ...caps(food)]) {
    assert.equal(cap.style.getPropertyValue("background"), "", `у капсулы цвет: ${cap.textContent}`);
    assert.equal(cap.style.getPropertyValue("color"), "");
  }
  // Подсказка — проект, состояние словами, фаза идущего; номер — на самой капсуле, «WF» и «шаги» нет (#9159).
  assert.equal(caps(pimp)[1].title, "Пимп · идёт · кодинг");
  assert.equal(caps(pimp)[0].title, "Пимп · готово");
  assert.equal(caps(food)[0].title, "Вкуснофф · ждёт тебя · показ");
  assert.equal(caps(pimp)[3].title, "Пимп · впереди");
  for (const cap of [...caps(pimp), ...caps(food)]) assert.doesNotMatch(cap.title, /WF|шаги/, cap.title);
  for (const cap of caps(pimp)) assert.ok(px(cap, "width") <= 36, `капсула шире 36: ${cap.textContent}`);
  // Нижняя строка (#9181, WF175 #9195, WF183): «˅ · В работе · Сделано · Всё · Отчёт» без чисел
  // («Всё» выбрано — так задан стенд), итога словами нет — в одну линию с Enter, слева от него: правый
  // край за 8 до Enter, середина — по его середине. Числа — в подсказках: в работе — идущие, ждущие и
  // упавшие (134, 135, 7).
  assert.deepEqual([...nav(loaded).childNodes].map(item => item.tagName.toLowerCase()), ["a", "a", "a", "a", "a"]);
  assert.deepEqual(kids(nav(loaded), "a").map((item, k) => [words(loaded)[k], item.getAttribute("aria-pressed")]),
    [["˅", null], ["В работе", "false"], ["Сделано", "false"], ["Всё", "true"], ["Отчёт", null]]);
  assert.doesNotMatch(nav(loaded).textContent, /\d/, "числа в строке кнопок (WF183: «В работе 11 — плохая идея»)");
  assert.deepEqual(kids(nav(loaded), "a").slice(1, 4).map(item => item.title), ["Идут, ждут тебя и упавшие: 3", "Готовые: 1", "Все Workflow: 5"]);
  assert.equal(viewButton(loaded).dataset.view, "none");
  assert.doesNotMatch(nav(loaded).textContent, /Идёт|Идут|Workflow/);
  const line = navBox(loaded);
  assert.equal(line.right, SEND.left - 8);
  assert.equal((line.top + line.bottom) / 2, SEND.top + SEND.height / 2);
  assert.ok(line.left >= FRAME.left + 6, "кнопки вылезли за рамку слева");
  assert.equal(nav(loaded).dataset.spot, "send");
  // Блок строк — от левого края рамки, кончается выше Enter (нижняя строка его места не отнимает),
  // строки 16 через 2.
  const first = box(loaded, pimp);
  const second = box(loaded, food);
  assert.equal(first.left, FRAME.left + 6);
  assert.equal(second.bottom, SEND.top - 3);
  assert.equal(second.top - first.top, 18);
  // Блок — до низа нижней строки (она в нём, у Enter).
  assert.equal(px(layer(loaded), "top") + px(layer(loaded), "height"), line.bottom);
  assert.deepEqual(rick(loaded), { wanted: true, visible: true, cells: 5, hidden: 0, rows: 2, dim: false, strips: 0, hover: null, projects: 2, filter: "all", open: 0, fetches: 1, answers: 1, last: DIGEST,
    fold: false, raised: false, more: 0, nav: "send", navLines: 1, room: 0, view: "full", navFont: 11, reports: 0, report: null, card: null, flow: null, block: null });
});

test("#9128, #9159: готовые подряд — одна капсула «1–14 ✓»; клик раскрывает, готовая в раскрытой — карточка; «Свернуть» и Esc сворачивают", async () => {
  const loaded = await page({ reply: ok(digest(P("Dictator", "#aa3366", [...flows(14), { n: 15, state: "идёт" }, ...flows(2, "готово", 16)]))) });
  assert.deepEqual(lines(loaded), ["Dictator 1–14 ✓ 15 16–17 ✓"]);
  const group = caps(rows(loaded)[0])[0];
  assert.equal(group.dataset.act, "open");
  assert.equal(group.dataset.state, "done");
  assert.equal(group.title, "Dictator · готово, 14 Workflow\nНажми — показать по одному");
  // Клик по сводке — по одной; своей кнопки в строке нет — «Свернуть» внизу справа (видом кнопок
  // фильтра, одна на всё раскрытое); панель PMP не открылась.
  click(loaded, group);
  assert.deepEqual(lines(loaded), [`Dictator ${Array.from({ length: 14 }, (_, i) => `${i + 1} ✓`).join(" ")} 15 16 ✓ 17 ✓`]);
  assert.deepEqual([raiseButton(loaded).dataset.raise, raiseButton(loaded).dataset.dir], ["off", "down"]);
  assert.equal(rick(loaded).raised, false, "строка влезла — полоса не поднята");
  assert.equal(rick(loaded).open, 1);
  assert.equal(loaded.calls.filter(([url]) => url === PANEL).length, 0, "раскрытие открыло панель");
  // Новая сводка раскрытое не сворачивает.
  loaded.later(30000);
  loaded.dom.fireKind("interval");
  await tick();
  assert.equal(caps(rows(loaded)[0]).length, 17);
  // Клик по «1 ✓» в раскрытой строке — карточка этого Workflow (слово 08.10 ~23:38: «нажимаю первый — он
  // должен стандартное подменю Workflow показывать»), строка остаётся раскрытой, капсула обведена.
  click(loaded, caps(rows(loaded)[0])[0]);
  assert.equal(rick(loaded).card, "flow");
  assert.equal(rick(loaded).open, 1);
  assert.deepEqual(flowHead(loaded), ["1 ✓", "Dictator", "готов"]);
  assert.equal(caps(rows(loaded)[0])[0].dataset.picked, "true");
  // Esc — сперва карточка (обводка уходит), потом строка; Claude Esc не достаётся.
  const esc = () => loaded.dom.document.dispatchEvent({ type: "keydown", key: "Escape" });
  assert.equal(esc(), false, "Esc ушёл в Claude");
  assert.equal(flowOpen(loaded), false);
  assert.equal(caps(rows(loaded)[0])[0].dataset.picked, undefined);
  assert.equal(rick(loaded).open, 1, "первый Esc свернул и строку");
  assert.equal(esc(), false);
  assert.deepEqual(lines(loaded), ["Dictator 1–14 ✓ 15 16–17 ✓"]);
  // «Свернуть» внизу — свернуть раскрытое; вид прежний (full), кнопка снова — «Свернуть» вида (WF179).
  click(loaded, caps(rows(loaded)[0])[0]);
  click(loaded, raiseButton(loaded));
  assert.deepEqual(lines(loaded), ["Dictator 1–14 ✓ 15 16–17 ✓"]);
  assert.equal(raiseButton(loaded), undefined);
  assert.equal(rick(loaded).view, "full");
  assert.deepEqual([words(loaded)[0], viewButton(loaded).dataset.view], ["˅", "none"]);
  // Свернуто — Esc не наш.
  assert.equal(esc(), true);
  // Давно не трогали — свернуть, но Esc отдать Claude.
  click(loaded, caps(rows(loaded)[0])[0]);
  loaded.later(11000);
  assert.equal(esc(), true);
  assert.equal(rick(loaded).open, 0);
});

test("#9113: сортировка — где идёт наверху, дальше кто обновился позже (at или замеченная смена), новые наверх", async () => {
  const loaded = await page({ reply: ok(digest(
    P("Тихий", "#111111", flows(2)),
    P("Старый", "#222222", flows(1), { at: "2026-10-08T10:00:00Z" }),
    P("Свежий", "#333333", flows(1), { at: "2026-10-08T21:00:00Z" }),
    P("Бегун", "#444444", [{ n: 2, state: "идёт" }, { n: 1, state: "готово" }]),
  )) });
  tall(loaded);
  assert.deepEqual(rows(loaded).map(nameOf), ["Бегун", "Свежий", "Старый", "Тихий"]);
  assert.deepEqual(caps(rows(loaded)[0]).map(cap => cap.textContent), ["1 ✓", "2"], "внутри проекта не по номеру");
  loaded.reply = ok(digest(
    P("Тихий", "#111111", [{ n: 1, state: "готово" }, { n: 2, state: "ждёт" }]),
    P("Старый", "#222222", flows(1), { at: "2026-10-08T10:00:00Z" }),
    P("Свежий", "#333333", flows(1), { at: "2026-10-08T21:00:00Z" }),
    P("Бегун", "#444444", [{ n: 2, state: "идёт" }, { n: 1, state: "готово" }]),
  ));
  loaded.later(30000);
  loaded.dom.fireKind("interval");
  await tick();
  assert.deepEqual(rows(loaded).map(nameOf), ["Бегун", "Тихий", "Свежий", "Старый"]);
  loaded.reply = ok(digest(
    P("Тихий", "#111111", [{ n: 1, state: "готово" }, { n: 2, state: "ждёт" }]),
    P("Старый", "#222222", flows(1), { at: "2026-10-08T10:00:00Z" }),
    P("Новичок", "#555555", flows(1)),
    P("Бегун", "#444444", [{ n: 2, state: "идёт" }, { n: 1, state: "готово" }]),
  ));
  loaded.later(30000);
  loaded.dom.fireKind("interval");
  await tick();
  assert.deepEqual(rows(loaded).map(nameOf), ["Бегун", "Новичок", "Тихий", "Старый"]);
});

test("#9131: поле пустое — все проекты без потолка 6 строк, сколько влезло в рамку; остальное «+N проектов» — клик поднимает полосу", async () => {
  const loaded = await page({ reply: ok(digest(...Array.from({ length: 9 }, (_, i) => P(`Проект${i + 1}`, "#123456", flows(3, "идёт"))))) });
  // Низкая рамка (596..657 над Enter; кнопки — у Enter, места не отнимают, #9181) — место на 3 строки:
  // две строки проектов и «+7 проектов».
  loaded.parts.shell.rect = { left: 100, top: 590, width: 1000, height: 130 };
  settle(loaded);
  assert.deepEqual(rows(loaded).map(nameOf), ["Проект1", "Проект2", "+7 проектов"]);
  assert.equal(rows(loaded)[2].dataset.state, "more");
  assert.deepEqual(rick(loaded).rows, 2);
  assert.equal(rick(loaded).more, 7);
  // Шеврон вида — «˅» (скрыть, WF183); все проекты — кликом по «+7 проектов».
  assert.equal(raiseButton(loaded), undefined);
  assert.equal(words(loaded)[0], "˅");
  assert.equal(listBottom(loaded), SEND.top - 3, "наехала на Enter");
  // Клик по «+7 проектов» — полоса поднята: все 9, выше рамки, на подложке; кнопка «Свернуть».
  click(loaded, rows(loaded)[2]);
  assert.equal(rick(loaded).raised, true);
  assert.equal(layer(loaded).dataset.raised, "true");
  assert.equal(rows(loaded).length, 9);
  assert.equal(px(list(loaded), "height"), 9 * 18 - 2);
  assert.ok(px(layer(loaded), "top") >= 8 && px(layer(loaded), "top") < FRAME.top, "не поднялась выше рамки");
  assert.equal(raiseButton(loaded).dataset.dir, "down");
  assert.equal(panels(loaded), 0, "«+N проектов» открыл панель");
  click(loaded, raiseButton(loaded));
  assert.equal(rick(loaded).raised, false);
  assert.equal(layer(loaded).dataset.raised, "false");
  assert.equal(rows(loaded).length, 3);
  // Высокая рамка — все 9 на виду, без «+N» и без прежнего потолка в 6 строк (106 px).
  tall(loaded);
  assert.equal(rows(loaded).length, 9);
  assert.ok(!lines(loaded).some(line => /проект/.test(line)), "лишняя «+N проектов»");
  assert.equal(px(list(loaded), "height"), 9 * 18 - 2);
  assert.equal(rick(loaded).more, 0);
  const layerBox = { left: px(layer(loaded), "left"), top: px(layer(loaded), "top") };
  assert.ok(layerBox.left >= FRAME.left + 6);
  assert.ok(layerBox.left + px(layer(loaded), "width") <= FRAME.right - 6 + 1, "вылезла вбок");
  assert.ok(listBottom(loaded) <= SEND.top, "наехала на Enter");
});

test("#9131, #9181: начал печатать — строки уходят вниз, у Enter встаёт «Показать»; клик — вжух вверх поверх текста; стёр — снова раскрыта", async () => {
  const loaded = await page({ reply: ok(digest(P("A", "#111111", flows(3, "идёт")), P("B", "#222222", flows(2)))) });
  tall(loaded);
  assert.equal(rick(loaded).fold, false);
  assert.equal(raiseButton(loaded), undefined, "подъём при пустом поле");
  assert.equal(words(loaded)[0], "˅", "шеврон — всегда первым (WF179, WF183)");
  const top0 = px(layer(loaded), "top");
  const line0 = navBox(loaded);
  assert.equal(line0.right, SEND.left - 8);
  // Текст — свёртка: строки прозрачны и без кликов (CSS по data-fold), нижняя строка не двигается (#9158).
  loaded.parts.editor.add("p", { text: "привет", rect: { left: 110, top: 306, width: 200, height: 14 } });
  settle(loaded);
  assert.equal(rick(loaded).fold, true);
  assert.equal(layer(loaded).dataset.fold, "true");
  assert.equal(rick(loaded).rows, 0);
  assert.deepEqual([navBox(loaded).top, navBox(loaded).right], [line0.top, line0.right], "нижняя строка сдвинулась");
  assert.equal(nav(loaded).style.getPropertyValue("transform"), "");
  // WF183: шеврон «˄» (показать поверх текста) — первым, за ним фильтр без чисел и «Отчёт» — одна линия у Enter.
  assert.deepEqual([raiseButton(loaded).dataset.raise, raiseButton(loaded).dataset.dir], ["on", "up"]);
  assert.deepEqual(words(loaded), ["˄", "В работе", "Сделано", "Всё", "Отчёт"]);
  assert.equal(navBox(loaded).right, line0.right);
  const css0 = [...loaded.inner.RULES].join("\n");
  assert.doesNotMatch(css0.split("\n").filter(rule => rule.startsWith("#myclaude-rick-cells>nav>a")).join("\n"), /box-shadow/, "у кнопки строки своя рамка");
  assert.match(list(loaded).style.getPropertyValue("transition"), /transform 200ms/, "свёртка не плавная");
  const css = [...loaded.inner.RULES].join("\n");
  assert.match(css, /#myclaude-rick-cells\[data-fold="true"\]>p\{opacity:0;transform:translateY\(14px\);pointer-events:none\}/);
  assert.ok(css.split("\n").some(rule => rule.startsWith("@media (prefers-reduced-motion:reduce)") &&
    rule.includes("#myclaude-rick-cells,#myclaude-rick-cells>nav,#myclaude-rick-cells>p{transition:none!important}")), "при «Уменьшить движение» переход остался");
  // «Показать» — поднята поверх текста, на подложке; набор продолжается — остаётся поднятой.
  click(loaded, raiseButton(loaded));
  assert.equal(rick(loaded).raised, true);
  assert.equal(rick(loaded).fold, false);
  assert.equal(layer(loaded).dataset.raised, "true");
  assert.equal(rick(loaded).rows, 2);
  assert.deepEqual([raiseButton(loaded).dataset.raise, raiseButton(loaded).dataset.dir], ["off", "down"]);
  assert.equal(navBox(loaded).right, line0.right, "поднятая — нижняя строка сдвинулась");
  assert.equal(navBox(loaded).top, line0.top, "поднятая — нижняя строка сдвинулась");
  // Подложка поднятой полосы — сплошная, цветом поля: текст под ней не просвечивает (WF175, #9191).
  assert.match(css, /#myclaude-rick-cells\[data-raised="true"\]\{pointer-events:auto;border-radius:8px;background:var\(--f,transparent\);/);
  settle(loaded);
  assert.equal(rick(loaded).raised, true);
  // Esc — назад в строку-итог.
  assert.equal(loaded.dom.document.dispatchEvent({ type: "keydown", key: "Escape" }), false, "Esc ушёл в Claude");
  assert.equal(rick(loaded).raised, false);
  assert.equal(rick(loaded).fold, true);
  // Стёр текст — снова раскрыта, на прежнем месте.
  loaded.parts.editor.textContent = "";
  settle(loaded);
  assert.equal(rick(loaded).fold, false);
  assert.equal(rick(loaded).rows, 2);
  assert.equal(px(layer(loaded), "top"), top0);
  assert.deepEqual(navBox(loaded), line0);
  // «Уменьшить движение» — без перехода.
  loaded.win.__reducedMotion = true;
  loaded.parts.editor.add("p", { text: "ещё", rect: { left: 110, top: 306, width: 200, height: 14 } });
  settle(loaded);
  assert.equal(rick(loaded).fold, true);
  assert.equal(list(loaded).style.getPropertyValue("transition"), "none");
});

test("#9132, #9181, WF175: итога словами нет нигде — ни на полосе, ни в status(); этап «план» вместо «планирование»", async () => {
  const run = (n, phase) => ({ n, state: "идёт", phase });
  const loaded = await page({ reply: ok(digest(
    P("A", "#111111", [run(1, "план"), run(2, "планирование"), run(3, "критик")]),
    P("B", "#222222", [run(1, "код"), { n: 8, state: "ждёт", phase: "кодинг" }]),
  )) });
  assert.equal("summary" in rick(loaded), false, "итог словами остался в status()");
  assert.equal(kids(nav(loaded), "span").length, 0, "итог словами на полосе (#9181: «Идут 16 — убери»)");
  assert.doesNotMatch(layer(loaded).textContent, /Идёт \d+|Workflow|ждёт тебя|упал|кодинг \d/);
  assert.equal(caps(rows(loaded)[0])[1].title, "A · идёт · план", "этап в подсказке — «план»");
});

test("#9132: строки без подложек и линий — ни фона у строки и имени, ни подсветки строки при наведении", async () => {
  const loaded = await page({ reply: ok(digest(P("A", "#111111", flows(3, "идёт")))) });
  const css = [...loaded.inner.RULES].join("\n");
  const rules = css.split("\n").filter(rule => rule.includes("#myclaude-rick-cells>p>s"));
  assert.ok(rules.length > 0);
  for (const rule of rules.filter(rule => /^#myclaude-rick-cells>p>s(>b)?(:hover)?\{/.test(rule) || /^#myclaude-rick-cells>p>s:hover>b\{/.test(rule))) {
    assert.ok(!/background:(?!none)/.test(rule), `подложка у строки: ${rule}`);
    assert.ok(!/border(-\w+)?:(?!0)/.test(rule) && !/box-shadow:(?!none)/.test(rule) && !/gradient|mask/.test(rule), `линия у строки: ${rule}`);
  }
  assert.ok(!/#myclaude-rick-cells>p>s:hover\{/.test(css), "строка подсвечивается при наведении");
  const row = rows(loaded)[0];
  for (const node of [row, kids(row, "b")[0], list(loaded), layer(loaded)]) {
    assert.equal(node.style.getPropertyValue("background"), "");
    assert.equal(node.style.getPropertyValue("border"), "");
  }
});

test("#9128: много Workflow — капсулы до края, «+K» (только впереди и готовые) нажимается и раскрывает строку с переносом", async () => {
  const loaded = await page({ reply: ok(digest(P("A", "#112233", flows(200, "впереди")))) });
  const row = rows(loaded)[0];
  const list0 = caps(row);
  const last = list0.at(-1);
  const hidden = 200 - list0.length + 1;
  assert.ok(list0.length > 20, "капсул мало — строка не до края");
  assert.equal(last.textContent, `+${hidden}`);
  assert.equal(last.dataset.state, "more");
  assert.equal(last.dataset.act, "open");
  assert.deepEqual(list0.slice(0, 3).map(cap => cap.textContent), ["1", "2", "3"]);
  assert.equal(rick(loaded).hidden, hidden);
  assert.equal(rick(loaded).cells, list0.length - 1);
  const end = Math.max(...list0.map(cap => px(cap, "left") + px(cap, "width")));
  assert.ok(end <= px(row, "width") - 3 + 1, `капсулы вылезли: ${end} > ${px(row, "width")}`);
  // Клик по «+K» — строка раскрыта: все 200, несколько линий, строка выше; в рамку не
  // влезла — полоса поднялась (не спряталась в «+1 проект»); внизу «Свернуть».
  click(loaded, last);
  assert.equal(rick(loaded).raised, true);
  const open = rows(loaded)[0];
  assert.equal(caps(open).length, 200);
  assert.equal(raiseButton(loaded).dataset.dir, "down");
  assert.ok(px(open, "height") > 16, "строка не выросла");
  const lefts = new Set(caps(open).map(cap => px(cap, "top")));
  assert.ok(lefts.size > 1, "перенос не случился");
  for (const cap of caps(open)) assert.ok(px(cap, "left") + px(cap, "width") <= px(open, "width") - 3 + 1, "раскрытая вылезла вбок");
  assert.equal(rick(loaded).hidden, 0);
  // Одна «Свернуть» — и строку, и подъём.
  click(loaded, raiseButton(loaded));
  assert.equal(rick(loaded).raised, false);
  assert.equal(rick(loaded).open, 0);
  assert.equal(caps(rows(loaded)[0]).at(-1).textContent, `+${hidden}`);
});

test("WF183 (было WF160 критик): свёрнутая строка — ВСЕГДА одной линией («Не надо в две строки»); что не влезло, и живые тоже, — «+K», клик раскрывает", async () => {
  const live = [...flows(60, "идёт"), { n: 61, state: "ждёт" }, { n: 62, state: "упал" }];
  const loaded = await page({ reply: ok(digest(P("A", "#112233", [...flows(5), ...live.map(flow => ({ ...flow, n: flow.n + 5 })), ...flows(60, "впереди", 68)]))) });
  tall(loaded);
  const row = rows(loaded)[0];
  const shown = caps(row).map(cap => cap.textContent);
  assert.equal(shown[0], "1–5 ✓");
  assert.equal(new Set(caps(row).map(cap => px(cap, "top"))).size, 1, "капсулы перенеслись второй линией");
  assert.equal(px(row, "height"), 16, "строка выше одной линии");
  const tail = caps(row).at(-1);
  assert.equal(tail.dataset.state, "more");
  assert.equal(tail.textContent, `+${123 - (caps(row).length - 1)}`, "«+K» — сколько капсул не влезло (1–5 ✓, 62 живых, 60 впереди)");
  for (const cap of caps(row)) assert.ok(px(cap, "left") + px(cap, "width") <= px(row, "width") - 3 + 1, "вылезла вбок");
  // Клик по «+K» — строка раскрыта (там перенос можно: раскрыл сам).
  click(loaded, tail);
  assert.equal(caps(rows(loaded)[0]).length, 127);
  assert.ok(new Set(caps(rows(loaded)[0]).map(cap => px(cap, "top"))).size > 1);
});

test("WF160 критик: готовые склеиваются только подряд по номеру — «Готово» не накрывает идущие и будущие", async () => {
  const at = (n, state) => ({ n, state });
  const rick17 = [...flows(13), at(14, "идёт"), at(15, "впереди"), at(16, "готово"), at(17, "готово"), at(18, "идёт"), at(19, "впереди")];
  const loaded = await page({ local: { "myclaude-rick-filter": "done" }, reply: ok(digest(
    P("Rick", "#111111", rick17),
    P("Gap", "#222222", [at(1, "готово"), at(2, "готово"), at(5, "готово"), at(6, "готово"), at(9, "готово")]),
  )) });
  tall(loaded);
  assert.deepEqual(lines(loaded), ["Rick 1–13 ✓ 16–17 ✓", "Gap 1–2 ✓ 5–6 ✓ 9 ✓"]);
  const span = caps(rows(loaded)[0])[1];
  assert.equal(span.title, "Rick · готово, 2 Workflow\nНажми — показать по одному");
  // «Все» — то же правило: пропуск номера рвёт склейку.
  click(loaded, kids(nav(loaded), "a").find(item => item.dataset.filter === "all"));
  assert.deepEqual(lines(loaded), ["Rick 1–13 ✓ 14 15 16–17 ✓ 18 19", "Gap 1–2 ✓ 5–6 ✓ 9 ✓"]);
});

test("#9128, #9181, WF175: фильтр «В работе N · Готовы · Все» — сразу, помнится; пусто — строка-пояснение", async () => {
  const loaded = await page({ reply: ok(digest(
    P("A", "#111111", [...flows(3), { n: 4, state: "идёт" }, { n: 5, state: "ждёт" }, { n: 6, state: "упал" }, { n: 7, state: "впереди" }]),
    P("B", "#222222", flows(2)),
  )) });
  tall(loaded);
  assert.deepEqual(lines(loaded), ["A 1–3 ✓ 4 5 ! 6 ✕ 7", "B 1–2 ✓"]);
  const pick = word => click(loaded, kids(nav(loaded), "a").find(item => item.textContent.startsWith(word)));
  // «Все» — все капсулы, строки не раскрываются и полоса не поднимается (#9195: «не надо… разворачивать»).
  assert.equal(rick(loaded).raised, false);
  assert.equal(rick(loaded).open, 0);
  pick("В работе");
  assert.deepEqual(lines(loaded), ["A 4 5 ! 6 ✕"]);
  assert.equal(kids(nav(loaded), "a")[1].textContent, "В работе", "без числа (WF183)");
  assert.equal(kids(nav(loaded), "a")[1].getAttribute("aria-pressed"), "true");
  assert.deepEqual(kids(nav(loaded), "a").slice(1, 4).map(item => item.title), ["Идут, ждут тебя и упавшие: 3", "Готовые: 5", "Все Workflow: 9"],
    "числа — сколько капсул у каждого фильтра — в подсказках");
  assert.equal(loaded.win.localStorage.getItem("myclaude-rick-filter"), "run");
  assert.equal(rick(loaded).filter, "run");
  pick("Сделано");
  assert.deepEqual(lines(loaded), ["A 1–3 ✓", "B 1–2 ✓"]);
  assert.equal(loaded.calls.filter(([url]) => url === PANEL).length, 0, "фильтр открыл панель");
  pick("Всё");
  assert.deepEqual(lines(loaded), ["A 1–3 ✓ 4 5 ! 6 ✕ 7", "B 1–2 ✓"]);
  // Выбор помнится: новая страница — тот же фильтр; ничего не подошло — пояснение, переключатель на месте.
  const next = await page({ local: { "myclaude-rick-filter": "done" }, reply: ok(digest(P("C", "#333333", [{ n: 1, state: "идёт" }]))) });
  assert.deepEqual(lines(next), ["Готовых нет"]);
  assert.equal(rows(next)[0].dataset.state, "empty");
  assert.equal(kids(nav(next), "a")[2].getAttribute("aria-pressed"), "true");
  assert.equal(rick(next).rows, 0);
  click(next, rows(next)[0]);
  assert.equal(next.calls.filter(([url]) => url === PANEL).length, 0, "клик по пояснению открыл панель");
  // Мусор в хранилище и пустое хранилище — «В работе» (умолчание WF175, #9195), «Все» не разворачивает.
  for (const local of [{ "myclaude-rick-filter": "xxx" }, {}]) {
    const fresh = await page({ local, reply: ok(digest(P("C", "#333333", [...flows(2), { n: 3, state: "идёт" }]))) });
    assert.equal(rick(fresh).filter, "run");
    assert.deepEqual(words(fresh), ["˅", "В работе", "Сделано", "Всё", "Отчёт"]);
    assert.equal(kids(nav(fresh), "a")[1].getAttribute("aria-pressed"), "true");
    assert.deepEqual(lines(fresh), ["C 3"]);
  }
});

test("#9125: не чат Rick (папка чата, не заголовок окна) — полосы нет; запрос один, редкий — ради числа у кнопки PMP (WF213)", async () => {
  for (const cwd of ["/Users/dev/Projects/PimpMyClaude", "/Users/dev/Projects/Rick/voice"]) {
    const loaded = await page({ cwd, reply: ok(digest({ name: "A", color: "#112233", workflows: flows(3) })) });
    assert.equal(digests(loaded), 1, cwd);
    loaded.later(30000);
    loaded.dom.fireKind("interval");
    await tick();
    assert.equal(digests(loaded), 1, "чаще раза в минуту без блока Рика сводку не спрашиваем");
    assert.notEqual(layer(loaded).style.getPropertyValue("display"), "block", cwd);
    assert.equal(rick(loaded).wanted, false);
  }
});

test("#9077: раз в 30 с — новый запрос; ошибка и тишина — ячейки прежние; 5 мин без ответа — гаснут", async () => {
  const loaded = await page({ reply: ok(digest({ name: "A", color: "#112233", workflows: flows(2, "идёт") })) });
  assert.equal(caps(rows(loaded)[0]).length, 2);
  loaded.reply = () => Promise.reject(new Error("net"));
  loaded.later(10000);
  loaded.dom.fireKind("interval");
  await tick();
  assert.equal(digests(loaded), 1, "запрос раньше 30 с");
  loaded.later(20000);
  loaded.dom.fireKind("interval");
  await tick();
  assert.equal(digests(loaded), 2);
  assert.equal(caps(rows(loaded)[0]).length, 2, "ошибка погасила ячейки");
  loaded.reply = () => Promise.resolve({ ok: false });
  loaded.later(30000);
  loaded.dom.fireKind("interval");
  await tick();
  assert.equal(layer(loaded).style.getPropertyValue("display"), "block", "отказ погасил ячейки");
  loaded.reply = () => new Promise(() => {});
  for (let i = 0; i < 8; i += 1) { loaded.later(30000); loaded.dom.fireKind("interval"); await tick(); }
  assert.equal(layer(loaded).style.getPropertyValue("display"), "none", "5 мин без ответа — не погасли");
  assert.equal(rick(loaded).projects, 0);
  loaded.reply = ok(digest({ name: "A", color: "#112233", workflows: flows(1, "идёт") }));
  loaded.later(30000);
  loaded.dom.fireKind("interval");
  await tick();
  assert.equal(caps(rows(loaded)[0]).length, 1, "ответ вернулся — ячейки нет");
});

test("#9077: окно скрыто — не спрашиваем; вернулось — спрашиваем сразу", async () => {
  const loaded = await page({ reply: ok(digest({ name: "A", color: "#112233", workflows: flows(1) })) });
  loaded.dom.document.hidden = true;
  loaded.later(30000);
  loaded.dom.fireKind("interval");
  await tick();
  assert.equal(digests(loaded), 1, "скрытое окно спросило");
  loaded.later(1000);
  loaded.dom.document.hidden = false;
  loaded.dom.document.dispatchEvent({ type: "visibilitychange" });
  await tick();
  assert.equal(digests(loaded), 2, "вернулось — не спросило");
});

test("#9191 (WF175): набранный текст и кнопки не пересекаются никогда — у Enter строка в полосе Enter под текстом; без Enter — своя полоса, место отнято у прокрутки текста", async () => {
  const loaded = await page({ text: "привет", reply: ok(digest({ name: "A", color: "#112233", workflows: flows(2, "идёт") })) });
  const root = loaded.parts.root;
  assert.equal(rick(loaded).nav, "send");
  assert.equal(rick(loaded).dim, false);
  assert.equal(rick(loaded).room, 0, "в полосе Enter места хватает — у текста ничего не отнято");
  assert.ok(navBox(loaded).top >= root.rect.top + root.rect.height, "кнопки залезли на текст");
  // Enter нет — нижняя строка своей полосой под текстом: прокрутка текста получает отступ снизу (CSS),
  // и браузер поднимает её низ на него; кнопки — между текстом и строкой модели.
  loaded.parts.send.rect = { left: 0, top: 0, width: 0, height: 0 };
  settle(loaded);
  assert.equal(rick(loaded).nav, "below");
  const room = rick(loaded).room;
  assert.equal(room, 16 + 4);
  assert.equal(root.getAttribute("data-myclaude-rick-room"), "true");
  assert.equal(root.style.getPropertyValue("--myclaude-rick-room"), `${room}px`);
  assert.match([...loaded.inner.RULES].join("\n"), /\[data-myclaude-rick-room\]\{margin-bottom:var\(--myclaude-rick-room,0px\) !important\}/);
  root.rect = { ...root.rect, height: root.rect.height - room };
  loaded.parts.editor.rect = { ...root.rect };
  settle(loaded);
  assert.equal(rick(loaded).room, room, "отступ дрожит");
  const textBottom = root.rect.top + root.rect.height;
  assert.ok(navBox(loaded).top >= textBottom + 2, `кнопки залезли на текст: ${navBox(loaded).top} < ${textBottom}`);
  assert.ok(navBox(loaded).bottom <= CHIN.top, "кнопки залезли на строку модели");
  assert.equal(rick(loaded).dim, false, "кнопки притухают — значит, их накрывает текст");
  // Полоса ушла (не чат Рика / нет сводки) — отступ снят.
  loaded.reply = ok(digest());
  loaded.later(30000);
  loaded.dom.fireKind("interval");
  await tick();
  settle(loaded);
  assert.equal(root.getAttribute("data-myclaude-rick-room"), null, "отступ остался без полосы");
});

test("#9130, #9159, #9181: клик по капсуле — карточка Workflow над капсулой, клик не всплывает до Claude; по имени — сводка проекта; панель PMP — только кнопкой; Esc и клик мимо закрывают", async () => {
  const loaded = await page({ reply: ok(digest(
    { name: "PimpMyClaude", title: "Пимп", marker: "⚪", color: "#3366ff", group: "идут", workflows: [
      { n: 1, state: "готово", about: "первый", steps: "3/3", phase: "" },
      { n: 2, state: "идёт", about: "карточка над капсулой", steps: "2/4", phase: "кодинг" },
      { n: 3, state: "впереди", about: "потом" }] },
  )) });
  const row = rows(loaded)[0];
  const cell = caps(row).find(cap => cap.textContent === "2");
  assert.equal(layer(loaded).dispatchEvent({ type: "mousedown", target: cell }), false, "mousedown не погашен");
  // Нажатие по полосе до слушателей Claude на document не доходит (#9181: открывалось «что-то не то»).
  const stopped = [];
  for (const type of ["pointerdown", "mousedown"]) {
    const event = { type, target: cell, stopPropagation: () => stopped.push(type) };
    layer(loaded).dispatchEvent(event);
  }
  layer(loaded).dispatchEvent({ type: "click", detail: 1, target: cell, stopPropagation: () => stopped.push("click") });
  assert.deepEqual(stopped, ["pointerdown", "mousedown", "click"], "нажатие всплывает до Claude");
  assert.equal(rick(loaded).card, "flow");
  click(loaded, cell);
  assert.equal(rick(loaded).card, null, "повторный клик не закрыл");
  click(loaded, cell);
  assert.equal(panels(loaded), 0, "клик по капсуле открыл панель PMP");
  assert.equal(flowOpen(loaded), true);
  assert.equal(rick(loaded).card, "flow");
  // Блока status.md нет (команды status не было) — карточка из /digest: капсула номера, проект, плашка,
  // «о чём», этапы по фазе; кто и когда неизвестны — пусто, «WF» и «шаги» не пишутся.
  assert.equal(rick(loaded).block, false);
  assert.deepEqual(flowHead(loaded), ["2", "Пимп", "идёт кодинг"]);
  assert.equal(kids(flowCard(loaded), "div")[1].textContent, "карточка над капсулой");
  assert.deepEqual(flowStages(loaded), [["план", ""], ["критик", ""], ["кодинг", ""], ["тест", ""]]);
  assert.equal(flowWhen(loaded), "");
  assert.doesNotMatch(flowCard(loaded).textContent, /WF|Воркфлоу|Шаги|шаги/);
  assert.equal(caps(rows(loaded)[0]).find(cap => cap.textContent === "2").dataset.picked, "true");
  // Над строкой своей капсулы (низ карточки — в 6 над верхом строки: WF201, №13 — имя проекта видно), по
  // левому краю поля и не шире его (≤ 400).
  const tip = flowTip(loaded);
  const rowTop = box(loaded, rows(loaded)[0]).top;
  assert.ok(rowTop < FRAME.top + 120 && rowTop > FRAME.top, "строка не в рамке");
  assert.equal(px(tip, "bottom"), 800 - rowTop + 6);
  assert.equal(px(tip, "left"), FRAME.left);
  assert.equal(px(tip, "width"), 400);
  // Идущий без блока: этапы до фазы из /digest пройдены (✓), фаза идёт, дальше впереди.
  assert.deepEqual(flowGlyphs(loaded), ["✓", "✓", "", ""]);
  // Готовый без блока, «3/3» — три этапа пройдены ✓, не четыре (WF198, #9159: «шаги три из трёх… я четыре
  // шага вижу»), кто — пусто; повторный клик — закрыть.
  click(loaded, caps(rows(loaded)[0]).find(cap => cap.textContent === "1 ✓"));
  assert.deepEqual(flowHead(loaded), ["1 ✓", "Пимп", "готов"]);
  assert.equal(kids(flowCard(loaded), "div")[2].style.getPropertyValue("display"), "block");
  assert.deepEqual(flowGlyphs(loaded), ["✓", "✓", "✓"]);
  assert.deepEqual(flowStages(loaded), [["критик", ""], ["кодинг", ""], ["тест", ""]]);
  assert.equal(flowWhen(loaded), "", "«о чём» целое — строки «подробности» нет");
  click(loaded, caps(rows(loaded)[0]).find(cap => cap.textContent === "1 ✓"));
  assert.equal(cardOpen(loaded), false);
  // Имя — сводка проекта: имя без значка-цвета и без плашки группы (число уже в счёте), счёт, список —
  // сперва идущие, потом впереди; готовые — за «Показать готовые ▾».
  click(loaded, kids(rows(loaded)[0], "b")[0]);
  assert.equal(rick(loaded).card, "project");
  assert.equal(panels(loaded), 0, "клик по имени открыл панель PMP");
  const p = card(loaded);
  assert.deepEqual([...kids(p, "header")[0].childNodes].map(node => node.textContent), ["Пимп"]);
  assert.equal(kids(p, "p")[0].textContent, "3 Workflow · готово 1 · идёт 1 · впереди 1");
  const items = () => kids(kids(card(loaded), "ul")[0], "li").map(li => (li.dataset.act ? li.textContent : [kids(li, "i")[0].textContent, kids(li, "span")[0].textContent]));
  assert.deepEqual(items(), [["2", "кодинг · карточка над капсулой"], ["3", "потом"], "Показать готовые ▾"]);
  // Капсулы списка — одной колонкой по самой широкой: «о чём» начинаются с одной линии (правило №14).
  assert.match(kids(card(loaded), "ul")[0].style.getPropertyValue("--cap"), /^\d+px$/);
  assert.doesNotMatch(p.textContent, /WF|Марафон|⚪/);
  // «Показать готовые ▾» — готовые свежими вперёд, строка — «Скрыть готовые ▴»; карточка не закрылась.
  card(loaded).dispatchEvent({ type: "click", detail: 1, target: kids(kids(card(loaded), "ul")[0], "li").find(li => li.dataset.act === "done") });
  assert.equal(rick(loaded).card, "project");
  assert.deepEqual(items(), [["2", "кодинг · карточка над капсулой"], ["3", "потом"], "Скрыть готовые ▴", ["1 ✓", "первый"]]);
  card(loaded).dispatchEvent({ type: "click", detail: 1, target: kids(kids(card(loaded), "ul")[0], "li").find(li => li.dataset.act === "done") });
  assert.equal(items().length, 3);
  // Пункт списка — карточка этого Workflow.
  card(loaded).dispatchEvent({ type: "click", detail: 1, target: kids(kids(p, "ul")[0], "li")[0] });
  assert.equal(rick(loaded).card, "flow");
  assert.equal(flowHead(loaded)[0], "2");
  assert.equal(card(loaded).style.getPropertyValue("display"), "none", "сводка проекта осталась под карточкой");
  // Esc — закрыть и не отдать Claude.
  assert.equal(loaded.dom.document.dispatchEvent({ type: "keydown", key: "Escape" }), false);
  assert.equal(cardOpen(loaded), false);
  // Клик мимо — закрыть; клик по полосе и по самой карточке — не «мимо».
  click(loaded, rows(loaded)[0]);
  assert.equal(rick(loaded).card, "project");
  loaded.dom.document.dispatchEvent({ type: "pointerdown", target: caps(rows(loaded)[0])[0] });
  assert.equal(cardOpen(loaded), true);
  click(loaded, caps(rows(loaded)[0]).find(cap => cap.textContent === "2"));
  loaded.dom.document.dispatchEvent({ type: "pointerdown", target: flowCard(loaded) });
  assert.equal(flowOpen(loaded), true, "клик по карточке её закрыл");
  loaded.dom.document.dispatchEvent({ type: "pointerdown", target: loaded.parts.editor });
  assert.equal(cardOpen(loaded), false);
  // «Открыть в Пимпе» — панель у часов, карточка закрыта.
  click(loaded, rows(loaded)[0]);
  const button = kids(card(loaded), "button")[0];
  assert.equal(button.textContent, "Открыть в Пимпе");
  card(loaded).dispatchEvent({ type: "click", detail: 1, target: button });
  assert.deepEqual(loaded.calls.filter(([url]) => url === PANEL), [[PANEL, "cors"]]);
  assert.equal(cardOpen(loaded), false);
  // Свёрнутое поле — ни полосы, ни карточки.
  click(loaded, caps(rows(loaded)[0]).find(cap => cap.textContent === "2"));
  loaded.api.setStage(loaded.api.stages.COLLAPSED);
  settle(loaded);
  assert.equal(layer(loaded).style.getPropertyValue("display"), "none");
  assert.equal(cardOpen(loaded), false);
});

// Сводка проекта, как её шлёт приложение командой status (раздел 2б): у Рика номера блоков не по
// порядку — /digest нумерует по порядку в файле (6-й блок — «9️⃣»), карточка находит блок по «о чём».
const RICK_FEED = [
  "# 🔰Rick",
  "обновлено вчера 23:30",
  "Сейчас: идут голос и сторож вопросов",
  "1️⃣ Workflow ✅ готово",
  "- о чём: публичный Рик",
  "- 20:30 → 21:11 · 41 мин",
  "- планирование · я · Opus 5.5 high",
  "- кодинг · 1 агент · Opus 5.5 medium",
  "- проверка · я · Opus 5.5 high",
  "9️⃣ Workflow 💭 идёт",
  "- о чём: сторож вопросов в чатах проектов: чат висит на вопросе разрешения, а Рик не знает — теперь знает",
  "- шаги 0 из 2",
  "- 23:49 → закончит в 00:07 · идёт 1 мин",
  "- критика · 1 агент · Fable max",
  "- кодинг · 2 агента · Opus 5.5 medium 💭",
  "- проверка · 1 агент · Opus 5.5 high",
].join("\n");
const feedDigest = () => digest({ name: "Rick", title: "Rick", group: "идут", workflows: [
  { n: 1, state: "готово", about: "публичный Рик", steps: "", phase: "" },
  { n: 2, state: "идёт", about: "сторож вопросов в чатах проектов: чат висит на вопросе разреш…", steps: "0/2", phase: "кодинг" },
] });

test("#9159: карточка Workflow — прежняя карточка полоски 2б: этапы и кто на них (модели), «когда», «о чём» целиком; блок — по «о чём»", async () => {
  const loaded = await page({ reply: ok(feedDigest()) });
  loaded.dom.command({ id: "s1", action: "status", at: "now", scope: "all", projects: [{ name: "Rick", text: RICK_FEED }] });
  click(loaded, caps(rows(loaded)[0]).find(cap => cap.textContent === "2"));
  assert.equal(rick(loaded).block, true, "блок не нашёлся");
  // Капсула — номер полосы (2), а не клавиша блока (9) и не «WF 2»: один знак на объект.
  assert.deepEqual(flowHead(loaded), ["2", "Rick", "идёт кодинг"]);
  assert.equal(kids(flowCard(loaded), "div")[1].textContent,
    "сторож вопросов в чатах проектов: чат висит на вопросе разрешения, а Рик не знает — теперь знает", "«о чём» срезано");
  // Этапы словами Элвиса — только записанные в блоке (WF198: планирования нет — и строки нет); кто —
  // модели и агенты (Fable max — 🔴); пройдено / идёт / впереди.
  assert.deepEqual(flowStages(loaded), [["критик", "🔴 Fable Max ×1"], ["кодинг", "Opus 5.5 Medium ×2"], ["тест", "Opus 5.5 High ×1"]]);
  assert.deepEqual(flowGlyphs(loaded), ["✓", "", ""]);
  // «Когда» без повтора «Идёт» (оно на плашке) и с днём: сводка вчерашняя.
  assert.equal(flowWhen(loaded), "Начался вчера в 23:49 · закончит в 00:07");
  assert.match(rick(loaded).flow, /идёт кодинг/);
  // «Кто» переносится, а не режется «…» (#9158).
  const who = flowRows(loaded)[1].children[3];
  assert.equal(who.style.getPropertyValue("white-space"), "normal");
  assert.notEqual(who.style.getPropertyValue("text-overflow"), "ellipsis");
  // «Сейчас:» сводки вчерашней — не показывается (как у полоски 2б: только сегодняшняя).
  assert.doesNotMatch(flowCard(loaded).textContent, /идут голос и сторож вопросов/);
  // Готовый: все записанные этапы пройдены, «Завершился … · занял 41 мин».
  click(loaded, caps(rows(loaded)[0]).find(cap => cap.textContent === "1 ✓"));
  assert.deepEqual(flowHead(loaded), ["1 ✓", "Rick", "готов"]);
  assert.deepEqual(flowStages(loaded).map(([stage, who]) => `${stage}:${who}`),
    ["план:я · Opus 5.5 High", "кодинг:Opus 5.5 Medium ×1", "тест:я · Opus 5.5 High"]);
  assert.deepEqual(flowGlyphs(loaded), ["✓", "✓", "✓"], "этапа без роли нет — три этапа, а не четыре");
  assert.equal(flowWhen(loaded), "Завершился вчера в 21:11 · занял 41 мин");
});

test("критик WF160: готовый без блока — «о чём» /digest без «…» (до целого слова) и строка, где оно целиком; ждущая капсула — обводкой, выбранная — обводкой внутрь", async () => {
  const loaded = await page({ reply: ok(digest({ name: "Rick", title: "Rick", workflows: [
    { n: 1, state: "готово", about: "публичный Рик — чистая выгрузка без памяти и ключей: програ…" },
    { n: 2, state: "ждёт", about: "показ меню", phase: "кодинг" }] })) });
  click(loaded, caps(rows(loaded)[0]).find(cap => cap.textContent === "1 ✓"));
  assert.equal(kids(flowCard(loaded), "div")[1].textContent, "публичный Рик — чистая выгрузка без памяти и ключей");
  // Строки «Подробности — в status.md» нет (WF175, #9195: «никто не будет смотреть»).
  assert.equal(flowWhen(loaded), "");
  assert.doesNotMatch(flowCard(loaded).textContent, /Подробности|status\.md/);
  assert.doesNotMatch(flowCard(loaded).textContent, /…|\.\.\./u);
  assert.deepEqual(flowGlyphs(loaded), ["✓", "✓", "✓", "✓"]);
  // Сводка проекта — тоже без «…».
  click(loaded, kids(rows(loaded)[0], "b")[0]);
  card(loaded).dispatchEvent({ type: "click", detail: 1, target: kids(kids(card(loaded), "ul")[0], "li").find(li => li.dataset.act === "done") });
  assert.doesNotMatch(card(loaded).textContent, /…|\.\.\./u);
  assert.equal(card(loaded).querySelector("ul").style.getPropertyValue("max-height") !== "", true, "у списка нет потолка — низ обрезался бы без признака");
  // «Ждёт тебя» в подсказке; капсула ждущего — обводкой (как идущие, но не дышит), не заливкой готовых.
  assert.equal(caps(rows(loaded)[0]).find(cap => cap.textContent === "2 !").title, "Rick · ждёт тебя · кодинг");
  const css = [...loaded.inner.RULES].join("\n").split("\n");
  assert.ok(css.some(rule => rule.includes('#myclaude-rick-cells>p>s>i:is([data-state="wait"],[data-state="fail"])') && /box-shadow:inset 0 0 0 \.5px/.test(rule) && !/animation/.test(rule)));
  assert.ok(css.some(rule => rule.startsWith('#myclaude-rick-cells>p>s>i[data-picked="true"]{') && rule.includes("outline-offset:-1.5px")), "обводка выбранной наезжает на соседей");
});

test("#9159: «Сейчас:» сегодняшней сводки — под идущим этапом, только у единственного живого Workflow проекта", async () => {
  const today = new Date();
  const feed = RICK_FEED.replace("обновлено вчера 23:30", `обновлено ${today.getDate()}.${String(today.getMonth() + 1).padStart(2, "0")}.${today.getFullYear()}`);
  const one = await page({ reply: ok(feedDigest()) });
  one.dom.command({ id: "s1", action: "status", at: "now", scope: "all", projects: [{ name: "Rick", text: feed }] });
  click(one, caps(rows(one)[0]).find(cap => cap.textContent === "2"));
  assert.match(flowCard(one).textContent, /идут голос и сторож вопросов/);
  const two = await page({ reply: ok(digest({ name: "Rick", title: "Rick", group: "идут", workflows: [
    { n: 1, state: "идёт", about: "публичный Рик", phase: "кодинг" },
    { n: 2, state: "идёт", about: "сторож вопросов в чатах проектов: чат висит на вопросе разреш…", phase: "кодинг" },
  ] })) });
  two.dom.command({ id: "s1", action: "status", at: "now", scope: "all", projects: [{ name: "Rick", text: feed.replace("1️⃣ Workflow ✅ готово", "1️⃣ Workflow 💭 идёт") }] });
  click(two, caps(rows(two)[0]).find(cap => cap.textContent === "2"));
  assert.equal(rick(two).block, true);
  assert.doesNotMatch(flowCard(two).textContent, /идут голос и сторож вопросов/, "строка проекта под одним из двух живых");
});

test("#9158, #9181: нижняя строка у Enter — место не зависит от числа строк и фильтра; один шрифт подписей нижней строки поля", async () => {
  const loaded = await page({ reply: ok(digest(P("A", "#111111", [...flows(3), { n: 4, state: "идёт", phase: "кодинг" }]), P("B", "#222222", flows(2)))) });
  tall(loaded);
  const spot = navBox(loaded);
  assert.equal(spot.right, SEND.left - 8);
  const pick = word => click(loaded, kids(nav(loaded), "a").find(item => item.textContent.startsWith(word)));
  pick("В работе");
  assert.equal(rows(loaded).length, 1);
  assert.deepEqual(navBox(loaded), spot, "«В работе» сдвинул фильтр");
  pick("Сделано");
  assert.deepEqual(navBox(loaded), spot, "«Готовы» сдвинул фильтр");
  pick("Всё");
  loaded.reply = ok(digest(...Array.from({ length: 6 }, (_, i) => P(`Проект${i + 1}`, "#123456", flows(2, "идёт")))));
  loaded.later(30000);
  loaded.dom.fireKind("interval");
  await tick();
  assert.equal(rows(loaded).length, 6);
  assert.deepEqual(navBox(loaded), spot, "больше строк — фильтр уехал");
  // Шрифт (#9181: «все шрифты разные»): имена и кнопки — гарнитурой и кеглем подписей нижней строки поля
  // (--rf, --rs), капсулы — той же гарнитурой, вторым кеглем 9; кнопки — цветом подписей (--k), как BY.
  const css = [...loaded.inner.RULES].join("\n");
  assert.match(css, /#myclaude-rick-cells>nav\{position:absolute;display:flex;align-items:center;[^}]*font:400 var\(--rs,11px\)\/16px var\(--rf,/);
  // Поля кнопки — 4, зазоры между всеми кнопками одинаковые (WF183); кегль — --ns (ужимается до 11).
  assert.match(css, /#myclaude-rick-cells>nav>a\{flex:0 0 auto;[^}]*padding:0 4px;[^}]*color:var\(--k,inherit\);font-size:var\(--ns,var\(--rs,11px\)\)/);
  assert.ok(!css.includes("#myclaude-rick-cells>nav>a[data-filter]+a"), "отдельный зазор группы перед «Отчёт» («огромный отступ»)");
  assert.match(css, /#myclaude-rick-cells>nav\{[^}]*font-variant-numeric:tabular-nums/, "цифры «В работе N» не табличные");
  assert.match(css, /#myclaude-rick-cells>p>s>b\{position:absolute;left:3px;[^}]*font:400 var\(--rs,11px\)\/16px var\(--rf,/);
  assert.match(css, /#myclaude-rick-cells>p>s>i\{[^}]*font:500 9px\/12px var\(--rf,/);
  const navRules = css.split("\n").filter(rule => rule.startsWith("#myclaude-rick-cells>nav"));
  for (const rule of navRules) assert.doesNotMatch(rule, /ellipsis|opacity:\.5/, rule);
  // Гарнитура, кегль и цвет — с кнопки нижней строки (BY): узел полосы несёт их переменными.
  const model = loaded.dom.query('[data-testid="epitaxy-cds-model-selector"]');
  assert.equal(model.getAttribute("data-myclaude-chin"), "text");
  model.computed = { ...model.computed, fontFamily: "anthropic-sans, system-ui", fontSize: "10px", color: "rgb(179, 162, 214)" };
  settle(loaded);
  assert.equal(layer(loaded).style.getPropertyValue("--rf"), "anthropic-sans, system-ui");
  assert.equal(layer(loaded).style.getPropertyValue("--rs"), "10px");
  assert.equal(layer(loaded).style.getPropertyValue("--k"), "rgb(179, 162, 214)");
});

test("#9191 (WF175), WF183: узкая колонка — кнопки ОДНОЙ линией у Enter полными словами, тесно — мельче кегль (до 11); не влезли — своей полосой под текстом; Enter в строке модели — своя полоса", async () => {
  const loaded = await page({ text: "длинный текст", reply: ok(digest(P("A", "#111111", [...flows(3), { n: 4, state: "идёт" }]))) });
  const root = loaded.parts.root;
  // Колонка ~330 (правая колонка Рика у Элвиса): полные слова в линию у Enter, без сокращений и чисел
  // (слово Элвиса 09.10 03:15: «Шрифт такого размера, чтобы в одну строку»).
  loaded.parts.shell.rect = { left: 770, top: 300, width: 330, height: 420 };
  root.rect = { left: 780, top: 600, width: 310, height: 55 };
  loaded.parts.editor.rect = { ...root.rect };
  settle(loaded);
  assert.equal(rick(loaded).nav, "send", "кнопки ушли от Enter");
  assert.equal(rick(loaded).navLines, 1);
  assert.equal(rick(loaded).navFont, 11);
  assert.deepEqual(words(loaded), ["˄", "В работе", "Сделано", "Всё", "Отчёт"]);
  assert.equal(nav(loaded).dataset.spot, "send");
  const css = [...loaded.inner.RULES].join("\n");
  assert.match(css, /#myclaude-rick-cells>nav\{[^}]*flex-wrap:nowrap/, "строка кнопок переносится");
  assert.match(css, /#myclaude-rick-cells>nav\[data-spot="send"\]\{justify-content:flex-end\}/);
  let line = navBox(loaded);
  assert.equal(line.right, SEND.left - 8, "правый край не у Enter");
  assert.ok(line.left >= 776, "кнопки вылезли за рамку");
  assert.equal(px(nav(loaded), "height"), 16);
  assert.equal((line.top + line.bottom) / 2, SEND.top + SEND.height / 2, "строка не по середине Enter");
  // Ширина каждой кнопки — явная; сумма с ОДИНАКОВЫМИ зазорами (2) — не шире строки; шеврон — 10 и поля 4.
  const sizes = kids(nav(loaded), "a").map(item => px(item, "width"));
  for (const size of sizes) assert.ok(size > 0);
  assert.equal(sizes[0], 18);
  assert.ok(sizes.reduce((sum, size) => sum + size, 0) + 4 * 2 <= px(nav(loaded), "width"), "линия не влезла");
  // Шеврон «˄» ↔ «˅» — та же ширина, строка не двигается.
  click(loaded, raiseButton(loaded));
  assert.equal(rick(loaded).raised, true);
  assert.equal(words(loaded)[0], "˅");
  assert.equal(px(viewButton(loaded), "width"), 18);
  assert.deepEqual(navBox(loaded), line);
  assert.ok(listBottom(loaded) <= navBox(loaded).top - 3, "строки наехали на кнопки");
  click(loaded, raiseButton(loaded));
  // Кегль строки модели 13 — кнопки им же, пока влезают; тесно (место 220) — мельче, первым влезшим шагом 0,5.
  const model = loaded.dom.query('[data-testid="epitaxy-cds-model-selector"]');
  model.computed = { ...model.computed, fontSize: "13px" };
  settle(loaded);
  assert.equal(rick(loaded).navFont, 13);
  assert.equal(nav(loaded).style.getPropertyValue("--ns"), "13px");
  loaded.parts.shell.rect = { left: 826, top: 300, width: 274, height: 420 };
  root.rect = { left: 836, top: 600, width: 254, height: 55 };
  loaded.parts.editor.rect = { ...root.rect };
  settle(loaded);
  assert.equal(rick(loaded).nav, "send");
  assert.equal(rick(loaded).navFont, 11.5, `кегль не ужался до влезающего: ${rick(loaded).navFont}, место ${px(nav(loaded), "width")}`);
  assert.deepEqual(words(loaded), ["˄", "В работе", "Сделано", "Всё", "Отчёт"], "слова сократились");
  assert.ok(kids(nav(loaded), "a").map(item => px(item, "width")).reduce((sum, size) => sum + size, 0) + 8 <= px(nav(loaded), "width"));
  model.computed = { ...model.computed, fontSize: "11px" };
  // Совсем узко (250): у Enter не влезает и кеглем 11 — одна линия своей полосой под текстом во всю
  // ширину рамки; место под неё — отступом снизу у прокрутки текста, текст выше кнопок.
  loaded.parts.shell.rect = { left: 850, top: 300, width: 250, height: 420 };
  root.rect = { left: 860, top: 600, width: 230, height: 55 };
  loaded.parts.editor.rect = { ...root.rect };
  settle(loaded);
  assert.equal(rick(loaded).nav, "below");
  assert.equal(rick(loaded).navLines, 1);
  assert.equal(rick(loaded).navFont, 11);
  assert.deepEqual(words(loaded), ["˄", "В работе", "Сделано", "Всё", "Отчёт"]);
  const room = rick(loaded).room;
  assert.equal(room, 16 + 4);
  root.rect = { ...root.rect, height: root.rect.height - room };
  loaded.parts.editor.rect = { ...root.rect };
  settle(loaded);
  assert.equal(rick(loaded).room, room, "отступ дрожит");
  line = navBox(loaded);
  assert.ok(line.top >= root.rect.top + root.rect.height + 2, `кнопки на тексте: ${line.top}`);
  assert.ok(line.bottom <= SEND.top, "кнопки на Enter");
  // Enter в нижней строке поля (там подписи Bp, Оп 5.5) — кнопки своей полосой под текстом, над строкой модели.
  loaded.parts.shell.rect = { left: 100, top: 300, width: 1000, height: 420 };
  root.rect = { left: 110, top: 600, width: 980, height: 55 };
  loaded.parts.send.rect = { left: 1060, top: 694, width: 24, height: 20 };
  settle(loaded);
  assert.equal(rick(loaded).nav, "below");
  assert.equal(rick(loaded).navLines, 1);
  assert.equal(rick(loaded).room, 16 + 4);
  root.rect = { ...root.rect, height: root.rect.height - 20 };
  settle(loaded);
  line = navBox(loaded);
  assert.equal(line.top, root.rect.top + root.rect.height + 2);
  assert.ok(line.bottom <= CHIN.top, "кнопки на строке модели");
  assert.equal(line.left, FRAME.left + 6 - 1, "текст первой кнопки не на линии имён (поле кнопки 4, имя с 3)");
});

// WF183 (слово Элвиса 09.10 03:30: «Вместо „Показать“ — стрелочка, как в Диктаторе, галочка вверх и вниз:
// нажал — вверх, нажал ещё раз — вниз»): два вида — строки видны (˅) и только кнопки (˄); помнится.
test("WF183: шеврон — два вида: строки видны «˅» → только кнопки «˄» → снова строки; помнится; прежний «short» — «full»", async () => {
  const many = digest(...Array.from({ length: 6 }, (_, i) => P(`Проект${i + 1}`, "#123456", flows(2, "идёт"))));
  const loaded = await page({ reply: ok(many) });
  tall(loaded);
  assert.equal(rick(loaded).view, "full");
  assert.equal(rows(loaded).length, 6);
  const line0 = navBox(loaded);
  const filters = () => words(loaded).slice(1);
  const before = filters();
  assert.deepEqual(before, ["В работе", "Сделано", "Всё", "Отчёт"]);
  assert.deepEqual([words(loaded)[0], viewButton(loaded).dataset.view, viewButton(loaded).dataset.chevron], ["˅", "none", "true"]);
  assert.equal(viewButton(loaded).getAttribute("aria-label"), "Скрыть проекты — останутся кнопки");
  assert.equal(kids(viewButton(loaded), "svg").length, 1, "шеврон — значком");
  const css = [...loaded.inner.RULES].join("\n");
  assert.match(css, /#myclaude-rick-cells>nav>a\[data-chevron\]>svg\{[^}]*fill:none;stroke:currentColor;[^}]*transition:transform/);
  assert.match(css, /#myclaude-rick-cells>nav>a\[data-chevron\]\[data-dir="down"\]>svg\{transform:rotate\(180deg\)\}/);
  // Нажал — строк нет совсем, остаются кнопки; шеврон «˄»; нижняя строка на месте.
  click(loaded, viewButton(loaded));
  assert.equal(rick(loaded).view, "none");
  assert.equal(rows(loaded).length, 0);
  assert.equal(rick(loaded).rows, 0);
  assert.equal(rick(loaded).fold, true);
  assert.equal(px(list(loaded), "height"), 0);
  assert.deepEqual([words(loaded)[0], viewButton(loaded).dataset.view], ["˄", "full"]);
  assert.deepEqual(filters(), before);
  assert.deepEqual(navBox(loaded), line0, "нижняя строка сдвинулась");
  assert.equal(px(layer(loaded), "top") + px(layer(loaded), "height"), line0.bottom, "блок — одна строка кнопок");
  assert.equal(loaded.win.localStorage.getItem("myclaude-rick-view"), "none");
  // Помнится: новая страница — без строк.
  const next = await page({ local: { "myclaude-rick-filter": "all", "myclaude-rick-view": "none" }, reply: ok(many) });
  assert.equal(rick(next).view, "none");
  assert.equal(rows(next).length, 0);
  assert.equal(words(next)[0], "˄");
  // Набран текст в виде «none» — «˄» поднимает полосу поверх текста и возвращает «full».
  loaded.parts.editor.add("p", { text: "привет", rect: { left: 110, top: 306, width: 200, height: 14 } });
  settle(loaded);
  assert.equal(rows(loaded).length, 0);
  assert.equal(viewButton(loaded).dataset.view, "full");
  click(loaded, viewButton(loaded));
  assert.equal(rick(loaded).view, "full");
  assert.equal(rick(loaded).raised, true, "с текстом — сразу поверх текста");
  assert.equal(rows(loaded).length, 6);
  assert.equal(words(loaded)[0], "˅");
  assert.equal(loaded.win.localStorage.getItem("myclaude-rick-view"), "full");
  // Стёр текст — снова «˅»: нажал — скрыл, нажал ещё раз — показал.
  click(loaded, raiseButton(loaded));
  loaded.parts.editor.textContent = "";
  settle(loaded);
  click(loaded, viewButton(loaded));
  assert.equal(rick(loaded).view, "none");
  click(loaded, viewButton(loaded));
  assert.equal(rick(loaded).view, "full");
  assert.equal(rows(loaded).length, 6);
  // Мусор и прежний вид «short» (WF179) в хранилище — «full».
  for (const view of ["xxx", "short"]) {
    const junk = await page({ local: { "myclaude-rick-view": view }, reply: ok(many) });
    assert.equal(rick(junk).view, "full", view);
  }
});

test("#9077: dispose — слоя нет, поздний ответ ничего не рисует, таймер снят", async () => {
  let answer = null;
  const loaded = await page({ reply: () => new Promise(resolve => { answer = resolve; }) });
  loaded.api.dispose();
  assert.equal(loaded.dom.query(LAYER), null);
  answer({ ok: true, json: () => Promise.resolve(digest({ name: "A", color: "#112233", workflows: flows(2) })) });
  await tick();
  assert.equal(loaded.dom.query(LAYER), null, "слой вернулся после dispose");
  assert.equal(loaded.dom.query(CARD), null, "карточка осталась после dispose");
});

test("#9145 (WF156), WF183: имена в полосе — 400, коротко и одной строкой, притемнённым цветом темы, без «:» и цвета проекта", async () => {
  const loaded = await page({ reply: ok(digest(P("Пимп", "#3366ff", flows(2, "идёт")), P("Вкуснофф", "#ff8800", flows(1)))) });
  tall(loaded);
  const [pimp, food] = rows(loaded);
  assert.deepEqual([nameOf(pimp), nameOf(food)], ["Пимп", "Вкуснофф"]);
  for (const row of [pimp, food]) assert.equal(row.style.getPropertyValue("--c"), "");
  // Колонка имён — замер самого длинного шрифтом полосы (#9181: кегль подписей нижней строки, 11; в стабе
  // 0,6 кегля на знак: «Вкуснофф» 8 × 6,6 + 4 → 57); капсулы — с одной линии за колонкой (правило №14).
  assert.equal(px(kids(pimp, "b")[0], "width"), 57);
  assert.equal(px(caps(pimp)[0], "left"), 3 + 57 + 3);
  assert.equal(px(caps(food)[0], "left"), px(caps(pimp)[0], "left"));
  // WF183 (слово Элвиса 09.10 03:35: «Не PimpMyClaude, а „Pimp“, VkusnoffKz — „Vkus“. Сокращённо… опять в две
  // строки»): имена коротко, хвост « — ночь 09.10» отброшен, полное — в подсказке; строка — одной высоты.
  loaded.reply = ok(digest(P("PimpMyClaude", "#3366ff", flows(2, "идёт")), P("VkusnoffKz — ночь 09.10", "#ff8800", flows(1)),
    P("Dictator", "#111111", flows(1, "идёт")), P("Очень-длинное-имя-проекта", "#222222", flows(1, "идёт"))));
  loaded.later(30000);
  loaded.dom.fireKind("interval");
  await tick();
  assert.deepEqual(rows(loaded).map(nameOf).sort(), ["Dictator", "Pimp", "Vkus", "Очень"]);
  const vkus = rows(loaded).find(row => nameOf(row) === "Vkus");
  assert.match(vkus.title, /^VkusnoffKz — ночь 09\.10 — 1 Workflow/, "полного имени нет в подсказке");
  for (const row of rows(loaded)) assert.equal(px(row, "height"), 16, `имя «${nameOf(row)}» в две строки`);
  // Колонка — по самому длинному короткому имени: «Dictator» 8 × 6,6 + 4 → 57.
  assert.equal(px(kids(rows(loaded)[0], "b")[0], "width"), 57);
  assert.deepEqual(["PimpMyClaude", "VkusnoffKz", "VkusnoffKz — ночь 09.10", "Dictator", "Trelvis", "Rick", "Rick voice", "Вкуснофф", "Проект1"].map(text => loaded.inner.rickShortName(text)),
    ["Pimp", "Vkus", "Vkus", "Dictator", "Trelvis", "Rick", "Rick", "Вкуснофф", "Проект1"]);
  assert.deepEqual(["PimpMyClaude", "PimpViewer", "Dictator"].map(text => loaded.inner.rickShortName(text, true)), ["PimpM", "PimpV", "Dictator"],
    "одно короткое имя у двух проектов — с буквой второй части");
  // Цвет имён — притемнённый цвет темы (--cds-text-secondary рамки поля), не текст поля (WF183: белые имена не нужны).
  loaded.parts.shell.computed = { ...loaded.parts.shell.computed, "--cds-text-secondary": "#6ca2bd" };
  settle(loaded);
  assert.equal(layer(loaded).style.getPropertyValue("--m"), "#6ca2bd");
  assert.equal(layer(loaded).style.getPropertyValue("--mo"), "1");
  const css = [...loaded.inner.RULES].join("\n");
  const name = css.split("\n").find(rule => rule.startsWith("#myclaude-rick-cells>p>s>b{"));
  assert.match(name, /white-space:nowrap/);
  assert.doesNotMatch(name, /ellipsis/);
  assert.match(name, /font:400 var\(--rs,11px\)/);
  assert.match(name, /color:var\(--m,inherit\);opacity:var\(--mo,0\.55\)/);
  assert.ok(!/var\(--c/.test(css.split("\n").filter(rule => rule.startsWith("#myclaude-rick-cells")).join("\n")), "цвет проекта в полосе");
  assert.ok(!/#myclaude-rick-cells[^\n]*font:(600|700)|#myclaude-rick-cells[^\n]*font-weight:(600|700)/.test(css), "жирное в полосе");
  assert.ok(!/#myclaude-rick-cells[^\n]*inset 0 0 0 1px/.test(css), "толстые обводки капсул");
});

test("#9145 (WF156): «+» у New — без серого кружка-заливки Claude, только значок", async () => {
  const loaded = await page();
  const { NEW_PLUS_SELECTOR } = loaded.inner;
  assert.equal(NEW_PLUS_SELECTOR, 'button[aria-keyshortcuts="Meta+n"] .df-new-circle');
  const rule = [...loaded.inner.RULES].find(item => item.startsWith(`${NEW_PLUS_SELECTOR}{`));
  assert.equal(rule, `${NEW_PLUS_SELECTOR}{background:transparent!important;box-shadow:none!important}`);
});

test("#9163 (WF175): «Отчёт» — последней кнопкой; в пустое поле ровно фраза, в непустое — с новой строки в конец; фокус в поле; не отправляет; двойной клик — без дубля", async () => {
  const loaded = await page({ reply: ok(digest(P("A", "#111111", [{ n: 1, state: "идёт" }]))) });
  const report = () => kids(nav(loaded), "a").at(-1);
  assert.equal(report().textContent, "Отчёт");
  assert.equal(report().dataset.act, "report");
  assert.equal(report().getAttribute("role"), "button");
  // Вид — как у соседних кнопок: то же правило nav>a и та же подсветка при наведении, без своей рамки.
  const css = [...loaded.inner.RULES].join("\n");
  assert.match(css, /#myclaude-rick-cells>nav>a:hover\{background:/);
  assert.doesNotMatch(css, /nav>a\[data-act="report"\]/, "у «Отчёта» свой вид");
  let sent = 0;
  loaded.parts.send.addEventListener("click", () => { sent += 1; });
  // Нажатие не отнимает фокус и не всплывает до Claude.
  assert.equal(layer(loaded).dispatchEvent({ type: "pointerdown", target: report() }), false, "нажатие отняло фокус у поля");
  click(loaded, report());
  assert.equal(loaded.parts.editor.innerText, "Рик, сделай отчёт по воркфлоу по правилам PMP");
  assert.equal(loaded.dom.document.activeElement, loaded.parts.editor, "фокус не в поле");
  assert.equal(rick(loaded).report, "вставлено");
  assert.equal(sent, 0, "«Отчёт» отправил сообщение");
  // Второй клик — фраза уже в конце поля: второй копии нет.
  click(loaded, report());
  assert.equal(loaded.parts.editor.innerText, "Рик, сделай отчёт по воркфлоу по правилам PMP");
  assert.equal(rick(loaded).report, "уже вставлено");
  // Непустое поле — с новой строки в конец, курсор в конце (следующий ввод — за фразой).
  loaded.parts.editor.innerText = "сначала моё";
  click(loaded, report());
  assert.equal(loaded.parts.editor.innerText, "сначала моё\nРик, сделай отчёт по воркфлоу по правилам PMP");
  assert.equal(rick(loaded).report, "вставлено в конец");
  assert.equal(loaded.dom.document.__caret, "end", "курсор не в конце");
  assert.equal(rick(loaded).reports, 3);
  assert.equal(sent, 0);
});

test("#9194 (WF175, WF179): идущий — капсула ровная, за номером маленький кружок тихо мигает (2,6 с), и при «Уменьшить движение»; место под кружок в ширине", async () => {
  const loaded = await page({ reply: ok(digest(P("A", "#111111", [{ n: 1, state: "готово" }, { n: 12, state: "идёт" }]))) });
  const [done, run] = caps(rows(loaded)[0]);
  assert.equal(run.textContent, "12", "у идущего знак текстом");
  assert.equal(done.textContent, "1 ✓");
  // Ширина — та же капсула номера плюс кружок с зазором (7): у будущего «12» кружка нет.
  const plan = await page({ reply: ok(digest(P("A", "#111111", [{ n: 12, state: "впереди" }]))) });
  assert.equal(px(run, "width"), px(caps(rows(plan)[0])[0], "width") + 7);
  const css = [...loaded.inner.RULES].join("\n").split("\n");
  const dot = css.find(rule => rule.includes('#myclaude-rick-cells>p>s>i[data-state="run"]') && rule.includes("::after{"));
  assert.ok(dot, "кружка нет");
  assert.match(dot, /content:"";display:inline-block;width:4px;height:4px;[^}]*border-radius:50%;background:currentColor;[^}]*animation:myclaude-rick-dot 2\.6s ease-in-out infinite/);
  assert.ok(css.some(rule => rule.startsWith("@keyframes myclaude-rick-dot{") && /opacity:\.2/.test(rule)), "кружок мигает не прозрачностью");
  assert.ok(!css.some(rule => /myclaude-rick-breathe/.test(rule)), "капсула идущего всё ещё дышит целиком");
  // WF179: мигает и при «Уменьшить движение» — мигание просил Элвис (#9194), а у Маков команды reduceMotion=1.
  assert.ok(!css.some(rule => rule.startsWith("@media (prefers-reduced-motion:reduce)") && rule.includes('[data-cap="run"])::after{animation:none}')), "при «Уменьшить движение» кружок не мигает");
});

test("WF175: пустое поле — строки полосы не заходят на первую строку редактора (подсказка Claude)", async () => {
  const loaded = await page({ reply: ok(digest(...Array.from({ length: 12 }, (_, i) => P(`П${i + 1}`, "#123456", [{ n: 1, state: "идёт" }])))) });
  tall(loaded);
  loaded.parts.editor.add("p", { text: "", rect: { left: 110, top: 310, width: 300, height: 20 } });
  settle(loaded);
  const listTop = px(layer(loaded), "top") + px(list(loaded), "top");
  assert.ok(listTop >= 330, `строки на подсказке: ${listTop}`);
});

// WF198 (#9159, слово Элвиса 08.10 ~23:38: «Шаг третий из трёх… Я там четыре шага вижу: планирование, критик,
// кодинг и тест…»; подписи «WF1» не нужны): этапов в карточке столько, сколько их у Workflow, — по
// ролям блока status.md, без блока — по шагам «N/M» из /digest; номер — капсулой, как в полосе. Данные —
// в форме живой сводки Элвиса 09.10 (PimpViewer 1 «3/3», Dictator 51 «1/2» на проверке, VkusnoffKz 9 «0/2»).
test("WF198 #9159: этапы карточки = шаги Workflow (без блока — «N/M» /digest, с блоком — роли), номер капсулой", async () => {
  const loaded = await page({ reply: ok(digest(
    { name: "Dictator", title: "Dictator", workflows: [
      { n: 50, state: "готово", about: "ревизия ночных правок (36–48)", phase: "", steps: "2/2" },
      { n: 51, state: "идёт", about: "9 находок ревизии", phase: "проверка", steps: "1/2" }] },
    { name: "VkusnoffKz", title: "VkusnoffKz", workflows: [{ n: 9, state: "впереди", about: "правки найденного проверкой корзины", phase: "", steps: "0/2" }] },
    { name: "PimpViewer", title: "PimpViewer", workflows: [{ n: 1, state: "готово", about: "галерея не вылетает при запуске", phase: "", steps: "3/3" }] },
    { name: "Rick", title: "Rick", workflows: [{ n: 1, state: "готово", about: "сборка 208", phase: "", steps: "2/2" }] },
  )) });
  // Четыре проекта в рамку не влезают — «+3 проекта» поднимает полосу.
  click(loaded, rows(loaded).find(line => line.dataset.state === "more"));
  const cap = (name, label) => {
    const row = rows(loaded).find(line => line.dataset.key === name);
    assert.ok(row, `строки ${name} нет: ${rows(loaded).map(line => line.textContent).join(" | ")}`);
    return caps(row).find(item => item.textContent === label);
  };
  // Идёт «1/2» на проверке: кодинг пройден ✓, тест идёт — два этапа, плашка называет идущий.
  click(loaded, cap("Dictator", "51"));
  assert.deepEqual(flowHead(loaded), ["51", "Dictator", "идёт тест"]);
  assert.deepEqual(flowStages(loaded), [["кодинг", ""], ["тест", ""]]);
  assert.deepEqual(flowGlyphs(loaded), ["✓", ""]);
  assert.doesNotMatch(flowCard(loaded).textContent, /WF|Воркфлоу|[Шш]аги/);
  // Впереди «0/2»: два этапа, оба впереди.
  click(loaded, cap("VkusnoffKz", "9"));
  assert.deepEqual(flowStages(loaded).map(([stage]) => stage), ["кодинг", "тест"]);
  assert.deepEqual(flowGlyphs(loaded), ["", ""]);
  // Готов «3/3»: три этапа ✓, не четыре (снимок Элвиса 16.png: «Шаги 3/3» при четырёх кружках).
  click(loaded, cap("PimpViewer", "1 ✓"));
  assert.deepEqual(flowHead(loaded), ["1 ✓", "PimpViewer", "готов"]);
  assert.deepEqual(flowStages(loaded).map(([stage]) => stage), ["критик", "кодинг", "тест"]);
  assert.deepEqual(flowGlyphs(loaded), ["✓", "✓", "✓"]);
  // С блоком: записан один кодинг при «шаги 2 из 2» — добирается тест; кто, модели и время — из блока.
  loaded.dom.command({ id: "s198", action: "status", at: "now", scope: "all", projects: [{ name: "Rick", text: [
    "# 🔰Rick", "обновлено вчера 23:30",
    "1️⃣ Workflow ✅ готово", "- о чём: сборка 208 (мягкий свет везде) на M4", "- шаги 2 из 2", "- 22:35 → 22:43",
    "- кодинг · 1 агент · Opus 5.5 medium",
  ].join("\n") }] });
  click(loaded, cap("Rick", "1 ✓"));
  assert.equal(rick(loaded).block, true, "блок не нашёлся");
  assert.deepEqual(flowStages(loaded), [["кодинг", "Opus 5.5 Medium ×1"], ["тест", ""]]);
  assert.deepEqual(flowGlyphs(loaded), ["✓", "✓"]);
  assert.equal(flowWhen(loaded), "Завершился вчера в 22:43 · занял 8 мин");
  // Роль «ревизия» (живой блок Dictator 50) — этап «критик» с моделью, а не пустая карточка.
  loaded.dom.command({ id: "s198b", action: "status", at: "now", scope: "all", projects: [{ name: "Dictator", text: [
    "# 🟢Dictator", "обновлено вчера 05:10",
    "5️⃣0️⃣ Workflow ✅ готово", "- о чём: ревизия ночных правок (36–48): ищем ещё стыки веток", "- шаги 2 из 2", "- 04:58 → 05:08",
    "- ревизия · 1 агент · Opus 5.5 high",
  ].join("\n") }] });
  click(loaded, cap("Dictator", "50 ✓"));
  assert.equal(rick(loaded).block, true, "блок Dictator не нашёлся");
  assert.deepEqual(flowStages(loaded), [["критик", "Opus 5.5 High ×1"], ["кодинг", ""]]);
});
