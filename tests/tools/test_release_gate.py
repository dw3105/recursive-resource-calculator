"""Cheap fail-closed tests for the release gate.

Every test owns its own tiny packaged archive.  The evidence is deliberately
filed below a temporary fixture directory, never below docs/engine-evidence.
"""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


GATE = load_module(ROOT / "tools" / "release_gate.py", "rrc_test_release_gate")
RECEIPT = load_module(ROOT / "tools" / "evidence_receipt.py", "rrc_test_release_receipt")


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


class ReleaseGateFixture:
    candidate = "fixture-candidate-sha"
    branch = "2.0"
    version = "1.1.99"
    case_id = "fixture-production"

    def __init__(self, root: Path):
        self.root = root
        self.matrix = root / "required-matrix.json"
        self.golden = root / "golden" / "cases"
        self.evidence = root / "fixture-evidence"
        self.archive = root / "fixture-test-build.zip"
        expected = {"blueprint": {"entities": [{"name": "stone-furnace", "position": {"x": 0, "y": 0}}]}}
        self.expected = expected
        self.manifest = {
            "schema_version": 1,
            "case_id": self.case_id,
            "factorio_branch": self.branch,
            "canonical_version": 1,
            "engine_scenario": {
                "initial_state": {},
                "supply": [],
                "drain": [],
                "warm_up_ticks": 5,
                "sampling_window_ticks": 10,
                "expected_rates": {"item/stone-brick": 1.0},
                "allowed_discrete_error": 0.01,
                "timeout_seconds": 10,
            },
            "expected_outcome": "production",
            "expected": "expected_canonical.json",
        }

    def make_matrix(self, **changes):
        case = {
            "case_id": self.case_id,
            "branches": [self.branch],
            "mods": ["base"],
            "outcome_kind": "production",
            "clauses": ["FIXTURE-01"],
            "state": "accepted",
            "prepared_input": None,
        }
        case.update(changes)
        write_json(self.matrix, {"schema_version": 1, "cases": [case]})

    def make_archive(self):
        build_id = (
            'return {candidate_sha = "fixture-candidate-sha", mod_version = "1.1.99", '
            'factorio_branch = "2.0", packaged = true}\n'
        )
        with zipfile.ZipFile(self.archive, "w", compression=zipfile.ZIP_STORED) as package:
            package.writestr("RRC-Fork_1.1.99/logic/build_id.lua", build_id)
            package.writestr("RRC-Fork_1.1.99/TEST_BUILD.txt", "fixture test build\n")

    def observation(self, **changes):
        outcome = {
            "canonical_sha256": GATE.canonical_sha256(self.expected),
            "canonical_version": 1,
            "rates": {"item/stone-brick": 1.0},
            "warm_up_ticks": 5,
            "sampling_window_ticks": 10,
            "timings": {"generation_seconds": 1.0, "elapsed_seconds": 2.0},
        }
        observation = {
            "schema_version": 1,
            "case_id": self.case_id,
            "outcome_kind": "production",
            "candidate_sha": self.candidate,
            "runner_revision": "fixture-runner",
            "engine_version": "2.0.77",
            "active_mods": ["base"],
            "force_research": [],
            "surface": "nauvis",
            "environment": {
                "factorio_branch": self.branch,
                "mod_version": self.version,
                "active_mods": ["base"],
            },
            "outcome": outcome,
        }
        observation.update(changes)
        return observation

    def file_evidence(self, observation=None):
        observation = observation or self.observation()
        path = self.evidence / self.candidate / self.branch
        write_json(path / f"{self.case_id}.observation.json", observation)
        receipt = RECEIPT.make_receipt(
            observation, self.archive, expected_case=self.case_id, expected_candidate=self.candidate
        )
        write_json(path / f"{self.case_id}.receipt.json", receipt)

    def prepare(self, **case_changes):
        self.make_matrix(**case_changes)
        self.golden_case = self.golden / self.case_id
        write_json(self.golden_case / "manifest.json", self.manifest)
        write_json(self.golden_case / "expected_canonical.json", self.expected)
        self.make_archive()
        self.file_evidence()

    def run(self, branch=None, archive=None):
        return GATE.run_gate(
            branch or self.branch,
            matrix_path=self.matrix,
            candidate_sha=self.candidate,
            archive=archive or self.archive,
            evidence_root=self.evidence,
            golden_root=self.golden,
            expected_version=self.version,
        )


class ReleaseGateTests(unittest.TestCase):
    def fixture(self):
        temp = tempfile.TemporaryDirectory()
        fixture = ReleaseGateFixture(Path(temp.name))
        return temp, fixture

    def test_valid_synthetic_fixture_passes_without_touching_engine_evidence(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            self.assertEqual(fixture.run()[0]["status"], "accepted")
            self.assertFalse((ROOT / "docs" / "engine-evidence" / fixture.candidate).exists())

    def test_draft_baseline_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare(state="draft")
            with self.assertRaisesRegex(GATE.ReleaseGateError, "draft baseline"):
                fixture.run()

    def test_wrong_archive_hash_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            with fixture.archive.open("ab") as stream:
                stream.write(b"changed after receipt")
            with self.assertRaisesRegex(GATE.ReleaseGateError, "mismatched archive"):
                fixture.run()

    def test_missing_branch_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            with self.assertRaisesRegex(GATE.ReleaseGateError, "missing branch"):
                GATE.run_gate(
                    None,
                    matrix_path=fixture.matrix,
                    candidate_sha=fixture.candidate,
                    archive=fixture.archive,
                    evidence_root=fixture.evidence,
                    golden_root=fixture.golden,
                    expected_version=fixture.version,
                )

    def test_empty_selection_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare(branches=["2.1"])
            with self.assertRaisesRegex(GATE.ReleaseGateError, "empty selection"):
                fixture.run()

    def test_absent_case_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.make_matrix()
            with self.assertRaisesRegex(GATE.ReleaseGateError, "absent case"):
                fixture.run()

    def test_unsupported_schema_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            write_json(fixture.matrix, {"schema_version": 99, "cases": []})
            with self.assertRaisesRegex(GATE.ReleaseGateError, "unsupported schema version"):
                fixture.run()

    def test_missing_observation_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.make_matrix()
            fixture.golden_case = fixture.golden / fixture.case_id
            write_json(fixture.golden_case / "manifest.json", fixture.manifest)
            write_json(fixture.golden_case / "expected_canonical.json", fixture.expected)
            fixture.make_archive()
            with self.assertRaisesRegex(GATE.ReleaseGateError, "missing observation"):
                fixture.run()

    def test_missing_receipt_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            (fixture.evidence / fixture.candidate / fixture.branch / f"{fixture.case_id}.receipt.json").unlink()
            with self.assertRaisesRegex(GATE.ReleaseGateError, "missing receipt"):
                fixture.run()

    def test_unexpected_rejection_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation(
                outcome_kind="rejection",
                outcome={"stage": "preflight", "reason_codes": ["BP_REJ_FIXTURE"]},
            )
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(GATE.ReleaseGateError, "unexpected rejection"):
                fixture.run()

    def test_rates_below_target_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            observation["outcome"]["rates"]["item/stone-brick"] = 0.1
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(GATE.ReleaseGateError, "rates below target"):
                fixture.run()

    def test_invalid_timing_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            observation["outcome"]["timed_out"] = True
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(GATE.ReleaseGateError, "invalid timing"):
                fixture.run()

    def test_mismatched_environment_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            observation["engine_version"] = "2.1.19"
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(GATE.ReleaseGateError, "mismatched environment"):
                fixture.run()


if __name__ == "__main__":
    unittest.main()
