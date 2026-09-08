// Живые цвета (раздел 2в inject.js, WF18): команда live-colors, интерполяция
// кольца, защёлкивание фазы окна, паузы, выключение, dispose. Перенесено в
// репозиторий из скретч-теста волны WF18 и приведено к общему раннеру.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const near = (a, b, eps = 0.05) => Math.abs(a - b) <= eps;
const rgb = (r, g, b) => `#${[r, g, b].map(value => value.toString(16).padStart(2, "0")).join("")}`;
// Кольцо из 12 точек с шагом 30°: цвета сделаны различимыми, чтобы середину
// хорды было видно глазами в самом тексте CSS.
const ringOf = base => Array.from({ length: 12 }, (unused, index) => ({
  accent: rgb(index * 0x10, 0, 0),
  background: rgb(0, index * 0x10, base),
  foreground: "#ffffff", sidebar: "#111111", panel: "#222222", muted: "#888888",
}));
const RING = { dark: ringOf(0x10), light: ringOf(0x20) };
const baseCommand = (extra = {}) => ({
  id: "c1", action: "live-colors", at: "now", scope: "all", on: true,
  mode: "solo", period: 300, epoch: Date.now(), light: false,
  titles: ["Trelvis", "Dictatorik", "PimpMyClaude"], ring: RING, ...extra,
});
const savedRing = (extra = {}) =>
  JSON.stringify({ on: true, mode: "solo", period: 300, epoch: Date.now(), light: false, ring: RING, ...extra });

const open = (options = {}) => loadInject({ title: "Trelvis", href: "https://claude.ai/chat/abc", ...options });
const phaseRecord = loaded => JSON.parse(loaded.win.sessionStorage.getItem("myclaude-live-phase-v1") ?? "null");
const lastTick = loaded => loaded.dom.ids("interval").slice(-1)[0];
const tick = loaded => loaded.document.dispatchEvent({ type: "visibilitychange" });

test("холодный старт: крутёжа нет, версия помечена воркфлоу", () => {
  const loaded = open();
  assert.match(loaded.version, /^wf\d+-[a-z]-\d+$/, "версия вида wfN-x-N");
  const live = loaded.api.status().live;
  assert.equal(live.on, false);
  assert.equal(live.hue, null);
  assert.ok(loaded.dom.count("interval") >= 2, "заголовок и пульс полосы");
});

test("команда включает крутёж и красит окно живой темой", () => {
  const loaded = open();
  const before = loaded.dom.count("interval");
  loaded.dom.command(baseCommand({ epoch: Date.now() }));
  const status = loaded.api.status();
  assert.equal(status.live.on, true);
  assert.equal(status.live.mode, "solo");
  assert.equal(status.live.period, 300);
  assert.ok(near(status.live.phase, 0), "первое окно из трёх стоит в нуле");
  assert.ok(near(status.live.hue, 0, 1), "сразу после epoch тон нулевой");
  assert.equal(status.live.ring, 12);
  assert.equal(status.live.source, "command");
  assert.equal(status.theme.source, "live");
  assert.ok(String(status.theme.id).startsWith("live-dark-"));
  assert.equal(loaded.dom.count("interval"), before + 1, "добавился ровно один интервал — тик");
  assert.ok(loaded.dom.sheets().includes("Живые цвета"));
  assert.notEqual(loaded.win.localStorage.getItem("myclaude-live-v1"), null, "крутёж живёт и без приложения");
  assert.equal(loaded.win.localStorage.getItem("myclaude-themes-v1"), null, "карта тем не тронута");
  assert.equal(loaded.win.sessionStorage.getItem("myclaude-theme-v1"), null, "сессия тем не тронута");
  assert.equal(phaseRecord(loaded).key, "main", "фаза защёлкнута под ключом окна");
});

test("фаза окна: по списку заголовков, а без списка — по хэшу имени", () => {
  const second = open({ title: "Dictatorik" });
  second.dom.command(baseCommand());
  assert.ok(near(second.api.status().live.phase, 120), "второе окно из трёх — 120°");
  const guest = open({ title: "Гость" });
  guest.dom.command(baseCommand());
  const phase = guest.api.status().live.phase;
  assert.ok(phase >= 0 && phase < 360, "окна нет в списке — фаза из хэша, но в круге");
  const twin = open({ title: "Гость" });
  twin.dom.command(baseCommand());
  assert.equal(twin.api.status().live.phase, phase, "хэш устойчив: то же имя — та же фаза");
});

test("защёлка: смена чата фазу не двигает, а скорость меняется", () => {
  const loaded = open();
  loaded.dom.command(baseCommand());
  const first = loaded.api.status().live.phase;
  loaded.document.title = "Совсем другой чат";
  loaded.dom.command(baseCommand({ id: "c2", period: 60 }));
  assert.equal(loaded.api.status().live.phase, first);
  assert.ok(near(first, 0));
  assert.equal(loaded.api.status().live.period, 60);
});

test("интерполяция: цвет — середина между соседями кольца", () => {
  const loaded = open();
  // Ровно середина первой хорды: 15° при шаге 30°.
  loaded.dom.command(baseCommand({ epoch: Date.now() - (15 / 360) * 300 * 1000, mode: "sync" }));
  assert.ok(near(loaded.api.status().live.hue, 15, 0.6));
  const css = loaded.dom.sheets();
  // accent: точка 0 = #000000, точка 1 = #100000 → середина #080000.
  assert.ok(css.includes("--claude-accent-clay: #080000"), "акцент посередине хорды");
  // background: точка 0 = #000010, точка 1 = #001010 → середина #000810.
  assert.ok(css.includes("--claude-background-color: #000810"), "фон посередине хорды");
});

test("паузы: спрятанное окно не красится, примерка сильнее тика", () => {
  const loaded = open();
  loaded.dom.command(baseCommand({ epoch: Date.now() - 100000 }));
  const tickId = lastTick(loaded);
  const painted = () => loaded.api.status().live.paints;
  const before = painted();
  loaded.document.hidden = true;
  loaded.dom.fire(tickId);
  assert.equal(painted(), before, "спрятанное окно не красится");
  loaded.document.hidden = false;
  loaded.dom.fire(tickId);
  assert.equal(painted(), before + 1, "вернулось — покрасилось");
  const beforeEvent = painted();
  tick(loaded);
  assert.equal(painted(), beforeEvent + 1, "visibilitychange догоняет цвет, не дожидаясь тика");
  loaded.dom.command({
    id: "p1", action: "theme", at: "now", scope: "window", title: "Trelvis", preview: true,
    theme: { id: "preview", name: "Примерка", type: "dark", palette: { accent: "#ff0000", background: "#010203", foreground: "#ffffff", sidebar: "#000000", panel: "#000000", muted: "#888888" } },
  });
  const paintedBefore = painted();
  loaded.dom.fire(tickId);
  assert.equal(painted(), paintedBefore, "во время примерки тик молчит");
  assert.ok(loaded.dom.sheets().includes("#010203"), "на экране примерка, а не живой цвет");
});

test("выключение возвращает прежнюю тему и снимает тик", () => {
  const stored = JSON.stringify({
    "chat:Trelvis": { theme: { id: "sea", name: "Море", type: "dark", palette: { accent: "#2299ff", background: "#001122", foreground: "#eeffff", sidebar: "#000811", panel: "#00223a", muted: "#88aabb" } } },
  });
  const loaded = open({ storage: { local: { "myclaude-themes-v1": stored } } });
  assert.equal(loaded.api.status().theme.id, "sea", "на старте тема чата");
  loaded.dom.command(baseCommand());
  assert.equal(loaded.api.status().theme.source, "live", "живые перекрыли тему чата");
  const before = loaded.dom.count("interval");
  loaded.dom.command({ id: "off", action: "live-colors", at: "now", scope: "all", on: false });
  const status = loaded.api.status();
  assert.equal(status.live.on, false);
  assert.equal(status.live.hue, null);
  assert.equal(status.theme.id, "sea");
  assert.equal(status.theme.source, "chat");
  assert.equal(loaded.dom.count("interval"), before - 1, "интервал тика снят");
  assert.equal(loaded.win.localStorage.getItem("myclaude-live-v1"), null, "память живых стёрта");
  assert.equal(JSON.parse(loaded.win.localStorage.getItem("myclaude-themes-v1"))["chat:Trelvis"].theme.id, "sea",
    "карта тем цела");
});

test("окно, открытое во время крутёжа, поднимает его из памяти", () => {
  const loaded = open({ title: "Позднее окно", storage: { local: { "myclaude-live-v1": savedRing({ period: 120, light: true }) } } });
  const status = loaded.api.status();
  assert.equal(status.live.on, true);
  assert.equal(status.live.source, "storage");
  assert.equal(status.live.light, true);
  assert.ok(status.theme.id.startsWith("live-light-"));
  assert.equal(status.live.period, 120);
});

test("мусор в команде: границы периода, режим и свет по умолчанию", () => {
  const loaded = open();
  loaded.dom.command({ id: "x", action: "live-colors", scope: "all", on: true, ring: { dark: [] } });
  assert.equal(loaded.api.status().live.on, false, "без кольца не включается");
  loaded.dom.command(baseCommand({ period: 5, mode: "нечто", light: "да" }));
  const status = loaded.api.status();
  assert.equal(status.live.period, 60, "период подтянут к минимуму");
  assert.equal(status.live.mode, "sync", "непонятный режим — общий круг");
  assert.equal(status.live.light, false, "непонятный свет — как окно сейчас");
  loaded.dom.command(baseCommand({ id: "big", period: 99999 }));
  assert.equal(loaded.api.status().live.period, 3600, "период подтянут к максимуму");
});

test("dispose снимает тик и сам объект", () => {
  const loaded = open();
  loaded.dom.command(baseCommand());
  assert.ok(loaded.dom.count("interval") >= 3);
  loaded.api.dispose();
  assert.equal(loaded.dom.count("interval"), 0, "после dispose интервалов нет");
  assert.equal(loaded.win.__myclaude, undefined);
});

test("повторный инжект не удваивает интервалы и поднимает крутёж из памяти", () => {
  const loaded = open();
  loaded.dom.command(baseCommand());
  const after = loaded.dom.count("interval");
  const again = loaded.reload();
  assert.equal(again.error, null);
  assert.ok(loaded.dom.count("interval") <= after, "второй инжект интервалы не удвоил");
  assert.equal(again.api.status().live.on, true);
});

test("чужая страница не красится и команду не берёт", () => {
  const loaded = loadInject({
    title: "Артефакт", href: "https://example.com/x",
    storage: { local: { "myclaude-live-v1": savedRing({ mode: "sync" }) } },
  });
  const status = loaded.api.status();
  assert.equal(status.live.on, false);
  assert.equal(status.theme.id, null);
  loaded.dom.command(baseCommand());
  assert.equal(loaded.api.status().live.on, false);
});

// Тик считается РАБОТОЙ, а не миллисекундами (#5683). Секундомер краснел на
// здоровой сборке, когда рядом шли другие агенты и swift build: замер плавал в
// шесть раз, а запас до потолка был всего вдвое. Числа ниже детерминированы —
// один мазок темы на тик и ни одного обхода страницы.
test("один тик — один мазок темы, страницу он не обходит", () => {
  const loaded = open();
  loaded.dom.command(baseCommand({ period: 60 }));
  const tickId = lastTick(loaded);
  // Записи в таблицы стилей: тема, шрифт и размер живут отдельными таблицами, и
  // тик обязан трогать только тему.
  let writes = 0;
  const sheets = loaded.win.CSSStyleSheet.prototype;
  const replaceSync = sheets.replaceSync;
  sheets.replaceSync = function counted(text) { writes += 1; return replaceSync.call(this, text); };
  // Прогревочный тик: на первом мазке садится грубый сектор круга, и полоса
  // прогресса переставляется один раз — это работа установки, а не тика.
  loaded.dom.fire(tickId);
  const paintsBefore = loaded.api.status().live.paints;
  const queriesBefore = loaded.dom.queries();
  const adopted = loaded.win.document.adoptedStyleSheets.length;
  writes = 0;
  for (let index = 0; index < 300; index += 1) loaded.dom.fire(tickId);
  sheets.replaceSync = replaceSync;
  assert.equal(loaded.api.status().live.paints - paintsBefore, 300, "каждый тик красит ровно раз");
  assert.equal(writes, 300, "на тик приходится одна запись в таблицу стилей, а не три");
  assert.equal(loaded.win.document.adoptedStyleSheets.length, adopted, "таблиц стилей за 300 тиков не прибавилось");
  // Обход страницы стоит дороже всего остального вместе взятого, поэтому его
  // здесь нет вовсе: пара поисков за 300 тиков — это редкая перестановка полосы
  // на смене сектора, а не работа каждого тика.
  const walks = loaded.dom.queries() - queriesBefore;
  assert.ok(walks <= 10, `тик обходит страницу: ${walks} поисков по дереву на 300 тиков`);
});

test("окно без заголовка: фаза временная, замок ставится по первому имени", () => {
  const loaded = loadInject({ title: "", href: "about:blank", storage: { local: { "myclaude-live-v1": savedRing() } } });
  const first = loaded.api.status().live.phase;
  assert.equal(loaded.api.status().live.on, true, "крутёж поднялся и без заголовка");
  assert.ok(loaded.api.status().live.paints >= 1, "окно покрашено сразу");
  assert.ok(near(first, 61), "фаза временная — хэш пустого имени");
  assert.equal(phaseRecord(loaded), null, "замка нет");
  loaded.document.title = "Позднее окно";
  tick(loaded);
  const second = loaded.api.status().live.phase;
  assert.ok(near(second, 115), "фаза пересчитана по настоящему заголовку");
  assert.equal(phaseRecord(loaded)?.key, "w:Позднее окно");
  loaded.document.title = "Совсем другой чат";
  tick(loaded);
  assert.equal(loaded.api.status().live.phase, second, "после защёлки заголовок фазу не двигает");
});

test("два безымянных окна расходятся, как только получают имена", () => {
  const local = { "myclaude-live-v1": savedRing() };
  const a = loadInject({ title: "", href: "about:blank", storage: { local } });
  const b = loadInject({ title: "", href: "about:blank", storage: { local } });
  assert.equal(a.api.status().live.phase, b.api.status().live.phase, "пока безымянны — в одной точке");
  a.document.title = "Позднее окно"; tick(a);
  b.document.title = "Второе окно"; tick(b);
  assert.notEqual(a.api.status().live.phase, b.api.status().live.phase, "с именами разъехались");
  assert.equal(phaseRecord(a)?.key, "w:Позднее окно");
  assert.equal(phaseRecord(b)?.key, "w:Второе окно");
});

test("новый список заголовков переставляет окно поверх замка", () => {
  const loaded = open({ title: "Dictatorik" });
  loaded.dom.command(baseCommand());
  assert.ok(near(loaded.api.status().live.phase, 120));
  loaded.dom.command(baseCommand({ id: "c2", titles: ["Dictatorik", "Trelvis"] }));
  assert.ok(near(loaded.api.status().live.phase, 0), "второй список — новая раскладка");
  assert.ok(near(phaseRecord(loaded)?.phase ?? -1, 0), "новая фаза записана в сессию");
  const other = open();
  other.dom.command(baseCommand());
  const first = other.api.status().live.phase;
  other.dom.command(baseCommand({ id: "c2", titles: ["Dictatorik", "PimpMyClaude"] }));
  assert.equal(other.api.status().live.phase, first, "окна нет в новом списке — фаза на месте");
});

test("главное окно: фаза запирается по первому настоящему заголовку", () => {
  const loaded = open({ title: "Claude", storage: { local: { "myclaude-live-v1": savedRing() } } });
  const stub = loaded.api.status().live.phase;
  assert.ok(near(stub, 95), "на заглушке фаза временная");
  assert.equal(phaseRecord(loaded), null, "замка на заглушке нет");
  loaded.document.title = "Trelvis";
  tick(loaded);
  const real = loaded.api.status().live.phase;
  assert.ok(near(real, 164), "первый настоящий заголовок защёлкнул фазу");
  assert.equal(phaseRecord(loaded)?.key, "main");
  for (const name of ["Dictatorik", "PimpMyClaude", "Claude", ""]) { loaded.document.title = name; tick(loaded); }
  assert.equal(loaded.api.status().live.phase, real, "смена чатов фазу больше не двигает");
});

test("первый мазок не затирает примерку темы", () => {
  const loaded = open();
  loaded.dom.command({
    id: "p1", action: "theme", at: "now", scope: "window", title: "Trelvis", preview: true,
    theme: { id: "preview", name: "Примерка", type: "dark", palette: { accent: "#ff0000", background: "#010203", foreground: "#ffffff", sidebar: "#000000", panel: "#000000", muted: "#888888" } },
  });
  assert.ok(loaded.dom.sheets().includes("#010203"));
  loaded.dom.command(baseCommand({ id: "c9" }));
  const status = loaded.api.status();
  assert.equal(status.live.on, true);
  assert.equal(status.live.paints, 0, "живые включились, но ни разу не покрасили");
  assert.equal(status.theme.source, "preview");
  assert.ok(loaded.dom.sheets().includes("#010203"), "примерка на экране цела");
  loaded.dom.command({ id: "p2", action: "theme", at: "now", scope: "window", title: "Trelvis", preview: false });
  tick(loaded);
  assert.equal(loaded.api.status().theme.source, "live", "после примерки живой цвет встал");
});

test("спрятанное окно получает первый мазок сразу", () => {
  const loaded = open();
  loaded.document.hidden = true;
  loaded.dom.command(baseCommand({ id: "h1" }));
  assert.equal(loaded.api.status().live.paints, 1, "к показу цвет уже верный");
});
