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
// Один шаг подтверждения доезда (WF50, #5780): работа доставки тикает своим
// setTimeout, и стенд гоняет её теми же таймерами, что живут в окне.
const step = loaded => loaded.dom.fireKind("timeout");
// Часы страницы вперёд: у окна свой Date, и ожидания (черновик, срок записи)
// проверяются переводом ЕГО часов, а не паузой в тесте.
const jump = (loaded, ms) => loaded.run(`(() => { const real = Date.now; Date.now = () => real.call(Date) + ${ms}; })()`);

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
    { record: true, to: null, title: null, stampedAt: null, refusal: null,
      delivery: "ждём", deliveryAt: null, files: { want: 0, sent: 0, done: 0 } },
    "запись есть, доезд ещё не подтверждён");
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
  assert.notEqual(stored(popup), null, "запись держится до подтверждения доезда");
  assert.equal(popup.api.status().cashout.delivery, "ждём");
  step(popup);
  assert.equal(stored(popup), null, "доезд подтверждён — только теперь запись стёрта");
  assert.equal(popup.counters.intervals, armed - 1, "сторож погасил себя");
  assert.equal(popup.api.status().cashout.record, false);
  assert.equal(popup.api.status().cashout.delivery, "вставлено", "приложению сказано одним словом");
});

test("перенос ложится в окно, узнанное по заголовку", () => {
  const popup = page({
    href: POPOUT, title: "VkusnoffKz 3", draft: "", answer: "",
    storage: { local: { [CASHOUT_KEY]: stamped() } },
  });
  assert.equal(popup.inner.tryPasteCashout(), "ждём доезда", "своего id окно ещё не знает — спасает заголовок");
  assert.equal(popup.parts.editor.textContent, `${ANSWER}\n\n${DRAFT}`);
  step(popup);
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

// Знаешь свой номер чата — заголовок больше не спасает (#5787). Заголовок
// попапа это снимок имени чата на момент выноса: чат переименовали, и то же имя
// носит уже другое окно — чужой перенос уезжал бы в разговор, где Элвис работает.
test("свой id сильнее заголовка: чужой перенос не присваивается", () => {
  const popup = page({
    href: POPOUT, title: "VkusnoffKz 3", draft: "", answer: "",
    storage: {
      // Заголовок совпал с записью, а адресована она другому чату.
      local: { [CASHOUT_KEY]: stamped({ to: "local_other", title: "VkusnoffKz 3" }) },
      session: { "myclaude-chat-v1": JSON.stringify({ id: "local_new", title: "VkusnoffKz 3" }) },
    },
  });
  assert.equal(popup.inner.tryPasteCashout(), "перенос не в это окно",
    "свой номер чата известен и не сошёлся — запись не наша");
  assert.equal(popup.parts.editor.textContent, "", "поле не тронуто");
  assert.notEqual(stored(popup), null, "и запись цела: её ждёт своё окно");
  assert.equal(popup.api.status().cashout.delivery, "ждём", "подтверждать этому окну нечего");
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

test("чужой черновик перенос больше не роняет (#5781)", () => {
  // До WF50 черновик был приговором: перенос молча протухал (60/90 с), а окно
  // донора к тому времени уже закрыто (#5768) — терялся текст Элвиса.
  const popup = page({
    href: POPOUT, title: "VkusnoffKz 3", draft: "Недописанная мысль", answer: "",
    storage: { local: { [CASHOUT_KEY]: stamped() } },
  });
  assert.equal(popup.inner.tryPasteCashout(), "ждём черновик", "сперва ждём: Claude убирает прошлый черновик сам");
  assert.equal(popup.parts.editor.textContent, "Недописанная мысль", "поле пока не тронуто");
  assert.notEqual(stored(popup), null, "и запись цела");
  assert.equal(popup.api.status().cashout.delivery, "ждём");

  jump(popup, 1900);
  assert.equal(popup.inner.tryPasteCashout(), "ждём доезда", "срок вышел — вставляем");
  assert.equal(popup.parts.editor.textContent, `${ANSWER}\n\n${DRAFT}`,
    "перенос лёг ПОВЕРХ выделения всего поля, а не рядом с черновиком");
  step(popup);
  assert.equal(stored(popup), null, "доезд подтверждён");
  assert.equal(popup.api.status().cashout.delivery, "вставлено");
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
  assert.equal(popup.inner.tryPasteCashout(), "ждём доезда", "id приехал — перенос лёг");
  step(popup);
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

// ---- Доезд подтверждается, а не предполагается (WF50, #5780 и #5779) -------
// Урок донора ElvisOS: мгновенная проверка врала «не попал» уже ПОСЛЕ удачной
// вставки. С #5768 цена этой ошибки — не пустой чат, а потерянный текст Элвиса:
// приложение закрывает окно-донор.

test("редактор принял текст не сразу — ждём и подтверждаем", () => {
  const popup = page({
    href: POPOUT, title: "VkusnoffKz 3", draft: "", answer: "",
    storage: { local: { [CASHOUT_KEY]: stamped() } },
  });
  // Редактор молчит: первый способ вставки ничего не кладёт.
  popup.run("document.execCommand = () => false;");
  assert.equal(popup.inner.tryPasteCashout(), "ждём доезда");
  step(popup);
  assert.equal(popup.api.status().cashout.delivery, "ждём", "молчание редактора — ещё не отказ");
  assert.notEqual(stored(popup), null, "запись цела: доезд не подтверждён");

  // Текст доехал сам, с задержкой — работа доставки это видит на своём тике.
  popup.parts.editor.__text = `${ANSWER}\n\n${DRAFT}`;
  step(popup);
  assert.equal(popup.api.status().cashout.delivery, "вставлено");
  assert.equal(stored(popup), null, "и только теперь запись стёрта");
});

test("первый способ не взял — досылаем вторым", () => {
  const popup = page({
    href: POPOUT, title: "VkusnoffKz 3", draft: "", answer: "",
    storage: { local: { [CASHOUT_KEY]: stamped() } },
  });
  popup.run("document.execCommand = () => false;");
  // ProseMirror, который понимает только событие paste.
  popup.parts.editor.addEventListener("paste", event => {
    popup.parts.editor.__text = event.clipboardData.getData("text/plain");
  });
  assert.equal(popup.inner.tryPasteCashout(), "ждём доезда");
  for (let tick = 0; tick < 12; tick += 1) step(popup);
  assert.equal(popup.parts.editor.textContent, `${ANSWER}\n\n${DRAFT}`, "второй способ положил текст");
  assert.notEqual(stored(popup), null, "но подтверждения ещё не было");
  step(popup);
  assert.equal(popup.api.status().cashout.delivery, "вставлено");
  assert.equal(stored(popup), null);
});

test("текст так и не попал — приговор словами, окно не трогаем", () => {
  const popup = page({
    href: POPOUT, title: "VkusnoffKz 3", draft: "", answer: "",
    storage: { local: { [CASHOUT_KEY]: stamped() } },
  });
  popup.run("document.execCommand = () => false;");
  const armed = popup.counters.intervals;
  popup.dom.fireKind("interval");
  for (let tick = 0; tick < 40; tick += 1) step(popup);
  assert.equal(popup.api.status().cashout.delivery, "отказ: текст не попал в поле",
    "приложение узнаёт приговор и донора не закрывает");
  assert.equal(popup.parts.editor.textContent, "", "в поле пусто");
  assert.notEqual(stored(popup), null, "запись чистится ТОЛЬКО после подтверждения");
  assert.equal(popup.counters.intervals, armed - 1, "сторож погашен: ждать больше нечего");
  // Приговор вынесен один раз — повтор второй вставки не делает.
  assert.equal(popup.inner.tryPasteCashout(), "отказ: текст не попал в поле");
});

test("нет записи — приложению сказать нечего", () => {
  const clean = page({ draft: "", answer: "" });
  assert.equal(clean.api.status().cashout.delivery, "", "пустое слово, а не «вставлено»");
});

// Находка гейта WF50: приговор о доезде обязан умирать вместе со своей записью.
// Иначе окно, куда перенос лёг в прошлый раз, на СЛЕДУЮЩЕМ «Обкэшить» снова
// говорит «вставлено» — и приложение закрывает донора по чужому ответу, хотя
// текст никуда не доехал (у двух подряд переносов в одном проекте окна ещё и
// зовутся одинаково, так что заголовок от этого не спасает).
test("приговор прошлого переноса не подтверждает следующий", () => {
  const popup = page({
    href: POPOUT, title: "VkusnoffKz 3", draft: "", answer: "",
    storage: { local: { [CASHOUT_KEY]: stamped() } },
  });
  assert.equal(popup.inner.tryPasteCashout(), "ждём доезда");
  popup.parts.editor.__text = `${ANSWER}\n\n${DRAFT}`;
  step(popup);
  assert.equal(popup.api.status().cashout.delivery, "вставлено");

  // Второй перенос: запись другая, и адресован он другому окну.
  popup.win.localStorage.setItem(CASHOUT_KEY, stamped({ at: Date.now() + 1000, to: "local_other", title: "Другое окно" }));
  assert.equal(popup.api.status().cashout.delivery, "ждём", "чужая запись — прошлый приговор молчит");
  // Запись второго переноса умерла, не доехав (протух штамп, чистка).
  popup.win.localStorage.removeItem(CASHOUT_KEY);
  assert.equal(popup.api.status().cashout.delivery, "",
    "и после чистки: чужой перенос это окно не подтверждает");
});

// Щель, которую закрывает #5788: «Обкэшить» нажали, а команда до страницы не
// дошла — записи не создал никто. Приложение спрашивает все окна, и соседнее,
// куда перенос лёг минуту назад, отвечало «вставлено» — донора закрывали по
// ответу про ПРОШЛЫЙ перенос, и текст Элвиса пропадал. Слово живёт ровно
// столько, сколько прожила бы сама запись, и названо вместе со своей записью.
test("приговор живёт не дольше самой записи", () => {
  const popup = page({
    href: POPOUT, title: "VkusnoffKz 3", draft: "", answer: "",
    storage: { local: { [CASHOUT_KEY]: stamped() } },
  });
  const at = JSON.parse(popup.win.localStorage.getItem(CASHOUT_KEY)).at;
  popup.inner.tryPasteCashout();
  popup.parts.editor.__text = `${ANSWER}\n\n${DRAFT}`;
  step(popup);
  assert.equal(popup.api.status().cashout.delivery, "вставлено");
  assert.equal(popup.api.status().cashout.deliveryAt, at, "слово названо вместе со своей записью");

  // Круг probe приложения — секунды: всё это время слово стоит, хотя запись уже
  // стёрта (её чистит сам доезд).
  jump(popup, 30000);
  assert.equal(popup.api.status().cashout.delivery, "вставлено", "приложение успевает услышать доезд");
  // А дальше запись переноса уже не прожила бы: штампу больше 60 с
  // (CASHOUT_STAMP_FRESH_MS), значит и подтверждать этим словом нечего.
  jump(popup, 31000);
  assert.equal(popup.api.status().cashout.delivery, "",
    "запись столько не живёт — и слово о ней замолкает");
  assert.equal(popup.api.status().cashout.deliveryAt, null, "и записи, о которой оно было, тоже нет");
});
