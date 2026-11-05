  // ---- 12ж¹. Лимиты подписки и «работает ли чат» для Пимпа (WF87) -----------
  // Значок Пимпа у часов показывает, сколько лимита осталось, а «самое время
  // обновить Claude» ждёт, пока ни один чат не работает. Спрашивает приложение
  // тем же кругом probe, что и «кто этот чат» (раздел 12в): поля working и
  // limits едут в ответе chats(); limits() и status().limits/working — для гейта.
  //
  // Откуда цифры (разведка 25.09): панель лимитов Claude берёт их запросом
  // GET /api/organizations/<org>/usage своего origin — five_hour и seven_day
  // ({utilization 0…100, resets_at ISO}) и список limits[] (kind session /
  // weekly_all / weekly_scoped, у последнего scope.model.display_name «Fable»).
  // Тот же запрос шлёт ТОЛЬКО главное окно и не чаще раза в минуту; ответ без
  // org id ложится в localStorage (у попапа он общий с главным окном), попапы
  // отвечают из него. Кэша нет — подпись кружка контекста (там ОДИН лимит, и не
  // всегда недельный: имя разбираем), потом открытая панель (aria-valuenow
  // полос; тексты там уже русские, имя — из запомненного оригинала 12ж).
  // Ошибка — null-поля, не исключение. Своих таймеров и подписок нет: запрос
  // заводит сам вопрос, ответ достаётся следующему кругу. Org id и почта не
  // уходят ни в localStorage, ни в status(): тот ложится на диск.
  const LIMITS_KEY = "myclaude-limits-v1";
  const LIMITS_API_EVERY_MS = 60000;
  // Кэш старше — не ответ: главное окно закрыто или сеть пропала надолго, а
  // процент получасовой давности на значке врал бы уверенно.
  const LIMITS_CACHE_TTL_MS = 10 * 60000;
  // Тариф меняется редко — спрашиваем раз в час.
  const LIMITS_PLAN_EVERY_MS = 60 * 60000;
  // Повисший запрос держит очередь не дольше этого (таймера не заводим).
  const LIMITS_HANG_MS = 30000;
  const LIMITS_ORG_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  // Кнопка стопа: у Code и у обычного чата свои (разведка 25.09, бандл Claude).
  const WORKING_SELECTOR = `${AUTO_STOP_SELECTOR}, [data-testid="chat-input-stop"]`;
  const limitsState = { tried: 0, busy: 0, last: null, plan: null, planAt: 0, fails: 0 };
  track(() => { limitsState.busy = 0; });

  // ---- чистые разборы (тестируются через люк) ----
  const limitsPct = value => {
    if (value == null || value === "") return null;
    const number = Number(value);
    return Number.isFinite(number) ? Math.max(0, Math.min(100, Math.round(number))) : null;
  };
  const limitsTime = value => {
    const at = typeof value === "number" ? value : typeof value === "string" ? Date.parse(value) : NaN;
    return Number.isFinite(at) ? at : null;
  };
  const limitsOne = (used, resets) => {
    const pct = limitsPct(used);
    return pct == null ? null : { used: pct, resetsAt: limitsTime(resets) };
  };
  // Ответ /usage → {fiveHour, weekly, fable}; ничего не узнали — null.
  const limitsFromApi = body => {
    if (!body || typeof body !== "object") return null;
    const list = Array.isArray(body.limits) ? body.limits : [];
    const item = test => list.find(entry => entry && typeof entry === "object" && test(entry)) ?? null;
    const fromItem = entry => (entry ? limitsOne(entry.percent, entry.resets_at) : null);
    const fromWindow = win => (win && typeof win === "object" ? limitsOne(win.utilization, win.resets_at) : null);
    const fiveHour = fromWindow(body.five_hour) ?? fromItem(item(entry => entry.kind === "session"));
    const weekly = fromWindow(body.seven_day) ?? fromItem(item(entry => entry.kind === "weekly_all"));
    const fable = fromItem(item(entry => entry.kind === "weekly_scoped" &&
      /^fable$/i.test(String(entry.scope?.model?.display_name ?? "").trim())));
    return fiveHour || weekly || fable ? { fiveHour, weekly, fable } : null;
  };
  // Тариф из /api/organizations/<org>: подпись, если Claude её дал, иначе
  // rate_limit_tier («default_claude_max_20x» → «Max 20x»).
  const limitsPlan = org => {
    if (!org || typeof org !== "object") return null;
    for (const key of ["plan_display_label", "plan_display_name"]) {
      const text = org[key];
      if (typeof text === "string" && text.trim()) return text.trim().slice(0, 40);
    }
    const tier = String(org.rate_limit_tier ?? "").toLowerCase();
    const max = /max(?:_(\d+x))?/.exec(tier);
    if (max) return max[1] ? `Max ${max[1]}` : "Max";
    if (/(^|_)pro(_|$)/.test(tier)) return "Pro";
    if (/team/.test(tier)) return "Team";
    if (/enterprise/.test(tier)) return "Enterprise";
    return null;
  };
  // Имя лимита из подписи 12ж → поле ответа. Незнакомое — null.
  const limitsKindOf = name => {
    const label = usageLabel(name);
    if (!label) return null;
    if (label.kind === "hour5") return "fiveHour";
    if (label.kind === "weekAll") return "weekly";
    return /^fable$/i.test(label.text) ? "fable" : null;
  };
  // aria-label кружка: «Usage: Context 126.9k / 1M (13%), 4% of 5-hour limit,
  // Resets in 3 hr 49 min» или «…, Weekly · all models: 77%, Resets Fri 8:00 AM».
  // → {kind, limit:{used, resetsAt}}; не разобрали — null.
  const limitsFromLabel = (text, now) => {
    const raw = String(text ?? "");
    let name = null;
    let used = null;
    const of = /(\d+(?:\.\d+)?)\s*%\s+(?:of|от)\s+([^,]+)/i.exec(raw); // #11618: «4% от 5-часового лимита»
    const named = of ? null : /(?:^|,)\s*([^,:]+?)\s*:\s*(\d+(?:\.\d+)?)\s*%/.exec(raw);
    if (of) { used = of[1]; name = of[2]; } else if (named) { name = named[1]; used = named[2]; }
    const kind = name == null ? null : limitsKindOf(name.trim());
    const pct = limitsPct(used);
    if (!kind || pct == null) return null;
    const reset = /(?:resets?|сброс:?)\s+[^,]+/i.exec(raw);
    let resetsAt = null;
    try { resetsAt = reset ? usageReset(reset[0].trim(), now)?.at ?? null : null; } catch {}
    return { kind, limit: { used: pct, resetsAt } };
  };

  // ---- источники ----
  const limitsFromPanel = () => {
    const panel = usageFind();
    if (!panel) return null;
    const out = {};
    for (const block of usageBlocks(panel)) {
      const raw = usageRaw(block.label);
      const label = raw == null ? null : usageLabel(raw);
      const kind = label ? limitsKindOf(raw) : null;
      if (!kind || out[kind]) continue;
      const used = limitsPct(block.bar.getAttribute("aria-valuenow"));
      if (used == null) continue;
      const kept = usageState.resets.get(label.kind === "week" ? `week:${label.text}` : label.kind);
      out[kind] = { used, resetsAt: kept?.at ?? null };
    }
    return Object.keys(out).length ? out : null;
  };
  const limitsCacheRead = now => {
    try {
      const record = JSON.parse(localStorage.getItem(LIMITS_KEY) ?? "null");
      if (!record || typeof record !== "object" || !Number.isFinite(record.at)) return null;
      if (now - record.at > LIMITS_CACHE_TTL_MS || record.at > now + LIMITS_API_EVERY_MS) return null;
      const pick = value => (value && typeof value === "object" ? limitsOne(value.used, value.resetsAt) : null);
      return {
        at: record.at, plan: typeof record.plan === "string" ? record.plan.slice(0, 40) : null,
        fiveHour: pick(record.fiveHour), weekly: pick(record.weekly), fable: pick(record.fable),
      };
    } catch { return null; }
  };
  // Org id — из куки lastActiveOrg (её ставит сам claude.ai), запасной путь —
  // адреса уже сделанных страницей запросов. Нигде не сохраняется.
  const limitsOrg = () => {
    try {
      const match = /(?:^|;\s*)lastActiveOrg=([^;]+)/.exec(String(document.cookie ?? ""));
      const id = match ? decodeURIComponent(match[1]).trim() : "";
      if (LIMITS_ORG_RE.test(id)) return id;
    } catch {}
    try {
      for (const entry of performance.getEntriesByType("resource")) {
        const hit = /\/api\/organizations\/([0-9a-f-]{36})\//i.exec(String(entry?.name ?? ""));
        if (hit && LIMITS_ORG_RE.test(hit[1])) return hit[1];
      }
    } catch {}
    return null;
  };
  const limitsJson = async url => {
    const reply = await fetch(url, { credentials: "include", headers: { accept: "application/json" } });
    if (!reply?.ok) throw new Error(`http ${reply?.status}`);
    return reply.json();
  };
  // Запрос в фоне: вопрос не ждёт сети, свежий ответ достанется следующему.
  const limitsRefresh = () => {
    if (!isMainWindow() || typeof fetch !== "function") return;
    const now = Date.now();
    if (limitsState.busy && now - limitsState.busy < LIMITS_HANG_MS) return;
    if (now - limitsState.tried < LIMITS_API_EVERY_MS) return;
    const org = limitsOrg();
    if (!org) return;
    limitsState.tried = now;
    limitsState.busy = now;
    const base = `/api/organizations/${encodeURIComponent(org)}`;
    const wantPlan = now - limitsState.planAt >= LIMITS_PLAN_EVERY_MS;
    if (wantPlan) limitsState.planAt = now;
    (async () => {
      try {
        if (wantPlan) { try { limitsState.plan = limitsPlan(await limitsJson(base)) ?? limitsState.plan; } catch {} }
        const parsed = limitsFromApi(await limitsJson(`${base}/usage`));
        if (!state.alive) return;
        if (!parsed) { limitsState.fails += 1; return; }
        const record = { v: 1, at: Date.now(), plan: limitsState.plan, ...parsed };
        limitsState.last = record;
        try { localStorage.setItem(LIMITS_KEY, JSON.stringify(record)); } catch {}
      } catch { limitsState.fails += 1; } finally { limitsState.busy = 0; }
    })();
  };
  // Ответ: {v:1, at, plan, fiveHour, weekly, fable, source}; лимит —
  // {used 0…100, resetsAt ms|null} или null; source — api | cache | label |
  // panel | null. refresh — можно ли завести запрос (status() не заводит).
  const limitsNow = refresh => {
    const empty = { v: 1, at: null, plan: null, fiveHour: null, weekly: null, fable: null, source: null };
    // Сброс уже прошёл — старый процент не отдаём (кэш живёт до 10 мин, подпись и панель
    // могут нести запомненный момент сброса): {used: 0, resetsAt: null}.
    const live = (limit, now) => (limit && limit.resetsAt != null && limit.resetsAt <= now ? { used: 0, resetsAt: null } : limit ?? null);
    try {
      if (refresh) limitsRefresh();
      const now = Date.now();
      const own = limitsState.last && now - limitsState.last.at <= LIMITS_CACHE_TTL_MS ? limitsState.last : null;
      const kept = own ?? limitsCacheRead(now);
      if (kept) {
        return {
          v: 1, at: kept.at, plan: kept.plan ?? null,
          fiveHour: live(kept.fiveHour, now), weekly: live(kept.weekly, now), fable: live(kept.fable, now),
          source: own ? "api" : "cache",
        };
      }
      const out = { ...empty, plan: limitsState.plan };
      let ring = null;
      try { ring = document.querySelector(USAGE_RING_SELECTOR); } catch {}
      const label = limitsFromLabel(ring?.getAttribute?.("aria-label"), now);
      if (label) { out[label.kind] = label.limit; out.source = "label"; out.at = now; }
      const panel = limitsFromPanel();
      if (panel) {
        for (const kind of ["fiveHour", "weekly", "fable"]) if (!out[kind] && panel[kind]) out[kind] = panel[kind];
        if (!out.source) { out.source = "panel"; out.at = now; }
      }
      for (const kind of ["fiveHour", "weekly", "fable"]) out[kind] = live(out[kind], now);
      return out;
    } catch { return empty; }
  };
  // Лимиты подписки и «чат работает» (раздел 12ж¹, WF87): слепок без запроса
  // в сеть; org id и почты здесь нет.
  statusPart("limits", () => limitsNow(false));
  statusPart("working", () => pageWorking());
  HATCH && Object.assign(HATCH, { limitsFromApi, limitsFromLabel, limitsPlan, LIMITS_KEY });

