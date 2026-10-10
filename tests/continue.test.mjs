// Кнопка «💬 Новый чат» в самом чате (раздел 12к inject.js, #7246,
// WF84) и закрепка нового чата цепочкой new-window (pin / unpin).
//
// Слово Элвиса 23.09: кнопка там, где блок продолжения, «чтоб всё автоматически
// было под рукой… и новый чат, который продолжается, сразу в закреплённые
// уходит». Канал к приложению — метка в document.title (как замок К6): клик
// ставит `Пимп: продолжить в новом чате · <метка>` на CONTINUE_HOLD_MS, ответ
// приложения — команда cashout с handoff. Контракт — docs/CONTRACTS.md, WF84.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { loadInject, plain } from "./load.mjs";

const fixture = name => JSON.parse(readFileSync(new URL(`./fixtures/cashout/${name}.json`, import.meta.url), "utf8"));
const HANDOFF = fixture("record-handoff").text;
const BOX = "[data-myclaude-continue]";
const PREFIX = "Пимп: продолжить в новом чате · ";

// Ответ с блоком передачи — разметка Claude 2.2553: div.epitaxy-codeblock >
// div.relative > div[data-code-text].
const answerWith = (dom, top, { head = "🆕 ОТКРОЙ НОВЫЙ ЧАТ", code = HANDOFF } = {}) => {
  const answer = dom.document.body.add("div", {
    attrs: { "data-testid": "assistant-message" }, rect: { left: 0, top, width: 800, height: 100 },
  });
  answer.add("p", { text: "Сделал." });
  if (head) answer.add("h2", { text: head });
  const block = answer.add("div", { class: "epitaxy-codeblock relative" });
  block.add("div", { class: "relative" }).add("div", { attrs: { "data-code-text": code }, text: code });
  const after = answer.add("p", { text: "Хвост ответа." });
  return { answer, block, after };
};
const page = ({ answers = [{}], title = "VkusnoffKz 2" } = {}) => {
  const got = [];
  const loaded = loadInject({
    href: "about:blank", title, hasFocus: false,
    html: dom => {
      const parts = dom.composer();
      answers.forEach((spec, index) => got.push(spec === null
        ? { answer: dom.document.body.add("div", { attrs: { "data-testid": "assistant-message" }, text: "Просто ответ." }) }
        : answerWith(dom, 100 + index * 120, spec)));
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  // Часы идут сами (страница ждёт времени в циклах), тест только добавляет сдвиг.
  // База заморожена (z8-r01): часы страницы двигает только тест, иначе
  // настоящее время под нагрузкой утекало бы в отсчёт.
  const base = loaded.win.performance.now();
  let shift = 0;
  loaded.win.performance.now = () => base + shift;
  const tick = ms => { shift += ms; };
  const pass = () => {
    tick(500);
    loaded.win.dispatchEvent({ type: "resize" });
    loaded.dom.fireKind("timeout");
    loaded.dom.fireKind("raf");
  };
  pass();
  return { loaded, got, tick, pass };
};
const button = loaded => loaded.dom.query(`${BOX} button`);
// Стенд не всплывает событиями — клик приходит слушателю захвата на document.
const click = loaded => loaded.document.dispatchEvent({ type: "click", target: button(loaded), bubbles: true });
const label = loaded => button(loaded)?.getAttribute("data-myclaude-continue-label");
const timers = loaded => loaded.dom.ids("timeout");
const fireAll = (loaded, rounds = 200) => {
  for (let index = 0; index < rounds && timers(loaded).length; index += 1) loaded.dom.fireKind("timeout");
};

test("#7246: кнопка встаёт ровно под блоком передачи последнего ответа", () => {
  const { loaded, got } = page({ answers: [{}, {}] });
  const boxes = loaded.dom.queryAll(BOX);
  assert.equal(boxes.length, 1, "одна кнопка — у последнего ответа");
  assert.equal(boxes[0].previousElementSibling, got[1].block, "сразу после блока кода, а не после внутреннего узла");
  assert.equal(label(loaded), "💬 Новый чат");
  assert.equal(got[1].answer.textContent.includes("Новый чат"), false, "подпись — из атрибута, текста ответа не трогает");
});

test("#7246: блок передачи только в старом ответе или его нет — кнопки нет", () => {
  assert.equal(page({ answers: [{}, null] }).loaded.dom.queryAll(BOX).length, 0);
  assert.equal(page({ answers: [{ head: "Итог" }] }).loaded.dom.queryAll(BOX).length, 0);
});

test("#7246: пришёл новый ответ без блока — старая кнопка уходит", () => {
  const { loaded, pass } = page();
  assert.equal(loaded.dom.queryAll(BOX).length, 1);
  loaded.document.body.add("div", { attrs: { "data-testid": "assistant-message" }, text: "Новый ответ." });
  pass();
  assert.equal(loaded.dom.queryAll(BOX).length, 0);
});

test("#7246: клик — метка в заголовке окна на срок, заголовок чата для страницы прежний", () => {
  const { loaded, tick } = page();
  click(loaded);
  const title = String(loaded.document.title);
  assert.ok(title.startsWith(PREFIX), `метка в заголовке: ${title}`);
  assert.match(title.slice(PREFIX.length), /^[0-9a-z]+$/, "метка — base36");
  assert.equal(loaded.inner.windowTitle(), "VkusnoffKz 2", "адресация и ключ темы видят имя чата");
  assert.equal(label(loaded), "⏳ Зову Пимпа…");
  assert.equal(button(loaded).getAttribute("aria-disabled"), "true");
  // Claude переписал заголовок посреди срока — метка встаёт обратно.
  loaded.document.title = "VkusnoffKz 2 (попап)";
  tick(100);
  loaded.dom.fire(timers(loaded)[0]);
  assert.ok(String(loaded.document.title).startsWith(PREFIX));
  tick(1200);
  fireAll(loaded, 3);
  assert.equal(loaded.document.title, "VkusnoffKz 2 (попап)", "срок вышел — его заголовок на месте");
  assert.equal(plain(loaded.api.status().continue).mark, null);
});

test("#7246: второй клик, пока ждём, — ничего; команда cashout с handoff — ответ приложения", () => {
  const { loaded } = page();
  click(loaded);
  const first = loaded.document.title;
  click(loaded);
  assert.equal(loaded.document.title, first, "метка не сменилась");
  loaded.dom.command({ id: "c1", action: "cashout", at: "now", scope: "window", title: "VkusnoffKz 2", handoff: true });
  const status = plain(loaded.api.status().continue);
  assert.equal(status.clicks, 1);
  assert.equal(status.acked, 1);
  assert.equal(status.pending, false);
  assert.equal(loaded.document.title, "VkusnoffKz 2", "метка снята сразу");
  assert.equal(label(loaded), "✓ Открываю новый чат…");
});

test("#7246: приложение молчит — кнопка снова живая и плашка «Пимп пока не взялся»", () => {
  const { loaded, tick } = page();
  click(loaded);
  // z2-r03: срок ожидания не короче очереди приложения (замок пустого окна
  // до ~9,5 с) — всё, что назначено раньше 12 с, ещё «⏳».
  for (let round = 0; round < 200; round += 1) {
    const early = [...loaded.dom.timers.entries()].filter(([, item]) => item.kind === "timeout" && item.ms < 12000);
    if (!early.length) break;
    for (const [id, item] of early) { loaded.win.clearTimeout(id); item.fn(); }
  }
  assert.equal(plain(loaded.api.status().continue).pending, true, "раньше 12 с плашки быть не должно");
  tick(13000);
  fireAll(loaded);
  const status = plain(loaded.api.status().continue);
  assert.equal(status.pending, false);
  assert.equal(status.silent, 1);
  assert.equal(label(loaded), "💬 Новый чат");
  assert.equal(button(loaded).hasAttribute("aria-disabled"), false);
  assert.ok(loaded.document.body.textContent.includes("Пимп пока не взялся — проверь, что он запущен и у него есть доступ, и нажми ещё раз"), "плашка");
  assert.equal(loaded.document.title, "VkusnoffKz 2");
});

test("#7246: dispose снимает кнопку и метку", () => {
  const { loaded } = page();
  click(loaded);
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(BOX).length, 0);
  assert.equal(loaded.document.title, "VkusnoffKz 2");
});

test("#7246: «Обкэшить» с handoff берёт тот же блок — кнопка его не портит", () => {
  const { loaded } = page();
  loaded.dom.command({ id: "c1", action: "cashout", at: "now", scope: "window", title: "VkusnoffKz 2", handoff: true });
  assert.equal(JSON.parse(loaded.win.localStorage.getItem("myclaude-cashout")).text, HANDOFF);
});

// ---- цепочка new-window: закрепить новый, открепить старый --------------------
const drain = () => new Promise(resolve => setImmediate(resolve));
const settle = async (times = 6) => { for (let index = 0; index < times; index += 1) await drain(); };
// Строка сайдбара с контекстным меню как у Claude 2.2553: пункт «Pin»/«Unpin»
// с приклеенной клавишей «p»; клик переносит строку между Pinned и Recents.
const home = ({ donorPinned = true, menu = true, stores = null } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy", title: "Claude",
    storage: { local: { "myclaude-cashout": JSON.stringify({ at: Date.now(), text: HANDOFF, handoff: true }) } },
    html: dom => {
      const input = dom.document.body.add("div", { attrs: { "data-testid": "code-prompt-input", contenteditable: "true" } });
      const send = dom.document.body.add("button", { attrs: { "data-testid": "code-prompt-send" } });
      const bar = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
      const pinned = bar.add("div", { attrs: { "data-testid": "sidebar-pinned" } });
      const recents = bar.add("div", { attrs: { "data-testid": "sidebar-recents" } });
      return { input, send, pinned, recents };
    },
  });
  const { parts } = loaded;
  const box = { menus: [] };
  const row = (list, id, text) => {
    const node = list.add("div", { attrs: { "data-row-key": `code:${id}` }, text });
    node.addEventListener("contextmenu", () => {
      box.menus.push(id);
      if (!menu) return;
      const isPinned = node.parentElement === parts.pinned;
      const popup = loaded.document.body.add("div", { attrs: { role: "menu" } });
      popup.add("div", { attrs: { role: "menuitem" }, text: "Rename" });
      const item = popup.add("div", { attrs: { role: "menuitem" }, text: isPinned ? "UnpinP" : "PinP" });
      item.addEventListener("click", () => {
        node.remove();
        row(isPinned ? parts.recents : parts.pinned, id, text);
        popup.remove();
      });
    });
    return node;
  };
  row(donorPinned ? parts.pinned : parts.recents, "local_old", "Старый чат");
  parts.send.addEventListener("click", () => {
    loaded.win.location.pathname = "/epitaxy/local_new";
    row(parts.recents, "local_new", "VkusnoffKz 3");
  });
  const hook = () => {};
  hook.getState = () => ({ popoutWindows: loaded.run("new Map()"), openPopout: () => {} });
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  // Сторы закрепки (WF85, К9): звёздочки и порядок закреплённых. Как Claude,
  // setStarred сам кладёт новый ключ НАВЕРХ порядка и снимает снятый.
  const chunk = { Store: hook };
  if (stores) {
    box.order = [];
    const pins = { starredIds: [...stores.starred], pinnedOrder: [...stores.order] };
    const star = () => {};
    star.getState = () => ({
      starredIds: pins.starredIds,
      setStarred: (id, on) => {
        pins.starredIds = on ? [...pins.starredIds.filter(item => item !== id), id] : pins.starredIds.filter(item => item !== id);
        pins.pinnedOrder = on ? [`code:${id}`, ...pins.pinnedOrder] : pins.pinnedOrder.filter(key => key !== `code:${id}`);
      },
    });
    const order = () => {};
    order.getState = () => ({
      pinnedOrder: pins.pinnedOrder,
      setPinnedOrder: list => { box.order.push([...list]); pins.pinnedOrder = [...list]; },
    });
    Object.assign(chunk, { Star: star, Order: order });
    box.pins = pins;
  }
  loaded.inner.setModuleImporter(() => Promise.resolve(chunk));
  return { loaded, parts, box };
};
const run = async (loaded, rounds = 80) => {
  let clock = loaded.win.performance.now();
  loaded.win.performance.now = () => clock;
  for (let index = 0; index < rounds; index += 1) {
    clock += 100;
    await settle(4);
    const ids = loaded.dom.ids("timeout");
    if (ids.length) loaded.dom.fire(ids[ids.length - 1]);
  }
  await settle();
};
const newChat = extra => ({
  id: "n1", action: "new-window", at: "now", scope: "window", title: "Claude",
  x: 100, y: 200, text: "Окно открыто. Жди задачу.", folder: "", name: "", sendTransfer: true, stay: true, ...extra,
});
const keys = list => [...list.querySelectorAll("[data-row-key]")].map(node => node.getAttribute("data-row-key"));

test("#7246: pin — новый чат уходит в закреплённые, unpin — старый оттуда уходит", async () => {
  const { loaded, parts } = home();
  loaded.dom.command(newChat({ pin: true, unpin: "local_old" }));
  await run(loaded);
  const mark = plain(loaded.api.status().newWindow);
  assert.equal(mark.pin, "ok");
  assert.equal(mark.unpin, "ok");
  assert.equal(mark.state, "ok");
  assert.deepEqual(keys(parts.pinned), ["code:local_new"], "наверху только живой чат");
  assert.deepEqual(keys(parts.recents), ["code:local_old"]);
  assert.equal(loaded.dom.queryAll('[role="menu"]').length, 0, "меню за собой закрыты");
});

test("#7246: старый не закреплён — открепление не трогаем; без pin цепочка меню не открывает", async () => {
  const first = home({ donorPinned: false });
  first.loaded.dom.command(newChat({ pin: true, unpin: "local_old" }));
  await run(first.loaded);
  assert.equal(plain(first.loaded.api.status().newWindow).unpin, "already");
  assert.deepEqual(first.box.menus, ["local_new"], "меню старого не открывали");
  const second = home();
  second.loaded.dom.command(newChat({}));
  await run(second.loaded);
  assert.deepEqual(second.box.menus, []);
  assert.equal(plain(second.loaded.api.status().newWindow).pin, null);
});

test("#7246: пункта в меню нет — закрепка тихо не вышла, чат создан, цепочка «ok»", async () => {
  const { loaded } = home({ menu: false });
  loaded.dom.command(newChat({ pin: true, unpin: "local_old" }));
  await run(loaded);
  const mark = plain(loaded.api.status().newWindow);
  assert.equal(mark.pin, "no-menu");
  assert.equal(mark.state, "ok");
  assert.equal(loaded.win.location.pathname, "/epitaxy/local_new");
});

test("#7246: мусор в unpin не принимаем", async () => {
  const { loaded, box } = home();
  loaded.dom.command(newChat({ pin: true, unpin: "\"] body [x=\"" }));
  await run(loaded);
  assert.equal(plain(loaded.api.status().newWindow).unpin, null);
  assert.deepEqual(box.menus, ["local_new"]);
});

test("#7246: эталон new-window-handoff-pin.json — страница берёт pin и unpin из команды Swift", async () => {
  const sample = fixture("new-window-handoff-pin");
  assert.deepEqual(Object.keys(sample).slice(-4), ["sendTransfer", "stay", "pin", "unpin"], "pin и unpin — после stay");
  const { loaded, box } = home();
  // Адрес и папку стенд не повторяет: главное окно здесь — /epitaxy «Claude», папки нет.
  const { match, ...rest } = sample;
  void match;
  loaded.dom.command({ ...rest, title: "Claude", folder: "", model: undefined, effort: undefined });
  await run(loaded);
  const mark = plain(loaded.api.status().newWindow);
  assert.equal(mark.pin, "ok");
  assert.equal(mark.unpin, "already", "донора эталона в стенде нет в Pinned — открепление не трогаем");
  assert.deepEqual(box.menus, ["local_new"]);
});

// ---- WF85, К9 (#7366): новый чат — РОВНО на место старого, через сторы ---------
test("К9: сторы есть — новый встаёт на индекс донора, донор снят, дублей нет, меню не открывали", async () => {
  const { loaded, box } = home({
    stores: { starred: ["local_x", "local_old", "local_y"], order: ["code:local_x", "code:local_old", "code:local_y"] },
  });
  loaded.dom.command(newChat({ pin: true, unpin: "local_old" }));
  await run(loaded);
  const mark = plain(loaded.api.status().newWindow);
  assert.deepEqual(plain(box.pins.pinnedOrder), ["code:local_x", "code:local_new", "code:local_y"]);
  assert.deepEqual(plain(box.pins.starredIds).sort(), ["local_new", "local_x", "local_y"]);
  assert.equal(mark.pin, "ok");
  assert.equal(mark.unpin, "ok");
  assert.equal(mark.pinWay, "стор");
  assert.equal(mark.pinPlace, 1);
  assert.equal(mark.state, "ok");
  assert.deepEqual(box.menus, [], "контекстное меню не нужно");
});

test("К9: донор не закреплён — новый закреплён, порядок не трогаем", async () => {
  const { loaded, box } = home({ stores: { starred: ["local_x"], order: ["code:local_x"] } });
  loaded.dom.command(newChat({ pin: true, unpin: "local_old" }));
  await run(loaded);
  const mark = plain(loaded.api.status().newWindow);
  assert.equal(mark.pin, "ok");
  assert.equal(mark.unpin, "already");
  assert.equal(mark.pinWay, "стор");
  assert.deepEqual(box.order, [], "setPinnedOrder не звали");
  assert.ok(plain(box.pins.starredIds).includes("local_new"));
});

test("К9: сторов нет — прежний путь меню, pinWay «меню»", async () => {
  const { loaded } = home();
  loaded.dom.command(newChat({ pin: true, unpin: "local_old" }));
  await run(loaded);
  const mark = plain(loaded.api.status().newWindow);
  assert.equal(mark.pinWay, "меню");
  assert.equal(mark.pin, "ok");
  assert.equal(mark.pinPlace, null);
});

// ---- проверка на гейте WF85 (D5) ---------------------------------------------
test("D5: донор закреплён, но в порядке его нет — порядок не пишем; новый левее донора — место сходится", async () => {
  const lost = home({ stores: { starred: ["local_x", "local_old"], order: ["code:local_x"] } });
  lost.loaded.dom.command(newChat({ pin: true, unpin: "local_old" }));
  await run(lost.loaded);
  assert.deepEqual(lost.box.order, [], "setPinnedOrder не звали");
  assert.equal(plain(lost.loaded.api.status().newWindow).unpin, "ok");

  const left = home({
    stores: { starred: ["local_new", "local_old"], order: ["code:local_new", "code:local_x", "code:local_old"] },
  });
  left.loaded.dom.command(newChat({ pin: true, unpin: "local_old" }));
  await run(left.loaded);
  const mark = plain(left.loaded.api.status().newWindow);
  assert.deepEqual(plain(left.box.pins.pinnedOrder), ["code:local_x", "code:local_new"]);
  assert.equal(mark.unpin, "ok", "не ложный not-done");
  assert.equal(mark.pinPlace, 1);
});
