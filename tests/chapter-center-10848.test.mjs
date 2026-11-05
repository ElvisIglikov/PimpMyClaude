// #10848 (слово Элвиса 24.10.2026 13:20, снимок 4: полоски глав «сильно прижаты к тексту… чуть левее сдвинуть, чтоб
// они ровно были посередине»): дорожка встаёт серединой полной полоски посередине между краем слева и началом текста;
// за кромку плитки Claude — не дальше 8 px (там режет прокрутка), вылет снимает overflow-clip-margin её обёртки.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const loaded = loadInject({ title: "Trelvis" });
const { chCenterPlan } = loaded.inner;

test("#10848: окно Рика 24.10 — полоски посередине между чертой дока и текстом, вылет за кромку плитки", () => {
  // Черта рейки дока 244.8 (+1 px), текст 268.8, дорожка 264.8, полоска 6 px (жёлоб 16), кромка плитки 256.8.
  const plan = chCenterPlan({ edge: 245.8, text: 268.8, navLeft: 264.8, len: 6, clipLeft: 256.8 });
  assert.equal(plan.shift, -10.5);
  assert.equal(264.8 + plan.shift + 3, 257.3, "середина полоски — посередине");
  assert.equal(plan.spill, 3, "вылет за кромку плитки — 2.5 px, вверх до целого");
});

test("#10848: дальше прокрутки плитки не выходит, правее места без сдвига не встаёт, без замера — прежние −4", () => {
  const wide = chCenterPlan({ edge: 100, text: 268.8, navLeft: 264.8, len: 12, clipLeft: 256.8 });
  assert.equal(wide.spill, 8, "вылет не больше 8 px");
  assert.equal(wide.shift, -16, "дорожка не левее кромки минус 8");
  const close = chCenterPlan({ edge: 262, text: 300, navLeft: 264.8, len: 6, clipLeft: 256.8 });
  assert.equal(close.shift, 0, "середина правее — сдвига нет");
  assert.equal(close.spill, 0);
  assert.deepEqual(plain(chCenterPlan({ edge: NaN, text: 268.8, navLeft: 264.8, len: 6, clipLeft: 256.8 })), { shift: -4, spill: 0 });
  assert.deepEqual(plain(chCenterPlan({ edge: 270, text: 268.8, navLeft: 264.8, len: 6, clipLeft: 256.8 })), { shift: -4, spill: 0 });
});

test("#10848: сдвиг — переменной поверх прежних −4, короткие полоски от середины, обёртке плитки — вылет", () => {
  const all = loaded.dom.queryAll("style").map(style => style.textContent).join("\n");
  assert.match(all, /\.epitaxy-toc > nav > ol\[aria-hidden="true"\]\{translate:var\(--myclaude-ch-shift,-4px\) 0\}/);
  assert.match(all, /\.epitaxy-toc > nav > ol\[aria-hidden="true"\]>li>span\{transform-origin:center !important\}/);
  assert.match(all, /\[data-myclaude-ch-clip\]\{overflow-clip-margin:var\(--myclaude-ch-spill,0px\) !important\}/);
  assert.ok(all.indexOf("translate:-4px 0") < all.indexOf("translate:var(--myclaude-ch-shift"), "переменная — после прежних −4");
});
