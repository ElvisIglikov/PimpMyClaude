  // ---- 12т¹. Текст в чат командой send-text (#7953, #7927, WF103) ------------
  // Слово Элвиса 27.09 (через Рика): «отправь текст в чат» — вставить текст в
  // окно нужного чата и нажать отправку; правило «Enter Пимп не жмёт» для ЭТОЙ
  // команды снято его словом, но Enter не шлём и здесь — только кнопка «отправить».
  // Контракт — CONTRACTS WF103 «Команда send»: команда с чужим chat — мимо; тот
  // же id — ничего; поле пустое (пробелы — пусто) — вставка (selectAll +
  // insertText, как 12р), кнопка «отправить» (SEND_SELECTOR + pressLikeMouse),
  // поле опустело за SEND_TEXT_WAIT_MS — sent; свой текст в поле — ничего,
  // field-busy; поля нет — no-field; кнопки нет или поле не опустело — no-send
  // (текст остаётся в поле). Исход — status().send, его берёт приложение.
  // С WF111 (слово Элвиса через Рика 30.09 ~19:40: голос не должен отказывать, пока
  // Элвис пишет в том же поле) свой текст или вложения в поле — не отказ: фраза
  // встаёт в очередь окна (исход queued, без плашки — 01.10) и уходит, как только поле опустеет (Элвис отправил или стёр своё) и простоит
  // пустым SEND_TEXT_QUEUE_GRACE_MS, без идущего счёта отправки и в своём чате.
  // Очередь полна — прежний отказ field-busy.
  // #11571 (RickIOS 02.11 05:06: «вставка не отправилась и осталась в поле Claude, письмо почтой
  // дошло…, а черновик из поля переезжал с чатом при renew и ушёл отправкой»). Голос запасным путём
  // rick_bus — «Голос Элвиса: [🎙 Голосом[ с телефона]] #v<id> · фраза» — только короткий путь: письмо
  // <id> уже в почте Рика и дойдёт само. Поэтому такая вставка ждёт в очереди только свою же отправку и
  // не дольше SEND_TEXT_VOICE_WAIT_MS (чужое в поле — сразу field-busy); не ушла — стирается из поля,
  // если там ровно она; одна в поле без отправки (страница сменилась посреди неё, Claude вернул черновик
  // чата после перезапуска или обхода) — стирается обходом раз в SEND_TEXT_SWEEP_MS; при renew с
  // черновиком не едет (12ч). Счёт стёртого — status().send.cleared.
  const SEND_TEXT_VOICE_RE = /^\s*Голос Элвиса:\s*(?:🎙️?\s*Голосом(?:\s+с\s+телефона)?\s+)?#v[0-9a-f-]+\s*·/;
  const SEND_TEXT_VOICE_WAIT_MS = 10000;
  const SEND_TEXT_SWEEP_MS = 2000;
  const sendTextVoice = text => SEND_TEXT_VOICE_RE.test(String(text ?? ""));
  // Текст без строк-вставок голоса; "" — в нём были одни они.
  const sendTextNoVoice = text => String(text ?? "").split("\n").filter(line => !sendTextVoice(line)).join("\n").trim();
  const SEND_TEXT_QUEUE_GRACE_MS = 1500;
  const SEND_TEXT_QUEUE_MAX = 5;
  const SEND_TEXT_QUEUE_ID = "myclaude-send-queue";
  const SEND_TEXT_WAIT_MS = 3000;
  const SEND_TEXT_PRESS_MS = 300;
  const SEND_TEXT_ALIVE_MS = 2000;
  const SEND_TEXT_REPRESS_MS = 1500;
  const SEND_TEXT_POLL_MS = 100;
  const SEND_TEXT_IDS = 50;
  const sendTextState = { id: null, state: null, at: null, sends: 0, ids: [], queued: 0, busy: false, cleared: 0 };
  const sendTextTimers = new Set();
  const sendTextQueue = [];
  let sendTextQueueEmptySince = null;
  let sendTextQueueTimer = null;
  const sendTextDone = (id, result) => {
    Object.assign(sendTextState, { id, state: result, at: new Date().toISOString() });
    if (result === "sent") sendTextState.sends += 1;
  };
  const runSendText = detail => {
    const id = typeof detail?.id === "string" ? detail.id : "";
    const chat = typeof detail?.chat === "string" ? detail.chat : "";
    const text = typeof detail?.text === "string" ? detail.text : "";
    if (!id || !chat || !text) return;
    if (chat !== myChatId()) {
      // Обход чатов увёл главное окно из этого чата — сперва вернуться (как у 15).
      if (isMainWindow() && roamState.phase !== "idle" && roamState.fromId === chat) roamDefer(() => runSendText(detail));
      return;
    }
    if (sendTextState.ids.includes(id)) return;
    sendTextState.ids.push(id);
    if (sendTextState.ids.length > SEND_TEXT_IDS) sendTextState.ids.shift();
    const editor = sayEditor();
    if (shotBlocked()) { sendTextDone(id, "field-busy"); return; }
    if (!editor?.isConnected) { sendTextDone(id, "no-field"); return; }
    // Своё Элвиса в поле (текст или вложения — гейт 2) или очередь уже ждёт — в очередь.
    if (sendTextFieldBusy(editor) || sendTextQueue.length || sendTextState.busy) {
      const voice = sendTextVoice(text);
      // Голос за чужим в поле не ждёт: Элвис отправит своё — письмо придёт с ним же (#11571).
      if (sendTextQueue.length >= SEND_TEXT_QUEUE_MAX || (voice && !sendTextState.busy && sendTextFieldBusy(editor))) {
        sendTextDone(id, "field-busy");
        return;
      }
      sendTextQueue.push({ id, chat, text, until: voice ? now() + SEND_TEXT_VOICE_WAIT_MS : null });
      sendTextState.queued += 1;
      sendTextDone(id, "queued");
      sendTextQueueArm();
      return;
    }
    sendTextPut(id, chat, editor, text);
  };
  // Плитки вложений ЭТОГО поля (WF111, судья page): ищем только в блоке ввода
  // (cashoutBox — блок, пока его нет — оболочка поля), не по всему документу:
  // плитка в ленте или во втором композере поле занятым не делает. Имя плитки —
  // подпись её кнопки снятия («Remove <name>»): при загрузке React перерисовывает
  // плитку (узел, подпись прогресса, src превью), а имя остаётся. Нет кнопки — "".
  const composerTileNames = () => {
    const box = cashoutBox();
    if (!box) return [];
    try {
      return [...box.querySelectorAll(PROGRESS_TILES_SELECTOR)].map(tile => {
        for (const button of tile.querySelectorAll("button[aria-label]")) {
          const label = String(button.getAttribute("aria-label") ?? "").trim();
          if (attachRemoveLabel(label)) return label;
        }
        return "";
      });
    } catch { return []; }
  };
  const sendTextFieldBusy = editor => shotState.pending > 0 || Boolean(sayNorm(rawText(editor))) || composerTileNames().length > 0;
  // Плашки над полем нет (слово Элвиса 01.10 через Рика: «сбивает, зачем»): очередь
  // работает молча, сироту прошлой версии (SEND_TEXT_QUEUE_ID) убирают строки ниже.
  // Опрос очереди: 4 раза в секунду, пока в ней что-то есть.
  const sendTextQueueArm = () => {
    if (sendTextQueueTimer != null || !sendTextQueue.length) return;
    sendTextQueueTimer = setInterval(sendTextQueueTick, 250);
  };
  const sendTextQueueTick = (t = now()) => {
    // Голос дольше SEND_TEXT_VOICE_WAIT_MS не ждёт — дальше его несёт почта (#11571).
    for (let i = sendTextQueue.length - 1; i >= 0; i -= 1) {
      if (sendTextQueue[i].until != null && t > sendTextQueue[i].until) sendTextQueue.splice(i, 1);
    }
    if (!state.alive || !sendTextQueue.length) {
      if (sendTextQueueTimer != null) { clearInterval(sendTextQueueTimer); sendTextQueueTimer = null; }
      sendTextQueueEmptySince = null;
      return;
    }
    const next = sendTextQueue[0];
    const editor = sayEditor();
    const free = next.chat === myChatId() && editor?.isConnected && !sendTextState.busy &&
      !sendDelayState.counting && !sendTextFieldBusy(editor);
    if (!free) { sendTextQueueEmptySince = null; return; }
    if (sendTextQueueEmptySince == null) { sendTextQueueEmptySince = t; return; }
    if (t - sendTextQueueEmptySince < SEND_TEXT_QUEUE_GRACE_MS) return;
    sendTextQueue.shift();
    sendTextQueueEmptySince = null;
    sendTextPut(next.id, next.chat, editor, next.text);
  };
  track(() => {
    if (sendTextQueueTimer != null) clearInterval(sendTextQueueTimer);
    sendTextQueueTimer = null;
    sendTextQueue.splice(0);
    try { document.getElementById(SEND_TEXT_QUEUE_ID)?.remove(); } catch {}
  });
  try { document.getElementById(SEND_TEXT_QUEUE_ID)?.remove(); } catch {}
  // Обход (#11571): в поле одни вставки голоса, и их никто не отправляет — стереть.
  const sendTextSweep = () => {
    if (!state.alive || sendTextState.busy || shotState.pending > 0 || composerTileNames().length) return;
    const editor = sayEditor();
    const text = editor?.isConnected ? rawText(editor) : "";
    if (!sayNorm(text) || sendTextNoVoice(text)) return;
    if (newWindowClearOwn(editor, text)) sendTextState.cleared += 1;
  };
  const sendTextSweepTimer = setInterval(() => { try { sendTextSweep(); } catch {} }, SEND_TEXT_SWEEP_MS);
  track(() => clearInterval(sendTextSweepTimer));
  // Вставка и нажатие «отправить»; busy — пока идёт, очередь ждёт.
  const sendTextPut = (id, chat, editor, text) => {
    sendTextState.busy = true;
    const finish = result => {
      sendTextState.busy = false;
      // Голос не ушёл — из поля вон, если там ровно он: письмо дойдёт почтой (#11571).
      if (result !== "sent" && sendTextVoice(text) && newWindowClearOwn(editor, text)) sendTextState.cleared += 1;
      sendTextDone(id, result);
    };
    const shotRevision = shotState.revision;
    const sameEditor = () => state.alive && shotState.revision === shotRevision && myChatId() === chat && editor?.isConnected && findEditor() === editor;
    if (!sameEditor() || sendTextFieldBusy(editor)) { finish("no-send"); return; }
    sayWrite(editor, text);
    if (sayNorm(rawText(editor)) !== sayNorm(text)) { finish("no-send"); return; }
    // React должен принять вставку до нажатия. Пока ждём живую кнопку, каждое
    // чтение и нажатие относятся к тому же чату и редактору. Снимок поля
    // (expected) — не в такте вставки, а с первого опроса, когда ProseMirror уже
    // разобрал её (пробелы, абзацы, правила ввода); до нажатия сверка по sayNorm
    // и снимок обновляется, после нажатия — точная: другое в поле — правка
    // Элвиса, no-send. Повтор (WF103, живой случай «первое нажатие не взяло»,
    // возвращён в WF111) — одно нажатие через SEND_TEXT_REPRESS_MS, только если в
    // поле всё ещё ровно наш текст: ушедшее первое нажатие поле бы опустошило.
    let button = null;
    try { button = document.querySelector(SEND_SELECTOR); } catch {}
    if (!button) { finish("no-send"); return; }
    const start = now();
    let expected = null;
    let pressedAt = null;
    let presses = 0;
    const hasAttachments = () => shotState.pending > 0 || composerTileNames().length > 0;
    const press = () => {
      let send = null;
      try { send = document.querySelector(`${SEND_SELECTOR}:not([disabled])`); } catch {}
      if (!send?.isConnected || send.disabled === true || !sameEditor() || rawText(editor) !== expected || hasAttachments()) return false;
      pressLikeMouse(send);
      presses += 1;
      return true;
    };
    const check = () => {
      if (!state.alive) { sendTextState.busy = false; return; }
      if (!sameEditor() || hasAttachments()) { finish("no-send"); return; }
      const current = rawText(editor);
      if (pressedAt != null && !sayNorm(current)) { finish("sent"); return; }
      if (pressedAt == null) {
        if (sayNorm(current) !== sayNorm(text)) { finish("no-send"); return; }
        expected = current;
      } else if (current !== expected) { finish("no-send"); return; }
      const t = now();
      if (pressedAt == null && t - start >= SEND_TEXT_PRESS_MS && press()) {
        pressedAt = t;
        if (!sameEditor() || hasAttachments()) { finish("no-send"); return; }
        if (!sayNorm(rawText(editor))) { finish("sent"); return; }
      }
      if (pressedAt == null && t - start >= SEND_TEXT_ALIVE_MS) { finish("no-send"); return; }
      if (presses === 1 && t - pressedAt >= SEND_TEXT_REPRESS_MS && press()) {
        if (!sameEditor() || hasAttachments()) { finish("no-send"); return; }
        if (!sayNorm(rawText(editor))) { finish("sent"); return; }
      }
      if (pressedAt != null && t - pressedAt >= SEND_TEXT_WAIT_MS) { finish("no-send"); return; }
      const timer = setTimeout(() => { sendTextTimers.delete(timer); check(); }, SEND_TEXT_POLL_MS);
      sendTextTimers.add(timer);
    };
    // Первый опрос — через SEND_TEXT_POLL_MS: ProseMirror успевает разобрать вставку.
    const first = setTimeout(() => { sendTextTimers.delete(first); check(); }, SEND_TEXT_POLL_MS);
    sendTextTimers.add(first);
  };
  track(() => { for (const timer of sendTextTimers) clearTimeout(timer); sendTextTimers.clear(); });
  // «Отправь текст в чат» (раздел 12т¹, WF103): исход последней send-text этого окна.
  statusPart("send", () => ({ id: sendTextState.id, state: sendTextState.state, at: sendTextState.at, sends: sendTextState.sends, queue: sendTextQueue.length, queued: sendTextState.queued, cleared: sendTextState.cleared }));
  HATCH && Object.assign(HATCH, { sendTextState, sendTextSweep, sendTextQueueTick, sendTextNoVoice });

