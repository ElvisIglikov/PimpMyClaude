// Класс «свой скрытый узел с ролью накладки» (ревизия WF247, P1; WF248 П0). Дважды: слой фото
// (починен 25.09, 3042c3b) и панель настройки глав (WF241) держали role="dialog" и закрытыми — сторож
// Esc (раздел 16) и «Bypass во всех чатах» (12с¹) считали окно открытым, и до перезагрузки страницы Esc
// в поле ввода снова останавливал агента, а Bypass в новых чатах не ставился.
//
// Что проверяется:
//   1) каждая своя панель — главы, фото, PMP, окошко «Запустить?» — открыта и закрыта: ни один узел
//      страницы не совпадает с приметами накладки (роли dialog/menu/listbox/alertdialog, [data-state=open],
//      [cmdk-root], aria-modal), Esc в поле глотается, status().escapesBlocked считает его;
//   2) сторож Esc видит только ВИДИМЫЕ окна и меню Claude (CLAUDE_POPUP_SELECTOR и палитра cmdk):
//      постоянный [data-state="open"], скрытый диалог и подсказка Esc не отпускают, видимые меню — отпускают;
//   3) Bypass во всех чатах ставится и после настройки глав.
// Стаб событий не всплывает: мышь — документу, клавиши — окну, с нужной целью в target.
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

// Приметы «открыто окно или меню» у проходов страницы (OVERLAY_SELECTOR, BYPASS_DIALOG_SELECTOR,
// ROAM_OVERLAY_SELECTOR, прежний голый ESC_OVERLAY_SELECTOR) плюс aria-modal.
const OVERLAY_SIGNS = '[role="dialog"],[role="menu"],[role="listbox"],[role="alertdialog"],[data-state="open"],[cmdk-root],[aria-modal]';
const signs = loaded => loaded.dom.queryAll(OVERLAY_SIGNS).map(node => node.id || node.tagName);
const blocked = loaded => plain(loaded.api.status()).escapesBlocked;
// Esc в поле ввода: отменён ли (true — проглочен и до Claude не дошёл).
const escInField = loaded => {
  loaded.parts.editor.focus();
  return !loaded.win.dispatchEvent({ type: "keydown", key: "Escape", target: loaded.parts.editor });
};
const escAt = loaded => !loaded.win.dispatchEvent({ type: "keydown", key: "Escape", target: loaded.document.activeElement });
const mouse = (loaded, type, target, extra = {}) => !loaded.document.dispatchEvent({ type, target, button: 0, detail: 1, clientX: 60, clientY: 120, ...extra });
const settle = async (times = 6) => { for (let i = 0; i < times; i += 1) await new Promise(resolve => setImmediate(resolve)); };
// Закрыто — ни одной приметы накладки, Esc в поле снова глотается и идёт в счёт.
const closedClean = (loaded, what) => {
  assert.deepEqual(signs(loaded), [], `${what}: закрытая панель держит роль накладки`);
  const before = blocked(loaded);
  assert.equal(escInField(loaded), true, `${what}: Esc в поле дошёл бы до Claude и остановил ход`);
  assert.equal(blocked(loaded), before + 1);
};

// ---- главы (12х²) и Bypass (12с¹) ----------------------------------------------------------------
const MODES = ["Ask permissions", "Accept edits", "Plan mode", "Bypass permissions", "Auto mode"];
const chaptersPage = ({ bypass = false } = {}) => {
  const nodes = { rail: [] };
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_overlay-248", title: "Rick",
    storage: { local: { "myclaude-auto-allow-roam": "off", ...(bypass ? { "myclaude.bypassChats": "1" } : {}) } },
    html: dom => {
      const parts = dom.composer({});
      if (bypass) {
        const chin = parts.modelRow.add("div", { attrs: { "data-cds": "ChatComposerChin" } });
        chin.add("button", { text: "Opus 5.5", attrs: { "data-testid": "epitaxy-cds-model-selector" } });
        parts.mode = chin.add("button", { text: "Auto mode", attrs: { "aria-haspopup": "menu" } });
        parts.opens = 0;
        parts.mode.addEventListener("pointerdown", () => {
          parts.opens += 1;
          const list = dom.document.body.add("div", { attrs: { role: "menu" } });
          for (const label of MODES) {
            const item = list.add("div", { attrs: { role: "menuitemradio" }, text: label });
            item.addEventListener("pointerdown", () => { list.remove(); parts.mode.textContent = label; });
          }
        });
      }
      nodes.feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      const toc = dom.document.body.add("div", { class: "epitaxy-toc absolute pointer-events-none" });
      nodes.nav = toc.add("nav", { attrs: { "aria-label": "Session chapters", tabindex: "0" }, rect: { left: 8, top: 48, width: 32, height: 400 } });
      const rail = nodes.nav.add("ol", { attrs: { "aria-hidden": "true" }, class: "flex flex-col" });
      const list = nodes.nav.add("div", { class: "absolute start-0 top-0 invisible opacity-0" }).add("ol", { attrs: { role: "list" } });
      for (const [index, title] of ["Начало", "Середина", "Конец"].entries()) {
        nodes.rail.push(rail.add("li", { class: "h-[8px] flex items-center" }));
        nodes.rail[index].add("span", { class: "block h-[2px] bg-alpha-3" });
        list.add("li").add("button", { attrs: { type: "button", title } }).add("span", { class: "truncate text-body", text: title });
      }
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.inner.chTick();
  return { loaded, nodes };
};
const chaptersSettings = (loaded, nodes) => {
  mouse(loaded, "contextmenu", nodes.rail[0], { button: 2, clientX: 20, clientY: 90 });
  assert.equal(plain(loaded.api.status().chapters).settings, true, "настройка глав открыта");
};

test("главы: настройка вида держит role=dialog только открытой — закрыта Esc или нажатием мимо, и Esc в поле снова наш", () => {
  const { loaded, nodes } = chaptersPage();
  assert.equal(escInField(loaded), true, "до настройки — Esc в поле глотается");
  chaptersSettings(loaded, nodes);
  assert.deepEqual(signs(loaded), ["myclaude-ch-settings"], "открыта — диалог");
  assert.equal(escAt(loaded), true, "Esc закрыл настройку");
  closedClean(loaded, "главы, Esc");
  chaptersSettings(loaded, nodes);
  mouse(loaded, "mousedown", nodes.feed);
  closedClean(loaded, "главы, нажатие мимо");
});

test("главы: Bypass во всех чатах ставится и после настройки вида глав", async () => {
  const { loaded, nodes } = chaptersPage({ bypass: true });
  chaptersSettings(loaded, nodes);
  escAt(loaded);
  let t = 100000;
  for (let i = 0; i < 8; i += 1) { t += 500; loaded.inner.bypassTick(t); await settle(); }
  const view = plain(loaded.api.status().bypassChats);
  assert.equal(loaded.parts.opens, 1, "меню режима открыто один раз");
  assert.equal(loaded.parts.mode.textContent, "Bypass permissions");
  assert.deepEqual([view.result, view.runs], ["ok", 1]);
});

// ---- просмотр фото (12л) -------------------------------------------------------------------------
test("фото: открытый просмотр — диалог, закрытый — без роли; Esc в поле снова наш", () => {
  const nodes = {};
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_overlay-photo",
    html: dom => {
      const parts = dom.composer({});
      const row = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } })
        .add("div", { class: "group/message-row" });
      const img = row.add("span", { attrs: { role: "button", tabindex: "0" } }).add("img", { attrs: { src: "data:image/png;base64,AAA" } });
      img.naturalWidth = 640;
      img.naturalHeight = 1440;
      img.rect = { left: 0, top: 0, width: 71, height: 160 };
      nodes.img = img;
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  for (const type of ["pointerdown", "mousedown", "click"]) mouse(loaded, type, nodes.img, { clientX: 10, clientY: 10 });
  assert.equal(plain(loaded.api.viewer.state()).open, true, "просмотр открыт");
  assert.deepEqual(signs(loaded), ["myclaude-photo-view"], "открыт — диалог");
  assert.equal(escAt(loaded), true, "Esc закрыл просмотр");
  assert.equal(plain(loaded.api.viewer.state()).open, false);
  closedClean(loaded, "фото");
});

// ---- панель PMP (12п³) ---------------------------------------------------------------------------
test("PMP: панель — группа, а не диалог, и открытой, и закрытой; Esc в поле после неё наш", async () => {
  const left = 100, width = 1000, top = 600, y = top + 148;
  const loaded = loadInject({
    title: "Чат", href: "https://claude.ai/epitaxy/local_overlay-pmp",
    html: dom => {
      const parts = dom.composer({ top, left, width });
      const chin = parts.block.add("div", { attrs: { "data-cds": "ChatComposerChin" }, rect: { left, top: y - 4, width, height: 28 } });
      const row = chin.add("div", { class: "flex items-center", rect: { left, top: y, width, height: 20 } });
      row.add("div", { class: "flex items-center self-start", rect: { left, top: y + 2, width: 60, height: 16 } })
        .add("button", { attrs: { "aria-label": "Add" }, rect: { left, top: y + 2, width: 20, height: 16 } });
      const grid = row.add("div", { class: "ms-auto flex items-center", rect: { left: left + width - 100, top: y, width: 100, height: 20 } })
        .add("div", { class: "grid", rect: { left: left + width - 100, top: y, width: 100, height: 20 } });
      grid.add("button", { attrs: { "data-testid": "epitaxy-cds-model-selector" }, text: "Opus 5.5", rect: { left: left + width - 100, top: y + 2, width: 60, height: 16 } });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.win.fetch = () => Promise.resolve({ ok: false, status: 404, json: async () => ({}) });
  const tick = () => { loaded.win.dispatchEvent({ type: "resize" }); loaded.dom.fireKind("timeout"); loaded.dom.fireKind("raf"); };
  tick();
  await settle();
  tick();
  const button = loaded.dom.query("#myclaude-pmp");
  assert.ok(button, "кнопка PMP есть");
  button.dispatchEvent({ type: "click", detail: 1 });
  await settle();
  assert.equal(plain(loaded.api.status().pmp).open, true, "панель открыта");
  assert.deepEqual(signs(loaded), [], "открытая панель PMP — не окно Claude");
  assert.equal(escAt(loaded), true, "Esc закрыл панель");
  assert.equal(plain(loaded.api.status().pmp).open, false);
  closedClean(loaded, "PMP");
});

// ---- окошко «Запустить?» (12т, вынесенное окно) ----------------------------------------------------
test("«Запустить?»: открытое окошко — диалог, закрытое — убрано; Esc в поле после него наш", () => {
  const CHAT = "local_4bea9b89-e7d5-47c9-b6da-f8996ba484e5";
  const sessions = { runBashCommand: () => Promise.resolve({ stdout: "", stderr: "", code: 0 }), reportRunFollowUp: () => {} };
  const loaded = loadInject({
    href: "about:blank", title: "Окно запуска", opener: { "claude.web": { LocalSessions: sessions } },
    storage: { local: { "myclaude-auto-allow-roam": "off" } },
    html: dom => {
      const parts = dom.composer({});
      const panel = dom.document.body.add("div", { class: "epitaxy-chat-panel", rect: { left: 0, top: 0, width: 600, height: 700 } });
      const titlebar = panel.add("div", { class: "epitaxy-titlebar", rect: { left: 80, top: 0, width: 300, height: 32 } });
      titlebar["__reactFiber$test"] = { memoizedProps: { episodeKey: CHAT }, return: null };
      const answer = panel.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" } })
        .add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant_text" } });
      const text = "echo $(id)";
      const block = answer.add("div", { class: "epitaxy-codeblock relative max-w-full" });
      block["__reactFiber$test"] = { memoizedProps: { className: "epitaxy-codeblock" }, return: { memoizedProps: { text, lang: "bash" }, return: null } };
      const inner = block.add("div", { class: "relative" });
      inner.add("div", { class: "epitaxy-diff epitaxy-fence rounded-lg", attrs: { "data-code-text": text } });
      inner.add("div", { class: "pointer-events-none absolute" }).add("div", { class: "pointer-events-auto sticky flex gap-0.75" })
        .add("button", { class: "cds-button ghost size-base", attrs: { "aria-label": "Copy code" } });
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  loaded.win.performance.now = () => 5_000_000;
  loaded.inner.runTick(5_000_000);
  const run = loaded.dom.query("[data-myclaude-run]");
  assert.ok(run, "▶ у сложной команды есть");
  mouse(loaded, "click", run, { isTrusted: true });
  assert.ok(loaded.dom.query("#myclaude-run-confirm"), "окошко открыто");
  assert.deepEqual(signs(loaded), ["myclaude-run-confirm"], "открыто — диалог");
  assert.equal(escAt(loaded), true, "Esc закрыл окошко");
  assert.equal(loaded.dom.query("#myclaude-run-confirm"), null);
  closedClean(loaded, "«Запустить?»");
});

// ---- сторож Esc: только видимые окна и меню Claude --------------------------------------------------
test("сторож Esc: постоянный [data-state=open], скрытый диалог и подсказка Esc не отпускают; видимые меню, диалог, поповер и cmdk — отпускают", () => {
  const nodes = {};
  const loaded = loadInject({
    href: "https://claude.ai/epitaxy/local_overlay-guard",
    html: dom => {
      const parts = dom.composer({});
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript", role: "feed" } });
      // Раскрытая свёртка в ленте (Radix Collapsible) — видима и открыта, но это не окно.
      feed.add("div", { attrs: { "data-state": "open" }, rect: { left: 0, top: 0, width: 600, height: 40 } });
      // Невидимые: закрытый диалог, оставленный в DOM, и постоянный открытый узел.
      dom.document.body.add("div", { attrs: { role: "dialog" } });
      dom.document.body.add("div", { attrs: { "data-state": "open" } });
      // Подсказка Radix (delayed-open) видна, но Esc закрывает не её одну — она не в счёт.
      dom.document.body.add("div", { attrs: { "data-radix-popper-content-wrapper": "" } })
        .add("div", { attrs: { "data-state": "delayed-open", role: "tooltip" }, rect: { left: 10, top: 10, width: 80, height: 20 } });
      nodes.body = dom.document.body;
      return parts;
    },
  });
  assert.equal(loaded.error, null, String(loaded.error?.stack ?? loaded.error));
  assert.equal(blocked(loaded), 0);
  assert.equal(escInField(loaded), true, "невидимые и не-окна сторожа не выключают");
  assert.equal(blocked(loaded), 1);
  const shown = { left: 100, top: 100, width: 200, height: 120 };
  const popups = [
    ["меню", () => nodes.body.add("div", { attrs: { role: "menu" }, rect: shown })],
    ["список", () => nodes.body.add("div", { attrs: { role: "listbox" }, rect: shown })],
    ["диалог", () => nodes.body.add("div", { attrs: { role: "dialog" }, rect: shown })],
    ["подтверждение", () => nodes.body.add("div", { attrs: { role: "alertdialog" }, rect: shown })],
    ["поповер", () => nodes.body.add("div", { attrs: { "data-radix-popper-content-wrapper": "" } }).add("div", { attrs: { "data-state": "open" }, rect: shown })],
    ["поповер cds", () => nodes.body.add("div", { attrs: { "data-cds": "Popover" }, rect: shown })],
    ["палитра cmdk", () => nodes.body.add("div", { attrs: { "cmdk-root": "" }, rect: shown })],
  ];
  for (const [what, make] of popups) {
    const node = make();
    assert.equal(escInField(loaded), false, `${what} Claude открыто — Esc его закрывает`);
    node.rect = { left: 0, top: 0, width: 0, height: 0 };
    assert.equal(escInField(loaded), true, `${what} скрыто — Esc снова глотается`);
    (node.parentElement?.getAttribute?.("data-radix-popper-content-wrapper") === "" ? node.parentElement : node).remove();
  }
  assert.equal(blocked(loaded), 1 + popups.length, "счёт — только проглоченные");
});
