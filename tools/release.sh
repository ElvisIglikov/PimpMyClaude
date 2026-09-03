#!/bin/bash
# tools/release.sh — релизная сборка PimpMyClaude.app для раздачи команде:
#   bundle.sh (Developer ID + hardened runtime) → нотаризация у Apple → stapler → dist/PimpMyClaude-<версия>.zip.
# Версия берётся из app/Resources/Info.plist. Результат — один zip, который открывается
# на чужом Маке без «программа повреждена» и без правого клика → «Открыть».
#
# Использование: tools/release.sh
# Переменные: NOTARY_PROFILE — профиль notarytool в keychain (по умолчанию pimpmyclaude),
#             SIGN_ID — чем подписывать, пробрасывается в bundle.sh.
# Профиль заводится один раз (пароль приложения с appleid.apple.com):
#   xcrun notarytool store-credentials pimpmyclaude --apple-id <Apple ID> --team-id F27N4S4NJ4
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
PROFILE="${NOTARY_PROFILE:-pimpmyclaude}"
PLIST="$ROOT/app/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"
APP="$DIST/PimpMyClaude.app"
UPLOAD_ZIP="$DIST/PimpMyClaude.zip"
FINAL_ZIP="$DIST/PimpMyClaude-$VERSION.zip"
SUBMIT_JSON="$DIST/notarytool-submit.json"

die() { echo "release.sh: $*" >&2; exit 1; }

# Достать поле из JSON notarytool: сначала plutil (JSON он читает), иначе грубым sed.
json_field() {
  local key="$1" file="$2" value=""
  value="$(/usr/bin/plutil -extract "$key" raw -o - "$file" 2>/dev/null || true)"
  if [ -z "$value" ]; then
    value="$(sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file" | head -1)"
  fi
  printf '%s' "$value"
}

echo "▶ PimpMyClaude $VERSION ($BUILD) → релиз"
mkdir -p "$DIST"
rm -f "$UPLOAD_ZIP" "$FINAL_ZIP" "$SUBMIT_JSON" "$DIST"/PimpMyClaude-*.zip  # старые релизы не копим: отдать не тот zip — одна опечатка

# 1. Сборка и подпись Developer ID (bundle.sh сам сносит старый $APP).
echo "▶ 1/6 сборка и подпись"
APP_OUT="$APP" "$ROOT/tools/bundle.sh" release
[ -d "$APP" ] || die "bundle.sh не оставил $APP"

# 2. Проверки до отправки: без них Apple вернёт Invalid через 5 минут ожидания.
echo "▶ 2/6 проверка подписи"
SIGINFO="$(codesign -dv --verbose=4 "$APP" 2>&1)"
echo "$SIGINFO" | grep -E 'Authority=|flags=' || true
echo "$SIGINFO" | grep -q 'Authority=Developer ID Application' \
  || die "подпись не Developer ID — нотаризация не примет"
echo "$SIGINFO" | grep -q 'TeamIdentifier=F27N4S4NJ4' \
  || die "подпись не команды F27N4S4NJ4 — чужой Developer ID"
echo "$SIGINFO" | grep -q 'flags=.*runtime' \
  || die "нет hardened runtime (codesign --options runtime) — нотаризация не примет"
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q 'get-task-allow'; then
  die "в entitlements остался get-task-allow — это отладочная подпись"
fi
codesign --verify --strict --deep --verbose=2 "$APP"

# 3. Отправка в Apple. --wait: ждём вердикт, обычно 1–5 минут.
echo "▶ 3/6 нотаризация (профиль keychain: $PROFILE), это несколько минут"
ditto -c -k --keepParent "$APP" "$UPLOAD_ZIP"
set +e
xcrun notarytool submit "$UPLOAD_ZIP" --keychain-profile "$PROFILE" --wait --timeout 30m --output-format json > "$SUBMIT_JSON"
NOTARY_RC=$?
set -e
cat "$SUBMIT_JSON"
SUBMIT_ID="$(json_field id "$SUBMIT_JSON")"
STATUS="$(json_field status "$SUBMIT_JSON")"
if [ "$STATUS" != "Accepted" ]; then
  echo "release.sh: нотаризация не прошла (status=${STATUS:-нет}, код $NOTARY_RC). Лог Apple:" >&2
  if [ -n "$SUBMIT_ID" ]; then
    xcrun notarytool log "$SUBMIT_ID" --keychain-profile "$PROFILE" >&2 || true
  fi
  exit 1
fi
echo "▶ нотаризация принята, submission $SUBMIT_ID"

# 4. Пришить билет к бандлу, чтобы Gatekeeper не ходил в интернет.
echo "▶ 4/6 stapler"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# 5. Итоговый zip уже со сшитым билетом.
echo "▶ 5/6 сборка $FINAL_ZIP"
rm -f "$UPLOAD_ZIP"
ditto -c -k --keepParent "$APP" "$FINAL_ZIP"

# 6. Проверка ровно того, что уедет команде: распаковать zip и спросить Gatekeeper.
echo "▶ 6/6 проверка распакованного zip"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
ditto -x -k "$FINAL_ZIP" "$CHECK_DIR"
CHECK_APP="$CHECK_DIR/PimpMyClaude.app"
[ -d "$CHECK_APP" ] || die "в $FINAL_ZIP нет PimpMyClaude.app"
xcrun stapler validate "$CHECK_APP"
ASSESS="$(spctl --assess --type execute -vv "$CHECK_APP" 2>&1)" || true
echo "$ASSESS"
case "$ASSESS" in
  *accepted*) ;;
  *) die "spctl не принял приложение — команде оно не откроется" ;;
esac
case "$ASSESS" in
  *"Notarized Developer ID"*) ;;
  *) die "spctl не видит нотаризацию (source не Notarized Developer ID)" ;;
esac

echo
echo "✅ готово: $FINAL_ZIP"
echo "   версия $VERSION ($BUILD), submission $SUBMIT_ID, билет пришит, Gatekeeper принял."
echo "   отдать команде вместе с docs/TEAM.md"
