#!/bin/bash
# Build the Script Maker Mac .app and DMG. RUN ON A MAC.
set -euo pipefail

cd "$(dirname "$0")"
VERSION="${1:-1.0}"
APP="ScriptMakerMac.app"
DMG="ScriptMakerMac-${VERSION}.dmg"

echo "==> Building (Release)..."
xcodebuild -project ../../ScriptMakerMac.xcodeproj \
  -target ScriptMakerMac \
  -configuration Release \
  -derivedDataPath build \
  clean build

BUILT_APP="$(find build -name "$APP" -maxdepth 4 | head -1)"
echo "==> Creating DMG..."
rm -f "$DMG"
hdiutil create -volname "Script Maker" -srcfolder "$BUILT_APP" -ov -format UDZO "$DMG"
echo "Done: $DMG"
