// Нижняя строка поля ввода (раздел 12з¹ inject.js, #7206, WF84): вариант 8.1
// макета docs/8-footer-opus-5.5.html — мельче (10 px в узком окне, 11 в
// широком), кнопки 16×16, в узком окне и в тесной строке подписи коротко («O55 · HI · AC», #7638, #8732).
// Микрофон Claude и его стрелка ⌄ спрятаны СТИЛЕМ (ответ Элвиса 8.2) — узел
// кнопки жив: его жмёт наш микрофон у кружка в режиме «claude» (#7054).
//
// Проверяется контракт раздела: какие узлы строки получают какую метку и
// какую короткую подпись, что правила стилей бьют только в помеченное, что
// смена подписи Claude меняет и короткую форму, и что dispose() метки снимает.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";

// Строка модели Claude Code: слева «+ 🎤 ⌄ Accept edits», справа «Opus 5.5 ·
// High · ◑». Подписи — настоящими текстовыми узлами, как у React.
const stand = ({ chevron = true, apart = false, guards = false } = {}) => dom => {
  const parts = dom.composer({ top: 600 });
  const chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" } });
  const left = chin.add("div", { class: "ps-[var(--cmp-chin-start)]" });
  const plus = left.add("button", { attrs: { "aria-label": "Add files" } });
  plus.add("svg");
  const micShell = left.add("span");
  const mic = micShell.add("button", { attrs: { "aria-label": "Press and hold to record" } });
  mic.add("svg");
  // guards — открытое меню Base UI вставило сторожа фокуса рядом с кнопками (#9055, WF144).
  const guard = host => host.add("span", { attrs: { "data-base-ui-focus-guard": "", tabindex: "0", "aria-hidden": "true" } });
  if (guards) { guard(micShell); guard(left); }
  // apart — как на живом Claude 23.09: между микрофоном и стрелкой чужой узел,
  // у стрелки ни меню, ни соседства — только подпись «Dictation settings».
  if (apart) left.add("span", { attrs: { "data-divider": "" } });
  const arrowHost = apart ? left.add("div") : left;
  const arrow = chevron
    ? arrowHost.add("button", { attrs: apart ? { "aria-label": "Dictation settings" } : { "aria-haspopup": "menu", "aria-label": "Dictation settings" } })
    : null;
  arrow?.add("svg");
  const mode = left.add("button", { attrs: { "aria-haspopup": "menu" } });
  mode.add("svg");
  const modeText = dom.leaf(mode, "span", "Accept edits");
  const right = chin.add("div");
  const model = right.add("button", {
    attrs: { "data-testid": "epitaxy-cds-model-selector", "aria-label": "Model: Opus 5.5", "aria-haspopup": "menu" },
  });
  const modelText = dom.leaf(model, "span", "Opus 5.5");
  const effort = right.add("button", { attrs: { "aria-label": "Effort: High", "aria-haspopup": "dialog" } });
  const effortText = dom.leaf(effort, "span", "High");
  const ring = right.add("button", { attrs: { "aria-haspopup": "dialog", "aria-label": "Usage: Context 300k / 1M (30%)" } });
  ring.add("svg");
  return { ...parts, chin, left, right, plus, micShell, mic, arrowHost, arrow, mode, modeText, model, modelText, effort, effortText, ring };
};
const open = options => loadInject({ title: "Trelvis", html: stand(options), geometry: { viewport: { width: 400, height: 800 } } });
const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const mark = node => node.getAttribute("data-myclaude-chin");
const short = node => node.getAttribute("data-myclaude-short");
const tail = node => node.getAttribute("data-myclaude-short-tail");

test("короткие имена (#9181, WF179): голова крупно, хвост мелко — Opus 5.5 → Оп + 5.5, Fable → Ф + Б, Sonnet → S + N, Haiku → Х; новой модели — буква и номер с точкой, без номера — не сокращаем", () => {
  const { inner } = loadInner();
  assert.deepEqual(["Opus 5.5", "Fable 5.1", "Sonnet 5", "Haiku 4.5", "Sonnet 4.5", "Opus 6", "Nova 2.0.1"].map(text => plain(inner.chinModelParts(text))),
    // WF179 (слово Элвиса 09.10 02:50: «О — непонятно, как ноль; „Оп“ — опус, и мелко 5.5»): Opus — две буквы.
    [["Op", "5.5"], ["Ф", "Б"], ["S", "N"], ["Х", ""], ["S", "N"], ["Op", "6"], ["N", "2.0.1"]]);
  assert.deepEqual(["Opus 5.5", "Fable 5.1", "Haiku 4.5"].map(inner.chinModelShort), ["Op5.5", "ФБ", "Х"]);
  assert.equal(inner.chinModelShort("Opus"), null, "номера нет — подпись остаётся полной");
  assert.deepEqual(["Low", "Medium", "High", "Extra", "Max", "xhigh"].map(inner.chinEffortShort),
    ["Lo", "Me", "Hi", "Ex", "Mx", "Ex"], "эффорты — две буквы, первая заглавная, вторая строчная (WF183, слово Элвиса 09.10 03:15)");
  assert.equal(inner.chinEffortShort("Ultra"), "Ul", "незнакомый эффорт — тоже «Хх»");
  assert.deepEqual(["Auto", "Accept edits", "Ask permissions", "Plan mode", "Bypass permissions"].map(inner.chinModeShort),
    ["Au", "Ac", "As", "Pl", "By"], "код режима — прежний: им пользуются «Включить» и сторож режима; в подпись — как есть (WF183)");
  assert.equal(inner.chinModeShort("Что-то своё"), null, "незнакомый режим не выдумываем");
});

test("метки строки: плюсик — значок 16×16, микрофон и ⌄ спрятаны, подписи коротко, кружок не тронут", () => {
  const loaded = open();
  const parts = loaded.parts;
  assert.equal(loaded.error, null);
  assert.equal(mark(parts.plus), "icon");
  assert.equal(mark(parts.micShell), "hide", "микрофон прячется вместе с обёрткой");
  assert.equal(mark(parts.arrow), "hide", "и стрелка настроек диктовки рядом с ним");
  assert.equal(parts.mic.isConnected, true, "кнопка Claude в разметке — её жмёт микрофон у кружка (#7054)");
  assert.equal(mark(parts.mode), "text");
  assert.equal(short(parts.modeText), "Ac", "Accept edits → Ac (WF183: первая заглавная, вторая строчная)");
  assert.equal(short(parts.modelText), "Op", "Opus — «Op» (04:05), не «O», похожая на ноль");
  assert.equal(tail(parts.modelText), "5.5", "хвост номера — отдельным атрибутом, мельче головы");
  assert.equal(tail(parts.effortText), null, "у эффорта хвоста нет");
  assert.equal(short(parts.effortText), "Hi");
  assert.equal(parts.ring.hasAttribute("data-myclaude-chin"), false, "кружок контекста — свой раздел, его не трогаем");
  assert.equal(parts.modelText.textContent, "Opus 5.5", "подпись Claude не переписана — её держит React");
});

test("правила: прячут и ужимают только помеченное; узкое окно — 10 px и короткая подпись из атрибута", () => {
  const { inner } = loadInner();
  const css = plain(inner.RULES).join("\n");
  assert.match(css, /\[data-cds="ChatComposerChin"\] \[data-myclaude-chin="hide"\]\{display:none !important\}/);
  assert.match(css, /\[data-myclaude-chin="text"\]\{font-size:11px !important;line-height:16px !important;height:16px/);
  assert.match(css, /\[data-myclaude-chin="icon"\]\{width:16px !important;min-width:16px !important;height:16px/);
  assert.match(css, /\[data-myclaude-chin="icon"\] svg\{width:13px !important;height:13px !important\}/);
  assert.match(css, /@media \(max-width:299px\)\{[^}]*\[data-myclaude-chin="text"\]\{font-size:10px !important;/);
  assert.match(css, /\[data-myclaude-short\]::after\{content:attr\(data-myclaude-short\);font-size:10px !important/);
  // Подпись модели с хвостом (#9181): голова ::before, хвост ::after мельче (10/8, узкое — 10/7.5); с WF195 — при
  // любой ширине строки, не только в тесной.
  assert.match(css, /\[data-cds="ChatComposerChin"\] \[data-myclaude-short-tail\]::before\{content:attr\(data-myclaude-short\);font-size:10px !important/);
  assert.match(css, /\[data-cds="ChatComposerChin"\] \[data-myclaude-short-tail\]::after\{content:attr\(data-myclaude-short-tail\);font-size:8px !important/);
  assert.match(css, /@media \(max-width:299px\)\{[^}]*\[data-myclaude-short-tail\]\[data-myclaude-short\]::before\{content:attr\(data-myclaude-short\);font-size:10px !important/);
  assert.doesNotMatch(css, /Press and hold to record"\]\{display:none/, "кнопку прячем меткой, а не выкидываем");
});

test("React сменил модель — короткая подпись за ней; dispose() снимает все метки", () => {
  const loaded = open();
  const { modelText, model } = loaded.parts;
  loaded.dom.retext(modelText, "Sonnet 4.5");
  settle(loaded);
  assert.equal(short(modelText), "S");
  assert.equal(tail(modelText), "N");
  loaded.dom.retext(modelText, "Haiku 4.5");
  settle(loaded);
  assert.equal(short(modelText), "Х");
  assert.equal(tail(modelText), null, "хвоста нет — атрибут снят");
  loaded.dom.retext(modelText, "Opus");
  settle(loaded);
  assert.equal(modelText.hasAttribute("data-myclaude-short"), false, "без номера — метка снята, подпись полная");
  assert.equal(modelText.hasAttribute("data-myclaude-short-tail"), false);
  assert.equal(mark(model), "text");
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll("[data-myclaude-chin],[data-myclaude-short],[data-myclaude-short-tail]").length, 0);
});

test("рядом с микрофоном нет стрелки — соседнюю кнопку с подписью не прячем", () => {
  const loaded = open({ chevron: false });
  assert.equal(mark(loaded.parts.micShell), "hide");
  assert.equal(mark(loaded.parts.mode), "text", "режим остался на виду");
});

test("#7206: стрелка «Dictation settings» спрятана и не рядом с микрофоном — по подписи, с обёрткой", () => {
  const loaded = open({ apart: true });
  const { arrow, arrowHost, mode } = loaded.parts;
  assert.equal(loaded.error, null);
  assert.equal(mark(arrowHost), "hide", "обёртка из одной стрелки прячется целиком");
  assert.equal(arrow.hasAttribute("data-myclaude-chin"), false, "кнопка внутри спрятанного не метится «icon»");
  assert.equal(mark(mode), "text", "режим на виду");
});

test("#7206: обёртки кнопок с подписью — «row»; сама строка и кружок не метятся", () => {
  const loaded = open();
  const { chin, left, right, ring, mode, model, effort } = loaded.parts;
  assert.equal(mark(left), "row");
  assert.equal(mark(right), "row", "группа модели и эффорта — тоже ряд, хоть в ней и кружок");
  assert.equal(chin.hasAttribute("data-myclaude-chin"), false, "строку Claude не трогаем");
  assert.equal(ring.hasAttribute("data-myclaude-chin"), false);
  assert.deepEqual([mode, model, effort].map(mark), ["text", "text", "text"], "все три подписи помечены, ряд их не заслонил");
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll("[data-myclaude-chin]").length, 0, "dispose снимает и «row»");
});

test("#7206: короткие подписи не режутся — кнопка не уже текста, при нехватке места ужимаются зазоры", () => {
  const { inner } = loadInner();
  const css = plain(inner.RULES).join("\n");
  const text = css.split("\n").find(line => line.includes('[data-myclaude-chin="text"]{flex-shrink:0'));
  assert.ok(text, "правила «не ужимать» нет");
  for (const part of ["flex-shrink:0 !important", "min-width:max-content !important", "white-space:nowrap !important", "overflow:visible !important"]) {
    assert.ok(text.includes(part), `у кнопки с подписью нет ${part}`);
  }
  assert.match(css, /\[data-myclaude-chin="text"\] \*\{[^}]*text-overflow:clip !important/, "подпись внутри без многоточия");
  assert.match(css, /\[data-myclaude-chin="row"\]\{min-width:min-content !important[;}]/, "обёртка не уже своих кнопок");
  const narrow = css.split("\n").find(line => line.startsWith("@media (max-width:299px)"));
  assert.match(narrow, /\[data-myclaude-chin="text"\]\{font-size:10px !important;padding-left:3px !important;padding-right:3px !important\}/,
    "узкое окно: поля кнопок тоньше");
  assert.match(narrow, /\[data-myclaude-chin="row"\][^{]*\{gap:2px !important;column-gap:2px !important\}/, "и зазоры 2 px");
  assert.doesNotMatch(css, /data-myclaude-chin="text"\][^{]*\{[^}]*text-overflow:ellipsis/, "многоточия у подписей нет");
});

test("#7206: совсем узкое окно (уже 260, WF94) — поля подписей и зазоры по 1 px", () => {
  const { inner } = loadInner();
  const css = plain(inner.RULES).join("\n");
  const tiny = css.split("\n").find(line => line.startsWith("@media (max-width:259px)"));
  assert.ok(tiny, "правила совсем узкого окна нет");
  assert.match(tiny, /\[data-myclaude-chin="text"\]\{padding-left:1px !important;padding-right:1px !important\}/);
  assert.match(tiny, /\[data-myclaude-chin="row"\][^{]*\{gap:1px !important;column-gap:1px !important\}/);
  const narrowAt = css.indexOf("@media (max-width:299px)");
  assert.ok(narrowAt >= 0 && narrowAt < css.indexOf("@media (max-width:259px)"), "узкое правило раньше — совсем узкое его перебивает");
});

test("#7638, #8732: подписи коротко, только когда полные не влезли в строку; хватает места — полные, с запасом против дребезга", () => {
  const loaded = open();
  const { chin, left, right, modeText } = loaded.parts;
  const narrow = () => chin.hasAttribute("data-myclaude-chin-narrow");
  left.rect = { left: 492, top: 700, width: 60, height: 24 };
  // Окно Рика 04.10: строка 317 при открытой боковой панели, «Auto · Opus 5.5 · Extra» и кружок влезают.
  chin.rect = { left: 455, top: 700, width: 317, height: 24 };
  right.rect = { left: 629, top: 700, width: 125, height: 24 };
  settle(loaded);
  assert.equal(narrow(), false, "влезает — «Opus 5.5 Extra» полностью (слово Элвиса 04.10 02:25)");
  // Строку сжали: правая группа вылезла за край на 18 — кружок режется.
  chin.rect = { left: 455, top: 700, width: 280, height: 24 };
  right.rect = { left: 628, top: 700, width: 125, height: 24 };
  settle(loaded);
  assert.equal(narrow(), true, "не влезло — коротко");
  // С короткими подписями группа уже; строка чуть шире нужных 298, но меньше запаса — не дёргаемся.
  right.rect = { left: 650, top: 700, width: 80, height: 24 };
  chin.rect = { left: 455, top: 700, width: 302, height: 24 };
  settle(loaded);
  assert.equal(narrow(), true, "запас 8 px: 302 < 298 + 8 — остаёмся на коротких");
  chin.rect = { left: 455, top: 700, width: 317, height: 24 };
  settle(loaded);
  assert.equal(narrow(), false, "строка снова 317 — полные подписи вернулись");
  // Сменилась подпись, пока коротко, — меряем заново, а не верим старой ширине.
  chin.rect = { left: 455, top: 700, width: 280, height: 24 };
  right.rect = { left: 628, top: 700, width: 125, height: 24 };
  settle(loaded);
  assert.equal(narrow(), true);
  right.rect = { left: 600, top: 700, width: 125, height: 24 };
  loaded.dom.retext(modeText, "Auto");
  settle(loaded);
  assert.equal(narrow(), false, "подпись стала короче и всё влезло — полные");
  const css = plain(loaded.inner.RULES).join("\n");
  // С WF195 короткие подписи — всегда: метка тесной строки ужимает только поля и зазоры.
  assert.match(css, /\[data-cds="ChatComposerChin"\] \[data-myclaude-short\]::after\{content:attr\(data-myclaude-short\);font-size:11px/);
  assert.doesNotMatch(css, /\[data-myclaude-chin-narrow\] \[data-myclaude-short/, "короткие подписи снова только в тесной строке");
  chin.rect = { left: 455, top: 700, width: 280, height: 24 };
  right.rect = { left: 628, top: 700, width: 125, height: 24 };
  settle(loaded);
  assert.equal(narrow(), true);
  loaded.api.dispose();
  assert.equal(narrow(), false, "dispose снимает и метку строки");
});

// WF144 (класс #9055, WF136 п.11): открытое меню вставляет пустой span-сторож фокуса
// рядом со своей кнопкой. Обёртка микрофона и стрелка ⌄ узнаются, как без него, —
// метки не перескакивают, строка не перестраивается, пока меню открыто.
test("WF144: сторожа фокуса Base UI не сбивают метки строки", () => {
  const loaded = open({ guards: true });
  const parts = loaded.parts;
  assert.equal(loaded.error, null);
  assert.equal(mark(parts.micShell), "hide", "обёртка с микрофоном и сторожем — всё ещё «одна кнопка»");
  assert.equal(mark(parts.arrow), "hide", "стрелка за сторожем — всё ещё сосед микрофона");
  assert.equal(mark(parts.mode), "text");
});

test("WF175 (#9195), WF183: Bypass permissions подписан «Bp», не «BY»/«BP»; код режима для сторожей — прежний «By»; обёртки кнопок — по середине строки, цифры табличные", () => {
  const loaded = open();
  const { modeText } = loaded.parts;
  loaded.dom.retext(modeText, "Bypass permissions");
  settle(loaded);
  assert.equal(short(modeText), "Bp");
  assert.equal(loaded.inner.chinModeShort("Bypass permissions"), "By");
  loaded.dom.retext(modeText, "Auto mode");
  settle(loaded);
  assert.equal(short(modeText), "Au", "прочие режимы — код как есть: «Хх» (WF183)");
  const css = [...loaded.inner.RULES].join("\n");
  assert.match(css, /\[data-myclaude-chin="row"\]\{min-width:min-content !important;align-self:center !important\}/, "левая группа прижата кверху — «BP» выше «O 5.5»");
  assert.match(css, /\[data-myclaude-chin="text"\]\{font-variant-numeric:tabular-nums\}/);
});

test("WF183: все подписи строки — притемнённым цветом темы; кружок токенов не ужимается, правое поле строки — как левое у микрофона; тесная строка ужимает поля подписей", () => {
  const { inner } = loadInner();
  const css = plain(inner.RULES).join("\n");
  assert.ok(css.includes('[data-cds="ChatComposerChin"] [data-myclaude-chin="text"],[data-cds="ChatComposerChin"] [data-myclaude-chin="text"] *{color:var(--cds-text-secondary,currentColor) !important}'),
    "подписи строки разными цветами (#03:05 «всё разными цветами»)");
  assert.ok(css.includes('[data-cds="ChatComposerChin"] [aria-haspopup="dialog"][aria-label^="Usage:"]{flex-shrink:0 !important}'), "кружок ужимается");
  assert.ok(css.includes('[data-cds="ChatComposerChin"] div[class*="--cmp-chin-start"]{padding-inline-end:6px !important}'), "правое поле строки не равно левому");
  assert.match(css, /\[data-myclaude-chin-narrow\] \[data-myclaude-chin="text"\]\{padding-left:3px !important;padding-right:3px !important\}/);
});
