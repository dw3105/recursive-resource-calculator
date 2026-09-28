#!/usr/bin/env python3
"""Check one lane's diff against the files that lane owns.

Usage:
    python3 tools/lane_ownership.py --base <lane base sha> --manifest <docs/tasks/NNN_name.manifest>
    python3 tools/lane_ownership.py write-manifest --task <task.md> --out <manifest>
    python3 tools/lane_ownership.py check --base <commit sha> --task <task.md>

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
import re
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


def ownership_overlaps(left, right):
    """Return whether two manifest entries can own the same changed path.

    A trailing slash is part of the manifest language: it makes the entry a
    directory owner.  Keeping this small predicate here lets the dispatch
    preflight use exactly the same directory boundary rule as the post-commit
    ownership check without changing that check's permissive manifest reader.
    """
    left_directory = left.endswith("/")
    right_directory = right.endswith("/")
    left = left.rstrip("/")
    right = right.rstrip("/")
    if not left_directory and not right_directory:
        return left == right
    if left_directory and right_directory:
        return left == right or left.startswith(right + "/") or right.startswith(left + "/")
    directory, path = (left, right) if left_directory else (right, left)
    return path.startswith(directory + "/")


def check_ownership(repo, base, owned, required, uncommitted=()):
    changed = {line for line in git(repo, "diff", "--name-only", base, "HEAD").splitlines() if line.strip()}

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
    descends = subprocess.run(["git", "merge-base", "--is-ancestor", base, "HEAD"], cwd=repo).returncode == 0
    if not descends:
        problems.append("HEAD does not descend from the lane base %s" % base)
    problems.extend("uncommitted change: %s" % path for path in uncommitted)

    for problem in problems:
        print("OWNERSHIP: %s" % problem)
    if problems:
        return 1
    print("owned-only: %d file(s) changed, %d required deliverable(s) present" % (len(changed), len(required)))
    return 0


def owned_from_task(text):
    lines = text.splitlines()
    try:
        start = lines.index("## Files this lane owns") + 1
    except ValueError:
        return None
    entries = []
    for line in lines[start:]:
        if line.startswith("# ") or line.startswith("## "):
            break
        if line.startswith("- "):
            match = re.match(r"^- `(!?)([^`]+)`", line)
            if not match:
                raise ValueError('refused: owned line is not "- `path`": %s' % line)
            required, path = match.groups()
            validate_owned_path(path)
            entries.append((path, bool(required)))
    seen = set()
    for path, _ in entries:
        if path in seen:
            raise ValueError("refused: bad owned path: %s" % path)
        seen.add(path)
    return entries


def validate_owned_path(path):
    if (not path or path.startswith("/") or "\\" in path or any(c.isspace() for c in path)
            or any(part in ("", "..") for part in path.rstrip("/").split("/"))):
        raise ValueError("refused: bad owned path: %s" % path)


def write_manifest(argv):
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--task")
    source.add_argument("--path", action="append")
    parser.add_argument("--out", required=True)
    parser.add_argument("--repo", default=".")
    args = parser.parse_args(argv)
    if args.task:
        text = Path(args.task).read_text()
        entries = owned_from_task(text)
        if entries is None:
            print("refused: no '## Files this lane owns' section in %s" % args.task)
            return 2
        label = args.task
    else:
        entries, label = [], "--path"
        try:
            for item in args.path:
                required = item.startswith("!")
                path = item[1:] if required else item
                validate_owned_path(path)
                entries.append((path, required))
        except ValueError as exc:
            print(str(exc)); return 2
    if len({path for path, _ in entries}) != len(entries):
        print("refused: bad owned path: %s" % next(path for i, (path, _) in enumerate(entries) if path in [p for p, _ in entries[:i]]))
        return 2
    if not entries:
        print("refused: no owned paths in %s" % label)
        return 2
    repo = Path(args.repo).expanduser().resolve()
    for path, required in entries:
        if not required and not (repo / path.rstrip("/")).exists():
            print("refused: owned path must exist at base or carry '!': %s" % path)
            return 2
    Path(args.out).write_text("# written by tools/lane_ownership.py write-manifest\n" +
                              "".join(("!" if required else "") + path + "\n" for path, required in entries))
    print("wrote %s: %d path(s), %d required" % (args.out, len(entries), sum(required for _, required in entries)))
    return 0


def check_command(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--task")
    source.add_argument("--manifest")
    parser.add_argument("--repo", default=".")
    args = parser.parse_args(argv)
    if not re.match(r"^[0-9a-f]{7,40}$", args.base):
        print("refused: base must be a commit sha, not a ref: %s" % args.base)
        return 2
    repo = Path(args.repo).expanduser().resolve()
    if args.task:
        task = Path(args.task)
        try:
            relative = task.resolve().relative_to(repo).as_posix()
        except ValueError:
            relative = args.task
        result = subprocess.run(["git", "show", "%s:%s" % (args.base, relative)], cwd=repo, capture_output=True, text=True)
        if result.returncode:
            print("refused: task not in base %s: %s" % (args.base, relative))
            return 2
        try:
            entries = owned_from_task(result.stdout)
        except ValueError as exc:
            print(str(exc)); return 2
        if entries is None:
            print("refused: no '## Files this lane owns' section in %s" % args.task)
            return 2
        if not entries:
            print("refused: no owned paths in %s" % args.task)
            return 2
        owned = {path for path, _ in entries}
        required = {path for path, req in entries if req}
    else:
        owned, required = read_manifest(args.manifest)
    status = git(repo, "status", "--porcelain", "--untracked-files=all")
    uncommitted = []
    for line in status.splitlines():
        path = line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        uncommitted.append(path)
    return check_ownership(repo, args.base, owned, required, uncommitted)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] == "write-manifest":
        return write_manifest(argv[1:])
    if argv and argv[0] == "check":
        return check_command(argv[1:])
    parser = argparse.ArgumentParser(description="Check a lane's diff against the files it owns.")
    parser.add_argument("--base", required=True, help="the lane's own base commit (its wave tag)")
    parser.add_argument("--manifest", required=True, help="the lane's ownership manifest")
    parser.add_argument("--repo", default=".", help="the checkout to inspect (default: the current directory)")
    args = parser.parse_args(argv)

    repo = Path(args.repo).expanduser().resolve()
    owned, required = read_manifest(args.manifest)
    return check_ownership(repo, args.base, owned, required)


if __name__ == "__main__":
    sys.exit(main())
