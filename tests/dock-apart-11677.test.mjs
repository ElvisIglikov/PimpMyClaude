// #11677 (контракт К-DOCK-1 — docs/contracts/560-wf277-dock.md). Элвис 05.11: «PimpViewer был отдельным приложением
// наверху… Чтоб мне документы было удобно смотреть HTML». Ответ /dock несёт apart — отдельное окно PimpViewer на экране,
// дока нет. Тогда файл из чата идёт прежним путём (`mode=click` без dock=1 — в то окно), панель в Claude сама не встаёт.
// Кнопка «PMP» — по-прежнему панель в Claude; панель уже стоит здесь — файлы в неё, как раньше.
// Сцена — как dock-file-narrow-wf302: чат 811×470 CSS px, окно 1067×618 точек.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_0f3a9c1e-7b2d-4e6f-8a1b-5c4d3e2f1a0b";
const FRAME = [0, 29, 1067, 618];
const flush = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };

const scene = reply => {
  const box = { calls: [], reply };
  const nodes = {};
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, geometry: { viewport: { width: 811, height: 470 }, frame: FRAME },
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
      const row = host.add("div", { class: "dframe-pane dframe-pane-primary", rect: rect(0, 0, 811, 470) })
        .add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" }, rect: rect(8, 0, 471, 462) })
        .add("div", { attrs: { "data-testid": "transcript-rows" } })
        .add("div", { attrs: { "data-testid": "transcript-row", "data-index": "9" } });
      nodes.html = row.add("div", { class: "prose" }).add("p").add("a", { attrs: { href: "/tmp/16.html" }, text: "16.html" });
      dom.window.fetch = address => {
        const url = String(address);
        box.calls.push(url);
        const answer = url.includes("/dock?") ? box.reply : url.includes("/open-html?") ? { taken: true, opened: true } : {};
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
const opens = loaded => loaded.box.calls.filter(url => url.includes("/open-html?"));
const click = (loaded, target) => loaded.document.dispatchEvent({ type: "click", isTrusted: true, target, button: 0, detail: 1 });
const press = (loaded, node) => {
  for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) {
    const event = { type, target: node, isTrusted: true, bubbles: true, cancelable: true, button: 0, buttons: type.endsWith("down") ? 1 : 0, detail: 1, pointerId: 1 };
    if (loaded.document.dispatchEvent(event)) node.dispatchEvent({ ...event });
  }
};

test("#11677: отдельное окно PimpViewer на экране — файл из чата туда (click без dock=1), панель в Claude не встаёт", async () => {
  const loaded = scene({ ok: true, viewer: "up", apart: true });
  await flush();
  assert.deepEqual([dock(loaded).button, dock(loaded).on, dock(loaded).apart], [true, false, true]);
  assert.equal(loaded.inner.dockForFile(), null);
  assert.equal(click(loaded, loaded.nodes.html), false, "клик взят страницей");
  assert.match(opens(loaded).at(-1), /^http:\/\/127\.0\.0\.1:47615\/open-html\?mode=click&path=%2Ftmp%2F16\.html&chat=[^&]+&frame=0,29,1067,618/);
  assert.ok(!opens(loaded).some(url => url.includes("dock=1")));
  assert.deepEqual([dock(loaded).on, dock(loaded).placed, dock(loaded).opens], [false, false, 0]);
  assert.ok(!loaded.box.calls.some(url => url.includes("/dock?on=1")), "док не просили");
  loaded.api.dispose();
});

test("#11677: окна PimpViewer не видно (apart false или старый Пимп без поля) — файл в панель, как раньше", async () => {
  for (const reply of [{ ok: true, viewer: "up", apart: false }, { ok: true, viewer: "up" }]) {
    const loaded = scene(reply);
    await flush();
    assert.equal(dock(loaded).apart, false);
    click(loaded, loaded.nodes.html);
    assert.match(opens(loaded).at(-1), /\/open-html\?mode=click&dock=1&path=%2Ftmp%2F16\.html&/);
    assert.equal(dock(loaded).on, true, "панель встала сама");
    loaded.api.dispose();
  }
});

test("#11677: «PMP» нажата — панель здесь, файлы в неё, даже если окно PimpViewer было на экране", async () => {
  const loaded = scene({ ok: true, viewer: "up", apart: true });
  await flush();
  loaded.box.reply = { ok: true, viewer: "up", docked: true, owner: "this", apart: false };
  press(loaded, loaded.document.getElementById("myclaude-dock-button"));
  await flush();
  assert.deepEqual([dock(loaded).on, dock(loaded).apart], [true, false]);
  // Даже если ответ со стороны сказал apart (окно вернулось) — нажатая панель здесь сильнее.
  loaded.inner.dockState.apart = true;
  click(loaded, loaded.nodes.html);
  assert.match(opens(loaded).at(-1), /\/open-html\?mode=click&dock=1&path=%2Ftmp%2F16\.html&/);
  loaded.api.dispose();
});
