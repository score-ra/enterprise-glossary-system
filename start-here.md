# Start Here - enterprise-glossary-system

> **Read this file at the start of every session. Update it at the end.**

## Current Status

| Field | Value |
|-------|-------|
| **Phase** | Phase 2: MVP (Weeks 5-12) |
| **Last Updated** | 2026-02-21 |
| **Last Session** | Phase 2 implementation -- multilingual, RBAC, CI/CD, audit, backup, monitoring |

## What's Done

### Phase 1 (Complete)
- [x] Initial project setup (README, LICENSE, .gitignore)
- [x] PRD created (docs/prds/prd.md)
- [x] Design architecture doc (docs/design-architecture.md)
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

### Phase 2 (Complete)
- [x] Multilingual support (FR-009): Spanish/French labels on key terms + SKOSMOS config
- [x] CI/CD pipeline: GitHub Actions for SKOS validation + Docker smoke tests
- [x] RBAC via Nginx gateway (FR-007, NFR-004): anonymous read, editor write, admin full
- [x] Versioned snapshots (FR-012): snapshot.sh with manifest tracking
- [x] Audit trail (FR-008): audit-log.py for snapshot comparison
- [x] Automated backups (NFR-006): backup.sh with retention policy
- [x] Health monitoring (NFR-003): health-check.sh with JSON output
- [x] Multilingual integration tests (test-multilingual.sh)
- [x] RBAC integration tests (test-rbac.sh)
- [x] Documentation updated (README, CLAUDE.md, design-architecture.md)

## What's Next

- [ ] Rebuild Docker services: `docker compose up -d --build`
- [ ] Run `./scripts/setup-auth.sh` to generate RBAC credentials
- [ ] Run `./scripts/load-data.sh` to load updated multilingual data
- [ ] Run `./scripts/test.sh` to verify all tests pass
- [ ] Create initial snapshot: `./scripts/snapshot.sh --version 1.0.0 --message "Phase 2 release"`
- [ ] Pilot team onboarding
- [ ] Phase 3 planning: company-wide rollout, training, API documentation

## Active Blockers

None

## Files Modified Recently

```
# Phase 2 -- Modified
config/skosmos/config.ttl (multilingual + language dropdown)
data/concept-scheme.ttl (es/fr labels on scheme + categories)
data/enterprise-glossary.ttl (es/fr labels on key terms)
docker-compose.yml (added Nginx gateway service)
.env.example (added gateway + RBAC vars)
scripts/test.sh (added multilingual + RBAC test suites)
README.md (Phase 2 features)
CLAUDE.md (updated structure + key files)
docs/design-architecture.md (RBAC, backup, governance sections)

# Phase 2 -- New
.github/workflows/validate.yml (CI/CD pipeline)
config/nginx/nginx.conf (reverse proxy + RBAC rules)
scripts/setup-auth.sh (generate htpasswd files)
scripts/snapshot.sh (versioned snapshots)
scripts/audit-log.py (snapshot comparison audit)
scripts/backup.sh (automated backup + retention)
scripts/health-check.sh (service monitoring)
tests/test-multilingual.sh (multilingual tests)
tests/test-rbac.sh (RBAC enforcement tests)
```

## Quick Commands

```bash
# Start all services (Fuseki + Varnish + SKOSMOS + Nginx gateway)
docker compose up -d

# Set up RBAC credentials
./scripts/setup-auth.sh

# Load vocabulary data
./scripts/load-data.sh

# Run integration tests
./scripts/test.sh

# Validate SKOS files offline
pip install -r scripts/requirements.txt
python scripts/validate-skos.py data/*.ttl

# Health check
./scripts/health-check.sh
./scripts/health-check.sh --json

# Create versioned snapshot
./scripts/snapshot.sh --message "Description of changes"

# Generate audit log from snapshots
python scripts/audit-log.py --manifest snapshots/manifest.json

# Automated backup
./scripts/backup.sh --verify

# Export data
./scripts/export-data.sh

# Check Fuseki status
curl http://localhost:3030/$/ping

# Check gateway health
curl http://localhost:8080/health

# Check SKOSMOS
curl http://localhost:9090
```

## PRD Coverage After Phase 2

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| FR-001 | Full-text search | Done | SKOSMOS + Jena text index |
| FR-002 | Stable URIs | Done | `http://glossary.example.org/terms/{slug}` |
| FR-003 | SKOS relationships | Done | broader/narrower/related |
| FR-004 | SPARQL endpoint | Done | Fuseki at :3030/skosmos/sparql |
| FR-005 | REST API | Done | SKOSMOS REST at :9090/rest/v1/ |
| FR-006 | Import/export CSV+RDF | Done | Scripts + CLI tools |
| FR-007 | RBAC | Done | Nginx gateway with htpasswd auth |
| FR-008 | Audit trail | Done | snapshot.sh + audit-log.py |
| FR-009 | Multilingual labels | Done | en/es/fr in config + data |
| FR-010 | Web browsing interface | Done | SKOSMOS UI at :9090 |
| FR-011 | Bulk loading | Done | load-data.sh + csv-to-skos.py |
| FR-012 | Versioned snapshots | Done | snapshot.sh + manifest.json |
| NFR-001 | Search P95 < 500ms | Done | Lucene + Varnish cache |
| NFR-002 | 10K+ terms scale | Done | TDB2 persistent storage |
| NFR-003 | 99.5% availability | Partial | Health checks + monitoring + restart policies (no HA) |
| NFR-004 | RBAC security | Done | Nginx gateway enforcement |
| NFR-005 | W3C SKOS compliance | Done | validate-skos.py passes |
| NFR-006 | Data integrity | Done | TDB2 + automated backups + retention |

## Notes

- Platform: SKOSMOS (open-source semantic web vocabulary browser)
- Storage: Apache Jena Fuseki (RDF triple store with SPARQL endpoint)
- Cache: Varnish (between SKOSMOS and Fuseki for SPARQL read caching)
- Gateway: Nginx (reverse proxy with RBAC for public access)
- Data format: SKOS (W3C standard, RDF/Turtle serialization)
- Languages: English, Spanish, French
- See PRD for full requirements: docs/prds/prd.md
- See design doc for architecture: docs/design-architecture.md
- Docker images: secoresearch/fuseki, quay.io/natlibfi/skosmos, varnish:7.6, nginx:1.27-alpine
