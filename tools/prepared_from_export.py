#!/usr/bin/env python3
"""Turn a debug export into a PreparedInput the offline generator can run.

Why this exists. The generator needs a PreparedInput, and the mod only writes one when the player presses
Generate. A capture-only export carries the sheet, the selection and a solved calculation, but no
`generation_attempt`, so `tests/golden/add_case` writes no `prepared_input.json` and nothing can be generated
from it offline.

A second gap is older and larger. Build 1.1.53 captures crafting-machine prototypes only -- measured on
`red_science_1s.txt`, 2026-09-21: 24 entities, none of them a belt, pipe, inserter, pole or roboport. The
generator needs those infrastructure facts, and rule 26.3 says an inserter's cells come from captured
offsets, never from a convention. So this tool supplies them from a NAMED, VERSIONED table of vanilla 2.0.77
values and marks the result accordingly.

**The result is a development input and can never certify anything.** It carries
`source_kind = "reconstructed"` and `provenance.reconstructed_facts` listing exactly which facts did not come
from the player's game. Contract 26.7 requires certification to read captured facts; a reconstruction is for
exercising producers while a complete capture is unavailable, and for nothing else.

usage: prepared_from_export.py <export.txt|export.json> -o prepared_input.json [--surface NAME]
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
import zlib
from pathlib import Path
from typing import Any, Dict

#Vanilla Factorio 2.0.77 infrastructure facts, from the pinned base prototypes. Each is a fact about the
#UNMODDED game; a modded save can disagree, which is exactly why the result is marked reconstructed.
VANILLA_2_0_77 = {
    "belt": {
        "belt": "transport-belt", "splitter": "splitter", "underground": "underground-belt",
        "quality": "normal", "items_per_second": 15, "lane_items_per_second": 7.5,
        "underground_max_distance": 5,
    },
    "pipe": {
        "pipe": "pipe", "underground": "pipe-to-ground", "quality": "normal",
        "throughput_per_second": 1200, "underground_max_distance": 10,
    },
    "inserter": {
        #A base inserter reaches BEHIND itself to pick up and drops in the direction it faces, so in the north
        #frame the pickup offset is +y and the drop offset is -y. These are the two facts the stored
        #player-am2-chain capture carries as EMPTY tables, which is why every inserter in it rejects with
        #"captured inserter offsets are missing".
        "name": "inserter", "quality": "normal", "items_per_second": 0.83,
        "pickup_offset": {"x": 0, "y": 1},
        "drop_offset": {"x": 0, "y": -1},
        "drop_position": {"x": 0, "y": -1},
    },
    "pole": {
        "name": "medium-electric-pole", "quality": "normal",
        "supply_w": 7, "supply_h": 7, "wire_reach": 9,
    },
    "roboport": {
        "name": "roboport", "quality": "normal",
        "logistic_radius": 50, "construction_radius": 55,
    },
}

DEFAULT_SETTINGS = {
    "belt": {"name": "transport-belt", "quality": "normal", "splitter": "splitter",
             "underground": "underground-belt"},
    "pipe": {"name": "pipe", "quality": "normal"},
    "underground_pipe": {"name": "pipe-to-ground", "quality": "normal"},
    "inserter": {"name": "inserter", "quality": "normal"},
    "pole": {"name": "medium-electric-pole", "quality": "normal"},
    "roboport": {"name": "roboport", "quality": "normal"},
    "input_edge": "left",
    "output_edge": "top",
}


def decode_sentinels(value: Any) -> Any:
    """Turn the export's explicit-empty-list sentinel back into a list.

    `logic/export_payload.lua:100` writes `rrc_empty_list = true` when a list is empty, so a JSON round trip
    keeps "empty LIST" distinct from "empty map". Nothing on the read side undid it, and the generator died
    with `preflight.lua:422: attempt to index local 'group' (a boolean value)` -- the boolean being the
    sentinel's own `true`, reached by iterating the marker table as if it held beacon groups.
    """
    if isinstance(value, dict):
        if value.get("rrc_empty_list") is True and len(value) == 1:
            return []
        return {key: decode_sentinels(item) for key, item in value.items()}
    if isinstance(value, list):
        return [decode_sentinels(item) for item in value]
    return value


def read_export(path: Path) -> Dict[str, Any]:
    text = path.read_text()
    stripped = text.strip()
    if stripped.startswith("{"):
        return json.loads(stripped)
    return json.loads(zlib.decompress(base64.b64decode("".join(text.split()))))


def build(export: Dict[str, Any], surface: str) -> Dict[str, Any]:
    sheet = export.get("sheet") or {}
    calculation = export.get("calculation") or {}
    environment = export.get("environment") or {}
    prototypes = export.get("prototypes") or {}

    if calculation.get("status") != "ok":
        raise SystemExit(f"prepared_from_export.py: the calculation did not solve: {calculation.get('status')!r}")

    reconstructed = []
    catalog: Dict[str, Any] = {}
    #Copy the infrastructure keys too, or a build that DOES capture them has its real facts silently replaced
    #by the vanilla table below -- the exact substitution contract 26.7 forbids. Caught by PE9, not by review.
    for key in ("entity", "item", "fluid", "module", "recipe", "beacon", "quality",
                "belt", "pipe", "inserter", "pole", "roboport"):
        if key in prototypes:
            catalog[key] = prototypes[key]
    for key, facts in VANILLA_2_0_77.items():
        if key not in catalog:
            catalog[key] = dict(facts)
            reconstructed.append(f"catalog.{key}")

    #The solver result the generator reads is the calculation the mod already solved.
    solver_result = {k: calculation[k] for k in
                     ("columns", "product_parts", "reasons_by_column", "recipe_rates", "solved_rates",
                      "status", "unsolved_rates") if k in calculation}

    revisions = sheet.get("revisions") or {}
    prepared = {
        "schema_version": 1,
        "source_kind": "reconstructed",
        "source_export": f"debug-export/{sheet.get('sheet_id') or 'sheet'}",
        "surface": surface,
        "force": ((environment.get("force") or {}).get("name")) or "player",
        "options": sheet.get("options") or {},
        "revisions": revisions,
        "settings": DEFAULT_SETTINGS,
        "snapshot": sheet,
        "solver_result": solver_result,
        "catalog": catalog,
        "provenance": {
            "mod_version": export.get("rrc_version"),
            "factorio_branch": (environment.get("base_game_version") or "").rsplit(".", 1)[0] or "2.0",
            "base_game_version": environment.get("base_game_version"),
            "active_mod_count": len(environment.get("active_mods") or {}),
            "outcome": "reconstructed",
            "revisions": revisions,
            #Named so no reader has to guess which facts the player's game did not supply.
            "reconstructed_facts": reconstructed,
            "reconstructed_from": "vanilla Factorio 2.0.77 base prototypes",
            "certifiable": False,
        },
    }
    return prepared


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("export", help="debug export string file, or decoded JSON")
    parser.add_argument("-o", "--output", required=True, help="where to write the PreparedInput")
    parser.add_argument("--surface", default="nauvis", help="surface name to record")
    args = parser.parse_args(argv)

    export = decode_sentinels(read_export(Path(args.export)))
    prepared = build(export, args.surface)
    Path(args.output).write_text(json.dumps(prepared, indent=1, sort_keys=True) + "\n")

    facts = prepared["provenance"]["reconstructed_facts"]
    sys.stderr.write(f"prepared_from_export.py: wrote {args.output}\n")
    sys.stderr.write(f"  source_kind = reconstructed, certifiable = False\n")
    if facts:
        sys.stderr.write(f"  facts NOT from the player's game: {', '.join(facts)}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
