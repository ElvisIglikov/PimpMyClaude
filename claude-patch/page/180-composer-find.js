  // ---- 5. Поиск поля ввода ------------------------------------------------
  // Свёрнутый блок ввода схлопнут в ноль и прижат к нижнему краю окна: у
  // редактора внутри геометрия перестаёт быть «видимой», хотя сам он живой и
  // держит черновик. Без этой поблажки поле терялось, свёрнутость снималась,
  // блок разворачивался — и на следующем кадре всё повторялось: низ окна
  // начинал мигать с частотой перерисовки.
  // Ниже этой ширины найденное считается не полем ввода, а чужим элементом
  // страницы. Порог не голые 200 точек: окна Элвиса бывают по 280, поле внутри
  // получается 194 — и по голому порогу поля в подчинённых окнах не находилось
  // вовсе, а вместе с ним пропадала и полоска над ним (#5857). В узком окне
  // порог считается от самого окна, в широком остаётся прежним.
  const narrowLimit = () => Math.min(200, innerWidth * 0.6);
  const visibleEditor = element => {
    const computed = getComputedStyle(element);
    if (element.disabled || computed.display === "none" || computed.visibility === "hidden") return false;
    if (element.closest(COLLAPSED_BLOCK_SELECTOR)) return true;
    const rect = element.getBoundingClientRect();
    // Само поле ввода Claude в узкой правой колонке бывает уже порога (09.10: 190 px при полях 24
    // по 33.5) — раскладка теряла поле, а с ним полосу Рика, шрифт поля и вложения. Порог узкого
    // окна — для чужих редакторов; поле composer'а видно от 120 px.
    const floor = element.closest('[data-cds="ChatComposer"]') ? Math.min(120, narrowLimit()) : narrowLimit();
    return rect.width >= floor && rect.bottom > 0 && rect.top < innerHeight;
  };
  // Кэш держится не на счётчике мутаций (во время набора дерево меняется каждую
  // букву), а на проверке самого ответа: прежнее поле всё ещё в документе, всё
  // ещё видно и всё ещё .ProseMirror. Держимся только за .ProseMirror — textarea
  // выигрывает развёртку лишь когда composer'а нет вовсе. И считаем ЖИВЫЕ
  // .ProseMirror: их число изменилось — значит рядом появился ещё один, и
  // выбирать надо заново (React пересоздаёт composer при смене чата).
  let editorHit = null;
  let editorSeen = -1;
  const findEditor = () => {
    const live = document.getElementsByClassName("ProseMirror");
    if (editorHit?.isConnected && live.length === editorSeen &&
        editorHit.classList.contains("ProseMirror") && visibleEditor(editorHit)) {
      return editorHit;
    }
    editorSeen = live.length;
    editorHit = [...document.querySelectorAll(EDITOR_SELECTOR)]
      .filter(visibleEditor)
      .map(element => ({ element, score: (element.matches(".ProseMirror") ? 100000 : 0) + element.getBoundingClientRect().bottom * 10 }))
      .sort((left, right) => right.score - left.score)[0]?.element ?? null;
    return editorHit;
  };
