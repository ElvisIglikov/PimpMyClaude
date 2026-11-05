// #11680 (страница, раздел 12ф): в плотном списке Claude кладёт текст прямо в пункт, без <p>, и `</details>` после
// списка — строкой этого пункта: `<li>пункт<br></details></li>` (проба окна Рика 05.11). Край #11651 читался только у
// <p> — вложенные «8.4», «8.7» и внешняя «💬 ОТВЕТЫ НА ТВОИ ВОПРОСЫ» оставались сырыми тегами.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const HEAD = "data-myclaude-fold-head";
const LABEL = "data-myclaude-fold-label";
const RAW = "data-myclaude-fold-raw";
const BODY = "data-myclaude-fold-body";
const WHOLE = "data-myclaude-fold-whole";

const page = build => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_fold-11680", title: "Rick",
    html: dom => {
      const parts = dom.composer({ text: "" });
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: { left: 0, top: 0, width: 1200, height: 500 } });
      const row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" }, rect: { left: 0, top: 0, width: 800, height: 300 } });
      parts.box = row.add("div", { class: "contents" });
      // Строки — текстовыми узлами, между ними <br>, как рисует Claude; tag — "p" или "li".
      const lines = (parent, tag, ...list) => {
        const node = parent.add(tag);
        list.forEach((line, index) => {
          if (index) node.add("br");
          node.appendChild(dom.document.createTextNode(line));
        });
        return node;
      };
      parts.nodes = build(parts.box, lines);
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.inner.foldTick();
  return { loaded, n: loaded.parts.nodes, tick: () => loaded.inner.foldTick() };
};
const heads = loaded => loaded.dom.queryAll(`[${HEAD}]:not([${WHOLE}])`);
const texts = node => [...node.childNodes].filter(kid => kid.nodeType === 3);
const label = (loaded, re) => heads(loaded).find(head => re.test(head.getAttribute(LABEL)));

test("#11680: форма ответа Рика — вложенные свёртки, `</details>` в плотном пункте цитаты", () => {
  const { loaded, n, tick } = page((box, lines) => {
    const lead = lines(box, "p", "🎯 Чем занимаемся");
    const outer = lines(box, "p", "<details>", "<summary><b>💬 ОТВЕТЫ НА ТВОИ ВОПРОСЫ — 2</b></summary>");
    const open1 = lines(box, "p", "<details>", "<summary><b>8.1. Ссылка</b> — пока никакую</summary>");
    const quote1 = box.add("blockquote");
    lines(quote1, "p", "Проверить можно сейчас.", "</details>");
    const open4 = lines(box, "p", "<details>", "<summary><b>8.4. Что сделано за ночь</b> — сайт, iiko</summary>");
    const quote4 = box.add("blockquote");
    const ul = quote4.add("ul");
    lines(ul, "li", "Сайт выложен.");
    const last = lines(ul, "li", "Сторис вышла.", "</details>");
    const close = lines(box, "p", "</details>");
    const after = lines(box, "p", "Дальше без тебя.");
    return { lead, outer, open1, quote1, open4, quote4, last, close, after };
  });
  assert.equal(heads(loaded).length, 3, heads(loaded).map(head => head.getAttribute(LABEL)).join(" | "));
  const big = label(loaded, /💬/);
  const h4 = label(loaded, /8\.4/);
  assert.ok(big && h4 && label(loaded, /8\.1/));
  assert.equal(big.nextElementSibling, n.outer);
  assert.equal(h4.nextElementSibling, n.open4);
  for (const raw of [n.outer, n.open1, n.open4, n.close]) assert.equal(raw.getAttribute(RAW), "", "сырые абзацы тегов спрятаны");
  assert.equal(n.quote4.getAttribute(BODY), "closed", "тело 8.4 — цитата со списком");
  assert.equal(h4.getAttribute(BODY), "closed", "внешняя закрыта — прячет и голову вложенной");
  assert.equal(n.after.hasAttribute(BODY), false);
  assert.equal(n.lead.hasAttribute(BODY), false);
  assert.deepEqual(texts(n.last).map(node => node.nodeValue), ["Сторис вышла.", ""], "текст тега в пункте спрятан");
  assert.equal([...n.last.childNodes].find(node => node.tagName === "BR").getAttribute(RAW), "");
  assert.equal(n.last.hasAttribute(RAW), false, "сам пункт виден");
  const before = loaded.dom.queryAll(`[${HEAD}]`).length;
  tick();
  assert.equal(loaded.dom.queryAll(`[${HEAD}]`).length, before, "второй проход стабилен");
  loaded.api.dispose();
  assert.deepEqual(texts(n.last).map(node => node.nodeValue), ["Сторис вышла.", "</details>"], "dispose возвращает текст");
});

test("#11680: плотный пункт без пары — не трогаем", () => {
  const { loaded, n } = page((box, lines) => {
    const ul = box.add("ul");
    const lonely = lines(ul, "li", "пункт", "</details>");
    return { lonely };
  });
  assert.equal(heads(loaded).length, 0);
  assert.equal(texts(n.lonely)[1].nodeValue, "</details>");
  assert.equal(loaded.inner.foldEdges(n.lonely).tail.length, 1, "край пункта прочитан");
});
