// #10904 (page/545-user-fold.js, раздел 12ф²): стартовое сообщение нового чата Рика (`pimp.py renew`) начинается
// блоком «Последний ответ Рика тебе (из прежнего чата, ЧЧ:ММ):», дальше ответ дословно, строка «———», ниже —
// служебный текст для нового Рика. Верх виден целиком (без свёртки, без родного обреза 200 px, основным цветом),
// сворачивается только низ — по прежним правилам. Разметка сообщения — как в user-fold-wf262 (Claude 1.40609).
import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { loadInject, plain } from "./load.mjs";

const FOLD = "data-myclaude-ufold";
const SRC = "data-myclaude-ufold-src";
const CLAMP = "data-myclaude-ufold-clamp";
const TEXT = "data-myclaude-ufold-text";
const LABEL = "data-myclaude-ufold-label";
const sha1 = text => createHash("sha1").update(text, "utf8").digest("hex");

const TITLE = "Последний ответ Рика тебе (из прежнего чата, 21:40):";
const ANSWER = ["**✅ Открыл в PimpViewer HTML, где подбирали звук на куске ролика.**", "Звук — все варианты: 40 секунд ролика, 20 вариантов звука."];
const SERVICE = Array.from({ length: 10 }, (_, at) => `Служебное для нового Рика, пункт ${at + 1}: прочитай паспорт, HANDOFF и журнал прежнего чата, продолжай с места.`);

let clampSeq = 0;
const addMessage = (feed, paragraphs) => {
  const row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "human" } });
  const card = row.add("div", { attrs: { "data-cds": "UserMessage" } });
  const bubble = card.add("div", { class: "relative flex text-primary" });
  const id = `_r_last${clampSeq += 1}_`;
  const clamp = bubble.add("div", { id, class: "overflow-hidden" });
  clamp.style.setProperty("max-height", "200px");
  const body = clamp.add("div", { class: "cds-user-message-body" });
  const message = body.add("div", { attrs: { "data-testid": "user-message" } });
  const column = message.add("div", { class: "flex" });
  for (const text of paragraphs) column.add("p", { text });
  const more = bubble.add("button", { attrs: { type: "button", "aria-controls": id, "aria-expanded": "false" }, text: "Show more" });
  return { row, clamp, message, more };
};
const page = (messages, { fetch = null } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_last-10904", title: "Rick",
    html: dom => {
      if (fetch) dom.window.fetch = fetch;
      const parts = dom.composer({ text: "" });
      parts.feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } });
      parts.items = messages.map(list => addMessage(parts.feed, list));
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const click = target => loaded.dom.document.dispatchEvent({ type: "click", target, detail: 1, isTrusted: true });
  return { loaded, items: loaded.parts.items, click };
};
const calls = [];
const pimpDown = (url, options) => { calls.push(JSON.parse(options.body)); return Promise.reject(new TypeError("Failed to fetch")); };

test("#10904: верх — ответ Рика целиком своим узлом, без свёртки и обреза, основным цветом; низ свёрнут", () => {
  calls.length = 0;
  const { loaded, items: [item], click } = page([[TITLE, ...ANSWER, "———", ...SERVICE]], { fetch: pimpDown });
  const head = item.message.nextSibling;
  assert.equal(head?.getAttribute(FOLD), "head", "верх — сразу под сообщением");
  // #11399: верх — вёрсткой ответа (Markdown шва), не сырым текстом: абзацы — <p>, «**…**» — жирный.
  assert.equal(head.hasAttribute("data-myclaude-ufold-md"), true, "верх нарисован вёрсткой ответа");
  assert.deepEqual([...head.querySelectorAll(".prose > p")].map(p => p.textContent), [TITLE, ...ANSWER.map(line => line.replaceAll("**", ""))],
    "дословно, абзацами, без «———» и служебного");
  assert.equal(head.querySelector("strong")?.textContent, "✅ Открыл в PimpViewer HTML, где подбирали звук на куске ролика.");
  const fold = head.nextSibling;
  assert.equal(fold.getAttribute(FOLD), "closed", "низ свёрнут, как раньше");
  assert.equal(fold.querySelector(`[${TEXT}]`).textContent.startsWith("Служебное для нового Рика, пункт 1"), true, "суть — из низа");
  assert.equal(item.message.getAttribute(SRC), "closed", "исходник спрятан — верх не двоится");
  assert.equal(item.clamp.getAttribute(CLAMP), "box", "родной обрез 200 px снят");
  assert.equal(item.more.getAttribute(CLAMP), "button", "«Show more» спрятана");
  assert.deepEqual(plain(calls.map(call => call.hash)), [sha1(SERVICE.join("\n"))], "Пимпа спрашиваем о низе, не о верхе");
  const css = loaded.dom.queryAll("style").map(node => node.textContent).join("\n");
  assert.match(css, /\[data-myclaude-ufold="head"\]\{[^}]*color:var\(--cds-text-primary, currentColor\) !important/, "основной цвет поверх тихого 12ф⁴");
  assert.match(css, /\[data-myclaude-ufold-clamp="box"\]\{max-height:none !important/);
  // Раскрыл — исходник целиком, свой верх уходит; свернул — снова верх и суть.
  click(fold);
  assert.equal(head.getAttribute(FOLD), "head-open");
  assert.equal(item.message.getAttribute(SRC), "open");
  assert.match(css, /\[data-myclaude-ufold="head-open"\]\{display:none\}/);
  click(fold.lastChild);
  assert.equal(head.getAttribute(FOLD), "head");
  assert.equal(fold.getAttribute(FOLD), "closed");
  loaded.api.dispose();
  assert.equal(item.message.nextSibling, null, "dispose убирает свои узлы");
});

test("#10904: короткий низ — не сворачивается: верх и низ видны как есть, нажатие ничего не делает", () => {
  calls.length = 0;
  const { loaded, items: [item], click } = page([[TITLE, ...ANSWER, "———", "Продолжай с места."]], { fetch: pimpDown });
  const head = item.message.nextSibling;
  const rest = head.nextSibling;
  assert.equal(head.getAttribute(FOLD), "head");
  assert.equal(rest.getAttribute(FOLD), "plain");
  assert.equal(rest.querySelector(`[${TEXT}]`).textContent, "Продолжай с места.");
  assert.equal(rest.lastChild.hasAttribute(LABEL), false, "кнопки «Развернуть» нет");
  assert.equal(calls.length, 0, "сути не нужно");
  click(rest);
  assert.equal(rest.getAttribute(FOLD), "plain");
  assert.equal(item.message.getAttribute(SRC), "closed");
  assert.equal(plain(loaded.api.status().userFold).open, 0);
  loaded.api.dispose();
});

test("#10904: длинный верх (до 6000 знаков) — весь, не суть; другие сообщения — как раньше", () => {
  const long = Array.from({ length: 60 }, (_, at) => `Абзац ответа ${at + 1}: всё, что Рик написал Элвису в прежнем чате, дословно и полностью.`);
  const { loaded, items: [last, other, noCut, short] } = page([
    [TITLE, ...long, "———", "Продолжай."],
    ["Обычное длинное сообщение. ———", ...SERVICE],
    [TITLE, ...SERVICE],
    ["Последний ответ Рика тебе (из прежнего чата) — это не то, просто короткая фраза."],
  ]);
  const head = last.message.nextSibling;
  assert.equal(head.getAttribute(FOLD), "head");
  assert.equal(head.querySelectorAll(".prose > p").length, 1 + long.length, "верх не урезан");
  assert.equal(head.textContent.endsWith(long.at(-1)), true, "последний абзац на месте");
  assert.equal(other.message.nextSibling.getAttribute(FOLD), "closed", "не начинается с «Последний ответ» — обычная свёртка");
  assert.equal(other.message.parentNode.querySelector(`[${FOLD}="head"]`), null);
  assert.equal(noCut.message.nextSibling.getAttribute(FOLD), "closed", "нет строки «———» — обычная свёртка целиком");
  assert.equal(short.message.nextSibling, null, "короткое без «———» — не трогается");
  loaded.api.dispose();
});
