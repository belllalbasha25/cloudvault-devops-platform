#!/usr/bin/env bash
# =============================================================================
# seed.sh — provided & working (this is part of the "built" half of the repo).
# =============================================================================
# Prepares a freshly-started local stack:
#   1. waits for the gateway to be healthy
#   2. creates the S3 bucket in LocalStack (idempotent)
#   3. applies DB migrations to every database (idempotent)
#   4. creates a demo user and uploads a sample image
#
# Run it after `make up` (or `docker compose up`).  Usage: ./scripts/seed.sh
# Bash + Linux practice is part of the course — read it, then extend it.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

# ---- Load env (defaults come from .env, else .env.example) -------------------
set -a
if [ -f .env ]; then . ./.env; else . ./.env.example; fi
set +a

GATEWAY_URL="${GATEWAY_URL:-http://localhost:${GATEWAY_PORT:-8080}}"
S3_URL="${S3_PUBLIC_ENDPOINT:-http://localhost:4566}"
BUCKET="${S3_BUCKET:-cloudvault}"
DEMO_EMAIL="${DEMO_EMAIL:-demo@cloudvault.dev}"
DEMO_PASSWORD="${DEMO_PASSWORD:-demopassword}"

say() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*"; }

# ---- 1. Wait for the gateway ------------------------------------------------
say "Waiting for gateway at ${GATEWAY_URL} ..."
for i in $(seq 1 60); do
  if curl -fsS "${GATEWAY_URL}/healthz" >/dev/null 2>&1; then break; fi
  sleep 2
  if [ "$i" = "60" ]; then echo "gateway never became healthy — is the stack up? (make up)"; exit 1; fi
done
say "Gateway is up."

# ---- 2. Create the S3 bucket in LocalStack ----------------------------------
say "Creating S3 bucket '${BUCKET}' in LocalStack ..."
# LocalStack S3 accepts an anonymous path-style PUT to create a bucket.
if curl -fsS -X PUT "${S3_URL}/${BUCKET}" >/dev/null 2>&1; then
  say "Bucket '${BUCKET}' ready."
else
  warn "Bucket create returned non-200 (it may already exist) — continuing."
fi

# ---- 3. Apply DB migrations (idempotent) ------------------------------------
apply() { # apply <db-service> <user> <db> <sql-file>
  local svc="$1" user="$2" db="$3" file="$4"
  if [ -f "$file" ]; then
    say "Migrating ${db} <- ${file}"
    docker compose exec -T "$svc" psql -v ON_ERROR_STOP=1 -U "$user" -d "$db" < "$file" >/dev/null
  fi
}
apply auth-db  "${AUTH_DB_USER:-auth}"   "${AUTH_DB_NAME:-authdb}"  services/auth-service/migrations/001_init.sql
apply files-db "${FILES_DB_USER:-files}" "${FILES_DB_NAME:-filesdb}" services/files-service/migrations/001_init.sql
apply files-db "${NOTIF_DB_USER:-files}" "${NOTIF_DB_NAME:-notifdb}" services/notification-service/migrations/001_init.sql

# ---- 4. Demo user + sample upload -------------------------------------------
say "Creating demo user ${DEMO_EMAIL} ..."
reg=$(curl -fsS -X POST "${GATEWAY_URL}/auth/register" \
  -H 'content-type: application/json' \
  -d "{\"email\":\"${DEMO_EMAIL}\",\"password\":\"${DEMO_PASSWORD}\"}" 2>/dev/null || true)
token=$(printf '%s' "$reg" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

if [ -z "$token" ]; then
  say "User exists — logging in instead."
  login=$(curl -fsS -X POST "${GATEWAY_URL}/auth/login" \
    -H 'content-type: application/json' \
    -d "{\"email\":\"${DEMO_EMAIL}\",\"password\":\"${DEMO_PASSWORD}\"}")
  token=$(printf '%s' "$login" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
fi
[ -n "$token" ] || { echo "could not obtain a token"; exit 1; }
say "Got a JWT for the demo user."

# Materialise a small valid 16x16 PNG so the upload -> thumbnail pipeline runs.
sample="$(mktemp -t cloudvault-sample-XXXXXX).png"
base64 -d > "$sample" <<'PNG'
iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAGklEQVR42mOw2PvjPyWYYdSAUQNGDRguBgAAdQLsHzKUwskAAAAASUVORK5CYII=
PNG

say "Uploading sample image ..."
curl -fsS -X POST "${GATEWAY_URL}/upload" \
  -H "Authorization: Bearer ${token}" \
  -F "file=@${sample};type=image/png;filename=sample.png" >/dev/null
rm -f "$sample"

say "Seed complete."
echo ""
echo "  Web UI : http://localhost:5173"
echo "  Login  : ${DEMO_EMAIL} / ${DEMO_PASSWORD}"
echo ""
