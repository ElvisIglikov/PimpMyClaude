// WF121: восстановленные тесты НАВИГАЦИИ из WF82. observeGrant ниже подаёт
// счётчику обхода синтетическое наблюдение уже выданного разрешения: это seam
// конечного автомата, НЕ положительная карточка Claude и НЕ проверка auto-click.
// Карточки и клики проверяет auto-allow.test.mjs и отдельный сценарий WF121 Б1 ниже.
// Обход чатов списка слева (раздел 12е inject.js, #7099, WF82): главное окно,
// пока его никто не трогает, заходит в чат, который ждёт разрешения, ждёт, пока
// тик 12е нажмёт Allow, и возвращается в прежний чат.
//
// Стенд — как Claude 2.2553.13 по разведке WF82: строка сайдбара
// [data-row-key="code:<id>"] с кнопкой перехода [data-row-main-button] и кнопкой
// «…» [data-row-action]; сессия чата лежит в React-волокне строки пропсом
// session с полем hasPendingApproval; стор разрешений — permissionsBySessionId
// (id чата → запросы с toolName), стор попапов — popoutWindows. Время — часы
// раздела (люк setAutoAllowClock), навигация — роутер стенда (dom.router()).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const A = "local_aaaa-1111";
const B = "local_bbbb-2222";
const C = "local_cccc-3333";
const MODE_KEY = "myclaude-auto-allow-roam";
const LOCK_KEY = "myclaude-auto-allow-roam-lock";
const CASHOUT_KEY = "myclaude-cashout";
// Выключатель К3: ключа нет — Авто-Allow выключен (WF108), стенд по умолчанию его включает явно.
const ON_KEY = "myclaude.autoAllowOnce";
const drain = () => new Promise(resolve => setImmediate(resolve));
const settle = async () => { for (let index = 0; index < 6; index += 1) await drain(); };

// Строка сайдбара с сессией в волокне двумя прыжками выше самой строки.
const addRow = (box, id, title, rows) => {
  const rect = { left: 8, top: 100 + Object.keys(rows).length * 28, width: 272, height: 26 };
  const row = box.add("div", { attrs: { "data-row-key": `code:${id}` }, rect });
  const inner = row.add("div", { attrs: { "data-row": "" } });
  const main = inner.add("button", { attrs: { "data-row-main-button": "" }, text: title, rect });
  const more = inner.add("button", { attrs: { "data-row-action": "", "aria-label": `More options for ${title}` } });
  const session = { ref: { kind: "code", id }, title, liveStatus: "running", hasPendingApproval: false };
  row["__reactFiber$test"] = {
    memoizedProps: { "data-row-key": `code:${id}` },
    return: { memoizedProps: { shiftKey: `code:${id}` }, return: { memoizedProps: { session }, return: null } },
  };
  const item = { row, main, more, session, moreClicks: 0 };
  more.addEventListener("click", () => { item.moreClicks += 1; });
  rows[id] = item;
  return item;
};

// Главное окно в чате A, слева Pinned и список недавних; сторы — через
// подставной импортёр модулей (боевой import() в vm бросает).
const page = ({
  path = `/epitaxy/${A}`, pinned = [[A, "Чат Элвиса"]], recents = [[B, "Вкуснофф: накладные"], [C, "Диктатор"]],
  focus = false, draft = "", sidebar = true, mode = "on", allow = "true", stores = {}, local = {}, lazy = [], cap = Infinity,
} = {}) => {
  const rows = {};
  const loaded = loadInject({
    href: `https://claude.ai${path}`, title: "Claude", hasFocus: focus,
    storage: { local: { ...(allow ? { [ON_KEY]: allow } : {}), ...(mode ? { [MODE_KEY]: mode } : {}), ...local } },
    html: dom => {
      const parts = dom.composer({ text: draft });
      if (sidebar) {
        const bar = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
        const pin = bar.add("div", { attrs: { "data-testid": "sidebar-pinned" } });
        const recent = bar.add("div", { attrs: { "data-testid": "sidebar-recents" } });
        for (const [id, title] of pinned) addRow(pin, id, title, rows);
        for (const [id, title] of recents) addRow(recent, id, title, rows);
      }
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const router = loaded.dom.router({ cap });
  // lazy — чаты, переход в которые Claude делает не сразу (pendingPathname):
  // щелчок только ставит переход в очередь, доводит его тест.
  const pending = [];
  for (const [id, item] of Object.entries(rows)) {
    item.main.addEventListener("click", () => {
      const go = () => router.navigate(`/epitaxy/${id}`);
      if (lazy.includes(id)) pending.push(go); else go();
    });
  }
  const clock = { t: 5_000_000 };
  loaded.inner.setAutoAllowClock(() => clock.t);
  const box = { popouts: loaded.run("new Map()"), perms: {}, opened: [], granted: [] };
  const exports = {};
  if (stores.popout !== false) {
    const value = { popoutWindows: box.popouts, openPopout: options => box.opened.push(options) };
    const store = () => {};
    store.getState = () => value;
    exports.Popouts = store;
  }
  if (stores.perm !== false) {
    const value = { permissionsBySessionId: box.perms, addPermission: () => {} };
    const store = () => {};
    store.getState = () => value;
    exports.Perms = store;
  }
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  loaded.inner.setModuleImporter(() => Promise.resolve(exports));
  const env = { loaded, rows, router, clock, stores: box, pending, grants: [] };
  return env;
};

const roam = env => plain(env.loaded.api.status().autoAllow.roam);
const path = env => env.loaded.win.location.pathname;
const tick = (env, ms = 700) => {
  env.clock.t += ms;
  if (env.loaded.api.status().autoAllow.on && env.grants.length) {
    const id = env.grants.shift();
    assert.equal(path(env), `/epitaxy/${id}`, 'наблюдение разрешения только в нужном чате');
    env.loaded.inner.autoAllowState.pressCount++;
    answered(env, id);
    env.stores.granted.push(id);
  }
  env.loaded.inner.autoAllowCycle();
};
// Чат просит разрешение: метка у строки и запрос в сторе.
const ask = (env, id, tool = "Bash") => {
  env.rows[id].session.hasPendingApproval = true;
  env.stores.perms[id] = [{ sessionId: id, toolUseId: `t-${id}`, toolName: tool, status: "pending" }];
};
const answered = (env, id) => {
  env.rows[id].session.hasPendingApproval = false;
  delete env.stores.perms[id];
};
// Наблюдение результата на границе автомата: native карточку не рисуем.
const observeGrant = (env, id) => { env.grants.push(id); };
// Подтверждение плана остаётся человеку — отрицательные случаи.
const unresolvedCard = (env, label = "Allow once", text = "Allow Claude to run ExitPlanMode: Ready to implement") => {
  const box = env.loaded.document.body.add("div", { class: "epitaxy-approval-card", text, rect: { width: 400, height: 140 } });
  const button = box.add("button", { text: label, rect: { width: 100, height: 28 } });
  button.addEventListener("click", () => { env.stores.granted.push("UNEXPECTED"); });
  return button;
};
// Первый круг: метку видно, сторы ищутся; второй — метка пережила два прочтения.
const warm = async (env, idle = 6000) => {
  tick(env, idle);
  await settle();
  tick(env, 2500);
};
// Обход B от начала до возврата: карточка, нажатие, стоянка, возврат.
const roamOnce = async (env, id = B) => {
  ask(env, id);
  await warm(env);
  assert.equal(path(env), `/epitaxy/${id}`, "окно ушло в ждущий чат");
  observeGrant(env, id);
  tick(env);
  tick(env);
  tick(env, 2000);
  tick(env);
};
const send = (env, event) => env.loaded.win.dispatchEvent({ cancelable: true, isTrusted: true, ...event });
// Один круг срочного опроса возврата (newWindowWait раздела 12б): толкаем самый свежий таймер.
const poll = async env => {
  const ids = env.loaded.dom.ids("timeout");
  env.loaded.dom.fire(ids[ids.length - 1]);
  await drain();
};

test("сессия строки читается из React-волокна, чужая сессия не принимается", () => {
  const env = page();
  assert.equal(env.loaded.inner.roamSession(env.rows[B].row, B)?.title, "Вкуснофф: накладные");
  assert.equal(env.loaded.inner.roamSession(env.rows[B].row, C), null, "сессия с другим id — не наша");
  assert.equal(env.loaded.inner.newWindowRow(A), null, "12б по-прежнему ищет только в списке недавних");
  assert.equal(env.loaded.inner.newWindowRow(A, true), env.rows[A].row, "обход находит и закреплённый чат");
});

test("сухой режим: status пишет, куда пошёл бы, окно стоит", async () => {
  const env = page({ mode: "dry" });
  ask(env, B);
  await warm(env);
  const state = roam(env);
  assert.equal(state.mode, "dry");
  assert.equal(state.on, false);
  assert.equal(state.lastRoam.dry, true);
  assert.deepEqual(state.lastRoam.chats, [B]);
  assert.deepEqual(state.lastRoam.tools, ["Bash"]);
  assert.match(state.reason, /сухой режим/);
  assert.equal(path(env), `/epitaxy/${A}`, "окно не уходило");
  assert.equal(env.router.entries().length, 1, "ни одного перехода");
  tick(env, 2500);
  assert.equal(roam(env).dryRuns, 1, "решение пишется раз на метку, а не каждый круг");
});

test("обход: зашёл в B, нажал Allow, вернулся строкой в закреплённый A", async () => {
  const env = page();
  await roamOnce(env);
  const state = roam(env);
  assert.equal(path(env), `/epitaxy/${A}`, "окно вернулось в прежний чат");
  assert.deepEqual(env.stores.granted, [B], "Allow нажат в B");
  assert.equal(state.state, "idle");
  assert.equal(state.roams, 1);
  assert.deepEqual(state.lastRoam.chats, [B]);
  assert.equal(state.lastRoam.presses, 1);
  assert.equal(state.lastRoam.back, "row", "возврат — строкой из раздела Pinned");
  assert.equal(env.loaded.win.localStorage.getItem(LOCK_KEY), null, "замок снят");
  assert.deepEqual(env.router.entries(), [`/epitaxy/${A}`, `/epitaxy/${B}`, `/epitaxy/${A}`]);
  for (const item of Object.values(env.rows)) assert.equal(item.moreClicks, 0, "кнопку «…» строки обход не трогает");
});

test('WF121 Б1: обход нажимает реальную DOM-кнопку Allow once и возвращается в A', async () => {
  const env = page(); ask(env, B); await warm(env);
  assert.equal(path(env), `/epitaxy/${B}`);
  const card = env.loaded.document.body.add('div', { class: 'epitaxy-approval-card',
    text: 'Allow Claude to run Bash: git status', rect: { width: 400, height: 140 } });
  let once = 0, always = 0;
  card.add('button', { text: 'Allow once', rect: { width: 100, height: 28 } }).addEventListener('click', () => {
    once++; card.remove(); answered(env, B);
  });
  card.add('button', { text: 'Always allow', rect: { width: 100, height: 28 } }).addEventListener('click', () => always++);
  tick(env); tick(env); tick(env, 2000); tick(env);
  assert.equal(once, 1); assert.equal(always, 0);
  assert.equal(path(env), `/epitaxy/${A}`); assert.equal(roam(env).state, 'idle');
  assert.equal(roam(env).lastRoam.presses, 1);
  assert.equal(env.loaded.inner.autoAllowState.pressCount, 1);
  assert.deepEqual(env.grants, [], 'счётчик нажатий не подставлялся через seam');
  env.loaded.api.dispose();
});

test("строки прежнего чата нет — возврат историей, с домашнего экрана тоже", async () => {
  const lost = page({ pinned: [] });
  await roamOnce(lost);
  assert.equal(path(lost), `/epitaxy/${A}`);
  assert.equal(roam(lost).lastRoam.back, "history");

  const home = page({ path: "/epitaxy" });
  await roamOnce(home);
  assert.equal(path(home), "/epitaxy", "домашний экран вернулся");
  assert.equal(roam(home).lastRoam.back, "history", "у домашнего экрана строки нет — только история");

  // Без Navigation API — прежний счёт шагов по history.length.
  const bare = page({ pinned: [] });
  delete bare.loaded.win.navigation;
  await roamOnce(bare);
  assert.equal(path(bare), `/epitaxy/${A}`);
  assert.equal(roam(bare).lastRoam.back, "history");
});

test("история упёрлась в 50 записей Chromium: возврат с домашнего экрана и без строки A — по ключу записи", async () => {
  for (const [where, pinned] of [["/epitaxy", [[A, "Чат Элвиса"]]], [`/epitaxy/${A}`, []]]) {
    const env = page({ path: where, pinned, cap: 50 });
    // Окно, где давно ходят по чатам (живой замер 23.09: history.length = 50).
    for (let step = 0; step < 60; step += 1) env.router.navigate(`/epitaxy/local_old-${step}`);
    env.router.navigate(where);
    assert.equal(env.loaded.win.history.length, 50, where);
    await roamOnce(env);
    assert.equal(env.loaded.win.history.length, 50, `${where}: длина не растёт — шаги по ней не посчитать`);
    const state = roam(env);
    assert.equal(path(env), where, `${where}: окно вернулось`);
    assert.equal(state.lastRoam.back, "history", where);
    assert.equal(state.disabled, null, `${where}: обход не выключен`);
  }
});

test("идём только по метке разрешения: вопрос и план — мимо; метку без запроса навещаем", async () => {
  for (const [tool, reason] of [["AskUserQuestion", "вопрос человеку"], ["ExitPlanMode", "план на одобрение"]]) {
    const env = page();
    ask(env, B, tool);
    await warm(env);
    assert.equal(path(env), `/epitaxy/${A}`, tool);
    assert.equal(roam(env).skipped[0].reason, reason, tool);
  }
  // Стор знает запросы только открытого чата (замер 23.09 12:22): чат слева с
  // меткой и пустым стором — идём. В B стор узнал вопрос — сразу назад.
  const bare = page();
  bare.rows[B].session.hasPendingApproval = true;
  await warm(bare);
  assert.equal(path(bare), `/epitaxy/${B}`, "метка без запроса в сторе — окно пошло смотреть");
  bare.stores.perms[B] = [{ sessionId: B, toolUseId: "q", toolName: "AskUserQuestion", status: "pending" }];
  tick(bare);
  tick(bare);
  tick(bare);
  assert.equal(path(bare), `/epitaxy/${A}`, "в B вопрос человеку — сразу вернулись");
  assert.equal(roam(bare).lastRoam.why, "вопрос человеку");
  tick(bare, 2500);
  tick(bare, 2500);
  assert.equal(path(bare), `/epitaxy/${A}`, "к вопросу не возвращаемся, пока метка та же");
});

test("исключения: попап, стор не найден, чат уже здесь", async () => {
  const popout = page();
  popout.stores.popouts.set(B, { title: "Вкуснофф: накладные" });
  ask(popout, B);
  await warm(popout);
  assert.equal(path(popout), `/epitaxy/${A}`);
  assert.equal(roam(popout).skipped[0].reason, "в отдельном окне");

  const blind = page({ stores: { perm: false } });
  ask(blind, B);
  await warm(blind);
  assert.equal(path(blind), `/epitaxy/${A}`, "без стора разрешений обход не идёт никуда");
  assert.equal(roam(blind).reason, "стор не найден");

  const here = page({ path: `/epitaxy/${B}` });
  ask(here, B);
  await warm(here);
  assert.equal(path(here), `/epitaxy/${B}`, "свой чат жмёт тик 12е на месте");
  assert.equal(here.router.entries().length, 1);
});

test("исключения: «Новое окно», свежий «Обкэшить», открытое меню, черновик", async () => {
  const busy = page();
  busy.loaded.dom.command({ id: "n1", action: "new-window", at: "now", scope: "window", title: "Claude", x: 1, y: 2, text: "Привет" });
  assert.equal(busy.loaded.api.status().newWindow.busy, true);
  ask(busy, B);
  await warm(busy);
  assert.equal(roam(busy).reason, "идёт «Новое окно»");
  assert.equal(busy.router.entries().length, 1);

  const cash = page({ local: { [CASHOUT_KEY]: JSON.stringify({ at: Date.now(), text: "перенос" }) } });
  ask(cash, B);
  await warm(cash);
  assert.equal(roam(cash).reason, "свежий «Обкэшить»");
  assert.equal(path(cash), `/epitaxy/${A}`);

  const menu = page();
  menu.loaded.document.body.add("div", { attrs: { role: "menu" } });
  ask(menu, B);
  await warm(menu);
  assert.equal(roam(menu).reason, "открыто меню");

  // Черновик чата Claude хранит сам по чату и вернёт; черновик домашнего экрана — держит.
  const home = page({ path: "/epitaxy", draft: "недописанная мысль" });
  ask(home, B);
  await warm(home);
  assert.equal(roam(home).reason, "в поле черновик");
  assert.equal(path(home), "/epitaxy");
  const chat = page({ draft: "недописанная мысль" });
  ask(chat, B);
  await warm(chat);
  assert.equal(path(chat), `/epitaxy/${B}`, "черновик в чате не держит обход");
});

test("исключения: списка нет или строки нет; свёрнутый список — не помеха", async () => {
  const none = page({ sidebar: false });
  await warm(none);
  assert.equal(roam(none).reason, "список слева не виден");

  const hidden = page();
  hidden.rows[B].row.rect = { left: 0, top: 0, width: 0, height: 0 };
  ask(hidden, B);
  await warm(hidden);
  assert.equal(path(hidden), `/epitaxy/${A}`);
  assert.equal(roam(hidden).skipped[0].reason, "строка не отрисована", "строка есть, размера нет — свёрнутая группа (#7112)");
  assert.equal(roam(hidden).unrendered, 1);
  assert.match(roam(hidden).reason, /свёрнутой группе списка — 1/, "причина названа честно");

  // Свёрнутый сайдбар Claude (⌘B) — всплывашка с inert: строки с размерами, обход идёт и по ним.
  const folded = page();
  folded.loaded.document.querySelector('[data-testid="sidebar"]').setAttribute("inert", "");
  ask(folded, B);
  await warm(folded);
  assert.notEqual(roam(folded).reason, "список слева спрятан");
  assert.equal(path(folded), `/epitaxy/${B}`, "по свёрнутому списку обход идёт");
});

test("пороги тишины: без фокуса — 1,5 с мыши, с фокусом — 3 с всего; считается только доверенное", async () => {
  const blur = page();
  ask(blur, B);
  await warm(blur);
  assert.equal(path(blur), `/epitaxy/${B}`, "без фокуса хватает полутора секунд тишины мыши");

  const mouse = page();
  ask(mouse, B);
  tick(mouse, 6000);
  await settle();
  send(mouse, { type: "pointermove", isTrusted: false });
  tick(mouse, 2500);
  assert.equal(path(mouse), `/epitaxy/${B}`, "недоверенное движение тишину не нарушает");

  const hover = page();
  ask(hover, B);
  tick(hover, 6000);
  await settle();
  send(hover, { type: "pointermove" });
  send(hover, { type: "keydown", key: "a" });
  tick(hover, 1300);
  assert.equal(roam(hover).reason, "мышь над окном");
  tick(hover, 1300);
  assert.equal(path(hover), `/epitaxy/${B}`, "клавиатура в окно без фокуса не идёт — ждём только мышь");

  const focused = page({ focus: true });
  ask(focused, B);
  tick(focused, 6000);
  await settle();
  send(focused, { type: "keydown", key: "a" });
  tick(focused, 1300);
  assert.equal(roam(focused).reason, "окно в работе");
  send(focused, { type: "keydown", key: "a" });
  tick(focused, 2500);
  assert.equal(roam(focused).reason, "окно в работе", "клавиша сбросила отсчёт");
  tick(focused, 1300);
  assert.equal(path(focused), `/epitaxy/${B}`, "три секунды тишины — окно пошло");
});

test("щит: ввод в окне посреди обхода глушится и возвращает окно; ⌘N и чужие события проходят", async () => {
  const env = page();
  ask(env, B);
  await warm(env);
  assert.equal(roam(env).state, "go");
  assert.equal(send(env, { type: "keydown", key: "n", metaKey: true }), true, "⌘N от «Нового окна» проходит");
  assert.equal(send(env, { type: "keydown", key: "a", isTrusted: false }), true, "недоверенное не глушим");
  assert.equal(roam(env).state, "go", "обход идёт дальше");
  // С #7199 вместо плашки — метка замка К6; с WF111 только в status, не в заголовке окна.
  assert.ok(!String(env.loaded.document.title).startsWith("Пимп жмёт Allow"), "заголовок окна метку не несёт");
  assert.ok(!env.loaded.document.body.textContent.includes("Пимп жмёт Allow в"), "плашки больше нет");
  assert.equal(send(env, { type: "keydown", key: "a" }), false, "клавиша в чужом чате заглушена");
  assert.equal(path(env), `/epitaxy/${A}`, "окно сразу вернулось");
  const state = roam(env);
  assert.equal(state.state, "idle");
  assert.equal(state.lastRoam.why, "рука на окне");
  for (const event of [{ type: "paste" }, { type: "pointerdown" }, { type: "keydown", key: "v", metaKey: true }]) {
    const again = page();
    ask(again, B);
    await warm(again);
    assert.equal(send(again, event), false, JSON.stringify(event));
    assert.equal(path(again), `/epitaxy/${A}`, JSON.stringify(event));
  }
});

test("фокус окна посреди обхода — возврат", async () => {
  const env = page();
  ask(env, B);
  await warm(env);
  observeGrant(env, B);
  tick(env);
  assert.equal(roam(env).state, "wait");
  // Цель — само окно страницы: у vm это его глобальный объект, а не стаб снаружи.
  send(env, { type: "focus", target: env.loaded.run("window") });
  assert.equal(path(env), `/epitaxy/${A}`);
  assert.equal(roam(env).lastRoam.why, "окно подняли");
});

test("кнопки нет — возврат, к чату не идём, пока метка не сменится; пустые заходы обход не выключают", async () => {
  const env = page();
  const empty = async round => {
    ask(env, B);
    await warm(env);
    assert.equal(path(env), `/epitaxy/${B}`, `заход ${round}`);
    for (let step = 0; step < 10; step += 1) tick(env);
    tick(env);
    assert.equal(path(env), `/epitaxy/${A}`, `заход ${round}: вернулись`);
    assert.equal(roam(env).lastRoam.why, "кнопки нет");
    assert.equal(roam(env).lastRoam.presses, 0);
  };
  await empty(1);
  tick(env, 2500);
  tick(env, 2500);
  assert.equal(path(env), `/epitaxy/${A}`, "метка та же — второй раз не идём");
  assert.equal(env.router.entries().length, 3);
  answered(env, B);
  tick(env, 2500);
  await empty(2);
  answered(env, B);
  tick(env, 2500);
  await empty(3);
  // Чат без кнопки Allow (вопрос, план) — честный заход, а не сбой.
  assert.equal(roam(env).disabled, null);
  answered(env, B);
  tick(env, 2500);
  await empty(4);
});

test("замок: пока другое окно в обходе, это никуда не идёт", async () => {
  const first = page();
  ask(first, B);
  await warm(first);
  assert.equal(path(first), `/epitaxy/${B}`);
  const lock = first.loaded.win.localStorage.getItem(LOCK_KEY);
  assert.equal(JSON.parse(lock).chat, B);

  const second = page({ local: { [LOCK_KEY]: lock } });
  second.clock.t = first.clock.t;
  second.loaded.inner.setAutoAllowClock(() => second.clock.t);
  ask(second, B);
  await warm(second);
  assert.equal(roam(second).reason, "обход идёт в другом окне");
  assert.equal(path(second), `/epitaxy/${A}`);
  tick(second, 15000);
  tick(second, 2500);
  assert.equal(path(second), `/epitaxy/${B}`, "замок протух — окно пошло");
});

test("«Новое окно» и «В отдельное окно» посреди обхода: сперва окно в A, потом команда", async () => {
  const env = page();
  ask(env, B);
  await warm(env);
  observeGrant(env, B);
  tick(env);
  assert.equal(path(env), `/epitaxy/${B}`);
  env.loaded.dom.command({ id: "n1", action: "new-window", at: "now", scope: "window", title: "Claude", x: 1, y: 2, text: "Привет" });
  assert.equal(path(env), `/epitaxy/${A}`, "окно вернулось раньше, чем команда пошла");
  assert.equal(roam(env).lastRoam.why, "команда");
  const mark = env.loaded.api.status().newWindow;
  assert.equal(mark.runs, 1, "команда исполнена после возврата");
  assert.equal(mark.busy, true);

  const popout = page();
  ask(popout, B);
  await warm(popout);
  observeGrant(popout, B);
  tick(popout);
  popout.loaded.dom.command({ id: "p1", action: "popout-window", at: "now", scope: "window", title: "Claude", x: 10, y: 20 });
  await settle();
  assert.equal(path(popout), `/epitaxy/${A}`);
  assert.equal(popout.stores.opened.length, 1);
  assert.equal(popout.stores.opened[0].sessionId, A, "в отдельное окно ушёл чат Элвиса, а не чужой B");
});

test("команда посреди обхода, а окно в A не вернулось — команда отменяется с плашкой", async () => {
  // Окно осталось в B: за стоянку в поле B лёг текст.
  const stay = page();
  ask(stay, B);
  await warm(stay);
  observeGrant(stay, B);
  tick(stay);
  tick(stay);
  assert.equal(roam(stay).state, "linger");
  stay.loaded.parts.editor.__text = "черновик B доехал после нажатия";
  stay.loaded.dom.command({ id: "p9", action: "popout-window", at: "now", scope: "window", title: "Claude", x: 10, y: 20 });
  await settle();
  assert.equal(path(stay), `/epitaxy/${B}`);
  assert.equal(roam(stay).lastRoam.back, "stay");
  assert.equal(stay.stores.opened.length, 0, "чужой B в отдельное окно не уехал");
  assert.ok(stay.loaded.document.body.textContent.includes("Команда отменена: окно не в прежнем чате"), "плашка");

  // Назад не пускает ничто: строки A нет, запись A выпала из истории.
  const lost = page({ pinned: [], cap: 1 });
  ask(lost, B);
  await warm(lost);
  observeGrant(lost, B);
  tick(lost);
  assert.equal(path(lost), `/epitaxy/${B}`);
  lost.loaded.dom.command({ id: "p10", action: "popout-window", at: "now", scope: "window", title: "Claude", x: 10, y: 20 });
  await settle();
  lost.clock.t += 2500;
  await poll(lost);
  await settle();
  assert.equal(roam(lost).lastRoam.back, "back-failed");
  assert.equal(lost.stores.opened.length, 0, "чужой B в отдельное окно не уехал");
  assert.ok(lost.loaded.document.body.textContent.includes("Команда отменена: окно не в прежнем чате"), "плашка");
});

test("снятие экземпляра посреди обхода возвращает окно", async () => {
  const env = page();
  ask(env, B);
  await warm(env);
  observeGrant(env, B);
  tick(env);
  assert.equal(path(env), `/epitaxy/${B}`);
  env.loaded.api.dispose();
  assert.equal(path(env), `/epitaxy/${A}`);
  assert.equal(env.loaded.win.localStorage.getItem(LOCK_KEY), null, "замок снят");
});

test("в поле B за обход появился текст — окно остаётся в B и говорит об этом", async () => {
  const env = page();
  ask(env, B);
  await warm(env);
  observeGrant(env, B);
  tick(env);
  tick(env);
  assert.equal(roam(env).state, "linger");
  env.loaded.parts.editor.__text = "продиктовано";
  tick(env, 2000);
  assert.equal(path(env), `/epitaxy/${B}`);
  assert.equal(roam(env).lastRoam.back, "stay");
  assert.ok(env.loaded.document.body.textContent.includes("появился текст"), "плашка объясняет, почему окно в B");
});

test("поле B спрятано на время карточки и вернулось с черновиком B — это не чужой текст, окно в A", async () => {
  const env = page();
  ask(env, B);
  await warm(env);
  assert.equal(path(env), `/epitaxy/${B}`);
  const { block, editor } = env.loaded.parts;
  // Поля нет, пока висит карточка: база не «пустая строка», а «не знаю».
  block.remove();
  observeGrant(env, B);
  tick(env);
  assert.equal(roam(env).state, "wait");
  // После нажатия Claude возвращает поле с сохранённым черновиком B.
  editor.__text = "черновик B";
  env.loaded.document.body.appendChild(block);
  tick(env);
  tick(env, 2000);
  tick(env);
  assert.equal(path(env), `/epitaxy/${A}`, "окно вернулось в A");
  assert.equal(roam(env).lastRoam.back, "row");
});

test("лента A после возврата — на прежнем месте", async () => {
  const env = page();
  const lane = env.loaded.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } });
  lane.scrollHeight = 5000;
  lane.clientHeight = 500;
  lane.scrollTop = 1200;
  ask(env, B);
  await warm(env);
  lane.scrollTop = 0;
  observeGrant(env, B);
  tick(env);
  tick(env);
  tick(env, 2000);
  lane.scrollTop = 4500;
  tick(env);
  assert.equal(path(env), `/epitaxy/${A}`);
  assert.equal(lane.scrollTop, 1200, "Элвис читал середину — середина и осталась");
});

for (const change of ['chat', 'wheel']) test(`отложенный возврат прокрутки отменяется после ${change}`, async () => {
  const env = page();
  const lane = env.loaded.document.body.add('div', { attrs: { 'data-testid': 'epitaxy-virtual-transcript' } });
  lane.scrollHeight = 5000; lane.clientHeight = 500; lane.scrollTop = 1200;
  await roamOnce(env);
  assert.equal(path(env), `/epitaxy/${A}`);
  env.clock.t += 1;
  if (change === 'chat') env.rows[C].main.click();
  else send(env, { type: 'wheel' });
  lane.scrollTop = 2400;
  env.loaded.dom.fireKind('timeout');
  assert.equal(lane.scrollTop, 2400, 'доводка старого A не меняет новый чат или ручную прокрутку');
  env.loaded.api.dispose();
});

test("два ждущих чата — B, C и обратно в A одним заходом", async () => {
  const env = page();
  ask(env, B);
  ask(env, C);
  await warm(env);
  assert.equal(path(env), `/epitaxy/${B}`);
  observeGrant(env, B);
  tick(env);
  tick(env);
  tick(env, 2000);
  assert.equal(path(env), `/epitaxy/${C}`, "из B сразу в C");
  observeGrant(env, C);
  tick(env);
  tick(env);
  tick(env, 2000);
  tick(env);
  const state = roam(env);
  assert.equal(path(env), `/epitaxy/${A}`);
  assert.deepEqual(state.lastRoam.chats, [B, C]);
  assert.equal(state.lastRoam.presses, 2);
  assert.deepEqual(env.stores.granted, [B, C]);
});

test("список читается не чаще раза в 1,2 с; status несёт поля обхода и tickAt", async () => {
  const env = page({ mode: "dry" });
  tick(env, 6000);
  await settle();
  assert.deepEqual(roam(env).waiting, []);
  ask(env, B);
  tick(env, 1000);
  assert.deepEqual(roam(env).waiting, [], "список не перечитан раньше срока");
  tick(env, 1600);
  // Сторы ищутся лениво — только когда кто-то ждёт, поэтому инструментов в первом прочтении нет.
  assert.deepEqual(roam(env).waiting, [{ id: B, title: "Вкуснофф: накладные" }]);
  assert.equal(roam(env).reason, "ищу стор");
  const status = env.loaded.api.status().autoAllow;
  assert.ok(status.tickAt, "время последнего тика");
  for (const key of ["on", "mode", "state", "chat", "from", "since", "roams", "lastRoam", "skipped", "reason"]) {
    assert.ok(key in status.roam, key);
  }
});

test("выключатель в localStorage и попап без обхода", async () => {
  const off = page({ mode: "off" });
  ask(off, B);
  await warm(off);
  assert.equal(roam(off).reason, "выключен");
  assert.equal(path(off), `/epitaxy/${A}`);

  const popup = loadInject({ href: "about:blank", title: "Второе окно" });
  popup.inner.autoAllowCycle();
  const state = plain(popup.api.status().autoAllow.roam);
  assert.equal(state.on, false);
  assert.equal(state.reason, "не главное окно");
});

test("переход в B отложен, а рука уже на окне: окно не остаётся в B", async () => {
  const env = page({ lazy: [B] });
  ask(env, B);
  await warm(env);
  assert.equal(roam(env).state, "go");
  assert.equal(path(env), `/epitaxy/${A}`, "адрес ещё прежний — переход в очереди");
  assert.equal(send(env, { type: "keydown", key: "a" }), false, "клавиша заглушена");
  assert.equal(roam(env).state, "back", "обход не объявил «вернулись», пока переход висит");
  env.pending.shift()();
  assert.equal(path(env), `/epitaxy/${B}`, "переход доехал уже после руки");
  await poll(env);
  await poll(env);
  assert.equal(path(env), `/epitaxy/${A}`, "окно вернули");
  assert.equal(roam(env).state, "idle");
  assert.equal(roam(env).lastRoam.back, "row");

  const never = page({ lazy: [B] });
  ask(never, B);
  await warm(never);
  send(never, { type: "keydown", key: "a" });
  never.clock.t += 2500;
  await poll(never);
  assert.equal(roam(never).state, "idle");
  assert.equal(roam(never).lastRoam.back, "never", "переход так и не случился — возвращаться было некуда");
  assert.equal(path(never), `/epitaxy/${A}`);
  assert.equal(roam(never).disabled, null, "это не «не вернулся»");
});

test("умолчание без ключа — обход включён (WF82, гейт)", async () => {
  const env = page({ mode: null });
  ask(env, B);
  await warm(env);
  assert.equal(roam(env).mode, "on");
  assert.equal(path(env), `/epitaxy/${B}`);
});

// ---- К3 выключатель (#7112) и К6 метка замка в заголовке (#7199) -------------
const aa = env => plain(env.loaded.api.status().autoAllow);

test("К3: fresh/off не жмут и не обходят; on не подтверждает ExitPlanMode", async () => {
  const env = page({ allow: null });
  unresolvedCard(env); tick(env);
  assert.equal(aa(env).on, false); assert.equal(aa(env).blocked, 0);
  env.loaded.dom.command({ action: "auto-allow-once", on: "true" }); tick(env);
  assert.equal(aa(env).on, true); assert.equal(aa(env).blockedLog[0].reason, "manual-required");
  assert.deepEqual(env.stores.granted, []);
  env.loaded.dom.command({ action: "auto-allow-once", on: "false" });
  ask(env, B); await warm(env);
  assert.equal(path(env), `/epitaxy/${A}`); assert.equal(roam(env).on, false);
});

test("К3: выключили посреди обхода — окно возвращается домой", async () => {
  const env = page();
  ask(env, B);
  await warm(env);
  assert.equal(path(env), `/epitaxy/${B}`);
  env.loaded.dom.command({ id: "a3", action: "auto-allow-once", at: "now", scope: "all", on: "false" });
  tick(env);
  await poll(env);
  assert.equal(path(env), `/epitaxy/${A}`, "обход брошен, окно дома");
  assert.equal(roam(env).lastRoam.why, "Авто-Allow выключен");
});

test("Авто-Allow: отказ не трогает заголовок окна", async () => {
  const env = page(); env.loaded.document.title = "Чат Элвиса";
  unresolvedCard(env); tick(env);
  assert.deepEqual(env.stores.granted, []);
  assert.equal(env.loaded.document.title, "Чат Элвиса");
  assert.equal(plain(await env.loaded.api.chats({ nonce: "k6" })).title, "Чат Элвиса");
});

test("Авто-Allow: обход не подменяет заголовок Claude", async () => {
  const env = page();
  env.loaded.document.title = "Чат Элвиса";
  ask(env, B);
  await warm(env);
  assert.equal(path(env), `/epitaxy/${B}`);
  env.loaded.document.title = "Вкуснофф: накладные";
  env.loaded.inner.autoAllowOnMutation([{ target: { nodeName: "TITLE" }, addedNodes: [] }]);
  assert.equal(env.loaded.document.title, "Вкуснофф: накладные", "заголовок Claude как есть");
  observeGrant(env, B);
  tick(env);
  tick(env);
  tick(env, 2000);
  // Вернулись в A: Claude пишет свой заголовок.
  env.loaded.document.title = "Чат Элвиса";
  tick(env);
  tick(env, 1500);
  assert.equal(path(env), `/epitaxy/${A}`);
  assert.equal(env.loaded.document.title, "Чат Элвиса", "метки нет — замок снимается");
});

test("Авто-Allow: dispose оставляет заголовок Claude", () => {
  const env = page();
  env.loaded.document.title = "Чат Элвиса";
  observeGrant(env, A);
  tick(env);
  env.loaded.api.dispose();
  assert.equal(env.loaded.document.title, "Чат Элвиса");
});

test("#7112: observer разбирает отказ в перекрытом окне, throttle 150 мс", () => {
  const env = page(); const button = unresolvedCard(env);
  env.loaded.inner.autoAllowOnMutation([{ addedNodes: [{ nodeType: 3 }] }]);
  assert.equal(aa(env).mutationRuns, 0);
  env.clock.t += 1000;
  const records = [{ target: env.loaded.document.body, addedNodes: [button.parentElement] }];
  env.loaded.inner.autoAllowOnMutation(records);
  assert.equal(aa(env).blockedLog[0].reason, "manual-required");
  assert.deepEqual(env.stores.granted, []); assert.equal(aa(env).mutationRuns, 1);
  env.clock.t += 149; env.loaded.inner.autoAllowOnMutation(records); assert.equal(aa(env).mutationRuns, 1);
  env.clock.t++; env.loaded.inner.autoAllowOnMutation(records); assert.equal(aa(env).mutationRuns, 2);
  assert.equal(aa(env).blocked, 1);
});

test("Allow вне карточки игнорируется; only-Always внутри не нажимается", () => {
  const env = page(); let foreign = 0;
  const button = env.loaded.document.body.add("button", { text: "Allow", rect: { width: 100, height: 28 } });
  button.addEventListener("click", () => foreign++);
  unresolvedCard(env, "Always allow"); tick(env);
  assert.equal(foreign, 0); assert.deepEqual(env.stores.granted, []);
  assert.equal(aa(env).blockedLog[0].reason, "no-once");
});

test('WF121: запрещённый B возвращает A, не выключает обход и не мешает C; новый запрос снимает дедупликацию', async () => {
  const env = page(); ask(env, B); ask(env, C); await warm(env);
  assert.equal(path(env), `/epitaxy/${B}`);
  const blocked = unresolvedCard(env, 'Allow once', 'Allow Claude to run Bash: /bin/rm sample');
  tick(env);
  assert.equal(path(env), `/epitaxy/${A}`);
  assert.equal(roam(env).skipped[0].reason, 'deletion');
  assert.equal(roam(env).lastRoam.presses, 0); assert.equal(roam(env).disabled, null);
  blocked.parentElement.remove(); // React снял DOM B после возврата, запрос B остался.
  tick(env, 1500); assert.equal(path(env), `/epitaxy/${C}`, 'неизменный B пропущен, следующий C доступен');
  const unknown = unresolvedCard(env); tick(env); unknown.parentElement.remove();
  assert.equal(path(env), `/epitaxy/${A}`);
  for (let i = 0; i < 6; i++) tick(env, 1500);
  assert.equal(path(env), `/epitaxy/${A}`); assert.equal(roam(env).roams, 2);
  assert.equal(roam(env).disabled, null, 'отказ по правилу не считается ошибкой навигации');
  env.stores.perms[B][0].toolUseId = 'new-request';
  tick(env, 1500); assert.equal(path(env), `/epitaxy/${B}`, 'очередь изменилась — можно перечитать карточку');
  const next = unresolvedCard(env); tick(env); next.parentElement.remove();
  assert.equal(roam(env).disabled, null); assert.equal(env.loaded.inner.roamState.empty, 0);
  answered(env, B); tick(env, 1500);
  assert.equal(env.loaded.inner.roamState.blockedRequests.has(B), false);
  ask(env, B); tick(env, 1500); tick(env, 1500);
  assert.equal(path(env), `/epitaxy/${B}`, 'метка исчезла и вернулась — новый заход');
  assert.deepEqual(env.stores.granted, []); env.loaded.api.dispose();
});

test('WF121: неизвестные toolName не попадают в waiting/dry/status или журнал навигации', async () => {
  const env = page({ mode: 'dry' }); ask(env, B, 'unknown_CONTROL_PRIVATE_VALUE_WF121'); await warm(env);
  assert.deepEqual(roam(env).waiting[0].tools, ['unknown']);
  assert.deepEqual(roam(env).lastRoam.tools, ['unknown']);
  assert.ok(!JSON.stringify(aa(env)).includes('CONTROL_PRIVATE_VALUE_WF121')); env.loaded.api.dispose();
});

test('WF121: общий цикл зовёт Trust ровно один раз и при выключенном Allow', () => {
  const env = page({ allow: 'false' });
  env.loaded.win.localStorage.setItem('myclaude-trust-root-v1', '/Users/dev/Projects/');
  const dialog = env.loaded.document.body.add('div', { attrs: { role: 'dialog' } });
  dialog.add('h2', { text: 'Trust this workspace?' });
  dialog.add('div', { text: '/Users/dev/Projects/PimpMyClaude' });
  let clicks = 0;
  for (let i = 0; i < 2; i++) dialog.add('button', { text: 'Trust workspace', rect: { width: 100, height: 24 } })
    .addEventListener('click', () => clicks++);
  tick(env); assert.equal(clicks, 1); assert.equal(env.loaded.api.status().trust.presses, 1);
  env.loaded.api.dispose(); env.loaded.inner.autoAllowCycle(); assert.equal(clicks, 1);
});
