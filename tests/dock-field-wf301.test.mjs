// WF301 (#11202, #11203; контракт К-DOCK-5 — docs/contracts/590-wf282-dock-size.md): режим «панель + поле» и
// компактные плитки поля в узкой колонке чата.
//
// Слово Элвиса 30.10 ~16:00 (#11202): «один из её режимов должен быть, что отображается панель и поле ввода.
// Одновременно, то есть вот это по серединке убирается… Вот он, классный режим». (#11203): «слишком скриншоты большие…
// Такие же маленькие сделай… больше скриншотов поместится». Замер окна Элвиса 30.10: окно 2518 pt, z ≈ 0,833.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_0f3a9c1e-7b2d-4e6f-8a1b-5c4d3e2f1a0b";
const UP = { ok: true, viewer: "up", docked: true, owner: "this" };
const flush = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };

// Окно: frame — рамка в точках, viewport — CSS px (z = frame[2] / viewport.width). Свёрнутая боковая панель.
const scene = ({ frame, viewport, storage = {} }) => {
  const box = { calls: [] };
  const { width, height } = viewport;
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, geometry: { viewport, frame }, storage: { local: storage },
    html: dom => {
      const rect = (left, top, w, h) => ({ left, top, width: w, height: h });
      const root = dom.document.body.add("div", { class: "dframe-root draggable-none cds-root text-primary", rect: rect(0, 0, width, height) });
      const aside = root.add("aside", { class: "dframe-sidebar df-hub-rail", rect: rect(84, 6, 28, 32) });
      aside.add("div", { class: "df-collapsed-chrome flex items-center", rect: rect(84, 6, 28, 32) })
        .add("button", { class: "cds-reset df-compact-trigger", rect: rect(84, 8, 28, 28),
          attrs: { "data-testid": "sidebar-compact-trigger", "aria-label": "Show sidebar", type: "button" } });
      aside.add("div", { id: "frame-peek-popover", attrs: { "data-testid": "sidebar" }, rect: rect(-4, 0, 254, height) }).computed = { opacity: "0" };
      const host = root.add("main", { class: "dframe-content", rect: rect(0, 0, width, height) })
        .add("div", { class: "dframe-content-inner", rect: rect(0, 0, width, height) })
        .add("div", { class: "dframe-pane-host flex-1 min-h-0 relative isolate", rect: rect(0, 0, width, height) });
      host.add("div", { class: "dframe-pane dframe-pane-primary", rect: rect(0, 0, width, height) })
        .add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" }, rect: rect(8, 0, width - 340, height - 8) })
        .add("div", { attrs: { "data-testid": "transcript-rows" } });
      dom.window.fetch = address => {
        box.calls.push(String(address));
        return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(String(address).includes("/dock?") ? UP : {}) });
      };
      return {};
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.box = box;
  return loaded;
};
const dock = loaded => plain(loaded.api.status().dock);
const byId = (loaded, id) => loaded.document.getElementById(id);
const px = (node, name) => Number.parseFloat(node.style.getPropertyValue(name));
const lastOn = loaded => new URL(loaded.box.calls.filter(url => url.includes("/dock?on=1")).at(-1)).searchParams;
const sizeButton = (loaded, mode) => [...byId(loaded, "myclaude-dock-sizes").children].find(node => node.dataset.mode === mode);
const press = (loaded, node) => {
  for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) {
    const event = { type, target: node, isTrusted: true, bubbles: true, cancelable: true, button: 0, buttons: type.endsWith("down") ? 1 : 0, detail: 1, pointerId: 1 };
    if (loaded.document.dispatchEvent(event)) node.dispatchEvent({ ...event });
  }
};
const opened = async options => {
  const loaded = scene(options);
  await flush();
  press(loaded, byId(loaded, "myclaude-dock-button"));
  await flush();
  assert.equal(dock(loaded).placed, true);
  return loaded;
};
const ownCss = loaded => loaded.dom.queryAll("style").map(style => style.textContent).join("\n");

// Окно Элвиса: 2518 pt, z ≈ 0,833 → 3022 CSS px.
const BIG = { frame: [0, 29, 2518, 690], viewport: { width: 3022, height: 793 } };

test("окно Элвиса 2518 pt: «панель + поле» — панель во всё место, справа колонка чата DOCK_FEED_MIN с полем; рейка видна", async () => {
  const loaded = await opened(BIG);
  press(loaded, sizeButton(loaded, "full"));
  await flush();
  const z = 2518 / 3022;
  const root = loaded.document.querySelector(".dframe-root");
  const place = byId(loaded, "myclaude-dock-place");
  const rail = byId(loaded, "myclaude-dock-rail");
  const want = Math.floor((3022 - 12 - 360) * z);
  assert.equal(lastOn(loaded).get("w"), String(want), "в Пимп — место панели, не весь чат");
  assert.equal(dock(loaded).mode, "full");
  const room = px(root, "--myclaude-dock-w");
  const column = 3022 - room;
  assert.ok(column >= 360 && column < 362, `колонка чата справа ≈ DOCK_FEED_MIN, а не ${column}`);
  assert.ok(Math.abs(px(place, "width") - want / z) < 0.01);
  assert.equal(place.dataset.cover, undefined, "подложка не закрывает чат");
  assert.equal(rail.style.getPropertyValue("display"), "block");
  assert.equal(sizeButton(loaded, "full").getAttribute("aria-pressed"), "true");
  loaded.api.dispose();
});

test("тяга рейки у «панель + поле» — дальше узкая с этой ширины (в границах: лента не ýже 360)", async () => {
  const loaded = await opened({ ...BIG, storage: { "myclaude-dock-mode-v1": "full" } });
  const rail = byId(loaded, "myclaude-dock-rail");
  const before = Number(lastOn(loaded).get("w"));
  const x = px(rail, "left");
  rail.dispatchEvent({ type: "pointerdown", target: rail, button: 0, clientX: x, pointerId: 1, isTrusted: true, cancelable: true });
  assert.equal(dock(loaded).mode, "narrow");
  loaded.document.dispatchEvent({ type: "pointermove", target: rail, buttons: 1, clientX: x - 100, pointerId: 1, isTrusted: true, cancelable: true });
  loaded.document.dispatchEvent({ type: "pointerup", target: rail, button: 0, clientX: x - 100, pointerId: 1, isTrusted: true });
  await flush();
  const z = 2518 / 3022;
  assert.equal(dock(loaded).width, Math.round(before - 100 * z), "ширина узкой — от места «панель + поле» минус тяга");
  assert.equal(loaded.win.localStorage.getItem("myclaude-dock-mode-v1"), "narrow");
  loaded.api.dispose();
});

test("окно ~800 pt: «панель + поле» не ýже половины (колонке 360 не хватает места — остаётся «½»)", async () => {
  const loaded = await opened({ frame: [0, 29, 800, 600], viewport: { width: 800, height: 571 } });
  press(loaded, sizeButton(loaded, "half"));
  await flush();
  const half = lastOn(loaded).get("w");
  press(loaded, sizeButton(loaded, "full"));
  await flush();
  assert.equal(dock(loaded).mode, "full");
  assert.equal(lastOn(loaded).get("w"), String(Math.max(Number(half), Math.floor(800 - 12 - 360))));
  assert.ok(Number(lastOn(loaded).get("w")) >= Number(half));
  loaded.api.dispose();
});

test("кнопка «панель + поле»: подсказка и aria по-русски, значок — панель ~80% и колонка справа", async () => {
  const loaded = await opened(BIG);
  const item = sizeButton(loaded, "full");
  assert.equal(item.title, "Панель материалов и поле ввода справа (ещё раз — узкая)");
  assert.equal(item.getAttribute("aria-label"), item.title);
  assert.match(ownCss(loaded), /#myclaude-dock-sizes>div\[data-mode="full"\]>span::before\{width:80%\}/);
  loaded.api.dispose();
});

test("#11203: плитка чата ýже широкого вида — плитки поля мелкие, как в колонке широкого вида (WIDE_TILE 40)", () => {
  const loaded = scene(BIG);
  const { layoutCss, attachmentsCss, WIDE_TILE, WIDE_PANEL_MIN } = loaded.inner;
  assert.equal(WIDE_TILE, 40);
  const css = layoutCss();
  const at = css.indexOf(`@container tile-slot (max-width: ${WIDE_PANEL_MIN - 1}px)`);
  assert.ok(at > css.indexOf(`@container tile-slot (min-width: ${WIDE_PANEL_MIN}px)`), "правило узкой плитки — после широкого вида");
  const block = css.slice(at);
  const rule = block.match(/\[data-cds-composer-attachments\] \[data-cds-attachment\] \{([^}]*)\}/);
  assert.ok(rule, "правило целится в плитки поля ввода");
  assert.match(rule[1], /width: clamp\(32px, calc\(\(100cqw - 16px\) \/ 5\), 40px\) !important/);
  assert.match(rule[1], /height: clamp\(32px, calc\(\(100cqw - 16px\) \/ 5\), 40px\) !important/);
  // Узкое окно (@media 560) — по-прежнему в attachmentsCss; спор решает порядок таблиц: layoutSheet после.
  assert.match(attachmentsCss(), /@media \(max-width: 560px\)/);
  loaded.api.dispose();
});
