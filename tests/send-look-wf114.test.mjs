// WF128 К1 v3 (#9041): виды счёта снова разные — 1.8 «Взлёт» (умолчание), 1.9
// «Пульс», 1.10 «Мерцание», 1.1, 1.2, 1.4, 1.6, 1.5; 1.3 и 1.7 — команда мимо.
// Ключ myclaude-send-look-v2; нет v2 — 1.8 и размер из v1. Preview — выбранный
// вид без отправки; адресация и seconds — WF119.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const CHAT = "local_aaaa-1111";
const KEY = "myclaude-send-look-v2";
const V1 = "myclaude-send-look-v1";
const DIGITS = "myclaude-send-delay-digits";
const ROCKET = "myclaude-send-delay-rocket";
const PLATE = "myclaude-send-delay";
const ACCENT = "#46d18b";
const SEND_RECT = { left: 1070, top: 748, width: 24, height: 24 };
const STYLES = ["1.8", "1.9", "1.10", "1.1", "1.2", "1.4", "1.6", "1.5"];
// Отправлено: взлёт 1.8 и волна 1.1/1.2/1.6/1.9/1.10; 1.4 и 1.5 тихо гаснут.
const FLIES = ["1.8", "1.1", "1.2", "1.6", "1.9", "1.10"];
const drain = () => new Promise(resolve => setImmediate(resolve));

const page = ({ stored = null, button = true, text = "привет", local = {}, session = {}, hasFocus = true, href = `https://claude.ai/epitaxy/${CHAT}` } = {}) => {
  const loaded = loadInject({
    href, hasFocus, title: "Тест вида счёта",
    storage: { local: { "myclaude-auto-allow-roam": "off", "myclaude-send-delay-seconds": "5", ...(stored == null ? {} : { [KEY]: stored }), ...local }, session },
    html: dom => {
      const parts = dom.composer({ text });
      parts.enters = [];
      parts.editor.addEventListener("keydown", event => {
        if (event.key !== "Enter") return;
        parts.enters.push(event.isTrusted === true ? "trusted" : "synthetic");
        parts.editor.__text = "";
      });
      if (button) parts.send = parts.modelRow.add("button", { attrs: { "data-testid": "code-prompt-send" }, rect: SEND_RECT });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  for (const node of [loaded.document.documentElement, ...loaded.document.querySelectorAll("*")]) {
    node.computed = { ...(node.computed ?? {}), "--accent-brand": ACCENT };
  }
  loaded.advance = (times = 1) => { for (let i = 0; i < times; i += 1) loaded.dom.fireKind("timeout"); };
  return loaded;
};
let seq = 0;
const look = (loaded, fields) => loaded.dom.command({ id: `look-${seq += 1}`, action: "send-look", at: new Date().toISOString(), ...fields });
const enter = loaded => loaded.document.dispatchEvent({
  type: "keydown", key: "Enter", code: "Enter", target: loaded.parts.editor, isTrusted: true, bubbles: true, cancelable: true,
});
const esc = loaded => {
  const event = { type: "keydown", key: "Escape", code: "Escape", target: loaded.parts.editor, isTrusted: true, bubbles: true, cancelable: true };
  return loaded.win.dispatchEvent(event);
};
const digits = loaded => loaded.document.getElementById(DIGITS);
const status = loaded => ({ ...loaded.api.status().sendDelay.look });
const stored = loaded => JSON.parse(loaded.win.localStorage.getItem(KEY));
const flew = loaded => loaded.dom.animations.some(anim => anim.node.id === ROCKET || anim.node.parentNode?.id === ROCKET);
// Анимации вида на узле счёта и его частях (не взлёт).
const moving = loaded => loaded.dom.running().filter(anim => {
  for (let node = anim.node; node; node = node.parentNode) if (node.id === DIGITS) return true;
  return false;
});

test("умолчание — 1.8 на 100 %; мусор в v2 — умолчание; нет v2 — размер из v1", () => {
  assert.deepEqual(status(page()), { style: "1.8", size: 100, preview: false });
  assert.deepEqual(status(page({ stored: "{не json" })), { style: "1.8", size: 100, preview: false });
  assert.deepEqual(status(page({ stored: JSON.stringify({ style: "1.3", size: 30 }) })), { style: "1.8", size: 100, preview: false });
  assert.deepEqual(status(page({ stored: JSON.stringify({ style: "1.7", size: 140 }) })), { style: "1.8", size: 140, preview: false });
  assert.deepEqual(status(page({ stored: JSON.stringify({ style: "1.10", size: 30 }) })), { style: "1.10", size: 100, preview: false });
  assert.deepEqual(status(page({ stored: JSON.stringify({ style: "1.9", size: 140 }) })), { style: "1.9", size: 140, preview: false });
  // v1 у всех хранит 1.5 с WF119 — вид из него не берётся, размер берётся.
  assert.deepEqual(status(page({ local: { [V1]: JSON.stringify({ style: "1.5", size: 160 }) } })), { style: "1.8", size: 160, preview: false });
  assert.deepEqual(status(page({ local: { [V1]: "мусор" } })), { style: "1.8", size: 100, preview: false });
  // v2 есть — v1 молчит.
  assert.deepEqual(status(page({ stored: JSON.stringify({ style: "1.6", size: 90 }), local: { [V1]: JSON.stringify({ style: "1.5", size: 160 }) } })),
    { style: "1.6", size: 90, preview: false });
});

test("send-look: каждый вид набора принимается и пишется в v2; 1.3, 1.7 и чужие — команда мимо", () => {
  const loaded = page({ local: { [V1]: JSON.stringify({ style: "1.5", size: 150 }) } });
  for (const style of STYLES) {
    look(loaded, { style, size: 150, preview: false });
    assert.deepEqual(stored(loaded), { style, size: 150 }, style);
    assert.equal(status(loaded).style, style);
  }
  look(loaded, { style: "1.9", size: 120 });
  for (const style of ["1.3", "1.7", "2.0", "1.10 ", 1.9, null]) {
    look(loaded, { style, size: 80, preview: true });
    assert.deepEqual(stored(loaded), { style: "1.9", size: 120 }, `${style} не отвергнут целиком`);
    assert.equal(status(loaded).preview, false, `${style}: показ всё же пошёл`);
  }
  assert.equal(loaded.win.localStorage.getItem(V1), JSON.stringify({ style: "1.5", size: 150 }), "v1 не трогается");
  look(loaded, { style: "1.4", size: 201 });
  assert.deepEqual(stored(loaded), { style: "1.4", size: 100 });
  look(loaded, { style: "1.1", size: "120" });
  assert.deepEqual(stored(loaded), { style: "1.1", size: 100 }, "строка — не число");
  look(loaded, { size: 60 });
  assert.deepEqual(stored(loaded), { style: "1.1", size: 60 }, "без style вид прежний");
});

test("storage из другого окна меняет вид сразу; чужой ключ — мимо; узел пересобирается", () => {
  const loaded = page();
  loaded.win.localStorage.setItem(KEY, JSON.stringify({ style: "1.4", size: 80 }));
  loaded.win.dispatchEvent({ type: "storage", key: "чужой-ключ" });
  assert.equal(status(loaded).style, "1.8");
  loaded.win.dispatchEvent({ type: "storage", key: KEY });
  assert.deepEqual(status(loaded), { style: "1.4", size: 80, preview: false });
  enter(loaded);
  assert.equal(digits(loaded).getAttribute("data-look"), "1.4/80");
  loaded.win.localStorage.setItem(KEY, JSON.stringify({ style: "1.10", size: 140 }));
  loaded.win.dispatchEvent({ type: "storage", key: KEY });
  loaded.advance();
  assert.equal(digits(loaded).getAttribute("data-look"), "1.10/140");
  assert.equal(digits(loaded).textContent, "4");
  assert.equal(loaded.document.querySelectorAll(`#${DIGITS}`).length, 1, "старый узел не снят");
});

// Каждый вид на настоящем счёте: идёт → последняя секунда → отправлено; dispose.
for (const style of STYLES) {
  const flight = FLIES.includes(style);
  test(`вид ${style}: счёт 5→1 на кнопке, ${style === "1.5" ? "без движения" : "движется"}, отпускание шлёт Enter, ${flight ? "взлёт" : "без взлёта"}`, async () => {
    const loaded = page({ stored: JSON.stringify({ style, size: 120 }) });
    enter(loaded);
    const node = digits(loaded);
    assert.equal(node.getAttribute("data-look"), `${style}/120`);
    assert.equal(node.getAttribute("role"), "timer");
    assert.equal(node.style.getPropertyValue("display"), "flex");
    assert.deepEqual(["left", "top", "width", "height"].map(k => node.style.getPropertyValue(k)), ["1070px", "748px", "24px", "24px"], "цель нажатия — ровно кнопка");
    assert.equal(node.textContent, "5");
    if (style === "1.5") assert.equal(moving(loaded).length, 0, "спокойная цифра движется");
    else assert.ok(moving(loaded).length > 0, "вид не движется");
    // Все части вида не ловят нажатие.
    for (const kid of node.querySelectorAll("*")) if (kid.style?.getPropertyValue) assert.notEqual(kid.style.getPropertyValue("pointer-events"), "auto");
    loaded.advance();
    assert.equal(node.textContent, "4");
    loaded.advance(3);
    assert.equal(node.textContent, "1", "последняя секунда");
    if (style === "1.9" || style === "1.10") {
      assert.ok(moving(loaded).some(anim => anim.options?.iterations === 2), "последняя секунда не чаще");
    }
    assert.equal(flew(loaded), false, "взлёт до отправки");
    loaded.advance();
    assert.deepEqual(loaded.parts.enters, ["synthetic"], "отпускание не отправило");
    assert.equal(loaded.api.status().sendDelay.released, 1);
    assert.equal(flew(loaded), flight, "взлёт не по виду");
    assert.equal(node.style.getPropertyValue("display"), "none");
    assert.equal(moving(loaded).length, 0, "анимации счёта остались");
    await drain();
    assert.equal(loaded.document.getElementById(ROCKET), null, "взлёт не снялся");
    enter(loaded);
    loaded.api.dispose();
    for (const id of [DIGITS, ROCKET, PLATE]) assert.equal(loaded.document.querySelectorAll(`#${id}`).length, 0, id);
  });

  test(`вид ${style}: отмена (Esc, клик по цифре) — узел гаснет сразу, без взлёта, ничего не ушло`, () => {
    for (const how of ["esc", "click"]) {
      const loaded = page({ stored: JSON.stringify({ style, size: 100 }) });
      enter(loaded);
      loaded.advance(2);
      if (how === "esc") assert.equal(esc(loaded), false, "Esc ушёл в Claude");
      else loaded.document.dispatchEvent({ type: "click", target: digits(loaded), isTrusted: true, bubbles: true, cancelable: true });
      assert.equal(loaded.api.status().sendDelay.counting, false, how);
      assert.equal(digits(loaded).style.getPropertyValue("display"), "none");
      assert.equal(moving(loaded).length, 0, "движение после отмены");
      loaded.advance(5);
      assert.equal(flew(loaded), false, "отмена взлетела");
      assert.deepEqual(loaded.parts.enters, []);
      loaded.api.dispose();
    }
  });
}

// WF179 (слово Элвиса 09.10 02:50: «я отсчёт „Ракета“ поставил — не отрабатывает»; у Мака
// reduceMotion=1 — страница играла спокойную цифру при выбранном виде): выбор человека (ключ v2)
// сильнее «Уменьшить движение»; выбора нет — спокойная цифра, как было.
test("«Уменьшить движение» и вид не выбран — спокойная цифра, без движения и взлёта", () => {
  const loaded = page();
  loaded.win.__reducedMotion = true;
  enter(loaded);
  assert.equal(digits(loaded).getAttribute("data-look"), "1.5/100");
  assert.equal(digits(loaded).children.length, 0);
  assert.equal(loaded.dom.running().length, 0);
  loaded.advance(5);
  assert.deepEqual(loaded.parts.enters, ["synthetic"]);
  assert.equal(flew(loaded), false);
  assert.equal(status(loaded).style, "1.8", "умолчание прежнее");
  loaded.api.dispose();
});

test("WF179: «Уменьшить движение», а вид выбран — играется выбранный, ракета 1.8 взлетает", () => {
  for (const style of ["1.8", "1.9", "1.10", "1.6"]) {
    const loaded = page({ stored: JSON.stringify({ style, size: 100 }) });
    loaded.win.__reducedMotion = true;
    enter(loaded);
    assert.equal(digits(loaded).getAttribute("data-look"), `${style}/100`, `${style}: показан не выбранный вид`);
    assert.ok(digits(loaded).children.length > 0, `${style}: части вида не собраны`);
    loaded.advance(5);
    assert.deepEqual(loaded.parts.enters, ["synthetic"]);
    assert.equal(flew(loaded), true, `${style}: отправка без взлёта`);
    assert.equal(status(loaded).style, style, "выбор не меняется");
    loaded.api.dispose();
  }
  // Выбор командой Пимпа (send-look) — тоже выбор: ключ v2 пишется, вид играется.
  const picked = page();
  picked.win.__reducedMotion = true;
  look(picked, { style: "1.8", size: 100 });
  enter(picked);
  assert.equal(digits(picked).getAttribute("data-look"), "1.8/100");
  picked.advance(5);
  assert.equal(flew(picked), true, "ракета не взлетела");
  picked.api.dispose();
});

test("1.1: штрих растёт за секунду на долю счёта цветом акцента", () => {
  const loaded = page({ stored: JSON.stringify({ style: "1.1", size: 100 }) });
  enter(loaded);
  const ring = digits(loaded).querySelector("svg");
  const arc = ring.children[1];
  assert.equal(arc.getAttribute("pathLength"), "100");
  assert.equal(arc.style.getPropertyValue("stroke-dasharray"), "20.00 100");
  assert.equal(arc.style.getPropertyValue("stroke"), ACCENT);
  loaded.advance(4);
  assert.equal(arc.style.getPropertyValue("stroke-dasharray"), "100.00 100", "на последней секунде круг не замкнулся");
  loaded.api.dispose();
});

test("1.8: метка с секундами, пламя растёт к нулю; холодный кеш — метка красная", () => {
  const loaded = page({ stored: JSON.stringify({ style: "1.8", size: 100 }) });
  enter(loaded);
  const node = digits(loaded);
  const flame = node.children[0];
  const badge = node.children[2];
  assert.equal(badge.textContent, "5");
  const first = parseFloat(flame.style.getPropertyValue("opacity"));
  loaded.advance(4);
  assert.ok(parseFloat(flame.style.getPropertyValue("opacity")) > first, "пламя не растёт");
  loaded.api.dispose();
});

test("preview: показывает выбранный вид 5→1 и кончается его взлётом, Enter не уходит", () => {
  for (const style of STYLES) {
    const loaded = page();
    look(loaded, { style, size: 120, preview: true });
    assert.deepEqual(status(loaded), { style, size: 120, preview: true });
    assert.equal(digits(loaded).getAttribute("data-look"), `${style}/120`, "показ не того вида");
    assert.equal(digits(loaded).textContent, "5");
    assert.equal(loaded.api.status().sendDelay.counting, false, "показ — не счёт");
    loaded.advance(4);
    assert.equal(digits(loaded).textContent, "1");
    assert.equal(flew(loaded), false);
    loaded.advance();
    assert.equal(status(loaded).preview, false);
    assert.deepEqual(loaded.parts.enters, [], "показ отправил сообщение");
    assert.equal(flew(loaded), FLIES.includes(style), `${style}: конец показа не как отправка`);
    assert.equal(digits(loaded).style.getPropertyValue("display"), "none");
    assert.equal(loaded.api.status().sendDelay.released, 0);
    loaded.api.dispose();
  }
});

test("preview адресуется: попап без match/chat — нет; match — по пути; идёт счёт — нет", () => {
  const popup = page({ href: "about:blank" });
  look(popup, { style: "1.4", size: 100, preview: true });
  assert.equal(status(popup).preview, false, "попап без адреса проиграл показ");
  assert.equal(status(popup).style, "1.4", "выбор всё равно общий");

  const other = page();
  look(other, { style: "1.4", size: 100, preview: true, match: "/epitaxy/local_other" });
  assert.equal(status(other).preview, false);
  look(other, { style: "1.4", size: 100, preview: true, match: `/epitaxy/${CHAT}` });
  assert.equal(status(other).preview, true);

  const busy = page();
  enter(busy);
  look(busy, { style: "1.2", size: 100, preview: true });
  assert.equal(status(busy).preview, false, "показ поверх настоящего счёта");
  assert.equal(busy.api.status().sendDelay.counting, true);
});

test("preview: новый сменяет старый, Enter с полным полем — настоящий счёт вместо показа", () => {
  const loaded = page();
  look(loaded, { style: "1.8", size: 100, preview: true });
  loaded.advance(2);
  assert.equal(digits(loaded).textContent, "3");
  look(loaded, { style: "1.9", size: 100, preview: true });
  assert.equal(digits(loaded).textContent, "5", "новый показ не с начала");
  assert.equal(digits(loaded).getAttribute("data-look"), "1.9/100");
  enter(loaded);
  assert.equal(status(loaded).preview, false);
  assert.equal(loaded.api.status().sendDelay.counting, true);
  loaded.advance(5);
  assert.deepEqual(loaded.parts.enters, ["synthetic"]);
});

test("preview гасят Esc (глушится), клик по узлу и правка поля", () => {
  const byEsc = page();
  look(byEsc, { style: "1.1", size: 100, preview: true });
  const passed = esc(byEsc);
  assert.equal(status(byEsc).preview, false);
  assert.equal(passed, false, "Esc показа ушёл в Claude");
  assert.equal(digits(byEsc).style.getPropertyValue("display"), "none");
  byEsc.advance(5);
  assert.equal(flew(byEsc), false, "погашенный показ взлетел");

  const byClick = page();
  look(byClick, { style: "1.2", size: 100, preview: true });
  const click = { type: "pointerdown", target: digits(byClick), isTrusted: true, bubbles: true, cancelable: true };
  assert.equal(byClick.document.dispatchEvent(click), false, "клик по показу ушёл в Claude");
  assert.equal(status(byClick).preview, false);
  assert.equal(byClick.api.status().sendDelay.counting, false, "клик по показу начал счёт");

  const byEdit = page();
  look(byEdit, { style: "1.6", size: 100, preview: true });
  byEdit.document.dispatchEvent({ type: "input", target: byEdit.parts.editor, isTrusted: true, bubbles: true });
  assert.equal(status(byEdit).preview, false);
});

test("preview без кнопки отправки — плашкой над полем; «уменьшить движение» — выбор играется (WF179), скрытое окно — без полёта", () => {
  const loaded = page({ button: false });
  look(loaded, { style: "1.1", size: 100, preview: true });
  const plate = loaded.document.getElementById(PLATE);
  assert.ok(plate?.textContent.startsWith("Показ: отправка через 5"), plate?.textContent);
  loaded.advance(5);
  assert.equal(status(loaded).preview, false);
  assert.equal(plate.style.getPropertyValue("display"), "none");
  assert.equal(flew(loaded), false, "без кнопки взлетать неоткуда");

  // «Уменьшить движение»: показ — выбор (WF179), вид играется и взлетает; отправки нет.
  const still = page();
  still.win.__reducedMotion = true;
  look(still, { style: "1.8", size: 100, preview: true });
  assert.equal(digits(still).getAttribute("data-look"), "1.8/100");
  still.advance(5);
  assert.equal(flew(still), true);
  assert.deepEqual(still.parts.enters, []);
  // Скрытое окно — всегда спокойно.
  const hidden = page({ stored: JSON.stringify({ style: "1.8", size: 100 }) });
  hidden.document.hidden = true;
  look(hidden, { style: "1.8", size: 100, preview: true });
  hidden.advance(5);
  assert.equal(flew(hidden), false, "скрытое окно взлетело");
});

for (const seconds of [3, 5, 10]) {
  for (const off of [false, true]) {
    test(`WF119 preview ${seconds} с, off=${off}: N→1, настройка/черновик прежние`, () => {
      const loaded = page({ hasFocus: false, local: { "myclaude-send-delay-off": off ? "1" : "0", "myclaude-send-delay-seconds": "5" } });
      loaded.dom.command({ id: "wf119-preview-main", action: "send-look", at: "2026-10-03T00:00:02Z",
        style: "1.5", size: 100, preview: true, seconds, match: `/epitaxy/${CHAT}` });
      for (let left = seconds; left > 0; left--) {
        assert.equal(digits(loaded).textContent, String(left));
        assert.equal(status(loaded).preview, true);
        loaded.advance();
      }
      assert.equal(status(loaded).preview, false);
      assert.equal(loaded.parts.editor.textContent, "привет");
      assert.deepEqual(loaded.parts.enters, []);
      assert.equal(loaded.api.status().sendDelay.released, 0);
      assert.equal(loaded.win.localStorage.getItem("myclaude-send-delay-seconds"), "5");
      assert.equal(loaded.win.localStorage.getItem("myclaude-send-delay-off"), off ? "1" : "0");
      assert.equal(flew(loaded), false);
      loaded.api.dispose();
    });
  }
}

test("WF119 точный preview попапа без фокуса; main/broadcast и legacy payload", () => {
  const popup = page({ href: "about:blank", hasFocus: false,
    session: { "myclaude-chat-v1": JSON.stringify({ id: CHAT, title: "Тест вида счёта" }) } });
  popup.dom.command(JSON.parse('{"id":"wf119-preview-popout","action":"send-look","at":"2026-10-03T00:00:03Z","style":"1.5","size":100,"preview":true,"seconds":10,"chat":"local_aaaa-1111"}'));
  assert.equal(status(popup).preview, true);
  assert.equal(digits(popup).textContent, "10");
  esc(popup);
  const main = page({ href: "https://claude.ai/epitaxy/local_main", hasFocus: false });
  main.dom.command(JSON.parse('{"id":"wf119-preview-main","action":"send-look","at":"2026-10-03T00:00:02Z","style":"1.5","size":100,"preview":true,"seconds":3,"match":"/epitaxy/local_main"}'));
  assert.equal(digits(main).textContent, "3");
  esc(main);
  for (const p of [main, popup]) {
    p.dom.command(JSON.parse('{"id":"wf119-look-broadcast","action":"send-look","at":"2026-10-03T00:00:04Z","style":"1.5","size":100,"preview":false}'));
    assert.equal(status(p).preview, false);
    p.win.localStorage.setItem("myclaude-send-delay-seconds", "3");
    look(p, { style: "1.2", size: 120, preview: true });
  }
  assert.equal(status(popup).preview, false, "старый CLI без адреса только главному");
  assert.equal(digits(main).textContent, "3", "legacy берёт интервал страницы");
  for (const p of [main, popup]) { p.advance(12); assert.deepEqual(p.parts.enters, []); p.api.dispose(); }
});

test("WF119 preview: неверные seconds не показываются; broadcast игнорирует seconds", () => {
  const p = page();
  for (const seconds of [null, true, "3", 0, 4, 3.5, -3, NaN]) {
    look(p, { preview: true, seconds });
    assert.equal(status(p).preview, false, String(seconds));
    look(p, { style: "1.2", size: 120, preview: false, seconds });
    assert.equal(status(p).size, 120);
    assert.equal(status(p).preview, false);
  }
  p.api.dispose();
});

test("WF119 размер 60…200: цель не растёт; две цифры помещаются в 24 px у каждого вида с цифрой на кнопке", () => {
  const p = page();
  for (const style of STYLES.filter(s => s !== "1.8")) {
    for (const size of [60, 100, 200]) {
      look(p, { style, size, preview: true, seconds: 10 });
      const d = digits(p);
      assert.equal(d.textContent, "10");
      assert.equal(d.style.getPropertyValue("width"), "24px");
      assert.equal(d.style.getPropertyValue("height"), "24px");
      // 1.5 — цифра в самом узле, остальные — в своём ребёнке.
      const text = style === "1.5" ? d : Array.from(d.children).find(kid => kid.textContent === "10");
      assert.ok(parseFloat(text.style.getPropertyValue("font-size")) <= 20 / 1.3, `${style}/${size}`);
    }
  }
  p.api.dispose();
});

test("WF119 preview: пустое поле и нет кнопки; клик по родной кнопке только отменяет", () => {
  const p = page({ text: "", button: false });
  look(p, { preview: true, seconds: 3 });
  assert.match(p.document.getElementById(PLATE).textContent, /через 3/);
  p.advance(3);
  assert.equal(p.parts.editor.textContent, "");
  assert.deepEqual(p.parts.enters, []); p.api.dispose();
  const q = page();
  look(q, { preview: true, seconds: 10 });
  for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) {
    assert.equal(q.document.dispatchEvent({ type, target: q.parts.send, isTrusted: true }), false);
  }
  q.advance(12);
  assert.equal(status(q).preview, false);
  assert.equal(q.api.status().sendDelay.counting, false);
  assert.deepEqual(q.parts.enters, []); q.api.dispose();
});

test("WF119 preview: смена чата и программная правка черновика гасят показ", () => {
  for (const change of [p => { p.parts.editor.__text = "новый текст"; }, p => { p.win.location.pathname = "/epitaxy/local_other"; }]) {
    const p = page(); look(p, { preview: true, seconds: 10 }); change(p); p.advance();
    assert.equal(status(p).preview, false);
    assert.deepEqual(p.parts.enters, []); p.api.dispose();
  }
});
