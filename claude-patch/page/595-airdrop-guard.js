  // ---- 12т². Фото с AirDrop в поле Рика (#9358) -------------------------------
  // Приложение (AirDropWatch.swift) увидело новые фото AirDrop в «Загрузках» и
  // вставляет их в поле главного чата тем же путём, что pimp.py paste-airdrop:
  // файлы в буфер, окно вперёд, ⌘V; Enter не жмёт. Перед ⌘V всем окнам уходит
  // airdrop-guard {id, n}: страница взводит сторожа на AIRDROP_GUARD_MS. Первая
  // доверенная вставка с файлами его снимает и идёт как есть — и в поле с текстом:
  // фото ложатся рядом с черновиком, текст не трогается (#11310, слово Элвиса 31.10
  // ~02:58: «Скриншот сейчас с аэрдропа пришёл и… не вставился» — прежде вставка
  // в поле с текстом гасилась, status().airdrop.last = "busy"). Плашка — «вставил N фото».
  const AIRDROP_GUARD_MS = 6000;
  const AIRDROP_IDS = 20;
  const AIRDROP_NOTE_MS = 4000;
  const airdropState = { id: null, n: 0, until: 0, ids: [], last: null };
  const airdropArm = detail => {
    const id = typeof detail?.id === "string" ? detail.id : "";
    const n = typeof detail?.n === "number" ? detail.n : NaN;
    if (!id || airdropState.ids.includes(id) || !Number.isInteger(n) || n < 1) return;
    airdropState.ids.push(id);
    if (airdropState.ids.length > AIRDROP_IDS) airdropState.ids.shift();
    Object.assign(airdropState, { id, n, until: Date.now() + AIRDROP_GUARD_MS });
  };
  const airdropPaste = event => {
    if (!airdropState.id || Date.now() > airdropState.until || !event?.isTrusted) return;
    if (!(event.clipboardData?.files?.length > 0)) return;
    const n = airdropState.n;
    Object.assign(airdropState, { id: null, until: 0 });
    airdropState.last = "pasted";
    try { newWindowNote(`📲 Вставил ${n} фото с AirDrop — жми Enter`, false, AIRDROP_NOTE_MS); } catch {}
  };
  on(window, "paste", airdropPaste, true);
  // Сторож взведён ли и чем кончилась последняя вставка AirDrop: pasted | null.
  statusPart("airdrop", () => ({ armed: Boolean(airdropState.id) && Date.now() <= airdropState.until, last: airdropState.last }));
  HATCH && Object.assign(HATCH, { airdropArm, airdropPaste, airdropState });

