// Ручка над полем ввода: ступени, сворачивание и высота (разделы 6, 7 и 10
// inject.js). Набора не было вовсе — самая старая и самая частая возможность
// продукта жила без единой проверки, и ревизия 08.09 (#5757) подсунула ей
// четыре настоящие ошибки, ни одну из которых гейт не заметил:
//   1) setStage без зажима — ступень уезжает за края;
//   2) setStage без storeStage — ступень не переживает перезапись файла;
//   3) высота мимо clampHeight — поле выше окна;
//   4) collapseTargets отдаёт блок целиком — вместе с полем уезжает строка
//      модели, низ окна становится чёрной полосой, и вернуть поле мышью нечем
//      (ровно то, от чего предостерегает комментарий в разделе 6).
// Здесь проверяются ровно эти четыре места и ничего сверх. Вторым набором, в
// конце файла, — четыре жалобы Элвиса 12.09 на низ окна (WF57).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner } from "./load.mjs";

const BLOCK_ATTRIBUTE = "data-myclaude-composer-block";
const HEIGHT_VARIABLE = "--myclaude-input-height";
const STAGE_KEY = "myclaude-input-stage-v1";
const COLLAPSED = 0;
const NORMAL = 1;
const STRETCHED = 2;

// Низ окна Claude Code целиком: плашка проекта над рамкой поля, сама рамка и
// строка модели под ней. Плашка нужна нарочно — без неё в списке сворачивания
// оказался бы один узел, и «блок целиком» от «рамки с тем, что над ней» было бы
// не отличить.
const composerStand = dom => {
  const parts = dom.composer({ top: 620 });
  const chip = dom.node("div");
  chip.className = "project-chip";
  chip.rect = { left: 100, top: 596, width: 1000, height: 22 };
  parts.block.insertBefore(chip, parts.shell);
  return { ...parts, chip };
};
// Тот же низ, но без строки модели: разбор не удался, и остаётся запасной путь.
const noModelRowStand = dom => {
  const block = dom.document.body.add("div", {
    class: "epitaxy-composer-width", rect: { left: 100, top: 620, width: 1000, height: 130 },
  });
  const shell = block.add("div", {
    class: "epitaxy-prompt", rect: { left: 100, top: 620, width: 1000, height: 120 },
    computed: { borderTopLeftRadius: "10px" },
  });
  const root = shell.add("div", {
    class: "editor-root", rect: { left: 110, top: 630, width: 980, height: 100 },
    computed: { overflowY: "auto" },
  });
  const editor = root.add("div", {
    class: "ProseMirror", attrs: { contenteditable: "true" },
    rect: { left: 110, top: 630, width: 980, height: 100 },
  });
  return { block, shell, root, editor };
};
// Низ окна в сборке Claude от 12.09.2026: .epitaxy-prompt держит уже не рамку
// поля, а ВЕСЬ низ — рамку и строку модели под ней (замер в живом окне, #5857).
// Внутри рамки, кроме поля, стоит полоса вложений: из-за неё прежний разбор
// отдавал рамкой сам .epitaxy-prompt, блок ввода совпадал с рамкой, сворачивать
// становилось нечего — и одинарный клик переставал сворачивать поле вовсе.
// Геометрия — с замера живого окна 12.09: рамка обведена (по обводке её и
// находит полоса прогресса), строка модели стоит вплотную под ней, а кнопка
// Claude «вниз к последнему сообщению» висит НАД строкой модели отдельным
// слоем — position:absolute, z-index:1, вне .epitaxy-prompt. Свёрнутая полоска
// стояла ровно на этой кнопке (#5866, #5867).
const newBuildStand = ({ left = 100, width = 1000, editorWidth = null, scrollButtonTop = 714 } = {}) => dom => {
  const inner = editorWidth ?? width - 20;
  const prompt = dom.document.body.add("div", {
    class: "epitaxy-prompt", rect: { left, top: 500, width, height: 260 },
  });
  const block = prompt.add("div", {
    class: "flex w-full min-w-0 flex-col font-sans", rect: { left, top: 500, width, height: 260 },
  });
  const shell = block.add("div", {
    class: "bg-surface-3", rect: { left, top: 500, width, height: 238 },
    computed: { borderBottomWidth: "1px" },
  });
  const files = shell.add("div", {
    class: "attachments", rect: { left, top: 500, width, height: 60 },
  });
  const root = shell.add("div", {
    class: "editor-root", rect: { left: left + 10, top: 566, width: inner, height: 150 },
    computed: { overflowY: "auto" },
  });
  const editor = root.add("div", {
    class: "ProseMirror", attrs: { contenteditable: "true" },
    rect: { left: left + 10, top: 566, width: inner, height: 150 },
  });
  const modelRow = block.add("div", {
    class: "model-row", rect: { left, top: 738, width, height: 22 },
  });
  const scrollButton = dom.document.body.add("button", {
    attrs: { "aria-label": "Scroll to bottom" },
    rect: { left: left + width / 2 - 16, top: scrollButtonTop, width: 32, height: 24 },
    computed: { position: "absolute", zIndex: "1" },
  });
  return { prompt, block, shell, files, root, editor, modelRow, scrollButton };
};
const open = (options = {}) => loadInject({ html: composerStand, title: "Trelvis", ...options });
const collapsed = node => node.getAttribute(BLOCK_ATTRIBUTE);
// Зона захвата полоски (высота в CSS) — по ней считается, где идёт сама линия:
// зона стоит верхом на кромке, линия — ровно посередине зоны.
const HANDLE_HEIGHT = 18;
// Высота самой полосы прогресса — столько же, сколько в inject.js: по ней видно,
// что линия полоски и линия полосы не сливаются в одну.
const PROGRESS_BAR_HEIGHT = 2;
const box = node => node.getBoundingClientRect();
const handleOf = loaded => loaded.dom.query("#myclaude-input-handle");
const handleTop = loaded => parseFloat(handleOf(loaded).style.top);
const handleLine = loaded => handleTop(loaded) + HANDLE_HEIGHT / 2;
const barTop = loaded => parseFloat(loaded.dom.query("#myclaude-progress-bar").style.top);
// Зазор между кромкой рамки и линией полосы (WF65, #6178) — из люка, не дублируем число.
const { PROGRESS_GAP } = loadInner({ title: "Trelvis" }).inner;
// Одиночный клик шагает не сразу: 260 мс он ждёт возможного второго. Таймеры в
// стабе сами не идут — дёргаем ровно тот, что поставил этот клик.
const clickHandle = loaded => {
  const before = new Set(loaded.dom.ids("timeout"));
  handleOf(loaded).dispatchEvent({ type: "click", detail: 1 });
  const id = loaded.dom.ids("timeout").find(item => !before.has(item));
  assert.ok(id, "клик поставил отложенный шаг");
  loaded.dom.fire(id);
};
// Тяга за полоску: нажали на ней, провели указателем, отпустили.
const dragHandle = (loaded, from, to) => {
  handleOf(loaded).dispatchEvent({ type: "pointerdown", button: 0, clientY: from, pointerId: 1 });
  loaded.document.dispatchEvent({ type: "pointermove", clientY: to, pointerId: 1 });
  loaded.document.dispatchEvent({ type: "pointerup", clientY: to, pointerId: 1 });
};
// Лента разговора: прокручиваемый высокий блок БЕЗ примет Claude — полоска
// обязана находить его по факту, а не по классам.
// Лента разговора — та самая, которую ищет findScroller: виртуальная лента
// Claude со своей приметой. Своего обхода «самый высокий прокручиваемый узел» у
// нас больше нет: в главном окне он держался в восьми точках от боковой панели
// со списком чатов (находка проверяющего 12.09).
const addTranscript = (loaded, { scrollTop }) => {
  const tail = loaded.document.body.add("div", {
    class: "some-generated-class",
    attrs: { "data-testid": "epitaxy-virtual-transcript" },
    rect: { left: 0, top: 0, width: 1200, height: 500 },
    computed: { overflowY: "auto" },
  });
  tail.clientHeight = 500;
  tail.scrollHeight = 900;
  tail.scrollTop = scrollTop;
  return tail;
};

test("низ окна разобран: рамка, плашка над ней и строка модели", () => {
  const loaded = open();
  const status = loaded.api.status();
  assert.equal(status.stage, NORMAL, "новое окно открывается обычной высотой");
  assert.equal(status.shell, true);
  assert.equal(status.composerBlock, true);
  assert.equal(status.modelRow, true, "строка модели найдена — работает основной путь, а не запасной");
  assert.equal(status.handleVisible, true, "ручка над полем показана");
});

test("ступень зажата краями: выше «растянуто» и ниже «свёрнуто» её не бывает", () => {
  const loaded = open();
  loaded.api.setStage(9);
  assert.equal(loaded.api.status().stage, STRETCHED, "девятой ступени нет — упёрлись в «растянуто»");
  loaded.api.setStage(-4);
  assert.equal(loaded.api.status().stage, COLLAPSED, "минусовой ступени нет — упёрлись в «свёрнуто»");
  // За края уезжает не только рука на гейте: ступень двигают и тяга, и клики, и
  // команды снаружи, а ступени выше «растянуто» поле уже не соответствует.
  assert.equal(loaded.win.sessionStorage.getItem(STAGE_KEY), String(COLLAPSED), "в сессию легла зажатая ступень");
});

test("ступень записывается в сессию окна и оттуда же поднимается", () => {
  const loaded = open();
  assert.equal(loaded.win.sessionStorage.getItem(STAGE_KEY), String(NORMAL), "стартовая ступень записана сразу");
  loaded.api.setStage(COLLAPSED);
  assert.equal(loaded.win.sessionStorage.getItem(STAGE_KEY), String(COLLAPSED), "свернули — запомнили");
  loaded.api.setStage(STRETCHED, { height: 300 });
  assert.equal(loaded.win.sessionStorage.getItem(STAGE_KEY), String(STRETCHED), "растянули — запомнили");
  // Лоадер перечитывает inject.js по mtime и гоняет его в том же окне снова:
  // без записи ступень возвращалась бы к обычной на каждой правке файла.
  const again = open({ storage: { session: { [STAGE_KEY]: String(COLLAPSED) } } });
  assert.equal(again.api.status().stage, COLLAPSED, "окно поднялось свёрнутым");
  assert.equal(again.api.status().collapsedNodes, 2, "и поле сразу свёрнуто, а не только помечено");
});

test("сворачивается рамка поля и всё над ней, но не блок целиком", () => {
  const loaded = open();
  const { block, chip, shell, modelRow } = loaded.parts;
  // Сравниваем поимённо, а не целым списком: узлы стаба живут в чужом реалме, и
  // deepEqual на них печатает дерево окна вместо понятной разницы.
  const targets = loaded.inner.collapseTargets();
  assert.equal(targets.length, 2, "сворачиваем ровно два узла");
  assert.equal(targets[0], chip, "первой идёт плашка проекта — она выше рамки");
  assert.equal(targets[1], shell, "второй сама рамка поля");
  assert.ok(!targets.includes(block), "блок целиком не сворачивается никогда");
  assert.ok(!targets.includes(modelRow), "строка модели остаётся на виду");
  loaded.api.setStage(COLLAPSED);
  assert.equal(collapsed(chip), "collapsed");
  assert.equal(collapsed(shell), "collapsed");
  assert.equal(collapsed(block), null, "иначе низ окна станет чёрной полосой");
  assert.equal(collapsed(modelRow), null, "«Auto · Opus 5 · Max» видно и в свёрнутом поле");
  assert.equal(loaded.api.status().collapsedNodes, 2);
  loaded.api.setStage(NORMAL);
  assert.equal(collapsed(chip), null, "развернули — пометки сняты");
  assert.equal(collapsed(shell), null);
});

test("строки модели нет — сворачиваем одну рамку, а не низ окна", () => {
  const loaded = loadInject({ html: noModelRowStand, title: "Trelvis" });
  assert.equal(loaded.api.status().modelRow, false, "разобрать низ не удалось");
  const targets = loaded.inner.collapseTargets();
  assert.equal(targets.length, 1, "запасной путь сворачивает ровно один узел");
  assert.equal(targets[0], loaded.parts.shell, "и это рамка поля, а не блок");
  loaded.api.setStage(COLLAPSED);
  assert.equal(collapsed(loaded.parts.shell), "collapsed");
  assert.equal(collapsed(loaded.parts.block), null, "открытое поле лучше слепого окна");
});

test("новая разметка Claude: сворачивается рамка поля, а не весь низ окна", () => {
  const loaded = loadInject({ html: newBuildStand(), title: "Trelvis" });
  const { prompt, shell, modelRow } = loaded.parts;
  assert.equal(loaded.api.status().modelRow, true, "строка модели найдена под рамкой");
  const targets = loaded.inner.collapseTargets();
  assert.equal(targets.length, 1, "сворачиваем ровно рамку поля");
  assert.equal(targets[0], shell, "и это рамка со вложениями, а не .epitaxy-prompt целиком");
  loaded.api.setStage(COLLAPSED);
  // Главная проверка: до правки сворачивать было нечего, и ступень откатывалась
  // в обычную — клик по полоске визуально не делал ничего.
  assert.equal(loaded.api.status().stage, COLLAPSED, "ступень держится");
  assert.equal(collapsed(shell), "collapsed");
  assert.equal(collapsed(prompt), null, "иначе вместе с полем уедет строка модели");
  assert.equal(collapsed(modelRow), null, "«Auto · Opus 5 · Max» видно и в свёрнутом поле");
});

test("узкое окно: поле уже 200 точек — полоска над ним всё равно есть", () => {
  // Окна Элвиса шириной 280: поле внутри 194 точки, и по прежнему голому порогу
  // в 200 оно вовсе не считалось полем — ручки в подчинённых окнах не было.
  const loaded = loadInject({
    html: newBuildStand({ left: 5, width: 244, editorWidth: 194 }), title: "Trelvis",
    geometry: { viewport: { width: 255, height: 780 } },
  });
  const status = loaded.api.status();
  assert.equal(status.editor, true, "поле найдено");
  assert.equal(status.handleVisible, true, "полоска показана");
  loaded.api.setStage(COLLAPSED);
  assert.equal(loaded.api.status().collapsedNodes, 1, "и сворачивается тоже");
});

test("сворачивать нечего — в свёрнутой ступени не залипаем", () => {
  const bare = loadInject({ title: "Trelvis" });
  assert.equal(bare.inner.collapseTargets().length, 0, "поля ввода на странице нет вовсе");
  bare.api.setStage(COLLAPSED);
  assert.equal(bare.api.status().stage, NORMAL, "иначе полоска рисовалась бы поверх открытого поля и врала");
  assert.equal(bare.win.sessionStorage.getItem(STAGE_KEY), String(NORMAL), "и в сессии осталась бы ложь");
});

test("высота зажата: не ниже минимума и не выше потолка окна", () => {
  const loaded = open();
  const { clampHeight } = loaded.inner;
  const ceiling = clampHeight(1e6);
  assert.equal(clampHeight(1), 38, "ниже минимума поле не сжимается");
  assert.equal(clampHeight(300), 300, "разумную высоту не трогаем");
  assert.ok(ceiling > 38 && ceiling < loaded.win.innerHeight, `потолок ${ceiling} внутри окна ${loaded.win.innerHeight}`);
  assert.equal(clampHeight(1e7), ceiling, "выше потолка не растём, сколько ни проси");
});

test("растянуть мимо зажима нельзя: и команда, и переменная в окне", () => {
  const loaded = open();
  const ceiling = loaded.inner.clampHeight(1e6);
  loaded.api.setStage(STRETCHED, { height: 1e6 });
  assert.equal(loaded.api.status().height, ceiling, "запрошенное урезано потолком");
  assert.equal(loaded.parts.root.style.getPropertyValue(HEIGHT_VARIABLE), `${ceiling}px`,
    "в окно уехала та же зажатая высота");
  loaded.api.setStage(STRETCHED, { height: 1 });
  assert.equal(loaded.api.status().height, 38, "и снизу тоже зажата");
});

test("возврат в «растянуто» — к прежней высоте, а не к потолку", () => {
  const loaded = open();
  loaded.api.setStage(STRETCHED, { height: 300 });
  assert.equal(loaded.api.status().height, 300);
  loaded.api.setStage(NORMAL);
  assert.equal(loaded.api.status().height, null, "обычная высота своей цифры не держит — поле слушается Claude");
  assert.equal(loaded.parts.root.style.getPropertyValue(HEIGHT_VARIABLE), "", "подмена снята");
  loaded.api.setStage(STRETCHED);
  assert.equal(loaded.api.status().height, 300, "вернулись к своему размеру, а не открыли поле во всё окно");
});

// ---- 12.09.2026: поле ввода перестаёт воевать с Claude (WF57) --------------
// Четыре жалобы Элвиса одного дня, и все четыре — про низ окна: полоска висит
// высоко и поверх кнопки Claude (#5866, #5867), низ разговора уезжает под поле
// (#5869), скриншот в свёрнутое поле вставляется невидимо (#5870), клик из
// свёрнутого распахивает поле на пол-экрана (#5868).

test("свёрнутая полоска легла на кромку строки модели и ушла с кнопки Claude", () => {
  const loaded = loadInject({ html: newBuildStand(), title: "Trelvis" });
  const { modelRow, scrollButton } = loaded.parts;
  loaded.api.setStage(COLLAPSED);
  assert.equal(handleOf(loaded).dataset.collapsed, "true", "полоска знает, что поле свёрнуто");
  // Место полоски — кромка строки модели, но не выше низа кнопки Claude «вниз к
  // последнему сообщению»: там, где та прижата к строке, зона захвата съедала бы
  // её нижнюю треть и клик уходил бы полоске, а не кнопке.
  assert.ok(handleTop(loaded) >= box(scrollButton).bottom,
    `зона захвата (верх ${handleTop(loaded)}) начинается не выше низа кнопки ${box(scrollButton).bottom}`);
  assert.ok(handleTop(loaded) >= box(modelRow).top - HANDLE_HEIGHT / 2,
    "и не выше кромки строки модели — выше неё полоска висела бы в пустоте, как до 12.09");
  // Кнопка отодвинута от строки модели — полоска садится ровно на кромку.
  const free = loadInject({ html: newBuildStand({ scrollButtonTop: 640 }), title: "Trelvis" });
  free.api.setStage(COLLAPSED);
  assert.equal(handleLine(free), box(free.parts.modelRow).top,
    "кнопка не мешает — линия ровно на кромке строки модели");
});

test("у свёрнутого поля полоса прогресса переезжает на низ блока — линии не сливаются", () => {
  const loaded = loadInject({ html: newBuildStand(), title: "Trelvis" });
  const { block, shell } = loaded.parts;
  assert.equal(loaded.api.status().progress.anchor, "рамка", "на открытом поле якорь прежний");
  assert.equal(barTop(loaded), box(shell).bottom + PROGRESS_GAP, "и линия сидит под низом рамки с зазором");
  loaded.api.setStage(COLLAPSED);
  // Свёрнутая рамка схлопнута в ноль, и её низ приходится ровно туда, куда
  // встала линия полоски: без переезда две линии рисовались бы одна в одну.
  assert.equal(loaded.api.status().progress.anchor, "низ блока");
  assert.equal(barTop(loaded), box(block).bottom + PROGRESS_GAP, "полоса ушла под низ блока ввода");
  assert.ok(barTop(loaded) - handleLine(loaded) >= PROGRESS_BAR_HEIGHT + 4,
    `между линиями ${barTop(loaded) - handleLine(loaded)} точек — не сливаются`);
  loaded.api.setStage(NORMAL);
  assert.equal(loaded.api.status().progress.anchor, "рамка", "поле открыли — якорь вернулся");
});

test("лента доскручивается вниз после смены ступени, если стояла внизу", () => {
  const loaded = loadInject({ html: newBuildStand(), title: "Trelvis" });
  // Стояла внизу: меняя высоту поля, мы отнимаем у ленты место, и последние
  // строки разговора уезжают под поле (замер 12.09: недокрут 0 → 40 точек).
  const tail = addTranscript(loaded, { scrollTop: 400 });
  loaded.api.setStage(COLLAPSED);
  assert.equal(tail.scrollTop, 900, "лента вернулась вниз");
  tail.scrollTop = 400;
  loaded.api.setStage(NORMAL);
  assert.equal(tail.scrollTop, 900, "и на обратном шаге тоже");
});

test("лента, уведённая наверх рукой, после смены ступени остаётся где была", () => {
  const loaded = loadInject({ html: newBuildStand(), title: "Trelvis" });
  const tail = addTranscript(loaded, { scrollTop: 100 });
  loaded.api.setStage(COLLAPSED);
  assert.equal(tail.scrollTop, 100, "человек сам ушёл наверх — не дёргаем");
});

test("файл в свёрнутое поле сначала открывает поле, а потом идёт своим ходом", () => {
  const loaded = loadInject({ html: newBuildStand(), title: "Trelvis" });
  loaded.api.setStage(COLLAPSED);
  // Свёрнутая рамка схлопнута в ноль и прозрачна: Claude вложение берёт, а
  // видно его не станет — Элвис думает, что вставка не работает.
  loaded.document.dispatchEvent({
    type: "paste", clipboardData: { files: [loaded.dom.file("снимок.png")] },
  });
  assert.equal(loaded.api.status().stage, NORMAL, "вставка картинки открыла поле");
  assert.equal(loaded.api.status().collapsedNodes, 0, "и рамка развёрнута, а не только помечена");
  loaded.api.setStage(COLLAPSED);
  loaded.document.dispatchEvent({
    type: "drop", dataTransfer: { files: [loaded.dom.file("отчёт.pdf", { type: "application/pdf" })] },
  });
  assert.equal(loaded.api.status().stage, NORMAL, "перетаскивание файла — тоже");
  loaded.api.setStage(COLLAPSED);
  loaded.document.dispatchEvent({ type: "paste", clipboardData: { files: [] } });
  assert.equal(loaded.api.status().stage, COLLAPSED, "вставка без файлов поле не трогает");
  // Третья дверь — кнопка «+»: она живёт в строке модели, а та видна и при
  // свёрнутом поле, так что выбранный ею файл пропадал так же молча.
  const picker = loaded.document.body.add("input", { attrs: { type: "file" } });
  picker.type = "file";
  picker.files = [loaded.dom.file("скрин.png")];
  loaded.document.dispatchEvent({ type: "change", target: picker });
  assert.equal(loaded.api.status().stage, NORMAL, "файл, выбранный кнопкой, тоже открыл поле");
});

test("тяга за полоску тоже возвращает ленту вниз", () => {
  // Доскрутка на смене ступени ленту спасает только у клика: тяга меняет высоту
  // мимо ступеней, и низ разговора опять уезжал под поле (находка проверяющего).
  const loaded = loadInject({ html: newBuildStand(), title: "Trelvis" });
  const tail = addTranscript(loaded, { scrollTop: 900 });
  const handle = handleOf(loaded);
  handle.dispatchEvent({ type: "pointerdown", button: 0, clientY: 600, pointerId: 1 });
  tail.scrollTop = 400;                       // поле отняло у ленты место
  // Тягу слушает документ, а не сама полоска: рука уходит с неё на первом же
  // движении.
  loaded.document.dispatchEvent({ type: "pointermove", clientY: 590, pointerId: 1 });
  loaded.document.dispatchEvent({ type: "pointerup", clientY: 590, pointerId: 1 });
  assert.equal(tail.scrollTop, 900, "по концу тяги лента вернулась вниз");
});

test("клик по свёрнутой полоске открывает поле обычной высотой", () => {
  // Три фиксированные строки тут пробовались 12.09 и сняты в тот же день: жёсткая
  // высота воюет с вложениями — блок ввода с пятью скриншотами перестаёт влезать
  // в окно, подрезка режет высоту, Claude перерисовывает вложения, и низ окна
  // прыгает. Клик снова открывает поле так, как его держит сам Claude.
  const loaded = loadInject({ html: newBuildStand(), title: "Trelvis" });
  loaded.api.setStage(STRETCHED, { height: 300 });
  loaded.api.setStage(COLLAPSED);
  clickHandle(loaded);
  assert.equal(loaded.api.status().stage, NORMAL, "клик поднял поле на обычную высоту");
  assert.equal(loaded.api.status().height, null, "своей цифры обычная высота не держит");
  clickHandle(loaded);
  assert.equal(loaded.api.status().stage, COLLAPSED, "второй клик сворачивает — лестница цела");
  loaded.api.setStage(STRETCHED);
  assert.equal(loaded.api.status().height, 300, "натянутый рукой размер память не потеряла");
});

test("подмены высоты у обычной ступени нет вовсе — полю нечем воевать с вложениями", () => {
  // Сторож против возврата жёсткой высоты кликом: пока подмены нет, низ окна
  // прыгать не может (слово Элвиса 12.09 19:00).
  const loaded = loadInject({ html: newBuildStand(), title: "Trelvis" });
  loaded.api.setStage(COLLAPSED);
  clickHandle(loaded);
  assert.equal(loaded.parts.root.style.getPropertyValue(HEIGHT_VARIABLE), "",
    "после клика высота поля ничем не подменена");
  dragHandle(loaded, 600, 500);
  assert.equal(loaded.api.status().stage, STRETCHED, "рукой поле по-прежнему растягивается");
  assert.ok(loaded.parts.root.style.getPropertyValue(HEIGHT_VARIABLE) !== "",
    "и вот тогда подмена появляется — по воле руки, а не сама");
});
