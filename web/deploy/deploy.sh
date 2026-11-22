#!/usr/bin/env bash
# Deploy the Mealy backend (web/) to an EC2 instance over SSH.
#
# Usage (from anywhere):
#   EC2_HOST=1.2.3.4 ./deploy/deploy.sh --setup     # first time: provision the box, set up the RDS db, deploy
#   EC2_HOST=1.2.3.4 ./deploy/deploy.sh --setup-db  # only (re)run the RDS database setup
#   EC2_HOST=1.2.3.4 ./deploy/deploy.sh             # every later deploy
#   EC2_HOST=1.2.3.4 ./deploy/deploy.sh --rollback  # point `current` back at the previous release
#
# Config: env vars, or put them in web/deploy/deploy.env (git-ignored).
#   EC2_HOST       (required) public IP or DNS of the instance
#   EC2_USER       ssh user; ubuntu (Ubuntu) or ec2-user (Amazon Linux). Default: ubuntu
#   SSH_KEY        path to the .pem key. Default: ssh's own config/agent
#   DOMAIN, CERTBOT_EMAIL             used by --setup, see setup-server.sh
#   RDS_HOST       RDS endpoint; with RDS_MASTER_USER (default postgres), DB_NAME, DB_USER. See setup-rds.sh
#   KEEP_RELEASES  releases kept on the box. Default: 5
#
# Production env: if web/.env.production exists it is uploaded to /opt/mealy/shared/.env on each deploy.
# Otherwise create that file on the server yourself before the first deploy. Leave DATABASE_URL out of it:
# setup-rds.sh writes the RDS URL to /opt/mealy/shared/database.env, which takes precedence.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
[ -f "$SCRIPT_DIR/deploy.env" ] && set -a && . "$SCRIPT_DIR/deploy.env" && set +a

: "${EC2_HOST:?Set EC2_HOST (instance IP or DNS)}"
EC2_USER="${EC2_USER:-ubuntu}"
APP_DIR="${APP_DIR:-/opt/mealy}"
APP_PORT="${APP_PORT:-3000}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30)
[ -n "${SSH_KEY:-}" ] && SSH_OPTS+=(-i "$SSH_KEY")
TARGET="$EC2_USER@$EC2_HOST"
ssh_run() { ssh "${SSH_OPTS[@]}" "$TARGET" "$@"; }
log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

MODE=deploy
case "${1:-}" in
  --setup) MODE=setup ;;
  --setup-db) MODE=setup-db ;;
  --rollback) MODE=rollback ;;
  "") ;;
  *) echo "Unknown option: $1" >&2; exit 1 ;;
esac

if [ "$MODE" = rollback ]; then
  log "Rolling back on $EC2_HOST"
  ssh_run "set -e; cd $APP_DIR/releases
    cur=\$(basename \$(readlink -f $APP_DIR/current))
    prev=\$(ls -1 | sort | grep -B1 -x \"\$cur\" | head -n1)
    [ -n \"\$prev\" ] && [ \"\$prev\" != \"\$cur\" ] || { echo 'No earlier release to roll back to'; exit 1; }
    ln -sfn $APP_DIR/releases/\$prev $APP_DIR/current
    sudo systemctl restart mealy
    echo \"Now running \$prev (was \$cur)\""
  exit 0
fi

setup_db() {
  : "${RDS_HOST:?Set RDS_HOST to your RDS endpoint (RDS console > Databases > your db > Endpoint)}"
  log "Setting up database on RDS ($RDS_HOST)"
  scp "${SSH_OPTS[@]}" "$SCRIPT_DIR/setup-rds.sh" "$TARGET:/tmp/mealy-setup-rds.sh"
  # -t so the script can prompt for the RDS master password on the instance (it is never stored).
  ssh -t "${SSH_OPTS[@]}" "$TARGET" "RDS_HOST='$RDS_HOST' RDS_PORT='${RDS_PORT:-5432}' \
    RDS_MASTER_USER='${RDS_MASTER_USER:-postgres}' DB_NAME='${DB_NAME:-mealy}' DB_USER='${DB_USER:-mealy}' \
    APP_DIR='$APP_DIR' FORCE='${FORCE:-0}' bash /tmp/mealy-setup-rds.sh; rc=\$?; rm -f /tmp/mealy-setup-rds.sh; exit \$rc"
}

if [ "$MODE" = setup-db ]; then setup_db; exit 0; fi

if [ "$MODE" = setup ]; then
  log "Provisioning $EC2_HOST"
  scp "${SSH_OPTS[@]}" "$SCRIPT_DIR/setup-server.sh" "$TARGET:/tmp/mealy-setup.sh"
  ssh_run "DOMAIN='${DOMAIN:-_}' CERTBOT_EMAIL='${CERTBOT_EMAIL:-}' \
    APP_DIR='$APP_DIR' APP_PORT='$APP_PORT' bash /tmp/mealy-setup.sh && rm -f /tmp/mealy-setup.sh"
  setup_db
fi

RELEASE="$(date -u +%Y%m%d%H%M%S)"
RELEASE_DIR="$APP_DIR/releases/$RELEASE"
GIT_REV="$(git -C "$WEB_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ -n "$(git -C "$WEB_DIR" status --porcelain -- . 2>/dev/null)" ]; then
  echo "Note: web/ has uncommitted changes; they will be deployed as-is."
fi

log "Uploading release $RELEASE ($GIT_REV) to $EC2_HOST"
ssh_run "mkdir -p $RELEASE_DIR"
# --link-dest hard-links unchanged files from the live release, so only changes are sent.
rsync -az --delete -e "ssh ${SSH_OPTS[*]}" --link-dest="$APP_DIR/current/" \
  --exclude node_modules --exclude .next --exclude '.env*' --exclude '*.tsbuildinfo' \
  --exclude deploy/deploy.env --exclude .git --exclude coverage \
  "$WEB_DIR/" "$TARGET:$RELEASE_DIR/"

if [ -f "$WEB_DIR/.env.production" ]; then
  log "Uploading .env.production"
  scp "${SSH_OPTS[@]}" "$WEB_DIR/.env.production" "$TARGET:$APP_DIR/shared/.env"
fi

log "Building on server"
ssh_run "set -euo pipefail
  [ -f $APP_DIR/shared/.env ] || { echo 'Missing $APP_DIR/shared/.env (copy web/.env.example, fill in production values)'; exit 1; }
  chmod 640 $APP_DIR/shared/.env
  grep -qs '^DATABASE_URL=' $APP_DIR/shared/database.env $APP_DIR/shared/.env || {
    echo 'No DATABASE_URL on the server. Run: ./deploy/deploy.sh --setup-db'; exit 1; }
  cd $RELEASE_DIR
  echo '$GIT_REV' > REVISION
  # Next.js and Prisma both read .env from the working dir; DATABASE_URL comes from database.env (RDS, written by setup-rds.sh).
  ln -sfn $APP_DIR/shared/.env .env
  if [ -f $APP_DIR/shared/database.env ]; then set -a; . $APP_DIR/shared/database.env; set +a; fi
  export NODE_ENV=production
  npm ci --include=dev --no-audit --no-fund
  npx prisma generate
  # No migrations folder in this repo, so sync the schema. Refuses destructive changes (no --accept-data-loss).
  npx prisma db push --skip-generate
  npm run build
  npm prune --omit=dev --no-audit --no-fund
  chmod -R g+w .next  # runtime cache writes as the mealy user"

log "Switching to new release and restarting"
ssh_run "set -e
  PREV=\$(readlink -f $APP_DIR/current 2>/dev/null || true)
  ln -sfn $RELEASE_DIR $APP_DIR/current
  sudo systemctl restart mealy
  for i in \$(seq 1 30); do
    code=\$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$APP_PORT/ || true)
    if [ \"\$code\" != 000 ] && [ \"\${code:0:1}\" != 5 ]; then echo \"Healthy (HTTP \$code)\"; exit 0; fi
    sleep 2
  done
  echo 'Health check failed; rolling back.'
  sudo journalctl -u mealy -n 40 --no-pager || true
  if [ -n \"\$PREV\" ]; then ln -sfn \"\$PREV\" $APP_DIR/current; sudo systemctl restart mealy; fi
  exit 1"

log "Pruning old releases (keeping $KEEP_RELEASES)"
ssh_run "cd $APP_DIR/releases && ls -1 | sort | head -n -$KEEP_RELEASES | xargs -r rm -rf"

log "Deployed $RELEASE ($GIT_REV) to $EC2_HOST"
