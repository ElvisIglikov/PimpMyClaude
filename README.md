# Pimp My Claude

A macOS menu-bar companion that tunes the **Claude desktop app** for people who keep many Claude windows open at once:
narrow windows, per-window themes and fonts, window layouts, a workflow progress strip, and a few safety switches.

> **Pimp My Claude is an unofficial community tool, not affiliated with or endorsed by Anthropic.**
> "Claude" is a trademark of Anthropic. Use at your own risk.

[Русская версия ниже](#pimp-my-claude--по-русски)

## What it does to Claude.app — read this first

Pimp My Claude changes your installed copy of Claude.app. When you press **«Пропатчить Claude»** ("Patch Claude"; the app UI is in Russian) it:

1. **Backs up** the original `app.asar` and `Info.plist` to
   `~/Library/Application Support/MyClaude/backups/<Claude version>/`.
2. **Appends a small loader** to `Claude.app/Contents/Resources/app.asar`. The loader reads live files from
   `~/Library/Application Support/MyClaude/` (`inject.js`, `claude.css`, `claude.json`, `command.json`, …) and applies
   them to Claude's windows without restarting Claude.
3. **Updates the asar integrity hash** in `Info.plist` and **re-signs Claude.app ad-hoc** (your local signature
   replaces Anthropic's). If the hash or signature step fails, the backup is restored automatically.

Patching quits Claude and reopens it (about 10 s).

**A patched Claude no longer updates itself:** its built-in updater rejects the ad-hoc signature. Pimp My Claude
brings Claude updates instead and patches the new version again (see [Network](#network) below).

**To undo:** menu-bar icon → **Ещё → «Снять патч…»** ("Remove patch…") puts the original `app.asar` and `Info.plist`
back from the backup, but the signature stays ad-hoc — Anthropic's signature does not come back. Only reinstalling
Claude from claude.ai gives you a clean, Anthropic-signed Claude that updates itself. Your settings in
`~/Library/Application Support/MyClaude/` stay until you delete that folder.

### Local trust boundary

Loader v8 applies page code and commands only to the exact `https://claude.ai` Chromium origin, including
pop-out `about:blank` pages that inherit that origin. External browser and HTML-preview pages are excluded.
The loopback HTTP service requires the Claude Origin and loopback Host; native clients use a separate token.
Updating from loader v7 requires patching Claude again, which closes and reopens Claude.

The files in `Application Support/MyClaude` are a local automation channel, not a sandbox against other
programs running as the same macOS user. The Claude bundle is signed ad-hoc by the patcher; this changes
Anthropic's original signing protections. Only install page scripts and configuration you trust.

### Switches that click for you

- **Auto-Allow** is **off by default**. Switched on (menu-bar panel → Settings → «Сам нажимать „Allow once“»), it
  presses the one-time **"Allow once"** in Claude's permission dialogs and never "Always allow", so no permanent rule
  appears. It leaves to you: deletion, publishing and merging (`git push`, deploys), payments, passwords and keys,
  sending data out, file edits, and any request it cannot read with certainty. It does not switch between chats by
  itself. Turn it off with the same toggle.
- **Auto-Trust** presses "Trust this workspace" only for folders inside the projects root you set yourself
  (`"projectsRoot"` in `~/Library/Application Support/MyClaude/claude.json`). With no root set it is **off**.
  This includes newly cloned repositories under that root and their Claude configuration; keep untrusted repositories outside it.

Automatic continuation is off on a fresh installation. **«Авто-продолжение»** in the panel controls it; migration preserves existing page choices until you explicitly change this switch.

### What else it does on its own

- Asks for **Accessibility** (moves and resizes Claude windows, reads their titles) and for **Automation** of your
  browser (to open HTML files from a chat in an already open tab).
- Adds itself to **Login Items** when run from `/Applications` — toggle «Запуск при входе» in the panel.
- **Blocks ⌘Q in Claude by default** — toggle «Блок ⌘Q» in the panel.
- Listens on a local port, **127.0.0.1:47615** (loopback only): the page script uses it to open files from a chat.

## Network

Everything the program sends over the Internet, by source code. It has no analytics, no telemetry and no server of its
own. Every host listed below sees your IP address.

- **Claude update check** — at launch, once a day and when you press the check in the panel. It asks three sources
  every time: Anthropic's official address (`api.anthropic.com` → `downloads.claude.ai`), the third-party mirror
  `claudeapp.agentsmirror.com`, and the third-party GitHub repository `Wangnov/claude-app-mirror` (`api.github.com`,
  `github.com`). The mirrors are not run by Anthropic. **There is no switch for the check or for the mirrors** — to stop
  these requests, quit the program.
- **Claude update download** — when a newer Claude is found, the DMG (a few hundred MB) is downloaded in the background
  from whichever of those sources answers faster. It does not start on an expensive or Low Data Mode network; the
  «Скачать» button in the panel starts it anyway. **There is no switch for the background download.** The download is
  only prepared: Claude is **replaced only when you click** «Обновить Claude». Before that the download is checked —
  code signature with Anthropic's Team ID `Q6L2SF6YDW`, Gatekeeper, bundle id and version; a download that fails is dropped.
- **Updating itself and PimpViewer** — switch **«Обновлять Пимп и Viewer самим»** (panel → «Настройки» → «Обновления»),
  on by default. While it is on, the program asks GitHub for the latest release of its own repository and of PimpViewer:
  at its launch, when Claude starts, and in the background no more often than once in 6 hours. Hosts: `api.github.com`,
  `github.com`, `*.githubusercontent.com` — nothing else, no mirrors. A newer version is downloaded in advance, checked
  (the author's Developer ID signature, Gatekeeper, bundle id, version) and installed on the next launch of the program
  or of Claude. It does not run on an expensive network or when the program is not in the Applications folder.
  **If the repository is private** (for example, your private fork), GitHub answers such a request with a refusal, and the program then runs the
  GitHub CLI installed on your Mac (`gh api …`, `gh release download …`) — that is, **it uses your GitHub account**. No
  `gh` or no access — it quietly does nothing. Switch off — nothing is checked, downloaded or installed.
- **«Запросы команды»** (panel → «Настройки») — when you open this section, the program runs your GitHub CLI (`gh`) and
  reads the open pull requests of your account and its organizations (`api.github.com`, under your GitHub account,
  read-only). You do not open the section — no request. `tools/pimp.py prs` does the same from the terminal.
- **Usage limits inside Claude** — the page script the patch adds asks `claude.ai` (the site Claude itself talks to,
  with your Claude session) for your usage numbers, from the main window, at most once a minute. The answer stays on
  this Mac: it is shown in the window and in the menu-bar panel. There is no separate switch; removing the patch stops it.
- **Voice entry** — only if you run `tools/pimp.py say` and have put a key in place: the dictated phrase and project
  names go to DeepSeek (`api.deepseek.com`, or the HTTPS endpoint you configure). The key travels in a request header;
  HTTP endpoints and server redirects are refused. The app itself never calls it.
- **Links** — «claude.ai/download» and the payment page in «Поддержать автора» open in your browser, only on your click.

Not the Internet: the local port `127.0.0.1:47615` and the channel to PimpViewer work only inside this Mac.

## Features

- Narrow Claude windows (down to 280 pt) with a drag handle above the input field.
- A menu on the window's yellow button: themes, fonts, text size and window frame — per window and per chat.
- 44 built-in themes plus your own; automatic colouring of windows by project.
- Window layouts: arrange all Claude windows in a row, a grid or a saved layout; restore windows after Claude restarts.
- A workflow progress strip and card at the top of the chat.
- A "🚀 Workflow" button that pastes a starter prompt for a structured multi-step workflow.
- Block ⌘Q in Claude (no more quitting by accident).
- `tools/pimp.py` — a command-line "Pimp" channel so Claude itself can open, arrange and close windows
  (see `skills/pimp/SKILL.md`).

## Build from source

Requirements: macOS 13+, Xcode or Command Line Tools (Swift 5.9+), Node 18+ (for tests), Python 3.

```bash
# run all checks (JS page tests, CLI tests, Swift build + tests)
bash tools/test.sh

# build the app with an ad-hoc signature (no Apple Developer ID, no notarization)
SIGN_ID=- bash tools/bundle.sh release
open app/.build/PimpMyClaude.app
```

`SIGN_ID` is the code-signing identity passed to `codesign`; `-` means ad-hoc. An ad-hoc build runs on the Mac that
built it. Gatekeeper will block it on other Macs, and macOS may ask again for Accessibility after every rebuild.
`tools/release.sh` (notarized zip) is for the author's own releases only: it is tied to the author's Developer ID
team and to files that are not in this repository. To build it yourself, use `SIGN_ID=-` as above.

Page script tests: `node --test tests/*.test.mjs`. CLI tests: `python3 -m unittest tests/pimp_cli_test.py`.

Some comments and UI texts are in Russian — the tool was built for a Russian-speaking team.

A few integrations belong to the author's own setup: a voice assistant script, the separate gallery app PimpViewer,
and workflow summaries read from `status.md` files under the projects root. They act only if those files or apps
exist on your Mac; otherwise they stay silent. Code comments refer to internal design notes (`docs/…`) that are not
published.

## Support the author

Coming soon.

## License

GPL-3.0 — see [LICENSE](LICENSE). Copyright © 2026 Elvis Iglikov.

---

# Pimp My Claude — по-русски

Приложение у часов на macOS, которое прокачивает **Claude Desktop** для тех, у кого открыто много окон Claude сразу:
узкие окна, темы и шрифты на каждое окно, раскладки окон, полоска прогресса воркфлоу и несколько выключателей.

> **Pimp My Claude — неофициальный инструмент сообщества, не связан с Anthropic и не одобрен ею.**
> «Claude» — товарный знак Anthropic. Пользуйтесь на свой риск.

## Что программа делает с Claude.app — прочитайте сначала

Кнопка **«Пропатчить Claude»**:

1. **Делает бэкап** исходных `app.asar` и `Info.plist` в `~/Library/Application Support/MyClaude/backups/<версия Claude>/`.
2. **Дописывает небольшой лоадер** в `Claude.app/Contents/Resources/app.asar`. Лоадер читает живые файлы из
   `~/Library/Application Support/MyClaude/` и применяет их к окнам Claude без перезапуска.
3. **Пересчитывает хэш целостности** в `Info.plist` и **переподписывает Claude.app ad-hoc** (ваша локальная подпись
   вместо подписи Anthropic). Сорвался хэш или подпись — бэкап возвращается сам.

Патч закрывает Claude и открывает его снова (~10 с).

**Пропатченный Claude сам больше не обновляется:** его встроенное обновление не принимает подпись ad-hoc. Обновления
Claude приносит Pimp My Claude и патчит новую версию заново (см. [Сеть](#сеть) ниже).

**Как снять:** значок у часов → **Ещё → «Снять патч…»** — исходные `app.asar` и `Info.plist` возвращаются из бэкапа, но
подпись остаётся ad-hoc: подпись Anthropic не возвращается. Чистый Claude с подписью Anthropic, который сам обновляется,
даёт только переустановка с claude.ai. Настройки в `~/Library/Application Support/MyClaude/` остаются, пока вы сами
не удалите папку.

### Граница доверия на этом Маке

Лоадер v8 применяет код страницы и команды только к точному Chromium origin `https://claude.ai`, включая
вынесенные `about:blank` с унаследованным origin. Встроенный браузер с чужими сайтами и HTML-превью исключены.
Локальный HTTP-сервис требует Origin Claude и loopback Host; нативные клиенты используют отдельный токен.
Переход с лоадера v7 требует снова пропатчить Claude; это закроет и откроет Claude.

Файлы в `Application Support/MyClaude` — локальный канал автоматизации, а не изоляция от других программ
той же учётной записи macOS. Патчер подписывает Claude ad-hoc, меняя исходную защиту подписи Anthropic.
Код страницы и настройки должны приходить из доверенного источника.

### Выключатели, которые жмут за вас

- **Авто-Allow** по умолчанию **выключен**. Включённый (панель у часов → Настройки → «Сам нажимать „Allow once“»), он
  жмёт разовое **«Allow once»** в диалогах разрешений Claude и никогда «Always allow» — постоянных правил не появляется.
  Вам остаются: удаление, выкладка и слияние (`git push`, деплой), платежи, пароли и ключи, отправка данных наружу,
  правка файлов и любой запрос, который он не смог прочитать наверняка. Сам по чатам он не ходит. Выключается тем же
  тумблером.
- **Авто-Trust** жмёт «Trust this workspace» только для папок внутри корня проектов, который вы задали сами
  (`"projectsRoot"` в `~/Library/Application Support/MyClaude/claude.json`). Корня нет — **выключен**.
  Это относится и к новым скачанным репозиториям с их настройками Claude; недоверенные репозитории храните вне этого корня.

Автопродолжение в чистой установке выключено. Им управляет **«Авто-продолжение»** в панели; миграция сохраняет прежний выбор страниц до явного изменения этого переключателя.

### Что ещё программа делает сама

- Просит **Универсальный доступ** (двигает окна Claude, читает их заголовки) и **Автоматизацию** браузера (открыть
  HTML-файл из чата в уже открытой вкладке).
- Добавляет себя в **Объекты входа**, если запущена из `/Applications`, — выключатель «Запуск при входе» в панели.
- **Блокирует ⌘Q в Claude по умолчанию** — выключатель «Блок ⌘Q» в панели.
- Слушает локальный порт **127.0.0.1:47615** (только этот Мак): через него страница открывает файлы из чата.

## Сеть

Всё, что программа отправляет в интернет, — по коду. Аналитики, телеметрии и своего сервера у неё нет. Каждый адрес
ниже видит ваш IP.

- **Проверка обновлений Claude** — на запуске, раз в сутки и по кнопке проверки в панели. Каждый раз спрашиваются три
  источника: официальный адрес Anthropic (`api.anthropic.com` → `downloads.claude.ai`), стороннее зеркало
  `claudeapp.agentsmirror.com` и сторонний репозиторий GitHub `Wangnov/claude-app-mirror` (`api.github.com`,
  `github.com`). Зеркала — не Anthropic. **Выключателя проверки и выключателя зеркал нет**: чтобы этих запросов не было,
  закройте программу.
- **Загрузка обновления Claude** — нашлась версия новее — образ DMG (несколько сотен МБ) качается в фоне с того из этих
  источников, который отвечает быстрее. В дорогой сети и в режиме экономии трафика сама не начинается; кнопка «Скачать»
  в панели запускает её всё равно. **Выключателя фоновой загрузки нет.** Загрузка только готовит обновление: Claude
  **заменяется только по вашему клику** «Обновить Claude». До этого скачанное проверяется — подпись с Team ID Anthropic
  `Q6L2SF6YDW`, Gatekeeper, bundle id и версия; не прошло проверку — выбрасывается.
- **Обновление самой программы и PimpViewer** — переключатель **«Обновлять Пимп и Viewer самим»** (панель у часов →
  «Настройки» → «Обновления»), по умолчанию включён. Пока он включён, программа спрашивает у GitHub последний выпуск
  своего репозитория и репозитория PimpViewer: на своём запуске, на запуске Claude и в фоне не чаще раза в 6 часов.
  Адреса: `api.github.com`, `github.com`, `*.githubusercontent.com` — больше никуда, зеркал нет. Версия новее
  скачивается заранее, проверяется (подпись Developer ID автора, Gatekeeper, bundle id, версия) и встаёт при следующем
  запуске программы или Claude. В дорогой сети и когда программа лежит не в «Программах», не работает.
  **Если репозиторий закрыт** (например, ваш закрытый форк), GitHub на такой запрос отвечает отказом, и тогда программа запускает GitHub CLI с вашего
  Мака (`gh api …`, `gh release download …`) — то есть **ходит под вашей учётной записью GitHub**. Нет `gh` или нет
  доступа — тихо ничего не делает. Переключатель выключен — ничего не проверяется, не скачивается и не ставится.
- **«Запросы команды»** (панель → «Настройки») — когда вы открываете этот раздел, программа запускает ваш GitHub CLI
  (`gh`) и читает открытые запросы на изменения вашей учётной записи и её организаций (`api.github.com`, под вашей
  учётной записью GitHub, только чтение). Раздел не открывали — запроса нет. То же делает `tools/pimp.py prs` из терминала.
- **Лимиты внутри Claude** — код страницы, который добавляет патч, спрашивает у `claude.ai` (сайт, с которым работает
  сам Claude, с вашей сессией Claude) цифры вашего расхода: из главного окна, не чаще раза в минуту. Ответ остаётся на
  этом Маке: его показывают окно и панель у часов. Отдельного выключателя нет; снятый патч это прекращает.
- **Голосовой вход** — только если вы сами запускаете `tools/pimp.py say` и положили ключ: продиктованная фраза и имена
  проектов уходят в DeepSeek (`api.deepseek.com` либо указанный вами HTTPS-адрес). Ключ передаётся заголовком; HTTP и
  перенаправления сервера запрещены. Само приложение его не вызывает.
- **Ссылки** — «claude.ai/download» и страница оплаты в окне «Поддержать автора» открываются в вашем браузере, только
  по вашему клику.

Не интернет: локальный порт `127.0.0.1:47615` и канал к PimpViewer работают только внутри этого Мака.

## Возможности

- Узкие окна Claude (до 280 pt) и ручка над полем ввода.
- Меню на жёлтой кнопке окна: темы, шрифты, размер текста и рамка — на каждое окно и чат.
- 44 темы и свои; автопокраска окон по проекту.
- Раскладки: расставить окна лентой, сеткой или по сохранённой раскладке; вернуть окна после перезапуска Claude.
- Полоска и карточка прогресса воркфлоу вверху чата.
- Кнопка «🚀 Workflow» — вставляет стартовый текст пошагового воркфлоу.
- Блок ⌘Q в Claude.
- `tools/pimp.py` — канал «Пимп» из командной строки: сам Claude может открывать, расставлять и закрывать окна
  (см. `skills/pimp/SKILL.md`).

## Сборка из исходников

Нужно: macOS 13+, Xcode или Command Line Tools (Swift 5.9+), Node 18+ (для тестов), Python 3.

```bash
bash tools/test.sh                      # все проверки
SIGN_ID=- bash tools/bundle.sh release  # сборка с подписью ad-hoc, без Developer ID и нотаризации
open app/.build/PimpMyClaude.app
```

`SIGN_ID=-` — подпись ad-hoc: сборка работает на том Маке, где собрана; на чужих её остановит Gatekeeper, а macOS может
заново спрашивать Универсальный доступ после каждой пересборки. `tools/release.sh` (нотаризованный zip) — только для
релизов автора: он привязан к команде Developer ID автора и к файлам, которых нет в этом репозитории. Для себя собирайте
с `SIGN_ID=-`, как выше.

Несколько интеграций — из личной настройки автора: скрипт голосового помощника, отдельная галерея PimpViewer и сводки
воркфлоу из файлов `status.md` под корнем проектов. Они срабатывают, только если такие файлы или приложения есть на
вашем Маке, иначе молчат. Комментарии в коде ссылаются на внутренние заметки о дизайне (`docs/…`) — они не публикуются.

## Поддержать автора

Скоро.

## Лицензия

GPL-3.0 — см. [LICENSE](LICENSE). © 2026 Elvis Iglikov.
