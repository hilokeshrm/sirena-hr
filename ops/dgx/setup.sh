#!/usr/bin/env bash
# One-time setup of Sirena HR on the DGX Spark (no sudo needed; the user must be in the docker group).
# Creates ~/sirena (data, secrets, certificate), then builds and starts the containers.
# Safe to run again: existing secrets and the certificate are kept.
set -euo pipefail

HOME_DIR="${SIRENA_HOME:-$HOME/sirena}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PUBLIC_IP="${PUBLIC_IP:-106.51.70.71}"
LAN_IP="${LAN_IP:-192.168.88.12}"
PORT=7777

umask 077
mkdir -p "$HOME_DIR"/{pgdata,files,www,logs,certs,secrets,backups/daily,backups/manual,caddy-data}
chmod 700 "$HOME_DIR" "$HOME_DIR/secrets" "$HOME_DIR/backups" "$HOME_DIR/certs"

secret() { # secret NAME LENGTH -> creates once, prints value
  local f="$HOME_DIR/secrets/$1"
  [ -s "$f" ] || openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c "$2" > "$f"
  cat "$f"
}
DB_PASS="$(secret db_password 32)"
JWT="$(secret jwt 64)"
chmod 600 "$HOME_DIR"/secrets/*

if [ ! -s "$HOME_DIR/certs/server.pem" ]; then
  openssl req -x509 -newkey rsa:3072 -sha256 -days 1095 -nodes \
    -keyout "$HOME_DIR/certs/server.key" -out "$HOME_DIR/certs/server.pem" \
    -subj "/CN=Sirena HR" -addext "subjectAltName=IP:$PUBLIC_IP,IP:$LAN_IP" 2>/dev/null
  # Caddy runs as this user and must read the key.
  chmod 600 "$HOME_DIR/certs/server.key"; chmod 644 "$HOME_DIR/certs/server.pem"
fi

cat > "$HOME_DIR/secrets/api.env" <<EOF
DATABASE_URL=postgresql://sirena_app:$DB_PASS@127.0.0.1:5433/sirena_hr
JWT_SECRET=$JWT
JWT_EXPIRES_IN=12h
PORT=3100
HOST=127.0.0.1
FILES_DIR=/data/files
MEAL_CUTOFF=10:30
TRUST_PROXY=true
CORS_ORIGINS=https://$PUBLIC_IP:$PORT,https://$LAN_IP:$PORT
TZ=Asia/Kolkata
EOF
chmod 600 "$HOME_DIR/secrets/api.env"

# Settings docker compose reads from ops/dgx/.env
cat > "$HERE/.env" <<EOF
SIRENA_HOME=$HOME_DIR
SIRENA_UID=$(id -u)
SIRENA_GID=$(id -g)
EOF

cd "$HERE"
docker compose up -d --build
echo
echo "Certificate SHA-256 (for the phone app):"
openssl x509 -in "$HOME_DIR/certs/server.pem" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':'
