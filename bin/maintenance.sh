#!/bin/bash
# =============================================================================
# maintenance.sh - Daily maintenance tasks
#
# This script performs:
# 1. SQLite database optimization (VACUUM, ANALYZE)
# 2. Log rotation via logrotate (includes compression of logs older than LOG_COMPRESS_AFTER_DAYS)
# 3. Cleanup of old log archives (older than LOG_RETENTION_DAYS)
# 4. Backup of configuration and data
# 5. Disk usage report
#
# Run via cron at scheduled time (default: 2:15 AM)
# =============================================================================

source /opt/solo-pool/install/config.sh

if [ "${CONFIG_LOADED:-}" != "true" ]; then
    echo "ERROR: Failed to load configuration" >&2
    exit 1
fi

LOG_FILE="${BASE_DIR}/logs/maintenance.log"
mkdir -p "$(dirname "${LOG_FILE}")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log "=============================================="
log "Starting daily maintenance"
log "=============================================="

# =============================================================================
# 1. SQLITE DATABASE MAINTENANCE
# =============================================================================
log ""
log "1. SQLite database maintenance..."

optimize_sqlite() {
    local db_path="$1"
    local db_name="$2"

    if [ -f "${db_path}" ]; then
        log "  Optimizing ${db_name}..."

        # Get database size before
        SIZE_BEFORE=$(du -h "${db_path}" 2>/dev/null | cut -f1)

        # Run VACUUM to reclaim space and defragment
        sqlite3 "${db_path}" "VACUUM;" 2>/dev/null

        # Run ANALYZE to update query planner statistics
        sqlite3 "${db_path}" "ANALYZE;" 2>/dev/null

        # Run integrity check
        INTEGRITY=$(sqlite3 "${db_path}" "PRAGMA integrity_check;" 2>/dev/null)

        # Get database size after
        SIZE_AFTER=$(du -h "${db_path}" 2>/dev/null | cut -f1)

        if [ "${INTEGRITY}" = "ok" ]; then
            log "    [OK] ${db_name}: ${SIZE_BEFORE} -> ${SIZE_AFTER}"
        else
            log "    [WARNING] ${db_name}: integrity check failed"
        fi
    else
        log "  [SKIP] ${db_name}: not found"
    fi
}

# WebUI databases
if [ "${ENABLE_WEBUI}" = "true" ]; then
    optimize_sqlite "${WEBUI_DIR}/data/webui.db" "WebUI"
    optimize_sqlite "${WEBUI_DIR}/data/sessions.db" "WebUI Sessions"
fi

# Payments processor database
NEED_PAYMENTS="false"
case "${ENABLE_MONERO_TARI_POOL}" in
    merge|merged|monero_only|tari_only) NEED_PAYMENTS="true" ;;
esac
[ "${ENABLE_ALEO_POOL}" = "true" ] && NEED_PAYMENTS="true"

if [ "${NEED_PAYMENTS}" = "true" ]; then
    optimize_sqlite "${PAYMENTS_DIR}/data/payments.db" "Payments"
fi

# Pool-specific databases
if [ "${ENABLE_MONERO_TARI_POOL}" = "monero_only" ]; then
    # monero-pool uses LMDB, not SQLite - skip
    log "  [INFO] monero-pool uses LMDB (no SQLite maintenance needed)"
fi

# =============================================================================
# 2. LOG ROTATION
# =============================================================================
log ""
log "2. Log rotation..."

LOGROTATE_CONF="${BASE_DIR}/config/logrotate.conf"
LOGROTATE_STATE="${BASE_DIR}/config/logrotate.state"

if [ -f "${LOGROTATE_CONF}" ]; then
    # Run logrotate with our custom config
    /usr/sbin/logrotate -s "${LOGROTATE_STATE}" "${LOGROTATE_CONF}" 2>&1 | while read line; do
        log "  ${line}"
    done

    if [ $? -eq 0 ]; then
        log "  [OK] Log rotation complete (includes compression of ${LOG_COMPRESS_AFTER_DAYS}+ day old logs)"
    else
        log "  [WARNING] Log rotation had issues"
    fi
else
    log "  [SKIP] Logrotate config not found: ${LOGROTATE_CONF}"
fi

# =============================================================================
# 3. CLEANUP OLD FILES
# =============================================================================
log ""
log "3. Cleanup..."

# Remove old log archives (older than LOG_RETENTION_DAYS)
DELETED_COUNT=0
for dir in "${BITCOIN_DIR}/logs" "${BCHN_DIR}/logs" "${DIGIBYTE_DIR}/logs" \
           "${MONERO_DIR}/logs" "${TARI_DIR}/logs" "${ALEO_DIR}/logs" \
           "${BTC_CKPOOL_DIR}/logs" "${BCH_CKPOOL_DIR}/logs" "${DGB_CKPOOL_DIR}/logs" \
           "${XMR_MONERO_POOL_DIR}/logs" "${XTM_MINER_DIR}/logs" "${XMR_XTM_MERGE_DIR}/logs" \
           "${ALEO_POOL_DIR}/logs" "${WEBUI_DIR}/logs" "${PAYMENTS_DIR}/logs" \
           "${MONERO_DIR}/wallet/logs" "${TARI_DIR}/wallet/logs" "${BASE_DIR}/logs/startup"; do
    if [ -d "${dir}" ]; then
        COUNT=$(find "${dir}" -name "*.gz" -mtime +${LOG_RETENTION_DAYS} -delete -print 2>/dev/null | wc -l)
        DELETED_COUNT=$((DELETED_COUNT + COUNT))
    fi
done

log "  Removed ${DELETED_COUNT} old log archive(s)"

# Remove temporary files older than 7 days
find /tmp -name "solo-pool-*" -mtime +7 -delete 2>/dev/null || true

# =============================================================================
# 4. BACKUP
# =============================================================================
log ""
log "4. Running backup..."

BACKUP_SCRIPT="${BIN_DIR}/backup.sh"
if [ -x "${BACKUP_SCRIPT}" ]; then
    "${BACKUP_SCRIPT}"
else
    log "  [SKIP] Backup script not found: ${BACKUP_SCRIPT}"
fi

# =============================================================================
# 5. DISK USAGE REPORT
# =============================================================================
log ""
log "5. Disk usage report..."

report_disk_usage() {
    local path="$1"
    local name="$2"

    if [ -d "${path}" ]; then
        SIZE=$(du -sh "${path}" 2>/dev/null | cut -f1)
        log "  ${name}: ${SIZE}"
    fi
}

report_disk_usage "${NODE_DIR}" "Nodes"
report_disk_usage "${POOL_DIR}" "Pools"
report_disk_usage "${WEBUI_DIR}" "WebUI"
report_disk_usage "${PAYMENTS_DIR}" "Payments"

# Total base directory
TOTAL=$(du -sh "${BASE_DIR}" 2>/dev/null | cut -f1)
log "  Total (${BASE_DIR}): ${TOTAL}"

# =============================================================================
# COMPLETE
# =============================================================================
log ""
log "=============================================="
log "Maintenance complete"
log "=============================================="
