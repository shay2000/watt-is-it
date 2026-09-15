#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
PRODUCT_NAME="WattIsIt"
APP_DIR="$BUILD_DIR/$PRODUCT_NAME.app"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

SWIFTC="$(xcrun --find swiftc)"
MACOS_SDK="$(xcrun --sdk macosx --show-sdk-path)"

cd "$ROOT_DIR"
mkdir -p "$MODULE_CACHE_DIR"

"$SWIFTC" \
    -O \
    -gnone \
    -parse-as-library \
    -target arm64-apple-macos14.6 \
    -sdk "$MACOS_SDK" \
    -module-cache-path "$MODULE_CACHE_DIR" \
    -Xcc -fmodules-cache-path="$MODULE_CACHE_DIR" \
    -framework AppKit \
    -framework IOKit \
    -framework ServiceManagement \
    "$ROOT_DIR/Sources/WattIsIt/AppDelegate.swift" \
    "$ROOT_DIR/Sources/WattIsIt/PowerReader.swift" \
    "$ROOT_DIR/Sources/WattIsIt/PowerSnapshot.swift" \
    "$ROOT_DIR/Sources/WattIsIt/BatteryIconVisibility.swift" \
    "$ROOT_DIR/Sources/WattIsIt/LaunchAtLogin.swift" \
    "$ROOT_DIR/Sources/WattIsIt/UpdateService.swift" \
    -o "$BUILD_DIR/$PRODUCT_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$PRODUCT_NAME" "$APP_DIR/Contents/MacOS/$PRODUCT_NAME"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

if [[ -f "$ROOT_DIR/Resources/WattIsIt.icns" ]]; then
    cp "$ROOT_DIR/Resources/WattIsIt.icns" "$APP_DIR/Contents/Resources/WattIsIt.icns"
fi

xattr -cr "$APP_DIR"
find "$APP_DIR" -exec xattr -d com.apple.FinderInfo {} + 2>/dev/null || true
find "$APP_DIR" -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} + 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null
xattr -cr "$APP_DIR"
find "$APP_DIR" -exec xattr -d com.apple.FinderInfo {} + 2>/dev/null || true
find "$APP_DIR" -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} + 2>/dev/null || true
echo "Built $APP_DIR"
