#!/usr/bin/env python3
"""Convert a CSV file of glossary terms into SKOS RDF/Turtle format.

Usage:
    python scripts/csv-to-skos.py data/template.csv > output.ttl
    python scripts/csv-to-skos.py data/template.csv -o data/output.ttl
    python scripts/csv-to-skos.py data/template.csv --base-uri http://glossary.example.org/terms/
"""

import argparse
import csv
import sys
from datetime import date


def escape_turtle(text):
    """Escape special characters for Turtle string literals."""
    return text.replace("\\", "\\\\").replace('"', '\\"')


def write_turtle(rows, base_uri, scheme_uri, out):
    """Write SKOS Turtle output from parsed CSV rows."""
    out.write("@prefix skos: <http://www.w3.org/2004/02/skos/core#> .\n")
    out.write("@prefix dct:  <http://purl.org/dc/terms/> .\n")
    out.write("@prefix xsd:  <http://www.w3.org/2001/XMLSchema#> .\n")
    out.write(f"@prefix eg:   <{base_uri}> .\n")
    out.write("\n")
    out.write(f"# Generated from CSV on {date.today().isoformat()}\n\n")

    for row in rows:
        slug = row["uri_slug"].strip()
        if not slug:
            continue

        uri = f"eg:{slug}"
        out.write(f"{uri} a skos:Concept ;\n")

        # prefLabel (required)
        pref = escape_turtle(row["pref_label"].strip())
        out.write(f'    skos:prefLabel "{pref}"@en ;\n')

        # altLabels
        if row.get("alt_labels", "").strip():
            for alt in row["alt_labels"].split("|"):
                alt = escape_turtle(alt.strip())
                if alt:
                    out.write(f'    skos:altLabel "{alt}"@en ;\n')

        # hiddenLabels
        if row.get("hidden_labels", "").strip():
            for hidden in row["hidden_labels"].split("|"):
                hidden = escape_turtle(hidden.strip())
                if hidden:
                    out.write(f'    skos:hiddenLabel "{hidden}"@en ;\n')

        # definition
        if row.get("definition", "").strip():
            defn = escape_turtle(row["definition"].strip())
            out.write(f'    skos:definition "{defn}"@en ;\n')

        # scopeNote
        if row.get("scope_note", "").strip():
            note = escape_turtle(row["scope_note"].strip())
            out.write(f'    skos:scopeNote "{note}"@en ;\n')

        # example
        if row.get("example", "").strip():
            ex = escape_turtle(row["example"].strip())
            out.write(f'    skos:example "{ex}"@en ;\n')

        # broader
        if row.get("broader_slug", "").strip():
            broader = row["broader_slug"].strip()
            out.write(f"    skos:broader eg:{broader} ;\n")

        # related
        if row.get("related_slugs", "").strip():
            for rel in row["related_slugs"].split("|"):
                rel = rel.strip()
                if rel:
                    out.write(f"    skos:related eg:{rel} ;\n")

        # inScheme
        out.write(f"    skos:inScheme <{scheme_uri}> .\n\n")


def main():
    parser = argparse.ArgumentParser(
        description="Convert CSV glossary terms to SKOS RDF/Turtle"
    )
    parser.add_argument("csv_file", help="Input CSV file path")
    parser.add_argument(
        "-o", "--output", help="Output file (default: stdout)", default=None
    )
    parser.add_argument(
        "--base-uri",
        help="Base URI for terms",
        default="http://glossary.example.org/terms/",
    )
    parser.add_argument(
        "--scheme-uri",
        help="Concept scheme URI",
        default="http://glossary.example.org/terms/enterprise-glossary",
    )
    args = parser.parse_args()

    with open(args.csv_file, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    if not rows:
        print("No rows found in CSV file.", file=sys.stderr)
        sys.exit(1)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as out:
            write_turtle(rows, args.base_uri, args.scheme_uri, out)
        print(f"Wrote {len(rows)} terms to {args.output}", file=sys.stderr)
    else:
        write_turtle(rows, args.base_uri, args.scheme_uri, sys.stdout)
        print(f"Wrote {len(rows)} terms to stdout", file=sys.stderr)


if __name__ == "__main__":
    main()
