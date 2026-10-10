// #9060 (WF154, раздел 12с¹): «Bypass permissions во всех чатах». Команда `bypass-chats`
// (`on:"true"|"false"`, как hide-tools) включает настройку страницы; включена — в каждом
// открытом чате один раз за открытие страница ставит режим Bypass permissions, если он есть
// в меню режимов и ещё не стоит; меню при этом невидимо; чат, где человек сам выбрал режим,
// не трогаем.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_aaaa-1111";
const KEY = "myclaude.bypassChats";
const QUIET = "data-myclaude-bypass-quiet";
const MENU = ["Ask permissions", "Accept edits", "Plan mode", "Bypass permissions", "Auto mode"];
const settle = async (times = 6) => { for (let i = 0; i < times; i += 1) await new Promise(r => setImmediate(r)); };

const page = ({ mode = "Auto mode", menu = MENU, on = false, confirm = false, title = "Trelvis" } = {}) => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title,
    storage: { local: { "myclaude-auto-allow-roam": "off", ...(on ? { [KEY]: "1" } : {}) } },
    html: dom => {
      const parts = dom.composer({});
      const chin = parts.modelRow.add("div", { attrs: { "data-cds": "ChatComposerChin" } });
      chin.add("button", { text: "Opus 5.5", attrs: { "data-testid": "epitaxy-cds-model-selector" } });
      parts.mode = chin.add("button", { text: mode, attrs: { "aria-haspopup": "menu" } });
      parts.opens = 0;
      parts.pressed = [];
      parts.mode.addEventListener("pointerdown", () => {
        parts.opens += 1;
        parts.quietAtOpen = dom.document.documentElement.hasAttribute(QUIET);
        const list = dom.document.body.add("div", { attrs: { role: "menu" } });
        parts.menu = list;
        for (const label of menu) {
          const item = list.add("div", { attrs: { role: "menuitemradio" }, text: label });
          item.addEventListener("pointerdown", () => {
            parts.pressed.push(label);
            list.remove();
            if (confirm && /^Bypass/.test(label)) dom.document.body.add("div", { attrs: { role: "alertdialog" }, text: "Enable bypass?" });
            else parts.mode.textContent = label;
          });
        }
      });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  let t = 100000;
  const tick = (step = 500) => { t += step; loaded.inner.bypassTick(t); };
  // Escape нашего меню: стаб событий не всплывает — закрываем на документе и окне.
  loaded.parts.escapes = 0;
  const esc = event => {
    if (event.key !== "Escape") return;
    loaded.parts.escapes += 1;
    for (const node of loaded.document.querySelectorAll('[role="menu"]')) node.remove();
  };
  loaded.parts.mode.addEventListener("pointerdown", () => loaded.parts.menu.addEventListener("keydown", esc));
  loaded.parts.editor.addEventListener("keydown", event => { if (event.key === "Escape") loaded.parts.editorEscapes = (loaded.parts.editorEscapes ?? 0) + 1; });
  return { loaded, parts: loaded.parts, tick };
};
const view = loaded => plain(loaded.api.status().bypassChats);
const run = async (tick, beats = 4) => { for (let i = 0; i < beats; i += 1) { tick(); await settle(); } };

test("#9060: выключено — режим не трогаем; команда bypass-chats включает и ставит Bypass", async () => {
  const { loaded, parts, tick } = page();
  await run(tick);
  assert.equal(parts.opens, 0);
  assert.equal(view(loaded).on, false);
  loaded.dom.command({ id: "b1", action: "bypass-chats", at: new Date().toISOString(), on: "true" });
  assert.equal(loaded.win.localStorage.getItem(KEY), "1");
  await run(tick, 6);
  assert.deepEqual(parts.pressed, ["Bypass permissions"]);
  assert.equal(parts.mode.textContent, "Bypass permissions");
  assert.equal(parts.quietAtOpen, true, "меню открылось невидимым");
  assert.equal(view(loaded).result, "ok");
  assert.equal(view(loaded).chat, CHAT);
});

test("#9060: один раз за открытие; человек вернул Auto — не спорим; новое открытие чата — снова", async () => {
  const { loaded, parts, tick } = page({ on: true });
  await run(tick, 6);
  assert.equal(parts.opens, 1);
  parts.mode.textContent = "Auto mode";
  await run(tick, 6);
  assert.equal(parts.opens, 1, "в том же открытии второй попытки нет");
  // Ушли в другой чат и вернулись — это новое открытие.
  loaded.win.location.pathname = "/epitaxy/local_bbbb-2222";
  await run(tick, 6);
  assert.equal(parts.opens, 2, "другой чат — своя попытка");
  parts.mode.textContent = "Auto mode";
  loaded.win.location.pathname = `/epitaxy/${CHAT}`;
  await run(tick, 6);
  assert.equal(parts.opens, 3);
  assert.equal(parts.mode.textContent, "Bypass permissions");
});

test("#9060: уже Bypass — меню не открываем; пункта нет — Escape своему меню, no-item", async () => {
  const already = page({ on: true, mode: "Bypass permissions" });
  await run(already.tick, 6);
  assert.equal(already.parts.opens, 0);
  assert.equal(view(already.loaded).result, "already");
  const none = page({ on: true, menu: ["Ask permissions", "Accept edits", "Auto mode"] });
  await run(none.tick, 5);
  // Ждём пункт NAZH_MENU_MS: часы вперёд, таймеры опроса — руками.
  let clock = none.loaded.win.performance.now();
  none.loaded.win.performance.now = () => clock;
  for (let i = 0; i < 40; i += 1) { clock += 100; none.loaded.dom.fireKind("timeout"); await settle(2); }
  assert.equal(none.parts.opens, 1);
  assert.deepEqual(none.parts.pressed, []);
  assert.equal(none.parts.escapes, 1, "закрыли своё невидимое меню");
  assert.equal(none.parts.editorEscapes, undefined, "Escape — меню, не полю ввода (агент не останавливается)");
  assert.equal(none.loaded.document.querySelector('[role="menu"]'), null);
  assert.equal(view(none.loaded).result, "no-item");
  assert.equal(none.parts.mode.textContent, "Auto mode");
});

test("#9060: человек сам выбирал режим в этом чате — его чат не трогаем", async () => {
  const { loaded, parts, tick } = page({ on: true });
  loaded.win.dispatchEvent({ type: "pointerdown", target: parts.mode, isTrusted: true });
  await run(tick, 6);
  assert.equal(parts.opens, 0);
  assert.equal(view(loaded).user, 1);
  // ⇧Tab (смена режима клавишей) — тоже выбор человека.
  const other = page({ on: true });
  other.loaded.win.dispatchEvent({ type: "keydown", key: "Tab", shiftKey: true, target: other.parts.editor, isTrusted: true });
  await run(other.tick, 6);
  assert.equal(other.parts.opens, 0);
});

test("#9060: подтверждение Claude не жмём и не закрываем, меню снова видимо", async () => {
  const { loaded, parts, tick } = page({ on: true, confirm: true });
  await run(tick, 6);
  assert.deepEqual(parts.pressed, ["Bypass permissions"]);
  assert.equal(view(loaded).result, "confirm");
  assert.ok(loaded.document.querySelector('[role="alertdialog"]'), "диалог остался человеку");
  assert.equal(parts.escapes, 0);
  assert.equal(loaded.document.documentElement.hasAttribute(QUIET), false);
});

test("#9060: открыто чужое меню — ждём; выключение гасит", async () => {
  const { loaded, parts, tick } = page({ on: true });
  const foreign = loaded.document.body.add("div", { attrs: { role: "menu" } });
  await run(tick, 6);
  assert.equal(parts.opens, 0, "чужое меню открыто — не лезем");
  foreign.remove();
  loaded.dom.command({ id: "b2", action: "bypass-chats", at: new Date().toISOString(), on: "false" });
  await run(tick, 6);
  assert.equal(parts.opens, 0);
  assert.equal(loaded.win.localStorage.getItem(KEY), null);
  assert.equal(view(loaded).on, false);
  loaded.api.dispose();
  assert.equal(loaded.document.documentElement.hasAttribute(QUIET), false);
});

test("#9060: касание человека посреди выбора — выбор брошен, своё меню закрыто, видимость вернулась", async () => {
  // Пункта нет — страница ждёт его NAZH_MENU_MS: окно для касания.
  const { loaded, parts, tick } = page({ on: true, menu: ["Ask permissions", "Auto mode"] });
  await run(tick, 5);
  assert.equal(parts.opens, 1);
  assert.equal(view(loaded).busy, true);
  assert.equal(loaded.document.documentElement.hasAttribute(QUIET), true);
  loaded.win.dispatchEvent({ type: "keydown", key: "a", target: parts.editor, isTrusted: true });
  assert.equal(view(loaded).busy, false);
  assert.equal(parts.escapes, 1);
  assert.equal(loaded.document.querySelector('[role="menu"]'), null);
  assert.equal(loaded.document.documentElement.hasAttribute(QUIET), false);
  await run(tick, 6);
  assert.equal(parts.opens, 1, "в этом открытии больше не пробуем");
});
