  // ---- 12 · Номера скриншотов в поле (#7532, WF120) -----------------------
  // Штампуем только PNG/JPEG/WebP из доверенного paste/drop без текста.
  // Черновик хранится рядом с полкой File: переживает reinject/возврат в чат.
  // Pending принадлежит экземпляру, редактору и поколению; его отмена запрещает
  // позднюю вставку. Отправка разрешается только новым действием после вставки.
  const SHOT_TYPES = { "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp" };
  const SHOT_NAME = "Скриншот";
  // Значок — обе стороны короче SHOT_SIDE_MIN: кладём как есть. Узкая полоса (снимок строки меню 1052×61, #10288 —
  // у второй картинки Элвиса не было «2») номер получает, пока плашка влезает по высоте: кегль 16 → плашка 24 и поля 8.
  const SHOT_SIDE_MIN = 64;
  const SHOT_SHORT_MIN = 40;
  // Больше — холст не потянет: как есть, с плашкой.
  const SHOT_SIDE_MAX = 16384;
  const SHOT_PIXELS_MAX = 50e6;
  // Кегль номера — доля короткой стороны в пределах 16…96 px: Claude ужимает
  // картинку до ~1568 px по длинной стороне, и номер ретина-скриншота остаётся
  // около 50 px — модель его читает.
  const SHOT_FONT_SHARE = 0.05;
  const SHOT_FONT_MIN = 16;
  const SHOT_FONT_MAX = 96;
  // Разбор и сборка большого PNG — до секунды; дольше — кладём как есть.
  const SHOT_WAIT_MS = 5000;
  // Дольше этого — плашка ожидания: без неё ⌘V жмут второй раз.
  const SHOT_BUSY_MS = 300;
  const SHOT_NOTE_BUSY = "Ставлю номер на скриншот…";
  const SHOT_NOTE_PLAIN = "Номер не поставлен — картинка вставлена как есть";
  const SHOT_NOTE_LOST = "Скриншот не вставлен: поле ввода пропало или чат сменился — вставь ещё раз";
  const shotHome = cashoutHome();
  shotHome.shots ??= new Map();
  const shotState = { chain: Promise.resolve(), revision: 0, pending: 0, jobs: new Set(), busyTimer: 0, busyShown: false };
  const shotRoute = () => myChatId() ?? location.href;
  const shotDraft = () => {
    const route = shotRoute();
    if (!shotHome.shots.has(route)) {
      shotHome.shots.set(route, { last: 0, generation: 0, issued: new Map(), hashes: new Map(), attempt: null });
      // Только метаданные черновиков; байты не удерживаются этим реестром.
    }
    const draft = shotHome.shots.get(route);
    draft.hashes ??= new Map(); // черновик прежнего экземпляра (реестр переживает reinject)
    return draft;
  };
  // Коробки поля нет (React пересобрал композер на первом вложении, раскладка ещё
  // не нашла новый) — плитки поля ищем по штатной разметке вложений композера во
  // всём документе: иначе первая плитка «не доезжала» и оставалась без номера (#9184).
  const shotTiles = () => {
    const box = cashoutBox();
    if (box) return [...box.querySelectorAll(PROGRESS_TILES_SELECTOR)];
    try { return [...document.querySelectorAll("[data-cds-composer-attachments] [data-cds-attachment]")]; } catch { return []; }
  };
  const shotTileName = tile => {
    for (const button of tile.querySelectorAll("button[aria-label]")) {
      const label = String(button.getAttribute("aria-label") ?? "");
      if (attachRemoveLabel(label)) return attachRemoveName(label);
    }
    return "";
  };
  // #11245 (слово Элвиса 30.10 ~20:15: «А зачем ты вот ещё раз добавил картинки? Они же уже здесь добавлены»):
  // что уже лежит в поле, второй раз туда не кладём — ни вставкой с номером, ни переносом, ни ⌘Z, ни «Обкэшить».
  // Плитка поля узнаётся по имени («Remove <имя>»); оригинал, уже вставленный «Скриншотом N», — по ключу
  // источника (имя, вес, тип), который выдача номера запоминает рядом с номером.
  const ATTACH_DUP_NOTE = "Эти файлы уже в поле — второй раз не кладу";
  const attachDup = { skipped: 0, last: null };
  const attachInField = () => new Set(shotTiles().map(shotTileName).filter(Boolean));
  const shotSourceKey = file => `${Number(file?.size) || 0}:${String(file?.type ?? "")}:${String(file?.name ?? "")}`;
  const attachSkip = (where, files) => {
    if (!files.length) return;
    attachDup.skipped += files.length;
    attachDup.last = { at: Date.now(), where, names: files.map(file => String(file?.name ?? "")).slice(0, 10) };
  };
  // Файлы, которых в поле ещё нет; лишние — в счёт status().attachDup.
  const attachFresh = (files, where) => {
    const have = attachInField();
    const fresh = [];
    const dup = [];
    for (const file of files ?? []) (have.has(String(file?.name ?? "")) ? dup : fresh).push(file);
    attachSkip(where, dup);
    return fresh;
  };
  // Связь с обработанным File запоминается только после вставки. Слабая ссылка
  // не удерживает байты после уборки полки; новый чужой File с тем же именем
  // отзывает связь (в том числе «+»). Одного похожего имени недостаточно.
  const shotIncoming = files => {
    const draft = shotDraft();
    for (const file of files ?? []) {
      const issued = draft.issued.get(file.name);
      if (issued && issued.file.deref() !== file) draft.issued.delete(file.name);
    }
  };
  const shotTileNumber = tile => {
    const name = shotTileName(tile);
    const issued = shotDraft().issued.get(name);
    return issued?.delivered ? issued.number : 0;
  };
  const shotMessageKeys = () => new Set([...document.querySelectorAll(
    '[data-testid="transcript-row"][data-perf-row="human"],[data-testid="user-message"],.epitaxy-user-turn')].map(node =>
      node.getAttribute("data-message-id") ?? node.getAttribute("data-epitaxy-entry") ??
      node.querySelector('[data-epitaxy-entry]')?.getAttribute("data-epitaxy-entry") ?? node.getAttribute("data-rs-index") ?? node.getAttribute("data-index")
    ).filter(Boolean));
  const shotAttempt = () => {
    const draft = shotDraft();
    if (!draft.last || shotState.pending || draft.attempt) return;
    draft.attempt = { before: shotMessageKeys(), at: Date.now() };
  };
  const shotSync = () => {
    for (const job of shotState.jobs) if (!(job.dispatched ? shotSent(job) : shotLive(job))) shotCancel(job);
    shotAdopt();
    for (const [route, draft] of shotHome.shots) if (route !== shotRoute()) draft.attempt = null;
    const draft = shotHome.shots.get(shotRoute());
    const attempt = draft?.attempt;
    if (!attempt) return;
    if (Date.now() - attempt.at > 30000) {
      draft.attempt = null; return;
    }
    const editor = findEditor();
    // Пустое поле само по себе ничего не доказывает: нужен новый постоянный id
    // реплики человека после пропущенной отправки в том же чате. React может
    // заменить редактор при успешной отправке; сам по себе remount не сбрасывает счёт.
    if (editor?.isConnected && !rawText(editor).trim() && !shotTiles().length &&
        [...shotMessageKeys()].some(key => !attempt.before.has(key))) {
      draft.last = 0;
      draft.generation += 1;
      draft.issued.clear();
      draft.hashes?.clear();
      draft.attempt = null;
    }
  };
  // Новый чат: до первой отправки у черновика нет id чата, и счёт живёт под
  // адресом страницы. Claude дал чату id, а плитки с нашими номерами уже в поле —
  // черновик переезжает вместе с ними, иначе номера на плитках пропадали (#9184).
  const shotAdopt = () => {
    const route = shotRoute();
    if (shotHome.shots.get(route)?.last) return;
    let names = null;
    for (const [key, draft] of shotHome.shots) {
      if (key === route || !/^[a-z]+:/i.test(key) || !draft.last) continue;
      names ??= new Set(shotTiles().map(shotTileName));
      if (![...draft.issued].some(([name, issued]) => issued.delivered && names.has(name))) continue;
      shotHome.shots.delete(key);
      shotHome.shots.set(route, draft);
      return;
    }
  };
  const markShotTiles = () => {
    shotSync();
    for (const tile of shotTiles()) {
      const number = shotTileNumber(tile);
      if (!number) { if (tile.hasAttribute(SHOT_ATTR)) tile.removeAttribute(SHOT_ATTR); }
      else if (tile.getAttribute(SHOT_ATTR) !== String(number)) tile.setAttribute(SHOT_ATTR, String(number));
    }
  };
  const shotNext = draft => {
    let number = ++draft.last;
    const names = new Set(shotTiles().map(shotTileName));
    while (Object.values(SHOT_TYPES).some(ext => names.has(`${SHOT_NAME} ${number}.${ext}`))) number = ++draft.last;
    return number;
  };
  const shotLive = job => state.alive && !job.cancelled && job.route === shotRoute() && job.where === location.href &&
    job.editor.isConnected && findEditor() === job.editor && job.draft.generation === job.generation;
  // После вставки картинка уже у Claude, и с номером в пикселях. Первое вложение
  // пересобирает композер (редактор, адрес нового чата), и прежняя проверка
  // «тот же редактор» роняла ожидание плитки: номер на плитке не вставал (#9184).
  // Дальше ждём только плитку: живой экземпляр и не отменено.
  const shotSent = job => state.alive && !job.cancelled;
  const shotCancel = job => {
    job.cancelled = true;
    for (const cancel of job.cancels) cancel();
  };
  // Не теряем поздний ImageBitmap при timeout/dispose и снимаем свои таймеры.
  const shotWait = (promise, job, late = () => {}, live = shotLive) => new Promise((resolve, reject) => {
    let finished = false;
    let timer = null;
    const done = (value, error) => {
      if (finished) { if (!error) late(value); return; }
      finished = true;
      clearTimeout(timer);
      job.cancels.delete(cancel);
      if (error) reject(error); else resolve(value);
    };
    const cancel = () => done(null, new Error("cancelled"));
    job.cancels.add(cancel);
    timer = setTimeout(() => done(null, new Error("timeout")), SHOT_WAIT_MS);
    Promise.resolve(promise).then(value => done(value), error => done(null, error));
    if (!live(job)) cancel();
  });
  // Белая цифра на тёмной плашке с белой каймой — читается на любом снимке.
  const shotBadge = (context, width, height, number) => {
    const text = String(number);
    const size = Math.round(Math.min(SHOT_FONT_MAX, Math.max(SHOT_FONT_MIN, Math.min(width, height) * SHOT_FONT_SHARE)));
    context.font = `700 ${size}px -apple-system, "Helvetica Neue", Arial, sans-serif`;
    const boxHeight = Math.round(size * 1.5);
    const boxWidth = Math.max(boxHeight, Math.round(context.measureText(text).width + size));
    // #11217 (слово Элвиса 30.10 17:20: «цифры… сильно прижаты… к низу… чтоб они чуть-чуть дышали»): от края — кегль,
    // а не полкегля; узкая полоса (#10288) — сколько влезает, плашка целиком внутри.
    const margin = Math.max(0, Math.min(size, Math.floor((height - boxHeight) / 2), Math.floor((width - boxWidth) / 2)));
    const top = height - margin - boxHeight;
    context.beginPath();
    context.roundRect(margin, top, boxWidth, boxHeight, boxHeight / 2);
    context.fillStyle = "rgba(0, 0, 0, 0.8)";
    context.fill();
    context.lineWidth = Math.max(1, Math.round(size / 12));
    context.strokeStyle = "#ffffff";
    context.stroke();
    context.fillStyle = "#ffffff";
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.fillText(text, margin + boxWidth / 2, top + boxHeight / 2);
  };
  // Одна картинка → { file, failed }. Не наш тип или значок — как есть и молча;
  // не разобралась, велика, холст отказал — как есть, с плашкой.
  const shotDraw = async (file, job) => {
    if (!SHOT_TYPES[file?.type] || !(file.size > 0)) return { file, failed: false };
    let bitmap = null;
    let number = 0;
    try {
      bitmap = await shotWait(createImageBitmap(file), job, value => { try { value?.close?.(); } catch {} });
      if (!shotLive(job)) return { file, failed: true };
      const width = Number(bitmap?.width) || 0;
      const height = Number(bitmap?.height) || 0;
      if (width > 0 && height > 0 && (Math.max(width, height) < SHOT_SIDE_MIN || Math.min(width, height) < SHOT_SHORT_MIN)) {
        return { file, failed: false };
      }
      if (!(width > 0 && height > 0) || Math.max(width, height) > SHOT_SIDE_MAX || width * height > SHOT_PIXELS_MAX) {
        return { file, failed: true };
      }
      const canvas = document.createElement("canvas");
      canvas.width = width;
      canvas.height = height;
      const context = canvas.getContext("2d");
      if (!context) return { file, failed: true };
      context.drawImage(bitmap, 0, 0);
      number = shotNext(job.draft);
      shotBadge(context, width, height, number);
      const blob = await shotWait(new Promise(resolve => canvas.toBlob(resolve, file.type, 0.92)), job);
      if (!shotLive(job) || !(blob?.size > 0)) throw new Error("toBlob");
      const type = blob.type;
      if (!SHOT_TYPES[type]) throw new Error("blob type");
      return { file: new File([blob], `${SHOT_NAME} ${number}.${SHOT_TYPES[type]}`, { type }), number, failed: false };
    } catch {
      // Номер выдан, а картинка не собралась — возвращаем его: дыры в счёте нет.
      if (number && job.draft.last === number) job.draft.last -= 1;
      return { file, failed: true };
    } finally {
      try { bitmap?.close?.(); } catch {}
    }
  };
  const shotBusyEnd = () => {
    if (shotState.busyTimer) { clearTimeout(shotState.busyTimer); shotState.busyTimer = 0; }
    if (shotState.busyShown) { shotState.busyShown = false; newWindowNoteHide(false); }
  };
  track(() => {
    for (const job of shotState.jobs) shotCancel(job);
    shotBusyEnd();
    for (const tile of document.querySelectorAll(`[${SHOT_ATTR}]`)) tile.removeAttribute(SHOT_ATTR);
  });
  // Оригинал уже в поле: его номерованная копия («Скриншот N») — плиткой этого черновика (#11245). Тот же
  // буфер вставили второй раз (Диктатор на «Стоп» оставил в буфере снимки вместо текста, и ⌘V по плашке
  // «Текст не вставлен · ⌘V» клал их снова — 1 = 3, 2 = 4).
  // Плитка с отпечатком содержимого (#11689, ниже) сверяется им: два разных снимка одного веса — оба «image.png».
  const shotAlready = (draft, file, have) => {
    const key = shotSourceKey(file);
    for (const [name, issued] of draft.issued) if (issued.source === key && have.has(name) && !draft.hashes.has(name)) return true;
    return false;
  };
  // #11689 (слово Элвиса 05.11 ~18:13: «Картинка была вставлена, я диктовку начал, она опять вставляется… Ты каждый
  // раз перед вставкой проверяй, картинка вставлена ли уже или нет»): Диктатор вставил снимок файлом из папки снимков
  // («Снимок … 18.13.08-762774.png»), а на старте записи понёс его же копией из стопки («shot-…png») — байты те же,
  // имя другое, и ключ источника его не узнал. Поэтому сверяем ещё содержимое (ключ полки «Обкэшить»: вес, тип и
  // djb2 первых 8 КБ) со всем, что этот черновик уже положил в поле: плитка → ключ её исходника, в draft.hashes.
  const shotHash = async file => { try { return await cashoutFileHash(file); } catch { return ""; } };
  const shotDeliver = async job => {
    const ready = [];
    let failed = false;
    try {
      // Сверка — здесь, а не в shotTake: очередь вставок к этому мгновению доставила все прежние.
      const hashes = new Map();
      for (const file of job.files) hashes.set(file, await shotHash(file));
      const have = attachInField();
      const known = new Set([...job.draft.hashes].filter(([name]) => have.has(name)).map(([, hash]) => hash));
      const dup = job.files.filter(file => {
        if (shotAlready(job.draft, file, have)) return true;
        const hash = hashes.get(file);
        if (!hash) return false;
        if (known.has(hash)) return true;
        known.add(hash); // один снимок дважды в одной вставке — тоже дубль
        return false;
      });
      if (dup.length) {
        attachSkip("shot", dup);
        job.files = job.files.filter(file => !dup.includes(file));
        if (!job.files.length) { if (state.alive) { shotBusyEnd(); newWindowNote(ATTACH_DUP_NOTE); } return; }
      }
      for (const file of job.files) {
        if (!shotLive(job)) break;
        const done = await shotDraw(file, job);
        ready.push(done);
        failed ||= done.failed;
      }
      if (!shotLive(job) || ready.length !== job.files.length) {
        if (state.alive) newWindowNote(SHOT_NOTE_LOST);
        return;
      }
      const data = new DataTransfer();
      for (const item of ready) data.items.add(item.file);
      cashoutRemember(ready.map(item => item.file));
      // Связь имя → номер — сразу доставленная: плитка с этим именем появится
      // только от этой вставки, а ждать её «тем же редактором» нельзя (#9184).
      ready.forEach(({ file, number }, at) => {
        const hash = hashes.get(job.files[at]);
        if (hash) job.draft.hashes.set(file.name, hash);
        if (number) job.draft.issued.set(file.name, { number, file: new WeakRef(file), delivered: true, source: shotSourceKey(job.files[at]) });
      });
      pasteRelaying = true;
      job.dispatched = true;
      try {
        job.editor.focus();
        job.editor.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
      } finally { pasteRelaying = false; }
      // React может дорисовать плитки позже события paste. До них барьер остаётся.
      const arrived = () => {
        const names = shotTiles().map(shotTileName);
        return ready.every(item => names.includes(item.file.name));
      };
      if (!arrived()) await shotWait(new Promise((resolve, reject) => {
        let timer;
        const stop = () => { clearTimeout(timer); job.cancels.delete(stop); reject(new Error("cancelled")); };
        job.cancels.add(stop);
        const check = () => {
          if (!shotSent(job)) { stop(); return; }
          if (arrived()) { job.cancels.delete(stop); resolve(); return; }
          timer = setTimeout(check, 50);
        };
        check();
      }), job, () => {}, shotSent);
      if (shotSent(job)) markShotTiles();
      if (failed && state.alive) { shotBusyEnd(); newWindowNote(SHOT_NOTE_PLAIN); }
    } catch {
      if (state.alive) { shotBusyEnd(); newWindowNote(SHOT_NOTE_LOST); }
    } finally {
      shotCancel(job);
      shotState.jobs.delete(job);
      shotState.pending -= 1;
      if (!shotState.pending) shotBusyEnd();
    }
  };
  const shotBlocked = () => {
    if (!shotState.pending) return false;
    newWindowNote(SHOT_NOTE_BUSY, true, SHOT_WAIT_MS * 2);
    shotState.busyShown = true;
    return true;
  };
  // Текст рядом с картинкой — обычно чужая разметка (Excel, страница): её не
  // трогаем. Но Диктатор, Finder и съёмщики кладут рядом со снимком его путь или
  // имя (`/…/Снимок 01.png`, `file:///…`, с `\ ` перед пробелами) — это тот же
  // снимок, а не текст, и он обязан получить номер (WF173: снимок остался без №).
  const SHOT_PATH_EXT = /\.(png|jpe?g|webp|gif|tiff?|heic|bmp)$/i;
  const shotTextIsPaths = (text, files) => {
    const names = new Set(files.map(file => String(file?.name ?? "")));
    const isPath = raw => {
      let token = raw.replace(/\\(.)/g, "$1");
      if (/^file:\/\//i.test(token)) {
        try { token = decodeURIComponent(token.slice(7)); } catch { return false; }
      }
      const base = token.slice(token.lastIndexOf("/") + 1);
      if (names.has(base) || names.has(token)) return true;
      // Фраза «смотри shot.png» — текст, не путь: голое имя только без пробелов.
      return SHOT_PATH_EXT.test(base) && (/^[/~]/.test(token) || !/\s/.test(token));
    };
    const lines = String(text).split(/[\r\n]+/).map(line => line.trim()).filter(Boolean);
    // Строка целиком — имя с пробелами (Finder); иначе пути через пробел, где
    // пробел с обратной косой — часть имени (Диктатор, Терминал).
    return lines.length > 0 && lines.every(line => isPath(line) ||
      line.split(/(?<!\\) +/).filter(Boolean).every(isPath));
  };
  const shotTake = (event, transfer, inField) => {
    if (event?.isTrusted !== true) return false;
    const files = Array.from(transfer?.files ?? []);
    if (!files.some(file => SHOT_TYPES[file?.type])) return false;
    const text = String(transfer.getData?.("text/plain") ?? "").trim();
    if (text && !shotTextIsPaths(text, files)) return false;
    const editor = pasteEditor();
    if (!editor || !inField(editor)) return false;
    shotSync();
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    // Исходники этой вставки полка «Обкэшить» запомнила раньше нас (её слушатель на захвате первый), а в
    // поле поедут номерованные копии — их на полку кладёт shotDeliver. Без этого ⇧⌘N в первые 10 с увозил
    // оригинал последнего снимка вместо «Скриншот 1» (ревизия WF247).
    const home = cashoutHome();
    home.shelf = home.shelf.filter(item => !files.includes(item.file));
    const draft = shotDraft();
    draft.attempt = null;
    const job = { files, editor, nodes: [...editor.childNodes], dispatched: false, where: location.href, route: shotRoute(), draft, generation: draft.generation, cancels: new Set(), cancelled: false };
    shotState.jobs.add(job);
    shotState.pending += 1;
    shotState.revision += 1;
    // Ожидавшее автоматическое сообщение не отправляется после обработки само.
    for (const queued of sendTextQueue.splice(0)) sendTextDone(queued.id, "field-busy");
    sendDelayStop("cancelled", "screenshot");
    sendDelayState.token += 1; // отменяет и запасной click уже отпущенного Enter
    sayDisarm("Ставлю номер…");
    nazhDisarm("Ставлю номер…");
    if (!shotState.busyTimer && !shotState.busyShown) {
      shotState.busyTimer = setTimeout(() => {
        shotState.busyTimer = 0;
        if (state.alive) shotBlocked();
      }, SHOT_BUSY_MS);
    }
    shotState.chain = shotState.chain.then(() => shotDeliver(job));
    return true;
  };
  // ⌘V — в само поле или мимо любого поля (дорога 2); поиск чатов и чужие поля — нет.
  const shotPaste = event => shotTake(event, event?.clipboardData,
    editor => editor.contains(event.target) || pasteOutside(event.target));
  // Бросок картинки — в любое место окна, кроме чужих полей и терминала: Claude
  // кладёт брошенное в поле и мимо блока ввода (лента, его подложка «брось сюда»),
  // и без номера (#11310, слово Элвиса 31.10 ~02:58: «я его драгдропом перенёс…
  // номера же у скриншотов есть, а здесь номера не стоят»). Номер — общий ряд со
  // вставками, дубль — К-ATTACH-DUP. Терминал и поиск получают бросок как раньше.
  const SHOT_DROP_SKIP = ".xterm";
  // Свой бросок Claude не увидел: пустой бросок той же цели гасит его подложку
  // «брось сюда», файлов в нём нет — вложить нечего.
  const shotDropRelease = target => {
    try { target?.dispatchEvent?.(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: new DataTransfer() })); } catch {}
  };
  const onShotDrop = event => {
    try {
      const target = event?.target;
      const taken = shotTake(event, event?.dataTransfer, editor => Boolean(cashoutBox()?.contains(target) ||
        sideDock(layoutPanel(editor))?.contains(target) || editor.contains(target) ||
        (pasteOutside(target) && !target?.closest?.(SHOT_DROP_SKIP))));
      if (taken) shotDropRelease(target);
    } catch {}
  };
  // «+» Claude → файл (#9184: «все скриншоты должны нумероваться, когда я их
  // добавляю»). Выбор файла приходит доверенным change поля <input type=file>
  // блока ввода: картинки забираем до Claude и везём в поле той же вставкой, что
  // ⌘V, — с номером. Поле выбора очищаем: тот же файл выбирается снова.
  const onShotPick = event => {
    try {
      const input = event?.target;
      if (input?.tagName !== "INPUT" || input.type !== "file") return;
      const editor = pasteEditor();
      const panel = layoutPanel(editor);
      const near = node => Boolean(node && (cashoutBox()?.contains(node) || sideDock(panel)?.contains(node) ||
        node.closest?.('[data-cds="ChatComposer"],.epitaxy-prompt')));
      if (!shotTake(event, { files: input.files, getData: () => "" }, () => near(input))) return;
      try { input.value = ""; } catch {}
    } catch {}
  };
  statusPart("attachDup", () => ({ skipped: attachDup.skipped, last: attachDup.last }));
  HATCH && Object.assign(HATCH, { shotState, shotPaste, attachDup });

