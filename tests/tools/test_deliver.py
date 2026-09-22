"""Exercise the delivery command with a recorded blueprint and a fake generator.

The real golden generator is deliberately absent from these tests.  The
player-red-science reference blueprint is decoded into the generator's result
shape once, then a PATH stub copies that recorded result when deliver.sh asks
for generation.  The real converter and auditor still judge the bytes.
"""

import base64
import json
import os
import pathlib
import re
import subprocess
import tempfile
import unittest
import zlib
from datetime import datetime, timezone


ROOT = pathlib.Path(__file__).resolve().parents[2]
DELIVER = ROOT / "tools" / "deliver.sh"
RECORDED = ROOT / "tests" / "golden" / "cases" / "player-red-science-1s" / "reference_manual_blueprint.txt"
CASE = "player-red-science-1s"
FAMILIES = (
    "belts", "undergrounds", "splitters", "inserters", "machines", "poles", "pipes",
    "beacons", "roboports", "other", "entities_excluding_roboports",
)


def recorded_result():
    encoded = RECORDED.read_text().strip()
    blueprint = json.loads(zlib.decompress(base64.b64decode(encoded[1:])))['blueprint']
    entities = [
        {key: value for key, value in entity.items() if key != "entity_number"}
        for entity in blueprint["entities"]
    ]
    return {"ok": True, "result": {"entities": entities, "wires": blueprint.get("wires", [])}}


class DeliverTests(unittest.TestCase):

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.temp.name)
        self.home = root / "home"
        self.bin = root / "bin"
        self.home.mkdir()
        self.bin.mkdir()
        self.recorded_json = root / "recorded-result.json"
        self.recorded_json.write_text(json.dumps(recorded_result()))

        stub = self.bin / "lua5.2"
        stub.write_text(
            "#!/bin/sh\n"
            "output=\n"
            "while [ $# -gt 0 ]; do\n"
            "  if [ \"$1\" = --output ]; then output=$2; shift 2; else shift; fi\n"
            "done\n"
            "cp \"$DELIVER_RECORDED_RESULT\" \"$output\"\n"
        )
        stub.chmod(0o755)

    def tearDown(self):
        self.temp.cleanup()

    def run_delivery(self, *args):
        environment = os.environ.copy()
        environment["HOME"] = str(self.home)
        environment["PATH"] = str(self.bin) + os.pathsep + environment["PATH"]
        environment["DELIVER_RECORDED_RESULT"] = str(self.recorded_json)
        return subprocess.run(
            [str(DELIVER), *args], cwd=ROOT, env=environment,
            capture_output=True, text=True,
        )

    @staticmethod
    def output_path(stdout):
        match = re.search(r"(?:^| )output=(\S+)", stdout)
        if not match:
            raise AssertionError(f"no output path in summary: {stdout!r}")
        return pathlib.Path(match.group(1))

    def test_accepting_recorded_export_has_census_timings_and_file_only_string(self):
        done = self.run_delivery(CASE)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(len(done.stdout.splitlines()), 1, done.stdout)
        for family in FAMILIES:
            self.assertRegex(done.stdout, rf"\b{family}=\d+\b")
        for timing in ("generation_s", "encode_s", "audit_s", "total_s"):
            self.assertRegex(done.stdout, rf"\b{timing}=\d+\.\d{{3}}\b")

        output = self.output_path(done.stdout)
        self.assertRegex(output.name, rf"^{CASE}-\d{{8}}\.txt$")
        self.assertEqual(int(re.search(r"\bbytes=(\d+)\b", done.stdout).group(1)), output.stat().st_size)
        self.assertTrue(output.read_text().startswith("0"))
        self.assertNotIn(RECORDED.read_text().strip(), done.stdout)

    def test_refusing_audit_is_nonzero_but_keeps_summary_and_counts(self):
        target = pathlib.Path(self.temp.name) / "reject.json"
        target.write_text(json.dumps({"machines": 999}))

        done = self.run_delivery(CASE, "--target", str(target))

        self.assertNotEqual(done.returncode, 0)
        self.assertEqual(len(done.stdout.splitlines()), 1, done.stdout)
        self.assertIn("verdict=refused", done.stdout)
        self.assertIn("machines=11", done.stdout)
        self.assertIn("target machines", done.stderr)
        self.assertNotIn(RECORDED.read_text().strip(), done.stdout)

    def test_target_override_can_accept_against_a_different_frozen_file(self):
        target = pathlib.Path(self.temp.name) / "override.json"
        target.write_text(json.dumps({"machines": 11}))

        done = self.run_delivery(CASE, "--target", str(target))

        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("verdict=accepted", done.stdout)

    def test_no_target_skips_only_count_contract_and_keeps_physical_audit(self):
        result = json.loads(self.recorded_json.read_text())
        result["result"]["entities"].append(
            {"name": "wooden-chest", "position": {"x": 0.5, "y": 0.5}})
        self.recorded_json.write_text(json.dumps(result))
        expected = self.run_delivery(CASE)
        self.output_path(expected.stdout).unlink()
        without_target = self.run_delivery(CASE, "--no-target")
        self.assertNotEqual(expected.returncode, 0, expected.stderr)
        self.assertIn("target entities_excluding_roboports", expected.stderr)
        self.assertEqual(without_target.returncode, 0, without_target.stderr)
        self.assertIn("verdict=accepted", without_target.stdout)
        for family in FAMILIES:
            self.assertRegex(without_target.stdout, rf"\b{family}=\d+\b")

    def test_no_target_and_target_is_named_usage_refusal(self):
        done = self.run_delivery(CASE, "--no-target", "--target", "ignored.json")
        self.assertEqual(done.returncode, 2)
        self.assertIn("--no-target cannot be combined with --target", done.stderr)
        self.assertNotIn("Traceback", done.stderr)

    def test_existing_output_is_named_and_not_overwritten(self):
        output_dir = self.home / "share" / "RRC"
        output_dir.mkdir(parents=True)
        output = output_dir / f"{CASE}-{datetime.now(timezone.utc):%Y%m%d}.txt"
        output.write_text("sentinel\n")

        done = self.run_delivery(CASE)

        self.assertNotEqual(done.returncode, 0)
        self.assertIn("reason=output_collision", done.stdout)
        self.assertIn("output collision", done.stderr)
        self.assertEqual(output.read_text(), "sentinel\n")

    def test_keep_intermediate_leaves_result_json(self):
        keep = pathlib.Path(self.temp.name) / "diagnosis"

        done = self.run_delivery(CASE, "--keep-intermediate", str(keep))

        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue((keep / "result.json").is_file())

    def test_unknown_case_is_named_without_a_traceback(self):
        done = self.run_delivery("not-a-case")

        self.assertNotEqual(done.returncode, 0)
        self.assertIn("unknown case 'not-a-case'", done.stderr)
        self.assertNotIn("Traceback", done.stdout + done.stderr)


if __name__ == "__main__":
    unittest.main()
