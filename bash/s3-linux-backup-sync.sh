#!/usr/bin/env bash
# ==============================================================================
# Script: s3-linux-backup-sync.sh
# EN: Compresses Linux directories, writes SHA-256 checksums, and uploads to Amazon S3.
# PT: Compacta diretórios no Linux, gera checksum SHA-256 e envia para o Amazon S3.
# Usage: ./s3-linux-backup-sync.sh <source_dir> <s3_bucket> [storage_class] [local_retention_days]
# ==============================================================================

set -euo pipefail

SOURCE_DIR="${1:-}"
S3_BUCKET="${2:-}"
STORAGE_CLASS="${3:-STANDARD_IA}"
LOCAL_RETENTION_DAYS="${4:-3}"
STAGING_DIR="${BACKUP_STAGING_DIR:-/var/backups/s3-staging}"

if [[ -z "$SOURCE_DIR" || -z "$S3_BUCKET" ]]; then
    echo "Usage: $0 <source_dir> <s3_bucket> [storage_class] [local_retention_days]"
    exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "[ERROR] Source directory not found: $SOURCE_DIR" >&2
    exit 1
fi

mkdir -p "$STAGING_DIR"

HOSTNAME_SHORT="$(hostname -s | tr '[:upper:]' '[:lower:]')"
DATE_FOLDER="$(date '+%Y-%m-%d')"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
BASENAME="$(basename "$SOURCE_DIR")"

ARCHIVE_NAME="${BASENAME}_${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="${STAGING_DIR}/${ARCHIVE_NAME}"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"

echo "[INFO] Creating compressed archive '${ARCHIVE_PATH}'..."
tar -czf "$ARCHIVE_PATH" -C "$(dirname "$SOURCE_DIR")" "$BASENAME"

sha256sum "$ARCHIVE_PATH" > "$CHECKSUM_PATH"
echo "[INFO] SHA-256 checksum generated: $(awk '{print $1}' "$CHECKSUM_PATH")"

S3_URI="s3://${S3_BUCKET}/backups/${HOSTNAME_SHORT}/${DATE_FOLDER}"
echo "[INFO] Uploading backup and manifest to ${S3_URI}/ (StorageClass: ${STORAGE_CLASS})..."

aws s3 cp "$ARCHIVE_PATH" "${S3_URI}/${ARCHIVE_NAME}" \
    --storage-class "$STORAGE_CLASS" \
    --sse AES256 \
    --only-show-errors

aws s3 cp "$CHECKSUM_PATH" "${S3_URI}/${ARCHIVE_NAME}.sha256" \
    --storage-class "$STORAGE_CLASS" \
    --sse AES256 \
    --only-show-errors

echo "[OK] Upload to Amazon S3 completed."

echo "[INFO] Pruning local staging archives older than ${LOCAL_RETENTION_DAYS} days..."
find "$STAGING_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.sha256" \) -mtime +"$LOCAL_RETENTION_DAYS" -delete
echo "[OK] Backup routine finished."
