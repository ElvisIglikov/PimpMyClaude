# PimpMyClaude

Прокачка Claude Desktop, как «Pimp My Ride», только для окон Claude. Бывший MyClaude (переименован 03.09.2026). GitHub: `ElvisIglikov/PimpMyClaude`.

## PimpMyClaude.app — приложение для команды

`app/` — приложение на Swift (AppKit, без Node и Hammerspoon), делает всё то же, что описанные ниже
`claude-patch/patch-claude.mjs` и три Lua-модуля: патчит Claude, меню на жёлтой кнопке, горячие клавиши,
блок ⌘Q, авто-Allow. Значок в строке меню: «Поставить», «Снять», статус патча, тумблеры, автозапуск при входе.
Инструкция для Маши, Аллы и Дениса — `docs/TEAM.md`.

- Собрать и подписать Developer ID: `tools/bundle.sh` (по умолчанию `release`, кладёт `app/.build/PimpMyClaude.app`;
  куда класть — переменная `APP_OUT`, чем подписывать — `SIGN_ID`).
- Релиз для раздачи: `tools/release.sh` — сборка → нотаризация у Apple (`xcrun notarytool`, профиль keychain
  `pimpmyclaude`) → `stapler staple` → `dist/PimpMyClaude-<версия>.zip`, проверенный `spctl` на распакованной копии.
  Версия — `CFBundleShortVersionString` в `app/Resources/Info.plist`. Профиль заводится один раз:
  `xcrun notarytool store-credentials pimpmyclaude --apple-id <Apple ID> --team-id F27N4S4NJ4`.
- Тесты: `cd app && swift test`.

Структура `app/`: `Sources/Patcher` — порт `patch-claude.mjs` на Swift (формат asar, лоадер, `ElectronAsarIntegrity`,
бэкап/restore, переподпись Claude ad-hoc); `Sources/ClaudeAX` — авто-Allow, меню на кнопке «Свернуть», хоткеи и ⌘Q
на Carbon, Расставить/Показать/Прокрутить, команды странице через `command.json`; `Sources/PimpMyClaude` — меню-бар,
окно операций, первый запуск и разрешения; `Resources` — Info.plist, entitlements, иконка; `Tests` — тесты.

Всё, что ниже, — исходники той же логики: `claude-patch/` и `hammerspoon/` остаются дев-инструментом
(проверить идею, не пересобирая приложение) и источником правды по поведению. Команде раздаётся только приложение.

## Узкие окна Claude и узкие поля по бокам (патч Claude Desktop)

`claude-patch/patch-claude.mjs` — дописывает в Claude.app маленький лоадер (взято точечно из ElvisOS).
Даёт две вещи, без панели настроек: минимальная ширина любого окна Claude 360 вместо 600 и поля по бокам текста 16 px вместо 32/40.

- Поставить (закроет и снова откроет Claude, переподпишет его локальной подписью):
  `node ~/_ElvisProjects/PimpMyClaude/claude-patch/patch-claude.mjs`
- Проверить: `node ~/_ElvisProjects/PimpMyClaude/claude-patch/patch-claude.mjs status`
- Вернуть оригинал: `... restore`. Прогон на копии без изменений приложения: `... selftest`.
- Значения лежат в `~/Library/Application Support/MyClaude/claude.json` (`minWindowWidth`, `sidePadding`), меняются на лету, перезапуск не нужен.
- Диагностика: лоадер раз в 2 с пишет `~/Library/Application Support/MyClaude/status.json` (окна, минимумы, куда вставлен CSS). Положи рядом `probe.js` — любой JS выполнится во всех страницах claude.ai, ответ в `probe-result.json`.
- Живой CSS `claude-patch/claude.css` (копия лежит в Application Support): скрыты стрелки «назад/вперёд» в заголовке; строка действий под сообщением (копировать, форк, «3 minutes ago») видна всегда.
- После обновления Claude патч слетает — запустить установку снова. После первой установки macOS один раз заново спросит разрешения.
- Бэкап оригинальных app.asar и Info.plist: `~/Library/Application Support/MyClaude/backups/<версия>/`.

## Ручка над полем ввода (`claude-patch/inject.js`)

Живой скрипт, лоадер v6 выполняет его в каждой странице Claude и перечитывает при изменении файла
(копия лежит в `~/Library/Application Support/MyClaude/inject.js`; «Поставить» в PimpMyClaude.app перезаписывает её копией из бандла — править только `claude-patch/inject.js` и пересобирать). Поведение как в ElvisOS:
- Узкая (96 px) едва заметная полоска по центру над полем ввода, ярче при наведении. Тянуть вверх/вниз — высота поля.
- Одинарный клик: поле схлопывается в полоску и обратно (из растянутого — тоже схлопывается).
- Двойной клик: растянуть до потолка окна; ещё раз двойной — обычная высота.
- После отправки поле НЕ сворачивается. Работает и в окнах «Open in new window».
- Escape не останавливает выполнение (глотается, пока на экране нет открытого меню или диалога).
- Команды из меню (см. ниже): `collapse`, `expand`, `scroll` — всем окнам сразу;
  `cashout` — сохраняет последний ответ и черновик, вставляет их в свежий чат.
- Проверка: `probe.js` с `window.__myclaude.status()`.

## Меню на кнопке «Свернуть» (`hammerspoon/claude_minimize_menu.lua`)

Наведи курсор на жёлтую кнопку окна Claude и подержи 0,3 с — всплывёт меню:
🚀 Workflow · Обкэшить · Новый чат · ─ · Свернуть · Развернуть · ─ · Расставить · Показать · Прокрутить.
Workflow (только в приложении) вставляет в поле ввода кикофф воркфлоу и не отправляет; клавиши у пункта нет — ⌘⌥W занят самим Claude.
Свернуть/Развернуть — это поле ввода, не окно. Расставить — столбцами во всю высоту на главном экране (ряды только когда столбцы уже 340 px). Показать — все
окна Claude вперёд. Прокрутить — все чаты к последнему сообщению.

Установка (один раз):
```bash
cp ~/_ElvisProjects/PimpMyClaude/hammerspoon/claude_minimize_menu.lua ~/.hammerspoon/ && echo 'pcall(function() require("claude_minimize_menu") end)' >> ~/.hammerspoon/init.lua && hs -c 'hs.reload()'
```
У пунктов иконки (🚀 💰 💬 ⬇️ ⬆️ ▦ 👀 ⏬) и горячие клавиши, работают только когда окно Claude впереди: Обкэшить ⇧⌘N · Новый чат ⌘N (штатная) · Свернуть ⌥⌘↓ · Развернуть ⌥⌘↑ · Расставить ⌥⌘A · Показать ⌥⌘S · Прокрутить ⌥⌘D. В самом меню подсказки стоят справа серым, в системном порядке ⌥⌘ (его рисует AppKit по `keyEquivalent`, в заголовке пункта клавиши больше нет); поменять — таблица `M.hotkeys` в начале Lua-модуля, в приложении — `MenuModel.entries`. Lua-модуль шлёт команды двумя каналами
(`M.commandChannel = "both"`): `command.json` для лоадера v6 и временно `probe.js` для лоадера v5 (задержка до 2 с).
Приложение шлёт только `command.json` — probe-канал в него не переносили. Проверено живьём 03.09: Прокрутить доводит все окна до низа.

## Темы окон (`claude-patch/themes.json` + inject.js)

В меню на кнопке «Свернуть» два подменю: «Тема окна ▸» — тема только этому окну, «Тема всех окон ▸» — всем сразу;
«Как у Claude» — сброс. Девять тем (фиолетовая, синяя, зелёная, оранжевая, Matrix, Dracula, Tokyo Night, серая,
светлая Arctic). Каталог `claude-patch/themes.json` (6 цветов на тему), CSS из палитры делает inject.js
(урезанный порт генератора ElvisOS) и вешает конструируемой таблицей `adoptedStyleSheets` — `<style>` в `<head>`
нельзя: Claude зеркалит его из главного окна во все окна «Open in new window». Окно помнит тему: главное под
ключом `main`, подчинённые по заголовку (`w:<title>`) в localStorage, плюс sessionStorage на жизнь окна; после
перезапуска Claude цвета возвращаются. Красятся только страницы claude.ai и about:blank (артефакты и браузер — нет).
Режим Claude (тёмный/светлый) не переключается — светлая тема поверх тёмного режима выглядит неровно.
Галка в подменю «Тема окна» у главного окна привязана к заголовку текущего чата и может отставать — сама тема при этом верная. Только в приложении PimpMyClaude.app (Lua-модули тем не знают). Проверено живьём 03.09: четыре окна четырьмя темами.

## ⌘Q не закрывает Claude (`hammerspoon/claude_noquit.lua`)

Пока окно Claude впереди, ⌘Q перехватывается и показывает подсказку; выход только через меню Claude → Quit.
Установка: `cp hammerspoon/claude_noquit.lua ~/.hammerspoon/`, в init.lua `pcall(function() require("claude_noquit") end)`, `hs -c 'hs.reload()'`.
Статус: `hs -c 'return require("claude_noquit").status()'`, снять: `…stop()`.

## План

1. ✅ Ручка, свернуть/развернуть (WF1, `docs/plan-wf1-2026-09-03.md`).
2. ✅ Меню семь пунктов (WF1 + WF2, `docs/plan-wf2-2026-09-03.md`); «3 min ago» — WF2/A2.
3. ✅ Сторож обновлений — в приложении (значок «!» и уведомление «Поставить снова», WF4).
3а. ✅ ⌘Q не закрывает Claude (`claude_noquit.lua`, WF3).
4. ✅ PimpMyClaude.app для команды (Маша, Алла, Денис): установщик, меню и авто-Allow без Hammerspoon,
   подпись Developer ID + нотаризация — WF4, `docs/plan-wf4-2026-09-03.md`; см. раздел «PimpMyClaude.app» выше.
5. ✅ Темы окон — WF5, `docs/plan-wf5-2026-09-03.md`.

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
