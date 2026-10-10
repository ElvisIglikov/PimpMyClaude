// WF103, батч P3 (раздел 12п inject.js; #7965): значок «Галерея» — только значок
// и число. Слово Элвиса 27.09: «не надо слово „галерея“ писать… просто картинку и
// цифру… в рамку ни в какую брать не надо… иконка очень мелкая… чтобы этих
// квадратиков было поменьше… покрупнее».
//
// Контракт (CONTRACTS, WF103, «Волна 3»): слова «Галерея» не видно нигде — ни в
// широком окне, ни в узком, ни у кружка (оно остаётся в title/aria-label); без
// рамки и заливки; значок 2×2; цвет — текста окна, data-on/data-fresh — янтарём
// #f59e0b; фиолетового и свечения нет; status().gallery — прежние поля.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const GALLERY = "#myclaude-gallery";
const CHAT = "local_aaaa-1111";
let seq = 0;

const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const page = ({ viewport, files = [3, 0] } = {}) => {
  const loaded = loadInject({
    title: "Trelvis", href: `https://claude.ai/epitaxy/${CHAT}`, ...(viewport ? { geometry: { viewport } } : {}),
    html: dom => {
      const parts = dom.composer({ top: 600 });
      parts.chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: { left: 92, top: 744, width: 1016, height: 28 } });
      const row = parts.chin.add("div", { class: "flex items-center", rect: { left: 100, top: 748, width: 1000, height: 20 } });
      parts.left = row.add("div", { class: "flex items-center self-start", rect: { left: 100, top: 750, width: 60, height: 16 } });
      parts.left.add("button", { attrs: { "aria-label": "Add" }, rect: { left: 100, top: 750, width: 20, height: 16 } });
      const right = row.add("div", { class: "ms-auto flex items-center", rect: { left: 1000, top: 748, width: 120, height: 20 } });
      const grid = right.add("div", { class: "grid", rect: { left: 1000, top: 748, width: 120, height: 20 } });
      grid.add("button", { attrs: { "data-testid": "epitaxy-cds-model-selector" }, text: "Opus 5.5", rect: { left: 1000, top: 750, width: 60, height: 16 } });
      grid.add("button", { attrs: { "aria-haspopup": "dialog", "aria-label": "Usage: Context 300k / 1M (30%)" }, rect: { left: 1100, top: 748, width: 20, height: 20 } });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.win.fetch = () => Promise.resolve({});
  loaded.dom.command({ id: `c-${seq += 1}`, action: "viewer-counts", at: "now", scope: "all", chats: { [CHAT]: files } });
  settle(loaded);
  return loaded;
};
const node = loaded => loaded.dom.query(GALLERY);
const css = loaded => loaded.dom.queryAll("style").map(style => style.textContent).join("\n");
const galleryRules = loaded => css(loaded).split("\n").filter(line => line.includes("#myclaude-gallery"));

test("#7965: слова «Галерея» не видно — ни в широком, ни в узком, ни у кружка; в title и aria-label оно есть", () => {
  for (const viewport of [undefined, { width: 340, height: 800 }]) {
    const loaded = page({ viewport });
    assert.equal(loaded.api.status().gallery.visible, true);
    assert.equal(node(loaded).textContent.trim(), "3", "видны только значок и число");
    assert.ok(!node(loaded).textContent.includes("Галерея"));
    assert.match(node(loaded).title, /Галерея/);
    assert.match(node(loaded).getAttribute("aria-label"), /Галерея/);
    loaded.api.setStage(loaded.api.stages.COLLAPSED);
    settle(loaded);
    assert.equal(loaded.api.status().gallery.spot, "ring");
    assert.equal(node(loaded).textContent.trim(), "3", "у кружка — тоже без слова");
  }
});

test("#7965: значок — 2×2 крупных квадрата, одна ширина в широком и узком окне", () => {
  const wide = page();
  const narrow = page({ viewport: { width: 340, height: 800 } });
  const svg = node(wide).querySelector("svg");
  assert.ok(svg, "значка SVG нет");
  assert.equal(svg.querySelectorAll("rect").length, 4, "квадратов не четыре");
  assert.equal(node(wide).style.getPropertyValue("width"), node(narrow).style.getPropertyValue("width"));
  // WF106 (#8099, «чуть-чуть поменьше»): значок 12 px (было 15), ширина 20 + 6 на
  // цифру (было 25 + 7), шрифт 10 px (было 12) — на ~20 % меньше.
  assert.match(css(wide), /#myclaude-gallery>svg\{[^}]*width:12px;height:12px/, "значок не 12 px");
  assert.match(css(wide), /#myclaude-gallery\{[^}]*font:600 10px\/16px/, "шрифт числа не уменьшен");
  assert.equal(node(wide).style.getPropertyValue("width"), "26px", "место под кнопку осталось прежним");
});

test("#7965: без рамки, заливки, фиолетового и свечения; WF106 (#8099): новое и нажатое — не жёлтым", () => {
  const loaded = page({ files: [4, 2] });
  const rules = galleryRules(loaded).join("\n");
  assert.ok(!/180,\s*140,\s*255/.test(rules), "фиолетовый остался");
  assert.ok(!/box-shadow:0 0|drop-shadow|glow|animation/.test(rules), "свечение осталось");
  assert.match(rules, /#myclaude-gallery\{[^}]*border:0;[^}]*background:transparent;/);
  assert.match(rules, /#myclaude-gallery\{[^}]*color:inherit;/, "цвет — не текста окна");
  assert.match(rules, /#myclaude-gallery\[data-fresh="true"\],#myclaude-gallery\[data-on="true"\]\{[^}]*color:inherit/);
  assert.ok(!/#f59e0b/.test(rules), "ярко-жёлтый остался у свежей или нажатой");
  // Точка-акцент у свежей — приглушённый янтарь (непрозрачность ≤ 0,75).
  assert.match(rules, /#myclaude-gallery\[data-fresh="true"\]::after\{[^}]*background:rgba\(245,158,11,\.75\)/);
  assert.equal(node(loaded).dataset.fresh, "true");
});

test("#7965: status().gallery — прежние поля", () => {
  const loaded = page();
  assert.deepEqual(Object.keys(plain(loaded.api.status().gallery)).sort(),
    ["clicks", "compact", "counted", "files", "fresh", "heard", "last", "on", "repeats", "spot", "unseen", "visible"]);
});
