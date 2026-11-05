// «Ждёт тебя» (раздел 12и inject.js, #7177, WF83): чей чат ждёт слова Элвиса — waitState.why
// (awaiting — вопрос или разрешение, ready — непрочитанный ответ, done — ход кончен на наших глазах
// и окна с тех пор не трогали) и kind. Его берут рамка «ждут твоего слова» (12и¹, #8282), «Сам»,
// холодный кэш отсчёта. Свечения окна нет (дыхание — #8112, 29.09; свет диктовки — page-69): до WF248
// этот набор звался wait-glow и сторожил выключенный свет; due/dismissed/lights сняты вместе с ним.
//
// Стенд — как Claude 2.2553.13 по разведке 23.09: строка сайдбара
// [data-row-key="code:<id>"] внутри [data-testid="sidebar"], сессия чата — пропс
// session в React-волокне строки (liveStatus, isRunning, hasCompleted,
// isUnread). Время раздела — аргумент waitTick (люк), шаг сердца не ждём.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";
import { sidebarRow } from "./stands.mjs";

const A = "local_aaaa-1111";
const B = "local_bbbb-2222";
const CHAT_ID_KEY = "myclaude-chat-v1";

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
        sidebarRow(bar, A, a);
        sidebarRow(bar, B, b);
      }
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return { loaded, a, b };
};
const wait = loaded => plain(loaded.api.status().wait);
const idle = s => Object.assign(s, { liveStatus: "idle", isRunning: false });
const run = s => Object.assign(s, { liveStatus: "running", isRunning: true });

test("ход кончен без касания окна — «done»; окно не светит (#8112: «все чаты мигают… Вырубай»)", () => {
  const { loaded, a } = page();
  const tick = loaded.inner.waitTick;
  let t = Date.now();
  tick(t);
  assert.deepEqual(wait(loaded), { why: null, kind: "running" });
  idle(a);
  tick(t += 1000);
  assert.deepEqual(wait(loaded), { why: "done", kind: "idle" });
  assert.equal(loaded.document.querySelector("#myclaude-wait-glow"), null, "узла свечения нет");
  assert.equal(loaded.dom.running().length, 0, "дыхания нет");
});

test("касание окна гасит «done»; тот же конец хода не возвращается, новый ход — да", () => {
  const { loaded, a } = page();
  const tick = loaded.inner.waitTick;
  let t = Date.now();
  tick(t); idle(a);
  tick(t += 1000);
  assert.equal(wait(loaded).why, "done");
  loaded.win.dispatchEvent({ type: "keydown", key: "a" });
  tick(t += 1000);
  assert.equal(wait(loaded).why, null, "клавиша погасила");
  for (let step = 0; step < 4; step += 1) tick(t += 1000);
  assert.equal(wait(loaded).why, null, "тот же конец хода второй раз не ждёт");
  run(a); tick(t += 1000);
  idle(a); tick(t += 1000);
  assert.equal(wait(loaded).why, "done", "новый ход — снова ждёт");
  loaded.win.dispatchEvent({ type: "pointerdown" });
  tick(t += 1000);
  assert.equal(wait(loaded).why, null, "нажатие мыши тоже гасит");
  run(a); tick(t += 1000);
  idle(a); tick(t += 1000);
  loaded.win.dispatchEvent({ type: "focus" });
  tick(t += 1000);
  assert.equal(wait(loaded).why, null, "и фокус окна");
});

test("касание посреди хода конец хода не гасит (замер 23.09 12:54)", () => {
  const { loaded, a } = page();
  const tick = loaded.inner.waitTick;
  let t = Date.now();
  tick(t);
  loaded.win.dispatchEvent({ type: "keydown", key: "a" });
  loaded.win.dispatchEvent({ type: "pointerdown" });
  idle(a);
  tick(t += 1000);
  assert.equal(wait(loaded).why, "done", "Элвис трогал окно, пока чат работал, — ответ всё равно ждёт");
});

test("вопрос человеку — awaiting, касание его не снимает; чат пошёл работать — не ждёт", () => {
  const { loaded, a } = page();
  const tick = loaded.inner.waitTick;
  let t = Date.now();
  a.liveStatus = "awaiting";
  tick(t);
  assert.deepEqual(wait(loaded), { why: "awaiting", kind: "awaiting" });
  loaded.win.dispatchEvent({ type: "keydown", key: "a" });
  tick(t += 1000);
  assert.equal(wait(loaded).why, "awaiting", "ответить всё равно надо");
  run(a);
  tick(t += 1000);
  assert.deepEqual(wait(loaded), { why: null, kind: "running" }, "разрешение нажали — чат работает");
});

test("непрочитанный ответ — ready и без увиденного хода", () => {
  const { loaded } = page({ a: session(A, { liveStatus: "idle", isRunning: false, hasCompleted: true, isUnread: true }) });
  const tick = loaded.inner.waitTick;
  let t = Date.now();
  tick(t += 1000);
  assert.deepEqual(wait(loaded), { why: "ready", kind: "ready" });
});

test("чат прочитан и не работал при нас — не ждёт; строки нет — молчим", () => {
  const { loaded } = page({ a: session(A, { liveStatus: "idle", isRunning: false }) });
  let t = Date.now();
  for (let step = 0; step < 5; step += 1) loaded.inner.waitTick(t += 1000);
  assert.deepEqual(wait(loaded), { why: null, kind: "idle" });

  const bare = page({ sidebar: false }).loaded;
  for (let step = 0; step < 5; step += 1) bare.inner.waitTick(t += 1000);
  assert.equal(wait(bare).why, null);
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
  tick(t += 1000);
  assert.equal(wait(popup).why, "done", "ждёт попап, а не главное окно");
  main.inner.waitTick(t);
  assert.equal(wait(main).why, null);
});
