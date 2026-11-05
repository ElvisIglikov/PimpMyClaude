// #11654 (+ #11634; контракт К-DOCK-6 — docs/contracts/660-11654-dock-bar.md): страница шлёт строку «Файлы» над местом —
// `&bx&by&bh` после `wh` в `/dock?on=1` и в `/open-html … dock=1`. by, bh — кнопка «Файлы», bx — правый край кнопок
// размера + 6 CSS px, всё × z. Негодная по К-DOCK-6b строка не шлётся. Сцена — как в dock-size-wf282: «Show sidebar»
// 84,8 28×28, чат 811×470 CSS px, z = 1067/811; кнопки размера кончаются на 260 CSS px → bx = round(266 × z) = 350.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const CHAT = "local_0f3a9c1e-7b2d-4e6f-8a1b-5c4d3e2f1a0b";
const FRAME = [0, 29, 1067, 618];
const Z = 1067 / 811;
const HALF = Math.round(811 * Z / 2);
const BAR = "&bx=350&by=11&bh=37";
const UP = { ok: true, viewer: "up", docked: true, owner: "this" };
const flush = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };

const scene = ({ storage = {}, button = true } = {}) => {
  const box = { calls: [] };
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, geometry: { viewport: { width: 811, height: 470 }, frame: FRAME }, storage: { local: storage },
    html: dom => {
      const rect = (left, top, width, height) => ({ left, top, width, height });
      const root = dom.document.body.add("div", { class: "dframe-root draggable-none cds-root text-primary", rect: rect(0, 0, 811, 470) });
      const aside = root.add("aside", { class: "dframe-sidebar df-hub-rail", rect: rect(84, 6, 28, 32) });
      const chrome = aside.add("div", { class: "df-collapsed-chrome flex items-center", rect: rect(84, 6, 28, 32) });
      if (button) chrome.add("button", { class: "cds-reset df-compact-trigger", rect: rect(84, 8, 28, 28),
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
const byId = (loaded, id) => loaded.document.getElementById(id);
const px = (node, name) => Number.parseFloat(node.style.getPropertyValue(name));
const press = (loaded, node) => {
  for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) {
    const event = { type, target: node, isTrusted: true, bubbles: true, cancelable: true, button: 0, buttons: type.endsWith("down") ? 1 : 0, detail: 1, pointerId: 1 };
    if (loaded.document.dispatchEvent(event)) node.dispatchEvent({ ...event });
  }
};
const lastOn = loaded => loaded.box.calls.filter(url => url.includes("/dock?on=1")).at(-1);

test("К-DOCK-6a: «½» — /dock?on=1 несёт bx, by, bh после wh; это строка кнопок «Файлы» и размера × z", async () => {
  const loaded = scene({ storage: { "myclaude-dock-mode-v1": "half" } });
  await flush();
  press(loaded, byId(loaded, "myclaude-dock-button"));
  await flush();
  assert.match(lastOn(loaded), new RegExp(`/dock\\?on=1&vis=1&x=0&y=55&w=${HALF}&h=563&wx=0&wy=29&ww=1067&wh=618${BAR}(&bg=[0-9a-f]{6})?&chat=${CHAT}&seq=\\d+$`));
  const button = byId(loaded, "myclaude-dock-button");
  const sizes = byId(loaded, "myclaude-dock-sizes");
  assert.equal(Math.round(px(button, "top") * Z), 11, "by — верх «Файлы» × z");
  assert.equal(Math.round(px(button, "height") * Z), 37, "bh — высота «Файлы» × z");
  assert.equal(Math.round((px(sizes, "left") + px(sizes, "width") + 6) * Z), 350, "bx — правый край кнопок размера + 6 × z");
  loaded.api.dispose();
});

test("К-DOCK-6a: файл из чата в широкую панель — /open-html … dock=1 несёт строку после wh, до frame и bg", async () => {
  const loaded = scene({ storage: { "myclaude-dock-width-v1": "5000" } });
  await flush();
  const pt = loaded.inner.dockForFile();
  assert.deepEqual([pt.bx, pt.by, pt.bh], [350, 11, 37]);
  const url = loaded.inner.htmlChromeUrl("/tmp/a.html", "click", CHAT, FRAME, "#1c1917", pt);
  assert.equal(url, `http://127.0.0.1:47615/open-html?mode=click&dock=1&path=%2Ftmp%2Fa.html&chat=${CHAT}` +
    `&x=0&y=55&w=${pt.w}&h=563&wx=0&wy=29&ww=1067&wh=618${BAR}&frame=0,29,1067,618&bg=1c1917`);
  loaded.api.dispose();
});

test("К-DOCK-6b: узкая панель (полосе < 80 pt) — строки нет, место как было", async () => {
  const loaded = scene();
  await flush();
  press(loaded, byId(loaded, "myclaude-dock-button"));
  await flush();
  assert.match(lastOn(loaded), new RegExp(`&wh=618(&bg=[0-9a-f]{6})?&chat=${CHAT}&seq=\\d+$`));
  assert.doesNotMatch(lastOn(loaded), /&b[xyh]=/);
  loaded.api.dispose();
});

test("К-DOCK-6a: нет кнопки «Show/Hide sidebar» — строки в месте нет", () => {
  const loaded = scene({ button: false });
  const measure = loaded.inner.dockMeasure();
  assert.ok(measure);
  assert.deepEqual([measure.pt.bx, measure.pt.by, measure.pt.bh], [undefined, undefined, undefined]);
  loaded.api.dispose();
});

test("К-DOCK-6b: проверка строки — негодно, ключа нет — место без строки; bx левее места годен", () => {
  const loaded = scene();
  const keys = loaded.inner.dockPlaceKeys;
  const place = { x: 100, y: 55, w: 534, h: 563, wx: 0, wy: 29, ww: 1067, wh: 618 };
  const base = "x=100&y=55&w=534&h=563&wx=0&wy=29&ww=1067&wh=618";
  const bar = { bx: 350, by: 11, bh: 37 };
  assert.equal(keys({ ...place, ...bar }), `${base}&bx=350&by=11&bh=37`);
  assert.equal(keys({ ...place, ...bar, bx: 40 }), `${base}&bx=40&by=11&bh=37`, "bx < x — у получателя bx = x, годно");
  assert.equal(keys({ ...place, ...bar, bx: 554 }), `${base}&bx=554&by=11&bh=37`, "ровно 80 pt полосе — годно");
  assert.equal(keys({ ...place, ...bar, by: 18 }), `${base}&bx=350&by=18&bh=37`, "by + bh = y — годно");
  for (const [bad, why] of [[{ bx: 555 }, "полосе < 80"], [{ by: -1 }, "by < 0"], [{ bh: 15 }, "bh < 16"], [{ bh: 65 }, "bh > 64"],
    [{ by: 19 }, "by + bh > y"], [{ bx: 1.5 }, "дробь"], [{ bh: undefined }, "нет ключа"], [{ bx: 1000000 }, "больше 6 знаков"]]) {
    assert.equal(keys({ ...place, ...bar, ...bad }), base, why);
  }
  assert.equal(keys({ ...place, w: 0, ...bar }), "", "битое место — как было: ничего");
  loaded.api.dispose();
});
