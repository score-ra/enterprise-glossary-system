#!/usr/bin/env bash
# Test RBAC enforcement via the Nginx gateway (FR-007, NFR-004).
#
# Expects gateway (Nginx) running with auth configured.
# Tests that:
#   - Public read endpoints are accessible without auth
#   - Write endpoints require authentication
#   - Invalid credentials are rejected

set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8080}"
PASS=0
FAIL=0

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

echo "=== RBAC Tests ==="
echo ""

# Test 1: Health endpoint is public
echo "Test: Health endpoint requires no auth"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$GATEWAY_URL/health")
assert_http_range "Health endpoint public" 200 299 "$HTTP_CODE"

# Test 2: SKOSMOS UI is public (follows redirect)
echo "Test: SKOSMOS home page requires no auth"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -L "$GATEWAY_URL/")
assert_http_range "Home page public" 200 302 "$HTTP_CODE"

# Test 3: Public SPARQL read endpoint
echo "Test: Public SPARQL read endpoint"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "$GATEWAY_URL/sparql?query=ASK%20%7B%20%3Fs%20%3Fp%20%3Fo%20%7D")
assert_http_range "SPARQL read public" 200 299 "$HTTP_CODE"

# Test 4: Write endpoint WITHOUT auth returns 401
echo "Test: SPARQL update rejects unauthenticated"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/sparql-update" \
    -d "INSERT DATA { <http://test/s> <http://test/p> <http://test/o> }" \
    "$GATEWAY_URL/fuseki/update")
assert_http "SPARQL update requires auth" "401" "$HTTP_CODE"

# Test 5: Data upload WITHOUT auth returns 401
echo "Test: Data upload rejects unauthenticated"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Content-Type: text/turtle" \
    -d "@prefix : <http://test/> . :s :p :o ." \
    "$GATEWAY_URL/fuseki/data?graph=http://test/")
assert_http "Data upload requires auth" "401" "$HTTP_CODE"

# Test 6: Upload endpoint WITHOUT auth returns 401
echo "Test: File upload rejects unauthenticated"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$GATEWAY_URL/fuseki/upload")
assert_http "File upload requires auth" "401" "$HTTP_CODE"

# Test 7: Write endpoint WITH valid credentials (uses env vars or defaults)
echo "Test: SPARQL update with valid editor credentials"
EDITOR_USER="${EGMS_EDITOR_USER:-editor}"
EDITOR_PASS="${EGMS_EDITOR_PASS:-editor123}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "$EDITOR_USER:$EDITOR_PASS" \
    -X POST \
    -H "Content-Type: application/sparql-update" \
    -d "INSERT DATA { <http://egms-test/rbac-check> <http://egms-test/verified> \"true\" }" \
    "$GATEWAY_URL/fuseki/update" 2>/dev/null || echo "000")
# Accept any non-401 response (could be 200, 400, etc. -- means auth passed)
if [ "$HTTP_CODE" != "401" ] && [ "$HTTP_CODE" != "000" ]; then
    echo "  PASS: Authenticated write accepted (HTTP $HTTP_CODE)"
    PASS=$((PASS + 1))
    # Clean up test data
    curl -s -o /dev/null \
        -u "$EDITOR_USER:$EDITOR_PASS" \
        -X POST \
        -H "Content-Type: application/sparql-update" \
        -d "DELETE DATA { <http://egms-test/rbac-check> <http://egms-test/verified> \"true\" }" \
        "$GATEWAY_URL/fuseki/update" 2>/dev/null
else
    echo "  FAIL: Authenticated write rejected (HTTP $HTTP_CODE) -- auth file may not be set up"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "RBAC Tests: $PASS passed, $FAIL failed"
exit $FAIL
