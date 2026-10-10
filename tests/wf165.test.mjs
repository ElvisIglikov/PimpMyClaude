// WF165 (09.10.2026, слова Элвиса 00:05) — страница:
// #9166а поле ввода прозрачно и без рамки во всех видах; #9166б тихое выделение чата в списке
// слева; #9166в точки чатов не серые/белые; #9165 плавное появление нового в ленте;
// #9167 плашки ленты ответа — по правому краю; #9168 выключка по ширине переключаемая
// (команда text-justify, К-J1). Геометрию CSS стаб не считает — правила сверяются текстом,
// поведение (команда, хранение, анимации) — через страницу.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const STYLE = "myclaude-input-handle-style";
const KEY = "myclaude.textJustify";
const MARK = "data-myclaude-justify";

const rules = loaded => {
  const text = loaded.document.getElementById(STYLE)?.textContent ?? "";
  return text.split("\n");
};
const ruleWith = (loaded, needle) => rules(loaded).filter(line => line.includes(needle));
const bodyOf = rule => rule.slice(rule.indexOf("{") + 1, rule.lastIndexOf("}"));
const selectorsOf = rule => rule.slice(0, rule.indexOf("{")).split(/,(?![^()]*\))/).map(item => item.trim());

const stand = () => {
  const loaded = loadInject({ html: "composer", title: "Rick чат Элвиса" });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return loaded;
};

test("#9166а: коробка поля ввода — прозрачна, без обводки, кольца, тени и размытия, одним правилом вне @container и вне живого фона", () => {
  const loaded = stand();
  const found = ruleWith(loaded, '[data-cds="ChatComposer"] > div[class*="bg-surface"]{');
  assert.equal(found.length, 1, "одно общее правило коробки поля");
  const body = bodyOf(found[0]);
  for (const part of [/background-color:transparent !important/, /background-image:none !important/, /border-color:transparent !important/,
    /box-shadow:0 0 0 0 transparent !important/, /outline:none !important/, /backdrop-filter:none !important/]) assert.match(body, part);
  // Геометрию рамки не трогаем: по ширине и тени editorFrame находит коробку (#6890).
  assert.ok(!/border-width:\s*0|border:\s*0|box-shadow:\s*none/.test(body));
  assert.ok(!found[0].startsWith("@"), "не под @media/@container — во всех видах");
});

test("#9166б: выбранный и наведённый чат слева — 4,5 % и 3 % цвета текста (WF182, вдвое тише), без акцента и свечения", () => {
  const loaded = stand();
  const [vars] = ruleWith(loaded, "aside.dframe-sidebar,aside.dframe-sidebar [data-row]{--df-selected:");
  assert.ok(vars, "переменные выделения не переопределены на панели");
  assert.match(vars, /--df-selected:color-mix\(in oklab, var\(--cds-text-primary, currentColor\) 4\.5%, transparent\) !important/);
  assert.match(vars, /--df-hover:color-mix\(in oklab, var\(--cds-text-primary, currentColor\) 3%, transparent\) !important/);
  assert.ok(!/accent/.test(vars), "не акцентом");
  assert.ok(ruleWith(loaded, "aside.dframe-sidebar [data-row],aside.dframe-sidebar [data-row-main-button]{box-shadow:none !important}").length, "свечения у строки нет");
  // Тема (30 % акцента) ставит переменные на корне — правило на панели ближе к строке и сильнее.
  const theme = loaded.inner.themeCss({ type: "dark", palette: { background: "#2a1440", foreground: "#eedefc", accent: "#a47cf0", panel: "#341a4e", muted: "#a078c2" } });
  assert.match(String(theme), /--df-selected: #[0-9a-f]{6} !important/, "тема по-прежнему ставит своё на корне");
});

test("#9166в: точка «идёт» и кружок «простаивает» у чатов — акцентом PMP, не серым и не белым", () => {
  const loaded = stand();
  const [run] = ruleWith(loaded, '.status-dot[data-kind="running"]{');
  assert.ok(run, "правила точки «идёт» нет");
  assert.match(run, /^aside\.dframe-sidebar /, "только в списке слева");
  assert.match(bodyOf(run), /background:#a47cf0 !important/);
  const [idle] = ruleWith(loaded, '.df-leading-slot [role="img"]>span[class~="rounded-full"][class~="border"]{');
  assert.ok(idle, "правила кружка «простаивает» нет");
  assert.match(bodyOf(idle), /color:#a47cf0 !important/);
  // Яркие точки Claude (ready — акцент, awaiting — жёлтая, error) не перекрашены.
  assert.ok(!rules(loaded).some(line => /status-dot\[data-kind="(ready|awaiting|error)"\]/.test(line)));
});

test("#9167: плашки ленты ответа — одним правилом к правому краю, ширина по содержимому; текст ответа не задет", () => {
  const loaded = stand();
  const { FEED_PLATES } = loaded.inner;
  const found = rules(loaded).filter(line => line.startsWith(`${FEED_PLATES}{`));
  assert.equal(found.length, 1, "одно правило");
  const body = bodyOf(found[0]);
  assert.match(body, /margin-inline-start:auto !important/);
  assert.match(body, /align-self:flex-end !important/);
  assert.match(body, /width:fit-content !important/);
  assert.match(body, /max-width:100% !important/);
  const selectors = selectorsOf(found[0]);
  assert.deepEqual(selectors.map(item => item.replace('.epitaxy-chat-panel [data-cds="AssistantMessage"] ', "")), [
    '[data-cds="TurnStatus"] > [data-cds-row]',
    'button[class~="group/tool"]',
    'button[class~="self-start"][class~="isolate"]',
    '[data-cds="Card"]:not([data-cds="Card"] *)',
  ]);
  assert.ok(selectors.every(item => item.startsWith('.epitaxy-chat-panel [data-cds="AssistantMessage"] ')), "только в ответах ленты");
  assert.ok(!selectors.some(item => /Prose|\bp\b|UserMessage/.test(item)), "абзацы и сообщения человека не трогаем");
});

test("#9168: выключка по умолчанию включена — метки нет, status().layout.justify = true", () => {
  const loaded = stand();
  assert.equal(loaded.document.documentElement.getAttribute(MARK), null);
  assert.equal(plain(loaded.api.status().layout).justify, true);
  assert.equal(loaded.inner.textJustifyOn(), true);
});

test("#9168: команда text-justify off/on строкой — хранение, метка на <html>, статус; мусор — влево", () => {
  const loaded = stand();
  loaded.dom.command({ id: "j1", action: "text-justify", at: 1, on: "false" });
  assert.equal(loaded.win.localStorage.getItem(KEY), "0");
  assert.equal(loaded.document.documentElement.getAttribute(MARK), "off");
  assert.equal(plain(loaded.api.status().layout).justify, false);
  loaded.dom.command({ id: "j2", action: "text-justify", at: 2, on: "true" });
  assert.equal(loaded.win.localStorage.getItem(KEY), null);
  assert.equal(loaded.document.documentElement.getAttribute(MARK), null);
  assert.equal(plain(loaded.api.status().layout).justify, true);
  loaded.dom.command({ id: "j3", action: "text-justify", at: 3, on: "да" });
  assert.equal(loaded.document.documentElement.getAttribute(MARK), "off", "как hide-tools: включает только \"true\"");
});

test("#9168: флаг из прошлого, соседнее окно (storage), dispose и повторный инжект", () => {
  const loaded = loadInject({ html: "composer", storage: { local: { [KEY]: "0" } } });
  assert.equal(loaded.error, null);
  const root = loaded.document.documentElement;
  assert.equal(root.getAttribute(MARK), "off", "флаг «влево» — метка с установки");
  loaded.win.localStorage.removeItem(KEY);
  loaded.win.dispatchEvent({ type: "storage", key: KEY });
  assert.equal(root.getAttribute(MARK), null);
  loaded.win.localStorage.setItem(KEY, "0");
  loaded.win.dispatchEvent({ type: "storage", key: KEY });
  assert.equal(root.getAttribute(MARK), "off");
  loaded.api.dispose();
  assert.equal(root.getAttribute(MARK), null, "dispose снимает метку");
  const again = loaded.reload();
  assert.equal(again.error, null);
  assert.equal(root.getAttribute(MARK), "off");
});

test("#9168: правило выключки обходит выключенное — селекторы с html:not([data-myclaude-justify=\"off\"])", () => {
  const loaded = stand();
  const css = loaded.inner.layoutCss().replace(/\/\*[\s\S]*?\*\//g, "");
  const at = css.indexOf("text-align: justify");
  const head = css.slice(css.lastIndexOf("}", at) + 1, css.indexOf("{", css.lastIndexOf("}", at) + 1));
  const selectors = head.split(/,(?![^()]*\))/).map(item => item.trim()).filter(Boolean);
  assert.equal(selectors.length, 1); // поле ввода — влево с 09.10
  assert.ok(selectors.every(item => item.startsWith('html:not([data-myclaude-justify="off"]) ')));
});

// --- #9165: появление нового в ленте ---------------------------------------
const row = (feed, index, tail) => feed.add("div", { attrs: {
  "data-testid": "transcript-row", "data-index": String(index), "data-perf-row": "assistant",
  ...(tail == null ? {} : { "data-perf-row-from-tail": String(tail) }),
} });
const feedStand = () => {
  const loaded = loadInject({
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", { class: "epitaxy-chat-panel" }).add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } });
      for (let index = 0; index < 4; index += 1) row(feed, index, 3 - index);
      parts.feed = feed;
      return parts;
    },
    title: "Rick чат Элвиса",
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.inner.feedEnterState.quietUntil = 0;
  return loaded;
};
const added = (target, ...nodes) => [{ type: "childList", target, addedNodes: nodes, removedNodes: [] }];
const enterings = loaded => loaded.dom.animations.filter(item => item.options?.duration === loaded.inner.FEED_ENTER_MS || item.options?.duration === 180);

test("#9165: новая строка ленты (номер выше виденных, у хвоста) проявляется — прозрачность 0→1 и подъём 5 px за 220 мс", () => {
  const loaded = feedStand();
  const fresh = row(loaded.parts.feed, 4, 0);
  loaded.inner.onMutated(added(loaded.parts.feed, fresh));
  const [one, ...rest] = enterings(loaded);
  assert.equal(rest.length, 0);
  assert.equal(one.node, fresh);
  assert.deepEqual(plain(one.frames), [{ opacity: 0, translate: "0 5px" }, { opacity: 1, translate: "0 0" }]);
  assert.equal(one.options.duration, 220);
  assert.ok(one.options.duration >= 180 && one.options.duration <= 240);
  assert.equal(loaded.inner.feedEnterState.rows, 1);
});

test("#9165: прокрутка (старая строка с меньшим номером, далёкая от хвоста) и та же строка второй раз — без анимации", () => {
  const loaded = feedStand();
  const feed = loaded.parts.feed;
  loaded.inner.feedEnterOnMutation(added(feed, row(feed, 1, 2)));
  loaded.inner.feedEnterOnMutation(added(feed, row(feed, 30, 9)));
  assert.equal(enterings(loaded).length, 0, "низ виртуальной ленты при прокрутке — далеко от хвоста");
  const tail = row(feed, 31, 0);
  loaded.inner.feedEnterOnMutation(added(feed, tail));
  loaded.inner.feedEnterOnMutation(added(feed, tail));
  assert.equal(enterings(loaded).length, 1, "перемонтаж той же строки не играет второй раз");
});

test("#9165: вход в чат и тишина после установки — лента грузится без анимации", () => {
  const loaded = feedStand();
  const feed = loaded.parts.feed;
  loaded.win.location.pathname = "/epitaxy/local_other";
  loaded.inner.feedEnterOnMutation(added(feed, row(feed, 7, 0)));
  assert.equal(enterings(loaded).length, 0, "смена чата — новая точка отсчёта");
  assert.ok(loaded.inner.feedEnterState.quietUntil > 0);
  loaded.inner.feedEnterOnMutation(added(feed, row(feed, 8, 0)));
  assert.equal(enterings(loaded).length, 0, "первые мгновения в чате — тишина");
});

test("#9165: «Уменьшить движение» — без анимации", () => {
  const loaded = feedStand();
  loaded.win.__reducedMotion = true;
  loaded.inner.feedEnterOnMutation(added(loaded.parts.feed, row(loaded.parts.feed, 4, 0)));
  assert.equal(enterings(loaded).length, 0);
  assert.equal(loaded.inner.feedEnterState.still, 1);
});

test("#9165: блок идущего ответа, дописанный в конец, — только прозрачностью; замена, строчный кусок, не в конце, законченный ответ — нет", () => {
  const loaded = feedStand();
  const feed = loaded.parts.feed;
  // Строку ответа заводим ДО отсчёта: она не новая.
  const message = feed.children[3].add("div", { attrs: { "data-cds": "AssistantMessage", "data-is-streaming": "true" } });
  const prose = message.add("div", { attrs: { "data-cds": "Prose" } });
  prose.add("p", { text: "первый" });
  const block = prose.add("p", { text: "второй" });
  loaded.inner.feedEnterOnMutation(added(prose, block));
  let list = enterings(loaded);
  assert.equal(list.length, 1);
  assert.equal(list[0].node, block);
  assert.deepEqual(plain(list[0].frames), [{ opacity: 0 }, { opacity: 1 }], "без сдвига — текст не прыгает");
  assert.equal(list[0].options.duration, 180);
  const swapped = prose.add("p", { text: "заменён" });
  loaded.inner.feedEnterOnMutation([{ type: "childList", target: prose, addedNodes: [swapped], removedNodes: [block] }]);
  const span = swapped.add("span", { text: "кусок" });
  loaded.inner.feedEnterOnMutation(added(swapped, span));
  const early = prose.add("ul");
  prose.add("p", { text: "хвост" });
  loaded.inner.feedEnterOnMutation(added(prose, early));
  message.setAttribute("data-is-streaming", "false");
  const done = prose.add("p", { text: "после" });
  loaded.inner.feedEnterOnMutation(added(prose, done));
  list = enterings(loaded);
  assert.equal(list.length, 1, "мигания при стриминге нет");
  assert.equal(loaded.inner.feedEnterState.blocks, 1);
});
