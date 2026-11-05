// Свои элементы у края окна и колонки — целиком (#9272, #9259; слово Элвиса 09.10 03:50: «кругленькая внизу
// почему-то обрезана… что-то с марджинами, с впадинами в этих контейнерах»). Класс «свой элемент у края режется»:
//   кружок токенов в нижней строке поля (12з¹) — обёртки строки его не режут, тесный ряд выпирает влево, а не
//     вправо (кружок у своего правого поля), теснота видна chinOver с обеих сторон;
//   значок микрофона (12з) — прижат внутрь окна, когда кружок или строка у самого края;
//   угол «Проект · чат» (2ж) — не шире окна минус кнопки окна и минус свой отступ справа (corner-wf102).
// Стенд в настоящем Chromium (раскладка, overflow) — необязательный, как wf120/wf125: без Playwright, сам
// chrome-headless-shell с --dump-dom; путь — PIMP_WF120_CHROMIUM. Без него идут только тесты стаба.
import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { loadInject, loadInner, plain } from "./load.mjs";

const MIC = "#myclaude-mic";
const MIC_SIZE = 20;
const STYLE = "#myclaude-input-handle-style";
const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const px = (node, name) => Number(String(node.style.getPropertyValue(name)).replace("px", ""));

// Поле с родной кнопкой диктовки и кружком контекста в заданном месте (режим чтения — значок у кружка).
const micStand = ring => dom => {
  const parts = dom.composer({ top: 600 });
  parts.modelRow.add("button", { attrs: { "aria-label": "Press and hold to record" }, rect: { left: 150, top: 726, width: 20, height: 20 } });
  parts.ring = parts.modelRow.add("button", {
    attrs: { "aria-haspopup": "dialog", "aria-label": "Usage: Context 300k / 1M (30%)" },
    rect: { left: ring.left, top: ring.top, width: 20, height: 20 },
  });
  return parts;
};
const micAt = (ring, viewport = { width: 1200, height: 800 }) => {
  const loaded = loadInject({ title: "Trelvis", html: micStand(ring), geometry: { viewport }, storage: { local: { "myclaude-send-delay-off": "1" } } });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.api.setStage(loaded.api.stages.COLLAPSED);
  settle(loaded);
  return { loaded, node: loaded.dom.query(MIC), viewport };
};

test("#9272: значок микрофона целиком в окне — кружок у нижнего края и у левой кромки узкого окна", () => {
  // Кружок вылез за низ окна на 8 (раскладка ещё не догнала ресайз): значок не уходит за край вместе с ним.
  const low = micAt({ left: 1100, top: 788 });
  assert.equal(low.node.style.getPropertyValue("display"), "flex");
  assert.equal(px(low.node, "left"), 1100 - 6 - MIC_SIZE, "по горизонтали — как всегда, слева от кружка");
  assert.ok(px(low.node, "top") + MIC_SIZE <= low.viewport.height, `низ значка ${px(low.node, "top") + MIC_SIZE} за краем окна ${low.viewport.height}`);
  // Узкое окно, кружок у левой кромки: слева от него места нет — значок не уходит за левый край.
  const tight = micAt({ left: 10, top: 700 }, { width: 240, height: 800 });
  assert.equal(tight.node.style.getPropertyValue("display"), "flex");
  assert.ok(px(tight.node, "left") >= 0, `левый край значка ${px(tight.node, "left")} за кромкой окна`);
  // Обычное место — без изменений: середина по кружку.
  const usual = micAt({ left: 1100, top: 760 });
  assert.equal(px(usual.node, "top") + MIC_SIZE / 2, 770);
});

// Нижняя строка как у Claude 09.10 (стенд WF195): ряд с полем начала, левая группа, распорка, правая с кружком.
const chinStand = rects => dom => {
  const parts = dom.composer({ top: 600 });
  const chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: rects.chin });
  const row = chin.add("div", { class: "ps-[var(--cmp-chin-start)]", rect: rects.row });
  const lead = row.add("div", { rect: rects.lead });
  lead.add("button", { attrs: { "aria-label": "Add" }, rect: { ...rects.lead, width: 16 } }).add("svg");
  const mode = lead.add("button", { attrs: { "aria-haspopup": "menu" } });
  dom.leaf(mode, "span", "Bypass permissions");
  row.add("span", { class: "flex min-w-0 flex-1 basis-0", rect: rects.gap });
  const end = row.add("div", { rect: rects.end });
  dom.leaf(end.add("button", { attrs: { "data-testid": "epitaxy-cds-model-selector", "aria-haspopup": "menu" } }), "span", "Opus 5.5");
  end.add("button", { attrs: { "aria-haspopup": "dialog", "aria-label": "Usage: Context 300k / 1M (30%)" } }).add("svg");
  return { ...parts, chin, row, lead, end };
};

test("#9272: тесный ряд выпирает влево (кружок у своего края) — теснота всё равно видна, подписи коротко", () => {
  // Ряд 300 точек с 108-го; левая группа вылезла за его левое поле на 12 — так тесноту рисует flex-end.
  const rects = {
    chin: { left: 100, top: 760, width: 316, height: 28 }, row: { left: 108, top: 762, width: 300, height: 20 },
    lead: { left: 96, top: 764, width: 120, height: 16 }, gap: { left: 216, top: 764, width: 0, height: 16 },
    end: { left: 216, top: 764, width: 186, height: 16 },
  };
  const loaded = loadInject({ title: "Trelvis", html: chinStand(rects), geometry: { viewport: { width: 1200, height: 800 } } });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  settle(loaded);
  assert.equal(loaded.parts.chin.hasAttribute("data-myclaude-chin-narrow"), true, "вылет влево — тоже теснота");
  // Места хватает (группы внутри поля ряда) — метки тесноты нет.
  const roomy = loadInject({
    title: "Trelvis", geometry: { viewport: { width: 1200, height: 800 } },
    html: chinStand({ ...rects, lead: { ...rects.lead, left: 108 }, gap: { ...rects.gap, left: 228, width: 0 }, end: { ...rects.end, left: 228, width: 174 } }),
  });
  settle(roomy);
  assert.equal(roomy.parts.chin.hasAttribute("data-myclaude-chin-narrow"), false);
});

test("#9272: правила кружка — обёртки строки на пути к нему не режут (кроме свёрнутых), ряд прижат к правому полю", () => {
  const loaded = loadInject({ html: "composer", title: "Trelvis" });
  const css = String(loaded.dom.query(STYLE).textContent ?? "");
  const { inner } = loadInner();
  const rules = plain(inner.RULES).join("\n");
  // Новые правила — после старых (lateRules): порядок каскада раздела 4 не тронут.
  assert.ok(css.startsWith(rules), "RULES раздела 4 — первыми");
  const late = css.slice(rules.length);
  assert.match(late, /\[data-cds="ChatComposerChin"\]:not\(\[data-myclaude-composer-block\]\),\[data-cds="ChatComposerChin"\] :has\(\[aria-haspopup="dialog"\]:is\(\[aria-label\^="Usage:"\],\[aria-label\^="Использование:"\]\)\):not\(\[data-myclaude-composer-block\]\)\{overflow:visible !important\}/);
  assert.match(late, /\[data-cds="ChatComposerChin"\] div\[class\*="--cmp-chin-start"\]\{justify-content:flex-end !important\}/);
});

// ---- Стенд в Chromium: узкое окно и колонка широкого вида; кружок целиком в окне и ни одним контейнером не срезан.
const CHROMIUM = process.env.PIMP_WF120_CHROMIUM ?? "";
const standHtml = ({ width, height, frame }, css) => `<!doctype html><html><head><meta charset="utf-8">
<style>
html,body{margin:0;height:100%;background:#1d2b36;color:#cfd8e3}
/* Рамка поля у края окна или колонки: скруглена и режет, как у Claude. */
.frame{position:absolute;left:${frame.left}px;top:${height - 100}px;width:${frame.width}px;height:90px;border-radius:12px;overflow:hidden;box-sizing:border-box;background:#22323f}
[data-cds="ChatComposerChin"]{position:absolute;left:0;right:0;bottom:0;height:28px}
/* Три обёртки по одному ребёнку (замер 04.10), одна из них режет — как анимированные обёртки Claude. */
.w{display:flex;flex:1 1 auto;height:100%;min-width:0}
.w.clip{overflow:hidden}
.row{display:flex;align-items:center;flex:1 1 auto;min-width:0;padding:0 10px 0 6px;box-sizing:border-box;white-space:nowrap;font:11px/16px -apple-system,system-ui,sans-serif}
.lead,.end{display:flex;align-items:center;gap:6px;flex-shrink:0}
.gap{flex:1 1 0;min-width:0}
button{all:unset;display:inline-flex;align-items:center;padding:0 4px;flex-shrink:0}
button.ring{width:20px;height:20px;border-radius:50%;box-sizing:border-box;border:2.5px solid #5ab4f0;padding:0}
</style>
<style>${css}</style></head><body>
<div class="frame"><div data-cds="ChatComposerChin"><div class="w clip"><div class="w"><div class="w"><div class="row ps-[var(--cmp-chin-start)]">
<div class="lead"><button aria-label="Add">+</button><button aria-haspopup="menu">Bypass permissions</button></div>
<span class="gap"></span>
<div class="end"><button data-testid="epitaxy-cds-model-selector">Opus 5.5</button><button aria-label="Effort: Extra">Extra</button><button class="ring" aria-haspopup="dialog" aria-label="Usage: Context 180k / 1M (18%)"></button></div>
</div></div></div></div></div></div>
<pre id="m"></pre>
<script>
const ring = document.querySelector(".ring").getBoundingClientRect();
let box = { left: 0, top: 0, right: innerWidth, bottom: innerHeight };
for (let node = document.querySelector(".ring").parentElement; node && node !== document.documentElement; node = node.parentElement) {
  const style = getComputedStyle(node);
  if (style.overflowX === "visible" && style.overflowY === "visible") continue;
  const own = node.getBoundingClientRect();
  box = { left: Math.max(box.left, own.left), top: Math.max(box.top, own.top), right: Math.min(box.right, own.right), bottom: Math.min(box.bottom, own.bottom) };
}
const cut = Math.max(0, box.left - ring.left, ring.right - box.right, box.top - ring.top, ring.bottom - box.bottom);
document.getElementById("m").textContent = "MEASURE " + JSON.stringify({ cut: Math.round(cut * 10) / 10, ring: [ring.left, ring.right], frame: [${frame.left}, ${frame.left + frame.width}] });
</script></body></html>`;

const measure = (scratch, name, stand, css) => {
  const file = path.join(scratch, `${name}.html`);
  writeFileSync(file, standHtml(stand, css));
  const run = spawnSync(CHROMIUM, ["--headless", `--user-data-dir=${path.join(scratch, `profile-${name}`)}`, "--disable-gpu", "--no-sandbox", `--window-size=${stand.width},${stand.height}`,
    "--virtual-time-budget=500", "--dump-dom", pathToFileURL(file).href], { encoding: "utf8", timeout: 20000 });
  const hit = /MEASURE (\{[^<]*\})/.exec(run.stdout ?? "");
  assert.ok(hit, `${name}: замера нет (${run.status}) ${String(run.stderr ?? "").slice(0, 300)}`);
  return JSON.parse(hit[1]);
};

test("#9272 Chromium: кружок токенов целиком — узкое окно и колонка широкого вида, тесная строка и просторная", { skip: !CHROMIUM, timeout: 60000 }, () => {
  const loaded = loadInject({ html: "composer", title: "Trelvis" });
  const css = String(loaded.dom.query(STYLE).textContent ?? "");
  const { inner } = loadInner();
  const before = plain(inner.RULES).join("\n");
  const scratch = mkdtempSync(path.join(tmpdir(), "pimp-edge-"));
  try {
    const stands = {
      // Узкое окно 240: поле во всю ширину, полные подписи не влезают.
      narrow: { width: 240, height: 220, frame: { left: 8, width: 224 } },
      // Колонка широкого вида у правого края окна: тесная (пол ещё не догнал) и просторная.
      "wide-tight": { width: 1200, height: 300, frame: { left: 1200 - 8 - 230, width: 230 } },
      "wide-roomy": { width: 1200, height: 300, frame: { left: 1200 - 8 - 320, width: 320 } },
    };
    for (const [name, stand] of Object.entries(stands)) {
      const after = measure(scratch, name, stand, css);
      assert.equal(after.cut, 0, `${name}: кружок срезан на ${after.cut} (${JSON.stringify(after)})`);
      assert.ok(after.ring[1] <= after.frame[1] && after.ring[0] >= after.frame[0], `${name}: кружок вне рамки поля ${JSON.stringify(after)}`);
    }
    // Стенд видит ошибку: без правил WF261 тесная строка режет кружок рамкой поля.
    assert.ok(measure(scratch, "narrow-before", stands.narrow, before).cut > 0, "стенд не видит обреза — проверка пустая");
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});
