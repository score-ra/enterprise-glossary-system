# Start Here - enterprise-glossary-system

> **Read this file at the start of every session. Update it at the end.**

## Current Status

| Field | Value |
|-------|-------|
| **Phase** | Phase 1: Setup (Weeks 1-4) |
| **Last Updated** | 2026-02-20 |
| **Last Session** | Repository standardization and gap analysis |

## What's Done

- [x] Initial project setup (README, LICENSE, .gitignore)
- [x] PRD created (docs/prds/prd.md)
- [x] Design architecture doc started (docs/design-architecture.md)
- [x] Repository standardized against team template
- [ ] Infrastructure setup (Docker, Fuseki, SKOSMOS)
- [ ] Initial vocabulary/term collection
- [ ] Pilot team onboarding

## What's Next

- [ ] Create Docker Compose setup for SKOSMOS + Fuseki
- [ ] Configure SKOSMOS for the organization
- [ ] Create initial SKOS vocabulary structure
- [ ] Load sample terms into Fuseki
- [ ] Set up data loading scripts

## Active Blockers

None

## Files Modified Recently

```
README.md
CLAUDE.md
start-here.md
.env.example
docs/design-architecture.md
.github/pull_request_template.md
```

## Quick Commands

```bash
# Start SKOSMOS + Fuseki
docker-compose up -d

# Load vocabulary data
./scripts/load-data.sh

# Check Fuseki status
curl http://localhost:3030/$/ping

# Check SKOSMOS status
curl http://localhost:9090
```

## Notes

- Platform: SKOSMOS (open-source semantic web vocabulary browser)
- Storage: Apache Jena Fuseki (RDF triple store with SPARQL endpoint)
- Data format: SKOS (W3C standard, RDF/Turtle serialization)
- See PRD for full requirements: docs/prds/prd.md
- See design doc for architecture: docs/design-architecture.md
