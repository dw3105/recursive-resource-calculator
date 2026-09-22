import contextlib
import io
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import collision_report as report  # noqa: E402


class CollisionReportTests(unittest.TestCase):
    def test_two_belts_one_tile_apart_do_not_overlap(self):
        entities = [
            {"id": "a", "name": "transport-belt", "position": {"x": 0.5, "y": 0.5}, "direction": 4},
            {"id": "b", "name": "transport-belt", "position": {"x": 1.5, "y": 0.5}, "direction": 4},
        ]
        self.assertEqual(report.overlapping_pairs(entities), [])

    def test_two_belts_on_one_tile_name_both_ids(self):
        entities = [
            {"id": "belt-a", "name": "transport-belt", "position": {"x": 0.5, "y": 0.5}},
            {"id": "belt-b", "name": "transport-belt", "position": {"x": 0.5, "y": 0.5}},
        ]
        pairs = report.overlapping_pairs(entities)
        self.assertEqual(len(pairs), 1)
        line = report.format_pair(pairs[0])
        self.assertIn("belt-a", line)
        self.assertIn("belt-b", line)

    def test_centred_splitter_next_to_belt_does_not_overlap(self):
        entities = [
            {"id": "split", "name": "splitter", "splitter": True,
             "position": {"x": 12.5, "y": 9.0}, "direction": 4},
            {"id": "belt", "name": "transport-belt", "position": {"x": 13.5, "y": 8.5}, "direction": 4},
        ]
        self.assertEqual(report.overlapping_pairs(entities), [])

    def test_shifted_splitter_overlaps_and_is_named(self):
        entities = [
            {"id": "split", "name": "splitter", "splitter": True,
             "position": {"x": 13.0, "y": 9.0}, "direction": 4},
            {"id": "belt", "name": "transport-belt", "position": {"x": 13.5, "y": 8.5}, "direction": 4},
        ]
        pairs = report.overlapping_pairs(entities)
        self.assertEqual(len(pairs), 1)
        self.assertIn("splitter", report.format_pair(pairs[0]))

    def test_rectangle_member_without_position_uses_its_centre(self):
        entities = [
            {"id": "rect-a", "name": "transport-belt", "x": 2, "y": 3, "w": 1, "h": 1},
            {"id": "rect-b", "name": "transport-belt", "position": {"x": 2.5, "y": 3.5}},
        ]
        pairs = report.overlapping_pairs(entities)
        self.assertEqual(len(pairs), 1)
        self.assertEqual((pairs[0]["left"]["cx"], pairs[0]["left"]["cy"]), (2.5, 3.5))

    def test_report_is_diagnostic_and_prints_summary(self):
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            lines = report.report_lines([])
            for line in lines:
                print(line)
        self.assertEqual(lines, ["SUMMARY pairs=0 entities=0 splitters=0 underground=0"])
        self.assertIn("pairs=0", stream.getvalue())


if __name__ == "__main__":
    unittest.main()
