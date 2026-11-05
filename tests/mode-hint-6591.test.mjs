// #6591 (раздел 12з² inject.js): подсказка PMP над кнопкой режима под полем. Мышь 0,6 с на кнопке (или фокус по Tab) —
// карточка: пять режимов, что делает каждый, текущий выделен, внизу «в Auto „не могу“ → Ask и Allow». Уходит, когда
// мышь ушла, по нажатию и по Escape (Escape дальше не идёт); при открытом меню её нет; меню Claude открывается как
// раньше — нажатие не гасится. Пока мышь на кнопке, своей подсказки браузера (title) у неё нет.
// Стаб событий не всплывает: мышь и фокус — документу, клавиши и нажатие — окну, с нужной целью в target.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CARD = "#myclaude-mode-hint";
const HOLD = "data-myclaude-mode-hint";
const OPEN = "data-myclaude-mode-hint-open";

const page = ({ mode = "Auto mode", width = 1200 } = {}) => {
  const loaded = loadInject({
    title: "Trelvis", href: "https://claude.ai/epitaxy/local_hint-6591",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    geometry: { viewport: { width, height: 800 } },
    html: dom => {
      const side = width > 600 ? 100 : 10;
      const parts = dom.composer({ top: 600, left: side, width: width - side * 2 });
      parts.chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: { left: side, top: 744, width: width - side * 2, height: 28 } });
      const left = parts.chin.add("div", { rect: { left: side, top: 748, width: 80, height: 20 } });
      parts.plus = left.add("button", { attrs: { "aria-label": "Add files" }, rect: { left: side, top: 750, width: 16, height: 16 } });
      parts.mode = left.add("button", { attrs: { "aria-haspopup": "menu" }, rect: { left: side + 30, top: 750, width: 24, height: 16 } });
      parts.modeText = dom.leaf(parts.mode, "span", mode);
      const right = parts.chin.add("div", { rect: { left: width - side - 120, top: 748, width: 120, height: 20 } });
      parts.model = right.add("button", { attrs: { "data-testid": "epitaxy-cds-model-selector", "aria-label": "Model: Opus 5.5", "aria-haspopup": "menu" }, rect: { left: width - side - 120, top: 750, width: 60, height: 16 } });
      dom.leaf(parts.model, "span", "Opus 5.5");
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return loaded;
};
const card = loaded => loaded.dom.query(CARD);
const shown = loaded => card(loaded)?.style.getPropertyValue("display") === "block";
const rows = loaded => [...card(loaded).children].filter(node => node.className === "r");
const current = loaded => rows(loaded).filter(row => row.getAttribute("aria-current") === "true").map(row => row.dataset.mode);
const view = loaded => plain(loaded.api.status().modeHint);
const over = (loaded, target, extra = {}) => loaded.document.dispatchEvent({ type: "pointerover", target, isTrusted: true, ...extra });
const out = (loaded, target, relatedTarget = null) => loaded.document.dispatchEvent({ type: "pointerout", target, relatedTarget, isTrusted: true });
const key = (loaded, name, target) => loaded.win.dispatchEvent({ type: "keydown", key: name, target: target ?? loaded.parts.editor, isTrusted: true, cancelable: true });
const press = (loaded, target) => loaded.win.dispatchEvent({ type: "pointerdown", target, button: 0, isTrusted: true, cancelable: true });
// Срок наведения: таймер раздела стоит на 0,6 с — проверяем срок и прогоняем ровно его.
const fireHint = loaded => {
  const id = loaded.inner.modeHint.timer;
  assert.ok(id, "наведение не взвело таймер карточки");
  const { fn, ms } = loaded.dom.timers.get(id);
  assert.equal(ms, 600, "карточка — через 0,6 с наведения");
  // Как в браузере: сработавший таймер больше не числится.
  loaded.win.clearTimeout(id);
  fn();
};
const watch = loaded => { const id = loaded.inner.modeHint.watch; assert.ok(id, "у видимой карточки нет сверки"); loaded.dom.fire(id); };
const layout = loaded => { loaded.dom.fireKind("timeout"); loaded.dom.fireKind("raf"); };
// Проход раскладки посреди наведения: ввод в поле зовёт scheduleLayout (resize не годится — он отпускает кнопку).
const relayout = loaded => { loaded.document.dispatchEvent({ type: "input", target: loaded.parts.editor }); layout(loaded); };

test("#6591: наведение 0,6 с — карточка с пятью режимами над кнопкой, текущий (Au) выделен, внизу совет про Ask и Allow", () => {
  const loaded = page();
  const { mode, modeText } = loaded.parts;
  over(loaded, modeText);
  assert.equal(shown(loaded), false, "карточка не ждёт 0,6 с");
  fireHint(loaded);
  assert.equal(shown(loaded), true);
  assert.deepEqual(rows(loaded).map(row => row.querySelector("b").textContent),
    ["Ask permissions", "Accept edits", "Plan mode", "Auto mode", "Bypass permissions"]);
  assert.deepEqual(rows(loaded).map(row => row.querySelector("i").textContent), ["As", "Ac", "Pl", "Au", "Bypass"], "код — тот же, что PMP пишет на кнопке");
  assert.deepEqual(current(loaded), ["Au"], "выделен текущий режим Auto");
  const text = card(loaded).textContent;
  assert.match(text, /Спрашивает разрешение на каждое действие/);
  assert.match(text, /робот-сторож молча запрещает/);
  assert.match(text, /Claude в Auto говорит «не могу»\? Поставь Ask permissions и жми Allow$/, "последняя строка — совет");
  assert.doesNotMatch(text, /…/, "без многоточий");
  assert.equal(card(loaded).getAttribute("role"), "tooltip", "не накладка: сторож Esc и Bypass её не считают меню");
  // Над кнопкой, не шире колонки поля.
  const style = card(loaded).style;
  assert.equal(style.getPropertyValue("bottom"), `${800 - 750 + 6}px`);
  assert.equal(style.getPropertyValue("width"), "320px");
  assert.equal(style.getPropertyValue("left"), "100px", "не левее колонки");
  assert.equal(loaded.document.documentElement.hasAttribute(OPEN), true, "подсказки Claude под карточкой не прячутся");
  assert.deepEqual(view(loaded), { shown: true, mode: "Au", shows: 1, escapes: 0 });
  assert.equal(mode.hasAttribute(HOLD), true);
});

test("#6591: узкое окно 330 — карточка не шире колонки и в её пределах", () => {
  const loaded = page({ width: 330 });
  over(loaded, loaded.parts.mode);
  fireHint(loaded);
  assert.equal(shown(loaded), true);
  const style = card(loaded).style;
  const left = parseFloat(style.getPropertyValue("left"));
  const width = parseFloat(style.getPropertyValue("width"));
  assert.equal(width, 310, "ширина — колонка поля (330 − 2·10)");
  assert.ok(left >= 10 && left + width <= 320, `карточка вылезла за колонку: ${left} + ${width}`);
});

test("#6591: открытое меню — карточки нет; открылось при ней — уходит; нажатие гасит её, а меню Claude открывается как раньше", () => {
  // Меню уже открыто, когда истекли 0,6 с.
  const opened = page();
  const menu = opened.document.body.add("div", { attrs: { role: "menu" }, rect: { left: 100, top: 500, width: 200, height: 200 } });
  over(opened, opened.parts.mode);
  fireHint(opened);
  assert.equal(shown(opened), false, "карточка поверх открытого меню");
  menu.remove();
  // Кнопка режима сама говорит, что её меню открыто.
  const expanded = page();
  expanded.parts.mode.setAttribute("aria-expanded", "true");
  over(expanded, expanded.parts.mode);
  fireHint(expanded);
  assert.equal(shown(expanded), false);
  // Меню открылось, пока карточка видна (⇧Tab, сторож режима) — сверка её снимает и до ухода мыши не возвращает.
  const later = page();
  over(later, later.parts.mode);
  fireHint(later);
  assert.equal(shown(later), true);
  later.document.body.add("div", { attrs: { role: "listbox" }, rect: { left: 100, top: 500, width: 200, height: 200 } });
  watch(later);
  assert.equal(shown(later), false, "карточка осталась при открытом меню");
  over(later, later.parts.modeText);
  assert.equal(later.inner.modeHint.timer, 0, "вернулась, пока мышь на кнопке");
  // Нажатие: карточка уходит, событие не гасится — меню Claude откроет как раньше.
  const click = page();
  over(click, click.parts.modeText);
  fireHint(click);
  assert.equal(press(click, click.parts.modeText), true, "нажатие по кнопке режима погашено");
  assert.equal(shown(click), false);
  over(click, click.parts.mode);
  assert.equal(click.inner.modeHint.timer, 0, "карточка снова взвелась поверх меню");
  // Мышь ушла и вернулась — снова карточка.
  out(click, click.parts.mode, click.parts.plus);
  over(click, click.parts.mode);
  fireHint(click);
  assert.equal(shown(click), true);
});

test("#6591: Escape закрывает карточку и дальше не идёт; без карточки Escape — как раньше", () => {
  const loaded = page();
  let later = 0;
  // Чужой слушатель окна после раздела: до него Escape карточки дойти не должен.
  loaded.win.addEventListener("keydown", event => { if (event.key === "Escape") later += 1; }, true);
  const blocked = () => plain(loaded.api.status()).escapesBlocked;
  over(loaded, loaded.parts.mode);
  fireHint(loaded);
  const before = blocked();
  assert.equal(key(loaded, "Escape"), false, "Escape карточки не погашен — дошёл бы до Claude");
  assert.equal(shown(loaded), false);
  assert.equal(blocked(), before, "Escape карточки ушёл сторожу Esc");
  assert.equal(later, 0, "Escape карточки ушёл дальше по окну");
  assert.equal(view(loaded).escapes, 1);
  over(loaded, loaded.parts.modeText);
  assert.equal(loaded.inner.modeHint.timer, 0, "после Escape карточка вернулась без ухода мыши");
  // Карточки нет — Escape не наш: его, как и раньше, глотает сторож Esc (раздел 16).
  key(loaded, "Escape");
  assert.equal(blocked(), before + 1);
  assert.equal(view(loaded).escapes, 1);
  // Escape до срока: карточка не появится, сам Escape — не наш.
  const early = page();
  over(early, early.parts.mode);
  key(early, "Escape");
  assert.equal(early.inner.modeHint.timer, 0, "Escape до срока не отменил карточку");
  assert.equal(view(early).escapes, 0);
  // Любая другая клавиша (пишут в поле) тоже убирает карточку, но не гасится.
  const typing = page();
  over(typing, typing.parts.mode);
  fireHint(typing);
  assert.equal(key(typing, "a"), true, "буква в поле погашена");
  assert.equal(shown(typing), false);
});

test("#6591: выделен текущий режим — Au → Auto mode; сменился при открытой карточке — выделение за ним; Bypass — «Bp»", () => {
  const loaded = page();
  over(loaded, loaded.parts.mode);
  fireHint(loaded);
  assert.deepEqual(current(loaded), ["Au"]);
  loaded.dom.retext(loaded.parts.modeText, "Accept edits");
  watch(loaded);
  assert.deepEqual(current(loaded), ["Ac"]);
  assert.equal(view(loaded).mode, "Ac");
  const bypass = page({ mode: "Bypass permissions" });
  over(bypass, bypass.parts.mode);
  fireHint(bypass);
  assert.deepEqual(current(bypass), ["By"]);
  assert.equal(rows(bypass).find(row => row.dataset.mode === "By").querySelector("i").textContent, "Bypass");
  const ask = page({ mode: "Ask permissions" });
  over(ask, ask.parts.mode);
  fireHint(ask);
  assert.deepEqual(current(ask), ["As"]);
});

test("#6591: мышь ушла — карточки нет, title кнопки вернулся; пока мышь на кнопке — title снят; чужие кнопки и «как мышью» сторожей — мимо", () => {
  const loaded = page();
  const { mode, modeText, model, plus } = loaded.parts;
  layout(loaded);
  assert.equal(mode.getAttribute("title"), "Auto mode", "подсказка полным именем (WF195) не поставлена");
  over(loaded, modeText);
  assert.equal(mode.getAttribute("title"), null, "под карточкой ещё и подсказка браузера");
  fireHint(loaded);
  relayout(loaded);
  assert.equal(mode.getAttribute("title"), null, "проход раскладки вернул подсказку браузера под карточку");
  assert.equal(shown(loaded), true);
  // Ход мыши внутри кнопки — не уход.
  out(loaded, modeText, mode);
  assert.equal(shown(loaded), true, "карточка ушла от хода мыши внутри кнопки");
  out(loaded, mode, plus);
  assert.equal(shown(loaded), false);
  assert.equal(mode.hasAttribute(HOLD), false);
  assert.equal(loaded.document.documentElement.hasAttribute(OPEN), false);
  layout(loaded);
  assert.equal(mode.getAttribute("title"), "Auto mode", "подсказка браузера не вернулась");
  // Модель — не кнопка режима; синтетический pointerover (pressLikeMouse сторожей) — не рука.
  over(loaded, model);
  assert.equal(loaded.inner.modeHint.timer, 0);
  over(loaded, mode, { isTrusted: false });
  assert.equal(loaded.inner.modeHint.timer, 0, "«как мышью» сторожа взвёл карточку");
  assert.equal(view(loaded).shows, 1);
});

test("#6591: фокус по Tab — карточка; уход фокуса — нет; фокус после нажатия (меню вернуло его) — не просьба", () => {
  const loaded = page();
  const { mode } = loaded.parts;
  key(loaded, "Tab");
  loaded.document.dispatchEvent({ type: "focusin", target: mode, isTrusted: true });
  fireHint(loaded);
  assert.equal(shown(loaded), true);
  loaded.document.dispatchEvent({ type: "focusout", target: mode, isTrusted: true });
  assert.equal(shown(loaded), false);
  press(loaded, loaded.parts.editor);
  loaded.document.dispatchEvent({ type: "focusin", target: mode, isTrusted: true });
  assert.equal(loaded.inner.modeHint.timer, 0, "фокус без Tab взвёл карточку");
});

test("#6591: dispose снимает карточку, метку кнопки и таймеры; повторная установка — одна карточка", () => {
  const loaded = page();
  over(loaded, loaded.parts.mode);
  fireHint(loaded);
  const again = loaded.reload();
  assert.equal(again.error, null, String(again.error?.stack ?? again.error));
  assert.equal(loaded.dom.queryAll(CARD).length, 1);
  assert.equal(shown(loaded), false);
  assert.equal(loaded.parts.mode.hasAttribute(HOLD), false);
  assert.equal(loaded.document.documentElement.hasAttribute(OPEN), false);
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(CARD).length, 0);
});
