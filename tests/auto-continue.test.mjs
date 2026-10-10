// «💬 Новый чат» сам (раздел 12к inject.js, WF85, контракт К7.5 плана
// docs/plan-wf85-2026-09-24.md, #7347). Ход кончился на глазах страницы
// (кнопка стоп пропала и не вернулась 3 с), лента у низа, у последнего ответа
// блок передачи — под ним отсчёт «💬 Новый чат через N с» и «✕»; досчитал —
// страница жмёт кнопку сама. Тик — сердце раздела 16 (интервал), не кадр.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { loadInject, plain } from "./load.mjs";

const fixture = name => JSON.parse(readFileSync(new URL(`./fixtures/cashout/${name}.json`, import.meta.url), "utf8"));
const HANDOFF = fixture("record-handoff").text;
const BOX = "[data-myclaude-continue]";
const MAIN = `${BOX} button:not([data-myclaude-continue-cancel])`;
const CANCEL = "[data-myclaude-continue-cancel]";
const LABEL = "data-myclaude-continue-label";
const PREFIX = "Пимп: продолжить в новом чате · ";
const AUTO_KEY = "myclaude-auto-continue";
const INPUT_KEY = "myclaude-last-input";
const CHAT = "local_aaaa-1111";
const TITLE = "VkusnoffKz 2";

// Ответ по правилу ELVIS.md: заголовок, фраза и «Модель:» в одном <p>, блок
// кода, строка расхода и в самом конце ещё раз заголовок без кода.
const answerWith = (dom, top, { code = HANDOFF, model = "Модель: Opus 5.5 · LOW" } = {}) => {
  const answer = dom.document.body.add("div", {
    attrs: { "data-testid": "assistant-message" }, rect: { left: 0, top, width: 800, height: 100 },
  });
  answer.add("h2", { text: "🆕 ОТКРОЙ НОВЫЙ ЧАТ" });
  answer.add("p", { text: `Волна сделана, граница — гейт.\n${model}` });
  const block = answer.add("div", { class: "epitaxy-codeblock relative" });
  block.add("div", { class: "relative" }).add("div", { attrs: { "data-code-text": code }, text: code });
  answer.add("p", { text: "Расход: 12%." });
  answer.add("h2", { text: "🆕 ОТКРОЙ НОВЫЙ ЧАТ" });
  return { answer, block };
};
// Строка чата в списке слева с сессией в React-волокне (как wait-glow.test).
const addRow = (bar, id, session) => {
  const row = bar.add("div", { attrs: { "data-row-key": `code:${id}` } });
  row["__reactFiber$test"] = {
    memoizedProps: { "data-row-key": `code:${id}` },
    return: { memoizedProps: { session }, return: null },
  };
};
const page = ({ answers = [{}], draft = "", live = null, tail = null, local = {}, enabled = true, stop = true } = {}) => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: TITLE, hasFocus: false,
    storage: { local: { "myclaude-auto-allow-roam": "off", ...(enabled ? { "myclaude.autoContinue": "true" } : {}), ...local } },
    html: dom => {
      const parts = dom.composer({ text: draft });
      if (live) {
        const bar = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
        addRow(bar, CHAT, { ref: { kind: "code", id: CHAT }, title: CHAT, hasCompleted: false, isUnread: false, ...live });
      }
      if (tail) {
        parts.tail = dom.document.body.add("div", {
          attrs: { "data-testid": "epitaxy-virtual-transcript" },
          rect: { left: 0, top: 0, width: 1200, height: 500 }, computed: { overflowY: "auto" },
        });
        Object.assign(parts.tail, tail);
      }
      parts.stop = dom.node("button");
      parts.stop.setAttribute("data-testid", "code-prompt-stop");
      if (stop) dom.document.body.appendChild(parts.stop);
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  // База заморожена (z8-r01): часы страницы двигает только тест, иначе
  // настоящее время под нагрузкой утекало бы в отсчёт.
  const base = loaded.win.performance.now();
  let shift = 0;
  loaded.win.performance.now = () => base + shift;
  // Шаг сердца: полсекунды часов, интервалы (сердце) и кадр раскладки.
  const beat = (times = 1) => {
    for (let index = 0; index < times; index += 1) {
      shift += 500;
      loaded.dom.fireKind("interval");
      loaded.dom.fireKind("raf");
    }
  };
  // Ход шёл на глазах страницы, кнопка стоп ушла и не вернулась 3 с — оценка.
  const endTurn = () => {
    beat(2);
    loaded.parts.stop.remove();
    beat(8);
  };
  const again = () => {
    loaded.document.body.appendChild(loaded.parts.stop);
    endTurn();
  };
  beat();
  // Ответы приходят ПОСЛЕ начала хода (проверка WF85, D1): ответ, что был
  // последним, когда страница впервые увидела стоп, сам не открывается.
  const addedAnswers = answers.map((spec, index) => (spec === null
    ? loaded.dom.document.body.add("div", { attrs: { "data-testid": "assistant-message" }, text: "Просто ответ." })
    : answerWith(loaded.dom, 100 + index * 120, spec).answer));
  // VM observer сам не доставляет мутации. В браузере вставка ответа будит
  // dirty-layout, поэтому доставляем её через настоящий обработчик страницы.
  loaded.inner.onMutated([{ type: "childList", target: loaded.document.body, addedNodes: addedAnswers, removedNodes: [] }]);
  beat();
  return { loaded, parts: loaded.parts, beat, endTurn, again };
};
const auto = loaded => plain(loaded.api.status().continue.auto);
const main = loaded => loaded.dom.query(MAIN);
const label = loaded => main(loaded)?.getAttribute(LABEL);
const clicks = loaded => loaded.api.status().continue.clicks;
const click = (loaded, target) => loaded.document.dispatchEvent({ type: "click", target, bubbles: true });
const stored = loaded => JSON.parse(loaded.win.localStorage.getItem(AUTO_KEY) ?? "null");

test("К7.5: ход кончился на глазах, лента у низа — отсчёт с «✕», досчитал — жмёт сам", () => {
  const { loaded, beat, endTurn } = page();
  assert.equal(loaded.dom.queryAll(BOX).length, 1, "хвостовой заголовок без кода кнопку не прячет (К7.1)");
  endTurn();
  assert.equal(auto(loaded).state, "count");
  assert.match(label(loaded), /^💬 Новый чат через 1[45] с$/);
  assert.equal(main(loaded).hasAttribute("aria-disabled"), false, "подпись отсчёта не «занята» — клик сразу");
  assert.equal(loaded.dom.queryAll(CANCEL).length, 1, "«✕» рядом");
  assert.equal(loaded.api.status().continue.button, 1, "«✕» основной кнопкой не считается");
  // React пересобрал блок посреди счёта — подпись и «✕» встают сразу.
  const oldBox = loaded.dom.query(BOX);
  const host = oldBox.parentNode;
  oldBox.remove();
  loaded.inner.onMutated([{ type: "childList", target: host, addedNodes: [], removedNodes: [oldBox] }]);
  beat();
  assert.match(label(loaded), /^💬 Новый чат через \d+ с$/);
  assert.equal(loaded.dom.queryAll(CANCEL).length, 1);
  beat(30);
  assert.equal(clicks(loaded), 1);
  assert.ok(String(loaded.document.title).startsWith(PREFIX), "метка для ContinueWatch в заголовке");
  const state = auto(loaded);
  assert.equal(state.state, "fired");
  assert.equal(state.fired, 1);
  assert.equal(loaded.dom.queryAll(CANCEL).length, 0, "«✕» ушла");
  const data = stored(loaded);
  assert.deepEqual(Object.keys(data.done).map(key => key.split(":")[0]), [CHAT], "отпечаток — чат и хэш текста");
  assert.equal(data.recent.length, 1);
});

test("К7.5: стопа на глазах не было — отсчёта нет", () => {
  const { loaded, beat } = page({ stop: false });
  beat(50);
  assert.equal(auto(loaded).state, "off");
  assert.equal(clicks(loaded), 0);
});

test("К7.5: ход кончился при ленте не у низа — отсчёта нет (Б2)", () => {
  const { loaded, endTurn, beat } = page({ tail: { clientHeight: 500, scrollHeight: 2000, scrollTop: 100 } });
  endTurn();
  assert.deepEqual([auto(loaded).state, auto(loaded).reason], ["off", "лента не у низа"]);
  beat(40);
  assert.equal(clicks(loaded), 0);
});

test("К7.5: последний ответ без блока, выше старый с блоком — отсчёта нет (Б2)", () => {
  const { loaded, endTurn, beat } = page({ answers: [{}, null] });
  endTurn();
  assert.equal(auto(loaded).reason, "нет блока");
  beat(40);
  assert.equal(clicks(loaded), 0);
});

test("К7.5: «✕» не открывает чат — отмена, отпечаток в done (Б1)", () => {
  const { loaded, endTurn, beat, again } = page();
  endTurn();
  click(loaded, loaded.dom.query(CANCEL));
  assert.equal(clicks(loaded), 0);
  assert.equal(loaded.document.title, TITLE, "метки в заголовке нет");
  const state = auto(loaded);
  assert.equal(state.state, "cancelled");
  assert.equal(state.cancelled, 1);
  assert.equal(loaded.dom.queryAll(CANCEL).length, 0);
  assert.equal(label(loaded), "💬 Новый чат");
  beat(40);
  assert.equal(clicks(loaded), 0);
  again();
  assert.equal(auto(loaded).reason, "уже было", "отменённый ответ повторно не считается");
});

test("К7.5: клавиша в своём поле — отмена насовсем", () => {
  const { loaded, parts, endTurn, beat } = page();
  endTurn();
  loaded.win.dispatchEvent({ type: "keydown", key: "a", target: parts.editor });
  assert.deepEqual([auto(loaded).state, auto(loaded).reason], ["cancelled", "клавиша в поле"]);
  beat(40);
  assert.equal(clicks(loaded), 0);
});

test("К7.5: ввод в другом окне (штамп) — пауза, после 30 с тишины счёт заново (В3)", () => {
  const { loaded, endTurn, beat } = page();
  endTurn();
  beat(4);
  loaded.win.localStorage.setItem(INPUT_KEY, String(Date.now()));
  beat();
  assert.deepEqual([auto(loaded).state, auto(loaded).reason], ["wait", "Элвис работает"]);
  assert.equal(label(loaded), "💬 Новый чат", "на паузе без цифр");
  assert.equal(loaded.dom.queryAll(CANCEL).length, 1, "«✕» остаётся — отсчёт не отменён");
  beat(60);
  assert.equal(clicks(loaded), 0);
  loaded.win.localStorage.setItem(INPUT_KEY, String(Date.now() - 31000));
  beat();
  assert.equal(auto(loaded).state, "count");
  assert.equal(auto(loaded).left, 15, "счёт начался заново");
  beat(30);
  assert.equal(clicks(loaded), 1);
});

test("К7.5: черновик в поле, Fable, Max — не сам", () => {
  const draft = page({ draft: "моя мысль" });
  draft.endTurn();
  assert.equal(auto(draft.loaded).reason, "черновик в поле");
  for (const model of ["Модель: Fable 5.1 · High", "Модель: Opus 5.5 · 🔥 MAX"]) {
    const { loaded, endTurn, beat } = page({ answers: [{ model }] });
    endTurn();
    assert.equal(auto(loaded).reason, "Fable/Max — руками", model);
    beat(40);
    assert.equal(clicks(loaded), 0);
  }
});

test("К7.5: чат ждёт ответа — не сам; «running» строки списка без стопа не мешает (живой гейт WF85)", () => {
  const waiting = page({ live: { liveStatus: "awaiting", isRunning: false } });
  waiting.endTurn();
  assert.equal(auto(waiting.loaded).reason, "чат ждёт ответа");
  // Строка в «Recents» минутами держит «running» после конца хода — судит стоп.
  const stale = page({ live: { liveStatus: "running", isRunning: true } });
  stale.endTurn();
  assert.equal(auto(stale.loaded).state, "count");
});

test("К7.5: обход Авто-Allow начался посреди счёта — отмена (В9)", () => {
  const { loaded, endTurn } = page();
  endTurn();
  assert.equal(auto(loaded).state, "count");
  loaded.inner.roamState.phase = "go";
  loaded.dom.fireKind("interval");
  assert.deepEqual([auto(loaded).state, auto(loaded).reason], ["cancelled", "обход Авто-Allow"]);
  assert.equal(clicks(loaded), 0);
});

test("К7.5: повтора на тот же ответ нет — ни после срабатывания, ни после ручного клика", () => {
  const first = page();
  first.endTurn();
  first.beat(30);
  assert.equal(clicks(first.loaded), 1);
  first.loaded.dom.command({ id: "c1", action: "cashout", at: "now", scope: "window", title: TITLE, handoff: true });
  first.again();
  assert.equal(auto(first.loaded).reason, "уже было");
  first.beat(40);
  assert.equal(clicks(first.loaded), 1);

  const manual = page();
  manual.endTurn();
  click(manual.loaded, main(manual.loaded));
  assert.equal(clicks(manual.loaded), 1);
  assert.deepEqual([auto(manual.loaded).state, auto(manual.loaded).reason], ["off", "нажато руками"]);
  manual.loaded.dom.command({ id: "c1", action: "cashout", at: "now", scope: "window", title: TITLE, handoff: true });
  manual.again();
  assert.equal(auto(manual.loaded).reason, "уже было", "ручной клик тоже пишет отпечаток");
  manual.beat(40);
  assert.equal(clicks(manual.loaded), 1);
});

test("К7.5: две страницы одного чата — жмёт одна (В4)", () => {
  const a = page();
  const b = page();
  b.loaded.win.localStorage = a.loaded.win.localStorage;
  a.endTurn();
  b.endTurn();
  a.beat(30);
  b.beat(30);
  assert.equal(clicks(a.loaded), 1);
  assert.equal(clicks(b.loaded), 0);
  assert.deepEqual([auto(b.loaded).state, auto(b.loaded).reason], ["wait", "уже открыт"]);
});

test("К7.5: не больше трёх за 10 минут; выключатель в localStorage", () => {
  const t = Date.now();
  const busy = page({ local: { [AUTO_KEY]: JSON.stringify({ done: {}, recent: [t - 60000, t - 120000, t - 180000] }) } });
  busy.endTurn();
  assert.equal(auto(busy.loaded).reason, "частота");
  const old = page({ local: { [AUTO_KEY]: JSON.stringify({ done: {}, recent: [t - 700000, t - 800000, t - 900000] }) } });
  old.endTurn();
  assert.equal(auto(old.loaded).state, "count", "старше 10 минут не в счёт");
  const off = page({ local: { "myclaude.autoContinue": "off" } });
  off.endTurn();
  assert.deepEqual([auto(off.loaded).on, auto(off.loaded).reason], [false, "выключено"]);
});

test("К7.5: dispose и повторная инъекция снимают обе кнопки", () => {
  const { loaded, endTurn } = page();
  endTurn();
  assert.equal(loaded.dom.queryAll(CANCEL).length, 1);
  const again = loaded.reload();
  assert.equal(again.error, null, String(again.error?.stack ?? again.error));
  assert.equal(loaded.dom.queryAll(CANCEL).length, 0, "отсчёт прошлой установки снят вместе с её кнопками");
  assert.ok(loaded.dom.queryAll(BOX).length <= 1, "кнопка одна — новой установки");
  assert.equal(label(loaded), "💬 Новый чат");
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(BOX).length, 0);
  assert.equal(loaded.dom.queryAll(CANCEL).length, 0);
});

// ---- проверка на гейте WF85 (D1, D2, D4) ------------------------------------

test("D1: ход прервали без нового ответа — старый ответ с блоком сам не открывается", () => {
  const { loaded, again, beat } = page({ stop: false });
  assert.equal(loaded.dom.queryAll(BOX).length, 1, "кнопка у старого ответа стоит");
  again();
  assert.equal(auto(loaded).state, "off");
  assert.equal(auto(loaded).reason, "ответ старый");
  beat(40);
  assert.equal(clicks(loaded), 0);
});

test("D2: чего нет в строке «Модель:», то берётся у донора — донор на Max, сам не открывает", () => {
  const donorOn = (loaded, effort) => {
    const model = loaded.dom.document.body.add("button", { attrs: { "data-testid": "epitaxy-cds-model-selector", "aria-label": "Model: Opus 5.5" } });
    const step = loaded.dom.document.body.add("button", { attrs: { "aria-label": `Effort: ${effort}` } });
    return { model, step };
  };
  const bare = page({ answers: [{ model: "Модель: Opus 5.5" }] });
  donorOn(bare.loaded, "Max");
  bare.endTurn();
  assert.equal(auto(bare.loaded).reason, "Fable/Max — руками");
  // Ступень в строке есть — донорская Max не мешает.
  const low = page();
  donorOn(low.loaded, "Max");
  low.endTurn();
  assert.equal(auto(low.loaded).state, "count");
});

test("D4: черновик появился посреди счёта (вставка мышью) — на нуле не жмёт", () => {
  const { loaded, parts, endTurn, beat } = page();
  endTurn();
  assert.equal(auto(loaded).state, "count");
  parts.editor.__text = "вставил мышью";
  beat(40);
  assert.equal(clicks(loaded), 0);
  assert.equal(auto(loaded).state, "cancelled");
  assert.equal(auto(loaded).reason, "черновик в поле");
});

// F07: прежние проверки автоматики выше явно включают настройку; чистая
// установка и миграция проверяются отдельно через настоящий command handler.
const SWITCH = 'myclaude.autoContinue';
const toggle = (loaded, on, extra = {}) => loaded.dom.command({ id: `switch-${Math.random()}`, action: 'auto-continue', on, ...extra });

test('F07: fresh install and reload stay off, manual New Chat remains usable', async () => {
  const p = page({ enabled: false });
  p.endTurn(); p.beat(40);
  assert.equal(p.loaded.api.status().autoContinue, false);
  assert.equal((await p.loaded.api.chats({ scan: false })).autoContinue, false);
  assert.equal(p.loaded.win.localStorage.getItem(SWITCH), null);
  assert.equal(clicks(p.loaded), 0);
  assert.equal(p.loaded.reload().error, null);
  assert.equal(p.loaded.api.status().autoContinue, false);
  click(p.loaded, main(p.loaded));
  assert.equal(clicks(p.loaded), 1);
  assert.ok(p.loaded.document.title.startsWith(PREFIX));
  p.loaded.api.dispose();
});

for (const value of ['true', 'false', 'off', 'on', 'garbage']) test(`F07: saved ${value} survives migration and reload; only true enables`, async () => {
  const p = page({ enabled: false, local: { [SWITCH]: value } });
  toggle(p.loaded, true, { migrate: true });
  assert.equal(p.loaded.win.localStorage.getItem(SWITCH), value);
  assert.equal(p.loaded.api.status().autoContinue, value === 'true');
  assert.equal((await p.loaded.api.chats({ scan: false })).autoContinue, value === 'true');
  assert.equal(p.loaded.reload().error, null);
  assert.equal(p.loaded.api.status().autoContinue, value === 'true');
  toggle(p.loaded, false); assert.equal(p.loaded.win.localStorage.getItem(SWITCH), 'false');
  toggle(p.loaded, true); assert.equal(p.loaded.win.localStorage.getItem(SWITCH), 'true');
  assert.equal(p.loaded.api.status().autoContinue, true); p.loaded.api.dispose();
});

for (const on of [true, false]) test(`F07: migration fills absent with ${on}, invalid string command is ignored`, () => {
  const p = page({ enabled: false });
  toggle(p.loaded, 'true'); assert.equal(p.loaded.win.localStorage.getItem(SWITCH), null);
  toggle(p.loaded, on, { migrate: true });
  assert.equal(p.loaded.win.localStorage.getItem(SWITCH), String(on));
  assert.equal(p.loaded.api.status().autoContinue, on); p.loaded.api.dispose();
});

test('F07: off cancels countdown immediately, re-enable does not resume old evaluator', () => {
  const p = page(); p.endTurn(); assert.equal(auto(p.loaded).state, 'count');
  toggle(p.loaded, false);
  assert.equal(auto(p.loaded).state, 'off'); assert.equal(auto(p.loaded).left, 0);
  assert.equal(p.loaded.dom.queryAll(CANCEL).length, 0);
  assert.equal(label(p.loaded), '💬 Новый чат');
  toggle(p.loaded, true); p.beat(40); assert.equal(clicks(p.loaded), 0);
  click(p.loaded, main(p.loaded)); assert.equal(clicks(p.loaded), 1);
  toggle(p.loaded, false);
  assert.equal(p.loaded.api.status().continue.pending, true, 'manual request remains with ContinueWatch');
  assert.ok(p.loaded.document.title.startsWith(PREFIX)); p.loaded.api.dispose();
});

test('F07: off clears armed evaluator before answer, storage event stops active countdown', () => {
  const p = page(); toggle(p.loaded, false); p.endTurn(); toggle(p.loaded, true); p.beat(40);
  assert.equal(clicks(p.loaded), 0); p.loaded.api.dispose();
  const q = page(); q.endTurn(); assert.equal(auto(q.loaded).state, 'count');
  q.loaded.win.localStorage.setItem(SWITCH, 'false');
  q.loaded.win.dispatchEvent({ type: 'storage', key: SWITCH });
  assert.equal(auto(q.loaded).state, 'off'); assert.equal(q.loaded.dom.queryAll(CANCEL).length, 0);
  q.beat(40); assert.equal(clicks(q.loaded), 0); q.loaded.api.dispose();
});

for (const failure of ['get', 'set']) test(`F07: storage ${failure} error disables automation and reports false`, async () => {
  const p = page(); p.endTurn();
  const storage = p.loaded.win.localStorage;
  if (failure === 'get') {
    const read = storage.getItem.bind(storage);
    storage.getItem = key => { if (key === SWITCH) throw Error('unavailable'); return read(key); };
    p.loaded.win.dispatchEvent({ type: 'storage', key: SWITCH });
  } else {
    storage.setItem = () => { throw Error('quota'); };
    toggle(p.loaded, false);
  }
  assert.equal(p.loaded.api.status().autoContinue, false);
  assert.equal((await p.loaded.api.chats({ scan: false })).autoContinue, false);
  assert.equal(auto(p.loaded).state, 'off'); p.beat(40); assert.equal(clicks(p.loaded), 0); p.loaded.api.dispose();
});
