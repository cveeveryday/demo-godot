#!/usr/bin/env bash
# Install + launch the APK on an Android device or a Steam Frame Lepton container.
# usage: tools/install.sh [apk] [extra args passed to Godot, e.g. --quality=low]
#
# Steam Frame: enable Developer Mode, start "Lepton Development" from the Steam library
# (or launch any Android game), then either
#   Wi-Fi: FRAME_HOST=frame tools/install.sh        (runs `adb connect frame`)
#   USB:   adb forward tcp:5555 tcp:5555 && FRAME_HOST=localhost:5555 tools/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."
APK=${1:-build/framedemo.apk}; shift || true
PKG=com.demo.framedemo
ADB=${ADB:-$(command -v adb || echo "$HOME/Android/Sdk/platform-tools/adb")}

if [ -n "${FRAME_HOST:-}" ]; then
  "$ADB" connect "$FRAME_HOST"
fi
if ! "$ADB" get-state >/dev/null 2>&1; then
  echo "no adb device. Steam Frame: start 'Lepton Development', then FRAME_HOST=frame $0"; exit 1
fi
[ -f "$APK" ] || { echo "missing $APK — run tools/build_apk.sh first"; exit 1; }

"$ADB" install -r -g "$APK"
"$ADB" shell am force-stop "$PKG" || true
if [ $# -gt 0 ]; then
  # Godot reads extra command-line args from the 'command_line_params' intent extra.
  "$ADB" shell am start -n "$PKG/com.godot.game.GodotApp" --esa command_line_params "$(IFS=,; echo "$*")"
else
  "$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
fi
echo "launched $PKG — logs: $ADB logcat -s godot:V  (Lepton: lepton dev logcat)"
