#!/bin/bash
# Builds "Dome Scanner.app" plus a .dmg and .zip in build/.
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
APP="build/Dome Scanner.app"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "▸ Building DomeScanner + domescan $VERSION (${ARCH_FLAGS[*]:-native})"
swift build -c release --product DomeScanner ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
swift build -c release --product domescan ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/DomeScanner" "$APP/Contents/MacOS/DomeScanner"
cp "$BIN/domescan" "$APP/Contents/MacOS/domescan"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

echo "▸ Signing ($SIGN_IDENTITY)"
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_FLAGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/MacOS/domescan"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --strict "$APP"

echo "▸ Packaging"
rm -f build/DomeScanner-*.dmg build/DomeScanner-*.zip
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Dome Scanner" -srcfolder "$STAGE" -format UDZO -ov "build/DomeScanner-$VERSION.dmg"
rm -rf "$STAGE"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "build/DomeScanner-$VERSION.dmg"
fi
ditto -c -k --keepParent "$APP" "build/DomeScanner-$VERSION.zip"

echo "✓ build/DomeScanner-$VERSION.dmg"
echo "✓ build/DomeScanner-$VERSION.zip"
