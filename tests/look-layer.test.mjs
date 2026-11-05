// Слой оформления look (WF83, #7178–#7180): живой фон, неон и ретро-экран,
// плотный текст. Контракт плана WF83: поле `look` команды theme —
// объект {aurora, neon, dense} целиком (ключа нет — false), null — сброс;
// хранится в карте тем рядом с темой, те же ключи и приоритет, примерка
// работает, в status() — поле look. Слоя frame (неоновая рамка) с WF248 нет.
//
// Проверяем настоящим путём: команда идёт через dom.command, экран читается
// dom.sheets(), состояние — api.status(), память — localStorage окна.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const MAP_KEY = "myclaude-themes-v1";

const theme = (id, accent) => ({
  id, name: id, type: "dark",
  palette: { accent, background: "#001122", foreground: "#eeffff", sidebar: "#000811", panel: "#00223a", muted: "#88aabb" },
});

const open = (map = {}) => loadInject({
  title: "Trelvis",
  storage: { local: { [MAP_KEY]: JSON.stringify(map) } },
});
const stored = loaded => JSON.parse(loaded.win.localStorage.getItem(MAP_KEY) ?? "{}");
// Объект из песочницы vm — другого мира, deepEqual сравнивает и прототипы.
// Список схем (WF146) проверяется отдельно — здесь только состояние слоя.
const lookOf = loaded => {
  const { schemes, ...look } = JSON.parse(JSON.stringify(loaded.api.status().look));
  return look;
};

let seq = 0;
const send = (loaded, detail) => loaded.dom.command({
  id: `wf83-${++seq}`, action: "theme", at: "now", scope: "window", title: "Trelvis", ...detail,
});

test("живой фон: слой ставится, хранится рядом с темой и виден в status(); снятый frame старой записи уходит", () => {
  // Живой фон окну даёт «Живой» панели — look у `*` (WF204).
  const loaded = open({ "chat:Trelvis": { theme: theme("зелёная", "#1eff5a"), frame: true }, "*": { look: { aurora: true, scheme: "theme", motion: "live" } } });
  send(loaded, { look: { aurora: true, scheme: "theme", motion: "live" } });
  assert.deepEqual(lookOf(loaded), { aurora: true, neon: false, dense: false, scheme: "theme", motion: "live", source: "window" });
  assert.deepEqual(stored(loaded)["chat:Trelvis"].look, { aurora: true, neon: false, dense: false, scheme: "theme", motion: "live" },
    "отсутствующие ключи записаны как false — объект целиком");
  assert.equal(stored(loaded)["chat:Trelvis"].theme.id, "зелёная", "тему команда не тронула");
  assert.equal("frame" in stored(loaded)["chat:Trelvis"], false, "снятая рамка (WF248) из записи уходит при её правке");
  const css = loaded.dom.sheets();
  assert.ok(css.includes("myclaude-aurora-a") && css.includes("myclaude-aurora-b"), "два слоя пятен с разными периодами");
  assert.ok(css.includes("#1eff5a"), "схема «Как у темы» — пятна цветом акцента темы");
  assert.ok(!css.includes("repeating-linear-gradient"), "неона никто не просил");
});

test("живой фон (WF128): двигает только transform, opacity и filter, медленно; при prefers-reduced-motion — Web Animations", () => {
  const { inner } = open();
  const css = inner.lookCss({ aurora: true, neon: false, dense: false, motion: "live" },
    { accent: "#c674fe", muted: "#88aabb", foreground: "#ffffff", dark: true });
  const frames = css.match(/@keyframes[^{]+\{([^@]*)\}\s*\}/g) ?? [];
  assert.equal(frames.length, 2);
  for (const block of frames) {
    const props = [...block.matchAll(/([a-z-]+):/g)].map(match => match[1]);
    assert.ok(props.every(name => ["transform", "opacity", "animation-timing-function"].includes(name)), `в кадрах только композитор, без filter — без перерисовки (#9134): ${props}`);
  }
  assert.match(css, /@media \(prefers-reduced-motion: reduce\) \{[^}]*animation: none !important/,
    "«уменьшить движение» — CSS-кадров нет (их ужимает Claude), переливание — Web Animations");
  const periods = [...css.matchAll(/animation-duration: (\d+)s/g)].map(match => Number(match[1]) * 2);
  assert.ok(periods.length === 2 && periods.every(value => value >= 40 && value <= 70), `живо, но плавно — круг 40–70 с (#9115): ${periods}`);
  assert.match(css, /z-index: -1/, "подложка под всем, а не поверх текста");
  assert.ok(!/requestAnimationFrame/.test(css));
});

// WF241 (заметка Рика 11.10: «Мак греется… при живой теме»): плавные кадры собирали всё окно на каждый кадр
// экрана. Положение слоя меняется около 30 раз в секунду по той же кривой ease-in-out — не рывками
// 10 раз в секунду, как до #9134, и не на каждый кадр.
test("живой фон (WF241): кадры — около 30 положений в секунду по кривой ease-in-out; ноль возвращает плавные", () => {
  const { inner } = open();
  const { lookAuroraFrames, LOOK_AURORA, LOOK_AURORA_FPS } = inner;
  assert.equal(LOOK_AURORA_FPS, 30);
  for (const layer of LOOK_AURORA) {
    const frames = [...lookAuroraFrames(layer)];
    const spans = layer.keys.length - 1;
    const parts = (frames.length - 1) / spans;
    assert.ok(Number.isInteger(parts) && parts >= 8, `каждый переход разбит на отрезки: ${parts}`);
    assert.equal(frames[0].offset, 0);
    assert.equal(frames.at(-1).offset, 1);
    assert.ok(frames.every((frame, index) => index === 0 || frame.offset > frames[index - 1].offset), "кадры идут по порядку");
    const steps = frames.map(frame => Number(/^steps\((\d+), end\)$/.exec(frame.easing)?.[1]));
    assert.ok(steps.every(count => count >= 1), `внутри отрезка — ступени: ${frames[0].easing}`);
    const perSecond = steps[0] * parts * spans / (layer.ms / 1000);
    assert.equal(perSecond, 30, `ровно 30 положений в секунду у обоих слоёв — шагают в одни моменты: ${perSecond}`);
    // Опорные положения те же, что были: начало, середина, конец.
    const [x0, y0, s0, r0, o0] = layer.keys[0];
    assert.equal(frames[0].transform, `translate3d(${x0}%, ${y0}%, 0) scale(${s0}) rotate(${r0}deg)`);
    assert.equal(frames[0].opacity, o0);
    const [x1, y1, s1, r1, o1] = layer.keys[1];
    assert.equal(frames[parts].transform, `translate3d(${x1}%, ${y1}%, 0) scale(${s1}) rotate(${r1}deg)`);
    assert.equal(frames[parts].opacity, o1);
    // Кривая ease-in-out: у края перехода шаг в разы меньше, чем в середине — без рывка на развороте.
    const shift = index => Math.abs(Number(/translate3d\((-?[\d.]+)%/.exec(frames[index + 1].transform)[1]) - Number(/translate3d\((-?[\d.]+)%/.exec(frames[index].transform)[1]));
    assert.ok(shift(Math.floor(parts / 2)) > shift(0) * 3, `середина быстрее края: ${shift(Math.floor(parts / 2))} против ${shift(0)}`);
    assert.ok(Math.abs(shift(0) - shift(parts - 1)) < 0.05, "разгон и торможение симметричны");
    // Откат одной строкой: ноль — прежние три плавных кадра.
    const smooth = [...lookAuroraFrames(layer, 0)];
    assert.deepEqual(smooth.map(frame => frame.easing), ["ease-in-out", "ease-in-out", "ease-in-out"]);
    assert.deepEqual(smooth.map(frame => frame.offset), [0, 0.5, 1]);
  }
  const css = inner.lookCss({ aurora: true, neon: false, dense: false, motion: "live" }, { accent: "#c674fe", muted: "#88aabb", foreground: "#ffffff", dark: true });
  assert.equal((css.match(/animation-timing-function: steps\(\d+, end\)/g) ?? []).length, 62, "CSS-кадры — те же кадры, по 31 на слой");
  assert.ok(!/animation-timing-function: ease-in-out/.test(css));
  assert.equal(Math.round(inner.lookEase(0.5) * 1000), 500, "кривая симметрична");
  assert.ok(inner.lookEase(0.1) < 0.03 && inner.lookEase(0.9) > 0.97, "у краёв медленно");
});

test("живой фон (WF241): окно дольше LOOK_IDLE_MS без фокуса — фон стоит; фокус вернулся — идёт; без живого фона отсчёта нет", () => {
  const loaded = open({ "*": { look: { aurora: true, motion: "live" } } });
  const html = loaded.document.documentElement;
  const idle = () => [...loaded.dom.timers.values()].filter(item => item.kind === "timeout" && item.ms === loaded.inner.LOOK_IDLE_MS);
  assert.equal(loaded.inner.LOOK_IDLE_MS, 20000);
  assert.equal(idle().length, 0, "окно в фокусе — отсчёта нет");
  loaded.document.hasFocus = () => false;
  loaded.win.dispatchEvent({ type: "blur" });
  assert.equal(idle().length, 1, "фокус ушёл — отсчёт заведён");
  assert.equal(html.hasAttribute("data-myclaude-look-still"), false, "сразу фон не замирает");
  loaded.win.dispatchEvent({ type: "blur" });
  assert.equal(idle().length, 1, "второй blur отсчёт не задваивает");
  loaded.dom.fireKind("timeout");
  assert.equal(html.hasAttribute("data-myclaude-look-still"), true, "20 секунд без фокуса — кадры стоят");
  assert.equal(loaded.api.status().lookStill, true, "и это видно в status()");
  loaded.document.hasFocus = () => true;
  loaded.win.dispatchEvent({ type: "focus" });
  assert.equal(html.hasAttribute("data-myclaude-look-still"), false, "фокус вернулся — идёт дальше");
  assert.equal(loaded.api.status().lookStill, false);
  // Вернулся раньше срока — фон не замирал вовсе.
  loaded.document.hasFocus = () => false;
  loaded.win.dispatchEvent({ type: "blur" });
  loaded.document.hasFocus = () => true;
  loaded.win.dispatchEvent({ type: "focus" });
  assert.equal(idle().length, 0, "отсчёт снят");
  assert.equal(html.hasAttribute("data-myclaude-look-still"), false);
  // Скрытое окно стоит независимо от фокуса, как раньше.
  loaded.document.hidden = true;
  loaded.document.dispatchEvent({ type: "visibilitychange" });
  assert.equal(html.hasAttribute("data-myclaude-look-still"), true);
  loaded.document.hidden = false;
  loaded.document.dispatchEvent({ type: "visibilitychange" });
  assert.equal(html.hasAttribute("data-myclaude-look-still"), false);
  // Живой фон выключили — отсчёт без фокуса не нужен и снят.
  loaded.document.hasFocus = () => false;
  loaded.win.dispatchEvent({ type: "blur" });
  assert.equal(idle().length, 1);
  send(loaded, { scope: "all", look: null });
  assert.equal(idle().length, 0, "фона нет — отсчёта нет");
  loaded.win.dispatchEvent({ type: "blur" });
  assert.equal(idle().length, 0);
  // dispose снимает отсчёт.
  send(loaded, { scope: "all", look: { aurora: true, motion: "live" } });
  assert.equal(idle().length, 1, "фон включили в окне без фокуса — отсчёт заведён");
  loaded.api.dispose();
  assert.equal(idle().length, 0, "отсчёт пережил dispose");
});

test("живой фон (WF128): одна подложка на всё окно, панели — стекло, без линий и обводок", () => {
  const { inner } = open();
  const css = inner.lookCss({ aurora: true, neon: false, dense: false, motion: "live" },
    { accent: "#c674fe", muted: "#88aabb", foreground: "#ffffff", dark: true });
  assert.match(css, /:is\(\.dframe-root, \.epitaxy-chat-panel:not\(\.dframe-root \*\)\)::before/,
    "подложка — у .dframe-root, в попапе без него — у панели ленты");
  assert.match(css, /\.dframe-root \{ isolation: isolate; \}/);
  assert.match(css, /\.dframe-root :is\(\.dframe-content, \.dframe-content-inner, \.bg-surface-1\.h-full\.w-full\) \{ background: transparent !important; \}/,
    "основа и страница во всё окно (попап) не закрывают подложку");
  assert.match(css, /aside\.dframe-sidebar \{ background-color: transparent !important/, "левая панель прозрачна (#9104)");
  assert.match(css, /aside\.dframe-sidebar \{[^}]*box-shadow: none !important; border-color: transparent !important/);
  assert.match(css, /rounded-card[^{]*\{[^}]*outline: none !important; box-shadow: none !important/, "у карточки ленты нет обводки");
  assert.match(css, /:is\(\.cursor-zoom-in, \[data-cds-attachment\]\) \{ border-color: transparent !important; box-shadow: none !important/,
    "фото без обводок");
  assert.match(css, /:root\[data-myclaude-look-still\][^{]*::after \{ animation-play-state: paused !important; \}/);
  // Свёрнутая панель (147e758) скруглена и без темы: живой фон ставит тот же радиус 10 (WF136).
  assert.match(css, /\.dframe-root\[data-collapsed\] aside\.dframe-sidebar \{ border-radius: 10px !important; \}/);
  // Сила «не ярче»: доли пятен прежние, лучи тише пятен.
  const shares = [...css.matchAll(/#[0-9a-f]{6} (\d+)%/g)].map(match => Number(match[1]));
  assert.ok(shares.length && Math.max(...shares) <= 38, `не ярче прежнего: ${shares}`);
  const layout = inner.layoutCss();
  // #11216: линии между лентой и колонкой поля нет и без живого фона.
  assert.doesNotMatch(layout, /inset 1px 0 0 0/, "без живого фона вернулась линия у колонки поля");
});

test("#9104/#9105 (WF139): под полем, у краёв и в меню — не сплошные плашки, а подложка или стекло", () => {
  const { inner } = open();
  const css = inner.lookCss({ aurora: true, neon: false, dense: false, motion: "live" },
    { accent: "#c674fe", muted: "#88aabb", foreground: "#ffffff", dark: true });
  // Всё, что Claude заливает цветом ленты (дока, маска под ней, шторка), — прозрачно; слой темы
  // красит те же узлы по классу, поэтому правило сильнее его на тех же корнях.
  assert.match(css, /\.epitaxy-chat-panel \{ --epitaxy-transcript-surface: transparent; \}/);
  assert.match(css, /:is\(main\.dframe-content, \.dframe-pane-host, \.epitaxy-chat-panel\) \[class\*="--epitaxy-transcript-surface"\] \{ background-color: transparent !important; \}/);
  // #9127 (WF142): поле ввода — прозрачно, без стекла и размытия (подложку видно насквозь);
  // рамка спрятана цветом (тень не none — editorFrame); переменной заливки широкого вида нет.
  const field = css.match(/\[data-cds="ChatComposer"\] > div\[class\*="bg-surface"\] \{([^}]*)\}/)?.[1] ?? "";
  assert.match(field, /background-color: transparent !important; background-image: none !important/);
  assert.match(field, /-webkit-backdrop-filter: none !important; backdrop-filter: none !important/);
  assert.ok(!/blur\(|color-mix/.test(field), "у поля снова стекло");
  assert.match(field, /border-color: transparent !important; box-shadow: 0 0 0 0 transparent !important/);
  assert.ok(!/--myclaude-composer-fill/.test(css), "в широком виде поле снова залито переменной");
  // Меню и списки Claude — стекло, а не сплошная плашка.
  const menu = css.match(/:is\(\[role="menu"\][^{]*\{([^}]*)\}/)?.[1] ?? "";
  assert.match(menu, /backdrop-filter: blur\(\d+px\)/);
  assert.match(menu, /color-mix\(in oklab, var\(--cds-surface-3\) \d+%, transparent\)/);
  assert.match(css, /\.df-bottom-tray::before \{ border-color: transparent !important; \}/, "волоска над аккаунтом нет");
  // Без живого фона — ни одного из этих правил.
  const plainCss = inner.lookCss({ aurora: false, neon: false, dense: true },
    { accent: "#c674fe", muted: "#88aabb", foreground: "#ffffff", dark: true });
  assert.ok(!/backdrop-filter|--epitaxy-transcript-surface/.test(plainCss));
});

test("«уменьшить движение»: Web Animations теми же кадрами — пятна плывут (#9115)", () => {
  const loaded = loadInject({
    title: "Trelvis",
    html: dom => { dom.document.body.add("div", { class: "dframe-root" }); },
  });
  loaded.win.__reducedMotion = true;
  send(loaded, { scope: "all", look: { aurora: true, motion: "live" } });
  const running = () => loaded.dom.running().filter(item => item.options?.pseudoElement);
  assert.equal(running().length, 2, "::before и ::after у .dframe-root");
  for (const item of running()) {
    assert.ok(item.node.className.includes("dframe-root"));
    assert.equal(item.options.iterations, Infinity);
    assert.ok(item.options.duration >= 20000 && item.options.duration <= 35000, "живо, но плавно");
    assert.equal(item.frames.length, 31, "те же кадры, что у CSS: по 15 отрезков на переход");
    assert.ok(item.frames.every(frame => /^steps\(\d+, end\)$/.test(frame.easing)), "около 30 положений в секунду по кривой ease-in-out (WF241)");
    assert.equal(item.options.direction, "alternate");
    assert.ok(item.frames.every(frame => !("filter" in frame)), "без filter — без перерисовки");
    assert.ok(item.frames.every(frame => "transform" in frame), "пятна плывут и при «уменьшить движение»");
  }
  const calm = loaded.inner.auroraCalm;
  assert.equal(calm.anims.length, 2);
  send(loaded, { scope: "all", look: null });
  assert.equal(running().length, 0, "живой фон снят — анимаций нет");
  loaded.win.__reducedMotion = false;
  send(loaded, { scope: "all", look: { aurora: true, motion: "live" } });
  assert.equal(running().length, 0, "без «уменьшить движение» крутит CSS");
});

test("живой фон стоит в скрытом окне и идёт снова, когда окно показано", () => {
  const loaded = open({ "*": { look: { aurora: true, motion: "live" } } });
  send(loaded, { look: { aurora: true, motion: "live" } });
  const html = loaded.document.documentElement;
  assert.equal(html.hasAttribute("data-myclaude-look-still"), false);
  loaded.document.hidden = true;
  loaded.document.dispatchEvent({ type: "visibilitychange" });
  assert.equal(html.hasAttribute("data-myclaude-look-still"), true, "окно скрыто — кадры стоят");
  loaded.document.hidden = false;
  loaded.document.dispatchEvent({ type: "visibilitychange" });
  assert.equal(html.hasAttribute("data-myclaude-look-still"), false);
  assert.ok(loaded.dom.sheets().includes("myclaude-aurora-a"));
});

test("плотный текст: межстрочный и отступы меньше, размер шрифта не трогаем", () => {
  const { inner } = open();
  const css = inner.lookCss({ aurora: false, neon: false, dense: true },
    { accent: "#c674fe", muted: "#88aabb", foreground: "#ffffff", dark: true });
  assert.match(css, /line-height: 1\.34 !important/);
  assert.match(css, /margin-top: 0\.45em !important/);
  assert.ok(!/font-size/.test(css), "шрифт не меньше — правил font-size нет");
});

test("неон и ретро-экран (WF128) сняты: ключ хранится, страница его не рисует", () => {
  const loaded = open();
  send(loaded, { look: { neon: true, dense: true } });
  assert.deepEqual(lookOf(loaded), { aurora: false, neon: true, dense: true, scheme: "violet", motion: "still", source: "window" });
  assert.deepEqual(stored(loaded)["chat:Trelvis"].look, { aurora: false, neon: true, dense: true }, "формат прежний");
  const css = loaded.dom.sheets();
  assert.ok(!/repeating-linear-gradient/.test(css), "сканлайнов нет");
  assert.ok(!/text-shadow/.test(css.slice(css.indexOf("PimpMyClaude · оформление"))), "заголовки не светятся");
  assert.match(css, /line-height: 1\.34 !important/, "плотный текст на месте");
});

test("null и объект без единого true — сброс слоя, таблица уходит с экрана", () => {
  const loaded = open();
  send(loaded, { look: { aurora: true } });
  send(loaded, { look: null });
  assert.deepEqual(lookOf(loaded), { aurora: false, neon: false, dense: false, scheme: "violet", motion: "still", source: "window" });
  assert.equal(stored(loaded)["chat:Trelvis"], undefined, "пустая запись не хранится");
  assert.ok(!loaded.dom.sheets().includes("myclaude-aurora"), "живого фона на экране нет");

  const two = open();
  send(two, { look: { dense: true } });
  send(two, { look: { dense: false, aurora: "да" } });
  assert.equal(two.api.status().look.dense, false, "мусор и false — выключено");
  assert.equal(stored(two)["chat:Trelvis"], undefined);
});

test("поле look нет — слой не трогаем", () => {
  const loaded = open({ "chat:Trelvis": { look: { neon: true } } });
  assert.equal(loaded.api.status().look.neon, true, "восстановлено из карты");
  assert.equal(loaded.api.status().look.source, "chat");
  send(loaded, { frame: true });
  assert.equal(loaded.api.status().look.neon, true);
  assert.deepEqual(stored(loaded)["chat:Trelvis"].look, { neon: true });
});

test("примерка: только на экран, конец примерки возвращает сохранённое", () => {
  const loaded = open({ "chat:Trelvis": { look: { dense: true } } });
  send(loaded, { preview: true, look: { aurora: true } });
  assert.deepEqual(lookOf(loaded), { aurora: true, neon: false, dense: false, scheme: "violet", motion: "still", source: "preview" });
  assert.deepEqual(stored(loaded)["chat:Trelvis"].look, { dense: true }, "хранилище примерка не тронула");
  send(loaded, { preview: false });
  assert.deepEqual(lookOf(loaded), { aurora: false, neon: false, dense: true, scheme: "violet", motion: "still", source: "chat" });
  assert.ok(!loaded.dom.sheets().includes("myclaude-aurora"), "живой фон ушёл вместе с примеркой");
});

test("приоритет как у остальных слоёв: запись чата сильнее «всем»", () => {
  const loaded = open({ "*": { look: { neon: true } }, "chat:Trelvis": { look: { dense: true } } });
  assert.deepEqual(lookOf(loaded), { aurora: false, neon: false, dense: true, scheme: "violet", motion: "still", source: "chat" });
  const other = loadInject({ title: "Другой", storage: { local: { [MAP_KEY]: JSON.stringify({ "*": { look: { neon: true } } }) } } });
  assert.equal(other.api.status().look.neon, true);
  assert.equal(other.api.status().look.source, "all");
});

test("themes-restore доливает look, как frame", () => {
  const loaded = open();
  loaded.dom.command({ id: "r-look", action: "themes-restore", at: "now", scope: "all",
    entries: { "*": { look: { aurora: true } }, "chat:Trelvis": { look: { aurora: true, dense: true } } } });
  assert.deepEqual(stored(loaded)["chat:Trelvis"].look, { aurora: true, neon: false, dense: true });
  assert.equal(loaded.api.status().look.aurora, true);
});

test("схема «Как у темы»: смена темы перекрашивает живой фон новым акцентом", () => {
  const loaded = open();
  send(loaded, { theme: theme("первая", "#2299ff"), look: { aurora: true, scheme: "theme" } });
  assert.ok(loaded.dom.sheets().includes("#2299ff"));
  send(loaded, { theme: theme("вторая", "#ee88aa") });
  const css = loaded.dom.sheets();
  assert.ok(css.includes("#ee88aa") && !css.includes("color-mix(in oklab, #2299ff"), "пятна поехали за темой");
});

test("dispose уносит таблицу оформления", () => {
  const loaded = open();
  send(loaded, { look: { aurora: true, neon: true, dense: true } });
  loaded.api.dispose();
  assert.equal(loaded.counters.sheets, 0);
});

// WF146 (#9107): схема цвета живого фона — ключ look.scheme.
const COLORS = { accent: "#1eff5a", muted: "#88aabb", foreground: "#ffffff", dark: true };
const AURORA = { aurora: true, neon: false, dense: false };
const hexes = css => new Set([...css.matchAll(/color-mix\(in oklab, (#[0-9a-f]{6}) \d+%/g)].map(match => match[1]));

test("схемы живого фона (WF146): у каждой свои тона, доли прежние, акцент темы не нужен", () => {
  const { inner } = open();
  const schemes = inner.LOOK_SCHEMES;
  assert.ok(schemes.length >= 7 && schemes.length <= 9, "7–9 схем (#10015: девятая — «Тёплое свечение»)");
  assert.equal(schemes[0].id, "violet", "по умолчанию — фиолетовые сумерки первой");
  assert.equal(schemes.at(-1).id, "theme");
  const seen = new Set();
  for (const scheme of schemes.filter(item => item.tones)) {
    assert.equal(scheme.tones.length, 4, `${scheme.id}: четыре тона пятен`);
    const css = inner.lookCss({ ...AURORA, scheme: scheme.id }, COLORS);
    const used = hexes(css);
    assert.deepEqual([...used].sort(), [...scheme.tones].sort(), `${scheme.id}: пятна и лучи — тонами схемы`);
    assert.ok(!css.includes("#1eff5a"), `${scheme.id}: акцент темы не примешан`);
    const key = scheme.tones.join();
    assert.ok(!seen.has(key), `${scheme.id}: свои цвета`);
    seen.add(key);
    // Тихо: ни одного кислотного тона — насыщенность HSL не выше 75%.
    for (const hex of scheme.tones) {
      const [r, g, b] = [1, 3, 5].map(at => parseInt(hex.slice(at, at + 2), 16) / 255);
      const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2;
      const sat = max === min ? 0 : (max - min) / (1 - Math.abs(2 * l - 1));
      assert.ok(sat <= 0.8, `${scheme.id} ${hex}: мягкая насыщенность (${sat.toFixed(2)})`);
    }
    const shares = [...css.matchAll(/#[0-9a-f]{6} (\d+)%/g)].map(match => Number(match[1])).sort((a, b) => b - a);
    assert.deepEqual([...new Set(shares)], [38, 32, 30, 24, 9, 7], `${scheme.id}: доли прозрачности прежние — читаемость та же`);
  }
  const theme = inner.lookCss({ ...AURORA, scheme: "theme" }, COLORS);
  assert.ok(theme.includes("color-mix(in oklab, #1eff5a 38%") && theme.includes("hsl(from #1eff5a calc(h - 56) s l)"),
    "«Как у темы» — прежний вид от акцента");
});

test("схема: нет ключа или мусор — violet; violet в объект не пишется", () => {
  const { inner } = open();
  const violet = inner.lookCss({ ...AURORA, scheme: "violet" }, COLORS);
  for (const junk of [undefined, "", "кислота", 7, null, { id: "sea" }, " VIOLET "]) {
    assert.equal(inner.lookCss(inner.normalizeLook({ aurora: true, scheme: junk }), COLORS), violet, `мусор ${JSON.stringify(junk)} → violet`);
  }
  assert.deepEqual(JSON.parse(JSON.stringify(inner.normalizeLook({ aurora: true, scheme: "violet" }))), AURORA, "по умолчанию ключа нет — запись прежняя");
  assert.deepEqual(JSON.parse(JSON.stringify(inner.normalizeLook({ aurora: true, scheme: " sea " }))), { ...AURORA, scheme: "sea" });
  assert.equal(inner.normalizeLook({ scheme: "sea" }), null, "одна схема без тумблеров — слоя нет");
  const loaded = open();
  send(loaded, { look: { aurora: true, scheme: "кислота" } });
  assert.equal(loaded.api.status().look.scheme, "violet");
  assert.deepEqual(stored(loaded)["chat:Trelvis"].look, AURORA);
});

test("схема хранится как look: на чат, «всем», примерка и themes-restore", () => {
  const loaded = open({ "*": { look: { aurora: true, scheme: "forest" } } });
  assert.equal(loaded.api.status().look.scheme, "forest");
  assert.equal(loaded.api.status().look.source, "all");
  assert.ok(loaded.dom.sheets().includes("#7f9f6a"), "мох на экране");
  send(loaded, { look: { aurora: true, scheme: "sea" } });
  assert.deepEqual(stored(loaded)["chat:Trelvis"].look, { ...AURORA, scheme: "sea" });
  // WF204: схема живого фона — за «Живым» панели (`*`), запись чата её не перекрывает.
  assert.equal(loaded.api.status().look.scheme, "forest", "схема — от «всем окнам»");
  send(loaded, { preview: true, look: { aurora: true, scheme: "sunset" } });
  assert.equal(loaded.api.status().look.scheme, "sunset");
  assert.ok(loaded.dom.sheets().includes("#e6a07c"), "примерка — ровно то, что примеряют");
  assert.deepEqual(stored(loaded)["chat:Trelvis"].look, { ...AURORA, scheme: "sea" }, "примерка не пишет");
  send(loaded, { preview: false });
  assert.equal(loaded.api.status().look.scheme, "forest");
  send(loaded, { scope: "all", look: { aurora: true, scheme: "lavender" } });
  assert.deepEqual(stored(loaded)["*"].look, { ...AURORA, scheme: "lavender" }, "«всем окнам» — тем же путём");
  assert.equal(loaded.api.status().look.scheme, "lavender");
  assert.ok(loaded.dom.sheets().includes("#b29ee6"), "таблица пересобрана новой схемой");

  const restored = open();
  restored.dom.command({ id: "r-scheme", action: "themes-restore", at: "now", scope: "all",
    entries: { "*": { look: { aurora: true, scheme: "graphite" } }, "chat:Trelvis": { look: { aurora: true, scheme: "graphite" } } } });
  assert.deepEqual(stored(restored)["chat:Trelvis"].look, { ...AURORA, scheme: "graphite" });
  assert.equal(restored.api.status().look.scheme, "graphite");
  const list = JSON.parse(JSON.stringify(restored.api.status().look.schemes));
  assert.deepEqual(list.map(item => item.id), ["violet", "aurora", "sea", "lavender", "sunset", "forest", "graphite", "warm", "theme"]);
  assert.ok(list.every(item => typeof item.name === "string" && item.name && !("tones" in item)), "меню — id и название");
});
