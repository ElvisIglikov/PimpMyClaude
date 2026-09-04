# ⚪PimpMyClaude — памятка агенту (читать первой, до README)

Обновлено 04.09.2026 14:00. Это файл-передача: новый чат открывает папку проекта и продолжает отсюда, ничего не
додумывая. Общие правила общения и воркфлоу 👾 Элвиса — `/Users/elvis/_ElvisProjects/SkilZZZ/AGENTS.md` и
`WORKFLOW.md` (прочитать). Задачник 🟣Trelvis: слаг проекта `other` (⚪ Другое); задачи регистрировать через
`python3 /Users/elvis/_ElvisProjects/Trelvis/trelvis.py`, актор `fable`.

## Что это

Прокачка Claude Desktop (macOS) для 👾 Элвиса и его команды (Маша, Алла, Денис, Саша Костина, Эрик, Тимон):
узкие окна, ручка над полем ввода, меню на жёлтой кнопке окна, темы/шрифты/размер/рамка на каждое окно и чат,
полоса прогресса воркфлоу, авто-Allow, блок ⌘Q, кнопка «🚀 Workflow» (вставляет стартовый текст подхода Элвиса).
Бывший MyClaude (переименован 03.09.2026). GitHub `ElvisIglikov/PimpMyClaude`, ветка `main`.

Раздаётся как **PimpMyClaude.app** (Swift/AppKit, Developer ID «ELVIS IGLIKOV (F27N4S4NJ4)», нотаризация через
профиль keychain `pimpmyclaude`). Текущий релиз **1.3.0 (7)**, zip `dist/PimpMyClaude-1.3.0.zip` (копия на рабочем
столе Элвиса вместе с `docs/TEAM.md` — инструкция команде). У Элвиса приложение стоит в `/Applications`, старые
Hammerspoon-модули из его `init.lua` сняты 03.09.

## Как устроено (три слоя)

1. **Патч Claude.app** — `claude-patch/patch-claude.mjs` (Node, дев-инструмент) и его порт `app/Sources/Patcher`
   (Swift, боевой): в `app.asar` дописывается **лоадер v6** (строка `LOADER` в mjs / `Loader.swift`), пересчёт
   `ElectronAsarIntegrity`, переподпись ad-hoc, бэкап в `~/Library/Application Support/MyClaude/backups/<версия>/`.
   Лоадер НЕ ТРОГАТЬ без крайней нужды: его смена = перепатч Claude у всей команды («Поставить снова»).
   Папка `~/Library/Application Support/MyClaude/` — так и называется (лоадер смотрит туда), не переименовывать.
2. **Живые файлы в Application Support/MyClaude/**, лоадер перечитывает их по mtime без перезапуска Claude:
   `claude.json` (minWindowWidth, sidePadding, projectsRoot), `claude.css` (user-стили, `insertCSS`), **`inject.js`**
   (исполняется в каждой странице Claude при dom-ready и при каждом изменении файла; обязан быть идемпотентным —
   `window.__myclaude.dispose()`), `command.json` (команды `{id, action, at, …}`; лоадер читает раз в 500 мс и берёт
   ПОСЛЕДНЮЮ запись — отсюда очередь в Swift), `probe.js` → `probe-result.json` (любой JS во все страницы, ответ в файл —
   главный инструмент гейта), `status.json` (диагностика лоадера, имя занято), `themes.json`, `my-themes.json`,
   `installed.json`, `workflow/` (комплект KICKOFF.md + WORKFLOW.md).
   Источник правды — `claude-patch/` в репозитории; «Поставить» и `bundle.sh` копируют оттуда. Живой `inject.js`
   руками не править — только репозиторный, потом `cp` в Application Support (лоадер подхватит).
3. **PimpMyClaude.app** — `app/` (SwiftPM, macOS 13+, Swift 5 mode). Таргеты: `Patcher`, `ClaudeAX`
   (AX-модуль: авто-Allow, меню на кнопке, Carbon-хоткеи, ⌘Q, Расставить/Показать, темы/шрифты/размер/рамка,
   автопокраска, StatusFeed, WorkflowKit, очередь `CommandChannel`), `PimpMyClaude` (меню-бар, окно настройки
   разрешений, уведомления, Поставить/Снять/Статус). Протокол `ClaudeAXControlling` в `ClaudeAX.swift` — контракт
   между модулями, менять только осознанно.

## Контракты (побайтно, страница и Swift обязаны совпадать)

- `theme`: `{"id","action":"theme","at","scope":"window"|"all","title":<AX-заголовок окна>,"preview":true|false?,
  "theme":{id,name,type,palette{accent,background,foreground,sidebar,panel,muted}}|null?,
  "font":{id,family,mono}|null?, "size":{answer?,question?}|null?, "frame":true|null?}` — поле есть → слой меняется,
  нет → не трогать, null → сброс; `preview:true` — только на экран, `preview:false` без слоёв — конец примерки.
- `workflow`: `{…,"scope":"window","title","text"}` — вставить текст в поле ввода, не отправлять.
- `status`: `{…,"scope":"all","projects":[{name,text}]}` — сводки status.md проектов для подсказки полоски.
- Старые: `cashout` (title), `collapse`, `expand`, `scroll`.
- Хранилище тем на странице: localStorage `myclaude-themes-v1` — карта `{ключ: {theme, font, size, frame}}`, ключи
  `chat:<заголовок>` (тема на чат), `main` (главное окно), `*` (всем); sessionStorage `myclaude-theme-v1` по окну
  (`main` / `w:<title>`). Приоритет по слою: `chat:` → session → `main` → `*`. Заглушки заголовка («Claude», «New chat»)
  в `chat:` не пишутся. Старые форматы (WF5 тема на верхнем уровне, `w:`-ключи) читаются и переносятся.
- Тема = `adoptedStyleSheets` (НЕ `<style>`: Claude зеркалит `<style>` главного окна в попапы). Красятся только
  страницы `claude.ai` и `about:blank` (окна «Open in new window»), артефакты/браузер — нет.

## Сборка, гейт, релиз

- `cd app && swift build && swift test` (49 тестов). JS: `node --check claude-patch/inject.js` + скретч-тесты в
  scratchpad сессии (`theme-store-test.mjs`, `theme-css-test.mjs`, `progress-test.mjs`, `progress-dom-test.mjs`,
  `workflow-insert-test.mjs`) — они не в репозитории; новый чат их не найдёт, при необходимости просить агента написать.
- `tools/bundle.sh release` → `app/.build/PimpMyClaude.app` (Developer ID). **Подмена без простоя:** сначала bundle,
  потом `pkill -f PimpMyClaude.app/Contents/MacOS; rm -rf /Applications/PimpMyClaude.app; ditto …; open …` — Элвис
  дважды ловил «минус не работает», когда приложение лежало во время сборки.
- `tools/release.sh` → нотаризация (профиль `pimpmyclaude`) → `dist/PimpMyClaude-<версия>.zip`; версию поднять в
  `app/Resources/Info.plist` (CFBundleShortVersionString + CFBundleVersion) до запуска.
- Живой гейт без клика: `probe.js` → `window.__myclaude.status()` (поля theme/font/size/frame/progress/statusFeed/
  chatKey/sessionKey/preview/workflow), команды руками в `command.json` (id обязан быть новым), скриншот
  `screencapture -x -R…`. Мышью водить через Hammerspoon (`hs -c`) можно, но `hs` иногда виснет — таймаут.
- **«Поставить» в приложении закрывает Claude** и с ним чат оркестратора — на Маке Элвиса делает он сам; патч у него
  уже стоит (v6). Живой «Снять → Поставить» новым Swift-патчером Элвис ещё НЕ делал (проверено только на копии
  Claude.app и старым mjs-ридером).
- Git: коммит с явным автором (`GIT_AUTHOR_NAME=Elvis GIT_AUTHOR_EMAIL=elvis@M4.local …`, иначе «Author identity
  unknown»), в конце сообщения `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Ветка на воркфлоу
  (`wfN`) + тег `wfN-start`, слияние в `main` `--no-ff`.

## Решения, о которых легко забыть

- Модели (слово Элвиса 03.09 18:00): оркестратор Fable 5.1 high; ВСЕ субагенты (критик, кодинг, verify) — Opus 5 max;
  Fable как субагент только в крайнем случае с пометкой в run-файле.
- Хоткеи только Carbon `RegisterEventHotKey` (NSEvent-монитор не глотает ⌘Q и просит Input Monitoring); в меню
  клавиши через `keyEquivalent` (AppKit рисует справа серым, порядок системный ⌥⌘). ⌘⌥W — клавиша Claude, не наша.
- `NSApp.activate(ignoringOtherApps: true)` перед `popUp` обязателен (кооперативный activate на macOS 14+ не работает —
  подменю закрывалось).
- Разрешений у приложения два: Accessibility и «Управление приложениями» (App Management); уведомления — третье,
  необязательное. Dev-сборки подписывать Developer ID с первого билда (стабильный DR → AX просится один раз).
- Претензии к цветам решались так: палитры «заметные» (фон явно окрашен, S 45–60 %), акцент в полосе контраста
  4,5–6 (тёмная) / 4,5–7 (светлая); `--cds-*` семантические переменные обязательны (попапы красятся через
  `bg-surface-1`); блок Epitaxy (Claude Code) обязателен для поля ввода.
- Полоска прогресса читает строку состояния ПОСЛЕДНЕГО ответа (`WF N из M · P%`, значки 💭✋✅🛑) — формат из
  SkilZZZ/AGENTS.md п. 5; окна-попапы — через текст всего окна (приметы ответов там не совпадают). Сегменты —
  пул узлов с переходами; подсказка — по клику на сегмент.
- Автопокраска не ставит галки тем и стирает старые; окна с одинаковым заголовком получают один цвет (адресация по
  `document.title`); «Случайно» режим берёт из памяти приложения (по умолчанию тёмный).
- Откат `themeScope` (выключатель темы-на-чат) снят: страница файлов не читает, тащить флаг = перепатч.

## История воркфлоу (планы `docs/plan-wf*.md`, состояние `docs/run-wf*.json`, сводка `docs/status.md`)

WF1–3 (03.09) ручка/меню/⌘Q в Hammerspoon → WF4 PimpMyClaude.app 1.0.0 → WF5 темы окон 1.1.0 → WF6 24 темы,
шрифты, «Мои темы» → WF7 полоска → WF8 предпросмотр → WF9 полоска v2, кнопка Workflow, клавиши, тема на чат,
категории шрифтов 1.2.0 → WF10 автопокраска → WF11 плавная полоска → WF12 размер, рамка, клик по сегменту 1.3.0.
Все 12 закрыты (`docs/status.md`: 12 из 12). Незавершённых воркфлоу и сторожей-кронов нет.

## Открытые хвосты (не сделано, задач в Trelvis на них нет — завести при старте)

- Живой «Снять → Поставить» Swift-патчером на Маке Элвиса и на чистом пользователе macOS; отзыв первого из команды.
- Поведение обновлений Claude (Squirrel/ShipIt) после ad-hoc подписи — не проверено; TEAM.md обещает «Поставить снова».
- Сброс только одной половины размера («Как у Claude» снимает обе); галка окна не видит запись «всем окнам»
  (тема/шрифт/размер/рамка); тумблер рамки живёт только в «Тема ▸» (нет каталога тем — нет тумблера).
- StatusFeed: подсказка полоски со сводками только там, где есть `~/_ElvisProjects` (`projectsRoot` в claude.json);
  при 9+ проектах хвост списка по алфавиту отбрасывается (32 КБ).
- «Ещё раз» после «Случайно» повторяет схему (память), первое «Случайно» после автопокраски — тёмное.
- Lua-модули в `hammerspoon/` — только источник логики, тем/полоски не знают; README про них честно говорит.
- Скретч-тесты JS живут вне репозитория (см. выше).
- Задачи в Trelvis #5312–#5343 закрыты агентом, ждут проверки Элвиса.

## Кто чем владеет при параллельных батчах (правило одного писателя)

`claude-patch/inject.js` — всегда ОДИН агент на волну (3600 строк, разделы 2а темы, 2б полоска, 12 «Обкэшить»,
12а Workflow, 16 подписки). Swift — второй агент; `themes.json`, `bundle.sh` — у Swift-батча. Контракт команды
фиксируется в плане до старта, менять — только на гейте.
