// Адресация окна (WF15): у команды со scope:"window" есть необязательное поле
// match — путь страницы. Есть строка → окно сверяет location.pathname; поля нет
// → старое поведение по заголовку и фокусу. Перенесено из скретч-теста WF15.
//
// Проверяем настоящим путём: шлём команду «Workflow» в окно с полем ввода и
// смотрим, взяло ли окно её. Взяло — значит addressed() сказал «моя».
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const taken = (detail, window = {}) => {
  const loaded = loadInject({
    html: "composer",
    title: window.title ?? "Привет",
    href: window.href ?? "https://claude.ai/epitaxy/local_aaa",
    hasFocus: window.hasFocus ?? false,
  });
  loaded.dom.command({ id: "w", action: "workflow", at: "now", scope: "window", text: "текст запуска", ...detail });
  return loaded.api.status().workflow.runs === 1;
};

test("без поля match команда адресуется заголовком", () => {
  assert.equal(taken({ title: "Привет" }), true, "заголовок совпал");
  assert.equal(taken({ title: "  Привет  " }), true, "пробелы по краям не мешают");
  assert.equal(taken({ title: "Другой" }), false, "чужой заголовок");
  assert.equal(taken({ title: "" }), false, "пустой заголовок без фокуса");
  assert.equal(taken({ title: 7 }), false, "заголовок не строка");
  assert.equal(taken({}), false, "поля title нет, фокуса нет");
});

test("фокус — запасной критерий, когда заголовка в команде нет", () => {
  assert.equal(taken({}, { hasFocus: true }), true, "поля title нет, зато окно под фокусом");
  assert.equal(taken({ title: "   " }, { hasFocus: true }), true, "пустой заголовок — смотрим фокус");
  assert.equal(taken({ title: "Другой" }, { hasFocus: true }), false, "заголовок прислали чужой — фокус не спасает");
});

test("поле match сверяется с путём страницы", () => {
  const main = { title: "Claude", href: "https://claude.ai/epitaxy/local_f44e46bb" };
  assert.equal(taken({ match: "/epitaxy/local_f44e46bb" }, main), true);
  assert.equal(taken({ match: "/epitaxy/local_zzz" }, main), false);
  assert.equal(taken({ match: "/epitaxy/local_zzz", title: "Claude" }, main), false, "match сильнее заголовка");
  assert.equal(taken({ match: "/epitaxy/local_f44e46bb", title: "Чужой" }, main), true, "match сильнее чужого имени");
  assert.equal(taken({ match: "" }, main), false, "пустая строка путём не бывает");
});

test("не-строковый match включает старое поведение", () => {
  const main = { title: "Claude", href: "https://claude.ai/epitaxy/local_f44e46bb" };
  assert.equal(taken({ match: null, title: "Claude" }, main), true);
  assert.equal(taken({ match: undefined, title: "Claude" }, main), true);
  assert.equal(taken({ match: 42, title: "Чужой" }, main), false);
  assert.equal(taken({ match: null }, { ...main, hasFocus: true }), true, "title нет, фокус есть");
});

test("попап about:blank чужой match не ловит, а заглушку-заголовок ловит", () => {
  const popup = { title: "Claude", href: "about:blank" };
  assert.equal(taken({ match: "/epitaxy/local_f44e46bb" }, popup), false, "путь главного окна попапу не подходит");
  assert.equal(taken({ title: "Claude" }, popup), true, "старый путь по заголовку работает");
});
