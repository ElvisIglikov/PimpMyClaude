// #11245: в поле не кладём второй раз то, что там уже лежит. Слово Элвиса 30.10 ~20:15: «А зачем ты вот ещё
// раз добавил картинки? Они же уже здесь добавлены, вот сам посмотри» — в поле 1 = 3, 2 = 4.
// Причина: Диктатор на «Стоп» вставил два снимка ⌘V и оставил их в буфере вместо текста; плашка «Текст не
// вставлен · ⌘V» — и тот же буфер лёг второй раз, уже «Скриншотами 3 и 4». Класс: вставка с номером, перенос
// черновика при renew, ⌘Z вложения, «Обкэшить», пересылка ⌘V мимо поля — всё сверяется с плитками поля.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const NOTE = "myclaude-new-window-note";
const DUP = "Эти файлы уже в поле — второй раз не кладу";

const tile = (box, name) => {
  const node = box.add("div", { attrs: { "data-cds-attachment": "", "data-cds": "MessageAttachmentsImage" } });
  node.add("img", { attrs: { src: `blob:claude/${name}` } });
  node.add("button", { attrs: { "aria-label": `Remove ${name}` } });
  return node;
};
const tick = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
// Поле чата с коробкой вложений; Claude кладёт плиткой всё, что пришло в поле вставкой.
const page = () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_a",
    title: "PimpMyClaude",
    html: dom => {
      const parts = dom.composer();
      parts.box = parts.shell.add("div", { attrs: { "data-cds-composer-attachments": "" } });
      parts.line = parts.editor.add("p", { text: "" });
      parts.outside = dom.document.body.add("div", { text: "лента" });
      return parts;
    },
  });
  assert.equal(loaded.error, null);
  tick(loaded);
  loaded.got = [];
  loaded.parts.editor.addEventListener("paste", event => {
    const files = [...(event.clipboardData?.files ?? [])];
    loaded.got.push(files.map(file => file.name));
    for (const file of files) tile(loaded.parts.box, file.name);
  });
  return loaded;
};
const paste = (loaded, files, target = loaded.parts.line) => loaded.document.dispatchEvent({
  type: "paste", target, isTrusted: true, cancelable: true,
  clipboardData: { files, getData: () => "" },
});
// Тот же буфер, вставленный второй раз: новые File с теми же именем, весом и байтами.
const shots = loaded => [
  loaded.dom.image("Снимок 2026-10-30 в 20.07.13-392211.png", { width: 2800, height: 1380 }),
  loaded.dom.image("Снимок 2026-10-30 в 20.10.53-156063.png", { width: 5120, height: 1440 }),
];
const note = loaded => {
  const node = loaded.document.getElementById(NOTE);
  return node && node.style.getPropertyValue("display") !== "none" ? node.textContent : null;
};
const tiles = loaded => [...loaded.parts.box.querySelectorAll("button")].map(node => node.getAttribute("aria-label").slice(7));

test("тот же буфер со снимками второй раз — в поле не ложится, номера 3 и 4 не выдаются", async () => {
  const loaded = page();
  paste(loaded, shots(loaded));
  await loaded.inner.shotState.chain;
  assert.deepEqual(tiles(loaded), ["Скриншот 1.png", "Скриншот 2.png"]);

  paste(loaded, shots(loaded));
  await loaded.inner.shotState.chain;
  assert.deepEqual(tiles(loaded), ["Скриншот 1.png", "Скриншот 2.png"], "1 = 3, 2 = 4 — ровно жалоба Элвиса");
  assert.equal(loaded.got.length, 1, "второй вставки в поле нет вовсе");
  assert.equal(note(loaded), DUP);
  const dup = plain(loaded.api.status().attachDup);
  assert.equal(dup.skipped, 2);
  assert.equal(dup.last.where, "shot");

  // Новый снимок после повтора — следующим номером, без дыры.
  paste(loaded, [loaded.dom.image("Снимок 2026-10-30 в 20.16.07-716477.png")]);
  await loaded.inner.shotState.chain;
  assert.deepEqual(tiles(loaded).at(-1), "Скриншот 3.png");
  loaded.api.dispose();
});

test("в одной вставке старый снимок и новый — едет только новый", async () => {
  const loaded = page();
  const [first, second] = shots(loaded);
  paste(loaded, [first]);
  await loaded.inner.shotState.chain;
  paste(loaded, [shots(loaded)[0], second]);
  await loaded.inner.shotState.chain;
  assert.deepEqual(tiles(loaded), ["Скриншот 1.png", "Скриншот 2.png"]);
  assert.deepEqual(loaded.got, [["Скриншот 1.png"], ["Скриншот 2.png"]]);
  loaded.api.dispose();
});

test("снял плитку крестиком — тот же снимок можно вставить снова", async () => {
  const loaded = page();
  paste(loaded, shots(loaded).slice(0, 1));
  await loaded.inner.shotState.chain;
  loaded.parts.box.children[0].remove();
  paste(loaded, shots(loaded).slice(0, 1));
  await loaded.inner.shotState.chain;
  assert.deepEqual(tiles(loaded), ["Скриншот 2.png"], "в поле его уже нет — вставка законная");
  assert.equal(plain(loaded.api.status().attachDup).skipped, 0);
  loaded.api.dispose();
});

test("⌘V файла мимо поля (пересылка): файл, который уже в поле, не пересылается", () => {
  const loaded = page();
  const pdf = loaded.dom.file("отчёт.pdf", { type: "application/pdf" });
  paste(loaded, [pdf], loaded.parts.outside);
  assert.deepEqual(loaded.got, [["отчёт.pdf"]]);
  paste(loaded, [loaded.dom.file("отчёт.pdf", { type: "application/pdf" })], loaded.parts.outside);
  assert.deepEqual(loaded.got, [["отчёт.pdf"]]);
  assert.equal(plain(loaded.api.status().attachDup).last.where, "relay");
  loaded.api.dispose();
});

// renew главного окна (#11201): Claude оставил вложения в поле нового чата — перенос их не повторяет.
const drain = () => new Promise(resolve => setImmediate(resolve));
const settle = async (times = 6) => { for (let index = 0; index < times; index += 1) await drain(); };
const RENEW = "Ты — Рик. Продолжай.";
const rick = () => {
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_old", title: "Claude",
    html: dom => {
      const parts = dom.composer({ text: "" });
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
      box.pills.push(loaded.dom.pill(parts.block, { name: file.name }));
    }
  });
  const value = { popoutWindows: loaded.run("new Map()"), openPopout: () => {} };
  const hook = () => {};
  hook.getState = () => value;
  loaded.dom.modules("https://claude.ai/assets/v1/chunk-1.js");
  loaded.inner.setModuleImporter(() => Promise.resolve({ Store: hook }));
  box.attach = names => {
    const files = names.map(name => loaded.dom.file(name));
    box.quiet = true;
    loaded.dom.document.dispatchEvent({ type: "paste", clipboardData: { files } });
    box.quiet = false;
    for (const name of names) box.pills.push(loaded.dom.pill(parts.block, { name }));
  };
  return { loaded, box };
};
const run = async (loaded, onRound, rounds = 120) => {
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

test("renew: Claude оставил вложения в поле нового чата — перенос их не кладёт второй раз", async () => {
  const { loaded, box } = rick();
  box.attach(["Скриншот 1.png", "Скриншот 2.png"]);
  loaded.dom.command({
    id: "r1", action: "new-window", at: "now", scope: "window", title: "Claude",
    x: 100, y: 200, text: RENEW, folder: "", name: "", stay: true,
  });
  // ⌘N: новый чат, а плитки прежнего поля Claude оставил на месте.
  await run(loaded, index => { if (index === 3) loaded.win.location.pathname = "/epitaxy"; });
  const carry = plain(loaded.api.status().newWindow).carry;
  assert.deepEqual(box.sent, [RENEW]);
  assert.equal(box.pasted.length, 0, "ничего не вставлено второй раз");
  assert.equal(box.pills.length, 2);
  assert.deepEqual(carry, { state: "ok", chars: 0, files: 2, want: 2, landed: 2 });
  assert.equal(plain(loaded.api.status().attachDup).last.where, "carry");
});
