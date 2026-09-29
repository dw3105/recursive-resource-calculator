"""A hand drop onto either splitter half must seed the shared splitter input."""
import ast
import unittest
from pathlib import Path


class HandDropTests(unittest.TestCase):
    def test_drop_seeds_both_splitter_halves(self):
        # Exercise the simulator's receiver selection with a tiny two-tile blueprint model.
        source = (Path(__file__).parents[1] / "tools/lane_sim.py").read_text()
        tree = ast.parse(source)
        fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "hand_receivers")
        env = {"splitter_of": {(1, 0): (4, [(1, 0), (1, 1)]), (1, 1): (4, [(1, 0), (1, 1)])}}
        exec(compile(ast.Module(body=[fn], type_ignores=[]), "lane_sim.py", "exec"), env)
        self.assertEqual(env["hand_receivers"]((1, 0)), [(1, 0), (1, 1)])


class SplitterSideLoadTests(unittest.TestCase):
    """LS1 red on 9d5caca: gray + magenta 2026-09-29, a west splitter (41,95)-(41,96) side-loads the south row head
    (40,96) whose other side takes iron-plate; lane_sim copied both splitter lanes straight across and read MIXED."""

    def test_splitter_output_into_belt_side_is_a_side_load(self):
        import base64, json, subprocess, sys, tempfile, zlib
        W, E, S = 12, 4, 8
        ents = [
            {"name": "turbo-transport-belt", "position": {"x": 2.5, "y": 2.5}, "direction": S},
            {"name": "turbo-transport-belt", "position": {"x": 2.5, "y": 3.5}, "direction": S},
            {"name": "turbo-transport-belt", "position": {"x": 1.5, "y": 2.5}, "direction": E},
            {"name": "turbo-splitter", "position": {"x": 3.5, "y": 2.0}, "direction": W},
            {"name": "turbo-transport-belt", "position": {"x": 4.5, "y": 1.5}, "direction": W},
            {"name": "turbo-transport-belt", "position": {"x": 4.5, "y": 2.5}, "direction": W},
            {"name": "bulk-inserter", "position": {"x": 1.5, "y": 3.5}, "direction": E},
            {"name": "assembling-machine-3", "position": {"x": -0.5, "y": 3.5}},
        ]
        for i, e in enumerate(ents, 1):
            e["entity_number"] = i
        raw = json.dumps({"blueprint": {"item": "blueprint", "entities": ents, "version": 1}}).encode()
        text = "0" + base64.b64encode(zlib.compress(raw, 9)).decode()
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
            f.write(text)
        tool = Path(__file__).parents[1] / "tools/lane_sim.py"
        out = subprocess.run([sys.executable, str(tool), f.name], capture_output=True, text=True, timeout=60).stdout
        self.assertIn("LANE-SIM mixed=0", out.strip().splitlines()[-1], out)


if __name__ == "__main__":
    unittest.main()
