  // ---- 13в¹. Верх стартового сообщения — вёрсткой ответа (#11399) ----------
  // Слово Элвиса 31.10 ~15:15 о последнем ответе прежнего Рика в начале нового чата (раздел 12ф², #10904): «эти
  // теги просто detail, суммари… чтобы здесь тоже всё работало. Вот эта верстка… чтобы я мог читать её
  // по-нормальному. Ну, со свёртками». Сообщение человека Claude не размечает — верх (ответ Рика дословно) шёл сырым
  // Markdown: «**», «#», <details>. Верх рисует Markdown шва (13в, seamProse): заголовки, жирный, списки, таблицы и
  // свёртки <details> видом 12ф, классы и переменные — с живого ответа (стили — общим охватом SEAM_MD в 677). Узлы
  // Claude не трогаются; раскрыл низ — исходник, как раньше (head-open). Упало — верх простым текстом.
  const USER_FOLD_MD_ATTRIBUTE = "data-myclaude-ufold-md";
  const userFoldMd = { painted: 0, error: null };
  const userFoldMdPaint = (own, head) => {
    const look = seamLook(document);
    const prose = seamProse(head, look);
    own.textContent = "";
    own.appendChild(prose);
    const weight = look.vars?.["--myclaude-seam-strong-w"];
    if (weight) own.style.setProperty("--myclaude-seam-strong-w", weight);
    own.setAttribute(USER_FOLD_MD_ATTRIBUTE, "");
    userFoldMd.painted += 1;
  };
  userFold.headPaint = (own, head) => {
    try { userFoldMdPaint(own, head); } catch (error) {
      userFoldMd.error = String(error?.message ?? error).slice(0, 200);
      own.textContent = head;
      own.removeAttribute(USER_FOLD_MD_ATTRIBUTE);
    }
  };
  // Верх, собранный первым проходом 545 при установке (до этого раздела), — перерисовать.
  for (const entry of userFold.entries.values()) {
    if (entry.head && !entry.head.hasAttribute(USER_FOLD_MD_ATTRIBUTE)) userFold.headPaint(entry.head, entry.head.textContent);
  }
  track(() => { userFold.headPaint = null; });
  lateRules.push(`[${USER_FOLD_ATTRIBUTE}="head"][${USER_FOLD_MD_ATTRIBUTE}]{white-space:normal}`);
  statusPart("userFoldMd", () => ({ on: Boolean(userFold.headPaint), painted: userFoldMd.painted, error: userFoldMd.error }));
  HATCH && Object.assign(HATCH, { userFoldMd });
