// #10699, раздел 12п⁵ inject.js: ролики и картинки чата — с диска.
// Слово Элвиса 23.10.2026: «Капец долго грузятся ролики… как будто бы они из интернета откуда-то скачиваются… Они же на
// диске всё равно лежат». Замер 23.10: ролик — <video controls preload="none" src="/api/organizations/<org>/files/<id>/
// contents" title="<имя>">, путь на диске — `path` в пропсах волокна двумя шагами выше; картинка-вложение — img с
// data-image-file-name, src …/preview и srcset 2x, путь — `path` пятью шагами выше.
//
// Что проверяется:
//   1) ролик Claude: запрос кадра `GET /media-thumb?chat&name&path`; до ответа плеер Claude как был; JPEG — плеер
//      спрятан меткой (узел остаётся), рядом своя кнопка с кадром и ▶; 204 — плашка 300×150 с именем;
//   2) приложение не нашло, молчит, ответ не JPEG — плеер Claude, повтор не раньше MEDIA_RETRY_MS; ролик, запущенный
//      в Claude, не трогаем;
//   3) нажатие: путь известен — `/open-html?mode=click&path`, нет — `&name`; `found:false`, тишина или 204 на `name` —
//      кнопка уходит, плеер Claude обратно; с местом панели — `dock=1` и место;
//   4) виртуальная лента: узел ушёл — кнопка тоже, пришёл тот же файл — кадр из кэша без запроса; другой файл в том же
//      узле — заново;
//   5) картинка-вложение: `GET /media-file`, байты PNG — blob: вместо src, srcset снят; ошибка загрузки — исходный адрес;
//      чужие байты — как было; кадр ролика — не фото просмотра 12л; dispose возвращает всё; status().chatMedia.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_a6b6fb8a-03e0-45a5-af2e-30d1d800bd1e";
const ORG = "e8d75308-e276-449a-86ed-f98d7b3771ab";
const DIR = "/Users/dev/Projects/Rick/work/pokaz-1023";
const VIDEO = `${DIR}/pizza-v2-nik.mp4`;
const PHOTO = `${DIR}/paket-a-25-10.png`;
const JPEG = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]);
const PNG = new Uint8Array([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
const HIDDEN = "data-myclaude-media";
const PLAY = "data-myclaude-media-play";
const flush = async () => { for (let i = 0; i < 6; i += 1) await new Promise(resolve => setImmediate(resolve)); };
const bytes = data => ({ ok: true, status: 200, arrayBuffer: async () => data.buffer.slice(0), json: async () => { throw new SyntaxError("not json"); } });
const json = body => ({ ok: true, status: 200, json: async () => body, arrayBuffer: async () => new ArrayBuffer(0) });
const empty = (status = 204) => ({ ok: status < 300, status, json: async () => { throw new SyntaxError("empty"); }, arrayBuffer: async () => new ArrayBuffer(0) });

// Ролик, как его кладёт Claude: после текста сообщения, путь — у обёртки меню (surface "attachment") двумя шагами выше.
const video = (parent, { name = "pizza-v2-nik.mp4", path = VIDEO, src = `/api/organizations/${ORG}/files/c5f4e682/contents` } = {}) => {
  const node = parent.add("video", { attrs: { class: "mt-2 block h-auto w-auto max-h-[240px] max-w-[320px] rounded-lg bg-black",
    controls: "", preload: "none", src, title: name }, rect: { left: 318, top: 200, width: 300, height: 150 } });
  node.paused = true;
  node.currentTime = 0;
  node.__reactFiber$test = { memoizedProps: { src, title: name }, return: { memoizedProps: { trigger: {} },
    return: { memoizedProps: path ? { path, surface: "attachment" } : { surface: "attachment" }, return: null } } };
  return node;
};
// Картинка-вложение: превью Claude с srcset, путь — пятью шагами выше.
const photo = (parent, { name = "paket-a-25-10.png", path = PHOTO } = {}) => {
  const button = parent.add("button", { attrs: { type: "button", title: name } });
  const img = button.add("img", { attrs: { alt: name, "data-image-file-name": name, class: "block object-contain",
    "data-image-original-src": `/api/organizations/${ORG}/files/e5b7127c/contents`,
    src: `/api/${ORG}/files/e5b7127c/preview`, srcset: `/api/${ORG}/files/e5b7127c/preview 2x` },
  rect: { left: 575, top: 400, width: 120, height: 120 } });
  let fiber = { memoizedProps: { path, surface: "attachment" }, return: null };
  for (let hop = 0; hop < 4; hop += 1) fiber = { memoizedProps: { hop }, return: fiber };
  img.__reactFiber$test = { memoizedProps: { alt: name }, return: fiber };
  return img;
};

const page = ({ reply = url => (url.includes("/media-thumb?") ? bytes(JPEG) : url.includes("/media-file?") ? bytes(PNG) : json({ found: true, taken: true, opened: true })),
  build = null, href = `https://claude.ai/epitaxy/${CHAT}`, blobs = true } = {}) => {
  const nodes = {};
  const loaded = loadInject({
    href, title: "Rick", storage: { local: { "myclaude-auto-allow-roam": "off" } }, geometry: { frame: [0, 29, 1280, 742] },
    html: dom => {
      const parts = dom.composer({});
      const panel = dom.document.body.add("div", { attrs: { class: "epitaxy-chat-panel" } });
      const feed = panel.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      nodes.row = feed.add("div", { attrs: { "data-testid": "transcript-row" } });
      nodes.message = nodes.row.add("div", { attrs: { "data-cds": "AssistantMessage" } });
      nodes.message.add("div", { attrs: { "data-cds": "Prose" }, text: "Вот ролик" });
      nodes.box = nodes.message.add("div");
      build ? build(nodes) : (nodes.video = video(nodes.box));
      nodes.cards = nodes.box.add("div", { attrs: { class: "flex flex-wrap gap-2 mt-2" } });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.box = { reply };
  loaded.win.fetch = address => {
    const url = String(address);
    loaded.calls.push(url);
    return Promise.resolve().then(() => loaded.box.reply(url));
  };
  loaded.blobs = [];
  if (blobs) {
    loaded.win.Blob = class { constructor(parts, options) { this.parts = parts; this.type = options?.type; } };
    loaded.win.URL = { createObjectURL: blob => { loaded.blobs.push(blob); return `blob:https://claude.ai/${loaded.blobs.length}`; },
      revokeObjectURL: url => { loaded.revoked = [...(loaded.revoked ?? []), url]; } };
  }
  return { loaded, nodes };
};
const asked = (loaded, part) => loaded.calls.filter(url => url.includes(part));
const buttonOf = video => {
  const next = video.nextSibling;
  return next?.nodeType === 1 && next.hasAttribute(PLAY) ? next : null;
};
const status = loaded => plain(loaded.api.status().chatMedia);
const click = (loaded, target) => loaded.win.dispatchEvent({ type: "click", isTrusted: true, target, button: 0, detail: 1 });

test("12п⁵: ролик Claude — кадр с диска вместо плеера: запрос с путём, до ответа плеер как был, потом кнопка с кадром и ▶", async () => {
  const { loaded, nodes } = page();
  loaded.inner.mediaTick();
  assert.deepEqual(asked(loaded, "/media-thumb?"), [
    `http://127.0.0.1:47615/media-thumb?chat=${CHAT}&name=pizza-v2-nik.mp4&path=${encodeURIComponent(VIDEO)}`,
  ]);
  assert.equal(nodes.video.getAttribute(HIDDEN), null, "до ответа приложения плеер Claude не прячем");
  assert.equal(buttonOf(nodes.video), null);
  await flush();
  const button = buttonOf(nodes.video);
  assert.ok(button, "своей кнопки нет");
  assert.equal(nodes.video.getAttribute(HIDDEN), "hidden");
  assert.ok(nodes.video.isConnected, "узел React на месте");
  assert.equal(button.tagName, "BUTTON");
  assert.equal(button.getAttribute(PLAY), "frame");
  assert.equal(button.getAttribute("class"), nodes.video.getAttribute("class"), "классы плеера Claude: отступ, скругление, 320×240");
  assert.equal(button.getAttribute("title"), "pizza-v2-nik.mp4");
  const img = button.querySelector("img");
  assert.equal(img.getAttribute("src"), "blob:https://claude.ai/1");
  assert.equal(loaded.blobs[0].type, "image/jpeg");
  assert.ok(button.querySelector('[data-k="play"]'), "▶ поверх кадра");
  // Повторные проходы ничего не шлют и вторую кнопку не ставят.
  loaded.inner.mediaTick();
  loaded.inner.mediaTick();
  assert.equal(asked(loaded, "/media-thumb?").length, 1);
  assert.equal(nodes.box.querySelectorAll(`[${PLAY}]`).length, 1);
  assert.deepEqual(status(loaded), { videos: 1, frames: 1, plates: 0, images: 0, asked: 1, failed: 0, opens: 0, given: 0, last: null });
  const css = loaded.dom.queryAll("style").map(style => style.textContent).join("\n");
  assert.match(css, /video\[data-myclaude-media="hidden"\]\{display:none !important\}/);
  assert.match(css, /\[data-myclaude-media-play\]>img\{[^}]*max-width:320px;max-height:240px/);
  // Кадр ролика — не фото ленты: просмотр 12л и перетаскивание его не берут.
  assert.equal(loaded.inner.photoAt(img), null);
  assert.equal(loaded.inner.photoAt(button), null);
});

test("12п⁵: файл есть, кадра нет (204) — тёмная плашка размером плеера Claude с ▶ и именем", async () => {
  const { loaded, nodes } = page({ reply: () => empty(204) });
  loaded.inner.mediaTick();
  await flush();
  const button = buttonOf(nodes.video);
  assert.ok(button);
  assert.equal(button.getAttribute(PLAY), "plate");
  assert.equal(button.querySelector("img"), null);
  assert.deepEqual([button.style.getPropertyValue("width"), button.style.getPropertyValue("height")], ["300px", "150px"]);
  assert.equal(button.querySelector('[data-k="name"]').textContent, "pizza-v2-nik.mp4");
  assert.equal(status(loaded).plates, 1);
});

test("12п⁵: приложение не нашло, молчит, ответ не JPEG — плеер Claude как был, повтор не раньше MEDIA_RETRY_MS", async () => {
  const replies = [() => empty(404), () => { throw new TypeError("Failed to fetch"); }, () => bytes(PNG)];
  for (const reply of replies) {
    const { loaded, nodes } = page({ reply });
    loaded.inner.mediaTick();
    await flush();
    loaded.inner.mediaTick();
    assert.equal(nodes.video.getAttribute(HIDDEN), null);
    assert.equal(buttonOf(nodes.video), null);
    assert.equal(asked(loaded, "/media-thumb?").length, 1, "повтор сразу после отказа");
    assert.equal(status(loaded).failed, 1);
    // Срок вышел — спрашиваем снова.
    for (const entry of loaded.inner.mediaState.cache.values()) entry.failAt -= loaded.inner.MEDIA_RETRY_MS;
    loaded.inner.mediaTick();
    assert.equal(asked(loaded, "/media-thumb?").length, 2);
  }
});

test("12п⁵: ролик уже запущен в Claude, ролик-blob, ролик в поле ввода, чат неизвестен — не трогаем", async () => {
  const playing = page();
  playing.nodes.video.paused = false;
  playing.loaded.inner.mediaTick();
  assert.deepEqual(asked(playing.loaded, "/media-"), []);
  const own = page({ build: nodes => { nodes.video = video(nodes.box, { src: "blob:https://claude.ai/x" }); } });
  own.loaded.inner.mediaTick();
  assert.deepEqual(asked(own.loaded, "/media-"), []);
  const draft = page({ build: nodes => { nodes.video = video(nodes.box.add("div", { attrs: { "data-cds-composer-attachments": "" } })); } });
  draft.loaded.inner.mediaTick();
  assert.deepEqual(asked(draft.loaded, "/media-"), []);
  const nowhere = page({ href: "https://claude.ai/new" });
  nowhere.loaded.inner.mediaTick();
  assert.deepEqual(asked(nowhere.loaded, "/media-"), []);
});

test("12п⁵: нажатие с известным путём — тот же клик по файлу (`click&path`); 204 — кнопка остаётся, повтор пока ждём — молчит", async () => {
  const { loaded, nodes } = page({ reply: url => (url.includes("/media-thumb?") ? bytes(JPEG) : empty(204)) });
  loaded.inner.mediaTick();
  await flush();
  const button = buttonOf(nodes.video);
  click(loaded, button.querySelector('[data-k="play"]'));
  click(loaded, button);
  assert.deepEqual(asked(loaded, "/open-html?"), [
    `http://127.0.0.1:47615/open-html?mode=click&path=${encodeURIComponent(VIDEO)}&chat=${CHAT}`,
  ], "второе нажатие, пока ждём ответа, — не второй запрос");
  assert.equal(button.getAttribute("data-myclaude-busy"), "file");
  await flush();
  assert.equal(button.getAttribute("data-myclaude-busy"), null);
  assert.ok(buttonOf(nodes.video), "ролик открыт — кнопка на месте");
  assert.equal(nodes.video.getAttribute(HIDDEN), "hidden");
  assert.deepEqual(status(loaded).last, { name: "pizza-v2-nik.mp4", path: VIDEO, via: "app", ok: true });
  // Синтетический клик (не человек) — ролик сам не открывается.
  loaded.win.dispatchEvent({ type: "click", target: button, button: 0, detail: 1 });
  assert.equal(asked(loaded, "/open-html?").length, 1);
});

test("12п⁵: путь неизвестен — `name`; Пимп не нашёл (found:false), молчит или старый (204) — плеер Claude обратно", async () => {
  const answers = [() => json({ found: false, taken: false, opened: false }), () => { throw new TypeError("Failed to fetch"); }, () => empty(204)];
  for (const answer of answers) {
    const { loaded, nodes } = page({ build: nodes => { nodes.video = video(nodes.box, { path: "" }); },
      reply: url => (url.includes("/media-thumb?") ? bytes(JPEG) : answer()) });
    loaded.inner.mediaTick();
    assert.deepEqual(asked(loaded, "/media-thumb?"), [`http://127.0.0.1:47615/media-thumb?chat=${CHAT}&name=pizza-v2-nik.mp4`]);
    await flush();
    click(loaded, buttonOf(nodes.video));
    assert.deepEqual(asked(loaded, "/open-html?"), [`http://127.0.0.1:47615/open-html?mode=click&name=pizza-v2-nik.mp4&chat=${CHAT}`]);
    await flush();
    assert.equal(buttonOf(nodes.video), null, "кнопка осталась");
    assert.equal(nodes.video.getAttribute(HIDDEN), "claude", "плеер Claude не вернулся");
    assert.equal(status(loaded).given, 1);
    // Этот узел больше не трогаем.
    loaded.inner.mediaTick();
    assert.equal(buttonOf(nodes.video), null);
  }
  // Нашёл — кнопка остаётся.
  const { loaded, nodes } = page({ build: nodes => { nodes.video = video(nodes.box, { path: "" }); } });
  loaded.inner.mediaTick();
  await flush();
  click(loaded, buttonOf(nodes.video));
  await flush();
  assert.ok(buttonOf(nodes.video));
  assert.equal(status(loaded).given, 0);
});

test("12п⁵: адрес нажатия с местом панели — `dock=1` и место, как у клика по файлу", () => {
  const { loaded } = page();
  const dock = { x: 0, y: 50, w: 358, h: 692, wx: 0, wy: 29, ww: 1280, wh: 742 };
  assert.equal(loaded.inner.mediaOpenUrl({ name: "a b.mp4", path: "" }, CHAT, dock),
    `http://127.0.0.1:47615/open-html?mode=click&dock=1&name=a%20b.mp4&chat=${CHAT}&x=0&y=50&w=358&h=692&wx=0&wy=29&ww=1280&wh=742`);
  assert.equal(loaded.inner.mediaOpenUrl({ name: "pizza-v2-nik.mp4", path: VIDEO }, CHAT, dock),
    `http://127.0.0.1:47615/open-html?mode=click&dock=1&path=${encodeURIComponent(VIDEO)}&chat=${CHAT}&x=0&y=50&w=358&h=692&wx=0&wy=29&ww=1280&wh=742`);
});

test("12п⁵: виртуальная лента — узел ушёл, кнопка тоже; тот же файл — кадр из кэша; другой файл в том же узле — заново", async () => {
  const { loaded, nodes } = page();
  loaded.inner.mediaTick();
  await flush();
  const first = buttonOf(nodes.video);
  nodes.video.remove();
  loaded.inner.mediaTick();
  assert.equal(first.isConnected, false, "кнопка ушедшего ролика осталась");
  const again = video(nodes.box);
  loaded.inner.mediaTick();
  assert.ok(buttonOf(again), "кадр не вернулся из кэша");
  assert.equal(asked(loaded, "/media-thumb?").length, 1, "за тем же файлом сходили второй раз");
  // React отдал узел другому ролику.
  again.setAttribute("title", "drugoy.mov");
  again.__reactFiber$test.return.return.memoizedProps = { path: `${DIR}/drugoy.mov`, surface: "attachment" };
  loaded.inner.mediaTick();
  assert.equal(again.getAttribute(HIDDEN), null, "чужой кадр на месте другого ролика");
  assert.equal(asked(loaded, "/media-thumb?").length, 2);
  await flush();
  assert.equal(buttonOf(again).getAttribute("title"), "drugoy.mov");
  assert.equal(loaded.document.querySelectorAll(`[${PLAY}]`).length, 1, "сироты кнопок");
});

test("12п⁵: картинка-вложение — с диска: blob: вместо src, srcset снят; ошибка — исходный адрес; чужие байты — как было", async () => {
  const { loaded, nodes } = page({ build: nodes => { nodes.img = photo(nodes.box); } });
  const src = nodes.img.getAttribute("src");
  const srcset = nodes.img.getAttribute("srcset");
  loaded.inner.mediaTick();
  assert.deepEqual(asked(loaded, "/media-file?"), [
    `http://127.0.0.1:47615/media-file?chat=${CHAT}&name=paket-a-25-10.png&path=${encodeURIComponent(PHOTO)}`,
  ]);
  await flush();
  assert.equal(nodes.img.getAttribute("src"), "blob:https://claude.ai/1");
  assert.equal(nodes.img.getAttribute("srcset"), null, "srcset перебил бы src на ретине");
  assert.equal(nodes.img.getAttribute(HIDDEN), "file");
  assert.equal(loaded.blobs[0].type, "image/png");
  assert.equal(status(loaded).images, 1);
  loaded.inner.mediaTick();
  assert.equal(asked(loaded, "/media-file?").length, 1);
  // Не загрузилась — исходный адрес Claude, узел больше не трогаем.
  loaded.document.dispatchEvent({ type: "error", target: nodes.img });
  assert.equal(nodes.img.getAttribute("src"), src);
  assert.equal(nodes.img.getAttribute("srcset"), srcset);
  assert.equal(nodes.img.getAttribute(HIDDEN), "claude");
  loaded.inner.mediaTick();
  assert.equal(nodes.img.getAttribute("src"), src);
  // Ответ не картинка — как было.
  const other = page({ build: nodes => { nodes.img = photo(nodes.box); }, reply: () => bytes(new TextEncoder().encode("<html>")) });
  other.loaded.inner.mediaTick();
  await flush();
  assert.equal(other.nodes.img.getAttribute("src"), src);
  assert.equal(other.nodes.img.getAttribute(HIDDEN), null);
  // Без Blob в странице — data: (тот же разбор байтов).
  const plainPage = page({ build: nodes => { nodes.img = photo(nodes.box); }, blobs: false });
  plainPage.loaded.inner.mediaTick();
  await flush();
  assert.equal(plainPage.nodes.img.getAttribute("src"), `data:image/png;base64,${Buffer.from(PNG).toString("base64")}`);
});

test("12п⁵: dispose — плеер Claude, исходные адреса картинок, своих кнопок нет, blob: отпущены", async () => {
  const { loaded, nodes } = page({ build: nodes => { nodes.video = video(nodes.box); nodes.img = photo(nodes.box); } });
  const src = nodes.img.getAttribute("src");
  loaded.inner.mediaTick();
  await flush();
  assert.ok(buttonOf(nodes.video));
  assert.equal(nodes.img.getAttribute(HIDDEN), "file");
  loaded.api.dispose();
  assert.equal(buttonOf(nodes.video), null);
  assert.equal(nodes.video.getAttribute(HIDDEN), null);
  assert.equal(nodes.img.getAttribute("src"), src);
  assert.equal(nodes.img.getAttribute(HIDDEN), null);
  assert.equal(loaded.document.querySelectorAll(`[${PLAY}]`).length, 0);
  assert.deepEqual([...loaded.revoked].sort(), ["blob:https://claude.ai/1", "blob:https://claude.ai/2"]);
});
