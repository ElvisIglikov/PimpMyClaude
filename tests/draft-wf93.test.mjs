// WF93 (N1), страница: ссылка «ОТКРОЙ НОВЫЙ ЧАТ» не открывает второй чат во время
// «⏳»/«✓» и на двойном клике, свежий попап не называет себя прошлым чатом (#7378).
// Черновик «Code» (draft-setup, WF88 К18, WF93, WF126) снят в WF248 вместе с движком пустого окна.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { loadInject } from "./load.mjs";

// ---- #7378: свежий попап не называет себя прошлым чатом ---------------------

const OLD = "local_dc5ef534";
const NEW = "local_6f1bd03f";
const popup = ({ title = "Loading", session = null } = {}) => loadInject({
  href: "about:blank", title,
  storage: session ? { session } : undefined,
  html: dom => ({ body: dom.document.body }),
});
const panelWith = (loaded, id) => {
  const panel = loaded.document.body.add("div", { class: "epitaxy-chat-panel" });
  panel.__reactFiber$test = { memoizedProps: {}, return: { memoizedProps: { sessionId: id }, return: null } };
  return panel;
};

test("#7378: запись прошлого чата с заглушкой «Loading» не называет новое окно", () => {
  const record = JSON.stringify({ id: OLD, title: "Loading" });
  const fresh = popup({ session: { "myclaude-chat-v1": record } });
  assert.equal(fresh.inner.readChatId(), null, "заглушка чата не называет");
  assert.equal(fresh.inner.myChatId(), null);
  assert.equal(fresh.inner.chatTitleKey(), null, "у «Loading» ключа темы по заголовку нет");
  panelWith(fresh, NEW);
  assert.equal(fresh.inner.myChatId(), NEW, "волокно называет свой чат");
  assert.equal(fresh.win.sessionStorage.getItem("myclaude-chat-v1"), record, "под заглушкой кэш не пишем");
});

test("#7378: окно из запаса Claude — новый чат с тем же заголовком называет себя новым", () => {
  const loaded = popup({ title: "Ожидание задачи" });
  const old = panelWith(loaded, OLD);
  assert.equal(loaded.inner.myChatId(), OLD);
  old.remove();
  panelWith(loaded, NEW);
  assert.equal(loaded.inner.myChatId(), NEW, "кэш волокна держится за живой узел");
  assert.equal(JSON.parse(loaded.win.sessionStorage.getItem("myclaude-chat-v1")).id, NEW);
});

// ---- К15: ссылка и кнопка не открывают второй чат ---------------------------

const HANDOFF = JSON.parse(readFileSync(new URL("./fixtures/cashout/record-handoff.json", import.meta.url), "utf8")).text;
const LINK = "[data-myclaude-continue-link]";
const PREFIX = "PMP: продолжить в новом чате · ";
const chatPage = () => {
  const heads = [];
  const loaded = loadInject({
    href: "about:blank", title: "VkusnoffKz 2", hasFocus: false,
    html: dom => {
      const parts = dom.composer();
      const answer = dom.document.body.add("div", { attrs: { "data-testid": "assistant-message" }, rect: { left: 0, top: 100, width: 800, height: 100 } });
      heads.push(answer.add("h2", { text: "🆕 ОТКРОЙ НОВЫЙ ЧАТ" }));
      const block = answer.add("div", { class: "epitaxy-codeblock relative" });
      block.add("div", { class: "relative" }).add("div", { attrs: { "data-code-text": HANDOFF }, text: HANDOFF });
      heads.push(answer.add("h2", { text: "🆕 ОТКРОЙ НОВЫЙ ЧАТ" }));
      return parts;
    },
  });
  assert.equal(loaded.error, null);
  // База заморожена (z8-r01): часы страницы двигает только тест, иначе
  // настоящее время под нагрузкой утекало бы в отсчёт.
  const base = loaded.win.performance.now();
  let shift = 500;
  loaded.win.performance.now = () => base + shift;
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
  assert.equal(loaded.dom.queryAll(LINK).length, 2);
  return { loaded, heads };
};
const click = (loaded, target, extra = {}) =>
  loaded.document.dispatchEvent({ type: "click", target, bubbles: true, button: 0, detail: 1, ...extra });
const lastTimer = loaded => { const ids = loaded.dom.ids("timeout"); loaded.dom.fire(ids[ids.length - 1]); };
const ack = loaded => loaded.dom.command({ id: "c1", action: "cashout", at: "now", scope: "window", title: "VkusnoffKz 2", handoff: true });

test("К15: двойной и тройной клик по ссылке — выделение, чат не открывается", () => {
  const { loaded, heads } = chatPage();
  click(loaded, heads[0]);
  click(loaded, heads[0], { detail: 2 });
  loaded.dom.fireKind("timeout");
  click(loaded, heads[1]);
  click(loaded, heads[1], { detail: 2 });
  click(loaded, heads[1], { detail: 3 });
  loaded.dom.fireKind("timeout");
  assert.equal(loaded.api.status().continue.clicks, 0);
  assert.equal(String(loaded.document.title), "VkusnoffKz 2");
});

test("К15: во время «⏳» и «✓» ни ссылка, ни кнопка второй раз не открывают", () => {
  const { loaded, heads } = chatPage();
  click(loaded, heads[0]);
  lastTimer(loaded);
  assert.ok(String(loaded.document.title).startsWith(PREFIX));
  assert.equal(loaded.api.status().continue.clicks, 1);
  const button = loaded.dom.query("[data-myclaude-continue] button");
  assert.ok(button, "кнопка «💬 Новый чат» стоит");
  click(loaded, button);
  assert.equal(loaded.api.status().continue.clicks, 1, "⏳: кнопка не жмётся");
  ack(loaded);
  assert.equal(heads[0].getAttribute("data-myclaude-continue-state"), "ack");
  assert.equal(click(loaded, heads[0]), false, "клик по ссылке во время «✓» погашен");
  assert.equal(loaded.dom.ids("timeout").length > 0, true);
  // Отложенный клик ссылки во время «✓» не заводится вовсе.
  assert.equal(click(loaded, button), false);
  assert.equal(loaded.api.status().continue.clicks, 1, "✓: второго чата нет");
  assert.equal(String(loaded.document.title), "VkusnoffKz 2", "метки заголовка нет");
});
