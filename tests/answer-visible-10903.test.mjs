// #10903 (раздел 14б, page/695-answer-reveal.js): видимый текст ответа не прячется. Слово Элвиса 24.10: «последнее
// сообщение почему-то не отображается. Просто пустота… то пропадает, то появляется». Живьём (окно Рика, Claude Code):
// у последнего куска ответа data-is-streaming="true" весь ход, кнопка стопа есть — правило «пишется» держало его
// прозрачным всё время, пока шла команда. Класс: прячет только метка, недолго и только то, что ещё не показывали.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const HOLD = "data-myclaude-reveal-hold";
const FREE = "data-myclaude-reveal-free";

// Лента Claude Code: реплика Элвиса, кнопка стопа (ход идёт). Ответы добавляет тест — уже после установки страницы,
// чтобы отсчёт шёл по часам стенда.
const stand = () => {
  const nodes = {};
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_visible-10903", title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({});
      nodes.stop = dom.document.body.add("button", { attrs: { "data-testid": "chat-input-stop" } });
      nodes.feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: { left: 0, top: 0, width: 800, height: 600 } });
      nodes.feed.clientHeight = 600;
      nodes.feed.scrollHeight = 600;
      nodes.rows = nodes.feed.add("div", { attrs: { "data-testid": "transcript-rows" } });
      nodes.rows.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "human" }, rect: { left: 0, top: 0, width: 800, height: 100 } })
        .add("div", { class: "epitaxy-user-turn" }).add("p", { text: "что с вкладками" });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  let clock = 5000000;
  loaded.win.performance.now = () => clock;
  // Кусок ответа хода entry: ряд ленты с ключом хода и сообщение «пишется».
  const answer = (entry, text, streaming = "true") => {
    const row = nodes.rows.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant" }, rect: { left: 0, top: 100, width: 800, height: 200 } });
    const message = row.add("div", { attrs: { "data-epitaxy-entry": entry } })
      .add("div", { attrs: { "data-cds": "AssistantMessage", "data-is-streaming": streaming } });
    message.add("p", { text });
    return { row, message };
  };
  return {
    loaded, nodes, answer,
    at: ms => { clock += ms; },
    sync: () => loaded.inner.revealSync(),
    tick: () => loaded.dom.fireKind("timeout"),
  };
};
const hidden = node => node.hasAttribute(HOLD);

test("#10903: ход идёт, а текст встал (идёт команда) — через REVEAL_WAIT_MS виден и под метку не встаёт", () => {
  const s = stand();
  const { message } = s.answer("A1", "Закрываю лишние вкладки в Хроме.");
  s.sync();
  assert.equal(hidden(message), true, "новый кусок сперва под меткой — печатания нет");
  const wait = s.loaded.inner.REVEAL_WAIT_MS;
  s.at(wait - 100);
  s.tick();
  assert.equal(hidden(message), true, "текст ещё мог расти");
  s.at(100);
  s.tick();
  assert.equal(hidden(message), false, "команда идёт, текст стоит — виден, а не пустота");
  assert.equal(message.hasAttribute(FREE), true);
  s.at(60000);
  s.tick();
  s.sync();
  assert.equal(hidden(message), false, "и через минуту хода — виден");
  assert.equal(plain(s.loaded.api.status().reveal).freed, 1);
  s.loaded.api.dispose();
});

test("#10903: показанное снова стало «пишется» — не прячется (и то, что было видно до нас)", () => {
  const s = stand();
  const { message } = s.answer("A1", "Первый кусок ответа.");
  s.sync();
  s.at(100);
  message.setAttribute("data-is-streaming", "false");
  s.answer("A1-tool", "Running a command", "false");
  s.sync();
  assert.equal(hidden(message), false, "кусок дописан — показан");
  message.setAttribute("data-is-streaming", "true");
  s.sync();
  assert.equal(hidden(message), false, "Claude снова поставил «пишется» — текст остаётся на виду");

  // Сообщение было на виду до нас («пишется» = false), Claude ставит ему «пишется» — это не новый текст.
  const seen = s.answer("A2", "Видимый ответ.", "false").message;
  seen.setAttribute("data-is-streaming", "true");
  s.loaded.inner.revealWatch.fn([{ type: "attributes", target: seen, attributeName: "data-is-streaming", oldValue: "false" }]);
  assert.equal(hidden(seen), false, "видимое не прячется");
  assert.equal(seen.hasAttribute(FREE), true);
  s.loaded.api.dispose();
});

test("#10903: виртуальная лента пересоздала ряд показанного ответа — новый узел не прячется; новый ход — прячется", () => {
  const s = stand();
  const first = s.answer("A1", "Ответ про вкладки.");
  s.sync();
  s.at(s.loaded.inner.REVEAL_WAIT_MS);
  s.tick();
  assert.equal(hidden(first.message), false);
  first.row.remove();
  const again = s.answer("A1", "Ответ про вкладки.");
  s.sync();
  assert.equal(hidden(again.message), false, "тот же ход, ряд пересоздан — без пустоты");
  assert.equal(again.message.hasAttribute(FREE), true);
  const next = s.answer("A3", "Новый ответ.");
  s.sync();
  assert.equal(hidden(next.message), true, "новый кусок нового хода — как раньше, без печаталки");
  const css = s.loaded.dom.queryAll("style").map(node => node.textContent).join("\n");
  assert.doesNotMatch(css, /\[data-is-streaming="true"\]\{|\[data-is-streaming="true"\]:not/, "сам «пишется» правилом не прячется");
  s.loaded.api.dispose();
  assert.equal(hidden(next.message), false, "dispose снимает метку");
});
