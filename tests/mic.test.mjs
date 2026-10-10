// Микрофон у кружка контекста и панель лимитов по наведению (раздел 12з
// inject.js, задачи #6906 и #6907). Слово Элвиса 21.09: «у меня просто в углу
// будет кнопка диктовки, я на неё буду нажимать и буду доволен»; «при наведении
// на этот кружок не надо показывать стандартную подсказку… должна открываться
// вот это полноценное окно… нажал — появилось и исчезнет только после
// повторного нажатия».
//
// Проверяется контракт раздела, а не разметка Claude:
//   1) значок стоит слева от кружка и по его середине — и только в режиме
//      чтения: в открытом поле слева от кружка стоят «Opus 5» и «Max»;
//   2) нажатие включает РОДНУЮ диктовку Claude, значок горит;
//   3) второе нажатие выключает её и, когда расшифровка устоялась, жмёт
//      «отправить»;
//   4) расшифровки не дождались — ничего не отправляем;
//   5) наведение на кружок открывает панель, уход мыши — закрывает;
//   6) нажатие рукой панель ЗАКРЕПЛЯЕТ: уход мыши её больше не закрывает;
//   7) dispose() уносит значок.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const MIC = "#myclaude-mic";
const MIC_SIZE = 20;
const MIC_GAP = 6;
const HEARTBEAT_MS = 500;
const WIDTH = 1200;
const HEIGHT = 800;
const RING = { left: 1100, top: 760, size: 20 };

// Стенд: поле ввода Claude, его кнопка диктовки (она же переключает подпись,
// как живая), кнопка отправки, кружок контекста и его панель. Нажатия считаем
// на самих узлах — так видно, что жмём мы именно родные кнопки Claude.
const stand = () => dom => {
  const parts = dom.composer({ top: 600 });
  const count = (node, make) => {
    node.__presses = 0;
    node.addEventListener("pointerdown", () => {
      node.__presses += 1;
      if (make) make(node);
    });
    return node;
  };
  const dictate = count(parts.modelRow.add("button", {
    attrs: { "aria-label": "Press and hold to record" },
    rect: { left: 150, top: 726, width: 20, height: 20 },
  }), node => {
    const live = node.getAttribute("aria-label") === "Stop dictation";
    node.setAttribute("aria-label", live ? "Press and hold to record" : "Stop dictation");
  });
  const send = count(parts.modelRow.add("button", {
    attrs: { "data-testid": "code-prompt-send" },
    rect: { left: 1150, top: 700, width: 24, height: 24 },
  }));
  const ring = count(parts.modelRow.add("button", {
    attrs: { "aria-haspopup": "dialog", "aria-label": "Usage: Context 300k / 1M (30%)" },
    rect: { left: RING.left, top: RING.top, width: RING.size, height: RING.size },
  }), node => {
    // Панель Claude: открывается и закрывается тем же нажатием по кружку.
    const open = dom.document.body.querySelector('[role="dialog"][data-cds="Popover"]');
    if (open) { open.parentNode.removeChild(open); return; }
    const panel = dom.document.body.add("div", {
      attrs: { role: "dialog", "data-cds": "Popover" },
      rect: { left: 900, top: 400, width: 300, height: 300 },
    });
    panel.add("div", { attrs: { "data-cds": "StackedMeter" } });
    panel.add("a", { attrs: { href: "/settings/usage" }, text: "See detailed breakdown" });
    node.__panel = panel;
  });
  return { ...parts, dictate, send, ring };
};

// Задержка отправки выключена: эти тесты про саму диктовку; через отсчёт — отдельный тест ниже (page-43).
const open = (local = { "myclaude-send-delay-off": "1" }) => loadInject({
  title: "Trelvis",
  html: stand(),
  geometry: { viewport: { width: WIDTH, height: HEIGHT } },
  storage: { local },
});
const px = (node, name) => Number(String(node.style.getPropertyValue(name)).replace("px", ""));
const mic = loaded => loaded.dom.query(MIC);
const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
// Круг сторожа: им страница замечает открытую панель (наблюдатель стаба записей
// не доставляет — тот же приём, что в usage-panel.test.mjs).
const beat = loaded => {
  for (const [id, item] of [...loaded.dom.timers.entries()]) {
    if (item.kind === "interval" && item.ms === HEARTBEAT_MS) loaded.dom.fire(id);
  }
};
const collapse = loaded => { loaded.api.setStage(loaded.api.stages.COLLAPSED); settle(loaded); };
const ringEvent = (loaded, type, extra = {}) => loaded.dom.document.dispatchEvent({
  type, target: loaded.parts.ring, ...extra,
});

test("значок стоит слева от кружка и по его середине — и только в режиме чтения", () => {
  const loaded = open();
  assert.equal(mic(loaded).style.getPropertyValue("display"), "none",
    "в открытом поле значка быть не должно: слева от кружка там «Opus 5» и «Max»");
  collapse(loaded);
  const node = mic(loaded);
  assert.equal(node.style.getPropertyValue("display"), "flex", "в режиме чтения значка нет");
  assert.equal(px(node, "left"), RING.left - MIC_GAP - MIC_SIZE, "значок не слева от кружка");
  assert.equal(px(node, "top") + MIC_SIZE / 2, RING.top + RING.size / 2, "значок не по середине кружка");
  assert.equal(loaded.api.status().mic.visible, true);
  assert.equal(loaded.api.status().mic.button, true, "кнопку диктовки Claude не нашли");
});

test("нажатие включает родную диктовку Claude, значок горит", () => {
  const loaded = open();
  collapse(loaded);
  mic(loaded).dispatchEvent({ type: "click" });
  assert.equal(loaded.parts.dictate.__presses, 1, "родную кнопку диктовки не нажали");
  assert.equal(loaded.parts.dictate.getAttribute("aria-label"), "Stop dictation");
  settle(loaded);
  assert.equal(loaded.api.status().mic.live, true, "значок не показывает, что идёт запись");
  assert.equal(loaded.api.status().mic.starts, 1);
});

test("второе нажатие выключает диктовку и отправляет расшифровку", () => {
  const loaded = open();
  collapse(loaded);
  mic(loaded).dispatchEvent({ type: "click" });
  mic(loaded).dispatchEvent({ type: "click" });
  assert.equal(loaded.parts.dictate.__presses, 2, "диктовку не выключили");
  assert.equal(loaded.parts.send.__presses, 0, "отправили, не дождавшись расшифровки");

  // Расшифровка приехала и устоялась: ждём три одинаковых круга.
  loaded.parts.editor.__text = "поставь чайник";
  for (let i = 0; i < 6; i += 1) loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.send.__presses, 1, "расшифровку не отправили");
  assert.equal(loaded.api.status().mic.sends, 1);

  // Лишних нажатий по «отправить» больше нет: ожидание снято.
  for (let i = 0; i < 6; i += 1) loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.send.__presses, 1, "отправили второй раз");
});

test("расшифровки не дождались — ничего не отправляем", () => {
  const loaded = open();
  collapse(loaded);
  mic(loaded).dispatchEvent({ type: "click" });
  mic(loaded).dispatchEvent({ type: "click" });
  // Поле пустое: сколько ни жди, отправлять нечего.
  for (let i = 0; i < 120; i += 1) loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.send.__presses, 0, "отправили пустое сообщение");
});

test("наведение на кружок открывает панель, уход мыши — закрывает", () => {
  const loaded = open();
  collapse(loaded);
  ringEvent(loaded, "pointerover");
  assert.equal(loaded.dom.document.documentElement.getAttribute("data-myclaude-ring-hover"), "",
    "родная подсказка не заглушена");
  loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.ring.__presses, 1, "панель по наведению не открылась");
  beat(loaded);
  assert.ok(loaded.dom.query('[role="dialog"][data-cds="Popover"]'), "панели нет");

  ringEvent(loaded, "pointerout", { relatedTarget: null });
  loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.ring.__presses, 2, "мышь ушла, а панель осталась");
  assert.equal(loaded.dom.query('[role="dialog"][data-cds="Popover"]'), null);
});

test("нажатие рукой закрепляет панель: уход мыши её больше не закрывает", () => {
  const loaded = open();
  collapse(loaded);
  ringEvent(loaded, "pointerover");
  loaded.dom.fireKind("timeout");
  beat(loaded);
  assert.equal(loaded.parts.ring.__presses, 1);

  // Настоящее нажатие Элвиса: панель закрепляется, а сам клик гасится — иначе
  // Claude свернул бы свою же панель.
  const click = { type: "click", target: loaded.parts.ring, isTrusted: true };
  loaded.dom.document.dispatchEvent(click);
  assert.ok(loaded.dom.query('[role="dialog"][data-cds="Popover"]'), "закреплённая панель закрылась");

  ringEvent(loaded, "pointerout", { relatedTarget: null });
  loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.ring.__presses, 1, "закреплённую панель закрыли уходом мыши");
  assert.ok(loaded.dom.query('[role="dialog"][data-cds="Popover"]'), "закреплённая панель пропала");
});

test("dispose(): значок уходит из окна", () => {
  const loaded = open();
  collapse(loaded);
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(MIC).length, 0);
});

// ---- К4 (#7054, WF84): режим Диктатора и место кружка для приложения ---------
const dictator = loaded => loaded.dom.command({ id: "m1", action: "mic", at: "now", scope: "all", mode: "dictator" });

test("К4: черновик, что лежал в поле до первого нажатия, сам не уходит", () => {
  const loaded = open();
  collapse(loaded);
  loaded.parts.editor.__text = "недописанная мысль";
  mic(loaded).dispatchEvent({ type: "click" });
  mic(loaded).dispatchEvent({ type: "click" });
  for (let i = 0; i < 20; i += 1) loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.send.__presses, 0, "текст не сменился — отправлять нечего");
  loaded.parts.editor.__text = "недописанная мысль и расшифровка";
  for (let i = 0; i < 6; i += 1) loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.send.__presses, 1, "сменился и устоялся — ушло");
});

test("К4: режим Диктатора — родную диктовку не жмём, отправку взводит второе нажатие после смены текста", () => {
  const loaded = open();
  dictator(loaded);
  assert.equal(loaded.win.localStorage.getItem("myclaude.mic"), "dictator");
  collapse(loaded);
  loaded.parts.editor.__text = "черновик";
  const down = new loaded.win.MouseEvent("mousedown", { cancelable: true });
  mic(loaded).dispatchEvent(down);
  assert.equal(down.defaultPrevented, true, "нажатие фокус у поля не отнимает — Диктатор вставит туда");
  mic(loaded).dispatchEvent({ type: "click" });
  assert.equal(loaded.parts.dictate.__presses, 0, "родную кнопку диктовки не трогаем — F5 жмёт приложение");
  settle(loaded);
  assert.equal(loaded.api.status().mic.dictating, true);
  assert.equal(loaded.api.status().mic.live, true, "значок горит своим счётом");
  for (let i = 0; i < 20; i += 1) loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.send.__presses, 0, "первое нажатие отправку не взводит");
  mic(loaded).dispatchEvent({ type: "click" });
  for (let i = 0; i < 20; i += 1) loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.send.__presses, 0, "текст прежний — ждём расшифровку");
  loaded.parts.editor.__text = "черновик поставь чайник";
  for (let i = 0; i < 6; i += 1) loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.send.__presses, 1, "расшифровка вставлена и устоялась — ушло");
  assert.equal(loaded.api.status().mic.mode, "dictator");
});

test("К4: режим Диктатора — значок виден и без родной кнопки диктовки; claude — снова по родной", () => {
  const loaded = open();
  loaded.parts.dictate.remove();
  collapse(loaded);
  assert.equal(mic(loaded).style.getPropertyValue("display"), "none", "claude без родной кнопки — значка нет");
  dictator(loaded);
  settle(loaded);
  assert.equal(mic(loaded).style.getPropertyValue("display"), "flex");
  loaded.dom.command({ id: "m2", action: "mic", at: "now", scope: "all", mode: "claude" });
  settle(loaded);
  assert.equal(mic(loaded).style.getPropertyValue("display"), "none");
});

test("К4: chats() — поле mic после frame: угол значка от правого и нижнего края, anchor 0, иначе null", async () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_aaa", title: "Trelvis", html: stand(),
    geometry: { viewport: { width: WIDTH, height: HEIGHT }, frame: [0, 25, WIDTH, HEIGHT] },
  });
  let answer = await loaded.api.chats({ nonce: "k4" });
  assert.equal(answer.mic, null, "поле открыто — значка нет");
  collapse(loaded);
  const node = mic(loaded);
  node.rect = { left: px(node, "left"), top: px(node, "top"), width: MIC_SIZE, height: MIC_SIZE };
  answer = await loaded.api.chats({ nonce: "k4b" });
  const keys = Object.keys(answer);
  assert.equal(keys[keys.indexOf("frame") + 1], "mic", "mic — сразу после frame");
  assert.deepEqual([...answer.mic], [WIDTH - px(node, "left"), HEIGHT - px(node, "top"), MIC_SIZE, MIC_SIZE, 0], "у кружка — anchor 0 (WF92-ap2)");
});

test("#7873: двойной клик по значку — одно нажатие: второй щелчок (detail 2) запись не останавливает", () => {
  const loaded = open();
  dictator(loaded);
  collapse(loaded);
  loaded.parts.editor.__text = "черновик";
  mic(loaded).dispatchEvent({ type: "click", detail: 1 });
  mic(loaded).dispatchEvent({ type: "click", detail: 2 });
  settle(loaded);
  assert.equal(loaded.api.status().mic.starts, 1);
  assert.equal(loaded.api.status().mic.dictating, true, "второй щелчок двойного клика остановил запись");
  loaded.parts.editor.__text = "черновик поставь чайник";
  for (let i = 0; i < 20; i += 1) loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.send.__presses, 0, "отправка взведена вторым щелчком двойного клика");
});

// page-43 (слово Элвиса 09.10 04:10: «Никаких быстрых отправок. Всё на таймере всегда»): расшифровка
// уходит через отсчёт, а не нажатием «отправить» мимо него.
test("page-43: диктовка при включённой задержке — через отсчёт, не сразу", () => {
  const loaded = open({});
  collapse(loaded);
  mic(loaded).dispatchEvent({ type: "click" });
  mic(loaded).dispatchEvent({ type: "click" });
  loaded.parts.editor.__text = "поставь чайник";
  for (let i = 0; i < 4; i += 1) loaded.dom.fireKind("timeout");
  assert.equal(loaded.parts.send.__presses, 0, "ушло мимо отсчёта");
  assert.equal(loaded.api.status().sendDelay.counting, true, "отсчёт не пошёл");
});
