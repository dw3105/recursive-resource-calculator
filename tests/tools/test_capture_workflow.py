import base64
import json
import subprocess
import tempfile
import unittest
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADD_CASE = ROOT / "tests" / "golden" / "add_case"


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


if __name__ == "__main__":
    unittest.main()
