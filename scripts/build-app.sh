#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
configuration="${CONFIGURATION:-release}"
swift build --disable-sandbox --configuration "$configuration" --cache-path "$PWD/.build/cache"
binary_dir="$(swift build --disable-sandbox --configuration "$configuration" --show-bin-path)"
app="$PWD/dist/Betterer Connect.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/BettererConnect" "$app/Contents/MacOS/BettererConnect"
cp Packaging/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$PWD/.build/BettererConnect.iconset"
iconutil -c icns "$PWD/.build/BettererConnect.iconset" -o "$app/Contents/Resources/BettererConnect.icns"
if [[ -n "${BUNDLE_ID:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$app/Contents/Info.plist"
fi
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
