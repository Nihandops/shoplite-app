#!/usr/bin/env bash
# Nightly pg_dump of the ShopLite database (Docker Compose stack) -> /var/backups/shoplite
set -euo pipefail
APP_DIR="${APP_DIR:-/opt/shoplite-app}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/shoplite}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${BACKUP_DIR}/shoplite-${STAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"
cd "$APP_DIR"
# credentials come from the container's own env, never from this script
docker compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner' \
  | gzip -9 > "${OUT}.part"
mv "${OUT}.part" "$OUT"
[ -s "$OUT" ] || { echo "backup is empty" >&2; exit 1; }
find "$BACKUP_DIR" -name 'shoplite-*.sql.gz' -mtime +"$RETENTION_DAYS" -delete
echo "backup written: $OUT ($(du -h "$OUT" | cut -f1))"
