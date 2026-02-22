#!/usr/bin/env python3
"""Convert markdown glossary files into CSV format for SKOS import.

Auto-detects 4 source format variants and produces a CSV compatible
with csv-to-skos.py. Supports category mapping, deduplication,
collision detection, and dry-run mode.

Usage:
    python scripts/md-to-csv.py SOURCE_FILES... \\
        --category-map data/category-mapping.csv \\
        -o data/imported-terms.csv \\
        --collision-report data/collision-report.csv \\
        --dry-run
"""

import argparse
import csv
import os
import re
import sys
from collections import OrderedDict

# Headings that are NOT glossary terms
HEADING_BLOCKLIST = {
    "navigation", "table of contents", "purpose", "core terminology",
    "relationship hierarchy", "quick reference", "summary",
    "process relationships", "key distinctions", "decision guide",
    "relationship guide", "hierarchy overview",
}

# Values treated as empty
NA_VALUES = {"n/a", "na", "none", "n.a.", ""}


def slugify(name):
    """Convert a term title to a kebab-case URI slug.

    Strips parenthetical abbreviations, replaces / with -, lowercases,
    and removes non-alphanumeric characters except hyphens.
    """
    # Remove parenthetical abbreviations: "Term (ABBREV)" -> "Term"
    name = re.sub(r"\s*\([^)]*\)\s*$", "", name)
    slug = name.lower().strip()
    slug = slug.replace("/", "-").replace("&", "and")
    slug = re.sub(r"[^a-z0-9\s-]", "", slug)
    slug = re.sub(r"[\s]+", "-", slug)
    slug = re.sub(r"-+", "-", slug)
    slug = slug.strip("-")
    return slug


def extract_abbrev(title):
    """Split 'Term (ABBREV)' into (clean_name, abbreviation).

    Returns (title, None) if no parenthetical abbreviation found.
    """
    m = re.match(r"^(.+?)\s*\(([^)]+)\)\s*$", title)
    if m:
        return m.group(1).strip(), m.group(2).strip()
    return title.strip(), None


def build_term(title_raw, abbrev, clean_name, definition, categories,
               abbreviations, variations, synonyms, src):
    """Build a normalized term dict from parsed fields.

    Abbreviation logic: outside parens = prefLabel, inside = altLabel.
    e.g. "SEO (Search Engine Optimization)" -> prefLabel=SEO, alt=Search Engine Optimization
    """
    slug = slugify(title_raw)

    alts = []
    parens_expansion = None
    if abbrev:
        # Outside text is the preferred label, parens text is an alt
        pref_label = clean_name
        alts.append(abbrev)
        parens_expansion = abbrev
    else:
        pref_label = clean_name

    for field_val in [abbreviations, variations, synonyms]:
        cv = clean_value(field_val) if field_val else None
        if cv:
            for item in cv.split(","):
                item = item.strip()
                if item and item.lower() not in NA_VALUES and item != pref_label:
                    alts.append(item)

    return {
        "slug": slug,
        "pref_label": pref_label,
        "alt_labels": alts,
        "definition": definition,
        "categories_raw": categories,
        "source": src,
        "_parens_expansion": parens_expansion,
    }


def clean_value(val):
    """Strip and return None if value is an NA sentinel."""
    val = val.strip()
    if val.lower() in NA_VALUES:
        return None
    return val


def skip_frontmatter(lines):
    """Skip 1 or 2 YAML frontmatter blocks.

    Handles double frontmatter (seo-glossary, service-as-product, retail-property).
    Returns the index of the first content line after all frontmatter.
    """
    i = 0
    blocks_skipped = 0

    while i < len(lines) and blocks_skipped < 2:
        # Skip blank lines
        while i < len(lines) and not lines[i].strip():
            i += 1
        if i >= len(lines):
            break

        # Check for YAML block start
        if lines[i].strip() == "---":
            i += 1
            # Scan for closing ---
            while i < len(lines):
                if lines[i].strip() == "---":
                    i += 1
                    blocks_skipped += 1
                    break
                i += 1
        else:
            # Not a YAML block; check if next non-blank after a heading
            # might be a second embedded frontmatter block
            if blocks_skipped >= 1:
                # Look ahead: skip # heading line, then check for ---
                j = i
                while j < len(lines) and lines[j].strip().startswith("#"):
                    j += 1
                # Skip blank lines
                while j < len(lines) and not lines[j].strip():
                    j += 1
                if j < len(lines) and lines[j].strip() == "---":
                    # Looks like a second frontmatter block after a heading
                    i = j
                    continue
            break

    return i


def detect_format(lines):
    """Auto-detect the markdown format variant.

    Scans first 60 content lines (after frontmatter) for distinguishing patterns.
    """
    start = skip_frontmatter(lines)
    window = lines[start:start + 60]
    text = "\n".join(window)

    if "**Definition**:" in text or "**Definition**: " in text:
        return "PROCESS_MGMT"

    # Check for bare (unbolded) "Categories:" without **
    has_bare_categories = False
    has_bold_categories = False

    for line in window:
        stripped = line.strip()
        if stripped.startswith("Categories:") and not stripped.startswith("**Categories**:"):
            has_bare_categories = True
        if stripped.startswith("**Categories**:"):
            has_bold_categories = True

    if has_bare_categories and not has_bold_categories:
        return "UNBOLDED"

    # Check for SECTION_GROUPED: ## Section heading followed by ### Term
    has_h2_section = False
    has_h3_after_h2 = False
    for i, line in enumerate(window):
        stripped = line.strip()
        if stripped.startswith("## ") and not stripped.startswith("### "):
            h2_text = stripped[3:].strip()
            if h2_text.lower() not in HEADING_BLOCKLIST:
                has_h2_section = True
        if has_h2_section and stripped.startswith("### "):
            has_h3_after_h2 = True
            break

    if has_h3_after_h2 and has_bold_categories:
        return "SECTION_GROUPED"

    return "STANDARD"


def parse_standard(lines, src):
    """Parse STANDARD format: ## Term, bold **Field**:, --- separators."""
    terms = []
    start = skip_frontmatter(lines)
    i = start

    while i < len(lines):
        line = lines[i].strip()

        # Look for ## heading (not ###)
        if line.startswith("## ") and not line.startswith("### "):
            title_raw = line[3:].strip()

            # Skip blocklisted headings
            if title_raw.lower() in HEADING_BLOCKLIST:
                i += 1
                continue

            clean_name, abbrev = extract_abbrev(title_raw)
            i += 1

            # Skip blank lines after heading
            while i < len(lines) and not lines[i].strip():
                i += 1

            # Collect definition (paragraphs before first ** field or ---)
            definition_lines = []
            while i < len(lines):
                l = lines[i].strip()
                if l == "---" or l.startswith("**"):
                    break
                if l.startswith("## ") and not l.startswith("### "):
                    break
                if l:
                    definition_lines.append(l)
                i += 1

            definition = " ".join(definition_lines)

            # Parse fields
            categories = ""
            abbreviations = ""
            variations = ""
            synonyms = ""

            while i < len(lines):
                l = lines[i].strip()
                if l == "---" or (l.startswith("## ") and not l.startswith("### ")):
                    break
                if not l:
                    i += 1
                    continue

                if l.startswith("**Categories**:"):
                    categories = l.split(":", 1)[1].strip()
                elif l.startswith("**Abbreviations**:"):
                    abbreviations = l.split(":", 1)[1].strip()
                elif l.startswith("**Variations**:"):
                    variations = l.split(":", 1)[1].strip()
                elif l.startswith("**Synonyms**:"):
                    synonyms = l.split(":", 1)[1].strip()
                # Skip **Tags** and other fields
                i += 1

            # Skip separator
            if i < len(lines) and lines[i].strip() == "---":
                i += 1

            terms.append(build_term(
                title_raw, abbrev, clean_name, definition, categories,
                abbreviations, variations, synonyms, src
            ))
        else:
            i += 1

    return terms


def parse_unbolded(lines, src):
    """Parse UNBOLDED format: ##/### Term, bare Field:, no bold."""
    terms = []
    start = skip_frontmatter(lines)
    i = start

    while i < len(lines):
        line = lines[i].strip()

        # Match ## or ### heading
        heading_match = re.match(r"^(#{2,3})\s+(.+)$", line)
        if heading_match:
            level = heading_match.group(1)
            title_raw = heading_match.group(2).strip()

            if title_raw.lower() in HEADING_BLOCKLIST:
                i += 1
                continue

            # Skip # title heading (level 1)
            if len(level) == 1:
                i += 1
                continue

            clean_name, abbrev = extract_abbrev(title_raw)
            i += 1

            # Collect definition (lines before first bare field)
            definition_lines = []
            while i < len(lines):
                l = lines[i].strip()
                if not l:
                    i += 1
                    continue
                # Check for bare field (no bold)
                if re.match(r"^(Categories|Abbreviations|Variations|Synonyms|Tags):", l):
                    break
                # Check for next heading
                if re.match(r"^#{2,3}\s+", l):
                    break
                if l == "---":
                    break
                definition_lines.append(l)
                i += 1

            definition = " ".join(definition_lines)

            # Parse bare fields
            categories = ""
            abbreviations = ""
            variations = ""
            synonyms = ""

            while i < len(lines):
                l = lines[i].strip()
                if not l:
                    i += 1
                    continue
                if re.match(r"^#{2,3}\s+", l) or l == "---":
                    break

                if l.startswith("Categories:"):
                    categories = l.split(":", 1)[1].strip()
                elif l.startswith("Abbreviations:"):
                    abbreviations = l.split(":", 1)[1].strip()
                elif l.startswith("Variations:"):
                    variations = l.split(":", 1)[1].strip()
                elif l.startswith("Synonyms:"):
                    synonyms = l.split(":", 1)[1].strip()
                # Skip Tags and other fields
                i += 1

            terms.append(build_term(
                title_raw, abbrev, clean_name, definition, categories,
                abbreviations, variations, synonyms, src
            ))
        else:
            i += 1

    return terms


def parse_section_grouped(lines, src):
    """Parse SECTION_GROUPED format: ## Section > ### Term, bold fields."""
    terms = []
    start = skip_frontmatter(lines)
    i = start

    while i < len(lines):
        line = lines[i].strip()

        # ### Term entries
        if line.startswith("### "):
            title_raw = line[4:].strip()

            if title_raw.lower() in HEADING_BLOCKLIST:
                i += 1
                continue

            clean_name, abbrev = extract_abbrev(title_raw)
            i += 1

            # Skip blank lines after heading
            while i < len(lines) and not lines[i].strip():
                i += 1

            # Collect definition (paragraphs before first ** field or ---)
            definition_lines = []
            while i < len(lines):
                l = lines[i].strip()
                if l == "---" or l.startswith("**"):
                    break
                if l.startswith("## ") or l.startswith("### "):
                    break
                if l:
                    definition_lines.append(l)
                i += 1

            definition = " ".join(definition_lines)

            # Parse bold fields
            categories = ""
            abbreviations = ""
            variations = ""
            synonyms = ""

            while i < len(lines):
                l = lines[i].strip()
                if l == "---" or l.startswith("## ") or l.startswith("### "):
                    break
                if not l:
                    i += 1
                    continue

                if l.startswith("**Categories**:"):
                    categories = l.split(":", 1)[1].strip()
                elif l.startswith("**Abbreviations**:"):
                    abbreviations = l.split(":", 1)[1].strip()
                elif l.startswith("**Variations**:"):
                    variations = l.split(":", 1)[1].strip()
                elif l.startswith("**Synonyms**:"):
                    synonyms = l.split(":", 1)[1].strip()
                # Skip Full Name, Stage Objective, Symphony Core Stage, Tags, etc.
                i += 1

            # Skip separator
            if i < len(lines) and lines[i].strip() == "---":
                i += 1

            terms.append(build_term(
                title_raw, abbrev, clean_name, definition, categories,
                abbreviations, variations, synonyms, src
            ))
        else:
            i += 1

    return terms


def parse_process_mgmt(lines, src):
    """Parse PROCESS_MGMT format: ### Term, **Definition**:, no categories."""
    terms = []
    start = skip_frontmatter(lines)
    i = start

    while i < len(lines):
        line = lines[i].strip()

        if line.startswith("### "):
            title_raw = line[4:].strip()

            if title_raw.lower() in HEADING_BLOCKLIST:
                i += 1
                continue

            clean_name, abbrev = extract_abbrev(title_raw)
            i += 1

            definition = ""

            # Parse structured fields
            while i < len(lines):
                l = lines[i].strip()
                if l == "---" or (l.startswith("### ") and not l.startswith("####")):
                    break
                if not l:
                    i += 1
                    continue

                if l.startswith("**Definition**:"):
                    definition = l.split(":", 1)[1].strip()
                # Skip Characteristics, When to Use, Examples, File Naming
                i += 1

            # Skip separator
            if i < len(lines) and lines[i].strip() == "---":
                i += 1

            terms.append(build_term(
                title_raw, abbrev, clean_name, definition, "",
                "", "", "", src
            ))
        else:
            i += 1

    return terms


def deduplicate_terms(all_terms, cat_map):
    """Merge duplicate slugs into single entries, disambiguating homographs.

    Strategy:
    1. Group terms by slug.
    2. Within each group, sub-group by concept identity using the
       parenthetical expansion (e.g. "Structured Query Language" vs
       "Sales Qualified Lead" for slug "sql").
    3. If only one concept: merge all entries (longest definition wins,
       union alt_labels, best broader_slug).
    4. If multiple concepts: keep the majority slug, re-slug the
       minority using their parenthetical expansion.
    """
    from collections import defaultdict

    groups = defaultdict(list)
    for term in all_terms:
        groups[term["slug"]].append(term)

    result = []
    merge_log = []
    disambig_log = []

    for slug in sorted(groups.keys()):
        entries = groups[slug]
        if len(entries) == 1:
            result.append(entries[0])
            continue

        # Sub-group by concept identity.
        # Identity key: the parenthetical expansion (full-name form) if
        # it is a long expansion (has spaces, longer than prefLabel).
        # This distinguishes "SQL (Structured Query Language)" from
        # "SQL (Sales Qualified Lead)".
        identity_groups = defaultdict(list)
        for e in entries:
            exp = e.get("_parens_expansion", "")
            pref = e["pref_label"]
            # A "full-name expansion" is longer than the prefix and
            # contains spaces (not just an abbreviation like "CAC")
            if exp and " " in exp and len(exp) > len(pref):
                identity_groups[exp].append(e)
            else:
                identity_groups[""].append(e)

        if len(identity_groups) <= 1:
            # All same concept: merge
            merged = _merge_group(entries, cat_map)
            merge_log.append((slug, len(entries),
                              [e["source"] for e in entries]))
            result.append(merged)
        else:
            # Multiple distinct concepts sharing the same slug
            # The group with the most entries (or the one without a
            # full-name expansion) keeps the original slug.
            canonical_key = ""
            if "" in identity_groups:
                canonical_key = ""
            else:
                canonical_key = max(identity_groups.keys(),
                                    key=lambda k: len(identity_groups[k]))

            for key, group in identity_groups.items():
                merged = _merge_group(group, cat_map)
                if key == canonical_key:
                    result.append(merged)
                    merge_log.append((slug, len(group),
                                     [e["source"] for e in group]))
                else:
                    # Re-slug using the expansion
                    new_slug = slugify(key)
                    old_slug = merged["slug"]
                    merged["slug"] = new_slug
                    disambig_log.append((old_slug, new_slug,
                                         merged["pref_label"],
                                         [e["source"] for e in group]))
                    result.append(merged)

    # Report
    if merge_log:
        print("Dedup: merged {} slug groups ({} terms -> {} unique)".format(
            len(merge_log),
            sum(c for _, c, _ in merge_log),
            len(merge_log),
        ), file=sys.stderr)
    if disambig_log:
        print("Dedup: disambiguated {} homographs:".format(
            len(disambig_log)), file=sys.stderr)
        for old, new, label, sources in disambig_log:
            print("  {} -> {} ({}, from {})".format(
                old, new, label, ", ".join(sources)
            ), file=sys.stderr)

    return result


def _merge_group(entries, cat_map):
    """Merge a list of term dicts for the same concept into one.

    - Longest definition wins
    - Alt labels are unioned (preserving order, removing dupes)
    - Best broader_slug is chosen by priority
    - Scope notes list all source files
    """
    # Pick the entry with the longest definition as base
    best = max(entries, key=lambda e: len(e.get("definition", "")))

    # Union alt_labels (preserve order, dedupe case-insensitively)
    seen_alts = set()
    merged_alts = []
    for e in entries:
        for alt in e.get("alt_labels", []):
            key = alt.lower()
            if key not in seen_alts and key != best["pref_label"].lower():
                seen_alts.add(key)
                merged_alts.append(alt)

    # Pick broader_slug: prefer the most domain-specific match.
    # Use the broader from the entry with the longest definition.
    broader_candidates = []
    for e in entries:
        b, _ = map_broader(e["categories_raw"], cat_map, e["source"])
        if b:
            broader_candidates.append(b)
    broader = broader_candidates[0] if broader_candidates else ""

    # Combine sources
    sources = list(OrderedDict.fromkeys(e["source"] for e in entries))

    return {
        "slug": best["slug"],
        "pref_label": best["pref_label"],
        "alt_labels": merged_alts,
        "definition": best["definition"],
        "categories_raw": best["categories_raw"],
        "source": sources[0],  # primary source
        "_all_sources": sources,
        "_parens_expansion": best.get("_parens_expansion"),
    }


def load_category_map(path):
    """Load category-mapping.csv into a dict."""
    cat_map = {}
    with open(path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            cat_map[row["source_category"].strip()] = row["egms_slug"].strip()
    return cat_map


def map_broader(categories_raw, cat_map, src_filename):
    """Look up the broader_slug from the first mapped category.

    Returns (broader_slug, list_of_unmapped_categories).
    """
    if not categories_raw:
        # PROCESS_MGMT files default to operations
        if "process-management" in src_filename:
            return "operations", []
        return "", []

    cats = [c.strip() for c in categories_raw.split(",") if c.strip()]
    unmapped = []
    broader = ""

    for cat in cats:
        slug = cat_map.get(cat)
        if slug:
            if not broader:
                broader = slug
        else:
            unmapped.append(cat)

    return broader, unmapped


def map_to_row(term, cat_map):
    """Convert a parsed term dict to a CSV row dict."""
    broader, unmapped = map_broader(
        term["categories_raw"], cat_map, term["source"]
    )

    # Use combined source list if available
    sources = term.get("_all_sources", [term["source"]])
    scope_note = "Source: {}".format(", ".join(sources))

    return {
        "uri_slug": term["slug"],
        "pref_label": term["pref_label"],
        "alt_labels": "|".join(term["alt_labels"]),
        "hidden_labels": "",
        "definition": term["definition"],
        "broader_slug": broader,
        "related_slugs": "",
        "scope_note": scope_note,
        "example": "",
    }, unmapped


def detect_collisions(all_terms):
    """Group terms by slug and return collision groups (slug -> list of terms)."""
    slug_groups = {}
    for term in all_terms:
        slug = term["slug"]
        if slug not in slug_groups:
            slug_groups[slug] = []
        slug_groups[slug].append(term)

    return {slug: terms for slug, terms in slug_groups.items() if len(terms) > 1}


def write_collision_report(collisions, path):
    """Write collision-report.csv listing duplicate slugs."""
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["uri_slug", "pref_label", "source", "definition_preview"])
        for slug in sorted(collisions.keys()):
            for term in collisions[slug]:
                preview = term["definition"][:80] + "..." if len(term["definition"]) > 80 else term["definition"]
                writer.writerow([slug, term["pref_label"], term["source"], preview])
    print("Collision report: {} duplicate slugs written to {}".format(
        len(collisions), path
    ), file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description="Convert markdown glossary files to CSV for SKOS import"
    )
    parser.add_argument(
        "source_files", nargs="+", help="Markdown glossary file(s) to parse"
    )
    parser.add_argument(
        "--category-map", required=True,
        help="Path to category-mapping.csv"
    )
    parser.add_argument(
        "-o", "--output", default=None,
        help="Output CSV file (default: stdout)"
    )
    parser.add_argument(
        "--collision-report", default=None,
        help="Path to write collision report CSV (pre-dedup)"
    )
    parser.add_argument(
        "--no-dedup", action="store_true",
        help="Disable automatic deduplication"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Parse and report stats without writing output CSV"
    )
    args = parser.parse_args()

    cat_map = load_category_map(args.category_map)
    print("Loaded {} category mappings".format(len(cat_map)), file=sys.stderr)

    all_terms = []
    file_counts = {}

    PARSERS = {
        "STANDARD": parse_standard,
        "UNBOLDED": parse_unbolded,
        "SECTION_GROUPED": parse_section_grouped,
        "PROCESS_MGMT": parse_process_mgmt,
    }

    for filepath in args.source_files:
        with open(filepath, "r", encoding="utf-8") as f:
            lines = f.readlines()
        lines = [l.rstrip("\n").rstrip("\r") for l in lines]

        basename = os.path.basename(filepath)
        fmt = detect_format(lines)
        parse_fn = PARSERS[fmt]
        terms = parse_fn(lines, basename)

        file_counts[basename] = {"format": fmt, "count": len(terms)}
        all_terms.extend(terms)

        print("  {} -> {} format, {} terms".format(
            basename, fmt, len(terms)
        ), file=sys.stderr)

    print("Total terms parsed: {}".format(len(all_terms)), file=sys.stderr)

    # Pre-dedup collision detection (for reporting)
    collisions = detect_collisions(all_terms)
    if collisions:
        print("{} slug collisions detected".format(
            len(collisions)
        ), file=sys.stderr)

    if args.collision_report and collisions:
        write_collision_report(collisions, args.collision_report)

    # Deduplicate
    if not args.no_dedup:
        all_terms = deduplicate_terms(all_terms, cat_map)
        remaining = detect_collisions(all_terms)
        if remaining:
            print("WARNING: {} unresolved collisions after dedup".format(
                len(remaining)
            ), file=sys.stderr)
        else:
            print("All collisions resolved", file=sys.stderr)

    # Map to rows and collect unmapped categories
    rows = []
    all_unmapped = set()
    for term in all_terms:
        row, unmapped = map_to_row(term, cat_map)
        rows.append(row)
        all_unmapped.update(unmapped)

    if all_unmapped:
        print("WARNING: {} unmapped categories: {}".format(
            len(all_unmapped), ", ".join(sorted(all_unmapped))
        ), file=sys.stderr)

    if args.dry_run:
        print("\nDry-run summary:", file=sys.stderr)
        print("  Files: {}".format(len(file_counts)), file=sys.stderr)
        print("  Total terms (after dedup): {}".format(len(rows)), file=sys.stderr)
        print("  Unmapped categories: {}".format(len(all_unmapped)), file=sys.stderr)
        return

    # Write output
    fieldnames = [
        "uri_slug", "pref_label", "alt_labels", "hidden_labels",
        "definition", "broader_slug", "related_slugs", "scope_note", "example"
    ]

    if args.output:
        with open(args.output, "w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)
        print("Wrote {} terms to {}".format(len(rows), args.output), file=sys.stderr)
    else:
        writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
        print("Wrote {} terms to stdout".format(len(rows)), file=sys.stderr)


if __name__ == "__main__":
    main()
