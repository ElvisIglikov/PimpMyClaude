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

test("К-V1 (WF97): open-html несёт chat этого чата, id неизвестен — ключа нет", () => {
  const { htmlChromeUrl } = loadInner().inner;
  const chat = "local_aaaa-1111";
  assert.equal(htmlChromeUrl("/tmp/a b/11.html", "click", chat),
    `http://127.0.0.1:47615/open-html?mode=click&path=%2Ftmp%2Fa%20b%2F11.html&chat=${chat}`);
  assert.equal(htmlChromeUrl("/tmp/x.png", "auto", null), "http://127.0.0.1:47615/open-html?mode=auto&path=%2Ftmp%2Fx.png");
  assert.equal(htmlChromeUrl("/tmp/x.png", "auto", ""), "http://127.0.0.1:47615/open-html?mode=auto&path=%2Ftmp%2Fx.png");
});
