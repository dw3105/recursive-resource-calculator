#!/usr/bin/env python3
"""Turn and Flip pose check (round 54): every recipe machine in a census blueprint faces the forced turn and,
when the census asked for a flip, is mirrored. A census row whose blueprint ignored its forced pose is not valid.
Usage: python3 tools/turn_flip_pose.py <bp.txt> <turn 0|4|8|12> <flip 0|1>  -> prints POSE ok | POSE bad ..."""
import base64, json, sys, zlib


def machines(text):
    data = json.loads(zlib.decompress(base64.b64decode(text.strip()[1:])))
    blueprint = data.get("blueprint") or data
    return [e for e in blueprint.get("entities", []) if e.get("recipe")]


def check(text, turn, flip):
    bad = []
    found = machines(text)
    if not found:
        return ["no recipe machine"]
    for entity in found:
        direction = entity.get("direction", 0) or 0
        mirror = bool(entity.get("mirror"))
        if direction != turn or (flip and not mirror) or (not flip and mirror):
            bad.append("%s@%s,%s dir=%s mirror=%s" % (entity["name"], entity["position"]["x"], entity["position"]["y"],
                                                     direction, mirror))
    return bad


if __name__ == "__main__":
    path, turn, flip = sys.argv[1], int(sys.argv[2]), sys.argv[3] == "1"
    problems = check(open(path).read(), turn, flip)
    print("POSE ok" if not problems else "POSE bad " + "; ".join(problems[:4]))
