// #10315: блок Workflow панели — только живое. Страница отдаёт приложению ход Workflow из строки состояния
// последнего ответа: chats().flow = {state, project} — у main и popout, после sendDelaySetting и перед limits,
// и только когда строка разобрана (контракт docs/contracts/510-10315-flow-live.md).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const page = line => dom => {
  const parts = dom.composer({ top: 620 });
  if (line != null) {
    dom.document.body.add("div", {
      attrs: { "data-testid": "assistant-message" },
      rect: { left: 100, top: 200, width: 1000, height: 300 },
      text: `Готово.\n\n${line}`,
    });
  }
  return parts;
};

const open = (line, extra = {}) => loadInject({
  html: page(line), title: "PimpMyClaude", geometry: { frame: [0, 25, 800, 600] }, ...extra,
});

test("строка «идёт» — flow {state:run, project} после sendDelaySetting и перед limits", async () => {
  const loaded = open("⚪[PimpMyClaude](docs/status.md) · WF 2 из 3 · идёт 💭");
  const answer = plain(await loaded.api.chats({ nonce: "f1" }));
  assert.equal(answer.kind, "main");
  assert.deepEqual(answer.flow, { state: "run", project: "PimpMyClaude" });
  const keys = Object.keys(answer);
  const at = keys.indexOf("flow");
  assert.deepEqual(keys.slice(at - 1, at + 2), ["sendDelaySetting", "flow", "limits"]);
  assert.deepEqual(Object.keys(answer.flow), ["state", "project"]);
});

test("другие слова строки — их состояние: жду, готово, упал", async () => {
  const cases = [
    ["⚪[PimpMyClaude](docs/status.md) · WF 2 из 3 · жду ❓", "wait"],
    ["⚪[PimpMyClaude](docs/status.md) · WF 3 из 3 · готово ✅", "done"],
    ["⚪[PimpMyClaude](docs/status.md) · WF 1 из 3 · упал 🛑", "fail"],
  ];
  for (const [line, state] of cases) {
    const answer = plain(await open(line).api.chats({ nonce: "f2" }));
    assert.equal(answer.flow?.state, state, line);
  }
});

test("строки состояния нет — поля flow нет, порядок прежних ключей тот же", async () => {
  const quiet = plain(await open("Просто ответ без строки состояния.").api.chats({ nonce: "f3" }));
  assert.ok(!("flow" in quiet));
  const empty = plain(await open(null).api.chats({ nonce: "f4" }));
  assert.ok(!("flow" in empty));
  const keys = Object.keys(empty);
  const at = keys.indexOf("sendDelaySetting");
  assert.equal(keys[at + 1], "limits", "без строки — сразу limits, как до #10315");
});

test("у чужой страницы поля flow нет", async () => {
  const other = loadInject({ href: "data:text/html,x", html: page("⚪[PimpMyClaude](docs/status.md) · WF 2 из 3 · идёт 💭") });
  const answer = plain(await other.api.chats({ nonce: "f5" }));
  assert.equal(answer.kind, "other");
  assert.ok(!("flow" in answer));
});

test("вынесенный чат (popout) — тоже flow", async () => {
  const parent = open(null);
  const popup = loadInject({
    href: "about:blank", title: "PimpMyClaude", opener: parent.win,
    html: page("⚪[PimpMyClaude](docs/status.md) · WF 2 из 3 · идёт 💭"), geometry: { frame: [40, 60, 700, 500] },
  });
  const answer = plain(await popup.api.chats({ nonce: "f6" }));
  assert.equal(answer.kind, "popout");
  assert.deepEqual(answer.flow, { state: "run", project: "PimpMyClaude" });
});
