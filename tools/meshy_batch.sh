#!/usr/bin/env bash
#
# Meshy production pipeline for house props: one asset, end to end.
#
#   balance  -> preview (5) -> wait -> thumbnail review -> refine (10) -> wait
#   -> download GLB -> [split into parts] -> trim to budget -> triangle gate
#   -> optimise (512 texture, section 7 material) -> install into
#      game/assets/models/meshy-props/<asset>/ -> manifest row -> Godot import
#
# Every paid step is ONE call, balance-checked before and after, appended to
# docs/MESHY_CREDIT_LEDGER.md, and refused without --yes. The whole tail after
# the download is local and free, and it runs on any GLB, which is how it is
# tested without credits:
#
#   tools/meshy_batch.sh balance
#   tools/meshy_batch.sh preview <asset> "<prompt>" [--tris 2600] --yes          # 5 credits
#   tools/meshy_batch.sh refine  <asset> <previewTaskId> "<texture prompt>" --yes  # 10 credits
#   tools/meshy_batch.sh wait    <taskId>                                       # free
#   tools/meshy_batch.sh thumb   <taskId> <out.png>                             # free
#   tools/meshy_batch.sh fetch   <asset> <taskId>                               # free -> assets_source
#   tools/meshy_batch.sh install <asset> <in.glb> [--max-tris 1200] [--size 0.30]
#                                [--parts body,lid] [--scale 0.26] [--yaw 0]
#                                [--pivot lid=hingeBack] [--split-args "..."]
#                                [--dest <dir>] [--no-import] [--dry-run]       # free, local
#
# `install --dry-run` runs split/trim/gate/optimise into a scratch directory
# and prints the manifest rows it WOULD write, touching nothing in game/.
# `install --parts a,b` writes one GLB per part (see tools/meshy_split.py);
# openable furniture (fridge, wardrobe, toy box) is installed this way so
# room.gd can hinge the door/lid exactly as it hinges the drawn ones.
# `--pivot lid=hingeBack` writes that part's manifest `pivot` (and checks the
# written file is hung on that edge); `--split-args` hands extra flags to
# meshy_split.py verbatim, e.g. "--rotate-x lid=100.7 --stretch lid=z:1.25
# --part-origin lid=hingeBack --assign 3=lid" to close a lid Meshy drew open.
#
# Key: MESHY_API_KEY from the environment, else the macOS keychain item
# `MESHY_API_KEY` (security find-generic-password -s MESHY_API_KEY -w). The key
# is never printed, logged or written; signed URLs are never written to a file.
#
# Guards carried over from tools/meshy_tutor_text3d.sh, each of which is a thing
# that has already gone wrong on this project: HTTP status captured (curl exits
# 0 on a 4xx), no overwrite of a paid-for file, the all-zeros sentinel refused,
# the answered task id compared to the asked one, no automatic retry of a paid
# call, balance measured before and after rather than assumed.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="${REPO}/tools"
SOURCE_DIR="${REPO}/game/assets_source/meshy/props"      # raw masters, gitignored
PACK_DIR="${REPO}/game/assets/models/meshy-props"          # runtime, committed
MANIFEST="${PACK_DIR}/manifest.json"
LEDGER="${REPO}/docs/MESHY_CREDIT_LEDGER.md"
API='https://api.meshy.ai/openapi/v2/text-to-3d'
BALANCE_API='https://api.meshy.ai/openapi/v1/balance'
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"

# Live price list, docs.meshy.ai/en/api/pricing (read 2026-09-20): Smart
# Topology preview 5, refine at 2k texture 10. 15 per finished asset.
PREVIEW_COST=5
REFINE_COST=10
# Owner's remaining authorisation for this sprint (100 authorised, 60 spent).
AUTHORISED_REMAINING="${MESHY_AUTHORISED_REMAINING:-40}"

# House style, appended to every prompt. No brand, no text, one object.
STYLE="Soft pastel low-poly toy style for a children's storybook game, single object, neutral pose, gently rounded shapes, matte colours, plain background, no text, no logos, no people."

SENTINEL='00000000-0000-0000-0000-000000000000'

die() { echo "ERROR: $*" >&2; exit 1; }
note() { echo "-- $*" >&2; }

# -- Key ---------------------------------------------------------------------

resolve_key() {
  if [[ -z "${MESHY_API_KEY:-}" ]] && command -v security >/dev/null 2>&1; then
    MESHY_API_KEY="$(security find-generic-password -s MESHY_API_KEY -w 2>/dev/null || true)"
  fi
  [[ -n "${MESHY_API_KEY:-}" ]] || die "no MESHY_API_KEY in the environment or the macOS keychain.
  Store it once with:  security add-generic-password -s MESHY_API_KEY -a littledays -w '<key>'
  (or export MESHY_API_KEY=... for this shell). Never paste the key into a chat or a file."
  export MESHY_API_KEY
}

redact() { sed -e 's/Bearer [A-Za-z0-9._-]*/Bearer <redacted>/g' -e 's#https://[^" ]*#<url>#g'; }

# -- HTTP --------------------------------------------------------------------

STATUS_FILE="$(mktemp "${TMPDIR:-/tmp}/meshy-status.XXXXXX")"
trap 'rm -f "$STATUS_FILE"' EXIT

api() {  # api <METHOD> <URL> [json-body] -> body on stdout; status via http_code
  local method="$1" url="$2" body="${3:-}"
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/meshy-response.XXXXXX")"
  local -a extra=()
  [[ -n "$body" ]] && extra=(-H 'Content-Type: application/json' -d "$body")
  # ${extra[@]+"${extra[@]}"}: bash 3.2 (macOS) treats an EMPTY array as unset
  # under `set -u`, so a plain "${extra[@]}" aborts every body-less GET.
  curl -sS -X "$method" "$url" -H "Authorization: Bearer ${MESHY_API_KEY}" ${extra[@]+"${extra[@]}"} \
    -o "$tmp" -w '%{http_code}' >"$STATUS_FILE" 2>/dev/null || echo 000 >"$STATUS_FILE"
  cat "$tmp"; rm -f "$tmp"
}
http_code() { tr -dc '0-9' <"$STATUS_FILE"; }

balance() {
  local body; body="$(api GET "$BALANCE_API")"
  [[ "$(http_code)" == "200" ]] || { echo "$body" | redact >&2; die "balance check failed with HTTP $(http_code)"; }
  python3 -c 'import json,sys; print(json.load(sys.stdin).get("balance","?"))' <<<"$body"
}

cmd_balance() {
  resolve_key
  local now; now="$(balance)"   # a failed read aborts here (set -e), never prints a blank
  echo "Meshy balance: ${now} credits   ($(date -u +%FT%TZ))"
}

check_task_id() {
  local id="$1"
  [[ -n "$id" ]] || die "missing task id"
  [[ "$id" != "$SENTINEL" ]] || die "refusing the all-zeros sentinel: the API answers it with an unrelated task"
  [[ "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || die "not a UUID: ${id}"
}

# -- Ledger ------------------------------------------------------------------

## ledger_row <asset> <operation> <taskId> <est> <actual> <before> <after> <outcome>
ledger_row() {
  local stamp; stamp="$(date -u +%FT%TZ)"
  printf '| %s | %s | %s | %s | %s | %s | %s → %s | `%s` | %s |\n' \
    "B" "$stamp" "$1" "$2" "$4" "$5" "$6" "$7" "$3" "$8" >>"$LEDGER"
  note "ledger row appended to docs/MESHY_CREDIT_LEDGER.md"
}

# -- Paid calls --------------------------------------------------------------

## paid_call <asset> <label> <json-payload> <cost> <flag>
paid_call() {
  local asset="$1" label="$2" payload="$3" cost="$4" flag="$5"
  local before; before="$(balance)"
  echo "Balance BEFORE: ${before} credits"
  echo "Expected cost : ${cost} credits (${label})"
  (( cost <= AUTHORISED_REMAINING )) || die "cost ${cost} exceeds the ${AUTHORISED_REMAINING} credits still authorised. Ask the owner."
  if [[ "$flag" != "--yes" ]]; then
    echo "Would POST to ${API}:"
    echo "$payload" | python3 -m json.tool
    echo "Nothing sent. Re-run with --yes to spend ${cost} credits."
    exit 2
  fi
  local body; body="$(api POST "$API" "$payload")"
  local code; code="$(http_code)"
  if [[ "$code" != "200" && "$code" != "202" ]]; then
    echo "$body" | redact >&2
    ledger_row "$asset" "$label" "-" "$cost" "0" "$before" "$(balance)" "REJECTED HTTP ${code}; nothing charged; NOT retried"
    die "paid call failed with HTTP ${code}. NOT retrying."
  fi
  local task_id; task_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("result",""))' <<<"$body")"
  check_task_id "$task_id"
  sleep 2
  local after; after="$(balance)"
  echo "Task id       : ${task_id}"
  echo "Balance AFTER : ${after} credits  (delta $((before - after)))"
  ledger_row "$asset" "$label" "$task_id" "$cost" "$((before - after))" "$before" "$after" "task created; awaiting result"
  echo "$task_id"
}

cmd_preview() {
  resolve_key
  local asset="${1:-}" prompt="${2:-}"; shift 2 || true
  local tris=2600 flag=""
  while (( $# )); do case "$1" in --tris) tris="$2"; shift 2;; --yes) flag="--yes"; shift;; *) die "unknown arg $1";; esac; done
  [[ -n "$asset" && -n "$prompt" ]] || die "usage: $0 preview <asset> \"<prompt>\" [--tris N] [--yes]"
  local full="${prompt} ${STYLE}"
  (( ${#full} <= 600 )) || die "prompt is ${#full} chars; the API limit is 600"
  local payload; payload="$(python3 - "$full" "$tris" <<'PY'
import json, sys
print(json.dumps({"mode": "preview", "prompt": sys.argv[1], "ai_model": "meshy-t2",
                  "model_type": "smart-topology", "topology": "triangle",
                  "target_polycount": int(sys.argv[2]), "target_formats": ["glb"],
                  "origin_at": "bottom", "moderation": False}))
PY
)"
  echo "asset: ${asset}"
  paid_call "$asset" "text-to-3D preview, smart-topology meshy-t2, ${tris} tris" "$payload" "$PREVIEW_COST" "$flag"
}

cmd_refine() {
  resolve_key
  local asset="${1:-}" preview_id="${2:-}" tex="${3:-}"; shift 3 || true
  local flag=""
  while (( $# )); do case "$1" in --yes) flag="--yes"; shift;; *) die "unknown arg $1";; esac; done
  [[ -n "$asset" && -n "$preview_id" ]] || die "usage: $0 refine <asset> <previewTaskId> \"<texture prompt>\" [--yes]"
  check_task_id "$preview_id"
  local full="${tex} ${STYLE}"
  (( ${#full} <= 800 )) || die "texture prompt is ${#full} chars; the API limit is 800"
  local body; body="$(api GET "${API}/${preview_id}")"
  [[ "$(http_code)" == "200" ]] || { echo "$body" | redact >&2; die "preview lookup HTTP $(http_code)"; }
  python3 -c '
import json, sys
want = sys.argv[1]; d = json.load(sys.stdin)
if d.get("id", "") != want: sys.exit("REFUSING: asked for %s, the API answered with %s" % (want, d.get("id")))
if d.get("status") != "SUCCEEDED": sys.exit("REFUSING: preview status is %s, not SUCCEEDED" % d.get("status"))
' "$preview_id" <<<"$body"
  local payload; payload="$(python3 - "$preview_id" "$full" <<'PY'
import json, sys
print(json.dumps({"mode": "refine", "preview_task_id": sys.argv[1], "enable_pbr": False,
                  "texture_resolution": "2k", "texture_prompt": sys.argv[2],
                  "target_formats": ["glb"], "origin_at": "bottom", "moderation": False}))
PY
)"
  echo "asset: ${asset}"
  paid_call "$asset" "text-to-3D refine, 2k texture, no PBR" "$payload" "$REFINE_COST" "$flag"
}

# -- Free calls --------------------------------------------------------------

cmd_poll() {
  resolve_key
  local task_id="${1:-}"; check_task_id "$task_id"
  local body; body="$(api GET "${API}/${task_id}")"
  [[ "$(http_code)" == "200" ]] || { echo "$body" | redact >&2; die "HTTP $(http_code)"; }
  STATUS="$(python3 -c '
import json, sys
want = sys.argv[1]; d = json.load(sys.stdin)
if d.get("id", "") and d.get("id") != want: sys.exit("REFUSING: asked for %s, the API answered with %s" % (want, d.get("id")))
print("status   :", d.get("status"), " progress:", d.get("progress"), " credits:", d.get("consumed_credits"), file=sys.stderr)
if d.get("task_error"): print("error    :", d["task_error"], file=sys.stderr)
print(d.get("status"))
' "$task_id" <<<"$body")"
}

cmd_wait() {
  local task_id="${1:-}" tries=0
  while :; do
    cmd_poll "$task_id"
    case "$STATUS" in
      SUCCEEDED) echo "SUCCEEDED ($(date -u +%FT%TZ))"; return 0 ;;
      FAILED|CANCELED) die "task ${task_id} ended ${STATUS}. NOT retrying; write the ledger outcome by hand." ;;
    esac
    tries=$((tries + 1)); (( tries < 120 )) || die "gave up after $((tries * 10))s; poll by hand"
    sleep 10
  done
}

## Thumbnail for the look-at-it review BEFORE paying for refine.
cmd_thumb() {
  resolve_key
  local task_id="${1:-}" out="${2:-}"; check_task_id "$task_id"
  [[ -n "$out" && ! -e "$out" ]] || die "usage: $0 thumb <taskId> <new.png>"
  local body; body="$(api GET "${API}/${task_id}")"
  [[ "$(http_code)" == "200" ]] || { echo "$body" | redact >&2; die "HTTP $(http_code)"; }
  local url; url="$(python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("id")==sys.argv[1]; print(d.get("thumbnail_url",""))' "$task_id" <<<"$body")"
  [[ -n "$url" ]] || die "no thumbnail yet"
  curl -sS -o "$out" "$url" || die "thumbnail download failed"
  echo "Wrote ${out} ($(wc -c <"$out") bytes). The signed URL was not written anywhere."
}

## Downloads the refined GLB into assets_source (gitignored). Free.
cmd_fetch() {
  resolve_key
  local asset="${1:-}" task_id="${2:-}"; check_task_id "$task_id"
  [[ -n "$asset" ]] || die "usage: $0 fetch <asset> <taskId>"
  local target="${SOURCE_DIR}/${asset}_v01.glb"
  [[ ! -e "$target" ]] || die "refusing to overwrite ${target}"
  local body; body="$(api GET "${API}/${task_id}")"
  [[ "$(http_code)" == "200" ]] || { echo "$body" | redact >&2; die "HTTP $(http_code)"; }
  local url; url="$(python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("id")==sys.argv[1]; print((d.get("model_urls") or {}).get("glb",""))' "$task_id" <<<"$body")"
  [[ -n "$url" ]] || die "no glb url yet -- wait until SUCCEEDED"
  mkdir -p "$SOURCE_DIR"
  curl -sS -o "$target" "$url" || die "download failed"
  echo "Wrote ${target} ($(wc -c <"$target") bytes). The signed URL was not written anywhere."
  echo "Next: $0 install ${asset} ${target} --max-tris <gate> --size <metres> [--parts ...]"
}

# -- Local tail: split / trim / gate / optimise / install ---------------------

cmd_install() {
  local asset="${1:-}" input="${2:-}"; shift 2 || true
  [[ -n "$asset" && -f "$input" ]] || die "usage: $0 install <asset> <in.glb> [--max-tris N] [--size M] [--parts a,b] [--scale S] [--yaw D] [--task-ids a,b] [--dest DIR] [--no-import] [--dry-run]"
  local max_tris=3000 size="" parts="" scale=1.0 yaw=0 task_ids="" dest="$PACK_DIR" do_import=1 dry=0 credits=15
  local pivots="" split_args=""
  while (( $# )); do
    case "$1" in
      --max-tris) max_tris="$2"; shift 2;;
      --pivot) pivots="$2"; shift 2;;
      --split-args) split_args="$2"; shift 2;;
      --size) size="$2"; shift 2;;
      --parts) parts="$2"; shift 2;;
      --scale) scale="$2"; shift 2;;
      --yaw) yaw="$2"; shift 2;;
      --task-ids) task_ids="$2"; shift 2;;
      --credits) credits="$2"; shift 2;;
      --dest) dest="$2"; shift 2;;
      --no-import) do_import=0; shift;;
      --dry-run) dry=1; do_import=0; shift;;
      *) die "unknown arg $1";;
    esac
  done
  local work; work="$(mktemp -d "${TMPDIR:-/tmp}/meshy-install.XXXXXX")"
  (( dry )) && dest="${work}/install" && note "DRY RUN: installing into ${dest}; game/ is not touched"
  mkdir -p "$dest"

  # 1. Parts. One file per part, or the whole thing as one part named <asset>.
  local -a names=()
  local -a extra_split=()
  # shellcheck disable=SC2206  # word-splitting the passthrough is the point
  [[ -n "$split_args" ]] && extra_split=($split_args)
  if [[ -n "$parts" ]]; then
    IFS=',' read -r -a names <<<"$parts"
    python3 "${TOOLS}/meshy_split.py" "$input" --parts "$parts" --drop-inner-shells \
      --scale "$scale" --origin bottom ${extra_split[@]+"${extra_split[@]}"} \
      --out-dir "${work}/split" --json >"${work}/split.json"
  else
    names=("$asset")
    mkdir -p "${work}/split"
    python3 "${TOOLS}/meshy_split.py" "$input" --parts "$asset" --drop-inner-shells \
      --scale "$scale" --origin bottom --out-dir "${work}/split" --json >"${work}/split.json"
  fi

  # 2..4. Per part: trim to the gate, optimise (512 texture, section 7), gate.
  local rows="[]"
  for name in "${names[@]}"; do
    local part_in="${work}/split/${name}.glb" trimmed="${work}/${name}_trim.glb" final="${dest}/${name}.glb"
    [[ -f "$part_in" ]] || die "split did not produce ${part_in}"
    python3 "${TOOLS}/meshy_trim.py" "$part_in" "$trimmed" --max "$max_tris" >&2
    python3 "${TOOLS}/optimize_runtime_glb.py" "$trimmed" "${work}/${name}_opt.glb" --texture 512 >&2 \
      || die "optimise failed for ${name}"
    # optimize rewrites normals/material; the split already placed the pivot.
    if [[ -e "$final" && $dry -eq 0 ]]; then die "refusing to overwrite ${final}; remove it first if a re-install is intended"; fi
    cp "${work}/${name}_opt.glb" "$final"
    rows="$(python3 - "$rows" "$final" "$name" "$asset" "$max_tris" "$size" "$yaw" "$task_ids" "$credits" "$input" "$parts" "$scale" "$pivots" "$split_args" <<'PY'
import json, os, struct, sys
rows, path, name, asset, gate, size, yaw, task_ids, credits, src, parts, scale, pivots, split_args = sys.argv[1:15]
rows = json.loads(rows)
pivot = dict(item.split("=", 1) for item in pivots.split(",") if "=" in item).get(name, "baseCentre")
# Count triangles and read the bounds straight off the file: the gate is
# checked on what was WRITTEN, not on what a tool reported.
data = open(path, "rb").read()
off, gltf, binc = 12, None, None
while off + 8 <= len(data):
    clen, ctype = struct.unpack_from("<II", data, off)
    body = data[off + 8: off + 8 + clen]
    if ctype == 0x4E4F534A: gltf = json.loads(body.decode())
    elif ctype == 0x004E4942: binc = body
    off += 8 + clen + ((4 - clen % 4) % 4)
tris = 0; lo = [1e9] * 3; hi = [-1e9] * 3
for mesh in gltf["meshes"]:
    for prim in mesh["primitives"]:
        acc = gltf["accessors"][prim["indices"]]; tris += acc["count"] // 3
        pacc = gltf["accessors"][prim["attributes"]["POSITION"]]
        lo = [min(a, b) for a, b in zip(lo, pacc["min"])]; hi = [max(a, b) for a, b in zip(hi, pacc["max"])]
longest = max(h - l for h, l in zip(hi, lo))
if tris > int(gate): sys.exit("GATE FAILED: %s is %d triangles > %s" % (name, tris, gate))
cx, cy, cz = [(l + h) * 0.5 for l, h in zip(lo, hi)]
if pivot == "hingeBack":
    if abs(lo[1]) > 0.003 or abs(lo[2]) > 0.003 or abs(cx) > 0.003: sys.exit("PIVOT FAILED: %s (hingeBack) base y=%.3f back z=%.3f centre x=%.3f" % (name, lo[1], lo[2], cx))
elif pivot == "hingeLeft":
    if abs(lo[0]) > 0.003 or abs(cy) > 0.003 or abs(cz) > 0.003: sys.exit("PIVOT FAILED: %s (hingeLeft) -X edge at %.3f" % (name, lo[0]))
elif pivot == "hingeRight":
    if abs(hi[0]) > 0.003 or abs(cy) > 0.003 or abs(cz) > 0.003: sys.exit("PIVOT FAILED: %s (hingeRight) +X edge at %.3f" % (name, hi[0]))
elif abs(lo[1]) > 0.003 or abs(cx) > 0.003 or abs(cz) > 0.003:
    sys.exit("PIVOT FAILED: %s base at y=%.3f, footprint centre (%.3f, %.3f)" % (name, lo[1], cx, cz))
tex = 0
for img in gltf.get("images", []):
    tex = 512  # optimize_runtime_glb resamples to <= 512; asserted again by test_assets_models
row = {"propId": name, "word": name, "file": "res://assets/models/meshy-props/%s.glb" % name,
       "longestAxisMetres": round(float(size) if size else longest, 4), "yawDegrees": float(yaw),
       "triangles": tris, "maxTriangles": int(gate), "textureSize": tex,
       "derivedFrom": {"file": os.path.basename(src), "tool": "tools/meshy_batch.sh install",
                        "args": ("--parts %s --scale %s --max-tris %s" % (parts or name, scale, gate)
                                 + (" --pivot %s" % pivots if pivots else "")
                                 + (" --split-args \"%s\"" % split_args if split_args else ""))},
       "meshyTaskIds": [t for t in task_ids.split(",") if t], "creditsSpent": int(credits) if (not parts or not rows) else 0,
       "creditsNote": "" if (not parts or not rows) else "one task shared by the parts of '%s'; the credits are on the first part" % asset,
       "license": "Meshy subscription — owner's account, commercial use per plan; evidence: task ids",
       "usedBy": []}
if pivot != "baseCentre": row["pivot"] = pivot
if not row["creditsNote"]: row.pop("creditsNote")
rows.append(row)
print(json.dumps(rows))
print("  %-12s %5d tris  longest %.3f m  base y=%.3f  -> %s" % (name, tris, longest, lo[1], path), file=sys.stderr)
PY
)"
  done

  # 5. Manifest rows: merged into the pack manifest, or printed in a dry run.
  if (( dry )); then
    echo "Manifest rows that WOULD be merged into ${MANIFEST}:"
    echo "$rows" | python3 -m json.tool
    echo "Dry run complete. Files in ${dest}:"; ls -la "$dest"
    return 0
  fi
  python3 - "$MANIFEST" "$rows" <<'PY'
import json, sys
path, rows = sys.argv[1], json.loads(sys.argv[2])
doc = json.load(open(path)) if __import__("os").path.exists(path) else {"manifestVersion": 1, "pack": "meshy-props", "props": []}
have = {p["propId"]: i for i, p in enumerate(doc["props"])}
for row in rows:
    if row["propId"] in have:
        sys.exit("manifest already has '%s'; edit it by hand rather than overwrite a reviewed row" % row["propId"])
    doc["props"].append(row)
json.dump(doc, open(path, "w"), ensure_ascii=False, indent=2); open(path, "a").write("\n")
print("manifest: +%d row(s) -> %s" % (len(rows), path))
PY
  # 6. Import, so the .import sidecars and extracted textures exist for a fresh clone.
  if (( do_import )); then
    ( cd "${REPO}/game" && "$GODOT" --headless --path . --import >/dev/null 2>&1 ) || die "Godot import failed"
    echo "imported. Next: run the suite, shoot it (tests/shots_props.gd), wire it (tools/meshy_attach.md), commit."
  fi
}

case "${1:-}" in
  balance) shift; cmd_balance "$@" ;;
  preview) shift; cmd_preview "$@" ;;
  refine)  shift; cmd_refine "$@" ;;
  poll)    shift; cmd_poll "$@" ;;
  wait)    shift; cmd_wait "$@" ;;
  thumb)   shift; cmd_thumb "$@" ;;
  fetch)   shift; cmd_fetch "$@" ;;
  install) shift; cmd_install "$@" ;;
  *) sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
