"""Sheet ports (round 54): a flipped machine's fluid box joins its pipe on the mirrored tile.

The lab read every Flip sheet's fluid inputs on the unflipped tiles ("input fluid/... has no feed tile", 42 of 144
sheets on 2.0). Flip = mirror x of the north shape, then Turn.
"""
import os, sys, unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import sheet_ports  # noqa: E402

# One box on the north face, one tile left of centre, of a 3x3 machine at (5.5, 5.5).
BOX = {"connections": [{"direction": 0, "positions": [{"x": -1, "y": -1}, {"x": 1, "y": -1}, {"x": 1, "y": 1}, {"x": -1, "y": 1}]}]}


def machine(direction=0, mirror=False):
    m = {"name": "chemical-plant", "position": {"x": 5.5, "y": 5.5}, "direction": direction}
    if mirror:
        m["mirror"] = True
    return m


class MirrorTest(unittest.TestCase):
    def test_plain_turns_read_the_table(self):
        self.assertEqual(sheet_ports.connection_tiles(machine(0), BOX), [(4, 3)])
        self.assertEqual(sheet_ports.connection_tiles(machine(4), BOX), [(7, 4)])
        print("SP1 unflipped boxes follow the rotation table")

    def test_flip_mirrors_x_then_turns(self):
        self.assertEqual(sheet_ports.connection_tiles(machine(0, True), BOX), [(6, 3)])
        self.assertEqual(sheet_ports.connection_tiles(machine(4, True), BOX), [(7, 6)])
        self.assertEqual(sheet_ports.connection_tiles(machine(8, True), BOX), [(4, 7)])
        print("SP2 flipped boxes: mirror x of the north shape, then Turn")


if __name__ == "__main__":
    unittest.main()
