// WF298, #11175: относительная markdown-ссылка на файл проекта в ответе Claude (`[отчёт](docs/12.html)`) открывается
// как абсолютная — путь = папка чата (cwd сессии строки списка слева) + относительный; http(s), #якорь, ?запрос,
// mailto — Claude, как раньше; папки чата нет — тоже Claude (не перехватываем).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const CHAT = "local_0f3a9c1e-7b2d-4e6f-8a1b-5c4d3e2f1a0b";
const CWD = "/Users/dev/Projects/PimpMyClaude";
const flush = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };

const scene = ({ cwd = CWD, links = [] } = {}) => {
  const calls = [];
  const nodes = {};
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`,
    geometry: { viewport: { width: 811, height: 470 }, frame: [0, 29, 1067, 618] },
    html: dom => {
      const body = dom.document.body;
      if (cwd !== null) {
        const row = body.add("div", { attrs: { "data-testid": "sidebar" } }).add("div", { attrs: { "data-row-key": `code:${CHAT}` } });
        row.__reactFiber$test = { memoizedProps: { session: { ref: { kind: "code", id: CHAT }, title: "Claude",
          source: { kind: "code", data: { cwd } } } }, return: null };
      }
      const prose = body.add("div", { attrs: { "data-testid": "transcript-row" } }).add("div", { class: "prose" }).add("p");
      nodes.links = links.map(href => prose.add("a", { attrs: { href }, text: href }));
      dom.window.fetch = address => {
        const url = String(address);
        calls.push(url);
        // PimpViewer не жив: панели нет, страницы и PDF — прежним путём (open-html mode=click).
        const answer = url.includes("/dock?") ? { ok: true, viewer: "down" } : url.includes("/open-html?") ? { taken: true, opened: true } : {};
        return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(answer), text: () => Promise.resolve("") });
      };
      return {};
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return Object.assign(loaded, { calls, nodes });
};
const click = (loaded, target) => loaded.document.dispatchEvent({ type: "click", isTrusted: true, target, button: 0, detail: 1 });
const opened = loaded => loaded.calls.filter(url => url.includes("/open-html?")).map(url => new URL(url).searchParams.get("path"));

test("#11175: относительная ссылка — от папки чата, как абсолютная (docs/, ./, ../, %XX)", async () => {
  const loaded = scene({ links: ["docs/12.html", "./docs/13.html", "../Other/отчёт.pdf", `docs/${encodeURIComponent("план работ.html")}`, "/tmp/abs.html"] });
  await flush();
  for (const node of loaded.nodes.links) assert.equal(click(loaded, node), false, `${node.getAttribute("href")} ушёл Claude`);
  assert.deepEqual(opened(loaded), [`${CWD}/docs/12.html`, `${CWD}/docs/13.html`, "/Users/dev/Projects/Other/отчёт.pdf",
    `${CWD}/docs/план работ.html`, "/tmp/abs.html"]);
  // Нажатие (pointerdown) тоже глушится — меню Claude на ссылке не открывается.
  assert.equal(loaded.document.dispatchEvent({ type: "pointerdown", isTrusted: true, target: loaded.nodes.links[0], button: 0, detail: 1 }), false);
});

test("#11175: http(s) — не файлом (12д³, #11118); #якорь, ?запрос, mailto — Claude, как раньше", async () => {
  const loaded = scene({ links: ["https://example.com/a.html", "http://example.com/b.pdf", "#раздел", "?x=1.html", "mailto:a@b.c"] });
  await flush();
  // С #11118 http(s) ленты берёт раздел 12д³ (браузер системы через window.open) — не файлом, /open-html нет.
  for (const node of loaded.nodes.links) {
    const web = /^https?:/.test(node.getAttribute("href"));
    for (const type of ["pointerdown", "click"]) {
      assert.equal(loaded.document.dispatchEvent({ type, isTrusted: true, target: node, button: 0, detail: 1 }), !web,
        `${type} по ${node.getAttribute("href")}: ${web ? "не у 12д³" : "перехвачен"}`);
    }
  }
  assert.deepEqual(opened(loaded), []);
});

test("#11175: папки чата нет — относительную не перехватываем (идёт Claude, как раньше); абсолютная — наша", async () => {
  const loaded = scene({ cwd: null, links: ["docs/12.html", "/tmp/abs.html"] });
  await flush();
  assert.equal(click(loaded, loaded.nodes.links[0]), true, "без cwd относительная — Claude");
  assert.equal(click(loaded, loaded.nodes.links[1]), false);
  assert.deepEqual(opened(loaded), ["/tmp/abs.html"]);
});
