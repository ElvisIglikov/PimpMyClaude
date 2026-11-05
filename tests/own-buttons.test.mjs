// #10527 (слово Элвиса 22.10 02:12: «То кнопка какая-нибудь отвалится…»): каждая наша кнопка нажимается и делает
// своё. Один параметризованный тест по таблице: строка на каждый наш узел из списка OWN страницы (HEALTH_PAGE.own,
// раздел 18 — id из раздела 1 и разделов фич) и на узлы Claude, которым мы даём своё нажатие (карточка файла,
// кнопка отправки под отсчётом). Нажатие — как мышью: pointerdown, mousedown, pointerup, mouseup, click сперва
// захватом document (там слушают перехватчики страницы), потом самому узлу, в центр его рамки.
//
// Новая кнопка без строки — красный тест: список берётся из страницы (OWN), и любой узел с id myclaude-…,
// появившийся в сценах, обязан быть в OWN (или в NOT_OWN с причиной).
//
// Строка таблицы: press — нажать и проверить действие; layer — узел без нажатий (почему); elsewhere — контейнер
// или кнопка со своей долгой сценой, её нажатие проверяет названный набор (сцена там своя, здесь не дублируем).
import test from "node:test";
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { loadInject, plain } from "./load.mjs";
import { claudeWindow, ownRects, pointHits, settle, wideByCss } from "./stands.mjs";

const CHAT = "local_5b0c7e2a-41d3-4f8e-9a6b-2c1d0e9f7a13";
const HTML = "/Users/dev/Projects/PimpMyClaude/docs/16.html";

const scene = ({ wide = true, card = false } = {}) => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Сторожи Пимпа",
    storage: { local: { "myclaude.mic": "dictator", "myclaude-send-delay-seconds": "5" } },
    geometry: { viewport: wide ? { width: 1200, height: 800 } : { width: 600, height: 800 } },
    html: dom => {
      const parts = claudeWindow(dom, { wide, card });
      // Карточка файла в ленте — как SendUserFile Claude: путь в пропсах волокна (раздел 12д¹).
      if (parts.card) parts.card["__reactFiber$test"] = { memoizedProps: { children: [] },
        return: { memoizedProps: { name: "16.html", size: 4096, path: HTML }, return: null } };
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.win.fetch = url => { loaded.calls.push(String(url)); return Promise.resolve({ ok: true, status: 204, text: () => Promise.resolve(""), json: () => Promise.resolve({}) }); };
  loaded.refresh = () => { wideByCss(loaded); settle(loaded); settle(loaded); ownRects(loaded.dom); pointHits(loaded.dom); };
  loaded.refresh();
  return loaded;
};
const status = loaded => plain(loaded.api.status());
const byId = (loaded, id) => loaded.document.getElementById(id);
const press = (loaded, node) => {
  assert.ok(node?.isConnected, "нажимать нечего — узла нет на странице");
  const box = node.getBoundingClientRect();
  for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) {
    const event = () => ({ type, target: node, isTrusted: true, bubbles: true, cancelable: true, button: 0,
      buttons: type.endsWith("down") ? 1 : 0, detail: 1, pointerId: 1, clientX: box.left + box.width / 2, clientY: box.top + box.height / 2 });
    if (loaded.document.dispatchEvent(event())) node.dispatchEvent(event());
  }
};
// Тяга рейки: захват у её кромки, ведём влево на 60 — колонка шире.
const drag = (loaded, node, dx) => {
  const box = node.getBoundingClientRect();
  const at = x => ({ button: 0, buttons: 1, pointerId: 1, clientX: x, clientY: box.top + 300, isTrusted: true });
  node.dispatchEvent({ type: "pointerdown", ...at(box.left + 5) });
  loaded.document.dispatchEvent({ type: "pointermove", ...at(box.left + 5 + dx) });
  loaded.document.dispatchEvent({ type: "pointerup", ...at(box.left + 5 + dx) });
};
// Отсчёт отправки: текст в поле и Enter — Claude не отправил, идут цифры поверх кнопки.
const counting = loaded => {
  loaded.parts.editor.__text = "привет";
  loaded.document.dispatchEvent({ type: "keydown", key: "Enter", code: "Enter", target: loaded.parts.editor, isTrusted: true, bubbles: true, cancelable: true });
  assert.equal(status(loaded).sendDelay.counting, true, "отсчёт не начался");
};

const COLLAPSED = 0;
const ROWS = {
  "myclaude-pmp": { press: {
    what: "открывает панель оркестрации страницы (12п³) и просит сводку у Пимпа",
    run: loaded => press(loaded, byId(loaded, "myclaude-pmp")),
    done: loaded => { assert.equal(status(loaded).pmp.open, true); assert.ok(loaded.calls.some(url => url.endsWith("/digest"))); },
  } },
  "myclaude-gallery": { press: {
    what: "просит галерею показать файлы этого чата (К-V1: /viewer?chat=…&on=1)",
    before: loaded => { loaded.dom.command({ id: "own-1", action: "viewer-counts", at: "now", scope: "all", chats: { [CHAT]: [3, 1] } }); loaded.refresh(); },
    run: loaded => press(loaded, byId(loaded, "myclaude-gallery")),
    done: loaded => assert.ok(loaded.calls.includes(`http://127.0.0.1:47615/viewer?chat=${CHAT}&on=1`), loaded.calls.join("\n")),
  } },
  "myclaude-mic": { press: {
    what: "включает диктовку (Диктатор) — значок горит",
    run: loaded => press(loaded, byId(loaded, "myclaude-mic")),
    done: loaded => { const mic = status(loaded).mic; assert.equal(mic.starts, 1); assert.equal(mic.dictating, true); assert.equal(mic.live, true); },
  } },
  "myclaude-input-handle": { scene: { wide: false }, press: {
    what: "одиночный клик по полоске — шаг ступени (обычное поле → свёрнутое)",
    run: loaded => { press(loaded, byId(loaded, "myclaude-input-handle")); loaded.dom.fireKind("timeout"); },
    done: loaded => assert.equal(status(loaded).stage, COLLAPSED),
  } },
  "myclaude-super-top": { scene: { wide: false }, press: {
    what: "дубль полоски у верхнего края — тот же шаг ступени сразу",
    run: loaded => press(loaded, byId(loaded, "myclaude-super-top")),
    done: loaded => assert.equal(status(loaded).stage, COLLAPSED),
  } },
  "myclaude-super-bottom": { scene: { wide: false }, press: {
    what: "дубль полоски у нижнего края — тот же шаг ступени",
    run: loaded => press(loaded, byId(loaded, "myclaude-super-bottom")),
    done: loaded => assert.equal(status(loaded).stage, COLLAPSED),
  } },
  "myclaude-side-rail": { press: {
    what: "тяга рейки влево расширяет колонку поля и запоминает ширину",
    run: loaded => drag(loaded, byId(loaded, "myclaude-side-rail"), -60),
    done: loaded => {
      assert.equal(loaded.parts.panel.style.getPropertyValue("--myclaude-side"), "448px");
      assert.equal(loaded.win.localStorage.getItem("myclaude-wide-side-v2"), "448");
    },
  } },
  "myclaude-send-delay-digits": { press: {
    what: "цифры отсчёта поверх кнопки отправки — нажатие отменяет отправку",
    before: counting,
    run: loaded => press(loaded, byId(loaded, "myclaude-send-delay-digits")),
    done: loaded => { const delay = status(loaded).sendDelay; assert.equal(delay.counting, false); assert.equal(delay.cancelled, 1); },
  } },
  "myclaude-corner": { elsewhere: "tests/corner-wf102.test.mjs", why: "имя проекта над New — меню проекта (WF197); справа вверху угол не показывается (#11676)" },
  "myclaude-send-delay": { elsewhere: "tests/send-delay-wf105.test.mjs", why: "плашка отсчёта холодного чата: нажатие — отмена" },
  "myclaude-send-delay-rocket": { elsewhere: "tests/send-look-wf188.test.mjs", why: "вид отсчёта «ракета»" },
  "myclaude-pmp-panel": { elsewhere: "tests/pmp-panel-wf213.test.mjs", why: "панель с командами — каждую жмёт свой набор" },
  "myclaude-progress-bar": { elsewhere: "tests/progress-card.test.mjs", why: "номера воркфлоу: нажатие открывает карточку (нужна строка состояния Workflow)" },
  "myclaude-progress-card": { elsewhere: "tests/progress-card-91.test.mjs", why: "карточка полосы Workflow" },
  "myclaude-read-next": { elsewhere: "tests/read-wf215.test.mjs", why: "«непрочитанные N» — к следующему непрочитанному" },
  "myclaude-remove-last-composer-image-v1": { elsewhere: "tests/composer-image-undo.test.mjs", why: "снять последнюю картинку поля" },
  "myclaude-ch-dim": { elsewhere: "tests/chapters-wf241.test.mjs", why: "затемнение под меню глав — нажатие закрывает" },
  "myclaude-ch-settings": { elsewhere: "tests/chapters-wf241.test.mjs", why: "настройка вида глав" },
  "myclaude-photo-view": { elsewhere: "tests/viewer-wf87.test.mjs", why: "просмотр фото: листание, закрытие" },
  "myclaude-run-confirm": { elsewhere: "tests/run-wf103.test.mjs", why: "подтверждение своей ▶" },
  "myclaude-pin-bulk": { elsewhere: "tests/pin-bulk.test.mjs", why: "закрепить чаты пачкой (над списком закреплённых)" },
  "myclaude-auto-allow-toast": { elsewhere: "tests/auto-allow.test.mjs", why: "плашка авто-Allow" },
  "myclaude-new-window-note": { elsewhere: "tests/new-window.test.mjs", why: "плашка отказа «Нового окна»" },
  // Панель материалов слева (WF277, #10644): кнопке и рейке нужны живой PimpViewer (ответ /dock) и место —
  // .dframe-pane-host, его в сцене claudeWindow нет; их нажатия — в своём наборе.
  "myclaude-dock-button": { elsewhere: "tests/materials-dock-wf277.test.mjs", why: "кнопка «PMP» у «Show sidebar»: on=1 / on=0" },
  "myclaude-dock-rail": { elsewhere: "tests/materials-dock-wf277.test.mjs", why: "рейка ширины панели материалов: тяга, двойной щелчок" },
  "myclaude-dock-sizes": { elsewhere: "tests/dock-size-wf282.test.mjs", why: "кнопки размера панели: узкая, «½», весь (#10759)" },
  "myclaude-progress-tip": { layer: "коробка карточки полосы, pointer-events: none" },
  "myclaude-progress-tail": { layer: "хвост полосы на свёрнутом поле, pointer-events: none" },
  "myclaude-main-drag": { layer: "полоса перетаскивания окна (app-region drag), нажатий нет" },
  "myclaude-mic-hint": { layer: "подсказка отказа Диктатора" },
  "myclaude-mode-hint": { layer: "подсказка режима над полем" },
  "myclaude-dim": { layer: "вуаль окна, pointer-events: none" },
  "myclaude-attn-frame": { layer: "рамка «ждут твоего слова», pointer-events: none" },
  "myclaude-composer-attachments-v1": { layer: "метка вложений поля для приложения (невидима)" },
  "myclaude-dock-place": { layer: "подложка места панели материалов под окном PimpViewer, нажатий нет" },
  "myclaude-dock-drag": { layer: "полоса перетаскивания окна над панелью материалов (app-region drag), нажатий нет" },
};
// Узлы Claude, которым мы даём своё нажатие.
const CLAUDE_ROWS = {
  fileCard: { scene: { card: true }, press: {
    what: "карточка файла в ленте открывается с ПЕРВОГО нажатия: запрос open-html?mode=click",
    run: loaded => press(loaded, loaded.parts.card),
    done: loaded => assert.ok(loaded.calls.some(url => url.startsWith(`http://127.0.0.1:47615/open-html?mode=click&path=${encodeURIComponent(HTML)}`)), loaded.calls.join("\n")),
  } },
  send: { press: {
    what: "кнопка отправки с текстом в поле — сперва отсчёт (Claude не отправил)",
    before: loaded => { loaded.parts.editor.__text = "привет"; },
    run: loaded => press(loaded, loaded.parts.send),
    done: loaded => assert.equal(status(loaded).sendDelay.counting, true),
  } },
};
// id myclaude-…, которые не наши кнопки: таблица стилей (её копирует попап Claude), метка на узле Claude, сироты.
const NOT_OWN = {
  "myclaude-input-handle-style": "наша таблица <style>",
  "myclaude-pic-style": "таблица подсветки упоминаний",
  "myclaude-image-undo-composer-v1": "наш id на рамке поля Claude (раздел 5¹), узел Claude",
};

const OWN = (() => { const loaded = scene(); return plain(loaded.inner.HEALTH_PAGE.own); })();

test("таблица кнопок полна: строка на каждый наш узел OWN, лишних строк нет", () => {
  assert.ok(OWN.length >= 20, "список OWN страницы пуст");
  const missing = OWN.filter(id => !(id in ROWS));
  assert.deepEqual(missing, [], "у новой кнопки нет строки в таблице — допиши, что она делает и как её нажать");
  assert.deepEqual(Object.keys(ROWS).filter(id => !OWN.includes(id)), [], "строка для узла, которого нет в OWN страницы");
  for (const [id, row] of Object.entries(ROWS)) {
    const kinds = ["press", "layer", "elsewhere"].filter(key => key in row);
    assert.equal(kinds.length, 1, `${id}: строка — ровно одно из press, layer, elsewhere`);
    if (row.elsewhere) assert.ok(existsSync(new URL(`../${row.elsewhere}`, import.meta.url)), `${id}: набора ${row.elsewhere} нет`);
  }
});

const pressRows = [
  ...Object.entries(ROWS).filter(([, row]) => row.press).map(([id, row]) => [`#${id}`, row]),
  ...Object.entries(CLAUDE_ROWS).map(([name, row]) => [`Claude ${name}`, row]),
];
const seen = new Set();
for (const [name, row] of pressRows) {
  test(`каждая наша кнопка нажимается и делает своё: ${name} — ${row.press.what}`, () => {
    const loaded = scene(row.scene ?? {});
    row.press.before?.(loaded);
    if (name.startsWith("#")) {
      const node = byId(loaded, name.slice(1));
      assert.ok(node?.isConnected, `${name}: узла нет на странице`);
      // Кнопку видно: страница её показала, и мышь в её центре попадает в неё (pointHits по рамкам).
      assert.notEqual(node.style.getPropertyValue("display"), "none", `${name}: страница её спрятала`);
    }
    row.press.run(loaded);
    row.press.done(loaded);
    for (const node of loaded.dom.queryAll('[id^="myclaude-"]')) seen.add(node.id);
  });
}

test("в сценах не появилось нашего узла вне OWN (новая кнопка обязана попасть в список и таблицу)", () => {
  assert.ok(seen.size > 10, "сцены не прогнались");
  const stray = [...seen].filter(id => !OWN.includes(id) && !(id in NOT_OWN));
  assert.deepEqual(stray, [], "наш узел, которого нет в OWN раздела 18");
});
