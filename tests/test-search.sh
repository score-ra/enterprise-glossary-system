#!/usr/bin/env bash
# Test search functionality across Fuseki and SKOSMOS.
#
# Expects all services running with data loaded.

set -euo pipefail

SKOSMOS_URL="${SKOSMOS_URL:-http://localhost:9090}"
FUSEKI_URL="${FUSEKI_URL:-http://localhost:3030}"
DATASET="${DATASET:-skosmos}"
VOCAB_ID="enterprise-glossary"
PASS=0
FAIL=0

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

echo "=== Search Tests ==="
echo ""

# Test 1: SKOSMOS REST search for "deployment"
echo "Test: REST API search for 'deployment'"
RESPONSE=$(curl -s "$SKOSMOS_URL/rest/v1/$VOCAB_ID/search?query=deployment&lang=en")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SKOSMOS_URL/rest/v1/$VOCAB_ID/search?query=deployment&lang=en")
assert_http_ok "Search endpoint responds" "$HTTP_CODE"
assert_contains "Search finds Deployment Pipeline" "$RESPONSE" "Deployment Pipeline"

# Test 2: Search for acronym (SLA)
echo "Test: Search for acronym 'SLA'"
RESPONSE=$(curl -s "$SKOSMOS_URL/rest/v1/$VOCAB_ID/search?query=SLA&lang=en")
assert_contains "Search finds SLA" "$RESPONSE" "SLA"

# Test 3: Search for altLabel
echo "Test: Search for altLabel 'CICD'"
RESPONSE=$(curl -s "$SKOSMOS_URL/rest/v1/$VOCAB_ID/search?query=CICD&lang=en")
assert_contains "Search finds CI/CD via hidden label" "$RESPONSE" "CI/CD"

# Test 4: Global search across vocabularies
echo "Test: Global search for 'container'"
RESPONSE=$(curl -s "$SKOSMOS_URL/rest/v1/search?query=container&lang=en")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SKOSMOS_URL/rest/v1/search?query=container&lang=en")
assert_http_ok "Global search responds" "$HTTP_CODE"
assert_contains "Global search finds Container" "$RESPONSE" "Container"

# Test 5: Fuseki text search (Jena text index)
echo "Test: Fuseki text search via SPARQL"
QUERY='PREFIX text: <http://jena.apache.org/text#>
PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
SELECT ?s ?label WHERE {
  ?s text:query (skos:prefLabel "deploy*") .
  ?s skos:prefLabel ?label .
} LIMIT 5'
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=$QUERY" \
    "$FUSEKI_URL/$DATASET/sparql")
assert_contains "Text index search works" "$RESPONSE" "Deployment"

# Test 6: Lookup exact term
echo "Test: Lookup exact label 'Microservice'"
RESPONSE=$(curl -s "$SKOSMOS_URL/rest/v1/$VOCAB_ID/lookup?label=Microservice&lang=en")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SKOSMOS_URL/rest/v1/$VOCAB_ID/lookup?label=Microservice&lang=en")
assert_http_ok "Lookup endpoint responds" "$HTTP_CODE"

echo ""
echo "Search Tests: $PASS passed, $FAIL failed"
exit $FAIL
