// WF93 (N1), страница: черновик «Code» принимает draft-setup (WF88 К18 и правки
// критика V-N 6–8), ссылка «ОТКРОЙ НОВЫЙ ЧАТ» не открывает второй чат во время
// «⏳»/«✓» и на двойном клике, свежий попап не называет себя прошлым чатом (#7378).
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { loadInject, plain } from "./load.mjs";

const drain = () => new Promise(resolve => setImmediate(resolve));
const settle = async (times = 6) => { for (let index = 0; index < times; index += 1) await drain(); };
// Прогон ожиданий страницы: микрозадачи и самый свежий таймер, часы по 100 мс.
const run = async (loaded, rounds = 80) => {
  let clock = loaded.win.performance.now();
  loaded.win.performance.now = () => clock;
  for (let index = 0; index < rounds; index += 1) {
    clock += 100;
    await settle(4);
    const ids = loaded.dom.ids("timeout");
    if (ids.length) loaded.dom.fire(ids[ids.length - 1]);
  }
  await settle();
};

const ROOT = "/Users/dev/Projects";
const FOLDERS = ["VkusnoffKz", "PimpMyClaude", "Dictator"];
const MODELS = ["Opus 5.5", "Fable 5.1", "Sonnet 5", "Haiku 4.5"];
const STEPS = ["Low", "Medium", "High", "Extra", "Max", "Ultracode"];

// Волокно чипа: путь папки лежит в пропсах компонента над кнопкой.
const chipFiber = path => ({ memoizedProps: { children: [] }, return: { memoizedProps: { folder: { path, name: path.split("/").pop() } }, return: null } });

// Черновик «Code»: поле, чип папки, кнопки модели и ступени; меню открываются
// «как мышью» (pointerdown с buttons:1), Escape на body закрывает открытое.
const draft = ({
  title = "Code", folder = "VkusnoffKz", folders = FOLDERS, chip = true, model = "Opus 5.5", effort = "High",
  text = "", hasFocus = true, href = "about:blank", opener = {}, feed = false, fiberChat = null, born = 0,
  mode = null, bypass = true, confirm = false,
} = {}) => {
  const box = { folderMenus: 0, modelMenus: 0, modeMenus: 0, enter: 0, escapes: 0 };
  const loaded = loadInject({
    href, title, hasFocus, opener,
    html: dom => {
      const body = dom.document.body;
      if (fiberChat) {
        const panel = body.add("div", { class: "epitaxy-chat-panel" });
        panel.__reactFiber$test = { memoizedProps: {}, return: { memoizedProps: { sessionId: fiberChat }, return: null } };
      }
      // Лента Claude 2.9939.2 (живая проба 25.09): контейнер висит и в пустом
      // окне; сообщения — строки transcript-row с data-perf-row, реплика
      // человека — .epitaxy-user-turn под [data-epitaxy-entry].
      if (feed) {
        const rows = body
          .add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed", "aria-label": "Chat messages" } })
          .add("div", { attrs: { "data-testid": "transcript-sizer" }, class: "relative epitaxy-transcript-typography" })
          .add("div", { attrs: { "data-testid": "transcript-rows" } });
        if (feed === "human" || feed === true) {
          rows.add("div", { attrs: { "data-index": "0", "data-testid": "transcript-row", "data-perf-row": "human" } })
            .add("div", { attrs: { "data-epitaxy-entry": "0f0e0d0c-0000-4000-8000-000000000001", role: "article", "aria-label": "Message 1" } })
            .add("div", { class: "epitaxy-user-turn", text: "Привет" });
        }
        if (feed === "tool") {
          rows.add("div", { attrs: { "data-index": "0", "data-testid": "transcript-row", "data-perf-row": "assistant_tool" } })
            .add("div", { attrs: { "data-epitaxy-entry": "msg_TEST1", role: "article", "aria-label": "Message 1" } })
            .add("button", { attrs: { type: "button" }, text: "Ran 1 command" });
        }
        rows.add("div", { attrs: { "data-index": "1", "data-testid": "transcript-row", "data-perf-row": "marker" } });
      }
      const input = body.add("div", { attrs: { "data-testid": "code-prompt-input", contenteditable: "true" }, text });
      const chipButton = chip ? body.add("button", { text: folder }) : null;
      if (chipButton) chipButton.__reactFiber$test = chipFiber(`${ROOT}/${folder}`);
      const modelButton = body.add("button", {
        attrs: { "data-testid": "epitaxy-cds-model-selector", "aria-label": `Model: ${model}`, "aria-haspopup": "menu" },
      });
      const effortButton = body.add("button", { attrs: { "aria-label": `Effort: ${effort}`, "aria-haspopup": "dialog" } });
      // Нижняя строка поля с переключателем режима (WF126, путь А Bypass).
      const modeButton = mode ? body.add("div", { attrs: { "data-cds": "ChatComposerChin" } })
        .add("button", { attrs: { "aria-haspopup": "menu" }, text: mode }) : null;
      return { input, chipButton, modelButton, effortButton, modeButton };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const { parts, document } = loaded;
  loaded.win.performance.timeOrigin = born || Date.now();
  const closeOpen = event => {
    if (event.key !== "Escape") return;
    box.escapes += 1;
    for (const node of document.querySelectorAll('[role="menu"],[role="dialog"]')) node.remove();
  };
  document.body.addEventListener("keydown", closeOpen);
  parts.input.addEventListener("keydown", event => { if (event.key === "Enter") box.enter += 1; });
  parts.chipButton?.addEventListener("pointerdown", event => {
    if (event.buttons !== 1) return;
    box.folderMenus += 1;
    const menu = document.body.add("div", { attrs: { role: "menu" } });
    for (const name of folders) {
      const item = menu.add("div", { attrs: { role: "menuitem" } });
      item.add("span", { text: name });
      item.add("span", { text: `~/Projects/${name}` });
      item.addEventListener("click", () => {
        parts.chipButton.__text = name;
        parts.chipButton.__reactFiber$test = chipFiber(`${ROOT}/${name}`);
        menu.remove();
      });
    }
  });
  parts.modelButton.addEventListener("pointerdown", event => {
    if (event.buttons !== 1) return;
    box.modelMenus += 1;
    const menu = document.body.add("div", { attrs: { role: "menu" } });
    MODELS.forEach((name, index) => {
      const current = `Model: ${name}` === parts.modelButton.getAttribute("aria-label");
      const item = menu.add("div", { attrs: { role: "menuitemradio" }, text: current ? name : `${name}${index + 1}` });
      item.addEventListener("click", () => {
        parts.modelButton.setAttribute("aria-label", `Model: ${name}`);
        menu.remove();
      });
    });
  });
  parts.effortButton.addEventListener("pointerdown", event => {
    if (event.buttons !== 1) return;
    const dialog = document.body.add("div", { attrs: { role: "dialog" } });
    const slider = dialog.add("input", {
      attrs: { type: "range", "aria-valuetext": parts.effortButton.getAttribute("aria-label").slice(8) },
    });
    // Стенд событий не всплывает: Escape ползунку закрывает его диалог сам.
    slider.addEventListener("keydown", closeOpen);
    slider.addEventListener("keydown", key => {
      if (key.key !== "ArrowRight" && key.key !== "ArrowLeft") return;
      const at = STEPS.indexOf(slider.getAttribute("aria-valuetext"));
      const next = Math.max(0, Math.min(STEPS.length - 1, at + (key.key === "ArrowRight" ? 1 : -1)));
      slider.setAttribute("aria-valuetext", STEPS[next]);
      parts.effortButton.setAttribute("aria-label", `Effort: ${STEPS[next]}`);
    });
  });
  parts.modeButton?.addEventListener("pointerdown", event => {
    if (event.buttons !== 1) return;
    box.modeMenus += 1;
    const menu = document.body.add("div", { attrs: { role: "menu" } });
    for (const name of ["Ask permissions", "Auto mode", "Accept edits", "Plan mode", ...(bypass ? ["Bypass permissions"] : [])]) {
      const item = menu.add("div", { attrs: { role: "menuitemradio" }, text: name });
      item.addEventListener("click", () => {
        menu.remove();
        // Первый раз в папке Claude спрашивает подтверждение — его жмёт человек.
        if (confirm && name === "Bypass permissions") document.body.add("div", { attrs: { role: "alertdialog" }, text: "Enable bypass?" });
        else parts.modeButton.__text = name;
      });
    }
  });
  return { loaded, parts, box };
};
const setup = (extra = {}) => ({
  id: `d${Math.random()}`, action: "draft-setup", at: new Date().toISOString(), scope: "window", title: "", draft: true,
  folder: `${ROOT}/PimpMyClaude`, ...extra,
});
const status = loaded => plain(loaded.api.status().draft);
const key = (loaded, event) => loaded.win.dispatchEvent({ type: "keydown", isTrusted: true, cancelable: true, ...event });

// ---- К18: черновик ставит папку, модель и ступень ---------------------------

test("К18: папка чипом, модель и ступень, поле в фокусе, Enter не нажат", async () => {
  const { loaded, parts, box } = draft();
  loaded.dom.command(setup({ model: "Fable 5.1", effort: "Extra" }));
  await run(loaded);
  assert.equal(parts.chipButton.textContent, "PimpMyClaude", "чип показывает папку проекта");
  assert.equal(parts.modelButton.getAttribute("aria-label"), "Model: Fable 5.1");
  assert.equal(parts.effortButton.getAttribute("aria-label"), "Effort: Extra");
  const got = status(loaded);
  assert.equal(got.state, "ok");
  assert.equal(got.folder, "ok");
  assert.deepEqual(got.model, { want: "Fable 5.1", got: "Fable 5.1" });
  assert.deepEqual(got.effort, { want: "Extra", got: "Extra" });
  assert.equal(got.text, 0);
  assert.equal(loaded.document.activeElement, parts.input, "курсор в поле");
  assert.equal(loaded.dom.queryAll('[role="menu"],[role="dialog"]').length, 0, "меню закрыты");
  assert.equal(box.enter, 0, "Enter не нажат ни разу");
});

test("К18: папка уже та — чип не трогаем; без model/effort — только папка", async () => {
  const { loaded, box, parts } = draft({ folder: "PimpMyClaude" });
  loaded.dom.command(setup());
  await run(loaded);
  assert.equal(box.folderMenus, 0);
  assert.equal(box.modelMenus, 0, "модели нет в команде — меню модели не открывали");
  assert.equal(status(loaded).state, "ok");
  assert.equal(status(loaded).folder, "same");
  assert.equal(status(loaded).model, null);
  assert.equal(loaded.document.activeElement, parts.input);
});

test("К18: папки нет в списке — folder-missing, меню закрыто, модель всё равно ставится, поле в фокусе", async () => {
  const { loaded, parts, box } = draft({ folders: ["VkusnoffKz", "Dictator"] });
  loaded.dom.command(setup({ model: "Sonnet 5" }));
  await run(loaded);
  const got = status(loaded);
  assert.equal(got.state, "folder-missing");
  assert.equal(got.folder, "no-item");
  assert.equal(parts.chipButton.textContent, "VkusnoffKz", "чужую папку не выбрали");
  assert.ok(box.escapes >= 1, "меню папок закрыто Escape");
  assert.equal(parts.modelButton.getAttribute("aria-label"), "Model: Sonnet 5");
  assert.equal(loaded.document.activeElement, parts.input);
});

test("К18: чипа нет — причина no-chip в status(), поле всё равно в фокусе", async () => {
  const { loaded, parts } = draft({ chip: false });
  loaded.dom.command(setup());
  await run(loaded);
  assert.equal(status(loaded).state, "folder-missing");
  assert.equal(status(loaded).folder, "no-chip");
  assert.equal(loaded.document.activeElement, parts.input);
});

test("К18: путь не абсолютный — bad-command, шаги дальше идут", async () => {
  const { loaded } = draft();
  loaded.dom.command(setup({ folder: "PimpMyClaude", model: "Haiku 4.5" }));
  await run(loaded);
  assert.equal(status(loaded).folder, "bad-command");
  assert.equal(status(loaded).model.got, "Haiku 4.5");
});

test("К18: text — в пустое поле; в непустое — дописью с новой строки; Enter не жмём", async () => {
  const empty = draft({ folder: "PimpMyClaude" });
  empty.loaded.dom.command(setup({ text: "проверь заказы за вчера" }));
  await run(empty.loaded);
  assert.equal(empty.parts.input.textContent, "проверь заказы за вчера");
  assert.equal(status(empty.loaded).text, 1);
  const full = draft({ folder: "PimpMyClaude", text: "моё" });
  full.loaded.dom.command(setup({ text: "задача" }));
  await run(full.loaded);
  assert.ok(full.parts.input.textContent.includes("\nзадача"), "дописью с новой строки");
  assert.ok(full.parts.input.textContent.includes("моё"), "черновик Элвиса на месте");
  assert.equal(full.box.enter + empty.box.enter, 0);
});

test("К18: без draft:true и не scope:window — не берётся; та же команда дважды — один прогон", async () => {
  const { loaded } = draft();
  loaded.dom.command(setup({ draft: "true" }));
  loaded.dom.command(setup({ draft: undefined }));
  loaded.dom.command(setup({ scope: "all" }));
  await run(loaded, 5);
  assert.equal(loaded.api.status().draft, null);
  const once = setup({ id: "same" });
  loaded.dom.command(once);
  await run(loaded);
  loaded.dom.command(once);
  await run(loaded, 5);
  assert.equal(status(loaded).runs, 1);
});

// ---- правка критика 7: кто черновик ------------------------------------------

test("К18: не черновик — not-draft с причиной (окно в фокусе)", async () => {
  const cases = [
    [{ title: "VkusnoffKz 2" }, "title"],
    [{ feed: "human" }, "feed"],
    [{ feed: "tool" }, "feed"],
    [{ fiberChat: "local_old" }, "chat"],
    [{ born: Date.now() - 60000 }, "old"],
    [{ opener: null }, "not-popup"],
  ];
  for (const [spec, reason] of cases) {
    const { loaded, parts } = draft(spec);
    loaded.dom.command(setup({ model: "Fable 5.1" }));
    await run(loaded, 10);
    assert.deepEqual([status(loaded)?.state, status(loaded)?.reason], ["not-draft", reason], JSON.stringify(spec));
    assert.equal(parts.modelButton.getAttribute("aria-label"), "Model: Opus 5.5", "ничего не перенастроено");
  }
});

test("К18: не в фокусе — чужой не черновик молчит, свежий черновик берёт (S.0: главный без фокуса)", async () => {
  const other = draft({ hasFocus: false, title: "Ожидание задачи" });
  other.loaded.dom.command(setup());
  await run(other.loaded, 10);
  assert.equal(other.loaded.api.status().draft, null);
  const fresh = draft({ hasFocus: false });
  fresh.loaded.dom.command(setup({ model: "Fable 5.1" }));
  await run(fresh.loaded);
  assert.equal(status(fresh.loaded).state, "ok");
});

test("К18: главное окно команду не берёт", async () => {
  const { loaded } = draft({ href: "https://claude.ai/epitaxy", opener: null });
  loaded.dom.command(setup());
  await run(loaded, 5);
  assert.equal(loaded.api.status().draft, null);
});

test("К18: окно из запаса Claude — старый timeOrigin, но показано только что — черновик", async () => {
  const { loaded } = draft({ born: Date.now() - 4 * 3600 * 1000 });
  loaded.document.visibilityState = "visible";
  loaded.document.dispatchEvent({ type: "visibilitychange" });
  loaded.dom.command(setup());
  await run(loaded);
  assert.equal(status(loaded).state, "ok");
});

test("WF93-g: пустая лента 2.9939.2 — контейнер и строка marker без сообщений — ещё черновик", async () => {
  const { loaded } = draft({ feed: "shell" });
  loaded.dom.command(setup({ model: "Fable 5.1" }));
  await run(loaded);
  assert.equal(status(loaded).state, "ok");
});

test("WF93-g: окно из запаса показано, но без фокуса — не рождение: молчит и ничего не трогает", async () => {
  const { loaded, parts } = draft({ born: Date.now() - 4 * 3600 * 1000, hasFocus: false });
  loaded.document.visibilityState = "visible";
  loaded.document.dispatchEvent({ type: "visibilitychange" });
  loaded.dom.command(setup({ model: "Fable 5.1" }));
  await run(loaded, 10);
  assert.equal(loaded.api.status().draft, null, "чужое окно без фокуса молчит");
  assert.equal(parts.modelButton.getAttribute("aria-label"), "Model: Opus 5.5");
  assert.equal(parts.chipButton.textContent, "VkusnoffKz");
});

// ---- правка критика 8: клавиша и нажатие Элвиса ------------------------------

test("WF93-g: Enter и стрелка в открытом нами меню — погашены, модель прежняя, настройка брошена", async () => {
  for (const name of ["Enter", "ArrowDown"]) {
    const { loaded, parts } = draft({ folder: "PimpMyClaude" });
    loaded.dom.command(setup({ folder: undefined, model: "Fable 5.1" }));
    assert.equal(loaded.dom.queryAll('[role="menu"]').length, 1, "меню модели открыто");
    const allowed = key(loaded, { key: name, target: loaded.dom.query('[role="menuitemradio"]') });
    assert.equal(allowed, false, `${name} до меню не дошёл`);
    await run(loaded);
    assert.equal(parts.modelButton.getAttribute("aria-label"), "Model: Opus 5.5", name);
    assert.equal(loaded.dom.queryAll('[role="menu"]').length, 0, "меню закрыто");
    assert.equal(status(loaded).state, "user");
    assert.equal(loaded.document.activeElement, parts.input);
  }
});

test("WF93-g: стрелка в ползунке ступени — погашена; Enter вне меню — не наш, не гасим", async () => {
  const slider = draft({ folder: "PimpMyClaude", effort: "High" });
  slider.loaded.dom.command(setup({ folder: undefined, effort: "Max" }));
  const range = slider.loaded.dom.query('[role="dialog"] input');
  assert.ok(range, "ползунок открыт");
  assert.equal(key(slider.loaded, { key: "ArrowRight", target: range }), false);
  await run(slider.loaded);
  assert.equal(status(slider.loaded).state, "user");
  const outside = draft({ folder: "PimpMyClaude" });
  outside.loaded.dom.command(setup({ folder: undefined, model: "Fable 5.1" }));
  assert.equal(key(outside.loaded, { key: "Enter", target: outside.loaded.document.body }), true);
  assert.equal(status(outside.loaded).state, "user");
});

test("К18: буква посреди выбора модели — в поле, меню закрыто, настройка брошена", async () => {
  const { loaded, parts } = draft({ folder: "PimpMyClaude" });
  loaded.dom.command(setup({ folder: undefined, model: "Fable 5.1", effort: "Max" }));
  // Меню модели уже открыто, пункт ещё не нажат.
  assert.equal(loaded.dom.queryAll('[role="menu"]').length, 1, "меню модели открыто");
  const allowed = key(loaded, { key: "п", target: loaded.dom.query('[role="menuitemradio"]') });
  assert.equal(allowed, false, "букву кладём сами — typeahead меню её не получит");
  await run(loaded);
  assert.ok(parts.input.textContent.includes("п"), "буква в поле");
  assert.equal(loaded.dom.queryAll('[role="menu"]').length, 0, "меню закрыто");
  assert.equal(parts.modelButton.getAttribute("aria-label"), "Model: Opus 5.5", "дальше ничего не делали");
  assert.equal(parts.effortButton.getAttribute("aria-label"), "Effort: High");
  assert.equal(status(loaded).state, "user");
  assert.equal(loaded.document.activeElement, parts.input);
});

test("К18: ⌘V посреди настройки — фокус в поле сразу, событие не гасим", async () => {
  const { loaded, parts } = draft({ folder: "PimpMyClaude" });
  loaded.dom.command(setup({ folder: undefined, model: "Fable 5.1" }));
  assert.equal(key(loaded, { key: "v", metaKey: true, target: loaded.document.body }), true);
  assert.equal(loaded.document.activeElement, parts.input, "вставка Диктатора уйдёт в поле");
  assert.equal(parts.input.textContent, "");
  assert.equal(status(loaded).state, "user");
});

test("К18: нажатие мышью посреди настройки — бросить, буквы нет; своё событие не считается", async () => {
  const { loaded, parts } = draft();
  loaded.dom.command(setup({ model: "Fable 5.1" }));
  loaded.win.dispatchEvent({ type: "pointerdown", isTrusted: false, target: loaded.document.body });
  assert.equal(status(loaded).state, "run", "недоверенное событие — не Элвис");
  loaded.win.dispatchEvent({ type: "pointerdown", isTrusted: true, target: loaded.document.body });
  await run(loaded);
  assert.equal(status(loaded).state, "user");
  assert.equal(parts.chipButton.textContent, "VkusnoffKz");
  assert.equal(parts.input.textContent, "");
});

test("К18: меню вернуло фокус своей кнопке — буква в хвосте настройки всё равно в поле", async () => {
  const { loaded, parts } = draft({ folder: "PimpMyClaude" });
  loaded.dom.command(setup({ model: "Fable 5.1" }));
  await run(loaded, 30);
  assert.equal(status(loaded).state, "ok");
  parts.modelButton.focus();
  assert.equal(key(loaded, { key: "д", target: parts.modelButton }), false);
  assert.ok(parts.input.textContent.includes("д"));
  assert.equal(loaded.document.activeElement, parts.input);
});

// ---- #7378: свежий попап не называет себя прошлым чатом ---------------------

const OLD = "local_dc5ef534";
const NEW = "local_6f1bd03f";
const popup = ({ title = "Loading", session = null } = {}) => loadInject({
  href: "about:blank", title,
  storage: session ? { session } : undefined,
  html: dom => ({ body: dom.document.body }),
});
const panelWith = (loaded, id) => {
  const panel = loaded.document.body.add("div", { class: "epitaxy-chat-panel" });
  panel.__reactFiber$test = { memoizedProps: {}, return: { memoizedProps: { sessionId: id }, return: null } };
  return panel;
};

test("#7378: запись прошлого чата с заглушкой «Loading» не называет новое окно", () => {
  const record = JSON.stringify({ id: OLD, title: "Loading" });
  const fresh = popup({ session: { "myclaude-chat-v1": record } });
  assert.equal(fresh.inner.readChatId(), null, "заглушка чата не называет");
  assert.equal(fresh.inner.myChatId(), null);
  assert.equal(fresh.inner.chatTitleKey(), null, "у «Loading» ключа темы по заголовку нет");
  panelWith(fresh, NEW);
  assert.equal(fresh.inner.myChatId(), NEW, "волокно называет свой чат");
  assert.equal(fresh.win.sessionStorage.getItem("myclaude-chat-v1"), record, "под заглушкой кэш не пишем");
});

test("#7378: окно из запаса Claude — новый чат с тем же заголовком называет себя новым", () => {
  const loaded = popup({ title: "Ожидание задачи" });
  const old = panelWith(loaded, OLD);
  assert.equal(loaded.inner.myChatId(), OLD);
  old.remove();
  panelWith(loaded, NEW);
  assert.equal(loaded.inner.myChatId(), NEW, "кэш волокна держится за живой узел");
  assert.equal(JSON.parse(loaded.win.sessionStorage.getItem("myclaude-chat-v1")).id, NEW);
});

// ---- К15: ссылка и кнопка не открывают второй чат ---------------------------

const HANDOFF = JSON.parse(readFileSync(new URL("./fixtures/cashout/record-handoff.json", import.meta.url), "utf8")).text;
const LINK = "[data-myclaude-continue-link]";
const PREFIX = "Пимп: продолжить в новом чате · ";
const chatPage = () => {
  const heads = [];
  const loaded = loadInject({
    href: "about:blank", title: "VkusnoffKz 2", hasFocus: false,
    html: dom => {
      const parts = dom.composer();
      const answer = dom.document.body.add("div", { attrs: { "data-testid": "assistant-message" }, rect: { left: 0, top: 100, width: 800, height: 100 } });
      heads.push(answer.add("h2", { text: "🆕 ОТКРОЙ НОВЫЙ ЧАТ" }));
      const block = answer.add("div", { class: "epitaxy-codeblock relative" });
      block.add("div", { class: "relative" }).add("div", { attrs: { "data-code-text": HANDOFF }, text: HANDOFF });
      heads.push(answer.add("h2", { text: "🆕 ОТКРОЙ НОВЫЙ ЧАТ" }));
      return parts;
    },
  });
  assert.equal(loaded.error, null);
  // База заморожена (z8-r01): часы страницы двигает только тест, иначе
  // настоящее время под нагрузкой утекало бы в отсчёт.
  const base = loaded.win.performance.now();
  let shift = 500;
  loaded.win.performance.now = () => base + shift;
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
  assert.equal(loaded.dom.queryAll(LINK).length, 2);
  return { loaded, heads };
};
const click = (loaded, target, extra = {}) =>
  loaded.document.dispatchEvent({ type: "click", target, bubbles: true, button: 0, detail: 1, ...extra });
const lastTimer = loaded => { const ids = loaded.dom.ids("timeout"); loaded.dom.fire(ids[ids.length - 1]); };
const ack = loaded => loaded.dom.command({ id: "c1", action: "cashout", at: "now", scope: "window", title: "VkusnoffKz 2", handoff: true });

test("К15: двойной и тройной клик по ссылке — выделение, чат не открывается", () => {
  const { loaded, heads } = chatPage();
  click(loaded, heads[0]);
  click(loaded, heads[0], { detail: 2 });
  loaded.dom.fireKind("timeout");
  click(loaded, heads[1]);
  click(loaded, heads[1], { detail: 2 });
  click(loaded, heads[1], { detail: 3 });
  loaded.dom.fireKind("timeout");
  assert.equal(loaded.api.status().continue.clicks, 0);
  assert.equal(String(loaded.document.title), "VkusnoffKz 2");
});

test("К15: во время «⏳» и «✓» ни ссылка, ни кнопка второй раз не открывают", () => {
  const { loaded, heads } = chatPage();
  click(loaded, heads[0]);
  lastTimer(loaded);
  assert.ok(String(loaded.document.title).startsWith(PREFIX));
  assert.equal(loaded.api.status().continue.clicks, 1);
  const button = loaded.dom.query("[data-myclaude-continue] button");
  assert.ok(button, "кнопка «💬 Новый чат» стоит");
  click(loaded, button);
  assert.equal(loaded.api.status().continue.clicks, 1, "⏳: кнопка не жмётся");
  ack(loaded);
  assert.equal(heads[0].getAttribute("data-myclaude-continue-state"), "ack");
  assert.equal(click(loaded, heads[0]), false, "клик по ссылке во время «✓» погашен");
  assert.equal(loaded.dom.ids("timeout").length > 0, true);
  // Отложенный клик ссылки во время «✓» не заводится вовсе.
  assert.equal(click(loaded, button), false);
  assert.equal(loaded.api.status().continue.clicks, 1, "✓: второго чата нет");
  assert.equal(String(loaded.document.title), "VkusnoffKz 2", "метки заголовка нет");
});

// ---- WF126 §7.3 (поправки критика 4–5): Bypass permissions в черновике PMP ------

test("WF126: mode:bypass — режим черновика Bypass после модели, итог в draft.mode, общий итог прежний", async () => {
  const { loaded, parts, box } = draft({ folder: "PimpMyClaude", mode: "Auto mode" });
  loaded.dom.command(setup({ model: "Fable 5.1", mode: "bypass" }));
  await run(loaded);
  assert.equal(parts.modeButton.textContent, "Bypass permissions");
  const got = status(loaded);
  assert.equal(got.state, "ok");
  assert.deepEqual(got.mode, { want: "bypass", got: "By", result: "ok" });
  assert.equal(box.modeMenus, 1);
  assert.equal(loaded.dom.queryAll('[role="menu"]').length, 0, "меню режима закрыто");
  assert.equal(loaded.document.activeElement, parts.input, "курсор в поле");
  assert.equal(box.enter, 0);
});

test("WF126: без mode — меню режима не открываем; уже Bypass — already без меню", async () => {
  const plain1 = draft({ folder: "PimpMyClaude", mode: "Auto mode" });
  plain1.loaded.dom.command(setup());
  await run(plain1.loaded);
  assert.equal(plain1.box.modeMenus, 0);
  assert.equal(status(plain1.loaded).mode, null);
  const already = draft({ folder: "PimpMyClaude", mode: "Bypass permissions" });
  already.loaded.dom.command(setup({ mode: "bypass" }));
  await run(already.loaded);
  assert.equal(already.box.modeMenus, 0);
  assert.equal(status(already.loaded).mode.result, "already");
});

test("WF126: пункта Bypass нет — no-item, меню закрыто Escape, режим прежний", async () => {
  const { loaded, parts, box } = draft({ folder: "PimpMyClaude", mode: "Auto mode", bypass: false });
  loaded.dom.command(setup({ mode: "bypass" }));
  await run(loaded);
  assert.equal(status(loaded).mode.result, "no-item");
  assert.equal(status(loaded).mode.got, "Au");
  assert.equal(status(loaded).state, "ok");
  assert.equal(parts.modeButton.textContent, "Auto mode");
  assert.ok(box.escapes >= 1);
  assert.equal(loaded.dom.queryAll('[role="menu"]').length, 0);
});

test("WF126: подтверждение Claude — confirm, диалог не закрыт и не нажат, Escape не шлём, текст не кладём", async () => {
  const { loaded, parts, box } = draft({ folder: "PimpMyClaude", mode: "Auto mode", confirm: true });
  loaded.dom.command(setup({ mode: "bypass", text: "проверь" }));
  await run(loaded);
  assert.equal(status(loaded).mode.result, "confirm");
  assert.equal(loaded.dom.queryAll('[role="alertdialog"]').length, 1, "подтверждение Claude закрыли");
  assert.equal(box.escapes, 0, "Escape ушёл в окно с подтверждением");
  assert.equal(parts.input.textContent, "", "текст лёг под диалог");
  assert.equal(box.enter, 0);
});

test("WF126: нет переключателя режима — no-button, остальное поставлено", async () => {
  const { loaded } = draft({ folder: "PimpMyClaude" });
  loaded.dom.command(setup({ model: "Sonnet 5", mode: "bypass" }));
  await run(loaded);
  assert.equal(status(loaded).mode.result, "no-button");
  assert.equal(status(loaded).model.got, "Sonnet 5");
});
