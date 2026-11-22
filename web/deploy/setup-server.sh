#!/usr/bin/env bash
# One-time EC2 provisioning for the Mealy backend. Runs ON the instance (deploy.sh --setup copies and runs it).
# Supports Ubuntu 22.04/24.04 and Amazon Linux 2023.
#
# Env (passed through by deploy.sh):
#   DOMAIN        public hostname for nginx (and TLS if CERTBOT_EMAIL is set). Default: _ (any host, HTTP only)
#   CERTBOT_EMAIL if set, request a Let's Encrypt certificate for DOMAIN
#   APP_DIR       default /opt/mealy
#   APP_PORT      default 3000
set -euo pipefail

DOMAIN="${DOMAIN:-_}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
APP_DIR="${APP_DIR:-/opt/mealy}"
APP_PORT="${APP_PORT:-3000}"
APP_USER="mealy"
NODE_MAJOR=22

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

if command -v apt-get >/dev/null; then PM=apt; elif command -v dnf >/dev/null; then PM=dnf; else
  echo "Unsupported distro (need apt or dnf)" >&2; exit 1
fi

log "Installing system packages ($PM)"
if [ "$PM" = apt ]; then
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates gnupg nginx rsync openssl
  if ! command -v node >/dev/null || [ "$(node -v | cut -d. -f1 | tr -d v)" -lt "$NODE_MAJOR" ]; then
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | sudo -E bash -
    sudo apt-get install -y nodejs
  fi
else
  sudo dnf install -y nginx rsync openssl tar
  if ! command -v node >/dev/null || [ "$(node -v | cut -d. -f1 | tr -d v)" -lt "$NODE_MAJOR" ]; then
    sudo dnf install -y "nodejs${NODE_MAJOR}" "nodejs${NODE_MAJOR}-npm" || {
      curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" | sudo bash -
      sudo dnf install -y nodejs
    }
    # AL2023 installs as node-22; expose plain `node`/`npm`
    [ -x /usr/bin/node-${NODE_MAJOR} ] && sudo alternatives --set node /usr/bin/node-${NODE_MAJOR} 2>/dev/null || true
  fi
fi
node -v

# `next build` needs >1 GB RAM; small instances (t3.micro/small) OOM without swap.
if ! swapon --show | grep -q /swapfile; then
  log "Adding 2 GB swap"
  sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
  sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
  grep -q /swapfile /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

log "Creating app user and directories"
id "$APP_USER" >/dev/null 2>&1 || sudo useradd --system --create-home --shell /usr/sbin/nologin "$APP_USER"
sudo mkdir -p "$APP_DIR/releases" "$APP_DIR/shared"
sudo chown -R "$(id -un)":"$APP_USER" "$APP_DIR"
sudo chown "$(id -un)":"$APP_USER" "$APP_DIR/releases" "$APP_DIR/shared"
sudo chmod 2775 "$APP_DIR/releases"   # setgid: new releases are group-owned by the app user
sudo chmod 2750 "$APP_DIR/shared"

log "Installing systemd service"
sudo tee /etc/systemd/system/mealy.service >/dev/null <<UNIT
[Unit]
Description=Mealy backend (Next.js)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR/current
Environment=NODE_ENV=production
Environment=PORT=$APP_PORT
# App secrets come from $APP_DIR/shared/.env, which Next.js loads via the .env symlink in each release.
# DATABASE_URL for RDS comes from database.env, written by setup-rds.sh.
EnvironmentFile=-$APP_DIR/shared/database.env
ExecStart=/usr/bin/env npx next start -H 127.0.0.1 -p $APP_PORT
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable mealy

log "Configuring nginx"
if [ -d /etc/nginx/sites-available ]; then
  NGINX_CONF=/etc/nginx/sites-available/mealy
  sudo rm -f /etc/nginx/sites-enabled/default
else
  NGINX_CONF=/etc/nginx/conf.d/mealy.conf
fi
sudo tee "$NGINX_CONF" >/dev/null <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    client_max_body_size 20m;

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 60s;
    }
}
NGINX
[ -d /etc/nginx/sites-enabled ] && sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/mealy
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx

if [ -n "$CERTBOT_EMAIL" ] && [ "$DOMAIN" != "_" ]; then
  log "Requesting TLS certificate for $DOMAIN"
  if [ "$PM" = apt ]; then sudo apt-get install -y certbot python3-certbot-nginx
  else sudo dnf install -y certbot python3-certbot-nginx; fi
  if sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$CERTBOT_EMAIL" --redirect; then
    sudo systemctl enable --now certbot-renew.timer 2>/dev/null || true  # AL2023 doesn't enable renewal by default
  else
    echo "WARNING: certificate request failed. Point $DOMAIN's DNS A record at this instance, then re-run --setup." >&2
  fi
fi

log "Server setup done."
