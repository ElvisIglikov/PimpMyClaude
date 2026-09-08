// Вложения переноса «Обкэшить» (WF50, задачи #5773, #5782, #5783). Слово
// Элвиса: «если какие-то скриншоты прикреплены к окну, они тоже должны доезжать
// при обкэшинге». До WF50 уезжал один текст, и вложения терялись МОЛЧА.
//
// Что здесь проверяется и почему именно так (уроки донора ElvisOS):
//   — File из разметки не достать, поэтому файлы ловятся НА ВХОДЕ в поле;
//   — полка лежит отдельным глобалом окна и переживает перезапись inject.js;
//   — считаем ШТУКАМИ, а не именами: восемь скриншотов macOS зовутся image.png;
//   — одинаковые имена Claude склеивает в одно вложение — разводим суффиксом;
//   — вложения кладутся ПОСЛЕ текста и только недостающие;
//   — что не доехало, названо числом и плашкой, а не молчанием.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CASHOUT_KEY = "myclaude-cashout";
const MAIN = "https://claude.ai/epitaxy/local_aaa";
const POPOUT = "about:blank";
const ANSWER = "Последний ответ Claude.";
const DRAFT = "Черновик Элвиса";
const TEXT = `${ANSWER}\n\n${DRAFT}`;

const page = ({ href = MAIN, title = "PimpMyClaude", draft = DRAFT, answer = ANSWER, storage, opener } = {}) =>
  loadInject({
    href,
    title,
    hasFocus: false,
    storage,
    opener,
    html: dom => {
      const parts = dom.composer({ text: draft });
      if (answer) dom.document.body.add("div", { attrs: { "data-testid": "assistant-message" }, text: answer });
      return parts;
    },
  });

const cashout = (extra = {}) => ({ id: "c1", action: "cashout", at: "now", scope: "window", ...extra });
const stored = loaded => {
  const raw = loaded.win.localStorage.getItem(CASHOUT_KEY);
  return raw == null ? null : JSON.parse(raw);
};
const step = loaded => loaded.dom.fireKind("timeout");
const drain = () => new Promise(resolve => setImmediate(resolve));
// Файлы кладёт сам Элвис: вставкой, перетаскиванием или кнопкой «Add».
const paste = (loaded, files) => loaded.dom.document.dispatchEvent({ type: "paste", clipboardData: { files } });
const drop = (loaded, files) => loaded.dom.document.dispatchEvent({ type: "drop", dataTransfer: { files } });
const pick = (loaded, files) => {
  const input = loaded.dom.node("input");
  input.type = "file";
  input.files = files;
  loaded.dom.document.dispatchEvent({ type: "change", target: input });
};
// Столько плашек видно в поле ввода — по ним «Обкэшить» и считает вложения.
const pills = (loaded, count, name = "image.png") => {
  for (let at = 0; at < count; at += 1) loaded.dom.pill(loaded.parts.block, { name });
};
const shelf = loaded => loaded.win.__myclaudeFiles.shelf;
// Часы страницы вперёд: у окна свой Date, и отсрочка уборки (10 с на свежую
// запись) проверяется переводом ЕГО часов, а не паузой в тесте.
const jump = (loaded, ms) => loaded.run(`(() => { const real = Date.now; Date.now = () => real.call(Date) + ${ms}; })()`);
// Новое окно, куда едет перенос: тот же родитель, что и у донора.
const fresh = (main, record) => page({
  href: POPOUT, title: "VkusnoffKz 3", draft: "", answer: "", opener: main.win,
  storage: { local: { [CASHOUT_KEY]: JSON.stringify(record) } },
});
// Claude рисует карточку на каждый принятый файл — этим стенд и отличает
// доехавшее от прикреплённого «в пустоту».
const acceptFiles = loaded => {
  loaded.parts.editor.addEventListener("paste", event => {
    for (const file of event.clipboardData?.files ?? []) loaded.dom.pill(loaded.parts.block, { name: file.name });
  });
};

test("файлы ловятся на входе: вставка, перетаскивание, кнопка «Add»", () => {
  const main = page();
  paste(main, [main.dom.file("снимок.png")]);
  drop(main, [main.dom.file("схема.pdf", { type: "application/pdf" })]);
  pick(main, [main.dom.file("список.txt", { type: "text/plain" })]);
  assert.deepEqual(plain(shelf(main).map(item => item.name)), ["снимок.png", "схема.pdf", "список.txt"],
    "из разметки File не достать — только на входе в поле");
});

test("полка переживает перезапись inject.js", () => {
  const main = page();
  paste(main, [main.dom.file("снимок.png")]);
  const again = main.reload();
  assert.equal(again.error, null);
  assert.deepEqual(plain(shelf(main).map(item => item.name)), ["снимок.png"],
    "лоадер перечитывает файл по mtime — полка в замыкании умирала бы каждый раз");
});

test("потолки полки: 24 штуки и 48 МБ, старое вытесняется", () => {
  const main = page();
  for (let at = 0; at < 30; at += 1) paste(main, [main.dom.file(`файл-${at}.png`)]);
  assert.equal(shelf(main).length, 24, "штук не больше 24");
  assert.equal(shelf(main)[0].name, "файл-6.png", "вытесняется самое старое");

  const heavy = page();
  const big = size => {
    const file = heavy.dom.file(`видео-${size}.mov`, { type: "video/quicktime", body: "x" });
    file.size = size;
    return file;
  };
  paste(heavy, [big(30 * 1024 * 1024), big(30 * 1024 * 1024)]);
  assert.equal(shelf(heavy).length, 1, "48 МБ — потолок байтов, свежее остаётся");
});

test("дедуп по содержимому, а не по имени", async () => {
  const main = page();
  // Восемь скриншотов macOS зовутся одинаково: отличить их можно только байтами.
  paste(main, [main.dom.file("image.png", { body: "первый" })]);
  paste(main, [main.dom.file("image.png", { body: "второй" })]);
  paste(main, [main.dom.file("image.png", { body: "первый" })]);
  await drain();
  assert.equal(shelf(main).length, 3, "на полке лежат все три");
  pills(main, 3);
  const haul = main.inner.cashoutHaul();
  assert.equal(haul.want, 3, "плашек в поле три");
  assert.equal(haul.files.length, 2, "одинаковое содержимое уезжает один раз");
});

test("считаем плашки штуками и берём с конца полки", () => {
  const main = page();
  for (const name of ["старый-1.png", "старый-2.png", "новый-1.png", "новый-2.png"]) {
    paste(main, [main.dom.file(name)]);
  }
  // Два вложения Элвис уже отправил — в поле осталось два.
  pills(main, 2);
  assert.equal(main.inner.cashoutPills(), 2, "три приметы плашки считают одну карточку один раз");
  assert.deepEqual(plain(main.inner.cashoutHaul().files.map(item => item.name)), ["новый-1.png", "новый-2.png"],
    "уезжает то, что видно в поле, а не вся история окна");
});

test("одинаковые имена разводятся суффиксом", () => {
  const main = page();
  const taken = new Set(["image.png"]);
  assert.equal(main.inner.cashoutUniqueName("image.png", taken), "image-2.png");
  taken.add("image-2.png");
  assert.equal(main.inner.cashoutUniqueName("image.png", taken), "image-3.png",
    "одинаковое имя Claude склеивает в ОДНО вложение — часть скриншотов пропала бы");
});

test("донор кладёт вложения в память родителя, новое окно их прикладывает", () => {
  const main = page({ draft: "", answer: "" });
  const donor = page({ href: POPOUT, title: "VkusnoffKz 2", opener: main.win });
  paste(donor, [donor.dom.file("image.png", { body: "раз" }), donor.dom.file("image.png", { body: "два" })]);
  pills(donor, 2);
  donor.dom.command(cashout({ title: "VkusnoffKz 2" }));

  const record = stored(donor);
  assert.equal(record.to, "pending", "запись переноса прежняя — вложения в неё НЕ кладутся");
  assert.deepEqual(plain(donor.api.status().cashout.files), { want: 2, sent: 2, done: 0 });
  assert.equal(shelf(donor).length, 2, "из донора ничего не снимаем — только копируем");
  assert.deepEqual(plain(main.win.__myclaudeFiles.carry.files.map(file => file.name)), ["image.png", "image-2.png"],
    "копии делает главное окно своим File: донора закрывают сразу после доезда текста");

  const born = fresh(main, { ...record, to: "local_new", title: "VkusnoffKz 3", stampedAt: Date.now() });
  acceptFiles(born);
  assert.equal(born.inner.tryPasteCashout(), "ждём доезда");
  step(born);
  assert.equal(born.parts.editor.textContent, TEXT, "текст доехал");
  assert.equal(born.inner.cashoutPills(), 2, "и вложения — ПОСЛЕ текста, иначе выделение поля смахнуло бы их");
  step(born);
  assert.deepEqual(plain(born.api.status().cashout.files), { want: 2, sent: 2, done: 2 });
  assert.equal(main.win.__myclaudeFiles.carry, null, "груз отпущен, байты свободны");
  assert.equal(born.dom.query("#myclaude-new-window-note"), null, "всё доехало — плашке молчать");
});

test("прикладываем только недостающие вложения", () => {
  const main = page({ draft: "", answer: "" });
  const donor = page({ href: POPOUT, title: "VkusnoffKz 2", opener: main.win });
  paste(donor, [donor.dom.file("a.png"), donor.dom.file("b.png")]);
  pills(donor, 2);
  donor.dom.command(cashout({ title: "VkusnoffKz 2" }));

  const born = fresh(main, { ...stored(donor), to: "local_new", title: "VkusnoffKz 3", stampedAt: Date.now() });
  acceptFiles(born);
  // Одно вложение новый чат уже держит сам.
  pills(born, 1, "a.png");
  born.inner.tryPasteCashout();
  step(born);
  assert.equal(born.inner.cashoutPills(), 2, "приложили одно, а не оба: сторож тикает часто и задвоил бы");
});

test("груз некуда положить — Элвису говорят плашкой", () => {
  // Попап без родителя: главное окно закрыто, класть вложения некому.
  const donor = page({ href: POPOUT, title: "VkusnoffKz 2" });
  paste(donor, [donor.dom.file("image.png")]);
  pills(donor, 3);
  donor.dom.command(cashout({ title: "VkusnoffKz 2" }));
  const note = donor.dom.query("#myclaude-new-window-note");
  assert.ok(note, "плашка есть");
  assert.equal(note.textContent, "Вложения останутся здесь: 3");
  assert.deepEqual(plain(donor.api.status().cashout.files), { want: 3, sent: 0, done: 0 });
  assert.notEqual(stored(donor), null, "текст всё равно едет: вложения перенос не отменяют");
});

test("доехали не все — число и плашка, а не молчание", () => {
  const main = page({ draft: "", answer: "" });
  const donor = page({ href: POPOUT, title: "VkusnoffKz 2", opener: main.win });
  paste(donor, [donor.dom.file("a.png"), donor.dom.file("b.png")]);
  pills(donor, 2);
  donor.dom.command(cashout({ title: "VkusnoffKz 2" }));

  const born = fresh(main, { ...stored(donor), to: "local_new", title: "VkusnoffKz 3", stampedAt: Date.now() });
  // Claude принял только одну карточку из двух.
  let once = false;
  born.parts.editor.addEventListener("paste", event => {
    if (once) return;
    once = true;
    for (const file of (event.clipboardData?.files ?? []).slice(0, 1)) {
      born.dom.pill(born.parts.block, { name: file.name });
    }
  });
  born.inner.tryPasteCashout();
  for (let tick = 0; tick < 45; tick += 1) step(born);
  assert.deepEqual(plain(born.api.status().cashout.files), { want: 2, sent: 2, done: 1 });
  assert.equal(born.dom.query("#myclaude-new-window-note").textContent, "Вложения доехали не все: 1 из 2");
  assert.equal(main.win.__myclaudeFiles.carry, null, "груз отпущен и на неудаче — байты не висят");
});

test("значок композера картинкой data: за вложение не считается", () => {
  const main = page();
  // Кнопки Claude рисуются svg в data: — селектор по «data:image/» насчитал бы
  // вложений больше, чем их есть, и часть полки уехала бы зря.
  main.parts.block.add("img", { attrs: { src: "data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=" } });
  assert.equal(main.inner.cashoutPills(), 0, "значков в поле нет — вложений тоже");
  main.dom.pill(main.parts.block, { name: "снимок.png" });
  assert.equal(main.inner.cashoutPills(), 1, "а настоящая плашка считается");
});

// ---- Уборка полки (#5789) --------------------------------------------------
// Полка обязана отражать то, что ВИДНО в поле. Элвис снимает плашку крестиком
// или отправляет сообщение — вложение ушло из поля, а из памяти окна нет: тогда
// «Обкэшить» увозит не то, что видно, а снятый файл выигрывает у нового с тем же
// именем (месяц отладки у донора ElvisOS). Плюс вес: без уборки в каждом окне
// висят ссылки на 24 файла и 48 МБ до самого закрытия Claude.

test("уборка: снятое крестиком не уезжает вместо видимого", () => {
  const main = page();
  paste(main, [main.dom.file("первый.png"), main.dom.file("второй.png")]);
  main.dom.pill(main.parts.block, { name: "первый.png" });
  const second = main.dom.pill(main.parts.block, { name: "второй.png" });
  jump(main, 11000);
  // Крестиком снято ПОСЛЕДНЕЕ вложение — по одному счёту плашек этого не узнать.
  second.remove();
  main.inner.cashoutSweep();
  assert.deepEqual(plain(shelf(main).map(item => item.name)), ["первый.png"],
    "на полке осталось ровно то, что подписано в поле");
  assert.deepEqual(plain(main.inner.cashoutHaul().files.map(item => item.name)), ["первый.png"],
    "и уезжает оно же");
});

test("уборка: отправленное уходит с полки, а уборщик гаснет", () => {
  const main = page();
  const before = main.counters.intervals;
  paste(main, [main.dom.file("снимок.png")]);
  const pill = main.dom.pill(main.parts.block, { name: "снимок.png" });
  assert.equal(main.counters.intervals, before + 1, "на полке что-то лежит — уборщик заведён");
  jump(main, 11000);
  // Сообщение отправлено: плашек в поле не осталось.
  pill.remove();
  main.inner.cashoutSweep();
  assert.equal(shelf(main).length, 0, "полка пуста — 48 МБ ссылок не висят до закрытия Claude");
  assert.equal(main.counters.intervals, before, "и уборщик погасил себя: сторожить нечего");
});

test("уборка: снятый файл не выигрывает у нового с тем же именем", () => {
  const main = page();
  // Все скриншоты macOS зовутся image.png — именно на этом донор и ломался.
  paste(main, [main.dom.file("image.png", { body: "снятый" })]);
  const pill = main.dom.pill(main.parts.block, { name: "image.png" });
  jump(main, 11000);
  pill.remove();
  main.inner.cashoutSweep();
  const born = main.dom.file("image.png", { body: "новый" });
  paste(main, [born]);
  main.dom.pill(main.parts.block, { name: "image.png" });
  const haul = main.inner.cashoutHaul();
  assert.equal(haul.files.length, 1, "в поле одно вложение — уезжает одно");
  assert.equal(haul.files[0].file, born, "и это новый файл, а не снятый крестиком");
});

test("уборка не трогает только что положенное", () => {
  const main = page();
  paste(main, [main.dom.file("снимок.png")]);
  // Плашки ещё нет: Claude рисует её не мгновенно.
  main.inner.cashoutSweep();
  assert.equal(shelf(main).length, 1, "свежая запись неприкосновенна — иначе уборка съедала бы вложение на входе");
});

test("уборка: без подписей плашек полка режется по их числу", () => {
  // Разметка Claude меняется без предупреждения: подписи прочесть не вышло, но
  // превью видно два. Тогда места достаются самым свежим записям — тот же
  // порядок, каким полку читает сбор груза.
  const main = page();
  paste(main, [main.dom.file("1.png"), main.dom.file("2.png"), main.dom.file("3.png")]);
  main.parts.block.add("img", { attrs: { src: "blob:claude/один" } });
  main.parts.block.add("img", { attrs: { src: "blob:claude/два" } });
  jump(main, 11000);
  main.inner.cashoutSweep();
  assert.deepEqual(plain(shelf(main).map(item => item.name)), ["2.png", "3.png"],
    "лишнее ушло, свежее осталось");
});

test("уборщик возвращается вместе с перезаписью inject.js", () => {
  const main = page();
  paste(main, [main.dom.file("снимок.png")]);
  main.dom.pill(main.parts.block, { name: "снимок.png" });
  const again = main.reload();
  assert.equal(again.error, null);
  assert.equal(shelf(main).length, 1, "полка пережила перезапись");
  jump(main, 11000);
  // Уборщик заведён самим инжектом — гоняем его тиком, а не вызовом помощника.
  main.dom.fireKind("interval");
  assert.equal(shelf(main).length, 1, "плашка в поле — запись на месте");
  main.dom.query(".epitaxy-attachment-pill").remove();
  main.dom.fireKind("interval");
  assert.equal(shelf(main).length, 0, "уборщик нового экземпляра работает сам, без новой вставки");
});

test("уборка молчит, когда поля ввода нет на месте", () => {
  // React пересобирает композер целиком: сверять не с чем, и пустое поле это не
  // «вложений не осталось». Вычеркнуть живое вложение уборка права не имеет.
  const main = page();
  paste(main, [main.dom.file("снимок.png")]);
  main.dom.pill(main.parts.block, { name: "снимок.png" });
  jump(main, 11000);
  main.parts.block.remove();
  main.inner.cashoutSweep();
  assert.equal(shelf(main).length, 1, "поля нет — полку не трогаем");
});
