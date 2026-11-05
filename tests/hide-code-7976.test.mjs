// #7976 (раздел 12т³ inject.js, контракт К-HC): «Прятать код и планы». Команда `hide-code` {on:"true"|"false"} всем
// окнам; флаг — localStorage["myclaude.hideCode"] = "1" | "0", нет ключа — выключено; метка — data-myclaude-hide-code
// на <html>; длинный блок кода законченного ответа (.epitaxy-codeblock, текст и язык — из пропсов {text, lang, rawLang}
// шагом выше по волокну, как у 12с и 12т) сворачивается своей строкой первым ребёнком блока
// (div[data-myclaude-code-fold], подпись — в data-myclaude-code-label), сам блок — data-myclaude-code-hidden="closed";
// прячет правило lateRules (высота 0 и прозрачность). status().hideCode = {on, folded, plans}.
//
// Разметка строки ответа — как в hide-tools-wf120 (article → … → transcript-row → AssistantMessage → div.gap-5),
// блок кода — как в code-to-chat-wf120 (по коду Claude 19.10: div.epitaxy-codeblock > div.epitaxy-fence[data-code-text]
// > pre и полоса с «Copy code»). MutationObserver в стабе не срабатывает: после правки ленты тест зовёт сверку сам
// (inner.hideCodeSync) — в бою её зовёт свой наблюдатель.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const KEY = "myclaude.hideCode";
const ATTR = "data-myclaude-hide-code";
const FOLD = "data-myclaude-code-fold";
const LABEL = "data-myclaude-code-label";
const HIDDEN = "data-myclaude-code-hidden";

const lines = (count, word = "let value") => Array.from({ length: count }, (_, index) => `${word}${index} = ${index}`).join("\n");

const codeBlock = (parent, { text, lang = "swift", rawLang = lang }) => {
  const block = parent.add("div", { class: "epitaxy-codeblock relative max-w-full w-fit" });
  block["__reactFiber$test"] = { memoizedProps: { className: "epitaxy-codeblock" }, stateNode: block, return: { memoizedProps: { text, lang, rawLang }, return: null } };
  const fence = block.add("div", { class: "epitaxy-diff epitaxy-fence rounded-lg overflow-clip", attrs: { "data-code-text": text.trimEnd() } });
  fence.add("pre", { text });
  block.add("div", { class: "pointer-events-none absolute" }).add("div", { class: "pointer-events-auto sticky flex" })
    .add("button", { class: "cds-button ghost size-base", attrs: { "aria-label": "Copy code" } });
  return block;
};

// Строка ответа: transcript-row → AssistantMessage → тело (div.gap-5). streaming — метки Claude у строки и сообщения;
// marks:false — меток нет вовсе (старая разметка: живость — по кнопке стопа).
const answerRow = (feed, index, { streaming = false, marks = true } = {}) => {
  const rowAttrs = { "data-rs-index": String(index), "data-testid": "transcript-row", "data-perf-row": "assistant" };
  const messageAttrs = { "data-cds": "AssistantMessage", "data-testid": "assistant-message" };
  if (marks) {
    rowAttrs["data-perf-row-streaming"] = String(streaming);
    messageAttrs["data-is-streaming"] = String(streaming);
  }
  const row = feed.add("div", { attrs: rowAttrs });
  const message = row.add("div", { class: "rounded-lg", attrs: { role: "article", "aria-label": `Message ${index}` } })
    .add("div", { attrs: { "data-transcript-row": "" } })
    .add("div", { class: "group/message-row relative flex w-full min-w-0", attrs: messageAttrs });
  const body = message.add("div", { class: "flex min-w-0 flex-col gap-5" });
  body.row = row;
  body.message = message;
  return body;
};

const page = ({ storage = {}, build = null } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_c0de-7976", title: "Код",
    storage: { local: { "myclaude-auto-allow-roam": "off", ...storage } },
    html: dom => {
      const parts = dom.composer({});
      parts.feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } });
      if (build) build(parts.feed, parts, dom);
      else {
        parts.body = answerRow(parts.feed, 10);
        parts.body.add("p", { text: "Вот файл целиком." });
        parts.long = codeBlock(parts.body, { text: `${lines(24)}\n` });
        parts.body.add("p", { text: "Готово." });
      }
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return { loaded, parts: loaded.parts };
};
const status = loaded => plain(loaded.api.status().hideCode);
const rows = loaded => loaded.dom.queryAll(`[${FOLD}]`);
const rowOf = block => [...block.children].find(kid => kid.hasAttribute(FOLD)) ?? null;
const sync = loaded => loaded.inner.hideCodeSync();
const on = loaded => loaded.dom.command({ action: "hide-code", on: "true" });
const css = loaded => loaded.dom.queryAll("style").map(node => node.textContent).join("\n");

test("#7976: по умолчанию выключено — строк, меток и наблюдателя нет", () => {
  const { loaded, parts } = page();
  assert.deepEqual(status(loaded), { on: false, folded: 0, plans: 0 });
  assert.equal(rows(loaded).length, 0);
  assert.equal(loaded.document.documentElement.hasAttribute(ATTR), false);
  assert.equal(parts.long.hasAttribute(HIDDEN), false);
  assert.equal(loaded.inner.hideCodeInfo(parts.long) !== null, true, "блок подходит — просто выключено");
});

test("#7976: команда on — длинный swift свёрнут строкой «Код · 24 строки ▸» первым ребёнком блока", () => {
  const { loaded, parts } = page();
  on(loaded);
  assert.equal(loaded.win.localStorage.getItem(KEY), "1");
  assert.equal(loaded.document.documentElement.hasAttribute(ATTR), true);
  assert.deepEqual(status(loaded), { on: true, folded: 1, plans: 0 });
  const row = rowOf(parts.long);
  assert.ok(row, "строка внутри блока");
  assert.ok(parts.long.firstChild === row, "первым ребёнком: соседом в flex-теле дала бы лишний зазор");
  assert.equal(row.getAttribute(FOLD), "closed");
  assert.equal(row.getAttribute(LABEL), "Код · 24 строки ▸");
  assert.equal(row.getAttribute("role"), "button");
  assert.equal(row.getAttribute("tabindex"), "0");
  assert.equal(row.getAttribute("aria-expanded"), "false");
  assert.equal(row.getAttribute("aria-label"), "Код, 24 строки — развернуть");
  assert.equal(row.textContent, "", "подпись — в атрибуте: копия и выделение её не видят");
  assert.equal(parts.long.getAttribute(HIDDEN), "closed");
  // Повторная сверка ничего не двигает и не плодит строк.
  sync(loaded);
  assert.equal(rows(loaded).length, 1);
  assert.ok(rowOf(parts.long) === row);
  // Склонение: 21 строка, 25 строк.
  const one = codeBlock(parts.body, { text: lines(21) });
  const many = codeBlock(parts.body, { text: lines(25), lang: "typescript", rawLang: "ts" });
  sync(loaded);
  assert.equal(rowOf(one).getAttribute(LABEL), "Код · 21 строка ▸");
  assert.equal(rowOf(many).getAttribute(LABEL), "Код · 25 строк ▸");
});

test("#7976: граница — 6 строк видны, 7 свёрнуты; хвостовые пустые строки не в счёт", () => {
  const { loaded, parts } = page({ storage: { [KEY]: "1" } });
  const six = codeBlock(parts.body, { text: `${lines(6)}\n\n\n` });
  const seven = codeBlock(parts.body, { text: lines(7) });
  sync(loaded);
  assert.ok(!rowOf(six));
  assert.equal(six.hasAttribute(HIDDEN), false);
  assert.equal(rowOf(seven).getAttribute(LABEL), "Код · 7 строк ▸");
  assert.equal(status(loaded).folded, 2, "24 строки и 7");
});

test("#7976: не трогаются — без языка и «text», команды, блоки с кнопками, блок передачи, код под заголовком нажималок", () => {
  const { loaded, parts } = page({ storage: { [KEY]: "1" } });
  const body = parts.body;
  const plainText = codeBlock(body, { text: lines(12), lang: "text", rawLang: "" });
  const bare = codeBlock(body, { text: lines(12), lang: "", rawLang: "" });
  const bash = codeBlock(body, { text: lines(12, "echo step"), lang: "bash" });
  const zsh = codeBlock(body, { text: lines(9, "ls dir"), lang: "zsh" });
  const withNazh = codeBlock(body, { text: lines(12) });
  withNazh.add("button", { attrs: { "data-myclaude-nazh-button": "code" } });
  const withRun = codeBlock(body, { text: lines(12) });
  withRun.add("button", { attrs: { "data-myclaude-run": "" } });
  const beforeContinue = codeBlock(body, { text: lines(12), lang: "markdown" });
  body.insertBefore(loaded.dom.node("div"), beforeContinue.nextSibling).setAttribute("data-myclaude-continue", "");
  // Блок передачи «ОТКРОЙ НОВЫЙ ЧАТ» — с языком, кнопки 12к рядом ещё нет.
  const handoffBody = answerRow(parts.feed, 12);
  handoffBody.add("h2", { text: "🆕 ОТКРОЙ НОВЫЙ ЧАТ" });
  const handoff = codeBlock(handoffBody, { text: lines(30, "Шаг "), lang: "markdown" });
  // Код под «🔘 ВЫБОР» — инструкция Элвису, по устройству блока (метки 12с ещё не стоят).
  const pickBody = answerRow(parts.feed, 14);
  pickBody.add("h2", { text: "🔘 ВЫБОР" });
  const picked = codeBlock(pickBody, { text: lines(10), lang: "json" });
  pickBody.add("h2", { text: "Дальше" });
  const after = codeBlock(pickBody, { text: lines(10), lang: "json" });
  sync(loaded);
  for (const [name, block] of Object.entries({ plainText, bare, bash, zsh, withNazh, withRun, beforeContinue, handoff, picked })) {
    assert.ok(!rowOf(block), `${name}: свёрнут, а не должен`);
    assert.equal(block.hasAttribute(HIDDEN), false, name);
  }
  assert.ok(rowOf(after), "после следующего заголовка блок нажималок кончился — свёрнут");
  assert.equal(status(loaded).folded, 2, "24 строки и json после «Дальше»");
});

test("#7976: идущий ответ не свёрнут; метка потока снялась — свёрнут", () => {
  const { loaded, parts } = page({
    storage: { [KEY]: "1" },
    build: (feed, own) => {
      own.done = codeBlock(answerRow(feed, 1), { text: lines(20) });
      own.live = answerRow(feed, 2, { streaming: true });
      own.code = codeBlock(own.live, { text: lines(20) });
    },
  });
  assert.ok(rowOf(parts.done));
  assert.ok(!rowOf(parts.code), "ответ пишется — не трогаем");
  assert.equal(status(loaded).folded, 1);
  parts.live.row.setAttribute("data-perf-row-streaming", "false");
  sync(loaded);
  assert.ok(!rowOf(parts.code), "сообщение ещё пишется (data-is-streaming)");
  parts.live.message.setAttribute("data-is-streaming", "false");
  sync(loaded);
  assert.ok(rowOf(parts.code), "дописан — свёрнут");
  assert.equal(status(loaded).folded, 2);
});

test("#7976: меток потока нет вовсе — последний ответ не свёрнут, пока видна кнопка стопа", () => {
  const { loaded, parts } = page({
    storage: { [KEY]: "1" },
    build: (feed, own, dom) => {
      own.first = codeBlock(answerRow(feed, 1, { marks: false }), { text: lines(20) });
      own.last = codeBlock(answerRow(feed, 2, { marks: false }), { text: lines(20) });
      own.stop = dom.document.body.add("button", { attrs: { "data-testid": "code-prompt-stop" } });
    },
  });
  assert.ok(rowOf(parts.first), "прошлый ответ законченный");
  assert.ok(!rowOf(parts.last), "последний — ход идёт");
  parts.stop.remove();
  sync(loaded);
  assert.ok(rowOf(parts.last));
});

test("#7976: не трогаются — инструменты и их обвязка, сообщение человека, карточка разрешения, диалог, поле ввода", () => {
  const { loaded, parts } = page({
    storage: { [KEY]: "1" },
    build: (feed, own) => {
      const body = answerRow(feed, 1);
      own.tool = codeBlock(body.add("div", { attrs: { "data-cds": "TurnStatus", "data-state": "done", "data-tool-anchor": "t1" } }), { text: lines(20) });
      own.card = codeBlock(body.add("div", { class: "epitaxy-approval-card" }), { text: lines(20) });
      own.dialog = codeBlock(body.add("div", { attrs: { role: "dialog" } }), { text: lines(20) });
      own.human = codeBlock(feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "human" } })
        .add("div", { class: "epitaxy-user-turn" }), { text: lines(20) });
      own.field = codeBlock(own.block, { text: lines(20) });
      // Обвязка инструментов (список правок «Edited N files»): наша role=button там сломала бы отбор К-B1.
      own.omitted = codeBlock(body.add("div", { class: "contents", attrs: { "data-find-omitted": "" } }), { text: lines(20) });
    },
  });
  for (const name of ["tool", "card", "dialog", "human", "field", "omitted"]) assert.ok(!rowOf(parts[name]), name);
  assert.deepEqual(status(loaded), { on: true, folded: 0, plans: 0 });
});

test("#7976: нажатие, Enter, пробел раскрывают и сворачивают; Esc сворачивает; двойной щелчок — одно нажатие", () => {
  const { loaded, parts } = page({ storage: { [KEY]: "1" } });
  const row = rowOf(parts.long);
  const click = extra => loaded.dom.document.dispatchEvent({ type: "click", target: row, detail: 1, isTrusted: true, ...extra });
  const key = name => ({ defaultPrevented: !loaded.win.dispatchEvent({ type: "keydown", key: name, target: row, cancelable: true }) });
  click();
  assert.equal(row.getAttribute(FOLD), "open");
  assert.equal(row.getAttribute(LABEL), "Код · 24 строки ▾");
  assert.equal(row.getAttribute("aria-expanded"), "true");
  assert.equal(row.getAttribute("aria-label"), "Код, 24 строки — свернуть");
  assert.equal(parts.long.getAttribute(HIDDEN), "open");
  assert.deepEqual(status(loaded), { on: true, folded: 0, plans: 0 }, "раскрытый — не свёрнут");
  click({ detail: 2 });
  assert.equal(row.getAttribute(FOLD), "open", "второй щелчок двойного — не нажатие");
  click();
  assert.equal(row.getAttribute(FOLD), "closed");
  assert.equal(key("Enter").defaultPrevented, true);
  assert.equal(row.getAttribute(FOLD), "open");
  key(" ");
  assert.equal(row.getAttribute(FOLD), "closed");
  key("Escape");
  assert.equal(row.getAttribute(FOLD), "closed", "Esc на свёрнутой ничего не раскрывает (дальше его судит сторож Esc)");
  key("Enter");
  assert.equal(key("Escape").defaultPrevented, true);
  assert.equal(row.getAttribute(FOLD), "closed", "Esc на раскрытой — свернуть");
  // Раскрытое помнится по тексту: лента пересоздала узел — тот же текст остаётся раскрытым.
  click();
  parts.long.remove();
  const again = codeBlock(parts.body, { text: `${lines(24)}\n` });
  sync(loaded);
  assert.equal(rowOf(again).getAttribute(FOLD), "open");
  assert.equal(rows(loaded).length, 1, "строка ушедшего узла снята");
});

test("#7976: innerText ленты тот же — до включения, свёрнутым и раскрытым; правило без display:none и visibility", () => {
  const { loaded, parts } = page();
  const before = parts.feed.innerText;
  assert.ok(before.includes("value23 = 23"));
  on(loaded);
  assert.equal(parts.feed.innerText, before, "свёрнут");
  loaded.dom.document.dispatchEvent({ type: "click", target: rowOf(parts.long), detail: 1, isTrusted: true });
  assert.equal(parts.feed.innerText, before, "раскрыт");
  const text = css(loaded);
  const rule = text.split("\n").find(item => item.includes(`[${HIDDEN}="closed"]>:not([${FOLD}])`));
  assert.ok(rule, "правило прятания в стиле страницы");
  assert.match(rule, /^html\[data-myclaude-hide-code\] /, "только при включённой настройке");
  for (const part of ["height:0 !important", "opacity:0 !important", "overflow:hidden !important", "pointer-events:none !important", "contain:paint !important"]) {
    assert.ok(rule.includes(part), part);
  }
  assert.ok(!/display:none|visibility/.test(rule), "innerText не должен терять код");
  assert.ok(text.includes(`[${FOLD}]::after{content:attr(${LABEL})}`));
  assert.ok(text.includes(`[${HIDDEN}="closed"]>.contents:not([${FOLD}]){display:block !important}`), "обёртка contents — блоком, иначе высота 0 её не прячет");
  assert.ok(![...loaded.inner.RULES].some(item => item.includes(FOLD)), "правила — в lateRules, не в RULES раздела 4");
});

test("#7976: off и мусор в on — строк, меток и атрибута нет, без перезагрузки", () => {
  const { loaded, parts } = page({ storage: { [KEY]: "1" } });
  assert.equal(rows(loaded).length, 1);
  loaded.dom.command({ action: "hide-code", on: "false" });
  assert.equal(loaded.win.localStorage.getItem(KEY), "0");
  assert.equal(rows(loaded).length, 0);
  assert.equal(parts.long.hasAttribute(HIDDEN), false);
  assert.equal(loaded.document.documentElement.hasAttribute(ATTR), false);
  assert.deepEqual(status(loaded), { on: false, folded: 0, plans: 0 });
  on(loaded);
  assert.equal(rows(loaded).length, 1);
  loaded.dom.command({ action: "hide-code", on: "да" });
  assert.equal(rows(loaded).length, 0, "не \"true\" — выключено");
  assert.equal(loaded.document.documentElement.hasAttribute(ATTR), false);
});

test("#7976: storage из соседнего окна включает и выключает; ключ null (очистка) — перечитать", () => {
  const { loaded } = page();
  loaded.win.localStorage.setItem(KEY, "1");
  loaded.win.dispatchEvent({ type: "storage", key: KEY });
  assert.equal(rows(loaded).length, 1);
  assert.equal(loaded.document.documentElement.hasAttribute(ATTR), true);
  loaded.win.localStorage.removeItem(KEY);
  loaded.win.dispatchEvent({ type: "storage", key: null });
  assert.equal(rows(loaded).length, 0);
  assert.equal(loaded.document.documentElement.hasAttribute(ATTR), false);
  loaded.win.localStorage.setItem("myclaude.other", "1");
  loaded.win.localStorage.setItem(KEY, "1");
  loaded.win.dispatchEvent({ type: "storage", key: "myclaude.other" });
  assert.equal(rows(loaded).length, 0, "чужой ключ — не наш повод");
});

test("#7976: dispose снимает всё; повторная установка ставит свёртки по ключу и снимает сирот", () => {
  const { loaded, parts } = page({ storage: { [KEY]: "1" } });
  assert.equal(rows(loaded).length, 1);
  loaded.api.dispose();
  assert.equal(rows(loaded).length, 0);
  assert.equal(parts.long.hasAttribute(HIDDEN), false);
  assert.equal(loaded.document.documentElement.hasAttribute(ATTR), false);
  const again = loaded.reload();
  assert.equal(again.error, null, String(again.error?.stack ?? again.error));
  assert.equal(rows(loaded).length, 1);
  assert.equal(rowOf(parts.long).getAttribute(FOLD), "closed");
  // Сирота прошлой установки (её экземпляр умер без dispose): строка и метка уходят, ставится своя.
  const stray = loaded.dom.node("div");
  stray.setAttribute(FOLD, "closed");
  parts.body.appendChild(stray);
  const third = loaded.reload();
  assert.equal(third.error, null, String(third.error?.stack ?? third.error));
  assert.equal(stray.isConnected, false);
  assert.equal(rows(loaded).length, 1);
});

// Отбор записей наблюдателя (разбор критика, п. 4): полный проход — только когда могло появиться или уйти то, что
// сворачиваем; свои вставки и токены идущего ответа его не будят.
test("#7976: отбор наблюдателя — свои строки и правки идущего ответа мимо; блок кода, метка потока, карточка — проход", () => {
  const { loaded, parts } = page({
    storage: { [KEY]: "1" },
    build: (feed, own, dom) => {
      own.body = answerRow(feed, 1);
      own.long = codeBlock(own.body, { text: lines(20) });
      own.doneText = dom.leaf(own.long.querySelector("pre"), "span", "x").firstChild;
      own.live = answerRow(feed, 2, { streaming: true });
      own.liveCode = codeBlock(own.live, { text: lines(20) });
      own.liveText = dom.leaf(own.liveCode.querySelector("pre"), "span", "y").firstChild;
    },
  });
  const needs = records => loaded.inner.hideCodeNeeds(records);
  const childList = (target, added = [], removed = []) => ({ type: "childList", target, addedNodes: added, removedNodes: removed });
  assert.equal(needs([childList(parts.long, [rowOf(parts.long)])]), false, "своя строка");
  assert.equal(needs([{ type: "characterData", target: parts.liveText }]), false, "токен идущего ответа");
  assert.equal(needs([childList(parts.live, [loaded.dom.node("p")])]), false, "абзац идущего ответа");
  assert.equal(needs([childList(parts.body, [loaded.dom.node("p")])]), false, "обычный абзац законченного ответа");
  assert.equal(needs([{ type: "characterData", target: parts.doneText }]), true, "правка внутри законченного блока");
  assert.equal(needs([{ type: "attributes", target: parts.live.message, attributeName: "data-is-streaming" }]), true, "метка потока");
  const block = loaded.dom.node("div");
  block.className = "epitaxy-codeblock";
  assert.equal(needs([childList(parts.body, [block])]), true, "новый блок кода");
  assert.equal(needs([childList(parts.body, [], [parts.long])]), true, "ушёл блок кода");
  const card = loaded.dom.node("div");
  card.className = "epitaxy-approval-card";
  assert.equal(needs([childList(parts.block, [], [card])]), true, "ушла карточка разрешения");
});

// Совместная работа (разбор критика, п. 6): включены «Прятать инструменты» (К-B1), «Чистые ответы» (К-CA) и
// «Прятать код» — инструменты и служебный хвост спрятаны, как были; наших строк в группе инструментов нет.
test("#7976: вместе с hide-tools и clean-answers — каждый прячет своё, друг другу не мешают", () => {
  const { loaded, parts } = page({
    build: (feed, own) => {
      const body = answerRow(feed, 1);
      own.group = body.add("div", { attrs: { "data-cds": "TurnStatus", "data-tool-anchor": "toolu_1", "data-find-omitted": "", "data-state": "done", "data-item-key": "a:grp" } });
      own.group.add("div", { attrs: { "data-cds-row": "" } }).add("bdi", { text: "Ran 2 commands" });
      const prose = body.add("div", { attrs: { "data-cds": "Prose" } });
      prose.add("p", { text: "Сделал." });
      own.code = codeBlock(prose, { text: lines(20) });
      own.tail = prose.add("p", { text: "Контекст 226K" });
    },
  });
  loaded.dom.command({ action: "hide-tools", on: "true" });
  loaded.dom.command({ action: "clean-answers", on: "true" });
  on(loaded);
  // Свои вставки в бою будят чужие наблюдатели; в стабе зовём их сверки сами.
  loaded.inner.cleanAnswersSync();
  assert.equal(parts.group.hasAttribute("data-myclaude-tool-done"), true, "законченная группа спрятана");
  assert.ok(!parts.group.querySelector(`[${FOLD}]`));
  assert.equal(plain(loaded.api.status().hideTools).hidden, 1);
  assert.equal(parts.tail.hasAttribute("data-myclaude-clean-line"), true, "служебный хвост спрятан");
  assert.ok(rowOf(parts.code), "код свёрнут");
  assert.deepEqual(status(loaded), { on: true, folded: 1, plans: 0 });
});

// ---- Планы ------------------------------------------------------------------------------------------------------
// Замера разметки карточки плана нет (probe.js исполнителю запрещён). По коду Claude (бандл 19.10) инструмент плана —
// {id, name:"ExitPlanMode", input:{plan, planFilePath}, status}; узел ленты получает его пропсом. Эталон ниже — карточка
// [data-cds="Card"] в теле ответа, пропс tool у её компонента; живьём проверяет оркестратор (status().hideCode.plans).
const PLAN = "# План переезда\n\n1. Снять копию базы\n2. Перенести файлы\n3. Проверить сайт\n";
const planCard = (parent, { plan = PLAN, status = "completed", id = "toolu_plan1", where = "tool" } = {}) => {
  const card = parent.add("div", { class: "rounded-lg border", attrs: { "data-cds": "Card" } });
  const tool = { id, name: "ExitPlanMode", input: { plan, planFilePath: "/Users/x/.claude/plans/plan.md" }, status };
  card["__reactFiber$test"] = { memoizedProps: { className: "rounded-lg" }, stateNode: card,
    return: { memoizedProps: { [where]: tool }, stateNode: null, return: { memoizedProps: {}, stateNode: parent, return: null } } };
  card.add("h1", { text: "План переезда" });
  const list = card.add("ol");
  for (const item of ["Снять копию базы", "Перенести файлы", "Проверить сайт"]) list.add("li", { text: item });
  card.tool = tool;
  return card;
};

test("#7976 планы: карточка законченного плана свёрнута «План · 3 пункта ▸», код внутри — не отдельно", () => {
  const { loaded, parts } = page({
    storage: { [KEY]: "1" },
    build: (feed, own) => {
      own.body = answerRow(feed, 1);
      own.card = planCard(own.body);
      own.inner = codeBlock(own.card, { text: lines(20) });
      own.after = answerRow(feed, 2);
      own.after.add("p", { text: "Начинаю." });
    },
  });
  const row = rowOf(parts.card);
  assert.ok(row, "план свёрнут");
  assert.ok(parts.card.firstChild === row);
  assert.equal(row.getAttribute(LABEL), "План · 3 пункта ▸");
  assert.equal(row.getAttribute("aria-label"), "План, 3 пункта — развернуть");
  assert.equal(parts.card.getAttribute(HIDDEN), "closed");
  assert.ok(!rowOf(parts.inner), "код внутри свёрнутого плана отдельной строкой не сворачивается");
  assert.deepEqual(status(loaded), { on: true, folded: 0, plans: 1 });
  loaded.dom.document.dispatchEvent({ type: "click", target: row, detail: 1, isTrusted: true });
  assert.equal(row.getAttribute(LABEL), "План · 3 пункта ▾");
  assert.deepEqual(status(loaded), { on: true, folded: 0, plans: 0 });
});

test("#7976 планы: ждёт одобрения — не свёрнут (статус инструмента, карточка разрешения у поля); одобрен — свёрнут", () => {
  const { loaded, parts } = page({
    storage: { [KEY]: "1" },
    build: (feed, own) => {
      own.body = answerRow(feed, 1);
      own.card = planCard(own.body, { status: "awaiting_approval" });
      own.approval = own.block.add("div", { class: "epitaxy-approval-card" });
    },
  });
  assert.ok(!rowOf(parts.card), "awaiting_approval");
  parts.card.tool.status = "completed";
  sync(loaded);
  assert.ok(!rowOf(parts.card), "у поля карточка разрешения, план — в последнем ответе");
  parts.approval.remove();
  sync(loaded);
  assert.ok(rowOf(parts.card), "одобрен — свёрнут");
  assert.equal(status(loaded).plans, 1);
});

test("#7976 планы: внутри решение, в группе инструментов, у соседа, в идущем ответе — не трогаем", () => {
  const { loaded, parts } = page({
    storage: { [KEY]: "1" },
    build: (feed, own) => {
      const body = answerRow(feed, 1);
      own.decision = planCard(body, { id: "p1" });
      own.decision.add("textarea");
      own.grouped = planCard(body.add("div", { attrs: { "data-cds": "TurnStatus", "data-state": "done", "data-tool-anchor": "p2" } }), { id: "p2" });
      // Пропс плана — у компонента-родителя тела, а не у самой карточки: это пропсы соседей, не её.
      own.stranger = body.add("div", { attrs: { "data-cds": "Card" } });
      own.stranger["__reactFiber$test"] = { memoizedProps: {}, stateNode: own.stranger, return: { memoizedProps: {}, stateNode: body,
        return: { memoizedProps: { tool: { name: "ExitPlanMode", input: { plan: PLAN }, status: "completed" } }, stateNode: null, return: null } } };
      own.live = planCard(answerRow(feed, 2, { streaming: true }), { id: "p3" });
      own.empty = planCard(answerRow(feed, 3), { id: "p4", plan: "   " });
    },
  });
  for (const name of ["decision", "grouped", "stranger", "live", "empty"]) assert.ok(!rowOf(parts[name]), name);
  assert.deepEqual(status(loaded), { on: true, folded: 0, plans: 0 });
});

test("#7976 планы: пункты — списки верхнего уровня; без них — заголовки без названия; ничего — «План ▸»", () => {
  const { loaded, parts } = page({
    storage: { [KEY]: "1" },
    build: (feed, own) => {
      const body = answerRow(feed, 1);
      own.heads = planCard(body, { id: "h", where: "item", plan: "# Handoff Plan\n\n## Сайт\nтекст\n## Бот\n```md\n- не пункт\n```\n" });
      own.nested = planCard(body, { id: "n", plan: "- один\n  - вложенный\n- два\n" });
      own.prose = planCard(body, { id: "t", plan: "Просто текст плана без пунктов." });
    },
  });
  assert.equal(rowOf(parts.heads).getAttribute(LABEL), "План · 2 пункта ▸", "пропс item, заголовки без названия");
  assert.equal(rowOf(parts.nested).getAttribute(LABEL), "План · 2 пункта ▸", "вложенный пункт не в счёт");
  assert.equal(rowOf(parts.prose).getAttribute(LABEL), "План ▸");
  assert.equal(rowOf(parts.prose).getAttribute("aria-label"), "План — развернуть");
  assert.equal(status(loaded).plans, 3);
});
