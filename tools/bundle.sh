#!/bin/bash
# Собирает PimpMyClaude.app из SwiftPM-пакета и подписывает Developer ID (стабильный cdhash → Accessibility просится один раз).
# Использование: tools/bundle.sh [debug|release]
# Переменные: APP_OUT — куда класть .app (по умолчанию app/.build/PimpMyClaude.app),
#             PIMP_PREBUILT — готовый бинарник (tools/m1.sh release), тогда здесь без компиляции,
#             SIGN_ID — чем подписывать (по умолчанию Developer ID Application: ELVIS IGLIKOV (F27N4S4NJ4)).
# Версия берётся из app/Resources/Info.plist; в конце печатает VERSION=/BUILD=/APP= — это читает tools/release.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${1:-release}"
SIGN_ID="${SIGN_ID:-Developer ID Application: ELVIS IGLIKOV (F27N4S4NJ4)}"
PLIST="$ROOT/app/Resources/Info.plist"
ICON="$ROOT/app/Resources/AppIcon.icns"
APP="${APP_OUT:-$ROOT/app/.build/PimpMyClaude.app}"
# Ниже rm -rf "$APP": пусть это будет только бандл, а не чей-то домашний каталог.
case "$APP" in
  *.app) ;;
  *) echo "bundle.sh: APP_OUT должен кончаться на .app, а это «${APP}»" >&2; exit 1 ;;
esac
# Ниже cd в app/ — относительный путь должен остаться относительным каталога вызова.
case "$APP" in /*) ;; *) APP="$PWD/$APP" ;; esac
case "${PIMP_PREBUILT:-}" in ""|/*) ;; *) PIMP_PREBUILT="$PWD/$PIMP_PREBUILT" ;; esac
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"

# Иконка лежит в репозитории; без неё zip в Finder выглядит как чужой файл.
# Нет — рисуем тем же генератором, что и лежащую (WF87, app/Resources/make-appicon.swift).
if [ ! -f "$ICON" ]; then
  echo "bundle.sh: рисую $ICON"
  TMP="$(mktemp -d)"
  swift "$ROOT/app/Resources/make-appicon.swift" "$TMP/AppIcon.iconset"
  iconutil -c icns "$TMP/AppIcon.iconset" -o "$ICON"
  rm -rf "$TMP"
fi

cd "$ROOT/app"
# PIMP_PREBUILT — бинарник, собранный на сборочном Маке (tools/m1.sh release): здесь только упаковка и подпись.
if [ -n "${PIMP_PREBUILT:-}" ]; then
  BIN="$PIMP_PREBUILT"
  [ -x "$BIN" ] || { echo "bundle.sh: нет бинарника $BIN" >&2; exit 1; }
else
  swift build -c "$CONF" 2>&1 | tail -3
  BIN="$(swift build -c "$CONF" --show-bin-path)/PimpMyClaude"
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PimpMyClaude"
cp "$PLIST" "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
# Умолчание «Поддержать автора» (WF108): DonateStore ищет его Bundle.main → Contents/Resources/donate.json.
cp "$ROOT/app/Resources/donate.json" "$APP/Contents/Resources/donate.json"
# Фото автора для окна «Поддержать автора» (WF227): DonatePhoto ищет его Bundle.main → Contents/Resources/ElvisPhoto.jpg.
cp "$ROOT/app/Resources/ElvisPhoto.jpg" "$APP/Contents/Resources/ElvisPhoto.jpg"
for f in "$ROOT/claude-patch/inject.js" "$ROOT/claude-patch/claude.css" "$ROOT/claude-patch/themes.json" "$ROOT/claude-patch/entitlements.plist"; do
  if [ ! -f "$f" ]; then echo "bundle.sh: нет ресурса $f" >&2; exit 1; fi
  cp "$f" "$APP/Contents/Resources/"
done
# Комплект воркфлоу: пункт меню «Workflow» кладёт его в Application Support и вставляет KICKOFF.md в чат.
KIT="$ROOT/resources/workflow-kit"
for f in "$KIT/WORKFLOW.md" "$KIT/STYLE.md" "$KIT/KICKOFF.md"; do
  if [ ! -f "$f" ]; then echo "bundle.sh: нет ресурса $f" >&2; exit 1; fi
done
cp -R "$KIT" "$APP/Contents/Resources/workflow-kit"
# Комплект Рика (WF216): снимок публичного RickBoss, RickKit.swift копирует его в <projectsRoot>/Rick.
# cp -R -p — исполняемые биты install.sh и tools/*.py обязаны доехать; без сети, скрипты здесь не запускаются.
RICK="$ROOT/resources/rick-kit"
for f in "$RICK/AGENTS.md" "$RICK/CLAUDE.md" "$RICK/README.md" "$RICK/install.sh" "$RICK/.claude/settings.json"; do
  if [ ! -f "$f" ]; then echo "bundle.sh: нет ресурса $f" >&2; exit 1; fi
done
[ -x "$RICK/install.sh" ] || { echo "bundle.sh: $RICK/install.sh потерял исполняемый бит" >&2; exit 1; }
cp -R -p "$RICK" "$APP/Contents/Resources/rick-kit"
codesign --force --options runtime --timestamp \
  --entitlements "$ROOT/app/Resources/PimpMyClaude.entitlements" \
  --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "OK: PimpMyClaude $VERSION ($BUILD)"
echo "VERSION=$VERSION"
echo "BUILD=$BUILD"
echo "APP=$APP"
