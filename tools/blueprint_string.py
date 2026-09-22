#!/usr/bin/env python3
"""Turn the generator's canonical entities into a blueprint string the game will actually import.

The generator's `result.entities` are the mod's INTERNAL shape. In game the mod hands them to the engine,
which builds the real blueprint; offline nothing performs that step, so pasting them straight into a string
produces a blueprint Factorio refuses. Measured 2026-09-21: a string built that way failed to load.

Four things had to change, and each is a different kind of mistake:

  * `type` is carried on every internal entity as its kind -- `machine`, `beacon`, `inserter`, `roboport`. In a
    blueprint `type` means something else entirely: it is the `input`/`output` half of an underground belt or
    loader, and nothing else may have it.
  * `pipe-to-ground` had `type` too. A pipe-to-ground is oriented by `direction` alone.
  * `port_id` and `ug_pair_id` are bookkeeping the router needs and the game has never heard of.
  * `wires` carried connector ids from `logic/bp/validate.lua`'s offline defaults, where `pole_copper` is 0.
    Round 13 dropped them silently and the delivery arrived with 0 of 10 edges. Contract 26.7 forbids that:
    a connector id that is genuinely unavailable offline is a NAMED REFUSAL, never a silent drop. So this
    refuses by default and says exactly which wires it cannot map.

    What is known, measured 2026-09-21: `factorio-draftsman` 4.0.0 reports `WireConnectorID.POLE_COPPER = 5`,
    so the offline placeholder 0 is wrong. Draftsman itself is NOT an oracle here -- it accepted connector 99
    and round-tripped `wires` as `None`, so it drops wires exactly as it drops every `recipe`. Writing 5 on
    that evidence alone would be a guess, and a guess is what makes a blueprint fail to import.

    All ten edges in the round 13 result were pole-to-pole copper, and electric poles auto-connect to poles in
    range when a blueprint is built, so omitting those specific wires costs nothing physically. That is a
    reason to allow it EXPLICITLY with --allow-pole-autoconnect, never a reason to do it quietly.

usage: blueprint_string.py <generate-output.json> [-o out.txt] [--label TEXT]
"""

from __future__ import annotations

import argparse
import base64
import json
import math
import sys
import zlib
from pathlib import Path
from typing import Any, Dict, List

#2.0.77, packed the way Factorio packs a version: major<<48 | minor<<32 | patch<<16 | dev.
DEFAULT_VERSION = (2 << 48) | (0 << 32) | (77 << 16)

#Only these take the input/output `type` in a blueprint.
TYPED = {"underground-belt", "loader", "loader-1x1", "fast-loader", "express-loader"}

#Everything the engine understands on an ordinary blueprint entity. Anything else is internal.
KEEP = ("name", "position", "direction", "recipe", "recipe_quality", "items", "quality",
        "orientation", "bar", "filters", "filter_mode", "override_stack_size", "control_behavior",
        "use_filters", "request_filters", "mirror", "tags")


def convert(entities: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    result = []
    for index, entity in enumerate(entities, start=1):
        position = entity.get("position")
        if (not isinstance(position, dict)
                or any(not isinstance(position.get(axis), (int, float))
                       or not math.isfinite(position[axis]) for axis in ("x", "y"))):
            raise SystemExit(
                f"blueprint_string.py: entity {index} ({entity.get('name', '<unnamed>')}) "
                "has no usable position")
        out: Dict[str, Any] = {"entity_number": index}
        for key in KEEP:
            if entity.get(key) is not None:
                out[key] = entity[key]
        #A direction of 0 is the default; writing it changes nothing and only adds noise.
        if out.get("direction") == 0:
            del out["direction"]
        if entity.get("name") in TYPED and entity.get("type") in ("input", "output"):
            out["type"] = entity["type"]
        result.append(out)
    return result


#The offline stand-in `logic/bp/power.lua:255-263` writes when no runtime connector id was captured.
PLACEHOLDER_CONNECTOR = 0
POLE_NAMES = {"small-electric-pole", "medium-electric-pole", "big-electric-pole", "substation"}


def resolve_wires(result: Dict[str, Any], entities: List[Dict[str, Any]],
                  allow_pole_autoconnect: bool) -> List[List[int]]:
    """Carry every wire, or refuse by name. Never drop one quietly."""
    wires = result.get("wires") or []
    if not wires:
        return []
    by_number = {entity["entity_number"]: entity for entity in entities}
    carried: List[List[int]] = []
    omitted: List[str] = []
    for wire in wires:
        if not isinstance(wire, (list, tuple)) or len(wire) != 4:
            raise SystemExit(f"blueprint_string.py: a wire is not [entity, connector, entity, connector]: {wire!r}")
        first, first_connector, second, second_connector = wire
        for number in (first, second):
            if number not in by_number:
                raise SystemExit(
                    f"blueprint_string.py: wire {wire!r} names entity {number}, which the artifact does not carry")
        placeholder = PLACEHOLDER_CONNECTOR in (first_connector, second_connector)
        if not placeholder:
            carried.append([first, first_connector, second, second_connector])
            continue
        both_poles = all(by_number[n]["name"] in POLE_NAMES for n in (first, second))
        if both_poles and allow_pole_autoconnect:
            omitted.append(f"{by_number[first]['name']}#{first} to {by_number[second]['name']}#{second}")
            continue
        raise SystemExit(
            f"blueprint_string.py: wire {wire!r} carries the offline placeholder connector "
            f"{PLACEHOLDER_CONNECTOR}, which is not a real wire_connector_id. The capture must supply the "
            f"runtime id. For pole-to-pole copper only, pass --allow-pole-autoconnect to omit it "
            f"deliberately: poles reconnect themselves when the blueprint is built.")
    if omitted:
        sys.stderr.write("blueprint_string.py: omitted %d pole-to-pole copper wire(s); poles auto-connect on "
                         "build:\n" % len(omitted))
        for line in omitted:
            sys.stderr.write("  " + line + "\n")
    return carried


def build(result: Dict[str, Any], label: str, version: int = DEFAULT_VERSION,
          allow_pole_autoconnect: bool = False) -> str:
    entities = convert(result.get("entities") or [])
    if not entities:
        raise SystemExit("blueprint_string.py: the result carries no entities")
    blueprint: Dict[str, Any] = {
        "item": "blueprint",
        "version": version,
        "label": label,
        "entities": entities,
    }
    #An icon is what the blueprint shows in inventory. Pick the machines actually placed, so the icon says
    #what the factory makes rather than defaulting to nothing.
    icons = []
    for entity in entities:
        name = entity["name"]
        if entity.get("recipe") and all(icon["signal"]["name"] != name for icon in icons):
            icons.append({"signal": {"type": "item", "name": name}, "index": len(icons) + 1})
        if len(icons) == 4:
            break
    if icons:
        blueprint["icons"] = icons
    wires = resolve_wires(result, entities, allow_pole_autoconnect)
    if wires:
        blueprint["wires"] = wires
    encoded = json.dumps({"blueprint": blueprint}, separators=(",", ":"))
    return "0" + base64.b64encode(zlib.compress(encoded.encode("utf-8"), 9)).decode("ascii")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="JSON printed by tests/golden/generate.lua")
    parser.add_argument("-o", "--output", help="write the string here instead of stdout")
    parser.add_argument("--label", default="Recursive Resource Calculator", help="blueprint label")
    parser.add_argument("--allow-pole-autoconnect", action="store_true",
                        help="omit pole-to-pole copper wires that carry the offline placeholder connector, "
                             "instead of refusing; poles reconnect themselves when the blueprint is built")
    args = parser.parse_args(argv)

    payload = json.loads(Path(args.input).read_text())
    if payload.get("ok") is not True:
        raise SystemExit(f"blueprint_string.py: the generator did not deliver: ok={payload.get('ok')!r}")
    string = build(payload.get("result") or {}, args.label,
                   allow_pole_autoconnect=args.allow_pole_autoconnect)
    if args.output:
        Path(args.output).write_text(string + "\n")
    else:
        sys.stdout.write(string + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
