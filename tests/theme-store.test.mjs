// Хранилище слоёв окна (раздел 2а inject.js): ключи, приоритет слоёв, перенос
// старых записей, независимость четырёх слоёв. Проверяется контракт из
// AGENTS.md, а не конкретные цвета: палитры Элвис крутит руками.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";

const MAP_KEY = "myclaude-themes-v1";
const SESSION_KEY = "myclaude-theme-v1";

const theme = (id, accent = "#2299ff") => ({
  id, name: id, type: "dark",
  palette: { accent, background: "#001122", foreground: "#eeffff", sidebar: "#000811", panel: "#00223a", muted: "#88aabb" },
});
const font = (family = "SF Mono") => ({ id: family, family, mono: true });
const map = value => ({ [MAP_KEY]: JSON.stringify(value) });
const sessionOf = (key, entry) => ({ [SESSION_KEY]: JSON.stringify({ key, ...entry }) });
const readMap = win => JSON.parse(win.localStorage.getItem(MAP_KEY) ?? "null");

test("запись чата сильнее сессии окна", () => {
  const { api } = loadInject({
    title: "Trelvis",
    storage: {
      local: map({ "chat:Trelvis": { theme: theme("чат") } }),
      session: sessionOf("main", { theme: theme("сессия") }),
    },
  });
  assert.equal(api.status().theme.id, "чат");
  assert.equal(api.status().theme.source, "chat");
});

test("сессия окна сильнее записи main", () => {
  const { api } = loadInject({
    title: "Trelvis",
    storage: {
      local: map({ main: { theme: theme("окно") } }),
      session: sessionOf("main", { theme: theme("сессия") }),
    },
  });
  assert.equal(api.status().theme.id, "сессия");
  assert.equal(api.status().theme.source, "session");
});

test("запись main сильнее записи «всем окнам»", () => {
  const { api } = loadInject({
    title: "Trelvis",
    storage: { local: map({ main: { theme: theme("окно") }, "*": { theme: theme("всем") } }) },
  });
  assert.equal(api.status().theme.id, "окно");
  assert.equal(api.status().theme.source, "window");
});

test("«всем окнам» — последний уровень", () => {
  const { api } = loadInject({ title: "Trelvis", storage: { local: map({ "*": { theme: theme("всем") } }) } });
  assert.equal(api.status().theme.id, "всем");
  assert.equal(api.status().theme.source, "all");
});

test("заголовки-заглушки ключом чата по ИМЕНИ не становятся", () => {
  for (const stub of ["Claude", "New chat", "Новый чат", "  claude  "]) {
    const { inner, api } = loadInner({ title: stub });
    assert.equal(inner.chatTitleKey(), null, stub);
    // WF35: у безымянного чата есть id, и ключ по нему законен — выбранный в
    // таком чате цвет обязан остаться, когда имя появится.
    assert.equal(inner.chatIdKey(), "id:local_test", stub);
    assert.equal(inner.chatKey(), "id:local_test", stub);
    assert.equal(inner.themeKey(), "id:local_test", stub);
    assert.equal(api.status().chatKey, "id:local_test", stub);
  }
});

test("id чата неизвестен — ключом остаётся имя, у заглушки ключа чата нет вовсе", () => {
  const named = loadInner({ title: "Trelvis", href: "https://claude.ai/new" });
  assert.equal(named.inner.chatIdKey(), null, "путь без local_ id не даёт");
  assert.equal(named.inner.chatKey(), "chat:Trelvis");
  assert.equal(named.inner.themeKey(), "chat:Trelvis");
  const stub = loadInner({ title: "Claude", href: "https://claude.ai/new" });
  assert.equal(stub.inner.chatKey(), null);
  assert.equal(stub.inner.themeKey(), "main", "у главного окна остаётся ключ окна");
});

test("запись старого образца w:<заголовок> читается как запись чата", () => {
  const { api, inner } = loadInner({
    title: "Trelvis",
    storage: { local: map({ "w:Trelvis": { theme: theme("старая") } }) },
  });
  assert.equal(inner.legacyKey("chat:Trelvis"), "w:Trelvis");
  assert.equal(api.status().theme.id, "старая");
  assert.equal(api.status().theme.source, "chat");
});

test("первая же запись переносит w:<заголовок> в chat:<заголовок>", () => {
  const loaded = loadInject({
    title: "Trelvis",
    storage: { local: map({ "w:Trelvis": { theme: theme("старая"), font: font("Menlo") } }) },
  });
  loaded.dom.command({ id: "1", action: "theme", at: "now", scope: "window", title: "Trelvis", theme: theme("новая") });
  const stored = readMap(loaded.win);
  assert.equal(stored["w:Trelvis"], undefined, "старый ключ снят");
  assert.equal(stored["chat:Trelvis"].theme.id, "новая");
  assert.equal(stored["chat:Trelvis"].font.family, "Menlo", "второй слой переехал вместе с первым");
});

test("слои независимы: шрифт приходит — тема цела", () => {
  const loaded = loadInject({ title: "Trelvis", storage: { local: map({ "chat:Trelvis": { theme: theme("цвет") } }) } });
  loaded.dom.command({ id: "2", action: "theme", at: "now", scope: "window", title: "Trelvis", font: font("SF Mono") });
  const status = loaded.api.status();
  assert.equal(status.theme.id, "цвет");
  assert.equal(status.font.family, "SF Mono");
  assert.equal(readMap(loaded.win)["chat:Trelvis"].theme.id, "цвет");
});

test("null у слоя — сброс только его, остальные слои целы", () => {
  const loaded = loadInject({
    title: "Trelvis",
    storage: { local: map({ "chat:Trelvis": { theme: theme("цвет"), font: font("Menlo"), size: { answer: 18 } } }) },
  });
  loaded.dom.command({ id: "3", action: "theme", at: "now", scope: "window", title: "Trelvis", theme: null });
  const entry = readMap(loaded.win)["chat:Trelvis"];
  assert.equal(entry.theme, undefined, "тема снята");
  assert.equal(entry.font.family, "Menlo", "шрифт на месте");
  assert.equal(entry.size.answer, 18, "размер на месте");
  assert.equal(loaded.api.status().theme.id, null);
  assert.equal(loaded.api.status().font.family, "Menlo");
});

test("битый JSON в localStorage не роняет чтение и не стирает чужие ключи", () => {
  const loaded = loadInject({
    title: "Trelvis",
    storage: { local: { [MAP_KEY]: "{это не json", "myclaude-live-v1": "своё" } },
  });
  assert.deepEqual(plain(loaded.inner.readThemeMap()), {}, "битая карта читается как пустая");
  assert.equal(loaded.api.status().theme.id, null, "окно не покрашено");
  loaded.dom.command({ id: "4", action: "theme", at: "now", scope: "window", title: "Trelvis", theme: theme("новая") });
  assert.equal(readMap(loaded.win)["chat:Trelvis"].theme.id, "новая");
  assert.equal(loaded.win.localStorage.getItem("myclaude-live-v1"), "своё", "чужой ключ цел");
});

test("массив вместо карты читается как пустая карта", () => {
  const { inner } = loadInner({ title: "Trelvis", storage: { local: { [MAP_KEY]: "[1,2,3]" } } });
  assert.deepEqual(plain(inner.readThemeMap()), {});
});

test("сессия окна переживает второй прогон инжекта", () => {
  const loaded = loadInject({ title: "Trelvis", storage: { session: sessionOf("main", { theme: theme("сессия") }) } });
  assert.equal(loaded.api.status().theme.source, "session");
  const again = loaded.reload();
  assert.equal(again.error, null);
  assert.equal(again.api.status().theme.id, "сессия", "после перезапуска инжекта тема та же");
  assert.equal(again.api.status().theme.source, "session");
});

test("ключ сессии — по окну: main у главного, w:<заголовок> у подчинённого", () => {
  const main = loadInner({ title: "Trelvis", href: "https://claude.ai/epitaxy/local_1" });
  assert.equal(main.inner.sessionKey(), "main");
  const popup = loadInner({ title: "Второе окно", href: "about:blank" });
  assert.equal(popup.inner.sessionKey(), "w:Второе окно");
  assert.equal(popup.inner.themeKey(), "chat:Второе окно");
});

test("чужая страница ключей не даёт вовсе", () => {
  const { inner } = loadInner({ title: "Артефакт", href: "https://example.com/x" });
  assert.equal(inner.chatKey(), null);
  assert.equal(inner.sessionKey(), null);
  assert.equal(inner.themeKey(), null);
});

test("entryLayer различает «нет слоя», «сброс» и значение", () => {
  const { inner } = loadInner({ title: "Trelvis" });
  assert.equal(inner.entryLayer({}, "theme"), undefined, "поля нет — слоя не касались");
  assert.equal(inner.entryLayer({ theme: "none" }, "theme"), null, "«none» — явный сброс");
  assert.equal(inner.entryLayer({ theme: null }, "theme"), null, "null — сброс");
  assert.equal(inner.entryLayer({ theme: "мусор" }, "theme"), undefined, "мусор равен отсутствию");
  assert.equal(inner.entryLayer({ theme: theme("цвет") }, "theme").id, "цвет");
  assert.equal(inner.entryLayer({ size: { answer: 99 } }, "size"), undefined, "размер вне границ — нет слоя");
});

test("mapEntry понимает формат WF5, где тема лежала на верхнем уровне", () => {
  const { inner } = loadInner({ title: "Trelvis" });
  const old = { "chat:Trelvis": theme("одна тема") };
  assert.equal(inner.mapEntry(old, "chat:Trelvis").theme.id, "одна тема");
  assert.equal(inner.mapEntry({ "chat:Trelvis": "none" }, "chat:Trelvis").theme, "none");
  assert.equal(inner.mapEntry({}, "chat:Trelvis"), null);
  assert.equal(inner.mapEntry({}, null), null);
});

test("writeThemeMap пустой картой убирает ключ целиком", () => {
  const loaded = loadInner({ title: "Trelvis", storage: { local: map({ "chat:Trelvis": { theme: theme("цвет") } }) } });
  loaded.inner.writeThemeMap({});
  assert.equal(loaded.win.localStorage.getItem(MAP_KEY), null);
});

test("выбор в безымянном чате в chat: не пишется — только id, main и сессия", () => {
  const loaded = loadInject({ title: "Claude" });
  loaded.dom.command({ id: "5", action: "theme", at: "now", scope: "window", title: "Claude", theme: theme("цвет") });
  const stored = readMap(loaded.win);
  assert.deepEqual(Object.keys(stored), ["id:local_test", "main"], "ключа по ИМЕНИ нет");
  assert.equal(JSON.parse(loaded.win.sessionStorage.getItem(SESSION_KEY)).key, "main");
});

test("запись «всем окнам» снимает свой слой у окон", () => {
  const loaded = loadInject({
    title: "Trelvis",
    storage: { local: map({ "chat:Trelvis": { theme: theme("своя"), font: font("Menlo") } }) },
  });
  loaded.dom.command({ id: "6", action: "theme", at: "now", scope: "all", theme: theme("общая") });
  const stored = readMap(loaded.win);
  assert.equal(stored["*"].theme.id, "общая");
  assert.equal(stored["chat:Trelvis"].theme, undefined, "своя тема снята — теперь красит общая");
  assert.equal(stored["chat:Trelvis"].font.family, "Menlo", "чужой слой не тронут");
});
