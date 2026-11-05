// Копия первого сообщения в поле нового чата (renew окна Рика 31.10 07:29, раздел 12к): сообщение ушло и
// стоит в ленте, а поле так и держит тот же текст — следующий renew увёз бы его переносом черновика (12ч).
// Цепочка stay стирает РОВНО свой текст, когда он уже в ленте; чужое и неотправленное не трогает.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const drain = () => new Promise(resolve => setImmediate(resolve));
const settle = async (times = 6) => { for (let index = 0; index < times; index += 1) await drain(); };
const RENEW = "Последний ответ Рика тебе (из прежнего чата, 04:55):\n\nЯ новый Рик, нить держу.\n\n———\nТы — Рик. Продолжай.";

// Главное окно Рика: ⌘N (его жмёт Swift) — `newChatKey()`. Отправка — адрес нового чата и сообщение
// в ленте; `ghost` — Claude оставил отправленный текст в поле, `feed: false` — в ленте его нет.
const rick = ({ ghost = true, feed = true } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_old", title: "Claude",
    html: dom => {
      const parts = dom.composer({ text: "" });
      parts.editor.setAttribute("data-testid", "code-prompt-input");
      parts.send = dom.document.body.add("button", { attrs: { "data-testid": "code-prompt-send" } });
      parts.recents = dom.document.body.add("div", { attrs: { "data-testid": "sidebar-recents" } });
      parts.recents.add("div", { attrs: { "data-row-key": "code:local_old" }, text: "Рик" });
      return parts;
    },
  });
  const { parts } = loaded;
  const box = { sent: [] };
  parts.send.addEventListener("click", () => {
    const text = parts.editor.textContent;
    box.sent.push(text);
    if (!ghost) parts.editor.textContent = "";
    loaded.win.location.pathname = "/epitaxy/local_new";
    if (feed) loaded.dom.document.body.add("div", { attrs: { "data-testid": "user-message" }, text });
    parts.recents.add("div", { attrs: { "data-row-key": "code:local_new" }, text: "Рик 2" });
  });
  const value = { popoutWindows: loaded.run("new Map()"), openPopout: () => {} };
  const hook = () => {};
  hook.getState = () => value;
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  loaded.inner.setModuleImporter(() => Promise.resolve({ Store: hook }));
  box.newChatKey = () => {
    loaded.win.location.pathname = "/epitaxy";
    parts.editor.textContent = "";
  };
  return { loaded, parts, box };
};
const renew = () => ({
  id: "r1", action: "new-window", at: "now", scope: "window", title: "Claude",
  x: 100, y: 200, text: RENEW, folder: "", name: "", stay: true,
});
// Прогон цепочки: микрозадачи и самый свежий таймер, часы — по 100 мс на круг.
const run = async (loaded, onRound = () => {}, rounds = 220) => {
  let clock = loaded.win.performance.now();
  loaded.win.performance.now = () => clock;
  for (let index = 0; index < rounds; index += 1) {
    onRound(index);
    clock += 100;
    await settle(4);
    const ids = loaded.dom.ids("timeout");
    if (ids.length) loaded.dom.fire(ids[ids.length - 1]);
  }
  await settle();
};

test("отправленный текст остался в поле, а сообщение в ленте — копию стираем, отправка одна", async () => {
  const { loaded, parts, box } = rick();
  loaded.dom.command(renew());
  await run(loaded, index => { if (index === 3) box.newChatKey(); });
  const mark = plain(loaded.api.status().newWindow);
  assert.deepEqual(box.sent, [RENEW]);
  assert.equal(mark.state, "ok");
  assert.equal(mark.ghost, "cleared");
  assert.equal(parts.editor.textContent, "", "поле нового чата пустое");
});

test("Claude опустошил поле сам — ничего не трогаем, поля ghost нет", async () => {
  const { loaded, parts, box } = rick({ ghost: false });
  loaded.dom.command(renew());
  await run(loaded, index => { if (index === 3) box.newChatKey(); });
  const mark = plain(loaded.api.status().newWindow);
  assert.equal(mark.state, "ok");
  assert.equal(mark.ghost, null);
  assert.equal(parts.editor.textContent, "");
});

test("в поле дописано своё — не трогаем ни копию, ни дописанное", async () => {
  const { loaded, parts, box } = rick();
  loaded.dom.command(renew());
  let added = false;
  await run(loaded, index => {
    if (index === 3) box.newChatKey();
    if (!added && box.sent.length) { parts.editor.textContent = `${RENEW} и ещё кусок`; added = true; }
  });
  assert.equal(plain(loaded.api.status().newWindow).ghost, null);
  assert.equal(parts.editor.textContent, `${RENEW} и ещё кусок`);
});

test("в ленте сообщения нет — текст в поле не стираем, исход left", async () => {
  const { loaded, parts, box } = rick({ feed: false });
  loaded.dom.command(renew());
  await run(loaded, index => { if (index === 3) box.newChatKey(); });
  assert.equal(plain(loaded.api.status().newWindow).ghost, "left");
  assert.equal(parts.editor.textContent, RENEW);
});
