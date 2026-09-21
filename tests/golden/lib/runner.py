#!/usr/bin/env python3
"""Run the release-only golden corpus without modifying a baseline.

Captured cases are generated afresh by the Lua bridge over their recorded
PreparedInput.  Cases without a prepared input are explicitly supported as
handwritten canonical fixtures.  A normal invocation never writes an
expectation; ``run accept CASE`` is the explicit replacement path.
"""

from __future__ import annotations

import argparse
import base64
import copy
import difflib
import hashlib
import importlib.util
import json
import math
import os
import re
import shutil
import sys
import subprocess
import tempfile
import time
import zlib
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple


class GoldenError(Exception):
    pass


REPO_ROOT = Path(__file__).resolve().parents[3]
GENERATOR = REPO_ROOT / "tests" / "golden" / "generate.lua"
HISTORICAL_NEGATIVES = REPO_ROOT / "tests" / "golden" / "historical-negatives.json"
SEMANTIC_ASSERTIONS = {
    "conservation", "flow_conservation", "simultaneous_demand", "transport_capacity", "belt_capacity",
    "beacon_coverage", "power_connectivity", "grid_containment", "machine_counts", "capacities",
    "wire_legality", "port_edges", "collisions",
}
FORBIDDEN_GENERATION_OPTIONS = ("search_budget", "max_ops", "max_search_grids", "max_grid_trials")
_SHARED_MATRIX_READER = None


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise GoldenError(f"cannot read {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise GoldenError(f"{path} is not valid JSON: {exc}") from exc


def is_placeholder(value: Any) -> bool:
    """Return true for the deliberately unfilled draft marker add_case writes."""
    if not isinstance(value, dict):
        return False
    if value.get("TODO"):
        return True
    return any(isinstance(item, str) and "TODO" in item.upper() for item in value.values())


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise GoldenError(f"cannot hash {path}: {exc}") from exc
    return digest.hexdigest()


def sha256_value(value: Any) -> str:
    return hashlib.sha256(stable_json(value).encode("utf-8")).hexdigest()


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")


def _shared_matrix_reader():
    """Load the release gate's matrix reader without making tools a package."""
    global _SHARED_MATRIX_READER
    if _SHARED_MATRIX_READER is None:
        path = REPO_ROOT / "tools" / "release_gate.py"
        spec = importlib.util.spec_from_file_location("rrc_golden_release_gate", path)
        if spec is None or spec.loader is None:
            raise GoldenError(f"cannot load shared matrix reader: {path}")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _SHARED_MATRIX_READER = module.load_matrix
    return _SHARED_MATRIX_READER


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


def canonical_numbers(value: Any) -> Any:
    """Match Serialize.lua's JSON boundary: integral numbers are written whole."""
    if isinstance(value, float) and math.isfinite(value) and value.is_integer():
        return int(value)
    if isinstance(value, list):
        return [canonical_numbers(item) for item in value]
    if isinstance(value, dict):
        return {key: canonical_numbers(item) for key, item in value.items()}
    return value


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
    return canonical_numbers({"blueprint": result} if wrapped else result)


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
        value = decode_blueprint_string(text)
        if is_placeholder(value):
            raise GoldenError(f"{path} is an unfilled draft placeholder")
        return value, text.strip()
    value = read_json(path)
    if is_placeholder(value):
        raise GoldenError(f"{path} is an unfilled draft placeholder")
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


def prepared_input_path(case: Path, manifest: Mapping[str, Any]) -> Optional[Path]:
    declared = path_from_manifest(case, manifest, ("prepared_input", "prepared", "input"))
    return declared or first_existing(case, ("prepared_input.json", "prepared.json", "input.json"))


def provenance_path(case: Path) -> Optional[Path]:
    path = case / "provenance.json"
    return path if path.exists() and path.is_file() else None


def case_provenance(case: Path, manifest: Mapping[str, Any], input_path: Optional[Path]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    path = provenance_path(case)
    if path:
        try:
            value = read_json(path)
            if isinstance(value, dict):
                result.update(value)
        except GoldenError as exc:
            result["error"] = str(exc)
    result.setdefault("case_id", manifest.get("case_id", case.name))
    result.setdefault("source_kind", manifest.get("source_kind", "captured" if input_path else "handwritten_fixture"))
    if input_path and input_path.exists():
        result.setdefault("prepared_input", input_path.name)
        result.setdefault("prepared_input_sha256", sha256_file(input_path))
    return result


def lua_interpreter() -> str:
    candidates = [os.environ.get("GOLDEN_LUA"), "lua5.2", "lua"]
    for candidate in candidates:
        if candidate and shutil.which(candidate):
            return candidate
    raise GoldenError("no Lua interpreter found (tried GOLDEN_LUA, lua5.2 and lua)")


def generator_path() -> Path:
    override = os.environ.get("GOLDEN_GENERATOR")
    return Path(override).resolve() if override else GENERATOR


def run_lua_generator(input_path: Path) -> Dict[str, Any]:
    command = [lua_interpreter(), str(generator_path()), "--input", str(input_path)]
    try:
        result = subprocess.run(command, cwd=REPO_ROOT, text=True, capture_output=True, check=False)
    except OSError as exc:
        raise GoldenError(f"could not start Lua generator: {exc}") from exc
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise GoldenError(f"Lua generator failed for {input_path}: {detail}")
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise GoldenError(f"Lua generator did not emit JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise GoldenError("Lua generator emitted a non-object result")
    return value


def run_lua_validation(candidate_path: Path, input_path: Path) -> Dict[str, Any]:
    command = [lua_interpreter(), str(generator_path()), "--input", str(input_path), "--validate", str(candidate_path)]
    try:
        result = subprocess.run(command, cwd=REPO_ROOT, text=True, capture_output=True, check=False)
    except OSError as exc:
        raise GoldenError(f"could not start Lua validator: {exc}") from exc
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise GoldenError(f"Lua validator failed: {detail}")
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise GoldenError(f"Lua validator did not emit JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise GoldenError("Lua validator emitted a non-object result")
    return value


def semantic_assertions(manifest: Mapping[str, Any]) -> List[str]:
    assertions = manifest.get("independent_assertions", manifest.get("assertions", manifest.get("invariants", {})))
    if not isinstance(assertions, dict):
        return []
    return sorted(key for key, value in assertions.items() if key in SEMANTIC_ASSERTIONS and value is not False)


def actual_from_generator(payload: Mapping[str, Any]) -> Any:
    result = payload.get("result")
    return result if isinstance(result, dict) else payload


def validation_receipt_failures(payload: Any) -> List[str]:
    """Require the combined receipt and both independent validation layers."""
    if not isinstance(payload, Mapping):
        return ["missing validation receipt"]
    receipt = payload.get("validation")
    if not isinstance(receipt, Mapping):
        # --validate also exposes the two layers at the envelope boundary so a
        # handwritten candidate uses the same evidence contract as a generated one.
        receipt = payload
    failures: List[str] = []
    if receipt.get("ok") is not True:
        failures.append("combined validation did not pass")
    for name in ("physical", "reconciliation"):
        layer = receipt.get(name)
        if not isinstance(layer, Mapping):
            failures.append(f"missing {name} validation result")
        elif layer.get("ok") is not True:
            failures.append(f"{name} validation did not pass")
        elif name == "physical" and not isinstance(layer.get("result"), Mapping):
            failures.append("physical validation has no completed result")
    return failures


def canonical_version_of(manifest: Mapping[str, Any], value: Any) -> int:
    if isinstance(value, dict) and isinstance(value.get("canonical_version"), int):
        return value["canonical_version"]
    declared = manifest.get("canonical_version", 1)
    return declared if isinstance(declared, int) else 1


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


def write_failure_artifacts(case: Path, manifest: Mapping[str, Any], artifact_root: Path, expected_canonical: Any,
                            actual_canonical: Any, expected_codes: Sequence[str], actual_codes: Sequence[str],
                            validation: Sequence[str], actual_string: Optional[str], actual_payload: Any,
                            input_path: Optional[Path], timings: Mapping[str, Any], stage: Any) -> None:
    failure_dir = artifact_root / case.name
    failure_dir.mkdir(parents=True, exist_ok=True)
    expected_for_diff = expected_canonical if expected_canonical is not None else {"reason_codes": sorted(set(expected_codes))}
    actual_for_diff = actual_canonical if actual_canonical is not None else {"reason_codes": sorted(set(actual_codes))}
    if expected_canonical is not None:
        write_json(failure_dir / "expected_canonical.json", expected_canonical)
    if actual_canonical is not None:
        write_json(failure_dir / "actual_canonical.json", actual_canonical)
    diff = difflib.unified_diff(pretty_json(expected_for_diff).splitlines(True), pretty_json(actual_for_diff).splitlines(True),
                                fromfile="expected", tofile="actual")
    (failure_dir / "diff.txt").write_text("".join(diff), encoding="utf-8")
    if actual_string:
        (failure_dir / "blueprint_string.txt").write_text(actual_string + "\n", encoding="utf-8")
    inputs: Dict[str, Any] = {}
    for name in ("inputs.json", "input.json", "prepared_input.json", "prepared.json", "snapshot.json", "export.json", "options.json"):
        source = case / name
        if source.exists():
            try:
                inputs[name] = read_json(source)
            except GoldenError as exc:
                inputs[name] = {"error": str(exc)}
    write_json(failure_dir / "inputs.json", inputs)
    write_json(failure_dir / "provenance.json", case_provenance(case, manifest, input_path))
    diagnostics: Dict[str, Any] = {"failures": list(validation), "stage": stage}
    if isinstance(actual_payload, dict):
        if actual_payload.get("errors") is not None:
            diagnostics["generator_errors"] = actual_payload["errors"]
        if actual_payload.get("validation") is not None:
            diagnostics["validation"] = actual_payload["validation"]
    write_json(failure_dir / "diagnostics.json", diagnostics)
    write_json(failure_dir / "timings.json", dict(timings))
    if isinstance(actual_payload, dict) and actual_payload.get("result") is not None:
        write_json(failure_dir / "generated_result.json", actual_payload["result"])
    if str(manifest.get("expected_outcome", manifest.get("outcome", "production"))).lower() not in {
        "failure", "failed", "rejection", "rejected", "negative"
    }:
        source = actual_payload.get("result", actual_payload) if isinstance(actual_payload, dict) else actual_payload
        overlay = source.get("blueprint", source) if isinstance(source, dict) else {}
        overlay_value = {
            "entities": [
                {"entity_number": entity.get("entity_number"), "name": entity.get("name"),
                 "position": entity.get("position"), "direction": entity.get("direction")}
                for entity in overlay.get("entities", []) if isinstance(entity, dict)
            ],
            "wires": overlay.get("wires", []) if isinstance(overlay, dict) else [],
        }
        write_json(failure_dir / "layout_overlay.json", overlay_value)


def compare_case(case: Path, manifest: Mapping[str, Any], candidate_override: Optional[Path], artifact_root: Path) -> Tuple[bool, Dict[str, Any]]:
    started = time.monotonic()
    generation_started = time.monotonic()
    expected_raw, expected_string, expected_path = expected_value(case, manifest)
    input_path = prepared_input_path(case, manifest)
    generated = input_path is not None
    actual_file = actual_path(case, manifest, candidate_override)
    actual_string: Optional[str] = None
    actual_payload: Any
    actual_source: str
    if generated:
        if candidate_override:
            message = f"{case.name} refused: --candidate is foreign to a captured PreparedInput; generate this candidate"
            expected_negative, expected_failure_codes = expected_rejection(manifest, expected_raw)
            write_failure_artifacts(case, manifest, artifact_root,
                                    None if expected_negative else canonical(expected_raw), None,
                                    expected_failure_codes, [], [message], None, {"error": message}, input_path,
                                    {"generation_seconds": 0, "comparison_seconds": 0,
                                     "elapsed_seconds": time.monotonic() - started}, "input")
            raise GoldenError(message)
        if actual_file and actual_file.exists():
            message = f"{case.name} refused: {actual_file.name} is a stale/foreign actual file; the corpus must run the Lua generator"
            expected_negative, expected_failure_codes = expected_rejection(manifest, expected_raw)
            write_failure_artifacts(case, manifest, artifact_root,
                                    None if expected_negative else canonical(expected_raw), None,
                                    expected_failure_codes, [], [message], None, {"error": message}, input_path,
                                    {"generation_seconds": 0, "comparison_seconds": 0,
                                     "elapsed_seconds": time.monotonic() - started}, "input")
            raise GoldenError(message)
        try:
            actual_payload = run_lua_generator(input_path)
        except GoldenError as exc:
            expected_negative, expected_failure_codes = expected_rejection(manifest, expected_raw)
            write_failure_artifacts(
                case, manifest, artifact_root,
                None if expected_negative else canonical(expected_raw), None,
                expected_failure_codes, [], [str(exc)], None, {"error": str(exc)}, input_path,
                {"generation_seconds": time.monotonic() - generation_started,
                 "comparison_seconds": 0, "elapsed_seconds": time.monotonic() - started}, "generator",
            )
            raise
        actual_raw = actual_from_generator(actual_payload)
        actual_source = "lua-generator"
    else:
        if not actual_file:
            raise GoldenError(f"{case} has no candidate; a captured case needs prepared_input.json, a fixture needs candidate.json")
        actual_raw, actual_string = load_value(actual_file)
        actual_payload = actual_raw
        actual_source = "handwritten-fixture"
    generation_elapsed = time.monotonic() - generation_started

    negative, expected_codes = expected_rejection(manifest, expected_raw)
    actual_codes = reason_codes(actual_payload)
    validation = [] if negative else independent_checks(manifest, actual_raw)
    if generated and not negative:
        validation.extend(validation_receipt_failures(actual_payload))
    semantic = semantic_assertions(manifest)
    stage = actual_payload.get("stage") if isinstance(actual_payload, dict) else None
    if semantic:
        if input_path and not generated:
            receipt = run_lua_validation(actual_file, input_path)
            stage = receipt.get("stage", stage)
            validation.extend(validation_receipt_failures(receipt))
        else:
            if not input_path:
                validation.append("semantic independent assertions require a captured PreparedInput")

    expected_canonical = None
    actual_canonical = None
    equal = False
    expected_version = canonical_version_of(manifest, expected_raw)
    actual_version = canonical_version_of(manifest, actual_payload)
    if negative:
        equal = actual_codes == sorted(set(expected_codes))
        if not equal:
            validation.append(f"reason codes differ: expected {sorted(set(expected_codes))}, got {actual_codes}")
    else:
        expected_canonical = canonical(expected_raw)
        if generated:
            # The envelope is evidence, not authority.  Rebuild both the
            # canonical structure and its digest from the artifact we are
            # comparing; a supplied ok/digest must never make bad content pass.
            actual_canonical = canonical(actual_raw)
            if isinstance(actual_payload.get("canonical"), dict) and actual_payload["canonical"] != actual_canonical:
                validation.append("Lua canonical structure disagrees with the Python canonical comparator")
                validation.append("canonical blueprint differs")
            lua_digest = actual_payload.get("canonical_sha256")
            if lua_digest != sha256_value(actual_canonical):
                validation.append("Lua canonical digest disagrees with the Python canonical digest")
        else:
            actual_canonical = canonical(actual_raw)
        equal = expected_canonical == actual_canonical and expected_version == actual_version
        if expected_version != actual_version:
            validation.append(f"canonical version differs: expected {expected_version}, got {actual_version}")
        if expected_canonical != actual_canonical:
            validation.append("canonical blueprint differs")
    ok = equal and not validation
    elapsed = time.monotonic() - started
    details = {"case": case.name, "ok": ok, "negative": negative, "expected_path": str(expected_path) if expected_path else None,
               "actual_path": str(actual_file) if actual_file else "generated by tests/golden/generate.lua",
               "actual_source": actual_source, "expected_reason_codes": sorted(set(expected_codes)),
               "actual_reason_codes": actual_codes, "validation_failures": validation, "stage": stage,
               "canonical_version": actual_version, "elapsed_seconds": elapsed}
    if not ok:
        write_failure_artifacts(case, manifest, artifact_root, expected_canonical, actual_canonical, expected_codes,
                                actual_codes, validation, actual_string, actual_payload, input_path,
                                {"generation_seconds": generation_elapsed, "comparison_seconds": max(0, elapsed - generation_elapsed),
                                 "elapsed_seconds": elapsed}, stage)
    return ok, details


def historical_negative_cases(root: Path) -> Dict[str, Mapping[str, Any]]:
    """Load the one registry that may remove a case from automatic release discovery."""
    default_root = Path(__file__).resolve().parent.parent / "cases"
    candidates = [root.parent / "historical-negatives.json"]
    if root.resolve() == default_root.resolve():
        candidates.append(HISTORICAL_NEGATIVES)
    path = next((candidate for candidate in candidates if candidate.is_file()), None)
    if path is None:
        return {}
    value = read_json(path)
    entries = value.get("cases") if isinstance(value, Mapping) else None
    if not isinstance(entries, list):
        raise GoldenError(f"{path} has no cases array")
    result: Dict[str, Mapping[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, Mapping) or not isinstance(entry.get("case_id"), str) or not entry["case_id"]:
            raise GoldenError(f"{path} has a historical-negative entry without a case_id")
        result[entry["case_id"]] = entry
    return result


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
    negative_cases = historical_negative_cases(root)
    result = []
    for path in sorted(root.iterdir()) if root.exists() else []:
        if path.is_dir() and any((path / name).exists() for name in ("manifest.json", "case.json")):
            manifest = read_json(manifest_path(path))
            case_id = manifest.get("case_id", path.name) if isinstance(manifest, Mapping) else path.name
            if case_id in negative_cases:
                continue
            result.append(path)
    return result


def expected_write_path(case: Path, existing: Optional[Path]) -> Path:
    return existing or case / "expected_canonical.json"


def _provenance_for_acceptance(case: Path, manifest: Mapping[str, Any], input_path: Optional[Path]) -> Dict[str, Any]:
    value: Dict[str, Any] = {}
    declared = manifest.get("provenance")
    if isinstance(declared, Mapping):
        value.update(declared)
    path = provenance_path(case)
    if path:
        loaded = read_json(path)
        if isinstance(loaded, Mapping):
            for key, item in loaded.items():
                value.setdefault(key, item)
    if input_path:
        prepared = read_json(input_path)
        if isinstance(prepared, Mapping):
            source_kind = prepared.get("source_kind")
            if source_kind is not None:
                value.setdefault("source_kind", source_kind)
            prepared_provenance = prepared.get("provenance")
            if isinstance(prepared_provenance, Mapping):
                for key, item in prepared_provenance.items():
                    value.setdefault(key, item)
    return value


def _require_bound_evidence(case: Path, manifest: Mapping[str, Any], input_path: Optional[Path]) -> None:
    if input_path is None:
        raise GoldenError(f"{case.name} refused: captured case has no bound PreparedInput evidence")
    source_kind = manifest.get("source_kind")
    provenance = _provenance_for_acceptance(case, manifest, input_path)
    source_kind = source_kind or provenance.get("source_kind")
    if source_kind not in ("runtime", "engine"):
        raise GoldenError(f"{case.name} refused: acceptance requires runtime/engine evidence, got {source_kind!r}")
    candidate_sha = provenance.get("candidate_sha")
    if not isinstance(candidate_sha, str) or not candidate_sha:
        raise GoldenError(f"{case.name} refused: bound evidence has no candidate SHA")
    if provenance.get("packaged") is not True:
        raise GoldenError(f"{case.name} refused: bound evidence is not from a packaged candidate")


def _reject_capped_production_case(case: Path, manifest: Mapping[str, Any], input_path: Optional[Path]) -> None:
    expected = manifest.get("expected_outcome", manifest.get("outcome", "production"))
    if str(expected).lower() not in {"production", "success", "accepted"} or case.name == "tiny-chain":
        return
    sources = []
    if input_path is not None:
        sources.append((input_path, read_json(input_path)))
    for name in ("options.json",):
        path = case / name
        if path.exists():
            sources.append((path, read_json(path)))
    for path, value in sources:
        if not isinstance(value, Mapping):
            continue
        for key in FORBIDDEN_GENERATION_OPTIONS:
            if key in value:
                raise GoldenError(f"{case.name} refused: production case carries {key}; use default configuration")
        nested = value.get("options")
        if isinstance(nested, Mapping):
            for key in FORBIDDEN_GENERATION_OPTIONS:
                if key in nested:
                    raise GoldenError(f"{case.name} refused: production case carries {key}; use default configuration")


def _matrix_path(root: Path) -> Optional[Path]:
    default_root = Path(__file__).resolve().parent.parent / "cases"
    candidates = [root.parent / "required-matrix.json"]
    if root.resolve() == default_root.resolve():
        candidates.append(REPO_ROOT / "tests" / "golden" / "required-matrix.json")
    return next((path for path in candidates if path.exists()), None)


def _matrix_with_path(root: Path) -> Tuple[Optional[Dict[str, Any]], Optional[Path]]:
    path = _matrix_path(root)
    if path is None:
        return None, None
    try:
        matrix = _shared_matrix_reader()(path)
    except Exception as exc:
        if isinstance(exc, GoldenError):
            raise
        raise GoldenError(str(exc)) from exc
    return dict(matrix), path


def _acceptance_matrix(root: Path, case: Path, manifest: Mapping[str, Any]) -> Tuple[Dict[str, Any], Path]:
    matrix, path = _matrix_with_path(root)
    if matrix is None or path is None:
        raise GoldenError(f"{case.name} refused: required matrix is missing")
    case_id = manifest.get("case_id", case.name)
    branch = case_branch(manifest)
    for entry in matrix.get("cases", []):
        if not isinstance(entry, Mapping) or entry.get("case_id") != case_id:
            continue
        if branch is None or branch in entry.get("branches", []):
            return matrix, path
    pair = f"{case_id}@{branch or '<unknown>'}"
    raise GoldenError(f"{case.name} refused: no required matrix pair {pair}")


def _staged_json(path: Path, value: Any) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(pretty_json(value))
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        try:
            Path(temporary).unlink()
        except OSError:
            pass
        raise
    return Path(temporary)


def _commit_acceptance(files: Mapping[Path, Any]) -> None:
    staged: Dict[Path, Path] = {}
    originals: Dict[Path, Optional[bytes]] = {}
    replaced: List[Path] = []
    try:
        for target, value in files.items():
            originals[target] = target.read_bytes() if target.exists() else None
            staged[target] = _staged_json(target, value)
        for target, temporary in staged.items():
            os.replace(temporary, target)
            replaced.append(target)
    except BaseException:
        for target in reversed(replaced):
            original = originals[target]
            try:
                if original is None:
                    target.unlink(missing_ok=True)
                else:
                    descriptor, restore_name = tempfile.mkstemp(
                        prefix=f".{target.name}.", suffix=".tmp", dir=target.parent
                    )
                    try:
                        with os.fdopen(descriptor, "wb") as stream:
                            stream.write(original)
                        os.replace(restore_name, target)
                    finally:
                        try:
                            Path(restore_name).unlink()
                        except OSError:
                            pass
            except BaseException:
                # The original exception remains the useful failure; the next invocation
                # still sees the staged files cleaned below and can repair the target.
                pass
        raise
    finally:
        for temporary in staged.values():
            try:
                temporary.unlink()
            except OSError:
                pass


def accept_case(case: Path, manifest: Mapping[str, Any], candidate_override: Optional[Path], artifact_root: Path,
                root: Optional[Path] = None) -> None:
    state = manifest.get("state", manifest.get("status"))
    if state == "accepted":
        raise GoldenError(f"{case.name} refused: accepted baseline may not be replaced by intake")
    if state not in (None, "draft", "captured"):
        raise GoldenError(f"{case.name} refused: unsupported case state {state!r}")
    input_path = prepared_input_path(case, manifest)
    _reject_capped_production_case(case, manifest, input_path)
    if state == "captured":
        _require_bound_evidence(case, manifest, input_path)
    try:
        expected_raw, _, old_path = expected_value(case, manifest)
    except GoldenError as exc:
        if "has no expected result" not in str(exc):
            raise
        expected_raw, old_path = {}, None
    actual_file = actual_path(case, manifest, candidate_override)
    if input_path:
        if candidate_override:
            raise GoldenError(f"{case.name} refused: --candidate is foreign to a captured PreparedInput")
        if actual_file and actual_file.exists():
            raise GoldenError(f"{case.name} refused: {actual_file.name} is a stale/foreign actual file")
        actual_payload = run_lua_generator(input_path)
        actual_raw = actual_from_generator(actual_payload)
        actual_label = "generated by tests/golden/generate.lua"
    else:
        if not actual_file:
            raise GoldenError(f"{case} has no candidate")
        actual_raw, _ = load_value(actual_file)
        actual_payload = actual_raw
        actual_label = str(actual_file)
    negative, old_codes = expected_rejection(manifest, expected_raw)
    failures = [] if negative else independent_checks(manifest, actual_raw)
    if input_path and not negative:
        failures.extend(validation_receipt_failures(actual_payload))
    semantic = semantic_assertions(manifest)
    if semantic:
        if not input_path:
            failures.append("semantic independent assertions require a captured PreparedInput")
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
    write_json(review / "provenance.json", {"case": case.name, "candidate": actual_label,
                                              "source": "lua-generator" if input_path else "handwritten-fixture",
                                              "prepared_input": str(input_path) if input_path else None,
                                              "prepared_input_sha256": sha256_file(input_path) if input_path else None,
                                              "canonical_version": canonical_version_of(manifest, actual_payload),
                                              "canonical_sha256": sha256_value(new_value) if not negative else None,
                                              "validation_failures": failures})
    target = expected_write_path(case, old_path)
    matrix, matrix_path = _matrix_with_path(root or case.parent)
    updated_matrix = None
    if matrix is not None and matrix_path is not None:
        matrix, matrix_path = _acceptance_matrix(root or case.parent, case, manifest)
        updated_matrix = deep_copy(matrix)
    case_id = manifest.get("case_id", case.name)
    if updated_matrix is not None:
        for entry in updated_matrix.get("cases", []):
            if isinstance(entry, dict) and entry.get("case_id") == case_id:
                entry["state"] = "accepted"
                break
    updated_manifest = dict(manifest)
    updated_manifest["state"] = "accepted"
    expectation_value = new_value
    # Preserve a wrapper manifest if expected.json stores more than the canonical value.
    if target.name == "expected.json":
        original = read_json(target)
        if isinstance(original, dict) and "canonical" in original:
            original["canonical"] = expectation_value
            expectation_value = original
        else:
            expectation_value = new_value
    files = {target: expectation_value, manifest_path(case): updated_manifest}
    if updated_matrix is not None and matrix_path is not None:
        files[matrix_path] = updated_matrix
    _commit_acceptance(files)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("paths", nargs="*", help="case root followed by optional case names")
    result.add_argument("--root", "--cases", dest="root", help="case directory")
    result.add_argument("--candidate", help="candidate blueprint/result path for one selected case")
    result.add_argument("--artifacts", help="failure/accept artifact directory")
    result.add_argument("--branch", help="only run cases declared for this Factorio branch")
    result.add_argument("--drafts", choices=("report",), help="report draft cases without treating them as passes")
    return result


def required_matrix(root: Path) -> Optional[Dict[str, Any]]:
    matrix, _ = _matrix_with_path(root)
    return matrix


def check_branch_requirements(root: Path, cases: Sequence[Path], branch: Optional[str]) -> Optional[str]:
    if not branch:
        return None
    matrix = required_matrix(root)
    if matrix is None:
        return None
    discovered: Dict[str, List[Path]] = {}
    for case in cases:
        try:
            manifest = read_json(manifest_path(case))
        except GoldenError:
            continue
        case_id = manifest.get("case_id", case.name)
        if isinstance(case_id, str):
            discovered.setdefault(case_id, []).append(case)
    negative_cases = historical_negative_cases(root)
    entries = []
    for entry in matrix.get("cases", []):
        if not isinstance(entry, Mapping) or branch not in entry.get("branches", []):
            continue
        case_id = entry.get("case_id")
        negative = negative_cases.get(case_id) if isinstance(case_id, str) else None
        if negative is not None:
            transferred = negative.get("production_coverage_transferred_to")
            branches = negative.get("branches_transferred", [])
            if isinstance(transferred, str) and branch in branches:
                entry = dict(entry)
                entry["case_id"] = transferred
            else:
                return f"historical-negative {case_id} has no checked transfer for branch {branch}"
        entries.append(entry)
    for entry in entries:
        case_id = entry.get("case_id")
        if not isinstance(case_id, str) or not case_id:
            return f"branch {branch} has a required matrix row without a case id"
        if case_id not in discovered:
            return f"branch {branch} missing required pair {case_id}@{branch} (case directory)"
    return None


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
    if args.drafts == "report" and not selected and root.is_dir():
        # Reporting is an audit view, not release discovery.  Include registered
        # historical negatives so the report retains the captured count while
        # the normal release path remains excluded and transfer-aware.
        known = {case.name for case in cases}
        for case_id in historical_negative_cases(root):
            case = root / case_id
            if case.name not in known and case.is_dir() and any((case / name).exists()
                                                               for name in ("manifest.json", "case.json")):
                cases.append(case)
        cases.sort()
    if not cases:
        if args.branch:
            print(f"FAIL branch {args.branch}: matches zero required cases", file=sys.stderr)
            return 1
        print("golden: no cases")
        return 0
    if not explicit_accept:
        requirement_failure = check_branch_requirements(root, cases, args.branch)
        if requirement_failure and args.drafts != "report":
            print("FAIL " + requirement_failure, file=sys.stderr)
            return 1
    failures = 0
    drafts = 0
    captured = 0
    processed = 0
    for case in cases:
        try:
            manifest = read_json(manifest_path(case))
            if not isinstance(manifest, dict):
                raise GoldenError("manifest is not an object")
            declared_branch = case_branch(manifest)
            if args.branch and declared_branch not in (None, args.branch):
                print(f"NOT_APPLICABLE {case.name} (declared branch {declared_branch}, selected {args.branch})")
                continue
            processed += 1
            #A captured case carries a real capture and still lacks an accepted expectation, so it is
            #reported apart from a draft and is never a pass. Explicit acceptance is an intake operation;
            #branch readiness is deliberately not a precondition for it.
            state = manifest.get("state", manifest.get("status"))
            if state in ("draft", "captured") and not explicit_accept:
                if args.drafts == "report":
                    if state == "captured":
                        captured += 1
                    else:
                        drafts += 1
                    failures += 1
                    print(("CAPTURED " if state == "captured" else "DRAFT ") + case.name)
                    continue
                raise GoldenError(f"{state} case cannot satisfy the release corpus")
            if explicit_accept:
                if len(cases) != 1:
                    raise GoldenError("accept names exactly one case")
                accept_case(case, manifest, Path(args.candidate) if args.candidate else None, artifact_root, root)
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
    if args.branch and processed == 0:
        print(f"FAIL branch {args.branch}: matches zero applicable cases", file=sys.stderr)
        return 1
    if args.drafts == "report":
        print(f"golden: {processed - failures} passed, {failures - drafts - captured} failed, "
              f"{drafts} drafts, {captured} captured")
    else:
        print(f"golden: {processed - failures} passed, {failures} failed")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
