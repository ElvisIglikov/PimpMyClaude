// Время под каждым сообщением (раздел 14а inject.js, #7747, WF94). Claude
// 2.9939.2 рисует строку действий с <time> только у последнего ответа, у реплик
// человека и под мышью; Пимп держит под каждой строкой сообщения свой тихий
// узел с временем из данных сообщения (entry.timestamp у React-волокна).
//
// Стенд повторяет пробу 26.09: ответ — div.group/message-row, запись entry — в
// пропсах компонента прямо над ним (у одной записи бывает несколько строк —
// инструменты и текст, их различает itemIdx); реплика человека —
// .epitaxy-user-turn с тем же классом, внутри пузырь UserMessage с тем же
// классом, запись — несколькими уровнями волокна выше, а родная строка
// действий с <time datetime> у неё есть.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";

const ROW = "group/msg group/message-row flex flex-col w-full relative gap-sm";
const MIN = 60000;
const fiber = (node, levels) => {
  // levels — пропсы от самого узла вверх по return; последний уровень — запись.
  let parent = null;
  for (const props of [...levels].reverse()) parent = { memoizedProps: props, return: parent };
  node["__reactFiber$test"] = parent;
};
const iso = ago => new Date(Date.now() - ago).toISOString();

const stand = rows => dom => {
  const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } });
  const made = {};
  for (const spec of rows) {
    if (spec.user) {
      const wrap = feed.add("div", { class: "flex w-full min-w-0 flex-col gap-5" });
      const msg = wrap.add("div", { class: "group/msg flex justify-start items-start gap-1 w-full" });
      const turn = msg.add("div", { class: "epitaxy-user-turn flex w-full flex-col gap-sm items-end group/message-row" });
      const bubble = turn.add("div", { attrs: { "data-cds": "UserMessage" }, class: "group/message-row ms-auto flex w-full" });
      bubble.add("p", { text: spec.text ?? "вопрос" });
      if (spec.native) {
        const bar = turn.add("div", { attrs: { "aria-label": "Message actions", role: "toolbar" } });
        bar.add("time", { attrs: { datetime: spec.at }, text: "2 hours ago" });
      }
      fiber(turn, [{ className: turn.className }, {}, {}, { entry: { id: spec.id, author: "user", timestamp: spec.at } }]);
      fiber(bubble, [{}, {}]);
      made[spec.name] = turn;
      made[`${spec.name}Bubble`] = bubble;
    } else {
      const row = feed.add("div", { class: ROW });
      row.add("div", { class: "flex flex-col select-text", text: spec.text ?? "ответ" });
      if (spec.fiber !== false) fiber(row, [{ className: ROW }, { entry: { id: spec.id, author: "assistant", timestamp: spec.at }, itemIdx: spec.idx ?? 0 }]);
      if (spec.native) {
        const bar = row.add("div", { attrs: { "aria-label": "Message actions" } });
        bar.add("time", { attrs: { datetime: spec.at }, text: "3 minutes ago" });
      }
      made[spec.name] = row;
    }
  }
  return made;
};
const open = rows => loadInject({ title: "Trelvis", html: stand(rows) });
const stampOf = row => [...row.children].find(kid => kid.hasAttribute("data-myclaude-stamp")) ?? null;
const textOf = row => stampOf(row)?.getAttribute("data-myclaude-stamp") ?? null;

test("#7747: коротко, как раздел 14; старше суток — дата и время по-местному", () => {
  const { inner } = loadInner();
  const at = Date.parse("2026-09-26T12:00:00Z");
  const ago = ms => new Date(at - ms).toISOString();
  assert.equal(inner.stampText(ago(20 * 1000), at), "just now");
  assert.equal(inner.stampText(ago(38 * MIN + 30000), at), "38 min ago");
  assert.equal(inner.stampText(ago(3 * 60 * MIN + 5 * MIN), at), "3 h ago");
  const old = new Date(at - 30 * 60 * MIN);
  const pad = value => String(value).padStart(2, "0");
  assert.equal(inner.stampText(old.toISOString(), at),
    `${pad(old.getDate())}.${pad(old.getMonth() + 1)} ${pad(old.getHours())}:${pad(old.getMinutes())}`);
  assert.equal(inner.stampText("не дата", at), null);
  assert.equal(inner.stampText(ago(-5000), at), "just now", "часы чуть впереди — не «минус минуты»");
});

test("#7747: время под каждым сообщением — и ответом, и репликой человека; текст в атрибуте, не в тексте строки", () => {
  const loaded = open([
    { name: "a1", id: "e1", at: iso(40 * MIN) },
    { name: "u1", user: true, id: "e2", at: iso(10 * MIN) },
    { name: "a2", id: "e3", at: iso(3 * MIN) },
  ]);
  assert.equal(loaded.error, null);
  const { a1, u1, a2, u1Bubble } = loaded.parts;
  assert.equal(textOf(a1), "40 min ago");
  assert.equal(textOf(u1), "10 min ago", "реплика человека — запись выше по волокну");
  assert.equal(textOf(a2), "3 min ago");
  assert.equal(stampOf(u1Bubble), null, "пузырь внутри реплики — часть её строки, второго времени нет");
  assert.equal(a1.lastElementChild, stampOf(a1), "время — последним в строке");
  assert.equal(stampOf(a1).textContent, "", "в textContent ленты времени нет — его рисует ::after");
  assert.equal(stampOf(a1).getAttribute("aria-hidden"), "true");
  assert.match(stampOf(a1).className, /text-muted/, "вид родного времени Claude");
});

test("#7747: несколько строк одной записи — время только под последней по itemIdx", () => {
  const at = iso(5 * MIN);
  const loaded = open([
    { name: "text", id: "e1", at, idx: 2, text: "Workflow идёт" },
    { name: "tools", id: "e1", at, idx: 0, text: "Ran 4 commands" },
  ]);
  assert.equal(textOf(loaded.parts.text), "5 min ago");
  assert.equal(stampOf(loaded.parts.tools), null, "строка инструментов той же записи — без времени");
});

test("#7747: один ход Claude (общий entry.id), тексты в разное время — время под каждым", () => {
  const late = iso(1 * MIN);
  const loaded = open([
    { name: "t1", id: "msg_1", at: iso(30 * MIN), idx: 30 },
    { name: "tools1", id: "msg_1", at: late, idx: 31 },
    { name: "t2", id: "msg_1", at: iso(20 * MIN), idx: 32 },
    { name: "tools2", id: "msg_1", at: late, idx: 33 },
  ]);
  const { t1, tools1, t2, tools2 } = loaded.parts;
  assert.deepEqual([t1, tools1, t2, tools2].map(textOf), ["30 min ago", null, "20 min ago", "1 min ago"],
    "строки инструментов с временем последнего обновления — одно сообщение, время под последней");
});

test("#7747: волокна нет — время из datetime родного <time> строки", () => {
  const loaded = open([{ name: "a", fiber: false, native: true, at: iso(7 * MIN) }]);
  assert.equal(textOf(loaded.parts.a), "7 min ago");
});

test("#7747: рядом с родным временем наше прячется правилом; время из записи, а не из текста", () => {
  const { inner } = loadInner();
  const css = plain(inner.RULES).join("\n");
  assert.match(css, /\[class\*="group\/message-row"\]:has\(\[aria-label="Message actions"\] time\)>\[data-myclaude-stamp\]\{display:none !important\}/);
  assert.match(css, /\[data-myclaude-stamp\]::after\{content:attr\(data-myclaude-stamp\)\}/);
});

test("#7747: раз в минуту меняется только атрибут — узел тот же, лента не перестраивается", () => {
  const loaded = open([{ name: "a", id: "e1", at: iso(2 * MIN) }]);
  const { a } = loaded.parts;
  const node = stampOf(a);
  assert.equal(node.getAttribute("data-myclaude-stamp"), "2 min ago");
  // Прошло время: запись та же, «сейчас» сдвинулось — подменяем запись на более раннюю.
  a["__reactFiber$test"].return.memoizedProps.entry.timestamp = iso(62 * MIN);
  const minute = [...loaded.dom.timers.entries()].filter(([, item]) => item.kind === "interval" && item.ms === MIN);
  assert.ok(minute.length > 0, "тика раз в минуту нет");
  for (const [id] of minute) loaded.dom.fire(id);
  assert.equal(stampOf(a), node, "узел не пересоздан");
  assert.equal(node.getAttribute("data-myclaude-stamp"), "1 h ago");
  assert.equal([...a.children].filter(kid => kid.hasAttribute("data-myclaude-stamp")).length, 1);
});

test("#7747: повторный проход и перезапись inject.js не плодят узлы; dispose() их убирает", () => {
  const loaded = open([{ name: "a", id: "e1", at: iso(2 * MIN) }, { name: "u", user: true, id: "e2", at: iso(1 * MIN) }]);
  loaded.inner.stampTimes();
  loaded.inner.stampTimes();
  assert.equal(loaded.dom.queryAll("[data-myclaude-stamp]").length, 2);
  loaded.reload();
  assert.equal(loaded.dom.queryAll("[data-myclaude-stamp]").length, 2, "после перезаписи — те же два");
  loaded.api.dispose();
  assert.equal(loaded.dom.queryAll("[data-myclaude-stamp]").length, 0);
});
