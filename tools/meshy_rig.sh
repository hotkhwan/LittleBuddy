#!/usr/bin/env bash
# The ONE approved Meshy Rigging run. input_task_id ONLY. NO RETRY. NO FALLBACK.
#
#   Approved 2026-09-19: babyStanding_remesh_v01, input task
#   01a0b49b-48a0-775f-8b1f-6390a68681eb, MAXIMUM 5 CREDITS.
#   Walk + run clips are included in the rigging price.
#   Animation, generation, retexture and further remeshing are NOT approved.
#
# Usage:  ./tools/meshy_rig.sh <remesh_task_id>
#
# HARD RULE FROM THE OWNER
# If `input_task_id` is rejected, STOP AND REPORT. Do NOT fall back to
# `model_url` — that substitution needs its own explicit approval. This script
# has no fallback path on purpose; adding one would break the authorisation.
#
# SECURITY
# MESHY_API_KEY comes from the environment into a curl -H. Never echoed, never
# written to a file, never in a URL. Output URLs are signed capability URLs and
# are scrubbed from everything printed. Do NOT add `set -x` or `curl -v`.

set -euo pipefail
set +x

TASK_IN="${1:-}"
# PREFIX is the full path stem for this character's outputs, e.g.
#   game/assets_source/meshy/buddy/pinkGirl
# It is REQUIRED. It used to be hardcoded to the baby, and running this for a
# second character silently overwrote the first character's rigged GLB and both
# of its clips with the new one -- three files, same names, no warning. The
# originals were recoverable only because Meshy still had the task. Make the
# caller name the output.
PREFIX="${2:-}"
RIGGED="${PREFIX}_rigged_v01.glb"
WALK="${PREFIX}_walk_v01.glb"
RUN="${PREFIX}_run_v01.glb"
MAX_CREDITS="${3:-5}"

if [[ -z "$TASK_IN" || -z "$PREFIX" ]]; then
  echo "usage: $0 <remesh_task_id> <output_path_stem> [max_credits]" >&2
  echo "  e.g. $0 01a0b5e9-... game/assets_source/meshy/buddy/pinkGirl" >&2
  exit 2
fi
for existing in "${PREFIX}_rigged_v01.glb" "${PREFIX}_walk_v01.glb" "${PREFIX}_run_v01.glb"; do
  if [[ -e "$existing" ]]; then
    echo "Refusing to overwrite an existing output: $existing" >&2
    echo "Move or delete it first. Rigging costs credits; a silent overwrite" >&2
    echo "destroys an asset that was paid for." >&2
    exit 9
  fi
done
if [[ -z "${MESHY_API_KEY:-}" ]]; then
  echo "MESHY_API_KEY is not set in this environment." >&2
  exit 3
fi

API="https://api.meshy.ai/openapi/v1"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
scrub() {
  sed -e 's|https://assets\.meshy\.ai/[^" ]*|<redacted-signed-url>|g' \
      -e 's/Bearer [A-Za-z0-9._-]*/Bearer <redacted>/g'
}
balance() {
  curl -sS "${API}/balance" -H "Authorization: Bearer ${MESHY_API_KEY}" 2>/dev/null \
    | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("balance"))
except Exception: print("?")'
}

BAL_BEFORE="$(balance)"
echo "Balance BEFORE : ${BAL_BEFORE}"
echo "Input task     : ${TASK_IN}  (via input_task_id, no fallback)"
echo "Ceiling        : ${MAX_CREDITS} credits. ONE request, no retry."
echo

cat > "${TMP}/req.json" <<JSON
{ "input_task_id": "${TASK_IN}" }
JSON

CODE="$(curl -sS -X POST "${API}/rigging" \
     -H "Authorization: Bearer ${MESHY_API_KEY}" \
     -H "Content-Type: application/json" \
     -d @"${TMP}/req.json" \
     -o "${TMP}/create.json" -w '%{http_code}' 2>"${TMP}/create.err")" \
     || { scrub < "${TMP}/create.err" >&2; exit 4; }

if [[ "$CODE" != "200" && "$CODE" != "201" && "$CODE" != "202" ]]; then
  echo "Meshy REJECTED the rigging request (HTTP ${CODE}):"
  scrub < "${TMP}/create.json"
  echo
  echo "Balance AFTER : $(balance)  (was ${BAL_BEFORE})"
  echo
  echo "STOPPING as instructed. No retry, and NO model_url fallback —"
  echo "that substitution requires separate explicit approval."
  exit 5
fi

TASK_ID="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("result") or d.get("id") or "")' "${TMP}/create.json")"
if [[ -z "$TASK_ID" ]]; then
  echo "No task id returned. Response:" >&2
  scrub < "${TMP}/create.json" >&2
  exit 6
fi
echo "Rigging task created: ${TASK_ID}"

for _ in $(seq 1 180); do
  sleep 5
  curl -sS "${API}/rigging/${TASK_ID}" \
       -H "Authorization: Bearer ${MESHY_API_KEY}" \
       -o "${TMP}/task.json" 2>"${TMP}/task.err" || { scrub < "${TMP}/task.err" >&2; exit 7; }
  STATUS="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("status",""))' "${TMP}/task.json")"
  PROG="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("progress",""))' "${TMP}/task.json")"
  echo "  status=${STATUS} progress=${PROG}"
  [[ "$STATUS" == "SUCCEEDED" || "$STATUS" == "FAILED" || "$STATUS" == "CANCELED" ]] && break
done

python3 - "${TMP}/task.json" "$MAX_CREDITS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); cap = int(sys.argv[2])
used = d.get("consumed_credits")
print(f"\nstatus           : {d.get('status')}")
print(f"consumed_credits : {used}")
if isinstance(used, int) and used > cap:
    print(f"!! OVER THE AUTHORISED CEILING of {cap}. Report before anything further.")
if d.get("status") != "SUCCEEDED":
    print("task_error       :", d.get("task_error"))
    print("\nFAILED. Do NOT retry automatically — a retry needs a new approval.")
PY

STATUS="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("status",""))' "${TMP}/task.json")"
if [[ "$STATUS" != "SUCCEEDED" ]]; then
  echo "Balance AFTER : $(balance)  (was ${BAL_BEFORE})"
  exit 8
fi

echo
echo "Output fields present:"
python3 - "${TMP}/task.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
res = d.get("result") if isinstance(d.get("result"), dict) else d
for k in sorted(res):
    if k.endswith("_url"):
        print(f"  {k}: {'present' if res[k] else 'EMPTY'}")
PY

mkdir -p "$(dirname "$PREFIX")"
get() { # field, destination
  # The walk/run urls are NOT at result top level — they live under
  # result.basic_animations. Searching only the top level silently reports them
  # as "not provided", which reads exactly like Meshy withheld them. Recurse.
  local field="$1" dest="$2"
  local url
  url="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1])); want=sys.argv[2]
def find(o):
    if isinstance(o,dict):
        if want in o and isinstance(o[want],str): return o[want]
        for v in o.values():
            r=find(v)
            if r: return r
    return ""
print(find(d) or "")' "${TMP}/task.json" "$field")"
  if [[ -z "$url" ]]; then
    echo "  ${field}: not provided, skipping"
    return 0
  fi
  curl -sS -L "$url" -o "$dest"
  echo "  ${field} -> ${dest}  ($(du -h "$dest" | cut -f1))"
}
echo
echo "Downloading:"
get rigged_character_glb_url "$RIGGED"
get walking_glb_url          "$WALK"
get running_glb_url          "$RUN"

echo
echo "Balance AFTER : $(balance)  (was ${BAL_BEFORE})"
echo
echo "STOP. Animation purchases are NOT approved."
