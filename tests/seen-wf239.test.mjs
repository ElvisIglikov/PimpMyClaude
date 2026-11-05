// WF239 (page-60, раздел 12м³ inject.js): галочка «просмотрено» у карточек файлов чата.
// Слово владельца 10.10 21:10: «сделал бы кнопку „просмотрено“… чтобы я как-то помечал те файлы,
// которые я просмотрел, галочкой. В правом углу в карточках… чтоб серыми становились, чтоб они
// внимание не отвлекали».
//
// Что проверяется:
//   1) галочка — настоящая кнопка в карточке файла ответа (файл и фото), с подписью результата;
//      у вложений реплики человека и вне ленты её нет;
//   2) нажал — карточка серая (метка on), галочка залита; ещё раз — как была; сама карточка при
//      нажатии на галочку не открывается, а нажатие по карточке открывает её и у просмотренной;
//   3) отметка хранится (localStorage["myclaude-seen-v1"] = {<ключ чата>: {at, ids}}), возвращается
//      после пересоздания узла ленты (в колбэке мутаций), после повторной установки страницы и после
//      «перезапуска» (новое окно на том же хранилище); общая у окон чата (storage);
//   4) тот же файл дважды — отмечен в обоих местах; новая редакция по тому же пути (другой размер) —
//      нет; узел, доставшийся другому файлу, отметку прежнего не наследует;
//   5) клавиатура — Enter и пробел, удержание не мигает, щелчок следом за клавишей не в счёт;
//   6) запись не удалась — отметка живёт до закрытия окна, причина в status().seen.lastError;
//   7) потолок хранилища; dispose убирает всё своё; status().seen = {marked, cards, lastError}.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_seen-2390";
const KEY = "myclaude-seen-v1";
const CHAT_KEY = `id:${CHAT}`;
const SEEN = "data-myclaude-seen";
const CHECK = "data-myclaude-seen-check";
const HTML = "/Users/demo/Projects/Marketolog/docs/58.html";
const PNG = "/Users/demo/Projects/Risovalka/out/nabor.png";
const MD = "/Users/demo/Projects/Rick/work/otchet.md";
const OWN = "/Users/demo/Desktop/moyo.png";
const ON_TEXT = "Снять отметку «просмотрено»";
const OFF_TEXT = "Отметить просмотренным";
const tick = () => new Promise(resolve => setImmediate(resolve));

// Карточка, как её кладёт Claude (замер 10.10): кнопка с путём в title, пропсы {name, size, path} —
// у компонента шагом выше; у файла — плашка типа и имя с размером, у фото — картинка.
const card = (parent, path, size = 4096, { photo = false } = {}) => {
  const button = parent.add("button", { attrs: { type: "button", title: path } });
  const name = path.split("/").pop();
  if (photo) button.add("img", { attrs: { alt: "", src: "data:image/png;base64,AAAA" } });
  else { button.add("div").add("span", { text: name.split(".").pop() }); button.add("div").add("p", { text: name }); }
  button.__reactFiber$test = { memoizedProps: { children: [] }, return: { memoizedProps: { name, size, path }, return: null } };
  return button;
};
const row = (feed, kind, index) => feed.add("div", { attrs: { "data-testid": "transcript-row", "data-index": String(index), "data-perf-row": kind } });

const page = ({ storage = {}, win = null, breakStorage = false } = {}) => {
  const nodes = {};
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off", ...storage } },
    geometry: { frame: [0, 0, 640, 900] },
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      nodes.feed = feed;
      nodes.human = row(feed, "human", 0);
      nodes.own = card(nodes.human, OWN, 900, { photo: true });
      nodes.first = row(feed, "assistant", 1);
      nodes.html = card(nodes.first, HTML, 49800);
      nodes.png = card(nodes.first, PNG, 120000, { photo: true });
      nodes.second = row(feed, "assistant", 2);
      nodes.again = card(nodes.second, HTML, 49800);
      nodes.next = card(nodes.second, HTML, 51200);
      nodes.md = card(nodes.second, MD, 0);
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.win.fetch = address => { loaded.calls.push(String(address)); return Promise.resolve({}); };
  if (breakStorage) loaded.win.localStorage.setItem = () => { const error = new Error("quota"); error.name = "QuotaExceededError"; throw error; };
  loaded.inner.seenTick();
  return { loaded, nodes };
};
const checkOf = node => [...node.childNodes].find(kid => kid.nodeType === 1 && kid.hasAttribute(CHECK)) ?? null;
const click = (loaded, target, extra = {}) => {
  const event = { type: "click", target, detail: 1, isTrusted: true, button: 0, ...extra };
  const passed = loaded.document.dispatchEvent(event);
  return { prevented: !passed };
};
const key = (loaded, name, target, extra = {}) => ({ prevented: !loaded.win.dispatchEvent({ type: "keydown", key: name, target, isTrusted: true, ...extra }) });
const stored = loaded => JSON.parse(loaded.win.localStorage.getItem(KEY) ?? "null");
const seen = loaded => plain(loaded.api.status().seen);
const look = nodes => Object.fromEntries(["own", "html", "png", "again", "next", "md"].map(name => [name, nodes[name].getAttribute(SEEN)]));
// Время страницы — вперёд (щелчок следом за клавишей отличается от щелчка позже).
const clock = loaded => {
  const base = loaded.win.performance.now();
  let shift = 0;
  loaded.win.performance.now = () => base + shift;
  return ms => { shift += ms; };
};

test("12м³: у каждой карточки файла ответа — кнопка-галочка с подписью результата; у вложения реплики человека её нет", () => {
  const { loaded, nodes } = page();
  assert.deepEqual(look(nodes), { own: null, html: "", png: "", again: "", next: "", md: "" });
  assert.equal(checkOf(nodes.own), null, "галочка у вложения человека");
  for (const name of ["html", "png", "again", "next", "md"]) {
    const check = checkOf(nodes[name]);
    assert.ok(check, `нет галочки: ${name}`);
    assert.equal(check.tagName, "BUTTON", "галочка — не настоящая кнопка");
    assert.equal(check.type, "button");
    assert.equal(check.getAttribute("aria-pressed"), "false");
    assert.equal(check.getAttribute("title"), OFF_TEXT);
    assert.equal(check.getAttribute("aria-label"), OFF_TEXT);
    assert.equal(check.getAttribute("tabindex"), null, "кнопка и так в порядке Tab — своего tabindex не нужно");
    assert.equal(check.parentNode, nodes[name], "галочка не в карточке");
    assert.equal(check.parentNode.childNodes[check.parentNode.childNodes.length - 1], check, "галочка не последним узлом — порядок содержимого карточки задет");
    assert.equal(String(check.textContent ?? ""), "", "у галочки есть текст — он попал бы в копию и в имя карточки");
  }
  assert.equal(loaded.dom.queryAll(`[${CHECK}]`).length, 5);
  assert.deepEqual(seen(loaded), { marked: 0, cards: 5, lastError: null });
  // Повторный проход ничего не плодит.
  loaded.inner.seenTick();
  loaded.inner.seenTick();
  assert.equal(loaded.dom.queryAll(`[${CHECK}]`).length, 5);
});

test("12м³: ключ файла — путь и размер из пропсов карточки; размера нет — один путь", () => {
  const { loaded, nodes } = page();
  assert.equal(loaded.inner.seenKeyOf(nodes.html), `${HTML}|49800`);
  assert.equal(loaded.inner.seenKeyOf(nodes.next), `${HTML}|51200`);
  assert.equal(loaded.inner.seenKeyOf(nodes.md), MD);
  // Пропсы не про этот путь (кнопка внутри чужого блока) — размер не берём.
  nodes.md.__reactFiber$test = { memoizedProps: {}, return: { memoizedProps: { name: "x", size: 5, path: "/другой/файл" }, return: null } };
  assert.equal(loaded.inner.seenKeyOf(nodes.md), MD);
  nodes.md.setAttribute("title", "не путь");
  assert.equal(loaded.inner.seenKeyOf(nodes.md), "");
});

test("12м³: нажал — карточка серая, галочка залита и подписана «снять»; ещё раз — как была; отметка лежит в хранилище по ключу чата", () => {
  const { loaded, nodes } = page();
  const check = checkOf(nodes.png);
  const first = click(loaded, check);
  assert.equal(first.prevented, true, "щелчок по галочке ушёл дальше");
  assert.equal(nodes.png.getAttribute(SEEN), "on");
  assert.equal(check.getAttribute("aria-pressed"), "true");
  assert.equal(check.getAttribute("title"), ON_TEXT);
  assert.equal(check.getAttribute("aria-label"), ON_TEXT);
  assert.equal(checkOf(nodes.png), check, "галочка пересоздана — фокус с неё слетел бы");
  assert.deepEqual(stored(loaded)[CHAT_KEY].ids, [`${PNG}|120000`]);
  assert.ok(stored(loaded)[CHAT_KEY].at > 0);
  assert.deepEqual(seen(loaded), { marked: 1, cards: 5, lastError: null });
  assert.equal(nodes.html.getAttribute(SEEN), "", "посерела чужая карточка");
  // Обратно — без вопроса; чат без отметок в хранилище не лежит.
  click(loaded, check);
  assert.equal(nodes.png.getAttribute(SEEN), "");
  assert.equal(check.getAttribute("aria-pressed"), "false");
  assert.equal(check.getAttribute("title"), OFF_TEXT);
  assert.equal(loaded.win.localStorage.getItem(KEY), null);
  assert.deepEqual(seen(loaded), { marked: 0, cards: 5, lastError: null });
});

test("12м³: нажатие на галочку карточку не открывает и фокус поля не отнимает; сама карточка открывается и серой; двойной щелчок — одна отметка", async () => {
  const { loaded, nodes } = page();
  const check = checkOf(nodes.html);
  // Нажатие мышью: фокус остаётся, где был (умолчание отменено), до карточки не доходит.
  assert.equal(loaded.document.dispatchEvent({ type: "mousedown", target: check, button: 0, isTrusted: true }), false, "mousedown по галочке не отменён — фокус ушёл бы с поля");
  click(loaded, check);
  await tick();
  assert.deepEqual(loaded.calls.filter(address => address.includes("/open-html")), [], "нажатие на галочку открыло файл");
  assert.equal(nodes.html.getAttribute("data-myclaude-busy"), null);
  assert.equal(loaded.api.status().htmlChrome.clicks, 0);
  // Второй щелчок двойного нажатия отметку обратно не снимает.
  click(loaded, check, { detail: 2 });
  assert.equal(nodes.html.getAttribute(SEEN), "on");
  // Просмотренная карточка рабочая: нажатие по ней самой открывает файл, как раньше.
  click(loaded, nodes.html);
  await tick();
  assert.equal(loaded.calls.filter(address => address.includes("/open-html")).length, 1, "серая карточка не открывается");
  assert.equal(nodes.html.getAttribute(SEEN), "on", "открытие карточки сняло отметку");
  // Перетаскивание: наведение на галочку не снимает с карточки draggable, поставленный наведением на неё.
  loaded.document.dispatchEvent({ type: "pointerover", target: nodes.html });
  loaded.document.dispatchEvent({ type: "pointerover", target: check });
  assert.equal(nodes.html.getAttribute("draggable"), "true");
  assert.equal(check.getAttribute("draggable"), null, "галочка сама стала перетаскиваемой");
});

test("12м³: тот же файл дважды — отмечен в обоих местах; новая редакция по тому же пути — нет", () => {
  const { loaded, nodes } = page();
  click(loaded, checkOf(nodes.again));
  assert.deepEqual(look(nodes), { own: null, html: "on", png: "", again: "on", next: "", md: "" });
  assert.equal(checkOf(nodes.html).getAttribute("aria-pressed"), "true");
  assert.equal(checkOf(nodes.next).getAttribute("aria-pressed"), "false", "новая редакция пришла уже «просмотренной»");
  assert.deepEqual(stored(loaded)[CHAT_KEY].ids, [`${HTML}|49800`]);
  // Снял на первом показе — снялось и на втором.
  click(loaded, checkOf(nodes.html));
  assert.deepEqual(look(nodes), { own: null, html: "", png: "", again: "", next: "", md: "" });
});

test("12м³: лента пересоздала узел — отмеченная карточка серая сразу, в колбэке мутаций; узел, доставшийся другому файлу, отметку не наследует", () => {
  const { loaded, nodes } = page();
  click(loaded, checkOf(nodes.html));
  click(loaded, checkOf(nodes.md));
  // Строка ушла из DOM и пришла новым узлом (виртуальная лента).
  nodes.first.remove();
  const row2 = row(nodes.feed, "assistant", 1);
  const fresh = card(row2, HTML, 49800);
  const plainCard = card(row2, PNG, 120000, { photo: true });
  loaded.inner.onMutated([{ type: "childList", target: nodes.feed, addedNodes: [row2], removedNodes: [nodes.first] }]);
  assert.equal(fresh.getAttribute(SEEN), "on", "пересозданная карточка мигнула бы обычной до следующего прохода");
  assert.equal(checkOf(fresh).getAttribute("aria-pressed"), "true");
  assert.equal(plainCard.getAttribute(SEEN), "", "неотмеченная в той же строке осталась без галочки");
  // Свои вставки второго круга не дают: мутация «добавлена галочка» ничего не делает.
  const before = loaded.dom.queryAll(`[${CHECK}]`).length;
  loaded.inner.onMutated([{ type: "childList", target: fresh, addedNodes: [checkOf(fresh)], removedNodes: [] }]);
  assert.equal(loaded.dom.queryAll(`[${CHECK}]`).length, before);
  // Общий проход снял учёт ушедших узлов.
  loaded.inner.seenTick();
  assert.deepEqual(seen(loaded), { marked: 2, cards: 5, lastError: null });
  // Тот же узел отдан другому файлу (Claude сменил ему title и пропсы): отметка прежнего файла не его.
  nodes.md.setAttribute("title", OWN);
  nodes.md.__reactFiber$test = { memoizedProps: {}, return: { memoizedProps: { name: "moyo.png", size: 900, path: OWN }, return: null } };
  loaded.inner.seenTick();
  assert.equal(nodes.md.getAttribute(SEEN), "");
  assert.equal(checkOf(nodes.md).getAttribute("aria-pressed"), "false");
  // Галочку вынесло из карточки (Claude пересобрал её содержимое) — проход возвращает ту же.
  const check = checkOf(nodes.again);
  check.remove();
  loaded.inner.seenTick();
  assert.equal(checkOf(nodes.again), check);
  assert.equal(loaded.dom.queryAll(`[${CHECK}]`).length, 5);
});

test("12м³: отметка переживает повторную установку страницы и перезапуск (новое окно на том же хранилище)", () => {
  const { loaded, nodes } = page();
  click(loaded, checkOf(nodes.html));
  click(loaded, checkOf(nodes.md));
  const saved = loaded.win.localStorage.getItem(KEY);
  // Лоадер перечитал inject.js в том же окне: прежний экземпляр снят, новый читает хранилище.
  const again = loaded.reload();
  assert.equal(again.error, null, String(again.error?.stack ?? again.error));
  again.inner.seenTick();
  assert.deepEqual(look(nodes), { own: null, html: "on", png: "", again: "on", next: "", md: "on" });
  assert.equal(loaded.dom.queryAll(`[${CHECK}]`).length, 5, "после повторной установки галочки задвоились");
  assert.deepEqual(plain(again.api.status().seen), { marked: 2, cards: 5, lastError: null });
  // Claude перезапущен: окно новое, узлы новые, хранилище то же.
  const restarted = page({ storage: { [KEY]: saved } });
  assert.deepEqual(look(restarted.nodes), { own: null, html: "on", png: "", again: "on", next: "", md: "on" });
  assert.equal(checkOf(restarted.nodes.md).getAttribute("title"), ON_TEXT);
  // Другой чат на том же хранилище отметок этого не получает.
  const other = page({ storage: { [KEY]: JSON.stringify({ "id:local_other": { at: 1, ids: [`${HTML}|49800`, MD] } }) } });
  assert.deepEqual(look(other.nodes), { own: null, html: "", png: "", again: "", next: "", md: "" });
  // Битое хранилище страницу не роняет.
  const broken = page({ storage: { [KEY]: "{не json" } });
  assert.deepEqual(seen(broken.loaded), { marked: 0, cards: 5, lastError: null });
});

test("12м³: другое окно того же чата видит отметку после события storage", () => {
  const { loaded, nodes } = page();
  loaded.win.localStorage.setItem(KEY, JSON.stringify({ [CHAT_KEY]: { at: 2, ids: [MD] }, "id:local_other": { at: 1, ids: [`${PNG}|120000`] } }));
  loaded.win.dispatchEvent({ type: "storage", key: KEY });
  assert.deepEqual(look(nodes), { own: null, html: "", png: "", again: "", next: "", md: "on" });
  // Чужие ключи хранилища отметок не трогают.
  loaded.win.localStorage.removeItem(KEY);
  loaded.win.dispatchEvent({ type: "storage", key: "myclaude-read-v1" });
  assert.equal(nodes.md.getAttribute(SEEN), "on");
  loaded.win.dispatchEvent({ type: "storage", key: KEY });
  assert.equal(nodes.md.getAttribute(SEEN), "");
});

test("12м³: клавиатура — Enter и пробел ставят и снимают; удержание не мигает; щелчок следом за клавишей не в счёт; чужие клавиши не трогаем", () => {
  const { loaded, nodes } = page();
  const later = clock(loaded);
  const check = checkOf(nodes.md);
  check.focus();
  assert.equal(key(loaded, "Enter", check).prevented, true);
  assert.equal(nodes.md.getAttribute(SEEN), "on");
  assert.equal(loaded.document.activeElement, check, "фокус ушёл с галочки");
  // Удержание клавиши отметку не переключает.
  assert.equal(key(loaded, "Enter", check, { repeat: true }).prevented, true);
  assert.equal(nodes.md.getAttribute(SEEN), "on");
  // Щелчок, который браузер шлёт кнопке следом за клавишей (detail 0), второй раз не переключает.
  assert.equal(click(loaded, check, { detail: 0 }).prevented, true);
  assert.equal(nodes.md.getAttribute(SEEN), "on");
  later(1000);
  assert.equal(key(loaded, " ", check).prevented, true);
  assert.equal(nodes.md.getAttribute(SEEN), "");
  // Щелчок без мыши сам по себе (чтение с экрана) — работает.
  later(1000);
  click(loaded, check, { detail: 0 });
  assert.equal(nodes.md.getAttribute(SEEN), "on");
  // Прочие клавиши на галочке и Enter на самой карточке — не наши.
  assert.equal(key(loaded, "Tab", check).prevented, false);
  assert.equal(key(loaded, "Enter", nodes.md).prevented, false);
  assert.equal(nodes.md.getAttribute(SEEN), "on");
});

test("12м³: запись не удалась — отметка действует до закрытия окна, причина — в status().seen.lastError", () => {
  const { loaded, nodes } = page({ breakStorage: true });
  click(loaded, checkOf(nodes.html));
  assert.deepEqual(look(nodes), { own: null, html: "on", png: "", again: "on", next: "", md: "" });
  assert.match(seen(loaded).lastError, /^отметки не сохранены, действуют до закрытия окна: QuotaExceededError/);
  assert.equal(seen(loaded).marked, 1);
  // Проход с чтением хранилища отметку сеанса не стирает.
  loaded.inner.seenTick();
  assert.equal(nodes.html.getAttribute(SEEN), "on");
  click(loaded, checkOf(nodes.html));
  assert.equal(nodes.html.getAttribute(SEEN), "");
});

test("12м³: потолок хранилища — у чата последние 300 отметок, давно не тронутые чаты уходят первыми", () => {
  const many = Array.from({ length: 320 }, (_, i) => `/f/${i}.html|${i + 1}`);
  const old = Object.fromEntries(Array.from({ length: 45 }, (_, i) => [`id:local_old-${i}`, { at: i + 1, ids: [`/o/${i}.png`] }]));
  const { loaded, nodes } = page({ storage: { [KEY]: JSON.stringify({ ...old, [CHAT_KEY]: { at: 5, ids: many } }) } });
  click(loaded, checkOf(nodes.md));
  const map = stored(loaded);
  assert.equal(map[CHAT_KEY].ids.length, 300);
  assert.equal(map[CHAT_KEY].ids.at(-1), MD, "свежая отметка срезана потолком");
  assert.equal(Object.keys(map).length, 40, "чатов больше потолка");
  assert.equal(map["id:local_old-0"], undefined, "самый давний чат остался");
  assert.ok(map["id:local_old-44"], "свежий чат ушёл раньше давнего");
});

test("12м³: вид каждого состояния задан правилами — покой, наведение, фокус, просмотрено, фото, «файл открывается», без движения", () => {
  const { loaded } = page();
  const rules = [...loaded.inner.RULES];
  const rule = start => rules.find(item => item.startsWith(start));
  const base = rule(`[${CHECK}]{`);
  assert.match(base, /position:absolute;top:5px;right:5px/);
  assert.match(base, /width:24px;height:24px/, "зона нажатия меньше 24");
  assert.match(base, /border-radius:50%/);
  assert.match(base, /opacity:\.3/, "в покое галочка не тихая");
  assert.match(rule(`button[${SEEN}]{`), /position:relative/);
  assert.ok(rule(`button[${SEEN}]:hover>[${CHECK}]`), "под курсором на карточке галочка не проявляется");
  assert.match(rule(`[${CHECK}]:hover,[${CHECK}]:focus-visible{`), /opacity:1 !important;background:/, "под курсором на галочке отклика нет");
  assert.match(rule(`[${CHECK}]:focus-visible{`), /outline:2px solid/, "фокус с клавиатуры не виден");
  assert.match(rule(`button[${SEEN}="on"]>:not([${CHECK}]){`), /opacity:\.5;filter:grayscale\(1\)/);
  assert.match(rule(`button[${SEEN}="on"]:is(:hover,:focus-visible)>:not([${CHECK}]){`), /opacity:\.85/, "серая карточка под курсором не проявляется");
  assert.ok(rule(`button[${SEEN}]:has(img)>[${CHECK}]{`), "на фото галочка без своей подложки");
  assert.match(rule(`button[data-myclaude-busy="file"]>[${CHECK}]{`), /visibility:hidden/, "галочка легла бы под ⏳");
  assert.ok(rules.some(item => item.startsWith("@media (prefers-reduced-motion: reduce){") && item.includes(`[${CHECK}]`)));
  // Размеры и поток карточки правила не меняют: ни отступов, ни ширины, ни display у карточки и её содержимого.
  for (const item of rules.filter(text => text.startsWith(`button[${SEEN}`))) assert.doesNotMatch(item.replace(/\[data-myclaude-seen-check\][^{]*\{[^}]*\}/g, ""), /padding|margin|width|height|display/, item);
});

test("12м³: dispose — галочек и меток нет, нажатия больше не наши; хранилище на месте", () => {
  const { loaded, nodes } = page();
  click(loaded, checkOf(nodes.html));
  const check = checkOf(nodes.png);
  const saved = loaded.win.localStorage.getItem(KEY);
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`[${CHECK}]`).length, 0);
  assert.equal(loaded.dom.queryAll(`[${SEEN}]`).length, 0);
  assert.equal(click(loaded, check).prevented, false, "слушатель щелчка остался после dispose");
  assert.equal(key(loaded, "Enter", check).prevented, false, "слушатель клавиш остался после dispose");
  assert.equal(loaded.win.localStorage.getItem(KEY), saved);
});

test("12м³: своего опроса нет — в покое проход идёт только общим сердцебиением (раз в 5 с), таймеров раздел не заводит", () => {
  const base = page();
  const timers = { ...base.loaded.counters };
  // Отметка, пересоздание узла и повторные проходы новых таймеров, наблюдателей и подписок не добавляют.
  click(base.loaded, checkOf(base.nodes.html));
  base.loaded.inner.seenTick();
  base.loaded.inner.onMutated([{ type: "childList", target: base.nodes.feed, addedNodes: [base.nodes.first], removedNodes: [] }]);
  for (const name of ["listeners", "observers", "timers", "intervals"]) assert.equal(base.loaded.counters[name], timers[name], name);
  // В покое (мутаций нет) сердцебиение зовёт проход не чаще раза в 5 с: 20 ударов по 0,5 с — 2 прохода.
  let now = Date.now();
  base.loaded.win.performance.now = () => now;
  for (let i = 0; i < 4; i += 1) { now += 500; base.loaded.inner.heartbeatTick(); base.loaded.dom.fireKind("timeout"); base.loaded.dom.fireKind("raf"); }
  const hits = [];
  const real = base.loaded.document.querySelectorAll.bind(base.loaded.document);
  base.loaded.document.querySelectorAll = selector => { if (String(selector).includes('button[title^="/"]') && String(selector).includes("data-perf-row")) hits.push(selector); return real(selector); };
  for (let i = 0; i < 20; i += 1) { now += 500; base.loaded.inner.heartbeatTick(); base.loaded.dom.fireKind("timeout"); base.loaded.dom.fireKind("raf"); }
  assert.equal(hits.length, 2, `проходов по карточкам за 10 с покоя: ${hits.length}`);
});
