"""Red on round-56-base: recipe, lock and pinned image metadata do not exist. 2026-10-04."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class RecipeTests(unittest.TestCase):
    def test_RC1_recipe_uses_auto_split_and_ids(self):
        recipe = json.loads((ROOT / "ci/suite-runner/rrc.recipe.json").read_text())
        self.assertEqual(recipe["split"], "auto")
        self.assertIn("{ids}", recipe["test"]["command"])
        print("RC1")

    def test_RC2_lock_is_placeholder_digest_line(self):
        lock = (ROOT / "ci/image.lock").read_text().strip()
        self.assertRegex(lock, r"^.+@sha256:[0-9a-f]{64} # TODO-integrator$")
        print("RC2")

    def test_RC3_dockerfile_pins_factorio_versions(self):
        dockerfile = (ROOT / "ci/image/Dockerfile").read_text()
        self.assertRegex(dockerfile, r"2\.0\.77")
        self.assertRegex(dockerfile, r"2\.1\.20")
        print("RC3")


if __name__ == "__main__":
    unittest.main()
