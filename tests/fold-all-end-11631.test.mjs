// #11631 (страница, раздел 12ф): слово Элвиса 04.11.2026 — «эти кнопки развернуть всё и свернуть всё. Они сейчас сверху
// ответа только располагаются. Давай ещё внизу ответа сделаем эти же кнопки две… Я буду нажимать». Та же строка —
// последней в корне ответа: те же подписи и состояния, нажатие снизу правит обе; свёрнутый ответ прячет её с хвостом.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const HEAD = "data-myclaude-fold-head";
const LABEL = "data-myclaude-fold-label";
const BODY = "data-myclaude-fold-body";
const WHOLE = "data-myclaude-fold-whole";
const LONG = "data-myclaude-fold-long";
const ALL = "data-myclaude-fold-all";
const END = "data-myclaude-fold-all-end";

const page = ({ build, height = 300 } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_fold-11631", title: "Rick",
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
      parts.box = row.add("div", { class: "contents" });
      parts.nodes = build(parts.box, dom) ?? {};
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.inner.foldTick();
  const click = node => loaded.dom.document.dispatchEvent({ type: "click", target: node, detail: 1, isTrusted: true });
  const key = (name, target) => ({ defaultPrevented: !loaded.win.dispatchEvent({ type: "keydown", key: name, target, isTrusted: true, bubbles: true, cancelable: true }) });
  return { loaded, n: loaded.parts.nodes, box: loaded.parts.box, click, key, tick: () => loaded.inner.foldTick() };
};
const bars = loaded => loaded.dom.queryAll(`[${ALL}="bar"]`);
const top = loaded => bars(loaded).find(bar => !bar.hasAttribute(END));
const end = loaded => bars(loaded).find(bar => bar.hasAttribute(END));
const state = bar => [...bar.children].map(button => [button.getAttribute(LABEL), button.getAttribute("aria-disabled")]);
const heads = loaded => loaded.dom.queryAll(`[${HEAD}]:not([${WHOLE}])`);
const three = box => ({
  title: box.add("h1", { text: "Сделано три дела" }),
  a1: box.add("p", { text: "<details><summary>Первое</summary>" }),
  b1: box.add("p", { text: "тело первого" }),
  c1: box.add("p", { text: "</details>" }),
  a2: box.add("p", { text: "<details><summary>Второе</summary>" }),
  b2: box.add("p", { text: "тело второго" }),
  c2: box.add("p", { text: "</details>" }),
  a3: box.add("p", { text: "<details><summary>Третье</summary>" }),
  b3: box.add("p", { text: "тело третьего" }),
  c3: box.add("p", { text: "</details>" }),
  last: box.add("p", { text: "Итог одной строкой." }),
});

test("#11631: внизу ответа — та же строка «Развернуть всё (N) / Свернуть всё», последней в ответе", () => {
  const { loaded, n, box } = page({ build: three });
  assert.equal(bars(loaded).length, 2);
  const bottom = end(loaded);
  assert.ok(bottom, "нижняя строка есть");
  assert.equal(box.lastElementChild, bottom, "последней — под последним абзацем");
  assert.equal(n.last.nextElementSibling, bottom);
  assert.equal(n.title.nextElementSibling, top(loaded), "верхняя — на месте, под заголовком");
  assert.deepEqual(state(bottom), state(top(loaded)));
  assert.deepEqual(state(bottom), [["Развернуть", "false"], ["Свернуть", "true"]]);
  for (const button of bottom.children) {
    assert.equal(button.getAttribute("role"), "button");
    assert.equal(button.getAttribute("tabindex"), "0");
  }
  assert.equal(bottom.textContent, "", "копия подписей не видит");
});

test("#11631: нажатие снизу — все свёртки ответа, обе строки меняют состояние; Enter и пробел — те же", () => {
  const { loaded, n, click, key } = page({ build: three });
  click(end(loaded).children[0]);
  assert.deepEqual(heads(loaded).map(head => head.getAttribute(HEAD)), ["open", "open", "open"]);
  for (const node of [n.b1, n.b2, n.b3]) assert.equal(node.getAttribute(BODY), "open");
  for (const bar of [top(loaded), end(loaded)]) assert.deepEqual(state(bar), [["Развернуть", "true"], ["Свернуть", "false"]]);
  assert.equal(key("Enter", end(loaded).children[1]).defaultPrevented, true);
  assert.deepEqual(heads(loaded).map(head => head.getAttribute(HEAD)), ["closed", "closed", "closed"]);
  key(" ", end(loaded).children[0]);
  assert.equal(n.b3.getAttribute(BODY), "open");
  assert.equal(loaded.api.status().folds.clicks, 3);
});

test("#11631: ответ дописался — нижняя строка снова последняя, без дублей; одна свёртка — строк нет; dispose убирает", () => {
  const { loaded, box, tick } = page({ build: three });
  const bottom = end(loaded);
  const added = box.add("p", { text: "Дописано после." });
  assert.equal(box.lastElementChild, added);
  tick();
  assert.equal(box.lastElementChild, bottom, "та же строка переехала вниз");
  assert.equal(bars(loaded).length, 2);
  loaded.api.dispose();
  assert.equal(bars(loaded).length, 0);
  const one = page({ build: box => ({
    a: box.add("p", { text: "<details><summary>Один</summary>" }),
    b: box.add("p", { text: "тело" }),
    c: box.add("p", { text: "</details>" }),
  }) });
  assert.equal(bars(one.loaded).length, 0);
});

test("#11631: «Свернуть ответ» прячет нижнюю строку с хвостом, верхняя видна; «Развернуть всё» сверху её возвращает", () => {
  const { loaded, n, click } = page({ height: 1700, build: box => ({ first: box.add("p", { text: "Сначала главное." }), ...three(box) }) });
  const whole = loaded.dom.queryAll(`[${WHOLE}]`)[0];
  assert.ok(whole);
  click(whole);
  assert.equal(whole.getAttribute(WHOLE), "closed");
  assert.equal(end(loaded).getAttribute(LONG), "closed", "нижняя — в свёрнутом хвосте");
  assert.equal(top(loaded).hasAttribute(LONG), false, "верхняя — над первым абзацем, видна");
  assert.equal(top(loaded).nextElementSibling, n.first);
  click(top(loaded).children[0]);
  assert.equal(whole.getAttribute(WHOLE), "open");
  assert.equal(end(loaded).hasAttribute(LONG), false);
  assert.equal(n.last.nextElementSibling, end(loaded));
});

test("#11631: нажата нижняя — она остаётся под курсором (лента сдвинута на столько, на сколько уехала строка); верхняя ленту не двигает", () => {
  const { loaded, click } = page({ build: three });
  const feed = loaded.dom.document.querySelector('[data-testid="epitaxy-virtual-transcript"]');
  feed.scrollTop = 1000;
  const bottom = end(loaded);
  // «Развернуть всё» снизу: над строкой выросло на 600 — строка ушла вниз, лента едет за ней.
  const tops = [400, 1000];
  bottom.getBoundingClientRect = () => { const top = tops.length > 1 ? tops.shift() : tops[0]; return { left: 0, top, right: 800, bottom: top + 20, width: 800, height: 20 }; };
  click(bottom.children[0]);
  assert.equal(feed.scrollTop, 1600);
  // «Свернуть всё» снизу: сжалось на 600 — лента назад.
  tops.splice(0, tops.length, 1000, 400);
  click(bottom.children[1]);
  assert.equal(feed.scrollTop, 1000);
  // Сдвиг в пиксель — не трогаем.
  tops.splice(0, tops.length, 400, 401);
  click(bottom.children[0]);
  assert.equal(feed.scrollTop, 1000);
  // Верхняя — под ней растёт само, лента стоит.
  top(loaded).getBoundingClientRect = () => { throw new Error("верхнюю не меряем"); };
  click(top(loaded).children[1]);
  assert.equal(feed.scrollTop, 1000);
  assert.equal(end(loaded), bottom, "строка та же");
});

test("#11631: свёртка со вложенными — без полос (метка flat у её узлов и голов вложенных), раскрытая вложенная — со своей", () => {
  const FLAT = "data-myclaude-fold-flat";
  const { loaded, n, click } = page({ build: box => ({
    a: box.add("p", { text: "<details>" }),
    s: box.add("p", { text: "<summary><b>💬 ОТВЕТЫ НА ТВОИ ВОПРОСЫ — 2</b></summary>" }),
    intro: box.add("p", { text: "Коротко по двум." }),
    a1: box.add("p", { text: "<details><summary>1. Адрес — да</summary>" }),
    q1: box.add("blockquote", { text: "Лена подтвердила адрес." }),
    c1: box.add("p", { text: "</details>" }),
    a2: box.add("p", { text: "<details><summary>2. Крышки — нет</summary>" }),
    q2: box.add("blockquote", { text: "Крышки отдельно." }),
    c2: box.add("p", { text: "</details>" }),
    c: box.add("p", { text: "</details>" }),
    b: box.add("p", { text: "<details><summary>Простая</summary>" }),
    body: box.add("p", { text: "тело простой" }),
    e: box.add("p", { text: "</details>" }),
  }) });
  const byTitle = title => heads(loaded).find(head => head.getAttribute("aria-label") === title);
  click(byTitle("💬 ОТВЕТЫ НА ТВОИ ВОПРОСЫ — 2"));
  const inner = [byTitle("1. Адрес — да"), byTitle("2. Крышки — нет")];
  for (const head of inner) assert.equal(head.getAttribute(BODY), "open");
  for (const head of inner) assert.equal(head.hasAttribute(FLAT), true, "сквозь голову вложенной — без полосы");
  assert.equal(n.intro.getAttribute(BODY), "open");
  assert.equal(n.intro.hasAttribute(FLAT), true, "свой узел внешней — без полосы");
  click(inner[0]);
  assert.equal(n.q1.getAttribute(BODY), "open");
  assert.equal(n.q1.hasAttribute(FLAT), false, "тело раскрытой вложенной — со своей полосой");
  click(byTitle("Простая"));
  assert.equal(n.body.getAttribute(BODY), "open");
  assert.equal(n.body.hasAttribute(FLAT), false, "без вложенных — полоса как была");
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`[${FLAT}]`).length, 0, "dispose снимает метку");
});
