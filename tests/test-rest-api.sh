#!/usr/bin/env bash
# Test SKOSMOS REST API endpoints.
#
# Expects SKOSMOS to be running with data loaded.

set -euo pipefail

SKOSMOS_URL="${SKOSMOS_URL:-http://localhost:9090}"
VOCAB_ID="enterprise-glossary"
PASS=0
FAIL=0

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

echo "=== REST API Tests ==="
echo ""

# Test 1: SKOSMOS home page
echo "Test: SKOSMOS home page loads"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SKOSMOS_URL/")
assert_http_ok "Home page accessible" "$HTTP_CODE"

# Test 2: REST API vocabularies endpoint
echo "Test: List vocabularies"
RESPONSE=$(curl -s "$SKOSMOS_URL/rest/v1/vocabularies?lang=en")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SKOSMOS_URL/rest/v1/vocabularies?lang=en")
assert_http_ok "Vocabularies endpoint responds" "$HTTP_CODE"
assert_contains "Enterprise Glossary listed" "$RESPONSE" "Enterprise Glossary"

# Test 3: Vocabulary info
echo "Test: Vocabulary info"
RESPONSE=$(curl -s "$SKOSMOS_URL/rest/v1/$VOCAB_ID/?lang=en")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SKOSMOS_URL/rest/v1/$VOCAB_ID/?lang=en")
assert_http_ok "Vocabulary info endpoint responds" "$HTTP_CODE"

# Test 4: Top concepts
echo "Test: Top concepts"
RESPONSE=$(curl -s "$SKOSMOS_URL/rest/v1/$VOCAB_ID/topConcepts?lang=en")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SKOSMOS_URL/rest/v1/$VOCAB_ID/topConcepts?lang=en")
assert_http_ok "Top concepts endpoint responds" "$HTTP_CODE"
assert_contains "Top concepts include Engineering" "$RESPONSE" "Engineering"

# Test 5: Concept data
echo "Test: Concept data"
CONCEPT_URI="http://glossary.example.org/terms/deployment-pipeline"
RESPONSE=$(curl -s "$SKOSMOS_URL/rest/v1/$VOCAB_ID/data?uri=$CONCEPT_URI&lang=en")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SKOSMOS_URL/rest/v1/$VOCAB_ID/data?uri=$CONCEPT_URI&lang=en")
assert_http_ok "Concept data endpoint responds" "$HTTP_CODE"
assert_contains "Concept data contains prefLabel" "$RESPONSE" "Deployment Pipeline"

echo ""
echo "REST API Tests: $PASS passed, $FAIL failed"
exit $FAIL
