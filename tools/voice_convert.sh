#!/usr/bin/env bash
# Little Days -- voice pack converter.
#
# Converts the owner's WAV masters (kept OUTSIDE the repo) into the OGG Vorbis
# files the game loads, validates them against game/content/voice/voice_manifest.json
# and writes a voice_pack_report.json next to this script's output folder.
#
#   tools/voice_convert.sh [MASTERS_DIR] [--dry-run]
#
#   MASTERS_DIR   default ~/Music/LittleDays/voice
#                 Masters are looked up as MASTERS_DIR/<character>/<lineId>.wav
#                 and, failing that, MASTERS_DIR/<lineId>.wav.
#
# Output: game/assets/audio/voice/<character>/<lineId>.ogg
#         44.1 kHz, mono, ~96 kb/s Vorbis (oggenc -q 3 or afconvert, whichever
#         is installed). Durations are validated (0.3 s .. 6.0 s) with ffprobe,
#         afinfo or python, whichever exists.
#
# The script never fabricates anything: a line with no master is reported as
# "missing", never as a silent placeholder file.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
MANIFEST="$ROOT/game/content/voice/voice_manifest.json"
OUT_ROOT="$ROOT/game/assets/audio/voice"
REPORT="$OUT_ROOT/voice_pack_report.json"

MASTERS="$HOME/Music/LittleDays/voice"
DRY_RUN=0
for arg in "$@"; do
  if [ "$arg" = "--dry-run" ]; then DRY_RUN=1; else MASTERS="$arg"; fi
done

MIN_SEC=0.3
MAX_SEC=6.0

if [ ! -f "$MANIFEST" ]; then
  echo "manifest not found: $MANIFEST" >&2
  exit 2
fi

# -- Which encoder do we have? -------------------------------------------------
ENCODER=""
if command -v oggenc >/dev/null 2>&1; then
  ENCODER="oggenc"
elif command -v ffmpeg >/dev/null 2>&1; then
  ENCODER="ffmpeg"
elif command -v afconvert >/dev/null 2>&1; then
  # afconvert cannot write Vorbis in an .ogg container on stock macOS; it is
  # kept as a documented last resort for a machine that has the Xiph
  # components installed. It is tried and its failure is reported honestly.
  ENCODER="afconvert"
fi

# -- Duration probe ------------------------------------------------------------
duration_of() {
  local file="$1"
  if command -v ffprobe >/dev/null 2>&1; then
    ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$file" 2>/dev/null || echo ""
  elif command -v afinfo >/dev/null 2>&1; then
    afinfo "$file" 2>/dev/null | awk '/estimated duration/ {print $3; exit}'
  else
    echo ""
  fi
}

encode() {
  local src="$1" dst="$2"
  case "$ENCODER" in
    oggenc)  oggenc -Q -q 3 --resample 44100 --downmix -o "$dst" "$src" ;;
    ffmpeg)  ffmpeg -v error -y -i "$src" -ac 1 -ar 44100 -c:a libvorbis -b:a 96k "$dst" ;;
    afconvert) afconvert -f ogg -d vorbis -c 1 -r 44100 "$src" "$dst" ;;
    *) return 1 ;;
  esac
}

mkdir -p "$OUT_ROOT/aliz" "$OUT_ROOT/bunny"

# -- Walk the manifest ---------------------------------------------------------
LINES_JSON="$(python3 - "$MANIFEST" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
for line in m["lines"]:
    print("%s\t%s" % (line["lineId"], line["character"]))
PY
)"

total=0; converted=0; present=0; missing=0; failed=0
entries=()

while IFS=$'\t' read -r line_id character; do
  [ -z "$line_id" ] && continue
  total=$((total + 1))
  master=""
  for candidate in "$MASTERS/$character/$line_id.wav" "$MASTERS/$line_id.wav" \
                   "$MASTERS/$character/$line_id.WAV" "$MASTERS/$line_id.aif" "$MASTERS/$character/$line_id.aif"; do
    if [ -f "$candidate" ]; then master="$candidate"; break; fi
  done
  dst="$OUT_ROOT/$character/$line_id.ogg"
  status=""; note=""; seconds=""

  if [ -z "$master" ]; then
    if [ -f "$dst" ]; then
      status="present"; present=$((present + 1))
      seconds="$(duration_of "$dst")"
      note="ogg already in place; no master found this run"
    else
      status="missing"; missing=$((missing + 1))
      note="no master at $MASTERS/$character/$line_id.wav"
    fi
  else
    if [ "$DRY_RUN" = "1" ]; then
      status="wouldConvert"; note="dry run"
    elif [ -z "$ENCODER" ]; then
      status="failed"; failed=$((failed + 1)); note="no encoder: install vorbis-tools (oggenc) or ffmpeg"
    elif encode "$master" "$dst"; then
      seconds="$(duration_of "$dst")"
      status="converted"; converted=$((converted + 1)); present=$((present + 1))
      if [ -n "$seconds" ]; then
        if python3 -c "import sys; d=float(sys.argv[1]); sys.exit(0 if $MIN_SEC <= d <= $MAX_SEC else 1)" "$seconds"; then
          note="duration ok"
        else
          note="DURATION OUT OF RANGE (${seconds}s; expected ${MIN_SEC}-${MAX_SEC}s): check head/tail trim"
        fi
      else
        note="converted; no duration probe available (install ffprobe)"
      fi
    else
      status="failed"; failed=$((failed + 1)); note="$ENCODER failed on $master"
      rm -f "$dst"
    fi
  fi
  printf '  %-26s %-12s %s\n' "$line_id" "$status" "$note"
  entries+=("{\"lineId\":\"$line_id\",\"character\":\"$character\",\"status\":\"$status\",\"seconds\":\"${seconds}\",\"note\":\"${note//\"/\\\"}\"}")
done <<< "$LINES_JSON"

# -- Report --------------------------------------------------------------------
{
  echo "{"
  echo "  \"generatedAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"mastersDir\": \"$MASTERS\","
  echo "  \"encoder\": \"${ENCODER:-none}\","
  echo "  \"dryRun\": $DRY_RUN,"
  echo "  \"total\": $total,"
  echo "  \"present\": $present,"
  echo "  \"converted\": $converted,"
  echo "  \"missing\": $missing,"
  echo "  \"failed\": $failed,"
  echo "  \"lines\": ["
  first=1
  for e in "${entries[@]}"; do
    if [ $first = 1 ]; then first=0; else echo ","; fi
    printf '    %s' "$e"
  done
  echo ""
  echo "  ]"
  echo "}"
} > "$REPORT"

echo
echo "voice pack: $present of $total recordings present ($converted converted now, $missing missing, $failed failed)"
echo "report: $REPORT"
[ "$failed" = "0" ]
