// Свечение «ждёт тебя» (раздел 12и inject.js, #7177, WF83): окно, чей чат ждёт
// слова Элвиса, мягко дышит светом по краю цветом акцента. Гаснет от касания
// окна (клавиша, мышь, фокус) и не зажигается, пока чат снова не поработает.
//
// Стенд — как Claude 2.2553.13 по разведке 23.09: строка сайдбара
// [data-row-key="code:<id>"] внутри [data-testid="sidebar"], сессия чата — пропс
// session в React-волокне строки (liveStatus, isRunning, hasCompleted,
// isUnread). Время раздела — аргумент waitTick (люк), шаг сердца не ждём.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const A = "local_aaaa-1111";
const B = "local_bbbb-2222";
const CHAT_ID_KEY = "myclaude-chat-v1";

const addRow = (bar, id, session) => {
  const row = bar.add("div", { attrs: { "data-row-key": `code:${id}` } });
  row["__reactFiber$test"] = {
    memoizedProps: { "data-row-key": `code:${id}` },
    return: { memoizedProps: { session }, return: null },
  };
};
const session = (id, extra = {}) => ({
  ref: { kind: "code", id }, title: id, liveStatus: "running", isRunning: true,
  hasPendingApproval: false, pendingPermissions: 0, hasCompleted: false, isUnread: false, ...extra,
});

// Главное окно в чате A; в списке слева — A и B.
const page = ({ a = session(A), b = session(B, { liveStatus: "idle", isRunning: false }), sidebar = true, focus = false } = {}) => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${A}`, title: "Claude", hasFocus: focus,
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({});
      if (sidebar) {
        const bar = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
        addRow(bar, A, a);
        addRow(bar, B, b);
      }
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return { loaded, a, b };
};
const glow = loaded => loaded.document.querySelector("#myclaude-wait-glow");
const wait = loaded => plain(loaded.api.status().wait);
const idle = s => Object.assign(s, { liveStatus: "idle", isRunning: false });
const run = s => Object.assign(s, { liveStatus: "running", isRunning: true });

test("ход кончен без касания окна — «ждёт тебя» для полоски, но окно больше не мигает (#8112)", () => {
  const { loaded, a } = page();
  const tick = loaded.inner.waitTick;
  let t = Date.now();
  tick(t);
  assert.equal(wait(loaded).kind, "running");
  assert.equal(wait(loaded).due, false);
  idle(a);
  tick(t += 1000);
  assert.equal(wait(loaded).why, "done");
  assert.equal(wait(loaded).due, false, "не сразу: метка держится WAIT_HOLD_MS");
  tick(t += 1000);
  tick(t += 1000);
  const state = wait(loaded);
  assert.equal(state.due, true);
  assert.equal(state.on, false, "слово Элвиса 29.09: «все чаты мигают… Вырубай»");
  assert.equal(state.lights, 0);
  assert.notEqual(glow(loaded).style.getPropertyValue("display"), "block");
  assert.equal(loaded.dom.running().filter(item => item.node === glow(loaded)).length, 0, "дыхания нет");
});

test("касание окна гасит свет; зажжётся только после нового хода", () => {
  const { loaded, a } = page();
  const tick = loaded.inner.waitTick;
  let t = Date.now();
  tick(t); idle(a);
  for (let step = 0; step < 4; step += 1) tick(t += 1000);
  assert.equal(wait(loaded).due, true);
  loaded.win.dispatchEvent({ type: "keydown", key: "a" });
  assert.equal(wait(loaded).due, false, "клавиша погасила");
  assert.equal(glow(loaded).style.getPropertyValue("display"), "none");
  assert.equal(loaded.dom.running().filter(item => item.node === glow(loaded)).length, 0, "анимация снята");
  for (let step = 0; step < 4; step += 1) tick(t += 1000);
  assert.equal(wait(loaded).due, false, "тот же конец хода второй раз не светит");
  run(a); tick(t += 1000);
  idle(a);
  for (let step = 0; step < 4; step += 1) tick(t += 1000);
  assert.equal(wait(loaded).due, true, "новый ход — новый свет");
  loaded.win.dispatchEvent({ type: "pointerdown" });
  assert.equal(wait(loaded).due, false, "нажатие мыши тоже гасит");
});

test("касание посреди хода конец хода не гасит (замер 23.09 12:54)", () => {
  const { loaded, a } = page();
  const tick = loaded.inner.waitTick;
  let t = Date.now();
  tick(t);
  loaded.win.dispatchEvent({ type: "keydown", key: "a" });
  loaded.win.dispatchEvent({ type: "pointerdown" });
  idle(a);
  for (let step = 0; step < 4; step += 1) tick(t += 1000);
  assert.equal(wait(loaded).due, true, "Элвис трогал окно, пока чат работал, — ответ всё равно светит");
});

test("вопрос человеку светит; разрешение, которое тут же нажали, — нет", () => {
  const { loaded, a } = page();
  const tick = loaded.inner.waitTick;
  let t = Date.now();
  a.liveStatus = "awaiting";
  tick(t);
  tick(t += 1000);
  run(a);
  tick(t += 1000);
  tick(t += 1000);
  assert.equal(wait(loaded).due, false, "метка прожила секунду — Авто-Allow успел");
  a.liveStatus = "awaiting";
  for (let step = 0; step < 4; step += 1) tick(t += 1000);
  assert.equal(wait(loaded).due, true);
  assert.equal(wait(loaded).why, "awaiting");
});

test("непрочитанный ответ светит и без увиденного хода", () => {
  const { loaded } = page({ a: session(A, { liveStatus: "idle", isRunning: false, hasCompleted: true, isUnread: true }) });
  const tick = loaded.inner.waitTick;
  let t = Date.now();
  for (let step = 0; step < 4; step += 1) tick(t += 1000);
  assert.equal(wait(loaded).why, "ready");
  assert.equal(wait(loaded).due, true);
});

test("чат прочитан и не работал при нас — не светит; строки нет — молчим", () => {
  const { loaded } = page({ a: session(A, { liveStatus: "idle", isRunning: false }) });
  let t = Date.now();
  for (let step = 0; step < 5; step += 1) loaded.inner.waitTick(t += 1000);
  assert.equal(wait(loaded).on, false);
  assert.equal(wait(loaded).why, null);

  const bare = page({ sidebar: false }).loaded;
  for (let step = 0; step < 5; step += 1) bare.inner.waitTick(t += 1000);
  assert.equal(wait(bare).on, false);
  assert.equal(wait(bare).kind, null, "без строки чата состояние неизвестно");
});

test("попап читает строку своего чата в списке родителя", () => {
  const { loaded: main, b } = page();
  const popup = loadInject({
    href: "about:blank", title: "Диктатор", hasFocus: false, opener: main.win,
    storage: { session: { [CHAT_ID_KEY]: JSON.stringify({ id: B, title: "Диктатор" }) } },
  });
  assert.equal(popup.error, null, String(popup.error?.stack ?? popup.error));
  const tick = popup.inner.waitTick;
  let t = Date.now();
  run(b); tick(t);
  assert.equal(wait(popup).kind, "running");
  idle(b);
  for (let step = 0; step < 4; step += 1) tick(t += 1000);
  assert.equal(wait(popup).due, true, "свет у попапа, а не у главного окна");
  assert.equal(wait(main).due, false);
});

test("окно, в которое говорят: Диктатор пишет и фокус — ровный яркий свет; без фокуса или запись кончилась — нет (#8112)", () => {
  const command = (loaded, detail) => loaded.win.dispatchEvent({ type: "myclaude-command", detail });
  const talk = loaded => plain(loaded.api.status().talk);
  const away = page().loaded;
  command(away, { id: "t1", action: "dictating", on: true });
  assert.equal(talk(away).dictating, true);
  assert.equal(talk(away).lit, false, "окно без фокуса не светит — текст ляжет не сюда");

  const here = page({ focus: true }).loaded;
  command(here, { id: "t1", action: "dictating", on: true });
  assert.equal(talk(here).lit, true);
  const node = glow(here);
  assert.equal(node.style.getPropertyValue("display"), "block");
  assert.match(node.style.getPropertyValue("box-shadow"), /inset 0 0 0 4px /, "ярче неоновой рамки");
  assert.equal(here.dom.running().filter(item => item.node === node).length, 0, "ровно, без дыхания");
  command(here, { id: "t2", action: "dictating", on: false });
  assert.equal(talk(here).lit, false);
  assert.equal(node.style.getPropertyValue("display"), "none");
});

test("dispose уносит узел свечения и его анимацию", () => {
  const { loaded, a } = page();
  let t = Date.now();
  loaded.inner.waitTick(t); idle(a);
  for (let step = 0; step < 4; step += 1) loaded.inner.waitTick(t += 1000);
  assert.equal(wait(loaded).due, true);
  loaded.api.dispose();
  assert.equal(loaded.document.querySelector("#myclaude-wait-glow"), null);
  assert.equal(loaded.dom.running().length, 0);
});
