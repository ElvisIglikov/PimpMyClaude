// «💬 Новый чат» на ⌘B (#7072, WF84; контракты К1 и К2 плана
// docs/plan-wf84-2026-09-23.md, эталоны tests/fixtures/cashout/*handoff*,
// record-sent). Страница: «Обкэшить» с handoff берёт ТОЛЬКО блок передачи
// последнего ответа; цепочка new-window ставит модель и эффорт до первого
// сообщения и шлёт текст передачи первым сообщением; попап с отправленной
// записью сразу говорит «вставлено».
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { loadInject, plain } from "./load.mjs";

const CASHOUT_KEY = "myclaude-cashout";
const fixture = name => JSON.parse(readFileSync(new URL(`./fixtures/cashout/${name}.json`, import.meta.url), "utf8"));
const HANDOFF = fixture("record-handoff").text;
const drain = () => new Promise(resolve => setImmediate(resolve));
const settle = async (times = 6) => { for (let index = 0; index < times; index += 1) await drain(); };
const stored = loaded => {
  const raw = loaded.win.localStorage.getItem(CASHOUT_KEY);
  return raw == null ? null : JSON.parse(raw);
};
const cashout = (extra = {}) => ({ id: "c1", action: "cashout", at: "now", scope: "window", handoff: true, ...extra });

// Ответ с блоком передачи: заголовок, строка модели, блок кода с data-code-text.
const answerWith = (dom, top, { head = "🆕 ОТКРОЙ НОВЫЙ ЧАТ", code = HANDOFF, tail = "", model = "Модель: Opus 5.5 · High", again = false } = {}) => {
  const answer = dom.document.body.add("div", {
    attrs: { "data-testid": "assistant-message" }, rect: { left: 0, top, width: 800, height: 100 },
  });
  answer.add("p", { text: "Сделал." });
  answer.add("pre", { attrs: { "data-code-text": "echo раньше" }, text: "echo раньше" });
  if (head) answer.add("h2", { text: head });
  if (model) answer.add("p", { text: model });
  if (code != null) answer.add("div", { attrs: { "data-code-text": code }, text: code });
  if (tail) answer.add("p", { text: tail });
  // Хвостовой повтор заголовка без кода — по правилу ELVIS.md (WF85, К7.1).
  if (again) answer.add("h2", { text: head });
  return answer;
};
const page = ({ href = "about:blank", title = "VkusnoffKz 2", answers = [{}], draft = "Черновик Элвиса", storage } = {}) =>
  loadInject({
    href, title, hasFocus: false, storage,
    html: dom => {
      const parts = dom.composer({ text: draft });
      answers.forEach((spec, index) => (spec === null
        ? dom.document.body.add("div", { attrs: { "data-testid": "assistant-message" }, text: "Просто ответ." })
        : answerWith(dom, 100 + index * 120, spec)));
      return parts;
    },
  });

test("К1: попап берёт блок кода после «ОТКРОЙ НОВЫЙ ЧАТ» последнего ответа, без черновика", () => {
  const popup = page({ answers: [{ code: "СТАРЫЙ перенос" }, {}] });
  const before = popup.counters.intervals;
  popup.dom.command(cashout({ title: "VkusnoffKz 2" }));
  const record = stored(popup);
  // С WF85 строка «Модель:» стенда разбирается — эталон record-handoff-model (К7.3).
  assert.deepEqual(Object.keys(record), Object.keys(fixture("record-handoff-model")), "порядок ключей — по эталону");
  assert.equal(record.model, "Opus 5.5");
  assert.equal(record.effort, "High");
  assert.equal(record.text, HANDOFF, "только текст блока — ни ответа вокруг, ни черновика, ни старого блока");
  assert.equal(record.to, "pending");
  assert.equal(record.handoff, true);
  assert.equal(popup.counters.intervals, before, "сторожа нет");
});

test("К1: блок передачи только в старом ответе — текст пустой, это не отказ (Б3)", () => {
  const popup = page({ answers: [{}, null] });
  popup.dom.command(cashout({ title: "VkusnoffKz 2" }));
  const record = stored(popup);
  assert.deepEqual(Object.keys(record), Object.keys(fixture("record-handoff-empty")));
  assert.equal(record.text, "");
  assert.equal(popup.api.status().cashout.refusal, null, "плашки отказа нет");
  assert.equal(popup.api.status().cashout.record, true, "пустая запись handoff читается");
});

test("К1: заголовок без блока кода после него — пусто; запасного пути по тексту нет", () => {
  const popup = page({ answers: [{ code: null, tail: HANDOFF }] });
  popup.dom.command(cashout({ title: "VkusnoffKz 2" }));
  assert.equal(stored(popup).text, "");
});

test("К1: главное окно пишет запись без адресата и сторожа НЕ заводит (Б2)", () => {
  const main = page({ href: "https://claude.ai/epitaxy/local_aaa", title: "PimpMyClaude", draft: "" });
  const before = main.counters.intervals;
  main.dom.command(cashout({ title: "PimpMyClaude", match: "/epitaxy/local_aaa" }));
  const record = stored(main);
  assert.deepEqual(Object.keys(record), [...Object.keys(fixture("record-handoff-main")), "model", "effort"]);
  assert.equal(record.text, HANDOFF);
  assert.equal(main.counters.intervals, before, "сторожа вставки нет");
  assert.equal(main.inner.tryPasteCashout(), "перенос «Нового чата»", "и вставкой её не взять");
  assert.equal(main.parts.editor.textContent, "", "домашний композер пуст — шаг 2 цепочки пройдёт");
});

test("К2: попап со своей записью sent:true сразу говорит «вставлено» и ничего не вставляет", () => {
  const sample = fixture("record-sent");
  const popup = page({
    title: sample.title, draft: "", answers: [],
    storage: {
      local: { [CASHOUT_KEY]: JSON.stringify({ ...sample, at: Date.now(), stampedAt: Date.now() }) },
      session: { "myclaude-chat-v1": JSON.stringify({ id: sample.to, title: sample.title }) },
    },
  });
  assert.equal(popup.inner.tryPasteCashout(), "вставлено", "тик сторожа попапа");
  assert.equal(popup.api.status().cashout.delivery, "вставлено");
  assert.equal(popup.parts.editor.textContent, "", "текст уже ушёл первым сообщением — второй раз не кладём");
  assert.equal(stored(popup), null, "запись снята");
});

test("К2: пустая запись handoff — тоже «вставлено» без вставки", () => {
  const popup = page({
    title: "VkusnoffKz 3", draft: "", answers: [],
    storage: {
      local: { [CASHOUT_KEY]: JSON.stringify({ at: Date.now(), text: "", to: "local_new", title: "VkusnoffKz 3", stampedAt: Date.now(), handoff: true, sent: false }) },
      session: { "myclaude-chat-v1": JSON.stringify({ id: "local_new", title: "VkusnoffKz 3" }) },
    },
  });
  assert.equal(popup.inner.tryPasteCashout(), "вставлено");
  assert.equal(popup.api.status().cashout.delivery, "вставлено");
});

// ---- WF85, К7.1–К7.3: хвостовой заголовок и строка «Модель:» --------------
test("К7.1: хвостовой заголовок без кода находку не сбрасывает", () => {
  const popup = page({ answers: [{ again: true, tail: "Расход: 12%." }] });
  popup.dom.command(cashout({ title: "VkusnoffKz 2" }));
  assert.equal(stored(popup).text, HANDOFF);
});

test("К7.2: «Модель:» в одном <p> с фразой; звёздочки и 🔥 не мешают; XHIGH → Extra", () => {
  const popup = page({ answers: [{ model: "Волна сделана, граница — гейт.\n**Модель:** opus 5.5 · 🔥 XHIGH" }] });
  popup.dom.command(cashout({ title: "VkusnoffKz 2" }));
  const record = stored(popup);
  assert.equal(record.model, "Opus 5.5", "первая буква заглавная — как подпись меню");
  assert.equal(record.effort, "Extra");
  assert.equal(popup.inner.readCashout().model, "Opus 5.5", "readCashout пропускает поля (В1)");
  assert.equal(popup.inner.readCashout().effort, "Extra");
});

test("К7.2: строка не разобралась или её нет — полей model и effort нет", () => {
  for (const model of ["Модель: как обычно", "", "Модель — Opus 5.5 · High"]) {
    const popup = page({ answers: [{ model }] });
    popup.dom.command(cashout({ title: "VkusnoffKz 2" }));
    assert.deepEqual(Object.keys(stored(popup)), Object.keys(fixture("record-handoff")), JSON.stringify(model));
  }
});

// ---- цепочка new-window: модель, эффорт, текст передачи ---------------------
// Домашний экран с полем, кнопкой отправки, кнопками модели и эффорта; меню
// модели и диалог эффорта — как у 2.2553.13 (спайк S0).
const MODELS = ["Opus 5.5", "Fable 5.1", "Sonnet 5", "Haiku 4.5"];
const home = ({ model = "Opus 5.5", effort = "High", models = MODELS, record = null } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy", title: "Claude",
    storage: record ? { local: { [CASHOUT_KEY]: JSON.stringify({ ...record, at: Date.now() }) } } : undefined,
    html: dom => {
      const input = dom.document.body.add("div", { attrs: { "data-testid": "code-prompt-input", contenteditable: "true" } });
      const send = dom.document.body.add("button", { attrs: { "data-testid": "code-prompt-send" } });
      const modelButton = dom.document.body.add("button", {
        attrs: { "data-testid": "epitaxy-cds-model-selector", "aria-label": `Model: ${model}`, "aria-haspopup": "menu" },
      });
      const effortButton = dom.document.body.add("button", {
        attrs: { "aria-label": `Effort: ${effort}`, "aria-haspopup": "dialog" },
      });
      const recents = dom.document.body.add("div", { attrs: { "data-testid": "sidebar-recents" } });
      return { input, send, modelButton, effortButton, recents };
    },
  });
  const { parts } = loaded;
  const box = { sent: [], menus: 0, keys: 0 };
  parts.send.addEventListener("click", () => {
    box.sent.push(parts.input.textContent);
    loaded.win.location.pathname = "/epitaxy/local_new";
    // Сессия родилась — её строка в недавних (шаг 6 цепочки).
    parts.recents.add("div", { attrs: { "data-row-key": "code:local_new" }, text: "VkusnoffKz 3" });
  });
  // Меню модели открывается только «как мышью» — pointerdown с buttons:1.
  parts.modelButton.addEventListener("pointerdown", event => {
    if (event.buttons !== 1) return;
    box.menus += 1;
    const menu = loaded.document.body.add("div", { attrs: { role: "menu" } });
    models.forEach((name, index) => {
      const current = `Model: ${name}` === parts.modelButton.getAttribute("aria-label");
      const item = menu.add("div", { attrs: { role: "menuitemradio" }, text: current ? name : `${name}${index + 1}` });
      item.addEventListener("click", () => {
        parts.modelButton.setAttribute("aria-label", `Model: ${name}`);
        menu.remove();
      });
    });
  });
  // Ползунок как у Claude 24.09 (живой гейт WF85): <input type="range"> с шестой ступенью.
  const steps = ["Low", "Medium", "High", "Extra", "Max", "Ultracode"];
  parts.effortButton.addEventListener("pointerdown", event => {
    if (event.buttons !== 1) return;
    const dialog = loaded.document.body.add("div", { attrs: { role: "dialog" } });
    const slider = dialog.add("input", {
      attrs: { type: "range", "aria-valuetext": parts.effortButton.getAttribute("aria-label").slice(8) },
    });
    slider.addEventListener("keydown", key => {
      if (key.key !== "ArrowRight" && key.key !== "ArrowLeft") return;
      box.keys += 1;
      const at = steps.indexOf(slider.getAttribute("aria-valuetext"));
      const next = Math.max(0, Math.min(steps.length - 1, at + (key.key === "ArrowRight" ? 1 : -1)));
      slider.setAttribute("aria-valuetext", steps[next]);
      parts.effortButton.setAttribute("aria-label", `Effort: ${steps[next]}`);
    });
  });
  const store = { calls: [] };
  const value = { popoutWindows: loaded.run("new Map()"), openPopout: options => store.calls.push(options) };
  const hook = () => {};
  hook.getState = () => value;
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  loaded.inner.setModuleImporter(() => Promise.resolve({ Store: hook }));
  return { loaded, parts, box, store };
};
const newChat = (extra = {}) => ({
  id: "n1", action: "new-window", at: "now", scope: "window", title: "Claude",
  x: 100, y: 200, text: "Окно открыто. Жди задачу.", folder: "", name: "", ...extra,
});
// Прогон цепочки: микрозадачи плюс таймеры ожиданий (newWindowWait/Sleep) — самый
// свежий; часы ожиданий (performance.now) идут по 100 мс на круг, иначе срок
// «пункта модели нет» не истёк бы никогда.
const run = async (loaded, rounds = 80) => {
  let clock = loaded.win.performance.now();
  loaded.win.performance.now = () => clock;
  for (let index = 0; index < rounds; index += 1) {
    clock += 100;
    await settle(4);
    const ids = loaded.dom.ids("timeout");
    if (ids.length) loaded.dom.fire(ids[ids.length - 1]);
  }
  await settle();
};

test("подпись пункта модели: цифра клавиши срезается, сверка целиком", () => {
  const { loaded } = home();
  const match = loaded.inner.newWindowModelMatch;
  assert.equal(match("Fable 5.12", "Fable 5.1"), true, "цифра клавиши приклеена в конец");
  assert.equal(match("Opus 5.5", "Opus 5.5"), true, "у текущей цифры нет");
  assert.equal(match("Opus 5.5", "Opus 5"), false, "«Opus 5» ≠ «Opus 5.5»");
  assert.equal(match("Sonnet 53", "Sonnet 5"), true);
  assert.equal(match("Haiku 4.54", "Haiku 4"), false);
});

test("К2: модель и эффорт ставятся до первого сообщения, текст передачи уходит им (попап)", async () => {
  const { loaded, parts, box, store } = home({ record: { text: HANDOFF, to: "pending", handoff: true } });
  loaded.dom.command(newChat({ transfer: true, model: "Fable 5.1", effort: "Extra", sendTransfer: true }));
  await run(loaded);
  const mark = plain(loaded.api.status().newWindow);
  assert.equal(parts.modelButton.getAttribute("aria-label"), "Model: Fable 5.1", "модель встала");
  assert.equal(parts.effortButton.getAttribute("aria-label"), "Effort: Extra", "эффорт встал");
  assert.deepEqual(box.sent, [HANDOFF], "первым сообщением ушёл текст передачи, а не заглушка");
  assert.equal(mark.handoff, "send");
  assert.deepEqual(mark.model.got, { model: "ok", effort: "ok" });
  assert.deepEqual(mark.model.was, { model: "Opus 5.5", effort: "High" }, "прежние — для возврата и гейта");
  assert.equal(mark.model.from, "донор", "в записи модели нет — поля команды");
  const record = stored(loaded);
  assert.deepEqual(Object.keys(record), Object.keys(fixture("record-sent")), "штамп — по эталону record-sent");
  assert.equal(record.sent, true);
  assert.equal(record.to, "local_new");
  assert.equal(store.calls.length, 1, "окно вынесено");
});

test("К2: модель не встала — текст передачи НЕ уходит, уходит заглушка; перенос вставит попап", async () => {
  const { loaded, box } = home({ record: { text: HANDOFF, to: "pending", handoff: true } });
  loaded.dom.command(newChat({ transfer: true, model: "Opus 9", sendTransfer: true }));
  await run(loaded);
  const mark = plain(loaded.api.status().newWindow);
  assert.deepEqual(box.sent, ["Окно открыто. Жди задачу."]);
  assert.equal(mark.model.note, "no-model");
  assert.equal(mark.handoff, "held");
  assert.equal(stored(loaded).sent, false, "запись не помечена — её вставит новый попап");
  assert.ok(loaded.document.body.textContent.includes("Модель «Opus 9» не выбралась — текст передачи не отправлял"), "плашка");
});

test("renew/new-window без sendTransfer: модель не встала — текст ушёл, плашка так и говорит", async () => {
  const { loaded, box } = home();
  loaded.dom.command(newChat({ model: "Opus 9", text: "Продолжай задачу." }));
  await run(loaded);
  assert.deepEqual(box.sent, ["Продолжай задачу."], "текст ушёл первым сообщением");
  const body = loaded.document.body.textContent;
  assert.ok(body.includes("Модель «Opus 9» не выбралась — текст отправлен на той, что стояла"), "плашка");
  assert.equal(body.includes("не отправлял"), false, "неправды про неотправленный текст нет");
});

test("К2: поля model нет (донор на Auto) — модель не трогаем", async () => {
  const { loaded, box } = home({ record: { text: HANDOFF, to: "pending", handoff: true } });
  loaded.dom.command(newChat({ transfer: true, sendTransfer: true }));
  await run(loaded);
  assert.equal(box.menus, 0, "меню модели не открывали");
  assert.deepEqual(box.sent, [HANDOFF]);
});

test("К2 stay: главное окно — текст передачи уходит, попапа и возврата нет, запись стёрта", async () => {
  const { loaded, box, store } = home({ record: { text: HANDOFF, handoff: true } });
  loaded.dom.command(newChat({ model: "Opus 5.5", sendTransfer: true, stay: true }));
  await run(loaded);
  const mark = plain(loaded.api.status().newWindow);
  assert.deepEqual(box.sent, [HANDOFF]);
  assert.equal(store.calls.length, 0, "без openPopout");
  assert.equal(mark.step, "stay");
  assert.equal(mark.state, "ok");
  assert.equal(loaded.win.location.pathname, "/epitaxy/local_new", "новый чат остался в главном окне");
  assert.equal(stored(loaded), null, "запись цепочка стёрла сама");
});

test("К2 stay без блока передачи — заглушку не шлём, остаётся домашний экран", async () => {
  const { loaded, box } = home({ record: { text: "", handoff: true } });
  loaded.dom.command(newChat({ sendTransfer: true, stay: true }));
  await run(loaded);
  assert.deepEqual(box.sent, [], "ничего не отправлено");
  assert.equal(plain(loaded.api.status().newWindow).step, "stay");
  assert.equal(loaded.win.location.pathname, "/epitaxy");
});

// ---- WF85, К7.4: модель и ступень из записи сильнее донорских ----------------
test("К7.4: запись с model/effort (эталон record-handoff-model) — модель из блока, from «блок»", async () => {
  const { at, ...sample } = fixture("record-handoff-model");
  void at;
  const { loaded, parts, box } = home({ record: sample });
  loaded.dom.command(newChat({ transfer: true, model: "Sonnet 5", effort: "High", sendTransfer: true }));
  await run(loaded);
  const mark = plain(loaded.api.status().newWindow);
  assert.equal(parts.modelButton.getAttribute("aria-label"), "Model: Opus 5.5");
  assert.equal(parts.effortButton.getAttribute("aria-label"), "Effort: Low");
  assert.equal(mark.model.from, "блок");
  assert.equal(mark.model.want, "Opus 5.5");
  assert.equal(mark.model.effort, "Low");
  assert.deepEqual(box.sent, [HANDOFF]);
});

test("К7.4 (В5): модели из блока нет в меню — откат на донорскую, текст уходит", async () => {
  const { loaded, parts, box } = home({ record: { text: HANDOFF, to: "pending", handoff: true, model: "Opus 9" } });
  loaded.dom.command(newChat({ transfer: true, model: "Sonnet 5", sendTransfer: true }));
  await run(loaded);
  const mark = plain(loaded.api.status().newWindow);
  assert.equal(parts.modelButton.getAttribute("aria-label"), "Model: Sonnet 5");
  assert.equal(mark.model.from, "донор");
  assert.equal(mark.model.note, "блок: no-model");
  assert.equal(mark.handoff, "send");
  assert.deepEqual(box.sent, [HANDOFF]);
  assert.equal(loaded.document.body.textContent.includes("не выбралась"), false, "плашки нет — модель встала");
});

test("К7.4: донорская модель после отката тоже не встала — текст не уходит, как в К2", async () => {
  const { loaded, box } = home({ record: { text: HANDOFF, to: "pending", handoff: true, model: "Opus 9" } });
  loaded.dom.command(newChat({ transfer: true, model: "Opus 8", sendTransfer: true }));
  await run(loaded);
  const mark = plain(loaded.api.status().newWindow);
  assert.equal(mark.model.note, "no-model");
  assert.equal(mark.handoff, "held");
  assert.deepEqual(box.sent, ["Окно открыто. Жди задачу."]);
});

// #7379: ACK плашки — фактический readback именно родившегося чата.
test('#7379: correlated actual reads resulting model/effort, not requested values', async () => {
  const q = home({ model: 'Opus 5.5', effort: 'High' });
  q.loaded.dom.command(newChat({ id: 'actual-1', model: 'Missing model', effort: 'Extra' }));
  await run(q.loaded);
  assert.deepEqual(plain(q.loaded.api.status().newWindow.actual), {
    commandId: 'actual-1', chat: 'local_new', model: 'Opus 5.5', effort: 'High',
  });
  assert.equal(q.box.sent.length, 1); q.loaded.api.dispose();
});

test('#7379: readback after session birth stays snapshot after main returns', async () => {
  const q = home();
  q.parts.send.addEventListener('click', () => {
    q.parts.modelButton.setAttribute('aria-label', 'Model: Sonnet 5');
    q.parts.effortButton.setAttribute('aria-label', 'Effort: Medium');
  });
  q.loaded.dom.command(newChat({ id: 'actual-born', model: 'Opus 5.5', effort: 'High' }));
  assert.equal(q.loaded.api.status().newWindow.actual, null);
  await run(q.loaded);
  assert.deepEqual(plain(q.loaded.api.status().newWindow.actual), {
    commandId: 'actual-born', chat: 'local_new', model: 'Sonnet 5', effort: 'Medium',
  });
  q.parts.modelButton.setAttribute('aria-label', 'Model: Auto');
  assert.equal(q.loaded.api.status().newWindow.actual.model, 'Sonnet 5'); q.loaded.api.dispose();
});

for (const kind of ['missing', 'long', 'duplicate']) test(`#7379: ${kind} readback stays null, no requested fallback`, async () => {
  const q = home();
  q.parts.send.addEventListener('click', () => {
    if (kind === 'missing') { q.parts.modelButton.remove(); q.parts.effortButton.remove(); }
    if (kind === 'long') {
      q.parts.modelButton.setAttribute('aria-label', 'Model: ' + 'x'.repeat(101));
      q.parts.effortButton.setAttribute('aria-label', 'Effort: ' + 'x'.repeat(33));
    }
    if (kind === 'duplicate') {
      q.loaded.document.body.add('button', { attrs: { 'data-testid': 'epitaxy-cds-model-selector', 'aria-label': 'Model: Other' } });
      q.loaded.document.body.add('button', { attrs: { 'aria-label': 'Effort: Low' } });
    }
  });
  q.loaded.dom.command(newChat({ model: 'Opus 5.5', effort: 'High' })); await run(q.loaded);
  assert.deepEqual(plain(q.loaded.api.status().newWindow.actual), { commandId: 'n1', chat: 'local_new', model: null, effort: null });
  q.loaded.api.dispose();
});

test('#7379: new run clears old ACK; stay without new session remains neutral', async () => {
  const q = home(); q.loaded.dom.command(newChat()); await run(q.loaded);
  assert.equal(q.loaded.api.status().newWindow.actual.chat, 'local_new');
  q.loaded.win.location.pathname = '/epitaxy'; q.parts.input.textContent = '';
  q.loaded.dom.command(newChat({ id: 'actual-stay', stay: true, text: '' }));
  assert.equal(q.loaded.api.status().newWindow.actual, null);
  await run(q.loaded); assert.equal(q.loaded.api.status().newWindow.actual, null); q.loaded.api.dispose();
});

test('#7379: stale session during row await yields no readback ACK', async () => {
  const q = home(); q.loaded.dom.command(newChat());
  for (let i = 0; i < 40 && q.loaded.api.status().newWindow?.step !== 'row'; i++) await Promise.resolve();
  assert.equal(q.loaded.api.status().newWindow.step, 'row');
  q.loaded.win.location.pathname = '/epitaxy/local_other';
  await run(q.loaded); assert.equal(q.loaded.api.status().newWindow.actual, null); q.loaded.api.dispose();
});

test('#7379: terminal popout failure clears captured readback', async () => {
  const q = home(); const store = () => {};
  store.getState = () => ({ popoutWindows: q.loaded.run('new Map()'), openPopout: () => { throw Error('failed'); } });
  q.loaded.inner.setModuleImporter(() => Promise.resolve({ Store: store }));
  q.loaded.dom.command(newChat()); await run(q.loaded);
  assert.equal(q.loaded.api.status().newWindow.state, 'popout-failed');
  assert.equal(q.loaded.api.status().newWindow.actual, null); q.loaded.api.dispose();
});

for (const id of ['', 'x'.repeat(65)]) test(`#7379: invalid command correlation (${id.length} chars) keeps ACK null`, async () => {
  const q = home(); q.loaded.dom.command(newChat({ id })); await run(q.loaded);
  assert.equal(q.loaded.api.status().newWindow.actual, null); q.loaded.api.dispose();
});

for (const action of ['main-chat', 'popout-window']) test(`#7379: new ${action} clears prior completed new-window ACK`, async () => {
  const q = home(); q.loaded.dom.command(newChat()); await run(q.loaded);
  assert.equal(q.loaded.api.status().newWindow.actual.commandId, 'n1');
  q.loaded.win.location.pathname = '/epitaxy/local_new';
  q.loaded.dom.command(newChat({ id: 'next-operation', action, chat: 'local_new' }));
  await run(q.loaded);
  assert.equal(q.loaded.api.status().newWindow.actual, null);
  assert.equal(q.loaded.api.status().newWindow.state, action === 'main-chat' ? 'already' : 'ok');
  q.loaded.api.dispose();
});

test('#7379: canonical helper trims outer whitespace; internal controls are unknown', async () => {
  const q = home();
  q.parts.send.addEventListener('click', () => {
    q.parts.modelButton.setAttribute('aria-label', 'Model: \n Opus 5.5 \t');
    q.parts.effortButton.setAttribute('aria-label', 'Effort: Hi\tgh');
  });
  q.loaded.dom.command(newChat()); await run(q.loaded);
  assert.deepEqual(plain(q.loaded.api.status().newWindow.actual), {
    commandId: 'n1', chat: 'local_new', model: 'Opus 5.5', effort: null,
  }); q.loaded.api.dispose();
});


test('#7379: late store from stale popout cannot erase newer run ACK or open old chat', async () => {
  const q = home();
  const oldCalls = [], newCalls = [];
  const makeStore = calls => {
    const store = () => {};
    const value = { popoutWindows: q.loaded.run('new Map()'), openPopout: options => calls.push(options) };
    store.getState = () => value;
    return store;
  };
  const oldStore = makeStore(oldCalls), currentStore = makeStore(newCalls);
  let releaseOld, imports = 0;
  q.loaded.inner.setModuleImporter(() => ++imports === 1
    ? new Promise(resolve => { releaseOld = resolve; })
    : Promise.resolve({ Store: currentStore }));
  q.loaded.dom.command(newChat({ id: 'old-popout', action: 'popout-window', chat: 'local_old' }));
  await settle();
  assert.equal(typeof releaseOld, 'function', 'old popout is suspended in store lookup');
  q.loaded.dom.command(newChat({ id: 'new-operation' }));
  await run(q.loaded);
  const before = plain(q.loaded.api.status().newWindow);
  assert.equal(before.actual.commandId, 'new-operation');
  assert.equal(newCalls.length, 1);
  releaseOld({ Store: oldStore });
  await settle();
  assert.equal(oldCalls.length, 0, 'superseded operation never opens its chat');
  assert.deepEqual(plain(q.loaded.api.status().newWindow), before, 'new run state and actual stay intact');
  q.loaded.api.dispose();
});


test('#7379: concurrent popout with same token still opens while new-window is busy', async () => {
  const q = home();
  const calls = [], pending = [];
  const store = () => {};
  const value = { popoutWindows: q.loaded.run('new Map()'), openPopout: options => calls.push(options) };
  store.getState = () => value;
  q.loaded.inner.setModuleImporter(() => new Promise(resolve => pending.push(resolve)));
  q.loaded.dom.command(newChat({ id: 'busy-new' }));
  await settle();
  assert.equal(q.loaded.api.status().newWindow.busy, true);
  q.loaded.dom.command(newChat({ id: 'concurrent-popout', action: 'popout-window', chat: 'local_existing' }));
  await settle();
  assert.equal(pending.length, 2);
  pending[1]({ Store: store });
  await settle();
  assert.equal(calls.length, 1, 'same-token popout is allowed before new-window lookup completes');
  assert.equal(q.loaded.api.status().newWindow.busy, true, 'popout does not release the new-window operation');
  pending[0]({ Store: store });
  await run(q.loaded);
  assert.equal(calls.length, 2);
  assert.equal(q.loaded.api.status().newWindow.actual.commandId, 'busy-new');
  q.loaded.api.dispose();
});
