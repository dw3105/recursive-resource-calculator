"""Qualify tools/blueprint_string.py on the one thing round 13 got silently wrong: wires.

The round 13 delivery carried 0 wire edges against 10 in the generator result. The converter dropped them on
purpose, reasoning that an invented connector id is worse than none. Contract 26.7 disagrees with the SILENCE,
never with the caution: a connector id that is genuinely unavailable offline is a named refusal.

What is known, measured on this host 2026-09-21. factorio-draftsman 4.0.0 reports
`WireConnectorID.POLE_COPPER = 5`, so the offline placeholder 0 that logic/bp/power.lua:255-263 writes is
wrong. Draftsman is NOT an oracle for this: it accepted connector 99 and round-tripped `wires` as `None`, so
it discards wires exactly as it discards every `recipe`. Writing 5 on that evidence alone would be a guess.

All ten edges in the round 13 result were pole to pole copper, and poles auto-connect to poles in range when a
blueprint is built, so omitting those costs nothing physically. That earns an explicit flag, never silence.
"""

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONVERT = ROOT / "tools" / "blueprint_string.py"

POLE_A = {"entity_number": 1, "name": "medium-electric-pole", "position": {"x": 0.5, "y": 0.5}}
POLE_B = {"entity_number": 2, "name": "medium-electric-pole", "position": {"x": 6.5, "y": 0.5}}
MACHINE = {"entity_number": 3, "name": "assembling-machine-3", "position": {"x": 4.5, "y": 6.5},
           "recipe": "iron-gear-wheel"}


def run(result, *extra):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
        json.dump({"ok": True, "result": result}, handle)
        path = handle.name
    try:
        done = subprocess.run([sys.executable, str(CONVERT), path, *extra],
                              capture_output=True, text=True)
        return done.returncode, done.stdout, done.stderr
    finally:
        pathlib.Path(path).unlink()


def decode(stdout):
    import base64
    import zlib
    text = stdout.strip()
    return json.loads(zlib.decompress(base64.b64decode(text[1:])))["blueprint"]


class BlueprintStringWireTest(unittest.TestCase):

    def test_BS9_locationless_entity_refuses_by_index_and_name(self):
        status, _, stderr = run({"entities": [{"name": "medium-electric-pole", "quality": "normal"}]})
        self.assertEqual(status, 1)
        self.assertIn("entity 1 (medium-electric-pole)", stderr)
        self.assertIn("has no usable position", stderr)

    def test_BS10_internal_xy_without_position_refuses_by_name(self):
        status, _, stderr = run({"entities": [{"name": "medium-electric-pole", "x": 10, "y": 20}]})
        self.assertEqual(status, 1)
        self.assertIn("entity 1 (medium-electric-pole)", stderr)
        self.assertIn("has no usable position", stderr)

    def test_BS11_every_underground_tier_keeps_its_type(self):
        """An untyped underground imports as an entrance; fast ones shipped untyped until 2026-09-25."""
        ends = [{"name": name, "position": {"x": 0.5 + 4 * i, "y": 2.5}, "direction": 4, "type": kind}
                for i, (name, kind) in enumerate([("fast-underground-belt", "input"), ("fast-underground-belt", "output"),
                                                  ("express-underground-belt", "input"), ("turbo-underground-belt", "output")])]
        status, stdout, stderr = run({"entities": [POLE_A, POLE_B, MACHINE] + ends})
        self.assertEqual(status, 0, stderr)
        kinds = [e.get("type") for e in decode(stdout)["entities"] if "underground" in e["name"]]
        self.assertEqual(kinds, ["input", "output", "input", "output"])

    def test_BS1_a_result_with_no_wires_converts(self):
        """The control. Without it every refusal below is satisfied by a converter that refuses everything."""
        status, stdout, stderr = run({"entities": [POLE_A, POLE_B, MACHINE]})
        self.assertEqual(status, 0, stderr)
        blueprint = decode(stdout)
        self.assertEqual(len(blueprint["entities"]), 3)
        self.assertNotIn("wires", blueprint)

    def test_BS2_a_real_connector_id_is_carried(self):
        status, stdout, stderr = run({"entities": [POLE_A, POLE_B, MACHINE], "wires": [[1, 5, 2, 5]]})
        self.assertEqual(status, 0, stderr)
        self.assertEqual(decode(stdout)["wires"], [[1, 5, 2, 5]])

    def test_BS3_the_offline_placeholder_refuses(self):
        """Round 13 dropped this one quietly and delivered 0 of 10 edges."""
        status, _, stderr = run({"entities": [POLE_A, POLE_B, MACHINE], "wires": [[1, 0, 2, 0]]})
        self.assertEqual(status, 1)
        self.assertIn("placeholder connector", stderr)

    def test_BS4_pole_copper_may_be_omitted_deliberately(self):
        status, stdout, stderr = run({"entities": [POLE_A, POLE_B, MACHINE], "wires": [[1, 0, 2, 0]]},
                                     "--allow-pole-autoconnect")
        self.assertEqual(status, 0, stderr)
        self.assertIn("omitted 1 pole-to-pole copper wire", stderr)
        self.assertNotIn("wires", decode(stdout))

    def test_BS5_a_non_pole_wire_refuses_even_with_the_flag(self):
        """The flag is about poles reconnecting themselves. Nothing else reconnects itself."""
        status, _, stderr = run({"entities": [POLE_A, POLE_B, MACHINE], "wires": [[1, 0, 3, 0]]},
                                "--allow-pole-autoconnect")
        self.assertEqual(status, 1)
        self.assertIn("placeholder connector", stderr)

    def test_BS6_a_wire_naming_a_missing_entity_refuses(self):
        status, _, stderr = run({"entities": [POLE_A, POLE_B], "wires": [[1, 5, 99, 5]]})
        self.assertEqual(status, 1)
        self.assertIn("which the artifact does not carry", stderr)

    def test_BS7_a_malformed_wire_refuses(self):
        status, _, stderr = run({"entities": [POLE_A, POLE_B], "wires": [[1, 5, 2]]})
        self.assertEqual(status, 1)
        self.assertIn("is not [entity, connector, entity, connector]", stderr)

    def test_BS8_the_round_13_result_refuses_by_default(self):
        """Known-bad regression, from the preserved generator output of the delivery the player pasted."""
        preserved = (pathlib.Path.home() / "codex-reviews" /
                     "rrc-blueprint-rescue-20260921-101555" / "generator-int3.json")
        if not preserved.exists():
            self.skipTest("the preserved round 13 generator result is not present on this host")
        done = subprocess.run([sys.executable, str(CONVERT), str(preserved)],
                              capture_output=True, text=True)
        self.assertEqual(done.returncode, 1)
        self.assertIn("placeholder connector", done.stderr)
        allowed = subprocess.run([sys.executable, str(CONVERT), str(preserved), "--allow-pole-autoconnect"],
                                 capture_output=True, text=True)
        self.assertEqual(allowed.returncode, 0, allowed.stderr)
        self.assertIn("omitted 10 pole-to-pole copper wire", allowed.stderr)


if __name__ == "__main__":
    unittest.main()
