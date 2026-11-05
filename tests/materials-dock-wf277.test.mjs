// WF277, батч Б2 (#10644, контракт К-DOCK — docs/contracts/560-wf277-dock.md): панель материалов слева в окне Claude.
//
// Слово Элвиса 22.10 22:16: «прямо в клауды, во внутрь» — кнопка «PMP» прямоугольная, такая же, как кнопка бокового
// меню, рядом с ней; любая ссылка из чата (html, картинка, md, pdf, ролик) открывается в панели, а не справа; открыл
// файл — панель открылась сама; панель тянется влево-вправо.
//
// Сцена — слепок живого окна Claude 3.1623 (tests/fixtures/claude-dom/3.1623-main-wide.json): свёрнутая боковая
// панель (aside.df-hub-rail, «Show sidebar» 84,8 28×28 в .df-collapsed-chrome), чат — .dframe-pane-host 811×470.
// Окно — 1067×618 точек на 811×470 CSS px (z = 1067/811, как у Элвиса ~1,32). fetch отвечает /dock словом из
// box.reply (null — PMP не отвечает), /open-html — {taken, opened}. Стаб CSS не считает: отступ чата проверяется
// правилом в таблице и переменной на .dframe-root, место — рамкой подложки.
import base from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { loadInject, plain } from "./load.mjs";
import { settle } from "./stands.mjs";

const SLICE_URL = new URL("./fixtures/claude-dom/3.1623-main-wide.json", import.meta.url);
// Слепков живых окон в открытой копии нет (tools/public_export.sh) — там файл пропускается целиком.
const SLICE = existsSync(SLICE_URL) ? JSON.parse(readFileSync(SLICE_URL, "utf8")) : null;
const test = (name, fn) => base(name, { skip: !SLICE && "нет слепка tests/fixtures/claude-dom (открытая копия)" }, fn);
const CHAT = "local_0f3a9c1e-7b2d-4e6f-8a1b-5c4d3e2f1a0b";
const CWD = "/Users/dev/Projects/PimpMyClaude";
const FRAME = [0, 29, 1067, 618];
const Z = 1067 / 811;
const UP = { ok: true, viewer: "up", docked: true, owner: "this" };
const DIR = "/Users/dev/Папка с пробелом";
const enc = text => text.split("/").map(encodeURIComponent).join("/");
const BUSY = "data-myclaude-busy";
const flush = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };

// Узел слепка → узел стаба (как tests/claude-dom-replay.test.mjs).
const grow = (parent, node) => {
  const attrs = { ...(node.a ?? {}) };
  if (node.tid) attrs["data-testid"] = node.tid;
  if (node.cds) attrs["data-cds"] = node.cds;
  if (node.role) attrs.role = node.role;
  if (node.aria) attrs["aria-label"] = node.aria;
  const [left, top, width, height] = node.r;
  const el = parent.add(node.t, { class: (node.c ?? []).join(" "), id: node.id, attrs, rect: { left, top, width, height } });
  for (const kid of node.k ?? []) grow(el, kid);
  return el;
};
// Карточка SendUserFile: button[title=<путь>], пропсы {name, size, path} шагом выше.
const card = (parent, path, rect = { left: 40, top: 300, width: 200, height: 40 }) => {
  const button = parent.add("button", { attrs: { type: "button", title: path }, rect });
  const name = path.split("/").pop();
  button.add("span", { text: name, rect });
  button.__reactFiber$test = { memoizedProps: { children: [] }, return: { memoizedProps: { name, size: 4096, path }, return: null } };
  return button;
};
// Ссылка на файл в тексте ответа: span[role=button].prose-link, fileRef двумя шагами выше.
const fileRef = (dom, parent, text, path) => {
  const span = dom.leaf(parent, "span", text, { class: "inline-block prose-link", attrs: { role: "button", tabindex: "0" } });
  span.__reactFiber$test = { memoizedProps: { role: "button" }, return: { memoizedProps: { trigger: {} }, return: { memoizedProps: { fileRef: { path } }, return: null } } };
  return span;
};

// Лёгкая копия слепка: те же узлы на пути к месту и кнопке (классы, data-testid, рамки 3.1623), без 2,8 МБ списка
// чатов и ленты — проход стаба по полному слепку стоит секунды. Сам слепок гоняет первая проверка ниже.
const mini = dom => {
  const rect = (left, top, width, height) => ({ left, top, width, height });
  const root = dom.document.body.add("div", { class: "dframe-root draggable-none cds-root text-primary", rect: rect(0, 0, 811, 470) });
  const aside = root.add("aside", { class: "dframe-sidebar font-normal font-control df-hub-rail", rect: rect(84, 6, 28, 32) });
  aside.add("div", { class: "dframe-peek-bridge", attrs: { "aria-hidden": "true" }, rect: rect(0, 6, 254, 40) });
  const chrome = aside.add("div", { class: "df-collapsed-chrome flex items-center", rect: rect(84, 6, 28, 32) });
  chrome.add("button", { class: "cds-reset df-compact-trigger draggable-none", rect: rect(84, 8, 28, 28),
    attrs: { "data-testid": "sidebar-compact-trigger", "data-cds": "Button", "aria-label": "Show sidebar", "aria-expanded": "false", type: "button" } });
  chrome.add("div", { class: "df-collapsed-nav draggable-none relative flex items-center", rect: rect(112, 22, 0, 0) });
  aside.add("div", { id: "frame-peek-popover", class: "dframe-sidebar-body flex flex-col flex-1 min-h-0", attrs: { "data-testid": "sidebar" }, rect: rect(-4, 0, 254, 470) });
  root.add("div", { class: "cds-reset group/resize w-3 cursor-col-resize relative h-full", rect: rect(0, 0, 12, 470) });
  const host = root.add("main", { class: "dframe-content", rect: rect(0, 0, 811, 470) })
    .add("div", { class: "dframe-content-inner", rect: rect(0, 0, 811, 470) })
    .add("div", { class: "dframe-pane-host flex-1 min-h-0 relative isolate", rect: rect(0, 0, 811, 470) });
  const primary = host.add("div", { class: "dframe-pane dframe-pane-primary min-w-0 relative flex flex-col", rect: rect(0, 0, 811, 470) });
  host.add("div", { class: "dframe-pane-col", rect: rect(0, 0, 811, 470) });
  primary.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" }, rect: rect(8, 0, 471, 462) })
    .add("div", { attrs: { "data-testid": "transcript-rows" } });
};

const scene = ({ reply = UP, storage = {}, href = `https://claude.ai/epitaxy/${CHAT}`, build = null, kind = "mini" } = {}) => {
  const box = { reply, calls: [], hang: false };
  const nodes = {};
  const loaded = loadInject({
    href, geometry: { viewport: { width: 811, height: 470 }, frame: FRAME }, storage: { local: storage },
    html: dom => {
      const body = dom.document.body;
      if (kind === "slice") {
        body.className = SLICE.root.c.join(" ");
        for (const kid of SLICE.root.k ?? []) grow(body, kid);
      } else if (kind === "mini") mini(dom);
      if (kind !== "bare") {
        // Выезжающий список свёрнутой панели в живом окне — opacity 0, пока не наведён (проба 23.10).
        dom.document.getElementById("frame-peek-popover").computed = { opacity: "0" };
        const list = dom.document.querySelector('[data-testid="sidebar"]');
        const row = list.add("div", { attrs: { "data-row-key": `code:${CHAT}` } });
        row.__reactFiber$test = { memoizedProps: { session: { ref: { kind: "code", id: CHAT }, title: "Claude",
          source: { kind: "code", data: { cwd: CWD } } } }, return: null };
        const rows = dom.document.querySelector('[data-testid="transcript-rows"]');
        nodes.row = rows.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "99" } });
        nodes.prose = nodes.row.add("div", { class: "prose" }).add("p");
      }
      build?.(dom, nodes);
      dom.window.fetch = address => {
        const url = String(address);
        box.calls.push(url);
        if (box.hang) return new Promise(() => {});
        const answer = url.includes("/dock?") ? box.reply : url.includes("/open-html?") ? { taken: true, opened: true } : {};
        if (answer === null) return Promise.reject(new Error("refused"));
        return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(answer), text: () => Promise.resolve("") });
      };
      return {};
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  Object.assign(loaded, { box, nodes });
  return loaded;
};
const dock = loaded => plain(loaded.api.status().dock);
const byId = (loaded, id) => loaded.document.getElementById(id);
const docks = loaded => loaded.box.calls.filter(url => url.includes("/dock?"));
const opens = loaded => loaded.box.calls.filter(url => url.includes("/open-html?"));
const query = url => Object.fromEntries(new URL(url).searchParams);
const px = (node, name) => Number.parseFloat(node.style.getPropertyValue(name));
const ownCss = loaded => loaded.dom.queryAll("style").map(style => style.textContent).join("\n");
// Нажатие мышью: захват документа (там перехватчики страницы), потом сам узел.
const press = (loaded, node) => {
  let passed = true;
  for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) {
    const event = () => ({ type, target: node, isTrusted: true, bubbles: true, cancelable: true, button: 0, buttons: type.endsWith("down") ? 1 : 0, detail: 1, pointerId: 1 });
    if (loaded.document.dispatchEvent(event())) node.dispatchEvent(event());
    else passed = false;
  }
  return passed;
};
const click = (loaded, target) => loaded.document.dispatchEvent({ type: "click", isTrusted: true, target, button: 0, detail: 1 });
// Сердце: беседа идёт по часам страницы, а performance.now стенда их не двигает — срок снимаем сами.
const beat = loaded => {
  loaded.inner.dockState.beatAt = -Infinity;
  for (const [id, item] of [...loaded.dom.timers.entries()]) if (item.kind === "interval" && item.ms === 2000) loaded.dom.fire(id);
};
const opened = async (loaded = null) => {
  const page = loaded ?? scene();
  await flush();
  assert.equal(dock(page).button, true, "кнопки нет при живом PimpViewer");
  press(page, byId(page, "myclaude-dock-button"));
  await flush();
  return page;
};

test("кнопки нет без живого PimpViewer: проверка probe=1, ответы down / none / нет PMP / не JSON; в попапе — ни кнопки, ни запроса", async () => {
  for (const reply of [{ ok: true, viewer: "down" }, { ok: true, viewer: "none" }, null, {}]) {
    const loaded = scene({ reply });
    await flush();
    const probe = docks(loaded);
    assert.equal(probe.length, 1, "одна проверка на старте");
    // К-DOCK-1: probe=1 — Пимп отвечает сам; on=0 снимал бы док другого окна (проверяющий WF277, ошибка 3).
    assert.equal(probe[0], "http://127.0.0.1:47615/dock?probe=1");
    assert.equal(dock(loaded).button, false, JSON.stringify(reply));
    assert.equal(byId(loaded, "myclaude-dock-button").style.getPropertyValue("display"), "none");
    assert.equal(dock(loaded).on, false);
    loaded.api.dispose();
  }
  const popout = scene({ href: "about:blank" });
  await flush();
  assert.deepEqual(docks(popout), [], "попап PimpViewer не спрашивает");
  assert.equal(dock(popout).button, false);
});

test("слепок 3.1623: кнопка «PMP» — сразу за «Show sidebar», та же высота и верх, прямоугольная; вид кнопки бокового меню; место — по нажатию", async () => {
  const loaded = scene({ kind: "slice" });
  await flush();
  const button = byId(loaded, "myclaude-dock-button");
  const sidebar = loaded.document.querySelector('[aria-label="Show sidebar"]').getBoundingClientRect();
  assert.equal(dock(loaded).viewer, "up");
  assert.equal(button.style.getPropertyValue("display"), "flex");
  assert.deepEqual([px(button, "left"), px(button, "top"), px(button, "width"), px(button, "height")], [sidebar.right + 4, sidebar.top, 48, sidebar.height]);
  assert.equal(button.textContent, "Файлы");
  assert.equal(button.getAttribute("aria-pressed"), "false");
  const css = ownCss(loaded);
  // #10705: рамка, подложка, вес, гарнитура и цвет — с «Show/Hide sidebar» (переменные dockLook), запасные — как у неё.
  assert.match(css, /#myclaude-dock-button\{position:fixed;[^}]*height:28px;[^}]*border-radius:8px;[^}]*box-shadow:var\(--myclaude-dock-ring,0 0 0 1px var\(--cds-border/);
  assert.match(css, /#myclaude-dock-button\{[^}]*font-weight:var\(--myclaude-dock-weight,var\(--cds-font-weight-control,435\)\)/);
  assert.match(css, /#myclaude-dock-button\{[^}]*-webkit-app-region:no-drag/);
  assert.equal(byId(loaded, "myclaude-dock-place").style.getPropertyValue("display"), "none", "не нажата — места нет");
  press(loaded, button);
  await flush();
  assert.equal(dock(loaded).placed, true);
  assert.match(docks(loaded).at(-1), new RegExp(`/dock\\?on=1&vis=1&x=0&y=55&w=420&h=563&wx=0&wy=29&ww=1067&wh=618&chat=${CHAT}&seq=\\d+$`),
    "на живой разметке ни один слой Claude место не закрывает — vis=1");
  const place = byId(loaded, "myclaude-dock-place");
  assert.deepEqual([px(place, "left"), px(place, "top"), px(place, "height")], [0, 42, 428]);
});

test("нажатие: место слева под строкой кнопок — отступ чата, подложка и рейка; /dock on=1 с местом в точках и рамкой окна", async () => {
  const loaded = scene();
  await flush();
  press(loaded, byId(loaded, "myclaude-dock-button"));
  assert.equal(dock(loaded).state, "wait", "до ответа — ждём");
  await flush();
  const state = dock(loaded);
  assert.deepEqual([state.on, state.viewer, state.docked, state.placed, state.state, state.vis], [true, "up", true, true, null, true]);
  assert.equal(loaded.win.localStorage.getItem("myclaude-dock-on-v1"), "1", "нажатие помнится");
  // Место: левый край чата, верх — низ «Show sidebar» + 6, ширина 420 точек = 420 / z CSS px, до низа чата.
  const width = 420 / Z;
  const place = byId(loaded, "myclaude-dock-place");
  assert.deepEqual([px(place, "left"), px(place, "top"), px(place, "height")], [0, 42, 428]);
  assert.ok(Math.abs(px(place, "width") - width) < 0.01, `ширина ${px(place, "width")}`);
  const rail = byId(loaded, "myclaude-dock-rail");
  assert.ok(Math.abs(px(rail, "left") - width) < 0.01);
  assert.deepEqual([px(rail, "top"), px(rail, "width"), px(rail, "height")], [42, 12, 428]);
  // Отступ чата — правилом на метку корня, ширина — переменной (место + рейка).
  const root = loaded.document.querySelector(".dframe-root");
  assert.equal(root.hasAttribute("data-myclaude-dock"), true);
  assert.ok(Math.abs(px(root, "--myclaude-dock-w") - (width + 12)) < 0.01);
  const css = ownCss(loaded);
  assert.ok(css.includes(".dframe-root[data-myclaude-dock] .dframe-pane-host{padding-left:var(--myclaude-dock-w) !important}"));
  assert.match(css, /#myclaude-dock-place\{[^}]*-webkit-app-region:no-drag;z-index:1\}/);
  // Полоса перетаскивания окна — над местом, правее кнопки «Файлы» и трёх кнопок размера (#10759: 168 + 3×28 + 2×4 + 4).
  const drag = byId(loaded, "myclaude-dock-drag");
  assert.deepEqual([px(drag, "left"), px(drag, "top"), px(drag, "height")], [264, 0, 42]);
  // К-DOCK-1 побайтно: ключи по порядку, точки = CSS px × z, рамка окна, чат, seq.
  const on = docks(loaded).filter(url => url.includes("on=1"));
  assert.equal(on.length, 1);
  assert.match(on[0], new RegExp(`^http://127\\.0\\.0\\.1:47615/dock\\?on=1&vis=1&x=0&y=55&w=420&h=563&wx=0&wy=29&ww=1067&wh=618&chat=${CHAT}&seq=\\d+$`));
  assert.deepEqual([Math.round(42 * Z), Math.round(428 * Z)], [55, 563], "y и h — CSS px × z");
  // Строка «Файлы» (#11654, К-DOCK-6a) в месте есть, но полосе 420 − 350 < 120 pt — в адрес не идёт (К-DOCK-6b).
  assert.deepEqual(state.place, { x: 0, y: 55, w: 420, h: 563, wx: 0, wy: 29, ww: 1067, wh: 618, bx: 350, by: 11, bh: 37 });
});

test("seq растёт: и от запроса к запросу, и у нового экземпляра страницы", async () => {
  const loaded = await opened();
  const seqs = () => docks(loaded).filter(url => !url.includes("probe=1")).map(url => Number(query(url).seq));
  beat(loaded);
  const before = seqs();
  assert.ok(before.every((seq, i) => i === 0 || seq > before[i - 1]), before.join(","));
  loaded.reload();
  await flush();
  const after = seqs();
  assert.ok(after.at(-1) > before.at(-1), "новый экземпляр начал seq заново — «последний выигрывает» сломался бы");
});

test("тяга рейки: шире на ходу кадром, в границах 260 точек и ленты ≥ 360; отпустил — помнится; двойной щелчок — 420", async () => {
  const loaded = await opened();
  const rail = byId(loaded, "myclaude-dock-rail");
  const x = px(rail, "left") + 6;
  const move = to => loaded.document.dispatchEvent({ type: "pointermove", buttons: 1, clientX: to, clientY: 200, pointerId: 1, isTrusted: true });
  rail.dispatchEvent({ type: "pointerdown", target: rail, button: 0, buttons: 1, clientX: x, clientY: 200, pointerId: 1 });
  assert.equal(dock(loaded).dragging, true);
  move(x + 50);
  loaded.dom.fireKind("raf");
  assert.equal(dock(loaded).width, Math.round(420 + 50 * Z));
  assert.equal(query(docks(loaded).at(-1)).w, String(Math.round(420 + 50 * Z)), "место уходит кадром, не по отпусканию");
  move(x + 2000);
  loaded.dom.fireKind("raf");
  const max = Math.round((811 - 12 - 360) * Z);
  assert.equal(dock(loaded).width, max, "лента не ýже 360");
  move(x - 2000);
  loaded.dom.fireKind("raf");
  assert.equal(dock(loaded).width, 260, "не ýже 260 точек");
  move(x + 30);
  loaded.document.dispatchEvent({ type: "pointerup", clientX: x + 30, pointerId: 1 });
  assert.equal(dock(loaded).dragging, false);
  assert.equal(loaded.win.localStorage.getItem("myclaude-dock-width-v1"), String(Math.round(420 + 30 * Z)));
  assert.ok(Math.abs(px(byId(loaded, "myclaude-dock-place"), "width") - Math.round(420 + 30 * Z) / Z) < 0.01);
  rail.dispatchEvent({ type: "dblclick", target: rail });
  assert.equal(dock(loaded).width, 420);
  assert.equal(loaded.win.localStorage.getItem("myclaude-dock-width-v1"), "420");
  // Ширина помнится и новым экземпляром.
  loaded.win.localStorage.setItem("myclaude-dock-width-v1", "300");
  loaded.reload();
  await flush();
  assert.equal(query(docks(loaded).at(-1)).w, "300");
});

test("vis=0 под слоями над местом: меню Claude, диалог, выехавший список, свой слой, скрытое окно; вне места — vis=1", async () => {
  const loaded = await opened();
  const last = () => query(docks(loaded).at(-1));
  const body = loaded.document.body;
  const menu = body.add("div", { attrs: { role: "menu" }, rect: { left: 100, top: 200, width: 180, height: 120 } });
  loaded.inner.dockSync();
  assert.deepEqual([last().on, last().vis], ["1", "0"], "меню над местом — док прячется");
  menu.rect = { left: 600, top: 200, width: 180, height: 120 };
  loaded.inner.dockSync();
  assert.equal(last().vis, "1", "меню у чата, мимо места");
  menu.remove();
  const dialog = body.add("div", { attrs: { role: "dialog" }, rect: { left: 0, top: 0, width: 811, height: 470 } });
  loaded.inner.dockSync();
  assert.equal(last().vis, "0", "диалог");
  dialog.remove();
  loaded.inner.dockSync();
  assert.equal(last().vis, "1");
  // Выезд свёрнутой боковой панели (наведение): Claude ставит data-hovering — и список становится видимым.
  const root = loaded.document.querySelector(".dframe-root");
  root.setAttribute("data-collapsed", "true");
  root.setAttribute("data-hovering", "");
  loaded.inner.dockSync();
  assert.equal(last().vis, "0", "выехал список чатов");
  root.removeAttribute("data-hovering");
  loaded.document.getElementById("frame-peek-popover").computed = { opacity: "1" };
  loaded.inner.dockSync();
  assert.equal(last().vis, "0", "список виден и без метки");
  loaded.document.getElementById("frame-peek-popover").computed = { opacity: "0" };
  // Свой слой (просмотр фото 12л) над местом.
  const own = body.add("div", { id: "myclaude-photo-view", rect: { left: 0, top: 0, width: 811, height: 470 } });
  loaded.inner.dockSync();
  assert.equal(last().vis, "0", "свой слой");
  own.remove();
  loaded.inner.dockSync();
  assert.equal(last().vis, "1");
  // Окно скрыто — сразу по visibilitychange, без кадра раскладки.
  loaded.document.hidden = true;
  loaded.document.dispatchEvent({ type: "visibilitychange" });
  assert.equal(last().vis, "0", "окно скрыто");
  loaded.document.hidden = false;
  loaded.document.dispatchEvent({ type: "visibilitychange" });
  assert.equal(last().vis, "1");
  assert.equal(docks(loaded).filter(url => url.includes("on=0")).length, 0, "пауза — только vis=0, on=0 не шлётся");
  assert.equal(dock(loaded).on, true);
});

test("on=0 — только закрыл человек и снятие экземпляра; сердце — on=1 раз в 2 с", async () => {
  const loaded = await opened();
  const count = () => docks(loaded).filter(url => url.includes("on=0")).length;
  const probes = count();
  beat(loaded);
  assert.match(docks(loaded).at(-1), /on=1&vis=1&/, "сердце");
  assert.equal(count(), probes);
  press(loaded, byId(loaded, "myclaude-dock-button"));
  assert.equal(count(), probes + 1, "закрыл кнопкой — on=0");
  // Владельца Пимп узнаёт по окну (ошибка 2): рамка окна — и в on=0.
  assert.match(docks(loaded).at(-1), new RegExp(`/dock\\?on=0&chat=${CHAT}&wx=0&wy=29&ww=1067&wh=618&seq=\\d+$`));
  const root = loaded.document.querySelector(".dframe-root");
  assert.equal(root.hasAttribute("data-myclaude-dock"), false, "чат вернулся на место");
  assert.equal(root.style.getPropertyValue("--myclaude-dock-w"), "");
  assert.equal(byId(loaded, "myclaude-dock-place").style.getPropertyValue("display"), "none");
  assert.equal(loaded.win.localStorage.getItem("myclaude-dock-on-v1"), null);
  assert.equal(dock(loaded).button, true, "кнопка осталась, не горит");
  assert.equal(byId(loaded, "myclaude-dock-button").dataset.on, "false");
  beat(loaded);
  assert.equal(count(), probes + 1, "закрытая панель сердца не шлёт");
  // Снятие экземпляра у нажатой панели — on=0; у не нажатой — ничего.
  press(loaded, byId(loaded, "myclaude-dock-button"));
  await flush();
  const before = count();
  loaded.api.dispose();
  assert.equal(count(), before + 1, "снятие экземпляра — on=0");
  assert.equal(root.hasAttribute("data-myclaude-dock"), false);
  assert.equal(byId(loaded, "myclaude-dock-button"), null, "узлы сняты");
  assert.equal(byId(loaded, "myclaude-dock-place"), null);
  assert.equal(loaded.win.localStorage.getItem("myclaude-dock-on-v1"), "1", "нажатие помнится до следующего экземпляра");
});

test("нажатая панель помнится: новый экземпляр сразу шлёт on=1 и ставит место по ответу", async () => {
  const loaded = scene({ storage: { "myclaude-dock-on-v1": "1" } });
  assert.match(docks(loaded)[0], /\/dock\?on=1&vis=1&x=0&y=55&w=420&h=563&/, "на старте — on=1, не проверка");
  assert.equal(dock(loaded).placed, false, "до ответа место не ставим — чат не дёргается дважды");
  await flush();
  assert.deepEqual([dock(loaded).placed, dock(loaded).button, dock(loaded).on], [true, true, true]);
});

test("PimpViewer не встал: спит при нажатии, PMP молчит, нет ответа 3 с, отказ трижды — кнопка как была и плашка", async () => {
  const note = loaded => byId(loaded, "myclaude-new-window-note")?.textContent ?? "";
  const down = scene();
  await flush();
  down.box.reply = { ok: true, viewer: "down", docked: false, owner: "this" };
  press(down, byId(down, "myclaude-dock-button"));
  await flush();
  // #10722: PimpViewer только что был жив — кнопка остаётся минуту (перезапуск, установка), нажатие снято, плашка.
  assert.deepEqual([dock(down).on, dock(down).placed, dock(down).button], [false, false, true]);
  assert.equal(note(down), "Панель материалов: PimpViewer не запущен");
  // Отжали по плохому ответу (ошибка 5): вдруг PimpViewer встал позже — on=0 вдогонку; общий ключ — человека (ошибка 2).
  assert.match(docks(down).at(-1), new RegExp(`/dock\\?on=0&chat=${CHAT}&wx=0&wy=29&ww=1067&wh=618&seq=\\d+$`));
  assert.equal(down.win.localStorage.getItem("myclaude-dock-on-v1"), "1", "отказ ключ не стирает");

  const silent = scene();
  await flush();
  silent.box.reply = null;
  press(silent, byId(silent, "myclaude-dock-button"));
  await flush();
  assert.equal(dock(silent).on, false);
  assert.equal(dock(silent).error, "network");
  assert.equal(note(silent), "Панель материалов недоступна: PMP не отвечает (порт 47615)");

  const hang = scene();
  await flush();
  hang.box.hang = true;
  press(hang, byId(hang, "myclaude-dock-button"));
  assert.equal(dock(hang).state, "wait");
  hang.dom.fireKind("timeout");
  assert.deepEqual([dock(hang).on, dock(hang).state], [false, null]);
  assert.match(docks(hang).at(-1), /\/dock\?on=0&/, "нет ответа 3 с — on=0 вдогонку");

  const refused = scene();
  await flush();
  refused.box.reply = { ok: true, viewer: "up", docked: false, owner: "this" };
  press(refused, byId(refused, "myclaude-dock-button"));
  await flush();
  assert.deepEqual([dock(refused).on, dock(refused).refusals], [true, 1], "один отказ — ещё ждём");
  // Скрытое место (vis=0) — не отказ.
  refused.document.hidden = true;
  refused.document.dispatchEvent({ type: "visibilitychange" });
  await flush();
  assert.equal(dock(refused).refusals, 1);
  refused.document.hidden = false;
  refused.document.dispatchEvent({ type: "visibilitychange" });
  await flush();
  beat(refused);
  await flush();
  assert.equal(dock(refused).on, false, "третий отказ подряд — панель снята");
  assert.equal(note(refused), "Панель материалов не встала: PimpViewer не нашёл окно Claude");
  assert.equal(dock(refused).button, true, "PimpViewer жив — кнопка остаётся");
  assert.match(docks(refused).at(-1), /\/dock\?on=0&/);
  assert.equal(refused.win.localStorage.getItem("myclaude-dock-on-v1"), "1");
});

test("док у другого окна (owner other) — не отказ: место здесь снято, нажатие и общий ключ помнятся, кнопка забирает панель сюда (ошибка 2)", async () => {
  const note = loaded => byId(loaded, "myclaude-new-window-note")?.textContent ?? "";
  const loaded = await opened();
  assert.equal(dock(loaded).placed, true);
  loaded.box.reply = { ok: true, viewer: "up", docked: true, owner: "other" };
  for (let i = 0; i < 5; i += 1) { beat(loaded); await flush(); }
  const state = dock(loaded);
  assert.deepEqual([state.on, state.owner, state.refusals, state.placed, state.button, state.state], [true, "other", 0, false, true, null]);
  assert.equal(note(loaded), "", "ложной плашки нет");
  assert.equal(loaded.win.localStorage.getItem("myclaude-dock-on-v1"), "1", "ключ общий у окон — не стёрт");
  assert.equal(loaded.document.querySelector(".dframe-root").hasAttribute("data-myclaude-dock"), false, "чат здесь на всю ширину");
  const button = byId(loaded, "myclaude-dock-button");
  assert.equal(button.getAttribute("aria-pressed"), "true");
  assert.equal(button.title, "Панель материалов в другом окне — перенести сюда");
  assert.match(docks(loaded).at(-1), /\/dock\?on=1&vis=1&/, "сердце идёт");
  assert.equal(docks(loaded).filter(url => url.includes("on=0")).length, 0, "чужой док не снимаем");
  // Нажатие — забрать сюда: пауза и показ подряд (для Пимпа — новость этого окна), не закрытие.
  const before = docks(loaded).length;
  loaded.box.reply = UP;
  press(loaded, button);
  assert.deepEqual(docks(loaded).slice(before).map(query).map(item => [item.on, item.vis]), [["1", "0"], ["1", "1"]]);
  await flush();
  assert.deepEqual([dock(loaded).on, dock(loaded).owner, dock(loaded).placed], [true, "this", true]);
  assert.equal(loaded.win.localStorage.getItem("myclaude-dock-on-v1"), "1");
});

test("не нажатая панель проверяет PimpViewer только probe=1 — чужой док не снимает (ошибка 3)", async () => {
  const loaded = scene();
  await flush();
  for (let i = 0; i < 3; i += 1) { loaded.inner.dockState.probeAt = -Infinity; loaded.inner.dockSync(); await flush(); }
  assert.equal(docks(loaded).length, 4);
  assert.deepEqual([...new Set(docks(loaded))], ["http://127.0.0.1:47615/dock?probe=1"]);
  assert.deepEqual([dock(loaded).button, dock(loaded).on], [true, false]);
});

test("сердце готово с 1,7 с от прошлой отправки: таймер раз в 2 с не теряет такт (ошибка 4)", async () => {
  const loaded = await opened();
  const state = loaded.inner.dockState;
  const fire = () => { for (const [id, item] of [...loaded.dom.timers.entries()]) if (item.kind === "interval" && item.ms === 2000) loaded.dom.fire(id); };
  let before = docks(loaded).length;
  state.beatAt = Date.now() - 1500;
  fire();
  assert.equal(docks(loaded).length, before, "1,5 с — рано");
  state.beatAt = Date.now() - 1750;
  fire();
  assert.equal(docks(loaded).length, before + 1, "1,75 с — сердце, не через такт (4 с)");
  assert.match(docks(loaded).at(-1), /\/dock\?on=1&vis=1&/);
});

test("страница в панель: click&dock=1 несёт и прежние frame/bg — док не взял, окно просмотра поверх чата, как до WF277 (ошибка 6)", async () => {
  const loaded = scene({ build: (dom, nodes) => { nodes.html = nodes.prose.add("a", { attrs: { href: "/tmp/16.html" }, text: "16.html" }); } });
  await flush();
  assert.equal(click(loaded, loaded.nodes.html), false);
  assert.match(opens(loaded)[0], new RegExp(`^http://127\\.0\\.0\\.1:47615/open-html\\?mode=click&dock=1&path=%2Ftmp%2F16\\.html&chat=${CHAT}`
    + "&x=0&y=55&w=420&h=563&wx=0&wy=29&ww=1067&wh=618&frame=0,29,1067,618(&bg=[0-9a-f]{6})?$"));
});

test("команда dock {on} — как кнопка, без клика (живая проверка гейта)", async () => {
  const loaded = scene();
  await flush();
  loaded.dom.command({ id: "dock-1", action: "dock", at: "now", on: true });
  assert.match(docks(loaded).at(-1), /\/dock\?on=1&vis=1&/);
  await flush();
  assert.equal(dock(loaded).placed, true);
  loaded.dom.command({ id: "dock-2", action: "dock", at: "now", on: false });
  assert.match(docks(loaded).at(-1), /\/dock\?on=0&/);
  assert.equal(dock(loaded).placed, false);
  const popout = scene({ href: "about:blank" });
  popout.dom.command({ id: "dock-3", action: "dock", at: "now", on: true });
  assert.deepEqual(docks(popout), [], "попап команду не берёт");
});

test("файл из чата при живом PimpViewer — в панель: click&dock=1 с местом, панель встала сама, «⏳» гаснет по ответу", async () => {
  const loaded = scene({ build: (dom, nodes) => {
    nodes.md = nodes.prose.add("a", { attrs: { href: `computer://${enc(`${DIR}/отчёт.md`)}` }, text: "отчёт.md" });
    nodes.video = card(nodes.row, `${DIR}/ролик.mp4`);
  } });
  await flush();
  assert.equal(dock(loaded).on, false);
  assert.equal(click(loaded, loaded.nodes.md), false, "клик ушёл Claude — открылась бы правая панель");
  const url = opens(loaded)[0];
  assert.match(url, new RegExp(`^http://127\\.0\\.0\\.1:47615/open-html\\?mode=click&dock=1&path=${encodeURIComponent(`${DIR}/отчёт.md`)}&chat=${CHAT}&x=0&y=55&w=420&h=563&wx=0&wy=29&ww=1067&wh=618$`));
  assert.equal(dock(loaded).on, true, "открыл файл — панель открылась сама");
  assert.match(docks(loaded).at(-1), /\/dock\?on=1&/);
  await flush();
  assert.equal(dock(loaded).placed, true);
  assert.equal(plain(loaded.api.status().htmlChrome.last).via, "dock");
  // Карточка ролика: «⏳» до ответа PimpViewer, ответ пришёл — гаснет (окно не уходит назад).
  click(loaded, loaded.nodes.video.querySelector("span"));
  assert.equal(loaded.nodes.video.getAttribute(BUSY), "file");
  await flush();
  assert.equal(loaded.nodes.video.getAttribute(BUSY), null, "ответ пришёл — «⏳» снят");
  assert.match(opens(loaded).at(-1), new RegExp(`dock=1&path=${encodeURIComponent(`${DIR}/ролик.mp4`)}&`));
  assert.equal(dock(loaded).opens, 2);
});

test("PimpViewer не жив — прежние фильтры: страница прежним путём (click с рамкой), md, txt и ролик — Claude (ошибка 1)", async () => {
  const loaded = scene({ reply: { ok: true, viewer: "down" }, build: (dom, nodes) => {
    nodes.html = nodes.prose.add("a", { attrs: { href: "/tmp/16.html" }, text: "16.html" });
    nodes.md = nodes.prose.add("a", { attrs: { href: "/tmp/notes.md" }, text: "notes.md" });
    nodes.ref = fileRef(dom, nodes.prose, "ролик", "/tmp/ролик.mov");
    nodes.card = card(nodes.row, "/tmp/notes.txt");
  } });
  await flush();
  assert.equal(click(loaded, loaded.nodes.html), false);
  // Без панели у новых видов прежних путей нет: клик и нажатие остаются Claude (его правая панель), не тишина.
  for (const node of [loaded.nodes.md, loaded.nodes.ref, loaded.nodes.card.querySelector("span")]) {
    for (const type of ["pointerdown", "click"]) {
      assert.equal(loaded.document.dispatchEvent({ type, isTrusted: true, target: node, button: 0, detail: 1 }), true, type);
    }
  }
  const [html, ...rest] = opens(loaded);
  assert.match(html, /^http:\/\/127\.0\.0\.1:47615\/open-html\?mode=click&path=%2Ftmp%2F16\.html&chat=[^&]+&frame=0,29,1067,618/);
  assert.deepEqual(rest, []);
  assert.equal(dock(loaded).on, false);
  assert.ok(!docks(loaded).some(url => url.includes("on=1")));
});

test("путь ссылки с кириллицей и пробелом — во всех формах (file://, computer://, голый с %XX, сырой, относительный)", async () => {
  const { mentionPath, filePathFrom } = scene().inner;
  const want = `${DIR}/отчёт.md`;
  for (const raw of [`file://${enc(want)}`, `computer://${enc(want)}`, enc(want), want, `file://localhost${enc(want)}`,
    `file://${enc(want)}#L10`, `computer://${enc(want)}?raw=1`]) {
    assert.equal(mentionPath(raw), want, raw);
  }
  assert.equal(mentionPath(`docs/${encodeURIComponent("план работ.md")}`, CWD), `${CWD}/docs/план работ.md`, "относительный с %XX");
  assert.equal(filePathFrom("/tmp/100% готово.md"), "/tmp/100% готово.md", "битая последовательность остаётся буквами");
  assert.equal(filePathFrom(`/tmp/100% ${encodeURIComponent("ролик")}.mp4`), "/tmp/100% ролик.mp4", "целые рядом раскрываются");
  // И кликом — каждая форма ссылки до запроса доходит раскрытой (свой файл на форму: повтор того же — защита 3 с).
  const loaded = scene({ build: (dom, nodes) => {
    nodes.forms = [
      nodes.prose.add("a", { attrs: { href: `file://${enc(`${DIR}/а.md`)}` } }),
      nodes.prose.add("a", { attrs: { href: `computer://${enc(`${DIR}/б.pdf`)}` } }),
      nodes.prose.add("a", { attrs: { href: enc(`${DIR}/в.html`) } }),
      fileRef(dom, nodes.prose, "г", `${DIR}/г.mov`),
      fileRef(dom, nodes.prose, "д", `docs/${encodeURIComponent("д с пробелом.txt")}`),
    ];
  } });
  await flush();
  for (const node of loaded.nodes.forms) assert.equal(click(loaded, node), false);
  assert.deepEqual(opens(loaded).map(url => query(url).path),
    [`${DIR}/а.md`, `${DIR}/б.pdf`, `${DIR}/в.html`, `${DIR}/г.mov`, `${CWD}/docs/д с пробелом.txt`]);
});

test("панель Files Claude не открывается по нашим видам: нажатие и клик глушатся на захвате; код — Claude", async () => {
  const loaded = scene({ build: (dom, nodes) => {
    nodes.md = fileRef(dom, nodes.prose, "статус", "docs/status.md");
    nodes.mp3 = nodes.prose.add("a", { attrs: { href: "/tmp/голос.mp3" } });
    nodes.code = fileRef(dom, nodes.prose, "код", "app/main.swift");
    nodes.card = card(nodes.row, "/tmp/notes.txt");
  } });
  await flush();
  for (const node of [loaded.nodes.md, loaded.nodes.mp3]) {
    for (const type of ["pointerdown", "mousedown", "click"]) {
      const passed = loaded.document.dispatchEvent({ type, isTrusted: true, target: node, button: 0, detail: 1 });
      assert.equal(passed, false, `${type} по ${node.textContent || node.getAttribute("href")} дошёл до Claude`);
    }
  }
  assert.equal(click(loaded, loaded.nodes.card.querySelector("span")), false, "карточка .txt — наша");
  for (const type of ["pointerdown", "mousedown", "click"]) {
    assert.equal(loaded.document.dispatchEvent({ type, isTrusted: true, target: loaded.nodes.code, button: 0, detail: 1 }), true, `${type} по .swift — Claude`);
  }
});

test("клик по фото в ленте — по-прежнему просмотр 12л, не панель", async () => {
  const loaded = scene({ build: (dom, nodes) => {
    const tile = nodes.row.add("span", { attrs: { role: "button", tabindex: "0" } });
    nodes.img = tile.add("img", { attrs: { src: "data:image/png;base64,AAA" } });
    nodes.img.naturalWidth = 640;
    nodes.img.naturalHeight = 1440;
    nodes.img.rect = { left: 40, top: 200, width: 71, height: 160 };
  } });
  await flush();
  loaded.document.dispatchEvent({ type: "click", isTrusted: true, target: loaded.nodes.img, button: 0, detail: 1 });
  assert.equal(loaded.api.status().photo.open, true);
  assert.deepEqual(opens(loaded), []);
  assert.equal(dock(loaded).on, false);
});

test("открытая боковая панель: кнопка — за переключателем Claude/Code, панель не ýже кнопки (не запоминается), PimpViewer ушёл — ширина Claude", async () => {
  const loaded = scene({ kind: "bare", build: dom => {
    const root = dom.document.body.add("div", { class: "dframe-root", rect: { left: 0, top: 0, width: 811, height: 470 } });
    const aside = root.add("aside", { class: "dframe-sidebar", rect: { left: 0, top: 0, width: 242, height: 470 } });
    const bar = aside.add("div", { class: "df-titlebar", rect: { left: 0, top: 0, width: 242, height: 44 } });
    bar.add("button", { class: "df-chrome-btn", attrs: { "aria-label": "Hide sidebar" }, rect: { left: 84, top: 8, width: 28, height: 28 } });
    bar.add("button", { class: "df-chrome-btn", attrs: { "aria-label": "Back" }, rect: { left: 116, top: 8, width: 28, height: 28 } });
    bar.add("button", { class: "df-chrome-btn", attrs: { "aria-label": "Forward" }, rect: { left: 148, top: 8, width: 28, height: 28 } });
    bar.add("div", { attrs: { role: "radiogroup", "aria-label": "Mode" }, rect: { left: 180, top: 10, width: 48, height: 24 } });
    root.add("main", { class: "dframe-content", rect: { left: 254, top: 0, width: 557, height: 470 } })
      .add("div", { class: "dframe-content-inner", rect: { left: 254, top: 0, width: 557, height: 470 } })
      .add("div", { class: "dframe-pane-host", rect: { left: 254, top: 0, width: 557, height: 470 } })
      .add("div", { class: "dframe-pane-primary", rect: { left: 254, top: 0, width: 557, height: 470 } });
  } });
  await flush();
  settle(loaded);
  const button = byId(loaded, "myclaude-dock-button");
  assert.deepEqual([px(button, "left"), px(button, "top")], [232, 8], "за Claude/Code (228) + 4");
  assert.equal(loaded.inner.dockLeftFloor(loaded.document.querySelector("aside")), 232 + 48 + 8);
  const root = loaded.document.querySelector(".dframe-root");
  assert.equal(root.style.getPropertyValue("--myclaude-left"), "288px", "панель раздвинута под кнопку");
  assert.equal(loaded.win.localStorage.getItem("myclaude-left-side-v1"), null, "своя ширина ради кнопки не запоминается");
  // Стаб CSS не считает — раздвигаем сами, как сделает переменная: панель 288, чат с 300.
  loaded.document.querySelector("aside").rect = { left: 0, top: 0, width: 288, height: 470 };
  for (const name of ["main", ".dframe-content-inner", ".dframe-pane-host", ".dframe-pane-primary"]) {
    loaded.document.querySelector(name).rect = { left: 300, top: 0, width: 511, height: 470 };
  }
  settle(loaded);
  // Место — правее боковой панели, сразу у чата: полоса перетаскивания — над местом, кнопка левее.
  press(loaded, button);
  await flush();
  const place = byId(loaded, "myclaude-dock-place");
  assert.deepEqual([px(place, "left"), px(place, "top")], [300, 42]);
  assert.equal(query(docks(loaded).at(-1)).x, String(Math.round(300 * Z)));
  // Кнопки размера (#10759) — над местом, правее границы боковой панели (не поперёк неё), полоса — правее них.
  const sizes = byId(loaded, "myclaude-dock-sizes");
  assert.equal(px(sizes, "left"), 300 + 4, "кнопки размера — с края места, не поперёк границы боковой панели");
  assert.equal(px(byId(loaded, "myclaude-dock-drag"), "left"), px(sizes, "left") + px(sizes, "width") + 4);
  // Чат 511: ленте 360 места на панель не хватает — панель не ýже 260 точек.
  assert.equal(dock(loaded).place.w, 260, "узкий чат — панель на своём минимуме");
  // PimpViewer закрыли — кнопки нет, ширина боковой панели снова у Claude (минута ожидания #10722 вышла).
  loaded.box.reply = { ok: true, viewer: "down" };
  loaded.inner.dockState.upAt = -Infinity;
  beat(loaded);
  await flush();
  settle(loaded);
  assert.equal(dock(loaded).button, false);
  assert.equal(root.hasAttribute("data-myclaude-left"), false);
});

test("#10722: PimpViewer или Пимп перезапускаются — кнопка и место остаются минуту, переспрос раз в 3 с; удалён — кнопки нет", async () => {
  const loaded = await opened();
  assert.equal(dock(loaded).docked, true);
  // Установка PimpViewer: на сердце — «down» (или сеть молчит).
  for (const reply of [{ ok: true, viewer: "down", docked: false }, null]) {
    loaded.box.reply = reply;
    beat(loaded);
    await flush();
    settle(loaded);
    assert.equal(dock(loaded).button, true, `кнопка пропала на ${JSON.stringify(reply)}`);
    assert.equal(byId(loaded, "myclaude-dock-button").style.getPropertyValue("display") === "none", false);
    assert.equal(dock(loaded).on, true, "нажатие не снято");
    assert.equal(byId(loaded, "myclaude-dock-place").style.getPropertyValue("display") === "none", false, "место осталось");
  }
  // Вернулся — снова «up», док встаёт.
  loaded.box.reply = { ok: true, viewer: "up", docked: true, owner: "this" };
  beat(loaded);
  await flush();
  assert.equal(dock(loaded).docked, true);
  // Удалён — сразу без кнопки.
  loaded.box.reply = { ok: true, viewer: "none" };
  beat(loaded);
  await flush();
  settle(loaded);
  assert.equal(dock(loaded).button, false);
  loaded.api.dispose();
});

test("status().dock — поля на месте; dispose снимает таймер, подписки и место", async () => {
  const loaded = await opened();
  assert.deepEqual(Object.keys(dock(loaded)), ["button", "on", "viewer", "docked", "owner", "apart", "placed", "place", "vis", "width", "mode", "file", "sizes",
    "shift", "state", "sent", "answers", "opens", "refusals", "last", "error", "dragging"]);
  loaded.api.dispose();
  assert.equal(loaded.dom.ids("interval").length, 0, "сердце снято");
  assert.equal(loaded.document.querySelector(".dframe-root").hasAttribute("data-myclaude-dock"), false);
});

// #10705 (снимок Элвиса 23.10 pmp-1355-5: «Там жирно, здесь не жирно»): кнопка «PMP» — тот же вес, рамка и подложка, что у
// «Show/Hide sidebar» рядом, замером её computed style; нажата — как нажатая кнопка Claude (заливка bg-accent и цвет
// text-accent поверх той же подложки), рамка не меняется.
test("#10705: «PMP» берёт рамку, подложку, вес и цвет с «Show sidebar»; у открытой панели — без рамки и подложки; нажата — заливка акцента", async () => {
  const loaded = scene({ build: dom => {
    const sidebar = dom.document.querySelector('[aria-label="Show sidebar"]');
    sidebar.computed = { "box-shadow": "rgb(61, 65, 72) 0px 0px 0px 1px", "font-weight": "435", color: "rgb(230, 232, 236)",
      "font-family": "ui-sans-serif, system-ui" };
    sidebar.pseudo = { "::before": { content: '""', "background-color": "rgb(19, 21, 24)" } };
  } });
  await flush();
  const button = byId(loaded, "myclaude-dock-button");
  const look = name => button.style.getPropertyValue(name);
  assert.equal(button.style.getPropertyValue("display"), "flex");
  assert.deepEqual([look("--myclaude-dock-ring"), look("--myclaude-dock-weight"), look("--myclaude-dock-fg"),
    look("--myclaude-dock-font"), look("--myclaude-dock-under")],
  ["rgb(61, 65, 72) 0px 0px 0px 1px", "435", "rgb(230, 232, 236)", "ui-sans-serif, system-ui", "rgb(19, 21, 24)"]);
  // Панель открыли: у «Hide sidebar» нет рамки раздела 4 и подложки — у «PMP» тоже.
  const sidebar = loaded.document.querySelector('[aria-label="Show sidebar"]');
  sidebar.computed = { "box-shadow": "none", "font-weight": "435", color: "rgb(230, 232, 236)", "font-family": "ui-sans-serif, system-ui" };
  sidebar.pseudo = { "::before": { content: "none" } };
  beat(loaded);
  await flush();
  assert.equal(look("--myclaude-dock-ring"), "none");
  assert.equal(look("--myclaude-dock-under"), "transparent");
  const css = ownCss(loaded);
  assert.doesNotMatch(css, /#myclaude-dock-button\{[^}]*font:600/, "жирной надписи больше нет");
  assert.match(css, /#myclaude-dock-button\[data-on="true"\]\{color:var\(--cds-text-accent,currentColor\);background:linear-gradient\(var\(--cds-bg-accent/);
  assert.doesNotMatch(css, /#myclaude-dock-button\[data-on="true"\]\{[^}]*box-shadow/, "нажатая — та же рамка, не акцентная");
  assert.match(css, /#myclaude-dock-button:hover\{background:linear-gradient\(var\(--cds-fill-button-ghost-hover/);
});
