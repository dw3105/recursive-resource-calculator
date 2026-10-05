#!/usr/bin/env python3
"""Decode a delivered sheet blueprint into the geometry-only entity fixture."""
import json
import sys
from pathlib import Path

from blueprint_audit import load_entities


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: tools/sheet_entities.py <case>")
    case = sys.argv[1]
    root = Path(__file__).resolve().parents[1]
    source = root / "tests/fixtures/sheets" / f"{case}.bp.txt"
    entities, _, _ = load_entities(source)
    result = [{key: entity[key] for key in ("name", "position", "direction", "type", "recipe") if key in entity}
              for entity in entities]
    xs = [e["position"]["x"] for e in result]
    ys = [e["position"]["y"] for e in result]
    ports = json.loads(source.with_name(f"{case}.ports.json").read_text())
    bbox = ports["bbox"]
    out = root / "tests/fixtures/sheets" / f"{case}.entities.json"
    out.write_text(json.dumps({"entities": result, "bbox": bbox}, indent=2) + "\n")


if __name__ == "__main__":
    main()
