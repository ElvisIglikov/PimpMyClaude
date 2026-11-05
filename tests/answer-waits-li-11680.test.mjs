// #11680 (страница, раздел 12ф³): копия «Ждёт тебя» над свёрнутым ответом. Claude кладёт `</details>` раздела
// строкой последнего пункта плотного списка — `<li>пункт<br></details></li>` (край #11651 у пункта, 540-folds).
// answerWaitsOf шёл только по целым абзацам-тегам: раздел не закрывался, и в копию утекали пункты следующего раздела,
// а строка «</details>» оставалась в тексте пункта.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const HEAD = "data-myclaude-fold-head";

const page = build => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_waits-li-11680", title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({ text: "" });
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: { left: 0, top: 0, width: 1200, height: 500 } });
      const row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" }, rect: { left: 0, top: 0, width: 800, height: 300 } });
      parts.box = row.add("div", { class: "prose" });
      // Строки — текстовыми узлами, между ними <br>, как рисует Claude.
      const lines = (parent, tag, ...list) => {
        const node = parent.add(tag);
        list.forEach((line, index) => {
          if (index) node.add("br");
          node.appendChild(dom.document.createTextNode(line));
        });
        return node;
      };
      build(parts.box, lines);
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return loaded;
};
const waitsOf = (loaded, tick) => {
  if (tick) loaded.inner.foldTick();
  const nodes = [...loaded.parts.box.children].filter(node => !node.hasAttribute(HEAD));
  return plain(loaded.inner.answerWaitsOf(nodes));
};
const answer = (box, lines) => {
  lines(box, "p", "Распродажа готова.");
  lines(box, "p", "<details>", "<summary><b>❗ ЖДЁТ ТЕБЯ — 2</b></summary>");
  const ul = box.add("ul");
  lines(ul, "li", "17 · «да» на цену");
  lines(ul, "li", "18 · «да» на отпуск Оли", "</details>");
  lines(box, "p", "<details>", "<summary><b>Что сделано</b></summary>");
  const done = box.add("ul");
  lines(done, "li", "Сайт выложен.");
  lines(done, "li", "Сторис вышла.", "</details>");
};
const WANT = ["❗ ЖДЁТ ТЕБЯ — 2", "17 · «да» на цену", "18 · «да» на отпуск Оли"];

test("#11680: `</details>` раздела «Ждёт тебя» в последнем пункте списка закрывает раздел копии", () => {
  const loaded = page(answer);
  assert.deepEqual(waitsOf(loaded, false), WANT, "до прохода 12ф — по строкам-тегам пункта");
  assert.deepEqual(waitsOf(loaded, true), WANT, "после прохода 12ф (теги краёв спрятаны) — то же");
  loaded.api.dispose();
});

test("#11680: открытие пункта-свёртки строкой-головой абзаца — подпись в копии, тело — нет", () => {
  const loaded = page((box, lines) => {
    lines(box, "p", "<details>", "<summary><b>❗ ЖДЁТ ТЕБЯ — 1</b></summary>");
    lines(box, "p", "<details><summary>19 · Лена — «да» на меню</summary>", "Файл меню на столе.", "</details>");
    lines(box, "p", "</details>");
    lines(box, "p", "Дальше делаю я.");
  });
  assert.deepEqual(waitsOf(loaded, false), ["❗ ЖДЁТ ТЕБЯ — 1", "19 · Лена — «да» на меню"]);
  loaded.api.dispose();
});
