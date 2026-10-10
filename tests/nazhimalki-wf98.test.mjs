// WF98, батч Б1 (страница, раздел 12с inject.js): нажималки в ответах (#7843)
// и «продолжим в другом чате» (#7842). Слово Элвиса 26.09 ~05:50: «оно не
// должно отправлять, оно просто должно вписать, какой вариант брать»;
// «разрешаю» и «сделал» — тоже не отправлять; «переключать сам режим тоже
// делаем»; «отчёт» и новый чат — с отсчётом, «чтобы не нажимать по ошибке».
//
// Время отсчёта — аргумент nazhTick (люк), таймеры стенда не ждём. Нажатие —
// событие click на document с целью-кнопкой (стенд событий не всплывает).
// Текст, рядом с которым встаёт кнопка, — настоящим текстовым узлом (dom.leaf):
// у стенда текст из options.text — не узел, и соседняя кнопка его «прячет».
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_aaaa-1111";
const PICK = "data-myclaude-nazh-pick";
const BUTTON = "data-myclaude-nazh-button";
const LABEL = "data-myclaude-nazh-label";
const CHAT_TEXT = "Дай блок «ОТКРОЙ НОВЫЙ ЧАТ» с текстом передачи";
const MENU = ["Ask permissions", "Accept edits", "Plan mode", "Bypass permissions", "Auto mode"];

// Лента (строка transcript-row/assistant_text, как на Claude 2.9939.2), поле
// ввода, кнопка отправки и нижняя строка с переключателем режима. Меню режима
// открывается нажатием на переключатель; пункт меняет подпись переключателя.
const page = ({ text = "", mode = "Auto", build = () => {}, menu = MENU, menuLate = false, chin = true, working = false } = {}) => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Trelvis",
    storage: { local: { "myclaude-auto-allow-roam": "off", "myclaude-send-delay-seconds": "5" } },
    html: dom => {
      const parts = dom.composer({ text });
      const feed = dom.document.body.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript" },
        rect: { left: 0, top: 0, width: 1200, height: 500 },
      });
      parts.feed = feed;
      const row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" } });
      parts.box = row.add("div", { class: "contents" });
      build(parts.box, dom, parts);
      parts.send = parts.modelRow.add("button", {
        attrs: { "data-testid": "code-prompt-send" },
        rect: { left: 1150, top: 700, width: 24, height: 24 },
      });
      parts.send.__presses = 0;
      parts.send.addEventListener("pointerdown", () => { parts.send.__presses += 1; parts.editor.__text = ""; });
      parts.pressed = [];
      parts.opens = 0;
      if (chin) {
        const row2 = parts.modelRow.add("div", { attrs: { "data-cds": "ChatComposerChin" } });
        row2.add("button", { text: "Opus 5.5", attrs: { "data-testid": "epitaxy-cds-model-selector" } });
        parts.mode = row2.add("button", { text: mode, attrs: { "aria-haspopup": "menu" } });
        const open = () => {
          parts.opens += 1;
          const list = dom.document.body.add("div", { attrs: { role: "menu" } });
          for (const label of menu) {
            const item = list.add("div", { attrs: { role: "menuitemradio" }, text: label });
            item.addEventListener("pointerdown", () => {
              parts.pressed.push(label);
              parts.mode.textContent = label.replace(/ mode$/, "");
              list.remove();
            });
          }
        };
        parts.mode.addEventListener("pointerdown", () => {
          if (menuLate) parts.openLater = open;
          else open();
        });
      }
      if (working) parts.stop = dom.document.body.add("button", { attrs: { "data-testid": "code-prompt-stop" } });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  caret(loaded);
  let t = Date.now();
  loaded.inner.nazhTick(t);
  const tick = (step = 500) => { t += step; loaded.inner.nazhTick(t); };
  const click = (node, extra = {}) => {
    loaded.dom.document.dispatchEvent({ type: "click", target: node, detail: 1, isTrusted: true, ...extra });
    t = Date.now();
  };
  return { loaded, parts: loaded.parts, tick, click };
};
// Курсор и выделение в поле, как в Chromium (образец — say-wf97): свой текст
// Элвиса пишется с курсора в конце, хвост выделяется назад Selection.modify.
const caret = loaded => {
  const doc = loaded.dom.document;
  const editor = loaded.parts.editor;
  let start = 0;
  let end = 0;
  doc.createRange = () => {
    const range = {
      end: false, setStart() {}, setEnd() {}, selectNodeContents() {},
      collapse(toStart) { range.end = !toStart; },
      getBoundingClientRect: () => ({ left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0 }),
    };
    return range;
  };
  const selection = {
    rangeCount: 1, getRangeAt: () => null, toString: () => editor.__text.slice(start, end), removeAllRanges() {},
    addRange(range) { start = end = range.end ? editor.__text.length : 0; },
    modify(alter, direction) { if (alter === "extend" && direction === "backward") start = Math.max(0, start - 1); },
  };
  loaded.win.getSelection = () => selection;
  doc.getSelection = () => selection;
  const stock = doc.execCommand;
  doc.execCommand = (name, ui, value) => {
    if ((name !== "insertText" && name !== "delete") || doc.__selectedAll) return stock(name, ui, value);
    if (doc.activeElement !== editor) return false;
    const put = name === "insertText" ? String(value) : "";
    editor.__text = editor.__text.slice(0, start) + put + editor.__text.slice(end);
    start = end = start + put.length;
    return true;
  };
};
const nazh = loaded => plain(loaded.api.status().nazh);
const field = loaded => loaded.parts.editor.textContent;
const buttons = (loaded, action) => loaded.dom.queryAll(`[${BUTTON}="${action}"]`);
const label = node => node.getAttribute(LABEL);

// ---- «🔘 ВЫБОР» ---------------------------------------------------------------

// Решения номерами: <ol> с вложенным списком «🟢/⚪»; Markdown рвёт список, и
// второе решение — отдельный <ol start="2">.
const choice = (box, dom, parts) => {
  box.add("h2", { text: "🔘 ВЫБОР" });
  const first = box.add("ol");
  const one = dom.leaf(first, "li", "Где хранить пометки");
  const list1 = one.add("ul");
  list1.add("li", { text: "🟢 в складе Viewer — переживает переустановку" });
  parts.alt1 = list1.add("li", { text: "⚪ в localStorage страницы — проще, но теряется" });
  box.add("pre", { text: "код между решениями" });
  const second = box.add("ol", { attrs: { start: "2" } });
  const two = dom.leaf(second, "li", "Цвет кнопки");
  const list2 = two.add("ul");
  parts.green2 = list2.add("li", { text: "🟢 янтарь — в тон миганию" });
  parts.alt2 = list2.add("li", { text: "⚪ фиолетовый — как Галерея" });
  parts.alt2b = list2.add("li", { text: "⚪ синий акцент — как ссылки" });
  box.add("h2", { text: "Pimp Viewer" });
  parts.after = box.add("ul").add("li", { text: "⚪ после блока — не нажималка" });
};

test("#7843 ВЫБОР: строки «⚪» нажимаются, «🟢» и чужие блоки — нет", () => {
  const { loaded, parts } = page({ build: choice });
  assert.equal(parts.alt1.getAttribute(PICK), "");
  assert.equal(parts.alt2.getAttribute(PICK), "");
  assert.equal(parts.green2.hasAttribute(PICK), false);
  assert.equal(parts.after.hasAttribute(PICK), false, "после следующего заголовка — уже не блок");
  assert.equal(nazh(loaded).picks, 3);
});

test("#7843 ВЫБОР: клик вписывает «Решение N: бери другой вариант — …», не отправляет; повтор — снимает", () => {
  const { loaded, parts, tick, click } = page({ build: choice });
  click(parts.alt2);
  assert.equal(field(loaded), "Решение 2: бери другой вариант — фиолетовый");
  assert.equal(parts.alt2.getAttribute(PICK), "on");
  for (let step = 0; step < 30; step += 1) tick();
  assert.equal(parts.send.__presses, 0, "ВЫБОР отправил сам");
  assert.equal(nazh(loaded).armed, false);
  click(parts.alt1);
  assert.equal(field(loaded), "Решение 2: бери другой вариант — фиолетовый; Решение 1: бери другой вариант — в localStorage страницы");
  click(parts.alt2);
  assert.equal(field(loaded), "Решение 1: бери другой вариант — в localStorage страницы");
  assert.equal(parts.alt2.getAttribute(PICK), "");
  click(parts.alt1);
  assert.equal(field(loaded), "");
});

test("#7843 ВЫБОР: два «⚪» одного решения сменяют друг друга", () => {
  const { loaded, parts, click } = page({ build: choice });
  click(parts.alt2);
  click(parts.alt2b);
  assert.equal(field(loaded), "Решение 2: бери другой вариант — синий акцент");
  assert.deepEqual([parts.alt2.getAttribute(PICK), parts.alt2b.getAttribute(PICK)], ["", "on"]);
});

test("#7843 ВЫБОР: номер без <ol> — из строки решения выше; свой текст в поле не трогается", () => {
  const { loaded, parts, click } = page({
    text: "мой черновик",
    build: (box, dom, parts2) => {
      box.add("h3", { text: "🔘 ВЫБОР" });
      box.add("p", { text: "3. Где рисовать кнопку" });
      const list = box.add("ul");
      list.add("li", { text: "🟢 под заголовком" });
      parts2.alt = list.add("li", { text: "⚪ в конце блока — дальше от глаз" });
    },
  });
  click(parts.alt);
  assert.equal(field(loaded), "мой черновик Решение 3: бери другой вариант — в конце блока");
  click(parts.alt);
  assert.equal(field(loaded), "мой черновик");
});

test("#7772: двойной клик по «⚪» — одно нажатие", () => {
  const { loaded, parts, click } = page({ build: choice });
  click(parts.alt1, { detail: 1 });
  click(parts.alt1, { detail: 2 });
  assert.equal(field(loaded), "Решение 1: бери другой вариант — в localStorage страницы");
});

// ---- «👾 ЭЛВИС, СДЕЛАЙ» ---------------------------------------------------------

const todo = (box, dom, parts) => {
  box.add("h2", { text: "👾 ЭЛВИС, СДЕЛАЙ" });
  const list = box.add("ol");
  parts.item1 = list.add("li");
  parts.item1p = dom.leaf(parts.item1, "p", "⚠️ Открой Системные настройки и дай доступ приложению PimpMyClaude к экрану");
  const steps = parts.item1.add("ul");
  steps.add("li", { text: "Нажми «Разрешить»" });
  parts.item2 = dom.leaf(list, "li", "Проверь окно");
  parts.item2.add("pre", { text: "bash tools/test.sh" });
};

test("#7843 СДЕЛАЙ: у каждого пункта «✓ сделал»; клик вписывает «Сделал: пункт N — …», не отправляет", () => {
  const { loaded, parts, tick, click } = page({ build: todo });
  const done = buttons(loaded, "done");
  assert.equal(done.length, 2, "у подпункта «Нажми» кнопки быть не должно");
  assert.ok(done[0].parentNode === parts.item1, "кнопка — прямой ребёнок пункта");
  // WF176 (#9198): кнопка — под первой строкой пункта: после его первого абзаца, до подпунктов.
  assert.ok(done[0].previousSibling === parts.item1p, "кнопка — сразу под первым абзацем пункта");
  assert.equal(done[0].nextSibling?.tagName, "UL", "подпункты — под кнопкой");
  assert.equal(label(done[0]), "✓ сделал");
  assert.equal(done[0].textContent, "", "подпись в тексте ответа — попадёт в копию");
  assert.equal(done[1].parentNode, parts.item2);
  assert.equal([...parts.item2.childNodes].indexOf(done[1]) < [...parts.item2.childNodes].indexOf(parts.item2.querySelector("pre")), true, "кнопка после кода");
  click(done[0]);
  assert.equal(field(loaded), "Сделал: пункт 1 — Открой Системные настройки и дай доступ приложению PimpMyClaude…");
  assert.equal(done[0].hasAttribute("data-myclaude-nazh-on"), true);
  click(buttons(loaded, "done")[1]);
  assert.equal(field(loaded), "Сделал: пункт 1 — Открой Системные настройки и дай доступ приложению PimpMyClaude…; Сделал: пункт 2 — Проверь окно");
  for (let step = 0; step < 30; step += 1) tick();
  assert.equal(parts.send.__presses, 0);
  click(buttons(loaded, "done")[0]);
  assert.equal(field(loaded), "Сделал: пункт 2 — Проверь окно");
});

test("z9-r09 СДЕЛАЙ: «👤 СДЕЛАЙ» комплекта команды — те же кнопки; «Сделайте вывод» — не блок", () => {
  const team = page({
    build: (box, dom, parts) => {
      box.add("h2", { text: "👤 СДЕЛАЙ" });
      dom.leaf(box.add("ol"), "li", "Проверь окно");
    },
  });
  assert.equal(buttons(team.loaded, "done").length, 1, "у «👤 СДЕЛАЙ» нет «✓ сделал»");
  const other = page({
    build: (box, dom) => {
      box.add("h2", { text: "Сделайте вывод" });
      dom.leaf(box.add("ol"), "li", "Проверь окно");
    },
  });
  assert.equal(buttons(other.loaded, "done").length, 0, "обычный заголовок со словом «сделайте» — не блок СДЕЛАЙ");
});

test("#7843 СДЕЛАЙ: номер — ol.start, когда список разорван", () => {
  const { loaded, click } = page({
    build: (box, dom) => {
      box.add("h2", { text: "👾 ЭЛВИС, СДЕЛАЙ" });
      dom.leaf(box.add("ol"), "li", "Первое дело");
      box.add("pre", { text: "echo 1" });
      dom.leaf(box.add("ol", { attrs: { start: "2" } }), "li", "Второе дело");
    },
  });
  click(buttons(loaded, "done")[1]);
  assert.equal(field(loaded), "Сделал: пункт 2 — Второе дело");
});

// ---- «🦾 Нужен …» ---------------------------------------------------------------

test("#7843 Нужен MAX: «разрешаю» / «нет» вписывают строку и сменяют друг друга, не отправляют", () => {
  const { loaded, parts, tick, click } = page({
    build: (box, dom, parts2) => {
      parts2.head = box.add("h2", { text: "🦾 Нужен Opus 🔥 MAX" });
      box.add("p", { text: "Задача: разбор архитектуры канала Пимп целиком" });
      box.add("p", { text: "Почему: EXTRA дважды упёрся" });
    },
  });
  const [yes] = buttons(loaded, "yes");
  const [no] = buttons(loaded, "no");
  assert.equal(yes.parentNode.previousElementSibling, parts.head, "кнопки — под заголовком");
  assert.deepEqual([label(yes), label(no)], ["разрешаю", "нет"]);
  click(yes);
  assert.equal(field(loaded), "Разрешаю: разбор архитектуры канала Пимп целиком");
  click(buttons(loaded, "no")[0]);
  assert.equal(field(loaded), "Не разрешаю: разбор архитектуры канала Пимп целиком");
  for (let step = 0; step < 30; step += 1) tick();
  assert.equal(parts.send.__presses, 0);
});

// ---- «📄 НУЖЕН ОТЧЁТ?» ----------------------------------------------------------

const report = (box, dom, parts) => {
  box.add("h2", { text: "📄 НУЖЕН ОТЧЁТ?" });
  parts.phrase = box.add("p", { text: "Сделать отчёт файлом: что сделано, что не работает? Скажи „отчёт“" });
  box.add("h2", { text: "👾 ЭЛВИС, СДЕЛАЙ" });
};

test("#7843 отчёт: кнопка после блока; клик — «отчёт» в поле, отсчёт 5, дотикал — отправлено", () => {
  const { loaded, parts, tick, click } = page({ build: report });
  const [button] = buttons(loaded, "report");
  assert.equal(button.parentNode.previousElementSibling, parts.phrase, "кнопка не после блока");
  assert.equal(parts.phrase.textContent.includes("отчёт"), true, "текст ответа не тронут");
  click(button);
  assert.equal(field(loaded), "отчёт");
  assert.deepEqual([nazh(loaded).armed, nazh(loaded).left], [true, 5]);
  assert.equal(label(button), "отчёт · 5");
  tick(1200);
  assert.equal(label(button), "отчёт · 4");
  tick(3000);
  assert.equal(parts.send.__presses, 0, "рано");
  tick(1000);
  assert.equal(parts.send.__presses, 0, "первые 5 с только включают настоящий счёт");
  assert.equal(loaded.api.status().sendDelay.counting, true);
  assert.equal(loaded.api.status().sendDelay.left, 5);
  for (let n = 0; n < 7; n += 1) loaded.dom.fireKind("timeout");
  assert.equal(parts.send.__presses, 1);
  assert.deepEqual([nazh(loaded).sends, nazh(loaded).armed, nazh(loaded).lines], [1, false, []]);
});

test("#7843 отчёт: клавиша в поле или своя правка — отсчёт гаснет; свой текст — без отсчёта", () => {
  const typed = page({ build: report });
  typed.click(buttons(typed.loaded, "report")[0]);
  typed.loaded.win.dispatchEvent({ type: "keydown", key: "a", target: typed.parts.editor, isTrusted: true });
  assert.equal(nazh(typed.loaded).armed, false);
  for (let step = 0; step < 20; step += 1) typed.tick();
  assert.equal(typed.parts.send.__presses, 0);

  const edited = page({ build: report });
  edited.click(buttons(edited.loaded, "report")[0]);
  edited.parts.editor.__text = "отчёт и ещё";
  edited.tick();
  assert.equal(nazh(edited.loaded).armed, false);
  for (let step = 0; step < 20; step += 1) edited.tick();
  assert.equal(edited.parts.send.__presses, 0);

  const own = page({ build: report, text: "подожди" });
  own.click(buttons(own.loaded, "report")[0]);
  assert.equal(field(own.loaded), "подожди отчёт");
  assert.equal(nazh(own.loaded).armed, false);
});

test("#7843 отчёт: повторный клик снимает слово и отсчёт", () => {
  const { loaded, parts, tick, click } = page({ build: report });
  click(buttons(loaded, "report")[0]);
  tick(2000);
  click(buttons(loaded, "report")[0]);
  assert.equal(field(loaded), "");
  assert.equal(nazh(loaded).armed, false);
  for (let step = 0; step < 20; step += 1) tick();
  assert.equal(parts.send.__presses, 0);
});

// ---- «❗ Включи Accept Edits» / «❗ Верни режим Авто» -------------------------------

const modes = (box, dom, parts) => {
  parts.accept = box.add("h2", { text: "❗ Включи Accept Edits" });
  box.add("p", { text: "Включи режим Accept Edits (переключатель под полем ввода) — тогда сделаю сам." });
  parts.auto = box.add("h2", { text: "❗ Верни режим Авто" });
  box.add("p", { text: "Переключи режим обратно на Авто" });
};

test("#7843 режим: «Включить» — меню, пункт Accept edits, в поле «Включил… — делай» без отправки; «Вернуть» — к Auto", async () => {
  const { loaded, parts, tick, click } = page({ build: modes });
  const [on] = buttons(loaded, "accept");
  const [back] = buttons(loaded, "auto");
  assert.deepEqual([label(on), label(back)], ["Включить", "Вернуть"]);
  click(on);
  await Promise.resolve();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(parts.pressed, ["Accept edits"]);
  assert.equal(parts.mode.textContent, "Accept edits");
  assert.equal(field(loaded), "Включил Accept Edits — делай");
  for (let step = 0; step < 30; step += 1) tick();
  assert.equal(parts.send.__presses, 0, "режим отправил сам");
  click(buttons(loaded, "auto")[0]);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(parts.pressed, ["Accept edits", "Auto mode"]);
  assert.equal(parts.mode.textContent, "Auto");
  assert.deepEqual([nazh(loaded).modes, nazh(loaded).modeFails], [2, 0]);
});

test("#7843 режим: «Вернуть» — к прежнему режиму (Ask), Bypass и Plan не жмутся никогда", async () => {
  const { loaded, parts, click } = page({ build: modes, mode: "Ask permissions", menu: ["Bypass permissions", "Plan mode", "Accept edits", "Ask permissions", "Auto mode"] });
  click(buttons(loaded, "accept")[0]);
  await new Promise(resolve => setImmediate(resolve));
  click(buttons(loaded, "auto")[0]);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(parts.pressed, ["Accept edits", "Ask permissions"]);
});

test("wf98-g-2 режим: «Вернуть» к Auto не жмёт «Auto-accept edits»", async () => {
  const { loaded, parts, click } = page({ build: modes, menu: ["Auto-accept edits", "Accept edits", "Plan mode", "Auto mode"] });
  click(buttons(loaded, "accept")[0]);
  await new Promise(resolve => setImmediate(resolve));
  click(buttons(loaded, "auto")[0]);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(parts.pressed, ["Accept edits", "Auto mode"]);
  assert.equal(parts.mode.textContent, "Auto");
});

test("#7843 режим: уже нужный — меню не открываем, плашка «уже»", async () => {
  const { loaded, parts, click } = page({ build: modes, mode: "Accept edits" });
  click(buttons(loaded, "accept")[0]);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(parts.opens, 0);
  assert.equal(nazh(loaded).modeNote, "Режим уже Accept edits");
  assert.equal(field(loaded), "Включил Accept Edits — делай");
});

test("#7843 режим: нет переключателя, свёрнутое поле, нет пункта — плашка, ничего не сломано", async () => {
  const none = page({ build: modes, chin: false });
  none.click(buttons(none.loaded, "accept")[0]);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(nazh(none.loaded).modeNote, "Не нашёл переключатель режима под полем");
  assert.equal(none.loaded.document.querySelector("#myclaude-new-window-note")?.textContent, "Не нашёл переключатель режима под полем");

  const folded = page({ build: modes });
  folded.parts.modelRow.setAttribute("data-myclaude-composer-block", "collapsed");
  folded.click(buttons(folded.loaded, "accept")[0]);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(folded.parts.opens, 0, "меню открыто в свёрнутом поле");
  assert.equal(nazh(folded.loaded).modeNote, "Разверни поле ввода — переключатель режима спрятан");
  assert.equal(field(folded.loaded), "");

  const bare = page({ build: modes, menu: ["Plan mode", "Bypass permissions", "Auto mode"] });
  // Часы страницы идут вперёд с каждым шагом опроса: меню ждут NAZH_MENU_MS.
  let shift = 0;
  const base = Date.now();
  bare.loaded.win.performance.now = () => base + shift;
  bare.click(buttons(bare.loaded, "accept")[0]);
  for (let round = 0; round < 60 && bare.loaded.dom.ids("timeout").length; round += 1) {
    shift += 100;
    bare.loaded.dom.fireKind("timeout");
    await new Promise(resolve => setImmediate(resolve));
    if (nazh(bare.loaded).modeFails) break;
  }
  assert.deepEqual(bare.parts.pressed, [], "нажат чужой пункт");
  assert.equal(nazh(bare.loaded).modeNote, "Не нашёл «Accept edits» в меню режима");
  assert.equal(bare.parts.mode.textContent, "Auto");
});

test("#7772: пока режим переключается — кнопка приглушена, повтор ничего не делает", async () => {
  const { loaded, parts, click } = page({ build: modes, menuLate: true });
  const [on] = buttons(loaded, "accept");
  click(on);
  assert.equal(on.getAttribute("aria-disabled"), "true");
  assert.equal(label(on), "Включаю…");
  click(on);
  click(buttons(loaded, "auto")[0]);
  assert.equal(parts.opens, 0);
  parts.openLater();
  for (let round = 0; round < 10 && nazh(loaded).modeBusy; round += 1) {
    loaded.dom.fireKind("timeout");
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.deepEqual(parts.pressed, ["Accept edits"]);
  assert.equal(on.hasAttribute("aria-disabled"), false);
  assert.equal(label(on), "Включить");
  assert.equal(nazh(loaded).modes, 1);
});

test("#7843 «❗ Верни режим Авто» мигает, как «Включи Accept Edits»", () => {
  const nodes = {};
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Trelvis", hasFocus: false,
    storage: { local: { "myclaude-auto-allow-roam": "off", "myclaude-send-delay-seconds": "5" } },
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", {
        attrs: { "data-testid": "epitaxy-virtual-transcript" },
        rect: { left: 0, top: 0, width: 1200, height: 500 }, computed: { overflowY: "auto" },
      });
      Object.assign(feed, { clientHeight: 500, scrollHeight: 2000, scrollTop: 100 });
      const answer = feed.add("div", { attrs: { "data-testid": "assistant-message" } });
      nodes.head = answer.add("h2", { text: "❗ Верни режим Авто" });
      answer.add("p", { text: "Переключи режим обратно на Авто" });
      nodes.stop = dom.document.body.add("button", { attrs: { "data-testid": "code-prompt-stop" } });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  let t = Date.now();
  const tick = () => { t += 500; loaded.inner.attnTick(t); };
  tick();
  nodes.stop.remove();
  for (let spent = 0; spent <= 4000; spent += 500) tick();
  assert.equal(nodes.head.hasAttribute("data-myclaude-attn"), true);
});

// ---- #7842 «продолжим в другом чате» ------------------------------------------

const offerPage = (paras, extra = {}) => page({
  ...extra,
  build: (box, dom, parts) => {
    box.add("h2", { text: "Готово" });
    parts.paras = paras.map(([tag, text]) => {
      if (tag === "pre") return box.add("pre").add("code", { text });
      if (tag === "blockquote") return box.add("blockquote").add("p", { text });
      if (tag === "h3") return box.add("h3", { text });
      if (tag === "li") return box.add("ul").add("li", { text });
      return box.add(tag, { text });
    });
    extra.build2?.(box, dom, parts);
  },
});
const STATUS = "🟠[PimpMyClaude](docs/status.md) · WF 1 из 3 · жду ❓";
const FOOTER = "Контекст 384K";

test("#7842: предложение продолжить в новом чате — под абзацем «💬 Новый чат»; клик — просьба в поле, отсчёт, отправка", () => {
  const { loaded, parts, tick, click } = offerPage([
    ["p", "Сделал всё по плану."],
    ["p", "Контекст почти кончился — предлагаю продолжить в новом чате."],
    ["p", STATUS],
    ["p", FOOTER],
  ]);
  const [button] = buttons(loaded, "chat");
  assert.ok(button, "кнопки нет");
  assert.equal(button.parentNode.previousElementSibling, parts.paras[1]);
  assert.equal(label(button), "💬 Новый чат");
  assert.equal(button.parentNode.hasAttribute("data-myclaude-continue"), false, "атрибут 12к — markContinue снесёт");
  assert.equal(nazh(loaded).offer, true);
  click(button);
  assert.equal(field(loaded), CHAT_TEXT);
  assert.equal(label(buttons(loaded, "chat")[0]), "💬 Новый чат · 5");
  tick(5100);
  assert.equal(parts.send.__presses, 0, "первые 5 с только включают настоящий счёт");
  assert.equal(loaded.api.status().sendDelay.counting, true);
  assert.equal(loaded.api.status().sendDelay.left, 5);
  for (let n = 0; n < 7; n += 1) loaded.dom.fireKind("timeout");
  assert.equal(parts.send.__presses, 1);
});

test("#7842: разные формы предложения ловятся, отказ и рассказ — нет", () => {
  const { loaded } = page();
  const yes = [
    "Давай продолжим в новом чате — этот тяжёлый.",
    "Лучше продолжить работу в другом чате.",
    "Продолжим в свежем чате?",
    "Предлагаю новый чат: контекст большой.",
    "Стоит перейти в новый чат.",
  ];
  const no = [
    "Не стоит продолжать в новом чате, всё влезает.",
    "В прошлом чате мы продолжили в новом чате без проблем.",
    "Кнопка «Новый чат» теперь работает.",
    "Чат открылся в новом окне.",
    // wf98-g-2: отрицание в прокладке, «другие чаты», вкладка браузера.
    "Лучше не продолжать в новом чате.",
    "Лучше другие чаты не трогать.",
    "Файл стоит открыть в новом чате браузера.",
    "Можно открыть в новом чате Chrome.",
    "Давай продолжим в новом чатике.",
  ];
  for (const text of yes) assert.equal(loaded.inner.nazhOffer(text), true, text);
  for (const text of no) assert.equal(loaded.inner.nazhOffer(text), false, text);
});

test("#7842: в коде, цитате, заголовке и далеко от конца — кнопки нет", () => {
  const cases = [
    [["pre", "предлагаю продолжить в новом чате"], ["p", "Готово."]],
    [["blockquote", "Давай продолжим в новом чате"], ["p", "Это цитата из прошлого ответа."]],
    [["h3", "Предлагаю продолжить в новом чате"], ["p", "Готово."]],
    [["p", "Предлагаю продолжить в новом чате."], ["p", "Потом."], ["p", "И ещё абзац."]],
  ];
  for (const paras of cases) {
    const { loaded } = offerPage(paras);
    assert.equal(buttons(loaded, "chat").length, 0, JSON.stringify(paras));
  }
});

test("#7842: пункт списка в конце — кнопка после списка", () => {
  const { loaded, parts } = offerPage([["p", "Итог."], ["li", "давай продолжим в другом чате"]]);
  const [button] = buttons(loaded, "chat");
  assert.equal(button.parentNode.previousElementSibling, parts.paras[1].parentNode);
});

test("#7842: блок «ОТКРОЙ НОВЫЙ ЧАТ» уже есть, ход идёт, после ответа реплика Элвиса — кнопки нет", () => {
  const handoff = offerPage([["p", "Предлагаю продолжить в новом чате."]], {
    build2: box => { box.add("h2", { text: "🆕 ОТКРОЙ НОВЫЙ ЧАТ" }); },
  });
  assert.equal(buttons(handoff.loaded, "chat").length, 0, "блок передачи есть");

  const working = offerPage([["p", "Предлагаю продолжить в новом чате."]], { working: true });
  assert.equal(buttons(working.loaded, "chat").length, 0, "ход идёт");

  const answered = offerPage([["p", "Предлагаю продолжить в новом чате."]]);
  answered.parts.feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "human" } });
  answered.tick();
  assert.equal(buttons(answered.loaded, "chat").length, 0, "Элвис уже ответил");
});

test("#7842: отсчёт один на окно — «отчёт» сменяет «💬 Новый чат»", () => {
  const { loaded, parts, tick, click } = offerPage([["p", "Предлагаю продолжить в новом чате."]], { build2: report });
  click(buttons(loaded, "chat")[0]);
  click(buttons(loaded, "report")[0]);
  assert.equal(field(loaded), "отчёт");
  assert.equal(nazh(loaded).armed, true);
  tick(5100);
  assert.equal(parts.send.__presses, 0, "первые 5 с только включают настоящий счёт");
  assert.equal(loaded.api.status().sendDelay.counting, true);
  assert.equal(loaded.api.status().sendDelay.left, 5);
  for (let n = 0; n < 7; n += 1) loaded.dom.fireKind("timeout");
  assert.equal(parts.send.__presses, 1);
  assert.equal(nazh(loaded).sends, 1);
});

// ---- Общие правила ---------------------------------------------------------------

test("#7843: новый ход и смена чата сбрасывают вписанное; dispose убирает кнопки и метки", () => {
  const { loaded, parts, tick, click } = page({ build: choice });
  click(parts.alt1);
  assert.equal(nazh(loaded).lines.length, 1);
  const stop = loaded.dom.document.body.add("button", { attrs: { "data-testid": "code-prompt-stop" } });
  tick();
  assert.deepEqual(nazh(loaded).lines, []);
  stop.remove();
  tick();
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll(`[${PICK}]`).length, 0);
  assert.equal(loaded.dom.queryAll(`[${BUTTON}]`).length, 0);
});

test("#7843: повторная установка не плодит кнопки", () => {
  const { loaded } = page({ build: todo });
  assert.equal(buttons(loaded, "done").length, 2);
  const again = loaded.reload();
  assert.equal(again.error, null, String(again.error?.stack ?? again.error));
  again.inner.nazhTick(Date.now());
  assert.equal(buttons(loaded, "done").length, 2);
  assert.equal(again.inner.nazhState.info.size, 2);
});

test("#7852: кнопки нажималок без перелива; стили — подпись из атрибута", () => {
  const { loaded } = page({ build: todo });
  const css = loaded.dom.queryAll("style").map(style => style.textContent).join("\n");
  assert.match(css, /\[data-myclaude-nazh-button\]::after\{content:attr\(data-myclaude-nazh-label\)\}/);
  assert.equal(buttons(loaded, "done").some(node => node.hasAttribute("data-myclaude-busy")), false);
  assert.doesNotMatch(css, /nazh[^{}]*\{[^}]*myclaude-busy-flow/);
});

for (const cancel of ["escape", "click", "edit"]) {
  test(`#8283: после первых 5 с настоящий отсчёт отменяется ${cancel}`, () => {
    const { loaded, tick, click } = page({ build: report });
    click(buttons(loaded, "report")[0]);
    tick(5100);
    assert.equal(loaded.api.status().sendDelay.counting, true);
    assert.equal(loaded.parts.send.__presses, 0);
    if (cancel === "escape") loaded.win.dispatchEvent({ type: "keydown", key: "Escape", isTrusted: true, target: loaded.parts.editor });
    else if (cancel === "click") loaded.document.dispatchEvent({ type: "click", target: loaded.parts.send, isTrusted: true });
    else loaded.parts.editor.__text += " дополнение";
    for (let n = 0; n < 8; n += 1) loaded.dom.fireKind("timeout");
    assert.equal(loaded.api.status().sendDelay.counting, false);
    assert.equal(loaded.api.status().sendDelay.cancelled, 1);
    assert.equal(loaded.api.status().nazh.sends, 0);
    assert.equal(loaded.parts.send.__presses, 0);
    assert.ok(loaded.parts.editor.textContent);
  });
}

test("#7891: изменение поля в начальном счёте отменяет его на первом тике", () => {
  const { loaded, tick, click } = page({ build: report });
  click(buttons(loaded, "report")[0]);
  loaded.parts.editor.__text += " новый текст";
  tick(200);
  assert.equal(loaded.api.status().nazh.armed, false);
  assert.equal(loaded.api.status().sendDelay.started, 0);
});

// #7973: только явное ручное «Включить», один откат Au→Ac, без правки draft.
const modeSettle = () => new Promise(resolve => setImmediate(resolve));
const guardBeat = (loaded, t) => loaded.inner.modeGuardTick(t);
const armMode = async q => {
  q.click(buttons(q.loaded, 'accept')[0]); await modeSettle();
  assert.equal(q.loaded.inner.modeGuard.armed, true);
};

test('#7973: initial Ac and synthetic own click do not arm or touch draft', async () => {
  const q = page({ build: modes, mode: 'Accept edits' });
  assert.equal(q.loaded.inner.modeGuard.armed, false);
  q.click(buttons(q.loaded, 'accept')[0], { isTrusted: false }); await modeSettle();
  assert.equal(q.loaded.inner.modeGuard.armed, false); assert.equal(field(q.loaded), '');
  q.parts.mode.textContent = 'Auto'; guardBeat(q.loaded, 1000); guardBeat(q.loaded, 3000);
  assert.deepEqual(q.parts.pressed, []); q.loaded.api.dispose();
});

test('#7973: trusted enable/readback arms one correction, preserves draft, never retries next reset', async () => {
  const q = page({ build: modes }); await armMode(q);
  q.parts.editor.__text = 'Мой следующий черновик';
  q.parts.mode.textContent = 'Auto'; guardBeat(q.loaded, 1000); guardBeat(q.loaded, 1999);
  assert.deepEqual(q.parts.pressed, ['Accept edits']);
  guardBeat(q.loaded, 2000); await modeSettle();
  assert.deepEqual(q.parts.pressed, ['Accept edits', 'Accept edits']);
  assert.equal(field(q.loaded), 'Мой следующий черновик');
  assert.equal(q.loaded.inner.modeGuard.armed, false);
  assert.equal(q.loaded.inner.modeGuard.attempts, 1);
  assert.equal(q.loaded.inner.modeGuard.result, 'ok');
  q.parts.mode.textContent = 'Auto'; guardBeat(q.loaded, 3000); guardBeat(q.loaded, 5000); await modeSettle();
  assert.equal(q.parts.pressed.length, 2); assert.equal(q.parts.send.__presses, 0); q.loaded.api.dispose();
});

for (const label of ['Auto', 'Ask permissions', 'Plan mode', 'Bypass permissions']) test(`#7973: manual native ${label} cancels; menuitem never arms intent`, async () => {
  const q = page({ build: modes }); await armMode(q);
  const menu = q.loaded.document.body.add('div', { attrs: { role: 'menu' } });
  const item = menu.add('div', { attrs: { role: 'menuitemradio' }, text: label });
  q.loaded.document.dispatchEvent({ type: 'click', target: item, isTrusted: true });
  q.parts.mode.textContent = label; menu.remove();
  guardBeat(q.loaded, 1000); q.parts.mode.textContent = 'Auto'; guardBeat(q.loaded, 3000); await modeSettle();
  assert.equal(q.loaded.inner.modeGuard.armed, false); assert.equal(q.parts.pressed.length, 1); q.loaded.api.dispose();
});

for (const label of ['Ask permissions', 'Plan mode', 'Bypass permissions']) test(`#7973: observed ${label} never auto-switches even without interaction event`, async () => {
  const q = page({ build: modes }); await armMode(q);
  q.parts.mode.textContent = label; guardBeat(q.loaded, 1000); guardBeat(q.loaded, 3000); await modeSettle();
  assert.equal(q.loaded.inner.modeGuard.armed, false); assert.equal(q.parts.pressed.length, 1); q.loaded.api.dispose();
});

test('#7973: own Return cancels; typing and Enter pause until quiet, then one unexpected Au correction', async () => {
  const q = page({ build: modes }); await armMode(q);
  q.click(buttons(q.loaded, 'auto')[0]); await modeSettle();
  guardBeat(q.loaded, 1000); guardBeat(q.loaded, 3000); await modeSettle();
  assert.deepEqual(q.parts.pressed, ['Accept edits', 'Auto mode']);
  await armMode(q);
  let clock = q.loaded.win.performance.now(); q.loaded.win.performance.now = () => clock;
  q.loaded.win.dispatchEvent({ type: 'pointerdown', target: q.parts.editor, isTrusted: true });
  q.loaded.win.dispatchEvent({ type: 'keydown', key: 'a', target: q.parts.editor, isTrusted: true });
  q.parts.editor.__text = 'Продолжай';
  q.loaded.document.dispatchEvent({ type: 'input', target: q.parts.editor, isTrusted: true });
  clock += 500;
  q.loaded.win.dispatchEvent({ type: 'keydown', key: 'Enter', target: q.parts.editor, isTrusted: true });
  q.parts.editor.__text = '';
  assert.equal(q.loaded.inner.modeGuard.armed, true);
  q.parts.mode.textContent = 'Auto';
  guardBeat(q.loaded, clock + 1999); await modeSettle(); assert.equal(q.parts.pressed.length, 3);
  guardBeat(q.loaded, clock + 2000); guardBeat(q.loaded, clock + 2999); await modeSettle(); assert.equal(q.parts.pressed.length, 3);
  guardBeat(q.loaded, clock + 3000); await modeSettle();
  assert.equal(q.parts.pressed.length, 4); assert.equal(q.parts.mode.textContent, 'Accept edits');
  assert.equal(field(q.loaded), ''); assert.equal(q.loaded.inner.modeGuard.armed, false); q.loaded.api.dispose();
});

for (const action of ['mode-control', 'shift-tab']) test(`#7973: explicit ${action} disarms while ordinary input only pauses`, async () => {
  const q = page({ build: modes }); await armMode(q);
  if (action === 'mode-control') q.loaded.win.dispatchEvent({ type: 'pointerdown', target: q.parts.mode, isTrusted: true });
  else q.loaded.win.dispatchEvent({ type: 'keydown', key: 'Tab', shiftKey: true, target: q.parts.editor, isTrusted: true });
  q.parts.mode.textContent = 'Auto'; guardBeat(q.loaded, 1000); guardBeat(q.loaded, 5000); await modeSettle();
  assert.equal(q.loaded.inner.modeGuard.armed, false); assert.equal(q.parts.pressed.length, 1); q.loaded.api.dispose();
});

test('#7973: trusted input during awaited correction cancels token and cannot retry', async () => {
  const q = page({ build: modes, menuLate: true });
  q.click(buttons(q.loaded, 'accept')[0]); q.parts.openLater(); q.loaded.dom.fireKind('timeout'); await modeSettle();
  q.parts.mode.textContent = 'Auto'; guardBeat(q.loaded, 1000); guardBeat(q.loaded, 2000);
  assert.equal(q.loaded.inner.modeGuard.attempts, 1);
  q.loaded.win.dispatchEvent({ type: 'keydown', key: 'a', target: q.parts.editor, isTrusted: true });
  q.parts.openLater(); q.loaded.dom.fireKind('timeout'); await modeSettle();
  assert.equal(q.parts.pressed.length, 1); assert.equal(q.loaded.inner.modeGuard.armed, false);
  guardBeat(q.loaded, 4000); guardBeat(q.loaded, 8000); await modeSettle();
  assert.equal(q.parts.pressed.length, 1); assert.equal(q.loaded.inner.modeGuard.attempts, 1); q.loaded.api.dispose();
});

test('#7973: chat changes while menu awaits — no target click, no draft insertion, no arm', async () => {
  const q = page({ build: modes, menuLate: true });
  q.click(buttons(q.loaded, 'accept')[0]);
  q.loaded.win.location.pathname = '/epitaxy/local_other';
  q.parts.openLater(); q.loaded.dom.fireKind('timeout'); await modeSettle();
  assert.deepEqual(q.parts.pressed, []); assert.equal(field(q.loaded), '');
  assert.equal(q.loaded.inner.modeGuard.armed, false); q.loaded.api.dispose();
});

test('#7973: chat changes during target click — readback cannot arm or write into next draft', async () => {
  const q = page({ build: modes, menuLate: true }); q.click(buttons(q.loaded, 'accept')[0]);
  q.parts.openLater();
  const item = q.loaded.dom.queryAll('[role="menuitemradio"]').find(node => node.textContent === 'Accept edits');
  item.addEventListener('pointerdown', () => { q.loaded.win.location.pathname = '/epitaxy/local_other'; });
  q.loaded.dom.fireKind('timeout'); await modeSettle();
  assert.deepEqual(q.parts.pressed, ['Accept edits']); assert.equal(field(q.loaded), '');
  assert.equal(q.loaded.inner.modeGuard.armed, false); q.loaded.api.dispose();
});

for (const cause of ['duplicate-control', 'menu', 'roam', 'chat', 'dispose']) test(`#7973: ${cause} disarms an already granted one-shot`, async () => {
  const q = page({ build: modes }); await armMode(q); q.parts.mode.textContent = 'Auto';
  if (cause === 'duplicate-control') q.parts.mode.parentNode.add('button', { text: 'Auto' });
  if (cause === 'menu') q.loaded.document.body.add('div', { attrs: { role: 'menu' } });
  if (cause === 'roam') q.loaded.inner.roamState.phase = 'opening';
  if (cause === 'chat') q.loaded.win.location.pathname = '/epitaxy/local_other';
  if (cause === 'dispose') q.loaded.api.dispose();
  guardBeat(q.loaded, 1000); guardBeat(q.loaded, 3000); await modeSettle();
  assert.equal(q.loaded.inner.modeGuard.armed, false); assert.equal(q.parts.pressed.length, 1); q.loaded.api?.dispose();
});

test('#7973: correction awaits menu with same chat guard, timeout consumes attempt without retry', async () => {
  const q = page({ build: modes, menuLate: true });
  q.click(buttons(q.loaded, 'accept')[0]); q.parts.openLater(); q.loaded.dom.fireKind('timeout'); await modeSettle();
  assert.equal(q.loaded.inner.modeGuard.armed, true);
  let clock = q.loaded.win.performance.now(); q.loaded.win.performance.now = () => clock;
  q.parts.mode.textContent = 'Auto'; guardBeat(q.loaded, 1000); guardBeat(q.loaded, 2000);
  clock += 3100; q.loaded.dom.fireKind('timeout'); await modeSettle();
  assert.equal(q.loaded.inner.modeGuard.armed, false); assert.equal(q.loaded.inner.modeGuard.attempts, 1);
  guardBeat(q.loaded, 4000); guardBeat(q.loaded, 6000); assert.equal(q.parts.pressed.length, 1); q.loaded.api.dispose();
});

const DONE_LIST = "data-myclaude-done-list";
const DONE_ITEM = "data-myclaude-done-item";
const DONE_CONT = "data-myclaude-done-continuation";
const splitTodo = (box, dom, parts) => {
  parts.head = box.add("h2", { text: "👾 ЭЛВИС, СДЕЛАЙ" });
  parts.before = box.add("p", { text: "До списка" });
  parts.ol = box.add("ol", { attrs: { start: "10" } });
  parts.first = dom.leaf(parts.ol, "li", "Первое действие");
  parts.inside = dom.leaf(parts.first, "p", "Пояснение внутри пункта");
  parts.second = dom.leaf(parts.ol, "li", "Следующее действие");
  parts.second.setAttribute("value", "100");
  parts.third = dom.leaf(parts.ol, "li", "Последнее действие");
  parts.para = box.add("p", { text: "Продолжение пункта" });
  parts.codeBox = box.add("div");
  parts.pre = parts.codeBox.add("pre");
  parts.code = parts.pre.add("code", { text: "echo проверка" });
  parts.copy = parts.codeBox.add("button", { text: "Copy" });
  parts.copyCalls = 0;
  parts.copy.addEventListener("click", () => { parts.copyCalls++; });
  parts.steps = box.add("ul");
  parts.sub = dom.leaf(parts.steps, "li", "Подчинённый шаг");
  parts.sub.add("ol").add("li", { text: "Вложенный шаг без кнопки" });
  parts.link = parts.para.add("a", { text: "ссылка", attrs: { href: "https://example.com" } });
  parts.nextList = box.add("ol", { attrs: { start: "102" } });
  parts.nextItem = dom.leaf(parts.nextList, "li", "Пункт после кода");
  box.add("h2", { text: "Другой раздел" });
  parts.outside = box.add("p", { text: "Не продолжение" });
};

test("WF119 СДЕЛАЙ: первая кнопка в li, родные start/value, разорванные p/pre/ul без переноса DOM", () => {
  const { loaded, parts, click } = page({ text: "мой черновик", build: splitTodo });
  const done = buttons(loaded, "done");
  assert.equal(done.length, 4);
  // WF176 (#9198): строка без абзаца — кнопка перед первым блоком пункта, одни строки — в конце.
  assert.ok(done[0].nextSibling === parts.inside, "под строкой пункта, перед его абзацем");
  for (const [i, li] of [parts.first, parts.second, parts.third, parts.nextItem].entries()) {
    if (i > 0) assert.ok(li.lastChild === done[i], "пункт в одну строку — кнопка под ней");
    assert.equal(li.getAttribute(DONE_ITEM), "");
    assert.equal(done[i].textContent, "");
  }
  assert.equal(parts.ol.getAttribute("start"), "10");
  assert.equal(parts.second.getAttribute("value"), "100");
  assert.equal(parts.ol.getAttribute(DONE_LIST), "");
  for (const node of [parts.para, parts.codeBox, parts.steps]) assert.equal(node.getAttribute(DONE_CONT), "");
  assert.ok(parts.codeBox.parentNode === parts.box);
  assert.ok(parts.inside.parentNode === parts.first);
  assert.ok(parts.pre.parentNode === parts.codeBox);
  for (const node of [parts.before, parts.outside, parts.sub]) assert.equal(node.hasAttribute(DONE_CONT), false);
  for (const [i, number] of [10, 100, 101, 102].entries()) {
    click(done[i], { detail: 0 }); // Клавиатурная активация нативной button.
    assert.match(field(loaded), new RegExp(`Сделал: пункт ${number} —`));
    click(done[i], { detail: 0 });
    assert.equal(field(loaded), "мой черновик");
  }
  parts.copy.dispatchEvent({ type: "click" });
  assert.equal(parts.copyCalls, 1);
  assert.equal(parts.link.getAttribute("href"), "https://example.com");
  assert.equal(parts.code.textContent, "echo проверка");
  assert.equal(parts.send.__presses, 0);
  loaded.api.dispose();
});

test("WF119 СДЕЛАЙ: React вставил текст перед абзацем — кнопка встаёт под строку без дублей", () => {
  const { loaded, parts, tick } = page({ build: todo });
  const text = loaded.document.createTextNode("Уточнение ");
  parts.item1.insertBefore(text, parts.item1.firstChild);
  tick();
  const own = () => [...parts.item1.childNodes].filter(node => node.getAttribute?.(BUTTON) === "done");
  assert.equal(own().length, 1);
  assert.ok(parts.item1.childNodes[0] === text, "текст React — на своём месте");
  assert.ok(own()[0].nextSibling === parts.item1p, "строка без абзаца — кнопка перед первым блоком");
  const stable = own()[0];
  tick(); tick();
  assert.ok(own()[0] === stable, "без изменений не пересоздаётся");
  assert.equal(buttons(loaded, "done").length, 2);
  loaded.api.dispose();
});

for (const barrier of ["hr", "service", "user", "interactive", "button", "heading"]) {
  test(`WF119 СДЕЛАЙ: продолжения не переходят через ${barrier}`, () => {
    const { loaded, parts } = page({ build: (box, dom, parts) => {
      box.add("h2", { text: "СДЕЛАЙ" });
      dom.leaf(box.add("ol"), "li", "Пункт");
      parts.cont = box.add("p", { text: "Пояснение" });
      if (barrier === "hr") box.add("hr");
      if (barrier === "service") box.add("p", { text: "1 · готово ✅" });
      if (barrier === "user") box.add("div", { class: "epitaxy-user-turn", text: "Реплика" });
      if (barrier === "interactive") box.add("div", { attrs: { role: "dialog" } }).add("button", { text: "Ввод" });
      if (barrier === "button") box.add("p").add("button", { text: "Чужое действие" });
      if (barrier === "heading") box.add("h3", { text: "Новый раздел" });
      parts.after = box.add("pre", { text: "чужой код" });
    } });
    assert.equal(parts.cont.getAttribute(DONE_CONT), "");
    assert.equal(parts.after.hasAttribute(DONE_CONT), false);
    loaded.api.dispose();
  });
}

test("WF119 СДЕЛАЙ: два блока размечены отдельно; удаление/смена заголовка/reinject/dispose очищают метки", () => {
  const { loaded, parts, tick } = page({ build: splitTodo });
  parts.box.add("h2", { text: "СДЕЛАЙ" });
  const extra = parts.box.add("ol"); loaded.dom.leaf(extra, "li", "Ещё пункт");
  tick();
  assert.equal(extra.getAttribute(DONE_LIST), "");
  parts.para.remove(); tick();
  assert.equal(parts.para.hasAttribute(DONE_CONT), false);
  parts.head.textContent = "Другая тема"; tick();
  assert.equal(parts.ol.hasAttribute(DONE_LIST), false);
  assert.equal(parts.first.hasAttribute(DONE_ITEM), false);
  assert.equal(parts.codeBox.hasAttribute(DONE_CONT), false);
  assert.equal(extra.hasAttribute(DONE_LIST), true);
  assert.equal(loaded.reload().error, null);
  loaded.inner.nazhTick(Date.now());
  assert.equal(extra.hasAttribute(DONE_LIST), true);
  loaded.api.dispose();
  assert.equal(loaded.document.querySelectorAll(`[${DONE_LIST}],[${DONE_ITEM}],[${DONE_CONT}]`).length, 0);
});

test("WF119 СДЕЛАЙ: нет доказанного ответа — продолжения не помечаются", () => {
  const { loaded, parts, tick } = page({ build: splitTodo });
  parts.box.parentElement.removeAttribute("data-testid");
  tick();
  assert.equal(parts.para.hasAttribute(DONE_CONT), false);
  assert.equal(parts.codeBox.hasAttribute(DONE_CONT), false);
  loaded.api.dispose();
});

for (const on of [true, false]) {
  test(`WF119 отчёт: первые 5 с, затем ${on ? "10 с" : "off"}, отправка одна`, () => {
    const { loaded, parts, tick, click } = page({ build: report });
    loaded.dom.command({ id: "wf119-report", action: "send-delay", on, seconds: 10 });
    click(buttons(loaded, "report")[0]);
    tick(4900);
    assert.equal(loaded.api.status().sendDelay.released, 0);
    assert.equal(loaded.api.status().sendDelay.started, 0);
    tick(200);
    assert.equal(loaded.api.status().sendDelay.counting, on);
    assert.equal(loaded.api.status().sendDelay.left, on ? 10 : 0);
    for (let n = 0; n < (on ? 12 : 2); n++) loaded.dom.fireKind("timeout");
    assert.equal(parts.send.__presses, 1);
    assert.equal(nazh(loaded).sends, 1);
    // WF128 К1 v3: взлёт 1.8 у кнопки законен, летящих цифр (1.3) нет.
    assert.equal(loaded.document.querySelectorAll(".myclaude-send-look-fly").length, 0);
    if (!on) assert.equal(loaded.document.getElementById("myclaude-send-delay-digits"), null);
    loaded.api.dispose();
  });
}

for (const mode of ['Accept edits', 'Auto', 'Ask permissions', 'Plan mode']) test(`WF121: Allow в ${mode} не выбирает режим и не меняет черновик`, () => {
  const q = page({ mode, text: 'Мой черновик' });
  q.loaded.win.localStorage.setItem('myclaude.autoAllowOnce', 'true');
  const card = q.loaded.document.body.add('div', { class: 'epitaxy-approval-card', text: 'Allow Claude to run Bash: git status', rect: { width: 400, height: 140 } });
  let once = 0, always = 0;
  card.add('button', { text: 'Allow once', rect: { width: 100, height: 28 } }).addEventListener('click', () => once++);
  card.add('button', { text: 'Always allow', rect: { width: 100, height: 28 } }).addEventListener('click', () => { always++; q.parts.mode.textContent = 'Auto'; });
  q.loaded.inner.autoAllowCycle();
  assert.equal(once, 1, 'разовое разрешение нажато; Always, меняющий режим в стенде, не тронут');
  assert.equal(always, 0); assert.equal(q.parts.opens, 0);
  assert.equal(q.parts.mode.textContent, mode); assert.equal(field(q.loaded), 'Мой черновик');
  q.loaded.api.dispose();
});

test('WF121: начало обхода разоружает guard до первого перехода даже при быстром A→B→A', async () => {
  const q = page({ build: modes }); await armMode(q);
  const token = q.loaded.inner.modeGuard.token;
  q.loaded.inner.roamStart({ id: 'local_bbbb', title: 'B' }, Date.now());
  assert.equal(q.loaded.inner.modeGuard.armed, false);
  assert.ok(q.loaded.inner.modeGuard.token > token);
  q.loaded.inner.roamState.phase = 'idle'; // мгновенный возврат между тиками
  q.parts.mode.textContent = 'Auto'; guardBeat(q.loaded, 1000); guardBeat(q.loaded, 5000); await modeSettle();
  assert.equal(q.parts.pressed.length, 1); q.loaded.api.dispose();
});

test('WF121: обход во время await переключателя отменяет token, позднее меню не нажимается', async () => {
  const q = page({ build: modes, menuLate: true });
  q.click(buttons(q.loaded, 'accept')[0]);
  const token = q.loaded.inner.modeGuard.token;
  q.loaded.inner.roamStart({ id: 'local_bbbb', title: 'B' }, Date.now());
  assert.ok(q.loaded.inner.modeGuard.token > token);
  q.loaded.inner.roamState.phase = 'idle';
  q.parts.openLater(); q.loaded.dom.fireKind('timeout'); await modeSettle();
  assert.deepEqual(q.parts.pressed, []); assert.equal(field(q.loaded), '');
  assert.equal(q.loaded.inner.modeGuard.armed, false); q.loaded.api.dispose();
});
