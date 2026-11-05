  // ---- 12и. «Ждёт тебя»: чей чат ждёт слова (#7177, WF83) ------------------
  // Вывод без света: свечение окна снято (дыхание — словом Элвиса 29.09, #8112:
  // «все чаты мигают… Вырубай»; свет окна диктовки — page-69, 11.10 06:48). Его
  // берут рамка «ждут твоего слова» (12и¹, waitState.why), «Сам» (autoJudge,
  // waitState.kind), холодный кэш отсчёта (sendDelayCold) и время сообщения (12о).
  //
  // «Ждёт» — по сессии чата из React-волокна его строки в списке слева
  // (roamSession, раздел 12е; разведка 23.09, 2.2553.13, и код сайдбара Claude):
  //   liveStatus "awaiting" — висит вопрос, план или разрешение человеку;
  //   liveStatus "idle" при hasCompleted и isUnread — ход кончен, ответ не
  //     прочитан (у чата Claude Code оба поля — один флаг unread);
  //   ход кончен на наших глазах (видели running, стал idle) и окно с тех пор
  //     никто не трогал (why = "done") — на случай, когда Claude считает
  //     открытый чат прочитанным сам.
  // Список слева есть только у главного окна; попап читает строку своего чата
  // в документе родителя (window.opener, тот же origin). Строки нет — молчим.
  // Пока окно ходит по чатам (обход 12е), чужой ждущий чат своим не считаем.
  // Своих таймеров нет — раздел шагает тиком сердца, раз в WAIT_SCAN_MS.
  // Узел свечения снят; id — ради уборки его сироты у прежних установок.
  const WAIT_GLOW_ID = "myclaude-wait-glow";
  const WAIT_SCAN_MS = 1000;
  // Выдержка «ждёт»: разрешение, которое через секунду нажмёт Авто-Allow, не в счёт (12и¹).
  const WAIT_HOLD_MS = 2000;
  for (const orphan of document.querySelectorAll(`#${WAIT_GLOW_ID}`)) orphan.remove();
  const waitState = { id: null, kind: "", why: "", ran: false, scanAt: -Infinity };
  // Сессия чата этого окна: строка сайдбара своего документа, у попапа — родителя.
  const waitSession = id => {
    if (!id) return null;
    let doc = null;
    try { doc = isMainWindow() ? document : window.opener?.document ?? null; } catch { doc = null; }
    if (!doc) return null;
    try {
      const key = String(id).replace(/["\\]/g, "\\$&");
      const row = doc.querySelector(`${ROAM_SIDEBAR_SELECTOR} [data-row-key$="${key}"]`);
      return row ? roamSession(row, id) : null;
    } catch { return null; }
  };
  // Что с чатом: "awaiting" | "ready" | "running" | "idle"; "" — не знаем.
  const waitVerdict = session => {
    if (!session || typeof session !== "object") return "";
    if (session.liveStatus === "awaiting") return "awaiting";
    if (session.liveStatus === "running" || session.isRunning === true) return "running";
    if (session.hasCompleted === true && session.isUnread === true) return "ready";
    return "idle";
  };
  const waitTick = t => {
    if (!themable || t - waitState.scanAt < WAIT_SCAN_MS) return;
    waitState.scanAt = t;
    // Окно ушло в чужой чат за Allow (обход 12е) — ждём, пока вернётся.
    if (roamState.phase !== "idle") return;
    let id = null;
    try { id = myChatId(); } catch { id = null; }
    if (id !== waitState.id) {
      waitState.id = id;
      waitState.ran = false;
    }
    const kind = waitVerdict(waitSession(id));
    waitState.kind = kind;
    if (kind === "running") waitState.ran = true;
    waitState.why = kind === "awaiting" || kind === "ready" ? kind : (kind === "idle" && waitState.ran ? "done" : "");
  };
  // Касание окна (фокус, клавиша, нажатие мыши): конец хода увиден, «done» гаснет
  // до нового хода. Касание посреди хода не в счёт (живой замер 23.09 12:54: Элвис
  // трогал окно, пока чат работал) — видеть нечего, ответа ещё нет.
  const onWaitTouch = () => {
    if (waitState.kind === "running") return;
    waitState.ran = false;
  };
  // «Ждёт тебя» (WF83, раздел 12и): почему (awaiting — вопрос или разрешение,
  // ready — непрочитанный ответ, done — ход кончен без касания окна) и что сейчас с чатом.
  statusPart("wait", () => ({ why: waitState.why || null, kind: waitState.kind || null }));
  HATCH && Object.assign(HATCH, { waitTick, waitState });

