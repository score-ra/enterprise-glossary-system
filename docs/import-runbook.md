# Import Pipeline Runbook

Operator checklist for importing markdown glossary files into EGMS.

---

## 1. Pre-Flight Checks

- [ ] Docker services are running: `docker compose ps`
- [ ] Fuseki is healthy: `curl -s http://localhost:3030/$/ping`
- [ ] Python dependencies installed: `pip install -r scripts/requirements.txt`
- [ ] Take a pre-import snapshot:
  ```bash
  ./scripts/snapshot.sh pre-import-$(date +%Y%m%d)
  ```

---

## 2. Parse Source Markdown

Run the parser on all source glossary files:

```bash
python scripts/md-to-csv.py \
    /path/to/glossary/pages/*.md \
    --category-map data/category-mapping.csv \
    -o data/imported-terms.csv \
    --collision-report data/collision-report.csv
```

**Dry-run first** (no output written):

```bash
python scripts/md-to-csv.py \
    /path/to/glossary/pages/*.md \
    --category-map data/category-mapping.csv \
    --dry-run
```

Check stderr output for:
- Term counts per file (compare against expected)
- Unmapped categories (should be 0)
- Collision count

---

## 3. Review Collision Report

Open `data/collision-report.csv` and resolve duplicates:

1. Identify terms that appear in multiple source files
2. Decide which definition to keep (prefer the more detailed one)
3. Remove duplicate rows from `data/imported-terms.csv`
4. Merge alt_labels from duplicates if they differ

Common collisions: `agile`, `api`, `scalability`, `net-promoter-score`

---

## 4. Convert to SKOS

```bash
python scripts/csv-to-skos.py data/imported-terms.csv \
    -o data/imported-glossary.ttl
```

---

## 5. Validate Turtle

```bash
python scripts/validate-skos.py \
    data/concept-scheme.ttl \
    data/imported-glossary.ttl \
    data/enterprise-glossary.ttl
```

- **0 errors** required before loading
- Warnings about non-reciprocal broader/narrower are expected

---

## 6. Load into Fuseki

```bash
./scripts/load-data.sh
```

This loads all `.ttl` files from `data/` into Fuseki.

---

## 7. Verify

Run SPARQL count query to confirm term count:

```bash
curl -s http://localhost:3030/skosmos/sparql \
    --data-urlencode "query=SELECT (COUNT(?s) AS ?count) WHERE { ?s a <http://www.w3.org/2004/02/skos/core#Concept> }" \
    -H "Accept: application/json"
```

Spot-check a few terms:
- Pick 1 term from each source file
- Verify prefLabel, definition, and broader relationship in SKOSMOS UI

---

## 8. Post-Import Snapshot

```bash
./scripts/snapshot.sh v1.1-import
```

---

## 9. Rollback Procedure

If the import needs to be reverted:

1. Stop services: `docker compose stop fuseki`
2. Restore the pre-import TDB2 data directory from snapshot
3. Remove `data/imported-glossary.ttl`
4. Restart services: `docker compose up -d`
5. Verify term count matches pre-import snapshot

---

## Expected Term Counts

| File | Format | ~Terms |
|------|--------|--------|
| retail-property-glossary.md | STANDARD | 127 |
| marketing-terms-glossary.md | SECTION_GROUPED | 107 |
| data-management-glossary.md | STANDARD | 68 |
| ai-glossary.md | STANDARD | 52 |
| product-management-glossary.md | UNBOLDED | 52 |
| software-dev-glossary.md | STANDARD | 51 |
| seo-glossary.md | STANDARD | 45 |
| lean-startup-glossary.md | UNBOLDED | 43 |
| service-as-product-glossary.md | STANDARD | 42 |
| business-plan-glossary.md | STANDARD | 34 |
| process-management-glossary.md | PROCESS_MGMT | 19 |
| sc-approved-terminology.md | STANDARD | 7 |
| **Total** | | **~647** |
