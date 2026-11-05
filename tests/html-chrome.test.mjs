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

test("К-DOCK-1 (WF277): open-html&dock=1 — место и рамка окна в том же запросе и прежние frame и bg (запасной путь); битое место — прежний адрес", () => {
  const { htmlChromeUrl } = loadInner().inner;
  const dock = { x: 0, y: 55, w: 420, h: 563, wx: 0, wy: 29, ww: 1067, wh: 618 };
  assert.equal(htmlChromeUrl("/tmp/a b/отчёт.html", "click", "local_aaaa-1111", [0, 29, 1067, 618], "#1c1917", dock),
    `http://127.0.0.1:47615/open-html?mode=click&dock=1&path=${encodeURIComponent("/tmp/a b/отчёт.html")}&chat=local_aaaa-1111&x=0&y=55&w=420&h=563&wx=0&wy=29&ww=1067&wh=618&frame=0,29,1067,618&bg=1c1917`);
  assert.equal(htmlChromeUrl("/tmp/a.md", "click", null, null, "", dock),
    "http://127.0.0.1:47615/open-html?mode=click&dock=1&path=%2Ftmp%2Fa.md&x=0&y=55&w=420&h=563&wx=0&wy=29&ww=1067&wh=618", "md — без рамки, как и без дока");
  assert.equal(htmlChromeUrl("/tmp/x.png", "click", null, null, "", { ...dock, w: 0 }), "http://127.0.0.1:47615/open-html?mode=click&path=%2Ftmp%2Fx.png", "w = 0 — без dock");
  assert.equal(htmlChromeUrl("/tmp/x.png", "click", null, null, "", { ...dock, wx: 1.5 }), "http://127.0.0.1:47615/open-html?mode=click&path=%2Ftmp%2Fx.png", "дробь — без dock");
});

test("WF277: клик по файлу из чата забирает у Claude html, pdf, картинки, md, txt, видео, звук и zip (#11347); код — нет", () => {
  const { FILE_OPEN_RE } = loadInner().inner;
  for (const ext of ["html", "htm", "pdf", "png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp", "md", "markdown", "txt",
    "mp4", "mov", "m4v", "webm", "mp3", "m4a", "aac", "wav", "zip", "MD", "MP4", "ZIP"]) assert.ok(FILE_OPEN_RE.test(`/tmp/файл с пробелом.${ext}`), ext);
  for (const ext of ["swift", "js", "json", "py", "mdx", "mp4.part", "zip.part", "7z"]) assert.ok(!FILE_OPEN_RE.test(`/tmp/x.${ext}`), ext);
});
