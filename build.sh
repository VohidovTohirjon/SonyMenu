#!/bin/zsh
# Builds SonyMenu.app (universal: Apple Silicon + Intel).
#   ./build.sh            build into build/SonyMenu.app
#   ./build.sh --install  also copy to ~/Applications and launch
#   ./build.sh --zip      also make build/SonyMenu.zip for a release
set -euo pipefail
cd "${0:A:h}"

swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/SonyMenu

APP=build/SonyMenu.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SonyMenu"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built: $PWD/$APP"

case "${1:-}" in
  --install)
    mkdir -p ~/Applications
    pkill -x SonyMenu 2>/dev/null || true
    sleep 1
    rm -rf ~/Applications/SonyMenu.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/SonyMenu.app
    echo "Installed: ~/Applications/SonyMenu.app"
    ;;
  --zip)
    rm -f build/SonyMenu.zip
    ditto -c -k --keepParent "$APP" build/SonyMenu.zip
    echo "Archive: $PWD/build/SonyMenu.zip"
    ;;
esac
