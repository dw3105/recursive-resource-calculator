"""Cheap fail-closed tests for the release gate.

Every test owns its own tiny packaged archive.  The evidence is deliberately
filed below a temporary fixture directory, never below docs/engine-evidence.
"""

from __future__ import annotations

import importlib.util
import json
import copy
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
PRODUCTION_EXAMPLE = json.loads(
    (ROOT / "docs" / "engine-evidence" / "examples" / "production.json").read_text(encoding="utf-8")
)


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
            f'return {{candidate_sha = "{self.candidate}", mod_version = "{self.version}", '
            f'factorio_branch = "{self.branch}", packaged = true}}\n'
        )
        with zipfile.ZipFile(self.archive, "w", compression=zipfile.ZIP_STORED) as package:
            package.writestr(f"RRC-Fork_{self.version}/logic/build_id.lua", build_id)
            package.writestr("RRC-Fork_1.1.99/TEST_BUILD.txt", "fixture test build\n")

    def observation(self, **changes):
        production = copy.deepcopy(PRODUCTION_EXAMPLE["production"])
        production.update({
            "canonical_sha256": GATE.canonical_sha256(self.expected),
            "canonical_version": 1,
            "rates": {"item/stone-brick": 1.0},
            "warm_up": {"ticks": 5, "start_tick": 100, "end_tick": 104},
            "window": {"ticks": 10, "start_tick": 105, "end_tick": 114},
            "timings": {
                "generation_ticks": 18,
                "sampling_ticks": 10,
                "warm_up_ticks": 5,
                "wall_clock_seconds": 2.0,
            },
        })
        observation = {
            "schema_version": 1,
            "case_id": self.case_id,
            "outcome_kind": "production",
            "factorio_branch": self.branch,
            "factorio_version": f"{self.branch}.77",
            "candidate_sha": self.candidate,
            "runner_revision": "fixture-runner",
            "engine_version": f"{self.branch}.77",
            "active_mods": [{"name": "base", "version": f"{self.branch}.77"}],
            "mods": [{"name": "base", "version": f"{self.branch}.77"}],
            "force": "player",
            "surface": "nauvis",
            "environment": {
                "factorio_branch": self.branch,
                "mod_version": self.version,
                "active_mods": ["base"],
            },
            "production": production,
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
                rejection={"stage": "preflight", "reason_codes": ["BP_REJ_FIXTURE"]},
            )
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(GATE.ReleaseGateError, "unexpected rejection"):
                fixture.run()

    def test_rates_below_target_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            observation["production"]["rates"]["item/stone-brick"] = 0.1
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(GATE.ReleaseGateError, "rates below target"):
                fixture.run()

    def test_surplus_rate_is_accepted(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            observation["production"]["rates"]["item/stone-brick"] = 1.5
            fixture.file_evidence(observation)
            self.assertEqual(fixture.run()[0]["status"], "accepted")

    def test_every_simultaneous_target_has_its_own_lower_bound(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.manifest["engine_scenario"]["expected_rates"] = {
                "item/stone-brick": 1.0,
                "item/iron-gear-wheel": 2.0,
            }
            fixture.prepare()
            observation = fixture.observation()
            observation["production"]["rates"] = {
                "item/stone-brick": 1.0,
                "item/iron-gear-wheel": 1.5,
            }
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(
                GATE.ReleaseGateError,
                r"rates below target: item/iron-gear-wheel measured 1\.5, target 2",
            ):
                fixture.run()

    def test_missing_or_empty_rate_data_is_refused(self):
        for empty_rates in (None, {}):
            temp, fixture = self.fixture()
            with temp:
                fixture.prepare()
                observation = fixture.observation()
                if empty_rates is None:
                    del observation["production"]["rates"]
                else:
                    observation["production"]["rates"] = empty_rates
                fixture.file_evidence(observation)
                with self.subTest(empty_rates=empty_rates):
                    with self.assertRaisesRegex(GATE.ReleaseGateError, "has no measured rates"):
                        fixture.run()

    def test_missing_or_invalid_window_is_refused(self):
        mutations = (
            lambda production: production.pop("window"),
            lambda production: production.update(window={"ticks": "not-a-number"}),
            lambda production: production.update(warm_up={"ticks": -1}),
        )
        for mutate in mutations:
            temp, fixture = self.fixture()
            with temp:
                fixture.prepare()
                observation = fixture.observation()
                mutate(observation["production"])
                fixture.file_evidence(observation)
                with self.subTest(mutate=mutate):
                    with self.assertRaisesRegex(GATE.ReleaseGateError, "invalid timing"):
                        fixture.run()

    def test_wall_clock_target_requires_wall_clock_measurement(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.manifest["engine_scenario"]["wall_clock_seconds"] = 3
            fixture.prepare()
            observation = fixture.observation()
            del observation["production"]["timings"]["wall_clock_seconds"]
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(GATE.ReleaseGateError, "wall_clock_seconds"):
                fixture.run()

    def test_flat_window_names_remain_accepted_as_synonyms(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            production = observation["production"]
            production["warm_up_ticks"] = production.pop("warm_up")["ticks"]
            production["sampling_window_ticks"] = production.pop("window")["ticks"]
            fixture.file_evidence(observation)
            self.assertEqual(fixture.run()[0]["status"], "accepted")

    def test_outcome_is_kept_as_a_legacy_synonym(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            observation["outcome"] = observation.pop("production")
            fixture.file_evidence(observation)
            self.assertEqual(fixture.run()[0]["status"], "accepted")

    def test_canonical_digest_mismatch_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            observation["production"]["canonical_sha256"] = "wrong-digest"
            fixture.file_evidence(observation)
            with self.assertRaisesRegex(GATE.ReleaseGateError, "canonical mismatch"):
                fixture.run()

    def test_missing_21_evidence_blocks_readiness(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.branch = "2.1"
            fixture.version = "1.1.99"
            fixture.prepare(branches=["2.1"])
            evidence_path = fixture.evidence / fixture.candidate / fixture.branch
            (evidence_path / f"{fixture.case_id}.observation.json").unlink()
            with self.assertRaisesRegex(GATE.ReleaseGateError, "missing observation"):
                fixture.run()

    def test_examples_use_one_named_producer_outcome_block(self):
        for name in ("production", "rejection", "export"):
            example = json.loads(
                (ROOT / "docs" / "engine-evidence" / "examples" / f"{name}.json")
                .read_text(encoding="utf-8")
            )
            self.assertEqual(example["outcome_kind"], name)
            self.assertIn(name, example)
            self.assertIn("Synthetic example", example["note"])

    def test_invalid_timing_has_its_own_refusal(self):
        temp, fixture = self.fixture()
        with temp:
            fixture.prepare()
            observation = fixture.observation()
            observation["production"]["timed_out"] = True
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
