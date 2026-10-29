#!/bin/bash
# Builds "build/NOVA V4.app" and "build/novav4ctl" (release, host architecture).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product NovaV4
swift build -c release --product novav4ctl
BIN="$(swift build -c release --show-bin-path)"

APP="build/NOVA V4.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/NovaV4" "$APP/Contents/MacOS/NovaV4"
cp "$BIN/novav4ctl" build/novav4ctl

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>NOVA V4</string>
    <key>CFBundleDisplayName</key><string>NOVA V4</string>
    <key>CFBundleIdentifier</key><string>local.novav4.configurator</string>
    <key>CFBundleExecutable</key><string>NovaV4</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# macOS ties the Input Monitoring grant to the signature's designated requirement. An ad-hoc
# signature's requirement is the cdhash, which changes on every build, so each rebuild loses the grant
# even though System Settings still shows it enabled. Signing with a fixed identity (e.g. a self-signed
# "Code Signing" certificate from Keychain Access) keeps the grant across builds:
#   SIGN_IDENTITY="NOVA V4 Dev" scripts/build-app.sh
IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP"
codesign --force --sign "$IDENTITY" build/novav4ctl
echo "built: $APP and build/novav4ctl"
if [ "$IDENTITY" = "-" ]; then
    echo "note: ad-hoc signed. After replacing an older build, re-grant Input Monitoring:"
    echo "      tccutil reset ListenEvent local.novav4.configurator"
fi
