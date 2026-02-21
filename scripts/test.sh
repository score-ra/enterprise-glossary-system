#!/usr/bin/env bash
# Run all integration tests for EGMS.
#
# Usage:
#   ./scripts/test.sh              # Run all tests
#   ./scripts/test.sh --offline    # Run offline tests only (validation)
#
# Expects Docker services running and data loaded for online tests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TOTAL_PASS=0
TOTAL_FAIL=0
OFFLINE_ONLY=false

if [ "${1:-}" = "--offline" ]; then
    OFFLINE_ONLY=true
fi

run_test() {
    local name="$1"
    local script="$2"

    echo ""
    echo "=========================================="
    echo " $name"
    echo "=========================================="
    if bash "$script"; then
        TOTAL_PASS=$((TOTAL_PASS + 1))
        echo ">> SUITE PASSED: $name"
    else
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
        echo ">> SUITE FAILED: $name"
    fi
}

echo "EGMS Integration Test Suite"
echo "$(date)"
echo ""

# Offline tests (always run)
if [ -f "$SCRIPT_DIR/requirements.txt" ] && command -v python3 > /dev/null 2>&1; then
    echo "-- Offline Tests --"

    echo ""
    echo "=========================================="
    echo " SKOS Validation"
    echo "=========================================="
    if python3 "$SCRIPT_DIR/validate-skos.py" "$PROJECT_DIR"/data/*.ttl; then
        TOTAL_PASS=$((TOTAL_PASS + 1))
        echo ">> SUITE PASSED: SKOS Validation"
    else
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
        echo ">> SUITE FAILED: SKOS Validation"
    fi
else
    echo "WARNING: Skipping SKOS validation (python3 or rdflib not available)"
fi

if [ "$OFFLINE_ONLY" = true ]; then
    echo ""
    echo "=========================================="
    echo " RESULTS (offline only)"
    echo "=========================================="
    echo "Suites passed: $TOTAL_PASS"
    echo "Suites failed: $TOTAL_FAIL"
    exit $TOTAL_FAIL
fi

# Online tests (require running services)
echo ""
echo "-- Online Tests (requires running services) --"

# Check if services are reachable
FUSEKI_URL="${FUSEKI_URL:-http://localhost:3030}"
SKOSMOS_URL="${SKOSMOS_URL:-http://localhost:9090}"

if ! curl -sf "$FUSEKI_URL/\$/ping" > /dev/null 2>&1; then
    echo "ERROR: Fuseki not reachable at $FUSEKI_URL"
    echo "Start services with: docker-compose up -d"
    exit 1
fi

if ! curl -sf -L "$SKOSMOS_URL/" > /dev/null 2>&1; then
    echo "ERROR: SKOSMOS not reachable at $SKOSMOS_URL"
    echo "Start services with: docker compose up -d"
    exit 1
fi

run_test "SPARQL Query Tests" "$PROJECT_DIR/tests/test-sparql-queries.sh"
run_test "REST API Tests" "$PROJECT_DIR/tests/test-rest-api.sh"
run_test "Search Tests" "$PROJECT_DIR/tests/test-search.sh"
run_test "Multilingual Tests" "$PROJECT_DIR/tests/test-multilingual.sh"

# RBAC tests (only if gateway is running)
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
if curl -sf "$GATEWAY_URL/health" > /dev/null 2>&1; then
    run_test "RBAC Tests" "$PROJECT_DIR/tests/test-rbac.sh"
else
    echo ""
    echo "SKIPPING: RBAC Tests (gateway not running at $GATEWAY_URL)"
fi

echo ""
echo "=========================================="
echo " FINAL RESULTS"
echo "=========================================="
echo "Suites passed: $TOTAL_PASS"
echo "Suites failed: $TOTAL_FAIL"

if [ "$TOTAL_FAIL" -gt 0 ]; then
    echo "OVERALL: FAILED"
    exit 1
else
    echo "OVERALL: PASSED"
    exit 0
fi
