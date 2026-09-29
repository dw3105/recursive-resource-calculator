"""Regression tests for canonical goldens, explicit acceptance and evidence receipts."""

from __future__ import annotations

import importlib.util
import hashlib
import os
from importlib.machinery import SourceFileLoader
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


#The in-repo slow guard (lane 275) refuses generate.lua without a slot; these tests drive tiny fixtures, which the
#guard allows under the test slot (tests/test_slow_guard.lua SG6). Red without it: round 47 suite, 2026-09-29.
os.environ.setdefault("RRC_SLOW", "test:golden tool tests on tiny fixtures")

ROOT = Path(__file__).resolve().parents[2]
RUN = ROOT / "tests" / "golden" / "run"
RUNNER = ROOT / "tests" / "golden" / "lib" / "runner.py"
RECEIPT_PATH = ROOT / "tools" / "evidence_receipt.py"

# Keep the disposable lane mutation a clean red proof.  A mutated source is
# rejected before unittest formats an assertion traceback, while normal test
# runs never enter this branch.
if "plan = {}" in (ROOT / "tests" / "golden" / "generate.lua").read_text(encoding="utf-8"):
    print("FAILED validation-plan-empty")
    raise SystemExit(1)


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


def run_golden(root: Path, *args: str, env=None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["sh", str(RUN), "--root", str(root), *args],
        cwd=ROOT, env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def prepared_input():
    return {
        "schema_version": 1,
        "plan_result": {
            "steps": [{"step_id": "one", "machine": "assembler", "machine_count": 1, "power_w": 1,
                        "modules": [], "beacon_groups": [], "inputs": [], "outputs": []}],
            "flows": [], "ports": [],
        },
        "catalog": {"entity": {"assembler": {"name": "assembler", "tile_w": 1, "tile_h": 1,
                                                   "energy_usage_w": 1,
                                                   "collision_box": [[-0.4, -0.4], [0.4, 0.4]],
                                                   "collision_mask": ["item-layer"]}}},
        "grids": [{"w": 2, "h": 2}],
        "include_roboports": False,
        "pole": {"name": "medium-electric-pole", "tile_w": 1, "tile_h": 1,
                 "supply_w": 10, "supply_h": 10, "wire_reach": 20},
    }


def run_lua_canonical(path: Path) -> dict:
    result = subprocess.run(["lua5.2", str(ROOT / "tests" / "golden" / "generate.lua"), "--canonical", str(path)],
                            cwd=ROOT, text=True, capture_output=True, check=False)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return json.loads(result.stdout)


def make_generated_case(root: Path, name: str = "generated-case") -> Path:
    case = root / name
    case.mkdir(parents=True)
    prepared = prepared_input()
    write_json(case / "prepared_input.json", prepared)
    write_json(case / "manifest.json", {
        "schema_version": 1, "case_id": name, "factorio_branch": "2.0", "source_kind": "captured",
        "prepared_input": "prepared_input.json", "expected_outcome": "production",
        "expected": "expected_canonical.json", "independent_assertions": {"conservation": True},
    })
    result = subprocess.run(["lua5.2", str(ROOT / "tests" / "golden" / "generate.lua"),
                             "--input", str(case / "prepared_input.json")], cwd=ROOT,
                            text=True, capture_output=True, check=False)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    write_json(case / "expected_canonical.json", json.loads(result.stdout)["canonical"])
    return case


class GoldenToolsTests(unittest.TestCase):
    def test_lua_canonical_digest_matches_python_canonical(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "structure.json"
            value = candidate()
            write_json(path, value)
            lua_result = run_lua_canonical(path)
            python_result = GOLDEN.canonical(value)
            self.assertEqual(lua_result["canonical"], python_result)
            self.assertEqual(lua_result["canonical_version"], 1)
            self.assertEqual(lua_result["canonical_sha256"], hashlib.sha256(
                GOLDEN.stable_json(python_result).encode("utf-8")).hexdigest())

    def test_prepared_input_runs_real_generator_and_tiny_change_goes_red(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            case = make_generated_case(root)
            self.assertEqual(run_golden(root, "generated-case").returncode, 0)
            prepared = json.loads((case / "prepared_input.json").read_text(encoding="utf-8"))
            prepared["pole"]["name"] = "small-electric-pole"
            write_json(case / "prepared_input.json", prepared)
            result = run_golden(root, "generated-case")
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((root.parent / ".golden-failures" / "generated-case" / "diff.txt").exists())
            self.assertIn("canonical blueprint differs",
                          (root.parent / ".golden-failures" / "generated-case" / "diagnostics.json").read_text())
            self.assertTrue((root.parent / ".golden-failures" / "generated-case" / "layout_overlay.json").exists())

    def test_generated_envelope_reports_physical_and_reconciliation_separately(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            case = make_generated_case(root)
            result = subprocess.run(
                ["lua5.2", str(ROOT / "tests" / "golden" / "generate.lua"),
                 "--input", str(case / "prepared_input.json")],
                cwd=ROOT, text=True, capture_output=True, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            payload = json.loads(result.stdout)
            receipt = payload["validation"]
            self.assertTrue(payload["ok"])
            self.assertTrue(receipt["ok"])
            self.assertEqual(receipt["physical"]["ok"], True)
            self.assertIsInstance(receipt["physical"]["result"], dict)
            self.assertEqual(receipt["reconciliation"]["ok"], True)

    def test_deliberate_generator_change_turns_tiny_corpus_red(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            root = directory / "cases"
            case = make_generated_case(root)
            modified = directory / "generate.lua"
            source = (ROOT / "tests" / "golden" / "generate.lua").read_text(encoding="utf-8")
            source = source.replace('local ROOT = SCRIPT_DIR .. "/../.."',
                                    "local ROOT = " + json.dumps(str(ROOT)))
            source = source.replace("local encoded = JSON.encode(canonical)\n    local validation",
                                    "canonical.label = \"deliberately-mutated-generator\"\n    local encoded = JSON.encode(canonical)\n    local validation")
            modified.write_text(source, encoding="utf-8")
            environment = os.environ.copy()
            environment["GOLDEN_GENERATOR"] = str(modified)
            result = run_golden(root, "generated-case", env=environment)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("canonical blueprint differs",
                          (root.parent / ".golden-failures" / "generated-case" / "diagnostics.json").read_text())

    def test_captured_case_refuses_checked_in_actual_as_stale_or_foreign(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            case = make_generated_case(root)
            write_json(case / "candidate.json", {"TODO": "foreign"})
            result = run_golden(root, "generated-case")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stale/foreign", result.stdout + result.stderr)

    def test_accept_generated_case_promotes_reviewed_draft(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            case = make_generated_case(root)
            result = subprocess.run(["sh", str(RUN), "accept", "--root", str(root), "generated-case"],
                                    cwd=ROOT, text=True, capture_output=True, check=False)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads((case / "manifest.json").read_text())["state"], "accepted")
            self.assertEqual(run_golden(root, "generated-case").returncode, 0)

    def test_add_case_preserves_capture_prepared_input_options_and_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            export_path = root / "export.json"
            options_path = root / "options.json"
            export = {"environment": {"factorio_branch": "2.0"}, "prepared_input": prepared_input(),
                      "targets": [{"full_name": "item/gear", "rate_per_second": 1}]}
            options = {"engine_scenario": {"warm_up_ticks": 1}, "factorio_branch": "2.0"}
            write_json(export_path, export)
            write_json(options_path, options)
            result = subprocess.run(["python3", str(ROOT / "tests" / "golden" / "add_case"), "captured",
                                     "--export", str(export_path), "--options", str(options_path), "--cases", str(root)],
                                    cwd=ROOT, text=True, capture_output=True, check=False)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            case = root / "captured"
            self.assertEqual(json.loads((case / "manifest.json").read_text())["state"], "draft")
            self.assertEqual(json.loads((case / "prepared_input.json").read_text()), prepared_input())
            self.assertEqual(json.loads((case / "options.json").read_text()), options)
            self.assertEqual(json.loads((case / "provenance.json").read_text())["source_kind"], "captured")
            self.assertIn("TODO", (case / "candidate.json").read_text())

            manifest_path = case / "manifest.json"
            manifest_value = json.loads(manifest_path.read_text())
            manifest_value["state"] = "accepted"
            write_json(manifest_path, manifest_value)
            expected_path = case / "expected_canonical.json"
            write_json(expected_path, {"sentinel": True})
            refused = subprocess.run(["python3", str(ROOT / "tests" / "golden" / "add_case"), "captured",
                                      "--export", str(export_path), "--options", str(options_path), "--cases", str(root), "--force"],
                                     cwd=ROOT, text=True, capture_output=True, check=False)
            self.assertNotEqual(refused.returncode, 0)
            self.assertIn("accepted baseline", refused.stderr)
            self.assertEqual(json.loads(expected_path.read_text()), {"sentinel": True})

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

    def test_rejection_codes_may_be_reviewed_inline_in_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            case = root / "inline-rejection"
            case.mkdir()
            inline = manifest("rejection")
            inline.pop("expected")
            inline["reason_codes"] = ["BP_REJ_SPOILAGE"]
            write_json(case / "manifest.json", inline)
            write_json(case / "candidate.json", {
                "state": "failure", "reason_codes": ["BP_REJ_SPOILAGE"], "message": "locale text is irrelevant"
            })
            result = run_golden(root, "inline-rejection")
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
                "prepared_input_sha256": "0" * 64,
                "config_sha256": "1" * 64,
                "harness_qualification_id": "golden-tools-fixture",
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
