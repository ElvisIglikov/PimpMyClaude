// WF302 (#11226, раздел 12ф inject.js). Слово Элвиса 30.10 ~17:45 об «Ответах на твои вопросы»: «пусть он будет
// свёрнутым, но… очень заметным для меня… в самом начале… Крупный очень»; о пунктах «Ждёт тебя»: «чтоб я их мог
// разворачивать… контекста больше, фоток в этих вопросах».
//
// Что проверяется:
//   1) свёртка с подписью на «💬» — голова с меткой «крупная», прочие — без; правило вида есть; status().folds.big
//      (плашка по подписи и «❗ ЖДЁТ ТЕБЯ» крупной — tests/folds-11478.test.mjs);
//   2) ссылка на картинку в теле ОТКРЫТОЙ свёртки — миниатюра (`GET /thumb`, К-TH) рядом последним узлом абзаца;
//      в закрытой — запроса нет; закрыл — миниатюра ушла; ссылка не на картинку — ничего; dispose убирает своё.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_fold-11226";
const HEAD = "data-myclaude-fold-head";
const BIG = "data-myclaude-fold-big";
const PIC = "data-myclaude-fold-pic";
const SHOT = "/Users/demo/Rick/work/4.webp";
const JPEG = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A]);
const wait = () => new Promise(resolve => setImmediate(resolve));
const settle = async () => { for (let i = 0; i < 4; i += 1) await wait(); };

// Ответ Рика по форме ELVIS.md: «💬 Ответы» → «Ждёт тебя» с пунктом-свёрткой, внутри цитата со ссылкой на скрин.
const answer = box => ({
  lead: box.add("p", { text: "Распродажа готова — нужно твоё «да»." }),
  qOpen: box.add("p", { text: "<details>" }),
  qSum: box.add("p", { text: "<summary><b>💬 ОТВЕТЫ НА ТВОИ ВОПРОСЫ — 2</b></summary>" }),
  qBody: box.add("p", { text: "1. Да — адрес подтверждён." }),
  qClose: box.add("p", { text: "</details>" }),
  wait: box.add("h2", { text: "❗ Ждёт тебя 1" }),
  iOpen: box.add("p", { text: "<details>" }),
  iSum: box.add("p", { text: "<summary><b>17 · 🔴 Распродажа 01.11 — «да» на цену</b></summary>" }),
  iBody: box.add("blockquote"),
  iClose: box.add("p", { text: "</details>" }),
});

const page = () => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({ text: "" });
      const panel = dom.document.body.add("div", { attrs: { class: "epitaxy-chat-panel" } });
      const feed = panel.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      const row = feed.add("div", {
        attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" },
        rect: { left: 0, top: 0, width: 800, height: 300 },
      });
      const box = row.add("div", { attrs: { class: "prose" } });
      parts.n = answer(box);
      const para = parts.n.iBody.add("p", { text: "Цена 3 290 ₸, картинка: " });
      parts.n.link = para.add("a", { attrs: { href: SHOT }, text: "скрин" });
      parts.n.other = para.add("a", { attrs: { href: "/Users/demo/Rick/work/plan.md" }, text: "план" });
      parts.n.para = para;
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.win.fetch = address => {
    loaded.calls.push(String(address));
    return Promise.resolve({ ok: true, arrayBuffer: async () => JPEG.buffer });
  };
  loaded.inner.foldTick();
  const click = node => loaded.dom.document.dispatchEvent({ type: "click", target: node, detail: 1, isTrusted: true });
  return { loaded, n: loaded.parts.n, click };
};
const headOf = (loaded, raw) => loaded.dom.queryAll(`[${HEAD}]`).find(head => head.nextElementSibling === raw);
const thumbs = loaded => loaded.calls.filter(item => item.includes("/thumb?"));
const rowOf = para => [...para.childNodes].find(kid => kid.nodeType === 1 && kid.getAttribute(PIC) === "row") ?? null;

test("WF302: «💬 Ответы на твои вопросы» — крупная голова, пункт «Ждёт тебя» — обычная; вид в правилах", () => {
  const { loaded, n } = page();
  const big = headOf(loaded, n.qOpen);
  const item = headOf(loaded, n.iOpen);
  assert.ok(big && item, "обе свёртки получили голову");
  assert.equal(big.getAttribute(BIG), "", "подпись на «💬» — крупная");
  assert.equal(item.getAttribute(BIG), null, "прочие — как были");
  assert.equal(big.getAttribute("data-myclaude-fold-label"), "💬 ОТВЕТЫ НА ТВОИ ВОПРОСЫ — 2", "подпись без стрелки (#11478: стрелка — ::before вне плашки)");
  assert.equal(big.getAttribute(HEAD), "closed", "свёрнута по умолчанию");
  assert.equal(plain(loaded.api.status().folds).big, 1);
  const css = loaded.dom.cssText?.() ?? [...loaded.dom.document.querySelectorAll("style")].map(node => node.textContent).join("\n");
  assert.match(css, new RegExp(`\\[${HEAD}\\]\\[${BIG}\\]\\{[^}]*font-size:1\\.5em;[^}]*font-weight:700`), "крупно, жирно");
});

test("WF302: ссылка на картинку в открытой свёртке — миниатюра в конце абзаца; закрыта — ни запроса, ни картинки", async () => {
  const { loaded, n, click } = page();
  assert.deepEqual(thumbs(loaded), [], "закрытая свёртка — запроса нет");
  click(headOf(loaded, n.iOpen));
  assert.deepEqual(thumbs(loaded), [`http://127.0.0.1:47615/thumb?path=${encodeURIComponent(SHOT)}&chat=${CHAT}`],
    "открыл — один запрос, только на картинку (план .md — не фото)");
  await settle();
  loaded.inner.foldTick();
  const row = rowOf(n.para);
  assert.ok(row, "миниатюра встала");
  assert.equal(n.para.childNodes[n.para.childNodes.length - 1], row, "последним узлом абзаца — текст ссылок не задет");
  const imgs = [...row.childNodes].filter(kid => kid.nodeType === 1);
  assert.equal(imgs.length, 1);
  assert.equal(imgs[0].tagName, "IMG");
  assert.equal(imgs[0].getAttribute(PIC), "img");
  assert.equal(imgs[0].getAttribute("title"), "4.webp");
  assert.equal(imgs[0].getAttribute("src"), `data:image/jpeg;base64,${Buffer.from(JPEG).toString("base64")}`);
  assert.equal(plain(loaded.api.status().folds).pics, 1);
  loaded.inner.foldTick();
  assert.equal(thumbs(loaded).length, 1, "повторный проход — из кэша, без запроса");
  assert.equal(rowOf(n.para), row, "тот же узел, не пересоздан");
  click(headOf(loaded, n.iOpen));
  assert.equal(rowOf(n.para), null, "закрыл — миниатюры нет");
  assert.equal(plain(loaded.api.status().folds).pics, 0);
  click(headOf(loaded, n.iOpen));
  assert.ok(rowOf(n.para), "открыл снова — из кэша сразу");
  loaded.api.dispose();
  assert.equal(rowOf(n.para), null, "dispose убирает миниатюры");
  assert.equal(n.link.getAttribute("href"), SHOT, "ссылка Claude не тронута");
});
