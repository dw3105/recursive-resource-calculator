#!/usr/bin/env python3
"""Write calculation references for a delivered Sheet sim case."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHEETS = ROOT / "tests/fixtures/sheets"
VANILLA = {
    "vanilla-2.1-red-science-1s": {
        "outputs": {"item/automation-science-pack": 1.0},
        "inputs": {"item/copper-plate": 1.0, "item/iron-plate": 2.0},
    },
    "vanilla-2.1-green-science-1s": {
        "outputs": {"item/logistic-science-pack": 1.0},
        "inputs": {"item/copper-plate": 1.5, "item/iron-plate": 5.5},
    },
}


def refs(case):
    if case in VANILLA:
        return VANILLA[case]
    prepared_path = ROOT / "tests/golden/cases" / case / "prepared_input.json"
    prepared = json.loads(prepared_path.read_text())
    outputs = {target["full_name"]: target["rate_per_second"]
               for target in prepared["snapshot"]["targets"]}
    inputs = prepared["solver_result"]["unsolved_rates"]
    return {"outputs": outputs, "inputs": inputs}


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: tools/sheet_refs.py <case>")
    case = sys.argv[1]
    payload = refs(case)
    (SHEETS / (case + ".refs.json")).write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
