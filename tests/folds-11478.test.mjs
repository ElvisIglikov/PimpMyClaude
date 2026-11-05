// #11478 (страница, разделы 12ф, 12с², 12с³, 12ф³ и 4). Слово Элвиса 01.11 о ленте ответа Рика: «чтобы оно…
// заканчивалось цифрой», «скругления были одинаковые», «ждёт тебя сделать таким же блоком свёртываемым», отступы —
// «принцип приближенности… заголовок-то нижнего абзаца».
//
// Что проверяется:
//   1) «💬 ОТВЕТЫ…» и «❗ ЖДЁТ ТЕБЯ — N (🔴 K)» — крупные головы; подпись без стрелки (стрелка — ::before вне плашки),
//      прочие — как были; плашка — ::after по ширине подписи, без выступа влево; правила близости в теле свёртки;
//      у мелкой головы висячий отступ на замеренную ширину «▾ » — длинная подпись переносится под текст, не на полосу;
//   2) раздел-свёртка «❗ ЖДЁТ ТЕБЯ»: фразы 12с² в его теле нажимаются, пункт с файлом — ссылкой (12с³), сама голова
//      раздела — нет; после </details> раздела — не раздел;
//   3) копия «Ждёт тебя» над свёрнутым ответом (12ф³, answerWaitsOf): подпись раздела и подписи пунктов, до его
//      </details>.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_fold-11478";
const HEAD = "data-myclaude-fold-head";
const BIG = "data-myclaude-fold-big";
const LABEL = "data-myclaude-fold-label";
const RAW = "data-myclaude-fold-raw";
const PHRASE = "data-myclaude-wait-phrase";
const FILE = "data-myclaude-wait-file";
const SALE = "/Users/demo/Rick/work/sale-01-11.html";

// Ответ Рика по форме ELVIS.md с 01.11: «💬 Ответы» → «❗ ЖДЁТ ТЕБЯ» свёрткой с пунктами-свёртками → остальное.
const answer = box => {
  const n = {};
  n.top = box.add("h1", { text: "Распродажа готова — нужно твоё «да»" });
  n.qOpen = box.add("p", { text: "<details>" });
  box.add("p", { text: "<summary><b>💬 ОТВЕТЫ НА ТВОИ ВОПРОСЫ — 1</b></summary>" });
  n.aOpen = box.add("p", { text: "<details>" });
  box.add("p", { text: "<summary><b>1. Адрес — да</b></summary>" });
  box.add("p", { text: "Лена подтвердила адрес." });
  box.add("p", { text: "</details>" });
  box.add("p", { text: "</details>" });
  n.wOpen = box.add("p", { text: "<details>" });
  box.add("p", { text: "<summary><b>❗ ЖДЁТ ТЕБЯ — 2 (🔴 1)</b></summary>" });
  n.sOpen = box.add("p", { text: "<details>" });
  box.add("p", { text: "<summary><b>17 · 🔴 Распродажа 01.11 — «да» на цену</b></summary>" });
  n.sBody = box.add("p", { text: "Цена 3 290 ₸, страница: " });
  n.sBody.add("a", { attrs: { href: SALE }, text: "распродажа" });
  n.sBody.add("span", { text: ", скажи " });
  n.phrase = n.sBody.add("strong", { text: "«выкладывай»" });
  box.add("p", { text: "</details>" });
  n.oOpen = box.add("p", { text: "<details><summary>18 · Оля — «да» на отпуск</summary>" });
  n.oBody = box.add("p", { text: "Файла нет, скажи " });
  n.oPhrase = n.oBody.add("strong", { text: "«да Оле»" });
  box.add("p", { text: "</details>" });
  n.wClose = box.add("p", { text: "</details>" });
  n.after = box.add("p", { text: "Дальше делаю я, скажи " });
  n.afterPhrase = n.after.add("strong", { text: "«не отсюда»" });
  return n;
};

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
      parts.box = row.add("div", { attrs: { class: "prose" } });
      parts.n = answer(parts.box);
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.win.fetch = () => Promise.resolve({ ok: true });
  const paint = () => { loaded.inner.foldTick(); loaded.inner.waitPhrasePaint(); loaded.inner.waitFilePaint(); };
  paint();
  const click = node => loaded.dom.document.dispatchEvent({ type: "click", target: node, button: 0, detail: 1, isTrusted: true });
  return { loaded, n: loaded.parts.n, box: loaded.parts.box, click, paint };
};
const headOf = (loaded, raw) => loaded.dom.queryAll(`[${HEAD}]`).find(head => head.nextElementSibling === raw);
const cssOf = loaded => loaded.dom.cssText?.() ?? [...loaded.dom.document.querySelectorAll("style")].map(node => node.textContent).join("\n");
const ruleOf = (css, selector) => css.split("\n").find(rule => rule.startsWith(`${selector}{`)) ?? "";

test("#11478: «💬» и «❗ ЖДЁТ ТЕБЯ» — крупные, подпись без стрелки; плашка — по подписи, без выступа; близость в теле", () => {
  const { loaded, n, click } = page();
  const answers = headOf(loaded, n.qOpen);
  const wait = headOf(loaded, n.wOpen);
  const item = headOf(loaded, n.sOpen);
  assert.ok(answers && wait && item, "головы на месте");
  assert.equal(answers.getAttribute(BIG), "", "«💬» — крупная");
  assert.equal(wait.getAttribute(BIG), "", "«❗ ЖДЁТ ТЕБЯ» — такая же");
  assert.equal(item.getAttribute(BIG), null, "пункт — обычный");
  assert.equal(headOf(loaded, n.aOpen).getAttribute(BIG), null, "вопрос внутри «💬» — обычный");
  assert.equal(answers.getAttribute(LABEL), "💬 ОТВЕТЫ НА ТВОИ ВОПРОСЫ — 1", "стрелка не в подписи");
  assert.equal(wait.getAttribute(LABEL), "❗ ЖДЁТ ТЕБЯ — 2 (🔴 1)");
  assert.equal(plain(loaded.api.status().folds).big, 2);
  click(wait);
  assert.equal(wait.getAttribute(HEAD), "open", "раскрылась нажатием");
  assert.equal(wait.getAttribute(LABEL), "❗ ЖДЁТ ТЕБЯ — 2 (🔴 1)", "подпись та же — стрелку меняет ::before");

  const css = cssOf(loaded);
  const big = `[${HEAD}][${BIG}]`;
  const head = ruleOf(css, big);
  assert.match(head, /display:flex;align-items:baseline;/, "стрелка и плашка — в строку");
  assert.match(head, /font-size:1\.5em;[^}]*font-weight:700/, "крупно и жирно");
  assert.doesNotMatch(head, /width:auto|margin:[^;]*-\d/, "не во всю ширину и без выступа влево (его режет скроллер)");
  assert.match(head, /background:none/, "у самой головы фона нет");
  assert.match(ruleOf(css, `${big}::before`), /content:"▸";[^}]*position:static/, "стрелка — своим знаком, в потоке");
  assert.match(ruleOf(css, `[${HEAD}="open"][${BIG}]::before`), /content:"▾"/);
  assert.match(ruleOf(css, `${big}::after`), /padding:8px 12px;border-radius:10px;background:color-mix/, "плашка по подписи, скругления с обеих сторон");
  assert.match(css, new RegExp(`\\[${HEAD}="open"\\]\\+\\[${RAW}\\]\\+\\[${RAW}\\]\\)\\+[^{]*\\{padding-top:\\.2em !important\\}`), "под головой — вплотную");
  assert.match(css, new RegExp(`:has\\(\\+:is\\(\\[${RAW}\\],\\[${HEAD}\\]\\)\\)\\{padding-bottom:\\.8em !important\\}`), "перед следующей головой — поле");
  assert.match(ruleOf(css, `[${HEAD}]:not([data-myclaude-fold-whole],[${BIG}])`), /padding-left:calc\(4px \+ var\(--myclaude-fold-hang, \.9em\)\);text-indent:calc\(0px - var\(--myclaude-fold-hang, \.9em\)\)/, "мелкая — перенос под текст, ▾ на месте");
  const root = loaded.dom.document.documentElement.style;
  assert.match(root.getPropertyValue("--myclaude-fold-hang"), /^\d+(\.\d+)?px$/, "ширина «▾ » замерена");
  loaded.api.dispose();
  assert.equal(root.getPropertyValue("--myclaude-fold-hang"), "", "dispose снимает замер");
});

test("#11478: раздел-свёртка «❗ ЖДЁТ ТЕБЯ» — фразы и ссылки пунктов внутри; сама голова и текст после — нет", () => {
  const { loaded, n } = page();
  assert.equal(n.phrase.getAttribute(PHRASE), "", "фраза в пункте-свёртке нажимается");
  assert.equal(n.oPhrase.getAttribute(PHRASE), "", "и в пункте одним <p>");
  assert.equal(n.afterPhrase.getAttribute(PHRASE), null, "после </details> раздела — не раздел");
  const item = headOf(loaded, n.sOpen);
  const link = [...item.children].find(kid => kid.getAttribute(FILE) === "fold");
  assert.ok(link, "пункт с файлом — ссылкой");
  assert.equal(loaded.inner.waitFile.marks.get(link), SALE);
  assert.equal([...headOf(loaded, n.wOpen).children].length, 0, "голова раздела ссылкой не стала");
  assert.equal(plain(loaded.api.status().waitFiles).count, 1);
  loaded.api.dispose();
  assert.equal(n.phrase.getAttribute(PHRASE), null, "dispose снимает своё");
});

test("#11478: копия «Ждёт тебя» над свёрнутым ответом — подпись раздела и пункты до его </details>", () => {
  const { loaded, box } = page();
  const nodes = [...box.children].filter(node => !node.hasAttribute(HEAD));
  assert.deepEqual(plain(loaded.inner.answerWaitsOf(nodes)), [
    "❗ ЖДЁТ ТЕБЯ — 2 (🔴 1)", "17 · 🔴 Распродажа 01.11 — «да» на цену", "18 · Оля — «да» на отпуск",
  ]);
  loaded.api.dispose();
});
