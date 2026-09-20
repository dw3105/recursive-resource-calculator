"""The pinned API extracts must carry which subclass may answer each member, and the mock must agree.

Why this file exists. Rounds 1 to 10 read `LuaEntityPrototype::connection_distance` off a roboport. That member
is `subclasses: ["RollingStock"]`, so a roboport never answers it: on the real engine the read raised, and every
capture came back without the field. The test harness meanwhile fabricated a value for it, so the whole suite
sat on a branch the engine never takes, and the planner silently fell back to a one-tile roboport gap.

The old extract could not have caught this. `tools/extract_api.py` reduced attributes and methods to sorted name
lists, so changing a member's subclass from RollingStock to Roboport left the class metadata identical. Member
existence says nothing about applicability. The extract now records applicability, and these cases pin it.

Everything here is offline and deterministic: it reads the committed extracts and the committed harness. No
network, no Factorio.
"""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
VERSIONS = ("2.0.77", "2.1.19")

# Factorio subclass name -> the prototype `type` strings an instance of it reports.
SUBCLASS_TYPES = {
    "RollingStock": {"locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon"},
    "Roboport": {"roboport"},
}


def extract(version: str) -> dict:
    return json.loads((ROOT / "docs" / "api" / f"{version}.members.json").read_text())


def applicability(version: str, cls: str = "LuaEntityPrototype") -> dict:
    return extract(version)["classes"][cls]["applicability"]


def harness_gates() -> dict:
    """member -> the set of prototype types tests/harness.lua lets answer it."""
    source = (ROOT / "tests" / "harness.lua").read_text()
    gates = {}
    for name, body in re.findall(r'^\s*(\w+)\s*=\s*gate\(\{([^}]*)\}\),', source, re.MULTILINE):
        gates[name] = {piece.strip().strip('"') for piece in body.split(",") if piece.strip()}
    return gates


class ApplicabilityRecorded(unittest.TestCase):
    def test_every_pinned_class_records_applicability(self):
        for version in VERSIONS:
            with self.subTest(version=version):
                classes = extract(version)["classes"]
                self.assertTrue(classes, "the extract lists classes")
                for name, cls in classes.items():
                    self.assertIn("applicability", cls, f"{name} records applicability")
                    self.assertIsInstance(cls["applicability"], dict)

    def test_the_entity_prototype_applicability_is_not_empty(self):
        for version in VERSIONS:
            with self.subTest(version=version):
                self.assertGreater(len(applicability(version)), 100,
                                   "LuaEntityPrototype has many subclass-restricted members")


class RoboportMembers(unittest.TestCase):
    """The three members this round turned on. A subclass-only change to any of them fails here."""

    def test_connection_distance_belongs_to_rolling_stock_not_roboports(self):
        for version in VERSIONS:
            with self.subTest(version=version):
                self.assertEqual(applicability(version)["connection_distance"], ["RollingStock"])

    def test_the_radii_belong_to_roboports(self):
        for version in VERSIONS:
            with self.subTest(version=version):
                self.assertEqual(applicability(version)["logistic_radius"], ["Roboport"])
                self.assertEqual(applicability(version)["construction_radius"], ["Roboport"])

    def test_a_roboport_can_never_answer_connection_distance(self):
        for version in VERSIONS:
            with self.subTest(version=version):
                owners = applicability(version)["connection_distance"]
                types = set().union(*(SUBCLASS_TYPES[owner] for owner in owners))
                self.assertNotIn("roboport", types,
                                 "reading connection_distance off a roboport is invalid on this version")


class MockMatchesTheApi(unittest.TestCase):
    """The harness gate and the pinned API must say the same thing, or tests run on a branch the engine never
    takes. This is the check that would have caught the fabricated roboport distance in round 1."""

    def test_the_harness_gates_the_same_types_the_api_names(self):
        gates = harness_gates()
        for member in ("connection_distance", "logistic_radius", "construction_radius"):
            with self.subTest(member=member):
                self.assertIn(member, gates, f"tests/harness.lua gates {member}")
                for version in VERSIONS:
                    owners = applicability(version)[member]
                    expected = set().union(*(SUBCLASS_TYPES[owner] for owner in owners))
                    self.assertEqual(gates[member], expected,
                                     f"{version}: harness gate for {member} matches its subclasses")

    def test_the_harness_never_fabricates_a_roboport_connection_distance(self):
        source = (ROOT / "tests" / "harness.lua").read_text()
        add_roboport = source[source.index("function world.add_roboport"):]
        add_roboport = add_roboport[:add_roboport.index("\n    end")]
        self.assertNotIn("connection_distance", add_roboport,
                         "a roboport mock that answers connection_distance hides the real engine behaviour")


class ProductionNeverReadsIt(unittest.TestCase):
    def test_the_catalog_does_not_read_connection_distance_from_a_prototype(self):
        source = (ROOT / "logic" / "catalog.lua").read_text()
        self.assertNotIn("entity.connection_distance", source,
                         "logic/catalog.lua must not read a rolling-stock member off a roboport prototype")


if __name__ == "__main__":
    unittest.main()
