// Пожелания 03.11.2026, п. 9 (раздел 12х²ᵈ inject.js): на Windows при идущем чате есть зарубки, на Маке нет. Зарубки —
// родная дорожка Claude, она рисуется только при главе от модели (mark_chapter) или закреплённой человеком. Нет её —
// страница ставит основу той же формы, и каждый ответ становится главой раздела 660.
//
// Стенд — как в chapters-9758: лента с пропсом entries, но родной дорожки нет. Тело панели — .epitaxy-chat-panel-body.
//
// Что проверяется:
//   1) мало ответов — основы нет; два и больше — основа той же формы, что у Claude, в теле панели, с главами;
//   2) нажатие ведёт к ответу, галочка и звёздочка работают, текущая глава по линии чтения;
//   3) пришла родная дорожка — основа снята, свои главы переехали; ушла — основа вернулась;
//   4) нет тела панели — тихо ничего; чат ещё пишется — без пишущегося ответа;
//   5) проход идемпотентен, повторная установка и dispose не оставляют следов.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_chapter-host";
const HOST = "data-myclaude-ch-host";
const OWN = "data-myclaude-ch-own";
const CHECK = "data-myclaude-ch-check";
const STAR = "data-myclaude-ch-star";
const MINE = "data-myclaude-ch-mine";
const ROW_H = 100;

const text = value => ({ kind: "text", text: value });
const LONG = name => `**✅ ${name} готово, проверено на стенде и лежит на месте.**`;
const ENTRIES = () => [
  { id: "u0", author: "user", items: [text("начнём")] },
  { id: "A1", author: "assistant", items: [text(LONG("Первое"))] },
  { id: "u2", author: "user", items: [text("дальше")] },
  { id: "A3", author: "assistant", items: [text(LONG("Второе"))] },
  { id: "u4", author: "user", items: [text("ок")] },
  { id: "A5", author: "assistant", items: [text("Готово.")] },
];

const page = ({ entries = ENTRIES(), panel = true, responding = false } = {}) => {
  const nodes = { feedRows: new Map() };
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({});
      nodes.panel = dom.document.body.add("div", { class: panel ? "epitaxy-chat-panel-body flex-1 min-h-0 relative" : "h-full", rect: { left: 8, top: 0, width: 800, height: 600 } });
      nodes.feed = nodes.panel.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: { left: 8, top: 0, width: 800, height: 600 } });
      nodes.feed.clientHeight = 600;
      nodes.feed.scrollHeight = entries.length * ROW_H + 600;
      entries.forEach((entry, at) => {
        const row = nodes.feed.add("div", {
          attrs: { "data-testid": "transcript-row", "data-index": String(at), "data-perf-row": entry.author === "user" ? "human" : "assistant", "data-perf-row-streaming": "false" },
          rect: { left: 8, top: at * ROW_H, width: 800, height: ROW_H },
        });
        const column = row.add("div", { attrs: { "data-epitaxy-entry": entry.id, "data-epitaxy-entry-index": String(at) } });
        if (entry.author === "assistant") column.add("div", { attrs: { "data-cds": "AssistantMessage", "data-turn-key": entry.id } }).add("div").add("div", { attrs: { "data-cds": "Prose" } }).add("p", { text: "ответ" });
        else column.add("div", { attrs: { "data-cds": "UserMessage" } }).add("div", { class: "text-primary" }).add("p", { text: "вопрос" });
        nodes.feedRows.set(entry.id, row);
      });
      nodes.feed.__reactFiber$test = { memoizedProps: {}, return: { memoizedProps: { entries, isResponding: responding, olderHistoryAbove: false }, return: null } };
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const tick = () => { loaded.inner.readTick(); loaded.inner.chHostTick(); loaded.inner.chTick(); };
  tick();
  return { loaded, nodes, tick };
};
const hostOf = loaded => loaded.dom.query(`[${HOST}]`);
const partsOf = host => {
  const nav = host.firstElementChild;
  const [rail, menu] = [...nav.children];
  return { nav, rail, menu, list: menu.firstElementChild };
};
const status = loaded => plain(loaded.api.status().chHost);
const send = (loaded, type, target, extra = {}) => !loaded.document.dispatchEvent({ type, target, button: 0, detail: 1, clientX: 20, clientY: 120, ...extra });
const buttonOf = row => [...row.children].find(node => node.tagName === "BUTTON" && !node.hasAttribute(CHECK) && !node.hasAttribute(STAR));
const css = loaded => String(loaded.dom.query("#myclaude-input-handle-style").textContent ?? "");
// Родная дорожка Claude с одной главой в ходе A1 — как после mark_chapter.
const native = (dom, nodes) => {
  const toc = nodes.panel.add("div", { class: "epitaxy-toc absolute pointer-events-none" });
  const nav = toc.add("nav", { attrs: { "aria-label": "Session chapters", tabindex: "0" }, rect: { left: 8, top: 48, width: 32, height: 400 } });
  const rail = nav.add("ol", { attrs: { "aria-hidden": "true" }, class: "flex flex-col" });
  const list = nav.add("div", { class: "absolute start-0 top-0" }).add("ol", { attrs: { role: "list" } });
  rail.add("li", { class: "h-[8px] flex items-center" }).add("span", { class: "block rounded-full bg-alpha-8" });
  const button = list.add("li").add("button", { attrs: { type: "button" }, class: "w-full flex text-secondary" });
  button.add("span", { attrs: { "aria-hidden": "true" }, class: "block" });
  button.add("span", { class: "flex-1", text: "Глава" });
  button.__reactFiber$test = { memoizedProps: {}, return: { memoizedProps: { chapter: { id: "ch-1", title: "Глава", source: "claude", entryId: "A1", entryIndex: 1 } }, return: null } };
  return { toc, nav, rail, list };
};

test("п. 9: один ответ — основы нет; ответов два и больше — основа той же формы, что у Claude, в теле панели", () => {
  const few = page({ entries: ENTRIES().slice(0, 2) });
  assert.equal(hostOf(few.loaded), null, "одна глава — не оглавление");
  assert.deepEqual(status(few.loaded), { on: false, plan: 1, why: "мало ответов" });

  const { loaded, nodes } = page();
  const host = hostOf(loaded);
  assert.ok(host, "основа стоит");
  assert.equal(host.parentNode, nodes.panel);
  assert.equal(host.matches(".epitaxy-toc"), true, "правила дорожки и разделы 660, 662 берут её как свою");
  const { nav, rail, menu, list } = partsOf(host);
  assert.equal(nav.tagName, "NAV");
  assert.equal(nav.getAttribute("aria-label"), "Главы чата");
  assert.equal(nav.getAttribute("tabindex"), "0", "с клавиатуры — как у Claude");
  assert.equal(rail.getAttribute("aria-hidden"), "true");
  assert.equal(menu.tagName, "DIV");
  assert.equal(list.getAttribute("role"), "list");
  assert.deepEqual(status(loaded), { on: true, plan: 2, why: null });
  assert.deepEqual([...list.children].map(row => row.__myclaudeOwn), ["A1", "A3"], "короткий «Готово.» — без главы");
  assert.equal([...rail.children].every(line => line.hasAttribute(OWN)), true);
  const chapters = plain(loaded.api.status().chapters);
  assert.equal(chapters.own, 2);
  assert.equal(chapters.count, 2);
  assert.equal(chapters.lastError, null);
});

test("п. 9: главы основы — как у Claude: полоска, название, переход к ответу, галочка, звёздочка, текущая", () => {
  const { loaded, nodes } = page();
  const { nav, rail, list } = partsOf(hostOf(loaded));
  const [first] = [...list.children];
  assert.match(buttonOf(first).textContent, /Первое готово/);
  assert.ok([...first.children].some(node => node.hasAttribute(CHECK)) && [...first.children].some(node => node.hasAttribute(STAR)));
  assert.match(rail.children[0].firstElementChild.getAttribute("class"), /bg-alpha-[38]/);

  const jumps = loaded.inner.chState.jumps;
  assert.equal(send(loaded, "click", buttonOf(first)), true, "нажатие — наше, до Claude не идёт");
  assert.equal(loaded.inner.chState.jumps, jumps + 1, "переход к ответу");

  const check = [...first.children].find(node => node.hasAttribute(CHECK));
  send(loaded, "click", check);
  assert.equal(check.getAttribute("aria-pressed"), "true");
  assert.equal(plain(loaded.api.status().chapters).read, 1);

  // Линия чтения выше первого ответа — своей текущей нет; прокрутка довела её до A1.
  assert.equal(nav.hasAttribute(MINE), false, "над первым ответом текущей нет");
  nodes.feed.scrollTop = ROW_H + 10;
  nodes.feedRows.forEach((row, id) => { row.rect = { ...row.rect, top: ENTRIES().findIndex(entry => entry.id === id) * ROW_H - nodes.feed.scrollTop }; });
  loaded.inner.chTick();
  assert.equal(nav.hasAttribute(MINE), true, "текущая — своя глава у линии чтения");
  assert.match(rail.children[0].firstElementChild.getAttribute("class"), /bg-alpha-8/);
});

test("п. 9: родная дорожка появилась — основа снята, главы в ней; ушла — основа вернулась", () => {
  const { loaded, nodes, tick } = page();
  const claude = native(loaded.dom, nodes);
  const entries = ENTRIES();
  entries[1] = { ...entries[1], items: [{ kind: "chapter", id: "ch-1", title: "Глава" }, ...entries[1].items] };
  nodes.feed.__reactFiber$test.return.memoizedProps = { entries, isResponding: false, olderHistoryAbove: false };
  tick();
  assert.equal(hostOf(loaded), null, "вторая дорожка не нужна");
  assert.deepEqual(plain(loaded.api.status().chHost).why, "есть дорожка Claude");
  assert.deepEqual([...claude.list.children].map(row => row.__myclaudeOwn ?? "claude"), ["claude", "A3"]);
  assert.equal(plain(loaded.api.status().chapters).own, 1);

  claude.toc.remove();
  nodes.feed.__reactFiber$test.return.memoizedProps = { entries: ENTRIES(), isResponding: false, olderHistoryAbove: false };
  tick();
  assert.ok(hostOf(loaded), "человек снял главу — дорожка осталась нашей");
  assert.deepEqual([...partsOf(hostOf(loaded)).list.children].map(row => row.__myclaudeOwn), ["A1", "A3"]);
});

test("п. 9: панели нет — тихо ничего; React выбросил основу — встала заново; пишущийся ответ без главы", () => {
  const bare = page({ panel: false });
  assert.equal(hostOf(bare.loaded), null);
  assert.deepEqual(status(bare.loaded), { on: false, plan: 2, why: "нет тела панели" });

  const { loaded, tick } = page();
  hostOf(loaded).remove();
  tick();
  assert.ok(hostOf(loaded), "узел встал заново");
  assert.equal(loaded.dom.queryAll(`[${HOST}]`).length, 1);

  const going = page({ entries: ENTRIES().slice(0, 4), responding: true });
  assert.equal(hostOf(going.loaded), null, "пишется второй ответ — пока одна глава");
  assert.equal(status(going.loaded).plan, 1);
});

test("п. 9: проход ничего не двигает, повторная установка и dispose без следа, вид задан правилами", () => {
  const { loaded, nodes, tick } = page();
  const host = hostOf(loaded);
  const lines = [...partsOf(host).list.children];
  tick();
  tick();
  assert.equal(hostOf(loaded), host, "тот же узел");
  assert.deepEqual([...partsOf(host).list.children], lines);
  assert.match(css(loaded), /\.epitaxy-toc\[data-myclaude-ch-host\]\{position:absolute;inset-inline-start:0;bottom:32px;z-index:11/);
  assert.match(css(loaded), /\.epitaxy-toc\[data-myclaude-ch-host\]>nav>ol\[aria-hidden="true"\]\{[^}]*pointer-events:auto/);

  const again = loaded.reload();
  assert.equal(again.error, null, String(again.error?.stack ?? again.error));
  assert.equal(hostOf(loaded), null, "прежняя основа снята");
  loaded.inner.readTick();
  loaded.inner.chHostTick();
  loaded.inner.chTick();
  assert.equal(loaded.dom.queryAll(`[${HOST}]`).length, 1, "встала одна");
  assert.equal(partsOf(hostOf(loaded)).list.children.length, 2);

  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`[${HOST}],[${OWN}],[${CHECK}],[${STAR}]`).length, 0);
  assert.equal(nodes.panel.children.length, 1, "в теле панели — только лента");
});
