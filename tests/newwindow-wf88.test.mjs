// WF88 (V-N), страница: правый клик по кнопке боковой панели (К19), ссылка на
// заголовках «ОТКРОЙ НОВЫЙ ЧАТ» (К15) и заглушка «Code» (К19).
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { loadInject, plain } from "./load.mjs";

const fixture = name => JSON.parse(readFileSync(new URL(`./fixtures/cashout/${name}.json`, import.meta.url), "utf8"));
const HANDOFF = fixture("record-handoff").text;
const LINK = "[data-myclaude-continue-link]";
const PREFIX = "Пимп: продолжить в новом чате · ";

// Ответ по правилу ELVIS.md: заголовок, блок передачи, хвостовой повтор заголовка.
const answerWith = (dom, top, { head = "🆕 ОТКРОЙ НОВЫЙ ЧАТ", tail = true, code = HANDOFF } = {}) => {
  const answer = dom.document.body.add("div", {
    attrs: { "data-testid": "assistant-message" }, rect: { left: 0, top, width: 800, height: 100 },
  });
  answer.add("p", { text: "Сделал." });
  const heads = [];
  if (head) heads.push(answer.add("h2", { text: head }));
  const block = answer.add("div", { class: "epitaxy-codeblock relative" });
  if (code) block.add("div", { class: "relative" }).add("div", { attrs: { "data-code-text": code }, text: code });
  if (head && tail) heads.push(answer.add("h2", { text: head }));
  return { answer, heads };
};
const page = ({ answers = [{}], title = "VkusnoffKz 2", html = null } = {}) => {
  const got = [];
  const loaded = loadInject({
    href: "about:blank", title, hasFocus: false,
    html: dom => {
      const parts = dom.composer();
      if (html) html(dom);
      answers.forEach((spec, index) => got.push(answerWith(dom, 100 + index * 120, spec)));
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  // База заморожена (z8-r01): часы страницы двигает только тест, иначе
  // настоящее время под нагрузкой утекало бы в отсчёт.
  const base = loaded.win.performance.now();
  let shift = 0;
  loaded.win.performance.now = () => base + shift;
  const pass = () => {
    shift += 500;
    loaded.win.dispatchEvent({ type: "resize" });
    loaded.dom.fireKind("timeout");
    loaded.dom.fireKind("raf");
  };
  pass();
  return { loaded, got, pass, tick: ms => { shift += ms; } };
};
const click = (loaded, target, extra = {}) =>
  loaded.document.dispatchEvent({ type: "click", target, bubbles: true, button: 0, ...extra });
const linkStatus = loaded => plain(loaded.api.status().continue.link);

// ---- К19: правый клик по кнопке панели --------------------------------------

test("WF88 К19: contextmenu на кнопке панели (и значке в ней) погашен, на других — нет", () => {
  const nodes = {};
  const { loaded } = page({
    answers: [],
    html: dom => {
      nodes.show = dom.document.body.add("button", { attrs: { "aria-label": "Show sidebar" } });
      nodes.icon = nodes.show.add("svg", {});
      nodes.hide = dom.document.body.add("button", { attrs: { "aria-label": "Hide sidebar" } });
      nodes.other = dom.document.body.add("button", { attrs: { "aria-label": "Search" } });
    },
  });
  const menu = target => loaded.document.dispatchEvent({ type: "contextmenu", target, bubbles: true, cancelable: true });
  assert.equal(menu(nodes.show), false, "Show sidebar — погашено");
  assert.equal(menu(nodes.icon), false, "значок внутри кнопки — погашено");
  assert.equal(menu(nodes.hide), false, "Hide sidebar — погашено");
  assert.equal(menu(nodes.other), true, "другая кнопка — меню Claude как было");
  assert.equal(loaded.api.status().sidebarContext, 3);
});

// ---- К19: заглушка «Code» ----------------------------------------------------

test("WF88 К19: у окна «Code» ключа чата по заголовку нет", () => {
  const { loaded } = page({ answers: [], title: "Code" });
  assert.equal(loaded.inner.chatTitleKey(), null);
  const named = page({ answers: [], title: "Code review" }).loaded;
  assert.notEqual(named.inner.chatTitleKey(), null, "имя, где «Code» только часть, — ключ есть");
});

// ---- К15: ссылка --------------------------------------------------------------

test("WF88 К15: ссылка на обоих заголовках последнего ответа, текст заголовка прежний", () => {
  const { loaded, got } = page({ answers: [{}, {}] });
  const links = loaded.dom.queryAll(LINK);
  assert.equal(links.length, 2, "верхний и хвостовой — у последнего ответа");
  assert.deepEqual(links, got[1].heads);
  for (const head of got[1].heads) {
    assert.equal(head.getAttribute("title"), "Открыть новый чат с этим текстом (Пимп)");
    assert.equal(head.textContent, "🆕 ОТКРОЙ НОВЫЙ ЧАТ");
  }
  for (const head of got[0].heads) assert.equal(head.hasAttribute("data-myclaude-continue-link"), false);
  assert.equal(linkStatus(loaded).shown, 2);
});

test("WF88 К15: блока нет — ссылки нет", () => {
  assert.equal(page({ answers: [{ code: "" }] }).loaded.dom.queryAll(LINK).length, 0);
  assert.equal(page({ answers: [{ head: "Итог" }] }).loaded.dom.queryAll(LINK).length, 0);
});

test("WF88 К15: пришёл новый ответ без блока — старые заголовки ссылку теряют", () => {
  const { loaded, got, pass } = page();
  assert.equal(loaded.dom.queryAll(LINK).length, 2);
  loaded.document.body.add("div", { attrs: { "data-testid": "assistant-message" }, text: "Новый ответ." });
  pass();
  assert.equal(loaded.dom.queryAll(LINK).length, 0);
  for (const head of got[0].heads) {
    assert.equal(head.hasAttribute("title"), false);
    assert.equal(head.hasAttribute("data-myclaude-continue-state"), false);
  }
});

test("WF88 К15: клик по ссылке — метка заголовка окна, ⏳, потом ✓ по команде приложения", () => {
  const { loaded, got } = page();
  const allowed = click(loaded, got[0].heads[1]);
  assert.equal(allowed, false, "клик погашен");
  // Первый клик ждёт, не двойной ли он (WF93), — срок вышел.
  const ids = loaded.dom.ids("timeout");
  loaded.dom.fire(ids[ids.length - 1]);
  assert.ok(String(loaded.document.title).startsWith(PREFIX), "метка заголовка — тот же канал, что у кнопки");
  for (const head of got[0].heads) assert.equal(head.getAttribute("data-myclaude-continue-state"), "wait");
  assert.deepEqual(linkStatus(loaded), { shown: 2, clicks: 1 });
  assert.equal(loaded.api.status().continue.clicks, 1);
  // Занято — второй клик ничего не делает.
  const title = loaded.document.title;
  click(loaded, got[0].heads[0]);
  assert.equal(loaded.document.title, title);
  assert.equal(linkStatus(loaded).clicks, 1);
  loaded.dom.command({ id: "c1", action: "cashout", at: "now", scope: "window", title: "VkusnoffKz 2", handoff: true });
  for (const head of got[0].heads) assert.equal(head.getAttribute("data-myclaude-continue-state"), "ack");
  assert.equal(loaded.document.title, "VkusnoffKz 2");
});

test("WF88 К15: клик с выделением или с модификатором — не открытие чата", () => {
  const { loaded, got } = page();
  const head = got[0].heads[0];
  for (const extra of [{ metaKey: true }, { shiftKey: true }, { altKey: true }, { ctrlKey: true }, { button: 1 }]) {
    assert.equal(click(loaded, head, extra), true, JSON.stringify(extra));
  }
  const selection = { toString: () => "ОТКРОЙ", rangeCount: 1, removeAllRanges() {}, addRange() {}, getRangeAt: () => null };
  loaded.win.getSelection = () => selection;
  loaded.document.getSelection = () => selection;
  assert.equal(click(loaded, head), true, "выделение — клик как был");
  assert.equal(linkStatus(loaded).clicks, 0);
  assert.equal(loaded.api.status().continue.clicks, 0);
  assert.equal(String(loaded.document.title), "VkusnoffKz 2");
});

test("WF88 К15: молчание приложения — плашка без пункта ⌘B, состояние снято", () => {
  const { loaded, got, tick } = page();
  click(loaded, got[0].heads[0]);
  tick(9000);
  for (let index = 0; index < 200 && loaded.dom.ids("timeout").length; index += 1) loaded.dom.fireKind("timeout");
  assert.ok(loaded.document.body.textContent.includes("Пимп пока не взялся — проверь, что он запущен и у него есть доступ, и нажми ещё раз"));
  assert.equal(loaded.document.body.textContent.includes("⌘B"), false);
  for (const head of got[0].heads) assert.equal(head.hasAttribute("data-myclaude-continue-state"), false);
});

test("WF88 К15: dispose снимает ссылку", () => {
  const { loaded } = page();
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(LINK).length, 0);
});
