#!/bin/bash
# Собирает PimpMyClaude.app из SwiftPM-пакета и подписывает Developer ID (стабильный cdhash → Accessibility просится один раз).
# Использование: tools/bundle.sh [debug|release]
# Переменные: APP_OUT — куда класть .app (по умолчанию app/.build/PimpMyClaude.app),
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
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"

# Иконка лежит в репозитории; без неё zip в Finder выглядит как чужой файл.
# Генератор оставлен здесь же — чтобы иконку можно было перерисовать, а не искать.
if [ ! -f "$ICON" ]; then
  echo "bundle.sh: рисую $ICON"
  TMP="$(mktemp -d)"
  cat > "$TMP/makeicon.swift" <<'SWIFT'
import AppKit
// Скруглённый квадрат с градиентом и белой «P». Рисуем прямо в битмап нужного размера
// (lockFocus на Retina удвоил бы пиксели и сломал имена в .iconset).
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let names: [Int: [String]] = [
    16: ["icon_16x16"], 32: ["icon_16x16@2x", "icon_32x32"], 64: ["icon_32x32@2x"],
    128: ["icon_128x128"], 256: ["icon_128x128@2x", "icon_256x256"],
    512: ["icon_256x256@2x", "icon_512x512"], 1024: ["icon_512x512@2x"],
]
for (px, files) in names {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let side = CGFloat(px), inset = side * 0.09
    let box = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let shape = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225)
    NSGradient(colors: [NSColor(srgbRed: 0.95, green: 0.58, blue: 0.44, alpha: 1),
                        NSColor(srgbRed: 0.74, green: 0.31, blue: 0.20, alpha: 1)])?.draw(in: shape, angle: -90)
    let letter = NSAttributedString(string: "P", attributes: [
        .font: NSFont.systemFont(ofSize: side * 0.56, weight: .bold),
        .foregroundColor: NSColor.white,
    ])
    let size = letter.size()
    letter.draw(at: NSPoint(x: (side - size.width) / 2, y: (side - size.height) / 2 - side * 0.035))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    for file in files { try png.write(to: URL(fileURLWithPath: "\(out)/\(file).png")) }
}
SWIFT
  swift "$TMP/makeicon.swift" "$TMP/AppIcon.iconset"
  iconutil -c icns "$TMP/AppIcon.iconset" -o "$ICON"
  rm -rf "$TMP"
fi

cd "$ROOT/app"
swift build -c "$CONF" 2>&1 | tail -3
BIN="$(swift build -c "$CONF" --show-bin-path)/PimpMyClaude"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PimpMyClaude"
cp "$PLIST" "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
for f in "$ROOT/claude-patch/inject.js" "$ROOT/claude-patch/claude.css" "$ROOT/claude-patch/themes.json" "$ROOT/claude-patch/entitlements.plist"; do
  if [ ! -f "$f" ]; then echo "bundle.sh: нет ресурса $f" >&2; exit 1; fi
  cp "$f" "$APP/Contents/Resources/"
done
codesign --force --options runtime --timestamp \
  --entitlements "$ROOT/app/Resources/PimpMyClaude.entitlements" \
  --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "OK: PimpMyClaude $VERSION ($BUILD)"
echo "VERSION=$VERSION"
echo "BUILD=$BUILD"
echo "APP=$APP"
