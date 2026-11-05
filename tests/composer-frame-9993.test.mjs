// #9993 (слово Элвиса 16.10.2026 19:40: «именно в вертикальном режиме… рамка есть такая, которая поле
// ввода символизирует, её нужно ставить вот в этом режиме, когда это поле внизу находится»): в главном окне,
// где поле внизу, у прозрачной коробки поля видна рамка 1 px цветом линии темы (--cds-border). Широкий вид
// (правило колонки в @container), свёрнутое поле (метка блока) и попап без .dframe-root — без рамки, как были.
// Геометрию CSS стаб не считает — правила сверяются текстом, как в tests/wf165.test.mjs.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const STYLE = "myclaude-input-handle-style";
const BOX = '[data-cds="ChatComposer"] > div[class*="bg-surface"]';
const rules = loaded => (loaded.document.getElementById(STYLE)?.textContent ?? "").split("\n");

test("#9993: в узком главном окне у поля рамка 1 px цветом линии темы; свёрнутое поле — без неё", () => {
  const loaded = loadInject({ html: "composer", title: "Rick чат Элвиса" });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const found = rules(loaded).filter(line => line.startsWith(`.dframe-root ${BOX}:not(`));
  assert.equal(found.length, 1, "одно правило рамки");
  const [rule] = found;
  const selector = rule.slice(0, rule.indexOf("{"));
  const body = rule.slice(rule.indexOf("{") + 1, rule.lastIndexOf("}"));
  assert.equal(body, "border-width:1px !important;border-style:solid !important;border-color:var(--cds-border) !important",
    "толщина и стиль — как у коробки в широком виде, цвет — линия темы (её же ставят темы Пимпа)");
  assert.ok(!/border-radius|background|box-shadow/.test(body), "скругление и прозрачность — прежние");
  assert.ok(selector.includes('[data-myclaude-composer-block^="collapsed"]') && selector.includes('[data-myclaude-composer-block^="collapsed"] *'),
    "свёрнутое поле (и коробка, и её предок) — без рамки");
  // Общее правило прозрачной коробки (#9166а) на месте и прячет рамку везде, где это правило не сильнее.
  assert.equal(rules(loaded).filter(line => line.startsWith(`${BOX}{`)).length, 1);
  // Широкий вид: своё правило внутри @container — рамка там по-прежнему спрятана цветом (#8098).
  const layout = loaded.inner.layoutCss().replace(/\/\*[\s\S]*?\*\//g, "");
  const wide = layout.slice(layout.indexOf("@container tile-slot"));
  const field = wide.slice(wide.indexOf(`& ${BOX} {`));
  assert.match(field.slice(0, field.indexOf("}")), /border-color:\s*transparent !important/);
  // Живой фон прячет рамку правилом без .dframe-root впереди — правило #9993 сильнее его.
  const live = loaded.inner.lookCss({ aurora: true, neon: false, dense: false }, { accent: "#c674fe", muted: "#88aabb", foreground: "#ffffff", dark: true });
  const hide = live.split("\n").find(line => line.startsWith(`${BOX} {`));
  assert.ok(hide && /border-color: transparent/.test(hide), "правило живого фона прежнее");
  loaded.api.dispose();
});
