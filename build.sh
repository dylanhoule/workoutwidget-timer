#!/bin/bash
# Build/run/check for Workout Interval. No Xcode needed: swiftc + a hand-rolled
# .app bundle (UNUserNotificationCenter requires a bundled app with a bundle ID).
# Keep CFBundleIdentifier stable across rebuilds or macOS may drop the
# notification permission grant (re-enable in System Settings > Notifications).
set -euo pipefail
cd "$(dirname "$0")"

NAME=WorkoutInterval
APP="build/$NAME.app"
TARGET="$(uname -m)-apple-macos13.0"

case "${1:-build}" in
  build|run)
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS"
    xcrun swiftc Sources/*.swift -parse-as-library -target "$TARGET" -O \
      -o "$APP/Contents/MacOS/$NAME"
    cp Info.plist "$APP/Contents/Info.plist"
    codesign --force --sign - "$APP"   # ad-hoc; must come after the plist copy
    echo "built $APP"
    if [ "${1:-}" = run ]; then
      pkill -x "$NAME" 2>/dev/null || true
      open "$APP"
    fi
    ;;
  check)
    # No -O here: it would compile the asserts out.
    mkdir -p build
    xcrun swiftc Sources/Model.swift Tests/main.swift -target "$TARGET" -o build/check
    ./build/check
    ;;
  *)
    echo "usage: $0 [build|run|check]" >&2
    exit 2
    ;;
esac
