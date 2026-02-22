#!/usr/bin/env bash
# Create a versioned, timestamped glossary snapshot for audit purposes.
#
# Each snapshot is a Turtle export with metadata (version, timestamp, term count).
# Snapshots are stored in snapshots/ with a manifest for tracking.
#
# Usage:
#   ./scripts/snapshot.sh                          # Auto-increment version
#   ./scripts/snapshot.sh --version 2.1.0          # Explicit version
#   ./scripts/snapshot.sh --message "Added Q1 terms"  # Add description
#
# Environment variables:
#   FUSEKI_URL   - Fuseki base URL (default: http://localhost:3030)
#   FUSEKI_USER  - Fuseki admin user (default: admin)
#   FUSEKI_PASS  - Fuseki admin password (default: admin123)
#   GRAPH_URI    - Named graph URI (default: http://glossary.example.org/)
#   DATASET      - Fuseki dataset name (default: skosmos)

set -euo pipefail

FUSEKI_URL="${FUSEKI_URL:-http://localhost:3030}"
FUSEKI_USER="${FUSEKI_USER:-admin}"
FUSEKI_PASS="${FUSEKI_PASS:-admin123}"
GRAPH_URI="${GRAPH_URI:-http://glossary.example.org/}"
DATASET="${DATASET:-skosmos}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SNAPSHOT_DIR="$PROJECT_DIR/snapshots"
MANIFEST="$SNAPSHOT_DIR/manifest.json"

VERSION=""
MESSAGE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --message) MESSAGE="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

mkdir -p "$SNAPSHOT_DIR"

# Initialize manifest if missing
if [ ! -f "$MANIFEST" ]; then
    echo '{"snapshots":[]}' > "$MANIFEST"
fi

# Auto-increment version if not specified
if [ -z "$VERSION" ]; then
    LAST_VERSION=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        m = json.load(f)
    if m['snapshots']:
        print(m['snapshots'][-1]['version'])
    else:
        print('0.0.0')
except Exception:
    print('0.0.0')
" "$MANIFEST" 2>/dev/null || echo "0.0.0")

    # Increment patch version
    IFS='.' read -r MAJOR MINOR PATCH <<< "$LAST_VERSION"
    PATCH=$((PATCH + 1))
    VERSION="$MAJOR.$MINOR.$PATCH"
fi

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SAFE_TS=$(date -u +%Y%m%d-%H%M%S)
SNAPSHOT_FILE="$SNAPSHOT_DIR/glossary-v${VERSION}-${SAFE_TS}.ttl"

echo "Creating snapshot v${VERSION}..."
echo "  Fuseki:    $FUSEKI_URL"
echo "  Graph:     $GRAPH_URI"
echo "  Output:    $SNAPSHOT_FILE"
echo ""

# Export data
HTTP_CODE=$(curl -s -o "$SNAPSHOT_FILE" -w "%{http_code}" \
    -u "$FUSEKI_USER:$FUSEKI_PASS" \
    -H "Accept: text/turtle" \
    "$FUSEKI_URL/$DATASET/data?graph=$GRAPH_URI")

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
    echo "Export FAILED (HTTP $HTTP_CODE)" >&2
    rm -f "$SNAPSHOT_FILE"
    exit 1
fi

# Count terms in export
TERM_COUNT=$(grep -c "a skos:Concept" "$SNAPSHOT_FILE" 2>/dev/null || true)
if [ -z "$TERM_COUNT" ]; then TERM_COUNT=0; fi
FILE_SIZE=$(wc -c < "$SNAPSHOT_FILE" | tr -d ' ')
CHECKSUM=$(sha256sum "$SNAPSHOT_FILE" | cut -d' ' -f1)

# Update manifest
SNAPSHOT_BASENAME=$(basename "$SNAPSHOT_FILE")
python3 -c "
import json, sys
manifest_path = sys.argv[1]
with open(manifest_path) as f:
    m = json.load(f)
m['snapshots'].append({
    'version': sys.argv[2],
    'timestamp': sys.argv[3],
    'file': sys.argv[4],
    'message': sys.argv[5],
    'term_count': int(sys.argv[6]),
    'file_size': int(sys.argv[7]),
    'sha256': sys.argv[8]
})
with open(manifest_path, 'w') as f:
    json.dump(m, f, indent=2)
" "$MANIFEST" "$VERSION" "$TIMESTAMP" "$SNAPSHOT_BASENAME" "$MESSAGE" "$TERM_COUNT" "$FILE_SIZE" "$CHECKSUM"

echo "Snapshot created successfully."
echo "  Version:    v${VERSION}"
echo "  Terms:      ${TERM_COUNT}"
echo "  Size:       ${FILE_SIZE} bytes"
echo "  SHA-256:    ${CHECKSUM}"
echo "  Timestamp:  ${TIMESTAMP}"
if [ -n "$MESSAGE" ]; then
    echo "  Message:    ${MESSAGE}"
fi
