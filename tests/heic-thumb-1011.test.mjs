// page-70, раздел 12м⁴ inject.js: превью HEIC во вложениях чата (контракт К-TH).
// Слово Элвиса 11.10 06:36: «Хэйки эти превьюшки отображаются. Можно сделать как-нибудь?.. отображались
// нормально, чтобы можно было смотреть, открывать тоже».
//
// Что проверяется:
//   1) плитка .HEIC реплики: путь из пропсов волокна (своё имя среди общих пропсов), запрос
//      `GET /thumb?path&chat` на порт приложения, пришёл JPEG — в плитке картинка data:, метка on;
//   2) пока ответа нет, ответ не JPEG, приложения нет — плитка как была; повтора подряд нет;
//   3) не HEIC, плитка поля ввода, чат неизвестен — запроса нет;
//   4) плитка пришла заново (виртуальная лента) — картинка из кэша без нового запроса; узел достался
//      другому файлу — картинка снята; dispose убирает своё; status().heic.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_heic-1011";
const ON = "data-myclaude-heic";
const IMG = "data-myclaude-heic-img";
const A = "/Users/demo/Downloads/IMG_0506.HEIC";
const B = "/Users/demo/Downloads/IMG_0507.HEIC";
const PDF = "/Users/demo/Downloads/arhiv.zip"; // не фото и не страница — превью нет (с #10229 PDF его получает)
const JPEG = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A]);
const wait = () => new Promise(resolve => setImmediate(resolve));
const settle = async () => { for (let i = 0; i < 4; i += 1) await wait(); };

// Плитка, как её кладёт Claude: имя в тексте, пути всех вложений реплики — в пропсах компонента над ней.
const tile = (parent, path, all) => {
  const node = parent.add("div", { attrs: { "data-cds": "MessageAttachmentsFile" } });
  node.add("div").add("p", { text: path.split("/").pop() });
  node.__reactFiber$test = { memoizedProps: { children: [] },
    return: { memoizedProps: { attachments: all.map(item => ({ name: item.split("/").pop(), path: item })) }, return: null } };
  return node;
};

const page = ({ href = `https://claude.ai/epitaxy/${CHAT}`, reply = () => ({ ok: true, arrayBuffer: async () => JPEG.buffer }) } = {}) => {
  const nodes = {};
  const loaded = loadInject({
    href, title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    geometry: { frame: [0, 0, 640, 900] },
    html: dom => {
      const parts = dom.composer({});
      const panel = dom.document.body.add("div", { attrs: { class: "epitaxy-chat-panel" } });
      const feed = panel.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      nodes.row = feed.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "human" } });
      nodes.a = tile(nodes.row, A, [A, B, PDF]);
      nodes.b = tile(nodes.row, B, [A, B, PDF]);
      nodes.pdf = tile(nodes.row, PDF, [A, B, PDF]);
      const draft = panel.add("div", { attrs: { "data-cds-composer-attachments": "" } });
      nodes.draft = tile(draft, A, [A]);
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.win.fetch = address => { loaded.calls.push(String(address)); return Promise.resolve().then(() => reply(String(address))); };
  return { loaded, nodes };
};
const imgOf = node => [...node.childNodes].find(kid => kid.nodeType === 1 && kid.hasAttribute(IMG)) ?? null;
const thumbs = loaded => loaded.calls.filter(item => item.includes("/thumb?"));

test("12м⁴: плитка .HEIC получает картинку от приложения; архив не тронут, плитка поля ввода — миниатюрой (#10345)", async () => {
  const { loaded, nodes } = page();
  loaded.inner.heicTick();
  assert.deepEqual(thumbs(loaded), [
    `http://127.0.0.1:47615/thumb?path=${encodeURIComponent(A)}&chat=${CHAT}`,
    `http://127.0.0.1:47615/thumb?path=${encodeURIComponent(B)}&chat=${CHAT}`,
  ], "запрос — на каждое фото HEIC ленты, со своим путём");
  assert.equal(nodes.a.getAttribute(ON), null, "метка до ответа приложения — плашка с именем пропала бы");
  await settle();
  for (const [node, path] of [[nodes.a, A], [nodes.b, B]]) {
    const img = imgOf(node);
    assert.ok(img, `нет картинки: ${path}`);
    assert.equal(img.tagName, "IMG");
    assert.equal(img.getAttribute("src"), `data:image/jpeg;base64,${Buffer.from(JPEG).toString("base64")}`);
    assert.equal(img.getAttribute("title"), path.split("/").pop(), "имя файла — в подсказке");
    assert.equal(node.getAttribute(ON), "on");
    assert.equal(node.childNodes[node.childNodes.length - 1], img, "картинка не последним узлом — порядок содержимого плитки задет");
  }
  assert.equal(imgOf(nodes.pdf), null);
  assert.equal(nodes.pdf.getAttribute(ON), null);
  // #10345: плитка поля — тот же снимок из кэша (запроса сверх двух нет), первым узлом под крестиком.
  assert.equal(nodes.draft.getAttribute(ON), "field");
  assert.equal(nodes.draft.childNodes[0], imgOf(nodes.draft), "снимок в поле не первым узлом — закроет крестик");
  // Повторные проходы ничего не шлют и вторую картинку не кладут.
  loaded.inner.heicTick();
  loaded.inner.heicTick();
  assert.equal(thumbs(loaded).length, 2);
  assert.equal(nodes.a.querySelectorAll(`[${IMG}]`).length, 1);
  assert.deepEqual(plain(loaded.api.status().heic), { shown: 3, asked: 2, failed: 0, cached: 2, cards: 0 });
  // Правила вида: фото вместо плашки только у плитки с меткой.
  const css = [...loaded.inner.RULES].join("\n");
  assert.match(css, /\[data-myclaude-heic="on"\]>:not\(\[data-myclaude-heic-img\]\)\{display:none !important\}/);
  assert.match(css, /\[data-myclaude-heic="on"\]>\[data-myclaude-heic-img\]\{[^}]*height:120px !important/);
});

test("12м⁴: ответа нет, ответ не картинка, приложения нет — плитка остаётся плашкой, запрос не повторяется подряд", async () => {
  const replies = [
    () => ({ ok: false, status: 404 }),
    () => ({ ok: true, arrayBuffer: async () => new TextEncoder().encode("<html>").buffer }),
    () => { throw new TypeError("Failed to fetch"); },
  ];
  for (const reply of replies) {
    const { loaded, nodes } = page({ reply });
    loaded.inner.heicTick();
    await settle();
    loaded.inner.heicTick();
    assert.equal(imgOf(nodes.a), null);
    assert.equal(nodes.a.getAttribute(ON), null);
    assert.equal(thumbs(loaded).length, 2, "повтор сразу после отказа");
    assert.equal(loaded.api.status().heic.failed, 2);
  }
});

test("12м⁴: чат неизвестен — запроса нет", async () => {
  const { loaded, nodes } = page({ href: "https://claude.ai/new" });
  loaded.inner.heicTick();
  await settle();
  assert.deepEqual(thumbs(loaded), []);
  assert.equal(imgOf(nodes.a), null);
});

test("12м⁴: плитка пришла заново — картинка из кэша; узел достался другому файлу — снята; dispose убирает своё", async () => {
  const { loaded, nodes } = page();
  loaded.inner.heicTick();
  await settle();
  // Виртуальная лента: узел ушёл и пришёл новый с тем же файлом.
  nodes.a.remove();
  const again = tile(nodes.row, A, [A, B, PDF]);
  loaded.inner.heicTick();
  assert.ok(imgOf(again), "картинка не вернулась из кэша");
  assert.equal(thumbs(loaded).length, 2, "за тем же файлом сходили второй раз");
  // Узел с картинкой достался не фото: текст и пропсы сменились.
  nodes.b.childNodes[0].childNodes[0].textContent = "arhiv.zip";
  nodes.b.__reactFiber$test.return.memoizedProps = { attachments: [{ name: "arhiv.zip", path: PDF }] };
  loaded.inner.heicTick();
  assert.equal(imgOf(nodes.b), null, "чужая картинка осталась в плитке");
  assert.equal(nodes.b.getAttribute(ON), null);
  loaded.api.dispose();
  assert.equal(imgOf(again), null);
  assert.equal(again.getAttribute(ON), null);
});

test("12м⁴: путь — строкой path, computer:// и file://; чужое имя и не-HEIC путём не становятся", () => {
  const { loaded, nodes } = page();
  const find = props => {
    nodes.a.__reactFiber$test.return.memoizedProps = props;
    return loaded.inner.heicPathOf(nodes.a);
  };
  assert.equal(find({ path: A }), A);
  assert.equal(find({ file: { absPath: `computer://${A}` } }), A);
  assert.equal(find({ file: { url: `file://${encodeURI(A)}` } }), A);
  assert.equal(find({ path: B }), null, "имя другого файла");
  assert.equal(find({ path: "IMG_0506.HEIC" }), null, "путь не абсолютный");
  assert.equal(find({ path: "/Users/demo/Downloads/IMG_0506.HEIC.txt" }), null);
  assert.equal(loaded.inner.heicBase64(new Uint8Array([1, 2, 3, 4, 5])), Buffer.from([1, 2, 3, 4, 5]).toString("base64"));
});

test("12м⁴ (#10254, #10229): JPG плиткой файла — фото; HTML — карточка: снимок над плашкой, мышь — плашке", async () => {
  const JPG = "/Users/demo/Rick/docs/shot.jpg";
  const HTML = "/Users/demo/Rick/docs/81-plan.html";
  const { loaded, nodes } = page();
  const row = nodes.row.parentNode.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant" } });
  const jpg = tile(row, JPG, [JPG, HTML]);
  const html = tile(row, HTML, [JPG, HTML]);
  loaded.inner.heicTick();
  assert.ok(thumbs(loaded).some(item => item.includes(encodeURIComponent(HTML))), "за снимком HTML не сходили");
  await settle();
  assert.equal(jpg.getAttribute(ON), "on", "JPG — фото, как HEIC");
  assert.equal(html.getAttribute(ON), "doc", "HTML — карточка");
  assert.ok(imgOf(html));
  assert.equal(imgOf(html).getAttribute("title"), "81-plan.html");
  const css = [...loaded.inner.RULES].join("\n");
  assert.match(css, /\[data-myclaude-heic="doc"\]>\[data-myclaude-heic-img\]\{[^}]*pointer-events:none/, "снимок забирал бы нажатие у плашки");
  assert.doesNotMatch(css, /\[data-myclaude-heic="doc"\]>:not/, "плашку Claude в карточке прятать нельзя — пропали бы нажатие и меню");
});

// #10383: фото, присланное SendUserFile (карточка button[title=<путь>] в ряду ленты), — миниатюра поверх
// плитки; карточка со своей <img> не тронута; HTML/PDF с #10603 — снимок верха страницы.
test("#10383: карточка SendUserFile с фото без картинки получает миниатюру, PDF (#10603) — тоже; своя <img> — нет", async () => {
  const P = "/Users/demo/Risovalka/out/01-banner.webp";
  const OWN = "/Users/demo/Risovalka/out/02-post.png";
  const DOC = "/Users/demo/Risovalka/out/list.pdf";
  const nodes = {};
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    geometry: { frame: [0, 0, 640, 900] },
    html: dom => {
      const parts = dom.composer({});
      const panel = dom.document.body.add("div", { attrs: { class: "epitaxy-chat-panel" } });
      const row = panel.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } }).add("div", { attrs: { "data-testid": "transcript-row" } });
      nodes.card = row.add("button", { attrs: { type: "button", title: P } });
      nodes.card.add("div").add("span", { text: "01-banner.webp" });
      nodes.own = row.add("button", { attrs: { type: "button", title: OWN } });
      nodes.own.add("img", { attrs: { src: "data:image/png;base64,AA" } });
      nodes.doc = row.add("button", { attrs: { type: "button", title: DOC } });
      nodes.docSquare = nodes.doc.add("div", { rect: { left: 0, top: 0, width: 120, height: 120 } });
      // Кнопка с путём без квадрата (заголовок инструмента) — не карточка файла (#10603).
      nodes.tool = row.add("button", { attrs: { type: "button", title: "/Users/demo/Risovalka/out/65.html" } });
      nodes.tool.add("span", { text: "Write 65.html" });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.win.fetch = address => { loaded.calls.push(String(address)); return Promise.resolve({ ok: true, arrayBuffer: async () => JPEG.buffer }); };
  loaded.inner.heicTick();
  // С #10603 PDF в квадрате тоже просит снимок (верх страницы); кнопка без квадрата — нет.
  assert.deepEqual(thumbs(loaded), [P, DOC].map(item => `http://127.0.0.1:47615/thumb?path=${encodeURIComponent(item)}&chat=${CHAT}`));
  await settle();
  const marked = [nodes.card, ...nodes.card.querySelectorAll("*")].find(node => node.getAttribute?.(ON) === "card");
  assert.ok(marked, "карточка не помечена");
  assert.ok(imgOf(marked), "миниатюры в карточке нет");
  assert.equal(nodes.own.querySelector(`[${IMG}]`), null);
  assert.equal(nodes.docSquare.getAttribute(ON), "card-doc", "#10603: PDF — снимок верха в квадрате");
  assert.equal(nodes.tool.getAttribute(ON), null, "кнопка с путём без квадрата стала карточкой");
  loaded.api.dispose();
  assert.equal(nodes.card.querySelector(`[${IMG}]`), null, "dispose не убрал миниатюру");
});

test("12м⁴ (#10345): плитка поля с путём, обрезанным серединой, узнаёт свой файл", () => {
  const { loaded, nodes } = page();
  nodes.draft.childNodes[0].childNodes[0].textContent = "/Users/demo/Do…HEIC";
  assert.equal(loaded.inner.heicPathOf(nodes.draft, true), A);
  assert.equal(loaded.inner.heicPathOf(nodes.draft), null, "плитка ленты без расширения в тексте — не фото");
  nodes.draft.childNodes[0].childNodes[0].textContent = "/Users/x/y…HEIC";
  assert.equal(loaded.inner.heicPathOf(nodes.draft, true), null, "чужое начало пути принято");
  const css = [...loaded.inner.RULES].join("\n");
  assert.match(css, /\[data-myclaude-heic\^="field"\]>\[data-myclaude-heic-img\]\{position:absolute !important;inset:0;z-index:-1/);
});
