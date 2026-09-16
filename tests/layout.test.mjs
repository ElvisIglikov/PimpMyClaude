// Широкий вид окна (раздел 2г inject.js, WF65, задачи #6176–#6179).
//
// Слово Элвиса 16.09: в широком окне лента разговора — во всю высоту слева,
// шапка и поле ввода — правой колонкой; в узком окне всё как раньше. Плюс три
// мелочи во всех окнах: строка репозитория не показывается никогда, затемнения
// ленты убраны, имя папки в шапке не превращается в значок.
//
// Стаб DOM (tests/dom.mjs) `:has()`, `:is()` и `@container` в querySelector не
// понимает, поэтому раскладка проверяется двумя путями:
//   1) контракт CSS — разбором текста layoutCss() на «внутри блока
//      @container» / «снаружи»: сетка и флаг живут только внутри, три правила
//      «всегда» — только снаружи;
//   2) геометрия — флаг `--myclaude-wide` подкладывается панели через
//      computed, и проверяется то, что делает JS: ступени, ручка, рейка,
//      status().layout. Стенд шириной 1200 БЕЗ флага обязан остаться узким:
//      второго порога по innerWidth у страницы нет.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";

const { inner } = loadInner({ title: "Trelvis" });
const { layoutCss, WIDE_PANEL_MIN, SIDE_MIN, SIDE_MAX_SHARE, TITLEBAR_CLEARANCE } = inner;

const WIDE_FLAG = "--myclaude-wide";
const SIDE_VARIABLE = "--myclaude-side";
const SIDE_KEY = "myclaude-wide-side-v1";
const STAGE_KEY = "myclaude-input-stage-v1";
const HEIGHT_VARIABLE = "--myclaude-input-height";
const RAIL_ID = "myclaude-side-rail";
const HANDLE_ID = "myclaude-input-handle";
const COLLAPSED = 0;
const NORMAL = 1;
// Три правила «во всех окнах» — по их приметам.
const NAV = 'nav[aria-label="Repository and pull request controls"]';
const FADES = [".scroll-fade-strip-top", ".scroll-fade-strip-bottom"];
const CHIP_NAME = "group-data-\\[pills-compact\\]\\/lead\\:hidden";
// Три приметы проверенной формы разметки: сетка включается только на ней.
const FORM = [":has(> .epitaxy-titlebar)", ":has(> .contents > .epitaxy-chat-panel-body)", ":has(.group\\/approval-dock)"];

// ---- разбор CSS: дерево блоков по скобкам --------------------------------
// Правила сетки вложены (`&`), поэтому плоского «селектор { тело }» мало —
// строим дерево: у каждого блока селектор, объявления и дочерние блоки.
const parse = text => {
  const source = String(text).replace(/\/\*[\s\S]*?\*\//g, "");
  let index = 0;
  const block = () => {
    const children = [];
    let declarations = "";
    let buffer = "";
    while (index < source.length) {
      const char = source[index];
      if (char === "{") {
        const selector = buffer.trim();
        buffer = "";
        index += 1;
        const kid = block();
        kid.selector = selector;
        children.push(kid);
        continue;
      }
      if (char === "}") { index += 1; break; }
      if (char === ";") { declarations += `${buffer.trim()};`; buffer = ""; index += 1; continue; }
      buffer += char;
      index += 1;
    }
    return { selector: "", body: declarations, children };
  };
  return block().children;
};
const flatten = blocks => blocks.flatMap(item => [item, ...flatten(item.children)]);

const css = layoutCss();
const tree = parse(css);
const container = tree.find(item => item.selector.startsWith("@container"));
const outside = tree.filter(item => item !== container);
const inside = container ? flatten(container.children) : [];
const declarations = body => body.split(";").map(item => item.trim()).filter(Boolean);

test("порог широкого вида — контейнерный, по плитке чата, числом из люка", () => {
  assert.ok(container, "блока @container в layoutCss нет");
  assert.equal(container.selector, `@container tile-slot (min-width: ${WIDE_PANEL_MIN}px)`,
    "контейнер обязан быть tile-slot — так Claude зовёт обёртку панели чата");
  // Двум колонкам нужно место: правая не уже SIDE_MIN, а тексту слева — хотя бы
  // ширина поля ввода узкого окна (narrowLimit, 200).
  assert.ok(WIDE_PANEL_MIN >= SIDE_MIN + 200, `порог ${WIDE_PANEL_MIN} не вмещает колонку ${SIDE_MIN} и текст`);
  assert.ok(!/NaN|undefined|null/.test(css), "мусор в готовом CSS");
});

test("сетка и флаг --myclaude-wide живут ТОЛЬКО внутри блока @container", () => {
  const flag = inside.find(item => declarations(item.body).some(line => line.startsWith(`${WIDE_FLAG}: 1`)));
  assert.ok(flag, "флага-оракула внутри блока нет");
  assert.ok(flag.selector.startsWith(".epitaxy-chat-panel"), "флаг ставится на панель чата — его читает wideLayout()");
  // Флаг стоит на панели, поэтому те же три приметы смотрят на шаг глубже.
  for (const part of [":has(> div > .epitaxy-titlebar)", ":has(> div > .contents > .epitaxy-chat-panel-body)", FORM[2]]) {
    assert.ok(flag.selector.includes(part), `флаг не привязан к примете формы «${part}»`);
  }
  const grid = inside.find(item => /display:\s*grid/.test(item.body));
  assert.ok(grid, "правила сетки внутри блока нет");
  for (const part of FORM) assert.ok(grid.selector.includes(part), `сетка не проверяет форму «${part}»`);
  assert.match(grid.body, /grid-template-columns:\s*minmax\(0,\s*1fr\)\s+clamp\(/, "левая колонка — minmax(0,1fr), правая — clamp");
  assert.ok(grid.body.includes(`clamp(${SIDE_MIN}px, var(${SIDE_VARIABLE}), ${SIDE_MAX_SHARE * 100}%)`),
    "границы правой колонки в CSS — те же, что у рейки в JS");
  // Снаружи блока ни сетки, ни флага: в узком окне раскладка Claude не трогается.
  for (const item of outside) {
    assert.ok(!/display:\s*grid/.test(item.body), `сетка снаружи блока: «${item.selector}»`);
    assert.ok(!item.body.includes(WIDE_FLAG), `флаг снаружи блока: «${item.selector}»`);
    assert.equal(item.children.length, 0, `вложенные правила снаружи блока: «${item.selector}»`);
  }
});

test("дочерние правила сетки вложены в её условие — там, где сетки нет, они молчат", () => {
  const grid = inside.find(item => /display:\s*grid/.test(item.body));
  assert.ok(grid.children.length >= 6, "у сетки нет вложенных правил колонок и композера");
  for (const kid of grid.children) assert.ok(kid.selector.startsWith("&"), `правило «${kid.selector}» не вложено в условие сетки`);
  // Опасные объявления — только внутри сетки: без неё margin-left:0 у шапки съел
  // бы место под кнопки окна.
  const loose = inside.filter(item => item !== grid && !grid.children.includes(item));
  for (const item of loose) {
    assert.ok(!/margin-left|padding-left|padding-top/.test(item.body), `«${item.selector}» меняет отступы вне сетки`);
  }
  const titlebar = grid.children.find(item => item.selector === "& > .epitaxy-titlebar");
  assert.ok(titlebar && /grid-column:\s*2/.test(titlebar.body) && /margin-left:\s*0 !important/.test(titlebar.body),
    "шапка — правая колонка, без места под кнопки окна");
  const body = grid.children.find(item => item.selector === "& > .contents > .epitaxy-chat-panel-body");
  assert.ok(body && /grid-row:\s*1 \/ 3/.test(body.body) && /min-height:\s*0/.test(body.body),
    "лента — левая колонка на обе строки, min-height:0");
  // Место под кнопки окна — переменная, которую ставит JS по положению панели
  // (примета data-top-left у шапки врёт при открытой боковой панели, гейт 16.09).
  assert.ok(/padding-top:\s*var\(--myclaude-top-clearance, 0px\)/.test(body.body), "место под кнопки окна — переменной от JS");
  // Хвост виртуальной ленты Claude (`transcript-spacer`) не трогаем никогда: его
  // высоту пишет сам Claude, и правило на неё ломало прокрутку (17.09, #6176).
  assert.ok(!layoutCss().includes("transcript-spacer"), "хвост виртуальной ленты Claude не трогаем");
  const dock = grid.children.find(item => item.selector === "& .group\\/approval-dock");
  assert.ok(dock && /grid-column:\s*2/.test(dock.body) && /grid-row:\s*2/.test(dock.body), "дока — правая колонка, вторая строка");
  // Поля самой доки не трогаются: их держит sidePadding из claude.json через
  // USER-стиль с !important (гейт 16.09, 24px при любом нашем правиле). Отступ
  // 12 делает само поле ввода — выезжает в поля доки отрицательным margin,
  // считанным от той же переменной, которой задан её padding.
  assert.ok(!/padding-(?:left|right|inline)/.test(dock.body), "поля доки не трогаем — они от sidePadding");
  const prompt = grid.children.find(item => item.selector === "& .epitaxy-prompt");
  // Переменная Claude не наследуется (@property inherits:false) — дока переписывает
  // её в свою наследуемую, поле читает уже её.
  assert.ok(/--myclaude-dock-pad-start:\s*var\(--chat-column-gutter-start\)/.test(dock.body), "дока отдаёт свой отступ наследуемой переменной");
  assert.ok(prompt && /margin-inline:\s*calc\(12px - var\(--myclaude-dock-pad-start\)\) calc\(12px - var\(--myclaude-dock-pad-end\)\)/.test(prompt.body),
    "поле ввода стоит в 12 от краёв колонки при любом sidePadding");
});

test("поле ввода растёт цепочкой замера, а height:100% никому не раздаётся", () => {
  const grid = inside.find(item => /display:\s*grid/.test(item.body));
  const chain = [
    "& .epitaxy-prompt",
    '& [data-cds="ChatComposer"]',
    '& [data-cds="ChatComposer"] div:has(.ProseMirror):not(:has(> .ProseMirror))',
    '& [data-cds="ChatComposer"] div:has(> .ProseMirror)',
  ];
  for (const selector of chain) {
    const rule = grid.children.find(item => item.selector === selector);
    assert.ok(rule, `звена цепочки «${selector}» нет`);
    assert.match(rule.body, /flex:\s*1 1 auto/, `«${selector}» не растёт`);
    assert.match(rule.body, /min-height:\s*0/, `«${selector}» без min-height:0 не ужмётся`);
  }
  const editor = grid.children.find(item => item.selector === chain[3]);
  assert.match(editor.body, /max-height:\s*none !important/, "потолок области текста из attachmentsSheet снят");
  assert.ok(!/(^|[^-])height:\s*100%/.test(css), "height:100% в CSS быть не должно");
  // Плитка вложений 56×56 — дубль правила WF61 в контейнерном блоке.
  const tile = grid.children.find(item => item.selector.endsWith("[data-cds-composer-attachments] [data-cds-attachment]"));
  assert.ok(tile && /width:\s*56px !important/.test(tile.body) && /height:\s*56px !important/.test(tile.body), "плитка вложений в колонке не ужата");
  const down = grid.children.find(item => item.selector.includes('[aria-label="Scroll to bottom"]'));
  assert.ok(down && /right:\s*calc\(100% \+ \d+px\)/.test(down.body) && /bottom:\s*\d+px/.test(down.body),
    "кнопка «вниз» уходит к низу колонки текста");
});

test("три правила «во всех окнах» стоят снаружи блока: nav репозитория, затемнения, имя папки", () => {
  const nav = outside.find(item => item.selector === NAV);
  assert.ok(nav && /display:\s*none !important/.test(nav.body), "строка репозитория не спрятана");
  const fades = outside.find(item => FADES.every(fade => item.selector.includes(`.epitaxy-chat-panel ${fade}`)));
  assert.ok(fades && /display:\s*none !important/.test(fades.body), "затемнения ленты не спрятаны (и в узком окне тоже — слово Элвиса)");
  const chip = outside.find(item => item.selector.includes(CHIP_NAME));
  assert.ok(chip, "правила имени папки нет");
  assert.ok(chip.selector.startsWith(".epitaxy-titlebar") && chip.selector.includes("[data-pills-compact]"),
    "имя папки целится только в спрятанное имя чипа в шапке");
  assert.match(chip.body, /display:\s*inline-block !important/);
  for (const item of inside) {
    assert.ok(item.selector !== NAV && !FADES.some(fade => item.selector.includes(fade)) && !item.selector.includes(CHIP_NAME),
      `правило «всегда» попало внутрь блока: «${item.selector}»`);
  }
});

// ---- живая часть -----------------------------------------------------------

test("лист ставится один раз при инжекте, не удваивается на втором прогоне и уходит по dispose", () => {
  const loaded = loadInject({ title: "Trelvis" });
  assert.equal(loaded.error, null);
  assert.ok(loaded.dom.sheets().includes(WIDE_FLAG), "правил широкого вида нет в таблицах стилей окна");
  const sheets = loaded.counters.sheets;
  const again = loaded.reload();
  assert.equal(again.error, null);
  assert.equal(loaded.counters.sheets, sheets, "второй прогон таблицу удвоил");
  assert.ok(loaded.dom.sheets().includes(WIDE_FLAG), "после второго прогона правило на месте");
  loaded.api.dispose();
  assert.ok(!loaded.dom.sheets().includes(WIDE_FLAG), "правило осталось в окне после dispose");
});

test("в артефакте таблицы нет вовсе", () => {
  const alien = loadInject({ href: "data:text/html,<p>артефакт</p>", title: "Артефакт" });
  assert.equal(alien.error, null);
  assert.ok(!alien.dom.sheets().includes(WIDE_FLAG), "чужая страница получила наш лист стилей");
});

// Панель чата в форме замера 16.09: панель → div (сетка) → шапка + .contents
// (тело ленты + .contents → дока). Поле ввода — низ окна сборки 12.09 внутри
// доки. Геометрия — правая колонка 320 из панели 900, экран 1200×800.
const PANEL = { left: 200, top: 0, width: 900, height: 800 };
const DOCK = { left: 780, top: 32, width: 320, height: 768 };
const panelStand = ({ wide = true } = {}) => dom => {
  const panel = dom.document.body.add("div", {
    class: "epitaxy-chat-panel", rect: PANEL, computed: wide ? { [WIDE_FLAG]: "1" } : {},
  });
  const grid = panel.add("div", { class: "relative h-full min-w-0 flex flex-col", rect: PANEL });
  const titlebar = grid.add("div", {
    class: "epitaxy-titlebar", attrs: { "data-top-left": "true" },
    rect: { left: DOCK.left, top: 0, width: DOCK.width, height: 32 },
  });
  const contents = grid.add("div", { class: "contents" });
  const panelBody = contents.add("div", {
    class: "epitaxy-chat-panel-body", rect: { left: PANEL.left, top: 0, width: DOCK.left - PANEL.left, height: PANEL.height },
  });
  const dock = contents.add("div", { class: "contents" }).add("div", { class: "group/approval-dock flex flex-col", rect: DOCK });
  const prompt = dock.add("div", { class: "epitaxy-prompt", rect: { left: 792, top: 100, width: 296, height: 690 } });
  const block = prompt.add("div", { class: "flex w-full min-w-0 flex-col font-sans", rect: { left: 792, top: 100, width: 296, height: 690 } });
  const shell = block.add("div", {
    class: "bg-surface-3", rect: { left: 792, top: 100, width: 296, height: 660 },
    computed: { borderBottomWidth: "1px" },
  });
  const root = shell.add("div", {
    class: "editor-root", rect: { left: 802, top: 110, width: 276, height: 640 },
    computed: { overflowY: "auto" },
  });
  const editor = root.add("div", {
    class: "ProseMirror", attrs: { contenteditable: "true" }, rect: { left: 802, top: 110, width: 276, height: 640 },
  });
  const modelRow = block.add("div", { class: "model-row", rect: { left: 792, top: 770, width: 296, height: 20 } });
  return { panel, grid, titlebar, panelBody, dock, prompt, block, shell, root, editor, modelRow };
};
const open = (options = {}) => loadInject({ html: panelStand(options.stand ?? {}), title: "Trelvis", ...options });
const rail = loaded => loaded.dom.query(`#${RAIL_ID}`);
const handle = loaded => loaded.dom.query(`#${HANDLE_ID}`);
// Проход планируется через LAYOUT_MIN_GAP: сперва таймер, потом кадр.
const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};

test("стенд 1200 без флага остаётся узким: status().layout честный, ручка на месте, ступени ходят", () => {
  // Композер без панели вовсе (стенд всех остальных наборов).
  const bare = loadInject({ html: "composer", title: "Trelvis", geometry: { viewport: { width: 1200, height: 800 } } });
  assert.deepEqual(plain(bare.api.status().layout), { wide: false, panel: null, side: null });
  assert.equal(handle(bare).style.getPropertyValue("display"), "flex", "ручка видна");
  assert.equal(rail(bare).style.getPropertyValue("display"), "none", "рейки в узком виде нет");
  // Панель есть, флага нет — окно ýже порога: вид узкий, ширина панели известна.
  const narrow = open({ stand: { wide: false } });
  assert.deepEqual(plain(narrow.api.status().layout), { wide: false, panel: PANEL.width, side: null });
  assert.equal(handle(narrow).style.getPropertyValue("display"), "flex");
  narrow.api.setStage(COLLAPSED);
  assert.equal(narrow.api.status().stage, COLLAPSED, "ступени в узком виде работают");
  assert.equal(handle(narrow).dataset.collapsed, "true");
});

test("широкий вид: ступень обычная, замера natural нет, ручка спрятана, рейка на кромке колонки", () => {
  // Поле было свёрнуто (ступень 0 в хранилище): в широком виде оно обязано
  // открыться — ручки, которая вернула бы его, там нет.
  const loaded = open({ storage: { session: { [STAGE_KEY]: String(COLLAPSED) } } });
  assert.equal(loaded.error, null);
  assert.deepEqual(plain(loaded.api.status().layout), { wide: true, panel: PANEL.width, side: DOCK.width });
  assert.equal(loaded.api.status().stage, NORMAL, "в широком виде ступень одна — обычная");
  assert.equal(loaded.win.sessionStorage.getItem(STAGE_KEY), String(COLLAPSED), "хранилище ступени не переписано");
  assert.equal(loaded.api.status().natural, null, "обычная высота в широком виде не меряется");
  assert.equal(loaded.parts.root.style.getPropertyValue(HEIGHT_VARIABLE), "", "подмены высоты нет");
  assert.equal(loaded.api.status().handleVisible, false, "ручки нет");
  const bar = rail(loaded);
  assert.equal(bar.style.getPropertyValue("display"), "block", "рейка видна");
  assert.equal(bar.style.getPropertyValue("left"), `${DOCK.left - 4}px`, "рейка стоит на левой кромке доки (8 точек, по центру кромки)");
  assert.equal(bar.style.getPropertyValue("top"), `${PANEL.top}px`);
  assert.equal(bar.style.getPropertyValue("height"), `${PANEL.height}px`, "во всю высоту панели");
  assert.equal(loaded.dom.queryAll(`#${RAIL_ID}`).length, 1, "узел один на окно");
  // Панель начинается на 200 — кнопок окна над лентой нет, места под них не оставляем.
  assert.equal(loaded.parts.panel.style.getPropertyValue("--myclaude-top-clearance"), "0px", "боковая панель открыта — лента от самого верха");
  // Панель у левого края окна (свёрнутая боковая панель, попап) — кнопки окна над лентой.
  loaded.parts.panel.rect = { ...PANEL, left: 40 };
  settle(loaded);
  assert.equal(loaded.parts.panel.style.getPropertyValue("--myclaude-top-clearance"), `${TITLEBAR_CLEARANCE}px`, "панель у края окна — место под кнопки");
});

test("возврат в узкий вид: ступень берётся из хранилища, рейка прячется, ручка возвращается", () => {
  const loaded = open({ storage: { session: { [STAGE_KEY]: String(COLLAPSED) } } });
  assert.equal(loaded.api.status().stage, NORMAL);
  loaded.parts.panel.computed = {};
  settle(loaded);
  assert.equal(loaded.api.status().layout.wide, false, "флаг снят — вид узкий");
  assert.equal(loaded.api.status().stage, COLLAPSED, "поле вернулось свёрнутым — как его оставили");
  assert.equal(rail(loaded).style.getPropertyValue("display"), "none");
  assert.equal(handle(loaded).style.getPropertyValue("display"), "flex", "ручка снова на месте");
});

test("рейка: тяга меняет --myclaude-side в границах, отпускание пишет хранилище, двойной клик — умолчание", () => {
  const loaded = open();
  const { panel } = loaded.parts;
  const bar = rail(loaded);
  const drag = (from, to) => {
    bar.dispatchEvent({ type: "pointerdown", button: 0, clientX: from, pointerId: 1 });
    loaded.document.dispatchEvent({ type: "pointermove", clientX: to, pointerId: 1 });
  };
  const drop = to => loaded.document.dispatchEvent({ type: "pointerup", clientX: to, pointerId: 1 });
  drag(776, 700);
  assert.equal(bar.dataset.dragging, "true");
  assert.equal(loaded.document.documentElement.style.cursor, "col-resize");
  // Ширина = правый край панели (1100) − курсор.
  assert.equal(panel.style.getPropertyValue(SIDE_VARIABLE), "400px");
  assert.equal(loaded.win.localStorage.getItem(SIDE_KEY), null, "пока тянут — в хранилище ничего");
  drop(700);
  assert.equal(bar.dataset.dragging, "false");
  assert.equal(loaded.document.documentElement.style.cursor, "");
  assert.equal(loaded.win.localStorage.getItem(SIDE_KEY), "400", "отпустили — ширина в хранилище");
  // Границы: не уже SIDE_MIN, не шире доли панели.
  drag(700, 1050); drop(1050);
  assert.equal(panel.style.getPropertyValue(SIDE_VARIABLE), `${SIDE_MIN}px`, "уже минимума не даём");
  drag(800, 100); drop(100);
  assert.equal(panel.style.getPropertyValue(SIDE_VARIABLE), `${Math.round(PANEL.width * SIDE_MAX_SHARE)}px`, "шире доли панели не даём");
  bar.dispatchEvent({ type: "dblclick" });
  assert.equal(panel.style.getPropertyValue(SIDE_VARIABLE), "", "двойной клик снял свою ширину — сетка берёт умолчание из CSS");
  assert.equal(loaded.win.localStorage.getItem(SIDE_KEY), null, "и из хранилища тоже");
});

test("сохранённая ширина ставится при инжекте, а dispose снимает её с чужого узла", () => {
  const loaded = open({ storage: { local: { [SIDE_KEY]: "380" } } });
  assert.equal(loaded.parts.panel.style.getPropertyValue(SIDE_VARIABLE), "380px", "ширина из хранилища на панели");
  loaded.api.dispose();
  assert.equal(loaded.parts.panel.style.getPropertyValue(SIDE_VARIABLE), "", "после dispose на панели нашего нет");
  assert.equal(loaded.dom.queryAll(`#${RAIL_ID}`).length, 0, "рейка снята");
  assert.equal(loaded.win.localStorage.getItem(SIDE_KEY), "380", "хранилище dispose не трогает");
  // Мусор в хранилище (меньше минимума, не число) — умолчание CSS.
  const junk = open({ storage: { local: { [SIDE_KEY]: "12" } } });
  assert.equal(junk.parts.panel.style.getPropertyValue(SIDE_VARIABLE), "", "негодная ширина не ставится");
});
