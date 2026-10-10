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
// С 2.2553.13 (WF82, #7098) тело ленты лежит в ДВУХ `div.contents`, а не в одном:
// примета принимает обе формы — старую сборку и новую.
const TRANSCRIPT = '[data-testid="epitaxy-virtual-transcript"]';
const BODY_OLD = "> .contents > .epitaxy-chat-panel-body";
const BODY_NEW = "> .contents > .contents > .epitaxy-chat-panel-body";
const bodyForm = prefix => `:has(${prefix}${BODY_OLD} ${TRANSCRIPT}, ${prefix}${BODY_NEW} ${TRANSCRIPT})`;
const FORM = [":has(> .epitaxy-titlebar)", bodyForm(""), ":has(.group\\/approval-dock)"];
// WF125 (#8846): колонка с шапкой — ребёнок панели (попап, прежнее главное окно)
// или внук через `div.contents` (главное окно 2.19675.0).
const COLUMNS = ["> div", "> .contents > div"];

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
  // Флаг стоит на панели, поэтому те же три приметы смотрят на шаг глубже — по
  // селектору на каждую форму пути к колонке (`:has()` внутри `:has()` нельзя).
  // Тело ленты — с виртуальной лентой внутри: домашний экран без неё сетку не получает.
  assert.deepEqual(flag.selector.split(/,\s*(?=\.epitaxy-chat-panel:has)/), COLUMNS.map(column =>
    `.epitaxy-chat-panel:has(${column} > .epitaxy-titlebar)${bodyForm(`${column} `)}${FORM[2]}`),
    "флаг — по селектору на форму: колонка ребёнком панели и внуком через div.contents");
  assert.ok(!/:has\([^()]*:has\(/.test(css), "вложенный :has() — правило выпадет целиком");
  const grid = inside.find(item => /display:\s*grid/.test(item.body));
  assert.ok(grid, "правила сетки внутри блока нет");
  assert.ok(grid.selector.startsWith(`:is(${COLUMNS.map(column => `.epitaxy-chat-panel ${column}`).join(", ")}):has(`),
    "сетка — на колонке-родителе шапки в обеих формах пути от панели");
  for (const part of FORM) assert.ok(grid.selector.includes(part), `сетка не проверяет форму «${part}»`);
  assert.match(grid.body, /grid-template-columns:\s*minmax\(0,\s*1fr\)\s+clamp\(/, "левая колонка — minmax(0,1fr), правая — clamp");
  // Нижняя граница — пол SIDE_FLOOR (#6625: замер строки модели держит только
  // умолчание, рейкой можно ýже); верхняя — доля панели, та же, что у рейки.
  // С WF183 пол — по факту (переменная --myclaude-side-floor: строки полосы Рика и модели встают), нет её — SIDE_FLOOR.
  // С WF197 ширина человека — не больше своей доли сетки (--myclaude-side-share): окно ýже — колонка уступает.
  assert.ok(grid.body.includes(`clamp(var(--myclaude-side-floor, ${SIDE_FLOOR}px), min(var(${SIDE_VARIABLE}), var(--myclaude-side-share, 100%)), ${SIDE_MAX_SHARE * 100}%)`),
    "границы правой колонки в CSS — те же, что у рейки в JS");
  // Группы строки модели в широком виде не ужимаются: по их ширине считается
  // нижняя граница, и ужатая строка мерилась бы ужатой (граница застряла бы).
  // Правило — только в доке, куда смотрит и JS (chinRow → sideDock).
  // Колонка ýже замера (#6625) — панель помечена, и группам снова можно ужиматься.
  const chin = grid.children.find(item => item.selector === `.epitaxy-chat-panel:not([data-myclaude-side-tight]) & .group\\/approval-dock ${CHIN_ROW_SELECTOR} > *`);
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
  // Правила по атрибуту панели начинаются с неё самой (`.epitaxy-chat-panel[…] &`):
  // так они не зависят от того, сколько обёрток между панелью и колонкой (WF125).
  for (const kid of grid.children) {
    assert.ok(kid.selector.split(",").every(part => /^(\.epitaxy-chat-panel(\[[^\]]+\]|:not\(\[[^\]]+\]\)) )?&/.test(part.trim())),
      `правило «${kid.selector}» не вложено в условие сетки`);
  }
  // Опасные объявления — только внутри сетки: без неё margin-left:0 у шапки съел
  // бы место под кнопки окна.
  const loose = inside.filter(item => item !== grid && !grid.children.includes(item));
  for (const item of loose) {
    assert.ok(!/margin-left|padding-left|padding-top/.test(item.body), `«${item.selector}» меняет отступы вне сетки`);
  }
  const titlebar = grid.children.find(item => item.selector === "& > .epitaxy-titlebar");
  assert.ok(titlebar && /grid-column:\s*2/.test(titlebar.body) && /margin-left:\s*-\d+px !important/.test(titlebar.body),
    "шапка — правая колонка, без места под кнопки окна");
  const body = grid.children.find(item => item.selector === `& ${BODY_OLD}, & ${BODY_NEW}`);
  assert.ok(body && /grid-row:\s*1 \/ 3/.test(body.body) && /min-height:\s*0/.test(body.body),
    "лента — левая колонка на обе строки, min-height:0, в обеих формах разметки");
  // Шапка слева (полоса под кнопками окна) — лента во второй строке, тоже в обеих формах.
  const left = '.epitaxy-chat-panel[data-myclaude-title="left"] & ';
  const bodyLeft = grid.children.find(item => item.selector === `${left}${BODY_OLD}, ${left}${BODY_NEW}`);
  assert.ok(bodyLeft && /grid-row:\s*2 \/ 3/.test(bodyLeft.body), "шапка слева — лента во второй строке в обеих формах");
  // Шапка уезжает влево под кнопки окна по атрибуту, который ставит JS по положению
  // панели (примета data-top-left у шапки врёт при открытой боковой панели, гейт 16.09).
  const titleLeft = grid.children.find(item => item.selector.includes('[data-myclaude-title="left"]') && item.selector.endsWith("> .epitaxy-titlebar"));
  assert.ok(titleLeft && /grid-column:\s*1/.test(titleLeft.body), "шапка влево — по атрибуту от JS");
  // Хвост виртуальной ленты Claude (`transcript-spacer`) не трогаем никогда: его
  // высоту пишет сам Claude, и правило на неё ломало прокрутку (17.09, #6176).
  assert.ok(!layoutCss().includes("transcript-spacer"), "хвост виртуальной ленты Claude не трогаем");
  // WF66: вложения без потолка и прокрутки, текст без правого поля под кнопку.
  // #7336: вложения — над текстом, как у Claude (слот первый ребёнок коробки).
  const slot = grid.children.find(item => item.selector.endsWith("div:has(> [data-cds-composer-attachments])"));
  assert.ok(slot && !/order:/.test(slot.body), "слот вложений остаётся первым ребёнком коробки");
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
  // её в свою наследуемую, поле читает уже её. С 2.16120 (#8225) полей у доки нет
  // вовсе (они у колонки-обёртки) — тогда ноль, и поле отступает на все 12.
  assert.ok(/--myclaude-dock-pad-start:\s*var\(--chat-column-gutter-start, 0px\)/.test(dock.body), "дока отдаёт свой отступ наследуемой переменной");
  // С WF156 (#9148) отступ — переменная поля колонки (JS, по sidePadding), без неё — 12;
  // с WF163 (33.5) слева — своя переменная половины просвета, без неё — та же.
  assert.ok(prompt && /margin-inline:\s*calc\(var\(--myclaude-dock-inset-start, var\(--myclaude-dock-inset, 12px\)\) - var\(--myclaude-dock-pad-start\)\) calc\(var\(--myclaude-dock-inset, 12px\) - var\(--myclaude-dock-pad-end\)\)/.test(prompt.body),
    "поле ввода стоит в поле колонки от её краёв (без замера — 12)");
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
  // WF188: сторона — доля ряда (5 в ряд, зазор 4), потолок WIDE_TILE.
  const side = `clamp(32px, calc((100cqw - 16px) / 5), ${WIDE_TILE}px)`;
  assert.ok(tile && tile.body.includes(`width: ${side} !important`) && tile.body.includes(`height: ${side} !important`), "плитка вложений в колонке не ужата");
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
  assert.deepEqual(plain(bare.api.status().layout), { wide: false, panel: null, side: null, sideMin: null, gaps: null, justify: true });
  assert.equal(handle(bare).style.getPropertyValue("display"), "flex", "ручка видна");
  assert.equal(rail(bare).style.getPropertyValue("display"), "none", "рейки в узком виде нет");
  // Панель есть, флага нет — окно ýже порога: вид узкий, ширина панели известна.
  const narrow = open({ stand: { wide: false } });
  assert.deepEqual(plain(narrow.api.status().layout), { wide: false, panel: PANEL.width, side: null, sideMin: null, gaps: null, justify: true });
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
  assert.deepEqual(plain(loaded.api.status().layout), { wide: true, panel: PANEL.width, side: DOCK.width, sideMin: CHIN_MIN, gaps: plain(inner.wideGapsFor({ column: DOCK.left - PANEL.left })), justify: true });
  assert.equal(loaded.api.status().stage, NORMAL, "в широком виде ступень одна — обычная");
  assert.equal(loaded.win.sessionStorage.getItem(STAGE_KEY), String(COLLAPSED), "хранилище ступени не переписано");
  assert.equal(loaded.api.status().natural, null, "обычная высота в широком виде не меряется");
  assert.equal(loaded.parts.root.style.getPropertyValue(HEIGHT_VARIABLE), "", "подмены высоты нет");
  assert.equal(loaded.api.status().handleVisible, false, "ручки нет");
  const bar = rail(loaded);
  assert.equal(bar.style.getPropertyValue("display"), "block", "рейка видна");
  assert.equal(bar.style.getPropertyValue("left"), `${DOCK.left - 6}px`, "рейка стоит на левой кромке доки (12 точек, как у Claude, по центру кромки)");
  assert.equal(bar.style.getPropertyValue("top"), `${PANEL.top}px`);
  assert.equal(bar.style.getPropertyValue("height"), `${PANEL.height}px`, "во всю высоту панели");
  assert.equal(loaded.dom.queryAll(`#${RAIL_ID}`).length, 1, "узел один на окно");
  // Панель начинается на 200 — кнопок окна над лентой нет, шапка справа.
  assert.equal(loaded.parts.panel.getAttribute(TITLE_SIDE_ATTRIBUTE), null, "боковая панель открыта — шапка справа");
  // Панель у левого края окна: главное окно (#7913, WF102) шапку влево НЕ переносит —
  // она во второй колонке, лента во всю высоту, под кнопками окна — полоса для тяги.
  loaded.parts.panel.rect = { ...PANEL, left: 40 };
  settle(loaded);
  assert.equal(loaded.parts.panel.getAttribute(TITLE_SIDE_ATTRIBUTE), null, "главное окно: шапка остаётся справа");
  assert.deepEqual(plain(loaded.api.status().head), { main: true, headless: false, drag: true, titleSide: null, titleShift: null, titleEnd: null, titleFade: false });
  // Попап у левого края окна — шапка уезжает влево под кнопки окна, как было.
  const popup = open({ href: "about:blank" });
  popup.parts.panel.rect = { ...PANEL, left: 40 };
  settle(popup);
  assert.equal(popup.parts.panel.getAttribute(TITLE_SIDE_ATTRIBUTE), "left", "попап у края окна — шапка влево");
  assert.equal(popup.parts.panel.style.getPropertyValue("--myclaude-title-inset"), "68px", "отступ под кнопки окна попапа");
  assert.equal(popup.api.status().head.drag, false, "полоса для тяги — только у главного окна");
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
  // Колонка — дока без выезда влево (320 − 12 = 308). Захват без движения ширину не
  // меняет (WF176, #9182: раньше каждый захват прибавлял 12 — «размер сбился»).
  drag(DOCK.left, DOCK.left);
  assert.equal(panel.style.getPropertyValue(SIDE_VARIABLE), `${DOCK.width - 12}px`, "захват без движения — та же ширина");
  drop(DOCK.left);
  // Ширина = ширина на захвате + сдвиг курсора влево: 308 + 80.
  drag(DOCK.left, 700);
  assert.equal(bar.dataset.dragging, "true");
  assert.equal(loaded.document.documentElement.style.cursor, "col-resize");
  assert.equal(panel.style.getPropertyValue(SIDE_VARIABLE), "388px");
  assert.equal(loaded.win.localStorage.getItem(SIDE_KEY), "308", "пока тянут — в хранилище прежнее");
  drop(700);
  assert.equal(bar.dataset.dragging, "false");
  assert.equal(loaded.document.documentElement.style.cursor, "");
  assert.equal(loaded.win.localStorage.getItem(SIDE_KEY), "388", "отпустили — ширина в хранилище");
  // Перерисовка панели (смена чата, React пересобрал узел) ширину не сбрасывает.
  panel.style.removeProperty(SIDE_VARIABLE);
  settle(loaded);
  assert.equal(panel.style.getPropertyValue(SIDE_VARIABLE), "388px", "ширина из хранилища вернулась");
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

// ---- #9135, #9133 (WF148): шапка колонки и тени у поля -----------------------
test("#9135: шапка над полем — название чата заголовком, значок сдвигается правилом по атрибуту", () => {
  const grid = inside.find(item => /display:\s*grid/.test(item.body));
  const right = '.epitaxy-chat-panel:not([data-myclaude-title="left"]) & > .epitaxy-titlebar';
  const title = grid.children.find(item => item.selector === `${right} [data-pane-title]`);
  assert.ok(title, "правила заголовка шапки колонки нет");
  const size = Number(/font-size:\s*(\d+)px !important/.exec(title.body)?.[1]);
  // WF190 (слово Элвиса 09.10 03:50: шрифт чуть уменьшить — слишком большой и не влезает): 16/600,
  // как заголовок блока; имя проекта в углу над New остаётся 20.
  assert.equal(size, inner.TITLE_COLUMN_FONT);
  assert.equal(size, 16);
  assert.equal(inner.CORNER_SIDE_PROJECT_FONT, 20);
  assert.match(title.body, /font-weight:\s*600 !important/);
  assert.match(title.body, /letter-spacing:\s*-0\.01em/);
  // WF179 (#9206: «мониторчик держать в самом правом углу»): группа названия во всю строку, ячейка значка
  // Remote Control — последней, к правому краю.
  const group = grid.children.find(item => item.selector === `${right} > .group\\/lead`);
  assert.ok(group && /flex:\s*1 1 auto/.test(group.body), "группа названия не растянута на строку");
  const gutter = grid.children.find(item => item.selector === `${right} > .group\\/lead > :has(> [data-testid="epitaxy-origin-gutter"])`);
  assert.ok(gutter, "правила значка Remote Control нет");
  assert.match(gutter.body, /order:\s*2/);
  assert.match(gutter.body, /margin-inline-start:\s*auto !important/);
  assert.match(gutter.body, /justify-content:\s*flex-end/);
  const lead = grid.children.find(item => item.selector === `${right} > [data-myclaude-title-lead]`);
  assert.ok(lead && /margin-inline-start:\s*var\(--myclaude-title-shift, 0px\) !important/.test(lead.body),
    "сдвиг значка — переменной панели по атрибуту ребёнка шапки");
  // Шапка слева (попап у края окна) и узкое окно этих правил не получают.
  // WF185: снаружи — только скрытие плашки проекта по этому атрибуту, без сдвигов.
  assert.ok(!outside.some(item => item.selector.includes("data-myclaude-title-lead") && /margin|padding/.test(item.body)), "сдвиг вне широкого вида");
});

test("#9133: у миниатюр поля и доки тени мягкие и тёмные, кольца Claude внутри плитки погашены", () => {
  const grid = inside.find(item => /display:\s*grid/.test(item.body));
  const tile = grid.children.find(item => item.selector.endsWith("[data-cds-composer-attachments] [data-cds-attachment]"));
  const shadow = /box-shadow:\s*([^;]+?) !important/.exec(tile.body)?.[1] ?? "";
  assert.match(shadow, /^0 \d+px \d+px rgba\(0, 0, 0, 0\.\d+\)$/, `тень плитки не одна тёмная: «${shadow}»`);
  assert.ok(Number(/0\.(\d+)\)$/.exec(shadow)[1]) <= 12, "тень плитки ярче половины родной");
  assert.ok(Number(/^0 \d+px (\d+)px/.exec(shadow)[1]) >= 8, "радиус тени не мягкий");
  assert.match(tile.body, /border-color:\s*transparent !important/, "светлый ободок плитки остался");
  const inner = grid.children.find(item => item.selector.includes("[data-cds-attachment] *::after"));
  assert.ok(inner && /box-shadow:\s*none !important/.test(inner.body), "кольца внутри плитки не погашены");
  assert.ok(!/:is\([^)]*::/.test(css), "псевдоэлемент внутри :is() — правило браузер выкинет");
  const dock = grid.children.find(item => item.selector === "& .group\\/approval-dock");
  for (const name of ["--cds-ring-color", "--cds-shadow-sm", "--cds-shadow-md", "--cds-shadow-popover"]) {
    assert.match(dock.body, new RegExp(`${name}:\\s*(0 \\d+px \\d+px )?rgba\\(0, 0, 0, 0\\.\\d+\\)`), `${name} у доки не мягкий тёмный`);
  }
});

const titleStand = ({ wide = true } = {}) => dom => {
  const parts = panelStand({ wide })(dom);
  parts.lead = parts.titlebar.add("div", { class: "group/lead flex items-center", rect: { left: DOCK.left, top: 4, width: 200, height: 24 } });
  parts.icon = parts.lead.add("button", { attrs: { "aria-label": "Local" }, rect: { left: DOCK.left + 2, top: 4, width: 24, height: 24 } });
  parts.title = parts.lead.add("span").add("span", { attrs: { "data-pane-title": "" }, text: "Rick чат Элвиса", rect: { left: DOCK.left + 32, top: 8, width: 120, height: 16 } });
  return parts;
};

test("#9135: значок шапки — левым краем по тексту поля; проходы сходятся; узкий вид снимает сдвиг", () => {
  const loaded = loadInject({ html: titleStand(), title: "Trelvis" });
  assert.equal(loaded.error, null);
  const { panel, lead, icon, editor } = loaded.parts;
  const want = editor.rect.left - icon.rect.left;
  assert.equal(panel.style.getPropertyValue("--myclaude-title-shift"), `${want}px`, "сдвиг до линии текста поля");
  assert.ok(lead.hasAttribute("data-myclaude-title-lead"), "сдвигается ребёнок шапки со значком");
  assert.equal(loaded.api.status().head.titleShift, want);
  // Браузер применил сдвиг — значок встал на линию; следующий проход сдвиг не копит.
  icon.rect = { ...icon.rect, left: icon.rect.left + want };
  loaded.parts.title.rect = { ...loaded.parts.title.rect, left: loaded.parts.title.rect.left + want };
  settle(loaded); settle(loaded);
  assert.equal(panel.style.getPropertyValue("--myclaude-title-shift"), `${want}px`, "сдвиг копится от прохода к проходу");
  // Узкий вид — сдвига нет, атрибут снят.
  panel.computed = {};
  settle(loaded);
  assert.equal(panel.style.getPropertyValue("--myclaude-title-shift"), "");
  assert.ok(!lead.hasAttribute("data-myclaude-title-lead"));
  assert.equal(loaded.api.status().head.titleShift, null);
  // Попап у края окна (шапка слева, над лентой) — не выравниваем.
  const popup = loadInject({ html: titleStand(), title: "Trelvis", href: "about:blank" });
  popup.parts.panel.rect = { ...PANEL, left: 40 };
  settle(popup);
  assert.equal(popup.parts.panel.getAttribute(TITLE_SIDE_ATTRIBUTE), "left");
  assert.equal(popup.parts.panel.style.getPropertyValue("--myclaude-title-shift"), "");
  // dispose снимает и переменную, и атрибут.
  loaded.parts.panel.computed = { [WIDE_FLAG]: "1" };
  settle(loaded);
  assert.ok(lead.hasAttribute("data-myclaude-title-lead"));
  loaded.api.dispose();
  assert.equal(panel.style.getPropertyValue("--myclaude-title-shift"), "");
  assert.ok(!lead.hasAttribute("data-myclaude-title-lead"));
});

// WF179 (#9206): первым в шапке — название (значок CSS увёл вправо): по линии текста поля встаёт начало
// ТЕКСТА названия — у кнопки Claude поле внутри (mx-outset), его прибавляем.
test("WF179 (#9206): название первым — начало его текста по линии текста поля; значок справа сдвиг не трогает", () => {
  const stand = dom => {
    const parts = panelStand({ wide: true })(dom);
    parts.lead = parts.titlebar.add("div", { class: "group/lead flex items-center", rect: { left: DOCK.left, top: 4, width: 300, height: 24 } });
    const words = parts.lead.add("span", { rect: { left: DOCK.left, top: 4, width: 150, height: 24 } });
    parts.title = words.add("button", { attrs: { "data-pane-title": "" }, text: "Rick чат Элвиса", rect: { left: DOCK.left - 4, top: 6, width: 150, height: 22 } });
    parts.title.computed = { ...parts.title.computed, "padding-left": "4px" };
    const cell = parts.lead.add("span", { rect: { left: DOCK.left + 270, top: 4, width: 30, height: 24 } });
    parts.icon = cell.add("button", { attrs: { "data-testid": "epitaxy-origin-gutter", "aria-label": "Remote Control" }, rect: { left: DOCK.left + 277, top: 4, width: 23, height: 23 } });
    return parts;
  };
  const loaded = loadInject({ html: stand, title: "Trelvis" });
  assert.equal(loaded.error, null);
  const { panel, lead, editor } = loaded.parts;
  const want = editor.rect.left - DOCK.left;
  assert.equal(panel.style.getPropertyValue("--myclaude-title-shift"), `${want}px`, "текст названия не на линии поля");
  assert.ok(lead.hasAttribute("data-myclaude-title-lead"));
  assert.ok(want <= inner.TITLE_SHIFT_MAX, "сдвиг упёрся в потолок");
});

test("#9148 (WF156): поля правой колонки — из «Поля» (sidePadding по полю ленты), до 40; 41 — зажим, меньше 12 — 12", () => {
  const { dockInsetFor, DOCK_INSET_MAX, DOCK_INSET_VARIABLE } = inner;
  assert.equal(DOCK_INSET_MAX, 40);
  assert.deepEqual([0, 5, 12, 16, 24, 32, 40, 41, 48, NaN, "мусор"].map(dockInsetFor), [12, 12, 12, 16, 24, 32, 40, 40, 40, 12, 12]);
  const loaded = open();
  assert.equal(loaded.error, null);
  const panel = loaded.parts.panel;
  // Поля ленты не нашлось — прежние 12.
  assert.equal(panel.style.getPropertyValue(DOCK_INSET_VARIABLE), "12px");
  const source = loaded.parts.panelBody.add("div", { class: "epitaxy-transcript-width", computed: { "padding-left": "40px" } });
  settle(loaded);
  assert.equal(panel.style.getPropertyValue(DOCK_INSET_VARIABLE), "40px", "40 принимается");
  source.computed = { "padding-left": "41px" };
  settle(loaded);
  assert.equal(panel.style.getPropertyValue(DOCK_INSET_VARIABLE), "40px", "41 зажат до 40");
  source.computed = { "padding-left": "24px" };
  settle(loaded);
  assert.equal(panel.style.getPropertyValue(DOCK_INSET_VARIABLE), "24px");
  // Узкий вид — переменная снята, поле ввода как в узком окне.
  panel.computed = {};
  settle(loaded);
  assert.equal(panel.style.getPropertyValue(DOCK_INSET_VARIABLE), "");
});

// ---- #9148, WF163: вариант 33.5 — три столбика с равными просветами ----------
// Геометрия считается по формуле wideGapsFor и проверяется краями колонок: текст
// ленты = левая кромка тела + feedStart + p … правая кромка тела − 2 − feedEnd − p;
// линия колонки = правая кромка тела − 12; коробка поля = линия + dockStart …
// правая кромка окна − dockEnd.
const edges = ({ body, menuRight, windowRight, pad, gaps }) => {
  const textLeft = body.left + gaps.feedStart + pad;
  const textRight = body.left + body.width - 2 - gaps.feedEnd - pad;
  const line = body.left + body.width - 12;
  const boxLeft = line + gaps.dockStart;
  const boxRight = windowRight - gaps.dockEnd;
  return { menuToText: textLeft - menuRight, feed: textRight - textLeft, textToBox: boxLeft - textRight, edge: windowRight - boxRight, scroll: line - textRight };
};

test("#9148 (33.5): окно 1600 с меню — просветы меню→лента 80, лента→поле 80, край 24", () => {
  const { wideGapsFor, FEED_MIN } = inner;
  assert.equal(FEED_MIN, 520);
  // Окно Рика: меню до 338 (пункты до 330), тело ленты 347…1180 (колонка поля 420), окно 1600.
  const body = { left: 347, width: 833 };
  const gaps = wideGapsFor({ pad: 24, column: body.width, menuGap: body.left - 330 });
  assert.deepEqual(plain(gaps), { edge: 24, gap: 80, share: 1, feedStart: 39, feedEnd: 26, dockStart: 40, dockEnd: 24 });
  const e = edges({ body, menuRight: 330, windowRight: 1600, pad: 24, gaps });
  assert.equal(e.menuToText, 80, "от пунктов меню до текста ленты");
  assert.equal(e.textToBox, 80, "от текста ленты до поля ввода");
  assert.equal(e.edge, 24, "у края окна — поле 24");
  assert.equal(e.scroll, 40, "линия колонки — ровно посередине просвета");
  assert.ok(e.feed >= FEED_MIN, `лента ${e.feed} не уже 520`);
});

test("#9148 (33.5): «Поля» двигают просвет (2p + 32), узкое широкое окно ужимает его, лента не уже 520", () => {
  const { wideGapsFor } = inner;
  // Поля 40: край 40, просвет 112.
  const big = wideGapsFor({ pad: 40, column: 900, menuGap: 17 });
  assert.equal(big.edge, 40);
  assert.equal(big.gap, 112);
  assert.equal(edges({ body: { left: 347, width: 900 }, menuRight: 330, windowRight: 1700, pad: 40, gaps: big }).textToBox, 112);
  // Поля 12 — просвет 56.
  assert.equal(wideGapsFor({ pad: 12, column: 900, menuGap: 17 }).gap, 56);
  // Ужатие: тело 610 — лента без прибавки 560, прибавки 65 → доля 40/65.
  const tight = wideGapsFor({ pad: 24, column: 610, menuGap: 17 });
  assert.equal(tight.share, 0.62);
  assert.deepEqual([tight.feedStart, tight.feedEnd, tight.dockStart, tight.dockEnd], [24, 16, 34, 24]);
  const e = edges({ body: { left: 347, width: 610 }, menuRight: 330, windowRight: 1300, pad: 24, gaps: tight });
  assert.equal(e.feed, 520, "лента ровно 520 — дальше просветы не растут");
  assert.ok(Math.abs(e.menuToText - e.textToBox) <= 8, `просветы ужаты одной долей: ${e.menuToText} и ${e.textToBox}`);
  // Совсем узко — всё как в WF156: прибавки нет, поле ввода с отступом p.
  assert.deepEqual(plain(wideGapsFor({ pad: 24, column: 420, menuGap: 17 })), { edge: 24, gap: 80, share: 0, feedStart: 0, feedEnd: 0, dockStart: 24, dockEnd: 24 });
  // Меню нет (попап, панель свёрнута): слева край окна — поле p, без прибавки.
  assert.equal(wideGapsFor({ pad: 24, column: 900, menuGap: null }).feedStart, 0);
  // Ширины нет — как WF156.
  assert.equal(wideGapsFor({ pad: 24 }).share, 0);
});

test("#9148 (33.5): страница кладёт просветы на панель по ряду ленты и меню; узкий вид и dispose — снимают", () => {
  const loaded = loadInject({
    html: dom => {
      const aside = dom.document.body.add("aside", { class: "dframe-sidebar", rect: { left: 0, top: 0, width: 190, height: 800 } });
      const parts = panelStand()(dom);
      return { ...parts, aside };
    },
    title: "Trelvis",
  });
  assert.equal(loaded.error, null);
  const panel = loaded.parts.panel;
  // Ряд Claude 2.26454: поле 24 у [data-transcript-column-row] (.epitaxy-transcript-width нет).
  loaded.parts.panelBody.add("div", { attrs: { "data-transcript-column-row": "" }, computed: { "padding-left": "24px" } });
  settle(loaded);
  // Тело 200…780 (580), пункты меню до 182: menuGap 18 → полная прибавка 38 + 26 = 64, запас 580−50−520 = 10.
  const gaps = wideGapsFor_({ pad: 24, column: 580, menuGap: 18 });
  assert.equal(panel.style.getPropertyValue("--myclaude-dock-inset"), "24px", "правый край поля — p");
  assert.equal(panel.style.getPropertyValue("--myclaude-dock-inset-start"), `${gaps.dockStart}px`);
  assert.equal(panel.style.getPropertyValue("--myclaude-feed-start"), `${gaps.feedStart}px`);
  assert.equal(panel.style.getPropertyValue("--myclaude-feed-end"), `${gaps.feedEnd}px`);
  assert.deepEqual(plain(loaded.api.status().layout.gaps), plain(gaps));
  loaded.parts.panel.computed = {};
  settle(loaded);
  for (const name of ["--myclaude-dock-inset", "--myclaude-dock-inset-start", "--myclaude-feed-start", "--myclaude-feed-end"]) {
    assert.equal(panel.style.getPropertyValue(name), "", `узкий вид: ${name} снят`);
  }
  assert.equal(loaded.api.status().layout.gaps, null);
  loaded.parts.panel.computed = { [WIDE_FLAG]: "1" };
  settle(loaded);
  assert.ok(panel.style.getPropertyValue("--myclaude-feed-end"));
  loaded.api.dispose();
  assert.equal(panel.style.getPropertyValue("--myclaude-feed-end"), "", "dispose снимает просветы");
});
const wideGapsFor_ = args => inner.wideGapsFor(args);

test("#9148 (33.5): CSS — ряды ленты margin'ами между просветами, поле ввода — свой отступ слева", () => {
  const rows = inside.filter(item => item.selector.includes("[data-transcript-column-row]"));
  assert.ok(rows.length, "правила рядов ленты в широком виде нет");
  const row = rows[0];
  assert.match(row.body, /max-width:\s*none\s*!important/);
  assert.match(row.body, /margin-left:\s*var\(--myclaude-feed-start,\s*0px\)\s*!important/);
  assert.match(row.body, /margin-right:\s*var\(--myclaude-feed-end,\s*0px\)\s*!important/);
  assert.ok(row.selector.includes(".epitaxy-transcript-width:not([data-transcript-column-row] *)"), "прежние сборки — тоже");
  assert.ok(row.selector.includes("[data-transcript-column-row]:not([data-transcript-column-row] *)"), "вложенный ряд не получает прибавку дважды");
  assert.ok(!outside.some(item => item.body.includes("--myclaude-feed-")), "в узком виде поля ленты прежние");
  const prompt = inside.find(item => /& \.epitaxy-prompt$/.test(item.selector));
  assert.match(prompt.body, /margin-inline:\s*calc\(var\(--myclaude-dock-inset-start,\s*var\(--myclaude-dock-inset,\s*12px\)\)/);
});

test("#9148 (33.5): по ширине с переносами — абзацы ленты в обоих видах (поле — влево); заголовки, списки, таблицы, код — влево", () => {
  const just = outside.filter(item => /text-align:\s*justify/.test(item.body));
  assert.equal(just.length, 1, "одно правило выключки, вне @container");
  const rule = just[0];
  assert.match(rule.body, /(^|;)\s*hyphens:\s*auto/);
  assert.match(rule.body, /-webkit-hyphens:\s*auto/);
  assert.match(rule.body, /hyphenate-limit-chars:\s*6 2 2/, "одну букву не отрываем");
  const selectors = rule.selector.split(/,\s*(?![^()]*\))/).map(item => item.trim());
  assert.deepEqual(selectors, [
    // #9168 (WF165): выключка переключаемая — правило не совпадает при data-myclaude-justify="off".
    'html:not([data-myclaude-justify="off"]) .epitaxy-chat-panel [data-cds="Prose"] p:not(:is(li, td, th, pre) p)',
  ]); // поле ввода — влево (09.10: в колонке ~200 px выключка давала дыры между словами)
  for (const tag of ["h1", "h2", "h3", "ul", "ol", "pre", "code", "table"]) {
    assert.ok(!selectors.some(item => new RegExp(`\\b${tag}\\b(?![^(]*\\))`).test(item.replace(/:not\(.*\)$/, ""))), `${tag} не по ширине`);
  }
  assert.ok(!/text-wrap:\s*pretty/.test(css), "text-wrap: pretty ломает переносы — не ставим");
  assert.ok(!inside.some(item => /text-align:\s*justify/.test(item.body)), "выключка не только в широком виде");
});

test("#9148 (33.5): lang=\"ru\" на панели у английской страницы — для переносов; русская страница и свой lang — не трогаем", () => {
  const loaded = open();
  assert.equal(loaded.error, null);
  loaded.dom.document.documentElement.setAttribute("lang", "en-US");
  settle(loaded);
  assert.equal(loaded.parts.panel.getAttribute("lang"), "ru");
  // Узкий вид — тоже: выключка в обоих видах.
  loaded.parts.panel.computed = {};
  settle(loaded);
  assert.equal(loaded.parts.panel.getAttribute("lang"), "ru");
  loaded.api.dispose();
  assert.equal(loaded.parts.panel.getAttribute("lang"), null, "dispose снимает свой lang");
  const ru = loadInject({ html: dom => { dom.document.documentElement.setAttribute("lang", "ru"); return panelStand()(dom); }, title: "Trelvis" });
  settle(ru);
  assert.equal(ru.parts.panel.getAttribute("lang"), null, "страница уже русская");
  const own = loadInject({ html: dom => { const parts = panelStand()(dom); parts.panel.setAttribute("lang", "de"); return parts; }, title: "Trelvis" });
  settle(own);
  assert.equal(own.parts.panel.getAttribute("lang"), "de", "свой lang панели не перебиваем");
});

// ---- WF185 (#9206): шапка колонки — название до значка, без «…», значок по правому краю поля -------
// Слово Элвиса 09.10 03:20: многоточие не нужно, справа ещё много места; «Мониторчик — к самому
// краю, как по выравниванию, отступ от правого края как у всех».
test("WF185 (#9206): название не влезло — затухание хвоста, влезло — без него; многоточия нет", () => {
  const grid = inside.find(item => /display:\s*grid/.test(item.body));
  const right = '.epitaxy-chat-panel:not([data-myclaude-title="left"]) & > .epitaxy-titlebar';
  const clip = grid.children.find(item => item.selector === `${right} [data-pane-title]` && /text-overflow/.test(item.body));
  assert.ok(clip && /text-overflow:\s*clip !important/.test(clip.body), "многоточие Claude (truncate) не снято");
  const fade = grid.children.find(item => item.selector === `${right} [data-pane-title][data-myclaude-title-fade]`);
  assert.ok(fade, "правила затухания по метке нет");
  assert.ok(fade.body.includes(`mask-image: ${inner.FADE_END_MASK}`), "затухание не как у строк списка слева");
  // Невидимая плашка проекта (имя проекта в углу) места не держит — только в шапке колонки (по метке группы).
  const pill = outside.find(item => item.selector.includes("[data-myclaude-title-lead]") && item.selector.includes("epitaxy-origin-label"));
  assert.ok(pill && /display:\s*none !important/.test(pill.body), "плашка проекта держит место у названия");
  assert.ok(pill.selector.startsWith("html[data-myclaude-corner]"), "плашку прячем, только когда имя проекта видно в углу");

  const stand = dom => {
    const parts = panelStand({ wide: true })(dom);
    parts.lead = parts.titlebar.add("div", { class: "group/lead flex items-center", rect: { left: DOCK.left, top: 4, width: 300, height: 24 } });
    parts.title = parts.lead.add("span").add("button", { attrs: { "data-pane-title": "" }, text: "Ночной режим Rick с бюджетом", rect: { left: DOCK.left + 10, top: 6, width: 200, height: 22 } });
    parts.icon = parts.lead.add("span").add("button", { attrs: { "data-testid": "epitaxy-origin-gutter", "aria-label": "Remote Control" }, rect: { left: 1090, top: 4, width: 24, height: 24 } });
    return parts;
  };
  const loaded = loadInject({ html: stand, title: "Trelvis" });
  assert.equal(loaded.error, null);
  const { title } = loaded.parts;
  title.scrollWidth = 200;
  title.clientWidth = 200;
  settle(loaded);
  assert.ok(!title.hasAttribute("data-myclaude-title-fade"), "влезло — без затухания");
  assert.equal(loaded.api.status().head.titleFade, false);
  title.scrollWidth = 290;
  settle(loaded);
  assert.ok(title.hasAttribute("data-myclaude-title-fade"), "не влезло — хвост затухает");
  assert.equal(loaded.api.status().head.titleFade, true);
  title.scrollWidth = 200;
  settle(loaded);
  assert.ok(!title.hasAttribute("data-myclaude-title-fade"), "снова влезло — метка снята");
  loaded.api.dispose();
  assert.ok(!title.hasAttribute("data-myclaude-title-fade"));
});

test("WF185 (#9206): значок Remote Control — правым краем по правому краю поля ввода; проходы сходятся", () => {
  const stand = dom => {
    const parts = panelStand({ wide: true })(dom);
    // Коробка поля Claude — ChatComposer (замер 09.10: поле 941, значок 961 при окне 973).
    parts.block.setAttribute("data-cds", "ChatComposer");
    parts.lead = parts.titlebar.add("div", { class: "group/lead flex items-center", rect: { left: DOCK.left, top: 4, width: 330, height: 24 } });
    parts.title = parts.lead.add("span").add("button", { attrs: { "data-pane-title": "" }, text: "Rick", rect: { left: DOCK.left + 10, top: 6, width: 60, height: 22 } });
    parts.icon = parts.lead.add("span").add("button", { attrs: { "data-testid": "epitaxy-origin-gutter", "aria-label": "Remote Control" }, rect: { left: 1090, top: 4, width: 24, height: 24 } });
    return parts;
  };
  const loaded = loadInject({ html: stand, title: "Trelvis" });
  assert.equal(loaded.error, null);
  const { panel, icon, block } = loaded.parts;
  const want = icon.rect.left + icon.rect.width - (block.rect.left + block.rect.width);
  assert.equal(want, 26);
  assert.equal(panel.style.getPropertyValue("--myclaude-title-end"), `${want}px`, "значок не по краю поля");
  assert.equal(loaded.api.status().head.titleEnd, want);
  // Браузер применил отступ — значок на линии; следующий проход отступ не копит.
  icon.rect = { ...icon.rect, left: icon.rect.left - want };
  settle(loaded); settle(loaded);
  assert.equal(panel.style.getPropertyValue("--myclaude-title-end"), `${want}px`, "отступ копится от прохода к проходу");
  // Правило: ячейка значка отступает справа на эту переменную.
  const grid = inside.find(item => /display:\s*grid/.test(item.body));
  const gutter = grid.children.find(item => item.selector.endsWith('> .group\\/lead > :has(> [data-testid="epitaxy-origin-gutter"])'));
  assert.match(gutter.body, /margin-inline-end:\s*var\(--myclaude-title-end, 0px\) !important/);
  // Узкий вид — снято.
  panel.computed = {};
  settle(loaded);
  assert.equal(panel.style.getPropertyValue("--myclaude-title-end"), "");
  assert.equal(loaded.api.status().head.titleEnd, null);
});

// WF183 (слово Элвиса 09.10 03:15: «Не давай уменьшать правую панель меньше, чем можно. Когда правую панель
// сдвигаю — пропадает кругляшок с токенами, ему нельзя пропадать»): пол колонки — по факту короткой строки
// модели с кружком (запас между группами минус вылет, плюс 4); тяга рейки и clamp сетки в него упираются.
test("WF183: пол колонки по строке модели с кружком токенов — рейка ýже не уводит", () => {
  const loaded = open();
  const { panel, chinRight } = loaded.parts;
  settle(loaded);
  assert.equal(panel.style.getPropertyValue("--myclaude-side-floor"), "", "без кружка пола по строке нет");
  // Правая группа с кружком вылезла за край строки (1088) на 2 — строка тесная, подписи коротко.
  chinRight.rect = { ...chinRight.rect, left: 953, width: 137 };
  chinRight.add("button", { attrs: { "aria-haspopup": "dialog", "aria-label": "Usage: Context 10k / 1M (1%)" }, rect: { left: 1070, top: 770, width: 20, height: 20 } });
  settle(loaded); settle(loaded);
  assert.ok(loaded.parts.modelRow.hasAttribute("data-myclaude-chin-narrow"), "строка не тесная");
  // Стенд: колонка 308, запас между группами 56 (897 → 953) минус вылет 2 — пол 308 + 4 − 54 = 258.
  const floor = panel.style.getPropertyValue("--myclaude-side-floor");
  assert.equal(floor, "258px");
  const bar = rail(loaded);
  bar.dispatchEvent({ type: "pointerdown", button: 0, clientX: DOCK.left, pointerId: 1 });
  loaded.document.dispatchEvent({ type: "pointermove", clientX: 1090, pointerId: 1 });
  loaded.document.dispatchEvent({ type: "pointerup", clientX: 1090, pointerId: 1 });
  assert.equal(panel.style.getPropertyValue(SIDE_VARIABLE), floor, "тяга ушла ниже пола по факту");
  // Узкий вид — пола нет.
  loaded.dispose?.();
});

// ---- WF197 (#9291): колонка уступает при узком окне, минимум — без распорки ------------------------
// Слово Элвиса 09.10 04:22: «Она больше не сжимается. Она супер широкая стала. Сделай, чтоб она сжималась».
const SHARE_VARIABLE = "--myclaude-side-share";
const SHARE_KEY = "myclaude-wide-side-share-v1";
// Ширина колонки так, как её решит сетка: clamp(пол, min(ширина, доля сетки), 60 % сетки).
const column = (panel, grid) => {
  const floor = Number.parseFloat(panel.style.getPropertyValue("--myclaude-side-floor")) || SIDE_FLOOR;
  const side = Number.parseFloat(panel.style.getPropertyValue(SIDE_VARIABLE));
  const share = (Number.parseFloat(panel.style.getPropertyValue(SHARE_VARIABLE)) || 100) / 100;
  return Math.max(floor, Math.min(Math.min(side, share * grid), SIDE_MAX_SHARE * grid));
};

test("WF197: распорка строки модели (flex-grow) в минимум колонки не входит — минимум по группам", () => {
  const loaded = open();
  const { panel, chinRow } = loaded.parts;
  // Распорка Claude между группами (flex-1 basis-0, без кнопок) растянута на всё свободное место строки.
  chinRow.add("span", { class: "flex min-w-0 flex-1 basis-0", rect: { left: 897, top: 770, width: 150, height: 0 }, computed: { "flex-grow": "1" } });
  settle(loaded);
  assert.equal(panel.style.getPropertyValue(SIDE_MIN_VARIABLE), `${CHIN_MIN}px`, "минимум — натуральные группы, не рамка распорки");
  assert.equal(loaded.api.status().layout.sideMin, CHIN_MIN);
});

test("WF197: ширина человека — с долей сетки: окно ýже — колонка уступает той же долей, шире — возвращается", () => {
  const loaded = open();
  settle(loaded);
  const { panel } = loaded.parts;
  const bar = rail(loaded);
  bar.dispatchEvent({ type: "pointerdown", button: 0, clientX: DOCK.left, pointerId: 1 });
  loaded.document.dispatchEvent({ type: "pointermove", clientX: 700, pointerId: 1 });
  loaded.document.dispatchEvent({ type: "pointerup", clientX: 700, pointerId: 1 });
  assert.equal(panel.style.getPropertyValue(SIDE_VARIABLE), "388px");
  // Доля — от сетки (родитель шапки, 900): 388 / 900.
  assert.equal(panel.style.getPropertyValue(SHARE_VARIABLE), "43.11%");
  assert.equal(loaded.win.localStorage.getItem(SHARE_KEY), "0.4311");
  assert.equal(Math.round(column(panel, 900)), 388, "окно как при тяге — ширина человека");
  assert.equal(Math.round(column(panel, 700)), 302, "окно ýже — колонка уступает долей");
  assert.equal(Math.round(column(panel, 500)), SIDE_FLOOR, "ещё ýже — до пола, не ниже");
  assert.equal(Math.round(column(panel, 1400)), 388, "окно шире — снова ширина человека, не шире");
  // Двойной клик — умолчание: ни ширины, ни доли.
  bar.dispatchEvent({ type: "dblclick" });
  assert.equal(panel.style.getPropertyValue(SHARE_VARIABLE), "");
  assert.equal(loaded.win.localStorage.getItem(SHARE_KEY), null);
});

test("WF197: ширина из хранилища без доли (выбрана до WF197) — доля берётся от нынешней сетки и запоминается", () => {
  const loaded = open({ storage: { local: { [SIDE_KEY]: "360" } } });
  const { panel } = loaded.parts;
  assert.equal(panel.style.getPropertyValue(SIDE_VARIABLE), "360px");
  assert.equal(panel.style.getPropertyValue(SHARE_VARIABLE), "40%");
  assert.equal(loaded.win.localStorage.getItem(SHARE_KEY), "0.4");
  const kept = open({ storage: { local: { [SIDE_KEY]: "360", [SHARE_KEY]: "0.3" } } });
  assert.equal(kept.parts.panel.style.getPropertyValue(SHARE_VARIABLE), "30%", "своя доля из хранилища");
  kept.api.dispose();
  assert.equal(kept.parts.panel.style.getPropertyValue(SHARE_VARIABLE), "", "dispose снимает долю");
});
