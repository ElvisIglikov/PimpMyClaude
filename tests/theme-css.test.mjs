// Сборка CSS слоёв (раздел 2а inject.js): тема, блок Epitaxy, шрифт, размер,
// рамка и цветовая арифметика. Цвета проверяются как КОНТРАКТ — наличие
// переменных, диапазоны, отсутствие NaN, — а не как вкус: палитры Элвис крутит
// руками, и тесты не должны это запрещать.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInner } from "./load.mjs";

const { inner } = loadInner({ title: "Trelvis" });
const {
  themeCss, epitaxyCss, fontCss, sizeCss, frameShadow,
  normalizeTheme, normalizeFont, normalizeSize, normalizeHex, mixHex, hslTriple,
} = inner;

const palette = {
  accent: "#2299ff", background: "#001122", foreground: "#eeffff",
  sidebar: "#000811", panel: "#00223a", muted: "#88aabb",
};
const dark = { id: "море", name: "Море", type: "dark", palette };
const light = { id: "снег", name: "Снег", type: "light", palette: { ...palette, background: "#ffffff", foreground: "#111827" } };

test("themeCss даёт семантические --cds-* — без них не красятся попапы", () => {
  const css = themeCss(dark);
  for (const name of [
    "--cds-page-bg", "--cds-surface-1", "--cds-surface-panel", "--cds-surface-popover",
    "--cds-text-primary", "--cds-text-secondary", "--cds-border", "--cds-fill-accent", "--cds-clay",
  ]) assert.ok(css.includes(`${name}:`), `нет переменной ${name}`);
  assert.ok((css.match(/--cds-[\w-]+:/g) ?? []).length >= 20, "семантических переменных должно быть много");
});

test("themeCss несёт цвета палитры и схему по типу темы", () => {
  const css = themeCss(dark);
  assert.ok(css.includes("--claude-accent-clay: #2299ff !important;"));
  assert.ok(css.includes("--claude-background-color: #001122 !important;"));
  assert.ok(css.includes("color-scheme: dark !important;"));
  assert.ok(themeCss(light).includes("color-scheme: light !important;"));
  assert.ok(css.includes("--df-bg-sidebar: #000811 !important;"), "сайдбар красится своим цветом");
});

test("в теме нет ни NaN, ни undefined, и каждое правило с !important", () => {
  for (const theme of [dark, light]) {
    const css = themeCss(theme);
    assert.ok(!/NaN|undefined|null/.test(css), "мусор в готовом CSS");
    const declarations = css.match(/^\s*--[\w-]+:[^;]+;/gm) ?? [];
    assert.ok(declarations.length > 80, "переменных подозрительно мало");
    assert.ok(declarations.every(line => line.includes("!important")), "правило без !important проиграет каскаду");
  }
});

test("блок Epitaxy обязателен: без него поле ввода Claude Code остаётся серым", () => {
  const css = themeCss(dark);
  assert.ok(css.includes(".epitaxy-root"), "блока Epitaxy нет вовсе");
  assert.ok(css.includes("--surface-prompt-blur:"), "поверхности поля ввода не покрашены");
  assert.ok(css.includes("diffs-container"), "блоки кода (shadow DOM) не покрашены");
});

test("epitaxyCss выдаёт все 19 уровней серого и 10 ступеней альфы", () => {
  const css = epitaxyCss({ type: "dark", ...palette });
  const grays = css.match(/--_gray-\d+:/g) ?? [];
  assert.equal(grays.length, 19);
  assert.equal(new Set(grays).size, 19, "уровни не должны повторяться");
  const alphas = css.match(/--t\d:/g) ?? [];
  assert.equal(alphas.length, 10);
  assert.equal((css.match(/--z\d:/g) ?? []).length, 7, "ступени поверхностей");
  assert.ok(!/NaN/.test(css));
});

test("fontCss режет длинное имя семейства и подставляет стек", () => {
  const long = normalizeFont({ id: "x", family: "a".repeat(120) });
  assert.equal(long.family.length, 60, "имя длиннее 60 не пропускаем");
  const ui = fontCss({ id: "ui", family: "Inter", mono: false });
  assert.ok(ui.includes('"Inter", -apple-system, system-ui, sans-serif'), "стек UI");
  assert.ok(!ui.includes("--font-mono"), "пропорциональный шрифт в код не лезет");
  const mono = fontCss({ id: "mono", family: "SF Mono", mono: true });
  assert.ok(mono.includes("ui-monospace, SFMono-Regular, Menlo, monospace"), "стек mono");
  assert.ok(mono.includes("code, pre, kbd, samp"), "моно-шрифт добирается до блоков кода");
});

test("normalizeFont выкидывает из имени всё, чем можно закрыть правило CSS", () => {
  assert.equal(normalizeFont({ family: 'In"ter;}*' }).family, "In ter");
  // Белый список латинский: имя одними кириллическими буквами шрифтом не станет.
  assert.equal(normalizeFont({ family: "Шрифт" }), null);
  assert.equal(normalizeFont({ family: "   " }), null, "пустое имя — шрифта нет");
  assert.equal(normalizeFont({ family: 42 }), null);
  assert.equal(normalizeFont(null), null);
  assert.equal(normalizeFont(["Inter"]), null);
  assert.equal(normalizeFont({ family: "SF Mono" }).mono, false, "mono только по явному true");
});

test("sizeCss: половинки независимы, заголовки в em, код 0.9", () => {
  const answer = sizeCss({ answer: 18 });
  assert.ok(answer.includes("font-size: 18px !important"));
  assert.ok(!answer.includes("[data-user-message-bubble]"), "вопросы не тронуты");
  for (const [tag, scale] of [["h1", 1.6], ["h2", 1.35], ["h3", 1.18], ["h4", 1.05]]) {
    assert.ok(answer.includes(`font-size: ${scale}em !important`), `нет коэффициента ${tag}`);
  }
  assert.ok(answer.includes("font-size: 0.9em !important"), "код мельче текста");
  assert.ok(answer.includes("font-size: 1em !important"), "второй проход em у <pre><code> погашен");
  const question = sizeCss({ question: 12 });
  assert.ok(question.includes("[data-user-message-bubble]"));
  assert.ok(!question.includes("18px"));
  assert.ok(!/color|background/.test(sizeCss({ answer: 15, question: 15 })), "в слое размера цветов нет вовсе");
});

test("normalizeSize держит границы 11…24 и округляет", () => {
  assert.equal(normalizeSize({ answer: 15.6 }).answer, 16);
  assert.equal(normalizeSize({ answer: 10 }), null, "меньше 11 не бывает");
  assert.equal(normalizeSize({ answer: 25 }), null, "больше 24 не бывает");
  assert.equal(normalizeSize({ answer: "abc" }), null);
  assert.equal(normalizeSize({}), null);
  assert.equal(normalizeSize(null), null);
  assert.equal(normalizeSize({ answer: 11, question: 24 }).question, 24);
});

test("normalizeHex и normalizeTheme на мусоре не бросают и падают на фолбэк", () => {
  assert.equal(normalizeHex("#ABC", "#000000"), "#aabbcc", "короткая запись разворачивается");
  assert.equal(normalizeHex("#11223344", "#000000"), "#112233", "альфа отбрасывается");
  assert.equal(normalizeHex("не цвет", "#123456"), "#123456");
  assert.equal(normalizeHex(null, "#123456"), "#123456");
  assert.equal(normalizeHex(42, "#123456"), "#123456");
  assert.equal(normalizeTheme(null), null);
  assert.equal(normalizeTheme({ id: "нет палитры" }), null, "без палитры темы нет");
  assert.equal(normalizeTheme([1, 2]), null);
  const dirty = normalizeTheme({ id: "a*/b", name: 'x";}', type: "странный", palette: { accent: "мусор" } });
  assert.equal(dirty.type, "dark", "непонятный тип — тёмная");
  assert.equal(dirty.palette.accent, "#60a5fa", "цвет из фолбэка тёмной темы");
  assert.ok(!/[<>{};*\\/"']/.test(dirty.id + dirty.name), "знаки, которыми закрывают правило, вычищены");
  assert.doesNotThrow(() => themeCss(dirty));
});

test("frameShadow не теряет акцент", () => {
  const shadow = frameShadow("#ff8800");
  assert.equal((shadow.match(/#ff8800/g) ?? []).length, 3, "три тени одним цветом");
  assert.ok(shadow.startsWith("inset 0 0 0 2px"), "линия в две точки");
  assert.ok(!/NaN|undefined/.test(shadow));
});

test("mixHex и hslTriple считают, а не выдумывают", () => {
  assert.equal(mixHex("#000000", "#ffffff", 0), "#000000");
  assert.equal(mixHex("#000000", "#ffffff", 1), "#ffffff");
  assert.equal(mixHex("#000000", "#ffffff", 0.5), "#808080");
  assert.equal(mixHex("#001122", "#001122", 0.4), "#001122");
  assert.equal(hslTriple("#000000"), "0.000 0.000% 0.000%");
  assert.equal(hslTriple("#ffffff"), "0.000 0.000% 100.000%");
  assert.equal(hslTriple("#ff0000"), "0.000 100.000% 50.000%");
  const [hue, saturation, lightness] = hslTriple("#2299ff").split(" ");
  assert.ok(Number(hue) > 200 && Number(hue) < 220, "синий тон");
  assert.ok(Number.parseFloat(saturation) > 50);
  assert.ok(Number.parseFloat(lightness) > 40 && Number.parseFloat(lightness) < 70);
});
