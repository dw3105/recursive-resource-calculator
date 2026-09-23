#!/usr/bin/env python3
"""Count the three transport shapes the player rejected in game on 2026-09-23.

Reads a blueprint string file (the delivered bytes) and prints one line:

    sideload=<n> back_to_back=<n> cycles=<n>

sideload      a belt, splitter or underground exit that feeds an underground-belt endpoint from anywhere but
              straight behind an INPUT.  The player's rule, 2026-09-23: a side-load is LEGAL, and a last
              resort -- one lane of the feeder is blocked by the inlet, so it is used only when nothing simpler
              exists.  This probe cannot tell which lane the items ride, so it COUNTS side-loads and does not
              fail on them; the lane-aware verdict belongs to tools/blueprint_audit.py.  Round 20's
              (14,4)W -> (13,4) input N stalled in game because the items rode the blocked lane.
back_to_back  an underground output whose very next tile is an input of the same direction, where one pair
              would have reached: (14,1) -> (15,1) E, two entities bought nothing.
cycles        a directed belt graph cycle: items circulate forever.  Round 20's copper-ore feed ran
              (1,22)..(1,29) S, (2,29)..(2,22) N under two inserters, and back into (1,22): 14 tiles.

Exit 0 when back_to_back and cycles are zero, 1 otherwise, 2 on unreadable input.  With --strict,
side-loads fail too.  Positions are tile coordinates.
"""
import base64
import json
import sys
import zlib

VEC = {0: (0, -1), 4: (1, 0), 8: (0, 1), 12: (-1, 0)}
UNDERGROUND_REACH = {"underground-belt": 5, "fast-underground-belt": 7, "express-underground-belt": 9,
                     "turbo-underground-belt": 11}


def tile(entity):
    p = entity["position"]
    return (int(p["x"] - 0.5), int(p["y"] - 0.5))


def decode(path):
    raw = open(path).read().strip()
    return json.loads(zlib.decompress(base64.b64decode(raw[1:])))["blueprint"]["entities"]


def measure(entities, verbose=False):
    belts, unders, splitters = {}, {}, {}
    for e in entities:
        name, d = e["name"], e.get("direction", 0)
        if name.endswith("transport-belt"):
            belts[tile(e)] = d
        elif name.endswith("underground-belt"):
            unders[tile(e)] = (e.get("type"), d, UNDERGROUND_REACH.get(name, 5))
        elif name.endswith("splitter"):
            #A splitter's position is the midpoint of its two tiles, across its own direction.
            first = (int(e["position"]["x"] - 1.0), int(e["position"]["y"] - 0.5)) if d in (0, 8) \
                else (int(e["position"]["x"] - 0.5), int(e["position"]["y"] - 1.0))
            second = (first[0] + 1, first[1]) if d in (0, 8) else (first[0], first[1] + 1)
            splitters[first] = d
            splitters[second] = d
    report = []
    sideload = 0
    feeders = list(belts.items()) + list(splitters.items()) + \
        [(p, v[1]) for p, v in unders.items() if v[0] == "output"]
    for src, d in feeders:
        dx, dy = VEC[d]
        dst = (src[0] + dx, src[1] + dy)
        if dst in unders:
            kind, ud, _ = unders[dst]
            if not (kind == "input" and ud == d):
                sideload += 1
                report.append("SIDELOAD %s dir=%d -> %s %s dir=%d" % (src, d, dst, kind, ud))
    pair = {}
    for p, (kind, d, reach) in unders.items():
        if kind != "input":
            continue
        dx, dy = VEC[d]
        for k in range(1, reach + 1):
            q = (p[0] + dx * k, p[1] + dy * k)
            if q in unders and unders[q][1] == d:
                if unders[q][0] == "output":
                    pair[p] = q
                break
    back_to_back = 0
    entry_of = {v: k for k, v in pair.items()}
    for p, (kind, d, reach) in unders.items():
        if kind != "output":
            continue
        dx, dy = VEC[d]
        nxt = (p[0] + dx, p[1] + dy)
        if nxt in pair and unders[nxt][1] == d and p in entry_of:
            span = abs(pair[nxt][0] - entry_of[p][0]) + abs(pair[nxt][1] - entry_of[p][1])
            if span <= reach:
                back_to_back += 1
                report.append("BACK_TO_BACK %s -> %s dir=%d one pair %s -> %s spans %d" %
                              (p, nxt, d, entry_of[p], pair[nxt], span))
    heading = dict(belts)
    heading.update(splitters)
    for p, v in unders.items():
        heading[p] = v[1]

    def successor(p):
        if p in pair:
            return pair[p]
        dx, dy = VEC[heading[p]]
        q = (p[0] + dx, p[1] + dy)
        return q if q in heading else None

    cycles, seen = 0, set()
    for start in heading:
        order, index, cur = [], {}, start
        while cur is not None and cur not in index and len(order) < 10000:
            index[cur] = len(order)
            order.append(cur)
            cur = successor(cur)
        if cur is not None and cur in index:
            ring = frozenset(order[index[cur]:])
            if ring not in seen:
                seen.add(ring)
                cycles += 1
                report.append("CYCLE len=%d first=%s" % (len(ring), sorted(ring)[0]))
    if verbose:
        for line in report:
            print("  " + line)
    return sideload, back_to_back, cycles


def main(argv):
    if len(argv) < 2:
        print("usage: transport_shape_probe.py <blueprint.txt> [-v]", file=sys.stderr)
        return 2
    try:
        entities = decode(argv[1])
    except Exception as exc:  # noqa: BLE001 - one line names the unreadable input
        print("unreadable blueprint %s: %s" % (argv[1], exc), file=sys.stderr)
        return 2
    s, b, c = measure(entities, verbose="-v" in argv)
    print("sideload=%d back_to_back=%d cycles=%d" % (s, b, c))
    if b or c or ("--strict" in argv and s):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
