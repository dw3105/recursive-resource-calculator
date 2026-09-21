#!/usr/bin/env python3
"""Fail-closed release verification for the packaged engine evidence.

The gate is deliberately a file verifier.  It never starts Factorio, creates an
observation, or rebuilds an archive.  The archive supplied to it is the exact
byte sequence named by the host-side receipt.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple


SCHEMA_VERSION = 1
SUPPORTED_BRANCHES = ("2.0", "2.1")
DEFAULT_MATRIX = Path("tests/golden/required-matrix.json")
DEFAULT_EVIDENCE_ROOT = Path("docs/engine-evidence")
DEFAULT_GOLDEN_ROOT = Path("tests/golden/cases")


class ReleaseGateError(Exception):
    """A release is refused for one auditable reason."""

    def __init__(self, reason: str):
        self.reason = reason
        super().__init__(reason)


def _receipt_module():
    """Load evidence_receipt.py without requiring tools to be a package."""
    path = Path(__file__).with_name("evidence_receipt.py")
    spec = importlib.util.spec_from_file_location("rrc_release_evidence_receipt", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


RECEIPT = _receipt_module()


def _read_json(path: Path, label: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ReleaseGateError(f"missing {label}: {path}") from exc
    except OSError as exc:
        raise ReleaseGateError(f"cannot read {label} {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ReleaseGateError(f"invalid {label}: {path}: {exc}") from exc


def _stable_json(value: Any) -> str:
    try:
        return json.dumps(value, sort_keys=True, separators=(",", ":"),
                          ensure_ascii=False, allow_nan=False)
    except (TypeError, ValueError) as exc:
        raise ReleaseGateError(f"invalid JSON value in evidence: {exc}") from exc


def observation_sha256(observation: Mapping[str, Any]) -> str:
    return hashlib.sha256(_stable_json(observation).encode("utf-8")).hexdigest()


def canonical_sha256(canonical: Any) -> str:
    """Hash the offline canonical JSON, not a compressed blueprint string."""
    return hashlib.sha256(_stable_json(canonical).encode("utf-8")).hexdigest()


def load_matrix(path: Path = DEFAULT_MATRIX) -> Mapping[str, Any]:
    matrix = _read_json(Path(path), "required-case matrix")
    if not isinstance(matrix, Mapping):
        raise ReleaseGateError("invalid matrix: the top level is not an object")
    version = matrix.get("schema_version")
    if version != SCHEMA_VERSION:
        raise ReleaseGateError(
            f"unsupported schema version: matrix has {version!r}, expected {SCHEMA_VERSION}"
        )
    cases = matrix.get("cases")
    if not isinstance(cases, list):
        raise ReleaseGateError("invalid matrix: cases must be an array")
    return matrix


def select_cases(matrix: Mapping[str, Any], branch: Optional[str]) -> List[Mapping[str, Any]]:
    if not branch:
        raise ReleaseGateError("missing branch: specify 2.0 or 2.1")
    cases = matrix.get("cases", [])
    selected: List[Mapping[str, Any]] = []
    for case in cases:
        if not isinstance(case, Mapping):
            raise ReleaseGateError("absent case: a matrix entry is not an object")
        branches = case.get("branches")
        if not isinstance(branches, list):
            raise ReleaseGateError(
                f"missing branch: case {case.get('case_id', '<unknown>')} has no branches"
            )
        if branch in branches:
            selected.append(case)
    if not selected:
        raise ReleaseGateError(f"empty selection: no required cases for branch {branch}")
    return selected


def _case_id(case: Mapping[str, Any]) -> str:
    value = case.get("case_id")
    if not isinstance(value, str) or not value:
        raise ReleaseGateError("absent case: matrix entry has no case_id")
    return value


def _case_manifest(case_id: str, golden_root: Path) -> Tuple[Mapping[str, Any], Path, Any]:
    case_root = golden_root / case_id
    manifest_path = case_root / "manifest.json"
    if not manifest_path.is_file():
        raise ReleaseGateError(f"absent case: offline golden {case_id} is not present")
    manifest = _read_json(manifest_path, f"golden manifest for {case_id}")
    if not isinstance(manifest, Mapping):
        raise ReleaseGateError(f"absent case: golden manifest for {case_id} is not an object")
    expected_name = manifest.get("expected", "expected_canonical.json")
    if not isinstance(expected_name, str) or not expected_name:
        raise ReleaseGateError(f"absent case: {case_id} has no offline expected result")
    expected_path = case_root / expected_name
    if not expected_path.is_file():
        raise ReleaseGateError(f"absent case: offline result for {case_id} is not present")
    return manifest, case_root, _read_json(expected_path, f"offline result for {case_id}")


def _same_identity(left: Any, right: Any) -> bool:
    if isinstance(left, Mapping):
        left = left.get("case_id", left.get("case", left.get("id")))
    if isinstance(right, Mapping):
        right = right.get("case_id", right.get("case", right.get("id")))
    return left == right


def _first(mapping: Mapping[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in mapping and mapping[key] is not None:
            return mapping[key]
    return None


def _outcome(observation: Mapping[str, Any]) -> Mapping[str, Any]:
    kind = observation.get("outcome_kind")
    if isinstance(kind, str):
        value = observation.get(kind)
        if isinstance(value, Mapping):
            return value
    value = observation.get("outcome")
    if isinstance(value, Mapping):
        return value
    return {}


def _observed_kind(observation: Mapping[str, Any]) -> Optional[str]:
    value = observation.get("outcome_kind")
    if isinstance(value, str):
        return value
    outcome = observation.get("outcome")
    if isinstance(outcome, Mapping):
        value = outcome.get("kind")
        if isinstance(value, str):
            return value
    return None


def _number(value: Any) -> Optional[float]:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if not math.isfinite(value):
        return None
    return float(value)


def _environment(observation: Mapping[str, Any]) -> Mapping[str, Any]:
    value = observation.get("environment")
    return value if isinstance(value, Mapping) else {}


def _branch_from_observation(observation: Mapping[str, Any]) -> Optional[str]:
    environment = _environment(observation)
    versions = observation.get("versions")
    if isinstance(versions, Mapping):
        value = _first(versions, "factorio_branch", "factorio", "branch", "base_game_version")
        if isinstance(value, str):
            return value
    value = _first(environment, "factorio_branch", "factorio", "branch", "base_game_version")
    if isinstance(value, str):
        return value
    value = _first(observation, "factorio_branch", "factorio", "branch")
    return value if isinstance(value, str) else None


def _mod_version_from_observation(observation: Mapping[str, Any]) -> Optional[str]:
    environment = _environment(observation)
    versions = observation.get("versions")
    for source in (observation, environment, versions if isinstance(versions, Mapping) else {}):
        value = _first(source, "mod_version", "rrc_version", "mod")
        if isinstance(value, str):
            return value
    return None


def _active_mod_names(observation: Mapping[str, Any]) -> set[str]:
    environment = _environment(observation)
    values: List[Any] = []
    for source in (observation, environment):
        value = _first(source, "active_mods", "mods")
        if value is not None:
            values.append(value)
    names: set[str] = set()
    for value in values:
        if isinstance(value, Mapping):
            for key, child in value.items():
                if isinstance(key, str):
                    names.add(key)
                if isinstance(child, Mapping):
                    name = _first(child, "name", "id", "mod")
                    if isinstance(name, str):
                        names.add(name)
        elif isinstance(value, list):
            for child in value:
                if isinstance(child, str):
                    names.add(child)
                elif isinstance(child, Mapping):
                    name = _first(child, "name", "id", "mod")
                    if isinstance(name, str):
                        names.add(name)
    return names


def _check_environment(case: Mapping[str, Any], observation: Mapping[str, Any],
                       build: Mapping[str, Any], branch: str,
                       expected_version: Optional[str]) -> None:
    observed_branch = _branch_from_observation(observation)
    if observed_branch is None:
        raise ReleaseGateError(f"missing branch: observation for {_case_id(case)} has no engine branch")
    if observed_branch != branch or build.get("factorio_branch") != branch:
        raise ReleaseGateError(
            f"mismatched environment: case {_case_id(case)} uses branch {observed_branch!r}, expected {branch!r}"
        )

    observed_version = _mod_version_from_observation(observation)
    build_version = build.get("mod_version")
    if observed_version is None or not isinstance(build_version, str):
        raise ReleaseGateError(f"mismatched environment: case {_case_id(case)} has no packaged mod version")
    if observed_version != build_version:
        raise ReleaseGateError(
            f"mismatched environment: observation mod version {observed_version!r}, archive {build_version!r}"
        )
    if expected_version is not None and build_version != expected_version:
        raise ReleaseGateError(
            f"mismatched environment: archive mod version {build_version!r}, requested {expected_version!r}"
        )

    engine_version = _first(observation, "engine_version", "factorio_version")
    if engine_version is None:
        engine_version = _first(_environment(observation), "engine_version", "factorio_version")
    if engine_version is not None and not str(engine_version).startswith(branch):
        raise ReleaseGateError(
            f"mismatched environment: engine {engine_version!r} is not Factorio {branch}"
        )
    expected_mods = case.get("mods", [])
    if not isinstance(expected_mods, list):
        raise ReleaseGateError(f"mismatched environment: case {_case_id(case)} has invalid mods")
    active_mods = _active_mod_names(observation)
    missing_mods = [str(mod) for mod in expected_mods if str(mod) not in active_mods]
    if missing_mods:
        raise ReleaseGateError(
            f"mismatched environment: missing active mod(s) {', '.join(missing_mods)}"
        )


def _check_receipt(case: Mapping[str, Any], observation: Mapping[str, Any], receipt: Mapping[str, Any],
                   archive: Path, candidate_sha: str, branch: str) -> None:
    case_id = _case_id(case)
    if receipt.get("schema_version") != SCHEMA_VERSION:
        raise ReleaseGateError(f"unsupported schema version: receipt for {case_id}")
    if not _same_identity(receipt.get("case_id", receipt.get("case")), case_id):
        raise ReleaseGateError(f"mismatched receipt: receipt case is not {case_id}")
    if str(receipt.get("candidate_sha")) != candidate_sha:
        raise ReleaseGateError(f"mismatched receipt: candidate for {case_id} is not {candidate_sha}")
    if receipt.get("observation") != dict(observation):
        raise ReleaseGateError(f"mismatched receipt: observation binding for {case_id} changed")
    expected_observation_hash = observation_sha256(observation)
    if receipt.get("observation_sha256") != expected_observation_hash:
        raise ReleaseGateError(f"mismatched receipt: observation digest for {case_id} is invalid")
    archive_hash = RECEIPT.zip_sha256(archive)
    if str(receipt.get("zip_sha256", "")).lower() != archive_hash:
        raise ReleaseGateError(
            f"mismatched archive: receipt hash {receipt.get('zip_sha256')!r}, supplied archive hash {archive_hash}"
        )
    #The three bindings that say WHICH run this is. A probe replaced a case's input and configuration file,
    #reused the unchanged observation and receipt, and this gate still returned `accepted`: hashing a receipt
    #protects the bytes inside it and never establishes what was observed.
    for key in RECEIPT.REQUIRED_BINDINGS:
        declared = receipt.get(key)
        if declared is None or str(declared).strip() == "":
            raise ReleaseGateError(f"missing binding: receipt for {case_id} declares no {key}")
        observed = observation.get(key)
        if observed is None and isinstance(observation.get("bindings"), Mapping):
            observed = observation["bindings"].get(key)
        if observed is None or str(observed).strip() == "":
            raise ReleaseGateError(f"missing binding: observation for {case_id} declares no {key}")
        if str(observed).lower() != str(declared).lower():
            raise ReleaseGateError(
                f"mismatched binding: {key} for {case_id} is {observed!r} in the observation "
                f"and {declared!r} in the receipt"
            )
    build = receipt.get("build_id")
    if not isinstance(build, Mapping) or build.get("packaged") is not True:
        raise ReleaseGateError(f"mismatched receipt: {case_id} has no packaged build id")
    if str(build.get("candidate_sha")) != candidate_sha:
        raise ReleaseGateError(f"mismatched receipt: packaged candidate for {case_id} is not {candidate_sha}")
    if build.get("factorio_branch") != branch:
        raise ReleaseGateError(f"mismatched environment: receipt build branch is not {branch}")


def _check_rates(case: Mapping[str, Any], manifest: Mapping[str, Any], observation: Mapping[str, Any]) -> None:
    scenario = manifest.get("engine_scenario")
    if not isinstance(scenario, Mapping):
        return
    expected_rates = scenario.get("expected_rates", {})
    if not isinstance(expected_rates, Mapping):
        return
    outcome = _outcome(observation)
    rates = _first(outcome, "rates", "measured_rates", "actual_rates")
    if not isinstance(rates, Mapping) or not rates:
        raise ReleaseGateError(f"rates below target: case {_case_id(case)} has no measured rates")
    tolerance = _number(_first(scenario, "allowed_discrete_error", "allowed_rate_error"))
    tolerance = 0.0 if tolerance is None else max(0.0, tolerance)
    for name, target_raw in expected_rates.items():
        target = _number(target_raw)
        actual = _number(rates.get(name))
        if target is None or actual is None:
            raise ReleaseGateError(f"rates below target: invalid rate for {name}")
        if actual < target - tolerance:
            raise ReleaseGateError(
                f"rates below target: {name} measured {actual:g}, target {target:g}"
            )


def _window_ticks(outcome: Mapping[str, Any], nested_name: str, flat_name: str) -> Any:
    if nested_name in outcome:
        window = outcome[nested_name]
        return window.get("ticks") if isinstance(window, Mapping) else None
    return outcome.get(flat_name)


def _check_timing(case: Mapping[str, Any], manifest: Mapping[str, Any], observation: Mapping[str, Any]) -> None:
    outcome = _outcome(observation)
    timed_out = _first(outcome, "timed_out", "timeout", "timedout")
    if timed_out is True:
        raise ReleaseGateError(f"invalid timing: case {_case_id(case)} timed out")
    scenario = manifest.get("engine_scenario")
    if not isinstance(scenario, Mapping):
        scenario = {}
    timings = _first(outcome, "timings", "timing", "performance")
    if not isinstance(timings, Mapping):
        raise ReleaseGateError(f"invalid timing: case {_case_id(case)} has no timing block")
    for name, value in timings.items():
        number = _number(value)
        if number is None or number < 0:
            raise ReleaseGateError(f"invalid timing: {case.get('case_id')} has non-finite {name}")

    timeout = _number(scenario.get("timeout_seconds"))
    generation_ticks = _number(timings.get("generation_ticks"))
    if timeout is not None and generation_ticks is not None and generation_ticks > timeout * 60:
        raise ReleaseGateError(
            f"invalid timing: case {_case_id(case)} took {generation_ticks:g} engine ticks, "
            f"timeout is {timeout:g}s"
        )

    wall_clock_target = _first(
        scenario, "wall_clock_seconds", "wall_clock_target_seconds", "max_wall_clock_seconds"
    )
    if wall_clock_target is not None:
        target = _number(wall_clock_target)
        measured = _number(timings.get("wall_clock_seconds"))
        if target is None or target < 0:
            raise ReleaseGateError(f"invalid timing: case {_case_id(case)} has invalid wall-clock target")
        if measured is None:
            raise ReleaseGateError(
                f"invalid timing: case {_case_id(case)} has no wall_clock_seconds measurement"
            )
        if measured > target:
            raise ReleaseGateError(
                f"invalid timing: case {_case_id(case)} took {measured:g}s, wall-clock target is {target:g}s"
            )

    for nested_name, flat_name, expected_name, minimum in (
        ("warm_up", "warm_up_ticks", "warm_up_ticks", 0.0),
        ("window", "sampling_window_ticks", "sampling_window_ticks", 1.0),
    ):
        expected = _number(scenario.get(expected_name))
        raw_observed = _window_ticks(outcome, nested_name, flat_name)
        observed = _number(raw_observed)
        if observed is None:
            raise ReleaseGateError(
                f"invalid timing: case {_case_id(case)} has no {flat_name}"
            )
        if observed < minimum or observed != math.floor(observed):
            raise ReleaseGateError(
                f"invalid timing: case {_case_id(case)} has invalid {nested_name}.ticks"
            )
        if expected is not None and observed != expected:
            raise ReleaseGateError(
                f"invalid timing: case {_case_id(case)} has {expected_name}={observed:g}, expected {expected:g}"
            )


def _expected_canonical(expected: Any) -> Any:
    if isinstance(expected, Mapping) and isinstance(expected.get("canonical"), (Mapping, list)):
        return expected["canonical"]
    return expected


def _check_input_binding(case: Mapping[str, Any], observation: Mapping[str, Any],
                         golden_root: Path) -> None:
    """Recompute the case's PreparedInput hash from disk and compare it with what was observed.

    Comparing two copies of the same declared string proves only that nobody edited the receipt. The input
    that the engine actually consumed has to be hashed again, here, from the file the case names.
    """
    named = case.get("prepared_input")
    if named in (None, ""):
        return
    path = Path(named)
    if not path.is_absolute():
        #A case names its input relative to the case root, and the same string must resolve the same way for
        #everyone who checks it.
        candidates = [Path(golden_root) / named, Path(golden_root).parent / named, Path(named)]
        path = next((option for option in candidates if option.is_file()), candidates[0])
    if not path.is_file():
        raise ReleaseGateError(
            f"absent input: case {_case_id(case)} names {named}, which is not a file"
        )
    actual = RECEIPT.file_sha256(path)
    declared = observation.get("prepared_input_sha256")
    if declared is None and isinstance(observation.get("bindings"), Mapping):
        declared = observation["bindings"].get("prepared_input_sha256")
    if str(declared).lower() != actual:
        raise ReleaseGateError(
            f"mismatched input: case {_case_id(case)} observed {declared!r}, "
            f"but {path.name} hashes to {actual}"
        )


def _check_outcome(case: Mapping[str, Any], manifest: Mapping[str, Any], expected: Any,
                   observation: Mapping[str, Any]) -> None:
    expected_kind = case.get("outcome_kind")
    observed_kind = _observed_kind(observation)
    if observed_kind == "rejection" and expected_kind != "rejection":
        raise ReleaseGateError(
            f"unexpected rejection: case {_case_id(case)} expects {expected_kind}, engine rejected it"
        )
    if observed_kind != expected_kind:
        raise ReleaseGateError(
            f"unexpected outcome: case {_case_id(case)} expects {expected_kind}, observed {observed_kind}"
        )
    outcome = _outcome(observation)
    if expected_kind == "production":
        expected_canonical = _expected_canonical(expected)
        expected_version = manifest.get("canonical_version", 1)
        expected_digest = manifest.get("canonical_sha256", manifest.get("expected_canonical_sha256"))
        if expected_digest is None and isinstance(expected, Mapping):
            candidate_digest = expected.get("canonical_sha256")
            if isinstance(candidate_digest, str):
                expected_digest = candidate_digest
        if expected_digest is None:
            expected_digest = canonical_sha256(expected_canonical)
        actual_digest = _first(outcome, "canonical_sha256", "canonical_digest")
        actual_version = _first(outcome, "canonical_version", "canonical_schema_version")
        if actual_version != expected_version or actual_digest != expected_digest:
            raise ReleaseGateError(
                f"canonical mismatch: case {_case_id(case)} has version/digest "
                f"{actual_version!r}/{actual_digest!r}, expected {expected_version!r}/{expected_digest}"
            )
        _check_rates(case, manifest, observation)
        _check_timing(case, manifest, observation)
    elif expected_kind == "rejection":
        codes = _first(outcome, "reason_codes", "reasons")
        if not isinstance(codes, list) or not codes:
            raise ReleaseGateError(f"rejection assertion missing: case {_case_id(case)} has no reason codes")
        stage = outcome.get("stage")
        if not isinstance(stage, str) or not stage:
            raise ReleaseGateError(f"rejection assertion missing: case {_case_id(case)} has no stage")
    elif expected_kind == "export":
        expected_digest = manifest.get("export_sha256", manifest.get("expected_export_sha256"))
        if expected_digest is None and isinstance(expected, Mapping):
            expected_digest = expected.get("digest", expected.get("export_sha256"))
        actual_digest = _first(
            outcome, "digest", "content_sha256", "export_sha256", "canonical_sha256"
        )
        if expected_digest is not None and actual_digest != expected_digest:
            raise ReleaseGateError(f"export mismatch: case {_case_id(case)} digest is not the offline result")
    else:
        raise ReleaseGateError(f"invalid case: unsupported outcome_kind {expected_kind!r}")


def check_case(case: Mapping[str, Any], branch: str, candidate_sha: str, archive: Path,
               evidence_root: Path = DEFAULT_EVIDENCE_ROOT,
               golden_root: Path = DEFAULT_GOLDEN_ROOT,
               expected_version: Optional[str] = None) -> Dict[str, Any]:
    case_id = _case_id(case)
    if case.get("state") == "draft":
        raise ReleaseGateError(f"draft baseline: required case {case_id} is still draft")
    if case.get("state") != "accepted":
        raise ReleaseGateError(f"invalid case: {case_id} has state {case.get('state')!r}")

    manifest, _case_root, expected = _case_manifest(case_id, Path(golden_root))
    if not archive.is_file():
        raise ReleaseGateError(f"mismatched archive: archive is missing: {archive}")
    try:
        build = RECEIPT.read_build_id(archive)
    except RECEIPT.EvidenceError as exc:
        raise ReleaseGateError(f"mismatched archive: {exc}") from exc
    if build.get("candidate_sha") != candidate_sha:
        raise ReleaseGateError(
            f"mismatched archive: packaged candidate {build.get('candidate_sha')!r}, expected {candidate_sha!r}"
        )
    if build.get("factorio_branch") != branch:
        raise ReleaseGateError(
            f"mismatched environment: packaged archive branch {build.get('factorio_branch')!r}, expected {branch!r}"
        )

    evidence_path = Path(evidence_root) / candidate_sha / branch
    observation_path = evidence_path / f"{case_id}.observation.json"
    receipt_path = evidence_path / f"{case_id}.receipt.json"
    if not observation_path.is_file():
        raise ReleaseGateError(f"missing observation: {observation_path}")
    if not receipt_path.is_file():
        raise ReleaseGateError(f"missing receipt: {receipt_path}")
    observation = _read_json(observation_path, f"observation for {case_id}")
    receipt = _read_json(receipt_path, f"receipt for {case_id}")
    if not isinstance(observation, Mapping):
        raise ReleaseGateError(f"invalid observation: {case_id} is not an object")
    if not isinstance(receipt, Mapping):
        raise ReleaseGateError(f"invalid receipt: {case_id} is not an object")
    if observation.get("schema_version") != SCHEMA_VERSION:
        raise ReleaseGateError(f"unsupported schema version: observation for {case_id}")
    observed_case = observation.get("case_id", observation.get("case"))
    if not _same_identity(observed_case, case_id):
        raise ReleaseGateError(f"absent case: observation is for {observed_case!r}, expected {case_id}")
    if observation.get("candidate_sha") != candidate_sha:
        raise ReleaseGateError(f"mismatched archive: observation candidate is not {candidate_sha}")
    _check_environment(case, observation, build, branch, expected_version)
    _check_receipt(case, observation, receipt, archive, candidate_sha, branch)
    _check_input_binding(case, observation, golden_root)
    _check_outcome(case, manifest, expected, observation)
    return {"case_id": case_id, "branch": branch, "candidate_sha": candidate_sha, "status": "accepted"}


def _git_candidate(repo: Path) -> str:
    result = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise ReleaseGateError(f"cannot resolve candidate SHA: {result.stderr.strip()}")
    return result.stdout.strip()


def run_gate(branch: str, *, matrix_path: Path = DEFAULT_MATRIX, candidate_sha: Optional[str] = None,
             archive: Optional[Path] = None, evidence_root: Path = DEFAULT_EVIDENCE_ROOT,
             golden_root: Path = DEFAULT_GOLDEN_ROOT, expected_version: Optional[str] = None,
             repo: Path = Path(".")) -> List[Dict[str, Any]]:
    matrix = load_matrix(Path(matrix_path))
    candidate = candidate_sha or _git_candidate(Path(repo))
    selected = select_cases(matrix, branch)
    if archive is None:
        raise ReleaseGateError("mismatched archive: supply the exact packaged archive used for evidence")
    results = []
    for case in selected:
        results.append(check_case(case, branch, candidate, Path(archive), evidence_root,
                                  golden_root, expected_version))
    return results


def _archive_for_branch(value: Optional[str], branch: str, candidate: str, archive_dir: Optional[Path]) -> Path:
    if value:
        return Path(value)
    if archive_dir is None:
        raise ReleaseGateError(f"mismatched archive: no archive supplied for branch {branch}")
    candidates = [
        archive_dir / f"{branch}.zip",
        archive_dir / f"{branch}-test.zip",
        archive_dir / f"{candidate}-{branch}.zip",
    ]
    found = [path for path in candidates if path.is_file()]
    if len(found) == 1:
        return found[0]
    all_zips = sorted(archive_dir.glob(f"*factorio-{branch}*.zip"))
    if not all_zips:
        all_zips = sorted(archive_dir.glob("*.zip"))
    if len(all_zips) == 1:
        return all_zips[0]
    raise ReleaseGateError(f"mismatched archive: no unique archive supplied for branch {branch}")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("branch", nargs="?", help="Factorio branch: 2.0 or 2.1")
    parser.add_argument("--release", action="store_true", help="verify both Factorio branches")
    parser.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX)
    parser.add_argument("--evidence-root", type=Path, default=DEFAULT_EVIDENCE_ROOT)
    parser.add_argument("--golden-root", type=Path, default=DEFAULT_GOLDEN_ROOT)
    parser.add_argument("--candidate", "--candidate-sha", dest="candidate")
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--archive-dir", type=Path)
    parser.add_argument("--version", dest="expected_version")
    parser.add_argument("--repo", type=Path, default=Path("."))
    return parser


def main(argv: Optional[Iterable[str]] = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.release and args.branch:
            raise ReleaseGateError("missing branch: --release takes no branch argument")
        if not args.release and not args.branch:
            raise ReleaseGateError("missing branch: specify 2.0, 2.1, or --release")
        # A release covers BOTH branches, so one --archive cannot be the exact package for either without
        # being wrong about the other. That was already the intent, but it was carried out by silently
        # replacing args.archive with None, and the run then failed with "no archive supplied for branch 2.0"
        # -- a message about a missing argument the caller had actually supplied. Refuse by name instead.
        if args.release and args.archive is not None:
            raise ReleaseGateError(
                "conflicting archive: --release verifies both branches, so it needs --archive-dir holding "
                "2.0.zip and 2.1.zip, never a single --archive. One branch's package is never valid "
                "evidence for the other")
        branches = list(SUPPORTED_BRANCHES if args.release else [args.branch])
        candidate = args.candidate or _git_candidate(args.repo)
        for branch in branches:
            archive = _archive_for_branch(
                str(args.archive) if args.archive is not None else None,
                branch, candidate, args.archive_dir,
            )
            results = run_gate(
                branch, matrix_path=args.matrix, candidate_sha=candidate, archive=archive,
                evidence_root=args.evidence_root, golden_root=args.golden_root,
                expected_version=args.expected_version, repo=args.repo,
            )
            print(f"release gate: {branch} accepted {len(results)} required case(s) for {candidate}")
        if args.release:
            print(f"release ready: both branches accepted for {candidate}")
        return 0
    except ReleaseGateError as exc:
        print(f"release refused: {exc.reason}", file=sys.stderr)
        return 2
    except (OSError, ValueError) as exc:
        print(f"release refused: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
