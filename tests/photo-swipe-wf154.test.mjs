// #8890 (WF154): «раньше можно было картинки листать влево-вправо… на весь экран».
// Класс: фото, открытое мимо нашего просмотра (своя всплывашка Claude ImagePreviewModal —
// одна картинка, без листания), и плитка, где рядом с фото лежит значок, — ← → и свайп
// вбок всё равно листают фото чата: всплывашка переходит в наш просмотр.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const photo = (parent, src, { w = 640, h = 1440, shown = [71, 160] } = {}) => {
  const img = parent.add("img", { attrs: { src } });
  img.naturalWidth = w;
  img.naturalHeight = h;
  img.rect = { left: 0, top: 0, width: shown[0], height: shown[1] };
  return img;
};

const page = () => {
  const nodes = {};
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_swipe",
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      const row = feed.add("div", { class: "group/message-row" });
      const tileA = row.add("span", { attrs: { role: "button", tabindex: "0" } });
      nodes.a = photo(tileA, "data:image/png;base64,AAA");
      // Плитка с фото и значком типа файла рядом (16×16 на экране).
      const tileB = row.add("button", { attrs: { type: "button" } });
      nodes.badge = photo(tileB, "data:image/png;base64,BADGE", { w: 32, h: 32, shown: [16, 16] });
      nodes.b = photo(tileB, "data:image/png;base64,BBB");
      nodes.tileB = tileB;
      nodes.c = photo(row, "data:image/png;base64,CCC");
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  return { loaded, nodes };
};

// Всплывашка Claude (08.10): base-ui Dialog на весь экран, фото и кнопка «Close image preview».
const claudePreview = (loaded, src) => {
  const dialog = loaded.document.body.add("div", { attrs: { role: "dialog", "aria-modal": "true" } });
  const shown = photo(dialog, src, { shown: [400, 900] });
  const close = dialog.add("button", { attrs: { "aria-label": "Close image preview", "data-testid": "close-file-preview" } });
  let closed = 0;
  close.addEventListener("click", () => { closed += 1; dialog.remove(); });
  return { dialog, shown, close, closed: () => closed };
};

const view = loaded => plain(loaded.api.viewer.state());
const key = (loaded, name, type = "keydown", extra = {}) => !loaded.win.dispatchEvent({ type, key: name, ...extra });

test("плитка со значком рядом с фото — фото открывается нашим просмотром", () => {
  const { loaded, nodes } = page();
  assert.equal(loaded.inner.photoAt(nodes.tileB), nodes.b, "значок 16×16 — не второе фото");
  for (const type of ["pointerdown", "mousedown", "click"]) {
    loaded.document.dispatchEvent({ type, target: nodes.tileB, button: 0, clientX: 5, clientY: 5 });
  }
  assert.deepEqual(view(loaded), { open: true, index: 1, total: 3, zoom: false, grown: false });
  key(loaded, "ArrowRight");
  assert.equal(view(loaded).index, 2);
});

test("всплывашка Claude с фото: → закрывает её и листает дальше нашим просмотром, Claude клавиши не видит", () => {
  const { loaded } = page();
  const preview = claudePreview(loaded, "data:image/png;base64,BBB");
  const claude = [];
  loaded.win.addEventListener("keydown", event => claude.push(`down ${event.key}`));
  loaded.win.addEventListener("keyup", event => claude.push(`up ${event.key}`));
  assert.ok(loaded.inner.photoClaudePreview(), "всплывашку узнали");
  assert.equal(key(loaded, "ArrowRight"), true, "стрелка — наша");
  assert.equal(preview.closed(), 1, "всплывашку Claude закрыли её же кнопкой");
  assert.deepEqual(view(loaded), { open: true, index: 2, total: 3, zoom: false, grown: false });
  assert.equal(key(loaded, "ArrowRight", "keyup"), true, "и отпускание той же стрелки");
  assert.deepEqual(claude, []);
  key(loaded, "ArrowLeft");
  key(loaded, "ArrowLeft");
  assert.equal(view(loaded).index, 0, "дальше листает наш просмотр по кругу");
  assert.equal(loaded.api.status().photo.from, "feed");
});

test("фото всплывашки вне ленты — первым, ← ведёт к последнему фото чата", () => {
  const { loaded } = page();
  claudePreview(loaded, "data:image/png;base64,ZZZ");
  key(loaded, "ArrowLeft");
  assert.deepEqual(view(loaded), { open: true, index: 3, total: 4, zoom: false, grown: false });
  assert.equal(loaded.inner.photoState.parts.img.src, "data:image/png;base64,CCC");
});

test("свайп вбок по всплывашке — один шаг на жест", () => {
  const { loaded } = page();
  const preview = claudePreview(loaded, "data:image/png;base64,AAA");
  for (const deltaX of [30, 40, 80, 120]) loaded.win.dispatchEvent({ type: "wheel", target: preview.shown, deltaX, deltaY: 1 });
  assert.equal(preview.closed(), 1);
  assert.equal(view(loaded).index, 1, "инерция того же жеста не листает");
});

test("без всплывашки, с клавишей-модификатором и в чужом диалоге стрелки остаются Claude", () => {
  const { loaded } = page();
  assert.equal(key(loaded, "ArrowRight"), false);
  claudePreview(loaded, "data:image/png;base64,AAA");
  assert.equal(key(loaded, "ArrowRight", "keydown", { metaKey: true }), false);
  assert.equal(key(loaded, "ArrowRight", "keydown", { shiftKey: true }), false);
  assert.equal(view(loaded).open, false);
  // Диалог с полем ввода (настройки, переименование) — не всплывашка фото.
  const { loaded: other } = page();
  const dialog = other.document.body.add("div", { attrs: { role: "dialog" } });
  photo(dialog, "data:image/png;base64,AAA", { shown: [400, 900] });
  dialog.add("input", { attrs: { type: "text" } });
  assert.equal(other.inner.photoClaudePreview(), null);
  assert.equal(key(other, "ArrowRight"), false);
});
