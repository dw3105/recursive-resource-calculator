"""Regression tests for canonical goldens, explicit acceptance and evidence receipts."""

from __future__ import annotations

import importlib.util
from importlib.machinery import SourceFileLoader
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RUN = ROOT / "tests" / "golden" / "run"
RUNNER = ROOT / "tests" / "golden" / "lib" / "runner.py"
RECEIPT_PATH = ROOT / "tools" / "evidence_receipt.py"


def load_module(path: Path, name: str):
    loader = SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


GOLDEN = load_module(RUNNER, "rrc_test_golden_run")
RECEIPT = load_module(RECEIPT_PATH, "rrc_test_evidence_receipt")


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def candidate(direction: int = 4, quality: str = "legendary", first_number: int = 17,
              second_number: int = 91):
    return {
        "blueprint": {
            "label": "tool-case",
            "entities": [
                {
                    "id": "r:belt",
                    "entity_number": second_number,
                    "name": "transport-belt",
                    "position": {"x": 11, "y": 20},
                    "direction": direction,
                },
                {
                    "id": "m:machine",
                    "entity_number": first_number,
                    "name": "assembling-machine-2",
                    "position": {"x": 10.5, "y": 19.5},
                    "recipe": "iron-gear-wheel",
                    "modules": [{"name": "speed-module-2", "quality": quality, "count": 1}],
                },
            ],
        }
    }


def manifest(outcome: str = "production"):
    return {
        "schema_version": 1,
        "case_id": "tool-case",
        "factorio_branch": "2.0",
        "expected_outcome": outcome,
        "expected": "expected_canonical.json" if outcome == "production" else "expected.json",
        "actual": "candidate.json",
        "independent_assertions": {
            "required_entities": ["transport-belt", "assembling-machine-2"],
            "entity_counts": {"transport-belt": 1, "assembling-machine-2": 1},
        },
        "engine_scenario": {
            "initial_state": {}, "supply": [], "drain": [], "warm_up_ticks": 1,
            "sampling_window_ticks": 2, "expected_rates": {},
            "allowed_discrete_error": 0.01, "timeout_seconds": 1,
        },
    }


def make_case(root: Path, name: str = "tool-case", actual=None, expected=None, outcome="production") -> Path:
    case = root / name
    case.mkdir(parents=True)
    actual = actual if actual is not None else candidate()
    write_json(case / "manifest.json", manifest(outcome))
    write_json(case / "candidate.json", actual)
    if outcome == "production":
        expected = expected if expected is not None else GOLDEN.canonical(actual)
        write_json(case / "expected_canonical.json", expected)
    else:
        write_json(case / "expected.json", expected or {"reason_codes": ["BP_REJ_CYCLE"]})
    return case


def run_golden(root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["sh", str(RUN), "--root", str(root), *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


class GoldenToolsTests(unittest.TestCase):
    def test_matching_case_passes_and_renumbering_is_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            make_case(root)
            self.assertEqual(run_golden(root, "tool-case").returncode, 0)
            write_json(root / "tool-case" / "candidate.json", candidate(first_number=800, second_number=12))
            result = run_golden(root, "tool-case")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_direction_or_module_quality_is_canonical_and_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            make_case(root)
            write_json(root / "tool-case" / "candidate.json", candidate(direction=12))
            result = run_golden(root, "tool-case")
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue((root.parent / ".golden-failures" / "tool-case" / "diff.txt").exists())
            write_json(root / "tool-case" / "candidate.json", candidate(quality="epic"))
            self.assertNotEqual(run_golden(root, "tool-case").returncode, 0)

    def test_rejection_compares_codes_not_message_text(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            actual = {"state": "failure", "message": "rewritten locale text", "reason_codes": ["BP_REJ_CYCLE"]}
            make_case(root, outcome="rejection", actual=actual)
            result = run_golden(root, "tool-case")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_accept_changes_only_the_named_expectation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            case_a = make_case(root, "tool-case")
            case_b = make_case(root, "other-case")
            before_b = (case_b / "expected_canonical.json").read_bytes()
            write_json(case_a / "candidate.json", candidate(direction=12))
            result = subprocess.run(
                ["sh", str(RUN), "accept", "--root", str(root), "tool-case"],
                cwd=ROOT, text=True, capture_output=True, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotEqual(json.loads((case_a / "expected_canonical.json").read_text()),
                                GOLDEN.canonical(candidate()))
            self.assertEqual((case_b / "expected_canonical.json").read_bytes(), before_b)
            self.assertTrue((root.parent / ".golden-failures" / "accept" / "tool-case" / "diff.txt").exists())

    def test_normal_run_never_rewrites_expectation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            case = make_case(root)
            write_json(case / "candidate.json", candidate(direction=12))
            before = (case / "expected_canonical.json").read_bytes()
            stamp = (case / "expected_canonical.json").stat().st_mtime_ns
            self.assertNotEqual(run_golden(root, "tool-case").returncode, 0)
            self.assertEqual((case / "expected_canonical.json").read_bytes(), before)
            self.assertEqual((case / "expected_canonical.json").stat().st_mtime_ns, stamp)

    def _archive(self, directory: Path, packaged: bool = True) -> Path:
        archive = directory / ("candidate.zip" if packaged else "development.zip")
        build = "return {candidate_sha = \"abc123\", mod_version = \"1.1.36\", factorio_branch = \"2.0\", packaged = " + ("true" if packaged else "false") + "}\n"
        with zipfile.ZipFile(archive, "w") as package:
            package.writestr("RRC-Fork/logic/build_id.lua", build)
        return archive

    def test_receipt_refuses_hash_candidate_case_and_development_build(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            archive = self._archive(directory)
            observation = {
                "case": "tool-case", "candidate_sha": "abc123",
                "environment": {"factorio_branch": "2.0"},
                "outcome": {"kind": "production"},
            }
            receipt = RECEIPT.make_receipt(observation, archive, expected_case="tool-case", expected_candidate="abc123")
            self.assertEqual(receipt["zip_sha256"], RECEIPT.zip_sha256(archive))
            for changed in (
                {**observation, "zip_sha256": "0" * 64},
                {**observation, "candidate_sha": "wrong"},
                {**observation, "case": "other-case"},
            ):
                with self.assertRaises(RECEIPT.EvidenceError):
                    RECEIPT.make_receipt(changed, archive, expected_case="tool-case", expected_candidate="abc123")
            with self.assertRaises(RECEIPT.EvidenceError):
                RECEIPT.make_receipt(observation, self._archive(directory, packaged=False))


if __name__ == "__main__":
    unittest.main()
