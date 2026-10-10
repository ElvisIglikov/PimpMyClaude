// Плашки заголовков групп проектов в списке слева (раздел 2е inject.js, #7244).
//
// Слово Элвиса 23.09: названия проектов (заголовки групп ChinaAI, Dictator) —
// такими же цветами, как в Pinned, прямоугольничками со скруглёнными углами; по
// наведению у группы появляется стрелка ⌄ — её не задеть. Стенд — разметка
// заголовка группы Claude 2.2553 (бандл сайдбара 23.09):
// [data-sidebar-group-label] > button[data-group-toggle] > span[data-group-name]
// + svg[data-group-caret], справа кнопки группы. Метится только span имени,
// плашку рисует CSS тенью — места в раскладке она не занимает.
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

test("#7244: имя группы-проекта получает плашку цвета проекта; «Today» — нет", () => {
  const { got } = page();
  assert.equal(got.china.label.getAttribute(ATTR), "ChinaAI");
  assert.equal(got.dict.label.getAttribute(ATTR), "Dictator", "группа по имени папки, а не репозитория");
  assert.equal(got.today.label.hasAttribute(ATTR), false, "группа по дате — не проект");
  assert.equal(got.today.label.style.getPropertyValue(TINT), "");
});

test("#7244: цвет — тот же расчёт, что у Pinned: запись окна чата, иначе авто-тон папки", () => {
  const palette = accent => ({ theme: { id: "x", name: "x", type: "dark",
    palette: { accent, background: "#111111", foreground: "#eeeeee", sidebar: "#0a0a0a", panel: "#1a1a1a", muted: "#888888" } } });
  const { loaded, got } = page({ map: { "id:local_c": palette("#ff8800") } });
  assert.equal(got.china.label.style.getPropertyValue(TINT), "color-mix(in srgb, #ff8800 40%, transparent)");
  assert.equal(got.dict.label.style.getPropertyValue(TINT),
    `color-mix(in srgb, hsl(${loaded.inner.pinnedHue("Dictator")} 80% 62%) 40%, transparent)`);
});

test("#7244: стрелка ⌄ и кнопки группы не тронуты — ни метки, ни стиля", () => {
  const { got } = page();
  for (const node of [got.china.header, got.china.toggle, got.china.caret, got.china.plus]) {
    assert.equal(node.hasAttribute(ATTR), false);
    assert.equal(node.style.getPropertyValue(TINT), "");
  }
  assert.equal(got.china.label.textContent, "ChinaAI", "текст имени не меняется");
});

test("#7244: плашка — тенью, без полей и отступов: стрелка и кнопки не сдвигаются", () => {
  const { loaded } = page();
  const css = String(loaded.dom.query(STYLE)?.textContent ?? "");
  const rule = css.split("\n").find(line => line.includes(`[data-group-name][${ATTR}]`));
  assert.ok(rule, "правила плашки нет");
  assert.ok(rule.startsWith("[data-sidebar-group-label] "), "только в заголовке группы");
  assert.match(rule, new RegExp(`background-color:var\\(${TINT}\\)`));
  assert.match(rule, /border-radius:6px/, "скругление как у чипа Pinned");
  assert.match(rule, /box-shadow:-3px 0 0 0 var\(--myclaude-folder-tint\),3px 0 0 0 var\(--myclaude-folder-tint\)/);
  assert.doesNotMatch(rule, /padding|margin|width|display|position/, "ничего, что двигает соседей");
});

test("#7244: React пересоздал заголовок — плашка встаёт заново; группа перестала быть проектом — снята; dispose снимает", () => {
  const { loaded, got } = page();
  let clock = loaded.win.performance.now();
  loaded.win.performance.now = () => clock;
  got.china.label.remove();
  const fresh = got.china.toggle.add("span", { attrs: { "data-group-name": "" }, text: "ChinaAI" });
  clock += 1500;
  pass(loaded);
  assert.equal(fresh.getAttribute(ATTR), "ChinaAI");
  loaded.dom.retext(got.dict.label, "Yesterday");
  clock += 1500;
  pass(loaded);
  assert.equal(got.dict.label.hasAttribute(ATTR), false);
  assert.equal(got.dict.label.style.getPropertyValue(TINT), "");
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`[${ATTR}]`).length, 0);
  assert.equal(fresh.style.getPropertyValue(TINT), "");
});

test("#7244: попап без своего списка — ничего не метит", () => {
  const { loaded } = page({ href: "about:blank" });
  assert.equal(loaded.dom.queryAll(`[${ATTR}]`).length, 0);
});
