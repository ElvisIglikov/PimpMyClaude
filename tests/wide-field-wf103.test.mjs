// WF103, батч P3 (раздел 2а layoutCss, широкий вид WF65; #7974): поле ввода в
// правой колонке — цветом чата с тонкой рамкой. Слово Элвиса 27.09: «поле ввода…
// когда он становится справа… сделать тем же самым цветом, что и чат, просто с
// рамочкой… А то у меня сейчас чат на две полосы делится».
//
// Контракт (CONTRACTS, WF103, «Волна 3»): в широком виде фон колонки и самого поля —
// цвет фона ленты (прозрачны, как лента), вокруг поля рамка 1 px линией темы;
// узкий вид не меняется; status().wide.field === "flat" в широком виде.
// Стаб DOM `@container` не понимает — CSS проверяется разбором текста.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";

const { inner } = loadInner({ title: "Trelvis" });
const css = inner.layoutCss().replace(/\/\*[\s\S]*?\*\//g, "");
const at = css.indexOf("@container tile-slot");
const inside = css.slice(at);
const outside = css.slice(0, at);
const FIELD = '& [data-cds="ChatComposer"] > div[class*="bg-surface"]';
const COLUMN = "& .group\\/approval-dock {";
const body = (text, selector) => {
  const start = text.indexOf(selector);
  if (start < 0) return null;
  const open = text.indexOf("{", start);
  return text.slice(open + 1, text.indexOf("}", open));
};

// WF106 (#8098, слово Элвиса 29.09: «доп-рамкой отображается… разделить…
// линией тоненькой… пусть они даже одним цветом будут»): рамки вокруг поля нет —
// её прячет ЦВЕТ (border-color и тень прозрачные; ширина, стиль и тень не «none»
// остаются: по ним editorFrame находит коробку поля, #6890). Ленту от поля
// делит одна линия var(--cds-border): в широком виде — вертикальная по левой
// кромке колонки (дока и шапка колонки), в узком — горизонтальная по верху доки.
const TITLE = ".epitaxy-chat-panel:not([data-myclaude-title=\"left\"]) & > .epitaxy-titlebar";

test("#8098: широкий вид — поле цветом ленты, рамка спрятана цветом, геометрия та же", () => {
  assert.ok(at > 0, "блока @container нет");
  const field = body(inside, FIELD);
  assert.ok(field, "правила поля в широком виде нет");
  // #9127 (WF142): прозрачно всегда — и с живым фоном (стекло WF139 снято).
  assert.match(field, /background:\s*transparent !important/);
  assert.match(field, /border-width:\s*1px !important/);
  assert.match(field, /border-style:\s*solid !important/);
  assert.match(field, /border-color:\s*transparent !important/);
  assert.match(field, /box-shadow:\s*0 0 0 0 transparent !important/);
  assert.ok(!/box-shadow:\s*none|border:\s*0|border-width:\s*0|border-radius/.test(field), "рамку сняли геометрией");
  assert.match(body(inside, COLUMN) ?? "", /background:\s*transparent !important/, "колонка не цветом ленты");
});

test("#8098: широкий вид — вертикальная линия по левой кромке колонки (дока и шапка)", () => {
  const line = body(inside, "& .group\\/approval-dock,");
  assert.ok(line, "правила линии нет");
  // WF128 (#9053): цвет — через --myclaude-split-line, живой фон гасит линию (lookCss).
  assert.match(line, /box-shadow:\s*inset 1px 0 0 0 var\(--myclaude-split-line, var\(--cds-border\)\) !important/);
  assert.ok(inside.includes(`${"& .group\\/approval-dock,"}\n    ${TITLE} {`), "у шапки колонки линии нет");
});

test("#8132/#9166а: узкий вид — в layoutCss своего правила поля нет (прозрачность без рамки — общим правилом RULES), линии по верху доки нет", () => {
  // Слово Элвиса 29.09 («нижнее поле ввода должно остаться, как раньше было») сменено словом
  // 09.10 00:05 («всё должно быть прозрачно… из-за того, что есть сейчас рамка, я ничего не
  // понимаю»): поле без рамки во всех видах — правилом раздела 4 (tests/wf165.test.mjs).
  assert.equal(body(outside, '[data-cds="ChatComposer"] > div[class*="bg-surface"] {'), null,
    "в layoutCss вне @container правила поля нет");
  assert.equal(body(outside, "\n.group\\/approval-dock {"), null, "в узком виде снова линия по верху доки");
});

const PANEL = { left: 200, top: 0, width: 900, height: 800 };
const DOCK = { left: 780, top: 32, width: 320, height: 768 };
const stand = wide => dom => {
  const panel = dom.document.body.add("div", { class: "epitaxy-chat-panel", rect: PANEL, computed: wide ? { "--myclaude-wide": "1" } : {} });
  const grid = panel.add("div", { class: "relative h-full min-w-0 flex flex-col", rect: PANEL });
  grid.add("div", { class: "epitaxy-titlebar", rect: { left: DOCK.left, top: 0, width: DOCK.width, height: 32 } });
  const contents = grid.add("div", { class: "contents" });
  contents.add("div", { class: "epitaxy-chat-panel-body", rect: { left: PANEL.left, top: 0, width: DOCK.left - PANEL.left, height: PANEL.height } });
  const dock = contents.add("div", { class: "contents" }).add("div", { class: "group/approval-dock flex flex-col", rect: DOCK });
  const prompt = dock.add("div", { class: "epitaxy-prompt", rect: { left: 792, top: 100, width: 296, height: 690 } });
  const block = prompt.add("div", { class: "flex w-full min-w-0 flex-col font-sans", rect: { left: 792, top: 100, width: 296, height: 690 } });
  const shell = block.add("div", { class: "bg-surface-3", rect: { left: 792, top: 100, width: 296, height: 660 }, computed: { borderBottomWidth: "1px" } });
  const root = shell.add("div", { class: "editor-root", rect: { left: 802, top: 110, width: 276, height: 640 }, computed: { overflowY: "auto" } });
  const editor = root.add("div", { class: "ProseMirror", attrs: { contenteditable: "true" }, rect: { left: 802, top: 110, width: 276, height: 640 } });
  return { panel, grid, dock, prompt, block, shell, root, editor };
};

test("#8098: status().wide — field: \"line\" в широком виде, null в узком", () => {
  const wide = loadInject({ html: stand(true), title: "Trelvis" });
  assert.equal(wide.error, null, String(wide.error?.stack ?? wide.error));
  assert.deepEqual(plain(wide.api.status().wide), { on: true, field: "line" });
  const narrow = loadInject({ html: stand(false), title: "Trelvis" });
  assert.deepEqual(plain(narrow.api.status().wide), { on: false, field: null });
});
