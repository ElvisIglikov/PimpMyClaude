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

const page = ({ href = "https://claude.ai/epitaxy/local_home", pinned = [], recents = [] } = {}) => {
  const rows = {};
  const loaded = loadInject({
    href,
    title: "Claude",
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

// ---- цвет плашки — цвет проекта (#7213, проба, отключается PINNED_TINT) -------
const TINT = "--myclaude-folder-tint";
const MAP_KEY = "myclaude-themes-v1";

test("#7213: тон авто-цвета папки — побайтно как AutoPaint.hue(forName:) приложения", () => {
  const { loaded } = page();
  // Эталоны — из ProjectTests.swift (testProjectHue…).
  assert.equal(loaded.inner.pinnedHue("Trelvis"), 20);
  assert.equal(loaded.inner.pinnedHue("PimpMyClaude"), 199);
});

test("#7213: плашка красится цветом проекта: запись чата, чат той же папки, иначе авто-тон", () => {
  const palette = accent => ({ theme: { id: "x", name: "x", type: "dark",
    palette: { accent, background: "#111111", foreground: "#eeeeee", sidebar: "#0a0a0a", panel: "#1a1a1a", muted: "#888888" } } });
  const map = { "id:local_a": palette("#ff8800") };
  const { loaded, rows } = (() => {
    const made = page({
      pinned: [
        ["local_a", "Ночь кода", repo("VkusnoffKz")],
        ["local_b", "Ещё Вкуснофф", repo("VkusnoffKz")],
        ["local_c", "Пимп", repo("PimpMyClaude")],
      ],
    });
    made.loaded.win.localStorage.setItem(MAP_KEY, JSON.stringify(map));
    pass(made.loaded);
    return made;
  })();
  assert.equal(rows.local_a.label.style.getPropertyValue(TINT), "color-mix(in srgb, #ff8800 40%, transparent)",
    "окно чата красили — его акцент");
  assert.equal(rows.local_b.label.style.getPropertyValue(TINT), "color-mix(in srgb, #ff8800 40%, transparent)",
    "чат той же папки — тот же цвет");
  assert.equal(rows.local_c.label.style.getPropertyValue(TINT), "color-mix(in srgb, hsl(199 80% 62%) 40%, transparent)",
    "записи нет — авто-тон папки, как у окна проекта без .pimpmyclaude.json");
  const css = String(loaded.dom.query(STYLE)?.textContent ?? "");
  assert.ok(css.includes(`background-color:var(${TINT},var(--cds-alpha-2))`), "без цвета — прежний серый");
  loaded.api.dispose();
  assert.equal(rows.local_a.label.style.getPropertyValue(TINT), "", "dispose снимает цвет");
});

// ---- часики кеша левее чипа (#7912, WF102) -----------------------------------
// Время — session.updatedAtMs строки; атрибут на [data-row-label], рисует CSS.
const CLOCK = "data-myclaude-clock";
const LATE = "data-myclaude-clock-late";
const T0 = 1_790_000_000_000;
const MIN = 60_000;
const rowLabel = row => row.row.querySelector("[data-row-label]");

test("#7912: часики — обратный отсчёт часа «60:00 → 0:00», красные меньше 10 минут и после нуля", () => {
  const { loaded, rows } = page({ pinned: [["local_a", "Ночь кода", repo("VkusnoffKz"), { updatedAtMs: T0 }]] });
  const label = rowLabel(rows.local_a);
  const at = t => { loaded.inner.markPinnedClocks(t); return [label.getAttribute(CLOCK), label.hasAttribute(LATE)]; };
  assert.deepEqual(at(T0), ["60:00", false], "только что ответил — полный час");
  assert.deepEqual(at(T0 + 1000), ["59:59", false]);
  assert.deepEqual(at(T0 + 25 * MIN + 7000), ["34:53", false], "минуты не дополняются нулём, секунды — двумя знаками");
  assert.deepEqual(at(T0 + 50 * MIN), ["10:00", false], "ровно 10 минут — ещё серые");
  assert.deepEqual(at(T0 + 50 * MIN + 1000), ["9:59", true], "меньше 10 минут — красные");
  assert.deepEqual(at(T0 + 60 * MIN), ["0:00", true]);
  assert.deepEqual(at(T0 + 3 * 60 * MIN), ["0:00", true], "кеш остыл — «0:00» красным, в минус не уходит");
  assert.equal(rows.local_a.row.textContent, "Ночь кода", "текст строки не меняется");
});

test("#7912: в DOM пишется только смена значения", () => {
  const { loaded, rows } = page({ pinned: [["local_a", "Ночь кода", repo("VkusnoffKz"), { updatedAtMs: T0 }]] });
  const label = rowLabel(rows.local_a);
  const writes = [];
  for (const name of ["setAttribute", "removeAttribute"]) {
    const original = label[name].bind(label);
    label[name] = (...args) => { writes.push([name, ...args]); return original(...args); };
  }
  loaded.inner.markPinnedClocks(T0 + 1000);
  assert.deepEqual(writes, [["setAttribute", CLOCK, "59:59"]]);
  loaded.inner.markPinnedClocks(T0 + 1000);
  loaded.inner.markPinnedClocks(T0 + 1400);
  assert.equal(writes.length, 1, "та же секунда — ни одной записи");
  loaded.inner.markPinnedClocks(T0 + 50 * MIN + 1000);
  assert.deepEqual(writes.slice(1), [["setAttribute", CLOCK, "9:59"], ["setAttribute", LATE, ""]]);
  loaded.inner.markPinnedClocks(T0 + 50 * MIN + 1500);
  assert.equal(writes.length, 3, "красный стоит — второй раз не ставится");
});

test("#7912: только закреплённые главного окна; нет времени — часиков нет", () => {
  const { loaded, rows } = page({
    pinned: [["local_a", "Закреплённый", repo("VkusnoffKz"), { updatedAtMs: T0 }], ["local_b", "Без времени", repo("Rick")]],
    recents: [["local_r", "Недавний", repo("Dictator"), { updatedAtMs: T0 }]],
  });
  loaded.inner.markPinnedClocks(T0);
  assert.equal(rowLabel(rows.local_a).getAttribute(CLOCK), "60:00");
  assert.equal(rowLabel(rows.local_b).hasAttribute(CLOCK), false, "updatedAtMs нет — не рисуем");
  assert.equal(rowLabel(rows.local_r).hasAttribute(CLOCK), false, "недавние не трогаются");
  const popout = loadInject({
    href: "about:blank",
    title: "Попап",
    html: dom => {
      const pin = dom.document.body.add("div", { attrs: { "data-testid": "sidebar-pinned" } });
      rows.popout = addRow(pin, "local_p", "Попап", repo("Geyboard"), { updatedAtMs: T0 });
    },
  });
  assert.equal(popout.error, null);
  popout.inner.markPinnedClocks(T0);
  popout.dom.fireKind("interval");
  assert.equal(rowLabel(rows.popout).hasAttribute(CLOCK), false, "вынесенное окно — без часиков");
});

test("#7912: тикают раз в секунду сами; dispose снимает и таймер, и метки", () => {
  const { loaded, rows } = page({ pinned: [["local_a", "Ночь кода", repo("VkusnoffKz"), { updatedAtMs: Date.now() - 5 * MIN }]] });
  const label = rowLabel(rows.local_a);
  const ticks = [...loaded.dom.timers.entries()].filter(([, item]) => item.kind === "interval" && item.ms === 1000);
  assert.ok(ticks.length >= 1, "секундный тик стоит");
  loaded.dom.fireKind("interval");
  assert.match(label.getAttribute(CLOCK), /^5[45]:\d\d$/);
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`[${CLOCK}],[${LATE}]`).length, 0, "dispose оставил часики");
  assert.equal(loaded.dom.count("interval"), 0, "dispose оставил тик");
});

test("#7912: часики рисует CSS — моноширинные, серые, красные по метке, только в Pinned", () => {
  const { loaded } = page();
  const css = String(loaded.dom.query(STYLE).textContent ?? "").split("\n");
  const clock = css.find(line => line.includes(`[${CLOCK}]::before`));
  const late = css.find(line => line.includes(`[${LATE}]::before`));
  assert.ok(clock && late, "правил часиков нет");
  assert.ok(clock.startsWith('[data-testid="sidebar-pinned"] '));
  assert.match(clock, new RegExp(`content:attr\\(${CLOCK}\\)`));
  assert.match(clock, /monospace/);
  assert.match(late, /color:#e5484d/);
});

// ---- настройка «Закреплённые» (#8743) -----------------------------------------
// Слово Элвиса 04.10: «настройку, чтобы эти штучки можно было отключить… показывать
// или нет название проекта и таймер». Команда `pinned-look` {folder, clock:
// "true"|"false"}; в localStorage — только «выключено».
const look = loaded => ({ ...loaded.api.status().pinnedLook });

test("#8743: без настройки показывается всё, как раньше", () => {
  const { loaded, rows } = page({ pinned: [["local_a", "Ночь кода", repo("VkusnoffKz"), { updatedAtMs: T0 }]] });
  loaded.inner.markPinnedClocks(T0);
  assert.deepEqual(look(loaded), { folder: true, clock: true });
  assert.equal(rows.local_a.label.getAttribute(ATTR), "VkusnoffKz");
  assert.equal(rowLabel(rows.local_a).getAttribute(CLOCK), "60:00");
});

test("#8743: название проекта выключается и включается сразу, таймер при этом не трогается", () => {
  const { loaded, rows } = page({ pinned: [["local_a", "Ночь кода", repo("VkusnoffKz"), { updatedAtMs: Date.now() }]] });
  loaded.dom.command({ action: "pinned-look", folder: "false", clock: "true" });
  assert.deepEqual(look(loaded), { folder: false, clock: true });
  assert.equal(rows.local_a.label.hasAttribute(ATTR), false, "чип снят без ожидания прохода");
  assert.equal(rowLabel(rows.local_a).hasAttribute(CLOCK), true, "таймер остался");
  pass(loaded);
  assert.equal(rows.local_a.label.hasAttribute(ATTR), false, "проход раскладки чип не возвращает");
  assert.equal(rows.local_a.row.textContent, "Ночь кода", "текст строки не меняется");
  loaded.dom.command({ action: "pinned-look", folder: "true", clock: "true" });
  assert.equal(rows.local_a.label.getAttribute(ATTR), "VkusnoffKz", "включили — чип на месте");
});

test("#8743: таймер выключается и включается сразу, название при этом не трогается", () => {
  const { loaded, rows } = page({ pinned: [["local_a", "Ночь кода", repo("VkusnoffKz"), { updatedAtMs: Date.now() }]] });
  const label = rowLabel(rows.local_a);
  loaded.dom.command({ action: "pinned-look", folder: "true", clock: "false" });
  assert.deepEqual(look(loaded), { folder: true, clock: false });
  assert.equal(label.hasAttribute(CLOCK), false, "часики сняты");
  assert.equal(label.hasAttribute(LATE), false);
  assert.equal(rows.local_a.label.getAttribute(ATTR), "VkusnoffKz", "название осталось");
  loaded.dom.fireKind("interval");
  assert.equal(label.hasAttribute(CLOCK), false, "тик часики не возвращает");
  loaded.dom.command({ action: "pinned-look", folder: "true", clock: "true" });
  assert.equal(label.hasAttribute(CLOCK), true, "включили — часики на месте");
});

test("#8743: поле без «true»/«false» свою половину не меняет; в хранилище — только «выключено»", () => {
  const { loaded, rows } = page({ pinned: [["local_a", "Ночь кода", repo("VkusnoffKz"), { updatedAtMs: Date.now() }]] });
  loaded.dom.command({ action: "pinned-look", folder: "false" });
  assert.deepEqual(look(loaded), { folder: false, clock: true }, "поля clock нет — таймер как был");
  loaded.dom.command({ action: "pinned-look", folder: 1, clock: "нет" });
  assert.deepEqual(look(loaded), { folder: false, clock: true }, "мусор ничего не меняет");
  assert.equal(loaded.win.localStorage.getItem("myclaude.pinnedFolderOff"), "1");
  assert.equal(loaded.win.localStorage.getItem("myclaude.pinnedClockOff"), null, "«показывать» ключа не держит");
  assert.equal(rows.local_a.label.hasAttribute(ATTR), false);
});
