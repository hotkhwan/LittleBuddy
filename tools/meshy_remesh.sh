#!/usr/bin/env bash
# The ONE approved Meshy operation: remesh the standing baby to ~8,000 quads.
#
#   Approved 2026-09-18: baby_standing_v01, target_polycount 8000, topology quad,
#   format glb, MAXIMUM 10 CREDITS. One operation only.
#   Rigging and Animation are NOT approved. Automatic retry is NOT approved.
#
# Usage:  ./tools/meshy_remesh.sh <input_task_id>
#
# SECURITY
# The key comes from the environment and goes straight to curl. It is never
# echoed, never written to a file, never put in a URL, and every error stream is
# filtered for a stray Authorization header before printing. Do NOT add `set -x`
# and do NOT add `curl -v`.

set -euo pipefail
set +x

TASK_IN="${1:-}"
OUT="game/assets_source/meshy/littleBuddy/babyStanding_remesh_v01.glb"
TARGET_POLYCOUNT=8000
MAX_CREDITS=10          # the ceiling the owner authorised

if [[ -z "$TASK_IN" ]]; then
  echo "usage: $0 <input_task_id>   (resolve it with tools/meshy_find_task.sh)" >&2
  exit 2
fi
if [[ -z "${MESHY_API_KEY:-}" ]]; then
  echo "MESHY_API_KEY is not set in this environment." >&2
  exit 3
fi

API="https://api.meshy.ai/openapi/v1"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
redact() { sed -e 's/Bearer [A-Za-z0-9._-]*/Bearer <redacted>/g'; }

echo "Remesh: input_task_id=${TASK_IN}  target_polycount=${TARGET_POLYCOUNT}  topology=quad"
echo "Authorised ceiling: ${MAX_CREDITS} credits. This is ONE operation; no retry."
echo

cat > "${TMP}/req.json" <<JSON
{
  "input_task_id": "${TASK_IN}",
  "target_formats": ["glb"],
  "topology": "quad",
  "target_polycount": ${TARGET_POLYCOUNT}
}
JSON

curl -sS -X POST "${API}/remesh" \
     -H "Authorization: Bearer ${MESHY_API_KEY}" \
     -H "Content-Type: application/json" \
     -d @"${TMP}/req.json" \
     -o "${TMP}/create.json" 2>"${TMP}/create.err" || { redact < "${TMP}/create.err" >&2; exit 4; }

TASK_ID="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("result") or d.get("id") or "")' "${TMP}/create.json")"

if [[ -z "$TASK_ID" ]]; then
  echo "No task id returned. Response:" >&2
  redact < "${TMP}/create.json" >&2
  exit 5
fi
echo "Remesh task created: ${TASK_ID}"

# Poll. The task is already paid for at this point; polling is free.
for _ in $(seq 1 120); do
  sleep 5
  curl -sS "${API}/remesh/${TASK_ID}" \
       -H "Authorization: Bearer ${MESHY_API_KEY}" \
       -o "${TMP}/task.json" 2>"${TMP}/task.err" || { redact < "${TMP}/task.err" >&2; exit 6; }
  STATUS="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("status",""))' "${TMP}/task.json")"
  echo "  status=${STATUS}"
  [[ "$STATUS" == "SUCCEEDED" || "$STATUS" == "FAILED" ]] && break
done

python3 - "${TMP}/task.json" "$MAX_CREDITS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); cap = int(sys.argv[2])
used = d.get("consumed_credits")
print(f"\nstatus           : {d.get('status')}")
print(f"consumed_credits : {used}")
if isinstance(used, int) and used > cap:
    print(f"!! OVER THE AUTHORISED CEILING of {cap}. Report this before any further operation.")
if d.get("status") != "SUCCEEDED":
    print("task_error       :", d.get("task_error"))
    print("\nFAILED. Do NOT retry automatically — a retry needs a new approval.")
PY

STATUS="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("status",""))' "${TMP}/task.json")"
[[ "$STATUS" == "SUCCEEDED" ]] || exit 7

URL="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1])); u=d.get("model_urls") or {}
print(u.get("glb") or "")' "${TMP}/task.json")"
[[ -n "$URL" ]] || { echo "SUCCEEDED but no glb url in the response" >&2; exit 8; }

mkdir -p "$(dirname "$OUT")"
curl -sS -L "$URL" -o "$OUT"
echo
echo "Saved: ${OUT}  ($(du -h "$OUT" | cut -f1))"
echo "STOP. Rigging is a separate operation and needs its own approval."
