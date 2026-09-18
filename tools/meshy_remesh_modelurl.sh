#!/usr/bin/env bash
# The ONE approved Meshy Remesh, via `model_url`. ONE REQUEST. NO RETRY.
#
#   Approved 2026-09-18 (amended): baby_standing_v01, verified source task
#   01a0b3a1-ca47-72da-85fb-bac548ffdae3, target_polycount 8000, topology quad,
#   format glb, MAXIMUM 10 CREDITS.
#   Rigging, Animation and Generation are NOT approved.
#
# Usage:  ./tools/meshy_remesh_modelurl.sh <verified_task_id>
#
# WHY model_url
# `input_task_id` is refused for this task with "Invalid task mode texture":
# the GET reports mode=preview but the remesh validator sees mode=texture.
# Remesh also accepts `model_url`, and Meshy already serves this exact asset
# from its own CDN, so the URL is fetched from the task record at run time and
# handed straight back to Meshy.
#
# SECRETS
# TWO secrets here, not one:
#   1. MESHY_API_KEY  — from the environment, only ever in a curl -H.
#   2. the signed CDN model_url — a CAPABILITY URL. It is held in a shell
#      variable and written only into a request body inside a mktemp dir that is
#      deleted on exit. It is NEVER echoed and NEVER written into the repo.
# Every byte printed goes through scrub() to strip both. Do NOT add `set -x`,
# do NOT add `curl -v`, and do NOT echo $MODEL_URL when debugging.

set -euo pipefail
set +x

TASK_IN="${1:-}"
OUT="${2:-}"
TARGET_POLYCOUNT="${3:-8000}"
MAX_CREDITS="${4:-10}"

if [[ -z "$TASK_IN" || -z "$OUT" ]]; then
  echo "usage: $0 <verified_task_id> <out.glb> [target_polycount] [max_credits]" >&2
  exit 2
fi
if [[ -z "${MESHY_API_KEY:-}" ]]; then
  echo "MESHY_API_KEY is not set in this environment." >&2
  exit 3
fi

API="https://api.meshy.ai/openapi/v1"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Strip both secrets from anything we print.
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
echo "Source task    : ${TASK_IN}"
echo "Parameters     : topology=quad target_polycount=${TARGET_POLYCOUNT} formats=[glb]"
echo "Ceiling        : ${MAX_CREDITS} credits. ONE request, no retry."
echo

# Pull the signed CDN url out of the verified task. Never printed.
curl -sS "https://api.meshy.ai/openapi/v2/text-to-3d/${TASK_IN}" \
     -H "Authorization: Bearer ${MESHY_API_KEY}" \
     -o "${TMP}/src.json" 2>"${TMP}/src.err" || { scrub < "${TMP}/src.err" >&2; exit 4; }

# Confirm the task still echoes its own id before using its url.
ECHOED="$(python3 -c '
import json,sys
try: print(json.load(open(sys.argv[1])).get("id") or "")
except Exception: print("")' "${TMP}/src.json")"
if [[ "$ECHOED" != "$TASK_IN" ]]; then
  echo "Source task id did not echo back (got: ${ECHOED:-<none>}). Refusing to continue." >&2
  exit 5
fi

MODEL_URL="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print((d.get("model_urls") or {}).get("glb") or "")' "${TMP}/src.json")"
if [[ -z "$MODEL_URL" ]]; then
  echo "No glb model_url on the source task. Stopping." >&2
  exit 6
fi
echo "Resolved source glb url from the verified task (value withheld)."

python3 - "$MODEL_URL" "$TARGET_POLYCOUNT" > "${TMP}/req.json" <<'PY'
import json, sys
json.dump({
    "model_url": sys.argv[1],
    "target_formats": ["glb"],
    "topology": "quad",
    "target_polycount": int(sys.argv[2]),
}, open(sys.stdout.fileno(), "w"))
PY

CODE="$(curl -sS -X POST "${API}/remesh" \
     -H "Authorization: Bearer ${MESHY_API_KEY}" \
     -H "Content-Type: application/json" \
     -d @"${TMP}/req.json" \
     -o "${TMP}/create.json" -w '%{http_code}' 2>"${TMP}/create.err")" \
     || { scrub < "${TMP}/create.err" >&2; exit 7; }

if [[ "$CODE" != "200" && "$CODE" != "201" && "$CODE" != "202" ]]; then
  echo "Meshy REJECTED the request (HTTP ${CODE}):"
  scrub < "${TMP}/create.json"
  echo
  echo "Balance AFTER : $(balance)  (was ${BAL_BEFORE})"
  echo "STOPPING as instructed. No retry."
  exit 8
fi

TASK_ID="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("result") or d.get("id") or "")' "${TMP}/create.json")"
if [[ -z "$TASK_ID" ]]; then
  echo "No task id returned. Response:" >&2
  scrub < "${TMP}/create.json" >&2
  echo "Balance AFTER : $(balance)  (was ${BAL_BEFORE})" >&2
  exit 9
fi
echo "Remesh task created: ${TASK_ID}"

for _ in $(seq 1 120); do
  sleep 5
  curl -sS "${API}/remesh/${TASK_ID}" \
       -H "Authorization: Bearer ${MESHY_API_KEY}" \
       -o "${TMP}/task.json" 2>"${TMP}/task.err" || { scrub < "${TMP}/task.err" >&2; exit 10; }
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
    print(f"!! OVER THE AUTHORISED CEILING of {cap}. Report before any further operation.")
if d.get("status") != "SUCCEEDED":
    print("task_error       :", d.get("task_error"))
    print("\nFAILED. Do NOT retry automatically — a retry needs a new approval.")
PY

STATUS="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("status",""))' "${TMP}/task.json")"
if [[ "$STATUS" != "SUCCEEDED" ]]; then
  echo "Balance AFTER : $(balance)  (was ${BAL_BEFORE})"
  exit 11
fi

URL="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1])); u=d.get("model_urls") or {}
print(u.get("glb") or "")' "${TMP}/task.json")"
[[ -n "$URL" ]] || { echo "SUCCEEDED but no glb url in the response" >&2; exit 12; }

mkdir -p "$(dirname "$OUT")"
curl -sS -L "$URL" -o "$OUT"
echo
echo "Saved: ${OUT}  ($(du -h "$OUT" | cut -f1))"
echo "Balance AFTER : $(balance)  (was ${BAL_BEFORE})"
echo
echo "STOP. Rigging is a separate operation and needs its own approval."
