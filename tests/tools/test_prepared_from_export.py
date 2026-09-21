"""Qualify tools/prepared_from_export.py, and pin the sentinel the repo never decoded.

`logic/export_payload.lua:100` writes `rrc_empty_list = true` when a list is empty, on purpose, so a JSON
round trip keeps "empty LIST" distinct from "empty map". Nothing on the read side undid it. Measured on
~/share/RRC/red_science_1s.txt, 2026-09-21: the generator died with
`preflight.lua:422: attempt to index local 'group' (a boolean value)`, the boolean being the sentinel's own
`true`, reached by iterating the marker table as if it held beacon groups.

The output of this tool is a development input and can never certify anything: it fills infrastructure facts
the export does not carry from vanilla 2.0.77 values, and says so in its own provenance.
"""

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "prepared_from_export.py"
sys.path.insert(0, str(ROOT / "tools"))

import prepared_from_export as PFE  # noqa: E402

MINIMAL_EXPORT = {
    "rrc_version": "1.1.53",
    "environment": {"base_game_version": "2.0.77", "active_mods": {"base": "2.0.77"}},
    "sheet": {"sheet_id": "sheet-1", "options": {"round_up": False},
              "revisions": {"sheet": 1, "config": 1},
              "selection": {"1": {"beacons": {"rrc_empty_list": True},
                                  "modules": {"rrc_empty_list": True},
                                  "machine": {"name": "assembling-machine-2", "quality": "normal"}}}},
    "calculation": {"status": "ok", "columns": [], "recipe_rates": {}, "solved_rates": {},
                    "unsolved_rates": {}, "product_parts": {}, "reasons_by_column": {}},
    "prototypes": {"entity": {"assembling-machine-2": {"name": "assembling-machine-2",
                                                       "etype": "assembling-machine"}}},
}


class SentinelTest(unittest.TestCase):

    def test_PE1_an_empty_list_sentinel_becomes_a_list(self):
        self.assertEqual(PFE.decode_sentinels({"rrc_empty_list": True}), [])

    def test_PE2_the_sentinel_is_decoded_wherever_it_sits(self):
        decoded = PFE.decode_sentinels(
            {"rows": [{"beacons": {"rrc_empty_list": True}, "name": "x"}]})
        self.assertEqual(decoded["rows"][0]["beacons"], [])
        self.assertEqual(decoded["rows"][0]["name"], "x")

    def test_PE3_a_map_that_merely_carries_the_key_is_left_alone(self):
        """Only a table whose SOLE key is the marker is the marker."""
        value = {"rrc_empty_list": True, "name": "not a marker"}
        self.assertEqual(PFE.decode_sentinels(value), value)

    def test_PE4_ordinary_values_survive(self):
        value = {"a": [1, 2, {"b": "c"}], "d": None, "e": 1.5}
        self.assertEqual(PFE.decode_sentinels(value), value)


class PreparedInputTest(unittest.TestCase):

    def build(self, export=None):
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory) / "export.json"
            source.write_text(json.dumps(export if export is not None else MINIMAL_EXPORT))
            target = pathlib.Path(directory) / "prepared.json"
            done = subprocess.run([sys.executable, str(TOOL), str(source), "-o", str(target)],
                                  capture_output=True, text=True)
            payload = json.loads(target.read_text()) if target.exists() else None
            return done.returncode, payload, done.stderr

    def test_PE5_a_solved_export_becomes_a_prepared_input(self):
        status, prepared, stderr = self.build()
        self.assertEqual(status, 0, stderr)
        for key in ("catalog", "settings", "snapshot", "solver_result", "provenance", "revisions"):
            self.assertIn(key, prepared)

    def test_PE6_the_result_names_itself_reconstructed_and_uncertifiable(self):
        _, prepared, _ = self.build()
        self.assertEqual(prepared["source_kind"], "reconstructed")
        self.assertIs(prepared["provenance"]["certifiable"], False)

    def test_PE7_every_invented_fact_is_named(self):
        """A reconstruction that does not say WHAT it invented is indistinguishable from a capture."""
        _, prepared, _ = self.build()
        named = prepared["provenance"]["reconstructed_facts"]
        for key in ("catalog.belt", "catalog.pipe", "catalog.inserter", "catalog.pole", "catalog.roboport"):
            self.assertIn(key, named)

    def test_PE8_the_inserter_carries_real_offsets(self):
        """The stored player capture has these as EMPTY tables, which is why its inserters all reject."""
        _, prepared, _ = self.build()
        inserter = prepared["catalog"]["inserter"]
        self.assertEqual(inserter["pickup_offset"], {"x": 0, "y": 1})
        self.assertEqual(inserter["drop_offset"], {"x": 0, "y": -1})

    def test_PE9_a_captured_fact_is_never_overwritten(self):
        """If the export DOES carry a belt catalog, the vanilla table must not replace it."""
        export = json.loads(json.dumps(MINIMAL_EXPORT))
        export["prototypes"]["belt"] = {"belt": "turbo-transport-belt", "items_per_second": 60}
        _, prepared, _ = self.build(export)
        self.assertEqual(prepared["catalog"]["belt"]["belt"], "turbo-transport-belt")
        self.assertNotIn("catalog.belt", prepared["provenance"]["reconstructed_facts"])

    def test_PE10_an_unsolved_calculation_is_refused(self):
        export = json.loads(json.dumps(MINIMAL_EXPORT))
        export["calculation"]["status"] = "unsolved"
        status, _, stderr = self.build(export)
        self.assertEqual(status, 1)
        self.assertIn("did not solve", stderr)


if __name__ == "__main__":
    unittest.main()
