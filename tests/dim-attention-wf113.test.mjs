// Притемнение попапов и рамка «ждут твоего слова» (раздел 12и¹ inject.js, WF113).
// Слово Элвиса #8256: «все окна Клауда, кроме твоего, главного, притемнить… Не хочу
// вот эту суету видеть»; #8282: чат, где ждут слова Элвиса, ярко мигает.
// Команда dim {on, level} → localStorage["myclaude-dim-v1"]; вуаль #myclaude-dim —
// только в попапе, не в фокусе и не при горящей рамке. Рамка #myclaude-attn-frame —
// по признаку «ждёт тебя» раздела 12и (awaiting или ход кончен со строкой «жду»/«упал»), гаснет от ввода в поле или
// фокуса окна дольше 3 с. Время раздела — аргумент тиков (люк), сердце не ждём.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const A = "local_aaaa-1111";
const B = "local_bbbb-2222";
const CHAT_ID_KEY = "myclaude-chat-v1";
const KEY = "myclaude-dim-v1";

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
const idle = s => Object.assign(s, { liveStatus: "idle", isRunning: false });
const run = s => Object.assign(s, { liveStatus: "running", isRunning: true });

// Главное окно в чате A (в списке слева A и B) и попап чата B.
const stand = ({ local = {}, focus = false } = {}) => {
  const a = session(A);
  const b = session(B);
  const main = loadInject({
    href: `https://claude.ai/epitaxy/${A}`, title: "Claude", hasFocus: false,
    storage: { local: { "myclaude-auto-allow-roam": "off", ...local } },
    html: dom => {
      const parts = dom.composer({});
      const bar = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
      addRow(bar, A, a);
      addRow(bar, B, b);
      return parts;
    },
  });
  assert.equal(main.error, null, String(main.error?.stack ?? main.error));
  const popup = loadInject({
    href: "about:blank", title: "Диктатор", hasFocus: focus, opener: main.win,
    storage: { local: { "myclaude-auto-allow-roam": "off", ...local }, session: { [CHAT_ID_KEY]: JSON.stringify({ id: B, title: "Диктатор" }) } },
    html: dom => dom.composer({}),
  });
  assert.equal(popup.error, null, String(popup.error?.stack ?? popup.error));
  return { main, popup, a, b };
};
let seq = 0;
const dim = (loaded, fields) => loaded.win.dispatchEvent({
  type: "myclaude-command", detail: { id: `dim-${seq += 1}`, action: "dim", at: new Date().toISOString(), ...fields },
});
const dimStatus = loaded => { const { keep, ...rest } = plain(loaded.api.status().dim); assert.deepEqual(keep, []); return rest; };
const keepOf = loaded => plain(loaded.api.status().dim).keep;
const veil = loaded => loaded.document.getElementById("myclaude-dim");
const frame = loaded => loaded.document.getElementById("myclaude-attn-frame");
const attn = loaded => {
  const { on, since } = plain(loaded.api.status().attention);
  return { on, since };
};
const setFocus = (loaded, on) => {
  loaded.win.__hasFocus = on;
  loaded.win.dispatchEvent({ type: on ? "focus" : "blur" });
};
// Шаг обоих разделов: 12и считает признак, 12и¹ — рамку.
const step = (loaded, t) => { loaded.inner.waitTick(t); loaded.inner.attnFrameTick(t); };
const steps = (loaded, t, n) => { for (let i = 0; i < n; i += 1) step(loaded, t += 1000); return t; };
// Строка состояния последнего ответа (раздел 2б): «жду» / «упал» / «готово».
const says = (loaded, state) => { loaded.inner.progressState.info = state ? { wf: 1, of: 3, state } : null; };
const want = loaded => plain(loaded.api.status().attention).want;
const pulses = loaded => loaded.dom.running().filter(anim => anim.node === frame(loaded));

test("по умолчанию притемнения нет; dim кладёт {on, level} в localStorage", () => {
  const { main, popup } = stand();
  assert.deepEqual(dimStatus(popup), { on: false, level: 0.5, veil: false });
  assert.equal(veil(popup).style.getPropertyValue("display"), "none");
  dim(main, { on: true, level: 0.6 });
  assert.deepEqual(JSON.parse(main.win.localStorage.getItem(KEY)), { on: true, level: 0.6, keep: [] });
  assert.deepEqual(dimStatus(main), { on: true, level: 0.6, veil: false }, "главное окно — никогда");
  assert.equal(veil(main).style.getPropertyValue("display"), "none");
});

test("попап без фокуса темнеет плавно и мимо мыши; фокус снимает вуаль сразу, уход — возвращает", () => {
  const { popup } = stand();
  dim(popup, { on: true, level: 0.7 });
  const node = veil(popup);
  assert.equal(dimStatus(popup).veil, true);
  assert.equal(node.style.getPropertyValue("display"), "block");
  assert.equal(node.style.getPropertyValue("opacity"), "1");
  assert.equal(node.style.getPropertyValue("background"), "rgba(0,0,0,0.7)");
  assert.equal(node.style.getPropertyValue("pointer-events"), "none");
  assert.equal(node.style.getPropertyValue("position"), "fixed");
  assert.match(node.style.getPropertyValue("transition"), /opacity 200ms/);
  setFocus(popup, true);
  assert.equal(dimStatus(popup).veil, false);
  assert.equal(node.style.getPropertyValue("opacity"), "0", "гаснет переходом, узел пока на месте");
  node.dispatchEvent({ type: "transitionend" });
  assert.equal(node.style.getPropertyValue("display"), "none", "угас — ушёл из раскладки");
  setFocus(popup, false);
  assert.equal(dimStatus(popup).veil, true);
  assert.equal(node.style.getPropertyValue("display"), "block");
  dim(popup, { on: false });
  assert.deepEqual(dimStatus(popup), { on: false, level: 0.7, veil: false }, "недостающее поле — прежнее");
  assert.equal(node.style.getPropertyValue("display"), "none");
});

test("негодное — умолчание: level вне 0,2…0,8, on не булево, мусор в хранилище", () => {
  const { popup } = stand({ local: { [KEY]: "{не json" } });
  assert.deepEqual(dimStatus(popup), { on: false, level: 0.5, veil: false });
  dim(popup, { on: true, level: 0.9 });
  assert.deepEqual(dimStatus(popup), { on: true, level: 0.5, veil: true });
  dim(popup, { level: 0.2 });
  assert.deepEqual(dimStatus(popup), { on: true, level: 0.2, veil: true });
  dim(popup, { on: "true" });
  assert.deepEqual(dimStatus(popup), { on: false, level: 0.2, veil: false });
  dim(popup, { level: "0.4" });
  assert.equal(dimStatus(popup).level, 0.5);
  const stored = stand({ local: { [KEY]: JSON.stringify({ on: true, level: 0.3 }) } }).popup;
  assert.deepEqual(dimStatus(stored), { on: false, level: 0.3, veil: false }, "перезагрузка снимает вуаль, сила прежняя");
});

test("выбор из другого окна — storage-событием; чужой ключ не трогает", () => {
  const { popup } = stand();
  popup.win.localStorage.setItem(KEY, JSON.stringify({ on: true, level: 0.4 }));
  popup.win.dispatchEvent({ type: "storage", key: "чужой-ключ" });
  assert.equal(dimStatus(popup).on, false);
  popup.win.dispatchEvent({ type: "storage", key: KEY });
  assert.deepEqual(dimStatus(popup), { on: true, level: 0.4, veil: true });
  popup.win.localStorage.removeItem(KEY);
  popup.win.dispatchEvent({ type: "storage", key: null });
  assert.deepEqual(dimStatus(popup), { on: false, level: 0.4, veil: false }, "хранилище очищено — выкл, сила прежняя");
});

test("чат попапа ждёт слова — янтарная рамка пульсирует 1,2 с, вуали нет; Авто-Allow за секунду не мигает", () => {
  const { popup, b } = stand();
  dim(popup, { on: true, level: 0.5 });
  let t = Date.now();
  step(popup, t);
  b.liveStatus = "awaiting";
  step(popup, t += 1000);
  run(b);
  t = steps(popup, t, 3);
  assert.equal(attn(popup).on, false, "метка прожила секунду — не мигаем");
  b.liveStatus = "awaiting";
  t = steps(popup, t, 4);
  const state = attn(popup);
  assert.equal(state.on, true);
  assert.equal(typeof state.since, "number");
  const node = frame(popup);
  assert.equal(node.style.getPropertyValue("display"), "block");
  assert.match(node.style.getPropertyValue("box-shadow"), /#f59e0b/);
  assert.equal(node.style.getPropertyValue("pointer-events"), "none");
  assert.ok(Number(node.style.getPropertyValue("z-index")) > Number(veil(popup).style.getPropertyValue("z-index")), "поверх вуали");
  const [pulse] = pulses(popup);
  assert.equal(pulse.options.duration * 2, 1200);
  assert.equal(pulse.options.iterations, Infinity);
  assert.equal(dimStatus(popup).veil, false, "окно, где ждут Элвиса, не темнеет");
  assert.equal(veil(popup).style.getPropertyValue("opacity"), "0");
});

test("ввод в поле гасит рамку; не возвращается, пока чат не поработает снова", () => {
  const { popup, b } = stand();
  let t = Date.now();
  step(popup, t); idle(b); says(popup, "wait");
  t = steps(popup, t, 4);
  assert.equal(attn(popup).on, true, "ход кончен на глазах — ждёт слова");
  popup.win.dispatchEvent({ type: "keydown", key: "x", target: popup.parts.editor });
  assert.deepEqual(attn(popup), { on: false, since: null });
  assert.equal(frame(popup).style.getPropertyValue("display"), "none");
  assert.equal(pulses(popup).length, 0, "пульс снят");
  t = steps(popup, t, 5);
  assert.equal(attn(popup).on, false, "то же ожидание второй раз не мигает");
  run(b); step(popup, t += 1000);
  idle(b);
  t = steps(popup, t, 4);
  assert.equal(attn(popup).on, true, "новое ожидание — новая рамка");
});

test("касание мимо поля рамку не гасит (свечение 12и гаснет, рамка — нет)", () => {
  const { popup, b } = stand();
  let t = Date.now();
  step(popup, t); idle(b); says(popup, "wait");
  t = steps(popup, t, 4);
  assert.equal(attn(popup).on, true);
  popup.win.dispatchEvent({ type: "pointerdown" });
  popup.win.dispatchEvent({ type: "keydown", key: "Escape" });
  t = steps(popup, t, 3);
  assert.equal(attn(popup).on, true, "ответа Элвиса ещё нет");
});

test("фокус окна гасит рамку через 3 с, миг фокуса — нет; уход из фокуса — вуаль снова", () => {
  const { popup, b } = stand();
  dim(popup, { on: true, level: 0.5 });
  let t = Date.now();
  step(popup, t); idle(b); says(popup, "wait");
  t = steps(popup, t, 4);
  assert.equal(attn(popup).on, true);
  setFocus(popup, true);
  step(popup, t += 1000);
  setFocus(popup, false);
  t = steps(popup, t, 3);
  assert.equal(attn(popup).on, true, "приложение подняло окно на миг — не в счёт");
  setFocus(popup, true);
  step(popup, t += 1000);
  step(popup, t += 1000);
  assert.equal(attn(popup).on, true, "2 с фокуса — ещё горит");
  t = steps(popup, t, 2);
  assert.equal(attn(popup).on, false, "3 с фокуса — увидел");
  assert.equal(dimStatus(popup).veil, false, "в фокусе вуали нет");
  setFocus(popup, false);
  t = steps(popup, t, 2);
  assert.equal(attn(popup).on, false, "не возвращается");
  assert.equal(dimStatus(popup).veil, true, "ушёл из фокуса — снова темно");
});

test("reduced-motion — рамка ровная, без пульса", () => {
  const { popup, b } = stand();
  popup.win.__reducedMotion = true;
  let t = Date.now();
  step(popup, t); idle(b); says(popup, "wait");
  t = steps(popup, t, 4);
  assert.equal(attn(popup).on, true);
  assert.equal(frame(popup).style.getPropertyValue("display"), "block");
  assert.equal(frame(popup).style.getPropertyValue("opacity"), "1");
  assert.equal(pulses(popup).length, 0);
});

test("чужой чат в списке ждёт — рамка у его окна, не у главного", () => {
  const { main, popup, b } = stand();
  let t = Date.now();
  step(main, t); step(popup, t);
  idle(b); says(popup, "wait"); says(main, "wait");
  for (let i = 0; i < 5; i += 1) { t += 1000; step(main, t); step(popup, t); }
  assert.equal(attn(popup).on, true);
  assert.equal(attn(main).on, false);
});

test("dispose уносит вуаль, рамку и пульс", () => {
  const { popup, b } = stand();
  dim(popup, { on: true, level: 0.5 });
  let t = Date.now();
  step(popup, t); idle(b); says(popup, "wait");
  t = steps(popup, t, 4);
  assert.equal(pulses(popup).length, 1);
  popup.api.dispose();
  assert.equal(veil(popup), null);
  assert.equal(frame(popup), null);
  assert.equal(popup.dom.running().length, 0);
});

test("#8112: ход кончен без «жду» — рамки нет; «жду» или «упал» в строке — есть; Allow — всегда", () => {
  const { popup, b } = stand();
  let t = Date.now();
  step(popup, t); idle(b);
  t = steps(popup, t, 4);
  assert.equal(attn(popup).on, false, "просто законченный ход не мигает");
  assert.equal(want(popup), false);
  says(popup, "done");
  t = steps(popup, t, 4);
  assert.equal(attn(popup).on, false, "«готово ✅» — не ждут");
  says(popup, "fail");
  step(popup, t += 1000);
  assert.equal(attn(popup).on, false, "выдержка 2 с — с нуля");
  assert.equal(want(popup), false);
  t = steps(popup, t, 2);
  assert.equal(attn(popup).on, true, "«упал 🛑» — ждут слова");
  assert.equal(want(popup), true);
  says(popup, "run");
  step(popup, t += 1000);
  assert.equal(attn(popup).on, false, "строка сменилась — рамка ушла");
  assert.equal(want(popup), false);
  says(popup, null);
  b.liveStatus = "awaiting";
  t = steps(popup, t, 3);
  assert.equal(attn(popup).on, true, "Allow или вопрос — без строки состояния");
  assert.equal(want(popup), true);
  popup.win.dispatchEvent({ type: "keydown", key: "x", target: popup.parts.editor });
  assert.equal(attn(popup).on, false);
  assert.equal(want(popup), true, "want — признак для приложения, ввод его не гасит");
});

test("keep: окна главного проекта светлые и без рамки, темнеют все прочие — и главное окно", () => {
  const { main, popup, b } = stand();
  // У стенда хранилище своё у каждой страницы — команда уходит обеим, как у приложения.
  for (const page of [main, popup]) dim(page, { on: true, level: 0.5, keep: [B] });
  assert.deepEqual(JSON.parse(main.win.localStorage.getItem(KEY)), { on: true, level: 0.5, keep: [B] });
  assert.deepEqual(keepOf(popup), [B]);
  assert.equal(plain(main.api.status().dim).veil, true, "главное окно в углу — темнеет");
  assert.equal(veil(main).style.getPropertyValue("display"), "block");
  assert.equal(plain(popup.api.status().dim).veil, false, "попап Рика — никогда");
  let t = Date.now();
  step(popup, t);
  b.liveStatus = "awaiting";
  t = steps(popup, t, 4);
  assert.equal(attn(popup).on, false, "Рик и так перед глазами — рамки нет");
  assert.equal(want(popup), true);
  dim(main, { keep: [] });
  assert.equal(plain(main.api.status().dim).veil, false, "keep пуст — как было: главное не темнеет");
  dim(popup, { keep: [] });
  step(popup, t += 1000);
  assert.equal(attn(popup).on, true, "keep снят — рамка вернулась");
});

test("keep проверяется: не массив, не local_…, длиннее 32 — пусто; недостающее поле — прежнее", () => {
  const { popup } = stand();
  dim(popup, { on: true, keep: [B] });
  assert.deepEqual(keepOf(popup), [B]);
  dim(popup, { level: 0.4 });
  assert.deepEqual(keepOf(popup), [B], "поле не пришло — прежнее");
  dim(popup, { keep: "local_x" });
  assert.deepEqual(keepOf(popup), []);
  dim(popup, { keep: [B, "Диктатор"] });
  assert.deepEqual(keepOf(popup), []);
  dim(popup, { keep: Array.from({ length: 33 }, (_, i) => `local_${i}`) });
  assert.deepEqual(keepOf(popup), []);
  dim(popup, { keep: Array.from({ length: 32 }, (_, i) => `local_${i}`) });
  assert.equal(keepOf(popup).length, 32);
  const stored = stand({ local: { [KEY]: JSON.stringify({ on: true, level: 0.3, keep: [7] }) } }).popup;
  assert.deepEqual(keepOf(stored), [], "мусор в хранилище — пусто");
});

for (const fallback of [false, true]) {
  test(`attention: настоящая строка без WF через ${fallback ? "панель" : "ответ"} даёт want и снимается новой строкой`, () => {
    const { popup, b } = stand();
    const node = popup.document.body.add("div", { attrs: fallback
      ? { class: "epitaxy-chat-panel-body" }
      : { "data-testid": "transcript-row" } });
    let t = Date.now();
    step(popup, t); idle(b);
    for (const [word, expected] of [["жду ❓", true], ["готово ✅", false], ["упал 🛑", true]]) {
      node.textContent = `Ответ\n⚪ Пимп · ${word}`;
      popup.inner.progressRefresh();
      assert.equal(popup.inner.progressState.info, null, "полоске нужен WF, рамке — слово");
      t = steps(popup, t, 4);
      assert.equal(want(popup), expected);
      assert.equal(attn(popup).on, expected);
    }
  });
}

test("WF119: загрузка сбрасывает старый on и ключ, сохраняя level/keep для внимания", () => {
  const { popup, b } = stand({ local: { [KEY]: JSON.stringify({ on: true, level: 0.7, keep: [B] }) } });
  assert.deepEqual(plain(popup.api.status().dim), { on: false, level: 0.7, keep: [B], veil: false });
  assert.equal(popup.win.localStorage.getItem(KEY), null);
  b.liveStatus = "awaiting";
  steps(popup, Date.now(), 5);
  assert.equal(attn(popup).on, false, "keep защищает от внимания после сброса");
  popup.api.dispose();
});

test("WF119: удаление общего ключа и два reinject сохраняют известные level/keep", () => {
  const { popup, b } = stand();
  dim(popup, { on: true, level: 0.7, keep: [B] });
  popup.win.localStorage.removeItem(KEY);
  popup.win.dispatchEvent({ type: "storage", key: KEY });
  const expected = { on: false, level: 0.7, keep: [B], veil: false };
  assert.deepEqual(plain(popup.api.status().dim), expected);
  for (let i = 0; i < 2; i++) {
    assert.equal(popup.reload().error, null);
    assert.deepEqual(plain(popup.api.status().dim), expected);
    b.liveStatus = "awaiting";
    steps(popup, Date.now(), 5);
    assert.equal(attn(popup).on, false);
  }
  dim(popup, { on: false, level: 0.7, keep: [] });
  assert.deepEqual(keepOf(popup), [], "явная команда снимает исключения");
  steps(popup, Date.now(), 5);
  assert.equal(attn(popup).on, true, "явное снятие keep возвращает внимание");
  popup.api.dispose();
});

test("WF119: свежая валидная LS-запись сильнее прошлого экземпляра, пустой keep явный", () => {
  const { popup } = stand();
  dim(popup, { on: false, level: 0.7, keep: [B] });
  popup.win.localStorage.setItem(KEY, JSON.stringify({ on: true, level: 0.2, keep: [] }));
  assert.equal(popup.reload().error, null);
  assert.deepEqual(plain(popup.api.status().dim), { on: false, level: 0.2, keep: [], veil: false });
  assert.equal(popup.win.localStorage.getItem(KEY), null);
  dim(popup, { on: false, level: 0.7, keep: [B] });
  popup.win.localStorage.setItem(KEY, JSON.stringify({ on: false, level: 0.5, keep: [] }));
  popup.win.dispatchEvent({ type: "storage", key: KEY });
  assert.deepEqual(keepOf(popup), []);
  popup.api.dispose();
});

test("WF119: reinject с недоступным LS снимает вуаль и сохраняет известные исключения", () => {
  const { popup } = stand();
  dim(popup, { on: true, level: 0.6, keep: [A] });
  assert.equal(popup.api.status().dim.veil, true);
  for (const key of ["getItem", "removeItem", "setItem"]) popup.win.localStorage[key] = () => { throw new Error("blocked"); };
  assert.equal(popup.reload().error, null);
  assert.deepEqual(plain(popup.api.status().dim), { on: false, level: 0.6, keep: [A], veil: false });
  popup.api.dispose();
});
