#!/bin/sh
set -eu
revision=$(/usr/bin/git -C "$SRCROOT" rev-parse --short=7 HEAD)
if ! /usr/bin/git -C "$SRCROOT" diff --quiet -- Sources ScriptMakerMac.xcodeproj/project.pbxproj; then
    revision="$revision-dirty"
fi
resource_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
/bin/mkdir -p "$resource_dir"
printf '%s\n' "$revision" > "$resource_dir/BuildCommit.txt"
