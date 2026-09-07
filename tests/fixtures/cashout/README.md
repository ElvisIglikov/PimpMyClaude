Эталоны контракта WF37 «Ремонт Пимпа» (план docs/plan-wf37-2026-09-07.md). Читают ОБА батча: страница (tests/*.mjs)
и Swift (CommandChannel.payload побайтно; id "1756900000123-0042", at 2025-09-03T11:46:40Z, как в testNewWindowPayloadMatchesContract).
Байты — как пишет CommandChannel.payload: без пробелов, id, action, at, затем поля в порядке контракта.

- cashout-main.json — «Обкэшить» в главном окне с открытым чатом: scope, title, match (путь главного окна).
- cashout-main-home.json — то же на домашнем экране: пути нет → scope, title.
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
  v, nonce, kind, self, path, row, title, popouts, store, folder, at, themes (themes только у главного окна).
- probe-answer-chat.json — главное окно в открытом чате: folder: null всегда (папку даёт индекс).
- probe-answer-popout.json — попап: folder: null, themes нет.
