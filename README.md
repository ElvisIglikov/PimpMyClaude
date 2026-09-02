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

## Ручка над полем ввода (`claude-patch/inject.js`)

Живой скрипт, лоадер v6 выполняет его в каждой странице Claude и перечитывает при изменении файла
(копия лежит в `~/Library/Application Support/MyClaude/inject.js`). Поведение как в ElvisOS:
- Едва заметная полоска над полем ввода, ярче при наведении. Тянуть вверх/вниз — высота поля.
- Одинарный клик: поле схлопывается в полоску и обратно (из растянутого — тоже схлопывается).
- Двойной клик: растянуть до потолка окна; ещё раз двойной — обычная высота.
- После отправки поле НЕ сворачивается. Работает и в окнах «Open in new window».
- Команды из меню (см. ниже): `collapse`, `expand` — только окну в фокусе; `scroll` — всем окнам;
  `cashout` — сохраняет последний ответ и черновик, вставляет их в свежий чат.
- Проверка: `probe.js` с `window.__myclaude.status()`.

## Меню на кнопке «Свернуть» (`hammerspoon/claude_minimize_menu.lua`)

Наведи курсор на жёлтую кнопку окна Claude и подержи 0,3 с — всплывёт меню:
Обкэшить · Новый чат · ─ · Свернуть · Развернуть · ─ · Расставить · Показать · Прокрутить.
Свернуть/Развернуть — это поле ввода, не окно. Расставить — сеткой на главном экране. Показать — все
окна Claude вперёд. Прокрутить — все чаты к последнему сообщению.

Установка (один раз):
```bash
cp ~/_ElvisProjects/MyClaude/hammerspoon/claude_minimize_menu.lua ~/.hammerspoon/ && echo 'pcall(function() require("claude_minimize_menu") end)' >> ~/.hammerspoon/init.lua && hs -c 'hs.reload()'
```
Пункты Свернуть/Развернуть/Прокрутить/Обкэшить идут через `command.json` — нужен лоадер v6
(`patch-claude.mjs` поставить заново, когда удобно перезапустить Claude).

## План

1. ✅ Ручка, свернуть/развернуть (WF1, `docs/plan-wf1-2026-09-03.md`).
2. ✅ Меню семь пунктов (WF1 + WF2, `docs/plan-wf2-2026-09-03.md`); «3 min ago» — WF2/A2.
3. Сторож обновлений — отложен по слову Элвиса.
3а. ⌘Q не должен закрывать Claude (слово Элвиса 03.09 01:30: случайно нажал, закрылись все четыре окна). Блокировать ⌘Q в Claude, выход только через меню. Hammerspoon-модуль `claude_noquit.lua` (hs.hotkey ⌘Q активен только когда Claude впереди, через hs.application.watcher).
4. MyClaude.app на Swift для команды (Маша, Алла, Денис): установщик, меню и авто-Allow без Hammerspoon,
   подпись Developer ID + нотаризация. Отдельный воркфлоу после закрытия фишек.

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
