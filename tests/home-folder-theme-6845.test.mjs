// #6845 (слово Элвиса): «в новых пустых чатах, когда я меняю название проекта… чтобы тема сразу менялась
// под название проекта». Вид проекта знает приложение и узнаёт папку чипа кругом probe (раз в 4 с);
// страница помнит вид, которым домашний экран красили при этой папке, и на смене папки в списке
// показывает его сама — тиком сторожа заголовка, без ожидания круга.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const HOME_KEY = "myclaude-home-folders-v1";
const A = "/Users/dev/Projects/Vkusnoff";
const B = "/Users/dev/Projects/PimpMyClaude";
const theme = (id, accent = "#2299ff") => ({
  id, name: id, type: "dark",
  palette: { accent, background: "#001122", foreground: "#eeffff", sidebar: "#000811", panel: "#00223a", muted: "#88aabb" },
});
const drain = async () => { for (let step = 0; step < 4; step += 1) await new Promise(setImmediate); };

const home = async () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy", title: "Claude",
    html: dom => ({ input: dom.document.body.add("div", { attrs: { "data-testid": "code-prompt-input" } }) }),
  });
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  const value = { selectedFolder: A, setLocalSelectedFolder: () => {}, setTrustedSelectedFolder: () => {} };
  const store = () => {};
  store.getState = () => value;
  loaded.inner.setModuleImporter(() => Promise.resolve({ Store: store }));
  // Первый тик заводит поиск стора папки, второй уже видит папку (первый взгляд — не смена).
  loaded.inner.syncHomeFolderTheme();
  await drain();
  loaded.inner.syncHomeFolderTheme();
  return { loaded, value };
};
let seq = 0;
// Покраска по проекту: команда приложения адресована путём домашнего экрана.
const paint = (loaded, layers) => loaded.dom.command({
  id: `p${seq += 1}`, action: "theme", at: "now", scope: "window", title: "Claude", match: "/epitaxy", ...layers,
});

test("#6845: смена проекта в списке пустого чата сразу красит окно видом этого проекта", async () => {
  const { loaded, value } = await home();
  paint(loaded, { theme: theme("вкуснофф") });
  value.selectedFolder = B;
  loaded.inner.syncHomeFolderTheme();
  assert.equal(loaded.api.status().theme.id, "вкуснофф", "вида B ещё не видели — ждём приложение, как раньше");
  paint(loaded, { theme: theme("пимп") });
  assert.equal(loaded.api.status().theme.id, "пимп");
  const saved = JSON.parse(loaded.win.localStorage.getItem(HOME_KEY));
  assert.deepEqual(Object.keys(saved), [A, B]);

  value.selectedFolder = A;
  loaded.inner.syncHomeFolderTheme();
  assert.equal(loaded.api.status().theme.id, "вкуснофф", "A — сразу, без круга probe");
  value.selectedFolder = `${B}/`;
  loaded.inner.syncHomeFolderTheme();
  assert.equal(loaded.api.status().theme.id, "пимп", "хвостовой слэш папку не меняет");
});

test("#6845: идёт «Новое окно» — чип чужой, окно не перекрашиваем; в чате — тоже", async () => {
  const { loaded, value } = await home();
  paint(loaded, { theme: theme("вкуснофф") });
  value.selectedFolder = B;
  loaded.inner.syncHomeFolderTheme();
  paint(loaded, { theme: theme("пимп") });

  // Цепочка занимает кнопку синхронно, до первого await, — тем же ходом и смотрим.
  loaded.dom.command({ id: "n1", action: "new-window", at: "now", scope: "window", title: "Claude", x: 1, y: 2, text: "Привет" });
  assert.equal(loaded.api.status().newWindow.busy, true);
  value.selectedFolder = A;
  loaded.inner.syncHomeFolderTheme();
  assert.equal(loaded.api.status().theme.id, "пимп", "чип показывает папку будущего чата");
  await drain();
  assert.equal(loaded.api.status().newWindow.busy, false);
  loaded.inner.syncHomeFolderTheme();
  assert.equal(loaded.api.status().theme.id, "пимп", "после цепочки первый взгляд — не смена");

  loaded.win.location.pathname = "/epitaxy/local_x";
  value.selectedFolder = B;
  loaded.inner.syncHomeFolderTheme();
  assert.equal(loaded.api.status().theme.id, "пимп", "в открытом чате чип ничего не решает");
});
