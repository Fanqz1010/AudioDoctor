#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="${APP_NAME:-Audio Doctor}"
BUNDLE_ID="${BUNDLE_ID:-com.fanqianzi.audiodoctor}"
VERSION="${VERSION:-0.5.0}"
BUILD="${BUILD:-7}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
ENTITLEMENTS="${ENTITLEMENTS:-$ROOT/packaging/AppStoreEntitlements.plist}"
PROFILE="${PROFILE:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/build/package}"

SDK="$(xcrun --show-sdk-path)"
APP_ROOT="$OUTPUT_DIR/$APP_NAME.app"
mkdir -p "$APP_ROOT/Contents/MacOS" "$APP_ROOT/Contents/Resources" "$OUTPUT_DIR"

echo "▸ Compiling AudioDoctor $VERSION ($BUILD)"
ADDITIONAL_FLAGS=()
if [[ "${APP_STORE_BUILD:-1}" == "1" ]]; then
  ADDITIONAL_FLAGS+=(-D APP_STORE_BUILD)
fi
(cd "$ROOT" && swiftc -sdk "$SDK" -O "${ADDITIONAL_FLAGS[@]}" -o "$APP_ROOT/Contents/MacOS/AudioDoctor" Sources/AudioDoctor/*.swift)

cat > "$APP_ROOT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleDisplayName</key><string>Audio Doctor</string>
    <key>CFBundleExecutable</key><string>AudioDoctor</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Audio Doctor</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDocumentTypes</key>
    <array>
      <dict>
        <key>CFBundleTypeName</key><string>Audio</string>
        <key>CFBundleTypeRole</key><string>Viewer</string>
        <key>LSItemContentTypes</key><array><string>public.audio</string></array>
      </dict>
    </array>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP_ROOT/Contents/PkgInfo"

ICONSET="$OUTPUT_DIR/AppIcon.iconset"
SOURCE_ICON="$ROOT/docs/assets/app-icon-1024.png"
[[ -f "$SOURCE_ICON" ]] || { echo "✗ Missing $SOURCE_ICON"; exit 2; }
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$SOURCE_ICON" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
done
sips -z 1024 1024 "$SOURCE_ICON" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP_ROOT/Contents/Resources/AppIcon.icns"

if [[ -n "$PROFILE" ]]; then
  cp "$PROFILE" "$APP_ROOT/Contents/embedded.provisionprofile"
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "▸ Signing with $SIGNING_IDENTITY"
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" "$APP_ROOT"
else
  echo "▸ No signing identity supplied; creating an ad-hoc local build"
  codesign --force --sign - --timestamp=none "$APP_ROOT"
fi

codesign --verify --deep --strict "$APP_ROOT"
plutil -lint "$APP_ROOT/Contents/Info.plist"
echo "✓ Packaged: $APP_ROOT"
