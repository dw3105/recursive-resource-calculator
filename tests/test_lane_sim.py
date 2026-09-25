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


if __name__ == "__main__":
    unittest.main()
