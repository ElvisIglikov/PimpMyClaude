// Цвета блоков кода (раздел 2а inject.js, WF34, задача #5365): палитра кода
// codePalette, слой codeCss, контраст подсветки и инлайн-чипа. Проверяется
// КОНТРАКТ, а не вкус: пороги читаемости (4,5 у токенов и чернил, 3,5 у
// комментария), состав селекторов и сторожа на чужие переменные Claude.
// Палитры берутся из claude-patch/themes.json — Элвис крутит их руками, и
// зашивать их сюда нельзя; зашиты только восемь исходных цветов One Dark,
// от которых считается «оттенок остался узнаваемым».
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { loadInner } from "./load.mjs";

const { inner } = loadInner({ title: "Trelvis" });
const { themeCss, epitaxyCss, codeCss, codePalette, contrastRatio, readableOn, hslTriple } = inner;

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
// Файл — объект {"version":1,"themes":[…]}, палитры лежат в .themes.
const THEMES = JSON.parse(readFileSync(path.join(ROOT, "claude-patch", "themes.json"), "utf8")).themes;
const DARK = THEMES.find(theme => theme.type === "dark");
const LIGHT = THEMES.find(theme => theme.type === "light");

// Восемь групп подсветки highlight.js «One Dark» — то, с чем страница живёт
// сегодня (разведка плана WF34, п. 2). Ключи — поля codePalette().tokens.
const ONE_DARK = {
  comment: "#5c6370", keyword: "#c678dd", name: "#e06c75", literal: "#56b6c2",
  string: "#98c379", number: "#d19a66", title: "#61aeee", builtin: "#e6c07b",
};
const TOKENS = Object.keys(ONE_DARK);
// Комментарий намеренно приглушён: у него своя цель и свой тон почти серый.
const BRIGHT = TOKENS.filter(name => name !== "comment");
const TARGET = 4.5;
const TARGET_COMMENT = 3.5;

const paletteInput = theme => ({
  type: theme.type,
  background: theme.palette.background,
  foreground: theme.palette.foreground,
  accent: theme.palette.accent,
});
const codeOf = theme => codePalette(paletteInput(theme));
// Подпись codeCss планом не заморожена (заморожены имена и поля палитры),
// поэтому зовём одним объектом, годным для любой разумной формы: в нём и
// палитра темы, и готовая палитра кода — россыпью и полем code.
const codeCssOf = theme => {
  const code = codeOf(theme);
  return codeCss({ ...paletteInput(theme), ...theme.palette, ...code, code });
};

// Правила режем механически, не построчно: селекторы Claude длинные, и правило
// целиком может стоять в одну строку.
const ruleBlocks = css => [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)]
  .map(([, selector, body]) => ({ selector: selector.replace(/\/\*[\s\S]*?\*\//g, "").trim(), body }));
// Запятая внутри :not(:is(a, b) *) селекторов не разделяет — считаем скобки.
const topParts = selector => {
  const parts = [];
  let depth = 0;
  let current = "";
  for (const symbol of selector) {
    if (symbol === "(") depth += 1;
    else if (symbol === ")") depth -= 1;
    if (symbol === "," && depth === 0) { parts.push(current.trim()); current = ""; continue; }
    current += symbol;
  }
  if (current.trim()) parts.push(current.trim());
  return parts;
};
// Правило, которое красит саму коробку или подсветку, — ему хвост обязателен.
const CODE_RULE = /\bpre\b|\.hljs|\.code-block__code/;
const hueOf = color => Number.parseFloat(hslTriple(color).split(" ")[0]);
const hueGap = (left, right) => {
  const gap = Math.abs(hueOf(left) - hueOf(right)) % 360;
  return gap > 180 ? 360 - gap : gap;
};

test("codeCss красит коробку и все восемь групп подсветки", () => {
  const css = codeCssOf(DARK);
  for (const selector of ["pre", ".hljs", ".code-block__code"]) {
    assert.ok(css.includes(selector), `коробка кода не покрашена: нет ${selector}`);
  }
  for (const group of [".hljs-keyword", ".hljs-string", ".hljs-comment", ".hljs-built_in",
    ".hljs-literal", ".hljs-number", ".hljs-title", ".hljs-name"]) {
    assert.ok(css.includes(group), `группа подсветки без правила: ${group}`);
  }
});

test("коробка кода красится подложкой из палитры", () => {
  for (const theme of [DARK, LIGHT]) {
    const css = themeCss(theme);
    const { surface } = codeOf(theme);
    assert.ok(css.includes(".hljs"), "слой кода не доехал до themeCss");
    assert.match(css, new RegExp(`background:\\s*${surface}\\s*!important`, "i"),
      `подложка коробки не равна surface (${surface}) темы ${theme.name}`);
  }
});

// Судья всех порогов ниже — contrastRatio, и до WF43 (#5759) он сам не был
// сверен ни с одним известным значением: снятие смещений 0,05 из формулы WCAG
// раздувало числа в разы, любой тёмный токен «проходил» 4,5, и гейт оставался
// зелёным на нечитаемых темах. Три опорные точки закрывают ровно это.
test("судья читаемости сверен: чёрное на белом — 21, серый WCAG — 4,54, цвет сам с собой — 1", () => {
  const near = (actual, expected, what) =>
    assert.ok(Math.abs(actual - expected) <= 0.01, `${what}: ${actual.toFixed(4)} вместо ${expected}`);
  near(contrastRatio("#000000", "#ffffff"), 21, "предельный контраст");
  near(contrastRatio("#ffffff", "#000000"), 21, "порядок цветов ничего не меняет");
  // #767676 на белом — канонический порог AA из WCAG: чуть темнее — уже провал.
  near(contrastRatio("#767676", "#ffffff"), 4.54, "серый на границе AA");
  near(contrastRatio("#777777", "#777777"), 1, "цвет сам с собой");
  assert.ok(contrastRatio("#757575", "#ffffff") >= TARGET, "на волосок темнее порога — проходит");
  assert.ok(contrastRatio("#777777", "#ffffff") < TARGET, "на волосок светлее порога — уже нет");
});

test("подсветка читается на всех 24 темах: токен ≥ 4,5, комментарий ≥ 3,5", () => {
  assert.equal(THEMES.length, 24, "палитр в themes.json стало другое число — пороги перепроверить");
  for (const theme of THEMES) {
    const { surface, tokens } = codeOf(theme);
    for (const name of BRIGHT) {
      const ratio = contrastRatio(tokens[name], surface);
      assert.ok(ratio >= TARGET, `${theme.name}: токен ${name} (${tokens[name]}) на ${surface} даёт ${ratio.toFixed(2)}`);
    }
    const comment = contrastRatio(tokens.comment, surface);
    assert.ok(comment >= TARGET_COMMENT, `${theme.name}: комментарий даёт ${comment.toFixed(2)}`);
  }
});

test("текст блока и инлайн-чип читаются на всех 24 темах", () => {
  for (const theme of THEMES) {
    const { surface, ink, chipInk } = codeOf(theme);
    const text = contrastRatio(ink, surface);
    const chip = contrastRatio(chipInk, surface);
    assert.ok(text >= TARGET, `${theme.name}: текст блока (${ink}) на ${surface} даёт ${text.toFixed(2)}`);
    assert.ok(chip >= TARGET, `${theme.name}: инлайн-чип (${chipInk}) на ${surface} даёт ${chip.toFixed(2)}`);
  }
});

test("оттенок подсветки остаётся узнаваемым", () => {
  for (const theme of THEMES) {
    const { tokens } = codeOf(theme);
    for (const name of BRIGHT) {
      const gap = hueGap(tokens[name], ONE_DARK[name]);
      assert.ok(gap <= 4, `${theme.name}: ${name} уехал по тону на ${gap.toFixed(2)}° (${ONE_DARK[name]} → ${tokens[name]})`);
    }
  }
});

test("в тёмных темах подсветка почти не двигается", () => {
  const darks = THEMES.filter(theme => theme.type === "dark");
  let same = 0;
  for (const theme of darks) {
    const { tokens } = codeOf(theme);
    for (const name of TOKENS) if (String(tokens[name]).toLowerCase() === ONE_DARK[name]) same += 1;
  }
  const total = darks.length * TOKENS.length;
  assert.ok(same >= 60, `One Dark уцелел лишь в ${same} значениях из ${total} — подсветка переехала целиком`);
});

test("readableOn не трогает достаточный цвет и не зацикливается", () => {
  // Контраст уже выше цели — тот же цвет, посимвольно, без хода через HSL.
  assert.equal(readableOn("#ffffff", "#000000", TARGET), "#ffffff");
  assert.equal(readableOn("#000000", "#ffffff", TARGET), "#000000");
  assert.equal(readableOn("#c678dd", "#221640", TARGET), "#c678dd", "тёмная тема: токен остаётся собой");
  // Цели не достичь — отдаём ЛУЧШИЙ из перепробованных, а не последний.
  for (const [color, background] of [["#000000", "#000000"], ["#ffffff", "#ffffff"], ["#808080", "#808080"]]) {
    const result = readableOn(color, background, 21);
    assert.match(result, /^#[0-9a-f]{6}$/, `не цвет: ${result}`);
    assert.ok(contrastRatio(result, background) + 1e-9 >= contrastRatio(color, background),
      `${color} на ${background}: ответ хуже исходного`);
    assert.equal(readableOn(color, background, 21), result, "два вызова — один ответ");
  }
  // Светлая подложка: зелёная строка One Dark обязана уехать в тёмную сторону.
  const pulled = readableOn("#98c379", "#f3e5db", TARGET);
  assert.notEqual(pulled, "#98c379", "на светлой подложке цвет обязан двинуться");
  assert.ok(contrastRatio(pulled, "#f3e5db") >= TARGET, `дотянули только до ${contrastRatio(pulled, "#f3e5db").toFixed(2)}`);
});

test("codeCss не переопределяет чужие переменные", () => {
  for (const theme of [DARK, LIGHT]) {
    const css = themeCss(theme);
    for (const name of ["--cds-alpha-", "--cds-bg-neutral", "--cds-text-danger", "--danger-000"]) {
      assert.ok(!css.includes(name), `${name} трогать нельзя: на ней держится половина страницы`);
    }
  }
});

test("инлайн-код красится переменными, а не своими фонами", () => {
  const css = themeCss(DARK);
  for (const name of ["--cds-prose-code-color:", "--code-chip-ink:", "--cds-editor-code-ink:"]) {
    assert.ok(css.includes(name), `нет код-переменной ${name}`);
  }
  assert.ok(!css.includes("code:not(pre code)"), "своё правило по инлайн-коду затопчет исключения Claude");
  assert.ok(!css.includes(".epitaxy-code-chip"), "чип Claude Code трогать не надо — у него свои правила");
});

test("в CSS блоков кода нет мусора и каждое правило с !important", () => {
  for (const theme of [DARK, LIGHT]) {
    const css = codeCssOf(theme);
    assert.ok(!/NaN|undefined|null/.test(css), "мусор в готовом CSS");
    const rules = ruleBlocks(css);
    assert.ok(rules.length >= 10, "правил кода подозрительно мало");
    for (const rule of rules) {
      for (const declaration of rule.body.split(";").map(part => part.trim()).filter(Boolean)) {
        assert.ok(declaration.includes("!important"), `правило без !important проиграет каскаду: ${declaration}`);
      }
    }
  }
});

test("diffs-container красится тем же цветом, что и блок кода", () => {
  for (const theme of [DARK, LIGHT]) {
    const css = themeCss(theme);
    const { surface } = codeOf(theme);
    for (const name of ["--diffs-dark-bg", "--diffs-light-bg"]) {
      assert.match(css, new RegExp(`${name}:\\s*${surface}\\b`, "i"),
        `${theme.name}: ${name} не равен surface (${surface}) — диффы и блоки кода разного цвета`);
    }
  }
});

test("epitaxyCss живёт без палитры кода", () => {
  let css = null;
  assert.doesNotThrow(() => { css = epitaxyCss({ type: "dark", ...DARK.palette }); }, "старый вызов без поля code");
  assert.ok(css.includes("--diffs-dark-bg"), "блоки кода Claude Code остались непокрашенными");
  assert.ok(!/NaN|undefined|null/.test(css));
});

test("цитата Claude Code берёт цвет темы", () => {
  const css = themeCss(DARK);
  const rule = ruleBlocks(css).find(block => block.selector.includes(".epitaxy-markdown blockquote"));
  assert.ok(rule, "цитата в окне Claude Code осталась «белыми 10 %»");
  assert.match(rule.body, /border-left-color\s*:/, "полоска цитаты не покрашена");
  assert.ok(!css.includes("--cds-alpha-2"), "альфа-переменные Claude трогать нельзя");
});

test("превью артефактов выключено у каждого правила кода", () => {
  for (const theme of [DARK, LIGHT]) {
    // Хвост нужен там, где мы красим саму коробку и подсветку: переменные
    // наследуются и внутри превью нужны, цитата и чернила инлайна с превью
    // не пересекаются.
    const rules = ruleBlocks(codeCssOf(theme))
      .filter(rule => !rule.selector.includes(":root") && CODE_RULE.test(rule.selector));
    assert.ok(rules.length >= 10, "коробка, рамка и восемь токенов — десять правил минимум");
    for (const rule of rules) {
      for (const part of topParts(rule.selector)) {
        assert.ok(part.includes(":not("), `правило без хвоста-выключателя: ${part}`);
        assert.ok(part.includes(".artifact-markdown-preview") && part.includes(".channel-artifact-markdown-preview"),
          `хвост не выключает превью артефактов: ${part}`);
      }
    }
  }
});

test("цвет коробки и рамка не задваиваются", () => {
  const rules = ruleBlocks(codeCssOf(DARK));
  const framed = rules.filter(rule => /(^|[\s;])border\s*:/.test(rule.body));
  assert.equal(framed.length, 1, "рамку рисует ровно одно правило — иначе двойная обводка у счётчика строк");
  assert.ok(framed[0].selector.startsWith("pre"), `рамка не у pre, а у «${framed[0].selector}»`);
  // Блок со счётчиком строк вложен в pre: своя рамка обвела бы его вторым кругом.
  for (const rule of rules.filter(rule => rule.selector.includes(".code-block__code"))) {
    assert.ok(!/border/.test(rule.body), `рамка у счётчика строк: ${rule.body.trim()}`);
  }
});
