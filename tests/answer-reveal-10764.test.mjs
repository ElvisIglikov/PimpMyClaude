// #10764 (раздел 14б inject.js, 23.10): ответ без печаталки — пока Claude пишет, сообщения не видно; финальный
// ответ: лента плавно (ease-out) встаёт на время реплики Элвиса над ним («N min ago»), ответ проявляется синхронно
// и виден целиком ровно к остановке ленты. Плюс главы (#9757): на Claude 2.32 пропсы главы ушли глубже
// (~20 волокон над кнопкой) — своих глав не было вовсе; переход по своей главе — к месту «N min ago».
// Слово Элвиса 23.10: «когда ответ готов, плавно прокрутить до места 2 min ago? И плавно показать ответ без
// появления, без вот этого печатания… в тот момент, когда прокрутка полностью остановилась, эта штука полностью
// прояснилась… Мне надо, чтобы главой метилось вот это место, где сейчас три минуты эго».
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const HOLD = "data-myclaude-reveal-hold";
const ROW_H = 100;

// Лента: u0 (реплика Элвиса, время «2 min ago» у её низа: 80…100), A1 — ответ, который пишется.
const stand = ({ working = true } = {}) => {
  const nodes = {};
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_reveal-10764", title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({});
      nodes.stop = working ? dom.document.body.add("button", { attrs: { "data-testid": "chat-input-stop" } }) : null;
      nodes.feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: { left: 0, top: 0, width: 800, height: 600 } });
      nodes.feed.clientHeight = 600;
      nodes.feed.scrollHeight = 3000;
      nodes.rows = nodes.feed.add("div", { attrs: { "data-testid": "transcript-rows" } });
      nodes.user = nodes.rows.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "0", "data-perf-row": "human" }, rect: { left: 0, top: 0, width: 800, height: ROW_H } });
      nodes.user.add("div", { class: "epitaxy-user-turn" }).add("p", { text: "что с ракетой" });
      // Родная строка времени реплики «✓✓ 2 min ago · …» (свой узел времени раздел 14а сам снимает в стенде).
      nodes.stamp = nodes.user.add("time", { attrs: { datetime: "2026-10-23T14:19:35.723Z", "data-row-time": "" }, rect: { left: 0, top: 80, width: 80, height: 20 } });
      nodes.answerRow = nodes.rows.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "1", "data-perf-row": "assistant" }, rect: { left: 0, top: ROW_H, width: 800, height: 900 } });
      nodes.answer = nodes.answerRow.add("div", { attrs: { "data-cds": "AssistantMessage", "data-is-streaming": "true" } });
      nodes.answer.add("p", { text: "Ракета снова показывается по нажатию." });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  let clock = 1000000;
  loaded.win.performance.now = () => clock;
  const at = ms => { clock = ms; };
  const reveal = () => loaded.inner.revealSync();
  return { loaded, nodes, at, reveal, get clock() { return clock; } };
};
const status = loaded => plain(loaded.api.status().reveal);
const fadesOn = (loaded, node) => loaded.dom.animations.filter(item => item.node === node);

test("#10764: пока ответ пишется — его не видно (метка и правило с первого кадра), печатания нет", () => {
  const { loaded, nodes, reveal } = stand();
  reveal();
  assert.equal(nodes.answer.hasAttribute(HOLD), true, "пишущийся ответ под меткой");
  assert.equal(loaded.document.documentElement.hasAttribute("data-myclaude-reveal"), true);
  const css = loaded.dom.queryAll("style").map(node => node.textContent).join("\n");
  assert.match(css, /html\[data-myclaude-reveal\] \[data-myclaude-reveal-hold\]\{opacity:0\}/,
    "правило прячет помеченное без !important — проявление сильнее");
  assert.doesNotMatch(css, /\[data-is-streaming="true"\]:not\(\[data-myclaude-reveal-free\]\)/, "#10903: сам «пишется» не прячет — только метка");
  assert.equal(status(loaded).held, 1);
  loaded.api.dispose();
  assert.equal(nodes.answer.hasAttribute(HOLD), false, "dispose снимает метку — текст виден");
  assert.equal(loaded.document.documentElement.hasAttribute("data-myclaude-reveal"), false);
});

test("#10764: финальный ответ — лента плавно встаёт на «2 min ago», проявление кончается ровно с остановкой", () => {
  const s = stand();
  const { loaded, nodes, reveal } = s;
  reveal();
  const start = s.clock;
  nodes.stop.remove();
  nodes.answer.setAttribute("data-is-streaming", "false");
  reveal();
  assert.equal(nodes.answer.hasAttribute(HOLD), false, "метка снята — дальше правит проявление");
  const [fade] = fadesOn(loaded, nodes.answer);
  assert.ok(fade, "ответ проявляется");
  assert.deepEqual(plain(fade.frames), [{ opacity: 0 }, { opacity: 1 }]);
  const ms = loaded.inner.REVEAL_MS;
  assert.equal(fade.options.fill, "backwards", "до начала проявления ответ прозрачен");
  assert.ok(fade.options.delay > 0 && fade.options.delay < ms / 2, "проявление начинается, когда лента уже замедляется");
  assert.equal(fade.options.delay + fade.options.duration, ms, "текст виден целиком ровно к остановке ленты");
  // Цель: время реплики (верх 80) — у верха ленты с отступом 12.
  const target = 80 - 12;
  s.at(start + ms / 2);
  loaded.dom.fireKind("raf");
  assert.ok(nodes.feed.scrollTop > target / 2 && nodes.feed.scrollTop < target, `к середине хода пройдено больше половины (ease-out): ${nodes.feed.scrollTop}`);
  s.at(start + ms);
  loaded.dom.fireKind("raf");
  assert.equal(nodes.feed.scrollTop, target, "лента встала: «2 min ago» сверху, ответ под ним");
  assert.equal(loaded.dom.count("raf") >= 0, true);
  loaded.dom.fireKind("raf");
  assert.equal(nodes.feed.scrollTop, target, "после остановки лента не дёргается");
  assert.deepEqual({ ...status(loaded), held: 0 }, { held: 0, finals: 1, glides: 1, fades: 1, broken: 0, skip: null, nudges: 0, freed: 0 });
  assert.equal(loaded.inner.revealPlaced(s.clock), true, "раздел 12м к низу уже не тянет");
  loaded.api.dispose();
});

test("#10764: промежуточное сообщение и затянувшийся ход — только проявление, лента на месте", () => {
  const s = stand();
  const { loaded, nodes, reveal } = s;
  reveal();
  nodes.answer.setAttribute("data-is-streaming", "false");
  reveal();
  assert.equal(nodes.answer.hasAttribute(HOLD), true, "ход идёт, за сообщением пусто — ждём, финальное ли");
  nodes.rows.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "2", "data-perf-row": "tool" } });
  reveal();
  assert.equal(nodes.answer.hasAttribute(HOLD), false);
  const [fade] = fadesOn(loaded, nodes.answer);
  assert.equal(fade.options.delay, 0);
  assert.equal(nodes.feed.scrollTop, 0, "лента не двигалась");
  assert.equal(status(loaded).glides, 0);

  // Ход не кончился, за сообщением ничего — через REVEAL_WAIT_MS показываем всё равно.
  const t = stand();
  t.reveal();
  t.nodes.answer.setAttribute("data-is-streaming", "false");
  t.reveal();
  assert.equal(t.nodes.answer.hasAttribute(HOLD), true);
  t.at(t.clock + 1500);
  t.loaded.dom.fireKind("timeout");
  assert.equal(t.nodes.answer.hasAttribute(HOLD), false, "текст не прячется дольше REVEAL_WAIT_MS после записи");
  assert.equal(t.nodes.feed.scrollTop, 0);
  loaded.api.dispose();
  t.loaded.api.dispose();
});

test("#10764 проверка: метка «пишется» залипла (хода нет — обрыв, ошибка, сеть) — ответ не остаётся спрятанным", () => {
  // Ход идёт, а текст не растёт (команда, ожидание) — через REVEAL_WAIT_MS виден (#10903: пустоты вместо текста нет).
  const s = stand();
  s.at(Date.now() + 60000);
  s.loaded.dom.fireKind("timeout");
  s.reveal();
  assert.equal(s.nodes.answer.hasAttribute(HOLD), false, "ход идёт, текст стоит — виден");
  assert.equal(status(s.loaded).freed, 1);
  s.loaded.api.dispose();
  // Кнопки стопа нет, а data-is-streaming="true" висит: через REVEAL_WAIT_MS — проявить.
  const t = stand({ working: false });
  t.reveal();
  assert.equal(t.nodes.answer.hasAttribute(HOLD), true, "сначала ждём: метка могла не успеть смениться");
  // Первая сверка была при установке страницы, по часам стенда по умолчанию (Date.now) — отсчёт от неё.
  t.at(Date.now() + 1500);
  t.loaded.dom.fireKind("timeout");
  assert.equal(t.nodes.answer.hasAttribute(HOLD), false);
  assert.equal(t.nodes.answer.hasAttribute("data-myclaude-reveal-free"), true, "правило «пишется» к нему больше не относится");
  assert.equal(fadesOn(t.loaded, t.nodes.answer).length, 1, "проявляется");
  assert.equal(status(t.loaded).freed, 1);
  t.reveal();
  assert.equal(t.nodes.answer.hasAttribute(HOLD), false, "снова под метку не встаёт");
  t.loaded.api.dispose();
  assert.equal(t.nodes.answer.hasAttribute("data-myclaude-reveal-free"), false, "dispose снимает и эту метку");
});

test("#10764: Элвис читает выше или тронул окно посреди хода — ленту не тянем", () => {
  const s = stand();
  const { loaded, nodes, reveal } = s;
  reveal();
  loaded.win.dispatchEvent({ type: "wheel", target: nodes.user, deltaY: -120 });
  nodes.stop.remove();
  nodes.answer.setAttribute("data-is-streaming", "false");
  reveal();
  assert.equal(nodes.answer.hasAttribute(HOLD), false, "ответ всё равно виден");
  assert.equal(loaded.dom.count("raf") === 0 || status(loaded).glides === 0, true);
  assert.equal(status(loaded).skip, "читает выше");
  assert.equal(nodes.feed.scrollTop, 0);
  loaded.api.dispose();

  const t = stand();
  t.reveal();
  const start = t.clock;
  t.nodes.stop.remove();
  t.nodes.answer.setAttribute("data-is-streaming", "false");
  t.reveal();
  assert.equal(status(t.loaded).glides, 1);
  t.at(start + 100);
  t.loaded.win.dispatchEvent({ type: "keydown", key: "a", target: t.loaded.document.body });
  t.loaded.dom.fireKind("raf");
  assert.equal(t.nodes.feed.scrollTop, 0, "касание обрывает ход ленты на месте");
  assert.equal(status(t.loaded).broken, 1);
  t.loaded.api.dispose();
});

test("#10764: «Уменьшить движение» — лента встаёт сразу, ответ виден сразу", () => {
  const s = stand();
  const { loaded, nodes, reveal } = s;
  loaded.win.__reducedMotion = true;
  reveal();
  nodes.stop.remove();
  nodes.answer.setAttribute("data-is-streaming", "false");
  reveal();
  assert.equal(nodes.feed.scrollTop, 68);
  assert.equal(fadesOn(loaded, nodes.answer).length, 0, "без проявления");
  assert.equal(nodes.answer.hasAttribute(HOLD), false);
  loaded.api.dispose();
});

// Главы: дорожка Claude, у строк — пропсы главы глубоко (как на 2.32: контекстное меню над кнопкой), лента с
// entries; ответ A3 без главы Claude получает свою, переход — к «N min ago» над ним.
const text = value => ({ kind: "text", text: value });
const ENTRIES = [
  { id: "u0", author: "user", items: [text("начнём")] },
  { id: "A1", author: "assistant", items: [{ kind: "chapter", id: "ch-1", title: "Утро" }, text("**✅ Утренние дела розданы, марафон Пимпа идёт третьим кругом.**")] },
  { id: "u2", author: "user", items: [text("что с ракетой")] },
  { id: "A3", author: "assistant", items: [text("✅ **Ракета снова показывается по нажатию: «Показать ракету» больше не молчит.**")] },
];
const NATIVE = [
  { id: "session-start", title: "Session start", source: "session", entryId: "u0", entryIndex: 0 },
  { id: "ch-1", title: "Утро", source: "claude", entryId: "A1", entryIndex: 1 },
];
const deepFiber = (row, list, chapter, depth) => {
  const top = { memoizedProps: { role: "list" }, stateNode: list, return: null };
  const owner = { memoizedProps: { chapter, sessionId: "s" }, return: top };
  let fiber = { memoizedProps: { className: "hit-row" }, stateNode: row, return: owner };
  for (let hop = 0; hop < depth; hop += 1) fiber = { memoizedProps: { value: hop }, return: fiber };
  return fiber;
};
const chapters = ({ depth = 18, above = false } = {}) => {
  const nodes = {};
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_chapters-10764", title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({});
      nodes.feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: { left: 0, top: 0, width: 800, height: 600 } });
      nodes.feed.clientHeight = 600;
      nodes.feed.scrollHeight = ENTRIES.length * ROW_H + 600;
      ENTRIES.forEach((entry, at) => {
        const row = nodes.feed.add("div", {
          attrs: { "data-testid": "transcript-row", "data-index": String(at), "data-perf-row": entry.author === "user" ? "human" : "assistant", "data-perf-row-streaming": "false" },
          rect: { left: 0, top: at * ROW_H, width: 800, height: ROW_H },
        });
        const column = row.add("div", { attrs: { "data-epitaxy-entry": entry.id, "data-epitaxy-entry-index": String(at) } });
        if (entry.author === "assistant") column.add("div", { attrs: { "data-cds": "AssistantMessage", "data-turn-key": entry.id } }).add("div").add("div", { attrs: { "data-cds": "Prose" } }).add("p", { text: entry.items.find(item => item.kind === "text")?.text ?? "" });
        else {
          column.add("div", { attrs: { "data-cds": "UserMessage" } }).add("div", { class: "text-primary" }).add("p", { text: "вопрос" });
          row.add("time", { attrs: { datetime: "2026-10-23T14:19:35.723Z" }, rect: { left: 0, top: at * ROW_H + 80, width: 80, height: 20 } });
        }
      });
      nodes.feed.__reactFiber$test = { memoizedProps: {}, return: { memoizedProps: { entries: ENTRIES, isResponding: false, olderHistoryAbove: false }, return: null } };
      const toc = dom.document.body.add("div", { class: "epitaxy-toc absolute pointer-events-none" });
      nodes.nav = toc.add("nav", { attrs: { "aria-label": "Session chapters", tabindex: "0" }, rect: { left: 8, top: 48, width: 32, height: 400 } });
      const rail = nodes.nav.add("ol", { attrs: { "aria-hidden": "true" }, class: "flex flex-col" });
      nodes.list = nodes.nav.add("div", { class: "absolute start-0 top-0 invisible opacity-0" }).add("ol", { attrs: { role: "list" } });
      NATIVE.forEach(chapter => {
        const now = chapter.id === "ch-1";
        rail.add("li", { class: "h-[8px] flex items-center" }).add("span", { class: now ? "block h-[2px] bg-alpha-8" : "block h-[2px] scale-x-[calc(9/14)] bg-alpha-3" });
        const row = nodes.list.add("li", { class: "hit-row" });
        const button = row.add("button", { attrs: { type: "button", ...(now ? { "aria-current": "true" } : {}) }, class: "group/ch w-full flex text-secondary hover:text-primary" });
        button.add("span", { attrs: { "aria-hidden": "true" }, class: "block h-[2px]" });
        button.add("span", { class: "flex-1 truncate", text: chapter.title });
        // above — пропсы главы выше списка строк: чужие, не брать.
        button.__reactFiber$test = above
          ? deepFiber(row, nodes.list, null, depth)
          : deepFiber(row, nodes.list, chapter, depth);
        if (above) {
          let fiber = button.__reactFiber$test;
          while (fiber.return) fiber = fiber.return;
          fiber.return = { memoizedProps: { chapter }, return: null };
        }
      });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.inner.readTick();
  loaded.inner.chTick();
  return { loaded, nodes };
};

test("#10764: главы вернулись — пропсы главы на ~20-м волокне находятся, выше списка строк — нет", () => {
  const { loaded, nodes } = chapters();
  const own = [...nodes.list.children].filter(node => node.hasAttribute("data-myclaude-ch-own"));
  assert.deepEqual(own.map(row => row.__myclaudeOwn), ["A3"], "ответ без главы Claude — своя глава");
  assert.equal(plain(loaded.api.status().chapters).lastError, null);
  assert.equal(loaded.inner.chKeyOf(nodes.list.children[0], 0), "id:session-start", "ключ главы — из пропсов");
  loaded.api.dispose();

  const far = chapters({ above: true });
  assert.equal([...far.nodes.list.children].filter(node => node.hasAttribute("data-myclaude-ch-own")).length, 0);
  assert.match(plain(far.loaded.api.status().chapters).lastError, /нет места в ленте/);
  far.loaded.api.dispose();
});

test("#10764: нажатие по своей главе — строка «3 min ago» над ответом встаёт к самому верху ленты (скрин №2)", () => {
  const { loaded, nodes } = chapters();
  const row = [...nodes.list.children].find(node => node.__myclaudeOwn === "A3");
  const button = [...row.children][0];
  loaded.document.dispatchEvent({ type: "click", target: button, button: 0, detail: 1 });
  // Время реплики u2 (верх 280) — на 12 px от верха ленты, ответ A3 (верх 300) — сразу под ним.
  assert.equal(nodes.feed.scrollTop, 280 - 12);
  loaded.api.dispose();
});

test("#10764 проверка (слово Элвиса 20:4x): глава Claude — к началу её ответа, сверху «✓✓ N ago», не на место главы внутри ответа", () => {
  const { loaded, nodes } = chapters();
  // Нажатие и дошло ли оно до Claude (его слушатель на document после наших).
  const press = row => {
    const button = [...row.children].find(node => node.tagName === "BUTTON");
    let reached = false;
    const claude = () => { reached = true; };
    loaded.document.addEventListener("click", claude);
    const prevented = !loaded.document.dispatchEvent({ type: "click", target: button, button: 0, detail: 1 });
    loaded.document.removeEventListener("click", claude);
    return { prevented, reached };
  };
  const rows = [...nodes.list.children].filter(node => !node.__myclaudeOwn);
  // «Утро» — глава Claude в ответе A1 (верх 100): время реплики u0 (верх 80) — на 12 px от верха ленты.
  const morning = press(rows[1]);
  assert.deepEqual(morning, { prevented: true, reached: false }, "переход Claude на место главы не идёт");
  assert.equal(nodes.feed.scrollTop, 80 - 12, "сверху строка времени, под ней начало ответа");
  // «Session start» — реплика человека, не ответ: переход Claude как есть.
  nodes.feed.scrollTop = 0;
  const start = press(rows[0]);
  assert.deepEqual(start, { prevented: false, reached: true });
  assert.equal(nodes.feed.scrollTop, 0);
  loaded.api.dispose();
});

test("#10764 живьём 23.10 22:17: лента под кнопками окна (угловой фейд) — время встаёт ниже кнопок, не под светофор", () => {
  const { loaded, nodes } = chapters();
  nodes.feed.setAttribute("data-myclaude-corner-fade", "");
  const morning = [...nodes.list.children].filter(node => !node.__myclaudeOwn)[1];
  loaded.document.dispatchEvent({ type: "click", target: [...morning.children][0], button: 0, detail: 1 });
  // Кнопки окна — до 40 px от верха; время реплики u0 (верх 80) — на 40 + 6, начало ответа A1 — под ним.
  assert.equal(nodes.feed.scrollTop, 80 - 46);
  loaded.api.dispose();
});

// Вход в чат (скрин №1 → №2): Claude поставил начало ответа под самый верх, строка «✓✓ 8 min ago» реплики над ним
// (её верх −20) уехала за край. Лента прокручена на 500.
const entered = ({ answerTop = 0 } = {}) => {
  const nodes = {};
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_enter-10764", title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({});
      nodes.feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: { left: 0, top: 0, width: 800, height: 600 } });
      nodes.feed.clientHeight = 600;
      nodes.feed.scrollHeight = 3000;
      nodes.feed.scrollTop = 500;
      const rows = nodes.feed.add("div", { attrs: { "data-testid": "transcript-rows" } });
      const user = rows.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "0", "data-perf-row": "human" }, rect: { left: 0, top: answerTop - ROW_H, width: 800, height: ROW_H } });
      user.add("time", { attrs: { datetime: "2026-10-23T14:19:35.723Z" }, rect: { left: 0, top: answerTop - 20, width: 80, height: 20 } });
      nodes.answer = rows.add("div", { attrs: { "data-testid": "transcript-row", "data-index": "1", "data-perf-row": "assistant" }, rect: { left: 0, top: answerTop, width: 800, height: 900 } });
      nodes.answer.add("div", { attrs: { "data-cds": "AssistantMessage" } }).add("p", { text: "Что делаем" });
      nodes.nav = dom.document.body.add("div", { class: "epitaxy-toc" }).add("nav", { attrs: { "aria-label": "Session chapters" } });
      nodes.nav.add("ol", { attrs: { "aria-hidden": "true" } });
      nodes.native = nodes.nav.add("div").add("ol", { attrs: { role: "list" } }).add("li").add("button", { attrs: { type: "button" } });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  // Вход в чат (смена адреса) — то же, что revealEnterArm с часами.
  loaded.inner.revealEnterArm();
  return { loaded, nodes };
};

test("#10764: вход в чат — строка «N min ago» встаёт к верху (12 px), ответ под ней; тронул окно — не трогаем", () => {
  const { loaded, nodes } = entered();
  loaded.dom.fireKind("timeout");
  // Начало ответа (0) должно встать на 12 + 20: лента вверх на 32.
  assert.equal(nodes.feed.scrollTop, 500 - 32);
  assert.equal(plain(loaded.api.status().reveal).nudges, 1);
  loaded.api.dispose();

  const touched = entered();
  touched.loaded.win.dispatchEvent({ type: "keydown", key: "a", target: touched.loaded.document.body });
  touched.loaded.dom.fireKind("timeout");
  assert.equal(touched.nodes.feed.scrollTop, 500, "Элвис взялся за окно сам — место его");
  touched.loaded.api.dispose();

  // Место чтения посреди ответа (начало далеко выше верха) — как есть.
  const middle = entered({ answerTop: -300 });
  middle.loaded.dom.fireKind("timeout");
  assert.equal(middle.nodes.feed.scrollTop, 500);
  middle.loaded.api.dispose();
});

test("#10764 проверка: лента ещё едет (плавный переход Claude, догрузка) — не сдвигаем посреди хода, только после тишины", () => {
  const { loaded, nodes } = entered();
  let clock = 5000000;
  loaded.win.performance.now = () => clock;
  loaded.inner.revealEnterArm();
  loaded.document.dispatchEvent({ type: "scroll", target: nodes.feed });
  loaded.dom.fireKind("timeout");
  assert.equal(nodes.feed.scrollTop, 500, "только что ехала — не трогаем, иначе оборвём ход Claude на чужой строке");
  clock += 300;
  loaded.dom.fireKind("timeout");
  assert.equal(nodes.feed.scrollTop, 500 - 32, "встала — строка времени к верху");
  loaded.api.dispose();
});

test("#10764: нажатие по главе Claude — после его перехода лента встаёт на строку времени", () => {
  const { loaded, nodes } = entered({ answerTop: -300 });
  loaded.dom.fireKind("timeout");
  assert.equal(nodes.feed.scrollTop, 500);
  // Claude перешёл к главе: начало ответа под самым верхом.
  nodes.answer.rect = { left: 0, top: 0, width: 800, height: 900 };
  nodes.answer.previousElementSibling.rect = { left: 0, top: -ROW_H, width: 800, height: ROW_H };
  nodes.answer.previousElementSibling.querySelector("time").rect = { left: 0, top: -20, width: 80, height: 20 };
  loaded.win.dispatchEvent({ type: "pointerdown", target: nodes.native });
  loaded.document.dispatchEvent({ type: "click", target: nodes.native, button: 0, detail: 1 });
  loaded.dom.fireKind("timeout");
  assert.equal(nodes.feed.scrollTop, 500 - 32);
  loaded.api.dispose();
});
