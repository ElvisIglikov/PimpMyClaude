// Просмотр фото (раздел 12л inject.js, #7667, #7668, WF87): клик по фото в ленте
// чата открывает свой просмотр на всё окно (окно растягивается на монитор), листание
// ← → ‹ › и свайпом по кругу, Esc/✕/фон — закрыть; Esc не доходит до Claude.
//
// Стенд — как Claude 2.9939.2 по разведке 25.09: лента
// [data-testid="epitaxy-virtual-transcript"] role=feed, фото — <img> с data:-адресом
// внутри span[role=button] плитки (главное окно) или button[aria-label^="View image"]
// (попап). Стаб событий не всплывает: событие шлём прямо туда, где висит
// слушатель (документ, окно, слой), с нужной целью в target.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const VIEW = "#myclaude-photo-view";

// На экране фото — как живая плитка 71×160, если не сказано иное.
const photo = (parent, src, { w = 640, h = 1440, shown = [71, 160] } = {}) => {
  const img = parent.add("img", { attrs: { src } });
  img.naturalWidth = w;
  img.naturalHeight = h;
  img.rect = { left: 0, top: 0, width: shown[0], height: shown[1] };
  return img;
};

// Лента: плитка с двумя фото, аватарка-значок, миниатюра вкладки Browser,
// фото в попапной кнопке «View image», повтор первого фото; вне ленты — фото в
// плашке поля ввода.
const page = ({ href = "https://claude.ai/epitaxy/local_view" } = {}) => {
  const nodes = {};
  const loaded = loadInject({
    href,
    html: dom => {
      const parts = dom.composer({});
      const pill = dom.pill(parts.block, { name: "draft.png" });
      pill.querySelector("img").naturalWidth = 800;
      const feed = dom.document.body.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed", "aria-label": "Chat messages" },
      });
      const row1 = feed.add("div", { class: "group/message-row" });
      nodes.avatar = photo(row1, "data:image/png;base64,AVATAR", { w: 32, h: 32 });
      // Значок большого натурального размера, показанный 16×16, — не фото.
      nodes.icon = photo(row1, "data:image/png;base64,ICON", { w: 128, h: 128, shown: [16, 16] });
      const tileA = row1.add("span", { attrs: { role: "button", tabindex: "0" } });
      nodes.a = photo(tileA, "data:image/png;base64,AAA");
      nodes.tileA = tileA;
      const tileB = row1.add("span", { attrs: { role: "button", tabindex: "0" } });
      nodes.b = photo(tileB, "data:image/webp;base64,BBB");
      nodes.tileB = tileB;
      const row2 = feed.add("div", { class: "group/message-row" });
      const browser = row2.add("button", { attrs: { "aria-label": "Open Browser tab" } });
      nodes.thumb = photo(browser, "data:image/jpeg;base64,THUMB", { w: 800, h: 600 });
      const view = row2.add("button", { attrs: { "aria-label": "View image preview.png" } });
      nodes.c = photo(view, "data:image/png;base64,CCC", { w: 1312, h: 540 });
      nodes.again = photo(row2, "data:image/png;base64,AAA");
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return { loaded, nodes };
};

const layer = loaded => loaded.document.querySelector(VIEW);
const parts = loaded => loaded.inner.photoState.parts;
const view = loaded => plain(loaded.api.viewer.state());
// Нажатие мышью по цели: pointerdown, mousedown и click — все на захват документа.
// Ответ — для каждого события, отменено ли оно (dispatchEvent стаба отдаёт
// !defaultPrevented, как браузер; сам объект события он копирует).
const press = (loaded, target) => ["pointerdown", "mousedown", "click"]
  .map(type => !loaded.document.dispatchEvent({ type, target, button: 0, clientX: 10, clientY: 10 }));
// Отменена ли клавиша.
const key = (loaded, name, type = "keydown") => !loaded.win.dispatchEvent({ type, key: name });

test("фото чата собираются по порядку ленты: без значков, миниатюры Browser, поля ввода и повторов", () => {
  const { loaded, nodes } = page();
  const list = loaded.inner.photoList();
  assert.deepEqual(plain(list.map(item => item.src)), [
    "data:image/png;base64,AAA", "data:image/webp;base64,BBB", "data:image/png;base64,CCC",
  ]);
  assert.equal(list[0].img, nodes.a);
  assert.equal(loaded.inner.photoAt(nodes.tileB), nodes.b, "нажатие в плитку (её ::after) — это её фото");
  assert.equal(loaded.inner.photoAt(nodes.avatar), null);
  assert.equal(loaded.inner.photoAt(nodes.icon), null, "128×128 на экране 16×16 — значок");
  assert.equal(loaded.inner.photoAt(nodes.thumb), null);
});

test("нажатие по фото открывает просмотр с этого фото, и Claude нажатия не видит", () => {
  const { loaded, nodes } = page();
  const claude = [];
  loaded.document.addEventListener("pointerdown", () => claude.push("pointerdown"));
  loaded.document.addEventListener("click", () => claude.push("click"));
  const prevented = press(loaded, nodes.tileB);
  assert.deepEqual(claude, [], "до Claude не дошло ни одно из трёх событий");
  // pointerdown и mousedown глушатся, но не отменяются: отмена pointerdown в
  // Chromium отменяет и перетаскивание фото (раздел 12м², #7685).
  assert.deepEqual(prevented, [false, false, true]);
  assert.deepEqual(view(loaded), { open: true, index: 1, total: 3, zoom: false, grown: false });
  assert.equal(layer(loaded).style.getPropertyValue("display"), "block");
  assert.equal(parts(loaded).img.src, "data:image/webp;base64,BBB");
  assert.equal(parts(loaded).count.textContent, "2 / 3");
  assert.equal(loaded.document.activeElement, layer(loaded), "фокус на слое — клавиши не уходят в поле ввода");
});

test("значок, миниатюра Browser, правая кнопка и нажатие с ⌘ остаются Claude", () => {
  const { loaded, nodes } = page();
  for (const target of [nodes.avatar, nodes.icon, nodes.thumb]) {
    assert.deepEqual(press(loaded, target), [false, false, false]);
  }
  assert.equal(loaded.document.dispatchEvent({ type: "click", target: nodes.a, button: 2 }), true);
  assert.equal(loaded.document.dispatchEvent({ type: "click", target: nodes.a, button: 0, metaKey: true }), true);
  assert.equal(view(loaded).open, false);
  assert.equal(layer(loaded), null, "слой рождается только при первом открытии");
});

test("листание по кругу: стрелки, кнопки ‹ ›, свайп — один шаг на жест", () => {
  const { loaded, nodes } = page();
  press(loaded, nodes.c);
  assert.equal(view(loaded).index, 2);
  key(loaded, "ArrowRight");
  assert.equal(view(loaded).index, 0, "после последнего — первое");
  key(loaded, "ArrowLeft");
  assert.equal(view(loaded).index, 2, "перед первым — последнее");
  assert.equal(parts(loaded).count.textContent, "3 / 3");
  layer(loaded).dispatchEvent({ type: "click", target: parts(loaded).next });
  assert.equal(view(loaded).index, 0);
  layer(loaded).dispatchEvent({ type: "click", target: parts(loaded).prev });
  assert.equal(view(loaded).index, 2);
  assert.equal(parts(loaded).img.src, "data:image/png;base64,CCC");
  // Пальцы влево — deltaX растёт: следующее; инерция того же жеста не листает.
  for (const deltaX of [30, 40, 80, 120]) layer(loaded).dispatchEvent({ type: "wheel", deltaX, deltaY: 2 });
  assert.equal(view(loaded).index, 0, "один свайп — один шаг");
  loaded.inner.photoState.swipeAt = -Infinity;
  for (const deltaX of [-50, -50]) layer(loaded).dispatchEvent({ type: "wheel", deltaX, deltaY: 0 });
  assert.equal(view(loaded).index, 2, "новый жест вправо — назад");
  loaded.inner.photoState.swipeAt = -Infinity;
  layer(loaded).dispatchEvent({ type: "wheel", deltaX: 5, deltaY: 90 });
  assert.equal(view(loaded).index, 2, "прокрутка вниз не листает");
});

test("Esc закрывает просмотр и не доходит до Claude — ни keydown, ни keyup", () => {
  const { loaded, nodes } = page();
  const claude = [];
  loaded.win.addEventListener("keydown", event => claude.push(`down ${event.key}`));
  loaded.win.addEventListener("keyup", event => claude.push(`up ${event.key}`));
  const editor = loaded.document.querySelector(".ProseMirror");
  editor.focus();
  // Как Esc обходится со страницей без просмотра (сторож раздела 16) — эталон для «после».
  const escBefore = key(loaded, "Escape");
  const claudeBefore = claude.splice(0);
  press(loaded, nodes.a);
  assert.equal(key(loaded, "ArrowRight"), true);
  assert.equal(key(loaded, "Escape"), true);
  assert.equal(view(loaded).open, false);
  assert.equal(layer(loaded).style.getPropertyValue("display"), "none");
  // Закрытый слой не «диалог»: иначе OVERLAY_SELECTOR и сторож Esc (раздел 16) видят его
  // открытым, и Esc снова останавливал бы агента.
  assert.equal(loaded.document.querySelector('[role="dialog"]'), null);
  assert.equal(key(loaded, "Escape", "keyup"), true, "keyup Esc после закрытия тоже наш");
  assert.deepEqual(claude, []);
  assert.equal(loaded.document.activeElement, editor, "фокус вернулся в поле ввода");
  // Просмотр закрыт — Esc снова как без просмотра: закрытый слой сторожа Esc не обманывает.
  assert.equal(key(loaded, "Escape"), escBefore);
  assert.deepEqual(claude, claudeBefore);
});

test("✕ и клик по фону закрывают; клик по фото — 100 % и обратно; перетаскивание не закрывает", () => {
  const { loaded, nodes } = page();
  press(loaded, nodes.a);
  const { img, stage, close } = parts(loaded);
  layer(loaded).dispatchEvent({ type: "click", target: img, clientX: 5, clientY: 5 });
  assert.equal(view(loaded).zoom, true);
  assert.equal(img.style.getPropertyValue("max-width"), "none");
  assert.equal(stage.style.getPropertyValue("overflow"), "auto");
  layer(loaded).dispatchEvent({ type: "click", target: img });
  assert.equal(img.style.getPropertyValue("max-height"), "100vh", "обратно — целиком в окне");
  layer(loaded).dispatchEvent({ type: "click", target: img, clientX: 5, clientY: 5 });
  assert.equal(stage.style.getPropertyValue("overflow"), "auto");
  layer(loaded).dispatchEvent({ type: "pointerdown", target: img, clientX: 100, clientY: 100 });
  layer(loaded).dispatchEvent({ type: "pointermove", target: img, clientX: 60, clientY: 70 });
  assert.equal(stage.scrollLeft, 40);
  assert.equal(stage.scrollTop, 30);
  layer(loaded).dispatchEvent({ type: "pointerup", target: img });
  layer(loaded).dispatchEvent({ type: "click", target: stage });
  assert.equal(view(loaded).open, true, "клик в конце перетаскивания — не клик по фону");
  assert.equal(view(loaded).zoom, true);
  layer(loaded).dispatchEvent({ type: "click", target: img });
  assert.equal(view(loaded).zoom, false);
  layer(loaded).dispatchEvent({ type: "click", target: stage });
  assert.equal(view(loaded).open, false);
  loaded.api.viewer.open(1);
  layer(loaded).dispatchEvent({ type: "click", target: close });
  assert.equal(view(loaded).open, false);
});

test("окно сразу растягивается на монитор без полноэкранного режима и при закрытии встаёт на место", () => {
  const { loaded, nodes } = page();
  const win = loaded.win;
  const calls = [];
  let asked = 0;
  const make = loaded.document.createElement;
  loaded.document.createElement = tag => {
    const node = make(tag);
    node.requestFullscreen = () => { asked += 1; return new Promise(() => {}); };
    return node;
  };
  Object.assign(win, {
    screenX: 900, screenY: 40, outerWidth: 321, outerHeight: 720,
    screen: { availLeft: 0, availTop: 25, availWidth: 1512, availHeight: 920 },
    moveTo: (x, y) => { calls.push(["move", x, y]); win.screenX = x; win.screenY = y; },
    resizeTo: (w, h) => { calls.push(["size", w, h]); win.outerWidth = w; win.outerHeight = h; },
  });
  press(loaded, nodes.a);
  assert.equal(asked, 0, "requestFullscreen у Claude висит — не зовём");
  assert.deepEqual(calls, [["move", 0, 25], ["size", 1512, 920]]);
  assert.equal(view(loaded).grown, true);
  key(loaded, "Escape");
  assert.deepEqual(calls.slice(2), [["size", 321, 720], ["move", 900, 40]]);
  assert.equal(view(loaded).grown, false);
  // Окно уже на весь монитор — не трогаем, закрытие тоже.
  calls.length = 0;
  Object.assign(win, { screenX: 0, screenY: 25, outerWidth: 1512, outerHeight: 920 });
  press(loaded, nodes.b);
  assert.equal(view(loaded).open, true);
  key(loaded, "Escape");
  assert.deepEqual(calls, []);
});

test("повторные открытия и перезапуск inject.js слоёв не плодят; dispose убирает всё", () => {
  const { loaded, nodes } = page();
  press(loaded, nodes.a);
  loaded.api.viewer.open(2);
  loaded.api.viewer.close();
  loaded.api.viewer.open(0);
  assert.equal(loaded.document.querySelectorAll(VIEW).length, 1);
  const again = loaded.reload();
  assert.equal(again.error, null);
  assert.equal(loaded.document.querySelectorAll(VIEW).length, 0, "прошлый экземпляр унёс свой слой");
  press(loaded, nodes.b);
  press(loaded, nodes.c);
  assert.equal(loaded.document.querySelectorAll(VIEW).length, 1);
  assert.equal(view(loaded).index, 1, "нажатие при открытом просмотре — внутри слоя, не заново");
  loaded.api.dispose();
  assert.equal(loaded.document.querySelectorAll(VIEW).length, 0);
  assert.equal(loaded.counters.listeners, 0, "подписки слоя и ленты сняты");
  assert.equal(key(loaded, "Escape"), false);
  assert.deepEqual(press(loaded, nodes.a), [false, false, false]);
});

test("на чужой странице нажатие по картинке не трогаем", () => {
  const { loaded, nodes } = page({ href: "file:///Applications/Claude.app/main_window/index.html" });
  assert.deepEqual(press(loaded, nodes.a), [false, false, false]);
  assert.equal(view(loaded).open, false);
  assert.equal(plain(loaded.inner.photoList()).length, 0);
});
