#!/bin/bash
# Builds Tangent.app. Usage: ./build.sh [install]
#   install  – also copies the app to /Applications and launches it
set -euo pipefail
cd "$(dirname "$0")"

# Universal binary: build each architecture, then merge with lipo.
BINS=()
for ARCH in arm64 x86_64; do
    swift build -c release --triple "$ARCH-apple-macosx13.0"
    BINS+=("$(swift build -c release --triple "$ARCH-apple-macosx13.0" --show-bin-path)/Tangent")
done

APP="build/Tangent.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/Tangent"
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
