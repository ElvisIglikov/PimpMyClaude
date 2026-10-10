// Края прокрутки живого вида (WF185). Слово Элвиса 09.10 03:40: «Полосу прокрутки в режиме живом
// убери вообще, она только отвлекает»; 03:42: «И сверху и снизу сделай плавный тоненький фейд,
// чтобы текст плавно терялся, а не обрезался жёстко». Классический вид — как у Claude.
//
// Проверяем настоящим путём: вид включает команда theme (look.aurora), правила читаются
// dom.sheets(), метки сторон ставят прокрутка (событие на документе) и обход раз в секунду.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const ATTR = "data-myclaude-scroll-fade";

const open = () => loadInject({
  title: "Trelvis",
  html: dom => {
    const body = dom.document.body;
    // Лента, список чатов, поле ввода — их узлы прокрутки в форме Claude (замер 09.10).
    const feed = body.add("div", { class: "h-full overflow-y-auto overflow-x-hidden", attrs: { "data-testid": "epitaxy-virtual-transcript" } });
    const side = body.add("div", { class: "dframe-nav-scroll relative flex flex-col overflow-y-auto" });
    const field = body.add("div", { attrs: { "data-cds": "ChatComposer" } }).add("div", { class: "w-full max-h-96 overflow-y-auto break-words" });
    // Область, которую обход не знает, — её метит сама прокрутка.
    const card = body.add("div", { class: "some-card" });
    return { feed, side, field, card };
  },
});
let seq = 0;
const look = (loaded, value) => loaded.dom.command({ id: `wf185-${++seq}`, action: "theme", at: "now", scope: "all", look: value });
const scroll = (node, { top, height, client }) => Object.assign(node, { scrollTop: top, scrollHeight: height, clientHeight: client });
const tick = loaded => loaded.dom.fireKind("interval");

test("WF185: сторона затухания — только туда, где ещё есть что крутить", () => {
  const { inner } = open();
  const of = (top, height, client) => inner.scrollFadeOf({ scrollTop: top, scrollHeight: height, clientHeight: client });
  assert.equal(of(0, 500, 500), "", "крутить некуда — затухания нет");
  assert.equal(of(0, 501, 500), "", "лишняя точка — не прокрутка");
  assert.equal(of(0, 1000, 500), "bottom", "у самого верха — только снизу: первая строка цела");
  assert.equal(of(250, 1000, 500), "both");
  assert.equal(of(500, 1000, 500), "top", "у самого низа — только сверху: последняя строка цела");
  assert.equal(of(499.5, 1000, 500), "top", "дробная прокрутка у низа — уже низ");
});

test("WF185: живой вид — полос прокрутки нет нигде, края затухают тонко; классический — правил нет", () => {
  const loaded = open();
  assert.equal(loaded.error, null);
  look(loaded, { aurora: true });
  const css = loaded.dom.sheets();
  assert.match(css, /\* \{ scrollbar-width: none !important; \}/, "полосы прокрутки видны");
  assert.match(css, /::-webkit-scrollbar \{ display: none !important;/);
  const px = Number(/\[data-myclaude-scroll-fade="top"\] \{ -webkit-mask-image: linear-gradient\(to bottom, transparent 0, #000 (\d+)px\)/.exec(css)?.[1]);
  assert.ok(px >= 12 && px <= 16, `затухание не тонкое: ${px}`);
  for (const side of ["top", "bottom", "both"]) assert.ok(css.includes(`[${ATTR}="${side}"] { -webkit-mask-image: linear-gradient(to bottom`), `нет правила стороны ${side}`);
  // Лента с угловым затуханием (applyCornerFade) — маски складываются, а не вытесняют друг друга.
  assert.match(css, /\[data-myclaude-scroll-fade="both"\]\[data-myclaude-corner-fade\] \{ -webkit-mask-image: radial-gradient[^}]*linear-gradient[^}]*mask-composite: intersect/);
  // Классический: правил нет — прокрутка как у Claude.
  look(loaded, { aurora: false, dense: true });
  const plainCss = loaded.dom.sheets();
  assert.ok(!plainCss.includes("scrollbar-width: none !important"), "в классическом полосы спрятаны");
  assert.ok(!plainCss.includes(ATTR), "в классическом наши края прокрутки");
});

test("WF185: метки сторон — по прокрутке и обходом; классический вид и dispose их снимают", () => {
  const loaded = open();
  const { feed, side, field, card } = loaded.parts;
  scroll(feed, { top: 0, height: 4000, client: 600 });
  scroll(side, { top: 0, height: 300, client: 300 });
  scroll(field, { top: 0, height: 380, client: 200 });
  scroll(card, { top: 0, height: 900, client: 300 });
  // Классический — ничего не метим.
  tick(loaded);
  assert.equal(loaded.document.querySelectorAll(`[${ATTR}]`).length, 0);
  look(loaded, { aurora: true });
  assert.equal(feed.getAttribute(ATTR), "bottom", "лента наверху — затухание только снизу");
  assert.equal(side.getAttribute(ATTR), null, "список влез — без затухания");
  assert.equal(field.getAttribute(ATTR), "bottom", "длинный текст в поле ввода — затухает");
  assert.equal(card.getAttribute(ATTR), null, "незнакомую область обход не трогает");
  // Прокрутили ленту в самый низ — затухание только сверху.
  feed.scrollTop = 3400;
  loaded.document.dispatchEvent({ type: "scroll", target: feed });
  assert.equal(feed.getAttribute(ATTR), "top");
  // Любая прокручиваемая область — по своей прокрутке.
  card.scrollTop = 100;
  loaded.document.dispatchEvent({ type: "scroll", target: card });
  assert.equal(card.getAttribute(ATTR), "both");
  // Список вырос без прокрутки — обход раз в секунду.
  side.scrollHeight = 900;
  tick(loaded);
  assert.equal(side.getAttribute(ATTR), "bottom");
  assert.equal(loaded.api.status().scrollFades, 4);
  // Классический — метки сняты сразу, без ожидания тика.
  look(loaded, { aurora: false, dense: true });
  assert.equal(loaded.document.querySelectorAll(`[${ATTR}]`).length, 0, "в классическом остались метки");
  assert.equal(loaded.api.status().scrollFades, 0);
  // Снова живой и dispose — меток нет.
  look(loaded, { aurora: true });
  assert.ok(loaded.document.querySelectorAll(`[${ATTR}]`).length > 0);
  loaded.api.dispose();
  assert.equal(loaded.document.querySelectorAll(`[${ATTR}]`).length, 0);
});

// Строки списка слева затухают своим фейдом Claude (.dframe-fade-label[data-overflowing], замер 09.10 —
// маска стоит и в живом, и в классическом): наши таблицы его не перебивают ни в одном виде.
test("WF185: фейд строк списка слева — родной Claude в живом и классическом, мы его не трогаем", () => {
  const loaded = open();
  for (const value of [{ aurora: true }, { aurora: false, dense: true }]) {
    look(loaded, value);
    const css = loaded.dom.sheets();
    const touching = css.split("\n").filter(line => /dframe-fade-label|data-row-label/.test(line) && /mask|text-overflow:\s*ellipsis|overflow:\s*visible/.test(line)
      && !/::before/.test(line));
    assert.deepEqual(touching, [], `вид ${JSON.stringify(value)}: правило перебивает фейд строки`);
    assert.ok(!/mask-image:\s*none/.test(css), "маски кто-то гасит");
  }
});

// WF197 (задача Рика: «нижнее затухание ленты в широком окне уходит за край»): лента Claude длиннее своей
// ячейки (инлайн height: calc(100% + высота доки), замер 09.10: лента 1012 при ячейке 527 и окне 535) —
// нижнее затухание у 100 % стояло за краем окна. Сдвиг до видимого края — переменной узла.
test("WF197: лента длиннее ячейки — нижнее затухание у видимого края, а не за окном", () => {
  const loaded = loadInject({
    title: "Trelvis",
    geometry: { viewport: { width: 973, height: 535 } },
    html: dom => {
      const cell = dom.document.body.add("div", { class: "h-full", rect: { left: 225, top: 0, width: 444, height: 527 } });
      const feed = cell.add("div", { class: "h-full overflow-y-auto", attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: { left: 225, top: 0, width: 444, height: 1012 } });
      return { cell, feed };
    },
  });
  const { feed } = loaded.parts;
  look(loaded, { aurora: true });
  const css = loaded.dom.sheets();
  assert.ok(css.includes("transparent calc(100% - var(--myclaude-scroll-cut, 0px)))"), "низ затухания — от видимого края");
  scroll(feed, { top: 2000, height: 16500, client: 1012 });
  tick(loaded);
  assert.equal(feed.getAttribute(ATTR), "both");
  assert.equal(feed.style.getPropertyValue("--myclaude-scroll-cut"), "485px", "1012 − 527: столько ленты ниже края");
  // У самого низа нижнего затухания нет — и сдвига тоже.
  scroll(feed, { top: 15488, height: 16500, client: 1012 });
  tick(loaded);
  assert.equal(feed.getAttribute(ATTR), "top");
  assert.equal(feed.style.getPropertyValue("--myclaude-scroll-cut"), "");
  // Лента в ячейку (узкий вид без сдвига) — сдвига нет.
  feed.rect = { left: 225, top: 0, width: 444, height: 527 };
  scroll(feed, { top: 2000, height: 16500, client: 527 });
  tick(loaded);
  assert.equal(feed.style.getPropertyValue("--myclaude-scroll-cut"), "");
  scroll(feed, { top: 2000, height: 16500, client: 1012 });
  feed.rect = { left: 225, top: 0, width: 444, height: 1012 };
  tick(loaded);
  loaded.api.dispose();
  assert.equal(feed.style.getPropertyValue("--myclaude-scroll-cut"), "", "dispose снимает сдвиг");
});
