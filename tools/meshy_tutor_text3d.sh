#!/usr/bin/env bash
#
# Text-to-3D teaching props for Aliz Tutor Mode (Smart Topology tier).
#
#   tools/meshy_tutor_text3d.sh balance                                   # zero credits
#   tools/meshy_tutor_text3d.sh preview <assetId> "<prompt>" --yes        # 5 credits
#   tools/meshy_tutor_text3d.sh refine  <assetId> <previewTaskId> "<texture prompt>" --yes   # 10 credits
#   tools/meshy_tutor_text3d.sh poll    <taskId>                          # zero credits
#   tools/meshy_tutor_text3d.sh wait    <taskId>                          # zero credits, polls to completion
#   tools/meshy_tutor_text3d.sh thumb   <taskId> <out.png>                # zero credits
#   tools/meshy_tutor_text3d.sh fetch   <taskId> <outputStem>             # zero credits
#
# Modelled on tools/meshy_aliz_apose.sh. Every guard there is kept here, because
# every one of them is a thing that has already gone wrong on this project:
#
#   1. `curl` exits 0 on an HTTP error. Every call captures the status code.
#   2. A hardcoded output path silently overwrote a paid-for GLB. Nothing here
#      writes over an existing file; the stem is caller-supplied.
#   3. The all-zeros sentinel UUID is answered with an UNRELATED real task, and
#      an id echo mismatch is possible. Both are refused before anything is read.
#   4. A paid call is never retried by this script. A failure exits non-zero and
#      the ledger row is written by hand.
#   5. Balance is printed BEFORE and AFTER every paid call so the spend is a
#      measured delta, not an assumption.
#
# The one deliberate difference: the typed `YES` prompt is replaced by an
# explicit `--yes` flag, because this runs unattended. Without the flag the
# script prints what it WOULD send and exits 2 without touching the API.
#
# It never prints, logs or persists MESHY_API_KEY, and it never writes a signed
# CDN URL to a file inside the repo.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${REPO}/game/assets_source/meshy/tutor"
LEDGER="${REPO}/docs/MESHY_CREDIT_LEDGER.md"
API='https://api.meshy.ai/openapi/v2/text-to-3d'

# Sprint ceiling (owner-set), and the per-asset hard stop from the brief.
SPRINT_CEILING=100
PER_ASSET_STOP=40
# Live price list, docs.meshy.ai/en/api/pricing, read 2026-09-20.
PREVIEW_COST=5    # model_type smart-topology, ai_model meshy-t2
REFINE_COST=10    # texture_resolution 2k

# Triangle budget asked for at generation time (props gate is 3,000).
TARGET_POLYCOUNT="${TUTOR_TARGET_POLYCOUNT:-2800}"

STYLE="Cute pastel toy-like, soft rounded shapes, low-poly friendly, single object on a plain background, no text except numerals, bright but soft colours matching a storybook children's game."

SENTINEL='00000000-0000-0000-0000-000000000000'

die() { echo "ERROR: $*" >&2; exit 1; }

require_key() {
  [[ -n "${MESHY_API_KEY:-}" ]] || die "MESHY_API_KEY is not set in this shell.
  Set it and re-run:   export MESHY_API_KEY=...
  Do not paste the key into a chat transcript or a file."
}

redact() { sed -e 's/Bearer [A-Za-z0-9._-]*/Bearer <redacted>/g'; }

# `api` runs inside `$(...)` so a plain variable would die with the subshell;
# the status travels through a file instead. (The reference script's
# HTTP_CODE-in-a-subshell pattern was latent: it had never run with a key.)
STATUS_FILE="$(mktemp)"
trap 'rm -f "$STATUS_FILE"' EXIT

api() {  # api <METHOD> <URL> [json-body] -> prints body; status via http_code
  local method="$1" url="$2" body="${3:-}"
  local tmp; tmp="$(mktemp)"
  if [[ -n "$body" ]]; then
    curl -sS -X "$method" "$url" \
      -H "Authorization: Bearer ${MESHY_API_KEY}" \
      -H 'Content-Type: application/json' \
      -d "$body" -o "$tmp" -w '%{http_code}' >"$STATUS_FILE" 2>/dev/null || echo 000 >"$STATUS_FILE"
  else
    curl -sS -X "$method" "$url" \
      -H "Authorization: Bearer ${MESHY_API_KEY}" \
      -o "$tmp" -w '%{http_code}' >"$STATUS_FILE" 2>/dev/null || echo 000 >"$STATUS_FILE"
  fi
  cat "$tmp"; rm -f "$tmp"
}
http_code() { tr -dc '0-9' <"$STATUS_FILE"; }

balance() {
  local body; body="$(api GET 'https://api.meshy.ai/openapi/v1/balance')"
  if [[ "$(http_code)" != "200" ]]; then
    echo "$body" | redact >&2
    die "balance check failed with HTTP $(http_code)"
  fi
  python3 -c 'import json,sys; print(json.load(sys.stdin).get("balance","?"))' <<<"$body"
}

cmd_balance() { echo "Meshy balance: $(balance) credits   ($(date -u +%FT%TZ))"; }

check_task_id() {
  local id="$1"
  [[ -n "$id" ]] || die "missing task id"
  [[ "$id" != "$SENTINEL" ]] \
    || die "refusing the all-zeros sentinel: the API answers it with an unrelated task"
  [[ "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] \
    || die "not a UUID: ${id}"
}

# Sends ONE paid request. $1 = human label, $2 = JSON payload, $3 = expected cost,
# $4 = "--yes" or anything else.
paid_call() {
  local label="$1" payload="$2" cost="$3" flag="$4"
  local before; before="$(balance)"
  echo "Balance BEFORE: ${before} credits   (sprint ceiling ${SPRINT_CEILING}, per-asset stop ${PER_ASSET_STOP})"
  [[ "$before" -ge "$cost" ]] || die "balance ${before} is below the expected cost ${cost}"
  [[ "$cost" -le "$PER_ASSET_STOP" ]] || die "expected cost ${cost} exceeds the per-asset stop ${PER_ASSET_STOP}"

  echo
  echo "About to spend ~${cost} credits on ONE ${label}."
  echo "  endpoint : POST ${API}"
  echo "  payload  :"
  echo "$payload" | python3 -m json.tool | sed 's/^/             /'
  if [[ "$flag" != "--yes" ]]; then
    echo
    echo "Dry run: pass --yes as the last argument to actually send it. Nothing was sent."
    exit 2
  fi

  local body; body="$(api POST "$API" "$payload")"
  if [[ "$(http_code)" != "200" && "$(http_code)" != "202" ]]; then
    echo "$body" | redact >&2
    die "${label} refused with HTTP $(http_code). NOT retrying -- read the error above and write the ledger row."
  fi
  local task_id; task_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("result",""))' <<<"$body")"
  [[ -n "$task_id" ]] || { echo "$body" | redact >&2; die "no task id in the response"; }

  echo
  echo "Task: ${task_id}   ($(date -u +%FT%TZ))"
  local after; after="$(balance)"
  echo "Balance AFTER : ${after} credits   (was ${before}, delta $((before - after)))"
  echo "Record the row in ${LEDGER}."
  echo "TASK_ID=${task_id}"
}

cmd_preview() {
  local asset_id="${1:-}" prompt="${2:-}" flag="${3:-}"
  [[ -n "$asset_id" && -n "$prompt" ]] || die "usage: $0 preview <assetId> \"<prompt>\" [--yes]"
  local full="${prompt} ${STYLE}"
  (( ${#full} <= 800 )) || die "prompt is ${#full} chars; the API limit is 800"

  local payload; payload="$(python3 - "$full" "$TARGET_POLYCOUNT" <<'PY'
import json, sys
print(json.dumps({
    "mode": "preview",
    "prompt": sys.argv[1],
    "ai_model": "meshy-t2",
    "model_type": "smart-topology",
    "topology": "triangle",
    "target_polycount": int(sys.argv[2]),
    "target_formats": ["glb"],
    "origin_at": "bottom",
    "moderation": False,
}))
PY
)"
  echo "asset: ${asset_id}"
  paid_call "text-to-3D PREVIEW (smart-topology, ${TARGET_POLYCOUNT} tris)" "$payload" "$PREVIEW_COST" "$flag"
}

cmd_refine() {
  local asset_id="${1:-}" preview_id="${2:-}" tex_prompt="${3:-}" flag="${4:-}"
  [[ -n "$asset_id" && -n "$preview_id" ]] || die "usage: $0 refine <assetId> <previewTaskId> \"<texture prompt>\" [--yes]"
  check_task_id "$preview_id"
  local full="${tex_prompt} ${STYLE}"
  (( ${#full} <= 800 )) || die "texture prompt is ${#full} chars; the API limit is 800"

  # Refuse to refine a preview that is not SUCCEEDED, or that is not the id we asked for.
  local body; body="$(api GET "${API}/${preview_id}")"
  [[ "$(http_code)" == "200" ]] || { echo "$body" | redact >&2; die "preview lookup HTTP $(http_code)"; }
  python3 -c '
import json, sys
want = sys.argv[1]; d = json.load(sys.stdin)
got = d.get("id", "")
if got != want: sys.exit("REFUSING: asked for %s, the API answered with %s" % (want, got))
if d.get("status") != "SUCCEEDED": sys.exit("REFUSING: preview status is %s, not SUCCEEDED" % d.get("status"))
' "$preview_id" <<<"$body"

  local payload; payload="$(python3 - "$preview_id" "$full" <<'PY'
import json, sys
print(json.dumps({
    "mode": "refine",
    "preview_task_id": sys.argv[1],
    "enable_pbr": False,
    "texture_resolution": "2k",
    "texture_prompt": sys.argv[2],
    "target_formats": ["glb"],
    "origin_at": "bottom",
    "moderation": False,
}))
PY
)"
  echo "asset: ${asset_id}"
  paid_call "text-to-3D REFINE (2k texture, no PBR)" "$payload" "$REFINE_COST" "$flag"
}

# Prints status/progress; echoes id compared. Sets STATUS for `wait`.
cmd_poll() {
  local task_id="${1:-}"
  check_task_id "$task_id"
  local body; body="$(api GET "${API}/${task_id}")"
  [[ "$(http_code)" == "200" ]] || { echo "$body" | redact >&2; die "HTTP $(http_code)"; }
  STATUS="$(python3 -c '
import json, sys
want = sys.argv[1]
d = json.load(sys.stdin)
got = d.get("id", "")
if got and got != want:
    sys.exit("REFUSING: asked for %s, the API answered with %s" % (want, got))
print("status   :", d.get("status"), file=sys.stderr)
print("progress :", d.get("progress"), file=sys.stderr)
print("credits  :", d.get("consumed_credits"), file=sys.stderr)
if d.get("task_error"): print("error    :", d["task_error"], file=sys.stderr)
u = (d.get("model_urls") or {}).get("glb")
print("glb ready:", "yes" if u else "no", file=sys.stderr)
print(d.get("status"))
' "$task_id" <<<"$body")"
}

cmd_wait() {
  local task_id="${1:-}" tries=0
  check_task_id "$task_id"
  while :; do
    cmd_poll "$task_id"
    case "$STATUS" in
      SUCCEEDED) echo "SUCCEEDED ($(date -u +%FT%TZ))"; return 0 ;;
      FAILED|CANCELED) die "task ${task_id} ended ${STATUS}. NOT retrying." ;;
    esac
    tries=$((tries + 1))
    (( tries < 120 )) || die "gave up waiting after $((tries * 10))s; poll by hand"
    sleep 10
  done
}

# Thumbnail for the look-at-it review before paying for refine. Zero credits.
cmd_thumb() {
  local task_id="${1:-}" out="${2:-}"
  check_task_id "$task_id"
  [[ -n "$out" ]] || die "usage: $0 thumb <taskId> <out.png>"
  [[ ! -e "$out" ]] || die "refusing to overwrite an existing file: ${out}"
  local body; body="$(api GET "${API}/${task_id}")"
  [[ "$(http_code)" == "200" ]] || { echo "$body" | redact >&2; die "HTTP $(http_code)"; }
  local url; url="$(python3 -c '
import json,sys
want=sys.argv[1]; d=json.load(sys.stdin)
if d.get("id","") != want: sys.exit("REFUSING: id mismatch")
print(d.get("thumbnail_url",""))' "$task_id" <<<"$body")"
  [[ -n "$url" ]] || die "no thumbnail yet"
  curl -sS -o "$out" "$url" || die "thumbnail download failed"
  echo "Wrote ${out} ($(wc -c <"$out") bytes). The signed URL was NOT written to any file."
}

cmd_fetch() {
  local task_id="${1:-}" stem="${2:-}"
  check_task_id "$task_id"
  [[ -n "$stem" ]] || die "usage: $0 fetch <taskId> <outputStem>"
  local target="${OUT_DIR}/${stem}.glb"
  [[ ! -e "$target" ]] || die "refusing to overwrite an existing file: ${target}
  Choose a different stem."

  local body; body="$(api GET "${API}/${task_id}")"
  [[ "$(http_code)" == "200" ]] || { echo "$body" | redact >&2; die "HTTP $(http_code)"; }
  local url; url="$(python3 -c '
import json,sys
want=sys.argv[1]; d=json.load(sys.stdin)
if d.get("id","") != want: sys.exit("REFUSING: id mismatch")
print((d.get("model_urls") or {}).get("glb",""))' "$task_id" <<<"$body")"
  [[ -n "$url" ]] || die "no glb url yet -- wait until SUCCEEDED"

  mkdir -p "$OUT_DIR"
  curl -sS -o "$target" "$url" || die "download failed"
  echo "Wrote ${target} ($(wc -c <"$target") bytes)"
  echo "The signed URL was NOT written to any file."
  echo "Next:  python3 tools/glb_inspect.py '${target}'"
}

case "${1:-}" in
  balance) require_key; cmd_balance ;;
  preview) require_key; shift; cmd_preview "$@" ;;
  refine)  require_key; shift; cmd_refine "$@" ;;
  poll)    require_key; shift; cmd_poll "$@" ;;
  wait)    require_key; shift; cmd_wait "$@" ;;
  thumb)   require_key; shift; cmd_thumb "$@" ;;
  fetch)   require_key; shift; cmd_fetch "$@" ;;
  *) sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
