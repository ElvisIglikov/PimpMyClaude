// WF297, батч C (страница).
// #11173: с Claude 4.29 микрофон Claude стоит не в нижней строке поля ([data-cds="ChatComposerChin"]), а рядом
// с отправкой — [data-testid="code-prompt-trailing-controls"] в верхней коробке поля [data-cds="ChatComposer"]
// (живой замер probe.js 29.10.2026). Прятание раздела 12з¹ искало его только в строке — микрофон Claude был виден
// вторым рядом с нашим. Теперь ищется во всём поле и прячется той же меткой "hide" (узел жив — его жмёт наш микрофон).
// #11174: подпись под свёрнутым своим сообщением объясняет себя — «кратко от Пимпа» (суть нейронки Пимпа) или
// «начало сообщения» (первые предложения), а не одно слово «суть»/«начало».
import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { loadInject } from "./load.mjs";

// Поле как на живом Claude 4.29: верхняя коробка «+ … [отправка][микрофон]», под ней строка «Bypass · Opus · ◑».
const stand = dom => {
  const parts = dom.composer({ top: 600 });
  parts.block.setAttribute("data-cds", "ChatComposer");
  const trailing = parts.shell.add("div", { attrs: { "data-testid": "code-prompt-trailing-controls" } });
  trailing.add("div", { attrs: { "data-testid": "code-prompt-send-cell" } });
  const micShell = trailing.add("span", { class: "inline-flex" });
  const mic = micShell.add("button", { attrs: { "aria-label": "Press and hold to record" } });
  mic.add("svg");
  trailing.add("span");
  const chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" } });
  const mode = chin.add("button", { attrs: { "aria-haspopup": "menu" } });
  dom.leaf(mode, "span", "Bypass permissions");
  const model = chin.add("button", { attrs: { "data-testid": "epitaxy-cds-model-selector", "aria-label": "Model: Opus 5.5", "aria-haspopup": "menu" } });
  dom.leaf(model, "span", "Opus 5.5");
  return { ...parts, trailing, micShell, mic, chin, mode };
};
const mark = node => node.getAttribute("data-myclaude-chin");
// Стиль страницы целиком: RULES раздела 4 и lateRules новых фич.
const css = loaded => loaded.dom.queryAll("style").map(node => node.textContent).join("\n");

test("#11173: микрофон Claude у отправки (вне нижней строки) спрятан меткой, узел жив; dispose снимает", () => {
  const loaded = loadInject({ title: "Rick", html: stand, geometry: { viewport: { width: 900, height: 800 } } });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const { micShell, mic, trailing, mode } = loaded.parts;
  assert.equal(mark(micShell), "hide", "обёртка микрофона у отправки — «hide»");
  assert.equal(mark(trailing), null, "соседи по группе отправки не тронуты");
  assert.equal(mark(mode), "text", "строка под полем размечается как раньше");
  assert.ok(mic.isConnected, "кнопка в разметке — её жмёт наш микрофон в режиме «claude»");
  loaded.api.dispose();
  assert.equal(micShell.hasAttribute("data-myclaude-chin"), false);
});

test("#11173: правило прячет метку «hide» во всём поле, а не только в нижней строке", () => {
  const loaded = loadInject({ title: "Rick", html: stand, geometry: { viewport: { width: 900, height: 800 } } });
  const text = css(loaded);
  assert.match(text, /\[data-cds="ChatComposer"\] \[data-myclaude-chin="hide"\]\{display:none !important\}/);
  assert.match(text, /\[data-cds="ChatComposerChin"\] \[data-myclaude-chin="hide"\]\{display:none !important\}/, "прежнее правило строки на месте");
});

// #11174: свёрнутое длинное сообщение — суть из кэша (нейронка Пимпа) и без кэша (первые предложения).
const LONG = Array.from({ length: 10 }, (_, i) => `Строка ${i + 1} длинного сообщения.`);
const sha1 = text => createHash("sha1").update(text, "utf8").digest("hex");
const page = local => loadInject({
  href: "https://claude.ai/epitaxy/local_wf297-c", title: "Rick", storage: { local },
  html: dom => {
    const parts = dom.composer({ text: "" });
    const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } });
    const row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "human" } });
    const card = row.add("div", { attrs: { "data-cds": "UserMessage" } });
    const body = card.add("div", { class: "cds-user-message-body" });
    const message = body.add("div", { attrs: { "data-testid": "user-message" } });
    for (const text of LONG) message.add("p", { text });
    return { ...parts, message };
  },
});
const kindOf = loaded => loaded.parts.message.nextSibling?.querySelector("[data-myclaude-ufold-bar]")?.getAttribute("data-myclaude-ufold-kind");

test("#11174: подпись свёрнутого своего сообщения — «кратко от Пимпа» для сути нейронки, «начало сообщения» без неё", () => {
  const lead = page({});
  assert.equal(lead.error, null, String(lead.error?.stack ?? lead.error));
  assert.equal(kindOf(lead), "начало сообщения", "Пимпа нет — видно начало текста, так и подписано");
  const hash = sha1(LONG.join("\n"));
  const ai = page({ "myclaude-ufold-v1": JSON.stringify({ v: 1, items: { [hash]: { s: "Суть от нейронки.", at: 1 } } }) });
  assert.equal(kindOf(ai), "кратко от Пимпа", "суть нейронки — подписано, чья она");
  assert.match(css(ai), /\[data-myclaude-ufold-bar\]\[data-myclaude-ufold-kind\]::before\{content:attr\(data-myclaude-ufold-kind\) " · "/, "подпись — из атрибута, копия текста её не берёт");
});
