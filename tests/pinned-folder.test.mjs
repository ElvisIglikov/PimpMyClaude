// Папка проекта у закреплённых чатов (раздел 2е inject.js, WF82, #7102).
//
// Слово Элвиса 22.09: у закреплённых «непонятно, к кому относится… папку в начале
// имени, как в шапке». Стенд — как Claude 2.2553.13 по разведке WF82: строка
// [data-row-key="code:<id>"] → [data-row-label] > .dframe-fade-label > имя; в
// React-волокне строки пропс session с ref.id и source.data (repoInfo, cwd).
// Страница ставит на подпись атрибут data-myclaude-folder, чип рисует CSS
// (::before с attr()), текст строки не меняется.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const ATTR = "data-myclaude-folder";
const STYLE = "#myclaude-input-handle-style";

const addRow = (list, id, title, data, extra = {}) => {
  const row = list.add("div", { attrs: { "data-row-key": `code:${id}` } });
  const button = row.add("div", { attrs: { "data-row": "" } }).add("button", { attrs: { "data-row-main-button": "" } });
  const label = button.add("span", { attrs: { "data-row-label": "" } }).add("span", { class: "dframe-fade-label" });
  label.add("span", { class: "inline-block", text: title });
  const session = { ref: { kind: "code", id }, title, source: { kind: "code", data }, ...extra };
  row["__reactFiber$test"] = { memoizedProps: {}, return: { memoizedProps: { session }, return: null } };
  return { row, button, label };
};

const page = ({ href = "https://claude.ai/epitaxy/local_home", pinned = [], recents = [], hatch = {}, local = {} } = {}) => {
  const rows = {};
  const loaded = loadInject({
    href,
    title: "Claude",
    hatch,
    storage: { local },
    html: dom => {
      const parts = dom.composer();
      const bar = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
      const pin = bar.add("div", { attrs: { "data-testid": "sidebar-pinned" } });
      const recent = bar.add("div", { attrs: { "data-testid": "sidebar-recents" } });
      for (const [id, title, data, extra] of pinned) rows[id] = addRow(pin, id, title, data, extra);
      for (const [id, title, data, extra] of recents) rows[id] = addRow(recent, id, title, data, extra);
      rows.pin = pin;
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return { loaded, rows };
};
// Проход раскладки: он и ставит чип (своего наблюдателя у раздела нет).
const pass = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const repo = (name, cwd = `/Users/dev/Projects/${name}`) => ({ cwd, repoInfo: { owner: "ElvisIglikov", name, branch: "main" } });

test("закреплённый чат получает папку проекта — имя репозитория, как у чипа в шапке", () => {
  const { rows } = page({
    pinned: [
      ["local_a", "Ночь кода", repo("VkusnoffKz")],
      ["local_b", "Dropdown и боковой режим", repo("PimpMyClaude")],
    ],
  });
  assert.equal(rows.local_a.label.getAttribute(ATTR), "VkusnoffKz");
  assert.equal(rows.local_b.label.getAttribute(ATTR), "PimpMyClaude");
});

test("репозитория нет — имя папки; нет и папки — чипа нет", () => {
  const { rows } = page({
    pinned: [
      ["local_a", "Без git", { cwd: "/Users/dev/Projects/Rick/" }],
      ["local_b", "Пустая сессия", {}],
    ],
  });
  assert.equal(rows.local_a.label.getAttribute(ATTR), "Rick", "хвостовой слэш путь не меняет");
  assert.equal(rows.local_b.label.hasAttribute(ATTR), false, "не знаем папку — не рисуем");
});

test("текст строки не меняется: имя чата читают переименование и обход", () => {
  const { loaded, rows } = page({ pinned: [["local_a", "Ночь кода", repo("VkusnoffKz")]] });
  assert.equal(rows.local_a.row.textContent, "Ночь кода");
  assert.equal(loaded.inner.newWindowRow("local_a", true), rows.local_a.row, "строка находится по-прежнему");
});

test("список недавних и попап не трогаются", () => {
  const { rows } = page({
    pinned: [["local_a", "Закреплённый", repo("VkusnoffKz")]],
    recents: [["local_r", "Недавний", repo("Dictator")]],
  });
  assert.equal(rows.local_r.label.hasAttribute(ATTR), false, "Recents у Claude и так разбит по проектам");
  const popout = loadInject({
    href: "about:blank",
    title: "Попап",
    html: dom => {
      const pin = dom.document.body.add("div", { attrs: { "data-testid": "sidebar-pinned" } });
      rows.popout = addRow(pin, "local_p", "Попап", repo("Geyboard"));
    },
  });
  assert.equal(popout.error, null);
  assert.equal(rows.popout.label.hasAttribute(ATTR), false, "у попапа своего списка слева нет");
});

test("React пересоздал подпись — чип встаёт заново на следующем проходе; dispose снимает", () => {
  const { loaded, rows } = page({ pinned: [["local_a", "Ночь кода", repo("VkusnoffKz")]] });
  const { button, label } = rows.local_a;
  label.remove();
  const fresh = button.querySelector("[data-row-label]").add("span", { class: "dframe-fade-label" });
  fresh.add("span", { class: "inline-block", text: "Ночь кода" });
  assert.equal(fresh.hasAttribute(ATTR), false);
  pass(loaded);
  assert.equal(fresh.getAttribute(ATTR), "VkusnoffKz");
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`[${ATTR}]`).length, 0, "dispose оставил метки папки");
});

test("чип рисует CSS из атрибута — только в Pinned, с многоточием на узкой панели", () => {
  const { loaded } = page();
  const css = String(loaded.dom.query(STYLE).textContent ?? "");
  const rule = css.split("\n").find(line => line.includes(`[${ATTR}]::before`));
  assert.ok(rule, "правила чипа нет");
  assert.ok(rule.startsWith('[data-testid="sidebar-pinned"] '), "чип только у закреплённых");
  assert.match(rule, new RegExp(`content:attr\\(${ATTR}\\)`), "текст чипа — из атрибута, не из разметки");
  assert.match(rule, /text-overflow:ellipsis/, "длинное имя режется многоточием (#6625)");
  assert.match(rule, /max-width:\d+%/, "чип не съедает имя чата целиком");
});

// Переменная цвета плашки проекта (#7213, снята в WF248 вместе с цветом — слово Элвиса 11.10 01:40).
const TINT = "--myclaude-folder-tint";
const MAP_KEY = "myclaude-themes-v1";

// ---- page-64: имя папки без цвета и мелко, часиков нет (слово Элвиса 11.10 01:40) ----
// «названия проектов не надо цветом выводить… сделай маленькими… А таймеры убери, это уже
// неактуальная тема».
const CLOCK = "data-myclaude-clock";
const LATE = "data-myclaude-clock-late";
const T0 = 1_790_000_000_000;
const rowLabel = row => row.row.querySelector("[data-row-label]");

test("page-64: имя папки — без цвета проекта: переменной цвета на подписи нет, правило — мелко и без заливки", () => {
  const palette = accent => ({ theme: { id: "x", name: "x", type: "dark",
    palette: { accent, background: "#111111", foreground: "#eeeeee", sidebar: "#0a0a0a", panel: "#1a1a1a", muted: "#888888" } } });
  const { loaded, rows } = page({
    local: { [MAP_KEY]: JSON.stringify({ "id:local_a": palette("#ff8800") }) },
    pinned: [["local_a", "Ночь кода", repo("VkusnoffKz")], ["local_c", "Пимп", repo("PimpMyClaude")]],
  });
  pass(loaded);
  assert.equal(rows.local_a.label.getAttribute(ATTR), "VkusnoffKz", "имя папки на месте");
  assert.equal(rows.local_a.label.style.getPropertyValue(TINT), "", "цвета проекта нет и у окрашенного чата");
  assert.equal(rows.local_c.label.style.getPropertyValue(TINT), "", "авто-тона папки нет");
  const rule = String(loaded.dom.query(STYLE).textContent ?? "").split("\n").find(line => line.includes(`[${ATTR}]::before`));
  assert.match(rule, /font-size:10px/, "мелко");
  assert.match(rule, /color:var\(--cds-text-secondary\)/, "приглушённый тон текста темы");
  assert.doesNotMatch(rule, /padding|border-radius|alpha-2/, "плашки нет");
  assert.doesNotMatch(rule, /background-color|folder-tint/, "и подложки цветом проекта нет");
});

test("page-64: часиков у закреплённых нет — ни меток, ни правил; секундный тик их не ставит", () => {
  const { loaded, rows } = page({
    pinned: [["local_a", "Ночь кода", repo("VkusnoffKz"), { updatedAtMs: Date.now() - 5 * 60_000 }],
      ["local_b", "Давний", repo("Rick"), { updatedAtMs: T0 }]],
  });
  pass(loaded);
  loaded.dom.fireKind("interval");
  assert.equal(loaded.dom.queryAll(`[data-row-label][${CLOCK}],[${LATE}]`).length, 0, "меток часиков нет");
  assert.equal(rows.local_a.row.textContent, "Ночь кода");
  const css = String(loaded.dom.query(STYLE).textContent ?? "");
  assert.ok(!css.includes(`[data-row-label][${CLOCK}`), "правил часиков строк в таблице нет");
  assert.equal(loaded.inner.markPinnedClocks, undefined, "прохода часиков в странице нет");
});

test("page-64: метки часиков и ключ «таймер выключен» прошлой страницы убираются при установке", () => {
  let label = null;
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_home",
    title: "Claude",
    storage: { local: { "myclaude.pinnedClockOff": "1", "myclaude.pinnedFolderOff": "1" } },
    html: dom => {
      const parts = dom.composer();
      const pin = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } }).add("div", { attrs: { "data-testid": "sidebar-pinned" } });
      label = rowLabel(addRow(pin, "local_a", "Ночь кода", repo("VkusnoffKz"), { updatedAtMs: T0 }));
      // Сирота прошлой страницы: её метки остались на подписи (страница упала, не сняв своё).
      label.setAttribute(CLOCK, "0:00");
      label.setAttribute(LATE, "");
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  assert.equal(label.hasAttribute(CLOCK), false, "метка часиков снята");
  assert.equal(label.hasAttribute(LATE), false);
  assert.equal(loaded.win.localStorage.getItem("myclaude.pinnedClockOff"), null, "ключ таймера убран");
  assert.equal(loaded.win.localStorage.getItem("myclaude.pinnedFolderOff"), "1", "настройка имени папки цела");
});

// ---- настройка «Закреплённые» (#8743) -----------------------------------------
// Слово Элвиса 04.10: «настройку, чтобы эти штучки можно было отключить… показывать
// или нет название проекта и таймер». Команда `pinned-look` {folder: "true"|"false"};
// в localStorage — только «выключено». Таймера с page-64 нет: поле clock принимается
// и ничего не меняет; в status().pinnedLook только folder (поле clock снято в WF248).
const look = loaded => ({ ...loaded.api.status().pinnedLook });

test("#8743: без настройки имя папки показывается; таймера нет", () => {
  const { loaded, rows } = page({ pinned: [["local_a", "Ночь кода", repo("VkusnoffKz"), { updatedAtMs: T0 }]] });
  assert.deepEqual(look(loaded), { folder: true });
  assert.equal(rows.local_a.label.getAttribute(ATTR), "VkusnoffKz");
  assert.equal(rowLabel(rows.local_a).hasAttribute(CLOCK), false);
});

test("#8743: название проекта выключается и включается сразу", () => {
  const { loaded, rows } = page({ pinned: [["local_a", "Ночь кода", repo("VkusnoffKz"), { updatedAtMs: Date.now() }]] });
  loaded.dom.command({ action: "pinned-look", folder: "false", clock: "true" });
  assert.deepEqual(look(loaded), { folder: false });
  assert.equal(rows.local_a.label.hasAttribute(ATTR), false, "чип снят без ожидания прохода");
  pass(loaded);
  assert.equal(rows.local_a.label.hasAttribute(ATTR), false, "проход раскладки чип не возвращает");
  assert.equal(rows.local_a.row.textContent, "Ночь кода", "текст строки не меняется");
  loaded.dom.command({ action: "pinned-look", folder: "true", clock: "true" });
  assert.equal(rows.local_a.label.getAttribute(ATTR), "VkusnoffKz", "включили — чип на месте");
});

test("#8743: поле clock команды ничего не включает и в хранилище не пишет", () => {
  const { loaded, rows } = page({ pinned: [["local_a", "Ночь кода", repo("VkusnoffKz"), { updatedAtMs: Date.now() }]] });
  const label = rowLabel(rows.local_a);
  for (const clock of ["true", "false"]) {
    loaded.dom.command({ action: "pinned-look", folder: "true", clock });
    loaded.dom.fireKind("interval");
    assert.deepEqual(look(loaded), { folder: true });
    assert.equal(label.hasAttribute(CLOCK), false, "часиков нет при любом значении");
    assert.equal(loaded.win.localStorage.getItem("myclaude.pinnedClockOff"), null);
  }
  assert.equal(rows.local_a.label.getAttribute(ATTR), "VkusnoffKz", "название осталось");
});

test("#8743: поле без «true»/«false» ничего не меняет; в хранилище — только «выключено»", () => {
  const { loaded, rows } = page({ pinned: [["local_a", "Ночь кода", repo("VkusnoffKz"), { updatedAtMs: Date.now() }]] });
  loaded.dom.command({ action: "pinned-look", folder: 1, clock: "нет" });
  assert.deepEqual(look(loaded), { folder: true }, "мусор ничего не меняет");
  loaded.dom.command({ action: "pinned-look", folder: "false" });
  assert.deepEqual(look(loaded), { folder: false });
  assert.equal(loaded.win.localStorage.getItem("myclaude.pinnedFolderOff"), "1");
  assert.equal(rows.local_a.label.hasAttribute(ATTR), false);
  loaded.dom.command({ action: "pinned-look", folder: "true" });
  assert.equal(loaded.win.localStorage.getItem("myclaude.pinnedFolderOff"), null, "«показывать» ключа не держит");
});
