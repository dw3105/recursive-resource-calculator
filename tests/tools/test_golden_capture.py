import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ADD_CASE = ROOT / "tests" / "golden" / "add_case"


def player_export():
    return {
        "format": "rrc-sheet-debug",
        "schema_version": 1,
        "rrc_version": "1.1.49",
        "environment": {
            "base_game_version": "2.0.77",
            "active_mods": {"base": "2.0.77", "quality": "2.0.77", "space-age": "2.0.77"},
            "mod_version": "1.1.49",
        },
        "sheet": {
            "targets": [{
                "index": 1,
                "full_name": "item/assembling-machine-2",
                "type": "item",
                "name": "assembling-machine-2",
                "quality": "normal",
                "raw_text": "1",
                "time_unit": "/s",
                "rate_per_second": 1,
                "valid": True,
            }],
            "options": {"round_up": False, "start_leftovers": "byproduct"},
            "selection": {},
        },
        "provenance": {
            "terminal_outcome": "failure",
            "stage": "preflight",
            "reason_codes": ["BP_REJ_PROTOTYPE_FACTS_MISSING"],
        },
        "state": "current",
    }


class GoldenCaptureTests(unittest.TestCase):
    def add_case(self, root, export, options=None, case_id="case"):
        export_path = root / "export.json"
        options_path = root / "options.json"
        export_path.write_text(json.dumps(export), encoding="utf-8")
        options_path.write_text(json.dumps(options or {}), encoding="utf-8")
        return subprocess.run(
            ["python3", str(ADD_CASE), case_id, "--export", str(export_path), "--options", str(options_path),
             "--cases", str(root / "cases")],
            cwd=ROOT, text=True, capture_output=True, check=False,
        )

    def test_export_keeps_exact_engine_version_and_records_missing_facts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.add_case(root, player_export(), {"factorio_branch": "2.1"})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            case = root / "cases" / "case"
            manifest = json.loads((case / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["factorio_branch"], "2.0")
            self.assertEqual(manifest["versions"]["base_game_version"], "2.0.77")
            self.assertEqual(manifest["versions"]["factorio_branch"], "2.0")
            self.assertEqual(manifest["source_kind"], "handwritten_fixture")
            self.assertEqual(manifest["facts_missing"], ["prepared_input", "catalog.recipe", "effect_receiver"])
            self.assertEqual(manifest["observed_outcome"], {
                "state": "failure",
                "stage": "preflight",
                "reason_codes": ["BP_REJ_PROTOTYPE_FACTS_MISSING"],
            })
            self.assertEqual(manifest["targets"], [])
            self.assertEqual(manifest["setup"]["selection"], [])
            self.assertFalse((case / "prepared_input.json").exists())
            provenance = json.loads((case / "provenance.json").read_text(encoding="utf-8"))
            self.assertEqual(provenance["facts_missing"], manifest["facts_missing"])

    def test_export_with_no_prepared_input_is_never_a_runtime_capture(self):
        export = player_export()
        export["source_kind"] = "runtime"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.add_case(root, export, {"factorio_branch": "2.0"}, case_id="truthful-source")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            manifest = json.loads(
                (root / "cases" / "truthful-source" / "manifest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(manifest["source_kind"], "handwritten_fixture")
            self.assertNotEqual(manifest["source_kind"], "runtime")


if __name__ == "__main__":
    unittest.main()
