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

    def test_ACC4_reversed_output_inserter_strands_its_belt(self):
        """Both endpoints stay legal, so only the obligation walk can see this."""
        entities = control()
        entities[4]["direction"] = 12
        status, counts = audit(entities)
        self.assertEqual(status, 1)
        self.assertGreaterEqual(counts["unused_belt_tiles"], 1)

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
        self.assertEqual(counts["unused_belt_tiles"], 224)
        self.assertEqual(counts["unused_pipe_tiles"], 35)
        self.assertEqual(counts["wires"], 0)


if __name__ == "__main__":
    unittest.main()
