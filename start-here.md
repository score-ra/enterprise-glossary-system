# Start Here - enterprise-glossary-system

> **Read this file at the start of every session. Update it at the end.**

## Current Status

| Field | Value |
|-------|-------|
| **Phase** | Phase 1: Setup (Weeks 1-4) |
| **Last Updated** | 2026-02-20 |
| **Last Session** | Phase 1 implementation -- infrastructure, data, testing |

## What's Done

- [x] Initial project setup (README, LICENSE, .gitignore)
- [x] PRD created (docs/prds/prd.md)
- [x] Design architecture doc started (docs/design-architecture.md)
- [x] Repository standardized against team template
- [x] Docker Compose setup (Fuseki + Varnish + SKOSMOS)
- [x] Fuseki assembler config (TDB2 + Lucene text index)
- [x] SKOSMOS config (vocabulary declaration, Fuseki connection via cache)
- [x] Varnish VCL config (cache SPARQL reads, bypass writes)
- [x] SKOS concept scheme with 4 top-level categories
- [x] 25 sample terms with full SKOS relationships
- [x] Data loading script (Fuseki Graph Store Protocol)
- [x] CSV-to-SKOS converter + CSV template
- [x] SKOS-to-CSV export script
- [x] SKOS validation script (syntax + required properties)
- [x] Integration test suite (SPARQL, REST API, search)
- [x] Backup/export script (timestamped Turtle export)
- [x] Docker health checks and restart policies
- [x] Documentation updated (README, .env.example, start-here.md)
- [ ] Verify end-to-end with Docker (manual)
- [ ] Pilot team onboarding

## What's Next

- [ ] Run `docker compose up -d` and verify all services start
- [ ] Run `./scripts/load-data.sh` and verify data loads
- [ ] Run `./scripts/test.sh` and verify all tests pass
- [ ] Pilot team onboarding

## Active Blockers

None

## Files Modified Recently

```
docker-compose.yml (new)
config/fuseki/skosmos.ttl (new)
config/skosmos/config.ttl (new)
config/varnish/default.vcl (new)
data/concept-scheme.ttl (new)
data/enterprise-glossary.ttl (new)
data/template.csv (new)
scripts/load-data.sh (new)
scripts/export-data.sh (new)
scripts/validate-skos.py (new)
scripts/csv-to-skos.py (new)
scripts/skos-to-csv.py (new)
scripts/test.sh (new)
scripts/requirements.txt (new)
tests/test-sparql-queries.sh (new)
tests/test-rest-api.sh (new)
tests/test-search.sh (new)
README.md (updated)
.env.example (updated)
start-here.md (updated)
```

## Quick Commands

```bash
# Start SKOSMOS + Fuseki + Varnish
docker compose up -d

# Load vocabulary data
./scripts/load-data.sh

# Run integration tests
./scripts/test.sh

# Validate SKOS files offline
pip install -r scripts/requirements.txt
python scripts/validate-skos.py data/*.ttl

# Check Fuseki status
curl http://localhost:3030/$/ping

# Check SKOSMOS status
curl http://localhost:9090

# Export data backup
./scripts/export-data.sh
```

## Notes

- Platform: SKOSMOS (open-source semantic web vocabulary browser)
- Storage: Apache Jena Fuseki (RDF triple store with SPARQL endpoint)
- Cache: Varnish (between SKOSMOS and Fuseki for SPARQL read caching)
- Data format: SKOS (W3C standard, RDF/Turtle serialization)
- See PRD for full requirements: docs/prds/prd.md
- See design doc for architecture: docs/design-architecture.md
- Docker images: secoresearch/fuseki, quay.io/natlibfi/skosmos, varnish:7.6
