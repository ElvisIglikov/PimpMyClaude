// Лимиты подписки и «работает ли чат» для Пимпа (раздел 12ж¹ inject.js, WF87).
//
// Проверяется контракт, который возьмёт приложение (батч C):
//   1) разбор ответа GET /api/organizations/<org>/usage — эталон снят живой
//      разведкой 25.09 (org id в эталоне не нужен и не хранится);
//   2) тариф из /api/organizations/<org> (rate_limit_tier);
//   3) разбор aria-label кружка контекста — там ОДИН лимит, имя разбираем;
//   4) главное окно ходит в API не чаще раза в минуту, кладёт ответ в
//      localStorage без org id; попап отвечает из кэша, старый кэш — не ответ;
//   5) отказ сети → null-поля без исключения;
//   6) working — по кнопке стопа и Code, и обычного чата;
//   7) chats() несёт working (наши страницы) и limits (только главное окно).
import test from "node:test";
import assert from "node:assert/strict";
import { loadInject, loadInner, plain } from "./load.mjs";

const ORG = "11111111-2222-3333-4444-555555555555";
const LIMITS_KEY = "myclaude-limits-v1";

// Ответ /usage, как его отдал claude.ai 25.09 (хвост лишних полей срезан).
const USAGE_BODY = {
  five_hour: { utilization: 5.0, resets_at: "2099-09-25T18:10:00.467734+00:00", limit_dollars: null, used_dollars: null, remaining_dollars: null, locked_reason: null },
  seven_day: { utilization: 2.0, resets_at: "2099-10-02T03:00:00.467761+00:00", limit_dollars: null, used_dollars: null, remaining_dollars: null, locked_reason: null },
  seven_day_oauth_apps: null, seven_day_opus: null, seven_day_sonnet: null,
  nimbus_quill: { utilization: 0.0, resets_at: null, limit_dollars: null, used_dollars: null, remaining_dollars: null, locked_reason: null },
  extra_usage: { is_enabled: false, monthly_limit: null, used_credits: null, utilization: null },
  limits: [
    { kind: "session", group: "session", percent: 5, severity: "normal", resets_at: "2099-09-25T18:10:00.467734+00:00", scope: null, is_active: true },
    { kind: "weekly_all", group: "weekly", percent: 2, severity: "normal", resets_at: "2099-10-02T03:00:00.467761+00:00", scope: null, is_active: false },
    { kind: "weekly_scoped", group: "weekly", percent: 0, severity: "normal", resets_at: "2099-10-02T03:00:00+00:00", scope: { model: { id: null, display_name: "Fable" }, surface: null }, is_active: false },
  ],
  spend: { used: { amount_minor: 0, currency: "USD", exponent: 2 }, limit: null, percent: 0 },
  member_dashboard_available: false,
};
const ORG_BODY = { uuid: ORG, name: "someone@example.com's Organization", rate_limit_tier: "default_claude_max_20x", plan_display_name: null, plan_display_label: null, capabilities: ["claude_max", "chat"] };

const flush = async () => { for (let i = 0; i < 10; i += 1) await new Promise(resolve => setImmediate(resolve)); };

// Заглушка fetch: отвечает по адресу, считает вызовы.
const fakeFetch = (routes, calls) => async (url, init) => {
  calls.push({ url: String(url), credentials: init?.credentials ?? null });
  const hit = Object.entries(routes).find(([tail]) => String(url).endsWith(tail));
  if (!hit) return { ok: false, status: 404, json: async () => ({}) };
  const value = hit[1];
  if (value instanceof Error) throw value;
  return { ok: true, status: 200, json: async () => JSON.parse(JSON.stringify(value)) };
};

const mainWindow = ({ html = null, storage = {} } = {}) => {
  const loaded = loadInject({ href: "https://claude.ai/epitaxy/local_aaa", title: "Trelvis", html, storage });
  loaded.document.cookie = `anthropic-device-id=x; lastActiveOrg=${ORG}; other=1`;
  return loaded;
};

test("разбор ответа API: пять часов, неделя, Fable; момент сброса в мс", () => {
  const { inner } = loadInner();
  const got = plain(inner.limitsFromApi(USAGE_BODY));
  assert.deepEqual(got, {
    fiveHour: { used: 5, resetsAt: Date.parse("2099-09-25T18:10:00.467Z") },
    weekly: { used: 2, resetsAt: Date.parse("2099-10-02T03:00:00.467Z") },
    fable: { used: 0, resetsAt: Date.parse("2099-10-02T03:00:00Z") },
  });
  // Окон five_hour/seven_day нет — берём список limits[].
  const listOnly = plain(inner.limitsFromApi({ limits: USAGE_BODY.limits.map(item => ({ ...item, percent: item.percent + 40 })) }));
  assert.equal(listOnly.fiveHour.used, 45);
  assert.equal(listOnly.weekly.used, 42);
  assert.equal(listOnly.fable.used, 40);
  // Зажим и мусор.
  assert.equal(inner.limitsFromApi({ five_hour: { utilization: 130, resets_at: "не дата" } }).fiveHour.used, 100);
  assert.equal(inner.limitsFromApi({ five_hour: { utilization: 130, resets_at: "не дата" } }).fiveHour.resetsAt, null);
  assert.equal(inner.limitsFromApi({ five_hour: { utilization: null } }), null);
  assert.equal(inner.limitsFromApi(null), null);
  assert.equal(inner.limitsFromApi("oops"), null);
  assert.equal(inner.limitsFromApi({}), null);
});

test("тариф: подпись Claude, иначе rate_limit_tier", () => {
  const { inner } = loadInner();
  assert.equal(inner.limitsPlan(ORG_BODY), "Max 20x");
  assert.equal(inner.limitsPlan({ rate_limit_tier: "default_claude_max_5x" }), "Max 5x");
  assert.equal(inner.limitsPlan({ rate_limit_tier: "default_claude_pro" }), "Pro");
  assert.equal(inner.limitsPlan({ plan_display_label: "Max (20x)", rate_limit_tier: "x" }), "Max (20x)");
  assert.equal(inner.limitsPlan({ rate_limit_tier: "default_claude_ai" }), null);
  assert.equal(inner.limitsPlan(null), null);
});

test("aria-label кружка: лимит по имени, английские формы сброса", () => {
  const { inner } = loadInner();
  const now = new Date(2026, 8, 25, 19, 0, 0, 0).getTime(); // пятница, 19:00 по местному
  const hour = plain(inner.limitsFromLabel("Usage: Context 126.9k / 1M (13%), 4% of 5-hour limit, Resets in 4 hr 9 min", now));
  assert.deepEqual(hour, { kind: "fiveHour", limit: { used: 4, resetsAt: now + (4 * 60 + 9) * 60000 } });
  const week = plain(inner.limitsFromLabel("Usage: Context 324.7k / 1M (32%), Weekly · all models: 77%, Resets Fri 8:00 AM", now));
  assert.equal(week.kind, "weekly");
  assert.equal(week.limit.used, 77);
  // Пятница 19:00 → следующая пятница 08:00.
  assert.equal(week.limit.resetsAt, new Date(2026, 9, 2, 8, 0, 0, 0).getTime());
  const fable = plain(inner.limitsFromLabel("Usage: Context 1k / 1M (0%), Weekly · Fable: 12%, Resets in 59 min", now));
  assert.deepEqual(fable, { kind: "fable", limit: { used: 12, resetsAt: now + 59 * 60000 } });
  // Сброса нет или форма незнакомая — процент остаётся, момент null.
  assert.deepEqual(plain(inner.limitsFromLabel("Usage: Context 1k / 1M (0%), 91% of 5-hour limit", now)),
    { kind: "fiveHour", limit: { used: 91, resetsAt: null } });
  // Чужой лимит и мусор — null.
  assert.equal(inner.limitsFromLabel("Usage: Context 1k / 1M (0%), Weekly · Sonnet: 12%, Resets Fri 8:00 AM", now), null);
  assert.equal(inner.limitsFromLabel("Usage: Context 324.7k / 1M (32%)", now), null);
  assert.equal(inner.limitsFromLabel(null, now), null);
  assert.equal(inner.limitsFromLabel("", now), null);
});

test("главное окно: запрос в API не чаще раза в минуту, кэш без org id", async () => {
  const loaded = mainWindow();
  const calls = [];
  loaded.win.fetch = fakeFetch({ [`/organizations/${ORG}`]: ORG_BODY, [`/organizations/${ORG}/usage`]: USAGE_BODY }, calls);
  const first = plain(loaded.api.limits());
  // Первый вопрос сети не ждёт: полей нет, запрос ушёл в фон.
  assert.equal(first.source, null);
  assert.equal(first.weekly, null);
  await flush();
  const second = plain(loaded.api.limits());
  assert.equal(second.source, "api");
  assert.equal(second.v, 1);
  assert.equal(second.plan, "Max 20x");
  assert.equal(second.weekly.used, 2);
  assert.equal(second.fiveHour.used, 5);
  assert.equal(second.fable.used, 0);
  assert.equal(typeof second.at, "number");
  assert.deepEqual(Object.keys(second), ["v", "at", "plan", "fiveHour", "weekly", "fable", "source"]);
  assert.deepEqual(calls.map(call => call.url), [`/api/organizations/${ORG}`, `/api/organizations/${ORG}/usage`]);
  assert.ok(calls.every(call => call.credentials === "include"));
  // Кэш лёг, org id и почты в нём нет; в status() — тоже.
  const raw = loaded.win.localStorage.getItem(LIMITS_KEY);
  assert.ok(raw && raw.includes("\"weekly\""));
  assert.ok(!raw.includes(ORG) && !raw.includes("@"));
  const status = loaded.api.status();
  assert.equal(status.limits.source, "api");
  assert.ok(!JSON.stringify(status).includes(ORG));
  // Минута не прошла — второго запроса нет.
  loaded.api.limits();
  await flush();
  assert.equal(calls.length, 2);
  // status() в сеть не ходит никогда.
  // Часы страницы — свои у контекста vm: сдвигаем их изнутри.
  loaded.run("globalThis.__limitsNow = Date.now; Date.now = () => globalThis.__limitsNow() + 61000;");
  try {
    loaded.api.status();
    await flush();
    assert.equal(calls.length, 2, "status() не заводит запрос");
    loaded.api.limits();
    await flush();
    assert.equal(calls.length, 3, "через минуту — снова /usage (тариф — раз в час)");
    assert.ok(calls[2].url.endsWith("/usage"));
  } finally {
    loaded.run("Date.now = globalThis.__limitsNow;");
  }
});

test("попап: отвечает из кэша главного окна и сам в сеть не ходит; старый кэш — не ответ", async () => {
  const at = Date.now() - 30000;
  const record = { v: 1, at, plan: "Max 20x", fiveHour: { used: 5, resetsAt: at + 3600000 }, weekly: { used: 23, resetsAt: at + 86400000 }, fable: null };
  const popup = loadInject({ href: "about:blank", title: "Bro Flow", storage: { local: { [LIMITS_KEY]: JSON.stringify(record) } } });
  const calls = [];
  popup.win.fetch = fakeFetch({ "/usage": USAGE_BODY }, calls);
  popup.document.cookie = `lastActiveOrg=${ORG}`;
  const got = plain(popup.api.limits());
  assert.deepEqual(got, { v: 1, at, plan: "Max 20x", fiveHour: record.fiveHour, weekly: record.weekly, fable: null, source: "cache" });
  await flush();
  assert.equal(calls.length, 0, "попап в API не ходит");
  // chats() попапа: working есть, limits нет.
  const answer = await popup.api.chats({ nonce: "p" });
  assert.equal(answer.kind, "popout");
  assert.equal(answer.working, false);
  assert.ok(!("limits" in answer));

  const stale = { ...record, at: Date.now() - 11 * 60000 };
  const old = loadInject({ href: "about:blank", title: "Bro Flow", storage: { local: { [LIMITS_KEY]: JSON.stringify(stale) } } });
  assert.deepEqual(plain(old.api.limits()), { v: 1, at: null, plan: null, fiveHour: null, weekly: null, fable: null, source: null });
  const broken = loadInject({ href: "about:blank", title: "Bro Flow", storage: { local: { [LIMITS_KEY]: "{не json" } } });
  assert.equal(broken.api.limits().source, null);
});

test("сброс уже прошёл: лимит отдаётся как {used: 0, resetsAt: null} (гейт 1 WF87, B3)", () => {
  const now = Date.now();
  const at = now - 5 * 60000;
  const record = { v: 1, at, plan: "Max 20x", fiveHour: { used: 95, resetsAt: now - 60000 }, weekly: { used: 23, resetsAt: now + 86400000 }, fable: { used: 40, resetsAt: null } };
  const popup = loadInject({ href: "about:blank", title: "Bro Flow", storage: { local: { [LIMITS_KEY]: JSON.stringify(record) } } });
  const got = plain(popup.api.limits());
  assert.equal(got.source, "cache");
  assert.deepEqual(got.fiveHour, { used: 0, resetsAt: null }, "95 % до сброса — уже не правда");
  assert.deepEqual(got.weekly, record.weekly, "неделя не сброшена — как есть");
  assert.deepEqual(got.fable, record.fable, "момента нет — процент как есть");
  assert.deepEqual(plain(popup.api.status().limits).fiveHour, { used: 0, resetsAt: null });
  // Подпись кружка: сброс «через 0 мин» — уже наступил.
  const ring = loadInject({ href: "https://claude.ai/epitaxy/local_aaa", html: dom => dom.document.body.add("button", {
    attrs: { "data-cds": "Button", "aria-haspopup": "dialog", "aria-label": "Usage: Context 1k / 1M (0%), 97% of 5-hour limit, Resets in 0 min" },
  }) });
  const label = plain(ring.api.limits());
  assert.equal(label.source, "label");
  assert.deepEqual(label.fiveHour, { used: 0, resetsAt: null });
});

test("отказ сети: null-поля, без исключения, и повтор не раньше минуты", async () => {
  for (const make of [
    calls => async url => { calls.push(url); throw new TypeError("Failed to fetch"); },
    calls => url => { calls.push(url); throw new Error("sync boom"); },
    calls => async url => { calls.push(url); return { ok: false, status: 500, json: async () => ({}) }; },
    calls => async url => { calls.push(url); return { ok: true, status: 200, json: async () => { throw new SyntaxError("bad json"); } }; },
  ]) {
    const loaded = mainWindow();
    const calls = [];
    loaded.win.fetch = make(calls);
    let got = null;
    assert.doesNotThrow(() => { got = plain(loaded.api.limits()); });
    await flush();
    assert.doesNotThrow(() => { got = plain(loaded.api.limits()); });
    assert.deepEqual(got, { v: 1, at: null, plan: null, fiveHour: null, weekly: null, fable: null, source: null });
    const answer = await loaded.api.chats({ nonce: "n" });
    assert.equal(answer.limits.source, null);
    assert.ok(calls.length >= 1 && calls.length <= 2, "тариф и /usage — один круг, не больше");
  }
  // Нет ни куки, ни fetch — просто null.
  const bare = loadInject({ href: "https://claude.ai/epitaxy/local_aaa" });
  assert.equal(bare.api.limits().source, null);
});

test("без API: подпись кружка, потом открытая панель (aria-valuenow)", () => {
  const ring = dom => dom.document.body.add("button", {
    attrs: { "data-cds": "Button", "aria-haspopup": "dialog", "aria-label": "Usage: Context 126.9k / 1M (13%), 4% of 5-hour limit, Resets in 3 hr 49 min" },
  });
  const panel = dom => {
    const root = dom.document.body.add("div", { attrs: { role: "dialog", "data-cds": "Popover", id: "usage-panel" } });
    root.add("a", { attrs: { href: "/settings/usage" } });
    const limit = (id, label, pct) => {
      const block = root.add("div", { class: "flex flex-col" });
      const row = block.add("div", {});
      dom.leaf(row, "span", label, { id });
      block.add("div", { attrs: { role: "progressbar", "aria-labelledby": id, "aria-valuenow": pct } });
    };
    limit("h", "5-hour limit", "9");
    limit("w", "Weekly · all models", "66");
    limit("f", "Weekly · Fable", "72");
  };
  const labelOnly = loadInject({ href: "https://claude.ai/epitaxy/local_aaa", html: ring });
  const one = plain(labelOnly.api.limits());
  assert.equal(one.source, "label");
  assert.equal(one.fiveHour.used, 4);
  assert.equal(one.weekly, null);

  const both = loadInject({ href: "https://claude.ai/epitaxy/local_aaa", html: dom => { ring(dom); panel(dom); } });
  const got = plain(both.api.limits());
  assert.equal(got.source, "label");
  assert.equal(got.fiveHour.used, 4, "подпись старше панели");
  assert.equal(got.weekly.used, 66);
  assert.equal(got.fable.used, 72);

  const panelOnly = loadInject({ href: "https://claude.ai/epitaxy/local_aaa", html: panel });
  const p = plain(panelOnly.api.limits());
  assert.equal(p.source, "panel");
  assert.deepEqual([p.fiveHour.used, p.weekly.used, p.fable.used], [9, 66, 72]);
});

test("working: кнопка стопа Code и обычного чата; status() и chats()", async () => {
  const loaded = mainWindow();
  assert.equal(loaded.api.status().working, false);
  let answer = await loaded.api.chats({ nonce: "w0" });
  assert.equal(answer.working, false);
  assert.ok("limits" in answer, "главное окно несёт limits");
  assert.deepEqual(Object.keys(answer.limits), ["v", "at", "plan", "fiveHour", "weekly", "fable", "source"]);

  const code = loaded.document.body.add("button", { attrs: { "data-testid": "code-prompt-stop", "aria-label": "Stop" } });
  assert.equal(loaded.api.status().working, true);
  answer = await loaded.api.chats({ nonce: "w1" });
  assert.equal(answer.working, true);
  code.remove();
  assert.equal(loaded.api.status().working, false);

  loaded.document.body.add("button", { attrs: { "data-testid": "chat-input-stop", "aria-label": "Stop response" } });
  assert.equal(loaded.api.status().working, true);
  answer = await loaded.api.chats({ nonce: "w2" });
  assert.equal(answer.working, true);

  // Чужая страница — ни working, ни limits.
  const other = loadInject({ href: "data:text/html,x" });
  const miss = await other.api.chats({ nonce: "o" });
  assert.equal(miss.kind, "other");
  assert.ok(!("working" in miss) && !("limits" in miss));
});

test("chats(): working, autoContinue, galleryCounted, sendDelaySetting и limits — после frame/mic и перед themes", async () => {
  const loaded = loadInject({ href: "https://claude.ai/epitaxy/local_aaa", title: "Trelvis", geometry: { frame: [0, 25, 800, 600] } });
  const keys = Object.keys(await loaded.api.chats({ nonce: "k" }));
  const at = keys.indexOf("working");
  assert.deepEqual(keys.slice(at - 2, at + 5), ["frame", "mic", "working", "autoContinue", "galleryCounted", "sendDelaySetting", "limits"]);
  if (keys.includes("themes")) assert.equal(keys[at + 5], "themes");
});
