// #11680 (раздел 14б, page/695-answer-reveal.js): ответ появляется разом, когда готов. Слово Элвиса 05.11: «чтоб вот
// эти ответы не вот так вот печатались, а разом появлялись… когда он весь готовый, разом показать его». Потолок 4 с
// (#10903) отпускал длинный ответ на середине — дальше он печатался кусками. Теперь растёт — держим, встал — показать.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const HOLD = "data-myclaude-reveal-hold";

const stand = () => {
  const nodes = {};
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_whole-11680", title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({});
      nodes.stop = dom.document.body.add("button", { attrs: { "data-testid": "chat-input-stop" } });
      nodes.feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: { left: 0, top: 0, width: 800, height: 600 } });
      nodes.feed.clientHeight = 600;
      nodes.feed.scrollHeight = 600;
      nodes.rows = nodes.feed.add("div", { attrs: { "data-testid": "transcript-rows" } });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  let clock = 7000000;
  loaded.win.performance.now = () => clock;
  const row = nodes.rows.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant" }, rect: { left: 0, top: 0, width: 800, height: 200 } });
  const message = row.add("div", { attrs: { "data-epitaxy-entry": "A1" } })
    .add("div", { attrs: { "data-cds": "AssistantMessage", "data-is-streaming": "true" } });
  message.add("p", { text: "Начало ответа" });
  return { loaded, nodes, message, at: ms => { clock += ms; }, sync: () => loaded.inner.revealSync(), tick: () => loaded.dom.fireKind("timeout") };
};

test("#11680: длинный ответ растёт 40 с — всё это время не виден ни куском", () => {
  const s = stand();
  s.sync();
  for (let spent = 0; spent < 40000; spent += 500) {
    s.at(500);
    s.message.add("p", { text: "ещё строка" });
    s.sync();
    assert.equal(s.message.hasAttribute(HOLD), true, `растёт — не видно (${spent + 500} мс)`);
  }
  s.loaded.api.dispose();
});

test("#11680: дописан, ход кончился — показан целиком", () => {
  const s = stand();
  s.sync();
  for (let spent = 0; spent < 10000; spent += 500) { s.at(500); s.message.add("p", { text: "строка" }); s.sync(); }
  assert.equal(s.message.hasAttribute(HOLD), true);
  s.message.setAttribute("data-is-streaming", "false");
  s.nodes.stop.remove();
  s.sync();
  assert.equal(s.message.hasAttribute(HOLD), false, "готов — виден разом");
  s.loaded.api.dispose();
});

test("#11680: текст встал посреди хода (команда) — виден, как в #10903", () => {
  const s = stand();
  s.sync();
  s.at(6000);
  s.message.add("p", { text: "последняя строка" });
  s.sync();
  assert.equal(s.message.hasAttribute(HOLD), true);
  s.at(s.loaded.inner.REVEAL_WAIT_MS);
  s.tick();
  assert.equal(s.message.hasAttribute(HOLD), false);
  s.loaded.api.dispose();
});
