#!/usr/bin/env python3
"""Feed and sink tiles of a delivered sheet, for the headless sheet sim (round 48 I3).

  tools/sheet_ports.py <r.json> <prepared_input.json> [-o ports.json]

The generator's description names every external port and its rate ("in:item/iron-ore=0.19/s"). The port
inserters carry `port_id`; a published inserter's direction points at its PICKUP (reach 2 for long-handed).
Inputs: walk the belt upstream from each in-port inserter's pickup tile to a head nobody feeds (the feed tile).
Outputs: walk downstream from each out-port inserter's drop tile to the last belt (the sink tile). Only chains
whose far end touches the sheet's bounding box are external; a chain fed by another machine is internal.
Fluids: every pipe network touching the input edge is fed with the one fluid ingredient of the machines it reaches.
Tiles are floor(position) in blueprint coordinates. Output: {"feeds": [...], "sinks": [...], "targets": {...}}.
"""
import json, math, re, sys
from collections import defaultdict

VEC = {0: (0, -1), 4: (1, 0), 8: (0, 1), 12: (-1, 0)}
BELT = ("transport-belt",)
UG = ("underground-belt",)


def tile(e):
    return (math.floor(e["position"]["x"]), math.floor(e["position"]["y"]))


def kind(name):
    if name.endswith("underground-belt"): return "ug"
    if name.endswith("splitter"): return "splitter"
    if name.endswith("transport-belt"): return "belt"
    if name == "pipe" or name.endswith("-pipe"): return "pipe"
    if name.endswith("pipe-to-ground"): return "ptg"
    if "inserter" in name: return "hand"
    return "other"


def parse_description(text):
    ports = {}
    for m in re.finditer(r"^((?:in|out):(?:item|fluid)/[^=\s]+)=([0-9.eE+-]+)/s$", text, re.M):
        ports[m.group(1)] = float(m.group(2))
    edges = dict(re.findall(r"^(input_edge|output_edge)=(\w+)$", text, re.M))
    return ports, edges


def build(entities):
    cells = {}  # tile -> (entity, kind)
    for e in entities:
        k = kind(e["name"])
        if k == "splitter":
            x, y = e["position"]["x"], e["position"]["y"]
            d = e.get("direction", 0)
            dx, dy = (0.5, 0) if d in (0, 8) else (0, 0.5)
            for s in (-1, 1):
                cells[(math.floor(x + s * dx), math.floor(y + s * dy))] = (e, k)
        else:
            cells[tile(e)] = (e, k)
    # underground pairs: ug_pair_id when present, else nearest partner facing the same way
    by_number = {e["entity_number"]: e for e in entities}
    pair = {}
    for e in entities:
        if kind(e["name"]) == "ug" and e.get("ug_pair_id") in by_number:
            pair[tile(e)] = tile(by_number[e["ug_pair_id"]])
    return cells, pair


def successors(cells, pair, t):
    e, k = cells[t]
    d = e.get("direction", 0)
    if k == "ug" and e.get("type") == "input":
        return [pair[t]] if t in pair else []
    vx, vy = VEC[d]
    n = (t[0] + vx, t[1] + vy)
    if n in cells and cells[n][1] in ("belt", "ug", "splitter"):
        ne, nk = cells[n]
        nd = ne.get("direction", 0)
        if nk == "ug" and ne.get("type") == "output" and nd == d:
            return []  # entering an exit from its buried rear is not a connection
        if (VEC[nd][0] + vx, VEC[nd][1] + vy) == (0, 0):
            return []  # head-on
        return [n]
    return []


def main(argv):
    out_path = None
    if "-o" in argv:
        i = argv.index("-o"); out_path = argv[i + 1]; argv = argv[:i] + argv[i + 2:]
    r = json.load(open(argv[0]))
    prepared = json.load(open(argv[1]))
    entities = r["result"]["entities"]
    ports, edges = parse_description(r["result"].get("description", ""))
    cells, pair = build(entities)
    xs = [t[0] for t in cells] + [tile(e)[0] for e in entities]
    ys = [t[1] for t in cells] + [tile(e)[1] for e in entities]
    box = (min(xs), min(ys), max(xs), max(ys))
    on_edge = lambda t: t[0] in (box[0], box[2]) or t[1] in (box[1], box[3])
    preds = defaultdict(list)
    for t, (e, k) in cells.items():
        if k in ("belt", "ug", "splitter"):
            for n in successors(cells, pair, t):
                preds[n].append(t)

    def reach(e):
        return 2 if e["name"].startswith("long-handed") else 1

    feeds, sinks, problems = {}, {}, []
    for e in entities:
        pid = e.get("port_id")
        if kind(e["name"]) != "hand" or not pid or pid not in ports:
            continue
        item = pid.split("/", 1)[1]
        vx, vy = VEC[e.get("direction", 0)]
        t = tile(e)
        if pid.startswith("in:"):
            start = (t[0] + vx * reach(e), t[1] + vy * reach(e))
            todo, seen, heads = [start], set(), []
            while todo:
                c = todo.pop()
                if c in seen or c not in cells:
                    continue
                seen.add(c)
                if preds[c]:
                    todo += preds[c]
                else:
                    heads.append(c)
            for h in heads:
                if on_edge(h) and cells[h][1] == "belt":
                    feeds[h] = item
                else:
                    problems.append(f"{pid}: head {h} not a plain belt on the edge")
        else:
            start = (t[0] - vx * reach(e), t[1] - vy * reach(e))
            c, seen = start, set()
            while c in cells and c not in seen:
                seen.add(c)
                nxt = successors(cells, pair, c) if cells[c][1] in ("belt", "ug", "splitter") else []
                if not nxt:
                    break
                c = nxt[0]
            if c in cells and on_edge(c):
                sinks.setdefault(c, set()).add(item)
            else:
                problems.append(f"{pid}: chain end {c} not on the edge")
    # fluid inputs
    catalog = prepared.get("catalog") or {}
    recipes = catalog.get("recipe") or {}
    fluid_in = [p.split("/", 1)[1] for p in ports if p.startswith("in:fluid/")]
    fluid_feeds = {}
    if fluid_in:
        pipes = {t for t, (e, k) in cells.items() if k in ("pipe", "ptg")}
        ptg_pair = {}
        ptgs = [e for e in entities if kind(e["name"]) == "ptg"]
        for a in ptgs:
            ta = tile(a)
            best = None
            for b in ptgs:
                tb = tile(b)
                if a is b or (a.get("direction", 0) + 8) % 16 != b.get("direction", 0):
                    continue
                if ta[0] == tb[0] or ta[1] == tb[1]:
                    dist = abs(ta[0] - tb[0]) + abs(ta[1] - tb[1])
                    if best is None or dist < best[0]:
                        best = (dist, tb)
            if best:
                ptg_pair[ta] = best[1]
        comp = {}
        for p in pipes:
            if p in comp:
                continue
            stack, members = [p], []
            comp[p] = p
            while stack:
                c = stack.pop(); members.append(c)
                nbrs = [(c[0] + dx, c[1] + dy) for dx, dy in VEC.values()]
                if c in ptg_pair:
                    nbrs.append(ptg_pair[c])
                for n in nbrs:
                    if n in pipes and n not in comp:
                        comp[n] = p; stack.append(n)
        machines = [e for e in entities if e.get("recipe")]
        for root in set(comp.values()):
            members = [c for c, rt in comp.items() if rt == root]
            edge_tiles = [c for c in members if on_edge(c)]
            if not edge_tiles:
                continue
            fluids = set()
            for m in machines:
                spec = (catalog.get("entity") or {}).get(m["name"]) or {}
                w, h = spec.get("tile_w", 3), spec.get("tile_h", 3)
                mx, my = m["position"]["x"] - w / 2, m["position"]["y"] - h / 2
                touch = any(mx - 1 <= c[0] < mx + w + 1 and my - 1 <= c[1] < my + h + 1 for c in members)
                if touch:
                    for ing in (recipes.get(m["recipe"]) or {}).get("ingredients", []):
                        if ing.get("type") == "fluid" and ing["name"] in fluid_in:
                            fluids.add(ing["name"])
            if len(fluids) == 1:
                for c in edge_tiles:
                    fluid_feeds[c] = fluids.pop() if False else next(iter(fluids))
            elif fluids:
                problems.append(f"pipe network at {edge_tiles[0]} reaches several input fluids {sorted(fluids)}")
    result = {
        "bbox": list(box), "edges": edges,
        "feeds": [{"tile": list(t), "item": i} for t, i in sorted(feeds.items())]
                 + [{"tile": list(t), "fluid": f} for t, f in sorted(fluid_feeds.items())],
        "sinks": [{"tile": list(t), "items": sorted(v)} for t, v in sorted(sinks.items())],
        "targets": {p.split(":", 1)[1]: rate for p, rate in ports.items() if p.startswith("out:")},
        "inputs": {p.split(":", 1)[1]: rate for p, rate in ports.items() if p.startswith("in:")},
        "problems": problems,
        "force": {k: (catalog.get("inserter") or {}).get(k) for k in ("bulk_inserter_capacity_bonus", "inserter_stack_size_bonus")
                  if (catalog.get("inserter") or {}).get(k) is not None},
    }
    fed = {f.get("item") or "fluid/" + f["fluid"] for f in result["feeds"]}
    for p in result["inputs"]:
        name = p.split("/", 1)[1] if p.startswith("item/") else p
        if name not in fed:
            result["problems"].append(f"input {p} has no feed tile")
    text = json.dumps(result, indent=1, sort_keys=True) + "\n"
    if out_path:
        open(out_path, "w").write(text)
    else:
        sys.stdout.write(text)
    return 1 if result["problems"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
