#!/usr/bin/env python3
"""Convert markdown glossary files into CSV format for SKOS import.

Auto-detects 4 source format variants and produces a CSV compatible
with csv-to-skos.py. Supports category mapping, collision detection,
and dry-run mode.

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


def clean_value(val):
    """Strip and return None if value is an NA sentinel."""
    val = val.strip()
    if val.lower() in NA_VALUES:
        return None
    return val


def clean_multi(val):
    """Parse a comma-separated field, filter NA values, return pipe-delimited."""
    if not val or val.strip().lower() in NA_VALUES:
        return ""
    parts = []
    for item in val.split(","):
        item = item.strip()
        if item and item.lower() not in NA_VALUES:
            parts.append(item)
    return "|".join(parts)


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
    has_section_grouped = False

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
            slug = slugify(title_raw)
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

            # Build alt_labels from abbreviations, variations, synonyms
            alts = []
            if abbrev:
                # Title had (ABBREV); prefLabel = ABBREV, altLabel = clean_name
                pref_label = abbrev
                alts.append(clean_name)
            else:
                pref_label = clean_name

            for field_val in [abbreviations, variations, synonyms]:
                cv = clean_value(field_val) if field_val else None
                if cv:
                    for item in cv.split(","):
                        item = item.strip()
                        if item and item.lower() not in NA_VALUES and item != pref_label:
                            alts.append(item)

            terms.append({
                "slug": slug,
                "pref_label": pref_label,
                "alt_labels": alts,
                "definition": definition,
                "categories_raw": categories,
                "source": src,
            })
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
            slug = slugify(title_raw)
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

            # Build alt_labels
            alts = []
            if abbrev:
                pref_label = abbrev
                alts.append(clean_name)
            else:
                pref_label = clean_name

            for field_val in [abbreviations, variations, synonyms]:
                cv = clean_value(field_val) if field_val else None
                if cv:
                    for item in cv.split(","):
                        item = item.strip()
                        if item and item.lower() not in NA_VALUES and item != pref_label:
                            alts.append(item)

            terms.append({
                "slug": slug,
                "pref_label": pref_label,
                "alt_labels": alts,
                "definition": definition,
                "categories_raw": categories,
                "source": src,
            })
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
            slug = slugify(title_raw)
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

            # Build alt_labels
            alts = []
            if abbrev:
                pref_label = abbrev
                alts.append(clean_name)
            else:
                pref_label = clean_name

            for field_val in [abbreviations, variations, synonyms]:
                cv = clean_value(field_val) if field_val else None
                if cv:
                    for item in cv.split(","):
                        item = item.strip()
                        if item and item.lower() not in NA_VALUES and item != pref_label:
                            alts.append(item)

            terms.append({
                "slug": slug,
                "pref_label": pref_label,
                "alt_labels": alts,
                "definition": definition,
                "categories_raw": categories,
                "source": src,
            })
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
            slug = slugify(title_raw)
            i += 1

            definition = ""
            alts = []

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

            if abbrev:
                pref_label = abbrev
                alts.append(clean_name)
            else:
                pref_label = clean_name

            terms.append({
                "slug": slug,
                "pref_label": pref_label,
                "alt_labels": alts,
                "definition": definition,
                "categories_raw": "",  # PROCESS_MGMT has no categories
                "source": src,
            })
        else:
            i += 1

    return terms


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

    return {
        "uri_slug": term["slug"],
        "pref_label": term["pref_label"],
        "alt_labels": "|".join(term["alt_labels"]),
        "hidden_labels": "",
        "definition": term["definition"],
        "broader_slug": broader,
        "related_slugs": "",
        "scope_note": "Source: {}".format(term["source"]),
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
        help="Path to write collision report CSV"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Parse and report stats without writing output CSV"
    )
    args = parser.parse_args()

    cat_map = load_category_map(args.category_map)
    print("Loaded {} category mappings".format(len(cat_map)), file=sys.stderr)

    all_terms = []
    all_unmapped = set()
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

    # Detect collisions
    collisions = detect_collisions(all_terms)
    if collisions:
        print("WARNING: {} slug collisions detected".format(
            len(collisions)
        ), file=sys.stderr)
        for slug, terms in sorted(collisions.items()):
            sources = [t["source"] for t in terms]
            print("  {} ({}x): {}".format(
                slug, len(terms), ", ".join(sources)
            ), file=sys.stderr)

    if args.collision_report and collisions:
        write_collision_report(collisions, args.collision_report)

    # Map to rows and collect unmapped categories
    rows = []
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
        print("  Total terms: {}".format(len(rows)), file=sys.stderr)
        print("  Collisions: {}".format(len(collisions)), file=sys.stderr)
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
