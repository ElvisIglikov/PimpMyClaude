// Авто-«Trust workspace» (#7498, раздел 12е inject.js; слово Элвиса 25.09 ~23:55:
// «сделай, как авто-Allow, чтоб нажимался. Я разрешаю»). Диалог Claude «Trust
// this workspace?» с путём папки: жмём ТОЛЬКО папки внутри
// /Users/dev/Projects/; с WF102 (#7905) — вне тумблера Авто-Allow, а с
// WF119 Авто-Allow снят совсем, счётчики — в status().trust (К-A5).
// С WF108 корень не зашит: его присылает приложение командой trust-root, страница
// держит его в localStorage (ROOT_KEY); корня нет — автодоверие выключено.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

// Ключ тумблера Авто-Allow (снят в WF119) — у людей он остался в хранилище.
const ON_KEY = "myclaude.autoAllow";
const ROOT_KEY = "myclaude-trust-root-v1";
const ROOT = "/Users/dev/Projects/";
const rect = { left: 100, top: 300, width: 140, height: 32 };

const page = ({ path, on = true, label = "Trust workspace", role = "dialog", root = ROOT } = {}) => {
  const box = { trust: 0, cancel: 0 };
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy", title: "Claude",
    storage: { local: { ...(on === null ? {} : { [ON_KEY]: on ? "true" : "false" }), ...(root ? { [ROOT_KEY]: root } : {}) } },
    html: dom => {
      const dialog = dom.document.body.add("div", { attrs: role ? { role } : {}, rect: { left: 0, top: 0, width: 500, height: 300 } });
      dialog.add("h2", { text: "Trust this workspace?" });
      // Пробелы по краям — как innerText у блоков настоящей страницы (стаб склеивает детей).
      if (path) dialog.add("p", { text: ` ${path} ` });
      dialog.add("p", { text: "Claude Code will be able to read, edit, and execute files here." });
      const trust = dialog.add("button", { text: label, rect });
      const cancel = dialog.add("button", { text: "Cancel", rect });
      trust.addEventListener("click", () => { box.trust += 1; });
      cancel.addEventListener("click", () => { box.cancel += 1; });
      return { dialog, trust, cancel };
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  const clock = { t: 9_000_000 };
  loaded.inner.setAutoAllowClock(() => clock.t);
  const cycle = () => { clock.t += 1000; loaded.inner.trustCycle(); };
  return { loaded, box, cycle };
};

test("#7498: папка проекта Элвиса — «Trust workspace» нажат, счётчик в status()", () => {
  const { loaded, box, cycle } = page({ path: "/Users/dev/Projects/PimpMyClaude" });
  cycle();
  assert.equal(box.trust, 1);
  assert.equal(box.cancel, 0, "Cancel не трогаем");
  const trust = plain(loaded.api.status().trust);
  assert.equal(trust.presses, 1);
  assert.equal(trust.last.verdict, "pressed");
  assert.equal(trust.last.path, "/Users/dev/Projects/PimpMyClaude");
});

test("#7498: путь через ~ и подпапка проекта — тоже жмём", () => {
  const { box, cycle } = page({ path: "~/Projects/VkusnoffKz/app." });
  cycle();
  assert.equal(box.trust, 1);
});

test("#7498: чужой путь — не жмём, отказ в status()", () => {
  for (const path of ["/Users/dev/Downloads/evil", "/Users/dev/ProjectsEvil/x", "/Users/dev/Projects",
    "/Users/dev/Projects/../Documents", "/tmp/x", "~/Desktop",
    // Обходы из проверки #7498: «..» в хвосте, путь с пробелом или кавычкой,
    // путь сразу после «:», длинный текст с «/..» за границей 2000 знаков.
    "/Users/dev/Projects/x/..", "/Users/dev/Projects/My Dir/../../../../tmp",
    '/Users/dev/Projects/a"b/../../../tmp', "Folder:/tmp and /Users/dev/Projects/a",
    "C:/tmp /Users/dev/Projects/a", `${"x ".repeat(995)}/Users/dev/Projects/a/../..`]) {
    const { loaded, box, cycle } = page({ path });
    cycle();
    cycle();
    assert.equal(box.trust, 0, path);
    const trust = plain(loaded.api.status().trust);
    assert.equal(trust.presses, 0, path);
    assert.equal(trust.refused, 1, `${path}: отказ считается один раз на диалог`);
    assert.notEqual(trust.last.verdict, "pressed", path);
  }
});

test("#7498: настоящий диалог Claude 2.9939.2 (снят 26.09) — жмём, список «Execution allowed by» не мешает", () => {
  for (const allowed of [".claude/settings.local.json", "~/.claude/settings.json"]) {
    const box = { trust: 0 };
    const loaded = loadInject({
      href: "https://claude.ai/epitaxy", title: "Claude",
      storage: { local: { [ROOT_KEY]: ROOT } },
      html: dom => {
        const dialog = dom.document.body.add("div", { attrs: { role: "alertdialog" }, rect: { left: 0, top: 0, width: 500, height: 300 } });
        const inner = dialog.add("div");
        inner.add("h2", { text: "Trust this workspace?" });
        inner.add("p", { text: "Claude Code may read, write, or execute files in this folder. Only proceed if you trust this workspace." });
        inner.add("div", { attrs: { class: "mt-3 text-code text-primary break-all" }, text: "/Users/dev/Projects/TrelvisBot" });
        inner.add("p", { text: "Read our security guide for more information." });
        const exec = inner.add("div");
        exec.add("div", { text: "Execution allowed by:" });
        exec.add("ul").add("li", { attrs: { class: "text-code break-all" }, text: allowed });
        const buttons = inner.add("div");
        buttons.add("button", { text: "Cancel", rect });
        const trust = buttons.add("button", { text: "Trust workspace", rect });
        trust.addEventListener("click", () => { box.trust += 1; });
        return {};
      },
    });
    assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
    loaded.inner.setAutoAllowClock(() => 9_000_000);
    loaded.inner.trustCycle();
    assert.equal(box.trust, 1, allowed);
    assert.equal(plain(loaded.api.status().trust).last.path, "/Users/dev/Projects/TrelvisBot");
  }
});

test("#7498: пути в диалоге нет — не жмём", () => {
  const { loaded, box, cycle } = page({ path: null });
  cycle();
  assert.equal(box.trust, 0);
  assert.equal(plain(loaded.api.status().trust).last.verdict, "no-path");
});

test("#7905, WF119: старый ключ тумблера Авто-Allow на доверие не влияет — вкл., выкл. и без ключа жмём одинаково", () => {
  for (const on of [true, false, null]) {
    const { loaded, box, cycle } = page({ path: "/Users/dev/Projects/PimpMyClaude", on });
    cycle();
    assert.equal(box.trust, 1, String(on));
    assert.equal(plain(loaded.api.status().trust).presses, 1, String(on));
  }
});

test("#7498: кнопка не «Trust workspace» — не наша", () => {
  const { box, cycle } = page({ path: "/Users/dev/Projects/PimpMyClaude", label: "Trust" });
  cycle();
  assert.equal(box.trust, 0);
});

test("WF108: корня нет — автодоверие выключено даже для папки проекта", () => {
  const { loaded, box, cycle } = page({ path: "/Users/dev/Projects/PimpMyClaude", root: null });
  cycle();
  assert.equal(box.trust, 0);
  const trust = plain(loaded.api.status().trust);
  assert.equal(trust.root, null);
  assert.equal(trust.last.verdict, "outside");
});

test("WF108: команда trust-root ставит корень (без «/» на конце — дописывает), null и мусор — снимают", () => {
  const { loaded, box, cycle } = page({ path: "/Users/dev/Projects/PimpMyClaude", root: null });
  const send = (id, root) => loaded.dom.command({ id, action: "trust-root", at: "now", root });
  send("r1", ROOT.slice(0, -1));
  assert.equal(loaded.win.localStorage.getItem(ROOT_KEY), ROOT);
  assert.equal(plain(loaded.api.status().trust).root, ROOT);
  cycle();
  assert.equal(box.trust, 1, "корень пришёл командой — папка проекта доверена");
  for (const [id, bad] of [["r2", null], ["r3", "/"], ["r4", "relative/x"], ["r5", "/Users/dev/../x/"], ["r6", 42]]) {
    send("r0" + id, ROOT);
    send(id, bad);
    assert.equal(loaded.win.localStorage.getItem(ROOT_KEY), null, `корень ${JSON.stringify(bad)} не снял прежний`);
  }
});
