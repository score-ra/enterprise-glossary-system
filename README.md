# Enterprise Glossary Management System (EGMS)

A centralized, URI-based enterprise glossary that serves as the single source of truth for organizational terminology, accessible to both humans and AI systems.

## Problem

Teams use different terms for the same concepts, glossary terms are scattered across wikis, Confluence, spreadsheets, and READMEs, and AI systems receive inconsistent context leading to poor responses.

## Key Objectives

1. **Standardization** -- One authoritative source for all company terminology
2. **Accessibility** -- Easily discoverable and queryable by all stakeholders
3. **AI Integration** -- Machine-readable (RDF/semantic web) format for AI agents
4. **Maintainability** -- Version control, audit trails, and automated backups
5. **Scalability** -- Support thousands of terms across departments and domains
6. **Integration** -- API access for embedding in documentation, systems, and tools
7. **Multilingual** -- Support for English, Spanish, and French labels/definitions
8. **Security** -- Role-based access control for read/write/admin operations

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Platform | [SKOSMOS](https://skosmos.org/) (open-source, semantic web-native) |
| Storage | [Apache Jena Fuseki](https://jena.apache.org/documentation/fuseki2/) (RDF triple store) |
| Cache | [Varnish](https://varnish-cache.org/) (HTTP cache between SKOSMOS and Fuseki) |
| Gateway | [Nginx](https://nginx.org/) (reverse proxy with RBAC) |
| Data Format | [SKOS](https://www.w3.org/TR/skos-reference/) (W3C standard, RDF/Turtle) |
| CI/CD | GitHub Actions (SKOS validation on push) |
| Infrastructure | Docker Compose (local dev), Cloud hosting (production) |

## Quick Start

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/)
- Python 3.8+ (for validation and CSV conversion scripts)
- curl (for data loading and testing)

### Setup

```bash
# 1. Clone and configure
git clone <repo-url>
cd enterprise-glossary-system
cp .env.example .env        # Edit passwords

# 2. Set up RBAC credentials
./scripts/setup-auth.sh

# 3. Start services
docker compose up -d

# 4. Load vocabulary data
./scripts/load-data.sh

# 5. Browse the glossary
open http://localhost:8080   # Gateway (with RBAC)
open http://localhost:9090   # SKOSMOS direct (dev only)
```

### Service Endpoints

| Service | URL | Purpose |
|---------|-----|---------|
| Gateway | http://localhost:8080 | Public entry point with RBAC |
| SKOSMOS | http://localhost:9090 | Direct web UI (dev only) |
| SKOSMOS REST API | http://localhost:9090/rest/v1/ | JSON-LD API for integrations |
| Fuseki SPARQL | http://localhost:3030/skosmos/sparql | SPARQL query endpoint |
| Fuseki Admin | http://localhost:3030 | Fuseki admin interface |
| Varnish Cache | http://localhost:9031 | SPARQL cache (internal) |

### Gateway RBAC Model

| Role | Read UI/Search | SPARQL Queries | Write/Update | Admin |
|------|---------------|----------------|-------------|-------|
| Anonymous | Yes | Yes | No | No |
| Editor | Yes | Yes | Yes | No |
| Admin | Yes | Yes | Yes | Yes |

### Common Operations

```bash
# Load/reload vocabulary data
./scripts/load-data.sh

# Validate SKOS vocabulary files
pip install -r scripts/requirements.txt
python scripts/validate-skos.py data/*.ttl

# Run integration tests
./scripts/test.sh              # All tests (requires running services)
./scripts/test.sh --offline    # Validation only

# Export data from Fuseki
./scripts/export-data.sh

# Create versioned snapshot
./scripts/snapshot.sh --message "Q1 2026 release"

# Compare snapshots (audit trail)
python scripts/audit-log.py --manifest snapshots/manifest.json

# Run automated backup
./scripts/backup.sh --verify

# Health check
./scripts/health-check.sh
./scripts/health-check.sh --json   # For monitoring systems

# Convert CSV to SKOS Turtle
python scripts/csv-to-skos.py data/template.csv -o data/new-terms.ttl

# Export SKOS to CSV
python scripts/skos-to-csv.py data/*.ttl -o export.csv
```

## Project Structure

```
enterprise-glossary-system/
|-- CLAUDE.md                      # AI assistant instructions
|-- README.md                      # This file
|-- .env.example                   # Environment variable template
|-- docker-compose.yml             # Fuseki + Varnish + SKOSMOS + Nginx
|-- .github/
|   |-- workflows/validate.yml    # CI/CD: SKOS validation + smoke tests
|   +-- pull_request_template.md  # PR template
|-- config/
|   |-- fuseki/skosmos.ttl         # Fuseki assembler (TDB2 + Lucene index)
|   |-- skosmos/config.ttl         # SKOSMOS vocabulary config (multilingual)
|   |-- varnish/default.vcl        # Varnish cache rules
|   +-- nginx/
|       |-- nginx.conf             # Reverse proxy + RBAC rules
|       +-- auth/                  # htpasswd files (generated)
|-- data/
|   |-- concept-scheme.ttl         # SKOS concept scheme + top categories
|   |-- enterprise-glossary.ttl    # 25 sample terms (en/es/fr)
|   +-- template.csv               # CSV template for bulk import
|-- scripts/
|   |-- load-data.sh               # Load Turtle files into Fuseki
|   |-- export-data.sh             # Export data as timestamped Turtle
|   |-- validate-skos.py           # Validate SKOS vocabulary files
|   |-- csv-to-skos.py             # Convert CSV to SKOS Turtle
|   |-- skos-to-csv.py             # Export SKOS to CSV
|   |-- test.sh                    # Run all integration tests
|   |-- setup-auth.sh              # Generate RBAC htpasswd files
|   |-- snapshot.sh                # Create versioned glossary snapshot
|   |-- audit-log.py               # Compare snapshots for audit trail
|   |-- backup.sh                  # Automated backup with retention
|   |-- health-check.sh            # Service health monitoring
|   +-- requirements.txt           # Python dependencies
|-- tests/
|   |-- test-sparql-queries.sh     # SPARQL endpoint tests
|   |-- test-rest-api.sh           # SKOSMOS REST API tests
|   |-- test-search.sh             # Search functionality tests
|   |-- test-multilingual.sh       # Multilingual label tests
|   +-- test-rbac.sh               # RBAC enforcement tests
|-- docs/
|   |-- design-architecture.md     # Technical design guide
|   +-- prds/prd.md                # Product Requirements Document
+-- _inbox/                        # Incoming items to triage
```

## REST API Examples

```bash
# List all vocabularies
curl http://localhost:9090/rest/v1/vocabularies?lang=en

# Search for a term (English)
curl http://localhost:9090/rest/v1/enterprise-glossary/search?query=deployment&lang=en

# Search for a term (Spanish)
curl http://localhost:9090/rest/v1/enterprise-glossary/search?query=Pipeline*&lang=es

# Get top-level concepts
curl http://localhost:9090/rest/v1/enterprise-glossary/topConcepts?lang=en

# Get concept data by URI
curl "http://localhost:9090/rest/v1/enterprise-glossary/data?uri=http://glossary.example.org/terms/ci-cd&lang=en"

# Get broader concepts
curl "http://localhost:9090/rest/v1/enterprise-glossary/broader?uri=http://glossary.example.org/terms/ci-cd&lang=en"
```

## Adding New Terms

### Option 1: Edit Turtle directly

Add terms to `data/enterprise-glossary.ttl` following the existing pattern, then reload:

```bash
python scripts/validate-skos.py data/*.ttl   # Validate first
./scripts/load-data.sh                        # Reload into Fuseki
```

### Option 2: CSV import

1. Fill in `data/template.csv` with new terms
2. Convert to Turtle: `python scripts/csv-to-skos.py data/template.csv -o data/new-terms.ttl`
3. Validate: `python scripts/validate-skos.py data/*.ttl`
4. Load: `./scripts/load-data.sh`

### Multilingual Labels

Terms support labels and definitions in English (`@en`), Spanish (`@es`), and French (`@fr`):

```turtle
eg:my-term a skos:Concept ;
    skos:prefLabel "My Term"@en ;
    skos:prefLabel "Mi Termino"@es ;
    skos:prefLabel "Mon Terme"@fr ;
    skos:definition "English definition."@en ;
    skos:definition "Definicion en espanol."@es ;
    skos:definition "Definition en francais."@fr ;
    skos:inScheme eg:enterprise-glossary .
```

## Backup & Recovery

```bash
# Create a backup
./scripts/backup.sh --verify

# Backups are stored in backups/ with automatic retention (14 by default)
./scripts/backup.sh --retain 30  # Keep last 30

# Create a versioned snapshot for audit
./scripts/snapshot.sh --version 1.0.0 --message "Initial production release"

# Compare snapshots to generate audit log
python scripts/audit-log.py snapshots/old.ttl snapshots/new.ttl -o audit.json
```

## License

This project is licensed under the MIT License.
