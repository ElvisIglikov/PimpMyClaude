// WF107, батч Б2 (#8126, контракт К2): размер шрифта в поле ввода — один на все окна.
//
// Команда Swift → все страницы: {id, action:"composer-font", at, px:N|null}; N — целое
// 11…32, null — «Как у Claude», прочее — мусор. Примерки (preview:true) нет с WF248 П2: её слало
// только меню жёлтой кнопки (лист 48 · 2.1) — такая команда мимо. Событие storage ставит размер из
// другого окна. Страница → приложение: GET /composer-font?px=<N|none>&chat=<id> после колеса и раз
// при загрузке.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const KEY = "myclaude-composer-font-size-v1";
const MAP_KEY = "myclaude-themes-v1";
const CHAT = "local_test";
const font = editor => editor.style.getPropertyValue("font-size");
const theme = (id, accent) => ({
  id, name: id, type: "dark",
  palette: { accent, background: "#001122", foreground: "#eeffff", sidebar: "#000811", panel: "#00223a", muted: "#88aabb" },
});

// fetchLog — массив: fetch есть уже на загрузке (запрос загрузки); нет — fetch нет вовсе.
const page = ({ stored = null, fetchLog = null, href = `https://claude.ai/epitaxy/${CHAT}`, title = "Trelvis", storage = {} } = {}) => {
  const loaded = loadInject({
    href, title,
    storage: { local: { ...(stored == null ? {} : { [KEY]: String(stored) }), ...storage } },
    html: dom => {
      if (fetchLog) dom.window.fetch = url => { fetchLog.push(url); return Promise.resolve({}); };
      const parts = dom.composer({ text: "черновик" });
      parts.editor.computed["font-size"] = "16px";
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return loaded;
};
let seq = 0;
const command = (loaded, detail) => loaded.dom.command({ id: `wf107-${++seq}`, action: "composer-font", at: "now", ...detail });
const themeCommand = (loaded, detail) => loaded.dom.command({ id: `wf107-${++seq}`, action: "theme", at: "now", scope: "window", title: "Trelvis", ...detail });
const status = loaded => plain(loaded.api.status().composerFont);
const pass = loaded => { loaded.dom.fireKind("timeout"); loaded.dom.fireKind("raf"); };
const wheel = loaded => loaded.win.dispatchEvent({
  type: "keydown", code: "BracketRight", key: "ъ", ctrlKey: true, altKey: true, metaKey: true, shiftKey: false,
  target: loaded.parts.editor,
});
const pings = log => log.filter(url => url.includes("/composer-font?"));

test("команда ставит px и localStorage во всех окнах, null снимает инлайн-стиль и ключ", () => {
  const loaded = page();
  command(loaded, { px: 18 });
  assert.equal(font(loaded.parts.editor), "18px");
  assert.equal(loaded.win.localStorage.getItem(KEY), "18");
  assert.deepEqual(status(loaded), { px: 18, pinged: 0 });
  command(loaded, { px: null });
  assert.equal(font(loaded.parts.editor), "");
  assert.equal(loaded.parts.editor.getAttribute("data-myclaude-composer-font"), null);
  assert.equal(loaded.win.localStorage.getItem(KEY), null);
  assert.equal(status(loaded).px, null);
});

test("мусор (10, 33, \"abc\", \"18\", 12.5, нет px) — ничего", () => {
  const loaded = page({ stored: 20 });
  for (const detail of [{ px: 10 }, { px: 33 }, { px: "abc" }, { px: "18" }, { px: 12.5 }, {}]) {
    command(loaded, detail);
    assert.equal(font(loaded.parts.editor), "20px", JSON.stringify(detail));
    assert.equal(loaded.win.localStorage.getItem(KEY), "20");
  }
  command(loaded, { px: 11 });
  assert.equal(font(loaded.parts.editor), "11px", "нижняя граница — годится");
  command(loaded, { px: 32 });
  assert.equal(font(loaded.parts.editor), "32px", "верхняя граница — годится");
});

// WF248 П2: меню жёлтой кнопки снято, примерку размера поля никто не шлёт. Команда с preview:true (старое
// приложение) — мимо: ни поля, ни хранилища; примерка темы (её шлёт панель PMP мышью по цветам) и размер поля
// друг друга больше не трогают.
test("WF248 П2: примерки размера поля нет — preview:true мимо, примерка темы размер поля не трогает", () => {
  const SAVED = theme("сохранённая", "#2299ff");
  const loaded = page({ stored: 15, storage: { [MAP_KEY]: JSON.stringify({ "chat:Trelvis": { theme: SAVED } }) } });
  for (const detail of [{ preview: true, title: "Trelvis", chat: CHAT, px: 24 }, { preview: true, title: "Trelvis", px: null }]) {
    command(loaded, detail);
    assert.equal(font(loaded.parts.editor), "15px", JSON.stringify(detail));
    assert.equal(loaded.win.localStorage.getItem(KEY), "15", "хранилище не тронуто");
  }
  assert.deepEqual(status(loaded), { px: 15, pinged: 0 }, "поля preview в status() больше нет");
  themeCommand(loaded, { preview: true, theme: theme("пудра", "#ee88aa") });
  assert.equal(loaded.api.status().theme.source, "preview");
  command(loaded, { px: 19 });
  assert.equal(font(loaded.parts.editor), "19px");
  assert.equal(loaded.api.status().preview, true, "выбор размера поля примерку темы не снимает");
  themeCommand(loaded, { preview: false });
  assert.equal(loaded.api.status().theme.id, "сохранённая");
  assert.equal(font(loaded.parts.editor), "19px", "конец примерки темы размер поля не трогает");
  themeCommand(loaded, { theme: theme("новая", "#11aa44") });
  assert.equal(font(loaded.parts.editor), "19px", "выбор темы размер поля не трогает");
});

test("storage из другого окна ставит размер сразу", () => {
  const loaded = page({ stored: 15 });
  loaded.win.localStorage.setItem(KEY, "21");
  loaded.win.dispatchEvent({ type: "storage", key: KEY });
  assert.equal(font(loaded.parts.editor), "21px");
  loaded.win.dispatchEvent({ type: "storage", key: "чужой-ключ" });
  assert.equal(font(loaded.parts.editor), "21px");
  // Хранилище очищено целиком (key null) — как у Claude.
  loaded.win.localStorage.removeItem(KEY);
  loaded.win.dispatchEvent({ type: "storage", key: null });
  assert.equal(font(loaded.parts.editor), "");
  // dispose снимает слушатель.
  loaded.api.dispose();
  loaded.win.localStorage.setItem(KEY, "25");
  loaded.win.dispatchEvent({ type: "storage", key: KEY });
  assert.equal(font(loaded.parts.editor), "");
});

test("колесо шлёт /composer-font?px=N&chat=…; команда и storage не шлют (петли нет)", async () => {
  const log = [];
  const loaded = page({ stored: 16, fetchLog: log });
  assert.deepEqual(pings(log), [`http://127.0.0.1:47615/composer-font?px=16&chat=${CHAT}`], "запрос загрузки");
  assert.equal(wheel(loaded), false);
  assert.equal(font(loaded.parts.editor), "17px");
  assert.equal(pings(log).at(-1), `http://127.0.0.1:47615/composer-font?px=17&chat=${CHAT}`);
  command(loaded, { px: 20 });
  loaded.win.localStorage.setItem(KEY, "22");
  loaded.win.dispatchEvent({ type: "storage", key: KEY });
  pass(loaded);
  assert.equal(pings(log).length, 2);
  assert.equal(status(loaded).pinged, 2);
});

test("без id чата — запросов нет; fetch бросает — колесо работает", () => {
  const log = [];
  const loaded = page({ stored: 16, fetchLog: log, href: "https://claude.ai/new" });
  wheel(loaded);
  pass(loaded);
  assert.equal(font(loaded.parts.editor), "17px");
  assert.deepEqual(pings(log), []);
  assert.equal(status(loaded).pinged, 0);

  const broken = page({ stored: 16 });
  broken.win.fetch = () => { throw new Error("нет сети"); };
  assert.equal(wheel(broken), false);
  assert.equal(font(broken.parts.editor), "17px");
  assert.equal(status(broken).pinged, 0);
});

test("загрузка: с сохранённым — один запрос px=N, без — один px=none", () => {
  const log = [];
  const loaded = page({ stored: 23, fetchLog: log });
  for (let i = 0; i < 3; i++) { loaded.win.dispatchEvent({ type: "resize" }); pass(loaded); }
  assert.deepEqual(pings(log), [`http://127.0.0.1:47615/composer-font?px=23&chat=${CHAT}`]);
  assert.equal(status(loaded).pinged, 1);

  const empty = [];
  const bare = page({ fetchLog: empty });
  pass(bare);
  assert.deepEqual(pings(empty), [`http://127.0.0.1:47615/composer-font?px=none&chat=${CHAT}`]);
  // Приложение отвечает зеркалом — команда встаёт, второго запроса нет.
  command(bare, { px: 18 });
  pass(bare);
  assert.equal(font(bare.parts.editor), "18px");
  assert.equal(pings(empty).length, 1);
});

test("перезапись inject.js: новый экземпляр — снова один запрос загрузки, слушатели не копятся", () => {
  const log = [];
  const loaded = page({ stored: 19, fetchLog: log });
  const listeners = loaded.counters.listeners;
  assert.equal(loaded.reload().error, null);
  assert.equal(font(loaded.parts.editor), "19px");
  assert.equal(pings(log).length, 2);
  assert.equal(loaded.counters.listeners, listeners);
});
