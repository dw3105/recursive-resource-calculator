#!/usr/bin/env python3
"""Create a host-side receipt for one observation from the packaged engine test API.

The observation is evidence about a particular case, candidate and environment.  This
tool deliberately does not trust the observation for archive identity: it hashes the
archive it was handed and reads the packaged build id from that archive.  A source
checkout has no build id and is therefore never eligible for a receipt.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path
from typing import Any, Dict, Iterable, Mapping, Optional


class EvidenceError(Exception):
    """A deliberate refusal to file evidence."""


def _json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def zip_sha256(archive: Path) -> str:
    digest = hashlib.sha256()
    try:
        with archive.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
    except OSError as exc:
        raise EvidenceError(f"cannot read archive {archive}: {exc}") from exc
    return digest.hexdigest()


def _build_id_text(archive: Path) -> str:
    try:
        with zipfile.ZipFile(archive) as package:
            names = package.namelist()
            matches = [name for name in names if name.rstrip("/").endswith("logic/build_id.lua")]
            if len(matches) != 1:
                raise EvidenceError("tested archive does not contain exactly one logic/build_id.lua")
            return package.read(matches[0]).decode("utf-8")
    except zipfile.BadZipFile as exc:
        raise EvidenceError(f"tested archive is not a zip: {exc}") from exc
    except KeyError as exc:
        raise EvidenceError("tested archive has no packaged build id") from exc


def read_build_id(archive: Path) -> Dict[str, Any]:
    text = _build_id_text(archive)
    result: Dict[str, Any] = {}
    for key in ("candidate_sha", "mod_version", "factorio_branch"):
        match = re.search(r"\b" + re.escape(key) + r"\s*=\s*([\"'])(.*?)\1", text)
        if match:
            result[key] = match.group(2)
    packaged = re.search(r"\bpackaged\s*=\s*(true|false)", text)
    result["packaged"] = bool(packaged and packaged.group(1) == "true")
    if not result["packaged"]:
        raise EvidenceError("development checkout is not eligible for engine evidence")
    if not result.get("candidate_sha"):
        raise EvidenceError("packaged build id has no candidate_sha")
    return result


def _read_json(value: str, label: str) -> Any:
    if value == "-":
        try:
            return json.load(sys.stdin)
        except json.JSONDecodeError as exc:
            raise EvidenceError(f"{label} is not valid JSON: {exc}") from exc
    path = Path(value)
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise EvidenceError(f"cannot read {label} {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise EvidenceError(f"{label} {path} is not valid JSON: {exc}") from exc


def _identity(value: Any) -> Any:
    """Make case/environment values comparable without changing their receipt shape."""
    if isinstance(value, Mapping):
        for key in ("id", "case_id", "name", "slug"):
            if key in value and isinstance(value[key], (str, int)):
                return value[key]
    return value


def _environment_matches(observed: Any, expected: Any, build: Mapping[str, Any]) -> bool:
    if expected is not None:
        if isinstance(expected, str) and isinstance(observed, Mapping):
            branch = observed.get("factorio_branch", observed.get("factorio", observed.get("branch")))
            if branch is not None:
                return branch == expected
        return _json(observed) == _json(expected)

    # The archive's build id is the authoritative minimum environment.  Extra
    # observation fields (mods, force, research, surface) are retained but cannot
    # be inferred from the zip and are not silently compared to absent data.
    if not isinstance(observed, Mapping):
        return True
    for key in ("factorio_branch", "mod_version"):
        if key in observed and observed[key] != build.get(key):
            return False
    return True


def _observation_case(observation: Mapping[str, Any]) -> Any:
    return observation.get("case", observation.get("case_id", observation.get("fixture")))


def _observation_candidate(observation: Mapping[str, Any]) -> Optional[str]:
    candidate = observation.get("candidate_sha")
    if candidate is not None:
        return str(candidate)
    build = observation.get("build_id")
    if isinstance(build, Mapping) and build.get("candidate_sha") is not None:
        return str(build["candidate_sha"])
    return None


def make_receipt(
    observation: Mapping[str, Any],
    archive: Path,
    *,
    expected_case: Any = None,
    expected_candidate: Optional[str] = None,
    expected_environment: Any = None,
) -> Dict[str, Any]:
    """Validate and return a receipt; no output is written before all checks pass."""

    if not isinstance(observation, Mapping):
        raise EvidenceError("observation must be a JSON object")
    build = read_build_id(archive)
    observed_build = observation.get("build_id")
    if isinstance(observed_build, Mapping) and observed_build.get("packaged") is not True:
        raise EvidenceError("observation came from a development checkout")
    if observation.get("packaged") is False:
        raise EvidenceError("observation came from a development checkout")
    observed_case = _observation_case(observation)
    if expected_case is not None and _identity(observed_case) != _identity(expected_case):
        raise EvidenceError(f"case mismatch: observation={observed_case!r}, expected={expected_case!r}")
    if observed_case is None:
        raise EvidenceError("observation has no case")

    observed_candidate = _observation_candidate(observation)
    if observed_candidate != build["candidate_sha"]:
        raise EvidenceError(
            f"candidate mismatch: observation={observed_candidate!r}, archive={build['candidate_sha']!r}"
        )
    if expected_candidate is not None and str(expected_candidate) != build["candidate_sha"]:
        raise EvidenceError(
            f"candidate mismatch: expected={expected_candidate!r}, archive={build['candidate_sha']!r}"
        )

    observed_environment = observation.get("environment", observation.get("env", {}))
    if not _environment_matches(observed_environment, expected_environment, build):
        raise EvidenceError("environment mismatch")

    computed_hash = zip_sha256(archive)
    declared_hash = observation.get("zip_sha256")
    if declared_hash is not None and str(declared_hash).lower() != computed_hash:
        raise EvidenceError("zip hash mismatch: observation does not describe the archive supplied")

    # Keep the original observation intact for auditability, but add the host-owned
    # facts at the top level.  The archive hash is always computed above.
    return {
        "schema_version": 1,
        "case": observed_case,
        "candidate_sha": build["candidate_sha"],
        "environment": observed_environment,
        "zip_sha256": computed_hash,
        "build_id": dict(build),
        "observation": dict(observation),
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("observation", nargs="?", help="observation JSON path, or - for stdin")
    parser.add_argument("archive", nargs="?", help="tested packaged zip")
    parser.add_argument("-o", "--output", "--receipt", dest="output", help="receipt JSON path (default: stdout)")
    parser.add_argument("--observation", dest="observation_option", help="observation JSON path")
    parser.add_argument("--archive", dest="archive_option", help="tested packaged zip")
    parser.add_argument("--case", dest="case", help="expected stable case id")
    parser.add_argument("--candidate", dest="candidate", help="expected candidate SHA")
    parser.add_argument(
        "--environment", dest="environment", help="expected environment id or JSON file/object"
    )
    return parser


def _environment_argument(value: Optional[str]) -> Any:
    if value is None:
        return None
    path = Path(value)
    if path.is_file():
        return _read_json(value, "environment")
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return value


def main(argv: Optional[Iterable[str]] = None) -> int:
    args = _parser().parse_args(argv)
    observation_name = args.observation_option or args.observation
    archive_name = args.archive_option or args.archive
    if not observation_name or not archive_name:
        _parser().error("an observation JSON and tested archive are required")
    try:
        observation = _read_json(observation_name, "observation")
        receipt = make_receipt(
            observation,
            Path(archive_name),
            expected_case=args.case,
            expected_candidate=args.candidate,
            expected_environment=_environment_argument(args.environment),
        )
        encoded = json.dumps(receipt, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
        if args.output:
            output = Path(args.output)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(encoded, encoding="utf-8")
        else:
            sys.stdout.write(encoded)
        return 0
    except EvidenceError as exc:
        print(f"evidence refused: {exc}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"evidence refused: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
