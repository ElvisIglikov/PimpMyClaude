// #10553 (слово Элвиса 22.10.2026: «наложение происходит… внизу? На текст накладывается»): в режиме обычного
// чата поле лежит в доке ChatComposerDock[data-cds-dock-masked] внутри липкой обёртки [data-chat-input-container]
// поверх ленты (бандл claude.ai 24.10). Claude прячет ленту под полем заливкой bg-page; живой фон её снимает —
// значит, под полем нужна дымка, как у Code, а поле остаётся прозрачным (#9127).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const COLORS = { accent: "#c674fe", muted: "#88aabb", foreground: "#ffffff", dark: true };
const lookCss = look => loadInject({ title: "Trelvis" }).inner.lookCss(look, COLORS);

test("#10553: в режиме чата лента под полем размыта, край мягкий, поле прозрачно", () => {
  for (const motion of ["live", "still", "image"]) {
    const css = lookCss({ aurora: true, neon: false, dense: false, motion });
    const haze = css.match(/\[data-chat-input-container\]:has\(\[data-cds-dock-masked\]\)::before \{([^}]*)\}/)?.[1] ?? "";
    assert.ok(haze, `${motion}: дымки под полем нет`);
    assert.match(haze, /content: ""; position: absolute; inset: 0; z-index: -1; pointer-events: none;/);
    assert.match(haze, /backdrop-filter: blur\(14px\) !important/, "размытие — как у маски под докой Code");
    assert.match(haze, /mask-image: linear-gradient\(to bottom, transparent, #000 24px\) !important/, "край — в отступе pt-6");
    assert.match(css, /\[class\*="in-data-cds-dock-masked:bg-page"\] \{ background-color: transparent !important; \}/);
    assert.match(css, /\[class\*="in-data-cds-dock-masked:from-page"\] \{ background-image: none !important; \}/,
      "полоса цвета страницы под плашками дока снята");
    const field = css.match(/\[data-cds="ChatComposer"\] > div\[class\*="bg-surface"\] \{([^}]*)\}/)?.[1] ?? "";
    assert.match(field, /backdrop-filter: none !important/, "само поле — без стекла (#9127)");
  }
  const plain = lookCss({ aurora: false, neon: false, dense: true });
  assert.ok(!/data-chat-input-container|dock-masked/.test(plain), "без живого фона Claude прячет ленту сам");
});
