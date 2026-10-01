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


partner = {}  # splitter half -> other half: one entity, so upstream of either half is upstream of both


def build(entities):
    cells = {}  # tile -> (entity, kind)
    partner.clear()
    for e in entities:
        k = kind(e["name"])
        if k == "splitter":
            x, y = e["position"]["x"], e["position"]["y"]
            d = e.get("direction", 0)
            dx, dy = (0.5, 0) if d in (0, 8) else (0, 0.5)
            halves = [(math.floor(x + s * dx), math.floor(y + s * dy)) for s in (-1, 1)]
            for h in halves:
                cells[h] = (e, k)
            partner[halves[0]], partner[halves[1]] = halves[1], halves[0]
        else:
            cells[tile(e)] = (e, k)
    # underground pairs: ug_pair_id when present, else nearest partner facing the same way
    by_number = {e["entity_number"]: e for e in entities}
    pair = {}
    for e in entities:
        if kind(e["name"]) == "ug" and e.get("ug_pair_id") in by_number:
            other = tile(by_number[e["ug_pair_id"]])
            pair[tile(e)] = other
            pair.setdefault(other, tile(e))  # often only one end names its partner
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


def connection_tiles(m, fbox):
    """Tiles a machine fluid box joins a pipe on, for the machine as placed (Turn, then Flip = mirror x of north)."""
    d = m.get("direction", 0)
    out = []
    for conn in fbox.get("connections") or []:
        pos = (conn.get("positions") or [None] * 4)[d // 4]
        cdir = (conn.get("direction", 0) + d) % 16
        if m.get("mirror"):
            north = (conn.get("positions") or [None])[0]
            if not north:
                continue
            x, y, nd = -north["x"], north["y"], (16 - conn.get("direction", 0)) % 16
            for _ in range(d // 4):
                x, y = -y, x
            pos, cdir = {"x": x, "y": y}, (nd + d) % 16
        if not pos:
            continue
        cx, cy = m["position"]["x"] + pos["x"], m["position"]["y"] + pos["y"]
        vx, vy = VEC[cdir]
        out.append((math.floor(cx + vx), math.floor(cy + vy)))
    return out


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
        if pid:
            if pid.startswith("row:"):
                pid = pid[4:]  # row blocks: "row:in:item/x" -> "in:item/x"
            pid = ":".join(pid.split(":")[:2])  # "in:item/x:hand:1" -> "in:item/x"
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
                ups = list(preds[c])
                if c in partner:
                    ups += preds[partner[c]]
                    todo.append(partner[c])
                if ups:
                    todo += ups
                elif c not in partner or not preds[partner[c]]:
                    if c not in partner:
                        heads.append(c)
            #An underground entrance on the edge is fed like a belt (round 54: asm-1 Turn 12 starts its trunk below).
            edge = [h for h in heads if on_edge(h) and cells[h][1] in ("belt", "ug")]
            for h in edge:
                if feeds.get(h, item) != item:  # one edge belt reached from hands of two items: a bleed (round 54)
                    problems.append(f"edge belt {h} feeds several items {sorted({feeds[h], item})}")
                feeds[h] = item
            if not edge:  # interior heads are machine outputs merging in: internal sources, not ports
                problems.append(f"{pid}: no plain edge belt upstream (heads {sorted(heads)})")
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
    # fluid inputs: pipes join on 4 sides; a pipe-to-ground only on the side it faces plus its underground partner.
    # Each input fluid box of a machine takes the recipe's fluid ingredients in order; the tile its connection
    # points at names the fluid of that pipe network. The sheet sim proves the assignment (a wrong one starves).
    catalog = prepared.get("catalog") or {}
    recipes = catalog.get("recipe") or {}
    fluid_in = [p.split("/", 1)[1] for p in ports if p.startswith("in:fluid/")]
    fluid_out = [p.split("/", 1)[1] for p in ports if p.startswith("out:fluid/")]
    fluid_feeds = {}
    if fluid_in or fluid_out:
        pipes = {t: e for t, (e, k) in cells.items() if k in ("pipe", "ptg")}
        ptgs = [e for e in entities if kind(e["name"]) == "ptg"]
        ptg_pair = {}
        for a in ptgs:
            ta, best = tile(a), None
            for b in ptgs:
                tb = tile(b)
                if a is b or (a.get("direction", 0) + 8) % 16 != b.get("direction", 0):
                    continue
                vx, vy = VEC[b.get("direction", 0)]
                along = ta[1] == tb[1] if vx != 0 else ta[0] == tb[0]  # partners sit on the facing axis only
                if along and tb != ta and ((tb[0] - ta[0]) * vx > 0 or (tb[1] - ta[1]) * vy > 0):
                    dist = abs(ta[0] - tb[0]) + abs(ta[1] - tb[1])
                    if best is None or dist < best[0]:
                        best = (dist, tb)
            if best:
                ptg_pair[ta] = best[1]

        def links(c):
            e = pipes[c]
            if kind(e["name"]) == "ptg":
                vx, vy = VEC[e.get("direction", 0)]
                out = [(c[0] + vx, c[1] + vy)]
                if c in ptg_pair: out.append(ptg_pair[c])
            else:
                out = [(c[0] + vx, c[1] + vy) for vx, vy in VEC.values()]
            keep = []
            for n in out:
                if n not in pipes:
                    continue
                ne = pipes[n]
                if kind(ne["name"]) == "ptg" and n != ptg_pair.get(c):
                    vx, vy = VEC[ne.get("direction", 0)]
                    if (n[0] + vx, n[1] + vy) != c:
                        continue
                keep.append(n)
            return keep

        comp = {}
        for p0 in pipes:
            if p0 in comp:
                continue
            stack = [p0]; comp[p0] = p0
            while stack:
                c = stack.pop()
                for n in links(c):
                    if n not in comp:
                        comp[n] = p0; stack.append(n)
        fluid_of = defaultdict(set)
        for m in entities:
            r = recipes.get(m.get("recipe") or "")
            if not r:
                continue
            wants = [i["name"] for i in r.get("ingredients", []) if i.get("type") == "fluid"]
            if not any(w in fluid_in for w in wants):
                continue
            spec = (catalog.get("entity") or {}).get(m["name"]) or {}
            boxes = sorted((b for b in spec.get("fluid_boxes") or [] if b.get("production_type") == "input"), key=lambda b: b.get("index", 0))
            d = m.get("direction", 0)
            bound = (r.get("fluid_boxes") or {}).get(m["name"]) or {}
            if any(w in bound for w in wants):
                # the engine's own fluid -> box binding (catalog, round 52): spare boxes merge or stay empty
                all_boxes = spec.get("fluid_boxes") or []
                for w in wants:
                    if w not in fluid_in:
                        continue
                    for index in (bound.get(w) or {}).get("boxes") or []:
                        for pos, fbox in enumerate(all_boxes):
                            if fbox.get("index", pos + 1) == index:
                                for n in connection_tiles(m, fbox):
                                    if n in comp:
                                        fluid_of[comp[n]].add(w)
                continue
            for i, fbox in enumerate(boxes):
                if i >= len(wants) or wants[i] not in fluid_in:
                    continue
                for n in connection_tiles(m, fbox):
                    if n in comp:
                        fluid_of[comp[n]].add(wants[i])
        for root, fluids in fluid_of.items():
            edge_tiles = [c for c, rt in comp.items() if rt == root and on_edge(c)]
            if len(fluids) > 1:
                problems.append(f"pipe network {root} gets several input fluids {sorted(fluids)}")
            elif fluids:
                for c in edge_tiles:
                    fluid_feeds[c] = next(iter(fluids))
        # fluid products (round 54): a pipe network on a machine's output box that no input feeds and that reaches
        # the edge is a sink; the lab drains it there and counts what arrives by fluid name.
        out_roots = defaultdict(set)
        for m in entities:
            r = recipes.get(m.get("recipe") or "")
            if not r:
                continue
            makes = [i["name"] for i in r.get("products", []) if i.get("type") == "fluid" and i["name"] in fluid_out]
            if not makes:
                continue
            spec = (catalog.get("entity") or {}).get(m["name"]) or {}
            bound = (r.get("fluid_boxes") or {}).get(m["name"]) or {}
            for pos, fbox in enumerate(spec.get("fluid_boxes") or []):
                if fbox.get("production_type") != "output":
                    continue
                index = fbox.get("index", pos + 1)
                here = [f for f in makes if index in ((bound.get(f) or {}).get("boxes") or [])] if any(f in bound for f in makes) else makes
                for n in connection_tiles(m, fbox):
                    if here and n in comp and comp[n] not in fluid_of:
                        out_roots[comp[n]].update(here)
        for root, makes in out_roots.items():
            edge_tiles = sorted(c for c, rt in comp.items() if rt == root and on_edge(c))
            if edge_tiles:
                sinks.setdefault(edge_tiles[0], set()).update(makes)
    result = {
        "bbox": list(box), "edges": edges,
        "feeds": [{"tile": list(t), "item": i} for t, i in sorted(feeds.items())]
                 + [{"tile": list(t), "fluid": f} for t, f in sorted(fluid_feeds.items())],
        "sinks": [{"tile": list(t), "items": sorted(v)} for t, v in sorted(sinks.items())],
        "targets": {p.split(":", 1)[1]: rate for p, rate in ports.items() if p.startswith("out:")},
        "inputs": {p.split(":", 1)[1]: rate for p, rate in ports.items() if p.startswith("in:")},
        "problems": problems,
        "force": dict({k: (catalog.get("inserter") or {}).get(k) for k in ("bulk_inserter_capacity_bonus", "inserter_stack_size_bonus")
                  if (catalog.get("inserter") or {}).get(k) is not None},
                  research=((prepared.get("environment") or {}).get("force") or {}).get("research") or {}),
    }
    drained = {i for v in sinks.values() for i in v}
    for f in fluid_out:
        if f not in drained:
            result["problems"].append(f"output fluid/{f} has no sink tile")
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
