Эталоны контракта WF37 «Ремонт Пимпа» (план docs/plan-wf37-2026-09-07.md). Читают ОБА батча: страница (tests/*.mjs)
и Swift (CommandChannel.payload побайтно; id "1756900000123-0042", at 2025-09-03T11:46:40Z, как в testNewWindowPayloadMatchesContract).
Байты — как пишет CommandChannel.payload: без пробелов, id, action, at, затем поля в порядке контракта.

- cashout-main.json — «Обкэшить» в главном окне с открытым чатом: scope, title, match (путь главного окна).
- cashout-main-home.json — то же на домашнем экране: пути чата нет → match:"/epitaxy" (гейт WF37: заголовком «Claude» команду взял бы и безымянный попап).
- cashout-popout.json — «Обкэшить» в попапе, id чата известен из карты probe: scope, title, chat. match попапу не шлётся никогда.
- cashout-popout-title.json — попап, id неизвестен: scope, title (адрес заголовком, как до WF37).
- new-window-transfer.json — «Новое окно» из ветки «Обкэшить»: transfer:true стоит ПОСЛЕ name и ПЕРЕД слоями;
  порядок scope, title, match?, x, y, text, folder, name, transfer?, theme?, font?, size?, frame?. Значение text —
  не часть контракта (часть A меняет его на локальную команду).
- new-window-transfer-plain.json — то же без проекта («Здесь же»): folder и name пустые, transfer:true.
  Команды без transfer (⌥⌘N, «▸ проект», канал «Пимп») поля НЕ содержат вовсе — прежний контракт WF16.
- record-main.json — запись localStorage myclaude-cashout из главного окна: at, text (как до WF37).
- record-pending.json — запись из попапа: at, text, to:"pending"; сторож в попапе-доноре не заводится.
- record-stamped.json — запись после шагов 5 и 6б цепочки с transfer: at, text, to:<id нового чата>, title:<заголовок строки>, stampedAt.
  Свежесть штампованной записи — от stampedAt (60 с), главное окно записи с to игнорирует всегда.
- probe-answer-home.json — ответ chats() главного окна на домашнем экране: folder — строка; порядок ключей
  v, nonce, kind, self, path, row, title, popouts, store, folder, at, frame, themes (themes только у главного окна).
- probe-answer-chat.json — главное окно в открытом чате: folder: null всегда (папку даёт индекс).
- probe-answer-popout.json — попап: folder: null, themes нет.
- frame (WF77) — [screenX, screenY, outerWidth, outerHeight] окна, целые, в ХВОСТЕ после at и перед themes.
  Шлют только наши страницы (main, popout); у kind:"other" и когда чисел нет — поля нет вовсе.
- working, limits (WF87, 25.09.2026) — после frame/mic и перед themes: working (true|false) у main и popout,
  limits ({v, at, plan, fiveHour, weekly, fable, source}, лимит — {used, resetsAt}) только у main. Сверяют оба конца:
  tests/chat-id.test.mjs (порядок ключей) и ChatProbeTests (разбор).

WF84 (23.09.2026, #7072, контракты К1 и К2 плана docs/plan-wf84-2026-09-23.md) — «💬 Новый чат» на ⌘B. Пишет батч P
ДО кода, по ним работают оба конца (страница и Swift M1).

- cashout-handoff.json — «Обкэшить» с `"handoff":true` ПОСЛЕДНИМ полем (попап: scope, title, chat, handoff).
  Текст — ТОЛЬКО из ПОСЛЕДНЕГО ответа: заголовок с «ОТКРОЙ НОВЫЙ ЧАТ» → первый `[data-code-text]` после него;
  узла нет — запись с `text:""` (не отказ, плашки нет). Черновик поля и вложения с handoff НЕ едут.
- cashout-handoff-main.json — то же из главного окна: scope, title, match, handoff.
- record-handoff.json — запись попапа-донора: at, text, to:"pending", handoff:true. Сторожа вставки не заводит.
- record-handoff-main.json — запись главного окна: at, text, handoff:true. Сторожа НЕ заводит (Б2): её забирает
  цепочка `new-window` с `sendTransfer` и сама стирает; tryPasteCashout её не вставляет никогда.
- record-handoff-empty.json — блока «ОТКРОЙ НОВЫЙ ЧАТ» в последнем ответе нет: text:"".
- record-sent.json — после штампа цепочки, когда текст ушёл первым сообщением: at, text, to, title, stampedAt,
  handoff:true, sent:true. Новый попап, увидев СВОЮ запись с sent:true или пустым text, сразу говорит «вставлено»
  (`status().cashout.delivery`) и ничего не вставляет.
- new-window-handoff.json — «Новый чат» из попапа: после transfer идут model?, effort?, sendTransfer?, stay?, потом
  слои; порядок scope, title, match?, x, y, text, folder, name, transfer?, model?, effort?, sendTransfer?, stay?,
  theme?, font?, size?, frame?. model — подпись пункта меню модели ЦЕЛИКОМ («Opus 5.5»; цифра клавиши в конце
  подписи пункта срезается страницей, «Opus 5» ≠ «Opus 5.5»); поля нет — модель не трогаем (донор на Auto).
  effort — имя ступени по aria-valuetext ползунка («Low»·«Medium»·«High»·«Extra»·«Max»; «xhigh» страница читает
  как «Extra»). Модель не встала — текст передачи НЕ уходит: уходит text, перенос вставит новый попап, как в WF37;
  `status().newWindow.model.note`. sendTransfer:true и непустой текст записи — он уходит первым сообщением
  ВМЕСТО text, запись штампуется с sent:true.
- new-window-handoff-stay.json — «Новый чат» из главного окна: stay:true, transfer нет. Без openPopout и без
  возврата: новый чат остаётся в главном окне. text-заглушка в режиме stay не отправляется НИКОГДА: уходит только
  текст передачи; его нет — остаётся домашний экран с папкой, моделью и эффортом. Запись цепочка стирает сама.
- mic (WF84, К4, #7054) — место кружка-микрофона в ответе chats(): ПОСЛЕ frame и только вместе с ним (наши страницы),
  `[dxRight, dyBottom, w, h]` — левый верхний угол значка от ПРАВОГО и НИЖНЕГО края окна, в точках, целые; значка не
  видно (поле открыто, кружка нет) — `null`. Экранная точка: x = screenX + outerWidth − dxRight, y = screenY +
  outerHeight − dyBottom (рамка — из frame того же ответа).

WF84 P3 (23.09.2026, #7246) — закрепка «Продолжить в новом чате».

- new-window-handoff-pin.json — «Новый чат» (меню ⌘B или кнопка в чате) несёт после `stay` поля `pin:true` (закрепить
  новый чат) и `unpin:"<id сессии донора>"` (открепить донора, только если он в Pinned); донора не знаем — `unpin`
  нет. Порядок: … sendTransfer?, stay?, pin?, unpin?, потом слои. Прочие пути (⌥⌘N, «▸ проект», канал «Пимп») этих
  полей не пишут.

WF85 (24.09.2026, #7347, контракт К7 плана docs/plan-wf85-2026-09-24.md) — «💬 Новый чат» сам.

- record-handoff-model.json — запись передачи с разобранной строкой «Модель:» блока: at, text, to?, handoff:true, потом
  `model` («Opus 5.5» — как подпись меню) и `effort` («Low»·«Medium»·«High»·«Extra»·«Max»; XHIGH и EXTRA → «Extra»).
  Поля — только разобранные, строго ПОСЛЕ handoff. Цепочка `new-window` с `sendTransfer` берёт их ДО шага модели, и они
  сильнее донорских полей команды (`status().newWindow.model.from` = "блок"); модели из блока нет в меню — откат на
  донорскую модель команды (`from:"донор"`, `note:"блок: no-model"`), текст уходит.
