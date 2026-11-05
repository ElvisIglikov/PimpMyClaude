// #11201 (WF301) — сквозная история чатов, раздел 13б (claude-patch/page/676-chat-chain.js): перенос блока Windows
// #10959. Сценарии стенда Windows (PimpWinTray tools/stand/chain.mjs, 26 проверок) — здесь на настоящем inject.js в
// стабе DOM, плюс маковские: Esc только слушаем, докрутка к началу не перебивается, «Следующий чат» выше
// «непрочитанных», попап без швов, обход 12е, инерция тачпада потоком мелких дельт, фишка в строке заголовка и под
// ней в колонке 354, широкий вид, dispose посреди докрутки.
// Часы — свои: performance.now, таймеры, интервалы и кадры страницы идут по виртуальному времени (advance).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const RICK = "/Users/dev/Projects/Rick";
const A = "local_7f03137a-8743-424d-b1f6-19850b4b0752";
const B = "local_2b6130c4-71f7-4972-a9d9-5271168649b8";
const C = "local_4a800974-9242-4007-93de-d030d7c580fc";
const D = "local_51b42b75-4537-44ec-9afe-b1349862fcf5";
const S = "local_f899c0b3-0000-4000-8000-000000000001";
const W = "local_aaaa0000-0000-4000-8000-000000000002";
const F = "local_bbbb0000-0000-4000-8000-000000000003";
const V = "local_cccc0000-0000-4000-8000-000000000004";
const P = "local_eeee0000-0000-4000-8000-000000000006";
const L = "local_ffff0000-0000-4000-8000-000000000007";
const T0 = Date.parse("2026-10-15T16:43:00Z");
const H = 3600e3;
const LIST = [
  { sessionId: A, cwd: RICK, originCwd: RICK, createdAt: T0, title: "Первый чат Рика" },
  // Время строкой ISO — тоже время.
  { sessionId: B, cwd: RICK, originCwd: RICK, createdAt: new Date(T0 + 50 * H).toISOString(), title: "Сайт: панель, сброс" },
  { sessionId: C, cwd: RICK, originCwd: RICK, createdAt: String(T0 + 120 * H), title: "Система отзывов" },
  { sessionId: D, cwd: `${RICK}/`, originCwd: RICK, createdAt: T0 + 240 * H, title: "Монитор и сайт 25.10" },
  { sessionId: S, cwd: RICK, originCwd: RICK, createdAt: T0 + 241 * H, title: "Боковой: история чатов", lineage: { kind: "side_session", sessionId: D } },
  { sessionId: W, cwd: `${RICK}/.claude/worktrees/wf1`, originCwd: RICK, createdAt: T0 + 200 * H, title: "Копия worktree" },
  { sessionId: F, cwd: RICK, originCwd: RICK, createdAt: T0 + 230 * H, title: "Форк", forkedFromSessionId: C },
  { sessionId: P, cwd: RICK, originCwd: RICK, createdAt: T0 + 242 * H, title: "👾 Главный чат", lineage: { kind: "side_session", sessionId: D }, isStarred: true },
  { sessionId: V, cwd: "/Users/dev/Projects/VkusnoffKz", originCwd: "/Users/dev/Projects/VkusnoffKz", createdAt: T0 + 100 * H, title: "Сайт" },
  // Мак: регистр в пути учитывается — это другая папка.
  { sessionId: L, cwd: RICK.toLowerCase(), originCwd: RICK.toLowerCase(), createdAt: T0 + 243 * H, title: "Строчными" },
  { sessionId: "local_dddd0000-0000-4000-8000-000000000005", cwd: RICK, createdAt: T0 + 10 * H, title: "Черновик", neverStarted: true },
];

const flush = () => new Promise(resolve => setImmediate(resolve));

// Окно Claude: панель чата со строкой заголовка (название, меню, кнопка справа), лента и поле ввода.
const stand = ({ chat = B, href = null, feedW = 1000, wide = false, list = LIST } = {}) => {
  const clock = { t: 1_000_000, q: new Map(), seq: 1 };
  const nav = [];
  let scrollTop = 1200;
  const loaded = loadInject({
    href: href ?? `https://claude.ai/epitaxy/${chat}`, title: "Rick",
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
      const feedRect = wide ? { left: 8, top: 0, width: 471, height: 800 } : { left: 0, top: 40, width: feedW, height: 520 };
      const barRect = wide ? { left: 483, top: 9, width: 328, height: 45 } : { left: 0, top: 0, width: feedW, height: 40 };
      const panel = body.add("div", { class: "epitaxy-chat-panel", rect: { left: 0, top: 0, width: wide ? 811 : feedW, height: 800 } });
      const titlebar = panel.add("div", { class: "epitaxy-titlebar", rect: barRect });
      titlebar.add("button", { attrs: { "data-pane-title": "" }, rect: { left: barRect.left + 16, top: barRect.top + 6, width: 140, height: 28 } });
      titlebar.add("button", { attrs: { "aria-label": "More options for Rick" }, rect: { left: barRect.left + 160, top: barRect.top + 6, width: 28, height: 28 } });
      titlebar.add("button", { attrs: { "aria-label": "Share" }, rect: { left: barRect.left + barRect.width - 40, top: barRect.top + 6, width: 28, height: 28 } });
      const feed = panel.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: feedRect, computed: { overflowY: "auto" } });
      const column = feed.add("div", { class: "flex min-h-full flex-col", rect: feedRect });
      const row = column.add("div", { attrs: { "data-testid": "transcript-row" }, rect: { ...feedRect, height: 200 } });
      row.add("p", { text: "строка ответа" });
      // Прокрутка, как у браузера: в пределах [0, scrollHeight − clientHeight].
      Object.assign(feed, { clientHeight: feedRect.height, scrollHeight: 3000 });
      Object.defineProperty(feed, "scrollTop", {
        get: () => scrollTop,
        set: value => { scrollTop = Math.max(0, Math.min(feed.scrollHeight - feed.clientHeight, Number(value) || 0)); },
      });
      const prompt = panel.add("div", { class: "epitaxy-prompt", rect: { left: 0, top: 580, width: feedW, height: 120 } });
      const host = { olderHistoryAbove: false, isPoolPending: false, isResponding: false };
      feed.__reactFiber$stand = { memoizedProps: {}, return: { memoizedProps: host, return: null } };
      win["claude.web"] = { LocalSessions: { getAll: async () => list.map(s => ({ ...s })) } };
      return { panel, titlebar, feed, prompt, row, host };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const { win } = loaded;
  loaded.dom.router();
  // Роутер приложения (TanStack): пишет историю; новый чат Claude открывает с низа.
  const router = { navigate: ({ to }) => { nav.push(to); win.history.pushState(null, "", to); loaded.parts.feed.scrollTop = 1e9; return Promise.resolve(); } };
  win.__TSR_ROUTER__ = router;
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
  const scrolled = () => win.dispatchEvent({ type: "scroll", target: feed });
  // Прыжок — рукой по полосе прокрутки: нажатие в ленте, иначе раздел 13а держит «место чтения» и не пустит вниз.
  const to = top => { win.dispatchEvent({ type: "pointerdown", target: feed }); feed.scrollTop = top; scrolled(); };
  const toTop = () => to(0);
  const toBottom = () => to(1e9);
  // Колесо как у браузера: событие над лентой, и лента едет на dy, если есть куда.
  const wheel = async (dy, n = 1, gap = 90) => {
    for (let i = 0; i < n; i += 1) {
      win.dispatchEvent({ type: "wheel", deltaY: dy, deltaX: 0, deltaMode: 0, target: loaded.parts.row });
      const before = feed.scrollTop;
      feed.scrollTop = before + dy;
      if (feed.scrollTop !== before) scrolled();
      await advance(gap);
    }
  };
  const st = () => plain(loaded.api.status().chain);
  const node = k => loaded.dom.query(`#myclaude-chain > [data-k="${k}"]`);
  const click = k => loaded.document.dispatchEvent({ type: "click", target: node(k) });
  const key = k => win.dispatchEvent({ type: "keydown", key: k, target: loaded.document.body });
  return { loaded, win, clock, nav, router, advance, feed, host: loaded.parts.host, to, toTop, toBottom, wheel, st, node, click, key, scrolled };
};
const text = (s, k) => s.node(k)?.textContent ?? "";
const chat = id => `/epitaxy/${id}`;

// ---- 1. Цепочка: чистая функция -------------------------------------------------------------------------------
test("цепочка: линия папки по времени, закреплённый в линии, боковой/форк/worktree — к родителю, регистр и «/» в пути", () => {
  const s = stand();
  const c = s.loaded.inner.chainOf;
  const pick = l => l && { prev: l.prev?.id ?? null, next: l.next?.id ?? null, last: l.last?.id ?? null, side: l.side, i: l.index, n: l.total };
  const links = Object.fromEntries([A, B, C, D, S, W, F, V, P, L].map(id => [id, plain(pick(c(LIST, id, new Set())))]));
  assert.deepEqual(links[A], { prev: null, next: B, last: P, side: false, i: 1, n: 5 }, "A: первый — без предыдущего, следующий B");
  assert.deepEqual(links[B], { prev: A, next: C, last: P, side: false, i: 2, n: 5 }, "B: A ← B → C (время строкой ISO), последний — закреплённый P");
  assert.deepEqual(links[C], { prev: B, next: D, last: P, side: false, i: 3, n: 5 }, "C: время числом-строкой");
  assert.deepEqual(links[D], { prev: C, next: P, last: P, side: false, i: 4, n: 5 }, "D (папка с «/» на конце): дальше — закреплённый P, запущенный из D");
  assert.deepEqual(links[S], { prev: D, next: null, last: P, side: true, i: 0, n: 5 }, "боковой S → родитель D, последний P");
  assert.equal(links[W].side, true, "копия worktree — не в линии");
  assert.equal(links[W].prev, null);
  assert.equal(links[W].last, P);
  assert.equal(links[F].side, true, "форк F → источник C");
  assert.equal(links[F].prev, C);
  assert.deepEqual(links[P], { prev: D, next: null, last: null, side: false, i: 5, n: 5 }, "закреплённый P — последний в линии");
  assert.deepEqual(links[V], { prev: null, next: null, last: null, side: false, i: 1, n: 1 }, "другая папка — один в линии");
  assert.deepEqual(links[L], { prev: null, next: null, last: null, side: false, i: 1, n: 1 }, "путь другим регистром — другая папка (Мак)");
  assert.equal(c(LIST, "local_dddd0000-0000-4000-8000-000000000005"), null, "черновик — мимо");
  // Закреплённый хоть раз — в линии и откреплённым.
  const unpinned = LIST.map(x => (x.sessionId === P ? { ...x, isStarred: false } : x));
  assert.equal(c(unpinned, P, new Set()).side, true, "откреплённый без памяти — боковой");
  assert.equal(c(unpinned, P, new Set([P])).side, false, "откреплённый, но помнится — в линии");
  assert.equal(s.loaded.inner.chainAt({ createdAt: "мусор" }), NaN);
  assert.equal(s.loaded.inner.chainFolder(`${RICK}//`), RICK);
  s.loaded.api.dispose();
});

// ---- 2–12. Окно: швы, натяжка, переходы ----------------------------------------------------------------------
test("сценарий стенда Windows: швы, колесо, приход, инерция, «Назад», последний, боковой, догрузка, двойной инжект, «не открылся»", async () => {
  const s = stand({ chat: B });
  await s.advance(400);
  assert.ok(s.loaded.win.localStorage.getItem("myclaude-chain-pinned-v1").includes(P), "закреплённый запомнен");

  // 2. Середина ленты B: фишка видна, швов нет; у верха — плашка «Предыдущий чат» и зазор.
  s.to(1000);
  await s.advance(1700);
  let st = s.st();
  assert.deepEqual(st.shown, { up: false, down: false, last: true, latest: false }, "B: «В последний чат» видно, швов посреди ленты нет");
  assert.equal(text(s, "last"), "2 из 5 · В последний чат");
  s.toTop();
  await s.advance(700);
  st = s.st();
  assert.equal(st.shown.up, true, "B: у верха плашка «Предыдущий чат»");
  assert.match(st.gap, /^top\b/, "и зазор над первой строкой (в стабе фишка без ширины — под строкой, зазор и на неё)");
  assert.match(text(s, "up"), /^↑ Предыдущий чат«Первый чат Рика»1[56] окт, \d\d:43$/);

  // 3. Колесо вверх у края: натяжка → A, его низ; внизу — «Следующий чат».
  await s.wheel(-100, 4, 120);
  await s.advance(2000);
  st = s.st();
  assert.equal(s.nav.at(-1), chat(A), "колесо вверх → A");
  assert.equal(st.chat, A);
  assert.equal(st.last.ok, true);
  assert.equal(st.last.kind, "up");
  assert.equal(s.feed.scrollTop, s.feed.scrollHeight - s.feed.clientHeight, "A: приземлились в низ");
  assert.equal(st.shown.down, true, "A: внизу «Следующий чат»");
  assert.match(text(s, "down"), /^↓ Следующий чат«Сайт: панель, сброс»/);

  // 4. Верх первого чата — плашки нет.
  s.toTop();
  await s.advance(1500);
  assert.equal(s.st().shown.up, false, "A: у верха первого чата плашки нет");

  // 5. Инерция у низа A: колесо без паузы — натяжки нет; пауза — взвод; недотянул — спадает.
  s.toBottom();
  const before = s.nav.length;
  await s.wheel(60, 25, 60);
  st = s.st();
  assert.equal(s.nav.length, before, "инерция: перехода нет");
  assert.equal(st.pull, 0, "инерция: без паузы колеса натяжки нет");
  await s.advance(1000);
  await s.wheel(100, 2, 100);
  const half = s.st().pull;
  await s.advance(1500);
  assert.ok(half > 0, `натяжка была: ${half}`);
  assert.equal(s.st().pull, 0, "недотянул — натяжка спала");
  assert.equal(s.nav.length, before);

  // 6. Колесо вниз у края A → B, в начало.
  await s.wheel(100, 4, 120);
  await s.advance(2000);
  st = s.st();
  assert.equal(s.nav.at(-1), chat(B), "колесо вниз → B");
  assert.equal(st.chat, B);
  assert.ok(s.feed.scrollTop <= 2, `B: в начале, scrollTop ${s.feed.scrollTop}`);
  assert.ok(s.clock.t < s.loaded.inner.feedHold.ownUntil + 2000, "докрутка шла своей прокруткой (раздел 13а)");

  // 7. «Назад» и «Вперёд» истории роутера.
  s.win.history.back();
  await s.advance(1500);
  assert.equal(s.st().chat, A, "«Назад» → A");
  assert.equal(s.st().going, null);
  s.win.history.forward();
  await s.advance(1500);
  assert.equal(s.st().chat, B, "«Вперёд» → B");

  // 8. «В последний чат» → P; там фишки нет, на её месте — тихая метка «Последний чат».
  s.toBottom();
  await s.advance(1500);
  s.click("last");
  await s.advance(1300);
  st = s.st();
  assert.equal(st.chat, P, "«В последний чат» → P");
  assert.equal(st.last.kind, "last");
  assert.equal(st.shown.last, false, "в последнем фишки нет");
  assert.equal(st.shown.latest, true, "метка «Последний чат»");
  assert.match(text(s, "latest"), /^Последний чат«👾 Главный чат»/);
  // В стабе у метки нет ширины — она встаёт под строку заголовка (как фишка в узкой колонке); главное — не внизу.
  assert.ok(Number.parseFloat(s.node("latest").style.top) <= 40 + 8, "метка — на месте фишки, не на последнем сообщении");

  // 9. Боковой S: сверху — «Откуда запущен».
  s.router.navigate({ to: chat(S) });
  await s.advance(400);
  s.toTop();
  await s.advance(1800);
  st = s.st();
  assert.equal(st.shown.up, true);
  assert.match(text(s, "up"), /^↑ Откуда запущен«Монитор и сайт 25\.10»/);

  // 10. Claude ещё догружает сверху — плашки нет.
  s.host.olderHistoryAbove = true;
  s.to(30);
  await s.advance(300);
  s.toTop();
  await s.advance(1200);
  st = s.st();
  assert.equal(st.shown.up, false, "догрузка сверху — плашки нет");
  assert.equal(st.armed.up, false);
  s.host.olderHistoryAbove = false;

  // 11. Двойной инжект: один корень, работает.
  assert.equal(s.loaded.reload().error, null);
  await s.advance(1600);
  st = s.st();
  assert.equal(s.loaded.dom.queryAll("#myclaude-chain").length, 1, "один корень");
  assert.equal(st.chat, S);
  assert.equal(st.links.prev.id, D);

  // 12. Роутер молчит — «Не открылся… — нажми ещё раз», чат прежний.
  s.win.__TSR_ROUTER__ = { navigate: () => Promise.resolve() };
  await s.advance(1500);
  assert.equal(s.st().shown.up, true);
  s.click("up");
  await s.advance(8600);
  st = s.st();
  assert.equal(st.chat, S, "чат прежний");
  assert.ok(st.failed, "переход не удался");
  assert.match(text(s, "up"), /^Не открылся «Монитор и сайт 25\.10» — нажми ещё раз/);
  s.loaded.api.dispose();
});

// ---- Мак ---------------------------------------------------------------------------------------------------
// Долгая докрутка к началу: Claude догружает старое, пока тест не отпустит.
const longLanding = async () => {
  const s = stand({ chat: A });
  await s.advance(400);
  s.toBottom();
  await s.advance(1500);
  assert.equal(s.st().shown.down, true);
  s.host.olderHistoryAbove = true;
  s.click("down");
  await s.advance(2000);
  assert.equal(s.st().going?.phase, "land", "идёт докрутка к началу");
  return s;
};

test("Мак: Esc останавливает докрутку к началу, а сам Esc глотает раздел 16 (ход Claude не обрывается)", async () => {
  const s = await longLanding();
  const blocked = s.loaded.api.status().escapesBlocked;
  s.key("Escape");
  await s.advance(400);
  const st = s.st();
  assert.equal(st.going, null, "докрутка остановлена");
  assert.equal(st.last.stopped, true);
  assert.equal(s.loaded.api.status().escapesBlocked, blocked + 1, "Esc дошёл до раздела 16 — блок его не глотал");
  s.loaded.api.dispose();
});

test("Мак: докрутку к началу не перебивает чужое «к низу», место чтения 13а молчит", async () => {
  const s = await longLanding();
  // Кто-то (возврат места, «стояла у низа — к низу») уводит ленту вниз посреди докрутки.
  s.feed.scrollTop = 1e9;
  s.scrolled();
  assert.ok(s.loaded.inner.feedHold.ownUntil > s.clock.t, "раздел 13а видит свою прокрутку");
  await s.advance(400);
  assert.equal(s.feed.scrollTop, 0, "докрутка вернула ленту к началу");
  s.host.olderHistoryAbove = false;
  await s.advance(1000);
  const st = s.st();
  assert.equal(st.going, null);
  assert.equal(st.chat, B);
  assert.equal(st.last.ok, true);
  assert.equal(st.last.stopped, false, "не перебита");
  assert.equal(s.feed.scrollTop, 0);
  s.loaded.api.dispose();
});

test("Мак: dispose посреди докрутки — ни таймера, ни узла, ни зазора", async () => {
  const s = await longLanding();
  s.loaded.api.dispose();
  assert.equal(s.clock.q.size, 0, "очередь таймеров пуста");
  assert.equal(s.loaded.dom.queryAll("#myclaude-chain").length, 0);
  assert.equal(s.loaded.dom.queryAll("[data-myclaude-chain-gap]").length, 0);
  await s.advance(20000);
  assert.equal(s.nav.length, 1, "после снятия ничего не ходит");
});

test("Мак: «Следующий чат» встаёт выше «непрочитанных N» (раздел 12х)", async () => {
  const s = stand({ chat: A });
  await s.advance(400);
  s.toBottom();
  await s.advance(1500);
  assert.equal(s.st().shown.down, true);
  assert.equal(s.node("down").style.top, `${560 - 30 - 14}px`, "без «непрочитанных» — над низом ленты");
  s.loaded.document.body.add("div", { id: "myclaude-read-next", rect: { left: 860, top: 520, width: 120, height: 26 } });
  await s.advance(300);
  assert.equal(s.node("down").style.top, `${520 - 30 - 8}px`, "с «непрочитанными» — над ними");
  s.loaded.api.dispose();
});

test("Мак: зазор снизу — шов «↓ Следующий чат» встаёт над ним, а не на последнее сообщение; ушли вверх — снят", async () => {
  const s = stand({ chat: A });
  await s.advance(400);
  s.toBottom();
  await s.advance(1500);
  assert.equal(s.st().shown.down, true);
  assert.equal(s.st().gapBottom, true, "у низа со швом — зазор снизу");
  assert.equal(s.feed.getAttribute("data-myclaude-chain-gap-bottom"), "");
  await s.advance(1500);
  assert.equal(s.st().shown.down, true, "зазор не снимает шов сам (низ в зазоре — тоже низ)");
  s.to(1000);
  await s.advance(300);
  assert.equal(s.st().shown.down, false);
  assert.equal(s.st().gapBottom, false, "ушли вверх — зазор снят");
  s.toBottom();
  await s.advance(1500);
  assert.equal(s.st().gapBottom, true);
  s.loaded.api.dispose();
  assert.equal(s.loaded.dom.queryAll("[data-myclaude-chain-gap-bottom]").length, 0, "dispose снимает зазор");
});

test("цепочка: архивные — мимо линии (как на Windows), открытый архивный — сам в линии", () => {
  const s = stand();
  const c = s.loaded.inner.chainOf;
  const archived = LIST.map(x => (x.sessionId === C ? { ...x, isArchived: true } : x));
  const b = c(archived, B, new Set());
  assert.equal(b.next.id, D, "B → D: архивный C пропущен");
  assert.equal(b.total, 4);
  const me = c(archived, C, new Set());
  assert.equal(me.prev.id, B);
  assert.equal(me.next.id, D);
  assert.equal(me.total, 5, "открытый архивный — в своей линии");
  s.loaded.api.dispose();
});

test("Мак: попап — без швов; обход 12е — края не взводятся", async () => {
  const popup = loadInject({ href: "about:blank" });
  assert.equal(popup.error, null);
  assert.equal(popup.api.status().chain.on, false, "попап: блок молчит");
  popup.api.dispose();

  const s = stand({ chat: B });
  await s.advance(400);
  s.loaded.inner.roamState.phase = "roaming";
  s.toTop();
  await s.advance(1500);
  assert.equal(s.st().armed.up, false, "обход идёт — край не взведён");
  assert.equal(s.st().shown.up, false);
  s.loaded.inner.roamState.phase = "idle";
  await s.advance(300);
  assert.equal(s.st().shown.up, true, "обход кончился — плашка");
  s.loaded.api.dispose();
});

test("Мак: инерция тачпада — поток мелких дельт до края и дальше без паузы край не взводит", async () => {
  const s = stand({ chat: B });
  await s.advance(400);
  s.to(400);
  await s.advance(1500);
  // Хвост жеста: по 8 px каждые 16 мс — до верха (50 событий) и ещё секунду в край.
  await s.wheel(-8, 110, 16);
  let st = s.st();
  assert.equal(s.feed.scrollTop, 0, "доехали до верха");
  assert.equal(st.pull, 0, "натяжки нет");
  assert.equal(s.nav.length, 0);
  // Новый жест после паузы — уже натяжка.
  await s.advance(600);
  await s.wheel(-100, 1, 50);
  st = s.st();
  assert.ok(st.pull > 0, `новый жест тянет: ${st.pull}`);
  s.loaded.api.dispose();
});

test("Мак: фишка «N из M» в строке заголовка после меню чата; в колонке 354 — под строкой, не под ней", async () => {
  const wide = stand({ chat: B });
  await wide.advance(200);
  Object.assign(wide.node("last"), { offsetWidth: 150, offsetHeight: 24 });
  await wide.advance(300);
  assert.equal(wide.node("last").style.left, `${160 + 28 + 10}px`, "сразу за кнопкой меню");
  assert.equal(wide.node("last").style.top, `${(40 - 24) / 2}px`, "по середине строки заголовка");
  wide.loaded.api.dispose();

  const narrow = stand({ chat: B, feedW: 354 });
  await narrow.advance(200);
  Object.assign(narrow.node("last"), { offsetWidth: 150, offsetHeight: 24 });
  narrow.toTop();
  await narrow.advance(1500);
  assert.equal(narrow.node("last").style.left, `${354 - 150 - 18}px`, "не влезла — у правого края ленты");
  assert.equal(narrow.node("last").style.top, `${40 + 8}px`, "под строкой заголовка (низ строки — 40)");
  assert.equal(narrow.st().shown.up, true);
  assert.equal(narrow.node("up").style.top, `${40 + 8 + 32}px`, "плашка — под фишкой");
  assert.equal(narrow.st().gap, "top under", "зазор над первой строкой — и на фишку: плашка не ложится на первое сообщение");
  narrow.loaded.api.dispose();
});

test("Мак: широкий вид — строка заголовка над правой колонкой ленту сверху не режет", async () => {
  const s = stand({ chat: B, wide: true });
  await s.advance(400);
  s.toTop();
  await s.advance(1500);
  assert.equal(s.st().shown.up, true);
  assert.equal(s.node("up").style.top, `${0 + 8 + 32}px`, "от верха ленты (0), под фишкой — не от низа чужой строки заголовка");
  s.loaded.api.dispose();
});

// ---- Автопереход в новый чат линии (WF301 A2, #11201) ------------------------------------------------------
// Слово Элвиса 30.10 16:50: «окно автоматически должно переходить в новый чат». Окно стоит в последнем чате линии
// (закреплённый P), в линии появляется новый Y — окно само уходит в Y, когда тихо.
const Y = "local_99990000-0000-4000-8000-000000000009";
const NEW = { sessionId: Y, cwd: RICK, originCwd: RICK, createdAt: T0 + 250 * H, title: "Новый главный чат" };
const WINDOWS_KEY = "myclaude-chain-windows-v1";
const followStand = async ({ chat: at = P, ...opts } = {}) => {
  const list = LIST.map(x => ({ ...x }));
  const s = stand({ chat: at, list, ...opts });
  await s.advance(400);
  return Object.assign(s, { list, add: (extra = NEW) => list.push({ ...extra }), fl: () => s.st().follow });
};
// Список обновляется раз в 15 с: новый чат увиден на ближайшем обновлении.
const SEEN_MS = 15200;
const waitChat = async (s, id, ms = 4000) => {
  for (let t = 0; t < ms && s.st().chat !== id; t += 50) await s.advance(50);
  return s.st().chat === id;
};

test("автопереход: в линии появился новый чат, всё тихо — окно само уходит в него, метка «Перешёл в новый чат», «Назад» возвращает", async () => {
  const s = await followStand();
  assert.equal(s.st().links.last, null, "P — последний");
  assert.equal(s.fl().pending, null);
  s.add();
  await s.advance(SEEN_MS);
  assert.ok(await waitChat(s, Y), "окно ушло в Y");
  assert.equal(s.nav.at(-1), chat(Y), "переход роутером (пишет историю)");
  for (let t = 0; t < 4000 && !s.fl().last; t += 50) await s.advance(50);
  let st = s.st();
  assert.deepEqual({ from: st.follow.last.from, to: st.follow.last.to, ok: st.follow.last.ok }, { from: P, to: Y, ok: true });
  assert.equal(st.follow.pending, null);
  assert.equal(st.follow.blocked, null);
  assert.equal(st.last.kind, "follow");
  assert.equal(st.shown.latest, true, "метка на месте фишки");
  assert.match(text(s, "latest"), /^Перешёл в новый чат«Новый главный чат»/);
  assert.ok(Number.parseFloat(s.node("latest").style.top) <= 40 + 8, "метка — у строки заголовка, не на последнем сообщении");
  await s.advance(2000);
  assert.equal(s.st().shown.latest, true, "держится дольше обычной вспышки 1,4 с");
  await s.advance(2300);
  assert.equal(s.st().shown.latest, false, "через 4 с снята");
  // «Назад» мыши — в P; снова туда не уводит (Y уже в хвосте).
  s.win.history.back();
  await s.advance(1500);
  assert.equal(s.st().chat, P, "«Назад» → P");
  await s.advance(SEEN_MS * 2);
  st = s.st();
  assert.equal(st.chat, P, "из P больше не уводит");
  assert.equal(st.follow.pending, null);
  s.loaded.api.dispose();
});

test("автопереход ждёт: текст в поле, Claude пишет ответ, недавнее колесо или клавиша", async () => {
  // Текст в поле — ждём; поле опустело — переход.
  const s = await followStand();
  const editor = s.loaded.parts.prompt.add("div", { class: "ProseMirror", attrs: { contenteditable: "true" }, text: "черновик Элвиса", rect: { left: 16, top: 590, width: 900, height: 80 } });
  s.add();
  await s.advance(SEEN_MS + 3000);
  let f = s.fl();
  assert.equal(s.st().chat, P, "текст в поле — остаёмся");
  assert.equal(f.pending?.to, Y);
  assert.equal(f.blocked, "typing");
  editor.textContent = "";
  assert.ok(await waitChat(s, Y), "поле пустое — перешли");
  s.loaded.api.dispose();

  // Claude пишет ответ в P — ждём.
  const r = await followStand();
  r.host.isResponding = true;
  r.add();
  await r.advance(SEEN_MS + 3000);
  assert.equal(r.st().chat, P);
  assert.equal(r.fl().blocked, "responding");
  r.host.isResponding = false;
  assert.ok(await waitChat(r, Y), "ответ кончился — перешли");
  r.loaded.api.dispose();

  // Клавиша и колесо недавно — ждём 3 с тишины.
  const k = await followStand();
  k.add();
  await k.advance(SEEN_MS - 400);
  k.key("a");
  await k.advance(1000);
  assert.equal(k.fl().pending?.to, Y);
  assert.equal(k.fl().blocked, "active", "клавиша < 3 с назад");
  await k.wheel(-40, 1, 1000);
  assert.equal(k.fl().blocked, "active", "колесо < 3 с назад");
  assert.equal(k.st().chat, P);
  await k.advance(1500);
  assert.equal(k.st().chat, P, "3 с после колеса ещё не прошли");
  assert.ok(await waitChat(k, Y), "3 с тишины — перешли");
  k.loaded.api.dispose();
});

test("автопереход: окно без фокуса — без 3 с тишины, но после паузы на реестр окон", async () => {
  const s = await followStand();
  s.win.__hasFocus = false;
  s.add();
  await s.advance(SEEN_MS);
  s.key("a");
  await s.advance(600);
  assert.equal(s.fl().pending?.to, Y, "увидел новый чат и ждёт");
  assert.equal(s.st().chat, P, "сразу не уходит: другое окно, открывшее Y, ещё могло не записать себя");
  assert.equal(s.fl().blocked, "settle", "без фокуса недавняя клавиша не держит — держит только пауза");
  assert.ok(await waitChat(s, Y, 2000), "перешёл, не дожидаясь 3 с после клавиши");
  s.loaded.api.dispose();
});

test("автопереход: Y открыт в другом окне — отмена; окна пишут себя в localStorage, dispose убирает свою запись", async () => {
  const s = await followStand();
  const store = s.win.localStorage;
  const mine = s.loaded.inner.chainWindowId;
  await s.advance(2200);
  let all = JSON.parse(store.getItem(WINDOWS_KEY));
  assert.equal(all[mine].chat, P, "своя запись: чат окна");
  // Другое окно того же Claude держит Y (свежая запись); старая чужая запись (> 10 с) вычищается при записи.
  all.wOther = { chat: Y, at: Date.now() };
  all.wStale = { chat: B, at: Date.now() - 11000 };
  store.setItem(WINDOWS_KEY, JSON.stringify(all));
  s.add();
  await s.advance(SEEN_MS);
  let f = s.fl();
  assert.equal(f.pending, null, "не ждём");
  assert.equal(f.blocked, "other-window");
  all = JSON.parse(store.getItem(WINDOWS_KEY));
  assert.equal(all.wStale, undefined, "старая чужая запись вычищена");
  assert.equal(all.wOther.chat, Y, "свежая чужая — на месте");
  // Другое окно закрылось — всё равно не уводим: один раз, без повторов.
  delete all.wOther;
  store.setItem(WINDOWS_KEY, JSON.stringify(all));
  await s.advance(SEEN_MS);
  assert.equal(s.st().chat, P);
  assert.equal(s.st().shown.last, true, "фишка «N из M · В последний чат» — как была");
  assert.equal(text(s, "last"), "5 из 6 · В последний чат");
  // Своя запись с Y другого окна не держит, а dispose её убирает (чужие — остаются).
  all = JSON.parse(store.getItem(WINDOWS_KEY));
  all.wKeep = { chat: A, at: Date.now() };
  store.setItem(WINDOWS_KEY, JSON.stringify(all));
  s.loaded.api.dispose();
  all = JSON.parse(store.getItem(WINDOWS_KEY));
  assert.equal(all[mine], undefined, "dispose убрал свою запись");
  assert.equal(all.wKeep.chat, A);
});

test("автопереход не начинается: окно не в последнем чате, новый боковой чат или копия worktree", async () => {
  // D — не последний (после него P): новый чат в линии ничего не делает.
  const d = await followStand({ chat: D });
  d.add();
  await d.advance(SEEN_MS + 4000);
  assert.equal(d.st().chat, D);
  assert.equal(d.fl().pending, null);
  assert.equal(d.fl().last, null);
  d.loaded.api.dispose();

  // Боковой из P (lineage side_session, не закреплён) и копия worktree — не в линии.
  const s = await followStand();
  s.add({ ...NEW, sessionId: "local_99990000-0000-4000-8000-00000000000a", lineage: { kind: "side_session", sessionId: P }, title: "Боковой" });
  s.add({ ...NEW, sessionId: "local_99990000-0000-4000-8000-00000000000b", cwd: `${RICK}/.claude/worktrees/wf9`, title: "Копия worktree" });
  s.add({ ...NEW, sessionId: "local_99990000-0000-4000-8000-00000000000c", forkedFromSessionId: P, title: "Форк" });
  await s.advance(SEEN_MS + 4000);
  assert.equal(s.st().chat, P);
  assert.equal(s.st().links.last, null, "P — всё ещё последний");
  assert.equal(s.fl().pending, null);
  assert.equal(s.nav.length, 0);
  // Боковой закрепили — он продолжение линии: переход.
  s.list.find(x => x.title === "Боковой").isStarred = true;
  await s.advance(SEEN_MS);
  assert.ok(await waitChat(s, "local_99990000-0000-4000-8000-00000000000a"), "закреплённый новый главный — переход");
  s.loaded.api.dispose();
});

test("автопереход снимается: окно само сменило чат, 30 мин, чат пропал, переход не удался — без повторов", async () => {
  // Сменили чат (человек ушёл или renew уже поставил новый) — не ждём.
  const m = await followStand();
  m.host.isResponding = true;
  m.add();
  await m.advance(SEEN_MS);
  assert.equal(m.fl().pending?.to, Y);
  m.router.navigate({ to: chat(B) });
  await m.advance(400);
  assert.equal(m.fl().pending, null);
  assert.equal(m.fl().blocked, "moved");
  m.host.isResponding = false;
  await m.advance(SEEN_MS);
  assert.equal(m.st().chat, B, "из B не уводит");
  m.loaded.api.dispose();

  // 30 мин ожидания.
  const e = await followStand();
  e.host.isResponding = true;
  e.add();
  await e.advance(SEEN_MS);
  assert.equal(e.fl().pending?.to, Y);
  e.loaded.inner.chainState.follow.pending.t -= e.loaded.inner.CHAIN_FOLLOW_WINDOW_MS + 1;
  await e.advance(300);
  assert.equal(e.fl().pending, null);
  assert.equal(e.fl().blocked, "expired");
  e.host.isResponding = false;
  await e.advance(SEEN_MS);
  assert.equal(e.st().chat, P);
  e.loaded.api.dispose();

  // Чат пропал из списка.
  const g = await followStand();
  g.host.isResponding = true;
  g.add();
  await g.advance(SEEN_MS);
  g.list.pop();
  await g.advance(SEEN_MS);
  assert.equal(g.fl().pending, null);
  assert.equal(g.fl().blocked, "gone");
  g.loaded.api.dispose();

  // Роутер молчит — «не удался», один раз.
  const n = await followStand();
  n.win.__TSR_ROUTER__ = { navigate: () => Promise.resolve() };
  n.add();
  await n.advance(SEEN_MS + 2500 + 9000);
  const f = n.fl();
  assert.equal(n.st().chat, P);
  assert.equal(f.blocked, "failed");
  assert.deepEqual({ to: f.last.to, ok: f.last.ok }, { to: Y, ok: false });
  assert.equal(n.st().shown.up, false, "тихо: ни «Не открылся», ни швов");
  await n.advance(SEEN_MS);
  assert.equal(n.fl().pending, null, "без повторов");
  n.loaded.api.dispose();
});
