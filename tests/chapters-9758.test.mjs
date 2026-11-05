// #9758 и #9757 (раздел 12х² inject.js, 17.10): главы тише, звёздочка-закладка, каждый ответ — глава; свой текст
// справа — тише (12ф⁴). Слова Элвиса 11.10 08:24: «метки… слева… более бледными… каждый твой ответ… заголовки…
// побольше там писать инфы… чтобы я мог звёздочкой пометить… галочки рядом и звёздочки сделай рядом… текущую главу
// сделай менее яркой… текст справа, который мой… менее ярким… как второстепенный»; 11.10 07:27: «каждый твой ответ —
// это глава. Я по ним, чтобы мне по ним удобно было ходить».
//
// Стенд — дорожка глав Claude (как в chapters-wf241: nav > ol[aria-hidden] полоски, div > ol[role=list] строки) с
// пропсами глав (chapter {id, title, source, entryId, entryIndex} — так их строит Claude из ходов ленты) и лента
// с пропсом entries (ходы, у хода ассистента items: text | chapter | tools). Ходы: u0, A1 (глава Claude), u2,
// A3 (жирный итог), u4, A5 (короткий «Готово.»), u6, A7 (без жирной строки), u8, A9 (закреплён человеком).
//
// Что проверяется:
//   1) название своей главы и план своих глав — чистые функции;
//   2) свои главы встают в обе колонки между главами Claude по порядку ленты, с галочкой и звёздочкой; узлы
//      Claude не двигаются; ход получил главу Claude — своя уходит; мест глав Claude нет — своих нет, причина в
//      lastError; ответ, который ещё пишется, — без главы;
//   3) нажатие по своей главе — переход к её ответу; двойное — «прочитано»; главы Claude по-прежнему у Claude;
//   4) текущая своя глава по линии чтения: её полоска текущая, на nav метка; у низа ленты — снова Claude;
//   5) звёздочка: мышь и клавиша ставят и снимают, хранилище своё, полоска дорожки янтарная, «прочитано» не
//      трогается; переживает повторную установку;
//   6) вид: тише по умолчанию, текст человека — вторичным цветом; dispose убирает своё.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_chapters-9758";
const CHAT_KEY = `id:${CHAT}`;
const READ_KEY = "myclaude-chapters-read-v1";
const STAR_KEY = "myclaude-chapters-star-v1";
const OWN = "data-myclaude-ch-own";
const STAR = "data-myclaude-ch-star";
const STARRED = "data-myclaude-ch-starred";
const CHECK = "data-myclaude-ch-check";
const MINE = "data-myclaude-ch-mine";
const READ = "data-myclaude-ch-read";

const IDLE = "block h-[2px] rounded-full w-[calc(var(--chat-gutter)*3/8+2px)] origin-left scale-x-[calc(9/14)] bg-alpha-3";
const NOW = "block h-[2px] rounded-full w-[calc(var(--chat-gutter)*3/8+2px)] origin-left bg-alpha-8";
const BUTTON = "group/ch w-full flex items-center gap-sm px-1.25 h-control rounded-[5px] text-left hover:bg-fill-ghost-hover";

const text = value => ({ kind: "text", text: value });
const ENTRIES = () => [
  { id: "u0", author: "user", items: [text("начнём")] },
  { id: "A1", author: "assistant", items: [{ kind: "chapter", id: "ch-1", title: "Утро" }, text("**✅ Утренние дела розданы, марафон Пимпа идёт третьим кругом.**")] },
  { id: "u2", author: "user", items: [text("что с ракетой")] },
  { id: "A3", author: "assistant", items: [text("Работа идёт 💭\n\n### ❗ Ждёт тебя\n1. ⚠️ **Срочно воткни зарядку.** Батарея на 24 %.\n\n✅ **Ракета снова показывается по нажатию: «Показать ракету» больше не молчит.**\n\nПодробности ниже.")] },
  { id: "u4", author: "user", items: [text("ок")] },
  { id: "A5", author: "assistant", items: [text("Готово.")] },
  { id: "u6", author: "user", items: [text("а галерея")] },
  { id: "A7", author: "assistant", items: [{ kind: "tools" }, text("Галерея теперь отвечает всегда, даже когда окно закрыто. Проверил на стенде.\n\nДальше — сторож снимков.")] },
  { id: "u8", author: "user", items: [text("закрепи")] },
  { id: "A9", author: "assistant", items: [text("**Сторож снимков работает службой и сам поднимается после перезагрузки Мака.**")] },
];
// Главы Claude: сессия (ход 0), глава Claude в A1, закреплённая человеком на A9; текущая — A1.
const NATIVE = [
  { id: "session", title: "Rick", source: "session", entryId: "u0", entryIndex: 0 },
  { id: "ch-1", title: "Утро", source: "claude", entryId: "A1", entryIndex: 1, itemIndex: 0 },
  { id: "uch-9", title: "Сторож снимков", source: "user", entryId: "A9", entryIndex: 9 },
];
const ROW_H = 100;

const page = ({ entries = ENTRIES(), natives = NATIVE, storage = {}, responding = false, win = null, positions = true } = {}) => {
  const nodes = { rail: [], rows: [], buttons: [], feedRows: new Map() };
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off", ...storage } },
    html: dom => {
      const parts = dom.composer({});
      nodes.feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: { left: 0, top: 0, width: 800, height: 600 } });
      nodes.feed.clientHeight = 600;
      nodes.feed.scrollHeight = entries.length * ROW_H + 600;
      entries.forEach((entry, at) => {
        const row = nodes.feed.add("div", {
          attrs: { "data-testid": "transcript-row", "data-index": String(at), "data-perf-row": entry.author === "user" ? "human" : "assistant", "data-perf-row-streaming": "false" },
          rect: { left: 0, top: at * ROW_H, width: 800, height: ROW_H },
        });
        const column = row.add("div", { attrs: { "data-epitaxy-entry": entry.id, "data-epitaxy-entry-index": String(at) } });
        if (entry.author === "assistant") column.add("div", { attrs: { "data-cds": "AssistantMessage", "data-turn-key": entry.id } }).add("div").add("div", { attrs: { "data-cds": "Prose" } }).add("p", { text: entry.items.find(item => item.kind === "text")?.text ?? "" });
        else column.add("div", { attrs: { "data-cds": "UserMessage" } }).add("div", { class: "text-primary" }).add("p", { text: "вопрос" });
        nodes.feedRows.set(entry.id, row);
      });
      nodes.feed.__reactFiber$test = { memoizedProps: {}, return: { memoizedProps: { entries, isResponding: responding, olderHistoryAbove: false }, return: null } };
      const toc = dom.document.body.add("div", { class: "epitaxy-toc absolute pointer-events-none" });
      nodes.nav = toc.add("nav", { attrs: { "aria-label": "Session chapters", tabindex: "0" }, rect: { left: 8, top: 48, width: 32, height: 400 } });
      nodes.railList = nodes.nav.add("ol", { attrs: { "aria-hidden": "true" }, class: "flex flex-col" });
      nodes.menu = nodes.nav.add("div", { class: "absolute start-0 top-0 invisible opacity-0" });
      nodes.list = nodes.menu.add("ol", { attrs: { role: "list" } });
      natives.forEach((chapter, index) => {
        const now = chapter.id === "ch-1";
        nodes.rail.push(nodes.railList.add("li", { class: "h-[8px] flex items-center" }));
        nodes.rail[index].add("span", { class: now ? NOW : IDLE });
        const row = nodes.list.add("li");
        const button = row.add("button", { attrs: { type: "button", ...(now ? { "aria-current": "true" } : {}) }, class: `${BUTTON} ${now ? "text-primary" : "text-secondary hover:text-primary"}` });
        button.add("span", { attrs: { "aria-hidden": "true" }, class: "block h-[2px] rounded-full shrink-0" });
        button.add("span", { class: "flex-1 min-w-0 truncate text-body", text: chapter.title });
        const props = positions ? chapter : { id: chapter.id, title: chapter.title };
        button.__reactFiber$test = { memoizedProps: {}, return: { memoizedProps: { chapter: props }, return: null } };
        nodes.rows.push(row);
        nodes.buttons.push(button);
      });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  if (win) loaded.win.localStorage = win.localStorage;
  const tick = () => { loaded.inner.readTick(); loaded.inner.chTick(); };
  tick();
  return { loaded, nodes, tick };
};
const status = loaded => plain(loaded.api.status().chapters);
const kids = list => [...list.children];
const ownRows = nodes => kids(nodes.list).filter(node => node.hasAttribute(OWN));
const titleOf = row => [...row.children].find(node => node.tagName === "BUTTON" && !node.hasAttribute(CHECK) && !node.hasAttribute(STAR))?.textContent ?? null;
const starOf = row => [...row.children].find(node => node.hasAttribute(STAR)) ?? null;
const checkOf = row => [...row.children].find(node => node.hasAttribute(CHECK)) ?? null;
const send = (loaded, type, target, extra = {}) => {
  const claude = [];
  const listener = () => claude.push(type);
  loaded.document.addEventListener(type, listener);
  const prevented = !loaded.document.dispatchEvent({ type, target, button: 0, detail: 1, clientX: 60, clientY: 120, ...extra });
  loaded.document.removeEventListener(type, listener);
  return { prevented, reached: claude.length > 0 };
};
const key = (loaded, name, target, extra = {}) => !loaded.win.dispatchEvent({ type: "keydown", key: name, target, ...extra });
// Прокрутить ленту: строки едут вверх на px (линия чтения — верх ленты + 64).
const scroll = (loaded, nodes, px) => {
  nodes.feed.scrollTop = px;
  nodes.feedRows.forEach((row, id) => { row.rect = { ...row.rect, top: ENTRIES().findIndex(entry => entry.id === id) * ROW_H - px }; });
  loaded.document.dispatchEvent({ type: "scroll", target: nodes.feed });
  loaded.dom.fireKind("raf");
};
const css = loaded => String(loaded.dom.query("#myclaude-input-handle-style").textContent ?? "").split("\n");
const rule = (loaded, start) => css(loaded).find(line => line.startsWith(start)) ?? "";

// ---- чистые функции через люк ---------------------------------------------------
const { inner } = loadInject({ title: "Rick" });

test("#9758: название своей главы — целиком жирная строка итога, со значком; шаги и служебное мимо; короткий ответ — без главы", () => {
  const title = items => inner.chTitleOf(items);
  assert.equal(title(ENTRIES()[3].items), "✅ Ракета снова показывается по нажатию: «Показать ракету» больше не молчит.",
    "жирная строка итога; «Работа идёт», заголовок «Ждёт тебя» и пункт с жирным началом — не название");
  assert.equal(title([text("**✅ Пимп 1.10.33 собран и подписан, ракета больше не молчит.**")]), "✅ Пимп 1.10.33 собран и подписан, ракета больше не молчит.");
  assert.equal(title([text("Работа идёт 💭\n\nГалерея теперь отвечает всегда, даже когда окно закрыто.\n\nДальше — сторож.")]),
    "Галерея теперь отвечает всегда, даже когда окно закрыто.", "жирной нет — первая строка текста");
  assert.equal(title([text("### Итог дня\n\n- [ссылка](https://x.y) на отчёт и `код` готовы к проверке")]), "ссылка на отчёт и код готовы к проверке", "разметка снята");
  assert.equal(title([text("Готово.")]), null, "короткий служебный ответ — без главы");
  assert.equal(title([text("·")]), null, "точка — без главы");
  assert.equal(title([text("Работа идёт 💭")]), null, "один шаг — без главы");
  assert.equal(title([{ kind: "tools" }]), null);
  assert.equal(title(null), null);
  const long = title([text(`**${"Очень подробный итог работы над главами и лентой ".repeat(5)}**`)]);
  assert.ok(long.length <= 161 && long.endsWith("…") && !long.endsWith(" …"), long);
});

test("#9757: план своих глав — ответы без главы Claude по порядку ленты; пишущийся и пропущенные — без", () => {
  const plan = (entries, chapters, skip) => plain(inner.chOwnPlan(entries, chapters, skip));
  assert.deepEqual(plan(ENTRIES(), NATIVE).map(item => [item.id, item.index]), [["A3", 3], ["A7", 7]],
    "A1 — глава Claude (блок chapter), A9 — закреплён человеком, A5 короткий, реплики человека — не ответы");
  assert.deepEqual(plan(ENTRIES(), [], new Set(["A7"])).map(item => item.id), ["A3", "A9"], "без пропсов глав A1 всё равно с главой (блок chapter)");
  assert.deepEqual(plan(null, NATIVE), []);
  assert.deepEqual(plan([{ id: "x", author: "assistant" }], []), [], "ход без блоков");
});

// ---- свои главы в дорожке ------------------------------------------------------

test("#9757: свои главы встают в обе колонки между главами Claude, с названием, галочкой и звёздочкой", () => {
  const { loaded, nodes } = page();
  const order = list => kids(list).map(node => (node.hasAttribute(OWN) ? `own:${node.__myclaudeOwn ?? "rail"}` : "claude"));
  assert.deepEqual(order(nodes.list), ["claude", "claude", "own:A3", "own:A7", "claude"]);
  assert.deepEqual(kids(nodes.railList).map(node => node.hasAttribute(OWN)), [false, false, true, true, false], "полоски — те же места");
  assert.deepEqual(kids(nodes.list).filter(node => !node.hasAttribute(OWN)), nodes.rows, "строки Claude не переставлены");
  const [a3, a7] = ownRows(nodes);
  assert.equal(titleOf(a3), "✅ Ракета снова показывается по нажатию: «Показать ракету» больше не молчит.");
  assert.equal(titleOf(a7), "Галерея теперь отвечает всегда, даже когда окно закрыто. Проверил на стенде.");
  assert.ok(checkOf(a3) && starOf(a3), "галочка и звёздочка — как у глав Claude");
  const strip = kids(nodes.railList)[2].firstElementChild;
  assert.equal(strip.getAttribute("class"), IDLE, "полоска — как обычная глава Claude");
  const button = [...a3.children][0];
  assert.match(button.getAttribute("class"), /text-secondary hover:text-primary$/);
  assert.ok(!/(^|\s)text-primary(\s|$)/.test(button.getAttribute("class")), "цвет — обычной главы, не текущей");
  assert.deepEqual(status(loaded), { count: 5, read: 0, starred: 0, own: 2, open: false, settings: false, lastError: null });
  // Повторный проход ничего не двигает и не плодит.
  const before = kids(nodes.list);
  loaded.inner.chTick();
  assert.deepEqual(kids(nodes.list), before);
});

test("#9757: ход получил главу Claude — своя уходит; ответ, который пишется, — без главы; мест глав нет — своих нет", () => {
  const { loaded, nodes, tick } = page();
  const entries = ENTRIES();
  entries[3] = { ...entries[3], items: [{ kind: "chapter", id: "ch-3", title: "Ракета" }, ...entries[3].items] };
  nodes.feed.__reactFiber$test.return.memoizedProps = { entries, isResponding: false, olderHistoryAbove: false };
  tick();
  assert.deepEqual(ownRows(nodes).map(row => row.__myclaudeOwn), ["A7"]);
  assert.equal(kids(nodes.railList).filter(node => node.hasAttribute(OWN)).length, 1, "полоска ушла вместе со строкой");

  // Последний ответ ещё пишется — главы у него нет, пока не допишется.
  const live = ENTRIES().slice(0, 8);
  const busy = page({ entries: live, natives: NATIVE.slice(0, 2), responding: true });
  assert.deepEqual(ownRows(busy.nodes).map(row => row.__myclaudeOwn), ["A3"]);

  const blind = page({ positions: false });
  assert.equal(ownRows(blind.nodes).length, 0, "Claude не отдал мест глав — свои не встают наугад");
  assert.match(status(blind.loaded).lastError, /нет места в ленте/);
});

test("#9757: нажатие по своей главе — переход к ответу; двойное — «прочитано»; глава Claude — у Claude", () => {
  const { loaded, nodes } = page();
  const [a3] = ownRows(nodes);
  const button = [...a3.children][0];
  const jump = send(loaded, "click", button);
  assert.deepEqual(jump, { prevented: true, reached: false }, "своё нажатие до Claude не доходит");
  assert.equal(nodes.feed.scrollTop, 3 * ROW_H - 72, "ответ A3 встал на линию чтения (12 % высоты ленты)");
  // #10764 (слово Элвиса 23.10 20:4x): глава Claude в ответе — переход наш, к началу ответа, а не к месту главы.
  const native = send(loaded, "click", nodes.buttons[1]);
  assert.deepEqual(native, { prevented: true, reached: false }, "переход по главе Claude в ответе — к началу ответа");
  const double = send(loaded, "dblclick", button, { detail: 2 });
  assert.equal(double.prevented, true);
  assert.equal(a3.hasAttribute(READ), true);
  assert.deepEqual(JSON.parse(loaded.win.localStorage.getItem(READ_KEY))[CHAT_KEY].ids, ["a:A3"], "ключ своей главы — ход ответа");
  assert.equal(kids(nodes.railList)[2].hasAttribute(READ), true, "полоска зелёная");
});

test("меню после перехода: уходит после щелчка мышью, второе нажатие держит его, клавиатура и галочка не закрывают", () => {
  const OPEN = "data-myclaude-ch-open";
  const open = () => {
    const made = page();
    send(made.loaded, "mouseover", made.nodes.railList);
    made.loaded.dom.fireKind("timeout");
    assert.equal(made.nodes.nav.hasAttribute(OPEN), true);
    return made;
  };
  const after = ({ loaded, nodes }) => { loaded.dom.fireKind("timeout"); return nodes.nav.hasAttribute(OPEN); };
  // Своя строка: щелчок закрывает с задержкой.
  let made = open();
  let button = [...ownRows(made.nodes)[0].children][0];
  send(made.loaded, "click", button);
  assert.equal(made.nodes.nav.hasAttribute(OPEN), true, "сразу меню не уходит");
  assert.equal(after(made), false, "после выдержки ушло");
  // Двойное нажатие: решает второе нажатие, а не второе отпускание.
  made = open();
  const row = ownRows(made.nodes)[0];
  button = [...row.children][0];
  send(made.loaded, "click", button);
  send(made.loaded, "mousedown", button);
  assert.equal(after(made), true, "второе нажатие сняло уход, меню дождалось отпускания");
  send(made.loaded, "dblclick", button, { detail: 2 });
  assert.equal(row.hasAttribute(READ), true, "отметка встала");
  // Enter по строке: click с detail 0, меню и фокус на месте.
  made = open();
  send(made.loaded, "click", [...ownRows(made.nodes)[0].children][0], { detail: 0 });
  assert.equal(after(made), true, "с клавиатуры меню остаётся");
  // Родная глава с переходом страницы и родная с переходом Claude: уходит так же, переход не трогаем.
  made = open();
  assert.equal(send(made.loaded, "click", made.nodes.buttons[1]).reached, false);
  assert.equal(after(made), false, "глава Claude в ответе");
  made = open();
  send(made.loaded, "click", made.nodes.buttons[1], { detail: 0 });
  assert.equal(after(made), true, "глава Claude в ответе, с клавиатуры");
  made = open();
  assert.equal(send(made.loaded, "click", made.nodes.buttons[0]).reached, true, "«Session start» — переход Claude");
  assert.equal(after(made), false, "глава Claude вне ответа");
  // Галочка меню не закрывает.
  made = open();
  send(made.loaded, "click", checkOf(made.nodes.rows[0]));
  assert.equal(after(made), true, "галочка");
});

test("запас меню считается заново при смене ширины окна, пока меню открыто", () => {
  const ROOM = "--myclaude-ch-room";
  const { loaded, nodes } = page();
  let right = 900;
  const closest = nodes.nav.closest.bind(nodes.nav);
  nodes.nav.closest = selector => (selector === ".epitaxy-chat-panel" ? { getBoundingClientRect: () => ({ right }) } : closest(selector));
  send(loaded, "mouseover", nodes.railList);
  loaded.dom.fireKind("timeout");
  assert.equal(nodes.nav.style.getPropertyValue(ROOM), "892px");
  right = 500;
  loaded.win.dispatchEvent({ type: "resize" });
  assert.equal(nodes.nav.style.getPropertyValue(ROOM), "492px");
});

test("#9757: текущая своя глава — по линии чтения; у низа ленты и над первой своей — текущая Claude", () => {
  const { loaded, nodes } = page();
  const strip = index => kids(nodes.railList)[index].firstElementChild.getAttribute("class");
  assert.equal(nodes.nav.hasAttribute(MINE), false, "у линии чтения A1 — глава Claude");
  scroll(loaded, nodes, 3 * ROW_H + 10);
  assert.equal(strip(2), NOW, "A3 у линии чтения — его полоска текущая");
  assert.equal([...ownRows(nodes)[0].children][0].getAttribute("aria-current"), "true");
  assert.equal(nodes.nav.hasAttribute(MINE), true, "текущая Claude показана обычной (правило по метке)");
  scroll(loaded, nodes, 7 * ROW_H + 10);
  assert.equal(strip(2), IDLE);
  assert.equal(strip(3), NOW, "дальше — A7");
  scroll(loaded, nodes, 9 * ROW_H + 10);
  assert.equal(nodes.nav.hasAttribute(MINE), false, "A9 — снова глава Claude");
  assert.equal(strip(3), IDLE);
  scroll(loaded, nodes, nodes.feed.scrollHeight - nodes.feed.clientHeight);
  assert.equal(nodes.nav.hasAttribute(MINE), false, "у низа — последняя глава, она Claude");
  const mine = rule(loaded, `.epitaxy-toc > nav[${MINE}]>ol[aria-hidden="true"]>li:not([${OWN}])>span[class~="bg-alpha-8"]{`);
  assert.match(mine, /opacity:var\(--myclaude-ch-ink,0\.35\);scale:calc\(9\/14\) 1 !important/);
});

// ---- звёздочка -------------------------------------------------------------------

test("#9758: звёздочка рядом с галочкой ставит и снимает закладку — мышью и клавишей; своё хранилище; полоска янтарная", () => {
  const { loaded, nodes } = page();
  // Меню открыто наведением (звёздочки видны только в нём).
  send(loaded, "mouseover", nodes.railList);
  loaded.dom.fireKind("timeout");
  const star = starOf(nodes.rows[1]);
  assert.equal(star.getAttribute("aria-pressed"), "false");
  assert.equal(star.getAttribute("title"), "Добавить главу в закладки");
  assert.equal(send(loaded, "mousedown", star).prevented, true, "нажатие фокус поля не отнимает");
  const click = send(loaded, "click", star);
  assert.deepEqual(click, { prevented: true, reached: false });
  assert.equal(star.getAttribute("aria-pressed"), "true");
  assert.equal(star.getAttribute("aria-label"), "Убрать главу из закладок");
  assert.equal(nodes.rows[1].hasAttribute(STARRED), true);
  assert.equal(nodes.rail[1].hasAttribute(STARRED), true, "полоска главы на дорожке — закладкой");
  assert.equal(nodes.rows[1].hasAttribute(READ), false, "«прочитано» не тронуто");
  assert.deepEqual(JSON.parse(loaded.win.localStorage.getItem(STAR_KEY))[CHAT_KEY].ids, ["id:ch-1"]);
  assert.equal(loaded.win.localStorage.getItem(READ_KEY), null);
  // Своя глава — тоже; клавишей.
  const ownStar = starOf(ownRows(nodes)[1]);
  assert.equal(key(loaded, "Enter", ownStar), true, "Enter на звёздочке — её, до Claude не идёт");
  assert.deepEqual(JSON.parse(loaded.win.localStorage.getItem(STAR_KEY))[CHAT_KEY].ids, ["id:ch-1", "a:A7"]);
  assert.equal(status(loaded).starred, 2);
  // Двойное нажатие по звёздочке — не «прочитано».
  send(loaded, "dblclick", star, { detail: 2 });
  assert.equal(nodes.rows[1].hasAttribute(READ), false);
  // Повторная установка — закладки на месте.
  const again = page({ win: loaded.win });
  again.loaded.inner.chTick();
  assert.equal(starOf(again.nodes.rows[1]).getAttribute("aria-pressed"), "true");
  send(again.loaded, "click", starOf(again.nodes.rows[1]));
  assert.deepEqual(JSON.parse(again.loaded.win.localStorage.getItem(STAR_KEY))[CHAT_KEY].ids, ["a:A7"], "снял — снято");
  assert.match(rule(loaded, `.epitaxy-toc > nav > ol[aria-hidden="true"]>li[${STARRED}]>span{`), /background-color:rgb\(245,158,11\) !important/);
  assert.match(rule(loaded, `[${STAR}]{`), /left:calc\(var\(--chat-gutter,32px\)\*9\/16 \+ 31px\)/, "звёздочка — сразу за галочкой");
});

// ---- вид и уборка ------------------------------------------------------------------

test("#9758: свой текст справа — вторичным цветом темы; dispose убирает свои главы, звёздочки и метки", () => {
  const { loaded, nodes } = page();
  assert.ok(css(loaded).includes(`[data-cds="UserMessage"]>div{color:var(--cds-text-secondary) !important}`));
  send(loaded, "click", starOf(nodes.rows[0]));
  scroll(loaded, nodes, 3 * ROW_H + 10);
  assert.equal(nodes.nav.hasAttribute(MINE), true);
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`[${OWN}],[${STAR}],[${CHECK}]`).length, 0);
  assert.equal(loaded.dom.queryAll(`[${STARRED}],[${MINE}]`).length, 0);
  assert.deepEqual(kids(nodes.list), nodes.rows, "строки Claude на месте");
});
