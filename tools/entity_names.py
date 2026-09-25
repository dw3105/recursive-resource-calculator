#!/usr/bin/env python3
"""Check delivered entity prototype names against the player's prepared blueprint settings."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from blueprint_audit import load_entities


def expected_names(settings):
    belt = settings.get("belt") or {}
    return {
        "inserter": {settings.get("inserter", {}).get("name"), settings.get("long_inserter", {}).get("name")},
        "transport-belt": {belt.get("name")},
        "underground-belt": {belt.get("underground")},
        "splitter": {belt.get("splitter")},
        "pole": {settings.get("pole", {}).get("name")},
        "pipe": {settings.get("pipe", {}).get("name")},
        "pipe-to-ground": {settings.get("underground_pipe", {}).get("name")},
        "roboport": {settings.get("roboport", {}).get("name")},
    }


def family(name):
    if "inserter" in name:
        return "inserter"
    if "underground-belt" in name:
        return "underground-belt"
    if "transport-belt" in name:
        return "transport-belt"
    if name.endswith("splitter"):
        return "splitter"
    if name in {"small-electric-pole", "medium-electric-pole", "big-electric-pole", "substation"}:
        return "pole"
    if name in {"pipe", "pipe-to-ground"}:
        return name
    if name == "roboport":
        return "roboport"
    return None


def audit(blueprint_path: Path, prepared_path: Path):
    entities, _, _ = load_entities(blueprint_path)
    prepared = json.loads(prepared_path.read_text())
    expected = expected_names(prepared.get("settings") or {})
    wrong = []
    for entity in entities:
        name = entity.get("name") or ""
        kind = family(name)
        if kind and name not in expected.get(kind, set()):
            wrong.append(f"NAMES-WRONG entity={entity.get('entity_number', '?')} name={name} expected={','.join(sorted(n for n in expected[kind] if n))}")
    return wrong


def main(argv):
    if len(argv) != 3:
        raise SystemExit("usage: entity_names.py <bp.txt> <prepared_input.json>")
    wrong = audit(Path(argv[1]), Path(argv[2]))
    for line in wrong:
        print(line)
    print(f"NAMES-BAD n={len(wrong)}" if wrong else "NAMES-OK")
    return 1 if wrong else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
