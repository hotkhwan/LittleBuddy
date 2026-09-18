#!/usr/bin/env bash
# Resolve the Meshy input_task_id for a local GLB. ZERO CREDITS — list queries only.
#
# Usage:  ./tools/meshy_find_task.sh 0918083052
#         (the 10-digit stamp from the downloaded filename)
#
# WHY THIS EXISTS
# A downloaded Meshy GLB carries no task id — its only metadata is
# `asset.generator = pygltflib`. The Remesh and Rigging endpoints want an
# `input_task_id` (the alternative, `model_url`, must be publicly reachable, and
# publishing a paid asset to a public URL is not something to do casually).
#
# !! SUPERSEDED 2026-09-18 — THE MATCH KEY BELOW IS UNSOUND. !!
# The stamp is the DOWNLOAD time, not created_at, and the lag is variable
# (132s / 155s / 56s / 421s for the four assets). Three of four fall outside the
# +/-120s window, so this script cannot find the standing baby even when the
# listings work. The listings also return empty for this key regardless.
#
# USE INSTEAD: the download-provenance xattr on the downloaded GLB, which carries
# the task id and the pose-stamped filename in one URL:
#   xattr -p com.apple.metadata:kMDItemWhereFroms -x <file.glb>
#   -> https://assets.meshy.ai/uploads/converted/<TASK_ID>/<name>_<stamp>_texture.glb
# Then verify with tools/meshy_validate_task.sh <id> and LOOK at the preview.
# Verified ids are tabulated in docs/MESHY_CREDIT_LEDGER.md.
#
# THE MATCH KEY, and why it is provable rather than a guess
# The filename stamp is MMDDHHMMSS in **UTC**. Verified against all four assets:
# the local download time is exactly +7h (Asia/Bangkok) with minutes and seconds
# matching to within two seconds.
#
#   0918081531 -> 2026-09-18 08:15:31Z   downloaded 15:15:33   pinkGirl
#   0918083052 -> 2026-09-18 08:30:52Z   downloaded 15:30:53   baby standing
#   0918083143 -> 2026-09-18 08:31:43Z   downloaded 15:31:44   baby seated
#   0918083218 -> 2026-09-18 08:32:18Z   downloaded 15:32:19   baby sleeping
#
# Four independent stamps agreeing to the second is a strong key. This script
# still prints EVERY candidate inside the window and refuses to pick when more
# than one matches — "do not guess if ambiguous" is the instruction.
#
# SECURITY
# The key is read from the environment and passed straight to curl. It is never
# echoed, never written to a file, never placed in a URL. Do NOT add `set -x`
# and do NOT add `curl -v`: both would put the Authorization header on stdout.

set -euo pipefail
set +x

STAMP="${1:-}"
if [[ -z "$STAMP" ]]; then
  echo "usage: $0 <10-digit filename stamp, e.g. 0918083052>" >&2
  exit 2
fi
if [[ -z "${MESHY_API_KEY:-}" ]]; then
  echo "MESHY_API_KEY is not set in this environment." >&2
  echo "Export it in the shell that runs this script, then re-run." >&2
  exit 3
fi

MM="${STAMP:0:2}"; DD="${STAMP:2:2}"; HH="${STAMP:4:2}"; MI="${STAMP:6:2}"; SS="${STAMP:8:2}"
TARGET="2026-${MM}-${DD}T${HH}:${MI}:${SS}Z"
echo "Looking for a task created at ~${TARGET} (UTC), +/- 120s"
echo

API="https://api.meshy.ai/openapi/v1"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Listing tasks consumes no credits.
#
# NOTE ON PATHS: text-to-3d lives under v2, image-to-3d under v1. Using v1 for
# text-to-3d returns 404 NoMatchingRoute, and because curl exits 0 on an HTTP
# error the old version of this script swallowed that and printed a misleading
# "0 task(s) listed". That is why the http status is now captured and checked.
for SPEC in "text-to-3d:v2" "image-to-3d:v1"; do
  KIND="${SPEC%%:*}"; VER="${SPEC##*:}"
  echo "--- ${KIND} (${VER}) ---"
  CODE="$(curl -sS -G "https://api.meshy.ai/openapi/${VER}/${KIND}" \
       -H "Authorization: Bearer ${MESHY_API_KEY}" \
       --data-urlencode "page_num=1" \
       --data-urlencode "page_size=50" \
       --data-urlencode "sort_by=-created_at" \
       -o "${TMP}/${KIND}.json" -w '%{http_code}' 2>"${TMP}/${KIND}.err")" || {
         echo "  request failed (see below); continuing"
         sed -e 's/Bearer [A-Za-z0-9._-]*/Bearer <redacted>/g' "${TMP}/${KIND}.err" >&2 || true
         continue
       }
  if [[ "$CODE" != "200" ]]; then
    echo "  HTTP ${CODE} — this is NOT an empty result, it is a failed request:"
    sed -e 's/Bearer [A-Za-z0-9._-]*/Bearer <redacted>/g' "${TMP}/${KIND}.json" | head -c 400
    echo; echo
    continue
  fi
  TARGET="$TARGET" python3 - "${TMP}/${KIND}.json" <<'PY'
import json, sys, os, datetime
target = os.environ["TARGET"]
t = datetime.datetime.strptime(target, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
try:
    raw = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"  could not parse response: {e}"); raise SystemExit
items = raw if isinstance(raw, list) else raw.get("result") or raw.get("data") or []
if not isinstance(items, list):
    print("  unexpected response shape; keys:", list(raw)[:8]); raise SystemExit
hits = []
for it in items:
    ca = it.get("created_at")
    if ca is None: continue
    try:
        when = (datetime.datetime.fromtimestamp(ca/1000, datetime.timezone.utc)
                if isinstance(ca, (int, float))
                else datetime.datetime.fromisoformat(str(ca).replace("Z", "+00:00")))
    except Exception:
        continue
    if abs((when - t).total_seconds()) <= 120:
        hits.append((abs((when - t).total_seconds()), it, when))
if not items:
    print("  the API returned an EMPTY task list for this key — no history to match against.")
    print("  (openapi listings only surface tasks CREATED VIA THE API; anything made in the")
    print("   Meshy web studio, or under another account/workspace, will never appear here.)")
elif not hits:
    print(f"  {len(items)} task(s) listed, none within 120s of the target")
for d, it, when in sorted(hits):
    print(f"  MATCH  id={it.get('id')}  created={when:%Y-%m-%d %H:%M:%SZ}  "
          f"delta={d:.0f}s  status={it.get('status')}  mode={it.get('mode','-')}")
    print(f"         prompt={str(it.get('prompt',''))[:90]!r}")
    print(f"         thumbnail={it.get('thumbnail_url','-')}")
PY
  echo
done

cat <<'NOTE'
NEXT
  Exactly one MATCH  -> that is the input_task_id. Confirm the thumbnail really
                        shows the standing baby before using it.
  More than one      -> AMBIGUOUS. Stop and report; do not pick one.
  None               -> the task may be older than the listing window, or these
                        were generated in a different account. Stop and report.
  Empty list         -> the assets were not created through the API, so no
                        input_task_id exists to be found here. The id has to come
                        from the Meshy web studio task URL. Stop and ask the owner.
NOTE
