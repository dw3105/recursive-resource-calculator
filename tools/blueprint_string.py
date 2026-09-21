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
    Those stand in for real `defines.wire_connector_id` values that only exist at runtime, so they are
    dropped: poles connect by proximity when the blueprint is built, and an invented id is worse than none.

usage: blueprint_string.py <generate-output.json> [-o out.txt] [--label TEXT]
"""

from __future__ import annotations

import argparse
import base64
import json
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


def build(result: Dict[str, Any], label: str, version: int = DEFAULT_VERSION) -> str:
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
    encoded = json.dumps({"blueprint": blueprint}, separators=(",", ":"))
    return "0" + base64.b64encode(zlib.compress(encoded.encode("utf-8"), 9)).decode("ascii")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="JSON printed by tests/golden/generate.lua")
    parser.add_argument("-o", "--output", help="write the string here instead of stdout")
    parser.add_argument("--label", default="Recursive Resource Calculator", help="blueprint label")
    args = parser.parse_args(argv)

    payload = json.loads(Path(args.input).read_text())
    if payload.get("ok") is not True:
        raise SystemExit(f"blueprint_string.py: the generator did not deliver: ok={payload.get('ok')!r}")
    string = build(payload.get("result") or {}, args.label)
    if args.output:
        Path(args.output).write_text(string + "\n")
    else:
        sys.stdout.write(string + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
