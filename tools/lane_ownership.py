#!/usr/bin/env python3
"""Check one lane's diff against the files that lane owns.

Usage:
    python3 tools/lane_ownership.py --base <lane base sha> --manifest <docs/tasks/NNN_name.manifest>

Three separate things are checked, because a lane can obey one and break another:

  * subset      every changed path is one the lane owns
  * deliverable every path the manifest marks "!" was actually changed
  * base        HEAD really descends from the base the lane was given

The base is the lane's own wave base, not the spine: waves after the first inherit earlier waves' files, and a
compliant lane must not fail for carrying them. Nothing is written to disk and no fixed temporary path is used,
because six lanes run at once and /tmp is not isolated by a worktree.

Manifest format: one path per line, "!" prefix marks a required deliverable, "#" starts a comment. A line ending
with "/" owns a whole directory: every changed path under it is owned, and marking it "!" demands at least one
changed path under it. A lane that creates a tree of case directories cannot list every file in advance.
"""

import argparse
import subprocess
import sys
from pathlib import Path


def git(repo, *args):
    result = subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit("refused: git %s failed: %s" % (" ".join(args), result.stderr.strip()))
    return result.stdout


def read_manifest(path):
    owned, required = set(), set()
    for line in Path(path).read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("!"):
            line = line[1:].strip()
            required.add(line)
        owned.add(line)
    return owned, required


def main(argv=None):
    parser = argparse.ArgumentParser(description="Check a lane's diff against the files it owns.")
    parser.add_argument("--base", required=True, help="the lane's own base commit (its wave tag)")
    parser.add_argument("--manifest", required=True, help="the lane's ownership manifest")
    parser.add_argument("--repo", default=".", help="the checkout to inspect (default: the current directory)")
    args = parser.parse_args(argv)

    repo = Path(args.repo).expanduser().resolve()
    owned, required = read_manifest(args.manifest)
    changed = {line for line in git(repo, "diff", "--name-only", args.base, "HEAD").splitlines() if line.strip()}

    prefixes = sorted(path for path in owned if path.endswith("/"))

    def owned_by_prefix(path):
        return any(path.startswith(prefix) for prefix in prefixes)

    problems = []
    for path in sorted(changed - owned):
        if not owned_by_prefix(path):
            problems.append("not owned by this lane: %s" % path)
    for path in sorted(required - changed):
        if path.endswith("/"):
            if not any(changed_path.startswith(path) for changed_path in changed):
                problems.append("required directory holds no changed file: %s" % path)
        else:
            problems.append("required deliverable never changed: %s" % path)
    descends = subprocess.run(["git", "merge-base", "--is-ancestor", args.base, "HEAD"], cwd=repo).returncode == 0
    if not descends:
        problems.append("HEAD does not descend from the lane base %s" % args.base)

    for problem in problems:
        print("OWNERSHIP: %s" % problem)
    if problems:
        return 1
    print("owned-only: %d file(s) changed, %d required deliverable(s) present" % (len(changed), len(required)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
