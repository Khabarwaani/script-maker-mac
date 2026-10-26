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
        ../../Sources/ScriptMakerMac/Resources/Info.plist 2>/dev/null)"
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

BUILT_APP="$(ruby -rjson -e '
  targets = JSON.parse(File.read(ARGV.fetch(0)))
  settings = targets.find { |target| target["target"] == "ScriptMakerMac" }.fetch("buildSettings")
  puts File.join(settings.fetch("TARGET_BUILD_DIR"), settings.fetch("FULL_PRODUCT_NAME"))
' "$SETTINGS_FILE")"