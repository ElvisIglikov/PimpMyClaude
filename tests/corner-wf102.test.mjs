// Угол «Проект · чат» (#7911) и главное окно без шапки (#7913), раздел 2ж
// inject.js, WF102. Слово Элвиса 26.09: «чтобы всегда в правом углу это место
// было занято под название проекта… заголовок чата — там же справа… фейд»;
// «этот хедер нужно вообще убрать у главного… чтобы по высоте освободить место».
//
// Стенд — как окна Claude по разведке 26.09: шапка .epitaxy-titlebar с названием
// чата [data-pane-title] и подписью проекта [data-testid="epitaxy-origin-label"],
// панель .epitaxy-chat-panel; попап — about:blank шириной 282, главное окно —
// claude.ai со списком чатов слева (сессия строки в React-волокне, как у Claude).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CORNER = "#myclaude-corner";
const DRAG = "#myclaude-main-drag";
const WIDE_FLAG = "--myclaude-wide";
const LONG_CHAT = "Семь окон с центральной оркестрацией и очень длинным хвостом";

const stand = ({ storage, href = "about:blank", width = 282, origin = "PimpMyClaude", chat = LONG_CHAT, wide = false, panelLeft = 9, row = null, fiberId = null, opener = null, gutter = null, sidebar = null } = {}) =>
  loadInject({
    href, title: chat, opener, storage,
    geometry: { viewport: { width, height: 720 } },
    html: dom => {
      const parts = dom.composer({ top: 560 });
      const panel = dom.document.body.add("div", {
        class: "epitaxy-chat-panel", rect: { left: panelLeft, top: 9, width: width - panelLeft - 1, height: 702 },
        computed: wide ? { [WIDE_FLAG]: "1" } : {},
      });
      const titlebar = panel.add("div", { class: "epitaxy-titlebar", rect: { left: 77, top: 9, width: 158, height: 32 } });
      // Попап знает свой чат по волокну шапки (episodeKey, раздел 12в).
      if (fiberId) titlebar["__reactFiber$test"] = { memoizedProps: { episodeKey: fiberId }, return: null };
      const lead = titlebar.add("div", { class: "group/lead" });
      // Remote Control у названия (#9054) — по нему строка «row».
      if (gutter) lead.add("button", { attrs: { "data-testid": "epitaxy-origin-gutter" }, rect: gutter });
      // Список чатов главного окна с кнопкой New (#9054) — по нему место «side».
      if (sidebar) {
        // Как живьём (замер WF155): aside.dframe-sidebar → строка окна .df-titlebar (светофор,
        // панель, назад, вперёд, переключатель Claude/Code) и список чатов с New.
        const host = sidebar.root ? dom.document.body.add("div", { class: "dframe-root" }) : dom.document.body;
        const aside = sidebar.aside ? host.add("aside", { class: "dframe-sidebar", rect: sidebar.aside }) : host;
        if (sidebar.titlebar) {
          const bar = aside.add("div", { class: "df-titlebar draggable", rect: sidebar.titlebar });
          for (const [label, rect] of sidebar.buttons ?? []) bar.add("button", { class: "df-chrome-btn", attrs: { "aria-label": label }, rect });
          if (sidebar.mode) bar.add("div", { class: "draggable-none flex ml-auto" }).add("div", { class: "df-app-switch flex" })
            .add("div", { attrs: { role: "radiogroup", "aria-label": "Mode" }, rect: sidebar.mode });
        }
        const list = aside.add("div", { attrs: { "data-testid": "sidebar" }, rect: sidebar.list });
        const next = list.add("button", { attrs: { "aria-keyshortcuts": "Meta+n" }, rect: sidebar.next });
        if (sidebar.circle) next.add("span", { class: "df-new-circle", rect: sidebar.circle });
      }
      const titleWrap = lead.add("span");
      const title = chat ? titleWrap.add("span", { attrs: { "data-pane-title": "" }, text: chat, rect: { left: 105, top: 13, width: 40, height: 24 } }) : null;
      const label = origin ? lead.add("button").add("span", { attrs: { "data-testid": "epitaxy-origin-label" }, text: origin }) : null;
      const tail = panel.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript" },
        rect: { left: panelLeft, top: 9, width: width - panelLeft - 1, height: 560 },
      });
      if (row) {
        const bar = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
        const node = bar.add("div", { attrs: { "data-row-key": `code:${row.id}` } });
        const session = { ref: { kind: "code", id: row.id }, title: chat, updatedAtMs: row.updatedAtMs, source: { kind: "code", data: row.data } };
        node["__reactFiber$test"] = { memoizedProps: { session }, return: null };
      }
      return { ...parts, panel, titlebar, title, label, tail };
    },
  });
// Проход раскладки: угол и шапку ставит он.
const pass = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const corner = loaded => loaded.dom.query(CORNER);
const parts = node => ({ project: node.children[0], chat: node.children[1], clock: node.children[2], text: node.children[1].children[1] });

test("#7911: попап 282 — угол виден, имя проекта целиком, чат рядом", () => {
  const loaded = stand();
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  pass(loaded);
  const node = corner(loaded);
  const { project, chat, text } = parts(node);
  assert.equal(node.style.getPropertyValue("display"), "flex");
  assert.equal(project.textContent, "PimpMyClaude", "имя проекта не обрезано");
  assert.equal(text.textContent, LONG_CHAT, "чат — название из шапки");
  // Имя проекта не сжимается, сжимается чат; угол не шире окна минус место под кнопки.
  assert.equal(project.style.getPropertyValue("flex"), "0 0 auto");
  assert.equal(chat.style.getPropertyValue("flex"), "0 1 auto");
  assert.equal(chat.style.getPropertyValue("min-width"), "0");
  assert.equal(chat.style.getPropertyValue("overflow"), "hidden");
  assert.equal(node.style.getPropertyValue("max-width"), "calc(100vw - 84px)");
  // Мышь и перетаскивание окна угол не трогает.
  assert.equal(node.style.getPropertyValue("pointer-events"), "none");
  assert.equal(node.style.getPropertyValue("-webkit-app-region"), "");
  // WF103, решение 12: прижат к самому верху окна; правый край — по панели (281 из 282, как живьём).
  assert.equal(node.style.getPropertyValue("top"), "0px");
  assert.equal(node.style.getPropertyValue("right"), "1px");
  assert.deepEqual(plain(loaded.api.status().corner), { on: true, project: "PimpMyClaude", chat: LONG_CHAT, fade: false, cover: false, clock: null, late: false, stage: null, mode: "corner", line: null, switch: null, tail: { project: false, chat: false }, lines: null, menu: null, originMenu: null });
  assert.equal(loaded.document.documentElement.getAttribute("data-myclaude-corner"), "on");
});

test("#9104 (WF139): живой фон — плашка угла без сплошной заливки, только размытие", () => {
  const loaded = stand();
  loaded.document.body.computed = { backgroundColor: "rgb(5, 58, 43)" };
  loaded.dom.command({ id: "wf139-corner", action: "theme", at: "now", scope: "all", look: { aurora: true } });
  pass(loaded);
  const node = corner(loaded);
  assert.equal(node.style.getPropertyValue("--myclaude-corner-bg"), "", "цвет фона окна не кладётся поверх живого фона");
  loaded.dom.command({ id: "wf139-corner-off", action: "theme", at: "now", scope: "all", look: null });
  pass(loaded);
  assert.equal(node.style.getPropertyValue("--myclaude-corner-bg"), "rgb(5, 58, 43)", "без живого фона — прежняя сплошная плашка");
});

// WF185 (слово Элвиса 09.10 03:35: «должно быть так же, как в Today — затемняется, фейд уходит»)
// отменяет многоточие решения 12 WF103: хвост чата, который не влез, затухает маской, как строки
// списка слева у Claude; влез — без маски. Фон плашки угла (затухание под ней) — по-прежнему без фейда.
test("WF185: чат не влез — хвост затухает, как в Today; влез — без маски", () => {
  const loaded = stand();
  pass(loaded);
  const { chat } = parts(corner(loaded));
  const FADE = "linear-gradient(to right, #000 calc(100% - 24px), transparent 100%)";
  chat.scrollWidth = 320;
  chat.clientWidth = 90;
  pass(loaded);
  assert.equal(loaded.api.status().corner.fade, false, "fade плашки — всегда false");
  assert.equal(chat.style.getPropertyValue("mask-image"), FADE);
  assert.equal(chat.style.getPropertyValue("-webkit-mask-image"), FADE);
  assert.equal(chat.style.getPropertyValue("text-overflow"), "clip", "без многоточия");
  assert.equal(loaded.api.status().corner.tail.chat, true);
  assert.equal(corner(loaded).style.getPropertyValue("white-space"), "nowrap");
  chat.scrollWidth = 90;
  pass(loaded);
  assert.equal(chat.style.getPropertyValue("mask-image"), "", "влез — маска снята");
  assert.equal(loaded.api.status().corner.tail.chat, false);
});

test("WF103 решение 12: фон угла — сплошной цвет фона окна, без градиента", () => {
  const loaded = stand();
  loaded.document.body.computed = { backgroundColor: "rgb(5, 58, 43)" };
  pass(loaded);
  const node = corner(loaded);
  assert.equal(node.style.getPropertyValue("--myclaude-corner-bg"), "rgb(5, 58, 43)");
  assert.equal(node.style.getPropertyValue("background"), "var(--myclaude-corner-bg, transparent)");
  assert.doesNotMatch(node.style.getPropertyValue("background"), /gradient/);
  // Текст у самого верхнего края: плашка 20 px от top 0, кнопки окна не перекрыты.
  assert.equal(node.style.getPropertyValue("top"), "0px");
  assert.equal(node.style.getPropertyValue("height"), "20px");
  assert.equal(node.style.getPropertyValue("max-width"), "calc(100vw - 84px)");
});

test("#7911: главное окно — имя проекта как у чипа закреплённых (репозиторий строки)", () => {
  const loaded = stand({
    href: "https://claude.ai/epitaxy/local_abc", width: 852, origin: "Другое", chat: "🧪 Рик",
    row: { id: "local_abc", data: { cwd: "/Users/dev/Projects/Rick", repoInfo: { name: "Rick" } } },
  });
  pass(loaded);
  assert.equal(parts(corner(loaded)).project.textContent, "Rick");
  assert.equal(loaded.api.status().corner.chat, "🧪 Рик");
});

test("#7911: проекта нет (домашний экран) — угла нет", () => {
  const loaded = stand({ origin: null, chat: null });
  pass(loaded);
  assert.equal(corner(loaded).style.getPropertyValue("display"), "none");
  assert.equal(loaded.api.status().corner.on, false);
  assert.equal(loaded.document.documentElement.hasAttribute("data-myclaude-corner"), false);
});

test("#7911: угол наехал на название чата в шапке — оно прячется (cover)", () => {
  const loaded = stand();
  const node = corner(loaded);
  node.rect = { left: 84, top: 9, width: 198, height: 32 };
  pass(loaded);
  assert.equal(loaded.api.status().corner.cover, true);
  assert.equal(loaded.document.documentElement.getAttribute("data-myclaude-corner"), "cover");
  node.rect = { left: 160, top: 9, width: 122, height: 32 };
  pass(loaded);
  assert.equal(loaded.api.status().corner.cover, false);
});

test("#7911: правила таблицы — дубль имени в шапке прозрачен, по нажатиям жив", () => {
  const loaded = stand();
  const css = loaded.dom.sheets();
  assert.match(css, /html\[data-myclaude-corner\] \.epitaxy-titlebar \.group\\\/lead \[data-testid="epitaxy-origin-label"\]/);
  assert.match(css, /html\[data-myclaude-corner="cover"\] \.epitaxy-titlebar \.group\\\/lead span:has\(> \[data-pane-title\]\)/);
});

test("#7913: главное окно в узком виде — шапка сжата, узел жив; попап — как был", () => {
  const main = stand({ href: "https://claude.ai/epitaxy/local_abc", width: 852, chat: "🧪 Рик" });
  pass(main);
  assert.equal(main.parts.panel.hasAttribute("data-myclaude-headless"), true);
  assert.ok(main.parts.titlebar.isConnected, "узел шапки на месте");
  assert.deepEqual(plain(main.api.status().head), { main: true, headless: true, drag: true, titleSide: null, titleShift: null, titleEnd: null, titleFade: false });
  assert.equal(main.dom.query(DRAG).style.getPropertyValue("display"), "block", "полоса для тяги под кнопками окна");
  assert.equal(main.dom.query(DRAG).style.getPropertyValue("-webkit-app-region"), "drag");
  assert.equal(main.parts.tail.hasAttribute("data-myclaude-corner-fade"), true, "текст под кнопками окна затухает");
  // Правило: высота ноль и невидимость — не display:none (волокно чата и замеры держатся на узле).
  const rule = main.dom.sheets().split("}").find(chunk => chunk.includes("[data-myclaude-headless] .epitaxy-titlebar"));
  assert.ok(rule, "правила шапки нет");
  assert.match(rule, /height: 0 !important/);
  assert.match(rule, /visibility: hidden !important/);
  assert.doesNotMatch(rule, /display:\s*none/);
  const popup = stand();
  pass(popup);
  assert.equal(popup.parts.panel.hasAttribute("data-myclaude-headless"), false);
  assert.deepEqual(plain(popup.api.status().head), { main: false, headless: false, drag: false, titleSide: null, titleShift: null, titleEnd: null, titleFade: false });
  assert.equal(popup.parts.tail.hasAttribute("data-myclaude-corner-fade"), false);
});

test("#7913: главное окно в широком виде — шапка во второй колонке, не сжата", () => {
  const loaded = stand({ href: "https://claude.ai/epitaxy/local_abc", width: 852, chat: "🧪 Рик", wide: true });
  pass(loaded);
  assert.equal(loaded.parts.panel.hasAttribute("data-myclaude-headless"), false);
  assert.equal(loaded.parts.panel.getAttribute("data-myclaude-title"), null, "шапку влево не переносим");
  assert.equal(loaded.api.status().head.drag, true);
  // Список чатов открыт — панель правее кнопок окна: ни полосы, ни затухания.
  loaded.parts.panel.rect = { ...loaded.parts.panel.rect, left: 200 };
  loaded.parts.tail.rect = { ...loaded.parts.tail.rect, left: 200 };
  pass(loaded);
  assert.equal(loaded.api.status().head.drag, false);
  assert.equal(loaded.dom.query(DRAG).style.getPropertyValue("display"), "none");
  assert.equal(loaded.parts.tail.hasAttribute("data-myclaude-corner-fade"), false);
});

test("dispose уносит угол, полосу и метки", () => {
  const loaded = stand({ href: "https://claude.ai/epitaxy/local_abc", width: 852, chat: "🧪 Рик" });
  pass(loaded);
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`${CORNER},${DRAG}`).length, 0);
  assert.equal(loaded.document.documentElement.hasAttribute("data-myclaude-corner"), false);
  assert.equal(loaded.parts.panel.hasAttribute("data-myclaude-headless"), false);
});

// ---- часики кеша в углу (#7943, WF102 Б5) ------------------------------------
// «В каждом чате я хотел бы в одном и том же месте, предсказуемо видеть время».
// Время — updatedAtMs сессии строки своего чата в списке слева (как у
// закреплённых); попап берёт строку из списка главного окна (window.opener).
const T0 = 1_790_000_000_000;
const MIN = 60_000;
const RICK = { id: "local_abc", updatedAtMs: T0, data: { cwd: "/Users/dev/Projects/Rick", repoInfo: { name: "Rick" } } };
const mainStand = (row = RICK) => stand({ href: "https://claude.ai/epitaxy/local_abc", width: 852, chat: "🧪 Рик", row });

test("#7943/#9144: главное окно — часики «60:00 → 0:00»; 10 минут — жёлтые, 5 — красные, жирные и тикают; потом «вышло»", () => {
  const loaded = mainStand();
  pass(loaded);
  const { clock, project } = parts(corner(loaded));
  const at = t => {
    loaded.inner.markCornerClock(t);
    const status = loaded.api.status().corner;
    return [clock.textContent, clock.style.getPropertyValue("color"), clock.style.getPropertyValue("font-weight"), status.stage, status.late, clock.getAttribute("data-myclaude-clock")];
  };
  assert.deepEqual(at(T0), ["60:00", "inherit", "400", "calm", false, "calm"]);
  assert.equal(clock.style.getPropertyValue("opacity"), "0.5", "в покое — приглушённо");
  assert.deepEqual(at(T0 + 25 * MIN + 7000), ["34:53", "inherit", "400", "calm", false, "calm"]);
  assert.deepEqual(at(T0 + 50 * MIN - 1000), ["10:01", "inherit", "400", "calm", false, "calm"], "больше 10 минут — тихо");
  assert.deepEqual(at(T0 + 50 * MIN), ["10:00", "#f0c049", "500", "warn", false, "warn"], "ровно 10 минут — жёлтым");
  assert.equal(clock.style.getPropertyValue("opacity"), "1");
  assert.deepEqual(at(T0 + 55 * MIN - 1000), ["5:01", "#f0c049", "500", "warn", false, "warn"]);
  assert.deepEqual(at(T0 + 55 * MIN), ["5:00", "#ff6b6b", "700", "alarm", true, "alarm"], "5 минут — красным и жирно");
  assert.deepEqual(at(T0 + 60 * MIN - 1000), ["0:01", "#ff6b6b", "700", "alarm", true, "alarm"]);
  assert.deepEqual(at(T0 + 3 * 60 * MIN), ["вышло", "#ff6b6b", "700", "out", true, "out"], "после нуля — «вышло» красным");
  assert.equal(clock.style.getPropertyValue("opacity"), "1");
  assert.equal(clock.style.getPropertyValue("display"), "inline-block");
  assert.equal(loaded.api.status().corner.clock, "вышло");
  // Тикает только «красная» ступень, пульс раз в секунду; «Уменьшить движение» — без пульса.
  const css = [...loaded.inner.RULES].join("\n");
  assert.match(css, /#myclaude-corner>\[data-myclaude-clock="alarm"\]\{animation:myclaude-clock-tick 1s ease-in-out infinite\}/);
  assert.match(css, /@keyframes myclaude-clock-tick\{0%,100%\{opacity:1\}50%\{opacity:\.45\}\}/);
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)\{#myclaude-corner>\[data-myclaude-clock\]\{animation:none !important\}\}/);
  assert.doesNotMatch(css, /\[data-myclaude-clock="(warn|out|calm)"\]\{animation/);
  // #9106: шрифт окна, не моноширинный, цифры одной ширины, тихие, без своей ширины.
  assert.equal(clock.style.getPropertyValue("font-family"), "");
  assert.equal(clock.style.getPropertyValue("font-variant-numeric"), "tabular-nums");
  assert.equal(clock.style.getPropertyValue("width"), "");
  loaded.inner.markCornerClock(T0);
  assert.equal(clock.style.getPropertyValue("opacity"), "0.5");
  assert.equal(clock.style.getPropertyValue("font-weight"), "400");
  assert.equal(project.textContent, "Rick");
});

test("#7943: попап — время своей строки из списка главного окна (opener)", () => {
  const main = mainStand({ ...RICK, id: "local_pop", updatedAtMs: T0 - 5 * MIN });
  const popup = stand({ fiberId: "local_pop", opener: { document: main.document } });
  assert.equal(popup.error, null, String(popup.error?.stack ?? popup.error));
  pass(popup);
  popup.inner.markCornerClock(T0);
  const { clock, project } = parts(corner(popup));
  assert.equal(clock.textContent, "55:00");
  assert.equal(popup.api.status().corner.clock, "55:00");
  // 282 pt: имя проекта целиком — не сжимаются ни оно, ни часики, сжимается только чат.
  assert.equal(project.textContent, "PimpMyClaude");
  assert.equal(project.style.getPropertyValue("flex"), "0 0 auto");
  assert.equal(clock.style.getPropertyValue("flex"), "0 0 auto");
  assert.equal(parts(corner(popup)).chat.style.getPropertyValue("flex"), "0 1 auto");
  // #9106: и в прежнем углу часики — сразу за именем проекта, мелко; чат после них.
  assert.equal(clock.style.getPropertyValue("order"), "1");
  assert.equal(parts(corner(popup)).chat.style.getPropertyValue("order"), "2");
  assert.equal(clock.style.getPropertyValue("font-size"), "10px");
});

test("#7943: источника нет — часиков нет (нет строки, нет времени, нет opener)", () => {
  const cases = [
    stand(),
    stand({ fiberId: "local_pop" }),
    stand({ fiberId: "local_pop", opener: { document: mainStand({ ...RICK, id: "local_other" }).document } }),
    mainStand({ ...RICK, updatedAtMs: undefined }),
  ];
  for (const loaded of cases) {
    pass(loaded);
    loaded.inner.markCornerClock(T0);
    assert.equal(parts(corner(loaded)).clock.style.getPropertyValue("display"), "none");
    assert.equal(loaded.api.status().corner.clock, null);
  }
});

test("#7943: в DOM пишется только смена значения", () => {
  const loaded = mainStand();
  pass(loaded);
  const { clock } = parts(corner(loaded));
  loaded.inner.markCornerClock(T0 + 1000);
  assert.equal(clock.textContent, "59:59");
  const kids = clock.childNodes;
  const writes = [];
  const original = clock.style.setProperty.bind(clock.style);
  clock.style.setProperty = (...args) => { writes.push(args); return original(...args); };
  loaded.inner.markCornerClock(T0 + 1000);
  loaded.inner.markCornerClock(T0 + 1400);
  assert.equal(clock.childNodes, kids, "та же секунда — текст не переписан");
  assert.deepEqual(writes, [], "та же секунда — стили не тронуты");
  loaded.inner.markCornerClock(T0 + 50 * MIN + 1000);
  assert.notEqual(clock.childNodes, kids);
  assert.deepEqual(writes.map(([name, value]) => `${name}=${value}`), ["color=#f0c049", "opacity=1", "font-weight=500"]);
});

test("#7943: тикают сами раз в секунду; dispose уносит часики и тик", () => {
  const loaded = mainStand({ ...RICK, updatedAtMs: Date.now() - 5 * MIN });
  pass(loaded);
  const { clock } = parts(corner(loaded));
  loaded.dom.fireKind("interval");
  assert.match(clock.textContent, /^5[45]:\d\d$/);
  loaded.api.dispose();
  assert.equal(clock.isConnected, false);
  assert.equal(loaded.dom.count("interval"), 0);
});

// ---- заголовок слева: над New и у Remote Control (#9054, WF128 Г1) -----------
// Слово Элвиса 08.10: «в правом верхнем углу жутко выглядит… слева, вот где New,
// над New… название проекта, там название чата и таймер… если эта штука
// свёрнута… там, где Remote Control».
const SIDEBAR = { list: { left: 0, top: 46, width: 190, height: 674 }, next: { left: 8, top: 96, width: 174, height: 26 } };

test("#9054/#9147: главное окно, список открыт — заголовок над New, две строки, угла справа нет", () => {
  const loaded = stand({ href: "https://claude.ai/epitaxy/local_abc", width: 852, chat: "🧪 Рик", panelLeft: 199, sidebar: SIDEBAR,
    gutter: { left: 552, top: 12, width: 24, height: 24 } });
  pass(loaded);
  const node = corner(loaded);
  const { project, chat, clock } = parts(node);
  assert.equal(loaded.api.status().corner.mode, "side");
  assert.equal(loaded.document.documentElement.getAttribute("data-myclaude-corner"), "side");
  // Значка у New в стенде нет — линия по полю строки Claude (+10); переключателя нет — сразу под строкой окна.
  // WF190: правый край текста — на 4 левее края строк списка (190 − 12), там встаёт подсветка имени.
  assert.deepEqual(["left", "top", "width", "height", "right"].map(name => node.style.getPropertyValue(name)), ["18px", "50px", "160px", "44px", "auto"]);
  // #9106: сетка — «Проект 59:49» строкой, чат ниже во всю ширину. Колонка имени
  // сжимается (многоточие), колонка часиков — нет: часики не уходят на свою строку
  // и не наезжают на имя.
  assert.equal(node.style.getPropertyValue("display"), "grid", "проект и часики — строка, чат — ниже");
  // WF185: колонка часиков — 1fr, но не уже их текста; часики — у левого края своей колонки, у имени.
  assert.equal(node.style.getPropertyValue("grid-template-columns"), "minmax(0, max-content) minmax(max-content, 1fr)");
  assert.equal(clock.style.getPropertyValue("justify-self"), "start");
  assert.equal(node.style.getPropertyValue("align-items"), "baseline", "часики на одной линии с именем");
  assert.equal(node.style.getPropertyValue("justify-content"), "start", "часики у имени, а не у правого края");
  // #9147: проект крупно 20/600, чат 14/400 приглушённо, часики 10 px.
  assert.match(node.style.getPropertyValue("font"), /^20px/);
  assert.equal(project.style.getPropertyValue("line-height"), "1.25");
  assert.equal(chat.style.getPropertyValue("font-size"), "14px");
  assert.equal(chat.style.getPropertyValue("font-weight"), "400");
  assert.equal(chat.style.getPropertyValue("grid-column"), "1 / -1");
  assert.equal(chat.style.getPropertyValue("order"), "3");
  assert.equal(clock.style.getPropertyValue("order"), "1", "часики сразу за именем проекта");
  assert.equal(project.style.getPropertyValue("flex"), "");
  assert.equal(project.style.getPropertyValue("min-width"), "0");
  assert.equal(project.style.getPropertyValue("text-overflow"), "clip", "длинное имя режется раньше часиков — затуханием (WF185)");
  // WF185: чат в размер колонок не вкладывается — иначе длинный чат сжимал колонку проекта в ноль.
  assert.equal(chat.style.getPropertyValue("contain"), "inline-size");
  assert.equal(clock.style.getPropertyValue("flex"), "0 0 auto");
  assert.equal(clock.style.getPropertyValue("white-space"), "nowrap");
  assert.equal(clock.style.getPropertyValue("font-size"), "10px", "#9144: ещё мельче — 10 px");
  assert.ok(Number.parseFloat(clock.style.getPropertyValue("font-size")) < Number.parseFloat(chat.style.getPropertyValue("font-size")));
  assert.equal(node.style.getPropertyValue("pointer-events"), "none");
  // Место над New — отступом списка (переменная корня), узлов в React-дерево не вставляем.
  assert.match(loaded.dom.sheets(), /html\[data-myclaude-corner="side"\] \[data-testid="sidebar"\] \{\s*padding-top: var\(--myclaude-side-space, 96px\) !important;/);
  assert.equal(loaded.document.documentElement.style.getPropertyValue("--myclaude-side-space"), "56px", "4 + 44 + 8 — без переключателя");
  // Список свернулся (панель снова у левого края) — к Remote Control, строкой шапки.
  loaded.parts.panel.rect = { ...loaded.parts.panel.rect, left: 9 };
  loaded.parts.titlebar.rect = { left: 548, top: 8, width: 301, height: 32 };
  pass(loaded);
  assert.equal(loaded.api.status().corner.mode, "row");
  assert.deepEqual(["left", "width"].map(name => node.style.getPropertyValue(name)), ["580px", "261px"]);
  assert.equal(node.style.getPropertyValue("display"), "grid");
  assert.equal(clock.style.getPropertyValue("font-size"), "10px");
  assert.equal(loaded.document.documentElement.style.getPropertyValue("--myclaude-side-space"), "", "не над New — переменных нет");
});

// ---- WF155→WF166: строка окна и левая колонка (#9146, #9147, #9164) ---------
// Слово Элвиса 09.10 00:05 (#9164): «иконки Chat и Code разместить справа рядом со всеми
// остальными иконками, где Hide Sidebar, Back и вперёд, сделать их такими же маленькими… всегда
// маленькие и в разделе "Чат", и в Code… не надо под ними делать эти фоны тёмные… там, где значок
// монитора, тоже никакой фон не нужен». Геометрия — замер живого окна (CSS px, режим Code, 09.10):
// строка окна 46, кнопки 24 по 84/108/132, переключатель Claude 70×28 у правого края панели
// (ml-auto), New 8/96, его кружок «+» с 18.
const LIVE = {
  root: true,
  aside: { left: 0, top: 0, width: 238, height: 536 },
  titlebar: { left: 0, top: 0, width: 238, height: 46 },
  buttons: [
    ["Hide sidebar", { left: 84, top: 12, width: 24, height: 24 }],
    ["Back", { left: 108, top: 12, width: 24, height: 24 }],
    ["Forward", { left: 132, top: 12, width: 24, height: 24 }],
  ],
  mode: { left: 160, top: 12, width: 48, height: 24 },
  list: { left: 0, top: 46, width: 238, height: 490 },
  next: { left: 8, top: 96, width: 222, height: 26 },
  circle: { left: 18, top: 101, width: 16, height: 16 },
};
const live = (options = {}) => stand({ href: "https://claude.ai/epitaxy/local_abc", width: 974, chat: "Rick чат Элвиса", panelLeft: 238, sidebar: LIVE, ...options });
const meet = (a, b) => a.left < b.left + b.width && b.left < a.left + a.width && a.top < b.top + b.height && b.top < a.top + a.height;
const px = (node, name) => Number.parseFloat(node.style.getPropertyValue(name));
// Правила листа страницы (RULES) и layoutCss вместе.
const allCss = loaded => `${loaded.dom.sheets()}\n${[...loaded.inner.RULES].join("\n")}`;
const MODE = '\\.dframe-root \\[role="radiogroup"\\]\\[aria-label="Mode"\\]';
const rule = (css, selector) => css.match(new RegExp(`${selector}\\{([^}]*)\\}`))?.[1];

test("WF166: переключатель Claude/Code — в строке окна сразу за «вперёд», на высоте кнопок; строки над названием нет", () => {
  const loaded = live();
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  pass(loaded);
  const node = corner(loaded);
  const root = loaded.document.documentElement.style;
  assert.equal(loaded.api.status().corner.mode, "side");
  // Место — от «вперёд» (правый край 156) + зазор групп 4; по высоте — по центру кнопок (12).
  assert.equal(root.getPropertyValue("--myclaude-switch-left"), "160px");
  assert.equal(root.getPropertyValue("--myclaude-switch-top"), "12px");
  assert.deepEqual(plain(loaded.api.status().corner.switch), { left: 160, top: 12, size: 24 });
  const css = loaded.dom.sheets();
  assert.match(css, /\.dframe-root:not\(\[data-collapsed\]\) aside\.dframe-sidebar > \.df-titlebar > :has\(\[role="radiogroup"\]\[aria-label="Mode"\]\) \{\s*position: absolute !important;\s*left: var\(--myclaude-switch-left, 160px\) !important;\s*top: var\(--myclaude-switch-top, 12px\) !important;/);
  assert.doesNotMatch(css, /html\[data-myclaude-corner="side"\] \.dframe-root:not\(\[data-collapsed\]\) aside/, "правила строки над названием нет");
  // Две кнопки по 24 вплотную: одна высота и шаг с кнопками окна.
  const flip = { left: 160, top: 12, width: 2 * 24, height: 24 };
  const buttons = LIVE.buttons.map(([, rect]) => rect);
  for (const rect of buttons) { assert.equal(rect.height, flip.height); assert.equal(rect.top, flip.top); }
  // Название проекта — сразу под строкой окна (4 от верха списка), отступ над New без строки переключателя.
  const text = { left: px(node, "left"), top: px(node, "top"), width: px(node, "width"), height: px(node, "height") };
  const space = px({ style: root }, "--myclaude-side-space");
  assert.equal(space, 4 + 44 + 8);
  assert.equal(text.top, LIVE.list.top + 4);
  const buttonsBottom = Math.max(...buttons.map(rect => rect.top + rect.height));
  assert.ok(text.top - buttonsBottom >= 12, "название ниже кнопок окна");
  // Одна вертикаль угла — кружок «+» у New плюс 2 (ab1192e).
  assert.equal(text.left, LIVE.circle.left + 2);
  assert.equal(loaded.api.status().corner.line, 20);
  // Ни одна пара не пересекается: кнопки окна, переключатель, текст угла; переключатель — внутри панели.
  const boxes = [...LIVE.buttons, ["switch", flip], ["text", text]];
  for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
    assert.equal(meet(boxes[i][1], boxes[j][1]), false, `${boxes[i][0]} × ${boxes[j][0]}`);
  }
  assert.ok(flip.left + flip.width <= LIVE.aside.width - 8);
  // dispose — переменные корня уходят.
  loaded.api.dispose();
  assert.equal(root.getPropertyValue("--myclaude-switch-left"), "");
  assert.equal(root.getPropertyValue("--myclaude-switch-top"), "");
  assert.equal(root.getPropertyValue("--myclaude-side-space"), "");
});

test("WF166: режим Chat — место и размер прежние (от «вперёд» и в px, а не по плотности Claude)", () => {
  const loaded = live();
  pass(loaded);
  const before = plain(loaded.api.status().corner.switch);
  // Chat: Claude ставит переключатель крупнее и в другое место строки — наше место от «вперёд» то же.
  const frame = loaded.document.querySelector(".dframe-root");
  frame.setAttribute("data-frame-mode", "chat");
  loaded.document.querySelector('[role="radiogroup"]').rect = { left: 150, top: 8, width: 76, height: 36 };
  pass(loaded);
  assert.deepEqual(plain(loaded.api.status().corner.switch), before);
  // Размеры — в px с !important, без rem, --cds-h-control и плотности: один вид в обоих режимах.
  const css = allCss(loaded);
  const group = rule(css, MODE);
  const radio = rule(css, `${MODE} \\[role="radio"\\]`);
  const icon = rule(css, `${MODE} \\[data-cds="Icon"\\]`);
  assert.match(group, /height:24px !important/);
  assert.match(radio, /width:24px !important;height:24px !important/);
  assert.match(icon, /font-size:16px !important;font-weight:533\.3 !important/);
  for (const body of [group, radio, icon]) {
    assert.doesNotMatch(body, /rem|--cds-h-control|data-frame-mode/);
  }
  assert.doesNotMatch(css, /data-frame-mode="(chat|code)"\][^{]*\[aria-label="Mode"\]/, "правил по режиму нет");
});

test("WF166: список свёрнут — переключатель у Claude (переменных нет, место только у пристыкованной)", () => {
  const loaded = live();
  pass(loaded);
  loaded.document.querySelector(".dframe-root").setAttribute("data-collapsed", "");
  loaded.parts.panel.rect = { ...loaded.parts.panel.rect, left: 9 };
  pass(loaded);
  const root = loaded.document.documentElement.style;
  assert.equal(root.getPropertyValue("--myclaude-switch-left"), "");
  assert.equal(root.getPropertyValue("--myclaude-switch-top"), "");
  assert.equal(loaded.api.status().corner.switch, null);
});

test("WF166: плашек нет — кнопки окна без своего фона, переключатель без дорожки и бегунка, выбранная — тонкая подложка, не белым (WF182)", () => {
  const css = allCss(live());
  assert.doesNotMatch(css, /--myclaude-chrome-plate/);
  assert.doesNotMatch(css, /\.df-chrome-btn:is\(\[aria-label="Hide sidebar"\]/, "своих правил у кнопок окна нет — только наведение Claude");
  const group = rule(css, MODE);
  assert.match(group, /background:transparent !important/);
  assert.match(group, /--cds-segmented-control-track:transparent/);
  assert.match(group, /backdrop-filter:none !important/);
  assert.match(rule(css, `${MODE}>\\[aria-hidden="true"\\]`), /display:none !important/, "бегунок спрятан");
  assert.match(rule(css, `${MODE} \\[role="radio"\\]`), /background:transparent !important;color:var\(--cds-text-secondary\) !important/);
  assert.match(rule(css, `${MODE} \\[role="radio"\\]:is\\(\\[data-checked\\],:hover\\)`), /^background:color-mix\(in oklab, var\(--cds-text-primary, currentColor\) 6%, transparent\) !important;color:color-mix\(in oklab, var\(--cds-text-secondary, currentColor\) 75%, var\(--cds-text-primary, currentColor\)\) !important$/);
});

test("WF166: значок Remote Control у названия — без тёмной заливки, цвета текста; наведение Claude", () => {
  const css = allCss(live());
  const gutter = '\\.epitaxy-titlebar \\[data-testid="epitaxy-origin-gutter"\\]';
  assert.match(rule(css, gutter), /^color:var\(--cds-text-primary\) !important$/);
  assert.match(rule(css, `${gutter} \\[data-cds-part="paint"\\]`), /^background-color:transparent !important$/);
  assert.match(rule(css, `${gutter}:hover \\[data-cds-part="paint"\\]`), /--cds-fill-ghost-hover/);
});

test("#9146: наложение — своя ширина панели только у пристыкованной; у свёрнутой выезжающий список и его переключатель меряет Claude", () => {
  const css = allCss(live());
  assert.match(css, /\.dframe-root\[data-myclaude-left\]:not\(\[data-collapsed\]\)\{--df-sidebar-width:var\(--myclaude-left\) !important\}/);
  assert.doesNotMatch(css, /\.dframe-root\[data-myclaude-left\]\{--df-sidebar-width/);
});

test("WF166: пол узкой панели — правый край переключателя за «вперёд» + поле; узкая 190 раздвигается до пола", () => {
  const loaded = live({ storage: { local: { "myclaude-left-side-v1": "190" } } });
  const aside = loaded.document.querySelector("aside.dframe-sidebar");
  // 160 + 48 + 8 — переключатель не свешивается за панель на ленту.
  assert.equal(loaded.inner.leftFloor(aside), 216);
  // Переключатель не в строке окна (например, Claude убрал его ниже) — пол только по кнопкам: 156 + 8.
  loaded.document.querySelector('[role="radiogroup"]').rect = { left: 18, top: 50, width: 70, height: 28 };
  assert.equal(loaded.inner.leftFloor(aside), 164);
  loaded.document.querySelector('[role="radiogroup"]').rect = LIVE.mode;
  // Своя ширина 190 (до WF166 переключатель жил над названием) — проход раздвигает до пола и запоминает.
  pass(loaded);
  const frame = loaded.document.querySelector(".dframe-root");
  assert.equal(frame.style.getPropertyValue("--myclaude-left"), "216px");
  assert.equal(loaded.win.localStorage.getItem("myclaude-left-side-v1"), "216");
});

test("#9054: список свёрнут или попап — строка шапки правее Remote Control, название под ней прозрачно", () => {
  const loaded = stand({ width: 400, gutter: { left: 77, top: 9, width: 24, height: 24 } });
  loaded.parts.titlebar.rect = { left: 77, top: 9, width: 320, height: 32 };
  pass(loaded);
  const node = corner(loaded);
  assert.equal(loaded.api.status().corner.mode, "row");
  assert.equal(loaded.document.documentElement.getAttribute("data-myclaude-corner"), "row");
  // От Remote Control +4 до края шапки −8; высота — шапки.
  assert.deepEqual(["left", "top", "width", "height"].map(name => node.style.getPropertyValue(name)), ["105px", "9px", "284px", "32px"]);
  assert.match(node.style.getPropertyValue("font"), /^13px/);
  assert.equal(node.children[1].children[0].style.getPropertyValue("display"), "none", "точки между проектом и чатом нет");
  const css = loaded.dom.sheets();
  assert.match(css, /html\[data-myclaude-corner="row"\] \.epitaxy-titlebar \.group\\\/lead span:has\(> \[data-pane-title\]\)/);
  // Кнопки попапа справа прячутся только под прежним углом.
  assert.match(css, /html:is\(\[data-myclaude-corner="on"\], \[data-myclaude-corner="cover"\]\) \.epitaxy-chat-panel/);
  // Строка узкая (попап 282) — прежний угол, с прежним видом.
  loaded.parts.titlebar.rect = { left: 77, top: 9, width: 158, height: 32 };
  pass(loaded);
  assert.equal(loaded.api.status().corner.mode, "corner");
  assert.deepEqual(["left", "top", "width", "height", "font"].map(name => node.style.getPropertyValue(name)),
    ["auto", "0px", "auto", "20px", "11px/1 -apple-system, system-ui, sans-serif"]);
  // Прежний угол — флекс в строку, следы сетки сняты.
  assert.equal(node.style.getPropertyValue("display"), "flex");
  assert.equal(node.style.getPropertyValue("grid-template-columns"), "");
  assert.equal(node.children[1].style.getPropertyValue("grid-column"), "");
  assert.equal(node.style.getPropertyValue("-webkit-backdrop-filter"), "blur(12px)", "под углом размытие, а не голый фон");
});

test("#9055: кнопка меню чата растянута под названием и при открытом меню (сосед «~», не «+»)", () => {
  const css = stand().dom.sheets();
  assert.match(css, /span:has\(> \[data-pane-title\]\) ~ button \{\s*position: absolute !important;\s*inset: 0 !important;/);
  assert.match(css, /span:has\(> \[data-pane-title\]\):has\(~ button\) \{/);
  assert.doesNotMatch(css, /span:has\(> \[data-pane-title\]\) \+ button \{/);
});

test("WF176 (#9182): рейка левой панели ведёт ширину во всём ходе — за 242 без прыжка к Claude, до aria-valuemax; ширина помнится", () => {
  const loaded = live({ storage: { local: { "myclaude-left-side-v1": "216" } } });
  pass(loaded);
  const frame = loaded.document.querySelector(".dframe-root");
  const aside = loaded.document.querySelector("aside.dframe-sidebar");
  aside.rect = { ...aside.rect, width: 216 };
  const handle = aside.add("div", { attrs: { "data-cds": "ResizeHandle", "aria-label": "Resize sidebar", "aria-valuemin": "242", "aria-valuemax": "420", "aria-valuenow": "242" }, rect: { left: 210, top: 0, width: 12, height: 536 } });
  const knob = handle.add("div", { rect: { left: 214, top: 244, width: 3, height: 48 } });
  const at = (type, x) => loaded.document.dispatchEvent({ type, button: 0, clientX: x, target: knob, pointerId: 1 });
  at("pointerdown", 216);
  at("pointermove", 300);
  assert.equal(frame.style.getPropertyValue("--myclaude-left"), "300px", "за минимумом Claude ширина своя, а не его 242 + сдвиг");
  assert.ok(frame.hasAttribute("data-myclaude-left"));
  at("pointermove", 900);
  assert.equal(frame.style.getPropertyValue("--myclaude-left"), "420px", "не шире aria-valuemax");
  at("pointermove", 100);
  assert.equal(frame.style.getPropertyValue("--myclaude-left"), "216px", "не ýже пола (кнопки и переключатель)");
  at("pointermove", 330);
  at("pointerup", 330);
  assert.equal(loaded.win.localStorage.getItem("myclaude-left-side-v1"), "330", "отпустили — ширина в хранилище");
  // Перерисовка корня (React) не сбрасывает ширину.
  frame.removeAttribute("data-myclaude-left");
  frame.style.removeProperty("--myclaude-left");
  pass(loaded);
  assert.equal(frame.style.getPropertyValue("--myclaude-left"), "330px");
  // Двойной клик по рейке — ширину снова ведёт Claude.
  loaded.document.dispatchEvent({ type: "dblclick", target: knob });
  assert.equal(frame.hasAttribute("data-myclaude-left"), false);
  assert.equal(loaded.win.localStorage.getItem("myclaude-left-side-v1"), null);
});

// ---- WF185: имя папки проекта в углу над New не пропадает ни на одном пути ----------------------
// Слово Элвиса 09.10 03:20/03:35: «А где название проекта, папки? Там же было… Слева сверху название
// папки крупным должно быть». Живьём (probe 09.10 03:34): «Rick» в узле есть, но колонка проекта
// 0 px — длинный чат во всю строку сетки отдавал ширину колонке часиков. Класс чиним раскладкой
// (чат в размер колонок не вкладывается) и источником имени (у попапа без подписи — строка opener).
test("WF185: длинный чат над New — имя проекта в своей колонке, чат шириной сетки, хвост затухает", () => {
  const LONG = "Ночной режим Rick с бюджетом и ещё очень длинным хвостом";
  const loaded = stand({ href: "https://claude.ai/epitaxy/local_abc", width: 852, chat: LONG, panelLeft: 199, sidebar: SIDEBAR, row: RICK });
  pass(loaded);
  const node = corner(loaded);
  const { project, chat, clock } = parts(node);
  assert.equal(loaded.api.status().corner.mode, "side");
  assert.equal(project.textContent, "Rick", "имя папки проекта — из строки чата");
  assert.equal(loaded.api.status().corner.project, "Rick");
  // Колонки: имя — max-content (сжимается до 0 только когда места нет вовсе), часики — остальное.
  assert.equal(node.style.getPropertyValue("grid-template-columns"), "minmax(0, max-content) minmax(max-content, 1fr)");
  assert.equal(chat.style.getPropertyValue("contain"), "inline-size", "чат не распирает колонку часиков");
  assert.equal(chat.style.getPropertyValue("grid-column"), "1 / -1");
  assert.equal(clock.style.getPropertyValue("justify-self"), "start", "часики рядом с именем, а не у правого края");
  // WF190: над New чат переносится (до трёх строк) — по ширине не режется; не влез и в три строки —
  // хвост третьей затухает (маска по высоте); имя проекта влезло — без маски.
  chat.scrollWidth = 400; chat.clientWidth = 160;
  chat.scrollHeight = 76; chat.clientHeight = 57;
  project.scrollWidth = 40; project.clientWidth = 40;
  pass(loaded);
  assert.match(chat.style.getPropertyValue("mask-image"), /linear-gradient\(#000, #000\), linear-gradient\(to right/);
  assert.equal(project.style.getPropertyValue("mask-image"), "");
  assert.deepEqual(plain(loaded.api.status().corner.tail), { project: false, chat: true });
  // Прежний угол (узкое окно без списка) после этого — без сетки и без contain.
  const narrow = stand({ chat: LONG });
  pass(narrow);
  assert.equal(parts(corner(narrow)).chat.style.getPropertyValue("contain"), "");
});

test("WF185: попап без подписи проекта в шапке — имя папки из строки своего чата в главном окне", () => {
  const main = mainStand({ ...RICK, id: "local_pop" });
  const popup = stand({ fiberId: "local_pop", opener: { document: main.document }, origin: null });
  assert.equal(popup.error, null, String(popup.error?.stack ?? popup.error));
  pass(popup);
  assert.equal(popup.api.status().corner.on, true, "угол не пропал");
  assert.equal(parts(corner(popup)).project.textContent, "Rick");
  // Своя подпись у попапа есть — она сильнее (это его собственная плашка проекта).
  const own = stand({ fiberId: "local_pop", opener: { document: main.document } });
  pass(own);
  assert.equal(parts(corner(own)).project.textContent, "PimpMyClaude");
  // Ни подписи, ни строки — угла нет (имени взять неоткуда).
  const none = stand({ fiberId: "local_pop", origin: null });
  pass(none);
  assert.equal(none.api.status().corner.on, false);
});

// ---- WF190: имя чата над New — до трёх строк, кликом меню Claude; папка на всех путях ----------
// Слово Элвиса 09.10 03:50: «Разреши в две строки писать. Название чата можно и в три строки… должен
// быть перенос, чтобы не вылезать справа: портит принцип приближенности»; по нажатию на имя чата должно
// открываться то же самое меню, что при нажатии наверху (Open in, Rename, Fork…); «Где
// заголовок? Появился только после того, как я Rename сделал».
const SIDE_LONG = "Ночной режим Rick с бюджетом и ещё очень длинным хвостом названия";
const sideStand = (options = {}) => stand({ href: "https://claude.ai/epitaxy/local_abc", width: 852, chat: SIDE_LONG, panelLeft: 199, sidebar: SIDEBAR, row: RICK, ...options });

test("WF190: имя чата над New переносится по словам до трёх строк, угол и отступ списка растут; правый край — по строкам списка", () => {
  const loaded = sideStand();
  pass(loaded);
  const node = corner(loaded);
  const { chat } = parts(node);
  assert.equal(chat.style.getPropertyValue("white-space"), "normal", "перенос, а не одна строка");
  assert.equal(chat.style.getPropertyValue("overflow-wrap"), "break-word");
  assert.equal(chat.style.getPropertyValue("max-height"), "4.05em", "потолок — три строки по 1.35");
  assert.equal(chat.style.getPropertyValue("overflow"), "hidden");
  // Правая граница: список 0…190, строки до 190 − 8; текст угла — до 190 − 12, подсветка (−4 по бокам) — ровно до 182.
  assert.equal(px(node, "left") + px(node, "width"), 178);
  // Подсветка — в рамку подложки строки списка: 4 вправо до её края, 11 влево (поле строки Claude: 19 − 11 = 8).
  assert.equal(chat.style.getPropertyValue("margin"), "0 -4px 0 -11px");
  assert.equal(chat.style.getPropertyValue("padding"), "0 4px 0 11px");
  // Одна строка — прежние 44 и отступ 56.
  assert.equal(node.style.getPropertyValue("height"), "44px");
  assert.equal(loaded.api.status().corner.lines, 1);
  // Две строки (38 px текста) — угол 63, список ниже на строку.
  chat.scrollHeight = 38; chat.clientHeight = 38;
  pass(loaded);
  assert.equal(loaded.api.status().corner.lines, 2);
  assert.equal(node.style.getPropertyValue("height"), "63px");
  assert.equal(loaded.document.documentElement.style.getPropertyValue("--myclaude-side-space"), "75px");
  assert.equal(chat.style.getPropertyValue("mask-image"), "", "влезло в две — без затухания");
  // Три строки и больше — потолок 3, хвост третьей затухает (верхние строки целиком).
  chat.scrollHeight = 95; chat.clientHeight = 57;
  pass(loaded);
  assert.equal(loaded.api.status().corner.lines, 3);
  assert.equal(node.style.getPropertyValue("height"), "82px");
  assert.equal(loaded.document.documentElement.style.getPropertyValue("--myclaude-side-space"), "94px");
  assert.equal(chat.style.getPropertyValue("mask-size"), "100% calc(100% - 1.35em), 100% 1.35em");
  assert.equal(chat.style.getPropertyValue("-webkit-mask-repeat"), "no-repeat");
  assert.equal(loaded.api.status().corner.tail.chat, true);
  // Живой фон и обратно — тот же перенос и те же строки (вид угла от оформления не зависит).
  loaded.dom.command({ id: "wf190-live", action: "theme", at: "now", scope: "all", look: { aurora: true } });
  pass(loaded);
  assert.equal(chat.style.getPropertyValue("white-space"), "normal");
  assert.equal(loaded.api.status().corner.lines, 3);
  loaded.dom.command({ id: "wf190-classic", action: "theme", at: "now", scope: "all", look: null });
  pass(loaded);
  assert.equal(chat.style.getPropertyValue("white-space"), "normal");
  assert.equal(node.style.getPropertyValue("height"), "82px");
  // Список свернулся — строка шапки: одна строка, маски по высоте нет, мышь — родным кнопкам.
  loaded.parts.panel.rect = { ...loaded.parts.panel.rect, left: 9 };
  loaded.parts.titlebar.rect = { left: 548, top: 8, width: 301, height: 32 };
  loaded.parts.title.parentElement.parentElement.add("button", { attrs: { "data-testid": "epitaxy-origin-gutter" }, rect: { left: 552, top: 12, width: 24, height: 24 } });
  chat.scrollHeight = 0; chat.clientHeight = 0;
  pass(loaded);
  assert.equal(loaded.api.status().corner.mode, "row");
  assert.equal(chat.style.getPropertyValue("white-space"), "nowrap");
  assert.equal(chat.style.getPropertyValue("max-height"), "");
  assert.equal(chat.style.getPropertyValue("pointer-events"), "");
  assert.equal(chat.style.getPropertyValue("mask-size"), "");
  assert.equal(loaded.api.status().corner.lines, null);
  assert.equal(loaded.document.documentElement.style.getPropertyValue("--myclaude-side-space"), "");
});

test("WF190: нажатие на имя чата над New открывает родное меню названия (кнопка «More options for…»)", () => {
  // Подписи проекта в шапке нет — единственная кнопка за названием та, что открывает меню Claude.
  const loaded = sideStand({ origin: null });
  pass(loaded);
  const lead = loaded.parts.title.parentElement.parentElement;
  const menu = lead.add("button", { attrs: { "aria-label": `More options for ${SIDE_LONG}`, "aria-haspopup": "menu", "aria-expanded": "false" } });
  const got = [];
  for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) menu.addEventListener(type, event => got.push(event.type));
  const { chat } = parts(corner(loaded));
  assert.equal(chat.style.getPropertyValue("pointer-events"), "auto", "имя ловит мышь, остальной угол — нет");
  assert.equal(corner(loaded).style.getPropertyValue("pointer-events"), "none");
  assert.equal(chat.style.getPropertyValue("cursor"), "pointer");
  // Наведение — лёгкая подложка, ушла мышь — снята.
  chat.dispatchEvent({ type: "pointerenter" });
  assert.match(chat.style.getPropertyValue("background-color"), /color-mix\(in srgb, currentColor 10%, transparent\)/);
  chat.dispatchEvent({ type: "pointerleave" });
  assert.equal(chat.style.getPropertyValue("background-color"), "");
  // Нажатие — как мышью по родной кнопке: pointerdown … click.
  chat.dispatchEvent({ type: "pointerdown" });
  chat.dispatchEvent({ type: "click" });
  assert.deepEqual(got, ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]);
  assert.equal(loaded.api.status().corner.menu, "opened");
  // Меню уже было открыто — нажатие мимо его закрыло, второй раз не открываем.
  got.length = 0;
  menu.setAttribute("aria-expanded", "true");
  chat.dispatchEvent({ type: "pointerdown" });
  menu.setAttribute("aria-expanded", "false");
  chat.dispatchEvent({ type: "click" });
  assert.deepEqual(got, []);
  assert.equal(loaded.api.status().corner.menu, "closed");
  // Кнопки нет (шапка ещё не смонтирована) — ничего не жмём.
  menu.remove();
  chat.dispatchEvent({ type: "pointerdown" });
  chat.dispatchEvent({ type: "click" });
  assert.equal(loaded.api.status().corner.menu, "no-button");
});

test("WF190: папка в углу стоит на всех путях — старт, смена чата, новый чат, renew — без Rename", () => {
  const addRow = (loaded, id, name) => {
    const bar = loaded.dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
    const node = bar.add("div", { attrs: { "data-row-key": `code:${id}` } });
    node["__reactFiber$test"] = { memoizedProps: { session: { ref: { kind: "code", id }, updatedAtMs: T0, source: { kind: "code", data: { repoInfo: { name } } } } }, return: null };
    return bar;
  };
  const go = (loaded, id) => {
    loaded.win.location.pathname = `/epitaxy/${id}`;
    loaded.win.location.href = `https://claude.ai/epitaxy/${id}`;
  };
  // Старт: строка своего чата ещё не отрисована, подписи в шапке нет — угла нет; строка пришла — папка сразу.
  const loaded = sideStand({ origin: null, row: null });
  pass(loaded);
  assert.equal(loaded.api.status().corner.on, false);
  addRow(loaded, "local_abc", "Rick");
  pass(loaded);
  assert.equal(loaded.api.status().corner.project, "Rick", "старт: строка пришла позже — папка без Rename");
  assert.equal(parts(corner(loaded)).project.textContent, "Rick");
  // Смена чата в списке: другой адрес, своя строка — папка того чата, имя — новое.
  addRow(loaded, "local_def", "Dictator");
  go(loaded, "local_def");
  loaded.parts.title.textContent = "Диктатор";
  pass(loaded);
  assert.equal(loaded.api.status().corner.project, "Dictator");
  assert.equal(loaded.api.status().corner.chat, "Диктатор");
  // Новый чат (домашний экран, своего id нет и подписи нет) — угла нет, а не прошлая папка.
  go(loaded, "new");
  pass(loaded);
  assert.equal(loaded.api.status().corner.on, false);
  // Renew: свежий id, строки ещё нет — подпись шапки; строка пришла — папка из неё.
  go(loaded, "local_ghi");
  const label = loaded.parts.title.parentElement.parentElement.add("button").add("span", { attrs: { "data-testid": "epitaxy-origin-label" }, text: "Rick" });
  pass(loaded);
  assert.equal(loaded.api.status().corner.project, "Rick", "renew: до строки — подпись плашки проекта");
  label.textContent = "";
  addRow(loaded, "local_ghi", "RickNext");
  pass(loaded);
  assert.equal(loaded.api.status().corner.project, "RickNext");
});

// ---- WF197: имя проекта над New — родные меню проекта (регресс WF185) ------------------------------
// WF185 сняла невидимую плашку проекта в шапке колонки, а с ней — меню ⋮ проекта (Terminal / Changes /
// Browser, ⋮ привязана к плашке, #7334) и меню самой плашки (Show in Finder / Change folder). С WF197 их
// открывает имя проекта в углу: левый клик — ⋮, правый — плашка; нажатием родных кнопок, плашка на время
// меню стоит невидимой на имени, закрылось — снова снята.
test("WF197: клик по имени проекта над New — родная ⋮ проекта, правый клик — меню плашки; закрылось — плашка снята", () => {
  const loaded = sideStand();
  pass(loaded);
  const pill = loaded.parts.label.parentElement;
  const lead = pill.parentElement;
  // Правая группа шапки: значки и ⋮ последней (как у Claude: Terminal / Changes / Browser в ней).
  const end = loaded.parts.titlebar.add("div", { class: "epitaxy-titlebar-end" });
  end.add("button", { attrs: { "aria-label": "Terminal" } });
  const dots = end.add("button", { attrs: { "aria-label": "View options", "aria-haspopup": "menu", "aria-expanded": "false" } });
  pill.setAttribute("aria-haspopup", "menu");
  pill.setAttribute("aria-expanded", "false");
  const got = { dots: [], pill: [] };
  for (const type of ["pointerdown", "click"]) {
    dots.addEventListener(type, event => got.dots.push(event.type));
    pill.addEventListener(type, event => got.pill.push(event.type));
  }
  const { project, chat } = parts(corner(loaded));
  assert.equal(project.style.getPropertyValue("pointer-events"), "auto", "имя проекта ловит мышь");
  assert.equal(project.style.getPropertyValue("cursor"), "pointer");
  project.dispatchEvent({ type: "pointerenter" });
  assert.match(project.style.getPropertyValue("background-color"), /color-mix/);
  project.dispatchEvent({ type: "pointerleave" });
  assert.equal(project.style.getPropertyValue("background-color"), "");
  const root = loaded.document.documentElement;
  project.dispatchEvent({ type: "click" });
  assert.deepEqual(got.dots, ["pointerdown", "click"], "левый клик — родная ⋮ проекта");
  assert.deepEqual(got.pill, []);
  assert.equal(loaded.api.status().corner.originMenu, "project");
  assert.ok(root.hasAttribute("data-myclaude-origin-open"), "плашка на время меню — на имени в углу");
  assert.match(root.style.getPropertyValue("--myclaude-origin-x"), /^-?\d+px$/);
  // Меню открылось (Claude ставит aria-expanded) — плашка на месте; закрылось — снята, переменных нет.
  dots.setAttribute("aria-expanded", "true");
  loaded.dom.fireKind("interval");
  assert.ok(root.hasAttribute("data-myclaude-origin-open"), "меню открыто — плашка стоит");
  dots.setAttribute("aria-expanded", "false");
  loaded.dom.fireKind("interval");
  assert.ok(!root.hasAttribute("data-myclaude-origin-open"), "меню закрылось — плашка снята");
  assert.equal(root.style.getPropertyValue("--myclaude-origin-x"), "");
  // Правый клик — меню плашки (Show in Finder / Change folder), родное контекстное меню не нужно.
  const passed = project.dispatchEvent({ type: "contextmenu", cancelable: true });
  assert.deepEqual(got.pill, ["pointerdown", "click"], "правый клик — меню плашки проекта");
  assert.equal(passed, false, "своё контекстное меню Claude поверх не нужно");
  assert.equal(loaded.api.status().corner.originMenu, "finder");
  // Меню чата по имени чата (WF190) живо и не путается с проектом.
  assert.equal(chat.style.getPropertyValue("pointer-events"), "auto");
  loaded.api.dispose();
  assert.ok(!root.hasAttribute("data-myclaude-origin-open"), "dispose снимает плашку из угла");
  assert.equal(root.style.getPropertyValue("--myclaude-origin-x"), "");
});

// WF204 (followup WF197): в широком виде имя проекта стоит в строке шапки, и меню ⋮ проекта (Terminal /
// Changes / Browser, правый клик — Show in Finder) было только у невидимой плашки у края. Теперь имя в
// углу открывает его везде, где показано, — тем же путём, что над New.
test("WF204: строка шапки — клик по имени проекта открывает ⋮ проекта, правый — меню плашки; строка не прыгает", () => {
  const loaded = stand({ width: 400, gutter: { left: 77, top: 9, width: 24, height: 24 } });
  loaded.parts.titlebar.rect = { left: 77, top: 9, width: 320, height: 32 };
  const pill = loaded.parts.label.parentElement;
  const end = loaded.parts.titlebar.add("div", { class: "epitaxy-titlebar-end" });
  const dots = end.add("button", { attrs: { "aria-label": "View options", "aria-haspopup": "menu", "aria-expanded": "false" } });
  pill.setAttribute("aria-haspopup", "menu");
  pill.setAttribute("aria-expanded", "false");
  const got = { dots: [], pill: [] };
  for (const type of ["pointerdown", "click"]) {
    dots.addEventListener(type, event => got.dots.push(event.type));
    pill.addEventListener(type, event => got.pill.push(event.type));
  }
  pass(loaded);
  const node = corner(loaded);
  const { project, chat } = parts(node);
  assert.equal(loaded.api.status().corner.mode, "row");
  assert.equal(node.style.getPropertyValue("pointer-events"), "none", "угол прозрачен, кроме имени");
  assert.equal(project.style.getPropertyValue("pointer-events"), "auto", "имя проекта ловит мышь");
  assert.equal(project.style.getPropertyValue("cursor"), "pointer");
  assert.equal(project.style.getPropertyValue("-webkit-app-region"), "no-drag", "клик, а не перетаскивание окна");
  assert.equal(chat.style.getPropertyValue("pointer-events"), "", "имя чата в строке — родное название под ним");
  project.dispatchEvent({ type: "pointerenter" });
  assert.match(project.style.getPropertyValue("background-color"), /color-mix/);
  project.dispatchEvent({ type: "pointerleave" });
  assert.equal(project.style.getPropertyValue("background-color"), "");
  const root = loaded.document.documentElement;
  project.dispatchEvent({ type: "click" });
  assert.deepEqual(got.dots, ["pointerdown", "click"], "левый клик — родная ⋮ проекта");
  assert.equal(loaded.api.status().corner.originMenu, "project");
  assert.ok(root.hasAttribute("data-myclaude-origin-open"), "плашка на время меню — на имени");
  // Плашка встала на имя — край строки прежний, угол из-под меню не уезжает.
  pill.rect = { left: 105, top: 9, width: 90, height: 32 };
  dots.setAttribute("aria-expanded", "true");
  loaded.dom.fireKind("interval");
  pass(loaded);
  assert.equal(loaded.api.status().corner.mode, "row");
  assert.equal(node.style.getPropertyValue("width"), "284px");
  pill.rect = { left: 0, top: 0, width: 0, height: 0 };
  dots.setAttribute("aria-expanded", "false");
  loaded.dom.fireKind("interval");
  assert.ok(!root.hasAttribute("data-myclaude-origin-open"), "меню закрылось — плашка снята");
  const passed = project.dispatchEvent({ type: "contextmenu", cancelable: true });
  assert.deepEqual(got.pill, ["pointerdown", "click"], "правый клик — меню плашки (Show in Finder)");
  assert.equal(passed, false);
  assert.equal(loaded.api.status().corner.originMenu, "finder");
});

test("WF204: угол без строки шапки (попап) — имя проекта тоже открывает меню проекта", () => {
  const loaded = stand();
  const pill = loaded.parts.label.parentElement;
  const got = [];
  pill.addEventListener("click", event => got.push(event.type));
  pass(loaded);
  const { project } = parts(corner(loaded));
  assert.equal(loaded.api.status().corner.mode, "corner");
  assert.equal(project.style.getPropertyValue("pointer-events"), "auto");
  project.dispatchEvent({ type: "click" });
  assert.deepEqual(got, ["click"], "⋮ нет — меню плашки проекта");
  assert.equal(loaded.api.status().corner.originMenu, "project");
  // Плашки нет вовсе — честное «no-button».
  loaded.parts.label.parentElement.remove();
  project.dispatchEvent({ type: "click" });
  assert.equal(loaded.api.status().corner.originMenu, "no-button");
});

// ---- WF209 (#9257): место head — надзаголовок над названием колонки ------------
// Слово Элвиса 10.10 00:45: «сверху вот этот заголовок маленький… он должен крупненько там быть по
// красоте»; 02:07 — эталон: крупное название чата в шапке колонки и значок ноутбука справа. Замер
// живого окна Рика 10.10 02:05 (Claude 2.31226, CSS px): окно 889, широкий вид, список слева свёрнут;
// шапка колонки 574/8 314×32, название 612/12 182×24 (поле кнопки 4 — текст с 616, линия текста поля),
// значок Remote Control — у ПРАВОГО края шапки, 840/12 24×24 (WF179). В прежних стендах «row» значок
// стоял слева, поэтому ошибку никто не видел: строка «правее значка» была 12 px, угол падал в полоску
// corner и через cover гасил крупное название.
const HEAD = {
  titlebar: { left: 574, top: 8, width: 314, height: 32 },
  title: { left: 612, top: 12, width: 120, height: 24 },
  gutter: { left: 840, top: 12, width: 24, height: 24 },
};
const headStand = (options = {}) => {
  const loaded = stand({ href: "https://claude.ai/epitaxy/local_abc", width: 889, chat: "Запуск Курочки 3.0", wide: true, row: RICK, gutter: HEAD.gutter, ...options });
  loaded.parts.titlebar.rect = HEAD.titlebar;
  if (loaded.parts.title) {
    loaded.parts.title.rect = HEAD.title;
    loaded.parts.title.computed = { "padding-left": "4px" };
  }
  return loaded;
};

test("WF209: широкий вид, список свёрнут, значок у правого края — название колонки видно, угол над ним: проект и часики", () => {
  const loaded = headStand();
  pass(loaded);
  const node = corner(loaded);
  const { project, chat, clock } = parts(node);
  const root = loaded.document.documentElement;
  assert.equal(loaded.api.status().corner.mode, "head");
  // Название не накрыто и не погашено: ни cover, ни row — правила таблицы гасят его только по ним.
  assert.equal(root.getAttribute("data-myclaude-corner"), "head");
  assert.equal(loaded.api.status().corner.cover, false);
  const css = loaded.dom.sheets();
  assert.doesNotMatch(css, /data-myclaude-corner="head"\][^{]*\[data-pane-title\]/, "правила, гасящего название в head, нет");
  // Левый край — линия текста названия (612 + поле 4), она же линия текста поля; правый — край значка.
  assert.deepEqual(["left", "top", "width", "height", "right"].map(name => node.style.getPropertyValue(name)), ["742px", "12px", "88px", "24px", "auto"]);
  assert.equal(loaded.api.status().corner.line, 742);
  // Только проект и часики: имени чата в углу нет — оно крупно стоит под ним.
  assert.equal(project.textContent, "Rick");
  assert.equal(chat.style.getPropertyValue("display"), "none", "имя чата в углу не дублируется");
  assert.equal(loaded.api.status().corner.chat, "Запуск Курочки 3.0", "название чата страница знает — оно в шапке");
  // Мелко и тихо: 12/600, приглушён; часики 10 px сразу за именем.
  assert.equal(node.style.getPropertyValue("display"), "grid");
  assert.match(node.style.getPropertyValue("font"), /^12px/);
  assert.equal(project.style.getPropertyValue("font-weight"), "600");
  assert.equal(project.style.getPropertyValue("opacity"), "0.72");
  assert.equal(clock.style.getPropertyValue("font-size"), "10px");
  assert.equal(clock.style.getPropertyValue("order"), "1");
  assert.equal(node.style.getPropertyValue("background"), "transparent", "без плашки");
  // Слово Элвиса 10.10 03:55: шапка не растёт — отступа нет, проект и часики стоят в строке названия,
  // правее его текста и левее значка Remote Control.
  assert.equal(root.style.getPropertyValue("--myclaude-head-space"), "0px");
  assert.ok(px(node, "left") >= HEAD.title.left + HEAD.title.width, "проект и часики не наезжают на название");
  assert.ok(px(node, "left") + px(node, "width") <= HEAD.gutter.left, "и не наезжают на значок");
  assert.equal(root.style.getPropertyValue("--myclaude-side-space"), "", "отступ списка — только над New");
  assert.ok(px(node, "left") >= 120, "и стоит правее кнопок окна");
  assert.match(css, /\.epitaxy-chat-panel:not\(\[data-myclaude-title="left"\]\) & > \.epitaxy-titlebar \{\s*box-sizing: content-box !important;\s*padding-top: var\(--myclaude-head-space, 0px\) !important;/);
  // Мышь: угол прозрачен, имя проекта — кнопка.
  assert.equal(node.style.getPropertyValue("pointer-events"), "none");
  assert.equal(project.style.getPropertyValue("pointer-events"), "auto");
  assert.equal(project.style.getPropertyValue("-webkit-app-region"), "no-drag");
});

test("WF209: head — клик по имени проекта открывает то же меню проекта (⋮), правый — меню плашки", () => {
  const loaded = headStand();
  const pill = loaded.parts.label.parentElement;
  const end = loaded.parts.titlebar.add("div", { class: "epitaxy-titlebar-end" });
  const dots = end.add("button", { attrs: { "aria-label": "View options", "aria-haspopup": "menu", "aria-expanded": "false" } });
  pill.setAttribute("aria-haspopup", "menu");
  pill.setAttribute("aria-expanded", "false");
  const got = { dots: [], pill: [] };
  for (const type of ["pointerdown", "click"]) {
    dots.addEventListener(type, event => got.dots.push(event.type));
    pill.addEventListener(type, event => got.pill.push(event.type));
  }
  pass(loaded);
  const { project } = parts(corner(loaded));
  assert.equal(loaded.api.status().corner.mode, "head");
  project.dispatchEvent({ type: "pointerenter" });
  assert.match(project.style.getPropertyValue("background-color"), /color-mix/);
  project.dispatchEvent({ type: "pointerleave" });
  assert.equal(project.style.getPropertyValue("background-color"), "");
  project.dispatchEvent({ type: "click" });
  assert.deepEqual(got.dots, ["pointerdown", "click"], "левый клик — родная ⋮ проекта");
  assert.equal(loaded.api.status().corner.originMenu, "project");
  assert.ok(loaded.document.documentElement.hasAttribute("data-myclaude-origin-open"), "плашка на время меню — на имени");
  // Меню открыто — проход раскладки место не меняет.
  dots.setAttribute("aria-expanded", "true");
  loaded.dom.fireKind("interval");
  pass(loaded);
  assert.equal(loaded.api.status().corner.mode, "head");
  dots.setAttribute("aria-expanded", "false");
  loaded.dom.fireKind("interval");
  assert.ok(!loaded.document.documentElement.hasAttribute("data-myclaude-origin-open"), "меню закрылось — плашка снята");
  const passed = project.dispatchEvent({ type: "contextmenu", cancelable: true });
  assert.deepEqual(got.pill, ["pointerdown", "click"], "правый клик — меню плашки (Show in Finder)");
  assert.equal(passed, false);
});

test("WF209: остальные места — как были: список открыт — side, попап с шапкой слева — row, узкий вид — прежний угол", () => {
  // Список чатов открыт и пристыкован — заголовок над New, отступа шапки нет.
  const side = headStand({ panelLeft: 199, sidebar: SIDEBAR });
  pass(side);
  assert.equal(side.api.status().corner.mode, "side");
  assert.equal(side.document.documentElement.style.getPropertyValue("--myclaude-head-space"), "");
  assert.equal(parts(corner(side)).chat.style.getPropertyValue("display"), "block", "над New имя чата — второй строкой");
  assert.equal(parts(corner(side)).project.style.getPropertyValue("opacity"), "0.92");
  // Список свернулся — head; открылся снова — side, отступ шапки снят.
  side.parts.panel.rect = { ...side.parts.panel.rect, left: 9 };
  pass(side);
  assert.equal(side.api.status().corner.mode, "head");
  assert.equal(side.document.documentElement.style.getPropertyValue("--myclaude-side-space"), "");
  assert.equal(side.document.documentElement.style.getPropertyValue("--myclaude-head-space"), "0px");
  side.parts.panel.rect = { ...side.parts.panel.rect, left: 199 };
  pass(side);
  assert.equal(side.api.status().corner.mode, "side");
  assert.equal(side.document.documentElement.style.getPropertyValue("--myclaude-head-space"), "");
  // Попап в широком виде: шапка слева, под кнопками окна (значок там слева) — строка шапки, как была.
  const popup = stand({ width: 889, wide: true, gutter: { left: 77, top: 9, width: 24, height: 24 } });
  popup.parts.titlebar.rect = { left: 77, top: 9, width: 320, height: 32 };
  pass(popup);
  assert.equal(popup.api.status().corner.mode, "row", "с первого же прохода, без кадра в head");
  assert.equal(popup.document.documentElement.style.getPropertyValue("--myclaude-head-space"), "");
  // Узкий вид с той же шапкой (значок справа) — прежний угол: head только у шапки колонки широкого вида.
  const narrow = headStand({ wide: false });
  pass(narrow);
  assert.equal(narrow.api.status().corner.mode, "corner");
  assert.equal(parts(corner(narrow)).chat.style.getPropertyValue("display"), "block");
  // Широкий вид без названия чата (черновик) — надзаголовку не над чем стоять: тоже прежний угол.
  const draft = headStand({ chat: null });
  pass(draft);
  assert.notEqual(draft.api.status().corner.mode, "head");
});

test("WF209: dispose снимает отступ шапки и метку места", () => {
  const loaded = headStand();
  pass(loaded);
  assert.equal(loaded.document.documentElement.style.getPropertyValue("--myclaude-head-space"), "0px");
  loaded.api.dispose();
  assert.equal(loaded.document.documentElement.style.getPropertyValue("--myclaude-head-space"), "");
  assert.equal(loaded.document.documentElement.hasAttribute("data-myclaude-corner"), false);
});
