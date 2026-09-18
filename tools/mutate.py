#!/usr/bin/env python3
"""Plant one mutation at a time in a named checkout, run a test file, report which cases fail, restore.

Usage:
    python3 tools/mutate.py --repo <checkout> --candidate-sha <sha> [--require assert|any] <mutations.json>

Two rules this tool exists to keep, both of which the round 7 runner broke:

1. It operates on the checkout named by --repo, and on no other. Every git call and every file write resolves
   against that path, and the run refuses before touching a file unless that checkout is clean and its HEAD is the
   candidate the caller asked for. A working tree somewhere else, with unrelated edits in it, is never read.

2. A mutant counts as caught only when the expected case fails as an assertion: the harness prints
   "FAIL <case> [assert]" for a failed assertion and "FAIL <case> [error]" for anything else, so a mutant that
   merely crashes the test proves nothing about the assertion that was supposed to catch it. Those are reported
   INVALID, separately from a surviving mutant, and both fail the run.

Each entry is {"id", "file", "old", "new", "test", "shapes", "expect"}, or {"id", "edits": [...], ...} for a
mutant that needs several edits applied together.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

FAIL_LINE = re.compile(r"^FAIL (?P<case>.*?) \[(?P<tag>assert|error)\]$")


def parse_failures(output):
    """Every failing case in a test run, with the kind of failure the harness reported."""
    failures = []
    for line in output.splitlines():
        match = FAIL_LINE.match(line.rstrip())
        if match:
            failures.append({"case": match.group("case"), "tag": match.group("tag")})
    return failures


def classify(failures, expect, exit_code, require):
    """CAUGHT, INVALID or MISSED for one mutant."""
    if exit_code == 0:
        return "MISSED", "the test suite stayed green"
    matching = [failure for failure in failures if expect in failure["case"]]
    if not matching:
        return "MISSED", "no failing case contains %r" % expect
    if require == "assert" and not any(failure["tag"] == "assert" for failure in matching):
        return "INVALID", "%r failed as [error], so its assertion never ran" % matching[0]["case"]
    return "CAUGHT", matching[0]["case"]


class Checkout:
    """The one checkout this run may read or write."""

    def __init__(self, path, candidate_sha):
        self.path = Path(path).expanduser().resolve()
        if not (self.path / ".git").exists():
            raise SystemExit("refused: %s is not a git checkout" % self.path)
        head = self.git("rev-parse", "HEAD").strip()
        if not head.startswith(candidate_sha) and not candidate_sha.startswith(head):
            raise SystemExit("refused: %s is at %s, not the candidate %s" % (self.path, head[:12], candidate_sha[:12]))
        if self.git("status", "--porcelain", "--untracked-files=no").strip():
            raise SystemExit("refused: %s has uncommitted tracked changes; mutation results would be unattributable" % self.path)
        self.head = head

    def git(self, *args):
        result = subprocess.run(["git", *args], cwd=self.path, capture_output=True, text=True)
        if result.returncode != 0:
            raise SystemExit("refused: git %s failed in %s: %s" % (" ".join(args), self.path, result.stderr.strip()))
        return result.stdout

    def run_test(self, test, shapes):
        env = dict(os.environ, RRC_SHAPES=shapes)
        return subprocess.run(["lua5.2", test], cwd=self.path, capture_output=True, text=True, env=env)

    def apply(self, edits, mutant_id):
        """Plant every edit of one mutant; each pattern must occur exactly once."""
        touched = sorted({edit["file"] for edit in edits})
        for edit in edits:
            path = self.path / edit["file"]
            with open(path, newline="") as handle:
                source = handle.read()
            eol = "\r\n" if "\r\n" in source else "\n"
            old, new = edit["old"].replace("\n", eol), edit["new"].replace("\n", eol)
            count = source.count(old)
            if count != 1:
                self.restore(touched)
                raise SystemExit("%s: pattern found %d times in %s, expected 1" % (mutant_id, count, edit["file"]))
            with open(path, "w", newline="") as handle:
                handle.write(source.replace(old, new))
        return touched

    def restore(self, files):
        if files:
            self.git("checkout", "--", *files)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Plant mutations in one named checkout and report which are caught.")
    parser.add_argument("mutations", help="JSON file describing the mutants")
    parser.add_argument("--repo", required=True, help="the checkout to mutate; never the working tree you are editing")
    parser.add_argument("--candidate-sha", required=True, help="the commit that checkout must be at")
    parser.add_argument("--require", choices=("assert", "any"), default="assert",
                        help="assert (default): a kill needs FAIL <case> [assert]")
    args = parser.parse_args(argv)

    mutations = json.loads(Path(args.mutations).read_text())
    checkout = Checkout(args.repo, args.candidate_sha)
    print("checkout %s at %s" % (checkout.path, checkout.head[:12]))

    for test, shapes in sorted({(m["test"], m.get("shapes", "2.0")) for m in mutations}):
        baseline = checkout.run_test(test, shapes)
        if baseline.returncode != 0:
            raise SystemExit("baseline red for %s shapes=%s; mutation results would mean nothing\n%s" % (test, shapes, baseline.stdout))
        print("baseline green: %s shapes=%s: %s" % (test, shapes, baseline.stdout.strip().splitlines()[-1]))

    missed, invalid = [], []
    for mutant in mutations:
        edits = mutant.get("edits") or [{"file": mutant["file"], "old": mutant["old"], "new": mutant["new"]}]
        touched = checkout.apply(edits, mutant["id"])
        result = checkout.run_test(mutant["test"], mutant.get("shapes", "2.0"))
        checkout.restore(touched)
        failures = parse_failures(result.stdout)
        verdict, detail = classify(failures, mutant["expect"], result.returncode, args.require)
        print("%s %s -> %s" % (verdict, mutant["id"], detail))
        if verdict == "MISSED":
            missed.append(mutant["id"])
        elif verdict == "INVALID":
            invalid.append(mutant["id"])

    if checkout.git("status", "--porcelain", "--untracked-files=no").strip():
        raise SystemExit("checkout not restored after mutations")
    print("%d mutations, %d caught, missed: %s, invalid: %s" % (len(mutations), len(mutations) - len(missed) - len(invalid), missed, invalid))
    return 1 if missed or invalid else 0


if __name__ == "__main__":
    sys.exit(main())
