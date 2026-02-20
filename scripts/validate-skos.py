#!/usr/bin/env python3
"""Validate SKOS vocabulary files for syntax and required properties.

Checks:
  1. Valid RDF/Turtle syntax (parses without errors)
  2. Every skos:Concept has skos:prefLabel
  3. Every skos:Concept has skos:definition
  4. Every skos:Concept has skos:inScheme
  5. No orphan concepts (must have broader or be topConceptOf)
  6. At least one skos:ConceptScheme exists
  7. Reciprocal broader/narrower relationships (warning only)

Usage:
    python scripts/validate-skos.py data/*.ttl
    python scripts/validate-skos.py data/enterprise-glossary.ttl data/concept-scheme.ttl
"""

import argparse
import sys

try:
    from rdflib import Graph, Namespace, RDF, URIRef
except ImportError:
    print("ERROR: rdflib is required. Install with: pip install rdflib", file=sys.stderr)
    sys.exit(1)

SKOS = Namespace("http://www.w3.org/2004/02/skos/core#")


def validate(files):
    """Validate one or more Turtle files. Returns (errors, warnings)."""
    g = Graph()
    errors = []
    warnings = []

    # Parse all files into a single graph
    for f in files:
        try:
            g.parse(f, format="turtle")
        except Exception as e:
            errors.append(f"Syntax error in {f}: {e}")
            return errors, warnings

    # Check for at least one ConceptScheme
    schemes = list(g.subjects(RDF.type, SKOS.ConceptScheme))
    if not schemes:
        errors.append("No skos:ConceptScheme found in the data.")

    # Validate each Concept
    concepts = list(g.subjects(RDF.type, SKOS.Concept))
    if not concepts:
        warnings.append("No skos:Concept instances found.")
        return errors, warnings

    top_concepts = set()
    for scheme in schemes:
        for tc in g.objects(scheme, SKOS.hasTopConcept):
            top_concepts.add(tc)
    for concept in g.subjects(SKOS.topConceptOf, None):
        top_concepts.add(concept)

    for concept in concepts:
        label = str(concept)

        # Check prefLabel
        pref_labels = list(g.objects(concept, SKOS.prefLabel))
        if not pref_labels:
            errors.append(f"Missing skos:prefLabel on <{label}>")
        else:
            label = str(pref_labels[0])

        # Check definition
        definitions = list(g.objects(concept, SKOS.definition))
        if not definitions:
            warnings.append(f"Missing skos:definition on '{label}'")

        # Check inScheme
        in_scheme = list(g.objects(concept, SKOS.inScheme))
        if not in_scheme:
            warnings.append(f"Missing skos:inScheme on '{label}'")

        # Check for orphans (no broader and not a top concept)
        broader = list(g.objects(concept, SKOS.broader))
        if not broader and concept not in top_concepts:
            warnings.append(f"Orphan concept '{label}' (no broader, not a top concept)")

    # Check reciprocal broader/narrower
    for s, _, o in g.triples((None, SKOS.broader, None)):
        if (o, SKOS.narrower, s) not in g:
            s_label = str(next(g.objects(s, SKOS.prefLabel), s))
            o_label = str(next(g.objects(o, SKOS.prefLabel), o))
            warnings.append(
                f"Non-reciprocal: '{s_label}' has broader '{o_label}' "
                f"but '{o_label}' does not declare narrower '{s_label}'"
            )

    return errors, warnings


def main():
    parser = argparse.ArgumentParser(description="Validate SKOS vocabulary files")
    parser.add_argument("files", nargs="+", help="Turtle (.ttl) files to validate")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Treat warnings as errors",
    )
    args = parser.parse_args()

    print(f"Validating {len(args.files)} file(s)...")
    errors, warnings = validate(args.files)

    for w in warnings:
        print(f"  WARNING: {w}")
    for e in errors:
        print(f"  ERROR: {e}")

    print()
    print(f"Results: {len(errors)} error(s), {len(warnings)} warning(s)")

    if errors or (args.strict and warnings):
        print("VALIDATION FAILED")
        sys.exit(1)
    else:
        print("VALIDATION PASSED")
        sys.exit(0)


if __name__ == "__main__":
    main()
