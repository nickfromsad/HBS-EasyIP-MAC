#!/bin/bash
# Builds "HBS EasyIP MAC.app" plus a .dmg and .zip in build/.
#
#   VERSION=1.2.0 scripts/build-app.sh
#
# Optional environment:
#   SIGN_IDENTITY   "Developer ID Application: ..." for a signed build (default: ad-hoc "-")
#   UNIVERSAL=1     build for Apple Silicon and Intel (needs Xcode, default on CI)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 0)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/HBS EasyIP MAC.app"
DIST="HBS-EasyIP-MAC-$VERSION"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "▸ Building EasyIPMac + easyip $VERSION (${ARCH_FLAGS[*]:-native})"
swift build -c release --product EasyIPMac ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
swift build -c release --product easyip ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/EasyIPMac" "$APP/Contents/MacOS/EasyIPMac"
cp "$BIN/easyip" "$APP/Contents/MacOS/easyip"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

echo "▸ Signing ($SIGN_IDENTITY)"
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_FLAGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/MacOS/easyip"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --strict "$APP"

echo "▸ Packaging"
rm -f build/HBS-EasyIP-MAC-*.dmg build/HBS-EasyIP-MAC-*.zip

# Styled install window (background, icon positions) via dmgbuild, which needs Python 3.10+:
# uv if installed, otherwise a venv from a recent enough python3.
DMGBUILD=()
if command -v uvx >/dev/null; then
    DMGBUILD=(uvx --quiet --from dmgbuild==1.6.7 dmgbuild)
elif python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
    python3 -m venv build/.venv && build/.venv/bin/pip install --quiet dmgbuild==1.6.7
    DMGBUILD=(build/.venv/bin/dmgbuild)
fi

if [[ ${#DMGBUILD[@]} -gt 0 ]]; then
    swift scripts/make-dmg-background.swift "$VERSION" build/dmg
    tiffutil -cathidpicheck build/dmg/background.png build/dmg/background@2x.png -out build/dmg/background.tiff
    "${DMGBUILD[@]}" -s scripts/dmg-settings.py \
        -D app="$APP" -D background=build/dmg/background.tiff -D icon=Resources/AppIcon.icns \
        "HBS EasyIP MAC" "build/$DIST.dmg"
else
    echo "  (no Python 3.10+ or uv: building a plain .dmg without the styled window)"
    STAGE="$(mktemp -d)"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -quiet -volname "HBS EasyIP MAC" -srcfolder "$STAGE" -format UDZO -ov "build/$DIST.dmg"
    rm -rf "$STAGE"
fi
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "build/$DIST.dmg"
fi
ditto -c -k --keepParent "$APP" "build/$DIST.zip"

echo "✓ build/$DIST.dmg"
echo "✓ build/$DIST.zip"
