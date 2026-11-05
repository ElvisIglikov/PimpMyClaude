// WF302 (#11223, #11224; контракт К-DOCK-5 — docs/contracts/590-wf282-dock-size.md, К-V8 — 080-wf97-wf104-pimp-viewer.md).
//
// Элвис 30.10 ~17:45: «у меня пимп на весь экран с чего-то открылся. Он у меня свёрнутый был, взял весь экран»; «один раз его
// должен крестик этот нажать и сразу вернуться обратно в окно, в котором я был». Панель, которую открыл файл из чата
// (до клика закрыта), — узкая и не шире половины места чата; запомненные ширина и размер остаются кнопке «PMP».
// `dock {on:false, only:"owner"}` (от `/viewer-dock-off`) закрывает панель только там, где она стоит.
// Сцена — та же, что в dock-size-wf282: чат 811×470 CSS px, z = 1067/811, место чата 1067 точек.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_0f3a9c1e-7b2d-4e6f-8a1b-5c4d3e2f1a0b";
const FRAME = [0, 29, 1067, 618];
const Z = 1067 / 811;
const HALF = Math.floor(811 * Z / 2);
const MAX = Math.round((811 - 12 - 360) * Z);
const UP = { ok: true, viewer: "up", docked: true, owner: "this" };
const flush = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };

const scene = ({ storage = {} } = {}) => {
  const box = { calls: [] };
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, geometry: { viewport: { width: 811, height: 470 }, frame: FRAME }, storage: { local: storage },
    html: dom => {
      const rect = (left, top, width, height) => ({ left, top, width, height });
      const root = dom.document.body.add("div", { class: "dframe-root draggable-none cds-root text-primary", rect: rect(0, 0, 811, 470) });
      const aside = root.add("aside", { class: "dframe-sidebar df-hub-rail", rect: rect(84, 6, 28, 32) });
      aside.add("div", { class: "df-collapsed-chrome flex items-center", rect: rect(84, 6, 28, 32) })
        .add("button", { class: "cds-reset df-compact-trigger", rect: rect(84, 8, 28, 28),
          attrs: { "data-testid": "sidebar-compact-trigger", "aria-label": "Show sidebar", type: "button" } });
      aside.add("div", { id: "frame-peek-popover", attrs: { "data-testid": "sidebar" }, rect: rect(-4, 0, 254, 470) }).computed = { opacity: "0" };
      const host = root.add("main", { class: "dframe-content", rect: rect(0, 0, 811, 470) })
        .add("div", { class: "dframe-content-inner", rect: rect(0, 0, 811, 470) })
        .add("div", { class: "dframe-pane-host flex-1 min-h-0 relative isolate", rect: rect(0, 0, 811, 470) });
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
const docks = loaded => loaded.box.calls.filter(url => url.includes("/dock?") && !url.includes("probe=1"));
const lastOn = loaded => new URL(docks(loaded).filter(url => url.includes("on=1")).at(-1)).searchParams;
const sizeButton = (loaded, mode) => [...byId(loaded, "myclaude-dock-sizes").children].find(node => node.dataset.mode === mode);
const press = (loaded, node) => {
  for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) {
    const event = { type, target: node, isTrusted: true, bubbles: true, cancelable: true, button: 0, buttons: type.endsWith("down") ? 1 : 0, detail: 1, pointerId: 1 };
    if (loaded.document.dispatchEvent(event)) node.dispatchEvent({ ...event });
  }
};
const keys = loaded => [loaded.win.localStorage.getItem("myclaude-dock-width-v1"), loaded.win.localStorage.getItem("myclaude-dock-mode-v1")];
// Панель закрыта, PimpViewer жив (probe=1 → up), запомнены «ширина на максимум» и выбранный размер.
const closed = async storage => {
  const loaded = scene({ storage });
  await flush();
  assert.deepEqual([dock(loaded).button, dock(loaded).on], [true, false]);
  return loaded;
};

for (const [stored, why] of [["narrow", "ширина рейки на максимуме"], ["half", "запомнена «½»"], ["full", "запомнена «панель + поле»"]]) {
  test(`#11223: файл из чата при закрытой панели (${why}) — узкая, ≤ ½ места чата; ключи не тронуты`, async () => {
    const loaded = await closed({ "myclaude-dock-width-v1": "5000", "myclaude-dock-mode-v1": stored });
    const pt = loaded.inner.dockForFile();
    assert.equal(pt.w, Math.min(MAX, HALF), "место для click&dock=1 — уже половины");
    assert.ok(pt.w <= 811 * Z / 2);
    assert.equal(lastOn(loaded).get("w"), String(HALF), "/dock on=1 — та же узкая");
    await flush();
    const state = dock(loaded);
    assert.deepEqual([state.on, state.placed, state.file], [true, true, true]);
    assert.ok(Math.abs(px(byId(loaded, "myclaude-dock-place"), "width") - HALF / Z) < 0.01);
    assert.equal(byId(loaded, "myclaude-dock-place").dataset.cover, undefined, "чат не закрыт подложкой");
    assert.equal(sizeButton(loaded, "narrow").getAttribute("aria-pressed"), "true", "на виду — узкая");
    assert.deepEqual(keys(loaded), ["5000", stored], "запомненные ширина и размер — кнопке «PMP»");
    // Закрыли (✕ PimpViewer → /viewer-dock-off) — и «PMP» открывает как раньше, по запомненному.
    loaded.dom.command({ id: `off-${stored}`, action: "dock", at: "now", on: false, only: "owner" });
    assert.match(docks(loaded).at(-1), /\/dock\?on=0&/);
    assert.deepEqual([dock(loaded).on, dock(loaded).placed, dock(loaded).file], [false, false, false]);
    press(loaded, byId(loaded, "myclaude-dock-button"));
    await flush();
    // «панель + поле» (WF301, #11202) — всё место, кроме колонки ленты 360 справа, не уже половины.
    const wide = stored === "full" ? Math.max(Math.round(811 * Z / 2), Math.floor((811 - 12 - 360) * Z)) : stored === "half" ? Math.round(811 * Z / 2) : MAX;
    assert.equal(lastOn(loaded).get("w"), String(wide), "кнопка «PMP» — запомненный размер");
    assert.equal(dock(loaded).mode, stored);
    assert.deepEqual(keys(loaded), ["5000", stored]);
    loaded.api.dispose();
  });
}

test("#11223: панель уже открыта — файл из чата её не сужает", async () => {
  const loaded = await closed({ "myclaude-dock-width-v1": "5000", "myclaude-dock-mode-v1": "narrow" });
  press(loaded, byId(loaded, "myclaude-dock-button"));
  await flush();
  assert.equal(lastOn(loaded).get("w"), String(MAX));
  const pt = loaded.inner.dockForFile();
  assert.equal(pt.w, MAX);
  assert.equal(dock(loaded).file, false);
  loaded.api.dispose();
});

test("#11223: кнопка размера у панели от файла — выбор человека, помнится; нажатая «½» — половина", async () => {
  const loaded = await closed({ "myclaude-dock-width-v1": "300", "myclaude-dock-mode-v1": "full" });
  loaded.inner.dockForFile();
  await flush();
  assert.equal(lastOn(loaded).get("w"), "300", "запомненная уже половины — она и стоит");
  press(loaded, sizeButton(loaded, "half"));
  await flush();
  assert.deepEqual([dock(loaded).mode, dock(loaded).file], ["half", false]);
  assert.equal(lastOn(loaded).get("w"), String(Math.round(811 * Z / 2)));
  assert.deepEqual(keys(loaded), ["300", "half"]);
  loaded.api.dispose();
});

test("#11224: dock {on:false, only:\"owner\"} — панели нет или она в другом окне — ничего не шлёт", async () => {
  const loaded = await closed({});
  loaded.dom.command({ id: "off-1", action: "dock", at: "now", on: false, only: "owner" });
  assert.deepEqual(docks(loaded), [], "закрывать нечего — on=0 не уходит");
  press(loaded, byId(loaded, "myclaude-dock-button"));
  await flush();
  loaded.inner.dockState.owner = "other";
  const before = docks(loaded).length;
  loaded.dom.command({ id: "off-2", action: "dock", at: "now", on: false, only: "owner" });
  assert.equal(docks(loaded).length, before, "док у другого окна — не наш крестик");
  assert.equal(dock(loaded).on, true);
  loaded.api.dispose();
});
