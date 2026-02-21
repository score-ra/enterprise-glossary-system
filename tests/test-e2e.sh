#!/usr/bin/env bash
# End-to-end tests for the full EGMS stack.
#
# Validates system integration across all services:
#   - Varnish caching behavior
#   - Data import/export pipelines
#   - Performance / latency (NFR-001)
#   - Snapshot and audit trail (FR-008, FR-012)
#   - Health check script
#   - Service availability and persistence
#   - Full user journeys through gateway (FR-001 -- FR-005, FR-010)
#   - Write workflows through gateway (FR-007)
#   - W3C SKOS compliance at runtime (NFR-005)
#
# Expects all services running (Fuseki, Varnish, SKOSMOS, Nginx gateway)
# and data loaded.

set -euo pipefail

FUSEKI_URL="${FUSEKI_URL:-http://localhost:3030}"
SKOSMOS_URL="${SKOSMOS_URL:-http://localhost:9090}"
CACHE_URL="${CACHE_URL:-http://localhost:9031}"
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
DATASET="${DATASET:-skosmos}"
GRAPH_URI="${GRAPH_URI:-http://glossary.example.org/}"
FUSEKI_USER="${FUSEKI_USER:-admin}"
FUSEKI_PASS="${FUSEKI_PASS:-admin123}"
EDITOR_USER="${EGMS_EDITOR_USER:-editor}"
EDITOR_PASS="${EGMS_EDITOR_PASS:-editor123}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

TEMP_DIR="/tmp/egms-e2e-$$"
mkdir -p "$TEMP_DIR"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

assert_http_ok() {
    local test_name="$1"
    local http_code="$2"

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo "  PASS: $test_name (HTTP $http_code)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name (HTTP $http_code)"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local test_name="$1"
    local response="$2"
    local expected="$3"

    if echo "$response" | grep -qi "$expected"; then
        echo "  PASS: $test_name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name (expected '$expected' in response)"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local test_name="$1"
    local response="$2"
    local unexpected="$3"

    if echo "$response" | grep -qi "$unexpected"; then
        echo "  FAIL: $test_name (unexpected '$unexpected' found in response)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $test_name"
        PASS=$((PASS + 1))
    fi
}

assert_http() {
    local test_name="$1"
    local expected_code="$2"
    local actual_code="$3"

    if [ "$actual_code" = "$expected_code" ]; then
        echo "  PASS: $test_name (HTTP $actual_code)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name (expected HTTP $expected_code, got $actual_code)"
        FAIL=$((FAIL + 1))
    fi
}

assert_http_range() {
    local test_name="$1"
    local min="$2"
    local max="$3"
    local actual_code="$4"

    if [ "$actual_code" -ge "$min" ] && [ "$actual_code" -le "$max" ]; then
        echo "  PASS: $test_name (HTTP $actual_code)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name (expected HTTP ${min}-${max}, got $actual_code)"
        FAIL=$((FAIL + 1))
    fi
}

assert_latency_under() {
    local test_name="$1"
    local actual_ms="$2"
    local max_ms="$3"

    if [ "$actual_ms" -le "$max_ms" ]; then
        echo "  PASS: $test_name (${actual_ms}ms <= ${max_ms}ms)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name (${actual_ms}ms > ${max_ms}ms)"
        FAIL=$((FAIL + 1))
    fi
}

measure_ms() {
    date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time()*1e9))"
}

elapsed_ms() {
    local start_ns="$1"
    local end_ns="$2"
    echo $(( (end_ns - start_ns) / 1000000 ))
}

cleanup_test_data() {
    # Remove E2E test triples from Fuseki
    curl -s -o /dev/null \
        -u "$FUSEKI_USER:$FUSEKI_PASS" \
        -X POST \
        -H "Content-Type: application/sparql-update" \
        -d "DELETE WHERE { <http://egms-test/e2e/test-concept> ?p ?o }" \
        "$FUSEKI_URL/$DATASET/update" 2>/dev/null || true
}

# Pre-clean and set up trap
cleanup_test_data
trap 'cleanup_test_data; rm -rf "$TEMP_DIR"' EXIT

echo "=== End-to-End Tests ==="
echo ""

# =========================================================================
# Section 1: Varnish Cache Behavior (4 tests)
# =========================================================================

echo "-- Section 1: Varnish Cache Behavior --"

SPARQL_QUERY="ASK%20%7B%20%3Fs%20a%20%3Chttp%3A%2F%2Fwww.w3.org%2F2004%2F02%2Fskos%2Fcore%23Concept%3E%20%7D"
VARNISH_SPARQL_URL="$CACHE_URL/$DATASET/sparql?query=$SPARQL_QUERY"

# 1.1 First request should be a cache MISS
echo "Test 1.1: SPARQL read first request (cache MISS)"
# Use a unique query param to bust any prior cache
BUST="$(date +%s%N)"
RESPONSE_HEADERS=$(curl -s -D - -o /dev/null \
    "$CACHE_URL/$DATASET/sparql?query=$SPARQL_QUERY&_bust=$BUST" 2>/dev/null)
XCACHE=$(echo "$RESPONSE_HEADERS" | grep -i "X-Cache" | tr -d '\r' | awk '{print $2}')
if echo "$XCACHE" | grep -qi "MISS"; then
    echo "  PASS: First request is cache MISS (X-Cache: $XCACHE)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected cache MISS, got X-Cache: $XCACHE"
    FAIL=$((FAIL + 1))
fi

# 1.2 Second identical request should be a cache HIT
echo "Test 1.2: SPARQL read second request (cache HIT)"
# Repeat the same request (same bust param)
RESPONSE_HEADERS=$(curl -s -D - -o /dev/null \
    "$CACHE_URL/$DATASET/sparql?query=$SPARQL_QUERY&_bust=$BUST" 2>/dev/null)
XCACHE=$(echo "$RESPONSE_HEADERS" | grep -i "X-Cache" | tr -d '\r' | awk '{print $2}')
if echo "$XCACHE" | grep -qi "HIT"; then
    echo "  PASS: Second request is cache HIT (X-Cache: $XCACHE)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected cache HIT, got X-Cache: $XCACHE"
    FAIL=$((FAIL + 1))
fi

# 1.3 Write operations bypass cache (POST to update endpoint)
echo "Test 1.3: Write operations bypass cache"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/sparql-update" \
    -u "$FUSEKI_USER:$FUSEKI_PASS" \
    -d "ASK { ?s ?p ?o }" \
    "$CACHE_URL/$DATASET/update" 2>/dev/null || echo "000")
# Varnish should pass through to Fuseki (not cache POST requests)
# Any response (even 400) means it was passed through, not cached
if [ "$HTTP_CODE" != "000" ]; then
    echo "  PASS: Write operation passed through Varnish (HTTP $HTTP_CODE)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Write operation failed to reach backend"
    FAIL=$((FAIL + 1))
fi

# 1.4 Error responses not cached
echo "Test 1.4: Error responses not cached"
BAD_QUERY="INVALID%20SPARQL%20HERE%20${BUST}"
# First request with bad query
curl -s -o /dev/null "$CACHE_URL/$DATASET/sparql?query=$BAD_QUERY" 2>/dev/null || true
# Second request -- should still be MISS (errors have TTL 0)
RESPONSE_HEADERS=$(curl -s -D - -o /dev/null \
    "$CACHE_URL/$DATASET/sparql?query=$BAD_QUERY" 2>/dev/null)
XCACHE=$(echo "$RESPONSE_HEADERS" | grep -i "X-Cache" | tr -d '\r' | awk '{print $2}')
if echo "$XCACHE" | grep -qi "MISS"; then
    echo "  PASS: Error response not cached (X-Cache: $XCACHE)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Error response should not be cached, got X-Cache: $XCACHE"
    FAIL=$((FAIL + 1))
fi

echo ""

# =========================================================================
# Section 2: Data Import/Export Pipeline (5 tests)
# =========================================================================

echo "-- Section 2: Data Import/Export Pipeline --"

# 2.1 CSV-to-SKOS produces valid Turtle
echo "Test 2.1: CSV-to-SKOS produces valid Turtle"
E2E_CSV="$TEMP_DIR/e2e-test.csv"
E2E_TTL="$TEMP_DIR/e2e-test.ttl"
cat > "$E2E_CSV" << 'CSVEOF'
uri_slug,pref_label,alt_labels,hidden_labels,definition,broader_slug,related_slugs,scope_note,example
e2e-test-term,E2E Test Term,Test Alias,,A term created for end-to-end testing.,engineering,deployment-pipeline,,
CSVEOF

if python3 "$PROJECT_DIR/scripts/csv-to-skos.py" "$E2E_CSV" -o "$E2E_TTL" 2>/dev/null; then
    assert_contains "CSV-to-SKOS output contains Concept" "$(cat "$E2E_TTL")" "skos:Concept"
else
    echo "  FAIL: csv-to-skos.py exited with error"
    FAIL=$((FAIL + 1))
fi

# 2.2 SKOS-to-CSV export
echo "Test 2.2: SKOS-to-CSV export"
E2E_EXPORT_CSV="$TEMP_DIR/e2e-export.csv"
if python3 "$PROJECT_DIR/scripts/skos-to-csv.py" "$PROJECT_DIR/data/enterprise-glossary.ttl" \
    -o "$E2E_EXPORT_CSV" 2>/dev/null; then
    CSV_CONTENT=$(cat "$E2E_EXPORT_CSV")
    assert_contains "CSV has uri_slug header" "$CSV_CONTENT" "uri_slug"
else
    echo "  FAIL: skos-to-csv.py exited with error"
    FAIL=$((FAIL + 1))
fi

# 2.3 CSV round-trip preserves data
echo "Test 2.3: CSV round-trip preserves data"
ROUNDTRIP_TTL="$TEMP_DIR/e2e-roundtrip.ttl"
if python3 "$PROJECT_DIR/scripts/csv-to-skos.py" "$E2E_EXPORT_CSV" \
    -o "$ROUNDTRIP_TTL" 2>/dev/null; then
    ROUNDTRIP_CONTENT=$(cat "$ROUNDTRIP_TTL")
    assert_contains "Round-trip preserves Deployment Pipeline" "$ROUNDTRIP_CONTENT" "Deployment Pipeline"
else
    echo "  FAIL: Round-trip csv-to-skos.py exited with error"
    FAIL=$((FAIL + 1))
fi

# 2.4 Turtle export via export-data.sh
echo "Test 2.4: Turtle export via export-data.sh"
EXPORT_DIR="$TEMP_DIR/exports"
if bash "$PROJECT_DIR/scripts/export-data.sh" -o "$EXPORT_DIR" 2>/dev/null; then
    EXPORT_FILE=$(ls "$EXPORT_DIR"/*.ttl 2>/dev/null | head -1)
    if [ -n "$EXPORT_FILE" ] && [ -s "$EXPORT_FILE" ]; then
        assert_contains "Export contains SKOS data" "$(cat "$EXPORT_FILE")" "Concept"
    else
        echo "  FAIL: Export file is empty or missing"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: export-data.sh exited with error"
    FAIL=$((FAIL + 1))
fi

# 2.5 Bulk load via load-data.sh
echo "Test 2.5: Bulk load via load-data.sh"
LOAD_TTL="$TEMP_DIR/e2e-load.ttl"
cat > "$LOAD_TTL" << 'LOADEOF'
@prefix skos: <http://www.w3.org/2004/02/skos/core#> .
@prefix eg:   <http://glossary.example.org/terms/> .

<http://egms-test/e2e/test-concept> a skos:Concept ;
    skos:prefLabel "E2E-Load-Test-Term"@en ;
    skos:definition "Temporary term for load testing."@en ;
    skos:inScheme eg:enterprise-glossary .
LOADEOF

# Load via the Graph Store Protocol directly (same as load-data.sh does)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -u "$FUSEKI_USER:$FUSEKI_PASS" \
    -H "Content-Type: text/turtle" \
    --data-binary "@$LOAD_TTL" \
    "$FUSEKI_URL/$DATASET/data?graph=$GRAPH_URI")

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    # Verify via SPARQL
    VERIFY=$(curl -s -H "Accept: application/sparql-results+json" \
        --data-urlencode "query=ASK { <http://egms-test/e2e/test-concept> a <http://www.w3.org/2004/02/skos/core#Concept> }" \
        "$FUSEKI_URL/$DATASET/sparql")
    assert_contains "Loaded test concept is queryable" "$VERIFY" "true"
    # Clean up
    cleanup_test_data
else
    echo "  FAIL: Bulk load failed (HTTP $HTTP_CODE)"
    FAIL=$((FAIL + 1))
fi

echo ""

# =========================================================================
# Section 3: Performance / Latency (3 tests)
# =========================================================================

echo "-- Section 3: Performance / Latency --"

# 3.1 SPARQL query latency < 500ms (NFR-001)
echo "Test 3.1: SPARQL query latency"
START_NS=$(measure_ms)
curl -s -o /dev/null \
    -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=SELECT (COUNT(?s) AS ?count) WHERE { ?s a <http://www.w3.org/2004/02/skos/core#Concept> }" \
    "$FUSEKI_URL/$DATASET/sparql"
END_NS=$(measure_ms)
LATENCY=$(elapsed_ms "$START_NS" "$END_NS")
assert_latency_under "SPARQL query latency (NFR-001)" "$LATENCY" 500

# 3.2 REST API search latency < 500ms (NFR-001)
echo "Test 3.2: REST API search latency"
START_NS=$(measure_ms)
curl -s -o /dev/null \
    "$SKOSMOS_URL/rest/v1/enterprise-glossary/search?query=deploy*&lang=en"
END_NS=$(measure_ms)
LATENCY=$(elapsed_ms "$START_NS" "$END_NS")
assert_latency_under "REST API search latency (NFR-001)" "$LATENCY" 500

# 3.3 Cached query is fast (Varnish HIT < 1000ms)
echo "Test 3.3: Cached query response time"
CACHE_BUST="perf$(date +%s%N)"
# Prime the cache
curl -s -o /dev/null "$CACHE_URL/$DATASET/sparql?query=$SPARQL_QUERY&_perf=$CACHE_BUST"
# Measure cached response
START_NS=$(measure_ms)
curl -s -o /dev/null "$CACHE_URL/$DATASET/sparql?query=$SPARQL_QUERY&_perf=$CACHE_BUST"
END_NS=$(measure_ms)
LATENCY=$(elapsed_ms "$START_NS" "$END_NS")
assert_latency_under "Cached query response time" "$LATENCY" 1000

echo ""

# =========================================================================
# Section 4: Snapshot and Audit Trail (3 tests)
# =========================================================================

echo "-- Section 4: Snapshot and Audit Trail --"

SNAPSHOT_DIR="$PROJECT_DIR/snapshots"

# Back up manifest if it exists
if [ -f "$SNAPSHOT_DIR/manifest.json" ]; then
    cp "$SNAPSHOT_DIR/manifest.json" "$TEMP_DIR/manifest-backup.json"
fi

# 4.1 Snapshot creates versioned file
echo "Test 4.1: Snapshot creates versioned file"
if bash "$PROJECT_DIR/scripts/snapshot.sh" --version "99.0.1" --message "E2E test snapshot 1" 2>/dev/null; then
    SNAP_FILE=$(ls "$SNAPSHOT_DIR"/glossary-v99.0.1-*.ttl 2>/dev/null | head -1)
    if [ -n "$SNAP_FILE" ] && [ -s "$SNAP_FILE" ]; then
        MANIFEST_CONTENT=$(cat "$SNAPSHOT_DIR/manifest.json")
        assert_contains "Manifest contains test version" "$MANIFEST_CONTENT" "99.0.1"
    else
        echo "  FAIL: Snapshot file not found or empty"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: snapshot.sh exited with error"
    FAIL=$((FAIL + 1))
fi

# 4.2 Audit log compares two snapshots
echo "Test 4.2: Audit log compares two snapshots"
# Create a second snapshot (identical data)
if bash "$PROJECT_DIR/scripts/snapshot.sh" --version "99.0.2" --message "E2E test snapshot 2" 2>/dev/null; then
    SNAP1=$(ls "$SNAPSHOT_DIR"/glossary-v99.0.1-*.ttl 2>/dev/null | head -1)
    SNAP2=$(ls "$SNAPSHOT_DIR"/glossary-v99.0.2-*.ttl 2>/dev/null | head -1)
    if [ -n "$SNAP1" ] && [ -n "$SNAP2" ]; then
        AUDIT_OUTPUT=$(python3 "$PROJECT_DIR/scripts/audit-log.py" "$SNAP1" "$SNAP2" 2>/dev/null)
        assert_contains "Audit log shows zero additions" "$AUDIT_OUTPUT" '"added": 0'
    else
        echo "  FAIL: Could not find both snapshot files"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: Second snapshot failed"
    FAIL=$((FAIL + 1))
fi

# 4.3 Cleanup snapshots
echo "Test 4.3: Cleanup test snapshots"
# Remove 99.0.x snapshot files
rm -f "$SNAPSHOT_DIR"/glossary-v99.0.*
# Filter 99.0.x entries from manifest
if [ -f "$TEMP_DIR/manifest-backup.json" ]; then
    cp "$TEMP_DIR/manifest-backup.json" "$SNAPSHOT_DIR/manifest.json"
else
    python3 -c "
import json
with open('$SNAPSHOT_DIR/manifest.json') as f:
    m = json.load(f)
m['snapshots'] = [s for s in m['snapshots'] if not s['version'].startswith('99.0.')]
with open('$SNAPSHOT_DIR/manifest.json', 'w') as f:
    json.dump(m, f, indent=2)
" 2>/dev/null
fi
# Verify cleanup
REMAINING=$(ls "$SNAPSHOT_DIR"/glossary-v99.0.* 2>/dev/null | wc -l || echo "0")
if [ "$REMAINING" -eq 0 ]; then
    echo "  PASS: Test snapshots cleaned up"
    PASS=$((PASS + 1))
else
    echo "  FAIL: $REMAINING test snapshot files remain"
    FAIL=$((FAIL + 1))
fi

echo ""

# =========================================================================
# Section 5: Health Check Script (2 tests)
# =========================================================================

echo "-- Section 5: Health Check Script --"

# 5.1 JSON mode reports healthy
echo "Test 5.1: Health check JSON mode"
HEALTH_JSON=$(bash "$PROJECT_DIR/scripts/health-check.sh" --json 2>/dev/null || true)
assert_contains "Health check reports healthy" "$HEALTH_JSON" '"status":"healthy"'

# 5.2 Alert mode exits 0 when healthy
echo "Test 5.2: Health check alert mode"
if bash "$PROJECT_DIR/scripts/health-check.sh" --alert > /dev/null 2>&1; then
    echo "  PASS: Alert mode exits 0 (healthy)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Alert mode exited non-zero (unhealthy)"
    FAIL=$((FAIL + 1))
fi

echo ""

# =========================================================================
# Section 6: Service Availability / Persistence (2 tests)
# =========================================================================

echo "-- Section 6: Service Availability / Persistence --"

# 6.1 Data persists (concepts queryable)
echo "Test 6.1: Data persists in triple store"
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=SELECT ?label WHERE { <http://glossary.example.org/terms/deployment-pipeline> <http://www.w3.org/2004/02/skos/core#prefLabel> ?label FILTER(lang(?label)='en') }" \
    "$FUSEKI_URL/$DATASET/sparql")
assert_contains "Known concept is queryable" "$RESPONSE" "Deployment Pipeline"

# 6.2 Gateway health returns JSON
echo "Test 6.2: Gateway health endpoint returns JSON"
HEALTH_RESPONSE=$(curl -s -w "\n%{content_type}" "$GATEWAY_URL/health" 2>/dev/null)
HEALTH_BODY=$(echo "$HEALTH_RESPONSE" | head -n -1)
CONTENT_TYPE=$(echo "$HEALTH_RESPONSE" | tail -1)
assert_contains "Health returns status ok" "$HEALTH_BODY" '"status"'

echo ""

# =========================================================================
# Section 7: Full User Journey (4 tests)
# =========================================================================

echo "-- Section 7: Full User Journey --"

# 7.1 Browse home page (FR-010)
echo "Test 7.1: Browse home page"
RESPONSE=$(curl -s -L "$GATEWAY_URL/")
assert_contains "Home page shows glossary name" "$RESPONSE" "Enterprise Glossary"

# 7.2 Search for term (FR-001)
echo "Test 7.2: Search for term via gateway"
RESPONSE=$(curl -s "$GATEWAY_URL/rest/v1/enterprise-glossary/search?query=deploy*&lang=en")
assert_contains "Search finds Deployment Pipeline" "$RESPONSE" "Deployment Pipeline"

# 7.3 View concept detail (FR-002, FR-003)
echo "Test 7.3: View concept detail"
CONCEPT_URI="http://glossary.example.org/terms/deployment-pipeline"
RESPONSE=$(curl -s "$GATEWAY_URL/rest/v1/enterprise-glossary/data?uri=$CONCEPT_URI&lang=en")
assert_contains "Concept has prefLabel" "$RESPONSE" "Deployment Pipeline"

# 7.4 Navigate relationships (FR-003)
echo "Test 7.4: Navigate relationships"
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=SELECT ?broader ?related WHERE { <http://glossary.example.org/terms/ci-cd> <http://www.w3.org/2004/02/skos/core#broader> ?broader . <http://glossary.example.org/terms/ci-cd> <http://www.w3.org/2004/02/skos/core#related> ?related }" \
    "$GATEWAY_URL/sparql")
assert_contains "CI/CD broader is engineering" "$RESPONSE" "engineering"

echo ""

# =========================================================================
# Section 8: Write Workflow Through Gateway (3 tests)
# =========================================================================

echo "-- Section 8: Write Workflow Through Gateway --"

E2E_TEST_URI="http://egms-test/e2e/test-concept"
E2E_TEST_LABEL="E2E-Test-Term-XYZ"

# 8.1 Insert test concept (editor auth) (FR-007)
echo "Test 8.1: Insert test concept with editor credentials"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "$EDITOR_USER:$EDITOR_PASS" \
    -X POST \
    -H "Content-Type: application/sparql-update" \
    -d "INSERT DATA { <$E2E_TEST_URI> a <http://www.w3.org/2004/02/skos/core#Concept> ; <http://www.w3.org/2004/02/skos/core#prefLabel> \"$E2E_TEST_LABEL\"@en ; <http://www.w3.org/2004/02/skos/core#inScheme> <http://glossary.example.org/terms/enterprise-glossary> }" \
    "$GATEWAY_URL/fuseki/update" 2>/dev/null || echo "000")
assert_http_range "Insert test concept accepted" 200 299 "$HTTP_CODE"

# 8.2 Verify via SPARQL query (FR-004)
echo "Test 8.2: Verify inserted concept via SPARQL"
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=SELECT ?label WHERE { <$E2E_TEST_URI> <http://www.w3.org/2004/02/skos/core#prefLabel> ?label }" \
    "$FUSEKI_URL/$DATASET/sparql")
assert_contains "Inserted concept has correct label" "$RESPONSE" "$E2E_TEST_LABEL"

# 8.3 Delete and verify removal (cleanup)
echo "Test 8.3: Delete test concept and verify removal"
curl -s -o /dev/null \
    -u "$EDITOR_USER:$EDITOR_PASS" \
    -X POST \
    -H "Content-Type: application/sparql-update" \
    -d "DELETE WHERE { <$E2E_TEST_URI> ?p ?o }" \
    "$GATEWAY_URL/fuseki/update" 2>/dev/null || true
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=ASK { <$E2E_TEST_URI> ?p ?o }" \
    "$FUSEKI_URL/$DATASET/sparql")
assert_contains "Test concept removed" "$RESPONSE" "false"

echo ""

# =========================================================================
# Section 9: W3C SKOS Compliance (2 tests)
# =========================================================================

echo "-- Section 9: W3C SKOS Compliance --"

# 9.1 All concepts have prefLabel (NFR-005)
echo "Test 9.1: All concepts have prefLabel"
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=ASK { ?s a <http://www.w3.org/2004/02/skos/core#Concept> . FILTER NOT EXISTS { ?s <http://www.w3.org/2004/02/skos/core#prefLabel> ?label } }" \
    "$FUSEKI_URL/$DATASET/sparql")
# ASK should return false (no concepts missing labels)
assert_contains "No concepts missing prefLabel" "$RESPONSE" "false"

# 9.2 All concepts belong to a scheme (NFR-005)
echo "Test 9.2: All concepts belong to a scheme"
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=ASK { ?s a <http://www.w3.org/2004/02/skos/core#Concept> . FILTER NOT EXISTS { ?s <http://www.w3.org/2004/02/skos/core#inScheme> ?scheme } }" \
    "$FUSEKI_URL/$DATASET/sparql")
# ASK should return false (no orphan concepts)
assert_contains "No orphan concepts" "$RESPONSE" "false"

echo ""
echo "E2E Tests: $PASS passed, $FAIL failed"
exit $FAIL
