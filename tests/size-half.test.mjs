// Половина размера текста (WF19): у КОМАНДЫ половина знает три состояния —
// поля нет, число, ровно null (снять только её), — а в хранилище по-прежнему
// два. Перенесено из скретч-теста волны WF19.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, injectSource, plain } from "./load.mjs";

const MAP_KEY = "myclaude-themes-v1";
const { inner } = loadInner({ title: "Trelvis" });
const parse = value => plain(inner.normalizeSizeCommand(value));

// Слияние с базой идёт внутри команды темы, поэтому проверяем его настоящим
// путём: положили базу в карту, прислали команду, прочитали запись.
const commit = (base, value) => {
  const loaded = loadInject({
    title: "Trelvis",
    storage: { local: { [MAP_KEY]: JSON.stringify({ "chat:Trelvis": base ? { size: base } : {} }) } },
  });
  loaded.dom.command({ id: "s1", action: "theme", at: "now", scope: "window", title: "Trelvis", size: value });
  const map = JSON.parse(loaded.win.localStorage.getItem(MAP_KEY) ?? "{}");
  return map["chat:Trelvis"]?.size ?? null;
};

test("три состояния половины в команде", () => {
  assert.deepEqual(parse({ answer: 16 }), { answer: 16 }, "поля question нет — половину не трогаем");
  assert.deepEqual(parse({ answer: 16, question: 12 }), { answer: 16, question: 12 });
  assert.deepEqual(Object.keys(parse({ question: 12, answer: 16 })), ["answer", "question"], "порядок ключей");
  assert.deepEqual(parse({ answer: null }), { answer: null }, "null — снятие этой половины");
  assert.deepEqual(parse({ question: null }), { question: null });
  assert.deepEqual(parse({ answer: null, question: null }), { answer: null, question: null });
});

test("мусор равен отсутствию поля, а не снятию", () => {
  assert.equal(parse({ answer: "abc" }), null, "одна строка — полный сброс слоя");
  assert.deepEqual(parse({ answer: "abc", question: null }), { question: null }, "мусор рядом со снятием не путается");
  assert.equal(parse({ answer: 0 }), null);
  assert.equal(parse({ answer: 99 }), null);
  assert.equal(parse({ answer: undefined }), null, "undefined — не снятие");
  assert.deepEqual(parse({ answer: 15.6 }), { answer: 16 }, "дробное округляется");
  assert.equal(parse({}), null);
  assert.equal(parse(null), null);
  assert.equal(parse([16]), null);
  assert.equal(parse("16"), null);
});

test("слияние с базой: снятая половина уходит, вторая живёт", () => {
  assert.deepEqual(commit({ answer: 14, question: 12 }, { answer: 18 }), { answer: 18, question: 12 });
  assert.deepEqual(commit({ answer: 18, question: 12 }, { answer: null }), { question: 12 });
  assert.deepEqual(commit({ answer: 18, question: 12 }, { question: null }), { answer: 18 });
  assert.equal(commit({ question: 12 }, { question: null }), null, "сняли последнюю половину — слоя нет");
  assert.equal(commit({ answer: 18, question: 12 }, { answer: null, question: null }), null);
  assert.deepEqual(commit({ question: 12 }, { answer: null }), { question: 12 }, "снятие половины, которой не было");
  assert.equal(commit(null, { answer: null }), null, "база пуста, снятие — слоя нет");
  assert.deepEqual(commit(null, { question: 12 }), { question: 12 });
  assert.deepEqual(commit({ answer: 18, question: 12 }, { answer: null, question: 20 }), { question: 20 },
    "снять одну и поставить другую разом");
  assert.equal(commit({ answer: 18, question: 12 }, null), null, "полный сброс командой null");
});

test("в хранилище не уходит ни одного null", () => {
  for (const [base, value] of [
    [{ answer: 18, question: 12 }, { answer: null }],
    [{ answer: 18, question: 12 }, { question: null }],
    [{ answer: 18 }, { answer: null, question: 14 }],
  ]) {
    const out = commit(base, value);
    const nulls = out ? Object.entries(out).filter(([, item]) => item == null).map(([key]) => key) : [];
    assert.deepEqual(nulls, [], `после ${JSON.stringify(value)} в записи остались пустые половины`);
  }
});

test("на экране половины тоже независимы", () => {
  const loaded = loadInject({
    title: "Trelvis",
    storage: { local: { [MAP_KEY]: JSON.stringify({ "chat:Trelvis": { size: { answer: 18, question: 12 } } }) } },
  });
  assert.equal(loaded.api.status().size.answer, 18);
  assert.equal(loaded.api.status().size.question, 12);
  loaded.dom.command({ id: "s2", action: "theme", at: "now", scope: "window", title: "Trelvis", size: { answer: null } });
  assert.equal(loaded.api.status().size.answer, null, "размер ответов снят");
  assert.equal(loaded.api.status().size.question, 12, "размер вопросов на месте");
});

test("normalizeSize и карта слоёв WF19 не тронуты — тристейт в хранилище не течёт", () => {
  const source = injectSource();
  for (const piece of [
    "const normalizeSize = value => {",
    "    const answer = sizePx(value.answer);\n    const question = sizePx(value.question);",
    "    theme: normalizeTheme, font: normalizeFont, size: normalizeSize, frame: normalizeFrame,",
  ]) assert.ok(source.includes(piece), `в inject.js пропал кусок: ${piece.slice(0, 40)}…`);
  assert.match(source, /const VERSION = "wf\d+-[a-z]-\d+";/, "метка версии на месте");
});
