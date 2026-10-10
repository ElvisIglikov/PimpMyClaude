// WF97, батч Б3 (страница, раздел 12п inject.js; #7724): кнопка «▦ Галерея» в
// чате. Слово Элвиса 26.09: «в правом углу под кнопкой Enter должна быть кнопка
// „Галерея“. Нажимаешь, и то окошко фильтруется сразу же… по артефактам
// текущего чата… и там могу снять фильтр, и здесь… они должны жениться».
//
// Волна 2 (слово Элвиса 26.09 ~04:23): «не справа, а слева… правее „+ Auto“
// (левее Opus 5.5); если в чате нет артефактов — кнопки нет… кнопку осветить».
//
// Контракт (план WF97, К-V1, К-V2, К-V7):
//   1) открытое поле — кнопка сразу правее левой группы «+ Auto» нижней строки,
//      группе дано поле справа под неё; узкое окно — «▦ N»;
//   1а) viewer-counts: нет файлов у чата — кнопки нет; есть — «▦ Галерея N»;
//      есть непросмотренные — светится (data-fresh);
//   2) свёрнутое поле — значком левее микрофона у кружка (нет его — левее кружка);
//   3) id чата неизвестен — кнопки нет;
//   4) нажатие — GET /viewer?chat=<id>&on=1|0 на 127.0.0.1:47615, горит сразу;
//   5) viewer-chat: свой чат — горит, чужой и null — гаснет.
// 12д (&chat= в open-html) — в html-chrome.test.mjs.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const GALLERY = "#myclaude-gallery";
const ROOM = "data-myclaude-gallery-room";
const MIC = "#myclaude-mic";
const CHIN = { left: 92, top: 744, width: 1016, height: 28 };
// Нижняя строка по живому замеру 26.09: flex-ряд, слева группа «+ Auto», справа
// (ms-auto) модель, эффорт и кружок.
const LEFT = { left: 100, top: 750, width: 60, height: 16 };
const RING = { left: 1100, top: 748, width: 20, height: 20 };
const CHAT = "local_aaaa-1111";

let seq = 0;
const counts = (loaded, chats) => {
  loaded.dom.command({ id: `c-${seq += 1}`, action: "viewer-counts", at: "now", scope: "all", chats });
  settle(loaded);
};
const page = ({ href = `https://claude.ai/epitaxy/${CHAT}`, viewport, mic = null, files = [3, 0], model = true } = {}) => {
  const loaded = loadInject({
    title: "Trelvis", href, ...(viewport ? { geometry: { viewport } } : {}),
    html: dom => {
      const parts = dom.composer({ top: 600 });
      parts.chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: CHIN });
      const row = parts.chin.add("div", { class: "flex items-center", rect: { left: 100, top: 748, width: 1000, height: 20 } });
      parts.left = row.add("div", { class: "flex items-center self-start", rect: LEFT });
      parts.left.add("button", { attrs: { "aria-label": "Add" }, rect: { left: 100, top: 750, width: 20, height: 16 } });
      parts.left.add("button", { text: "Auto", rect: { left: 120, top: 750, width: 40, height: 16 } });
      const right = row.add("div", { class: "ms-auto flex items-center", rect: { left: 1000, top: 748, width: 120, height: 20 } });
      const grid = right.add("div", { class: "grid", rect: { left: 1000, top: 748, width: 120, height: 20 } });
      if (model) {
        grid.add("button", {
          attrs: { "data-testid": "epitaxy-cds-model-selector", "aria-label": "Model: Opus 5.5" }, text: "Opus 5.5",
          rect: { left: 1000, top: 750, width: 60, height: 16 },
        });
      }
      parts.ring = grid.add("button", {
        attrs: { "aria-haspopup": "dialog", "aria-label": "Usage: Context 300k / 1M (30%)" }, rect: RING,
      });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  // Число у кнопки PMP (WF213) — редкий запрос /digest: к «Галерее» он не относится.
  loaded.win.fetch = url => { if (!String(url).endsWith("/digest")) loaded.calls.push(url); return Promise.resolve({}); };
  if (mic) loaded.dom.command({ id: `m-${mic}`, action: "mic", at: "now", scope: "all", mode: mic });
  if (files) counts(loaded, { [CHAT]: files });
  settle(loaded);
  return loaded;
};
const settle = loaded => {
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
};
const node = loaded => loaded.dom.query(GALLERY);
const gallery = loaded => plain(loaded.api.status().gallery);
const px = (item, name) => Number(String(item.style.getPropertyValue(name)).replace("px", ""));
const collapse = loaded => { loaded.api.setStage(loaded.api.stages.COLLAPSED); settle(loaded); };
const press = loaded => node(loaded).dispatchEvent({ type: "click" });
const viewer = (loaded, chat) => loaded.dom.command({ id: `v-${seq += 1}`, action: "viewer-chat", at: "now", scope: "all", chat });

test("#7724: открытое поле — «Галерея 3» сразу правее «+ Auto», группе дано место справа", () => {
  const loaded = page();
  const item = node(loaded);
  assert.equal(item.style.getPropertyValue("display"), "flex");
  assert.equal(px(item, "left"), LEFT.left + LEFT.width + 6, "не сразу правее левой группы «+ Auto»");
  assert.equal(px(item, "top") + 10, LEFT.top + LEFT.height / 2, "не по середине строки");
  assert.equal(px(item, "width"), 20 + 6, "ширина — значок и одна цифра (WF103, #7965: без слова)");
  assert.deepEqual([gallery(loaded).visible, gallery(loaded).spot, gallery(loaded).compact], [true, "field", false]);
  // С WF213 кнопка PMP — в каждом чате главного окна: место — на «Галерею» и на неё (6 + 26 + 6 + 24 + 6).
  assert.equal(loaded.parts.left.getAttribute(ROOM), "68px", "левой группе не дали места под кнопки");
  assert.equal(loaded.parts.left.style.getPropertyValue("--myclaude-gallery-room"), "68px");
  assert.equal(loaded.parts.chin.hasAttribute(ROOM), false, "у правого края места больше не берём");
  assert.equal(item.textContent.trim(), "3", "WF103 (#7965): только значок и число");
  const css = loaded.dom.queryAll("style").map(style => style.textContent).join("\n");
  assert.match(css, /\[data-cds="ChatComposerChin"\] \[data-myclaude-gallery-room\]\{margin-inline-end:var\(--myclaude-gallery-room,0px\) !important;/);
});

test("#7724: узкое окно — «▦ N», места у группы меньше", () => {
  const loaded = page({ viewport: { width: 340, height: 800 } });
  assert.deepEqual([gallery(loaded).visible, gallery(loaded).compact], [true, true]);
  assert.equal(node(loaded).dataset.compact, "true");
  assert.equal(px(node(loaded), "width"), 20 + 6);
  assert.equal(loaded.parts.left.getAttribute(ROOM), "68px");
});

test("#7724: viewer-counts — нет файлов у чата, кнопки нет; есть — видна с числом", () => {
  const loaded = page({ files: null });
  assert.equal(gallery(loaded).visible, false, "чисел ещё нет — кнопки нет");
  assert.equal(loaded.parts.left.getAttribute(ROOM), "36px", "без «Галереи» место — только под кнопку PMP (WF213)");
  counts(loaded, { "local_bbbb-2222": [5, 1] });
  assert.equal(gallery(loaded).visible, false, "файлы есть у чужого чата");
  counts(loaded, { [CHAT]: [12, 0] });
  assert.deepEqual([gallery(loaded).visible, gallery(loaded).files, gallery(loaded).counted], [true, 12, 2]);
  assert.equal(node(loaded).textContent.trim(), "12");
  assert.equal(px(node(loaded), "width"), 20 + 12, "две цифры — шире");
  counts(loaded, {});
  assert.equal(gallery(loaded).visible, false, "файлов не стало — кнопка ушла");
  assert.equal(loaded.parts.left.getAttribute(ROOM), "36px");
});

test("#7724: непросмотренные — кнопка светится, нет — спокойная", () => {
  const loaded = page({ files: [4, 2] });
  assert.deepEqual([gallery(loaded).fresh, gallery(loaded).unseen], [true, 2]);
  assert.equal(node(loaded).dataset.fresh, "true");
  counts(loaded, { [CHAT]: [4, 0] });
  assert.equal(node(loaded).dataset.fresh, "false");
  const css = loaded.dom.queryAll("style").map(style => style.textContent).join("\n");
  // WF106 (#8099): непросмотренные — не ярко-жёлтым, а цветом текста окна с
  // маленькой точкой-акцентом.
  assert.match(css, /#myclaude-gallery\[data-fresh="true"\][^{]*\{[^}]*color:inherit/, "WF106 (#8099): непросмотренные — цветом текста окна");
  assert.match(css, /#myclaude-gallery\[data-fresh="true"\]::after\{[^}]*width:4px;height:4px;border-radius:50%/, "у свежих нет точки-акцента");
  assert.ok(!/#f59e0b/.test(css.split("\n").filter(line => line.includes("#myclaude-gallery")).join("\n")), "ярко-жёлтый у «Галереи» остался");
});

test("#7724: viewer-counts доходит и в окно без поля ввода", () => {
  const bare = loadInject({ href: `https://claude.ai/epitaxy/${CHAT}` });
  bare.dom.command({ id: "c-bare", action: "viewer-counts", at: "now", scope: "all", chats: { [CHAT]: [2, 1] } });
  assert.deepEqual([bare.api.status().gallery.counted, bare.api.status().gallery.files], [1, 2]);
});

test("#7724: строка без кнопки модели — места не найти, кнопки нет", () => {
  const loaded = page({ model: false });
  assert.equal(gallery(loaded).visible, false);
  assert.equal(loaded.parts.left.hasAttribute(ROOM), false);
});

test("#7724: свёрнутое поле — «▦ N» левее кружка; место в строке снято", () => {
  const loaded = page();
  collapse(loaded);
  const item = node(loaded);
  assert.deepEqual([gallery(loaded).spot, gallery(loaded).compact], ["ring", true]);
  assert.equal(loaded.dom.query(MIC).style.getPropertyValue("display"), "none", "стенд: микрофона нет");
  assert.equal(px(item, "left"), RING.left - 6 - 24 - 6 - 26, "не левее кружка и кнопки PMP (WF213)");
  assert.equal(px(item, "top") + 10, RING.top + RING.height / 2, "не по середине кружка");
  assert.equal(loaded.parts.left.hasAttribute(ROOM), false);
});

test("#7724: свёрнутое поле с микрофоном — «Галерея» левее микрофона", () => {
  const loaded = page({ mic: "dictator" });
  collapse(loaded);
  const mic = loaded.dom.query(MIC);
  assert.equal(mic.dataset.spot, "ring");
  assert.equal(px(node(loaded), "left"), px(mic, "left") - 6 - 24 - 6 - 26, "не левее микрофона и кнопки PMP (WF213)");
});

test("#7724: id чата неизвестен — кнопки нет", () => {
  const loaded = page({ href: "https://claude.ai/epitaxy" });
  assert.equal(node(loaded).style.getPropertyValue("display"), "none");
  assert.equal(gallery(loaded).visible, false);
  assert.equal(loaded.parts.left.hasAttribute(ROOM), false);
  press(loaded);
  assert.deepEqual(loaded.calls, [], "без чата запроса нет");
});

test("#7724: нажатие — запрос /viewer on=1, горит сразу; второе — on=0, гаснет", () => {
  const loaded = page();
  press(loaded);
  assert.deepEqual(loaded.calls, [`http://127.0.0.1:47615/viewer?chat=${CHAT}&on=1`]);
  assert.equal(gallery(loaded).on, true);
  assert.equal(node(loaded).dataset.on, "true");
  press(loaded);
  assert.equal(loaded.calls[1], `http://127.0.0.1:47615/viewer?chat=${CHAT}&on=0`);
  assert.deepEqual([gallery(loaded).on, gallery(loaded).clicks], [false, 2]);
  assert.equal(node(loaded).dataset.on, "false");
});

test("#7724: viewer-chat — свой чат зажигает, чужой и null гасят", () => {
  const loaded = page();
  viewer(loaded, CHAT);
  assert.equal(gallery(loaded).on, true, "свой чат в фильтре — кнопка горит");
  assert.equal(node(loaded).dataset.on, "true");
  viewer(loaded, "local_bbbb-2222");
  assert.equal(gallery(loaded).on, false, "чужой чат — гаснет");
  viewer(loaded, CHAT);
  viewer(loaded, null);
  assert.equal(gallery(loaded).on, false, "фильтр снят в Viewer — гаснет");
  assert.equal(gallery(loaded).heard, 4);
  assert.deepEqual(loaded.calls, [], "команда Viewer сама запросов не шлёт");
});

test("#7724: viewer-chat доходит и в свёрнутом поле, и в окне без поля ввода", () => {
  const loaded = page();
  collapse(loaded);
  viewer(loaded, CHAT);
  assert.equal(gallery(loaded).on, true);
  const bare = loadInject({ href: `https://claude.ai/epitaxy/${CHAT}` });
  bare.dom.command({ id: "v-bare", action: "viewer-chat", at: "now", scope: "all", chat: CHAT });
  assert.equal(bare.api.status().gallery.heard, 1, "команда умерла на проверке поля ввода");
});

test("#7724: нажатие гасит горящую от Viewer кнопку — on=0", () => {
  const loaded = page();
  viewer(loaded, CHAT);
  press(loaded);
  assert.equal(loaded.calls[0], `http://127.0.0.1:47615/viewer?chat=${CHAT}&on=0`);
  assert.equal(gallery(loaded).on, false);
});

test("#7724: dispose() уносит кнопку и место в строке", () => {
  const loaded = page();
  assert.equal(loaded.parts.left.hasAttribute(ROOM), true);
  loaded.api.dispose();
  assert.equal(node(loaded), null);
  assert.equal(loaded.parts.left.hasAttribute(ROOM), false);
  assert.equal(loaded.parts.left.style.getPropertyValue("--myclaude-gallery-room"), "");
});

test('F13: ordinary chats probe reports gallery counts generation; reload resets it', async () => {
  const loaded = loadInject({ href: `https://claude.ai/epitaxy/${CHAT}`, html: 'composer' });
  assert.equal((await loaded.api.chats({ scan: false })).galleryCounted, 0);
  loaded.dom.command({ id: 'f13-count', action: 'viewer-counts', chats: { [CHAT]: [2, 1] } });
  assert.equal((await loaded.api.chats({ scan: false })).galleryCounted, 1);
  assert.equal(loaded.reload().error, null);
  assert.equal((await loaded.api.chats({ scan: false })).galleryCounted, 0);
  loaded.api.dispose();
});
