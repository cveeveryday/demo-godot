#!/usr/bin/env bash
# Render a scene to a PNG sequence for visual verification.
# usage: tools/render_frames.sh res://shots/coast/coast.tscn OUT_DIR [fps=4] [seconds=7] [WxH=1280x720]
set -euo pipefail
SCENE=$1; OUT=$2; FPS=${3:-4}; SECS=${4:-7}; RES=${5:-1280x720}
mkdir -p "$OUT"
FRAMES=$(python3 -c "print(int($FPS*$SECS))")
cd "$(dirname "$0")/.."
godot --path . --resolution "$RES" --fixed-fps "$FPS" --write-movie "$OUT/frame.png" \
  --quit-after "$FRAMES" "$SCENE" 2>&1 | grep -vE "^(Godot Engine|Vulkan|$)" | tail -40
ls "$OUT" | head -3; echo "... $(ls "$OUT" | wc -l) frames in $OUT"
