  // ---- 14б. Ответ без печаталки: лента плавно встаёт на «N min ago», ответ проявляется (#10764) ----
  // Слово Элвиса 23.10: «вот это печатанье… дёрганое такое… когда ответ готов, плавно прокрутить до места
  // 2 min ago? И плавно показать ответ без появления, без вот этого печатания… быстро, но плавно проясняется…
  // прокрутка прошла, вух, она так плавно остановилась… как замедляется и тут же появляется синхронно. И в тот
  // момент, когда прокрутка полностью остановилась, эта штука полностью прояснилась».
  // • Пока Claude пишет сообщение (метка data-is-streaming="true" у AssistantMessage), его не видно: место
  //   держится (прозрачность 0, раскладка та же), печатания нет. Правило CSS прячет с первого кадра, страница
  //   ставит свою метку REVEAL_HOLD — она держит сообщение и после конца записи, пока не решено, как показать.
  // • Запись кончилась, хода нет (кнопки стопа нет) и сообщение последнее — это финальный ответ: лента за
  //   REVEAL_MS едет (замедляясь, ease-out) так, чтобы время реплики Элвиса над ответом («N min ago», раздел 14а)
  //   встало у верха ленты (stampTop, раздел 14а); далеко или нет его — встаёт сам ответ. Ответ проявляется синхронно:
  //   с доли REVEAL_FADE_FROM хода и до самой остановки — лента встала, текст виден целиком.
  // • Промежуточное сообщение (ход идёт, за ним уже новая строка) или ход не кончился за REVEAL_WAIT_MS —
  //   только проявляется за REVEAL_SOLO_MS, лента не двигается.
  // • Элвис читает выше (attnReading, раздел 12м) — ленту не трогаем, ответ только проявляется. Тронул окно
  //   посреди хода ленты — ход обрывается на месте. «Уменьшить движение» — лента встаёт сразу, ответ виден сразу.
  // • Финальный ответ поставлен — раздел 12м ленту к низу уже не тянет (revealPlaced).
  // • Метка «пишется» залипла (хода нет — кнопки стопа нет — дольше REVEAL_WAIT_MS: обрыв, ошибка, сеть) — сообщение
  //   получает REVEAL_FREE и проявляется: спрятанным навсегда оно не остаётся.
  // • Видимый текст не прячется (#10903, слово Элвиса 24.10: «последнее сообщение почему-то не отображается.
  //   Просто пустота… то пропадает, то появляется»). В Claude Code «пишется» висит на куске ответа весь ход, и текст
  //   перед долгой командой стоял пустотой, пока шла команда. Теперь: прячет только метка REVEAL_HOLD (её ставит
  //   наблюдатель до отрисовки), а не сам «пишется»; ход идёт, а текст не растёт REVEAL_WAIT_MS (команда, ожидание)
  //   — показать. Показанное получает REVEAL_FREE и под метку больше не встаёт: ни когда Claude снова ставит ему «пишется», ни когда виртуальная лента пересоздаёт его ряд (ключ
  //   хода и номер сообщения в ряду — revealState.shown).
  // • Потолка нет (#11680, слово Элвиса 05.11: «чтоб вот эти ответы не вот так вот печатались, а разом появлялись…
  //   когда он весь готовый, разом показать»): потолок 4 с (#10903) отпускал длинный ответ на середине, и дальше он
  //   печатался кусками. Растёт — держим, сколько бы ни рос; встал — показать.
  const REVEAL_HOLD = "data-myclaude-reveal-hold";
  const REVEAL_FREE = "data-myclaude-reveal-free";
  const REVEAL_ON = "data-myclaude-reveal";
  const REVEAL_STREAM = '[data-cds="AssistantMessage"][data-is-streaming="true"]';
  const REVEAL_MS = 700;
  const REVEAL_FADE_FROM = 0.3;
  const REVEAL_SOLO_MS = 420;
  const REVEAL_WAIT_MS = 1500;
  const REVEAL_PLACED_MS = 10000;
  const REVEAL_EASE = "cubic-bezier(0.33, 1, 0.68, 1)";
  const revealState = {
    held: new Map(), timer: 0, raf: 0, placedAt: -Infinity, finals: 0, glides: 0, fades: 0, broken: 0, skip: null, freed: 0,
    shown: new Set(),
  };
  const revealStill = () => { try { return matchMedia("(prefers-reduced-motion: reduce)").matches; } catch { return false; } };
  const revealEase = t => 1 - (1 - t) ** 3;
  // Ключ сообщения, переживающий пересоздание ряда: ход строки (раздел 13а) и номер сообщения в ряду.
  const revealKeyOf = node => {
    try {
      const row = node.closest?.(READ_ROW_SELECTOR);
      const key = row ? readKeyOf(row) : null;
      return key ? `${key}#${[...row.querySelectorAll('[data-cds="AssistantMessage"]')].indexOf(node)}` : null;
    } catch { return null; }
  };
  // Показано — больше не прячется (#10903).
  const revealFree = node => {
    try { node.setAttribute(REVEAL_FREE, ""); } catch {}
    const key = revealKeyOf(node);
    if (key) revealState.shown.add(key);
  };
  // Показать сообщение: снять метку и проявить (duration 0 — сразу; delay — проявление начинается позже).
  const revealShow = (node, duration, delay = 0) => {
    revealState.held.delete(node);
    try { node.removeAttribute(REVEAL_HOLD); } catch {}
    revealFree(node);
    if (!(duration > 0) || typeof node?.animate !== "function") return;
    try {
      node.animate([{ opacity: 0 }, { opacity: 1 }], { duration, delay, easing: REVEAL_EASE, fill: "backwards" });
      revealState.fades += 1;
    } catch {}
  };
  const revealStop = () => {
    if (revealState.raf) { try { cancelAnimationFrame(revealState.raf); } catch {} revealState.raf = 0; }
  };
  // Ход ленты к top за REVEAL_MS с замедлением; касание окна после старта — обрыв на месте.
  const revealGlide = (feed, top) => {
    revealStop();
    const from = Number(feed.scrollTop) || 0;
    const start = now();
    const touched = attnState.inputAt;
    feedHold.ownUntil = start + REVEAL_MS + 300;
    revealState.glides += 1;
    const step = () => {
      revealState.raf = 0;
      if (!state.alive || !feed.isConnected) return;
      if (attnState.inputAt !== touched) { revealState.broken += 1; return; }
      const t = Math.min(1, (now() - start) / REVEAL_MS);
      try { feed.scrollTop = Math.round(from + (top - from) * revealEase(t)); } catch {}
      if (t < 1) revealState.raf = requestAnimationFrame(step);
    };
    revealState.raf = requestAnimationFrame(step);
  };
  // Финальный ответ: лента — на время реплики над ним (или на сам ответ), ответ проявляется к её остановке.
  const revealFinal = node => {
    revealState.finals += 1;
    revealState.skip = null;
    const still = revealStill();
    let feed = null;
    try { feed = node.closest?.(READ_FEED_SELECTOR) ?? readFeed() ?? findScroller(); } catch { feed = null; }
    if (!feed?.isConnected) { revealState.skip = "нет ленты"; revealShow(node, still ? 0 : REVEAL_SOLO_MS); return; }
    if (attnReading(now())) { revealState.skip = "читает выше"; revealShow(node, still ? 0 : REVEAL_SOLO_MS); return; }
    let top = null;
    try {
      const row = node.closest?.(READ_ROW_SELECTOR) ?? node;
      const view = feed.getBoundingClientRect();
      const box = row.getBoundingClientRect();
      const place = box.top - stampLead(row, box, Number(feed.clientHeight) || view.height);
      const room = Math.max(0, (Number(feed.scrollHeight) || 0) - (Number(feed.clientHeight) || 0));
      top = Math.max(0, Math.min(room, Math.round((Number(feed.scrollTop) || 0) + place - view.top - stampTop(feed, view))));
    } catch { top = null; }
    revealState.placedAt = now();
    if (top == null || Math.abs(top - (Number(feed.scrollTop) || 0)) < 2) { revealShow(node, still ? 0 : REVEAL_SOLO_MS); return; }
    if (still) {
      feedHold.ownUntil = now() + 300;
      try { feed.scrollTop = top; } catch {}
      revealShow(node, 0);
      return;
    }
    revealGlide(feed, top);
    revealShow(node, Math.round(REVEAL_MS * (1 - REVEAL_FADE_FROM)), Math.round(REVEAL_MS * REVEAL_FADE_FROM));
  };
  // За сообщением в ленте уже что-то есть (строка инструмента, следующее сообщение) — оно не последнее.
  const revealFollowed = node => {
    try {
      const row = node.closest?.(READ_ROW_SELECTOR);
      if (row?.nextElementSibling) return true;
      const all = document.querySelectorAll('[data-cds="AssistantMessage"]');
      return all.length > 0 && all[all.length - 1] !== node;
    } catch { return false; }
  };
  // Сверка (наблюдатель и таймер): пишущиеся — под метку, дописанные — решить и показать.
  const revealSync = () => {
    if (revealState.timer) { clearTimeout(revealState.timer); revealState.timer = 0; }
    if (!state.alive || !themable) return;
    const t = now();
    let streaming = [];
    try { streaming = [...document.querySelectorAll(REVEAL_STREAM)]; } catch { streaming = []; }
    let working = false;
    try { working = pageWorking(); } catch { working = false; }
    let waiting = false;
    for (const node of streaming) {
      if (node.hasAttribute?.(REVEAL_FREE)) continue;
      let held = revealState.held.get(node);
      const size = String(node.textContent ?? "").length;
      if (held) held.endedAt = 0;
      else {
        // Уже показанное (ряд пересоздан лентой) — не прятать снова.
        const key = revealKeyOf(node);
        if (key && revealState.shown.has(key)) { try { node.setAttribute(REVEAL_FREE, ""); } catch {} continue; }
        held = { endedAt: 0, idleAt: 0, size, grewAt: t };
        revealState.held.set(node, held);
        try { node.setAttribute(REVEAL_HOLD, ""); } catch {}
      }
      if (size !== held.size) { held.size = size; held.grewAt = t; }
      if (working) {
        // Ход идёт: держим, пока текст растёт (печаталки нет); встал — показать.
        held.idleAt = 0;
        if (!(size > 0 && t - held.grewAt >= REVEAL_WAIT_MS)) { waiting = true; continue; }
      } else {
        // «Пишется», а хода нет: метка залипла — подождать и проявить как есть.
        held.idleAt ||= t;
        if (t - held.idleAt < REVEAL_WAIT_MS) { waiting = true; continue; }
      }
      revealState.freed += 1;
      revealShow(node, revealStill() ? 0 : REVEAL_SOLO_MS);
    }
    for (const [node, held] of [...revealState.held]) {
      if (!node.isConnected) { revealState.held.delete(node); continue; }
      if (streaming.includes(node)) continue;
      held.endedAt ||= t;
      if (!working && !revealFollowed(node)) { revealFinal(node); continue; }
      if (revealFollowed(node) || t - held.endedAt >= REVEAL_WAIT_MS) { revealShow(node, revealStill() ? 0 : REVEAL_SOLO_MS); continue; }
      waiting = true;
    }
    if (waiting) revealState.timer = setTimeout(revealSync, Math.max(100, Math.round(REVEAL_WAIT_MS / 3)));
  };
  // Вход в чат и переход по главе Claude (слово Элвиса 23.10 19:30, «когда этот я перехожу», скрины №1 и №2):
  // Claude ставит начало ответа под самый верх, строка «✓✓ N min ago» реплики над ним уезжает за край. Первые
  // REVEAL_ENTER_MS после входа (смена адреса, установка страницы) или нажатия по главе Claude, пока Элвис не тронул
  // окно сам: у верха ленты (не дальше REVEAL_NEAR) начало ответа, а его строки времени не видно — лента
  // сдвигается так, чтобы она встала на stampTop. Место чтения посреди ответа (раздел 13а) не трогается.
  const REVEAL_ENTER_MS = 4000;
  const REVEAL_NEAR = 48;
  const REVEAL_ENTER_STEPS = [300, 900, 1800, 3200];
  // Лента ещё едет (плавный переход Claude, догрузка виртуальной ленты) — не трогаем: сдвиг посреди хода оборвал бы
  // его и поставил на строку, мимо которой лента только проезжала. Ждём REVEAL_CALM_MS тишины.
  const REVEAL_CALM_MS = 150;
  Object.assign(revealState, { href: location.href, enterAt: now(), enterInput: attnState.inputAt, enterTimer: 0, enterStep: 0, nudges: 0, movedAt: -Infinity });
  const onRevealScroll = event => { try { if (event?.target === readFeed()) revealState.movedAt = now(); } catch {} };
  on(document, "scroll", onRevealScroll, { capture: true, passive: true });
  const revealNudge = () => {
    const feed = readFeed();
    if (!feed?.isConnected || now() - revealState.movedAt < REVEAL_CALM_MS) return false;
    try {
      const view = feed.getBoundingClientRect();
      const row = readRowsNow().find(item => { const box = item.getBoundingClientRect(); return box.height > 0 && box.bottom > view.top + 1; });
      if (!row || row.getAttribute("data-perf-row") === "human" || row.querySelector?.(".epitaxy-user-turn")) return false;
      const box = row.getBoundingClientRect();
      if (Math.abs(box.top - view.top) > REVEAL_NEAR) return false;
      const lead = stampLead(row, box, Number(feed.clientHeight) || view.height);
      if (!lead) return false;
      const delta = Math.round(box.top - (view.top + stampTop(feed, view) + lead));
      if (Math.abs(delta) < 2) return false;
      feedHold.ownUntil = now() + 300;
      feed.scrollTop = Math.max(0, (Number(feed.scrollTop) || 0) + delta);
      revealState.nudges += 1;
      return true;
    } catch { return false; }
  };
  const revealEnterLive = () => now() - revealState.enterAt < REVEAL_ENTER_MS && attnState.inputAt === revealState.enterInput
    && !revealState.raf && !readState.seek;
  const revealEnterStep = () => {
    revealState.enterTimer = 0;
    if (!state.alive || !themable) return;
    if (revealEnterLive()) revealNudge();
    const next = REVEAL_ENTER_STEPS[revealState.enterStep];
    if (next == null) return;
    const prev = REVEAL_ENTER_STEPS[revealState.enterStep - 1] ?? 0;
    revealState.enterStep += 1;
    revealState.enterTimer = setTimeout(revealEnterStep, next - prev);
  };
  // timer — сверки по часам (REVEAL_ENTER_STEPS); при установке страницы их нет: ленту ещё рисуют, сверку ведут мутации.
  const revealEnterArm = (timer = true) => {
    revealState.enterAt = now();
    revealState.enterInput = attnState.inputAt;
    revealState.enterStep = 0;
    if (revealState.enterTimer) { clearTimeout(revealState.enterTimer); revealState.enterTimer = 0; }
    if (timer) revealState.enterTimer = setTimeout(revealEnterStep, 0);
  };
  // Наблюдатель: сменился адрес — вход; пока окно входа открыто — сверка на каждой волне мутаций.
  const revealEnterCheck = () => {
    if (location.href !== revealState.href) { revealState.href = location.href; revealEnterArm(); return; }
    if (revealEnterLive()) revealNudge();
  };
  // Нажатие по строке главы Claude (не своей, не галочке и не звёздочке). Слово Элвиса 23.10 20:4x: «ты должен был
  // меня переместить по главам… там один час ago сверху показывается и ответ» — Claude ставит ленту на место главы
  // внутри ответа (подзаголовок «Ждёт тебя» посреди ответа). Глава — ход ассистента (entryId из пропсов строки,
  // chChapterOf): переход наш, как у своей главы, — к началу ответа, его «✓✓ N ago» у верха. Ход не ответ
  // («Session start» — реплика человека) или глава не читается — переход Claude, а место правит сверка входа.
  const onRevealChapterClick = event => {
    if (!state.alive || !themable) return;
    const target = event?.target;
    let row = null;
    try {
      if (!target?.closest?.(CH_NAV_SELECTOR) || target.closest(`[${CH_CHECK_ATTRIBUTE}],[${CH_STAR_ATTRIBUTE}],li[${CH_OWN_ATTRIBUTE}]`)) return;
      if (!target.closest(`${CH_NAV_SELECTOR} > div > ol > li > button`)) return;
      row = target.closest(`${CH_NAV_SELECTOR} > div > ol > li`);
    } catch { return; }
    let key = null;
    try {
      const id = chChapterOf(row)?.entryId;
      if (typeof id === "string" && readState.order.some(entry => entry.id === id && entry.assistant)) key = id;
    } catch { key = null; }
    if (!key) { revealEnterArm(); return; }
    event.preventDefault?.();
    event.stopImmediatePropagation?.();
    if (Number(event.detail) > 1) return;
    chState.jumps += 1;
    try { readSeek(key, { flash: true, smooth: true, stamp: true }); } catch {}
    // Меню уходит как после своей главы: событие до onChClick отсюда не доходит. С клавиатуры остаётся.
    if (Number(event.detail) > 0) chLeaveSoon();
  };
  on(document, "click", onRevealChapterClick, true);
  // Финальный ответ поставлен только что — раздел 12м ленту к низу не тянет.
  const revealPlaced = t => t - revealState.placedAt < REVEAL_PLACED_MS;
  // Свой наблюдатель «до отрисовки»: метка ставится раньше, чем первые буквы успеют показаться.
  // Сообщение было видно («пишется» = false) и снова стало «пишется» — это не новый текст, не прятать (#10903).
  const revealSeen = records => {
    for (const record of records ?? []) {
      const node = record?.target;
      if (record?.type === "attributes" && record.oldValue === "false" && node?.getAttribute?.("data-is-streaming") === "true"
        && !node.hasAttribute?.(REVEAL_HOLD)) revealFree(node);
    }
  };
  const revealWatch = new MutationObserver(records => { try { revealSeen(records); } catch {} try { revealSync(); } catch {} try { if (themable) revealEnterCheck(); } catch {} });
  if (themable) {
    try { document.documentElement.setAttribute(REVEAL_ON, ""); } catch {}
    revealWatch.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeOldValue: true, attributeFilter: ["data-is-streaming"] });
  }
  track(() => {
    revealWatch.disconnect();
    revealStop();
    if (revealState.timer) { clearTimeout(revealState.timer); revealState.timer = 0; }
    if (revealState.enterTimer) { clearTimeout(revealState.enterTimer); revealState.enterTimer = 0; }
    revealState.held.clear();
    revealState.shown.clear();
    try {
      document.documentElement.removeAttribute(REVEAL_ON);
      for (const node of document.querySelectorAll(`[${REVEAL_HOLD}],[${REVEAL_FREE}]`)) { node.removeAttribute(REVEAL_HOLD); node.removeAttribute(REVEAL_FREE); }
    } catch {}
  });
  try { for (const node of document.querySelectorAll(`[${REVEAL_HOLD}],[${REVEAL_FREE}]`)) { node.removeAttribute(REVEAL_HOLD); node.removeAttribute(REVEAL_FREE); } } catch {}
  try { revealSync(); } catch {}
  if (themable) revealEnterArm(false);
  // Без !important: проявление (Web Animations) должно быть сильнее правила. Прячет только метка (#10903).
  lateRules.push(`html[${REVEAL_ON}] [${REVEAL_HOLD}]{opacity:0}`);
  // Ответ без печаталки (раздел 14б): сколько сообщений держится, финальных ответов, ходов ленты, проявлений,
  // обрывов касанием, почему ленту не двигали в последний раз, сколько раз при входе или переходе по главе Claude
  // лента встала на строку времени, сколько «пишется» проявлено до конца записи (freed: залипло, текст встал).
  statusPart("reveal", () => ({
    held: revealState.held.size, finals: revealState.finals, glides: revealState.glides, fades: revealState.fades,
    broken: revealState.broken, skip: revealState.skip, nudges: revealState.nudges, freed: revealState.freed,
  }));
  HATCH && Object.assign(HATCH, { revealSync, revealState, revealPlaced, revealNudge, revealEnterArm, revealWatch, REVEAL_MS, REVEAL_WAIT_MS });
