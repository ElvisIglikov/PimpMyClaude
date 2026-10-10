// WF125 (#8894, раздел 12п¹ inject.js): кнопка «PMP» на месте кнопки «Повторить
// голос Рика» (#7960, WF103).
//
// Контракт (CONTRACTS, «Кнопка „PMP“ в окне Claude»): рядом с «Галереей» у поля;
// с WF213 (#9373, критик WF209 п. 13) — во всех чатах главного окна, в попапе — как
// было, только в чате папки Rick (последний компонент cwd сессии чата). Клик
// открывает панель оркестрации страницы (tests/pmp-panel-wf213.test.mjs), а панель
// у часов — её команда «Настройки Пимпа»: GET http://127.0.0.1:47615/panel (cors);
// пока ждём ответа — новые нажатия ничего; отказ или тишина 3 с — «PimpMyClaude не
// отвечает» и возврат вида; фокус поля не отнимает;
// status().pmp = {button, clicks, last, state, open, rows, terminals, running, lastError}.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const PMP = "#myclaude-pmp";
const HINT = "#myclaude-mic-hint";
const GALLERY = "#myclaude-gallery";
const MIC = "#myclaude-mic";
const CHAT = "local_aaaa-1111";
const LEFT = { left: 100, top: 750, width: 60, height: 16 };
const RING = { left: 1100, top: 748, width: 20, height: 20 };
const URL = "http://127.0.0.1:47615/panel";
let seq = 0;

const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const EMPTY = { v: 1, at: "2026-10-10T00:00:00Z", projects: [] };
const page = ({ cwd = "/Users/dev/Projects/Rick", files = null, mic = null, reply = () => Promise.resolve({ ok: true }), local = {}, popup = null } = {}) => {
  const loaded = loadInject({
    title: "Rick", href: popup ? "about:blank" : `https://claude.ai/epitaxy/${CHAT}`,
    // Попап своего адреса не имеет: id чата — из кэша окна, папка чата — из списка слева у родителя.
    storage: { local, ...(popup ? { session: { "myclaude-chat-v1": JSON.stringify({ id: CHAT, title: "Rick" }) } } : {}) },
    opener: popup,
    html: dom => {
      const parts = dom.composer({ top: 600 });
      parts.chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: { left: 92, top: 744, width: 1016, height: 28 } });
      const row = parts.chin.add("div", { class: "flex items-center", rect: { left: 100, top: 748, width: 1000, height: 20 } });
      parts.left = row.add("div", { class: "flex items-center self-start", rect: LEFT });
      parts.left.add("button", { attrs: { "aria-label": "Add" }, rect: { left: 100, top: 750, width: 20, height: 16 } });
      const right = row.add("div", { class: "ms-auto flex items-center", rect: { left: 1000, top: 748, width: 120, height: 20 } });
      const grid = right.add("div", { class: "grid", rect: { left: 1000, top: 748, width: 120, height: 20 } });
      grid.add("button", { attrs: { "data-testid": "epitaxy-cds-model-selector" }, text: "Opus 5.5", rect: { left: 1000, top: 750, width: 60, height: 16 } });
      grid.add("button", { attrs: { "aria-haspopup": "dialog", "aria-label": "Usage: Context 300k / 1M (30%)" }, rect: RING });
      // Список слева: строка чата с сессией (cwd — папка чата), как у P1.
      const side = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
      const item = side.add("div", { attrs: { "data-row-key": `code:${CHAT}` } });
      item.__reactFiber$test = { memoizedProps: { session: { ref: { id: CHAT }, source: { data: { cwd } } } }, return: null };
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  // Сводку /digest спрашивают ячейки Workflow в окне Rick (12п², WF134) и число у кнопки, текст
  // запуска /kickoff — открытая панель (12п³, WF213): это не запросы панели у часов.
  loaded.win.fetch = (url, options) => {
    if (String(url).endsWith("/digest")) return Promise.resolve({ ok: true, json: async () => EMPTY });
    if (String(url).endsWith("/kickoff")) return Promise.resolve({ ok: false });
    loaded.calls.push([url, options?.mode]);
    return reply();
  };
  const base = loaded.win.performance.now();
  let shift = 0;
  loaded.win.performance.now = () => base + shift;
  loaded.later = ms => { shift += ms; };
  if (mic) loaded.dom.command({ id: `m-${seq += 1}`, action: "mic", at: "now", scope: "all", mode: mic });
  if (files) loaded.dom.command({ id: `c-${seq += 1}`, action: "viewer-counts", at: "now", scope: "all", chats: { [CHAT]: files } });
  settle(loaded);
  return loaded;
};
const node = loaded => loaded.dom.query(PMP);
const px = (item, name) => Number(String(item.style.getPropertyValue(name)).replace("px", ""));
const pmp = loaded => plain(loaded.api.status().pmp);
const press = (loaded, detail = 1) => node(loaded).dispatchEvent({ type: "click", detail });
// «Настройки Пимпа» открытой панели — прежнее действие кнопки: панель у часов.
const PANEL = "#myclaude-pmp-panel";
const settings = (loaded, detail = 1) => {
  if (!pmp(loaded).open) press(loaded);
  const button = [...loaded.dom.query(PANEL).querySelectorAll("button")].find(item => item.dataset.act === "settings");
  // Стаб событий не всплывает: слушатель панели получает нажатие с целью-кнопкой.
  return button ? loaded.dom.query(PANEL).dispatchEvent({ type: "click", detail, target: button }) : null;
};
const QUIET = { open: false, rows: 0, terminals: 0, running: 0, lastError: null };
const tick = () => new Promise(resolve => setImmediate(resolve));
const hint = loaded => loaded.dom.query(HINT);

test("#8894: окно проекта Rick — плашка «PMP» у поля, подсказка «Workflow и терминалы» (WF213), кнопки Рика нет", () => {
  const loaded = page();
  const item = node(loaded);
  assert.equal(item.style.getPropertyValue("display"), "flex");
  assert.equal(item.title, "Workflow и терминалы");
  assert.equal(item.getAttribute("aria-label"), "Workflow и терминалы");
  assert.equal(item.getAttribute("aria-expanded"), "false");
  assert.equal(item.textContent, "PMP");
  assert.equal(loaded.dom.query("#myclaude-rick"), null, "кнопка Рика осталась");
  assert.equal(loaded.api.status().rick, undefined);
  assert.deepEqual(pmp(loaded), { button: true, clicks: 0, last: null, state: null, ...QUIET });
  // Галереи нет — кнопка сразу правее левой группы, группе дано место под неё.
  assert.equal(px(item, "left"), LEFT.left + LEFT.width + 6);
  assert.equal(loaded.parts.left.getAttribute("data-myclaude-gallery-room"), `${6 + 24 + 6}px`);
});

test("#8894: с «Галереей» — правее неё, место у группы на обе", () => {
  const loaded = page({ files: [3, 0] });
  const gallery = loaded.dom.query(GALLERY);
  assert.equal(px(node(loaded), "left"), px(gallery, "left") + px(gallery, "width") + 6);
  assert.equal(loaded.parts.left.getAttribute("data-myclaude-gallery-room"), `${6 + 26 + 6 + 24 + 6}px`);
});

test("#8894: свёрнутое поле — между микрофоном и «Галереей»", () => {
  const loaded = page({ files: [3, 0], mic: "dictator" });
  loaded.api.setStage(loaded.api.stages.COLLAPSED);
  settle(loaded);
  const mic = loaded.dom.query(MIC);
  assert.equal(mic.dataset.spot, "ring");
  assert.equal(node(loaded).dataset.spot, "ring");
  assert.equal(px(node(loaded), "left"), px(mic, "left") - 6 - 24, "не левее микрофона");
  assert.equal(px(loaded.dom.query(GALLERY), "left"), px(node(loaded), "left") - 6 - 26, "«Галерея» не левее кнопки PMP");
});

test("WF213 (критик п. 13): главное окно — кнопка в любом чате; попап — только в чате папки Rick", () => {
  for (const cwd of ["/Users/dev/Projects/PimpMyClaude", "/Users/dev/Projects/Rick/voice", "/Users/dev/Rickety"]) {
    const loaded = page({ cwd });
    assert.equal(node(loaded).style.getPropertyValue("display"), "flex", cwd);
    assert.equal(pmp(loaded).button, true);
    assert.equal(loaded.api.status().rickCells.wanted, false, "старый блок Workflow — только в чате Рика");
    press(loaded);
    assert.equal(pmp(loaded).open, true, cwd);
    assert.equal(loaded.calls.length, 0, "нажатие открывает панель страницы, а не панель у часов");
    // Попап этого же чата: папка не Rick — кнопки нет, как до WF213.
    const popup = page({ cwd, popup: loaded.win });
    assert.equal(popup.api.status().chat.self, CHAT, "стенд: попап не узнал свой чат");
    assert.equal(node(popup).style.getPropertyValue("display"), "none", `попап: ${cwd}`);
    press(popup);
    assert.equal(pmp(popup).open, false);
  }
  const rick = page();
  const popup = page({ popup: rick.win });
  assert.equal(node(popup).style.getPropertyValue("display"), "flex", "попап чата Рика — кнопка на месте");
});

test("#8894 → WF213: клик — панель оркестрации, запроса /panel нет; «Настройки Пимпа» — GET /panel, cors; ждём ответа — повтор ничего; фокус не отнимает", async () => {
  const loaded = page();
  assert.equal(node(loaded).dispatchEvent({ type: "pointerdown" }), false, "pointerdown не погашен");
  assert.equal(node(loaded).dispatchEvent({ type: "mousedown" }), false, "mousedown не погашен");
  press(loaded);
  assert.deepEqual(loaded.calls, [], "клик по кнопке ушёл в приложение");
  assert.equal(pmp(loaded).open, true);
  assert.equal(node(loaded).getAttribute("aria-expanded"), "true");
  settings(loaded);
  assert.deepEqual(loaded.calls, [[URL, "cors"]]);
  assert.deepEqual(pmp(loaded), { button: true, clicks: 1, last: URL, state: "wait", ...QUIET });
  settings(loaded);
  settings(loaded, 2);
  assert.equal(loaded.calls.length, 1, "повтор до ответа ушёл в приложение");
  await tick();
  assert.equal(pmp(loaded).state, null, "ответ пришёл — вид не вернулся");
  assert.notEqual(hint(loaded).style.getPropertyValue("display"), "block", "подсказка при удаче");
  settings(loaded, 2);
  assert.equal(loaded.calls.length, 1, "двойной клик — второе нажатие");
  settings(loaded);
  assert.equal(loaded.calls.length, 2, "после ответа команда снова работает");
  assert.equal(pmp(loaded).clicks, 2);
});

test("#8894: приложение не отвечает (ошибка сети, отказ, тишина) — «PimpMyClaude не отвечает», вид возвращается", async () => {
  const silent = [() => Promise.reject(new Error("net")), () => Promise.resolve({ ok: false }), () => new Promise(() => {})];
  for (const [index, reply] of silent.entries()) {
    const loaded = page({ reply });
    settings(loaded);
    assert.equal(pmp(loaded).state, "wait", String(index));
    await tick();
    if (index === 2) {
      assert.equal(pmp(loaded).state, "wait", "тишина — ждём срок");
      loaded.dom.fireKind("timeout");
    }
    assert.equal(pmp(loaded).state, "silent", String(index));
    assert.equal(hint(loaded).style.getPropertyValue("display"), "block", String(index));
    assert.equal(hint(loaded).textContent, "PimpMyClaude не отвечает");
    loaded.dom.fireKind("timeout");
    assert.equal(pmp(loaded).state, null, `вид не вернулся: ${index}`);
    assert.equal(hint(loaded).style.getPropertyValue("display"), "none", String(index));
    settings(loaded);
    assert.equal(loaded.calls.length, 2, "после отказа команда снова работает");
  }
});

test("#8894: dispose посреди ожидания — узла нет, поздний ответ вид не трогает", async () => {
  let answer = null;
  const loaded = page({ reply: () => new Promise(resolve => { answer = resolve; }) });
  settings(loaded);
  loaded.api.dispose();
  assert.equal(loaded.dom.query(PMP), null, "узел кнопки остался");
  assert.equal(loaded.dom.query(PANEL), null, "узел панели остался");
  answer({ ok: false });
  await tick();
  assert.notEqual(loaded.dom.query(HINT)?.style.getPropertyValue("display"), "block", "подсказка после dispose");
});

// #9136 (слово Элвиса 08.10 ~23:00: «серенький непонятный… я бы вообще пимпу убрал… 19
// подержал и всё»): у поля — только число недели цветом соседних подписей, без плашки.
test("#9136: только число недели, без серой плашки; числа нет — тихая надпись «PMP»", () => {
  const week = { at: Date.now(), plan: "max", weekly: { used: 19, resetsAt: Date.now() + 86400000 } };
  const loaded = page({ local: { "myclaude-limits-v1": JSON.stringify(week) } });
  const item = node(loaded);
  assert.equal(item.style.getPropertyValue("display"), "flex");
  assert.equal([...item.children][1].textContent, "19");
  assert.equal([...item.children][2].textContent, "", "знак «▶N» без идущих Workflow");
  assert.equal(item.textContent, "PMP19", "надпись «PMP» в узле, на экране её прячет лист стилей");
  assert.equal(item.style.getPropertyValue("--pmp-week"), "19%");
  const sheet = loaded.dom.query("#myclaude-input-handle-style").textContent;
  assert.ok(!sheet.includes("#4b4b52"), "серая плашка осталась");
  assert.match(sheet, /#myclaude-pmp>\.p\{display:none;/, "плашка «PMP» видна рядом с числом");
  assert.match(sheet, /#myclaude-pmp:has\(>\.n:empty\)>\.p\{display:flex\}/, "без числа кнопка пропала бы");
  assert.match(sheet, /#myclaude-pmp\{[^}]*color:inherit;[^}]*opacity:1;/, "число бледнее соседних подписей");
  assert.match(sheet, /#myclaude-pmp>\.n\{[^}]*color:inherit;[^}]*font:600 1[2-3]px/, "число мельче соседних подписей");
  press(loaded);
  assert.equal(pmp(loaded).open, true, "клик по числу открывает панель оркестрации");
});

test("#9181: в нижней строке поля число недели и «Галерея» — цветом, гарнитурой и кеглем подписей строки (как BY), не белее", () => {
  const loaded = page({ files: [8, 0] });
  const model = loaded.dom.query('[data-testid="epitaxy-cds-model-selector"]');
  assert.equal(model.getAttribute("data-myclaude-chin"), "text");
  model.computed = { ...model.computed, fontFamily: "anthropic-sans, system-ui", fontSize: "11px", color: "rgb(179, 162, 214)" };
  settle(loaded);
  const gallery = loaded.dom.query(GALLERY);
  for (const item of [node(loaded), gallery]) {
    assert.equal(item.dataset.spot, "field");
    assert.equal(item.style.getPropertyValue("--k"), "rgb(179, 162, 214)");
    assert.equal(item.style.getPropertyValue("--rf"), "anthropic-sans, system-ui");
    assert.equal(item.style.getPropertyValue("--rs"), "11px");
  }
  const css = plain(loaded.inner.RULES).join("\n");
  assert.match(css, /#myclaude-pmp\[data-spot="field"\]\{color:var\(--k,inherit\)\}/);
  // WF175 (#9195: «все цифры плавают»): строка числа 16, как у подписей строки, — общая базовая линия.
  assert.match(css, /#myclaude-pmp\[data-spot="field"\]>\.n\{padding-bottom:0;font:400 var\(--rs,11px\)\/16px var\(--rf,[^}]*font-variant-numeric:tabular-nums/);
  assert.match(css, /#myclaude-gallery\[data-spot="field"\]\[data-fresh="true"\]::after\{display:none\}/, "точка над числом в строке поля");
  assert.match(css, /#myclaude-gallery\[data-spot="field"\]\{color:var\(--k,inherit\);opacity:1\}/);
  assert.match(css, /#myclaude-gallery\[data-spot="field"\]>i\{font:400 var\(--rs,11px\)/);
  // По вертикали — по середине подписи модели (её строка 16), не группы слева (у Claude прижата кверху).
  model.rect = { left: 1000, top: 754, width: 60, height: 16 };
  settle(loaded);
  const mid = node => Number(node.style.getPropertyValue("top").replace("px", "")) + Number(node === gallery ? 20 : 14) / 2;
  assert.equal(mid(gallery), 762, "«Галерея» не на линии подписи модели");
  assert.equal(mid(node(loaded)), 762, "число недели не на линии подписи модели");
  // Правило цвета у «Галереи» — после «свежей» и «нажатой» (там color:inherit — белее подписей строки).
  const at = needle => css.indexOf(needle);
  assert.ok(at('#myclaude-gallery[data-spot="field"]{') > at('#myclaude-gallery[data-fresh="true"],#myclaude-gallery[data-on="true"]{'));
});
