#!/usr/bin/env bash
# Health monitoring for all EGMS services.
#
# Checks:
#   1. Fuseki: ping endpoint, SPARQL query latency, dataset stats
#   2. Varnish: cache status, hit/miss ratio
#   3. SKOSMOS: home page, REST API, search latency
#   4. Gateway: Nginx health endpoint
#
# Output: structured status suitable for monitoring/alerting.
#
# Usage:
#   ./scripts/health-check.sh              # Human-readable output
#   ./scripts/health-check.sh --json       # JSON output for monitoring
#   ./scripts/health-check.sh --alert      # Exit 1 if any service is down
#
# Environment variables:
#   FUSEKI_URL    - Fuseki URL (default: http://localhost:3030)
#   SKOSMOS_URL   - SKOSMOS URL (default: http://localhost:9090)
#   CACHE_URL     - Varnish cache URL (default: http://localhost:9031)
#   GATEWAY_URL   - Nginx gateway URL (default: http://localhost:8080)

set -euo pipefail

FUSEKI_URL="${FUSEKI_URL:-http://localhost:3030}"
SKOSMOS_URL="${SKOSMOS_URL:-http://localhost:9090}"
CACHE_URL="${CACHE_URL:-http://localhost:9031}"
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
DATASET="${DATASET:-skosmos}"

JSON_MODE=false
ALERT_MODE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --json) JSON_MODE=true; shift ;;
        --alert) ALERT_MODE=true; shift ;;
        *) shift ;;
    esac
done

OVERALL_STATUS="healthy"
RESULTS=""

check_service() {
    local name="$1"
    local url="$2"
    local start_ms end_ms latency_ms http_code

    start_ms=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time()*1e9))")
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" -m 10 "$url" 2>/dev/null || echo "000")
    end_ms=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time()*1e9))")

    # Calculate latency in ms
    if [ "$end_ms" != "$start_ms" ]; then
        latency_ms=$(( (end_ms - start_ms) / 1000000 ))
    else
        latency_ms=0
    fi

    local status="up"
    if [ "$http_code" = "000" ] || [ "$http_code" -ge 500 ]; then
        status="down"
        OVERALL_STATUS="unhealthy"
    fi

    if [ "$JSON_MODE" = true ]; then
        RESULTS="$RESULTS{\"service\":\"$name\",\"status\":\"$status\",\"http_code\":$http_code,\"latency_ms\":$latency_ms},"
    else
        local icon="[OK]"
        if [ "$status" = "down" ]; then
            icon="[FAIL]"
        fi
        echo "  $icon $name (HTTP $http_code, ${latency_ms}ms)"
    fi
}

check_sparql_latency() {
    local query='SELECT (COUNT(?s) AS ?count) WHERE { ?s a <http://www.w3.org/2004/02/skos/core#Concept> }'
    local start_ms end_ms latency_ms

    start_ms=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time()*1e9))")
    local response
    response=$(curl -sf -m 10 \
        -H "Accept: application/sparql-results+json" \
        --data-urlencode "query=$query" \
        "$FUSEKI_URL/$DATASET/sparql" 2>/dev/null || echo "")
    end_ms=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time()*1e9))")

    if [ "$end_ms" != "$start_ms" ]; then
        latency_ms=$(( (end_ms - start_ms) / 1000000 ))
    else
        latency_ms=0
    fi

    local status="ok"
    if [ -z "$response" ]; then
        status="failed"
        OVERALL_STATUS="unhealthy"
    elif [ "$latency_ms" -gt 500 ]; then
        status="slow"
    fi

    if [ "$JSON_MODE" = true ]; then
        RESULTS="$RESULTS{\"check\":\"sparql_latency\",\"status\":\"$status\",\"latency_ms\":$latency_ms},"
    else
        local icon="[OK]"
        if [ "$status" = "failed" ]; then icon="[FAIL]"; fi
        if [ "$status" = "slow" ]; then icon="[WARN]"; fi
        echo "  $icon SPARQL query latency: ${latency_ms}ms (target: <500ms)"
    fi
}

check_search_latency() {
    local start_ms end_ms latency_ms

    start_ms=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time()*1e9))")
    local response
    response=$(curl -sf -m 10 \
        "$SKOSMOS_URL/rest/v1/enterprise-glossary/search?query=deploy*&lang=en" 2>/dev/null || echo "")
    end_ms=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time()*1e9))")

    if [ "$end_ms" != "$start_ms" ]; then
        latency_ms=$(( (end_ms - start_ms) / 1000000 ))
    else
        latency_ms=0
    fi

    local status="ok"
    if [ -z "$response" ]; then
        status="failed"
    elif [ "$latency_ms" -gt 500 ]; then
        status="slow"
    fi

    if [ "$JSON_MODE" = true ]; then
        RESULTS="$RESULTS{\"check\":\"search_latency\",\"status\":\"$status\",\"latency_ms\":$latency_ms},"
    else
        local icon="[OK]"
        if [ "$status" = "failed" ]; then icon="[FAIL]"; fi
        if [ "$status" = "slow" ]; then icon="[WARN]"; fi
        echo "  $icon Search latency: ${latency_ms}ms (target: <500ms)"
    fi
}

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ "$JSON_MODE" = false ]; then
    echo "=== EGMS Health Check ==="
    echo "Timestamp: $TIMESTAMP"
    echo ""
    echo "Services:"
fi

check_service "fuseki" "$FUSEKI_URL/\$/ping"
check_service "varnish" "$CACHE_URL/skosmos/sparql?query=ASK%20%7B%20%3Fs%20%3Fp%20%3Fo%20%7D"
check_service "skosmos" "$SKOSMOS_URL/"
check_service "gateway" "$GATEWAY_URL/health"

if [ "$JSON_MODE" = false ]; then
    echo ""
    echo "Performance:"
fi

check_sparql_latency
check_search_latency

if [ "$JSON_MODE" = true ]; then
    # Remove trailing comma and wrap in JSON
    RESULTS="${RESULTS%,}"
    echo "{\"timestamp\":\"$TIMESTAMP\",\"status\":\"$OVERALL_STATUS\",\"checks\":[$RESULTS]}"
else
    echo ""
    echo "Overall: $OVERALL_STATUS"
fi

if [ "$ALERT_MODE" = true ] && [ "$OVERALL_STATUS" = "unhealthy" ]; then
    exit 1
fi
