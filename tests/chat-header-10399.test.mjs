// #10399 (слово Элвиса 20.10.2026: «чёрные прямоугольники… в режиме кода всё нормально, а в режиме чата нет»):
// в режиме обычного чата шапка .dframe-header и док у поля залиты цветом страницы поверх живого фона (бандл
// claude.ai 24.10): шапка — bg-surface-1, под названием и кнопками — подложка панели toolbar-ground, без
// панелей — полоса df-header-backdrop; у поля — bg-page карточек дока, затухание page-fade и плашка подписи.
// Живой фон их снимает: шапка — дымка с мягким краем, у поля — прозрачно; шапку Code (WF274) не трогает.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const COLORS = { accent: "#c674fe", muted: "#88aabb", foreground: "#ffffff", dark: true };
const lookCss = look => loadInject({ title: "Trelvis" }).inner.lookCss(look, COLORS);
const body = (css, selector) => {
  const at = css.indexOf(`${selector} {`);
  return at < 0 ? "" : css.slice(at + selector.length + 2, css.indexOf("}", at));
};

const HEADER = `.dframe-header:is([class~="bg-surface-1"], [class*=":bg-surface-1"])`;
const GROUND = `:is([data-cds="Toolbar"]:not(.epitaxy-titlebar *) > [data-cds-part="toolbar-ground"], [data-cds="Page"] [data-cds-part="page-header-ground"])`;

test("#10399: в режиме чата шапка — дымка с мягким краем, без заливки и черты", () => {
  for (const motion of ["live", "still", "image"]) {
    const css = lookCss({ aurora: true, neon: false, dense: false, motion });
    assert.match(body(css, HEADER), /^ background-color: transparent !important; $/, `${motion}: шапка залита`);
    const haze = body(css, `${HEADER}::before`);
    assert.match(haze, /content: ""; position: absolute; inset: 0 0 -12px; z-index: -1; pointer-events: none;/, `${motion}: дымки шапки нет`);
    for (const part of [haze, body(css, GROUND)]) {
      assert.match(part, /backdrop-filter: blur\(14px\) !important/, "размытие — как под полем");
      assert.match(part, /mask-image: linear-gradient\(to top, transparent, #000 12px\) !important/, "нижний край мягкий");
    }
    assert.match(body(css, GROUND), /^ bottom: -12px !important; background-color: transparent !important;/, "подложка панели цветом страницы снята");
    assert.match(body(css, ":is(.df-header-backdrop, [data-lifted-row-fade])"),
      /background-color: transparent !important; -webkit-backdrop-filter: blur\(14px\) !important/, "полоса под шапкой — дымка");
    assert.match(body(css, `.dframe-header [data-cds="Toolbar"]::after`), /border-bottom-width: 0 !important/, "линий нет (WF128)");
  }
});

test("#10399: у поля в режиме чата карточки дока, затухание и плашка подписи прозрачны", () => {
  const css = lookCss({ aurora: true, neon: false, dense: false, motion: "still" });
  assert.match(css, /\[data-cds-dock-masked\] \.bg-page \{ background-color: transparent !important; \}/);
  assert.match(css, /\[data-cds-dock-masked\] \[class\*="page-fade"\]::before \{ background-image: none !important; \}/);
  assert.match(css, /\[class~="-mt-10"\]\[class~="pt-12"\]\[class~="bg-surface-1"\] \{ background-color: transparent !important; \}/);
});

test("#10399: шапку Code правило не трогает, без живого фона правил нет", () => {
  const css = lookCss({ aurora: true, neon: false, dense: false, motion: "still" });
  assert.ok(css.includes(GROUND) && GROUND.includes(":not(.epitaxy-titlebar *)"), "подложку шапки Code снимает сетка WF274");
  const plain = lookCss({ aurora: false, neon: false, dense: true });
  assert.ok(!/dframe-header|toolbar-ground|df-header-backdrop|page-fade/.test(plain), "без живого фона Claude рисует шапку сам");
});
