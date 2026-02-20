#!/usr/bin/env bash
# Export vocabulary data from Fuseki as a timestamped Turtle file.
#
# Usage:
#   ./scripts/export-data.sh                      # Export to exports/ directory
#   ./scripts/export-data.sh -o /path/to/dir      # Export to custom directory
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
OUTPUT_DIR="$PROJECT_DIR/exports"

while getopts "o:" opt; do
    case $opt in
        o) OUTPUT_DIR="$OPTARG" ;;
        *) echo "Usage: $0 [-o output_dir]" >&2; exit 1 ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_FILE="$OUTPUT_DIR/glossary-export-$TIMESTAMP.ttl"

echo "Exporting from Fuseki..."
echo "  Fuseki:  $FUSEKI_URL"
echo "  Graph:   $GRAPH_URI"
echo "  Output:  $OUTPUT_FILE"
echo ""

HTTP_CODE=$(curl -s -o "$OUTPUT_FILE" -w "%{http_code}" \
    -u "$FUSEKI_USER:$FUSEKI_PASS" \
    -H "Accept: text/turtle" \
    "$FUSEKI_URL/$DATASET/data?graph=$GRAPH_URI")

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    FILE_SIZE=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')
    echo "Export successful: $OUTPUT_FILE ($FILE_SIZE bytes)"
else
    echo "Export FAILED (HTTP $HTTP_CODE)" >&2
    rm -f "$OUTPUT_FILE"
    exit 1
fi
