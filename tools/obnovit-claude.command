#!/bin/bash
# Обновление Claude целиком, одним двойным кликом (задача #7078, находка #7079).
#
# ПОЧЕМУ ТАК. Claude обновление находит и скачивает, но ставить отказывается:
# Squirrel сверяет подпись нового бандла с требованием, снятым с работающего, а наш
# патч переподписан ad-hoc. В логе — «Code signature … did not pass validation»,
# в меню Claude — «Last Update Attempt Failed». Поэтому порядок только такой:
# снять патч → обновить → поставить патч обратно → вернуть окна.
#
# Скрипт кликает за тебя в меню Пимпа и в меню Claude. Ничего не вводит и не удаляет.
# Прервать — Ctrl+C или закрыть окно.
set -u
PIMP_REPO="/Users/elvis/_ElvisProjects/PimpMyClaude"
ASAR="/Applications/Claude.app/Contents/Resources/app.asar"
PLIST="/Applications/Claude.app/Contents/Info.plist"

version() { /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST" 2>/dev/null; }
loader()  { LC_ALL=C grep -a -o -m1 -E '\[MyClaude:v[0-9]+:start\]' "$ASAR" 2>/dev/null | grep -o '[0-9]\+'; }

pimp_click() { # $1 — пункт меню Пимпа, $2 — кнопка в окошке (или пусто)
    osascript <<EOF >/dev/null 2>&1
tell application "System Events" to tell process "PimpMyClaude"
  click menu bar item 1 of menu bar 1
  delay 1
  click menu item "$1" of menu 1 of menu bar item 1 of menu bar 1
end tell
EOF
    [ -n "${2:-}" ] || return 0
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        sleep 1
        osascript -e "tell application \"System Events\" to tell process \"PimpMyClaude\" to click button \"$2\" of window 1" >/dev/null 2>&1 && return 0
    done
    return 1
}

NOWLOADER="$(loader)"
echo "⚪ Сейчас: Claude $(version), лоадер ${NOWLOADER:-нет}"
pgrep -f "PimpMyClaude.app/Contents/MacOS" >/dev/null || { echo "Открываю Пимп…"; open -a PimpMyClaude; sleep 4; }

echo
echo "1/4 · Снимаю патч (Claude закроется и откроется чистым)…"
pimp_click "Снять…" "Снять" || { echo "⛔ Не нажалось. Сделай руками: Пимп у часов → «Снять…»."; read -r -p "Enter"; exit 1; }
for _ in $(seq 1 60); do sleep 2; [ -z "$(loader)" ] && break; done
if [ -n "$(loader)" ]; then echo "⛔ Патч всё ещё на месте — дальше не иду."; read -r -p "Enter"; exit 1; fi
echo "   ✅ Патч снят, подпись Claude снова родная."
pgrep -f "Claude.app/Contents/MacOS" >/dev/null || { open -a Claude; sleep 8; }

echo
echo "2/4 · Прошу Claude проверить обновления…"
WAS="$(version)"
osascript >/dev/null 2>&1 <<'EOF'
tell application "System Events" to tell process "Claude"
  set frontmost to true
  delay 1
  click menu item "Check for Updates…" of menu 1 of menu bar item 2 of menu bar 1
end tell
EOF
echo "   Жду обновление до 20 минут. Claude может сам предложить перезапуск — соглашайся."
for _ in $(seq 1 120); do
    sleep 10
    NOW="$(version)"
    [ -n "$NOW" ] && [ "$NOW" != "$WAS" ] && break
done
NOW="$(version)"
if [ "$NOW" = "$WAS" ]; then
    echo "   ⚠️ Версия не поменялась ($NOW). Возможно, обновления и правда нет."
    echo "   Ставлю патч обратно — Claude останется рабочим."
else
    echo "   ✅ Claude обновился: $WAS → $NOW"
fi

echo
echo "3/4 · Ставлю патч обратно…"
pgrep -f "Claude.app/Contents/MacOS" >/dev/null || { open -a Claude; sleep 8; }
pimp_click "Поставить…" "Поставить" || { echo "⛔ Не нажалось. Сделай руками: Пимп у часов → «Поставить…»."; read -r -p "Enter"; exit 1; }
for _ in $(seq 1 60); do sleep 2; [ -n "$(loader)" ] && break; done
[ -n "$(loader)" ] && echo "   ✅ Патч на месте (лоадер $(loader))." || echo "   ⚠️ Патч не встал — открой Пимп и нажми «Поставить…»."

echo
echo "4/4 · Возвращаю окна на места…"
sleep 5
bash "/Users/elvis/_ElvisProjects/_Не удалять/вернуть окна.command" </dev/null

echo
echo "Готово. Claude $(version), лоадер $(loader)."
read -r -p "Enter — закрыть."
