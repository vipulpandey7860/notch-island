#!/bin/sh
# Builds build/NotchIsland.app. `./build.sh run` also (re)launches it.
set -e
cd "$(dirname "$0")"
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=build/NotchIsland.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/NotchIsland" "$APP/Contents/MacOS/NotchIsland"
cp "$BIN/libNowPlayingHelper.dylib" "$APP/Contents/Resources/NowPlayingHelper.dylib"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Signed with the "Notch Island Release" certificate when you have it (./release.sh --setup makes one), so macOS
# recognises every release as the same app and keeps its permissions, like calendar access. Otherwise ad hoc, and
# macOS asks again after each rebuild. Either way it isn't notarized (that needs a paid Apple developer account).
ID=-
security find-identity -v -p codesigning 2>/dev/null | grep -q '"Notch Island Release"' && ID="Notch Island Release"
codesign --force --sign "$ID" "$APP/Contents/Resources/NowPlayingHelper.dylib"
codesign --force --sign "$ID" "$APP"
if [ "$1" = run ]; then
    pkill -x NotchIsland || true
    while pgrep -qx NotchIsland; do sleep 0.1; done
    open "$APP"  # via open, so macOS asks for calendar access as Notch Island, not as your terminal
fi
