  // ---- 0. Снятие прошлого экземпляра -------------------------------------
  // Сначала штатный путь, потом реестр уборки: даже упавшая на середине
  // установка оставляет после себя готовый список отмен, и следующий инжект
  // начинает с чистого листа (приём донора).
  let previousDim = null;
  try { previousDim = window.__myclaude?.status?.().dim ?? null; } catch {}
  try { window.__myclaude?.dispose?.(); } catch {}
  const REGISTRY_KEY = "__myclaudeUndo";
  const pendingUndo = window[REGISTRY_KEY];
  if (Array.isArray(pendingUndo)) {
    for (const undo of pendingUndo.splice(0).reverse()) { try { undo(); } catch {} }
  }
  const undoList = [];
  window[REGISTRY_KEY] = undoList;
  const track = undo => { undoList.push(undo); };
  // Подписка и её снятие пишутся одной строкой — разъехаться они не могут.
  const on = (target, type, handler, options) => {
    target.addEventListener(type, handler, options);
    track(() => target.removeEventListener(type, handler, options));
  };

