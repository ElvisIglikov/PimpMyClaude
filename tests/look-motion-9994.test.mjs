// #9994 (слово Элвиса 16.10.2026 19:42: «эту анимацию отключить, чтобы оно не шевелилось… у людей бывают
// слабые компьютеры… настройку типа анимация, не анимация или просто статическая градиентная картинка»):
// ключ look.motion — "live" | "still" | "image", последним ключом объекта, только при aurora:true; нет ключа
// или мусор — "still". live — как было; still — тот же рисунок без кадров и Web Animations; image — один
// статичный градиент тонами схемы. Проверяем настоящим путём: команды через dom.command, экран —
// dom.sheets(), анимации — dom.running(), таймеры — dom.timers, состояние — api.status().
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const MAP_KEY = "myclaude-themes-v1";
const COLORS = { accent: "#1eff5a", muted: "#88aabb", foreground: "#ffffff", dark: true };
const open = (map = {}, extra = {}) => loadInject({
  title: "Trelvis", storage: { local: { [MAP_KEY]: JSON.stringify(map) } }, ...extra,
});
const stored = loaded => JSON.parse(loaded.win.localStorage.getItem(MAP_KEY) ?? "{}");
let seq = 0;
const send = (loaded, detail) => loaded.dom.command({
  id: `m9994-${++seq}`, action: "theme", at: "now", scope: "window", title: "Trelvis", ...detail,
});
const plainOf = value => JSON.parse(JSON.stringify(value));
// Правила самого фона: ::before/::after слоя подложки.
const layerRules = css => css.split("\n").filter(line => /:is\(\.dframe-root, \.epitaxy-chat-panel:not\(\.dframe-root \*\)\)::(?:before|after)\b/.test(line) && !line.startsWith("@"));

test("normalizeLook: motion — live | still | image, нет ключа или мусор — still, последним ключом и только при живом фоне", () => {
  const { inner } = open();
  for (const motion of ["live", "image"]) {
    const look = plainOf(inner.normalizeLook({ aurora: true, scheme: "sea", motion }));
    assert.equal(look.motion, motion);
    assert.deepEqual(Object.keys(look), ["aurora", "neon", "dense", "scheme", "motion"], "motion — после scheme, последним");
  }
  for (const junk of [undefined, null, "", "LIVE", " live", "anim", 1, true, {}, ["live"], "still"]) {
    const look = plainOf(inner.normalizeLook({ aurora: true, motion: junk }));
    assert.equal("motion" in look, false, `${JSON.stringify(junk)} → умолчание still, в объект не пишется`);
  }
  // «Светлячки» сняты (#11211): старая запись у людей — «стоит», крутилки отброшены.
  assert.deepEqual(Object.keys(plainOf(inner.normalizeLook({ aurora: true, motion: "fireflies", flySpeed: 1.2, flyChaos: 0.8 }))),
    ["aurora", "neon", "dense"], "fireflies → still");
  assert.deepEqual(Object.keys(plainOf(inner.normalizeLook({ aurora: true }))), ["aurora", "neon", "dense"],
    "схема и движение по умолчанию не пишутся (как шлёт Swift)");
  assert.deepEqual(plainOf(inner.normalizeLook({ dense: true, motion: "live" })), { aurora: false, neon: false, dense: true },
    "без живого фона ключа нет");
  assert.equal(inner.normalizeLook({ motion: "live" }), null, "одно движение без тумблеров — слоя нет");
});

test("lookCss: still — тот же рисунок, что live, но без кадров, animation-* и will-change", () => {
  const { inner } = open();
  for (const scheme of ["violet", "sea", "theme"]) {
    const live = inner.lookCss({ aurora: true, neon: false, dense: false, scheme, motion: "live" }, COLORS);
    const still = inner.lookCss({ aurora: true, neon: false, dense: false, scheme, motion: "still" }, COLORS);
    assert.ok(/@keyframes myclaude-aurora-a/.test(live), "live — с кадрами, как было");
    assert.ok(!/@keyframes|animation|will-change|transform/.test(still), `${scheme}: у «стоит» ни кадров, ни анимаций, ни transform`);
    // Те же пятна и лучи: фон обоих псевдоэлементов совпадает с живым.
    const backgrounds = css => [...css.matchAll(/::(before|after) \{ background: ([^;]*);/g)].map(match => `${match[1]}:${match[2]}`);
    assert.equal(backgrounds(still).length, 2);
    assert.deepEqual(backgrounds(still), backgrounds(live), `${scheme}: рисунок тот же`);
    assert.match(still, /:root \.dframe-root::before, :root \.dframe-root::after \{ inset: -22%; \}/, "та же геометрия слоя");
    // Всё остальное оформление (прозрачные поверхности, стекло меню) — как у живого.
    const rest = css => css.split("\n").filter(line => !/::(?:before|after)|@keyframes|@media \(prefers-reduced-motion|look-still/.test(line));
    assert.deepEqual(rest(still), rest(live));
  }
  const missing = inner.lookCss({ aurora: true, neon: false, dense: false }, COLORS);
  assert.equal(missing, inner.lookCss({ aurora: true, neon: false, dense: false, motion: "still" }, COLORS), "нет ключа — still");
});

test("lookCss: image — один статичный линейный градиент тонами схемы, без пятен, ::after, фильтров и анимаций", () => {
  const { inner } = open();
  const sea = inner.LOOK_SCHEMES.find(item => item.id === "sea");
  const css = inner.lookCss({ aurora: true, neon: false, dense: false, scheme: "sea", motion: "image" }, COLORS);
  const rules = layerRules(css);
  assert.equal(rules.length, 1, `один слой: ${rules}`);
  const [rule] = rules;
  assert.match(rule, /::before \{ content: ""; position: absolute; inset: 0; z-index: -1; pointer-events: none; background: linear-gradient\(135deg, /);
  assert.equal((rule.match(/gradient\(/g) ?? []).length, 1, "ровно один градиент");
  assert.ok(!/radial-gradient|conic-gradient|filter|blur|animation|transform|will-change/.test(rule), "без пятен, лучей, фильтров и движения");
  for (const tone of sea.tones) assert.ok(rule.includes(tone), `тон схемы ${tone}`);
  assert.ok(!rule.includes(COLORS.accent), "акцент темы не примешан");
  assert.ok(!/@keyframes|animation-|inset: -22%/.test(css), "кадров и раздутого слоя нет");
  const shares = [...rule.matchAll(/#[0-9a-f]{6} (\d+)%/g)].map(match => Number(match[1]));
  assert.ok(shares.length === 4 && Math.max(...shares) <= 20, `тише пиков пятен (38): ${shares}`);
  const light = layerRules(inner.lookCss({ aurora: true, neon: false, dense: false, scheme: "sea", motion: "image" }, { ...COLORS, dark: false }))[0];
  const lightShares = [...light.matchAll(/#[0-9a-f]{6} (\d+)%/g)].map(match => Number(match[1]));
  assert.ok(Math.max(...lightShares) < Math.max(...shares), "в светлой теме ещё тише, как пятна");
  const theme = layerRules(inner.lookCss({ aurora: true, neon: false, dense: false, scheme: "theme", motion: "image" }, COLORS))[0];
  assert.ok(theme.includes("#1eff5a") && theme.includes("hsl(from #1eff5a"), "«Как у темы» — от акцента");
  // Прозрачные поверхности окна — те же, иначе картинку не видно.
  assert.match(css, /\.epitaxy-chat-panel \{ --epitaxy-transcript-surface: transparent; \}/);
});

test("страница: старый look без ключа — стоит; still и image — ни кадров, ни Web Animations, ни отсчёта; live — как было", () => {
  const loaded = open({ "*": { look: { aurora: true, scheme: "forest" } } }, {
    html: dom => { dom.document.body.add("div", { class: "dframe-root" }); },
  });
  const status = () => plainOf(loaded.api.status().look);
  const anims = () => loaded.dom.running().filter(item => item.options?.pseudoElement);
  const idle = () => [...loaded.dom.timers.values()].filter(item => item.kind === "timeout" && item.ms === loaded.inner.LOOK_IDLE_MS);
  assert.equal(status().aurora, true);
  assert.equal(status().motion, "still", "запись до #9994 — новое умолчание «стоит»");
  assert.ok(!/@keyframes myclaude-aurora/.test(loaded.dom.sheets()), "кадров на экране нет");
  // «Уменьшить движение» и окно без фокуса — у «стоит» не заводят ни Web Animations, ни отсчёт.
  loaded.win.__reducedMotion = true;
  loaded.inner.heartbeatTick?.();
  loaded.document.hasFocus = () => false;
  loaded.win.dispatchEvent({ type: "blur" });
  assert.equal(anims().length, 0, "у «стоит» Web Animations не крутятся");
  assert.equal(idle().length, 0, "отсчёта без фокуса нет — двигать нечего");
  // live — прежнее поведение: Web Animations при «уменьшить движение» и отсчёт без фокуса.
  send(loaded, { scope: "all", look: { aurora: true, scheme: "forest", motion: "live" } });
  assert.equal(status().motion, "live");
  assert.equal(anims().length, 2, "live при «уменьшить движение» — Web Animations, как было");
  assert.equal(idle().length, 1, "live без фокуса — отсчёт, как было");
  assert.ok(/@keyframes myclaude-aurora-a/.test(loaded.dom.sheets()));
  // Обратно в «стоит»: Web Animations отменены, отсчёт снят.
  const rafs = loaded.counters.rafs;
  send(loaded, { scope: "all", look: { aurora: true, scheme: "forest", motion: "still" } });
  assert.equal(status().motion, "still");
  assert.equal(anims().length, 0, "переход в «стоит» отменяет Web Animations");
  assert.equal(idle().length, 0, "и снимает отсчёт");
  assert.ok(!/@keyframes|animation-name/.test(loaded.dom.sheets()));
  // Картинка: один слой, без кадров, анимаций и отсчёта.
  send(loaded, { scope: "all", look: { aurora: true, scheme: "forest", motion: "image" } });
  assert.equal(status().motion, "image");
  assert.equal(anims().length, 0);
  assert.equal(idle().length, 0);
  assert.ok(loaded.dom.sheets().includes("linear-gradient(135deg"), "картинка на экране");
  assert.equal(loaded.counters.rafs, rafs, "ни одного нового кадра rAF");
  assert.deepEqual(Object.keys(stored(loaded)["*"].look), ["aurora", "neon", "dense", "scheme", "motion"], "в карте — последним ключом");
  // Живой фон выключен — движение в status() по умолчанию.
  send(loaded, { scope: "all", look: null });
  assert.equal(status().motion, "still");
  loaded.api.dispose();
});

test("motion хранится как look: «всем окнам», примерка и themes-restore; окно берёт его у `*`", () => {
  const loaded = open({ "*": { look: { aurora: true, motion: "image" } } });
  assert.equal(loaded.api.status().look.motion, "image");
  send(loaded, { look: { aurora: true, motion: "live" } });
  assert.equal(stored(loaded)["chat:Trelvis"].look.motion, "live", "запись чата хранит своё");
  assert.equal(loaded.api.status().look.motion, "image", "но движение — от «Живого» панели (`*`), как схема (WF204)");
  send(loaded, { preview: true, look: { aurora: true, motion: "live" } });
  assert.equal(loaded.api.status().look.motion, "live", "примерка — ровно то, что примеряют");
  send(loaded, { preview: false });
  assert.equal(loaded.api.status().look.motion, "image");
  const restored = open();
  restored.dom.command({ id: "m9994-restore", action: "themes-restore", at: "now", scope: "all",
    entries: { "*": { look: { aurora: true, scheme: "sea", motion: "live" } } } });
  assert.deepEqual(plainOf(stored(restored)["*"].look), { aurora: true, neon: false, dense: false, scheme: "sea", motion: "live" });
  assert.equal(restored.api.status().look.motion, "live");
});
