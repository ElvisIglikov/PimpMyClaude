// #11651 (страница, раздел 12ф): `</details>` сразу после списка, цитаты или текста Claude кладёт в тот же абзац
// строкой — `<p>пункт<br></details></p>` (проба 05.11, docs/probe-11651/README.md). Свёртка встаёт и так: строки-теги
// в начале и в конце абзаца — теги на уровне хозяина (абзац, или список/цитата, где он последний), их <br> спрятан
// меткой, текст — пустым nodeValue с возвратом. Без пары в законченном ответе — не трогаем.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const HEAD = "data-myclaude-fold-head";
const LABEL = "data-myclaude-fold-label";
const RAW = "data-myclaude-fold-raw";
const BODY = "data-myclaude-fold-body";
const WHOLE = "data-myclaude-fold-whole";
const ALL = "data-myclaude-fold-all";

const page = ({ build, streaming = false } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_fold-11651", title: "Rick",
    html: dom => {
      const parts = dom.composer({ text: "" });
      const feed = dom.document.body.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript" },
        rect: { left: 0, top: 0, width: 1200, height: 500 },
      });
      const row = feed.add("div", {
        attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text", ...(streaming ? { "data-is-streaming": "true" } : {}) },
        rect: { left: 0, top: 0, width: 800, height: 300 },
      });
      parts.box = row.add("div", { class: "contents" });
      // Абзац, как его рисует Claude: строки — текстовыми узлами, между ними <br>.
      const para = (parent, ...lines) => {
        const p = parent.add("p");
        lines.forEach((line, index) => {
          if (index) p.add("br");
          p.appendChild(dom.document.createTextNode(line));
        });
        return p;
      };
      parts.nodes = build(parts.box, para) ?? {};
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.inner.foldTick();
  const click = node => loaded.dom.document.dispatchEvent({ type: "click", target: node, detail: 1, isTrusted: true });
  return { loaded, box: loaded.parts.box, n: loaded.parts.nodes, click, tick: () => loaded.inner.foldTick() };
};
const heads = loaded => loaded.dom.queryAll(`[${HEAD}]:not([${WHOLE}])`);
const kids = parent => [...parent.childNodes].filter(node => node.nodeType === 1);
const texts = p => [...p.childNodes].filter(node => node.nodeType === 3);
const brs = p => [...p.childNodes].filter(node => node.tagName === "BR");
// Снимок разметки: порядок узлов, их метки и текст — второй проход не должен менять ничего.
const shot = box => {
  const out = [];
  const walk = node => {
    if (node.nodeType === 3) { out.push(`#${node.nodeValue}`); return; }
    out.push(`<${node.tagName} ${[RAW, BODY, HEAD, LABEL].map(name => node.getAttribute(name)).join("|")}>`);
    for (const kid of node.childNodes) walk(kid);
    out.push(`</${node.tagName}>`);
  };
  walk(box);
  return out.join("");
};

const listFold = (box, para) => ({
  open: para(box, "<details>", "<summary>Список</summary>"),
  ul: (() => {
    const ul = box.add("ul");
    para(ul.add("li"), "пункт 1");
    return ul;
  })(),
  after: para(box, "после"),
});

test("#11651: </details> строкой в последнем пункте списка — свёртка вокруг всего списка, тег спрятан", () => {
  const { loaded, box, n, click, tick } = page({
    build: (box, para) => {
      const parts = listFold(box, para);
      parts.last = para(parts.ul.add("li"), "пункт 2", "</details>");
      return parts;
    },
  });
  const list = heads(loaded);
  assert.equal(list.length, 1);
  assert.equal(list[0].nextElementSibling, n.open, "голова — перед сырым <p> открытия");
  assert.equal(list[0].getAttribute(LABEL), "▸ Список");
  assert.equal(n.ul.getAttribute(BODY), "closed", "тело — весь список");
  assert.equal(n.after.hasAttribute(BODY), false, "после </details> — вне свёртки");
  const [item, tag] = texts(n.last);
  assert.equal(item.nodeValue, "пункт 2");
  assert.equal(tag.nodeValue, "", "текст тега спрятан");
  assert.equal(brs(n.last)[0].getAttribute(RAW), "", "перевод строки перед тегом спрятан");
  const before = shot(box);
  tick();
  assert.equal(shot(box), before, "второй проход ничего не меняет");
  click(list[0]);
  assert.equal(n.ul.getAttribute(BODY), "open");
  assert.equal(tag.nodeValue, "", "раскрытая — тег всё равно спрятан");
  // React вернул текст (перерисовка) — снова спрятан.
  tag.nodeValue = "</details>";
  tick();
  assert.equal(tag.nodeValue, "");
  assert.equal(n.ul.getAttribute(BODY), "open", "выбор Элвиса держится");
  loaded.api.dispose();
  assert.equal(tag.nodeValue, "</details>", "dispose возвращает текст");
  assert.equal(brs(n.last)[0].hasAttribute(RAW), false);
  assert.equal(heads(loaded).length, 0);
});

test("#11651: </details> строкой в цитате и в абзаце", () => {
  for (const shape of ["blockquote", "p"]) {
    const { loaded, n } = page({
      build: (box, para) => {
        const open = para(box, "<details>", "<summary>Цитата</summary>");
        const quote = shape === "blockquote" ? box.add("blockquote") : null;
        const last = para(quote ?? box, "текст", "</details>");
        const after = para(box, "после");
        return { open, owner: quote ?? last, last, after };
      },
    });
    assert.equal(heads(loaded).length, 1, shape);
    assert.equal(n.owner.getAttribute(BODY), "closed", shape);
    assert.equal(n.after.hasAttribute(BODY), false, shape);
    assert.equal(texts(n.last)[1].nodeValue, "", shape);
    assert.equal(texts(n.last)[0].nodeValue, "текст", shape);
    assert.equal(n.last.hasAttribute(RAW), false, `${shape}: сам абзац виден`);
  }
});

test("#11651: хвост `</details>⏎<details>⏎<summary>F</summary>` в пункте — закрыть одну и открыть следующую", () => {
  const { loaded, box, n, tick } = page({
    build: (box, para) => {
      const open = para(box, "<details>", "<summary>A</summary>");
      const ul = box.add("ul");
      const last = para(ul.add("li"), "пункт", "</details>", "<details>", "<summary>F</summary>");
      const bodyF = para(box, "тело F");
      const close = para(box, "</details>");
      const after = para(box, "после");
      return { open, ul, last, bodyF, close, after };
    },
  });
  const list = heads(loaded);
  assert.equal(list.length, 2);
  const [a, f] = [list.find(head => head.getAttribute(LABEL) === "▸ A"), list.find(head => head.getAttribute(LABEL) === "▸ F")];
  assert.ok(a && f, list.map(head => head.getAttribute(LABEL)).join(","));
  assert.equal(a.nextElementSibling, n.open);
  assert.equal(n.ul.nextElementSibling, f, "голова F — сразу после списка");
  assert.equal(f.nextElementSibling, n.bodyF);
  assert.equal(n.ul.getAttribute(BODY), "closed");
  assert.equal(n.bodyF.getAttribute(BODY), "closed");
  assert.equal(n.close.getAttribute(RAW), "");
  assert.equal(n.after.hasAttribute(BODY), false);
  assert.deepEqual(texts(n.last).map(node => node.nodeValue), ["пункт", "", "", ""]);
  assert.ok(brs(n.last).every(br => br.getAttribute(RAW) === ""));
  const before = shot(box);
  tick();
  tick();
  assert.equal(shot(box), before, "проходы стабильны");
  // Две свёртки — строки «Развернуть / Свернуть» сверху и снизу.
  assert.equal(loaded.dom.queryAll(`[${ALL}="bar"]`).length, 2);
});

test("#11651: голова `<details>⏎<summary>A</summary>⏎текст` — свёртка с этого абзаца", () => {
  const { loaded, n, tick, box } = page({
    build: (box, para) => {
      const lead = para(box, "Вступление");
      const first = para(box, "<details>", "<summary>A</summary>", "текст");
      const more = para(box, "ещё");
      const close = para(box, "</details>");
      return { lead, first, more, close };
    },
  });
  const list = heads(loaded);
  assert.equal(list.length, 1);
  assert.equal(list[0].nextElementSibling, n.first, "голова — перед абзацем");
  assert.equal(list[0].getAttribute(LABEL), "▸ A");
  assert.equal(n.first.getAttribute(BODY), "closed");
  assert.equal(n.more.getAttribute(BODY), "closed");
  assert.equal(n.lead.hasAttribute(BODY), false);
  assert.deepEqual(texts(n.first).map(node => node.nodeValue), ["", "", "текст"]);
  assert.deepEqual(brs(n.first).map(br => br.getAttribute(RAW)), ["", ""]);
  const before = shot(box);
  tick();
  assert.equal(shot(box), before);
});

test("#11651: без пары в законченном ответе и `<details>` в коде — не трогаем", () => {
  const { loaded, n } = page({
    build: (box, para) => {
      const lonely = para(box, "текст", "</details>");
      para(box, "<details>", "<summary>Код</summary>");
      const coded = para(box, "текст", "");
      coded.add("code", { text: "</details>" });
      return { lonely, coded };
    },
  });
  assert.equal(heads(loaded).length, 0);
  assert.equal(texts(n.lonely)[1].nodeValue, "</details>");
  assert.equal(brs(n.lonely)[0].hasAttribute(RAW), false);
  assert.equal(loaded.inner.foldEdges(n.lonely).tail.length, 1, "край прочитан, но пары нет");
  assert.equal(loaded.inner.foldEdges(n.coded), null, "`</details>` в коде — не тег");
});

test("#11651: вложенные открытия строками одного абзаца — внешняя голова перед внутренней", () => {
  const { loaded, n, tick, box } = page({
    build: (box, para) => {
      const lead = para(box, "текст", "<details>", "<summary>Внешняя</summary>", "<details>", "<summary>Внутренняя</summary>");
      const body = para(box, "тело");
      const inner = para(box, "</details>");
      const outer = para(box, "</details>");
      return { lead, body, inner, outer };
    },
  });
  const list = heads(loaded);
  assert.equal(list.length, 2);
  assert.equal(n.lead.nextElementSibling.getAttribute(LABEL), "▸ Внешняя");
  assert.equal(n.lead.nextElementSibling.nextElementSibling.getAttribute(LABEL), "▸ Внутренняя");
  assert.equal(n.lead.nextElementSibling.nextElementSibling.nextElementSibling, n.body);
  const innerHead = list.find(head => head.getAttribute(LABEL) === "▸ Внутренняя");
  assert.equal(innerHead.getAttribute(BODY), "closed", "закрытая внешняя прячет голову внутренней");
  assert.equal(n.lead.hasAttribute(BODY), false);
  const before = shot(box);
  tick();
  assert.equal(shot(box), before);
});

test("#11651: абзац из одних строк-тегов — спрятан целиком, текст не тронут", () => {
  const { loaded, n } = page({
    build: (box, para) => {
      const open = para(box, "<details>", "<summary>A</summary>");
      const bodyA = para(box, "тело A");
      const middle = para(box, "</details>", "<details>", "<summary>B</summary>");
      const bodyB = para(box, "тело B");
      const close = para(box, "</details>");
      return { open, bodyA, middle, bodyB, close };
    },
  });
  const list = heads(loaded);
  assert.equal(list.length, 2);
  assert.equal(n.middle.getAttribute(RAW), "");
  assert.deepEqual(texts(n.middle).map(node => node.nodeValue), ["</details>", "<details>", "<summary>B</summary>"]);
  assert.equal(n.bodyA.getAttribute(BODY), "closed");
  assert.equal(n.bodyB.getAttribute(BODY), "closed");
  const b = list.find(head => head.getAttribute(LABEL) === "▸ B");
  assert.equal(b.nextElementSibling, n.bodyB);
});

test("#11651: ответ пишется — открытие строкой в конце встаёт без пары и не качается с нижней строкой", () => {
  const { loaded, n, tick, box } = page({
    streaming: true,
    build: (box, para) => {
      para(box, "<details>", "<summary>A</summary>");
      para(box, "тело A");
      para(box, "</details>");
      const last = para(box, "текст", "<details>", "<summary>B</summary>");
      return { last };
    },
  });
  assert.equal(heads(loaded).length, 2);
  const b = heads(loaded).find(head => head.getAttribute(LABEL) === "▸ B");
  assert.equal(n.last.nextElementSibling, b);
  const before = shot(box);
  tick();
  tick();
  assert.equal(shot(box), before, "голова B и нижняя строка не меняются местами");
  assert.equal(box.lastElementChild.hasAttribute("data-myclaude-fold-all-end"), true);
});
