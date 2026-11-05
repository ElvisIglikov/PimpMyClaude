// #9631 (жалоба коллеги 10.10, ноут, 1.10.20): «внизу… кнопка с артефактами… в другом чате… нажимаю и ничего не
// открывается». Нажатие «Галереи» не молчит: приложение отвечает на /viewer словом исхода
// (ViewerClient.GalleryOutcome), страница говорит человеку плашкой, почему нет, и возвращает кнопку как была;
// opened/off — без плашки (видно и так), launching — «PimpViewer не запущен — открываю»; 204 без слова —
// старое приложение, молчим, как раньше; Пимп не ответил вовсе — тоже плашка.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_aaaa-1111";
const NOTE = "#myclaude-new-window-note";
const drain = async () => { for (let i = 0; i < 5; i += 1) await new Promise(resolve => setImmediate(resolve)); };

let seq = 0;
const page = reply => {
  const loaded = loadInject({
    title: "Trelvis", href: `https://claude.ai/epitaxy/${CHAT}`,
    html: dom => {
      const parts = dom.composer({ top: 600 });
      parts.chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: { left: 92, top: 744, width: 1016, height: 28 } });
      const row = parts.chin.add("div", { class: "flex items-center", rect: { left: 100, top: 748, width: 1000, height: 20 } });
      parts.left = row.add("div", { class: "flex items-center self-start", rect: { left: 100, top: 750, width: 60, height: 16 } });
      parts.left.add("button", { attrs: { "aria-label": "Add" }, rect: { left: 100, top: 750, width: 20, height: 16 } });
      const right = row.add("div", { class: "ms-auto flex items-center", rect: { left: 1000, top: 748, width: 120, height: 20 } });
      right.add("button", {
        attrs: { "data-testid": "epitaxy-cds-model-selector", "aria-label": "Model: Opus 5.5" }, text: "Opus 5.5",
        rect: { left: 1000, top: 750, width: 60, height: 16 },
      });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.calls = [];
  loaded.win.fetch = url => {
    if (String(url).endsWith("/digest")) return Promise.resolve({});
    loaded.calls.push(String(url));
    return reply(String(url));
  };
  loaded.dom.command({ id: `c-${seq += 1}`, action: "viewer-counts", at: "now", scope: "all", chats: { [CHAT]: [3, 0] } });
  loaded.win.dispatchEvent({ type: "resize" });
  loaded.dom.fireKind("timeout");
  loaded.dom.fireKind("raf");
  return loaded;
};
const answer = (status, word) => () => Promise.resolve({ status, ok: status >= 200 && status < 300, text: () => Promise.resolve(word) });
const press = loaded => loaded.dom.query("#myclaude-gallery").dispatchEvent({ type: "click" });
const gallery = loaded => plain(loaded.api.status().gallery);
const note = loaded => {
  const node = loaded.dom.query(NOTE);
  return node && node.style.getPropertyValue("display") !== "none" ? node.textContent : null;
};

test("#9631: открылась — кнопка горит, плашки нет; снят фильтр — гаснет, плашки нет", async () => {
  const loaded = page(url => answer(200, url.endsWith("on=1") ? "opened" : "off")());
  press(loaded);
  await drain();
  assert.deepEqual([gallery(loaded).on, gallery(loaded).answer, note(loaded)], [true, "opened", null]);
  press(loaded);
  await drain();
  assert.deepEqual([gallery(loaded).on, gallery(loaded).answer, note(loaded)], [false, "off", null]);
});

test("#9631: горела, а приложение открыло окно (окна галереи не было видно) — снова горит", async () => {
  const loaded = page(answer(200, "opened"));
  loaded.dom.command({ id: "v-lit", action: "viewer-chat", at: "now", scope: "all", chat: CHAT });
  press(loaded);
  assert.equal(loaded.calls[0].endsWith("on=0"), true);
  assert.equal(gallery(loaded).on, false, "сразу — как нажали");
  await drain();
  assert.equal(gallery(loaded).on, true, "ответ «opened» зажигает");
});

test("#9631: PimpViewer не запущен — плашка «открываю», кнопка горит", async () => {
  const loaded = page(answer(200, "launching"));
  press(loaded);
  await drain();
  assert.equal(note(loaded), "PimpViewer не запущен — открываю");
  assert.equal(gallery(loaded).on, true);
});

test("#9631: каждый отказ — плашка с причиной, кнопка как была", async () => {
  const cases = {
    missing: "Галерея недоступна: PimpViewer не установлен",
    foreign: "Галерея недоступна: порт 47616 занят другой программой",
    "no-token": "Галерея недоступна: нет ключа канала — перезапусти PimpViewer",
    silent: "Галерея недоступна: PimpViewer не отвечает",
    refused: "Галерея недоступна: PimpViewer отказал",
    "no-window": "Галерея ответила, но окна не видно: чат ей неизвестен или окно на другом рабочем столе",
  };
  for (const [word, text] of Object.entries(cases)) {
    const loaded = page(answer(word === "no-window" ? 200 : 503, word));
    press(loaded);
    assert.equal(gallery(loaded).on, true, `${word}: сразу горит`);
    await drain();
    assert.equal(note(loaded), text, word);
    assert.deepEqual([gallery(loaded).on, gallery(loaded).answer], [false, word], `${word}: кнопка не вернулась`);
  }
});

test("#9631: Пимп не ответил (сеть) или отказал кодом — плашка; 204 старого приложения — молчим", async () => {
  const down = page(() => Promise.reject(new TypeError("Failed to fetch")));
  press(down);
  await drain();
  assert.equal(note(down), "Галерея недоступна: PMP не отвечает (порт 47615)");
  assert.deepEqual([gallery(down).on, gallery(down).answer], [false, "network"]);

  const denied = page(answer(403, ""));
  press(denied);
  await drain();
  assert.equal(note(denied), "Галерея недоступна: PMP ответил 403");
  assert.equal(gallery(denied).on, false);

  const old = page(answer(204, ""));
  press(old);
  await drain();
  assert.equal(note(old), null, "старое приложение без слова — плашки нет");
  assert.equal(gallery(old).on, true, "кнопка — как раньше, горит сразу");
});

test("#9631: поздний ответ после dispose — ничего", async () => {
  let release;
  const loaded = page(() => new Promise(resolve => { release = resolve; }));
  press(loaded);
  loaded.api.dispose();
  release({ status: 503, text: () => Promise.resolve("silent") });
  await drain();
  assert.equal(loaded.dom.query(NOTE), null);
});
