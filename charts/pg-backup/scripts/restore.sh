#!/bin/bash
set -e

echo "=== PostgreSQL Restore from S3 ==="
echo "Database: ${PG_DATABASE}@${PG_HOST}:${PG_PORT}"
echo "S3 Bucket: ${S3_BUCKET} @ ${S3_ENDPOINT}"
echo ""

# Download MinIO Client (mc)
echo "Downloading MinIO Client..."
curl -sL https://dl.min.io/client/mc/release/linux-amd64/mc -o /tmp/mc
chmod +x /tmp/mc

# Configure S3 alias
/tmp/mc alias set s3 "${S3_ENDPOINT}" "${S3_ACCESS_KEY}" "${S3_SECRET_KEY}"

# Find latest backup (files are named homelab-YYYYMMDD-HHMMSS.dump, so alphabetical = chronological)
echo "Looking for latest backup..."
LATEST=$(/tmp/mc ls "s3/${S3_BUCKET}/" 2>/dev/null | grep '\.dump$' | tail -1 | awk '{print $NF}')

if [ -z "${LATEST}" ]; then
  echo "No backup found in s3://${S3_BUCKET}/"
  echo "This appears to be a fresh install. Skipping restore."
  exit 0
fi

echo "Latest backup: ${LATEST}"

# Download backup
echo "Downloading..."
/tmp/mc cp "s3/${S3_BUCKET}/${LATEST}" "/tmp/restore.dump"

BACKUP_SIZE=$(du -h /tmp/restore.dump | cut -f1)
echo "Downloaded: ${BACKUP_SIZE}"

# Wait for PostgreSQL to be fully ready
echo "Waiting for PostgreSQL to accept connections..."
export PGPASSWORD="${PG_PASSWORD}"
for i in $(seq 1 30); do
  if pg_isready -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DATABASE}" > /dev/null 2>&1; then
    echo "PostgreSQL is ready."
    break
  fi
  echo -n "."
  sleep 2
done

# Restore (--clean drops existing objects first, --if-exists avoids errors on first run)
echo "Restoring database..."
pg_restore -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DATABASE}" \
  --clean --if-exists --no-owner --no-acl "/tmp/restore.dump" 2>&1 || true

echo ""
echo "=== Restore complete ==="

# Show table count as verification
TABLE_COUNT=$(psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DATABASE}" \
  -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')
echo "Tables in database: ${TABLE_COUNT:-unknown}"
