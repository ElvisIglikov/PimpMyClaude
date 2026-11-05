// #9859 «Ответы в окне Claude сразу свёрнутыми — без мигания развёрнутыми». Свёртки ставил тик
// сердца (до HEARTBEAT_MS после мутации), и кадр-другой новый ход был виден развёрнутым. Теперь
// разметка — в колбэке наблюдателя (микрозадача, до отрисовки): стенд отдаёт записи мутаций всем
// живым наблюдателям страницы ровно так, как это сделал бы браузер, а «кадр» — это rAF/таймер стенда.
// Замер «был ли видимый кадр развёрнутым»: после записей и до первого кадра узел уже спрятан.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const HEAD = "data-myclaude-fold-head";
const LABEL = "data-myclaude-fold-label";
const RAW = "data-myclaude-fold-raw";
const BODY = "data-myclaude-fold-body";
const WHOLE = "data-myclaude-fold-whole";
const LONG = "data-myclaude-fold-long";
const BLOCK = "data-myclaude-composer-block";

const page = ({ height = 300, streaming = false, collapsedStage = false } = {}) => {
  const observers = [];
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_fold-9859", title: "Rick",
    ...(collapsedStage ? { storage: { session: { "myclaude-input-stage-v1": "0" } } } : {}),
    html: dom => {
      const Observer = dom.window.MutationObserver;
      dom.window.MutationObserver = class extends Observer {
        constructor(callback) { super(callback); observers.push(this); }
      };
      const parts = dom.composer({ text: "" });
      parts.chip = dom.node("div");
      parts.chip.className = "project-chip";
      parts.block.insertBefore(parts.chip, parts.shell);
      parts.feed = dom.document.body.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript" },
        rect: { left: 0, top: 0, width: 1200, height: 500 },
      });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  // Записи мутаций — всем живым наблюдателям (как микрозадача браузера: до кадра).
  const deliver = records => { for (const observer of observers) if (observer.live) observer.fn(records); };
  const added = (target, nodes) => deliver([{ type: "childList", target, addedNodes: nodes, removedNodes: [] }]);
  // Новый ход ленты: строка ответа, контейнер, блоки — и одна запись о вставке строки.
  const answer = (build, { rowHeight = height, live = streaming } = {}) => {
    const row = loaded.dom.node("div");
    row.setAttribute("data-testid", "transcript-row");
    row.setAttribute("data-perf-row", "assistant_text");
    if (live) row.setAttribute("data-is-streaming", "true");
    row.rect = { left: 0, top: 0, width: 800, height: rowHeight };
    const box = row.add("div", { class: "contents" });
    const nodes = build(box);
    loaded.parts.feed.appendChild(row);
    added(loaded.parts.feed, [row]);
    return { row, box, nodes };
  };
  // Узел виден, если ни он, ни предок не спрятан правилом свёрток (раздел 4).
  const shown = node => {
    for (let item = node; item; item = item.parentElement) {
      if (item.hasAttribute?.(RAW) || item.getAttribute?.(BODY) === "closed" || item.getAttribute?.(LONG) === "closed") return false;
    }
    return true;
  };
  // Кадры: сколько из них показали узел развёрнутым (rAF и таймеры стенда, затем тик сердца).
  const framesShown = (nodes, frames = 3) => {
    let seen = 0;
    for (let frame = 0; frame < frames; frame += 1) {
      if (nodes.some(shown)) seen += 1;
      loaded.dom.fireKind("raf");
      loaded.dom.fireKind("timeout");
      loaded.dom.fireKind("interval");
    }
    return seen;
  };
  return { loaded, deliver, added, answer, shown, framesShown };
};
const fold = (box, title = "Подробно") => ({
  lead: box.add("p", { text: "Коротко: готово." }),
  open: box.add("p", { text: `<details><summary>${title}</summary>` }),
  body: box.add("p", { text: "Тело свёртки, которого не должно быть видно." }),
  list: box.add("ul", { text: "пункт" }),
  close: box.add("p", { text: "</details>" }),
});

test("#9859: новый ход со свёрткой спрятан до первого кадра — ни один кадр не развёрнут", () => {
  const { answer, framesShown, shown, loaded } = page();
  const { nodes } = answer(fold);
  assert.equal(framesShown([nodes.body, nodes.list, nodes.open, nodes.close]), 0, "ни одного кадра развёрнутым");
  assert.equal(shown(nodes.lead), true, "текст до свёртки виден");
  const head = nodes.open.previousElementSibling;
  assert.equal(head.getAttribute(HEAD), "closed");
  assert.equal(head.getAttribute(LABEL), "▸ Подробно");
  assert.equal(loaded.api.status().folds.count, 1);
});

test("#9859: замер ловит мигание — без записей мутаций (старый путь, только тик) первый кадр развёрнут", () => {
  const { loaded, framesShown } = page();
  const row = loaded.parts.feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" }, rect: { left: 0, top: 0, width: 800, height: 300 } });
  const nodes = fold(row.add("div", { class: "contents" }));
  assert.ok(framesShown([nodes.body], 1) >= 1, "без разметки до кадра тело видно — замер не слепой");
});

test("#9859: ответ пишется — свёртка без закрывающего встаёт сразу и прячет всё после тега; закрылся — та же свёртка", () => {
  const { answer, added, deliver, framesShown, shown, loaded } = page({ streaming: true });
  const { row, box, nodes } = answer(b => ({
    lead: b.add("p", { text: "Начало ответа." }),
    open: b.add("p", { text: "<details><summary>Пишется</summary>" }),
    body: b.add("p", { text: "первая строка тела" }),
  }));
  assert.equal(framesShown([nodes.body]), 0, "тело, что пишется, не мелькает");
  assert.equal(shown(nodes.lead), true);
  const head = nodes.open.previousElementSibling;
  assert.equal(head.getAttribute(HEAD), "closed");
  // Пришёл новый абзац тела — спрятан той же микрозадачей.
  const more = box.add("p", { text: "вторая строка тела" });
  added(box, [more]);
  assert.equal(framesShown([more]), 0, "новый абзац тела не мелькает");
  // Элвис раскрыл свёртку, пока ответ пишется: тело дописывается — выбор держится.
  loaded.dom.document.dispatchEvent({ type: "click", target: head, detail: 1, isTrusted: true });
  assert.equal(nodes.body.getAttribute(BODY), "open");
  const third = box.add("p", { text: "третья строка — ключ свёртки по началу тела сменился бы" });
  nodes.body.__text = "первая строка тела, дописанная до восьмидесяти знаков и дальше, чтобы ключ точно сменился";
  added(box, [third]);
  assert.equal(nodes.body.getAttribute(BODY), "open", "раскрытая не схлопнулась от дописанного тела");
  assert.equal(third.getAttribute(BODY), "open");
  loaded.dom.document.dispatchEvent({ type: "click", target: head, detail: 1, isTrusted: true });
  // Закрывающий тег и хвост после него.
  const close = box.add("p", { text: "</details>" });
  const tail = box.add("p", { text: "Дальше — видно." });
  added(box, [close, tail]);
  assert.equal(shown(close), false);
  assert.equal(framesShown([tail], 1), 1, "хвост после свёртки виден сразу");
  assert.equal(nodes.body.getAttribute(BODY), "closed");
  // Ответ дописан: метка Claude снялась — разметка та же (пара есть).
  row.removeAttribute("data-is-streaming");
  deliver([{ type: "attributes", target: row, attributeName: "data-is-streaming" }]);
  assert.equal(nodes.body.getAttribute(BODY), "closed");
  assert.equal(loaded.dom.queryAll(`[${HEAD}]`).length, 1, "заголовок один, не продублирован");
});

test("#9859: ответ дописан без закрывающего — тег без пары, свёртка снимается (контракт 12ф)", () => {
  const { answer, deliver, shown, loaded } = page({ streaming: true });
  const { row, nodes } = answer(b => ({
    open: b.add("p", { text: "<details>" }),
    body: b.add("p", { text: "тело без пары" }),
  }));
  assert.equal(shown(nodes.body), false);
  row.removeAttribute("data-is-streaming");
  deliver([{ type: "attributes", target: row, attributeName: "data-is-streaming" }]);
  assert.equal(shown(nodes.body), true);
  assert.equal(shown(nodes.open), true);
  assert.equal(loaded.dom.queryAll(`[${HEAD}]`).length, 0);
});

test("#9859: текст абзаца стал тегом (печать по буквам) — свёртка встаёт той же микрозадачей", () => {
  const { answer, deliver, shown } = page({ streaming: true });
  const { nodes } = answer(b => ({
    open: b.add("p", { text: "<det" }),
    body: b.add("p", { text: "тело" }),
  }));
  assert.equal(shown(nodes.body), true, "пока это не тег — не трогаем");
  nodes.open.__text = "<details><summary>Готово</summary>";
  deliver([{ type: "characterData", target: nodes.open.firstChild ?? nodes.open }]);
  assert.equal(shown(nodes.body), false);
});

test("#9859: свёрнутый Элвисом ответ пересоздан лентой — спрятан до первого кадра", () => {
  const { loaded, answer, framesShown, added } = page({ height: 1700 });
  const first = answer(b => ({
    first: b.add("p", { text: "Первый абзац длинного ответа." }),
    second: b.add("p", { text: "Второй." }),
    last: b.add("p", { text: "Конец." }),
  }));
  // Кнопка «Свернуть ответ» — это добавление, не свёртка: её ставит тик, как раньше.
  loaded.inner.foldTick();
  const whole = loaded.dom.queryAll(`[${WHOLE}]`)[0];
  assert.ok(whole, "кнопка «Свернуть ответ» встала");
  loaded.dom.document.dispatchEvent({ type: "click", target: whole, detail: 1, isTrusted: true });
  assert.equal(first.nodes.second.getAttribute(LONG), "closed");
  // Лента виртуальная: строка ушла и пришла новыми узлами.
  first.row.remove();
  added(loaded.parts.feed, []);
  const again = answer(b => ({
    first: b.add("p", { text: "Первый абзац длинного ответа." }),
    second: b.add("p", { text: "Второй." }),
    last: b.add("p", { text: "Конец." }),
  }));
  assert.equal(framesShown([again.nodes.second, again.nodes.last]), 0, "свёрнутый ответ не мелькнул развёрнутым");
});

test("#9859: обычный ход без свёрток — отбор не зовёт разметку (дешёвый путь)", () => {
  const { loaded } = page();
  const box = loaded.parts.feed.add("div", { class: "contents" });
  const para = box.add("p", { text: "просто текст" });
  assert.equal(loaded.inner.foldNeeds([{ type: "childList", target: box, addedNodes: [para], removedNodes: [] }]), false);
  assert.equal(loaded.inner.foldNeeds([{ type: "characterData", target: para }]), false);
  assert.equal(loaded.inner.foldNeeds([{ type: "attributes", target: box, attributeName: "data-is-streaming" }]), false, "свёрток, что пишутся, нет");
});

test("#9859: свёрнутое поле — новый узел над строкой модели спрятан до раскладки, ниже неё и кружок — раскладке", () => {
  const { loaded, added, framesShown } = page({ collapsedStage: true });
  assert.equal(loaded.api.status().stage, 0, "окно поднялось свёрнутым");
  const { block, modelRow, shell } = loaded.parts;
  assert.equal(modelRow.getAttribute(BLOCK), "collapsed");
  // React вставил строку над рамкой (вложения, плашка) — раскладка ещё не прошла.
  const strip = loaded.dom.node("div");
  block.insertBefore(strip, shell);
  const below = loaded.dom.node("div");
  block.appendChild(below);
  const ring = loaded.dom.node("div");
  block.insertBefore(ring, modelRow);
  ring.add("button", { attrs: { "aria-haspopup": "dialog", "aria-label": "Usage: 40%" } });
  added(block, [strip, below, ring]);
  assert.equal(strip.getAttribute(BLOCK), "collapsed", "над строкой модели — спрятан сразу");
  assert.equal(below.getAttribute(BLOCK), null, "ниже строки модели не трогаем");
  assert.equal(ring.getAttribute(BLOCK), null, "ветка с кружком — своим видом, её ставит раскладка");
  const shownStrip = framesShown([strip].filter(node => node.getAttribute(BLOCK) !== "collapsed"), 1);
  assert.equal(shownStrip, 0);
  // Новая шапка окна (смена чата) — тоже до кадра.
  const bar = loaded.dom.document.body.add("div", { class: "epitaxy-titlebar" });
  added(loaded.dom.document.body, [bar]);
  assert.equal(bar.getAttribute(BLOCK), "collapsed");
  // Развернули — сняты все, и подставленные до раскладки.
  loaded.api.setStage(1);
  for (const node of [strip, bar, shell, modelRow]) assert.equal(node.getAttribute(BLOCK), null);
  // Обычная ступень: вставки не трогаем.
  const late = loaded.dom.node("div");
  block.insertBefore(late, shell);
  added(block, [late]);
  assert.equal(late.getAttribute(BLOCK), null);
});
