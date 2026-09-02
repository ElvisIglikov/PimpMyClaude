# MyClaude

## Узкие окна Claude и узкие поля по бокам (патч Claude Desktop)

`claude-patch/patch-claude.mjs` — дописывает в Claude.app маленький лоадер (взято точечно из ElvisOS).
Даёт две вещи, без панели настроек: минимальная ширина любого окна Claude 360 вместо 600 и поля по бокам текста 16 px вместо 32/40.

- Поставить (закроет и снова откроет Claude, переподпишет его локальной подписью):
  `node ~/_ElvisProjects/MyClaude/claude-patch/patch-claude.mjs`
- Проверить: `node ~/_ElvisProjects/MyClaude/claude-patch/patch-claude.mjs status`
- Вернуть оригинал: `... restore`. Прогон на копии без изменений приложения: `... selftest`.
- Значения лежат в `~/Library/Application Support/MyClaude/claude.json` (`minWindowWidth`, `sidePadding`), меняются на лету, перезапуск не нужен.
- Диагностика: лоадер раз в 2 с пишет `~/Library/Application Support/MyClaude/status.json` (окна, минимумы, куда вставлен CSS). Положи рядом `probe.js` — любой JS выполнится во всех страницах claude.ai, ответ в `probe-result.json`.
- Живой CSS `claude-patch/claude.css` (копия лежит в Application Support): скрыты стрелки «назад/вперёд» в заголовке; строка действий под сообщением (копировать, форк, «3 minutes ago») видна всегда.
- После обновления Claude патч слетает — запустить установку снова. После первой установки macOS один раз заново спросит разрешения.
- Бэкап оригинальных app.asar и Info.plist: `~/Library/Application Support/MyClaude/backups/<версия>/`.

## План (решения 02.09.2026)

1. Ручка над полем ввода: едва заметная полоска, ярче при наведении. Клик — шаг по ступеням (полоска → обычная → растянуто), двойной клик — до упора, тянуть тоже можно. После отправки поле НЕ сворачивается. Едет в патч.
2. Меню по наведению на кнопку «Свернуть» окна (Hammerspoon), окончательный состав 03.09: Обкэшить, Новый чат, ─, Свернуть, Развернуть, ─, Расставить, Показать, Прокрутить. Первые четыре — WF1 (`docs/plan-wf1-2026-09-03.md`), последние три — WF2 (`docs/plan-wf2-2026-09-03.md`).
3. Сторож обновлений (Hammerspoon): при запуске Claude проверяет патч; слетел — уведомление с кнопкой «Поставить».
4. Скрыть стрелки «назад/вперёд» в заголовке окна (они в внешней оболочке окна, не на claude.ai — нужен лоадер v5, CSS во все страницы).

## Auto-Allow для окон Claude Desktop

`hammerspoon/claude_autoallow.lua` — модуль Hammerspoon, сам жмёт «Allow» в диалогах разрешений Claude Desktop.
Нужен потому, что часть инструментов (например, create routine) спрашивают в любом режиме, и хуками/настройками Claude это не отключается.

- Ставится: `cp hammerspoon/claude_autoallow.lua ~/.hammerspoon/`, в `~/.hammerspoon/init.lua` строка `pcall(function() require("claude_autoallow") end)`, потом `hs -c 'hs.reload()'`.
- Работает всегда: Hammerspoon стартует при входе в систему (autoLaunch в init.lua), модуль грузится вместе с ним.
- Жмёт любую кнопку «Allow…» во всех окнах Claude, не только для workflow. Исключения — список `M.blockHeadingPatterns` в файле.
- Признак что работает: вверху экрана, в строке справа рядом с часами и батареей, иконка 🤖✓ (может прятаться, если иконок много). Выключить/включить: зажать control+option+command и нажать A, на экране мелькнёт «Claude auto-allow: OFF/ON».
- Выключить из терминала: `hs -c 'require("claude_autoallow").setEnabled(false)'`, включить: то же с `true`.
- Проверено 2026-09-02: окно «Allow once» закрылось само, в history() две записи.
- Проверка: `hs -c 'return require("claude_autoallow").status()'`, история нажатий: `hs -c 'return require("claude_autoallow").history()'`.
- Диалог должен быть виден на экране: окно свёрнуто или сессия не открыта — не нажмёт.
