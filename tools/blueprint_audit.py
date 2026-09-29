#!/usr/bin/env python3
"""Audit a DELIVERED blueprint string against the physical contract, reading bytes only.

Why this exists.  Twice the generator reported `ok=true` on an arrangement that cannot produce, and both times
the lie lived in an internal table.  Round 12: `validate.lua` accepted a candidate with every belt removed.
Round 13: `tests/golden/generate.lua:414` reported `Validate.reconcile_artifact` AS the validation result, and
that function never reads a belt, a pipe or an inserter.  An auditor that decodes the delivered string and
re-derives the geometry cannot be fooled by either, because it never sees our tables at all.

It answers these questions; the first four are the ones the round 13 delivery failed:

  * does every inserter pick up from, and drop onto, a real belt or a real machine?
  * does every underground endpoint have a legal partner it can actually pair with?
  * does every transport component serve something, or is it decoration?
  * is every beacon load-bearing, or would removing it leave every machine at its configured count?
  * RRC-03: does any hand take from the first tile of a belt nothing feeds, or drop onto the last tile of a
    belt that leads nowhere?  Round 18 shipped all 26 hands turned 180 degrees and every count above read 0.
  * RRC-03: would the game import the string at all?  Decode, schema and wire rows are named before geometry.

Frozen baseline, measured on this host 2026-09-21 against
~/share/RRC/rrc-round13-mine.txt (sha256 9e075dddf2a16485cfa4d24e45b5fc62f2ba6cb04fbc23236ca6b8c78cb3d95a):
11 invalid inserters, 12 unpairable pipe-to-ground endpoints, 89 untouched belt tiles, 3 redundant beacons.
Any change to those four numbers is a change to this tool, not a discovery.

usage: blueprint_audit.py <blueprint.txt | generator.json> [--beacon-config FILE] [--expect-target FILE]
                           [--expect-wires N] [--json] [-q]
"""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import sys
import zlib
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

#Tile footprints.  A blueprint carries no size, so the auditor needs the prototype fact to know which cells an
#entity occupies.  Splitters have a direction-dependent rectangular footprint (handled below).
SIZE = {
    "assembling-machine-1": 3, "assembling-machine-2": 3, "assembling-machine-3": 3,
    "electromagnetic-plant": 4, "electric-furnace": 3, "steel-furnace": 2, "stone-furnace": 2,
    "foundry": 5, "biochamber": 3, "chemical-plant": 3, "oil-refinery": 5, "centrifuge": 3,
    "cryogenic-plant": 5, "rocket-silo": 9, "lab": 3, "beacon": 3, "roboport": 4,
    "big-electric-pole": 2, "substation": 2,
    #Player mod machines on the gray + magenta sheet (catalog tile_w/tile_h, 2026-09-28): without them 18 inserters
    #read as dropping onto empty ground.
    "smelting-plant": 4, "machining-assembler": 5,
}

MACHINES = {
    "assembling-machine-1", "assembling-machine-2", "assembling-machine-3", "electromagnetic-plant",
    "electric-furnace", "steel-furnace", "stone-furnace", "foundry", "biochamber", "chemical-plant",
    "oil-refinery", "centrifuge", "cryogenic-plant", "rocket-silo", "smelting-plant", "machining-assembler",
}
BELTS = {"transport-belt", "fast-transport-belt", "express-transport-belt", "turbo-transport-belt"}
UG_BELTS = {"underground-belt", "fast-underground-belt", "express-underground-belt", "turbo-underground-belt"}
SPLITTERS = {"splitter", "fast-splitter", "express-splitter", "turbo-splitter"}
PIPES = {"pipe"}
UG_PIPES = {"pipe-to-ground"}
POLES = {"small-electric-pole", "medium-electric-pole", "big-electric-pole", "substation"}

#Underground reach per family, in tiles between the two endpoint centres.  Vanilla 2.0 values.
UG_REACH = {
    "underground-belt": 5, "fast-underground-belt": 7, "express-underground-belt": 9,
    "turbo-underground-belt": 11, "pipe-to-ground": 10,
}
BEACON_SUPPLY_DISTANCE = 3.0   #vanilla beacon supply_area_distance; 3x3 entity => 9x9 supplied area

#Factorio 2.0 uses sixteen directions; only the four cardinals can carry transport.
VEC = {0: (0.0, -1.0), 4: (1.0, 0.0), 8: (0.0, 1.0), 12: (-1.0, 0.0)}
OPPOSITE = {0: 8, 4: 12, 8: 0, 12: 4}
NAME = {0: "north", 4: "east", 8: "south", 12: "west"}


def occupied_tiles(entity):
    """Return tile-centre coordinates covered by an entity, including oriented splitter footprints."""
    name = entity.get("name")
    px, py = entity["position"]["x"], entity["position"]["y"]
    if name in SPLITTERS:
        direction = entity.get("direction", 0)
        if direction not in VEC:
            return [(px, py)]
        vx, vy = VEC[direction]
        # Across the splitter is perpendicular to its flow.  Its anchor lies midway between these tiles.
        return [(px - vy * 0.5, py + vx * 0.5), (px + vy * 0.5, py - vx * 0.5)]
    size = SIZE.get(name, 1)
    half = (size - 1) / 2.0
    return [(px - half + dx, py - half + dy) for dx in range(size) for dy in range(size)]


def load_entities(path: Path) -> Tuple[List[Dict[str, Any]], List[Any], str]:
    """Return (entities, wires, label) from a blueprint string file or a generator JSON result."""
    text = path.read_text().strip()
    if text.startswith("{"):
        payload = json.loads(text)
        result = payload.get("result") or payload
        return list(result.get("entities") or []), list(result.get("wires") or []), "generator json"
    if not text or text[0] != "0":
        raise SystemExit(f"blueprint_audit.py: {path} is not a version-0 blueprint string")
    decoded = json.loads(zlib.decompress(base64.b64decode(text[1:])))
    blueprint = decoded.get("blueprint")
    if blueprint is None:
        raise SystemExit("blueprint_audit.py: the string decodes to a book or an upgrade planner, not a blueprint")
    return list(blueprint.get("entities") or []), list(blueprint.get("wires") or []), blueprint.get("label") or ""


def family_census(entities: List[Dict[str, Any]]) -> Dict[str, int]:
    """Count every delivered entity by the audit's known physical families.

    The family sets are deliberately the same ones used by the physical checks below.  Unknown names remain
    visible under ``other`` instead of disappearing from the report.
    """
    counts = {
        "belts": 0,
        "undergrounds": 0,
        "splitters": 0,
        "inserters": 0,
        "machines": 0,
        "poles": 0,
        "pipes": 0,
        "beacons": 0,
        "roboports": 0,
        "other": 0,
    }
    for entity in entities:
        name = entity.get("name") or ""
        if name in BELTS:
            family = "belts"
        elif name in UG_BELTS:
            family = "undergrounds"
        elif name in SPLITTERS:
            family = "splitters"
        elif "inserter" in name:
            family = "inserters"
        elif name in MACHINES:
            family = "machines"
        elif name in POLES:
            family = "poles"
        elif name in PIPES or name in UG_PIPES:
            family = "pipes"
        elif name == "beacon":
            family = "beacons"
        elif name == "roboport":
            family = "roboports"
        else:
            family = "other"
        counts[family] += 1
    counts["entities_excluding_roboports"] = len(entities) - counts["roboports"]
    return counts


def target_mismatches(counts: Dict[str, int], path: Path) -> List[str]:
    """Return one readable mismatch for each count pinned by a target JSON file."""
    target = json.loads(path.read_text())
    if not isinstance(target, dict):
        raise SystemExit(f"blueprint_audit.py: target {path} must contain a JSON object")

    mismatches = []
    for key, expectation in target.items():
        # Delivery targets may carry a human note alongside their count pins.
        if key in ("note", "_note"):
            continue
        delivered = counts.get(key)
        if isinstance(expectation, dict):
            lower = expectation.get("min")
            upper = expectation.get("max")
            valid = ((lower is None or delivered is not None and delivered >= lower)
                     and (upper is None or delivered is not None and delivered <= upper))
            if lower is not None and upper is not None:
                expected_text = f"between {lower} and {upper}"
            elif lower is not None:
                expected_text = f"at least {lower}"
            elif upper is not None:
                expected_text = f"at most {upper}"
            else:
                valid = False
                expected_text = "a target window"
        else:
            valid = delivered == expectation
            expected_text = str(expectation)
        if not valid:
            mismatches.append(f"target {key}: delivered {delivered}, expected {expected_text}")
    return mismatches


def occupancy(entities: List[Dict[str, Any]]) -> Dict[Tuple[float, float], Dict[str, Any]]:
    cells: Dict[Tuple[float, float], Dict[str, Any]] = {}
    for entity in entities:
        for tile in occupied_tiles(entity):
            cells[tile] = entity
    return cells


def endpoint_kind(entity: Optional[Dict[str, Any]]) -> str:
    """What an inserter found at one of its cells, in contract 26.3's vocabulary."""
    if entity is None:
        return "empty ground"
    name = entity.get("name", "")
    if name in MACHINES:
        return "machine"
    if name in BELTS or name in UG_BELTS or name in SPLITTERS:
        return "belt"
    return name


def audit_inserters(entities, cells) -> List[str]:
    """Contract 26.3: each inserter's pickup and drop cell must hold a real belt or a real machine."""
    failures = []
    for entity in entities:
        if "inserter" not in entity.get("name", ""):
            continue
        direction = entity.get("direction", 0)
        px, py = entity["position"]["x"], entity["position"]["y"]
        if direction not in VEC:
            failures.append(f"inserter at ({px},{py}) faces direction {direction}, which is not cardinal")
            continue
        # In a blueprint, direction points to the pickup tile; the inserter drops behind itself.
        # A long-handed inserter reaches TWO tiles each way (tools/lane_sim.py already knew this); reading one tile
        # reported player-inserter-10s's long hand at (25.5,26.5) as picking from empty ground, 2026-09-25.
        reach = 2 if "long-handed" in entity.get("name", "") else 1
        vx, vy = VEC[direction]
        vx, vy = vx * reach, vy * reach
        pickup = endpoint_kind(cells.get((px + vx, py + vy)))
        drop = endpoint_kind(cells.get((px - vx, py - vy)))
        bad_pickup = pickup not in ("belt", "machine")
        bad_drop = drop not in ("belt", "machine")
        if bad_pickup or bad_drop:
            failures.append(
                f"inserter at ({px},{py}) facing {NAME[direction]}: picks up from {pickup}, drops onto {drop}")
    return failures


def audit_underground(entities) -> Tuple[List[str], Dict[str, int]]:
    """Contract 26.5: every underground endpoint needs a partner it can genuinely pair with.

    Belts pair in the SAME direction, entrance `input` and exit `output`, and the entrance looks DOWNSTREAM
    while the exit looks UPSTREAM -- an exit scanned downstream finds its own successor and reports a false
    orphan.  Pipes pair in OPPOSITE directions, each one's buried side facing the other, and carry no `type`
    field at all.  Both need the partner on the axis the endpoint points along, within the family's reach,
    with no nearer endpoint of the same family stealing the pairing.
    """
    failures = []
    by_family: Dict[str, int] = {}
    pairs: List[Tuple[Tuple[float, float], Tuple[float, float]]] = []
    families = {}
    for entity in entities:
        name = entity.get("name", "")
        if name in UG_BELTS or name in UG_PIPES:
            families.setdefault(name, []).append(entity)

    for name, members in families.items():
        reach = UG_REACH.get(name, 5)
        is_pipe = name in UG_PIPES
        for entity in members:
            direction = entity.get("direction", 0)
            px, py = entity["position"]["x"], entity["position"]["y"]
            if direction not in VEC:
                failures.append(f"{name} at ({px},{py}) faces direction {direction}, which is not cardinal")
                continue
            vx, vy = VEC[direction]
            want_direction = OPPOSITE[direction] if is_pipe else direction
            #A belt exit is fed from behind it, so it must look the other way along the same axis.
            if not is_pipe and entity.get("type") == "output":
                vx, vy = -vx, -vy
            #A pipe-to-ground faces its EXPOSED connection; its buried side, and so its partner, is behind it
            #(prototype: normal connection at the entity's direction, underground connection opposite).
            if is_pipe:
                vx, vy = -vx, -vy
            partner = None
            blocker = None
            for step in range(1, reach + 1):
                qx, qy = px + vx * step, py + vy * step
                other = next((m for m in members
                              if m["position"]["x"] == qx and m["position"]["y"] == qy), None)
                if other is None:
                    continue
                #An endpoint on the OTHER axis is not a candidate at all: the engine pairs an underground only
                #along its own axis, so a crossing pair passes under it.  Counting it as a blocker reported
                #(5,3) E -> (10,3) E, which passes under the NORTH exit at (6,3), as two orphans, measured
                #2026-09-23 on legalcopilot-dev in round 21's first delivery.
                if VEC.get(other.get("direction", 0), (None, None))[0] == 0 and vx == 0 or \
                        VEC.get(other.get("direction", 0), (None, None))[1] == 0 and vy == 0:
                    pass
                else:
                    continue
                #The FIRST endpoint of this family along the axis is the one the engine pairs with.  A later,
                #better-oriented candidate never gets the chance -- that is the stolen-partner case.
                if other.get("direction", 0) == want_direction and (
                        is_pipe or {entity.get("type"), other.get("type")} == {"input", "output"}):
                    partner = other
                else:
                    blocker = other
                break
            if partner is not None:
                pairs.append(((px, py), (partner["position"]["x"], partner["position"]["y"])))
            if partner is None:
                detail = (f"nearest endpoint at ({blocker['position']['x']},{blocker['position']['y']}) "
                          f"faces {NAME.get(blocker.get('direction', 0), blocker.get('direction'))}"
                          if blocker is not None else f"no endpoint within {reach} tiles")
                need = "opposite" if is_pipe else "same"
                failures.append(
                    f"{name} at ({px},{py}) facing {NAME[direction]} has no partner "
                    f"({need}-facing required): {detail}")
                by_family[name] = by_family.get(name, 0) + 1
    return failures, by_family, pairs


def audit_orphans(entities, cells, pairs) -> Tuple[List[str], int, int]:
    """Contract 26.2: transport that serves no obligation is waste.

    Component membership is NOT the test.  Measured on the round 13 delivery: by orthogonal adjacency alone 89
    belt tiles looked dead, and once legal underground pairs were allowed to join their components -- which is
    physically right, a tunnel is a connection -- the same artifact reported 0.  One inserter anywhere was
    blessing the whole network.  Neither number describes the contract.

    So this walks the belt graph in the direction product actually moves.  A belt tile is USED only when it is
    both reachable forward from a real source and can reach forward to a real sink.  A source is an inserter
    drop cell or a perimeter supply terminal; a sink is an inserter pickup cell or a perimeter drain terminal.
    A perimeter terminal is a belt on the artifact's bounding edge with nothing feeding it, or nothing after
    it: from bytes alone a declared external terminal is indistinguishable from a stub, so the edge is the only
    defensible inference and every inferred terminal is reported.

    Pipes carry no direction, so a pipe network is used when it touches a machine fluid box; an unpaired
    pipe-to-ground is already reported by contract 26.5.
    """
    transport = {tile: e for e in entities if e.get("name") in BELTS | UG_BELTS | SPLITTERS
                 for tile in occupied_tiles(e)}
    partner = {}
    for first, second in pairs:
        if first in transport and second in transport:
            partner[first] = second
            partner[second] = first

    drops, pickups = set(), set()
    for entity in entities:
        if "inserter" not in entity.get("name", ""):
            continue
        direction = entity.get("direction", 0)
        if direction not in VEC:
            continue
        reach = 2 if "long-handed" in entity.get("name", "") else 1
        vx, vy = VEC[direction]
        vx, vy = vx * reach, vy * reach
        px, py = entity["position"]["x"], entity["position"]["y"]
        if (px - vx, py - vy) in transport:
            drops.add((px - vx, py - vy))
        if (px + vx, py + vy) in transport:
            pickups.add((px + vx, py + vy))

    def successor(cell):
        entity = transport[cell]
        #A belt entrance hands product to its exit; everything else hands it to the tile it faces.
        if entity.get("name") in UG_BELTS and entity.get("type") == "input":
            return partner.get((entity["position"]["x"], entity["position"]["y"]))
        direction = entity.get("direction", 0)
        if direction not in VEC:
            return None
        vx, vy = VEC[direction]
        if entity.get("name") in SPLITTERS:
            # Both lanes enter at the back and may leave through either front lane.  There are no side exits.
            return [nxt for lane in occupied_tiles(entity)
                    if (nxt := (lane[0] + vx, lane[1] + vy)) in transport]
        nxt = (cell[0] + vx, cell[1] + vy)
        return nxt if nxt in transport else None

    forward = {cell: successor(cell) for cell in transport}
    # The two incoming lanes can be routed to either of the splitter's two outputs.
    for entity in entities:
        if entity.get("name") not in SPLITTERS:
            continue
        direction = entity.get("direction", 0)
        if direction not in VEC:
            continue
        vx, vy = VEC[direction]
        lanes = occupied_tiles(entity)
        back_sources = [(lane[0] - vx, lane[1] - vy) for lane in lanes]
        for source in back_sources:
            if source in transport and transport[source].get("name") not in SPLITTERS:
                forward[source] = [*([forward[source]] if forward.get(source) and not isinstance(forward[source], list)
                                      else forward.get(source) or []), *lanes]
    backward: Dict[Tuple[float, float], List[Tuple[float, float]]] = {}
    for cell, nxt in forward.items():
        for destination in (nxt if isinstance(nxt, list) else [nxt] if nxt is not None else []):
            backward.setdefault(destination, []).append(cell)

    #A belt run that begins nowhere is where the player feeds it; one that ends nowhere is where it leaves.
    #That is the physical reading, and it needs no bounding box at all.
    #
    #The bounding box version was wrong twice over. It missed almost every terminal in a hand-built factory,
    #because roboports and poles push the box far from the belt ends: measured on
    #~/share/RRC/red_science_1s_manual_bp.txt, a working 131-entity factory, it inferred 3 terminals and
    #declared all 84 belts unused. And it missed the real structure -- supply runs feed inserter PICKUPS while
    #output runs carry inserter DROPS away, so the two never touch. Forward-reachable-from-a-drop and
    #reaches-a-pickup were disjoint sets of 25, intersecting in 0.
    #
    #A cell with neither a predecessor nor a successor would be BOTH a supply and a drain, and so would
    #satisfy its own obligation. That is exactly the stray-belt case, so it is excluded from both.
    terminals = []
    sources, sinks = set(drops), set(pickups)
    for cell in sorted(transport):
        has_feeder = bool(backward.get(cell))
        has_next = forward.get(cell) is not None
        if not has_feeder and not has_next:
            continue
        if not has_feeder and cell not in sources:
            sources.add(cell)
            terminals.append(f"inferred external SUPPLY terminal at {cell}")
        if not has_next and cell not in sinks:
            sinks.add(cell)
            terminals.append(f"inferred external DRAIN terminal at {cell}")

    def walk(seeds, graph):
        seen, stack = set(seeds), list(seeds)
        while stack:
            cell = stack.pop()
            for nxt in (graph.get(cell) or []) if isinstance(graph.get(cell), list) else (
                    [graph.get(cell)] if graph.get(cell) else []):
                if nxt not in seen:
                    seen.add(nxt)
                    stack.append(nxt)
        return seen

    fed = walk(sources, forward)
    draining = walk(sinks, backward)
    dead = sorted(cell for cell in transport if cell not in fed or cell not in draining)

    failures = [f"{transport[cell]['name']} at {cell} serves no obligation: "
                + ("no source reaches it" if cell not in fed else "it reaches no sink") for cell in dead]

    dead_pipe = 0
    pipe_cells = {(e["position"]["x"], e["position"]["y"]): e
                  for e in entities if e.get("name") in PIPES | UG_PIPES}
    seen_pipe = set()
    for start in sorted(pipe_cells):
        if start in seen_pipe:
            continue
        stack, group = [start], []
        seen_pipe.add(start)
        while stack:
            cell = stack.pop()
            group.append(cell)
            neighbours = [(cell[0] + dx, cell[1] + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
            neighbours.extend([q for r, q in pairs if r == cell] + [r for r, q in pairs if q == cell])
            for nxt in neighbours:
                if nxt in pipe_cells and nxt not in seen_pipe:
                    seen_pipe.add(nxt)
                    stack.append(nxt)
        touches = any(
            (cells.get((cx + dx, cy + dy)) or {}).get("name") in MACHINES
            for cx, cy in group for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if not touches:
            dead_pipe += len(group)
            failures.append(f"pipe component of {len(group)} tiles at {min(group)} touches no machine")

    return failures, len(dead), dead_pipe, terminals


def audit_transport_shapes(entities, pairs):
    """Count side entries, blocked underground entries, adjacent tunnels, and directed belt cycles."""
    transport = {tile: e for e in entities if e.get("name") in BELTS | UG_BELTS | SPLITTERS
                 for tile in occupied_tiles(e)}
    side, blocked, back = [], [], []
    pair_map = {a: b for a, b in pairs} | {b: a for a, b in pairs}
    for target, inlet in transport.items():
        if inlet.get("name") not in UG_BELTS or inlet.get("type") != "input":
            continue
        d = inlet.get("direction", 0)
        if d not in VEC: continue
        vx, vy = VEC[d]
        for feeder in ((target[0]-vy, target[1]+vx), (target[0]+vy, target[1]-vx)):
            source = transport.get(feeder)
            if not source or source.get("name") not in BELTS | SPLITTERS: continue
            if source.get("direction", 0) not in VEC or VEC[source.get("direction", 0)] != (target[0]-feeder[0], target[1]-feeder[1]): continue
            side.append((feeder, target))
            # Engine (headless 2.0.77 + 2.1.20, round 48 twins ug_sideload_north/south): a plain belt side-loading an
            # underground entrance loses one of its two lanes to the hood from EITHER side (3.75 of 7.5 items/s).
            # The old rule counted one side only.
            if source.get("name") in SPLITTERS: continue
            blocked.append((feeder, target))
    inputs = [e for e in entities if e.get("name") in UG_BELTS and e.get("type")=="input"]
    outputs = [e for e in entities if e.get("name") in UG_BELTS and e.get("type")=="output"]
    for out in outputs:
        x,y=out["position"]["x"],out["position"]["y"]; d=out.get("direction",0); v=VEC.get(d)
        if not v: continue
        nxt=(x+v[0],y+v[1]); inp=transport.get(nxt)
        if inp and inp.get("name") in UG_BELTS and inp.get("type")=="input" and inp.get("direction")==d:
            origin=pair_map.get((x,y))
            end=pair_map.get(nxt)
            if origin and end:
                span=abs(origin[0]-end[0])+abs(origin[1]-end[1])
                if span <= UG_REACH.get(out.get("name"),5): back.append(((x,y),nxt))
    # Directed tile graph; underground inputs jump to their paired output. Splitter tiles emit to both front tiles.
    graph={}
    for cell,e in transport.items():
        d=e.get("direction",0); v=VEC.get(d); dest=[]
        if e.get("name") in UG_BELTS and e.get("type")=="input":
            q=pair_map.get(cell)
            if q in transport: dest=[q]
        elif v:
            if e.get("name") in SPLITTERS:
                dest=[q for t in occupied_tiles(e) if (q:=(t[0]+v[0],t[1]+v[1])) in transport]
            else:
                q=(cell[0]+v[0],cell[1]+v[1])
                target = transport.get(q)
                # On legalcopilot-dev's magenta 10/s blueprint (2026-09-29), the apparent cycle was
                # two belt ends facing each other; Factorio moves no items between those belts.
                if target and not (e.get("name") in BELTS and target.get("name") in BELTS
                                   and VEC.get(target.get("direction", 0)) == (-v[0], -v[1])):
                    dest=[q]
        graph[cell]=dest
    visiting=set(); visited=set(); cycles=0
    def visit(n):
        nonlocal cycles
        if n in visiting: cycles+=1; return
        if n in visited: return
        visiting.add(n)
        for q in graph.get(n,[]): visit(q)
        visiting.remove(n); visited.add(n)
    for cell in graph: visit(cell)
    tile = lambda p: (int(p[0] // 1), int(p[1] // 1))
    return len(side), len(blocked), len(back), cycles, [f"({tile(a)[0]},{tile(a)[1]})->({tile(b)[0]},{tile(b)[1]})" for a,b in blocked]


sys.path.insert(0, str(Path(__file__).resolve().parent))
from blueprint_string import KEEP, TYPED  # noqa: E402  one allow-list, owned by the converter

ENTITY_KEYS = {"entity_number", "type", "drop_position", *KEEP}


def _number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def string_problems(text: str) -> List[str]:
    """RRC-03: every reason the game would refuse to import this string, read from its bytes."""
    text = text.strip()
    try:
        raw = base64.b64decode(text[1:], validate=True)
    except (ValueError, binascii.Error) as error:
        return [f"string: base64: {error}"]
    inflater = zlib.decompressobj()
    try:
        body = inflater.decompress(raw) + inflater.flush()
    except zlib.error as error:
        return [f"string: zlib: {error}"]
    if not inflater.eof:
        return ["string: zlib stream is truncated"]
    if inflater.unused_data:
        return ["string: bytes after the zlib stream"]
    try:
        payload = json.loads(body)
    except ValueError as error:
        return [f"string: JSON: {error}"]
    blueprint = payload.get("blueprint") if isinstance(payload, dict) else None
    if not isinstance(blueprint, dict):
        return []  # a book or planner: load_entities names it
    problems = []
    if blueprint.get("item") != "blueprint":
        problems.append(f"blueprint: item is {blueprint.get('item')!r}, not 'blueprint'")
    if not isinstance(blueprint.get("version"), int) or isinstance(blueprint.get("version"), bool):
        problems.append("blueprint: version is not an integer")
    entities = blueprint.get("entities")
    if entities is None or entities == []:
        return problems  # main names an empty artifact
    if not isinstance(entities, list):
        return problems + ["blueprint: entities is not a list"]
    numbers = set()
    for index, entity in enumerate(entities, start=1):
        where = f"entity {index}"
        if not isinstance(entity, dict):
            problems.append(f"{where}: not an object")
            continue
        name = entity.get("name")
        if isinstance(name, str) and name:
            where = f"entity {index} ({name})"
        else:
            problems.append(f"{where}: name is not a non-empty string")
        number = entity.get("entity_number")
        if not isinstance(number, int) or isinstance(number, bool) or number < 1:
            problems.append(f"{where}: entity_number is not a positive integer")
        elif number in numbers:
            problems.append(f"{where}: entity_number {number} repeats")
        else:
            numbers.add(number)
        position = entity.get("position")
        if not isinstance(position, dict) or not _number(position.get("x")) or not _number(position.get("y")):
            problems.append(f"{where}: position is not numeric x and y")
        if "direction" in entity:
            d = entity["direction"]
            if not isinstance(d, int) or isinstance(d, bool) or not 0 <= d <= 15:
                problems.append(f"{where}: direction {d!r} is not an integer 0..15")
        if "type" in entity and name not in TYPED:
            problems.append(f"{where}: carries 'type' but is not an underground belt or loader")
        elif name in TYPED and "type" not in entity:
            problems.append(f"{where}: has no 'type'; it imports as an entrance")
        elif "type" in entity and entity["type"] not in ("input", "output"):
            problems.append(f"{where}: type {entity['type']!r} is not 'input' or 'output'")
        for key in sorted(set(entity) - ENTITY_KEYS):
            problems.append(f"{where}: unknown key {key!r}")
    for index, wire in enumerate(blueprint.get("wires") or [], start=1):
        if (not isinstance(wire, list) or len(wire) != 4
                or not all(isinstance(v, int) and not isinstance(v, bool) for v in wire)):
            problems.append(f"wire {index}: not four integers")
            continue
        if wire[0] not in numbers or wire[2] not in numbers:
            problems.append(f"wire {index}: names an entity_number the blueprint does not hold")
        if wire[1] < 1 or wire[3] < 1:
            problems.append(f"wire {index}: connector id below 1")
    return problems


def audit_hand_direction(entities, pairs) -> List[str]:
    """RRC-03: a hand that takes from the head of a belt nothing feeds, or drops onto the tail of a belt that leads
    nowhere, is turned 180 degrees."""
    transport = {tile: e for e in entities if e.get("name") in BELTS | UG_BELTS | SPLITTERS
                 for tile in occupied_tiles(e)}
    partner = {}
    for first, second in pairs:
        if first in transport and second in transport:
            partner[first] = second
            partner[second] = first
    nexts = {}
    for cell, entity in transport.items():
        if entity.get("name") in UG_BELTS and entity.get("type") == "input":
            dest = [partner[(entity["position"]["x"], entity["position"]["y"])]] if (entity["position"]["x"], entity["position"]["y"]) in partner else []
        else:
            d = entity.get("direction", 0)
            if d not in VEC:
                dest = []
            else:
                vx, vy = VEC[d]
                if entity.get("name") in SPLITTERS:
                    dest = [q for t in occupied_tiles(entity) if (q := (t[0] + vx, t[1] + vy)) in transport]
                else:
                    q = (cell[0] + vx, cell[1] + vy)
                    dest = [q] if q in transport else []
        nexts[cell] = dest
    for entity in entities:
        if entity.get("name") not in SPLITTERS or entity.get("direction", 0) not in VEC:
            continue
        vx, vy = VEC[entity.get("direction", 0)]
        lanes = occupied_tiles(entity)
        for lane in lanes:
            source = (lane[0] - vx, lane[1] - vy)
            if source in transport and transport[source].get("name") not in SPLITTERS:
                nexts[source] = list(nexts[source]) + lanes
    fed = {q for dest in nexts.values() for q in dest}
    hands = []
    for entity in entities:
        if "inserter" not in entity.get("name", "") or entity.get("direction", 0) not in VEC:
            continue
        reach = 2 if "long-handed" in entity.get("name", "") else 1
        vx, vy = VEC[entity.get("direction", 0)]
        px, py = entity["position"]["x"], entity["position"]["y"]
        hands.append((entity, (px + vx * reach, py + vy * reach), (px - vx * reach, py - vy * reach)))
    drops = {drop for _, _, drop in hands}
    pickups = {pickup for _, pickup, _ in hands}
    failures = []
    for entity, pickup, drop in hands:
        px, py = entity["position"]["x"], entity["position"]["y"]
        facing = NAME[entity.get("direction", 0)]
        if pickup in transport and pickup not in fed and nexts[pickup] and pickup not in drops:
            failures.append(f"inserter at ({px},{py}) facing {facing}: picks up from {pickup}, "
                            f"the first tile of a belt nothing feeds")
        elif drop in transport and not nexts[drop] and drop in fed and drop not in pickups:
            failures.append(f"inserter at ({px},{py}) facing {facing}: drops onto {drop}, "
                            f"the last tile of a belt that leads nowhere")
    return failures


def audit_beacons(entities, config: Dict[str, int]) -> Tuple[List[str], int]:
    """Contract 26.6: extra influence is legal, a REDUNDANT beacon is not.

    A beacon is redundant when removing it leaves every machine at or above its configured count.  Removal is
    greedy in deterministic position order, so the reported count is reproducible.
    """
    beacons = [e for e in entities if e.get("name") == "beacon"]
    machines = [e for e in entities if e.get("name") in MACHINES]
    if not beacons or not config:
        return [], 0

    def required_for(machine):
        key = machine.get("recipe") or machine.get("name")
        return int(config.get(key, config.get(machine.get("name"), 0)))

    def reaches(beacon, machine):
        bx, by = beacon["position"]["x"], beacon["position"]["y"]
        half = SIZE["beacon"] / 2.0 + BEACON_SUPPLY_DISTANCE
        size = SIZE.get(machine["name"], 1) / 2.0
        mx, my = machine["position"]["x"], machine["position"]["y"]
        return (bx - half < mx + size and mx - size < bx + half
                and by - half < my + size and my - size < by + half)

    influence = {id(m): [b for b in beacons if reaches(b, m)] for m in machines}
    ordered = sorted(beacons, key=lambda b: (b["position"]["x"], b["position"]["y"]))
    removed = []
    for beacon in ordered:
        trial = set(id(b) for b in removed) | {id(beacon)}
        if all(len([b for b in influence[id(m)] if id(b) not in trial]) >= required_for(m) for m in machines):
            removed.append(beacon)
    failures = [f"beacon at ({b['position']['x']},{b['position']['y']}) is redundant: "
                f"removing it leaves every machine at its configured count" for b in removed]
    return failures, len(removed)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input", help="blueprint string file, or generator JSON")
    parser.add_argument("--beacon-config", help="JSON map of recipe-or-machine name to configured beacon count")
    parser.add_argument("--expect-wires", type=int, default=None,
                        help="fail unless exactly this many wire edges are delivered")
    parser.add_argument("--expect-target",
                        help="JSON file pinning exact or min/max expected delivery counts")
    parser.add_argument("--json", action="store_true", help="print the counts as JSON")
    parser.add_argument("-q", "--quiet", action="store_true", help="print counts only, never each violation")
    args = parser.parse_args(argv)

    raw_text = Path(args.input).read_text().strip()
    if raw_text.startswith("0"):
        problems = string_problems(raw_text)
        if problems and problems[0].startswith("string: "):
            raise SystemExit(f"blueprint_audit.py: {args.input} does not decode: {problems[0][len('string: '):]}")
        if problems:
            for line in problems:
                print(f"blueprint_audit.py: schema: {line}", file=sys.stderr)
            return 1
    entities, wires, label = load_entities(Path(args.input))
    if not entities:
        raise SystemExit("blueprint_audit.py: the artifact carries no entities")
    cells = occupancy(entities)
    config = json.loads(Path(args.beacon_config).read_text()) if args.beacon_config else {}

    inserter_failures = audit_inserters(entities, cells)
    underground_failures, underground_by_family, underground_pairs = audit_underground(entities)
    orphan_failures, dead_belt, dead_pipe, terminals = audit_orphans(entities, cells, underground_pairs)
    beacon_failures, redundant = audit_beacons(entities, config)
    hand_failures = audit_hand_direction(entities, underground_pairs)
    sideload, sideload_blocked, back_to_back, cycles, blocked_rows = audit_transport_shapes(entities, underground_pairs)

    counts = {
        **family_census(entities),
        "entities": len(entities),
        "wires": len(wires),
        "invalid_inserters": len(inserter_failures),
        "unpairable_underground": len(underground_failures),
        "unpairable_underground_belt": sum(v for k, v in underground_by_family.items() if k in UG_BELTS),
        "unpairable_pipe_to_ground": sum(v for k, v in underground_by_family.items() if k in UG_PIPES),
        "unused_belt_tiles": dead_belt,
        "unused_pipe_tiles": dead_pipe,
        "inferred_terminals": len(terminals),
        "redundant_beacons": redundant,
        "sideload": sideload, "sideload_blocked": sideload_blocked,
        "back_to_back": back_to_back, "cycles": cycles,
        "backward_hands": len(hand_failures),
    }
    groups = [("inserter endpoints (contract 26.3)", inserter_failures),
              ("underground pairing (contract 26.5)", underground_failures),
              ("unused transport (contract 26.2)", orphan_failures),
              ("beacon redundancy (contract 26.6)", beacon_failures),
              ("blocked underground side-load", blocked_rows),
              ("underground back-to-back", [str(x) for x in range(back_to_back)]),
              ("belt route cycles", [str(x) for x in range(cycles)]),
              ("hand direction (RRC-03)", hand_failures)]

    if args.json:
        print(json.dumps(counts, indent=2, sort_keys=True))
    else:
        print(f"blueprint_audit: {args.input}" + (f"  label={label!r}" if label else ""))
        for key in sorted(counts):
            print(f"  {key:24s} {counts[key]}")
        print(f"  roboport entities are excluded from entities_excluding_roboports: {counts['roboports']} excluded")
        if not args.quiet:
            if terminals:
                print(f"\ninferred external terminals: {len(terminals)}")
                for line in terminals:
                    print(f"  {line}")
            for title, failures in groups:
                if failures:
                    print(f"\n{title}: {len(failures)}")
                    for line in failures:
                        print(f"  {line}")

    failed = sum(len(f) for _, f in groups)
    if args.expect_wires is not None and len(wires) != args.expect_wires:
        print(f"\nwires: delivered {len(wires)}, expected {args.expect_wires}", file=sys.stderr)
        failed += 1
    if args.expect_target:
        for mismatch in target_mismatches(counts, Path(args.expect_target)):
            print(mismatch, file=sys.stderr)
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
