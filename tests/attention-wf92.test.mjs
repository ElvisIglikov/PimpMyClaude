// WF92, батч AP (страница): слово Элвиса 25.09 — «у меня много чатов открыто,
// внимание рассеянное, и мне важно видеть, когда от меня что-то требуется».
//
//   #7702 (раздел 12м inject.js) — на ФИНАЛЬНОМ ответе (ход кончился: кнопки
//         стопа нет, текст устоялся) лента едет вниз; промежуточные ответы
//         посреди хода — нет; Элвис листал ленту вверх недавно — не дёргаем;
//   #7703 (раздел 12м) — заголовки «❗ Скажи — и сделаю ❗», «👾 ЭЛВИС, СДЕЛАЙ»,
//         «❗ Включи Accept Edits», «🦾 Нужен …» финального ответа мигают, пока
//         окно не тронули или 2 минуты;
//   #7704 (раздел 12з) — микрофон Диктатора: мигает, пока идёт запись; в
//         открытом поле стоит у левого края нижней строки и текст только
//         кладёт в поле; в режиме чтения — отправка, как раньше; команда
//         mic-refused сбрасывает счёт нажатий и показывает подсказку.
//
// Время разделов 12м — аргумент attnTick (люк), шаг сердца не ждём.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const STOP = "code-prompt-stop";
const ATTN = "data-myclaude-attn";
const SETTLE = 3500;

// Страница Claude Code: поле ввода, лента-скролл, ответы в ленте, кнопка стопа.
const page = ({ tail = { clientHeight: 500, scrollHeight: 2000, scrollTop: 100 }, heads = [], userAfter = false, older = [] } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_aaaa-1111", title: "Trelvis", hasFocus: false,
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript" },
        rect: { left: 0, top: 0, width: 1200, height: 500 }, computed: { overflowY: "auto" },
      });
      Object.assign(feed, tail);
      const answer = (list, text) => {
        const node = feed.add("div", { attrs: { "data-testid": "assistant-message" } });
        for (const head of list) node.add("h2", { text: head });
        node.add("p", { text });
        return node;
      };
      parts.feed = feed;
      parts.old = answer(older, "старый ответ");
      parts.answer = answer(heads, "финальный ответ");
      if (userAfter) feed.add("div", { class: "epitaxy-user-turn", text: "а ещё вот что" });
      parts.stop = dom.document.body.add("button", { attrs: { "data-testid": STOP } });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  let t = Date.now();
  const tick = (step = 500) => { t += step; loaded.inner.attnTick(t); };
  // Ход кончился: стоп пропал, дальше тики до «устоялся» и чуть дальше.
  const endTurn = () => {
    tick();
    loaded.parts.stop.remove();
    for (let spent = 0; spent <= SETTLE + 500; spent += 500) tick();
  };
  return { loaded, tick, endTurn, at: () => t };
};
const attn = loaded => plain(loaded.api.status().attention);
const marked = loaded => loaded.dom.queryAll(`[${ATTN}]`).map(node => node.textContent);

test("#7702: ход кончился, ответ устоялся — лента едет вниз, один раз", () => {
  const { loaded, tick } = page();
  const feed = loaded.parts.feed;
  tick();
  assert.equal(attn(loaded).armed, true, "стоп виден — ход идёт");
  loaded.parts.stop.remove();
  for (let spent = 0; spent < SETTLE - 500; spent += 500) tick();
  assert.equal(feed.scrollTop, 100, "рано: ответ ещё может дописываться");
  tick(); tick();
  assert.equal(feed.scrollTop, 2000, "финальный ответ — лента внизу");
  assert.deepEqual([attn(loaded).turns, attn(loaded).scrolls, attn(loaded).skip], [1, 1, null]);
  feed.scrollTop = 300;
  for (let step = 0; step < 20; step += 1) tick();
  assert.equal(feed.scrollTop, 300, "тот же ход второй раз ленту не дёргает");
});

test("#7702: промежуточные ответы посреди хода ленту не трогают", () => {
  const { loaded, tick } = page();
  for (let step = 0; step < 30; step += 1) {
    loaded.parts.answer.add("p", { text: `шаг ${step}` });
    tick();
  }
  assert.equal(loaded.parts.feed.scrollTop, 100);
  assert.equal(attn(loaded).turns, 0);
});

test("#7702: ответ дописывается после стопа — ждём, пока устоится", () => {
  const { loaded, tick } = page();
  tick();
  loaded.parts.stop.remove();
  for (let step = 0; step < 12; step += 1) {
    loaded.parts.answer.add("p", { text: `хвост ${step}` });
    tick();
  }
  assert.equal(loaded.parts.feed.scrollTop, 100, "текст менялся — не устоялся");
  for (let spent = 0; spent <= SETTLE; spent += 500) tick();
  assert.equal(loaded.parts.feed.scrollTop, 2000);
});

test("#7702: Элвис листал ленту вверх недавно — читает старое, не дёргаем", () => {
  const { loaded, endTurn } = page();
  loaded.win.dispatchEvent({ type: "wheel", deltaY: -40, target: loaded.parts.old });
  assert.equal(attn(loaded).reading, true);
  endTurn();
  assert.equal(loaded.parts.feed.scrollTop, 100, "читает выше — лента стоит");
  assert.deepEqual([attn(loaded).scrolls, attn(loaded).skip], [0, "читает выше"]);
});

test("#7702: листал давно (окно брошено) — крутим; колесо вниз и вне ленты не в счёт", () => {
  const { loaded, tick } = page();
  loaded.win.dispatchEvent({ type: "wheel", deltaY: 40, target: loaded.parts.old });
  loaded.win.dispatchEvent({ type: "wheel", deltaY: -40, target: loaded.parts.editor });
  assert.equal(attn(loaded).reading, false, "вниз и над полем ввода — не чтение старого");
  loaded.win.dispatchEvent({ type: "wheel", deltaY: -40, target: loaded.parts.old });
  // Прошло больше ATTN_READING_MS (5 мин).
  tick(301000);
  loaded.parts.stop.remove();
  for (let spent = 0; spent <= SETTLE + 500; spent += 500) tick();
  assert.equal(loaded.parts.feed.scrollTop, 2000);
});

test("#7702: после ответа уже реплика Элвиса — ответ не последний, не крутим", () => {
  const { loaded, endTurn } = page({ userAfter: true });
  endTurn();
  assert.equal(loaded.parts.feed.scrollTop, 100);
  assert.equal(attn(loaded).skip, "нет последнего ответа");
});

test("#7702: окно открыли на законченном ходе — ничего не делаем", () => {
  const { loaded, tick } = page();
  loaded.parts.stop.remove();
  for (let step = 0; step < 20; step += 1) tick();
  assert.equal(loaded.parts.feed.scrollTop, 100);
  assert.equal(attn(loaded).turns, 0);
});

const HEADS = ["❗ Скажи — и сделаю ❗", "👾 ЭЛВИС, СДЕЛАЙ", "❗ Включи Accept Edits", "🦾 Нужен Opus 🔥 MAX"];

test("#7703: заголовки «нужен Элвис» финального ответа мигают, прочие — нет", () => {
  const { loaded, endTurn } = page({ heads: ["Итог", ...HEADS], older: ["❗ Скажи — и сделаю ❗"] });
  endTurn();
  assert.deepEqual(marked(loaded), HEADS, "мигают ровно заголовки финального ответа");
  const state = attn(loaded);
  assert.deepEqual([state.blink, state.heads, state.blinks], [true, 4, 1]);
  const css = loaded.dom.queryAll("style").map(node => node.textContent).join("\n");
  assert.match(css, /\[data-myclaude-attn\]\{[^}]*animation:myclaude-attn-blink/, "мигание нарисовано правилом");
  assert.match(css, /prefers-reduced-motion: reduce\)\{[^}]*\[data-myclaude-attn\]\{animation:none/, "без движения — не мигает");
});

test("z9-r09: «👤 СДЕЛАЙ» комплекта команды мигает, «Сделайте вывод» и «Итог: сделай бэкап» — нет", () => {
  const { loaded, endTurn } = page({ heads: ["Сделайте вывод", "👤 СДЕЛАЙ", "Итог: сделай бэкап"] });
  endTurn();
  assert.deepEqual(marked(loaded), ["👤 СДЕЛАЙ"]);
});

test("#7703: мигание гаснет от касания окна", () => {
  for (const event of [{ type: "keydown", key: "a" }, { type: "pointerdown" }]) {
    const { loaded, endTurn } = page({ heads: [HEADS[0]] });
    endTurn();
    assert.equal(attn(loaded).blink, true);
    loaded.win.dispatchEvent({ type: "focus" });
    assert.equal(attn(loaded).blink, true, "фокус окна — не касание: окна поднимает и приложение");
    loaded.win.dispatchEvent({ ...event, isTrusted: false });
    assert.equal(attn(loaded).blink, true, `своё синтетическое ${event.type} — не касание`);
    loaded.win.dispatchEvent(event);
    assert.equal(attn(loaded).blink, false, `${event.type} погасил`);
    assert.deepEqual(marked(loaded), []);
  }
});

test("#7703: мигание гаснет через 2 минуты и с новым ходом", () => {
  const first = page({ heads: [HEADS[1]] });
  first.endTurn();
  first.tick(60000);
  assert.equal(attn(first.loaded).blink, true, "минута — ещё мигает");
  first.tick(60000);
  assert.equal(attn(first.loaded).blink, false, "две минуты — хватит");
  assert.deepEqual(marked(first.loaded), []);

  const second = page({ heads: [HEADS[2]] });
  second.endTurn();
  assert.equal(attn(second.loaded).blink, true);
  second.loaded.document.body.add("button", { attrs: { "data-testid": STOP } });
  second.tick();
  assert.equal(attn(second.loaded).blink, false, "новый ход — старый ответ уже не финальный");
  assert.deepEqual(marked(second.loaded), []);
});

test("#7703: Элвис читает выше — мигание ждёт, пока лента дойдёт до низа", () => {
  const { loaded, endTurn, tick } = page({ heads: [HEADS[0]] });
  loaded.win.dispatchEvent({ type: "wheel", deltaY: -40, target: loaded.parts.old });
  endTurn();
  assert.deepEqual([attn(loaded).blink, attn(loaded).pending], [false, true]);
  assert.deepEqual(marked(loaded), [], "на экране старое — ему мигать нечего");
  loaded.parts.feed.scrollTop = 1500;
  tick();
  assert.equal(attn(loaded).blink, true);
  assert.deepEqual(marked(loaded), [HEADS[0]]);
});

test("#7702/#7703: dispose() снимает метки мигания", () => {
  const { loaded, endTurn } = page({ heads: [HEADS[3]] });
  endTurn();
  assert.equal(marked(loaded).length, 1);
  loaded.api.dispose();
  assert.deepEqual(marked(loaded), []);
});

// ---- #7704: микрофон Диктатора -------------------------------------------
const MIC = "#myclaude-mic";
const HINT = "#myclaude-mic-hint";
const ROOM = "data-myclaude-mic-room";
// Как в замере 25.09: строка шире рамки поля и левее её на 8 pt.
const CHIN = { left: 92, top: 744, width: 1016, height: 28 };

const micPage = ({ mode = "dictator", title = "Trelvis", href = "https://claude.ai/epitaxy/local_test", viewport } = {}) => {
  // Задержка отправки выключена: тесты про диктовку; через отсчёт — mic.test.mjs (page-43).
  const loaded = loadInject({
    title, href, ...(viewport ? { geometry: { viewport } } : {}), storage: { local: { "myclaude-send-delay-off": "1" } },
    html: dom => {
      const parts = dom.composer({ top: 600 });
      parts.chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: CHIN });
      parts.send = parts.chin.add("button", { attrs: { "data-testid": "code-prompt-send" }, rect: { left: 1150, top: 748, width: 20, height: 20 } });
      parts.send.__presses = 0;
      parts.send.addEventListener("pointerdown", () => { parts.send.__presses += 1; });
      parts.ring = parts.chin.add("button", {
        attrs: { "aria-haspopup": "dialog", "aria-label": "Usage: Context 300k / 1M (30%)" },
        rect: { left: 1100, top: 760, width: 20, height: 20 },
      });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  if (mode) loaded.dom.command({ id: `m-${mode}`, action: "mic", at: "now", scope: "all", mode });
  settle(loaded);
  return loaded;
};
const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const mic = loaded => loaded.dom.query(MIC);
const micStatus = loaded => plain(loaded.api.status().mic);
const press = loaded => mic(loaded).dispatchEvent({ type: "click" });
const px = (node, name) => Number(String(node.style.getPropertyValue(name)).replace("px", ""));
const wait = (loaded, rounds = 40) => { for (let i = 0; i < rounds; i += 1) loaded.dom.fireKind("timeout"); };

test("#7704: Диктатор в открытом поле — значок у левого края поля, в нижней строке ему место", () => {
  const loaded = micPage();
  const node = mic(loaded);
  assert.equal(loaded.api.status().stage, loaded.api.stages.NORMAL);
  assert.equal(node.style.getPropertyValue("display"), "flex");
  assert.equal(px(node, "left"), loaded.parts.shell.rect.left + 6, "не у левого края рамки поля");
  assert.equal(px(node, "top") + 10, CHIN.top + CHIN.height / 2, "не по середине строки");
  assert.equal(micStatus(loaded).spot, "field");
  assert.equal(loaded.parts.chin.hasAttribute(ROOM), true, "строке не дали места под значок");
  // WF226: ряд кнопок стоит в строке не по середине (замер живого окна: строка 42, ряд — на 3 ниже её
  // середины) — значок встаёт по середине кнопки модели, а не всей строки.
  loaded.parts.chin.add("button", { attrs: { "data-testid": "epitaxy-cds-model-selector" }, rect: { left: 900, top: 753, width: 40, height: 16 } });
  settle(loaded);
  assert.equal(px(node, "top") + 10, 753 + 8, "значок не по середине ряда кнопок");

  // В режиме чтения — снова у кружка, место в строке снято.
  loaded.api.setStage(loaded.api.stages.COLLAPSED);
  settle(loaded);
  assert.equal(micStatus(loaded).spot, "ring");
  assert.equal(loaded.parts.chin.hasAttribute(ROOM), false);
});

test("#7704: режим claude — в открытом поле значка нет, как раньше", () => {
  const loaded = micPage({ mode: "claude" });
  assert.equal(mic(loaded).style.getPropertyValue("display"), "none");
  assert.equal(loaded.parts.chin.hasAttribute(ROOM), false);
});

test("#7704: первое нажатие — значок ярко мигает; поле видно — текст ложится без отправки", () => {
  const loaded = micPage();
  loaded.parts.editor.__text = "черновик";
  press(loaded);
  const status = micStatus(loaded);
  assert.deepEqual([status.dictating, status.live, status.blink], [true, true, true], "запись идёт — мигает");
  assert.equal(mic(loaded).dataset.mode, "dictator");
  const css = loaded.dom.queryAll("style").map(node => node.textContent).join("\n");
  assert.match(css, /#myclaude-mic\[data-live="true"\]\[data-mode="dictator"\]\{[^}]*animation:myclaude-mic-blink/);

  press(loaded);
  loaded.parts.editor.__text = "черновик поставь чайник";
  wait(loaded);
  assert.equal(loaded.parts.send.__presses, 0, "поле видно — никакой отправки");
  assert.deepEqual([micStatus(loaded).blink, micStatus(loaded).kept, micStatus(loaded).sends], [false, 1, 0]);
});

test("#7704: поле спрятано (режим чтения) — текст Диктатора уходит сам", () => {
  const loaded = micPage();
  loaded.api.setStage(loaded.api.stages.COLLAPSED);
  settle(loaded);
  loaded.parts.editor.__text = "";
  press(loaded);
  press(loaded);
  loaded.parts.editor.__text = "поставь чайник";
  wait(loaded, 6);
  assert.equal(loaded.parts.send.__presses, 1, "спрятанное поле — отправка");
  assert.equal(micStatus(loaded).sends, 1);
});

test("#7704: поле открыли, пока ждали расшифровку, — не отправляем", () => {
  const loaded = micPage();
  loaded.api.setStage(loaded.api.stages.COLLAPSED);
  settle(loaded);
  press(loaded);
  press(loaded);
  loaded.api.setStage(loaded.api.stages.NORMAL);
  loaded.parts.editor.__text = "поставь чайник";
  wait(loaded);
  assert.equal(loaded.parts.send.__presses, 0);
});

test("#7704: mic-refused — счёт нажатий сброшен, подсказка у значка 3 с", () => {
  const loaded = micPage();
  press(loaded);
  assert.equal(micStatus(loaded).blink, true);
  loaded.dom.command({ id: "r1", action: "mic-refused", at: "now", reason: "recording", chat: null, match: "Trelvis" });
  const status = micStatus(loaded);
  assert.deepEqual([status.dictating, status.blink, status.refused, status.hint], [false, false, 1, true]);
  const hint = loaded.dom.query(HINT);
  assert.equal(hint.textContent, "Сначала останови запись в Диктаторе");
  assert.equal(px(hint, "bottom"), 800 - px(mic(loaded), "top") + 6, "подсказка над значком");
  wait(loaded, 1);
  assert.equal(micStatus(loaded).hint, false, "подсказка ушла");
  // Следующее нажатие — снова ПЕРВОЕ: запись, а не остановка с отправкой.
  press(loaded);
  assert.equal(micStatus(loaded).dictating, true);
});

test("#7704: mic-refused в окне, где микрофон не нажимали, — ничего", () => {
  const loaded = micPage();
  loaded.dom.command({ id: "r2", action: "mic-refused", at: "now", reason: "recording", chat: null, match: "Trelvis" });
  assert.deepEqual([micStatus(loaded).refused, micStatus(loaded).hint], [0, false]);
});

test("#7704: dispose() уносит значок, подсказку и место в строке", () => {
  const loaded = micPage();
  press(loaded);
  loaded.dom.command({ id: "r3", action: "mic-refused", at: "now", reason: "recording", chat: null, match: "Trelvis" });
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(MIC).length, 0);
  assert.equal(loaded.dom.queryAll(HINT).length, 0);
  assert.equal(loaded.parts.chin.hasAttribute(ROOM), false);
});

// ---- WF92-ap2: правки гейта --------------------------------------------------

test("wf92-ap2: mic-refused адресный — два окна нажаты подряд, отказ только второму", () => {
  const first = micPage({ title: "Trelvis", href: "https://claude.ai/epitaxy/local_aaaa-1111" });
  const second = micPage({ title: "Pimp", href: "https://claude.ai/epitaxy/local_bbbb-2222" });
  press(first);
  press(second);
  const chat = second.api.status().chat.self;
  assert.ok(chat && chat !== first.api.status().chat.self, "у окон свои id чата");
  const command = { id: "r-two", action: "mic-refused", at: "now", reason: "recording", chat, match: "Pimp" };
  first.dom.command(command);
  second.dom.command(command);
  assert.deepEqual([micStatus(first).refused, micStatus(first).dictating, micStatus(first).hint], [0, true, false], "первому окну отказ не адресован");
  assert.deepEqual([micStatus(second).refused, micStatus(second).dictating, micStatus(second).hint], [1, false, true]);
});

test("wf92-ap2: mic-refused при chat=null — по заголовку; чужой заголовок — мимо", () => {
  const loaded = micPage({ title: "Trelvis" });
  press(loaded);
  loaded.dom.command({ id: "x1", action: "mic-refused", at: "now", reason: "recording", chat: null, match: "Другой" });
  assert.equal(micStatus(loaded).refused, 0);
  loaded.dom.command({ id: "x2", action: "mic-refused", at: "now", reason: "recording", chat: "local_чужой", match: "Trelvis" });
  assert.equal(micStatus(loaded).refused, 0, "chat задан и чужой — заголовок не спасает");
  loaded.dom.command({ id: "x3", action: "mic-refused", at: "now", reason: "recording", chat: null, match: "Trelvis" });
  assert.equal(micStatus(loaded).refused, 1);
});

test("wf92-ap2: К4 mic — в поле anchor 1 (dx от левого края), у кружка anchor 0", () => {
  const loaded = micPage();
  const node = mic(loaded);
  // Стаб раскладки не считает: рамка значка — из его же стилей.
  const frame = target => { target.rect = { left: px(target, "left"), top: px(target, "top"), width: 20, height: 20 }; };
  frame(node);
  const field = plain(loaded.inner.micSpot());
  assert.deepEqual(field, [px(node, "left"), 800 - px(node, "top"), 20, 20, 1]);
  loaded.api.setStage(loaded.api.stages.COLLAPSED);
  settle(loaded);
  frame(mic(loaded));
  const ring = plain(loaded.inner.micSpot());
  assert.deepEqual(ring, [1200 - px(mic(loaded), "left"), 800 - px(mic(loaded), "top"), 20, 20, 0]);
});

test("wf92-ap2: окно 280 — значок жмётся к рамке, строке отступ меньше", () => {
  const loaded = micPage({ viewport: { width: 280, height: 800 } });
  assert.equal(px(mic(loaded), "left"), loaded.parts.shell.rect.left + 1);
  const css = loaded.dom.queryAll("style").map(node => node.textContent).join("\n");
  assert.match(css, /@media \(max-width:319px\)\{\[data-cds="ChatComposerChin"\]\[data-myclaude-mic-room\]\{padding-left:23px !important\}\}/);
});

test("wf92-ap2: «читает выше» держится, пока лента не у низа (до 5 мин), и снимается у низа", () => {
  const { loaded, tick } = page();
  loaded.win.dispatchEvent({ type: "wheel", deltaY: -40, target: loaded.parts.old });
  tick(120000);
  assert.equal(attn(loaded).reading, true, "2 минуты, лента выше — всё ещё читает");
  loaded.parts.feed.scrollTop = 1500;
  tick();
  assert.equal(attn(loaded).reading, false, "вернулся к низу — дочитал");
});

test("wf92-ap2: Shift+Space и полоса прокрутки — тоже «читает выше»", () => {
  const key = page();
  key.loaded.win.dispatchEvent({ type: "keydown", key: " ", shiftKey: true, target: key.loaded.parts.old });
  assert.equal(attn(key.loaded).reading, true);
  const plainSpace = page();
  plainSpace.loaded.win.dispatchEvent({ type: "keydown", key: " ", target: plainSpace.loaded.parts.old });
  assert.equal(attn(plainSpace.loaded).reading, false, "просто пробел — не вверх");

  const bar = page();
  const feed = bar.loaded.parts.feed;
  feed.clientWidth = 1190;
  bar.loaded.win.dispatchEvent({ type: "pointerdown", target: feed, clientX: 600 });
  assert.equal(attn(bar.loaded).reading, false, "нажатие в ленту, не в полосу");
  bar.loaded.win.dispatchEvent({ type: "pointerdown", target: feed, clientX: 1195 });
  assert.equal(attn(bar.loaded).reading, true, "нажатие в полосу прокрутки");
});
