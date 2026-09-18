#!/bin/bash
# Cuts every iOS icon slot from game/icon_1024.png. Local, lossless, no network.
#
# Godot's iOS exporter WILL synthesise the smaller icons from the App Store one,
# but it does so at export time with no chance to look at the result. Icons are
# the one asset whose whole job is to be legible at 40 px, so they are cut here
# instead and checked by eye -- `docs/shots/icon_preview_*.png`.
#
# Usage: tools/make_ios_icons.sh
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/game/icon_1024.png"
OUT="$REPO/game/assets/icon/ios"
[ -f "$SRC" ] || { echo "missing $SRC -- run the icon_render scene first" >&2; exit 1; }
mkdir -p "$OUT"
# slot sizes Godot's export preset asks for
for SIZE in 40 58 76 80 120 152 167 180 1024; do
  cp "$SRC" "$OUT/icon_${SIZE}.png"
  sips -Z "$SIZE" "$OUT/icon_${SIZE}.png" >/dev/null
  printf '  %4s  %s\n' "$SIZE" "$(du -h "$OUT/icon_${SIZE}.png" | cut -f1)"
done
echo "wrote $(ls "$OUT" | wc -l | tr -d ' ') icons to $OUT"
