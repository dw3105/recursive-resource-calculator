"""Turn and Flip pose check (round 54): a census row whose machines ignore the forced pose is not valid."""
import base64, json, os, sys, unittest, zlib

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import turn_flip_pose  # noqa: E402


def bp(*machines):
    entities = [{"entity_number": i + 1, "name": "foundry", "position": {"x": 2.5, "y": 2.5}, "recipe": "casting-iron"}
                for i in range(len(machines))]
    for entity, (direction, mirror) in zip(entities, machines):
        if direction:
            entity["direction"] = direction
        if mirror:
            entity["mirror"] = True
    entities.append({"entity_number": 99, "name": "pipe", "position": {"x": 0.5, "y": 0.5}})
    raw = json.dumps({"blueprint": {"entities": entities}}).encode()
    return "0" + base64.b64encode(zlib.compress(raw)).decode()


class PoseTest(unittest.TestCase):
    def test_turn_and_flip_applied(self):
        self.assertEqual(turn_flip_pose.check(bp((4, True), (4, True)), 4, True), [])
        print("TFP1 turned and mirrored machines pass")

    def test_turn_dropped_on_flip(self):
        self.assertTrue(turn_flip_pose.check(bp((0, True)), 4, True))
        print("TFP2 a flipped machine left north fails a Turn 4 row")

    def test_flip_dropped_or_extra(self):
        self.assertTrue(turn_flip_pose.check(bp((8, False)), 8, True))
        self.assertTrue(turn_flip_pose.check(bp((8, True)), 8, False))
        self.assertEqual(turn_flip_pose.check(bp((0, False)), 0, False), [])
        print("TFP3 missing or unasked mirror fails")

    def test_flip_that_moves_no_pipe(self):
        self.assertEqual(turn_flip_pose.check(bp((4, False)), 4, True, can_flip={"chemical-plant"}), [])
        self.assertTrue(turn_flip_pose.check(bp((4, True)), 4, True, can_flip={"chemical-plant"}))
        self.assertEqual(turn_flip_pose.flippable({"catalog": {"entities": [{"name": "foundry", "can_flip": True},
                                                                            {"name": "assembling-machine-2"}]}}), {"foundry"})
        print("TFP5 a Flip on a machine that cannot flip is the same build, no mirror")

    def test_no_machine(self):
        self.assertTrue(turn_flip_pose.check(bp(), 0, False))
        print("TFP4 a blueprint with no recipe machine fails")


if __name__ == "__main__":
    unittest.main()
