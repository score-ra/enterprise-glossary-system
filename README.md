# Enterprise Glossary Management System (EGMS)

A centralized, URI-based enterprise glossary that serves as the single source of truth for organizational terminology, accessible to both humans and AI systems.

## Problem

Teams use different terms for the same concepts, glossary terms are scattered across wikis, Confluence, spreadsheets, and READMEs, and AI systems receive inconsistent context leading to poor responses.

## Key Objectives

1. **Standardization** -- One authoritative source for all company terminology
2. **Accessibility** -- Easily discoverable and queryable by all stakeholders
3. **AI Integration** -- Machine-readable (RDF/semantic web) format for AI agents
4. **Maintainability** -- Version control and audit trails
5. **Scalability** -- Support thousands of terms across departments and domains
6. **Integration** -- API access for embedding in documentation, systems, and tools

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Platform | [SKOSMOS](https://skosmos.org/) (open-source, semantic web-native) |
| Storage | [Apache Jena Fuseki](https://jena.apache.org/documentation/fuseki2/) (RDF triple store) |
| Cache | [Varnish](https://varnish-cache.org/) (HTTP cache between SKOSMOS and Fuseki) |
| Data Format | [SKOS](https://www.w3.org/TR/skos-reference/) (W3C standard, RDF/Turtle) |
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
cp .env.example .env        # Edit as needed

# 2. Start services
docker compose up -d

# 3. Load vocabulary data
./scripts/load-data.sh

# 4. Browse the glossary
open http://localhost:9090   # SKOSMOS web UI
```

### Service Endpoints

| Service | URL | Purpose |
|---------|-----|---------|
| SKOSMOS | http://localhost:9090 | Web UI for browsing and searching |
| SKOSMOS REST API | http://localhost:9090/rest/v1/ | JSON-LD API for integrations |
| Fuseki SPARQL | http://localhost:3030/skosmos/sparql | SPARQL query endpoint |
| Fuseki Admin | http://localhost:3030 | Fuseki admin interface |
| Varnish Cache | http://localhost:9031 | SPARQL cache (internal) |

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

# Convert CSV to SKOS Turtle
python scripts/csv-to-skos.py data/template.csv -o data/new-terms.ttl

# Export SKOS to CSV
python scripts/skos-to-csv.py data/*.ttl -o export.csv
```

## Project Structure

```
enterprise-glossary-system/
├── CLAUDE.md                      # AI assistant instructions
├── README.md                      # This file
├── start-here.md                  # Session context (read first)
├── .env.example                   # Environment variable template
├── docker-compose.yml             # SKOSMOS + Fuseki + Varnish services
├── config/
│   ├── fuseki/skosmos.ttl         # Fuseki assembler (TDB2 + Lucene index)
│   ├── skosmos/config.ttl         # SKOSMOS vocabulary configuration
│   └── varnish/default.vcl        # Varnish cache rules
├── data/
│   ├── concept-scheme.ttl         # SKOS concept scheme + top categories
│   ├── enterprise-glossary.ttl    # 25 sample terms with relationships
│   └── template.csv               # CSV template for bulk import
├── scripts/
│   ├── load-data.sh               # Load Turtle files into Fuseki
│   ├── export-data.sh             # Export data as timestamped Turtle
│   ├── validate-skos.py           # Validate SKOS vocabulary files
│   ├── csv-to-skos.py             # Convert CSV to SKOS Turtle
│   ├── skos-to-csv.py             # Export SKOS to CSV
│   ├── test.sh                    # Run all integration tests
│   └── requirements.txt           # Python dependencies
├── tests/
│   ├── test-sparql-queries.sh     # SPARQL endpoint tests
│   ├── test-rest-api.sh           # SKOSMOS REST API tests
│   └── test-search.sh             # Search functionality tests
├── docs/
│   ├── design-architecture.md     # Technical design guide
│   └── prds/prd.md                # Product Requirements Document
└── _inbox/                        # Incoming items to triage
```

## REST API Examples

```bash
# List all vocabularies
curl http://localhost:9090/rest/v1/vocabularies?lang=en

# Search for a term
curl http://localhost:9090/rest/v1/enterprise-glossary/search?query=deployment&lang=en

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

## License

This project is licensed under the MIT License.
