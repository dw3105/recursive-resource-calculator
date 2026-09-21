"""The player's capture is what the player's game actually sent, and nothing has drifted since.

Round 12 repairs beacon placement against `tests/golden/cases/player-am2-chain/`. Every conclusion drawn from
that fixture is worthless if the fixture stopped matching the raw export it came from, or if someone quietly
added a search allowance to make a run finish. Rounds 10 and 11 both lost time to exactly that class of
mistake, so the check is executable and runs in the ordinary suite rather than living in a plan.

What it proves, in order of strength:

  1. The stored PreparedInput is content-identical to the copy carried inside the raw debug export. Not
     "similar", not "has the fields we looked at" - identical. That single assertion subsumes every
     per-field comparison, so drift cannot hide in a field nobody thought to name.
  2. No `search_budget`, `max_ops`, `max_search_grids` or `max_grid_trials` was added. A capped search
     measures the cap, never the generator.
  3. Every solved column maps to a selected entry carrying its machine, quality, modules and beacon loadout.
     A solved recipe with no selection would mean the capture lost the very thing the round is about.
  4. The configured beacon counts are the player's own, unreduced.

Measured on this capture, legalcopilot-dev 2026-09-20: 7 solved columns, 550 selected entries, and beacon
counts of 3 on casting-iron and copper-plate, 1 on casting-steel, copper-cable and electronic-circuit.
`assembling-machine-1` and `assembling-machine-2` request no beacons at all.
"""

from __future__ import annotations

import base64
import json
import subprocess
import sys
import unittest
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CASE = ROOT / "tests" / "golden" / "cases" / "player-am2-chain"
EXPORT = ROOT / "docs" / "incidents" / "2026-09-20-search-budget" / "checkpoint-2" / "export.txt"
REPLAY = ROOT / "tests" / "incident" / "replay.py"

FORBIDDEN = ("search_budget", "max_ops", "max_search_grids", "max_grid_trials")

# The player's own configuration, read off the capture and pinned here so a reduction is loud.
EXPECTED_BEACON_COUNTS = {
    "casting-iron": 3,
    "copper-plate": 3,
    "casting-steel": 1,
    "copper-cable": 1,
    "electronic-circuit": 1,
}
EXPECTED_NO_BEACONS = {"assembling-machine-1", "assembling-machine-2"}


def prepared() -> dict:
    return json.loads((CASE / "prepared_input.json").read_text())


def exported_prepared() -> dict:
    raw = EXPORT.read_text().strip()
    return json.loads(zlib.decompress(base64.b64decode(raw)))["prepared_input"]


def selected_by_recipe(capture: dict) -> dict:
    out = {}
    for entry in capture["snapshot"]["selection"].values():
        if isinstance(entry, dict) and entry.get("status") == "selected":
            name = entry.get("recipe_name")
            if name:
                out.setdefault(name, entry)
    return out


class CaptureMatchesItsExport(unittest.TestCase):
    def test_the_stored_prepared_input_is_the_one_the_export_carried(self):
        self.assertEqual(prepared(), exported_prepared(),
                         "the fixture has drifted from the raw export it was taken from")

    def test_both_artefacts_are_present(self):
        self.assertTrue((CASE / "prepared_input.json").is_file())
        self.assertTrue(EXPORT.is_file(), "the raw export is the only thing that can prove the fixture")


class CaptureIsDefaultConfiguration(unittest.TestCase):
    def test_no_search_allowance_was_added(self):
        capture = prepared()
        options = capture.get("options") or {}
        for key in FORBIDDEN:
            with self.subTest(key=key):
                self.assertNotIn(key, options)
                self.assertNotIn(key, capture)


class CaptureIsComplete(unittest.TestCase):
    def test_every_solved_column_has_a_selection_with_its_machine(self):
        capture = prepared()
        by_recipe = selected_by_recipe(capture)
        columns = capture["solver_result"]["columns"]
        self.assertTrue(columns, "the capture solved nothing")
        for column in columns:
            recipe = column["recipe_name"]
            with self.subTest(recipe=recipe):
                entry = by_recipe.get(recipe)
                self.assertIsNotNone(entry, f"solved recipe {recipe} has no selection")
                machine = entry.get("machine") or {}
                self.assertTrue(machine.get("name"), f"{recipe} has no selected machine")
                self.assertTrue(machine.get("quality"), f"{recipe} machine has no quality")

    def test_the_beacon_loadouts_carry_their_modules_and_qualities(self):
        by_recipe = selected_by_recipe(prepared())
        for recipe in EXPECTED_BEACON_COUNTS:
            with self.subTest(recipe=recipe):
                beacons = (by_recipe[recipe].get("beacons") or [])
                self.assertTrue(beacons, f"{recipe} lost its beacon loadout")
                group = beacons[0]
                self.assertTrue(group.get("name"))
                self.assertTrue(group.get("quality"))
                self.assertTrue(group.get("modules"), f"{recipe} beacon has no modules")
                for module in group["modules"]:
                    self.assertTrue(module.get("name"))
                    self.assertTrue(module.get("quality"))


class BeaconCountsAreThePlayersOwn(unittest.TestCase):
    """The round must never make itself pass by asking for fewer beacons."""

    def test_each_configured_count_is_unreduced(self):
        by_recipe = selected_by_recipe(prepared())
        for recipe, expected in EXPECTED_BEACON_COUNTS.items():
            with self.subTest(recipe=recipe):
                beacons = by_recipe[recipe].get("beacons") or []
                self.assertEqual(beacons[0].get("count"), expected,
                                 f"{recipe} no longer requests {expected} beacons")

    def test_both_beacon_settings_are_present(self):
        by_recipe = selected_by_recipe(prepared())
        for recipe in EXPECTED_BEACON_COUNTS:
            with self.subTest(recipe=recipe):
                group = (by_recipe[recipe].get("beacons") or [])[0]
                self.assertIn("count", group)
                self.assertIn("sharing", group, "sharing is the second beacon setting and must survive")

    def test_the_two_beaconless_steps_stay_beaconless(self):
        by_recipe = selected_by_recipe(prepared())
        for recipe in EXPECTED_NO_BEACONS:
            with self.subTest(recipe=recipe):
                self.assertFalse(by_recipe[recipe].get("beacons"),
                                 f"{recipe} gained a beacon requirement it never had")


class HistoricalReplayPolicy(unittest.TestCase):
    def test_historical_case_keeps_its_structural_incomplete_capture_rejection(self):
        result = subprocess.run(
            [sys.executable, str(REPLAY), "--case", "player-am2-chain", "--require-rejection"],
            cwd=ROOT, text=True, capture_output=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("BP_CAP_INCOMPLETE", result.stdout)

    def test_require_success_cannot_promote_the_historical_case(self):
        result = subprocess.run(
            [sys.executable, str(REPLAY), "--case", "player-am2-chain", "--require-success"],
            cwd=ROOT, text=True, capture_output=True, check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("historical negative", result.stdout)


if __name__ == "__main__":
    unittest.main()
