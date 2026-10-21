#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

OUTPUT="${1:-../dist/macos}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
APP="$OUTPUT/薪跳.app"

swift run SalaryEngineChecks
swift build -c release --arch arm64
swift build -c release --arch x86_64

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/AppIcon.iconset
lipo -create .build/arm64-apple-macosx/release/PayPulse .build/x86_64-apple-macosx/release/PayPulse -output "$APP/Contents/MacOS/PayPulse"
swift MakeIcon.swift .build/AppIcon1024.png
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" .build/AppIcon1024.png --out ".build/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" .build/AppIcon1024.png --out ".build/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>薪跳</string>
<key>CFBundleDisplayName</key><string>薪跳</string>
<key>CFBundleIdentifier</key><string>local.paypulse.mac</string>
<key>CFBundleExecutable</key><string>PayPulse</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 PayPulse Contributors. MIT License.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built: %s\n' "$APP"
