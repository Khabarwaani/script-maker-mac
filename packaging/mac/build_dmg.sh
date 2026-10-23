#!/bin/bash
# Build the Script Maker Mac .app and DMG. RUN ON A MAC.
#
# Usage: build_dmg.sh [VERSION]
#   VERSION defaults to the CFBundleShortVersionString in Info.plist.
set -euo pipefail

cd "$(dirname "$0")"

if [ $# -ge 1 ]; then
    VERSION="$1"
else
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
        ../../Sources/ScriptMakerMac/Resources/Info.plist 2>/dev/null || echo 1.2.0)"
fi
DMG="ScriptMakerMac-${VERSION}.dmg"

echo "==> Building (Release)..."
xcodebuild -project ../../ScriptMakerMac.xcodeproj \
  -scheme ScriptMakerMac \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build

SETTINGS_FILE="$(mktemp -t scriptmaker-release-settings.XXXXXX)"
trap 'rm -f "$SETTINGS_FILE"' EXIT
xcodebuild -project ../../ScriptMakerMac.xcodeproj \
  -scheme ScriptMakerMac \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -showBuildSettings -json > "$SETTINGS_FILE"

BUILT_APP="$(python3 -c '
import json, sys, os
targets = json.load(open(sys.argv[1]))
settings = next(t["buildSettings"] for t in targets if t.get("target") == "ScriptMakerMac")
print(os.path.join(settings["TARGET_BUILD_DIR"], settings["FULL_PRODUCT_NAME"]))
' "$SETTINGS_FILE")"

if [ ! -d "$BUILT_APP" ]; then
    echo "ERROR: built app missing at $BUILT_APP." >&2
    exit 1
fi
echo "==> Built: $BUILT_APP"

echo "==> Creating DMG..."
rm -f "$DMG"
hdiutil create -volname "Script Maker" -srcfolder "$BUILT_APP" -ov -format UDZO "$DMG"
echo "Done: $(pwd)/$DMG"
