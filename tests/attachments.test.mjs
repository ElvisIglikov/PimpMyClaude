// Вложения ПОЛЯ ВВОДА в узком окне (раздел 2а inject.js, WF61, задача #5912).
//
// Болезнь: у Claude плитка вложения в композере жёстко 120×120, а в окне 280 на
// поле остаётся 194 точки — в ряд встаёт ровно одна плитка. Пять скриншотов
// съедали всё окно: ни черновика, ни строки модели, печатать негде. В широком
// окне те же плитки ложатся сеткой, и там вид Claude обязан остаться прежним.
//
// Проверяется КОНТРАКТ правила, а не точные числа Claude:
//   1) селекторы целятся только в потомков поля ввода — лента разговора тем же
//      компонентом нарисована, и тронуть её нельзя;
//   2) всё живёт внутри @media по ширине окна, за его пределами — ни правила;
//   3) в узком окне в ряд встаёт несколько плиток, а весь блок вложений имеет
//      потолок высоты и свою прокрутку;
//   4) правило не лезет ни в высоту поля (это задача #5886), ни в кнопку снятия
//      вложения (по её подписи «Обкэшить» считает вложения), ни в переходы и
//      анимации Claude.
// Плюс живая часть: лист стилей ставится один раз при инжекте, на втором
// прогоне не удваивается, уходит по dispose и не ставится в артефакте.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner } from "./load.mjs";

const { inner } = loadInner({ title: "Trelvis" });
const { attachmentsCss } = inner;

// Замеры живьём (probe 12.09): окно Элвиса 280 точек — это 255–259 внутри, поле
// ввода 194; широкое окно 908 — это 829 внутри. Порог обязан лечь между ними.
const NARROW_WINDOW = 259;
const WIDE_WINDOW = 829;
const NARROW_FIELD = 194;
// Зазор между плитками у Claude — примерно столько; в ряд считаем с ним.
const GAP = 8;
// Столько плитка занимает у самого Claude (правило из ресурсов app.asar).
const CLAUDE_TILE = 120;
// Примета композера: любой наш селектор обязан начинаться с неё.
const COMPOSER = "[data-cds-composer-attachments]";

const css = attachmentsCss();
// Разбор: всё правило — один блок @media, внутри него обычные правила.
const media = css.match(/@media\s*\(max-width:\s*(\d+)px\)\s*\{([\s\S]*)\}\s*$/);
const threshold = media ? Number(media[1]) : null;
const rules = media
  ? [...media[2].matchAll(/([^{}]+)\{([^{}]*)\}/g)].map(item => ({
    selector: item[1].trim(),
    body: item[2].trim(),
  }))
  : [];
const ruleFor = part => rules.find(rule => rule.selector.includes(part)) ?? null;
const numberOf = (body, property) => {
  const hit = body.match(new RegExp(`${property}:\\s*(\\d+(?:\\.\\d+)?)px`));
  return hit ? Number(hit[1]) : null;
};

test("правило целится только в вложения ПОЛЯ ВВОДА — лента разговора не наша", () => {
  assert.ok(rules.length > 0, "правил не нашлось вовсе");
  for (const rule of rules) {
    // Список через запятую разбираем по частям: проверка «начинается с»
    // пропустила бы в ленту разговора весь хвост такого списка.
    for (const part of rule.selector.split(",").map(item => item.trim())) {
      assert.ok(part.startsWith(COMPOSER), `селектор «${part}» начинается не с приметы поля ввода`);
    }
  }
});

test("порог узкого окна — числом, и между окнами Элвиса", () => {
  assert.ok(threshold !== null, "@media по ширине окна не нашёлся");
  assert.ok(threshold > NARROW_WINDOW, `порог ${threshold} не накрывает узкое окно (${NARROW_WINDOW})`);
  assert.ok(threshold < WIDE_WINDOW, `порог ${threshold} задевает широкое окно (${WIDE_WINDOW})`);
});

test("в широком окне не меняется ничего: за @media нет ни одного правила", () => {
  const outside = css.slice(0, css.indexOf("@media"));
  assert.ok(!outside.includes("{"), `за пределами @media стоит правило: «${outside.trim()}»`);
  assert.equal((css.match(/@media/g) ?? []).length, 1, "блок @media должен быть один");
});

test("в узком окне в ряд встают несколько плашек, а не одна", () => {
  // Размер вложения в поле ввода задаёт класс `size-[120px]` на самой плашке
  // `[data-cds-attachment]` — замер живьём 12.09 23:37. `[data-cds-tile-media]`
  // в композере не встречается вовсе (он живёт в ленте разговора), и первая
  // версия правила целилась в него, то есть не меняла ничего.
  const tile = ruleFor("[data-cds-attachment]");
  assert.ok(tile, "правила плашки нет");
  const side = numberOf(tile.body, "width");
  assert.equal(side, numberOf(tile.body, "height"), "плитка обязана остаться квадратной");
  assert.ok(side < CLAUDE_TILE, `плитка ${side} не меньше сегодняшних ${CLAUDE_TILE} у Claude`);
  assert.ok(side >= 40, `плитка ${side} — это уже не картинка, а значок`);
  assert.ok(side * 3 + GAP * 2 <= NARROW_FIELD,
    `три плитки по ${side} с зазорами не встают в поле шириной ${NARROW_FIELD}`);
  // Свой min-* нужен на день, когда Claude допишет композеру нижнюю границу
  // размера (в ленте она у него уже есть) — иначе плитка перестанет ужиматься.
  assert.match(tile.body, /min-width:\s*0/);
  assert.match(tile.body, /min-height:\s*0/);
});

test("блок вложений не съедает окно: потолок высоты долей окна и своя прокрутка", () => {
  const box = rules.find(rule => rule.selector === COMPOSER);
  assert.ok(box, "правила самой коробки вложений нет");
  // Доля ОКНА (vh), а не точки Claude: у Элвиса окна разной высоты, и зашитое
  // число врало бы то в одну, то в другую сторону.
  const share = box.body.match(/max-height:\s*(\d+)vh/);
  assert.ok(share, `потолок высоты задан не долей окна: «${box.body}»`);
  assert.ok(Number(share[1]) >= 15 && Number(share[1]) <= 40,
    `потолок ${share[1]}vh — либо в нём не видно вложений, либо он не спасает поле`);
  assert.match(box.body, /overflow-y:\s*auto/, "что не влезло, коробка обязана прокручивать сама");
  // Прокрутка обрезает и по горизонтали (overflow-y:auto делает overflow-x из
  // visible тоже auto), а крестик «Remove» вылезает за плашку на 8 точек вверх —
  // без полей у верхнего ряда срезало бы половину кнопки.
  for (const side of ["padding-top", "padding-right"]) {
    const pad = box.body.match(new RegExp(`${side}:\\s*(\\d+)px`));
    assert.ok(pad, `у коробки нет ${side} — крестик снятия срежется прокруткой`);
    assert.ok(Number(pad[1]) >= 10, `${side} ${pad[1]} меньше вылета крестика (8 точек плюс запас)`);
  }
});

test("каждое объявление с !important — иначе правило Claude сильнее", () => {
  for (const rule of rules) {
    const declarations = rule.body.split(";").map(item => item.trim()).filter(Boolean);
    assert.ok(declarations.length > 0, `пустое правило «${rule.selector}»`);
    for (const line of declarations) {
      assert.ok(line.includes("!important"), `без !important: «${line}» (${rule.selector})`);
    }
  }
  assert.ok(!/NaN|undefined|null/.test(css), "мусор в готовом CSS");
});

test("лист ставится один раз при инжекте, не удваивается на втором прогоне и уходит по dispose", () => {
  const loaded = loadInject({ title: "Trelvis" });
  assert.equal(loaded.error, null);
  assert.ok(loaded.dom.sheets().includes(COMPOSER), "правила вложений нет в таблицах стилей окна");
  const sheets = loaded.counters.sheets;
  assert.ok(sheets >= 1);
  const again = loaded.reload();
  assert.equal(again.error, null);
  assert.equal(loaded.counters.sheets, sheets, "второй прогон таблицу удвоил");
  assert.ok(loaded.dom.sheets().includes(COMPOSER), "после второго прогона правило на месте");
  loaded.api.dispose();
  assert.ok(!loaded.dom.sheets().includes(COMPOSER), "правило осталось в окне после dispose");
});

test("в артефакте таблицы нет вовсе: поля ввода там не бывает", () => {
  const alien = loadInject({ href: "data:text/html,<p>артефакт</p>", title: "Артефакт" });
  assert.equal(alien.error, null);
  assert.ok(!alien.dom.sheets().includes(COMPOSER), "чужая страница получила наш лист стилей");
});
