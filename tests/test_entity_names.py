import base64
import json
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "entity_names.py"


class EntityNamesTest(unittest.TestCase):
    def run_audit(self, names):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bp = root / "bp.txt"
            prepared = root / "prepared.json"
            payload = {"blueprint": {"entities": [
                {"entity_number": i, "name": name, "position": {"x": i, "y": 0}}
                for i, name in enumerate(names, 1)
            ]}}
            bp.write_text("0" + base64.b64encode(zlib.compress(json.dumps(payload).encode())).decode())
            prepared.write_text(json.dumps({"settings": {
                "inserter": {"name": "fast-inserter"},
                "long_inserter": {"name": "long-handed-inserter"},
            }}))
            return subprocess.run([sys.executable, str(TOOL), str(bp), str(prepared)],
                                  text=True, capture_output=True)

    def test_wrong_inserter_is_reported(self):
        result = self.run_audit(["inserter"])
        self.assertEqual(result.returncode, 1)
        self.assertIn("NAMES-BAD n=1", result.stdout)

    def test_picked_inserters_are_accepted(self):
        result = self.run_audit(["fast-inserter", "long-handed-inserter"])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "NAMES-OK")


if __name__ == "__main__":
    unittest.main()
