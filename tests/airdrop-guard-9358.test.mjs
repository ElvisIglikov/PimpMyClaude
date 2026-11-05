// Фото с AirDrop в поле Рика (#9358, раздел 12т²). Приложение перед ⌘V шлёт
// airdrop-guard {id, n}; первая доверенная вставка с файлами снимает сторожа и
// идёт как есть — и в поле с текстом (#11310), плашка «вставил N фото». Без сторожа — ничего.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInner, plain } from "./load.mjs";

const NOTE = "#myclaude-new-window-note";
const page = (text = "") => {
  const loaded = loadInner({ html: dom => dom.composer({ text }) });
  return loaded;
};
const paste = (loaded, { trusted = true, files = 1 } = {}) => loaded.win.dispatchEvent({
  type: "paste",
  isTrusted: trusted,
  clipboardData: { files: Array.from({ length: files }, (_, i) => loaded.dom.file(`IMG_${i}.HEIC`)) },
});
const note = loaded => loaded.dom.query(NOTE)?.textContent ?? "";

test("поле без текста: вставка идёт как есть, плашка «вставил N фото»", () => {
  const loaded = page();
  loaded.dom.command({ id: "a1", action: "airdrop-guard", n: 3 });
  assert.equal(paste(loaded, { files: 3 }), true, "вставку гасить нельзя");
  assert.match(note(loaded), /Вставил 3 фото с AirDrop/);
  assert.deepEqual(plain(loaded.api.status().airdrop), { armed: false, last: "pasted" });
});

test("в поле текст: вставка всё равно идёт, текст не трогаем (#11310)", () => {
  const loaded = page("пишу Рику");
  loaded.dom.command({ id: "a2", action: "airdrop-guard", n: 2 });
  assert.equal(paste(loaded, { files: 2 }), true, "фото ложатся рядом с черновиком");
  assert.match(note(loaded), /Вставил 2 фото с AirDrop/);
  assert.deepEqual(plain(loaded.api.status().airdrop), { armed: false, last: "pasted" });
});

test("без сторожа, чужая вставка и вставка без файлов — не трогаем", () => {
  const loaded = page("текст");
  assert.equal(paste(loaded), true, "без airdrop-guard вставка — обычная");
  loaded.dom.command({ id: "a3", action: "airdrop-guard", n: 1 });
  assert.equal(paste(loaded, { trusted: false }), true, "синтетическую вставку страницы не трогаем");
  assert.equal(paste(loaded, { files: 0 }), true, "вставку текста не трогаем");
  assert.equal(plain(loaded.api.status().airdrop).armed, true, "сторож ждёт вставку с файлами");
});

test("тот же id второй раз и плохое n — сторож не взводится", () => {
  const loaded = page("текст");
  loaded.dom.command({ id: "a4", action: "airdrop-guard", n: 0 });
  loaded.dom.command({ id: "a5", action: "airdrop-guard", n: "2" });
  assert.equal(plain(loaded.api.status().airdrop).armed, false);
  loaded.dom.command({ id: "a6", action: "airdrop-guard", n: 1 });
  assert.equal(plain(loaded.api.status().airdrop).armed, true);
  paste(loaded);
  loaded.dom.command({ id: "a6", action: "airdrop-guard", n: 1 });
  assert.equal(plain(loaded.api.status().airdrop).armed, false, "повтор id не взводит сторожа заново");
});

test("сторож живёт 6 с", () => {
  const loaded = page("текст");
  loaded.dom.command({ id: "a7", action: "airdrop-guard", n: 1 });
  loaded.run("(() => { const real = Date.now; Date.now = () => real() + 6500; })()");
  paste(loaded);
  assert.equal(plain(loaded.api.status().airdrop).last, null, "просроченный сторож вставку не считает");
});
