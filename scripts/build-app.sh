#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME="NS2 Controller"
BUNDLE_ID="com.p1rate.ns2controller.app"
VERSION="${NS2_VERSION:-0.2.0}"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building NS2App (release)"
swift build -c release --product NS2App 2>&1 | tail -n 1

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/NS2App" "$APP/Contents/MacOS/NS2App"

ICON_BIN=".build/make-icon"
if [ ! -x "$ICON_BIN" ] || [ "scripts/make-icon.swift" -nt "$ICON_BIN" ]; then
    swiftc -O -o "$ICON_BIN" scripts/make-icon.swift -framework AppKit
fi
rm -rf "$DIST/AppIcon.iconset"
"$ICON_BIN" "$DIST/AppIcon.iconset"
iconutil -c icns "$DIST/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>NS2App</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSHumanReadableCopyright</key><string>ns2controller</string>
    <key>NSBluetoothAlwaysUsageDescription</key><string>Для подключения контроллера Switch 2 по Bluetooth.</string>
</dict>
</plist>
PLIST

SIGN="${NS2_SIGN_IDENTITY:-}"
if [ -z "$SIGN" ]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q '"ns2controller'; then SIGN="ns2controller"; else SIGN="-"; fi
fi
codesign --force --deep --sign "$SIGN" "$APP" 2>&1 | grep -v "replacing existing signature" || true
echo "==> $APP (signature: $SIGN)"
