#!/usr/bin/env python3
"""Add the engine's fluid -> box binding to the Turn and Flip census cases (round 54).

  tools/turn_flip_bind.py <turn_flip_cases_<ver>.json> <box_binding_<ver>.txt>

In game, generation probes every plan step's binding before the search starts (logic/bp/box_binding.lua fill) and
writes it to catalog.recipe[recipe].fluid_boxes[machine][fluid] = {box, boxes, role}. The census cases are prepared
inputs captured before that probe, so the offline census guessed "fluid k -> box k" and piped ammonia into a
fluorine box of the cryogenic plant (2.0.77 lab: fluid_ingredient_shortage, 0 fluoroketone). Run after every probe
that rewrites the cases file. Idempotent.
"""
import json, re, sys


def main(argv):
    cases_path, bind_path = argv
    binds = {}
    for line in open(bind_path):
        m = re.match(r"^BIND\s+(\S+)\s+recipe=(\S+)\s+fluid=(\S+)\s+role=(\S+)\s+box=(\d+)", line)
        if m:
            machine, recipe, fluid, role, box = m.groups()
            entry = binds.setdefault(recipe, {}).setdefault(machine, {}).setdefault(fluid, {"box": int(box), "boxes": [], "role": role})
            if int(box) not in entry["boxes"]:
                entry["boxes"].append(int(box))
    data = json.load(open(cases_path))
    added = 0
    for case in data["cases"].values():
        catalog = case.get("catalog") or {}
        machines = set((catalog.get("entity") or {}).keys())
        for name, recipe in (catalog.get("recipe") or {}).items():
            for machine, fluids in (binds.get(name) or {}).items():
                if machine in machines:
                    recipe.setdefault("fluid_boxes", {})[machine] = fluids
                    added += 1
    json.dump(data, open(cases_path, "w"), separators=(",", ":"), sort_keys=True)
    print(f"bound {added} recipe x machine pairs in {len(data['cases'])} cases")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
