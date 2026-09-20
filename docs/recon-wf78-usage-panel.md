# Разведка WF78 — панель лимитов и кружок контекста (снято живьём 21.09.2026 00:05, Claude Desktop у Элвиса)

**Кружок** (над полем ввода, справа): `button[data-cds="Button"][aria-haspopup="dialog"][aria-label^="Usage:"]`,
`aria-label="Usage: Context 324.7k / 1M (32%), Weekly · all models: 77%, Resets Fri 8:00 AM"`, при открытой панели
`aria-expanded="true"`, `data-popup-open`, `aria-controls=<id панели>`. Есть в главном окне и в каждом попапе.

**Панель**: `div[role="dialog"][data-cds="Popover"][data-side="top"][data-align="end"]`, id = `aria-controls` кружка.
Внутри `div.flex.flex-col.py-sm`:

1. Строка контекста — `button[aria-expanded]` с тремя детьми: `span.text-footnote.text-muted` «Context window»,
   `span.text-footnote.text-muted.tabular-nums.ml-auto` «324.7k / 1M (32%)», `span[data-cds="Icon"]` (шеврон). Под ней
   `div[data-cds="StackedMeter"][role="img"][aria-label^="Context window: Messages: …"]` — цветные сегменты (НЕ трогать).
2. Разделитель `div.h-px.bg-alpha-2`.
3. Шапка лимитов: `span.text-footnote.text-muted` «Plan usage limits · Max (20x)» и ссылка
   `a[href="/settings/usage"][aria-label="View usage in Settings"]`.
4. Три блока лимитов, каждый `div.flex.flex-col`: строка `div.flex.items-baseline.justify-between` = подпись
   `span[id].text-footnote.text-primary.truncate` («5-hour limit» / «Weekly · all models» / «Weekly · Fable») + правая
   группа `span.flex.items-baseline.gap-1.5.text-muted.tabular-nums` из ДВУХ span: «Resets in 58 min» | «Resets Fri 8:00 AM»
   и «65%»; под строкой полоса `div[role="progressbar"][aria-labelledby=<id подписи>][aria-valuenow="65"]` с заливкой
   `div.h-full.bg-fill-accent` (у недельных при 77 % — `bg-fill-warning`, жёлтая) и `style="width: 65%"`.
5. Разделитель, затем `button.text-footnote.text-secondary` «See detailed breakdown».

Панель — React: тексты перерисовываются при каждом обновлении чисел, узлы пересоздаются при каждом открытии.
Формы времени, виденные живьём: «Resets in 4 hr 9 min», «Resets in 59 min», «Resets Fri 8:00 AM».

**Имя аккаунта**: только в ГЛАВНОМ окне, `button[data-testid="user-menu-button"]`, текст «EElvisnya·Max» (буква аватара +
имя + «·» + тариф) — нужное имя «Elvisnya». В попапах этой кнопки нет; кнопки нет и при свёрнутой боковой панели.
`localStorage` у попапа общий с главным окном (about:blank унаследовал origin claude.ai).

**Режим чтения** (автосвёртка/свёрнутое поле ввода, раздел «Автосвёртка (#6666)» и угловой фейд #6656/#6658 в `inject.js`):
кружок живёт в нижней строке поля ввода и прячется вместе с ним.
