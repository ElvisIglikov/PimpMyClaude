// «Обкэшить» из подчинённого окна (WF37, задачи #5575 и #5535). До WF37 попап
// клал перенос в localStorage и ждал ⌘N — а ⌘N из попапа исполняет ГЛАВНОЕ окно
// Claude, и перенос уезжал в чат, где Элвис ведёт диктовку. Теперь попап только
// помечает запись «ждёт адресата» (to: "pending"), адресата называет цепочка
// «Нового окна» (cashoutStamp), и перенос ложится в НОВОЕ окно.
//
// Формы записей и порядок ключей сверяются с эталонами tests/fixtures/cashout —
// те же файлы читает Swift-половина (CommandChannel.payload побайтно).
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { loadInject, plain } from "./load.mjs";

const CASHOUT_KEY = "myclaude-cashout";
const MAIN = "https://claude.ai/epitaxy/local_aaa";
const POPOUT = "about:blank";
const ANSWER = "Последний ответ Claude.";
const DRAFT = "Черновик Элвиса";

const fixture = name => JSON.parse(readFileSync(new URL(`./fixtures/cashout/${name}.json`, import.meta.url), "utf8"));

// Страница с полем ввода и (по желанию) последним ответом Claude: ровно то, из
// чего «Обкэшить» собирает перенос.
const page = ({ href = MAIN, title = "PimpMyClaude", draft = DRAFT, answer = ANSWER, storage, opener } = {}) =>
  loadInject({
    href,
    title,
    hasFocus: false,
    storage,
    opener,
    html: dom => {
      const parts = dom.composer({ text: draft });
      if (answer) dom.document.body.add("div", { attrs: { "data-testid": "assistant-message" }, text: answer });
      return parts;
    },
  });

const cashout = (extra = {}) => ({ id: "c1", action: "cashout", at: "now", scope: "window", ...extra });
const stored = loaded => {
  const raw = loaded.win.localStorage.getItem(CASHOUT_KEY);
  return raw == null ? null : JSON.parse(raw);
};
// Запись переноса, как её оставляет цепочка «Нового окна» после штампа.
const stamped = (extra = {}) => JSON.stringify({
  at: Date.now(), text: `${ANSWER}\n\n${DRAFT}`, to: "local_new", title: "VkusnoffKz 3", stampedAt: Date.now(), ...extra,
});
const drain = () => new Promise(resolve => setImmediate(resolve));

test("попап пишет перенос «ждёт адресата» и сторожа не заводит", () => {
  const popup = page({ href: POPOUT, title: "VkusnoffKz 2" });
  const before = popup.counters.intervals;
  popup.dom.command(cashout({ title: "VkusnoffKz 2" }));
  const record = stored(popup);
  assert.deepEqual(Object.keys(record), Object.keys(fixture("record-pending")), "порядок ключей — по эталону");
  assert.equal(record.to, "pending", "адресата назовёт цепочка «Нового окна»");
  assert.equal(record.text, fixture("record-pending").text, "ответ и черновик, как раньше");
  assert.equal(typeof record.at, "number");
  assert.equal(popup.counters.intervals, before, "донор сторожа не заводит: вставлять перенос ему некуда");
  assert.equal(popup.api.status().cashout.to, "pending");
  assert.equal(popup.api.status().cashout.record, true);
});

test("главное окно пишет запись без адресата и заводит сторож", () => {
  const main = page();
  const before = main.counters.intervals;
  main.dom.command(cashout({ title: "PimpMyClaude" }));
  const record = stored(main);
  assert.deepEqual(Object.keys(record), Object.keys(fixture("record-main")), "полей переноса у главного окна нет");
  assert.equal(record.text, fixture("record-main").text);
  assert.equal(main.counters.intervals, before + 1, "сторож вставки на месте — ⌘N откроет чат в этом же окне");
  assert.deepEqual(plain(main.api.status().cashout),
    { record: true, to: null, title: null, stampedAt: null, refusal: null });
});

test("адресация: match и chat сильнее заголовка", () => {
  const main = page();
  const took = detail => {
    main.win.localStorage.removeItem(CASHOUT_KEY);
    main.dom.command(cashout(detail));
    return stored(main) != null;
  };
  assert.equal(took({ title: "PimpMyClaude" }), true, "заголовок совпал — как до WF37");
  assert.equal(took({ title: "Чужое имя" }), false, "чужой заголовок, фокуса нет");
  assert.equal(took({ title: "Чужое имя", chat: "local_aaa" }), true, "id чата сильнее заголовка");
  assert.equal(took({ title: "PimpMyClaude", chat: "local_zzz" }), false, "чужой id — команда не наша, молчим");
  assert.equal(took({ title: "Чужое имя", match: "/epitaxy/local_aaa" }), true, "путь страницы сильнее заголовка");
  assert.equal(took({ title: "PimpMyClaude", match: "/epitaxy/local_zzz" }), false, "чужой путь");
});

test("перенос ложится в окно, названное по id чата", () => {
  const popup = page({
    href: POPOUT,
    title: "Заголовок ещё старый",
    draft: "",
    answer: "",
    storage: {
      local: { [CASHOUT_KEY]: stamped({ title: "VkusnoffKz 3" }) },
      // Свой id попап уже знает — ответ родителя лежит в кэше (раздел 12в).
      session: { "myclaude-chat-v1": JSON.stringify({ id: "local_new", title: "Заголовок ещё старый" }) },
    },
  });
  const armed = popup.counters.intervals;
  // Сторож заведён на инжекте — гоняем именно его, а не помощника напрямую.
  popup.dom.fireKind("interval");
  assert.equal(popup.parts.editor.textContent, `${ANSWER}\n\n${DRAFT}`, "перенос лёг в поле нового окна");
  assert.equal(stored(popup), null, "вставил — запись стёрта");
  assert.equal(popup.counters.intervals, armed - 1, "сторож погасил себя");
  assert.equal(popup.api.status().cashout.record, false);
});

test("перенос ложится в окно, узнанное по заголовку", () => {
  const popup = page({
    href: POPOUT, title: "VkusnoffKz 3", draft: "", answer: "",
    storage: { local: { [CASHOUT_KEY]: stamped() } },
  });
  assert.equal(popup.inner.tryPasteCashout(), "вставлено", "своего id окно ещё не знает — спасает заголовок");
  assert.equal(popup.parts.editor.textContent, `${ANSWER}\n\n${DRAFT}`);
  assert.equal(stored(popup), null);

  // Заглушка заголовка в сопоставлении не участвует: её носят разные чаты во
  // всех окнах разом.
  const stub = page({
    href: POPOUT, title: "Claude", draft: "", answer: "",
    storage: { local: { [CASHOUT_KEY]: stamped({ title: "Claude" }) } },
  });
  assert.equal(stub.inner.tryPasteCashout(), "чат не опознан", "по «Claude» окно не опознаётся");
  assert.notEqual(stored(stub), null, "чужой перенос не съеден");
});

test("запись «ждёт адресата» не вставляется никуда", () => {
  const popup = page({
    href: POPOUT, title: "VkusnoffKz 2", draft: "", answer: "",
    storage: { local: { [CASHOUT_KEY]: JSON.stringify({ ...fixture("record-pending"), at: Date.now() }) } },
  });
  assert.equal(popup.inner.tryPasteCashout(), "адресат не назначен");
  assert.equal(popup.parts.editor.textContent, "", "поле не тронуто");
  assert.notEqual(stored(popup), null, "запись ждёт цепочку «Нового окна»");
});

test("главное окно записи с адресатом игнорирует всегда", () => {
  const main = page({
    draft: "", answer: "",
    // Худший случай: адресат — id чата самого главного окна.
    storage: { local: { [CASHOUT_KEY]: stamped({ to: "local_aaa", title: "PimpMyClaude" }) } },
  });
  assert.equal(main.inner.tryPasteCashout(), "перенос не главному окну");
  assert.equal(main.parts.editor.textContent, "", "чат Элвиса не тронут");
  assert.notEqual(stored(main), null, "и запись не съедена — её ждёт новое окно");
});

test("поле с черновиком перенос не принимает", () => {
  const popup = page({
    href: POPOUT, title: "VkusnoffKz 3", draft: "Недописанная мысль", answer: "",
    storage: { local: { [CASHOUT_KEY]: stamped() } },
  });
  assert.equal(popup.inner.tryPasteCashout(), "в поле черновик");
  assert.equal(popup.parts.editor.textContent, "Недописанная мысль");
  assert.notEqual(stored(popup), null);
});

test("протухший штамп: не вставили и запись стёрли", () => {
  const old = Date.now() - 61000;
  const popup = page({
    href: POPOUT, title: "VkusnoffKz 3", draft: "", answer: "",
    storage: { local: { [CASHOUT_KEY]: stamped({ stampedAt: old }) } },
  });
  assert.equal(popup.inner.tryPasteCashout(), "перенос протух", "срок считается от штампа, а не от нажатия");
  assert.equal(popup.parts.editor.textContent, "");
  assert.equal(stored(popup), null);

  // Цепочка сорвалась и адресата не назвала — запись умирает по общему сроку.
  const never = page({
    href: POPOUT, title: "VkusnoffKz 2", draft: "", answer: "",
    storage: { local: { [CASHOUT_KEY]: JSON.stringify({ at: Date.now() - 91000, text: "перенос", to: "pending" }) } },
  });
  assert.equal(never.inner.tryPasteCashout(), "запись протухла");
  assert.equal(stored(never), null);

  // Штампа нет вовсе (битая запись) — тот же исход, ждать нечего.
  const noStamp = page({
    href: POPOUT, title: "VkusnoffKz 3", draft: "", answer: "",
    storage: { local: { [CASHOUT_KEY]: JSON.stringify({ at: Date.now(), text: "перенос", to: "local_new" }) } },
  });
  assert.equal(noStamp.inner.tryPasteCashout(), "перенос протух");
  assert.equal(stored(noStamp), null);
});

test("родителя сторож спрашивает ровно один раз", async () => {
  const mute = { asks: 0 };
  const silent = page({
    href: POPOUT, title: "VkusnoffKz 3", draft: "", answer: "",
    storage: { local: { [CASHOUT_KEY]: stamped({ title: "Имя, которого окно не знает" }) } },
    opener: { __myclaude: { popoutChat: async () => { mute.asks += 1; return null; } } },
  });
  assert.equal(silent.inner.tryPasteCashout(), "чат не опознан", "ни id, ни заголовка — спрашиваем родителя");
  await drain();
  assert.equal(mute.asks, 1);
  assert.equal(silent.inner.tryPasteCashout(), "чат не опознан", "родитель промолчал — ждём круга probe");
  assert.equal(silent.inner.tryPasteCashout(), "чат не опознан");
  await drain();
  assert.equal(mute.asks, 1, "долбить родителя каждые 300 мс нельзя");
  assert.notEqual(stored(silent), null, "чужой перенос цел");

  // Ответ родителя ложится в кэш myclaude-chat-v1 — и следующий тик вставляет.
  const heard = { asks: 0 };
  const popup = page({
    href: POPOUT, title: "VkusnoffKz 3", draft: "", answer: "",
    storage: { local: { [CASHOUT_KEY]: stamped({ title: "Имя, которого окно не знает" }) } },
    opener: { __myclaude: { popoutChat: async () => { heard.asks += 1; return "local_new"; } } },
  });
  assert.equal(popup.inner.tryPasteCashout(), "чат не опознан");
  await drain();
  assert.equal(heard.asks, 1);
  assert.equal(popup.win.sessionStorage.getItem("myclaude-chat-v1") != null, true, "ответ лёг в кэш окна");
  assert.equal(popup.inner.tryPasteCashout(), "вставлено", "id приехал — перенос лёг");
  assert.equal(stored(popup), null);
  assert.equal(heard.asks, 1, "второй раз спрашивать было незачем");
});

test("пустой чат: «Обкэшить» отказывает плашкой, а не молчанием", () => {
  // ⌘N жмёт приложение независимо от ответа страницы, и до починки Элвис получал
  // пустой новый чат без единого слова (находка ревизии 08.09).
  const main = page({ draft: "", answer: "" });
  main.dom.command(cashout({ title: "PimpMyClaude" }));
  assert.equal(stored(main), null, "переносить нечего — записи нет");
  const note = main.dom.query("#myclaude-new-window-note");
  assert.ok(note, "плашка в окне есть");
  assert.equal(note.textContent, "Нечего переносить");
  assert.equal(note.style.getPropertyValue("display"), "block", "и она видна");
  assert.equal(plain(main.api.status().cashout).refusal, "Нечего переносить",
    "гейту причина названа тем же словом");
});
