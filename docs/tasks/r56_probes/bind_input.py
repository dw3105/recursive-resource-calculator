#!/usr/bin/env python3
"""LOCAL PROBE ticket 11: add engine fluid->box binding (box_binding_<ver>.txt) to one prepared_input.json,
same rule as tools/turn_flip_bind.py. usage: bind_input.py <in.json> <box_binding.txt> <out.json>"""
import json, re, sys
src, bind_path, out = sys.argv[1:]
binds = {}
for line in open(bind_path):
    m = re.match(r"^BIND\s+(\S+)\s+recipe=(\S+)\s+fluid=(\S+)\s+role=(\S+)\s+box=(\d+)", line)
    if m:
        machine, recipe, fluid, role, box = m.groups()
        e = binds.setdefault(recipe, {}).setdefault(machine, {}).setdefault(fluid, {"box": int(box), "boxes": [], "role": role})
        if int(box) not in e["boxes"]: e["boxes"].append(int(box))
d = json.load(open(src)); cat = d["catalog"]; machines = set((cat.get("entity") or {}).keys()); added = []
for name, recipe in (cat.get("recipe") or {}).items():
    for machine, fluids in (binds.get(name) or {}).items():
        if machine in machines:
            recipe.setdefault("fluid_boxes", {})[machine] = fluids; added.append(name + "@" + machine)
json.dump(d, open(out, "w"), separators=(",", ":"))
print("bound", len(added))
