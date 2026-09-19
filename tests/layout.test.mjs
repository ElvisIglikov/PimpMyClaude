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
const { layoutCss, WIDE_PANEL_MIN, SIDE_MIN, SIDE_FLOOR, SIDE_CHIN_GAP, CHIN_ROW_SELECTOR, SIDE_MAX_SHARE, TITLE_SIDE_ATTRIBUTE, WIDE_TILE } = inner;

const WIDE_FLAG = "--myclaude-wide";
const SIDE_VARIABLE = "--myclaude-side";
// Нижняя граница колонки по строке модели (WF68, #6212): JS кладёт её на панель
// этой переменной, CSS берёт её в clamp; без неё — SIDE_MIN.
const SIDE_MIN_VARIABLE = "--myclaude-side-min";
// v2 с WF68: ширины v1 (у Элвиса лежало ровно 300 — старый минимум) не читаются.
const SIDE_KEY = "myclaude-wide-side-v2";
const SIDE_KEY_V1 = "myclaude-wide-side-v1";
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
// Тело ленты — с виртуальной лентой внутри (WF66): домашний экран без неё сетку не получает.
const FORM = [":has(> .epitaxy-titlebar)", ':has(> .contents > .epitaxy-chat-panel-body [data-testid="epitaxy-virtual-transcript"])', ":has(.group\\/approval-dock)"];

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
  // Тело ленты — с виртуальной лентой внутри: домашний экран без неё сетку не получает.
  for (const part of [":has(> div > .epitaxy-titlebar)", ':has(> div > .contents > .epitaxy-chat-panel-body [data-testid="epitaxy-virtual-transcript"])', FORM[2]]) {
    assert.ok(flag.selector.includes(part), `флаг не привязан к примете формы «${part}»`);
  }
  const grid = inside.find(item => /display:\s*grid/.test(item.body));
  assert.ok(grid, "правила сетки внутри блока нет");
  for (const part of FORM) assert.ok(grid.selector.includes(part), `сетка не проверяет форму «${part}»`);
  assert.match(grid.body, /grid-template-columns:\s*minmax\(0,\s*1fr\)\s+clamp\(/, "левая колонка — minmax(0,1fr), правая — clamp");
  // Нижняя граница — пол SIDE_FLOOR (#6625: замер строки модели держит только
  // умолчание, рейкой можно ýже); верхняя — доля панели, та же, что у рейки.
  assert.ok(grid.body.includes(`clamp(${SIDE_FLOOR}px, var(${SIDE_VARIABLE}), ${SIDE_MAX_SHARE * 100}%)`),
    "границы правой колонки в CSS — те же, что у рейки в JS");
  // Группы строки модели в широком виде не ужимаются: по их ширине считается
  // нижняя граница, и ужатая строка мерилась бы ужатой (граница застряла бы).
  // Правило — только в доке, куда смотрит и JS (chinRow → sideDock).
  // Колонка ýже замера (#6625) — панель помечена, и группам снова можно ужиматься.
  const chin = grid.children.find(item => item.selector === `&:not(.epitaxy-chat-panel[data-myclaude-side-tight] > *) .group\\/approval-dock ${CHIN_ROW_SELECTOR} > *`);
  assert.ok(chin && /flex-shrink:\s*0/.test(chin.body), "группы строки модели в доке должны держать натуральную ширину");
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
  assert.ok(titlebar && /grid-column:\s*2/.test(titlebar.body) && /margin-left:\s*-\d+px !important/.test(titlebar.body),
    "шапка — правая колонка, без места под кнопки окна");
  const body = grid.children.find(item => item.selector === "& > .contents > .epitaxy-chat-panel-body");
  assert.ok(body && /grid-row:\s*1 \/ 3/.test(body.body) && /min-height:\s*0/.test(body.body),
    "лента — левая колонка на обе строки, min-height:0");
  // Шапка уезжает влево под кнопки окна по атрибуту, который ставит JS по положению
  // панели (примета data-top-left у шапки врёт при открытой боковой панели, гейт 16.09).
  const titleLeft = grid.children.find(item => item.selector.includes('[data-myclaude-title="left"]') && item.selector.endsWith("> .epitaxy-titlebar"));
  assert.ok(titleLeft && /grid-column:\s*1/.test(titleLeft.body), "шапка влево — по атрибуту от JS");
  // Хвост виртуальной ленты Claude (`transcript-spacer`) не трогаем никогда: его
  // высоту пишет сам Claude, и правило на неё ломало прокрутку (17.09, #6176).
  assert.ok(!layoutCss().includes("transcript-spacer"), "хвост виртуальной ленты Claude не трогаем");
  // WF66: вложения после текста без потолка и прокрутки, текст без правого поля под кнопку.
  const slot = grid.children.find(item => item.selector.endsWith("div:has(> [data-cds-composer-attachments])"));
  assert.ok(slot && /order:\s*2/.test(slot.body), "слот вложений — последним ребёнком коробки");
  const attachments = grid.children.find(item => item.selector.endsWith("[data-cds-composer-attachments]"));
  assert.ok(attachments && /max-height:\s*none !important/.test(attachments.body) && /overflow:\s*visible !important/.test(attachments.body),
    "вложения целиком, без своей прокрутки");
  // Домашний экран (без виртуальной ленты) сетку не получает.
  assert.ok(grid.selector.includes('[data-testid="epitaxy-virtual-transcript"]'), "сетка только у страницы с лентой");
  const textWrap = grid.children.find(item => item.selector === '& [data-cds="ChatComposer"] div[style*="--cmp-wrap-h"]');
  assert.ok(textWrap && /padding-right:\s*0 !important/.test(textWrap.body) && /padding-bottom:\s*\d+px !important/.test(textWrap.body),
    "текст во всю ширину, последняя строка выше кнопки отправки");
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
  // Плитка вложений в колонке — мельче узкой (WF66, слово Элвиса: «превьюшки помельче»).
  const tile = grid.children.find(item => item.selector.endsWith("[data-cds-composer-attachments] [data-cds-attachment]"));
  assert.ok(tile && new RegExp(`width:\\s*${WIDE_TILE}px !important`).test(tile.body) && new RegExp(`height:\\s*${WIDE_TILE}px !important`).test(tile.body), "плитка вложений в колонке не ужата");
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
const panelStand = ({ wide = true, chin = true } = {}) => dom => {
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
  // Строка модели — в форме замера 17.09 (WF68): ChatComposerChin → обёртка →
  // строка с полями --cmp-chin-* и двумя группами: «+ 🎤 ⌄ Auto» (98) и
  // «Fable 5.1 · Extra · ◑» (137, своё поле слева внутри). Поля строки 7 и 10,
  // как в бою; строка во всю ширину поля (296 при колонке 308 = дока 320 − 12).
  const modelRow = block.add("div", { class: "model-row", attrs: chin ? { "data-cds": "ChatComposerChin" } : {}, rect: { left: 792, top: 770, width: 296, height: 20 } });
  let chinRow = null, chinLeft = null, chinRight = null;
  if (chin) {
    const wrap = modelRow.add("div", { class: "min-h-0", rect: { left: 792, top: 770, width: 296, height: 20 } });
    chinRow = wrap.add("div", {
      class: "flex min-h-control items-center gap-0 text-footnote ps-[var(--cmp-chin-start)] pe-[var(--cmp-chin-end)] justify-between",
      rect: { left: 792, top: 770, width: 296, height: 20 },
      computed: { "padding-left": "7px", "padding-right": "10px" },
    });
    chinLeft = chinRow.add("div", { class: "flex items-center self-start", rect: { left: 799, top: 770, width: CHIN_LEFT, height: 20 } });
    chinRight = chinRow.add("div", { class: "ms-auto flex min-w-0 items-center gap-1 ps-2", rect: { left: 1078 - CHIN_RIGHT, top: 770, width: CHIN_RIGHT, height: 20 } });
  }
  return { panel, grid, titlebar, panelBody, dock, prompt, block, shell, root, editor, modelRow, chinRow, chinLeft, chinRight };
};
const CHIN_LEFT = 98;
const CHIN_RIGHT = 137;
// Ожидаемая нижняя граница стенда: группы + поля строки (17) + зазор + обвязка
// (колонка 308 − строка 296 = 12).
const CHIN_MIN = CHIN_LEFT + CHIN_RIGHT + 17 + SIDE_CHIN_GAP + (DOCK.width - 12 - 296);
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
  assert.deepEqual(plain(bare.api.status().layout), { wide: false, panel: null, side: null, sideMin: null });
  assert.equal(handle(bare).style.getPropertyValue("display"), "flex", "ручка видна");
  assert.equal(rail(bare).style.getPropertyValue("display"), "none", "рейки в узком виде нет");
  // Панель есть, флага нет — окно ýже порога: вид узкий, ширина панели известна.
  const narrow = open({ stand: { wide: false } });
  assert.deepEqual(plain(narrow.api.status().layout), { wide: false, panel: PANEL.width, side: null, sideMin: null });
  assert.equal(narrow.parts.panel.style.getPropertyValue(SIDE_MIN_VARIABLE), "", "в узком виде нижней границы на панели нет");
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
  assert.deepEqual(plain(loaded.api.status().layout), { wide: true, panel: PANEL.width, side: DOCK.width, sideMin: CHIN_MIN });
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
  // Панель начинается на 200 — кнопок окна над лентой нет, шапка справа.
  assert.equal(loaded.parts.panel.getAttribute(TITLE_SIDE_ATTRIBUTE), null, "боковая панель открыта — шапка справа");
  // Панель у левого края окна (свёрнутая боковая панель, попап) — шапка уезжает влево под кнопки окна.
  loaded.parts.panel.rect = { ...PANEL, left: 40 };
  settle(loaded);
  assert.equal(loaded.parts.panel.getAttribute(TITLE_SIDE_ATTRIBUTE), "left", "панель у края окна — шапка влево");
  assert.equal(loaded.parts.panel.style.getPropertyValue("--myclaude-title-inset"), "112px", "отступ под кнопки окна главного окна");
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
  // Захват ровно на кромке доки (780): зазор курсор–кромка нулевой, ширина = правый край панели − курсор.
  drag(DOCK.left, 700);
  assert.equal(bar.dataset.dragging, "true");
  assert.equal(loaded.document.documentElement.style.cursor, "col-resize");
  // Ширина = правый край панели (1100) − курсор.
  assert.equal(panel.style.getPropertyValue(SIDE_VARIABLE), "400px");
  assert.equal(loaded.win.localStorage.getItem(SIDE_KEY), null, "пока тянут — в хранилище ничего");
  drop(700);
  assert.equal(bar.dataset.dragging, "false");
  assert.equal(loaded.document.documentElement.style.cursor, "");
  assert.equal(loaded.win.localStorage.getItem(SIDE_KEY), "400", "отпустили — ширина в хранилище");
  // Границы: не уже пола (#6625 — ýже строки модели можно), не шире доли панели.
  drag(700, 1050); drop(1050);
  assert.equal(panel.style.getPropertyValue(SIDE_VARIABLE), `${SIDE_FLOOR}px`, "уже пола не даём");
  drag(800, 100); drop(100);
  assert.equal(panel.style.getPropertyValue(SIDE_VARIABLE), `${Math.round(PANEL.width * SIDE_MAX_SHARE)}px`, "шире доли панели не даём");
  bar.dispatchEvent({ type: "dblclick" });
  assert.equal(panel.style.getPropertyValue(SIDE_VARIABLE), "", "двойной клик снял свою ширину — сетка берёт умолчание из CSS");
  assert.equal(loaded.win.localStorage.getItem(SIDE_KEY), null, "и из хранилища тоже");
});

test("сохранённая ширина ставится при инжекте, а dispose снимает её с чужого узла", () => {
  const loaded = open({ storage: { local: { [SIDE_KEY]: "380" } } });
  assert.equal(loaded.parts.panel.style.getPropertyValue(SIDE_VARIABLE), "380px", "ширина из хранилища на панели");
  assert.equal(loaded.parts.panel.style.getPropertyValue(SIDE_MIN_VARIABLE), `${CHIN_MIN}px`, "нижняя граница на панели");
  loaded.api.dispose();
  assert.equal(loaded.parts.panel.style.getPropertyValue(SIDE_VARIABLE), "", "после dispose на панели нашего нет");
  assert.equal(loaded.parts.panel.style.getPropertyValue(SIDE_MIN_VARIABLE), "", "и нижней границы тоже");
  assert.equal(loaded.dom.queryAll(`#${RAIL_ID}`).length, 0, "рейка снята");
  assert.equal(loaded.win.localStorage.getItem(SIDE_KEY), "380", "хранилище dispose не трогает");
  // Мусор в хранилище (ниже пола, не число) — умолчание CSS; ширина между полом
  // и запасным минимумом — годная: нижнюю границу по строке модели дорежет clamp.
  const junk = open({ storage: { local: { [SIDE_KEY]: "12" } } });
  assert.equal(junk.parts.panel.style.getPropertyValue(SIDE_VARIABLE), "", "негодная ширина не ставится");
  const low = open({ storage: { local: { [SIDE_KEY]: String(SIDE_FLOOR + 10) } } });
  assert.equal(low.parts.panel.style.getPropertyValue(SIDE_VARIABLE), `${SIDE_FLOOR + 10}px`, "ширина не ниже пола ставится");
  // Ширины v1 не читаются: под ними лежал старый минимум 300, и новая граница
  // осталась бы за ним невидимой (WF68).
  const stale = open({ storage: { local: { [SIDE_KEY_V1]: "300" } } });
  assert.equal(stale.parts.panel.style.getPropertyValue(SIDE_VARIABLE), "", "ширина v1 не переносится");
  assert.equal(stale.win.localStorage.getItem(SIDE_KEY), null, "и в v2 не переписывается");
});

test("нижняя граница колонки — по строке модели: считается из групп, следует за ними, без строки — запасной минимум", () => {
  const loaded = open();
  const { panel, chinRow, chinLeft, chinRight } = loaded.parts;
  assert.equal(panel.style.getPropertyValue(SIDE_MIN_VARIABLE), `${CHIN_MIN}px`, "граница = группы + поля строки + зазор + обвязка");
  assert.ok(CHIN_MIN < SIDE_MIN, `стенд обязан показать границу ниже 300, а вышло ${CHIN_MIN}`);
  assert.equal(loaded.api.status().layout.sideMin, CHIN_MIN);
  // Имя модели стало длиннее (Fable 5.1 → Sonnet 5.1 Medium): правая группа
  // шире на 20, граница выше на 20 — в обе стороны, каждый проход.
  chinRight.rect = { ...chinRight.rect, width: CHIN_RIGHT + 20 };
  settle(loaded);
  assert.equal(panel.style.getPropertyValue(SIDE_MIN_VARIABLE), `${CHIN_MIN + 20}px`, "граница выросла за строкой");
  chinRight.rect = { ...chinRight.rect, width: CHIN_RIGHT };
  settle(loaded);
  assert.equal(panel.style.getPropertyValue(SIDE_MIN_VARIABLE), `${CHIN_MIN}px`, "и вернулась");
  // Рейка уводит колонку ýже строки модели, до пола (#6625); панель помечается,
  // замер замирает на натуральном, шире замера — пометка снимается.
  const bar = rail(loaded);
  bar.dispatchEvent({ type: "pointerdown", button: 0, clientX: DOCK.left, pointerId: 1 });
  loaded.document.dispatchEvent({ type: "pointermove", clientX: 1090, pointerId: 1 });
  loaded.document.dispatchEvent({ type: "pointerup", clientX: 1090, pointerId: 1 });
  assert.equal(panel.style.getPropertyValue(SIDE_VARIABLE), `${SIDE_FLOOR}px`, "тяга уводит ниже строки модели, до пола");
  settle(loaded);
  assert.ok(panel.hasAttribute("data-myclaude-side-tight"), "колонка ýже замера — панель помечена");
  assert.equal(panel.style.getPropertyValue(SIDE_MIN_VARIABLE), `${CHIN_MIN}px`, "замер замер на натуральном");
  loaded.win.localStorage.removeItem(SIDE_KEY);
  panel.style.removeProperty(SIDE_VARIABLE);
  settle(loaded); settle(loaded);
  assert.ok(!panel.hasAttribute("data-myclaude-side-tight"), "ширина по умолчанию — пометка снята");
  // Совсем короткая строка не роняет колонку ниже пола: редактору нужны narrowLimit.
  chinLeft.rect = { ...chinLeft.rect, width: 40 };
  chinRight.rect = { ...chinRight.rect, width: 40 };
  settle(loaded);
  assert.equal(panel.style.getPropertyValue(SIDE_MIN_VARIABLE), `${SIDE_FLOOR}px`, "ниже пола не опускаемся");
  // Строка пропала (Claude перерисовал низ) — запасной минимум, а не мусор.
  chinRow.remove();
  settle(loaded);
  assert.equal(panel.style.getPropertyValue(SIDE_MIN_VARIABLE), `${SIDE_MIN}px`, "без строки модели — запасной минимум");
  // Узкий вид снимает границу с панели.
  panel.computed = {};
  settle(loaded);
  assert.equal(panel.style.getPropertyValue(SIDE_MIN_VARIABLE), "", "в узком виде переменной нет");
  // Стенд без строки модели вовсе (чужая сборка): как до WF68.
  const bare = open({ stand: { chin: false } });
  assert.equal(bare.parts.panel.style.getPropertyValue(SIDE_MIN_VARIABLE), `${SIDE_MIN}px`);
  assert.equal(bare.api.status().layout.sideMin, SIDE_MIN);
});
