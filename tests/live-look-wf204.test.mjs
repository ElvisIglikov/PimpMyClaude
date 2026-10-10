// WF204 (диагноз WF200, решение Элвиса 09.10 02:50: «Живой» в панели — главный): живой фон и его схема
// у окна всегда из look у `*`, неон и плотность — свои, по цепочке чат → сессия → main → `*`. Раньше сброс
// окна («🧹 Всё как у Claude», look:null) ложился маркером "none", который сильнее `*`, и гасил «Живой»
// у этого чата навсегда. Проверяем настоящим путём: команды через dom.command, экран — dom.sheets(),
// состояние — api.status(), память — localStorage окна.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const MAP_KEY = "myclaude-themes-v1";
const open = (map = {}, title = "Trelvis") => loadInject({ title, storage: { local: { [MAP_KEY]: JSON.stringify(map) } } });
const stored = loaded => JSON.parse(loaded.win.localStorage.getItem(MAP_KEY) ?? "{}");
const lookOf = loaded => {
  const { schemes, ...look } = JSON.parse(JSON.stringify(loaded.api.status().look));
  return look;
};
let seq = 0;
const send = (loaded, detail) => loaded.dom.command({
  id: `wf204-${++seq}`, action: "theme", at: "now", scope: "window", title: "Trelvis", ...detail,
});
const LIVE = { "*": { look: { aurora: true, scheme: "sea" } } };

test("«🧹 Всё как у Claude» в меню окна не гасит «Живой»: ни на экране, ни в памяти, ни после перезапуска", () => {
  const loaded = open(LIVE);
  assert.equal(lookOf(loaded).aurora, true);
  send(loaded, { theme: null, font: null, size: null, frame: null, look: null });
  assert.deepEqual(lookOf(loaded), { aurora: true, neon: false, dense: false, scheme: "sea", source: "window" });
  assert.ok(loaded.dom.sheets().includes("myclaude-aurora-a"), "живой фон на экране");
  assert.equal(stored(loaded)["chat:Trelvis"]?.look, undefined, "у `*` один живой фон — сбрасывать окну нечего, \"none\" не пишется");
  const again = open(stored(loaded));
  assert.equal(lookOf(again).aurora, true, "после перезапуска «Живой» на месте");
  assert.equal(lookOf(again).scheme, "sea");
});

test("сброс окна гасит свой неон поверх `*`, а живой фон и схема остаются от `*`", () => {
  const loaded = open({ "*": { look: { aurora: true, neon: true, scheme: "forest" } } });
  assert.deepEqual(lookOf(loaded), { aurora: true, neon: true, dense: false, scheme: "forest", source: "all" });
  send(loaded, { look: null });
  assert.equal(stored(loaded)["chat:Trelvis"].look, "none", "неон у `*` есть — сброс окна его перекрывает");
  const again = open(stored(loaded));
  assert.deepEqual(lookOf(again), { aurora: true, neon: false, dense: false, scheme: "forest", source: "chat" });
});

test("старые записи чатов — \"none\" и look без живого фона — «Живой» больше не гасят; неон и плотность — свои", () => {
  const none = open({ ...LIVE, "chat:Trelvis": { look: "none" } });
  assert.deepEqual(lookOf(none), { aurora: true, neon: false, dense: false, scheme: "sea", source: "chat" });
  const dense = open({ ...LIVE, "chat:Trelvis": { look: { aurora: false, neon: false, dense: true } } });
  assert.deepEqual(lookOf(dense), { aurora: true, neon: false, dense: true, scheme: "sea", source: "chat" });
  const scheme = open({ ...LIVE, "chat:Trelvis": { look: { aurora: true, scheme: "sunset" } } });
  assert.equal(lookOf(scheme).scheme, "sea", "схема — от «Живого» панели");
});

test("«Живой» выключен (у `*` нет живого фона) — старый живой фон чата не оживает, неон чата цел", () => {
  const loaded = open({ "chat:Trelvis": { look: { aurora: true, neon: true, scheme: "sunset" } } });
  assert.deepEqual(lookOf(loaded), { aurora: false, neon: true, dense: false, scheme: "violet", source: "chat" });
  assert.ok(!loaded.dom.sheets().includes("myclaude-aurora-a"));
  // Неон окна из меню окна — свой, живой фон всё так же от `*`.
  send(loaded, { look: { neon: false, dense: true } });
  assert.deepEqual(lookOf(loaded), { aurora: false, neon: false, dense: true, scheme: "violet", source: "window" });
});

test("смена чата и themes-restore — то же правило: живой фон от `*`", () => {
  const loaded = open({ ...LIVE, "chat:Другой": { look: "none" } });
  assert.equal(lookOf(loaded).aurora, true);
  loaded.document.title = "Другой";
  loaded.dom.fireKind("interval");
  assert.equal(loaded.api.status().look.aurora, true, "чат с \"none\" — «Живой» не гаснет");
  const restored = open(LIVE);
  restored.dom.command({ id: "wf204-restore", action: "themes-restore", at: "now", scope: "all",
    entries: { "chat:Trelvis": { look: "none" } } });
  assert.equal(stored(restored)["chat:Trelvis"].look, "none", "присланное доливается как есть");
  assert.equal(restored.api.status().look.aurora, true);
});

test("примерка показывает ровно примеряемое, конец примерки — снова от `*`", () => {
  const loaded = open(LIVE);
  send(loaded, { preview: true, look: { neon: true } });
  assert.equal(lookOf(loaded).neon, true);
  send(loaded, { preview: false });
  assert.deepEqual(lookOf(loaded), { aurora: true, neon: false, dense: false, scheme: "sea", source: "all" });
});

test("«Живой» всем окнам: выключили — гаснет и у окна с записью; включили — загорается", () => {
  const loaded = open({ ...LIVE, "chat:Trelvis": { look: { neon: true } } });
  assert.deepEqual(lookOf(loaded), { aurora: true, neon: true, dense: false, scheme: "sea", source: "chat" });
  send(loaded, { scope: "all", look: null });
  assert.equal(lookOf(loaded).aurora, false);
  send(loaded, { scope: "all", look: { aurora: true, scheme: "lavender" } });
  assert.equal(lookOf(loaded).aurora, true);
  assert.equal(lookOf(loaded).scheme, "lavender");
});
