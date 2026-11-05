  // ---- 12п¹. Кнопка «PMP» — панель PimpMyClaude у часов (#8894, WF125) ------
  // Слово Элвиса 07.10: «вот здесь кнопка повторно воспроизвести голос Рика…
  // Там же должна PMP-кнопка быть». Стоит на месте прежней кнопки Рика (#7960,
  // WF103; повтор голоса со страницы снят) и по её правилам: только в окне, чей
  // проект — папка Rick (последний компонент cwd сессии чата, mentionCwd раздела
  // 12д¹; ответ помним PMP_CWD_MS на чат — список слева не обходим на каждом
  // проходе), ставит её placeGallery. Фокус поля не отнимает.
  // С WF213 (#9373, слово Элвиса 10.10: «в строке меню кнопка Пимпа и в клоде — это две разных
  // кнопки… поведение… и то, как они выглядят, должно быть совсем по-разному»; критик WF209 п. 13):
  // кнопка — во всех чатах главного окна (pmpWanted; в попапе — как было, только чат папки Rick,
  // rickWanted), нажатие открывает и закрывает панель оркестрации страницы (раздел 12п³). Enter и
  // пробел на кнопке — то же нажатие. С #9507 (слово Элвиса 10.10 ~11:00 по снимку «10 ⊞ 54 ▶6»:
  // «весь функционал кнопки… подменили, оно сейчас не нужно») на кнопке только надпись «PMP»: числа
  // недели и «▶N» у неё нет — сколько Workflow идёт, говорят подсказка и сама панель.
  // Панель у часов — командой «Настройки Пимпа» той панели (pmpOpen): GET /panel на порт
  // приложения (CORS, как «Галерея»): приложение
  // открывает панель у часов и отвечает 204. Пока ждём ответа (state "wait"),
  // повторный запрос — ничего. Отказ, сетевая ошибка или тишина
  // PMP_WAIT_MS — «PimpMyClaude не отвечает» над кнопкой и вид "silent", с
  // подсказкой вид возвращается сам. Панель уже открыта — её закрывает сам клик
  // мимо неё, а приложение на запрос сразу следом её не открывает: не моргает.
  // Тем же путём — «Всё в одном чате» той панели (#9552, К-OC): pmpOpen("/one-chat").
  const pmpState = { clicks: 0, last: null, seq: 0, timer: 0, back: 0, cwd: { chat: null, at: -Infinity, pmp: false } };
  // Панель оркестрации (раздел 12п³): открыта ли, какие строки раскрыты, раскрыт ли блок Workflow (flows) и
  // узел его свёрнутой строки (line), модель из ответа /digest, текст запуска Workflow (К-KO; null — адреса нет),
  // чем кончился последний запрос сводки.
  const pmpPanel = { open: false, rows: new Set(), flows: false, line: null, model: null, kickoff: null, kickSeq: 0, error: null, timer: 0, sig: "", opens: 0, last: "" };
  const pmpNode = (() => {
    for (const orphan of document.querySelectorAll(`#${PMP_ID}`)) orphan.remove();
    const node = document.createElement("div");
    node.id = PMP_ID;
    node.setAttribute("role", "button");
    node.setAttribute("aria-label", PMP_TITLE);
    node.setAttribute("aria-haspopup", "true");
    node.setAttribute("aria-expanded", "false");
    node.setAttribute("tabindex", "0");
    node.title = PMP_TITLE;
    const plate = document.createElement("span");
    plate.className = "p";
    plate.textContent = "PMP";
    node.append(plate);
    (document.body ?? document.documentElement).appendChild(node);
    track(() => node.remove());
    return node;
  })();
  // Чат папки Rick: в попапе кнопка PMP стоит только в нём.
  const rickWanted = () => {
    const chat = galleryChat();
    if (!chat) return false;
    const memo = pmpState.cwd;
    const at = now();
    if (memo.chat !== chat || at - memo.at >= PMP_CWD_MS) {
      let cwd = "";
      try { cwd = mentionCwd(); } catch { cwd = ""; }
      memo.chat = chat;
      memo.at = at;
      memo.pmp = cwd.replace(/\/+$/, "").split("/").pop() === PMP_FOLDER;
    }
    return memo.pmp;
  };
  const pmpWanted = () => Boolean(galleryChat()) && (isMainWindow() || rickWanted());
  // Сколько Workflow идёт — из последней сводки (общая с панелью оркестрации); сводка старше
  // RICK_CELLS_STALE_MS — числа нет. Число — в подсказке кнопки, не на ней (#9507).
  // Слово Элвиса 10.10 23:05 скрыло блок «Идёт Workflow сейчас» целиком («Пока убери его… Потом вернём,
  // когда надо») и с ним знак «▶N» у кнопки; 17.10 00:37 — вернуть одной строкой (лист 48 · 1.2, «делай по
  // рекомендациям»): блок снова виден. Спрятать опять — false. «Ждут тебя» снят совсем (#9520).
  const PMP_FLOWS_SHOWN = true;
  const pmpRunning = () => (PMP_FLOWS_SHOWN && pmpPanel.model && now() - rickState.okAt < RICK_CELLS_STALE_MS ? pmpPanel.model.running : 0);
  const pmpWidth = () => PMP_WIDTH;
  const pmpHide = () => {
    if (pmpNode.style.getPropertyValue("display") !== "none") pmpNode.style.setProperty("display", "none");
  };
  // Сторож своих узлов (ownNodes) её не знает — вынесло из body, вернём сами.
  const pmpShow = (left, top, spot) => {
    if (!pmpNode.isConnected) { try { (document.body ?? document.documentElement).appendChild(pmpNode); } catch {} }
    pmpNode.style.setProperty("display", "flex");
    pmpNode.style.setProperty("left", `${Math.round(left)}px`);
    pmpNode.style.setProperty("top", `${Math.round(top)}px`);
    if (pmpNode.dataset.spot !== spot) pmpNode.dataset.spot = spot;
    const at = now();
    const running = pmpRunning();
    const title = running > 0 ? `${PMP_TITLE} · ${running} ${usagePlural(running, "идёт", "идут", "идут")}` : PMP_TITLE;
    if (pmpNode.title !== title) pmpNode.title = title;
    // Число в подсказке обновляет редкий запрос отсюда (не чаще PMP_COUNT_MS, окно видно) — во всех чатах: блока у
    // поля, который спрашивал сводку в чате папки Rick, с page-60 нет.
    if (!pmpPanel.open && !document.hidden && at - rickState.triedAt >= PMP_COUNT_MS) { try { rickFetch(); } catch {} }
    if (pmpPanel.open) { try { pmpPanelPlace(); } catch {} }
  };
  const pmpPaint = value => {
    if (value) pmpNode.dataset.state = value;
    else delete pmpNode.dataset.state;
  };
  const pmpSettle = () => {
    if (pmpState.timer) { clearTimeout(pmpState.timer); pmpState.timer = 0; }
    if (pmpState.back) { clearTimeout(pmpState.back); pmpState.back = 0; }
  };
  track(() => { pmpState.seq += 1; pmpSettle(); });
  // Ответ на запрос seq: ok — вид возвращается; иначе подсказка и "silent" на её срок.
  const pmpAnswer = (seq, ok) => {
    if (seq !== pmpState.seq || pmpNode.dataset.state !== "wait") return;
    pmpSettle();
    if (ok) { pmpPaint(null); return; }
    pmpPaint("silent");
    micHint(PMP_SILENT_TEXT, pmpNode, PMP_WIDTH);
    pmpState.back = setTimeout(() => { pmpState.back = 0; pmpPaint(null); }, MIC_HINT_MS);
  };
  const pmpOpen = (path = "/panel") => {
    if (!pmpWanted() || pmpNode.dataset.state === "wait") return false;
    pmpSettle();
    const seq = pmpState.seq += 1;
    pmpState.clicks += 1;
    pmpState.last = `http://127.0.0.1:${HTML_CHROME_PORT}${path}`;
    pmpPaint("wait");
    pmpState.timer = setTimeout(() => { pmpState.timer = 0; pmpAnswer(seq, false); }, PMP_WAIT_MS);
    let sent = null;
    if (typeof fetch === "function") {
      try { sent = fetch(pmpState.last, { mode: "cors", credentials: "omit", cache: "no-store" }); } catch { sent = null; }
    }
    if (sent && typeof sent.then === "function") sent.then(reply => pmpAnswer(seq, Boolean(reply?.ok)), () => pmpAnswer(seq, false));
    else pmpAnswer(seq, false);
    return true;
  };
  on(pmpNode, "click", event => {
    event.preventDefault();
    if (!state.alive || Number(event.detail) > 1) return;
    try { pmpPanelToggle(); } catch {}
  });
  // С клавиатуры (Tab до кнопки): Enter и пробел — то же нажатие; фокус уходит в панель.
  on(pmpNode, "keydown", event => {
    if (!state.alive || (event.key !== "Enter" && event.key !== " ")) return;
    event.preventDefault();
    try { if (pmpPanelToggle()) pmpPanelFocus(0); } catch {}
  });
  on(pmpNode, "pointerdown", galleryKeepFocus);
  on(pmpNode, "mousedown", galleryKeepFocus);
  // Кнопка «PMP» (#8894, раздел 12п¹): видна ли, запросов к приложению (команды «Настройки Пимпа»
  // и «Всё в одном чате»), адрес последнего, вид (null — обычный, "wait", "silent").
  // С WF213 — панель оркестрации (12п³): open, rows — строк счётчика на виду,
  // terminals — строк «работают N терминалов», running — идущих Workflow (число
  // в подсказке кнопки), lastError — чем кончился последний запрос сводки (null — ответом).
  statusPart("pmp", () => ({
    button: pmpNode.isConnected && pmpNode.style.display !== "none",
    clicks: pmpState.clicks, last: pmpState.last, state: pmpNode.dataset.state ?? null,
    ...pmpPanelStatus(),
  }));
  HATCH && Object.assign(HATCH, { pmpPanel });

