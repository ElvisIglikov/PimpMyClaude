  // ---- 12л. Просмотр фото (#7667, #7668, WF87) -----------------------------
  // Слово Элвиса 25.09 ~21:00: в узком окне всплывашка Claude с фото обрезана
  // краями окна — «чтобы при нажатии оно расширялось… на весь экран… и
  // лево-вправо все фотки, которые в чате были». Клик по фото в ленте чата
  // открывает НАШ просмотр вместо всплывашки Claude: слой на всё окно, фото
  // целиком, и само окно растягивается на свободную площадь своего монитора;
  // закрытие возвращает окну прежнюю рамку. Растянуть нельзя (главное окно) —
  // остаётся слой на всё окно. ← →, кнопки ‹ ›, свайп трекпадом
  // вбок — соседние фото того же сообщения, без круга (#10230, слово Элвиса
  // 18.10: «должен только между ними ходить… и оно не должно зацикливаться»);
  // Esc, ✕, клик по фону — закрыть.
  // Масштаб (#9469): колесо и щипок трекпада — от точки под курсором, двойной
  // клик — 100 % и обратно целиком, полоса внизу «− 37 % + По ширине», клавиши
  // + − 0; увеличенное двигают перетаскивание, свайп вбок и ↑ ↓.
  // Подержал курсор на фото в ленте — оно раскрывается само (#9817, photoHover).
  //
  // Разведка 25.09 (Claude 2.9939.2): лента — [data-testid="epitaxy-virtual-transcript"]
  // (role=feed, виртуальная: в DOM только ряды рядом с экраном — их фото и
  // листаются); фото — <img> с data:-адресом ПОЛНОГО размера (natural 640×1440
  // при превью 71×160). В главном окне оно в span[role=button] плитки, чей
  // ::after накрывает фото (нажатие приходит в span), и react-aria ловит
  // нажатие на pointerdown; в попапе — button[aria-label^="View image"] с
  // onClick. Поэтому нажатие по фото глотаем на захвате документа целиком:
  // pointerdown, mousedown и click. Миниатюра вкладки Browser («Open Browser
  // tab») — не фото. Esc и стрелки, пока просмотр открыт, глотаются на захвате
  // окна: Esc в чате Claude Code останавливает работающего агента.
  //
  // Живой замер 25.09 в попапе: requestFullscreen() у Claude не отвечает вовсе
  // (промис висит, окно не меняется), а window.moveTo/resizeTo попапу, открытому
  // window.open, послушны. Поэтому полноэкранный режим не просим (гейт 2 WF87):
  // окно сразу растягивается на доступную площадь монитора, где оно стоит.
  const PHOTO_VIEW_ID = "myclaude-photo-view";
  const PHOTO_FEED_SELECTOR = '[data-testid="epitaxy-virtual-transcript"],[role="feed"]';
  const PHOTO_IMG_SELECTOR = '[data-testid="epitaxy-virtual-transcript"] img,[role="feed"] img';
  // Сообщение ленты — строка transcript-row (у старой ленты — ряд group/message-row): листаются фото только его.
  const PHOTO_MESSAGE_SELECTOR = `[data-testid="transcript-row"],${MESSAGE_ROW_SELECTOR}`;
  // Карточка HTML/PDF (#10229, раздел 12м⁴) — снимок страницы, не фото: её нажатие — файл в PimpViewer. Кадр ролика
  // (#10699, раздел 12п⁵) — тоже не фото: его нажатие — ролик в панели материалов.
  // #11304 (слово Элвиса 30.10: «HTML открываю, ты эту HTML как картинку открываешь… ни прокрутить, ни скопировать»):
  // снимок страницы в карточке SendUserFile (#10603) помечен card-doc / plate-doc / square-doc — всё на «doc»; его
  // нажатие идёт в карточку (fileClick, раздел 12д), снимок остаётся превью и в листание ‹ › не входит.
  // Перетаскивание 12м² берёт список без снимков страниц: карточка HTML/PDF тащится файлом, а не снимком.
  const PHOTO_SKIP_DRAG_SELECTOR = `button[aria-label="Open Browser tab"],button[aria-label="Открыть вкладку браузера"],.epitaxy-attachment-pill,[contenteditable="true"],[${MEDIA_PLAY_ATTRIBUTE}]`;
  const PHOTO_SKIP_SELECTOR = `${PHOTO_SKIP_DRAG_SELECTOR},[${HEIC_ATTRIBUTE}$="doc"]`;
  // Меньше по обеим сторонам — значок, а не фото: натуральный размер и размер
  // на экране (значок 128×128, показанный 16×16, — всё равно значок; живая
  // плитка фото — 71×160).
  const PHOTO_MIN = 64;
  const PHOTO_MIN_SHOWN = 40;
  // Сдвиг трекпада вбок на одно листание, и тишина колеса, после которой
  // начинается новый жест: инерция одного свайпа листает один раз.
  const PHOTO_SWIPE = 60;
  const PHOTO_SWIPE_REST_MS = 300;
  // Дальше этого — перетаскивание 100 %-го фото, а не клик.
  const PHOTO_DRAG = 4;
  const PHOTO_KEYS = ["Escape", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"];
  // Масштаб с клавиатуры (#9469): + − 0 по месту клавиши — в любой раскладке;
  // с ⌘/⌃/⌥ это масштаб самого Claude, не наш.
  const PHOTO_ZOOM_CODES = { Equal: 1, NumpadAdd: 1, Minus: -1, NumpadSubtract: -1, Digit0: 0, Numpad0: 0 };
  // Полоса масштаба (#9469): шаг кнопок и + −, мягкость колеса (щипок — PHOTO_PINCH_RATE),
  // сдвиг ↑ ↓ — доля высоты окна. Метки полосы и «подсмотра» (#9817) — для правил lateRules.
  const PHOTO_ZOOM_STEP = 1.5;
  const PHOTO_WHEEL_RATE = 0.0025;
  const PHOTO_PAN_SHARE = 0.15;
  const PHOTO_BAR_ATTRIBUTE = "data-myclaude-photo-bar";
  const PHOTO_PEEK_ATTRIBUTE = "data-myclaude-photo-peek";
  const PHOTO_WIDE_LABEL = "По ширине";
  const PHOTO_WHOLE_LABEL = "Целиком";
  // «▦ Все» (WF120, #7533): подпись, подпись отказа, сколько ждать ответа
  // приложения и сколько держать подпись отказа.
  const PHOTO_ALL_LABEL = "▦ Галерея";
  const PHOTO_ALL_FAIL_LABEL = "⚠️ PMP не ответил";
  const PHOTO_ALL_WAIT_MS = 3000;
  const PHOTO_ALL_FAIL_MS = 2500;
  const photoState = {
    open: false, list: [], index: 0, zoom: false,
    drag: null, dragged: false, swipe: 0, swipeAt: -Infinity,
    keys: new Set(), focus: null, before: null, layer: null, parts: null, grown: null,
    openedAt: -Infinity, from: null, takeovers: 0, peek: null,
  };
  const photoStyle = (node, styles) => {
    for (const [name, value] of Object.entries(styles)) node.style.setProperty(name, value);
  };
  const photoSrc = img => String(img?.currentSrc || img?.src || img?.getAttribute?.("src") || "");
  // Снимок файла — не фото (#11304, слово Элвиса 31.10 ~01:55: «эту HTML, как картинку открываешь… ни прокрутить,
  // ни скопировать… при нажатии на неё… должна открываться»): превью страницы или PDF во всех видах карточки 12м⁴
  // (doc, plate-doc, card-doc, square-doc) и своя картинка Claude в карточке файла, который сам не картинка. Нажатие
  // и наведение такую картинку не раскрывают — нажатие уходит карточке (файл в панель, 12д), тащится файл, не снимок.
  const PHOTO_SHOT_SELECTOR = `[${HEIC_ATTRIBUTE}$="doc"]`;
  const PHOTO_FILE_RE = /\.(png|jpe?g|gif|webp|bmp|tiff?|hei[cf]|avif|svg)$/i;
  const photoIsShot = node => {
    if (node.closest(PHOTO_SHOT_SELECTOR)) return true;
    const card = node.closest('button[title^="/"]');
    return Boolean(card) && !PHOTO_FILE_RE.test(String(card.getAttribute("title") ?? "").trim());
  };
  const isChatPhoto = node => {
    if (!themable || !node || node.nodeType !== 1 || node.tagName !== "IMG") return false;
    if (!node.closest(PHOTO_FEED_SELECTOR) || node.closest(PHOTO_SKIP_SELECTOR) || photoIsShot(node)) return false;
    if (Math.max(Number(node.naturalWidth) || 0, Number(node.naturalHeight) || 0) < PHOTO_MIN) return false;
    const shown = node.getBoundingClientRect?.();
    if (!shown || Math.max(Number(shown.width) || 0, Number(shown.height) || 0) < PHOTO_MIN_SHOWN) return false;
    return Boolean(photoSrc(node));
  };
  // Фото чата по порядку ленты (scope — сообщение: только его фото); одно и то же фото дважды — одно.
  const photoList = (scope = null) => {
    const seen = new Set();
    const out = [];
    let nodes = [];
    try { nodes = [...(scope ?? document).querySelectorAll(scope ? "img" : PHOTO_IMG_SELECTOR)]; } catch { nodes = []; }
    for (const img of nodes) {
      if (!isChatPhoto(img)) continue;
      const src = photoSrc(img);
      if (seen.has(src)) continue;
      seen.add(src);
      out.push({ src, img });
    }
    return out;
  };
  // Фото под нажатием: сам <img> или кнопка-плитка ровно с одним фото внутри.
  const photoAt = target => {
    if (!target || target.nodeType !== 1) return null;
    if (target.tagName === "IMG") return isChatPhoto(target) ? target : null;
    const press = target.closest?.('button,[role="button"]');
    if (!press) return null;
    // #8890: в плитке бывают и значки (иконка типа, бейдж) — фото считаем
    // только то, что им по размеру является; ровно одно — его и открываем.
    const imgs = [...press.querySelectorAll("img")].filter(isChatPhoto);
    return imgs.length === 1 ? imgs[0] : null;
  };
  // #8890: своя всплывашка Claude с одной картинкой (ImagePreviewModal, Claude
  // 08.10: base-ui Dialog, кнопка data-testid="close-file-preview", листания
  // нет). Открылась мимо нас — ← → и свайп вбок переводят её в наш просмотр.
  const PHOTO_CLAUDE_CLOSE = '[data-testid="close-file-preview"]';
  const photoClaudePreview = () => {
    if (!themable || photoState.open) return null;
    let dialogs = [];
    try { dialogs = [...document.querySelectorAll('[role="dialog"]')]; } catch { dialogs = []; }
    for (const dialog of dialogs) {
      if (dialog.id === PHOTO_VIEW_ID) continue;
      if (dialog.querySelector?.('[contenteditable="true"],textarea,input,select')) continue;
      const imgs = [...dialog.querySelectorAll("img")].filter(img => photoSrc(img)
        && Math.max(Number(img.naturalWidth) || 0, Number(img.naturalHeight) || 0) >= PHOTO_MIN);
      if (imgs.length !== 1) continue;
      // Без своей кнопки закрытия — только диалог, где кроме фото ничего нет.
      const close = dialog.querySelector(PHOTO_CLAUDE_CLOSE);
      // #11618: «Close…» по-русски — «Закрыть…» (каталог claude.ai).
      if (!close && dialog.querySelector('button:not([aria-label*="lose"],[aria-label*="акрыть"]),a[href]')) continue;
      return { dialog, img: imgs[0], close };
    }
    return null;
  };
  const photoTakeOver = (preview, delta) => {
    const src = photoSrc(preview.img);
    const at = photoList().find(item => item.src === src);
    if (preview.close) { try { pressLikeMouse(preview.close); } catch {} }
    if (at) photoOpen(at.img);
    else photoOpen(0, src);
    photoState.takeovers += 1;
    return photoStep(delta);
  };
  const photoView = () => ({
    open: photoState.open, index: photoState.index, total: photoState.list.length,
    zoom: photoState.zoom, grown: Boolean(photoState.grown),
  });
  const photoButton = (layer, text, label, styles) => {
    const button = document.createElement("button");
    button.setAttribute("type", "button");
    button.setAttribute("aria-label", label);
    button.textContent = text;
    photoStyle(button, {
      position: "absolute", border: "none", margin: "0", padding: "0", color: "#fff",
      background: "rgba(255,255,255,0.14)", cursor: "pointer", "line-height": "1",
      "font-family": "-apple-system, system-ui, sans-serif", ...styles,
    });
    layer.appendChild(button);
    return button;
  };
  // Слой один на окно и живёт до dispose: закрытие его только прячет, и
  // повторное открытие слоёв не плодит.
  const photoLayer = () => {
    const host = document.body ?? document.documentElement;
    if (photoState.layer) {
      if (!photoState.layer.isConnected) host.appendChild(photoState.layer);
      return photoState.layer;
    }
    for (const orphan of document.querySelectorAll(`#${PHOTO_VIEW_ID}`)) orphan.remove();
    const layer = document.createElement("div");
    layer.id = PHOTO_VIEW_ID;
    layer.setAttribute("aria-label", "Просмотр фото");
    layer.setAttribute("tabindex", "-1");
    photoStyle(layer, {
      position: "fixed", inset: "0px", display: "none", "z-index": "2147483647",
      background: "rgba(0,0,0,0.94)", outline: "none", "user-select": "none",
      "-webkit-app-region": "no-drag", "overscroll-behavior": "contain",
    });
    const stage = document.createElement("div");
    photoStyle(stage, {
      position: "absolute", inset: "0px", overflow: "hidden",
      display: "grid", "place-items": "safe center",
    });
    const img = document.createElement("img");
    img.setAttribute("alt", "");
    img.setAttribute("draggable", "false");
    stage.appendChild(img);
    layer.appendChild(stage);
    const side = { top: "50%", transform: "translateY(-50%)", width: "36px", height: "56px", "border-radius": "10px", "font-size": "30px" };
    const prev = photoButton(layer, "‹", "Предыдущее фото", { ...side, left: "6px" });
    const next = photoButton(layer, "›", "Следующее фото", { ...side, right: "6px" });
    const close = photoButton(layer, "✕", "Закрыть", {
      top: "8px", right: "8px", width: "32px", height: "32px", "border-radius": "16px", "font-size": "16px",
    });
    // «▦ Все» (WF120, #7533) — левее ✕; видна по photoAllPaint.
    const all = photoButton(layer, PHOTO_ALL_LABEL, "Файлы этого чата", {
      top: "8px", right: "48px", height: "32px", padding: "0 12px", "border-radius": "16px", "font-size": "13px",
      display: "none",
    });
    // Полоса внизу: «3 / 7» и масштаб «− 37 % + По ширине» (#9469, слова — как в галерее
    // PimpViewer). В «подсмотре» (#9817) кнопок нет — до них курсор не дойдёт, не закрыв
    // просмотр; вместо них подсказка «клик — оставить».
    const bar = document.createElement("div");
    bar.setAttribute(PHOTO_BAR_ATTRIBUTE, "");
    photoStyle(bar, {
      position: "absolute", bottom: "10px", left: "50%", transform: "translateX(-50%)",
      display: "flex", "align-items": "center", gap: "2px", padding: "2px", "border-radius": "16px",
      // Плотнее прежней плашки «3 / 7»: под полосой бывает увеличенный текст снимка.
      background: "rgba(0,0,0,0.72)", "backdrop-filter": "blur(12px)", color: "#fff", "white-space": "nowrap",
      "font": "12px -apple-system, system-ui, sans-serif", "font-variant-numeric": "tabular-nums",
    });
    const count = document.createElement("span");
    photoStyle(count, { padding: "0 8px", "line-height": "28px", "pointer-events": "none" });
    bar.appendChild(count);
    const hint = document.createElement("span");
    hint.setAttribute(`${PHOTO_BAR_ATTRIBUTE}-hint`, "");
    hint.textContent = "клик — оставить";
    photoStyle(hint, { padding: "0 10px 0 2px", "line-height": "28px", opacity: "0.7", "pointer-events": "none" });
    bar.appendChild(hint);
    const tool = (text, label, styles) => photoButton(bar, text, label, {
      position: "relative", height: "28px", "min-width": "28px", "border-radius": "14px",
      background: "transparent", "font-size": "13px", ...styles,
    });
    const zoomOut = tool("−", "Уменьшить", { "font-size": "17px" });
    const pct = tool("", "100 % или целиком", { padding: "0 4px", "min-width": "52px", "font-size": "12px" });
    const zoomIn = tool("+", "Увеличить", { "font-size": "17px" });
    const wide = tool(PHOTO_WIDE_LABEL, "Во всю ширину окна", { padding: "0 12px", "min-width": "96px" });
    zoomOut.title = "Уменьшить (−)";
    zoomIn.title = "Увеличить (+)";
    pct.title = "100 % или целиком — как двойной клик по фото";
    layer.appendChild(bar);
    host.appendChild(layer);
    photoState.layer = layer;
    photoState.parts = { stage, img, prev, next, close, all, count, bar, zoomOut, pct, zoomIn, wide };
    on(layer, "click", onPhotoLayerClick);
    on(layer, "dblclick", onPhotoDblClick);
    on(img, "load", photoPaintZoom);
    on(window, "resize", photoPaintZoom);
    on(layer, "pointerdown", onPhotoDragStart);
    on(layer, "pointermove", onPhotoDragMove);
    on(layer, "pointerup", onPhotoDragEnd);
    on(layer, "pointercancel", onPhotoDragEnd);
    on(layer, "wheel", onPhotoWheel, { passive: false });
    return layer;
  };
  // 100 %: фото в натуральную величину, лишнее — прокруткой и перетаскиванием;
  // точка под курсором остаётся под курсором.
  const photoZoom = (on100, x = null, y = null) => {
    const parts = photoState.parts;
    if (!parts) return;
    const box = parts.img.getBoundingClientRect();
    photoState.zoom = Boolean(on100);
    photoState.drag = null;
    photoStyle(parts.stage, { overflow: on100 ? "auto" : "hidden" });
    photoStyle(parts.img, on100
      ? { "max-width": "none", "max-height": "none", width: "auto", cursor: "grab" }
      // Единицы окна, а не %: у ряда сетки высота не задана, и 100 % по
      // высоте не держало (живой замер 25.09: фото 1080×1350 в окне высотой
      // 789 вылезло за низ).
      // Одиночный клик по фото больше не увеличивает (двойной — да, #9469): курсор обычный.
      : { "max-width": "100vw", "max-height": "100vh", width: "auto", "object-fit": "contain", cursor: "default" });
    if (on100 && x != null && box.width && box.height) {
      const width = Number(parts.img.naturalWidth) || 0;
      const height = Number(parts.img.naturalHeight) || 0;
      const room = parts.stage.getBoundingClientRect();
      parts.stage.scrollLeft = Math.max(0, ((x - box.left) / box.width) * width - (x - room.left));
      parts.stage.scrollTop = Math.max(0, ((y - box.top) / box.height) * height - (y - room.top));
    }
    photoPaintZoom();
  };
  // Щипок трекпада (слово Элвиса 10.10 22:50: «открыл фотку, она на весь экран отображается, а я не
  // могу здесь увеличить… чтобы щипок работал»). Щипок приходит колесом с ctrlKey, deltaY — сотые
  // доли логарифма масштаба. Фото растёт и уменьшается плавно, точка под пальцами остаётся на месте;
  // потолок — PHOTO_PINCH_MAX натуральных размеров, меньше вида «целиком» — снова «целиком».
  // Увеличенное двигают прокрутка и перетаскивание, как 100 %; клик по нему возвращает «целиком».
  const PHOTO_PINCH_RATE = 0.01;
  const PHOTO_PINCH_MAX = 4;
  // Размеры для масштаба: натуральные, на экране, окно просмотра и ширина вида «целиком» (fit).
  const photoMeasure = () => {
    const parts = photoState.parts;
    if (!parts) return null;
    const wide = Number(parts.img.naturalWidth) || 0;
    const tall = Number(parts.img.naturalHeight) || 0;
    const box = parts.img.getBoundingClientRect();
    const room = parts.stage.getBoundingClientRect();
    if (!wide || !tall || !box.width || !box.height || !room.width || !room.height) return null;
    return { parts, wide, tall, box, room, fit: wide * Math.min(1, room.width / wide, room.height / tall) };
  };
  // Фото шириной width px; точка (x, y) остаётся под курсором, без точки — середина окна. Не шире
  // PHOTO_PINCH_MAX натуральных; уже вида «целиком» — снова «целиком». Щипок, колесо, + − и полоса — здесь.
  const photoResize = (width, x = null, y = null) => {
    const m = photoMeasure();
    if (!m || !Number.isFinite(width)) return false;
    const { parts, box, room } = m;
    width = Math.min(width, m.wide * PHOTO_PINCH_MAX);
    if (width <= m.fit + 0.5) { photoZoom(false); return true; }
    if (x == null || y == null) { x = room.left + room.width / 2; y = room.top + room.height / 2; }
    const fx = (x - box.left) / box.width;
    const fy = (y - box.top) / box.height;
    photoState.zoom = true;
    photoState.drag = null;
    photoStyle(parts.stage, { overflow: "auto" });
    photoStyle(parts.img, { "max-width": "none", "max-height": "none", width: `${Math.round(width)}px`, cursor: "grab" });
    const grown = parts.img.getBoundingClientRect();
    parts.stage.scrollLeft = Math.max(0, (Number(parts.stage.scrollLeft) || 0) + grown.left + fx * grown.width - x);
    parts.stage.scrollTop = Math.max(0, (Number(parts.stage.scrollTop) || 0) + grown.top + fy * grown.height - y);
    photoPaintZoom();
    return true;
  };
  const photoPinch = (deltaY, x, y, rate = PHOTO_PINCH_RATE) => {
    const m = photoMeasure();
    if (m && deltaY) photoResize(m.box.width * Math.exp(-deltaY * rate), x, y);
  };
  const photoZoomBy = factor => {
    const m = photoMeasure();
    if (m) photoResize(m.box.width * factor);
  };
  // «По ширине» (#9469, как в PimpViewer): во всю ширину окна, верх — у верхнего края, высокий
  // снимок дальше двигают ↓, колесо вбок и перетаскивание. Уже по ширине — «Целиком». Фото и так
  // во всю ширину — кнопка гаснет.
  const photoWideRoom = m => m.room.width > m.fit + 1 && m.fit < m.wide * PHOTO_PINCH_MAX;
  const photoIsWide = m => photoState.zoom && Math.abs(m.box.width - Math.min(m.room.width, m.wide * PHOTO_PINCH_MAX)) < 1.5;
  const photoWide = () => {
    const m = photoMeasure();
    if (!m || !photoWideRoom(m)) return;
    if (photoIsWide(m)) { photoZoom(false); return; }
    photoResize(m.room.width, m.room.left, m.room.top);
    m.parts.stage.scrollLeft = 0;
    m.parts.stage.scrollTop = 0;
  };
  // Двойной клик и «37 %» на полосе: увеличенное — целиком; целиком — 100 % в точку (фото меньше
  // окна и так 100 % — вдвое).
  const photoToggle = (x = null, y = null) => {
    const m = photoMeasure();
    if (!m) return;
    if (photoState.zoom) { photoZoom(false); return; }
    if (x == null || y == null) { x = m.room.left + m.room.width / 2; y = m.room.top + m.room.height / 2; }
    if (m.fit < m.wide - 0.5) photoZoom(true, x, y);
    else photoResize(m.fit * 2, x, y);
  };
  const photoPan = (dx, dy) => {
    const stage = photoState.parts?.stage;
    if (!stage || !photoState.zoom) return;
    stage.scrollLeft = Math.max(0, (Number(stage.scrollLeft) || 0) + dx);
    stage.scrollTop = Math.max(0, (Number(stage.scrollTop) || 0) + dy);
  };
  const photoEnable = (button, ok) => {
    if (ok) button.removeAttribute("aria-disabled");
    else button.setAttribute("aria-disabled", "true");
  };
  // Вид полосы: проценты — от натурального размера, «−» гаснет у «целиком», «+» — у потолка.
  const photoPaintZoom = () => {
    const parts = photoState.parts;
    if (!parts?.bar || !photoState.open) return;
    const m = photoMeasure();
    parts.pct.textContent = m ? `${Math.round((m.box.width / m.wide) * 100)} %` : "";
    photoEnable(parts.zoomOut, Boolean(m && photoState.zoom));
    photoEnable(parts.zoomIn, Boolean(m && m.box.width < m.wide * PHOTO_PINCH_MAX - 0.5));
    photoEnable(parts.pct, Boolean(m));
    photoEnable(parts.wide, Boolean(m && photoWideRoom(m)));
    const whole = Boolean(m && photoIsWide(m));
    parts.wide.textContent = whole ? PHOTO_WHOLE_LABEL : PHOTO_WIDE_LABEL;
    parts.wide.title = whole ? "Вся картинка в окне" : "Во всю ширину окна";
  };
  lateRules.push(
    `#${PHOTO_VIEW_ID} [${PHOTO_BAR_ATTRIBUTE}] button:hover:not([aria-disabled="true"]){background:rgba(255,255,255,.18) !important}`,
    `#${PHOTO_VIEW_ID} [${PHOTO_BAR_ATTRIBUTE}] button[aria-disabled="true"]{opacity:.35 !important;cursor:default !important}`,
    `#${PHOTO_VIEW_ID}:not([${PHOTO_PEEK_ATTRIBUTE}]) [${PHOTO_BAR_ATTRIBUTE}-hint]{display:none !important}`,
    `#${PHOTO_VIEW_ID}[${PHOTO_PEEK_ATTRIBUTE}] button{display:none !important}`,
  );
  // «▦ Все» (WF120, #7533): все файлы чата — сеткой в Pimp Viewer. Своей сетки
  // в просмотре нет: её номера разошлись бы с номерами, которые понимает чат
  // (#7851). Запрос — тот же, что у «▦ Галерея» (К-V1, раздел 12п:
  // GET /viewer?chat=<id>&on=1); ответ не закрывает просмотр: готовность Viewer
  // этим каналом не подтверждается. Видна, только
  // если у чата есть файлы во Viewer (viewer-counts, К-V7). Ждёт ответа — буквы
  // переливаются (правило BUSY_ATTRIBUTE раздела 4, как у плашки «⏳ Уже открываю
  // окно…», #7772), второй раз не жмётся; отказ или нет ответа за
  // PHOTO_ALL_WAIT_MS — надпись отказа на кнопке, просмотр остаётся (плашка
  // newWindowNote лежит ниже слоя просмотра и видна не была бы). Закрытие
  // просмотра и dispose снимают ожидание; поздний ответ ничего не закрывает.
  const photoAllState = { token: 0, busy: false, timer: 0 };
  const photoAllSet = (busy, label = PHOTO_ALL_LABEL) => {
    const button = photoState.parts?.all;
    if (!button) return;
    button.textContent = "";
    if (busy) {
      const span = document.createElement("span");
      span.setAttribute(BUSY_ATTRIBUTE, "1");
      span.style.setProperty("pointer-events", "none");
      span.textContent = label;
      button.appendChild(span);
      button.setAttribute("aria-disabled", "true");
    } else {
      button.textContent = label;
      button.removeAttribute("aria-disabled");
    }
    button.style.setProperty("cursor", busy ? "progress" : "pointer");
  };
  const photoAllStop = () => {
    photoAllState.token += 1;
    photoAllState.busy = false;
    if (photoAllState.timer) { clearTimeout(photoAllState.timer); photoAllState.timer = 0; }
    photoAllSet(false);
  };
  const photoAllPaint = () => {
    const button = photoState.parts?.all;
    if (!button) return false;
    const files = galleryChat() ? galleryNumbers().files : 0;
    button.style.setProperty("display", files > 0 ? "block" : "none");
    button.title = `Файлы этого чата (${files})`;
    return files > 0;
  };
  const photoAllFail = token => {
    if (token !== photoAllState.token) return;
    photoAllStop();
    photoAllSet(false, PHOTO_ALL_FAIL_LABEL);
    photoAllState.timer = setTimeout(() => { photoAllState.timer = 0; photoAllSet(false); }, PHOTO_ALL_FAIL_MS);
  };
  const photoAll = () => {
    if (photoAllState.busy || !photoState.open || !photoAllPaint()) return false;
    const chat = galleryChat();
    photoAllStop();
    const token = photoAllState.token;
    photoAllState.busy = true;
    photoAllSet(true);
    photoAllState.timer = setTimeout(() => { photoAllState.timer = 0; photoAllFail(token); }, PHOTO_ALL_WAIT_MS);
    try {
      fetch(galleryUrl(chat, true), { mode: "cors", credentials: "omit", cache: "no-store" })
        .then(response => {
          if (token !== photoAllState.token || !state.alive || !photoState.open) return;
          if (chat !== galleryChat()) { photoAllStop(); return; }
          if (!response?.ok) { photoAllFail(token); return; }
          // HTTP ACK подтверждает запрос, но не окно Viewer: слой остаётся.
          photoAllStop();
        }, () => photoAllFail(token));
    } catch { photoAllFail(token); }
    return true;
  };
  const photoShow = () => {
    const parts = photoState.parts;
    const item = photoState.list[photoState.index];
    if (!parts || !item) return;
    photoZoom(false);
    parts.img.src = item.src;
    const total = photoState.list.length;
    parts.count.textContent = `${photoState.index + 1} / ${total}`;
    // Без круга (#10230): у первого фото нет «‹», у последнего — «›».
    parts.prev.style.setProperty("display", photoState.index > 0 ? "block" : "none");
    parts.next.style.setProperty("display", photoState.index < total - 1 ? "block" : "none");
    photoAllPaint();
    photoPaintZoom();
  };
  // Окно на всю доступную площадь своего монитора; прежняя рамка — в grown.
  const photoGrow = () => {
    if (!photoState.open || photoState.grown) return;
    const scr = window.screen;
    const was = [window.screenX, window.screenY, window.outerWidth, window.outerHeight].map(Number);
    if (!scr || typeof window.resizeTo !== "function" || !was.every(Number.isFinite)) return;
    const to = [Number(scr.availLeft) || 0, Number(scr.availTop) || 0, Number(scr.availWidth) || 0, Number(scr.availHeight) || 0];
    if (was[2] >= to[2] && was[3] >= to[3]) return;
    try { window.moveTo(to[0], to[1]); window.resizeTo(to[2], to[3]); } catch { return; }
    photoState.grown = was;
    // Растянутое окно — поверх соседних окон Claude.
    try { window.focus(); } catch {}
  };
  const photoShrink = () => {
    const was = photoState.grown;
    photoState.grown = null;
    if (!was) return;
    try { window.resizeTo(was[2], was[3]); window.moveTo(was[0], was[1]); } catch {}
  };
  // Открыть с фото: номер в списке или сам <img> из ленты. first — data:
  // фото из карточки файла (WF103, раздел 12д¹): оно первое, дальше фото ленты.
  const PHOTO_BEFORE_MS = 5000;
  // peek — раскрыто наведением (#9817): фокус остаётся в поле ввода, уход с плитки закрывает.
  const photoOpen = (target = 0, first = "", peek = false) => {
    if (!themable || !state.alive) return photoView();
    // Нажали фото ленты — листаются фото его сообщения (#10230); номер или фото карточки — вся лента.
    const message = !first && typeof target !== "number" ? target?.closest?.(PHOTO_MESSAGE_SELECTOR) ?? null : null;
    const feed = photoList(message);
    const list = first ? [{ src: first, img: null }, ...feed.filter(item => item.src !== first)] : feed;
    const index = first ? 0 : typeof target === "number" ? target : list.findIndex(item => item.src === photoSrc(target));
    if (!list.length || index < 0 || index >= list.length) return photoView();
    const layer = photoLayer();
    photoState.list = list;
    photoState.index = index;
    photoState.from = first ? "card" : "feed";
    if (!photoState.open) {
      photoState.open = true;
      photoState.openedAt = now();
      photoState.swipe = 0;
      // Фокус до нажатия по фото (не старше PHOTO_BEFORE_MS) сильнее того, что
      // осталось после mousedown по плитке.
      const before = photoState.before;
      photoState.before = null;
      const fresh = before?.node?.isConnected && now() - before.at <= PHOTO_BEFORE_MS ? before.node : null;
      photoState.focus = fresh ?? document.activeElement ?? null;
      // role="dialog" — только пока открыт: закрытый слой в DOM с этой ролью ловят
      // OVERLAY_SELECTOR и сторож Esc (раздел 16), и Esc снова останавливал бы агента.
      layer.setAttribute("role", "dialog");
      layer.setAttribute("aria-modal", "true");
      layer.style.setProperty("display", "block");
      if (peek) layer.setAttribute(PHOTO_PEEK_ATTRIBUTE, "");
      else { try { layer.focus({ preventScroll: true }); } catch {} }
      photoGrow();
    }
    photoShow();
    return photoView();
  };
  // why = "leave" — курсор ушёл с плитки «подсмотра» (#9817); иначе фото под курсором само
  // не раскроется снова, пока курсор с него не уйдёт.
  const photoClose = why => {
    if (!photoState.open) return photoView();
    photoState.open = false;
    photoState.peek = null;
    photoHover.skip = why === "leave" ? null : "next";
    photoAllStop();
    photoState.drag = null;
    photoState.dragged = false;
    photoZoom(false);
    const layer = photoState.layer;
    layer?.style.setProperty("display", "none");
    layer?.removeAttribute("role");
    layer?.removeAttribute("aria-modal");
    layer?.removeAttribute(PHOTO_PEEK_ATTRIBUTE);
    // data:-адрес фото — мегабайты: отпускаем его вместе со списком.
    try { photoState.parts?.img.removeAttribute("src"); } catch {}
    photoState.list = [];
    photoShrink();
    const back = photoState.focus;
    photoState.focus = null;
    try { if (back?.isConnected) back.focus({ preventScroll: true }); } catch {}
    return photoView();
  };
  const photoStep = delta => {
    const total = photoState.list.length;
    if (!photoState.open || total < 2 || !delta) return photoView();
    const next = photoState.index + Math.sign(delta);
    if (next < 0 || next >= total) return photoView();
    photoState.index = next;
    photoShow();
    return photoView();
  };
  // Нажатие по фото в ленте (захват документа): Claude его не видит вовсе.
  // Правая кнопка и нажатие с клавишей остаются Claude. pointerdown и
  // mousedown только глушим, но НЕ отменяем: отменённый pointerdown в
  // Chromium отменяет и начало перетаскивания (раздел 12м², #7685).
  const onPhotoPress = event => {
    if (event.type === "pointerdown") photoHoverStop();
    if (photoState.open || (Number(event.button) || 0) !== 0) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const img = photoAt(event.target);
    if (!img) return;
    event.stopImmediatePropagation();
    // Где был фокус ДО нажатия: mousedown по плитке уводит его на плитку, и
    // после закрытия просмотра курсор должен вернуться в поле ввода.
    if (event.type === "pointerdown") {
      photoState.before = { node: document.activeElement ?? null, at: now() };
    }
    if (event.type !== "click") return;
    event.preventDefault();
    photoOpen(img);
  };
  // Esc и стрелки при открытом просмотре — только нам (захват окна). Отпускание
  // клавиши, нажатой в просмотре, тоже глотаем: Esc закрыл просмотр, и его
  // keyup уже не должен дойти до Claude.
  // + − 0 (#9469) — по коду клавиши; ↑ ↓ двигают увеличенное. Любая клавиша, кроме Esc, оставляет
  // «подсмотр» (#9817) открытым; чужая клавиша его закрывает — фокус и так в поле ввода.
  const onPhotoKey = event => {
    if (event.type === "keydown") photoHoverStop();
    const zoomKey = Object.hasOwn(PHOTO_ZOOM_CODES, event.code ?? "") ? event.code : "";
    const key = zoomKey || event.key;
    if (!zoomKey && !PHOTO_KEYS.includes(key)) {
      if (event.type === "keydown" && photoState.peek) photoClose();
      return;
    }
    if (event.type === "keyup") {
      if (!photoState.keys.has(key)) return;
      photoState.keys.delete(key);
    } else {
      const delta = key === "ArrowLeft" ? -1 : key === "ArrowRight" ? 1 : 0;
      if (zoomKey && (!photoState.open || event.metaKey || event.ctrlKey || event.altKey)) return;
      if (!photoState.open) {
        // Всплывашка Claude с фото (#8890): стрелка — в наш просмотр, на шаг.
        if (!delta || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return;
        const preview = photoClaudePreview();
        if (!preview) return;
        photoState.keys.add(key);
        event.preventDefault();
        event.stopImmediatePropagation();
        photoTakeOver(preview, delta);
        return;
      }
      photoState.keys.add(key);
    }
    event.preventDefault();
    event.stopImmediatePropagation();
    if (event.type !== "keydown") return;
    if (key === "Escape") { photoClose(); return; }
    photoPin();
    const room = photoState.parts?.stage.getBoundingClientRect().height || 0;
    if (zoomKey) {
      const step = PHOTO_ZOOM_CODES[zoomKey];
      if (step) photoZoomBy(step > 0 ? PHOTO_ZOOM_STEP : 1 / PHOTO_ZOOM_STEP);
      else photoZoom(false);
    } else if (key === "ArrowUp" || key === "ArrowDown") photoPan(0, (key === "ArrowUp" ? -1 : 1) * room * PHOTO_PAN_SHARE);
    else photoStep(key === "ArrowLeft" ? -1 : 1);
  };
  // Свайп вбок по всплывашке Claude с фото (#8890) — тот же жест, что в нашем
  // просмотре: один свайп — один шаг, дальше листает уже наш слой.
  const onPhotoClaudeWheel = event => {
    photoHoverStop();
    if (photoState.open) return;
    const dx = Number(event.deltaX) || 0;
    if (Math.abs(dx) <= Math.abs(Number(event.deltaY) || 0)) return;
    const preview = photoClaudePreview();
    if (!preview) return;
    event.preventDefault();
    const t = now();
    if (t - photoState.swipeAt > PHOTO_SWIPE_REST_MS) photoState.swipe = 0;
    photoState.swipeAt = t;
    if (photoState.swipe === null) return;
    photoState.swipe += dx;
    if (Math.abs(photoState.swipe) < PHOTO_SWIPE) return;
    const delta = photoState.swipe > 0 ? 1 : -1;
    photoTakeOver(preview, delta);
    // Инерция того же жеста уже не листает (onPhotoWheel ждёт паузы).
    photoState.swipe = null;
  };
  // Второй клик двойного по фото в ленте (#7772) приходит уже в слой: он не
  // должен ни закрыть просмотр, ни увеличить фото.
  const PHOTO_OPEN_REPEAT_MS = 600;
  // Клик в «подсмотре» (#9817) — оставить открытым, и только. Одиночный клик по фото ничего не
  // делает: масштаб — двойным (#9469), иначе двойной сперва увеличивал бы и сразу возвращал.
  const onPhotoLayerClick = event => {
    const parts = photoState.parts;
    const target = event.target;
    if (Number(event.detail) > 1 && now() - photoState.openedAt < PHOTO_OPEN_REPEAT_MS) return;
    if (photoPin()) return;
    if (target === parts.prev) { photoStep(-1); return; }
    if (target === parts.next) { photoStep(1); return; }
    if (target === parts.close) { photoClose(); return; }
    if (parts.all.contains(target)) { photoAll(); return; }
    if (parts.bar.contains(target)) {
      const button = target.closest?.("button");
      if (!button || button.getAttribute("aria-disabled") === "true") return;
      if (button === parts.zoomOut) photoZoomBy(1 / PHOTO_ZOOM_STEP);
      else if (button === parts.zoomIn) photoZoomBy(PHOTO_ZOOM_STEP);
      else if (button === parts.pct) photoToggle();
      else if (button === parts.wide) photoWide();
      return;
    }
    if (photoState.dragged) { photoState.dragged = false; return; }
    if (target === parts.img) return;
    photoClose();
  };
  // Двойной клик по фото (#9469): 100 % в точку и обратно целиком. Двойной по плитке в ленте,
  // который просмотр и открыл, не в счёт.
  const onPhotoDblClick = event => {
    const parts = photoState.parts;
    if (!parts || event.target !== parts.img || photoState.dragged) return;
    if (now() - photoState.openedAt < PHOTO_OPEN_REPEAT_MS) return;
    event.preventDefault();
    photoToggle(event.clientX, event.clientY);
  };
  const onPhotoDragStart = event => {
    photoState.dragged = false;
    if (!photoState.zoom || event.target !== photoState.parts?.img) return;
    const stage = photoState.parts.stage;
    photoState.drag = { x: event.clientX, y: event.clientY, left: Number(stage.scrollLeft) || 0, top: Number(stage.scrollTop) || 0 };
    photoState.parts.img.style.setProperty("cursor", "grabbing");
    event.preventDefault();
  };
  const onPhotoDragMove = event => {
    const drag = photoState.drag;
    if (!drag) return;
    const dx = event.clientX - drag.x;
    const dy = event.clientY - drag.y;
    if (Math.abs(dx) + Math.abs(dy) > PHOTO_DRAG) photoState.dragged = true;
    photoState.parts.stage.scrollLeft = drag.left - dx;
    photoState.parts.stage.scrollTop = drag.top - dy;
  };
  const onPhotoDragEnd = () => {
    if (!photoState.drag) return;
    photoState.drag = null;
    if (photoState.zoom) photoState.parts.img.style.setProperty("cursor", "grab");
  };
  // Колесо вверх-вниз — масштаб от точки под курсором (#9469); щипок (колесо с ctrlKey) — так же,
  // быстрее. Вбок: увеличенное — сдвиг, целиком — свайп трекпада, пальцы влево (deltaX > 0) —
  // следующее фото. Строки и страницы колеса (deltaMode 1, 2) — в пикселях.
  const PHOTO_WHEEL_UNIT = [1, 40, 800];
  const onPhotoWheel = event => {
    photoPin();
    event.preventDefault();
    const unit = PHOTO_WHEEL_UNIT[Number(event.deltaMode) || 0] ?? 1;
    const dx = (Number(event.deltaX) || 0) * unit;
    const dy = (Number(event.deltaY) || 0) * unit;
    if (event.ctrlKey) { photoPinch(dy, event.clientX, event.clientY); return; }
    const t = now();
    if (t - photoState.swipeAt > PHOTO_SWIPE_REST_MS) photoState.swipe = 0;
    photoState.swipeAt = t;
    if (Math.abs(dy) > Math.abs(dx)) { photoPinch(dy, event.clientX, event.clientY, PHOTO_WHEEL_RATE); return; }
    if (photoState.zoom) { photoPan(dx, 0); return; }
    if (photoState.swipe === null || !dx) return;
    photoState.swipe += dx;
    if (Math.abs(photoState.swipe) < PHOTO_SWIPE) return;
    photoStep(photoState.swipe > 0 ? 1 : -1);
    photoState.swipe = null;
  };
  // Подержал курсор на фото в ленте — оно раскрывается (#9817, слово Элвиса 11.10 ~21:40: «навёл,
  // подержал, чуть-чуть, он так раскрылся… Если на следующий навожу, то нужно тоже долго подержать…
  // Не моментально»). Отсчёт PHOTO_HOVER_MS ставит только настоящее движение мыши над фото (лента,
  // уехавшая под неподвижным курсором, и перерисовка — не в счёт); сдвиг дальше PHOTO_HOVER_STILL —
  // отсчёт заново; ушёл с фото, колесо, клавиша, нажатие, окно не в фокусе — отмена. Раскрытое так —
  // «подсмотр»: курсор ушёл с плитки дальше PHOTO_HOVER_LEAVE (по экрану: окно при раскрытии растёт)
  // или из окна — закрыто, на соседней плитке снова держать; клик, клавиша, колесо — открыто, как
  // нажатием. Закрыл Esc, ✕ или кликом — фото под курсором не раскроется, пока курсор с него не уйдёт.
  const PHOTO_HOVER_MS = 600;
  const PHOTO_HOVER_STILL = 6;
  const PHOTO_HOVER_LEAVE = 12;
  const photoHover = { timer: 0, img: null, x: 0, y: 0, cx: 0, cy: 0, dx: 0, dy: 0, at: null, skip: null, opens: 0 };
  const photoHoverStop = () => {
    if (photoHover.timer) clearTimeout(photoHover.timer);
    photoHover.timer = 0;
    photoHover.img = null;
  };
  const photoPin = () => {
    if (!photoState.peek) return false;
    photoState.peek = null;
    photoState.layer?.removeAttribute(PHOTO_PEEK_ATTRIBUTE);
    try { photoState.layer?.focus({ preventScroll: true }); } catch {}
    return true;
  };
  const photoHoverTile = img => {
    const press = img.closest?.('button,[role="button"]');
    return press && press.contains(img) ? press : img;
  };
  const photoHoverFire = () => {
    const { cx, cy, dx, dy } = photoHover;
    // Отсчёт после ухода с «подсмотра» — без фото: какое под курсором, смотрим по точке сейчас,
    // когда окно уже вернулось в свою рамку.
    let img = photoHover.img;
    if (!img) { try { img = photoAt(document.elementFromPoint(cx, cy)); } catch { img = null; } }
    photoHover.timer = 0;
    photoHover.img = null;
    if (!state.alive || photoState.open || !img?.isConnected || !document.hasFocus?.() || !isChatPhoto(img)) return;
    // Новое сообщение увело ленту из-под неподвижного курсора — фото уже не под ним.
    const box = photoHoverTile(img).getBoundingClientRect();
    if (cx < box.left || cx > box.right || cy < box.top || cy > box.bottom) return;
    photoOpen(img, "", true);
    if (!photoState.open) return;
    photoHover.opens += 1;
    photoState.peek = {
      left: box.left + dx - PHOTO_HOVER_LEAVE, right: box.right + dx + PHOTO_HOVER_LEAVE,
      top: box.top + dy - PHOTO_HOVER_LEAVE, bottom: box.bottom + dy + PHOTO_HOVER_LEAVE,
    };
  };
  const onPhotoHover = event => {
    if (event.pointerType && event.pointerType !== "mouse") return;
    const x = Number(event.screenX) || 0;
    const y = Number(event.screenY) || 0;
    if (photoState.open) {
      const peek = photoState.peek;
      if (!peek) return;
      const gone = event.type === "pointerout" ? !event.relatedTarget
        : x < peek.left || x > peek.right || y < peek.top || y > peek.bottom;
      if (!gone) return;
      photoClose("leave");
      // Движение, уведшее с плитки, могло быть последним и уже над соседним фото: отсчёт и ему.
      if (event.type === "pointerout" || !document.hasFocus?.()) return;
      photoHoverStop();
      Object.assign(photoHover, { x, y, cx: x - photoHover.dx, cy: y - photoHover.dy, at: { x, y } });
      photoHover.timer = setTimeout(photoHoverFire, PHOTO_HOVER_MS);
      return;
    }
    if (event.type === "pointerout") { if (!event.relatedTarget) photoHoverStop(); return; }
    if (photoHover.at && photoHover.at.x === x && photoHover.at.y === y) return;
    photoHover.at = { x, y };
    const img = event.buttons ? null : photoAt(event.target);
    if (photoHover.skip === "next") photoHover.skip = img;
    if (img && img === photoHover.skip) { photoHoverStop(); return; }
    photoHover.skip = null;
    if (!img || !document.hasFocus?.()) { photoHoverStop(); return; }
    if (photoHover.timer && photoHover.img === img && Math.hypot(x - photoHover.x, y - photoHover.y) <= PHOTO_HOVER_STILL) return;
    photoHoverStop();
    const cx = Number(event.clientX) || 0;
    const cy = Number(event.clientY) || 0;
    Object.assign(photoHover, { img, x, y, cx, cy, dx: x - cx, dy: y - cy });
    photoHover.timer = setTimeout(photoHoverFire, PHOTO_HOVER_MS);
  };
  track(() => {
    photoHoverStop();
    try { photoClose(); } catch {}
    photoState.layer?.remove();
    photoState.layer = null;
    photoState.parts = null;
  });
  // Просмотр фото (раздел 12л): открыт ли, какое, откуда список (feed | card, WF103).
  // peek — раскрыт наведением и ещё не оставлен (#9817), hoverOpens — сколько раз наведением.
  statusPart("photo", () => ({
    ...photoView(), from: photoState.from, takeovers: photoState.takeovers,
    peek: Boolean(photoState.peek), hoverOpens: photoHover.opens,
  }));
  HATCH && Object.assign(HATCH, { photoList, photoAt, photoOpen, photoStep, photoState, photoClaudePreview, photoHover });

