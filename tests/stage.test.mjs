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
// Здесь проверяются ровно эти четыре места и ничего сверх.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

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
const open = (options = {}) => loadInject({ html: composerStand, title: "Trelvis", ...options });
const collapsed = node => node.getAttribute(BLOCK_ATTRIBUTE);

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
