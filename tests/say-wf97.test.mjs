// WF97, батч Б0 (страница, раздел 12р inject.js): слово Элвиса 26.09 ~04:00
// (#7755) — жирные «фразы» блока «❗ Скажи — и сделаю ❗» становятся кнопками:
// клик кладёт слово в поле и подсвечивает его, второй клик добавляет следом,
// клик по выбранному снимает; после каждого клика отсчёт 5 с заново; дотикал —
// сообщение уходит само, без клавиатуры. Свой текст в поле — ничего не шлём.
//
// Время отсчёта — аргумент sayTick (люк), таймеры стенда не ждём. Нажатие —
// событие click на document с целью-словом (стенд событий не всплывает).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const SAY = "data-myclaude-say";
const LEFT = "data-myclaude-say-left";

// Лента с ответами (разметка — живой замер 26.09: h3 и p со strong в одной
// строке transcript-row/assistant_text), поле ввода и кнопка отправки.
const page = ({ text = "", foreign = false } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_aaaa-1111", title: "Trelvis",
    storage: { local: { "myclaude-auto-allow-roam": "off", "myclaude-send-delay-seconds": "5", "myclaude-send-delay-second": "none" } },
    html: dom => {
      const parts = dom.composer({ text });
      const feed = dom.document.body.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript" },
        rect: { left: 0, top: 0, width: 1200, height: 500 },
      });
      const row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" } });
      const box = row.add("div", { class: "contents" });
      const para = (word, rest) => {
        const node = box.add("p");
        const strong = node.add("strong", { text: `«${word}»` });
        node.add("span", { text: ` — ${rest}` });
        return strong;
      };
      if (foreign) box.add("h3", { text: "Кнопки в «Скажи — и сделаю»" });
      else box.add("h3", { text: "❗ Скажи — и сделаю ❗" });
      parts.clean = para("чисти", "склею повторы");
      parts.go = para("поехали", "план следующей пачки");
      box.add("h3", { text: "Pimp Viewer" });
      parts.other = para("другое", "не из блока");
      parts.head = box.children[0];
      parts.send = parts.modelRow.add("button", {
        attrs: { "data-testid": "code-prompt-send" },
        rect: { left: 1150, top: 700, width: 24, height: 24 },
      });
      parts.send.__presses = 0;
      parts.send.addEventListener("pointerdown", () => { parts.send.__presses += 1; parts.editor.__text = ""; });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  caret(loaded);
  let t = Date.now();
  loaded.inner.sayTick(t);
  const tick = (step = 500) => { t += step; loaded.inner.sayTick(t); };
  const click = node => {
    loaded.dom.document.dispatchEvent({ type: "click", target: node });
    // Отсчёт считается от времени нажатия: стенд двигает свои часы от того же now().
    t = Date.now();
  };
  return { loaded, tick, click };
};
// Курсор и выделение в поле, как в Chromium (находка 6 проверки гейта 1): стенд
// вставляет в начало, а свой текст Элвиса пишется с курсора в конце и хвост
// выделяется назад Selection.modify. Выделение [start, end) в тексте поля.
const caret = loaded => {
  const doc = loaded.dom.document;
  const editor = loaded.parts.editor;
  let start = 0;
  let end = 0;
  doc.createRange = () => {
    const range = {
      end: false, setStart() {}, setEnd() {}, selectNodeContents() {},
      collapse(toStart) { range.end = !toStart; },
      getBoundingClientRect: () => ({ left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0 }),
    };
    return range;
  };
  const selection = {
    rangeCount: 1, getRangeAt: () => null, toString: () => editor.__text.slice(start, end), removeAllRanges() {},
    addRange(range) { start = end = range.end ? editor.__text.length : 0; },
    modify(alter, direction) { if (alter === "extend" && direction === "backward") start = Math.max(0, start - 1); },
  };
  loaded.win.getSelection = () => selection;
  doc.getSelection = () => selection;
  const stock = doc.execCommand;
  doc.execCommand = (name, ui, value) => {
    if ((name !== "insertText" && name !== "delete") || doc.__selectedAll) return stock(name, ui, value);
    if (doc.activeElement !== editor) return false;
    const put = name === "insertText" ? String(value) : "";
    editor.__text = editor.__text.slice(0, start) + put + editor.__text.slice(end);
    start = end = start + put.length;
    return true;
  };
};
const say = loaded => plain(loaded.api.status().say);
const field = loaded => loaded.parts.editor.textContent;

test("#7755: жирные слова блока — кнопки; вне блока — нет", () => {
  const { loaded } = page();
  assert.equal(loaded.parts.clean.getAttribute(SAY), "");
  assert.equal(loaded.parts.go.getAttribute(SAY), "");
  assert.equal(loaded.parts.other.hasAttribute(SAY), false, "после следующего заголовка — уже не блок");
  assert.deepEqual(say(loaded), { armed: false, words: [], left: 0, sends: 0 });
});

test("#7755: заголовок без «❗ Скажи — и сделаю ❗» целиком — не блок", () => {
  const { loaded } = page({ foreign: true });
  assert.equal(loaded.parts.clean.hasAttribute(SAY), false);
  loaded.dom.document.dispatchEvent({ type: "click", target: loaded.parts.clean });
  assert.equal(field(loaded), "");
});

test("#7755: клик — слово в поле, подсвечено, отсчёт 5", () => {
  const { loaded, tick, click } = page();
  click(loaded.parts.clean);
  assert.equal(field(loaded), "чисти");
  assert.equal(loaded.parts.clean.getAttribute(SAY), "on");
  assert.deepEqual(say(loaded), { armed: true, words: ["чисти"], left: 5, sends: 0 });
  assert.equal(loaded.parts.head.getAttribute(LEFT), "5");
  tick(1200);
  assert.equal(say(loaded).left, 4);
  assert.equal(loaded.parts.head.getAttribute(LEFT), "4");
});

test("#7755: второй клик — слово следом, отсчёт с 5 заново", () => {
  const { loaded, tick, click } = page();
  click(loaded.parts.clean);
  tick(3000);
  assert.equal(say(loaded).left, 2);
  click(loaded.parts.go);
  // #8687 (WF125): слова в поле — каждое с новой строки, не одной фразой через пробел.
  assert.equal(field(loaded), "чисти\nпоехали");
  assert.deepEqual(say(loaded), { armed: true, words: ["чисти", "поехали"], left: 5, sends: 0 });
  tick(3000);
  assert.equal(loaded.parts.send.__presses, 0, "первый отсчёт сброшен вторым кликом");
});

test("#7755: клик по выбранному — снято из поля и подсветки, отсчёт заново; всё снято — отсчёта нет", () => {
  const { loaded, tick, click } = page();
  click(loaded.parts.clean);
  click(loaded.parts.go);
  tick(4000);
  click(loaded.parts.clean);
  assert.equal(field(loaded), "поехали");
  assert.equal(loaded.parts.clean.getAttribute(SAY), "");
  assert.deepEqual(say(loaded), { armed: true, words: ["поехали"], left: 5, sends: 0 });
  click(loaded.parts.go);
  assert.equal(field(loaded), "");
  assert.deepEqual(say(loaded), { armed: false, words: [], left: 0, sends: 0 });
  assert.equal(loaded.parts.head.hasAttribute(LEFT), false, "пилюля отсчёта убрана");
  tick(6000);
  assert.equal(loaded.parts.send.__presses, 0);
});

test("#7755: дотикал — «отправить» нажат сам, выбор сброшен", () => {
  const { loaded, tick, click } = page();
  click(loaded.parts.clean);
  click(loaded.parts.go);
  tick(4900);
  assert.equal(loaded.parts.send.__presses, 0, "рано");
  tick(200);
  assert.equal(loaded.parts.send.__presses, 0, "первые 5 с только включают настоящий счёт");
  assert.equal(loaded.api.status().sendDelay.counting, true);
  assert.equal(loaded.api.status().sendDelay.left, 5);
  for (let n = 0; n < 7; n += 1) loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.send.__presses, 1);
  assert.deepEqual(say(loaded), { armed: false, words: [], left: 0, sends: 1 });
  assert.equal(loaded.parts.clean.getAttribute(SAY), "");
  tick(6000);
  assert.equal(loaded.parts.send.__presses, 1, "второй раз не шлём");
});

test("#7755: свой текст в поле — слово дописано, но ничего не шлём", () => {
  const { loaded, tick, click } = page({ text: "мой черновик" });
  click(loaded.parts.go);
  assert.equal(field(loaded), "мой черновик\nпоехали", "слово — с новой строки (#8687)");
  assert.equal(say(loaded).armed, false);
  tick(6000);
  assert.equal(loaded.parts.send.__presses, 0);
  click(loaded.parts.go);
  assert.equal(field(loaded), "мой черновик", "снятие возвращает свой текст как был");
});

test("#7755: черновик с абзацами — клик и снятие не трогают его, побайтно (находка 6)", () => {
  const draft = "первая строка\n\n  код:  x = 1\nпоследняя";
  const { loaded, click } = page({ text: draft });
  click(loaded.parts.go);
  assert.equal(field(loaded), `${draft}\nпоехали`, "слово — в конец с новой строки, черновик как был");
  click(loaded.parts.clean);
  assert.equal(field(loaded), `${draft}\nпоехали\nчисти`);
  click(loaded.parts.go);
  assert.equal(field(loaded), `${draft}\nчисти`, "снято только слово из хвоста");
  click(loaded.parts.clean);
  assert.equal(field(loaded), draft, "всё снято — черновик побайтно прежний");
  assert.equal(say(loaded).armed, false);
});

test("#7755: одни выбранные слова — поле пересобирается целиком", () => {
  const { loaded, click } = page();
  click(loaded.parts.clean);
  click(loaded.parts.go);
  click(loaded.parts.clean);
  assert.equal(field(loaded), "поехали");
  assert.equal(say(loaded).armed, true);
});

test("#7755: Элвис дописал в поле посреди отсчёта — отсчёт гаснет, слова остаются", () => {
  const { loaded, tick, click } = page();
  click(loaded.parts.clean);
  loaded.parts.editor.__text = "чисти и ещё";
  tick(6000);
  assert.equal(loaded.parts.send.__presses, 0);
  assert.equal(say(loaded).armed, false);
  assert.deepEqual(say(loaded).words, ["чисти"]);
});

test("#7755: клавиша в поле и клик по пилюле гасят отсчёт", () => {
  const { loaded, tick, click } = page();
  click(loaded.parts.clean);
  loaded.win.dispatchEvent({ type: "keydown", key: "a", target: loaded.parts.editor });
  assert.equal(say(loaded).armed, false);
  click(loaded.parts.go);
  assert.equal(say(loaded).armed, true);
  loaded.dom.document.dispatchEvent({ type: "click", target: loaded.parts.head });
  assert.equal(say(loaded).armed, false);
  assert.equal(field(loaded), "чисти\nпоехали", "слова остаются");
  tick(6000);
  assert.equal(loaded.parts.send.__presses, 0);
});

test("#7755: новый ход (стоп появился) — выбор и отсчёт сброшены", () => {
  const { loaded, tick, click } = page();
  click(loaded.parts.clean);
  loaded.dom.document.body.add("button", { attrs: { "data-testid": "code-prompt-stop" } });
  tick();
  assert.deepEqual(say(loaded), { armed: false, words: [], left: 0, sends: 0 });
  tick(6000);
  assert.equal(loaded.parts.send.__presses, 0);
});

test("#7755: снятие экземпляра убирает метки", () => {
  const { loaded, click } = page();
  click(loaded.parts.clean);
  loaded.api.dispose();
  assert.equal(loaded.parts.clean.hasAttribute(SAY), false);
  assert.equal(loaded.parts.go.hasAttribute(SAY), false);
  assert.equal(loaded.parts.head.hasAttribute(LEFT), false);
});

test("#7755: свёрнутое поле (режим чтения) — слово ложится и уходит так же", () => {
  const { loaded, tick, click } = page();
  loaded.api.setStage(loaded.api.stages.COLLAPSED);
  click(loaded.parts.go);
  assert.equal(field(loaded), "поехали");
  tick(5100);
  assert.equal(loaded.parts.send.__presses, 0, "первые 5 с только включают настоящий счёт");
  assert.equal(loaded.api.status().sendDelay.counting, true);
  assert.equal(loaded.api.status().sendDelay.left, 5);
  for (let n = 0; n < 7; n += 1) loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.send.__presses, 1);
});

for (const cancel of ["escape", "click", "edit"]) {
  test(`#8283: после первых 5 с настоящий отсчёт отменяется ${cancel}`, () => {
    const { loaded, tick, click } = page();
    click(loaded.parts.clean);
    tick(5100);
    assert.equal(loaded.api.status().sendDelay.counting, true);
    assert.equal(loaded.parts.send.__presses, 0);
    if (cancel === "escape") loaded.win.dispatchEvent({ type: "keydown", key: "Escape", isTrusted: true, target: loaded.parts.editor });
    else if (cancel === "click") loaded.document.dispatchEvent({ type: "click", target: loaded.parts.send, isTrusted: true });
    else loaded.parts.editor.__text += " дополнение";
    for (let n = 0; n < 8; n += 1) loaded.dom.fireKind("timeout");
    assert.equal(loaded.api.status().sendDelay.counting, false);
    assert.equal(loaded.api.status().sendDelay.cancelled, 1);
    assert.equal(loaded.api.status().say.sends, 0);
    assert.equal(loaded.parts.send.__presses, 0);
    assert.ok(loaded.parts.editor.textContent);
  });
}

// #8773 (до WF125 — #8338): Enter в общем отсчёте фразы. Настоящий Chromium ведёт keydown сперва по
// захвату window (onSayKey), потом document (onSendDelayKey) — стенд не всплывает,
// поэтому оба шага руками.
const enterKey = loaded => {
  const event = () => ({ type: "keydown", key: "Enter", code: "Enter", target: loaded.parts.editor, isTrusted: true, bubbles: true, cancelable: true });
  loaded.win.dispatchEvent(event());
  return loaded.document.dispatchEvent(event());
};

test("#8773: второй этап (счёт 12у после фразы) — Enter глотается, счёт идёт и дотикивает сам", () => {
  const { loaded, tick, click } = page();
  click(loaded.parts.clean);
  tick(5100);
  assert.equal(loaded.api.status().sendDelay.counting, true);
  assert.equal(enterKey(loaded), false, "Enter ушёл к Claude нетронутым");
  assert.equal(loaded.api.status().sendDelay.counting, true, "Enter отправил или отменил");
  assert.equal(loaded.api.status().sendDelay.left, 5);
  assert.equal(loaded.api.status().sendDelay.immediate, 0);
  assert.equal(loaded.parts.send.__presses, 0);
  for (let n = 0; n < 7; n += 1) loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.send.__presses, 1, "не ушло");
  assert.equal(loaded.api.status().say.sends, 1);
});

test("#8773: первый этап (5 с фразы) — Enter гасит отсчёт фразы и ставит обычный счёт 12у; второй Enter глотается", () => {
  const { loaded, tick, click } = page();
  click(loaded.parts.clean);
  tick(1000);
  assert.equal(enterKey(loaded), false);
  assert.equal(loaded.api.status().say.armed, false, "отсчёт фразы не погас");
  assert.equal(loaded.api.status().sendDelay.counting, true);
  assert.equal(loaded.api.status().sendDelay.left, 5);
  tick(6000);
  assert.equal(loaded.api.status().sendDelay.started, 1, "фраза поставила второй счёт");
  assert.equal(enterKey(loaded), false);
  assert.equal(loaded.api.status().sendDelay.immediate, 0);
  assert.equal(loaded.api.status().sendDelay.counting, true, "второй Enter отправил или отменил");
  assert.equal(loaded.parts.send.__presses, 0);
  for (let n = 0; n < 7; n += 1) loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.send.__presses, 1);
});

test("#8338: после фразы — один счёт ровно 5 с: один узел цифр, пилюли фразы нет, третьего счёта нет", () => {
  const { loaded, tick, click } = page();
  click(loaded.parts.clean);
  tick(5100);
  const delay = () => loaded.api.status().sendDelay;
  assert.equal(delay().started, 1);
  assert.equal(loaded.document.querySelectorAll("#myclaude-send-delay-digits").length, 1);
  assert.equal(loaded.parts.head.hasAttribute(LEFT), false, "пилюля фразы тикает рядом со счётом");
  assert.equal(loaded.api.status().say.armed, false);
  for (let n = 0; n < 4; n += 1) { loaded.dom.fireKind("timeout"); tick(1000); }
  assert.equal(delay().counting, true, "счёт кончился раньше 5 с");
  assert.equal(delay().left, 1);
  loaded.dom.fireKind("timeout");
  assert.equal(delay().counting, false);
  assert.equal(delay().released, 1);
  for (let n = 0; n < 6; n += 1) { loaded.dom.fireKind("timeout"); tick(1000); }
  assert.equal(delay().started, 1, "третий счёт");
  assert.equal(loaded.parts.send.__presses, 1);
  assert.equal(loaded.document.querySelectorAll("#myclaude-send-delay-digits").length, 1);
});

test("#7891: изменение поля в начальном счёте отменяет его на первом тике", () => {
  const { loaded, tick, click } = page();
  click(loaded.parts.clean);
  loaded.parts.editor.__text += " новый текст";
  tick(200);
  assert.equal(loaded.api.status().say.armed, false);
  assert.equal(loaded.api.status().sendDelay.started, 0);
});

for (const on of [true, false]) {
  test(`WF119 фразы: первые 5 с прежние; второй этап ${on ? "3 с" : "off без эффектов"}`, () => {
    const { loaded, tick, click } = page();
    loaded.dom.command({ id: "wf119-phrase", action: "send-delay", on, seconds: 3 });
    click(loaded.parts.go);
    tick(4900);
    assert.equal(loaded.api.status().sendDelay.started, 0);
    assert.equal(loaded.api.status().sendDelay.released, 0);
    tick(200);
    assert.equal(loaded.api.status().sendDelay.counting, on);
    assert.equal(loaded.api.status().sendDelay.left, on ? 3 : 0);
    assert.equal(loaded.api.status().sendDelay.released, on ? 0 : 1);
    for (let n = 0; n < (on ? 5 : 2); n++) loaded.dom.fireKind("timeout");
    assert.equal(loaded.parts.send.__presses, 1);
    assert.equal(say(loaded).sends, 1);
    // WF128 К1 v3: взлёт 1.8 у кнопки законен, летящих цифр (1.3) нет.
    assert.equal(loaded.document.querySelectorAll(".myclaude-send-look-fly").length, 0);
    if (!on) assert.equal(loaded.document.getElementById("myclaude-send-delay-digits"), null);
    loaded.api.dispose();
  });
}
