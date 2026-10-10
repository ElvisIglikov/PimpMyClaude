// Выезжающий список чатов Claude 2.2553.13 и наши полоски (раздел 4 inject.js, WF82, #7097).
//
// Скрин Элвиса 22.09: у свёрнутой левой панели Claude по наведению выдвигает её
// поверх ленты и поля ввода (`.dframe-root[data-collapsed][data-hovering]`), а
// сквозь панель видны ручка поля, полоса прогресса и нижний дубль полоски. Фон у
// панели непрозрачный — поверх неё рисовались НАШИ узлы: они живут в body над
// всем деревом Claude. Пока панель выдвинута, их прячет одно правило CSS.
// Стаб `:has()` не исполняет, поэтому проверяется контракт правила в <style>.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const OURS = [
  "myclaude-input-handle", "myclaude-super-top", "myclaude-super-bottom",
  "myclaude-progress-bar", "myclaude-progress-tip", "myclaude-side-rail", "myclaude-mic",
];

test("пока список чатов выдвинут, наши полоски спрятаны — visibility, а не display", () => {
  const loaded = loadInject({ html: "composer", title: "Trelvis" });
  const css = String(loaded.dom.query("#myclaude-input-handle-style").textContent ?? "");
  const rule = css.split("\n").find(line => line.includes("[data-collapsed][data-hovering]"));
  assert.ok(rule, "правила под выезжающую панель нет");
  assert.ok(rule.startsWith("body:has(.dframe-root[data-collapsed][data-hovering])"), "условие — атрибуты корня Claude");
  for (const id of OURS) {
    assert.ok(rule.includes(`#${id}`), `#${id} остался бы поверх панели`);
    assert.ok(loaded.dom.query(`#${id}`), `узла #${id} на странице нет — правило целится в пустоту`);
  }
  // display полосок ведёт раскладка (раздел 9): спор за него вернул бы их поверх панели.
  assert.match(rule, /\{visibility:hidden !important\}$/);
  // Рамку окна не прячем: это кромка всего окна, а не узел над полем.
  assert.ok(!rule.includes("myclaude-window-frame"));
});

// WF144 (класс WF136 п.5–6, «наши слои уступают меню»): пока открыто меню или список
// Claude, наши слои над полем мышь не ловят — правилом CSS, тем же кадром, а не на
// проходе раскладки; иначе нажатие по пункту меню над ручкой сворачивало поле.
test("WF144: при открытом меню Claude ручка, дубли, микрофон, галерея и PMP пропускают мышь", () => {
  const loaded = loadInject({ html: "composer", title: "Trelvis" });
  const css = String(loaded.dom.query("#myclaude-input-handle-style").textContent ?? "");
  const rule = css.split("\n").find(line => line.startsWith('body:has([role="menu"],[role="listbox"]') && line.includes(") :is(#myclaude-input-handle"));
  assert.ok(rule, "правила «уступить меню» нет");
  for (const id of ["myclaude-input-handle", "myclaude-super-top", "myclaude-super-bottom", "myclaude-mic", "myclaude-gallery", "myclaude-pmp"]) {
    assert.ok(rule.includes(`#${id}`), `#${id} ловил бы нажатие по пункту меню`);
  }
  assert.match(rule, /\) \*\{pointer-events:none !important\}$/, "и их дети тоже — у кнопок свой pointer-events");
});

// WF179 (#9205, снимок 09.10 02:30: ячейки полосы Рика читались сквозь панель «Контекст / лимиты»
// Claude — `[role="dialog"][data-cds="Popover"]`): наши слои уступают не только меню и спискам, но и
// диалогам и поповерам Claude. Полоса Рика, её карточки и полоска 2б — прячутся; ручка, дубли, рейка,
// микрофон, галерея, PMP — пропускают мышь. Свои диалоги (#myclaude-…) не в счёт, подсказки — тоже.
test("WF179: открыт поповер или диалог Claude — полоса Рика, карточки и полоска 2б спрятаны, наши кнопки пропускают мышь", () => {
  const loaded = loadInject({ html: "composer", title: "Trelvis" });
  const css = String(loaded.dom.query("#myclaude-input-handle-style").textContent ?? "");
  const hide = css.split("\n").find(line => line.startsWith("body:has(") && line.includes(":is(#myclaude-rick-cells"));
  assert.ok(hide, "правила «уступить поповеру» у полосы Рика нет");
  assert.match(hide, /\{visibility:hidden!important\}$/);
  for (const id of ["myclaude-rick-cells", "myclaude-rick-card", "myclaude-rick-flow", "myclaude-progress-bar", "myclaude-progress-tip", "myclaude-progress-card", "myclaude-progress-tail"]) {
    assert.ok(hide.includes(`#${id}`), `#${id} рисовался бы поверх поповера Claude`);
  }
  const pass = css.split("\n").find(line => line.startsWith('body:has([role="menu"]') && line.includes(") :is(#myclaude-input-handle"));
  for (const id of ["myclaude-input-handle", "myclaude-gallery", "myclaude-pmp", "myclaude-mic", "myclaude-side-rail"]) assert.ok(pass.includes(`#${id}`), id);
  // Оба правила — одним условием.
  const popup = hide.match(/^body:has\((.*?)\) :is\(/)?.[1];
  assert.ok(popup && pass.startsWith(`body:has(${popup}) `), "условия правил разошлись");
  // Условие ловит панель лимитов, меню, список, открытый Radix-поповер; не ловит свои диалоги и подсказки.
  const body = loaded.document.body;
  const hits = attrs => { const node = body.add("div", { attrs }); const hit = Boolean(body.querySelector(popup)); node.remove(); return hit; };
  assert.equal(hits({ role: "dialog", "data-cds": "Popover" }), true, "панель лимитов");
  assert.equal(hits({ role: "menu" }), true);
  assert.equal(hits({ role: "listbox" }), true);
  assert.equal(hits({ "data-cds": "Popover" }), true, "поповер без роли");
  assert.equal(hits({ role: "dialog", id: "myclaude-photo-view" }), false, "свой просмотр фото");
  assert.equal(hits({ role: "tooltip" }), false, "подсказка не прячет полосу");
  const wrap = body.add("div", { attrs: { "data-radix-popper-content-wrapper": "" } });
  const tip = wrap.add("div", { attrs: { "data-state": "delayed-open" } });
  assert.equal(Boolean(body.querySelector(popup)), false, "подсказка Radix — не в счёт");
  tip.setAttribute("data-state", "open");
  assert.equal(Boolean(body.querySelector(popup)), true, "открытый поповер Radix");
  wrap.remove();
});
