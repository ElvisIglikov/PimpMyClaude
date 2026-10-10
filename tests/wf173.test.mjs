// WF173 (09.10.2026, обратная связь Элвиса 02:00 по снимку ответа Рика и #9181):
//   1) ОШИБКА — вставленный скриншот без номера. Диктатор (и Finder, и съёмщики) кладут рядом
//      со снимком его путь простым текстом; страница видела «текст рядом с картинкой» и отдавала
//      вставку Claude как есть. Путь/имя самого снимка — не текст: номер ставится;
//   2) вид ответа: цитата — волосок цветом текста, отступ 10; маркеры тише, в свёртках их нет;
//      строки плотнее, абзацы врозь — только ответы Claude;
//   3) карточки файлов в ленте — плашки в одну строку, не квадраты 120×120.
// Геометрию CSS стаб не считает — правила сверяются текстом, вставка — через страницу.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject } from "./load.mjs";

const CHAT = "https://claude.ai/epitaxy/local_a";

const page = () => {
  const loaded = loadInject({
    href: CHAT,
    title: "Rick чат Элвиса",
    html: dom => {
      const parts = dom.composer();
      parts.box = parts.shell.add("div", { attrs: { "data-cds-composer-attachments": "" } });
      parts.line = parts.editor.add("p", { text: "" });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
  loaded.got = [];
  loaded.parts.editor.addEventListener("paste", event => {
    const files = [...(event.clipboardData?.files ?? [])];
    loaded.got.push(files);
    for (const file of files) {
      const tile = loaded.parts.box.add("div", { attrs: { "data-cds-attachment": "" } });
      tile.add("button", { attrs: { "aria-label": `Remove ${file.name}` } });
    }
  });
  loaded.native = [];
  loaded.document.addEventListener("paste", event => loaded.native.push(event));
  loaded.document.addEventListener("drop", event => loaded.native.push(event));
  return loaded;
};
const clip = (files, text) => ({ files, getData: type => (type === "text/plain" ? text : "") });
const paste = (loaded, files, text) => loaded.document.dispatchEvent({
  type: "paste", target: loaded.parts.line, isTrusted: true, cancelable: true, clipboardData: clip(files, text) });
const names = loaded => loaded.got.map(files => files.map(file => file.name));

test("ОШИБКА: снимок Диктатора (картинка + путь с «\\ » текстом) получает номер", async () => {
  const loaded = page();
  const shot = loaded.dom.image("Снимок 2026-10-09 в 01.58.12-123.png");
  const passed = paste(loaded, [shot], "/Users/dev/Pictures/Снимки/Снимок\\ 2026-10-09\\ в\\ 01.58.12-123.png");
  assert.equal(passed, false, "вставку обязаны забрать — иначе без номера");
  assert.equal(loaded.native.length, 0);
  await loaded.inner.shotState.chain;
  assert.deepEqual(names(loaded), [["Скриншот 1.png"]]);
});

test("ОШИБКА классом: имя из Finder (с пробелами), file://-адрес, пачка путей — тоже с номерами", async () => {
  const loaded = page();
  paste(loaded, [loaded.dom.image("Снимок экрана 2026-10-09.png")], "Снимок экрана 2026-10-09.png");
  paste(loaded, [loaded.dom.image("b.png")], "file:///Users/dev/Desktop/%D0%A1%D0%BD%D0%B8%D0%BC%D0%BE%D0%BA.png");
  paste(loaded, [loaded.dom.image("c.png"), loaded.dom.image("d.jpg", { type: "image/jpeg" })],
    "/tmp/c.png /tmp/d.jpg\n");
  await loaded.inner.shotState.chain;
  assert.deepEqual(names(loaded), [["Скриншот 1.png"], ["Скриншот 2.png"], ["Скриншот 3.png", "Скриншот 4.jpg"]]);
});

test("настоящий текст рядом с картинкой по-прежнему не трогаем (Excel, фраза с именем файла)", async () => {
  const loaded = page();
  for (const text of ["1\t2", "смотри shot.png", "/Users/dev/notes.txt", "Привет"]) {
    loaded.native.length = 0;
    assert.equal(paste(loaded, [loaded.dom.image("shot.png")], text), true, `«${text}»: вставку отменили`);
    assert.equal(loaded.native.length, 1, `«${text}»: родная вставка Claude не дошла`);
  }
  await loaded.inner.shotState.chain;
  assert.deepEqual(loaded.got, []);
});

const css = () => {
  const loaded = page();
  return [...loaded.inner.RULES].join("\n");
};
const rule = (text, needle) => text.split("\n").find(line => line.includes(needle)) ?? "";

test("цитата в ответе: волосок 1,5 px цветом текста, отступ 10 px, без акцента; только ответы Claude", () => {
  const text = css();
  const quote = rule(text, '[data-cds="AssistantMessage"] [data-cds="Prose"] blockquote{');
  assert.ok(quote, "правила цитаты нет");
  assert.match(quote, /border-left:1\.5px solid currentColor !important/);
  assert.match(quote, /padding-left:10px !important/);
  assert.match(quote, /margin-left:0 !important/);
  assert.ok(!/accent|--cds-border/.test(quote), "не акцентом и не цветом рамки темы");
  assert.ok(!/user-turn|ChatComposer/.test(quote));
});

test("абзацы: строки 1.45, между абзацами/списками/цитатами .8em, пункты .5em", () => {
  const text = css();
  assert.match(rule(text, '[data-cds="Prose"] :is(p,li,blockquote){line-height'), /line-height:1\.45 !important/);
  assert.match(rule(text, '[data-cds="Prose"] * + :is(p,ul,ol,blockquote){'), /margin-top:\.8em !important/);
  assert.match(rule(text, '[data-cds="Prose"] li + li{'), /margin-top:\.5em !important/);
  for (const line of text.split("\n").filter(item => item.includes("line-height:1.45"))) {
    assert.match(line, /^\.epitaxy-chat-panel \[data-cds="AssistantMessage"\]/, "интервал — только в ответах Claude");
  }
});

test("маркеры: тише в ответах; в свёртке 12ф кругляшков и отступа под них нет", () => {
  const text = css();
  const marker = rule(text, "li::marker{");
  assert.match(marker, /color:var\(--cds-text-secondary,currentColor\)/);
  assert.match(marker, /font-size:\.8em/);
  const fold = rule(text, "ul[data-myclaude-fold-body],[data-myclaude-fold-body] ul");
  assert.ok(fold, "правила списка в свёртке нет");
  assert.match(fold, /list-style:none !important/);
  assert.match(fold, /padding-inline-start:0 !important/);
});

test("карточки файлов в ленте — плашка в строку «имя · размер», поле ввода не трогаем", () => {
  const text = css();
  const tile = '.epitaxy-chat-panel [data-cds="MessageAttachmentsFile"]:not([data-cds-composer-attachments] *)';
  const root = rule(text, `${tile}{`);
  assert.match(root, /width:auto !important;height:auto !important/, "квадрат 120×120 остался");
  assert.match(rule(text, `${tile} .justify-between>:not(:first-child){`), /display:none/, "плашка «HTML» осталась");
  assert.match(rule(text, `${tile} .justify-between,`), /flex-direction:row !important/);
  assert.match(rule(text, `${tile} .line-clamp-2{`), /-webkit-line-clamp:1/);
  // Ссылку карточки (клик Claude) не прячем и не перекрываем.
  for (const line of text.split("\n").filter(item => item.includes("MessageAttachmentsFile"))) {
    assert.ok(!/pointer-events|a\{|button\{/.test(line), `клик карточки тронут: ${line}`);
  }
});
