  // ---- 12х²ᶜ. Полоски глав — посередине между краем и текстом (#10848) --------
  // Слово Элвиса 24.10.2026 13:20 (снимок 4): «они сейчас не по центру, они сильно прижаты к тексту. Ты их можешь
  // чуть левее сдвинуть, чтоб они ровно были посередине». Замер 24.10 (окно Рика, панель материалов слева): черта
  // рейки дока — 244.8, плитка Claude — с 256.8 (её обёртка с contain:strict и overflow-x:clip режет всё левее), лента —
  // с 264.8, текст — с 268.8, дорожка (сдвиг −4, #10764) — с 260.8: середина свободной полосы — ровно кромка плитки.
  //  - Край слева — что ближе к плитке слева: черта рейки панели материалов (#myclaude-dock-rail, черта — её левый
  //    пиксель) или боковая панель Claude (.dframe-sidebar шире CH_CENTER_SIDEBAR_MIN); ничего — кромка плитки минус
  //    CH_CENTER_SPILL (там кончается прокрутка плитки).
  //  - Текст — левый край абзацев ответа в видимой части ленты (самый левый из первых CH_CENTER_PROBES); нет — край ленты.
  //  - Дорожка сдвигается так, чтобы середина полной полоски легла посередине (не дальше CH_CENTER_MAX влево и не
  //    правее места без сдвига); короткие полоски — по той же оси (origin center), а не от левого края.
  //  - Вылет за кромку плитки — overflow-clip-margin её обёртке ровно на вылет, не больше CH_CENTER_SPILL (дальше режет
  //    прокрутка плитки — тогда дорожка встаёт правее). Нет замера — прежний сдвиг −4.
  const CH_CENTER_SHIFT_VARIABLE = "--myclaude-ch-shift";
  const CH_CENTER_SPILL_VARIABLE = "--myclaude-ch-spill";
  const CH_CLIP_ATTRIBUTE = "data-myclaude-ch-clip";
  const CH_CENTER_BASE = -4;
  const CH_CENTER_MAX = 16;
  const CH_CENTER_SPILL = 8;
  const CH_CENTER_PROBES = 6;
  const CH_CENTER_HOPS = 14; // замер 03.11, 3.1623: режет 14-й предок nav (contain:strict, overflow-x:clip), выше .tiles-shell
  const CH_CENTER_SIDEBAR_MIN = 40;
  const chCenterState = { navs: 0, shift: null, spill: 0, edge: null, text: null };
  // Чистый расчёт (px): edge — край слева, text — начало текста, navLeft — левый край дорожки без сдвига, len — длина
  // полной полоски, clipLeft — кромка обёртки плитки (нет — NaN). → {shift, spill}: сдвиг дорожки и вылет за кромку.
  const chCenterPlan = ({ edge, text, navLeft, len, clipLeft }) => {
    if (![edge, text, navLeft, len].every(Number.isFinite) || text <= edge) return { shift: CH_CENTER_BASE, spill: 0 };
    let shift = Math.min(0, Math.max(-CH_CENTER_MAX, (edge + text) / 2 - len / 2 - navLeft));
    let spill = Number.isFinite(clipLeft) ? clipLeft - (navLeft + shift) : 0;
    if (spill > CH_CENTER_SPILL) { shift += spill - CH_CENTER_SPILL; spill = CH_CENTER_SPILL; }
    return { shift: Math.round(shift * 2) / 2, spill: Math.max(0, Math.ceil(spill - 0.01)) };
  };
  // Обёртка, что режет дорожку слева: ближайший предок с overflow не visible или contain с paint.
  const chCenterClipOf = nav => {
    let node = nav?.parentElement ?? null;
    for (let hop = 0; node && hop < CH_CENTER_HOPS; hop += 1, node = node.parentElement) {
      let style = null;
      try { style = getComputedStyle(node); } catch { style = null; }
      if (!style) continue;
      if (style.overflowX !== "visible" || /paint|strict|content/.test(String(style.contain ?? ""))) return node;
    }
    return null;
  };
  const chCenterEdge = clipLeft => {
    let edge = -Infinity;
    try {
      const rail = document.getElementById("myclaude-dock-rail")?.getBoundingClientRect();
      if (rail && rail.width > 0 && rail.right <= clipLeft + 1) edge = Math.max(edge, rail.left + 1);
    } catch {}
    try {
      for (const side of document.querySelectorAll(".dframe-sidebar")) {
        const box = side.getBoundingClientRect();
        if (box.width > CH_CENTER_SIDEBAR_MIN && box.right <= clipLeft + 1) edge = Math.max(edge, box.right);
      }
    } catch {}
    return Number.isFinite(edge) ? edge : Math.max(0, clipLeft - CH_CENTER_SPILL);
  };
  const chCenterText = nav => {
    const panel = nav.closest?.(".epitaxy-chat-panel");
    if (!panel) return NaN;
    let left = Infinity;
    let seen = 0;
    try {
      for (const p of panel.querySelectorAll('[data-testid="transcript-row"] p')) {
        const box = p.getBoundingClientRect();
        if (box.height <= 0 || box.width <= 0 || box.bottom <= 0 || box.top >= innerHeight) continue;
        left = Math.min(left, box.left);
        if ((seen += 1) >= CH_CENTER_PROBES) break;
      }
    } catch {}
    if (Number.isFinite(left)) return left;
    try { return panel.getBoundingClientRect().left; } catch { return NaN; }
  };
  const chCenterDrop = nav => {
    try { nav.style.removeProperty(CH_CENTER_SHIFT_VARIABLE); } catch {}
    try { nav.style.removeProperty(CH_ROOM_VARIABLE); } catch {}
  };
  const chCenterUnclip = node => {
    try { node.removeAttribute(CH_CLIP_ATTRIBUTE); node.style.removeProperty(CH_CENTER_SPILL_VARIABLE); } catch {}
  };
  const chCenterTick = () => {
    let navs = [];
    try { navs = themable ? [...document.querySelectorAll(CH_NAV_SELECTOR)] : []; } catch { navs = []; }
    const clips = new Set();
    chCenterState.navs = navs.length;
    for (const nav of navs) {
      const span = nav.querySelector('ol[aria-hidden="true"] > li > span');
      if (!span) { chCenterDrop(nav); continue; }
      let navLeft = NaN;
      let len = NaN;
      try { navLeft = nav.getBoundingClientRect().left; len = parseFloat(getComputedStyle(span).width); } catch {}
      const clip = chCenterClipOf(nav);
      let clipLeft = NaN;
      try { clipLeft = clip ? clip.getBoundingClientRect().left : NaN; } catch {}
      const edge = chCenterEdge(Number.isFinite(clipLeft) ? clipLeft : navLeft);
      const text = chCenterText(nav);
      const plan = chCenterPlan({ edge, text, navLeft, len, clipLeft });
      const shift = `${plan.shift}px`;
      if (nav.style.getPropertyValue(CH_CENTER_SHIFT_VARIABLE) !== shift) nav.style.setProperty(CH_CENTER_SHIFT_VARIABLE, shift);
      if (clip && plan.spill > 0) {
        clips.add(clip);
        if (!clip.hasAttribute(CH_CLIP_ATTRIBUTE)) clip.setAttribute(CH_CLIP_ATTRIBUTE, "");
        const spill = `${plan.spill}px`;
        if (clip.style.getPropertyValue(CH_CENTER_SPILL_VARIABLE) !== spill) clip.style.setProperty(CH_CENTER_SPILL_VARIABLE, spill);
      }
      Object.assign(chCenterState, { shift: plan.shift, spill: plan.spill, edge: Math.round(edge * 10) / 10, text: Math.round(text * 10) / 10 });
    }
    try { for (const node of document.querySelectorAll(`[${CH_CLIP_ATTRIBUTE}]`)) if (!clips.has(node)) chCenterUnclip(node); } catch {}
  };
  track(() => {
    try { for (const nav of document.querySelectorAll(CH_NAV_SELECTOR)) chCenterDrop(nav); } catch {}
    try { for (const node of document.querySelectorAll(`[${CH_CLIP_ATTRIBUTE}]`)) chCenterUnclip(node); } catch {}
  });
  // Сдвиг — переменной на nav (сетка 4 держит прежние −4 без неё); короткие полоски — от середины.
  lateRules.push(
    `${CH_RAIL}{translate:var(${CH_CENTER_SHIFT_VARIABLE},${CH_CENTER_BASE}px) 0}`,
    `${CH_RAIL}>li>span{transform-origin:center !important}`,
    `[${CH_CLIP_ATTRIBUTE}]{overflow-clip-margin:var(${CH_CENTER_SPILL_VARIABLE},0px) !important}`,
  );
  statusPart("chCenter", () => ({ ...chCenterState }));
  HATCH && Object.assign(HATCH, { chCenterPlan, chCenterTick, chCenterState });
