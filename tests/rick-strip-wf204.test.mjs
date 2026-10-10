// WF204 (followups WF201, #9095): готовые подряд в полоске марафона — всегда одна полоса (длинная рябила),
// своей клеткой — только идущий, упавший и ждущий (впереди — как раньше: сливаются, лишь когда клетки
// узкие); наведение на слитый отрезок — ячейка «WF1–WF5 · готово» и свет на весь отрезок, клик — карточка
// последнего из него. Счёт «N из M» — правым краем по знаку ↵ в кнопке, а не по коробке кнопки.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const LAYER = "#myclaude-rick-cells";
const CHAT = "local_cccc-3333";
const DIGEST = "http://127.0.0.1:47615/digest";
// Рамка поля 100..1100 × 600..720; Enter — коробка 24×24, знак ↵ — иконка 16×16 в ней (замер 09.10).
const SEND = { left: 1060, top: 660, width: 24, height: 24 };
const GLYPH = { left: 1064, top: 664, width: 16, height: 16 };
const CHIN = { left: 100, top: 690, width: 1000, height: 28 };

const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const tick = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };
const digest = (...projects) => ({ v: 1, at: "2026-10-09T07:00:00Z", projects });
const ok = data => () => Promise.resolve({ ok: true, json: () => Promise.resolve(data) });
const KIND = { d: "готово", r: "идёт", w: "ждёт", f: "упал", p: "впереди" };
const M = (name, states) => {
  const workflows = [...states].map((mark, i) => ({ n: i + 1, state: KIND[mark], about: `работа ${i + 1}`, steps: "1/3", phase: mark === "r" ? "кодинг" : "" }));
  return { name, title: name, group: "идут", done: workflows.filter(flow => flow.state === "готово").length, total: workflows.length, workflows };
};
const page = async ({ reply, glyph = true } = {}) => {
  const loaded = loadInject({
    title: "Rick", href: `https://claude.ai/epitaxy/${CHAT}`, storage: { local: { "myclaude-rick-filter": "all" } },
    html: dom => {
      const parts = dom.composer({ top: 600 });
      parts.root.rect = { left: 110, top: 610, width: 980, height: 45 };
      parts.editor.rect = { left: 110, top: 610, width: 980, height: 45 };
      parts.chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: CHIN });
      parts.send = parts.block.add("button", { attrs: { "data-testid": "code-prompt-send" }, rect: SEND });
      if (glyph) {
        // Как у Claude: подложки во всю коробку, иконка — меньше.
        parts.send.add("span", { rect: SEND });
        parts.send.add("span", { rect: GLYPH }).add("span", { rect: GLYPH });
      }
      const side = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
      const item = side.add("div", { attrs: { "data-row-key": `code:${CHAT}` } });
      item.__reactFiber$test = { memoizedProps: { session: { ref: { id: CHAT }, source: { data: { cwd: "/Users/dev/Projects/Rick" } } } }, return: null };
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.win.fetch = url => (url === DIGEST ? reply() : Promise.resolve({ ok: true }));
  settle(loaded);
  await tick();
  settle(loaded);
  return loaded;
};
const kids = (node, tag) => [...node.childNodes].filter(kid => kid.nodeType === 1 && (!tag || kid.tagName.toLowerCase() === tag));
const layer = loaded => loaded.dom.query(LAYER);
const rows = loaded => kids(kids(layer(loaded), "p")[0], "s");
const row = (loaded, key) => rows(loaded).find(item => item.dataset.key === key);
const strip = item => kids(item, "span").find(node => node.dataset.strip);
const tally = item => kids(item, "span").find(node => node.dataset.count);
const parts = item => kids(strip(item), "u").filter(node => !node.dataset.mark);
const marks = (item, kind) => kids(strip(item), "u").filter(node => node.dataset.mark === kind);
const px = (node, name) => Number(String(node.style.getPropertyValue(name)).replace("px", ""));
const rick = loaded => plain(loaded.api.status().rickCells);
const cellX = (loaded, item, k) => px(layer(loaded), "left") + px(strip(item), "left") + k * Number(strip(item).dataset.pitch) + 0.5;
const tip = loaded => kids(layer(loaded), "i").find(node => node.dataset.tip);
const spans = item => parts(item).map(node => [node.dataset.state, Number(node.dataset.from), Number(node.dataset.to)]);

test("WF204: готовые подряд — одна полоса и при широких клетках; идущий, ждущий, упавший — каждый своей; впереди широко — клетками", async () => {
  const loaded = await page({ reply: ok(digest(M("Vkus", "dddddrrdfwdpp"))) });
  const vkus = row(loaded, "Vkus");
  assert.equal(strip(vkus).dataset.pitch, "12", "клетки не широкие — проверка не о том");
  assert.deepEqual(spans(vkus), [["done", 0, 4], ["run", 5, 5], ["run", 6, 6], ["done", 7, 7], ["fail", 8, 8], ["wait", 9, 9], ["done", 10, 10], ["plan", 11, 11], ["plan", 12, 12]]);
  // Слитая полоса — сплошная: от первой клетки до конца пятой, без зазоров внутри.
  const [done] = parts(vkus);
  assert.equal(px(done, "left"), 0);
  assert.equal(px(done, "width"), 5 * 12 - 1.5);
  assert.equal(px(parts(vkus)[1], "left"), 5 * 12);
  assert.equal(tally(vkus).textContent, "7 из 13");
});

test("WF204: наведение на слитую часть — «WF1–WF5 · готово» над серединой отрезка, свет на весь отрезок; клик — карточка последнего (5), ещё клик — закрыть", async () => {
  const loaded = await page({ reply: ok(digest(M("Dict", "dddddr"))) });
  const dict = row(loaded, "Dict");
  const bar = strip(dict);
  layer(loaded).dispatchEvent({ type: "pointermove", target: parts(dict)[0], clientX: cellX(loaded, dict, 1) });
  assert.equal(tip(loaded).textContent, "WF1–WF5 · готово");
  assert.equal(tip(loaded).dataset.state, "done");
  assert.equal(tip(loaded).style.getPropertyValue("display"), "block");
  assert.deepEqual(rick(loaded).hover, { key: "Dict", n: 5 });
  const [hover] = marks(dict, "hover");
  assert.equal(px(hover, "left"), 0);
  assert.equal(px(hover, "width"), 5 * 12 - 1.5);
  // Ножка — в середину отрезка.
  const mid = px(bar, "left") + (5 * 12 - 1.5) / 2;
  assert.equal(px(tip(loaded), "left") + px(tip(loaded), "--sx"), Math.round(mid * 2) / 2);
  // Внутри того же отрезка — тот же свет, не мигает заново.
  layer(loaded).dispatchEvent({ type: "pointermove", target: parts(dict)[0], clientX: cellX(loaded, dict, 4) });
  assert.equal(marks(dict, "hover")[0], hover);
  // Идущая клетка рядом — своя ячейка «6».
  layer(loaded).dispatchEvent({ type: "pointermove", target: parts(dict)[1], clientX: cellX(loaded, dict, 5) });
  assert.equal(tip(loaded).textContent, "6");
  assert.equal(marks(dict, "hover").length, 1);
  assert.equal(px(marks(dict, "hover")[0], "left"), 5 * 12);
  // Клик по слитой части — карточка Workflow 5 (последнего из диапазона); свет «открыта» — на весь отрезок.
  layer(loaded).dispatchEvent({ type: "click", detail: 1, target: parts(dict)[0], clientX: cellX(loaded, dict, 2) });
  assert.equal(rick(loaded).card, "flow");
  assert.match(rick(loaded).flow, /^Воркфлоу 5 ·/);
  const again = row(loaded, "Dict");
  const [picked] = marks(again, "picked");
  assert.equal(px(picked, "left"), 0);
  assert.equal(px(picked, "width"), 5 * 12 - 1.5);
  layer(loaded).dispatchEvent({ type: "click", detail: 1, target: parts(again)[0], clientX: cellX(loaded, again, 0) });
  assert.equal(rick(loaded).card, null, "повторный клик по отрезку не закрыл");
});

test("WF204: счёт «N из M» — правым краем по знаку ↵ в кнопке, не по её коробке; знака нет — по коробке", async () => {
  const loaded = await page({ reply: ok(digest(M("Vkus", "drr"))) });
  const vkus = row(loaded, "Vkus");
  assert.equal(px(layer(loaded), "left") + px(tally(vkus), "left") + px(tally(vkus), "width"), GLYPH.left + GLYPH.width);
  const bare = await page({ reply: ok(digest(M("Vkus", "drr"))), glyph: false });
  const plainRow = row(bare, "Vkus");
  assert.equal(px(layer(bare), "left") + px(tally(plainRow), "left") + px(tally(plainRow), "width"), SEND.left + SEND.width);
});
