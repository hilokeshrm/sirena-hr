#!/usr/bin/env bash
# Database backup: a compressed pg_dump in ~/sirena/backups/<kind>, plus uploaded files.
# Usage: backup.sh [daily|manual]   (cron runs `daily` every night; 14 daily copies are kept)
set -euo pipefail
HOME_DIR="${SIRENA_HOME:-$HOME/sirena}"
KIND="${1:-manual}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME_DIR/backups/$KIND"
STAMP="$(date +%Y%m%d-%H%M%S)"
umask 077
mkdir -p "$DEST"

cd "$HERE"
docker compose exec -T db pg_dump -U sirena_app -d sirena_hr -Fc > "$DEST/sirena_hr-$STAMP.dump"
tar -C "$HOME_DIR" -czf "$DEST/files-$STAMP.tgz" files
echo "$DEST/sirena_hr-$STAMP.dump ($(du -h "$DEST/sirena_hr-$STAMP.dump" | cut -f1))"

if [ "$KIND" = daily ]; then
  ls -1t "$DEST"/sirena_hr-*.dump | tail -n +15 | xargs -r rm -f
  ls -1t "$DEST"/files-*.tgz | tail -n +15 | xargs -r rm -f
fi
