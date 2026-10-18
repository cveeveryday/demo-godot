#!/usr/bin/env bash
# Build the Steam Frame APK headless.
# usage: tools/build_apk.sh [debug|release] [out.apk]
#   release needs keystore/release* set in export_presets.cfg (or GODOT_ANDROID_KEYSTORE_RELEASE_* env vars).
set -euo pipefail
MODE=${1:-debug}
cd "$(dirname "$0")/.."
OUT=${2:-build/framedemo.apk}
PRESET="Steam Frame (arm64)"
GODOT=${GODOT:-godot}
mkdir -p "$(dirname "$OUT")"

# Make sure every asset is imported (ASTC/ETC2 variants are generated at import time).
for i in 1 2 3; do
  if "$GODOT" --headless --path . --import >/tmp/framedemo_import.$$.log 2>&1; then break; fi
  echo "import attempt $i failed (another agent importing?), retrying..."; sleep 5
done
grep -iE "^(ERROR|SCRIPT ERROR)" /tmp/framedemo_import.$$.log | head -20 || true
rm -f /tmp/framedemo_import.$$.log

"$GODOT" --headless --path . "--export-$MODE" "$PRESET" "$OUT" 2>&1 \
  | grep -vE "^(ADDING|\[ *[0-9]+% \]|$)" | tail -25
[ -f "$OUT" ] || { echo "export failed: $OUT not produced"; exit 1; }
echo "APK: $OUT ($(du -h "$OUT" | cut -f1))"
command -v unzip >/dev/null && echo "largest entries:" && unzip -l "$OUT" | sort -k1 -n -r | sed -n '2,8p'
