"""The lane verifier picks one lane's checks, and can never pick none.

Round 10 adds three things this file pins: focused Lua sets for the export lanes, a Python dispatch for the
handoff lane (the Lua loop would otherwise hand a .py file to lua5.2), and --dispatch-only, which resolves a
tag and prints its selection without executing, so spine can gate the dispatcher before a lane has written its
new test.
"""

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
ROUND10_LUA_TESTS = {
    "091_export_payload": (
        "tests/test_export_completeness.lua",
        "tests/test_export_payload.lua",
    ),
    "092_attempt_lookup": (
        "tests/test_generation_attempt_lookup.lua",
        "tests/test_generation_reload.lua",
        "tests/test_generation_record_handoff.lua",
    ),
}
ROUND11_LUA_TESTS = {
    "094_beacon_geometry": (
        "tests/test_groups.lua",
        "tests/test_beacon_coverage.lua",
    ),
    "095_validator_symmetry": (
        "tests/test_validate.lua",
        "tests/test_power_semantics.lua",
        "tests/test_validated_candidate.lua",
    ),
    "096_roboport_facts": (
        "tests/test_catalog.lua",
        "tests/test_export_payload.lua",
        "tests/test_export_completeness.lua",
    ),
    "097_search_truth": (
        "tests/test_search.lua",
        "tests/test_search_budget.lua",
        "tests/test_search_allowance.lua",
        "tests/test_generation_reload.lua",
        "tests/test_generation_attempt_lookup.lua",
        "tests/test_blueprint_pipeline.lua",
        "tests/test_external_ports.lua",
        "tests/test_locale_keys.lua",
    ),
}
ROUND11_PYTHON_TAGS = {
    "098_golden_truth": "tests.tools.test_capture_workflow",
    "099_release_lifecycle": "tests.tools.test_handoff",
}
PYTHON_TAG = "093_diagnostic_handoff"
PYTHON_MODULE = "tests.tools.test_handoff"
PYTHON_PATH = "tests/tools/test_handoff.py"

EVERY_TEST = sorted(
    {path for paths in CONSUMER_TESTS.values() for path in paths}
    | {path for paths in ROUND10_LUA_TESTS.values() for path in paths}
    | {path for paths in ROUND11_LUA_TESTS.values() for path in paths}
)
EVERY_PYTHON_MODULE = sorted({PYTHON_MODULE} | set(ROUND11_PYTHON_TAGS.values()))


def make_worktree(directory: Path, lua_exit: int = 0, gateslot_exit: int = 0,
                  python_exit: int = 0) -> Path:
    """A worktree whose lua, lua5.4 and gateslot are harmless doubles that record their arguments."""
    worktree = directory / "worktree"
    (worktree / "tests" / "tools").mkdir(parents=True)
    for path in EVERY_TEST:
        (worktree / path).write_text("-- double\n")
    (worktree / "tests" / "run.sh").write_text("#!/bin/sh\nexit 0\n")
    (worktree / "tests" / "tools" / "__init__.py").write_text("")
    for module in EVERY_PYTHON_MODULE:
        (worktree / (module.replace(".", "/") + ".py")).write_text("# double\n")

    stubs = directory / "stubs"
    stubs.mkdir()
    log = directory / "calls.log"
    for name, exit_code in (
        ("lua5.2", lua_exit), ("lua5.4", lua_exit),
        ("gateslot", gateslot_exit), ("python3", python_exit),
    ):
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


def dispatch_only(worktree: Path, tag: str, directory: Path):
    env = dict(os.environ)
    env["PATH"] = f"{directory / 'stubs'}{os.pathsep}{env['PATH']}"
    return subprocess.run(
        ["sh", str(SCRIPT), "--dispatch-only", str(worktree), tag],
        cwd=str(ROOT), text=True, capture_output=True, env=env, check=False,
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


class Round10DispatchTests(unittest.TestCase):
    def test_export_lane_tags_select_their_own_lua_checks(self):
        for tag, expected in ROUND10_LUA_TESTS.items():
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
                self.assertNotIn("python3", "".join(recorded))

    def test_the_handoff_lane_is_dispatched_through_python_never_lua(self):
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            worktree = make_worktree(directory)
            result = run(worktree, PYTHON_TAG, directory)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            recorded = "".join(calls(directory))
            self.assertIn(f"python3 -m unittest -v {PYTHON_MODULE}", recorded)
            #The Lua loop would have handed a .py file to an interpreter that cannot read it.
            self.assertNotIn("lua5.2", recorded)
            self.assertNotIn("lua5.4", recorded)
            self.assertNotIn("gateslot", recorded)

    def test_a_failing_python_module_fails_the_verifier(self):
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            worktree = make_worktree(directory, python_exit=1)
            result = run(worktree, PYTHON_TAG, directory)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_missing_python_module_is_refused_instead_of_selecting_nothing(self):
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            worktree = make_worktree(directory)
            (worktree / PYTHON_PATH).unlink()
            result = run(worktree, PYTHON_TAG, directory)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("missing test module", result.stderr)

    def test_dispatch_only_resolves_without_executing_anything(self):
        for tag in list(ROUND10_LUA_TESTS) + [PYTHON_TAG]:
            with self.subTest(tag=tag), tempfile.TemporaryDirectory() as raw:
                directory = Path(raw)
                worktree = make_worktree(directory)
                result = dispatch_only(worktree, tag, directory)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(calls(directory), [], "dispatch-only ran a command")
                self.assertIn("selected", result.stdout)

    def test_dispatch_only_works_before_the_lane_writes_its_test(self):
        #Spine gates this dispatcher while tests/test_export_completeness.lua does not exist yet. An ordinary
        #run refuses a missing file, and it must keep refusing; only the resolution may run early.
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            worktree = make_worktree(directory)
            (worktree / "tests" / "test_export_completeness.lua").unlink()
            resolved = dispatch_only(worktree, "091_export_payload", directory)
            self.assertEqual(resolved.returncode, 0, resolved.stdout + resolved.stderr)
            self.assertIn("tests/test_export_completeness.lua", resolved.stdout)
            executed = run(worktree, "091_export_payload", directory)
            self.assertEqual(executed.returncode, 1, executed.stdout + executed.stderr)
            self.assertIn("missing test", executed.stderr)

    def test_dispatch_only_names_the_whole_suite_for_an_unknown_tag(self):
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            worktree = make_worktree(directory)
            result = dispatch_only(worktree, "999_unknown", directory)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("dispatch=suite", result.stdout)
            self.assertEqual(calls(directory), [], "dispatch-only ran the suite")


class Round11DispatchTests(unittest.TestCase):
    """Round 11 keeps the round 10 rule: one lane, one focused set, never the whole suite."""

    def test_each_round11_lua_tag_selects_its_own_checks(self):
        for tag, expected in ROUND11_LUA_TESTS.items():
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

    def test_each_round11_python_tag_is_dispatched_through_python(self):
        for tag, module in ROUND11_PYTHON_TAGS.items():
            with self.subTest(tag=tag), tempfile.TemporaryDirectory() as raw:
                directory = Path(raw)
                worktree = make_worktree(directory)
                result = run(worktree, tag, directory)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                recorded = "".join(calls(directory))
                self.assertIn(f"python3 -m unittest -v {module}", recorded)
                self.assertNotIn("lua5.2", recorded)
                self.assertNotIn("gateslot", recorded)

    def test_no_round11_tag_ever_runs_the_whole_suite(self):
        for tag in list(ROUND11_LUA_TESTS) + list(ROUND11_PYTHON_TAGS):
            with self.subTest(tag=tag), tempfile.TemporaryDirectory() as raw:
                directory = Path(raw)
                worktree = make_worktree(directory)
                run(worktree, tag, directory)
                self.assertNotIn("tests/run.sh", "".join(calls(directory)))

    def test_the_search_lane_resolves_before_it_writes_its_mandated_test(self):
        #docs/tasks/084_search_allowance.md mandates tests/test_search_allowance.lua and it has never been
        #written. Spine gates this dispatcher before lane 097 starts, so resolution must not need the file,
        #while an ordinary run must still refuse it.
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            worktree = make_worktree(directory)
            (worktree / "tests" / "test_search_allowance.lua").unlink()
            resolved = dispatch_only(worktree, "097_search_truth", directory)
            self.assertEqual(resolved.returncode, 0, resolved.stdout + resolved.stderr)
            self.assertIn("tests/test_search_allowance.lua", resolved.stdout)
            executed = run(worktree, "097_search_truth", directory)
            self.assertEqual(executed.returncode, 1, executed.stdout + executed.stderr)
            self.assertIn("missing test", executed.stderr)


if __name__ == "__main__":
    unittest.main()
