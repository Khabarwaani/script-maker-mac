#!/bin/bash
set -euo pipefail

os_version="$(sw_vers -productVersion)"
xcode_version="$(xcodebuild -version | head -1 | awk '{print $2}')"
if [ "${os_version%%.*}" -lt 27 ] || [ "${xcode_version%%.*}" -lt 27 ]; then
    echo "::error::LocalAgent requires macOS 27+ and Xcode 27+. Found macOS $os_version / Xcode $xcode_version."
    exit 1
fi
