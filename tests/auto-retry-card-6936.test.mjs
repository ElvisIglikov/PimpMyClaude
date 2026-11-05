// #6936 — карточка ошибки Claude Desktop в том виде, как её рисует фронт (снято из кэша фронта 20.10.2026):
// заголовок, подсказка, свёрнутое «View details» с сырым текстом ошибки, кнопка «Try again».
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, plain } from "./load.mjs";

const T0 = Date.UTC(2026, 9, 20, 18, 30, 0);
const MIN = 60000;
const box = (top, height = 40) => ({ left: 10, top, width: 600, height });
const RAW_NET = "API Error: Can't reach the API server — check your internet or DNS (ENOTFOUND)";

function page({ headline, hint, details = null, open = false, retry = "Try again", extra = [], olderRetry = false }) {
  const p = loadInject({
    storage: { local: { "myclaude.autoRetry": "true", "myclaude.autoRetryEvery": "5" } },
    html: dom => {
      const feed = dom.document.body.add("div", { attrs: { "data-testid": "epitaxy-virtual-transcript" }, rect: box(0, 600) });
      if (olderRetry) { const f = feed.add("div", { rect: box(0, 20) }); f.add("span", { text: "Couldn’t load older messages.", rect: box(0, 20) }); f.add("button", { text: "Retry", rect: box(0, 20) }); }
      const rows = feed.add("div", { attrs: { "data-testid": "transcript-rows" }, rect: box(20, 580) });
      rows.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "human", "data-index": "0" }, rect: box(30), text: "Сделай отчёт" });
      const row = rows.add("div", { attrs: { "data-testid": "transcript-row", "data-perf-row": "assistant", "data-index": "1", "data-last-message": "true" }, rect: box(80, 200) });
      const entry = row.add("div", { rect: box(80, 200) }).add("div", { attrs: { "data-epitaxy-entry": "x" }, rect: box(80, 200) });
      const card = entry.add("div", { class: "epitaxy-card-outline-layer flex w-fit flex-col", rect: box(80, 200) });
      const head = card.add("div", { class: "flex items-center gap-md bg-alpha-1 px-lg py-md", rect: box(80, 30) });
      head.add("svg", { rect: box(80, 16) });
      head.add("span", { class: "min-w-0 grow text-body text-primary", text: headline, rect: box(80, 20) });
      const body = card.add("div", { class: "flex flex-col gap-md px-lg pt-lg pb-md", rect: box(110, 30) });
      body.add("span", { class: "text-body text-secondary whitespace-pre-line", text: hint, rect: box(110, 20) });
      const root = card.add("div", { class: "flex flex-col self-stretch", rect: box(150, 40) });
      const bar = root.add("div", { class: "flex min-w-0 max-w-full flex-wrap items-center gap-x-lg gap-y-sm px-lg pb-lg pt-md", rect: box(150, 30) });
      if (details) bar.add("button", { attrs: { "aria-expanded": open ? "true" : "false" }, rect: box(150, 24) }).add("span", { text: "View details", rect: box(150, 20) });
      const acts = bar.add("div", { class: "ms-auto flex min-w-0 max-w-full flex-wrap items-center justify-end gap-sm", rect: box(150, 30) });
      for (const label of extra) acts.add("button", { text: label, rect: { left: 300, top: 152, width: 120, height: 24 } });
      const button = acts.add("button", { text: retry, rect: { left: 450, top: 152, width: 80, height: 24 } });
      button.presses = 0; button.addEventListener("click", () => { button.presses += 1; });
      if (details && open) root.add("div", { rect: box(190, 40) }).add("div", { class: "border-t px-lg py-lg", rect: box(190, 40) }).add("span", { class: "whitespace-pre-wrap", text: details, rect: box(190, 30) });
      return { ...dom.composer({ text: "" }), button };
    },
  });
  assert.equal(p.error, null, String(p.error?.stack ?? p.error));
  p.run(`globalThis.__now = ${T0}; Date.now = () => globalThis.__now;`);
  p.at = ms => { p.run(`globalThis.__now = ${ms}`); p.inner.autoRetryTick(ms); };
  p.ar = () => plain(p.api.status().autoRetry);
  p.go = () => { p.at(T0); const first = p.ar(); p.at(T0 + 5 * MIN); const after = p.ar(); const presses = p.parts.button.presses; p.api.dispose(); return { first, after, presses }; };
  return p;
}
const HINT_NET = "Check your internet connection, VPN, or proxy and try again.";
const HINT_SERVER = "The server returned an error while handling this message. It’s usually temporary.";

for (const [name, card] of [
  ["обрыв сети, детали свёрнуты", { headline: "Connection problem", hint: HINT_NET, details: RAW_NET }],
  ["обрыв сети, детали раскрыты", { headline: "Connection problem", hint: HINT_NET, details: RAW_NET, open: true }],
  ["ответ оборвался", { headline: "Connection went idle", hint: "The response stopped before finishing. Try again in a moment." }],
  ["ошибка сервера", { headline: "Server error", hint: HINT_SERVER }],
  ["перегрузка, рядом «Try again with …»", { headline: "Service is busy", hint: "Try again in a moment, or switch to a different model.", extra: ["Try again with Sonnet"] }],
  ["«Retry» старых сообщений вверху ленты", { headline: "Server error", hint: HINT_SERVER, olderRetry: true }],
]) test(`карточка Claude: ${name} — через 5 мин одно нажатие «Try again»`, () => {
  assert.equal(page(card).go().presses, 1);
});

for (const [headline, hint] of [
  ["Usage limit reached", "You’ve reached your usage limit. Try again after your limit resets."],
  ["Authentication failed", "Sign in again to continue."],
  ["Your context window is full", "This chat is too long to continue. Compact it to summarize earlier messages and keep going, rewind to an earlier point, or start a new chat."],
  ["An API error occurred", "invalid_request_error: messages.0 400"],
]) test(`карточка Claude: «${headline}» — не жмём`, () => {
  assert.equal(page({ headline, hint }).go().presses, 0);
});
