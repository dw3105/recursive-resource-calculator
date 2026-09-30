#!/usr/bin/env python3
"""MS1: material score counts blueprint entities and reports unknown names."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class MaterialScoreTest(unittest.TestCase):
    def test_score_and_unknown(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bp = root / "bp.json"
            bp.write_text(json.dumps({"result": {"entities": [
                {"name": "transport-belt"}, {"name": "transport-belt"}, {"name": "transport-belt"},
                {"name": "underground-belt"}, {"name": "mystery"}
            ]}}))
            fixture = root / "material.txt"
            fixture.write_text("MATERIAL transport-belt 1.5000\nMATERIAL underground-belt 8.7500\n")
            result = subprocess.run(["python3", str(ROOT / "tools/material_score.py"), str(bp), str(fixture)],
                                    check=True, text=True, capture_output=True)
            self.assertEqual(result.stdout.strip(), "material=13.2 unknown=1 unknown_names=mystery")
            print("MS1")

if __name__ == "__main__":
    unittest.main()
