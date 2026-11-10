#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set a Developer ID Application signing identity}"
: "${INSTALLER_IDENTITY:?Set a Developer ID Installer signing identity}"
: "${NOTARY_PROFILE:?Set an existing notarytool keychain profile name}"
scripts/build-app.sh
app="$PWD/dist/OpenConnect Mac GUI.app"
archive="$PWD/dist/OpenConnect-Mac-GUI-notary.zip"
ditto -c -k --keepParent "$app" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
pkgbuild --component "$app" --install-location /Applications --sign "$INSTALLER_IDENTITY" "$PWD/dist/OpenConnect-Mac-GUI.pkg"
xcrun notarytool submit "$PWD/dist/OpenConnect-Mac-GUI.pkg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$PWD/dist/OpenConnect-Mac-GUI.pkg"
xcrun stapler validate "$PWD/dist/OpenConnect-Mac-GUI.pkg"
spctl --assess --type execute --verbose "$app"
pkgutil --check-signature "$PWD/dist/OpenConnect-Mac-GUI.pkg"
ditto -c -k --keepParent "$app" "$PWD/dist/OpenConnect-Mac-GUI.zip"
printf 'Release artifacts are in dist/.\n'
