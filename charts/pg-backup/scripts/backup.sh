#!/bin/bash
set -e

echo "=== PostgreSQL Backup to S3 ==="
echo "Database: ${PG_DATABASE}@${PG_HOST}:${PG_PORT}"
echo "S3 Bucket: ${S3_BUCKET} @ ${S3_ENDPOINT}"
echo ""

# Configure S3 alias (mc is baked into the image)
mc alias set s3 "${S3_ENDPOINT}" "${S3_ACCESS_KEY}" "${S3_SECRET_KEY}"

# Ensure bucket exists
mc mb --ignore-existing "s3/${S3_BUCKET}"

# Generate backup filename with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="homelab-${TIMESTAMP}.dump"

# Run pg_dump (custom format = compressed)
echo "Running pg_dump..."
export PGPASSWORD="${PG_PASSWORD}"
pg_dump -h "${PG_HOST}" -p "${PG_PORT}" -U "${PG_USER}" -d "${PG_DATABASE}" \
  -Fc --no-owner --no-acl -f "/tmp/${BACKUP_FILE}"

BACKUP_SIZE=$(du -h "/tmp/${BACKUP_FILE}" | cut -f1)
echo "Backup created: ${BACKUP_FILE} (${BACKUP_SIZE})"

# Upload to S3
echo "Uploading to S3..."
mc cp "/tmp/${BACKUP_FILE}" "s3/${S3_BUCKET}/${BACKUP_FILE}"
echo "Upload complete."

# Clean up old backups (keep only the last N)
if [ -n "${RETENTION_COUNT}" ] && [ "${RETENTION_COUNT}" -gt 0 ]; then
  echo ""
  TOTAL=$(mc ls "s3/${S3_BUCKET}/" 2>/dev/null | grep '\.dump$' | wc -l)
  if [ "${TOTAL}" -gt "${RETENTION_COUNT}" ]; then
    DELETE_COUNT=$((TOTAL - RETENTION_COUNT))
    echo "Pruning ${DELETE_COUNT} old backup(s) (keeping last ${RETENTION_COUNT})..."
    mc ls "s3/${S3_BUCKET}/" 2>/dev/null | grep '\.dump$' | head -n "${DELETE_COUNT}" | awk '{print $NF}' | while read -r FILE; do
      echo "  Deleting: ${FILE}"
      mc rm "s3/${S3_BUCKET}/${FILE}" 2>/dev/null || true
    done
  else
    echo "Backup count (${TOTAL}) within retention limit (${RETENTION_COUNT}), nothing to prune."
  fi
fi

# List current backups
echo ""
echo "Current backups in S3:"
mc ls "s3/${S3_BUCKET}/"

echo ""
echo "=== Backup complete ==="
