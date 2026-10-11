#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

BACKUP_ROOT="${BACKUP_DIR:-$HOME/backups}"
DIR="$BACKUP_ROOT/$(date +%F)"
mkdir -p "$DIR"
for db in kavach hisaab dwaarpal karya sutra sanjeevani; do
  docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" -Fc "$db" > "$DIR/$db.dump"
done

# keep 7 days locally
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} +
