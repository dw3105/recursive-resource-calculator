"""Replay one named golden case against the current offline generator.

The case is always selected explicitly and verified against its manifest.  The
historical-negative registry gives captured failures a structural role without
turning them into production successes or silently dropping their coverage.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
CASES_ROOT = ROOT / "tests" / "golden" / "cases"
REGISTRY_PATH = ROOT / "tests" / "golden" / "historical-negatives.json"
GENERATOR = ROOT / "tests" / "golden" / "generate.lua"
INTERPRETERS = ("lua5.2",)  # Factorio runs Lua 5.2 only; lua5.4 dropped 2026-09-23


def _load_runner():
    path = ROOT / "tests" / "golden" / "lib" / "runner.py"
    spec = importlib.util.spec_from_file_location("rrc_incident_golden_runner", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"FAIL cannot load golden runner: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


GOLDEN = _load_runner()
FORBIDDEN_OPTIONS = ("search_budget", "max_ops", "max_search_grids", "max_grid_trials")


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"FAIL cannot read {path}: {exc}") from exc


def registry() -> dict[str, dict[str, Any]]:
    value = load(REGISTRY_PATH)
    entries = value.get("cases") if isinstance(value, dict) else None
    if not isinstance(entries, list):
        raise SystemExit(f"FAIL {REGISTRY_PATH} has no cases array")
    result: dict[str, dict[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("case_id"), str):
            raise SystemExit(f"FAIL {REGISTRY_PATH} has an invalid case entry")
        result[entry["case_id"]] = entry
    return result


def select_case(case_id: str) -> tuple[Path, dict[str, Any], dict[str, Any] | None, Path]:
    if not case_id or Path(case_id).name != case_id or case_id in {".", ".."}:
        raise SystemExit(f"FAIL invalid case selector: {case_id!r}")
    case = (CASES_ROOT / case_id).resolve()
    if CASES_ROOT.resolve() not in case.parents or not case.is_dir():
        raise SystemExit(f"FAIL case is missing: {case_id}")
    manifest_path = case / "manifest.json"
    if not manifest_path.is_file():
        raise SystemExit(f"FAIL case has no manifest: {case_id}")
    manifest = load(manifest_path)
    if not isinstance(manifest, dict) or manifest.get("case_id", case.name) != case_id:
        raise SystemExit(f"FAIL case selector does not match its manifest: {case_id}")
    input_path = GOLDEN.prepared_input_path(case, manifest)
    if input_path is None or not input_path.is_file():
        raise SystemExit(f"FAIL {case_id}: selected case has no prepared input")
    return case, manifest, registry().get(case_id), input_path


def run_generator(interpreter: str, input_path: Path) -> dict[str, Any]:
    proc = subprocess.run(
        [interpreter, str(GENERATOR), "--input", str(input_path)],
        cwd=str(ROOT), capture_output=True, text=True, check=False, timeout=1800,
    )
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip()
        raise SystemExit(f"FAIL the generator aborted under {interpreter} (exit {proc.returncode}): {detail[-2000:]}")
    try:
        value = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"FAIL {interpreter}: generator did not emit JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"FAIL {interpreter}: generator emitted a non-object result")
    return value


def capture_reason_codes(prepared: dict[str, Any]) -> list[str]:
    """Check required capture vectors without inferring their values."""
    catalog = prepared.get("catalog") if isinstance(prepared.get("catalog"), dict) else {}
    inserter = catalog.get("inserter") if isinstance(catalog.get("inserter"), dict) else None
    if inserter is None:
        return ["BP_CAP_INCOMPLETE"]
    for field in ("pickup_offset", "drop_offset"):
        value = inserter.get(field)
        if not isinstance(value, dict) or not value or value.get("x") is None or value.get("y") is None:
            return ["BP_CAP_INCOMPLETE"]
    return []


def expected_structural_rejection(entry: dict[str, Any] | None) -> str | None:
    if entry is None:
        return None
    outcome = str(entry.get("structural_outcome", "")).lower()
    code = entry.get("structural_reason_code")
    if outcome not in {"rejection", "rejected", "failure", "failed"} or not isinstance(code, str) or not code:
        raise SystemExit("FAIL historical-negative entry has no complete structural rejection role")
    return code


def check_default_configuration(prepared: dict[str, Any], manifest: dict[str, Any]) -> None:
    options = prepared.get("options") if isinstance(prepared.get("options"), dict) else {}
    for key in FORBIDDEN_OPTIONS:
        if key in options:
            raise SystemExit(f"FAIL {manifest.get('case_id')}: captured input carries {key}")
    provenance = manifest.get("provenance") if isinstance(manifest.get("provenance"), dict) else {}
    if provenance and provenance.get("default_configuration") is not True:
        raise SystemExit(f"FAIL {manifest.get('case_id')}: case is not default configuration")


def artifact_failure(payload: dict[str, Any], manifest: dict[str, Any]) -> str | None:
    artifact = payload.get("result")
    if not isinstance(artifact, dict):
        return "generator produced no artifact"
    blueprint = artifact.get("blueprint", artifact)
    entities = blueprint.get("entities") if isinstance(blueprint, dict) else None
    if not isinstance(entities, list) or not entities:
        return "artifact is empty"
    physical = GOLDEN.independent_checks(manifest, artifact)
    if physical:
        return "invalid artifact: " + "; ".join(physical)
    validation_failures = GOLDEN.validation_receipt_failures(payload)
    if validation_failures:
        return "artifact validation failed: " + "; ".join(validation_failures)
    actual_canonical = GOLDEN.canonical(artifact)
    if payload.get("canonical") != actual_canonical:
        return "generator canonical content does not match the decoded artifact"
    expected_digest = hashlib.sha256(GOLDEN.stable_json(actual_canonical).encode("utf-8")).hexdigest()
    if payload.get("canonical_sha256") != expected_digest:
        return "generator canonical digest does not match the decoded artifact"
    return None


def structural(case_id: str, manifest: dict[str, Any], entry: dict[str, Any] | None,
               input_path: Path) -> int:
    prepared = load(input_path)
    if not isinstance(prepared, dict):
        print(f"FAIL {case_id}: prepared input is not an object")
        return 1
    expected_code = expected_structural_rejection(entry)
    actual_codes = capture_reason_codes(prepared)
    if expected_code is not None:
        if actual_codes != [expected_code]:
            print(f"FAIL {case_id}: expected structural rejection {expected_code}, got {actual_codes}")
            return 1
        print(f"PASS {case_id}: structural rejection {expected_code}")
        print(f"ENGINE_STATUS {case_id}: pending")
        return 0

    check_default_configuration(prepared, manifest)
    for interpreter in INTERPRETERS:
        payload = run_generator(interpreter, input_path)
        failure = artifact_failure(payload, manifest)
        if failure:
            print(f"FAIL {case_id} [{interpreter}]: {failure}")
            return 1
        print(f"PASS {case_id} [{interpreter}]: nonempty physically valid artifact")
    print(f"ENGINE_STATUS {case_id}: pending")
    return 0


def require_complete_case(case: Path, manifest: dict[str, Any]) -> str | None:
    state = manifest.get("state", manifest.get("status"))
    if state in {"draft", "captured"}:
        return f"case state {state!r} is not complete"
    try:
        expected, _, _ = GOLDEN.expected_value(case, manifest)
    except GOLDEN.GoldenError as exc:
        return f"case has no complete expected result: {exc}"
    negative, _ = GOLDEN.expected_rejection(manifest, expected)
    if negative:
        return "a rejection case cannot satisfy --require-success"
    return None


def replay_recorded(case_id: str, manifest: dict[str, Any], input_path: Path, require_success: bool) -> int:
    prepared = load(input_path)
    if not isinstance(prepared, dict):
        print(f"FAIL {case_id}: prepared input is not an object")
        return 1
    check_default_configuration(prepared, manifest)
    recorded = manifest.get("current_outcome") or manifest.get("observed_outcome")
    if not isinstance(recorded, dict):
        print(f"FAIL {case_id}: case has no recorded outcome")
        return 1
    failures: list[str] = []
    for interpreter in INTERPRETERS:
        payload = run_generator(interpreter, input_path)
        label = f"[{interpreter}]"
        if require_success:
            failure = artifact_failure(payload, manifest)
            if failure:
                failures.append(f"{label} {failure}")
            else:
                print(f"PASS {case_id} {label}: complete artifact")
            continue
        if recorded.get("state") == "failure":
            artifact = payload.get("result")
            blueprint = artifact.get("blueprint", artifact) if isinstance(artifact, dict) else {}
            if isinstance(blueprint, dict) and isinstance(blueprint.get("entities"), list) and blueprint["entities"]:
                failures.append(f"{label} expected generator failure")
            codes = GOLDEN.reason_codes(payload.get("errors"))
            if codes != sorted(recorded.get("reason_codes", [])):
                failures.append(f"{label} reason codes differ: expected {recorded.get('reason_codes')}, got {codes}")
        else:
            failure = artifact_failure(payload, manifest)
            if failure:
                failures.append(f"{label} {failure}")
            elif recorded.get("entity_count") is not None:
                artifact = payload["result"]
                blueprint = artifact.get("blueprint", artifact)
                if len(blueprint.get("entities", [])) != recorded["entity_count"]:
                    failures.append(f"{label} entity count differs")
    if failures:
        for failure in failures:
            print(f"FAIL {case_id}: {failure}")
        return 1
    print(f"PASS {case_id}: recorded outcome matches")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", required=True, help="verified golden case id")
    parser.add_argument("--require-success", action="store_true")
    parser.add_argument("--require-rejection", action="store_true")
    parser.add_argument("--structural", action="store_true", help="run structural replay; engine remains pending")
    args = parser.parse_args(argv)
    if args.require_success and args.require_rejection:
        parser.error("--require-success and --require-rejection are mutually exclusive")

    case, manifest, entry, input_path = select_case(args.case)
    expected_code = expected_structural_rejection(entry)
    if args.require_rejection:
        if expected_code is None:
            print(f"FAIL {args.case}: selected case is not a registered historical negative")
            return 1
        return structural(args.case, manifest, entry, input_path)
    if args.structural:
        return structural(args.case, manifest, entry, input_path)
    if args.require_success and expected_code is not None:
        print(f"FAIL {args.case}: a registered historical negative cannot satisfy --require-success")
        return 1
    if args.require_success:
        incomplete = require_complete_case(case, manifest)
        if incomplete:
            print(f"FAIL {args.case}: {incomplete}")
            return 1
    return replay_recorded(args.case, manifest, input_path, args.require_success)


if __name__ == "__main__":
    sys.exit(main())
