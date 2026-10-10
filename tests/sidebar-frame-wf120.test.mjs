// WF120, батч B-P1b (#7111, контракт К-B2): рамка кнопки боковой панели в ответе chats().
//
// Claude выключает доступность (журнал «[a11y] … disabled»), AX кнопку «Show sidebar»
// не находит — и меню Пимпа на ⌘B мертво. Запасной путь: страница отдаёт в ответе
// probe рамку кнопки, приложение переводит её в экран по frame того же ответа.
//
// Контракт К-B2 (план WF120, правки по критику):
//   sidebar = {x, y, w, h, vw, vh} — CSS px кнопки
//   button[aria-label="Show sidebar"|"Hide sidebar"] (дробные как есть) и
//   innerWidth/innerHeight страницы; только kind "main", ПОСЛЕДНИМ полем (после
//   themes); в попапе, на чужой странице, без кнопки или с нулевой кнопкой — поля нет.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const MAIN = "https://claude.ai/epitaxy/local_aaaa-1111";
const VIEWPORT = { width: 1180.5, height: 790 };

const withButtons = buttons => dom => {
  const bar = dom.document.body.add("div", { class: "epitaxy-titlebar" });
  for (const [label, rect] of buttons) bar.add("button", { attrs: { "aria-label": label }, rect });
};
const main = (buttons, options = {}) => {
  const loaded = loadInject({
    href: MAIN, title: "Trelvis",
    geometry: { viewport: VIEWPORT, frame: [-1512, -982, 1180, 815] },
    html: withButtons(buttons),
    ...options,
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return loaded;
};
const answer = async loaded => plain(await loaded.api.chats({ nonce: "sb" }));

test("главное окно: рамка «Hide sidebar» в CSS px, дробные как есть, и размер окна страницы", async () => {
  const loaded = main([["Hide sidebar", { left: 82.5, top: 10.25, width: 28, height: 27.5 }]]);
  const got = await answer(loaded);
  assert.equal(got.kind, "main");
  assert.deepEqual(got.sidebar, { x: 82.5, y: 10.25, w: 28, h: 27.5, vw: 1180.5, vh: 790 });
  assert.deepEqual(got.frame, [-1512, -982, 1180, 815], "frame для перевода — в том же ответе");
});

test("свёрнутая панель — кнопка «Show sidebar»", async () => {
  const loaded = main([["Show sidebar", { left: 84, top: 8, width: 26, height: 26 }]]);
  assert.deepEqual((await answer(loaded)).sidebar, { x: 84, y: 8, w: 26, h: 26, vw: 1180.5, vh: 790 });
});

test("sidebar — последним полем, после themes; прежние поля на своих местах", async () => {
  const loaded = main([["Hide sidebar", { left: 82, top: 10, width: 28, height: 28 }]]);
  const keys = Object.keys(await answer(loaded));
  assert.equal(keys.at(-1), "sidebar");
  assert.equal(keys.at(-2), "themes");
  const at = keys.indexOf("working");
  assert.deepEqual(keys.slice(at - 2, at + 5), ["frame", "mic", "working", "autoContinue", "galleryCounted", "sendDelaySetting", "limits"]);
});

test("скрытая (нулевая) кнопка не в счёт — берётся видимая; нет видимой — поля нет", async () => {
  const two = main([
    ["Show sidebar", { left: 0, top: 0, width: 0, height: 0 }],
    ["Hide sidebar", { left: 82, top: 10, width: 28, height: 28 }],
  ]);
  assert.deepEqual((await answer(two)).sidebar, { x: 82, y: 10, w: 28, h: 28, vw: 1180.5, vh: 790 });

  const hidden = main([["Hide sidebar", { left: 82, top: 10, width: 0, height: 28 }]]);
  assert.ok(!("sidebar" in (await answer(hidden))), "нулевая кнопка — поля нет");

  const none = main([]);
  assert.ok(!("sidebar" in (await answer(none))), "кнопки нет — поля нет");

  const other = main([["Toggle menu", { left: 82, top: 10, width: 28, height: 28 }]]);
  assert.ok(!("sidebar" in (await answer(other))), "чужая кнопка — не кнопка панели");
});

test("размер окна страницы не годится (0 или не число) — поля нет", async () => {
  const loaded = main([["Hide sidebar", { left: 82, top: 10, width: 28, height: 28 }]]);
  loaded.win.innerWidth = 0;
  assert.ok(!("sidebar" in (await answer(loaded))));
  loaded.win.innerWidth = 1180;
  loaded.win.innerHeight = Number.NaN;
  assert.ok(!("sidebar" in (await answer(loaded))));
  loaded.win.innerHeight = 790;
  assert.equal((await answer(loaded)).sidebar.vh, 790, "размер вернулся — поле вернулось");
});

test("попап и чужая страница — поля нет, даже если такая кнопка есть", async () => {
  const parent = main([["Hide sidebar", { left: 82, top: 10, width: 28, height: 28 }]]);
  const popup = loadInject({
    href: "about:blank", title: "Trelvis", opener: parent.win,
    geometry: { frame: [100, 100, 640, 900] },
    html: withButtons([["Show sidebar", { left: 84, top: 8, width: 26, height: 26 }]]),
  });
  const pop = plain(await popup.api.chats({ nonce: "pop" }));
  assert.equal(pop.kind, "popout");
  assert.ok(!("sidebar" in pop), "у попапа поля нет");

  const stranger = loadInject({
    href: "data:text/html,x",
    html: withButtons([["Hide sidebar", { left: 82, top: 10, width: 28, height: 28 }]]),
  });
  const miss = plain(await stranger.api.chats({ nonce: "o" }));
  assert.equal(miss.kind, "other");
  assert.ok(!("sidebar" in miss));
});

test("рамка — живая: панель свернули (кнопка сменилась и съехала) — следующий ответ уже с новой", async () => {
  const loaded = main([["Hide sidebar", { left: 250, top: 10, width: 28, height: 28 }]]);
  assert.equal((await answer(loaded)).sidebar.x, 250);
  const hide = loaded.document.querySelector('button[aria-label="Hide sidebar"]');
  hide.setAttribute("aria-label", "Show sidebar");
  hide.rect = { left: 84, top: 8, width: 26, height: 26 };
  assert.deepEqual((await answer(loaded)).sidebar, { x: 84, y: 8, w: 26, h: 26, vw: 1180.5, vh: 790 });
});

test("sidebar: отрицательные/вне viewport/нечисловые координаты и скрытая кнопка не выдаются", async () => {
  for (const rect of [
    { left: -1, top: 0, width: 28, height: 28 },
    { left: 1170, top: 0, width: 28, height: 28 },
    { left: 50, top: 780, width: 28, height: 28 },
    { left: "50", top: 0, width: 28, height: 28 },
    { left: Infinity, top: 0, width: 28, height: 28 },
  ]) {
    const loaded = main([["Hide sidebar", rect]]);
    assert.ok(!("sidebar" in await answer(loaded)));
  }
  const loaded = main([["Hide sidebar", { left: 50, top: 0, width: 28, height: 28 }]]);
  loaded.document.querySelector('button[aria-label="Hide sidebar"]').setAttribute("hidden", "");
  assert.ok(!("sidebar" in await answer(loaded)));
  loaded.win.innerWidth = true;
  assert.ok(!("sidebar" in await answer(loaded)));
});
