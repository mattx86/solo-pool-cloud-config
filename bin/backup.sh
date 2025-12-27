#!/bin/bash
# =============================================================================
# backup.sh - Solo Pool backup script
#
# Creates compressed backups of /opt/solopool (excluding blockchain data
# and the backups directory itself).
#
# Called by maintenance.sh after SQLite optimization and log rotation.
# =============================================================================

source /opt/solopool/install/config.sh

if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration" >&2
    exit 1
fi

LOG_FILE="${BASE_DIR}/logs/maintenance.log"
mkdir -p "$(dirname "${LOG_FILE}")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# =============================================================================
# CONFIGURATION
# =============================================================================

# Use configured backup directory or default
BACKUP_DIR="${BACKUP_DIR:-${BASE_DIR}/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# Generate filename with timezone
# Format: solopool-backup-YYYYMMDD_HHMMSS_TZ.tar.gz
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
TZ_OFFSET=$(date '+%z')
BACKUP_FILENAME="solopool-backup-${TIMESTAMP}_${TZ_OFFSET}.tar.gz"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"

# =============================================================================
# CREATE BACKUP
# =============================================================================

log "Creating backup..."
log "  Target: ${BACKUP_PATH}"

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Directories to exclude from backup (large blockchain data, backups, temp)
EXCLUDES=(
    # Backup directory itself
    "--exclude=${BACKUP_DIR}"
    # Blockchain data directories
    "--exclude=${BITCOIN_DIR}/data"
    "--exclude=${BCHN_DIR}/data"
    "--exclude=${DIGIBYTE_DIR}/data"
    "--exclude=${MONERO_DIR}/data"
    "--exclude=${TARI_DIR}/data"
    "--exclude=${ALEO_DIR}/data"
    # Temporary files
    "--exclude=${BASE_DIR}/*.tmp"
    "--exclude=${BASE_DIR}/*/.cache"
    # Rotated logs (keep current logs only)
    "--exclude=${BASE_DIR}/**/logs/*.gz"
    "--exclude=${BASE_DIR}/**/logs/*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]"
)

# Create the backup
if tar -czf "${BACKUP_PATH}" \
    "${EXCLUDES[@]}" \
    -C "$(dirname "${BASE_DIR}")" \
    "$(basename "${BASE_DIR}")" 2>/dev/null; then

    BACKUP_SIZE=$(du -h "${BACKUP_PATH}" 2>/dev/null | cut -f1)
    log "  [OK] Backup created: ${BACKUP_SIZE}"
else
    log "  [ERROR] Failed to create backup"
    exit 1
fi

# =============================================================================
# CLEANUP OLD BACKUPS
# =============================================================================

log "Cleaning up old backups (older than ${BACKUP_RETENTION_DAYS} days)..."

DELETED_COUNT=0
while IFS= read -r old_backup; do
    if [ -n "${old_backup}" ]; then
        rm -f "${old_backup}"
        log "  Deleted: $(basename "${old_backup}")"
        ((DELETED_COUNT++))
    fi
done < <(find "${BACKUP_DIR}" -name "solopool-backup-*.tar.gz" -mtime +${BACKUP_RETENTION_DAYS} 2>/dev/null)

if [ ${DELETED_COUNT} -gt 0 ]; then
    log "  Removed ${DELETED_COUNT} old backup(s)"
else
    log "  No old backups to remove"
fi

# =============================================================================
# SUMMARY
# =============================================================================

BACKUP_COUNT=$(find "${BACKUP_DIR}" -name "solopool-backup-*.tar.gz" 2>/dev/null | wc -l)
BACKUP_TOTAL=$(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1)

log "Backup complete:"
log "  Current backups: ${BACKUP_COUNT}"
log "  Total size: ${BACKUP_TOTAL}"
