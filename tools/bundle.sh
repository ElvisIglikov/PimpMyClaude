#!/bin/bash
# Собирает app/.build/PimpMyClaude.app из SwiftPM-пакета и подписывает Developer ID (стабильный cdhash → Accessibility просится один раз).
# Использование: tools/bundle.sh [debug|release]   Переменные: SIGN_ID (по умолчанию Developer ID Application: ELVIS IGLIKOV (F27N4S4NJ4))
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${1:-release}"
SIGN_ID="${SIGN_ID:-Developer ID Application: ELVIS IGLIKOV (F27N4S4NJ4)}"
cd "$ROOT/app"
swift build -c "$CONF" 2>&1 | tail -3
BIN="$(swift build -c "$CONF" --show-bin-path)/PimpMyClaude"
APP="$ROOT/app/.build/PimpMyClaude.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PimpMyClaude"
cp "$ROOT/app/Resources/Info.plist" "$APP/Contents/Info.plist"
for f in "$ROOT/claude-patch/inject.js" "$ROOT/claude-patch/claude.css" "$ROOT/claude-patch/entitlements.plist"; do
  [ -f "$f" ] && cp "$f" "$APP/Contents/Resources/"
done
codesign --force --options runtime --timestamp \
  --entitlements "$ROOT/app/Resources/PimpMyClaude.entitlements" \
  --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "OK: $APP"
