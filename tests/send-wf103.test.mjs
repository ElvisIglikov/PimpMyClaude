// WF103, батч P2 (раздел 12т¹ inject.js; #7953, #7927): команда send-text.
//
// Контракт — CONTRACTS WF103 «Команда send»: command.json
// {"id","action":"send-text","at","chat","text"}; страница сверяет chat с
// myChatId() (чужой — мимо), повтор того же id — ничего; поле пустое (пробелы —
// пусто) — вставка selectAll + insertText, кнопка «отправить» (SEND_SELECTOR +
// pressLikeMouse), поле опустело за 3 с — sent; свой текст — queued (поле не
// тронуто, фраза уйдёт, когда поле опустеет; WF111), очередь полна — field-busy; поля нет — no-field; кнопки нет или поле не опустело — no-send
// (текст остаётся). Enter не шлётся никогда. Исход — status().send.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_aaaa-1111";
const OTHER = "local_bbbb-2222";

// Главное окно (свой чат — из адреса) или попап (свой чат — из волокна шапки).
const page = ({ text = "", button = true, clears = true, composer = true, popout = false } = {}) => {
  const loaded = loadInject({
    href: popout ? "about:blank" : `https://claude.ai/epitaxy/${CHAT}`, title: "Тест send",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = composer ? dom.composer({ text }) : {};
      if (popout) {
        const panel = dom.document.body.add("div", { class: "epitaxy-chat-panel", rect: { left: 0, top: 0, width: 600, height: 700 } });
        const bar = panel.add("div", { class: "epitaxy-titlebar", rect: { left: 80, top: 0, width: 300, height: 32 } });
        bar["__reactFiber$test"] = { memoizedProps: { episodeKey: CHAT }, return: null };
      }
      if (composer && button) {
        parts.send = parts.modelRow.add("button", {
          attrs: { "data-testid": "code-prompt-send" },
          rect: { left: 1150, top: 700, width: 24, height: 24 },
        });
        parts.send.__presses = 0;
        // Claude уносит текст из поля, когда сообщение ушло.
        parts.send.addEventListener("pointerdown", () => {
          parts.send.__presses += 1;
          if (clears) parts.editor.__text = "";
        });
      }
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  // Часы страницы (now() — performance.now) двигает тест.
  let t = 1_000_000;
  loaded.win.performance.now = () => t;
  loaded.keys = [];
  loaded.win.addEventListener("keydown", event => loaded.keys.push(event.key), true);
  loaded.document.addEventListener("keydown", event => loaded.keys.push(event.key), true);
  loaded.advance = ms => { t += ms; loaded.dom.fireKind("timeout"); };
  return loaded;
};
const send = (loaded, extra = {}) => loaded.dom.command({ id: "s-1", action: "send-text", at: "2026-09-27T02:10:00Z", chat: CHAT, text: "Проверка send: текст голоса.", ...extra });
const outcome = loaded => {
  const value = plain(loaded.api.status().send);
  return { id: value.id, state: value.state, sends: value.sends, at: typeof value.at };
};

test("send-text: пустое поле — текст вставлен, «отправить» нажата, поле опустело — sent", () => {
  const loaded = page();
  assert.deepEqual(plain(loaded.api.status().send), { id: null, state: null, at: null, sends: 0, queue: 0, queued: 0 });
  send(loaded);
  assert.equal(loaded.parts.send.__presses, 0, "не в том же такте, что вставка");
  loaded.advance(300);
  assert.equal(loaded.parts.send.__presses, 1, "кнопка «отправить» нажата один раз");
  assert.deepEqual(outcome(loaded), { id: "s-1", state: "sent", sends: 1, at: "string" });
  assert.deepEqual(loaded.keys, [], "Enter не шлётся");
});

test("send-text: вставка — поверх пустого поля ровно этим текстом (selectAll + insertText)", () => {
  const loaded = page({ text: "   ", clears: false });
  send(loaded);
  assert.equal(loaded.parts.editor.textContent, "Проверка send: текст голоса.", "пробелы — пусто, поле переписано целиком");
  loaded.advance(300);
  assert.equal(loaded.parts.send.__presses, 1);
  loaded.advance(1500);
  assert.equal(loaded.parts.send.__presses, 2, "в поле ровно наш текст — ещё одно нажатие через 1,5 с (WF103)");
  loaded.advance(1500);
  assert.equal(loaded.parts.send.__presses, 2, "третьего нажатия нет, таймаут не повторяет");
  assert.equal(loaded.api.status().send.state, "no-send");
});

test("send-text: первое нажатие не взяло — повтор через 1,5 с, поле опустело — sent (WF103, WF111)", () => {
  const loaded = page({ clears: false });
  loaded.parts.send.addEventListener("pointerdown", () => { if (loaded.parts.send.__presses === 2) loaded.parts.editor.__text = ""; });
  send(loaded);
  loaded.advance(300);
  assert.equal(loaded.parts.send.__presses, 1);
  for (let step = 0; step < 14; step += 1) loaded.advance(100);
  assert.equal(loaded.parts.send.__presses, 1, "до 1,5 с не повторяем");
  loaded.advance(100);
  assert.equal(loaded.parts.send.__presses, 2);
  assert.deepEqual(outcome(loaded), { id: "s-1", state: "sent", sends: 1, at: "string" });
});

test("send-text: поле после нажатия не наше — повтора нет, no-send (WF111)", () => {
  const loaded = page({ clears: false });
  send(loaded);
  loaded.advance(300);
  loaded.parts.editor.__text += " ещё";
  loaded.advance(1500);
  assert.equal(loaded.parts.send.__presses, 1);
  assert.equal(loaded.api.status().send.state, "no-send");
});

test("send-text: ProseMirror переписал вставку до первого опроса (nbsp, хвост) — снимок с первого опроса, sent (WF111)", () => {
  const loaded = page();
  send(loaded);
  // Разбор вставки: пробелы стали nbsp, в конце — перевод строки абзаца.
  loaded.parts.editor.__text = "Проверка\u00a0send:\u00a0текст голоса.\n";
  loaded.advance(100);
  loaded.advance(200);
  assert.equal(loaded.parts.send.__presses, 1);
  assert.deepEqual(outcome(loaded), { id: "s-1", state: "sent", sends: 1, at: "string" });
});

test("send-text: поле опустело не сразу — ждём до 3 с; не опустело — no-send, текст остаётся", () => {
  const late = page({ clears: false });
  send(late);
  assert.equal(late.api.status().send.state, null, "исхода ещё нет — ждём");
  late.advance(300);
  late.advance(1000);
  late.parts.editor.__text = "";
  late.advance(100);
  assert.equal(late.api.status().send.state, "sent");

  const stuck = page({ clears: false });
  send(stuck);
  for (let step = 0; step < 38; step += 1) stuck.advance(100);
  assert.deepEqual(outcome(stuck), { id: "s-1", state: "no-send", sends: 0, at: "string" });
  assert.equal(stuck.parts.editor.textContent, "Проверка send: текст голоса.", "текст остался в поле");
});

test("send-text: в поле свой текст — фраза в очереди, поле не тронуто; опустело на 1,5 с — ушла (WF111)", () => {
  const loaded = page({ text: "мой черновик" });
  send(loaded);
  assert.equal(loaded.parts.editor.textContent, "мой черновик");
  assert.equal(loaded.parts.send.__presses, 0);
  assert.deepEqual(outcome(loaded), { id: "s-1", state: "queued", sends: 0, at: "string" });
  assert.equal(loaded.api.status().send.queue, 1);
  assert.equal(loaded.document.getElementById("myclaude-send-queue"), null, "плашки нет (01.10: «сбивает»)");
  // Элвис ещё пишет — ждём.
  loaded.advance(2000);
  loaded.dom.fireKind("interval");
  assert.equal(loaded.parts.send.__presses, 0);
  // Поле опустело (Элвис отправил своё): мгновение пустоты — мало, нужно 1,5 с.
  loaded.parts.editor.__text = "";
  loaded.dom.fireKind("interval");
  loaded.advance(1000);
  loaded.dom.fireKind("interval");
  assert.equal(loaded.parts.editor.textContent, "", "рано — не вставляли");
  loaded.advance(600);
  loaded.dom.fireKind("interval");
  assert.equal(loaded.parts.editor.textContent, "Проверка send: текст голоса.", "вставили после 1,5 с пустоты");
  loaded.advance(300);
  assert.equal(loaded.parts.send.__presses, 1);
  assert.deepEqual(outcome(loaded), { id: "s-1", state: "sent", sends: 1, at: "string" });
  assert.equal(loaded.api.status().send.queue, 0);
  assert.equal(loaded.document.getElementById("myclaude-send-queue"), null, "плашка ушла");
});

test("send-text: очередь — не больше 5, шестая фраза — field-busy, плашки нет (WF111, 01.10)", () => {
  const loaded = page({ text: "мой черновик" });
  for (let n = 1; n <= 6; n += 1) send(loaded, { id: `s-${n}` });
  assert.equal(loaded.api.status().send.queue, 5);
  assert.deepEqual(outcome(loaded), { id: "s-6", state: "field-busy", sends: 0, at: "string" });
  assert.equal(loaded.document.getElementById("myclaude-send-queue"), null, "плашки нет");
});

test("send-text: поля нет — no-field; кнопки нет — no-send, текст вставлен и остался", () => {
  const bare = page({ composer: false });
  send(bare);
  assert.deepEqual(outcome(bare), { id: "s-1", state: "no-field", sends: 0, at: "string" });

  const nobutton = page({ button: false });
  send(nobutton);
  assert.deepEqual(outcome(nobutton), { id: "s-1", state: "no-send", sends: 0, at: "string" });
  assert.equal(nobutton.parts.editor.textContent, "Проверка send: текст голоса.");
});

test("send-text: чужой chat — мимо; тот же id второй раз — ничего", () => {
  const loaded = page();
  send(loaded, { chat: OTHER });
  assert.equal(loaded.parts.send.__presses, 0);
  assert.equal(loaded.parts.editor.textContent, "");
  assert.equal(loaded.api.status().send.id, null);

  send(loaded);
  loaded.advance(300);
  assert.equal(loaded.parts.send.__presses, 1);
  loaded.parts.editor.__text = "";
  send(loaded);
  loaded.advance(300);
  assert.equal(loaded.parts.send.__presses, 1, "повтор id — ничего");
  assert.equal(loaded.api.status().send.sends, 1);

  send(loaded, { id: "s-2" });
  loaded.advance(300);
  assert.equal(loaded.parts.send.__presses, 2, "новый id — снова работает");
  assert.deepEqual(outcome(loaded), { id: "s-2", state: "sent", sends: 2, at: "string" });
});

test("send-text: без id, chat или текста — ничего", () => {
  const loaded = page();
  send(loaded, { id: "" });
  send(loaded, { id: "s-3", chat: undefined });
  send(loaded, { id: "s-4", text: "" });
  assert.equal(loaded.parts.send.__presses, 0);
  assert.equal(loaded.api.status().send.id, null);
});

test("send-text: попап — свой чат по волокну шапки, отправка та же", () => {
  const loaded = page({ popout: true });
  send(loaded);
  loaded.advance(300);
  assert.equal(loaded.parts.send.__presses, 1);
  assert.equal(loaded.api.status().send.state, "sent");
});

test("send-text: кнопка ещё неживая — ждём её до 2 с; ожила — sent, не ожила — no-send (гейт 2)", () => {
  const late = page();
  late.parts.send.setAttribute("disabled", "");
  late.parts.send.disabled = true;
  send(late);
  late.advance(300);
  assert.equal(late.parts.send.__presses, 0, "неживую не жмём");
  late.parts.send.removeAttribute("disabled");
  late.parts.send.disabled = false;
  late.advance(100);
  assert.equal(late.parts.send.__presses, 1);
  assert.equal(late.api.status().send.state, "sent");

  const dead = page();
  dead.parts.send.setAttribute("disabled", "");
  dead.parts.send.disabled = true;
  send(dead);
  for (let step = 0; step < 21; step += 1) dead.advance(100);
  assert.deepEqual(outcome(dead), { id: "s-1", state: "no-send", sends: 0, at: "string" });
  assert.equal(dead.parts.send.__presses, 0);
});

test("send-text: в поле вложения Элвиса — в очередь, текст не вставлен (гейт 2, WF111)", () => {
  const loaded = page();
  loaded.parts.block.add("div", { attrs: { "data-cds-composer-attachments": "" } }).add("div", { attrs: { "data-cds-attachment": "" } });
  send(loaded);
  loaded.advance(300);
  assert.equal(loaded.parts.editor.textContent, "");
  assert.equal(loaded.parts.send.__presses, 0);
  assert.deepEqual(outcome(loaded), { id: "s-1", state: "queued", sends: 0, at: "string" });
});

test("send-text: плитка вне поля ввода (лента, чужой композер) поле занятым не делает (WF111)", () => {
  const loaded = page();
  loaded.document.body.add("div", { class: "epitaxy-attachment-pill", text: "photo.png" });
  loaded.document.body.add("div", { attrs: { "data-cds-composer-attachments": "" } }).add("div", { attrs: { "data-cds-attachment": "" } });
  send(loaded);
  loaded.advance(300);
  assert.equal(loaded.parts.send.__presses, 1);
  assert.deepEqual(outcome(loaded), { id: "s-1", state: "sent", sends: 1, at: "string" });
});

for (const when of ["before", "after"]) {
  for (const change of ["chat", "editor", "text", "whitespace", "attachment", "legacy-attachment"]) {
    test(`F02: ${change} ${when} click — no-send и новый черновик цел`, () => {
      const loaded = page({ clears: false });
      send(loaded);
      if (when === "after") loaded.advance(300);
      const old = loaded.parts.editor;
      let current = old;
      if (change === "chat") {
        loaded.win.location.pathname = `/epitaxy/${OTHER}`;
        loaded.win.location.href = `https://claude.ai/epitaxy/${OTHER}`;
      } else if (change === "editor") {
        old.remove();
        current = loaded.dom.composer({ text: old.textContent }).editor;
      } else if (change === "text") old.__text = "новый черновик";
      else if (change === "whitespace") old.__text += " ";
      else if (change === "legacy-attachment") loaded.parts.block.add("div", { class: "epitaxy-attachment-pill", text: "photo.png" });
      else loaded.parts.block.add("div", { attrs: { "data-cds-composer-attachments": "" } })
        .add("div", { attrs: { "data-cds-attachment": "" }, text: "photo.png" });
      const draft = current.textContent;
      loaded.advance(300);
      loaded.advance(4000);
      // До нажатия пробел сверяется по sayNorm (так ProseMirror правит вставку) —
      // это ещё наш текст: нажатие и повтор через 1,5 с; после нажатия сверка точная.
      const pressed = when === "after" ? 1 : change === "whitespace" ? 2 : 0;
      assert.equal(loaded.parts.send.__presses, pressed);
      assert.equal(loaded.api.status().send.state, "no-send");
      assert.equal(current.textContent, draft);
      send(loaded);
      loaded.advance(4000);
      assert.equal(loaded.parts.send.__presses, pressed, "тот же id не повторяется");
    });
  }
}
