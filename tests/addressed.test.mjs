// Адресация окна (WF15): у команды со scope:"window" есть необязательное поле
// match — путь страницы. Есть строка → окно сверяет location.pathname; поля нет
// → старое поведение по заголовку и фокусу. Перенесено из скретч-теста WF15.
// WF29 добавил между ними поле chat — id чата страницы (раздел 12в inject.js).
//
// Проверяем настоящим путём: шлём команду «Workflow» в окно с полем ввода и
// смотрим, взяло ли окно её. Взяло — значит addressed() сказал «моя».
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const window29 = window => ({
  html: "composer",
  title: window.title ?? "Привет",
  href: window.href ?? "https://claude.ai/epitaxy/local_aaa",
  hasFocus: window.hasFocus ?? false,
  storage: window.storage,
  opener: window.opener,
});

const taken = (detail, window = {}) => {
  const loaded = loadInject(window29(window));
  loaded.dom.command({ id: "w", action: "workflow", at: "now", scope: "window", text: "текст запуска", ...detail });
  return loaded.api.status().workflow.runs === 1;
};

// Кэш id чата попапа: ровно та запись, которую кладёт ответ родителя.
const chatCache = (title, id = "local_c4abc832") =>
  ({ session: { "myclaude-chat-v1": JSON.stringify({ id, title }) } });

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

test("поле chat адресует окно по id чата", () => {
  const main = { title: "Claude", href: "https://claude.ai/epitaxy/local_f44e46bb" };
  assert.equal(taken({ chat: "local_f44e46bb" }, main), true, "свой id");
  assert.equal(taken({ chat: "local_zzz" }, main), false, "чужой id");
  assert.equal(taken({ chat: "" }, main), false, "пустая строка адресом не бывает");
  assert.equal(taken({ chat: "local_f44e46bb" }, { ...main, href: "https://claude.ai/epitaxy" }), false,
    "своего id у страницы нет вовсе — команда не наша");
  assert.equal(taken({ chat: null, title: "Claude" }, main), true, "не строка — старое поведение");
  assert.equal(taken({ chat: undefined, title: "Claude" }, main), true, "поля нет — старое поведение");
  assert.equal(taken({ chat: 42, title: "Чужой" }, main), false, "не строка — старое поведение");
});

test("chat сильнее заголовка, match сильнее chat", () => {
  const main = { title: "Claude", href: "https://claude.ai/epitaxy/local_f44e46bb" };
  assert.equal(taken({ chat: "local_f44e46bb", title: "Чужой" }, main), true, "чужое имя при своём id — взята");
  assert.equal(taken({ chat: "local_zzz", title: "Claude" }, main), false, "своё имя при чужом id — не взята");
  assert.equal(taken({ match: "/epitaxy/local_f44e46bb", chat: "local_zzz" }, main), true, "решает match");
  assert.equal(taken({ match: "/epitaxy/local_zzz", chat: "local_f44e46bb" }, main), false, "решает match");
});

test("попап ловит команду по chat из кэша id", () => {
  const popup = { title: "Bro Flow продолжение", href: "about:blank" };
  assert.equal(taken({ chat: "local_c4abc832" }, { ...popup, storage: chatCache("Bro Flow продолжение") }), true,
    "кэш наполнен — команда взята (по match попап её не поймал бы вовсе)");
  assert.equal(taken({ chat: "local_c4abc832" }, popup), false,
    "кэша нет — команда не наша: addressed синхронный, ждать ответа родителя нечем");
  assert.equal(taken({ chat: "local_c4abc832" }, { ...popup, storage: chatCache("Старое имя") }), false,
    "заголовок окна сменился — кэш не применяется");
  assert.equal(taken({ chat: "local_zzz" }, { ...popup, storage: chatCache("Bro Flow продолжение") }), false,
    "чужой id");
});

test("перезапуск инжекта кэш id не стирает", () => {
  const loaded = loadInject({
    html: "composer",
    title: "Bro Flow продолжение",
    href: "about:blank",
    hasFocus: false,
    storage: chatCache("Bro Flow продолжение"),
  });
  // Ровно то, что делает лоадер после `cp` живого файла: тот же файл в том же
  // окне ещё раз. Замыкание при этом новое, а sessionStorage — прежний.
  loaded.reload();
  loaded.dom.command({
    id: "w2", action: "workflow", at: "now", scope: "window", text: "текст запуска", chat: "local_c4abc832",
  });
  assert.equal(loaded.api.status().workflow.runs, 1, "команда по chat взята и после перезапуска инжекта");
  assert.equal(loaded.api.status().chat.self, "local_c4abc832");
});
