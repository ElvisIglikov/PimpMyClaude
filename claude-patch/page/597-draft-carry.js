  // ---- 12ч · Черновик переезжает при смене чата (#11201, WF302) ------------
  // Слово Элвиса 30.10 ~17:45 (смена чата Рика): «Я там скриншоты ещё закреплял,
  // скриншоты не закрепились… И где мне скриншоты искать?… диктовки ещё куски
  // большие не вставились». renew главного окна (цепочка new-window со stay и без
  // sendTransfer, WF181) открывает новый чат в ТОМ ЖЕ окне: набранное в поле и
  // вложения оставались в поле прежнего чата, а Элвис видел пустое поле нового.
  // Теперь цепочка снимает черновик до ⌘N (и досматривает, пока окно ещё на
  // прежнем чате), а когда первое сообщение нового чата ушло — кладёт тот же
  // текст в поле (без отправки) и те же файлы вложениями. Файлы — те же File с
  // полки «Обкэшить» (раздел 12): окно одно, память одна, на диск ничего не едет.
  // Черновик прежнего чата не трогаем — он остаётся запасом там, где был; цепочка
  // сорвалась и прежний чат вернулся с пустым полем — кладём черновик обратно туда.
  // Пустой черновик — ни одного лишнего шага, поля carry у цепочки нет.
  // Строки-вставки голоса «Голос Элвиса: … #v<id> · …» не едут (#11571): их письмо и так в почте Рика.
  // Исход — newWindow.carry (его ждёт приложение и называет `pimp.py renew`):
  //   {state:"wait"|"ok"|"part"|"fail"|"kept"|"back", chars, files, landed, why?}.
  const DRAFT_CARRY_FIELD_MS = 6000;
  const DRAFT_CARRY_FILES_MS = 4000;
  const DRAFT_CARRY_BACK_MS = 1500;
  const draftCarryLast = { state: null, runs: 0 };
  const draftCarryEditor = () => {
    const box = document.querySelector(NEW_WINDOW_INPUT_SELECTOR);
    return box?.isConnected ? box : pasteEditor();
  };
  const draftCarryHas = carry => Boolean(carry && (carry.text || carry.files.length || carry.want));
  // Снимок поля прежнего чата: текст и вложения, чьи File знает полка. Плиток
  // больше, чем известных файлов (вложение пришло мимо наших слушателей), —
  // `want` больше `files`, и исход честно скажет «не всё».
  const draftCarrySnap = carry => {
    const editor = draftCarryEditor();
    if (!editor) return;
    const text = editorText(editor) ? sendTextNoVoice(rawText(editor).replace(/[​﻿]/g, "")) : "";
    const haul = cashoutHaul();
    if (!text && !haul.want) return;
    carry.text = text;
    carry.want = haul.want;
    carry.files = haul.files.filter(item => item?.file).map(item => ({ name: item.name, file: item.file }));
    carry.shots = shotHome.shots.get(shotRoute()) ?? null;
    if (carry.state !== "wait") draftCarryMark(carry, "wait");
  };
  const draftCarryMark = (carry, next, extra = {}) => {
    carry.state = next;
    const view = { state: next, chars: carry.text.length, files: carry.files.length, want: carry.want, landed: carry.landed, ...extra };
    draftCarryLast.state = view;
    newWindowMark({ carry: view });
  };
  // Старт: только renew главного окна. Холдер есть всегда — черновик мог
  // появиться в те 0,9 с, что Swift ждёт перед ⌘N.
  const draftCarryStart = prev => {
    draftCarryLast.runs += 1;
    const carry = { prev, text: "", files: [], want: 0, landed: 0, shots: null, state: null };
    draftCarrySnap(carry);
    return carry;
  };
  // Досмотр, пока окно ещё на прежнем чате: дописанное за последние мгновения
  // тоже едет. Пустой снимок прежний не затирает — поле пустеет и на уходе.
  const draftCarryRefresh = carry => {
    if (carry && carry.state !== "ok" && location.pathname === carry.prev) draftCarrySnap(carry);
  };
  // Нумерация скриншотов едет с ними: «Скриншот 3» в новом чате остаётся тройкой,
  // следующий снимок — четвёртым (у нового чата своего счёта ещё нет).
  const draftCarryShots = carry => {
    const old = carry.shots;
    const route = shotRoute();
    if (!old?.last || shotHome.shots.get(route)?.last) return;
    shotHome.shots.set(route, { last: old.last, generation: 0, issued: new Map(old.issued), attempt: null });
  };
  // Вложение, которое уже в поле нового чата (Claude сам оставил поле или перенос повторили), второй раз
  // не кладётся и считается доехавшим (#11245).
  const draftCarryFiles = async (carry, editor, token) => {
    if (!carry.files.length) return 0;
    const fresh = attachFresh(carry.files.map(item => item.file), "carry");
    const already = carry.files.length - fresh.length;
    if (!fresh.length) return already;
    const before = cashoutPills();
    try {
      const data = new DataTransfer();
      for (const file of fresh) data.items.add(file);
      try { editor.focus(); } catch {}
      editor.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
    } catch {}
    await newWindowWait(() => (cashoutPills() - before >= fresh.length ? true : null), DRAFT_CARRY_FILES_MS, token);
    return already + Math.max(0, Math.min(fresh.length, cashoutPills() - before));
  };
  // Новый чат родился, первое сообщение ушло: ждём, пока поле от него очистится,
  // кладём текст в начало (надиктованное за эти секунды остаётся после него) и
  // прикладываем файлы. Отправки нет.
  const draftCarryPut = async (carry, first, token) => {
    if (!draftCarryHas(carry)) return;
    const head = cashoutNorm(first).slice(0, CASHOUT_HEAD);
    const editor = await newWindowWait(() => {
      const box = draftCarryEditor();
      if (!box || location.pathname === carry.prev) return null;
      return head && cashoutNorm(rawText(box)).includes(head) ? null : box;
    }, DRAFT_CARRY_FIELD_MS, token);
    if (!newWindowLive(token)) return;
    if (!editor) { draftCarryMark(carry, "fail", { why: "поле нового чата не освободилось" }); return; }
    let textOk = true;
    if (carry.text) {
      if (!cashoutHeadHit(editor, carry.text)) insertIntoEditor(editor, carry.text, true);
      textOk = cashoutArrived(editor, carry.text);
    }
    draftCarryShots(carry);
    carry.landed = await draftCarryFiles(carry, editor, token);
    if (!newWindowLive(token)) return;
    if (!textOk) draftCarryMark(carry, "fail", { why: "текст не лёг в поле" });
    else draftCarryMark(carry, carry.landed < carry.want ? "part" : "ok");
  };
  // Цепочка не дошла до нового чата: черновик остаётся в прежнем. Вернулись на
  // прежний чат, а поле там пустое и без вложений — кладём снятое обратно.
  const draftCarryKeep = carry => {
    if (!draftCarryHas(carry) || carry.state !== "wait") return;
    draftCarryMark(carry, "kept");
    newWindowLater(() => {
      try {
        if (!state.alive || location.pathname !== carry.prev) return;
        const editor = draftCarryEditor();
        if (!editor || editorText(editor) || cashoutPills()) return;
        if (carry.text) insertIntoEditor(editor, carry.text, true);
        if (carry.files.length) {
          const data = new DataTransfer();
          for (const item of carry.files) data.items.add(item.file);
          editor.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
        }
        draftCarryMark(carry, "back");
      } catch {}
    }, DRAFT_CARRY_BACK_MS);
  };
  statusPart("draftCarry", () => (draftCarryLast.state ? { ...draftCarryLast.state, runs: draftCarryLast.runs } : null));
