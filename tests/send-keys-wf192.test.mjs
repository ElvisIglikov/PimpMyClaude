// WF192 (слово Элвиса 09.10 04:10): «Command-Enter, Option-Enter — они должны переносить на новую строку.
// Любые сочетания клавиш — все на таймер должны попадать. Никаких быстрых отправок. Всё на таймере всегда.»
// и «Ту полоску верхнюю убрать, но чтобы я переносить мог за верхнюю часть экрана это окошко… фейд сделать
// от самого края окна Claude».
//
// Клавиши: каждое сочетание с Enter — либо перенос строки (⌘↩, ⌥↩, ⇧↩ и их пары с ⇧), либо отсчёт (Enter, ⌃↩,
// кнопка «Отправить»); ни одно не доходит до Claude отправкой мимо счёта. Стенд «Claude» в редакторе: ⇧Enter —
// перенос строки (дописывает "\n", гасит событие), любой другой Enter — отправка (поле пустеет).
// Верх: в живом виде рамка плиток Claude теряет верхнее поле и рамку, шапка колонки возвращается на место,
// полосы перетаскивания окна мы не трогаем; в классическом — правил нет.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_aaaa-1111";

const page = ({ local = {}, takesShift = true } = {}) => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Тест клавиш",
    storage: { local: { "myclaude-auto-allow-roam": "off", "myclaude-send-delay-seconds": "3", ...local } },
    html: dom => {
      const parts = dom.composer({ text: "привет" });
      parts.got = [];
      parts.editor.addEventListener("keydown", event => {
        if (event.key !== "Enter") return;
        if (event.shiftKey && !event.metaKey && !event.altKey && !event.ctrlKey) {
          parts.got.push(event.isTrusted === true ? "newline-trusted" : "newline");
          if (takesShift) { parts.editor.__text += "\n"; event.preventDefault(); }
          return;
        }
        parts.got.push("send");
        parts.editor.__text = "";
      });
      parts.send = parts.modelRow.add("button", { attrs: { "data-testid": "code-prompt-send" }, rect: { left: 1070, top: 748, width: 24, height: 24 } });
      parts.send.__presses = 0;
      parts.send.addEventListener("click", () => { parts.send.__presses += 1; parts.editor.__text = ""; });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.passed = [];
  loaded.document.addEventListener("keydown", event => loaded.passed.push(event.key), true);
  loaded.advance = (times = 1) => { for (let i = 0; i < times; i += 1) loaded.dom.fireKind("timeout"); };
  return loaded;
};
// Доверенная клавиша: захват document (перехватчик); не погашена — дальше, в редактор (там «Claude»).
const key = (loaded, extra = {}) => {
  const event = () => ({ type: "keydown", key: "Enter", code: "Enter", target: loaded.parts.editor, isTrusted: true, bubbles: true, cancelable: true, ...extra });
  const passed = loaded.document.dispatchEvent(event());
  if (passed) loaded.parts.editor.dispatchEvent(event());
  return passed;
};
const click = (loaded, target) => {
  const event = { type: "click", target, isTrusted: true, bubbles: true, cancelable: true };
  const passed = loaded.document.dispatchEvent(event);
  if (passed) target.dispatchEvent({ ...event });
  return passed;
};
const delay = loaded => plain(loaded.api.status().sendDelay);
const NEWLINE_COMBOS = [
  ["⌘↩", { metaKey: true }], ["⌥↩", { altKey: true }],
  ["⌘⇧↩", { metaKey: true, shiftKey: true }], ["⌥⇧↩", { altKey: true, shiftKey: true }], ["⌘⌥↩", { metaKey: true, altKey: true }],
];

for (const [name, extra] of NEWLINE_COMBOS) {
  test(`WF192: ${name} — перенос строки в позицию курсора, не отправка и не отсчёт`, () => {
    const loaded = page();
    assert.equal(key(loaded, extra), false, `${name} дошёл до Claude — он отправил бы сразу`);
    assert.deepEqual(loaded.passed, [], `${name} прошёл дальше перехватчика`);
    assert.deepEqual(loaded.parts.got, ["newline"], "редактор получил не перенос строки");
    assert.equal(loaded.parts.editor.__text, "привет\n");
    assert.equal(delay(loaded).counting, false);
    assert.equal(delay(loaded).started, 0);
    assert.equal(delay(loaded).newlines, 1);
    loaded.advance(6);
    assert.equal(loaded.parts.got.includes("send"), false, "ушло без отсчёта");
    loaded.api.dispose();
  });
}

test("WF192: Enter, ⌃↩ и ⌃⇧↩ — только через отсчёт; отсчёт кончился — одна отправка", () => {
  for (const extra of [{}, { ctrlKey: true }, { ctrlKey: true, shiftKey: true }, { ctrlKey: true, metaKey: true }]) {
    const loaded = page();
    const label = JSON.stringify(extra);
    assert.equal(key(loaded, extra), false, `${label}: дошёл до Claude`);
    assert.deepEqual(loaded.parts.got, [], `${label}: Claude увидел Enter до отсчёта`);
    assert.equal(delay(loaded).counting, true, `${label}: отсчёта нет`);
    loaded.advance(2);
    assert.deepEqual(loaded.parts.got, [], `${label}: ушло раньше отсчёта`);
    loaded.advance();
    assert.deepEqual(loaded.parts.got, ["send"], `${label}: после отсчёта — не одна отправка`);
    loaded.api.dispose();
  }
});

test("WF192: кнопка «Отправить» мышью и клавиатурой (click без pointerdown) — через отсчёт", () => {
  const loaded = page();
  assert.equal(click(loaded, loaded.parts.send), false, "клик дошёл до Claude");
  assert.equal(loaded.parts.send.__presses, 0);
  assert.equal(delay(loaded).counting, true);
  assert.equal(delay(loaded).left, 3);
  loaded.advance(3);
  assert.deepEqual(loaded.parts.got, ["send"], "после отсчёта не ушло одним Enter");
  loaded.api.dispose();
});

test("WF192: ⇧↩ без счёта — перенос строки Claude, нетронутым; во время счёта по умолчанию — тоже перенос, не «сразу»", () => {
  const loaded = page();
  assert.equal(delay(loaded).shift, "newline");
  assert.equal(key(loaded, { shiftKey: true }), true);
  assert.deepEqual(loaded.parts.got, ["newline-trusted"]);
  assert.equal(delay(loaded).started, 0);
  key(loaded);
  assert.equal(delay(loaded).counting, true);
  assert.equal(key(loaded, { shiftKey: true }), true, "⇧↩ во время счёта проглочен");
  assert.equal(delay(loaded).immediate, 0, "⇧↩ отправил мимо отсчёта");
  assert.equal(loaded.parts.got.includes("send"), false);
  // Перенос строки — правка поля: счёт гаснет, текст остаётся.
  loaded.advance();
  assert.equal(delay(loaded).counting, false);
  assert.equal(delay(loaded).last.why, "edit");
  loaded.advance(5);
  assert.equal(loaded.parts.got.includes("send"), false);
  loaded.api.dispose();
});

test("WF192: ⌘↩ во время счёта — перенос строки, не «сразу»; правка гасит счёт, ничего не ушло", () => {
  const loaded = page();
  key(loaded);
  assert.equal(key(loaded, { metaKey: true }), false);
  assert.deepEqual(loaded.parts.got, ["newline"]);
  assert.equal(delay(loaded).immediate, 0);
  loaded.advance();
  assert.equal(delay(loaded).counting, false);
  assert.equal(delay(loaded).last.why, "edit");
  loaded.advance(5);
  assert.equal(loaded.parts.got.includes("send"), false);
  loaded.api.dispose();
});

test("WF192: ⌘↩ в IME (isComposing, keyCode 229) — мимо, как было; ⌘↩ вне поля — не наш", () => {
  const loaded = page();
  assert.equal(key(loaded, { metaKey: true, isComposing: true }), true);
  assert.equal(key(loaded, { metaKey: true, keyCode: 229 }), true);
  assert.equal(delay(loaded).newlines, 0);
  const other = loaded.document.body.add("input");
  assert.equal(loaded.document.dispatchEvent({ type: "keydown", key: "Enter", metaKey: true, target: other, isTrusted: true, cancelable: true }), true);
  assert.equal(delay(loaded).newlines, 0);
  loaded.api.dispose();
});

test("WF192: редактор не взял синтетический ⇧↩ — перенос строки командой insertLineBreak", () => {
  const loaded = page({ takesShift: false });
  const commands = [];
  const original = loaded.document.execCommand;
  loaded.document.execCommand = (name, ...rest) => { commands.push(name); return original(name, ...rest); };
  assert.equal(key(loaded, { altKey: true }), false);
  assert.deepEqual(commands, ["insertLineBreak"]);
  assert.equal(loaded.parts.got.includes("send"), false);
  loaded.api.dispose();
});

test("WF192: «сразу» по ⇧↩ — только явным выбором; команда shift:send пишет ключ, newline снимает", () => {
  const loaded = page({ local: { "myclaude-send-delay-shift": "send" } });
  assert.equal(delay(loaded).shift, "send");
  key(loaded);
  assert.equal(key(loaded, { shiftKey: true }), false);
  assert.equal(delay(loaded).immediate, 1);
  assert.deepEqual(loaded.parts.got, ["send"]);
  loaded.dom.command({ id: "wf192-nl", action: "send-delay", at: "2026-10-09T00:00:00Z", shift: "newline" });
  assert.equal(loaded.win.localStorage.getItem("myclaude-send-delay-shift"), null);
  assert.equal(delay(loaded).shift, "newline");
  loaded.api.dispose();
});

// ---- Верх ленты ----
const TILE_RULE = 'div[style*="--tiles-padding"]:has(.tiles-shell) { padding-top: 0 !important; border-top-width: 0 !important; }';
const TITLE_RULE = 'div[style*="--tiles-padding"] .epitaxy-chat-panel:not([data-myclaude-headless]) .epitaxy-titlebar { margin-top: calc(var(--tiles-padding, 8px) + 1px) !important; }';
let seq = 0;
const look = (loaded, value) => loaded.dom.command({ id: `wf192-${++seq}`, action: "theme", at: "now", scope: "all", look: value });

test("WF192: живой вид — лента от самого края окна (поле и рамка сверху сняты), шапка колонки на прежнем месте", () => {
  const loaded = page();
  look(loaded, { aurora: true });
  const css = loaded.dom.sheets();
  assert.ok(css.includes(TILE_RULE), "верхнее поле рамки плиток осталось — лента режется о полосу");
  assert.ok(css.includes(TITLE_RULE), "шапка колонки не возвращена на место");
  // Затухание ленты — от 0 её края (а край теперь — край окна).
  assert.ok(css.includes('[data-myclaude-scroll-fade="top"] { -webkit-mask-image: linear-gradient(to bottom, transparent 0, #000 14px)'));
  // Полосу перетаскивания окна Claude (.draggable, app-region: drag) мы не трогаем и no-drag сверху не ставим.
  assert.equal(/draggable/.test(css), false, "наши правила задели полосу перетаскивания окна");
  assert.equal(/\.tiles-shell[^{]*\{[^}]*app-region/.test(css), false);
  look(loaded, { aurora: false });
  const plainCss = loaded.dom.sheets();
  assert.equal(plainCss.includes("--tiles-padding"), false, "в классическом виде рамка плиток тронута");
  loaded.api.dispose();
});
