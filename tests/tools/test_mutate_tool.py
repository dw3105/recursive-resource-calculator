"""The mutation runner's own regressions: what counts as a kill, and which checkout it may touch.

Both rules were broken by the previous runner. A crash that merely looks like a failing case used to count as a
kill, and the checkout was a hardcoded constant, so "run it on a scratch clone" was never true.
"""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools"))

import mutate  # noqa: E402  (imported after the path is set)


class ParsesHarnessOutput(unittest.TestCase):
    def test_reads_case_and_kind_from_a_failure_line(self):
        failures = mutate.parse_failures("FAIL W1-snapshot S1 [assert]\nFAIL W1-snapshot S2 [error]\nnoise\n")
        self.assertEqual(failures, [{"case": "W1-snapshot S1", "tag": "assert"},
                                    {"case": "W1-snapshot S2", "tag": "error"}])

    def test_ignores_an_untagged_line(self):
        self.assertEqual(mutate.parse_failures("FAIL W1-snapshot S1\n"), [])


class ClassifiesAMutant(unittest.TestCase):
    def verdict(self, output, exit_code, expect="W1-snapshot S1", require="assert"):
        return mutate.classify(mutate.parse_failures(output), expect, exit_code, require)[0]

    def test_the_expected_case_failing_as_an_assertion_is_a_kill(self):
        self.assertEqual(self.verdict("FAIL W1-snapshot S1 [assert]\n", 1), "CAUGHT")

    def test_the_expected_case_crashing_is_not_a_kill(self):
        self.assertEqual(self.verdict("FAIL W1-snapshot S1 [error]\n", 1), "INVALID")

    def test_another_case_failing_is_not_a_kill(self):
        self.assertEqual(self.verdict("FAIL W2-jobs J4 [assert]\n", 1), "MISSED")

    def test_a_syntax_failure_with_no_case_is_not_a_kill(self):
        self.assertEqual(self.verdict("lua5.2: tests/test_x.lua:3: unexpected symbol\n", 1), "MISSED")

    def test_a_green_run_is_a_surviving_mutant(self):
        self.assertEqual(self.verdict("test_x: 4 cases, 4 passed, 0 failed\n", 0), "MISSED")

    def test_require_any_accepts_a_crash_when_asked_explicitly(self):
        self.assertEqual(self.verdict("FAIL W1-snapshot S1 [error]\n", 1, require="any"), "CAUGHT")


class OperatesOnTheNamedCheckoutOnly(unittest.TestCase):
    """A disposable repository is built here; the outer working tree must come back byte-identical."""

    def build_repo(self, directory):
        def git(*args):
            subprocess.run(["git", *args], cwd=directory, check=True, capture_output=True)

        git("init", "-q")
        git("config", "user.email", "test@example.invalid")
        git("config", "user.name", "test")
        (directory / "subject.lua").write_text("return {value = 2}\n")
        (directory / "tests").mkdir()
        (directory / "tests" / "test_subject.lua").write_text(
            'local subject = dofile("subject.lua")\n'
            'if subject.value == 2 then print("test_subject: 1 cases, 1 passed, 0 failed") os.exit(0) end\n'
            'print("FAIL S1 subject keeps its value [assert]")\n'
            'print("test_subject: 1 cases, 0 passed, 1 failed")\n'
            'os.exit(1)\n')
        git("add", ".")
        git("commit", "-q", "-m", "fixture")
        return subprocess.run(["git", "rev-parse", "HEAD"], cwd=directory, capture_output=True, text=True).stdout.strip()

    def run_tool(self, repo, sha, mutations, workdir):
        catalogue = workdir / "mutations.json"
        catalogue.write_text(json.dumps(mutations))
        return subprocess.run([sys.executable, str(REPO / "tools" / "mutate.py"),
                               "--repo", str(repo), "--candidate-sha", sha, str(catalogue)],
                              capture_output=True, text=True)

    def test_mutating_a_clone_leaves_the_outer_tree_untouched(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            clone, sentinel_home = temp / "clone", temp / "outer"
            clone.mkdir()
            sentinel_home.mkdir()
            sha = self.build_repo(clone)
            sentinel = sentinel_home / "subject.lua"
            sentinel.write_text("return {value = 2} -- an unrelated edit somebody else is holding\n")
            before = sentinel.read_bytes()

            result = self.run_tool(clone, sha, [{"id": "M1", "file": "subject.lua", "old": "value = 2",
                                                 "new": "value = 3", "test": "tests/test_subject.lua",
                                                 "expect": "S1 subject keeps its value"}], temp)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("CAUGHT M1", result.stdout)
            self.assertEqual(sentinel.read_bytes(), before)
            self.assertEqual((clone / "subject.lua").read_text(), "return {value = 2}\n")

    def test_a_wrong_candidate_sha_refuses_before_any_file_is_written(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            clone = temp / "clone"
            clone.mkdir()
            self.build_repo(clone)
            before = (clone / "subject.lua").read_bytes()

            result = self.run_tool(clone, "0" * 40, [{"id": "M1", "file": "subject.lua", "old": "value = 2",
                                                      "new": "value = 3", "test": "tests/test_subject.lua",
                                                      "expect": "S1"}], temp)

            self.assertEqual(result.returncode, 1)
            self.assertIn("not the candidate", result.stderr)
            self.assertEqual((clone / "subject.lua").read_bytes(), before)

    def test_a_dirty_checkout_refuses(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            clone = temp / "clone"
            clone.mkdir()
            sha = self.build_repo(clone)
            (clone / "subject.lua").write_text("return {value = 99}\n")

            result = self.run_tool(clone, sha, [{"id": "M1", "file": "subject.lua", "old": "value = 99",
                                                 "new": "value = 3", "test": "tests/test_subject.lua",
                                                 "expect": "S1"}], temp)

            self.assertEqual(result.returncode, 1)
            self.assertIn("uncommitted tracked changes", result.stderr)


if __name__ == "__main__":
    unittest.main()
