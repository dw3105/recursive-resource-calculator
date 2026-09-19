"""Shared input and case helpers for the golden corpus tools.

The game writes debug exports with Factorio's ``zlib+base64`` helper.  Keeping
that decoder here gives ``add_case`` and the tests one implementation, and
makes the format useful on a machine without Factorio installed.
"""

from __future__ import annotations

import base64
import copy
import json
import math
import zlib
from pathlib import Path
from typing import Any, Mapping, Optional


class CaseInputError(Exception):
    """An export or generation-options input cannot describe a case."""


def read_json(path: Path, label: str = "JSON") -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise CaseInputError(f"cannot read {label} {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise CaseInputError(f"{label} {path} is not valid JSON: {exc}") from exc


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")


def decode_zlib_base64(encoded: str) -> Any:
    text = "".join(encoded.split())
    if text.startswith("0"):
        text = text[1:]
    try:
        compressed = base64.b64decode(text, validate=True)
        return json.loads(zlib.decompress(compressed).decode("utf-8"))
    except (ValueError, zlib.error, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CaseInputError(f"encoded export is not valid zlib+base64 JSON: {exc}") from exc


def read_export(path: Path) -> tuple[Any, Optional[str]]:
    """Read either a debug string or already-decoded export JSON."""
    try:
        text = path.read_text(encoding="utf-8").strip()
    except OSError as exc:
        raise CaseInputError(f"cannot read debug export {path}: {exc}") from exc
    if not text:
        raise CaseInputError(f"debug export {path} is empty")
    if text.startswith("{") or text.startswith("["):
        try:
            return json.loads(text), None
        except json.JSONDecodeError as exc:
            raise CaseInputError(f"debug export {path} is not valid JSON: {exc}") from exc
    return decode_zlib_base64(text), text


def finite(value: Any, fallback: Any = None) -> Any:
    if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value):
        return value
    return fallback


def first(mapping: Mapping[str, Any], *keys: str, default: Any = None) -> Any:
    for key in keys:
        if key in mapping and mapping[key] is not None:
            return mapping[key]
    return default


def copy_value(value: Any) -> Any:
    return copy.deepcopy(value)


def branch_of(value: Mapping[str, Any]) -> Optional[str]:
    versions = value.get("versions")
    environment = value.get("environment")
    if isinstance(versions, Mapping):
        branch = first(versions, "factorio_branch", "factorio", "branch")
        if isinstance(branch, str):
            return branch
    if isinstance(environment, Mapping):
        branch = first(environment, "factorio_branch", "factorio", "branch", "base_game_version")
        if isinstance(branch, str):
            return branch
    branch = first(value, "factorio_branch", "factorio", "branch")
    return branch if isinstance(branch, str) else None


def build_manifest(case_id: str, export: Mapping[str, Any], options: Mapping[str, Any]) -> dict[str, Any]:
    """Make the mechanical part of a case manifest from a debug snapshot.

    Human review fields deliberately remain explicit: an author must choose
    the expected outcome and rates rather than having a capture silently become
    a release expectation.
    """
    environment = export.get("environment") if isinstance(export.get("environment"), Mapping) else {}
    sheet = export.get("sheet") if isinstance(export.get("sheet"), Mapping) else {}
    settings = export.get("settings") if isinstance(export.get("settings"), Mapping) else {}
    targets = first(export, "targets", default=sheet.get("targets", []))
    selection = first(export, "selection", default=sheet.get("selection", []))
    branch = first(options, "factorio_branch", "factorio", "branch", default=None) or branch_of(export) or "2.0"
    mod_version = first(options, "mod_version", "rrc_version", default=None)
    if mod_version is None:
        mod_version = first(export, "rrc_version", default=environment.get("mod_version", "unknown"))
    base_version = first(options, "base_game_version", default=environment.get("base_game_version", branch))
    scenario = options.get("engine_scenario") if isinstance(options.get("engine_scenario"), Mapping) else {}
    scenario = copy_value(scenario)
    scenario.setdefault("initial_state", {})
    scenario.setdefault("supply", [])
    scenario.setdefault("drain", [])
    scenario.setdefault("warm_up_ticks", 0)
    scenario.setdefault("sampling_window_ticks", 0)
    scenario.setdefault("expected_rates", {})
    scenario.setdefault("allowed_discrete_error", 0)
    scenario.setdefault("timeout_seconds", 60)
    return {
        "schema_version": 1,
        "case_id": case_id,
        "factorio_branch": branch,
        "versions": {
            "mod": mod_version,
            "rrc_version": mod_version,
            "factorio": branch,
            "factorio_branch": branch,
            "base_game_version": base_version,
        },
        "targets": copy_value(targets if targets is not None else []),
        "setup": {
            "selection": copy_value(selection if selection is not None else []),
            "settings": copy_value(settings),
            "options": copy_value(sheet.get("options", {})),
        },
        "engine_scenario": scenario,
        "expected_outcome": options.get("expected_outcome", "production"),
        "expected": options.get("expected", "expected_canonical.json"),
        "actual": options.get("actual", "candidate.json"),
    }


def source_case_root(script_path: Path) -> Path:
    return script_path.resolve().parent / "cases"
