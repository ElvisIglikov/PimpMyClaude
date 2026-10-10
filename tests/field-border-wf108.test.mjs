// #8128 (WF108, раздел 2а inject.js, epitaxyCss): на тёмно-красных темах рамка
// поля ввода сливалась с фоном поля (--surface-prompt-blur = panel). Слово
// Элвиса: «у темы красной, бордовой не видно… рамки поля ввода». Рамка там
// дотягивается светлотой до 3:1 к фону поля (в фокусе — до 3,6:1); остальные
// темы — побайтно как были. Палитры — из claude-patch/themes.json.
//
// Замер до правки (рамка / фон поля): «Красная» 1,83, «Малиновая» 1,64,
// «Коралл» 1,71, «Магма» 1,91; в фокусе 2,75 / 2,33 / 2,51 / 2,95.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { loadInner } from "./load.mjs";

const { inner } = loadInner({ title: "Trelvis" });
const { epitaxyCss, contrastRatio } = inner;
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const THEMES = JSON.parse(readFileSync(path.join(ROOT, "claude-patch", "themes.json"), "utf8")).themes;
const RED = ["red", "crimson", "coral", "magma"];
const BEFORE = { red: 1.83, crimson: 1.64, coral: 1.71, magma: 1.91 };

const borders = theme => {
  const css = epitaxyCss({ type: theme.type, ...theme.palette });
  const pick = name => css.match(new RegExp(`--${name}: (#[0-9a-f]{6}) !important`))?.[1];
  return { blur: pick("prompt-blur-inner-color"), focus: pick("prompt-focus-inner-color"), outer: pick("prompt-blur-outer-color") };
};
// Прежняя формула: замес акцента с фоном 0,55 (0,32 в фокусе).
const mix = (left, right, ratio) => {
  const rgb = hex => [1, 3, 5].map(at => Number.parseInt(hex.slice(at, at + 2), 16));
  const [a, b] = [rgb(left), rgb(right)];
  return `#${a.map((value, index) => Math.round(value + (b[index] - value) * ratio).toString(16).padStart(2, "0")).join("")}`;
};

test("#8128: тёмно-красные темы — рамка поля ≥ 3:1 к фону поля (в фокусе ≥ 3,6:1), до правки было < 2", () => {
  for (const id of RED) {
    const theme = THEMES.find(item => item.id === id);
    assert.ok(theme, `темы ${id} нет в themes.json`);
    const { panel, accent, background } = theme.palette;
    const before = contrastRatio(mix(accent, background, 0.55), panel);
    assert.equal(before.toFixed(2), BEFORE[id].toFixed(2), `${id}: замер «до» поехал`);
    const { blur, focus, outer } = borders(theme);
    assert.equal(outer, blur, `${id}: внешняя и внутренняя рамка разошлись`);
    assert.ok(contrastRatio(blur, panel) >= 3, `${id}: рамка ${blur} к полю ${panel} — ${contrastRatio(blur, panel).toFixed(2)}`);
    assert.ok(contrastRatio(focus, panel) >= 3.6, `${id}: рамка в фокусе ${focus} — ${contrastRatio(focus, panel).toFixed(2)}`);
    assert.ok(contrastRatio(blur, background) >= 3, `${id}: рамка к фону окна — ${contrastRatio(blur, background).toFixed(2)}`);
  }
});

test("#8128: не тёмно-красные темы (розовая, фуксия, лазер, светлые) — рамка прежняя, побайтно", () => {
  const others = THEMES.filter(theme => !RED.includes(theme.id));
  assert.ok(others.some(theme => theme.id === "pink") && others.some(theme => theme.type === "light"));
  for (const theme of others) {
    const { accent, background } = theme.palette;
    const { blur, focus } = borders(theme);
    assert.equal(blur, mix(accent, background, 0.55), `${theme.id}: рамка поменялась`);
    assert.equal(focus, mix(accent, background, 0.32), `${theme.id}: рамка в фокусе поменялась`);
  }
});
