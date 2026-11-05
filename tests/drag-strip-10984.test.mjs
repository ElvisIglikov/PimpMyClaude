// #10984 (страница, раздел 2ж¹, файл page/125-drag-strip.js): окно таскается за всю верхнюю полосу.
// Слово Элвиса 29.10.2026: «у пимпа вот там сверху не за что ухватиться… Слева, где закрыть, открыть, там можно
// ухватиться. А где-то посередине сверху… вообще не хватается». Причина — сам Пимп: у главного окна без шапки (2ж,
// #7913) таскать можно было только полосу 76×40 под кнопками окна.
//
// Что проверяется:
//   1) главное окно, список чатов свёрнут — полоса стоит: первым узлом body, метка «вкл», CSS — drag во всю ширину
//      правее кнопки «Show sidebar» (left 120), высота 28;
//   2) список чатов открыт (полосы под кнопками нет) и попап — полосы нет;
//   3) пропала из body — вернулась на следующем проходе, одна; dispose — ушла.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const STRIP = "[data-myclaude-drag-strip]";
const ON = "data-myclaude-drag-strip-on";

const stand = ({ href = "https://claude.ai/epitaxy/local_abc", width = 852, panelLeft = 9 } = {}) => {
  const loaded = loadInject({
    href, title: "🧪 Рик",
    geometry: { viewport: { width, height: 720 } },
    html: dom => {
      const parts = dom.composer({ top: 560 });
      const panel = dom.document.body.add("div", {
        class: "epitaxy-chat-panel", rect: { left: panelLeft, top: 9, width: width - panelLeft - 1, height: 702 },
      });
      const titlebar = panel.add("div", { class: "epitaxy-titlebar", rect: { left: 77, top: 9, width: 158, height: 32 } });
      titlebar.add("div", { class: "group/lead" }).add("span").add("span", { attrs: { "data-pane-title": "" }, text: "🧪 Рик", rect: { left: 105, top: 13, width: 40, height: 24 } });
      const tail = panel.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript" },
        rect: { left: panelLeft, top: 9, width: width - panelLeft - 1, height: 560 },
      });
      return { ...parts, panel, tail };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return loaded;
};
const pass = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const strip = loaded => loaded.dom.queryAll(STRIP);

test("#10984: главное окно, список чатов свёрнут — полоса во всю ширину, первая в body", () => {
  const loaded = stand();
  pass(loaded);
  assert.equal(loaded.api.status().head.drag, true, "полоса под кнопками окна стоит");
  assert.equal(strip(loaded).length, 1);
  const node = strip(loaded)[0];
  assert.equal(node.hasAttribute(ON), true);
  assert.equal(node.id, "", "без id — слой, нажатий нет");
  assert.equal(loaded.document.body.firstChild, node, "первой в body: поздние no-drag кнопок вырезают её");
  assert.deepEqual(plain(loaded.api.status().dragStrip), { on: true, first: true });
  const css = loaded.dom.query("#myclaude-input-handle-style").textContent;
  const rule = css.split("}").find(chunk => chunk.includes(`${STRIP}{`));
  assert.ok(rule, "правила полосы нет");
  assert.match(rule, /position:fixed/);
  assert.match(rule, /display:none/);
  assert.match(rule, /top:0/);
  assert.match(rule, /left:120px/, "правее «Show sidebar» (82–110)");
  assert.match(rule, /right:0/);
  assert.match(rule, /height:28px/);
  assert.match(rule, /-webkit-app-region:drag/);
  assert.ok(css.includes(`${STRIP}[${ON}]{display:block}`));
  // Ещё проход — тот же узел, не дубль.
  pass(loaded);
  assert.equal(strip(loaded).length, 1);
  assert.equal(strip(loaded)[0], node);
  loaded.api.dispose();
});

test("#10984: список чатов открыт — полоса стоит (слово 03.11.2026), у попапа её нет", () => {
  const loaded = stand();
  pass(loaded);
  assert.equal(strip(loaded)[0].hasAttribute(ON), true);
  loaded.parts.panel.rect = { ...loaded.parts.panel.rect, left: 200 };
  loaded.parts.tail.rect = { ...loaded.parts.tail.rect, left: 200 };
  pass(loaded);
  assert.equal(loaded.api.status().head.drag, false);
  assert.equal(strip(loaded)[0].hasAttribute(ON), true, "между боковой колонкой и чатом у Claude только 8 px");
  assert.deepEqual(plain(loaded.api.status().dragStrip), { on: true, first: true });
  loaded.api.dispose();
  const popup = stand({ href: "about:blank", width: 282 });
  pass(popup);
  assert.equal(popup.api.status().head.drag, false);
  assert.equal(strip(popup).length, 0, "попап — узла нет вовсе");
  popup.api.dispose();
});

test("#10984: пропала из body — вернулась одна; dispose — ушла", () => {
  const loaded = stand();
  pass(loaded);
  const node = strip(loaded)[0];
  node.remove();
  assert.equal(strip(loaded).length, 0);
  pass(loaded);
  assert.equal(strip(loaded).length, 1);
  assert.equal(loaded.document.body.firstChild, strip(loaded)[0]);
  loaded.api.dispose();
  assert.equal(strip(loaded).length, 0);
});
