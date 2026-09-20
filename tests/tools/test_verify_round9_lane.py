"""The round 9 lane verifier picks one lane's checks, and can never pick none."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "verify_round9_lane.sh"

CONSUMER_TESTS = {
    "086_preflight_facts": (
        "tests/test_preflight_quality_facts.lua",
        "tests/test_quality_policy.lua",
        "tests/test_bp_preflight.lua",
    ),
    "087_planner_facts": (
        "tests/test_plan_quality_facts.lua",
        "tests/test_quality_policy.lua",
        "tests/test_bp_plan.lua",
    ),
}
EVERY_TEST = sorted({path for paths in CONSUMER_TESTS.values() for path in paths})


def make_worktree(directory: Path, lua_exit: int = 0, gateslot_exit: int = 0) -> Path:
    """A worktree whose lua, lua5.4 and gateslot are harmless doubles that record their arguments."""
    worktree = directory / "worktree"
    (worktree / "tests" / "tools").mkdir(parents=True)
    for path in EVERY_TEST:
        (worktree / path).write_text("-- double\n")
    (worktree / "tests" / "run.sh").write_text("#!/bin/sh\nexit 0\n")

    stubs = directory / "stubs"
    stubs.mkdir()
    log = directory / "calls.log"
    for name, exit_code in (("lua5.2", lua_exit), ("lua5.4", lua_exit), ("gateslot", gateslot_exit)):
        script = stubs / name
        script.write_text(
            "#!/bin/sh\n"
            f'printf "%s %s\\n" "{name}" "$*" >> "{log}"\n'
            f"exit {exit_code}\n"
        )
        script.chmod(0o755)
    return worktree


def run(worktree: Path, tag: str, directory: Path, cwd: Path | None = None):
    env = dict(os.environ)
    env["PATH"] = f"{directory / 'stubs'}{os.pathsep}{env['PATH']}"
    return subprocess.run(
        ["sh", str(SCRIPT), str(worktree), tag],
        cwd=str(cwd or ROOT), text=True, capture_output=True, env=env, check=False,
    )


def calls(directory: Path) -> list[str]:
    log = directory / "calls.log"
    return log.read_text().splitlines() if log.is_file() else []


class VerifyRound9LaneTests(unittest.TestCase):
    def test_consumer_tags_select_their_own_checks_under_both_interpreters(self):
        for tag, expected in CONSUMER_TESTS.items():
            with self.subTest(tag=tag), tempfile.TemporaryDirectory() as raw:
                directory = Path(raw)
                worktree = make_worktree(directory)
                result = run(worktree, tag, directory)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                recorded = calls(directory)
                for path in expected:
                    self.assertIn(f"lua5.2 {path}", recorded)
                    self.assertIn(f"lua5.4 {path}", recorded)
                self.assertEqual(len(recorded), 2 * len(expected), recorded)
                self.assertNotIn("gateslot", "".join(recorded))
                self.assertIn(f"ran {2 * len(expected)} check(s)", result.stdout)

    def test_a_consumer_tag_never_runs_the_whole_suite(self):
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            worktree = make_worktree(directory)
            run(worktree, "086_preflight_facts", directory)
            self.assertNotIn("tests/run.sh", "".join(calls(directory)))

    def test_every_other_tag_keeps_the_whole_suite(self):
        for tag in ("085_facts_producer", "088_case_importer", "anything-else"):
            with self.subTest(tag=tag), tempfile.TemporaryDirectory() as raw:
                directory = Path(raw)
                worktree = make_worktree(directory)
                result = run(worktree, tag, directory)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                recorded = "".join(calls(directory))
                self.assertIn("gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", recorded)
                self.assertNotIn("lua5.2 tests/", recorded)

    def test_a_failing_check_fails_the_verifier(self):
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            worktree = make_worktree(directory, lua_exit=1)
            result = run(worktree, "086_preflight_facts", directory)
            self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_a_failing_suite_fails_the_verifier(self):
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            worktree = make_worktree(directory, gateslot_exit=3)
            result = run(worktree, "085_facts_producer", directory)
            self.assertEqual(result.returncode, 3, result.stdout + result.stderr)

    def test_it_runs_inside_the_named_worktree(self):
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            worktree = make_worktree(directory)
            #A test present only in the worktree proves the script changed directory: the repository root
            #holds no tests/test_plan_quality_facts.lua yet.
            result = run(worktree, "087_planner_facts", directory, cwd=Path(raw))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_arguments_are_refused(self):
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            worktree = make_worktree(directory)
            env = dict(os.environ)
            env["PATH"] = f"{directory / 'stubs'}{os.pathsep}{env['PATH']}"
            for argv in ([], [str(worktree)], [str(worktree), ""], ["", "086_preflight_facts"]):
                with self.subTest(argv=argv):
                    result = subprocess.run(
                        ["sh", str(SCRIPT), *argv], cwd=str(ROOT), text=True,
                        capture_output=True, env=env, check=False,
                    )
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)

    def test_a_missing_worktree_is_refused(self):
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            make_worktree(directory)
            result = run(directory / "absent", "086_preflight_facts", directory)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)

    def test_a_missing_selected_test_is_refused_instead_of_selecting_nothing(self):
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            worktree = make_worktree(directory)
            (worktree / "tests" / "test_quality_policy.lua").unlink()
            result = run(worktree, "086_preflight_facts", directory)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("missing test", result.stderr)


if __name__ == "__main__":
    unittest.main()
