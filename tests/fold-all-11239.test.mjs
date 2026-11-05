// #11239 (страница, раздел 12ф): слово Элвиса 30.10 18:47 — «должны быть кнопки сверху… развернуть, свернуть… чтоб я мог
// всё развернуть и тогда читать всё как одним сообщением группированным… чтобы при этом разворачивании дублирования не
// было инфы». У ответа с двумя свёртками и больше — строка ссылок «Развернуть всё (N)» и «Свернуть всё» под заголовком;
// развернуть — все свёртки (и вложенные) и свёрнутый ответ целиком, без сводки.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const HEAD = "data-myclaude-fold-head";
const LABEL = "data-myclaude-fold-label";
const BODY = "data-myclaude-fold-body";
const WHOLE = "data-myclaude-fold-whole";
const LONG = "data-myclaude-fold-long";
const ALL = "data-myclaude-fold-all";

const page = ({ build, height = 300 } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_fold-11239", title: "Rick",
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
  const click = node => loaded.dom.document.dispatchEvent({ type: "click", target: node, detail: 1, isTrusted: true });
  const key = (name, target) => ({ defaultPrevented: !loaded.win.dispatchEvent({ type: "keydown", key: name, target, isTrusted: true, bubbles: true, cancelable: true }) });
  return { loaded, n: loaded.parts.nodes, click, key, tick: () => loaded.inner.foldTick() };
};
const heads = loaded => loaded.dom.queryAll(`[${HEAD}]:not([${WHOLE}])`);
const bars = loaded => loaded.dom.queryAll(`[${ALL}="bar"]`);
const buttons = loaded => {
  const [bar] = bars(loaded);
  return { bar, open: bar.children[0], close: bar.children[1] };
};
const folds = loaded => plain(loaded.api.status().folds);

// Ответ Рика по форме ELVIS.md: `# ` → «💬 Ответы» → «## Ждёт тебя» с пунктами-свёртками; один пункт с вложенной.
const rick = box => ({
  title: box.add("h1", { text: "Распродажа 01.11 готова" }),
  a1: box.add("p", { text: "<details><summary><b>💬 ОТВЕТЫ НА ТВОИ ВОПРОСЫ — 2</b></summary>" }),
  b1: box.add("p", { text: "1. Адрес — да." }),
  c1: box.add("p", { text: "</details>" }),
  h2: box.add("h2", { text: "❗ Ждёт тебя 2" }),
  a2: box.add("p", { text: "<details><summary><b>17 · Распродажа — «да» на цену</b></summary>" }),
  b2: box.add("p", { text: "Маркетолог собрал распродажу." }),
  a3: box.add("p", { text: "<details><summary>Подробнее про цену</summary>" }),
  b3: box.add("p", { text: "А — 3 290, Б — 3 490." }),
  c3: box.add("p", { text: "</details>" }),
  c2: box.add("p", { text: "</details>" }),
  a4: box.add("p", { text: "<details><summary><b>6 · Гастроёмкости — корзина</b></summary>" }),
  b4: box.add("p", { text: "Корзина Kaspi на 30 314." }),
  c4: box.add("p", { text: "</details>" }),
});

test("#11239: строка «Развернуть всё (N) / Свернуть всё» — под заголовком ответа, подписи из атрибута", () => {
  const { loaded, n } = page({ build: rick });
  assert.equal(bars(loaded).length, 2, "сверху и внизу ответа (#11631)");
  const { bar, open, close } = buttons(loaded);
  assert.equal(n.title.nextElementSibling, bar, "сразу под # заголовком");
  assert.equal(bar.nextElementSibling?.getAttribute(HEAD), "closed", "дальше — крупная «💬»");
  for (const button of [open, close]) {
    assert.equal(button.getAttribute("role"), "button");
    assert.equal(button.getAttribute("tabindex"), "0");
  }
  assert.equal(open.getAttribute(LABEL), "Развернуть");
  assert.equal(close.getAttribute(LABEL), "Свернуть");
  assert.equal(bar.textContent, "", "копия и «Прочитано» подписей не видят");
  assert.equal(open.getAttribute("aria-disabled"), "false");
  assert.equal(close.getAttribute("aria-disabled"), "true", "всё закрыто — сворачивать нечего");
  assert.equal(folds(loaded).all, 1);
});

test("#11239: «Развернуть всё» — все свёртки, вложенные тоже; «Свернуть всё» — все закрыты; клавиши — те же", () => {
  const { loaded, n, click, key, tick } = page({ build: rick });
  const { open, close } = buttons(loaded);
  click(open);
  assert.deepEqual(heads(loaded).map(head => head.getAttribute(HEAD)), ["open", "open", "open", "open"]);
  for (const node of [n.b1, n.b2, n.b3, n.b4]) assert.equal(node.getAttribute(BODY), "open");
  assert.equal(open.getAttribute("aria-disabled"), "true");
  assert.equal(close.getAttribute("aria-disabled"), "false");
  tick();
  assert.equal(bars(loaded).length, 2, "повторный проход строки не дублирует");
  assert.equal(n.title.nextElementSibling, buttons(loaded).bar);
  assert.equal(key("Enter", close).defaultPrevented, true);
  assert.deepEqual(heads(loaded).map(head => head.getAttribute(HEAD)), ["closed", "closed", "closed", "closed"]);
  for (const node of [n.b1, n.b2, n.b3, n.b4]) assert.equal(node.getAttribute(BODY), "closed");
  key(" ", open);
  assert.equal(n.b3.getAttribute(BODY), "open");
  assert.equal(folds(loaded).clicks, 3);
});

test("#11239: одна свёртка — строки нет; без заголовка — перед первой свёрткой; dispose убирает", () => {
  const one = page({ build: box => ({
    a: box.add("p", { text: "<details><summary>Один</summary>" }),
    b: box.add("p", { text: "тело" }),
    c: box.add("p", { text: "</details>" }),
  }) });
  assert.equal(bars(one.loaded).length, 0);
  const two = page({ build: box => ({
    a: box.add("p", { text: "<details><summary>Первая</summary>" }),
    b: box.add("p", { text: "тело" }),
    c: box.add("p", { text: "</details>" }),
    d: box.add("p", { text: "<details><summary>Вторая</summary>" }),
    e: box.add("p", { text: "тело" }),
    f: box.add("p", { text: "</details>" }),
  }) });
  const { bar } = buttons(two.loaded);
  assert.equal(bar.nextElementSibling?.getAttribute(HEAD), "closed", "строка — над первой свёрткой");
  assert.equal(bar.nextElementSibling?.nextElementSibling, two.n.a);
  two.loaded.api.dispose();
  assert.equal(bars(two.loaded).length, 0);
});

test("#11239: свёрнутый длинный ответ — «Развернуть всё» показывает его целиком, без сводки (нет повтора)", () => {
  const { loaded, n, click } = page({ height: 1700, build: box => ({
    first: box.add("p", { text: "Сначала главное." }),
    a: box.add("p", { text: "<details><summary>Первая</summary>" }),
    b: box.add("p", { text: "тело первой" }),
    c: box.add("p", { text: "</details>" }),
    d: box.add("p", { text: "<details><summary>Вторая</summary>" }),
    e: box.add("p", { text: "тело второй" }),
    f: box.add("p", { text: "</details>" }),
    last: box.add("p", { text: "Конец." }),
  }) });
  const whole = loaded.dom.queryAll(`[${WHOLE}]`)[0];
  assert.ok(whole);
  click(whole);
  assert.equal(whole.getAttribute(WHOLE), "closed");
  assert.equal(n.last.getAttribute(LONG), "closed");
  const { bar, open } = buttons(loaded);
  assert.equal(bar.nextElementSibling, n.first, "строка — над первым абзацем, не под свёрнутым");
  assert.equal(open.getAttribute("aria-disabled"), "false");
  click(open);
  assert.equal(whole.getAttribute(WHOLE), "open");
  for (const node of [n.b, n.e, n.last]) assert.equal(node.hasAttribute(LONG), false);
  assert.equal(n.b.getAttribute(BODY), "open");
  assert.equal(n.e.getAttribute(BODY), "open");
  assert.equal(loaded.dom.queryAll("[data-myclaude-asum]").length, 0, "сводки Пимпа нет — текст не повторяется");
});
