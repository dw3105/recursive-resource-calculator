import base64
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
ADD_CASE = ROOT / "tests" / "golden" / "add_case"
RUNNER_PATH = ROOT / "tests" / "golden" / "lib" / "runner.py"


def load_runner():
    spec = importlib.util.spec_from_file_location("rrc_capture_workflow_runner", RUNNER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {RUNNER_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def encode_export(value):
    text = json.dumps(value, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return base64.b64encode(zlib.compress(text)).decode("ascii")


def prepared_input():
    return {
        "schema_version": 1,
        "snapshot": {"sheet_id": "capture-sheet", "targets": [{"full_name": "item/gear", "rate": 1.2345678901234567}]},
        "solver_result": {"rate": 0.00000000012345678},
        "catalog": {"entity": {"assembler": {"tile_w": 1}}},
        "settings": {"input_edge": "left"},
        "options": {"round_up": True},
        "revisions": {"sheet": 7, "config": 3},
        "surface": "nauvis",
        "force": "player-force",
    }


def capture_export(source_kind="runtime", provenance=None, source_export="debug-export"):
    prepared = prepared_input()
    prepared["source_export"] = source_export
    return {
        "format": "rrc-sheet-debug",
        "schema_version": 1,
        "environment": {"factorio_branch": "2.0", "mod_version": "1.1.10"},
        "prepared_input": prepared,
        "source_kind": source_kind,
        "provenance": provenance or {
            "candidate_sha": "candidate-sha",
            "mod_version": "1.1.10",
            "factorio_branch": "2.0",
            "packaged": True,
            "sheet_revision": 7,
            "config_revision": 3,
            "terminal_outcome": "success",
        },
        "source_export": source_export,
    }


#Acceptance requires BOTH validation layers, per contract 26.7: identity reconciliation and physical
#validation, neither standing in for the other. A stub payload carrying only entities is refused, which is
#the point of the rule, so the generator mock has to speak the real evidence contract.
GENERATED_PAYLOAD = {
    "result": {"entities": []},
    "validation": {
        "ok": True,
        "physical": {"ok": True, "result": {"ok": True, "errors": []}},
        "reconciliation": {"ok": True, "errors": []},
    },
}


class CaptureWorkflowTests(unittest.TestCase):
    def add_case(self, root, export, options=None, encoded=True, case_id="capture"):
        export_path = root / (case_id + (".txt" if encoded else ".json"))
        if encoded:
            export_path.write_text(encode_export(export) + "\n", encoding="utf-8")
        else:
            export_path.write_text(json.dumps(export), encoding="utf-8")
        options_path = root / "options.json"
        options_path.write_text(json.dumps(options or {"factorio_branch": "2.0"}), encoding="utf-8")
        return subprocess.run(
            ["python3", str(ADD_CASE), case_id, "--export", str(export_path), "--options", str(options_path),
             "--cases", str(root / "cases")],
            cwd=ROOT, text=True, capture_output=True, check=False,
        )

    def write_matrix(self, root, rows):
        (root / "required-matrix.json").write_text(
            json.dumps({"schema_version": 1, "cases": rows}, indent=2) + "\n", encoding="utf-8"
        )

    def write_case(self, root, case_id, state="captured", source_kind="runtime", prepared=True,
                   packaged=True, options=None, expected=True):
        case = root / "cases" / case_id
        case.mkdir(parents=True, exist_ok=True)
        manifest = {
            "schema_version": 1,
            "case_id": case_id,
            "factorio_branch": "2.0",
            "state": state,
            "source_kind": source_kind,
            "expected_outcome": "production",
            "expected": "expected_canonical.json",
            "actual": "candidate.json",
            "prepared_input": "prepared_input.json" if prepared else None,
        }
        (case / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        if prepared:
            prepared_value = {
                "schema_version": 1,
                "source_kind": source_kind,
                "provenance": {
                    "candidate_sha": "fixture-candidate",
                    "packaged": packaged,
                    "factorio_branch": "2.0",
                },
                "options": options or {},
            }
            (case / "prepared_input.json").write_text(
                json.dumps(prepared_value, indent=2) + "\n", encoding="utf-8"
            )
            (case / "provenance.json").write_text(json.dumps({
                "candidate_sha": "fixture-candidate",
                "packaged": packaged,
                "source_kind": source_kind,
            }, indent=2) + "\n", encoding="utf-8")
        else:
            (case / "candidate.json").write_text('{"entities": []}\n', encoding="utf-8")
        if expected:
            (case / "expected_canonical.json").write_text('{"entities": []}\n', encoding="utf-8")
        return case

    @staticmethod
    def matrix_row(case_id, state="captured", branches=None):
        return {
            "case_id": case_id,
            "branches": branches or ["2.0"],
            "mods": ["base"],
            "outcome_kind": "production",
            "clauses": ["FIXTURE"],
            "state": state,
            "prepared_input": "prepared_input.json" if state == "captured" else None,
        }

    def test_runtime_capture_round_trips_and_files_a_draft(self):
        export = capture_export()
        encoded = encode_export(export)
        decoded = json.loads(zlib.decompress(base64.b64decode(encoded)).decode("utf-8"))
        self.assertEqual(decoded, export)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.add_case(root, export)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            case = root / "cases" / "capture"
            manifest = json.loads((case / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["source_kind"], "runtime")
            self.assertEqual(manifest["supported_outcome"], "production")
            self.assertEqual(manifest["expected_outcome"], "production")
            self.assertEqual(manifest["state"], "draft")
            self.assertEqual(json.loads((case / "prepared_input.json").read_text()), export["prepared_input"])
            self.assertFalse((case / "expected_canonical.json").exists())

    def test_failed_search_capture_is_reproducible_and_keeps_production_support(self):
        export = capture_export(provenance={
            "candidate_sha": "candidate-sha",
            "mod_version": "1.1.10",
            "factorio_branch": "2.0",
            "packaged": True,
            "sheet_revision": 7,
            "config_revision": 3,
            "terminal_outcome": "failure",
            "stage": "search",
            "reason_codes": ["BP_FAIL_NO_LAYOUT_GRID_LIMIT"],
        })
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.add_case(root, export, case_id="failed-search")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            case = root / "cases" / "failed-search"
            manifest = json.loads((case / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["supported_outcome"], "production")
            self.assertEqual(manifest["observed_outcome"], {
                "state": "failure", "stage": "search", "reason_codes": ["BP_FAIL_NO_LAYOUT_GRID_LIMIT"]
            })
            self.assertEqual(json.loads((case / "prepared_input.json").read_text()), export["prepared_input"])

    def test_harness_capture_is_not_labelled_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.add_case(root, capture_export(source_kind="harness"), case_id="harness")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            manifest = json.loads((root / "cases" / "harness" / "manifest.json").read_text())
            self.assertEqual(manifest["source_kind"], "harness")
            self.assertNotEqual(manifest["source_kind"], "runtime")

    def test_capture_cannot_name_its_own_export_text(self):
        source = encode_export(capture_export(source_export="named-export"))
        export = capture_export(source_export=source)
        with tempfile.TemporaryDirectory() as directory:
            result = self.add_case(Path(directory), export, case_id="self-export")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("source_export", result.stderr)

    def test_force_still_refuses_an_accepted_baseline(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            case = root / "cases" / "accepted"
            case.mkdir(parents=True)
            (case / "manifest.json").write_text(json.dumps({"state": "accepted"}), encoding="utf-8")
            sentinel = case / "expected_canonical.json"
            sentinel.write_text('{"sentinel":true}\n', encoding="utf-8")
            result = self.add_case(root, capture_export(), case_id="accepted")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("accepted baseline", result.stderr)
            self.assertEqual(sentinel.read_text(encoding="utf-8"), '{"sentinel":true}\n')

    def test_a_deleted_required_case_directory_fails_the_branch_check(self):
        runner = load_runner()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cases = root / "cases"
            self.write_case(root, "surviving", state="accepted", prepared=False)
            self.write_matrix(root, [
                self.matrix_row("surviving", state="accepted"),
                self.matrix_row("deleted", state="accepted"),
            ])
            message = runner.check_branch_requirements(
                cases, runner.discover(cases, []), "2.0"
            )
            self.assertIsNotNone(message)
            self.assertIn("deleted@2.0", message)

    def test_a_production_case_carrying_a_search_budget_is_refused(self):
        runner = load_runner()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            case = self.write_case(root, "capped-case", options={"search_budget": 2500})
            self.write_matrix(root, [self.matrix_row("capped-case")])
            manifest = json.loads((case / "manifest.json").read_text(encoding="utf-8"))
            with mock.patch.object(runner, "run_lua_generator", return_value=GENERATED_PAYLOAD):
                with self.assertRaisesRegex(runner.GoldenError, r"capped-case.*search_budget"):
                    runner.accept_case(case, manifest, None, root / "artifacts")

    def test_one_captured_case_with_evidence_is_accepted_while_others_stay_draft(self):
        runner = load_runner()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = self.write_case(root, "runtime-capture", expected=False)
            self.write_case(root, "still-draft", state="draft", prepared=False)
            self.write_case(root, "still-captured", state="captured", source_kind="harness")
            self.write_matrix(root, [
                self.matrix_row("runtime-capture"),
                self.matrix_row("still-draft", state="draft"),
                self.matrix_row("still-captured", state="captured"),
            ])
            with mock.patch.object(runner, "run_lua_generator", return_value=GENERATED_PAYLOAD):
                result = runner.main(["accept", "--root", str(root / "cases"), "runtime-capture"])
            self.assertEqual(result, 0)
            self.assertEqual(json.loads((target / "manifest.json").read_text())["state"], "accepted")
            self.assertTrue((target / "expected_canonical.json").exists())
            matrix = json.loads((root / "required-matrix.json").read_text())
            states = {row["case_id"]: row["state"] for row in matrix["cases"]}
            self.assertEqual(states, {
                "runtime-capture": "accepted",
                "still-draft": "draft",
                "still-captured": "captured",
            })

    def test_acceptance_without_evidence_never_reaches_accepted(self):
        runner = load_runner()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            case = self.write_case(root, "unbound-capture", source_kind="harness", prepared=False)
            self.write_matrix(root, [self.matrix_row("unbound-capture")])
            before_manifest = (case / "manifest.json").read_bytes()
            before_matrix = (root / "required-matrix.json").read_bytes()
            before_expected = (case / "expected_canonical.json").read_bytes()
            manifest = json.loads(before_manifest)
            with self.assertRaisesRegex(runner.GoldenError, "evidence"):
                runner.accept_case(case, manifest, None, root / "artifacts")
            self.assertEqual((case / "manifest.json").read_bytes(), before_manifest)
            self.assertEqual((root / "required-matrix.json").read_bytes(), before_matrix)
            self.assertEqual(json.loads((case / "manifest.json").read_text())["state"], "captured")
            self.assertEqual((case / "expected_canonical.json").read_bytes(), before_expected)
            self.assertEqual(json.loads((root / "required-matrix.json").read_text())["cases"][0]["state"], "captured")

    def test_interrupted_acceptance_rolls_back_all_three_baseline_files(self):
        runner = load_runner()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            case = self.write_case(root, "interrupted-capture", expected=True)
            self.write_matrix(root, [self.matrix_row("interrupted-capture")])
            manifest_path = case / "manifest.json"
            matrix_path = root / "required-matrix.json"
            before_manifest = manifest_path.read_bytes()
            before_matrix = matrix_path.read_bytes()
            before_expected = (case / "expected_canonical.json").read_bytes()
            real_replace = runner.os.replace
            calls = {"count": 0}

            def interrupt_on_matrix(source, target):
                calls["count"] += 1
                if calls["count"] == 3:
                    raise OSError("simulated interrupted acceptance")
                return real_replace(source, target)

            manifest = json.loads(before_manifest)
            with mock.patch.object(runner, "run_lua_generator", return_value=GENERATED_PAYLOAD):
                with mock.patch.object(runner.os, "replace", side_effect=interrupt_on_matrix):
                    with self.assertRaisesRegex(OSError, "interrupted"):
                        runner.accept_case(case, manifest, None, root / "artifacts")
            self.assertEqual(manifest_path.read_bytes(), before_manifest)
            self.assertEqual(matrix_path.read_bytes(), before_matrix)
            self.assertEqual((case / "expected_canonical.json").read_bytes(), before_expected)


if __name__ == "__main__":
    unittest.main()


class AcceptanceEvidenceTests(unittest.TestCase):
    """A candidate is accepted only when it shows BOTH validation layers.

    Round 13 delivered a blueprint the generator called valid, and the value that made it valid came from
    Validate.reconcile_artifact, which never reads a belt, a pipe or an inserter. Contract 26.7 requires both
    layers and lets neither stand in for the other, so acceptance must refuse a payload showing one or
    neither -- otherwise the rule lives only inside the generator being judged.
    """

    def test_a_payload_with_no_validation_receipt_is_refused(self):
        runner = load_runner()
        failures = runner.validation_receipt_failures({"result": {"entities": []}})
        self.assertIn("combined validation did not pass", failures)
        self.assertIn("missing physical validation result", failures)
        self.assertIn("missing reconciliation validation result", failures)

    def test_reconciliation_alone_is_refused(self):
        runner = load_runner()
        failures = runner.validation_receipt_failures(
            {"validation": {"ok": True, "reconciliation": {"ok": True}}})
        self.assertIn("missing physical validation result", failures)

    def test_physical_alone_is_refused(self):
        runner = load_runner()
        failures = runner.validation_receipt_failures(
            {"validation": {"ok": True, "physical": {"ok": True, "result": {}}}})
        self.assertIn("missing reconciliation validation result", failures)

    def test_a_physical_layer_with_no_completed_result_is_refused(self):
        runner = load_runner()
        failures = runner.validation_receipt_failures(
            {"validation": {"ok": True, "physical": {"ok": True},
                            "reconciliation": {"ok": True}}})
        self.assertIn("physical validation has no completed result", failures)

    def test_both_layers_present_and_passing_is_accepted(self):
        """The positive control. Without it every refusal above is met by refusing everything."""
        runner = load_runner()
        self.assertEqual(runner.validation_receipt_failures(GENERATED_PAYLOAD), [])
