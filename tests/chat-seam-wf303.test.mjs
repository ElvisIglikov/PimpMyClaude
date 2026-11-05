// #11201 (WF303) — бесшовная лента, раздел 13в (claude-patch/page/677-chat-seam.js): прошлый чат линии над верхом
// текущего. Чистые функции (ходы, Markdown, шаг колеса) — через люк; окно — стаб DOM со своими часами, лентой,
// узлом React над ней (olderHistoryAbove) и LocalSessions.getTranscriptTail/Page. Строки хвоста — форма JSONL
// Claude Code (tests/fixtures/seam-wf303/tail.json), текст выдуман.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { loadInject, plain } from "./load.mjs";

const TAIL = JSON.parse(fs.readFileSync(new URL("./fixtures/seam-wf303/tail.json", import.meta.url), "utf8"));
const DIR = "/work/line";
const FIRST = "local_10000000-0000-4000-8000-000000000001";
const OLDEST = "local_20000000-0000-4000-8000-000000000002";
const OLDER = "local_30000000-0000-4000-8000-000000000003";
const PREV = "local_40000000-0000-4000-8000-000000000004";
const CUR = "local_50000000-0000-4000-8000-000000000005";
const T0 = Date.parse("2026-10-15T09:00:00Z");
const H = 3600e3;
const LIST = [
  { sessionId: FIRST, cwd: DIR, originCwd: DIR, createdAt: T0, title: "Самый первый" },
  { sessionId: OLDEST, cwd: DIR, originCwd: DIR, createdAt: T0 + 10 * H, title: "Третий сверху" },
  { sessionId: OLDER, cwd: DIR, originCwd: DIR, createdAt: T0 + 20 * H, title: "Позапрошлый" },
  { sessionId: PREV, cwd: DIR, originCwd: DIR, createdAt: T0 + 30 * H, title: "Прошлый чат" },
  { sessionId: CUR, cwd: DIR, originCwd: DIR, createdAt: T0 + 40 * H, title: "Этот чат" },
];
// Ходы «вопрос — ответ» в форме хвоста: n штук, uuid с приставкой.
const gen = (p, n) => {
  const rows = [];
  for (let i = 0; i < n; i += 1) {
    const at = new Date(T0 + i * 60e3).toISOString();
    rows.push({ type: "user", uuid: `${p}-u${i}`, parentUuid: null, timestamp: at, isMeta: false, isSidechain: false, message: { role: "user", content: `вопрос ${p}${i}` } });
    rows.push({ type: "assistant", uuid: `${p}-a${i}`, parentUuid: `${p}-u${i}`, timestamp: at, isMeta: false, isSidechain: false, message: { role: "assistant", id: `m-${p}${i}`, content: [{ type: "text", text: `ответ ${p}${i}` }], stop_reason: "end_turn" } });
  }
  return rows;
};
const TAILS = {
  [PREV]: { messages: TAIL, hasMore: true },
  [OLDER]: { messages: gen("o", 3), hasMore: false },
  [OLDEST]: { messages: gen("x", 2), hasMore: false },
};
const PAGES = { [`${PREV}|s-01`]: { messages: gen("p", 4), hasMore: false, found: true } };
const flush = () => new Promise(resolve => setImmediate(resolve));
const TURN_PX = 300;
const STRIP_PX = 60;

// Окно Claude: строка заголовка, лента (scrollTop с зажимом), поле ввода внизу накрывает 20 px ленты.
// tails/pages — ответы API по id чата; short — короткий чат (лента у верха и у низа разом).
const stand = ({ chat = CUR, list = LIST, host: withHost = true, api = true, tails = TAILS, pages = PAGES, short = false } = {}) => {
  const clock = { t: 1_000_000, q: new Map(), seq: 1 };
  const nav = [];
  const calls = [];
  const wheelOn = new Set();
  let scrollTop = 1200;
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${chat}`, title: "Line",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    geometry: { viewport: { width: 1200, height: 800 } },
    html: dom => {
      const win = dom.window;
      win.performance.now = () => clock.t;
      const put = (fn, ms, every) => { const id = clock.seq++; clock.q.set(id, { fn, at: clock.t + Math.max(0, Number(ms) || 0), every }); return id; };
      win.setTimeout = (fn, ms) => put(fn, ms, 0);
      win.setInterval = (fn, ms) => put(fn, ms, Math.max(1, Number(ms) || 1));
      win.requestAnimationFrame = fn => put(() => fn(clock.t), 16, 0);
      win.clearTimeout = win.clearInterval = win.cancelAnimationFrame = id => { clock.q.delete(id); };
      const body = dom.document.body;
      const feedRect = { left: 0, top: 40, width: 1000, height: 560 };
      const panel = body.add("div", { class: "epitaxy-chat-panel", rect: { left: 0, top: 0, width: 1000, height: 800 } });
      panel.add("div", { class: "epitaxy-titlebar", rect: { left: 0, top: 0, width: 1000, height: 40 } });
      const feed = panel.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: feedRect, computed: { overflowY: "auto" } });
      const column = feed.add("div", { class: "epitaxy-transcript-column", rect: { left: 100, top: 40, width: 760, height: 560 } });
      // Переменные CSS Claude — на строках ленты (вне их не определены): шов переносит их на свой корень.
      const user = column.add("div", { attrs: { "data-cds": "UserMessage" }, computed: { "--cds-message-bubble-radius": "14px", "--cds-message-bubble-pad-x": "18px", "--cds-message-bubble-pad-y": "10px", "--cds-message-bubble-measure": "85%" } });
      const bubble = user.add("div", { class: "bubble-live group/message-row" });
      bubble.style.maxWidth = "479px";
      bubble.add("p", { text: "вопрос этого чата" });
      const row = column.add("div", { attrs: { "data-testid": "transcript-row" }, rect: { ...feedRect, height: 200 } });
      // Строка ответа — уже колонки: у обёртки колонки свои отступы 20/36 px.
      const message = row.add("div", { attrs: { "data-cds": "AssistantMessage" }, rect: { left: 120, top: 40, width: 704, height: 200 }, computed: { "--cds-assistant-message-text-inset": "4px", "--cds-assistant-message-text-stop": "50px" } });
      message.add("div", { class: "prose prose-live font-claude-response-body", attrs: { "data-cds": "Prose", "data-prose-font": "serif" }, computed: {} })
        .add("p").add("strong", { text: "строка ответа", computed: { "font-weight": "501" } });
      Object.assign(feed, { clientHeight: feedRect.height, scrollHeight: short ? feedRect.height : 3000 });
      Object.defineProperty(feed, "scrollTop", {
        get: () => scrollTop,
        set: value => { scrollTop = Math.max(0, Math.min(feed.scrollHeight - feed.clientHeight, Number(value) || 0)); },
      });
      // Шпион: блокирующий слушатель колеса на ленте — только пока шов взведён.
      const add = feed.addEventListener.bind(feed);
      const remove = feed.removeEventListener.bind(feed);
      feed.addEventListener = (type, fn, options) => { if (type === "wheel" && options?.passive === false) wheelOn.add(fn); add(type, fn, options); };
      feed.removeEventListener = (type, fn, options) => { if (type === "wheel") wheelOn.delete(fn); remove(type, fn, options); };
      const prompt = panel.add("div", { class: "epitaxy-prompt", rect: { left: 0, top: 580, width: 1000, height: 120 } });
      const host = { olderHistoryAbove: false, isPoolPending: false, isResponding: false };
      if (withHost) feed.__reactFiber$stand = { memoizedProps: {}, return: { memoizedProps: host, return: null } };
      const sessions = { getAll: async () => list.map(s => ({ ...s })) };
      if (api) {
        sessions.getTranscriptTail = async (id, limit) => { calls.push(["tail", id, limit]); return structuredClone(tails[id] ?? { messages: [], hasMore: false }); };
        sessions.getTranscriptPage = async (id, before, limit) => {
          calls.push(["page", id, before, limit]);
          return structuredClone(pages[`${id}|${before}`] ?? { messages: [], hasMore: false, found: false });
        };
      }
      win["claude.web"] = { LocalSessions: sessions };
      return { feed, row, host, prompt };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const { win } = loaded;
  loaded.dom.router();
  win.__TSR_ROUTER__ = { navigate: ({ to }) => { nav.push(to); win.history.pushState(null, "", to); loaded.parts.feed.scrollTop = 1e9; return Promise.resolve(); } };
  const advance = async ms => {
    const end = clock.t + ms;
    for (let guard = 0; guard < 200000; guard += 1) {
      let next = null;
      for (const entry of clock.q) if (entry[1].at <= end && (!next || entry[1].at < next[1].at)) next = entry;
      if (!next) break;
      const [id, item] = next;
      clock.t = Math.max(clock.t, item.at);
      if (item.every) item.at += item.every; else clock.q.delete(id);
      try { item.fn(); } catch {}
      await flush();
    }
    clock.t = end;
    await flush();
  };
  const feed = loaded.parts.feed;
  const seam = () => loaded.inner.seamState;
  const root = () => loaded.document.getElementById("myclaude-seam");
  // Блок у стаба без раскладки: высота — ходы и полосы, окно — видимая высота ленты; scrollTop с зажимом.
  let paneTop = 0;
  const pane = () => {
    const p = seam().pane;
    if (p && !p.__metrics) {
      p.__metrics = true;
      Object.defineProperty(p, "clientHeight", { get: () => seam().H, configurable: true });
      Object.defineProperty(p, "scrollHeight", {
        get: () => 44 + TURN_PX * p.querySelectorAll(".myclaude-seam-turn").length + STRIP_PX * p.querySelectorAll(".myclaude-seam-strip").length,
        configurable: true,
      });
      // Как у браузера в худшем случае (display:none): закрытому блоку scrollTop не встаёт.
      Object.defineProperty(p, "scrollTop", {
        get: () => paneTop,
        set: v => { if (root()?.getAttribute("data-phase") !== "idle") paneTop = Math.max(0, Math.min(p.scrollHeight - p.clientHeight, Number(v) || 0)); },
        configurable: true,
      });
    }
    return p;
  };
  const scrolled = (target = feed) => win.dispatchEvent({ type: "scroll", target });
  const to = top => { win.dispatchEvent({ type: "pointerdown", target: feed }); feed.scrollTop = top; scrolled(); };
  // Колесо как у браузера: захват окна (13а, 13б), потом цель (лента или блок); не погашено — едет то, что под ним.
  const wheelNow = (dy, where = "feed") => {
    pane();
    const inBlock = where === "seam";
    const target = inBlock ? seam().col : loaded.parts.row;
    const event = { __event: true, type: "wheel", deltaY: dy, deltaX: 0, deltaMode: 0, target, defaultPrevented: false };
    event.preventDefault = () => { event.defaultPrevented = true; };
    win.dispatchEvent(event);
    (inBlock ? root() : feed).dispatchEvent(event);
    if (!event.defaultPrevented) {
      if (inBlock && seam().phase === "inside") { const p = pane(); const b = p.scrollTop; p.scrollTop = b + dy; if (p.scrollTop !== b) scrolled(p); }
      else if (!inBlock && !feed.hasAttribute("data-myclaude-seam")) { const b = feed.scrollTop; feed.scrollTop = b + dy; if (feed.scrollTop !== b) scrolled(); }
    }
    return event;
  };
  const wheel = async (dy, n = 1, gap = 90, where = "feed") => {
    let last = null;
    for (let i = 0; i < n; i += 1) { last = wheelNow(dy, where); await advance(gap); }
    return last;
  };
  const st = () => plain(loaded.api.status().seam);
  const chainSt = () => plain(loaded.api.status().chain);
  const key = k => win.dispatchEvent({ type: "keydown", key: k, target: loaded.document.body });
  const click = target => loaded.document.dispatchEvent({ type: "click", target });
  return { loaded, win, clock, nav, calls, wheelOn, advance, feed, seam, root, pane, to, wheel, wheelNow, st, chainSt, key, click, scrolled, host: loaded.parts.host, prompt: loaded.parts.prompt };
};
// Открыть шов у верха ленты новым жестом: пауза колеса, потом n щелчков вверх.
const openSeam = async (s, n = 1) => {
  s.to(0);
  await s.advance(700);
  return s.wheel(-100, n, 90);
};
const feedVar = (s, name) => s.feed.style.getPropertyValue(name);

// ---- 1. Ходы ------------------------------------------------------------------------------------------------
test("ходы: вопрос человека, подходы по уведомлению и команде, ответ после последнего инструмента, служебное мимо", () => {
  const s = stand({ api: false });
  const turns = plain(s.loaded.inner.seamTurns(TAIL));
  assert.equal(turns.length, 3, "три вопроса человека — три хода");
  const [one, two, three] = turns;
  assert.deepEqual(one.q, { text: "Сверь остатки на складе за неделю и дай итог.", images: 0 });
  assert.equal(one.key, "u-01");
  assert.equal(one.at, Date.parse("2026-10-20T10:01:00.000Z"));
  assert.equal(one.aps.length, 2, "ответ и подход по уведомлению; [Image…] (isMeta), result и rate_limit — не границы");
  assert.match(one.aps[0].answer, /^## Итог/, "ответ — текст после последнего tool_use");
  assert.deepEqual(one.aps[0].work, ["Смотрю таблицу остатков."], "текст до инструмента — «Работа»; повтор строки по uuid — мимо");
  assert.equal(one.aps[0].tools, 1, "tool_use той же строки дважды — один");
  assert.equal(one.aps[0].done, true);
  assert.equal(one.aps[1].note, "Фоновая проверка закончилась", "уведомление — тихая метка из <summary>");
  assert.equal(one.aps[1].answer, "Фоновая проверка подтвердила итог.");
  assert.deepEqual(two.q, { text: "Посмотри вставку:\nстрока из вставки", images: 1 }, "напоминание вырезано, обёртка вставки снята, снимок посчитан");
  assert.equal(two.aps.length, 2, "команда — граница подхода");
  assert.equal(two.aps[0].answer, "Вижу вставку, проверяю.", "кончился на tool_use — ответ последний текст");
  assert.equal(two.aps[0].tools, 2);
  assert.equal(two.aps[0].done, false);
  assert.equal(two.aps[1].note, null);
  assert.ok(!JSON.stringify(turns).includes("субагент"), "ветка субагента (isSidechain) — мимо");
  assert.deepEqual(three.q.text, "А что с грушами?");
  assert.equal(three.aps[0].answer, "Груши: одна лишняя, пересчитаю завтра.", "плоская строка (content сверху) — тоже строка");
  // Края: мусор, ответ без вопроса, только служебное.
  const t = s.loaded.inner.seamTurns;
  assert.deepEqual(plain(t(null)), []);
  assert.deepEqual(plain(t([null, 7, { type: "user", isMeta: true, message: { content: "x" } }])), []);
  const orphan = plain(t([{ type: "assistant", uuid: "a", message: { id: "m", content: [{ type: "text", text: "хвост ответа" }] } }]));
  assert.equal(orphan.length, 1);
  assert.equal(orphan[0].q, null, "начало хвоста посреди хода — ход без вопроса");
  assert.equal(orphan[0].aps[0].answer, "хвост ответа");
  s.loaded.api.dispose();
});

// ---- 2. Markdown ---------------------------------------------------------------------------------------------
const tree = node => (node.nodeType === 3 ? String(node.nodeValue ?? "")
  : `<${node.tagName.toLowerCase()}${node.className ? `.${node.className.split(" ").join(".")}` : ""}${node.getAttribute("href") ? ` ${node.getAttribute("href")}` : ""}>${node.__text ?? ""}${[...node.childNodes].map(tree).join("")}</>`);
const md = (s, text) => tree(s.loaded.inner.seamMarkdown(text));

test("Markdown: заголовки, абзацы, списки, таблица, код, цитата, свёртка, ссылки — и ничего опасного", () => {
  const s = stand({ api: false });
  assert.equal(md(s, "# Раз ##\n\nтекст"), "<div.myclaude-seam-md><div.myclaude-seam-h.myclaude-seam-h1>Раз</><p>текст</></>", "заголовок — div своим классом, не h1");
  assert.equal(md(s, "**жир** *курс* __жир__ _курс_ ~~зачерк~~ `a*b*`"),
    "<div.myclaude-seam-md><p><strong>жир</> <em>курс</> <strong>жир</> <em>курс</> <s>зачерк</> <code>a*b*</></></>");
  assert.equal(md(s, "snake_case_name и a * b * c"), "<div.myclaude-seam-md><p>snake_case_name и a * b * c</></>", "«_» внутри слова и «*» в пробелах — текст");
  assert.equal(md(s, "строка\nдругая"), "<div.myclaude-seam-md><p>строка<br></>другая</></>");
  assert.equal(md(s, "- a\n  - b\n- c\n\n3. три\n4. четыре"),
    "<div.myclaude-seam-md><ul><li>a<ul><li>b</></></><li>c</></><ol><li>три</><li>четыре</></></>");
  assert.equal(md(s, "| a | b |\n|:--|--:|\n| 1 | `x|y` |"),
    "<div.myclaude-seam-md><div.myclaude-seam-scroll><table><thead><tr><th>a</><th>b</></></><tbody><tr><td>1</><td><code>x|y</></></></></></></>");
  assert.equal(md(s, "```js\n<b>x</b>\n**не жир**\n```"), "<div.myclaude-seam-md><pre.myclaude-seam-code><code><b>x</b>\n**не жир**</></></>", "код — как есть");
  assert.equal(md(s, "> цитата **жир**\n> > вложенная"), "<div.myclaude-seam-md><blockquote><p>цитата <strong>жир</></><blockquote><p>вложенная</></></></>");
  assert.equal(md(s, "до\n\n---\n\nпосле"), "<div.myclaude-seam-md><p>до</><hr></><p>после</></>");
  assert.equal(md(s, "<details>\n<summary>Свёртка **1**</summary>\n\nтело\n</details>\nдальше"),
    "<div.myclaude-seam-md><details.myclaude-seam-fold><summary.myclaude-seam-fold-head>Свёртка <strong>1</></><div.myclaude-seam-fold-body><p>тело</></></><p>дальше</></>");
  // Ссылки: только http/https/mailto, с target и rel; голый адрес — без хвостовой точки.
  const links = s.loaded.inner.seamMarkdown("[сайт](https://example.com/a?b=1) [почта](mailto:x@example.com) https://example.com/b. ").querySelectorAll("a");
  assert.deepEqual([...links].map(a => [a.getAttribute("href"), a.textContent, a.getAttribute("target"), a.getAttribute("rel")]), [
    ["https://example.com/a?b=1", "сайт", "_blank", "noopener noreferrer"],
    ["mailto:x@example.com", "почта", "_blank", "noopener noreferrer"],
    ["https://example.com/b", "https://example.com/b", "_blank", "noopener noreferrer"],
  ]);
  for (const bad of ["[x](javascript:alert(1))", "[x](data:text/html,1)", "[x](vbscript:1)", "[x](  JavaScript:alert(1))"]) {
    assert.equal(s.loaded.inner.seamMarkdown(bad).querySelectorAll("a").length, 0, `${bad}: не ссылка`);
    assert.equal(s.loaded.inner.seamMarkdown(bad).textContent, bad, `${bad}: текстом как есть`);
  }
  // HTML: белый список без атрибутов; остальное — текстом.
  const html = s.loaded.inner.seamMarkdown("<script>alert(1)</script> <img src=x onerror=1> <b onclick=1>x</b> <b>ok</b> <kbd>⌘</kbd>");
  assert.equal(html.querySelectorAll("script,img").length, 0);
  assert.equal(tree(html), "<div.myclaude-seam-md><p><script>alert(1)</script> <img src=x onerror=1> <b onclick=1>x</b> <strong>ok</> <kbd>⌘</></></>");
  // Абзац «Ждёт тебя» — div (522 ищет p), длинное — простым текстом.
  assert.equal(md(s, "Ждёт тебя: решение"), "<div.myclaude-seam-md><div.myclaude-seam-p>Ждёт тебя: решение</></>");
  const long = s.loaded.inner.seamMarkdown(`**${"x".repeat(41000)}**`);
  assert.equal(long.querySelector(".myclaude-seam-plain").textContent.length, 41004, "больше 40 КБ — простым текстом");
  // Незакрытое и вложенное без конца — не виснет и ничего не теряет.
  const odd = "**a *b `c [d](e ~~f <b>g";
  assert.equal(s.loaded.inner.seamMarkdown(odd).textContent, odd);
  s.loaded.api.dispose();
});

// ---- 3. Шаг колеса --------------------------------------------------------------------------------------------
test("шаг колеса: вход только новым жестом у верха, «внутри» на H, вниз — назад, остаток — ленте", () => {
  const s = stand({ api: false });
  const step = s.loaded.inner.seamWheelStep;
  const base = { phase: "idle", h: 0, H: 500, owned: false, lastAt: 0 };
  const e = (dy, t, more = {}) => ({ dy, t, atTop: true, ready: true, innerTop: 0, innerMax: 1000, ...more });
  let r = step(base, e(-100, 100));
  assert.equal(r.s.phase, "idle", "колесо помолчало меньше 250 мс — хвост жеста, не вход");
  assert.equal(r.prevent, false);
  r = step(base, e(-100, 300));
  assert.deepEqual([r.s.phase, r.s.h, r.s.owned, r.prevent, r.pin], ["reveal", 100, true, true, true], "новый жест у верха — шов");
  assert.equal(step(base, e(-100, 300, { atTop: false })).s.phase, "idle", "не у верха — нет");
  assert.equal(step(base, e(-100, 300, { ready: false })).s.phase, "idle", "Claude ещё догружает верх — нет");
  assert.equal(step(base, e(100, 300)).s.phase, "idle", "вниз — нет");
  r = step({ ...base, phase: "reveal", h: 450, owned: true, lastAt: 300 }, e(-100, 390));
  assert.deepEqual([r.s.phase, r.s.h, r.innerBy, r.pin], ["inside", 500, -50, true], "дошли до H — «внутри», остаток — блоку");
  r = step({ ...base, phase: "reveal", h: 60, owned: true, lastAt: 300 }, e(100, 390));
  assert.deepEqual([r.s.phase, r.s.h, r.feedBy, r.prevent], ["idle", 0, 40, true], "вниз ниже нуля — закрыт, остаток ленте");
  r = step({ ...base, owned: true, lastAt: 300 }, e(80, 390));
  assert.deepEqual([r.prevent, r.feedBy], [true, 80], "погашенный жест — наш до конца: ленту крутим сами");
  r = step({ ...base, owned: true, lastAt: 300 }, e(80, 500));
  assert.deepEqual([r.prevent, r.s.owned], [false, false], "пауза 120 мс — жест кончился");
  r = step({ ...base, phase: "inside", h: 500, lastAt: 0 }, e(50, 900, { innerTop: 300, innerMax: 1000 }));
  assert.deepEqual([r.prevent, r.s.phase], [false, "inside"], "внутри чужой жест — блок крутится сам");
  r = step({ ...base, phase: "inside", h: 500, lastAt: 0 }, e(50, 900, { innerTop: 1000, innerMax: 1000 }));
  assert.deepEqual([r.prevent, r.s.phase, r.s.h], [true, "reveal", 450], "у низа блока вниз — шов съезжает");
  r = step({ ...base, phase: "inside", h: 500, owned: true, lastAt: 850 }, e(120, 900, { innerTop: 900, innerMax: 1000 }));
  assert.deepEqual([r.s.phase, r.s.h, r.innerBy], ["reveal", 480, 100], "свой жест через низ блока: 100 — блоку, 20 — шву");
  assert.equal(step({ ...base, H: 0 }, e(-100, 300)).s.phase, "idle", "нет высоты — нет шва");
  s.loaded.api.dispose();
});

// ---- 4. Окно: заранее, уступка 13б, взвод, сдвиг ---------------------------------------------------------------------
test("окно: хвост заранее, 13б уступает верх, взвод у верха, сдвиг трансформом и обрезкой, жест до H", async () => {
  const s = stand();
  await s.advance(400);
  let st = s.st();
  assert.equal(st.on, true, "шов годен: есть прошлый, API и узел React над лентой");
  assert.equal(st.prev, PREV);
  assert.equal(st.turns, 3, "хвост прошлого взят заранее");
  assert.deepEqual(s.calls, [["tail", PREV, 40]]);
  assert.equal(s.wheelOn.size, 0, "середина ленты — блокирующего слушателя нет");
  assert.equal(s.root(), null, "и узлов — нет");
  s.to(0);
  await s.advance(700);
  assert.equal(s.chainSt().shown.up, false, "у верха плашки «↑ Предыдущий чат» 13б нет");
  assert.equal(s.chainSt().gap, "", "и зазора нет");
  assert.equal(s.wheelOn.size, 1, "у верха — взведён");
  assert.ok(s.root(), "блок собран заранее");
  assert.equal(s.root().getAttribute("data-phase"), "idle");
  assert.equal(s.root().parentNode, s.feed.parentNode, "сосед скроллера");
  // Инерция, донёсшая до верха, шов не открывает.
  s.to(300);
  await s.advance(400);
  await s.wheel(-100, 5, 60);
  assert.equal(s.feed.scrollTop, 0);
  assert.equal(s.st().phase, "idle", "хвост жеста — не открывает");
  // Новый жест — открывает.
  await s.advance(300);
  const ev = s.wheelNow(-100);
  assert.equal(ev.defaultPrevented, true, "колесо погашено — лента не дёргается");
  st = s.st();
  assert.deepEqual([st.phase, st.h, st.H], ["reveal", 100, 540], "H — от строки заголовка до верха поля");
  assert.ok(s.feed.hasAttribute("data-myclaude-seam"), "лента сдвинута своим атрибутом");
  assert.equal(feedVar(s, "--myclaude-seam-h"), "100px");
  assert.equal(feedVar(s, "--myclaude-seam-ct"), "0px");
  assert.equal(feedVar(s, "--myclaude-seam-cb"), "120px", "низ обрезан по полю ввода (20) + сдвиг");
  assert.equal(s.root().style.top, "40px");
  assert.equal(s.root().style.height, "540px");
  assert.equal(s.seam().col.style.marginLeft, "120px", "колонка — краями строки сообщения, не обёртки колонки");
  assert.equal(s.seam().col.style.width, "704px");
  // Переменные строки ленты — на корне шва: пузырь и отступы абзацев как у живых.
  const rootVar = name => s.root().style.getPropertyValue(name);
  assert.deepEqual(["--cds-message-bubble-radius", "--cds-message-bubble-pad-x", "--cds-message-bubble-pad-y", "--cds-message-bubble-measure", "--cds-assistant-message-text-inset", "--cds-assistant-message-text-stop", "--myclaude-seam-strong-w"].map(rootVar),
    ["14px", "18px", "10px", "479px", "4px", "50px", "501"]);
  assert.equal(s.root().getAttribute("data-phase"), "reveal");
  // Тот же жест — до H: «внутри»; 13б не уводит в прошлый чат.
  await s.advance(90);
  await s.wheel(-100, 5, 90);
  st = s.st();
  assert.deepEqual([st.phase, st.h], ["inside", 540]);
  assert.deepEqual(s.nav, [], "13б не перешёл — верх у шва");
  assert.equal(s.chainSt().shown.up, false);
  // Колесо вниз у низа блока — шов съезжает, до конца — закрыт, остаток — ленте.
  s.pane().scrollTop = 1e9;
  await s.advance(400);
  await s.wheel(200, 1, 90, "seam");
  assert.deepEqual([s.st().phase, s.st().h], ["reveal", 340], "у низа блока вниз — шов съезжает");
  await s.wheel(200, 2, 90, "seam");
  st = s.st();
  assert.equal(st.phase, "idle");
  assert.ok(!s.feed.hasAttribute("data-myclaude-seam"), "сдвиг снят");
  assert.equal(feedVar(s, "--myclaude-seam-h"), "");
  assert.equal(s.root().getAttribute("data-phase"), "idle");
  s.loaded.api.dispose();
});

// ---- 5. Подгрузка, линия, потолок ------------------------------------------------------------------------------
test("подгрузка: порция сверху без прыжка, потом чат выше по линии с полосой, потолок 3 чата — «Открыть «…»»", async () => {
  const s = stand();
  await s.advance(400);
  // Шов приоткрыт, верх блока ближе 1,5 экрана — порция того же чата; пока приоткрыт, блок прижат к низу.
  await openSeam(s, 1);
  await s.advance(50);
  assert.deepEqual(s.calls.at(-1), ["page", PREV, "s-01", 60], "порция до первой строки хвоста");
  let st = s.st();
  assert.equal(st.turns, 7, "3 хода хвоста + 4 порции");
  assert.equal(st.chats, 1);
  assert.equal(s.pane().scrollTop, s.pane().scrollHeight - 540, "приоткрыт — у низа блока");
  await s.wheel(-100, 5, 90);
  assert.equal(s.st().phase, "inside");
  const firstTurn = s.seam().segs[0].nodes[4];
  // Наверх блока — чат выше по линии: его хвост и полоса «↑ Предыдущий чат» под ним; место чтения не прыгает.
  s.pane().scrollTop = 100;
  const h0 = s.pane().scrollHeight;
  s.scrolled(s.pane());
  await s.advance(50);
  assert.deepEqual(s.calls.at(-1), ["tail", OLDER, 40]);
  assert.equal(s.pane().scrollHeight - h0, 3 * TURN_PX + STRIP_PX);
  assert.equal(s.pane().scrollTop, 100 + 3 * TURN_PX + STRIP_PX, "scrollTop + прирост высоты");
  st = s.st();
  assert.equal(st.chats, 2);
  assert.equal(st.turns, 10);
  assert.equal(s.seam().segs[1].nodes[4], firstTurn, "узлы прошлого чата не пересобраны");
  const go = [...s.root().querySelectorAll("[data-myclaude-seam-go]")].map(b => [b.getAttribute("data-myclaude-seam-go"), b.textContent]);
  assert.equal(go.length, 2, "полоса под каждым чатом");
  assert.equal(go[0][0], OLDER);
  assert.match(go[0][1], /^↑ Предыдущий чат«Позапрошлый»\d+ окт, \d\d:00$/);
  assert.equal(go[1][0], PREV);
  s.pane().scrollTop = 0;
  s.scrolled(s.pane());
  await s.advance(50);
  st = s.st();
  assert.equal(st.chats, 3);
  assert.equal(st.ceiling, true, "три чата — потолок");
  const pill = s.seam().top.querySelector("[data-myclaude-seam-go]");
  assert.equal(pill.getAttribute("data-myclaude-seam-go"), FIRST, "дальше — открыть следующий выше");
  assert.equal(pill.textContent, "Открыть «Самый первый»");
  const loads = st.loads;
  s.pane().scrollTop = 0;
  s.scrolled(s.pane());
  await s.advance(300);
  assert.equal(s.st().loads, loads, "у потолка больше не грузим");
  // Нажатие на полосу — переход в тот чат, на его низ; шов закрыт.
  s.click(s.root().querySelector(`[data-myclaude-seam-go="${OLDER}"] > span`));
  await s.advance(2000);
  assert.equal(s.nav.at(-1), `/epitaxy/${OLDER}`);
  assert.equal(s.st().phase, "idle");
  s.loaded.api.dispose();
});

test("начало линии: у первого чата блок кончается «Начало линии»; ошибка API — в status, повтор позже", async () => {
  const list = LIST.filter(x => x.sessionId === OLDER || x.sessionId === PREV || x.sessionId === CUR);
  const s = stand({ list });
  await s.advance(400);
  await openSeam(s, 6);
  await s.advance(50);
  s.pane().scrollTop = 0;
  s.scrolled(s.pane());
  await s.advance(50);
  assert.equal(s.st().chats, 2);
  s.pane().scrollTop = 0;
  s.scrolled(s.pane());
  await s.advance(50);
  assert.equal(s.st().start, true);
  assert.equal(s.seam().top.textContent, "Начало линии");
  s.loaded.api.dispose();
  // Хвост не дался — шва нет, ошибка видна, повтор через 5 с.
  const t = stand();
  let fails = 1;
  const api = t.win["claude.web"].LocalSessions;
  const real = api.getTranscriptTail;
  api.getTranscriptTail = async (...a) => { if (fails-- > 0) throw new Error("boom"); return real(...a); };
  await t.advance(400);
  assert.equal(t.st().on, false);
  assert.equal(t.st().error, "boom");
  await t.advance(5200);
  assert.equal(t.st().on, true);
  assert.equal(t.st().error, null);
  t.loaded.api.dispose();
});

// ---- 6. Закрыть: чужая прокрутка, клавиши, «↓ К этому чату», снятие --------------------------------------------------
test("закрытие: лента сдвинулась не нами, End, «↓ К этому чату»; ушли вниз на 3 экрана — подгруженное снято", async () => {
  const s = stand();
  await s.advance(400);
  await openSeam(s, 2);
  assert.equal(s.st().phase, "reveal");
  // Отправил сообщение — Claude увёл ленту вниз.
  await s.advance(300);
  s.feed.scrollTop = 900;
  s.scrolled();
  assert.equal(s.st().phase, "idle", "чужая прокрутка — шов закрыт");
  assert.ok(!s.feed.hasAttribute("data-myclaude-seam"));
  // Внутри: PageUp — блоку, End — закрыть.
  await openSeam(s, 7);
  assert.equal(s.st().phase, "inside");
  await s.advance(50);
  s.pane().scrollTop = 1500;
  s.key("PageUp");
  assert.equal(s.pane().scrollTop, 1500 - 0.9 * 540);
  s.key("End");
  assert.equal(s.st().phase, "idle");
  // «↓ К этому чату» — плавно до конца.
  await openSeam(s, 7);
  const home = s.root().querySelector("[data-myclaude-seam-home]");
  assert.equal(home.textContent, "↓ К этому чату");
  s.click(home);
  await s.advance(100);
  assert.equal(s.st().phase, "reveal", "едет");
  assert.ok(s.st().h > 0 && s.st().h < 540);
  await s.advance(300);
  assert.equal(s.st().phase, "idle");
  assert.equal(s.st().h, 0);
  // Ушли вниз — DOM снят, хвост — в памяти; у верха собран снова.
  assert.ok(s.st().nodes > 3);
  s.to(2000);
  await s.advance(200);
  let st = s.st();
  assert.equal(st.nodes, 0);
  assert.equal(st.chats, 0);
  assert.equal(st.turns, 3, "хвост прошлого — в кэше");
  assert.equal(s.root(), null);
  assert.equal(s.wheelOn.size, 0, "далеко от верха — не взведён");
  const calls = s.calls.length;
  s.to(0);
  await s.advance(400);
  st = s.st();
  assert.equal(st.nodes, 3, "собран из кэша");
  assert.equal(s.calls.length, calls, "без нового запроса");
  // Хвост старше 30 с — на входе взят заново; те же строки — узлы не пересобраны.
  const node = s.seam().segs[0].nodes[0];
  await s.advance(31000);
  await openSeam(s, 1);
  await s.advance(50);
  assert.deepEqual(s.calls.slice(calls), [["tail", PREV, 40], ["page", PREV, "s-01", 60]]);
  assert.equal(s.seam().segs[0].nodes.at(-3), node);
  s.loaded.api.dispose();
});

// ---- 7. Без узла React — работает 13б; автопереход ждёт шва ---------------------------------------------------------
test("без узла React над лентой шва нет — у верха плашка 13б; автопереход, пока шов открыт, — blocked «seam»", async () => {
  const s = stand({ host: false });
  await s.advance(400);
  s.to(0);
  await s.advance(1500);
  assert.equal(s.st().on, false, "край «догружено ли всё» не знаем — шва нет");
  assert.equal(s.chainSt().shown.up, true, "плашка «↑ Предыдущий чат» 13б");
  assert.equal(s.wheelOn.size, 0);
  s.loaded.api.dispose();
  const t = stand();
  await t.advance(400);
  await openSeam(t, 2);
  const f = t.loaded.inner.chainState.follow;
  f.pending = { from: CUR, to: PREV, title: "", since: Date.now(), t: t.clock.t - 10000 };
  await t.advance(1200);
  assert.equal(f.blocked, "seam");
  assert.ok(f.pending, "ждёт");
  assert.deepEqual(t.nav, []);
  t.loaded.api.dispose();
});

// ---- 8. Разделы ленты шов не видят, вид — классы живых узлов, dispose ------------------------------------------------
test("наши узлы: без h1–h6, data-cds, data-testid, role и классов строк; разделы ленты их не метят; dispose всё снимает", async () => {
  const s = stand();
  await s.advance(400);
  await openSeam(s, 7);
  await s.advance(3000);
  const root = s.root();
  const all = [root, ...root.querySelectorAll("*")];
  const own = new Set(["data-myclaude-seam-go", "data-myclaude-seam-home"]);
  for (const node of all) {
    assert.ok(!/^H[1-6]$/.test(node.tagName), `${node.tagName}: заголовок — div`);
    for (const name of node.getAttributeNames()) {
      assert.ok(!["data-cds", "data-testid", "role", "aria-label"].includes(name), `${name} на ${node.tagName}`);
      assert.ok(!name.startsWith("data-myclaude-") || own.has(name), `чужая метка ${name} на ${node.tagName}.${node.className}`);
    }
    for (const cls of String(node.className ?? "").split(/\s+/)) {
      assert.ok(!["group/message-row", "epitaxy-user-turn", "epitaxy-transcript-width"].includes(cls) && !cls.startsWith("font-claude-response"), cls);
    }
  }
  assert.ok(root.querySelector(".myclaude-seam-p"), "«Ждёт тебя» — div, не p");
  assert.ok(root.classList.contains("epitaxy-transcript-typography"));
  const prose = root.querySelector(".myclaude-seam-a > div");
  assert.equal(prose.className, "prose prose-live", "классы живого ответа без font-claude-response*");
  assert.equal(prose.getAttribute("data-prose-font"), "serif");
  assert.equal(root.querySelector(".myclaude-seam-q > div:not(.myclaude-seam-when)").className, "bubble-live", "пузырь — классы живого, без group/message-row");
  const work = [...root.querySelectorAll("details.myclaude-seam-work > summary")].map(x => x.textContent);
  assert.deepEqual(work, ["Работа · 1 действие", "Работа · 2 действия"]);
  assert.equal(root.querySelector(".myclaude-seam-note").textContent, "⚙ Фоновая проверка закончилась");
  assert.equal(root.querySelector(".myclaude-seam-pic").textContent, "🖼 снимок");
  // dispose: блок, сдвиг, слушатели, уступка 13б — всё снято.
  s.loaded.api.dispose();
  assert.equal(s.root(), null);
  assert.ok(!s.feed.hasAttribute("data-myclaude-seam"));
  assert.equal(feedVar(s, "--myclaude-seam-h"), "");
  assert.equal(s.wheelOn.size, 0);
  assert.equal(s.loaded.inner.chainState.seamTop, "");
});

// ---- 9. Починки по проверке и стенду (WF303) -------------------------------------------------------------------------
test("ответ API не массив — ошибка в status, повтор не раньше 5 с, без необработанных отказов", async () => {
  let unhandled = 0;
  const onUnhandled = () => { unhandled += 1; };
  process.on("unhandledRejection", onUnhandled);
  try {
    const s = stand({ tails: { [PREV]: { found: false } } });
    const tails = () => s.calls.filter(c => c[0] === "tail").length;
    await s.advance(400);
    assert.equal(s.st().error, "not-array");
    assert.equal(s.st().on, false, "хвоста нет — шва нет");
    await s.advance(4000);
    assert.equal(tails(), 1, "раз в 150 мс не долбим");
    await s.advance(1500);
    assert.equal(tails(), 2, "повтор через 5 с");
    s.loaded.api.dispose();
    await new Promise(resolve => setTimeout(resolve, 20));
  } finally { process.off("unhandledRejection", onUnhandled); }
  assert.equal(unhandled, 0);
});

test("шов открывается у низа блока: сперва показ, потом прижим — и после смены высоты при закрытом шве", async () => {
  const s = stand({ pages: {} });
  await s.advance(400);
  s.to(0);
  await s.advance(700);
  const p = s.pane();
  assert.equal(p.scrollTop, 0);
  s.wheelNow(-100);
  assert.equal(s.st().phase, "reveal");
  assert.equal(p.scrollTop, p.scrollHeight - 540, "приоткрыт — конец прошлого чата у полосы");
  await s.advance(90);
  await s.wheel(100, 2, 90);
  assert.equal(s.st().phase, "idle");
  // Закрыт — поле ввода выросло (видимая лента ниже на 140): новый жест — снова у низа своей новой высоты.
  s.prompt.rect = { ...s.prompt.rect, top: 440, height: 260 };
  const before = p.scrollTop;
  s.to(0);
  await s.advance(700);
  s.wheelNow(-100);
  assert.equal(s.st().H, 400);
  assert.notEqual(before, p.scrollHeight - 400);
  assert.equal(p.scrollTop, p.scrollHeight - 400);
  s.loaded.api.dispose();
});

test("короткий чат у верха и у низа: жест вниз из шва не тянет 13б в следующий чат; новый жест — тянет", async () => {
  const s = stand({ chat: PREV, short: true });
  await s.advance(400);
  s.to(0);
  await s.advance(1500);
  assert.equal(s.st().on, true);
  assert.equal(s.st().prev, OLDER);
  await s.wheel(-100, 2, 90);
  assert.equal(s.st().phase, "reveal");
  // Тот же жест вниз: шов съехал, остаток — ленте (ей некуда), 13б не копит натяжку.
  await s.wheel(100, 10, 40);
  assert.equal(s.st().phase, "idle");
  assert.equal(s.loaded.inner.chainState.pull, 0, "натяжки вниз нет");
  await s.advance(2000);
  assert.deepEqual(s.nav, []);
  // Новый жест после паузы — 13б как раньше.
  await s.wheel(100, 1, 40);
  assert.ok(s.loaded.inner.chainState.pull > 0, "13б тянет вниз");
  s.loaded.api.dispose();
});

test("Claude пишет ответ и прилипает к низу — шов не закрыт; после отправки (Enter в поле) — закрыт", async () => {
  const s = stand();
  const box = s.loaded.document.body.add("textarea");
  await s.advance(400);
  await openSeam(s, 2);
  await s.advance(1600);
  s.host.isResponding = true;
  s.feed.scrollTop = 300;
  s.scrolled();
  assert.equal(s.st().phase, "reveal", "прилипание к низу — не наш жест и не человек");
  // Набор ответа (буквы) — не действие с лентой.
  s.win.dispatchEvent({ type: "keydown", key: "a", target: box });
  s.feed.scrollTop = 500;
  s.scrolled();
  assert.equal(s.st().phase, "reveal");
  s.win.dispatchEvent({ type: "keydown", key: "Enter", shiftKey: false, target: box });
  s.feed.scrollTop = 900;
  s.scrolled();
  assert.equal(s.st().phase, "idle", "отправил — Claude увёл ленту: шов закрыт");
  s.loaded.api.dispose();
});

test("поле ввода выросло при открытом шве — H, корень и обрезка пересчитаны; ленты не осталось — шов закрыт", async () => {
  const s = stand();
  await s.advance(400);
  await openSeam(s, 2);
  assert.deepEqual([s.st().phase, s.st().H], ["reveal", 540]);
  s.prompt.rect = { ...s.prompt.rect, top: 480, height: 220 };
  await s.advance(200);
  assert.equal(s.st().H, 440);
  assert.equal(s.root().style.height, "440px");
  assert.equal(feedVar(s, "--myclaude-seam-cb"), `${120 + s.st().h}px`, "низ обрезан по новому верху поля");
  assert.equal(s.st().phase, "reveal");
  s.feed.rect = { ...s.feed.rect, height: 0 };
  await s.advance(200);
  assert.equal(s.st().phase, "idle");
  assert.ok(!s.feed.hasAttribute("data-myclaude-seam"), "у ленты не остался overflow:hidden");
  s.loaded.api.dispose();
});

test("короткий чат: закрыт и помолчал — подгруженное сверх хвоста снято, хвост собран снова из памяти", async () => {
  const s = stand();
  await s.advance(400);
  await openSeam(s, 7);
  await s.advance(50);
  s.pane().scrollTop = 0;
  s.scrolled(s.pane());
  await s.advance(50);
  assert.equal(s.st().chats, 2);
  assert.equal(s.st().turns, 10);
  s.key("End");
  assert.equal(s.st().phase, "idle");
  await s.advance(600);
  assert.equal(s.st().chats, 2, "сразу не снимаем");
  const calls = s.calls.length;
  await s.advance(1200);
  const st = s.st();
  assert.deepEqual([st.chats, st.turns, st.nodes], [1, 3, 3], "остался хвост прошлого чата");
  assert.equal(s.feed.scrollTop, 0, "лента у верха — шов снова готов");
  assert.equal(s.wheelOn.size, 1);
  assert.equal(s.calls.length, calls, "без новых запросов");
  s.loaded.api.dispose();
});

test("порция из виденных строк — к чату выше без повторов; потолок и по строкам", async () => {
  const s = stand({ pages: { [`${PREV}|s-01`]: { messages: TAIL.slice(0, 6), hasMore: true, found: true } } });
  await s.advance(400);
  await openSeam(s, 1);
  await s.advance(400);
  const pages = s.calls.filter(c => c[0] === "page");
  assert.equal(pages.length, 1, "одна порция: новых строк нет — у этого чата больше нечего брать");
  assert.deepEqual(s.calls.at(-1), ["tail", OLDER, 40]);
  s.loaded.api.dispose();
  // Агентская сессия: один вопрос и тысячи строк инструментов — ходов мало, строк — потолок.
  const work = [{ type: "user", uuid: "w-q", timestamp: new Date(T0).toISOString(), message: { role: "user", content: "долгая работа" } }];
  for (let i = 0; i < 3000; i += 1) work.push({ type: "assistant", uuid: `w-${i}`, timestamp: new Date(T0).toISOString(), message: { role: "assistant", id: `m-w${i}`, content: [{ type: "tool_use", id: `t${i}`, name: "Bash" }] } });
  const t = stand({ pages: { [`${PREV}|s-01`]: { messages: work, hasMore: true, found: true } } });
  await t.advance(400);
  await openSeam(t, 1);
  await t.advance(1000);
  const st = t.st();
  assert.equal(st.ceiling, true, "потолок по строкам");
  assert.ok(st.turns < 150, "ходов мало");
  assert.equal(t.calls.filter(c => c[0] === "page").length, 1, "дальше не грузим");
  t.loaded.api.dispose();
});
