// Кружок у поля ввода — только контекст этого чата (раздел 12з² inject.js, #10317). Слово Элвиса 19.10: кружок, где
// «Opus 5.5», показывает «как будто недельный лимит, то краснеет, то зеленеет», а должен всегда — только контекст,
// сколько его занято в этом чате.
//
// Проверяется контракт раздела, а не разметка Claude:
//   1) кружок есть — поверх встаёт свой слой (родной svg и aria-label целы); числа нет — пустая дорожка;
//   2) chat-context своего чата с 400 000 токенов — дуга 40 % (status().contextRing.pct = 40); чужой чат — не
//      меняется;
//   3) кружка нет, или в нём нет родного svg — слоя нет, found: false, без исключений;
//   4) смена чата — дуга пустеет сразу и приложение спрошено о новом чате;
//   5) когда спрашивать приложение: идёт ход — не чаще CTX_RING_WORK_MS, конец хода — ещё раз, чат молчит и число
//      есть — не спрашиваем;
//   6) dispose() снимает слой и метку, родной svg остаётся.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const HEARTBEAT_MS = 500;
const CHAT = "local_aaaa-1111";
const OTHER = "local_bbbb-2222";
const RING_ATTRIBUTE = "data-myclaude-ctx-ring";
const LAYER = "[data-myclaude-ctx-layer]";
const ARC = '[data-myclaude-ctx-part="arc"]';
const LABEL = "Usage: Weekly · all models: 77%, Resets Fri 8:00 AM";

// Кружок Claude в нижней строке поля: кнопка 24×24, внутри родной svg 16×16 по середине.
const stand = ({ ring = true, art = true } = {}) => dom => {
  const parts = dom.composer({ top: 600 });
  if (!ring) return parts;
  const button = parts.modelRow.add("button", {
    attrs: { "data-cds": "Button", "aria-haspopup": "dialog", "aria-label": LABEL },
    rect: { left: 1060, top: 726, width: 24, height: 24 },
  });
  const native = art ? button.add("svg", { attrs: { viewBox: "0 0 16 16" }, rect: { left: 1064, top: 730, width: 16, height: 16 } }) : null;
  if (native) native.add("circle", { attrs: { r: "6", stroke: "red" } });
  return { ...parts, ring: button, native };
};

// Часы стенда: performance.now (now() страницы) — снаружи vm, Date.now (зазор запросов) — внутри; двигаем оба.
const clock = loaded => {
  loaded.win.__shift = 0;
  loaded.run("(() => { const real = Date.now; Date.now = () => real() + (globalThis.__shift || 0); })()");
  const real = loaded.win.performance.now;
  loaded.win.performance.now = () => real() + loaded.win.__shift;
  return ms => { loaded.win.__shift += ms; };
};

const open = options => {
  const loaded = loadInject({ href: `https://claude.ai/epitaxy/${CHAT}`, html: stand(options) });
  loaded.fetched = [];
  loaded.win.fetch = url => { loaded.fetched.push(String(url)); return Promise.resolve({}); };
  loaded.tick = clock(loaded);
  return loaded;
};
const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const beat = loaded => {
  for (const [id, item] of [...loaded.dom.timers.entries()]) {
    if (item.kind === "interval" && item.ms === HEARTBEAT_MS) loaded.dom.fire(id);
  }
};
const context = (loaded, chat, tokens) =>
  loaded.dom.command({ id: `ctx-${Math.random()}`, action: "chat-context", at: "now", chat, tokens });
const asks = (loaded, chat = CHAT) => loaded.fetched.filter(url => url === `http://127.0.0.1:47615/context?chat=${chat}`).length;
const ring = loaded => plain(loaded.api.status().contextRing);

test("кружок есть — свой слой поверх родного, числа нет — пустая дорожка", () => {
  const loaded = open();
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  settle(loaded);
  const { ring: button, native } = loaded.parts;
  const layer = button.querySelector(LAYER);
  assert.ok(layer, "своего слоя в кружке нет");
  assert.equal(button.hasAttribute(RING_ATTRIBUTE), true, "кружок не помечен — родной svg не спрятан");
  assert.equal(native.parentNode, button, "родной svg вынут");
  assert.equal(native.getAttribute("viewBox"), "0 0 16 16");
  assert.equal(button.getAttribute("aria-label"), LABEL, "родной aria-label тронут");
  // Слой — ровно по рамке родного svg внутри кнопки.
  assert.deepEqual(["left", "top", "width", "height"].map(name => layer.style.getPropertyValue(name)), ["4px", "4px", "16px", "16px"]);
  assert.equal(button.querySelector(ARC).getAttribute("display"), "none", "без числа дуги быть не должно");
  assert.deepEqual(ring(loaded), { found: true, pct: null, chat: CHAT });
  // Правила: родной svg — opacity 0 (нажатие «как мышью» должно в него попадать), свой слой — без нажатий.
  const css = String(loaded.dom.query("#myclaude-input-handle-style")?.textContent ?? "");
  assert.ok(css.includes(`[${RING_ATTRIBUTE}] svg:not([data-myclaude-ctx-layer]){opacity:0 !important}`), "родная дуга не прячется");
  assert.match(css, /\[data-myclaude-ctx-layer\]\{position:absolute !important;[^}]*pointer-events:none !important/);
  // Повторный проход слой не множит.
  settle(loaded);
  assert.equal(button.querySelectorAll(LAYER).length, 1);
});

test("chat-context своего чата — дуга по контексту (400k → 40 %), чужой чат — не меняется", () => {
  const loaded = open();
  settle(loaded);
  context(loaded, OTHER, 900000);
  assert.equal(ring(loaded).pct, null, "принят контекст чужого чата");
  assert.equal(loaded.parts.ring.querySelector(ARC).getAttribute("display"), "none");
  context(loaded, CHAT, 400000);
  const arc = loaded.parts.ring.querySelector(ARC);
  assert.equal(ring(loaded).pct, 40);
  assert.equal(arc.hasAttribute("display"), false, "дуга не показана");
  assert.equal(arc.getAttribute("stroke-dasharray"), "40.00 100");
  assert.equal(loaded.parts.ring.querySelector(LAYER).getAttribute("title"), "Контекст: 400k из 1M");
  // Чужой чат после своего — дуга та же.
  context(loaded, OTHER, 100000);
  assert.equal(ring(loaded).pct, 40);
  assert.equal(arc.getAttribute("stroke-dasharray"), "40.00 100");
  // Больше окна — полный круг, не больше.
  context(loaded, CHAT, 1500000);
  assert.equal(ring(loaded).pct, 100);
  assert.equal(arc.getAttribute("stroke-dasharray"), "100.00 100");
  // Родной aria-label (его читают лимиты для Пимпа) не тронут.
  assert.equal(loaded.parts.ring.getAttribute("aria-label"), LABEL);
});

test("кружка нет или в нём нет родного svg — слоя нет, found: false, без исключений", () => {
  for (const options of [{ ring: false }, { art: false }]) {
    const loaded = open(options);
    assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
    settle(loaded);
    beat(loaded);
    context(loaded, CHAT, 400000);
    assert.equal(loaded.dom.queryAll(LAYER).length, 0, "слой без родного кружка");
    assert.equal(loaded.dom.queryAll(`[${RING_ATTRIBUTE}]`).length, 0);
    assert.equal(ring(loaded).found, false);
    loaded.api.dispose();
  }
});

test("смена чата — дуга пустеет сразу, приложение спрошено о новом чате", () => {
  const loaded = open();
  const router = loaded.dom.router();
  settle(loaded);
  beat(loaded);
  assert.equal(asks(loaded), 1, "о своём чате не спросили");
  context(loaded, CHAT, 400000);
  assert.equal(ring(loaded).pct, 40);
  router.navigate(`/epitaxy/${OTHER}`);
  beat(loaded);
  assert.deepEqual(ring(loaded), { found: true, pct: null, chat: OTHER });
  assert.equal(loaded.parts.ring.querySelector(ARC).getAttribute("display"), "none", "дуга прошлого чата осталась");
  assert.equal(asks(loaded, OTHER), 1, "о новом чате не спросили сразу");
  context(loaded, OTHER, 120000);
  assert.equal(ring(loaded).pct, 12);
  // Вернулся в прежний чат — спрошен снова, мимо зазора.
  router.navigate(`/epitaxy/${CHAT}`);
  beat(loaded);
  assert.equal(asks(loaded), 2);
});

test("когда спрашивать: идёт ход — раз в 15 с, конец хода — ещё раз, молчит с числом — нет", () => {
  const loaded = open();
  settle(loaded);
  beat(loaded);
  assert.equal(asks(loaded), 1);
  // Числа нет, чат молчит: повтор не раньше 30 с.
  beat(loaded);
  loaded.tick(20000);
  beat(loaded);
  assert.equal(asks(loaded), 1, "без числа спрашивают чаще 30 с");
  loaded.tick(11000);
  beat(loaded);
  assert.equal(asks(loaded), 2, "без числа не переспросили");
  context(loaded, CHAT, 300000);
  // Число есть, чат молчит — не спрашиваем.
  loaded.tick(60000);
  beat(loaded);
  assert.equal(asks(loaded), 2, "молчащий чат с числом спрошен");
  // Идёт ход — сразу (с прошлого запроса прошло больше 15 с), потом не чаще 15 с.
  const stop = loaded.parts.modelRow.add("button", { attrs: { "data-testid": "code-prompt-stop" } });
  beat(loaded);
  assert.equal(asks(loaded), 3, "в ходе не спросили");
  loaded.tick(10000);
  beat(loaded);
  assert.equal(asks(loaded), 3, "в ходе спрашивают чаще 15 с");
  loaded.tick(6000);
  beat(loaded);
  assert.equal(asks(loaded), 4);
  // Ход кончился — через 2 с ещё раз, мимо зазора.
  stop.parentNode.removeChild(stop);
  beat(loaded);
  assert.equal(asks(loaded), 4, "спросили до того, как расшифровка дописана");
  loaded.tick(2100);
  beat(loaded);
  assert.equal(asks(loaded), 5, "после хода не спросили");
  loaded.tick(60000);
  beat(loaded);
  assert.equal(asks(loaded), 5);
});

test("dispose() снимает слой и метку, родной svg остаётся; второй прогон — один слой", () => {
  const loaded = open();
  settle(loaded);
  context(loaded, CHAT, 400000);
  const { ring: button, native } = loaded.parts;
  assert.ok(button.querySelector(LAYER));
  const again = loaded.reload();
  assert.equal(again.error, null, String(again.error?.stack ?? again.error));
  settle(loaded);
  assert.equal(loaded.dom.queryAll(LAYER).length, 1, "второй прогон оставил два слоя");
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(LAYER).length, 0, "свой слой пережил dispose()");
  assert.equal(button.hasAttribute(RING_ATTRIBUTE), false, "метка пережила dispose()");
  assert.equal(native.parentNode, button, "родной svg пропал");
  assert.equal(button.getAttribute("aria-label"), LABEL);
});
