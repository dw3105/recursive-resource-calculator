#!/usr/bin/env python3
"""Score blueprint entities against a MATERIAL fixture."""
from __future__ import annotations
import sys
from collections import Counter
from pathlib import Path
from blueprint_audit import load_entities


def read_fixture(path: Path) -> dict[str, float]:
    costs = {}
    for line in path.read_text().splitlines():
        fields = line.split("#", 1)[0].split()
        if len(fields) == 3 and fields[0] == "MATERIAL":
            try:
                value = float(fields[2])
            except ValueError:
                continue
            if value > 0:
                costs[fields[1]] = value
    return costs


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: material_score.py <bp.txt|r.json> <fixture>", file=sys.stderr)
        return 2
    entities, _, _ = load_entities(Path(sys.argv[1]))
    counts = Counter(entity.get("name") for entity in entities if entity.get("name"))
    costs = read_fixture(Path(sys.argv[2]))
    unknown = {name: count for name, count in counts.items() if name not in costs}
    total = sum(count * costs[name] for name, count in counts.items() if name in costs)
    print(f"material={total:.1f} unknown={sum(unknown.values())} unknown_names={','.join(sorted(unknown)) or '-'}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
