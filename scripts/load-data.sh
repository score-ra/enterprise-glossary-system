#!/usr/bin/env bash
# Load SKOS vocabulary data into Fuseki via the Graph Store Protocol.
#
# Usage:
#   ./scripts/load-data.sh                    # Load all .ttl files from data/
#   ./scripts/load-data.sh data/custom.ttl    # Load a specific file
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

upload_file() {
    local file="$1"
    local filename
    filename="$(basename "$file")"

    echo "Loading $filename into <$GRAPH_URI> ..."

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -u "$FUSEKI_USER:$FUSEKI_PASS" \
        -H "Content-Type: text/turtle" \
        --data-binary "@$file" \
        "$FUSEKI_URL/$DATASET/data?graph=$GRAPH_URI")

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo "  OK ($http_code)"
    else
        echo "  FAILED (HTTP $http_code)" >&2
        return 1
    fi
}

# Wait for Fuseki to be ready
echo "Waiting for Fuseki at $FUSEKI_URL ..."
retries=0
max_retries=30
until curl -sf "$FUSEKI_URL/\$/ping" > /dev/null 2>&1; do
    retries=$((retries + 1))
    if [ "$retries" -ge "$max_retries" ]; then
        echo "ERROR: Fuseki not reachable after ${max_retries} attempts." >&2
        exit 1
    fi
    sleep 2
done
echo "Fuseki is ready."

# Determine files to load
if [ $# -gt 0 ]; then
    files=("$@")
else
    files=("$PROJECT_DIR"/data/*.ttl)
fi

if [ ${#files[@]} -eq 0 ]; then
    echo "No .ttl files found to load."
    exit 0
fi

echo ""
echo "Loading ${#files[@]} file(s) into Fuseki dataset '$DATASET'..."
echo "  Fuseki:  $FUSEKI_URL"
echo "  Graph:   $GRAPH_URI"
echo ""

errors=0
for file in "${files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "WARNING: File not found: $file" >&2
        errors=$((errors + 1))
        continue
    fi
    if ! upload_file "$file"; then
        errors=$((errors + 1))
    fi
done

echo ""
if [ "$errors" -gt 0 ]; then
    echo "Completed with $errors error(s)." >&2
    exit 1
else
    echo "All files loaded successfully."
fi
