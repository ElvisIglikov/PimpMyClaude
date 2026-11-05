// #10527: слепки живой разметки Claude (tests/fixtures/claude-dom/<версия>-<вид>.json, формат --slice контракта
// К-HEALTH) — стаб из слепка, на нём страница и health(). Класс поломок «Claude обновился, разметка разошлась»
// (С1–С3, С12) офлайн не ловился: стенды строились по нашей картине разметки. Слепок — разметка, какой её
// отдал живой Claude; обновился Claude — снят новый слепок — починка — слепок остаётся тестом.
//
// Проверка сторожа на прошлом: тот же слепок 3.1623 и страница до починки #10500 (dist/rollback/
// inject-wf272-page-98.js) дают красные wide и fold — ровно то, что Элвис видел 22.10 («поле ввода справа должно
// быть… кнопка свёртки перестала работать»). Страница прошлого health() не знает: проверку берём у нынешней
// (healthRun — без замыкания страницы) и гоняем в окне прошлой.
//
// Чего слепок не несёт и что сцена кладёт сама (честно — это не проверка Claude):
//  - CSS. Флаг широкого вида и сетку ставит wideByCss по таблице той страницы, что стоит в окне (контейнерный
//    запрос раздела 2а): у прошлой — её примета формы, у нынешней — её. Ширина контейнера — рамка плитки.
//  - Вычисленные стили. Поле слева у названия чата (px-md кнопки Claude) — 12: замер живого окна 22.10 (название
//    524 + 12 = текст поля 536). Подложки, прозрачность и перекрытие настоящими слоями (sidebarButton: backing,
//    look) слепком не проверяются — их смотрит живой прогон pimp.py live-check.
//  - Текст и React-волокна. Проект чата (папка в углу) даёт строка списка слева, как в стендах (sidebarRow).
//  - Время. Claude 3.1623 рисует строку модели (ChatComposerChin) позже поля: сцена вынимает её до установки
//    страницы и возвращает после первого прохода — так это было в окне.
import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import { createDom } from "./dom.mjs";
import { injectSource, plain } from "./load.mjs";
import { ownRects, pointHits, settle, wideByCss } from "./stands.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SLICES = path.join(ROOT, "tests", "fixtures", "claude-dom");
const PAST = path.join(ROOT, "dist", "rollback", "inject-wf272-page-98.js");
const CHAT = "local_0f3a9c1e-7b2d-4e6f-8a1b-5c4d3e2f1a0b";
const TITLE_PAD = "12px";

// Узел слепка → узел стаба: теги, классы, data-testid, data-cds, role, aria-label, атрибуты белого списка, рамка.
const grow = (parent, node) => {
  const attrs = { ...(node.a ?? {}) };
  if (node.tid) attrs["data-testid"] = node.tid;
  if (node.cds) attrs["data-cds"] = node.cds;
  if (node.role) attrs.role = node.role;
  if (node.aria) attrs["aria-label"] = node.aria;
  const [left, top, width, height] = node.r;
  const el = parent.add(node.t, { class: (node.c ?? []).join(" "), id: node.id, attrs, rect: { left, top, width, height } });
  if ("data-pane-title" in attrs) el.computed = { ...el.computed, "padding-left": TITLE_PAD };
  for (const kid of node.k ?? []) grow(el, kid);
  return el;
};

// Окно из слепка со страницей source. chinLater — строка модели появляется после первого прохода.
const replay = (slice, source, { chinLater = true } = {}) => {
  const [width, height] = slice.viewport;
  const dom = createDom({ href: `https://claude.ai/epitaxy/${CHAT}`, title: "Claude", viewport: { width, height } });
  const body = dom.document.body;
  if (slice.root.c) body.className = slice.root.c.join(" ");
  for (const kid of slice.root.k ?? []) grow(body, kid);
  // Строка своего чата в списке слева — проект для угла (раздел 2ж): в слепок волокна не идут.
  const list = dom.document.querySelector('[data-testid="sidebar"]');
  assert.ok(list, "в слепке нет списка чатов [data-testid=sidebar]");
  const row = list.add("div", { attrs: { "data-row-key": `code:${CHAT}` } });
  row["__reactFiber$test"] = { memoizedProps: { session: { ref: { kind: "code", id: CHAT }, title: "Claude",
    source: { kind: "code", data: { cwd: "/Users/dev/Projects/PimpMyClaude", repoInfo: { name: "PimpMyClaude" } } } } }, return: null };
  const chin = dom.document.querySelector('[data-cds="ChatComposerChin"]');
  assert.ok(chin, "в слепке нет строки модели");
  const home = { parent: chin.parentElement, next: chin.nextElementSibling };
  if (chinLater) chin.remove();
  const win = dom.window;
  let inner = null;
  win.__myclaudeTest = value => { inner = value; };
  vm.createContext(win);
  vm.runInContext(source, win, { filename: "replay-page.js" });
  const loaded = { dom, win, document: dom.document, get api() { return win.__myclaude; }, get inner() { return inner; } };
  const pass = () => { wideByCss(loaded); settle(loaded); settle(loaded); };
  pass();
  if (chinLater) { home.parent.insertBefore(chin, home.next); pass(); }
  ownRects(dom);
  pointHits(dom);
  return loaded;
};

// Проверка нынешней страницы — в любом окне: её текст и данные из люка, status() — той страницы, что в окне.
const now = (() => {
  const dom = createDom({ href: `https://claude.ai/epitaxy/${CHAT}` });
  let inner = null;
  dom.window.__myclaudeTest = value => { inner = value; };
  vm.createContext(dom.window);
  vm.runInContext(injectSource(), dom.window);
  return { source: inner.healthRun.toString(), page: JSON.parse(JSON.stringify(inner.HEALTH_PAGE)) };
})();
const healthIn = loaded => {
  const run = vm.runInContext(`(${now.source})`, loaded.win);
  const status = loaded.api.status();
  return plain(run(loaded.win, { ...now.page, version: status.version, status }));
};
const verdicts = result => Object.fromEntries(result.checks.map(item => [item.id, item.ok ? (item.skip ? `– ${item.skip}` : "✓") : item.why]));

const slices = existsSync(SLICES) ? readdirSync(SLICES).filter(name => name.endsWith(".json")).sort() : [];

test("слепки: есть хоть один, формат — контракт --slice, текста нет", { skip: !existsSync(SLICES) && "нет tests/fixtures/claude-dom (открытая копия)" }, () => {
  assert.ok(slices.length > 0, "tests/fixtures/claude-dom пуст");
  for (const name of slices) {
    const slice = JSON.parse(readFileSync(path.join(SLICES, name), "utf8"));
    assert.deepEqual(Object.keys(slice), ["v", "claude", "page", "view", "at", "viewport", "dpr", "root"], name);
    assert.equal(name, `${slice.claude.split(".").slice(0, 2).join(".")}-${slice.view}.json`, "имя файла — <версия Claude>-<вид>");
    const ORDER = ["t", "id", "c", "tid", "cds", "role", "aria", "a", "r", "k"];
    const walk = node => {
      const keys = Object.keys(node);
      assert.deepEqual(keys, ORDER.filter(key => key in node), `${name}: ключи узла по порядку`);
      assert.ok(!String(node.id ?? "").startsWith("myclaude-"), `${name}: наш узел в слепке`);
      for (const value of [...(node.c ?? []), node.tid, node.cds, node.role, ...Object.values(node.a ?? {})]) {
        assert.ok(!/[А-Яа-яЁё]/.test(String(value ?? "")), `${name}: кириллица в слепке — «${value}»`);
      }
      for (const kid of node.k ?? []) walk(kid);
    };
    walk(slice.root);
  }
});

for (const name of slices) {
  const slice = JSON.parse(readFileSync(path.join(SLICES, name), "utf8"));
  test(`слепок ${name}: нынешняя страница — anchors, wide, fold, title зелёные`, () => {
    const loaded = replay(slice, injectSource());
    const result = plain(loaded.api.health());
    const got = verdicts(result);
    for (const id of ["anchors", "wide", "fold", "title"]) assert.equal(got[id], "✓", `${id}: ${JSON.stringify(got)}`);
    assert.equal(result.wide, slice.view !== "main-narrow", "вид слепка и флаг страницы");
    // Тот же ответ у проверки, вынутой из страницы (так её гоняют прошлые страницы и живое окно).
    const standalone = healthIn(loaded);
    assert.deepEqual({ ...verdicts(standalone), install: null }, { ...got, install: null });
  });
}

test("сторож на прошлом: слепок 3.1623 и страница wf272-page-98 — красные wide и fold (#10500)", { skip: (!existsSync(PAST) && "нет dist/rollback/inject-wf272-page-98.js") || (!slices.includes("3.1623-main-wide.json") && "нет слепка 3.1623-main-wide") }, () => {
  const slice = JSON.parse(readFileSync(path.join(SLICES, "3.1623-main-wide.json"), "utf8"));
  const loaded = replay(slice, readFileSync(PAST, "utf8"));
  assert.equal(loaded.api.status().version, "wf272-page-98");
  const result = healthIn(loaded);
  const got = verdicts(result);
  assert.ok(result.red.includes("wide"), JSON.stringify(got));
  assert.ok(result.red.includes("fold"), JSON.stringify(got));
  assert.equal(got.wide, `flag: плитка ${slice.root.k ? Math.round(loaded.document.querySelector(".epitaxy-chat-panel").getBoundingClientRect().width) : 0}, флаг 0`,
    "широкий вид не включился: примета формы прошлой страницы не нашла шапку в обёртках 3.1623");
  assert.equal(got.fold, "no-target: modelRow", "строка модели дорисовалась позже — прошлая страница её не нашла");
  assert.equal(got.anchors, "✓", "опоры Claude на месте — поломка в странице, а не в Claude");
});
