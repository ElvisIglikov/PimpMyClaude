// WF279 (#10760, контракт К-DOCK-4 — docs/contracts/580-wf279-dock-shot.md): кадр панели материалов в подложке.
//
// Слово Элвиса 23.10.2026: «Сделай, чтобы на скриншоте тоже было видно. Это важно. И в Диктаторе, и в других программах
// скриншотилках». Панель — окно PimpViewer поверх окна Claude; снимок окна Claude берёт подложку — в ней кадр панели.
// Стенд без слепка: подложку ставим руками (её место — забота 12п⁴), fetch отвечает /dock-shot по box.reply.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_0f3a9c1e-7b2d-4e6f-8a1b-5c4d3e2f1a0b";
const JPEG = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3];
const flush = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };

const scene = () => {
  const box = { reply: { status: 200, version: "100.7", bytes: JPEG }, calls: [] };
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, geometry: { viewport: { width: 811, height: 470 }, frame: [0, 29, 1067, 618] },
    html: dom => {
      dom.window.fetch = address => {
        const url = String(address);
        box.calls.push(url);
        if (!url.includes("/dock-shot?")) return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve({}) });
        const { status, version, bytes } = box.reply;
        return Promise.resolve({ ok: status === 200, status, headers: { get: name => name === "X-Pimp-Shot" ? version : null },
          arrayBuffer: () => Promise.resolve(new Uint8Array(bytes).buffer) });
      };
      return {};
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const inner = loaded.inner;
  inner.dockState.want = true;
  inner.dockState.viewer = "up";
  return { loaded, inner, box, place: () => inner.dockNodes.place };
};
const shots = box => box.calls.filter(url => url.includes("/dock-shot?"));

test("WF279 #10760: кадр панели ложится фоном подложки, та же версия — без перерисовки, 404 — кадр прочь", async () => {
  const { loaded, inner, box, place } = scene();
  inner.dockShotTick();
  await flush();
  assert.equal(shots(box).length, 0, "подложки нет — не спрашиваем");
  place().style.setProperty("display", "block");
  inner.dockShotTick();
  await flush();
  assert.match(shots(box)[0], /^http:\/\/127\.0\.0\.1:47615\/dock-shot\?since=$/);
  const first = place().style.getPropertyValue("--myclaude-dock-shot");
  assert.match(first, /^url\("(blob:|data:)/, "кадр в подложке");
  assert.equal(plain(loaded.api.status().dockShot).got, 1);
  box.reply = { status: 204 };
  inner.dockShotTick();
  await flush();
  assert.match(shots(box)[1], /since=100\.7$/, "спрашиваем с версией");
  assert.equal(place().style.getPropertyValue("--myclaude-dock-shot"), first, "204 — кадр тот же");
  box.reply = { status: 200, version: "200.9", bytes: [1, 2, 3] };
  inner.dockShotTick();
  await flush();
  assert.equal(place().style.getPropertyValue("--myclaude-dock-shot"), first, "не JPEG — не кладём");
  assert.equal(plain(loaded.api.status().dockShot).errors, 1);
  box.reply = { status: 404 };
  inner.dockShotTick();
  await flush();
  assert.equal(place().style.getPropertyValue("--myclaude-dock-shot"), "", "кадра нет — фон прочь");
  assert.equal(inner.dockShot.version, "");
});

test("WF279 #10760: подложка снята, окно скрыто или PimpViewer не «up» — не спрашиваем; снята — кадр прочь", async () => {
  const { inner, box, place } = scene();
  place().style.setProperty("display", "block");
  inner.dockShotTick();
  await flush();
  assert.ok(place().style.getPropertyValue("--myclaude-dock-shot"));
  inner.dockState.viewer = "down";
  inner.dockShotTick();
  await flush();
  assert.equal(shots(box).length, 1, "PimpViewer не «up» — тишина");
  place().style.setProperty("display", "none");
  inner.dockShotTick();
  assert.equal(place().style.getPropertyValue("--myclaude-dock-shot"), "", "подложка снята — кадр прочь");
});

test("WF279 #10760: опрос раз в 700 мс только в главном окне; правило фона подложки в таблице", () => {
  const { loaded, inner } = scene();
  assert.ok([...loaded.dom.timers.values()].some(item => item.kind === "interval" && item.ms === inner.DOCK_SHOT_MS));
  const css = loaded.dom.queryAll("style").map(style => style.textContent).join("\n");
  assert.match(css, /background-image:var\(--myclaude-dock-shot,none\);background-size:100% 100%/);
});
