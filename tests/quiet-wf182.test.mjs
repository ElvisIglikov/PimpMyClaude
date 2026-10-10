// WF182 (09.10.2026, слово Элвиса 03:15 по снимкам 39/41/42 и строке окна): тише — выделение
// чата слева, подложка реплики человека, выбранный значок Claude/Code (не белым); линия цитаты
// в свёртке — под центром ▾ в любом виде ленты. Геометрию CSS стаб не считает — правила
// сверяются текстом, замер ▾ — через страницу (canvas стаба).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const STYLE = "myclaude-input-handle-style";
const rules = loaded => (loaded.document.getElementById(STYLE)?.textContent ?? "").split("\n");
const ruleWith = (loaded, needle) => rules(loaded).filter(line => line.includes(needle));
const bodyOf = rule => rule.slice(rule.indexOf("{") + 1, rule.lastIndexOf("}"));
const stand = () => {
  const loaded = loadInject({ html: "composer", title: "Rick чат Элвиса" });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return loaded;
};
const share = (text, name) => Number(new RegExp(`${name}:color-mix\\(in oklab, var\\(--cds-text-primary, currentColor\\) ([\\d.]+)%, transparent\\)`).exec(text)?.[1]);

test("выделение чата слева вдвое тише прежних 9 %, наведение тише выделения, оба от цвета текста темы", () => {
  const loaded = stand();
  const [vars] = ruleWith(loaded, "aside.dframe-sidebar,aside.dframe-sidebar [data-row]{--df-selected:");
  assert.ok(vars);
  const selected = share(vars, "--df-selected");
  const hover = share(vars, "--df-hover");
  assert.ok(selected > 0 && selected <= 4.5, `выделение ${selected} %`);
  assert.ok(hover > 0 && hover < selected, `наведение ${hover} % тише выделения ${selected} %`);
});

test("подложка реплики человека — переменная Claude на самой реплике, вдвое тише его 5 % белого и цветом текста темы", () => {
  const loaded = stand();
  const found = ruleWith(loaded, '[data-cds="UserMessage"]{--cds-bg-user-message:');
  assert.equal(found.length, 1);
  assert.ok(!found[0].startsWith("@"), "во всех видах");
  const fill = share(bodyOf(found[0]), "--cds-bg-user-message");
  assert.ok(fill > 0 && fill <= 2.5, `подложка ${fill} %`);
  assert.ok(!/#fff|white|255/.test(found[0]), "не белым");
});

test("выбранный и наведённый значок Claude/Code — не белым: цвет соседних кнопок окна чуть ярче и тонкая подложка", () => {
  const loaded = stand();
  const [plain] = ruleWith(loaded, '[aria-label="Mode"] [role="radio"]{');
  assert.match(bodyOf(plain), /color:var\(--cds-text-secondary\) !important/, "невыбранный — как ←, →, сайдбар");
  const [active] = ruleWith(loaded, '[aria-label="Mode"] [role="radio"]:is([data-checked],:hover){');
  assert.ok(active, "правила выбранного нет");
  const body = bodyOf(active);
  assert.ok(!/neutral-900|#fff|white|--df-hover/.test(body), `не белым и не заливкой наведения Claude: ${body}`);
  assert.match(body, /color:color-mix\(in oklab, var\(--cds-text-secondary, currentColor\) 75%, var\(--cds-text-primary, currentColor\)\) !important/);
  const fill = share(body, "background");
  assert.ok(fill > 0 && fill <= 8, `подложка ${fill} %`);
});

test("тело свёртки: волосок 1,5 px и отступ от замера ▾ — и в прозе Code, и в любом другом виде ленты", () => {
  const loaded = stand();
  const found = rules(loaded).find(line => line.includes('blockquote[data-myclaude-fold-body]{margin-left:calc(var(--myclaude-fold-mid'));
  assert.ok(found, "правила тела свёртки нет");
  const selectors = found.slice(0, found.indexOf("{")).split(",");
  assert.ok(selectors.includes("blockquote[data-myclaude-fold-body]"), "не только проза Code");
  const body = bodyOf(found);
  assert.match(body, /margin-left:calc\(var\(--myclaude-fold-mid, 7\.4px\) - \.75px\) !important/, "центр линии = замер ▾ (половина волоска — влево)");
  assert.match(body, /border-left-width:1\.5px !important/);
});
