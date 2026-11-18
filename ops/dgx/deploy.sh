#!/usr/bin/env bash
# Update the running app after new code is in ~/sirena-hr: backup, rebuild the API, restart.
# The website (Flutter build) is copied to ~/sirena/www separately; Caddy serves it as-is.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
./backup.sh manual
docker compose build api
docker compose up -d
for i in $(seq 1 30); do
  if curl -fsk https://127.0.0.1:7777/api/health -H 'Host: 106.51.70.71:7777' >/dev/null 2>&1 \
     || curl -fs http://127.0.0.1:3100/api/health >/dev/null 2>&1; then
    echo "API healthy"; exit 0
  fi
  sleep 2
done
echo "API did not become healthy; recent logs:" >&2
docker compose logs --tail 40 api >&2
exit 1
