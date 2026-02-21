#!/usr/bin/env bash
# Test multilingual label support (FR-009).
#
# Expects SKOSMOS and Fuseki running with multilingual data loaded.

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

echo "=== Multilingual Tests ==="
echo ""

# Test 1: Spanish prefLabel via SPARQL
echo "Test: Spanish labels exist in Fuseki"
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=SELECT ?label WHERE { <http://glossary.example.org/terms/deployment-pipeline> <http://www.w3.org/2004/02/skos/core#prefLabel> ?label . FILTER(lang(?label) = 'es') }" \
    "$FUSEKI_URL/$DATASET/sparql")
assert_contains "Spanish label for Deployment Pipeline" "$RESPONSE" "Pipeline de Despliegue"

# Test 2: French prefLabel via SPARQL
echo "Test: French labels exist in Fuseki"
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=SELECT ?label WHERE { <http://glossary.example.org/terms/api> <http://www.w3.org/2004/02/skos/core#prefLabel> ?label . FILTER(lang(?label) = 'fr') }" \
    "$FUSEKI_URL/$DATASET/sparql")
assert_contains "French label for API" "$RESPONSE" "API"

# Test 3: Spanish definitions via SPARQL
echo "Test: Spanish definitions exist"
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=SELECT ?def WHERE { <http://glossary.example.org/terms/ci-cd> <http://www.w3.org/2004/02/skos/core#definition> ?def . FILTER(lang(?def) = 'es') }" \
    "$FUSEKI_URL/$DATASET/sparql")
assert_contains "Spanish definition for CI/CD" "$RESPONSE" "automatiz"

# Test 4: REST API search with Spanish lang parameter
echo "Test: SKOSMOS search with lang=es"
RESPONSE=$(curl -s "$SKOSMOS_URL/rest/v1/$VOCAB_ID/search?query=Pipeline*&lang=es")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SKOSMOS_URL/rest/v1/$VOCAB_ID/search?query=Pipeline*&lang=es")
assert_http_ok "Search endpoint responds for Spanish" "$HTTP_CODE"

# Test 5: Top concepts with French language
echo "Test: Top concepts respond with lang=fr"
RESPONSE=$(curl -s "$SKOSMOS_URL/rest/v1/$VOCAB_ID/topConcepts?lang=fr")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SKOSMOS_URL/rest/v1/$VOCAB_ID/topConcepts?lang=fr")
assert_http_ok "Top concepts endpoint responds for French" "$HTTP_CODE"

# Test 6: Count multilingual labels
echo "Test: Multiple languages present"
RESPONSE=$(curl -s -H "Accept: application/sparql-results+json" \
    --data-urlencode "query=SELECT (COUNT(DISTINCT ?lang) AS ?count) WHERE { ?s <http://www.w3.org/2004/02/skos/core#prefLabel> ?label . BIND(lang(?label) AS ?lang) FILTER(?lang != '') }" \
    "$FUSEKI_URL/$DATASET/sparql")
assert_contains "Multiple languages indexed" "$RESPONSE" "count"

echo ""
echo "Multilingual Tests: $PASS passed, $FAIL failed"
exit $FAIL
