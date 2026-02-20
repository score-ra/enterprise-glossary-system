# Claude Code Instructions - enterprise-glossary-system

## Project Overview

Enterprise Glossary Management System (EGMS) — a centralized, URI-based glossary built on SKOSMOS and Apache Jena Fuseki, serving as the single source of truth for organizational terminology.

## Tech Stack

- **Platform:** SKOSMOS (semantic web vocabulary browser)
- **Storage:** Apache Jena Fuseki (RDF triple store / SPARQL endpoint)
- **Data Format:** SKOS (RDF/Turtle)
- **Infrastructure:** Docker + cloud hosting

## Quick Start

```bash
# Start services
docker-compose up -d

# Load vocabulary data
./scripts/load-data.sh

# Run tests
./scripts/test.sh
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
# 2. Test SPARQL queries
# 3. Verify Docker services start cleanly
# 4. Update start-here.md
```

## Key Files

| File | Purpose |
|------|---------|
| `start-here.md` | Session context - READ FIRST |
| `README.md` | Project overview and setup |
| `docs/prds/prd.md` | Product Requirements Document |
| `docs/design-architecture.md` | Technical design guide |

## Project Structure

```
enterprise-glossary-system/
├── CLAUDE.md              # AI assistant instructions (this file)
├── README.md              # Project overview
├── start-here.md          # Session context
├── .env.example           # Environment variable template
├── docker-compose.yml     # SKOSMOS + Fuseki services
├── config/                # SKOSMOS & Fuseki configuration
├── data/                  # RDF/Turtle vocabulary files
├── scripts/               # Utility scripts
├── tests/                 # Validation and integration tests
├── docs/                  # Documentation
│   ├── design-architecture.md
│   └── prds/prd.md
└── _inbox/                # Incoming items to triage
```
