  // ---- 18. Самопроверка страницы: health() (#10527, К-HEALTH) ---------------
  // Слово Элвиса 22.10 02:12: «постоянно одни и те же ошибки правлю. То кнопка какая-нибудь отвалится, то ещё
  // что-нибудь отвалится». Девять проверок того, что видно на экране: опоры Claude, широкий вид, свёртка, линия
  // названия, кнопка боковой панели, живой фон, наши кнопки, родные кнопки под нашими слоями, установка. Форма
  // ответа, id и коды `why` — docs/contracts/550-10527-health-live-check.md.
  //
  // Только чтение: поиск узлов, рамки, вычисленные стили, elementFromPoint, status(). Ни нажатий, ни фокуса, ни
  // прокрутки, ни записи атрибутов, стилей и хранилищ, ни таймеров.
  //
  // healthRun — сама проверка, без замыкания страницы: всё, что она знает о странице, приходит в env (опоры —
  // селекторы тех разделов, где страница ими пользуется, список наших узлов, status()). Так её же текст гоняют
  // слепок прошлой страницы (tests/claude-dom-replay.test.mjs) и живое окно со страницей без health().
  const healthRun = (w, env) => {
    const doc = w.document;
    const s = env.status ?? {};
    const sel = env.sel;
    const q = (selector, root = doc) => { try { return root.querySelector(selector); } catch { return null; } };
    const qa = (selector, root = doc) => { try { return [...root.querySelectorAll(selector)]; } catch { return []; } };
    const css = (node, pseudo = null) => { try { return w.getComputedStyle(node, pseudo); } catch { return null; } };
    const prop = (style, name) => String(style?.getPropertyValue?.(name) ?? "").trim();
    const num = value => Number.parseFloat(value) || 0;
    const box = node => {
      try {
        const rect = node.getBoundingClientRect();
        return { l: rect.left, t: rect.top, w: rect.width, h: rect.height, r: rect.left + rect.width, b: rect.top + rect.height };
      } catch { return null; }
    };
    const round = value => Math.round(value);
    // Альфа цвета фона: rgba(…, a), rgb(…) = 1, «… / a» (color(), oklab()), transparent = 0.
    const alpha = color => {
      const text = String(color ?? "").trim();
      if (!text || text === "transparent") return 0;
      const slash = text.match(/\/\s*([\d.]+)(%?)\s*\)$/);
      if (slash) return Math.round((slash[2] ? num(slash[1]) / 100 : num(slash[1])) * 100) / 100;
      const rgba = text.match(/^rgba\(([^)]*)\)$/);
      if (rgba) { const parts = rgba[1].split(","); return parts.length > 3 ? Math.round(num(parts[3]) * 100) / 100 : 1; }
      return 1;
    };
    const backAlpha = node => alpha(prop(css(node), "background-color") || css(node)?.backgroundColor);
    // Имя узла для why: #id или тег.первый класс (классы Claude длинные — режем).
    const nameOf = node => {
      if (!node || node.nodeType !== 1) return "?";
      if (node.id) return `#${node.id}`;
      const first = String(node.className?.baseVal ?? node.className ?? "").split(/\s+/).filter(Boolean)[0];
      return `${String(node.tagName).toLowerCase()}${first ? `.${first.slice(0, 40)}` : ""}`;
    };
    const viewW = Number(w.innerWidth) || 0;
    const viewH = Number(w.innerHeight) || 0;
    // Страница показывает узел сама: инлайн display задан и не none (так прячут и показывают свои узлы все разделы).
    const shown = node => { const display = node?.style?.getPropertyValue?.("display") ?? ""; return display !== "" && display !== "none"; };
    const onScreen = node => {
      const style = css(node);
      if (!node?.isConnected || !style) return false;
      if ((prop(style, "display") || style.display) === "none" || (prop(style, "visibility") || style.visibility) === "hidden") return false;
      const opacity = prop(style, "opacity") || style.opacity;
      if (opacity !== "" && opacity != null && num(opacity) <= 0) return false;
      const rect = box(node);
      return Boolean(rect && rect.w > 0 && rect.h > 0 && rect.b > 0 && rect.t < viewH && rect.r > 0 && rect.l < viewW);
    };
    // Что под центром узла. null — не знаем (центр вне окна или браузер не ответил): такой узел не судим.
    const hitAt = node => {
      const rect = box(node);
      if (!rect) return null;
      const x = rect.l + rect.w / 2;
      const y = rect.t + rect.h / 2;
      if (x < 0 || y < 0 || x >= viewW || y >= viewH) return null;
      try { return doc.elementFromPoint(x, y) ?? null; } catch { return null; }
    };
    const inside = (node, hit) => hit === node || Boolean(node?.contains?.(hit));
    // Открытое меню, диалог или наша панель над узлом — законно; так же — подглядывание свёрнутой боковой панели,
    // при котором наши узлы спрятаны правилом раздела 4.
    const overlay = hit => { try { return Boolean(hit?.closest?.(sel.overlay)); } catch { return false; } };
    const peek = Boolean(q(sel.peek));

    const href = String(w.location?.href ?? "");
    const path = String(w.location?.pathname ?? "");
    const windowKind = s.chat?.kind ?? (href.startsWith("about:blank") ? "popout" : "main");
    if (windowKind === "other") return null;
    const kind = windowKind === "popout" ? "popout" : /^\/(?:epitaxy|new)\/?$/.test(path) ? "new" : "main";
    const editor = q(sel.dockEditor) ?? q(sel.editor);
    const tile = editor?.closest?.(sel.tile) ?? q(sel.tile);
    const mode = kind === "popout" ? (tile ? "code" : "chat") : path.startsWith("/epitaxy") ? "code" : "chat";
    const flag = tile?.isConnected ? prop(css(tile), env.wideFlag) === "1" : false;
    const wide = Boolean(flag);
    const chatSkip = mode === "chat" ? { ok: true, skip: "mode-chat" } : null;
    const red = (code, detail) => ({ ok: false, why: `${code}${detail === undefined ? "" : `: ${detail}`}` });
    const green = () => ({ ok: true });

    // Строка модели без ChatComposerChin (#10972): домашний экран Claude 3.6556 её не рисует — модель и режим лежат
    // полкой под полем. Строка — самый крупный предок кнопки модели в плитке, где нет поля ввода (в чате это сама
    // ChatComposerChin), не выше 200: шапку с лентой строкой не считаем.
    const rowOf = button => {
      if (!button?.isConnected || !editor?.isConnected || !tile?.isConnected) return null;
      let row = null;
      for (let node = button; node && !node.contains?.(editor); node = node.parentElement) row = node;
      return row && tile.contains(row.parentElement) && (box(row)?.h ?? Infinity) <= 200 ? row : null;
    };
    const anchors = {
      tile, header: q(sel.header), feed: q(sel.feed), editor,
      modelRow: q(sel.modelRow) ?? qa(sel.modelButton).map(rowOf).find(Boolean) ?? null, modelButton: q(sel.modelButton),
      sidebarButton: q(sel.sidebarButton), usageRing: q(sel.usageRing), dock: q(sel.dock),
    };
    const checks = {
      anchors: () => {
        if (chatSkip) return chatSkip;
        const optional = new Set(kind === "popout" ? ["usageRing"] : kind === "new" ? ["feed", "header"] : []);
        const missing = Object.keys(anchors).filter(name => !optional.has(name) && !anchors[name]?.isConnected);
        return missing.length ? red("missing", missing.join(", ")) : green();
      },
      wide: () => {
        if (chatSkip) return chatSkip;
        const width = tile ? round(box(tile)?.w ?? 0) : 0;
        // Домашний экран (new) широкого вида не получает никогда: в нём нет ленты (раздел 2а). У самого порога
        // (±1) не судим — контейнер плитки и её рамка расходятся на точку.
        const want = kind !== "new" && width >= env.wideMin;
        if (Math.abs(width - env.wideMin) > 1 && want !== wide) return red("flag", `плитка ${width}, флаг ${wide ? 1 : 0}`);
        const handle = q(`#${env.ids.handle}`);
        const rail = q(`#${env.ids.rail}`);
        if (!wide) {
          if (rail && shown(rail)) return red("rail", "есть в узком");
          return handle ? green() : red("handle", "нет ручки");
        }
        // Колонка сетки — предок шапки, ребёнок плитки или её обёртки .contents (раздел 2а, PANEL_COLUMN_PATHS).
        let column = anchors.header;
        while (column && column.parentElement !== tile &&
          !(column.parentElement?.parentElement === tile && column.parentElement.classList?.contains("contents"))) column = column.parentElement;
        const display = column ? prop(css(column), "display") || css(column)?.display || "" : "нет колонки";
        if (display !== "grid") return red("grid", display);
        const feed = anchors.feed ? box(anchors.feed) : null;
        const dock = anchors.dock ? box(anchors.dock) : null;
        if (feed && dock && dock.l < feed.r - 1) return red("dock-left", `лента ${round(feed.l)}–${round(feed.r)}, дока ${round(dock.l)}–${round(dock.r)}`);
        const frame = anchors.dock ? box(q(sel.shell, anchors.dock) ?? anchors.dock) : null;
        // Высота — не больше 40 % окна: в окне ниже 500 поле с колонку и шапкой не наберёт 200.
        if (frame && (frame.w < 200 || frame.h < Math.min(200, viewH * 0.4))) return red("dock-size", `${round(frame.w)}×${round(frame.h)}`);
        return rail && shown(rail) ? green() : red("rail", "нет в широком");
      },
      fold: () => {
        if (chatSkip) return chatSkip;
        // Цель свёртки — то, что нашла сама страница (раздел 5): строка модели и рамка поля.
        const lost = [s.modelRow === true ? null : "modelRow", s.shell === true ? null : "frame"].filter(Boolean);
        if (lost.length) return red("no-target", lost.join(", "));
        const bars = [env.ids.handle, env.ids.superTop, env.ids.superBottom]
          .flatMap(id => qa(`[id="${id}"]`)).filter(node => shown(node) && onScreen(node));
        // Широкий вид — ступеней нет (раздел 2г, syncWide): полоска там свернула бы поле, которое нечем вернуть.
        if (wide) return bars.length ? red("bars", bars.length) : green();
        const handles = bars.filter(node => node.id === env.ids.handle).length;
        if (handles === 1 || (handles === 0 && (s.handleCovered === true || peek))) return green();
        return red("bars", handles);
      },
      title: () => {
        if (chatSkip) return chatSkip;
        if (kind === "new") return { ok: true, skip: "no-chat" };
        if (!wide) return { ok: true, skip: "narrow" };
        const title = q(sel.title);
        // Название слева над лентой (свёрнутая боковая панель, атрибут раздела 2а) — линии поля у него нет.
        if (title && tile?.getAttribute?.(env.titleSide) !== "left" && editor) {
          const left = (box(title)?.l ?? 0) + num(prop(css(title), "padding-left"));
          const text = (box(editor)?.l ?? 0) + num(prop(css(editor), "padding-left"));
          if (Math.abs(left - text) > 6) return red("line", `название ${round(left)}, поле ${round(text)}`);
        }
        return s.corner?.on && String(s.corner?.project ?? "").trim() ? green() : red("folder", "пусто");
      },
      sidebarButton: () => {
        if (chatSkip) return chatSkip;
        const button = anchors.sidebarButton;
        if (!button?.isConnected) return red("missing");
        const hit = hitAt(button);
        if (hit && !inside(button, hit) && !overlay(hit) && !peek) return red("covered", nameOf(hit));
        if (button.closest?.(sel.collapsedChrome) && ["Show sidebar", "Показать боковую панель"].includes(button.getAttribute("aria-label"))) {
          const backing = alpha(prop(css(button, "::before"), "background-color") || css(button, "::before")?.backgroundColor);
          if (backing < 1) return red("backing", `альфа ${backing}`);
        }
        return green();
      },
      look: () => {
        // Живой фон — слой «Оформления» (look.aurora, раздел 2а) или живые цвета (live.on, раздел 2в).
        if (!(s.live?.on === true || s.look?.aurora === true)) return { ok: true, skip: "live-off" };
        const host = q(sel.lookHost) ?? tile;
        // Пустая страница (попап до въезда чата) — красить нечего.
        if (!host) return green();
        const layer = css(host, "::before");
        const content = prop(layer, "content") || layer?.content || "";
        if (!content || content === "none") return red("layer", "нет слоя");
        if ((prop(layer, "display") || layer?.display) === "none") return red("layer", "display none");
        if (num(prop(layer, "opacity") || layer?.opacity || "1") <= 0) return red("layer", "opacity 0");
        const size = [prop(layer, "width") || layer?.width, prop(layer, "height") || layer?.height];
        if (size.some(value => /px$/.test(String(value)) && num(value) <= 0)) return red("layer", "размер 0");
        // Плитка — с обёртками до основы слоя: рамка плиток .tiles-shell залитая закрывала фон целиком (3.1623).
        for (let node = tile; node && node !== host && node.nodeType === 1; node = node.parentElement) {
          const a = backAlpha(node);
          if (a > 0) return red("opaque", `tile альфа ${a}`);
        }
        for (const [name, node] of [["composer", q(sel.composerFill)], ["sidebar", q(sel.sidebar)]]) {
          const a = node ? backAlpha(node) : 0;
          if (a > 0) return red("opaque", `${name} альфа ${a}`);
        }
        const feed = anchors.feed?.isConnected ? box(anchors.feed) : null;
        if (feed && feed.w > 0 && feed.h > 0) {
          const top = Math.max(0, feed.t);
          const bottom = Math.min(viewH, feed.b);
          const points = [[0.5, 0.5], [0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]]
            .map(([fx, fy]) => [feed.l + feed.w * fx, top + (bottom - top) * fy]);
          for (const [x, y] of points) {
            let stack = [];
            try { stack = [...(doc.elementsFromPoint(x, y) ?? [])]; } catch { stack = []; }
            for (const node of stack) {
              if (node === anchors.feed || node.contains?.(anchors.feed)) break;
              if (anchors.feed.contains?.(node) || overlay(node)) continue;
              const rect = box(node);
              if (rect && rect.w > 40 && rect.h > 40 && backAlpha(node) >= 1) return red("over-feed", `${nameOf(node)} ${round(rect.w)}×${round(rect.h)}`);
            }
          }
        }
        return green();
      },
      ownButtons: () => {
        const bad = [];
        for (const id of env.own) {
          const nodes = qa(`[id="${id}"]`);
          if (nodes.length > 1) { bad.push(`dupe: ${id}×${nodes.length}`); continue; }
          const node = nodes[0];
          if (!node) { if (env.made.includes(id)) bad.push(`missing: ${id}`); continue; }
          if (!shown(node) || peek) continue;
          // Узел в дереве Claude (кнопки над списком закреплённых) прячется вместе с хозяином: свёрнутая боковая
          // панель — не поломка. Судим только узлы в body и узлы с видимым хозяином.
          const host = node.parentElement;
          if (host && host !== doc.body && host !== doc.documentElement && !onScreen(host)) continue;
          if (!onScreen(node)) { bad.push(`hidden: ${id}`); continue; }
          // Слой без нажатий (pointer-events: none) мышь пропускает насквозь — его не судим.
          if (prop(css(node), "pointer-events") === "none") continue;
          const hit = hitAt(node);
          if (hit && !inside(node, hit) && !overlay(hit)) bad.push(`covered: ${id} под ${nameOf(hit)}`);
        }
        return bad.length ? { ok: false, why: bad.join("; ").slice(0, 400) } : green();
      },
      claudeButtons: () => {
        const own = hit => { try { return hit?.closest?.('[id^="myclaude-"]') ?? null; } catch { return null; } };
        const chin = anchors.modelRow;
        const attach = chin ? qa("button", chin).find(node => !node.matches?.(`${sel.modelButton},${sel.usageRing}`)) ?? null : null;
        const list = [["send", q(sel.send)], ["modelButton", anchors.modelButton], ["attach", attach]];
        if (kind !== "popout") list.push(["usageRing", anchors.usageRing]);
        for (const card of anchors.feed ? qa(sel.fileCard, anchors.feed) : []) list.push(["fileCard", card]);
        for (const [name, node] of list) {
          if (!node?.isConnected || !onScreen(node)) continue;
          const hit = hitAt(node);
          const ours = hit && !inside(node, hit) ? own(hit) : null;
          // Наш id на узле Claude (рамка поля, раздел 5¹) — не наш слой.
          if (ours && !ours.contains?.(node)) return red("covered", `${name} под #${ours.id}`);
        }
        return green();
      },
      install: () => {
        const verdict = (() => {
          if (s.cssOk === false) return red("css", "cssOk false");
          if (Array.isArray(s.cssViolations) && s.cssViolations.length) return red("violations", s.cssViolations.length);
          if (w.__myclaudeFailure) return red("failure", String(w.__myclaudeFailure?.message ?? w.__myclaudeFailure).slice(0, 100));
          const handles = qa(`[id="${env.ids.handle}"]`).length;
          return handles > 1 ? red("dupes", `ручек ${handles}`) : green();
        })();
        return env.installedAt ? { ...verdict, at: env.installedAt } : verdict;
      },
    };
    const list = Object.entries(checks).map(([id, run]) => {
      let verdict;
      try { verdict = run(); } catch (error) { verdict = { ok: false, why: `error: ${String(error?.message ?? error).slice(0, 120)}` }; }
      const out = { id, ok: verdict.ok === true };
      if (verdict.skip) out.skip = verdict.skip;
      if (!out.ok) out.why = String(verdict.why ?? "error");
      if (verdict.at) out.at = verdict.at;
      return out;
    });
    let chat = "";
    try { chat = String(s.chat?.self ?? "") || ""; } catch { chat = ""; }
    return {
      v: 1, version: String(env.version ?? s.version ?? ""), page: windowKind === "popout" ? "about:blank" : `${w.location?.origin ?? ""}${path}`,
      kind, mode, wide, chat, title: String(doc.title ?? "").slice(0, 80), at: new Date().toISOString(),
      checks: list, red: list.filter(item => !item.ok).map(item => item.id),
    };
  };
  // Наши узлы (id из раздела 1 и разделов фич; сироты прошлых версий — RICK_*, WINDOW_FRAME_ID, WAIT_GLOW_ID,
  // SEND_TEXT_QUEUE_ID — не в счёт: их только убирают; <style> тоже — попап Claude копирует таблицы окна-родителя вместе
  // с нашей, и копия с тем же id — не двойная установка, её ловит install по ручкам). made — узлы, которые страница ставит при установке в любом
  // окне: их отсутствие — «кнопка отвалилась».
  const HEALTH_MADE = [PROGRESS_ID, PROGRESS_TIP_ID, PROGRESS_CARD_ID, PROGRESS_TAIL_ID, CORNER_ID, MAIN_DRAG_ID,
    HANDLE_ID, SUPER_TOP_ID, SUPER_BOTTOM_ID, SIDE_RAIL_ID, MIC_ID, MIC_HINT_ID, GALLERY_ID, PMP_ID, PMP_PANEL_ID,
    MODE_HINT_ID, DIM_ID, ATTN_FRAME_ID, DOCK_BUTTON_ID, DOCK_SIZES_ID, DOCK_PLACE_ID, DOCK_RAIL_ID, DOCK_DRAG_ID];
  const HEALTH_OWN = [...HEALTH_MADE, COMPOSER_ATTACHMENTS_ID, COMPOSER_IMAGE_UNDO_ID, READ_NEXT_ID,
    CH_DIM_ID, CH_SET_ID, AUTO_ALLOW_TOAST_ID, NEW_WINDOW_NOTE_ID, PIN_BULK_ID, RUN_CONFIRM_ID, SEND_DELAY_ID,
    SEND_DELAY_DIGITS_ID, SEND_DELAY_ROCKET_ID, PHOTO_VIEW_ID];
  // Опоры — селекторы тех разделов, где страница ими пользуется.
  const HEALTH_PAGE = {
    wideFlag: WIDE_FLAG, wideMin: WIDE_PANEL_MIN, titleSide: TITLE_SIDE_ATTRIBUTE,
    ids: { handle: HANDLE_ID, superTop: SUPER_TOP_ID, superBottom: SUPER_BOTTOM_ID, rail: SIDE_RAIL_ID },
    own: HEALTH_OWN, made: HEALTH_MADE,
    sel: {
      tile: ".epitaxy-chat-panel", header: ".epitaxy-titlebar", feed: PANEL_TRANSCRIPT.trim(), editor: ".ProseMirror",
      dockEditor: '[class~="group/approval-dock"] .ProseMirror', dock: '[class~="group/approval-dock"]', shell: ".epitaxy-prompt",
      modelRow: '[data-cds="ChatComposerChin"]', modelButton: NEW_WINDOW_MODEL_SELECTOR, usageRing: USAGE_RING_SELECTOR,
      sidebarButton: '[aria-label="Show sidebar"],[aria-label="Hide sidebar"],[aria-label="Показать боковую панель"],[aria-label="Скрыть боковую панель"]', collapsedChrome: ".df-collapsed-chrome",
      title: CORNER_TITLE_SELECTOR, send: `${SEND_SELECTOR},${AUTO_STOP_SELECTOR}`, fileCard: MENTION_CARD_SELECTOR,
      overlay: `${CLAUDE_POPUP_SELECTOR},[role="dialog"],#${PMP_PANEL_ID}`, peek: ".dframe-root[data-collapsed][data-hovering]",
      lookHost: ".dframe-root", composerFill: '[data-cds="ChatComposer"] > div[class*="bg-surface"]', sidebar: "aside.dframe-sidebar",
    },
  };
  const healthInstalledAt = new Date().toISOString();
  const healthNow = () => {
    if (chatKind() === "other") return null;
    let status = {};
    try { status = statusView(); } catch {}
    return healthRun(window, { ...HEALTH_PAGE, version: VERSION, installedAt: healthInstalledAt, status });
  };
  HATCH && Object.assign(HATCH, { healthRun, HEALTH_PAGE });
