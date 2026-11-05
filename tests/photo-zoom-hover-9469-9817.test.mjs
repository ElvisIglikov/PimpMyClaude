// #9469: в просмотре фото (раздел 12л) — масштаб колесом и щипком от точки под курсором, полоса
// «− 37 % + По ширине», клавиши + − 0 и ↑ ↓, двойной клик — 100 % и обратно.
// #9817 (слово Элвиса 11.10): «навёл, подержал, чуть-чуть, он так раскрылся… на следующем тоже
// долго подержать… Не моментально». Подержал курсор на фото — «подсмотр», ушёл с плитки — закрыто.
// Стаб раскладку не считает: рамки фото и окна просмотра ставит тест.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const photo = (parent, src, { w = 640, h = 1440, rect = { left: 0, top: 0, width: 71, height: 160 } } = {}) => {
  const img = parent.add("img", { attrs: { src } });
  img.naturalWidth = w;
  img.naturalHeight = h;
  img.rect = rect;
  return img;
};

const page = ({ hasFocus = true } = {}) => {
  const nodes = {};
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_zoom",
    hasFocus,
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      const row = feed.add("div", { class: "group/message-row" });
      nodes.tileA = row.add("span", { attrs: { role: "button", tabindex: "0" } });
      nodes.tileA.rect = { left: 100, top: 100, width: 71, height: 160 };
      nodes.a = photo(nodes.tileA, "data:image/png;base64,AAA", { rect: { left: 100, top: 100, width: 71, height: 160 } });
      nodes.tileB = row.add("span", { attrs: { role: "button", tabindex: "0" } });
      nodes.tileB.rect = { left: 200, top: 100, width: 71, height: 160 };
      nodes.b = photo(nodes.tileB, "data:image/png;base64,BBB", { rect: { left: 200, top: 100, width: 71, height: 160 } });
      nodes.text = row.add("p");
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return { loaded, nodes };
};

const view = loaded => plain(loaded.api.viewer.state());
const parts = loaded => loaded.inner.photoState.parts;
const layer = loaded => loaded.document.querySelector("#myclaude-photo-view");
const status = loaded => plain(loaded.api.status().photo);
// Окно стоит на экране в (1000, 50): screen = client + сдвиг.
const OFF = { x: 1000, y: 50 };
const move = (loaded, target, clientX, clientY, extra = {}) => loaded.document.dispatchEvent({
  type: "pointermove", target, pointerType: "mouse", clientX, clientY,
  screenX: clientX + OFF.x, screenY: clientY + OFF.y, buttons: 0, ...extra,
});
const hoverTimer = loaded => loaded.inner.photoHover.timer;
const fireHover = loaded => { const id = hoverTimer(loaded); assert.ok(id, "отсчёт идёт"); loaded.dom.fire(id); };

// Открытое фото 640×1440 в окне 1000×720: целиком — 320×720.
const opened = () => {
  const { loaded, nodes } = page();
  loaded.api.viewer.open(0);
  const { img, stage } = parts(loaded);
  img.naturalWidth = 640;
  img.naturalHeight = 1440;
  stage.rect = { left: 0, top: 0, width: 1000, height: 720 };
  img.rect = { left: 340, top: 0, width: 320, height: 720 };
  loaded.inner.photoState.openedAt = -Infinity;
  return { loaded, nodes, img, stage };
};
const wheel = (loaded, extra) => !layer(loaded).dispatchEvent({ type: "wheel", deltaX: 0, deltaY: 0, clientX: 500, clientY: 360, ...extra });
const tap = (loaded, target) => layer(loaded).dispatchEvent({ type: "click", target, detail: 1 });
const key = (loaded, code, keyName, extra = {}, type = "keydown") => !loaded.win.dispatchEvent({ type, key: keyName, code, ...extra });

test("#9469 колесо вверх-вниз — масштаб от точки под курсором; вниз у «целиком» — ничего; вбок по увеличенному — сдвиг", () => {
  const { loaded, img, stage } = opened();
  assert.equal(wheel(loaded, { deltaY: 100 }), true, "колесо глотается: лента под просмотром не едет");
  assert.equal(view(loaded).zoom, false);
  // e^(0,0025·277,26) = 2 — вдвое.
  assert.equal(wheel(loaded, { deltaY: -277.26 }), true);
  assert.equal(view(loaded).zoom, true);
  assert.equal(img.style.getPropertyValue("width"), "640px");
  assert.equal(stage.style.getPropertyValue("overflow"), "auto");
  // Строки колеса (deltaMode 1) — по 40 px.
  img.rect = { left: 180, top: 0, width: 640, height: 1440 };
  wheel(loaded, { deltaY: -3, deltaMode: 1 });
  assert.equal(img.style.getPropertyValue("width"), `${Math.round(640 * Math.exp(0.3))}px`);
  const index = view(loaded).index;
  stage.scrollLeft = 0;
  wheel(loaded, { deltaX: 80, deltaY: 2 });
  wheel(loaded, { deltaX: 120, deltaY: 0 });
  assert.equal(stage.scrollLeft, 200, "вбок по увеличенному — сдвиг");
  assert.equal(view(loaded).index, index, "и не листание");
  img.rect = { left: 0, top: 0, width: 864, height: 1944 };
  wheel(loaded, { deltaY: 2000 });
  assert.equal(view(loaded).zoom, false, "ниже «целиком» — снова целиком");
});

test("#9469 полоса: «− 50 % +», «По ширине» ⇄ «Целиком», погашенная кнопка не жмётся и не закрывает", () => {
  const { loaded, img, stage } = opened();
  const { bar, zoomOut, zoomIn, pct, wide, count } = parts(loaded);
  loaded.inner.photoState.parts.img.dispatchEvent({ type: "load" });
  assert.equal(pct.textContent, "50 %", "проценты — от натурального размера");
  assert.equal(zoomOut.getAttribute("aria-disabled"), "true", "меньше «целиком» некуда");
  assert.equal(zoomIn.getAttribute("aria-disabled"), null);
  assert.equal(wide.textContent, "По ширине");
  assert.equal(count.textContent, "1 / 2");
  tap(loaded, zoomOut);
  assert.deepEqual([view(loaded).open, view(loaded).zoom], [true, false], "погашенная «−» ничего не делает и не закрывает");
  tap(loaded, bar);
  assert.equal(view(loaded).open, true, "клик по самой полосе — не клик по фону");
  tap(loaded, zoomIn);
  assert.equal(img.style.getPropertyValue("width"), "480px", "+ — ×1,5");
  img.rect = { left: 260, top: 0, width: 480, height: 1080 };
  loaded.win.dispatchEvent({ type: "resize" });
  assert.equal(pct.textContent, "75 %");
  assert.equal(zoomOut.getAttribute("aria-disabled"), null);
  tap(loaded, zoomOut);
  assert.equal(view(loaded).zoom, false, "− обратно к «целиком»");
  // «По ширине»: во всю ширину окна, верх — у верха.
  img.rect = { left: 340, top: 0, width: 320, height: 720 };
  stage.scrollTop = 300;
  tap(loaded, wide);
  assert.equal(img.style.getPropertyValue("width"), "1000px");
  assert.equal(stage.scrollTop, 0);
  img.rect = { left: 0, top: 0, width: 1000, height: 2250 };
  loaded.win.dispatchEvent({ type: "resize" });
  assert.equal(wide.textContent, "Целиком");
  tap(loaded, wide);
  assert.equal(view(loaded).zoom, false);
  img.rect = { left: 340, top: 0, width: 320, height: 720 };
  loaded.win.dispatchEvent({ type: "resize" });
  assert.equal(wide.textContent, "По ширине");
  // «37 %» — как двойной клик: 100 % и обратно.
  tap(loaded, pct);
  assert.equal(view(loaded).zoom, true);
  assert.equal(img.style.getPropertyValue("width"), "auto", "100 % — натуральный размер");
  tap(loaded, pct);
  assert.equal(view(loaded).zoom, false);
  // Широкая картинка в узком окне и так во всю ширину — «По ширине» гаснет.
  img.naturalWidth = 2000;
  img.naturalHeight = 1000;
  img.rect = { left: 0, top: 235, width: 1000, height: 500 };
  loaded.win.dispatchEvent({ type: "resize" });
  assert.equal(wide.getAttribute("aria-disabled"), "true");
  tap(loaded, wide);
  assert.equal(view(loaded).zoom, false);
  assert.equal(view(loaded).open, true);
});

test("#9469 клавиши: + − 0 в любой раскладке, ↑ ↓ двигают увеличенное, ⌘+ — масштаб Claude, не наш", () => {
  const { loaded, img, stage } = opened();
  const claude = [];
  loaded.win.addEventListener("keydown", event => claude.push(event.code));
  assert.equal(key(loaded, "Equal", "="), true);
  assert.equal(img.style.getPropertyValue("width"), "480px");
  img.rect = { left: 260, top: 0, width: 480, height: 1080 };
  stage.scrollTop = 0;
  assert.equal(key(loaded, "", "ArrowDown"), true);
  assert.equal(stage.scrollTop, 108, "↓ — 15 % высоты окна");
  key(loaded, "", "ArrowUp");
  assert.equal(stage.scrollTop, 0);
  assert.equal(key(loaded, "Minus", "-"), true);
  assert.equal(view(loaded).zoom, false);
  key(loaded, "NumpadAdd", "+");
  assert.equal(view(loaded).zoom, true);
  assert.equal(key(loaded, "Digit0", "0"), true);
  assert.equal(view(loaded).zoom, false, "0 — целиком");
  assert.equal(key(loaded, "Equal", "=", { metaKey: true }), false, "⌘+ не трогаем");
  assert.equal(view(loaded).zoom, false);
  assert.equal(key(loaded, "Equal", "=", {}, "keyup"), true, "отпускание своей клавиши тоже наше");
  assert.deepEqual(claude, ["Equal"]);
  // Просмотр закрыт — + − 0 снова Claude.
  key(loaded, "", "Escape");
  assert.equal(key(loaded, "Equal", "="), false);
});

test("#9817 подержал курсор на фото — раскрылось «подсмотром»: фокус в поле, кнопок нет, подсказка", () => {
  const { loaded, nodes } = page();
  const editor = loaded.document.querySelector(".ProseMirror");
  editor.focus();
  move(loaded, nodes.a, 120, 150);
  assert.ok(hoverTimer(loaded), "наведение ставит отсчёт");
  assert.equal(loaded.dom.timers.get(hoverTimer(loaded)).ms, 600, "не моментально — 0,6 с");
  assert.equal(view(loaded).open, false);
  fireHover(loaded);
  assert.deepEqual(view(loaded), { open: true, index: 0, total: 2, zoom: false, grown: false });
  assert.equal(status(loaded).peek, true);
  assert.equal(status(loaded).hoverOpens, 1);
  assert.equal(layer(loaded).getAttribute("data-myclaude-photo-peek"), "");
  assert.equal(loaded.document.activeElement, editor, "фокус остался в поле ввода");
  const css = [...loaded.document.querySelectorAll("style")].map(node => node.textContent).join("\n");
  assert.match(css, /#myclaude-photo-view\[data-myclaude-photo-peek\] button\{display:none !important\}/);
  assert.match(css, /#myclaude-photo-view:not\(\[data-myclaude-photo-peek\]\) \[data-myclaude-photo-bar-hint\]\{display:none !important\}/);
});

test("#9817 отсчёт: дрожь руки не сбивает, сдвиг дальше 6 px — заново; ушёл, колесо, клавиша, нажатие, зажатая кнопка, чужой фокус — отмена", () => {
  const { loaded, nodes } = page();
  move(loaded, nodes.a, 120, 150);
  const first = hoverTimer(loaded);
  move(loaded, nodes.a, 123, 153);
  assert.equal(hoverTimer(loaded), first, "дрожь — тот же отсчёт");
  move(loaded, nodes.tileA, 130, 150);
  assert.notEqual(hoverTimer(loaded), first, "сдвинулся — держать заново");
  move(loaded, nodes.text, 300, 150);
  assert.equal(hoverTimer(loaded), 0, "ушёл с фото — отмена");
  move(loaded, nodes.a, 120, 150);
  assert.ok(hoverTimer(loaded));
  loaded.win.dispatchEvent({ type: "wheel", target: nodes.a, deltaY: 40, deltaX: 0 });
  assert.equal(hoverTimer(loaded), 0, "колесо — отмена");
  // Лента уехала под неподвижным курсором — событие с теми же экранными точками не в счёт.
  move(loaded, nodes.a, 120, 150);
  assert.equal(hoverTimer(loaded), 0, "без движения мыши отсчёт не встаёт");
  move(loaded, nodes.a, 121, 150);
  assert.ok(hoverTimer(loaded));
  loaded.win.dispatchEvent({ type: "keydown", key: "a", code: "KeyA" });
  assert.equal(hoverTimer(loaded), 0, "клавиша — отмена");
  move(loaded, nodes.a, 122, 150);
  loaded.document.dispatchEvent({ type: "pointerdown", target: nodes.a, button: 0 });
  assert.equal(hoverTimer(loaded), 0, "нажатие — отмена (дальше обычный клик)");
  move(loaded, nodes.a, 125, 150, { buttons: 1 });
  assert.equal(hoverTimer(loaded), 0, "с зажатой кнопкой — перетаскивание, не наведение");
  move(loaded, nodes.a, 128, 150);
  loaded.document.dispatchEvent({ type: "pointerout", target: nodes.a, relatedTarget: null });
  assert.equal(hoverTimer(loaded), 0, "ушёл из окна — отмена");
  loaded.win.__hasFocus = false;
  move(loaded, nodes.a, 131, 150);
  assert.equal(hoverTimer(loaded), 0, "окно не в фокусе — не раскрываем");
});

test("#9817 ушёл с плитки — закрыто; на соседней — снова подержать; клик оставляет открытым", () => {
  const { loaded, nodes } = page();
  move(loaded, nodes.a, 120, 150);
  fireHover(loaded);
  assert.equal(status(loaded).peek, true);
  const cover = layer(loaded);
  // Курсор в пределах плитки (+12 px по экрану) — смотрим дальше.
  move(loaded, cover, 175, 255);
  assert.equal(view(loaded).open, true);
  move(loaded, cover, 190, 150);
  assert.equal(view(loaded).open, false, "ушёл с плитки — закрыто");
  // Сразу на соседнюю — не моментально: снова отсчёт.
  move(loaded, nodes.b, 220, 150);
  assert.ok(hoverTimer(loaded));
  assert.equal(view(loaded).open, false);
  fireHover(loaded);
  assert.equal(view(loaded).index, 1);
  assert.equal(status(loaded).hoverOpens, 2);
  // Клик — оставить: не закрывает, не увеличивает, уход больше не закрывает.
  layer(loaded).dispatchEvent({ type: "click", target: parts(loaded).stage, detail: 1 });
  assert.deepEqual([view(loaded).open, view(loaded).zoom, status(loaded).peek], [true, false, false]);
  assert.equal(layer(loaded).getAttribute("data-myclaude-photo-peek"), null);
  move(loaded, cover, 600, 600);
  assert.equal(view(loaded).open, true);
  layer(loaded).dispatchEvent({ type: "click", target: parts(loaded).stage, detail: 1 });
  assert.equal(view(loaded).open, false, "дальше — как обычно: клик по фону закрывает");
});

test("#9817 движение, уведшее с плитки, было последним и уже над соседним фото — отсчёт идёт и ему", () => {
  const { loaded, nodes } = page();
  move(loaded, nodes.a, 120, 150);
  fireHover(loaded);
  // Курсор встал на соседнюю плитку одним движением: событие пришло ещё в слой просмотра.
  loaded.document.elementFromPoint = (x, y) => (x === 220 && y === 150 ? nodes.b : null);
  move(loaded, layer(loaded), 220, 150);
  assert.equal(view(loaded).open, false, "ушёл — закрыто");
  assert.equal(loaded.dom.timers.get(hoverTimer(loaded)).ms, 600, "не моментально");
  fireHover(loaded);
  assert.deepEqual([view(loaded).open, view(loaded).index, status(loaded).peek], [true, 1, true]);
  // Ушёл в пустое место — отсчёт по точке ничего не раскрывает.
  move(loaded, layer(loaded), 400, 600);
  assert.equal(view(loaded).open, false);
  fireHover(loaded);
  assert.equal(view(loaded).open, false);
});

test("#9817 в «подсмотре»: стрелка и колесо оставляют открытым, Esc закрывает, чужая клавиша закрывает и уходит в поле", () => {
  const { loaded, nodes } = page();
  move(loaded, nodes.a, 120, 150);
  fireHover(loaded);
  assert.equal(!loaded.win.dispatchEvent({ type: "keydown", key: "ArrowRight", code: "ArrowRight" }), true);
  assert.deepEqual([view(loaded).index, status(loaded).peek], [1, false]);
  key(loaded, "", "Escape");
  assert.equal(view(loaded).open, false);
  // Закрыл Esc, курсор на том же фото: дрожь не раскрывает снова.
  move(loaded, nodes.a, 121, 150);
  assert.equal(hoverTimer(loaded), 0);
  move(loaded, nodes.text, 300, 150);
  move(loaded, nodes.a, 120, 150);
  assert.ok(hoverTimer(loaded), "увёл и вернул — снова раскрывается");
  fireHover(loaded);
  layer(loaded).dispatchEvent({ type: "wheel", deltaX: 0, deltaY: 10, clientX: 500, clientY: 360 });
  assert.equal(status(loaded).peek, false, "колесо — оставить");
  key(loaded, "", "Escape");
  move(loaded, nodes.text, 300, 150);
  move(loaded, nodes.a, 120, 150);
  fireHover(loaded);
  assert.equal(loaded.win.dispatchEvent({ type: "keydown", key: "п", code: "KeyG" }), true, "буква не наша — едет в поле");
  assert.equal(view(loaded).open, false);
});

test("#9817 лента уехала из-под курсора до конца отсчёта — не раскрываем; dispose снимает отсчёт", () => {
  const { loaded, nodes } = page();
  move(loaded, nodes.a, 120, 150);
  nodes.tileA.rect = { left: 100, top: 400, width: 71, height: 160 };
  fireHover(loaded);
  assert.equal(view(loaded).open, false);
  nodes.tileA.rect = { left: 100, top: 100, width: 71, height: 160 };
  move(loaded, nodes.a, 125, 150);
  assert.ok(hoverTimer(loaded));
  const live = loaded.dom.count("timeout");
  loaded.api.dispose();
  assert.equal(hoverTimer(loaded), 0);
  assert.ok(loaded.dom.count("timeout") < live);
});
