// WF215 (#9377, раздел 12х inject.js): «Прочитано» у ответов. В длинном чате теряется, какие ответы
// прочитаны: слева у ответа — дорожка (одна зона, без правой кнопки), нажал — ответ помечен, сереет и
// сворачивается одним блоком (первая строка + «прочитано»); нажал на блок — раскрыт, пометка остаётся;
// ещё раз на дорожку — пометка снята. Кнопка «непрочитанные N» ведёт к следующему непрочитанному.
//
// Ответ — весь ход ассистента: его id (msg_…) Claude пишет на каждую строку ленты хода
// (data-epitaxy-entry у колонки строки, data-turn-key у сообщения) — это ключ пометки. Лента
// виртуальная: строк вне экрана в DOM нет, список всех ходов — пропс entries у React-узла над лентой.
// Пометки — localStorage["myclaude-read-v1"] = {<ключ чата>: {at, ids}}.
//
// Разметку гоняет люк inner.readTick(); нажатие — click на document, клавиши — keydown на window.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const KEY = "myclaude-read-v1";
const CHAT = "id:local_read-2150";
const ROW = "data-myclaude-read";
const LINE = "data-myclaude-read-line";
const ZONE = "data-myclaude-read-zone";
const OPEN = "data-myclaude-read-open";
const HIT = "data-myclaude-read-hit";
const HOT = "data-myclaude-read-hot";
const LABEL = "data-myclaude-read-label";
const NEXT = "myclaude-read-next";

const user = (id, text = "вопрос") => ({ id, author: "user", rows: [{ kind: "text", text }] });
const answer = (id, ...rows) => ({ id, author: "assistant", rows: rows.length ? rows : [{ kind: "text", text: `ответ ${id}` }] });
const text = (value, extra = {}) => ({ kind: "text", text: value, ...extra });
const tools = (value = "Ran 3 commands") => ({ kind: "tools", text: value });
const image = () => ({ kind: "image" });

// Лента по замеру живого окна 10.10 (Claude 2.31226). mount(index, entry) — строка в DOM или нет
// (виртуальная лента); fiber: false — списка ходов нет; responding — идёт ответ.
const page = ({ entries, mount = () => true, fiber = true, responding = false, above = false, storage = {}, breakStorage = false, title = "Rick", scrollHeight = 9000 } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_read-2150", title,
    storage: { local: { "myclaude-auto-allow-roam": "off", ...storage } },
    html: dom => {
      const parts = dom.composer({});
      const dock = dom.document.body.add("div", { class: "group/approval-dock relative", rect: { left: 0, top: 600, width: 800, height: 180 } });
      const feed = dom.document.body.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: { left: 0, top: 0, width: 800, height: 600 },
      });
      feed.clientHeight = 600;
      feed.scrollHeight = scrollHeight;
      const rows = new Map();
      let index = 0;
      let top = 20;
      entries.forEach((entry, at) => {
        entry.rows.forEach((item, k) => {
          const mine = index;
          const height = item.height ?? 100;
          const place = top;
          index += 1;
          top += height;
          if (!mount(mine, entry)) return;
          const kind = entry.author === "user" ? "human" : "assistant";
          const row = feed.add("div", {
            attrs: { "data-testid": "transcript-row", "data-index": String(mine), "data-perf-row": kind, "data-perf-row-streaming": String(Boolean(item.live)) },
            rect: { left: 0, top: place, width: 800, height },
          });
          const column = row.add("div", { attrs: { "data-epitaxy-entry": entry.id, "data-epitaxy-entry-index": String(at), "data-transcript-column-row": "" } });
          const made = { row, column, entry, item };
          if (kind === "human") column.add("div", { class: "epitaxy-user-turn" }).add("p", { text: item.text });
          else {
            made.message = column.add("div", {
              attrs: { "data-cds": "AssistantMessage", "data-testid": "assistant-message", "data-turn-key": entry.id, ...(item.live ? { "data-is-streaming": "true" } : {}) },
              rect: { left: 24, top: place, width: 752, height },
            });
            if (item.kind === "text") {
              made.prose = made.message.add("div", { class: "prose", attrs: { "data-cds": "Prose" } });
              const host = made.prose.add("div", { class: "contents" });
              made.paras = [];
              for (const line of [].concat(item.html ?? item.text)) {
                made.paras.push(typeof line === "function" ? line(host, dom) : host.add("p", { text: line }));
                // Между блоками в ленте — перевод строки (так их отдаёт innerText браузера).
                host.appendChild(dom.document.createTextNode("\n"));
              }
            } else if (item.kind === "tools") made.message.add("div", { class: "toolrow", text: item.text });
            else made.message.add("img", { attrs: { alt: "картинка", src: "data:image/png;base64,AAAA" } });
          }
          rows.set(`${entry.id}:${k}`, made);
        });
      });
      if (fiber) {
        feed.__reactFiber$test = { memoizedProps: {}, return: { memoizedProps: {
          entries: entries.map(entry => ({ id: entry.id, author: entry.author, items: [] })), isResponding: responding, olderHistoryAbove: above,
        }, return: null } };
      }
      return { ...parts, dock, feed, rows };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  if (breakStorage) loaded.win.localStorage.setItem = () => { const error = new Error("quota"); error.name = "QuotaExceededError"; throw error; };
  loaded.inner.readTick();
  const at = (id, k = 0) => loaded.parts.rows.get(`${id}:${k}`);
  const zone = (id, k = 0) => [...at(id, k).row.childNodes].find(node => node.nodeType === 1 && node.hasAttribute(ZONE)) ?? null;
  const block = (id, k = 0) => [...at(id, k).row.childNodes].find(node => node.nodeType === 1 && node.hasAttribute(OPEN)) ?? null;
  const click = (node, extra = {}) => loaded.dom.document.dispatchEvent({ type: "click", target: node, detail: 1, isTrusted: true, ...extra });
  const key = (name, target, extra = {}) => {
    const event = { type: "keydown", key: name, target, isTrusted: true, bubbles: true, cancelable: true, ...extra };
    return { defaultPrevented: !loaded.win.dispatchEvent(event) };
  };
  const look = id => [...loaded.parts.rows.entries()].filter(([name]) => name.startsWith(`${id}:`)).map(([, made]) => made.row.getAttribute(ROW));
  const stored = () => JSON.parse(loaded.win.localStorage.getItem(KEY) ?? "null");
  const read = () => plain(loaded.api.status().read);
  const next = () => loaded.dom.query(`#${NEXT}`);
  return { loaded, parts: loaded.parts, at, zone, block, click, key, look, stored, read, next, tick: () => loaded.inner.readTick() };
};

const CHAT5 = () => [
  user("u1"), answer("msg_A", text("Сейчас: сайт обновлён."), tools(), text("Что сделано: меню выверено.")),
  user("u2"), answer("msg_B", text("Вот баннер."), image(), text("Подпись под ним.")),
  user("u3"), answer("msg_C", tools("Read 2 files"), text("Остатки по складу."), text("Списания — отдельным листом.")),
  user("u4"), answer("msg_D", text("Бот отвечает гостям без задержек.")),
  user("u5"), answer("msg_E", text("План на завтра.")),
];

// ---- модель: чистые функции через люк -----------------------------------------
const { inner } = loadInject({ title: "Rick" });
const order = (...ids) => ids.map(id => ({ id, assistant: !id.startsWith("u") }));

test("12х: ключ ответа — id хода из строки ленты, а не место в DOM; у реплики человека и служебной строки ключа нет", () => {
  const { at, parts } = page({ entries: CHAT5() });
  assert.equal(inner.readKeyOf(at("msg_A").row), "msg_A");
  assert.equal(inner.readKeyOf(at("msg_A", 2).row), "msg_A", "все строки хода — один ключ");
  assert.equal(inner.readKeyOf(at("msg_B", 1).row), "msg_B", "строка с картинкой — тот же ход");
  assert.equal(inner.readKeyOf(at("u1").row), null);
  // Тот же ход на другом месте ленты (номер строки другой) — ключ тот же.
  at("msg_D").row.setAttribute("data-index", "777");
  assert.equal(inner.readKeyOf(at("msg_D").row), "msg_D");
  // Claude отдал тот же узел строки другому ходу (тот же DOM-узел, новый id) — ключ идёт за ходом.
  at("msg_E").column.setAttribute("data-epitaxy-entry", "msg_Z");
  assert.equal(inner.readKeyOf(at("msg_E").row), "msg_Z");
  // Служебная строка (marker): сообщение есть, хода нет.
  const marker = parts.feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "marker" } });
  marker.add("div", { attrs: { "data-cds": "AssistantMessage" } });
  assert.equal(inner.readKeyOf(marker), null);
  // Старая разметка: id только у сообщения (data-turn-key), строки вида assistant_text.
  const old = parts.feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" } });
  old.add("div", { attrs: { "data-cds": "AssistantMessage", "data-turn-key": "msg_old" } });
  assert.equal(inner.readKeyOf(old), "msg_old");
});

test("12х: непрочитанные — ответы без пометки ПОСЛЕ первого помеченного; без пометок — пусто", () => {
  const list = order("u1", "A", "u2", "B", "u3", "C", "u4", "D", "u5", "E");
  assert.deepEqual(plain(inner.readUnreadOf(list, new Set())), [], "старый чат без пометок — кнопки нет");
  assert.deepEqual(plain(inner.readUnreadOf(list, new Set(["B"]))), ["C", "D", "E"], "A выше первого помеченного — не в счёт");
  assert.deepEqual(plain(inner.readUnreadOf(list, new Set(["B", "D"]))), ["C", "E"]);
  assert.deepEqual(plain(inner.readUnreadOf(list, new Set(["E"]))), [], "помечен последний — непрочитанных нет");
  assert.deepEqual(plain(inner.readUnreadOf(list, new Set(["A", "B", "C", "D", "E"]))), []);
  // Ответ, который ещё пишется, не в счёт.
  assert.deepEqual(plain(inner.readUnreadOf(list, new Set(["B"]), "E")), ["C", "D"]);
  // Пометки есть, но в списке их нет: без незагруженной истории сверху — счёта нет; с ней — пометки
  // лежат выше, и считаются все ответы списка.
  assert.deepEqual(plain(inner.readUnreadOf(list, new Set(["Z"]))), []);
  assert.deepEqual(plain(inner.readUnreadOf(list, new Set(["Z"]), null, true)), ["A", "B", "C", "D", "E"]);
  assert.deepEqual(plain(inner.readUnreadOf(list, new Set(), null, true)), [], "пометок нет вовсе — пусто и с историей сверху");
  assert.deepEqual(plain(inner.readUnreadOf([], new Set(["A"]))), [], "пустой чат");
});

test("12х: следующий непрочитанный — ниже текущего места, после последнего — первый сверху (по кругу)", () => {
  const list = order("u1", "A", "u2", "B", "u3", "C", "u4", "D", "u5", "E");
  const unread = ["C", "E"];
  assert.equal(inner.readNextOf(list, unread, "u1"), "C");
  assert.equal(inner.readNextOf(list, unread, "B"), "C");
  assert.equal(inner.readNextOf(list, unread, "C"), "E", "стоим на непрочитанном — идём к следующему");
  assert.equal(inner.readNextOf(list, unread, "D"), "E");
  assert.equal(inner.readNextOf(list, unread, "E"), "C", "после последнего — к первому");
  assert.equal(inner.readNextOf(list, unread, null), "C", "место неизвестно — первый");
  assert.equal(inner.readNextOf(list, unread, "нет такого"), "C");
  assert.equal(inner.readNextOf(list, ["C"], "C"), "C", "один непрочитанный — он же");
  assert.equal(inner.readNextOf(list, [], "A"), null);
});

// ---- хранилище -----------------------------------------------------------------
test("12х: потолок хранилища — у чата последние пометки, старые чаты уходят первыми, свой чат остаётся", () => {
  const ids = (prefix, count) => Array.from({ length: count }, (_, k) => `${prefix}${k}`);
  // У чата — последние READ_IDS_MAX.
  const one = plain(inner.readStoreTrim({ a: { at: 5, ids: ids("m", inner.READ_IDS_MAX + 30) } }, "a"));
  assert.equal(one.a.ids.length, inner.READ_IDS_MAX);
  assert.equal(one.a.ids[0], "m30", "ушли самые старые пометки");
  assert.equal(one.a.ids.at(-1), `m${inner.READ_IDS_MAX + 29}`);
  // Чатов не больше READ_CHATS_MAX: уходят те, которых дольше не касались; свой — никогда.
  const many = {};
  for (let k = 0; k < inner.READ_CHATS_MAX + 5; k += 1) many[`chat${k}`] = { at: 1000 + k, ids: ["x"] };
  many.mine = { at: 1, ids: ["y"] };
  const kept = plain(inner.readStoreTrim(many, "mine"));
  assert.equal(Object.keys(kept).length, inner.READ_CHATS_MAX);
  assert.ok(kept.mine, "свой чат — самый старый по времени, но остаётся");
  assert.equal(kept.chat0, undefined);
  assert.ok(kept[`chat${inner.READ_CHATS_MAX + 4}`]);
  // Пометок всего не больше READ_TOTAL_MAX.
  const heavy = {};
  const chats = Math.ceil(inner.READ_TOTAL_MAX / inner.READ_IDS_MAX) + 3;
  for (let k = 0; k < chats; k += 1) heavy[`c${k}`] = { at: k + 1, ids: ids(`c${k}-`, inner.READ_IDS_MAX) };
  const light = plain(inner.readStoreTrim(heavy, `c${chats - 1}`));
  assert.ok(Object.values(light).reduce((sum, record) => sum + record.ids.length, 0) <= inner.READ_TOTAL_MAX);
  assert.equal(light.c0, undefined);
  // Мусор и пустое не хранятся; повторы склеиваются.
  assert.deepEqual(plain(inner.readStoreTrim({ a: { at: 1, ids: [] }, b: "мусор", c: { at: 2, ids: ["x", "x", 5, ""] } })), { c: { at: 2, ids: ["x"] } });
  assert.deepEqual(plain(inner.readStoreTrim(null)), {});
});

test("12х: пометка пишется в хранилище под ключом чата и переживает перезагрузку страницы", () => {
  const { loaded, zone, click, look, stored, read } = page({ entries: CHAT5() });
  assert.equal(stored(), null, "без пометок ключа нет");
  click(zone("msg_B"));
  assert.deepEqual(stored()[CHAT].ids, ["msg_B"]);
  assert.ok(stored()[CHAT].at > 0);
  click(zone("msg_C"));
  assert.deepEqual(stored()[CHAT].ids, ["msg_B", "msg_C"]);
  assert.deepEqual(read(), { marked: 2, unread: 2, firstMarked: "msg_B", lastError: null });
  // Перезапись inject.js (перезагрузка страницы тем же окном): пометки те же, ответы снова свёрнуты.
  const again = loaded.reload();
  assert.equal(again.error, null, String(again.error?.stack ?? again.error));
  again.inner.readTick();
  assert.deepEqual(plain(again.api.status().read), { marked: 2, unread: 2, firstMarked: "msg_B", lastError: null });
  assert.deepEqual(look("msg_B"), ["head", "rest", "rest"]);
  // Пометка снята — id ушёл; снята последняя — ключа нет.
  click(zone("msg_B"));
  assert.deepEqual(stored()[CHAT].ids, ["msg_C"]);
  click(zone("msg_C"));
  assert.equal(stored(), null);
});

test("12х: другое окно того же чата видит пометки после события storage; чужой чат пометок не получает", () => {
  const { loaded, look, read } = page({ entries: CHAT5(), storage: { [KEY]: JSON.stringify({ "id:local_other": { at: 1, ids: ["msg_D"] } }) } });
  assert.deepEqual(read(), { marked: 0, unread: 0, lastError: null });
  assert.deepEqual(look("msg_D"), [null]);
  loaded.win.localStorage.setItem(KEY, JSON.stringify({ "id:local_other": { at: 1, ids: ["msg_D"] }, [CHAT]: { at: 2, ids: ["msg_A"] } }));
  loaded.win.dispatchEvent({ type: "storage", key: KEY });
  assert.deepEqual(read(), { marked: 1, unread: 4, firstMarked: "msg_A", lastError: null });
  assert.deepEqual(look("msg_A"), ["head", "rest", "rest"]);
  assert.deepEqual(look("msg_D"), [null], "пометка чужого чата сюда не попала");
  // Запись этого окна не стирает чужой чат.
  loaded.inner.readToggle("msg_D");
  const map = JSON.parse(loaded.win.localStorage.getItem(KEY));
  assert.deepEqual(map["id:local_other"].ids, ["msg_D"]);
  assert.deepEqual(map[CHAT].ids, ["msg_A", "msg_D"]);
});

test("12х: хранилище переполнено — пометки работают до закрытия окна, причина в lastError, ничего не падает", () => {
  const { loaded, zone, click, look, read } = page({ entries: CHAT5(), breakStorage: true });
  click(zone("msg_B"));
  assert.deepEqual(look("msg_B"), ["head", "rest", "rest"], "ответ свёрнут и без хранилища");
  const state = read();
  assert.equal(state.marked, 1);
  assert.equal(state.unread, 3);
  assert.match(state.lastError, /^пометки не сохранены, действуют до закрытия окна: QuotaExceededError$/);
  assert.equal(loaded.win.localStorage.getItem(KEY), null);
  // Следующий проход (перечитка чата) пометок сеанса не теряет.
  loaded.inner.readState.chat = undefined;
  loaded.inner.readTick();
  assert.equal(read().marked, 1);
  assert.deepEqual(look("msg_B"), ["head", "rest", "rest"]);
  // Битая запись в хранилище читается как пустая.
  const broken = page({ entries: CHAT5(), storage: { [KEY]: "{не json" } });
  assert.deepEqual(broken.read(), { marked: 0, unread: 0, lastError: null });
  broken.click(broken.zone("msg_A"));
  assert.deepEqual(broken.stored()[CHAT].ids, ["msg_A"]);
});

// ---- дорожка и свёртка ------------------------------------------------------------
test("12х: дорожка — свой узел в каждой строке ответа; кнопка на ответ одна, с ролью, подписью и местом в порядке Tab", () => {
  const { loaded, at, zone, parts } = page({ entries: CHAT5() });
  const zones = loaded.dom.queryAll(`[${ZONE}]`);
  assert.equal(zones.length, 11, "по дорожке на строку ассистента, у реплик человека дорожек нет");
  assert.equal(zone("u1"), null);
  const first = zone("msg_A");
  assert.equal(first.parentNode, at("msg_A").row);
  assert.equal(first.getAttribute("role"), "button");
  assert.equal(first.getAttribute("tabindex"), "0");
  assert.equal(first.getAttribute("aria-label"), "Прочитано");
  assert.equal(first.getAttribute("aria-pressed"), "false");
  assert.equal(first.getAttribute("title"), "Отметить прочитанным");
  assert.equal(first.textContent, "", "подписи в тексте нет: копия и разбор ответа её не видят");
  for (const k of [1, 2]) {
    const more = zone("msg_A", k);
    assert.equal(more.getAttribute("tabindex"), "-1", "вторая и третья дорожки ответа — не отдельные кнопки");
    assert.equal(more.getAttribute("aria-hidden"), "true");
    assert.equal(more.hasAttribute("role"), false);
  }
  // Узлы Claude на местах: дорожка дописана в конец строки.
  assert.equal(at("msg_A").row.childNodes[0], at("msg_A").column);
  // Место и ширина — по полю слева от текста (24): дорожка 20 целиком в поле, зазор 2 до текста.
  const root = loaded.document.documentElement;
  assert.equal(root.style.getPropertyValue("--myclaude-read-left"), "2px");
  assert.equal(root.style.getPropertyValue("--myclaude-read-width"), "20px");
  assert.equal(root.hasAttribute("data-myclaude-read-tight"), false);
  // Повторный проход ничего не дублирует.
  loaded.inner.readTick(); loaded.inner.readTick();
  assert.equal(loaded.dom.queryAll(`[${ZONE}]`).length, 11);
  assert.equal(zone("msg_A"), first);
  assert.equal(parts.dock.childNodes.length, 0, "без пометок кнопки «непрочитанные» нет");
});

test("12х: узкое поле слева (5) — дорожка не уже 12 и встаёт от края строки, корень помечен", () => {
  const made = page({ entries: CHAT5() });
  for (const item of made.parts.rows.values()) if (item.message) item.message.rect.left = 5;
  made.tick();
  const root = made.loaded.document.documentElement;
  assert.equal(root.style.getPropertyValue("--myclaude-read-left"), "0px");
  assert.equal(root.style.getPropertyValue("--myclaude-read-width"), "12px");
  assert.equal(root.hasAttribute("data-myclaude-read-tight"), true);
});

test("12х: нажал на дорожку — ответ свёрнут одним блоком: первая строка текста, остальные строки и картинка — под ним", () => {
  const { loaded, at, zone, block, click, look } = page({ entries: CHAT5() });
  click(zone("msg_B"));
  assert.deepEqual(look("msg_B"), ["head", "rest", "rest"], "текст-блок, картинка и хвост — один свёрнутый ответ");
  assert.equal(at("msg_B").prose.hasAttribute(LINE), true, "первая строка — блок текста первой строки ответа");
  assert.equal(at("msg_B", 2).prose.hasAttribute(LINE), false);
  assert.equal(zone("msg_B").getAttribute(ZONE), "on");
  assert.equal(zone("msg_B").getAttribute("aria-pressed"), "true");
  assert.equal(zone("msg_B").getAttribute("title"), "Прочитано. Нажми — снять пометку");
  const open = block("msg_B");
  assert.ok(open, "поверх блока — своя кнопка");
  assert.equal(open.getAttribute("role"), "button");
  assert.equal(open.getAttribute("tabindex"), "0");
  assert.equal(open.getAttribute("aria-expanded"), "false");
  assert.equal(open.getAttribute("aria-label"), "Развернуть прочитанный ответ");
  assert.equal(open.textContent, "");
  assert.equal(loaded.dom.queryAll(`[${OPEN}]`).length, 1);
  // Ответ начинается с инструмента — блоком служит первая строка С ТЕКСТОМ.
  click(zone("msg_C"));
  assert.deepEqual(look("msg_C"), ["rest", "head", "rest"]);
  assert.equal(zone("msg_C", 1).getAttribute("tabindex"), "0", "кнопка-дорожка — у видимого блока, а не у спрятанной строки");
  assert.equal(zone("msg_C", 0).getAttribute("tabindex"), "-1");
  // Соседние ответы не тронуты.
  assert.deepEqual(look("msg_A"), [null, null, null]);
  assert.deepEqual(look("msg_D"), [null]);
  assert.equal(loaded.api.status().read.marked, 2);
});

test("12х: ответ без текста (картинка, файл, одни инструменты) — блок «без текста» на первой строке", () => {
  const { at, zone, block, click, look } = page({ entries: [user("u1"), answer("msg_I", image(), tools()), user("u2"), answer("msg_T", text("Готово."))] });
  click(zone("msg_I"));
  assert.deepEqual(look("msg_I"), ["bare", "rest"]);
  assert.ok(block("msg_I"));
  assert.equal(at("msg_T").prose.hasAttribute(LINE), false);
  // Чат из одного ответа.
  const one = page({ entries: [user("u1"), answer("msg_1", text("Единственный ответ."))] });
  one.click(one.zone("msg_1"));
  assert.deepEqual(one.look("msg_1"), ["head"]);
  assert.deepEqual(one.read(), { marked: 1, unread: 0, firstMarked: "msg_1", lastError: null });
  assert.equal(one.next(), null, "непрочитанных нет — кнопки нет");
  // Пустой чат: ничего не рисуем, ничего не падает.
  const none = page({ entries: [] });
  assert.equal(none.loaded.dom.queryAll(`[${ZONE}]`).length, 0);
  assert.deepEqual(none.read(), { marked: 0, unread: 0, lastError: null });
});

test("12х: нажал на блок — ответ раскрыт, пометка остаётся; ещё раз на дорожку — пометка снята", () => {
  const { loaded, at, zone, block, click, look, stored, read } = page({ entries: CHAT5() });
  click(zone("msg_B"));
  click(block("msg_B"));
  assert.deepEqual(look("msg_B"), ["open", "open", "open"], "раскрыт, но помечен");
  assert.equal(at("msg_B").prose.hasAttribute(LINE), false);
  assert.equal(block("msg_B"), null, "кнопки блока больше нет");
  assert.equal(zone("msg_B").getAttribute(ZONE), "on", "тихая пометка у дорожки остаётся");
  assert.equal(zone("msg_B").getAttribute("aria-pressed"), "true");
  assert.deepEqual(stored()[CHAT].ids, ["msg_B"], "раскрытие счёт не меняет");
  assert.equal(read().unread, 3);
  // Раскрытый прочитанный остаётся раскрытым и после следующих проходов.
  loaded.inner.readTick();
  assert.deepEqual(look("msg_B"), ["open", "open", "open"]);
  click(zone("msg_B"));
  assert.deepEqual(look("msg_B"), [null, null, null], "пометка снята");
  assert.equal(zone("msg_B").getAttribute(ZONE), "");
  assert.equal(stored(), null);
  assert.deepEqual(read(), { marked: 0, unread: 0, lastError: null });
  // Снова пометил — снова свёрнут (раскрытие не запоминается за снятой пометкой).
  click(zone("msg_B"));
  assert.deepEqual(look("msg_B"), ["head", "rest", "rest"]);
  // Пометку можно снять и со свёрнутого — одним нажатием на дорожку.
  click(zone("msg_B"));
  assert.deepEqual(look("msg_B"), [null, null, null]);
});

test("12х: Enter и пробел на дорожке и на блоке — как нажатие; двойное нажатие — одно; клавиши мимо своих узлов не трогаем", () => {
  const { at, zone, block, click, key, look } = page({ entries: CHAT5() });
  assert.equal(key("Enter", zone("msg_D")).defaultPrevented, true);
  assert.deepEqual(look("msg_D"), ["head"]);
  assert.equal(key(" ", block("msg_D")).defaultPrevented, true);
  assert.deepEqual(look("msg_D"), ["open"]);
  assert.equal(key(" ", zone("msg_D")).defaultPrevented, true);
  assert.deepEqual(look("msg_D"), [null]);
  // Удержание клавиши не мигает пометкой (и ленту пробелом не листает).
  assert.equal(key("Enter", zone("msg_D"), { repeat: true }).defaultPrevented, true);
  assert.deepEqual(look("msg_D"), [null]);
  // Не свой узел и другие клавиши — мимо.
  assert.equal(key("Enter", at("msg_D").paras[0]).defaultPrevented, false);
  key("Escape", zone("msg_D"));
  key("a", zone("msg_D"));
  assert.deepEqual(look("msg_D"), [null]);
  // Двойной клик — одно нажатие.
  click(zone("msg_D"));
  click(zone("msg_D"), { detail: 2 });
  assert.deepEqual(look("msg_D"), ["head"]);
  // Нажатие по тексту ответа пометку не ставит (зона — только дорожка).
  click(at("msg_E").paras[0]);
  assert.deepEqual(look("msg_E"), [null]);
});

test("12х: наведение на дорожку подсвечивает дорожки ВСЕГО ответа, уход — гасит", () => {
  const { loaded, zone } = page({ entries: CHAT5() });
  loaded.dom.document.dispatchEvent({ type: "pointerover", target: zone("msg_A", 1) });
  for (const k of [0, 1, 2]) assert.equal(zone("msg_A", k).hasAttribute(HOT), true);
  assert.equal(zone("msg_B").hasAttribute(HOT), false);
  loaded.dom.document.dispatchEvent({ type: "pointerout", target: zone("msg_A", 1), relatedTarget: zone("msg_A", 2) });
  assert.equal(zone("msg_A", 0).hasAttribute(HOT), true, "переход между строками того же ответа — подсветка не мигает");
  loaded.dom.document.dispatchEvent({ type: "pointerout", target: zone("msg_A", 2), relatedTarget: loaded.parts.feed });
  for (const k of [0, 1, 2]) assert.equal(zone("msg_A", k).hasAttribute(HOT), false);
});

test("12х: ответ, который ещё пишется, пометить нельзя — ни последний при идущей работе, ни строку с меткой потока", () => {
  // Идёт ответ: последний ход — ассистента.
  const going = page({ entries: CHAT5(), responding: true });
  assert.equal(going.zone("msg_E").getAttribute("aria-disabled"), "true");
  assert.equal(going.zone("msg_E").getAttribute("title"), "Ответ ещё пишется");
  going.click(going.zone("msg_E"));
  going.key("Enter", going.zone("msg_E"));
  assert.deepEqual(going.look("msg_E"), [null]);
  assert.equal(going.stored(), null);
  assert.equal(going.loaded.inner.readToggle("msg_E"), false);
  // Законченные ответы выше помечаются как обычно; пишущийся в счёт непрочитанных не идёт.
  going.click(going.zone("msg_C"));
  assert.deepEqual(going.look("msg_C"), ["rest", "head", "rest"]);
  assert.deepEqual(going.read(), { marked: 1, unread: 1, firstMarked: "msg_C", lastError: null });
  // Наведение на пишущийся ответ дорожку не подсвечивает.
  going.loaded.dom.document.dispatchEvent({ type: "pointerover", target: going.zone("msg_E") });
  assert.equal(going.zone("msg_E").hasAttribute(HOT), false);
  // Идёт работа, но последний ход — реплика человека (ответ ещё не начался): прежний ответ помечается.
  const waiting = page({ entries: [...CHAT5(), user("u6")], responding: true });
  waiting.click(waiting.zone("msg_E"));
  assert.deepEqual(waiting.look("msg_E"), ["head"]);
  // Метка потока на строке (список ходов говорит «не идёт») — тоже нельзя.
  const live = page({ entries: [user("u1"), answer("msg_L", text("Пишу"), text("ещё пишу", { live: true }))] });
  live.click(live.zone("msg_L"));
  assert.deepEqual(live.look("msg_L"), [null, null]);
  // Окно ещё не знает своего чата (пометку некуда записать) — дорожка молчит, нажатие ничего не делает.
  const lost = page({ entries: CHAT5() });
  lost.loaded.inner.readState.chat = null;
  lost.loaded.inner.readPaint();
  assert.equal(lost.zone("msg_A").getAttribute("aria-disabled"), "true");
  assert.equal(lost.zone("msg_A").getAttribute("title"), "Чат ещё открывается");
  lost.click(lost.zone("msg_A"));
  assert.deepEqual(lost.look("msg_A"), [null, null, null]);
  // Помеченный ответ, который снова пишется, показан раскрытым — новое не прячется.
  const back = page({ entries: [user("u1"), answer("msg_L", text("Было"), text("дописываю", { live: true }))], storage: { [KEY]: JSON.stringify({ [CHAT]: { at: 1, ids: ["msg_L"] } }) } });
  assert.deepEqual(back.look("msg_L"), ["open", "open"]);
});

// ---- соседи: разбор ответа не меняется ------------------------------------------
test("12х: свёртка — метками, а не удалением: узлы на местах, innerText ленты тот же, полоса 2б и «Скажи — и сделаю» читают то же", () => {
  const entries = () => [
    user("u1"),
    answer("msg_A", text(["Сделал шапку и поле.", "Дальше — чистые ответы."]), tools(), text([
      host => host.add("h3", { text: "❗ Скажи — и сделаю ❗" }),
      host => { const p = host.add("p"); p.add("strong", { text: "да" }); return p; },
      "⚪PimpMyClaude · WF 2 из 3 · идёт 💭",
    ])),
  ];
  const snapshot = made => {
    made.loaded.win.dispatchEvent({ type: "resize" });
    made.loaded.dom.fireKind("timeout");
    made.loaded.dom.fireKind("raf");
    const { wf, of, state, source } = plain(made.loaded.api.status().progress);
    return {
      progress: { wf, of, state, source },
      say: [...made.loaded.inner.sayButtons()].map(item => item.word),
      feed: made.parts.feed.innerText,
      row: made.at("msg_A", 2).row.innerText,
      kids: [...made.at("msg_A", 2).prose.childNodes[0].childNodes].length,
    };
  };
  // Лента стоит у низа (полоса 2б читает низ ленты), проект окна — тот же, что в строке состояния.
  const plainPage = page({ entries: entries(), title: "PimpMyClaude", scrollHeight: 600 });
  const folded = page({ entries: entries(), title: "PimpMyClaude", scrollHeight: 600 });
  folded.click(folded.zone("msg_A"));
  assert.deepEqual(folded.look("msg_A"), ["head", "rest", "rest"]);
  const before = snapshot(plainPage);
  const after = snapshot(folded);
  assert.deepEqual(after, before, "разбор ответа со свёрнутым прочитанным и без него — один и тот же");
  assert.equal(after.progress.wf, 2);
  assert.equal(after.progress.of, 3);
  assert.equal(after.progress.state, "run");
  assert.deepEqual(after.say, ["да"]);
  assert.ok(after.feed.includes("Сделал шапку и поле.") && after.feed.includes("WF 2 из 3 · идёт 💭"), "спрятанное по-прежнему в тексте ответа («Обкэшить»)");
  // Узлы Claude не удаляются, не переставляются и инлайн-стилей не получают.
  for (const k of [0, 1, 2]) {
    const { row, column, message } = folded.at("msg_A", k);
    assert.ok(row.isConnected && message.isConnected);
    assert.equal(row.childNodes[0], column, "строка: сначала узел Claude, свои — в конце");
    for (const node of [row, column, message]) {
      assert.equal(node.style.getPropertyValue("display"), "");
      assert.equal(node.style.getPropertyValue("visibility"), "");
      assert.equal(node.style.getPropertyValue("height"), "");
    }
  }
  // Правила раздела 4: свёрнутое прячется высотой и прозрачностью, не display и не visibility.
  const rules = [...folded.loaded.inner.RULES];
  const rest = rules.find(rule => rule.startsWith(`[${ROW}="rest"]`));
  assert.ok(rest, "правила свёрнутых строк нет");
  assert.match(rest, /height:0 !important/);
  assert.match(rest, /overflow:hidden !important/);
  assert.ok(!/display|visibility/.test(rest), "display и visibility innerText пропускает — ими прятать нельзя");
  const side = rules.find(rule => rule.includes(`:has([${LINE}]))`) && rule.includes("height:0"));
  assert.ok(side, "правила «всё, кроме первой строки» нет");
  assert.ok(!/display|visibility/.test(side));
  // Блок — одной системой со свёртками 12ф: полоска под ▾ свёрток, отступ 10 px.
  // WF225: правило полосы свёрток 12ф тоже называет строку head (в свёрнутом блоке полосы нет) — блок ищем по началу.
  const band = rules.find(rule => rule.startsWith(`:is([${ROW}="head"]`) && rule.includes("border-left:1.5px solid currentColor"));
  assert.ok(band, "правила блока нет");
  assert.match(band, /margin-left:calc\(var\(--myclaude-fold-mid, 7\.4px\) - \.75px\) !important/);
  assert.match(band, /padding:4px \d+px 4px 10px !important/);
  // Движение короткое и снимается «Уменьшить движение».
  assert.ok(rules.some(rule => rule.startsWith("@media (prefers-reduced-motion: reduce)") && rule.includes(`[${ZONE}]`) && rule.includes("animation:none")));
});

test("12х: свёртки 12ф и «чистые ответы» рядом — свои узлы 12ф живы, метки К-CA на месте, двойной свёртки нет", () => {
  const entries = () => [user("u1"), answer("msg_F", text([
    "Сейчас: сайт первым.", "<details><summary>Подробно</summary>", "Скрытое тело.", "</details>", "Конец.", "🟠Сайт · готово ✅",
  ]))];
  const { loaded, at, zone, block, click, look } = page({ entries: entries() });
  loaded.inner.foldTick();
  loaded.inner.cleanAnswersSync();
  const head = loaded.dom.query("[data-myclaude-fold-head]");
  assert.ok(head, "заголовок свёртки 12ф стоит");
  const body = at("msg_F").paras[2];
  assert.equal(body.getAttribute("data-myclaude-fold-body"), "closed");
  assert.equal(at("msg_F").paras[5].hasAttribute("data-myclaude-clean-line"), true);
  click(zone("msg_F"));
  loaded.inner.foldTick();
  loaded.inner.cleanAnswersSync();
  assert.deepEqual(look("msg_F"), ["head"]);
  assert.equal(loaded.dom.query("[data-myclaude-fold-head]"), head, "заголовок 12ф тот же — под срезом блока");
  assert.equal(body.getAttribute("data-myclaude-fold-body"), "closed");
  assert.equal(at("msg_F").paras[5].hasAttribute("data-myclaude-clean-line"), true);
  assert.equal(loaded.api.status().folds.count, 1);
  // Раскрыл прочитанный — свёртка 12ф работает как раньше.
  click(block("msg_F"));
  loaded.dom.document.dispatchEvent({ type: "click", target: head, detail: 1, isTrusted: true });
  assert.equal(body.getAttribute("data-myclaude-fold-body"), "open");
  assert.deepEqual(look("msg_F"), ["open"]);
});

// ---- виртуальная лента, счёт и переход ---------------------------------------------
test("12х: «непрочитанные N» — в доке поля ввода, подпись из атрибута; счёт идёт и по ответам вне экрана", () => {
  // В DOM — только первые шесть строк (ходы u1…B); C, D, E — вне экрана.
  const { loaded, parts, zone, click, read, next } = page({ entries: CHAT5(), mount: index => index < 8 });
  assert.equal(loaded.dom.queryAll(`[${ZONE}]`).length, 6);
  assert.equal(next(), null, "пометок нет — кнопки нет, хоть ответов и пять");
  click(zone("msg_A"));
  assert.deepEqual(read(), { marked: 1, unread: 4, firstMarked: "msg_A", lastError: null });
  const button = next();
  assert.ok(button, "кнопка появилась");
  assert.equal(button.parentNode, parts.dock);
  assert.equal(button.getAttribute(LABEL), "непрочитанные 4", "три из четырёх — вне экрана");
  assert.equal(button.getAttribute("role"), "button");
  assert.equal(button.getAttribute("tabindex"), "0");
  assert.equal(button.getAttribute("aria-label"), "Непрочитанные ответы: 4. К следующему");
  assert.equal(button.getAttribute("title"), "К следующему непрочитанному ответу");
  assert.equal(button.textContent, "");
  click(zone("msg_B"));
  assert.equal(next().getAttribute(LABEL), "непрочитанные 3");
  assert.equal(next(), button, "тот же узел");
  // Пометка первого снята — счёт начинается со следующего помеченного.
  click(zone("msg_A"));
  assert.deepEqual(read(), { marked: 1, unread: 3, firstMarked: "msg_B", lastError: null });
  click(zone("msg_B"));
  assert.equal(next(), null, "пометок нет — кнопки нет");
  assert.equal(parts.dock.childNodes.length, 0);
});

test("12х: лента не отдала список ходов — счёт только по строкам в DOM, и status().read говорит об этом", () => {
  const { zone, click, read, next } = page({ entries: CHAT5(), mount: index => index < 8, fiber: false });
  click(zone("msg_A"));
  const state = read();
  assert.equal(state.unread, 1, "виден один непрочитанный (B), про ответы вне экрана страница не знает и не выдумывает");
  assert.match(state.lastError, /лента не отдала список ответов/);
  assert.equal(next().getAttribute(LABEL), "непрочитанные 1");
});

test("12х: выше списка есть незагруженная история — пометки, которых в списке нет, лежат там: считаются все ответы", () => {
  const { read, next } = page({ entries: CHAT5(), above: true, storage: { [KEY]: JSON.stringify({ [CHAT]: { at: 1, ids: ["msg_old"] } }) } });
  assert.deepEqual(read(), { marked: 1, unread: 5, lastError: null });
  assert.equal(next().getAttribute(LABEL), "непрочитанные 5");
  // Без незагруженной истории такая пометка счёта не даёт (ход ушёл из чата).
  const gone = page({ entries: CHAT5(), storage: { [KEY]: JSON.stringify({ [CHAT]: { at: 1, ids: ["msg_old"] } }) } });
  assert.deepEqual(gone.read(), { marked: 1, unread: 0, lastError: null });
  assert.equal(gone.next(), null);
});

test("12х: нажал «непрочитанные» — лента ставит следующий непрочитанный ниже на линию чтения и подсвечивает его; по кругу", () => {
  const { loaded, parts, at, zone, click, next } = page({ entries: CHAT5(), storage: { [KEY]: JSON.stringify({ [CHAT]: { at: 1, ids: ["msg_A"] } }) } });
  const line = Math.round(600 * 0.12);
  assert.equal(next().getAttribute(LABEL), "непрочитанные 4");
  // Линия чтения — на первом ходе: следующий непрочитанный ниже — B.
  click(next());
  const topB = at("msg_B").row.rect.top;
  assert.equal(parts.feed.scrollTop, topB - line, "верх ответа B — на линии чтения");
  for (const k of [0, 1, 2]) assert.equal(zone("msg_B", k).hasAttribute(HIT), true, "ответ подсвечен");
  assert.equal(zone("msg_C").hasAttribute(HIT), false);
  assert.equal(loaded.inner.readState.jumps, 1);
  // Подсветка короткая: таймер её снимает.
  loaded.dom.fireKind("timeout");
  assert.equal(zone("msg_B").hasAttribute(HIT), false);
  // Лента стоит на E (последний непрочитанный) — следующий по кругу: B.
  const shift = at("msg_E").row.rect.top - line;
  for (const made of parts.rows.values()) made.row.rect.top -= shift;
  parts.feed.scrollTop = 0;
  click(next());
  assert.equal(loaded.inner.readState.jumped, "msg_B", "после последнего — к первому сверху");
  // Клавиши на кнопке — то же, что нажатие.
  const event = { type: "keydown", key: "Enter", target: next(), isTrusted: true, bubbles: true, cancelable: true };
  assert.equal(loaded.win.dispatchEvent(event), false);
  assert.equal(loaded.inner.readState.jumps, 3);
});

test("12х: непрочитанный вне экрана — лента прокручивается в его сторону, пока строка не придёт, потом встаёт на место", () => {
  // В DOM — ходы u1…B; C…E вне экрана. Помечены A и B → непрочитанные C, D, E.
  const { loaded, parts, at, next, click } = page({
    entries: CHAT5(), mount: index => index < 8, storage: { [KEY]: JSON.stringify({ [CHAT]: { at: 1, ids: ["msg_A", "msg_B"] } }) },
  });
  assert.equal(next().getAttribute(LABEL), "непрочитанные 3");
  click(next());
  assert.equal(loaded.inner.readState.jumped, "msg_C");
  assert.ok(parts.feed.scrollTop > 0, "строки ответа нет в DOM — лента пошла вниз");
  const moved = parts.feed.scrollTop;
  assert.ok(loaded.inner.readState.seek, "переход ещё идёт");
  // Лента «домонтировала» строки ответа C (виртуальный список отдал их после прокрутки).
  const add = (id, k, index, top, kind) => {
    const row = parts.feed.add("div", { attrs: { "data-testid": "transcript-row", "data-index": String(index), "data-perf-row": "assistant" }, rect: { left: 0, top, width: 800, height: 100 } });
    const message = row.add("div", { attrs: { "data-epitaxy-entry": id, "data-transcript-column-row": "" } })
      .add("div", { attrs: { "data-cds": "AssistantMessage", "data-turn-key": id }, rect: { left: 24, top, width: 752, height: 100 } });
    if (kind === "text") message.add("div", { attrs: { "data-cds": "Prose" } }).add("p", { text: "текст" });
    return row;
  };
  const human = parts.feed.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "8", "data-perf-row": "human" }, rect: { left: 0, top: 300, width: 800, height: 100 } });
  human.add("div", { attrs: { "data-epitaxy-entry": "u3" } });
  const first = add("msg_C", 0, 9, 400, "tools");
  add("msg_C", 1, 10, 500, "text");
  loaded.dom.fireKind("timeout");
  assert.equal(parts.feed.scrollTop, moved + (400 - Math.round(600 * 0.12)), "верх первой строки ответа — на линии чтения");
  assert.ok([...first.childNodes].some(node => node.nodeType === 1 && node.hasAttribute(HIT)), "ответ подсвечен, дорожка у новой строки стоит");
  // Колесо мыши снимает переход: страница не спорит с рукой.
  assert.ok(loaded.inner.readState.seek);
  loaded.win.dispatchEvent({ type: "wheel", target: parts.feed });
  assert.equal(loaded.inner.readState.seek, null);
  assert.ok(at("msg_A").row.isConnected);
});

test("12х: пометка и раскрытие не дёргают прокрутку — верх ответа виден: блок встаёт на его место", () => {
  const { parts, zone, block, click } = page({ entries: CHAT5() });
  parts.feed.scrollTop = 0;
  click(zone("msg_A"));
  assert.equal(parts.feed.scrollTop, 0, "верх ответа виден — лента не прокручивается");
  click(block("msg_A"));
  assert.equal(parts.feed.scrollTop, 0, "раскрытие — вниз от блока, лента на месте");
  click(zone("msg_A"));
  assert.equal(parts.feed.scrollTop, 0, "пометка снята с раскрытого — высота та же");
});

test("12х: виден только низ ответа — после свёртки на месте остаётся то, что под ним", () => {
  const { parts, at, zone, click } = page({ entries: CHAT5() });
  // Ответ A: три строки по 100, верх выше ленты (−150), низ на экране (150).
  const shift = at("msg_A").row.rect.top + 150;
  for (const made of parts.rows.values()) made.row.rect.top -= shift;
  parts.feed.scrollTop = 1000;
  click(zone("msg_A", 2));
  // Блок (первая строка, высота 100) встаёт низом на прежний низ ответа: верх −150 → 50.
  assert.equal(parts.feed.scrollTop, 1000 + (-150 - (150 - 100)));
});

test("12х: строки ленты пришли заново при прокрутке — метки прочитанного возвращаются сразу, начало вне экрана — блока пока нет", () => {
  const made = page({ entries: CHAT5(), storage: { [KEY]: JSON.stringify({ [CHAT]: { at: 1, ids: ["msg_C"] } }) }, mount: index => index !== 9 });
  // Начало ответа C (строка 9, инструменты) не в DOM: строки 10 и 11 свёрнуты, блока нет.
  assert.deepEqual(made.look("msg_C"), ["rest", "rest"]);
  assert.equal(made.loaded.dom.queryAll(`[${OPEN}]`).length, 0);
  // Все строки на месте — блок на первой строке с текстом.
  const whole = page({ entries: CHAT5(), storage: { [KEY]: JSON.stringify({ [CHAT]: { at: 1, ids: ["msg_C"] } }) } });
  assert.deepEqual(whole.look("msg_C"), ["rest", "head", "rest"]);
  // Лента убрала из DOM строку над блоком (она нулевой высоты): блок остаётся блоком — высота ленты не скачет.
  const lead = whole.at("msg_C", 0).row;
  lead.remove();
  whole.loaded.inner.onMutated([{ type: "childList", target: whole.parts.feed, addedNodes: [], removedNodes: [lead] }]);
  assert.deepEqual(whole.look("msg_C").slice(1), ["head", "rest"], "начало ответа ушло из DOM, блок — на той же строке");
  assert.equal(whole.block("msg_C", 1) != null, true);
  whole.parts.feed.insertBefore(lead, whole.at("msg_C", 1).row);
  whole.loaded.inner.readPaint();
  assert.deepEqual(whole.look("msg_C"), ["rest", "head", "rest"]);
  // Claude пересоздал строку (узел новый, меток нет): следующий проход ставит их заново, старых узлов не держит.
  const { row } = whole.at("msg_C", 2);
  row.removeAttribute(ROW);
  for (const node of [...row.childNodes]) if (node.nodeType === 1 && node.hasAttribute(ZONE)) node.remove();
  whole.loaded.inner.onMutated([{ type: "childList", target: whole.parts.feed, addedNodes: [row], removedNodes: [] }]);
  assert.equal(row.getAttribute(ROW), "rest", "метка вернулась прямо в колбэке мутаций — до отрисовки");
  assert.equal(whole.loaded.dom.queryAll(`[${ZONE}]`).length, 11);
  // Тот же узел строки отдан другому ходу (меняются только атрибуты и текст): прежняя метка снята.
  const tail = whole.at("msg_C", 2);
  tail.column.setAttribute("data-epitaxy-entry", "msg_D2");
  whole.loaded.inner.onMutated([{ type: "characterData", target: tail.paras[0], addedNodes: [], removedNodes: [] }]);
  assert.equal(tail.row.hasAttribute(ROW), false, "строка другого, непрочитанного хода не остаётся свёрнутой");
  assert.deepEqual(whole.look("msg_C").slice(0, 2), ["rest", "head"]);
});

// ---- уборка ---------------------------------------------------------------------
test("12х: dispose убирает всё своё — дорожки, кнопки, метки и переменные; пометки в хранилище остаются", () => {
  const { loaded, zone, click, stored, next } = page({ entries: CHAT5() });
  click(zone("msg_B"));
  assert.ok(next());
  const root = loaded.document.documentElement;
  assert.notEqual(root.style.getPropertyValue("--myclaude-read-left"), "");
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`[${ZONE}]`).length, 0);
  assert.equal(loaded.dom.queryAll(`[${OPEN}]`).length, 0);
  assert.equal(loaded.dom.queryAll(`[${ROW}]`).length, 0);
  assert.equal(loaded.dom.queryAll(`[${LINE}]`).length, 0);
  assert.equal(loaded.dom.query(`#${NEXT}`), null);
  assert.equal(root.style.getPropertyValue("--myclaude-read-left"), "");
  assert.equal(root.style.getPropertyValue("--myclaude-read-width"), "");
  assert.equal(root.hasAttribute("data-myclaude-read-tight"), false);
  assert.deepEqual(stored()[CHAT].ids, ["msg_B"], "пометки — данные человека, уборка их не трогает");
  // Нажатие после уборки ничего не делает.
  const stale = loaded.parts.rows.get("msg_A:0").row;
  loaded.dom.document.dispatchEvent({ type: "click", target: stale, detail: 1, isTrusted: true });
  assert.equal(loaded.dom.queryAll(`[${ROW}]`).length, 0);
});
