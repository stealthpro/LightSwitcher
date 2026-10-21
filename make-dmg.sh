#!/bin/sh
# Builds LightSwitcher in Release and packages it as a compressed .dmg
# with an /Applications shortcut, so the app can be dragged into place.
#
#   ./make-dmg.sh          writes dist/LightSwitcher.dmg
#
# The app is only as signed as the Release build: it is not notarized, so
# on another Mac Gatekeeper will block it until the user allows it in
# System Settings > Privacy & Security.
set -eu

cd "$(dirname "$0")"

APP_NAME=LightSwitcher
OUT_DIR=dist
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lightswitcher-dmg.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Building $APP_NAME (Release)..."
if ! xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$WORK_DIR/derived" build \
    > "$WORK_DIR/build.log" 2>&1; then
    tail -n 40 "$WORK_DIR/build.log"
    echo "Build failed." >&2
    exit 1
fi

BUILT_APP="$WORK_DIR/derived/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "Build succeeded but $BUILT_APP was not found." >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT_APP/Contents/Info.plist")
DMG="$OUT_DIR/$APP_NAME.dmg"

STAGE="$WORK_DIR/stage"
mkdir -p "$STAGE" "$OUT_DIR"
ditto "$BUILT_APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

echo "Creating $DMG..."
rm -f "$DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" > /dev/null

hdiutil verify "$DMG" > /dev/null
echo "Done: $(pwd)/$DMG"
