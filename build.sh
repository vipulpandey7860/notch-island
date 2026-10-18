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
# TODO: sign releases with a Developer ID and notarize. Ad-hoc signatures change every build,
# so macOS asks for calendar access again after each rebuild.
codesign --force --sign - "$APP"
if [ "$1" = run ]; then
    pkill -x NotchIsland || true
    while pgrep -qx NotchIsland; do sleep 0.1; done
    open "$APP"  # via open, so macOS asks for calendar access as Notch Island, not as your terminal
fi
