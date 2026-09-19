// HTML-файлы — в Chrome (раздел 12д, #6618): что считается страницей в поле «Page URL» панели.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInner } from "./load.mjs";

test("путь из поля панели Browser: только абсолютные .html/.htm", () => {
  const { htmlChromePanePath } = loadInner().inner;
  assert.equal(htmlChromePanePath("/tmp/a b/отчёт.html"), "/tmp/a b/отчёт.html");
  assert.equal(htmlChromePanePath("file:///tmp/a%20b/x.HTM"), "/tmp/a b/x.HTM");
  assert.equal(htmlChromePanePath("http://localhost:1488/index.html"), null);
  assert.equal(htmlChromePanePath("/tmp/notes.md"), null);
  assert.equal(htmlChromePanePath("/tmp/00-превью.png"), "/tmp/00-превью.png");
  assert.equal(htmlChromePanePath("/tmp/счёт.PDF"), "/tmp/счёт.PDF");
  assert.equal(htmlChromePanePath(""), null);
});
