#!/usr/bin/env python3
"""Extract the pinned Factorio runtime API surface used by RRC."""

import argparse
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen


PINS = (
    {
        "source_url": "https://lua-api.factorio.com/2.0.77/runtime-api.json",
        "destination": Path("docs/api/2.0.77.members.json"),
    },
    {
        "source_url": "https://lua-api.factorio.com/2.1.19/runtime-api.json",
        "destination": Path("docs/api/2.1.19.members.json"),
    },
)

# Keep this list intentionally explicit. It is the union of the classes used
# by the offline harness and by tests/golden/engine/mod; classes absent from a
# branch's pinned description are not invented in that branch's extract.
CLASSES = [
    "LuaBootstrap",
    "LuaBurnerPrototype",
    "LuaControl",
    "LuaElectricEnergySourcePrototype",
    "LuaEntity",
    "LuaEntityPrototype",
    "LuaFluidBox",
    "LuaFluidBoxPrototype",
    "LuaFluidPrototype",
    "LuaForce",
    "LuaGameScript",
    "LuaGuiElement",
    "LuaHelpers",
    "LuaInventory",
    "LuaItemCommon",
    "LuaItemPrototype",
    "LuaItemStack",
    "LuaModuleCategoryPrototype",
    "LuaPlayer",
    "LuaQualityPrototype",
    "LuaRCON",
    "LuaRecipeCategoryPrototype",
    "LuaRecipePrototype",
    "LuaRemote",
    "LuaSurface",
    "LuaTechnology",
]
CONCEPTS = [
    "PipeConnectionDefinition",
    "BlueprintEntity",
    "BlueprintWire",
    "BlueprintInsertPlan",
    "ItemInventoryPositions",
    "BlueprintItemIDAndQualityIDPair",
    "MapPosition",
    "Vector",
    "PipeConnectionType",
    "FluidFlowDirection",
]


def members(cls_by_name, name, seen=None):
    """Return attributes and methods, including the complete parent chain."""
    seen = set() if seen is None else seen
    if name in seen or name not in cls_by_name:
        return set(), set()
    seen.add(name)
    cls = cls_by_name[name]
    attrs = {a["name"] for a in cls.get("attributes", [])}
    meths = {m["name"] for m in cls.get("methods", [])}
    parent = cls.get("parent")
    if parent:
        parent_attrs, parent_methods = members(cls_by_name, parent, seen)
        attrs |= parent_attrs
        meths |= parent_methods
    return attrs, meths


def extract(raw, source_url):
    """Build the deterministic reduced extract from one downloaded document."""
    api = json.loads(raw.decode("utf-8"))
    cls_by_name = {c["name"]: c for c in api["classes"]}
    con_by_name = {c["name"]: c for c in api["concepts"]}
    out = {
        "application_version": api["application_version"],
        "api_version": api["api_version"],
        "classes": {},
        "concepts": {},
        "defines": {},
        "description_sha256": hashlib.sha256(raw).hexdigest(),
        "source_url": source_url,
    }
    for name in CLASSES:
        if name not in cls_by_name:
            continue
        attrs, meths = members(cls_by_name, name)
        out["classes"][name] = {
            "parent": cls_by_name[name].get("parent"),
            "attributes": sorted(attrs),
            "methods": sorted(meths),
        }
    for name in CONCEPTS:
        concept = con_by_name.get(name)
        if concept is None:
            continue
        kind = concept["type"]
        if isinstance(kind, dict) and kind.get("complex_type") in ("table", "struct"):
            parameters = kind["parameters"]
            out["concepts"][name] = {
                "kind": kind["complex_type"],
                "parameters": sorted(p["name"] for p in parameters),
                "optional": sorted(p["name"] for p in parameters if p.get("optional")),
            }
        else:
            out["concepts"][name] = {
                "kind": "other",
                "raw": kind if isinstance(kind, str) else kind.get("complex_type"),
            }

    def walk(defines, prefix=""):
        for item in defines:
            path = prefix + item["name"]
            if item.get("values"):
                out["defines"][path] = sorted(value["name"] for value in item["values"])
            walk(item.get("subkeys") or [], path + ".")

    walk(api["defines"])
    return out


def rendered(out):
    return (json.dumps(out, indent=1, sort_keys=True) + "\n").encode("utf-8")


def download(source_url):
    request = Request(source_url, headers={"User-Agent": "rrc-api-extractor/1"})
    with urlopen(request) as response:
        return response.read()


def write_or_check(destination, content, check):
    if check:
        current = destination.read_bytes() if destination.exists() else None
        if current != content:
            raise SystemExit(f"{destination}: extract is stale; run python3 tools/extract_api.py")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(content)


def process(source_url, destination, check=False, raw=None):
    raw = download(source_url) if raw is None else raw
    out = extract(raw, source_url)
    write_or_check(destination, rendered(out), check)
    print(
        f"{destination}: {out['application_version']}, "
        f"{len(out['classes'])} classes, {len(out['concepts'])} concepts, "
        f"sha256={out['description_sha256']}"
    )


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify both committed extracts are reproducible")
    parser.add_argument("source", nargs="?", help=argparse.SUPPRESS)
    parser.add_argument("destination", nargs="?", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)

    if (args.source is None) != (args.destination is None):
        parser.error("source and destination must be provided together")
    if args.source is not None:
        # Preserve the old two-argument utility for local API fixtures. The
        # canonical lane command below always downloads the two named pins.
        destination = Path(args.destination)
        pin_names = {pin["destination"].name: pin["source_url"] for pin in PINS}
        source_url = pin_names.get(destination.name, "file://" + str(Path(args.source).resolve()))
        process(source_url, destination, check=args.check, raw=Path(args.source).read_bytes())
        return

    for pin in PINS:
        process(pin["source_url"], pin["destination"], check=args.check)


if __name__ == "__main__":
    main()
