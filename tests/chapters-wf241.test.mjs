// WF241 (page-64, раздел 12х² inject.js): главы чата — меню с затемнением, «прочитано», настройка вида.
// Слово Элвиса 11.10 01:40: «как я навожу на главы, они как вылетают, расширяются… когда навожу —
// открывай подменю с названиями, оно так выезжает. И пусть весь интерфейс плавно затемнится… если я
// главу прочитал, то могу на неё нажать, и она зелёным окрасится… правой кнопкой понажимал, и там
// была настройка… расстояние… толщину… и яркость».
//
// Стенд — разметка дорожки глав Claude 2.31226 (исходник компонента из кэша приложения, 11.10):
// div.epitaxy-toc > nav > ol[aria-hidden] (полоски: li > span, у текущей класс bg-alpha-8) и
// div > ol[role=list] > li > button (полоска и название). Пропсов React в стенде нет — глава
// узнаётся по номеру и названию; с пропсами (chapter.id) — по id, отдельная проверка.
// Стаб событий не всплывает: события шлём документу и окну с нужной целью в target.
//
// Что проверяется:
//   1) меню открывает страница: наведение — с задержкой, уход курсора и нажатие мимо закрывают;
//      затемнение ставится и снимается вместе с меню;
//   2) «прочитано»: галочка (мышь, Enter, пробел) и двойное нажатие по строке ставят и снимают;
//      двойное нажатие до Claude не доходит (переименования нет), одиночное — доходит (переход);
//   3) отметки хранятся по чату, переживают повторную установку и «перезапуск», общие у окон;
//   4) настройка правой кнопкой: родное меню Claude не открывается, ползунки меняют вид сразу и
//      пишут его в хранилище, «Как было» возвращает умолчание, Esc и нажатие мимо закрывают;
//   5) status().chapters; запись не удалась — причина в lastError; dispose убирает всё своё.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_chapters-241";
const CHAT_KEY = `id:${CHAT}`;
const READ_KEY = "myclaude-chapters-read-v1";
const LOOK_KEY = "myclaude-chapters-look-v1";
const OPEN = "data-myclaude-ch-open";
const READ = "data-myclaude-ch-read";
const CHECK = "data-myclaude-ch-check";
const DIM = "#myclaude-ch-dim";
const PANEL = "#myclaude-ch-settings";
const TITLES = ["Session start", "Ночная выкладка сайта", "Вибрация на телефоне", "Три распродажи среды"];
const NOW = 2; // текущая глава (с нуля)

const page = ({ storage = {}, win = null, breakStorage = false, titles = TITLES, fiber = false } = {}) => {
  const nodes = { rail: [], rows: [], buttons: [] };
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off", ...storage } },
    html: dom => {
      const parts = dom.composer({});
      nodes.feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      const toc = dom.document.body.add("div", { class: "epitaxy-toc absolute pointer-events-none" });
      nodes.nav = toc.add("nav", { attrs: { "aria-label": "Session chapters", tabindex: "0" }, rect: { left: 8, top: 48, width: 32, height: 400 } });
      nodes.railList = nodes.nav.add("ol", { attrs: { "aria-hidden": "true" }, class: "flex flex-col" });
      nodes.menu = nodes.nav.add("div", { class: "absolute start-0 top-0 invisible opacity-0" });
      nodes.list = nodes.menu.add("ol", { attrs: { role: "list" } });
      titles.forEach((title, index) => {
        nodes.rail.push(nodes.railList.add("li", { class: "h-[8px] flex items-center" }));
        nodes.rail[index].add("span", { class: index === NOW ? "block h-[2px] bg-alpha-8" : "block h-[2px] bg-alpha-3" });
        const row = nodes.list.add("li");
        const button = row.add("button", { attrs: { type: "button", title, ...(index === NOW ? { "aria-current": "true" } : {}) }, class: "group/ch" });
        button.add("span", { attrs: { "aria-hidden": "true" }, class: "block h-[2px]" });
        button.add("span", { class: "truncate text-body", text: title });
        if (fiber) button.__reactFiber$test = { memoizedProps: {}, return: { memoizedProps: {}, return: { memoizedProps: { chapter: { id: `ch-${index}`, title } }, return: null } } };
        nodes.rows.push(row);
        nodes.buttons.push(button);
      });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  if (win) loaded.win.localStorage = win.localStorage;
  if (breakStorage) loaded.win.localStorage.setItem = () => { throw Object.assign(new Error("нет места"), { name: "QuotaExceededError" }); };
  loaded.inner.chTick();
  return { loaded, nodes };
};
const status = loaded => plain(loaded.api.status().chapters);
const stored = loaded => JSON.parse(loaded.win.localStorage.getItem(READ_KEY) ?? "null");
const look = loaded => JSON.parse(loaded.win.localStorage.getItem(LOOK_KEY) ?? "null");
const checkOf = row => [...row.children].find(node => node.hasAttribute(CHECK)) ?? null;
// События мыши — документу (захват), клавиши — окну; ответ — отменено ли событие и дошло ли до Claude.
const send = (loaded, type, target, extra = {}) => {
  const claude = [];
  const listener = () => claude.push(type);
  loaded.document.addEventListener(type, listener);
  const prevented = !loaded.document.dispatchEvent({ type, target, button: 0, detail: 1, clientX: 60, clientY: 120, ...extra });
  loaded.document.removeEventListener(type, listener);
  return { prevented, reached: claude.length > 0 };
};
const key = (loaded, name, target, extra = {}) => !loaded.win.dispatchEvent({ type: "keydown", key: name, target, ...extra });
const hover = (loaded, target) => { send(loaded, "mouseover", target); loaded.dom.fireKind("timeout"); };
const css = loaded => String(loaded.dom.query("#myclaude-input-handle-style").textContent ?? "").split("\n");
const rule = (loaded, start) => css(loaded).find(line => line.startsWith(start)) ?? "";

test("дорожка в покое: шаг, толщина и яркость — переменные с умолчанием; текущая толще и ярче; полоски меню спрятаны", () => {
  const { loaded } = page();
  const rail = '.epitaxy-toc > nav > ol[aria-hidden="true"]';
  assert.match(rule(loaded, `${rail}>li{`), /height:var\(--myclaude-ch-step,26px\) !important/, "шаг полосок — шаг строк меню");
  assert.match(rule(loaded, `${rail}>li>span{`), /height:var\(--myclaude-ch-thick,3px\) !important;width:calc\(var\(--chat-gutter,32px\)\*3\/8\) !important/, "#10764: толще, длина прежняя — длиннее значит на текст");
  assert.match(rule(loaded, `${rail}{`), /padding-inline-start:0 !important;translate:-4px 0;/, "#10764: дорожка левее — полоски кончаются до текста (скрин №3)");
  assert.match(rule(loaded, `${rail}>li>span{`), /opacity:var\(--myclaude-ch-ink,0\.35\)/, "#10764: заметнее (было 12 %, у Claude 20 %)");
  assert.match(rule(loaded, `${rail}>li>span[class~="bg-alpha-8"]{`), /height:calc\(var\(--myclaude-ch-thick,3px\) \+ 1px\) !important;opacity:min\(1,calc\(var\(--myclaude-ch-ink,0\.35\) \+ \.3\)\)/, "#9758: текущая — тише (было + .65)");
  assert.match(rule(loaded, ".epitaxy-toc > nav > div>ol>li{"), /height:var\(--myclaude-ch-step,26px\)/, "строка меню той же высоты, что шаг дорожки");
  assert.match(rule(loaded, '.epitaxy-toc > nav > div>ol>li>button>span[aria-hidden="true"]{'), /display:none !important/, "полоски строк меню спрятаны: их место — у полосок дорожки");
  assert.match(rule(loaded, `.epitaxy-toc > nav:not([${OPEN}])>div{`), /visibility:hidden !important;opacity:0 !important/, "закрытое меню не видно, что бы ни сказал Claude");
  assert.match(rule(loaded, `.epitaxy-toc > nav:not([${OPEN}])>div{`), /pointer-events:none !important/);
  assert.ok(css(loaded).some(line => line.startsWith("@media (prefers-reduced-motion: reduce){.epitaxy-toc > nav > div,") && line.includes("transition:none !important")), "«Уменьшить движение» — без анимации");
  assert.deepEqual(status(loaded), { count: 4, read: 0, starred: 0, own: 0, open: false, settings: false, lastError: null });
});

test("наведение открывает меню с задержкой и затемняет окно; уход курсора закрывает оба", () => {
  const { loaded, nodes } = page();
  send(loaded, "mouseover", nodes.railList);
  assert.equal(nodes.nav.hasAttribute(OPEN), false, "мимоходом меню не открывается — только после задержки");
  assert.equal(loaded.dom.query(DIM), null, "затемнения до открытия нет");
  loaded.dom.fireKind("timeout");
  assert.equal(nodes.nav.hasAttribute(OPEN), true);
  const dim = loaded.dom.query(DIM);
  assert.equal(dim.dataset.on, "true", "окно притемнено");
  assert.equal(dim.style.getPropertyValue("left"), "8px", "затемнение — по месту меню");
  assert.equal(dim.style.getPropertyValue("top"), "48px");
  assert.equal(status(loaded).open, true);
  // Курсор перешёл с дорожки на строку меню — меню держится.
  send(loaded, "mouseover", nodes.buttons[1]);
  loaded.dom.fireKind("timeout");
  assert.equal(nodes.nav.hasAttribute(OPEN), true, "над меню — держится");
  // Ушёл на ленту — закрывается после задержки, затемнение гаснет.
  send(loaded, "mouseover", nodes.feed);
  assert.equal(nodes.nav.hasAttribute(OPEN), true, "закрытие — с задержкой, по дороге назад не захлопнется");
  loaded.dom.fireKind("timeout");
  assert.equal(nodes.nav.hasAttribute(OPEN), false);
  assert.equal(dim.dataset.on, "false", "затемнение снято");
  assert.equal(status(loaded).open, false);
});

test("курсор прошёл мимо дорожки, не задержавшись, — меню не открылось; ушёл из окна — закрылось", () => {
  const { loaded, nodes } = page();
  send(loaded, "mouseover", nodes.railList);
  send(loaded, "mouseover", nodes.feed);
  loaded.dom.fireKind("timeout");
  assert.equal(nodes.nav.hasAttribute(OPEN), false, "прошёл мимо — не открылось");
  hover(loaded, nodes.railList);
  assert.equal(nodes.nav.hasAttribute(OPEN), true);
  send(loaded, "mouseout", nodes.railList, { relatedTarget: null });
  loaded.dom.fireKind("timeout");
  assert.equal(nodes.nav.hasAttribute(OPEN), false, "курсор ушёл из окна — закрыто");
});

test("нажатие мимо закрывает меню сразу, и само нажатие до Claude доходит", () => {
  const { loaded, nodes } = page();
  hover(loaded, nodes.railList);
  const press = send(loaded, "mousedown", nodes.feed);
  assert.equal(nodes.nav.hasAttribute(OPEN), false);
  assert.equal(loaded.dom.query(DIM).dataset.on, "false");
  assert.deepEqual(press, { prevented: false, reached: true }, "нажатие не проглочено");
});

test("галочка — настоящая кнопка в каждой строке меню; нажал — глава зелёная в меню и в дорожке, ещё раз — снята", () => {
  const { loaded, nodes } = page();
  const check = checkOf(nodes.rows[1]);
  assert.equal(nodes.rows.filter(row => checkOf(row)).length, 4, "галочка в каждой строке");
  assert.equal(check.tagName, "BUTTON");
  assert.equal(check.type, "button");
  assert.equal(check.getAttribute("aria-pressed"), "false");
  assert.equal(check.getAttribute("aria-label"), "Отметить главу прочитанной", "подпись называет результат");
  assert.equal(check.parentNode, nodes.rows[1], "галочка — рядом с кнопкой строки, не внутри неё");
  hover(loaded, nodes.railList);
  const click = send(loaded, "click", check);
  assert.deepEqual(click, { prevented: true, reached: false }, "нажатие по галочке — только наше: перехода к главе нет");
  assert.equal(nodes.rows[1].hasAttribute(READ), true, "строка меню отмечена");
  assert.equal(nodes.rail[1].hasAttribute(READ), true, "полоска дорожки отмечена");
  assert.equal(nodes.rail[0].hasAttribute(READ), false);
  assert.equal(check.getAttribute("aria-pressed"), "true");
  assert.equal(check.getAttribute("aria-label"), "Снять отметку «прочитано»");
  assert.deepEqual(stored(loaded)[CHAT_KEY].ids, ["n2:Ночная выкладка сайта"]);
  assert.equal(status(loaded).read, 1);
  assert.equal(nodes.nav.hasAttribute(OPEN), true, "меню при отметке не закрывается");
  send(loaded, "click", check);
  assert.equal(nodes.rows[1].hasAttribute(READ), false, "второе нажатие снимает");
  assert.equal(nodes.rail[1].hasAttribute(READ), false);
  assert.equal(stored(loaded), null, "пустая запись не хранится");
  const green = rule(loaded, `.epitaxy-toc > nav > ol[aria-hidden="true"]>li[${READ}]>span{`);
  assert.match(green, /background-color:var\(--myclaude-ch-ok,rgb\(77,187,125\)\) !important/, "прочитанная полоска — зелёная");
});

test("двойное нажатие по строке отмечает главу и до Claude не доходит (переименования нет); одиночное — доходит", () => {
  const { loaded, nodes } = page();
  hover(loaded, nodes.railList);
  const single = send(loaded, "click", nodes.buttons[3]);
  assert.deepEqual(single, { prevented: false, reached: true }, "одиночное нажатие по названию — Claude (переход к главе)");
  assert.equal(nodes.rows[3].hasAttribute(READ), false, "одиночное нажатие ничего не отмечает");
  const double = send(loaded, "dblclick", nodes.buttons[3].children[1], { detail: 2 });
  assert.deepEqual(double, { prevented: true, reached: false }, "двойное нажатие Claude не видит");
  assert.equal(nodes.rows[3].hasAttribute(READ), true);
  assert.equal(nodes.rail[3].hasAttribute(READ), true);
  send(loaded, "dblclick", nodes.buttons[3], { detail: 2 });
  assert.equal(nodes.rows[3].hasAttribute(READ), false, "ещё одно двойное — снято");
  // Двойное нажатие по самой галочке: первый щелчок отметил, второй (detail 2) и dblclick обратно не снимают.
  const check = checkOf(nodes.rows[0]);
  send(loaded, "click", check, { detail: 1 });
  send(loaded, "click", check, { detail: 2 });
  send(loaded, "dblclick", check, { detail: 2 });
  assert.equal(nodes.rows[0].hasAttribute(READ), true);
  // Двойное нажатие по дорожке — не строка меню: не наше.
  assert.equal(send(loaded, "dblclick", nodes.rail[2], { detail: 2 }).prevented, false);
});

test("клавиатура: Enter и пробел на галочке ставят и снимают; удержание не мигает; щелчок следом за клавишей не в счёт", () => {
  const { loaded, nodes } = page();
  const check = checkOf(nodes.rows[2]);
  assert.equal(key(loaded, "Enter", check), true, "Enter наш — до Claude не уходит");
  assert.equal(nodes.rows[2].hasAttribute(READ), true);
  send(loaded, "click", check, { detail: 0 });
  assert.equal(nodes.rows[2].hasAttribute(READ), true, "щелчок, который браузер шлёт кнопке следом за клавишей, отметку не снимает");
  key(loaded, " ", check, { repeat: true });
  assert.equal(nodes.rows[2].hasAttribute(READ), true, "удержание клавиши не мигает");
  key(loaded, " ", check);
  assert.equal(nodes.rows[2].hasAttribute(READ), false, "пробел снимает");
  assert.equal(key(loaded, "Enter", nodes.buttons[2]), false, "Enter на строке — не наш: переход Claude");
});

test("отметки переживают повторную установку страницы и перезапуск; глава узнаётся по номеру и названию", () => {
  const first = page();
  send(first.loaded, "click", checkOf(first.nodes.rows[1]));
  send(first.loaded, "click", checkOf(first.nodes.rows[3]));
  const again = first.loaded.reload();
  assert.equal(again.error, null, String(again.error));
  first.loaded.inner.chTick();
  assert.equal(first.nodes.rows[1].hasAttribute(READ), true, "после повторной установки отметка на месте");
  assert.equal(first.nodes.rows.filter(row => checkOf(row)).length, 4, "галочки не задвоились и не пропали");
  assert.equal(first.loaded.dom.queryAll(`[${CHECK}]`).length, 4);
  const restart = page({ storage: { [READ_KEY]: first.loaded.win.localStorage.getItem(READ_KEY) } });
  assert.deepEqual(restart.nodes.rows.map(row => row.hasAttribute(READ)), [false, true, false, true]);
  assert.deepEqual(restart.nodes.rail.map(line => line.hasAttribute(READ)), [false, true, false, true]);
  assert.equal(status(restart.loaded).read, 2);
  // Другой чат — свои отметки.
  const other = page({ storage: { [READ_KEY]: JSON.stringify({ "id:local_other": { at: 1, ids: ["n2:Ночная выкладка сайта"] } }) } });
  assert.equal(status(other.loaded).read, 0);
});

test("с пропсами React глава узнаётся по своему id — переименование отметку не теряет", () => {
  const { loaded, nodes } = page({ fiber: true });
  assert.equal(loaded.inner.chKeyOf(nodes.rows[1], 1), "id:ch-1");
  send(loaded, "click", checkOf(nodes.rows[1]));
  assert.deepEqual(stored(loaded)[CHAT_KEY].ids, ["id:ch-1"]);
  loaded.dom.retext(nodes.buttons[1].children[1], "Выкладка сайта: готово");
  loaded.inner.chTick();
  assert.equal(nodes.rows[1].hasAttribute(READ), true, "название сменилось — отметка та же");
});

test("отметка из другого окна того же чата приходит через storage", () => {
  const { loaded, nodes } = page();
  loaded.win.localStorage.setItem(READ_KEY, JSON.stringify({ [CHAT_KEY]: { at: 5, ids: ["n1:Session start"] } }));
  loaded.win.dispatchEvent({ type: "storage", key: READ_KEY });
  assert.equal(nodes.rows[0].hasAttribute(READ), true);
  assert.equal(nodes.rail[0].hasAttribute(READ), true);
  assert.equal(checkOf(nodes.rows[0]).getAttribute("aria-pressed"), "true");
});

test("запись не удалась — отметка действует до закрытия окна, причина в status().chapters.lastError", () => {
  const { loaded, nodes } = page({ breakStorage: true });
  send(loaded, "click", checkOf(nodes.rows[0]));
  assert.equal(nodes.rows[0].hasAttribute(READ), true, "отметка на экране есть");
  assert.match(status(loaded).lastError, /отметки глав не сохранены, действуют до закрытия окна: QuotaExceededError/);
  loaded.inner.chTick();
  assert.equal(nodes.rows[0].hasAttribute(READ), true, "проход сердцебиения её не стирает");
  send(loaded, "click", checkOf(nodes.rows[0]));
  assert.equal(nodes.rows[0].hasAttribute(READ), false, "и снимается");
});

test("правая кнопка по дорожке или меню открывает настройку вида; родное меню Claude не открывается", () => {
  const { loaded, nodes } = page();
  const menu = send(loaded, "contextmenu", nodes.rail[1], { button: 2, clientX: 20, clientY: 90 });
  assert.deepEqual(menu, { prevented: true, reached: false }, "до Claude событие не дошло — его меню «Rename · Delete» не открыто");
  assert.equal(nodes.nav.hasAttribute(OPEN), true, "меню глав открыто сразу — вид меняется на глазах");
  const panel = loaded.dom.query(PANEL);
  assert.equal(panel.style.getPropertyValue("display"), "block");
  assert.equal(panel.getAttribute("role"), "dialog");
  assert.deepEqual(status(loaded), { count: 4, read: 0, starred: 0, own: 0, open: true, settings: true, lastError: null });
  const inputs = loaded.dom.queryAll(`${PANEL} input`);
  assert.deepEqual(inputs.map(input => input.getAttribute("aria-label")), ["Расстояние", "Толщина", "Яркость"]);
  assert.deepEqual(inputs.map(input => input.type), ["range", "range", "range"], "ползунки — родные: Tab ходит по ним сам");
  assert.deepEqual(inputs.map(input => input.value), ["26", "3", "35"], "умолчание");
  assert.equal(loaded.document.activeElement, inputs[0], "фокус — на первом ползунке");
  // Курсор ушёл с меню на панель и дальше на ленту — пока настройка открыта, меню держится.
  send(loaded, "mouseover", nodes.feed);
  loaded.dom.fireKind("timeout");
  assert.equal(nodes.nav.hasAttribute(OPEN), true, "с открытой настройкой меню не закрывается от ухода курсора");
  // Правая кнопка по строке меню — то же самое.
  const again = send(loaded, "contextmenu", nodes.buttons[2], { button: 2 });
  assert.equal(again.prevented, true);
  assert.equal(loaded.dom.queryAll(PANEL).length, 1, "панель одна");
  // Правая кнопка вне глав — не наша.
  assert.deepEqual(send(loaded, "contextmenu", nodes.feed, { button: 2 }), { prevented: false, reached: true });
});

test("ползунки меняют вид сразу и пишут его в хранилище; «Как было» возвращает умолчание", () => {
  const { loaded, nodes } = page();
  send(loaded, "contextmenu", nodes.rail[0], { button: 2 });
  const [step, thick, ink] = loaded.dom.queryAll(`${PANEL} input`);
  const reset = loaded.dom.query(`${PANEL} button`);
  const root = loaded.document.documentElement.style;
  assert.equal(reset.textContent, "Как было");
  assert.equal(reset.getAttribute("aria-disabled"), "true", "возвращать нечего");
  step.value = "34";
  loaded.document.dispatchEvent({ type: "input", target: step });
  assert.equal(root.getPropertyValue("--myclaude-ch-step"), "34px", "шаг сменился сразу");
  assert.deepEqual(look(loaded), { step: 34, thick: 3, ink: 35 });
  thick.value = "3.5";
  loaded.document.dispatchEvent({ type: "input", target: thick });
  ink.value = "45";
  loaded.document.dispatchEvent({ type: "input", target: ink });
  assert.equal(root.getPropertyValue("--myclaude-ch-thick"), "3.5px");
  assert.equal(root.getPropertyValue("--myclaude-ch-ink"), "0.45");
  assert.deepEqual(look(loaded), { step: 34, thick: 3.5, ink: 45 });
  assert.equal(reset.getAttribute("aria-disabled"), "false");
  assert.equal(nodes.nav.hasAttribute(OPEN), true, "меню открыто, пока крутят");
  send(loaded, "click", reset);
  for (const name of ["--myclaude-ch-step", "--myclaude-ch-thick", "--myclaude-ch-ink"]) assert.equal(root.getPropertyValue(name), "", `${name} снята`);
  assert.equal(look(loaded), null, "умолчание в хранилище не держится");
  assert.deepEqual([step.value, thick.value, ink.value], ["26", "3", "35"], "ползунки вернулись");
  assert.equal(reset.getAttribute("aria-disabled"), "true");
  assert.equal(loaded.dom.query(PANEL).style.getPropertyValue("display"), "block", "«Как было» панель не закрывает");
});

test("вид переживает перезапуск и приходит из другого окна; мусор в хранилище — умолчание", () => {
  const saved = page({ storage: { [LOOK_KEY]: JSON.stringify({ step: 18, thick: 4, ink: 60 }) } });
  const root = saved.loaded.document.documentElement.style;
  assert.equal(root.getPropertyValue("--myclaude-ch-step"), "18px");
  assert.equal(root.getPropertyValue("--myclaude-ch-thick"), "4px");
  assert.equal(root.getPropertyValue("--myclaude-ch-ink"), "0.6");
  saved.loaded.win.localStorage.setItem(LOOK_KEY, JSON.stringify({ step: 30 }));
  saved.loaded.win.dispatchEvent({ type: "storage", key: LOOK_KEY });
  assert.equal(root.getPropertyValue("--myclaude-ch-step"), "30px", "другое окно сменило шаг");
  assert.equal(root.getPropertyValue("--myclaude-ch-thick"), "", "чего в записи нет — по умолчанию");
  const junk = page({ storage: { [LOOK_KEY]: "{не json" } });
  assert.equal(junk.loaded.document.documentElement.style.getPropertyValue("--myclaude-ch-step"), "");
  const clean = junk.loaded.inner.chLookClean;
  assert.deepEqual(plain(clean({ step: 999, thick: -5, ink: "abc" })), { step: 40, thick: 1, ink: 35 }, "за пределами — к краю, мусор — умолчание");
  assert.deepEqual(plain(clean({ step: 21.4, thick: 2.74, ink: 33.6 })), { step: 21, thick: 2.5, ink: 34 }, "по шагу ползунка");
});

test("Esc закрывает настройку и возвращает фокус; нажатие мимо закрывает настройку и меню; чужой Esc не трогаем", () => {
  const { loaded, nodes } = page();
  hover(loaded, nodes.railList);
  key(loaded, "Escape", nodes.feed);
  assert.equal(nodes.nav.hasAttribute(OPEN), true, "меню открыто наведением, фокус не в главах — Esc принадлежит Claude, меню от него не закрывается");
  loaded.parts.editor.focus();
  send(loaded, "contextmenu", nodes.rail[0], { button: 2 });
  assert.equal(status(loaded).settings, true);
  assert.equal(key(loaded, "Escape", loaded.document.activeElement), true, "Esc — наш");
  assert.equal(status(loaded).settings, false);
  assert.equal(loaded.dom.query(PANEL).style.getPropertyValue("display"), "none");
  assert.equal(loaded.document.activeElement, loaded.parts.editor, "фокус вернулся в поле ввода");
  assert.equal(nodes.nav.hasAttribute(OPEN), true, "меню глав после Esc настройки остаётся");
  send(loaded, "contextmenu", nodes.rail[0], { button: 2 });
  // Нажатие внутри панели её не закрывает.
  send(loaded, "mousedown", loaded.dom.query(`${PANEL} input`));
  assert.equal(status(loaded).settings, true);
  // Нажатие по строке меню закрывает настройку, меню остаётся.
  send(loaded, "mousedown", nodes.buttons[1]);
  assert.deepEqual([status(loaded).settings, status(loaded).open], [false, true]);
  send(loaded, "contextmenu", nodes.rail[0], { button: 2 });
  send(loaded, "mousedown", nodes.feed);
  assert.deepEqual([status(loaded).settings, status(loaded).open], [false, false], "нажатие мимо — закрыто всё");
  assert.equal(loaded.dom.query(DIM).dataset.on, "false");
});

test("Claude пересобрал дорожку (другой чат) — открытое меню закрыто, отметки и галочки — нового чата", () => {
  const { loaded, nodes } = page();
  send(loaded, "click", checkOf(nodes.rows[1]));
  hover(loaded, nodes.railList);
  const toc = nodes.nav.parentNode;
  nodes.nav.remove();
  const nav = toc.add("nav");
  const railList = nav.add("ol", { attrs: { "aria-hidden": "true" } });
  const list = nav.add("div").add("ol", { attrs: { role: "list" } });
  const rail = [railList.add("li"), railList.add("li")];
  rail.forEach(line => line.add("span", { class: "bg-alpha-3" }));
  const rows = ["Session start", "Ночная выкладка сайта"].map(title => { const row = list.add("li"); row.add("button", { attrs: { type: "button" }, text: title }); return row; });
  loaded.inner.chTick();
  assert.deepEqual(status(loaded), { count: 2, read: 1, starred: 0, own: 0, open: false, settings: false, lastError: null });
  assert.equal(loaded.dom.query(DIM).dataset.on, "false", "затемнение прежней дорожки снято");
  assert.equal(rows[1].hasAttribute(READ), true, "та же глава на своём месте — отмечена");
  assert.equal(rail[1].hasAttribute(READ), true);
  assert.equal(loaded.dom.queryAll(`[${CHECK}]`).filter(node => node.parentNode && rows.includes(node.parentNode)).length, 2);
});

test("чужая страница и окно без глав: подписок и своих узлов нет", () => {
  const alien = loadInject({ href: "data:text/html,<p>артефакт</p>", title: "Артефакт", storage: { local: { [LOOK_KEY]: JSON.stringify({ step: 18 }) } } });
  assert.equal(alien.error, null);
  assert.equal(alien.document.documentElement.style.getPropertyValue("--myclaude-ch-step"), "", "на чужой странице вид не ставится");
  const empty = loadInject({ href: `https://claude.ai/epitaxy/${CHAT}`, html: "composer" });
  empty.inner.chTick();
  assert.deepEqual(plain(empty.api.status().chapters), { count: 0, read: 0, starred: 0, own: 0, open: false, settings: false, lastError: null });
  assert.equal(empty.dom.queryAll(`${DIM},${PANEL},[${CHECK}]`).length, 0);
});

test("dispose убирает всё своё: галочки, метки, затемнение, панель, переменные вида, таймеры", () => {
  const { loaded, nodes } = page({ storage: { [LOOK_KEY]: JSON.stringify({ step: 18 }) } });
  send(loaded, "click", checkOf(nodes.rows[0]));
  send(loaded, "contextmenu", nodes.rail[0], { button: 2 });
  send(loaded, "mouseover", nodes.feed);
  assert.equal(loaded.dom.queryAll(`${DIM},${PANEL}`).length, 2);
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`${DIM},${PANEL},[${CHECK}],[${READ}],[${OPEN}]`).length, 0, "свои узлы и метки остались");
  const root = loaded.document.documentElement.style;
  for (const name of ["--myclaude-ch-step", "--myclaude-ch-thick", "--myclaude-ch-ink", "--myclaude-ch-ok"]) assert.equal(root.getPropertyValue(name), "", `${name} осталась`);
  assert.equal(loaded.dom.count("timeout"), 0, "таймер пережил dispose");
  assert.equal(nodes.rows[0].children.length, 1, "в строке меню — только кнопка Claude");
  assert.ok(loaded.win.localStorage.getItem(READ_KEY), "отметки в хранилище целы");
});

test("page-71: меню шире и без многоточий; строка — полоска, галочка, название; строка с переносом тянет за собой полоску", () => {
  // Слово Элвиса 11.10 07:27: «многоточия-то эти не нужны… чтобы они пошире, вот эта панель была», «галочки…
  // справа… до них далеко тянуться. Давай галочки поставим вот: минус, потом галочка… ну и название».
  const { loaded, nodes } = page();
  const menu = rule(loaded, ".epitaxy-toc > nav > div{width:max-content");
  assert.match(menu, /max-width:min\(560px,calc\(var\(--myclaude-ch-room,100vw\) - 16px\)\) !important/);
  const title = rule(loaded, ".epitaxy-toc > nav > div>ol>li>button>span:not([aria-hidden]){");
  assert.match(title, /white-space:normal !important/);
  assert.match(title, /text-overflow:clip !important/);
  assert.match(rule(loaded, ".epitaxy-toc > nav > div>ol>li{"), /height:auto !important;min-height:var\(--myclaude-ch-step,26px\)/);
  const check = rule(loaded, `[${CHECK}]{`);
  assert.match(check, /left:calc\(var\(--chat-gutter,32px\)\*9\/16 \+ 6px\)/, "галочка не сразу за полоской");
  assert.ok(!/right:/.test(check), "галочка осталась у правого края");
  assert.match(rule(loaded, `.epitaxy-toc > nav > div>ol>li>button:not([${CHECK}],[data-myclaude-ch-star]){`), /padding-inline:calc\(var\(--chat-gutter,32px\)\*9\/16 \+ 58px\) 12px !important/, "#9758: название — за галочкой и звёздочкой");
  // Название не влезло и перенеслось: строка меню 44 при шаге 26 — полоска этой главы той же высоты.
  nodes.rows[1].getBoundingClientRect = () => ({ left: 0, top: 26, width: 300, height: 44, right: 300, bottom: 70 });
  loaded.inner.chTick();
  assert.equal(nodes.rail[1].style.getPropertyValue("height"), "44px");
  assert.equal(nodes.rail[0].style.getPropertyValue("height"), "", "строка в один ряд — полоска как была");
  // Название снова в один ряд — своя высота снята; dispose тоже снимает.
  nodes.rows[1].getBoundingClientRect = () => ({ left: 0, top: 26, width: 300, height: 26, right: 300, bottom: 52 });
  loaded.inner.chTick();
  assert.equal(nodes.rail[1].style.getPropertyValue("height"), "");
  nodes.rows[1].getBoundingClientRect = () => ({ left: 0, top: 26, width: 300, height: 62, right: 300, bottom: 88 });
  loaded.inner.chTick();
  assert.equal(nodes.rail[1].style.getPropertyValue("height"), "62px");
  loaded.api.dispose();
  assert.equal(nodes.rail[1].style.getPropertyValue("height"), "");
});
