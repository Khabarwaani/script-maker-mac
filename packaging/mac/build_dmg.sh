#!/bin/bash
# Build the Script Maker Mac .app and DMG. RUN ON A MAC.
#
# 1. Builds the Xcode target (Swift launcher).
# 2. Bundles the Streamlit payload into Resources/streamlit-payload.
# 3. Stamps the AppIcon and produces ScriptMakerMac.dmg.
set -euo pipefail

cd "$(dirname "$0")"
VERSION="${1:-1.0}"
APP="ScriptMakerMac.app"
DMG="ScriptMakerMac-${VERSION}.dmg"

echo "==> Building Xcode target..."
xcodebuild -project ScriptMakerMac.xcodeproj -scheme ScriptMakerMac \
  -configuration Release -derivedDataPath build clean build

BUILT_APP="$(find build -name "$APP" -maxdepth 4 | head -1)"
echo "==> Assembling payload..."
PAYLOAD="$BUILT_APP/Contents/Resources/streamlit-payload"
mkdir -p "$PAYLOAD"
cp -r ../../../app "$PAYLOAD/"
cp ../../../requirements.txt "$PAYLOAD/"
cat > "$PAYLOAD/launch.sh" <<'EOF'
#!/bin/bash
# Launched by the Swift AppDelegate. Starts the Streamlit thin client.
PORT="${1:-8502}"
cd "$(dirname "$0")"
exec python3 -m streamlit run app/main.py --server.port "$PORT" --server.headless true
EOF
chmod +x "$PAYLOAD/launch.sh"

echo "==> Creating DMG..."
rm -f "$DMG"
hdiutil create -volname "Script Maker" -srcfolder "$BUILT_APP" -ov -format UDZO "$DMG"
echo "Done: $DMG"
