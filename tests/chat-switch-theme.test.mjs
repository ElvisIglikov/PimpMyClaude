// Переход между чатами в главном окне (раздел 2а inject.js, syncChatTheme; WF82, #7103).
//
// Слово Элвиса 22.09: «у двух нижних [закреплённых] тема меняется: пришли из
// зелёного — зелёная, из „Ночи кода“ — оранжевая… своей темы что ли нет?».
// Своих записей у этих чатов не было, и правило «чат без записи окно не трогает»
// оставляло им цвет того чата, откуда пришли. Теперь переход ИЗ ЧАТА В ЧАТ идёт
// полным порядком слоёв: запись чата → сессия окна → `main` → «всем», а слоя нет
// нигде — он снимается. Чат, родившийся с домашнего экрана (⌘N, «Обкэшить»),
// живёт по старому правилу: окно своего цвета не меняет.
//
// Окно в 2.2553.13 носит заголовок-заглушку «Claude» на любом чате, поэтому чат
// узнаётся только по адресу (/epitaxy/local_<id>), а смену ловит опрос сторожа
// заголовка — тик интервала стенда.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const MAP_KEY = "myclaude-themes-v1";
const SESSION_KEY = "myclaude-theme-v1";
const A = "local_aaaa-green";
const B = "local_bbbb-orange";
const C = "local_cccc-norecord";

const theme = (id, accent = "#2299ff") => ({
  id, name: id, type: "dark",
  palette: { accent, background: "#001122", foreground: "#eeffff", sidebar: "#000811", panel: "#00223a", muted: "#88aabb" },
});
const font = (family = "SF Mono") => ({ id: family, family, mono: true });

// Главное окно на чате A. У A и B свои записи, у C — никакой; у окна своя тема `main`.
const open = ({ at = A, records = {}, session = null } = {}) => {
  const map = {
    [`id:${A}`]: { theme: theme("зелёная", "#22cc55") },
    [`id:${B}`]: { theme: theme("оранжевая", "#ff8800") },
    main: { theme: theme("окно", "#8844ff") },
    ...records,
  };
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${at}`,
    title: "Claude",
    storage: {
      local: { [MAP_KEY]: JSON.stringify(map) },
      session: session ? { [SESSION_KEY]: JSON.stringify({ key: "main", ...session }) } : {},
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const router = loaded.dom.router();
  // Переход по строке сайдбара: адрес меняется, заголовок остаётся «Claude»,
  // смену чата видит опрос сторожа заголовка.
  const go = path => { router.navigate(path); loaded.dom.fireKind("interval"); };
  return { loaded, go, look: () => loaded.api.status().theme };
};

test("из чата в чат без записи — тема окна, а не цвет того чата, откуда пришли", () => {
  const { go, look } = open();
  assert.equal(look().id, "зелёная", "A в своём цвете");
  go(`/epitaxy/${C}`);
  assert.equal(look().id, "окно", "C без записи — в цвете окна");
  assert.equal(look().source, "window");
  go(`/epitaxy/${B}`);
  assert.equal(look().id, "оранжевая");
  go(`/epitaxy/${C}`);
  assert.equal(look().id, "окно", "из оранжевого — тот же вид C, путь не важен");
});

test("A → C → A и обход A → B → A: у A всегда свой цвет", () => {
  const { go, look } = open();
  go(`/epitaxy/${C}`);
  go(`/epitaxy/${A}`);
  assert.equal(look().id, "зелёная");
  assert.equal(look().source, "chat");
  go(`/epitaxy/${B}`);
  go(`/epitaxy/${A}`);
  assert.equal(look().id, "зелёная");
});

test("сессия окна сильнее `main`, как на инжекте", () => {
  const { go, look } = open({ session: { theme: theme("сессия", "#00aaff") } });
  go(`/epitaxy/${C}`);
  assert.equal(look().id, "сессия");
  assert.equal(look().source, "session");
});

test("темы окна нет нигде — слой снимается, чужой цвет не остаётся", () => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${A}`,
    title: "Claude",
    storage: { local: { [MAP_KEY]: JSON.stringify({ [`id:${A}`]: { theme: theme("зелёная"), font: font("Menlo"), frame: true } }) } },
  });
  const router = loaded.dom.router();
  assert.equal(loaded.api.status().font.family, "Menlo");
  assert.equal(loaded.api.status().frame.on, true);
  router.navigate(`/epitaxy/${C}`);
  loaded.dom.fireKind("interval");
  const status = loaded.api.status();
  assert.equal(status.theme.id, null, "тема A не переехала в C");
  assert.equal(status.font.family, null, "шрифт A не переехал в C");
  assert.equal(status.frame.on, false, "рамка A не переехала в C");
});

test("чат, родившийся с домашнего экрана, цвет окна не меняет (⌘N, «Обкэшить»)", () => {
  const { go, look } = open();
  go("/epitaxy");
  assert.equal(look().id, "зелёная", "домашний экран — окно того же цвета");
  go("/epitaxy/local_new-chat");
  assert.equal(look().id, "зелёная", "новый чат без записи остался в цвете окна, как до WF82");
});

test("живые цвета: слой темы на переходе не трогается, остальные — по порядку", () => {
  const ring = Array.from({ length: 12 }, () => ({
    accent: "#ff0000", background: "#101010", foreground: "#ffffff", sidebar: "#111111", panel: "#222222", muted: "#888888",
  }));
  const { loaded, look } = open({ records: { [`id:${A}`]: { theme: theme("зелёная"), font: font("Menlo") } } });
  // Сторож заголовка — первый интервал окна (раздел 2а стоит раньше всех): тикаем
  // только его, иначе тик круга перекрасил бы окно сам и проверка ослепла бы.
  const watch = loaded.dom.ids("interval")[0];
  loaded.dom.command({
    id: "live", action: "live-colors", at: "now", scope: "all", on: true,
    mode: "solo", period: 300, epoch: Date.now(), light: false, titles: [], ring: { dark: ring, light: ring },
  });
  assert.equal(look().source, "live");
  loaded.win.history.pushState(null, "", `/epitaxy/${C}`);
  loaded.dom.fire(watch);
  assert.equal(loaded.api.status().chatKey, `id:${C}`, "сторож увидел переход");
  assert.equal(look().source, "live", "живую тему переход не сбил");
  assert.equal(loaded.api.status().font.family, null, "шрифт A в C не остался");
});
