#!/usr/bin/env bash
# Loads Cloudflare credentials into the environment from the macOS keychain.
# Source it:  source tools/cf_keychain.sh
# It never prints a secret. Store them once with:
#   security add-generic-password -s CLOUDFLARE_API_TOKEN -a littledays -w '<token>'
#   security add-generic-password -s CLOUDFLARE_ACCOUNT_ID -a littledays -w '<account id>'
# The token should be scoped (Workers Scripts:Edit, D1:Edit, Account Settings:Read,
# Workers Routes:Edit for the joinanny.com zone only). Never a Global API Key.
if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  CLOUDFLARE_API_TOKEN="$(security find-generic-password -s CLOUDFLARE_API_TOKEN -w 2>/dev/null || true)"
  export CLOUDFLARE_API_TOKEN
fi
if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
  CLOUDFLARE_ACCOUNT_ID="$(security find-generic-password -s CLOUDFLARE_ACCOUNT_ID -w 2>/dev/null || true)"
  export CLOUDFLARE_ACCOUNT_ID
fi
if [[ -z "${CLOUDFLARE_API_TOKEN}" ]]; then
  echo "cf_keychain: no CLOUDFLARE_API_TOKEN in the environment or the keychain." >&2
  echo "  security add-generic-password -s CLOUDFLARE_API_TOKEN -a littledays -w '<token>'" >&2
  return 1 2>/dev/null || exit 1
fi
echo "cf_keychain: token loaded (len ${#CLOUDFLARE_API_TOKEN}); account id $( [[ -n "$CLOUDFLARE_ACCOUNT_ID" ]] && echo set || echo MISSING )"
