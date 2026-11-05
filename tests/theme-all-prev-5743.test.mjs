// #5743: «всем окнам» — подложка. Тема (шрифт, размер, вид) всем окнам снимает личные слои чатов,
// но складывает их на склад; снятие общего слоя («Как у Claude» → «Вернуть» в «Оформлении» панели,
// команда theme scope:"all" со слоем null) отдаёт их назад.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const MAP_KEY = "myclaude-themes-v1";
const PREV_KEY = "myclaude-themes-prev-v1";
const SESSION_KEY = "myclaude-theme-v1";
const theme = (id, accent = "#2299ff") => ({
  id, name: id, type: "dark",
  palette: { accent, background: "#001122", foreground: "#eeffff", sidebar: "#000811", panel: "#00223a", muted: "#88aabb" },
});
const font = (family = "SF Mono") => ({ id: family, family, mono: true });
const readMap = win => JSON.parse(win.localStorage.getItem(MAP_KEY) ?? "null");
let seq = 0;
const all = (loaded, layers) => loaded.dom.command({ id: `a${seq += 1}`, action: "theme", at: "now", scope: "all", ...layers });
const chats = () => ({
  "id:local_a": { theme: theme("а") },
  "chat:Альфа": { theme: theme("а"), by: "local_a" },
  "id:local_b": { theme: theme("б"), font: font("Menlo") },
  "id:local_c": { theme: "none" },
});
const window3 = () => loadInject({
  title: "Альфа", href: "https://claude.ai/epitaxy/local_a",
  storage: { local: { [MAP_KEY]: JSON.stringify(chats()) } },
});

test("#5743: тема всем, затем «Как у Claude» всем — личные цвета чатов вернулись", () => {
  const loaded = window3();
  all(loaded, { theme: theme("общая") });
  let map = readMap(loaded.win);
  assert.equal(map["*"].theme.id, "общая");
  assert.equal(map["id:local_a"], undefined, "своя тема снята — красит общая");
  assert.equal(map["id:local_b"].font.family, "Menlo", "чужой слой не тронут");
  assert.equal(loaded.api.status().theme.id, "общая");
  assert.ok(loaded.win.localStorage.getItem(PREV_KEY), "снятое лежит на складе");

  all(loaded, { theme: null });
  map = readMap(loaded.win);
  assert.equal(map["*"], undefined, "общей записи больше нет");
  assert.equal(map["id:local_a"].theme.id, "а");
  assert.equal(map["chat:Альфа"].theme.id, "а");
  assert.equal(map["chat:Альфа"].by, "local_a", "владелец тени вернулся вместе со слоем");
  assert.equal(map["id:local_b"].theme.id, "б");
  assert.equal(map["id:local_b"].font.family, "Menlo");
  assert.equal(map["id:local_c"].theme, "none", "и явный «как у Claude» чата — тоже его выбор");
  assert.equal(loaded.api.status().theme.id, "а", "окно на экране — снова в своём цвете");
  assert.equal(loaded.api.status().theme.source, "chat");
});

test("#5743: смена общей темы не стирает склад; второе окно с той же командой ничего не ломает", () => {
  const loaded = window3();
  all(loaded, { theme: theme("синяя") });
  all(loaded, { theme: theme("красная") });
  all(loaded, { theme: theme("красная") });
  all(loaded, { theme: null });
  // Ту же команду исполняет каждое окно: повтор не снимает только что вернувшееся.
  all(loaded, { theme: null });
  const map = readMap(loaded.win);
  assert.equal(map["id:local_a"].theme.id, "а");
  assert.equal(map["id:local_b"].theme.id, "б");
});

test("#5743: цвет, выбранный чату поверх общего, после «Вернуть» остаётся его", () => {
  const loaded = window3();
  all(loaded, { theme: theme("общая") });
  loaded.dom.command({ id: "w1", action: "theme", at: "now", scope: "window", title: "Альфа", theme: theme("новая") });
  assert.equal(loaded.api.status().theme.id, "новая");
  all(loaded, { theme: null });
  assert.equal(readMap(loaded.win)["id:local_a"].theme.id, "новая", "последний выбор сильнее склада");
  assert.equal(loaded.api.status().theme.id, "новая");
});

test("#5743: склад заводится заново, когда общего слоя не было", () => {
  const loaded = window3();
  all(loaded, { theme: theme("общая") });
  all(loaded, { theme: null });
  // Чату сняли цвет руками, пока общего слоя нет, — следующий круг его не воскрешает.
  loaded.dom.command({ id: "w2", action: "theme", at: "now", scope: "window", title: "Альфа", theme: null });
  all(loaded, { theme: theme("общая") });
  all(loaded, { theme: null });
  const map = readMap(loaded.win);
  assert.equal(map["id:local_a"]?.theme, undefined, "снятый руками цвет не вернулся");
  assert.equal(map["id:local_b"].theme.id, "б");
});

test("#5743: шрифт всем и обратно — личный шрифт чата вернулся, темы не тронуты", () => {
  const loaded = window3();
  all(loaded, { font: font("Avenir") });
  assert.equal(readMap(loaded.win)["id:local_b"].font, undefined);
  all(loaded, { font: null });
  const map = readMap(loaded.win);
  assert.equal(map["id:local_b"].font.family, "Menlo");
  assert.equal(map["id:local_a"].theme.id, "а");
});

test("#5743: домашний экран — цвет окна `main` возвращается, сессия его не закрывает", () => {
  const loaded = loadInject({
    title: "Claude", href: "https://claude.ai/epitaxy",
    storage: {
      local: { [MAP_KEY]: JSON.stringify({ main: { theme: theme("окно") } }) },
      session: { [SESSION_KEY]: JSON.stringify({ key: "main", theme: theme("окно") }) },
    },
  });
  assert.equal(loaded.api.status().theme.id, "окно");
  all(loaded, { theme: theme("общая") });
  assert.equal(loaded.api.status().theme.id, "общая");
  all(loaded, { theme: null });
  assert.equal(readMap(loaded.win).main.theme.id, "окно");
  assert.equal(loaded.api.status().theme.id, "окно");
  assert.equal(JSON.parse(loaded.win.sessionStorage.getItem(SESSION_KEY)).theme, undefined, "в сессии слоя нет вовсе");
});
