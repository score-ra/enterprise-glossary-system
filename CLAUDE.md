# Claude Code Instructions - enterprise-glossary-system

## Project Overview

Enterprise Glossary Management System (EGMS) — a centralized, URI-based glossary built on SKOSMOS and Apache Jena Fuseki, serving as the single source of truth for organizational terminology.

## Tech Stack

- **Platform:** SKOSMOS (semantic web vocabulary browser)
- **Storage:** Apache Jena Fuseki (RDF triple store / SPARQL endpoint)
- **Data Format:** SKOS (RDF/Turtle)
- **Cache:** Varnish (HTTP cache for SPARQL reads)
- **Infrastructure:** Docker Compose (local), cloud hosting (production)

## Quick Start

```bash
# Start services
cp .env.example .env
docker compose up -d

# Load vocabulary data
./scripts/load-data.sh

# Run tests
pip install -r scripts/requirements.txt
./scripts/test.sh

# Validate SKOS files offline
python scripts/validate-skos.py data/*.ttl
```

## Session Management

### Always Start Here
1. **Read** [start-here.md](start-here.md) for current context
2. **Verify** Docker services are running

### Always End Here
1. **Update** [start-here.md](start-here.md) with:
   - Completed tasks
   - Files modified
   - Next steps
   - Any blockers

## Development Standards

### Data Quality
- All terms must have URI identifiers
- SKOS vocabularies must validate against W3C SKOS spec
- Use `skos:prefLabel`, `skos:altLabel`, `skos:definition` consistently

### Git Conventions
- Branch naming: `feature/description` or `fix/description`
- Commits: Clear, atomic, focused on single change
- Always test vocabulary loads before pushing

## Pre-Commit Checklist

```bash
# 1. Validate RDF/Turtle syntax
python scripts/validate-skos.py data/*.ttl

# 2. Test SPARQL queries (requires running services)
./scripts/test.sh

# 3. Verify Docker services start cleanly
docker compose up -d && docker compose ps

# 4. Update start-here.md
```

## Key Files

| File | Purpose |
|------|---------|
| `start-here.md` | Session context - READ FIRST |
| `README.md` | Project overview and setup |
| `docs/prds/prd.md` | Product Requirements Document |
| `docs/design-architecture.md` | Technical design guide |
| `docker-compose.yml` | Service definitions (Fuseki + Varnish + SKOSMOS) |
| `config/fuseki/skosmos.ttl` | Fuseki assembler (TDB2 + Lucene) |
| `config/skosmos/config.ttl` | SKOSMOS vocabulary config |
| `config/varnish/default.vcl` | Varnish cache rules |
| `data/enterprise-glossary.ttl` | Sample vocabulary terms |
| `scripts/load-data.sh` | Load data into Fuseki |
| `scripts/validate-skos.py` | Validate SKOS files |
| `scripts/test.sh` | Run integration tests |

## Project Structure

```
enterprise-glossary-system/
├── CLAUDE.md                      # AI assistant instructions (this file)
├── README.md                      # Project overview and setup
├── start-here.md                  # Session context
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
