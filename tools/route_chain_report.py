#!/usr/bin/env python3
"""Say WHERE each routed belt run stops being a directed chain.

Fed the candidate that `tools/route_chain_probe.sh` dumps -- the object
`logic/bp/search.lua:1477` hands `Validate.begin`, so exactly what the validator judges.

The rule reproduced here is the validator's own, `logic/bp/validate.lua:478-512`
`transport_neighbors`: a belt's only successor is the tile it faces, plus, for a splitter, one side tile;
and a step is legal only when the next tile's flow is absent or equal.  A belt pointing the wrong way breaks
the walk exactly like a missing belt, which is why `BP_V_ROUTE_DISCONTINUOUS` and `BP_V_TRANSPORT_UNUSED` are
one fault counted twice.

This tool reports.  It never judges: it exits 0 whatever it finds, because producing a diagnosis is not a
pass.  `tools/census_gate.py` judges.
"""
import json
import sys
from collections import Counter

NORTH, EAST, SOUTH, WEST = 0, 4, 8, 12
VECTOR = {NORTH: (0, -1), EAST: (1, 0), SOUTH: (0, 1), WEST: (-1, 0)}
NAME = {NORTH: "N", EAST: "E", SOUTH: "S", WEST: "W"}


def tile(value):
    """A belt entity sits at the tile CENTRE, `logic/bp/route.lua:911-913` adds 0.5 to each axis."""
    if value is None:
        return None
    import math
    return int(math.floor(float(value) + 1e-9))


def direction_of(entity):
    for key in ("direction", "dir"):
        value = entity.get(key)
        if isinstance(value, (int, float)):
            return int(value) % 16
    return None


def flow_of(entity):
    return entity.get("flow_id") or entity.get("full_name")


def transport_kind(entity):
    name = str(entity.get("name") or "")
    if entity.get("splitter") or entity.get("type") == "splitter" or "splitter" in name:
        return "belt"
    if "underground-belt" in name or "transport-belt" in name or entity.get("ug_role"):
        return "belt"
    if "pipe" in name:
        return "pipe"
    return None


def entity_tile(entity):
    position = entity.get("position") or {}
    return (tile(entity.get("x") if entity.get("x") is not None else position.get("x")),
            tile(entity.get("y") if entity.get("y") is not None else position.get("y")))


def belts_by_tile(entities):
    by_tile, by_id = {}, {}
    for entity in entities:
        if transport_kind(entity) != "belt":
            continue
        if entity.get("id") is not None:
            by_id[str(entity["id"])] = entity
        x, y = entity_tile(entity)
        if x is None or y is None:
            continue
        by_tile.setdefault((x, y), []).append(entity)
    return by_tile, by_id


def successors(entity, by_tile, by_id, wanted_flow):
    """Every legal continuation, the validator's rule verbatim (logic/bp/validate.lua:478-512).

    Three sources, and the underground pair is the one a naive walk forgets: an underground entry's
    continuation is its PARTNER, not the tile it faces.  Measured 2026-09-22, the player's sheet routes 52
    underground endpoints, so a walk without this reports breaks that are not there.
    """
    out = []
    pair_id = entity.get("ug_pair_id") or entity.get("underground_pair_id")
    if pair_id is not None:
        pair = by_id.get(str(pair_id))
        if pair is not None and pair is not entity:
            flow = flow_of(pair)
            if wanted_flow is None or flow is None or flow == wanted_flow:
                out.append(pair)
    direction = direction_of(entity)
    x, y = entity_tile(entity)
    steps = []
    if direction in VECTOR:
        dx, dy = VECTOR[direction]
        steps.append((x + dx, y + dy))
    if entity.get("splitter") or entity.get("type") == "splitter":
        side = (direction + EAST) % 16 if direction is not None else EAST
        if side in VECTOR:
            sx, sy = VECTOR[side]
            steps.append((x + sx, y + sy))
    for step in steps:
        for nxt in by_tile.get(step, []):
            if nxt is entity:
                continue
            flow = flow_of(nxt)
            if wanted_flow is None or flow is None or flow == wanted_flow:
                out.append(nxt)
    return out


def walk(start, target, by_tile, by_id, wanted_flow, limit=20000):
    """Breadth first, exactly as `transport_path` (logic/bp/validate.lua:519) does it.

    A single-successor chase is not the rule: a splitter has two continuations and an underground endpoint
    has its partner as well as its facing tile.  When the target is unreachable this reports the dead end
    CLOSEST to it, which is the tile a fix has to reach.
    """
    seeds = [e for e in by_tile.get(start, [])
             if wanted_flow is None or flow_of(e) is None or flow_of(e) == wanted_flow]
    if not seeds:
        return {"reached": False, "stopped_at": start, "why": "no belt of this flow at the source tile",
                "steps": 0}
    frontier = list(seeds)
    seen = {id(e) for e in seeds}
    dead_ends, visited = [], 0
    while frontier and visited < limit:
        nxt = []
        for entity in frontier:
            visited += 1
            here = entity_tile(entity)
            if here == target:
                return {"reached": True, "stopped_at": here, "why": "reached", "steps": visited}
            options = successors(entity, by_tile, by_id, wanted_flow)
            fresh = [o for o in options if id(o) not in seen]
            if not options:
                dead_ends.append(entity)
            for option in fresh:
                seen.add(id(option))
                nxt.append(option)
        frontier = nxt
    if not dead_ends:
        return {"reached": False, "stopped_at": None, "why": "walk closed with no dead end and no target",
                "steps": visited}

    def distance(entity):
        x, y = entity_tile(entity)
        return abs(x - target[0]) + abs(y - target[1])

    worst = min(dead_ends, key=distance)
    wx, wy = entity_tile(worst)
    direction = direction_of(worst)
    ahead = None
    if direction in VECTOR:
        dx, dy = VECTOR[direction]
        ahead = (wx + dx, wy + dy)
    occupants = by_tile.get(ahead, []) if ahead else []
    why = "nothing ahead" if not occupants else "tile ahead carries another flow"
    return {"reached": False, "stopped_at": (wx, wy), "why": why, "steps": visited,
            "facing": NAME.get(direction), "flow": flow_of(worst), "name": worst.get("name"),
            "ahead": ahead, "ahead_flows": sorted({str(flow_of(o)) for o in occupants}),
            "splitter": bool(worst.get("splitter")), "ug_role": worst.get("ug_role"),
            "dead_ends": len(dead_ends), "distance": distance(worst)}


def port_tiles(candidate):
    tiles = {}
    for port in list(candidate.get("ports") or []) + list(candidate.get("external_ports") or []):
        pid = port.get("port_id") or port.get("id")
        x, y = tile(port.get("x")), tile(port.get("y"))
        if pid is not None and x is not None and y is not None:
            tiles[str(pid)] = (x, y, port.get("flow_id") or port.get("full_name"), port.get("role"))
    return tiles


def main():
    payload = json.loads(open(sys.argv[1]).read())
    candidate = payload.get("candidate") or {}
    entities = candidate.get("entities") or []
    by_tile, by_id = belts_by_tile(entities)
    ports = port_tiles(candidate)
    belts = sum(len(v) for v in by_tile.values())
    inserters = [e for e in entities if (e.get("type") == "inserter" or e.get("kind") == "inserter")]
    machines = [e for e in entities if (e.get("type") == "machine" or e.get("kind") == "machine")]

    print("CHAIN candidate entities=%d belts=%d inserters=%d machines=%d ports=%d ops_used=%s"
          % (len(entities), belts, len(inserters), len(machines), len(ports), payload.get("ops_used")))
    print("CHAIN splitters=%d undergrounds=%d"
          % (sum(1 for e in entities if e.get("splitter")),
             sum(1 for e in entities if e.get("ug_role"))))

    #Every routed segment is one demand's run.  Walking port to port is what `connection_path` does at
    #logic/bp/validate.lua:1346-1349, so a break found here is a break the validator will find.
    reasons, broken, whole = Counter(), [], 0
    for binding in (candidate.get("bindings") or []):
        source = str(binding.get("source_port_id") or "")
        sink = str(binding.get("sink_port_id") or "")
        if source not in ports or sink not in ports:
            reasons["binding names a port the candidate does not publish"] += 1
            continue
        sx, sy, port_flow, _ = ports[source]
        tx, ty, _, _ = ports[sink]
        flow = binding.get("flow_id") or port_flow
        result = walk((sx, sy), (tx, ty), by_tile, by_id, flow)
        if result["reached"]:
            whole += 1
        else:
            broken.append((source, sink, flow, result))
            reasons[result["why"]] += 1

    print("CHAIN bindings=%d whole=%d broken=%d" % (len(candidate.get("bindings") or []), whole, len(broken)))
    for why, count in reasons.most_common():
        print("CHAIN reason %-46s %d" % (why, count))
    for source, sink, flow, result in broken[:20]:
        print("CHAIN break %s -> %s flow=%s stopped_at=%s facing=%s why=%s ahead=%s ahead_flows=%s"
              " splitter=%s ug_role=%s dead_ends=%s distance=%s visited=%s"
              % (source, sink, flow, result.get("stopped_at"), result.get("facing"), result.get("why"),
                 result.get("ahead"), result.get("ahead_flows"), result.get("splitter"),
                 result.get("ug_role"), result.get("dead_ends"), result.get("distance"),
                 result.get("steps")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
