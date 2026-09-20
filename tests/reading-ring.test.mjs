// Кружок контекста в режиме чтения (раздел 6 inject.js, WF78, задача #6737).
// Слово Элвиса 20.09: «кружок — правый нижний угол, там же, где он и сейчас, он
// на своём месте остаётся стоять, тот же кружок, просто плавает».
//
// Способ (он же ответ на вопрос «почему не проще»): кружок НЕ вынимается из
// дерева и не клонируется — React потерял бы свой узел. Сужается действие
// свёртки: ветка с кружком метится «collapsed-ring» (свёртка без opacity —
// opacity создаёт группу прозрачности, и никакой opacity:1 на потомке кружок из
// неё не вытащит), путь до кнопки метится своим атрибутом, соседи по пути
// прячутся правилом, кнопка встаёт absolute в угол.
//
// Проверяется:
//   1) свёрнули — ветка с кружком помечена иначе, чем остальные, кнопка
//      помечена своим атрибутом, а путь — своим; сама кнопка в путь не входит
//      (иначе правило спрятало бы её собственный значок);
//   2) редактор остаётся на обычной свёртке — черновик и фокус не трогаем;
//   3) развернули, сняли экземпляр — меток нет;
//   4) кружка в блоке нет или он прямой ребёнок блока — режим не включается и
//      ничего не ломается;
//   5) зеркальный фейд справа внизу ставится только вместе с кружком, а левый
//      верхний (#6656/#6658) от этого не меняется;
//   6) правила: у зеркала две маски и intersect (иначе слои сложились бы и
//      съели левый верхний фейд), z-index кружка НИЖЕ ручки.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const BLOCK_ATTRIBUTE = "data-myclaude-composer-block";
const RING = "data-myclaude-ring";
const RING_PATH = "data-myclaude-ring-path";
const RING_FADE = "data-myclaude-ring-fade";
const CORNER_FADE = "data-myclaude-corner-fade";
const WIDE_FLAG = "--myclaude-wide";
const COLLAPSED = 0;
const NORMAL = 1;
// Ручка стоит на 2147483646 — кружок обязан быть ниже, иначе он перехватит
// клик по полоске возврата и вернуть поле станет нечем.
const HANDLE_Z = 2147483646;

// Низ окна Claude в режиме чтения: панель чата с лентой во всю высоту, блок
// ввода, а в его нижней строке — группа кнопок с кружком контекста.
const stand = ({ ringWhere = "group", wide = false } = {}) => dom => {
  const panel = dom.document.body.add("div", {
    class: "epitaxy-chat-panel",
    rect: { left: 0, top: 0, width: 1200, height: 800 },
    computed: wide ? { [WIDE_FLAG]: "1" } : {},
  });
  const tail = panel.add("div", {
    attrs: { "data-testid": "epitaxy-virtual-transcript" },
    rect: { left: 0, top: 0, width: 1200, height: 800 },
    computed: { overflowY: "auto" },
  });
  const block = panel.add("div", { class: "epitaxy-composer-width", rect: { left: 100, top: 620, width: 1000, height: 160 } });
  const shell = block.add("div", {
    class: "epitaxy-prompt",
    rect: { left: 100, top: 620, width: 1000, height: 120 },
    computed: { borderTopLeftRadius: "10px" },
  });
  const root = shell.add("div", { class: "editor-root", rect: { left: 110, top: 630, width: 980, height: 100 }, computed: { overflowY: "auto" } });
  const editor = root.add("div", {
    class: "ProseMirror", attrs: { contenteditable: "true" },
    rect: { left: 110, top: 630, width: 980, height: 100 },
  });
  const modelRow = block.add("div", { class: "model-row", rect: { left: 100, top: 744, width: 1000, height: 28 } });
  const model = modelRow.add("button", { rect: { left: 110, top: 746, width: 140, height: 24 } });
  const group = modelRow.add("div", { rect: { left: 900, top: 746, width: 190, height: 24 } });
  const host = { group, row: modelRow, block }[ringWhere] ?? group;
  const ring = host.add("button", {
    attrs: {
      "data-cds": "Button", "aria-haspopup": "dialog",
      "aria-label": "Usage: Context 324.7k / 1M (32%), Weekly · all models: 66%",
    },
    rect: { left: 1050, top: 746, width: 24, height: 24 },
  });
  // Внутри кнопки её собственный значок: он обязан пережить правило, которое
  // прячет всё лишнее внутри пути.
  const icon = ring.add("svg", { rect: { left: 1054, top: 750, width: 16, height: 16 } });
  return { panel, tail, block, shell, root, editor, modelRow, model, group, ring, icon };
};

const open = (options = {}) => loadInject({ html: stand(options), title: "Trelvis" });
const mark = node => node.getAttribute(BLOCK_ATTRIBUTE);
const rules = loaded => String(loaded.dom.query("#myclaude-input-handle-style").textContent ?? "");

test("свёрнули: ветка с кружком помечена особо, кнопка и путь — своими метками", () => {
  const loaded = open();
  const { shell, modelRow, group, ring, icon } = loaded.parts;
  loaded.api.setStage(COLLAPSED);

  assert.equal(mark(shell), "collapsed", "рамка поля сворачивается как обычно — черновик и фокус целы");
  assert.equal(mark(modelRow), "collapsed-ring", "ветка с кружком должна сворачиваться без opacity");
  assert.equal(modelRow.hasAttribute(RING_PATH), true, "ветка не на пути к кружку");
  assert.equal(group.hasAttribute(RING_PATH), true, "промежуточный узел не помечен — правило спрячет кружок");
  assert.equal(ring.getAttribute(RING), "", "кружок не помечен");
  assert.equal(ring.hasAttribute(RING_PATH), false, "кнопка в путь не входит: иначе правило спрячет её значок");
  assert.equal(icon.hasAttribute(RING_PATH), false);
  // Сосед по строке (кнопка модели) не помечен ничем — его и прячет правило.
  assert.equal(loaded.parts.model.hasAttribute(RING_PATH), false);
  assert.equal(loaded.parts.model.hasAttribute(RING), false);
  assert.equal(loaded.api.status().collapsedNodes, 2);
});

test("развернули и сняли экземпляр — меток кружка не остаётся", () => {
  const loaded = open();
  const { modelRow, group, ring } = loaded.parts;
  loaded.api.setStage(COLLAPSED);
  loaded.api.setStage(NORMAL);
  assert.equal(mark(modelRow), null, "свёрнутость не снялась");
  assert.equal(group.hasAttribute(RING_PATH), false, "путь к кружку пережил разворот");
  assert.equal(ring.hasAttribute(RING), false, "метка кружка пережила разворот");

  const again = open();
  again.api.setStage(COLLAPSED);
  assert.equal(again.parts.ring.hasAttribute(RING), true);
  again.api.dispose();
  assert.equal(again.dom.queryAll(`[${RING}],[${RING_PATH}]`).length, 0, "dispose оставил метки кружка");
  assert.equal(again.dom.queryAll(`[${BLOCK_ATTRIBUTE}]`).length, 0);
});

test("кружка в блоке нет — режим не включается, свёртка обычная", () => {
  const loaded = loadInject({
    html: dom => {
      const parts = stand()(dom);
      parts.ring.remove();
      return parts;
    },
    title: "Trelvis",
  });
  loaded.api.setStage(COLLAPSED);
  assert.equal(mark(loaded.parts.modelRow), "collapsed", "без кружка ветке нечего показывать");
  assert.equal(loaded.dom.queryAll(`[${RING_PATH}]`).length, 0);
});

test("кружок прямым ребёнком блока — режим не включается: свёртка срезала бы значок", () => {
  const loaded = open({ ringWhere: "block" });
  loaded.api.setStage(COLLAPSED);
  assert.equal(loaded.parts.ring.hasAttribute(RING), false, "у кнопки-ребёнка блока пустой путь — так нельзя");
  assert.equal(loaded.dom.queryAll(`[${RING_PATH}]`).length, 0);
  // И ничего не сломалось: остальное свёрнуто как обычно.
  assert.equal(mark(loaded.parts.shell), "collapsed");
});

test("кружок в самой строке (не в группе): путь из одного узла, кнопка вне пути", () => {
  const loaded = open({ ringWhere: "row" });
  loaded.api.setStage(COLLAPSED);
  assert.equal(mark(loaded.parts.modelRow), "collapsed-ring");
  assert.equal(loaded.dom.queryAll(`[${RING_PATH}]`).length, 1, "путь должен быть ровно до ветки");
  assert.equal(loaded.parts.ring.hasAttribute(RING), true);
});

test("зеркальный фейд: ставится вместе с кружком, левый верхний не меняется", () => {
  const loaded = open();
  const { tail } = loaded.parts;
  loaded.api.setStage(COLLAPSED);
  assert.equal(tail.hasAttribute(CORNER_FADE), true, "левого верхнего фейда нет — сравнивать не с чем");
  const top = {
    w: tail.style.getPropertyValue("--myclaude-fade-w"),
    h: tail.style.getPropertyValue("--myclaude-fade-h"),
  };
  assert.ok(top.w && top.h, "левый верхний фейд без размеров");
  assert.equal(tail.hasAttribute(RING_FADE), true, "зеркального фейда под кружком нет");
  const ringW = parseFloat(tail.style.getPropertyValue("--myclaude-ring-fade-w"));
  const ringH = parseFloat(tail.style.getPropertyValue("--myclaude-ring-fade-h"));
  assert.ok(ringW > 0 && ringH > 0, "у зеркального фейда нет размеров");
  assert.ok(ringW < parseFloat(top.w) && ringH < parseFloat(top.h),
    `зеркало обязано быть МЕНЬШЕ левого верхнего: ${ringW}×${ringH} против ${top.w}×${top.h}`);

  // Развернули — оба фейда ушли, лента чистая.
  loaded.api.setStage(NORMAL);
  assert.equal(tail.hasAttribute(RING_FADE), false);
  assert.equal(tail.hasAttribute(CORNER_FADE), false);
});

test("без кружка зеркала нет, а левый верхний фейд на месте", () => {
  const loaded = loadInject({
    html: dom => {
      const parts = stand()(dom);
      parts.ring.remove();
      return parts;
    },
    title: "Trelvis",
  });
  loaded.api.setStage(COLLAPSED);
  assert.equal(loaded.parts.tail.hasAttribute(CORNER_FADE), true, "левый верхний фейд пропал вместе с кружком");
  assert.equal(loaded.parts.tail.hasAttribute(RING_FADE), false, "зеркало встало без кружка");
});

test("в широком виде режима чтения нет — значит нет и кружка в углу", () => {
  const loaded = open({ wide: true });
  loaded.api.setStage(COLLAPSED);
  assert.equal(loaded.api.status().layout.wide, true, "стенд не признан широким");
  assert.equal(loaded.api.status().stage, NORMAL, "в широком виде ступень всегда обычная");
  assert.equal(loaded.dom.queryAll(`[${RING}],[${RING_PATH}]`).length, 0);
});

test("правила: у зеркала две маски и intersect, кружок ниже ручки", () => {
  const css = rules(open());
  const plainFade = css.split("\n").find(line => line.startsWith(`[${CORNER_FADE}]{`));
  const ringFade = css.split("\n").find(line => line.startsWith(`[${CORNER_FADE}][${RING_FADE}]{`));
  assert.ok(plainFade, "правила левого верхнего фейда нет");
  assert.ok(ringFade, "правила зеркального фейда нет");
  // Старое правило остаётся однослойным: два слоя по умолчанию СКЛАДЫВАЮТСЯ
  // (mask-composite:add), и левый верхний фейд #6656/#6658 пропал бы.
  assert.equal((plainFade.match(/radial-gradient/g) ?? []).length, 2, "левый верхний фейд обзавёлся лишним слоем");
  assert.equal(plainFade.includes("mask-composite"), false, "в однослойном правиле composite не нужен");
  assert.equal((ringFade.match(/radial-gradient/g) ?? []).length, 4, "у зеркала должно быть по два слоя в каждой форме");
  assert.ok(ringFade.includes("mask-composite:intersect"), "без intersect слои сложатся и съедят левый фейд");
  assert.ok(ringFade.includes("-webkit-mask-composite:source-in"), "webkit-форма composite не дописана");
  assert.ok(ringFade.includes("at 100% 100%"), "зеркало считается от правого нижнего угла");

  const ringRule = css.split("\n").find(line => line.startsWith(`[${RING}]{`));
  assert.ok(ringRule, "правила кружка нет");
  const z = Number(/z-index:(\d+)/.exec(ringRule)?.[1]);
  assert.ok(z < HANDLE_Z, `кружок обязан стоять ниже ручки: ${z}`);
  assert.ok(ringRule.includes("pointer-events:auto"), "кружок обязан ловить нажатия");
  assert.ok(ringRule.includes("opacity:1"), "кружок обязан быть виден");

  const branch = css.split("\n").find(line => line.startsWith(`[${BLOCK_ATTRIBUTE}="collapsed-ring"]{`));
  assert.ok(branch, "правила ветки с кружком нет");
  assert.equal(branch.includes("opacity:0"), false, "opacity в ветке с кружком делает его невидимым навсегда");
  assert.ok(branch.includes("overflow:visible"), "без overflow:visible кружок срежет");
  assert.ok(branch.includes("position:relative"), "без relative absolute кружка поедет к чужому предку");
});
