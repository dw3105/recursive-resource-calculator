"""Qualify tools/blueprint_audit.py against a hand-built control and one named mutation each.

The auditor is the delivery gate of round 14, so it must be shown to REJECT before it is trusted to accept.
Two of its rules were wrong when first written and both were caught here, not in review:

  * component membership is not the contract.  Joining components across legal underground pairs -- which is
    physically right -- made one inserter bless a whole network, and the round 13 artifact's unused belt count
    fell from 89 to 0.  Directed reachability replaced it.
  * the bounding box was taken from entity CENTRES, so every cell of a one-row layout counted as perimeter and
    a stray belt extended the box and inferred ITSELF as both supply and drain terminal.  Both the reversed
    inserter and the added waste belt survived.  Extents, plus a terminal only where the belt's own flow
    crosses the boundary, killed both.
"""

import base64
import copy
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
AUDIT = ROOT / "tools" / "blueprint_audit.py"


def belt(x, y, direction=4):
    return {"name": "transport-belt", "position": {"x": x, "y": y}, "direction": direction}


def underground(x, y, half, direction=4):
    return {"name": "underground-belt", "position": {"x": x, "y": y},
            "direction": direction, "type": half}


def inserter(x, y, direction=4):
    return {"name": "inserter", "position": {"x": x, "y": y}, "direction": direction}


def control():
    """Belt in, inserter, machine, inserter, belt, tunnel, belt out.  Every entity serves the one obligation."""
    return [
        belt(0.5, 0.5), belt(1.5, 0.5),
        inserter(2.5, 0.5),
        {"name": "assembling-machine-3", "position": {"x": 4.5, "y": 0.5}, "recipe": "iron-gear-wheel"},
        inserter(6.5, 0.5),
        belt(7.5, 0.5),
        underground(8.5, 0.5, "input"), underground(12.5, 0.5, "output"),
        belt(13.5, 0.5),
    ]


def encode(entities, label="control"):
    entities = copy.deepcopy(entities)
    for index, entity in enumerate(entities, start=1):
        entity["entity_number"] = index
    payload = {"blueprint": {"item": "blueprint", "version": (2 << 48) | (77 << 16),
                             "label": label, "entities": entities}}
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    return "0" + base64.b64encode(zlib.compress(body, 9)).decode("ascii")


def audit(entities, *extra):
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as handle:
        handle.write(encode(entities) + "\n")
        path = handle.name
    try:
        done = subprocess.run([sys.executable, str(AUDIT), path, "--json", *extra],
                              capture_output=True, text=True)
        return done.returncode, json.loads(done.stdout) if done.stdout.strip() else {}
    finally:
        pathlib.Path(path).unlink()


class BlueprintAuditTest(unittest.TestCase):

    def test_ACC1_control_is_accepted(self):
        """Without this the whole suite below is satisfied by an auditor that rejects everything."""
        status, counts = audit(control())
        self.assertEqual(status, 0, f"the control must pass before any rejection counts: {counts}")
        self.assertEqual(counts["unused_belt_tiles"], 0)
        self.assertEqual(counts["invalid_inserters"], 0)
        self.assertEqual(counts["unpairable_underground"], 0)

    def test_ACC2_inserter_dropping_on_empty_ground(self):
        entities = control()
        entities[2]["position"] = {"x": 2.5, "y": 20.5}
        status, counts = audit(entities)
        self.assertEqual(status, 1)
        self.assertGreaterEqual(counts["invalid_inserters"], 1)

    def test_ACC3_inserter_dropping_onto_a_pole(self):
        entities = control()
        entities.append({"name": "medium-electric-pole", "position": {"x": 14.5, "y": 0.5}})
        entities.append(inserter(15.5, 0.5, 12))
        status, counts = audit(entities)
        self.assertEqual(status, 1)
        self.assertGreaterEqual(counts["invalid_inserters"], 1)

    def test_ACC4_a_reversed_output_inserter_is_BEYOND_byte_level_waste(self):
        """Honest limit of this tool, kept as a case so nobody re-adds the claim.

        Reversing the output inserter makes the machine drain nowhere, which is a broken obligation. It is NOT
        a waste violation: the belt it used to receive from becomes an externally fed run that passes an
        inserter taking from it, and that is a legal arrangement. From bytes alone, with no obligations, the
        two are indistinguishable. Only the validator, which holds the plan, can reject this.

        An earlier version of this suite asserted the opposite and passed, because the terminal rule was wrong
        and reported every belt of a working factory as unused.
        """
        entities = control()
        entities[4]["direction"] = 12
        _, counts = audit(entities)
        self.assertEqual(counts["unused_belt_tiles"], 0)
        self.assertEqual(counts["invalid_inserters"], 0)

    def test_ACC5_added_waste_belt_is_rejected(self):
        """Production is untouched; contract 26.2 still refuses the spare entity."""
        entities = control()
        entities.append(belt(20.5, 20.5))
        status, counts = audit(entities)
        self.assertEqual(status, 1)
        self.assertGreaterEqual(counts["unused_belt_tiles"], 1)

    def test_ACC6_underground_exit_turned_aside(self):
        entities = control()
        entities[7]["direction"] = 8
        status, counts = audit(entities)
        self.assertEqual(status, 1)
        self.assertGreaterEqual(counts["unpairable_underground_belt"], 1)

    def test_ACC7_underground_entrance_deleted(self):
        entities = control()
        del entities[6]
        status, counts = audit(entities)
        self.assertEqual(status, 1)
        self.assertGreaterEqual(counts["unpairable_underground_belt"], 1)

    def test_ACC8_underground_beyond_reach(self):
        entities = control()
        entities[7]["position"] = {"x": 20.5, "y": 0.5}
        entities[8]["position"] = {"x": 21.5, "y": 0.5}
        status, counts = audit(entities)
        self.assertEqual(status, 1)
        self.assertGreaterEqual(counts["unpairable_underground_belt"], 1)

    def test_ACC9_pipe_to_ground_pair_facing_the_same_way(self):
        """The exact round 13 defect: every delivered pipe-to-ground faced east or south, so none could pair."""
        entities = control()
        entities.append({"name": "pipe-to-ground", "position": {"x": 4.5, "y": 5.5}, "direction": 4})
        entities.append({"name": "pipe-to-ground", "position": {"x": 8.5, "y": 5.5}, "direction": 4})
        status, counts = audit(entities)
        self.assertEqual(status, 1)
        self.assertGreaterEqual(counts["unpairable_pipe_to_ground"], 1)

    def test_ACC10_pipe_to_ground_pair_facing_each_other_is_accepted(self):
        """A correct pair must NOT be reported, or the rule above is satisfied by rejecting all pipes."""
        entities = control()
        entities.append({"name": "pipe-to-ground", "position": {"x": 4.5, "y": 5.5}, "direction": 4})
        entities.append({"name": "pipe-to-ground", "position": {"x": 8.5, "y": 5.5}, "direction": 12})
        _, counts = audit(entities)
        self.assertEqual(counts["unpairable_pipe_to_ground"], 0)

    def test_ACC11_redundant_beacon_is_rejected(self):
        entities = control()
        entities.append({"name": "beacon", "position": {"x": 4.5, "y": 4.5}})
        entities.append({"name": "beacon", "position": {"x": 4.5, "y": -3.5}})
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            handle.write(json.dumps({"iron-gear-wheel": 1}))
            config = handle.name
        try:
            status, counts = audit(entities, "--beacon-config", config)
            self.assertEqual(status, 1)
            self.assertEqual(counts["redundant_beacons"], 1)
        finally:
            pathlib.Path(config).unlink()

    def test_ACC12_extra_influence_from_a_load_bearing_beacon_is_legal(self):
        """Your rule: more beacons per machine is fine.  Only a REMOVABLE beacon is waste."""
        entities = control()
        entities.append({"name": "beacon", "position": {"x": 4.5, "y": 4.5}})
        entities.append({"name": "beacon", "position": {"x": 4.5, "y": -3.5}})
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            handle.write(json.dumps({"iron-gear-wheel": 2}))
            config = handle.name
        try:
            _, counts = audit(entities, "--beacon-config", config)
            self.assertEqual(counts["redundant_beacons"], 0)
        finally:
            pathlib.Path(config).unlink()

    def test_ACC13_the_round_13_delivery_stays_rejected(self):
        """Known-bad regression.  These counts are the frozen baseline of round 14."""
        artifact = pathlib.Path.home() / "share" / "RRC" / "rrc-round13-mine.txt"
        if not artifact.exists():
            self.skipTest("the round 13 delivery is not present on this host")
        done = subprocess.run([sys.executable, str(AUDIT), str(artifact), "--json"],
                              capture_output=True, text=True)
        self.assertEqual(done.returncode, 1)
        counts = json.loads(done.stdout)
        self.assertEqual(counts["invalid_inserters"], 11)
        self.assertEqual(counts["unpairable_pipe_to_ground"], 12)
        self.assertEqual(counts["unpairable_underground_belt"], 4)
        #51, not the 224 this suite first froze. The bounding-box terminal rule reported every belt of a
        #working hand-built factory as unused, so its count here was inflated too. 51 belt entities of 224
        #genuinely reach no sink or are reached by no source.
        self.assertEqual(counts["unused_belt_tiles"], 51)
        self.assertEqual(counts["unused_pipe_tiles"], 35)
        self.assertEqual(counts["wires"], 0)


if __name__ == "__main__":
    unittest.main()


class HandBuiltReferenceTest(unittest.TestCase):
    """The strongest control available: a factory a person built and the game runs.

    Supplied 2026-09-21 as ~/share/RRC/red_science_1s_manual_bp.txt, sha256
    934a0034af3069ef40ee1878582d53b26834d287fa4106c2b4480404f6123c30, 131 entities for
    automation-science-pack at 1/s. A tool that rejects this rejects working factories, and the first version
    of this auditor did exactly that: it reported all 84 belts unused.
    """

    def test_ACC14_a_working_hand_built_factory_is_accepted(self):
        reference = pathlib.Path.home() / "share" / "RRC" / "red_science_1s_manual_bp.txt"
        if not reference.exists():
            self.skipTest("the hand-built reference is not present on this host")
        done = subprocess.run([sys.executable, str(AUDIT), str(reference), "--json"],
                              capture_output=True, text=True)
        counts = json.loads(done.stdout)
        self.assertEqual(counts["unused_belt_tiles"], 0, "a working factory has no unused belt")
        self.assertEqual(counts["invalid_inserters"], 0, "a working factory has no invalid inserter")
        self.assertEqual(counts["unpairable_underground"], 0)
        self.assertEqual(counts["wires"], 12)
        self.assertEqual({key: counts[key] for key in (
            "entities", "belts", "inserters", "poles", "machines", "roboports", "splitters",
            "undergrounds", "pipes", "beacons", "entities_excluding_roboports")}, {
            "entities": 131, "belts": 84, "inserters": 22, "poles": 10, "machines": 11, "roboports": 4,
            "splitters": 0, "undergrounds": 0, "pipes": 0, "beacons": 0,
            "entities_excluding_roboports": 127,
        })
        self.assertEqual(done.returncode, 0, "the reference must pass outright")

    def test_ACC15_family_census_keeps_zero_families_and_unknowns(self):
        entities = control()
        entities.append({"name": "modded-widget", "position": {"x": 30.5, "y": 30.5}})
        status, counts = audit(entities)
        self.assertEqual(status, 0)
        self.assertEqual(counts["belts"], 4)
        self.assertEqual(counts["undergrounds"], 2)
        self.assertEqual(counts["splitters"], 0)
        self.assertEqual(counts["inserters"], 2)
        self.assertEqual(counts["machines"], 1)
        self.assertEqual(counts["poles"], 0)
        self.assertEqual(counts["pipes"], 0)
        self.assertEqual(counts["beacons"], 0)
        self.assertEqual(counts["roboports"], 0)
        self.assertEqual(counts["other"], 1)
        self.assertEqual(counts["entities_excluding_roboports"], 10)

    def test_ACC16_target_accepts_exact_values_and_windows(self):
        target = {
            "note": "roboports are excluded",
            "belts": {"min": 4, "max": 4},
            "inserters": 2,
            "entities_excluding_roboports": 9,
        }
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            json.dump(target, handle)
            target_path = handle.name
        try:
            status, counts = audit(control(), "--expect-target", target_path)
            self.assertEqual(status, 0, counts)
        finally:
            pathlib.Path(target_path).unlink()

    def test_ACC17_target_reports_mismatch_after_counts(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            json.dump({"splitters": 99}, handle)
            target_path = handle.name
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as handle:
            handle.write(encode(control()) + "\n")
            artifact_path = handle.name
        try:
            done = subprocess.run([sys.executable, str(AUDIT), artifact_path, "--expect-target", target_path, "-q"],
                                  capture_output=True, text=True)
            self.assertEqual(done.returncode, 1)
            self.assertIn("splitters", done.stderr)
            self.assertIn("delivered 0", done.stderr)
            self.assertIn("entities", done.stdout)
        finally:
            pathlib.Path(target_path).unlink()
            pathlib.Path(artifact_path).unlink()

    def test_ACC18_human_report_names_roboport_exclusion(self):
        entities = control() + [{"name": "roboport", "position": {"x": 30.5, "y": 30.5}}]
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as handle:
            handle.write(encode(entities) + "\n")
            artifact_path = handle.name
        try:
            done = subprocess.run([sys.executable, str(AUDIT), artifact_path], capture_output=True, text=True)
            self.assertEqual(done.returncode, 0)
            self.assertIn("roboport", done.stdout.lower())
            self.assertIn("exclud", done.stdout.lower())
            self.assertIn("1", done.stdout)
        finally:
            pathlib.Path(artifact_path).unlink()
