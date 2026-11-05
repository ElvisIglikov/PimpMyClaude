// #9319 «Новое сообщение в чате сбивает место чтения» (раздел 13а, 675-reading-place.js):
// лента уехала к самому низу САМА (Claude догоняет новое, наши «стояла у низа — к низу»),
// а Элвис читает (attnReading, раздел 12м) — прежний верх возвращается; не читает — едет за новым.
// #6590 🔥 «окошки Allow не должны дёргать чат вверх-вниз» (раздел 9, 250-layout.js): карточка
// разрешения в узком виде ложится слоем над лентой у верхней кромки доки, место ленты не меняется.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

// Часы страницы (performance.now стенда = Date.now) — вперёд на ms.
const later = ms => { const real = Date.now; Date.now = () => real() + ms; return () => { Date.now = real; }; };
const attn = loaded => plain(loaded.api.status().attention);

// ---- #9319: лента, ответ в ней, поле ввода ---------------------------------------------
const feedPage = () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_aaaa-1111", title: "Trelvis", hasFocus: true,
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript" },
        rect: { left: 0, top: 0, width: 1200, height: 500 }, computed: { overflowY: "auto" },
      });
      Object.assign(feed, { clientHeight: 500, scrollHeight: 2000, scrollTop: 1000 });
      parts.feed = feed;
      parts.answer = feed.add("div", { attrs: { "data-testid": "assistant-message" } });
      parts.answer.add("p", { text: "ответ, который Элвис читает" });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const feed = loaded.parts.feed;
  const scrolled = () => loaded.win.dispatchEvent({ type: "scroll", target: feed });
  // Пришло новое: лента выросла, и её довели до самого низа не рукой Элвиса.
  const grow = (by = 600) => { feed.scrollHeight += by; feed.scrollTop = feed.scrollHeight - feed.clientHeight; scrolled(); };
  const wheel = () => { loaded.win.dispatchEvent({ type: "wheel", deltaY: 40, target: loaded.parts.answer }); scrolled(); };
  return { loaded, feed, scrolled, grow, wheel };
};

test("#9319: читает (листал ленту) — новое не уводит её к низу, верх на месте", () => {
  const { loaded, feed, grow, wheel } = feedPage();
  wheel();
  const back = later(1500);
  try {
    grow();
    assert.equal(feed.scrollTop, 1000, "лента уехала к новому");
    grow(300);
    assert.equal(feed.scrollTop, 1000, "и второй раз тоже стоит");
    assert.equal(attn(loaded).held, 2);
  } finally { back(); }
});

test("#9319: не читает (жестов не было) — лента едет за новым, как было", () => {
  const { loaded, feed, scrolled, grow } = feedPage();
  scrolled();
  grow();
  assert.equal(feed.scrollTop, 2100);
  assert.equal(attn(loaded).held, 0);
});

test("#9319: прокрутка сразу после касания — его (стрелка Claude «вниз»), и её плавный ход до конца", () => {
  const { loaded, feed, scrolled, wheel } = feedPage();
  // Часы стоят и идут только шагами теста: кадры — ровно через 150 мс при цепочке FEED_CHAIN_MS 200,
  // а под нагрузкой настоящие миллисекунды между кадрами рвали её (#11441).
  const real = Date.now, base = real();
  const at = ms => { Date.now = () => base + ms; };
  try {
    at(0);
    wheel();
    // Нажал стрелку «вниз» (вне ленты): Claude везёт ленту плавно, кадр за кадром.
    at(1500);
    loaded.win.dispatchEvent({ type: "pointerdown", target: loaded.parts.editor });
    // Ход тянется дольше FEED_USER_MS — кадры по 150 мс, цепочка всё ещё его.
    for (let step = 1; step <= 10; step += 1) {
      at(1500 + step * 150);
      feed.scrollTop = 1000 + step * 50; scrolled();
    }
  } finally { Date.now = real; }
  assert.equal(feed.scrollTop, 1500, "конец плавного хода — не «уехала сама»");
  assert.equal(attn(loaded).held, 0);
});

test("#9319: сдвиг вниз не до низа (якорь прокрутки, досчитанные строки) — не трогаем", () => {
  const { loaded, feed, scrolled, wheel } = feedPage();
  wheel();
  const back = later(1500);
  try {
    feed.scrollTop = 1080; scrolled();
    assert.equal(feed.scrollTop, 1080);
    assert.equal(attn(loaded).held, 0);
  } finally { back(); }
});

test("#9319: своя прокрутка (команда «Прокрутить») не спорит с местом чтения", () => {
  const { loaded, feed, scrolled, wheel } = feedPage();
  wheel();
  const back = later(1500);
  try {
    loaded.dom.command({ id: "s-1", action: "scroll", at: "now" });
    scrolled();
    assert.equal(feed.scrollTop, 2000, "команда прокрутила к низу");
    assert.equal(attn(loaded).held, 0);
  } finally { back(); }
});

test("#9319: Claude спорит (снова и снова к низу) — после трёх возвратов уступаем до следующего жеста", () => {
  const { loaded, feed, grow, wheel } = feedPage();
  wheel();
  const back = later(1500);
  try {
    for (let round = 0; round < 3; round += 1) { grow(100); assert.equal(feed.scrollTop, 1000, `возврат ${round + 1}`); }
    grow(100);
    assert.equal(feed.scrollTop, feed.scrollHeight - feed.clientHeight, "уступили: дёрганье хуже сдвига");
    assert.deepEqual([attn(loaded).held, attn(loaded).yielded], [3, 1]);
    grow(100);
    assert.equal(attn(loaded).held, 3, "до следующего жеста не держим");
  } finally { back(); }
});

test("#9319: другой чат в том же окне — прежний верх не в счёт", () => {
  const { loaded, feed, grow, wheel } = feedPage();
  wheel();
  loaded.win.location.href = "https://claude.ai/epitaxy/local_bbbb-2222";
  const back = later(1500);
  try {
    grow();
    assert.equal(feed.scrollTop, 2100, "новый чат Claude открывает с низа");
  } finally { back(); }
});

// ---- #6590: панель чата в узком виде — тело ленты и дока с полем ---------------------
const CARD_FLOAT = "data-myclaude-card-float";
const PANEL = { left: 0, top: 0, width: 600, height: 800 };
const BODY = { left: 0, top: 32, width: 600, height: 568 };
const DOCK = { left: 0, top: 600, width: 600, height: 200 };
const PROMPT = { left: 12, top: 610, width: 576, height: 150 };
const panelPage = ({ wide = false, body = BODY, card = null } = {}) => {
  const loaded = loadInject({
    title: "Trelvis",
    html: dom => {
      const panel = dom.document.body.add("div", { class: "epitaxy-chat-panel", rect: PANEL, computed: wide ? { "--myclaude-wide": "1" } : {} });
      const grid = panel.add("div", { class: "relative h-full min-w-0 flex flex-col", rect: PANEL });
      const contents = grid.add("div", { class: "contents" });
      const panelBody = contents.add("div", { class: "epitaxy-chat-panel-body", rect: body });
      const dock = contents.add("div", { class: "contents" }).add("div", { class: "group/approval-dock flex flex-col", rect: DOCK });
      const prompt = dock.add("div", { class: "epitaxy-prompt", rect: PROMPT });
      const block = prompt.add("div", { class: "flex w-full min-w-0 flex-col font-sans", rect: PROMPT });
      const shell = block.add("div", { class: "bg-surface-3", rect: { ...PROMPT, height: 120 }, computed: { borderBottomWidth: "1px" } });
      const root = shell.add("div", { class: "editor-root", rect: { left: 22, top: 620, width: 556, height: 100 }, computed: { overflowY: "auto" } });
      const editor = root.add("div", { class: "ProseMirror", attrs: { contenteditable: "true" }, rect: { left: 22, top: 620, width: 556, height: 100 } });
      block.add("div", { class: "model-row", rect: { left: 12, top: 734, width: 576, height: 26 } });
      return { panel, panelBody, dock, prompt, editor };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return loaded;
};
const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
// Карточка Claude над полем: слой — 220 над верхней кромкой доки.
const addCard = (loaded, computed = { backgroundColor: "rgb(40, 40, 40)" }) =>
  loaded.parts.dock.add("div", { class: "epitaxy-approval-card", rect: { left: 12, top: 374, width: 576, height: 220 }, computed });

test("#6590: узкий вид — дока помечена заранее, карточка слоем над лентой: CSS тем же кадром, места ленты не отнимает", () => {
  const loaded = panelPage();
  settle(loaded);
  const dock = loaded.parts.dock;
  assert.equal(dock.hasAttribute(CARD_FLOAT), true, "дока не помечена до карточки");
  assert.equal(dock.style.getPropertyValue("--myclaude-card-room"), `${DOCK.top - BODY.top - 6}px`, "потолок карточки — лента над доком");
  assert.equal(dock.style.getPropertyValue("--myclaude-card-start"), "12px");
  assert.equal(dock.style.getPropertyValue("--myclaude-card-end"), "12px");
  const css = loaded.dom.queryAll("style").map(node => node.textContent).join("\n");
  assert.match(css, /\[data-myclaude-card-float\] \.epitaxy-approval-card\{position:absolute !important;inset:auto var\(--myclaude-card-end,0px\) calc\(100% \+ 6px\) var\(--myclaude-card-start,0px\) !important;[^}]*max-height:var\(--myclaude-card-room,50vh\) !important;overflow-y:auto !important/);
  const card = addCard(loaded);
  settle(loaded);
  assert.deepEqual([attn(loaded).card, attn(loaded).cards], ["on", 1]);
  assert.equal(card.hasAttribute("data-myclaude-card-solid"), false, "у карточки свой фон — не трогаем");
  settle(loaded);
  assert.equal(attn(loaded).cards, 1, "та же карточка — не новая");
});

test("#6590: прозрачная карточка слоем получает фон доки, иначе легла бы текстом на текст", () => {
  const loaded = panelPage();
  settle(loaded);
  const card = addCard(loaded, {});
  settle(loaded);
  assert.equal(card.hasAttribute("data-myclaude-card-solid"), true);
  const css = loaded.dom.queryAll("style").map(node => node.textContent).join("\n");
  assert.match(css, /\[data-myclaude-card-float\] \.epitaxy-approval-card\[data-myclaude-card-solid\]\{background-color:var\(--epitaxy-transcript-surface,var\(--cds-surface-1\)\) !important\}/);
  loaded.api.dispose();
  assert.equal(card.hasAttribute("data-myclaude-card-solid"), false);
  assert.equal(loaded.parts.dock.hasAttribute(CARD_FLOAT), false, "dispose снимает метку доки");
});

test("#6590: слой закрыт чужим (в его середине лента) — карточка в поток до перезагрузки", () => {
  const loaded = panelPage();
  settle(loaded);
  addCard(loaded);
  loaded.document.elementFromPoint = () => loaded.parts.panelBody;
  settle(loaded);
  assert.equal(loaded.parts.dock.hasAttribute(CARD_FLOAT), false);
  assert.equal(attn(loaded).card, "off");
  loaded.document.elementFromPoint = () => null;
  settle(loaded);
  assert.equal(loaded.parts.dock.hasAttribute(CARD_FLOAT), false, "не мигает туда-обратно");
});

test("#6590: слой ушёл за край окна — тоже в поток", () => {
  const loaded = panelPage();
  settle(loaded);
  const card = addCard(loaded);
  card.rect = { ...card.rect, top: -40 };
  settle(loaded);
  assert.equal(attn(loaded).card, "off");
});

test("#6590: широкий вид (дока — своя колонка) и растянутое поле (ленты над ним мало) — карточка как у Claude", () => {
  const wide = panelPage({ wide: true });
  settle(wide);
  assert.equal(wide.parts.dock.hasAttribute(CARD_FLOAT), false, "широкий вид");
  const tall = panelPage({ body: { ...BODY, top: 460, height: 140 } });
  settle(tall);
  assert.equal(tall.parts.dock.hasAttribute(CARD_FLOAT), false, "ленты над полем 134 < 160");
  assert.equal(attn(tall).card, null);
});
