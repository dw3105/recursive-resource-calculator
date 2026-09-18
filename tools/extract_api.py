#!/usr/bin/env python3
"""Extract the member surface RRC mocks from a pinned Factorio runtime-api.json."""
import json, sys

CLASSES = ["LuaEntityPrototype","LuaItemPrototype","LuaRecipePrototype","LuaFluidPrototype","LuaQualityPrototype",
           "LuaModuleCategoryPrototype","LuaFluidBoxPrototype","LuaHelpers","LuaGuiElement","LuaItemStack",
           "LuaItemCommon","LuaPlayer","LuaControl","LuaForce","LuaSurface","LuaGameScript","LuaBootstrap",
           "LuaBurnerPrototype","LuaElectricEnergySourcePrototype","LuaInventory","LuaRecipeCategoryPrototype"]
CONCEPTS = ["PipeConnectionDefinition","BlueprintEntity","BlueprintWire","BlueprintInsertPlan",
            "ItemInventoryPositions","BlueprintItemIDAndQualityIDPair","MapPosition","Vector","PipeConnectionType",
            "FluidFlowDirection"]

def members(cls_by_name, name, seen=None):
    """Attributes and methods of a class, with its parent chain resolved."""
    seen = seen or set()
    if name in seen or name not in cls_by_name:
        return set(), set()
    seen.add(name)
    cls = cls_by_name[name]
    attrs = {a["name"] for a in cls.get("attributes", [])}
    meths = {m["name"] for m in cls.get("methods", [])}
    parent = cls.get("parent")
    if parent:
        pa, pm = members(cls_by_name, parent, seen)
        attrs |= pa
        meths |= pm
    return attrs, meths

def main(src, dest):
    api = json.load(open(src))
    cls_by_name = {c["name"]: c for c in api["classes"]}
    con_by_name = {c["name"]: c for c in api["concepts"]}
    out = {"application_version": api["application_version"], "api_version": api["api_version"], "classes": {}, "concepts": {}, "defines": {}}
    for name in CLASSES:
        if name not in cls_by_name:
            continue
        attrs, meths = members(cls_by_name, name)
        out["classes"][name] = {"parent": cls_by_name[name].get("parent"),
                                "attributes": sorted(attrs), "methods": sorted(meths)}
    for name in CONCEPTS:
        concept = con_by_name.get(name)
        if concept is None:
            continue
        kind = concept["type"]
        if isinstance(kind, dict) and kind.get("complex_type") in ("table", "struct"):
            out["concepts"][name] = {"kind": kind["complex_type"],
                                     "parameters": sorted(p["name"] for p in kind["parameters"]),
                                     "optional": sorted(p["name"] for p in kind["parameters"] if p.get("optional"))}
        else:
            out["concepts"][name] = {"kind": "other", "raw": kind if isinstance(kind, str) else kind.get("complex_type")}
    def walk(defines, prefix=""):
        for d in defines:
            path = prefix + d["name"]
            if d.get("values"):
                out["defines"][path] = sorted(v["name"] for v in d["values"])
            walk(d.get("subkeys") or [], path + ".")
    walk(api["defines"])
    json.dump(out, open(dest, "w"), indent=1, sort_keys=True)
    print(f"{dest}: {api['application_version']}, {len(out['classes'])} classes, {len(out['concepts'])} concepts")

main(sys.argv[1], sys.argv[2])
