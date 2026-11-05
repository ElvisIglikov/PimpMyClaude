// WF282 (#10759, контракт К-DOCK-5 — docs/contracts/590-wf282-dock-size.md): три кнопки размера панели материалов.
//
// Слово Элвиса 23.10: «в пол-экрана и потом вообще во весь экран. Нажимаешь вот так — чик и чик… легко его было
// возвращать к исходному размеру»; «три кнопки размера… стандартный узенький». Сцена — та же лёгкая копия слепка 3.1623,
// что в materials-dock-wf277: свёрнутая боковая панель, «Show sidebar» 84,8 28×28, чат 811×470 CSS px, z = 1067/811.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_0f3a9c1e-7b2d-4e6f-8a1b-5c4d3e2f1a0b";
const FRAME = [0, 29, 1067, 618];
const Z = 1067 / 811;
const UP = { ok: true, viewer: "up", docked: true, owner: "this" };
const flush = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };

const scene = ({ storage = {}, paint = null } = {}) => {
  const box = { calls: [] };
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, geometry: { viewport: { width: 811, height: 470 }, frame: FRAME }, storage: { local: storage },
    html: dom => {
      const rect = (left, top, width, height) => ({ left, top, width, height });
      const root = dom.document.body.add("div", { class: "dframe-root draggable-none cds-root text-primary", rect: rect(0, 0, 811, 470) });
      const aside = root.add("aside", { class: "dframe-sidebar df-hub-rail", rect: rect(84, 6, 28, 32) });
      const chrome = aside.add("div", { class: "df-collapsed-chrome flex items-center", rect: rect(84, 6, 28, 32) });
      chrome.add("button", { class: "cds-reset df-compact-trigger", rect: rect(84, 8, 28, 28),
        attrs: { "data-testid": "sidebar-compact-trigger", "aria-label": "Show sidebar", type: "button" } });
      aside.add("div", { id: "frame-peek-popover", attrs: { "data-testid": "sidebar" }, rect: rect(-4, 0, 254, 470) }).computed = { opacity: "0" };
      const host = root.add("main", { class: "dframe-content", rect: rect(0, 0, 811, 470) })
        .add("div", { class: "dframe-content-inner", rect: rect(0, 0, 811, 470) })
        .add("div", { class: "dframe-pane-host flex-1 min-h-0 relative isolate", rect: rect(0, 0, 811, 470) });
      paint?.({ root, aside });
      host.add("div", { class: "dframe-pane dframe-pane-primary", rect: rect(0, 0, 811, 470) })
        .add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" }, rect: rect(8, 0, 471, 462) })
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
const opened = async (options = {}) => {
  const loaded = scene(options);
  await flush();
  press(loaded, byId(loaded, "myclaude-dock-button"));
  await flush();
  assert.equal(dock(loaded).placed, true);
  return loaded;
};

test("кнопки размера: нет, пока панель закрыта; открыта — три за «PMP», узкая нажата, подсказки и aria по-русски", async () => {
  const loaded = scene();
  await flush();
  const sizes = byId(loaded, "myclaude-dock-sizes");
  assert.equal(dock(loaded).sizes, false);
  assert.equal(sizes.style.getPropertyValue("display"), "none");
  press(loaded, byId(loaded, "myclaude-dock-button"));
  await flush();
  const state = dock(loaded);
  assert.deepEqual([state.sizes, state.mode], [true, "narrow"]);
  const button = byId(loaded, "myclaude-dock-button");
  assert.equal(px(sizes, "left"), px(button, "left") + px(button, "width") + 4);
  assert.deepEqual([px(sizes, "top"), px(sizes, "height"), px(sizes, "width")], [8, 28, 3 * 28 + 2 * 4]);
  assert.equal(sizes.getAttribute("role"), "group");
  for (const [mode, pressed] of [["narrow", "true"], ["half", "false"], ["full", "false"]]) {
    const item = sizeButton(loaded, mode);
    assert.equal(item.getAttribute("role"), "button");
    assert.equal(item.getAttribute("tabindex"), "0");
    assert.equal(item.getAttribute("aria-pressed"), pressed, mode);
    assert.match(item.title, /^Панель материалов /);
    assert.equal(item.getAttribute("aria-label"), item.title);
  }
  const css = loaded.dom.queryAll("style").map(style => style.textContent).join("\n");
  assert.match(css, /#myclaude-dock-sizes>div:hover\{/);
  assert.match(css, /#myclaude-dock-sizes>div\[data-on="true"\]\{/);
  assert.match(css, /#myclaude-dock-sizes>div:focus-visible\{/);
  // Закрыли панель — кнопок нет.
  press(loaded, button);
  await flush();
  assert.equal(dock(loaded).sizes, false);
  assert.equal(sizes.style.getPropertyValue("display"), "none");
  loaded.api.dispose();
});

// «Панель + поле» (#11202, WF301): место панели — всё, кроме колонки ленты DOCK_FEED_MIN справа, не уже половины.
const FULL_PT = Math.max(Math.round(811 * Z / 2), Math.floor((811 - 12 - 360) * Z));

test("«½» — половина чата, «панель + поле» — всё, кроме колонки 360 справа, с рейкой; нажатая ещё раз — обратно узкая; помнится", async () => {
  const loaded = await opened();
  const place = byId(loaded, "myclaude-dock-place");
  const rail = byId(loaded, "myclaude-dock-rail");
  const root = loaded.document.querySelector(".dframe-root");
  const narrowRoom = 420 / Z + 12;
  assert.equal(lastOn(loaded).get("w"), "420");

  press(loaded, sizeButton(loaded, "half"));
  await flush();
  assert.equal(dock(loaded).mode, "half");
  assert.equal(loaded.win.localStorage.getItem("myclaude-dock-mode-v1"), "half");
  assert.equal(lastOn(loaded).get("w"), String(Math.round(811 * Z / 2)), "место ушло в Пимп сразу");
  assert.ok(Math.abs(px(place, "width") - Math.round(811 * Z / 2) / Z) < 0.01);
  assert.equal(rail.style.getPropertyValue("display"), "block");
  assert.ok(Math.abs(px(root, "--myclaude-dock-w") - (Math.round(811 * Z / 2) / Z + 12)) < 0.01, "у «½» чат подвинулся");
  assert.equal(sizeButton(loaded, "half").getAttribute("aria-pressed"), "true");
  assert.equal(sizeButton(loaded, "narrow").getAttribute("aria-pressed"), "false");

  press(loaded, sizeButton(loaded, "full"));
  await flush();
  const query = lastOn(loaded);
  assert.deepEqual([query.get("x"), query.get("y"), query.get("w"), query.get("h"), query.get("vis")], ["0", "55", String(FULL_PT), "563", "1"]);
  const fullRoom = FULL_PT / Z + 12;
  assert.ok(Math.abs(px(place, "width") - FULL_PT / Z) < 0.01, "подложка — место панели, не весь чат");
  assert.deepEqual([px(place, "top"), px(place, "height")], [42, 428], "высота — от строки кнопок до низа окна");
  assert.equal(place.dataset.cover, undefined, "подложки над чатом нет: колонка чата с полем видна");
  assert.equal(rail.style.getPropertyValue("display"), "block", "рейка видна, как у «½»");
  assert.ok(Math.abs(px(rail, "left") - FULL_PT / Z) < 0.01);
  assert.ok(Math.abs(px(root, "--myclaude-dock-w") - fullRoom) < 0.01, "чат подвинулся за панель");
  assert.ok(811 - fullRoom >= 360 - 0.01, "колонка чата справа — не ýже DOCK_FEED_MIN");
  const drag = byId(loaded, "myclaude-dock-drag");
  assert.ok(Math.abs(px(drag, "left") + px(drag, "width") - fullRoom) < 0.01, "полоса перетаскивания — до кромки чата: шапка чата Claude правее кликабельна");

  // Нажатая «панель + поле» ещё раз — узкая, как было.
  press(loaded, sizeButton(loaded, "full"));
  await flush();
  assert.equal(dock(loaded).mode, "narrow");
  assert.equal(lastOn(loaded).get("w"), "420");
  assert.equal(place.dataset.cover, undefined);
  assert.equal(rail.style.getPropertyValue("display"), "block");
  assert.ok(Math.abs(px(root, "--myclaude-dock-w") - narrowRoom) < 0.01);
  assert.equal(loaded.win.localStorage.getItem("myclaude-dock-mode-v1"), "narrow");
  // Нажатая «узкая» — ничего не меняет.
  press(loaded, sizeButton(loaded, "narrow"));
  await flush();
  assert.equal(dock(loaded).mode, "narrow");
  loaded.api.dispose();

  // Размер помнится: новый экземпляр с «панель + поле» сразу шлёт её место.
  const again = scene({ storage: { "myclaude-dock-on-v1": "1", "myclaude-dock-mode-v1": "full" } });
  await flush();
  again.inner.dockSync(true);
  await flush();
  assert.deepEqual([dock(again).mode, dock(again).placed], ["full", true]);
  assert.equal(lastOn(again).get("w"), String(FULL_PT));
  again.api.dispose();
  // Мусор в ключе — узкая.
  const junk = scene({ storage: { "myclaude-dock-mode-v1": "huge" } });
  assert.equal(dock(junk).mode, "narrow");
  junk.api.dispose();
});

test("«панель + поле» и слой Claude над местом: vis=0, место прежнее; подложка не над чатом и без правил «крышки»", async () => {
  const loaded = await opened({ storage: { "myclaude-dock-mode-v1": "full" } });
  const place = byId(loaded, "myclaude-dock-place");
  loaded.document.body.add("div", { attrs: { role: "dialog" }, rect: { left: 200, top: 200, width: 200, height: 100 } });
  loaded.inner.dockSync(true);
  await flush();
  assert.equal(lastOn(loaded).get("vis"), "0");
  assert.equal(lastOn(loaded).get("w"), String(FULL_PT), "место прежнее, только пауза");
  assert.equal(place.dataset.cover, undefined);
  assert.ok(Math.abs(px(place, "width") - FULL_PT / Z) < 0.01);
  assert.doesNotMatch(ownCss(loaded), /data-cover/, "правил «крышки» над чатом больше нет (WF301)");
  loaded.api.dispose();
});

test("«панель + поле», а PimpViewer в док не встал (перезапуск, отказ): чат по-прежнему колонкой справа, место в Пимп прежнее", async () => {
  const loaded = await opened({ storage: { "myclaude-dock-mode-v1": "full" } });
  const place = byId(loaded, "myclaude-dock-place");
  loaded.inner.dockAnswer({ ok: true, viewer: "up", docked: false, owner: "this" }, 200, Date.now() * 2, {});
  assert.equal(place.dataset.cover, undefined);
  assert.ok(Math.abs(px(place, "width") - FULL_PT / Z) < 0.01);
  assert.equal(lastOn(loaded).get("w"), String(FULL_PT));
  loaded.api.dispose();
});

test("#11657: ширина рейки запомнилась почти во всё окно — узкая с кнопки всё равно обычная 420, не «панель + поле»", async () => {
  const loaded = await opened({ storage: { "myclaude-dock-width-v1": "2540", "myclaude-dock-mode-v1": "full" } });
  assert.equal(lastOn(loaded).get("w"), String(FULL_PT));
  press(loaded, sizeButton(loaded, "narrow"));
  await flush();
  assert.equal(dock(loaded).mode, "narrow");
  assert.equal(lastOn(loaded).get("w"), "420", "узкая — не та же ширина, что «панель + поле»");
  assert.equal(loaded.win.localStorage.getItem("myclaude-dock-width-v1"), "420");
  // Тянули рейку у «панель + поле» вправо до края — снова огромная; нажатая «панель + поле» ещё раз — тоже обычная.
  press(loaded, sizeButton(loaded, "full"));
  await flush();
  const rail = byId(loaded, "myclaude-dock-rail");
  rail.dispatchEvent({ type: "pointerdown", target: rail, button: 0, clientX: px(rail, "left"), pointerId: 1, isTrusted: true, cancelable: true });
  loaded.document.dispatchEvent({ type: "pointermove", target: rail, clientX: px(rail, "left") + 400, buttons: 1, pointerId: 1, isTrusted: true, cancelable: true });
  loaded.document.dispatchEvent({ type: "pointerup", target: rail, pointerId: 1, isTrusted: true, cancelable: true });
  await flush();
  assert.equal(dock(loaded).mode, "narrow");
  assert.ok(dock(loaded).width > 420, "тяга запомнила широкую");
  press(loaded, sizeButton(loaded, "full"));
  await flush();
  assert.equal(lastOn(loaded).get("w"), String(FULL_PT));
  press(loaded, sizeButton(loaded, "full"));
  await flush();
  assert.equal(lastOn(loaded).get("w"), "420");
  loaded.api.dispose();
});

test("клавиатура: Enter и пробел на кнопке размера; тяга рейки у «½» — дальше узкая", async () => {
  const loaded = await opened();
  const key = (node, name) => node.dispatchEvent({ type: "keydown", key: name, target: node, isTrusted: true, bubbles: true, cancelable: true });
  key(sizeButton(loaded, "half"), "Enter");
  await flush();
  assert.equal(dock(loaded).mode, "half");
  key(sizeButton(loaded, "half"), " ");
  await flush();
  assert.equal(dock(loaded).mode, "narrow", "пробел по нажатой «½» — узкая");
  key(sizeButton(loaded, "full"), "Tab");
  assert.equal(dock(loaded).mode, "narrow", "чужая клавиша — мимо");
  key(sizeButton(loaded, "half"), "Enter");
  await flush();
  const rail = byId(loaded, "myclaude-dock-rail");
  rail.dispatchEvent({ type: "pointerdown", target: rail, button: 0, clientX: px(rail, "left"), pointerId: 1, isTrusted: true, cancelable: true });
  assert.equal(dock(loaded).mode, "narrow");
  assert.equal(loaded.win.localStorage.getItem("myclaude-dock-mode-v1"), "narrow");
  loaded.api.dispose();
});

test("команда dock {size} — размер без клика; одна size не трогает нажатие; мусор — мимо; вместе с on — и то и другое", async () => {
  const loaded = scene();
  await flush();
  loaded.dom.command({ id: "size-1", action: "dock", at: "now", size: "half" });
  assert.deepEqual([dock(loaded).mode, dock(loaded).on], ["half", false], "закрытая панель: размер помнится, панель не открылась");
  loaded.dom.command({ id: "size-2", action: "dock", at: "now", size: "giant" });
  assert.equal(dock(loaded).mode, "half");
  loaded.dom.command({ id: "size-3", action: "dock", at: "now", on: true, size: "full" });
  await flush();
  assert.deepEqual([dock(loaded).mode, dock(loaded).on, dock(loaded).placed], ["full", true, true]);
  assert.equal(lastOn(loaded).get("w"), String(FULL_PT));
  loaded.dom.command({ id: "size-4", action: "dock", at: "now", size: "narrow" });
  await flush();
  assert.deepEqual([dock(loaded).mode, dock(loaded).on], ["narrow", true]);
  assert.equal(lastOn(loaded).get("w"), "420");
  loaded.api.dispose();
});

// Слово Элвиса 23.10 19:30 (снимки pmp-1930 №1, №2 → №4, №5): «зачем она там вообще, эта чёрная-пустая полоса… разделение
// точно такое же, как вот здесь вот». Подложка — поверхность боковой панели Claude, рейка — её тонкая граница, тот же
// цвет уходит PimpViewer (`bg` в /dock); панель закрыта — ни подложки, ни отступа. 05.11 #11692 («у файлов фон точно
// такой же, как у клауда»): подложка и `bg` — поверхность чата (#131518), не боковой панели; рейка — по-прежнему её граница.
const VARS = { "--cds-page-bg": "#131518", "--df-web-sidebar-bg": "#0e1013", "--cds-border": "#3d4148" };
const ownCss = loaded => loaded.dom.queryAll("style").map(style => style.textContent).join("\n");

test("свёрнутая боковая панель: подложка — цвет чата Claude, рейка — граница боковой панели; bg уходит в /dock", async () => {
  const loaded = await opened({ paint: ({ root }) => { root.setAttribute("data-collapsed", ""); root.computed = { ...VARS }; } });
  const place = byId(loaded, "myclaude-dock-place");
  const rail = byId(loaded, "myclaude-dock-rail");
  assert.equal(place.style.getPropertyValue("--myclaude-dock-bg"), "#131518", "поверхность чата, не боковой панели #0e1013 (#11692)");
  assert.equal(rail.style.getPropertyValue("--myclaude-dock-line"), "#3d4148");
  assert.equal(lastOn(loaded).get("bg"), "131518");
  assert.match(loaded.box.calls.filter(url => url.includes("/dock?on=1")).at(-1), /&wh=618&bg=131518&chat=/, "порядок ключей К-DOCK-1: место, bg, chat, seq");
  const css = ownCss(loaded);
  // Рейка прозрачна (тёмного зазора между местом и лентой нет), граница — тонкая линия у края места, тянется как раньше.
  assert.match(css, /#myclaude-dock-rail\{[^}]*background:transparent;[^}]*cursor:col-resize/);
  assert.match(css, /#myclaude-dock-rail::before\{[^}]*left:0;[^}]*width:max\(var\(--cds-panel-line,0px\),\.5px\);background:var\(--myclaude-dock-line,var\(--cds-border/);
  assert.match(css, /#myclaude-dock-rail>span\{position:absolute;left:0;/, "ручка наведения — на линии");
  assert.match(css, /#myclaude-dock-place\{[^}]*background:var\(--myclaude-dock-bg,/);
  // Закрыли — ни подложки, ни рейки, ни отступа чата.
  press(loaded, byId(loaded, "myclaude-dock-button"));
  await flush();
  const root = loaded.document.querySelector(".dframe-root");
  assert.equal(root.hasAttribute("data-myclaude-dock"), false, "правило отступа снято");
  assert.equal(root.style.getPropertyValue("--myclaude-dock-w"), "");
  assert.equal(place.style.getPropertyValue("display"), "none");
  assert.equal(rail.style.getPropertyValue("display"), "none");
  loaded.api.dispose();
});

test("открытая боковая панель: фон — чат Claude, граница — замером aside", async () => {
  const loaded = await opened({ paint: ({ root, aside }) => {
    root.computed = { ...VARS };
    aside.computed = { backgroundColor: "rgb(20, 22, 26)", "border-right-width": "0.5px", "border-right-color": "rgb(61, 65, 72)" };
  } });
  assert.equal(byId(loaded, "myclaude-dock-place").style.getPropertyValue("--myclaude-dock-bg"), "#131518", "не фон aside (#11692)");
  assert.equal(byId(loaded, "myclaude-dock-rail").style.getPropertyValue("--myclaude-dock-line"), "rgb(61, 65, 72)");
  assert.equal(lastOn(loaded).get("bg"), "131518");
  loaded.api.dispose();
});

test("живой фон: подложка прозрачна; PimpViewer получает сплошной цвет чата из темы", async () => {
  const loaded = scene({ paint: ({ root }) => { root.setAttribute("data-collapsed", ""); root.computed = { ...VARS }; } });
  await flush();
  loaded.dom.command({ id: "look-1", action: "theme", at: "now", scope: "all", look: { aurora: true } });
  press(loaded, byId(loaded, "myclaude-dock-button"));
  await flush();
  assert.equal(dock(loaded).placed, true);
  assert.equal(byId(loaded, "myclaude-dock-place").style.getPropertyValue("--myclaude-dock-bg"), "transparent");
  assert.equal(lastOn(loaded).get("bg"), "131518");
  loaded.api.dispose();
});
