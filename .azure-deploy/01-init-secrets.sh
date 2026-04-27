#!/usr/bin/env bash
# Generates secrets + unique resource names and persists them to secrets.sh.
# Idempotent: if values already present in secrets.sh, keeps them.
set -euo pipefail
cd "$(dirname "$0")"

SECRETS=./secrets.sh
[ -f "$SECRETS" ] || touch "$SECRETS"
chmod 600 "$SECRETS"

# shellcheck disable=SC1090
. ./env.sh

write_if_missing() {
  local var="$1" val="$2"
  if ! grep -q "^export ${var}=" "$SECRETS"; then
    printf "export %s='%s'\n" "$var" "$val" >> "$SECRETS"
  fi
}

if ! grep -q '^# Generated' "$SECRETS"; then
  echo "# Generated $(date -u +%FT%TZ). NEVER COMMIT." > "$SECRETS"
fi

write_if_missing N8N_ENCRYPTION_KEY "$(openssl rand -hex 32)"
write_if_missing N8N_JWT_SECRET     "$(openssl rand -hex 32)"
write_if_missing PG_PASSWORD        "$(openssl rand -base64 24 | tr -d '/+=' | head -c 28)Aa1!"
write_if_missing PG_SERVER          "psql-n8n-01-dev-$RANDOM"
write_if_missing STORAGE_ACCT       "stn8n01dev$RANDOM$RANDOM"

# Re-source to surface the new values
. ./env.sh
echo "PG_SERVER          = $PG_SERVER"
echo "PG_HOST            = $PG_HOST"
echo "STORAGE_ACCT       = $STORAGE_ACCT"
echo "N8N_ENCRYPTION_KEY = (length ${#N8N_ENCRYPTION_KEY})"
echo "PG_PASSWORD        = (length ${#PG_PASSWORD})"
