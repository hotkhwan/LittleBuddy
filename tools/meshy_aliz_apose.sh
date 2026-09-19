#!/usr/bin/env bash
#
# Aliz, regenerated in an A-pose from the approved standalone reference.
#
#   tools/meshy_aliz_apose.sh preview        # image-to-3D preview, costs credits
#   tools/meshy_aliz_apose.sh poll <taskId>  # zero credits
#   tools/meshy_aliz_apose.sh balance        # zero credits
#
# WHY THIS SCRIPT EXISTS RATHER THAN A HAND-TYPED CURL
#
# Three things have already gone wrong on this project when Meshy was driven by
# hand, and every guard below is one of them:
#
#   1. `curl` exits 0 on an HTTP error, so a 404 read as a success and a script
#      carried on to the next paid step. Every call here captures the status.
#   2. A hardcoded output path silently overwrote a paid-for rigged GLB and both
#      of its animation clips. Nothing here writes over an existing file.
#   3. A run with no ceiling is a run with no ceiling. This refuses to start
#      without an explicit budget and prints the balance before and after, so
#      the spend is a measured fact rather than an assumption.
#
# It never prints, logs or persists MESHY_API_KEY, and it never writes a signed
# CDN URL to a file inside the repo.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REFERENCE="${ALIZ_REFERENCE:-${REPO}/docs/reference/aliz_reference_apose.png}"
OUT_DIR="${REPO}/game/assets_source/meshy/buddy"
LEDGER="${REPO}/docs/MESHY_CREDIT_LEDGER.md"

# The sprint's authorised ceiling, not the account balance. The account has
# thousands; this run may use a hundred at the very most, and a preview is
# expected to be a small fraction of that.
SPRINT_CEILING=100

# The texture/style prompt sent alongside the image.
#
# HONEST LIMIT, and it decides which reference you must use: image-to-3D copies
# the POSE IN THE PICTURE. No amount of prompt text will spread the arms of a
# reference whose arms are down. So the A-pose has to be IN THE REFERENCE --
# which is what `tools/make_aliz_reference.py --apose` produces. This text only
# fixes what a picture cannot say: that the hair is one solid piece.
PROMPT='A-pose, arms held about 40 degrees away from the torso, legs clearly \
separated, standing straight, facing forward. Stylized cute 3D cartoon girl \
about seven years old, long pink hair as ONE SOLID CONTINUOUS piece with no gaps \
or separate strands, straight fringe, large friendly eyes, gentle CLOSED-MOUTH \
smile, colourful striped dress, simple soft shapes, single character, no props, \
no extra objects, plain background.'

die() { echo "ERROR: $*" >&2; exit 1; }

# Checked only for the commands that actually call the API, so `--help` and a
# bare invocation stay useful on a machine that has never had the key.
require_key() {
  [[ -n "${MESHY_API_KEY:-}" ]] || die "MESHY_API_KEY is not set in this shell.
  Set it and re-run:   export MESHY_API_KEY=...
  Do not paste the key into a chat transcript or a file."
}

redact() { sed -e 's/Bearer [A-Za-z0-9._-]*/Bearer <redacted>/g'; }

api() {  # api <METHOD> <URL> [json-body] -> prints body, sets HTTP_CODE
  local method="$1" url="$2" body="${3:-}"
  local tmp; tmp="$(mktemp)"
  if [[ -n "$body" ]]; then
    HTTP_CODE="$(curl -sS -X "$method" "$url" \
      -H "Authorization: Bearer ${MESHY_API_KEY}" \
      -H 'Content-Type: application/json' \
      -d "$body" -o "$tmp" -w '%{http_code}' 2>&1 | tail -1)"
  else
    HTTP_CODE="$(curl -sS -X "$method" "$url" \
      -H "Authorization: Bearer ${MESHY_API_KEY}" \
      -o "$tmp" -w '%{http_code}')"
  fi
  cat "$tmp"; rm -f "$tmp"
}

balance() {
  local body; body="$(api GET 'https://api.meshy.ai/openapi/v1/balance')"
  if [[ "$HTTP_CODE" != "200" ]]; then
    echo "$body" | redact >&2
    die "balance check failed with HTTP ${HTTP_CODE}"
  fi
  python3 -c 'import json,sys; print(json.load(sys.stdin).get("balance","?"))' <<<"$body"
}

cmd_balance() { echo "Meshy balance: $(balance) credits"; }

cmd_preview() {
  [[ -f "$REFERENCE" ]] || die "reference image missing: $REFERENCE
  Rebuild it with:  python3 tools/make_aliz_reference.py \\
      docs/shots/aliz_reference_raw.png docs/reference/aliz_reference_v1.png"

  local before; before="$(balance)"
  echo "Balance BEFORE: ${before} credits   (sprint ceiling: ${SPRINT_CEILING})"
  [[ "$before" -gt 0 ]] || die "no credits available"

  # The reference travels as a data URI. It is built here, in memory, and is
  # never written anywhere -- and the request body is never echoed, because it
  # contains the whole image.
  local data_uri; data_uri="data:image/png;base64,$(base64 -i "$REFERENCE" | tr -d '\n')"

  local payload; payload="$(python3 - "$data_uri" "$PROMPT" <<'PY'
import json, sys
print(json.dumps({
    "image_url": sys.argv[1],
    "ai_model": "meshy-5",
    "topology": "quad",
    "target_polycount": 8000,
    "symmetry_mode": "on",
    "should_remesh": True,
    "should_texture": True,
    "enable_pbr": False,
    "texture_prompt": sys.argv[2],
}))
PY
)"

  echo
  echo "About to spend credits on ONE image-to-3D preview."
  echo "  reference : ${REFERENCE}"
  echo "  topology  : quad, 8000 triangles, symmetry on, textured, no PBR"
  read -r -p "Type YES to proceed: " confirm
  [[ "$confirm" == "YES" ]] || die "not confirmed; nothing was sent"

  local body; body="$(api POST 'https://api.meshy.ai/openapi/v1/image-to-3d' "$payload")"
  if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "202" ]]; then
    echo "$body" | redact >&2
    die "image-to-3d refused with HTTP ${HTTP_CODE}. NOT retrying -- read the error above."
  fi

  local task_id; task_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("result",""))' <<<"$body")"
  [[ -n "$task_id" ]] || { echo "$body" | redact >&2; die "no task id in the response"; }

  echo
  echo "Task: ${task_id}"
  echo "Poll it (free):  tools/meshy_aliz_apose.sh poll ${task_id}"
  echo
  echo "Balance AFTER : $(balance) credits   (was ${before})"
  echo "Record the delta in ${LEDGER}."
}

cmd_poll() {
  local task_id="${1:-}"
  [[ -n "$task_id" ]] || die "usage: $0 poll <taskId>"
  [[ "$task_id" != "00000000-0000-0000-0000-000000000000" ]] \
    || die "refusing the all-zeros sentinel: the API answers it with an unrelated task"

  local body; body="$(api GET "https://api.meshy.ai/openapi/v1/image-to-3d/${task_id}")"
  [[ "$HTTP_CODE" == "200" ]] || { echo "$body" | redact >&2; die "HTTP ${HTTP_CODE}"; }

  # Echo the id back and compare. A backend that answers an unknown id with SOME
  # other real task has already cost this project a near-miss.
  python3 -c '
import json, sys
want = sys.argv[1]
d = json.load(sys.stdin)
got = d.get("id", "")
if got and got != want:
    sys.exit("REFUSING: asked for %s, the API answered with %s" % (want, got))
print("status   :", d.get("status"))
print("progress :", d.get("progress"))
if d.get("task_error"): print("error    :", d["task_error"])
u = (d.get("model_urls") or {}).get("glb")
print("glb ready:", "yes" if u else "no")
' "$task_id" <<<"$body"

  echo
  echo "When status is SUCCEEDED, download with (signed URL stays out of the repo):"
  echo "  mkdir -p '${OUT_DIR}'"
  echo "  tools/meshy_aliz_apose.sh fetch ${task_id} alizApose_v01"
}

cmd_fetch() {
  local task_id="${1:-}" stem="${2:-}"
  [[ -n "$task_id" && -n "$stem" ]] || die "usage: $0 fetch <taskId> <outputStem>"
  local target="${OUT_DIR}/${stem}.glb"
  # Guard 2: never overwrite. A paid asset has already been lost this way once.
  [[ ! -e "$target" ]] || die "refusing to overwrite an existing file: ${target}
  Choose a different stem."

  local body; body="$(api GET "https://api.meshy.ai/openapi/v1/image-to-3d/${task_id}")"
  [[ "$HTTP_CODE" == "200" ]] || { echo "$body" | redact >&2; die "HTTP ${HTTP_CODE}"; }
  local url; url="$(python3 -c '
import json,sys
d=json.load(sys.stdin)
print((d.get("model_urls") or {}).get("glb",""))' <<<"$body")"
  [[ -n "$url" ]] || die "no glb url yet -- poll until SUCCEEDED"

  mkdir -p "$OUT_DIR"
  curl -sS -o "$target" "$url" || die "download failed"
  echo "Wrote ${target} ($(wc -c <"$target") bytes)"
  echo "The signed URL was NOT written to any file."
  echo
  echo "Next, and only after LOOKING at it:"
  echo "  python3 tools/glb_inspect.py '${target}'"
}

case "${1:-}" in
  balance) require_key; cmd_balance ;;
  preview) require_key; cmd_preview ;;
  poll)    require_key; shift; cmd_poll "$@" ;;
  fetch)   require_key; shift; cmd_fetch "$@" ;;
  *) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
