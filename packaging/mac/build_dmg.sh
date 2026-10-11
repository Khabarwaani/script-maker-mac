#!/bin/bash
# Build the Script Maker Mac .app and DMG. RUN ON A MAC.
#
# Usage: build_dmg.sh [VERSION]
#   VERSION defaults to the CFBundleShortVersionString in Info.plist.
set -euo pipefail

cd "$(dirname "$0")"
APP="ScriptMakerMac.app"

if [ $# -ge 1 ]; then
    VERSION="$1"
else
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
        ../../Sources/ScriptMakerMac/Resources/Info.plist 2>/dev/null || echo 1.0)"
fi
DMG="ScriptMakerMac-${VERSION}.dmg"

echo "==> Building (Release)..."
xcodebuild -project ../../ScriptMakerMac.xcodeproj \
  -scheme ScriptMakerMac \
  -configuration Release \
  -derivedDataPath build \
  clean build

BUILT_APP="$(find build -name "$APP" -maxdepth 4 | head -1)"
if [ -z "$BUILT_APP" ]; then
    echo "ERROR: $APP not found under build/ after xcodebuild." >&2
    exit 1
fi
echo "==> Built: $BUILT_APP"

echo "==> Creating DMG..."
rm -f "$DMG"
hdiutil create -volname "Script Maker" -srcfolder "$BUILT_APP" -ov -format UDZO "$DMG"
echo "Done: $(pwd)/$DMG"
