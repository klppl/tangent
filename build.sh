#!/bin/bash
# Builds Tangent.app. Usage: ./build.sh [install]
#   install  – also copies the app to /Applications and launches it
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Tangent"

APP="build/Tangent.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Tangent"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x Tangent || true
    rm -rf /Applications/Tangent.app
    cp -R "$APP" /Applications/
    open /Applications/Tangent.app
    echo "Installed to /Applications/Tangent.app"
fi
