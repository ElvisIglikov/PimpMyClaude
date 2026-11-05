// Полоса прокрутки ленты (#9845, WF266; #11216 — уже и едва заметная). Классический вид: своя полоса у ленты чата — дорожка
// 8 px, ползунок в покое тоньше, под курсором и при захвате — шире и плотнее, цвет — от темы. Живой фон — полос
// нет, как решено в WF185: наши правила без !important, его — с !important, и в каскаде побеждают его.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const open = () => loadInject({
  title: "Trelvis",
  html: dom => {
    const body = dom.document.body;
    const feed = body.add("div", { class: "h-full overflow-y-auto overflow-x-hidden", attrs: { "data-testid": "epitaxy-virtual-transcript" } });
    const side = body.add("div", { class: "dframe-nav-scroll relative flex flex-col overflow-y-auto" });
    return { feed, side };
  },
});
let seq = 0;
const look = (loaded, value) => loaded.dom.command({ id: `wf266-${++seq}`, action: "theme", at: "now", scope: "all", look: value });
// Свои правила страницы (RULES и lateRules) — в <style id=myclaude-input-handle-style>, слои вида — в листах окна.
const allCss = loaded => `${loaded.dom.document.getElementById("myclaude-input-handle-style")?.textContent ?? ""}\n${loaded.dom.sheets()}`;
const AREA = 'html :where([data-testid="epitaxy-virtual-transcript"], [data-cds="ChatComposer"] div:has(> .ProseMirror), [data-myclaude-editor-root])';

test("#9845/#11216: классический вид — у ленты своя полоса: дорожка 8, едва заметная, ползунок тоньше в покое, шире под курсором и при захвате", () => {
  const loaded = open();
  assert.equal(loaded.error, null);
  look(loaded, { aurora: false });
  const css = allCss(loaded);
  assert.ok(css.includes(`${AREA}{scrollbar-width:auto;scrollbar-color:auto;scrollbar-gutter:auto}`), "Chromium не рисует ::-webkit-scrollbar при thin/цвете Claude; место под полосу — только справа (#10111)");
  assert.ok(css.includes(`${AREA}::-webkit-scrollbar{width:8px;height:8px;`), "дорожка не 8 px (#11216: «поуже… суперпрозрачную»)");
  const ink = /::-webkit-scrollbar-thumb\{[^}]*currentColor\) (\d+)%/.exec(css);
  assert.ok(ink && Number(ink[1]) <= 20, `ползунок в покое не едва заметный: ${ink?.[1]} %`);
  const rest = /::-webkit-scrollbar-thumb\{[^}]*border:(\d+)px solid transparent/.exec(css);
  const hover = /::-webkit-scrollbar-thumb:hover\{border-width:(\d+)px/.exec(css);
  const grab = /::-webkit-scrollbar-thumb:active\{border-width:(\d+)px/.exec(css);
  assert.ok(rest && hover && grab, "нет вида покоя, наведения или захвата");
  assert.ok(Number(hover[1]) < Number(rest[1]) && Number(grab[1]) < Number(rest[1]), "под курсором и при захвате ползунок не шире");
  assert.match(css, /::-webkit-scrollbar-thumb\{[^}]*var\(--cds-text-secondary, currentColor\)/, "цвет ползунка не от темы");
  assert.doesNotMatch(css, /scrollbar-width:auto[^;}]*!important/, "наша полоса пересилит живой фон (WF185)");
  assert.doesNotMatch(css, /dframe-nav-scroll[^{]*\{scrollbar-width:auto/, "список чатов — как у Claude");
});

test("#9845: живой фон — полос по-прежнему нет: скрытие WF185 с !important стоит рядом с нашей полосой", () => {
  const loaded = open();
  look(loaded, { aurora: true });
  const css = allCss(loaded);
  assert.match(css, /\* \{ scrollbar-width: none !important; \}/);
  assert.match(css, /::-webkit-scrollbar \{ display: none !important; width: 0 !important;/);
  assert.ok(css.includes(`${AREA}::-webkit-scrollbar{width:8px;`), "правило полосы общее, его гасит !important живого вида");
});
