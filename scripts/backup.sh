#!/usr/bin/env bash
# Automated backup of Fuseki glossary data with retention policy.
#
# Features:
#   - Exports vocabulary as timestamped Turtle file
#   - Verifies backup integrity (non-empty, valid HTTP response)
#   - Enforces retention policy (keep last N backups)
#   - Suitable for cron scheduling
#
# Usage:
#   ./scripts/backup.sh                    # Run backup with defaults
#   ./scripts/backup.sh --retain 30        # Keep last 30 backups
#   ./scripts/backup.sh --verify           # Verify after backup
#
# Environment variables:
#   FUSEKI_URL      - Fuseki base URL (default: http://localhost:3030)
#   FUSEKI_USER     - Fuseki admin user (default: admin)
#   FUSEKI_PASS     - Fuseki admin password (default: admin123)
#   GRAPH_URI       - Named graph URI (default: http://glossary.example.org/)
#   DATASET         - Fuseki dataset name (default: skosmos)
#   BACKUP_DIR      - Backup directory (default: ./backups)
#   BACKUP_RETAIN   - Number of backups to keep (default: 14)

set -euo pipefail

FUSEKI_URL="${FUSEKI_URL:-http://localhost:3030}"
FUSEKI_USER="${FUSEKI_USER:-admin}"
FUSEKI_PASS="${FUSEKI_PASS:-admin123}"
GRAPH_URI="${GRAPH_URI:-http://glossary.example.org/}"
DATASET="${DATASET:-skosmos}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_DIR/backups}"
RETAIN="${BACKUP_RETAIN:-14}"
VERIFY=false

while [ $# -gt 0 ]; do
    case "$1" in
        --retain) RETAIN="$2"; shift 2 ;;
        --verify) VERIFY=true; shift ;;
        --dir) BACKUP_DIR="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup-${TIMESTAMP}.ttl"
LOG_FILE="$BACKUP_DIR/backup.log"

log() {
    local msg="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# Check Fuseki is reachable
if ! curl -sf "$FUSEKI_URL/\$/ping" > /dev/null 2>&1; then
    log "ERROR: Fuseki not reachable at $FUSEKI_URL"
    exit 1
fi

# Export data
log "Starting backup to $BACKUP_FILE"

HTTP_CODE=$(curl -s -o "$BACKUP_FILE" -w "%{http_code}" \
    -u "$FUSEKI_USER:$FUSEKI_PASS" \
    -H "Accept: text/turtle" \
    "$FUSEKI_URL/$DATASET/data?graph=$GRAPH_URI")

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
    log "ERROR: Backup failed (HTTP $HTTP_CODE)"
    rm -f "$BACKUP_FILE"
    exit 1
fi

# Verify backup is non-empty
FILE_SIZE=$(wc -c < "$BACKUP_FILE" | tr -d ' ')
if [ "$FILE_SIZE" -lt 100 ]; then
    log "ERROR: Backup file suspiciously small ($FILE_SIZE bytes)"
    exit 1
fi

CHECKSUM=$(sha256sum "$BACKUP_FILE" | cut -d' ' -f1)
log "Backup complete: $(basename "$BACKUP_FILE") ($FILE_SIZE bytes, sha256:${CHECKSUM:0:16}...)"

# Optional: verify backup by parsing
if [ "$VERIFY" = true ]; then
    if command -v python3 > /dev/null 2>&1; then
        if python3 -c "
from rdflib import Graph
g = Graph()
g.parse('$BACKUP_FILE', format='turtle')
count = len(list(g.subjects()))
print(f'  Verified: {count} subjects in backup')
" 2>/dev/null; then
            log "Verification passed"
        else
            log "WARNING: Backup verification failed (rdflib parse error)"
        fi
    else
        log "WARNING: python3 not available for verification"
    fi
fi

# Retention: remove old backups beyond the limit
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/backup-*.ttl 2>/dev/null | wc -l | tr -d ' ')
if [ "$BACKUP_COUNT" -gt "$RETAIN" ]; then
    REMOVE_COUNT=$((BACKUP_COUNT - RETAIN))
    log "Retention: removing $REMOVE_COUNT old backup(s) (keeping $RETAIN)"
    ls -1t "$BACKUP_DIR"/backup-*.ttl | tail -n "$REMOVE_COUNT" | while read -r old_file; do
        log "  Removing: $(basename "$old_file")"
        rm -f "$old_file"
    done
fi

log "Backup process complete. $BACKUP_COUNT total backup(s), retaining $RETAIN."
