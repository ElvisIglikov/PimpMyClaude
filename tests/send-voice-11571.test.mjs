// #11571 (RickIOS 02.11 05:06): «та фраза ушла Пимпу на Маке запасным путём, вставка не отправилась и
// осталась в поле Claude, письмо почтой дошло в 23:58, а черновик из поля переезжал с чатом при renew и
// ушёл отправкой в 03:05». Вставка голоса «Голос Элвиса: … #v<id> · …» (rick_bus.tell_voice) — только
// короткий путь: письмо уже в почте Рика. Не ушла — из поля вон; за чужим в поле не ждёт; в очереди — не
// дольше 10 с; одна в поле — стирается обходом; с черновиком при renew не едет (раздел 12ч).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const CHAT = "local_aaaa-1111";
const VOICE = "Голос Элвиса: 🎙 Голосом с телефона #v1793559474634-d9d0e9 · посмотри картинку";
const VOICE_LIVE = "Голос Элвиса: #v1793570868037-b915dc · Голос отправляй сжатым";

const page = ({ text = "", clears = true } = {}) => {
  const loaded = loadInject({
    href: `https://claude.ai/epitaxy/${CHAT}`, title: "Тест голоса",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({ text });
      parts.send = parts.modelRow.add("button", {
        attrs: { "data-testid": "code-prompt-send" },
        rect: { left: 1150, top: 700, width: 24, height: 24 },
      });
      parts.send.__presses = 0;
      parts.send.addEventListener("pointerdown", () => {
        parts.send.__presses += 1;
        if (clears) parts.editor.__text = "";
      });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  let t = 1_000_000;
  loaded.win.performance.now = () => t;
  loaded.advance = ms => { t += ms; loaded.dom.fireKind("timeout"); };
  return loaded;
};
const send = (loaded, text, id = "v-1") =>
  loaded.dom.command({ id, action: "send-text", at: "2026-11-02T05:30:00Z", chat: CHAT, text });
const status = loaded => plain(loaded.api.status().send);

test("голос не ушёл (поле не опустело) — no-send, вставка стёрта из поля", () => {
  const loaded = page({ clears: false });
  send(loaded, VOICE);
  for (let step = 0; step < 50; step += 1) loaded.advance(100);
  assert.equal(status(loaded).state, "no-send");
  assert.equal(loaded.parts.editor.textContent, "", "в поле не осталось вставки — renew её не увезёт");
  assert.equal(status(loaded).cleared, 1);
});

test("обычный текст не ушёл — остаётся в поле, как по контракту WF103", () => {
  const loaded = page({ clears: false });
  send(loaded, "Проверка send: текст.");
  for (let step = 0; step < 50; step += 1) loaded.advance(100);
  assert.equal(status(loaded).state, "no-send");
  assert.equal(loaded.parts.editor.textContent, "Проверка send: текст.");
  assert.equal(status(loaded).cleared, 0);
});

test("голос не ушёл, а Элвис дописал в поле — поле не трогаем", () => {
  const loaded = page({ clears: false });
  send(loaded, VOICE);
  loaded.advance(300);
  loaded.parts.editor.__text += " моё";
  for (let step = 0; step < 50; step += 1) loaded.advance(100);
  assert.equal(status(loaded).state, "no-send");
  assert.equal(loaded.parts.editor.textContent, `${VOICE} моё`);
});

test("в поле текст Элвиса — голос сразу field-busy, в очередь не встаёт, поле не тронуто", () => {
  const loaded = page({ text: "мой черновик" });
  send(loaded, VOICE);
  assert.equal(status(loaded).state, "field-busy");
  assert.equal(status(loaded).queue, 0);
  loaded.parts.editor.__text = "";
  for (let step = 0; step < 10; step += 1) { loaded.advance(500); loaded.dom.fireKind("interval"); }
  assert.equal(loaded.parts.send.__presses, 0, "поле опустело — голос не вставлен второй раз после почты");
});

test("голос за своей отправкой — ждёт и уходит; дольше 10 с не ждёт", () => {
  const behind = page();
  send(behind, VOICE, "v-1");
  send(behind, VOICE_LIVE, "v-2");
  assert.equal(status(behind).state, "queued");
  behind.advance(300);
  assert.equal(behind.parts.send.__presses, 1);
  for (let step = 0; step < 8; step += 1) { behind.advance(250); behind.dom.fireKind("interval"); }
  behind.advance(300);
  assert.equal(behind.parts.send.__presses, 2, "вторая фраза ушла за первой");
  assert.equal(status(behind).state, "sent");

  const late = page();
  send(late, VOICE, "v-1");
  send(late, VOICE_LIVE, "v-2");
  late.advance(300);
  late.parts.editor.__text = "Элвис печатает";
  for (let step = 0; step < 44; step += 1) { late.advance(250); late.dom.fireKind("interval"); }
  assert.equal(status(late).queue, 0, "через 10 с фраза вышла из очереди — её несёт почта");
  late.parts.editor.__text = "";
  for (let step = 0; step < 10; step += 1) { late.advance(250); late.dom.fireKind("interval"); }
  assert.equal(late.parts.send.__presses, 1, "поле опустело — старая фраза не вставлена");
});

test("обход: в поле одна вставка голоса — стёрта; с текстом Элвиса или обычный текст — не тронуты", () => {
  for (const [text, left] of [
    [VOICE, ""],
    [`${VOICE}\n${VOICE_LIVE}`, ""],
    [`${VOICE}\nмоё`, `${VOICE}\nмоё`],
    ["Голос Элвиса: без метки письма", "Голос Элвиса: без метки письма"],
    ["обычный черновик", "обычный черновик"],
  ]) {
    const loaded = page({ text });
    loaded.dom.fireKind("interval");
    assert.equal(loaded.parts.editor.textContent, left, text);
    assert.equal(status(loaded).cleared, left ? 0 : 1, text);
  }
});

test("строки вставок голоса из текста черновика убираются, остальное — как было", () => {
  const loaded = page();
  const strip = loaded.inner.sendTextNoVoice;
  assert.equal(strip(`${VOICE}\nнадиктовал кусок\n${VOICE_LIVE}`), "надиктовал кусок");
  assert.equal(strip(VOICE), "");
  assert.equal(strip("Голос Элвиса: просто фраза"), "Голос Элвиса: просто фраза", "без #v — не вставка запасного пути");
});
