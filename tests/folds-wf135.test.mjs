// WF135 (страница, раздел 12ф inject.js): свёртки <details> (#9065, файл 29,
// вариант 1.1). Desktop печатает теги текстом в отдельных <p> — страница
// ставит перед сырым <p> свой заголовок role=button, сырые <p> прячет, тело
// метит closed|open. React-узлы не переносятся, их текст не меняется. Плюс
// слово Элвиса 08.10 «по возможности сворачивать… чтоб здесь кнопка
// появилась»: у ответа выше двух экранов — «▾ Свернуть ответ / ▸ Развернуть ответ»
// (WF218, #9426: стрелка впереди, как у заголовков свёрток).
//
// Разметку гоняет люк inner.foldTick(); нажатие — click на document (стенд
// событий не всплывает), клавиши — keydown на window.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const HEAD = "data-myclaude-fold-head";
const LABEL = "data-myclaude-fold-label";
const RAW = "data-myclaude-fold-raw";
const BODY = "data-myclaude-fold-body";
const WHOLE = "data-myclaude-fold-whole";
const LONG = "data-myclaude-fold-long";

// Лента с одним ответом (transcript-row/assistant_text); build кладёт блоки в
// корень ответа. height — высота строки ответа (экран стенда — 800).
const page = ({ build, height = 300 } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_fold-1111", title: "Rick",
    html: dom => {
      const parts = dom.composer({ text: "" });
      const feed = dom.document.body.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript" },
        rect: { left: 0, top: 0, width: 1200, height: 500 },
      });
      const row = feed.add("div", {
        attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" },
        rect: { left: 0, top: 0, width: 800, height },
      });
      parts.row = row;
      parts.box = row.add("div", { class: "contents" });
      parts.nodes = build(parts.box, dom) ?? {};
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.inner.foldTick();
  const click = (node, extra = {}) => {
    loaded.dom.document.dispatchEvent({ type: "click", target: node, detail: 1, isTrusted: true, ...extra });
  };
  const key = (name, target, extra = {}) => {
    const event = { type: "keydown", key: name, target, isTrusted: true, bubbles: true, cancelable: true, ...extra };
    return { defaultPrevented: !loaded.win.dispatchEvent(event) };
  };
  return { loaded, parts: loaded.parts, n: loaded.parts.nodes, click, key, tick: () => loaded.inner.foldTick() };
};
const folds = loaded => plain(loaded.api.status().folds);
const heads = loaded => loaded.dom.queryAll(`[${HEAD}]:not([${WHOLE}])`);
const wholes = loaded => loaded.dom.queryAll(`[${WHOLE}]`);
const kids = parent => [...parent.childNodes].filter(node => node.nodeType === 1);

// Ответ Рика 08.10, как его печатает Desktop: каждый тег — отдельный <p>.
const oneFold = box => ({
  lead: box.add("p", { text: "Сейчас: сайт первым." }),
  open: box.add("p", { text: "<details><summary><b>1. Сайт</b> — первым</summary>" }),
  body1: box.add("p", { text: "Ошибка исправлена, на сайте с 19:09." }),
  body2: box.add("ul", { text: "пункт" }),
  close: box.add("p", { text: "</details>" }),
  tail: box.add("p", { text: "Дальше — ничего." }),
});

test("12ф: сырой <details> — свой заголовок перед <p>, теги спрятаны, тело закрыто по умолчанию", () => {
  const { loaded, parts, n } = page({ build: oneFold });
  const before = kids(parts.box).filter(node => !node.hasAttribute(HEAD));
  const list = heads(loaded);
  assert.equal(list.length, 1);
  const head = list[0];
  assert.equal(head.nextElementSibling, n.open, "заголовок — прямо перед сырым <p>");
  assert.equal(head.getAttribute("role"), "button");
  assert.equal(head.getAttribute("tabindex"), "0");
  assert.equal(head.getAttribute(HEAD), "closed");
  assert.equal(head.getAttribute("aria-expanded"), "false");
  assert.equal(head.getAttribute(LABEL), "▸ 1. Сайт — первым");
  assert.equal(head.textContent, "", "подпись — из атрибута: копия и выделение её не видят");
  assert.equal(n.open.getAttribute(RAW), "");
  assert.equal(n.close.getAttribute(RAW), "");
  assert.equal(n.body1.getAttribute(BODY), "closed");
  assert.equal(n.body2.getAttribute(BODY), "closed");
  for (const node of [n.lead, n.tail]) { assert.equal(node.hasAttribute(BODY), false); assert.equal(node.hasAttribute(RAW), false); }
  // React-узлы на местах, текст не тронут (Copy копирует исходник с тегами).
  assert.deepEqual(kids(parts.box).filter(node => !node.hasAttribute(HEAD)), before);
  assert.equal(n.open.textContent, "<details><summary><b>1. Сайт</b> — первым</summary>");
  assert.equal(n.close.textContent, "</details>");
  assert.deepEqual(folds(loaded), { count: 1, open: 0, long: 0, shut: 0, clicks: 0 });
});

test("12ф: нажатие, Enter и пробел — открыть/закрыть; повторный проход ничего не дублирует", () => {
  const { loaded, n, click, key, tick } = page({ build: oneFold });
  const head = heads(loaded)[0];
  click(head);
  assert.equal(head.getAttribute(HEAD), "open");
  assert.equal(head.getAttribute("aria-expanded"), "true");
  assert.equal(head.getAttribute(LABEL), "▾ 1. Сайт — первым");
  assert.equal(n.body1.getAttribute(BODY), "open");
  assert.equal(n.open.getAttribute(RAW), "", "сырые теги спрятаны и в открытой");
  tick(); tick();
  assert.equal(heads(loaded).length, 1);
  assert.equal(heads(loaded)[0], head, "тот же узел заголовка");
  const enter = key("Enter", head);
  assert.equal(enter.defaultPrevented, true);
  assert.equal(n.body1.getAttribute(BODY), "closed");
  key(" ", head);
  assert.equal(n.body1.getAttribute(BODY), "open");
  // Двойной клик — одно нажатие.
  click(head, { detail: 2 });
  assert.equal(n.body1.getAttribute(BODY), "open");
  assert.equal(folds(loaded).open, 1);
  assert.equal(folds(loaded).clicks, 3);
  // Enter не на заголовке — мимо.
  const other = key("Enter", n.tail);
  assert.equal(other.defaultPrevented, false);
});

test("12ф: Esc — закрыть открытую под фокусом (заголовок или тело); в поле ввода — мимо", () => {
  const { loaded, parts, n, click, key } = page({ build: oneFold });
  const head = heads(loaded)[0];
  click(head);
  head.focus();
  const esc = key("Escape", head);
  assert.equal(esc.defaultPrevented, true);
  assert.equal(n.body1.getAttribute(BODY), "closed");
  click(head);
  loaded.dom.document.activeElement = n.body1;
  key("Escape", n.body1);
  assert.equal(n.body1.getAttribute(BODY), "closed");
  assert.equal(loaded.dom.document.activeElement, head, "фокус — на заголовок");
  click(head);
  parts.editor.focus();
  // Esc в поле — у Claude и других разделов, свёртку не трогаем.
  const clicks = folds(loaded).clicks;
  key("Escape", parts.editor);
  assert.equal(n.body1.getAttribute(BODY), "open");
  assert.equal(folds(loaded).clicks, clicks);
  // Закрытая — Esc не трогаем.
  click(head);
  head.focus();
  key("Escape", head);
  assert.equal(n.body1.getAttribute(BODY), "closed");
  assert.equal(folds(loaded).clicks, clicks + 1);
});

test("12ф: закрывающего нет (ответ пишется, тег без пары) — не трогаем", () => {
  const { loaded, n, tick } = page({
    build: box => ({
      open: box.add("p", { text: "<details><summary>Пишется</summary>" }),
      body: box.add("p", { text: "текст" }),
      stray: box.add("p", { text: "</details>" }),
    }),
  });
  // Пара есть — свёртка; теперь закрывающий пропал (React перерисовал).
  assert.equal(heads(loaded).length, 1);
  n.stray.remove();
  tick();
  assert.equal(heads(loaded).length, 0);
  assert.equal(n.open.hasAttribute(RAW), false);
  assert.equal(n.body.hasAttribute(BODY), false);
  assert.equal(folds(loaded).count, 0);
});

test("12ф: одиночный </details> и `<details>` в строке кода — не теги", () => {
  const { loaded, n } = page({
    build: (box, dom) => {
      const code = box.add("p");
      code.add("code", { text: "<details>" });
      return {
        code,
        lone: box.add("p", { text: "</details>" }),
        inline: box.add("p", { text: "Пиши <details> с пустой строкой" }),
      };
    },
  });
  assert.equal(heads(loaded).length, 0);
  for (const node of [n.code, n.lone, n.inline]) assert.equal(node.hasAttribute(RAW), false);
});

test("12ф: <summary> отдельным <p>, <details open> — открыта, пустой заголовок — «Подробнее»", () => {
  const { loaded, n } = page({
    build: box => ({
      open: box.add("p", { text: "<details open>" }),
      summary: box.add("p", { text: "<summary>Отдельно</summary>" }),
      body: box.add("p", { text: "тело" }),
      close: box.add("p", { text: "</details>" }),
      open2: box.add("p", { text: "<details>" }),
      body2: box.add("p", { text: "без заголовка" }),
      close2: box.add("p", { text: "</details>" }),
    }),
  });
  const [first, second] = heads(loaded);
  assert.equal(first.getAttribute(LABEL), "▾ Отдельно");
  assert.equal(first.getAttribute(HEAD), "open");
  assert.equal(n.summary.getAttribute(RAW), "");
  assert.equal(n.summary.hasAttribute(BODY), false, "<summary> — не тело");
  assert.equal(n.body.getAttribute(BODY), "open");
  assert.equal(second.getAttribute(LABEL), "▸ Подробнее");
  assert.equal(n.body2.getAttribute(BODY), "closed");
});

test("12ф: вложенные — стеком; закрытая внешняя прячет и заголовок внутренней", () => {
  const { loaded, n, click } = page({
    build: box => ({
      outer: box.add("p", { text: "<details><summary>Внешняя</summary>" }),
      a: box.add("p", { text: "до" }),
      inner: box.add("p", { text: "<details><summary>Внутренняя</summary>" }),
      b: box.add("p", { text: "внутри" }),
      innerClose: box.add("p", { text: "</details>" }),
      c: box.add("p", { text: "после" }),
      outerClose: box.add("p", { text: "</details>" }),
    }),
  });
  assert.equal(folds(loaded).count, 2);
  const outerHead = n.outer.previousElementSibling;
  const innerHead = n.inner.previousElementSibling;
  assert.equal(outerHead.getAttribute(LABEL), "▸ Внешняя");
  assert.equal(innerHead.getAttribute(LABEL), "▸ Внутренняя");
  assert.equal(innerHead.getAttribute(BODY), "closed", "внешняя закрыта — заголовок внутренней спрятан");
  for (const node of [n.a, n.b, n.c]) assert.equal(node.getAttribute(BODY), "closed");
  click(outerHead);
  // WF225 (#9426): раскрытая внешняя ведёт полосу и сквозь заголовок внутренней — метка та же, что у тела.
  assert.equal(innerHead.getAttribute(BODY), "open");
  assert.equal(n.a.getAttribute(BODY), "open");
  assert.equal(n.c.getAttribute(BODY), "open");
  assert.equal(n.b.getAttribute(BODY), "closed", "внутренняя закрыта сама по себе");
  click(innerHead);
  assert.equal(n.b.getAttribute(BODY), "open");
  click(outerHead);
  assert.equal(n.b.getAttribute(BODY), "closed", "закрыл внешнюю — спрятано всё внутри");
  assert.equal(innerHead.getAttribute(HEAD), "open", "внутренняя помнит, что открыта");
});

test("12ф: ⌥-нажатие — все свёртки ответа разом", () => {
  const { loaded, n, click } = page({
    build: box => ({
      o1: box.add("p", { text: "<details><summary>Один</summary>" }),
      b1: box.add("p", { text: "1" }),
      c1: box.add("p", { text: "</details>" }),
      o2: box.add("p", { text: "<details><summary>Два</summary>" }),
      b2: box.add("p", { text: "2" }),
      c2: box.add("p", { text: "</details>" }),
    }),
  });
  click(n.o1.previousElementSibling, { altKey: true });
  assert.equal(n.b1.getAttribute(BODY), "open");
  assert.equal(n.b2.getAttribute(BODY), "open");
  assert.equal(folds(loaded).open, 2);
  click(n.o2.previousElementSibling, { altKey: true });
  assert.equal(n.b1.getAttribute(BODY), "closed");
  assert.equal(n.b2.getAttribute(BODY), "closed");
});

test("12ф: открытое остаётся открытым, когда React пересоздал узлы ответа", () => {
  const { loaded, parts, click, tick } = page({ build: oneFold });
  click(heads(loaded)[0]);
  for (const node of [...parts.box.childNodes]) node.remove();
  const again = oneFold(parts.box);
  tick();
  assert.equal(heads(loaded).length, 1);
  assert.equal(again.body1.getAttribute(BODY), "open");
});

// ---- «Свернуть ответ» --------------------------------------------------------
const longAnswer = box => ({
  first: box.add("p", { text: "Первый абзац ответа." }),
  second: box.add("p", { text: "Второй." }),
  list: box.add("ul", { text: "пункты" }),
  last: box.add("p", { text: "Конец." }),
});

test("12ф: ответ выше двух экранов — тихая кнопка под первым абзацем, по умолчанию не свёрнут", () => {
  const { loaded, n, click, key, tick } = page({ build: longAnswer, height: 1700 });
  const [whole] = wholes(loaded);
  assert.ok(whole);
  assert.equal(n.first.nextElementSibling, whole);
  assert.equal(whole.getAttribute("role"), "button");
  assert.equal(whole.getAttribute(WHOLE), "open");
  assert.equal(whole.getAttribute(LABEL), "▾ Свернуть ответ");
  // WF225 (#9426): раскрытое под кнопкой помечено — по метке идёт полоса слева; первый абзац — нет.
  for (const node of [n.second, n.list, n.last]) assert.equal(node.getAttribute(LONG), "open");
  assert.equal(n.first.hasAttribute(LONG), false);
  click(whole);
  assert.equal(whole.getAttribute(WHOLE), "closed");
  assert.equal(whole.getAttribute(LABEL), "▸ Развернуть ответ");
  assert.equal(whole.getAttribute("aria-expanded"), "false");
  for (const node of [n.second, n.list, n.last]) assert.equal(node.getAttribute(LONG), "closed");
  assert.equal(n.first.hasAttribute(LONG), false);
  // Свёрнутый ответ стал низким — кнопка остаётся.
  loaded.parts.row.rect.height = 200;
  tick();
  assert.equal(wholes(loaded).length, 1);
  assert.deepEqual(folds(loaded), { count: 0, open: 0, long: 1, shut: 1, clicks: 1 });
  // Развернул — ответ снова высокий, кнопка на месте.
  loaded.parts.row.rect.height = 1700;
  key("Enter", whole);
  assert.equal(whole.getAttribute(WHOLE), "open");
  assert.equal(wholes(loaded).length, 1);
  for (const node of [n.second, n.list, n.last]) assert.equal(node.getAttribute(LONG), "open");
  // WF225: полоса сама меняет высоту ответа — у порога (2 экрана = 1600) кнопка держится с запасом, не мигает.
  loaded.parts.row.rect.height = 1500;
  tick();
  assert.equal(wholes(loaded).length, 1, "чуть ниже порога — кнопка остаётся");
  // Развёрнут и низкий — кнопки нет, меток полосы тоже.
  loaded.parts.row.rect.height = 200;
  tick();
  assert.equal(wholes(loaded).length, 0);
  for (const node of [n.second, n.list, n.last]) assert.equal(node.hasAttribute(LONG), false);
});

// WF225 (#9426, слово Элвиса 10.10: при развороте свёрнутые группы выделять полосой — большая группа
// или небольшая): под раскрытой кнопкой «Свернуть ответ» помечено всё, вместе со своими заголовками
// свёрток; тело <details> несёт обе метки, а правило полосы на них одно — двойной линии нет.
test("12ф: раскрытая большая свёртка — полоса по метке у всего под кнопкой; <details> внутри — без двойной", () => {
  const { loaded, n, click } = page({
    height: 1700,
    build: box => ({
      first: box.add("p", { text: "Первый абзац ответа." }),
      second: box.add("p", { text: "Второй." }),
      shutOpen: box.add("p", { text: "<details><summary>Закрытая</summary>" }),
      shutBody: box.add("p", { text: "скрыто" }),
      shutClose: box.add("p", { text: "</details>" }),
      openOpen: box.add("p", { text: "<details open><summary>Раскрытая</summary>" }),
      openBody: box.add("p", { text: "видно" }),
      openList: box.add("ul", { text: "пункты" }),
      openClose: box.add("p", { text: "</details>" }),
      list: box.add("ol", { text: "раз два" }),
      code: box.add("div", { attrs: { "data-not-prose": "" }, text: "ls" }),
      last: box.add("p", { text: "Конец." }),
    }),
  });
  const [whole] = wholes(loaded);
  assert.equal(whole.getAttribute(WHOLE), "open");
  assert.equal(n.first.nextElementSibling, whole);
  const [shutHead, openHead] = heads(loaded);
  // Всё под кнопкой — в полосе: абзацы, списки, код, сырые теги и свои заголовки свёрток.
  const under = [];
  for (let node = whole.nextElementSibling; node; node = node.nextElementSibling) under.push(node);
  assert.equal(under.length, 13);
  assert.ok(under.includes(shutHead) && under.includes(openHead));
  for (const node of under) assert.equal(node.getAttribute(LONG), "open");
  assert.equal(whole.hasAttribute(LONG), false, "сама кнопка — не тело");
  assert.equal(n.first.hasAttribute(LONG), false);
  // Свои заголовки места не меняют: метки тела у них нет, состояние — своё.
  assert.equal(shutHead.hasAttribute(BODY), false);
  assert.equal(shutHead.getAttribute(HEAD), "closed");
  assert.equal(openHead.getAttribute(HEAD), "open");
  // Тела <details>: закрытое спрятано своей меткой, раскрытое — в той же полосе.
  assert.equal(n.shutBody.getAttribute(BODY), "closed");
  assert.equal(n.openBody.getAttribute(BODY), "open");
  assert.equal(n.openList.getAttribute(BODY), "open");
  assert.equal(n.list.hasAttribute(BODY), false);
  // Одно правило линии на обе метки; заголовки, сырые теги и свёрнутый блок «Прочитано» — мимо.
  const rules = [...loaded.inner.RULES];
  const strip = `:is([${BODY}="open"],[${LONG}="open"]):not([${HEAD}],[${RAW}],:is([data-myclaude-read="head"],[data-myclaude-read="bare"]) *)`;
  const lines = rules.filter(rule => rule.includes("border-left:1.5px solid currentColor") && (rule.includes(`[${LONG}="open"]`) || rule.includes(`[${BODY}="open"]`)) && !rule.includes("::before") && !rule.includes("blockquote:is("));
  assert.equal(lines.length, 1, "линию узлу полосы даёт ровно одно правило");
  assert.ok(lines[0].endsWith(`,${strip}:not(blockquote,table){${lines[0].slice(lines[0].indexOf("{") + 1)}`));
  assert.ok(rules.some(rule => rule.startsWith(`[${HEAD}]:is([${BODY}="open"],[${LONG}="open"])::before{`) && rule.includes("border-left:1.5px solid currentColor")), "сквозь свой заголовок линию ведёт его слой");
  // Свернул ответ — раскрытых меток нет, всё под кнопкой спрятано; развернул — полоса вернулась.
  click(whole);
  for (const node of under) assert.equal(node.getAttribute(LONG), "closed");
  assert.equal(loaded.dom.queryAll(`[${LONG}="open"]`).length, 0);
  click(whole);
  for (const node of under) assert.equal(node.getAttribute(LONG), "open");
  // Текст ответа тот же: узлы на местах, сырые теги целы.
  assert.equal(n.openOpen.textContent, "<details open><summary>Раскрытая</summary>");
  assert.equal(kids(loaded.parts.box).filter(node => !node.hasAttribute(HEAD)).length, 12);
  // dispose снимает метки полосы и свои узлы.
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`[${HEAD}]`).length, 0);
  for (const node of kids(loaded.parts.box)) for (const attr of [RAW, BODY, LONG]) assert.equal(node.hasAttribute(attr), false);
});

test("12ф: вложенные раскрыты — полоса внешней идёт сквозь заголовок внутренней; закрыл внутреннюю — заголовок в полосе", () => {
  const { n, click } = page({
    build: box => ({
      outer: box.add("p", { text: "<details open><summary>Внешняя</summary>" }),
      a: box.add("p", { text: "до" }),
      inner: box.add("p", { text: "<details open><summary>Внутренняя</summary>" }),
      b: box.add("p", { text: "внутри" }),
      innerClose: box.add("p", { text: "</details>" }),
      c: box.add("p", { text: "после" }),
      outerClose: box.add("p", { text: "</details>" }),
    }),
  });
  const outerHead = n.outer.previousElementSibling;
  const innerHead = n.inner.previousElementSibling;
  assert.equal(outerHead.hasAttribute(BODY), false, "заголовок внешней — вне полосы");
  assert.equal(innerHead.getAttribute(BODY), "open");
  for (const node of [n.a, n.b, n.c]) assert.equal(node.getAttribute(BODY), "open");
  for (const node of [n.a, n.b, n.c, innerHead]) assert.equal(node.hasAttribute(LONG), false, "короткий ответ — метки большой свёртки нет");
  click(innerHead);
  assert.equal(n.b.getAttribute(BODY), "closed");
  assert.equal(innerHead.getAttribute(BODY), "open", "закрытая внутренняя: её заголовок по-прежнему в полосе внешней");
  click(outerHead);
  assert.equal(innerHead.getAttribute(BODY), "closed");
  for (const node of [n.a, n.b, n.c]) assert.equal(node.getAttribute(BODY), "closed");
});

// WF218 (#9426): клавиши у кнопки — как у заголовков свёрток.
test("12ф: Esc на кнопке «Свернуть ответ» сворачивает ответ; на свёрнутой и в тексте ответа — мимо", () => {
  const { loaded, n, key } = page({ build: longAnswer, height: 1700 });
  const [whole] = wholes(loaded);
  loaded.dom.document.activeElement = n.second;
  key("Escape", n.second);
  assert.equal(whole.getAttribute(WHOLE), "open");
  assert.equal(folds(loaded).clicks, 0);
  loaded.dom.document.activeElement = whole;
  key("Escape", whole);
  assert.equal(whole.getAttribute(WHOLE), "closed");
  assert.equal(whole.getAttribute(LABEL), "▸ Развернуть ответ");
  for (const node of [n.second, n.list, n.last]) assert.equal(node.getAttribute(LONG), "closed");
  key("Escape", whole);
  assert.equal(whole.getAttribute(WHOLE), "closed");
  assert.equal(folds(loaded).clicks, 1);
  key(" ", whole);
  assert.equal(whole.getAttribute(WHOLE), "open");
});

test("12ф: короткий ответ — без кнопки «Свернуть ответ»", () => {
  const { loaded } = page({ build: longAnswer, height: 1500 });
  assert.equal(wholes(loaded).length, 0);
});

test("12ф: dispose снимает заголовки, кнопки и метки; новая установка не плодит дублей", () => {
  const { loaded, parts, n } = page({
    height: 1700,
    build: box => ({ ...oneFold(box) }),
  });
  assert.equal(heads(loaded).length, 1);
  assert.equal(wholes(loaded).length, 1);
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`[${HEAD}]`).length, 0);
  for (const node of kids(parts.box)) for (const attr of [RAW, BODY, LONG]) assert.equal(node.hasAttribute(attr), false);
  assert.equal(n.open.textContent, "<details><summary><b>1. Сайт</b> — первым</summary>");
});
