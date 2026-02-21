# Design & Implementation Guide
## Enterprise Glossary Management System

**Version:** 1.0
**Date:** February 2026
**Status:** Active

---

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [SKOSMOS: Selection & Rationale](#skosmos-selection--rationale)
3. [Technical Stack](#technical-stack)
4. [System Design](#system-design)
5. [Implementation Roadmap](#implementation-roadmap)
6. [Deployment Strategy](#deployment-strategy)
7. [Integration Patterns](#integration-patterns)
8. [UI/UX Improvements](#uiux-improvements)
9. [Governance & Maintenance](#governance--maintenance)

---

## Architecture Overview

### High-Level System Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Consumers                         │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────┐ │
│  │ Web UI   │  │ AI Agents    │  │ External Apps │ │
│  │ (Browse/ │  │ (RDF/SPARQL) │  │ (REST API)    │ │
│  │  Search) │  │              │  │               │ │
│  └────┬─────┘  └──────┬───────┘  └───────┬───────┘ │
└───────┼────────────────┼──────────────────┼─────────┘
        │                │                  │
┌───────▼────────────────▼──────────────────▼─────────┐
│                    SKOSMOS                            │
│           (Vocabulary Browser & API)                  │
│  ┌────────────────────────────────────────────────┐  │
│  │  REST API  │  SPARQL Proxy  │  Web Interface   │  │
│  └────────────────────────────────────────────────┘  │
└───────────────────────┬─────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────┐
│              Apache Jena Fuseki                       │
│            (RDF Triple Store / SPARQL)                │
│  ┌────────────────────────────────────────────────┐  │
│  │  SKOS Vocabularies  │  Term Relationships      │  │
│  │  URI Identifiers     │  Multi-language Labels   │  │
│  └────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## SKOSMOS: Selection & Rationale

SKOSMOS was selected as the platform because it is:

- **Semantic web-native** — Built on SKOS (Simple Knowledge Organization System), the W3C standard for controlled vocabularies
- **URI-based identification** — Every term gets a stable, dereferenceable URI
- **Open source** — No licensing costs, active community
- **RDF/SPARQL support** — Machine-readable format for AI agent consumption
- **Multi-language** — Built-in support for multilingual labels and definitions
- **Proven at scale** — Used by national libraries, government agencies, and large organizations

---

## Technical Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Vocabulary Browser | SKOSMOS | Web UI for browsing, searching, and managing terms |
| Triple Store | Apache Jena Fuseki | RDF storage with SPARQL endpoint |
| Data Format | SKOS (RDF/Turtle) | W3C standard for vocabularies |
| Infrastructure | Cloud (AWS/GCP/Azure) | Hosting and scaling |
| Import/Export | CSV, RDF/Turtle | Bulk data operations |

---

## System Design

### Core Features
- **Centralized glossary management interface** with web-based browsing and search
- **URI-based term identification** for semantic web compliance
- **Term relationships** — synonyms, broader/narrower terms, related concepts (SKOS relations)
- **Multi-language support** via SKOS multilingual labels
- **Role-based access control** for term governance
- **Version control and audit trails** for all term changes
- **API access** for integration with external systems
- **Import/export** in CSV and RDF/Turtle formats

### Non-Functional Requirements
- **Search Performance:** 95th percentile query response < 500ms
- **Scale:** Support thousands of terms across multiple departments
- **Availability:** Cloud-hosted for high availability

---

## Implementation Roadmap

| Phase | Duration | Key Deliverables |
|-------|----------|------------------|
| **Phase 1: Setup** | Weeks 1-4 | Infrastructure setup, initial term collection, pilot team onboarding |
| **Phase 2: MVP** | Weeks 5-12 | Web UI, search functionality, basic integrations |
| **Phase 3: Launch** | Weeks 13-16 | Company-wide rollout, training materials, API documentation |
| **Phase 4: Optimization** | Weeks 17+ | Performance tuning, advanced features, expanded integrations |

---

## Deployment Strategy

### Container Architecture

```
                :8080              :9090                :9031 (internal)         :3030
 Browser  -->  Nginx   -------->  SKOSMOS  -->  Varnish Cache  -->  Apache Jena Fuseki
 API          Gateway             (PHP/Apache)    (VCL rules)       (TDB2 + Lucene)
              (RBAC)
```

Four Docker containers orchestrated via Docker Compose:

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| gateway | nginx:1.27-alpine | 8080 | Reverse proxy with RBAC (public entry point) |
| fuseki | secoresearch/fuseki | 3030 | RDF triple store with SPARQL and Graph Store Protocol |
| fuseki-cache | varnish:7.6 | 9031 | HTTP cache for SPARQL read queries (5min TTL) |
| skosmos | quay.io/natlibfi/skosmos | 9090 | Web UI, REST API, SPARQL proxy |

### Key Configuration Files

- `config/fuseki/skosmos.ttl` -- Fuseki assembler (TDB2 persistent storage + Lucene text index on SKOS labels)
- `config/skosmos/config.ttl` -- SKOSMOS vocabulary declaration (JenaText dialect, multilingual en/es/fr, connects via Varnish)
- `config/varnish/default.vcl` -- Varnish rules (cache GET/sparql, pass through writes/updates)
- `config/nginx/nginx.conf` -- Gateway reverse proxy with RBAC rules (anonymous read, editor write, admin full)
- `config/nginx/auth/` -- htpasswd files for basic auth (generated by `scripts/setup-auth.sh`)

### Data Flow

1. Vocabulary data authored as RDF/Turtle files in `data/`
2. Loaded into Fuseki via Graph Store Protocol (`scripts/load-data.sh`)
3. Stored in named graph `<http://glossary.example.org/>`
4. SKOSMOS queries Fuseki through Varnish cache for reads
5. Lucene text index enables fast full-text search on SKOS labels

### Environment Setup

```bash
cp .env.example .env          # Configure passwords and ports
docker compose up -d          # Start all services
./scripts/load-data.sh        # Load vocabulary data
```

---

## Integration Patterns

### REST API (SKOSMOS)

Base URL: `http://localhost:9090/rest/v1/`

| Pattern | Endpoint | Use Case |
|---------|----------|----------|
| Search | `GET /rest/v1/{vocid}/search?query=term&lang=en` | Full-text term lookup |
| Lookup | `GET /rest/v1/{vocid}/lookup?label=term&lang=en` | Exact label match |
| Concept data | `GET /rest/v1/{vocid}/data?uri=...&lang=en` | Get concept details (JSON-LD) |
| Hierarchy | `GET /rest/v1/{vocid}/broader?uri=...&lang=en` | Navigate broader terms |
| Top concepts | `GET /rest/v1/{vocid}/topConcepts?lang=en` | Get category roots |

### SPARQL Endpoint (Fuseki)

URL: `http://localhost:3030/skosmos/sparql`

Supports standard SPARQL 1.1 queries plus Jena text search extensions:

```sparql
PREFIX text: <http://jena.apache.org/text#>
PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
SELECT ?concept ?label ?definition WHERE {
  ?concept text:query (skos:prefLabel "deploy*") .
  ?concept skos:prefLabel ?label .
  ?concept skos:definition ?definition .
}
```

### AI Agent Integration

AI agents consume the glossary via:
1. **REST API** -- JSON-LD responses for term lookup and search
2. **SPARQL** -- Complex semantic queries for relationship traversal
3. **RDF export** -- Full vocabulary dump for offline embedding

---

## UI/UX Improvements

### Multilingual Interface

SKOSMOS is configured with a language dropdown (en/es/fr) allowing users to browse terminology in their preferred language. The vocabulary data includes multilingual labels and definitions for key terms.

### Gateway Access

The Nginx gateway at port 8080 is the recommended public entry point, providing:
- Clean URL routing (SKOSMOS UI, SPARQL, and admin under one host)
- RBAC enforcement (anonymous read, authenticated write)
- `/health` endpoint for monitoring

---

## Security & RBAC

### Access Control Model

| Role | Capabilities | Authentication |
|------|-------------|----------------|
| Anonymous | Browse UI, search, SPARQL queries, REST API reads | None |
| Editor | All anonymous + SPARQL updates, data uploads | Basic auth (htpasswd) |
| Admin | All editor + file uploads, Fuseki admin panel | Basic auth (htpasswd-admin) |

### Authentication Setup

```bash
# Generate auth files (auto-generates passwords if not in .env)
./scripts/setup-auth.sh

# Or with explicit credentials
EGMS_ADMIN_PASS=secretpass EGMS_EDITOR_PASS=editpass ./scripts/setup-auth.sh
```

Auth files are stored in `config/nginx/auth/` and mounted into the Nginx container.

### Endpoint Protection

| Endpoint | Auth Required | Allowed Roles |
|----------|--------------|---------------|
| `/` (SKOSMOS UI) | No | All |
| `/sparql` (read queries) | No | All |
| `/fuseki/update` (SPARQL Update) | Yes | Editor, Admin |
| `/fuseki/data` (Graph Store) | Yes | Editor, Admin |
| `/fuseki/upload` (file upload) | Yes | Admin only |
| `/fuseki-admin/` (Fuseki UI) | Yes | Admin only |

---

## Backup & Disaster Recovery

### Automated Backups

`scripts/backup.sh` provides:
- Timestamped Turtle exports from Fuseki
- Configurable retention policy (default: 14 backups)
- Backup verification via rdflib parsing
- Logging to `backups/backup.log`

### Versioned Snapshots

`scripts/snapshot.sh` provides:
- Semantic versioning (auto-increment or explicit)
- Manifest tracking (`snapshots/manifest.json`) with checksums
- Message annotations for each snapshot

### Audit Trail

`scripts/audit-log.py` compares two snapshots and generates a JSON change log:
- Added/removed/modified concepts
- Property-level diffs (labels, definitions, relationships)
- Supports manifest-based comparison of last two snapshots

---

## Governance & Maintenance

### Term Lifecycle

1. **Proposal** -- New terms submitted as Turtle additions or CSV rows
2. **Validation** -- `validate-skos.py` enforces SKOS compliance
3. **Review** -- PR-based review using GitHub pull request workflow
4. **Loading** -- Approved terms loaded via `load-data.sh`
5. **Snapshot** -- `snapshot.sh` creates versioned audit record
6. **Audit** -- `audit-log.py` generates change reports for compliance

### CI/CD Pipeline

GitHub Actions workflow (`.github/workflows/validate.yml`):
- **On push** (data/ changes): Runs SKOS validation
- **On PR**: Full Docker Compose smoke test with data loading and integration tests

### Monitoring

`scripts/health-check.sh` provides:
- Service availability checks (Fuseki, Varnish, SKOSMOS, Gateway)
- SPARQL query latency measurement (target: P95 < 500ms)
- Search latency measurement
- JSON output mode for monitoring system integration
- Alert mode (exit 1 if unhealthy) for cron-based alerting
