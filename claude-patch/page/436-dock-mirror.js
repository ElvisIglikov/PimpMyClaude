  // ---- 12п⁴¹. Кадр панели материалов в подложке — для скриншотилок (#10760, WF279) ----
  // Слово Элвиса 23.10.2026: «Сделай, чтобы на скриншоте тоже было видно. Это важно. И в Диктаторе, и в других
  // программах скриншотилках». Панель (12п⁴) — отдельное окно PimpViewer поверх окна Claude; снимок одного окна Claude
  // её не берёт, на месте панели выходила подложка. PimpViewer снимает страницу дока в файл, Пимп отдаёт его
  // (К-DOCK-4 `GET /dock-shot?since=<версия>`: 200 JPEG с X-Pimp-Shot, 204 — та же версия, 404 — кадра нет); кадр
  // ложится фоном подложки во всё место: на экране его закрывает сама панель, в снимке окна Claude он виден.
  // Спрашиваем раз в DOCK_SHOT_MS, пока подложка стоит, PimpViewer «up» и окно не скрыто; подложка снята — кадр прочь.
  const DOCK_SHOT_MS = 700;
  const DOCK_SHOT_VARIABLE = "--myclaude-dock-shot";
  const dockShot = { version: "", url: "", busy: false, asked: 0, got: 0, errors: 0, at: null, timer: 0 };
  const dockShotPlaced = () => dockNodes.place.style.getPropertyValue("display") === "block";
  // Без URL.createObjectURL — data: (как mediaObjectUrl в 12п⁵); отзываем только blob:.
  const dockShotUrl = bytes => {
    try {
      if (typeof URL !== "undefined" && typeof URL.createObjectURL === "function" && typeof Blob === "function") {
        return URL.createObjectURL(new Blob([bytes], { type: "image/jpeg" }));
      }
    } catch {}
    try { return `data:image/jpeg;base64,${heicBase64(bytes)}`; } catch { return ""; }
  };
  const dockShotRevoke = url => {
    if (String(url).startsWith("blob:")) { try { URL.revokeObjectURL(url); } catch {} }
  };
  const dockShotClear = () => {
    if (dockNodes.place.style.getPropertyValue(DOCK_SHOT_VARIABLE)) dockNodes.place.style.removeProperty(DOCK_SHOT_VARIABLE);
    dockShotRevoke(dockShot.url);
    dockShot.url = "";
    dockShot.version = "";
  };
  const dockShotTake = (bytes, version) => {
    if (!state.alive || !dockShotPlaced()) return;
    if (!bytes || bytes.length < 3 || bytes[0] !== 0xFF || bytes[1] !== 0xD8) { dockShot.errors += 1; return; }
    const url = dockShotUrl(bytes);
    if (!url) { dockShot.errors += 1; return; }
    const old = dockShot.url;
    Object.assign(dockShot, { url, version, got: dockShot.got + 1, at: Date.now() });
    dockNodes.place.style.setProperty(DOCK_SHOT_VARIABLE, `url("${url}")`);
    dockShotRevoke(old);
  };
  const dockShotTick = () => {
    if (!dockShotPlaced()) { dockShotClear(); return; }
    if (!state.alive || !dockState.want || dockState.viewer !== "up" || document.hidden || dockShot.busy) return;
    if (typeof fetch !== "function") return;
    dockShot.busy = true;
    dockShot.asked += 1;
    const done = () => { dockShot.busy = false; };
    const fail = () => { dockShot.errors += 1; done(); };
    let sent = null;
    try {
      sent = fetch(`http://127.0.0.1:${HTML_CHROME_PORT}/dock-shot?since=${encodeURIComponent(dockShot.version)}`,
        { mode: "cors", credentials: "omit", cache: "no-store" });
    } catch { sent = null; }
    if (!sent || typeof sent.then !== "function") { fail(); return; }
    sent.then(reply => {
      const status = Number(reply?.status) || 0;
      if (status === 204) return done();
      if (status === 404) { dockShotClear(); return done(); }
      if (!reply?.ok || typeof reply.arrayBuffer !== "function") return fail();
      let version = "";
      try { version = String(reply.headers?.get?.("X-Pimp-Shot") ?? ""); } catch { version = ""; }
      return reply.arrayBuffer().then(buffer => { done(); dockShotTake(buffer ? new Uint8Array(buffer) : null, version); }, fail);
    }, fail).catch(done);
  };
  if (chatKind() === "main") dockShot.timer = setInterval(() => { try { dockShotTick(); } catch {} }, DOCK_SHOT_MS);
  track(() => {
    if (dockShot.timer) { clearInterval(dockShot.timer); dockShot.timer = 0; }
    dockShotClear();
  });
  lateRules.push(
    `#${DOCK_PLACE_ID}{background-image:var(${DOCK_SHOT_VARIABLE},none);background-size:100% 100%;background-repeat:no-repeat}`,
  );
  // Кадр панели в подложке (#10760, раздел 12п⁴¹): стоит ли, версия, когда пришёл, запросов, кадров, ошибок.
  statusPart("dockShot", () => ({
    shown: Boolean(dockShot.url), version: dockShot.version, at: dockShot.at, asked: dockShot.asked, got: dockShot.got,
    errors: dockShot.errors,
  }));
  HATCH && Object.assign(HATCH, { dockShot, dockShotTick, dockShotClear, DOCK_SHOT_MS, dockNodes });
