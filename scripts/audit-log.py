#!/usr/bin/env python3
"""Generate an audit log by comparing two SKOS vocabulary snapshots.

Detects:
  - Added concepts (present in new, absent in old)
  - Removed concepts (present in old, absent in new)
  - Modified concepts (changed labels, definitions, relationships)

Usage:
    python scripts/audit-log.py snapshots/old.ttl snapshots/new.ttl
    python scripts/audit-log.py snapshots/old.ttl snapshots/new.ttl -o audit.json
    python scripts/audit-log.py --manifest snapshots/manifest.json  # compare last 2
"""

import argparse
import json
import sys
from datetime import datetime, timezone

try:
    from rdflib import Graph, Namespace, RDF
except ImportError:
    print("ERROR: rdflib is required. Install with: pip install rdflib", file=sys.stderr)
    sys.exit(1)

SKOS = Namespace("http://www.w3.org/2004/02/skos/core#")

TRACKED_PROPERTIES = [
    (SKOS.prefLabel, "prefLabel"),
    (SKOS.altLabel, "altLabel"),
    (SKOS.hiddenLabel, "hiddenLabel"),
    (SKOS.definition, "definition"),
    (SKOS.scopeNote, "scopeNote"),
    (SKOS.example, "example"),
    (SKOS.broader, "broader"),
    (SKOS.narrower, "narrower"),
    (SKOS.related, "related"),
]


def get_concept_data(g, concept):
    """Extract all tracked properties for a concept."""
    data = {}
    for prop, name in TRACKED_PROPERTIES:
        values = sorted(str(o) for o in g.objects(concept, prop))
        if values:
            data[name] = values
    return data


def compare_snapshots(old_file, new_file):
    """Compare two SKOS Turtle files and return a change log."""
    old_g = Graph()
    old_g.parse(old_file, format="turtle")

    new_g = Graph()
    new_g.parse(new_file, format="turtle")

    old_concepts = {c: get_concept_data(old_g, c)
                    for c in old_g.subjects(RDF.type, SKOS.Concept)}
    new_concepts = {c: get_concept_data(new_g, c)
                    for c in new_g.subjects(RDF.type, SKOS.Concept)}

    changes = []

    # Added concepts
    for uri in sorted(set(new_concepts) - set(old_concepts), key=str):
        label = new_concepts[uri].get("prefLabel", [str(uri)])[0]
        changes.append({
            "action": "added",
            "uri": str(uri),
            "label": label,
            "details": new_concepts[uri],
        })

    # Removed concepts
    for uri in sorted(set(old_concepts) - set(new_concepts), key=str):
        label = old_concepts[uri].get("prefLabel", [str(uri)])[0]
        changes.append({
            "action": "removed",
            "uri": str(uri),
            "label": label,
            "details": old_concepts[uri],
        })

    # Modified concepts
    for uri in sorted(set(old_concepts) & set(new_concepts), key=str):
        old_data = old_concepts[uri]
        new_data = new_concepts[uri]
        if old_data != new_data:
            label = new_data.get("prefLabel", old_data.get("prefLabel", [str(uri)]))[0]
            diffs = {}
            all_keys = set(old_data) | set(new_data)
            for key in sorted(all_keys):
                old_val = old_data.get(key, [])
                new_val = new_data.get(key, [])
                if old_val != new_val:
                    diffs[key] = {"old": old_val, "new": new_val}
            changes.append({
                "action": "modified",
                "uri": str(uri),
                "label": label,
                "changes": diffs,
            })

    return {
        "generated": datetime.now(timezone.utc).isoformat(),
        "old_file": str(old_file),
        "new_file": str(new_file),
        "summary": {
            "added": sum(1 for c in changes if c["action"] == "added"),
            "removed": sum(1 for c in changes if c["action"] == "removed"),
            "modified": sum(1 for c in changes if c["action"] == "modified"),
        },
        "changes": changes,
    }


def main():
    parser = argparse.ArgumentParser(description="Generate audit log from SKOS snapshot comparison")
    parser.add_argument("old_file", nargs="?", help="Old snapshot Turtle file")
    parser.add_argument("new_file", nargs="?", help="New snapshot Turtle file")
    parser.add_argument("-o", "--output", help="Output JSON file (default: stdout)")
    parser.add_argument("--manifest", help="Use manifest.json to compare last two snapshots")
    args = parser.parse_args()

    if args.manifest:
        with open(args.manifest) as f:
            manifest = json.load(f)
        snapshots = manifest.get("snapshots", [])
        if len(snapshots) < 2:
            print("ERROR: Need at least 2 snapshots in manifest to compare.", file=sys.stderr)
            sys.exit(1)
        import os
        base = os.path.dirname(args.manifest)
        old_file = os.path.join(base, snapshots[-2]["file"])
        new_file = os.path.join(base, snapshots[-1]["file"])
    elif args.old_file and args.new_file:
        old_file = args.old_file
        new_file = args.new_file
    else:
        parser.error("Provide two files or --manifest")

    audit = compare_snapshots(old_file, new_file)

    output = json.dumps(audit, indent=2, ensure_ascii=False)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output)
        print(f"Audit log written to {args.output}", file=sys.stderr)
    else:
        print(output)

    s = audit["summary"]
    print(
        f"Changes: {s['added']} added, {s['removed']} removed, {s['modified']} modified",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
