#!/usr/bin/env bash
# Test SPARQL query endpoints on Fuseki.
#
# Expects Fuseki to be running with data loaded.

set -euo pipefail

FUSEKI_URL="${FUSEKI_URL:-http://localhost:3030}"
DATASET="${DATASET:-skosmos}"
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

echo "=== SPARQL Query Tests ==="
echo ""

# Test 1: SPARQL endpoint responds
echo "Test: SPARQL endpoint reachable"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "$FUSEKI_URL/$DATASET/sparql?query=ASK%20%7B%20%3Fs%20%3Fp%20%3Fo%20%7D")
assert_http_ok "SPARQL endpoint responds" "$HTTP_CODE"

# Test 2: Query for ConceptScheme
echo "Test: ConceptScheme exists"
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=SELECT ?s WHERE { ?s a <http://www.w3.org/2004/02/skos/core#ConceptScheme> } LIMIT 1" \
    "$FUSEKI_URL/$DATASET/sparql")
assert_contains "ConceptScheme found" "$RESPONSE" "enterprise-glossary"

# Test 3: Count concepts
echo "Test: Concepts loaded"
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=SELECT (COUNT(?s) AS ?count) WHERE { ?s a <http://www.w3.org/2004/02/skos/core#Concept> }" \
    "$FUSEKI_URL/$DATASET/sparql")
assert_contains "Multiple concepts exist" "$RESPONSE" "count"

# Test 4: Query specific term
echo "Test: Query specific term (Deployment Pipeline)"
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=SELECT ?label WHERE { <http://glossary.example.org/terms/deployment-pipeline> <http://www.w3.org/2004/02/skos/core#prefLabel> ?label }" \
    "$FUSEKI_URL/$DATASET/sparql")
assert_contains "Deployment Pipeline found" "$RESPONSE" "Deployment Pipeline"

# Test 5: Query broader/narrower relationships
echo "Test: Broader relationships"
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=SELECT ?broader WHERE { <http://glossary.example.org/terms/ci-cd> <http://www.w3.org/2004/02/skos/core#broader> ?broader }" \
    "$FUSEKI_URL/$DATASET/sparql")
assert_contains "CI/CD has broader concept" "$RESPONSE" "engineering"

# Test 6: Query related relationships
echo "Test: Related relationships"
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=SELECT ?related WHERE { <http://glossary.example.org/terms/sla> <http://www.w3.org/2004/02/skos/core#related> ?related }" \
    "$FUSEKI_URL/$DATASET/sparql")
assert_contains "SLA has related concepts" "$RESPONSE" "kpi"

echo ""
echo "SPARQL Tests: $PASS passed, $FAIL failed"
exit $FAIL
