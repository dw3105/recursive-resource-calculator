#!/usr/bin/env python3
"""Run the release-only golden comparator without modifying a case baseline.

The runner is intentionally a file comparator: an engine harness may place a
generated blueprint/result in a case's ``actual`` file, or pass one with
``--candidate``.  It never invokes Factorio implicitly and never accepts a
candidate merely because the generator produced it.

``run accept CASE`` is provided as a convenience for this lane's explicit
accept operation.  A normal invocation has no code path that writes an
expectation.
"""

from __future__ import annotations

import argparse
import base64
import copy
import difflib
import hashlib
import json
import math
import os
import re
import sys
import time
import zlib
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple


class GoldenError(Exception):
    pass


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise GoldenError(f"cannot read {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise GoldenError(f"{path} is not valid JSON: {exc}") from exc


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")


def stable_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def pretty_json(value: Any) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + "\n"


def finite(value: Any, fallback: Optional[float] = None) -> Optional[float]:
    if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value):
        return value
    return fallback


def deep_copy(value: Any) -> Any:
    return copy.deepcopy(value)


def list_or_map(value: Any) -> List[Any]:
    if not isinstance(value, (list, dict)):
        return []
    if isinstance(value, list):
        return list(value)
    return [value[key] for key in sorted(value, key=lambda item: str(item)) if isinstance(value[key], dict)]


def quality_name(value: Any) -> str:
    if isinstance(value, dict):
        value = value.get("name", value.get("id"))
    return value if isinstance(value, str) and value else "normal"


def position(value: Any) -> Optional[Dict[str, Any]]:
    if not isinstance(value, dict):
        return None
    x = finite(value.get("x"), None)
    y = finite(value.get("y"), None)
    if x is not None and y is not None:
        return {"x": x, "y": y}
    pair_x = finite(value.get(0, value.get("1")), None)
    pair_y = finite(value.get(1, value.get("2")), None)
    if pair_x is not None and pair_y is not None:
        return {"x": pair_x, "y": pair_y}
    return None


def entity_position(entity: Mapping[str, Any]) -> Dict[str, Any]:
    result = position(entity.get("position"))
    if result:
        return result
    x = finite(entity.get("x"), None)
    y = finite(entity.get("y"), None)
    if x is None or y is None:
        return {"x": 0, "y": 0}
    width = finite(entity.get("w", entity.get("width")), None)
    height = finite(entity.get("h", entity.get("height")), None)
    if width is not None and height is not None:
        return {"x": x + width / 2, "y": y + height / 2}
    return {"x": x, "y": y}


def entity_id(entity: Any, fallback: Any) -> Any:
    if not isinstance(entity, dict):
        return fallback
    for key in ("id", "entity_id", "_id", "entity_number"):
        if entity.get(key) is not None:
            return entity[key]
    return fallback


def id_text(entity: Mapping[str, Any], fallback: Any) -> str:
    return str(entity_id(entity, fallback))


def candidate_entities(root: Mapping[str, Any]) -> List[Dict[str, Any]]:
    source_root: Mapping[str, Any] = root.get("candidate", root) if isinstance(root, dict) else {}
    blueprint = source_root.get("blueprint") if isinstance(source_root.get("blueprint"), dict) else source_root
    result: List[Dict[str, Any]] = []
    seen = set()

    def append(source: Any) -> None:
        for index, raw in enumerate(list_or_map(source), 1):
            if not isinstance(raw, dict):
                continue
            ident = entity_id(raw, index)
            key = (type(ident).__name__, str(ident))
            if key not in seen:
                seen.add(key)
                result.append(raw)

    for key in ("entities",):
        append(blueprint.get(key))
    for key in ("placed_entities",):
        append(source_root.get(key))
    for branch in ("layout", "route", "routing", "power", "infrastructure", "result"):
        value = source_root.get(branch)
        if isinstance(value, dict):
            append(value.get("entities"))

    blocks = list_or_map(source_root.get("blocks"))
    placements: Any = source_root.get("placements")
    if placements is None and isinstance(source_root.get("layout"), dict):
        placements = source_root["layout"].get("placements")
    placements = placements if isinstance(placements, (list, dict)) else {}
    for block in blocks:
        block_id = block.get("id", block.get("block_id")) if isinstance(block, dict) else None
        placement = placements.get(block_id) if isinstance(placements, dict) else None
        if placement is None:
            for possible in list_or_map(placements):
                if possible.get("block_id", possible.get("id")) == block_id:
                    placement = possible
                    break
        placement = placement if isinstance(placement, dict) else {}
        px, py = finite(placement.get("x"), 0), finite(placement.get("y"), 0)
        members = block.get("entities", block.get("members")) if isinstance(block, dict) else None
        for index, raw in enumerate(list_or_map(members), 1):
            if not isinstance(raw, dict):
                continue
            entity = deep_copy(raw)
            entity.setdefault("id", f"m:{block_id or index}:{index}")
            if "position" not in entity:
                x, y = finite(entity.get("x"), None), finite(entity.get("y"), None)
                if x is not None and y is not None:
                    width, height = finite(entity.get("w"), 1), finite(entity.get("h"), 1)
                    entity["position"] = {"x": px + x + width / 2, "y": py + y + height / 2}
            append([entity])
    return result


def order_entities(entities: Sequence[Mapping[str, Any]]) -> Tuple[List[Dict[str, Any]], Dict[Any, int]]:
    ordered = []
    for index, raw in enumerate(entities, 1):
        entity = deep_copy(raw) if isinstance(raw, dict) else {}
        entity["_serialize_index"] = index
        ordered.append(entity)
    ordered.sort(key=lambda item: (
        entity_position(item)["y"], entity_position(item)["x"], id_text(item, item["_serialize_index"]),
        item["_serialize_index"],
    ))
    references: Dict[Any, int] = {}

    def add_reference(value: Any, number: int) -> None:
        if value is None:
            return
        try:
            references[value] = number
        except TypeError:
            pass
        references[str(value)] = number

    for number, entity in enumerate(ordered, 1):
        old_number = entity.get("entity_number")
        entity["entity_number"] = number
        for key in ("id", "entity_id", "_id", "_serialize_index", "entity_number"):
            add_reference(old_number if key == "entity_number" else entity.get(key), number)
        # The new number is intentionally also a reference, matching Serialize.lua.
        add_reference(number, number)
    for entity in ordered:
        entity.pop("_serialize_index", None)
    return ordered, references


def remap(references: Mapping[Any, int], value: Any) -> Any:
    if value is None:
        return None
    try:
        if value in references:
            return references[value]
    except TypeError:
        pass
    return references.get(str(value), value)


def map_position(value: Any) -> Optional[Dict[str, Any]]:
    return position(value)


def normalized_module(module: Any) -> Optional[Dict[str, Any]]:
    ident = module
    quality = "normal"
    count = 1
    slot = None
    if isinstance(module, dict):
        ident = module.get("name", module.get("id", module.get("prototype")))
        if isinstance(ident, dict):
            quality = quality_name(ident.get("quality"))
            ident = ident.get("name", ident.get("id"))
        else:
            quality = quality_name(module.get("quality"))
        count = max(1, int(finite(module.get("count"), 1)))
        slot = module.get("slot", module.get("index"))
    if not isinstance(ident, str) or not ident:
        return None
    return {"name": ident, "quality": quality, "count": count, "slot": slot}


def module_inventory(entity: Mapping[str, Any]) -> Any:
    value = entity.get("module_inventory", entity.get("inventory"))
    if isinstance(value, dict):
        value = value.get("index", value.get("inventory"))
    value = finite(value, None)
    if value is not None:
        return value
    if entity.get("type") == "beacon" or entity.get("kind") == "beacon" or entity.get("name") == "beacon":
        return 1
    return 4


def make_items(entity: Mapping[str, Any]) -> Optional[List[Any]]:
    items = entity.get("items")
    if isinstance(items, list) and items and all(isinstance(item, dict) and isinstance(item.get("id"), dict)
                                                 and isinstance(item.get("items"), dict) for item in items):
        result = deep_copy(items)
        for item in result:
            quality = quality_name(item["id"].get("quality"))
            if quality == "normal":
                item["id"].pop("quality", None)
            slots = item["items"].get("in_inventory")
            if isinstance(slots, list):
                for slot in slots:
                    if isinstance(slot, dict):
                        slot["inventory"] = finite(slot.get("inventory"), 1)
                        slot["stack"] = finite(slot.get("stack"), 0)
        return result
    source = entity.get("modules", entity.get("module_requests", entity.get("module_set")))
    if source is None and isinstance(entity.get("setup"), dict):
        source = entity["setup"].get("modules")
    modules: List[Dict[str, Any]] = []
    next_slot = 0
    for raw in list_or_map(source):
        module = normalized_module(raw)
        if not module:
            continue
        first_slot = module.get("slot")
        for count in range(module["count"]):
            slot = first_slot + count if first_slot is not None else next_slot
            modules.append({"name": module["name"], "quality": module["quality"],
                            "inventory": module_inventory(entity), "stack": slot})
            if first_slot is None:
                next_slot += 1
        if first_slot is not None:
            next_slot = max(next_slot, first_slot + module["count"])
    if not modules:
        return None
    result: List[Any] = []
    for module in modules:
        previous = result[-1] if result else None
        slots = previous.get("items", {}).get("in_inventory", []) if previous else []
        if (previous and previous["id"].get("name") == module["name"]
                and quality_name(previous["id"].get("quality")) == module["quality"]
                and slots and slots[-1].get("inventory") == module["inventory"]):
            slots.append({"inventory": module["inventory"], "stack": module["stack"]})
        else:
            ident = {"name": module["name"]}
            if module["quality"] != "normal":
                ident["quality"] = module["quality"]
            result.append({"id": ident, "items": {"in_inventory": [
                {"inventory": module["inventory"], "stack": module["stack"]}
            ]}})
    return result


def wire_tuple(edge: Any) -> Optional[List[Any]]:
    if not isinstance(edge, dict) and not isinstance(edge, list):
        return None
    if isinstance(edge, dict):
        if "a_id" in edge or "b_id" in edge:
            return [edge.get("a_id", edge.get("a")), edge.get("a_connector", edge.get("a_connection")),
                    edge.get("b_id", edge.get("b")), edge.get("b_connector", edge.get("b_connection"))]
        return None
    if len(edge) >= 2 and isinstance(edge[0], (dict, list)) and isinstance(edge[1], (dict, list)):
        def endpoint(value: Any) -> List[Any]:
            if isinstance(value, dict):
                return [value.get("entity_id", value.get("id")), value.get("connector_id", value.get("connector"))]
            return [value[0] if value else None, value[1] if len(value) > 1 else None]
        left, right = endpoint(edge[0]), endpoint(edge[1])
        return [left[0], left[1], right[0], right[1]]
    if len(edge) >= 3:
        return [edge[0], edge[1], edge[2], edge[3] if len(edge) > 3 else None]
    return None


def normalize_wires(source: Any, references: Mapping[Any, int]) -> List[List[Any]]:
    result: List[List[Any]] = []
    seen = set()
    for raw in list_or_map(source):
        wire = wire_tuple(raw)
        if not wire:
            continue
        wire[0], wire[2] = remap(references, wire[0]), remap(references, wire[2])
        key = stable_json(wire)
        if key not in seen:
            seen.add(key)
            result.append(wire)
    result.sort(key=lambda wire: tuple(str(value) for value in wire))
    return result


def serialize_entity(entity: Mapping[str, Any], references: Mapping[Any, int]) -> Dict[str, Any]:
    result: Dict[str, Any] = {"entity_number": entity.get("entity_number"),
                              "name": entity.get("name", entity.get("prototype")),
                              "position": entity_position(entity)}
    direction = entity.get("direction", entity.get("dir"))
    if direction is not None:
        result["direction"] = direction
    quality = quality_name(entity.get("quality"))
    if quality != "normal":
        result["quality"] = quality
    for field in ("recipe", "recipe_quality", "type", "mirror", "tags", "request_filters", "burner_fuel_inventory"):
        if field in entity and entity[field] is not None:
            result[field] = deep_copy(entity[field])
    if result.get("recipe") is not None and result.get("recipe_quality") is None:
        result["recipe_quality"] = "normal"
    if entity.get("drop_position") is not None:
        result["drop_position"] = map_position(entity.get("drop_position"))
    items = make_items(entity)
    if items is not None:
        result["items"] = items
    for field in ("ug_pair_id", "partner_id", "port_id"):
        if field in entity and entity[field] is not None:
            result[field] = remap(references, entity[field])
    if entity.get("wires") is not None:
        result["wires"] = normalize_wires(entity["wires"], references)
    return result


def canonical(value: Any) -> Dict[str, Any]:
    if not isinstance(value, dict):
        raise GoldenError("blueprint result is not an object")
    wrapped = isinstance(value.get("blueprint"), dict) and "entities" not in value
    source = value["blueprint"] if wrapped else value
    ordered, references = order_entities(candidate_entities(source))
    points = [entity_position(entity) for entity in ordered]
    minimum_x = min((point["x"] for point in points), default=0)
    minimum_y = min((point["y"] for point in points), default=0)
    entities = []
    for entity in ordered:
        item = serialize_entity(entity, references)
        item["position"] = {"x": item["position"]["x"] - minimum_x,
                             "y": item["position"]["y"] - minimum_y}
        entities.append(item)
    result: Dict[str, Any] = {"entities": entities}
    for field in ("label", "icons", "description"):
        if field in source and source[field] is not None:
            result[field] = deep_copy(source[field])
    wires = normalize_wires(source.get("wires"), references)
    if wires:
        result["wires"] = wires
    return {"blueprint": result} if wrapped else result


def decode_blueprint_string(value: str) -> Dict[str, Any]:
    text = value.strip()
    if text.startswith("{"):
        try:
            decoded = json.loads(text)
        except json.JSONDecodeError as exc:
            raise GoldenError(f"blueprint JSON is invalid: {exc}") from exc
        return decoded
    if text.startswith("0"):
        text = text[1:]
    try:
        raw = base64.b64decode(text, validate=True)
        return json.loads(zlib.decompress(raw).decode("utf-8"))
    except (ValueError, zlib.error, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise GoldenError(f"blueprint string could not be decoded: {exc}") from exc


def load_value(path: Path) -> Tuple[Any, Optional[str]]:
    if path.suffix.lower() in (".txt", ".blueprint", ".bp"):
        text = path.read_text(encoding="utf-8")
        return decode_blueprint_string(text), text.strip()
    value = read_json(path)
    if isinstance(value, str):
        return decode_blueprint_string(value), value
    if isinstance(value, dict):
        for key in ("blueprint_string", "blueprintString", "string"):
            if isinstance(value.get(key), str):
                return decode_blueprint_string(value[key]), value[key]
        if isinstance(value.get("canonical"), dict):
            return value["canonical"], None
        if isinstance(value.get("blueprint"), dict) and "entities" in value["blueprint"]:
            return value, None
        if "entities" in value:
            return value, None
    return value, None


def path_from_manifest(case: Path, manifest: Mapping[str, Any], keys: Sequence[str]) -> Optional[Path]:
    for key in keys:
        value = manifest.get(key)
        if isinstance(value, str):
            path = case / value
            if path.exists():
                return path
        if isinstance(value, dict):
            for nested in ("path", "file", "blueprint", "canonical"):
                if isinstance(value.get(nested), str) and (case / value[nested]).exists():
                    return case / value[nested]
    return None


def first_existing(case: Path, names: Sequence[str]) -> Optional[Path]:
    for name in names:
        path = case / name
        if path.exists() and path.is_file():
            return path
    return None


def manifest_path(case: Path) -> Path:
    path = first_existing(case, ("manifest.json", "case.json", "manifest.lua.json"))
    if not path:
        raise GoldenError(f"{case} has no manifest.json")
    return path


def expected_value(case: Path, manifest: Mapping[str, Any]) -> Tuple[Any, Optional[str], Optional[Path]]:
    path = path_from_manifest(case, manifest, ("expected", "expected_result", "expected_blueprint"))
    path = path or first_existing(case, ("expected_canonical.json", "expected.json", "expected_blueprint.txt",
                                          "expected.blueprint", "blueprint.txt"))
    if path:
        return (*load_value(path)[:2], path)
    inline = manifest.get("expected_result", manifest.get("expected"))
    if isinstance(inline, dict):
        if isinstance(inline.get("blueprint_string"), str):
            return decode_blueprint_string(inline["blueprint_string"]), inline["blueprint_string"], None
        return inline, None, None
    # Rejection cases may keep their reviewed reason-code set in the manifest;
    # requiring a dummy blueprint file would make the negative form needlessly
    # different from the production form.
    declared_codes = manifest.get("reason_codes", manifest.get("expected_reason_codes"))
    if declared_codes is not None:
        return {"reason_codes": declared_codes}, None, None
    declared_outcome = manifest.get("expected_outcome", manifest.get("outcome"))
    if isinstance(declared_outcome, Mapping) and reason_codes(declared_outcome):
        return {"reason_codes": reason_codes(declared_outcome)}, None, None
    raise GoldenError(f"{case} has no expected result")


def actual_path(case: Path, manifest: Mapping[str, Any], override: Optional[Path]) -> Optional[Path]:
    if override:
        return override
    return path_from_manifest(case, manifest, ("actual", "candidate", "generated", "output")) or first_existing(
        case, ("actual_blueprint.txt", "actual.blueprint", "actual.json", "candidate.blueprint", "candidate.json",
               "generated.blueprint", "generated.json", "output.json", "result.json")
    )


def reason_codes(value: Any) -> List[str]:
    result: List[str] = []

    def add(item: Any) -> None:
        if isinstance(item, str):
            result.append(item)
        elif isinstance(item, dict):
            add(item.get("code", item.get("reason_code", item.get("reason"))))

    if isinstance(value, dict):
        for key in ("reason_codes", "reasons", "diagnostics", "errors"):
            if key in value:
                return reason_codes(value[key])
        for key, item in value.items():
            if item and isinstance(key, str) and key.startswith("BP_"):
                result.append(key)
            elif isinstance(item, dict):
                add(item)
    elif isinstance(value, list):
        for item in value:
            add(item)
    else:
        add(value)
    return sorted(set(result))


def expected_rejection(manifest: Mapping[str, Any], expected: Any) -> Tuple[bool, List[str]]:
    outcome = manifest.get("expected_outcome", manifest.get("outcome", manifest.get("expected")))
    codes = reason_codes(manifest.get("reason_codes", manifest.get("expected_reason_codes")))
    if isinstance(outcome, dict):
        codes = codes or reason_codes(outcome)
        outcome = outcome.get("state", outcome.get("result", outcome.get("outcome")))
    if isinstance(expected, dict):
        codes = codes or reason_codes(expected)
    negative = bool(codes) or str(outcome).lower() in {"failure", "failed", "rejection", "rejected", "negative"}
    return negative, codes


def case_branch(manifest: Mapping[str, Any]) -> Optional[str]:
    """Return the declared Factorio branch, if this case has one."""
    for key in ("factorio_branch", "branch"):
        if isinstance(manifest.get(key), str):
            return manifest[key]
    versions = manifest.get("versions")
    if isinstance(versions, Mapping):
        for key in ("factorio_branch", "factorio", "branch"):
            if isinstance(versions.get(key), str):
                return versions[key]
    return None


def independent_checks(manifest: Mapping[str, Any], value: Any) -> List[str]:
    failures: List[str] = []
    blueprint = value.get("blueprint", value) if isinstance(value, dict) else {}
    entities = blueprint.get("entities") if isinstance(blueprint, dict) else None
    if entities is not None:
        if not isinstance(entities, list):
            failures.append("entities is not an array")
            entities = []
        numbers = [entity.get("entity_number") for entity in entities if isinstance(entity, dict)]
        if any(number is None for number in numbers):
            failures.append("an entity has no entity_number")
        if len(numbers) != len(set(str(number) for number in numbers)):
            failures.append("entity numbers are not unique")
        ids = set(numbers)
        for index, entity in enumerate(entities, 1):
            if not isinstance(entity, dict) or not isinstance(entity.get("name"), str):
                failures.append(f"entity {index} has no name")
                continue
            point = entity.get("position")
            if not isinstance(point, dict) or finite(point.get("x")) is None or finite(point.get("y")) is None:
                failures.append(f"entity {index} has an invalid position")
            for field in ("ug_pair_id", "partner_id", "port_id"):
                if field in entity and entity[field] not in ids:
                    failures.append(f"entity {index} has a dangling {field}")
        for index, wire in enumerate(blueprint.get("wires", []), 1):
            if not isinstance(wire, list) or len(wire) != 4 or wire[0] not in ids or wire[2] not in ids:
                failures.append(f"wire {index} has a dangling endpoint")

    assertions = manifest.get("independent_assertions", manifest.get("assertions", manifest.get("invariants", {})))
    if not isinstance(assertions, dict):
        assertions = {}
    counts: Dict[str, int] = {}
    for entity in entities or []:
        if isinstance(entity, dict) and isinstance(entity.get("name"), str):
            counts[entity["name"]] = counts.get(entity["name"], 0) + 1
    for key in ("entity_counts", "required_entity_counts", "minimum_entity_counts"):
        expected_counts = assertions.get(key, manifest.get(key))
        if isinstance(expected_counts, dict):
            for name, expected_count in expected_counts.items():
                if key == "minimum_entity_counts":
                    ok = counts.get(name, 0) >= int(expected_count)
                else:
                    ok = counts.get(name, 0) == int(expected_count)
                if not ok:
                    failures.append(f"entity count {name}: expected {expected_count}, got {counts.get(name, 0)}")
    required = assertions.get("required_entities", manifest.get("required_entities"))
    if isinstance(required, list):
        for name in required:
            if name not in counts:
                failures.append(f"required entity missing: {name}")
    return failures


def compare_case(case: Path, manifest: Mapping[str, Any], candidate_override: Optional[Path], artifact_root: Path) -> Tuple[bool, Dict[str, Any]]:
    started = time.monotonic()
    expected_raw, expected_string, expected_path = expected_value(case, manifest)
    actual_file = actual_path(case, manifest, candidate_override)
    if not actual_file:
        raise GoldenError(f"{case} has no generated candidate; provide actual.json or --candidate")
    actual_raw, actual_string = load_value(actual_file)
    negative, expected_codes = expected_rejection(manifest, expected_raw)
    actual_codes = reason_codes(actual_raw)
    # A rejection has no blueprint to validate. Its independent contract is the
    # stable reason-code set, never entity geometry or message text.
    validation = [] if negative else independent_checks(manifest, actual_raw)
    expected_canonical = None
    actual_canonical = None
    equal = False
    if negative:
        equal = actual_codes == sorted(set(expected_codes))
        if not equal:
            validation.append(f"reason codes differ: expected {sorted(set(expected_codes))}, got {actual_codes}")
    else:
        expected_canonical = canonical(expected_raw)
        actual_canonical = canonical(actual_raw)
        equal = expected_canonical == actual_canonical
        if not equal:
            validation.append("canonical blueprint differs")
    ok = equal and not validation
    elapsed = time.monotonic() - started
    details = {"case": case.name, "ok": ok, "negative": negative, "expected_path": str(expected_path) if expected_path else None,
               "actual_path": str(actual_file), "expected_reason_codes": sorted(set(expected_codes)),
               "actual_reason_codes": actual_codes, "validation_failures": validation, "elapsed_seconds": elapsed}
    if not ok:
        failure_dir = artifact_root / case.name
        failure_dir.mkdir(parents=True, exist_ok=True)
        if expected_canonical is not None:
            write_json(failure_dir / "expected_canonical.json", expected_canonical)
        if actual_canonical is not None:
            write_json(failure_dir / "actual_canonical.json", actual_canonical)
        expected_for_diff = expected_canonical if expected_canonical is not None else {"reason_codes": sorted(set(expected_codes))}
        actual_for_diff = actual_canonical if actual_canonical is not None else {"reason_codes": actual_codes}
        diff = difflib.unified_diff(pretty_json(expected_for_diff).splitlines(True), pretty_json(actual_for_diff).splitlines(True),
                                    fromfile="expected", tofile="actual")
        (failure_dir / "diff.txt").write_text("".join(diff), encoding="utf-8")
        if actual_string:
            (failure_dir / "blueprint_string.txt").write_text(actual_string + "\n", encoding="utf-8")
        inputs = {}
        for name in ("inputs.json", "input.json", "snapshot.json", "export.json", "options.json"):
            source = case / name
            if source.exists():
                inputs[name] = read_json(source)
        write_json(failure_dir / "inputs.json", inputs)
        write_json(failure_dir / "validation.json", {"failures": validation})
        write_json(failure_dir / "timings.json", {"elapsed_seconds": elapsed})
    return ok, details


def discover(root: Path, selected: Sequence[str]) -> List[Path]:
    if root.is_file():
        return [root.parent]
    if root.is_dir() and any((root / name).exists() for name in ("manifest.json", "case.json")):
        return [root]
    if selected:
        result = []
        for item in selected:
            path = Path(item)
            if not path.is_absolute():
                path = root / item
            result.append(path if path.is_dir() else path.parent)
        return result
    result = []
    for path in sorted(root.iterdir()) if root.exists() else []:
        if path.is_dir() and any((path / name).exists() for name in ("manifest.json", "case.json")):
            result.append(path)
    return result


def expected_write_path(case: Path, existing: Optional[Path]) -> Path:
    return existing or case / "expected_canonical.json"


def accept_case(case: Path, manifest: Mapping[str, Any], candidate_override: Optional[Path], artifact_root: Path) -> None:
    expected_raw, _, old_path = expected_value(case, manifest)
    actual_file = actual_path(case, manifest, candidate_override)
    if not actual_file:
        raise GoldenError(f"{case} has no generated candidate")
    actual_raw, _ = load_value(actual_file)
    negative, old_codes = expected_rejection(manifest, expected_raw)
    failures = [] if negative else independent_checks(manifest, actual_raw)
    if failures:
        raise GoldenError("candidate failed independent checks: " + "; ".join(failures))
    if negative:
        new_codes = reason_codes(actual_raw)
        if not new_codes:
            raise GoldenError("a rejection expectation can only accept a candidate with reason codes")
        new_value = {"reason_codes": new_codes}
        old_value = {"reason_codes": sorted(set(old_codes))}
    else:
        new_value = canonical(actual_raw)
        old_value = canonical(expected_raw)
    review = artifact_root / "accept" / case.name
    write_json(review / "old.json", old_value)
    write_json(review / "new.json", new_value)
    diff = difflib.unified_diff(pretty_json(old_value).splitlines(True), pretty_json(new_value).splitlines(True),
                                fromfile="old", tofile="new")
    (review / "diff.txt").write_text("".join(diff), encoding="utf-8")
    write_json(review / "provenance.json", {"case": case.name, "candidate": str(actual_file), "validation_failures": failures})
    target = expected_write_path(case, old_path)
    # Preserve a wrapper manifest if expected.json stores more than the canonical value.
    if target.name == "expected.json":
        original = read_json(target)
        if isinstance(original, dict) and "canonical" in original:
            original["canonical"] = new_value
            write_json(target, original)
        else:
            write_json(target, new_value)
    else:
        write_json(target, new_value)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("paths", nargs="*", help="case root followed by optional case names")
    result.add_argument("--root", "--cases", dest="root", help="case directory")
    result.add_argument("--candidate", help="candidate blueprint/result path for one selected case")
    result.add_argument("--artifacts", help="failure/accept artifact directory")
    result.add_argument("--branch", help="only run cases declared for this Factorio branch")
    return result


def main(argv: Optional[Iterable[str]] = None) -> int:
    raw = list(argv if argv is not None else sys.argv[1:])
    explicit_accept = bool(raw and raw[0] == "accept")
    if explicit_accept:
        raw = raw[1:]
    args = parser().parse_args(raw)
    if args.root:
        root = Path(args.root)
        selected = args.paths
    elif args.paths:
        first = Path(args.paths[0])
        if first.is_dir() and any((first / name).exists() for name in ("manifest.json", "case.json")):
            root = first
            selected = []
        else:
            root = first
            selected = args.paths[1:] if root.is_dir() else args.paths
    else:
        root = Path(__file__).resolve().parent.parent / "cases"
        selected = []
    artifact_root = Path(args.artifacts) if args.artifacts else root.parent / ".golden-failures"
    cases = discover(root, selected)
    if not cases:
        print("golden: no cases")
        return 0
    failures = 0
    processed = 0
    for case in cases:
        try:
            manifest = read_json(manifest_path(case))
            if not isinstance(manifest, dict):
                raise GoldenError("manifest is not an object")
            if args.branch and case_branch(manifest) not in (None, args.branch):
                print(f"SKIP {case.name} (branch {case_branch(manifest)})")
                continue
            processed += 1
            if explicit_accept:
                if len(cases) != 1:
                    raise GoldenError("accept names exactly one case")
                accept_case(case, manifest, Path(args.candidate) if args.candidate else None, artifact_root)
                print(f"ACCEPT {case.name}")
                continue
            ok, details = compare_case(case, manifest, Path(args.candidate) if args.candidate else None, artifact_root)
            print(("PASS" if ok else "FAIL") + " " + case.name)
            if not ok:
                failures += 1
        except GoldenError as exc:
            failures += 1
            print(f"FAIL {case.name}: {exc}", file=sys.stderr)
    if explicit_accept:
        return 0 if failures == 0 else 1
    print(f"golden: {processed - failures} passed, {failures} failed")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
