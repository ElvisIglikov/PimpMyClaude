  // ---- 1а. Общие помощники разделов (WF248 П4) ----------------------------
  // Их зовут несколько разделов; тела те же, что стояли в разделах-хозяевах (2б, 12ж, 12ж¹, 12з, 12р, 12ф,
  // 12х). Константы своих разделов они читают при вызове, а не при установке, — поэтому могут стоять здесь
  // (TDZ). WORKING_SELECTOR остался в 12ж¹: он строится из AUTO_STOP_SELECTOR раздела 12к при установке.
  // Тёмное окно или светлое: наши темы пишут color-scheme прямо на :root, а без
  // темы решает системная настройка.
  const progressDark = () => {
    try {
      const scheme = String(getComputedStyle(document.documentElement).colorScheme ?? "");
      if (/dark/.test(scheme) && !/light/.test(scheme)) return true;
      if (/light/.test(scheme) && !/dark/.test(scheme)) return false;
    } catch {}
    try { return matchMedia("(prefers-color-scheme: dark)").matches; } catch { return true; }
  };
  // Доля цвета поверх фона рамки: фон ждущей капсулы — 22 % акцента, заливка
  // идущей — 70 %, номер ждущей — 90 % (макет, вариант 4.5).
  const progressTint = (color, share) => `color-mix(in srgb, ${color} ${share}%, transparent)`;
  // Цвета от темы окна (WF84): T — цвет текста поля, F — его фон. Читаются на
  // каждом показе: тема меняется командой в любой момент. Прозрачный фон рамки
  // — берём `--bg-000` палитры Claude (тройка HSL, как у акцента), нет и его —
  // кожа карточки.
  const PROGRESS_CLEAR_RE = /^(?:transparent|rgba\(\s*0,\s*0,\s*0,\s*0\s*\))$/i;
  const progressTextColor = (frame) => {
    let color = "";
    try { color = String(frame?.isConnected ? getComputedStyle(frame).color ?? "" : "").trim(); } catch {}
    return color || PROGRESS_CARD_SKIN[progressDark() ? "dark" : "light"].text;
  };
  const progressFieldColor = (frame) => {
    let color = "";
    try { color = String(frame?.isConnected ? getComputedStyle(frame).backgroundColor ?? "" : "").trim(); } catch {}
    if (color && !PROGRESS_CLEAR_RE.test(color)) return color;
    let raw = "";
    try {
      const host = document.querySelector(".epitaxy-root") ?? document.documentElement;
      raw = String(getComputedStyle(host).getPropertyValue("--bg-000") ?? "").trim();
    } catch {}
    if (/^[\d.]+(?:deg)?\s+[\d.]+%\s+[\d.]+%$/.test(raw)) return `hsl(${raw})`;
    if (/^(?:#|rgba?\(|hsla?\()/i.test(raw)) return raw;
    return PROGRESS_CARD_SKIN[progressDark() ? "dark" : "light"].back;
  };
  const usagePlural = (value, one, few, many) => {
    const hundred = Math.abs(Math.round(value)) % 100;
    const ten = hundred % 10;
    if (hundred >= 11 && hundred <= 14) return many;
    if (ten === 1) return one;
    if (ten >= 2 && ten <= 4) return few;
    return many;
  };
  // Чат работает, пока видна кнопка стопа.
  const pageWorking = () => {
    try { return Boolean(document.querySelector(WORKING_SELECTOR)); } catch { return false; }
  };
  // Слово Элвиса 21.09: «у меня просто в углу будет кнопка диктовки, я на неё
  // буду нажимать и буду доволен» — в режиме чтения строки поля ввода не видно
  // вовсе, и до родного микрофона Claude не дотянуться. Свой значок встаёт
  // ЛЕВЕЕ кружка контекста и в одну линию с ним, а жмёт за Элвиса родные
  // кнопки Claude: диктовку и отправку. Своей записи звука у нас нет и не будет.
  //
  // Нажатие «как мышью» (замер 21.09): Claude слушает не сам <button>, а то,
  // что лежит под точкой, — на кнопке кружка панель не открывалась ни кликом,
  // ни Enter, а на её <svg> открылась с первого раза. Поэтому бьём в
  // elementFromPoint, а если узел спрятан (свёрнутое поле) — прямо в него.
  const pressLikeMouse = node => {
    if (!node?.isConnected) return false;
    const rect = node.getBoundingClientRect();
    const x = Math.round(rect.left + rect.width / 2);
    const y = Math.round(rect.top + rect.height / 2);
    let target = node;
    if (rect.width > 0 && rect.height > 0) {
      let hit = null;
      try { hit = document.elementFromPoint(x, y); } catch {}
      if (hit && (hit === node || node.contains(hit))) target = hit;
    }
    const at = { clientX: x, clientY: y, screenX: x, screenY: y, bubbles: true, cancelable: true, composed: true, view: window };
    const pointer = (type, extra) => {
      try { target.dispatchEvent(new PointerEvent(type, { ...at, pointerId: 1, isPrimary: true, pointerType: "mouse", ...extra })); } catch {}
    };
    const mouse = (type, extra) => {
      try { target.dispatchEvent(new MouseEvent(type, { ...at, ...extra })); } catch {}
    };
    pointer("pointerover", { buttons: 0 }); mouse("mouseover", {});
    pointer("pointermove", { buttons: 0 }); mouse("mousemove", {});
    pointer("pointerdown", { button: 0, buttons: 1 }); mouse("mousedown", { button: 0, buttons: 1 });
    pointer("pointerup", { button: 0, buttons: 0 }); mouse("mouseup", { button: 0, buttons: 0 });
    mouse("click", { button: 0, detail: 1 });
    return true;
  };
  // Над значком и по его середине, в пределах окна; значка не видно — над низом
  // окна по центру.
  const micHint = (text, anchor = micNode, size = MIC_SIZE) => {
    micHintHide();
    if (!micHintNode.isConnected) (document.body ?? document.documentElement).appendChild(micHintNode);
    micHintNode.textContent = text;
    micHintNode.style.setProperty("display", "block");
    // Место значка — из его же стилей (их ставит micShow): рамку он может ещё
    // не получить, а число уже есть.
    const x = parseFloat(anchor.style.getPropertyValue("left"));
    const y = parseFloat(anchor.style.getPropertyValue("top"));
    const seen = anchor.style.getPropertyValue("display") !== "none" && Number.isFinite(x) && Number.isFinite(y);
    const width = micHintNode.getBoundingClientRect().width || 240;
    const middle = seen ? x + size / 2 : innerWidth / 2;
    const left = Math.max(8, Math.min(middle - width / 2, innerWidth - width - 8));
    micHintNode.style.setProperty("left", `${Math.round(left)}px`);
    micHintNode.style.setProperty("bottom", `${Math.round(seen ? innerHeight - y + 6 : 40)}px`);
    micState.hintTimer = setTimeout(() => {
      micState.hintTimer = 0;
      micHintNode.style.setProperty("display", "none");
    }, MIC_HINT_MS);
  };
  const sayNorm = value => String(value ?? "").replace(/[​﻿]/g, "").replace(/ /g, " ").replace(/\s+/g, " ").trim();
  const foldSet = (node, name, value) => {
    if (value == null) { if (node.hasAttribute(name)) node.removeAttribute(name); return; }
    if (node.getAttribute(name) !== value) node.setAttribute(name, value);
  };
  const readIdsOf = record => (Array.isArray(record?.ids) ? record.ids.filter(id => typeof id === "string" && id) : []);
  // Потолок хранилища (чистая функция): у чата — последние READ_IDS_MAX пометок; чатов не больше
  // READ_CHATS_MAX и пометок всего не больше READ_TOTAL_MAX — уходят чаты, которых дольше всех не
  // касались. Чат keep остаётся; чат без пометок не хранится.
  const readStoreTrim = (map, keep = null, idsMax = READ_IDS_MAX, chatsMax = READ_CHATS_MAX, totalMax = READ_TOTAL_MAX) => {
    const out = {};
    for (const [chat, record] of Object.entries(map ?? {})) {
      const ids = [...new Set(readIdsOf(record))].slice(-idsMax);
      if (ids.length) out[chat] = { at: Number(record?.at) || 0, ids };
    }
    const old = Object.keys(out).filter(chat => chat !== keep).sort((a, b) => out[a].at - out[b].at);
    let chats = Object.keys(out).length;
    let total = Object.values(out).reduce((sum, record) => sum + record.ids.length, 0);
    while (old.length && (chats > chatsMax || total > totalMax)) {
      const chat = old.shift();
      total -= out[chat].ids.length;
      chats -= 1;
      delete out[chat];
    }
    return out;
  };
  HATCH && Object.assign(HATCH, { usagePlural, pageWorking, readStoreTrim });

