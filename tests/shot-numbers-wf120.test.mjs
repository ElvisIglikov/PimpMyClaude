// Номера скриншотов в поле ввода (раздел 12 inject.js, задача #7532, WF120).
// Элвис: у скриншотов в поле — номера, чтобы писать «на втором видно…», и номер
// должен доходить до модели.
//
// Проверяется контракт:
//   1) живая вставка картинки (⌘V в поле или мимо поля, бросок на блок ввода)
//      забирается на захвате; в поле уезжает «Скриншот N.<ext>» с номером,
//      нарисованным в левом нижнем углу самой картинки; исходную Claude не видит;
//   2) номер на плитке поля — атрибутом data-myclaude-shot из имени плитки
//      («Remove Скриншот N.png»); снятая плитка соседей не перенумеровывает;
//   3) счёт с 1 в каждом сообщении, только растёт; сброс — отправка и смена
//      адреса; следующий номер больше любого на плитках поля;
//   4) не картинка, gif, текст рядом с картинкой, чужое поле, своя синтетика —
//      не трогаем; не разобралась или холст отказал — оригинал и плашка; чат
//      сменился, пока рисовали, — в чужое поле не кладём, плашка;
//   5) долгий разбор — плашка ожидания, срок — оригинал; dispose снимает
//      подписку и атрибуты, вставку в полёте доводит.
//
// Стенд: события шлём прямо на документ с нужной целью (стаб не всплывает);
// Claude изображает слушатель paste на поле: на каждый файл — плитка в коробке
// вложений с кнопкой «Remove <имя>», как у настоящего композера.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const ATTR = "data-myclaude-shot";
const NOTE = "myclaude-new-window-note";
const LOST = "Скриншот не вставлен: поле ввода пропало или чат сменился — вставь ещё раз";
const PLAIN = "Номер не поставлен — картинка вставлена как есть";
const BUSY = "Ставлю номер на скриншот…";
const CHAT_A = "https://claude.ai/epitaxy/local_a";
const CHAT_B = "https://claude.ai/epitaxy/local_b";

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

const page = ({ href = CHAT_A } = {}) => {
  const loaded = loadInject({
    href,
    title: "PimpMyClaude",
    html: dom => {
      const parts = dom.composer();
      parts.box = parts.shell.add("div", { attrs: { "data-cds-composer-attachments": "" } });
      parts.transcript = dom.document.body.add("div", {
        attrs: { "data-testid": "assistant-message" },
        rect: { left: 100, top: 200, width: 1000, height: 300 },
        text: "Последний ответ Claude.",
      });
      parts.search = dom.document.body.add("input", { attrs: { type: "text" } });
      parts.line = parts.editor.add("p", { text: "" });
      return parts;
    },
  });
  assert.equal(loaded.error, null);
  tick(loaded);
  // Claude: что пришло в поле вставкой — то и легло плитками.
  loaded.got = [];
  loaded.parts.editor.addEventListener("paste", event => {
    const files = [...(event.clipboardData?.files ?? [])];
    loaded.got.push(files);
    for (const file of files) tile(loaded.parts.box, file.name);
  });
  // Родная вставка Claude ниже нашего захвата: видна, только если мы её пропустили.
  loaded.native = [];
  loaded.document.addEventListener("paste", event => loaded.native.push(event));
  loaded.document.addEventListener("drop", event => loaded.native.push(event));
  return loaded;
};

const clip = (files, text = "") => ({ files, getData: type => (type === "text/plain" ? text : "") });
const paste = (loaded, { target = loaded.parts.line, files, text = "", trusted = true }) =>
  loaded.document.dispatchEvent({ type: "paste", target, isTrusted: trusted, cancelable: true, clipboardData: clip(files, text) });
const drop = (loaded, { target, files, text = "", trusted = true }) =>
  loaded.document.dispatchEvent({
    type: "drop", target, isTrusted: trusted, cancelable: true,
    dataTransfer: { ...clip(files, text), types: ["Files"] },
  });
const settle = loaded => loaded.inner.shotState.chain;
const names = loaded => loaded.got.map(files => files.map(file => file.name));
const drawn = file => JSON.parse(String.fromCharCode(...file.__bytes));
const marks = loaded => [...loaded.parts.box.querySelectorAll("[data-cds-attachment]")].map(node => node.getAttribute(ATTR));
const note = loaded => {
  const node = loaded.document.getElementById(NOTE);
  return node && node.style.getPropertyValue("display") !== "none" ? node.textContent : null;
};

test("⌘V скриншота в поле: Claude получает «Скриншот 1.png» с номером в левом нижнем углу", async () => {
  const loaded = page();
  const passed = paste(loaded, { files: [loaded.dom.image("image.png", { width: 1600, height: 1000 })] });
  assert.equal(passed, false, "исходную вставку обязаны забрать: иначе в поле две картинки");
  assert.equal(loaded.native.length, 0, "родная вставка Claude не должна увидеть оригинал");
  await settle(loaded);

  assert.deepEqual(names(loaded), [["Скриншот 1.png"]]);
  const [file] = loaded.got[0];
  assert.equal(file.type, "image/png");
  const picture = drawn(file);
  assert.equal(picture.width, 1600, "холст — в размер снимка, без ужатия");
  assert.equal(picture.height, 1000);
  assert.deepEqual(picture.ops[0], { op: "drawImage", args: ["bitmap 1600x1000", 0, 0], font: "10px sans-serif", fillStyle: "#000000" },
    "сперва сам снимок, потом номер поверх");
  const text = picture.ops.find(item => item.op === "fillText");
  assert.equal(text.args[0], "1");
  assert.ok(text.args[1] < 1600 / 4 && text.args[2] > 1000 * 3 / 4, `номер не в левом нижнем углу: ${text.args}`);
  assert.equal(text.fillStyle, "#ffffff");
  assert.match(text.font, /^700 50px /, "кегль — доля короткой стороны");
  const box = picture.ops.find(item => item.op === "roundRect").args;
  assert.ok(box[0] > 0 && box[1] + box[3] < 1000, "плашка номера целиком внутри снимка");
  assert.ok(loaded.dom.bitmaps.every(bitmap => bitmap.closed), "разобранная картинка не закрыта");
  assert.equal(loaded.document.activeElement, loaded.parts.editor);
  assert.equal(note(loaded), null, "без плашек: всё получилось");
});

test("три скриншота подряд — 1, 2, 3 по порядку ⌘V; номер на плитке; снятая не перенумеровывает", async () => {
  const loaded = page();
  // Первая картинка разбирается дольше второй — номера всё равно по порядку ⌘V.
  const decode = loaded.win.createImageBitmap;
  let release = null;
  const calls = [];
  loaded.win.createImageBitmap = source => {
    calls.push(source.name);
    if (calls.length > 1) return decode(source);
    return new Promise(resolve => { release = () => resolve(decode(source)); });
  };
  for (const name of ["a.png", "b.png", "c.png"]) paste(loaded, { files: [loaded.dom.image(name)] });
  await Promise.resolve();
  await Promise.resolve();
  assert.deepEqual(calls, ["a.png"], "вторая вставка ждёт первую в очереди");
  release();
  await settle(loaded);
  assert.deepEqual(names(loaded), [["Скриншот 1.png"], ["Скриншот 2.png"], ["Скриншот 3.png"]]);

  tick(loaded);
  assert.deepEqual(marks(loaded), ["1", "2", "3"], "номер плитки — из её имени");
  // Имена плиток (по ним считает отсчёт 12у) остаются подписями Claude.
  assert.deepEqual([...loaded.parts.box.querySelectorAll("button")].map(node => node.getAttribute("aria-label")),
    ["Remove Скриншот 1.png", "Remove Скриншот 2.png", "Remove Скриншот 3.png"]);

  loaded.parts.box.children[0].remove();
  tick(loaded);
  assert.deepEqual(marks(loaded), ["2", "3"], "снятая плитка перенумеровала соседей");

  paste(loaded, { files: [loaded.dom.image("d.png")] });
  await settle(loaded);
  assert.equal(names(loaded)[3][0], "Скриншот 4.png", "счёт только растёт");
});

test("несколько картинок одной вставкой и pdf рядом: номера по порядку, pdf как есть", async () => {
  const loaded = page();
  const pdf = loaded.dom.file("отчёт.pdf", { type: "application/pdf" });
  paste(loaded, { files: [loaded.dom.image("x.jpg", { type: "image/jpeg" }), pdf, loaded.dom.image("y.webp", { type: "image/webp" })] });
  await settle(loaded);
  assert.equal(loaded.got.length, 1, "одна вставка — один paste в поле");
  assert.deepEqual(names(loaded)[0], ["Скриншот 1.jpg", "отчёт.pdf", "Скриншот 2.webp"]);
  assert.equal(loaded.got[0][1], pdf, "pdf — тот же файл, без перекладки");
  assert.equal(loaded.got[0][0].type, "image/jpeg", "jpeg остаётся jpeg — не раздуваем в png");
  assert.equal(drawn(loaded.got[0][0]).quality, 0.92);
  tick(loaded);
  assert.deepEqual(marks(loaded), ["1", null, "2"], "у pdf номера на плитке нет");
});

test("новая подтверждённая реплика сбрасывает счёт: следующее сообщение с 1", async () => {
  const loaded = page();
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  paste(loaded, { files: [loaded.dom.image("b.png")] });
  await settle(loaded);
  tick(loaded);
  // Отправка, как её видит раздел 5в: Enter в поле. Плитки уходят вместе с сообщением.
  loaded.document.dispatchEvent({ type: "keydown", key: "Enter", target: loaded.parts.line });
  for (const node of [...loaded.parts.box.children]) node.remove();
  loaded.document.body.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "human", "data-rs-index": "new-message" } });
  paste(loaded, { files: [loaded.dom.image("c.png")] });
  await settle(loaded);
  assert.equal(names(loaded)[2][0], "Скриншот 1.png");
});

test("смена чата: счёт заново, но больше любого номера на плитках черновика", async () => {
  const loaded = page();
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  paste(loaded, { files: [loaded.dom.image("b.png")] });
  await settle(loaded);
  tick(loaded);

  // Чат Б: в поле свой черновик без скриншотов.
  loaded.win.location.href = CHAT_B;
  loaded.win.location.pathname = "/epitaxy/local_b";
  for (const node of loaded.parts.box.children) node.remove();
  paste(loaded, { files: [loaded.dom.image("c.png")] });
  await settle(loaded);
  assert.equal(names(loaded)[2][0], "Скриншот 1.png", "в другом чате счёт с 1");

  // Назад в чат А: в его черновике остались «Скриншот 1» и «Скриншот 2».
  loaded.win.location.href = CHAT_A;
  loaded.win.location.pathname = "/epitaxy/local_a";
  for (const node of loaded.parts.box.children) node.remove();
  tile(loaded.parts.box, "Скриншот 1.png");
  tile(loaded.parts.box, "Скриншот 2.png");
  tick(loaded);
  paste(loaded, { files: [loaded.dom.image("d.png")] });
  await settle(loaded);
  assert.equal(names(loaded)[3][0], "Скриншот 3.png", "второй «Скриншот 1» Claude склеил бы с первым");
});

test("чат сменился, пока рисовали: в чужое поле не кладём, плашка говорит", async () => {
  const loaded = page();
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  loaded.win.location.href = CHAT_B;
  await settle(loaded);
  assert.deepEqual(loaded.got, [], "скриншот уехал в поле чужого чата");
  assert.equal(note(loaded), LOST);
});

test("поле пропало, пока рисовали: плашка, и ничего не падает", async () => {
  const loaded = page();
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  loaded.parts.block.remove();
  await settle(loaded);
  assert.deepEqual(loaded.got, []);
  assert.equal(note(loaded), LOST);
});

test("картинка не разобралась — в поле оригинал, без номера, и плашка", async () => {
  const loaded = page();
  const broken = loaded.dom.file("битая.png");
  paste(loaded, { files: [broken] });
  await settle(loaded);
  assert.equal(loaded.got[0][0], broken, "в поле — тот же файл, что в буфере");
  assert.equal(note(loaded), PLAIN);
  tick(loaded);
  assert.deepEqual(marks(loaded), [null], "без номера в картинке — без номера на плитке");
  // Номер не потрачен: следующий скриншот — первый.
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  await settle(loaded);
  assert.equal(names(loaded)[1][0], "Скриншот 1.png");
});

test("холст отказал (контекст или сборка файла) — оригинал, номер не потрачен", async () => {
  for (const fail of ["context", "toBlob"]) {
    const loaded = page();
    loaded.win.__canvasFail = fail;
    const original = loaded.dom.image("a.png");
    paste(loaded, { files: [original] });
    await settle(loaded);
    assert.equal(loaded.got[0][0], original, `${fail}: в поле не оригинал`);
    assert.equal(note(loaded), PLAIN, `${fail}: без плашки`);
    assert.ok(loaded.dom.bitmaps.every(bitmap => bitmap.closed), `${fail}: картинка не закрыта`);
    loaded.win.__canvasFail = null;
    paste(loaded, { files: [loaded.dom.image("b.png")] });
    await settle(loaded);
    assert.equal(names(loaded)[1][0], "Скриншот 1.png", `${fail}: в счёте дыра`);
  }
});

test("значок меньше 64 точек — как есть и молча; огромная — как есть, с плашкой", async () => {
  const loaded = page();
  const icon = loaded.dom.image("icon.png", { width: 32, height: 32 });
  paste(loaded, { files: [icon] });
  await settle(loaded);
  assert.equal(loaded.got[0][0], icon);
  assert.equal(note(loaded), null, "значок без номера — не ошибка");

  const huge = loaded.dom.image("pano.png", { width: 20000, height: 1000 });
  paste(loaded, { files: [huge] });
  await settle(loaded);
  assert.equal(loaded.got[1][0], huge);
  assert.equal(note(loaded), PLAIN);

  const small = loaded.dom.image("small.png", { width: 300, height: 64 });
  paste(loaded, { files: [small] });
  await settle(loaded);
  const text = drawn(loaded.got[2][0]).ops.find(item => item.op === "fillText");
  assert.match(text.font, /^700 16px /, "у маленькой картинки номер не мельче 16");
  assert.equal(names(loaded)[2][0], "Скриншот 1.png");
});

test("не трогаем: gif, файл без картинки, текст рядом с картинкой, поиск чатов, своя синтетика", async () => {
  const loaded = page();
  const cases = [
    { why: "gif — анимацию холст убил бы", files: [loaded.dom.image("a.gif", { type: "image/gif" })] },
    { why: "pdf без картинок", files: [loaded.dom.file("a.pdf", { type: "application/pdf" })] },
    { why: "Excel кладёт рядом с текстом картинку-превью", files: [loaded.dom.image("a.png")], text: "1\t2" },
    { why: "поиск чатов — чужое поле", files: [loaded.dom.image("a.png")], target: loaded.parts.search },
    { why: "не живая вставка (isTrusted)", files: [loaded.dom.image("a.png")], trusted: false },
  ];
  for (const item of cases) {
    loaded.native.length = 0;
    const passed = paste(loaded, item);
    assert.equal(passed, true, `${item.why}: вставку отменили`);
    assert.equal(loaded.native.length, 1, `${item.why}: родная вставка Claude не дошла`);
  }
  await settle(loaded);
  assert.deepEqual(loaded.got, [], "что-то уехало в поле нашей вставкой");
});

test("⌘V мимо поля (лента): скриншот уезжает в поле уже с номером; своя синтетика — как раньше", async () => {
  const loaded = page();
  const passed = paste(loaded, { target: loaded.parts.transcript, files: [loaded.dom.image("a.png")] });
  assert.equal(passed, false);
  await settle(loaded);
  assert.deepEqual(names(loaded), [["Скриншот 1.png"]]);
  assert.equal(loaded.document.activeElement, loaded.parts.editor);

  // Не живая вставка мимо поля — прежняя пересылка (WF64): сразу и без номера.
  const plain = loaded.dom.image("b.png");
  paste(loaded, { target: loaded.parts.transcript, files: [plain], trusted: false });
  assert.equal(loaded.got[1][0], plain);
});

test("бросок картинки на блок ввода — с номером; на ленту — не наш", async () => {
  const loaded = page();
  const passed = drop(loaded, { target: loaded.parts.modelRow, files: [loaded.dom.image("a.png")] });
  assert.equal(passed, false, "бросок на блок ввода обязаны забрать");
  assert.equal(loaded.native.length, 0, "Claude увидел бы оригинал");
  await settle(loaded);
  assert.deepEqual(names(loaded), [["Скриншот 1.png"]]);

  for (const target of [loaded.parts.transcript, loaded.parts.search]) {
    loaded.native.length = 0;
    assert.equal(drop(loaded, { target, files: [loaded.dom.image("b.png")] }), true);
    assert.equal(loaded.native.length, 1, "бросок мимо блока ввода — дело Claude");
  }
  assert.equal(drop(loaded, { target: loaded.parts.editor, files: [loaded.dom.image("c.png")], trusted: false }), true,
    "чужой синтетический бросок не трогаем");
  await settle(loaded);
  assert.equal(loaded.got.length, 1);
});

test("долгий разбор: через 300 мс плашка ожидания, по сроку 5 с — оригинал, плашка ожидания уходит", async () => {
  const loaded = page();
  loaded.win.__bitmapHang = true;
  const original = loaded.dom.image("a.png");
  paste(loaded, { files: [original] });
  await Promise.resolve();
  await Promise.resolve();
  // Свой таймер — последний с таким сроком: он поставлен этой вставкой.
  const timer = ms => [...loaded.dom.timers].filter(([, item]) => item.kind === "timeout" && item.ms === ms).pop()?.[0];
  assert.equal(note(loaded), null, "плашка не мигает у быстрой вставки");
  loaded.dom.fire(timer(300));
  assert.equal(note(loaded), BUSY);
  assert.ok(loaded.document.getElementById(NOTE).querySelector("span"), "ожидание — с переливом, как у прочих плашек");
  const limit = timer(5000);
  assert.ok(limit, "у разбора нет срока — вставка повисла бы навсегда");
  loaded.dom.fire(limit);
  loaded.win.clearTimeout(limit);
  await settle(loaded);
  assert.equal(loaded.got[0][0], original);
  assert.equal(note(loaded), PLAIN, "плашка ожидания сменилась словами");
  assert.equal(loaded.inner.shotState.busyTimer, 0);
  assert.equal(loaded.inner.shotState.pending, 0);
});

test("dispose: подписка броска, атрибуты плиток и значок уходят; поздняя вставка отменена", async () => {
  const loaded = page();
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  await settle(loaded);
  tick(loaded);
  assert.deepEqual(marks(loaded), ["1"]);
  assert.ok(loaded.dom.sheets().includes(`[${ATTR}]::after`), "значка плитки нет в таблицах стилей");

  const drops = () => (loaded.document.__listeners.get("drop") ?? []).length;
  const before = drops();
  paste(loaded, { files: [loaded.dom.image("b.png")] });
  loaded.api.dispose();
  assert.equal(drops(), before - 3, "из трёх своих подписок броска что-то осталось");
  assert.deepEqual(marks(loaded), [null], "атрибут номера пережил dispose");
  assert.ok(!loaded.dom.sheets().includes(`[${ATTR}]::after`), "значок пережил dispose");
  await settle(loaded);
  assert.equal(names(loaded).length, 1, "после dispose нельзя вставлять в найденное заново поле");
  assert.equal(loaded.document.getElementById(NOTE), null, "мёртвый экземпляр показал плашку");
  assert.equal(loaded.counters.timers, 0, "таймер ожидания пережил dispose");
});

const microtasks = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };
const sendFixture = loaded => {
  loaded.parts.editor.__text = "Текст с картинкой";
  const send = loaded.parts.modelRow.add("button", { attrs: { "data-testid": "code-prompt-send" } });
  let sends = 0;
  let sent = [];
  const accept = () => { sends++; sent = loaded.got.flat(); loaded.parts.editor.__text = ""; };
  loaded.parts.editor.addEventListener("keydown", e => { if (e.key === "Enter") accept(); });
  loaded.document.addEventListener("keydown", e => { if (e.key === "Enter") accept(); });
  loaded.document.addEventListener("click", e => { if (e.target === send) accept(); });
  send.addEventListener("pointerdown", accept);
  return { send, get sends() { return sends; }, get sent() { return sent; } };
};
const enter = loaded => loaded.document.dispatchEvent({ type: "keydown", key: "Enter", target: loaded.parts.editor, isTrusted: true });
const timeouts = loaded => { for (let i = 0; i < 12; i++) loaded.dom.fireKind("timeout"); };

for (const seconds of [0, 3, 5, 10]) for (const stage of ["decode", "toBlob"]) {
  test(`pending ${stage}, отсчёт ${seconds}: Enter/кнопка/submit/send-text ждут нового действия`, async () => {
    const loaded = page();
    loaded.dom.command({ action: "send-delay", on: seconds > 0, seconds: seconds || 5 });
    const f = sendFixture(loaded);
    let release;
    if (stage === "decode") {
      const decode = loaded.win.createImageBitmap;
      loaded.win.createImageBitmap = file => new Promise(resolve => { release = () => resolve(decode(file)); });
    } else {
      const create = loaded.document.createElement;
      loaded.document.createElement = tag => {
        const node = create(tag);
        if (tag === "canvas") { const encode = node.toBlob; node.toBlob = (...args) => { release = () => encode(...args); }; }
        return node;
      };
    }
    paste(loaded, { files: [loaded.dom.image("a.png")] });
    await microtasks();
    assert.equal(loaded.inner.shotState.pending, 1);
    assert.equal(enter(loaded), false);
    assert.equal(loaded.document.dispatchEvent({ type: "click", target: f.send, isTrusted: true }), false);
    assert.equal(loaded.document.dispatchEvent({ type: "submit", target: loaded.parts.shell }), false);
    loaded.dom.command({ id: `blocked-${seconds}-${stage}`, action: "send-text", chat: "local_a", text: "Преждевременная отправка" });
    assert.equal(loaded.api.status().send.state, "field-busy");
    assert.equal(f.sends, 0);
    assert.match(note(loaded), /Ставлю номер/);
    release();
    await settle(loaded);
    assert.equal(loaded.inner.shotState.pending, 0);
    timeouts(loaded);
    assert.equal(f.sends, 0, "готовность не отправляет и не запускает отсчёт");
    assert.equal(loaded.api.status().sendDelay.counting, false);
    enter(loaded);
    timeouts(loaded);
    assert.equal(f.sends, 1);
    assert.equal(f.sent[0].name, "Скриншот 1.png");
    assert.equal(drawn(f.sent[0]).ops.find(op => op.op === "fillText").args[0], "1");
  });
}

test("начало обработки отменяет прежний отсчёт, фразу и активную отправку send-text", async () => {
  const loaded = page();
  const f = sendFixture(loaded);
  enter(loaded);
  assert.equal(loaded.api.status().sendDelay.counting, true);
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  assert.equal(loaded.api.status().sendDelay.counting, false);
  await settle(loaded);
  timeouts(loaded);
  assert.equal(f.sends, 0);
});

test("подмена редактора при decode: ни в старое, ни в новое поле не доставлять", async () => {
  const loaded = page();
  const decode = loaded.win.createImageBitmap;
  let release;
  loaded.win.createImageBitmap = file => new Promise(resolve => { release = () => resolve(decode(file)); });
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  await microtasks();
  loaded.parts.block.remove();
  const next = loaded.dom.composer();
  let delivered = 0;
  next.editor.addEventListener("paste", () => delivered++);
  release();
  await settle(loaded);
  assert.equal(loaded.got.length, 0);
  assert.equal(delivered, 0);
  assert.ok(loaded.dom.bitmaps.every(bitmap => bitmap.closed));
});

test("timeout decode закрывает поздний bitmap, оригинал вставляется один раз", async () => {
  const loaded = page();
  const decode = loaded.win.createImageBitmap;
  let release;
  loaded.win.createImageBitmap = file => new Promise(resolve => { release = () => resolve(decode(file)); });
  const original = loaded.dom.image("a.png");
  paste(loaded, { files: [original] });
  await microtasks();
  const timer = [...loaded.dom.timers].find(([, t]) => t.kind === "timeout" && t.ms === 5000)[0];
  loaded.dom.fire(timer);
  await settle(loaded);
  assert.equal(loaded.got[0][0], original);
  release();
  await microtasks();
  assert.ok(loaded.dom.bitmaps.every(bitmap => bitmap.closed));
  assert.equal(loaded.got.length, 1);
});

test("2/3 после удаления 1 и reinject остаются 2/3; новый снимок 4; чужое имя из + без номера", async () => {
  const loaded = page();
  for (const name of ["a", "b", "c"]) paste(loaded, { files: [loaded.dom.image(`${name}.png`)] });
  await settle(loaded);
  loaded.parts.box.children[0].remove();
  assert.equal(loaded.reload().error, null);
  tick(loaded);
  assert.deepEqual(marks(loaded), ["2", "3"]);
  paste(loaded, { files: [loaded.dom.image("d.png")] });
  await settle(loaded);
  assert.equal(names(loaded).at(-1)[0], "Скриншот 4.png");
  const foreign = loaded.dom.image("Скриншот 3.png");
  const picker = loaded.parts.shell.add("input");
  picker.type = "file";
  picker.files = [foreign];
  loaded.document.dispatchEvent({ type: "change", target: picker });
  tile(loaded.parts.box, foreign.name);
  tick(loaded);
  assert.deepEqual(marks(loaded), ["2", null, "4", null]);
});

test("попытка Enter, Esc, очистка DOM и неудачная отправка не обнуляют номера", async () => {
  const loaded = page();
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  await settle(loaded);
  tick(loaded);
  enter(loaded);
  loaded.win.dispatchEvent({ type: "keydown", key: "Escape", isTrusted: true });
  for (const node of [...loaded.parts.box.children]) node.remove();
  paste(loaded, { files: [loaded.dom.image("b.png")] });
  await settle(loaded);
  assert.equal(names(loaded).at(-1)[0], "Скриншот 2.png");
});

test("reinject во время decode отменяет старый job, сохраняет готовые номера и закрывает bitmap", async () => {
  const loaded = page();
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  await settle(loaded);
  let release;
  const decode = loaded.win.createImageBitmap;
  loaded.win.createImageBitmap = file => new Promise(resolve => { release = () => resolve(decode(file)); });
  paste(loaded, { files: [loaded.dom.image("b.png")] });
  const oldChain = settle(loaded);
  await microtasks();
  assert.equal(loaded.reload().error, null);
  await oldChain;
  release();
  await microtasks();
  assert.equal(loaded.got.length, 1);
  assert.ok(loaded.dom.bitmaps.every(bitmap => bitmap.closed));
  loaded.win.createImageBitmap = decode;
  paste(loaded, { files: [loaded.dom.image("c.png")] });
  await settle(loaded);
  assert.equal(names(loaded).at(-1)[0], "Скриншот 2.png");
});

test("фразы во время pending не взводятся и не отправляются после готовности", async () => {
  const loaded = page();
  const f = sendFixture(loaded);
  const decode = loaded.win.createImageBitmap;
  let release;
  loaded.win.createImageBitmap = file => new Promise(resolve => { release = () => resolve(decode(file)); });
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  await microtasks();
  assert.equal(loaded.inner.sayToggle("отчёт", null), false);
  assert.equal(loaded.inner.nazhToggle({ key: "code:инструкция", group: "send", text: "инструкция", send: true }), false);
  release();
  await settle(loaded);
  loaded.inner.sayTick(Date.now() + 10000);
  loaded.inner.nazhTick(Date.now() + 10000);
  timeouts(loaded);
  assert.equal(f.sends, 0);
  assert.equal(loaded.parts.editor.textContent, "Текст с картинкой");
});

test("send-text, начатый до скриншота, отменён даже если картинка быстро обработалась", async () => {
  const loaded = page();
  const f = sendFixture(loaded);
  loaded.parts.editor.__text = "";
  loaded.dom.command({ id: "inflight", action: "send-text", chat: "local_a", text: "Мост голоса" });
  assert.equal(loaded.inner.sendTextState.busy, true);
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  await settle(loaded);
  timeouts(loaded);
  assert.equal(f.sends, 0);
  assert.equal(loaded.api.status().send.state, "no-send");
});

test("возврат в черновик после уборки полки сохраняет 2/3, следующий номер 4", async () => {
  const loaded = page();
  for (const name of ["a", "b", "c"]) paste(loaded, { files: [loaded.dom.image(`${name}.png`)] });
  await settle(loaded);
  loaded.parts.box.children[0].remove();
  const saved = [...loaded.parts.box.children];
  for (const node of saved) node.remove();
  loaded.win.location.href = CHAT_B;
  loaded.win.location.pathname = "/epitaxy/local_b";
  tick(loaded);
  loaded.inner.cashoutHome().shelf.splice(0);
  loaded.win.location.href = CHAT_A;
  loaded.win.location.pathname = "/epitaxy/local_a";
  for (const node of saved) loaded.parts.box.appendChild(node);
  tick(loaded);
  assert.deepEqual(marks(loaded), ["2", "3"]);
  paste(loaded, { files: [loaded.dom.image("d.png")] });
  await settle(loaded);
  assert.equal(names(loaded).at(-1)[0], "Скриншот 4.png");
});

test("toBlob timeout: оригинал, поздний ответ не добавляет вторую картинку и не шлёт", async () => {
  const loaded = page();
  const f = sendFixture(loaded);
  const create = loaded.document.createElement;
  let release;
  loaded.document.createElement = tag => {
    const node = create(tag);
    if (tag === "canvas") { const encode = node.toBlob; node.toBlob = (...args) => { release = () => encode(...args); }; }
    return node;
  };
  const original = loaded.dom.image("a.png");
  paste(loaded, { files: [original] });
  await microtasks();
  const timer = [...loaded.dom.timers].find(([, t]) => t.kind === "timeout" && t.ms === 5000)[0];
  loaded.dom.fire(timer);
  await settle(loaded);
  assert.equal(loaded.got[0][0], original);
  release();
  await microtasks();
  timeouts(loaded);
  assert.equal(loaded.got.length, 1);
  assert.equal(f.sends, 0);
  assert.equal(loaded.inner.shotState.pending, 0);
});

test("Esc во время обработки запрещает позднюю доставку и не меняет готовые номера", async () => {
  const loaded = page();
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  await settle(loaded);
  let release;
  const decode = loaded.win.createImageBitmap;
  loaded.win.createImageBitmap = file => new Promise(resolve => { release = () => resolve(decode(file)); });
  paste(loaded, { files: [loaded.dom.image("b.png")] });
  await microtasks();
  loaded.win.dispatchEvent({ type: "keydown", key: "Escape", isTrusted: true });
  await settle(loaded);
  release();
  await microtasks();
  assert.equal(loaded.got.length, 1);
  loaded.win.createImageBitmap = decode;
  paste(loaded, { files: [loaded.dom.image("c.png")] });
  await settle(loaded);
  assert.equal(names(loaded).at(-1)[0], "Скриншот 2.png");
});

test("полная замена DOM того же редактора отменяет pending, но не обнуляет готовые номера", async () => {
  const loaded = page();
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  await settle(loaded);
  let release;
  const decode = loaded.win.createImageBitmap;
  loaded.win.createImageBitmap = file => new Promise(resolve => { release = () => resolve(decode(file)); });
  paste(loaded, { files: [loaded.dom.image("b.png")] });
  await microtasks();
  const old = loaded.parts.line;
  old.remove();
  loaded.parts.line = loaded.parts.editor.add("p", { text: "Следующий черновик" });
  loaded.inner.onMutated([{ type: "childList", target: loaded.parts.editor, removedNodes: [old], addedNodes: [loaded.parts.line] }]);
  await settle(loaded);
  release();
  await microtasks();
  assert.equal(loaded.got.length, 1);
  loaded.win.createImageBitmap = decode;
  paste(loaded, { files: [loaded.dom.image("c.png")] });
  await settle(loaded);
  assert.equal(names(loaded).at(-1)[0], "Скриншот 2.png");
});

test("Обкэшить увозит обработанный File с тем же номером, снятие/возврат плитки не меняет его", async () => {
  const loaded = page();
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  await settle(loaded);
  const haul = loaded.inner.cashoutHaul();
  assert.equal(haul.files.length, 1);
  assert.equal(haul.files[0].file, loaded.got[0][0]);
  assert.equal(drawn(haul.files[0].file).ops.find(op => op.op === "fillText").args[0], "1");
  const card = loaded.parts.box.children[0];
  card.remove();
  tick(loaded);
  loaded.parts.box.appendChild(card);
  tick(loaded);
  assert.deepEqual(marks(loaded), ["1"]);
});

test("подтверждённая отправка с заменой редактора начинает новый черновик с 1", async () => {
  const loaded = page();
  paste(loaded, { files: [loaded.dom.image("a.png")] });
  await settle(loaded);
  loaded.document.dispatchEvent({ type: "keydown", key: "Enter", target: loaded.parts.line });
  loaded.parts.block.remove();
  const next = loaded.dom.composer();
  next.box = next.shell.add("div", { attrs: { "data-cds-composer-attachments": "" } });
  next.line = next.editor.add("p", { text: "" });
  loaded.parts = next;
  next.editor.addEventListener("paste", event => {
    const files = [...event.clipboardData.files];
    loaded.got.push(files);
    for (const file of files) tile(next.box, file.name);
  });
  loaded.document.body.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "human", "data-message-id": "sent" } });
  tick(loaded);
  paste(loaded, { files: [loaded.dom.image("b.png")] });
  await settle(loaded);
  assert.equal(names(loaded).at(-1)[0], "Скриншот 1.png");
});
