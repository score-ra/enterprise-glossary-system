#!/usr/bin/env python3
"""Export SKOS vocabulary from Turtle files to CSV format.

Usage:
    python scripts/skos-to-csv.py data/*.ttl
    python scripts/skos-to-csv.py data/*.ttl -o export.csv
"""

import argparse
import csv
import sys

try:
    from rdflib import Graph, Namespace, RDF
except ImportError:
    print("ERROR: rdflib is required. Install with: pip install rdflib", file=sys.stderr)
    sys.exit(1)

SKOS = Namespace("http://www.w3.org/2004/02/skos/core#")


def get_slug(uri, base_uri):
    """Extract the slug from a full URI."""
    uri_str = str(uri)
    if uri_str.startswith(base_uri):
        return uri_str[len(base_uri):]
    return uri_str


def collect_values(g, subject, predicate):
    """Collect all string values for a predicate, pipe-separated."""
    values = [str(o) for o in g.objects(subject, predicate)]
    return "|".join(values)


def export_csv(files, base_uri, out):
    """Export SKOS concepts from Turtle files to CSV."""
    g = Graph()
    for f in files:
        g.parse(f, format="turtle")

    writer = csv.writer(out)
    writer.writerow([
        "uri_slug", "pref_label", "alt_labels", "hidden_labels",
        "definition", "broader_slug", "related_slugs", "scope_note", "example"
    ])

    concepts = sorted(g.subjects(RDF.type, SKOS.Concept), key=str)
    count = 0

    for concept in concepts:
        pref_labels = list(g.objects(concept, SKOS.prefLabel))
        if not pref_labels:
            continue

        slug = get_slug(concept, base_uri)
        pref_label = str(pref_labels[0])
        alt_labels = collect_values(g, concept, SKOS.altLabel)
        hidden_labels = collect_values(g, concept, SKOS.hiddenLabel)
        definition = str(next(g.objects(concept, SKOS.definition), ""))
        scope_note = str(next(g.objects(concept, SKOS.scopeNote), ""))
        example = str(next(g.objects(concept, SKOS.example), ""))

        broader_uris = list(g.objects(concept, SKOS.broader))
        broader_slug = get_slug(broader_uris[0], base_uri) if broader_uris else ""

        related_uris = list(g.objects(concept, SKOS.related))
        related_slugs = "|".join(get_slug(r, base_uri) for r in related_uris)

        writer.writerow([
            slug, pref_label, alt_labels, hidden_labels,
            definition, broader_slug, related_slugs, scope_note, example
        ])
        count += 1

    return count


def main():
    parser = argparse.ArgumentParser(description="Export SKOS vocabulary to CSV")
    parser.add_argument("files", nargs="+", help="Turtle (.ttl) files to export")
    parser.add_argument("-o", "--output", help="Output CSV file (default: stdout)")
    parser.add_argument(
        "--base-uri",
        default="http://glossary.example.org/terms/",
        help="Base URI to strip from concept URIs",
    )
    args = parser.parse_args()

    if args.output:
        with open(args.output, "w", encoding="utf-8", newline="") as out:
            count = export_csv(args.files, args.base_uri, out)
        print(f"Exported {count} concepts to {args.output}", file=sys.stderr)
    else:
        count = export_csv(args.files, args.base_uri, sys.stdout)
        print(f"Exported {count} concepts", file=sys.stderr)


if __name__ == "__main__":
    main()
