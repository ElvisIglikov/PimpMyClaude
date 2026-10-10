// #7905 (WF102): «Новое окно» в папке, которой Claude ещё не доверял. Диалог
// «Trust this workspace?» закрывает отправку; до WF102 цепочка жала Enter
// вхолостую и через 15 с отказывала. Теперь авто-Trust жмёт сам, вне Авто-Allow
// (снят в WF119; только папки внутри Projects), а цепочка ждёт ухода диалога
// с плашкой «Нажми Trust workspace» и шлёт заново; status().newWindow.trust —
// "waited" | "timeout" | null.
//
// Стенд: домашний экран (поле ввода + кнопка отправки), стор попапов подставным
// импортёром (приём tests/new-window.test.mjs). Диалог встаёт либо на первом
// клике по отправке (after — так у Claude: «send a message and choose Trust
// workspace when asked»), либо ещё до него, гася кнопку (before).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const INSIDE = "/Users/dev/Projects/PimpTest102";
const drain = () => new Promise(resolve => setImmediate(resolve));
const settle = async (times = 6) => { for (let index = 0; index < times; index += 1) await drain(); };
const rect = { left: 100, top: 300, width: 140, height: 32 };
const command = () => ({ id: "n1", action: "new-window", at: "now", scope: "window", title: "Claude", x: 100, y: 200, text: "Привет" });

const stand = ({ path = INSIDE, when = "after" } = {}) => {
  const box = { sends: 0, trusts: 0, trusted: false, dialog: null };
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy", title: "Claude",
    // Корень автодоверия (WF108) присылает приложение командой trust-root.
    storage: { local: { "myclaude-trust-root-v1": "/Users/dev/Projects/" } },
    html: dom => {
      const input = dom.document.body.add("div", { attrs: { "data-testid": "code-prompt-input", contenteditable: "true" } });
      const send = dom.document.body.add("button", { attrs: { "data-testid": "code-prompt-send" }, rect });
      return { input, send };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const store = () => {};
  const value = { popoutWindows: loaded.run("new Map()"), openPopout: () => {} };
  store.getState = () => value;
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  loaded.inner.setModuleImporter(() => Promise.resolve({ Store: store }));
  const showDialog = () => {
    const dialog = loaded.document.body.add("div", { attrs: { role: "alertdialog" }, rect: { left: 0, top: 0, width: 500, height: 300 } });
    dialog.add("h2", { text: "Trust this workspace?" });
    dialog.add("div", { attrs: { class: "text-code" }, text: path });
    const trust = dialog.add("button", { text: "Trust workspace", rect });
    dialog.add("button", { text: "Cancel", rect });
    trust.addEventListener("click", () => {
      box.trusts += 1;
      box.trusted = true;
      dialog.remove();
      loaded.parts.send.removeAttribute("disabled");
    });
    box.dialog = dialog;
  };
  loaded.parts.send.addEventListener("click", () => {
    box.sends += 1;
    if (!box.trusted) { if (!box.dialog?.isConnected) showDialog(); return; }
    loaded.win.location.pathname = "/epitaxy/local_new";
  });
  if (when === "before") { showDialog(); loaded.parts.send.setAttribute("disabled", ""); }
  // Часы: цепочка меряет сроки performance.now, авто-Trust — своими.
  const clock = { t: 9_000_000 };
  loaded.win.performance.now = () => clock.t;
  loaded.inner.setAutoAllowClock(() => clock.t);
  // Круг ожидания цепочки: самый свежий таймер (сторож всей цепочки старше).
  const poll = async () => {
    const ids = loaded.dom.ids("timeout");
    loaded.dom.fire(ids[ids.length - 1]);
    await settle();
  };
  const tick = () => { clock.t += 1000; loaded.inner.trustCycle(); };
  const note = () => loaded.dom.query("#myclaude-new-window-note");
  return { loaded, box, clock, poll, tick, note };
};

test("#7905: папка проекта — авто-Trust жмёт", () => {
  const { loaded, box, tick } = stand({ when: "before" });
  tick();
  assert.equal(box.trusts, 1, "доверие папке внутри Projects");
  assert.equal(plain(loaded.api.status().trust).last.verdict, "pressed");
});

test("#7905: чужая папка — не жмём", () => {
  const { loaded, box, tick } = stand({ when: "before", path: "/Users/dev/Downloads/x" });
  tick();
  assert.equal(box.trusts, 0);
  assert.equal(plain(loaded.api.status().trust).last.verdict, "outside");
});

test("#7905: диалог встал на отправке — цепочка ждёт его ухода и шлёт ещё раз", async () => {
  const { loaded, box, poll, tick, note } = stand();
  loaded.dom.command(command());
  await settle();
  assert.equal(box.sends, 1, "первый клик ушёл");
  await poll();
  let mark = loaded.api.status().newWindow;
  assert.equal(mark.step, "trust", "цепочка увидела диалог и ждёт");
  assert.equal(mark.trust, "wait");
  assert.equal(note()?.style.getPropertyValue("display"), "block", "плашка видна");
  assert.equal(note()?.textContent, "Нажми Trust workspace");
  tick();
  assert.equal(box.trusts, 1, "авто-Trust нажал");
  await poll();
  await poll();
  mark = loaded.api.status().newWindow;
  assert.equal(box.sends, 2, "после доверия отправку нажали ещё раз");
  assert.equal(mark.trust, "waited");
  assert.equal(mark.id, "local_new", "сессия родилась");
  assert.equal(note()?.style.getPropertyValue("display"), "none", "плашка ушла");
});

test("#7905: диалог стоит до отправки и гасит кнопку — ждём, потом жмём один раз", async () => {
  const { loaded, box, poll, tick } = stand({ when: "before" });
  loaded.dom.command(command());
  await settle();
  assert.equal(box.sends, 0, "по погашенной кнопке не бьём");
  assert.equal(loaded.api.status().newWindow.step, "trust");
  tick();
  await poll();
  await poll();
  const mark = loaded.api.status().newWindow;
  assert.equal(box.sends, 1);
  assert.equal(mark.trust, "waited");
  assert.equal(mark.id, "local_new");
});

test("#7905: чужую папку никто не доверил за 20 с — прежний отказ, trust: timeout", async () => {
  const { loaded, box, clock, poll, tick } = stand({ path: "/tmp/elsewhere" });
  loaded.dom.command(command());
  await settle();
  await poll();
  tick();
  assert.equal(box.trusts, 0, "вне Projects авто-Trust не жмёт");
  clock.t += 21_000;
  await poll();
  await settle();
  const mark = loaded.api.status().newWindow;
  assert.equal(mark.trust, "timeout");
  assert.equal(box.sends, 1, "второго клика нет");
  assert.equal(mark.state, "no-send", "исход прежний — новых state не заводим");
});

test("диалога не было — trust: null, отправка одна", async () => {
  const { loaded, box } = stand();
  box.trusted = true;
  loaded.dom.command(command());
  await settle();
  const mark = loaded.api.status().newWindow;
  assert.equal(box.sends, 1);
  assert.equal(mark.trust, null);
  assert.equal(mark.id, "local_new");
});
