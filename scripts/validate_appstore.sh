#!/bin/zsh
set -euo pipefail
APP="${1:-build/package/Audio Doctor.app}"
[[ -d "$APP" ]] || { echo "✗ App bundle not found: $APP"; exit 2; }
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -vvv -t exec "$APP" || true
echo "Bundle ID: $(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")"
echo "Version: $(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist") ($(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist"))"
echo "Icon: $(test -f "$APP/Contents/Resources/AppIcon.icns" && echo OK || echo MISSING)"
echo "Sandbox profile: $(test -f "$APP/Contents/embedded.provisionprofile" && echo OK || echo 'MISSING — required for Mac App Store submission')"
