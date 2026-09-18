#!/usr/bin/env bash
# Is a given Meshy id usable as `input_task_id`? ZERO CREDITS — GET retrieves only.
#
# Usage:  ./tools/meshy_validate_task.sh <id>
#
# WHY THIS EXISTS
# A id copied out of the Meshy **web studio** URL is not automatically an
# `input_task_id`. The openapi surface only sees tasks that the API itself
# created: `tools/meshy_find_task.sh` proved the task LISTINGS for this key are
# empty even though the studio clearly holds the assets. So before spending a
# credit on Remesh we ask the one question that settles it for free:
#
#   does GET <pipeline>/<id> return the task?
#
# Retrieving a task consumes no credits. If every pipeline 404s, the id is not
# visible to the API and Remesh would fail on it — that is a STOP, not a retry.
#
# EXIT CODES
#   0  retrievable on at least one pipeline -> candidate for input_task_id
#   1  retrievable nowhere                  -> STOP, do not call Remesh
#   2  usage error
#   3  MESHY_API_KEY missing
#
# SECURITY
# The key comes from the environment straight into curl's -H. Never echoed,
# never written to a file, never in a URL. Do NOT add `set -x` or `curl -v`.

set -euo pipefail
set +x

ID="${1:-}"
if [[ -z "$ID" ]]; then
  echo "usage: $0 <meshy task id>" >&2
  exit 2
fi
if [[ -z "${MESHY_API_KEY:-}" ]]; then
  echo "MESHY_API_KEY is not set in this environment." >&2
  exit 3
fi

# Refuse an unsubstituted placeholder rather than sending it as if it were an id.
if [[ "$ID" == *"<"*">"* || "$ID" == *PASTE* ]]; then
  echo "That looks like an unsubstituted placeholder, not an id: ${ID}" >&2
  echo "Nothing was sent. Paste the real id and re-run." >&2
  exit 2
fi

# The all-zeros sentinel is NOT treated as a lookup by the backend: it returns
# some other real task with HTTP 200 (observed 2026-09-18, it returned the
# SLEEPING baby). Never let that masquerade as a successful validation.
if [[ "$ID" == "00000000-0000-0000-0000-000000000000" ]]; then
  echo "Refusing the all-zeros sentinel UUID: the API answers it with an unrelated task." >&2
  exit 2
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
redact() { sed -e 's/Bearer [A-Za-z0-9._-]*/Bearer <redacted>/g'; }

echo "Validating id: ${ID}"
echo "Zero-credit check — GET retrieve only, no Remesh, no generation."
echo

FOUND=0

for SPEC in "text-to-3d:v2" "image-to-3d:v1" "remesh:v1"; do
  KIND="${SPEC%%:*}"; VER="${SPEC##*:}"
  CODE="$(curl -sS "https://api.meshy.ai/openapi/${VER}/${KIND}/${ID}" \
       -H "Authorization: Bearer ${MESHY_API_KEY}" \
       -o "${TMP}/r.json" -w '%{http_code}' 2>"${TMP}/r.err")" || {
         echo "--- ${KIND} (${VER}): request failed"
         redact < "${TMP}/r.err" >&2 || true
         continue
       }

  if [[ "$CODE" != "200" ]]; then
    printf -- "--- %-12s (%s): HTTP %s  " "$KIND" "$VER" "$CODE"
    python3 -c '
import json,sys
try: print(str(json.load(open(sys.argv[1])).get("message",""))[:100])
except Exception: print("")' "${TMP}/r.json"
    continue
  fi

  # A 200 is NOT proof on its own. The backend can answer with a DIFFERENT task
  # than the one asked for, so the returned id must echo the requested id before
  # anything is believed. This check is what stops a credit being spent on the
  # wrong character.
  ECHOED="$(python3 -c '
import json,sys
try: print(json.load(open(sys.argv[1])).get("id") or "")
except Exception: print("")' "${TMP}/r.json")"
  if [[ "$ECHOED" != "$ID" ]]; then
    echo "--- ${KIND} (${VER}): HTTP 200 but the response is for a DIFFERENT task"
    echo "      requested : ${ID}"
    echo "      returned  : ${ECHOED}"
    echo "      -> NOT a validation. Ignoring this pipeline."
    echo
    continue
  fi

  echo "--- ${KIND} (${VER}): HTTP 200 — RETRIEVED, id echoes correctly"
  FOUND=1
  python3 - "${TMP}/r.json" <<'PY'
import json, sys, datetime
d = json.load(open(sys.argv[1]))
def when(v):
    if v is None: return "-"
    try:
        if isinstance(v,(int,float)):
            return f"{datetime.datetime.fromtimestamp(v/1000, datetime.timezone.utc):%Y-%m-%d %H:%M:%SZ}"
        return str(v)
    except Exception: return str(v)
print(f"      id         : {d.get('id')}")
print(f"      status     : {d.get('status')}")
print(f"      created_at : {when(d.get('created_at'))}")
print(f"      mode       : {d.get('mode','-')}")
print(f"      prompt     : {str(d.get('prompt',''))[:90]!r}")
print(f"      thumbnail  : {d.get('thumbnail_url','-')}")
urls = d.get("model_urls") or {}
print(f"      model_urls : {', '.join(sorted(urls)) if urls else '-'}")
art = d.get("art_style") or d.get("texture_richness")
if art: print(f"      art_style  : {art}")
PY
  echo
done

if [[ "$FOUND" == "1" ]]; then
  # Pull the preview image down so the pose can actually be LOOKED AT. The prompt
  # text alone has already proved able to distinguish the four assets (pose and
  # onesie colour differ), but the picture is the final word.
  THUMB="$(python3 -c '
import json,sys
try: print(json.load(open(sys.argv[1])).get("thumbnail_url") or "")
except Exception: print("")' "${TMP}/r.json")"
  if [[ -n "$THUMB" ]]; then
    SHOT="/tmp/meshy_validate_${ID}.png"
    curl -sS -L "$THUMB" -o "$SHOT" && echo "preview saved: ${SHOT}"
  fi
  cat <<'NOTE'

RESULT: the id is retrievable AND echoes back correctly — a genuine candidate.
This is still NOT permission to spend a credit. Confirm by eye first:
  - created_at is ~2026-09-18 08:30:52Z
  - status is SUCCEEDED
  - the preview shows the STANDING baby: BLUE onesie + hair curl, upright pose
  - it is NOT the sleeping baby (white onesie, pastel stars, lying down),
    the seated baby, or pinkGirl
NOTE
  exit 0
fi

cat <<'NOTE'
RESULT: the id is retrievable on NO pipeline.
It is not visible to this API key, so Remesh would fail on it.
STOP. Do not call Remesh. Do not mutate the id and try again.
NOTE
exit 1
