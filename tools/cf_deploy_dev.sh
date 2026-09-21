#!/usr/bin/env bash
# First real DEV deployment of the Little Days cloud backend. Safe by construction:
#   * dev environment only (`--env dev`); production is never touched here
#   * reuses the owner's EXISTING Worker when LD_DEV_WORKER_NAME is given (no duplicate)
#   * creates the dev D1 database only if one of that name does not exist
#   * every step prints what it will do and stops on the first failure
#   * secrets come from the keychain / env; nothing is printed or committed
# Usage:
#   source tools/cf_keychain.sh
#   LD_DEV_WORKER_NAME=<existing worker name> tools/cf_deploy_dev.sh [--apply]
# Without --apply it runs the preflight + dry-run only and changes nothing remote.
set -euo pipefail
cd "$(dirname "$0")/../cloud"
APPLY=0; [[ "${1:-}" == "--apply" ]] && APPLY=1
DB_NAME="${LD_DEV_DB_NAME:-little-days-dev}"
W="npx wrangler"

step() { printf '\n==> %s\n' "$*"; }

step "0. credentials"
[[ -n "${CLOUDFLARE_API_TOKEN:-}" ]] || { echo "CLOUDFLARE_API_TOKEN missing (source tools/cf_keychain.sh)"; exit 1; }
$W whoami | sed 's/[A-Za-z0-9_-]\{40,\}/<redacted>/g'

step "1. existing Workers on the account (to avoid a duplicate)"
$W deployments list --name "${LD_DEV_WORKER_NAME:-little-days-cloud-dev}" >/dev/null 2>&1 && \
  echo "Worker '${LD_DEV_WORKER_NAME:-little-days-cloud-dev}' exists: deploy will UPDATE it" || \
  echo "Worker '${LD_DEV_WORKER_NAME:-little-days-cloud-dev}' not found: deploy would CREATE it"
if [[ -n "${LD_DEV_WORKER_NAME:-}" ]]; then
  step "1b. point [env.dev] at the existing Worker name '${LD_DEV_WORKER_NAME}'"
  python3 - "$LD_DEV_WORKER_NAME" <<'PY'
import re,sys
name=sys.argv[1]; p='wrangler.toml'; s=open(p).read()
s=re.sub(r'(\[env\.dev\]\nname = )"[^"]*"', r'\1"%s"' % name, s, count=1)
open(p,'w').write(s)
PY
  grep -n -A1 '^\[env.dev\]' wrangler.toml
fi

step "2. dev D1 database '${DB_NAME}'"
EXISTING_ID="$($W d1 list --json 2>/dev/null | python3 -c 'import json,sys; n=sys.argv[1]; print(next((d["uuid"] for d in json.load(sys.stdin) if d.get("name")==n), ""))' "$DB_NAME" || true)"
if [[ -n "$EXISTING_ID" ]]; then
  echo "found existing database id ${EXISTING_ID}"
else
  echo "no database named ${DB_NAME}"
  if [[ $APPLY -eq 1 ]]; then
    $W d1 create "$DB_NAME" >/dev/null
    EXISTING_ID="$($W d1 list --json | python3 -c 'import json,sys; n=sys.argv[1]; print(next((d["uuid"] for d in json.load(sys.stdin) if d.get("name")==n), ""))' "$DB_NAME")"
    echo "created ${DB_NAME}: ${EXISTING_ID}"
  else
    echo "(dry run) would create it with: npx wrangler d1 create ${DB_NAME}"
  fi
fi
if [[ -n "$EXISTING_ID" ]]; then
  python3 - "$EXISTING_ID" "$DB_NAME" <<'PY'
import re,sys
dbid,name=sys.argv[1],sys.argv[2]; p='wrangler.toml'; s=open(p).read()
block=re.search(r'\[\[env\.dev\.d1_databases\]\].*?migrations_dir', s, re.S).group(0)
new=re.sub(r'database_name = "[^"]*"', 'database_name = "%s"' % name, block)
new=re.sub(r'database_id = "[^"]*"', 'database_id = "%s"' % dbid, new)
open(p,'w').write(s.replace(block,new,1))
PY
  grep -n -A3 '^\[\[env.dev.d1_databases\]\]' wrangler.toml | sed 's/database_id = "\(........\).*"/database_id = "\1…"/'
fi

step "3. migrations (remote, dev)"
if [[ $APPLY -eq 1 && -n "$EXISTING_ID" ]]; then
  $W d1 migrations apply "$DB_NAME" --env dev --remote
else
  $W d1 migrations list "$DB_NAME" --env dev --remote 2>/dev/null || echo "(dry run) would apply migrations/*.sql"
fi

step "4. PARENT_TOKEN_SECRET (dev)"
if [[ $APPLY -eq 1 ]]; then
  if $W secret list --env dev 2>/dev/null | grep -q PARENT_TOKEN_SECRET; then
    echo "already set"
  else
    openssl rand -hex 32 | $W secret put PARENT_TOKEN_SECRET --env dev
  fi
else
  echo "(dry run) would generate and set it if absent"
fi

step "5. dry run"
$W deploy --dry-run --env dev --outdir /tmp/ld-cloud-dryrun | tail -20

if [[ $APPLY -eq 1 ]]; then
  step "6. deploy dev"
  $W deploy --env dev | tee /tmp/ld-cloud-deploy.log | tail -12
  URL="$(grep -oE 'https://[a-z0-9.-]+\.workers\.dev' /tmp/ld-cloud-deploy.log | head -1 || true)"
  step "7. verify health + database"
  for u in "$URL" "${LD_DEV_URL:-}"; do
    [[ -n "$u" ]] || continue
    echo "GET $u/healthz?db=1"; curl -fsS "$u/healthz?db=1"; echo
  done
else
  echo; echo "Dry run complete. Re-run with --apply to create/migrate/deploy dev."
fi
