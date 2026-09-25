"""Compatibility entry point for the prepared export converter tests."""
import json

from tests.tools.test_prepared_from_export import *  # noqa: F401,F403


class InserterFactsTest(PreparedInputTest):
    def test_PE12_inserter_game_and_force_facts_pass_through(self):
        export = json.loads(json.dumps(MINIMAL_EXPORT))
        export["prototypes"]["inserter"] = {"name": "modded-inserter", "rotation_speed": 0.08,
            "extension_speed": 0.04, "bulk": True, "inserter_stack_size_bonus": 2,
            "bulk_inserter_capacity_bonus": 3, "items_per_second": 13.2}
        _, prepared, _ = self.build(export)
        self.assertEqual(prepared["catalog"]["inserter"]["rotation_speed"], 0.08)
        self.assertEqual(prepared["catalog"]["inserter"]["extension_speed"], 0.04)
        self.assertIs(prepared["catalog"]["inserter"]["bulk"], True)
        self.assertEqual(prepared["catalog"]["inserter"]["bulk_inserter_capacity_bonus"], 3)
