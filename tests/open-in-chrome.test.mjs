// «Открыть в Chrome» правой кнопкой по карточке файла (раздел 12г inject.js,
// WF67, задача #6190). Слово Элвиса: «правой кнопкой открываю, а здесь не вижу
// до сих пор открыть в Хром… приходится через Файндер идти».
//
// Проверяется контракт раздела, а не разметка Claude:
//   1) правый клик по карточке файла запоминает путь из React-волокна и ставит
//      наблюдателя за меню — на время, не навсегда; правый клик по тексту не
//      ставит ничего;
//   2) в меню Claude с «Show in Finder» наш пункт встаёт ПЕРВЫМ, жирным, с
//      меткой, плюс клон разделителя; вставка в одно меню — одна; чужое меню
//      (без «Show in Finder») не трогается;
//   3) клик по пункту зовёт мост Claude ровно раз с (id чата, путь) и потом
//      закрывает меню Escape; без чата или моста — плашка, мост не зовётся;
//   4) dispose() снимает подписку, наблюдателя, таймер и вставленный пункт.
//
// Наблюдатель стаба записи о мутациях не отдаёт, поэтому появление меню
// проверяется прямым вызовом openChromeInsert через люк, а сам наблюдатель —
// только счётчиком постановки/снятия.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_test";
const PATH = "/Users/elvis/_ElvisProjects/PimpMyClaude/docs/mockup-wf66-composer.html";
const ATTRIBUTE = "data-myclaude-open-chrome";
const NOTE_ID = "myclaude-new-window-note";

// Страница окна Claude: композер и карточка файла в ленте. Волокно React
// подкладывается свойством `__reactFiber$test`: у настоящей карточки пропс
// path лежит у компонента над кнопкой — поэтому и у стенда он на шаг выше.
const page = ({ href, title = "PimpMyClaude", path = PATH, fiberAt = "parent" } = {}) =>
  loadInject({
    href,
    title,
    html: dom => {
      const parts = dom.composer();
      parts.transcript = dom.document.body.add("div", {
        attrs: { "data-testid": "assistant-message" },
        rect: { left: 100, top: 200, width: 1000, height: 300 },
        text: "Последний ответ Claude.",
      });
      parts.card = parts.transcript.add("button", { class: "font-sans rounded-lg" });
      parts.label = parts.card.add("span", { text: "html mockup-wf66-composer.html 10.1kB" });
      const above = { memoizedProps: { path, name: "mockup-wf66-composer.html", title: path }, return: null };
      const own = { memoizedProps: { children: [] }, return: above };
      if (path !== null) parts.card.__reactFiber$test = fiberAt === "parent" ? own : above;
      return parts;
    },
  });

// Контекстное меню Claude, каким его видела разведка: пункты в прокручиваемом
// листе, разделитель перед «Show in Finder».
const menuOf = (loaded, { finder = "Show in Finder" } = {}) => {
  const menu = loaded.document.body.add("div", { attrs: { role: "menu", "data-cds": "ContextMenu" } });
  const list = menu.add("div", { attrs: { "data-cds-sheet-scroll": "" } });
  const item = text => {
    const node = list.add("div", { attrs: { role: "menuitem", id: `item-${text}` } });
    node.add("span", { class: "min-w-0 flex-1 truncate", text });
    return node;
  };
  item("Attach as context");
  item("Copy");
  list.add("div", { attrs: { role: "separator" }, class: "my-1 h-px bg-border" });
  if (finder) item(finder);
  return { menu, list };
};

const rightClick = (loaded, target) => loaded.document.dispatchEvent({ type: "contextmenu", target });
const found = loaded => loaded.inner.openChromePath(loaded.parts.card);
const ours = list => list.children.filter(node => node.hasAttribute(ATTRIBUTE));
const listeners = (loaded, type) => (loaded.document.__listeners.get(type) ?? []).length;
const bridgeOf = (loaded, reply = () => Promise.resolve({ ok: true })) => {
  const calls = [];
  loaded.win["claude.web"] = {
    LocalSessions: { openSessionFileInDefaultApp: (...args) => { calls.push(args); return reply(...args); } },
  };
  return calls;
};
const keys = loaded => {
  const seen = [];
  loaded.document.addEventListener("keydown", event => seen.push(event.key));
  return seen;
};
const settle = () => new Promise(resolve => setTimeout(resolve, 0));

test("правый клик по карточке: путь из волокна, наблюдатель — на время", () => {
  const loaded = page();
  const before = { observers: loaded.counters.observers, timers: loaded.counters.timers };
  const passed = rightClick(loaded, loaded.parts.label);

  assert.equal(passed, true, "contextmenu отменять нельзя — меню Claude открывает сам Claude");
  const status = plain(loaded.api.status().openInChrome);
  assert.equal(status.path, PATH, "путь из React-волокна не найден");
  assert.equal(status.pending, true, "меню не ждут");
  assert.equal(loaded.counters.observers, before.observers + 1, "наблюдатель за меню не встал");
  assert.equal(loaded.counters.timers, before.timers + 1, "у наблюдателя нет срока");

  // Срок вышел — наблюдатель и таймер сняты сами, путь остаётся на память.
  loaded.dom.fireKind("timeout");
  assert.equal(loaded.counters.observers, before.observers, "наблюдатель пережил свой срок");
  assert.equal(loaded.counters.timers, before.timers, "таймер срока не снят");
  assert.equal(plain(loaded.api.status().openInChrome).pending, false);
});

test("не страница (.md, .png) — пункта нет вовсе: мост открыл бы файл не в Chrome", () => {
  for (const other of [PATH.replace(/\.html$/, ".md"), PATH.replace(/\.html$/, ".png")]) {
    const loaded = page({ path: other });
    assert.equal(found(loaded), null, `${other}: путь не должен опознаваться`);
  }
});

test("путь берётся и с префиксом computer://, и с волокна самой кнопки", () => {
  const prefixed = page({ path: `computer://${PATH}` });
  assert.equal(found(prefixed)?.path, PATH, "префикс computer:// не снят");
  const own = page({ fiberAt: "own" });
  assert.equal(found(own)?.path, PATH, "пропс на волокне самой кнопки не найден");
  assert.equal(found(own)?.name, "mockup-wf66-composer.html", "имя файла не взято");
});

test("правый клик по тексту: наблюдатель не ставится, путь пуст", () => {
  const loaded = page();
  const before = loaded.counters.observers;
  rightClick(loaded, loaded.parts.transcript);
  const status = plain(loaded.api.status().openInChrome);
  assert.equal(status.pending, false, "ждут меню, хотя файла под курсором нет");
  assert.equal(status.path, null, "путь взялся из ниоткуда");
  assert.equal(loaded.counters.observers, before, "наблюдатель встал на правый клик по тексту");
});

test("меню с «Show in Finder»: наш пункт первым, жирным, с разделителем, один раз", () => {
  const loaded = page();
  const { menu, list } = menuOf(loaded);
  assert.equal(loaded.inner.openChromeInsert(menu, found(loaded)), true, "пункт не встал");

  const first = list.firstElementChild;
  assert.ok(first.hasAttribute(ATTRIBUTE), "наш пункт не первый");
  assert.equal(first.getAttribute("role"), "menuitem");
  assert.equal(first.textContent, "🌐 Открыть в Chrome");
  assert.equal(first.style.getPropertyValue("font-weight"), "600", "пункт не жирный");
  assert.equal(first.id, "", "у клона остался id пункта Claude");
  assert.equal(list.children[1].getAttribute("role"), "separator", "после пункта нет разделителя");
  assert.ok(list.children[1].hasAttribute(ATTRIBUTE), "разделитель без метки — dispose его не снимет");
  assert.equal(list.children[2].textContent, "Attach as context", "пункты Claude сдвинулись не туда");
  assert.equal(list.querySelectorAll('[role="menuitem"]').length, 4, "пунктов Claude стало не столько");

  // Подсветка — атрибутом, по которому Claude рисует фон.
  first.dispatchEvent({ type: "pointerenter" });
  assert.ok(first.hasAttribute("data-highlighted"), "подсветка при наведении не встала");
  first.dispatchEvent({ type: "pointerleave" });
  assert.ok(!first.hasAttribute("data-highlighted"), "подсветка не снята");

  assert.equal(loaded.inner.openChromeInsert(menu, found(loaded)), false, "в то же меню встали второй раз");
  assert.equal(ours(list).length, 2, "пункт и разделитель задвоились");
  assert.equal(plain(loaded.api.status().openInChrome).inserted, 1);
});

test("чужое меню без «Show in Finder» не трогаем", () => {
  const loaded = page();
  const { menu, list } = menuOf(loaded, { finder: null });
  assert.equal(loaded.inner.openChromeInsert(menu, found(loaded)), false);
  assert.equal(ours(list).length, 0, "в чужое меню вставили пункт");
  assert.equal(list.children.length, 3, "чужое меню изменилось");
});

test("клик: мост Claude зовётся ровно раз с (id чата, путь), меню закрывается Escape", async () => {
  const loaded = page();
  const calls = bridgeOf(loaded);
  const seen = keys(loaded);
  const { menu, list } = menuOf(loaded);
  loaded.inner.openChromeInsert(menu, found(loaded));

  const stopped = [];
  list.firstElementChild.dispatchEvent({ type: "click", stopPropagation: () => stopped.push(1) });
  assert.deepEqual(calls, [[CHAT, PATH]], "мост позван не так или не раз");
  assert.equal(stopped.length, 1, "клик всплыл в меню Claude");
  assert.deepEqual(seen, ["Escape"], "меню не закрыто Escape");
  await settle();
  assert.deepEqual(plain(loaded.api.status().openInChrome.last), { path: PATH, ok: true, error: "" });
  assert.equal(loaded.document.querySelector(`#${NOTE_ID}`), null, "плашка на удачном открытии");
});

test("мост ответил ошибкой: плашка с текстом, обрезанным до 120 знаков", async () => {
  const loaded = page();
  const error = "Ошибка ".repeat(40);
  bridgeOf(loaded, () => Promise.reject(new Error(error)));
  const { menu, list } = menuOf(loaded);
  loaded.inner.openChromeInsert(menu, found(loaded));
  list.firstElementChild.dispatchEvent({ type: "click" });
  await settle();
  const last = plain(loaded.api.status().openInChrome.last);
  assert.equal(last.ok, false);
  assert.equal(last.error, error.slice(0, 120));
  assert.equal(loaded.document.querySelector(`#${NOTE_ID}`)?.textContent, error.slice(0, 120), "плашки с ошибкой нет");
});

test("моста нет: плашка, ничего не зовём", () => {
  const loaded = page();
  const seen = keys(loaded);
  loaded.inner.openChromeOpen(PATH);
  assert.equal(plain(loaded.api.status().openInChrome.last).error, "no-bridge");
  assert.equal(loaded.document.querySelector(`#${NOTE_ID}`)?.textContent, "Claude не даёт открыть файл");
  assert.deepEqual(seen, ["Escape"], "меню без моста осталось открытым");
});

test("чат неизвестен (попап без родителя): плашка, мост не зовём", () => {
  const loaded = page({ href: "about:blank", title: "Bro Flow" });
  const calls = bridgeOf(loaded);
  loaded.inner.openChromeOpen(PATH);
  assert.deepEqual(calls, [], "мост позван без id чата");
  assert.equal(plain(loaded.api.status().openInChrome.last).error, "no-chat");
  assert.equal(loaded.document.querySelector(`#${NOTE_ID}`)?.textContent, "Не знаю, какой это чат — открой через Finder");
});

test("на чужой странице подписки нет", () => {
  const alien = page({ href: "data:text/html,<p>артефакт</p>", title: "Артефакт" });
  assert.equal(alien.error, null, "чужая страница инжект не роняет");
  assert.equal(listeners(alien, "contextmenu"), 0);
  assert.equal(listeners(page(), "contextmenu"), 1);
});

test("dispose(): подписка, наблюдатель, срок и вставленный пункт сняты; второй прогон не удваивает", () => {
  const loaded = page();
  const base = { observers: loaded.counters.observers, timers: loaded.counters.timers };
  rightClick(loaded, loaded.parts.label);
  const { menu, list } = menuOf(loaded);
  loaded.inner.openChromeInsert(menu, found(loaded));
  assert.equal(ours(list).length, 2);

  const again = loaded.reload();
  assert.equal(again.error, null, "второй прогон упал");
  assert.equal(ours(list).length, 0, "пункт прошлого экземпляра остался в меню");
  assert.equal(listeners(loaded, "contextmenu"), 1, "подписок стало не одна");
  assert.equal(loaded.counters.observers, base.observers, "наблюдатель прошлого экземпляра жив");
  assert.equal(loaded.counters.timers, base.timers, "срок прошлого экземпляра жив");
  assert.equal(loaded.inner.openChromeInsert(menu, found(loaded)), true);
  assert.equal(ours(list).length, 2, "после перезапуска пункт задвоился");

  loaded.api.dispose();
  assert.equal(listeners(loaded, "contextmenu"), 0, "подписка пережила dispose");
  assert.equal(ours(list).length, 0, "пункт пережил dispose");
});
