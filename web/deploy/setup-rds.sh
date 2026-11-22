#!/usr/bin/env bash
# One-time setup of the Mealy database on an existing AWS RDS Postgres instance.
# Runs ON the EC2 instance (deploy.sh --setup-db copies it there and runs it interactively),
# because RDS is normally reachable only from inside the VPC.
#
# What it does:
#   1. installs the psql client and the RDS CA bundle
#   2. checks the EC2 instance can reach RDS on 5432
#   3. logs in with the RDS master user (password prompted, never stored)
#   4. creates an app role + database owned by it, with a random password
#   5. writes DATABASE_URL (TLS required) to $APP_DIR/shared/database.env, which the service loads
#
# Env: RDS_HOST (required), RDS_PORT=5432, RDS_MASTER_USER=postgres, DB_NAME=mealy, DB_USER=mealy,
#      APP_DIR=/opt/mealy, FORCE=1 to rotate the app password and rewrite database.env.
set -euo pipefail

: "${RDS_HOST:?Set RDS_HOST to the RDS endpoint (xxx.yyy.region.rds.amazonaws.com)}"
RDS_PORT="${RDS_PORT:-5432}"
RDS_MASTER_USER="${RDS_MASTER_USER:-postgres}"
DB_NAME="${DB_NAME:-mealy}"
DB_USER="${DB_USER:-mealy}"
APP_DIR="${APP_DIR:-/opt/mealy}"
FORCE="${FORCE:-0}"
ENV_FILE="$APP_DIR/shared/database.env"
CA_FILE="$APP_DIR/shared/rds-ca.pem"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

[[ "$DB_NAME" =~ ^[a-z_][a-z0-9_]*$ && "$DB_USER" =~ ^[a-z_][a-z0-9_]*$ ]] || die "DB_NAME/DB_USER must be lowercase identifiers"
[ -d "$APP_DIR/shared" ] || die "$APP_DIR/shared missing: run deploy.sh --setup first"

if [ -f "$ENV_FILE" ] && [ "$FORCE" != 1 ]; then
  echo "$ENV_FILE already exists; database is set up. Re-run with FORCE=1 to rotate the app password."
  exit 0
fi

log "Installing psql client"
if ! command -v psql >/dev/null; then
  if command -v apt-get >/dev/null; then sudo apt-get install -y postgresql-client
  else sudo dnf install -y postgresql16; fi
fi

log "Fetching RDS CA bundle"
curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o "$CA_FILE"
chmod 644 "$CA_FILE"

log "Checking network path to $RDS_HOST:$RDS_PORT"
if ! timeout 5 bash -c "</dev/tcp/$RDS_HOST/$RDS_PORT" 2>/dev/null; then
  die "Can't reach $RDS_HOST:$RDS_PORT from this instance.
Fix: in the RDS instance's security group, add an inbound rule for PostgreSQL (TCP 5432)
whose source is this EC2 instance's security group. Also check both are in the same VPC
(or that the RDS instance is publicly accessible, which isn't recommended)."
fi

read -rsp "RDS master password for '$RDS_MASTER_USER': " PGPASSWORD; echo
export PGPASSWORD PGSSLMODE=verify-full PGSSLROOTCERT="$CA_FILE" PGCONNECT_TIMEOUT=10
master_psql() { psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$RDS_MASTER_USER" -v ON_ERROR_STOP=1 -qtA "$@"; }

master_psql -d postgres -c 'select 1' >/dev/null || die "Login as $RDS_MASTER_USER failed (wrong password, or the master user isn't '$RDS_MASTER_USER')."
echo "Connected: $(master_psql -d postgres -c 'show server_version')"

APP_PASS="$(openssl rand -hex 24)"

log "Creating role '$DB_USER' and database '$DB_NAME'"
if [ "$(master_psql -d postgres -c "select 1 from pg_roles where rolname='$DB_USER'")" = 1 ]; then
  master_psql -d postgres -c "alter role $DB_USER with login password '$APP_PASS'"
  echo "Role existed; password rotated."
else
  master_psql -d postgres -c "create role $DB_USER with login password '$APP_PASS'"
fi
# The master user must be a member of the role to hand it ownership of a database (PG16+ rule).
master_psql -d postgres -c "grant $DB_USER to $RDS_MASTER_USER" >/dev/null 2>&1 || true

if [ "$(master_psql -d postgres -c "select 1 from pg_database where datname='$DB_NAME'")" != 1 ]; then
  master_psql -d postgres -c "create database $DB_NAME owner $DB_USER"
else
  master_psql -d postgres -c "alter database $DB_NAME owner to $DB_USER"
  echo "Database existed; ownership set to $DB_USER."
fi
master_psql -d postgres -c "revoke all on database $DB_NAME from public"
# Prisma creates tables in public; make sure the app role can (PG15+ no longer grants this to everyone).
master_psql -d "$DB_NAME" -c "alter schema public owner to $DB_USER"
unset PGPASSWORD

log "Verifying app login"
PGPASSWORD="$APP_PASS" psql -h "$RDS_HOST" -p "$RDS_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -qtA \
  -c 'create table _mealy_probe(id int); drop table _mealy_probe;' >/dev/null
echo "OK: $DB_USER can create tables in $DB_NAME"

# Prisma: sslmode=require encrypts the connection. connection_limit keeps a small RDS
# instance from running out of connections.
umask 027
cat > "$ENV_FILE" <<EOF
DATABASE_URL="postgresql://$DB_USER:$APP_PASS@$RDS_HOST:$RDS_PORT/$DB_NAME?schema=public&sslmode=require&connection_limit=10"
EOF
sudo chgrp mealy "$ENV_FILE" 2>/dev/null || true
chmod 640 "$ENV_FILE"

log "Done. DATABASE_URL written to $ENV_FILE (leave DATABASE_URL out of .env.production)."
echo "Next deploy runs 'prisma db push' to create the tables."
