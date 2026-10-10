// WF105, батч Б2 (раздел 12у inject.js; #8069): отсрочка отправки; WF106 (#8103):
// пять секунд, цифры на кнопке, мышь тоже ждёт, остывший кеш — красным.
//
// Доверенный Enter без Shift в непустом поле при закрытом меню подсказок не
// уходит к Claude: встаёт счёт 5-4-3-2-1 цифрами поверх кнопки отправки (своим
// fixed-узлом; кнопки нет — плашкой над полем). Доверенный клик по кнопке при
// непустом поле — тоже счёт, Claude клика не видит. Esc, клик по цифрам, кнопке
// или плашке, правка поля — отмена, текст остаётся. Повторный Enter во время
// счёта глотается при любом темпе, счёт идёт (#8773, WF125; до того «сразу», #8338);
// сразу шлёт только Shift+Enter (#8114). Счёт кончился — синтетический Enter в редактор;
// поле не опустело — кнопка; и так не ушло — плашка «Не ушло». Смена чата и
// dispose — ничего не уходит. Кеш остыл (час с последней активности, чат не
// работает) — цифры красные, красная плашка с «Отменить», один запрос /context;
// команда chat-context своего чата ставит число токенов.
// Стенд не ставит isTrusted сам — тесты ставят его явно; без него событие чужое.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_aaaa-1111";
const PLATE = "myclaude-send-delay";
const DIGITS = "myclaude-send-delay-digits";
const RED = "#e5484d";
const SEND_RECT = { left: 1070, top: 748, width: 24, height: 24 };

// Счёт в этих проверках — 5 с, выбранные явно (умолчание с 07.10 — 3 с, его проверки — seeded: false).
const page = ({ text = "привет", button = true, takesEnter = true, clicks = true, local = {}, seeded = true } = {}) => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Тест отсрочки",
    storage: { local: { "myclaude-auto-allow-roam": "off", ...(seeded ? { "myclaude-send-delay-seconds": "5" } : {}), ...local } },
    html: dom => {
      const parts = dom.composer({ text });
      // Claude: Enter в редакторе шлёт сообщение и уносит текст из поля.
      parts.enters = [];
      parts.editor.addEventListener("keydown", event => {
        if (event.key !== "Enter") return;
        parts.enters.push(event.isTrusted === true ? "trusted" : "synthetic");
        if (takesEnter) parts.editor.__text = "";
      });
      if (button) {
        parts.send = parts.modelRow.add("button", {
          attrs: { "data-testid": "code-prompt-send" },
          rect: SEND_RECT,
        });
        parts.send.__presses = 0;
        parts.send.addEventListener("pointerdown", () => {
          parts.send.__presses += 1;
          if (clicks) parts.editor.__text = "";
        });
      }
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  // Что дошло дальше перехватчика (слушатель на захвате document — после страницы).
  loaded.passed = [];
  loaded.document.addEventListener("keydown", event => loaded.passed.push(event.key), true);
  loaded.advance = (times = 1) => { for (let i = 0; i < times; i += 1) loaded.dom.fireKind("timeout"); };
  return loaded;
};
const enter = (loaded, extra = {}) => loaded.document.dispatchEvent({
  type: "keydown", key: "Enter", code: "Enter", target: loaded.parts.editor, isTrusted: true,
  bubbles: true, cancelable: true, ...extra,
});
const esc = loaded => loaded.win.dispatchEvent({
  type: "keydown", key: "Escape", code: "Escape", target: loaded.parts.editor, isTrusted: true,
  bubbles: true, cancelable: true,
});
const delay = loaded => plain(loaded.api.status().sendDelay);
const plate = loaded => loaded.document.getElementById(PLATE);
const plateShown = loaded => {
  const node = plate(loaded);
  return Boolean(node?.isConnected) && node.style.getPropertyValue("display") === "block";
};
const digits = loaded => loaded.document.getElementById(DIGITS);
const digitsShown = loaded => {
  const node = digits(loaded);
  return Boolean(node?.isConnected) && node.style.getPropertyValue("display") === "flex";
};
// Доверенное нажатие мышью: сперва захват document (наш перехватчик), и если он
// событие не заглушил — до самого узла (там слушает «Claude» стенда).
const press = (loaded, target, types = ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) =>
  types.map(type => {
    const event = () => ({ type, target, isTrusted: true, bubbles: true, cancelable: true });
    const passed = loaded.document.dispatchEvent(event());
    if (passed) target.dispatchEvent(event());
    return passed;
  });

test("Enter → счёт 5-4-3-2-1 цифрами поверх кнопки, через 5 с синтетический Enter в редактор — ушло", () => {
  const loaded = page();
  const allowed = enter(loaded);
  assert.equal(allowed, false, "Enter не отменён — Claude отправил бы сразу");
  assert.deepEqual(loaded.passed, [], "отложенный Enter дошёл до onPasteKey и дальше");
  assert.equal(delay(loaded).counting, true);
  assert.equal(delay(loaded).left, 5);
  assert.ok(digitsShown(loaded), "цифр на кнопке нет");
  assert.equal(digits(loaded).textContent, "5");
  const node = digits(loaded);
  assert.deepEqual(["left", "top", "width", "height"].map(name => node.style.getPropertyValue(name)),
    [`${SEND_RECT.left}px`, `${SEND_RECT.top}px`, `${SEND_RECT.width}px`, `${SEND_RECT.height}px`], "цифры не поверх кнопки");
  assert.equal(node.style.getPropertyValue("position"), "fixed");
  assert.equal(loaded.parts.send.children.length, 0, "в кнопку React что-то вставлено");
  assert.equal(plateShown(loaded), false, "тёплый чат с кнопкой — плашки нет, только цифры");
  assert.notEqual(node.style.getPropertyValue("color"), RED, "тёплый чат — не красным");

  for (const left of ["4", "3", "2", "1"]) {
    loaded.advance();
    assert.equal(digits(loaded).textContent, left);
  }
  assert.deepEqual(loaded.parts.enters, [], "ушло раньше срока");
  loaded.advance();
  assert.deepEqual(loaded.parts.enters, ["synthetic"], "отпускание — одним синтетическим Enter");
  assert.equal(digitsShown(loaded), false, "цифры остались после отпускания");
  assert.equal(delay(loaded).counting, false);
  loaded.advance();
  const state = delay(loaded);
  assert.equal(state.released, 1);
  assert.equal(state.sent, 1);
  assert.equal(state.immediate, 0);
  assert.equal(loaded.parts.send.__presses, 0, "кнопку жать не пришлось");
});

test("кнопки нет (свёрнутое поле) — счёт прежней плашкой над полем", () => {
  const loaded = page({ button: false });
  // Умолчание второго Enter — отмена (#8917): подпись обещает её первой.
  enter(loaded);
  assert.equal(digitsShown(loaded), false);
  assert.ok(plateShown(loaded), "плашки нет");
  // ⇧Enter во время счёта по умолчанию — перенос строки (WF192): подпись «сразу» не обещает.
  assert.equal(plate(loaded).textContent, "Отправка через 5 · Enter или Esc — отмена");
  loaded.advance();
  assert.equal(plate(loaded).textContent, "Отправка через 4 · Enter или Esc — отмена");
  press(loaded, plate(loaded));
  assert.equal(delay(loaded).counting, false);
  assert.equal(delay(loaded).last.why, "plate");
});

test("Esc во время счёта — отмена: ничего не ушло, текст на месте, Esc проглочен", () => {
  const loaded = page();
  enter(loaded);
  const allowed = esc(loaded);
  assert.equal(allowed, false, "Esc ушёл к Claude — остановил бы агента");
  assert.equal(delay(loaded).counting, false);
  assert.equal(delay(loaded).cancelled, 1);
  assert.equal(digitsShown(loaded), false);
  loaded.advance(8);
  assert.deepEqual(loaded.parts.enters, []);
  assert.equal(loaded.parts.editor.textContent, "привет");
  assert.equal(loaded.parts.send.__presses, 0);
});

test("правка поля во время счёта — отмена (событие input и тихая смена текста)", () => {
  const loaded = page();
  enter(loaded);
  loaded.parts.editor.__text = "привет, мир";
  loaded.document.dispatchEvent({ type: "input", target: loaded.parts.editor, isTrusted: true });
  assert.equal(delay(loaded).counting, false);
  assert.equal(delay(loaded).last.why, "edit");
  loaded.advance(8);
  assert.deepEqual(loaded.parts.enters, []);
  assert.equal(loaded.parts.editor.textContent, "привет, мир");

  // Текст сменился без input (вставка скриптом Диктатора) — тик это видит.
  enter(loaded);
  loaded.parts.editor.__text = "другое";
  loaded.advance(8);
  assert.deepEqual(loaded.parts.enters, []);
  assert.equal(delay(loaded).cancelled, 2);
});

test("клик по цифрам на кнопке — отмена, текст на месте, Claude нажатия не видит", () => {
  const loaded = page();
  enter(loaded);
  const allowed = press(loaded, digits(loaded));
  assert.deepEqual(allowed, [false, false, false, false, false], "нажатие по цифрам ушло дальше");
  assert.equal(delay(loaded).cancelled, 1, "отмена посчитана не один раз");
  assert.equal(delay(loaded).last.why, "plate");
  assert.equal(digitsShown(loaded), false);
  assert.equal(delay(loaded).started, 1, "нажатие по цифрам снова запустило счёт");
  loaded.advance(8);
  assert.deepEqual(loaded.parts.enters, []);
  assert.equal(loaded.parts.send.__presses, 0);
  assert.equal(loaded.parts.editor.textContent, "привет");
});

// #8773 (слово Элвиса 04.10 15:56, новее #8338 от 01.10): второй Enter во время
// счёта не отправляет и не отменяет — глотается, счёт идёт до конца сам.
test("второй Enter «ничего» (#8773, выбор в настройке #8917): глотается, счёт идёт дальше и дотикивает сам", () => {
  const loaded = page({ local: { "myclaude-send-delay-second": "none" } });
  enter(loaded);
  loaded.advance();
  const allowed = enter(loaded);
  assert.equal(allowed, false, "повторный Enter ушёл к Claude нетронутым");
  assert.deepEqual(loaded.passed, []);
  assert.equal(delay(loaded).counting, true, "повторный Enter отправил или отменил");
  assert.equal(delay(loaded).left, 4, "счёт сбился");
  assert.equal(delay(loaded).cancelled, 0);
  assert.equal(delay(loaded).immediate, 0);
  assert.equal(delay(loaded).released, 0);
  assert.deepEqual(loaded.parts.enters, [], "ушло раньше срока");
  assert.equal(digits(loaded).textContent, "4");
  loaded.advance(3);
  assert.deepEqual(loaded.parts.enters, [], "ушло раньше срока");
  loaded.advance();
  assert.deepEqual(loaded.parts.enters, ["synthetic"], "счёт дотикал — одна отправка");
  assert.equal(delay(loaded).last.why, "timer");
  loaded.advance(8);
  assert.deepEqual(loaded.parts.enters, ["synthetic"], "второй отправки нет");
  assert.equal(delay(loaded).sent, 1);
});

test("второй Enter «ничего»: быстрый двойной — то же самое, отправка только по счёту (#8773)", () => {
  const loaded = page({ local: { "myclaude-send-delay-second": "none" } });
  enter(loaded);
  assert.equal(enter(loaded), false);
  assert.equal(enter(loaded), false);
  assert.equal(delay(loaded).counting, true);
  assert.equal(delay(loaded).left, 5);
  assert.equal(delay(loaded).started, 1, "второй Enter поставил новый счёт");
  assert.equal(delay(loaded).immediate, 0);
  assert.equal(delay(loaded).cancelled, 0);
  assert.deepEqual(loaded.parts.enters, []);
});

// #8917 (слово Элвиса 07.10 ~03:10): по умолчанию второй Enter — отмена, текст остаётся в поле.
test("второй Enter по умолчанию — отмена: ничего не уходит, текст в поле, подпись обещает отмену", () => {
  const loaded = page();
  enter(loaded);
  loaded.advance();
  assert.equal(enter(loaded), false, "второй Enter ушёл к Claude");
  assert.equal(delay(loaded).counting, false);
  assert.equal(delay(loaded).cancelled, 1);
  assert.equal(delay(loaded).last.why, "enter");
  assert.equal(delay(loaded).second, "cancel");
  loaded.advance(8);
  assert.deepEqual(loaded.parts.enters, [], "отменённое ушло");
  assert.equal(loaded.parts.editor.textContent, "привет");
});

test("второй Enter «сразу» (выбор #8917): одна отправка сразу, без второй по таймеру", () => {
  const loaded = page({ local: { "myclaude-send-delay-second": "send" } });
  enter(loaded);
  assert.equal(enter(loaded), false);
  assert.deepEqual(loaded.parts.enters, ["synthetic"]);
  assert.equal(delay(loaded).immediate, 1);
  loaded.advance(8);
  assert.deepEqual(loaded.parts.enters, ["synthetic"], "второй отправки нет");
});

test("команда send-delay принимает second отдельно и не трогает секунды", () => {
  const loaded = page();
  loaded.dom.command({ id: "second-send", action: "send-delay", at: "2026-10-07T00:00:00Z", second: "send" });
  assert.equal(loaded.win.localStorage.getItem("myclaude-send-delay-second"), "send");
  assert.equal(loaded.win.localStorage.getItem("myclaude-send-delay-seconds"), "5");
  loaded.dom.command({ id: "second-weird", action: "send-delay", at: "2026-10-07T00:00:01Z", second: "weird" });
  assert.equal(loaded.win.localStorage.getItem("myclaude-send-delay-second"), "send");
  assert.equal(delay(loaded).second, "send");
});

test("автоповтор зажатого Enter — не «второй Enter»: глотается, счёт идёт", () => {
  const loaded = page();
  enter(loaded);
  assert.equal(enter(loaded, { repeat: true }), false);
  assert.equal(delay(loaded).counting, true);
  assert.equal(delay(loaded).immediate, 0);
  assert.deepEqual(loaded.parts.enters, []);
});

test("плашка без кнопки подсказывает «⇧Enter — сразу · Esc — отмена» (#8773): голый Enter сразу не шлёт", () => {
  // ⇧Enter «сразу» — явный выбор (с WF192 умолчание — перенос строки).
  const loaded = page({ button: false, ...{ local: { "myclaude-send-delay-second": "none", "myclaude-send-delay-shift": "send" } } });
  enter(loaded);
  assert.equal(plate(loaded).textContent, "Отправка через 5 · ⇧Enter — сразу · Esc — отмена");
  assert.equal(/(^|[^⇧])Enter — сразу/.test(plate(loaded).textContent), false, "голый Enter обещан как «сразу»");
});

test("клик по кнопке отправки во время счёта — отмена, Claude клика не видит", () => {
  const loaded = page();
  enter(loaded);
  const allowed = press(loaded, loaded.parts.send);
  assert.deepEqual(allowed, [false, false, false, false, false], "нажатие по кнопке ушло к Claude");
  assert.equal(loaded.parts.send.__presses, 0);
  assert.equal(delay(loaded).counting, false);
  assert.equal(delay(loaded).cancelled, 1);
  assert.equal(delay(loaded).last.why, "button");
  assert.equal(delay(loaded).immediate, 0);
  loaded.advance(8);
  assert.deepEqual(loaded.parts.enters, []);
  assert.equal(loaded.parts.editor.textContent, "привет");
});

test("клик по кнопке без счёта при непустом поле — счёт, как Enter; через 5 с — ушло", () => {
  const loaded = page();
  const allowed = press(loaded, loaded.parts.send);
  assert.deepEqual(allowed, [false, false, false, false, false], "первый клик мышью ушёл к Claude сразу");
  assert.equal(loaded.parts.send.__presses, 0);
  assert.equal(delay(loaded).counting, true);
  assert.equal(delay(loaded).started, 1, "счёт начат не один раз на один клик");
  assert.equal(digits(loaded).textContent, "5");
  loaded.advance(5);
  assert.deepEqual(loaded.parts.enters, ["synthetic"]);
  // Пустое поле — клик по кнопке к Claude как есть (там ему решать).
  const empty = page({ text: "" });
  assert.deepEqual(press(empty, empty.parts.send), [true, true, true, true, true]);
  assert.equal(empty.parts.send.__presses, 1);
  assert.equal(delay(empty).started, 0);
});

test("отсчёт выключен (myclaude-send-delay-off = 1) — Enter и кнопка уходят к Claude сразу, без цифр", () => {
  const loaded = page({ local: { "myclaude-send-delay-off": "1" } });
  assert.equal(enter(loaded), true, "Enter отложен при выключенном отсчёте");
  assert.deepEqual(loaded.passed, ["Enter"]);
  assert.equal(delay(loaded).off, true);
  const clicked = page({ local: { "myclaude-send-delay-off": "1" } });
  assert.deepEqual(press(clicked, clicked.parts.send), [true, true, true, true, true]);
  assert.equal(clicked.parts.send.__presses, 1);
  for (const one of [loaded, clicked]) {
    assert.equal(delay(one).started, 0);
    assert.equal(digits(one), null, "цифры появились");
    assert.equal(plate(one), null, "плашка появилась");
  }
  assert.equal(delay(page()).off, false, "по умолчанию отсчёт включён");
});

// ⌘Enter и ⌥Enter — перенос строки (WF192), их проверки — send-keys-wf192.test.mjs.
test("Shift+Enter, IME, пустое поле, открытое меню «/» — как раньше, без счёта", () => {
  const loaded = page();
  const cases = [{ shiftKey: true }, { isComposing: true }, { keyCode: 229 }];
  for (const extra of cases) {
    assert.equal(enter(loaded, extra), true, JSON.stringify(extra));
  }
  loaded.parts.editor.__text = "   ";
  assert.equal(enter(loaded), true, "пустое поле");
  loaded.parts.editor.__text = "/com";
  const menu = loaded.document.body.add("div", { attrs: { role: "listbox" }, rect: { left: 100, top: 500, width: 300, height: 120 } });
  assert.equal(enter(loaded), true, "Enter в меню подсказок отложен");
  menu.remove();
  const cmdk = loaded.document.body.add("div", { attrs: { "cmdk-root": "" }, rect: { left: 100, top: 500, width: 300, height: 120 } });
  assert.equal(enter(loaded), true, "Enter в cmdk отложен");
  cmdk.remove();
  assert.equal(loaded.passed.length, 6, "не все клавиши дошли до Claude");
  assert.equal(delay(loaded).started, 0);
  assert.equal(plate(loaded), null, "плашка появилась");
});

test("одни вложения в поле — Enter тоже откладывается", () => {
  const loaded = page({ text: "" });
  loaded.parts.block.add("div", { attrs: { "data-cds-attachment": "" } });
  loaded.api.status();
  assert.equal(enter(loaded), false);
  assert.equal(delay(loaded).counting, true);
});

test("чужой (синтетический) Enter и send-text Пимпа идут сразу, мимо счёта", () => {
  const loaded = page();
  assert.equal(loaded.document.dispatchEvent({ type: "keydown", key: "Enter", target: loaded.parts.editor, bubbles: true }), true);
  assert.equal(loaded.document.dispatchEvent({ type: "keydown", key: "Enter", target: loaded.parts.editor, isTrusted: false }), true);
  assert.equal(delay(loaded).started, 0);

  const empty = page({ text: "" });
  // Часы send-text (now() — performance.now) двигает тест, как в send-wf103.
  let t = 1_000_000;
  empty.win.performance.now = () => t;
  empty.dom.command({ id: "s-1", action: "send-text", at: "2026-09-29T12:00:00Z", chat: CHAT, text: "Текст Пимпа." });
  for (let i = 0; i < 5; i += 1) { t += 200; empty.advance(); }
  assert.equal(empty.parts.send.__presses, 1, "send-text не нажал отправку");
  assert.equal(plain(empty.api.status().send).state, "sent");
  assert.equal(delay(empty).started, 0);
});

test("смена чата во время счёта — ничего не ушло, плашки нет", () => {
  const loaded = page();
  enter(loaded);
  loaded.win.location.pathname = "/epitaxy/local_bbbb-2222";
  loaded.win.location.href = "https://claude.ai/epitaxy/local_bbbb-2222";
  loaded.advance();
  // Плашка не пропадает молча — иначе кажется, что ушло (проверка WF105).
  assert.ok(plateShown(loaded), "плашка пропала молча");
  assert.equal(plate(loaded).textContent, "Не отправлено — чат сменился");
  loaded.advance(8);
  assert.deepEqual(loaded.parts.enters, []);
  assert.equal(loaded.parts.send.__presses, 0);
  assert.equal(plateShown(loaded), false);
  assert.equal(digitsShown(loaded), false);
  assert.equal(delay(loaded).dropped, 1);
  assert.equal(delay(loaded).last.why, "chat");
});

test("автоповтор зажатого Enter и IME во время счёта — не «сразу»: глотается или мимо, счёт идёт", () => {
  const loaded = page();
  enter(loaded);
  const allowed = enter(loaded, { repeat: true });
  assert.equal(allowed, false, "автоповтор ушёл к Claude — отправил бы сразу");
  assert.deepEqual(loaded.passed, []);
  enter(loaded, { keyCode: 229 });
  assert.equal(delay(loaded).counting, true, "счёт погас от автоповтора или модификатора");
  assert.equal(delay(loaded).immediate, 0);
  loaded.advance(5);
  assert.deepEqual(loaded.parts.enters.filter(kind => kind === "synthetic"), ["synthetic"]);
});

test("обход чатов во время счёта — ничего не ушло", () => {
  const loaded = page();
  enter(loaded);
  loaded.inner.roamState.phase = "going";
  loaded.advance(8);
  loaded.inner.roamState.phase = "idle";
  assert.deepEqual(loaded.parts.enters, []);
  assert.equal(delay(loaded).last.why, "roam");
});

test("dispose во время счёта — ничего не ушло, цифр, плашки и таймеров отсрочки нет", () => {
  const loaded = page();
  enter(loaded);
  const node = digits(loaded);
  loaded.api.dispose();
  assert.equal(node.isConnected, false, "цифры пережили dispose");
  assert.equal(plate(loaded), null, "плашка пережила dispose");
  loaded.advance(8);
  assert.deepEqual(loaded.parts.enters, []);
  assert.equal(loaded.parts.send.__presses, 0);
});

test("повторный инжект: плашка одна, счёт прошлого экземпляра не отпускает", () => {
  const loaded = page();
  enter(loaded);
  loaded.win.__myclaude.dispose();
  loaded.advance(8);
  assert.deepEqual(loaded.parts.enters, []);
  assert.equal(loaded.document.querySelectorAll(`#${PLATE}`).length, 0);
  assert.equal(loaded.document.querySelectorAll(`#${DIGITS}`).length, 0);
});

test("Enter не принят — через 1,5 с нажата кнопка отправки", () => {
  const loaded = page({ takesEnter: false });
  enter(loaded);
  loaded.advance(5);
  assert.deepEqual(loaded.parts.enters, ["synthetic"]);
  loaded.advance();
  assert.equal(loaded.parts.send.__presses, 1);
  loaded.advance();
  assert.equal(delay(loaded).sent, 1);
  assert.equal(delay(loaded).last.why, "button");
});

test("не ушло и кнопкой — плашка «Не ушло», текст остаётся, следующий Enter — сразу", () => {
  const loaded = page({ takesEnter: false, clicks: false });
  enter(loaded);
  loaded.advance(7);
  assert.equal(loaded.parts.send.__presses, 1);
  assert.equal(delay(loaded).failed, 1);
  assert.ok(plateShown(loaded));
  assert.equal(plate(loaded).textContent, "Не ушло — Enter отправит сразу");
  assert.equal(loaded.parts.editor.textContent, "привет");
  loaded.advance();
  assert.equal(plateShown(loaded), false, "плашка «не ушло» не ушла сама");
  // Повтор после «Не ушло» — к Claude сам, без нового счёта (гейт WF105).
  const allowed = enter(loaded);
  assert.notEqual(allowed, false, "повтор после «Не ушло» снова встал в счёт");
  assert.equal(delay(loaded).counting, false);
  assert.equal(delay(loaded).started, 1);
  // Дальше — снова обычная отсрочка.
  enter(loaded);
  assert.equal(delay(loaded).counting, true);
});

test("после «Не ушло» и кнопка отправляет сразу, как Enter", () => {
  const loaded = page({ takesEnter: false, clicks: false });
  enter(loaded);
  loaded.advance(8);
  assert.equal(delay(loaded).failed, 1);
  const presses = loaded.parts.send.__presses;
  assert.deepEqual(press(loaded, loaded.parts.send), [true, true, true, true, true], "повтор кнопкой снова встал в счёт");
  assert.equal(loaded.parts.send.__presses, presses + 1);
  assert.equal(delay(loaded).started, 1);
});

// ---- остывший кеш (WF106, решение 5) -----------------------------------------

const MIN = 60000;
const cold = (loaded, ago = 61 * MIN) => {
  loaded.inner.sigState.chat = CHAT;
  loaded.inner.sigState.lastAt = Date.now() - ago;
  loaded.fetched = [];
  loaded.win.fetch = (url, init) => { loaded.fetched.push({ url, init }); return Promise.resolve({}); };
  return loaded;
};
const context = (loaded, detail) => loaded.dom.command({ id: `ctx-${Math.random()}`, action: "chat-context", at: "now", ...detail });

test("кеш остыл — цифры красные, красная плашка с «Отменить», один запрос /context за счёт", () => {
  const loaded = cold(page());
  enter(loaded);
  assert.equal(delay(loaded).cold, true);
  // Вид 1.8 (умолчание WF128): красные ободок, цифра и метка; 1.5 — красная заливка (send-delay-18).
  assert.equal(digits(loaded).style.getPropertyValue("border-color"), RED, "холодный счёт не красный");
  assert.ok(plateShown(loaded), "плашки нет");
  assert.equal(plate(loaded).style.getPropertyValue("background"), RED, "плашка не красная");
  assert.equal(plate(loaded).textContent, "Кеш остыл — весь чат перечитается заново" + "Отменить");
  assert.equal(plate(loaded).querySelector("button")?.textContent, "Отменить", "кнопки «Отменить» нет");
  assert.deepEqual(loaded.fetched.map(item => item.url), [`http://127.0.0.1:47615/context?chat=${CHAT}`]);
  assert.equal(loaded.fetched[0].init.mode, "cors");
  assert.equal(loaded.fetched[0].init.credentials, "omit");
  loaded.advance(2);
  assert.equal(loaded.fetched.length, 1, "запрос /context не один за счёт");
  assert.equal(delay(loaded).asks, 1);
  // «Отменить» — отмена, ничего не уходит.
  press(loaded, plate(loaded).querySelector("button"));
  assert.equal(delay(loaded).counting, false);
  assert.equal(delay(loaded).last.why, "plate");
  assert.equal(plateShown(loaded), false);
  assert.equal(digitsShown(loaded), false);
  loaded.advance(8);
  assert.deepEqual(loaded.parts.enters, []);
});

test("chat-context своего чата во время счёта — число токенов на плашке; чужой чат и без счёта — нет", () => {
  const loaded = cold(page());
  context(loaded, { chat: CHAT, tokens: 412345 });
  assert.equal(delay(loaded).tokens, null, "число принято без счёта");
  enter(loaded);
  context(loaded, { chat: "local_bbbb-2222", tokens: 9000 });
  assert.equal(delay(loaded).tokens, null, "принято число чужого чата");
  assert.ok(plate(loaded).textContent.startsWith("Кеш остыл — весь чат перечитается заново"));
  context(loaded, { chat: CHAT, tokens: "мусор" });
  assert.equal(delay(loaded).tokens, null);
  context(loaded, { chat: CHAT, tokens: 412345 });
  assert.equal(delay(loaded).tokens, 412345);
  assert.equal(plate(loaded).textContent, "Кеш остыл — перечитается ~412 345 токенов" + "Отменить");
  loaded.advance();
  assert.ok(plate(loaded).textContent.startsWith("Кеш остыл — перечитается ~412 345 токенов"), "число пропало на тике");
  assert.equal(digits(loaded).textContent, "4");
  loaded.advance(4);
  assert.deepEqual(loaded.parts.enters, ["synthetic"], "холодный чат не отправился по истечении 5 с");
  assert.equal(plateShown(loaded), false);
  assert.equal(delay(loaded).tokens, null);
});

test("тёплый кеш, чат работает или времени нет — без тревоги и без /context", () => {
  for (const [name, setup] of [
    ["59 минут", loaded => cold(loaded, 59 * MIN)],
    ["чат работает", loaded => { cold(loaded); loaded.inner.waitState.kind = "running"; }],
    ["времени нет", loaded => { cold(loaded); loaded.inner.sigState.lastAt = 0; }],
  ]) {
    const loaded = page();
    setup(loaded);
    enter(loaded);
    assert.equal(delay(loaded).counting, true, name);
    assert.equal(delay(loaded).cold, false, name);
    assert.equal(plateShown(loaded), false, `${name}: плашка тревоги`);
    assert.notEqual(digits(loaded).style.getPropertyValue("color"), RED, `${name}: цифры красные`);
    assert.deepEqual(loaded.fetched, [], `${name}: запрос /context`);
  }
});

test("Shift+Enter во время счёта при явном «сразу» — отправить сразу; без счёта — перенос строки, как всегда (#8114)", () => {
  // С WF192 «сразу» — только явным выбором (ключ "send"), умолчание — перенос строки.
  const loaded = page({ local: { "myclaude-send-delay-shift": "send" } });
  // Без счёта Shift+Enter до Claude доходит нетронутым — перенос строки.
  const plainShift = enter(loaded, { shiftKey: true });
  assert.notEqual(plainShift, false, "Shift+Enter без счёта съеден — сломали перенос строки");
  assert.equal(delay(loaded).counting, false);
  enter(loaded);
  assert.equal(delay(loaded).counting, true);
  const fast = enter(loaded, { shiftKey: true });
  assert.equal(fast, false, "Shift+Enter во время счёта дошёл до Claude — вставил бы перенос строки");
  assert.equal(delay(loaded).counting, false);
  assert.deepEqual(loaded.parts.enters.filter(kind => kind === "synthetic"), ["synthetic"], "ушло сразу, одним Enter");
  assert.equal(delay(loaded).immediate, 1);
  assert.equal(delay(loaded).last.why, "timer");
  loaded.advance(6);
  assert.deepEqual(loaded.parts.enters.filter(kind => kind === "synthetic"), ["synthetic"], "второй отправки нет");
});

for (const change of ["chat", "editor", "text", "whitespace", "attachment"]) {
  test(`F02 delayed Enter fallback: ${change} не отправляет новый черновик`, () => {
    const loaded = page({ takesEnter: false });
    enter(loaded);
    loaded.advance(5);
    assert.deepEqual(loaded.parts.enters, ["synthetic"]);
    let current = loaded.parts.editor;
    if (change === "chat") {
      loaded.win.location.pathname = "/epitaxy/local_bbbb-2222";
      loaded.win.location.href = "https://claude.ai/epitaxy/local_bbbb-2222";
    } else if (change === "editor") {
      current.remove();
      current = loaded.dom.composer({ text: "привет" }).editor;
    } else if (change === "text") current.__text = "новый черновик";
    else if (change === "whitespace") current.__text += " ";
    else loaded.dom.pill(loaded.parts.block, { name: "новое фото.png" });
    const draft = current.textContent;
    loaded.advance(8);
    assert.equal(loaded.parts.send.__presses, 0);
    assert.equal(current.textContent, draft);
  });
}

test("изменились вложения во время общего отсчёта — отмена до Enter", () => {
  const loaded = page();
  enter(loaded);
  loaded.dom.pill(loaded.parts.block, { name: "новое фото.png" });
  loaded.advance(6);
  assert.deepEqual(loaded.parts.enters, []);
  assert.equal(loaded.parts.send.__presses, 0);
  assert.equal(delay(loaded).cancelled, 1);
});

test("вложение заменено в том же узле до fallback — нажатия нет", () => {
  const loaded = page({ takesEnter: false });
  const tile = loaded.dom.pill(loaded.parts.block, { name: "old.png" });
  enter(loaded);
  loaded.advance(5);
  tile.querySelector("button").setAttribute("aria-label", "Remove new.png");
  loaded.advance(8);
  assert.equal(loaded.parts.send.__presses, 0);
  assert.equal(tile.querySelector("button").getAttribute("aria-label"), "Remove new.png");
});

// WF111 (судья page): React перерисовывает плитку при загрузке — новый узел,
// подпись прогресса, другой src превью; имя то же — счёт идёт до конца и уходит.
test("плитка перерисована с тем же именем — счёт не гаснет, сообщение уходит", () => {
  const loaded = page();
  const old = loaded.dom.pill(loaded.parts.block, { name: "снимок.png" });
  old.add("span", { text: "12%" });
  enter(loaded);
  loaded.advance(2);
  old.remove();
  const fresh = loaded.dom.pill(loaded.parts.block, { name: "снимок.png" });
  fresh.querySelector("img").setAttribute("src", "blob:claude/uploaded");
  fresh.add("span", { text: "100%" });
  loaded.advance(3);
  assert.equal(delay(loaded).cancelled, 0);
  assert.deepEqual(loaded.parts.enters, ["synthetic"], "счёт досчитал, Enter ушёл");
});

test("плитка вне поля ввода (лента) счёт не трогает", () => {
  const loaded = page();
  enter(loaded);
  loaded.document.body.add("div", { class: "epitaxy-attachment-pill", text: "фото в ленте" });
  loaded.advance(5);
  assert.equal(delay(loaded).cancelled, 0);
  assert.deepEqual(loaded.parts.enters, ["synthetic"]);
});

const OFF_KEY = "myclaude-send-delay-off";
const SECONDS_KEY = "myclaude-send-delay-seconds";
const setting = (loaded, on, seconds) => loaded.dom.command({ id: `delay-${on}-${seconds}`, action: "send-delay", at: "2026-10-03T00:00:00Z", on, seconds });

for (const seconds of [3, 5, 10]) {
  test(`WF119 send-delay ${seconds}: сохранение, N→1 и одна отправка`, () => {
    const p = page({ local: { [OFF_KEY]: "1" } });
    setting(p, true, seconds);
    assert.equal(p.win.localStorage.getItem(OFF_KEY), null);
    assert.equal(p.win.localStorage.getItem(SECONDS_KEY), String(seconds));
    enter(p);
    for (let left = seconds; left > 0; left--) {
      assert.equal(delay(p).left, left);
      assert.equal(delay(p).released, 0);
      p.advance();
    }
    assert.equal(delay(p).released, 1);
    assert.deepEqual(p.parts.enters, ["synthetic"]);
    p.api.dispose();
  });
}

test("WF119 точные on/off JSON, повтор on сохраняет текущий таймер", async () => {
  const p = page();
  p.dom.command(JSON.parse('{"id":"wf119-delay-on","action":"send-delay","at":"2026-10-03T00:00:00Z","on":true,"seconds":3}'));
  enter(p); p.advance();
  setting(p, true, 3);
  assert.equal(delay(p).left, 2);
  assert.equal(delay(p).started, 1);
  assert.deepEqual(plain((await p.api.chats()).sendDelaySetting), { on: true, seconds: 3 });
  p.dom.command(JSON.parse('{"id":"wf119-delay-off","action":"send-delay","at":"2026-10-03T00:00:01Z","on":false,"seconds":3}'));
  assert.equal(delay(p).counting, false);
  assert.equal(delay(p).cancelled, 1);
  assert.equal(p.parts.editor.textContent, "привет");
  assert.deepEqual(plain((await p.api.chats()).sendDelaySetting), { on: false, seconds: 3 });
  assert.equal(p.win.localStorage.getItem(OFF_KEY), "1");
  assert.equal(p.win.localStorage.getItem(SECONDS_KEY), "3");
  p.advance(10);
  assert.equal(delay(p).released, 0);
  assert.equal(enter(p), true);
  p.api.dispose();
});

test("WF119: без явного выбора off и seconds не переписываются, чтение берёт on/3", async () => {
  for (const local of [{}, { [OFF_KEY]: "1" }, { [OFF_KEY]: "other", [SECONDS_KEY]: "03" }, { [SECONDS_KEY]: "10" }]) {
    const p = page({ local, seeded: false });
    const before = [p.win.localStorage.getItem(OFF_KEY), p.win.localStorage.getItem(SECONDS_KEY)];
    assert.equal(delay(p).seconds, local[SECONDS_KEY] === "10" ? 10 : 3);
    assert.deepEqual(plain((await p.api.chats()).sendDelaySetting), { on: local[OFF_KEY] !== "1", seconds: local[SECONDS_KEY] === "10" ? 10 : 3 });
    assert.equal(p.reload().error, null);
    assert.deepEqual([p.win.localStorage.getItem(OFF_KEY), p.win.localStorage.getItem(SECONDS_KEY)], before);
    p.api.dispose();
  }
});

test("WF119: неверная команда целиком игнорируется, в том числе при активном счёте", () => {
  const p = page(); setting(p, true, 3); enter(p);
  for (const bad of [{}, { on: true }, { seconds: 10 }, { on: "false", seconds: 10 }, { on: 0, seconds: 3 },
    ...[null, true, "3", 3.5, 0, -3, 4, NaN].map(seconds => ({ on: false, seconds }))]) {
    p.dom.command({ id: "invalid-delay", action: "send-delay", ...bad });
    assert.equal(p.win.localStorage.getItem(OFF_KEY), null);
    assert.equal(p.win.localStorage.getItem(SECONDS_KEY), "3");
    assert.equal(delay(p).left, 3);
    assert.equal(delay(p).counting, true);
  }
  p.api.dispose();
});

test("WF119: изменение seconds/off командой, напрямую на тике и перед release отменяет отправку", () => {
  for (const change of [p => setting(p, true, 10), p => p.win.localStorage.setItem(OFF_KEY, "1"),
    p => p.win.localStorage.setItem(SECONDS_KEY, "3")]) {
    for (const immediate of [false, true]) {
      const p = page({ local: { "myclaude-send-delay-shift": "send" } }); enter(p); change(p);
      if (immediate && delay(p).counting) enter(p, { shiftKey: true }); else p.advance();
      assert.equal(delay(p).counting, false);
      assert.equal(delay(p).released, 0);
      assert.equal(p.parts.editor.textContent, "привет");
      p.advance(12);
      assert.deepEqual(p.parts.enters, []);
      p.api.dispose();
    }
  }
});

test("WF119: themable без поля/фокуса принимает send-delay, чужая страница игнорирует", async () => {
  const p = loadInject({ href: `https://claude.ai/epitaxy/${CHAT}`, hasFocus: false });
  setting(p, false, 10);
  assert.deepEqual(plain((await p.api.chats()).sendDelaySetting), { on: false, seconds: 10 });
  const q = loadInject({ href: "https://example.com/", hasFocus: false });
  setting(q, false, 3);
  assert.equal(q.win.localStorage.getItem(OFF_KEY), null);
  assert.equal((await q.api.chats()).sendDelaySetting, undefined);
  p.api.dispose(); q.api.dispose();
});

test("WF119: недоступное LS — безопасное on/3 без исключения", () => {
  const p = page({ seeded: false });
  p.win.localStorage.getItem = () => { throw new Error("blocked"); };
  p.win.localStorage.setItem = () => { throw new Error("blocked"); };
  p.win.localStorage.removeItem = () => { throw new Error("blocked"); };
  assert.doesNotThrow(() => setting(p, false, 3));
  assert.equal(delay(p).off, false);
  assert.equal(delay(p).seconds, 3);
  enter(p); assert.equal(delay(p).left, 3); p.api.dispose();
});

// WF126 §7.2 (поправка критика 2): ⇧Enter во время счёта — «отправить» или «новая строка» (умолчание с WF192).
test("WF126: shift=newline — ⇧Enter во время счёта идёт к редактору, не шлёт; подпись без «⇧Enter — сразу»", () => {
  const loaded = page({ button: false, local: { "myclaude-send-delay-shift": "newline" } });
  enter(loaded);
  assert.equal(plate(loaded).textContent, "Отправка через 5 · Enter или Esc — отмена");
  assert.equal(delay(loaded).shift, "newline");
  const passed = enter(loaded, { shiftKey: true });
  assert.notEqual(passed, false, "⇧Enter проглочен — перенос строки не дошёл до редактора");
  assert.equal(delay(loaded).immediate, 0);
  assert.deepEqual(loaded.passed, ["Enter"], "⇧Enter не прошёл дальше перехватчика");
  assert.deepEqual(loaded.parts.enters, [], "синтетический Enter — отправка");
  // Правка поля (перенос строки) гасит счёт, как любая правка.
  loaded.parts.editor.__text = "привет\n";
  loaded.advance(8);
  assert.equal(delay(loaded).counting, false);
  assert.equal(delay(loaded).last.why, "edit");
  assert.equal(delay(loaded).sent, 0);
});

test("WF126/WF192: команда send-delay принимает shift отдельно, newline (умолчание) снимает ключ, чужое — отказ", () => {
  const loaded = page();
  assert.equal(delay(loaded).shift, "newline", "умолчание — перенос строки (WF192: никаких быстрых отправок)");
  loaded.dom.command({ id: "shift-send", action: "send-delay", at: "2026-10-07T00:00:00Z", shift: "send" });
  assert.equal(loaded.win.localStorage.getItem("myclaude-send-delay-shift"), "send");
  assert.equal(loaded.win.localStorage.getItem("myclaude-send-delay-seconds"), "5", "секунды тронуты");
  loaded.dom.command({ id: "shift-weird", action: "send-delay", at: "2026-10-07T00:00:01Z", shift: "jump" });
  assert.equal(delay(loaded).shift, "send");
  loaded.dom.command({ id: "both", action: "send-delay", at: "2026-10-07T00:00:02Z", second: "none", shift: "newline" });
  assert.equal(loaded.win.localStorage.getItem("myclaude-send-delay-shift"), null);
  assert.equal(delay(loaded).second, "none");
  assert.equal(delay(loaded).shift, "newline");
});

test("WF126: второй Enter «ничего» и ⇧Enter «новая строка» — подпись только «Esc — отмена»", () => {
  const loaded = page({ button: false, local: { "myclaude-send-delay-second": "none", "myclaude-send-delay-shift": "newline" } });
  enter(loaded);
  assert.equal(plate(loaded).textContent, "Отправка через 5 · Esc — отмена");
});
