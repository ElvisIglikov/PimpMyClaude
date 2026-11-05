// Плашки заголовков групп проектов в списке слева (раздел 2е inject.js, #7244).
//
// Слово Элвиса 23.09: названия проектов (заголовки групп ChinaAI, Dictator) —
// такими же цветами, как в Pinned, прямоугольничками со скруглёнными углами; по
// наведению у группы появляется стрелка ⌄ — её не задеть. Стенд — разметка
// заголовка группы Claude 2.2553 (бандл сайдбара 23.09):
// [data-sidebar-group-label] > button[data-group-toggle] > span[data-group-name]
// + svg[data-group-caret], справа кнопки группы. Метится только span имени,
// плашку рисует CSS тенью — места в раскладке она не занимает.
// С page-64 (слово Элвиса 11.10 01:40: «названия проектов не надо цветом выводить») цвет выключен,
// в WF248 снят и код: заголовки групп — как у Claude, страница их не метит и не красит.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const ATTR = "data-myclaude-project";
const TINT = "--myclaude-folder-tint";
const STYLE = "#myclaude-input-handle-style";
const MAP_KEY = "myclaude-themes-v1";

const addRow = (list, id, title, data) => {
  const row = list.add("div", { attrs: { "data-row-key": `code:${id}` } });
  const label = row.add("div", { attrs: { "data-row": "" } }).add("button", { attrs: { "data-row-main-button": "" } })
    .add("span", { attrs: { "data-row-label": "" } }).add("span", { class: "dframe-fade-label" });
  label.add("span", { class: "inline-block", text: title });
  const session = { ref: { kind: "code", id }, title, source: { kind: "code", data } };
  row["__reactFiber$test"] = { memoizedProps: {}, return: { memoizedProps: { session }, return: null } };
  return row;
};
const addGroup = (dom, list, name) => {
  const section = list.add("div", { class: "flex flex-col" });
  const header = section.add("div", { attrs: { "data-sidebar-group-label": "" } });
  const toggle = header.add("button", { attrs: { "data-group-toggle": "", "aria-expanded": "true" } });
  const label = dom.leaf(toggle, "span", name, { attrs: { "data-group-name": "" }, class: "min-w-0 truncate" });
  const caret = toggle.add("svg", { attrs: { "data-group-caret": "" } });
  const plus = header.add("button", { attrs: { "aria-label": "New session" } });
  return { section, header, toggle, label, caret, plus };
};
const repo = (name, cwd = `/Users/dev/Projects/${name}`) => ({ cwd, repoInfo: { owner: "ElvisIglikov", name, branch: "main" } });

const page = ({ href = "https://claude.ai/epitaxy/local_home", map = null } = {}) => {
  const got = {};
  const loaded = loadInject({
    href,
    title: "Claude",
    storage: map ? { local: { [MAP_KEY]: JSON.stringify(map) } } : undefined,
    html: dom => {
      const parts = dom.composer();
      const bar = dom.document.body.add("div", { attrs: { "data-testid": "sidebar" } });
      const pin = bar.add("div", { attrs: { "data-testid": "sidebar-pinned" } });
      addRow(pin, "local_p", "Закреплённый", repo("VkusnoffKz"));
      const recents = bar.add("div", { attrs: { "data-testid": "sidebar-recents" } });
      got.china = addGroup(dom, recents, "ChinaAI");
      addRow(got.china.section, "local_c", "Арена", repo("ChinaAI"));
      got.dict = addGroup(dom, recents, "Dictator");
      // Папка и репозиторий зовутся по-разному — группа подписана папкой.
      addRow(got.dict.section, "local_d", "Диктовка", repo("dictator-app", "/Users/dev/Projects/Dictator"));
      got.today = addGroup(dom, recents, "Today");
      addRow(got.today.section, "local_t", "Разное", repo("VkusnoffKz"));
      got.recents = recents;
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return { loaded, got };
};
const pass = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};

test("#7244: попап без своего списка — ничего не метит", () => {
  const { loaded } = page({ href: "about:blank" });
  assert.equal(loaded.dom.queryAll(`[${ATTR}]`).length, 0);
});

test("page-64: заголовки групп — как у Claude: ни метки, ни цвета, ни правила", () => {
  const palette = accent => ({ theme: { id: "x", name: "x", type: "dark",
    palette: { accent, background: "#111111", foreground: "#eeeeee", sidebar: "#0a0a0a", panel: "#1a1a1a", muted: "#888888" } } });
  const { loaded, got } = page({ map: { "id:local_c": palette("#ff8800") } });
  pass(loaded);
  assert.equal(loaded.dom.queryAll(`[${ATTR}]`).length, 0, "меток проекта нет");
  for (const group of [got.china, got.dict, got.today]) assert.equal(group.label.style.getPropertyValue(TINT), "");
  assert.equal(got.china.label.textContent, "ChinaAI", "текст имени не меняется");
  const css = String(loaded.dom.query(STYLE)?.textContent ?? "");
  assert.ok(css.includes("data-myclaude-folder"), "таблица правил на месте");
  assert.equal(css.includes(ATTR), false, "правила плашки группы нет (WF248)");
  assert.equal(css.includes(TINT), false, "переменной цвета проекта нет");
});
