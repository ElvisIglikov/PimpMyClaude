// Черновик переезжает при смене чата (#11201, WF302, раздел 12ч inject.js). Слово Элвиса 30.10 ~17:45:
// «Я там скриншоты ещё закреплял, скриншоты не закрепились… И где мне скриншоты искать?… диктовки ещё
// куски большие не вставились». renew главного окна (new-window со stay, без sendTransfer) открывает
// новый чат в ТОМ ЖЕ окне: набранное и вложения прежнего поля теперь едут в поле нового чата —
// без отправки; пустой черновик — путь прежний; сорвалось — черновик остаётся в прежнем чате.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const drain = () => new Promise(resolve => setImmediate(resolve));
const settle = async (times = 6) => { for (let index = 0; index < times; index += 1) await drain(); };
const RENEW = "Ты — Рик. Продолжай.";
const DRAFT = "Надиктовал кусок: цена 3 290, тема номер семь";

// Главное окно Рика на прежнем чате: поле ввода (оно же code-prompt-input), отправка, недавние.
// ⌘N (его жмёт Swift) — `newChatKey()`: адрес /epitaxy, поле пустое, плиток нет. Отправка —
// адрес нового чата и пустое поле, как у Claude. Принятый файл Claude рисует плиткой.
const rick = ({ draft = DRAFT, accept = true } = {}) => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_old", title: "Claude",
    html: dom => {
      const parts = dom.composer({ text: draft });
      parts.editor.setAttribute("data-testid", "code-prompt-input");
      parts.send = dom.document.body.add("button", { attrs: { "data-testid": "code-prompt-send" } });
      parts.recents = dom.document.body.add("div", { attrs: { "data-testid": "sidebar-recents" } });
      parts.recents.add("div", { attrs: { "data-row-key": "code:local_old" }, text: "Рик" });
      return parts;
    },
  });
  const { parts } = loaded;
  const box = { sent: [], pills: [], pasted: [] };
  parts.send.addEventListener("click", () => {
    box.sent.push(parts.editor.textContent);
    parts.editor.textContent = "";
    loaded.win.location.pathname = "/epitaxy/local_new";
    parts.recents.add("div", { attrs: { "data-row-key": "code:local_new" }, text: "Рик 2" });
  });
  parts.editor.addEventListener("paste", event => {
    if (box.quiet) return;
    for (const file of event.clipboardData?.files ?? []) {
      box.pasted.push(file);
      if (accept) box.pills.push(loaded.dom.pill(parts.block, { name: file.name }));
    }
  });
  const store = { calls: [] };
  const value = { popoutWindows: loaded.run("new Map()"), openPopout: options => store.calls.push(options) };
  const hook = () => {};
  hook.getState = () => value;
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  loaded.inner.setModuleImporter(() => Promise.resolve({ Store: hook }));
  // Элвис вставил скриншоты сам: полка их запомнила, Claude нарисовал плитки.
  box.attach = names => {
    const files = names.map(name => loaded.dom.file(name));
    box.quiet = true;
    loaded.dom.document.dispatchEvent({ type: "paste", clipboardData: { files } });
    box.quiet = false;
    for (const name of names) box.pills.push(loaded.dom.pill(parts.block, { name }));
    return files;
  };
  box.newChatKey = () => {
    loaded.win.location.pathname = "/epitaxy";
    parts.editor.textContent = "";
    for (const pill of box.pills.splice(0)) pill.remove();
  };
  return { loaded, parts, box, store };
};
const renew = (extra = {}) => ({
  id: "r1", action: "new-window", at: "now", scope: "window", title: "Claude",
  x: 100, y: 200, text: RENEW, folder: "", name: "", stay: true, ...extra,
});
// Прогон цепочки: микрозадачи и самый свежий таймер, часы — по 100 мс на круг.
// `onRound(index)` — что делает «Swift» и Элвис между кругами.
const run = async (loaded, onRound = () => {}, rounds = 120) => {
  let clock = loaded.win.performance.now();
  loaded.win.performance.now = () => clock;
  for (let index = 0; index < rounds; index += 1) {
    onRound(index);
    clock += 100;
    await settle(4);
    const ids = loaded.dom.ids("timeout");
    if (ids.length) loaded.dom.fire(ids[ids.length - 1]);
  }
  await settle();
};

test("текст черновика: первым уходит renew, набранное — в поле нового чата, без отправки", async () => {
  const { loaded, parts, box } = rick();
  loaded.dom.command(renew());
  await run(loaded, index => { if (index === 3) box.newChatKey(); });
  const mark = plain(loaded.api.status().newWindow);
  assert.deepEqual(box.sent, [RENEW], "черновик не приклеился к первому сообщению и не отправлен");
  assert.equal(mark.state, "ok");
  assert.equal(loaded.win.location.pathname, "/epitaxy/local_new");
  assert.equal(parts.editor.textContent, DRAFT, "набранное — в поле нового чата");
  assert.deepEqual(mark.carry, { state: "ok", chars: DRAFT.length, files: 0, want: 0, landed: 0 });
  assert.equal(plain(loaded.api.status().draftCarry).runs, 1);
});

test("1 и 3 картинки едут вложениями нового чата — те же File, плитки на месте", async () => {
  for (const names of [["Скриншот 1.png"], ["Скриншот 1.png", "Скриншот 2.png", "Скриншот 3.png"]]) {
    const { loaded, parts, box } = rick();
    const files = box.attach(names);
    loaded.dom.command(renew());
    await run(loaded, index => { if (index === 3) box.newChatKey(); });
    const mark = plain(loaded.api.status().newWindow);
    assert.deepEqual(box.sent, [RENEW]);
    assert.equal(parts.editor.textContent, DRAFT);
    assert.equal(box.pasted.length, names.length, "вставили ровно столько, сколько было в поле");
    assert.ok(files.every(file => box.pasted.includes(file)), "те же File, а не копии");
    assert.equal(box.pills.length, names.length, "плитки в поле нового чата");
    assert.deepEqual(mark.carry, { state: "ok", chars: DRAFT.length, files: names.length, want: names.length, landed: names.length });
  }
});

test("только картинки, без текста — едут одни вложения", async () => {
  const { loaded, parts, box } = rick({ draft: "" });
  box.attach(["Скриншот 4.png"]);
  loaded.dom.command(renew());
  await run(loaded, index => { if (index === 3) box.newChatKey(); });
  assert.equal(parts.editor.textContent, "");
  assert.equal(plain(loaded.api.status().newWindow).carry.state, "ok");
  assert.equal(box.pills.length, 1);
});

test("пустой черновик — ни одного лишнего шага: поля carry нет, ничего не вставляем", async () => {
  const { loaded, parts, box } = rick({ draft: "" });
  loaded.dom.command(renew());
  await run(loaded, index => { if (index === 3) box.newChatKey(); });
  const mark = plain(loaded.api.status().newWindow);
  assert.equal(mark.state, "ok");
  assert.equal(mark.carry, null);
  assert.equal(parts.editor.textContent, "");
  assert.equal(box.pasted.length, 0);
  assert.equal(loaded.api.status().draftCarry, null);
});

test("дописанное до ⌘N тоже едет: досмотр, пока окно на прежнем чате", async () => {
  const { loaded, parts, box } = rick({ draft: "" });
  loaded.dom.command(renew());
  await run(loaded, index => {
    if (index === 1) parts.editor.textContent = DRAFT;
    if (index === 3) box.newChatKey();
  });
  assert.equal(parts.editor.textContent, DRAFT);
  assert.equal(plain(loaded.api.status().newWindow).carry.state, "ok");
});

test("Claude взял не все файлы — исход part, называем сколько доехало", async () => {
  const { loaded, box } = rick({ accept: false });
  box.attach(["Скриншот 1.png", "Скриншот 2.png"]);
  loaded.dom.command(renew());
  await run(loaded, index => { if (index === 3) box.newChatKey(); });
  const carry = plain(loaded.api.status().newWindow).carry;
  assert.equal(carry.state, "part");
  assert.equal(carry.want, 2);
  assert.equal(carry.landed, 0);
});

test("вынос чата отдельным окном (не stay) — черновик не трогаем", async () => {
  const { loaded, box } = rick();
  loaded.dom.command(renew({ stay: false }));
  await run(loaded, index => { if (index === 3) box.newChatKey(); });
  assert.equal(plain(loaded.api.status().newWindow).carry, null);
  assert.equal(loaded.api.status().draftCarry, null);
});

test("цепочка сорвалась (⌘N не случился) — черновик остаётся в прежнем чате, исход kept", async () => {
  const { loaded, parts, box } = rick();
  box.attach(["Скриншот 1.png"]);
  loaded.dom.command(renew());
  await run(loaded, () => {}, 200);
  const mark = plain(loaded.api.status().newWindow);
  assert.equal(mark.state, "no-home");
  assert.equal(mark.carry.state, "kept");
  assert.deepEqual(box.sent, []);
  assert.equal(parts.editor.textContent, DRAFT, "поле прежнего чата не тронуто");
  assert.equal(box.pasted.length, 0, "второй раз не вкладываем — плитка и так на месте");
});

test("сорвалось после ⌘N, прежний чат вернулся с пустым полем — кладём черновик обратно", async () => {
  const { loaded, parts, box } = rick();
  box.attach(["Скриншот 1.png"]);
  // Поле домашнего экрана занято (черновик «нового чата» Claude) — шаг draft, возврат на прежний чат.
  loaded.dom.command(renew());
  await run(loaded, index => {
    if (index === 3) { box.newChatKey(); parts.editor.textContent = "чужое"; }
    if (index === 6 && loaded.win.location.pathname === "/epitaxy") {
      loaded.win.location.pathname = "/epitaxy/local_old";
      parts.editor.textContent = "";
    }
  }, 160);
  const mark = plain(loaded.api.status().newWindow);
  assert.equal(mark.state, "draft");
  assert.equal(mark.carry.state, "back", JSON.stringify(mark.carry));
  assert.equal(parts.editor.textContent, DRAFT);
  assert.equal(box.pasted.length, 1);
});

// #11571: вставка голоса запасным путём («Голос Элвиса: … #v<id> · …») уже в почте Рика — с черновиком не едет.
test("вставка голоса в черновике не едет в новый чат; набранное рядом — едет", async () => {
  const VOICE = "Голос Элвиса: 🎙 Голосом с телефона #v1793559474634-d9d0e9 · посмотри картинку";
  for (const [draft, landed] of [[`${VOICE}\n${DRAFT}`, DRAFT], [VOICE, ""]]) {
    const { loaded, parts, box } = rick({ draft });
    loaded.dom.command(renew());
    await run(loaded, index => { if (index === 3) box.newChatKey(); });
    assert.deepEqual(box.sent, [RENEW], "вставка голоса не ушла отправкой");
    assert.equal(parts.editor.textContent, landed, "в поле нового чата — только набранное Элвисом");
    assert.equal(plain(loaded.api.status().newWindow).carry?.chars ?? 0, landed.length);
  }
});
