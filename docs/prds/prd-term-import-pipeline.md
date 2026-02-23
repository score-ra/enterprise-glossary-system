---
title: "PRD: Repeatable Glossary Term Import Pipeline"
version: 1.0
type: product-prd
status: draft
author: score-ra
created: 2026-02-22
last_updated: 2026-02-22
reviewers: []
next_review: 2026-03-22
related_docs:
  parent:
    - docs/prds/prd.md
  children: []
  references:
    - docs/design-architecture.md
    - docs/taxonomy-reference.md
tags: [product, prd, import-pipeline, taxonomy, data-migration]
scope_tier: 2
problem_validated: true
routing:
  destination_repo: enterprise-glossary-system
  github_url: https://github.com/score-ra/enterprise-glossary-system
  confidence: high
  score: 10
  rationale: "Import pipeline extends the existing EGMS infrastructure"
  routed_date: 2026-02-22
---

# PRD: Repeatable Glossary Term Import Pipeline

## Document Control

| Field | Value |
|-------|-------|
| Version | 1.0 |
| Status | Draft |
| Author | score-ra |
| Last Updated | 2026-02-22 |

---

## Executive Summary

The EGMS is deployed with 25 sample terms and 4 top-level taxonomy categories. The organization has **530-560 production terms** across **12 markdown glossary pages** in `symphony-core-documents/08-reference/glossary/pages/`. These terms represent real vocabulary used in websites, client documentation, and SEO. Without a repeatable import pipeline, the EGMS cannot serve as the single source of truth it was built to be.

This PRD defines the full pipeline from source markdown to loaded SKOS vocabulary: markdown parsing across 4 format variants, field mapping to SKOS properties, taxonomy expansion from 4 to 26 concepts (including industry verticals), deduplication strategy, and an operational runbook. The pipeline is designed to be repeatable -- new verticals and source pages can be added following the same pattern.

**Scope Tier:** 2 -- Enhancement to Existing System

**Parent PRD:** [PRD: Enterprise Glossary Management System](prd.md) (FR-006, FR-011)

---

## Goals & Desired Outcomes

### Business Outcomes

| Outcome | Measurement | Target | Timeline |
|---------|-------------|--------|----------|
| Production vocabulary loaded into EGMS | Terms successfully imported and browsable | 530+ terms from 12 source pages | 2 weeks |
| Taxonomy supports multi-vertical strategy | Vertical concepts defined and extensible | 5+ verticals scaffolded | 2 weeks |
| Import process is repeatable for new verticals | New vertical imported without pipeline code changes | < 1 day per vertical | Ongoing |
| Zero data loss during migration | All source terms accounted for in import report | 100% term coverage | Import day |

### User Outcomes

| User Persona | Current Pain | Desired Future State |
|--------------|--------------|---------------------|
| Knowledge Manager | Must manually recreate 530+ terms from markdown files | Runs a scripted pipeline that parses, validates, and loads all terms |
| Documentation Author | EGMS has only 25 sample terms; production vocabulary is elsewhere | All 530+ production terms browsable and searchable in EGMS |
| AI/ML Engineer | Cannot point AI agents at EGMS -- too few terms | SPARQL endpoint returns the full production vocabulary |
| Engineering Lead | Adding a new vertical requires ad-hoc manual work | Follows a documented checklist to add any new vertical in < 1 day |

---

## Context

### Current State

The EGMS infrastructure (Fuseki, SKOSMOS, Varnish, Nginx) is deployed and functional with:
- 4 top-level concepts: Engineering, Business, Infrastructure, Process
- 25 sample terms in `data/enterprise-glossary.ttl`
- CSV-to-SKOS converter (`scripts/csv-to-skos.py`) handling 9 CSV columns
- Validation, snapshot, and audit tooling

### Gap

The production vocabulary exists in 12 markdown glossary pages with:
- **4 different format variants** requiring distinct parsers
- **240+ unique category values** that must map to EGMS taxonomy concepts
- **~30 cross-page duplicate terms** needing human-reviewed deduplication
- **Fields** (Tags, Abbreviations, Variations, Synonyms) without direct SKOS equivalents
- **No industry vertical structure** -- Real Estate, Legal, Accounting, Healthcare, and Home Services terms have no taxonomy home

### Source Pages

| Page | Format | Approx. Terms | Target Branch |
|------|--------|---------------|---------------|
| ai-glossary.md | Standard | ~52 | Engineering > AI & Machine Learning |
| business-plan-glossary.md | Standard | ~42 | Business > Strategy & Planning |
| data-management-glossary.md | Standard | ~68 | Engineering > Data Management |
| lean-startup-glossary.md | Unbolded | ~35 | Business > Strategy & Planning |
| marketing-terms-glossary.md | Section-grouped | ~99 | Business > Marketing & SEO |
| process-management-glossary.md | Process-management | ~19 | Process > Operations |
| product-management-glossary.md | Unbolded | ~52 | Business > Product Management |
| retail-property-glossary.md | Standard | ~87 | Real Estate > (3 sub-categories) |
| sc-approved-terminology.md | Standard | ~6 | Process > SC Internal |
| seo-glossary.md | Standard | ~52 | Business > Marketing & SEO |
| service-as-product-glossary.md | Standard | ~42 | Business > Service Design |
| software-dev-glossary.md | Standard | ~51 | Engineering > Software Development |

---

## Taxonomy Design

### Architecture: Core Concepts + Industry Verticals

The taxonomy has two types of top-level concepts:

- **Core concepts** (4 existing) -- universal terms applicable across all verticals
- **Vertical concepts** (new, extensible) -- industry-specific terminology for each client vertical

This maps directly to Symphony Core's vertical strategy: Home Services, Real Estate, Professional Services, and future expansions.

See [Taxonomy Reference](../taxonomy-reference.md) for the full hierarchy diagram, category definitions, and scaffolding guidelines.

### Term Distribution

| Branch | Type | Mid-Level Categories | Terms | Source Pages |
|--------|------|---------------------|-------|-------------|
| Engineering | Core | 3 + existing | ~196 | 3 pages + existing .ttl |
| Business | Core | 4 | ~322 | 5 pages |
| Infrastructure | Core | 1 | (scattered) | - |
| Process | Core | 2 | ~25 | 2 pages |
| Real Estate | Vertical | 3 | ~87 | 1 page |
| Legal | Vertical | 4 | scaffold only | - |
| Accounting | Vertical | 3 | scaffold only | - |
| Healthcare | Vertical | 3 | scaffold only | - |
| Home Services | Vertical | 3 | scaffold only | - |
| **Total** | | **26 concepts** | **~540 terms** | **12 pages** |

---

## Requirements

### Functional Requirements

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| FR-IP-001 | Parse 4 markdown format variants (Standard, Unbolded, Section-grouped, Process-management) into a common intermediate CSV | Must | Implemented |
| FR-IP-002 | Auto-detect format variant per page based on heading patterns and field formatting | Must | Implemented |
| FR-IP-003 | Extract all source fields: Title, Description, Categories, Tags, Abbreviations, Variations, Synonyms | Must | Implemented |
| FR-IP-004 | Map source fields to SKOS properties per the field mapping table | Must | Implemented |
| FR-IP-005 | Strip parenthetical abbreviations from titles and emit them as `skos:altLabel` | Must | Implemented |
| FR-IP-006 | Skip "N/A" values in Abbreviations, Variations, and Synonyms fields | Must | Implemented |
| FR-IP-007 | Map source Categories to EGMS taxonomy concepts via `data/category-mapping.csv` lookup | Must | Implemented |
| FR-IP-008 | Generate a collision report CSV listing all cross-page duplicate terms with their source pages and definitions | Must | Implemented |
| FR-IP-009 | Add `source_page` column to intermediate CSV and emit it as `skos:scopeNote` in generated Turtle | Must | Implemented |
| FR-IP-010 | Expand `data/concept-scheme.ttl` with mid-level concepts under each core branch and vertical top concepts with their mid-level categories | Must | Implemented |
| FR-IP-011 | Scaffold vertical concepts (Legal, Accounting, Healthcare, Home Services) with top concept and 3-4 mid-level categories each, containing no terms | Should | Implemented |
| FR-IP-012 | Validate all generated Turtle files with `scripts/validate-skos.py` before loading | Must | Implemented |
| FR-IP-013 | Load imported terms via existing `scripts/load-data.sh` pipeline | Must | Implemented |
| FR-IP-014 | Generate an import summary report: total terms parsed, loaded, duplicates found, categories mapped | Should | Implemented |
| FR-IP-015 | Document the end-to-end import process in an operator runbook with pre-flight checks, execution steps, and rollback procedure | Must | Implemented |

### Non-Functional Requirements

| ID | Category | Requirement | Target | Status |
|----|----------|-------------|--------|--------|
| NFR-IP-001 | Data Integrity | Zero term loss during import -- every source term accounted for in import report | 100% coverage | Implemented |
| NFR-IP-002 | Repeatability | Pipeline runs end-to-end without manual intervention (except dedup review) | Single command per stage | Implemented |
| NFR-IP-003 | Extensibility | Adding a new vertical requires no code changes to pipeline scripts | Config-only addition | Implemented |
| NFR-IP-004 | Idempotency | Re-running the pipeline on the same source produces identical output | Deterministic output | Implemented |
| NFR-IP-005 | Provenance | Every imported term traces back to its source markdown page | `skos:scopeNote` on all terms | Implemented |

### Requirements Traceability

| FR-IP ID | Enables Parent FR | Implementation Artifact |
|----------|-------------------|------------------------|
| FR-IP-001 to FR-IP-006 | FR-006, FR-011 | `scripts/md-to-csv.py` |
| FR-IP-007 | FR-006, FR-011 | `data/category-mapping.csv` |
| FR-IP-008 | FR-006 | `scripts/md-to-csv.py` (collision report output) |
| FR-IP-009 | FR-006 | `data/template.csv`, `scripts/csv-to-skos.py` |
| FR-IP-010, FR-IP-011 | FR-003 | `data/concept-scheme.ttl` |
| FR-IP-012 | NFR-005 (parent) | `scripts/validate-skos.py` (existing) |
| FR-IP-013 | FR-006, FR-011 | `scripts/load-data.sh` (existing) |
| FR-IP-014 | FR-006 | `scripts/md-to-csv.py` (summary output) |
| FR-IP-015 | - | `docs/import-runbook.md` |

---

## Field Mapping

### Source Markdown to SKOS Properties

| Source Field | SKOS Property | Notes |
|-------------|---------------|-------|
| Title (H2/H3) | `skos:prefLabel` | Strip parenthetical abbreviations (e.g., "Search Engine Optimization (SEO)" becomes prefLabel "Search Engine Optimization", altLabel "SEO") |
| Description | `skos:definition` | Direct mapping |
| Categories (first value) | `skos:broader` | Lookup via `data/category-mapping.csv` to resolve EGMS concept slug |
| Abbreviations | `skos:altLabel` | Skip "N/A" values; pipe-delimited in CSV |
| Variations | `skos:altLabel` | Skip "N/A" values; pipe-delimited in CSV |
| Synonyms | `skos:altLabel` | Skip "N/A" values; pipe-delimited in CSV |
| Tags | `skos:hiddenLabel` | Search-only discovery; skip values that duplicate existing labels |
| source_page (generated) | `skos:scopeNote` | Provenance: "Source: {filename}" |

### CSV Column Mapping

Existing `data/template.csv` columns and how import populates them:

| CSV Column | Populated From |
|------------|---------------|
| `uri_slug` | Kebab-case of Title (strip abbreviation parentheticals first) |
| `pref_label` | Title (cleaned) |
| `alt_labels` | Abbreviations + Variations + Synonyms (pipe-delimited, deduplicated) |
| `hidden_labels` | Tags (pipe-delimited, excluding label duplicates) |
| `definition` | Description |
| `broader_slug` | Category lookup via `data/category-mapping.csv` |
| `related_slugs` | Empty (populated manually post-import if needed) |
| `scope_note` | "Source: {source_page filename}" |
| `example` | Empty (not present in source markdown) |

---

## Format Variants

### Detection Logic

| Format | Pages | Detection Rule |
|--------|-------|----------------|
| Standard | ai, business-plan, data-mgmt, seo, service-as-product, software-dev, retail, sc-approved | `## Term` headings with `**Field**:` bold field names and `---` separators |
| Unbolded | lean-startup, product-management | `## Term` or `### Term` headings with plain `Field:` (no bold markers) |
| Section-grouped | marketing-terms | `## Section` headings containing `### Term` sub-headings |
| Process-management | process-management | `### Term` headings with `**Definition**:` field near heading |

The `md-to-csv.py` script will auto-detect the format by scanning the first 50 lines of each file for these patterns, then apply the appropriate parser.

---

## Deduplication Strategy

Approximately 30 terms appear on multiple source pages. The pipeline generates a `collision-report.csv` for human review.

### Resolution Rules

| Scenario | Action |
|----------|--------|
| Identical definitions | Merge: keep longest definition, union all labels, note all source pages |
| Different definitions (domain-specific) | Keep both with domain-qualified URI slugs (e.g., `roi-marketing`, `roi-finance`); add `skos:related` link between them |
| Subset definition | Keep longer definition; shorter becomes additional `skos:scopeNote` |

### Collision Report Columns

| Column | Description |
|--------|-------------|
| `term` | The term text (case-normalized) |
| `page_1` | First source page filename |
| `definition_1` | Definition from page 1 |
| `page_2` | Second source page filename |
| `definition_2` | Definition from page 2 |
| `similarity` | Rough text similarity score (0-1) |
| `recommended_action` | `merge`, `keep-both`, or `review` |

---

## Implementation Artifacts

### New Files

| File | Purpose | Implements |
|------|---------|------------|
| `scripts/md-to-csv.py` | Parse 4 markdown format variants into intermediate CSV | FR-IP-001 to FR-IP-006, FR-IP-008, FR-IP-009, FR-IP-014 |
| `data/category-mapping.csv` | Source category values mapped to EGMS concept slugs | FR-IP-007 |
| `docs/import-runbook.md` | Step-by-step operator checklist for running the pipeline | FR-IP-015 |
| `docs/taxonomy-reference.md` | Taxonomy hierarchy diagram and vertical scaffolding guide | FR-IP-010, FR-IP-011 |

### Modified Files

| File | Change | Implements |
|------|--------|------------|
| `data/concept-scheme.ttl` | Add mid-level concepts under core branches; add vertical top concepts and their mid-level categories | FR-IP-010, FR-IP-011 |
| `data/template.csv` | Add `source_page` column (backward-compatible -- existing rows get empty value) | FR-IP-009 |
| `scripts/csv-to-skos.py` | Emit `source_page` CSV column as `skos:scopeNote` (already supports `scope_note` column -- verify mapping) | FR-IP-009 |

---

## Phased Rollout

### Phase 1: Pipeline Build (Days 1-3)

| Step | Description | Output |
|------|-------------|--------|
| 1.1 | Write `scripts/md-to-csv.py` with 4 format parsers | Script + unit tests |
| 1.2 | Build `data/category-mapping.csv` from source category analysis | Mapping file |
| 1.3 | Run parser against all 12 pages, generate intermediate CSVs | 12 CSV files |
| 1.4 | Generate collision report | `collision-report.csv` |

### Phase 2: Taxonomy Expansion (Days 2-3)

| Step | Description | Output |
|------|-------------|--------|
| 2.1 | Add mid-level concepts to `data/concept-scheme.ttl` | Updated Turtle file |
| 2.2 | Add vertical top concepts (Real Estate + 4 scaffolds) | Updated Turtle file |
| 2.3 | Add vertical mid-level categories | Updated Turtle file |
| 2.4 | Validate expanded concept scheme | Validation pass |

### Phase 3: Import & Validate (Days 3-4)

| Step | Description | Output |
|------|-------------|--------|
| 3.1 | Human review of collision report; apply dedup decisions | Resolved CSV |
| 3.2 | Run `csv-to-skos.py` on resolved CSVs | Generated Turtle files |
| 3.3 | Validate all Turtle with `validate-skos.py` | Validation report |
| 3.4 | Load via `load-data.sh` | Terms in Fuseki |
| 3.5 | Take versioned snapshot | Snapshot artifact |

### Phase 4: Verify & Document (Day 5)

| Step | Description | Output |
|------|-------------|--------|
| 4.1 | Spot-check terms in SKOSMOS UI | Manual verification |
| 4.2 | Run SPARQL count queries to verify totals | Query results |
| 4.3 | Write import runbook | `docs/import-runbook.md` |
| 4.4 | Update taxonomy reference with final counts | `docs/taxonomy-reference.md` |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Markdown format variants have edge cases not covered by 4 parsers | Medium | Medium | Run parser on all 12 pages early; iterate on failures before bulk import |
| Category mapping misclassifies terms | Medium | Low | Generate mapping review CSV; spot-check 10% of terms post-import |
| Duplicate resolution requires extensive manual effort | Low | Medium | Auto-classify duplicates by similarity score; only flag ambiguous cases for review |
| Existing 25 sample terms conflict with imported terms | Low | Low | Check for slug collisions before import; existing terms take precedence |
| Import breaks SKOSMOS browse/search | Low | High | Take pre-import snapshot; validate Turtle before loading; test on staging first |

---

## New Vertical Checklist

When adding a new industry vertical to the glossary, follow this checklist:

```
## Adding a New Vertical: [Vertical Name]

1. [ ] Define 3-4 mid-level categories with clear scope boundaries
2. [ ] Add top concept + mid-level concepts to data/concept-scheme.ttl
3. [ ] Add category mapping rows to data/category-mapping.csv
4. [ ] Create or import glossary source pages (markdown format)
5. [ ] Run: md-to-csv.py -> csv-to-skos.py -> validate-skos.py -> load-data.sh
6. [ ] Take snapshot with version bump (scripts/snapshot.sh)
7. [ ] Update docs/taxonomy-reference.md with new branch and term counts
```

---

## Open Questions

- [ ] What is the production EGMS URL? (Needed for cross-reference links in source repo)
- [ ] Is EGMS public-facing (SEO indexable) or internal-only?
- [ ] For duplicates with genuinely different domain-specific definitions, should we keep separate terms or merge with combined definition?
- [ ] Should Symphony Core-specific terms (from `sc-approved-terminology.md`) be visually distinguished from general terms?
- [ ] Who is the ongoing Knowledge Manager responsible for post-import maintenance?
- [ ] Which verticals beyond the 4 proposed scaffolds should be prioritized?

---

## Success Criteria

The import pipeline is complete when:

1. All 530+ source terms are parsed without data loss (import report confirms 100% coverage)
2. All terms are browsable and searchable in SKOSMOS
3. Taxonomy hierarchy shows 26 concepts (4 core top + mid-levels, 5 vertical top + mid-levels)
4. Every imported term has `skos:scopeNote` tracing to its source page
5. Collision report has been reviewed and all duplicates resolved
6. Pipeline can import a new vertical page end-to-end with zero code changes
7. Import runbook is written and tested by a second operator

---

## Related Documents

| Document | Type | Relationship | Link |
|----------|------|--------------|------|
| PRD: Enterprise Glossary Management System | PRD | Parent | [prd.md](prd.md) |
| Taxonomy Reference | Reference | Child | [taxonomy-reference.md](../taxonomy-reference.md) |
| Design & Implementation Guide | Architecture | Sibling | [design-architecture.md](../design-architecture.md) |

---

## Glossary

| Term | Definition |
|------|------------|
| Concept Scheme | The top-level SKOS container for an organized set of concepts |
| Top Concept | A concept at the highest level of the hierarchy, linked via `skos:topConceptOf` |
| Mid-Level Concept | A concept that groups related terms under a top concept via `skos:broader` |
| Vertical | An industry-specific branch of the taxonomy (e.g., Real Estate, Legal) |
| Scaffold | A vertical with taxonomy structure defined but no terms loaded yet |
| Collision Report | CSV listing terms that appear on multiple source pages with different definitions |

---

*End of Document*
