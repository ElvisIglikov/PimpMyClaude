// WF183 (слова Элвиса 09.10 03:05–03:35): нижняя строка поля и Enter.
//   — «Справа слишком большой отступ — Enter не сходится: центр кружка отправки и Enter на одной вертикали…
//     Когда прижал окно к правому краю — Enter должен быть правее, центр ровно над кружочком»: кнопка отправки
//     (или «Стоп») сдвигается translate так, что её середина — над серединой кружка токенов строки под ней;
//   — «Галерея: сначала цифра, потом значок; значок сильно яркий — линии не заполненные, а пустые».
// Полоса Рика (шеврон, «В работе · Сделано · Всё · Отчёт», короткие имена) — rick-cells-wf134.test.mjs;
// подписи «Bp/Ex», цвет строки — chin.test.mjs; пол колонки — layout.test.mjs.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const CHAT = "local_wf183-0001";
let seq = 0;
const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
// Поле 100..1100; Enter 1060..1084 × 660..684 над строкой модели; кружок токенов 1066..1086 × 694..714.
const page = ({ ring = { left: 1066, top: 694, width: 20, height: 20 }, sendTestid = "code-prompt-send" } = {}) => {
  const loaded = loadInject({
    title: "Trelvis", href: `https://claude.ai/epitaxy/${CHAT}`,
    html: dom => {
      const parts = dom.composer({ top: 600 });
      parts.chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: { left: 92, top: 690, width: 1016, height: 28 } });
      const row = parts.chin.add("div", { class: "flex items-center", rect: { left: 100, top: 694, width: 1000, height: 20 } });
      parts.left = row.add("div", { class: "flex items-center self-start", rect: { left: 100, top: 696, width: 60, height: 16 } });
      parts.left.add("button", { attrs: { "aria-label": "Add" }, rect: { left: 100, top: 696, width: 20, height: 16 } });
      const right = row.add("div", { class: "ms-auto flex items-center", rect: { left: 960, top: 694, width: 130, height: 20 } });
      right.add("button", { attrs: { "data-testid": "epitaxy-cds-model-selector" }, text: "Opus 5.5", rect: { left: 960, top: 696, width: 60, height: 16 } });
      parts.ring = ring ? right.add("button", { attrs: { "aria-haspopup": "dialog", "aria-label": "Usage: Context 300k / 1M (30%)" }, rect: ring }) : null;
      parts.send = parts.block.add("button", { attrs: { "data-testid": sendTestid }, rect: { left: 1060, top: 660, width: 24, height: 24 } });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.win.fetch = () => Promise.resolve({});
  settle(loaded);
  return loaded;
};
const mid = node => { const box = node.getBoundingClientRect(); return (box.left + box.right) / 2; };

test("WF183: Enter — ровно над кружком токенов (одна вертикаль), сдвиг стоит на месте, следует за кружком", () => {
  const loaded = page();
  const { send, ring } = loaded.parts;
  assert.equal(send.style.getPropertyValue("translate"), "4px 0px", "Enter не сдвинут к кружку");
  assert.equal(mid(send), mid(ring), "центр Enter не над центром кружка");
  // Повторные проходы — сдвиг не копится.
  settle(loaded); settle(loaded);
  assert.equal(mid(send), mid(ring));
  assert.equal(send.style.getPropertyValue("translate"), "4px 0px");
  // Кружок левее (строка ужалась) — Enter за ним.
  ring.rect = { ...ring.rect, left: 1058 };
  settle(loaded);
  assert.equal(send.style.getPropertyValue("translate"), "-4px 0px");
  assert.equal(mid(send), mid(ring));
  // Кружок под Enter ровно — сдвига нет вовсе.
  ring.rect = { ...ring.rect, left: 1062 };
  settle(loaded);
  assert.equal(send.style.getPropertyValue("translate"), "");
  // Кружок далеко (другая строка) или пропал — Enter на своём месте.
  ring.rect = { ...ring.rect, left: 600 };
  settle(loaded);
  assert.equal(send.style.getPropertyValue("translate"), "");
  ring.rect = { ...ring.rect, left: 1070 };
  settle(loaded);
  assert.equal(mid(send), mid(ring));
  ring.remove();
  settle(loaded);
  assert.equal(send.style.getPropertyValue("translate"), "", "кружка нет — сдвиг остался");
});

test("WF183: «Стоп» на месте Enter — тоже над кружком; кружок в той же строке (широкое поле) — не трогаем; dispose снимает", () => {
  const stop = page({ sendTestid: "code-prompt-stop" });
  assert.equal(mid(stop.parts.send), mid(stop.parts.ring));
  const inline = page({ ring: { left: 1090, top: 662, width: 20, height: 20 } });
  assert.equal(inline.parts.send.style.getPropertyValue("translate"), "", "кружок рядом в строке — Enter сдвинут");
  const loaded = page();
  assert.notEqual(loaded.parts.send.style.getPropertyValue("translate"), "");
  loaded.api.dispose();
  assert.equal(loaded.parts.send.style.getPropertyValue("translate"), "", "dispose не снял сдвиг");
});

test("WF183: «Галерея» — сначала число, потом значок; квадраты контуром, без заливки; в строке значок тише числа", () => {
  const loaded = page();
  loaded.dom.command({ id: `c-${seq += 1}`, action: "viewer-counts", at: "now", scope: "all", chats: { [CHAT]: [7, 0] } });
  settle(loaded);
  const node = loaded.dom.query("#myclaude-gallery");
  const kids = [...node.childNodes].filter(kid => kid.nodeType === 1).map(kid => kid.tagName.toLowerCase());
  assert.deepEqual(kids, ["i", "svg"], "число не первым");
  assert.equal(node.textContent.trim(), "7");
  const svg = node.querySelector("svg");
  assert.equal(svg.getAttribute("fill"), "none", "значок залит");
  assert.equal(svg.getAttribute("stroke"), "currentColor");
  assert.equal(svg.querySelectorAll("rect").length, 4);
  const css = [...loaded.inner.RULES].join("\n");
  assert.ok(css.includes('#myclaude-gallery[data-spot="field"]>svg{opacity:.7}'), "значок в строке такой же яркий");
});
