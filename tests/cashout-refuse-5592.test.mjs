// #5592: «Обкэшить» из попапа едет цепочкой «Нового окна» главного окна. Цепочка отказала (черновик в
// поле домашнего экрана и прочие отказы) — раньше плашка вставала в главном окне, а донор и приложение
// ждали до потолка (90 и 135 с). Теперь главное окно пишет причину в запись переноса: слово доезда у
// всех окон — «отказ: <причина>» (приложение бросает ожидание на ближайшем круге), а донор сразу
// показывает плашку у себя.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { loadInject } from "./load.mjs";

const CASHOUT_KEY = "myclaude-cashout";
const ANSWER = "Последний ответ Claude.";
const DRAFT = "Черновик Элвиса";
const fixture = name => JSON.parse(readFileSync(new URL(`./fixtures/cashout/${name}.json`, import.meta.url), "utf8"));
const pending = () => JSON.stringify({ ...fixture("record-pending"), at: Date.now() });
const stored = loaded => JSON.parse(loaded.win.localStorage.getItem(CASHOUT_KEY) ?? "null");
const settle = async (times = 8) => { for (let index = 0; index < times; index += 1) await new Promise(setImmediate); };

// Главное окно на домашнем экране, в поле — мысль Элвиса; стор попапов на месте.
const mainAtHome = (draft = "мысль Элвиса") => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy", title: "Claude",
    storage: { local: { [CASHOUT_KEY]: pending() } },
    html: dom => ({
      input: dom.document.body.add("div", { attrs: { "data-testid": "code-prompt-input", contenteditable: "true" }, text: draft }),
    }),
  });
  const value = { popoutWindows: loaded.run("new Map()"), openPopout: () => {} };
  const store = () => {};
  store.getState = () => value;
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  loaded.inner.setModuleImporter(() => Promise.resolve({ Store: store }));
  return loaded;
};
const transfer = (extra = {}) => ({
  id: "t1", action: "new-window", at: "now", scope: "window", title: "Claude",
  x: 100, y: 200, text: "Привет", folder: "", name: "", transfer: true, ...extra,
});
// Попап с ответом и черновиком — ровно то, из чего «Обкэшить» собрал запись.
const popup = ({ answer = ANSWER, draft = DRAFT } = {}) => loadInject({
  href: "about:blank", title: "VkusnoffKz 2", hasFocus: false,
  html: dom => {
    const parts = dom.composer({ text: draft });
    dom.document.body.add("div", { attrs: { "data-testid": "assistant-message" }, text: answer });
    return parts;
  },
});
const note = loaded => loaded.dom.query("#myclaude-new-window-note");

test("#5592: черновик на домашнем экране — главное окно пишет отказ в запись переноса", async () => {
  const main = mainAtHome();
  main.dom.command(transfer());
  await settle();
  assert.equal(main.api.status().newWindow.state, "draft");
  assert.equal(stored(main).refused, "в главном окне в поле черновик");
  assert.equal(stored(main).to, "pending", "запись не штампуется и не стирается — её слово читают все окна");
  assert.equal(main.api.status().cashout.delivery, "отказ: в главном окне в поле черновик",
    "приложение бросает ожидание на ближайшем круге, а не через 135 с");
});

test("#5592: без transfer чужая запись переноса не трогается", async () => {
  const main = mainAtHome();
  main.dom.command(transfer({ transfer: undefined }));
  await settle();
  assert.equal(main.api.status().newWindow.state, "draft");
  assert.equal(stored(main).refused, undefined);
  assert.equal(main.api.status().cashout.delivery, "ждём");
});

test("#5592: донор показывает плашку сразу — по событию storage, один раз", () => {
  const donor = popup();
  donor.dom.command({ id: "c1", action: "cashout", at: "now", scope: "window", title: "VkusnoffKz 2" });
  assert.equal(stored(donor).to, "pending");
  assert.equal(note(donor), null);
  // Главное окно пишет отказ в общий localStorage — у донора приходит storage.
  assert.equal(donor.inner.cashoutRefuse("в главном окне в поле черновик"), true);
  donor.win.dispatchEvent({ type: "storage", key: CASHOUT_KEY });
  const shown = note(donor);
  assert.ok(shown, "плашка в окне, где нажали");
  assert.match(shown.textContent, /^Перенос не уехал: в главном окне в поле черновик\./);
  assert.match(shown.textContent, /Текст остался здесь/);
  assert.equal(donor.api.status().cashout.refusal, "в главном окне в поле черновик");
  assert.equal(donor.api.status().cashout.delivery, "отказ: в главном окне в поле черновик");
  assert.equal(donor.inner.cashoutRefuse("другое"), false, "второй отказ первый не переписывает");
});

test("#5592: чужой попап плашку не показывает, донор узнаёт себя и с правленым черновиком", () => {
  const other = popup({ answer: "Совсем другой разговор." });
  other.win.localStorage.setItem(CASHOUT_KEY, JSON.stringify({ ...fixture("record-pending"), at: Date.now(), refused: "новое окно не открылось" }));
  other.win.dispatchEvent({ type: "storage", key: CASHOUT_KEY });
  assert.equal(note(other), null);

  const donor = popup({ draft: "Черновик Элвиса, дописанный" });
  donor.win.localStorage.setItem(CASHOUT_KEY, JSON.stringify({ ...fixture("record-pending"), at: Date.now(), refused: "новое окно не открылось" }));
  // storage не дошёл — запасной путь: вопрос приложения (status().cashout).
  donor.api.status();
  assert.ok(note(donor), "плашка по вопросу приложения");
});

test("#5592: штампованная запись чужого чата отказом не помечается", () => {
  const donor = popup();
  donor.win.localStorage.setItem(CASHOUT_KEY, JSON.stringify({ ...fixture("record-stamped"), stampedAt: Date.now() }));
  const to = stored(donor).to;
  assert.equal(donor.inner.cashoutRefuse("новое окно не открылось"), false);
  assert.equal(donor.inner.cashoutRefuse("новое окно не открылось", "local_other"), false);
  assert.equal(donor.inner.cashoutRefuse("новое окно не открылось", to), true, "свой чат создан, а в окно не вынесся");
});
