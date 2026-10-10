// WF97, батч Б5p (страница; #7772). Слово Элвиса 26.09 ~05:00: «риск, что
// пользователь несколько раз нажмёт… где написано „зову Пимпа“ — поярче, чтоб
// люди поняли, что работа идёт… чтобы буквы переливались цветами… ничего не
// делать при повторном нажатии… у нас везде должны быть такие ощущения».
//
// Правило волны 3: второе и следующие нажатия, пока действие идёт, — без
// последствий; идущее действие видно на самой кнопке. Здесь:
//   1) «ОТКРОЙ НОВЫЙ ЧАТ» и «💬 Новый чат» — «занято» (data-myclaude-busy) и
//      aria-disabled сразу с нажатия, все ⏳/✓; повторы не открывают второй чат;
//      двойной клик (выделение) — «занято» снято, подпись прежняя;
//   2) стили: с WF98 (#7852, «дискотеку убери… просто ссылочку») ссылка и кнопка
//      без перелива; бегущий градиент — только у плашки «Новое окно»,
//      «уменьшить движение» — и там без него, приглушённо;
//   3) «▦ Галерея», слово «Скажи — и сделаю» — двойной клик = одно нажатие;
//   4) карточка .html и пункт «Открыть в браузере» — тот же файл дважды за
//      HTML_CHROME_REPEAT_MS — одна вкладка;
//   5) фото: второй клик двойного по фото в ленте (уже в слое) не закрывает и не
//      увеличивает просмотр;
//   6) «Новое окно», пока идёт первое, — плашка «⏳ Уже открываю окно…» с переливом.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { loadInject, plain } from "./load.mjs";

const BUSY = "data-myclaude-busy";
const HANDOFF = JSON.parse(readFileSync(new URL("./fixtures/cashout/record-handoff.json", import.meta.url), "utf8")).text;
const PREFIX = "Пимп: продолжить в новом чате · ";

// ---- 1. «ОТКРОЙ НОВЫЙ ЧАТ» и «💬 Новый чат» ---------------------------------

const chatPage = () => {
  const heads = [];
  const loaded = loadInject({
    href: "about:blank", title: "VkusnoffKz 2", hasFocus: false,
    html: dom => {
      const parts = dom.composer();
      const answer = dom.document.body.add("div", { attrs: { "data-testid": "assistant-message" }, rect: { left: 0, top: 100, width: 800, height: 100 } });
      heads.push(answer.add("h2", { text: "🆕 ОТКРОЙ НОВЫЙ ЧАТ" }));
      const block = answer.add("div", { class: "epitaxy-codeblock relative" });
      block.add("div", { class: "relative" }).add("div", { attrs: { "data-code-text": HANDOFF }, text: HANDOFF });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  // База заморожена (z8-r01): часы страницы двигает только тест, иначе
  // настоящее время под нагрузкой утекало бы в отсчёт.
  const base = loaded.win.performance.now();
  let shift = 500;
  loaded.win.performance.now = () => base + shift;
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
  return { loaded, head: heads[0], later: ms => { shift += ms; } };
};
const click = (loaded, target, extra = {}) =>
  loaded.document.dispatchEvent({ type: "click", isTrusted: true, target, bubbles: true, button: 0, detail: 1, ...extra });
const button = loaded => loaded.dom.query("[data-myclaude-continue] button");
const lastTimer = loaded => { const ids = loaded.dom.ids("timeout"); loaded.dom.fire(ids[ids.length - 1]); };
const ack = loaded => loaded.dom.command({ id: "c1", action: "cashout", at: "now", scope: "window", title: "VkusnoffKz 2", handoff: true });
const busy = node => [node.getAttribute(BUSY), node.getAttribute("aria-disabled")];

test("#7772: клик по «ОТКРОЙ НОВЫЙ ЧАТ» — «занято» и запрет сразу, а не через полсекунды", () => {
  const { loaded, head } = chatPage();
  assert.deepEqual(busy(head), [null, null], "до нажатия ссылка живая");
  click(loaded, head);
  assert.deepEqual(busy(head), ["1", "true"], "нажатие не видно сразу");
  assert.equal(head.getAttribute("data-myclaude-continue-state"), "wait");
  assert.equal(button(loaded).getAttribute("data-myclaude-continue-label"), "⏳ Зову Пимпа…");
  assert.deepEqual(busy(button(loaded)), ["1", "true"], "кнопка под блоком не занята");
  // Второй и третий одиночный клик, пока ждём, — ничего нового.
  click(loaded, head);
  click(loaded, button(loaded));
  lastTimer(loaded);
  assert.equal(loaded.api.status().continue.clicks, 1, "второй чат");
  assert.ok(String(loaded.document.title).startsWith(PREFIX));
  click(loaded, head);
  click(loaded, button(loaded));
  assert.equal(loaded.api.status().continue.clicks, 1, "повтор во время «⏳» открыл второй чат");
  assert.deepEqual(busy(head), ["1", "true"]);
});

test("#7772: «✓ Открываю новый чат…» — тоже занято; дождались конца — ссылка снова живая", () => {
  const { loaded, head } = chatPage();
  click(loaded, head);
  lastTimer(loaded);
  ack(loaded);
  assert.equal(head.getAttribute("data-myclaude-continue-state"), "ack");
  assert.deepEqual(busy(head), ["1", "true"], "во время «✓» ссылка не занята");
  assert.deepEqual(busy(button(loaded)), ["1", "true"]);
  click(loaded, head);
  loaded.dom.fireKind("timeout");
  assert.equal(loaded.api.status().continue.clicks, 1, "повтор во время «✓» открыл второй чат");
  for (let round = 0; round < 50 && loaded.dom.ids("timeout").length; round += 1) loaded.dom.fireKind("timeout");
  assert.deepEqual(busy(head), [null, null], "после «✓» ссылка осталась занятой");
  assert.deepEqual(busy(button(loaded)), [null, null]);
  assert.equal(button(loaded).getAttribute("data-myclaude-continue-label"), "💬 Новый чат");
});

test("#7772: Пимп молчит — «занято» снято, ссылку можно нажать снова", () => {
  const { loaded, head } = chatPage();
  click(loaded, head);
  lastTimer(loaded);
  for (let round = 0; round < 50 && loaded.dom.ids("timeout").length; round += 1) loaded.dom.fireKind("timeout");
  assert.equal(loaded.api.status().continue.silent, 1);
  assert.deepEqual(busy(head), [null, null]);
  click(loaded, head);
  lastTimer(loaded);
  assert.equal(loaded.api.status().continue.clicks, 2, "после тишины ссылка не нажимается");
});

test("#7772: двойной клик по ссылке — выделение: «занято» сразу снято, чат не открыт", () => {
  const { loaded, head } = chatPage();
  click(loaded, head);
  assert.equal(head.getAttribute(BUSY), "1");
  click(loaded, head, { detail: 2 });
  assert.deepEqual(busy(head), [null, null], "после двойного клика ссылка «занята»");
  assert.equal(button(loaded).getAttribute("data-myclaude-continue-label"), "💬 Новый чат");
  loaded.dom.fireKind("timeout");
  assert.equal(loaded.api.status().continue.clicks, 0);
});

test("#7772: dispose снимает «занято» с заголовка Claude", () => {
  const { loaded, head } = chatPage();
  click(loaded, head);
  loaded.api.dispose();
  assert.deepEqual(busy(head), [null, null]);
});

// ---- 2. Стили: ссылка простая, перелив — только у плашки ---------------------

test("#7865: ждём Пимпа — блик по буквам, кружок вместо ⏳, кнопка наливается; радуги больше нет", () => {
  const { loaded } = chatPage();
  const css = loaded.dom.queryAll("style").map(style => style.textContent).join("\n");
  assert.doesNotMatch(css, /myclaude-busy-flow|#e05bd0/, "радужный перелив остался");
  assert.match(css, /@keyframes myclaude-shim\{/);
  assert.match(css, /@keyframes myclaude-spin\{/);
  assert.match(css, /@keyframes myclaude-fill\{from\{background-size:0% 100%\}to\{background-size:88% 100%\}\}/);
  // Ссылка: копия текста поверх с бегущей полосой, в конце — кружок; «✓» — ровно.
  assert.match(css, /\[data-myclaude-continue-link\]\[data-myclaude-continue-state="wait"\]::before\{content:attr\(data-myclaude-continue-text\);[^}]*background-clip:text;[^}]*animation:myclaude-shim /);
  assert.match(css, /\[data-myclaude-continue-link\]\[data-myclaude-continue-state="wait"\]::after\{content:"";[^}]*border-radius:50%;[^}]*animation:myclaude-spin /);
  assert.match(css, /\[data-myclaude-continue-link\]\[data-myclaude-continue-state="ack"\]::after\{content:" ✓"\}/);
  // Кнопка: наливается, кружок, подпись без ⏳ с бликом.
  assert.match(css, /\[data-myclaude-continue\]>button\[data-myclaude-busy\]\[data-myclaude-continue-label\^="⏳"\]\{[^}]*animation:myclaude-fill /);
  assert.match(css, /\[data-myclaude-continue\]>button\[data-myclaude-busy\]\[data-myclaude-continue-label\^="⏳"\]::before\{[^}]*animation:myclaude-spin /);
  assert.match(css, /\[data-myclaude-continue\]>button\[data-myclaude-busy\]\[data-myclaude-continue-label\^="⏳"\]::after\{content:"Зову Пимпа…";[^}]*animation:myclaude-shim /);
  assert.match(css, /\[data-myclaude-continue-link\]\[data-myclaude-busy\]\{cursor:default\}/, "курсор-рука над занятой ссылкой");
  // Плашка «Новое окно» — тоже блик, «уменьшить движение» — без анимации.
  assert.match(css, /(^|[}\s])\[data-myclaude-busy\]:not\(button\):not\(\[data-myclaude-continue-link\]\)\{background:linear-gradient\(100deg,[^}]*animation:myclaude-shim /m);
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)\{\[data-myclaude-busy\]:not\(button\):not\(\[data-myclaude-continue-link\]\)\{animation:none !important;/);
});

// ---- 3. «▦ Галерея» и «Скажи — и сделаю» -------------------------------------

const CHAT = "local_aaaa-1111";
const galleryPage = () => {
  const loaded = loadInject({
    title: "Trelvis", href: `https://claude.ai/epitaxy/${CHAT}`,
    html: dom => dom.composer({ top: 600 }),
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.win.fetch = url => { loaded.calls.push(url); return Promise.resolve({}); };
  return loaded;
};

test("#7772: двойной клик по «Галерее» — одно нажатие, фильтр не снят тут же", () => {
  const loaded = galleryPage();
  const node = loaded.dom.query("#myclaude-gallery");
  node.dispatchEvent({ type: "click", detail: 1 });
  node.dispatchEvent({ type: "click", detail: 2 });
  node.dispatchEvent({ type: "click", detail: 3 });
  assert.deepEqual(loaded.calls, [`http://127.0.0.1:47615/viewer?chat=${CHAT}&on=1`], "Viewer дёрнули не раз");
  const gallery = plain(loaded.api.status().gallery);
  assert.deepEqual([gallery.on, gallery.clicks, gallery.repeats], [true, 1, 2]);
  // Отдельный клик потом — снова переключает.
  node.dispatchEvent({ type: "click", detail: 1 });
  assert.equal(plain(loaded.api.status().gallery).on, false);
});

test("#7772: двойной клик по слову «Скажи — и сделаю» — слово выбрано, не снято", () => {
  const nodes = {};
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Trelvis",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({});
      const row = dom.document.body.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" } });
      const box = row.add("div", { class: "contents" });
      box.add("h3", { text: "❗ Скажи — и сделаю ❗" });
      nodes.go = box.add("p").add("strong", { text: "«поехали»" });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.inner.sayTick(Date.now());
  assert.equal(nodes.go.getAttribute("data-myclaude-say"), "");
  loaded.dom.document.dispatchEvent({ type: "click", isTrusted: true, target: nodes.go, detail: 1 });
  loaded.dom.document.dispatchEvent({ type: "click", isTrusted: true, target: nodes.go, detail: 2 });
  assert.deepEqual(plain(loaded.inner.sayState.words), ["поехали"], "второй клик двойного снял слово");
  assert.equal(nodes.go.getAttribute("data-myclaude-say"), "on");
});

// ---- 4. HTML-файл в браузер -------------------------------------------------

const PATH = "/Users/dev/Projects/PimpMyClaude/docs/11.html";
const cardPage = () => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "PimpMyClaude",
    html: dom => {
      const parts = dom.composer();
      const answer = dom.document.body.add("div", { attrs: { "data-testid": "assistant-message" }, text: "Ответ." });
      parts.card = answer.add("button", { class: "font-sans rounded-lg" });
      parts.label = parts.card.add("span", { text: "html 11.html" });
      parts.card.__reactFiber$test = { memoizedProps: { children: [] }, return: { memoizedProps: { path: PATH, name: "11.html" }, return: null } };
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.win.fetch = url => { loaded.calls.push(url); return Promise.resolve({}); };
  return loaded;
};

test("#7772: двойной клик по карточке .html — одна вкладка, Claude нажатия не видит", () => {
  const loaded = cardPage();
  const passed = [1, 2].map(detail => loaded.document.dispatchEvent({ type: "click", isTrusted: true, target: loaded.parts.label, button: 0, detail }));
  assert.deepEqual(passed, [false, false], "второй клик ушёл Claude — откроется панель Browser");
  assert.equal(loaded.calls.length, 1, "файл открыт дважды");
  assert.match(loaded.calls[0], /\/open-html\?mode=click&path=/);
  const html = plain(loaded.api.status().htmlChrome);
  assert.deepEqual([html.clicks, html.repeats], [2, 1]);
});

test("#7772: пункт «Открыть в браузере» нажат дважды, пока меню не закрылось, — одна вкладка", () => {
  const loaded = cardPage();
  const menu = loaded.document.body.add("div", { attrs: { role: "menu", "data-cds": "ContextMenu" } });
  const list = menu.add("div");
  list.add("div", { attrs: { role: "separator" } });
  list.add("div", { attrs: { role: "menuitem" } }).add("span", { text: "Show in Finder" });
  assert.equal(loaded.inner.openChromeInsert(menu, loaded.inner.openChromePath(loaded.parts.card)), true);
  const item = [...list.children].find(node => node.textContent === "🌐 Открыть в браузере");
  item.dispatchEvent({ type: "click" });
  item.dispatchEvent({ type: "click" });
  assert.equal(loaded.calls.length, 1, "файл открыт дважды");
});

// ---- 5. Фото ----------------------------------------------------------------

test("#7772: двойной клик по фото в ленте — просмотр открыт и не увеличен", () => {
  const nodes = {};
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_view",
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      const tile = feed.add("div", { class: "group/message-row" }).add("span", { attrs: { role: "button" } });
      const img = tile.add("img", { attrs: { src: "data:image/png;base64,AAA" } });
      img.naturalWidth = 640;
      img.naturalHeight = 1440;
      img.rect = { left: 0, top: 0, width: 71, height: 160 };
      nodes.img = img;
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.document.dispatchEvent({ type: "click", isTrusted: true, target: nodes.img, button: 0, detail: 1 });
  const state = loaded.inner.photoState;
  assert.equal(state.open, true);
  const layer = loaded.document.querySelector("#myclaude-photo-view");
  layer.dispatchEvent({ type: "click", isTrusted: true, target: state.parts.img, detail: 2, clientX: 5, clientY: 5 });
  assert.deepEqual([state.open, state.zoom], [true, false], "второй клик увеличил фото");
  layer.dispatchEvent({ type: "click", isTrusted: true, target: state.parts.stage, detail: 2 });
  assert.equal(state.open, true, "второй клик закрыл просмотр");
  // Обычный клик по фону — закрывает, как прежде.
  layer.dispatchEvent({ type: "click", isTrusted: true, target: state.parts.stage, detail: 1 });
  assert.equal(state.open, false);
});

// ---- 6. «Новое окно» ещё раз, пока идёт первое ------------------------------

test("#7772: «Новое окно» нажато ещё раз — второго нет, плашка «⏳ Уже открываю окно…» переливается", async () => {
  const loaded = loadInject({ href: "https://claude.ai/epitaxy/local_abc", title: "Claude" });
  const command = id => ({ id, action: "new-window", at: "now", scope: "window", title: "Claude", text: "Привет", x: 100, y: 100 });
  loaded.dom.command(command("n1"));
  assert.equal(loaded.api.status().newWindow.busy, true);
  loaded.dom.command(command("n2"));
  assert.equal(loaded.api.status().newWindow.runs, 1, "второй запуск начался");
  const note = loaded.document.querySelector("#myclaude-new-window-note");
  assert.equal(note?.textContent, "⏳ Уже открываю окно…");
  const span = note.querySelector(`[${BUSY}]`);
  assert.ok(span, "плашка без перелива");
  assert.equal(span.textContent, "⏳ Уже открываю окно…");
});
